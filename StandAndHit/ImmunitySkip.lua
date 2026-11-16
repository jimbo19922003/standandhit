local _, SH = ...
local Skip = {widths = {data = {}, commit = {}}}
SH.ImmunitySkip = Skip

local signal = SH.BinarySignal.New(Skip, "Skip if immune (bleed)", "immunity-skip", "StandAndHitImmunitySkip")
local bindings, casts, learned = {}, {}, {}
local events, candidate, mechanicalName
local learnedCount, sequence = 0, 0
local MAX_CASTS, MAX_LEARNED = 8, 128
local SENT_WINDOW, CAST_WINDOW = 0.75, 30
-- Client 1.60.1 reports target UNIT_COMBAT IMMUNE immediately after player
-- SUCCEEDED, but supplies no caster or spell ID on IMMUNE. This 100 ms window
-- is deliberately a timing heuristic, not proof of which spell was immune.
local IMPACT_WINDOW = 0.10

Skip.READ_SNIPPET = [[
    self:SetAttribute("sh-immunity-skip", nil)
    local index, unit = ...
    if rawtype(index) ~= "number" or index < 1 or index > 32 or index % 1 ~= 0 then return false end
    if rawtype(unit) ~= "string" or unit == "" or unit == "none" then return false end
]] .. SH.BinarySignal.Reader("immunity-skip", "sh-immunity-skip", "RefreshImmunitySkip", "phase, index, unit")

local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function text(value)
    return public(value) and type(value) == "string" and value ~= ""
end
local function integer(value)
    return public(value) and type(value) == "number" and value > 0
        and value < math.huge and value % 1 == 0
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local function now()
    local value = call(GetTime)
    if public(value) and type(value) == "number" and value >= 0 and value < math.huge then return value end
end
local function guidOf(unit)
    if not text(unit) or unit == "none" then return nil end
    local guid = call(UnitGUID, unit)
    if text(guid) then return guid end
end
local function sameRecipient(attempt)
    return guidOf(attempt.unit) == attempt.guid
end

-- Active bleed families verified against the cached 1.60.1.70450 spell data.
-- Rank-name lookup below also recognizes localized higher ranks of each family.
-- Pounce is excluded: its active spell is a stun that triggers a separate bleed.
local bleedIDs = {
    [772] = true, [6546] = true, [6547] = true, [6548] = true, [11572] = true, [11573] = true, [11574] = true,
    [1079] = true, [9492] = true, [9493] = true, [9752] = true, [9894] = true, [9896] = true,
    [1822] = true, [1823] = true, [1824] = true, [9904] = true,
    [703] = true, [8631] = true, [8632] = true, [8633] = true, [11289] = true, [11290] = true,
    [462724] = true, [462726] = true, [462727] = true, [462728] = true, [462729] = true, [462730] = true,
    [1943] = true, [8639] = true, [8640] = true, [11273] = true, [11274] = true, [11275] = true,
    [414644] = true, [1235826] = true, [1235827] = true,
}
local bleedBases = {772, 1079, 1822, 703, 1943, 414644}
local function spellName(value)
    local info = call(C_Spell and C_Spell.GetSpellInfo, value)
    if public(info) and type(info) == "table" and text(info.name) then return info.name end
    local name = call(GetSpellInfo, value)
    if text(name) then return name end
end
local function isMechanical(unit)
    local name, id = call(UnitCreatureType, unit)
    -- UnitCreatureType's second return is the CreatureType ID, not pet type.
    if integer(id) then return id == 9 end
    return text(name) and mechanicalName ~= nil and name == mechanicalName
end
local function clear()
    candidate, casts, learned, learnedCount, sequence = nil, {}, {}, 0, 0
end
local function prune(timestamp)
    if candidate and (timestamp - candidate.at > SENT_WINDOW or not sameRecipient(candidate)) then candidate = nil end
    for id, attempt in pairs(casts) do
        local expires = attempt.success and attempt.success + IMPACT_WINDOW or attempt.at + CAST_WINDOW
        if timestamp > expires or not sameRecipient(attempt) then casts[id] = nil end
    end
end
local function remember(guid, spell)
    if learned[guid] and learned[guid][spell] then return end
    if learnedCount >= MAX_LEARNED then
        local oldestGUID, oldestSpell, oldest
        for target, spells in pairs(learned) do
            for id, age in pairs(spells) do
                if not oldest or age < oldest then oldestGUID, oldestSpell, oldest = target, id, age end
            end
        end
        learned[oldestGUID][oldestSpell] = nil
        if not next(learned[oldestGUID]) then learned[oldestGUID] = nil end
        learnedCount = learnedCount - 1
    end
    sequence = sequence + 1
    learned[guid] = learned[guid] or {}
    learned[guid][spell], learnedCount = sequence, learnedCount + 1
end
local function dropState(state)
    if candidate and candidate.state == state then candidate = nil end
    for id, attempt in pairs(casts) do if attempt.state == state then casts[id] = nil end end
end
local function dropUnit(prefix)
    if candidate and candidate.unit:sub(1, #prefix) == prefix then candidate = nil end
    for id, attempt in pairs(casts) do
        if attempt.unit:sub(1, #prefix) == prefix then casts[id] = nil end
    end
end
local function dropSuccesses()
    for id, attempt in pairs(casts) do if attempt.success then casts[id] = nil end end
end
local function onEvent(_, event, unit, arg2, arg3, arg4)
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then clear(); return end
    if event == "PLAYER_TARGET_CHANGED" then dropUnit("target"); return end
    if event == "PLAYER_FOCUS_CHANGED" then dropUnit("focus"); return end
    if event == "UPDATE_MOUSEOVER_UNIT" then dropUnit("mouseover"); return end
    if event == "GROUP_ROSTER_UPDATE" then dropUnit("party"); dropUnit("raid"); return end
    local timestamp = now()
    if not timestamp then return end
    prune(timestamp)
    if event == "UNIT_COMBAT" then
        if not text(unit) or not text(arg2) then return end
        local guid = guidOf(unit)
        if not guid then return end
        local match, ambiguous
        for _, attempt in pairs(casts) do
            if attempt.success and attempt.guid == guid then
                if match then ambiguous = true else match = attempt end
            end
        end
        if not match then return end
        if arg2 == "IMMUNE" and not ambiguous then
            -- A recognized bleed's immunity applies to the checked bleed rules
            -- on this enemy. Other spells remain exact-ID observations.
            remember(guid, match.rule.bleed and "bleed" or match.spell)
        end
        -- Hybrid bleeds such as Rake can deal direct damage before the bleed
        -- reports IMMUNE. WOUND is not immunity evidence and leaves the short
        -- window open; an explicit avoidance/failure closes it.
        if arg2 == "IMMUNE" or arg2 == "PARRY" or arg2 == "DODGE" or arg2 == "MISS"
            or arg2 == "RESIST" or arg2 == "EVADE" then
            for id, attempt in pairs(casts) do
                if attempt.success and attempt.guid == guid then casts[id] = nil end
            end
        end
        return
    end
    if not text(unit) then
        if event == "UNIT_SPELLCAST_SUCCEEDED" then dropSuccesses() end
        if event == "UNIT_SPELLCAST_SENT" then candidate = nil end
        return
    end
    if unit ~= "player" then return end
    local sent = event == "UNIT_SPELLCAST_SENT"
    local castID, spell
    if sent then castID, spell = arg3, arg4 else castID, spell = arg2, arg3 end
    if not text(castID) or not integer(spell) then
        if event == "UNIT_SPELLCAST_SUCCEEDED" then dropSuccesses() end
        if sent then candidate = nil end
        return
    end
    if sent then
        local attempt = candidate
        candidate = nil
        if not attempt or not attempt.rule.ids[spell] then return end
        if casts[castID] then return end
        -- Retain earlier accepted casts while a repeated keypress is rejected.
        -- SENT is tied to this dispatch; START alone never proves immunity.
        local count, oldestID, oldest = 0
        for id, active in pairs(casts) do
            count = count + 1
            if not oldest or active.at < oldest then oldestID, oldest = id, active.at end
        end
        if count >= MAX_CASTS then casts[oldestID] = nil end
        attempt.spell, attempt.cast = spell, castID
        casts[castID] = attempt
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local attempt = casts[castID]
        if not attempt or attempt.spell ~= spell then
            -- Another successful player cast makes an unlabelled impact unsafe
            -- to assign to an earlier successful cast.
            dropSuccesses()
            return
        end
        if not attempt.success then attempt.success = timestamp end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local attempt = casts[castID]
        if attempt and attempt.spell == spell then casts[castID] = nil end
    end
end
local function startEvents()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", onEvent)
    end
    for _, event in ipairs({"UNIT_COMBAT", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE"}) do events:RegisterEvent(event) end
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED"}) do events:RegisterUnitEvent(event, "player") end
end
local function prepare(button, rules)
    signal.Outside()
    if type(issecretvalue) ~= "function" then error("This client cannot check spell immunity.", 0) end
    local names, spells = {}, {}
    for _, id in ipairs(bleedBases) do
        local name = spellName(id)
        if name then names[name] = true end
    end
    local info = call(C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo, 9)
    mechanicalName = public(info) and type(info) == "table" and text(info.name) and info.name or nil
    for index, row in ipairs(rules) do
        if index <= 32 and row.skipIfImmune == true and integer(row.spellID) then
            local ids = {[row.spellID] = true}
            if text(row.spell) and SH.SpellRanks and type(SH.SpellRanks.GetChoices) == "function" then
                for _, rank in ipairs(SH.SpellRanks.GetChoices(row.spell)) do
                    if integer(rank.id) then ids[rank.id] = true end
                end
            end
            local bleed = bleedIDs[row.spellID] or names[spellName(row.spellID)] or false
            spells[index] = {ids = ids, bleed = bleed == true}
        end
    end
    if not next(spells) then
        local ok, reason = Skip:Release(button)
        if not ok then error(reason, 0) end
        return
    end
    if not next(bindings) or not Skip.calibrated or not Skip.dataFrame:IsShown() or not Skip.commitFrame:IsShown() then signal.Prepare() end
    signal.Attach(button)
    if not next(bindings) then startEvents() end
    if bindings[button] then dropState(bindings[button]) end
    bindings[button] = {spells = spells}
end
function Skip:Prepare(button, rules)
    local ok, reason = pcall(prepare, button, rules)
    if not ok and not next(bindings) and not InCombatLockdown() then
        if events then events:UnregisterAllEvents() end
        pcall(signal.Hide)
    end
    return ok, reason
end
function Skip:Release(button)
    if not bindings[button] then return true end
    if InCombatLockdown() then return false, "Leave combat to change Skip if immune (bleed)." end
    dropState(bindings[button])
    bindings[button] = nil
    if not next(bindings) then
        events:UnregisterAllEvents()
        clear()
        return pcall(signal.Hide)
    end
    return true
end
function Skip:Begin(button, index, unit)
    candidate = nil
    local timestamp = now()
    if not timestamp then return end
    prune(timestamp)
    local state = bindings[button]
    if not state or not integer(index) or not state.spells[index] then return end
    local guid = guidOf(unit)
    if not guid then return end
    candidate = {state = state, rule = state.spells[index], unit = unit, guid = guid, at = timestamp}
end
function Skip:Refresh(button, phase, index, unit)
    local state = bindings[button]
    if not state or not integer(index) or not state.spells[index] or not text(unit) or unit == "none" then return false end
    local rule, skip = state.spells[index], false
    if rule.bleed and isMechanical(unit) then skip = true end
    local guid = guidOf(unit)
    if not skip and guid and learned[guid] then
        if rule.bleed and learned[guid].bleed then skip = true end
        for id in pairs(rule.ids) do if learned[guid][id] then skip = true; break end end
    end
    return pcall(signal.Publish, skip, phase)
end

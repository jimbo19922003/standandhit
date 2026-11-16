local _, SH = ...
local Skip = {widths = {data = {}, commit = {}}}
SH.PositionSkip = Skip

local signal = SH.BinarySignal.New(Skip, "Require being behind target", "position-skip", "StandAndHitPositionSkip")
local bindings, errorIDs, reasons = {}, {}, {}
local events, pending, logReader, comparisonReady
local MAX_REPLY = 0.75
local ERROR_PAIR = 0.15

Skip.READ_SNIPPET = [[
    self:SetAttribute("sh-position-skip", nil)
    local index = ...
    if rawtype(index) ~= "number" or index < 1 or index > 32 or index % 1 ~= 0 then return false end
]] .. SH.BinarySignal.Reader("position-skip", "sh-position-skip", "RefreshPositionSkip", "phase, index")

local function public(value)
    return not issecretvalue(value)
end

local function guidOf(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not public(guid) then return nil, true end
    if type(guid) == "string" and guid ~= "" then return guid end
end

local function eventTrackedUnit(unit)
    return unit == "target" or unit == "player" or unit == "focus" or unit == "mouseover"
        or unit:match("^party[1-4]$") ~= nil
end

local function sameRecipient(attempt)
    -- The ordinary target/focus/party tokens also have change events when a
    -- GUID is restricted. For a composite/custom token require a readable ID.
    if attempt.guid then
        local current, restricted = guidOf(attempt.unit)
        if not restricted then return current == attempt.guid end
    end
    return eventTrackedUnit(attempt.unit)
end

local function resetTargets()
    pending = nil
    for _, state in pairs(bindings) do state.skip = nil end
end

local function comparisonStrength()
    if C_Intl and type(C_Intl.CompareStrings) == "function" and Enum and Enum.CollationStrength then
        return Enum.CollationStrength.Identical
    end
end

local function positional(errorType, message)
    local kind = public(errorType) and errorIDs[errorType]
    if kind == "relative" then return kind end
    if public(message) then return reasons[message] or kind end
    local strength = comparisonStrength()
    if strength then
        -- Ask WoW to compare the full localized message. A secret comparison
        -- result can use the same native measurement used by other combat rules.
        for text, category in pairs(reasons) do
            if category == "relative" then
                local ok, result = pcall(C_Intl.CompareStrings, message, text, strength)
                if ok then
                    if public(result) then
                        if result == 0 then return category end
                    elseif comparisonReady and SH.TotemSignal:IsComparisonEqual(result) then
                        return category
                    end
                end
            end
        end
    end
    return kind
end

local function addReason(message, kind)
    if type(message) ~= "string" or message == "" then return end
    reasons[message] = kind
    -- Match the complete localized wrapper as well as the bare reason.
    if type(ERR_SPELL_FAILED_S) == "string" and ERR_SPELL_FAILED_S:find("%s", 1, true) then
        local ok, wrapped = pcall(string.format, ERR_SPELL_FAILED_S, message)
        if ok then reasons[wrapped] = kind end
    end
end

local function initializeErrors()
    -- Some spell failures share the generic ERR_SPELL_FAILED_S type. Match
    -- its localized reason exactly. Only dedicated types qualify on ID alone.
    -- An auto-attack can raise this general facing error too, so an
    -- asynchronous report needs a matching spell failure before it counts.
    if type(LE_GAME_ERR_BADATTACKFACING) == "number" then errorIDs[LE_GAME_ERR_BADATTACKFACING] = "facing" end
    addReason(ERR_BADATTACKFACING, "facing")
    for _, name in ipairs({"SPELL_FAILED_NOT_BEHIND", "SPELL_FAILED_NOT_INFRONT",
        "SPELL_FAILED_UNIT_NOT_BEHIND", "SPELL_FAILED_UNIT_NOT_INFRONT"}) do
        local id = _G["LE_GAME_ERR_" .. name]
        if type(id) == "number" then errorIDs[id] = "relative" end
        addReason(_G["ERR_" .. name], "relative")
        addReason(_G[name], "relative")
    end
end

local function reject(attempt)
    if sameRecipient(attempt) then attempt.state.skip = attempt end
end

local function accept(attempt)
    if attempt.state.skip == attempt then attempt.state.skip = nil end
    pending = nil
end

local function logAvailable()
    if not C_CombatLog or type(C_CombatLog.IsCombatLogRestricted) ~= "function" then return false end
    local ok, restricted = pcall(C_CombatLog.IsCombatLogRestricted)
    return ok and public(restricted) and restricted == false
end

local function onEvent(_, event, arg1, arg2, arg3, arg4)
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then resetTargets(); return end
    if event == "PLAYER_FOCUS_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "GROUP_ROSTER_UPDATE" then
        -- Leave a target-bound skip alone when someone simply moves the mouse.
        local prefix = event == "PLAYER_FOCUS_CHANGED" and "focus" or event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or "party"
        if pending and pending.unit:sub(1, #prefix) == prefix then pending = nil end
        for _, state in pairs(bindings) do
            if state.skip and state.skip.unit:sub(1, #prefix) == prefix then state.skip = nil end
        end
        return
    end
    local attempt = pending
    if not attempt then return end
    local acceptedCast = event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_SUCCEEDED"
    local now = GetTime()
    if now - attempt.at > MAX_REPLY then
        pending = nil
        return
    end
    if event == "UI_ERROR_MESSAGE" then
        local kind = positional(arg1, arg2)
        -- This UI event carries no cast ID. Unrelated messages can arrive
        -- either side of Backstab's actual rejection.
        if not kind then return end
        -- Backstab can report only the positional error on a later frame.
        -- This attempt belongs to the most recent dispatch, has a short
        -- response window, and is invalidated on recipient or cast changes.
        if attempt.inside or kind == "relative" then reject(attempt)
        elseif attempt.cast then
            attempt.reasonAt = now
            if attempt.failedAt and now - attempt.failedAt <= ERROR_PAIR then reject(attempt) end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not logAvailable() then return end
        local ok, _, kind, _, source, _, _, _, dest, _, _, _, spell, _, _, failure = pcall(logReader)
        if not ok or not public(kind) or kind ~= "SPELL_CAST_FAILED" or not public(spell) or not attempt.ids[spell] then return end
        if not public(source) or type(source) ~= "string" or source ~= guidOf("player") then return end
        if not public(dest) or (dest and attempt.guid ~= dest) then return end
        if positional(nil, failure) then reject(attempt) else accept(attempt) end
    elseif not public(arg1) or arg1 == "player" then
        -- All spellcast events here are registered for the player alone.
        local sent = event == "UNIT_SPELLCAST_SENT"
        local spell, cast
        if sent then spell, cast = arg4, arg3 else spell, cast = arg3, arg2 end
        if public(spell) and spell ~= nil and not attempt.ids[spell] then
            if sent then accept(attempt) end
            return
        end
        local castID = public(cast) and type(cast) == "string" and cast ~= "" and cast
        if sent then
            if attempt.sent then
                if not castID or castID ~= attempt.cast then accept(attempt) end
                return
            end
            attempt.sent, attempt.cast = true, castID
        elseif attempt.cast and castID and castID ~= attempt.cast then
            -- Another cast of the same spell makes an unlabelled error ambiguous.
            accept(attempt)
        elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
            if not attempt.cast or castID ~= attempt.cast then return end
            attempt.failedAt = now
            if attempt.reasonAt and now - attempt.reasonAt <= ERROR_PAIR then reject(attempt) end
        elseif acceptedCast then
            accept(attempt)
        end
    end
end

local function startEvents()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", onEvent)
        initializeErrors()
    end
    for _, event in ipairs({"UI_ERROR_MESSAGE", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD"}) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET"}) do
        events:RegisterUnitEvent(event, "player")
    end
    if logAvailable() then
        logReader = C_CombatLog.GetCurrentEventInfo or CombatLogGetCurrentEventInfo
        if type(logReader) == "function" then pcall(events.RegisterEvent, events, "COMBAT_LOG_EVENT_UNFILTERED") end
    end
end

local function prepare(button, rules)
    signal.Outside()
    local spells = {}
    for index, row in ipairs(rules) do
        if row.skipIfNotCasted then
            local ids = {[row.spellID] = true}
            if type(row.spell) == "string" and SH.SpellRanks then
                -- A cast by name uses the highest learned rank, whose event ID
                -- can differ from the spell ID returned for the name.
                for _, rank in ipairs(SH.SpellRanks.GetChoices(row.spell)) do
                    if rank.id then ids[rank.id] = true end
                end
            end
            spells[index] = ids
        end
    end
    if not next(spells) then Skip:Release(button); return end
    if type(issecretvalue) ~= "function" then error("This client cannot check positional cast failures.", 0) end
    if not next(bindings) or not Skip.calibrated or not Skip.dataFrame:IsShown() or not Skip.commitFrame:IsShown() then signal.Prepare() end
    signal.Attach(button)
    if not next(bindings) then
        startEvents()
        if comparisonStrength() and SH.TotemSignal and SH.TotemSignal.IsComparisonEqual then
            local ok, acquired = pcall(SH.TotemSignal.Acquire, SH.TotemSignal, Skip, "comparison")
            comparisonReady = ok and acquired
        end
    end
    if pending and pending.state == bindings[button] then pending = nil end
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
    if InCombatLockdown() then return false, "Leave combat to change Require being behind target." end
    if pending and pending.state == bindings[button] then pending = nil end
    bindings[button] = nil
    if not next(bindings) then
        events:UnregisterAllEvents()
        if comparisonReady then SH.TotemSignal:Release(Skip); comparisonReady = nil end
        return pcall(signal.Hide)
    end
    return true
end

function Skip:Begin(button, index, unit)
    pending = nil
    local state = bindings[button]
    if not state or not public(index) or not state.spells[index] or not public(unit)
        or type(unit) ~= "string" or unit == "none" or unit == "" then return end
    local guid = guidOf(unit)
    if not guid and not eventTrackedUnit(unit) then return end
    pending = {state = state, index = index, ids = state.spells[index], unit = unit, guid = guid,
        at = GetTime(), inside = true}
end

function Skip:End(button)
    local attempt = pending
    if not attempt or attempt.state ~= bindings[button] then return end
    attempt.inside = false
end

function Skip:Consume(button)
    pending = nil
    if bindings[button] then bindings[button].skip = nil end
end

function Skip:Refresh(button, phase, index)
    local state = bindings[button]
    if not state or not public(index) or not state.spells[index] then return false end
    local attempt = state.skip
    if attempt and not sameRecipient(attempt) then state.skip, attempt = nil, nil end
    return pcall(signal.Publish, attempt ~= nil and attempt.index == index, phase)
end

-- Observe the pending skip without consuming it or clearing its recipient.
function Skip:Preview(button, index)
    local state = bindings[button]
    if not state or not public(index) or not state.spells[index] then return nil, "Position condition is not prepared" end
    local attempt = state.skip
    return attempt ~= nil and sameRecipient(attempt) and attempt.index == index
end

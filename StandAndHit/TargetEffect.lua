local _, SH = ...

local Effect = {widths = {data = {}, commit = {}}}
SH.TargetEffect = Effect
local signal = SH.BinarySignal.New(Effect, "Target debuff", "target-effect", "StandAndHitTargetEffect")
local bindings = {}

Effect.READ_SNIPPET = [[
    self:SetAttribute("sh-target-effect-present", nil)
    local key = ...
    if rawtype(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    if SecureCmdOptionParse("[@target,exists,harm,nodead]1") ~= "1" then return false end
]] .. SH.BinarySignal.Reader("target-effect", "sh-target-effect-present", "RefreshTargetEffect", "phase, key")

function Effect.IsCurseGroup(entry)
    return entry and entry.baseID == 1319652 -- Curses in Forever's Tracked Buffs
end

function Effect.ResolveCurse(entry, input, spellName)
    if not Effect.IsCurseGroup(entry) then return nil end
    local text = SH.Model.Trim(input)
    local id, lower = tonumber(text), text:lower()
    if id and entry.linkedIDs[id] then
        local name = spellName(id)
        return {name = name or ("spell ID " .. id), ids = {[id] = true}, spellID = id,
            unit = "target", skipNameLookup = not name}
    end
    local ids, name, representative = {}
    for member in pairs(entry.linkedIDs) do
        local memberName = spellName(member)
        if not id and memberName and memberName:lower() == lower then
            ids[member], name = true, memberName
            if not representative or member < representative then representative = member end
        end
    end
    if not name then
        return nil, "enter the name or spell ID of one curse listed under Curses."
    end
    return {name = name, ids = ids, spellID = representative, unit = "target"}
end

local function directAvailable(record)
    if not C_Secrets or type(C_Secrets.ShouldSpellAuraBeSecret) ~= "function" or not C_UnitAuras then return false end
    return record.skipNameLookup and type(C_UnitAuras.GetUnitAuras) == "function"
        or not record.skipNameLookup and type(C_UnitAuras.GetAuraDataBySpellName) == "function"
end

local function queryable(value)
    local restricted = C_Secrets.ShouldSpellAuraBeSecret(value)
    return not issecretvalue(restricted) and restricted == false
end

local function readableTable(value)
    return not issecretvalue(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function readDirect(record)
    local exists = UnitExists("target")
    if issecretvalue(exists) then return nil end
    if not exists then return false end -- Can verify an empty group at Prepare.
    local visible = UnitIsVisible("target")
    if issecretvalue(visible) or visible ~= true or not directAvailable(record) then return nil end
    for id in pairs(record.ids) do
        if not queryable(id) then return nil end
    end
    if record.skipNameLookup then
        local auras = C_UnitAuras.GetUnitAuras("target", "HARMFUL|PLAYER")
        if not readableTable(auras) then return nil end
        local complete = true
        for _, aura in ipairs(auras) do
            if readableTable(aura) and not issecretvalue(aura.spellId) and type(aura.spellId) == "number" then
                if record.ids[aura.spellId] then return true end
            else
                complete = false
            end
        end
        if complete then return false end
        return nil
    end
    if not queryable(record.name) then return nil end
    local aura = C_UnitAuras.GetAuraDataBySpellName("target", record.name, "HARMFUL|PLAYER")
    if issecretvalue(aura) then return nil end
    if aura == nil then return false end
    if readableTable(aura) then
        local id = aura.spellId
        if not issecretvalue(id) and type(id) == "number" and record.ids[id] then return true end
    end
end

local function release(button)
    signal.Outside()
    if SH.TotemBuffSlot then SH.TotemBuffSlot:Release(bindings[button]) end
    bindings[button] = nil
    if not next(bindings) then signal.Hide() end
end

function Effect:Release(button)
    if not bindings[button] then return true end
    return pcall(release, button)
end

local function prepare(button, effects)
    signal.Outside()
    if type(issecretvalue) ~= "function" or type(UnitIsVisible) ~= "function" then
        error("This client cannot check individual target debuffs.", 0)
    end
    -- The same button can own player-buff observers, so keep target-effect
    -- ownership separate even when the underlying groups share a pool.
    local binding = {records = {}}
    if not next(bindings) or not Effect.calibrated then signal.Prepare() end
    signal.Attach(button)
    local old = bindings[button]
    if old and SH.TotemBuffSlot then SH.TotemBuffSlot:Release(old) end
    bindings[button] = binding
    for key, effect in ipairs(effects) do
        local record = {name = effect.name, ids = effect.ids, unit = "target", skipNameLookup = effect.skipNameLookup}
        binding.records[key] = record
        local layout = SH.TotemBuffSlot and SH.TotemBuffSlot:Acquire(record, binding, readDirect)
        if not layout and not directAvailable(record) then
            error("The target debuff " .. record.name .. " could not be checked on this client.", 0)
        end
    end
end

function Effect:Prepare(button, effects)
    local ok, reason = pcall(prepare, button, effects)
    if not ok and not InCombatLockdown() then
        if bindings[button] then self:Release(button)
        elseif not next(bindings) then pcall(signal.Hide) end
    end
    return ok, reason
end

local function refresh(button, phase, key)
    local binding = bindings[button]
    local record = binding and binding.records[key]
    if not record then return false end
    local ok, present = pcall(readDirect, record)
    if ok and present ~= nil then
        if not InCombatLockdown() and SH.TotemBuffSlot then
            SH.TotemBuffSlot:ObserveDirect(record, present)
        end
    elseif SH.TotemBuffSlot then
        present = SH.TotemBuffSlot:Read(record)
    else
        present = nil
    end
    if type(present) ~= "boolean" then return false end
    signal.Publish(present, phase)
    return true
end

function Effect:Refresh(button, phase, key)
    local ok, result = pcall(refresh, button, phase, key)
    if not ok then return false, result end
    return result
end

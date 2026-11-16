local _, SH = ...

local Buff = {widths = {data = {}, commit = {}}}
SH.PlayerBuff = Buff
local signal = SH.BinarySignal.New(Buff, "Player buff", "buff", "StandAndHitPlayerBuff")
local bindings = {}

Buff.READ_SNIPPET = [[
    self:SetAttribute("sh-buff-present", nil)
    local key = ...
    if rawtype(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
]] .. SH.BinarySignal.Reader("buff", "sh-buff-present", "RefreshPlayerBuff", "phase, key")

local function positiveInteger(value)
    return type(value) == "number" and value > 0 and value % 1 == 0
end

local function canQuery(identifier)
    local ok, restricted = pcall(signal.Call, "ShouldSpellAuraBeSecret", C_Secrets.ShouldSpellAuraBeSecret, identifier)
    return ok and not issecretvalue(restricted) and restricted == false
end

local function readableTable(value)
    return not issecretvalue(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function byName(buff, allRanksReadable)
    local filter = buff.groupedPlayerBuff and "HELPFUL|PLAYER" or "HELPFUL"
    local aura = signal.Call("GetAuraDataBySpellName", C_UnitAuras.GetAuraDataBySpellName, "player", buff.name, filter)
    if issecretvalue(aura) then return nil end
    if aura == nil then
        -- This API can return nil for a restricted rank even when the buff is active.
        if allRanksReadable then return false end
    elseif readableTable(aura) then
        if buff.groupedPlayerBuff or buff.exactIDs then
            -- Totem buffs accept any caster; grouped class buffs require self.
            -- Check IDs too: a proc or another effect can share the buff's name.
            local id, source = aura.spellId, aura.sourceUnit
            if buff.groupedPlayerBuff and not issecretvalue(source) and source ~= nil and source ~= "player" then return nil end
            if not issecretvalue(id) and buff.ids[id] then return true end
            return nil
        end
        local name = aura.name
        -- The native query already filtered by exact name and HELPFUL. A masked
        -- name inside the returned record does not invalidate that match.
        if issecretvalue(name) or name == buff.name then return true end
    end
end

local function byRank(buff)
    local lookup = C_UnitAuras.GetUnitAuraBySpellID
    if type(lookup) ~= "function" then return nil end
    local complete = true
    for id in pairs(buff.ids) do
        if canQuery(id) then
            local ok, aura = pcall(signal.Call, "GetUnitAuraBySpellID", lookup, "player", id)
            if ok and readableTable(aura) then
                local foundID = aura.spellId
                if issecretvalue(foundID) or foundID == id then return true end
            end
            if not ok or issecretvalue(aura) or aura ~= nil then complete = false end
        else
            complete = false
        end
    end
    if complete then return false end
end

local function scanPlayerBuffs(buff)
    if type(C_UnitAuras.GetUnitAuras) ~= "function" then return nil end
    -- No count limit or ownership/raid filter. A different Shaman's buff counts.
    local auras = signal.Call("GetUnitAuras", C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
    if not readableTable(auras) then return nil end
    local complete = true
    for _, aura in ipairs(auras) do
        if readableTable(aura) then
            local id, name = aura.spellId, aura.name
            local hasID = not issecretvalue(id) and positiveInteger(id)
            local hasName = not issecretvalue(name) and type(name) == "string" and name ~= ""
            if (hasID and buff.ids[id]) or (not buff.exactIDs and hasName and name == buff.name) then return true end
            if not hasID and (not hasName or (buff.exactIDs and name == buff.name)) then complete = false end
        else
            complete = false
        end
    end
    if complete then return false end
end

local function exactSelfBuff(aura, id)
    if not readableTable(aura) then return nil end
    local foundID, helpful, harmful, source = aura.spellId, aura.isHelpful, aura.isHarmful, aura.sourceUnit
    if issecretvalue(foundID) or foundID ~= id then return nil end
    if not issecretvalue(helpful) and helpful == false then return false end
    if not issecretvalue(harmful) and harmful == true then return false end
    if not issecretvalue(source) and source ~= nil and source ~= "player" then return false end
    if not issecretvalue(helpful) and helpful == true and not issecretvalue(source) and source == "player" then
        return true
    end
end

local function readExactSelfBuff(buff)
    local id, lookup = buff.memberID, C_UnitAuras.GetUnitAuraBySpellID
    local queryable = canQuery(id)
    if type(lookup) == "function" and queryable then
        local ok, aura = pcall(signal.Call, "GetUnitAuraBySpellID", lookup, "player", id)
        if ok and not issecretvalue(aura) then
            if aura == nil then return false, "exact ID" end
            -- The ID lookup has no HELPFUL or caster filter. A harmful or
            -- foreign instance is not proof that our own buff is absent.
            if exactSelfBuff(aura, id) == true then return true, "exact ID" end
        end
    end
    if type(C_UnitAuras.GetUnitAuras) ~= "function" then return nil end
    local ok, auras = pcall(signal.Call, "GetUnitAuras", C_UnitAuras.GetUnitAuras, "player", "HELPFUL|PLAYER")
    if not ok or not readableTable(auras) then return nil end
    local complete = true
    for _, aura in ipairs(auras) do
        if not readableTable(aura) then
            complete = false
        else
            local foundID = aura.spellId
            if issecretvalue(foundID) or not positiveInteger(foundID) then
                complete = false
            elseif foundID == id then
                local present = exactSelfBuff(aura, id)
                if present == true then return true, "exact buff list" end
                if present == nil then complete = false end
            end
        end
    end
    -- A restricted aura may be omitted. A readable matching ID proves
    -- presence, but an empty list cannot prove absence for that restricted ID.
    if complete and queryable then return false, "exact buff list" end
end

local function readBuff(buff, directOnly)
    local visible = signal.Call("UnitIsVisible", UnitIsVisible, "player")
    if issecretvalue(visible) or visible ~= true then return nil, "player hidden" end
    if buff.nativePlayerBuff then
        -- Ghostly Strike's dodge and stealth-free opener buffs share a name.
        -- Only the selected exact spell ID may supply this condition.
        local present, source = readExactSelfBuff(buff)
        if present ~= nil then return present, source end
        if SH.TotemBuffSlot and not directOnly then
            local ok, native, reason = pcall(SH.TotemBuffSlot.Read, SH.TotemBuffSlot, buff)
            if ok and not issecretvalue(native) and type(native) == "boolean" then return native, "aura group" end
            return nil, ok and reason or "aura group unavailable"
        end
        return nil, "selected buff unreadable"
    end
    local allRanksReadable = true
    for id in pairs(buff.ids) do
        if not canQuery(id) then allRanksReadable = false; break end
    end
    if (allRanksReadable or buff.totemBuff or buff.groupedPlayerBuff) and canQuery(buff.name) then
        local ok, present = pcall(byName, buff, allRanksReadable)
        if ok and present ~= nil then return present, "name" end
    end
    if buff.totemBuff or buff.groupedPlayerBuff then
        local groupReason
        if SH.TotemBuffSlot and not directOnly then
            local ok, present, reason = pcall(SH.TotemBuffSlot.Read, SH.TotemBuffSlot, buff)
            if ok and not issecretvalue(present) and type(present) == "boolean" then return present, "aura group" end
            groupReason = ok and reason or "aura group unavailable"
        end
        -- The totem fallbacks accept all casters. Grouped class buffs require
        -- the player as their source even when the name lookup is restricted.
        if buff.groupedPlayerBuff then return nil, groupReason or "selected buff unreadable" end
        local present = byRank(buff)
        if present ~= nil then return present, "rank" end
        local ok, scanned = pcall(scanPlayerBuffs, buff)
        if ok and scanned ~= nil then return scanned, "buff list" end
        return nil, groupReason or "buff list unreadable"
    end
    return nil, "name unreadable"
end

local function readDirect(buff)
    return readBuff(buff, true)
end

local function prepare(button, buffs)
    signal.Outside()
    if type(issecretvalue) ~= "function" or type(UnitIsVisible) ~= "function"
        or not C_Secrets or type(C_Secrets.ShouldSpellAuraBeSecret) ~= "function"
        or not C_UnitAuras then
        error("This client cannot check player buffs by name.", 0)
    end
    local records = {}
    for key, buff in pairs(buffs) do
        if not positiveInteger(key) or type(buff) ~= "table" or type(buff.name) ~= "string"
            or not buff.name:find("%S") or type(buff.ids) ~= "table" or not next(buff.ids) then
            error("Choose the buff applied to the player.", 0)
        end
        local ids, idCount = {}, 0
        for id, enabled in pairs(buff.ids) do
            if not positiveInteger(id) or enabled ~= true then error("Invalid player buff spell ID.", 0) end
            ids[id] = true
            idCount = idCount + 1
        end
        if buff.nativePlayerBuff then
            if buff.exactIDs ~= true or (buff.memberID ~= 14278 and buff.memberID ~= 1329326)
                or not ids[buff.memberID] or idCount ~= 1 then
                error("Choose one exact Ghostly Strike player buff spell ID.", 0)
            end
        elseif type(C_UnitAuras.GetAuraDataBySpellName) ~= "function" then
            error("This client cannot check player buffs by name.", 0)
        end
        local record = {name = buff.name, ids = ids, totemBuff = buff.totemBuff == true,
            groupedPlayerBuff = buff.groupedPlayerBuff == true, exactIDs = buff.exactIDs == true,
            nativePlayerBuff = buff.nativePlayerBuff == true, memberID = buff.memberID}
        local ok, present = pcall(readBuff, record)
        if not ok or present == nil then
            error(("The player buff %s could not be checked. Prepare again when your buffs are available."):format(buff.name), 0)
        end
        records[key] = record
    end
    if not next(records) then error("Choose a player buff to check.", 0) end
    signal.Prepare()
    signal.Attach(button)
    if SH.TotemBuffSlot then
        SH.TotemBuffSlot:Release(button)
        for _, record in pairs(records) do
            if record.totemBuff or record.groupedPlayerBuff or record.nativePlayerBuff then
                -- The player's normal aura lookup remains usable on clients
                -- that cannot create or verify the optional combat display.
                pcall(SH.TotemBuffSlot.Acquire, SH.TotemBuffSlot, record, button, readDirect)
            end
        end
    end
    bindings[button] = records
end

function Buff:Prepare(button, buffs)
    return pcall(prepare, button, buffs)
end

local function release(button)
    signal.Outside()
    if not bindings[button] then return end
    if SH.TotemBuffSlot then SH.TotemBuffSlot:Release(button) end
    bindings[button] = nil
    if not next(bindings) then signal.Hide() end
end

function Buff:Release(button)
    return pcall(release, button)
end

local function refresh(button, phase, key)
    local buff = bindings[button] and bindings[button][key]
    if not buff then return false end
    local present, source = readBuff(buff)
    if present == nil then return false end
    if (buff.totemBuff or buff.groupedPlayerBuff or buff.nativePlayerBuff) and source ~= "aura group" and not InCombatLockdown()
        and SH.TotemBuffSlot and SH.TotemBuffSlot.ObserveDirect then
        SH.TotemBuffSlot:ObserveDirect(buff, present)
    end
    signal.Publish(present, phase)
    return true
end

function Buff:Refresh(button, phase, key)
    local ok, result = pcall(refresh, button, phase, key)
    if not ok then return false, result end
    return result
end

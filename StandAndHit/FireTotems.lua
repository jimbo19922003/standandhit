local _, SH = ...
local Slot = {}
SH.FireTotems = Slot

-- Keep the public module and secure attribute names for existing fire rules.
local slots = {fire = FIRE_TOTEM_SLOT or 1, earth = EARTH_TOTEM_SLOT or 2,
    water = WATER_TOTEM_SLOT or 3, air = AIR_TOTEM_SLOT or 4}
local elements, casts = {}, {}
for element, slot in pairs(slots) do elements[slot], casts[element] = element, {} end
local codes = {missing = 0, searing = 1, magma = 2, other = 3}
local users, names = {}, {}
local signal = SH.BinarySignal.New(Slot, "Totem slots", "shfire-slot", "StandAndHitFireSlot")
local decoder = SH.TotemSignal
local listener
local boolOwner, comparisonOwner = {}, {}
local SETTLE = 0.75
-- Discard old placement events if the client missed a slot update.
-- A timeout never authorizes a recast.
local CAST_EVIDENCE_LIMIT = 120

local function plain(value)
    if not issecretvalue(value) then return value end
    return nil
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

local function family(id)
    id = plain(id)
    if type(id) ~= "number" or id <= 0 then return nil end
    local base = SH.TotemFamily(id)
    local element = base and SH.TotemElement(base)
    if element then
        return base == 3599 and "searing" or base == 8190 and "magma" or "other", element
    end
end

local function resetCast(element)
    local cast = casts[element]
    cast.kind, cast.at, cast.awaiting, cast.paired = nil, nil, nil, nil
end

local function resetAll()
    for element in pairs(slots) do resetCast(element) end
end

local function onEvent(_, event, unitOrSlot, _, id)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Registered for player only. Casts from the normal spell buttons
        -- count here too, including a manual swap to another learned rank.
        local kind, element = family(id)
        if kind and unitOrSlot == "player" then
            local cast = casts[element]
            cast.kind, cast.at, cast.awaiting, cast.paired = kind, GetTime(), true, false
        end
    elseif event == "PLAYER_TOTEM_UPDATE" then
        local changed = plain(unitOrSlot)
        local element = changed and elements[changed]
        if changed == nil or changed == 0 then
            resetAll()
        elseif element then
            local cast = casts[element]
            local age = cast.at and GetTime() - cast.at
            if cast.awaiting and age and age >= 0 and age <= SETTLE then
                cast.awaiting, cast.paired = false, true
            else resetCast(element) end
        end
    else
        resetAll()
    end
end

local function bool(value)
    if issecretvalue(value) then return decoder:ReadBoolean(value) end
    if type(value) == "boolean" then return value end
end

local function durationActive(slot)
    local duration = plain(call(GetTotemDuration, slot))
    if duration and type(duration.IsActive) == "function" then
        return bool(call(duration.IsActive, duration))
    end
end

local function matchesName(value, name)
    if not name then return false end
    if not issecretvalue(value) then return type(value) == "string" and value == name end
    if C_Intl and Enum and Enum.CollationStrength and Enum.CollationStrength.Identical then
        local diff = call(C_Intl.CompareStrings, value, name, Enum.CollationStrength.Identical)
        return decoder:IsComparisonEqual(diff) == true
    end
    return false
end

local function observe(element)
    local slot, cast = slots[element], casts[element]
    local ok, have, name, _, _, _, _, id = pcall(GetTotemInfo, slot)
    if not ok then have, name, id = nil, nil, nil end
    local kind = family(id)
    if not kind then
        if element == "fire" and matchesName(name, names.searing) then kind = "searing"
        elseif element == "fire" and matchesName(name, names.magma) then kind = "magma"
        elseif type(plain(id)) == "number" and id > 0 then kind = "other" end
    end
    local left = plain(call(GetTotemTimeLeft, slot))
    local active
    if type(left) == "number" and left >= 0 then
        active = left > 0
    else
        active = durationActive(slot)
    end
    local age = cast.at and GetTime() - cast.at
    local recent = age and age >= 0 and age <= SETTLE
    local haveSlot = bool(have)
    if recent and ((kind and kind ~= cast.kind) or active == false or haveSlot == false) then
        return "unknown"
    end
    -- On classic clients haveTotem can describe an unlocked slot even
    -- when its duration, spell ID and time left are zero.
    if active == false or haveSlot == false then
        resetCast(element)
        if kind or active == true then return "unknown" end
        return "missing"
    end
    if kind then
        if cast.kind and kind ~= cast.kind then resetCast(element) end
        return element == "fire" and kind or "other"
    end
    if cast.kind and age and age >= 0 and age <= CAST_EVIDENCE_LIMIT and cast.paired then
        return element == "fire" and cast.kind or "other"
    end
    if active == true then return "other" end
    return "unknown"
end

-- Both bits belong to one observation. Each RunAttribute requires a new
-- acknowledgment from the native reader. An incomplete read returns unknown.
Slot.READ_SNIPPET = [[
    local element = ...
    if element == nil then element = "fire" end
    if element ~= "fire" and element ~= "earth" and element ~= "water" and element ~= "air" then return "unknown" end
    if self:RunAttribute("shfire-read-bit", 0, element) ~= true then return "unknown" end
    local low = self:GetAttribute("shfire-bit")
    if self:RunAttribute("shfire-read-bit", 1, element) ~= true then return "unknown" end
    local high = self:GetAttribute("shfire-bit")
    if low == false and high == false then return "missing" end
    if low == true and high == false then return "searing" end
    if low == false and high == true then return "magma" end
    if low == true and high == true then return "other" end
    return "unknown"
]]

local function refresh(button, phase, bit, element)
    local binding = users[button]
    if not binding then return end
    local code, pendingElement = binding.pending, binding.element
    binding.pending, binding.element = nil, nil
    if not slots[element] then return end
    if bit == 0 then
        local ok, value = pcall(observe, element)
        if not ok then return end
        code = codes[value]
        if code and pcall(signal.Publish, code % 2 == 1, phase) then
            binding.pending, binding.element = code, element
        end
    elseif bit == 1 and code and pendingElement == element then
        pcall(signal.Publish, code >= 2, phase)
    end
end

local readBit = [[
    local bit, element = ...
    self:SetAttribute("shfire-bit", nil)
]] .. SH.BinarySignal.Reader("shfire-slot", "shfire-bit", "RefreshFireTotemsSlot", "phase, bit, element")

local function stop()
    if listener then listener:UnregisterAllEvents() end
    resetAll()
    decoder:Release(boolOwner)
    decoder:Release(comparisonOwner)
    signal.Hide()
end

local function prepare(button)
    signal.Outside()
    if type(issecretvalue) ~= "function" or type(GetTotemInfo) ~= "function" then
        error("This client cannot read the shaman totem slots.", 0)
    end
    if not next(users) or not Slot.calibrated or not Slot.dataFrame:IsShown() or not Slot.commitFrame:IsShown() then
        signal.Prepare()
    end
    if not next(users) then
        -- Exact native name comparisons and duration flags are optional.
        -- Public slot readings and observed spell casts work independently.
        decoder:Acquire(boolOwner, "cooldown")
        decoder:Acquire(comparisonOwner, "comparison")
        names.searing = plain(call(C_Spell and C_Spell.GetSpellName, 3599))
        names.magma = plain(call(C_Spell and C_Spell.GetSpellName, 8190))
        if names.searing == "" then names.searing = nil end
        if names.magma == "" then names.magma = nil end
        if not listener then
            listener = CreateFrame("Frame")
            listener:SetScript("OnEvent", onEvent)
        end
        listener:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        listener:RegisterEvent("PLAYER_TOTEM_UPDATE")
        listener:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    users[button] = {}
    signal.Attach(button)
    button.RefreshFireTotemsSlot = refresh
    button:SetAttribute("shfire-read-bit", readBit)
end

function Slot:Prepare(button)
    local ok, err = pcall(prepare, button)
    if not ok and not InCombatLockdown() then
        if users[button] then self:Release(button) elseif not next(users) then pcall(stop) end
    end
    return ok, err
end

function Slot:Release(button)
    if InCombatLockdown() then return false, "Leave combat before removing the totem conditions." end
    if not users[button] then return true end
    users[button] = nil
    button:SetAttribute("shfire-read-bit", nil)
    button:SetAttribute("shfire-bit", nil)
    button.RefreshFireTotemsSlot = nil
    if not next(users) then return pcall(stop) end
    return true
end

local _, SH = ...

-- Ordinary-Lua measurement adapters for the private readiness model. These
-- never execute a live secure snippet or write the prepared action button.
local Readers = {}
SH.ReadinessReaders = Readers

local function plain(value, label)
    if type(issecretvalue) == "function" then
        local ok, hidden = pcall(issecretvalue, value)
        if not ok or type(hidden) ~= "boolean" or hidden then
            error((label or "Reading") .. " is restricted", 0)
        end
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or type(accessible) ~= "boolean" or not accessible then
            error((label or "Reading") .. " is inaccessible", 0)
        end
    end
    return value
end
local function finite(value, label)
    value = plain(value, label)
    if type(value) ~= "number" or value ~= value or value <= -math.huge or value >= math.huge then
        error((label or "Reading") .. " is not a readable number", 0)
    end
    return value
end
local function integer(value, low, high, label)
    value = finite(value, label)
    if value % 1 ~= 0 or value < low or value > high then error((label or "Reading") .. " is invalid", 0) end
    return value
end
local function boolean(value, label)
    value = plain(value, label)
    if type(value) ~= "boolean" then error((label or "Reading") .. " is unavailable", 0) end
    return value
end
local function object(value, label)
    value = plain(value, label)
    if value == nil then error((label or "Source") .. " is unavailable", 0) end
    return value
end
local function call(frame, method, ...)
    frame = object(frame, method)
    local fn = plain(frame[method], method)
    if type(fn) ~= "function" then error(method .. " is unavailable", 0) end
    local value, reason = fn(frame, ...)
    return plain(value, method), plain(reason, method)
end
local function module(name)
    local value = object(SH[name], name)
    if type(value) ~= "table" then error(name .. " is unavailable", 0) end
    return value
end
local function shown(frame)
    if call(frame, "IsShown") ~= true then error("Prepared reader is hidden", 0) end
end
local function state(owner, readyAttribute, binary)
    local flag = binary and "calibrated" or "ready"
    if plain(owner[flag], "Reader readiness") ~= true then error("Reader has not been prepared", 0) end
    shown(owner.dataFrame); shown(owner.commitFrame)
    if readyAttribute and call(owner.commitFrame, "GetAttribute", readyAttribute) ~= true then
        error("Reader calibration is unavailable", 0)
    end
end
local function widths(owner, kind, maximum, binary)
    local result = {}
    local source
    if not binary then
        local all = object(owner.widths, "Reader calibration")
        source = object(all[kind], "Reader calibration")
    end
    for code = 0, maximum do
        local value
        if binary then value = call(owner[kind .. "Frame"], "GetAttribute", "sh-width" .. code)
        else value = source[code] end
        result[code] = finite(value, "Reader calibration")
        if result[code] <= 0 then error("Reader calibration is invalid", 0) end
    end
    return result
end
local function decode(frame, mapping, maximum)
    local value, found = finite(call(frame, "GetWidth"), "Reader width"), nil
    for code = 0, maximum do
        if math.abs(value - mapping[code]) <= 0.5 then
            if found ~= nil then error("Reader signal is ambiguous", 0) end
            found = code
        end
    end
    if found == nil then error("Reader signal is unavailable", 0) end
    return found
end
local function fresh(owner, maximum, base, readyAttribute, binary, refresh)
    state(owner, readyAttribute, binary)
    local dataWidths, commitWidths = widths(owner, "data", maximum, binary), widths(owner, "commit", maximum, binary)
    local oldCode = decode(owner.commitFrame, commitWidths, maximum)
    local phase = oldCode < base and 1 or 0
    local ok, reason = refresh(phase)
    ok, reason = plain(ok, "Reader refresh"), plain(reason, "Reader error")
    if ok ~= true then error(type(reason) == "string" and reason or "Reader could not obtain a fresh value", 0) end
    state(owner, readyAttribute, binary)
    local dataCode = decode(owner.dataFrame, dataWidths, maximum)
    local commitCode = decode(owner.commitFrame, commitWidths, maximum)
    if dataCode ~= commitCode or commitCode == oldCode or math.floor(commitCode / base) ~= phase then
        error("Reader did not acknowledge this observation", 0)
    end
    return commitCode % base
end
local function refresh(owner, ...)
    return call(owner, "Refresh", ...)
end
local function binary(owner, callback)
    return fresh(owner, 3, 2, "sh-binary-ready", true, callback) == 1
end
local function result(shadow, attribute, value)
    shadow:SetAttribute(attribute, boolean(value, attribute))
    return true, true
end
local function macroCondition(expression)
    if type(SecureCmdOptionParse) ~= "function" then error("Target condition is unavailable", 0) end
    local value = plain(SecureCmdOptionParse(expression), "Target condition")
    if value ~= nil and type(value) ~= "string" then error("Target condition is invalid", 0) end
    return value == "1"
end
local function effective(frame, key)
    local fn = plain(frame.GetEffectiveAttribute)
    if type(fn) == "function" then return plain(fn(frame, key), key) end
    if type(SecureButton_GetModifiedAttribute) == "function" then
        return plain(SecureButton_GetModifiedAttribute(frame, key), key)
    end
    return call(frame, "GetAttribute", key)
end
local function validatePing(owner, button, index)
    local bindings = object(owner.bindings, "Spell timing bindings")
    local binding = object(plain(bindings[button]), "Spell timing binding")
    local record = object(plain(binding[index]), "Spell timing record")
    if plain(record.invalid) or plain(record.pendingSource) then error("Spell timing source is unavailable", 0) end
    local source = object(record.source, "Spell timing source")
    local native = object(source.button, "Spell timing action")
    if call(native, "IsVisible") ~= true then error("Spell timing action bar is hidden", 0) end
    local id = finite(call(native, "GetID"), "Action button ID")
    local slot
    if id > 0 then
        local page = effective(native, "actionpage")
        if page == nil then
            local fn = GetActionBarPage or (C_ActionBar and C_ActionBar.GetActionBarPage)
            if type(fn) ~= "function" then error("Action bar page is unavailable", 0) end
            page = plain(fn())
        end
        slot = id + (finite(page, "Action bar page") - 1) * finite(source.barSize, "Action bar size")
    else slot = effective(native, "action") or 1 end
    slot = finite(slot, "Action slot")
    if slot ~= finite(source.slot, "Prepared action slot") then error("Spell timing action slot changed", 0) end
    if type(GetActionInfo) ~= "function" then error("Action information is unavailable", 0) end
    local kind, spellID = GetActionInfo(slot)
    if plain(kind, "Action type") ~= "spell" or plain(spellID, "Action spell") ~= finite(source.spellID, "Prepared spell") then
        error("Spell timing action changed", 0)
    end
end
local function petState(key)
    local pet = module("PetAttack")
    if plain(pet.ready) ~= true then error("Pet attack is not prepared", 0) end
    if key <= -1 and key >= -10 then return boolean(call(pet, "IsAttackSlot", -key), "Pet action") end
    -- PetAttack:IsOnTarget records a successful order. Preview only observes.
    if type(GetTime) ~= "function" then error("Pet order time is unavailable", 0) end
    if finite(GetTime(), "Current time") < finite(pet.retryAt, "Pet retry time") then return true end
    if key == -11 then return false end
    if type(UnitIsUnit) == "function" then
        local ok, same = pcall(UnitIsUnit, "pettarget", "target")
        if ok then
            local readable, value = pcall(boolean, same, "Pet target")
            if readable then return value end
        end
    end
    return boolean(pet.ordered, "Pet order state")
end

local numeric = {
    ["sh-read-resource"] = {"Resources", "sh-resource-pass"},
    ["sh-read-health"] = {"Health", "sh-health-pass", "sh-health-ready"},
    ["sh-read-stacks"] = {"AuraStacks", "sh-stacks-pass", "sh-stacks-ready"},
    ["sh-read-aura-time"] = {"AuraTime", "sh-aura-time-pass", "sh-aura-time-ready"},
}
local ordinary = {
    ["sh-read-player-buff"] = {"PlayerBuff", "sh-buff-present"},
    ["sh-read-target-effect"] = {"TargetEffect", "sh-target-effect-present"},
    ["sh-read-totem"] = {"TotemCooldown", "sh-totem-ready"},
    ["sh-read-target-casting"] = {"TargetCasting", "sh-target-casting"},
    ["sh-read-range"] = {"Range", "sh-out-of-range"},
    ["sh-read-immunity-skip"] = {"ImmunitySkip", "sh-immunity-skip"},
    ["sh-read-riposte"] = {"Riposte", "sh-riposte-ready"},
    ["sh-read-reactive"] = {"Riposte", "sh-reactive-ready"},
}

function Readers.Run(rotation, shadow, name, key, extra)
    rotation, shadow = object(rotation, "Rotation"), object(shadow, "Preview model")
    name, key, extra = plain(name, "Reader name"), plain(key, "Reader argument"), plain(extra, "Reader argument")
    if type(name) ~= "string" then error("Reader name is invalid", 0) end
    local button = object(rotation.button, "Prepared button")
    local spec = numeric[name]
    if spec then
        local owner = module(spec[1])
        key = integer(key, 1, 256, "Condition index")
        local value = fresh(owner, 3, 2, spec[3], false, function(phase)
            return refresh(owner, button, key, phase)
        end)
        return result(shadow, spec[2], value == 1)
    end
    if name == "sh-read-combo" then
        local owner = module("ComboPoints")
        local count = fresh(owner, 11, 6, nil, false, function(phase) return refresh(owner, phase) end)
        shadow:SetAttribute("sh-combo-count", count)
        return true, true
    end
    if name == "sh-hawk-read" then
        local owner = module("HawkCount")
        state(owner, "sh-binary-ready", true)
        local count = integer(call(owner, "Preview", button), 0, 2, "Hawk count")
        shadow:SetAttribute("sh-hawk-count", count)
        return true, true
    end
    if name == "sh-read-position-skip" then
        key = integer(key, 1, 32, "Position rule")
        local owner = module("PositionSkip")
        state(owner, "sh-binary-ready", true)
        return result(shadow, "sh-position-skip", call(owner, "Preview", button, key))
    end
    if name == "shfire-read-slot" then
        key = key or "fire"
        if key ~= "fire" and key ~= "earth" and key ~= "water" and key ~= "air" then error("Totem element is invalid", 0) end
        local owner = module("FireTotems")
        local function bit(index)
            return binary(owner, function(phase)
                call(button, "RefreshFireTotemsSlot", phase, index, key)
                return true -- The callback acknowledges through the fresh signal.
            end)
        end
        local low, high = bit(0), bit(1)
        return true, ({[0] = "missing", "searing", "magma", "other"})[(low and 1 or 0) + (high and 2 or 0)]
    end
    if name == "sh-read-ping" then
        key = integer(key, 1, 32, "Spell timing rule")
        if extra ~= nil and type(extra) ~= "boolean" then error("Spell timing request is invalid", 0) end
        local owner = module("PingDelay")
        validatePing(owner, button, key)
        local pass = binary(owner, function(phase) return refresh(owner, button, key, phase, false) end)
        validatePing(owner, button, key)
        return result(shadow, "sh-ping-pass", pass)
    end
    if name == "sh-read-wand" then
        if extra == true then
            if type(key) == "number" then integer(key, 1, 2147483647, "Current spell")
            elseif type(key) ~= "string" or key == "" then error("Current spell is invalid", 0) end
        else
            if extra ~= nil then error("Attack state request is invalid", 0) end
            integer(key, -11, 2147483647, "Attack spell")
            if key <= 0 then return result(shadow, "sh-wand-active", petState(key)) end
            if key ~= 75 and key ~= 5019 and key ~= 6603 then error("Attack spell is unsupported", 0) end
        end
        local owner = module("WandShoot")
        return result(shadow, "sh-wand-active", binary(owner, function(phase) return refresh(owner, phase, key, extra) end))
    end
    spec = ordinary[name]
    if spec then
        if name == "sh-read-player-buff" or name == "sh-read-target-effect" then integer(key, 1, 2147483647, "Aura reader index") end
        if name == "sh-read-target-effect" and not macroCondition("[@target,exists,harm,nodead]1") then
            error("Target debuff needs a living enemy target", 0)
        end
        if name == "sh-read-target-casting" and not macroCondition("[@target,exists]1") then
            return result(shadow, "sh-target-casting", false)
        end
        if name == "sh-read-range" or name == "sh-read-immunity-skip" then integer(key, 1, 32, "Rule index") end
        if name == "sh-read-immunity-skip" and (type(extra) ~= "string" or extra == "" or extra == "none") then error("Recipient is invalid", 0) end
        if name == "sh-read-reactive" or name == "sh-read-totem" then integer(key, 1, 2147483647, "Spell ID") end
        local owner = module(spec[1])
        if name == "sh-read-range" then
            local outsideCombat = not macroCondition("[combat]1")
            local ok, value = call(owner, "Preview", button, key)
            if ok ~= true then error(type(value) == "string" and value or "Range is unavailable", 0) end
            local stillOutsideCombat = outsideCombat and not macroCondition("[combat]1")
            if value == nil and (not outsideCombat or stillOutsideCombat) then
                -- Native selection excludes only a positive range failure.
                -- Public nil means this optional check supplied no result;
                -- do not turn it into either a confirmed range or an error.
                shadow:SetAttribute(spec[2], nil)
                return true, false
            end
            if value ~= nil then boolean(value, "Spell range") end
            if stillOutsideCombat then
                return result(shadow, spec[2], value)
            end
            -- In combat, keep the native signal's freshness checks. A readable
            -- preflight value alone does not validate a broken combat reader.
            -- If combat began during Preview, discard its outside-combat
            -- result (including nil) and request a fresh combat observation.
        end
        return result(shadow, spec[2], binary(owner, function(phase) return refresh(owner, button, phase, key, extra) end))
    end
    -- The caller owns local selector/check snippets and rejects any other name.
    return false
end

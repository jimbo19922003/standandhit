local _, SH = ...

local W = {ready = false, reason = "Attack actions have not been prepared.", widths = {data = {}, commit = {}}}
SH.WandShoot = W
local signal = SH.BinarySignal.New(W, "Attack actions", "wand", "StandAndHitAttack")

function W.IsSpell(spellID)
    return spellID == 5019 or spellID == 75
end

W.READ_SNIPPET = [[
    self:SetAttribute("sh-wand-active", nil)
    local spellID, currentSpell = ...
    if currentSpell == true then
        if rawtype(spellID) == "number" then
            if spellID < 1 or spellID % 1 ~= 0 then return false end
        elseif rawtype(spellID) ~= "string" or spellID == "" then return false end
    else
        if currentSpell ~= nil or rawtype(spellID) ~= "number" then return false end
        if spellID ~= 5019 and spellID ~= 75 and spellID ~= 6603 and (spellID < -11 or spellID > 0 or spellID % 1 ~= 0) then return false end
    end
]] .. SH.BinarySignal.Reader("wand", "sh-wand-active", "RefreshWandShoot", "phase, spellID, currentSpell")

local function secret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, result = pcall(issecretvalue, value)
    return not ok or type(result) ~= "boolean" or result
end

local function message(value)
    if secret(value) or type(value) ~= "string" then return "Attack action is unavailable" end
    return value:gsub("[\r\n\t]", " "):sub(1, 300)
end

local function active(spellID)
    if not W.IsSpell(spellID) then error("Unknown auto-repeat spell", 0) end
    if secret(C_Spell) or (C_Spell ~= nil and type(C_Spell) ~= "table") then error("Ranged spell API is unavailable", 0) end
    local fn = C_Spell and C_Spell.IsAutoRepeatSpell
    if secret(fn) then error("Ranged spell API is unreadable", 0) end
    if fn == nil then fn = IsAutoRepeatSpell end
    if secret(fn) or type(fn) ~= "function" then error("Ranged spell API is unavailable", 0) end
    -- This is the same active-or-pending query used by Blizzard's gamepad
    -- ranged attack button. Query again on each press so failed starts retry.
    return signal.Call("IsAutoRepeatSpell", fn, spellID)
end

local function current(spell)
    if secret(spell) or (type(spell) ~= "string" and type(spell) ~= "number") then error("Current spell is unreadable", 0) end
    if type(spell) == "number" and (spell < 1 or spell % 1 ~= 0) or spell == "" then error("Current spell is unavailable", 0) end
    if secret(C_Spell) or (C_Spell ~= nil and type(C_Spell) ~= "table") then error("Current spell API is unavailable", 0) end
    local fn = C_Spell and C_Spell.IsCurrentSpell
    if secret(fn) then error("Current spell API is unreadable", 0) end
    if fn == nil then fn = IsCurrentSpell end
    if secret(fn) or type(fn) ~= "function" then error("Current spell API is unavailable", 0) end
    return signal.Call("IsCurrentSpell", fn, spell)
end

function W:Prepare()
    local permitted, reason = pcall(signal.Outside)
    if not permitted then self.reason = message(reason); return false, self.reason end
    local ok, err = pcall(signal.Prepare)
    self.ready = ok
    if not ok then self.reason = message(err); return false, self.reason end
    self.reason = nil
    return true
end

function W:Attach(button)
    if not self.ready then return false, self.reason end
    local ok, err = pcall(signal.Attach, button)
    if not ok then self.reason = message(err); return false, self.reason end
    self.reason = nil
    return true
end

function W:Refresh(phase, spellID, currentSpell)
    if not self.ready then return false, self.reason end
    local ok, err = pcall(function()
        local value
        -- 0 checks the pet's current target. -11 checks an order still in flight.
        -- -1 through -10 identify the matching action on the pet bar.
        if currentSpell == true then value = current(spellID)
        elseif currentSpell ~= nil then error("Unknown attack state request", 0)
        elseif spellID == 0 or spellID == -11 then value = SH.PetAttack:IsOnTarget(spellID == -11)
        elseif type(spellID) == "number" and spellID < 0 and spellID >= -10 and spellID % 1 == 0 then
            value = SH.PetAttack:IsAttackSlot(-spellID)
        elseif spellID == 6603 then
            -- This is the melee state read by Blizzard's gamepad action bar.
            value = current(spellID)
        else value = active(spellID) end
        signal.Publish(value, phase)
    end)
    if not ok then self.reason = message(err); return false, self.reason end
    self.reason = nil
    return true
end

function W:Cleanup()
    local ok, err = pcall(signal.Hide)
    if not ok then self.reason = message(err); return false, self.reason end
    self.ready, self.reason = false, "Attack actions have not been prepared."
    return true
end

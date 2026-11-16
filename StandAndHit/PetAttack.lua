local _, SH = ...

local PetAttack = {ordered = false, retryAt = 0}
SH.PetAttack = PetAttack

-- If the client restricts target comparisons, one command can be issued for
-- each new target or pet. A miss on the first attempt can still be retried
-- when the pet has no living enemy, as checked by the secure rule.
local function resetTarget()
    PetAttack.ordered = false
    PetAttack.retryAt = 0
end

local function prepare()
    if InCombatLockdown() then error("Prepare Pet Attack outside combat.", 0) end
    if not PetAttack.events then PetAttack.events = CreateFrame("Frame") end
    local events = PetAttack.events
    events:SetScript("OnEvent", resetTarget)
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterUnitEvent("UNIT_PET", "player")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    PetAttack.ready = true
end

function PetAttack:Prepare()
    if self.ready then return true end
    return pcall(prepare)
end

local function readable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

function PetAttack:IsAttackSlot(slot)
    if not self.ready then return nil end
    if type(IsPetAttackAction) == "function" then
        local ok, attack = pcall(IsPetAttackAction, slot)
        if ok and readable(attack) and type(attack) == "boolean" then return attack end
    end
    if type(GetPetActionInfo) == "function" then
        local ok, name, _, token = pcall(GetPetActionInfo, slot)
        if ok and readable(name) and readable(token) then
            return token == true and name == "PET_ACTION_ATTACK"
        end
    end
    return nil
end

function PetAttack:IsOnTarget(idle)
    if not self.ready then return nil end
    -- Player spells can win subsequent presses while a pet order is in
    -- flight, even if the pet is out of range or has no path to the target.
    if GetTime() < self.retryAt then return true end
    if idle then return false end
    if type(UnitIsUnit) == "function" then
        local ok, same = pcall(UnitIsUnit, "pettarget", "target")
        if ok and readable(same) and type(same) == "boolean" then
            if same then self.ordered = true end
            return same
        end
    end
    return self.ordered
end

-- Only the final physical action records an order. Direct keys also evaluate
-- the priority list before clicking the Hit Button.
function PetAttack:NoteAttempt()
    self.ordered = true
    self.retryAt = GetTime() + 1
end

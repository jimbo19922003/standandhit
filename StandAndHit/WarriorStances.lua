local _, SH = ...
local Stances = {}
SH.WarriorStances = Stances

local stanceIDs = {2457, 71, 2458} -- Battle, Defensive, Berserker

local function public(value)
    return not (issecretvalue and issecretvalue(value))
end

-- Blizzard's stance bar uses the fourth return as its spell ID. The learned
-- slots can differ between characters, so never assume a stance's position.
function Stances.LearnedSpellID(slot)
    if type(GetShapeshiftFormInfo) ~= "function" then return nil end
    local ok, _, _, _, id = pcall(GetShapeshiftFormInfo, slot)
    if ok and public(id) and type(id) == "number" and id > 0 then return id end
end

function Stances.Resolve(input, source, spellName)
    if source ~= nil and source ~= "player" and source ~= "tracker" then return nil end
    local text = SH.Model.Trim(input)
    local requestedID, requestedName = tonumber(text), text:lower()
    spellName = spellName or (C_Spell and C_Spell.GetSpellName)
    local memberID, memberName
    for _, id in ipairs(stanceIDs) do
        local name
        if type(spellName) == "function" then
            local ok, value = pcall(spellName, id)
            if ok and public(value) and type(value) == "string" then name = value end
        end
        if id == requestedID or (not requestedID and name and name:lower() == requestedName) then
            if memberID then return nil, "more than one Warrior stance has that name. Enter its exact spell ID." end
            memberID, memberName = id, name
        end
    end
    if not memberID then return nil end
    if type(GetNumShapeshiftForms) ~= "function" then
        return nil, "the stance bar could not be read. Try Prepare again."
    end
    local ok, count = pcall(GetNumShapeshiftForms)
    if not ok or not public(count) or type(count) ~= "number" or count < 0 or count > 255 or count % 1 ~= 0 then
        return nil, "the stance bar could not be read. Try Prepare again."
    end
    local memberSlot
    for slot = 1, count do
        if Stances.LearnedSpellID(slot) == memberID then
            if memberSlot then return nil, "the stance bar has duplicate stance slots. Try Prepare again." end
            memberSlot = slot
        end
    end
    if not memberSlot then
        return nil, "the Warrior stance is missing from this character's stance bar. Learn it, then Prepare again."
    end
    -- A stance is a native form state, not an aura or the visibility of a
    -- Cooldown Manager icon. Reuse the existing secure form signal machinery.
    return {
        warriorStance = true, formSlot = memberSlot, formSpellID = memberID,
        auraSource = "tracker", effectInput = text, name = memberName or text,
        baseID = memberID, ids = {[memberID] = true}, linkedIDs = {[memberID] = true}, metadata = {},
    }
end

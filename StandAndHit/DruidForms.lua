local _, SH = ...
local Forms = {GroupID = 1319289} -- Druid Forms in Forever's Tracked Buffs
SH.DruidForms = Forms

function Forms.IsGroup(entry)
    return entry and entry.baseID == Forms.GroupID
end

-- The fourth return is the spell on this character's stance bar. Slots depend
-- on the forms learned, so resolve them on Prepare instead of assuming an order.
function Forms.LearnedSpellID(slot)
    if type(GetShapeshiftFormInfo) ~= "function" then return nil end
    local ok, _, _, _, id = pcall(GetShapeshiftFormInfo, slot)
    if ok and not (issecretvalue and issecretvalue(id)) and type(id) == "number" and id > 0 then
        return id
    end
end

function Forms.Resolve(entry, input, spellName)
    if not Forms.IsGroup(entry) then return nil end
    local text = SH.Model.Trim(input)
    local id, name = tonumber(text), text:lower()
    spellName = spellName or (C_Spell and C_Spell.GetSpellName)
    if id == Forms.GroupID then
        return nil, nil, "enter an individual form from Druid Forms, such as Cat Form."
    end

    local memberID
    for linkedID in pairs(entry.linkedIDs) do
        local memberName = not id and spellName and spellName(linkedID)
        if linkedID == id or (memberName and memberName:lower() == name) then
            if memberID then return nil, nil, "more than one form has that name. Enter its exact spell ID." end
            memberID = linkedID
        end
    end
    if not memberID then
        if not id and entry.name and entry.name:lower() == name then
            return nil, nil, "enter an individual form from Druid Forms, such as Cat Form."
        end
        return nil
    end
    local count = GetNumShapeshiftForms and GetNumShapeshiftForms()
    if type(count) ~= "number" then return nil, nil, "the stance bar could not be read. Try Prepare again." end
    for slot = 1, count do
        if Forms.LearnedSpellID(slot) == memberID then return slot, memberID end
    end
    return nil, nil, "the form is tracked, but it is missing from this character's stance bar."
end

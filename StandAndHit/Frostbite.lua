local _, SH = ...
local Frostbite = {}
SH.Frostbite = Frostbite

-- Forever's Frostbite tracker (cooldown ID 199326) lists the passive talent
-- as its base spell and the freeze it applies as a linked spell.
local talentID, freezeID = 11071, 12494

function Frostbite.IsEntry(entry)
    return entry and (entry.baseID == talentID or entry.baseID == freezeID)
end

function Frostbite.Resolve(entry, input, spellName)
    if not Frostbite.IsEntry(entry) then return nil end
    local text = SH.Model.Trim(input)
    local id = tonumber(text)
    if id and id ~= talentID and id ~= freezeID then return nil end
    local freezeName = spellName(freezeID)
    local name = freezeName or entry.name
    if not name then return nil, "the Frostbite tracker is still loading. Try Prepare again." end
    if not id and text:lower() ~= name:lower() and
        (not entry.name or text:lower() ~= entry.name:lower()) then return nil end
    if entry.baseID ~= freezeID and not entry.linkedIDs[freezeID] then
        return nil, "this Frostbite entry doesn't list the applied freeze (12494). Check the entry in Tracked Buffs or Tracked Bars."
    end
    return {name = name, ids = {[freezeID] = true}, skipNameLookup = not freezeName}
end

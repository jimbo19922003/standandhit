local _, SH = ...
local Gouge = {}
SH.Gouge = Gouge

-- Forever's Tracked Buff entry 200223 uses cast 1776 and links only the
-- self-targeted dummy 1324481. Its visibility does not identify the enemy's
-- incapacitate. Read the player's harmful target aura using the real ranks.
local proxyID = 1324481
local ranks = {[1776] = true, [1777] = true, [8629] = true, [11285] = true, [11286] = true}

local function familyID(id)
    return ranks[id] == true or id == proxyID
end

function Gouge.IsEntry(entry)
    return entry and familyID(entry.baseID)
end

function Gouge.Matches(entry, input, spellName)
    if not Gouge.IsEntry(entry) then return false end
    local text = SH.Model.Trim(input)
    local id = tonumber(text)
    if id then return familyID(id) end
    local name = spellName(1776) or entry.name
    return name and text:lower() == name:lower() or false
end

function Gouge.Resolve(entry, input, spellName)
    if not Gouge.Matches(entry, input, spellName) then return nil end
    -- Only the verified Gouge family receives this mapping. Unknown aliases,
    -- items and category trackers retain the ordinary rejection behavior.
    for id in pairs(entry.ids or {}) do
        if not familyID(id) then return nil, "the Gouge tracker includes an unrelated spell. Use the Gouge entry in Tracked Buffs or Tracked Bars." end
    end
    local metadata = entry.metadata or {}
    if metadata.equipSlot or metadata.spellCategoryID then
        return nil, "item and category trackers cannot be used as Target debuff."
    end
    if metadata.spellID and not familyID(metadata.spellID) then
        return nil, "the Gouge tracker does not identify a known Gouge spell."
    end
    local ids = {}
    for id in pairs(ranks) do ids[id] = true end
    local name = spellName(1776)
    return {name = name or entry.name, ids = ids, unit = "target", skipNameLookup = not name}
end

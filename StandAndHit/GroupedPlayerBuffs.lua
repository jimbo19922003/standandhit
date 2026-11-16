local _, SH = ...
local Buffs = {groups = {
    [1324056] = {class = "HUNTER", className = "hunter", groupName = "Aspects", kind = "aspect"},
    [1323522] = {class = "PALADIN", className = "paladin", groupName = "Seals", kind = "seal"},
    [465] = {class = "PALADIN", className = "paladin", groupName = "Devotion Aura", kind = "aura"},
    [7294] = {class = "PALADIN", className = "paladin", groupName = "Retribution Aura", kind = "aura"},
    [19746] = {class = "PALADIN", className = "paladin", groupName = "Concentration Aura", kind = "aura"},
    [19876] = {class = "PALADIN", className = "paladin", groupName = "Shadow Resistance Aura", kind = "aura"},
    [19888] = {class = "PALADIN", className = "paladin", groupName = "Frost Resistance Aura", kind = "aura"},
    [19891] = {class = "PALADIN", className = "paladin", groupName = "Fire Resistance Aura", kind = "aura"},
    [19740] = {class = "PALADIN", className = "paladin", groupName = "Blessing of Might", kind = "blessing"},
    [19742] = {class = "PALADIN", className = "paladin", groupName = "Blessing of Wisdom", kind = "blessing"},
    [20217] = {class = "PALADIN", className = "paladin", groupName = "Blessing of Kings", kind = "blessing"},
    [1022] = {class = "PALADIN", className = "paladin", groupName = "Blessing of Protection", kind = "blessing"},
    [6940] = {class = "PALADIN", className = "paladin", groupName = "Blessing of Sacrifice", kind = "blessing"},
    [1044] = {class = "PALADIN", className = "paladin", groupName = "Blessing of Freedom", kind = "blessing"},
    [1038] = {class = "PALADIN", className = "paladin", groupName = "Salvation", kind = "blessing"},
    [19977] = {class = "PALADIN", className = "paladin", groupName = "Blessing of Light", kind = "blessing"},
}}
SH.GroupedPlayerBuffs = Buffs

-- A tracker can use a learned rank or Greater Blessing as its base spell.
-- These are native members of the supported families, not tooltip aliases.
local familyRanks = {
    [465] = {465, 10290, 643, 10291, 1032, 10292, 10293},
    [7294] = {7294, 10298, 10299, 10300, 10301},
    [19746] = {19746},
    [19876] = {19876, 19895, 19896},
    [19888] = {19888, 19897, 19898},
    [19891] = {19891, 19899, 19900},
    [19740] = {19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916},
    [19742] = {19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918},
    [20217] = {20217, 25898},
    [1022] = {1022, 5599, 10278},
    [6940] = {6940, 20729},
    [1044] = {1044},
    [1038] = {1038, 25895},
    [19977] = {19977, 19978, 19979, 25890},
}
local rankGroups = {}
for baseID, ranks in pairs(familyRanks) do
    for _, id in ipairs(ranks) do rankGroups[id] = Buffs.groups[baseID] end
end

local function groupForEntry(entry)
    return entry and (Buffs.groups[entry.baseID] or rankGroups[entry.baseID])
end

-- These learned seals apply buffs to the caster. Their Player buff conditions
-- need the same combat reader as the Seals tracker, even with no tracker entry.
-- Include only self-aura ranks; same-name damage and Judgement effects differ.
local directSealFamilies = {
    {baseID = 21082, ranks = {21082, 20162, 20305, 20306, 20307, 20308}},
    {baseID = 21084, ranks = {21084, 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293}},
}

function Buffs.ResolvePlayerSeal(input, spellName, isLearned)
    local class
    if UnitClassBase then class = UnitClassBase("player")
    elseif UnitClass then class = select(2, UnitClass("player")) end
    if class ~= "PALADIN" then return nil end
    local text = SH.Model.Trim(input)
    local numeric, lower = tonumber(text), text:lower()
    for _, family in ipairs(directSealFamilies) do
        local name, matches, learned
        for _, id in ipairs(family.ranks) do
            local rankName = spellName(id)
            name = name or rankName
            if numeric == id or (not numeric and rankName and rankName:lower() == lower) then matches = true end
            if isLearned(id) then learned = true end
        end
        if matches and learned and name then
            local ids = {}
            for _, id in ipairs(family.ranks) do ids[id] = true end
            return {name = name, ids = ids, groupedPlayerBuff = true, memberID = family.baseID,
                groupName = "Seals", kind = "seal"}
        end
    end
end

function Buffs.IsGroup(entry)
    return groupForEntry(entry) ~= nil
end

function Buffs.Resolve(entry, input, spellName, isLearned)
    local group = groupForEntry(entry)
    if not group then return nil, "this tracker is not a supported class buff group." end
    local class
    if UnitClassBase then class = UnitClassBase("player")
    elseif UnitClass then class = select(2, UnitClass("player")) end
    if class ~= group.class then return nil, "only a " .. group.className .. " can check their active " .. group.kind .. "." end

    local text = SH.Model.Trim(input)
    local numeric = tonumber(text)
    local name = text
    if numeric then name = spellName(numeric) end
    if type(name) ~= "string" or name == "" then return nil, "the selected spell name could not be read. Try Prepare again." end
    local lower = name:lower()
    local ids, learned, memberID = {}, false, nil
    -- Some single-rank families have no linked members in native metadata.
    local linkedIDs = next(entry.linkedIDs) and entry.linkedIDs or {[entry.baseID] = true}
    for id in pairs(linkedIDs) do
        local member = spellName(id)
        if member and member:lower() == lower then
            ids[id], name = true, member
            if not memberID or memberID > id then memberID = id end
            if isLearned(id) then learned = true end
        end
    end
    if not memberID then return nil, "enter the name or spell ID of an individual " .. group.kind .. " listed under " .. group.groupName .. "." end

    -- The native group can list only some ranks (for example, Hawk through
    -- rank 6). Accept additional ranks from this character's learned spellbook,
    -- where rank subtext distinguishes them from same-name triggered spells.
    if SH.SpellRanks then
        for _, choice in ipairs(SH.SpellRanks.GetChoices(numeric or name)) do
            if choice.id and choice.name and choice.name:lower() == lower and
                (ids[choice.id] or (choice.rankText and choice.rankText ~= "")) then
                ids[choice.id], learned = true, true
            end
        end
    end
    if numeric and not ids[numeric] then return nil, "that spell ID is not a tracked " .. group.kind .. " or a learned rank of it." end
    if not learned then return nil, "this " .. group.className .. " has not learned the selected " .. group.kind .. "." end
    return {name = name, ids = ids, groupedPlayerBuff = true, memberID = memberID,
        groupName = group.groupName, kind = group.kind}
end

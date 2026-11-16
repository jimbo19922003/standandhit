local _, SH = ...
local SpellRanks = {}
SH.SpellRanks = SpellRanks

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end

local function trim(value)
    if type(value) ~= "string" and type(value) ~= "number" then return "" end
    return tostring(value):match("^%s*(.-)%s*$")
end

local function spellInfo(value)
    local info = call(C_Spell and C_Spell.GetSpellInfo, value)
    if type(info) == "table" and info.name then return info end
    local name, rank, icon, _, _, _, id = call(GetSpellInfo, value)
    if name then return {name = name, spellID = id, iconID = icon, rank = rank} end
end

local function playerBank()
    return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
end

local function knownSpell(id)
    local known
    local function result(value)
        if (type(issecretvalue) ~= "function" or not issecretvalue(value)) and type(value) == "boolean" then
            if value then return true end
            known = false
        end
    end
    local book = C_SpellBook
    -- Form/talent replacements may be in the player's spellbook without
    -- being separately learned. A negative legacy query must not veto them.
    if result(call(book and book.IsSpellKnownOrInSpellBook, id, playerBank(), true)) then return true end
    if result(call(book and book.IsSpellInSpellBook, id, playerBank(), true)) then return true end
    if result(call(book and book.IsSpellKnown, id, playerBank())) then return true end
    if result(call(IsPlayerSpell, id)) then return true end
    if result(call(IsSpellKnown, id, false)) then return true end
    return known
end

SpellRanks.IsLearned = knownSpell

local function passiveSpell(id)
    local passive = call(C_Spell and C_Spell.IsSpellPassive, id)
    if type(passive) == "boolean" then return passive end
    return call(IsPassiveSpell, id) == true
end

local function subtext(id, fallback)
    local text = trim(call(C_Spell and C_Spell.GetSpellSubtext, id))
    if text == "" then text = trim(call(GetSpellSubtext, id)) end
    if text == "" then text = trim(fallback) end
    return text
end

-- Read all player spellbook slots, including ranks hidden by the spellbook UI.
-- These APIs only inspect learned spells; no action bars or settings are changed.
function SpellRanks.GetChoices(spellText)
    local text = trim(spellText)
    local numeric = tonumber(text)
    if numeric and (numeric < 1 or numeric ~= math.floor(numeric)) then numeric = nil end
    local requested = text ~= "" and spellInfo(numeric or text) or nil
    local baseName = requested and requested.name or (not numeric and text or nil)
    local choices = {{label = "Highest learned", name = baseName}}
    if not baseName or baseName == "" then return choices, baseName end

    local matches, seen = {}, {}
    local matchName = string.lower(baseName)
    local function add(id, name, rankText, learnedSlot)
        if type(id) ~= "number" or id < 1 or id ~= math.floor(id) or seen[id] then return end
        local info = spellInfo(id)
        name = info and info.name or name
        if type(name) ~= "string" or string.lower(name) ~= matchName then return end
        local known = knownSpell(id)
        -- A current, non-passive SPELL slot is evidence when the client lacks a
        -- learned-spell query. Direct name/ID fallbacks need an explicit result.
        if known == false or (known ~= true and not learnedSlot) or passiveSpell(id) then return end
        seen[id] = true
        local rank = subtext(id, rankText or (info and info.rank))
        matches[#matches + 1] = {
            id = id, name = name, label = rank ~= "" and rank or ("Spell ID " .. id),
            rankText = rank, rankNumber = tonumber(rank:match("%d+")),
        }
    end

    local modern = C_SpellBook
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
    local numLines = call(modern and modern.GetNumSpellBookSkillLines)
    if type(numLines) == "number" then
        for line = 1, numLines do
            local skill = call(modern.GetSpellBookSkillLineInfo, line)
            if type(skill) == "table" and not skill.isGuild and
                (not skill.offSpecID or skill.offSpecID == 0) and
                type(skill.itemIndexOffset) == "number" and type(skill.numSpellBookItems) == "number" then
                for slot = skill.itemIndexOffset + 1, skill.itemIndexOffset + skill.numSpellBookItems do
                    local item = call(modern.GetSpellBookItemInfo, slot, playerBank())
                    if type(item) == "table" and item.itemType == spellType and
                        not item.isPassive and not item.isOffSpec and
                        call(modern.IsSpellBookItemPassive, slot, playerBank()) ~= true then
                        local name, rank = call(modern.GetSpellBookItemName, slot, playerBank())
                        local rankText = trim(item.subName) ~= "" and item.subName or rank
                        add(item.spellID or item.actionID, item.name or name, rankText, true)
                    end
                end
            end
        end
    end

    -- Classic clients expose the same player book through global functions.
    -- Visiting both interfaces is harmless: exact spell IDs are deduplicated.
    local numTabs = call(GetNumSpellTabs)
    if type(numTabs) == "number" then
        local bank = BOOKTYPE_SPELL or "spell"
        for tab = 1, numTabs do
            local _, _, offset, count, isGuild, offSpecID = call(GetSpellTabInfo, tab)
            if type(offset) == "number" and type(count) == "number" and not isGuild and
                (not offSpecID or offSpecID == 0) then
                for slot = offset + 1, offset + count do
                    local kind, id = call(GetSpellBookItemInfo, slot, bank)
                    if kind == "SPELL" and call(IsPassiveSpell, slot, bank) ~= true then
                        local name, rank, nameID = call(GetSpellBookItemName, slot, bank)
                        add(nameID or id, name, rank, true)
                    end
                end
            end
        end
    end

    -- Preserve a learned numeric spell ID even if it is not exposed in a tab,
    -- and offer the resolved known spell when enumeration is unavailable.
    if requested then add(numeric or requested.spellID, requested.name, requested.rank, false) end
    table.sort(matches, function(a, b)
        if a.rankNumber and b.rankNumber and a.rankNumber ~= b.rankNumber then
            return a.rankNumber < b.rankNumber
        end
        if (a.rankNumber ~= nil) ~= (b.rankNumber ~= nil) then return a.rankNumber ~= nil end
        if a.rankText ~= b.rankText then return a.rankText < b.rankText end
        return a.id < b.id
    end)
    local labels = {}
    for _, choice in ipairs(matches) do labels[choice.label] = (labels[choice.label] or 0) + 1 end
    for _, choice in ipairs(matches) do
        if labels[choice.label] > 1 then choice.label = choice.label .. " (ID " .. choice.id .. ")" end
        choices[#choices + 1] = choice
    end
    return choices, baseName
end

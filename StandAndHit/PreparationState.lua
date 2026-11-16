local _, SH = ...

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end

local function integer(value, minimum)
    return type(value) == "number" and value >= minimum and value < math.huge and value == math.floor(value)
end

local function signature(values, prefix)
    local sorted = {}
    for value in pairs(values) do sorted[#sorted + 1] = value end
    if #sorted == 0 then return nil end
    table.sort(sorted)
    return prefix .. table.concat(sorted, ";")
end

local function spellState()
    local ids, total = {}, 0
    local function add(id)
        if not integer(id, 1) then return false end
        ids["s" .. id] = true
        return true
    end
    local function flyout(id)
        if not integer(id, 1) then return false end
        local _, _, count = call(GetFlyoutInfo, id)
        if not integer(count, 0) or count > 1000 then return false end
        for slot = 1, count do
            local spellID, _, known = call(GetFlyoutSlotInfo, id, slot)
            if type(known) ~= "boolean" then return false end
            if known then
                if not add(spellID) then return false end
                total = total + 1
            end
        end
        return true
    end
    local modern = C_SpellBook
    if modern and type(modern.GetNumSpellBookSkillLines) == "function" then
        local count = call(modern.GetNumSpellBookSkillLines)
        if not integer(count, 1) or count > 100 then return nil end
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
        local flyoutType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout or 4
        for line = 1, count do
            local skill = call(modern.GetSpellBookSkillLineInfo, line)
            if type(skill) ~= "table" then return nil end
            if not skill.isGuild and (not skill.offSpecID or skill.offSpecID == 0) then
                local offset, length = skill.itemIndexOffset, skill.numSpellBookItems
                if not integer(offset, 0) or not integer(length, 0) or length > 10000 then return nil end
                for slot = offset + 1, offset + length do
                    local item = call(modern.GetSpellBookItemInfo, slot, bank)
                    if type(item) ~= "table" or item.itemType == nil or item.itemType == 0 then return nil end
                    if not item.isOffSpec then
                        if item.itemType == spellType then
                            -- actionID is the learned base spell; spellID can be a temporary override.
                            if not add(item.actionID or item.spellID) then return nil end
                            total = total + 1
                        elseif item.itemType == flyoutType then
                            if not flyout(item.actionID) then return nil end
                        end
                    end
                end
            end
        end
    else
        local count = call(GetNumSpellTabs)
        if not integer(count, 1) or count > 100 then return nil end
        for tab = 1, count do
            local _, _, offset, length, guild, offSpec = call(GetSpellTabInfo, tab)
            if not integer(offset, 0) or not integer(length, 0) or length > 10000 then return nil end
            if not guild and (not offSpec or offSpec == 0) then
                for slot = offset + 1, offset + length do
                    local kind, id = call(GetSpellBookItemInfo, slot, BOOKTYPE_SPELL or "spell")
                    if kind == nil then return nil end
                    if kind == "SPELL" then
                        if not add(id) then return nil end
                        total = total + 1
                    elseif kind == "FLYOUT" then
                        if not flyout(id) then return nil end
                    end
                end
            end
        end
    end
    if total == 0 then return nil end
    return signature(ids, "book:")
end

local function talentState()
    local api = C_SpecializationInfo
    if api and type(api.IsInitialized) == "function" and call(api.IsInitialized) ~= true then return nil end
    if type(GetNumTalents) == "function" then
        local count = call(GetNumTalentTabs)
        if count == nil then count = call(GetNumSpecializations, false, false) end
        if not integer(count, 1) or count > 20 then return nil end
        local values, total = {}, 0
        for tab = 1, count do
            local length = call(GetNumTalents, tab, false, false)
            -- A listed player talent tab with no entries is still loading.
            -- Keeping just the other tabs would look like a talent reset.
            if not integer(length, 1) or length > 1000 then return nil end
            for index = 1, length do
                local rank
                if api and type(api.GetTalentInfo) == "function" then
                    local info = call(api.GetTalentInfo, {specializationIndex = tab, talentIndex = index, isInspect = false, isPet = false})
                    if type(info) ~= "table" then return nil end
                    rank = info.rank
                else
                    local name, _, _, _, value = call(GetTalentInfo, tab, index, false, false)
                    if name == nil then return nil end
                    rank = value
                end
                if not integer(rank, 0) then return nil end
                values[tab .. ":" .. index .. ":" .. rank] = true
                total = total + 1
            end
        end
        if total == 0 then return nil end
        local groupAPI = api and api.GetActiveSpecGroup or GetActiveTalentGroup
        if type(groupAPI) == "function" then
            local group = call(groupAPI)
            -- Do not save a fingerprint without its group, then call the
            -- group's later arrival a talent change.
            if not integer(group, 1) then return nil end
            values["group:" .. group] = true
        end
        return signature(values, "talents:")
    end

    -- Newer clients expose their active talent tree through trait nodes.
    local traits = C_Traits
    local configID = call(C_ClassTalents and C_ClassTalents.GetActiveConfigID)
    if not integer(configID, 1) or not traits then return nil end
    if type(traits.ConfigHasStagedChanges) == "function" and call(traits.ConfigHasStagedChanges, configID) ~= false then return nil end
    local config = call(traits.GetConfigInfo, configID)
    if type(config) ~= "table" or type(config.treeIDs) ~= "table" or #config.treeIDs == 0 then return nil end
    local values, total = {}, 0
    for _, treeID in ipairs(config.treeIDs) do
        local nodes = call(traits.GetTreeNodes, treeID)
        if type(nodes) ~= "table" or #nodes == 0 then return nil end
        for _, nodeID in ipairs(nodes) do
            local node = call(traits.GetNodeInfo, configID, nodeID)
            if type(node) ~= "table" or not integer(node.ranksPurchased, 0) then return nil end
            local entry = node.activeEntry and node.activeEntry.entryID or 0
            if not integer(entry, 0) then return nil end
            values[treeID .. ":" .. nodeID .. ":" .. entry .. ":" .. node.ranksPurchased] = true
            total = total + 1
        end
    end
    if total == 0 then return nil end
    return signature(values, "traits:")
end

-- Unavailable or incomplete data never becomes an empty fingerprint. The caller
-- can retain its last complete baseline while native data reloads during zoning.
function SH.GetPreparationState()
    local state = {spells = call(spellState), talents = call(talentState)}
    local spellAPI = (C_SpellBook and type(C_SpellBook.GetNumSpellBookSkillLines) == "function")
        or type(GetNumSpellTabs) == "function"
    local talentAPI = type(GetNumTalents) == "function"
        or (C_ClassTalents and type(C_ClassTalents.GetActiveConfigID) == "function" and C_Traits)
    local talentPending = talentAPI and state.talents == nil
    if talentPending and C_SpecializationInfo and call(C_SpecializationInfo.IsInitialized) == true and
        call(C_SpecializationInfo.HasPlayerEarnedATalentPoint) == false then
        -- Some clients expose no player talent tree before the first point.
        -- Native initialization plus this explicit answer is not a load delay.
        talentPending = false
    end
    -- The second result distinguishes unsupported APIs from supported APIs
    -- whose initial data is missing. An empty first snapshot is not readiness.
    return state, (not spellAPI or state.spells ~= nil) and not talentPending
end

function SH.CompletePreparationTalentBaseline(previous, current)
    -- Older snapshots could omit a temporarily unavailable active group.
    -- Fill only that missing field when every recorded talent rank agrees.
    if type(previous) == "string" and type(current) == "string" and
        previous:sub(1, 8) == "talents:" and not previous:find("group:", 1, true) and
        current:gsub(";group:%d+", "") == previous then return current end
    return previous
end

function SH.PreparationStateKnowsSpell(state, spellID)
    local spells = state and state.spells
    if type(spells) ~= "string" or spells:sub(1, 5) ~= "book:" or not integer(spellID, 1) then return false end
    return (";" .. spells:sub(6) .. ";"):find(";s" .. spellID .. ";", 1, true) ~= nil
end

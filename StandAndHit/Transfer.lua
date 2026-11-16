local _, SH = ...
local Transfer = {}
SH.Transfer = Transfer

Transfer.MAX_TEXT = 262144
local MAX_PAYLOAD = 131072
local MAX_NAME = 200
local MAX_ID = 2147483647
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decodeAlphabet = {}
for index = 1, #alphabet do decodeAlphabet[alphabet:sub(index, index)] = index - 1 end
local groups = {"andConditions", "orConditions", "notConditions"}
local auraSources = {tracker = true, target = true, player = true}
local flags = {"useOr", "skipCooldown", "oncePerProc", "stopCasting", "stopWhenInvalid", "pingDelay", "manualCooldown", "targetCasting", "skipIfNotCasted", "skipIfImmune", "skipOutOfRange", "outOfCombatOnly", "inCombatOnly", "advanceOnToggle"}

local function hasSpellCooldown(row)
    if row.orAuraSource == "cooldown" then return true end
    for _, group in ipairs(groups) do
        for _, condition in ipairs(row[group] or {}) do
            if condition.auraSource == "cooldown" then return true end
        end
    end
    return false
end

local function checksum(text)
    local a, b = 1, 0
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

local function encode64(text)
    local result = {}
    for index = 1, #text, 3 do
        local a, b, c = text:byte(index, index + 2)
        local value = a * 65536 + (b or 0) * 256 + (c or 0)
        local x = math.floor(value / 262144) % 64 + 1
        local y = math.floor(value / 4096) % 64 + 1
        local z = math.floor(value / 64) % 64 + 1
        local w = value % 64 + 1
        result[#result + 1] = alphabet:sub(x, x) .. alphabet:sub(y, y)
            .. (b and alphabet:sub(z, z) or "=") .. (c and alphabet:sub(w, w) or "=")
    end
    return table.concat(result)
end

local function decode64(text)
    if #text == 0 or #text % 4 ~= 0 or #text > math.ceil(MAX_PAYLOAD / 3) * 4 then return nil end
    local result = {}
    for index = 1, #text, 4 do
        local c, d = text:sub(index + 2, index + 2), text:sub(index + 3, index + 3)
        local a, b = decodeAlphabet[text:sub(index, index)], decodeAlphabet[text:sub(index + 1, index + 1)]
        local x, y = decodeAlphabet[c], decodeAlphabet[d]
        if not a or not b or (not x and c ~= "=") or (not y and d ~= "=") then return nil end
        if c == "=" and (d ~= "=" or b % 16 ~= 0) then return nil end
        if d == "=" and c ~= "=" and x % 4 ~= 0 then return nil end
        if (c == "=" or d == "=") and index + 3 ~= #text then return nil end
        local value = a * 262144 + b * 4096 + (x or 0) * 64 + (y or 0)
        result[#result + 1] = string.char(math.floor(value / 65536))
        if c ~= "=" then result[#result + 1] = string.char(math.floor(value / 256) % 256) end
        if d ~= "=" then result[#result + 1] = string.char(value % 256) end
    end
    local decoded = table.concat(result)
    if #decoded > MAX_PAYLOAD then return nil end
    return decoded
end

local function integer(value, minimum, maximum)
    return type(value) == "number" and value >= minimum and value <= maximum and value % 1 == 0
end

local function listSize(value, maximum, label)
    if type(value) ~= "table" then return nil, label .. " must be a numbered list." end
    local count = 0
    for key in pairs(value) do
        if not integer(key, 1, maximum) then return nil, label .. " is too large or is not a numbered list." end
        count = count + 1
    end
    for index = 1, count do
        if value[index] == nil then return nil, label .. " must not contain gaps." end
    end
    return count
end

local function name(value, label)
    if value == nil then return "" end
    if type(value) == "number" then
        if not integer(value, 1, MAX_ID) then return nil, label .. " must be a spell name or a valid spell ID." end
        value = tostring(value)
    end
    if type(value) ~= "string" then return nil, label .. " must be a spell name or spell ID." end
    if #value > MAX_NAME then return nil, label .. " is too long (maximum 200 bytes)." end
    if value:find("[%z\1-\31\127]") then return nil, label .. " contains an invalid control character." end
    return SH.Model.Trim(value)
end

-- Only portable draft settings are copied. Runtime frames, keys, positions,
-- prepared state, and any unrelated saved variables never enter the payload.
local function validate(rules, preventClipping)
    if preventClipping == nil then preventClipping = true end
    if type(preventClipping) ~= "boolean" then return nil, "Protect channels must be on or off." end
    local size, err = listSize(rules, SH.Model.MAX_RULES, "Spell rules")
    if not size then return nil, err end
    local result = {rules = {}, preventClipping = preventClipping}
    for index = 1, size do
        local source, row = rules[index], {}
        local prefix = "Rule " .. index .. ": "
        if type(source) ~= "table" then return nil, prefix .. "invalid rule." end
        for _, key in ipairs({"spell", "aura", "orAura"}) do
            local label = (key == "spell" or key == "orAura" and source.orAuraSource == "cooldown") and "Spell" or "Aura"
            row[key], err = name(source[key], label)
            if not row[key] then return nil, prefix .. err end
        end
        for _, key in ipairs(flags) do
            if source[key] ~= nil and type(source[key]) ~= "boolean" then return nil, prefix .. key .. " must be on or off." end
            row[key] = source[key] == true
        end
        if row.outOfCombatOnly and row.inCombatOnly then
            return nil, prefix .. "Choose either In combat only or Out of combat only."
        end
        if source.enabled ~= nil and type(source.enabled) ~= "boolean" then return nil, prefix .. "Enable Rule must be on or off." end
        row.enabled = source.enabled ~= false
        for _, field in ipairs({"skipModifier", "priorityModifier"}) do
            row[field], err = SH.Model.NormalizeModifier(source[field])
            if err then return nil, prefix .. field .. ": " .. err end
        end
        if source.totemCondition ~= nil and not SH.Model.IsTotemCondition(source.totemCondition) then
            return nil, prefix .. "choose a valid totem condition."
        end
        row.totemCondition = source.totemCondition
        for _, field in ipairs({"customTarget", "customCondition"}) do
            if source[field] ~= nil then
                if type(source[field]) ~= "string" or #source[field] > 255 or source[field]:find("[%c]") then
                    return nil, prefix .. "Invalid macro target or condition text."
                end
                row[field] = source[field]
            end
        end
        if source.customRule ~= nil then
            row.customRule, err = SH.Model.NormalizeCustomRule(source.customRule)
            if not row.customRule then return nil, prefix .. err end
            row.spell = "Custom Rule"
        end
        row.pingDelayMS = source.pingDelayMS == nil and 100 or source.pingDelayMS
        if not integer(row.pingDelayMS, 1, 5000) then return nil, prefix .. "Ping Delay must be a whole number from 1 to 5000 ms." end
        row.manualCooldownSeconds, err = SH.Model.NormalizeManualCooldownSeconds(source.manualCooldownSeconds, source.manualCooldown)
        if row.manualCooldownSeconds == nil then return nil, prefix .. err end
        row.condition = source.condition == nil and "present" or source.condition
        row.unit = source.unit == nil and "target" or source.unit
        row.auraSource = source.auraSource == nil and "tracker" or source.auraSource
        row.orCondition = source.orCondition == nil and "present" or source.orCondition
        row.orAuraSource = source.orAuraSource == nil and "tracker" or source.orAuraSource
        for _, field in ipairs({"condition", "unit", "auraSource", "orAuraSource"}) do
            if type(row[field]) ~= "string" or #row[field] > 16 or row[field]:find("%c") then
                return nil, prefix .. "Invalid " .. field .. "."
            end
        end
        if row.orCondition ~= "present" and row.orCondition ~= "missing" then return nil, prefix .. "choose present or missing after OR." end
        if not auraSources[row.auraSource] then return nil, prefix .. "Choose a valid primary aura source." end
        if not auraSources[row.orAuraSource] and row.orAuraSource ~= "cooldown" then
            return nil, prefix .. "Choose a valid OR condition source."
        end
        if row.orAuraSource == "cooldown" and row.orAura == "" then
            return nil, prefix .. "Enter the spell for the OR cooldown condition."
        end
        row.rankID = source.rankID
        if row.rankID ~= nil and not integer(row.rankID, 1, MAX_ID) then return nil, prefix .. "invalid spell rank ID." end
        row.castCount = source.castCount == nil and 0 or source.castCount
        if not integer(row.castCount, 0, 99) then return nil, prefix .. "Cast Count must be a whole number from 0 to 99." end
        row.castCountCondition = source.castCountCondition == nil and "primary" or source.castCountCondition
        if source.comboPoints ~= nil then
            local combo, comboError = SH.Model.NormalizeComboPoints(source.comboPoints)
            if not combo then return nil, prefix .. comboError end
            row.comboPoints = combo
        end
        if source.hawkCount ~= nil then
            local hawks, hawkError = SH.Model.NormalizeHawkCount(source.hawkCount)
            if not hawks then return nil, prefix .. hawkError end
            row.hawkCount = hawks
        end
        local resources, resourceError = SH.Model.NormalizeResourceConditions(source.resourceConditions)
        if not resources then return nil, prefix .. resourceError end
        row.resourceConditions = resources
        local health, healthError = SH.Model.NormalizeHealthConditions(source.healthConditions)
        if not health then return nil, prefix .. healthError end
        row.healthConditions = health
        local stacks, stackError = SH.Model.NormalizeStackConditions(source.stackConditions)
        if not stacks then return nil, prefix .. stackError end
        row.stackConditions = stacks
        row.logicConditions = {}
        if source.primaryCondition ~= nil then
            local primary, primaryError = SH.Model.NormalizePrimaryCondition(source.primaryCondition)
            if not primary then return nil, prefix .. primaryError end
            row.primaryCondition = primary
        end
        if source.logicConditions ~= nil then
            local logic, logicError = SH.Model.NormalizeLogicConditions(source.logicConditions)
            if not logic then return nil, prefix .. logicError end
            row.logicConditions = logic
        end
        -- Disabled drafts still have to fit the native reader's per-rule bounds.
        local totals = {resource = #resources, health = #health, stacks = #stacks, auraTime = 0}
        if row.primaryCondition and totals[row.primaryCondition.type] then
            totals[row.primaryCondition.type] = totals[row.primaryCondition.type] + 1
        end
        for _, item in ipairs(row.logicConditions) do
            if totals[item.type] then totals[item.type] = totals[item.type] + 1 end
        end
        for kind, count in pairs(totals) do
            if count > 8 then return nil, prefix .. "use at most 8 " .. kind .. " conditions across all operators." end
        end
        if type(row.castCountCondition) ~= "string" or #row.castCountCondition > 40 then
            return nil, prefix .. "invalid cast-count condition."
        end
        local extraCount = 0
        for _, group in ipairs(groups) do
            local entries = source[group] == nil and {} or source[group]
            local count
            count, err = listSize(entries, SH.Model.MAX_EXTRA_CONDITIONS, group)
            if not count then return nil, prefix .. err end
            extraCount = extraCount + count
            if extraCount > SH.Model.MAX_EXTRA_CONDITIONS then return nil, prefix .. "use at most 8 additional AND / OR / NOT conditions." end
            row[group] = {}
            for conditionIndex = 1, count do
                local item = entries[conditionIndex]
                if type(item) ~= "table" then return nil, prefix .. "invalid added condition." end
                local aura
                aura, err = name(item.aura, item.auraSource == "cooldown" and "Spell" or "Aura")
                if not aura then return nil, prefix .. err end
                row[group][conditionIndex] = {
                    aura = aura,
                    auraSource = item.auraSource == nil and "tracker" or item.auraSource,
                    condition = item.condition == nil and "present" or item.condition,
                }
                local condition = row[group][conditionIndex]
                for _, field in ipairs({"auraSource", "condition"}) do
                    if type(condition[field]) ~= "string" or #condition[field] > 16 or condition[field]:find("%c") then
                        return nil, prefix .. "Invalid " .. field .. " in an added condition."
                    end
                end
                if not auraSources[condition.auraSource] and condition.auraSource ~= "cooldown" then
                    return nil, prefix .. "Choose a valid source for the added condition."
                end
                if condition.condition ~= "present" and condition.condition ~= "missing" then
                    return nil, prefix .. "Choose present or missing for the added condition."
                end
                if condition.auraSource == "cooldown" and condition.aura == "" then
                    return nil, prefix .. "Enter the spell for the added cooldown condition."
                end
            end
        end
        if row.enabled and not SH.Model.GetCountCondition(row) then return nil, prefix .. "The cast-count condition no longer exists. Select an existing condition." end
        result.rules[index] = row
    end
    if size > 0 then
        -- Validation does not depend on the recipient's spellbook or trackers.
        -- Prepare performs those local checks after the imported draft is reviewed.
        local normalized
        normalized, err = SH.Model.NormalizeRules(result.rules, function(spell, rankID)
            return {cast = spell, name = spell, id = rankID or tonumber(spell)}
        end)
        if not normalized then return nil, err end
    end
    return result
end

local function serialize(data, version)
    local tokens = {}
    local function add(value)
        local text = tostring(value)
        tokens[#tokens + 1] = #text .. ":" .. text .. ","
    end
    local function addTyped(item)
        add(item.type)
        if item.type == "comboPoints" or item.type == "hawkCount" then
            add(item.operator); add(item.value)
        elseif item.type == "resource" then
            add(item.resource); add(item.operator); add(item.percent)
        elseif item.type == "health" then
            add(item.unit); add(item.operator); add(item.percent)
        elseif item.type == "stacks" then
            add(item.aura); add(item.auraSource); add(item.operator); add(item.value)
        elseif item.type == "auraTime" then
            add(item.aura); add(item.unit); add(item.operator); add(item.seconds)
        elseif item.type == "totemCondition" or item.type == "customCondition" then
            add(item.value)
        end
    end
    add(data.preventClipping and "1" or "0")
    add(#data.rules)
    for _, row in ipairs(data.rules) do
        for _, key in ipairs({"spell", "aura", "condition", "unit"}) do add(row[key]) end
        add(row.rankID or "")
        add(row.auraSource)
        add(row.useOr and "1" or "0")
        add(row.orAura)
        add(row.orCondition)
        add(row.orAuraSource)
        for _, key in ipairs({"skipCooldown", "oncePerProc", "stopCasting", "stopWhenInvalid"}) do add(row[key] and "1" or "0") end
        add(row.castCount)
        add(row.castCountCondition)
        for _, group in ipairs(groups) do
            add(#row[group])
            for _, item in ipairs(row[group]) do
                add(item.aura)
                add(item.auraSource)
                add(item.condition)
            end
        end
        if version >= 2 then
            add(row.comboPoints and row.comboPoints.operator or "")
            add(row.comboPoints and row.comboPoints.value or "")
        end
        if version >= 3 then
            add(#row.resourceConditions)
            for _, resource in ipairs(row.resourceConditions) do
                add(resource.resource)
                add(resource.operator)
                add(resource.percent)
            end
        end
        if version >= 4 then
            add(row.pingDelay and "1" or "0")
            add(row.pingDelayMS)
        end
        if version >= 5 then
            add(row.manualCooldown and "1" or "0")
            add(string.format("%.3f", row.manualCooldownSeconds):gsub("0+$", ""):gsub("%.$", ""))
        end
        if version >= 6 then
            add(row.enabled and "1" or "0")
            add(row.customTarget or "")
            add(row.customCondition ~= nil and "1" or "0")
            if row.customCondition ~= nil then add(row.customCondition) end
        end
        if version >= 7 then add(row.targetCasting and "1" or "0") end
        if version >= 8 then add(row.skipIfNotCasted and "1" or "0") end
        if version >= 9 then add(row.totemCondition or "") end
        if version >= 11 then add(row.skipOutOfRange and "1" or "0") end
        if version >= 13 then add(row.outOfCombatOnly and "1" or "0") end
        if version >= 14 then add(row.advanceOnToggle and "1" or "0") end
        if version >= 15 then
            add(row.hawkCount and row.hawkCount.operator or "")
            add(row.hawkCount and row.hawkCount.value or "")
        end
        if version >= 16 then
            add(row.skipModifier or "")
            add(row.priorityModifier or "")
        end
        if version >= 18 then add(row.inCombatOnly and "1" or "0") end
        if version >= 19 then
            add(#row.healthConditions)
            for _, health in ipairs(row.healthConditions) do
                add(health.operator)
                add(health.percent)
                if version >= 20 then add(health.unit or "target") end
            end
        end
        if version >= 21 then
            add(#row.stackConditions)
            for _, stacks in ipairs(row.stackConditions) do
                add(stacks.aura)
                add(stacks.auraSource)
                add(stacks.operator)
                add(stacks.value)
            end
        end
        if version >= 22 then
            add(row.primaryCondition and "1" or "0")
            if row.primaryCondition then addTyped(row.primaryCondition) end
            add(#row.logicConditions)
            for _, item in ipairs(row.logicConditions) do
                add(item.logic)
                addTyped(item)
            end
        end
        if version >= 24 then add(row.skipIfImmune and "1" or "0") end
        if version >= 25 then
            add(row.customRule ~= nil and "1" or "0")
            if row.customRule ~= nil then add(row.customRule) end
        end
    end
    return table.concat(tokens)
end

function Transfer.Encode(rules, preventClipping)
    local data, err = validate(rules, preventClipping)
    if not data then return nil, err end
    local version = 1
    for _, row in ipairs(data.rules) do
        if row.customRule ~= nil then version = math.max(version, 25) end
        if row.skipIfImmune then version = math.max(version, 24) end
        if row.primaryCondition or #row.logicConditions > 0 then version = math.max(version, 22) end
        if SH.Model.HasLogicType(row, "auraTime") then version = math.max(version, 23) end
        if #row.stackConditions > 0 then version = math.max(version, 21) end
        if #row.healthConditions > 0 then version = math.max(version, 19) end
        for _, health in ipairs(row.healthConditions) do
            if health.unit == "player" then version = math.max(version, 20) end
        end
        if row.inCombatOnly then version = math.max(version, 18) end
        if hasSpellCooldown(row) then version = math.max(version, 17) end
        if row.skipModifier or row.priorityModifier then version = math.max(version, 16) end
        if row.hawkCount then version = math.max(version, 15) end
        if row.advanceOnToggle then version = math.max(version, 14) end
        if row.outOfCombatOnly then version = math.max(version, 13) end
        -- New element conditions must not import into a fire-only build.
        if row.totemCondition and row.totemCondition:find("-", 1, true) then
            version = math.max(version, 12)
        end
        if row.skipOutOfRange then
            version = math.max(version, 11)
        elseif SH.Model.IsAutoAttack(row.spell) then
            -- Older clients may resolve this command as a normal, toggling spell.
            version = math.max(version, 10)
        elseif row.totemCondition then
            version = math.max(version, 9)
        elseif row.skipIfNotCasted then
            version = math.max(version, 8)
        elseif row.targetCasting then
            version = math.max(version, 7)
        elseif not row.enabled or row.unit == "custom" or row.unit == "focustarget"
            or row.customCondition ~= nil or (row.customTarget and row.customTarget ~= "") then
            version = math.max(version, 6)
        elseif row.manualCooldown or row.manualCooldownSeconds ~= 0 then version = math.max(version, 5)
        elseif row.pingDelay or row.pingDelayMS ~= 100 then version = math.max(version, 4)
        elseif #row.resourceConditions > 0 then version = math.max(version, 3)
        elseif row.comboPoints then version = math.max(version, 2) end
    end
    local payload = serialize(data, version)
    if #payload > MAX_PAYLOAD then return nil, "This rotation is too large to export." end
    return "SNH" .. version .. ":" .. encode64(payload) .. ":" .. checksum(payload)
end

local function parse(payload, version)
    local position = 1
    local function take(maximum)
        local colon = payload:find(":", position, true)
        if not colon or colon - position > 6 then error("Invalid rotation data. Copy the entire export text.", 0) end
        local lengthText = payload:sub(position, colon - 1)
        if not lengthText:match("^%d+$") then error("Invalid rotation field length.", 0) end
        local length = tonumber(lengthText)
        if not length or length > maximum or payload:sub(colon + length + 1, colon + length + 1) ~= "," then
            error("Invalid or incomplete rotation field.", 0)
        end
        local value = payload:sub(colon + 1, colon + length)
        position = colon + length + 2
        return value
    end
    local function number(minimum, maximum, optional)
        local text = take(10)
        if text == "" and optional then return nil end
        if not text:match("^%d+$") then error("Invalid rotation number.", 0) end
        local value = tonumber(text)
        if not integer(value, minimum, maximum) then error("Rotation number is outside the supported range.", 0) end
        return value
    end
    local function boolean()
        local value = take(1)
        if value ~= "0" and value ~= "1" then error("Invalid rotation toggle.", 0) end
        return value == "1"
    end
    local function seconds()
        local text = take(9)
        if not text:match("^%d+$") and not text:match("^%d+%.%d%d?%d?$") then
            error("Manual cooldown must use seconds with at most 3 decimal places.", 0)
        end
        local value = tonumber(text)
        if not value or value < 0 or value > 86400 then
            error("Manual cooldown must be between 0 and 86400 seconds.", 0)
        end
        return value
    end
    local function typed()
        local item = {type = take(16)}
        if item.type == "comboPoints" or item.type == "hawkCount" then
            item.operator = take(2)
            item.value = number(0, item.type == "comboPoints" and 5 or 2)
        elseif item.type == "resource" then
            item.resource = take(6); item.operator = take(2); item.percent = number(0, 100)
        elseif item.type == "health" then
            item.unit = take(6); item.operator = take(2); item.percent = number(0, 100)
        elseif item.type == "stacks" then
            item.aura = take(MAX_NAME); item.auraSource = take(6); item.operator = take(2); item.value = number(0, 99)
        elseif item.type == "auraTime" then
            if version < 23 then error("Aura time remaining requires export version SNH23 or newer.", 0) end
            item.aura = take(MAX_NAME); item.unit = take(6); item.operator = take(2); item.seconds = number(0, 60)
        elseif item.type == "totemCondition" then
            item.value = take(13)
        elseif item.type == "customCondition" then
            item.value = take(255)
        elseif item.type ~= "targetCasting" then
            error("Unknown condition type.", 0)
        end
        return item
    end
    local data = {preventClipping = boolean(), rules = {}}
    local ruleCount = number(0, SH.Model.MAX_RULES)
    for index = 1, ruleCount do
        local row = {}
        for _, key in ipairs({"spell", "aura", "condition", "unit"}) do row[key] = take(MAX_NAME) end
        row.rankID = number(1, MAX_ID, true)
        row.auraSource = take(16)
        row.useOr = boolean()
        row.orAura = take(MAX_NAME)
        row.orCondition = take(16)
        row.orAuraSource = take(16)
        for _, key in ipairs({"skipCooldown", "oncePerProc", "stopCasting", "stopWhenInvalid"}) do row[key] = boolean() end
        row.castCount = number(0, 99)
        row.castCountCondition = take(40)
        local extras = 0
        for _, group in ipairs(groups) do
            local count = number(0, SH.Model.MAX_EXTRA_CONDITIONS)
            extras = extras + count
            if extras > SH.Model.MAX_EXTRA_CONDITIONS then error("Use at most 8 additional AND / OR / NOT conditions per rule.", 0) end
            row[group] = {}
            for itemIndex = 1, count do
                row[group][itemIndex] = {aura = take(MAX_NAME), auraSource = take(16), condition = take(16)}
            end
        end
        if version >= 2 then
            local operator = take(4)
            local value = number(0, 5, true)
            if operator ~= "" or value ~= nil then row.comboPoints = {operator = operator, value = value} end
        end
        if version >= 3 then
            row.resourceConditions = {}
            local count = number(0, SH.Model.MAX_RESOURCE_CONDITIONS)
            for resourceIndex = 1, count do
                row.resourceConditions[resourceIndex] = {resource = take(8), operator = take(4), percent = number(0, 100)}
            end
        end
        if version >= 4 then
            row.pingDelay = boolean()
            row.pingDelayMS = number(1, 5000)
        end
        if version >= 5 then
            row.manualCooldown = boolean()
            row.manualCooldownSeconds = seconds()
        end
        if version >= 6 then
            row.enabled = boolean()
            local target = take(255)
            if target ~= "" then row.customTarget = target end
            if boolean() then row.customCondition = take(255) end
        end
        if version >= 7 then row.targetCasting = boolean() end
        if version >= 8 then row.skipIfNotCasted = boolean() end
        if version >= 9 then
            local condition = take(version >= 12 and 13 or 7)
            if condition ~= "" then row.totemCondition = condition end
        end
        if version >= 11 then row.skipOutOfRange = boolean() end
        if version >= 13 then row.outOfCombatOnly = boolean() end
        if version >= 14 then row.advanceOnToggle = boolean() end
        if version >= 15 then
            local operator = take(4)
            local value = number(0, 2, true)
            if operator ~= "" or value ~= nil then row.hawkCount = {operator = operator, value = value} end
        end
        if version >= 16 then
            for _, field in ipairs({"skipModifier", "priorityModifier"}) do
                local modifier = take(5)
                if modifier ~= "" then row[field] = modifier end
            end
        end
        if version >= 18 then row.inCombatOnly = boolean() end
        if version >= 19 then
            row.healthConditions = {}
            local count = number(0, SH.Model.MAX_HEALTH_CONDITIONS)
            for healthIndex = 1, count do
                row.healthConditions[healthIndex] = {operator = take(4), percent = number(0, 100)}
                if version >= 20 then
                    local unit = take(6)
                    if unit ~= "target" and unit ~= "player" then
                        error("Choose Enemy health or Self health for the health condition.", 0)
                    end
                    row.healthConditions[healthIndex].unit = unit
                end
            end
        end
        if version >= 21 then
            row.stackConditions = {}
            local count = number(0, SH.Model.MAX_STACK_CONDITIONS)
            for stackIndex = 1, count do
                row.stackConditions[stackIndex] = {aura = take(MAX_NAME), auraSource = take(6), operator = take(2), value = number(0, 99)}
            end
        end
        if version >= 22 then
            if boolean() then row.primaryCondition = typed() end
            row.logicConditions = {}
            local count = number(0, 8)
            for logicIndex = 1, count do
                local operation = take(3)
                if operation ~= "AND" and operation ~= "OR" and operation ~= "NOT" then error("Choose AND, OR, or NOT for an added condition.", 0) end
                local item = typed()
                item.logic = operation
                row.logicConditions[logicIndex] = item
            end
        end
        if version >= 24 then row.skipIfImmune = boolean() end
        if version >= 25 and boolean() then row.customRule = take(SH.Model.MAX_CUSTOM_RULE_BYTES) end
        data.rules[index] = row
    end
    if position ~= #payload + 1 then error("The rotation contains unexpected extra data.", 0) end
    return data
end

function Transfer.Decode(text)
    if type(text) ~= "string" then return nil, "Paste a Stand and Hit export first." end
    if #text > Transfer.MAX_TEXT then return nil, "The pasted rotation is too large (maximum 256 KiB)." end
    if text:match("^%s*$") then return nil, "Paste a Stand and Hit export first." end
    text = text:gsub("%s", "")
    local version, encoded, expected = text:match("^SNH(%d+):([A-Za-z0-9+/=]+):(%x%x%x%x%x%x%x%x)$")
    -- Keep only the explicit export import path from the previous addon.
    if not version then
        version, encoded, expected = text:match("^VIBE(%d+):([A-Za-z0-9+/=]+):(%x%x%x%x%x%x%x%x)$")
    end
    if not version then return nil, "This is not a complete Stand and Hit export. Copy the entire export text." end
    if not version:match("^[1-9]$") and version ~= "10" and version ~= "11" and version ~= "12" and version ~= "13" and version ~= "14" and version ~= "15" and version ~= "16" and version ~= "17" and version ~= "18" and version ~= "19" and version ~= "20" and version ~= "21" and version ~= "22" and version ~= "23" and version ~= "24" and version ~= "25" then return nil, "This rotation uses an unsupported export version. Update Stand and Hit before importing it." end
    local payload = decode64(encoded)
    if not payload then return nil, "Invalid rotation encoding. Copy the entire export text again." end
    if checksum(payload) ~= expected:lower() then return nil, "The rotation text is damaged or incomplete. Copy the entire export text again." end
    local ok, data = pcall(parse, payload, tonumber(version))
    if not ok then return nil, data end
    if tonumber(version) < 17 then
        for _, row in ipairs(data.rules) do
            if hasSpellCooldown(row) then return nil, "Spell cooldown conditions require export version SNH17 or newer." end
        end
    end
    return validate(data.rules, data.preventClipping)
end

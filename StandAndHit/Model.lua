local _, SH = ...
local Model = {}
SH.Model = Model
Model.MAX_RULES = 32
Model.MAX_EXTRA_CONDITIONS = 8
Model.MAX_RESOURCE_CONDITIONS = 8
Model.MAX_HEALTH_CONDITIONS = 8
Model.MAX_STACK_CONDITIONS = 8
Model.MAX_AURA_TIME_CONDITIONS = 8
Model.MAX_LOGIC_CONDITIONS = 8
local comboOperators = {ge = ">=", le = "<=", eq = "==", ne = "~="}
local hawkOperators = {lt = "<", le = "<=", eq = "==", ne = "~=", ge = ">=", gt = ">"}
local resourceOperators = {lt = true, ge = true}
local resourceTypes = {mana = true, rage = true, energy = true}
local auraSources = {tracker = true, target = true, player = true}
local modifiers = {ctrl = true, alt = true, shift = true}
Model.MAX_CUSTOM_RULE_BYTES = 1023
Model.MAX_CUSTOM_RULE_LINES = 16
local customCommands = {
    target = true, targetexact = true, targetenemy = true, targetenemyplayer = true,
    targetfriend = true, targetfriendplayer = true, targetparty = true, targetraid = true,
    targetlasttarget = true, targetlastenemy = true, targetlastfriend = true, cleartarget = true,
    assist = true, focus = true, clearfocus = true, startattack = true, stopattack = true,
    petattack = true, petfollow = true, petstay = true, petpassive = true, petdefensive = true,
    petassist = true, cast = true, use = true, cancelaura = true, cancelform = true,
    stopcasting = true, cancelqueuedspell = true,
}
local targetCommands = {
    target = true, targetexact = true, targetenemy = true, targetenemyplayer = true,
    targetfriend = true, targetfriendplayer = true, targetparty = true, targetraid = true,
    targetlasttarget = true, targetlastenemy = true, targetlastfriend = true, cleartarget = true,
    assist = true,
}

function Model.IsCustomRule(row)
    return type(row) == "table" and row.customRule ~= nil
end

function Model.GetCustomRuleCommands()
    local commands = {}
    for command in pairs(customCommands) do commands[#commands + 1] = "/" .. command end
    table.sort(commands)
    return commands
end

function Model.NormalizeCustomRule(value)
    if type(value) ~= "string" then return nil, "Enter macro commands for Custom Rule." end
    if #value > Model.MAX_CUSTOM_RULE_BYTES then return nil, "Custom Rule supports up to 1023 bytes." end
    value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
    if value:find("[%z\1-\8\11\12\14-\31\127]") then return nil, "Custom Rule contains an invalid control character." end
    local result, changesTarget = {}, false
    for line in (value .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
        if line ~= "" then
            local command, arguments = line:match("^/([%a]+)(.*)$")
            command = command and command:lower()
            if not command or not customCommands[command] or arguments ~= "" and not arguments:match("^[ \t]") then
                return nil, "Custom Rule line " .. (#result + 1) .. ": use a supported macro command. Open Custom Rule examples for the list."
            end
            result[#result + 1] = "/" .. command .. arguments
            if #result > Model.MAX_CUSTOM_RULE_LINES then return nil, "Custom Rule supports up to 16 command lines." end
            changesTarget = changesTarget or targetCommands[command] == true
        end
    end
    if #result == 0 then return nil, "Enter at least one macro command, such as /targetenemy [noexists][dead]." end
    return table.concat(result, "\n"), nil, changesTarget
end
local fireSlotMatches = {
    missing = 'fireSlot=="missing"',
    active = '(fireSlot=="searing" or fireSlot=="magma")',
    searing = 'fireSlot=="searing"',
    magma = 'fireSlot=="magma"',
    ["fire-active"] = '(fireSlot=="searing" or fireSlot=="magma" or fireSlot=="other")',
}
local totemElements = {missing = "fire", active = "fire", searing = "fire", magma = "fire", ["fire-active"] = "fire"}
for _, element in ipairs({"earth", "water", "air"}) do
    totemElements[element .. "-active"] = element
    totemElements[element .. "-missing"] = element
    fireSlotMatches[element .. "-active"] = element .. 'Slot=="other"'
    fireSlotMatches[element .. "-missing"] = element .. 'Slot=="missing"'
end

function Model.IsTotemCondition(value)
    return type(value) == "string" and fireSlotMatches[value] ~= nil
end

function Model.TotemConditionElement(value)
    return type(value) == "string" and totemElements[value] or nil
end

function Model.NormalizeModifier(value)
    if value == nil then return nil end
    if type(value) ~= "string" or not modifiers[value] then
        return nil, "Choose Ctrl, Alt, or Shift, or leave the modifier off."
    end
    return value
end

function Model.NormalizeManualCooldownSeconds(value, enabled)
    if enabled ~= nil and type(enabled) ~= "boolean" then return nil, "Manual cooldown must be on or off." end
    if value == nil then value = 0 end
    if type(value) ~= "number" or value ~= value or value < 0 or value > 86400 then
        return nil, "Manual cooldown must be a number of seconds from 0.001 to 86400."
    end
    local milliseconds = value * 1000
    if math.abs(milliseconds - math.floor(milliseconds + 0.5)) > 0.0000001 then
        return nil, "Manual cooldown supports up to three decimal places."
    end
    if enabled and value < 0.001 then return nil, "Enter the manual cooldown in seconds (0.001 to 86400)." end
    return value
end

function Model.NormalizeResourceConditions(value)
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "Resource conditions must be a numbered list." end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > Model.MAX_RESOURCE_CONDITIONS or key % 1 ~= 0 then
            return nil, "Use at most 8 resource conditions in a numbered list."
        end
        count = count + 1
    end
    local result = {}
    for index = 1, count do
        local item = value[index]
        local prefix = "Resource condition " .. index .. ": "
        if type(item) ~= "table" then return nil, prefix .. "choose a resource, comparison, and percentage." end
        for key in pairs(item) do
            if key ~= "resource" and key ~= "operator" and key ~= "percent" then return nil, prefix .. "unknown setting." end
        end
        if type(item.resource) ~= "string" or not resourceTypes[item.resource] then return nil, prefix .. "choose Mana, Rage, or Energy." end
        if type(item.operator) ~= "string" or not resourceOperators[item.operator] then return nil, prefix .. "choose Below (<) or At least (>=)." end
        if type(item.percent) ~= "number" or item.percent < 0 or item.percent > 100 or item.percent % 1 ~= 0 then
            return nil, prefix .. "choose a whole percentage from 0 to 100."
        end
        result[index] = {resource = item.resource, operator = item.operator, percent = item.percent}
    end
    return result
end

function Model.ResourceRequests(rules)
    local result = {}
    for index, row in ipairs(rules) do
        local normalized, reason = Model.NormalizeResourceConditions(row.resourceConditions)
        if not normalized then return nil, "Rule " .. index .. ": " .. reason end
        local primary, primaryError = Model.NormalizePrimaryCondition(row.primaryCondition)
        if primaryError then return nil, "Rule " .. index .. ": " .. primaryError end
        if primary and primary.type == "resource" then normalized[#normalized + 1] = {resource = primary.resource, operator = primary.operator, percent = primary.percent} end
        local logic, logicError = Model.NormalizeLogicConditions(row.logicConditions)
        if not logic then return nil, "Rule " .. index .. ": " .. logicError end
        for _, item in ipairs(logic) do
            if item.type == "resource" then normalized[#normalized + 1] = {resource = item.resource, operator = item.operator, percent = item.percent} end
        end
        if #normalized > Model.MAX_RESOURCE_CONDITIONS then return nil, "Rule " .. index .. ": use at most 8 resource conditions across all operators." end
        for _, item in ipairs(normalized) do result[#result + 1] = item end
    end
    return result
end

function Model.NormalizeHealthConditions(value)
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "Health conditions must be a numbered list." end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > Model.MAX_HEALTH_CONDITIONS or key % 1 ~= 0 then
            return nil, "Use at most 8 health conditions in a numbered list."
        end
        count = count + 1
    end
    local result = {}
    for index = 1, count do
        local item = value[index]
        local prefix = "Health condition " .. index .. ": "
        if type(item) ~= "table" then return nil, prefix .. "choose a comparison and percentage." end
        for key in pairs(item) do
            if key ~= "operator" and key ~= "percent" and key ~= "unit" then return nil, prefix .. "unknown setting." end
        end
        if item.unit ~= nil and item.unit ~= "target" and item.unit ~= "player" then
            return nil, prefix .. "choose Enemy health or Self health."
        end
        if type(item.operator) ~= "string" or not resourceOperators[item.operator] then
            return nil, prefix .. "choose Below (<) or At least (>=)."
        end
        if type(item.percent) ~= "number" or item.percent < 0 or item.percent > 100 or item.percent % 1 ~= 0 then
            return nil, prefix .. "choose a whole percentage from 0 to 100."
        end
        result[index] = {operator = item.operator, percent = item.percent, unit = item.unit == "player" and "player" or nil}
    end
    return result
end

function Model.HealthRequests(rules)
    local result = {}
    for index, row in ipairs(rules) do
        local normalized, reason = Model.NormalizeHealthConditions(row.healthConditions)
        if not normalized then return nil, "Rule " .. index .. ": " .. reason end
        local primary, primaryError = Model.NormalizePrimaryCondition(row.primaryCondition)
        if primaryError then return nil, "Rule " .. index .. ": " .. primaryError end
        if primary and primary.type == "health" then normalized[#normalized + 1] = {unit = primary.unit == "player" and "player" or nil, operator = primary.operator, percent = primary.percent} end
        local logic, logicError = Model.NormalizeLogicConditions(row.logicConditions)
        if not logic then return nil, "Rule " .. index .. ": " .. logicError end
        for _, item in ipairs(logic) do
            if item.type == "health" then normalized[#normalized + 1] = {unit = item.unit == "player" and "player" or nil, operator = item.operator, percent = item.percent} end
        end
        if #normalized > Model.MAX_HEALTH_CONDITIONS then return nil, "Rule " .. index .. ": use at most 8 health conditions across all operators." end
        for _, item in ipairs(normalized) do result[#result + 1] = item end
    end
    return result
end

function Model.NormalizeStackConditions(value)
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "Aura stack conditions must be a numbered list." end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > Model.MAX_STACK_CONDITIONS or key % 1 ~= 0 then
            return nil, "Use at most 8 aura stack conditions in a numbered list."
        end
        count = count + 1
    end
    local result = {}
    for index = 1, count do
        local item, prefix = value[index], "Aura stacks condition " .. index .. ": "
        if type(item) ~= "table" then return nil, prefix .. "choose an aura, source, comparison, and stack count." end
        for key in pairs(item) do
            if key ~= "aura" and key ~= "auraSource" and key ~= "operator" and key ~= "value" then
                return nil, prefix .. "unknown setting."
            end
        end
        if type(item.aura) ~= "string" or #item.aura > 200 or item.aura:find("[%z\1-\31\127]") then
            return nil, prefix .. "enter an aura name or ID, up to 200 characters."
        end
        local aura = Model.Trim(item.aura)
        if aura == "" then return nil, prefix .. "enter the aura name or ID." end
        if item.auraSource ~= "player" and item.auraSource ~= "target" then
            return nil, prefix .. "choose Player buff or Target debuff."
        end
        if type(item.operator) ~= "string" or not hawkOperators[item.operator] then
            return nil, prefix .. "choose a stack comparison."
        end
        if type(item.value) ~= "number" or item.value < 0 or item.value > 99 or item.value % 1 ~= 0 then
            return nil, prefix .. "choose a whole stack count from 0 to 99."
        end
        result[index] = {aura = aura, auraSource = item.auraSource, operator = item.operator, value = item.value}
    end
    return result
end

function Model.StackRequests(rules)
    local result = {}
    for index, row in ipairs(rules) do
        local normalized, reason = Model.NormalizeStackConditions(row.stackConditions)
        if not normalized then return nil, "Rule " .. index .. ": " .. reason end
        local primary, primaryError = Model.NormalizePrimaryCondition(row.primaryCondition)
        if primaryError then return nil, "Rule " .. index .. ": " .. primaryError end
        if primary and primary.type == "stacks" then normalized[#normalized + 1] = {aura = primary.aura, auraSource = primary.auraSource, operator = primary.operator, value = primary.value} end
        local logic, logicError = Model.NormalizeLogicConditions(row.logicConditions)
        if not logic then return nil, "Rule " .. index .. ": " .. logicError end
        for _, item in ipairs(logic) do
            if item.type == "stacks" then normalized[#normalized + 1] = {aura = item.aura, auraSource = item.auraSource, operator = item.operator, value = item.value} end
        end
        if #normalized > Model.MAX_STACK_CONDITIONS then return nil, "Rule " .. index .. ": use at most 8 aura stack conditions across all operators." end
        for _, item in ipairs(normalized) do result[#result + 1] = item end
    end
    return result
end

function Model.NormalizeAuraTimeCondition(value)
    if type(value) ~= "table" then return nil, "Choose an aura, source, comparison, and number of seconds." end
    for key in pairs(value) do
        if key ~= "aura" and key ~= "unit" and key ~= "operator" and key ~= "seconds" then
            return nil, "Aura time remaining contains an unknown setting."
        end
    end
    if type(value.aura) ~= "string" or #value.aura > 200 or value.aura:find("[%z\1-\31\127]") then
        return nil, "Enter an aura name or ID, up to 200 characters."
    end
    local aura = Model.Trim(value.aura)
    if aura == "" then return nil, "Enter the aura name or ID for Aura time remaining." end
    if value.unit ~= "player" and value.unit ~= "target" then
        return nil, "Choose Player buff or Target debuff for Aura time remaining."
    end
    if type(value.operator) ~= "string" or not hawkOperators[value.operator] then
        return nil, "Choose a comparison for Aura time remaining."
    end
    if type(value.seconds) ~= "number" or value.seconds < 0 or value.seconds > 60 or value.seconds % 1 ~= 0 then
        return nil, "Aura time remaining must use whole seconds from 0 to 60."
    end
    return {aura = aura, unit = value.unit, operator = value.operator, seconds = value.seconds}
end

function Model.AuraTimeRequests(rules)
    local result = {}
    for index, row in ipairs(rules) do
        local primary, primaryError = Model.NormalizePrimaryCondition(row.primaryCondition)
        if primaryError then return nil, "Rule " .. index .. ": " .. primaryError end
        local logic, logicError = Model.NormalizeLogicConditions(row.logicConditions)
        if not logic then return nil, "Rule " .. index .. ": " .. logicError end
        local count = 0
        local function add(item)
            if item and item.type == "auraTime" then
                count = count + 1
                result[#result + 1] = {aura = item.aura, unit = item.unit, operator = item.operator, seconds = item.seconds}
            end
        end
        add(primary)
        for _, item in ipairs(logic) do add(item) end
        if count > Model.MAX_AURA_TIME_CONDITIONS then
            return nil, "Rule " .. index .. ": use at most 8 aura time conditions across all operators."
        end
        if #result > 256 then return nil, "Use at most 256 aura time conditions per rotation." end
    end
    return result
end

function Model.NormalizeComboPoints(value)
    if value == nil then return nil end
    if type(value) ~= "table" then return nil, "Combo points must contain a comparison and a number." end
    for key in pairs(value) do
        if key ~= "operator" and key ~= "value" then return nil, "Combo points contains an unknown setting." end
    end
    if type(value.operator) ~= "string" or not comboOperators[value.operator] then
        return nil, "Choose At least, At most, Equal to, or Not equal to for Combo points."
    end
    if type(value.value) ~= "number" or value.value < 0 or value.value > 5 or value.value % 1 ~= 0 then
        return nil, "Combo points must be a whole number from 0 to 5."
    end
    return {operator = value.operator, value = value.value}
end

function Model.NormalizeHawkCount(value)
    if value == nil then return nil end
    if type(value) ~= "table" then return nil, "Hawk conditions must contain a comparison and a number." end
    for key in pairs(value) do
        if key ~= "operator" and key ~= "value" then return nil, "Hawk conditions contains an unknown setting." end
    end
    if type(value.operator) ~= "string" or not hawkOperators[value.operator] then
        return nil, "Choose a valid comparison for Hawk conditions."
    end
    if type(value.value) ~= "number" or value.value < 0 or value.value > 2 or value.value % 1 ~= 0 then
        return nil, "Hawk count must be a whole number from 0 to 2."
    end
    return {operator = value.operator, value = value.value}
end

function Model.Trim(value)
    if type(value) ~= "string" and type(value) ~= "number" then return "" end
    return tostring(value):match("^%s*(.-)%s*$")
end

function Model.NormalizeMacroTarget(value, conditionUnit)
    if type(value) == "string" and #value <= 100 and not value:find("%c") then
        local target = Model.Trim(value)
        if target:lower() == "@cursor" and not conditionUnit then
            return nil, "@cursor places a spell on the ground. Choose a unit for this Hit Button."
        end
        if target:lower():match("^@nameplate%d") then
            return nil, "Numbered nameplates are UI units. Use a macro target such as @mouseover."
        end
        -- Native unit IDs and party/raid member names (including Name-Realm).
        if target:match("^@[%a\128-\255][%w'%-\128-\255]*$") then
            return target:lower() == "@none" and "@none" or target
        end
    end
    return nil, "Enter one macro target, such as @focus or @party2target."
end

function Model.NormalizeMacroCondition(value)
    if type(value) ~= "string" or #value > 254 or value:find("[%c;|]") then
        return nil, "Enter only bracketed macro conditions, up to 254 characters."
    end
    local expression = Model.Trim(value)
    if expression == "" then return nil, "Enter a macro condition, such as [harm,nodead]." end
    local rest = expression
    while rest ~= "" do
        local block, tail = rest:match("^%[([^%[%]]*)%]%s*(.*)$")
        if not block then return nil, "Use bracketed macro conditions, such as [harm,nodead] or [mod:shift][combat]." end
        -- Adjacent brackets are alternatives. An empty [] is WoW's fallback.
        if Model.Trim(block) ~= "" then
            for word in (block .. ","):gmatch("(.-),") do
                local token = Model.Trim(word)
                local unit = token:match("^@(.+)$") or token:match("^[Tt][Aa][Rr][Gg][Ee][Tt]=(.+)$")
                if unit then
                    local target, reason = Model.NormalizeMacroTarget("@" .. unit, true)
                    if not target then return nil, reason end
                else
                    local keyword, argument = token:match("^(%a[%w]*):(.+)$")
                    keyword = keyword or token:match("^(%a[%w]*)$")
                    if not keyword or (argument and (argument:match("^%s*/") or argument:match("/%s*$")
                        or argument:match("/%s*/") or argument:find("[=@\\]") or Model.Trim(argument) == "")) then
                        return nil, "Invalid macro condition. Try [harm,nodead] or [mod:shift/ctrl]."
                    end
                    if SH.MacroReference and not SH.MacroReference.IsCondition(keyword) then
                        return nil, "Unknown macro condition '" .. keyword .. "'. See Examples in Advanced."
                    end
                end
            end
        end
        rest = tail
    end
    return expression
end

local logicFields = {
    comboPoints = {operator = true, value = true},
    resource = {resource = true, operator = true, percent = true},
    health = {unit = true, operator = true, percent = true},
    stacks = {aura = true, auraSource = true, operator = true, value = true},
    auraTime = {aura = true, unit = true, operator = true, seconds = true},
    targetCasting = {}, totemCondition = {value = true},
    hawkCount = {operator = true, value = true}, customCondition = {value = true},
}

function Model.NormalizeLogicConditions(value)
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "Added conditions must be a numbered list." end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > Model.MAX_LOGIC_CONDITIONS or key % 1 ~= 0 then
            return nil, "Use at most 8 added conditions in a numbered list."
        end
        count = count + 1
    end
    local result = {}
    for index = 1, count do
        local item, prefix = value[index], "Added condition " .. index .. ": "
        if type(item) ~= "table" then return nil, prefix .. "choose AND, OR, or NOT and a condition type." end
        if item.logic ~= "AND" and item.logic ~= "OR" and item.logic ~= "NOT" then return nil, prefix .. "choose AND, OR, or NOT." end
        local fields = type(item.type) == "string" and logicFields[item.type]
        if not fields then return nil, prefix .. "choose a supported condition type." end
        local payload = {}
        for key, setting in pairs(item) do
            if key ~= "logic" and key ~= "type" then
                if not fields[key] then return nil, prefix .. "unknown setting." end
                payload[key] = setting
            end
        end
        local normalized, reason
        if item.type == "comboPoints" then normalized, reason = Model.NormalizeComboPoints(payload)
        elseif item.type == "hawkCount" then normalized, reason = Model.NormalizeHawkCount(payload)
        elseif item.type == "resource" then
            local list; list, reason = Model.NormalizeResourceConditions({payload}); normalized = list and list[1]
        elseif item.type == "health" then
            if payload.unit ~= "player" and payload.unit ~= "target" then return nil, prefix .. "choose Enemy health or Self health." end
            local list; list, reason = Model.NormalizeHealthConditions({payload}); normalized = list and list[1]
            if normalized then normalized.unit = payload.unit end
        elseif item.type == "stacks" then
            local list; list, reason = Model.NormalizeStackConditions({payload}); normalized = list and list[1]
        elseif item.type == "auraTime" then normalized, reason = Model.NormalizeAuraTimeCondition(payload)
        elseif item.type == "targetCasting" then normalized = {}
        elseif item.type == "totemCondition" then
            if not Model.IsTotemCondition(payload.value) then return nil, prefix .. "choose a valid totem condition." end
            normalized = {value = payload.value}
        elseif item.type == "customCondition" then
            local expression; expression, reason = Model.NormalizeMacroCondition(payload.value)
            if expression then normalized = {value = expression} end
        end
        if not normalized then return nil, prefix .. (reason or "invalid condition.") end
        normalized.logic, normalized.type = item.logic, item.type
        result[index] = normalized
    end
    return result
end

function Model.HasLogicType(row, kind)
    if type(row) ~= "table" then return false end
    if type(row.primaryCondition) == "table" and row.primaryCondition.type == kind then return true end
    if type(row.logicConditions) ~= "table" then return false end
    for _, item in ipairs(row.logicConditions) do
        if type(item) == "table" and item.type == kind then return true end
    end
    return false
end

function Model.NormalizePrimaryCondition(value)
    if value == nil then return nil end
    if type(value) ~= "table" then return nil, "IF: choose a condition type and its settings." end
    if value.logic ~= nil then return nil, "IF does not take AND, OR, or NOT." end
    local candidate = {}
    for key, setting in pairs(value) do candidate[key] = setting end
    candidate.logic = "AND"
    local normalized, reason = Model.NormalizeLogicConditions({candidate})
    if not normalized then return nil, "IF: " .. (reason or "invalid condition.") end
    local result = normalized[1]
    result.logic = nil
    return result
end

function Model.IsPetAttack(value)
    return Model.Trim(value):lower() == "pet attack"
end

function Model.IsAutoAttack(value)
    local text = Model.Trim(value):lower()
    return text == "auto attack" or text == "startattack" or text == "/startattack"
end

function Model.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = Model.Copy(item) end
    return copy
end

function Model.StopBranches(row)
    local condition = row.condition or "present"
    return row.primaryCondition == nil and condition == "present" and row.auraSource ~= "player",
        row.useOr == true and (condition ~= "always" or row.primaryCondition ~= nil) and row.orAuraSource ~= "player" and row.orAuraSource ~= "cooldown"
            and (row.orCondition or "present") == "present"
end

function Model.HasExtraConditions(row)
    return (type(row.andConditions) == "table" and next(row.andConditions) ~= nil) or
        (type(row.notConditions) == "table" and next(row.notConditions) ~= nil) or
        (type(row.orConditions) == "table" and next(row.orConditions) ~= nil)
end

-- Keys identify predicates independently of their displayed condition number.
-- The editor adjusts list keys when an earlier predicate is removed.
function Model.ConditionEntries(row)
    local entries = {}
    local function add(key, kind, aura, source, condition, group, index)
        local entry = {key = key, number = #entries + 1, kind = kind,
            aura = aura or "", auraSource = source == nil and "tracker" or source,
            condition = condition == nil and "present" or condition,
            group = group, index = index, countEligible = true}
        if entry.condition == "customCondition" or entry.condition == "targetCasting" or entry.condition == "totemCondition" then entry.countReason = "Cast counts require a tracked-aura condition."
        elseif entry.condition == "resource" then entry.countReason = "Cast counts cannot attach to resource conditions."
        elseif entry.condition == "health" then entry.countReason = "Cast counts cannot attach to health conditions."
        elseif entry.condition == "stacks" then entry.countReason = "Cast counts cannot attach to aura stack conditions."
        elseif entry.condition == "auraTime" then entry.countReason = "Cast counts cannot attach to aura time conditions."
        elseif entry.condition == "hawkCount" then entry.countReason = "Cast counts cannot attach to Hawk conditions."
        elseif entry.condition == "comboPoints" then entry.countReason = "Cast counts cannot attach to combo-point conditions."
        elseif kind == "NOT" then entry.countReason = "Cast counts cannot attach to NOT exclusions."
        elseif entry.condition == "cooldown" or entry.condition == "manualCooldown" or entry.auraSource == "cooldown" then entry.countReason = "Cast counts cannot attach to cooldown conditions."
        elseif entry.condition == "always" then entry.countReason = "Cast counts require a tracked-aura condition instead of Always or cooldown-only."
        elseif entry.auraSource == "target" then entry.countReason = "Cast counts cannot attach to target-debuff conditions."
        elseif entry.auraSource == "player" then entry.countReason = "Cast counts cannot attach to Player buff conditions."
        elseif entry.auraSource ~= "tracker" then entry.countReason = "Cast counts require a valid tracked-aura source."
        elseif entry.condition ~= "present" and entry.condition ~= "missing" then
            entry.countReason = "Cast counts require a present or missing tracked-aura condition."
        end
        entry.countEligible = entry.countReason == nil
        entries[#entries + 1] = entry
    end
    add("primary", "IF", row.aura, row.auraSource,
        row.manualCooldown == true and row.condition == "always" and "manualCooldown" or row.condition)
    if type(row.primaryCondition) == "table" then
        local item, entry = row.primaryCondition, entries[1]
        entry.condition, entry.type = item.type, item.type
        entry.aura, entry.auraSource = item.aura or "", item.auraSource
        entry.operator, entry.value, entry.percent, entry.resource, entry.unit = item.operator, item.value, item.percent, item.resource, item.unit
        entry.seconds = item.seconds
        if item.type == "customCondition" then entry.expression = item.value end
        entry.countEligible, entry.countReason = false, "Cast counts require a tracked-aura condition."
    end
    if entries[1].condition == "manualCooldown" then entries[1].seconds = row.manualCooldownSeconds or 0 end
    if row.useOr == true then add("or", "OR", row.orAura, row.orAuraSource, row.orCondition) end
    for _, group in ipairs({{"andConditions", "AND"}, {"orConditions", "OR"}, {"notConditions", "NOT"}}) do
        for index, item in ipairs(type(row[group[1]]) == "table" and row[group[1]] or {}) do
            if type(item) == "table" then
                add(group[1] .. ":" .. index, group[2], item.aura, item.auraSource, item.condition, group[1], index)
            else
                add(group[1] .. ":" .. index, group[2], "", false, false, group[1], index)
            end
        end
    end
    if row.manualCooldown == true and (row.condition ~= "always" or row.primaryCondition ~= nil) then
        add("manualCooldown", "AND", "", nil, "manualCooldown")
        entries[#entries].seconds = row.manualCooldownSeconds or 0
    elseif row.skipCooldown == true and not row.manualCooldown and (row.condition ~= "always" or row.primaryCondition ~= nil) then
        add("cooldown", "AND", "", nil, "cooldown")
    end
    if row.comboPoints ~= nil then
        add("comboPoints", "AND", "", nil, "comboPoints")
        if type(row.comboPoints) == "table" then
            entries[#entries].operator, entries[#entries].value = row.comboPoints.operator, row.comboPoints.value
        end
    end
    if row.hawkCount ~= nil then
        add("hawkCount", "AND", "", nil, "hawkCount")
        if type(row.hawkCount) == "table" then
            entries[#entries].operator, entries[#entries].value = row.hawkCount.operator, row.hawkCount.value
        end
    end
    for index, item in ipairs(type(row.resourceConditions) == "table" and row.resourceConditions or {}) do
        add("resourceConditions:" .. index, "AND", "", nil, "resource", "resourceConditions", index)
        if type(item) == "table" then
            entries[#entries].resource, entries[#entries].operator, entries[#entries].percent = item.resource, item.operator, item.percent
        end
    end
    for index, item in ipairs(type(row.healthConditions) == "table" and row.healthConditions or {}) do
        add("healthConditions:" .. index, "AND", "", nil, "health", "healthConditions", index)
        if type(item) == "table" then
            entries[#entries].operator, entries[#entries].percent = item.operator, item.percent
            entries[#entries].unit = item.unit or "target"
            entries[#entries].countReason = "Cast counts cannot attach to " .. (item.unit == "player" and "self" or "enemy") .. " health conditions."
        end
    end
    for index, item in ipairs(type(row.stackConditions) == "table" and row.stackConditions or {}) do
        if type(item) == "table" then
            add("stackConditions:" .. index, "AND", item.aura, item.auraSource, "stacks", "stackConditions", index)
            entries[#entries].operator, entries[#entries].value = item.operator, item.value
        else
            add("stackConditions:" .. index, "AND", "", nil, "stacks", "stackConditions", index)
        end
    end
    if row.customCondition ~= nil then
        add("customCondition", "AND", "", nil, "customCondition")
        entries[#entries].expression = row.customCondition
    end
    if row.targetCasting == true then add("targetCasting", "AND", "", nil, "targetCasting") end
    if row.totemCondition ~= nil then
        add("totemCondition", "AND", "", nil, "totemCondition")
        entries[#entries].value = row.totemCondition
    end
    for index, item in ipairs(type(row.logicConditions) == "table" and row.logicConditions or {}) do
        if type(item) == "table" then
            add("logicConditions:" .. index, item.logic, item.aura, item.auraSource, item.type, "logicConditions", index)
            local entry = entries[#entries]
            entry.type, entry.logic = item.type, item.logic
            entry.operator, entry.value, entry.percent, entry.resource, entry.unit = item.operator, item.value, item.percent, item.resource, item.unit
            entry.seconds = item.seconds
            if item.type == "customCondition" then entry.expression = item.value end
            entry.countEligible, entry.countReason = false, "Cast counts require a tracked-aura condition."
        end
    end
    return entries
end

function Model.GetCountCondition(row)
    local key = row.castCountCondition == nil and "primary" or row.castCountCondition
    for _, entry in ipairs(Model.ConditionEntries(row)) do
        if entry.key == key then return entry end
    end
end

local function normalizeExtraConditions(value, label)
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, label .. " conditions must be a list." end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return nil, label .. " conditions must be a numbered list."
        end
        count = count + 1
    end
    local normalized = {}
    for index = 1, count do
        local item = value[index]
        local prefix = label .. " condition " .. index .. ": "
        if type(item) ~= "table" then return nil, prefix .. "invalid condition." end
        if type(item.aura) ~= "string" or Model.Trim(item.aura) == "" then
            return nil, prefix .. "enter an aura name or spell ID."
        end
        local aura = Model.Trim(item.aura)
        if #aura > 200 then return nil, prefix .. "aura name is too long." end
        if not auraSources[item.auraSource] and item.auraSource ~= "cooldown" then
            return nil, prefix .. "choose Tracked aura, Target debuff, Player buff, or Spell cooldown."
        end
        if item.condition ~= "present" and item.condition ~= "missing" then
            return nil, prefix .. "choose present or missing."
        end
        normalized[index] = {aura = aura, auraSource = item.auraSource, condition = item.condition}
    end
    return normalized
end

function Model.NormalizeRules(rules, resolveSpell)
    if type(rules) ~= "table" or #rules < 1 then return nil, "Add at least one spell." end
    if #rules > Model.MAX_RULES then return nil, "Use at most 32 spell rules." end
    local normalized, enabledIndices, lastPriorityModifier, enabledCustomRules = {}, {}, 0, 0
    local customIndex
    local units = {target = true, player = true, focus = true, focustarget = true, mouseover = true, custom = true,
        party1 = true, party2 = true, party3 = true, party4 = true}
    local conditions = {present = true, missing = true, always = true}
    for index, row in ipairs(rules) do
        local prefix = "Rule " .. index .. ": "
        if type(row) ~= "table" then return nil, prefix .. "invalid rule." end
        if row.enabled ~= nil and type(row.enabled) ~= "boolean" then return nil, prefix .. "Enable Rule must be on or off." end
        local _, skipError = Model.NormalizeModifier(row.skipModifier)
        if skipError then return nil, prefix .. "Skip modifier: " .. skipError end
        local _, priorityError = Model.NormalizeModifier(row.priorityModifier)
        if priorityError then return nil, prefix .. "Priority modifier: " .. priorityError end
        if row.enabled ~= false then
            if Model.IsCustomRule(row) then
                enabledCustomRules = enabledCustomRules + 1
                if enabledCustomRules > 1 then return nil, prefix .. "Enable only one Custom Rule per Hit Button. Combine its commands in one rule or disable the other Custom Rule." end
                customIndex = index
            end
            enabledIndices[#enabledIndices + 1] = index
            if row.priorityModifier then lastPriorityModifier = index end
        end
    end
    if customIndex then
        for _, index in ipairs(enabledIndices) do
            local row = rules[index]
            if Model.IsAutoAttack(row.spell) then
                if index < customIndex then return nil, "Rule " .. customIndex .. ": move Custom Rule above Auto Attack so its commands can run first." end
                if row.priorityModifier and row.priorityModifier ~= rules[customIndex].priorityModifier then
                    return nil, "Rule " .. index .. ": Auto Attack cannot use a different priority modifier from Custom Rule. The Custom Rule must run first."
                end
            end
        end
    end
    for priority, index in ipairs(enabledIndices) do
        local row = rules[index]
        local prefix = "Rule " .. index .. ": "
        local comboPoints, comboError = Model.NormalizeComboPoints(row.comboPoints)
        if comboError then return nil, prefix .. comboError end
        local hawkCount, hawkError = Model.NormalizeHawkCount(row.hawkCount)
        if hawkError then return nil, prefix .. hawkError end
        local resourceConditions, resourceError = Model.NormalizeResourceConditions(row.resourceConditions)
        if not resourceConditions then return nil, prefix .. resourceError end
        local healthConditions, healthError = Model.NormalizeHealthConditions(row.healthConditions)
        if not healthConditions then return nil, prefix .. healthError end
        local stackConditions, stackError = Model.NormalizeStackConditions(row.stackConditions)
        if not stackConditions then return nil, prefix .. stackError end
        local primaryCondition, primaryError = Model.NormalizePrimaryCondition(row.primaryCondition)
        if primaryError then return nil, prefix .. primaryError end
        local logicConditions, logicError = Model.NormalizeLogicConditions(row.logicConditions)
        if not logicConditions then return nil, prefix .. logicError end
        local logicOr = false
        local totals = {resource = #resourceConditions, health = #healthConditions, stacks = #stackConditions, auraTime = 0}
        if primaryCondition and totals[primaryCondition.type] then totals[primaryCondition.type] = totals[primaryCondition.type] + 1 end
        for _, item in ipairs(logicConditions) do
            if item.logic == "OR" then logicOr = true end
            if totals[item.type] then
                totals[item.type] = totals[item.type] + 1
                if totals[item.type] > 8 then return nil, prefix .. "use at most 8 " .. item.type .. " conditions across all operators." end
            end
        end
        for kind, count in pairs(totals) do
            if count > 8 then return nil, prefix .. "use at most 8 " .. kind .. " conditions across all operators." end
        end
        local andConditions, andError = normalizeExtraConditions(row.andConditions, "AND")
        if not andConditions then return nil, prefix .. andError end
        local notConditions, notError = normalizeExtraConditions(row.notConditions, "NOT")
        if not notConditions then return nil, prefix .. notError end
        local orConditions, orError = normalizeExtraConditions(row.orConditions, "OR")
        if not orConditions then return nil, prefix .. orError end
        if #andConditions + #notConditions + #orConditions > Model.MAX_EXTRA_CONDITIONS then
            return nil, prefix .. "use at most " .. Model.MAX_EXTRA_CONDITIONS .. " additional AND / OR / NOT conditions."
        end
        local hasExtraConditions = #andConditions + #notConditions > 0
        local hasExtraAuras = false
        for _, list in ipairs({andConditions, notConditions}) do
            for _, item in ipairs(list) do if item.auraSource ~= "cooldown" then hasExtraAuras = true end end
        end
        local spellText, aura, orAura = Model.Trim(row.spell), Model.Trim(row.aura), Model.Trim(row.orAura)
        local customRule, customRuleError, customChangesTarget
        if Model.IsCustomRule(row) then
            customRule, customRuleError, customChangesTarget = Model.NormalizeCustomRule(row.customRule)
            if not customRule then return nil, prefix .. customRuleError end
            spellText = "Custom Rule"
        end
        local petAttack = Model.IsPetAttack(spellText)
        local startAttack = Model.IsAutoAttack(spellText)
        local condition, unit = row.condition or "present", row.unit or "target"
        if primaryCondition then condition, aura = "always", "" end
        local useOr, orCondition, rankID = row.useOr == true, row.orCondition or "present", row.rankID
        local auraSource = row.auraSource == nil and "tracker" or row.auraSource
        local orAuraSource = row.orAuraSource == nil and "tracker" or row.orAuraSource
        if not auraSources[auraSource] then return nil, prefix .. "Choose Tracked aura, Target debuff, or Player buff for the primary condition." end
        if not auraSources[orAuraSource] and orAuraSource ~= "cooldown" then return nil, prefix .. "Choose Tracked aura, Target debuff, Player buff, or Spell cooldown for the OR condition." end
        if not conditions[condition] then return nil, prefix .. "choose an aura condition." end
        if not units[unit] then return nil, prefix .. "choose a valid cast target." end
        local customTarget, customCondition, macroError
        if unit == "custom" then
            customTarget, macroError = Model.NormalizeMacroTarget(row.customTarget)
            if not customTarget then return nil, prefix .. macroError end
        end
        if row.customCondition ~= nil then
            customCondition, macroError = Model.NormalizeMacroCondition(row.customCondition)
            if not customCondition then return nil, prefix .. macroError end
        end
        if row.targetCasting ~= nil and type(row.targetCasting) ~= "boolean" then
            return nil, prefix .. "Target is casting must be on or off."
        end
        if row.outOfCombatOnly ~= nil and type(row.outOfCombatOnly) ~= "boolean" then
            return nil, prefix .. "Out of combat only must be on or off."
        end
        if row.inCombatOnly ~= nil and type(row.inCombatOnly) ~= "boolean" then
            return nil, prefix .. "In combat only must be on or off."
        end
        if row.inCombatOnly == true and row.outOfCombatOnly == true then
            return nil, prefix .. "In combat only and Out of combat only cannot both be enabled."
        end
        if row.advanceOnToggle ~= nil and type(row.advanceOnToggle) ~= "boolean" then
            return nil, prefix .. "Advance on toggle must be on or off."
        end
        local advanceOnToggle = row.advanceOnToggle == true
        if row.totemCondition ~= nil and not Model.IsTotemCondition(row.totemCondition) then
            return nil, prefix .. "choose a valid totem condition."
        end
        if row.skipIfNotCasted ~= nil and type(row.skipIfNotCasted) ~= "boolean" then
            return nil, prefix .. "Require being behind target must be on or off."
        end
        local skipIfNotCasted = row.skipIfNotCasted == true
        if row.skipIfImmune ~= nil and type(row.skipIfImmune) ~= "boolean" then
            return nil, prefix .. "Skip if immune (bleed) must be on or off."
        end
        local skipIfImmune = row.skipIfImmune == true
        if row.skipOutOfRange ~= nil and type(row.skipOutOfRange) ~= "boolean" then
            return nil, prefix .. "Skip if out of range must be on or off."
        end
        local skipOutOfRange = row.skipOutOfRange == true
        if spellText == "" then return nil, prefix .. "enter a spell name or spell ID." end
        if #spellText > 200 or #aura > 200 then return nil, prefix .. "name is too long." end
        if condition ~= "always" and aura == "" then
            return nil, prefix .. "enter the aura to watch, or choose Always."
        end
        if rankID ~= nil and (type(rankID) ~= "number" or rankID <= 0 or rankID % 1 ~= 0) then
            return nil, prefix .. "choose a valid spell rank."
        end
        if (useOr or #orConditions > 0 or logicOr) and condition == "always" and not primaryCondition then
            return nil, prefix .. "OR requires a conditional IF instead of Always. Choose an aura condition for IF; the spell's cooldown still applies to every alternative."
        end
        if useOr then
            if orCondition ~= "present" and orCondition ~= "missing" then return nil, prefix .. "choose an aura condition after OR." end
            if orAura == "" then return nil, prefix .. "enter the second aura to watch after OR." end
            if #orAura > 200 then return nil, prefix .. "second aura name is too long." end
        end
        local skipCooldown = row.skipCooldown == true
        local oncePerProc = row.oncePerProc == true
        local stopCasting = row.stopCasting == true
        local stopWhenInvalid = row.stopWhenInvalid == true
        if primaryCondition and oncePerProc then return nil, prefix .. "Once per proc requires a present aura as IF." end
        if primaryCondition and stopWhenInvalid then return nil, prefix .. "Stop if buffs change requires an aura as IF." end
        local manualCooldownSeconds, manualError = Model.NormalizeManualCooldownSeconds(row.manualCooldownSeconds, row.manualCooldown)
        if manualError then return nil, prefix .. manualError end
        local manualCooldown = row.manualCooldown == true
        local pingDelay = row.pingDelay == true
        local pingDelayMS = row.pingDelayMS == nil and 100 or row.pingDelayMS
        if row.pingDelay ~= nil and type(row.pingDelay) ~= "boolean" then
            return nil, prefix .. "Ping Delay must be on or off."
        end
        if type(pingDelayMS) ~= "number" or pingDelayMS ~= pingDelayMS or
            pingDelayMS < 1 or pingDelayMS > 5000 or pingDelayMS % 1 ~= 0 then
            return nil, prefix .. "Ping Delay must be a whole number from 1 to 5000 milliseconds."
        end
        local castCount = row.castCount == nil and 0 or row.castCount
        if type(castCount) ~= "number" or castCount < 0 or castCount > 99 or castCount % 1 ~= 0 then
            return nil, prefix .. "Number of times to cast must be a whole number from 1 to 99, or blank / 0 for unlimited."
        end
        local castCountCondition = row.castCountCondition == nil and "primary" or row.castCountCondition
        if castCount > 0 then
            local attachment = Model.GetCountCondition(row)
            if not attachment then return nil, prefix .. "The cast-count condition no longer exists. Select an existing condition." end
            if not attachment.countEligible then return nil, prefix .. attachment.countReason end
        end
        if castCount > 0 and oncePerProc then
            return nil, prefix .. "Number of times to cast cannot be combined with Once per proc."
        end
        if oncePerProc and condition ~= "present" then
            return nil, prefix .. "Once per proc requires Aura is present."
        end
        if oncePerProc and auraSource == "player" then
            return nil, prefix .. "Once per proc cannot use Player buff as the IF condition."
        end
        local stopPrimary, stopOr = Model.StopBranches(row)
        if stopCasting and not stopPrimary and not stopOr then
            if auraSource == "player" or (useOr and orAuraSource == "player") then
                return nil, prefix .. "Stop current cast needs a present Tracked aura or Target debuff in IF or the first OR."
            end
            return nil, prefix .. "Stop current cast requires Aura is present in either condition."
        end
        if stopWhenInvalid and condition == "always" and not hasExtraAuras then
            return nil, prefix .. "Stop if buffs change requires an aura condition instead of Always."
        end
        if customRule then
            if rankID or skipCooldown or pingDelay or manualCooldown or castCount > 0 or oncePerProc or stopCasting or stopWhenInvalid
                or advanceOnToggle or skipIfNotCasted or skipIfImmune or skipOutOfRange then
                return nil, prefix .. "Custom Rule uses the commands you enter. Remove spell ranks, cast settings, cooldowns and range checks; use conditions for other spells where needed."
            end
            if unit ~= "target" or customTarget then return nil, prefix .. "Put Custom Rule targets in the macro command itself." end
        elseif petAttack or startAttack then
            local actionName = petAttack and "Pet Attack" or "Auto Attack"
            if advanceOnToggle then return nil, prefix .. actionName .. " already advances after starting. Remove Advance on toggle." end
            if unit ~= "target" then return nil, prefix .. actionName .. " needs your current target." end
            if skipOutOfRange then return nil, prefix .. "Choose a spell to use Skip if out of range." end
            if rankID or skipCooldown or pingDelay or manualCooldown or castCount > 0 or oncePerProc or stopCasting or stopWhenInvalid then
                return nil, prefix .. actionName .. " supports aura, combo-point, resource, health and aura stack conditions. Remove spell ranks, cooldown, cast count and cast interruption settings."
            end
        end
        local conditionalRecipient = unit == "focustarget" or (customTarget and customTarget ~= "@none")
        local macroCanFilter = customCondition and not customCondition:match("%[%s*%]")
        local wouldHideLaterRules = condition == "always" and not customRule and not petAttack and not startAttack and not advanceOnToggle and not skipCooldown and not pingDelay and not manualCooldown
            and not skipIfNotCasted and not skipIfImmune and not skipOutOfRange and not row.outOfCombatOnly and not row.inCombatOnly and not row.skipModifier
            and not hasExtraConditions and not comboPoints and not hawkCount and #resourceConditions == 0 and #healthConditions == 0 and #stackConditions == 0 and #logicConditions == 0 and not primaryCondition
            and not macroCanFilter and not conditionalRecipient and not row.targetCasting and not row.totemCondition
            and lastPriorityModifier <= index and priority ~= #enabledIndices
        local spell, err
        if customRule then
            spell = {name = "Custom Rule", cast = "Custom Rule", icon = "Interface\\Icons\\INV_Misc_Note_01"}
        elseif petAttack then
            spell = {name = "Pet Attack", cast = "Pet Attack", icon = PET_ATTACK_TEXTURE or "Interface\\Icons\\Ability_GhoulFrenzy"}
        elseif startAttack then
            spell = {name = "Auto Attack", cast = 6603, id = 6603, icon = "Interface\\Icons\\INV_Sword_04"}
        else
            spell, err = resolveSpell(spellText, rankID)
        end
        if not spell then return nil, prefix .. (err or "spell not found.") end
        if wouldHideLaterRules and not (SH.Riposte and SH.Riposte.IsReactive(spell.id)) then
            return nil, prefix .. "move Always to the bottom, or enable Skip while on cooldown; it would hide every rule below it."
        end
        if (type(spell.cast) ~= "string" and type(spell.cast) ~= "number") or not spell.name then
            return nil, prefix .. "spell information is unavailable."
        end
        local wandShoot = spell.id == 5019
        local rangedRepeat = wandShoot or spell.id == 75
        if skipIfNotCasted and (petAttack or startAttack or rangedRepeat) then
            return nil, prefix .. "Choose a spell you cast directly to use Require being behind target."
        end
        if skipIfImmune and (petAttack or startAttack or rangedRepeat or advanceOnToggle) then
            return nil, prefix .. "Choose a spell you cast directly to use Skip if immune (bleed)."
        end
        if rangedRepeat and castCount > 0 then
            return nil, prefix .. "Cast Count is not supported for " .. (wandShoot and "wand Shoot" or "Auto Shot") .. ". It keeps firing automatically."
        end
        normalized[priority] = {
            sourceIndex = index, customTarget = customTarget, customCondition = customCondition,
            customRule = customRule, customChangesTarget = customChangesTarget,
            targetCasting = row.targetCasting == true,
            outOfCombatOnly = row.outOfCombatOnly == true,
            inCombatOnly = row.inCombatOnly == true,
            skipModifier = row.skipModifier,
            priorityModifier = row.priorityModifier,
            advanceOnToggle = advanceOnToggle,
            totemCondition = row.totemCondition,
            skipIfNotCasted = skipIfNotCasted,
            skipIfImmune = skipIfImmune,
            skipOutOfRange = skipOutOfRange,
            spell = spell.cast, displayName = spell.name, spellID = spell.id,
            wandShoot = wandShoot,
            rangedRepeat = rangedRepeat, petAttack = petAttack, startAttack = startAttack,
            icon = spell.icon, aura = aura, condition = condition, unit = unit,
            rankID = rankID, rankLabel = spell.rankLabel,
            useOr = useOr, orAura = orAura, orCondition = orCondition,
            auraSource = auraSource, orAuraSource = orAuraSource,
            andConditions = andConditions, notConditions = notConditions, orConditions = orConditions,
            skipCooldown = skipCooldown,
            oncePerProc = oncePerProc,
            stopCasting = stopCasting,
            stopWhenInvalid = stopWhenInvalid,
            pingDelay = pingDelay,
            pingDelayMS = pingDelayMS,
            manualCooldown = manualCooldown,
            manualCooldownSeconds = manualCooldownSeconds,
            castCount = castCount,
            castCountCondition = castCountCondition,
            comboPoints = comboPoints,
            hawkCount = hawkCount,
            resourceConditions = resourceConditions,
            healthConditions = healthConditions,
            stackConditions = stackConditions,
            logicConditions = logicConditions,
            primaryCondition = primaryCondition,
        }
    end
    return normalized
end

local function literal(value)
    if type(value) == "number" then return tostring(value) end
    return string.format("%q", value)
end

function Model.CustomRuleTargetChangeExpression(text)
    local normalized = Model.NormalizeCustomRule(text)
    if not normalized then return "true" end
    local first, tests = true, {}
    for line in normalized:gmatch("[^\n]+") do
        local command, arguments = line:match("^/(%a+)%s*(.*)$")
        if targetCommands[command] then
            -- Later guards may change after an earlier command (focus, cast,
            -- target, etc.). The first line can be checked exactly now.
            if not first or arguments == "" or not arguments:match("^%[") then return "true" end
            tests[#tests + 1] = "SecureCmdOptionParse(" .. literal(arguments) .. ")~=nil"
        end
        first = false
    end
    return #tests == 0 and "false" or "(" .. table.concat(tests, " or ") .. ")"
end

function Model.CustomRuleExecutesExpression(text)
    local normalized = Model.NormalizeCustomRule(text)
    if not normalized then return "false" end
    local tests = {}
    for line in normalized:gmatch("[^\n]+") do
        local arguments = line:match("^/%a+%s*(.*)$")
        if arguments == "" or not arguments:match("^%[") then return "true" end
        tests[#tests + 1] = "SecureCmdOptionParse(" .. literal(arguments) .. ")~=nil"
    end
    return #tests == 0 and "false" or "(" .. table.concat(tests, " or ") .. ")"
end

-- CDM can still contain the previous target during the macro's current frame.
-- A target-changing command may continue to native checks immediately, but
-- these cached target predicates wait until the next physical press.
function Model.UsesTargetSnapshot(row)
    local function aura(source, condition)
        return condition ~= "always" and source ~= "player" and source ~= "cooldown"
    end
    if not row.primaryCondition and aura(row.auraSource, row.condition or "present") then return true end
    if row.useOr and aura(row.orAuraSource, row.orCondition or "present") then return true end
    for _, key in ipairs({"andConditions", "orConditions", "notConditions"}) do
        for _, item in ipairs(row[key] or {}) do if aura(item.auraSource, item.condition) then return true end end
    end
    for _, item in ipairs(row.stackConditions or {}) do if item.auraSource == "target" then return true end end
    local function typed(item)
        return item and (item.type == "auraTime" and item.unit == "target"
            or item.type == "stacks" and item.auraSource == "target")
    end
    if typed(row.primaryCondition) then return true end
    for _, item in ipairs(row.logicConditions or {}) do if typed(item) then return true end end
    return false
end

local function auraMatch(source, expression)
    if source == "target" then return '(targetValid and (' .. expression .. '))' end
    return expression
end

function Model.Compile(rules, preventClipping, pass)
    local commandPass = pass == "commands"
    local customPass = pass == "custom"
    local autoPass, castPass = pass == "auto" or commandPass or customPass, pass == "cast" or pass == "final"
    local hasCounts, hasTarget, invalidCount, hasCombo, invalidCombo = false, false, false, false, false
    local hasPing, invalidPing = false, false
    local invalidCooldown, hasTargetCasting, hasRiposte, hasPositionSkip, hasImmunitySkip = false, false, false, false, false
    local reactiveSpells, invalidReactive = {}, false
    local hasFireTotems, hasRangeSkip, hasOutOfCombat, hasInCombat = false, false, false, false
    local hasHawks, invalidHawks, hasConditionCooldowns = false, false, false
    local usedModifiers, hasPriorityModifier, invalidModifier = {}, false, false
    local resourceRequests = Model.ResourceRequests(rules)
    local hasResources = resourceRequests ~= nil and #resourceRequests > 0
    local healthRequests = Model.HealthRequests(rules)
    local hasHealth = healthRequests ~= nil and #healthRequests > 0
    local stackRequests = Model.StackRequests(rules)
    local hasStacks = stackRequests ~= nil and #stackRequests > 0
    local auraTimeRequests = Model.AuraTimeRequests(rules)
    local logicRows, primaryRows, logicRequestIndices, legacyRequestOffsets = {}, {}, {}, {}
    local requestTotals = {resource = 0, health = 0, stacks = 0, auraTime = 0}
    local requestFields = {resource = "resourceConditions", health = "healthConditions", stacks = "stackConditions"}
    local hasLogic, invalidLogic = false, false
    for index, row in ipairs(rules) do
        local logic = Model.NormalizeLogicConditions(row.logicConditions)
        if not logic then invalidLogic = true; logic = {} end
        local primary, primaryError = Model.NormalizePrimaryCondition(row.primaryCondition)
        if primaryError then invalidLogic = true end
        primaryRows[index] = primary
        logicRows[index], logicRequestIndices[index], legacyRequestOffsets[index] = logic, {}, {}
        if #logic > 0 or primary then hasLogic = true end
        for kind, field in pairs(requestFields) do
            legacyRequestOffsets[index][kind] = requestTotals[kind]
            requestTotals[kind] = requestTotals[kind] + #(row[field] or {})
        end
        if primary and requestTotals[primary.type] then
            requestTotals[primary.type] = requestTotals[primary.type] + 1
            logicRequestIndices[index].primary = requestTotals[primary.type]
        end
        for conditionIndex, item in ipairs(logic) do
            if requestTotals[item.type] then
                requestTotals[item.type] = requestTotals[item.type] + 1
                logicRequestIndices[index][conditionIndex] = requestTotals[item.type]
            end
            if item.logic == "OR" and row.condition == "always" and not primary then invalidLogic = true end
        end
        if row.useOr and row.orAuraSource == "cooldown" then hasConditionCooldowns = true end
        for _, key in ipairs({"skipModifier", "priorityModifier"}) do
            local modifier, reason = Model.NormalizeModifier(row[key])
            if reason then invalidModifier = true end
            if modifier then usedModifiers[modifier] = true end
        end
        if row.priorityModifier ~= nil then hasPriorityModifier = true end
        if row.targetCasting then hasTargetCasting = true end
        if row.outOfCombatOnly then hasOutOfCombat = true end
        if row.inCombatOnly then hasInCombat = true end
        if row.totemCondition ~= nil then hasFireTotems = true end
        if row.riposteReady then hasRiposte = true end
        if row.reactiveReady ~= nil then
            local id = row.reactiveReady
            if type(id) ~= "number" or id < 1 or id % 1 ~= 0 or id ~= row.spellID then invalidReactive = true
            else reactiveSpells[id] = true end
        end
        if (row.reactiveAura or row.orReactiveAura) and row.reactiveReady == nil then invalidReactive = true end
        for _, list in ipairs({row.andConditions or {}, row.notConditions or {}, row.orConditions or {}}) do
            for _, item in ipairs(list) do
                if item.reactiveAura and row.reactiveReady == nil then invalidReactive = true end
            end
        end
        if row.skipIfNotCasted then hasPositionSkip = true end
        if row.skipIfImmune then hasImmunitySkip = true end
        if row.skipOutOfRange then hasRangeSkip = true end
        if row.skipCooldown and not row.manualCooldown and row.spellCooldownID ~= nil then
            local id = row.spellCooldownID
            if type(id) ~= "number" or id < 1 or id % 1 ~= 0 then invalidCooldown = true end
        end
        if row.pingDelay or row.manualCooldown then
            hasPing = true
            local delay = row.pingDelayMS == nil and 100 or row.pingDelayMS
            if type(delay) ~= "number" or delay ~= delay or delay < 1 or delay > 5000 or delay % 1 ~= 0 then invalidPing = true end
            if row.manualCooldown and not Model.NormalizeManualCooldownSeconds(row.manualCooldownSeconds, row.manualCooldown) then invalidPing = true end
        end
        if row.comboPoints ~= nil then
            hasCombo = true
            local valid = Model.NormalizeComboPoints(row.comboPoints)
            if not valid then invalidCombo = true end
        end
        if row.hawkCount ~= nil then
            hasHawks = true
            if not Model.NormalizeHawkCount(row.hawkCount) then invalidHawks = true end
        end
        if (row.castCount or 0) > 0 then
            hasCounts = true
            local attachment = Model.GetCountCondition(row)
            if not attachment or not attachment.countEligible then invalidCount = true end
        end
        if row.startAttack or row.petAttack or row.condition ~= "always" and row.auraSource == "target" or row.useOr and row.orAuraSource == "target" then
            hasTarget = true
        end
        for _, list in ipairs({row.andConditions or {}, row.notConditions or {}, row.orConditions or {}}) do
            for _, item in ipairs(list) do
                if item.auraSource == "target" then hasTarget = true end
                if item.auraSource == "cooldown" then hasConditionCooldowns = true end
            end
        end
    end
    local lines = {
        'self:SetAttribute("sh-valid",false)',
        'self:SetAttribute("type","spell")',
        'self:SetAttribute("macrotext",nil)',
        'self:SetAttribute("spell",nil)',
        'self:SetAttribute("unit",nil)',
        'self:SetAttribute("selected-row",nil)',
        'self:SetAttribute("selected-primary",nil)',
        'self:SetAttribute("selected-or",nil)',
        'self:SetAttribute("selected-legacy-or",nil)',
        'self:SetAttribute("sh-command-target-change",nil)',
        'self:SetAttribute("sh-command-executes",nil)',
        'self:SetAttribute("sh-count-wait",nil)',
        'self:SetAttribute("sh-wand-hold",nil)',
        'self:SetAttribute("sh-pet-attack",nil)',
    }
    for index in ipairs(rules) do
        lines[#lines + 1] = 'self:SetAttribute("sh-aura-match' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-extra' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-extra-or' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-extra-count' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-extra-or-count' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-extra-or-bypass' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-count-match' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-count-available' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-logic-all' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-logic-or' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-logic-or-unknown' .. index .. '",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-logic-primary' .. index .. '",nil)'
    end
    lines[#lines + 1] = 'if not self:GetAttribute("ready") then return false end'
    if #rules == 0 then
        lines[#lines + 1] = 'self:SetAttribute("sh-valid",true); return false'
        return table.concat(lines, "\n")
    end
    if invalidCount or invalidCombo or invalidHawks or invalidPing or invalidCooldown or invalidModifier or invalidLogic or invalidReactive or not resourceRequests or not healthRequests or not stackRequests or not auraTimeRequests then
        lines[#lines + 1] = 'return false'
        return table.concat(lines, "\n")
    end
    if hasTarget then
        lines[#lines + 1] = 'local targetValid=SecureCmdOptionParse("[@target,exists,harm,nodead]1")=="1"'
    end
    local beforeEpochs = #lines + 1
    local formChecks, formSlots = {}, {}
    local function countMatch(row, index, key, predicate, raw)
        if (row.castCount or 0) == 0 or (row.castCountCondition or "primary") ~= key then return predicate end
        local attachment = Model.GetCountCondition(row)
        if attachment.condition == "missing" then
            local continuation = 'b' .. index .. '==true'
            if raw then continuation = continuation .. ' and k' .. index .. '<' .. row.castCount end
            predicate = '(' .. predicate .. ' or (' .. continuation .. '))'
        end
        if not raw then predicate = '(' .. predicate .. ') and k' .. index .. '<' .. row.castCount end
        return predicate
    end
    local function readValue(value, reader, present, key)
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return end
        lines[#lines + 1] = 'self:SetAttribute("' .. present .. '",nil)'
        lines[#lines + 1] = 'if rawtype(self:GetAttribute("' .. reader .. '"))=="string" and self:RunAttribute("' .. reader .. '",' .. literal(key) .. ')==true then'
        lines[#lines + 1] = value .. '=self:GetAttribute("' .. present .. '") end'
    end
    if hasRiposte then
        lines[#lines + 1] = 'local riposteReady'
        lines[#lines + 1] = 'self:SetAttribute("sh-riposte-ready",nil)'
        lines[#lines + 1] = 'if rawtype(self:GetAttribute("sh-read-riposte"))=="string" and self:RunAttribute("sh-read-riposte")==true then'
        lines[#lines + 1] = 'riposteReady=self:GetAttribute("sh-riposte-ready") end'
    end
    local function reactiveValue(id)
        return 'self:GetAttribute("sh-reactive-spell-' .. id .. '")'
    end
    for id in pairs(reactiveSpells) do
        -- These results belong to this physical selection only. Duplicate
        -- rules share their exact rank's reading, never another spell's result.
        lines[#lines + 1] = 'self:SetAttribute("sh-reactive-spell-' .. id .. '",nil)'
        lines[#lines + 1] = 'do local ready'
        readValue("ready", "sh-read-reactive", "sh-reactive-ready", id)
        lines[#lines + 1] = 'if rawtype(ready)=="boolean" then self:SetAttribute("sh-reactive-spell-' .. id .. '",ready) end end'
    end
    local function syncGuard(value, guard)
        if autoPass then return end
        lines[#lines + 1] = 'if rawtype(' .. value .. ')=="boolean" then'
        lines[#lines + 1] = 'local g=self:GetFrameRef("' .. guard .. '");if not g then return false end'
        lines[#lines + 1] = 'local e=g:GetAttribute("sh-proc-epoch");if rawtype(e)~="number" then return false end'
        -- The tracker or its border may already have hidden between presses.
        -- Count a confirmed disappearance once even if both stay visible.
        lines[#lines + 1] = 'if not ' .. value .. ' and g:GetAttribute("sh-effect-present")==true and g:GetAttribute("sh-effect-seen-epoch")==e then'
        lines[#lines + 1] = 'e=e+1;g:SetAttribute("sh-proc-epoch",e) end'
        lines[#lines + 1] = 'g:SetAttribute("sh-effect-present",' .. value .. ');g:SetAttribute("sh-effect-seen-epoch",e) end'
    end
    local sampled = {}
    local function syncEffectGuard(value, key, guard)
        sampled[value] = true
        lines[#lines + 1] = 'local ' .. value
        lines[#lines + 1] = 'if targetValid then'
        readValue(value, "sh-read-target-effect", "sh-target-effect-present", key)
        syncGuard(value, guard)
        lines[#lines + 1] = 'end'
    end
    for index, row in ipairs(rules) do
        local primaryStop, orStop = Model.StopBranches(row)
        if row.reactiveAura and row.stopCasting and primaryStop then
            syncGuard(reactiveValue(row.reactiveReady), "proc" .. index)
        elseif row.riposteReady and row.stopCasting and primaryStop then
            syncGuard("riposteReady", "proc" .. index)
        elseif row.targetEffectKey and (row.oncePerProc or row.stopCasting and primaryStop) then
            syncEffectGuard("p" .. index, row.targetEffectKey, "proc" .. index)
        end
        if row.orReactiveAura and row.stopCasting and orStop then
            syncGuard(reactiveValue(row.reactiveReady), "orProc" .. index)
        elseif row.orTargetEffectKey and row.stopCasting and orStop then
            syncEffectGuard("o" .. index, row.orTargetEffectKey, "orProc" .. index)
        end
    end
    -- A submitted spell can fail. Only a later click confirming its channel
    -- consumes this epoch, and a changed epoch must never consume a new proc.
    for index, row in ipairs(rules) do
        if row.oncePerProc and not autoPass then
            local channel = "[channeling:" .. row.displayName .. "]1"
            lines[#lines + 1] = 'if self:GetAttribute("sh-pending-row")== ' .. index .. ' and SecureCmdOptionParse(' .. literal(channel) .. ') then'
            lines[#lines + 1] = 'local g=self:GetFrameRef("proc' .. index .. '")'
            lines[#lines + 1] = 'if not g then return false end'
            lines[#lines + 1] = 'local e=g:GetAttribute("sh-proc-epoch")'
            lines[#lines + 1] = 'if e==nil then return false end'
            lines[#lines + 1] = 'if self:GetAttribute("sh-pending-epoch")==e then self:SetAttribute("sh-used' .. index .. '",e) end'
            lines[#lines + 1] = 'self:SetAttribute("sh-pending-row",nil)'
            lines[#lines + 1] = 'self:SetAttribute("sh-pending-epoch",nil)'
            lines[#lines + 1] = 'end'
        end
    end
    if preventClipping then
        -- A blocked press must also remove any request queued before the channel
        -- began. Let the native secure action run this macro without clipping it.
        lines[#lines + 1] = 'if SecureCmdOptionParse("[channeling]1") then'
        if autoPass then
            lines[#lines + 1] = 'return false end'
        else
            lines[#lines + 1] = 'self:SetAttribute("type","macro")'
            lines[#lines + 1] = 'self:SetAttribute("macrotext","/cancelqueuedspell")'
            lines[#lines + 1] = 'return end'
        end
    end
    if hasCombo then
        lines[#lines + 1] = 'if self:RunAttribute("sh-read-combo")~=true then return false end'
        lines[#lines + 1] = 'local comboCount=self:GetAttribute("sh-combo-count")'
        lines[#lines + 1] = 'if rawtype(comboCount)~="number" or comboCount<0 or comboCount>5 or comboCount%1~=0 then return false end'
    end
    local rowsWithAuraReader = {}
    local function readAura(index, value, source, auraRef, debuffRef, playerKey, formSlot, targetEffectKey, cooldownSpellID)
        if not sampled[value] then lines[#lines + 1] = 'local ' .. value end
        if source == "cooldown" then
            -- Presence means a known active spell cooldown; an unreadable
            -- result is neither present nor missing, including inside NOT.
            if cooldownSpellID ~= nil then
                if type(cooldownSpellID) ~= "number" or cooldownSpellID < 1 or cooldownSpellID % 1 ~= 0 then
                    lines[#lines + 1] = 'do return false end'
                    return
                end
                lines[#lines + 1] = 'self:SetAttribute("sh-totem-ready",nil)'
                lines[#lines + 1] = 'if rawtype(self:GetAttribute("sh-read-totem"))=="string" and self:RunAttribute("sh-read-totem",' .. cooldownSpellID .. ',true)==true then'
                lines[#lines + 1] = 'local ready=self:GetAttribute("sh-totem-ready");if rawtype(ready)=="boolean" then ' .. value .. '=not ready end end'
            else
                lines[#lines + 1] = 'do local flash=self:GetFrameRef("' .. auraRef .. 'Cooldown");local timer=self:GetFrameRef("' .. auraRef .. 'Timer")'
                lines[#lines + 1] = 'if flash and timer then local flashing,ticking=flash:IsShown(),timer:IsShown()'
                lines[#lines + 1] = 'if rawtype(flashing)=="boolean" and rawtype(ticking)=="boolean" then ' .. value .. '=flashing and ticking end end end'
            end
            return
        end
        if formSlot ~= nil then
            if (source ~= "tracker" and source ~= "player") or type(formSlot) ~= "number" or formSlot < 1 or formSlot % 1 ~= 0 then
                formChecks[#formChecks + 1] = 'do return false end'
                return
            end
            if not formSlots[formSlot] then
                -- The native state driver can update after a button press.
                -- Refresh our own frame before its proc and count guards run.
                formSlots[formSlot] = true
                local conditional = "[form:" .. formSlot .. "]1;0"
                formChecks[#formChecks + 1] = 'do local f=self:GetFrameRef("' .. auraRef .. '")'
                formChecks[#formChecks + 1] = 'if not f or f:GetAttribute("sh-druid-form-slot")~=' .. formSlot .. ' then return false end'
                formChecks[#formChecks + 1] = 'local state=SecureCmdOptionParse(' .. literal(conditional) .. ')'
                formChecks[#formChecks + 1] = 'if state~="1" and state~="0" then return false end'
                formChecks[#formChecks + 1] = 'if state=="1" then if not f:IsShown() then f:Show() end'
                formChecks[#formChecks + 1] = 'elseif f:IsShown() then f:Hide() end end'
            end
        end
        if source == "reactive" or source == "riposte" or (source == "player" and formSlot == nil) or (source == "target" and targetEffectKey ~= nil) then
            local targeted = source == "target"
            local key = targeted and targetEffectKey or playerKey
            local reader = targeted and "sh-read-target-effect" or "sh-read-player-buff"
            local present = targeted and "sh-target-effect-present" or "sh-buff-present"
            local unknown = '"sh-buff-unknown' .. index .. '"'
            if not rowsWithAuraReader[index] then
                rowsWithAuraReader[index] = true
                lines[#lines + 1] = 'self:SetAttribute(' .. unknown .. ',nil)'
            end
            if targeted then lines[#lines + 1] = 'if targetValid then' end
            if source == "reactive" then
                lines[#lines + 1] = value .. '=' .. reactiveValue(rules[index].reactiveReady)
            elseif source == "riposte" then
                lines[#lines + 1] = value .. '=riposteReady'
            elseif not sampled[value] then
                readValue(value, reader, present, key)
            end
            lines[#lines + 1] = 'if rawtype(' .. value .. ')~="boolean" then ' .. value .. '=nil;self:SetAttribute(' .. unknown .. ',true) end'
            if targeted then lines[#lines + 1] = 'end' end
        else
            lines[#lines + 1] = 'do local f=self:GetFrameRef("' .. auraRef .. '")'
            lines[#lines + 1] = 'if not f then return false end'
            lines[#lines + 1] = value .. '=f:IsShown();if ' .. value .. '==nil then return false end'
            if source == "target" then
                lines[#lines + 1] = 'f=self:GetFrameRef("' .. debuffRef .. '")'
                lines[#lines + 1] = 'if not f then return false end;local d=f:IsShown();if d==nil then return false end'
                lines[#lines + 1] = value .. '=' .. value .. ' and d'
            end
            lines[#lines + 1] = 'end'
        end
    end
    -- Validate tracker and proc references and capture the aura state used by
    -- the direct key to decide whether an ongoing cast should be interrupted.
    for index, row in ipairs(rules) do
        if row.condition ~= "always" then
            readAura(index, "p" .. index, row.reactiveAura and "reactive" or row.riposteReady and "riposte" or row.auraSource, "aura" .. index, "debuff" .. index,
                row.playerBuffKey, row.formSlot, row.targetEffectKey)
        end
        if row.useOr then
            readAura(index, "o" .. index, row.orReactiveAura and "reactive" or row.orAuraSource, "orAura" .. index, "orDebuff" .. index,
                row.orPlayerBuffKey, row.orFormSlot, row.orTargetEffectKey, row.orCooldownSpellID)
        end
        if (row.castCount or 0) > 0 then
            lines[#lines + 1] = 'local k' .. index .. ',b' .. index
            lines[#lines + 1] = 'do local g=self:GetFrameRef("count' .. index .. '")'
            lines[#lines + 1] = 'if not g then return false end'
            -- Paging hides this spell's observer without changing its saved slot.
            -- Keep other rules usable while this count is temporarily unavailable.
            lines[#lines + 1] = 'self:SetAttribute("sh-count-available' .. index .. '",g:RunAttribute("sh-check")==true)'
            lines[#lines + 1] = 'if g:GetAttribute("sh-valid")~=true then return false end'
            lines[#lines + 1] = 'k' .. index .. '=g:GetAttribute("sh-count");b' .. index .. '=g:GetAttribute("sh-started")'
            lines[#lines + 1] = 'if g:GetAttribute("sh-limit")~=' .. row.castCount .. ' or rawtype(k' .. index .. ')~="number" or k' .. index .. '<0 or k' .. index .. '>' .. row.castCount .. ' or k' .. index .. '%1~=0 then return false end'
            lines[#lines + 1] = 'if b' .. index .. '~=true and b' .. index .. '~=false then return false end end'
        end
        if Model.HasExtraConditions(row) then
            -- Extra predicates stay scoped: a full 32-rule rotation already
            -- needs nearly all of Lua 5.1's persistent local-variable budget.
            lines[#lines + 1] = 'do local matches,counted=true,true'
            for _, group in ipairs({{"and", row.andConditions or {}}, {"not", row.notConditions or {}}}) do
                for conditionIndex, item in ipairs(group[2]) do
                    local suffix = index .. "_" .. conditionIndex
                    lines[#lines + 1] = 'do'
                    readAura(index, "p", item.reactiveAura and "reactive" or item.auraSource, group[1] .. "Aura" .. suffix,
                        group[1] .. "Debuff" .. suffix, item.playerBuffKey, item.formSlot, item.targetEffectKey, item.cooldownSpellID)
                    local predicate = 'p==' .. (item.condition == "present" and 'true' or 'false')
                    if group[1] == "not" then
                        predicate = 'not (' .. predicate .. ')'
                        if item.reactiveAura or item.auraSource == "player" or item.auraSource == "cooldown" or item.targetEffectKey then predicate = 'p~=nil and ' .. predicate end
                    end
                    -- A missing/invalid target is never inverted into a match
                    -- by NOT. Every target gate requires a valid target.
                    if item.auraSource == "target" then predicate = 'targetValid and (' .. predicate .. ')' end
                    local key = group[1] .. "Conditions:" .. conditionIndex
                    local effective = countMatch(row, index, key, predicate, false)
                    lines[#lines + 1] = 'matches=matches and (' .. (item.auraSource == "cooldown" and 'true' or countMatch(row, index, key, predicate, true)) .. ')'
                    lines[#lines + 1] = 'counted=counted and (' .. effective .. ')'
                    if (row.castCount or 0) > 0 and row.castCountCondition == key then
                        lines[#lines + 1] = 'self:SetAttribute("sh-count-match' .. index .. '",' .. effective .. ')'
                    end
                    lines[#lines + 1] = 'end'
                end
            end
            lines[#lines + 1] = 'self:SetAttribute("sh-extra' .. index .. '",matches)'
            lines[#lines + 1] = 'self:SetAttribute("sh-extra-count' .. index .. '",counted) end'
        end
        if #(row.orConditions or {}) > 0 then
            lines[#lines + 1] = 'do local matches,counted,bypass=false,false,false'
            for conditionIndex, item in ipairs(row.orConditions) do
                local suffix = index .. "_" .. conditionIndex
                lines[#lines + 1] = 'do'
                readAura(index, "p", item.reactiveAura and "reactive" or item.auraSource, "orExtraAura" .. suffix,
                    "orExtraDebuff" .. suffix, item.playerBuffKey, item.formSlot, item.targetEffectKey, item.cooldownSpellID)
                local predicate = auraMatch(item.auraSource, 'p==' .. (item.condition == "present" and 'true' or 'false'))
                local key = "orConditions:" .. conditionIndex
                local effective = countMatch(row, index, key, predicate, false)
                lines[#lines + 1] = 'matches=matches or (' .. (item.auraSource == "cooldown" and 'true' or countMatch(row, index, key, predicate, true)) .. ')'
                lines[#lines + 1] = 'counted=counted or (' .. effective .. ')'
                if (row.castCount or 0) > 0 and row.castCountCondition == key then
                    lines[#lines + 1] = 'self:SetAttribute("sh-count-match' .. index .. '",' .. effective .. ')'
                else
                    lines[#lines + 1] = 'bypass=bypass or (' .. effective .. ')'
                end
                lines[#lines + 1] = 'end'
            end
            lines[#lines + 1] = 'self:SetAttribute("sh-extra-or' .. index .. '",matches)'
            lines[#lines + 1] = 'self:SetAttribute("sh-extra-or-count' .. index .. '",counted)'
            lines[#lines + 1] = 'self:SetAttribute("sh-extra-or-bypass' .. index .. '",bypass) end'
        end
        if row.skipCooldown and not row.manualCooldown then
            local ready = 'cooldownReady' .. index
            lines[#lines + 1] = 'local ' .. ready
            if row.spellCooldownID then
                -- A totem's real cooldown can be unreadable during combat. Only
                -- this rule needs the answer; other spells can still be cast.
                lines[#lines + 1] = 'self:SetAttribute("sh-totem-ready",nil)'
                lines[#lines + 1] = ready .. '=rawtype(self:GetAttribute("sh-read-totem"))=="string"'
                lines[#lines + 1] = 'and self:RunAttribute("sh-read-totem",' .. literal(row.spellCooldownID) .. ')==true'
                lines[#lines + 1] = 'and self:GetAttribute("sh-totem-ready")==true'
            else
                lines[#lines + 1] = 'do local flash=self:GetFrameRef("cooldown' .. index .. '")'
                lines[#lines + 1] = 'local timer=self:GetFrameRef("timer' .. index .. '")'
                lines[#lines + 1] = 'if not flash or not timer then return false end'
                lines[#lines + 1] = 'local flashing,ticking=flash:IsShown(),timer:IsShown()'
                lines[#lines + 1] = 'if flashing==nil or ticking==nil then return false end'
                lines[#lines + 1] = ready .. '=(flashing==false or ticking==false) end'
            end
        end
        local stopPrimary, stopOr = Model.StopBranches(row)
        if row.oncePerProc or (row.stopCasting and stopPrimary) then
            -- Scope temporary handles so 32 rules stay below Lua's local limit.
            lines[#lines + 1] = 'do local g=self:GetFrameRef("proc' .. index .. '")'
            lines[#lines + 1] = 'if not g then return false end'
            lines[#lines + 1] = 'if g:GetAttribute("sh-proc-epoch")==nil then return false end end'
        end
        if row.stopCasting and stopOr then
            lines[#lines + 1] = 'do local g=self:GetFrameRef("orProc' .. index .. '")'
            lines[#lines + 1] = 'if not g then return false end'
            lines[#lines + 1] = 'if g:GetAttribute("sh-proc-epoch")==nil then return false end end'
        end
    end
    -- Typed alternatives also affect an interrupted cast's aura predicate.
    -- Read them once per selection, preserving unknown separately from false;
    -- scoped locals keep full rotations within the secure Lua local limit.
    local predicateReaders = {
        resource = {"sh-read-resource", "sh-resource-pass"},
        health = {"sh-read-health", "sh-health-pass"},
        stacks = {"sh-read-stacks", "sh-stacks-pass"},
        auraTime = {"sh-read-aura-time", "sh-aura-time-pass"},
        targetCasting = {"sh-read-target-casting", "sh-target-casting"},
    }
    for index, items in ipairs(logicRows) do
        local primary = primaryRows[index]
        if #items > 0 or primary then
            local readItems = {}
            if primary then
                local item = Model.Copy(primary)
                item.logic = "IF"
                readItems[#readItems + 1] = item
            end
            for _, item in ipairs(items) do readItems[#readItems + 1] = item end
            lines[#lines + 1] = 'do local all,alternative,unknown=true,false,false'
            for conditionIndex, item in ipairs(readItems) do
                lines[#lines + 1] = 'do local result'
                local reader = predicateReaders[item.type]
                if reader then
                    lines[#lines + 1] = 'self:SetAttribute(' .. literal(reader[2]) .. ',nil)'
                    local request = item.logic == "IF" and logicRequestIndices[index].primary or logicRequestIndices[index][conditionIndex - (primary and 1 or 0)]
                    lines[#lines + 1] = 'if rawtype(self:GetAttribute(' .. literal(reader[1]) .. '))=="string" and self:RunAttribute(' .. literal(reader[1]) .. (request and ',' .. request or '') .. ')==true then'
                    lines[#lines + 1] = 'local value=self:GetAttribute(' .. literal(reader[2]) .. ');if rawtype(value)=="boolean" then result=value end end'
                elseif item.type == "comboPoints" or item.type == "hawkCount" then
                    local combo = item.type == "comboPoints"
                    local key, output = combo and "sh-read-combo" or "sh-hawk-read", combo and "sh-combo-count" or "sh-hawk-count"
                    lines[#lines + 1] = 'self:SetAttribute(' .. literal(output) .. ',nil)'
                    lines[#lines + 1] = 'if rawtype(self:GetAttribute(' .. literal(key) .. '))=="string" and self:RunAttribute(' .. literal(key) .. ')==true then'
                    lines[#lines + 1] = 'local value=self:GetAttribute(' .. literal(output) .. ')'
                    lines[#lines + 1] = 'if rawtype(value)=="number" and value>=0 and value<=' .. (combo and 5 or 2) .. ' and value%1==0 then result=value' .. (combo and comboOperators or hawkOperators)[item.operator] .. item.value .. ' end end'
                elseif item.type == "totemCondition" then
                    local element = Model.TotemConditionElement(item.value)
                    local slot = element .. "Slot"
                    lines[#lines + 1] = 'if rawtype(self:GetAttribute("shfire-read-slot"))=="string" then'
                    lines[#lines + 1] = 'local ' .. slot .. '=self:RunAttribute("shfire-read-slot",' .. literal(element) .. ')'
                    local known = slot .. '=="missing" or ' .. slot .. '=="other"'
                    if element == "fire" then known = known .. ' or ' .. slot .. '=="searing" or ' .. slot .. '=="magma"' end
                    lines[#lines + 1] = 'if rawtype(' .. slot .. ')=="string" and (' .. known .. ') then result=' .. fireSlotMatches[item.value] .. ' end end'
                elseif item.type == "customCondition" then
                    lines[#lines + 1] = 'result=SecureCmdOptionParse(' .. literal(item.value .. "1") .. ')=="1"'
                end
                if item.logic == "IF" then
                    lines[#lines + 1] = 'self:SetAttribute("sh-logic-primary' .. index .. '",result)'
                elseif item.logic == "OR" then
                    lines[#lines + 1] = 'alternative=alternative or result==true;unknown=unknown or result==nil'
                elseif item.logic == "NOT" then
                    lines[#lines + 1] = 'all=all and result==false'
                else
                    lines[#lines + 1] = 'all=all and result==true'
                end
                lines[#lines + 1] = 'end'
            end
            lines[#lines + 1] = 'self:SetAttribute("sh-logic-all' .. index .. '",all)'
            lines[#lines + 1] = 'self:SetAttribute("sh-logic-or' .. index .. '",alternative)'
            lines[#lines + 1] = 'self:SetAttribute("sh-logic-or-unknown' .. index .. '",unknown) end'
        end
    end
    -- Publish every row's raw buff condition only after all dependencies are
    -- known. Cooldowns and consumed procs must not look like a changed buff.
    for index, row in ipairs(rules) do
        local matches = primaryRows[index] and ('self:GetAttribute("sh-logic-primary' .. index .. '")==true') or row.condition == "always" and "true" or
            (row.condition == "present" and ("p" .. index .. "==true") or ("p" .. index .. "==false"))
        matches = countMatch(row, index, "primary", matches, true)
        if row.condition ~= "always" then matches = auraMatch(row.auraSource, matches) end
        if row.useOr then
            local alternative = row.orAuraSource == "cooldown" and 'true' or auraMatch(row.orAuraSource, 'o' .. index .. (row.orCondition == "missing" and '==false' or '==true'))
            alternative = countMatch(row, index, "or", alternative, true)
            matches = '(' .. matches .. ' or ' .. alternative .. ')'
        end
        if #(row.orConditions or {}) > 0 then
            matches = '(' .. matches .. ' or self:GetAttribute("sh-extra-or' .. index .. '")==true)'
        end
        if #(logicRows[index] or {}) > 0 then
            matches = '(' .. matches .. ' or self:GetAttribute("sh-logic-or' .. index .. '")==true)'
        end
        if Model.HasExtraConditions(row) then
            matches = '(' .. matches .. ') and self:GetAttribute("sh-extra' .. index .. '")==true'
        end
        if rowsWithAuraReader[index] or #(logicRows[index] or {}) > 0 or primaryRows[index] then
            -- Direct input may interrupt on a confirmed mismatch. Leave the
            -- result unset when an unreadable buff could still satisfy it.
            lines[#lines + 1] = 'do local matched=' .. matches
            local knownPrimary = primaryRows[index] and (' and self:GetAttribute("sh-logic-primary' .. index .. '")~=nil') or ''
            lines[#lines + 1] = 'if matched or (not self:GetAttribute("sh-buff-unknown' .. index .. '") and not self:GetAttribute("sh-logic-or-unknown' .. index .. '")' .. knownPrimary .. ') then self:SetAttribute("sh-aura-match' .. index .. '",matched) end end'
        else
            lines[#lines + 1] = 'self:SetAttribute("sh-aura-match' .. index .. '",' .. matches .. ')'
        end
    end
    lines[#lines + 1] = 'self:SetAttribute("sh-valid",true)'
    if hasTargetCasting then lines[#lines + 1] = 'local targetCasting' end
    if hasFireTotems then lines[#lines + 1] = 'local fireSlot,earthSlot,waterSlot,airSlot' end
    if hasHawks then lines[#lines + 1] = 'local hawkCount' end
    for _, modifier in ipairs({"ctrl", "alt", "shift"}) do
        if usedModifiers[modifier] then
            lines[#lines + 1] = 'local modifier_' .. modifier .. '=SecureCmdOptionParse("[mod:' .. modifier .. ']1")=="1"'
        end
    end
    -- Resource percentages and spell timing only gate their own candidate.
    -- Read each on demand, immediately before that row can win priority.
    local function appendGate(reader, result, index)
        lines[#lines + 1] = 'if eligible then'
        lines[#lines + 1] = 'self:SetAttribute("' .. result .. '",nil)'
        lines[#lines + 1] = 'local fresh=self:RunAttribute("' .. reader .. '",' .. index .. ')'
        lines[#lines + 1] = 'eligible=self:GetAttribute("' .. result .. '")'
        lines[#lines + 1] = 'if fresh~=true or rawtype(eligible)~="boolean" then self:SetAttribute("sh-valid",false);return false end'
        lines[#lines + 1] = 'end'
    end
    -- Emit each candidate once. The first pass considers held priority rules;
    -- the second considers only the remaining rules. Readers and selection
    -- side effects therefore run at most once per candidate per selection.
    if hasPriorityModifier then lines[#lines + 1] = 'for modifierPass=1,2 do' end
    for index, row in ipairs(rules) do
        local resourceIndex, healthIndex, stackIndex = legacyRequestOffsets[index].resource, legacyRequestOffsets[index].health, legacyRequestOffsets[index].stacks
        local hasLogicOr = false
        for _, item in ipairs(logicRows[index]) do if item.logic == "OR" then hasLogicOr = true end end
        local castUnit = row.unit == "custom" and row.customTarget:sub(2) or row.unit
        local primary = primaryRows[index] and ('self:GetAttribute("sh-logic-primary' .. index .. '")==true') or row.condition == "always" and "true" or
            (row.condition == "present" and ("p" .. index .. "==true") or ("p" .. index .. "==false"))
        local modifierCondition = row.skipModifier and ('not modifier_' .. row.skipModifier) or nil
        if hasPriorityModifier then
            local prioritized = row.priorityModifier and ('modifier_' .. row.priorityModifier) or 'false'
            local priorityCondition = '(modifierPass==1)==(' .. prioritized .. ')'
            modifierCondition = modifierCondition and (modifierCondition .. ' and (' .. priorityCondition .. ')') or priorityCondition
        end
        lines[#lines + 1] = modifierCondition and ('if ' .. modifierCondition .. ' then') or 'do'
        if row.oncePerProc then
            lines[#lines + 1] = 'local g=self:GetFrameRef("proc' .. index .. '")'
            lines[#lines + 1] = 'if not g then self:SetAttribute("sh-valid",false); return false end'
            lines[#lines + 1] = 'local e=g:GetAttribute("sh-proc-epoch")'
            lines[#lines + 1] = 'if e==nil then self:SetAttribute("sh-valid",false); return false end'
            primary = primary .. ' and self:GetAttribute("sh-used' .. index .. '")~=e'
        end
        primary = countMatch(row, index, "primary", primary, false)
        if row.condition ~= "always" then primary = auraMatch(row.auraSource, primary) end
        lines[#lines + 1] = 'local m=' .. primary
        local condition = 'm'
        local hasAnyOr = row.useOr or #(row.orConditions or {}) > 0 or hasLogicOr
        local legacyOr = row.useOr and auraMatch(row.orAuraSource, 'o' .. index .. (row.orCondition == "missing" and '==false' or '==true')) or 'false'
        legacyOr = countMatch(row, index, "or", legacyOr, false)
        if hasAnyOr then
            local alternative = legacyOr
            if #(row.orConditions or {}) > 0 then
                alternative = '(' .. alternative .. ' or self:GetAttribute("sh-extra-or-count' .. index .. '")==true)'
            end
            if hasLogicOr then alternative = '(' .. alternative .. ' or self:GetAttribute("sh-logic-or' .. index .. '")==true)' end
            lines[#lines + 1] = 'local n=' .. alternative
            condition = '(m or n)'
        end
        if Model.HasExtraConditions(row) then
            condition = condition .. ' and self:GetAttribute("sh-extra-count' .. index .. '")==true'
        end
        if #logicRows[index] > 0 then condition = condition .. ' and self:GetAttribute("sh-logic-all' .. index .. '")==true' end
        if (row.castCount or 0) > 0 then
            condition = condition .. ' and self:GetAttribute("sh-count-available' .. index .. '")==true'
        end
        if row.skipCooldown and not row.manualCooldown then
            condition = condition .. ' and cooldownReady' .. index
        end
        if row.comboPoints then
            condition = condition .. ' and comboCount' .. comboOperators[row.comboPoints.operator] .. row.comboPoints.value
        end
        if row.customCondition then
            condition = condition .. ' and SecureCmdOptionParse(' .. literal(row.customCondition .. "1") .. ')=="1"'
        end
        if row.outOfCombatOnly then
            condition = condition .. ' and SecureCmdOptionParse("[nocombat]1")=="1"'
        end
        if row.inCombatOnly then
            condition = condition .. ' and SecureCmdOptionParse("[combat]1")=="1"'
        end
        if row.reactiveReady then
            -- Usability is a requirement of the selected spell, so an OR
            -- condition cannot bypass its window, resource or cooldown check.
            condition = condition .. ' and ' .. reactiveValue(row.reactiveReady) .. '==true'
            if castUnit ~= "none" then
                condition = condition .. ' and SecureCmdOptionParse(' .. literal("[@" .. castUnit .. ",exists,harm,nodead]1") .. ')=="1"'
            end
        elseif row.riposteReady then
            -- An alternative condition cannot make Riposte castable after its window closes.
            if hasAnyOr then condition = condition .. ' and p' .. index .. '==true' end
            if castUnit ~= "none" then
                condition = condition .. ' and SecureCmdOptionParse(' .. literal("[@" .. castUnit .. ",exists,harm,nodead]1") .. ')=="1"'
            end
        elseif row.unit == "focustarget" or (row.unit == "custom" and castUnit ~= "none") then
            condition = condition .. ' and SecureCmdOptionParse(' .. literal("[@" .. castUnit .. ",exists]1") .. ')=="1"'
        end
        if row.petAttack then
            condition = condition .. ' and targetValid and SecureCmdOptionParse("[@pet,exists,nodead]1")=="1"'
        elseif row.startAttack then
            -- Blizzard's melee spell can toggle off. Only issue it after a
            -- fresh, explicitly inactive reading on this hardware click.
            condition = condition .. ' and targetValid and rawtype(self:GetAttribute("sh-read-wand"))=="string"'
                .. ' and self:RunAttribute("sh-read-wand",6603)==true and self:GetAttribute("sh-wand-active")==false'
            if castPass or customPass then condition = 'false' end
        end
        if row.customRule and castPass then condition = 'false' end
        if row.customRule or commandPass and row.startAttack then
            condition = condition .. ' and self:GetAttribute("sh-command-done' .. index .. '")~=true'
        end
        if Model.UsesTargetSnapshot(row) then
            condition = condition .. ' and self:GetAttribute("sh-command-target-dirty")~=true'
        end
        if row.advanceOnToggle then
            -- Highest learned casts use their resolved name; an explicit rank
            -- uses its exact ID. Only a fresh inactive result permits another
            -- attempt. Unknown state skips this rule without changing others.
            local repeatAction = row.rangedRepeat or row.wandShoot
            local identifier = repeatAction and row.spellID or row.spell
            condition = condition .. ' and rawtype(self:GetAttribute("sh-read-wand"))=="string"'
                .. ' and self:RunAttribute("sh-read-wand",' .. literal(identifier) .. (repeatAction and '' or ',true') .. ')==true'
                .. ' and self:GetAttribute("sh-wand-active")==false'
        end
        if row.targetCasting or row.totemCondition ~= nil or row.hawkCount ~= nil or #(row.resourceConditions or {}) > 0 or #(row.healthConditions or {}) > 0 or #(row.stackConditions or {}) > 0
            or row.pingDelay or row.manualCooldown or row.skipIfNotCasted or row.skipIfImmune or row.skipOutOfRange then
            lines[#lines + 1] = 'local eligible=' .. condition
            if row.hawkCount ~= nil then
                -- All qualifying Hawk rules share one fresh count for this
                -- selection. Unknown state skips only Hawk-dependent rules.
                lines[#lines + 1] = 'if eligible and hawkCount==nil then'
                lines[#lines + 1] = 'hawkCount=-1'
                lines[#lines + 1] = 'self:SetAttribute("sh-hawk-count",nil)'
                lines[#lines + 1] = 'if rawtype(self:GetAttribute("sh-hawk-read"))=="string" and self:RunAttribute("sh-hawk-read")==true then'
                lines[#lines + 1] = 'local observed=self:GetAttribute("sh-hawk-count")'
                lines[#lines + 1] = 'if rawtype(observed)=="number" and observed>=0 and observed<=2 and observed%1==0 then hawkCount=observed end end end'
                lines[#lines + 1] = 'eligible=eligible and hawkCount>=0 and hawkCount' .. hawkOperators[row.hawkCount.operator] .. row.hawkCount.value
            end
            if row.totemCondition ~= nil then
                -- Each element gets its own reading for this selection. An
                -- unavailable slot skips only the rows that depend on it.
                local element = Model.TotemConditionElement(row.totemCondition)
                local slot = element .. "Slot"
                lines[#lines + 1] = 'if eligible and ' .. slot .. '==nil then'
                lines[#lines + 1] = slot .. '=rawtype(self:GetAttribute("shfire-read-slot"))=="string" and self:RunAttribute("shfire-read-slot",' .. literal(element) .. ') or "unknown" end'
                lines[#lines + 1] = 'eligible=eligible and ' .. (fireSlotMatches[row.totemCondition] or 'false')
            end
            if row.skipOutOfRange then
                lines[#lines + 1] = 'if eligible and rawtype(self:GetAttribute("sh-read-range"))=="string" then'
                lines[#lines + 1] = 'self:SetAttribute("sh-out-of-range",nil)'
                lines[#lines + 1] = 'if self:RunAttribute("sh-read-range",' .. index .. ')==true and self:GetAttribute("sh-out-of-range")==true then eligible=false end end'
            end
            if row.skipIfImmune then
                -- Unavailable evidence must not mark an enemy immune. A
                -- positive reading gates every alternative for this rule.
                lines[#lines + 1] = 'if eligible then self:SetAttribute("sh-immunity-skip",nil)'
                lines[#lines + 1] = 'if rawtype(self:GetAttribute("sh-read-immunity-skip"))=="string" and self:RunAttribute("sh-read-immunity-skip",' .. index .. ',' .. literal(castUnit) .. ')==true and self:GetAttribute("sh-immunity-skip")==true then eligible=false end end'
            end
            if row.skipIfNotCasted then
                -- Only a positive, fresh failure skips a rule. Previewing it
                -- here must leave the same answer for the final native click.
                lines[#lines + 1] = 'if eligible then self:SetAttribute("sh-position-skip",nil)'
                lines[#lines + 1] = 'if self:RunAttribute("sh-read-position-skip",' .. index .. ')==true and self:GetAttribute("sh-position-skip")==true then eligible=false end end'
            end
            if row.targetCasting then
                -- The reader checks the current target. All qualifying rules in
                -- this selection share the same fresh answer, including a miss.
                lines[#lines + 1] = 'if eligible and targetCasting==nil then'
                lines[#lines + 1] = 'self:SetAttribute("sh-target-casting",nil)'
                lines[#lines + 1] = 'targetCasting=rawtype(self:GetAttribute("sh-read-target-casting"))=="string"'
                lines[#lines + 1] = 'and self:RunAttribute("sh-read-target-casting")==true and self:GetAttribute("sh-target-casting")==true end'
                lines[#lines + 1] = 'eligible=eligible and targetCasting==true'
            end
            for _ in ipairs(row.resourceConditions or {}) do
                resourceIndex = resourceIndex + 1
                appendGate("sh-read-resource", "sh-resource-pass", resourceIndex)
            end
            for _ in ipairs(row.healthConditions or {}) do
                healthIndex = healthIndex + 1
                -- The reader checks this condition's player or target unit
                -- independently of Cast on. Unknown skips only this candidate.
                lines[#lines + 1] = 'if eligible then'
                lines[#lines + 1] = 'self:SetAttribute("sh-health-pass",nil)'
                lines[#lines + 1] = 'eligible=rawtype(self:GetAttribute("sh-read-health"))=="string"'
                    .. ' and self:RunAttribute("sh-read-health",' .. healthIndex .. ')==true and self:GetAttribute("sh-health-pass")==true'
                lines[#lines + 1] = 'end'
            end
            for _ in ipairs(row.stackConditions or {}) do
                stackIndex = stackIndex + 1
                -- Each aura stack check applies to every IF / OR alternative.
                -- An unknown reading skips only the rule that depends on it.
                lines[#lines + 1] = 'if eligible then'
                lines[#lines + 1] = 'self:SetAttribute("sh-stacks-pass",nil)'
                lines[#lines + 1] = 'eligible=rawtype(self:GetAttribute("sh-read-stacks"))=="string"'
                    .. ' and self:RunAttribute("sh-read-stacks",' .. stackIndex .. ')==true and self:GetAttribute("sh-stacks-pass")==true'
                lines[#lines + 1] = 'end'
            end
            if row.pingDelay or row.manualCooldown then appendGate("sh-read-ping", "sh-ping-pass", index) end
            condition = 'eligible'
        end
        lines[#lines + 1] = 'if ' .. condition .. ' then'
        if row.petAttack then
            -- An idle pet can retry an unacknowledged order. An engaged pet
            -- issues another order only when it needs to change targets.
            lines[#lines + 1] = 'local petCheck=SecureCmdOptionParse("[@pettarget,exists,harm,nodead]1")=="1" and 0 or -11'
            lines[#lines + 1] = 'local issue=self:RunAttribute("sh-read-wand",petCheck)==true and self:GetAttribute("sh-wand-active")==false'
            -- Pet Attack can move to any of the ten native pet action slots.
            -- Read the command identity again for each order, including after
            -- a pet swap. Never cast a different action from an old slot.
            lines[#lines + 1] = 'local petSlot'
            lines[#lines + 1] = 'if issue then for slot=1,10 do'
            lines[#lines + 1] = 'if self:RunAttribute("sh-read-wand",-slot)~=true then break end'
            lines[#lines + 1] = 'if self:GetAttribute("sh-wand-active")==true then petSlot=slot; break end'
            lines[#lines + 1] = 'end end'
            lines[#lines + 1] = 'if petSlot then'
        end
        if autoPass and not row.startAttack and not ((commandPass or customPass) and row.customRule) then
            -- An earlier eligible spell still wins priority. This prepass may
            -- inspect its gates, but must not arm a cast batch or consume a proc.
            lines[#lines + 1] = 'return false'
        else
        if row.unit == "party1" or row.unit == "party2" or row.unit == "party3" or row.unit == "party4" then
            -- Never let a missing party slot become a target/self cast. The
            -- game checks spell-specific requirements, including resurrection.
            lines[#lines + 1] = 'if SecureCmdOptionParse(' .. literal('[@' .. row.unit .. ',exists]1') .. ')~="1" then self:SetAttribute("sh-valid",false); return false end'
        end
        if (row.castCount or 0) > 0 then
            -- Only the selected predicate can start its batch. Once started,
            -- every matching native spell/rank success counts, including OR.
            local attachment = Model.GetCountCondition(row)
            local counted, bypass
            if attachment.key == "primary" then
                counted, bypass = 'm', hasAnyOr and 'n' or 'false'
            elseif attachment.key == "or" then
                counted = '(' .. legacyOr .. ')'
                bypass = '(m or self:GetAttribute("sh-extra-or-count' .. index .. '")==true)'
                if hasLogicOr then bypass = '(' .. bypass .. ' or self:GetAttribute("sh-logic-or' .. index .. '")==true)' end
            elseif attachment.kind == "OR" then
                counted = 'self:GetAttribute("sh-count-match' .. index .. '")==true'
                bypass = '(m or (' .. legacyOr .. ') or self:GetAttribute("sh-extra-or-bypass' .. index .. '")==true)'
                if hasLogicOr then bypass = '(' .. bypass .. ' or self:GetAttribute("sh-logic-or' .. index .. '")==true)' end
            else
                counted = 'self:GetAttribute("sh-count-match' .. index .. '")==true'
                bypass = 'false'
            end
            lines[#lines + 1] = 'local g=self:GetFrameRef("count' .. index .. '")'
            lines[#lines + 1] = 'if ' .. counted .. ' then g:SetAttribute("sh-started",true) end'
            lines[#lines + 1] = 'if ' .. counted .. ' and k' .. index .. '==' .. (row.castCount - 1) ..
                ' and not (' .. bypass .. ') and g:RunAttribute("sh-casting")==true then'
            lines[#lines + 1] = 'self:SetAttribute("sh-count-wait",true)'
            lines[#lines + 1] = 'self:SetAttribute("type","macro")'
            lines[#lines + 1] = 'self:SetAttribute("macrotext","/cancelqueuedspell")'
            lines[#lines + 1] = 'return end'
        end
        -- An explicit @target makes Blizzard cancel a summon before the
        -- spell executes if nothing is targeted. A normal totem has no unit.
        lines[#lines + 1] = 'self:SetAttribute("unit",' .. (row.castAtFeet and "nil" or literal(castUnit)) .. ')'
        lines[#lines + 1] = 'self:SetAttribute("selected-row",' .. index .. ')'
        lines[#lines + 1] = 'self:SetAttribute("selected-primary",m)'
        lines[#lines + 1] = 'self:SetAttribute("selected-or",' .. (hasAnyOr and 'n' or 'false') .. ')'
        lines[#lines + 1] = 'self:SetAttribute("selected-legacy-or",' .. legacyOr .. ')'
        if row.rangedRepeat or row.wandShoot then
            -- Read the native repeat state on this click. A remembered attempt
            -- would prevent retrying a failed start or restarting after moving.
            lines[#lines + 1] = 'if self:RunAttribute("sh-read-wand",' .. literal(row.spellID) .. ')~=true then self:SetAttribute("sh-valid",false); return false end'
            lines[#lines + 1] = 'local active=self:GetAttribute("sh-wand-active")'
            lines[#lines + 1] = 'if rawtype(active)~="boolean" then self:SetAttribute("sh-valid",false); return false end'
            lines[#lines + 1] = 'if active then self:SetAttribute("sh-wand-hold",true); return end'
        end
        if row.customRule then
            lines[#lines + 1] = 'self:SetAttribute("type","macro")'
            lines[#lines + 1] = 'self:SetAttribute("macrotext",' .. literal(row.customRule) .. ')'
            lines[#lines + 1] = 'self:SetAttribute("sh-command-executes",' .. Model.CustomRuleExecutesExpression(row.customRule) .. ')'
            lines[#lines + 1] = 'self:SetAttribute("sh-command-target-change",' .. Model.CustomRuleTargetChangeExpression(row.customRule) .. ')'
        elseif row.petAttack then
            lines[#lines + 1] = 'self:SetAttribute("sh-pet-attack",true)'
            lines[#lines + 1] = 'self:SetAttribute("type","pet")'
            lines[#lines + 1] = 'self:SetAttribute("action",petSlot)'
        else
            local cast = (row.rangedRepeat or row.wandShoot) and row.spellID or row.spell
            lines[#lines + 1] = 'self:SetAttribute("spell",' .. literal(cast) .. ')'
        end
        if not autoPass then
        if row.oncePerProc then
            lines[#lines + 1] = 'if m then'
            lines[#lines + 1] = 'self:SetAttribute("sh-pending-row",' .. index .. ')'
            lines[#lines + 1] = 'self:SetAttribute("sh-pending-epoch",e)'
            lines[#lines + 1] = 'else'
        end
        lines[#lines + 1] = 'self:SetAttribute("sh-pending-row",nil)'
        lines[#lines + 1] = 'self:SetAttribute("sh-pending-epoch",nil)'
        if row.oncePerProc then lines[#lines + 1] = 'end' end
        end
        lines[#lines + 1] = 'return'
        end
        lines[#lines + 1] = 'end'
        if row.petAttack then lines[#lines + 1] = 'end' end
        lines[#lines + 1] = 'end'
    end
    if hasPriorityModifier then lines[#lines + 1] = 'end' end
    if not autoPass and (hasCounts or hasCombo or hasHawks or hasResources or hasHealth or hasStacks or hasLogic or hasPing or hasTargetCasting or hasRiposte or next(reactiveSpells) or hasPositionSkip or hasImmunitySkip or hasFireTotems or hasRangeSkip or hasOutOfCombat or hasInCombat or hasConditionCooldowns or next(usedModifiers)) then
        -- A stale queued request must not survive a press with no matching rule.
        -- Direct keys and the generated macro also cancel at their own level.
        lines[#lines + 1] = 'self:SetAttribute("type","macro")'
        lines[#lines + 1] = 'self:SetAttribute("macrotext","/cancelqueuedspell")'
        lines[#lines + 1] = 'return'
    else
        lines[#lines + 1] = 'return false'
    end
    if #formChecks > 0 then
        table.insert(lines, beforeEpochs, table.concat(formChecks, "\n"))
    end
    return table.concat(lines, "\n")
end

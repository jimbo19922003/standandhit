local _, SH = ...
local Explanation = {}
SH.Explanation = Explanation

local MAX_RULES = 32
local units = {player = "yourself", target = "your target", focus = "your focus", focustarget = "your focus's target", mouseover = "your mouseover",
    party1 = "party member 1", party2 = "party member 2", party3 = "party member 3", party4 = "party member 4"}
local conditions = {present = true, missing = true, always = true}
local auraSources = {tracker = true, target = true, player = true}
local extraGroups = {{field = "andConditions", label = "AND"}, {field = "orConditions", label = "OR"}, {field = "notConditions", label = "NOT"}}
local resourceNames = {mana = "mana", rage = "rage", energy = "energy"}
local resourceComparisons = {lt = "below ", ge = "at least "}
local stackComparisons = {lt = "fewer than ", le = "at most ", eq = "exactly ", ne = "not exactly ", ge = "at least ", gt = "more than "}
local modifierNames = {ctrl = "Ctrl", alt = "Alt", shift = "Shift"}
local fireTotemNames = {searing = "Searing Totem", magma = "Magma Totem"}
local totemSlotConditions = {
    ["fire-active"] = {element = "fire"}, missing = {element = "fire", missing = true},
    ["earth-active"] = {element = "earth"}, ["earth-missing"] = {element = "earth", missing = true},
    ["water-active"] = {element = "water"}, ["water-missing"] = {element = "water", missing = true},
    ["air-active"] = {element = "air"}, ["air-missing"] = {element = "air", missing = true},
}

local function manualCooldownSeconds(value, enabled)
    if SH.Model and SH.Model.NormalizeManualCooldownSeconds then
        return SH.Model.NormalizeManualCooldownSeconds(value, enabled)
    end
    if enabled ~= nil and type(enabled) ~= "boolean" then return nil, "Manual cooldown must be on or off." end
    value = value == nil and 0 or value
    if type(value) ~= "number" or value ~= value or value < 0 or value > 86400
        or math.abs(value * 1000 - math.floor(value * 1000 + 0.5)) > 0.0000001 then
        return nil, "Manual cooldown must be from 0 to 86400 seconds with at most 3 decimal places."
    end
    if enabled == true and value < 0.001 then return nil, "Manual cooldown must be from 0.001 to 86400 seconds when enabled." end
    return value
end

local function modifier(value)
    if SH.Model and SH.Model.NormalizeModifier then return SH.Model.NormalizeModifier(value) end
    if value == nil then return nil end
    if type(value) ~= "string" or not modifierNames[value] then
        return nil, "Choose Ctrl, Alt, Shift, or Off for the modifier."
    end
    return value
end

local function resourceConditions(value)
    if SH.Model and SH.Model.NormalizeResourceConditions then return SH.Model.NormalizeResourceConditions(value) end
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "Resource conditions must be a numbered list." end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > 8 or key % 1 ~= 0 then return nil, "Use at most 8 resource conditions in a numbered list." end
        count = count + 1
    end
    for index = 1, count do
        local item = value[index]
        if type(item) ~= "table" then return nil, "Complete resource condition " .. index .. "." end
        for key in pairs(item) do
            if key ~= "resource" and key ~= "operator" and key ~= "percent" then return nil, "The resource condition has an unknown setting." end
        end
        if type(item.resource) ~= "string" or not resourceNames[item.resource] then return nil, "Choose Mana, Rage, or Energy." end
        if type(item.operator) ~= "string" or not resourceComparisons[item.operator] then return nil, "Choose a resource comparison." end
        if type(item.percent) ~= "number" or item.percent < 0 or item.percent > 100 or item.percent % 1 ~= 0 then return nil, "Choose a whole percentage from 0 to 100." end
    end
    return value
end

local function healthConditions(value)
    if SH.Model and SH.Model.NormalizeHealthConditions then return SH.Model.NormalizeHealthConditions(value) end
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "Health conditions must be a numbered list." end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > 8 or key % 1 ~= 0 then return nil, "Use at most 8 health conditions in a numbered list." end
        count = count + 1
    end
    for index = 1, count do
        local item = value[index]
        if type(item) ~= "table" then return nil, "Complete health condition " .. index .. "." end
        for key in pairs(item) do
            if key ~= "operator" and key ~= "percent" and key ~= "unit" then return nil, "The health condition has an unknown setting." end
        end
        if item.unit ~= nil and item.unit ~= "target" and item.unit ~= "player" then return nil, "Choose Self health or Enemy health." end
        if type(item.operator) ~= "string" or not resourceComparisons[item.operator] then return nil, "Choose a health comparison." end
        if type(item.percent) ~= "number" or item.percent < 0 or item.percent > 100 or item.percent % 1 ~= 0 then return nil, "Choose a whole percentage from 0 to 100." end
    end
    return value
end

local function stackConditions(value)
    if SH.Model and SH.Model.NormalizeStackConditions then return SH.Model.NormalizeStackConditions(value) end
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "Aura stack conditions must be a numbered list." end
    local count, result = 0, {}
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > 8 or key % 1 ~= 0 then
            return nil, "Use at most 8 aura stack conditions in a numbered list."
        end
        count = count + 1
    end
    for index = 1, count do
        local item = value[index]
        if type(item) ~= "table" then return nil, "Complete aura stack condition " .. index .. "." end
        for key in pairs(item) do
            if key ~= "aura" and key ~= "auraSource" and key ~= "operator" and key ~= "value" then
                return nil, "The aura stack condition has an unknown setting."
            end
        end
        if type(item.aura) ~= "string" or #item.aura > 200 or item.aura:find("[%z\1-\31\127]") then
            return nil, "Enter an aura name or ID, up to 200 characters."
        end
        local aura = item.aura:match("^%s*(.-)%s*$")
        if aura == "" then return nil, "Enter the aura name or ID." end
        if item.auraSource ~= "player" and item.auraSource ~= "target" then return nil, "Choose Player buff or Target debuff." end
        if type(item.operator) ~= "string" or not stackComparisons[item.operator] then return nil, "Choose a stack comparison." end
        if type(item.value) ~= "number" or item.value < 0 or item.value > 99 or item.value % 1 ~= 0 then
            return nil, "Choose a whole stack count from 0 to 99."
        end
        result[index] = {aura = aura, auraSource = item.auraSource, operator = item.operator, value = item.value}
    end
    return result
end

local function logicConditions(value)
    if SH.Model and SH.Model.NormalizeLogicConditions then return SH.Model.NormalizeLogicConditions(value) end
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "Added conditions must be a numbered list." end
    local fields = {
        comboPoints = {operator = true, value = true}, hawkCount = {operator = true, value = true},
        resource = {resource = true, operator = true, percent = true},
        health = {unit = true, operator = true, percent = true},
        stacks = {aura = true, auraSource = true, operator = true, value = true},
        auraTime = {aura = true, unit = true, operator = true, seconds = true},
        targetCasting = {}, totemCondition = {value = true}, customCondition = {value = true},
    }
    local count, result = 0, {}
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > 8 or key % 1 ~= 0 then
            return nil, "Use at most 8 added conditions in a numbered list."
        end
        count = count + 1
    end
    for index = 1, count do
        local item, prefix = value[index], "Added condition " .. index .. ": "
        if type(item) ~= "table" then return nil, prefix .. "choose AND, OR, or NOT and a condition type." end
        if item.logic ~= "AND" and item.logic ~= "OR" and item.logic ~= "NOT" then return nil, prefix .. "choose AND, OR, or NOT." end
        local allowed = type(item.type) == "string" and fields[item.type]
        if not allowed then return nil, prefix .. "choose a supported condition type." end
        local payload = {}
        for key, setting in pairs(item) do
            if key ~= "logic" and key ~= "type" then
                if not allowed[key] then return nil, prefix .. "unknown setting." end
                payload[key] = setting
            end
        end
        local normalized, reason
        if item.type == "comboPoints" or item.type == "hawkCount" then
            local supported = item.type == "hawkCount" and stackComparisons
                or {ge = true, le = true, eq = true, ne = true}
            if type(payload.operator) ~= "string" or not supported[payload.operator]
                or type(payload.value) ~= "number" or payload.value < 0
                or payload.value > (item.type == "comboPoints" and 5 or 2) or payload.value % 1 ~= 0 then
                return nil, prefix .. "choose a valid count comparison and whole number."
            end
            normalized = payload
        elseif item.type == "resource" or item.type == "health" or item.type == "stacks" then
            if item.type == "health" and payload.unit ~= "target" and payload.unit ~= "player" then
                return nil, prefix .. "choose Enemy health or Self health."
            end
            local normalize = item.type == "resource" and resourceConditions
                or item.type == "health" and healthConditions or stackConditions
            local list; list, reason = normalize({payload}); normalized = list and list[1]
            if normalized and item.type == "health" then normalized.unit = payload.unit end
        elseif item.type == "auraTime" then
            if payload.unit ~= "player" and payload.unit ~= "target" then return nil, prefix .. "choose Player buff or Target debuff." end
            if type(payload.aura) ~= "string" or not payload.aura:match("%S") or #payload.aura > 200 or payload.aura:find("[%z\1-\31\127]") then
                return nil, prefix .. "enter the aura name or spell ID."
            end
            if type(payload.operator) ~= "string" or not stackComparisons[payload.operator] then return nil, prefix .. "choose a time comparison." end
            if type(payload.seconds) ~= "number" or payload.seconds < 0 or payload.seconds > 60 or payload.seconds % 1 ~= 0 then
                return nil, prefix .. "enter whole seconds from 0 to 60."
            end
            payload.aura = payload.aura:match("^%s*(.-)%s*$")
            normalized = payload
        elseif item.type == "targetCasting" then normalized = payload
        elseif item.type == "totemCondition" then
            if payload.value ~= "active" and not totemSlotConditions[payload.value] and not fireTotemNames[payload.value] then
                return nil, prefix .. "choose a valid totem condition."
            end
            normalized = payload
        elseif item.type == "customCondition" then
            local expression = payload.value
            if type(expression) ~= "string" or #expression > 254 or expression:find("[%c;|]") then
                return nil, prefix .. "enter only bracketed macro conditions, up to 254 characters."
            end
            expression = expression:match("^%s*(.-)%s*$")
            if expression == "" then return nil, prefix .. "enter a macro condition." end
            local rest = expression
            while rest ~= "" do
                local block, tail = rest:match("^%[([^%[%]]*)%]%s*(.*)$")
                if not block then return nil, prefix .. "use bracketed macro conditions." end
                if block:match("%S") then
                    for word in (block .. ","):gmatch("(.-),") do
                        local token = word:match("^%s*(.-)%s*$")
                        if token == "" or token:find("[\\]") then return nil, prefix .. "invalid macro condition." end
                        local unit = token:match("^@(.+)$") or token:match("^[Tt][Aa][Rr][Gg][Ee][Tt]=(.+)$")
                        if unit then
                            if not unit:match("^[%a\128-\255][%w'%-\128-\255]*$") or unit:lower():match("^nameplate%d") then
                                return nil, prefix .. "invalid macro target."
                            end
                        else
                            local keyword, argument = token:match("^(%a[%w]*):(.+)$")
                            keyword = keyword or token:match("^(%a[%w]*)$")
                            if not keyword or (argument and (argument:match("^%s*/") or argument:match("/%s*$")
                                or argument:match("/%s*/") or argument:find("[=@]") or not argument:match("%S"))) then
                                return nil, prefix .. "invalid macro condition."
                            end
                        end
                    end
                end
                rest = tail
            end
            normalized = {value = expression}
        end
        if not normalized then return nil, prefix .. (reason or "invalid condition.") end
        normalized.logic, normalized.type = item.logic, item.type
        result[index] = normalized
    end
    return result
end

local function primaryCondition(value)
    if SH.Model and SH.Model.NormalizePrimaryCondition then return SH.Model.NormalizePrimaryCondition(value) end
    if value == nil then return nil end
    if type(value) ~= "table" then return nil, "IF: choose a condition type and its settings." end
    if value.logic ~= nil then return nil, "IF does not take AND, OR, or NOT." end
    local candidate = {}
    for key, setting in pairs(value) do candidate[key] = setting end
    candidate.logic = "AND"
    local normalized, reason = logicConditions({candidate})
    if not normalized then return nil, "IF: " .. (reason or "invalid condition.") end
    normalized[1].logic = nil
    return normalized[1]
end

local function trim(value)
    if type(value) ~= "string" and type(value) ~= "number" then return "" end
    return tostring(value):match("^%s*(.-)%s*$")
end

local function add(tokens, text, bold)
    tokens[#tokens + 1] = {text = text, bold = bold == true}
end

local function keyword(tokens, word)
    add(tokens, word, true)
end

local function paragraph(paragraphs, kind, text, ruleIndex)
    local item = {kind = kind, ruleIndex = ruleIndex, tokens = {}}
    if text then add(item.tokens, text) end
    paragraphs[#paragraphs + 1] = item
    return item.tokens
end

local function name(value, resolver)
    local text = trim(value)
    if type(resolver) == "function" then
        local ok, resolved = pcall(resolver, value)
        if ok and type(resolved) == "string" and trim(resolved) ~= "" then return trim(resolved) end
    end
    return text
end

local function joined(op, first, second)
    if not first then return second end
    if not second then return first end
    return {op = op, first = first, second = second}
end

local function auraExpression(aura, source, present, excluded, number)
    if source == "cooldown" then
        return {kind = "spellCooldown", name = aura, onCooldown = present, excluded = excluded, number = number}
    end
    local expression = {kind = excluded and "excludedAura" or "aura", name = aura, present = present, source = source, number = number}
    -- A target exclusion still needs a valid target; an unavailable target is not a negative match.
    if source == "target" then expression = joined("and", {kind = "target"}, expression) end
    return expression
end

local function requiresReactiveReady(expression)
    if not expression then return false end
    if expression.op == "and" then
        return requiresReactiveReady(expression.first) or requiresReactiveReady(expression.second)
    elseif expression.op == "or" then
        return requiresReactiveReady(expression.first) and requiresReactiveReady(expression.second)
    end
    return expression.kind == "reactiveReady" and expression.present ~= (expression.excluded == true)
end

-- The explanation can also be loaded on its own by offline readers.
local function conditionEntries(row)
    if SH.Model and SH.Model.ConditionEntries then return SH.Model.ConditionEntries(row) end
    local entries = {}
    local function entry(key, kind, aura, source, condition)
        entries[#entries + 1] = {key = key, number = #entries + 1, kind = kind,
            aura = aura or "", auraSource = source or "tracker", condition = condition or "present"}
    end
    entry("primary", "IF", row.aura, row.auraSource,
        row.condition == "always" and row.manualCooldown == true and "manualCooldown" or row.condition)
    if type(row.primaryCondition) == "table" then
        local item, current = row.primaryCondition, entries[1]
        current.condition, current.aura, current.auraSource = item.type, item.aura or "", item.auraSource
        current.unit = item.unit
    end
    if row.useOr == true then entry("or", "OR", row.orAura, row.orAuraSource, row.orCondition) end
    for _, group in ipairs(extraGroups) do
        for index, item in ipairs(row[group.field] or {}) do
            entry(group.field .. ":" .. index, group.label, item.aura, item.auraSource, item.condition)
        end
    end
    if (row.condition or "present") ~= "always" or row.primaryCondition ~= nil then
        if row.manualCooldown == true then entry("manualCooldown", "AND", "", nil, "manualCooldown")
        elseif row.skipCooldown == true then entry("cooldown", "AND", "", nil, "cooldown") end
    end
    if row.comboPoints ~= nil then entry("comboPoints", "AND", "", nil, "comboPoints") end
    if row.hawkCount ~= nil then entry("hawkCount", "AND", "", nil, "hawkCount") end
    for index in ipairs(row.resourceConditions or {}) do
        entry("resourceConditions:" .. index, "AND", "", nil, "resource")
    end
    for index, item in ipairs(row.healthConditions or {}) do
        entry("healthConditions:" .. index, "AND", "", nil, "health")
        entries[#entries].unit = item.unit or "target"
    end
    for index, item in ipairs(row.stackConditions or {}) do
        entry("stackConditions:" .. index, "AND", item.aura, item.auraSource, "stacks")
    end
    if row.customCondition ~= nil then entry("customCondition", "AND", "", nil, "customCondition") end
    if row.targetCasting == true then entry("targetCasting", "AND", "", nil, "targetCasting") end
    if row.totemCondition ~= nil then entry("totemCondition", "AND", "", nil, "totemCondition") end
    for index, item in ipairs(row.logicConditions or {}) do
        entry("logicConditions:" .. index, item.logic, item.aura, item.auraSource, item.type)
        entries[#entries].group = "logicConditions"
        entries[#entries].unit = item.unit
    end
    return entries
end

local function describeRow(row, index, options)
    if type(row) ~= "table" then return nil, "This rule is incomplete. Add a spell and choose its conditions." end
    local spell, aura = trim(row.spell), trim(row.aura)
    local customRule, customRuleError, customChangesTarget
    if row.customRule ~= nil then
        customRule, customRuleError, customChangesTarget = SH.Model.NormalizeCustomRule(row.customRule)
        if not customRule then return nil, customRuleError end
        spell = "Custom Rule"
    end
    local condition, unit = row.condition or "present", row.unit or "target"
    local primary, primaryError = primaryCondition(row.primaryCondition)
    if primaryError then return nil, primaryError end
    if primary then condition, aura = "always", "" end
    local auraSource = row.auraSource == nil and "tracker" or row.auraSource
    local orAuraSource = row.orAuraSource == nil and "tracker" or row.orAuraSource
    if spell == "" then return nil, "Enter a spell name or ID for this rule." end
    if #spell > 200 or #aura > 200 then return nil, "Shorten this rule's spell or aura name to 200 characters or fewer." end
    if not conditions[condition] then return nil, "Choose Aura is present, Aura is missing, or Always for this rule." end
    if not auraSources[auraSource] then return nil, "Choose Tracked aura, Target debuff, or Player buff for the primary condition." end
    if not auraSources[orAuraSource] and orAuraSource ~= "cooldown" then
        return nil, "Choose Tracked aura, Target debuff, Player buff, or Spell cooldown for the OR condition."
    end
    local recipient = units[unit]
    if row.targetCasting ~= nil and type(row.targetCasting) ~= "boolean" then
        return nil, "Target is casting must be on or off."
    end
    if row.outOfCombatOnly ~= nil and type(row.outOfCombatOnly) ~= "boolean" then
        return nil, "Out of combat only must be on or off."
    end
    if row.inCombatOnly ~= nil and type(row.inCombatOnly) ~= "boolean" then
        return nil, "In combat only must be on or off."
    end
    if row.outOfCombatOnly and row.inCombatOnly then
        return nil, "Choose either In combat only or Out of combat only."
    end
    local skipModifier, modifierError = modifier(row.skipModifier)
    if modifierError then return nil, "Skip modifier: " .. modifierError end
    local priorityModifier
    priorityModifier, modifierError = modifier(row.priorityModifier)
    if modifierError then return nil, "Priority modifier: " .. modifierError end
    local totem = row.totemCondition
    if totem ~= nil and totem ~= "active" and not totemSlotConditions[totem] and not fireTotemNames[totem] then
        return nil, "Choose a valid totem condition."
    end
    if unit == "custom" then
        recipient = trim(row.customTarget)
        if SH.Model and SH.Model.NormalizeMacroTarget then
            local target, reason = SH.Model.NormalizeMacroTarget(recipient)
            if not target then return nil, reason end
            recipient = target
        elseif recipient == "" then return nil, "Enter a custom macro target." end
    elseif not recipient then
        return nil, "Choose a Cast on target for this rule."
    end
    if row.customCondition ~= nil then
        if SH.Model and SH.Model.NormalizeMacroCondition then
            local conditionText, reason = SH.Model.NormalizeMacroCondition(row.customCondition)
            if not conditionText then return nil, reason end
        elseif trim(row.customCondition) == "" then return nil, "Enter a macro condition." end
    end
    if condition ~= "always" and aura == "" then return nil, "Enter the aura to track, or choose Always for this rule." end
    if primary and row.oncePerProc == true then return nil, "Once per proc requires a present aura as IF." end
    if primary and row.stopWhenInvalid == true then return nil, "Stop if buffs change requires an aura as IF." end
    if row.oncePerProc == true and condition ~= "present" then return nil, "Once per proc requires Aura is present." end
    if row.oncePerProc == true and auraSource == "player" then return nil, "Once per proc cannot use Player buff as the IF condition." end
    if row.oncePerProc == true and options.preventClipping == false then return nil, "Enable Protect channels to use Once per proc." end
    local manualSeconds, manualError = manualCooldownSeconds(row.manualCooldownSeconds, row.manualCooldown)
    if manualSeconds == nil then return nil, manualError end
    local combo = row.comboPoints
    if combo ~= nil then
        local operators = {ge = true, le = true, eq = true, ne = true}
        if type(combo) ~= "table" or not operators[combo.operator] or type(combo.value) ~= "number"
            or combo.value < 0 or combo.value > 5 or combo.value % 1 ~= 0 then
            return nil, "Choose a combo-point comparison and a whole number from 0 to 5."
        end
        for key in pairs(combo) do
            if key ~= "operator" and key ~= "value" then return nil, "The combo-point condition has an unknown setting." end
        end
    end
    local hawks = row.hawkCount
    if hawks ~= nil then
        local operators = {lt = true, le = true, eq = true, ne = true, ge = true, gt = true}
        if type(hawks) ~= "table" or not operators[hawks.operator] or type(hawks.value) ~= "number"
            or hawks.value < 0 or hawks.value > 2 or hawks.value % 1 ~= 0 then
            return nil, "Choose a Hawk comparison and a whole number from 0 to 2."
        end
        for key in pairs(hawks) do
            if key ~= "operator" and key ~= "value" then return nil, "The Hawk condition has an unknown setting." end
        end
    end
    local resources, resourceError = resourceConditions(row.resourceConditions)
    if not resources then return nil, resourceError end
    local health, healthError = healthConditions(row.healthConditions)
    if not health then return nil, healthError end
    local stacks, stackError = stackConditions(row.stackConditions)
    if not stacks then return nil, stackError end
    local logic, logicError = logicConditions(row.logicConditions)
    if not logic then return nil, logicError end
    local logicOr, totals = false, {resource = #resources, health = #health, stacks = #stacks, auraTime = 0}
    if primary and totals[primary.type] then
        totals[primary.type] = totals[primary.type] + 1
        if totals[primary.type] > 8 then return nil, "Use at most 8 " .. primary.type .. " conditions across all operators." end
    end
    for _, item in ipairs(logic) do
        if item.logic == "OR" then logicOr = true end
        if totals[item.type] then
            totals[item.type] = totals[item.type] + 1
            if totals[item.type] > 8 then return nil, "Use at most 8 " .. item.type .. " conditions across all operators." end
        end
    end
    local castCount = row.castCount == nil and 0 or row.castCount
    if type(castCount) ~= "number" or castCount < 0 or castCount > 99 or castCount % 1 ~= 0 then
        return nil, "Number of times to cast must be a whole number from 1 to 99, or blank / 0 for unlimited."
    end
    if castCount > 0 and row.oncePerProc == true then return nil, "Number of times to cast cannot be combined with Once per proc." end
    if row.rankID ~= nil and (type(row.rankID) ~= "number" or row.rankID <= 0 or row.rankID % 1 ~= 0) then
        return nil, "Choose a valid spell rank for this rule."
    end
    local petAttack = SH.Model and SH.Model.IsPetAttack and SH.Model.IsPetAttack(spell)
    local startAttack = SH.Model and SH.Model.IsAutoAttack and SH.Model.IsAutoAttack(spell)
    local attackCommand = petAttack and "Pet Attack" or startAttack and "Auto Attack" or customRule and "Custom Rule"
    local id, resolvedSpell = row.rankID or tonumber(spell), nil
    local resolveSpell = SH.ResolveSpell or options.resolveSpell
    if not attackCommand and type(resolveSpell) == "function" then
        local ok, info = pcall(resolveSpell, spell, row.rankID)
        if ok and type(info) == "table" then id, resolvedSpell = info.id or id, info end
    end
    local rangedRepeat = id == 5019 or id == 75
    local reactive = not attackCommand and SH.Riposte and SH.Riposte.IsReactive
        and SH.Riposte.IsReactive(id) and type(SH.Riposte.MatchesCondition) == "function"
    if row.skipIfNotCasted ~= nil and type(row.skipIfNotCasted) ~= "boolean" then
        return nil, "Require being behind target must be on or off."
    end
    if row.skipIfNotCasted and (attackCommand or rangedRepeat) then
        return nil, "Choose a spell you cast directly to use Require being behind target."
    end
    if row.skipIfImmune ~= nil and type(row.skipIfImmune) ~= "boolean" then
        return nil, "Skip if immune (bleed) must be on or off."
    end
    if row.skipIfImmune and (attackCommand or rangedRepeat or row.advanceOnToggle == true) then
        return nil, "Choose a spell you cast directly to use Skip if immune (bleed)."
    end
    if row.skipOutOfRange ~= nil and type(row.skipOutOfRange) ~= "boolean" then
        return nil, "Skip if out of range must be on or off."
    end
    if row.skipOutOfRange and attackCommand then return nil, "Choose a spell to use Skip if out of range." end
    if row.advanceOnToggle ~= nil and type(row.advanceOnToggle) ~= "boolean" then
        return nil, "Advance on toggle must be on or off."
    end
    if row.advanceOnToggle and attackCommand then return nil, "Choose a spell to use Advance on toggle." end
    if attackCommand and unit ~= "target" then return nil, attackCommand .. " needs your current target." end
    if attackCommand and (row.rankID or row.skipCooldown or row.manualCooldown or row.pingDelay or castCount > 0
        or row.oncePerProc or row.stopCasting or row.stopWhenInvalid) then
        return nil, "Remove spell ranks, cooldowns, cast counts and cast interruption settings from " .. attackCommand .. "."
    end
    if rangedRepeat and castCount > 0 then return nil, "Remove Cast Count from this repeating shot." end
    local useOr, orAura, orCondition = row.useOr == true, trim(row.orAura), row.orCondition or "present"
    if useOr then
        if condition == "always" and not primary then return nil, "OR requires a conditional IF instead of Always." end
        if orAuraSource == "cooldown" then
            if orAura == "" then return nil, "Enter the spell for the OR cooldown condition." end
            if #orAura > 200 then return nil, "Shorten the OR cooldown spell name to 200 characters or fewer." end
            if orCondition ~= "present" and orCondition ~= "missing" then return nil, "Choose On cooldown or Off cooldown after OR." end
        else
            if orAura == "" then return nil, "Enter the second aura to track after OR." end
            if #orAura > 200 then return nil, "Shorten the second aura name to 200 characters or fewer." end
            if orCondition ~= "present" and orCondition ~= "missing" then return nil, "Choose Aura is present or Aura is missing after OR." end
        end
    end
    local extras, extraCount, hasExtraAuras = {}, 0, false
    for _, group in ipairs(extraGroups) do
        local list = row[group.field]
        extras[group.field] = {}
        if list ~= nil and type(list) ~= "table" then return nil, "Choose valid " .. group.label .. " conditions." end
        local listCount = 0
        for key in pairs(list or {}) do
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
                return nil, group.label .. " conditions must be a numbered list."
            end
            listCount = listCount + 1
        end
        for extraIndex = 1, listCount do
            local entry = list[extraIndex]
            extraCount = extraCount + 1
            if extraCount > 8 then return nil, "Use no more than 8 added AND, OR, and NOT conditions per rule." end
            if type(entry) ~= "table" then return nil, "Complete the added " .. group.label .. " condition." end
            local extraAura, source, state = trim(entry.aura), entry.auraSource, entry.condition
            if source == "cooldown" then
                if type(entry.aura) ~= "string" or extraAura == "" then return nil, "Enter the spell for the added " .. group.label .. " cooldown condition." end
                if #extraAura > 200 then return nil, "Shorten the added cooldown spell name to 200 characters or fewer." end
                if state ~= "present" and state ~= "missing" then return nil, "Choose On cooldown or Off cooldown for the added " .. group.label .. " condition." end
            else
                if type(entry.aura) ~= "string" or extraAura == "" then return nil, "Enter the aura for the added " .. group.label .. " condition." end
                if #extraAura > 200 then return nil, "Shorten the added aura name to 200 characters or fewer." end
                if not auraSources[source] then return nil, "Choose Tracked aura, Target debuff, Player buff, or Spell cooldown for the added " .. group.label .. " condition." end
                if state ~= "present" and state ~= "missing" then return nil, "Choose present or missing for the added " .. group.label .. " condition." end
                hasExtraAuras = true
            end
            extras[group.field][#extras[group.field] + 1] = entry
        end
    end
    if condition == "always" and not primary and (#extras.orConditions > 0 or logicOr) then return nil, "OR requires a conditional IF instead of Always." end
    local stopPrimary = condition == "present" and auraSource ~= "player"
    local stopOr = useOr and orCondition == "present" and orAuraSource ~= "player" and orAuraSource ~= "cooldown"
    if row.stopCasting == true and not stopPrimary and not stopOr then
        if auraSource == "player" or (useOr and (orAuraSource == "player" or orAuraSource == "cooldown")) then
            return nil, "Stop current cast needs a present Tracked aura or Target debuff in IF or the first OR."
        end
        return nil, "Stop current cast requires Aura is present in either condition."
    end
    if row.stopWhenInvalid == true and condition == "always" and not hasExtraAuras then
        return nil, "Stop if buffs change requires an aura condition instead of Always."
    end

    local entries, byKey = conditionEntries(row), {}
    for _, entry in ipairs(entries) do byKey[entry.key] = entry end
    local countKey = row.castCountCondition == nil and "primary" or row.castCountCondition
    local countEntry = byKey[countKey]
    if castCount > 0 then
        if not countEntry then return nil, "The cast-count condition no longer exists. Select an existing condition." end
        if countKey == "primary" and primary then return nil, "Cast counts require a tracked-aura condition." end
        if countEntry.group == "logicConditions" then return nil, "Cast counts require a tracked-aura condition." end
        if countEntry.kind == "NOT" then return nil, "Cast counts cannot attach to NOT exclusions." end
        if countEntry.condition == "cooldown" then return nil, "Cast counts cannot attach to cooldown conditions." end
        if countEntry.auraSource == "cooldown" then return nil, "Cast counts cannot attach to spell cooldown conditions." end
        if countEntry.condition == "manualCooldown" then return nil, "Cast counts cannot attach to manual cooldown conditions." end
        if countEntry.condition == "comboPoints" then return nil, "Cast counts cannot attach to combo-point conditions." end
        if countEntry.condition == "hawkCount" then return nil, "Cast counts cannot attach to Hawk conditions." end
        if countEntry.key == "customCondition" or countEntry.key == "targetCasting" or countEntry.key == "totemCondition" then
            return nil, "Choose a tracked aura for Cast Count."
        end
        if countEntry.condition == "resource" then return nil, "Cast counts cannot attach to resource conditions." end
        if countEntry.condition == "stacks" then return nil, "Cast counts cannot attach to aura stack conditions." end
        if countEntry.condition == "auraTime" then return nil, "Cast counts cannot attach to aura time conditions." end
        if countEntry.condition == "health" then return nil, "Cast counts cannot attach to "
            .. (countEntry.unit == "player" and "self" or "enemy") .. " health conditions." end
        if countEntry.condition == "always" then return nil, "Cast counts require a tracked-aura condition instead of Always or cooldown-only." end
        if countEntry.auraSource == "target" then return nil, "Cast counts cannot attach to target-debuff conditions." end
        if countEntry.auraSource == "player" then return nil, "Cast counts cannot attach to Player buff conditions." end
    end

    local result = {
        spell = attackCommand or name(row.spell, options.resolveName),
        aura = name(row.aura, options.resolveName),
        auraSource = auraSource,
        orAuraSource = orAuraSource,
        recipient = recipient,
        orAura = name(row.orAura, options.resolveName),
        oncePerProc = row.oncePerProc == true,
        useOr = useOr,
        hasAlternatives = useOr or #extras.orConditions > 0 or logicOr,
        condition = condition,
        castCount = castCount,
        petAttack = petAttack,
        startAttack = startAttack,
        customRule = customRule,
        customChangesTarget = customChangesTarget,
        rangedRepeat = rangedRepeat,
        skipIfNotCasted = row.skipIfNotCasted == true,
        skipIfImmune = row.skipIfImmune == true,
        skipOutOfRange = row.skipOutOfRange == true,
        advanceOnToggle = row.advanceOnToggle == true,
        skipModifier = skipModifier,
        priorityModifier = priorityModifier,
        alwaysPrimary = not primary and condition == "always" and row.skipCooldown ~= true and row.manualCooldown ~= true,
    }
    local selectedRank = row.rankID or tonumber(row.spell)
    local reactiveName = resolvedSpell and type(resolvedSpell.name) == "string" and resolvedSpell.name or result.spell
    if rangedRepeat and tonumber(result.spell) then
        result.spell = id == 5019 and "Shoot" or "Auto Shot"
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, id)
            if ok and info and info.name then result.spell = info.name end
        end
    end
    if selectedRank and not rangedRepeat and not attackCommand then
        local rankLabel
        if type(options.resolveRankLabel) == "function" then
            local ok, label = pcall(options.resolveRankLabel, row.spell, row.rankID)
            if ok and type(label) == "string" and trim(label) ~= "" then rankLabel = trim(label) end
        end
        result.spell = result.spell .. " (" .. (rankLabel or ("spell ID " .. selectedRank)) .. ")"
    end
    local function predicate(key, aura, source, state, excluded)
        local current
        if reactive and (source == "player" or source == "tracker") and SH.Riposte.MatchesCondition(byKey[key].aura,
            function() return reactiveName end, id) then
            current = {kind = "reactiveReady", name = result.spell, present = state == "present",
                excluded = excluded, number = byKey[key].number}
        else
            current = auraExpression(aura, source, state == "present", excluded, byKey[key].number)
        end
        if castCount > 0 and key == countKey then
            if state == "missing" then current = joined("or", current, {kind = "batch"}) end
            current = joined("and", current, {kind = "count", name = result.spell, count = castCount})
        end
        return current
    end
    local function logicPredicate(key, entry)
        local current = {kind = entry.type, operator = entry.operator, value = entry.value,
            resource = entry.resource, percent = entry.percent, unit = entry.unit, seconds = entry.seconds,
            source = entry.auraSource, name = name(entry.aura, options.resolveName), text = entry.value}
        local number = byKey[key].number
        if entry.logic == "NOT" then current = {kind = "excludedCondition", predicate = current} end
        current.number = number
        if ((entry.type == "health" or entry.type == "auraTime") and entry.unit == "target") or (entry.type == "stacks" and entry.auraSource == "target") then
            current = joined("and", {kind = "target"}, current)
        end
        return current
    end
    local expression
    if primary then
        expression = logicPredicate("primary", primary)
    elseif condition ~= "always" then
        expression = predicate("primary", result.aura, auraSource, condition)
    end
    if result.oncePerProc then
        expression = joined("and", expression, {kind = "unused", name = result.aura, spell = result.spell, index = index})
    end
    if useOr then
        local alternative = predicate("or", result.orAura, orAuraSource, orCondition)
        expression = joined("or", expression, alternative)
    end
    for extraIndex, entry in ipairs(extras.orConditions) do
        expression = joined("or", expression, predicate("orConditions:" .. extraIndex, name(entry.aura, options.resolveName),
            entry.auraSource, entry.condition))
    end
    for logicIndex, entry in ipairs(logic) do
        if entry.logic == "OR" then expression = joined("or", expression, logicPredicate("logicConditions:" .. logicIndex, entry)) end
    end
    for _, group in ipairs({"andConditions", "notConditions"}) do
        for extraIndex, entry in ipairs(extras[group]) do
            local current = predicate(group .. ":" .. extraIndex, name(entry.aura, options.resolveName),
                entry.auraSource, entry.condition, group == "notConditions")
            expression = joined("and", expression, current)
        end
    end
    for logicIndex, entry in ipairs(logic) do
        if entry.logic ~= "OR" then expression = joined("and", expression, logicPredicate("logicConditions:" .. logicIndex, entry)) end
    end
    if row.manualCooldown == true then
        expression = joined("and", expression, {kind = "manualCooldown", seconds = manualSeconds,
            number = byKey[condition == "always" and not primary and "primary" or "manualCooldown"].number})
    elseif row.skipCooldown == true then
        expression = joined("and", expression, {kind = "cooldown", name = result.spell,
            number = byKey[condition == "always" and not primary and "primary" or "cooldown"].number})
    end
    if combo then
        expression = joined("and", expression, {kind = "comboPoints", operator = combo.operator,
            value = combo.value, number = byKey.comboPoints.number})
    end
    if hawks then
        expression = joined("and", expression, {kind = "hawkCount", operator = hawks.operator,
            value = hawks.value, number = byKey.hawkCount.number})
    end
    for resourceIndex, resource in ipairs(resources) do
        expression = joined("and", expression, {kind = "resource", resource = resource.resource,
            operator = resource.operator, percent = resource.percent,
            number = byKey["resourceConditions:" .. resourceIndex].number})
    end
    for _, threshold in ipairs(health) do
        if threshold.unit ~= "player" then
            expression = joined("and", expression, {kind = "target"})
            break
        end
    end
    for healthIndex, threshold in ipairs(health) do
        expression = joined("and", expression, {kind = "health", operator = threshold.operator, unit = threshold.unit,
            percent = threshold.percent, number = byKey["healthConditions:" .. healthIndex].number})
    end
    for _, threshold in ipairs(stacks) do
        if threshold.auraSource == "target" then
            expression = joined("and", expression, {kind = "target"})
            break
        end
    end
    for stackIndex, threshold in ipairs(stacks) do
        expression = joined("and", expression, {kind = "stacks", name = name(threshold.aura, options.resolveName),
            source = threshold.auraSource, operator = threshold.operator, value = threshold.value,
            number = byKey["stackConditions:" .. stackIndex].number})
    end
    if row.customCondition ~= nil then
        expression = joined("and", expression, {kind = "customCondition", text = row.customCondition, number = byKey.customCondition.number})
    end
    if row.targetCasting == true then
        expression = joined("and", expression, {kind = "targetCasting", number = byKey.targetCasting.number})
    end
    if row.outOfCombatOnly == true then
        expression = joined("and", expression, {kind = "outOfCombatOnly"})
    end
    if row.inCombatOnly == true then
        expression = joined("and", expression, {kind = "inCombatOnly"})
    end
    if row.advanceOnToggle == true then
        expression = joined("and", expression, {kind = "advanceOnToggle", name = result.spell})
    end
    if totem then
        expression = joined("and", expression, {kind = "totemCondition", value = totem, number = byKey.totemCondition.number})
    end
    if unit == "focustarget" or (unit == "custom" and recipient ~= "@none") then
        expression = joined("and", expression, {kind = "recipient", name = recipient})
    end
    if petAttack then expression = joined("and", expression, {kind = "petAttack"}) end
    if startAttack then
        expression = joined("and", expression, {kind = "target"})
        expression = joined("and", expression, {kind = "startAttack"})
    end
    -- Keep the automatic gate outside the alternatives unless they already require it.
    if reactive and not requiresReactiveReady(expression) then
        expression = joined("and", expression, {kind = "reactiveReady", name = result.spell, present = true})
    end
    result.expression = expression
    return result
end

-- Keep each count beside its attached condition, without the batch-state details.
local function displayExpression(expression)
    if not expression or expression.kind == "batch" then return nil end
    if expression.op then
        return joined(expression.op, displayExpression(expression.first), displayExpression(expression.second))
    end
    return expression
end

local function emitPredicate(tokens, predicate)
    if predicate.number then add(tokens, "Condition " .. predicate.number .. ": ") end
    if predicate.kind == "excludedCondition" then
        keyword(tokens, "NOT"); add(tokens, " (")
        emitPredicate(tokens, predicate.predicate)
        add(tokens, ")")
    elseif predicate.kind == "aura" or predicate.kind == "excludedAura" then
        if predicate.kind == "excludedAura" then keyword(tokens, "NOT"); add(tokens, " (") end
        add(tokens, (predicate.source == "target" and "your " or "") .. predicate.name .. " is ")
        if not predicate.present then keyword(tokens, "NOT"); add(tokens, " ") end
        if predicate.source == "target" then add(tokens, "active on your current target")
        elseif predicate.source == "player" then add(tokens, "active on you")
        else add(tokens, "active") end
        if predicate.kind == "excludedAura" then add(tokens, ")") end
    elseif predicate.kind == "reactiveReady" then
        if predicate.excluded then keyword(tokens, "NOT"); add(tokens, " (") end
        add(tokens, predicate.name .. " is ")
        if not predicate.present then keyword(tokens, "NOT"); add(tokens, " ") end
        add(tokens, "ready to use")
        if predicate.excluded then add(tokens, ")") end
    elseif predicate.kind == "spellCooldown" then
        if predicate.excluded then keyword(tokens, "NOT"); add(tokens, " (") end
        add(tokens, predicate.name .. (predicate.onCooldown and " is on cooldown" or " is off cooldown"))
        if predicate.excluded then add(tokens, ")") end
    elseif predicate.kind == "target" then
        add(tokens, "your current target is alive and hostile")
    elseif predicate.kind == "customCondition" then
        add(tokens, "the macro condition " .. predicate.text .. " matches")
    elseif predicate.kind == "targetCasting" then
        add(tokens, "your current target is casting or channeling")
    elseif predicate.kind == "outOfCombatOnly" then
        add(tokens, "you are out of combat")
    elseif predicate.kind == "inCombatOnly" then
        add(tokens, "you are in combat")
    elseif predicate.kind == "totemCondition" then
        local slot = totemSlotConditions[predicate.value]
        if slot then
            add(tokens, slot.missing and ("your " .. slot.element .. " totem slot is empty")
                or ("any of your " .. slot.element .. " totems is active"))
        elseif predicate.value == "active" then
            add(tokens, "your Searing Totem ")
            keyword(tokens, "OR")
            add(tokens, " Magma Totem is active")
        else
            add(tokens, "your " .. fireTotemNames[predicate.value] .. " is active")
        end
    elseif predicate.kind == "recipient" then
        add(tokens, predicate.name .. " exists")
    elseif predicate.kind == "petAttack" then
        add(tokens, "you have a living pet that needs an attack order for your current enemy")
    elseif predicate.kind == "startAttack" then
        add(tokens, "Auto Attack is off")
    elseif predicate.kind == "advanceOnToggle" then
        add(tokens, predicate.name .. " is ")
        keyword(tokens, "NOT")
        add(tokens, " queued or toggled on")
    elseif predicate.kind == "cooldown" then
        add(tokens, predicate.name .. " is off cooldown")
    elseif predicate.kind == "manualCooldown" then
        local seconds = string.format("%.3f", predicate.seconds):gsub("0+$", ""):gsub("%.$", "")
        add(tokens, "manual cooldown (" .. seconds .. " seconds) has finished")
    elseif predicate.kind == "comboPoints" then
        local comparisons = {ge = "at least ", le = "at most ", eq = "exactly "}
        add(tokens, "your current target has ")
        if predicate.operator == "ne" then keyword(tokens, "NOT"); add(tokens, " exactly ")
        else add(tokens, comparisons[predicate.operator]) end
        add(tokens, predicate.value .. " combo points")
    elseif predicate.kind == "hawkCount" then
        local comparisons = {lt = "fewer than ", le = "at most ", eq = "exactly ", ge = "at least ", gt = "more than "}
        add(tokens, "you have ")
        if predicate.operator == "ne" then keyword(tokens, "NOT"); add(tokens, " exactly ")
        else add(tokens, comparisons[predicate.operator]) end
        add(tokens, predicate.value .. (predicate.value == 1 and " active hawk" or " active hawks"))
    elseif predicate.kind == "resource" then
        add(tokens, "your " .. resourceNames[predicate.resource] .. " is " .. resourceComparisons[predicate.operator]
            .. predicate.percent .. "% of maximum")
    elseif predicate.kind == "health" then
        add(tokens, (predicate.unit == "player" and "your health is " or "your current enemy target's health is ") .. resourceComparisons[predicate.operator]
            .. predicate.percent .. "% of maximum")
    elseif predicate.kind == "auraTime" then
        local comparisons = {lt = "less than ", le = "at most ", eq = "exactly ", ge = "at least ", gt = "more than "}
        add(tokens, predicate.name .. (predicate.unit == "player" and " on you has " or " on your current target has "))
        if predicate.operator == "ne" then keyword(tokens, "NOT"); add(tokens, " exactly ")
        else add(tokens, comparisons[predicate.operator]) end
        add(tokens, predicate.seconds .. (predicate.seconds == 1 and " second remaining" or " seconds remaining"))
        add(tokens, " (missing counts as 0)")
    elseif predicate.kind == "stacks" then
        add(tokens, predicate.source == "player" and "you have " or "your current target has ")
        if predicate.operator == "ne" then keyword(tokens, "NOT"); add(tokens, " exactly ")
        else add(tokens, stackComparisons[predicate.operator]) end
        add(tokens, predicate.value .. " " .. predicate.name .. (predicate.value == 1 and " stack" or " stacks"))
    elseif predicate.kind == "unused" then
        add(tokens, predicate.name .. " has ")
        keyword(tokens, "NOT")
        add(tokens, " been used by this rule")
    elseif predicate.kind == "count" then
        add(tokens, "fewer than " .. predicate.count .. " successful casts of " .. predicate.name .. " have counted for this batch")
    end
end

local function bullet(item, depth, condition, prefix, text)
    local entry = {tokens = {}, depth = depth or 0, condition = condition == true}
    item.bullets[#item.bullets + 1] = entry
    if prefix then keyword(entry.tokens, prefix); add(entry.tokens, " ") end
    if text then add(entry.tokens, text) end
    return entry.tokens
end

-- The diagram uses the same validated condition tree as the text explanation.
-- These helpers describe a draft; they never select or cast a spell.
function Explanation.DescribeRule(row, index, options)
    local result, problem = describeRow(row, index or 1, type(options) == "table" and options or {})
    if result then result.conditionEntries = conditionEntries(row) end
    return result, problem
end

function Explanation.PredicateText(predicate, includeNumber)
    if type(predicate) ~= "table" then return "Choose a condition." end
    if predicate.kind == "batch" then return "An unfinished cast batch is active" end
    local copy = {}
    for key, value in pairs(predicate) do copy[key] = value end
    if not includeNumber then copy.number = nil end
    local tokens, parts = {}, {}
    emitPredicate(tokens, copy)
    for _, token in ipairs(tokens) do parts[#parts + 1] = token.text or "" end
    return table.concat(parts)
end

local emitConditionBullets
local function emitAlternative(item, expression, prefix, depth)
    if expression.op == "and" then
        bullet(item, depth, true, prefix, "both conditions match:")
        emitConditionBullets(item, expression, "IF", depth + 1)
    else
        emitConditionBullets(item, expression, prefix, depth)
    end
end

local function alternatives(expression, result)
    if expression.op == "or" then
        alternatives(expression.first, result)
        alternatives(expression.second, result)
    else
        result[#result + 1] = expression
    end
end

emitConditionBullets = function(item, expression, prefix, depth)
    if not expression then return end
    if expression.op == "and" then
        emitConditionBullets(item, expression.first, prefix, depth)
        emitConditionBullets(item, expression.second, "AND", depth)
    elseif expression.op == "or" then
        local choices = {}
        alternatives(expression, choices)
        bullet(item, depth, true, prefix, #choices == 2 and "either condition matches:" or "any of these conditions match:")
        for index, choice in ipairs(choices) do emitAlternative(item, choice, index == 1 and "IF" or "OR", depth + 1) end
    else
        emitPredicate(bullet(item, depth, true, prefix), expression)
    end
end

local function emitPreviousReference(tokens, last)
    if last == 1 then
        add(tokens, "rule 1 does ")
    else
        add(tokens, "rules 1 through " .. last .. " do ")
    end
    keyword(tokens, "NOT")
    add(tokens, " match")
end

function Explanation.Build(rules, options)
    options = type(options) == "table" and options or {}
    local paragraphs = {}
    if type(rules) ~= "table" or #rules == 0 then
        paragraph(paragraphs, "note", "Add a spell rule to see its rotation explanation.")
        return paragraphs
    end

    local count = math.min(#rules, MAX_RULES)
    local dynamicPriority, enabledTotal = false, 0
    for index = 1, count do
        local row = rules[index]
        if type(row) == "table" and row.enabled ~= false then
            enabledTotal = enabledTotal + 1
            if modifier(row.priorityModifier) then dynamicPriority = true end
        end
    end
    if dynamicPriority then
        paragraph(paragraphs, "note", "These rules describe the current draft in normal priority order. Each press selects the first matching rule, checking rules whose priority modifier is held before the remaining rules. Rules in each group keep the displayed order. Skip modifiers take precedence. Condition numbers match the spell editor.")
    else
        paragraph(paragraphs, "note", "These rules describe the current draft, from highest to lowest priority. Each press selects the first matching rule. Condition numbers match the spell editor.")
    end
    if options.preventClipping ~= false then
        local tokens = paragraph(paragraphs, "note")
        keyword(tokens, "IF")
        add(tokens, " you are channeling, do ")
        keyword(tokens, "NOT")
        add(tokens, " start another spell. Protect channels takes priority over every rule below.")
    end

    local unreachable, hasOncePerProc = nil, false
    local enabledCount, previousDisabled = 0, false
    local previousAutoAttack, previousOtherRules = false, 0
    for index = 1, count do
        local draft = rules[index]
        local disabled = type(draft) == "table" and draft.enabled == false
        local row, problem
        if disabled then
            paragraph(paragraphs, "note", (name(draft.spell, options.resolveName) or "") .. " (disabled).", index)
            previousDisabled = true
        else
            row, problem = describeRow(draft, index, options)
            enabledCount = enabledCount + 1
        end
        if problem then
            paragraph(paragraphs, "warning", problem .. " This draft needs correction before it can be prepared.", index)
        elseif row and unreachable then
            paragraph(paragraphs, "warning", row.spell .. " cannot be reached: rule " .. unreachable .. " is Always with no additional conditions. Move that rule to the bottom, or add conditions to it.", index)
        elseif row then
            hasOncePerProc = hasOncePerProc or row.oncePerProc
            local tokens = paragraph(paragraphs, "rule", nil, index)
            local item = paragraphs[#paragraphs]
            item.bullets = {}
            if row.customRule then
                add(tokens, "Rule " .. index .. ": Run Custom Rule, then try the next matching rule on the same press.")
                bullet(item, 0, false, nil, row.customRule)
                bullet(item, 0, false, nil, "Use the visible Hit Button, Set cast key, or Controller. Custom Rules do not run through the action-bar macro.")
                if row.customChangesTarget then
                    bullet(item, 0, false, nil, "After a target command, target aura, stack and timer checks wait until the next press so they cannot use the old target's tracker.")
                end
            elseif row.petAttack then
                add(tokens, "Rule " .. index .. ": Send your pet to attack your target.")
            elseif row.startAttack then
                add(tokens, "Rule " .. index .. ": Start Auto Attack on your target, then try the next matching rule on the same press.")
            else
                add(tokens, "Rule " .. index .. ": " .. (row.rangedRepeat and "Start " or "Cast ") .. row.spell .. " on " .. row.recipient .. ".")
            end
            local hasPriorRule = dynamicPriority and enabledTotal > 1
                or enabledCount > 1 and (not previousAutoAttack or previousOtherRules > 0)
            if hasPriorRule then
                local prior = bullet(item, 0, true, "IF")
                if dynamicPriority then
                    add(prior, "no higher-priority spell or pet command matches in the current modifier order")
                elseif previousAutoAttack then
                    add(prior, "no higher-priority spell or pet command matches")
                elseif previousDisabled then
                    add(prior, "no higher-priority enabled rule matches")
                else
                    emitPreviousReference(prior, index - 1)
                end
            end
            if row.alwaysPrimary then bullet(item, 0, false, nil, "Condition 1: Always, when this rule is reached.") end
            emitConditionBullets(item, displayExpression(row.expression), hasPriorRule and "AND" or "IF", 0)
            local totemSlot = totemSlotConditions[draft.totemCondition]
            if totemSlot and totemSlot.missing then
                bullet(item, 0, false, nil, "An empty slot also matches before your first summon and after destruction, expiry, or dismissal. Any totem in this element's slot prevents a match.")
            end
            if row.skipIfNotCasted then
                bullet(item, 0, false, nil, "A facing or behind-target error skips this rule for the next press.")
            end
            if row.skipIfImmune then
                bullet(item, 0, false, nil, "Skip if immune (bleed): recognized bleed spells skip Mechanical targets immediately. An Immune response immediately after your successful cast skips that spell on that enemy for the rest of combat. If it is a recognized bleed, your other checked bleed rules skip that enemy too, such as Rip after an immune Rake. Learned immunity is forgotten when combat ends.")
            end
            if row.skipOutOfRange then
                bullet(item, 0, false, nil, "On each press, skip this rule if WoW reports that " .. row.spell .. " is out of range for " .. row.recipient .. ". If range is unknown, this rule stays eligible.")
            end
            if row.skipModifier then
                bullet(item, 0, false, nil, "Skip this rule while " .. modifierNames[row.skipModifier] .. " is held.")
            end
            if row.priorityModifier then
                bullet(item, 0, false, nil, "While " .. modifierNames[row.priorityModifier] .. " is held, try this rule before rules without a held priority modifier. All normal conditions and cooldown checks still apply.")
            end
            if row.skipModifier and row.priorityModifier then
                bullet(item, 0, false, nil, "If both modifiers are held, skip this rule.")
            end
            if row.rangedRepeat then bullet(item, 0, false, nil, "Repeated presses keep " .. row.spell .. " active while this rule matches.") end
            if row.hasAlternatives and row.oncePerProc then
                bullet(item, 0, false, nil, "Once per proc applies to the first condition only.")
                bullet(item, 0, false, nil, "An OR condition can still select this spell after that proc is used.")
            end
            if not dynamicPriority and not row.customRule and not row.expression and not row.skipIfNotCasted
                and not row.skipIfImmune and not row.skipOutOfRange and not row.skipModifier then unreachable = index end
            if row.startAttack or row.customRule then previousAutoAttack = true else previousOtherRules = previousOtherRules + 1 end
        end
    end

    if not unreachable then
        local tokens = paragraph(paragraphs, "note")
        keyword(tokens, "IF")
        add(tokens, " no rule matches, no spell is selected.")
    end
    if hasOncePerProc then
        paragraph(paragraphs, "note", "Once per proc records use when another press confirms the selected spell's channel. The tracked aura must hide before that rule can use a new proc.")
    end
    if #rules > MAX_RULES then
        paragraph(paragraphs, "warning", "Only the first 32 rules are shown. Remove extra rules before preparing this draft.")
    end
    return paragraphs
end

function Explanation.PlainText(paragraphs)
    local lines = {}
    for _, item in ipairs(type(paragraphs) == "table" and paragraphs or {}) do
        local text = {}
        for _, token in ipairs(item.tokens or {}) do text[#text + 1] = token.text or "" end
        local block = {(item.ruleIndex and item.kind ~= "rule" and ("Rule " .. item.ruleIndex .. ": ") or "") .. table.concat(text)}
        for _, entry in ipairs(item.bullets or {}) do
            text = {}
            for _, token in ipairs(entry.tokens or {}) do text[#text + 1] = token.text or "" end
            block[#block + 1] = string.rep("  ", entry.depth or 0) .. "- " .. table.concat(text)
        end
        lines[#lines + 1] = table.concat(block, "\n")
    end
    return table.concat(lines, "\n\n")
end

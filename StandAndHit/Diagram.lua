local _, SH = ...
local Diagram = {}
SH.Diagram = Diagram

local MAX_RULES = 32
local modifierNames = {ctrl = "Ctrl", alt = "Alt", shift = "Shift"}
local implicitSettings = {
    unused = "oncePerProc", advanceOnToggle = "advanceOnToggle",
    outOfCombatOnly = "outOfCombatOnly", inCombatOnly = "inCombatOnly",
}
local titles = {
    aura = "Aura", spellCooldown = "Spell cooldown", reactiveReady = "Spell usable",
    target = "Enemy target", customCondition = "Custom Conditions", targetCasting = "Target is casting",
    outOfCombatOnly = "Out of combat only", inCombatOnly = "In combat only", totemCondition = "Totem conditions",
    recipient = "Cast on target", petAttack = "Pet Attack", startAttack = "Auto Attack",
    advanceOnToggle = "Advance on toggle", cooldown = "Off cooldown", manualCooldown = "Manual cooldown",
    comboPoints = "Combo points", hawkCount = "Hawk conditions", resource = "Resources",
    health = "Health", auraTime = "Aura time remaining", stacks = "Aura stacks",
    unused = "Once per proc", count = "Cast Count", batch = "Cast Count batch",
}

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function newGraph(mode)
    return {mode = mode, nodes = {}, edges = {}, sections = {}, warnings = {}, draft = true}
end

local function node(graph, id, kind, title, text, ruleIndex, conditionKey)
    local item = {id = id, kind = kind, title = title, text = text or "", inputs = {},
        ruleIndex = ruleIndex, conditionKey = conditionKey, editable = ruleIndex ~= nil and conditionKey ~= nil}
    graph.nodes[#graph.nodes + 1] = item
    return item
end

local function edge(graph, from, to, label, kind)
    graph.edges[#graph.edges + 1] = {from = from, to = to, label = label or "", kind = kind or "logic"}
end

local function warning(graph, message, index)
    graph.warnings[#graph.warnings + 1] = {text = message, ruleIndex = index}
end

local function actionText(described)
    if described.customRule then return "Run once on this press, then try the next matching rule.\n" .. described.customRule
        .. "\nUse the visible Hit Button, Set cast key, or Controller. Action-bar macros cannot run this rule." end
    if described.startAttack then return "Start Auto Attack on your target. Continue to the next matching rule on this press." end
    if described.petAttack then return "Send your pet to attack your target." end
    return (described.rangedRepeat and "Start " or "Cast ") .. described.spell .. " on " .. described.recipient .. "."
end

local function appendRule(graph, raw, index, options, includeChannels)
    local prefix, first = "r" .. index .. ":", #graph.nodes + 1
    local section = {ruleIndex = index, nodeIDs = {}}
    local function finish()
        for i = first, #graph.nodes do section.nodeIDs[#section.nodeIDs + 1] = graph.nodes[i].id end
        graph.sections[#graph.sections + 1] = section
        return section
    end
    if type(raw) == "table" and raw.enabled == false then
        local item = node(graph, prefix .. "disabled", "disabled", "Rule " .. index .. " disabled",
            tostring(raw.spell or "") .. " is skipped. Its settings stay saved at this priority.", index, "action")
        section.rootID, section.disabled = item.id, true
        return finish()
    end
    local ok, described, problem = pcall(SH.Explanation.DescribeRule, raw, index, options)
    if not ok then described, problem = nil, "This rule has an incomplete setting. Open its controls to finish it." end
    if not described then
        problem = problem or "Choose a spell and conditions for this rule."
        local item = node(graph, prefix .. "warning", "warning", "Rule " .. index .. " needs editing", problem, index, "action")
        section.rootID, section.invalid = item.id, true
        warning(graph, problem, index)
        return finish()
    end
    section.described = described
    local byNumber = {}
    for _, entry in ipairs(described.conditionEntries or {}) do byNumber[entry.number] = entry end
    local expression
    expression = function(value, path, inheritedNumber)
        if value.op then
            local parts = {}
            local function flatten(part, branch)
                if part.op == value.op then
                    flatten(part.first, branch .. "a")
                    flatten(part.second, branch .. "b")
                else parts[#parts + 1] = {part, branch} end
            end
            flatten(value, path)
            local inputs = {}
            for _, part in ipairs(parts) do inputs[#inputs + 1] = expression(part[1], part[2]) end
            local gate = node(graph, prefix .. path, value.op, value.op:upper(),
                value.op == "or" and "At least one input must match." or "Every input must match.", index)
            for _, input in ipairs(inputs) do
                gate.inputs[#gate.inputs + 1] = input
                edge(graph, input, gate.id)
            end
            return gate.id
        end
        local number = value.number or inheritedNumber
        local descriptor = byNumber[number]
        local conditionKey = descriptor and descriptor.key or "settings"
        local excluded = value.kind == "excludedCondition" or value.kind == "excludedAura" or value.excluded == true
        if excluded then
            local inner = copy(value.kind == "excludedCondition" and value.predicate or value)
            inner.excluded, inner.number = nil, nil
            if inner.kind == "excludedAura" then inner.kind = "aura" end
            local input = expression(inner, path .. "input", number)
            local gate = node(graph, prefix .. path, "not", "NOT", "This condition must not match.", index, conditionKey)
            gate.conditionNumber, gate.inputs[1] = number, input
            edge(graph, input, gate.id)
            return gate.id
        end
        local title = titles[value.kind] or "Condition"
        if value.kind == "health" then title = value.unit == "player" and "Self health" or "Enemy health" end
        if number then title = "Condition " .. number .. ": " .. title end
        local item = node(graph, prefix .. path, "condition", title,
            SH.Explanation.PredicateText(value), index, conditionKey)
        item.conditionNumber, item.predicate = number, copy(value)
        item.predicate.number = number
        if value.kind == "recipient" then item.conditionKey = "action"
        elseif value.kind == "count" or value.kind == "batch" then item.conditionKey = "count"
        elseif not descriptor then
            local setting = implicitSettings[value.kind]
            if setting then item.settingField = setting
            else
                -- Target validity, automatic reactive-spell usability, pet
                -- readiness and melee-toggle state have no editable setting.
                item.editable, item.conditionKey = false, nil
            end
        end
        return item.id
    end
    local root = described.expression and expression(described.expression, "expr") or nil
    if described.alwaysPrimary then
        local item = node(graph, prefix .. "always", "condition", "Condition 1: Always",
            "Match when this rule is reached.", index, "primary")
        item.conditionNumber, item.predicate = 1, {kind = "always"}
        if root then
            local gate = node(graph, prefix .. "alwaysAnd", "and", "AND", "Every input must match.", index)
            gate.inputs = {item.id, root}; edge(graph, item.id, gate.id); edge(graph, root, gate.id); root = gate.id
        else root = item.id end
    end
    local requirements, notes = {}, {}
    local function requirement(field, title, text)
        local item = node(graph, prefix .. field, "condition", title, text, index, "settings")
        item.settingField, item.predicate = field, {kind = field}
        requirements[#requirements + 1] = item.id
    end
    if raw.pingDelay == true then
        requirement("pingDelay", "Ping Delay", "This spell is not casting, and its delay of " .. tostring(raw.pingDelayMS or 100) .. " ms has finished.")
    end
    if described.skipIfNotCasted then requirement("skipIfNotCasted", "Require being behind target", "No skip is pending from a facing or behind-target error on the previous press.") end
    if described.skipIfImmune then requirement("skipIfImmune", "Skip if immune (bleed)", "This enemy is not being skipped for bleed immunity. Checked bleeds skip Mechanical targets and share learned immunity for this enemy.") end
    if described.skipOutOfRange then requirement("skipOutOfRange", "Skip if out of range", "WoW has not reported this spell out of range. An unknown range does not block the rule.") end
    if described.skipModifier then requirement("skipModifier", "Skip modifier", modifierNames[described.skipModifier] .. " is not held.") end
    if includeChannels and options.preventClipping ~= false then
        requirement("protectChannels", "Protect channels", "You are not channeling. Channel protection takes priority over this rule.")
    end
    if #requirements > 0 then
        local gate = node(graph, prefix .. "requirements", "and", "AND", "These checks apply to every alternative.", index)
        if root then gate.inputs[#gate.inputs + 1] = root; edge(graph, root, gate.id) end
        for _, input in ipairs(requirements) do gate.inputs[#gate.inputs + 1] = input; edge(graph, input, gate.id) end
        root = gate.id
    end
    if not root then
        local item = node(graph, prefix .. "always", "condition", "Always", "Match when this rule is reached.", index, "primary")
        item.predicate = {kind = "always"}; root = item.id
    end
    if described.priorityModifier then notes[#notes + 1] = "Holding " .. modifierNames[described.priorityModifier] .. " moves this rule ahead of rules without a held priority modifier. Its conditions still apply; Skip wins if both modifiers are held." end
    if raw.stopCasting then notes[#notes + 1] = "Stop current cast is enabled for a fresh cast-key press when its tracked trigger matches." end
    if raw.stopWhenInvalid then notes[#notes + 1] = "Stop if buffs change is enabled for a fresh cast-key press when the required aura condition stops matching." end
    if described.rangedRepeat then notes[#notes + 1] = "Repeated presses keep this attack active while its rule matches." end
    local action = node(graph, prefix .. "action", "action", "Rule " .. index .. ": " .. described.spell,
        actionText(described), index, "action")
    action.inputs[1] = root
    action.notes, action.continues = notes, described.startAttack == true or described.customRule ~= nil
    if #notes > 0 then action.text = action.text .. "\n" .. table.concat(notes, "\n") end
    edge(graph, root, action.id, "Match")
    section.rootID, section.actionID, section.continues = root, action.id, action.continues
    section.unconditional = not described.expression and not described.skipIfNotCasted and not described.skipIfImmune
        and not described.skipOutOfRange and not described.skipModifier and raw.pingDelay ~= true
    return finish()
end

function Diagram.BuildRule(raw, index, options)
    index = type(index) == "number" and index >= 1 and index <= MAX_RULES and math.floor(index) == index and index or 1
    options = type(options) == "table" and options or {}
    local graph = newGraph("rule")
    graph.ruleIndex, graph.title = index, "Rule " .. index
    graph.note = "Current draft. Click a block to edit its setting. Prepare outside combat to apply changes."
    local section = appendRule(graph, raw, index, options, true)
    graph.rootID, graph.actionID, graph.described = section.rootID, section.actionID, section.described
    return graph
end

function Diagram.BuildRotation(rules, options)
    options = type(options) == "table" and options or {}
    rules = type(rules) == "table" and rules or {}
    local graph, count = newGraph("rotation"), math.min(#rules, MAX_RULES)
    graph.title = "Rotation diagram"
    local dynamic = false
    for index = 1, count do
        local raw = rules[index]
        if type(raw) == "table" and raw.enabled ~= false and modifierNames[raw.priorityModifier] then dynamic = true end
    end
    graph.dynamicPriority = dynamic
    graph.note = dynamic and "Current draft in normal order. Held priority modifiers move matching rules ahead of the remaining rules; each group keeps its listed order. Skip modifiers take precedence."
        or "Current draft, from highest to lowest priority. Each press uses the first matching rule."
    local start = node(graph, "start", "start", "Hit Button press", "Follow the rule priority shown below.")
    graph.rootID = start.id
    local selected = node(graph, "selected", "end", "Use selected action", "This press has selected its spell or pet command.")
    local noMatch = node(graph, "no-match", "end", "No spell selected", "No spell or pet command was selected on this press.")
    graph.endID, graph.noMatchID = selected.id, noMatch.id
    local firstID = start.id
    if options.preventClipping ~= false then
        local channels = node(graph, "channels", "global", "Protect channels", "Are you channeling?")
        local hold = node(graph, "channel-hold", "end", "Keep channeling", "Do not start another spell on this press.")
        edge(graph, start.id, channels.id, "", "flow")
        edge(graph, channels.id, hold.id, "Yes", "flow")
        firstID = channels.id
    end
    local previous, previousAction, unreachable
    for index = 1, count do
        local section = appendRule(graph, rules[index], index, options, false)
        local check = node(graph, "r" .. index .. ":check", "check", "Rule " .. index,
            section.disabled and "Disabled: continue." or section.invalid and "Finish this rule before Prepare." or "Do this rule's conditions match?", index, "action")
        section.checkID = check.id
        section.nodeIDs[#section.nodeIDs + 1] = check.id
        check.inputs[1] = section.rootID
        edge(graph, section.rootID, check.id, "Conditions")
        if section.actionID then
            for i = #graph.edges, 1, -1 do
                local item = graph.edges[i]
                if item.from == section.rootID and item.to == section.actionID then table.remove(graph.edges, i); break end
            end
            for _, item in ipairs(graph.nodes) do if item.id == section.actionID then item.inputs = {check.id}; break end end
            edge(graph, check.id, section.actionID, "Match", "flow")
            if not section.continues then edge(graph, section.actionID, selected.id, "Selected", "flow") end
        end
        if previous then
            edge(graph, previous.checkID, check.id, previous.disabled and "Disabled" or previous.invalid and "Needs editing" or "No match", "flow")
            if previousAction then edge(graph, previousAction, check.id, "Continue on this press", "flow") end
        else edge(graph, firstID, check.id, firstID == "channels" and "No" or "", "flow") end
        if unreachable and not section.disabled then warning(graph, "Rule " .. index .. " is below unconditional rule " .. unreachable .. ". Move that rule down or add conditions.", index) end
        if not dynamic and section.unconditional and not section.continues then unreachable = unreachable or index end
        previous, previousAction = section, section.continues and section.actionID or nil
    end
    if previous then
        edge(graph, previous.checkID, noMatch.id, previous.disabled and "Disabled" or previous.invalid and "Needs editing" or "No match", "flow")
        if previousAction then edge(graph, previousAction, noMatch.id, "Continue on this press", "flow") end
    else edge(graph, firstID, noMatch.id, firstID == "channels" and "No" or "", "flow") end
    if #rules > MAX_RULES then warning(graph, "Only the first 32 rules are shown. Remove extra rules before Prepare.") end
    return graph
end

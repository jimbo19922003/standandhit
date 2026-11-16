local addonName, SH = ...

local MAX_RULES = 32
local ROW_HEIGHT = 80
local MAX_EXTRA_CONDITIONS = 8
local PANEL_WIDTH, PANEL_HEIGHT = 1000, 836
local PROFILE_ROW_HEIGHT = 36
local conditions = { "present", "missing", "always" }
local conditionLabels = { present = "Aura is present", missing = "Aura is missing", always = "Always" }
local conditionLabelsBySource = {
    tracker = conditionLabels,
    target = { present = "Debuff is present", missing = "Debuff is missing", always = "Always" },
    player = { present = "Buff is present", missing = "Buff is missing", always = "Always" },
    cooldown = { present = "On cooldown", missing = "Off cooldown" },
}
local auraSources = { "tracker", "target", "player" }
local extraConditionSources = { "tracker", "target", "player", "cooldown" }
local auraSourceLabels = { tracker = "Tracked aura", target = "Target debuff", player = "Player buff", cooldown = "Spell cooldown" }
local auraPrefixes = { target = "Target: ", player = "You: " }
local auraNameLabels = { target = "Debuff name or ID", player = "Buff name or ID (e.g. Strength of Earth)" }
local conditionInputLabels = { tracker = "Aura name or ID", target = "Debuff name or ID", player = "Buff name or ID", cooldown = "Spell name or ID" }
local auraSourceHelp = "Tracked aura follows a Buff Bar or Buff Icon. Target debuff checks your own debuff on your current hostile target. Player buff checks the buff on your character, whoever applied it."
local spellCooldownHelp = "Enter another spell's name or ID and choose On cooldown or Off cooldown. Add that spell to Blizzard's native Essential Cooldowns or Utility Cooldowns, close its settings, then Prepare. Example: Eviscerate with AND > Spell cooldown > Kidney Shot > On cooldown casts Eviscerate only while Kidney Shot is on cooldown and the other conditions match. Spell cooldown conditions cannot count casts or trigger Once per proc or Stop current cast."
local extraConditionSourceHelp = auraSourceHelp .. " Spell cooldown checks another spell in Blizzard's native Essential Cooldowns or Utility Cooldowns."
local ruleModifiers = { "none", "ctrl", "alt", "shift" }
local ruleModifierLabels = { none = "None", ctrl = "Ctrl", alt = "Alt", shift = "Shift" }
local modifierHelp = "Hold the chosen key while pressing Hit Button. Skip if ignores this rule. Prioritize if checks it first, keeping its conditions and cooldown. Prioritized rules keep their order; Skip wins if both apply. Click Prepare after editing. With Set cast key, the prepared modifiers also work with that key, including combinations. For a macro-only keybind, bind the modified key to the same action-bar slot or use Set cast key."
local auraInputHelp = {
    tracker = "Enter the aura name or spell ID from your tracked Buff Bars or Buff Icons. For grouped entries, enter the individual name, such as Aspect of the Monkey, Cat Form, or Seal of Righteousness. Paladin auras and blessings use their individual names too. On a Shaman, enter a totem buff name like Strength of Earth to check it on yourself.",
    target = "Enter the name or spell ID of your own tracked debuff on your current hostile target.",
    player = "Enter the buff name or spell ID from your character's buffs. For Strength of Earth Totem, enter Strength of Earth. For Windfury Totem, enter Windfury Totem. Buff is missing can replace a distant totem once you lose its buff. Remove any slot-empty condition from that rule. A buff from another shaman counts too.",
    cooldown = spellCooldownHelp,
}
local auraConditions = { "present", "missing" }
local units = { "target", "player", "party1", "party2", "party3", "party4", "focus", "focustarget", "mouseover" }
local unitLabels = { target = "Target", player = "Self", focus = "Focus", focustarget = "Target of focus",
    mouseover = "Mouseover", custom = "Custom Target",
    party1 = "Party 1", party2 = "Party 2", party3 = "Party 3", party4 = "Party 4" }
local comboOperators = { "ge", "le", "eq", "ne" }
local comboOperatorLabels = { ge = "At least (>=)", le = "At most (<=)", eq = "Equal to (=)", ne = "Not equal to (!=)" }
local comboSymbols = { ge = ">=", le = "<=", eq = "=", ne = "!=" }
local hawkOperators = { "lt", "le", "eq", "ne", "ge", "gt" }
local hawkOperatorLabels = { lt = "Fewer than (<)", le = "At most (<=)", eq = "Equal to (=)",
    ne = "Not equal to (!=)", ge = "At least (>=)", gt = "More than (>)" }
local hawkSymbols = { lt = "<", le = "<=", eq = "=", ne = "!=", ge = ">=", gt = ">" }
local hawkHelp = "Checks how many of your Summon Hawk hawks are active. Applies to every IF / OR alternative. No cooldown-tracker entry is needed for this condition."
local resourceTypes = { "mana", "rage", "energy" }
local resourceLabels = { mana = "Mana", rage = "Rage", energy = "Energy" }
local resourceOperators = { "lt", "ge" }
local resourceOperatorLabels = { lt = "Below (<)", ge = "At least (>=)" }
local resourceSymbols = { lt = "<", ge = ">=" }
local stackSources = { "target", "player" }
local auraTimeHelp = "Track in Tracked Bars. Reads displayed seconds from 0 to 60; missing = 0. Unreadable or unsupported timer text does not match."
local auraTimeOperatorLabels = {lt = "Below (<)", le = "At most (<=)", eq = "Equal to (=)", ne = "Not equal to (!=)", ge = "At least (>=)", gt = "Above (>)"}
local stackHelp = "Track this aura in Blizzard's Buffs/Bars. Missing counts as 0; unreadable skips this rule."
local totemElements = {"fire", "earth", "water", "air"}
local totemElementLabels = {fire = "Fire", earth = "Earth", water = "Water", air = "Air"}
local totemModes = {
    fire = {"active", "searing", "magma", "fire-active", "missing"},
    earth = {"earth-active", "earth-missing"},
    water = {"water-active", "water-missing"},
    air = {"air-active", "air-missing"},
}
local totemLabels = {
    active = "Searing or Magma active", searing = "Searing Totem active",
    magma = "Magma Totem active", missing = "Fire slot empty",
    ["fire-active"] = "Any Fire totem active",
    ["earth-active"] = "Any Earth totem active", ["earth-missing"] = "Earth slot empty",
    ["water-active"] = "Any Water totem active", ["water-missing"] = "Water slot empty",
    ["air-active"] = "Any Air totem active", ["air-missing"] = "Air slot empty",
}
local totemCooldownHelp = "Choose Fire, Earth, Water, or Air. Matches while your totem in that element's slot is active. Fire also offers Searing and Magma choices. For Fire Nova, also choose Off cooldown to check Fire Nova's own cooldown."
local totemDestroyedHelp = "Choose Fire, Earth, Water, or Air. Matches an empty slot, including before your first summon and after your totem is destroyed, expires, or is dismissed. Another totem in the same element's slot prevents a match. Distance does not empty the slot. To replace a buff totem when you lose its benefit, remove this condition and use Player buff > Buff is missing."
local accent = { 0.36, 0.78, 0.88 }
local extraGroups = { "andConditions", "orConditions", "notConditions" }
local extraLabels = { andConditions = "AND", orConditions = "OR", notConditions = "NOT" }
local RefreshRows, RefreshInlineConditions, RefreshResourceConditions, RefreshHealthConditions, RefreshStackConditions, RefreshLogicConditions, DraftChanged
local RefreshRuleDiagram, CreateRuleDiagramControls, CheckBox

local function ExtraCount(rule)
    return #(rule.andConditions or {}) + #(rule.orConditions or {}) + #(rule.notConditions or {})
end

local function HasAuraConditions(rule)
    if rule.condition ~= "always" then return true end
    for _, group in ipairs({"andConditions", "notConditions"}) do
        for _, entry in ipairs(rule[group] or {}) do
            if entry.auraSource ~= "cooldown" then return true end
        end
    end
    return false
end

local function CopyConditions(entries)
    local copy = {}
    for i, entry in ipairs(entries or {}) do
        copy[i] = { aura = entry.aura, auraSource = entry.auraSource, condition = entry.condition }
    end
    return copy
end

local function ActiveRotation(ui)
    if ui and ui.rotation then return ui.rotation end
    return SH.GetActiveRotation and SH:GetActiveRotation() or SH
end

local function IsEnabled(rotation)
    return not rotation.IsEnabled or rotation:IsEnabled()
end

local function RotationLabel(rotation)
    return rotation.label or ((rotation.index or 1) > 1 and ("Hit Button " .. rotation.index) or "Hit Button")
end

local function Trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function TotemConditionElement(value)
    return type(value) == "string" and value:match("^(%a+)%-") or "fire"
end

local function TotemConditionMissing(value)
    return value == "missing" or (type(value) == "string" and value:match("%-missing$") ~= nil)
end

local function TotemConditionMode(element, missing)
    if missing then return element == "fire" and "missing" or element .. "-missing" end
    return element .. "-active"
end

local function DefaultTotemElement(rule)
    if rule.totemCondition then return TotemConditionElement(rule.totemCondition) end
    if not SH.TotemElement then return "fire" end
    local id = tonumber(rule.rankID) or tonumber(rule.spell)
    if not id and SH.ResolveSpell then
        local ok, spell = pcall(SH.ResolveSpell, Trim(rule.spell))
        if ok and spell then id = spell.id end
    end
    return SH.TotemElement(id) or "fire"
end

local function DraftCount(value)
    local text = Trim(value)
    if text == "" then return nil end
    return tonumber(text) or text
end

local function DraftPingDelayMS(value)
    if value == nil then return 100 end
    local text = Trim(value)
    return tonumber(text) or text
end

local function DraftManualCooldownSeconds(value)
    if value == nil then return 0 end
    return tonumber(Trim(value)) or value
end

local function CooldownLabel(rule)
    return rule.manualCooldown == true and "Manual cooldown ready" or "Off cooldown"
end

local rangedNames = { [5019] = "Shoot", [75] = "Auto Shot" }

local function AttackCommand(spell)
    if SH.Model.IsPetAttack(spell) then return "Pet Attack" end
    if SH.Model.IsAutoAttack(spell) then return "Auto Attack" end
end

local function HasEnabledCustomRule(ui, exceptIndex)
    for index, rule in ipairs(ui.draft or {}) do
        if index ~= exceptIndex and rule.customRule ~= nil and rule.enabled ~= false then return true end
    end
    return false
end

local function DisplaySpell(rule)
    if rule.customRule ~= nil then return "Custom Rule" end
    if SH.Model.IsAutoAttack(rule.spell) then return "Auto Attack" end
    local id = tonumber(rule.spell)
    if not rangedNames[id] then return Trim(rule.spell) end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and info and info.name then return info.name end
    end
    return rangedNames[id]
end

local function CopyRules(rules)
    local copy = {}
    for i, rule in ipairs(rules or {}) do
        copy[i] = {
            spell = Trim(rule.spell), aura = Trim(rule.aura),
            rankID = tonumber(rule.rankID),
            condition = rule.condition or "present", unit = rule.unit or "target",
            enabled = rule.enabled, customTarget = rule.customTarget,
            customRule = rule.customRule,
            customCondition = rule.customCondition, targetCasting = rule.targetCasting,
            totemCondition = rule.totemCondition,
            auraSource = rule.auraSource == nil and "tracker" or rule.auraSource,
            useOr = rule.useOr == true, orAura = Trim(rule.orAura),
            orCondition = rule.orCondition or "present",
            orAuraSource = rule.orAuraSource == nil and "tracker" or rule.orAuraSource,
            skipCooldown = rule.skipCooldown == true,
            oncePerProc = rule.oncePerProc == true,
            castCount = DraftCount(rule.castCount),
            castCountCondition = rule.castCountCondition,
            stopCasting = rule.stopCasting == true,
            stopWhenInvalid = rule.stopWhenInvalid == true,
            pingDelay = rule.pingDelay == true,
            pingDelayMS = DraftPingDelayMS(rule.pingDelayMS),
            manualCooldown = rule.manualCooldown == true,
            manualCooldownSeconds = DraftManualCooldownSeconds(rule.manualCooldownSeconds),
            skipIfNotCasted = rule.skipIfNotCasted == true,
            skipIfImmune = rule.skipIfImmune == true,
            skipOutOfRange = rule.skipOutOfRange == true,
            outOfCombatOnly = rule.outOfCombatOnly == true,
            inCombatOnly = rule.inCombatOnly == true,
            advanceOnToggle = rule.advanceOnToggle == true,
            skipModifier = rule.skipModifier,
            priorityModifier = rule.priorityModifier,
            andConditions = CopyConditions(rule.andConditions),
            orConditions = CopyConditions(rule.orConditions),
            notConditions = CopyConditions(rule.notConditions),
            comboPoints = SH.Model.Copy(rule.comboPoints),
            hawkCount = SH.Model.Copy(rule.hawkCount),
            resourceConditions = SH.Model.Copy(rule.resourceConditions),
            healthConditions = SH.Model.Copy(rule.healthConditions),
            stackConditions = SH.Model.Copy(rule.stackConditions),
            logicConditions = SH.Model.Copy(rule.logicConditions),
            primaryCondition = SH.Model.Copy(rule.primaryCondition),
        }
    end
    return copy
end

local function Label(parent, text, font, color)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    label:SetText(text)
    label:SetJustifyH("LEFT")
    if color then label:SetTextColor(unpack(color)) end
    return label
end

local function Tooltip(widget, title, body)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
        GameTooltip:AddLine(type(body) == "function" and body() or body, 0.82, 0.85, 0.9, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Button(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 100, height or 25)
    button:SetText(text)
    return button
end

local function EditBox(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 25)
    box:SetAutoFocus(false)
    box:SetMaxLetters(120)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function Cycle(values, current)
    for i, value in ipairs(values) do
        if value == current then return values[i % #values + 1] end
    end
    return values[1]
end

local function RankChoices(rule)
    if SH.SpellRanks and SH.SpellRanks.GetChoices then
        local ok, choices, baseName = pcall(SH.SpellRanks.GetChoices, rule.spell)
        if ok and type(choices) == "table" and #choices > 0 then return choices, baseName end
    end
    return { { label = "Highest learned" } }, nil
end

local function RefreshRank(row, rule)
    row.customRuleAction = rule.customRule ~= nil
    row.attackCommand = row.customRuleAction and "Custom Rule" or AttackCommand(rule.spell)
    row.petAttack = row.attackCommand == "Pet Attack"
    local id = tonumber(rule.rankID) or tonumber(rule.spell)
    if not id and not row.attackCommand then
        local ok, spell = pcall(SH.ResolveSpell, Trim(rule.spell))
        if ok and spell then id = spell.id end
    end
    row.wandShoot, row.autoShot = id == 5019, id == 75
    row.spellLabel:SetText(row.customRuleAction and "Macro commands (one per line)" or row.petAttack and "Pet command" or row.attackCommand and "Melee action" or "Spell name or ID")
    row.spell:SetShown(not row.customRuleAction)
    if row.customRuleScroll then row.customRuleScroll:SetShown(row.customRuleAction) end
    if row.castOnLabel then row.castOnLabel:SetShown(not row.customRuleAction) end
    row.unit:SetShown(not row.customRuleAction)
    row.unit:SetEnabled(not row.attackCommand)
    row.rankLabel:SetShown(not row.attackCommand)
    row.rank:SetShown(not row.attackCommand)
    if row.attackCommand or row.wandShoot or row.autoShot then
        row.rank:SetText("Unranked")
        row.rank:SetEnabled(false)
        return
    end
    local choices = RankChoices(rule)
    local selected = tonumber(rule.rankID) or tonumber(rule.spell)
    local text = selected and ("Selected ID: " .. selected) or "Highest learned"
    for _, choice in ipairs(choices) do
        if choice.id == selected then text = choice.label; break end
    end
    row.rank:SetText(text)
    row.rank:SetEnabled(#choices > 1 or selected ~= nil)
end

local function Skin(frame, fill, edge)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(fill))
    frame:SetBackdropBorderColor(unpack(edge))
end

local function ChoiceMenu(ui, owner, choices, selected, changed)
    if ui.choiceMenu and ui.choiceMenu:IsShown() and ui.choiceMenu.owner == owner then
        ui.choiceMenu:Hide()
        return
    end
    local menu = ui.choiceMenu
    if menu then menu:Hide(); menu:SetParent(ui)
    else
        -- Keep menus outside the editor's scroll child so long lists are not clipped.
        menu = CreateFrame("Frame", "StandAndHitChoiceMenu", ui, "BackdropTemplate")
        menu.buttons = {}
        if UISpecialFrames then table.insert(UISpecialFrames, "StandAndHitChoiceMenu") end
    end
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(owner:GetFrameLevel() + 30)
    menu:SetClampedToScreen(true)
    menu:ClearAllPoints()
    menu:SetPoint(owner.menuAlignRight and "TOPRIGHT" or "TOPLEFT", owner,
        owner.menuAlignRight and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -2)
    menu:SetSize(math.max(owner:GetWidth(), owner.menuWidth or 202), #choices * 28 + 8)
    Skin(menu, { 0.035, 0.05, 0.07, 1 }, { 0.36, 0.78, 0.88, 1 })
    menu.owner, owner.menuChoices = owner, {}
    ui.choiceMenu = menu
    if not owner.choiceHideHook then
        owner.choiceHideHook = true
        owner:HookScript("OnHide", function(self)
            if ui.choiceMenu and ui.choiceMenu.owner == self then ui.choiceMenu:Hide() end
        end)
    end
    for i, choice in ipairs(choices) do
        local option = menu.buttons[i] or Button(menu, "", menu:GetWidth() - 8, 26)
        menu.buttons[i] = option
        option:SetWidth(menu:GetWidth() - 8)
        option:SetText((choice.value == selected and "* " or "") .. choice.label)
        option:ClearAllPoints()
        option:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 28)
        option:SetEnabled(choice.enabled ~= false)
        option.choiceReason = choice.reason
        option.choiceTitle = choice.tooltipTitle or "Count attachment"
        option:SetScript("OnEnter", function(self)
            if not self.choiceReason then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.choiceTitle, 1, 1, 1)
            GameTooltip:AddLine(self.choiceReason, 0.82, 0.85, 0.9, true)
            GameTooltip:Show()
        end)
        option:SetScript("OnLeave", function() GameTooltip:Hide() end)
        option:SetScript("OnClick", function()
            if choice.enabled == false then return end
            menu:Hide()
            changed(choice.value)
        end)
        owner.menuChoices[choice.value] = option
        option:Show()
    end
    for i = #choices + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:Show()
end

local function Choices(values, labels)
    local choices = {}
    for _, value in ipairs(values) do choices[#choices + 1] = { value = value, label = labels[value] } end
    return choices
end

local function MarkDropdown(button)
    local arrow = Label(button, "v", "GameFontNormalSmall", accent)
    arrow:SetPoint("RIGHT", -7, 0)
    button.dropdownArrow = arrow
end

local function SaveDraft(ui)
    ActiveRotation(ui):SaveDraft(CopyRules(ui.draft))
end

local function CanStopCast(rule)
    local primary, alternative = SH.Model.StopBranches(rule)
    return primary or alternative
end

local function ConditionEntry(rule, key)
    for _, entry in ipairs(SH.Model.ConditionEntries(rule)) do
        if entry.key == key then return entry end
    end
end

local function ConditionTitle(entry)
    if not entry then return "Missing condition" end
    return "Condition " .. entry.number .. " - " .. entry.kind
end

local function HealthLabel(unit)
    return unit == "player" and "Self health" or "Enemy health"
end

local function CountConditionLabel(entry, compact)
    if not entry then return "Missing condition - choose another" end
    local aura = Trim(entry.aura)
    local prefix = auraPrefixes[entry.auraSource] or ""
    local nameLimit = 24 - #prefix - (entry.kind == "NOT" and 4 or 0)
    if compact and #aura > nameLimit then
        local ending = nameLimit - 3
        while ending > 0 and aura:byte(ending + 1) >= 128 and aura:byte(ending + 1) <= 191 do ending = ending - 1 end
        aura = aura:sub(1, ending) .. "..."
    end
    if entry.auraSource == "cooldown" then
        if aura == "" then aura = "Choose spell" end
        aura = aura .. (entry.condition == "missing" and " off cooldown" or " on cooldown")
        if entry.kind == "NOT" then aura = "NOT " .. aura end
    elseif entry.condition == "always" then aura = "Always / off cooldown"
    elseif entry.condition == "cooldown" then aura = "Off cooldown"
    elseif entry.condition == "manualCooldown" then aura = "Manual cooldown ready"
    elseif entry.condition == "comboPoints" then aura = "Combo points " .. (comboSymbols[entry.operator] or "?") .. " " .. tostring(entry.value or "?")
    elseif entry.condition == "hawkCount" then aura = "Hawks " .. (hawkSymbols[entry.operator] or "?") .. " " .. tostring(entry.value or "?")
    elseif entry.condition == "resource" then aura = (resourceLabels[entry.resource] or "Resource") .. " "
        .. (resourceSymbols[entry.operator] or "?") .. " " .. tostring(entry.percent or "?") .. "%"
    elseif entry.condition == "health" then aura = HealthLabel(entry.unit) .. " "
        .. (resourceSymbols[entry.operator] or "?") .. " " .. tostring(entry.percent or "?") .. "%"
    elseif entry.condition == "auraTime" then aura = (auraPrefixes[entry.unit] or "") .. (aura ~= "" and aura or "Choose aura") .. " time "
        .. (hawkSymbols[entry.operator] or "?") .. " " .. tostring(entry.seconds or "?") .. "s"
    elseif entry.condition == "stacks" then aura = prefix .. (aura ~= "" and aura or "Choose aura") .. " stacks "
        .. (hawkSymbols[entry.operator] or "?") .. " " .. tostring(entry.value or "?")
    elseif entry.key == "customCondition" or entry.condition == "customCondition" then aura = "Custom Conditions"
    elseif entry.key == "targetCasting" or entry.condition == "targetCasting" then aura = "Target is casting"
    elseif entry.key == "totemCondition" or entry.condition == "totemCondition" then aura = totemLabels[entry.value] or "Totem condition"
    else
        if aura == "" then aura = "Choose aura" end
        aura = aura .. (entry.condition == "missing" and " missing" or " present")
        aura = prefix .. aura
        if entry.kind == "NOT" then aura = "NOT " .. aura end
    end
    return "Condition " .. entry.number .. " - " .. aura
end

local function CountUnavailableReason(entry)
    if entry.group == "logicConditions" then return "this condition cannot count casts" end
    if entry.kind == "NOT" then return "NOT cannot count" end
    if entry.condition == "stacks" then return "aura stacks cannot count casts" end
    if entry.condition == "auraTime" then return "aura time cannot count casts" end
    if entry.auraSource == "cooldown" then return "spell cooldown cannot count" end
    if entry.auraSource == "target" then return "target debuff cannot count" end
    if entry.auraSource == "player" then return "player buff cannot count" end
    if entry.condition == "cooldown" or entry.condition == "manualCooldown" then return "cooldown cannot count" end
    if entry.condition == "comboPoints" then return "combo points cannot count" end
    if entry.condition == "hawkCount" then return "hawk conditions cannot count casts" end
    if entry.condition == "resource" then return "resources cannot count" end
    if entry.condition == "health" then return HealthLabel(entry.unit):lower() .. " cannot count casts" end
    if entry.key == "customCondition" or entry.key == "targetCasting" or entry.key == "totemCondition" then return "cannot count casts" end
    return "needs a tracked aura"
end

local function HasDraftCount(rule)
    local count = DraftCount(rule.castCount)
    return count ~= nil and count ~= 0
end

local function ClearCountAttachment(rule, key)
    local attachedKey = rule.castCountCondition == nil and "primary" or rule.castCountCondition
    if attachedKey ~= key then return false end
    local hadCount = HasDraftCount(rule)
    rule.castCount, rule.castCountCondition = nil, nil
    return hadCount
end

local function RemoveCountCondition(rule, group, index)
    local key = rule.castCountCondition == nil and "primary" or rule.castCountCondition
    if ClearCountAttachment(rule, group .. ":" .. index) then return true end
    local attachedIndex = type(key) == "string" and tonumber(key:match("^" .. group .. ":(%d+)$"))
    if attachedIndex and attachedIndex > index then
        rule.castCountCondition = group .. ":" .. (attachedIndex - 1)
    end
    return false
end

local function RefreshCountControls(row, rule)
    local entry = SH.Model.GetCountCondition(rule)
    local hasCount = HasDraftCount(rule)
    local canCount = not rule.oncePerProc and ((entry and entry.countEligible) or hasCount)
    row.castCount:SetEnabled(canCount and true or false)
    row.castCount:SetAlpha(canCount and 1 or 0.35)
    row.castCountLabel:SetAlpha(canCount and 1 or 0.35)
    row.castCountHint:SetAlpha(canCount and 1 or 0.35)
    row.castCountHint:SetText("0 = unlimited")
    row.castCountCondition:SetEnabled(not rule.oncePerProc)
    row.castCountCondition:SetText(CountConditionLabel(entry, true))
    row.countAttachmentLabel:SetAlpha(rule.oncePerProc and 0.35 or 1)
    local valid = entry and entry.countEligible and not rule.oncePerProc
    if hasCount and not valid then
        local reason = rule.oncePerProc and "Cast counts cannot be combined with Once per proc."
            or (entry and entry.countReason or "The attached condition no longer exists.")
        row.countReminder:SetText(CountConditionLabel(entry, true) .. ": " .. reason .. " Choose another condition or clear the count.")
        row.countReminder:SetTextColor(1, 0.57, 0.57)
    else
        row.countReminder:SetText((entry and ("Condition " .. entry.number .. ": ") or "")
            .. "completed casts count toward this condition, including proc casts during a batch.\nKeep this spell's chosen rank in a fixed, visible Blizzard action-bar slot.")
        row.countReminder:SetTextColor(unpack(accent))
    end
end

local function ShowResult(ui, ok, message)
    ui.message = message or (ok and "Done." or "This action could not be completed.")
    ui.messageOK = ok
    SH:RefreshUIStatus()
end

local function ClearRowFocus(row)
    row.spell:ClearFocus()
    if row.customRuleText then row.customRuleText:ClearFocus() end
    row.customTarget:ClearFocus()
    row.customCondition:ClearFocus()
    row.aura:ClearFocus()
    row.orAura:ClearFocus()
    row.castCount:ClearFocus()
    row.pingDelayMS:ClearFocus()
    row.manualCooldownSeconds:ClearFocus()
    for _, entry in ipairs(row.conditionRows or {}) do entry.aura:ClearFocus() end
    for _, entry in ipairs(row.resourceRows or {}) do entry.percent:ClearFocus() end
    for _, entry in ipairs(row.healthRows or {}) do entry.percent:ClearFocus() end
    for _, entry in ipairs(row.stackRows or {}) do entry.aura:ClearFocus(); entry.value:ClearFocus() end
    for _, entry in ipairs(row.logicRows or {}) do
        for _, field in ipairs({entry.aura, entry.percent, entry.value, entry.custom}) do field:ClearFocus() end
    end
    for _, entry in ipairs(row.primaryTypedRows or {}) do
        for _, field in ipairs({entry.aura, entry.percent, entry.value, entry.custom}) do field:ClearFocus() end
    end
end

local function SetEditorOffset(ui, offset)
    local scroll = ui.editorScroll
    local maximum = math.max(0, ui.editorBody:GetHeight() - scroll:GetHeight())
    offset = math.max(0, math.min(offset or 0, maximum))
    if ui.choiceMenu then ui.choiceMenu:Hide() end
    scroll:SetVerticalScroll(offset)
    if scroll.ScrollBar then scroll.ScrollBar:SetValue(offset) end
end

local function RefreshEditorScroll(ui)
    local row, rule = ui.rows[ui.selectedIndex], ui.draft[ui.selectedIndex]
    local offset = ui.editorScroll:GetVerticalScroll() or 0
    if ui.editorRule ~= rule then offset = 0 end
    ui.editorRule = rule
    ui.editorBody:SetHeight(rule and row and row:GetHeight() or ui.editorScroll:GetHeight())
    ui.editorScroll:UpdateScrollChildRect()
    local maximum = math.max(0, ui.editorBody:GetHeight() - ui.editorScroll:GetHeight())
    if ui.editorScroll.ScrollBar then
        ui.editorScroll.ScrollBar:SetMinMaxValues(0, maximum)
        ui.editorScroll.ScrollBar:SetShown(maximum > 0)
    end
    -- Ordinary text edits keep the menu and scroll position stable.
    local clamped = math.max(0, math.min(offset, maximum))
    if clamped ~= (ui.editorScroll:GetVerticalScroll() or 0) then SetEditorOffset(ui, clamped) end
end

local function RevealEditorRegion(ui, top, height, focus)
    -- Diagram additions reveal their new block after the shared add handler
    -- completes. Do not scroll or focus the hidden fields view in between.
    if ui.ruleDiagramMode and ui.ruleDiagramPanel and ui.ruleDiagramPanel:IsShown() then return end
    local scroll = ui.editorScroll
    local offset, viewport = scroll:GetVerticalScroll() or 0, scroll:GetHeight()
    if top < offset then offset = top end
    if top + height > offset + viewport then offset = top + height - viewport end
    SetEditorOffset(ui, offset)
    if focus then
        ClearRowFocus(ui.rows[ui.selectedIndex])
        focus:SetFocus()
    end
end

local function TypedConditionSummary(item)
            local phrase
            if item.type == "health" then phrase = HealthLabel(item.unit) .. " " .. (resourceSymbols[item.operator] or "?") .. " " .. tostring(item.percent or "?") .. "%"
            elseif item.type == "resource" then phrase = (resourceLabels[item.resource] or "Resource") .. " " .. (resourceSymbols[item.operator] or "?") .. " " .. tostring(item.percent or "?") .. "%"
            elseif item.type == "auraTime" then phrase = (auraPrefixes[item.unit] or "") .. (Trim(item.aura) ~= "" and Trim(item.aura) or "Choose aura") .. " time " .. (hawkSymbols[item.operator] or "?") .. " " .. tostring(item.seconds or "?") .. "s"
            elseif item.type == "stacks" then phrase = (auraPrefixes[item.auraSource] or "") .. (Trim(item.aura) ~= "" and Trim(item.aura) or "Choose aura") .. " stacks " .. (hawkSymbols[item.operator] or "?") .. " " .. tostring(item.value or "?")
            elseif item.type == "comboPoints" or item.type == "hawkCount" then phrase = (item.type == "comboPoints" and "Combo " or "Hawks ") .. (hawkSymbols[item.operator] or "?") .. " " .. tostring(item.value or "?")
            elseif item.type == "targetCasting" then phrase = "Target is casting"
            elseif item.type == "totemCondition" then phrase = totemLabels[item.value] or "Totem condition"
            elseif item.type == "customCondition" then phrase = Trim(item.value) ~= "" and Trim(item.value) or "Custom Conditions"
            else phrase = "Choose condition" end
    return phrase
end

local function RuleSummary(rule)
    local summary
    if type(rule.primaryCondition) == "table" then
        summary = TypedConditionSummary(rule.primaryCondition)
        if rule.manualCooldown then summary = summary .. " / manual cooldown"
        elseif rule.skipCooldown then summary = summary .. " / off cooldown" end
        if rule.useOr then summary = summary .. " / OR" end
    elseif rule.condition == "always" then
        summary = (rule.manualCooldown or rule.skipCooldown) and CooldownLabel(rule) or "Always"
    else
        local aura = Trim(rule.aura)
        if aura == "" then aura = rule.auraSource == "target" and "Choose debuff" or rule.auraSource == "player" and "Choose buff" or "Choose aura" end
        aura = (auraPrefixes[rule.auraSource] or "") .. aura
        summary = aura .. (rule.condition == "missing" and " missing" or " present")
        if rule.useOr then
            summary = summary .. " / OR"
            if rule.orAuraSource == "cooldown" then
                summary = summary .. " " .. (Trim(rule.orAura) ~= "" and Trim(rule.orAura) or "Choose spell")
                    .. (rule.orCondition == "missing" and " off cooldown" or " on cooldown")
            end
        end
        if rule.manualCooldown then summary = summary .. " / manual cooldown"
        elseif rule.skipCooldown then summary = summary .. " / off cooldown" end
    end
    for _, group in ipairs(extraGroups) do
        local auraCount = 0
        for _, entry in ipairs(rule[group] or {}) do
            if entry.auraSource ~= "cooldown" then auraCount = auraCount + 1 end
        end
        if auraCount > 0 then summary = summary .. " / " .. auraCount .. " " .. extraLabels[group] end
        for _, entry in ipairs(rule[group] or {}) do
            if entry.auraSource == "cooldown" then
                local text = (Trim(entry.aura) ~= "" and Trim(entry.aura) or "Choose spell")
                    .. (entry.condition == "missing" and " off cooldown" or " on cooldown")
                if group ~= "andConditions" or summary ~= "Always" then text = extraLabels[group] .. " " .. text end
                summary = summary == "Always" and text or summary .. " / " .. text
            end
        end
    end
    if type(rule.comboPoints) == "table" then
        summary = summary .. " / Combo " .. (comboSymbols[rule.comboPoints.operator] or "?") .. " " .. tostring(rule.comboPoints.value or "?")
    end
    if type(rule.hawkCount) == "table" then
        local hawks = "Hawks " .. (hawkSymbols[rule.hawkCount.operator] or "?") .. " " .. tostring(rule.hawkCount.value or "?")
        summary = summary == "Always" and hawks or summary .. " / " .. hawks
    end
    for _, resource in ipairs(type(rule.resourceConditions) == "table" and rule.resourceConditions or {}) do
        if type(resource) == "table" then
            summary = summary .. " / " .. (resourceLabels[resource.resource] or "Resource") .. " "
                .. (resourceSymbols[resource.operator] or "?") .. " " .. tostring(resource.percent or "?") .. "%"
        end
    end
    for _, health in ipairs(type(rule.healthConditions) == "table" and rule.healthConditions or {}) do
        if type(health) == "table" then
            local text = HealthLabel(health.unit) .. " " .. (resourceSymbols[health.operator] or "?") .. " " .. tostring(health.percent or "?") .. "%"
            summary = summary == "Always" and text or summary .. " / " .. text
        end
    end
    for _, stacks in ipairs(type(rule.stackConditions) == "table" and rule.stackConditions or {}) do
        if type(stacks) == "table" then
            local aura = Trim(stacks.aura)
            local text = (auraPrefixes[stacks.auraSource] or "") .. (aura ~= "" and aura or "Choose aura")
                .. " stacks " .. (hawkSymbols[stacks.operator] or "?") .. " " .. tostring(stacks.value or "?")
            summary = summary == "Always" and text or summary .. " / " .. text
        end
    end
    if rule.customCondition ~= nil then summary = summary .. " / " .. rule.customCondition end
    if rule.targetCasting then
        summary = summary == "Always" and "Target is casting" or summary .. " / Target is casting"
    end
    if rule.totemCondition then
        local totem = totemLabels[rule.totemCondition] or "Totem condition"
        summary = summary == "Always" and totem or summary .. " / " .. totem
    end
    for _, item in ipairs(type(rule.logicConditions) == "table" and rule.logicConditions or {}) do
        if type(item) == "table" then
            local phrase = TypedConditionSummary(item)
            summary = summary .. " / " .. (item.logic or "?") .. " " .. phrase
        end
    end
    if rule.skipIfImmune then
        summary = summary == "Always" and "Skip if immune (bleed)" or summary .. " / Skip if immune (bleed)"
    end
    if rule.skipOutOfRange then
        summary = summary == "Always" and "Skip if out of range" or summary .. " / Skip if out of range"
    end
    if rule.outOfCombatOnly then
        summary = summary == "Always" and "Out of combat only" or summary .. " / Out of combat only"
    end
    if rule.inCombatOnly then
        summary = summary == "Always" and "In combat only" or summary .. " / In combat only"
    end
    if rule.advanceOnToggle then
        summary = summary == "Always" and "Advance on toggle" or summary .. " / Advance on toggle"
    end
    if rule.skipModifier then
        local text = "Skip if " .. (ruleModifierLabels[rule.skipModifier] or tostring(rule.skipModifier)) .. " held"
        summary = summary == "Always" and text or summary .. " / " .. text
    end
    if rule.priorityModifier then
        local text = "Prioritize if " .. (ruleModifierLabels[rule.priorityModifier] or tostring(rule.priorityModifier)) .. " held"
        summary = summary == "Always" and text or summary .. " / " .. text
    end
    if summary == "Always" and SH.Model.IsAutoAttack(rule.spell) then return "When Auto Attack is off" end
    return summary
end

local function RefreshTargetCasting(ui, row, rule, top)
    local panel = row.targetCastingPanel
    if not rule.targetCasting then
        if panel then panel:Hide() end
        return top
    end
    if not panel then
        panel = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.targetCastingPanel = panel
        panel:SetSize(686, 61)
        Skin(panel, { 0.075, 0.105, 0.13, 1 }, { 0.15, 0.2, 0.25, 1 })
        panel.title = Label(panel, "", "GameFontNormal", accent)
        panel.title:SetPoint("TOPLEFT", 12, -9)
        local hint = Label(panel, "Checks your current target for a cast or channel, even if the spell can't be interrupted.", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 13, -34)
        panel.remove = Button(panel, "Remove", 78, 25)
        panel.remove:SetPoint("TOPRIGHT", -12, -7)
        panel.remove:SetScript("OnClick", function()
            local current = ui.draft[row.index]
            current.targetCasting = nil
            ClearCountAttachment(current, "targetCasting")
            DraftChanged(ui)
            RefreshRows(ui)
        end)
    end
    panel.top = top
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", 14, -top)
    panel.title:SetText(ConditionTitle(ConditionEntry(rule, "targetCasting")) .. " - Target is casting")
    panel:Show()
    return top + panel:GetHeight() + 8
end

local function RefreshTotemCondition(ui, row, rule, top)
    local panel = row.totemPanel
    if not rule.totemCondition then
        if panel then panel:Hide() end
        return top
    end
    if not panel then
        panel = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.totemPanel = panel
        panel:SetSize(686, 94)
        Skin(panel, { 0.075, 0.105, 0.13, 1 }, { 0.15, 0.2, 0.25, 1 })
        panel.title = Label(panel, "", "GameFontNormal", accent)
        panel.title:SetPoint("TOPLEFT", 12, -9)
        panel.element = Button(panel, "", 120, 25)
        panel.element:SetPoint("TOPLEFT", 12, -35)
        MarkDropdown(panel.element)
        panel.element:SetScript("OnClick", function(self)
            local current = ui.draft[row.index]
            ChoiceMenu(ui, self, Choices(totemElements, totemElementLabels), TotemConditionElement(current.totemCondition), function(value)
                if value ~= TotemConditionElement(current.totemCondition) then
                    current.totemCondition = TotemConditionMode(value, TotemConditionMissing(current.totemCondition))
                    DraftChanged(ui)
                end
            end)
        end)
        Tooltip(panel.element, "Totem element", "Check your Fire, Earth, Water, or Air slot. Empty-slot conditions wait while any totem occupies that element's slot.")
        panel.mode = Button(panel, "", 240, 25)
        panel.mode:SetPoint("LEFT", panel.element, "RIGHT", 10, 0)
        MarkDropdown(panel.mode)
        panel.mode:SetScript("OnClick", function(self)
            local current = ui.draft[row.index]
            ChoiceMenu(ui, self, Choices(totemModes[TotemConditionElement(current.totemCondition)] or totemModes.fire, totemLabels), current.totemCondition, function(value)
                current.totemCondition = value
                DraftChanged(ui)
            end)
        end)
        Tooltip(panel.mode, "Totem condition", function()
            return TotemConditionMissing(ui.draft[row.index].totemCondition) and totemDestroyedHelp or totemCooldownHelp
        end)
        panel.hint = Label(panel, "", "GameFontHighlightSmall")
        panel.hint:SetPoint("TOPLEFT", 12, -68)
        panel.hint:SetWidth(660)
        panel.remove = Button(panel, "Remove", 78, 25)
        panel.remove:SetPoint("TOPRIGHT", -12, -7)
        panel.remove:SetScript("OnClick", function()
            local current = ui.draft[row.index]
            current.totemCondition = nil
            ClearCountAttachment(current, "totemCondition")
            DraftChanged(ui)
        end)
    end
    local missing = TotemConditionMissing(rule.totemCondition)
    panel.top = top
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", 14, -top)
    panel.title:SetText(ConditionTitle(ConditionEntry(rule, "totemCondition")) .. (missing and " - Totem conditions" or " - Totem cooldown"))
    panel.element:SetText(totemElementLabels[TotemConditionElement(rule.totemCondition)] or "Choose element")
    panel.mode:SetText(totemLabels[rule.totemCondition] or "Choose a totem condition")
    panel.hint:SetText(missing and "Empty before summoning, or after destruction, expiry, or dismissal. Occupied slots do not match."
        or "Your totem must still be active in the selected element's slot when you press.")
    panel:Show()
    return top + panel:GetHeight() + 8
end

local function RefreshModifiers(ui, row, rule, top, view)
    local panel = row.modifiersPanel
    if not (SH.rootDB.modifiersEnabled or rule.skipModifier or rule.priorityModifier) then
        if panel then panel:Hide() end
        return top
    end
    if not panel then
        panel = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.modifiersPanel = panel
        panel:SetSize(686, 130)
        Skin(panel, { 0.075, 0.105, 0.13, 1 }, { 0.15, 0.2, 0.25, 1 })
        panel.title = Label(panel, "Modifiers", "GameFontNormal", accent)
        panel.title:SetPoint("TOPLEFT", 12, -9)
        local function ModifierChoice(field, label, x)
            local caption = Label(panel, label, "GameFontHighlightSmall")
            caption:SetPoint("TOPLEFT", x, -42)
            local choice = Button(panel, "None", 140, 25)
            choice:SetPoint("TOPLEFT", x + 83, -35)
            MarkDropdown(choice)
            Tooltip(choice, label, modifierHelp)
            choice:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                ChoiceMenu(ui, self, Choices(ruleModifiers, ruleModifierLabels), current[field] or "none", function(value)
                    if value == "none" then current[field] = nil else current[field] = value end
                    ui.castingViews[current] = ui.castingViews[current] or {}
                    ui.castingViews[current].modifiers = true
                    DraftChanged(ui)
                end)
            end)
            return choice, caption
        end
        panel.skip, panel.skipLabel = ModifierChoice("skipModifier", "Skip if", 12)
        panel.priority, panel.priorityLabel = ModifierChoice("priorityModifier", "Prioritize if", 344)
        panel.hint = Label(panel, "Hold a key while pressing Hit Button. Conditions and cooldown still apply.\nPrioritized rules keep their listed order. Skip wins if both apply. None turns that choice off.", "GameFontHighlightSmall")
        panel.hint:SetPoint("TOPLEFT", 12, -72)
        panel.hint:SetSize(660, 46)
        panel.hint:SetWordWrap(true)
        panel.hint:SetJustifyV("TOP")
        panel.remove = Button(panel, "Reset", 78, 25)
        panel.remove:SetPoint("TOPRIGHT", -12, -7)
        panel.remove:SetScript("OnClick", function()
            local current = ui.draft[row.index]
            current.skipModifier, current.priorityModifier = nil, nil
            if ui.castingViews[current] then ui.castingViews[current].modifiers = nil end
            DraftChanged(ui)
        end)
    end
    panel.top = top
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", 14, -top)
    panel.skip:SetText(ruleModifierLabels[rule.skipModifier or "none"] or "Choose modifier")
    panel.priority:SetText(ruleModifierLabels[rule.priorityModifier or "none"] or "Choose modifier")
    panel:Show()
    return top + panel:GetHeight() + 8
end

local function RefreshCastingOptions(ui)
    ui.castingViews = ui.castingViews or setmetatable({}, { __mode = "k" })
    for i, row in ipairs(ui.rows) do
        local rule = ui.draft[i]
        if rule then
            local view = ui.castingViews[rule] or {}
            local hasCount = DraftCount(rule.castCount) ~= nil and DraftCount(rule.castCount) ~= 0
            local showCount = not (row.attackCommand or row.wandShoot or row.autoShot) or hasCount
            local showSettings = true
            local showSpellSettings = showSettings and not row.attackCommand
            local count = (rule.stopCasting and 1 or 0) + (rule.stopWhenInvalid and 1 or 0)
                + (rule.oncePerProc and 1 or 0)
                + (rule.skipIfImmune and 1 or 0)
                + (rule.skipOutOfRange and 1 or 0)
                + (rule.outOfCombatOnly and 1 or 0)
                + (rule.inCombatOnly and 1 or 0)
                + (rule.advanceOnToggle and 1 or 0)
                + ((tonumber(rule.castCount) or 0) > 0 and 1 or 0)
                + (rule.comboPoints ~= nil and 1 or 0)
                + (rule.hawkCount ~= nil and 1 or 0)
                + (type(rule.resourceConditions) == "table" and #rule.resourceConditions or 0)
                + (type(rule.healthConditions) == "table" and #rule.healthConditions or 0)
                + (type(rule.stackConditions) == "table" and #rule.stackConditions or 0)
                + (type(rule.logicConditions) == "table" and #rule.logicConditions or 0)
                + (rule.customCondition ~= nil and 1 or 0)
                + (rule.targetCasting and 1 or 0)
                + (rule.totemCondition and 1 or 0)
                + (rule.skipModifier and 1 or 0) + (rule.priorityModifier and 1 or 0)
            row.castingOptions:SetText("+ Casting conditions" .. (count > 0 and (" (" .. count .. " enabled)") or ""))
            row.optionsBody:SetShown(showCount or showSettings)
            for _, widget in ipairs({row.stopCasting, row.stopCastingLabel, row.stopWhenInvalid,
                row.stopWhenInvalidLabel, row.oncePerProc, row.oncePerProcLabel, row.skipOutOfRange,
                row.skipOutOfRangeLabel, row.advanceOnToggle, row.advanceOnToggleLabel,
                row.optionsHint}) do widget:SetShown(showSpellSettings) end
            row.outOfCombatOnly:SetShown(showSettings)
            row.outOfCombatOnlyLabel:SetShown(showSettings)
            row.outOfCombatOnly:ClearAllPoints()
            row.outOfCombatOnly:SetPoint("TOPLEFT", row.attackCommand and 0 or 225, row.attackCommand and 0 or -28)
            row.inCombatOnly:SetShown(showSettings)
            row.inCombatOnlyLabel:SetShown(showSettings)
            row.inCombatOnly:ClearAllPoints()
            row.inCombatOnly:SetPoint("TOPLEFT", row.attackCommand and 225 or 456, row.attackCommand and 0 or -28)
            for _, widget in ipairs({row.castCount, row.castCountLabel, row.castCountHint,
                row.castCountCondition, row.countAttachmentLabel}) do widget:SetShown(showCount) end
            row.countReminder:SetShown(showCount and hasCount)
            if not showCount then row.castCount:ClearFocus() end
            RefreshCountControls(row, rule)
            row.castCountLabel:ClearAllPoints()
            row.castCount:ClearAllPoints()
            row.castCountHint:ClearAllPoints()
            row.castCountCondition:ClearAllPoints()
            row.countAttachmentLabel:ClearAllPoints()
            row.countReminder:ClearAllPoints()
            local settingsHeight = showSettings and (row.attackCommand and 25 or 100) or 0
            local countY = showSettings and -settingsHeight - 6 or -2
            row.castCountLabel:SetPoint("TOPLEFT", 6, countY - 7)
            row.castCount:SetPoint("TOPLEFT", 88, countY)
            row.castCountHint:SetPoint("TOPLEFT", 152, countY - 7)
            row.countAttachmentLabel:SetPoint("TOPLEFT", 246, countY - 7)
            row.castCountCondition:SetPoint("TOPLEFT", 350, countY)
            row.countReminder:SetPoint("TOPLEFT", 6, countY - 32)
            local typed = type(rule.primaryCondition) == "table" and rule.primaryCondition or nil
            local primaryLabels = {comboPoints = "Combo points", resource = "Resources", stacks = "Aura stacks", auraTime = "Aura time remaining",
                targetCasting = "Target is casting", totemCondition = "Totem conditions", hawkCount = "Hawk conditions",
                customCondition = "Custom Conditions"}
            row.primaryType:SetText(typed and (typed.type == "health" and HealthLabel(typed.unit) or primaryLabels[typed.type] or "Choose condition")
                or rule.condition ~= "always" and "Aura" or (rule.skipCooldown or rule.manualCooldown) and "Spell cooldown" or "Always")
            row.primaryTitle:SetText(ConditionTitle(ConditionEntry(rule, "primary")))
            row.primaryTitle:SetShown(not typed)
            row.primaryPanel:SetShown(not typed)
            local auraPrimary = not typed and rule.condition ~= "always"
            for _, widget in ipairs({row.condition, row.aura, row.auraLabel, row.auraSource}) do widget:SetShown(auraPrimary) end
            row.primaryHint:SetShown(not typed and not auraPrimary)
            row.primaryHint:SetText((rule.skipCooldown or rule.manualCooldown) and "Cast when this spell is off cooldown. Added conditions still apply."
                or "No IF requirement. Added AND and NOT conditions still apply.")
            local y = RefreshLogicConditions(ui, row, rule, 132, true)
            if not typed then
                row.primaryPanel:SetHeight(auraPrimary and 130 or 78)
                y = auraPrimary and 270 or 218
            end
            row.primaryBottom = y
            row.primaryType:SetFrameLevel(row:GetFrameLevel() + 3)
            row.useOrLabel:SetText(ConditionTitle(ConditionEntry(rule, "or"))
                .. (rule.orAuraSource == "cooldown" and " / Spell cooldown" or " / Alternative aura"))
            local legacyOr = rule.useOr == true
            for _, widget in ipairs({row.alternativePanel, row.useOr, row.useOrLabel,
                row.orAuraSource, row.orAura, row.orAuraLabel, row.orCondition}) do widget:SetShown(legacyOr) end
            if legacyOr then
                row.alternativePanel:ClearAllPoints(); row.alternativePanel:SetPoint("TOPLEFT", 14, -y)
                row.useOr:ClearAllPoints(); row.useOr:SetPoint("TOPLEFT", 23, -y - 6)
                row.orAuraSource:ClearAllPoints(); row.orAuraSource:SetPoint("TOPLEFT", 524, -y - 6)
                row.orAuraLabel:ClearAllPoints(); row.orAuraLabel:SetPoint("TOPLEFT", 220, -y - 26)
                row.orAura:ClearAllPoints(); row.orAura:SetPoint("TOPLEFT", 220, -y - 40)
                row.orCondition:ClearAllPoints(); row.orCondition:SetPoint("TOPLEFT", 27, -y - 40)
                y = y + 86
            end
            y = RefreshInlineConditions(ui, row, rule, y)
            row.comboPoints:SetShown(rule.comboPoints ~= nil)
            if rule.comboPoints ~= nil then
                local combo = type(rule.comboPoints) == "table" and rule.comboPoints or {}
                row.comboPoints:ClearAllPoints()
                row.comboPoints:SetPoint("TOPLEFT", 14, -y)
                row.comboTop = y
                row.comboTitle:SetText(ConditionTitle(ConditionEntry(rule, "comboPoints")) .. " - Combo points")
                row.comboOperator:SetText(comboOperatorLabels[combo.operator] or "Choose comparison")
                row.comboValue:SetText(type(combo.value) == "number" and tostring(combo.value) or "Choose")
                y = y + 86
            end
            row.hawkCount:SetShown(rule.hawkCount ~= nil)
            if rule.hawkCount ~= nil then
                local hawk = type(rule.hawkCount) == "table" and rule.hawkCount or {}
                row.hawkCount:ClearAllPoints()
                row.hawkCount:SetPoint("TOPLEFT", 14, -y)
                row.hawkTop = y
                row.hawkTitle:SetText(ConditionTitle(ConditionEntry(rule, "hawkCount")) .. " - Hawk conditions")
                row.hawkOperator:SetText(hawkOperatorLabels[hawk.operator] or "Choose comparison")
                row.hawkValue:SetText(type(hawk.value) == "number" and tostring(hawk.value) or "Choose")
                y = y + 86
            end
            y = RefreshResourceConditions(ui, row, rule, y)
            y = RefreshHealthConditions(ui, row, rule, y)
            y = RefreshStackConditions(ui, row, rule, y)
            row.macroPanel:SetShown(rule.customCondition ~= nil)
            if rule.customCondition ~= nil then
                row.macroTop = y
                row.macroPanel:ClearAllPoints()
                row.macroPanel:SetPoint("TOPLEFT", 14, -y)
                row.macroTitle:SetText(ConditionTitle(ConditionEntry(rule, "customCondition")) .. " - Custom Conditions")
                y = y + 84
            end
            y = RefreshTargetCasting(ui, row, rule, y)
            y = RefreshTotemCondition(ui, row, rule, y)
            y = RefreshLogicConditions(ui, row, rule, y)
            row.wandHint:SetShown(row.wandShoot or row.autoShot or row.attackCommand ~= nil)
            if row.wandShoot or row.autoShot or row.attackCommand then
                if row.customRuleAction then
                    row.wandHint:SetText("Runs these commands, then checks the next matching rule on the same press. Prepare applies your edits.")
                elseif row.petAttack then
                    row.wandHint:SetText("Keep Attack on your pet bar. Once your pet engages your target, continue to the next rule.")
                elseif row.attackCommand == "Auto Attack" then
                    row.wandHint:SetText("Starts your melee swings and tries the next matching ability on the same press. Repeated presses don't stop your swings.")
                elseif row.wandShoot then
                    row.wandHint:SetText("Keep wanding (automatic). Repeated presses keep Shoot active.")
                else
                    row.wandHint:SetText("Repeated presses keep Auto Shot active.")
                end
                row.wandHint:ClearAllPoints()
                row.wandHint:SetPoint("TOPLEFT", 20, -y - 5)
                y = y + 30
            end
            row.castingOptions:ClearAllPoints()
            row.castingOptions:SetPoint("TOPLEFT", 14, -y)
            row.castingOptions:SetWidth(686)
            for _, widget in ipairs({row.pingDelay, row.pingDelayLabel, row.pingDelayMS, row.pingDelayUnit, row.pingDelayHint,
                row.manualCooldown, row.manualCooldownLabel, row.manualCooldownSeconds, row.manualCooldownUnit, row.manualCooldownHint}) do
                widget:SetShown(not row.attackCommand)
            end
            row.pingDelay:ClearAllPoints()
            row.settingsTitle:ClearAllPoints()
            row.settingsTitle:SetPoint("TOPLEFT", 20, -y - 36)
            row.pingDelay:SetPoint("TOPLEFT", 15, -y - 58)
            row.pingDelayTop = y + 58
            row.pingDelayMS:ClearAllPoints()
            row.pingDelayMS:SetPoint("TOPLEFT", 132, -y - 58)
            row.manualCooldown:ClearAllPoints()
            row.manualCooldown:SetPoint("TOPLEFT", 15, -y - 92)
            row.manualCooldownTop = y + 92
            row.manualCooldownSeconds:ClearAllPoints()
            row.manualCooldownSeconds:SetPoint("TOPLEFT", 174, -y - 92)
            local canSkipFailedCast = not (row.attackCommand or row.wandShoot or row.autoShot)
            row.skipIfNotCasted:SetShown(canSkipFailedCast)
            row.skipIfNotCastedLabel:SetShown(canSkipFailedCast)
            row.skipIfImmune:ClearAllPoints()
            row.skipIfImmuneTop = y + (row.attackCommand and 58 or 126)
            row.skipIfImmune:SetPoint("TOPLEFT", 15, -row.skipIfImmuneTop)
            row.skipIfImmune:SetShown(not row.customRuleAction)
            row.skipIfImmuneLabel:SetShown(not row.customRuleAction)
            row.optionsBody:ClearAllPoints()
            row.skipCooldown:SetShown(not row.attackCommand)
            row.skipCooldownLabel:SetShown(not row.attackCommand)
            row.cooldownHint:SetShown(not row.attackCommand)
            row.skipCooldown:ClearAllPoints(); row.skipCooldown:SetPoint("TOPLEFT", 15, -y - 160)
            row.cooldownTop = y + 160
            row.cooldownHint:ClearAllPoints(); row.cooldownHint:SetPoint("TOPLEFT", 207, -y - 168)
            row.cooldownHint:SetText(rule.manualCooldown and "Uses the manual cooldown above." or "Check this spell's cooldown as well as its conditions.")
            row.optionsTop = y + (row.attackCommand and 94 or 196)
            row.optionsBody:SetPoint("TOPLEFT", 14, -row.optionsTop)
            local countHeight = showCount and (-countY + (hasCount and 72 or 27)) or 0
            row.optionsBody:SetHeight(math.max(1, settingsHeight, countHeight))
            local bottom = (showSettings or showCount) and row.optionsTop + row.optionsBody:GetHeight() or y + (row.attackCommand and 83 or 185)
            bottom = RefreshModifiers(ui, row, rule, bottom + 12, view)
            row:SetHeight(math.max(500, bottom + 14))
        end
    end
    RefreshEditorScroll(ui)
end

local function ScrollToSelection(ui)
    if #ui.draft == 0 then
        ui.scroll:SetVerticalScroll(0)
        if ui.scroll.ScrollBar then ui.scroll.ScrollBar:SetValue(0) end
        return
    end
    local top = (ui.selectedIndex - 1) * ROW_HEIGHT
    local viewport = ui.scroll:GetHeight()
    local offset = ui.scroll:GetVerticalScroll() or 0
    if top < offset then offset = top end
    if top + ROW_HEIGHT > offset + viewport then offset = top + ROW_HEIGHT - viewport end
    offset = math.max(0, math.min(offset, math.max(0, #ui.draft * ROW_HEIGHT - viewport)))
    ui.scroll:SetVerticalScroll(offset)
    if ui.scroll.ScrollBar then ui.scroll.ScrollBar:SetValue(offset) end
end

local function RefreshPriorityList(ui)
    if not ui.priorityButtons then return end
    for i, rule in ipairs(ui.draft) do
        local entry = ui.priorityButtons[i]
        if not entry then
            entry = CreateFrame("Button", nil, ui.scrollChild, "BackdropTemplate")
            entry:SetSize(202, ROW_HEIGHT - 4)
            entry.number = Label(entry, "", "GameFontHighlightSmall", accent)
            entry.number:SetPoint("TOPLEFT", 9, -7)
            entry.enableRule = CreateFrame("CheckButton", nil, entry, "UICheckButtonTemplate")
            entry.enableRule:SetSize(21, 21)
            entry.enableRule:SetPoint("TOPLEFT", 66, -2)
            if entry.enableRule.SetHitRectInsets then entry.enableRule:SetHitRectInsets(0, -72, 0, 0) end
            entry.enableLabel = Label(entry, "Enable Rule", "GameFontHighlightSmall")
            entry.enableLabel:SetPoint("LEFT", entry.enableRule, "RIGHT", 2, 0)
            Tooltip(entry.enableRule, "Enable Rule", "Uncheck to skip this rule when you Prepare. Its settings and priority are saved.")
            entry.enableRule:SetScript("OnClick", function(self)
                if self:GetChecked() and ui.draft[entry.index].customRule ~= nil and HasEnabledCustomRule(ui, entry.index) then
                    self:SetChecked(false)
                    ShowResult(ui, false, "Only one Custom Rule can be enabled per Hit Button. Uncheck Enable Rule on the other Custom Rule first.")
                    return
                end
                ui.draft[entry.index].enabled = self:GetChecked() and true or false
                DraftChanged(ui)
            end)
            entry.title = Label(entry, "", "GameFontHighlight")
            entry.title:SetPoint("TOPLEFT", 9, -24)
            entry.title:SetSize(184, 16)
            entry.title:SetWordWrap(false)
            entry.summary = Label(entry, "", "GameFontHighlightSmall", { 0.66, 0.74, 0.79 })
            entry.summary:SetPoint("TOPLEFT", 9, -42)
            entry.summary:SetSize(184, 13)
            entry.summary:SetWordWrap(false)
            entry.batch = Label(entry, "", "GameFontHighlightSmall", accent)
            entry.batch:SetPoint("TOPLEFT", 9, -58)
            entry.batch:SetSize(184, 13)
            entry.batch:SetWordWrap(false)
            local highlight = entry:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(0.36, 0.78, 0.88, 0.12)
            entry:SetHighlightTexture(highlight)
            entry:SetScript("OnClick", function(self) ui:SelectRule(self.index) end)
            ui.priorityButtons[i] = entry
        end
        entry.index = i
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        local spell = DisplaySpell(rule)
        entry.number:SetText("Rule " .. i)
        entry.enableRule:SetChecked(rule.enabled ~= false)
        entry.title:SetAlpha(rule.enabled == false and 0.55 or 1)
        entry.title:SetText(spell ~= "" and spell or "New spell")
        entry.summary:SetText(RuleSummary(rule))
        local count = tonumber(rule.castCount) or 0
        local attached = SH.Model.GetCountCondition(rule)
        entry.batch:SetText(count > 0 and ((attached and ("Condition " .. attached.number) or "Missing condition")
            .. ": " .. count .. " completed casts") or "")
        local selected = i == ui.selectedIndex
        Skin(entry, selected and { 0.10, 0.24, 0.30, 1 } or { 0.055, 0.075, 0.095, 1 },
            selected and { 0.36, 0.78, 0.88, 1 } or { 0.13, 0.19, 0.23, 1 })
        entry:Show()
    end
    for i = #ui.draft + 1, #ui.priorityButtons do ui.priorityButtons[i]:Hide() end
    RefreshCastingOptions(ui)
    if RefreshRuleDiagram then RefreshRuleDiagram(ui) end
end

local function SelectRule(ui, index)
    if ui.choiceMenu then ui.choiceMenu:Hide() end
    ui.selectedIndex = math.max(1, math.min(tonumber(index) or 1, #ui.draft))
    ui.selectedIndices[ActiveRotation(ui).index or 1] = ui.selectedIndex
    for i, row in ipairs(ui.rows) do
        local selected = i == ui.selectedIndex and i <= #ui.draft
        if not selected then ClearRowFocus(row) end
        row:SetShown(selected)
    end
    ui.moveUp:SetEnabled(#ui.draft > 0 and ui.selectedIndex > 1)
    ui.moveDown:SetEnabled(#ui.draft > 0 and ui.selectedIndex < #ui.draft)
    ui.remove:SetEnabled(#ui.draft > 0)
    ui.copyRule:SetEnabled(#ui.draft > 0)
    ui.pasteRule:SetEnabled(ui.copiedRule ~= nil and #ui.draft < MAX_RULES)
    RefreshPriorityList(ui)
    ScrollToSelection(ui)
end

DraftChanged = function(ui)
    ui.message = nil
    SaveDraft(ui)
    RefreshPriorityList(ui)
    SH:RefreshUIStatus()
end

local function AddExtraCondition(ui, group, source)
    local rule = ui.draft[ui.selectedIndex]
    if not rule or ExtraCount(rule) >= MAX_EXTRA_CONDITIONS then return end
    rule[group] = rule[group] or {}
    table.insert(rule[group], { aura = "", auraSource = source or "tracker", condition = "present" })
    DraftChanged(ui)
    RefreshRows(ui)
    for _, entry in ipairs(ui.rows[ui.selectedIndex].conditionRows) do
        if entry.group == group and entry.entryIndex == #rule[group] then
            local finalEntry = entry.displayIndex == ExtraCount(rule)
            RevealEditorRegion(ui, entry.top, entry:GetHeight() + (finalEntry and 40 or 8), entry.aura)
        end
    end
end

local logicLabels = {
    comboPoints = "Combo points", resource = "Resources", health = "Enemy health", stacks = "Aura stacks", auraTime = "Aura time remaining",
    targetCasting = "Target is casting", totemCondition = "Totem conditions", hawkCount = "Hawk conditions",
    customCondition = "Custom Conditions",
}
local logicKinds = {"AND", "OR", "NOT"}
local logicKindLabels = {AND = "AND", OR = "OR", NOT = "NOT"}
local logicGroups = {AND = "andConditions", OR = "orConditions", NOT = "notConditions"}

local function TypedConditionRoom(rule, kind, replacePrimary)
    local conditionType = (kind == "targetHealth" or kind == "playerHealth") and "health" or kind
    local group = conditionType == "resource" and "resourceConditions"
        or conditionType == "health" and "healthConditions" or conditionType == "stacks" and "stackConditions"
    if not group and conditionType ~= "auraTime" then return true end
    local count = group and #(rule[group] or {}) or 0
    if not replacePrimary and type(rule.primaryCondition) == "table" and rule.primaryCondition.type == conditionType then count = count + 1 end
    for _, item in ipairs(rule.logicConditions or {}) do
        if type(item) == "table" and item.type == conditionType then count = count + 1 end
    end
    return count < 8
end

local function NewTypedCondition(rule, kind)
    local item = {type = kind}
    if kind == "comboPoints" then item.operator, item.value = "ge", 5
    elseif kind == "hawkCount" then item.operator, item.value = "lt", 2
    elseif kind == "resource" then item.resource, item.operator, item.percent = "mana", "lt", 50
    elseif kind == "targetHealth" or kind == "playerHealth" then
        item.type, item.unit, item.operator, item.percent = "health", kind == "playerHealth" and "player" or "target", "lt", 20
    elseif kind == "stacks" then item.aura, item.auraSource, item.operator, item.value = "", "target", "lt", 5
    elseif kind == "auraTime" then item.aura, item.unit, item.operator, item.seconds = "", "player", "le", 5
    elseif kind == "totemCondition" then item.value = TotemConditionMode(DefaultTotemElement(rule), true)
    elseif kind == "customCondition" then item.value = "" end
    return item
end

local function PrimaryConditionMenu(ui, row, owner)
    local rule = ui.draft[row.index]
    local choices = {
        {value = "always", label = "Always"}, {value = "aura", label = "Aura"},
        {value = "spellCooldown", label = "Spell cooldown", enabled = not row.attackCommand},
        {value = "comboPoints", label = "Combo points"}, {value = "resource", label = "Resources", enabled = TypedConditionRoom(rule, "resource", true)},
        {value = "targetHealth", label = "Enemy health", enabled = TypedConditionRoom(rule, "targetHealth", true)},
        {value = "playerHealth", label = "Self health", enabled = TypedConditionRoom(rule, "playerHealth", true)},
        {value = "stacks", label = "Aura stacks", enabled = TypedConditionRoom(rule, "stacks", true)},
        {value = "auraTime", label = "Aura time remaining", enabled = TypedConditionRoom(rule, "auraTime", true)},
        {value = "targetCasting", label = "Target is casting"},
    }
    if SH.IsShaman and SH.IsShaman() then choices[#choices + 1] = {value = "totemCondition", label = "Totem conditions"} end
    if SH.IsHunter and SH.IsHunter() then choices[#choices + 1] = {value = "hawkCount", label = "Hawk conditions"} end
    if SH.rootDB.customConditionsEnabled then choices[#choices + 1] = {value = "customCondition", label = "Custom Conditions"} end
    ChoiceMenu(ui, owner, choices, nil, function(kind)
        ClearRowFocus(row)
        if kind == "aura" then
            rule.primaryCondition = nil
            if rule.condition == "always" then rule.condition = "present" end
        elseif kind == "always" or kind == "spellCooldown" then
            rule.primaryCondition, rule.condition = nil, "always"
            if not rule.manualCooldown then rule.skipCooldown = kind == "spellCooldown" end
        else
            rule.primaryCondition = NewTypedCondition(rule, kind)
            rule.condition, rule.aura = "always", ""
        end
        DraftChanged(ui)
        RefreshRows(ui)
        local card = row.primaryTypedRows and row.primaryTypedRows[1]
        local focus = kind == "aura" and row.aura or card and ((kind == "stacks" or kind == "auraTime") and card.aura
            or kind == "customCondition" and card.custom
            or (kind == "resource" or kind == "targetHealth" or kind == "playerHealth") and card.percent)
        RevealEditorRegion(ui, 132, row.primaryBottom - 132, focus)
    end)
end

local function AddLogicCondition(ui, logic, kind)
    local rule = ui.draft[ui.selectedIndex]
    if not rule or #(rule.logicConditions or {}) >= 8 then return end
    local item = NewTypedCondition(rule, kind)
    item.logic = logic
    rule.logicConditions = rule.logicConditions or {}
    rule.logicConditions[#rule.logicConditions + 1] = item
    DraftChanged(ui)
    RefreshRows(ui)
    local entry = ui.rows[ui.selectedIndex].logicRows[#rule.logicConditions]
    local focus = (kind == "stacks" or kind == "auraTime") and entry.aura or kind == "customCondition" and entry.custom
        or (kind == "resource" or kind == "targetHealth" or kind == "playerHealth") and entry.percent
    RevealEditorRegion(ui, entry.top, entry:GetHeight(), focus)
end

local function AddLegacyAndCondition(ui, kind)
    local rule, row = ui.draft[ui.selectedIndex], ui.rows[ui.selectedIndex]
    local field = kind == "comboPoints" and "comboPoints" or kind == "hawkCount" and "hawkCount"
        or kind == "targetCasting" and "targetCasting" or kind == "totemCondition" and "totemCondition"
        or kind == "customCondition" and "customCondition"
    if field and rule[field] ~= nil then return false end
    local entry, group
    if kind == "comboPoints" then rule.comboPoints = {operator = "ge", value = 5}
    elseif kind == "hawkCount" then rule.hawkCount = {operator = "lt", value = 2}
    elseif kind == "targetCasting" then rule.targetCasting = true
    elseif kind == "totemCondition" then rule.totemCondition = TotemConditionMode(DefaultTotemElement(rule), true)
    elseif kind == "customCondition" then rule.customCondition = ""
    elseif kind == "resource" then group, entry = "resourceConditions", {resource = "mana", operator = "lt", percent = 50}
    elseif kind == "targetHealth" or kind == "playerHealth" then
        group, entry = "healthConditions", {operator = "lt", percent = 20, unit = kind == "playerHealth" and "player" or nil}
    elseif kind == "stacks" then group, entry = "stackConditions", {aura = "", auraSource = "target", operator = "lt", value = 5}
    else return false end
    if group then
        rule[group] = rule[group] or {}
        if #rule[group] >= 8 then return true end
        rule[group][#rule[group] + 1] = entry
    end
    if Trim(rule.aura) == "" and not rule.useOr and ExtraCount(rule) == 0
        and not rule.oncePerProc and not rule.stopCasting and not rule.stopWhenInvalid
        and not HasDraftCount(rule) then rule.condition = "always" end
    DraftChanged(ui)
    RefreshRows(ui)
    if group then
        local rows = group == "resourceConditions" and row.resourceRows or group == "healthConditions" and row.healthRows or row.stackRows
        local card = rows[#rule[group]]
        RevealEditorRegion(ui, card.top, card:GetHeight(), group == "stackConditions" and card.aura or card.percent)
    elseif kind == "comboPoints" then RevealEditorRegion(ui, row.comboTop, row.comboPoints:GetHeight())
    elseif kind == "hawkCount" then RevealEditorRegion(ui, row.hawkTop, row.hawkCount:GetHeight())
    elseif kind == "targetCasting" then RevealEditorRegion(ui, row.targetCastingPanel.top, row.targetCastingPanel:GetHeight())
    elseif kind == "totemCondition" then RevealEditorRegion(ui, row.totemPanel.top, row.totemPanel:GetHeight())
    else RevealEditorRegion(ui, row.macroTop, row.macroPanel:GetHeight(), row.customCondition) end
    return true
end

local function AddConditionMenu(ui, owner, forcedLogic, beforeAdd, afterAdd)
    local rule = ui.draft[ui.selectedIndex]
    if not rule then return end
    local function chooseLogic(logic)
        local room, typedRoom = ExtraCount(rule) < MAX_EXTRA_CONDITIONS, #(rule.logicConditions or {}) < 8
        local function canAdd(kind)
            if not TypedConditionRoom(rule, kind) then return false end
            if logic ~= "AND" or kind == "auraTime" then return typedRoom end
            local group = kind == "resource" and "resourceConditions"
                or (kind == "targetHealth" or kind == "playerHealth") and "healthConditions" or kind == "stacks" and "stackConditions"
            if group then return #(rule[group] or {}) < 8 end
            return rule[kind] == nil or typedRoom
        end
        local choices = {
            {value = "aura", label = "Aura", enabled = room},
            {value = "spellCooldown", label = "Spell cooldown", enabled = room, tooltipTitle = "Spell cooldown", reason = spellCooldownHelp},
            {value = "comboPoints", label = "Combo points", enabled = canAdd("comboPoints")},
            {value = "resource", label = "Resources", enabled = canAdd("resource")},
            {value = "targetHealth", label = "Enemy health", enabled = canAdd("targetHealth")},
            {value = "playerHealth", label = "Self health", enabled = canAdd("playerHealth")},
            {value = "stacks", label = "Aura stacks", enabled = canAdd("stacks"), tooltipTitle = "Aura stacks", reason = stackHelp},
            {value = "auraTime", label = "Aura time remaining", enabled = canAdd("auraTime"), tooltipTitle = "Aura time remaining", reason = auraTimeHelp},
            {value = "targetCasting", label = "Target is casting", enabled = canAdd("targetCasting")},
        }
        if SH.IsShaman and SH.IsShaman() then choices[#choices + 1] = {value = "totemCondition", label = "Totem conditions", enabled = canAdd("totemCondition")} end
        if SH.IsHunter and SH.IsHunter() then choices[#choices + 1] = {value = "hawkCount", label = "Hawk conditions", enabled = canAdd("hawkCount")} end
        if SH.rootDB.customConditionsEnabled then choices[#choices + 1] = {value = "customCondition", label = "Custom Conditions", enabled = canAdd("customCondition")} end
        ChoiceMenu(ui, owner, choices, nil, function(kind)
            if beforeAdd then beforeAdd() end
            if kind == "aura" or kind == "spellCooldown" then
                if logic == "OR" and not rule.useOr then
                    rule.useOr, rule.orAura, rule.orCondition = true, rule.orAura or "", rule.orCondition or "present"
                    rule.orAuraSource = kind == "spellCooldown" and "cooldown" or "tracker"
                    DraftChanged(ui)
                    RefreshRows(ui)
                    RevealEditorRegion(ui, 218, 86, ui.rows[ui.selectedIndex].orAura)
                else AddExtraCondition(ui, logicGroups[logic], kind == "spellCooldown" and "cooldown" or "tracker") end
            elseif logic ~= "AND" or not AddLegacyAndCondition(ui, kind) then AddLogicCondition(ui, logic, kind) end
            if afterAdd then afterAdd() end
        end)
    end
    if forcedLogic then chooseLogic(forcedLogic)
    else ChoiceMenu(ui, owner, {
        {value = "AND", label = "AND"}, {value = "OR", label = "OR"}, {value = "NOT", label = "NOT"},
    }, nil, chooseLogic) end
end

local function DiagramEnabled()
    return SH.rootDB and SH.rootDB.functionBlockDiagramsEnabled == true and SH.Diagram ~= nil and SH.DiagramUI ~= nil
end

local DiagramEditor = {}

-- The diagram uses the same controls as Fields. A fixed scroll window exposes
-- only the selected region of that row inside the expanded block.
function DiagramEditor.Region(ui, selection)
    local row, rule, key = ui.rows[ui.selectedIndex], ui.draft[ui.selectedIndex], selection.key
    if not row or not rule then return end
    if key == "protectChannels" then return 0, 60 end
    if key == "action" then return 0, 124, row.customRuleAction and row.customRuleText or row.spell end
    if key == "primary" then
        local card = rule.primaryCondition and row.primaryTypedRows and row.primaryTypedRows[1]
        local focus = card and (card.aura:IsShown() and card.aura or card.percent:IsShown() and card.percent or card.value:IsShown() and card.value or card.custom:IsShown() and card.custom)
        return 132, row.primaryBottom - 132, focus or (rule.condition ~= "always" and row.aura or nil)
    elseif key == "or" and rule.useOr then return row.primaryBottom, 86, row.orAura end
    for _, collection in ipairs({"primaryTypedRows", "conditionRows", "resourceRows", "healthRows", "stackRows", "logicRows"}) do
        for _, entry in ipairs(row[collection] or {}) do
            if entry.key == key and entry:IsShown() then
                local focus
                for _, field in ipairs({"aura", "percent", "value", "custom"}) do
                    local widget = entry[field]
                    if widget and widget:IsShown() then focus = widget; break end
                end
                return entry.top, entry:GetHeight(), focus
            end
        end
    end
    if key == "comboPoints" and rule.comboPoints then return row.comboTop, 86
    elseif key == "hawkCount" and rule.hawkCount then return row.hawkTop, 86
    elseif key == "customCondition" and rule.customCondition ~= nil then return row.macroTop, 84, row.customCondition
    elseif key == "targetCasting" and rule.targetCasting then return row.targetCastingPanel.top, row.targetCastingPanel:GetHeight()
    elseif key == "totemCondition" and rule.totemCondition then return row.totemPanel.top, row.totemPanel:GetHeight()
    elseif key == "manualCooldown" then return row.manualCooldownTop, 30, row.manualCooldownSeconds
    elseif key == "cooldown" then return row.cooldownTop, 30
    elseif key == "pingDelay" then return row.pingDelayTop, 30, row.pingDelayMS
    elseif key == "skipIfImmune" then return row.skipIfImmuneTop, 30
    elseif key == "skipIfNotCasted" then return row.manualCooldownTop, 30
    elseif key == "modifiers" or key == "skipModifier" or key == "priorityModifier" then
        ui.castingViews[rule] = ui.castingViews[rule] or {}
        ui.castingViews[rule].modifiers = true
        RefreshCastingOptions(ui)
        return row.modifiersPanel and row.modifiersPanel.top or row.optionsTop, 130
    elseif key == "settings" then
        local top = row.pingDelayTop - 28
        return top, row:GetHeight() - top
    elseif key == "count" or key == "castCount" or key == "oncePerProc" or key == "stopCasting" or key == "stopWhenInvalid"
        or key == "skipOutOfRange" or key == "outOfCombatOnly" or key == "inCombatOnly" or key == "advanceOnToggle" then
        return row.optionsTop, row.optionsBody:GetHeight(), (key == "count" or key == "castCount") and row.castCount or nil
    end
end

function DiagramEditor.Unmount(ui)
    local row = ui.diagramMountedRow
    if row then
        ClearRowFocus(row)
        if ui.diagramRegionScroll then ui.diagramRegionScroll:SetScrollChild(ui.diagramEmptyChild) end
        row:SetParent(ui.editorBody)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, 0)
        row:SetFrameLevel(ui.editorBody:GetFrameLevel() + 1)
        row:SetShown(row.index == ui.selectedIndex and ui.draft[row.index] ~= nil)
        ui.diagramMountedRow = nil
    end
    if ui.diagramRegionScroll then ui.diagramRegionScroll:Hide() end
    if ui.diagramProtectChannels then ui.diagramProtectChannels:Hide(); ui.diagramProtectChannels.label:Hide() end
end

function DiagramEditor.Mount(ui, host, selection, top, height)
    if selection.key == "protectChannels" then
        if not ui.diagramProtectChannels then
            ui.diagramProtectChannels = CheckBox(host, "Protect channels", 14, -8, "Protect channels",
                "Check this to keep channels from being interrupted. Prepare applies the change.", function(value)
                    ActiveRotation(ui).db.preventClipping = value
                    ui.preventClipping:SetChecked(value)
                    DraftChanged(ui)
                end)
        end
        ui.diagramProtectChannels:SetParent(host)
        ui.diagramProtectChannels:SetChecked(ActiveRotation(ui).db.preventClipping ~= false)
        ui.diagramProtectChannels:Show(); ui.diagramProtectChannels.label:Show()
        return
    end
    local scroll = ui.diagramRegionScroll
    if not scroll then
        scroll = CreateFrame("ScrollFrame", nil, host)
        ui.diagramRegionScroll = scroll
        ui.diagramEmptyChild = CreateFrame("Frame", nil, scroll)
        ui.diagramEmptyChild:SetSize(1, 1)
        scroll:EnableMouseWheel(false)
    end
    scroll:SetParent(host)
    scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetSize(686, height)
    local row = ui.rows[ui.selectedIndex]
    ui.diagramMountedRow = row
    row:SetParent(scroll)
    scroll:SetScrollChild(row)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, 0)
    row:SetFrameLevel(host:GetFrameLevel() + 2)
    row:Show(); scroll:Show()
    scroll:UpdateScrollChildRect()
    scroll:SetHorizontalScroll(14)
    scroll:SetVerticalScroll(top)
end

function DiagramEditor.Spec(ui, graph)
    local selection = ui.diagramSelection
    if not selection or selection.rule ~= ui.draft[ui.selectedIndex] then
        ui.diagramSelection = nil
        return
    end
    local top, height = DiagramEditor.Region(ui, selection)
    if not top then ui.diagramSelection = nil; return end
    local chosen
    for _, node in ipairs(graph.nodes or {}) do
        local key = node.conditionKey
        if key == "settings" and node.settingField then key = node.settingField end
        if key == selection.key and node.editable ~= false then
            chosen = node
            if node.kind ~= "not" then break end
        end
    end
    if not chosen then
        chosen = {id = "inline-draft", kind = "condition", title = selection.key == "settings" and "Other casting options" or "Edit condition",
            text = "Edit this draft below. Prepare applies your changes.", ruleIndex = ui.selectedIndex,
            conditionKey = selection.key, editable = true}
        graph.nodes[#graph.nodes + 1] = chosen
    end
    -- Keep the host identity stable while a partially typed name changes the
    -- graph's validation or expression shape. Never recreate the focused input.
    local oldID, stableID = chosen.id, "inline-selected"
    chosen.id = stableID
    for _, edge in ipairs(graph.edges or {}) do
        if edge.from == oldID then edge.from = stableID end
        if edge.to == oldID then edge.to = stableID end
    end
    for _, node in ipairs(graph.nodes or {}) do
        for i, input in ipairs(node.inputs or {}) do if input == oldID then node.inputs[i] = stableID end end
    end
    if graph.rootID == oldID then graph.rootID = stableID end
    if graph.actionID == oldID then graph.actionID = stableID end
    return {nodeID = stableID, key = selection, width = 686, height = height,
        mount = function(host) DiagramEditor.Mount(ui, host, selection, top, height) end,
        refresh = function(host)
            if ui.diagramMountedRow then
                ui.diagramRegionScroll:SetSize(686, height)
                ui.diagramRegionScroll:UpdateScrollChildRect()
                ui.diagramRegionScroll:SetVerticalScroll(top)
            elseif selection.key == "protectChannels" then
                ui.diagramProtectChannels:SetChecked(ActiveRotation(ui).db.preventClipping ~= false)
            end
        end,
        unmount = function() DiagramEditor.Unmount(ui) end}
end

local function DiagramFocus(ui, node)
    if node.editable == false then return end
    local index = tonumber(node.ruleIndex) or ui.selectedIndex
    if index < 1 or index > #ui.draft then return end
    ui.advancedPage:Hide(); ui.rotationPage:Show()
    ui.ruleDiagramMode = true
    if index ~= ui.selectedIndex then SelectRule(ui, index) end
    local key = node.conditionKey or "action"
    if key == "settings" and node.settingField then key = node.settingField end
    local selection = {rule = ui.draft[index], key = key}
    local top, _, focus = DiagramEditor.Region(ui, selection)
    if not top then return end
    ClearRowFocus(ui.rows[index])
    ui.diagramSelection = selection
    RefreshRuleDiagram(ui)
    if focus and focus:IsVisible() and focus:IsEnabled() then focus:SetFocus() end
    local view = ui.ruleDiagram
    local position = view and view.positions and view.positions["inline-selected"]
    if position then
        -- Expose the full 686-pixel editor, including its Remove button. The
        -- row's unused outer margins are clipped, not its controls.
        local x = math.max(0, position.x + 10)
        local y = math.max(0, position.y - 5)
        view.scroll:SetHorizontalScroll(x)
        view.horizontal:SetValue(x)
        view.scroll:SetVerticalScroll(y)
        if view.scroll.ScrollBar then view.scroll.ScrollBar:SetValue(y) end
    end
end

RefreshRuleDiagram = function(ui)
    if not ui.ruleDiagramToolbar then return end
    local enabled = DiagramEnabled()
    local rule = ui.draft[ui.selectedIndex]
    if enabled and ui.ruleDiagramMode == nil then ui.ruleDiagramMode = true end
    local diagram = enabled and ui.ruleDiagramMode == true and rule ~= nil
    ui.ruleDiagramToolbar:SetShown(enabled)
    ui.fieldsTab:SetShown(enabled)
    ui.diagramTab:SetShown(enabled)
    ui.ruleDiagramPanel:SetShown(diagram)
    ui.editorScroll:SetShown(not diagram)
    ui.editorScroll:ClearAllPoints()
    ui.editorScroll:SetPoint("TOPLEFT", 0, enabled and -36 or 0)
    ui.editorScroll:SetSize(714, enabled and 464 or 500)
    ui.fieldsTab:SetEnabled(rule ~= nil and diagram)
    ui.diagramTab:SetEnabled(rule ~= nil and not diagram)
    ui.ruleDiagramTitle:SetText(rule and ("Rule " .. ui.selectedIndex .. (diagram and " - diagram" or " - settings")) or "Add a rule to begin")
    if not diagram then
        ui.diagramCloseBlock:Hide()
        if ui.ruleDiagram and ui.ruleDiagram.ClearEditor then ui.ruleDiagram:ClearEditor() end
        DiagramEditor.Unmount(ui)
        ui.diagramSelection = nil
        return
    end
    if not ui.ruleDiagram then
        ui.ruleDiagram = SH.DiagramUI.Create(ui.ruleDiagramPanel, 714, 382)
        ui.ruleDiagram:SetPoint("TOPLEFT", 0, -43)
    end
    local protect = ActiveRotation(ui).db.preventClipping ~= false
    local ok, graph = pcall(SH.Diagram.BuildRule, rule, ui.selectedIndex, {
        preventClipping = protect,
        resolveName = function(value)
            local id = tonumber(value)
            if id and C_Spell and C_Spell.GetSpellInfo then
                local success, info = pcall(C_Spell.GetSpellInfo, id)
                if success and type(info) == "table" and type(info.name) == "string" then return info.name end
            end
            return tostring(value or "")
        end,
        resolveRankLabel = function(value, rankID)
            local id = tonumber(rankID) or tonumber(value)
            if not id then return nil end
            for _, choice in ipairs(RankChoices({spell = value, rankID = rankID})) do
                if choice.id == id then return choice.label end
            end
            return "Selected ID: " .. id
        end,
    })
    if not ok then
        graph = {mode = "rule", nodes = {{id = "draft-error", kind = "warning", title = "Check this rule", text = "Open the rule settings to finish this draft.",
            ruleIndex = ui.selectedIndex, conditionKey = "action", editable = true}}, edges = {}}
    end
    ui.ruleDiagram:Render(graph, function(node) DiagramFocus(ui, node) end, DiagramEditor.Spec(ui, graph))
    ui.diagramCloseBlock:SetShown(ui.diagramSelection ~= nil)
end

CreateRuleDiagramControls = function(ui)
    local toolbar = CreateFrame("Frame", nil, ui.editor)
    ui.ruleDiagramToolbar = toolbar
    toolbar:SetPoint("TOPLEFT", 0, 0)
    toolbar:SetSize(714, 36)
    toolbar:SetFrameLevel(ui.editor:GetFrameLevel() + 6)
    ui.ruleDiagramTitle = Label(toolbar, "", "GameFontNormal", accent)
    ui.ruleDiagramTitle:SetPoint("TOPLEFT", 14, -10)
    local function changeView(diagram)
        if ui.choiceMenu then ui.choiceMenu:Hide() end
        local row = ui.rows[ui.selectedIndex]
        if row then ClearRowFocus(row) end
        ui.ruleDiagramMode = diagram == true
        RefreshRuleDiagram(ui)
        RefreshEditorScroll(ui)
    end
    ui.ShowRuleDiagram = changeView
    ui.OpenDiagramNode = function(node) DiagramFocus(ui, node) end
    ui.fieldsTab = Button(toolbar, "Fields", 100, 25)
    ui.fieldsTab:SetPoint("TOPRIGHT", -125, -5)
    ui.fieldsTab:SetScript("OnClick", function() changeView(false) end)
    ui.diagramTab = Button(toolbar, "Diagram", 100, 25)
    ui.diagramTab:SetPoint("TOPRIGHT", -14, -5)
    ui.diagramTab:SetScript("OnClick", function() changeView(true) end)
    local panel = CreateFrame("Frame", nil, ui.editor)
    ui.ruleDiagramPanel = panel
    panel:SetPoint("TOPLEFT", 0, -36)
    panel:SetSize(714, 464)
    ui.diagramEditRule = Button(panel, "Edit spell / target", 155, 26)
    ui.diagramEditRule:SetPoint("TOPLEFT", 12, -6)
    ui.diagramEditRule:SetScript("OnClick", function() DiagramFocus(ui, {conditionKey = "action"}) end)
    ui.diagramSettings = Button(panel, "Casting options", 168, 26)
    ui.diagramSettings:SetPoint("TOPRIGHT", -12, -6)
    ui.diagramSettings:SetScript("OnClick", function() DiagramFocus(ui, {conditionKey = "settings"}) end)
    for index, spec in ipairs({{"AND", "diagramAddAnd"}, {"OR", "diagramAddOr"}, {"NOT", "diagramAddNot"}}) do
        local logic = spec[1]
        local button = Button(panel, "+ " .. logic, 90, 26)
        ui[spec[2]] = button
        button:SetPoint("TOPLEFT", 181 + (index - 1) * 103, -6)
        button:SetScript("OnClick", function(self)
            local previous = {}
            AddConditionMenu(ui, self, logic, function()
                for _, entry in ipairs(SH.Model.ConditionEntries(ui.draft[ui.selectedIndex])) do previous[entry.key] = true end
            end, function()
                for _, entry in ipairs(SH.Model.ConditionEntries(ui.draft[ui.selectedIndex])) do
                    if not previous[entry.key] then DiagramFocus(ui, {conditionKey = entry.key}); return end
                end
            end)
        end)
    end
    local help = Label(panel, "Click a block to edit it here. Add AND, OR, or NOT above. Prepare applies the draft.", "GameFontHighlightSmall")
    help:SetPoint("BOTTOMLEFT", 14, 8)
    help:SetWidth(540)
    help:SetWordWrap(true)
    ui.diagramCloseBlock = Button(panel, "Close block", 114, 25)
    ui.diagramCloseBlock:SetPoint("BOTTOMRIGHT", -12, 5)
    ui.diagramCloseBlock:SetScript("OnClick", function()
        if ui.choiceMenu then ui.choiceMenu:Hide() end
        ui.diagramSelection = nil
        RefreshRuleDiagram(ui)
        local view = ui.ruleDiagram
        if view and view.scroll then
            view.scroll:SetVerticalScroll(0)
            if view.scroll.ScrollBar then view.scroll.ScrollBar:SetValue(0) end
            view.horizontal:SetValue(0)
        end
    end)
    ui.diagramCloseBlock:Hide()
    toolbar:Hide()
    panel:Hide()
end

RefreshInlineConditions = function(ui, row, rule, top)
    row.conditionRows = row.conditionRows or {}
    local index = 0
    for _, descriptor in ipairs(SH.Model.ConditionEntries(rule)) do
        if extraLabels[descriptor.group] then
            index = index + 1
            local condition = rule[descriptor.group][descriptor.index]
            local entry = row.conditionRows[index]
            if not entry then
                entry = CreateFrame("Frame", nil, row, "BackdropTemplate")
                entry:SetSize(686, 76)
                Skin(entry, { 0.075, 0.105, 0.13, 1 }, { 0.15, 0.2, 0.25, 1 })
                entry.title = Label(entry, "", "GameFontNormal", accent)
                entry.title:SetPoint("TOPLEFT", 10, -8)
                entry.source = Button(entry, "", 154, 25)
                entry.source:SetPoint("TOPLEFT", 10, -35)
                MarkDropdown(entry.source)
                Tooltip(entry.source, "Condition source", extraConditionSourceHelp)
                entry.condition = Button(entry, "", 168, 25)
                entry.condition:SetPoint("TOPLEFT", 170, -35)
                MarkDropdown(entry.condition)
                entry.aura = EditBox(entry, 248)
                entry.aura:SetPoint("TOPLEFT", 347, -35)
                entry.auraLabel = Label(entry, "", "GameFontNormalSmall", { 0.76, 0.8, 0.84 })
                entry.auraLabel:SetPoint("TOPLEFT", 347, -9)
                Tooltip(entry.aura, function()
                    return conditionInputLabels[entry.item and entry.item.auraSource] or conditionInputLabels.tracker
                end, function()
                    return auraInputHelp[entry.item and entry.item.auraSource] or auraInputHelp.tracker
                end)
                Tooltip(entry.condition, "Condition state", function()
                    if entry.item and entry.item.auraSource == "cooldown" then return spellCooldownHelp end
                    return "Choose whether the selected aura, buff, or debuff must be present or missing."
                end)
                entry.remove = Button(entry, "Remove", 73, 25)
                entry.remove:SetPoint("TOPLEFT", 603, -35)
                entry.source:SetScript("OnClick", function(self)
                    local current = ui.draft[row.index]
                    local item = current[entry.group][entry.entryIndex]
                    ChoiceMenu(ui, self, Choices(extraConditionSources, auraSourceLabels), item.auraSource, function(value)
                        item.auraSource = value
                        local clearedCount = value == "cooldown" and ClearCountAttachment(current, entry.key)
                        if not HasAuraConditions(current) then current.stopWhenInvalid = false end
                        DraftChanged(ui)
                        RefreshRows(ui)
                        if clearedCount then ShowResult(ui, false, "This condition now checks a spell cooldown, so its cast count was cleared.") end
                    end)
                end)
                entry.condition:SetScript("OnClick", function(self)
                    local item = ui.draft[row.index][entry.group][entry.entryIndex]
                    local labels = conditionLabelsBySource[item.auraSource] or conditionLabels
                    ChoiceMenu(ui, self, Choices(auraConditions, labels), item.condition, function(value)
                        item.condition = value
                        if not CanStopCast(ui.draft[row.index]) then ui.draft[row.index].stopCasting = false end
                        DraftChanged(ui)
                        RefreshRows(ui)
                    end)
                end)
                entry.aura:SetScript("OnTextChanged", function(self, userInput)
                    if userInput and not ui.loadingRows then
                        ui.draft[row.index][entry.group][entry.entryIndex].aura = self:GetText()
                        DraftChanged(ui)
                    end
                end)
                entry.remove:SetScript("OnClick", function()
                    if ui.choiceMenu then ui.choiceMenu:Hide() end
                    entry.aura:ClearFocus()
                    local current = ui.draft[row.index]
                    local removedTitle = ConditionTitle(ConditionEntry(current, entry.key))
                    local clearedCount = RemoveCountCondition(current, entry.group, entry.entryIndex)
                    table.remove(current[entry.group], entry.entryIndex)
                    if not CanStopCast(current) then current.stopCasting = false end
                    if not HasAuraConditions(current) then current.stopWhenInvalid = false end
                    DraftChanged(ui)
                    RefreshRows(ui)
                    if clearedCount then
                        ShowResult(ui, false, removedTitle .. " was removed, so its cast count was cleared.")
                    end
                end)
                row.conditionRows[index] = entry
            end
            if entry.item ~= condition then entry.aura:ClearFocus() end
            entry.item = condition
            entry.group, entry.entryIndex, entry.displayIndex = descriptor.group, descriptor.index, index
            entry.key, entry.top = descriptor.key, top
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", 14, -top)
            local hint = descriptor.group == "andConditions" and "must also match"
                or (descriptor.group == "orConditions" and "may match instead of IF" or "do not cast when this matches")
            entry.title:SetText(ConditionTitle(descriptor) .. " - " .. hint)
            entry.source:SetText(auraSourceLabels[condition.auraSource] or "Tracked aura")
            entry.auraLabel:SetText(conditionInputLabels[condition.auraSource] or conditionInputLabels.tracker)
            local labels = conditionLabelsBySource[condition.auraSource] or conditionLabels
            entry.condition:SetText(labels[condition.condition] or labels.present)
            if entry.aura:GetText() ~= (condition.aura or "") then entry.aura:SetText(condition.aura or "") end
            entry:Show()
            top = top + 82
        end
    end
    for i = index + 1, #row.conditionRows do
        row.conditionRows[i].aura:ClearFocus()
        row.conditionRows[i].item = nil
        row.conditionRows[i]:Hide()
    end
    return top
end

RefreshResourceConditions = function(ui, row, rule, top)
    row.resourceRows = row.resourceRows or {}
    local index = 0
    for _, descriptor in ipairs(SH.Model.ConditionEntries(rule)) do
        if descriptor.group == "resourceConditions" then
            index = index + 1
            local condition = rule.resourceConditions[descriptor.index]
            local values = type(condition) == "table" and condition or {}
            local entry = row.resourceRows[index]
            if not entry then
                entry = CreateFrame("Frame", nil, row, "BackdropTemplate")
                entry:SetSize(686, 96)
                Skin(entry, { 0.075, 0.105, 0.13, 1 }, { 0.15, 0.2, 0.25, 1 })
                entry.title = Label(entry, "", "GameFontNormal", accent)
                entry.title:SetPoint("TOPLEFT", 13, -9)
                entry.resource = Button(entry, "Mana", 165, 25)
                entry.resource:SetPoint("TOPLEFT", 13, -35)
                MarkDropdown(entry.resource)
                entry.operator = Button(entry, "Below (<)", 218, 25)
                entry.operator:SetPoint("TOPLEFT", 186, -35)
                MarkDropdown(entry.operator)
                entry.percent = EditBox(entry, 80)
                entry.percent:SetPoint("TOPLEFT", 421, -35)
                entry.percent:SetMaxLetters(8)
                entry.percentLabel = Label(entry, "%", "GameFontHighlight")
                entry.percentLabel:SetPoint("TOPLEFT", 509, -42)
                entry.hint = Label(entry, "", "GameFontHighlightSmall")
                entry.hint:SetPoint("TOPLEFT", 13, -70)
                entry.hint:SetWidth(660)
                entry.remove = Button(entry, "Remove", 70, 22)
                entry.remove:SetPoint("TOPLEFT", 604, -8)
                Tooltip(entry.resource, "Player resource", "Check your own mana, rage, or energy, regardless of the spell's Cast on target. This condition must match for every IF / OR alternative. No aura tracker is needed.")
                Tooltip(entry.percent, "Resource percentage", "Enter a whole percentage from 0 to 100. For example, Mana below 20% or Energy at least 40%.")
                local function item()
                    local current = ui.draft[row.index]
                    if not current or type(current.resourceConditions) ~= "table" then return end
                    if type(current.resourceConditions[entry.entryIndex]) ~= "table" then
                        current.resourceConditions[entry.entryIndex] = {}
                    end
                    return current.resourceConditions[entry.entryIndex]
                end
                entry.resource:SetScript("OnClick", function(self)
                    local current = item()
                    if not current then return end
                    ChoiceMenu(ui, self, Choices(resourceTypes, resourceLabels), current.resource, function(value)
                        current.resource = value
                        DraftChanged(ui)
                        RefreshRows(ui)
                    end)
                end)
                entry.operator:SetScript("OnClick", function(self)
                    local current = item()
                    if not current then return end
                    ChoiceMenu(ui, self, Choices(resourceOperators, resourceOperatorLabels), current.operator, function(value)
                        current.operator = value
                        DraftChanged(ui)
                        RefreshRows(ui)
                    end)
                end)
                entry.percent:SetScript("OnTextChanged", function(self, userInput)
                    if userInput and not ui.loadingRows then
                        local current = item()
                        if not current then return end
                        current.percent = DraftCount(self:GetText()) or ""
                        DraftChanged(ui)
                    end
                end)
                entry.remove:SetScript("OnClick", function()
                    if ui.choiceMenu then ui.choiceMenu:Hide() end
                    entry.percent:ClearFocus()
                    local current = ui.draft[row.index]
                    if not current or type(current.resourceConditions) ~= "table" then return end
                    local clearedCount = RemoveCountCondition(current, "resourceConditions", entry.entryIndex)
                    table.remove(current.resourceConditions, entry.entryIndex)
                    if #current.resourceConditions == 0 then current.resourceConditions = nil end
                    DraftChanged(ui)
                    RefreshRows(ui)
                    if clearedCount then ShowResult(ui, false, "The unsupported resource cast count was cleared with its condition.") end
                end)
                row.resourceRows[index] = entry
            end
            if entry.item ~= condition then entry.percent:ClearFocus() end
            entry.item, entry.entryIndex, entry.key, entry.top = condition, descriptor.index, descriptor.key, top
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", 14, -top)
            entry.title:SetText(ConditionTitle(descriptor) .. " - Player resource")
            entry.resource:SetText(resourceLabels[values.resource] or "Choose resource")
            entry.operator:SetText(resourceOperatorLabels[values.operator] or "Choose comparison")
            local percent = values.percent == nil and "" or tostring(values.percent)
            if entry.percent:GetText() ~= percent then entry.percent:SetText(percent) end
            local valid = type(values.percent) == "number" and values.percent >= 0 and values.percent <= 100 and values.percent % 1 == 0
            entry.hint:SetText(valid and "Your resource; must also match for every alternative." or "Enter a whole percentage from 0 to 100.")
            if valid then entry.hint:SetTextColor(0.82, 0.85, 0.9) else entry.hint:SetTextColor(1, 0.57, 0.57) end
            entry:Show()
            top = top + 104
        end
    end
    for i = index + 1, #row.resourceRows do
        row.resourceRows[i].percent:ClearFocus()
        row.resourceRows[i].item = nil
        row.resourceRows[i]:Hide()
    end
    return top
end

RefreshHealthConditions = function(ui, row, rule, top)
    row.healthRows = row.healthRows or {}
    local index = 0
    for _, descriptor in ipairs(SH.Model.ConditionEntries(rule)) do
        if descriptor.group == "healthConditions" then
            index = index + 1
            local condition = rule.healthConditions[descriptor.index]
            local values = type(condition) == "table" and condition or {}
            local entry = row.healthRows[index]
            if not entry then
                entry = CreateFrame("Frame", nil, row, "BackdropTemplate")
                entry:SetSize(686, 96)
                Skin(entry, { 0.075, 0.105, 0.13, 1 }, { 0.15, 0.2, 0.25, 1 })
                entry.title = Label(entry, "", "GameFontNormal", accent)
                entry.title:SetPoint("TOPLEFT", 13, -9)
                entry.operator = Button(entry, "Below (<)", 218, 25)
                entry.operator:SetPoint("TOPLEFT", 13, -35)
                MarkDropdown(entry.operator)
                entry.percent = EditBox(entry, 80)
                entry.percent:SetPoint("TOPLEFT", 249, -35)
                entry.percent:SetMaxLetters(8)
                entry.percentLabel = Label(entry, "%", "GameFontHighlight")
                entry.percentLabel:SetPoint("TOPLEFT", 337, -42)
                entry.hint = Label(entry, "", "GameFontHighlightSmall")
                entry.hint:SetPoint("TOPLEFT", 13, -70)
                entry.hint:SetWidth(660)
                entry.remove = Button(entry, "Remove", 70, 22)
                entry.remove:SetPoint("TOPLEFT", 604, -8)
                Tooltip(entry.operator, function() return HealthLabel(type(entry.item) == "table" and entry.item.unit) end, function()
                    if type(entry.item) == "table" and entry.item.unit == "player" then
                        return "Check your own health, regardless of the spell's Cast on target. Every Self health condition must match for every IF / OR alternative. No target or tracker is needed."
                    end
                    return "Check your current living enemy target's health, regardless of the spell's Cast on target. Every Enemy health condition must match for every IF / OR alternative. No tracker is needed. Without a living enemy target, this rule is skipped."
                end)
                Tooltip(entry.percent, function() return HealthLabel(type(entry.item) == "table" and entry.item.unit) .. " percentage" end,
                    "Enter a whole percentage from 0 to 100. Below 20% excludes exactly 20%; At least 20% includes it. Add another health condition for the same unit to set a range.")
                local function item()
                    local current = ui.draft[row.index]
                    if not current or type(current.healthConditions) ~= "table" then return end
                    if type(current.healthConditions[entry.entryIndex]) ~= "table" then
                        current.healthConditions[entry.entryIndex] = {}
                    end
                    return current.healthConditions[entry.entryIndex]
                end
                entry.operator:SetScript("OnClick", function(self)
                    local current = item()
                    if not current then return end
                    ChoiceMenu(ui, self, Choices(resourceOperators, resourceOperatorLabels), current.operator, function(value)
                        current.operator = value
                        DraftChanged(ui)
                        RefreshRows(ui)
                    end)
                end)
                entry.percent:SetScript("OnTextChanged", function(self, userInput)
                    if userInput and not ui.loadingRows then
                        local current = item()
                        if not current then return end
                        current.percent = DraftCount(self:GetText()) or ""
                        DraftChanged(ui)
                    end
                end)
                entry.remove:SetScript("OnClick", function()
                    if ui.choiceMenu then ui.choiceMenu:Hide() end
                    entry.percent:ClearFocus()
                    local current = ui.draft[row.index]
                    if not current or type(current.healthConditions) ~= "table" then return end
                    local clearedCount = RemoveCountCondition(current, "healthConditions", entry.entryIndex)
                    table.remove(current.healthConditions, entry.entryIndex)
                    if #current.healthConditions == 0 then current.healthConditions = nil end
                    DraftChanged(ui)
                    RefreshRows(ui)
                    if clearedCount then ShowResult(ui, false, "The unsupported health cast count was cleared with its condition.") end
                end)
                row.healthRows[index] = entry
            end
            if entry.item ~= condition then entry.percent:ClearFocus() end
            entry.item, entry.entryIndex, entry.key, entry.top = condition, descriptor.index, descriptor.key, top
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", 14, -top)
            entry.title:SetText(ConditionTitle(descriptor) .. " - " .. HealthLabel(values.unit))
            entry.operator:SetText(resourceOperatorLabels[values.operator] or "Choose comparison")
            local percent = values.percent == nil and "" or tostring(values.percent)
            if entry.percent:GetText() ~= percent then entry.percent:SetText(percent) end
            local valid = type(values.percent) == "number" and values.percent >= 0 and values.percent <= 100 and values.percent % 1 == 0
            local hint = values.unit == "player" and "Your own health; no target needed. Must match for every alternative."
                or "Current living enemy target; must match for every alternative."
            entry.hint:SetText(valid and hint or "Enter a whole percentage from 0 to 100.")
            if valid then entry.hint:SetTextColor(0.82, 0.85, 0.9) else entry.hint:SetTextColor(1, 0.57, 0.57) end
            entry:Show()
            top = top + 104
        end
    end
    for i = index + 1, #row.healthRows do
        row.healthRows[i].percent:ClearFocus()
        row.healthRows[i].item = nil
        row.healthRows[i]:Hide()
    end
    return top
end

RefreshStackConditions = function(ui, row, rule, top)
    row.stackRows = row.stackRows or {}
    local index = 0
    for _, descriptor in ipairs(SH.Model.ConditionEntries(rule)) do
        if descriptor.group == "stackConditions" then
            index = index + 1
            local condition = rule.stackConditions[descriptor.index]
            local values = type(condition) == "table" and condition or {}
            local entry = row.stackRows[index]
            if not entry then
                entry = CreateFrame("Frame", nil, row, "BackdropTemplate")
                entry:SetSize(686, 154)
                Skin(entry, { 0.075, 0.105, 0.13, 1 }, { 0.15, 0.2, 0.25, 1 })
                entry.title = Label(entry, "", "GameFontNormal", accent)
                entry.title:SetPoint("TOPLEFT", 13, -9)
                entry.source = Button(entry, "Target debuff", 165, 25)
                entry.source:SetPoint("TOPLEFT", 13, -43)
                MarkDropdown(entry.source)
                entry.auraLabel = Label(entry, "Debuff name or ID", "GameFontNormalSmall", { 0.76, 0.8, 0.84 })
                entry.auraLabel:SetPoint("TOPLEFT", 193, -27)
                entry.aura = EditBox(entry, 480)
                entry.aura:SetPoint("TOPLEFT", 193, -43)
                entry.operator = Button(entry, "Fewer than (<)", 218, 25)
                entry.operator:SetPoint("TOPLEFT", 13, -78)
                MarkDropdown(entry.operator)
                entry.value = EditBox(entry, 80)
                entry.value:SetPoint("TOPLEFT", 249, -78)
                entry.value:SetMaxLetters(8)
                entry.valueLabel = Label(entry, "stacks", "GameFontHighlight")
                entry.valueLabel:SetPoint("TOPLEFT", 337, -85)
                entry.hint = Label(entry, "", "GameFontHighlightSmall")
                entry.hint:SetPoint("TOPLEFT", 13, -113)
                entry.hint:SetWidth(660)
                entry.remove = Button(entry, "Remove", 70, 22)
                entry.remove:SetPoint("TOPLEFT", 604, -8)
                Tooltip(entry.source, "Aura stacks", "Player buff checks your character. Target debuff checks your own debuff on your current enemy, regardless of Cast on. Every stack condition must match for every IF / OR alternative. " .. stackHelp)
                Tooltip(entry.aura, function()
                    return conditionInputLabels[type(entry.item) == "table" and entry.item.auraSource] or "Aura name or ID"
                end, stackHelp)
                Tooltip(entry.operator, "Stack comparison", "Choose how the aura's stack count compares with the number you enter. Equal to includes only that count; Not equal to excludes it.")
                Tooltip(entry.value, "Stack count", "Enter a whole number from 0 to 99. Add another Aura stacks condition to set a range. " .. stackHelp)
                local function item()
                    local current = ui.draft[row.index]
                    if not current or type(current.stackConditions) ~= "table" then return end
                    if type(current.stackConditions[entry.entryIndex]) ~= "table" then
                        current.stackConditions[entry.entryIndex] = {}
                    end
                    return current.stackConditions[entry.entryIndex]
                end
                entry.source:SetScript("OnClick", function(self)
                    local current = item()
                    if not current then return end
                    ChoiceMenu(ui, self, Choices(stackSources, auraSourceLabels), current.auraSource, function(value)
                        current.auraSource = value
                        DraftChanged(ui)
                        RefreshRows(ui)
                    end)
                end)
                entry.operator:SetScript("OnClick", function(self)
                    local current = item()
                    if not current then return end
                    ChoiceMenu(ui, self, Choices(hawkOperators, hawkOperatorLabels), current.operator, function(value)
                        current.operator = value
                        DraftChanged(ui)
                        RefreshRows(ui)
                    end)
                end)
                entry.aura:SetScript("OnTextChanged", function(self, userInput)
                    if userInput and not ui.loadingRows then
                        local current = item()
                        if not current then return end
                        current.aura = self:GetText()
                        DraftChanged(ui)
                    end
                end)
                entry.value:SetScript("OnTextChanged", function(self, userInput)
                    if userInput and not ui.loadingRows then
                        local current = item()
                        if not current then return end
                        current.value = DraftCount(self:GetText()) or ""
                        DraftChanged(ui)
                    end
                end)
                entry.remove:SetScript("OnClick", function()
                    if ui.choiceMenu then ui.choiceMenu:Hide() end
                    entry.aura:ClearFocus()
                    entry.value:ClearFocus()
                    local current = ui.draft[row.index]
                    if not current or type(current.stackConditions) ~= "table" then return end
                    local clearedCount = RemoveCountCondition(current, "stackConditions", entry.entryIndex)
                    table.remove(current.stackConditions, entry.entryIndex)
                    if #current.stackConditions == 0 then current.stackConditions = nil end
                    DraftChanged(ui)
                    RefreshRows(ui)
                    if clearedCount then ShowResult(ui, false, "The unsupported stack cast count was cleared with its condition.") end
                end)
                row.stackRows[index] = entry
            end
            if entry.item ~= condition then entry.aura:ClearFocus(); entry.value:ClearFocus() end
            entry.item, entry.entryIndex, entry.key, entry.top = condition, descriptor.index, descriptor.key, top
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", 14, -top)
            entry.title:SetText(ConditionTitle(descriptor) .. " - Aura stacks")
            entry.source:SetText(auraSourceLabels[values.auraSource] or "Choose source")
            entry.auraLabel:SetText(conditionInputLabels[values.auraSource] or "Aura name or ID")
            entry.operator:SetText(hawkOperatorLabels[values.operator] or "Choose comparison")
            local aura = values.aura == nil and "" or tostring(values.aura)
            if entry.aura:GetText() ~= aura then entry.aura:SetText(aura) end
            local count = values.value == nil and "" or tostring(values.value)
            if entry.value:GetText() ~= count then entry.value:SetText(count) end
            local validCount = type(values.value) == "number" and values.value >= 0 and values.value <= 99 and values.value % 1 == 0
            local problem = not validCount and "Enter a whole stack count from 0 to 99."
                or Trim(values.aura) == "" and "Enter the buff or debuff name or spell ID."
                or not (values.auraSource == "player" or values.auraSource == "target") and "Choose Player buff or Target debuff."
                or not hawkOperatorLabels[values.operator] and "Choose a stack comparison."
            entry.hint:SetText(problem or (stackHelp .. "\nMust match for every IF / OR alternative."))
            if problem then entry.hint:SetTextColor(1, 0.57, 0.57) else entry.hint:SetTextColor(0.82, 0.85, 0.9) end
            entry:Show()
            top = top + 162
        end
    end
    for i = index + 1, #row.stackRows do
        row.stackRows[i].aura:ClearFocus()
        row.stackRows[i].value:ClearFocus()
        row.stackRows[i].item = nil
        row.stackRows[i]:Hide()
    end
    return top
end

RefreshLogicConditions = function(ui, row, rule, top, primary)
    local rowsKey = primary and "primaryTypedRows" or "logicRows"
    row[rowsKey] = row[rowsKey] or {}
    local rows = row[rowsKey]
    local count = 0
    for _, descriptor in ipairs(SH.Model.ConditionEntries(rule)) do
        if (primary and descriptor.key == "primary" and rule.primaryCondition ~= nil)
            or (not primary and descriptor.group == "logicConditions") then
            count = count + 1
            local item = primary and rule.primaryCondition or rule.logicConditions[descriptor.index]
            local values = type(item) == "table" and item or {}
            local entry = rows[count]
            if not entry then
                entry = CreateFrame("Frame", nil, row, "BackdropTemplate")
                entry:SetWidth(686)
                Skin(entry, {0.075, 0.105, 0.13, 1}, {0.15, 0.2, 0.25, 1})
                entry.title = Label(entry, "", "GameFontNormal", accent)
                entry.title:SetPoint("TOPLEFT", 13, -9)
                entry.title:SetWidth(480)
                entry.logic = Button(entry, "", 84, 22)
                entry.logic:SetPoint("TOPLEFT", 510, -8)
                MarkDropdown(entry.logic)
                entry.remove = Button(entry, "Remove", 70, 22)
                entry.remove:SetPoint("TOPLEFT", 604, -8)
                entry.source = Button(entry, "", 165, 25)
                entry.resource = Button(entry, "", 165, 25)
                entry.operator = Button(entry, "", 218, 25)
                entry.choiceValue = Button(entry, "", 80, 25)
                entry.element = Button(entry, "", 165, 25)
                entry.mode = Button(entry, "", 480, 25)
                for _, button in ipairs({entry.source, entry.resource, entry.operator, entry.choiceValue, entry.element, entry.mode}) do MarkDropdown(button) end
                entry.aura = EditBox(entry, 480)
                entry.auraLabel = Label(entry, "", "GameFontNormalSmall", {0.76, 0.8, 0.84})
                entry.auraLabel:SetPoint("TOPLEFT", 193, -27)
                entry.value = EditBox(entry, 80)
                entry.percent = EditBox(entry, 80)
                entry.value:SetMaxLetters(8)
                entry.percent:SetMaxLetters(8)
                entry.custom = EditBox(entry, 660)
                entry.custom:SetMaxLetters(254)
                entry.suffix = Label(entry, "", "GameFontHighlight")
                entry.hint = Label(entry, "", "GameFontHighlightSmall")
                entry.hint:SetSize(660, 44)
                entry.hint:SetJustifyV("TOP")
                local function current()
                    local r = ui.draft[row.index]
                    if not r then return end
                    if primary then return r.primaryCondition end
                    if type(r.logicConditions) == "table" then return r.logicConditions[entry.entryIndex] end
                end
                local function changed()
                    DraftChanged(ui)
                    RefreshRows(ui)
                end
                local function dropdown(widget, fields, labels, field)
                    widget:SetScript("OnClick", function(self)
                        local value = current()
                        if type(value) ~= "table" then return end
                        ChoiceMenu(ui, self, Choices(fields, labels), value[field], function(selected)
                            value[field] = selected
                            changed()
                        end)
                    end)
                end
                dropdown(entry.logic, logicKinds, logicKindLabels, "logic")
                entry.source:SetScript("OnClick", function(self)
                    local value = current()
                    if type(value) ~= "table" then return end
                    local field = value.type == "auraTime" and "unit" or "auraSource"
                    ChoiceMenu(ui, self, Choices(stackSources, auraSourceLabels), value[field], function(selected)
                        value[field] = selected
                        changed()
                    end)
                end)
                dropdown(entry.resource, resourceTypes, resourceLabels, "resource")
                entry.operator:SetScript("OnClick", function(self)
                    local value = current()
                    if type(value) ~= "table" then return end
                    local operators, labels = hawkOperators, hawkOperatorLabels
                    if value.type == "auraTime" then operators, labels = hawkOperators, auraTimeOperatorLabels
                    elseif value.type == "comboPoints" then operators, labels = comboOperators, comboOperatorLabels
                    elseif value.type == "health" or value.type == "resource" then operators, labels = resourceOperators, resourceOperatorLabels end
                    ChoiceMenu(ui, self, Choices(operators, labels), value.operator, function(selected)
                        value.operator = selected
                        changed()
                    end)
                end)
                entry.choiceValue:SetScript("OnClick", function(self)
                    local value = current()
                    if type(value) ~= "table" then return end
                    local choices = {}
                    for i = 0, value.type == "hawkCount" and 2 or 5 do choices[#choices + 1] = {value = i, label = tostring(i)} end
                    ChoiceMenu(ui, self, choices, value.value, function(selected) value.value = selected; changed() end)
                end)
                entry.element:SetScript("OnClick", function(self)
                    local value = current()
                    if type(value) ~= "table" then return end
                    ChoiceMenu(ui, self, Choices(totemElements, totemElementLabels), TotemConditionElement(value.value), function(selected)
                        value.value = TotemConditionMode(selected, TotemConditionMissing(value.value))
                        changed()
                    end)
                end)
                entry.mode:SetScript("OnClick", function(self)
                    local value = current()
                    if type(value) ~= "table" then return end
                    local element = TotemConditionElement(value.value)
                    ChoiceMenu(ui, self, Choices(totemModes[element] or totemModes.fire, totemLabels), value.value,
                        function(selected) value.value = selected; changed() end)
                end)
                for _, field in ipairs({"aura", "percent", "value", "custom"}) do
                    local fieldName = field
                    entry[field]:SetScript("OnTextChanged", function(self, userInput)
                        if not userInput or ui.loadingRows then return end
                        local value = current()
                        if type(value) ~= "table" then return end
                        if fieldName == "custom" then value.value = self:GetText()
                        elseif fieldName == "aura" then value.aura = self:GetText()
                        elseif fieldName == "value" and value.type == "auraTime" then value.seconds = DraftCount(self:GetText()) or ""
                        else value[fieldName] = DraftCount(self:GetText()) or "" end
                        DraftChanged(ui)
                    end)
                end
                entry.remove:SetScript("OnClick", function()
                    if ui.choiceMenu then ui.choiceMenu:Hide() end
                    for _, field in ipairs({entry.aura, entry.percent, entry.value, entry.custom}) do field:ClearFocus() end
                    local r = ui.draft[row.index]
                    if not r or type(r.logicConditions) ~= "table" then return end
                    RemoveCountCondition(r, "logicConditions", entry.entryIndex)
                    table.remove(r.logicConditions, entry.entryIndex)
                    if #r.logicConditions == 0 then r.logicConditions = nil end
                    changed()
                end)
                Tooltip(entry.logic, "Condition logic", "AND must also match. OR may match instead of IF. NOT prevents this rule when its condition matches. Cooldown and other shared settings still apply.")
                Tooltip(entry.aura, "Aura name or ID", function() return entry.item and entry.item.type == "auraTime" and auraTimeHelp or stackHelp end)
                Tooltip(entry.source, "Aura source", "Player buff checks your character. Target debuff checks your own debuff on your current enemy, regardless of Cast on.")
                Tooltip(entry.percent, "Percentage", "Enter a whole percentage from 0 to 100.")
                Tooltip(entry.value, function() return entry.item and entry.item.type == "auraTime" and "Seconds remaining" or "Stack count" end,
                    function() return entry.item and entry.item.type == "auraTime" and "Enter a whole number from 0 to 60. " .. auraTimeHelp
                        or "Enter a whole number from 0 to 99. " .. stackHelp end)
                Tooltip(entry.custom, "Custom Conditions", "Enter a bracketed macro condition such as [harm,nodead]. See Advanced > Custom Conditions examples for the list.")
                rows[count] = entry
            end
            if entry.item ~= item then
                for _, field in ipairs({entry.aura, entry.percent, entry.value, entry.custom}) do field:ClearFocus() end
            end
            entry.item, entry.entryIndex, entry.key, entry.top = item, descriptor.index, descriptor.key, top
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", 14, -top)
            local title = values.type == "health" and HealthLabel(values.unit) or logicLabels[values.type] or "Choose condition"
            entry.title:SetText(ConditionTitle(descriptor) .. (primary and "" or " - " .. title))
            entry.title:SetWidth(primary and 410 or 480)
            entry.logic:SetShown(not primary)
            entry.remove:SetShown(not primary)
            entry.logic:SetText(values.logic or "Choose")
            for _, widget in ipairs({entry.source, entry.resource, entry.operator, entry.choiceValue, entry.element, entry.mode,
                entry.aura, entry.auraLabel, entry.value, entry.percent, entry.custom, entry.suffix}) do
                widget.conditionVisible = false
                widget:ClearAllPoints()
            end
            local function place(widget, x, y)
                widget.conditionVisible = true
                widget:SetPoint("TOPLEFT", x, -y)
                widget:Show()
            end
            local function edit(widget, value)
                local display = value == nil and "" or tostring(value)
                -- A focused field owns its in-progress text and native selection.
                if not widget:HasFocus() and widget:GetText() ~= display then widget:SetText(display) end
            end
            local detail, problem, height, hintY = "", nil, 126, 70
            if values.type == "stacks" or values.type == "auraTime" then
                local timer = values.type == "auraTime"
                local source = timer and values.unit or values.auraSource
                place(entry.source, 13, 43); place(entry.aura, 193, 43); place(entry.auraLabel, 193, 27)
                place(entry.operator, 13, 78); place(entry.value, 249, 78); place(entry.suffix, 337, 85)
                entry.source:SetText(auraSourceLabels[source] or "Choose source")
                entry.auraLabel:SetText(conditionInputLabels[source] or "Aura name or ID")
                entry.operator:SetText((timer and auraTimeOperatorLabels or hawkOperatorLabels)[values.operator] or "Choose comparison")
                entry.suffix:SetText(timer and "seconds remaining" or "stacks")
                edit(entry.aura, values.aura); edit(entry.value, timer and values.seconds or values.value)
                detail, height, hintY = timer and auraTimeHelp or stackHelp, 170, 113
                if Trim(values.aura) == "" then problem = "Enter the buff or debuff name or spell ID." end
                local amount, maximum = timer and values.seconds or values.value, timer and 60 or 99
                if type(amount) ~= "number" or amount < 0 or amount > maximum or amount % 1 ~= 0 then
                    problem = timer and "Enter whole seconds from 0 to 60." or "Enter a whole stack count from 0 to 99."
                end
            elseif values.type == "resource" or values.type == "health" then
                local resource = values.type == "resource"
                if resource then place(entry.resource, 13, 35); entry.resource:SetText(resourceLabels[values.resource] or "Choose resource") end
                place(entry.operator, resource and 186 or 13, 35)
                place(entry.percent, resource and 421 or 249, 35); place(entry.suffix, resource and 509 or 337, 42)
                entry.operator:SetText(resourceOperatorLabels[values.operator] or "Choose comparison")
                entry.suffix:SetText("%")
                edit(entry.percent, values.percent)
                detail = resource and "Your resource, regardless of Cast on."
                    or values.unit == "player" and "Your own health; no target needed." or "Your current living enemy's health, regardless of Cast on."
                if type(values.percent) ~= "number" or values.percent < 0 or values.percent > 100 or values.percent % 1 ~= 0 then problem = "Enter a whole percentage from 0 to 100." end
            elseif values.type == "comboPoints" or values.type == "hawkCount" then
                place(entry.operator, 13, 35); place(entry.choiceValue, 249, 35)
                local labels = values.type == "comboPoints" and comboOperatorLabels or hawkOperatorLabels
                entry.operator:SetText(labels[values.operator] or "Choose comparison")
                entry.choiceValue:SetText(values.value == nil and "Choose" or tostring(values.value))
                detail = values.type == "comboPoints" and "Combo points on your current target." or "Your active Summon Hawk hawks."
            elseif values.type == "totemCondition" then
                place(entry.element, 13, 35); place(entry.mode, 186, 35)
                entry.element:SetText(totemElementLabels[TotemConditionElement(values.value)] or "Choose element")
                entry.mode:SetText(totemLabels[values.value] or "Choose state")
                detail = "Checks your totem in the selected element's slot. Distance does not empty the slot."
            elseif values.type == "customCondition" then
                place(entry.custom, 13, 35); edit(entry.custom, values.value)
                detail = "Use macro conditions such as [harm,nodead]. See Advanced > Custom Conditions examples."
                if Trim(values.value) == "" then problem = "Enter a bracketed macro condition." end
            elseif values.type == "targetCasting" then
                detail, hintY, height = "Checks your current target for a cast or channel, even if it cannot be interrupted.", 35, 94
            end
            -- Hiding an EditBox drops focus. Keep the current type's controls
            -- visible while typing; hide only fields this condition no longer uses.
            for _, widget in ipairs({entry.source, entry.resource, entry.operator, entry.choiceValue, entry.element, entry.mode,
                entry.aura, entry.auraLabel, entry.value, entry.percent, entry.custom, entry.suffix}) do
                if not widget.conditionVisible then widget:Hide() end
            end
            local meaning = values.logic == "OR" and "May match instead of IF; shared AND, NOT and cooldown checks still apply."
                or values.logic == "NOT" and "Skip this rule when this condition matches." or "Must also match alongside IF or an OR alternative."
            if primary then meaning = "The first condition for this rule; added AND and NOT conditions still apply." end
            if values.logic == "OR" and rule.condition == "always" and not rule.primaryCondition then problem = "Choose a conditional IF before using OR." end
            entry.hint:ClearAllPoints()
            entry.hint:SetPoint("TOPLEFT", 13, -hintY)
            entry.hint:SetText((problem or detail) .. "\n" .. meaning)
            if problem then entry.hint:SetTextColor(1, 0.57, 0.57) else entry.hint:SetTextColor(0.82, 0.85, 0.9) end
            entry:SetHeight(height)
            entry:Show()
            top = top + height + 8
        end
    end
    for i = count + 1, #rows do
        local entry = rows[i]
        for _, field in ipairs({entry.aura, entry.percent, entry.value, entry.custom}) do field:ClearFocus() end
        entry.item = nil
        entry:Hide()
    end
    return top
end

RefreshRows = function(ui)
    ui.refreshingRows = true
    ui.loadingRows = true
    for i, rule in ipairs(ui.draft) do
        local row = ui.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, ui.editorBody)
            row:SetSize(714, 500)
            row.primaryPanel = row:CreateTexture(nil, "BACKGROUND")
            row.primaryPanel:SetPoint("TOPLEFT", 14, -132)
            row.primaryPanel:SetSize(686, 78)
            row.primaryPanel:SetColorTexture(0.075, 0.105, 0.13, 1)
            row.primaryTitle = Label(row, "IF / Primary condition", "GameFontNormal", accent)
            row.primaryTitle:SetPoint("TOPLEFT", 27, -143)
            row.primaryType = Button(row, "", 236, 24)
            row.primaryType:SetPoint("TOPLEFT", 450, -140)
            MarkDropdown(row.primaryType)
            row.primaryType:SetScript("OnClick", function(self) PrimaryConditionMenu(ui, row, self) end)
            Tooltip(row.primaryType, "IF condition", "Choose the first condition for this rule. Always has no IF requirement. Added AND and NOT conditions still apply; OR offers another way to match.")
            row.primaryHint = Label(row, "", "GameFontHighlightSmall")
            row.primaryHint:SetPoint("TOPLEFT", 27, -176)
            row.primaryHint:SetSize(650, 28)
            row.settingsTitle = Label(row, "Other casting options", "GameFontNormal", accent)
            row.alternativePanel = row:CreateTexture(nil, "BACKGROUND")
            row.alternativePanel:SetPoint("TOPLEFT", 14, -218)
            row.alternativePanel:SetSize(686, 78)
            row.alternativePanel:SetColorTexture(0.075, 0.105, 0.13, 1)
            row.optionsBody = CreateFrame("Frame", nil, row)
            row.optionsBody:SetPoint("TOPLEFT", 14, -379)
            row.optionsBody:SetSize(686, 126)
            row.castingOptions = Button(row, "+ Casting conditions", 686, 26)
            row.castingOptions:SetPoint("TOPLEFT", 14, -343)
            row.optionsToggle = row.castingOptions
            MarkDropdown(row.castingOptions)
            row.optionsToggle = row.castingOptions
            row.castingOptions:SetScript("OnClick", function(self) AddConditionMenu(ui, self, false) end)
            Tooltip(row.castingOptions, "Add a condition", "Choose AND, OR, or NOT, then choose the kind of condition. Casting controls and Cast Count are always shown below.")
            row.pingDelay = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.pingDelay:SetSize(25, 25)
            row.pingDelayLabel = Label(row, "Ping Delay", "GameFontHighlightSmall")
            row.pingDelayLabel:SetPoint("LEFT", row.pingDelay, "RIGHT", 2, 0)
            row.pingDelayMS = EditBox(row, 64)
            row.pingDelayUnit = Label(row, "ms", "GameFontHighlightSmall")
            row.pingDelayUnit:SetPoint("LEFT", row.pingDelayMS, "RIGHT", 7, 0)
            row.pingDelayHint = Label(row, "1-5000 ms; default 100", "GameFontHighlightSmall", { 0.69, 0.75, 0.8 })
            row.pingDelayHint:SetPoint("LEFT", row.pingDelayUnit, "RIGHT", 16, 0)
            local pingDelayTooltip = "Set a delay in milliseconds if spells with buffs or debuffs are double casting. Enter a whole number from 1 to 5000. Requires this spell's chosen rank on a fixed, visible Blizzard action bar."
            Tooltip(row.pingDelay, "Ping Delay", pingDelayTooltip)
            Tooltip(row.pingDelayMS, "Ping Delay (milliseconds)", pingDelayTooltip)
            row.pingDelay:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                current.pingDelay = self:GetChecked() and true or false
                DraftChanged(ui)
                RefreshRows(ui)
            end)
            row.pingDelayMS:SetScript("OnTextChanged", function(self, userInput)
                local current = ui.draft[row.index]
                if userInput and not ui.loadingRows and current.pingDelay then
                    current.pingDelayMS = DraftPingDelayMS(self:GetText())
                    DraftChanged(ui)
                end
            end)
            row.manualCooldown = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.manualCooldown:SetSize(25, 25)
            row.manualCooldownLabel = Label(row, "Manual cooldown", "GameFontHighlightSmall")
            row.manualCooldownLabel:SetPoint("LEFT", row.manualCooldown, "RIGHT", 2, 0)
            row.manualCooldownSeconds = EditBox(row, 82)
            row.manualCooldownUnit = Label(row, "seconds", "GameFontHighlightSmall")
            row.manualCooldownUnit:SetPoint("LEFT", row.manualCooldownSeconds, "RIGHT", 7, 0)
            row.manualCooldownHint = Label(row, "0.001 to 86400", "GameFontHighlightSmall", { 0.69, 0.75, 0.8 })
            row.manualCooldownHint:SetPoint("LEFT", row.manualCooldownUnit, "RIGHT", 16, 0)
            local manualCooldownTooltip = "For cooldown spells with a tracked aura. Enter the spell's cooldown in seconds instead of using a cooldown tracker. The timer starts after a successful cast; tracked aura present/missing conditions still apply. Enter a positive value from 0.001 to 86400, with up to 3 decimal places. Like Ping Delay, this requires the spell's chosen rank on a fixed, visible Blizzard action bar."
            Tooltip(row.manualCooldown, "Manual cooldown", manualCooldownTooltip)
            Tooltip(row.manualCooldownSeconds, "Manual cooldown (seconds)", manualCooldownTooltip)
            row.manualCooldown:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                current.manualCooldown = self:GetChecked() and true or false
                DraftChanged(ui)
                RefreshRows(ui)
            end)
            row.manualCooldownSeconds:SetScript("OnTextChanged", function(self, userInput)
                local current = ui.draft[row.index]
                if userInput and not ui.loadingRows and current.manualCooldown then
                    current.manualCooldownSeconds = DraftManualCooldownSeconds(self:GetText())
                    DraftChanged(ui)
                end
            end)
            row.skipIfNotCasted = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.skipIfNotCasted:SetSize(25, 25)
            row.skipIfNotCasted:SetPoint("LEFT", row.manualCooldown, "LEFT", 482, 0)
            row.manualCooldownHint:SetPoint("RIGHT", row.skipIfNotCasted, "LEFT", -12, 0)
            row.skipIfNotCastedLabel = Label(row, "Require being behind target", "GameFontHighlightSmall")
            row.skipIfNotCastedLabel:SetPoint("LEFT", row.skipIfNotCasted, "RIGHT", 2, 0)
            Tooltip(row.skipIfNotCasted, "Require being behind target", "If WoW gives a positioning error, like Backstab from the front, your next press skips this rule once.")
            row.skipIfNotCasted:SetScript("OnClick", function(self)
                ui.draft[row.index].skipIfNotCasted = self:GetChecked() and true or false
                DraftChanged(ui)
            end)
            row.skipIfImmune = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.skipIfImmune:SetSize(25, 25)
            row.skipIfImmuneLabel = Label(row, "Skip if immune (bleed) [BETA]", "GameFontHighlightSmall")
            row.skipIfImmuneLabel:SetPoint("LEFT", row.skipIfImmune, "RIGHT", 2, 0)
            Tooltip(row.skipIfImmune, "Skip if immune (bleed) [BETA]", "When checked, recognized bleed spells skip Mechanical targets immediately. An Immune response immediately after your successful cast skips that spell on that enemy for the rest of combat. If it is a recognized bleed, your other checked bleed rules skip that enemy too, such as Rip after an immune Rake. Learned immunity is forgotten when combat ends.")
            row.skipIfImmune:SetScript("OnClick", function(self)
                ui.draft[row.index].skipIfImmune = self:GetChecked() and true or false
                DraftChanged(ui)
            end)
            row.comboPoints = CreateFrame("Frame", nil, row)
            row.comboPoints:SetSize(686, 78)
            local comboBackground = row.comboPoints:CreateTexture(nil, "BACKGROUND")
            comboBackground:SetAllPoints()
            comboBackground:SetColorTexture(0.075, 0.105, 0.13, 1)
            row.comboTitle = Label(row.comboPoints, "Combo points", "GameFontNormal", accent)
            row.comboTitle:SetPoint("TOPLEFT", 13, -9)
            row.comboOperator = Button(row.comboPoints, "At least (>=)", 230, 25)
            row.comboOperator:SetPoint("TOPLEFT", 13, -37)
            MarkDropdown(row.comboOperator)
            row.comboValue = Button(row.comboPoints, "5", 70, 25)
            row.comboValue:SetPoint("TOPLEFT", 251, -37)
            MarkDropdown(row.comboValue)
            local comboHint = Label(row.comboPoints, "Current target; applies to every alternative", "GameFontHighlightSmall")
            comboHint:SetPoint("TOPLEFT", 333, -44)
            row.comboRemove = Button(row.comboPoints, "Remove", 70, 22)
            row.comboRemove:SetPoint("TOPLEFT", 604, -8)
            row.comboPoints.operator, row.comboPoints.value, row.comboPoints.remove = row.comboOperator, row.comboValue, row.comboRemove
            Tooltip(row.comboOperator, "Combo points", "This spell also requires the chosen number of combo points on your current target. The comparison applies to every IF / OR alternative and works with any spell. No aura tracker is needed.")
            Tooltip(row.comboValue, "Required combo points", "Choose a number from 0 to 5. For a builder, Not equal to 5 allows it only when you do not have exactly five combo points.")
            row.comboOperator:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                if not current or current.comboPoints == nil then return end
                local combo = type(current.comboPoints) == "table" and current.comboPoints or {}
                ChoiceMenu(ui, self, Choices(comboOperators, comboOperatorLabels), combo.operator, function(value)
                    if type(current.comboPoints) ~= "table" then current.comboPoints = {value = 5} end
                    current.comboPoints.operator = value
                    DraftChanged(ui)
                    RefreshRows(ui)
                end)
            end)
            row.comboValue:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                if not current or current.comboPoints == nil then return end
                local choices = {}
                for value = 0, 5 do choices[#choices + 1] = {value = value, label = tostring(value)} end
                local combo = type(current.comboPoints) == "table" and current.comboPoints or {}
                ChoiceMenu(ui, self, choices, combo.value, function(value)
                    if type(current.comboPoints) ~= "table" then current.comboPoints = {operator = "ge"} end
                    current.comboPoints.value = value
                    DraftChanged(ui)
                    RefreshRows(ui)
                end)
            end)
            row.comboRemove:SetScript("OnClick", function()
                local current = ui.draft[row.index]
                if not current then return end
                local clearedCount = ClearCountAttachment(current, "comboPoints")
                current.comboPoints = nil
                DraftChanged(ui)
                RefreshRows(ui)
                if clearedCount then ShowResult(ui, false, "The unsupported combo-point cast count was cleared with its condition.") end
            end)
            row.hawkCount = CreateFrame("Frame", nil, row)
            row.hawkCount:SetSize(686, 78)
            local hawkBackground = row.hawkCount:CreateTexture(nil, "BACKGROUND")
            hawkBackground:SetAllPoints()
            hawkBackground:SetColorTexture(0.075, 0.105, 0.13, 1)
            row.hawkTitle = Label(row.hawkCount, "Hawk conditions", "GameFontNormal", accent)
            row.hawkTitle:SetPoint("TOPLEFT", 13, -9)
            row.hawkOperator = Button(row.hawkCount, "Fewer than (<)", 230, 25)
            row.hawkOperator:SetPoint("TOPLEFT", 13, -37)
            MarkDropdown(row.hawkOperator)
            row.hawkValue = Button(row.hawkCount, "2", 70, 25)
            row.hawkValue:SetPoint("TOPLEFT", 251, -37)
            MarkDropdown(row.hawkValue)
            local hawkHint = Label(row.hawkCount, "Your hawks; applies to every alternative", "GameFontHighlightSmall")
            hawkHint:SetPoint("TOPLEFT", 333, -44)
            row.hawkRemove = Button(row.hawkCount, "Remove", 70, 22)
            row.hawkRemove:SetPoint("TOPLEFT", 604, -8)
            row.hawkCount.operator, row.hawkCount.value, row.hawkCount.remove = row.hawkOperator, row.hawkValue, row.hawkRemove
            Tooltip(row.hawkOperator, "Hawk conditions", hawkHelp)
            Tooltip(row.hawkValue, "Active hawks", "Choose 0, 1, or 2 active hawks. Fewer than 2 can keep Summon Hawk from replacing a hawk that is still active.")
            row.hawkOperator:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                if not current or current.hawkCount == nil then return end
                local hawk = type(current.hawkCount) == "table" and current.hawkCount or {}
                ChoiceMenu(ui, self, Choices(hawkOperators, hawkOperatorLabels), hawk.operator, function(value)
                    if type(current.hawkCount) ~= "table" then current.hawkCount = {value = 2} end
                    current.hawkCount.operator = value
                    DraftChanged(ui)
                    RefreshRows(ui)
                end)
            end)
            row.hawkValue:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                if not current or current.hawkCount == nil then return end
                local choices = {}
                for value = 0, 2 do choices[#choices + 1] = {value = value, label = tostring(value)} end
                local hawk = type(current.hawkCount) == "table" and current.hawkCount or {}
                ChoiceMenu(ui, self, choices, hawk.value, function(value)
                    if type(current.hawkCount) ~= "table" then current.hawkCount = {operator = "lt"} end
                    current.hawkCount.value = value
                    DraftChanged(ui)
                    RefreshRows(ui)
                end)
            end)
            row.hawkRemove:SetScript("OnClick", function()
                local current = ui.draft[row.index]
                if not current then return end
                local clearedCount = ClearCountAttachment(current, "hawkCount")
                current.hawkCount = nil
                DraftChanged(ui)
                RefreshRows(ui)
                if clearedCount then ShowResult(ui, false, "The unsupported hawk cast count was cleared with its condition.") end
            end)
            row.number = Label(row, "", "GameFontNormalLarge", accent)
            row.number:SetPoint("TOPLEFT", 16, -14)

            row.spellLabel = Label(row, "Spell name or ID", "GameFontNormalSmall", { 0.76, 0.8, 0.84 })
            row.spellLabel:SetPoint("TOPLEFT", 16, -42)
            row.spell = EditBox(row, 310)
            row.spell:SetPoint("TOPLEFT", 16, -58)
            Tooltip(row.spell, "Spell or action", "Enter a spell name or ID, or choose Auto Attack, Shoot, Auto Shot, or Pet Attack under + Action.")
            row.customRuleScroll = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.customRuleScroll:SetPoint("TOPLEFT", 14, -58)
            row.customRuleScroll:SetSize(686, 64)
            Skin(row.customRuleScroll, {0.04, 0.06, 0.08, 1}, {0.34, 0.3, 0.21, 1})
            row.customRuleViewport = CreateFrame("ScrollFrame", nil, row.customRuleScroll, "UIPanelScrollFrameTemplate")
            row.customRuleViewport:SetPoint("TOPLEFT", 6, -4)
            row.customRuleViewport:SetSize(650, 56)
            row.customRuleText = CreateFrame("EditBox", nil, row.customRuleViewport)
            row.customRuleText:SetMultiLine(true)
            row.customRuleText:SetAutoFocus(false)
            row.customRuleText:SetMaxLetters(SH.Model.MAX_CUSTOM_RULE_BYTES or 1023)
            row.customRuleText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "")
            row.customRuleText:SetSize(642, 1)
            row.customRuleText:SetTextInsets(2, 2, 2, 2)
            row.customRuleViewport:SetScrollChild(row.customRuleText)
            row.customRuleText:SetScript("OnTextChanged", function(self, userInput)
                row.customRuleViewport:UpdateScrollChildRect()
                if userInput and not ui.loadingRows then
                    ui.draft[row.index].customRule = self:GetText()
                    DraftChanged(ui)
                end
            end)
            row.customRuleText:SetScript("OnSizeChanged", function() row.customRuleViewport:UpdateScrollChildRect() end)
            row.customRuleText:SetScript("OnCursorChanged", function(_, _, y, _, height)
                local scroll = row.customRuleViewport
                local offset, current = math.max(0, -(y or 0)), scroll:GetVerticalScroll()
                if offset < current then scroll:SetVerticalScroll(offset)
                elseif offset + (height or 0) > current + scroll:GetHeight() then
                    scroll:SetVerticalScroll(offset + (height or 0) - scroll:GetHeight())
                end
            end)
            row.customRuleText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            row.customRuleText:SetScript("OnHide", function(self) self:ClearFocus() end)
            row.customRuleScroll:SetScript("OnMouseDown", function() row.customRuleText:SetFocus() end)
            Tooltip(row.customRuleText, "Custom Rule", "Write macro commands, one per line, such as /targetenemy [noexists][dead]. One Custom Rule can be enabled per Hit Button. Use the visible Hit Button, Set cast key, or Controller; action-bar macros cannot run Custom Rules. Put it above Auto Attack. Matching commands run once, then the same press checks the next matching rule. Up to 16 lines and 1023 bytes; Prepare checks the final size.\nWhen commands run, automatic cast interruption does not apply. Add /stopcasting to interrupt. If all command conditions fail, normal interrupt settings still apply. See Advanced > Custom Rule examples for supported commands.")
            row.customRuleScroll:Hide()
            row.wandHint = Label(row, "", "GameFontHighlightSmall", accent)
            row.wandHint:SetWidth(670)
            row.wandHint:Hide()

            row.auraLabel = Label(row, "Aura name or ID", "GameFontNormalSmall", { 0.76, 0.8, 0.84 })
            row.auraLabel:SetPoint("TOPLEFT", 27, -211)
            row.auraSource = Button(row, "Tracked aura", 154, 22)
            MarkDropdown(row.auraSource)
            row.auraSource:SetPoint("TOPLEFT", 27, -174)
            Tooltip(row.auraSource, "Aura source", auraSourceHelp)
            row.auraSource:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                ChoiceMenu(ui, self, Choices(auraSources, auraSourceLabels), current.auraSource or "tracker", function(value)
                    current.auraSource = value
                    if not SH.Model.StopBranches(current) then current.oncePerProc = false end
                    if not CanStopCast(current) then current.stopCasting = false end
                    DraftChanged(ui)
                    RefreshRows(ui)
                end)
            end)
            row.aura = EditBox(row, 650)
            row.aura:SetPoint("TOPLEFT", 27, -225)
            Tooltip(row.aura, "Aura name or ID", function()
                return auraInputHelp[ui.draft[row.index].auraSource] or auraInputHelp.tracker
            end)

            row.up = Button(row, "Up", 48, 23)
            row.up:SetPoint("TOPRIGHT", -70, -10)
            row.down = Button(row, "Down", 48, 23)
            row.down:SetPoint("TOPRIGHT", -15, -10)
            row.remove = Button(row, "Remove", 103, 23)
            row.remove:SetPoint("TOPRIGHT", -15, -38)
            row.up:Hide(); row.down:Hide(); row.remove:Hide()

            row.condition = Button(row, "", 178, 24)
            MarkDropdown(row.condition)
            row.condition:SetPoint("TOPLEFT", 207, -174)
            Tooltip(row.condition, "Aura condition", "Choose whether the selected buff or debuff must be present or missing. Cast on chooses who receives the spell.")

            local castOn = Label(row, "Cast on", "GameFontNormalSmall", { 0.76, 0.8, 0.84 })
            row.castOnLabel = castOn
            castOn:SetPoint("TOPLEFT", 16, -100)
            row.unit = Button(row, "", 200, 24)
            row.unit:SetPoint("TOPLEFT", 78, -93)
            MarkDropdown(row.unit)
            Tooltip(row.unit, "Casting target", "Target of focus casts on the unit your focus is targeting. Party numbers refer to the game's party slots. A missing party member stops that press. Choose Advanced to enable Custom Target.")
            row.customTarget = EditBox(row, 242)
            row.customTarget:SetMaxLetters(100)
            row.customTarget:SetPoint("TOPLEFT", 296, -93)
            row.targetHint = Label(row, "e.g. @focus", "GameFontHighlightSmall")
            row.targetHint:SetPoint("LEFT", row.customTarget, "RIGHT", 10, 0)
            Tooltip(row.customTarget, "Custom Target", "Enter one macro target, such as @focus, @party2 or @targettarget. See Advanced > Custom Target examples for the list.")
            row.customTarget:SetScript("OnTextChanged", function(self, userInput)
                if userInput and not ui.loadingRows then
                    ui.draft[row.index].customTarget = self:GetText()
                    DraftChanged(ui)
                end
            end)

            row.macroPanel = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.macroPanel:SetSize(686, 76)
            Skin(row.macroPanel, { 0.075, 0.105, 0.13, 1 }, { 0.15, 0.2, 0.25, 1 })
            row.macroTitle = Label(row.macroPanel, "", "GameFontNormal", accent)
            row.macroTitle:SetPoint("TOPLEFT", 12, -9)
            row.customCondition = EditBox(row.macroPanel, 565)
            row.customCondition:SetMaxLetters(254)
            row.customCondition:SetPoint("TOPLEFT", 14, -36)
            Tooltip(row.customCondition, "Custom Conditions", "Enter a bracketed macro condition such as [harm,nodead]. It must match for the rule to cast. See Advanced > Custom Conditions examples for the list.")
            row.customCondition:SetScript("OnTextChanged", function(self, userInput)
                if userInput and not ui.loadingRows then
                    ui.draft[row.index].customCondition = self:GetText()
                    DraftChanged(ui)
                end
            end)
            row.removeMacro = Button(row.macroPanel, "Remove", 78, 25)
            row.removeMacro:SetPoint("TOPRIGHT", -12, -36)
            row.removeMacro:SetScript("OnClick", function()
                row.customCondition:ClearFocus()
                ui.draft[row.index].customCondition = nil
                DraftChanged(ui)
                RefreshRows(ui)
            end)

            row.skipCooldown = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.skipCooldown:SetSize(25, 25)
            row.skipCooldown:SetPoint("TOPLEFT", 15, -307)
            row.skipCooldownLabel = Label(row, "Skip while on cooldown", "GameFontHighlightSmall")
            row.skipCooldownLabel:SetPoint("LEFT", row.skipCooldown, "RIGHT", 2, 0)
            row.cooldownHint = Label(row, "AND: off cooldown, whichever aura condition matches.", "GameFontHighlightSmall", { 0.69, 0.75, 0.8 })
            row.cooldownHint:SetPoint("TOPLEFT", 207, -315)
            Tooltip(row.skipCooldown, "Skip while on cooldown", function()
                if ui.draft[row.index].manualCooldown then
                    return "Manual cooldown supplies this rule's cooldown check. This native tracker option is disabled; its saved setting is kept for when Manual cooldown is turned off. Tracked aura present/missing conditions still apply."
                end
                return "Try the next matching rule while this spell is on cooldown. Requires a supported native Essential or Utility tracker. Spells whose tracker displays a buff also need an Aura is missing rule for that same buff. Charge-based spells are not supported."
            end)
            row.skipCooldown:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                if current.manualCooldown then
                    self:SetChecked(current.skipCooldown == true)
                    return
                end
                current.skipCooldown = self:GetChecked() and true or false
                local count = DraftCount(current.castCount)
                if current.skipCooldown and Trim(current.aura) == "" and not current.useOr
                    and not current.oncePerProc and not current.stopCasting and not current.stopWhenInvalid
                    and (count == nil or count == 0) then
                    current.condition = "always"
                end
                DraftChanged(ui)
                RefreshRows(ui)
            end)

            row.oncePerProc = CreateFrame("CheckButton", nil, row.optionsBody, "UICheckButtonTemplate")
            row.oncePerProc:SetSize(25, 25)
            row.oncePerProc:SetPoint("TOPLEFT", 456, 0)
            row.oncePerProcLabel = Label(row.optionsBody, "Once per proc", "GameFontHighlightSmall")
            row.oncePerProcLabel:SetPoint("LEFT", row.oncePerProc, "RIGHT", 2, 0)
            Tooltip(row.oncePerProc, "Once per proc", "For a channel that uses a single-use proc. A press during that channel marks the primary aura branch used until its tracker hides. The first OR condition can still match independently. Requires a present primary tracker and Protect channels. Spell cooldown conditions do not create a proc. Enabling this clears Number of times to cast.")
            row.oncePerProc:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                current.oncePerProc = SH.Model.StopBranches(current) and self:GetChecked() and true or false
                if current.oncePerProc then current.castCount, current.castCountCondition = nil, nil end
                DraftChanged(ui)
                RefreshRows(ui)
            end)

            row.stopCasting = CreateFrame("CheckButton", nil, row.optionsBody, "UICheckButtonTemplate")
            row.stopCasting:SetSize(25, 25)
            row.stopCasting:SetPoint("TOPLEFT", 0, 0)
            row.stopCastingLabel = Label(row.optionsBody, "Stop current cast", "GameFontHighlightSmall")
            row.stopCastingLabel:SetPoint("LEFT", row.stopCasting, "RIGHT", 2, 0)
            Tooltip(row.stopCasting, "Stop current cast", "Use Set cast key or Controller below. When a present Tracked aura or Target debuff allows the IF or first OR branch, press the assigned button to interrupt your current cast and try this spell. This triggers once per proc. Channels stay protected.")
            row.stopCasting:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                current.stopCasting = CanStopCast(current) and self:GetChecked() and true or false
                DraftChanged(ui)
                RefreshRows(ui)
            end)

            row.skipOutOfRange = CreateFrame("CheckButton", nil, row.optionsBody, "UICheckButtonTemplate")
            row.skipOutOfRange:SetSize(25, 25)
            row.skipOutOfRange:SetPoint("TOPLEFT", 0, -28)
            row.skipOutOfRangeLabel = Label(row.optionsBody, "Skip if out of range", "GameFontHighlightSmall")
            row.skipOutOfRangeLabel:SetPoint("LEFT", row.skipOutOfRange, "RIGHT", 2, 0)
            Tooltip(row.skipOutOfRange, "Skip if out of range", "Try the next rule when WoW confirms the selected unit is out of range for this spell. If range is unknown, try this rule as usual.")
            row.skipOutOfRange:SetScript("OnClick", function(self)
                ui.draft[row.index].skipOutOfRange = self:GetChecked() and true or false
                DraftChanged(ui)
            end)

            row.outOfCombatOnly = CreateFrame("CheckButton", nil, row.optionsBody, "UICheckButtonTemplate")
            row.outOfCombatOnly:SetSize(25, 25)
            row.outOfCombatOnlyLabel = Label(row.optionsBody, "Out of combat only", "GameFontHighlightSmall")
            row.outOfCombatOnlyLabel:SetPoint("LEFT", row.outOfCombatOnly, "RIGHT", 2, 0)
            Tooltip(row.outOfCombatOnly, "Out of combat only", "Skip this rule during combat and try the next matching rule. It becomes available again after combat, with all its other conditions still required. Does not stop a cast or attack already running.")
            row.outOfCombatOnly:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                current.outOfCombatOnly = self:GetChecked() and true or false
                if current.outOfCombatOnly then current.inCombatOnly = false end
                DraftChanged(ui)
                RefreshRows(ui)
            end)

            row.inCombatOnly = CreateFrame("CheckButton", nil, row.optionsBody, "UICheckButtonTemplate")
            row.inCombatOnly:SetSize(25, 25)
            row.inCombatOnlyLabel = Label(row.optionsBody, "In combat only", "GameFontHighlightSmall")
            row.inCombatOnlyLabel:SetPoint("LEFT", row.inCombatOnly, "RIGHT", 2, 0)
            Tooltip(row.inCombatOnly, "In combat only", "Use this rule while you are in combat, with all its other conditions still required. Outside combat, try the next matching rule.")
            row.inCombatOnly:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                current.inCombatOnly = self:GetChecked() and true or false
                if current.inCombatOnly then current.outOfCombatOnly = false end
                DraftChanged(ui)
                RefreshRows(ui)
            end)

            row.advanceOnToggle = CreateFrame("CheckButton", nil, row.optionsBody, "UICheckButtonTemplate")
            row.advanceOnToggle:SetSize(25, 25)
            row.advanceOnToggle:SetPoint("TOPLEFT", 0, -56)
            row.advanceOnToggleLabel = Label(row.optionsBody, "Advance on toggle", "GameFontHighlightSmall")
            row.advanceOnToggleLabel:SetPoint("LEFT", row.advanceOnToggle, "RIGHT", 2, 0)
            Tooltip(row.advanceOnToggle, "Advance on toggle", "Once this spell is queued or toggled on, later presses skip it and try the next matching rule. This rule becomes available again when the spell is no longer queued or toggled on. For spells such as Raptor Strike, Heroic Strike, and Maul.")
            row.advanceOnToggle:SetScript("OnClick", function(self)
                ui.draft[row.index].advanceOnToggle = self:GetChecked() and true or false
                DraftChanged(ui)
                RefreshRows(ui)
            end)

            row.rankLabel = Label(row, "Rank", "GameFontNormalSmall", { 0.76, 0.8, 0.84 })
            row.rankLabel:SetPoint("TOPLEFT", 351, -42)
            row.rank = Button(row, "Highest learned", 332, 24)
            row.rank:SetPoint("TOPLEFT", 349, -58)
            Tooltip(row.rank, "Spell rank", "Click to cycle through Highest learned and the ranks you know. Highest learned follows new ranks as you learn them. A numbered rank stays fixed until you change it.")
            row.rank:SetScript("OnClick", function()
                local current = ui.draft[row.index]
                local choices, baseName = RankChoices(current)
                local selected = tonumber(current.rankID) or tonumber(current.spell)
                local nextIndex = 1
                for index, choice in ipairs(choices) do
                    if choice.id == selected then nextIndex = index % #choices + 1; break end
                end
                local choice = choices[nextIndex]
                -- A numeric field must become a name when switching to Highest learned.
                if not choice.id and tonumber(current.spell) and (not baseName or tonumber(baseName)) then return end
                if type(baseName) == "string" and Trim(baseName) ~= "" then current.spell = baseName end
                current.rankID = choice.id
                DraftChanged(ui)
                RefreshRows(ui)
            end)

            row.useOr = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.useOr:SetSize(25, 25)
            row.useOr:SetPoint("TOPLEFT", 23, -224)
            row.useOrLabel = Label(row, "OR / Use an alternative aura", "GameFontNormal", accent)
            row.useOrLabel:SetPoint("LEFT", row.useOr, "RIGHT", 2, 0)
            Tooltip(row.useOr, "Alternative condition", "Allow this rule when either the primary aura condition or this second aura or spell cooldown condition matches. Added AND and NOT conditions and Skip while on cooldown still apply to both.")
            row.orAuraSource = Button(row, "Tracked aura", 154, 22)
            MarkDropdown(row.orAuraSource)
            row.orAuraSource:SetPoint("TOPLEFT", 524, -224)
            Tooltip(row.orAuraSource, "Alternative condition source", extraConditionSourceHelp)
            row.orAuraSource:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                ChoiceMenu(ui, self, Choices(extraConditionSources, auraSourceLabels), current.orAuraSource or "tracker", function(value)
                    current.orAuraSource = value
                    local clearedCount = value == "cooldown" and ClearCountAttachment(current, "or")
                    if not CanStopCast(current) then current.stopCasting = false end
                    DraftChanged(ui)
                    RefreshRows(ui)
                    if clearedCount then ShowResult(ui, false, "Condition 2 - OR now checks a spell cooldown, so its cast count was cleared.") end
                end)
            end)
            row.useOr:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                current.useOr = self:GetChecked() and true or false
                local clearedCount = not current.useOr and ClearCountAttachment(current, "or")
                if not CanStopCast(current) then current.stopCasting = false end
                DraftChanged(ui)
                RefreshRows(ui)
                if clearedCount then ShowResult(ui, false, "Condition 2 - OR was removed, so its cast count was cleared.") end
            end)
            row.orAura = EditBox(row, 458)
            row.orAura:SetPoint("TOPLEFT", 220, -258)
            row.orAuraLabel = Label(row, "Aura name or ID", "GameFontNormalSmall", { 0.76, 0.8, 0.84 })
            row.orAuraLabel:SetPoint("TOPLEFT", 220, -244)
            Tooltip(row.orAura, function()
                return conditionInputLabels[ui.draft[row.index].orAuraSource] or conditionInputLabels.tracker
            end, function()
                return auraInputHelp[ui.draft[row.index].orAuraSource] or auraInputHelp.tracker
            end)
            row.orAura:SetScript("OnTextChanged", function(self, userInput)
                if userInput and not ui.loadingRows then
                    ui.draft[row.index].orAura = self:GetText()
                    DraftChanged(ui)
                end
            end)
            row.orCondition = Button(row, "", 178, 24)
            MarkDropdown(row.orCondition)
            row.orCondition:SetPoint("TOPLEFT", 27, -258)
            Tooltip(row.orCondition, "Alternative condition", function()
                if ui.draft[row.index].orAuraSource == "cooldown" then return spellCooldownHelp end
                return "Choose whether the alternative aura, buff, or debuff must be present or missing."
            end)
            row.orCondition:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                local labels = conditionLabelsBySource[current.orAuraSource] or conditionLabels
                ChoiceMenu(ui, self, Choices(auraConditions, labels), current.orCondition, function(value)
                    current.orCondition = value
                    if not CanStopCast(current) then current.stopCasting = false end
                    DraftChanged(ui)
                    RefreshRows(ui)
                end)
            end)

            row.stopWhenInvalid = CreateFrame("CheckButton", nil, row.optionsBody, "UICheckButtonTemplate")
            row.stopWhenInvalid:SetSize(25, 25)
            row.stopWhenInvalid:SetPoint("TOPLEFT", 225, 0)
            row.stopWhenInvalidLabel = Label(row.optionsBody, "Stop if buffs change", "GameFontHighlightSmall")
            row.stopWhenInvalidLabel:SetPoint("LEFT", row.stopWhenInvalid, "RIGHT", 2, 0)
            Tooltip(row.stopWhenInvalid, "Stop if buffs change", "Use Set cast key or Controller below. On your next assigned key or controller-button press, stop the spell last selected by Stand and Hit when its aura, buff, or debuff conditions no longer match, then select the next matching rule. OR can replace IF; every aura AND must still match and any matching aura NOT blocks the rule, including an unfinished cast batch. Spell cooldown changes do not trigger this option. This does not act automatically when a buff changes or identify spells cast manually. Channels stay protected.")
            row.stopWhenInvalid:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                current.stopWhenInvalid = current.primaryCondition == nil and HasAuraConditions(current) and self:GetChecked() and true or false
                DraftChanged(ui)
                RefreshRows(ui)
            end)

            row.castCountLabel = Label(row.optionsBody, "Cast count", "GameFontHighlightSmall")
            row.castCountLabel:SetPoint("TOPLEFT", 343, -39)
            row.castCount = EditBox(row.optionsBody, 54)
            row.castCount:SetPoint("TOPLEFT", 512, -32)
            row.castCountHint = Label(row.optionsBody, "0 = unlimited", "GameFontHighlightSmall", { 0.69, 0.75, 0.8 })
            row.castCountHint:SetPoint("TOPLEFT", 580, -39)
            row.countAttachmentLabel = Label(row.optionsBody, "Attach count to", "GameFontHighlightSmall")
            row.castCountCondition = Button(row.optionsBody, "", 330, 25)
            row.castCountCondition.menuWidth = 640
            row.castCountCondition.menuAlignRight = true
            MarkDropdown(row.castCountCondition)
            Tooltip(row.castCountCondition, "Attach count to a condition", "Choose which numbered condition gets this cast limit. Tracked-aura IF, OR, and AND conditions are supported. Other conditions keep their ordinary behavior. Unsupported conditions appear unavailable in this menu.")
            row.castCountCondition:SetScript("OnClick", function(self)
                local current, choices = ui.draft[row.index], {}
                for _, entry in ipairs(SH.Model.ConditionEntries(current)) do
                    choices[#choices + 1] = { value = entry.key,
                        label = CountConditionLabel(entry, true) .. (entry.countEligible and "" or (" (" .. CountUnavailableReason(entry) .. ")")),
                        enabled = entry.countEligible and not current.oncePerProc,
                        reason = entry.countReason }
                end
                ChoiceMenu(ui, self, choices, current.castCountCondition == nil and "primary" or current.castCountCondition, function(value)
                    current.castCountCondition = value
                    DraftChanged(ui)
                    RefreshRows(ui)
                end)
            end)
            row.optionsHint = Label(row.optionsBody, "Interrupt options use Set cast key or Controller below. Channels stay protected.", "GameFontHighlightSmall", { 0.69, 0.75, 0.8 })
            row.optionsHint:SetPoint("TOPLEFT", 6, -85)
            row.countReminder = Label(row.optionsBody, "Keep this spell's chosen rank in a fixed, visible Blizzard action-bar slot.", "GameFontHighlightSmall", accent)
            row.countReminder:SetPoint("TOPLEFT", 6, -59)
            row.countReminder:SetWidth(672)
            row.countReminder:SetHeight(40)
            row.countReminder:SetJustifyV("TOP")
            Tooltip(row.castCount, "Number of times to cast", "Enter 1 to 99 completed casts; blank or 0 is unlimited. Attach the count to a numbered tracked-aura IF, OR, or AND condition. A missing-aura batch continues after its buff appears. That aura disappearing resets its count. Completed casts during a running batch count even when a proc allows them. The limit applies only to the attached condition. Requires a normal cast-time spell and its matching rank on a fixed, visible Blizzard action bar. Instant spells, channels, and Once per proc are not supported.")
            row.castCount:SetScript("OnTextChanged", function(self, userInput)
                local current = ui.draft[row.index]
                local attached = SH.Model.GetCountCondition(current)
                if userInput and not ui.loadingRows and not current.oncePerProc
                    and ((attached and attached.countEligible) or HasDraftCount(current)) then
                    ui.castingViews = ui.castingViews or setmetatable({}, { __mode = "k" })
                    ui.castingViews[current] = ui.castingViews[current] or {}
                    ui.castingViews[current].count = true
                    current.castCount = DraftCount(self:GetText())
                    if HasDraftCount(current) and current.castCountCondition == nil then current.castCountCondition = "primary" end
                    DraftChanged(ui)
                end
            end)

            row.spell:SetScript("OnTextChanged", function(self, userInput)
                if userInput and not ui.loadingRows then
                    local current = ui.draft[row.index]
                    local previousCommand = row.attackCommand
                    local wasRepeating = row.wandShoot or row.autoShot
                    current.spell, current.rankID = self:GetText(), nil
                    if AttackCommand(current.spell) and not previousCommand then
                        current.unit, current.customTarget = "target", nil
                        current.castCount, current.castCountCondition = nil, nil
                        current.skipCooldown, current.pingDelay, current.manualCooldown = false, false, false
                        current.skipOutOfRange = false
                        current.advanceOnToggle = false
                        current.oncePerProc, current.stopCasting, current.stopWhenInvalid = false, false, false
                        if ui.castingViews then ui.castingViews[current] = nil end
                        if Trim(current.aura) == "" and not current.useOr and #(current.orConditions or {}) == 0 then
                            current.condition = "always"
                        end
                    end
                    RefreshRank(row, current)
                    if row.attackCommand or row.wandShoot or row.autoShot then current.skipIfNotCasted = false end
                    if previousCommand ~= row.attackCommand or wasRepeating ~= (row.wandShoot or row.autoShot) then RefreshRows(ui) end
                    DraftChanged(ui)
                end
            end)
            row.aura:SetScript("OnTextChanged", function(self, userInput)
                if userInput and not ui.loadingRows then
                    ui.draft[row.index].aura = self:GetText()
                    DraftChanged(ui)
                end
            end)
            row.condition:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                local labels = conditionLabelsBySource[current.auraSource] or conditionLabels
                ChoiceMenu(ui, self, Choices(auraConditions, labels), current.condition, function(value)
                    current.condition = value
                    if current.condition ~= "present" then current.oncePerProc = false end
                    if not CanStopCast(current) then current.stopCasting = false end
                    DraftChanged(ui)
                    RefreshRows(ui)
                end)
            end)
            row.unit:SetScript("OnClick", function(self)
                local current = ui.draft[row.index]
                local choices = Choices(units, unitLabels)
                if SH.rootDB.customTargetsEnabled then
                    choices[#choices + 1] = {value = "custom", label = unitLabels.custom}
                end
                ChoiceMenu(ui, self, choices, current.unit, function(value)
                    current.unit = value
                    if value == "custom" then current.customTarget = current.customTarget or ""
                    else current.customTarget = nil end
                    DraftChanged(ui)
                    RefreshRows(ui)
                    if value == "custom" then row.customTarget:SetFocus() end
                end)
            end)
            row.up:SetScript("OnClick", function()
                local index = row.index
                if index > 1 then
                    ui.draft[index], ui.draft[index - 1] = ui.draft[index - 1], ui.draft[index]
                    ui.selectedIndex = index - 1
                    DraftChanged(ui)
                    RefreshRows(ui)
                end
            end)
            row.down:SetScript("OnClick", function()
                local index = row.index
                if index < #ui.draft then
                    ui.draft[index], ui.draft[index + 1] = ui.draft[index + 1], ui.draft[index]
                    ui.selectedIndex = index + 1
                    DraftChanged(ui)
                    RefreshRows(ui)
                end
            end)
            row.remove:SetScript("OnClick", function()
                table.remove(ui.draft, row.index)
                ui.selectedIndex = math.min(row.index, #ui.draft)
                DraftChanged(ui)
                RefreshRows(ui)
            end)
            ui.rows[i] = row
        end
        row.index = i
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, 0)
        row.number:SetText("Rule " .. i)
        row.spell:SetText(DisplaySpell(rule))
        if row.customRuleText:GetText() ~= (rule.customRule or "") then row.customRuleText:SetText(rule.customRule or "") end
        row.aura:SetText(rule.aura or "")
        RefreshRank(row, rule)
        row.orAura:SetText(rule.orAura or "")
        local labels = conditionLabelsBySource[rule.auraSource] or conditionLabels
        local orLabels = conditionLabelsBySource[rule.orAuraSource] or conditionLabels
        row.orCondition:SetText(orLabels[rule.orCondition] or orLabels.present)
        row.condition:SetText(rule.condition == "always" and (rule.skipCooldown == true or rule.manualCooldown == true)
            and CooldownLabel(rule) or labels[rule.condition] or labels.present)
        row.auraSource:SetText(auraSourceLabels[rule.auraSource or "tracker"] or "Choose source")
        row.orAuraSource:SetText(auraSourceLabels[rule.orAuraSource or "tracker"] or "Choose source")
        row.orAuraLabel:SetText(conditionInputLabels[rule.orAuraSource] or conditionInputLabels.tracker)
        row.auraLabel:SetText(auraNameLabels[rule.auraSource] or "Aura name or ID")
        row.unit:SetText(unitLabels[rule.unit] or unitLabels.target)
        local hasCustomTarget = rule.unit == "custom" and not row.attackCommand
        row.customTarget:SetShown(hasCustomTarget)
        row.targetHint:SetShown(hasCustomTarget)
        row.customTarget:SetText(rule.customTarget or "")
        row.customCondition:SetText(rule.customCondition or "")
        if not hasCustomTarget then row.customTarget:ClearFocus() end
        row.skipCooldown:SetChecked(rule.skipCooldown == true)
        row.skipCooldown:SetEnabled(not rule.manualCooldown)
        row.skipCooldownLabel:SetAlpha(rule.manualCooldown and 0.35 or 1)
        row.cooldownHint:SetAlpha((rule.skipCooldown or rule.manualCooldown) and 1 or 0.45)
        row.oncePerProc:SetChecked(rule.oncePerProc == true)
        local canUseOncePerProc = SH.Model.StopBranches(rule)
        local incompatibleProc = rule.oncePerProc and not canUseOncePerProc
        row.oncePerProc:SetEnabled(canUseOncePerProc or rule.oncePerProc == true)
        row.oncePerProcLabel:SetAlpha((canUseOncePerProc or rule.oncePerProc) and 1 or 0.35)
        row.oncePerProcLabel:SetTextColor(1, incompatibleProc and 0.4 or 1, incompatibleProc and 0.4 or 1)
        row.stopCasting:SetChecked(rule.stopCasting == true)
        local canStop = CanStopCast(rule)
        local incompatibleStop = rule.stopCasting and not canStop
        row.stopCasting:SetEnabled(canStop or rule.stopCasting == true)
        row.stopCastingLabel:SetAlpha((canStop or rule.stopCasting) and 1 or 0.35)
        row.stopCastingLabel:SetTextColor(1, incompatibleStop and 0.4 or 1, incompatibleStop and 0.4 or 1)
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #ui.draft)
        local needsAura = rule.condition ~= "always"
        local needsOrAura = rule.useOr == true
        if not needsAura then row.aura:ClearFocus() end
        if not needsOrAura then row.orAura:ClearFocus() end
        local hasConditions = rule.primaryCondition == nil and HasAuraConditions(rule)
        local incompatibleInvalid = rule.stopWhenInvalid and not hasConditions
        row.stopWhenInvalid:SetChecked(rule.stopWhenInvalid == true)
        row.stopWhenInvalid:SetEnabled(hasConditions or rule.stopWhenInvalid == true)
        row.stopWhenInvalidLabel:SetAlpha((hasConditions or rule.stopWhenInvalid) and 1 or 0.35)
        row.stopWhenInvalidLabel:SetTextColor(1, incompatibleInvalid and 0.4 or 1, incompatibleInvalid and 0.4 or 1)
        row.optionsHint:SetText((incompatibleProc or incompatibleStop or incompatibleInvalid)
            and "Clear the red casting options, or choose a matching aura condition."
            or "Interrupt options use Set cast key or Controller below. Channels stay protected.")
        row.castCount:SetText(tostring(rule.castCount or ""))
        row.pingDelay:SetChecked(rule.pingDelay == true)
        row.pingDelayMS:SetText(tostring(DraftPingDelayMS(rule.pingDelayMS)))
        row.pingDelayMS:SetEnabled(rule.pingDelay == true)
        row.pingDelayMS:SetAlpha(rule.pingDelay and 1 or 0.35)
        row.pingDelayUnit:SetAlpha(rule.pingDelay and 1 or 0.35)
        if not rule.pingDelay then row.pingDelayMS:ClearFocus() end
        row.manualCooldown:SetChecked(rule.manualCooldown == true)
        row.skipIfNotCasted:SetChecked(rule.skipIfNotCasted == true)
        row.skipIfImmune:SetChecked(rule.skipIfImmune == true)
        row.skipOutOfRange:SetChecked(rule.skipOutOfRange == true)
        row.outOfCombatOnly:SetChecked(rule.outOfCombatOnly == true)
        row.inCombatOnly:SetChecked(rule.inCombatOnly == true)
        row.advanceOnToggle:SetChecked(rule.advanceOnToggle == true)
        row.manualCooldownSeconds:SetText(tostring(DraftManualCooldownSeconds(rule.manualCooldownSeconds)))
        row.manualCooldownSeconds:SetEnabled(rule.manualCooldown == true)
        row.manualCooldownSeconds:SetAlpha(rule.manualCooldown and 1 or 0.35)
        row.manualCooldownUnit:SetAlpha(rule.manualCooldown and 1 or 0.35)
        if not rule.manualCooldown then row.manualCooldownSeconds:ClearFocus() end
        RefreshCountControls(row, rule)
        row.useOr:SetChecked(rule.useOr == true)
        row.useOr:SetEnabled(true)
        row.useOrLabel:SetAlpha(1)
        row.orAura:SetEnabled(needsOrAura)
        row.orAura:SetAlpha(needsOrAura and 1 or 0.35)
        row.orCondition:SetEnabled(needsOrAura)
        row.orAuraSource:SetEnabled(needsOrAura)
        row.aura:SetEnabled(needsAura)
        row.auraSource:SetEnabled(needsAura)
        row.aura:SetAlpha(needsAura and 1 or 0.35)
        row.auraLabel:SetAlpha(needsAura and 1 or 0.35)
        row:Show()
    end
    for i = #ui.draft + 1, #ui.rows do
        ClearRowFocus(ui.rows[i])
        ui.rows[i]:Hide()
    end
    ui.scrollChild:SetHeight(math.max(1, #ui.draft * ROW_HEIGHT))
    ui.empty:SetShown(#ui.draft == 0)
    ui.count:SetText(string.format("%d / %d rules", #ui.draft, MAX_RULES))
    ui.add:SetEnabled(#ui.draft < MAX_RULES)
    ui.addAction:SetEnabled(#ui.draft < MAX_RULES)
    ui.loadingRows = false
    ui.scroll:UpdateScrollChildRect()
    SelectRule(ui, ui.selectedIndex)
    ui.refreshingRows = false
end

CheckBox = function(parent, text, x, y, tooltipTitle, tooltipBody, changed)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(25, 25)
    check:SetPoint("TOPLEFT", x, y)
    local label = Label(parent, text, "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label = label
    Tooltip(check, tooltipTitle, tooltipBody)
    check:SetScript("OnClick", function(self) changed(self:GetChecked() and true or false) end)
    return check
end

local function TrackerEnabled()
    local getter = C_CVar and C_CVar.GetCVarBool or GetCVarBool
    if type(getter) ~= "function" then return nil end
    local ok, enabled = pcall(getter, "cooldownViewerEnabled")
    if ok then return enabled end
end

local function RefreshTrackerControl(ui)
    local enabled = TrackerEnabled()
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    ui.enableTracker:SetChecked(enabled == true)
    ui.enableTracker:SetEnabled(not InCombatLockdown() and enabled ~= nil and type(setter) == "function")
    if enabled == false then
        ui.enableTracker.label:SetTextColor(1, 0.3, 0.3)
    elseif enabled == true then
        ui.enableTracker.label:SetTextColor(1, 1, 1)
    else
        ui.enableTracker.label:SetTextColor(0.5, 0.5, 0.5)
    end
end

local function FitConfig(ui)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if width and height and width > 24 and height > 24 then
        ui:SetScale(math.min(1, (width - 24) / PANEL_WIDTH, (height - 24) / PANEL_HEIGHT))
    end
end

local modifierKeys = {
    SHIFT = true, LSHIFT = true, RSHIFT = true,
    CTRL = true, LCTRL = true, RCTRL = true,
    ALT = true, LALT = true, RALT = true,
}

local function CleanupKeyCapture(ui)
    ui.keyCapture:Hide()
    if not ui.keyCleanupPending or InCombatLockdown() then return end
    ui.keyCapture:EnableKeyboard(false)
    ui.keyCapture:SetPropagateKeyboardInput(true)
    ui.keyCleanupPending = nil
end

local function EndKeyCapture(ui)
    ui.capturingKey, ui.pendingKey, ui.pendingRawKey = false, nil, nil
    -- Hiding this ordinary frame releases input immediately, even in combat.
    -- Reset keyboard flags after combat; leave the visible key control alone.
    CleanupKeyCapture(ui)
    ui.castKey:SetText("Set cast key")
end

local function RefreshWeakAurasControls(ui)
    if not ui.weakAurasIntegrationEnabled then return end
    local integration = SH.WeakAurasIntegration
    local enabled = integration and integration.IsEnabled() or false
    local inCombat = InCombatLockdown()
    ui.weakAurasIntegrationEnabled:SetChecked(enabled)
    ui.weakAurasIntegrationEnabled:SetEnabled(integration ~= nil and not inCombat)
    ui.openWeakAuras:SetShown(enabled)
    ui.weakAurasSetup:SetShown(enabled)
    ui.weakAurasStatus:SetShown(enabled)
    ui.openWeakAuras:SetEnabled(enabled and not inCombat)
    local status = integration and integration.GetStatus()
    ui.weakAurasStatus:SetText(ui.weakAurasMessage or (status and status.message) or "")
    local help = ui.weakAurasHelpFrame
    if help then
        help.openWeakAuras:SetEnabled(enabled and not inCombat)
        if not enabled then help:Hide() end
    end
end

local function OpenWeakAuras(ui, help)
    local integration = SH.WeakAurasIntegration
    if not integration then return end
    local ok, message = integration.OpenWeakAuras()
    ui.weakAurasMessage = message
    RefreshWeakAurasControls(ui)
    if help then help.status:SetText(message or (ok and "WeakAuras is open. Paste the code into Custom Trigger.") or "WeakAuras could not be opened.") end
    if ok then ui:Hide() end
end

local function ShowWeakAurasHelp(ui)
    local integration = SH.WeakAurasIntegration
    if not integration or not integration.IsEnabled() then return end
    local help = ui.weakAurasHelpFrame
    if not help then
        help = CreateFrame("Frame", "StandAndHitWeakAurasHelp", ui, "BackdropTemplate")
        ui.weakAurasHelpFrame = help
        help:SetSize(760, 560)
        help:SetPoint("CENTER")
        help:SetFrameStrata("FULLSCREEN_DIALOG")
        help:SetFrameLevel(ui:GetFrameLevel() + 20)
        help:SetClampedToScreen(true)
        help:SetMovable(true)
        help:EnableMouse(true)
        help:RegisterForDrag("LeftButton")
        help:SetScript("OnDragStart", function(self) self:StartMoving() end)
        help:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        Skin(help, {0.035, 0.05, 0.07, 1}, {0.23, 0.33, 0.4, 1})
        if UISpecialFrames then table.insert(UISpecialFrames, "StandAndHitWeakAurasHelp") end
        local title = Label(help, "WeakAuras setup", "GameFontNormalLarge", accent)
        title:SetPoint("TOPLEFT", 22, -20)
        local intro = Label(help, "Want a WeakAura for your Hit Button? Choose the button below, then copy its trigger.", "GameFontHighlight")
        intro:SetPoint("TOPLEFT", 22, -56)
        intro:SetWidth(708)
        intro:SetWordWrap(true)
        help.buttonChoices = {}
        local function SelectButton(index)
            help.buttonIndex = index
            help.triggerCode = integration.GetTriggerCode(index) or ""
            help.code:SetText(help.triggerCode)
            help.code:SetCursorPosition(0)
            help.code:SetFocus()
            help.code:HighlightText()
            for i, button in ipairs(help.buttonChoices) do button:SetEnabled(i ~= index) end
            help.status:SetText("The code is selected. Press Ctrl+C to copy it, then Ctrl+V to paste it into Custom Trigger.")
        end
        for i = 1, 4 do
            local index = i
            local button = Button(help, "Hit Button " .. i, 167, 27)
            button:SetPoint("TOPLEFT", 22 + (i - 1) * 183, -91)
            button:SetScript("OnClick", function() SelectButton(index) end)
            help.buttonChoices[i] = button
        end
        help.instructions = Label(help,
            "1. Press Ctrl+C to copy the selected code.\n"
            .. "2. Click Open WeakAuras, then New > Icon.\n"
            .. "3. Open Trigger. Set Type to Custom and Event Type to Status.\n"
            .. "4. Set Check On to Every Frame, then paste into Custom Trigger.\n\n"
            .. "The icon shows when this Hit Button has a matching prepared rule. It follows your active profile. "
            .. "Remember to click Prepare in /snh after changing the rotation!", "GameFontHighlight")
        help.instructions:SetPoint("TOPLEFT", 22, -139)
        help.instructions:SetWidth(708)
        help.instructions:SetJustifyV("TOP")
        help.instructions:SetWordWrap(true)
        local panel = CreateFrame("Frame", nil, help, "BackdropTemplate")
        panel:SetPoint("TOPLEFT", 22, -287)
        panel:SetSize(716, 137)
        Skin(panel, {0.02, 0.03, 0.04, 1}, {0.23, 0.33, 0.4, 1})
        local code = CreateFrame("EditBox", nil, panel)
        help.code = code
        code:SetPoint("TOPLEFT", 12, -12)
        code:SetSize(690, 113)
        code:SetMultiLine(true)
        code:SetAutoFocus(false)
        code:SetMaxLetters(2048)
        code:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "")
        code:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(help.triggerCode or "") end
        end)
        code:SetScript("OnEscapePressed", function() help:Hide() end)
        code:SetScript("OnHide", function(self) self:ClearFocus() end)
        help.status = Label(help, "", "GameFontHighlightSmall")
        help.status:SetPoint("TOPLEFT", 23, -440)
        help.status:SetWidth(710)
        help.status:SetWordWrap(true)
        help.copy = Button(help, "Select code to copy", 190, 29)
        help.copy:SetPoint("BOTTOMLEFT", 22, 21)
        help.copy:SetScript("OnClick", function() SelectButton(help.buttonIndex or 1) end)
        help.openWeakAuras = Button(help, "Open WeakAuras", 170, 29)
        help.openWeakAuras:SetPoint("LEFT", help.copy, "RIGHT", 12, 0)
        help.openWeakAuras:SetScript("OnClick", function() OpenWeakAuras(ui, help) end)
        help.close = Button(help, "Close", 100, 29)
        help.close:SetPoint("BOTTOMRIGHT", -22, 21)
        help.close:SetScript("OnClick", function() help:Hide() end)
        local close = CreateFrame("Button", nil, help, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() help:Hide() end)
        help:SetScript("OnHide", function(self) self.code:ClearFocus(); self:StopMovingOrSizing() end)
        help.SelectButton = SelectButton
    end
    help:Show()
    help:Raise()
    help.SelectButton((ActiveRotation(ui).index or 1))
    RefreshWeakAurasControls(ui)
end

local function ShowMacroExamples(ui, section)
    local page = ui.examplesPage
    local reference = SH.MacroReference
    local targets = section == "targets"
    local entries = targets and reference.Targets or section == "rules" and reference.Rules or reference.Conditions
    if ui.weakAurasHelpFrame then ui.weakAurasHelpFrame:Hide() end
    ui.advancedSettings:Hide()
    page:Show()
    page.targets:SetEnabled(not targets)
    page.conditions:SetEnabled(section ~= "conditions")
    page.rules:SetEnabled(section ~= "rules")
    local y = 4
    for i, entry in ipairs(entries) do
        local line = page.lines[i]
        if not line then
            line = Label(page.body, "", "GameFontHighlight")
            line:SetWidth(870)
            line:SetJustifyV("TOP")
            line:SetWordWrap(true)
            page.lines[i] = line
        end
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 2, -y)
        line:SetText("|cff64cce0" .. entry.syntax .. "|r\n" .. entry.description
            .. (entry.example and ("\nExample: " .. entry.example) or ""))
        line:Show()
        y = y + line:GetStringHeight() + 17
    end
    for i = #entries + 1, #page.lines do page.lines[i]:Hide() end
    page.body:SetHeight(math.max(1, y))
    page.scroll:UpdateScrollChildRect()
    page.scroll:SetVerticalScroll(0)
    if page.scroll.ScrollBar then page.scroll.ScrollBar:SetValue(0) end
end

local function CreateAdvancedPage(ui)
    local page = CreateFrame("Frame", nil, ui, "BackdropTemplate")
    ui.advancedPage = page
    page:SetPoint("TOPLEFT", 20, -82 - PROFILE_ROW_HEIGHT)
    page:SetPoint("BOTTOMRIGHT", -20, 18)
    Skin(page, { 0.04, 0.06, 0.08, 1 }, { 0.15, 0.2, 0.25, 1 })
    page:Hide()
    local settingsContainer = CreateFrame("Frame", nil, page)
    settingsContainer:SetAllPoints()
    ui.advancedSettings = settingsContainer
    local settingsScroll = CreateFrame("ScrollFrame", nil, settingsContainer, "UIPanelScrollFrameTemplate")
    settingsScroll:SetPoint("TOPLEFT", 0, 0)
    settingsScroll:SetPoint("BOTTOMRIGHT", -28, 0)
    settingsScroll:SetSize(932, 700)
    ui.advancedScroll = settingsScroll
    local settings = CreateFrame("Frame", nil, settingsScroll)
    settings:SetSize(928, 957)
    settingsScroll:SetScrollChild(settings)
    ui.advancedContent = settings
    local title = Label(settings, "Advanced", "GameFontNormalLarge", accent)
    title:SetPoint("TOPLEFT", 19, -18)
    local intro = Label(settings, "Choose the extra options you want to use. Turning one off keeps your existing rules and settings.", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", 20, -53)
    intro:SetWidth(895)
    intro:SetWordWrap(true)
    local function Option(key, label, top, help)
        local check = CheckBox(settings, label, 21, -top, label, help, function(value)
            SH.rootDB[key] = value
            if key == "functionBlockDiagramsEnabled" then ui.ruleDiagramMode = value end
            RefreshRows(ui)
            if key == "functionBlockDiagramsEnabled" then
                SH:RefreshUIStatus()
                if SH.RefreshExplanation then SH:RefreshExplanation(true) end
            end
        end)
        local description = Label(settings, help, "GameFontHighlight")
        description:SetPoint("TOPLEFT", 53, -top - 31)
        description:SetWidth(858)
        description:SetWordWrap(true)
        check.description = description
        return check
    end
    ui.customTargetsEnabled = Option("customTargetsEnabled", "Custom Target", 95,
        "Adds Custom Target to Cast on. Enter a macro target such as @focus to cast on your focus while keeping your current target selected.")
    ui.customTargetExamples = Button(settings, "Custom Target examples", 200, 27)
    ui.customTargetExamples:SetPoint("TOPLEFT", 53, -164)
    ui.customTargetExamples:SetScript("OnClick", function() ShowMacroExamples(ui, "targets") end)
    ui.customConditionsEnabled = Option("customConditionsEnabled", "Custom Conditions", 215,
        "Adds Custom Conditions to Casting conditions. Enter a macro condition such as [harm,nodead] to use the rule only when your current target is alive and attackable.")
    ui.customConditionExamples = Button(settings, "Custom Conditions examples", 225, 27)
    ui.customConditionExamples:SetPoint("TOPLEFT", 53, -284)
    ui.customConditionExamples:SetScript("OnClick", function() ShowMacroExamples(ui, "conditions") end)
    ui.customRulesEnabled = Option("customRulesEnabled", "Custom Rules [BETA]", 335,
        "Adds Custom Rule under + Action. Each Hit Button can have one enabled Custom Rule with several command lines. It runs when its conditions match, then the same press checks the next matching rule.\nUse the visible Hit Button, Set cast key, or Controller. Custom Rules do not work through action-bar macros. Existing rules stay saved when this option is off.\nWhen commands run, automatic cast interruption does not apply. Add /stopcasting if they should interrupt your current cast.")
    ui.customRuleExamples = Button(settings, "Custom Rule examples", 200, 27)
    ui.customRuleExamples:SetPoint("TOPLEFT", 53, -452)
    ui.customRuleExamples:SetScript("OnClick", function() ShowMacroExamples(ui, "rules") end)
    ui.modifiersEnabled = Option("modifiersEnabled", "Modifiers", 502,
        "Shows Modifiers in Other casting options. Choose Ctrl, Alt, or Shift to skip a rule or prioritize it while held. Each choice starts at None. Existing configured rules remain active and editable when this option is off.")
    ui.functionBlockDiagramsEnabled = Option("functionBlockDiagramsEnabled", "Function Block Diagrams [BETA]", 607,
        "Show your rules as connected blocks. Click a condition to edit it, or add AND, OR, and NOT conditions from the diagram. You can switch between text and diagram views in the rotation explanation too.")
    local weakAurasHelp = "Check this to let WeakAuras read your prepared Hit Buttons. The buttons below will open WeakAuras and show you where to paste the trigger."
    ui.weakAurasIntegrationEnabled = CheckBox(settings, "WeakAuras integration [BETA]", 21, -727,
        "WeakAuras integration", weakAurasHelp, function(value)
            local integration = SH.WeakAurasIntegration
            if integration then
                local ok, message = integration.SetEnabled(value)
                ui.weakAurasMessage = not ok and message or nil
            end
            RefreshWeakAurasControls(ui)
        end)
    local weakAurasDescription = Label(settings, weakAurasHelp, "GameFontHighlight")
    weakAurasDescription:SetPoint("TOPLEFT", 53, -761)
    weakAurasDescription:SetWidth(858)
    weakAurasDescription:SetWordWrap(true)
    ui.openWeakAuras = Button(settings, "Open WeakAuras", 170, 29)
    ui.openWeakAuras:SetPoint("TOPLEFT", 53, -818)
    ui.openWeakAuras:SetScript("OnClick", function() OpenWeakAuras(ui) end)
    ui.weakAurasSetup = Button(settings, "Setup and copy trigger", 200, 29)
    ui.weakAurasSetup:SetPoint("LEFT", ui.openWeakAuras, "RIGHT", 12, 0)
    ui.weakAurasSetup:SetScript("OnClick", function() ShowWeakAurasHelp(ui) end)
    ui.weakAurasStatus = Label(settings, "", "GameFontHighlightSmall")
    ui.weakAurasStatus:SetPoint("TOPLEFT", 53, -863)
    ui.weakAurasStatus:SetWidth(858)
    ui.weakAurasStatus:SetWordWrap(true)
    RefreshWeakAurasControls(ui)
    local examples = CreateFrame("Frame", nil, page)
    examples:SetAllPoints()
    examples:Hide()
    ui.examplesPage = examples
    local heading = Label(examples, "Macro examples", "GameFontNormalLarge", accent)
    heading:SetPoint("TOPLEFT", 20, -18)
    local back = Button(examples, "Back to Advanced", 164, 25)
    back:SetPoint("TOPRIGHT", -18, -15)
    back:SetScript("OnClick", function()
        examples:Hide()
        settingsContainer:Show()
    end)
    examples.targets = Button(examples, "Macro targets", 149, 26)
    examples.targets:SetPoint("TOPLEFT", 19, -53)
    examples.conditions = Button(examples, "Macro conditions", 159, 26)
    examples.conditions:SetPoint("LEFT", examples.targets, "RIGHT", 6, 0)
    examples.rules = Button(examples, "Macro commands", 159, 26)
    examples.rules:SetPoint("LEFT", examples.conditions, "RIGHT", 6, 0)
    examples.targets:SetScript("OnClick", function() ShowMacroExamples(ui, "targets") end)
    examples.conditions:SetScript("OnClick", function() ShowMacroExamples(ui, "conditions") end)
    examples.rules:SetScript("OnClick", function() ShowMacroExamples(ui, "rules") end)
    examples.scroll = CreateFrame("ScrollFrame", nil, examples, "UIPanelScrollFrameTemplate")
    examples.scroll:SetPoint("TOPLEFT", 20, -96)
    examples.scroll:SetSize(892, 584)
    examples.body = CreateFrame("Frame", nil, examples.scroll)
    examples.body:SetWidth(885)
    examples.scroll:SetScrollChild(examples.body)
    examples.lines = {}
    settingsScroll:UpdateScrollChildRect()
end

local function SelectAdvanced(ui)
    EndKeyCapture(ui)
    if ui.choiceMenu then ui.choiceMenu:Hide() end
    if SH.transferUI then SH.transferUI:Hide() end
    for _, row in ipairs(ui.rows) do ClearRowFocus(row) end
    ui.rotationPage:Hide()
    ui.advancedPage:Show()
    ui.advancedSettings:Show()
    ui.examplesPage:Hide()
    ui.customTargetsEnabled:SetChecked(SH.rootDB.customTargetsEnabled == true)
    ui.customConditionsEnabled:SetChecked(SH.rootDB.customConditionsEnabled == true)
    ui.customRulesEnabled:SetChecked(SH.rootDB.customRulesEnabled == true)
    ui.modifiersEnabled:SetChecked(SH.rootDB.modifiersEnabled == true)
    ui.functionBlockDiagramsEnabled:SetChecked(SH.rootDB.functionBlockDiagramsEnabled == true)
    ui.functionBlockDiagramsEnabled:SetEnabled(SH.Diagram ~= nil and SH.DiagramUI ~= nil)
    ui.weakAurasMessage = nil
    RefreshWeakAurasControls(ui)
    SH:RefreshUIStatus()
end

local function StartKeyCapture(ui)
    if InCombatLockdown() then
        ShowResult(ui, false, "Leave combat to set the cast key.")
        return
    end
    if not IsEnabled(ActiveRotation(ui)) then
        ShowResult(ui, false, "Enable " .. RotationLabel(ActiveRotation(ui)) .. " before setting its cast key.")
        return
    end
    if ui.capturingKey then
        EndKeyCapture(ui)
        SH:RefreshUIStatus()
        return
    end
    for _, row in ipairs(ui.rows) do
        ClearRowFocus(row)
    end
    CleanupKeyCapture(ui)
    ui.capturingKey = true
    ui.keyCleanupPending = true
    ui.castKey:SetText("Press a key...")
    ui.keyCapture:SetPropagateKeyboardInput(false)
    ui.keyCapture:EnableKeyboard(true)
    ui.keyCapture:Show()
    SH:RefreshUIStatus()
end

local function SelectRotation(ui, index)
    local rotation = SH.GetRotation and SH:GetRotation(index) or (index == 1 and SH)
    if not rotation then return end
    if ui.weakAurasHelpFrame then ui.weakAurasHelpFrame:Hide() end
    ui.advancedPage:Hide()
    ui.rotationPage:Show()
    if rotation == ui.rotation then
        SH:RefreshUIStatus()
        return
    end
    if SH.transferUI then SH.transferUI:Hide() end
    ui.rotationScrolls[ActiveRotation(ui).index or 1] = {
        priority = ui.scroll:GetVerticalScroll() or 0,
        editor = ui.editorScroll:GetVerticalScroll() or 0,
    }
    SaveDraft(ui)
    EndKeyCapture(ui)
    for _, row in ipairs(ui.rows) do
        ClearRowFocus(row)
    end
    SH.activeRotationIndex = index
    ui.rotation = rotation
    ui.draft = CopyRules(rotation:GetDraftRules())
    ui.selectedIndex = ui.selectedIndices[index] or 1
    ui.message, ui.messageOK = nil, nil
    RefreshRows(ui)
    local offsets = ui.rotationScrolls[index] or {}
    ui.scroll:SetVerticalScroll(offsets.priority or 0)
    if ui.scroll.ScrollBar then ui.scroll.ScrollBar:SetValue(offsets.priority or 0) end
    ScrollToSelection(ui)
    SetEditorOffset(ui, offsets.editor or 0)
    SH:RefreshUIStatus()
end

local function ProfileNames()
    if SH.GetProfileNames then return SH:GetProfileNames() end
    return {"Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5"}
end

local function ProfileIndex()
    return SH.GetActiveProfileIndex and SH:GetActiveProfileIndex() or 1
end

function SH:RefreshProfileUI()
    local ui = SH.ui
    if not ui then return end
    if ui.weakAurasHelpFrame then ui.weakAurasHelpFrame:Hide() end
    EndKeyCapture(ui)
    if ui.choiceMenu then ui.choiceMenu:Hide() end
    if ui.profileRenameDialog then ui.profileRenameDialog:Hide() end
    if SH.transferUI then SH.transferUI:Hide() end
    if SH.explanationUI then SH.explanationUI:Hide() end
    if SH.controllerUI then SH.controllerUI:Hide() end
    for _, row in ipairs(ui.rows) do ClearRowFocus(row) end
    ui.rotation = SH.GetActiveRotation and SH:GetActiveRotation() or SH
    ui.profileIndex = ProfileIndex()
    ui.draft = CopyRules(ui.rotation:GetDraftRules())
    ui.selectedIndices, ui.rotationScrolls = {}, {}
    ui.selectedIndex = 1
    ui.message, ui.messageOK = nil, nil
    ui.advancedPage:Hide()
    ui.rotationPage:Show()
    RefreshRows(ui)
    ui.scroll:SetVerticalScroll(0)
    if ui.scroll.ScrollBar then ui.scroll.ScrollBar:SetValue(0) end
    SetEditorOffset(ui, 0)
    SH:RefreshUIStatus()
end

local function SelectProfile(ui, index)
    if InCombatLockdown() then
        ShowResult(ui, false, "Leave combat to switch profiles.")
        return
    end
    if index == ProfileIndex() then return end
    if not SH.SwitchProfile then return end
    SaveDraft(ui)
    EndKeyCapture(ui)
    local ok, message = SH:SwitchProfile(index)
    if ok then SH:RefreshProfileUI() end
    ShowResult(ui, ok, message)
end

local function ShowProfileRename(ui)
    if InCombatLockdown() then
        ShowResult(ui, false, "Leave combat to rename a profile.")
        return
    end
    if not SH.RenameProfile then return end
    EndKeyCapture(ui)
    if ui.choiceMenu then ui.choiceMenu:Hide() end
    local dialog = ui.profileRenameDialog
    if not dialog then
        dialog = CreateFrame("Frame", "StandAndHitProfileRename", ui, "BackdropTemplate")
        ui.profileRenameDialog = dialog
        dialog:SetSize(390, 170)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(ui:GetFrameLevel() + 40)
        dialog:EnableMouse(true)
        Skin(dialog, { 0.035, 0.05, 0.07, 1 }, { 0.36, 0.78, 0.88, 1 })
        if UISpecialFrames then table.insert(UISpecialFrames, "StandAndHitProfileRename") end
        local title = Label(dialog, "Rename profile", "GameFontNormalLarge", accent)
        title:SetPoint("TOPLEFT", 20, -16)
        dialog.name = EditBox(dialog, 344)
        dialog.name:SetPoint("TOPLEFT", 23, -49)
        dialog.name:SetMaxLetters(40)
        dialog.message = Label(dialog, "", "GameFontHighlightSmall")
        dialog.message:SetPoint("TOPLEFT", 22, -80)
        dialog.message:SetWidth(344)
        dialog.message:SetWordWrap(true)
        dialog.save = Button(dialog, "Save", 104, 27)
        dialog.save:SetPoint("BOTTOMRIGHT", -133, 17)
        dialog.cancel = Button(dialog, "Cancel", 104, 27)
        dialog.cancel:SetPoint("BOTTOMRIGHT", -22, 17)
        local function SaveName()
            if InCombatLockdown() then dialog:Hide(); return end
            if dialog.profileIndex ~= ProfileIndex() then dialog:Hide(); return end
            local ok, message = SH:RenameProfile(dialog.profileIndex, dialog.name:GetText())
            if ok then
                dialog:Hide()
                SH:RefreshUIStatus()
            else
                dialog.message:SetText(message or "Enter a profile name.")
                dialog.message:SetTextColor(1, 0.55, 0.55)
            end
        end
        dialog.save:SetScript("OnClick", SaveName)
        dialog.cancel:SetScript("OnClick", function() dialog:Hide() end)
        dialog.name:SetScript("OnEnterPressed", SaveName)
        dialog.name:SetScript("OnEscapePressed", function() dialog:Hide() end)
        dialog:SetScript("OnHide", function() dialog.name:ClearFocus() end)
    end
    dialog.profileIndex = ProfileIndex()
    dialog.name:SetText(ProfileNames()[dialog.profileIndex] or ("Profile " .. dialog.profileIndex))
    dialog.message:SetText("Up to 40 characters.")
    dialog.message:SetTextColor(0.82, 0.85, 0.9)
    dialog:Show()
    dialog:Raise()
    dialog.name:SetFocus()
    dialog.name:HighlightText()
end

local function ShowTransfer(ui, mode)
    EndKeyCapture(ui)
    if ui.choiceMenu then ui.choiceMenu:Hide() end
    for _, row in ipairs(ui.rows) do ClearRowFocus(row) end
    SaveDraft(ui)
    local rotation = ActiveRotation(ui)
    SH:ShowRotationTransfer(mode, rotation, CopyRules(ui.draft), rotation.db.preventClipping ~= false,
        function(data)
            if ActiveRotation(ui) ~= rotation or not ui:IsShown() then
                return false, "Open Import again from the rotation tab you want to replace."
            end
            ui.draft = CopyRules(data.rules)
            rotation.db.preventClipping = data.preventClipping
            ui.selectedIndex = 1
            ui.selectedIndices[rotation.index or 1] = 1
            ui.rotationScrolls[rotation.index or 1] = nil
            SaveDraft(ui)
            RefreshRows(ui)
            ui.scroll:SetVerticalScroll(0)
            if ui.scroll.ScrollBar then ui.scroll.ScrollBar:SetValue(0) end
            SetEditorOffset(ui, 0)
            local message = "Imported " .. #ui.draft .. " rules into " .. RotationLabel(rotation)
                .. ". Check your trackers, then Prepare outside combat."
            ShowResult(ui, true, message)
            return true, message
        end)
end

local function CreateConfig()
    local ui = CreateFrame("Frame", "StandAndHitConfig", UIParent, "BackdropTemplate")
    SH.ui = ui
    ui:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    ui:SetPoint("CENTER")
    ui:SetFrameStrata("DIALOG")
    ui:SetClampedToScreen(true)
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", function(self) self:StartMoving() end)
    ui:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Skin(ui, { 0.035, 0.05, 0.07, 0.99 }, { 0.23, 0.33, 0.4, 1 })
    if UISpecialFrames then table.insert(UISpecialFrames, "StandAndHitConfig") end
    ui.rotation = ActiveRotation()
    ui.draft = CopyRules(ui.rotation:GetDraftRules())
    ui.rows = {}
    ui.priorityButtons = {}
    ui.selectedIndices = {}
    ui.rotationScrolls = {}
    ui.selectedIndex = 1
    ui.profileIndex = ProfileIndex()
    ui.SelectRule = SelectRule

    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = getMetadata and getMetadata(addonName, "Version")
    ui.title = Label(ui, "Stand and Hit" .. (version and " v" .. version or ""), "GameFontNormalLarge", accent)
    ui.title:SetPoint("TOPLEFT", 22, -17)
    local page = CreateFrame("Frame", nil, ui)
    page:SetPoint("TOPLEFT", 0, -PROFILE_ROW_HEIGHT)
    page:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.rotationPage = page
    ui.tabs = {}
    for index, text in ipairs({"Hit Button", "Hit Button 2", "Hit Button 3", "Hit Button 4"}) do
        local tab = Button(ui, text, 108, 28)
        tab:SetPoint("TOPLEFT", 300 + (index - 1) * 112, -13)
        tab:SetScript("OnClick", function() SelectRotation(ui, index) end)
        Tooltip(tab, text, "Edit this rotation's spell rules, casting button, macro, and key.")
        ui.tabs[index] = tab
    end
    ui.advancedTab = Button(ui, "Advanced", 90, 28)
    ui.advancedTab:SetPoint("TOPLEFT", 749, -13)
    ui.advancedTab:SetScript("OnClick", function() SelectAdvanced(ui) end)
    local profileLabel = Label(ui, "Profile", "GameFontHighlightSmall")
    profileLabel:SetPoint("TOPLEFT", 23, -55)
    ui.profile = Button(ui, "Profile 1", 280, 26)
    ui.profile:SetPoint("TOPLEFT", 73, -47)
    ui.profile.menuWidth = 360
    MarkDropdown(ui.profile)
    ui.profile:SetScript("OnClick", function()
        if InCombatLockdown() then
            ShowResult(ui, false, "Leave combat to switch profiles.")
            return
        end
        local choices = {}
        for index, name in ipairs(ProfileNames()) do
            choices[#choices + 1] = {value = index, label = name}
        end
        ChoiceMenu(ui, ui.profile, choices, ProfileIndex(), function(index) SelectProfile(ui, index) end)
    end)
    Tooltip(ui.profile, function() return ProfileNames()[ProfileIndex()] or "Rotation profiles" end,
        "Each of your five profiles saves four Hit Button rotations. Switch profiles outside combat to use that profile's rules and settings with the same four buttons.")
    ui.renameProfile = Button(ui, "Rename", 90, 26)
    ui.renameProfile:SetPoint("LEFT", ui.profile, "RIGHT", 6, 0)
    ui.renameProfile:SetScript("OnClick", function() ShowProfileRename(ui) end)
    local profileHelp = Label(ui, "Four Hit Buttons per profile.", "GameFontHighlightSmall")
    profileHelp:SetPoint("LEFT", ui.renameProfile, "RIGHT", 12, 0)
    CreateAdvancedPage(ui)
    ui.enableRotation = CheckBox(page, "Enable Hit Button 2", 780, -14,
        function() return "Enable " .. RotationLabel(ActiveRotation(ui)) end,
        "Enable this rotation, with its own rules, button, macro, and cast key. Disable it to stop its casting and release its key. Draft rules are kept. Change this outside combat.", function(value)
        local rotation = ActiveRotation(ui)
        if InCombatLockdown() then
            ShowResult(ui, false, "Leave combat to enable or disable " .. RotationLabel(rotation) .. ".")
            return
        end
        EndKeyCapture(ui)
        local ok, message = rotation:SetRotationEnabled(value)
        ShowResult(ui, ok, message)
    end)
    ui.enableSecond = ui.enableRotation
    local subtitle = Label(page, "Your first matching rule wins (that means the spell you want to spam goes last).\nEdit the draft, then Prepare to apply it.", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", 23, -49)
    local close = CreateFrame("Button", nil, ui, "UIPanelCloseButton")
    ui.close = close
    ui.close = close
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() ui:Hide() end)

    local function AddRule(action)
        if #ui.draft >= MAX_RULES then return end
        if action == "Custom Rule" and HasEnabledCustomRule(ui) then
            ShowResult(ui, false, "Only one Custom Rule can be enabled per Hit Button. Disable the current Custom Rule before adding another.")
            return
        end
        local insertIndex = #ui.draft + 1
        local condition = action and "always" or "present"
        local lastIndex = #ui.draft
        while lastIndex > 0 and ui.draft[lastIndex].enabled == false do lastIndex = lastIndex - 1 end
        local last = ui.draft[lastIndex]
        if last and last.condition == "always" and not last.skipCooldown and not last.manualCooldown and not last.pingDelay
            and not last.skipIfNotCasted and not last.skipIfImmune and not last.skipOutOfRange and not last.outOfCombatOnly and not last.inCombatOnly
            and not last.advanceOnToggle and not last.skipModifier
            and last.unit ~= "focustarget" and last.unit ~= "custom" and last.customCondition == nil and not last.targetCasting and not last.totemCondition
            and not AttackCommand(last.spell) and last.customRule == nil and last.comboPoints == nil and last.hawkCount == nil and #(last.resourceConditions or {}) == 0
            and #(last.healthConditions or {}) == 0
            and #(last.stackConditions or {}) == 0
            and #(last.logicConditions or {}) == 0 and last.primaryCondition == nil
            and #(last.andConditions or {}) == 0 and #(last.notConditions or {}) == 0 then
            insertIndex = lastIndex
            if rangedNames[tonumber(action)] then condition = "present" end
        end
        if action == "Custom Rule" then
            for index, existing in ipairs(ui.draft) do
                if existing.enabled ~= false and SH.Model.IsAutoAttack(existing.spell) then
                    insertIndex = math.min(insertIndex, index)
                    break
                end
            end
        end
        table.insert(ui.draft, insertIndex, { spell = action or "", customRule = action == "Custom Rule" and "" or nil, aura = "", condition = condition, unit = "target",
            skipCooldown = false, oncePerProc = false, stopCasting = false, stopWhenInvalid = false,
            pingDelay = false, pingDelayMS = 100, manualCooldown = false, manualCooldownSeconds = 0, skipIfNotCasted = false,
            skipIfImmune = false, skipOutOfRange = false, outOfCombatOnly = false, inCombatOnly = false, advanceOnToggle = false,
            useOr = false, orAura = "", orCondition = "present", andConditions = {}, orConditions = {}, notConditions = {} })
        ui.selectedIndex = insertIndex
        DraftChanged(ui)
        RefreshRows(ui)
        if action == "Custom Rule" then
            if ui.ruleDiagramMode then DiagramFocus(ui, {conditionKey = "action"}) else ui.rows[insertIndex].customRuleText:SetFocus() end
        elseif not action then ui.rows[insertIndex].spell:SetFocus()
        elseif condition ~= "always" then ui.rows[insertIndex].aura:SetFocus() end
    end
    ui.add = Button(page, "+ Add spell", 109, 27)
    ui.add:SetFrameLevel(ui:GetFrameLevel() + 3)
    ui.add:SetPoint("TOPLEFT", 28, -493)
    ui.add:SetScript("OnClick", function() AddRule() end)
    ui.addAction = Button(page, "+ Action", 100, 27)
    ui.addAction:SetFrameLevel(ui:GetFrameLevel() + 3)
    ui.addAction:SetPoint("LEFT", ui.add, "RIGHT", 5, 0)
    MarkDropdown(ui.addAction)
    ui.addAction:SetScript("OnClick", function(self)
        local choices = {
            {value = "Auto Attack", label = "Auto Attack"},
            {value = "5019", label = DisplaySpell({spell = "5019"}) .. " (wand)"},
            {value = "75", label = DisplaySpell({spell = "75"}) .. " (hunter)"},
            {value = "Pet Attack", label = "Pet Attack"},
        }
        if SH.rootDB.customRulesEnabled then
            choices[#choices + 1] = {value = "Custom Rule", label = "Custom Rule", enabled = not HasEnabledCustomRule(ui),
                tooltipTitle = "Custom Rule", reason = "One enabled Custom Rule per Hit Button. Put several commands on separate lines, or disable the existing Custom Rule before adding another."}
        end
        ChoiceMenu(ui, self, choices, nil, AddRule)
    end)
    ui.count = Label(page, "", "GameFontDisableSmall")
    ui.count:SetPoint("TOPRIGHT", -29, -78)

    ui.import = Button(page, "Import", 106, 25)
    ui.import:SetPoint("TOPRIGHT", -143, -45)
    ui.import:SetScript("OnClick", function() ShowTransfer(ui, "import") end)
    Tooltip(ui.import, "Import rotation", "Paste a shared rotation to replace this tab's draft. Review it and Prepare outside combat to apply it.")
    ui.export = Button(page, "Export", 106, 25)
    ui.export:SetPoint("TOPRIGHT", -28, -45)
    ui.export:SetScript("OnClick", function() ShowTransfer(ui, "export") end)
    Tooltip(ui.export, "Export rotation", "Copy this tab's draft rules and Protect channels setting to share or import into another tab.")

    local priorityPanel = CreateFrame("Frame", nil, page, "BackdropTemplate")
    priorityPanel:SetPoint("TOPLEFT", 20, -94)
    priorityPanel:SetSize(232, 500)
    Skin(priorityPanel, { 0.02, 0.03, 0.04, 1 }, { 0.15, 0.2, 0.25, 1 })
    local priorityTitle = Label(priorityPanel, "Spell priority", "GameFontNormal", accent)
    priorityTitle:SetPoint("TOPLEFT", 12, -12)
    ui.scroll = CreateFrame("ScrollFrame", nil, priorityPanel, "UIPanelScrollFrameTemplate")
    ui.scroll:SetPoint("TOPLEFT", 8, -38)
    ui.scroll:SetSize(202, 348)
    ui.scrollChild = CreateFrame("Frame", nil, ui.scroll)
    ui.scrollChild:SetWidth(202)
    ui.scroll:SetScrollChild(ui.scrollChild)
    ui.editor = CreateFrame("Frame", nil, page, "BackdropTemplate")
    ui.editor:SetPoint("TOPLEFT", 266, -94)
    ui.editor:SetSize(714, 500)
    Skin(ui.editor, { 0.04, 0.06, 0.08, 1 }, { 0.15, 0.2, 0.25, 1 })
    ui.editorScroll = CreateFrame("ScrollFrame", nil, ui.editor, "UIPanelScrollFrameTemplate")
    ui.editorScroll:SetPoint("TOPLEFT", 0, 0)
    ui.editorScroll:SetSize(714, 500)
    ui.editorBody = CreateFrame("Frame", nil, ui.editorScroll)
    ui.editorBody:SetSize(714, 500)
    ui.editorScroll:SetScrollChild(ui.editorBody)
    -- The full-width controls end at x=966. This bar ends at x=996 inside the window.
    if ui.editorScroll.ScrollBar then
        local bar = ui.editorScroll.ScrollBar
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", ui.editorScroll, "TOPRIGHT", 2, -16)
        bar:SetPoint("BOTTOMLEFT", ui.editorScroll, "BOTTOMRIGHT", 2, 16)
        bar:SetWidth(14)
    end
    ui.editorScroll:EnableMouseWheel(true)
    ui.editorScroll:SetScript("OnMouseWheel", function(self, delta)
        local row = ui.rows[ui.selectedIndex]
        if row then ClearRowFocus(row) end
        SetEditorOffset(ui, (self:GetVerticalScroll() or 0) - delta * 64)
    end)
    ui.editorScroll:HookScript("OnVerticalScroll", function()
        if ui.choiceMenu then ui.choiceMenu:Hide() end
        local row = ui.rows[ui.selectedIndex]
        if row then ClearRowFocus(row) end
    end)
    CreateRuleDiagramControls(ui)
    ui.empty = Label(ui.editor, "Add a spell or action to start your rotation.", "GameFontHighlight")
    ui.empty:SetPoint("CENTER", 0, 0)
    ui.moveUp = Button(page, "Up", 64, 25)
    ui.moveUp:SetPoint("TOPLEFT", 28, -561)
    ui.moveUp:SetScript("OnClick", function()
        local row = ui.rows[ui.selectedIndex]
        if row and #ui.draft > 0 then row.up:Click() end
    end)
    ui.moveDown = Button(page, "Down", 64, 25)
    ui.moveDown:SetPoint("LEFT", ui.moveUp, "RIGHT", 5, 0)
    ui.moveDown:SetScript("OnClick", function()
        local row = ui.rows[ui.selectedIndex]
        if row and #ui.draft > 0 then row.down:Click() end
    end)
    ui.remove = Button(page, "Remove", 76, 25)
    ui.remove:SetPoint("LEFT", ui.moveDown, "RIGHT", 5, 0)
    ui.remove:SetScript("OnClick", function()
        local row = ui.rows[ui.selectedIndex]
        if row and #ui.draft > 0 then row.remove:Click() end
    end)

    ui.copyRule = Button(page, "Copy Rule", 107, 27)
    ui.copyRule:SetFrameLevel(ui:GetFrameLevel() + 3)
    ui.copyRule:SetPoint("TOPLEFT", 28, -527)
    ui.copyRule:SetScript("OnClick", function()
        local rule = ui.draft[ui.selectedIndex]
        if not rule then return end
        if ui.choiceMenu then ui.choiceMenu:Hide() end
        ClearRowFocus(ui.rows[ui.selectedIndex])
        ui.copiedRule = SH.Model.Copy(rule)
        ui.pasteRule:SetEnabled(#ui.draft < MAX_RULES)
        ShowResult(ui, true, "Rule copied. Select a Hit Button tab, then click Paste Rule.")
    end)
    Tooltip(ui.copyRule, "Copy Rule", "Copy the selected spell and all its settings. The copy is available across Hit Button tabs and profiles until you reload or log out.")
    ui.pasteRule = Button(page, "Paste Rule", 107, 27)
    ui.pasteRule:SetFrameLevel(ui:GetFrameLevel() + 3)
    ui.pasteRule:SetPoint("LEFT", ui.copyRule, "RIGHT", 5, 0)
    ui.pasteRule:SetScript("OnClick", function()
        if not ui.copiedRule or #ui.draft >= MAX_RULES then return end
        if ui.choiceMenu then ui.choiceMenu:Hide() end
        local row = ui.rows[ui.selectedIndex]
        if row then ClearRowFocus(row) end
        local index = math.min(ui.selectedIndex, #ui.draft) + 1
        local copy = SH.Model.Copy(ui.copiedRule)
        local disabledCopy = copy.customRule ~= nil and copy.enabled ~= false and HasEnabledCustomRule(ui)
        if disabledCopy then copy.enabled = false end
        table.insert(ui.draft, index, copy)
        ui.selectedIndex = index
        DraftChanged(ui)
        RefreshRows(ui)
        ShowResult(ui, true, disabledCopy and ("Pasted as disabled Rule " .. index .. ". This Hit Button already has an enabled Custom Rule. Disable that rule before enabling this copy.")
            or ("Pasted as Rule " .. index .. ". Use Up or Down to set its priority, then Prepare outside combat."))
    end)
    Tooltip(ui.pasteRule, "Paste Rule", "Add a copy below the selected rule in this Hit Button's draft. Use Up and Down to adjust its priority, then Prepare outside combat.")

    ui.preventClipping = CheckBox(page, "Protect channels", 20, -602, "Protect channels", "While you are channeling, a press clears any queued spell without starting a new cast or stopping the current channel. This setting takes effect when you Prepare the draft.", function(value)
        ActiveRotation(ui).db.preventClipping = value
        DraftChanged(ui)
    end)
    ui.showButton = CheckBox(page, "Show Hit Button", 207, -602, "Casting button", "Show or hide this rotation's casting button. Outside combat, hold Shift and drag it with the left mouse button to move it.", function(value)
        local rotation = ActiveRotation(ui)
        if not IsEnabled(rotation) then return end
        rotation.db.showButton = value
        rotation:SetButtonVisible(value)
        SH:RefreshUIStatus()
    end)
    ui.autoPrepare = CheckBox(page, "Restore at login", 410, -602, "Restore at login", "Restore the last successfully prepared rules and channel-protection setting when the addon starts and the required trackers are available. Unprepared draft edits are not applied.", function(value)
        ActiveRotation(ui).db.autoPrepare = value
        SH:RefreshUIStatus()
    end)
    ui.hideUIErrors = CheckBox(page, "Hide casting errors", 610, -602, "Hide casting errors", "Hide common red casting error text and its character voice lines and error sounds, such as not enough energy, rage, or mana, for 0.2 seconds after this Hit Button attempts a spell. Normal casting errors return when you stop pressing. Other messages and audio are unchanged. This preference takes effect immediately for this rotation; no Prepare is needed.", function(value)
        ActiveRotation(ui).db.hideUIErrors = value
        SH:RefreshUIStatus()
    end)

    ui.statusScroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    ui.statusScroll:SetPoint("TOPLEFT", 24, -674)
    ui.statusScroll:SetSize(924, 48)
    ui.statusBody = CreateFrame("Frame", nil, ui.statusScroll)
    ui.statusBody:SetSize(920, 54)
    ui.statusScroll:SetScrollChild(ui.statusBody)
    ui.status = Label(ui.statusBody, "", "GameFontHighlightSmall")
    ui.status:SetPoint("TOPLEFT")
    ui.status:SetWidth(918)
    ui.status:SetJustifyV("TOP")
    ui.status:SetWordWrap(true)

    ui.castKey = Button(page, "Set cast key", 120, 27)
    ui.castKey:SetPoint("TOPLEFT", 22, -635)
    ui.castKey:SetScript("OnClick", function() StartKeyCapture(ui) end)
    Tooltip(ui.castKey, "Direct cast key", "Choose a keyboard key for this rotation; it can be the same key as its action-bar macro. It allows Stop current cast and Stop if buffs change. Prepared rule modifiers also work with this key, including combinations. Click Prepare after changing modifiers. If a combination belongs to another Hit Button, choose another key. Press Escape to cancel. Set keys outside combat.")
    ui.keyCapture = CreateFrame("Frame", nil, page)
    ui.keyCapture:SetAllPoints(ui)
    ui.keyCapture:SetFrameLevel(ui:GetFrameLevel() + 20)
    ui.keyCapture:Hide()
    ui.keyCapture:SetScript("OnKeyDown", function(_, key)
        if not ui.capturingKey then return end
        if InCombatLockdown() or key == "ESCAPE" then
            EndKeyCapture(ui)
            SH:RefreshUIStatus()
            return
        end
        if modifierKeys[key] or ui.pendingKey or type(key) ~= "string" or key == "" then return end
        local prefix = (IsControlKeyDown() and "CTRL-" or "")
            .. (IsAltKeyDown() and "ALT-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "")
        ui.pendingKey, ui.pendingRawKey = prefix .. key, key
        ui.castKey:SetText("Release key...")
        SH:RefreshUIStatus()
    end)
    ui.keyCapture:SetScript("OnKeyUp", function(_, key)
        if not ui.capturingKey or key ~= ui.pendingRawKey then return end
        local chosen = ui.pendingKey
        -- Finish the capture press before enabling the binding it selected.
        EndKeyCapture(ui)
        if InCombatLockdown() then SH:RefreshUIStatus(); return end
        local ok, message = ActiveRotation(ui):SetDirectKey(chosen)
        ShowResult(ui, ok, message)
    end)
    ui.clearKey = Button(page, "Clear key", 100, 27)
    ui.clearKey:SetPoint("LEFT", ui.castKey, "RIGHT", 9, 0)
    ui.clearKey:SetScript("OnClick", function()
        EndKeyCapture(ui)
        local rotation = ActiveRotation(ui)
        if not IsEnabled(rotation) then return end
        local ok, message = rotation:ClearDirectKey()
        ShowResult(ui, ok, message)
    end)
    Tooltip(ui.clearKey, "Clear direct cast key", "Remove this rotation's direct cast key and its modifier combinations, restoring their normal bindings. Its action-bar macro can still cast the rotation.")
    ui.castKeyLabel = Label(page, "", "GameFontHighlightSmall", { 0.69, 0.75, 0.8 })
    ui.castKeyLabel:SetPoint("LEFT", ui.clearKey, "RIGHT", 12, 0)
    ui.castKeyLabel:SetWidth(526)
    ui.castKeyLabel:SetJustifyH("LEFT")

    ui.controller = Button(page, "Controller", 144, 27)
    ui.controller:SetPoint("TOPRIGHT", -24, -635)
    ui.controller:SetScript("OnClick", function()
        EndKeyCapture(ui)
        if ui.choiceMenu then ui.choiceMenu:Hide() end
        for _, row in ipairs(ui.rows) do ClearRowFocus(row) end
        if SH.ShowControllerUI then
            local ok, message = SH:ShowControllerUI()
            if not ok then ShowResult(ui, false, message) end
        end
    end)
    Tooltip(ui.controller, "Controller settings", "Assign separate controller buttons to the four Hit Buttons, and choose combat-start or critical-hit rumble. Your keyboard cast keys stay unchanged. Change controller settings outside combat.")

    local help = Label(page, "For setup directions, read README.txt in Interface/AddOns/StandAndHit. Use fresh keypresses to switch spells.", "GameFontHighlightSmall", { 0.69, 0.75, 0.8 })
    help:SetPoint("TOPLEFT", 24, -731)
    help:SetWidth(950)
    help:SetJustifyV("TOP")

    ui.trackers = Button(page, "Open trackers", 128, 29)
    ui.trackers:SetPoint("BOTTOMLEFT", 22, 19)
    ui.trackers:SetScript("OnClick", function()
        local ok, message = SH:OpenTrackerSettings()
        ShowResult(ui, ok, message)
    end)
    Tooltip(ui.trackers, "Native aura trackers", "Open the game's tracker settings to set up Tracked aura, Target debuff, and native cooldown conditions.")

    ui.macro = Button(page, "Drag macro to bar", 154, 29)
    ui.macro:SetPoint("LEFT", ui.trackers, "RIGHT", 9, 0)
    ui.macro:SetScript("OnClick", function()
        local rotation = ActiveRotation(ui)
        if not IsEnabled(rotation) then
            ShowResult(ui, false, "Enable " .. RotationLabel(rotation) .. " before creating its macro.")
            return
        end
        local ok, message = rotation:CreateOrPickupMacro()
        ShowResult(ui, ok, message)
    end)
    Tooltip(ui.macro, "Rotation macro", "Pick up this rotation's macro, drop it on an action bar, and use that slot's normal keybind. Prepare applies the draft to this rotation's casting button.")

    ui.explain = Button(page, "Rotation textual explanation", 266, 29)
    ui.explain:SetPoint("LEFT", ui.macro, "RIGHT", 9, 0)
    ui.explain:SetScript("OnClick", function() SH:ShowExplanation() end)
    Tooltip(ui.explain, "Rotation textual explanation", "Read your current draft as IF, AND, OR, and NOT rules, from highest priority to lowest.")

    ui.prepare = Button(page, "Prepare", 144, 31)
    ui.prepare:SetPoint("BOTTOMRIGHT", -23, 18)
    ui.prepare:SetScript("OnClick", function()
        local rotation = ActiveRotation(ui)
        if not IsEnabled(rotation) then
            ShowResult(ui, false, "Enable " .. RotationLabel(rotation) .. " before preparing it. Your draft has been saved.")
            return
        end
        if InCombatLockdown() then
            ShowResult(ui, false, "Leave combat to Prepare. Your draft has been saved.")
            return
        end
        SaveDraft(ui)
        local ok, message = rotation:Prepare(CopyRules(ui.draft))
        ShowResult(ui, ok, message)
    end)
    Tooltip(ui.prepare, "Apply your draft", "Validate all rules and prepare secure casting outside combat. Failed validation disables casting until you Prepare successfully. Ordinary draft edits do not change the active rotation.")

    ui.enableTracker = CheckBox(page, "Enable tracker", 0, 0, "Enable Blizzard's tracker", "Turn Blizzard's Cooldown Manager on or off. This setting is shared by all rotations. Red means the tracker is disabled, even if spells are listed in its settings. Enable it, close tracker settings, then Prepare. Change this setting outside combat.", function(value)
        if InCombatLockdown() then
            RefreshTrackerControl(ui)
            return
        end
        local setter = C_CVar and C_CVar.SetCVar or SetCVar
        local ok = type(setter) == "function" and pcall(setter, "cooldownViewerEnabled", value and "1" or "0")
        if not ok or TrackerEnabled() ~= value then
            ShowResult(ui, false, "Could not change the tracker setting. Open the game's settings to enable Cooldown Manager.")
        else
            ShowResult(ui, true, value and "Tracker enabled. Close tracker settings, then Prepare."
                or "Tracker disabled. Tracked aura and native cooldown rules need it enabled.")
        end
        RefreshTrackerControl(ui)
    end)
    ui.enableTracker:ClearAllPoints()
    ui.enableTracker:SetPoint("LEFT", ui.prepare, "LEFT", -164, 0)

    ui:RegisterEvent("PLAYER_REGEN_DISABLED")
    ui:RegisterEvent("PLAYER_REGEN_ENABLED")
    ui:RegisterEvent("UI_SCALE_CHANGED")
    ui:RegisterEvent("DISPLAY_SIZE_CHANGED")
    ui:RegisterEvent("CVAR_UPDATE")
    ui:SetScript("OnEvent", function(self, event, name)
        if event == "CVAR_UPDATE" then
            if type(name) == "string" and name:lower() == "cooldownviewerenabled" then RefreshTrackerControl(self) end
            return
        end
        if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then FitConfig(self) end
        if event == "PLAYER_REGEN_DISABLED" and self.capturingKey then EndKeyCapture(self) end
        if event == "PLAYER_REGEN_DISABLED" then
            if self.profileRenameDialog then self.profileRenameDialog:Hide() end
            if self.choiceMenu and self.choiceMenu.owner == self.profile then self.choiceMenu:Hide() end
        end
        if event == "PLAYER_REGEN_ENABLED" and self.keyCleanupPending then CleanupKeyCapture(self) end
        SH:RefreshUIStatus()
    end)
    ui:SetScript("OnHide", function(self)
        EndKeyCapture(self)
        if SH.transferUI then SH.transferUI:Hide() end
        if self.choiceMenu then self.choiceMenu:Hide() end
        if self.profileRenameDialog then self.profileRenameDialog:Hide() end
        if self.weakAurasHelpFrame then self.weakAurasHelpFrame:Hide() end
        for _, row in ipairs(self.rows) do ClearRowFocus(row) end
    end)
    RefreshRows(ui)
    return ui
end

function SH:RefreshUIStatus()
    local ui = SH.ui
    if not ui then return end
    local rotation = ActiveRotation(ui)
    local enabled = IsEnabled(rotation)
    local index = rotation.index or SH.activeRotationIndex or 1
    local inCombat = InCombatLockdown()
    local profileIndex = ProfileIndex()
    ui.profile:SetText(ProfileNames()[profileIndex] or ("Profile " .. profileIndex))
    ui.profile:SetEnabled(not inCombat and SH.SwitchProfile ~= nil)
    ui.renameProfile:SetEnabled(not inCombat and SH.RenameProfile ~= nil)
    if ui.capturingKey and (inCombat or not enabled) then EndKeyCapture(ui) end
    local status = rotation:Status() or ""
    if ui.message then
        local color = ui.messageOK and "|cff80d8ac" or "|cffff9292"
        status = color .. tostring(ui.message) .. "|r\n" .. status
    end
    if not enabled then status = RotationLabel(rotation) .. " is disabled. Edit its draft here, then enable it outside combat.\n" .. status end
    if inCombat then status = "|cffffd27fCombat: draft editing is available; Prepare when combat ends.|r\n" .. status end
    ui.status:SetText(status)
    local statusHeight = math.max(54, ui.status:GetStringHeight() + 3)
    ui.status:SetHeight(statusHeight)
    ui.statusBody:SetHeight(statusHeight)
    ui.prepare:SetEnabled(not inCombat and enabled)
    RefreshTrackerControl(ui)
    ui.macro:SetEnabled(not inCombat and enabled)
    ui.showButton:SetEnabled(not inCombat and enabled)
    ui.trackers:SetEnabled(not inCombat)
    ui.castKey:SetEnabled(not inCombat and enabled)
    ui.controller:SetEnabled(not inCombat and SH.ShowControllerUI ~= nil)
    RefreshWeakAurasControls(ui)
    ui.clearKey:SetEnabled(not inCombat and enabled and (rotation.db.directKey ~= nil or ui.capturingKey))
    if ui.capturingKey then
        ui.castKeyLabel:SetText(ui.pendingKey and ("Release " .. ui.pendingKey .. " to set it. Escape cancels.")
            or "Press a key. Escape cancels.")
    else
        ui.castKeyLabel:SetText("Direct cast key: " .. tostring(rotation.db.directKey or "Not set"))
    end
    ui.preventClipping:SetChecked(rotation.db.preventClipping ~= false)
    ui.showButton:SetChecked(rotation.db.showButton ~= false)
    ui.showButton.label:SetText("Show " .. RotationLabel(rotation))
    ui.autoPrepare:SetChecked(rotation.db.autoPrepare ~= false)
    ui.hideUIErrors:SetChecked(rotation.db.hideUIErrors == true)
    for tabIndex, tab in ipairs(ui.tabs) do
        local available = not SH.GetRotation or SH:GetRotation(tabIndex) ~= nil
        tab:SetEnabled(available and (ui.advancedPage:IsShown() or index ~= tabIndex))
    end
    ui.advancedTab:SetEnabled(not ui.advancedPage:IsShown())
    if ui.explain then ui.explain:SetText(DiagramEnabled() and "Rotation explanation" or "Rotation textual explanation") end
    ui.enableRotation:SetShown(index > 1)
    ui.enableRotation.label:SetShown(index > 1)
    ui.enableRotation.label:SetText("Enable " .. RotationLabel(rotation))
    ui.enableRotation:SetChecked(enabled)
    ui.enableRotation:SetEnabled(not inCombat)
    if SH.RefreshExplanation then SH:RefreshExplanation() end
end

function SH:ShowConfig()
    local ui = SH.ui or CreateConfig()
    FitConfig(ui)
    ui:Show()
    ui:Raise()
    SH:RefreshUIStatus()
end

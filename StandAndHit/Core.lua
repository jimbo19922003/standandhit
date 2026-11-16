local addonName, SH = ...
local M = SH.Model
local DISABLED_MACRO_BODY = "#showtooltip\n/stopmacro"
local CUSTOM_RULE_MACRO_BODY = '#showtooltip\n/run print("Stand and Hit: Custom Rules need the visible Hit Button, Set cast key, or a controller binding.")\n/stopmacro'
local QUESTION_MARK = 134400
local EMPTY = {}
local METADATA_KEYS = {"spellID", "overrideSpellID", "overrideTooltipSpellID", "selfAura", "hasAura", "charges", "flags", "equipSlot", "spellCategoryID"}
local VARIANT_KEYS = {"spellID", "overrideSpellID", "overrideTooltipSpellID"}
local DESCRIPTION_SETS = {ids = true, names = true, linkedIDs = true, auraIDs = true, auraNames = true, metadata = true}
local defaults = {
    version = 2, preventClipping = true, autoPrepare = true, showButton = true, hideUIErrors = false, hideTooltip = false,
    rules = {
        {spell = "Arcane Missiles", condition = "present", aura = "Missile Barrage", unit = "target", oncePerProc = true},
        {spell = "Frostbolt", condition = "always", aura = "", unit = "target"},
    },
    point = {point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 160},
    minimapAngle = 225, customRulesEnabled = false,
}
SH.guards, SH.signals, SH.orSignals, SH.extraSignals, SH.cooldownSignals = {}, {}, {}, {}, {}
SH.conditionCooldownSignals = {}
SH.statusText = "Not prepared. Add your spell rules, then click Prepare outside combat."
SH.index, SH.label, SH.buttonName, SH.macroName, SH.directButtonName = 1, "Hit Button", "HitButton", "Hit Button", "HitDirectButton"
SH.MAX_ROTATIONS = 4

function SH:GetRotation(index)
    if index == 1 then return SH end
    if type(index) ~= "number" or index % 1 ~= 0 or index < 2 or index > SH.MAX_ROTATIONS then return nil end
    return SH.rotations and SH.rotations[index]
end

function SH:GetActiveRotation()
    return SH:GetRotation(SH.activeRotationIndex or 1)
end

function SH:IsEnabled()
    return self.index == 1 or self.db.enabled == true
end

local function say(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff5cc7e0Stand and Hit:|r " .. tostring(message)) end
end

local function diagnosticText(value, fallback, maximum)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret ~= false then return fallback end
    end
    if type(value) ~= "string" and type(value) ~= "number" then return fallback end
    return tostring(value):gsub("[%c|]", " "):sub(1, maximum or 180)
end

function SH:CallNativeDiagnostic(label, fn, ...)
    local previous = SH.activeNativeDiagnostic
    local context = {label = diagnosticText(label, "native action"), blocked = false}
    SH.activeNativeDiagnostic = context
    local ok, value = pcall(fn, ...)
    SH.activeNativeDiagnostic = previous
    -- A denied native call can return normally. Do not let its caller mistake
    -- that result for success, and restore the diagnostic scope before raising.
    if context.blocked then
        SH.blockedNativeCalls = SH.blockedNativeCalls or {}
        SH.blockedNativeCalls[context.label] = true
        error("Client blocked " .. context.label, 0)
    end
    if not ok then error(value, 0) end
    return value
end

local function recordBlockedAction(event, owner, action)
    if diagnosticText(owner, nil) ~= addonName then return end
    action = diagnosticText(action, "Unknown action")
    local context = SH.activeNativeDiagnostic
    local source = context and context.label
    if context then context.blocked = true end
    local previous = SH.lastBlockedAction
    if previous and previous.event == event and previous.action == action and previous.source == source then
        previous.count = math.min(previous.count + 1, 1000000)
        return
    end
    local version, build = "unknown", "unknown"
    if type(GetBuildInfo) == "function" then
        local ok, clientVersion, clientBuild = pcall(GetBuildInfo)
        if ok then
            version = diagnosticText(clientVersion, version)
            build = diagnosticText(clientBuild, build)
        end
    end
    local detail = source and (source .. " [" .. action .. "]") or action
    local report = "Blocked action: " .. detail .. " (" .. event .. "). Client " .. version .. ", build " .. build .. "."
    local stack
    if type(debugstack) == "function" then
        local ok, value = pcall(debugstack, 2, 12, 0)
        if ok then stack = diagnosticText(value, nil, 3000) end
    end
    -- Retain one session report without retrying the action or changing setup.
    -- Do not refresh UI here: a UI callback may be the source of the block.
    SH.lastBlockedAction = {event = event, action = action, source = source, stack = stack, count = 1, report = report}
    say(report .. " Send this in a screenshot as a bug report.")
end

local function safeMethod(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object, ...)
    if ok then return value end
end

local function spellInfo(value)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, value)
        if ok then return info end
    elseif GetSpellInfo then
        local name, _, icon, _, _, _, id = GetSpellInfo(value)
        if name then return {name = name, iconID = icon, spellID = id} end
    end
end

local function isLearnedSpell(id)
    if SH.SpellRanks and SH.SpellRanks.IsLearned then return SH.SpellRanks.IsLearned(id) end
    local known
    if IsPlayerSpell then known = IsPlayerSpell(id) end
    if not known and IsSpellKnown then known = IsSpellKnown(id) end
    if not known and C_SpellBook and C_SpellBook.IsSpellKnown then
        known = C_SpellBook.IsSpellKnown(id)
    end
    return known
end

-- Several weapon skills have the same localized spell name as wand Shoot.
-- Existing name-based rules should use the learned auto-repeat action.
local rangedSpellIDs = {5019, 75}
local function resolveSpell(text, rankID)
    local numeric = tonumber(text)
    if numeric and (numeric < 1 or numeric ~= math.floor(numeric)) then
        return nil, "enter a positive whole spell ID."
    end
    if rankID ~= nil and (type(rankID) ~= "number" or rankID < 1 or rankID % 1 ~= 0) then
        return nil, "choose a valid spell rank."
    end
    local base = spellInfo(numeric or text)
    local exactID = rankID or numeric
    if not exactID and type(text) == "string" then
        for _, id in ipairs(rangedSpellIDs) do
            local ranged = spellInfo(id)
            if ranged and ranged.name and ranged.name:lower() == text:lower() and isLearnedSpell(id) then
                base, exactID = ranged, id
                break
            end
        end
    end
    local info = exactID and spellInfo(exactID) or base
    if not info or not info.name or not info.spellID then
        return nil, "spell not found: " .. tostring(exactID or text) .. ". Use its spellbook name or ID."
    end
    if rankID and (not base or not base.name or base.name:lower() ~= info.name:lower()) then
        return nil, "the selected rank does not belong to " .. tostring(text) .. ". Choose its rank again."
    end
    local rankLabel, learnedRank
    if exactID and SH.SpellRanks then
        for _, choice in ipairs(SH.SpellRanks.GetChoices(text)) do
            if choice.id == exactID then learnedRank, rankLabel = true, choice.label; break end
        end
    end
    if not exactID and SH.SpellRanks and SH.Riposte and SH.Riposte.IsReactive(info.spellID) then
        local family = SH.Riposte.Family(info.spellID)
        for _, choice in ipairs(SH.SpellRanks.GetChoices(text)) do
            if choice.id and SH.Riposte.Family(choice.id) == family then
                local learned = spellInfo(choice.id)
                if learned then info, learnedRank = learned, true end
            end
        end
    end
    local known = isLearnedSpell(info.spellID)
    if not learnedRank and (known == false or (rankID and known ~= true)) then
        return nil, "you have not learned " .. info.name .. " (" .. info.spellID .. ")."
    end
    -- A name preserves normal highest-known-rank selection. An ID requests that exact rank.
    return {cast = exactID or info.name, name = info.name, id = info.spellID, icon = info.iconID, rankLabel = rankLabel}
end
SH.ResolveSpell = resolveSpell

function SH:NotifyUI()
    if SH.switchingProfile then return end
    if SH.RefreshUIStatus then SH:RefreshUIStatus() end
    if SH.RefreshPreparationNotice then SH:RefreshPreparationNotice() end
end

function SH:Status()
    local text = self.statusText
    if self.prepared and self.dirty then text = text .. "\nYou have draft changes. Click Prepare to apply them." end
    if InCombatLockdown() then text = text .. "\nIn combat: setup changes wait until combat ends." end
    if SH.lastBlockedAction then text = text .. "\n" .. SH.lastBlockedAction.report end
    return text
end

function SH:GetDraftRules() return M.Copy(self.db.rules) end
local function sameConditionList(left, right)
    left, right = left == nil and {} or left, right == nil and {} or right
    local function equal(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
        for key in pairs(b) do if a[key] == nil then return false end end
        return true
    end
    return equal(left, right)
end
local function hasLogicAlternative(row)
    for _, item in ipairs(row.logicConditions or {}) do
        if item.logic == "OR" then return true end
    end
    return false
end
function SH:UpdateDraftState()
    local saved = self.db.preparedRules
    self.dirty = false
    if not saved or #saved ~= #self.db.rules or
        (self.db.preventClipping ~= false) ~= (self.db.preparedPreventClipping ~= false) then
        self.dirty = true
        return
    end
    for index, row in ipairs(self.db.rules) do
        local prepared = saved[index]
        for _, key in ipairs({"spell", "aura", "condition", "unit"}) do
            if M.Trim(row[key]) ~= M.Trim(prepared[key]) then self.dirty = true; return end
        end
        if (row.enabled ~= false) ~= (prepared.enabled ~= false) or
            (row.targetCasting == true) ~= (prepared.targetCasting == true) or
            (row.outOfCombatOnly == true) ~= (prepared.outOfCombatOnly == true) or
            (row.inCombatOnly == true) ~= (prepared.inCombatOnly == true) or
            (row.advanceOnToggle == true) ~= (prepared.advanceOnToggle == true) or
            row.totemCondition ~= prepared.totemCondition or
            row.skipModifier ~= prepared.skipModifier or
            row.priorityModifier ~= prepared.priorityModifier or
            (row.skipIfNotCasted == true) ~= (prepared.skipIfNotCasted == true) or
            (row.skipIfImmune == true) ~= (prepared.skipIfImmune == true) or
            (row.skipOutOfRange == true) ~= (prepared.skipOutOfRange == true) or
            row.customRule ~= prepared.customRule or
            row.customCondition ~= prepared.customCondition or
            M.Trim(row.customTarget) ~= M.Trim(prepared.customTarget) then
            self.dirty = true
            return
        end
        if (row.skipCooldown == true) ~= (prepared.skipCooldown == true) then self.dirty = true; return end
        if (row.oncePerProc == true) ~= (prepared.oncePerProc == true) then self.dirty = true; return end
        if (row.stopCasting == true) ~= (prepared.stopCasting == true) then self.dirty = true; return end
        if (row.stopWhenInvalid == true) ~= (prepared.stopWhenInvalid == true) then self.dirty = true; return end
        if (row.pingDelay == true) ~= (prepared.pingDelay == true) then self.dirty = true; return end
        local delay = row.pingDelayMS == nil and 100 or tonumber(row.pingDelayMS) or M.Trim(row.pingDelayMS)
        local preparedDelay = prepared.pingDelayMS == nil and 100 or tonumber(prepared.pingDelayMS) or M.Trim(prepared.pingDelayMS)
        if delay ~= preparedDelay then self.dirty = true; return end
        if (row.manualCooldown == true) ~= (prepared.manualCooldown == true) then self.dirty = true; return end
        local seconds = row.manualCooldownSeconds == nil and 0 or tonumber(row.manualCooldownSeconds) or M.Trim(row.manualCooldownSeconds)
        local preparedSeconds = prepared.manualCooldownSeconds == nil and 0 or tonumber(prepared.manualCooldownSeconds) or M.Trim(prepared.manualCooldownSeconds)
        if seconds ~= preparedSeconds then self.dirty = true; return end
        local count, preparedCount = tonumber(row.castCount) or M.Trim(row.castCount), tonumber(prepared.castCount) or M.Trim(prepared.castCount)
        if count == "" then count = 0 end
        if preparedCount == "" then preparedCount = 0 end
        if count ~= preparedCount then self.dirty = true; return end
        local countCondition = row.castCountCondition == nil and "primary" or row.castCountCondition
        local preparedCondition = prepared.castCountCondition == nil and "primary" or prepared.castCountCondition
        if countCondition ~= preparedCondition then
            self.dirty = true; return
        end
        if row.rankID ~= prepared.rankID then self.dirty = true; return end
        for _, key in ipairs({"auraSource", "orAuraSource"}) do
            local source = row[key] == nil and "tracker" or row[key]
            local applied = prepared[key] == nil and "tracker" or prepared[key]
            if source ~= applied then self.dirty = true; return end
        end
        if (row.useOr == true) ~= (prepared.useOr == true) then self.dirty = true; return end
        if M.Trim(row.orAura) ~= M.Trim(prepared.orAura) or
            (row.orCondition or "present") ~= (prepared.orCondition or "present") then self.dirty = true; return end
        if not sameConditionList(row.andConditions, prepared.andConditions) or
            not sameConditionList(row.notConditions, prepared.notConditions) or
            not sameConditionList(row.orConditions, prepared.orConditions) then self.dirty = true; return end
        if (row.comboPoints == nil) ~= (prepared.comboPoints == nil) or
            not sameConditionList(row.comboPoints, prepared.comboPoints) then self.dirty = true; return end
        if (row.hawkCount == nil) ~= (prepared.hawkCount == nil) or
            not sameConditionList(row.hawkCount, prepared.hawkCount) then self.dirty = true; return end
        if not sameConditionList(row.resourceConditions, prepared.resourceConditions) then self.dirty = true; return end
        if not sameConditionList(row.logicConditions, prepared.logicConditions) then
            local draftLogic = M.NormalizeLogicConditions(row.logicConditions)
            local preparedLogic = M.NormalizeLogicConditions(prepared.logicConditions)
            if not draftLogic or not preparedLogic or not sameConditionList(draftLogic, preparedLogic) then
                self.dirty = true; return
            end
        end
        if not sameConditionList(row.primaryCondition, prepared.primaryCondition) then
            local draftPrimary = M.NormalizePrimaryCondition(row.primaryCondition)
            local preparedPrimary = M.NormalizePrimaryCondition(prepared.primaryCondition)
            if not draftPrimary or not preparedPrimary or not sameConditionList(draftPrimary, preparedPrimary) then
                self.dirty = true; return
            end
        end
        if not sameConditionList(row.stackConditions, prepared.stackConditions) then
            local draftStacks = M.NormalizeStackConditions(row.stackConditions)
            local preparedStacks = M.NormalizeStackConditions(prepared.stackConditions)
            if not draftStacks or not preparedStacks or not sameConditionList(draftStacks, preparedStacks) then
                self.dirty = true; return
            end
        end
        if not sameConditionList(row.healthConditions, prepared.healthConditions) then
            local draftHealth = M.NormalizeHealthConditions(row.healthConditions)
            local preparedHealth = M.NormalizeHealthConditions(prepared.healthConditions)
            if not draftHealth or not preparedHealth or not sameConditionList(draftHealth, preparedHealth) then
                self.dirty = true; return
            end
        end
    end
end
function SH:SaveDraft(rules)
    self.db.rules = M.Copy(rules)
    self:UpdateDraftState()
    self:NotifyUI()
end

local function settingsOpen()
    return (CooldownViewerSettings and CooldownViewerSettings:IsShown()) or
        (EditModeManagerFrame and EditModeManagerFrame:IsShown())
end

local function spellName(id)
    -- This native API returns a string instead of allocating a SpellInfo table.
    -- Read it afresh: spell data can become available or change after loading.
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and name then return name end
    end
    local info = spellInfo(id)
    return info and info.name
end

local function addDescriptionID(entry, id)
    if not id then return end
    entry.ids[id] = true
    local name = spellName(id)
    if name then entry.names[name:lower()] = true end
end

local function describeFrame(frame, viewer, entry)
    entry = entry or {}
    -- Validation owns bounded scratch records; setup callers get independent
    -- durable records. Clear before any native read, including failing reads.
    for key in pairs(entry) do if not DESCRIPTION_SETS[key] then entry[key] = nil end end
    for key in pairs(DESCRIPTION_SETS) do
        local values = entry[key]
        if not values then values = {}; entry[key] = values end
        for id in pairs(values) do values[id] = nil end
    end
    local cooldownID = safeMethod(frame, "GetCooldownID")
    local baseID = safeMethod(frame, "GetBaseSpellID")
    if not cooldownID or not baseID then return nil end
    local name = spellName(baseID) or safeMethod(frame, "GetNameText")
    if not name then return nil end
    local ids, names, linkedIDs = entry.ids, entry.names, entry.linkedIDs
    ids[baseID], names[name:lower()] = true, true
    local info = safeMethod(frame, "GetCooldownInfo")
    if info then
        addDescriptionID(entry, info.overrideSpellID)
        addDescriptionID(entry, info.overrideTooltipSpellID)
        for _, id in ipairs(info.linkedSpellIDs or EMPTY) do addDescriptionID(entry, id); linkedIDs[id] = true end
    end
    local count = 0
    for _ in pairs(names) do count = count + 1 end
    -- A talent or cast and the proc it tracks can have different names.
    -- Compare the linked/tooltip aura family, not every metadata alias.
    -- Selection still follows this native entry's visibility as a whole.
    local auraIDs, auraNames, auraCount = entry.auraIDs, entry.auraNames, 0
    if info then
        for _, id in ipairs(info.linkedSpellIDs or EMPTY) do auraIDs[id] = true end
        if info.overrideTooltipSpellID then auraIDs[info.overrideTooltipSpellID] = true end
    end
    if not next(auraIDs) then auraIDs[(info and info.overrideSpellID) or baseID] = true end
    for id in pairs(auraIDs) do
        local auraName = spellName(id)
        -- Unknown spell data cannot establish that multiple IDs are one family.
        local key = auraName and auraName:lower() or ("spell ID " .. tostring(id))
        if not auraNames[key] then auraNames[key] = true; auraCount = auraCount + 1 end
    end
    local metadata = entry.metadata
    for _, key in ipairs(METADATA_KEYS) do
        metadata[key] = info and info[key]
    end
    entry.frame, entry.viewer, entry.cooldownID, entry.baseID = frame, viewer, cooldownID, baseID
    entry.name, entry.linkedSpellID = name, info and info.linkedSpellID
    entry.effectLinkCount = #(info and info.linkedSpellIDs or EMPTY)
    entry.ambiguous, entry.auraAmbiguous = count > 1, auraCount > 1
    return entry
end

local function sameIDs(left, right)
    for id in pairs(left) do if not right[id] then return false end end
    for id in pairs(right) do if not left[id] then return false end end
    return true
end

local function sameIdentity(left, right)
    if not right or left.baseID ~= right.baseID or left.cooldownID ~= right.cooldownID or
        not sameIDs(left.ids, right.ids) or not sameIDs(left.linkedIDs, right.linkedIDs) then return false end
    for key, value in pairs(left.metadata) do if right.metadata[key] ~= value then return false end end
    for key, value in pairs(right.metadata) do if left.metadata[key] ~= value then return false end end
    return true
end

local function viewerError(viewer)
    if not viewer:IsShown() then return "show the required native tracker group." end
    if viewer.visibleSetting and Enum and Enum.CooldownViewerVisibleSetting and
        viewer.visibleSetting ~= Enum.CooldownViewerVisibleSetting.Always then
        return "set the required native tracker group's visibility to Always."
    end
end

local function harmfulSpellError(id)
    local harmfulOK, harmful = pcall(C_Spell.IsSpellHarmful, id)
    local helpfulOK, helpful = pcall(C_Spell.IsSpellHelpful, id)
    if not harmfulOK or harmful ~= true or not helpfulOK or helpful ~= false then
        return "the target tracker includes a helpful or unclassified spell (" .. tostring(id) .. "). Use a dedicated harmful-only debuff entry."
    end
end

local function readLiveAuraValue(object, key, callMethod)
    local value
    if callMethod then
        local method = object[key]
        if type(method) ~= "function" then return false end
        value = method(object)
    else
        value = object[key]
    end
    if type(issecretvalue) == "function" and issecretvalue(value) then return false end
    return true, value
end

local function optionalLiveAuraValue(object, key, callMethod)
    local ok, readable, value = pcall(readLiveAuraValue, object, key, callMethod)
    return ok and readable == true, value
end

local function validationErrorDetail(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return end
    if type(value) ~= "string" then return end
    return value:gsub("%c", " "):gsub("|", ""):sub(1, 240)
end

local function targetAuraError(entry, allowUnreadableLiveData)
    local frame, info = entry.frame, entry.metadata
    if info.hasAura ~= true or info.selfAura ~= false then
        return "Target debuff needs a dedicated target-aura tracker, with no self-buff."
    end
    if info.equipSlot or info.spellCategoryID then return "item and category trackers cannot be used as Target debuff." end
    if safeMethod(frame, "GetTotemData") ~= nil or safeMethod(frame, "GetTotemSlot") ~= nil then
        return "totem-duration trackers cannot be used as Target debuff."
    end
    local nativeRegistration = CooldownViewerBuffItemMixin and CooldownViewerBuffItemMixin.NeedsTargetUpdateRegistration
    if type(nativeRegistration) ~= "function" or not CooldownViewerItemMixin or
        nativeRegistration == CooldownViewerItemMixin.NeedsTargetUpdateRegistration or
        frame.NeedsTargetUpdateRegistration ~= nativeRegistration then
        return "this client lacks the native tracker support needed to follow missing debuffs when targets change."
    end
    if safeMethod(frame, "NeedsTargetUpdateRegistration") ~= true then
        return "this native tracker is not following target changes. Use a dedicated target-debuff entry."
    end
    local border = frame.DebuffBorder
    if not border or type(border.IsShown) ~= "function" or safeMethod(border, "GetParent") ~= frame or safeMethod(border, "IsForbidden") then
        return "the native aura-presence frame is unavailable for this target tracker."
    end
    entry.debuffReference = border
    -- These are all IDs that the native scanner can treat as related auras.
    -- The current linked ID is live aura data and can become secret in combat.
    -- Never use it as a table key until it is readable. A readable undeclared
    -- alias still invalidates the tracker; its static IDs are checked below.
    local ids = entry.ids
    local linkedReadable, linkedID = optionalLiveAuraValue(entry, "linkedSpellID")
    if linkedReadable and linkedID and not ids[linkedID] and linkedID ~= info.spellID then
        return "the target tracker has an undeclared linked aura. Use a dedicated debuff entry."
    end
    if not C_Spell or type(C_Spell.IsSpellHarmful) ~= "function" or type(C_Spell.IsSpellHelpful) ~= "function" then
        return "this client cannot verify that the tracker contains only harmful spells."
    end
    for id in pairs(ids) do
        local reason = harmfulSpellError(id)
        if reason then return reason end
    end
    if info.spellID and not ids[info.spellID] then
        local reason = harmfulSpellError(info.spellID)
        if reason then return reason end
    end
    -- Live aura details can become secret during combat. They provide optional
    -- rejection evidence for an already-validated tracker, not its identity or
    -- the protected selection signal. Check readable fields independently so
    -- one unavailable field cannot hide another field's contradictory evidence.
    local unitReadable, unit = optionalLiveAuraValue(frame, "GetAuraDataUnit", true)
    local auraReadable, aura = optionalLiveAuraValue(frame, "GetAuraDataCached", true)
    local unavailable = not linkedReadable or not unitReadable or not auraReadable
    if unitReadable and unit ~= nil and unit ~= "target" then
        return "this entry is displaying a player buff instead of a target debuff. Use a dedicated debuff entry."
    end
    if auraReadable and aura ~= nil then
        local harmfulReadable, harmful = optionalLiveAuraValue(aura, "isHarmful")
        local helpfulReadable, helpful = optionalLiveAuraValue(aura, "isHelpful")
        local sourceReadable, source = optionalLiveAuraValue(aura, "sourceUnit")
        unavailable = unavailable or not harmfulReadable or not helpfulReadable or not sourceReadable
        if (unitReadable and unit ~= "target") or (harmfulReadable and harmful ~= true) or
            (helpfulReadable and helpful ~= false) or (sourceReadable and source ~= "player") then
            return "this entry is not displaying your own harmful aura on the current target."
        end
    end
    if unavailable and not allowUnreadableLiveData then
        return "this target tracker's current aura details are unavailable. Try Prepare again when they can be checked."
    end
end

local function resolveTrackerAura(entry, input, source)
    local frame, viewer = entry.frame, entry.viewer
    if safeMethod(frame, "IsForbidden") then return "the tracker cannot be accessed on this client." end
    if source == "target" then
        local resolver
        if SH.Frostbite and SH.Frostbite.IsEntry(entry) then resolver = SH.Frostbite.Resolve
        elseif SH.Gouge and SH.Gouge.IsEntry(entry) then resolver = SH.Gouge.Resolve
        elseif SH.Judgements and SH.Judgements.IsEntry(entry) then resolver = SH.Judgements.Resolve
        elseif SH.TargetEffect and SH.TargetEffect.IsCurseGroup(entry) then resolver = SH.TargetEffect.ResolveCurse end
        if resolver then
            local effect, reason = resolver(entry, input, spellName)
            if not effect then return reason or "enter the name or spell ID of a debuff in this tracker." end
            entry.targetEffect, entry.effectInput = effect, input
            return
        end
    elseif SH.GroupedPlayerBuffs and SH.GroupedPlayerBuffs.IsGroup(entry) then
        local buff, reason = SH.GroupedPlayerBuffs.Resolve(entry, input, spellName, isLearnedSpell)
        if not buff then return reason end
        entry.groupedPlayerBuff, entry.effectInput = buff, input
        return
    elseif SH.DruidForms and SH.DruidForms.IsGroup(entry) then
        local slot, spellID, reason = SH.DruidForms.Resolve(entry, input, spellName)
        if not slot then return reason or "enter an individual learned form from the Druid Forms entry." end
        entry.formSlot, entry.formSpellID = slot, spellID
        return
    end
    if entry.auraAmbiguous then return "the tracker links multiple different buffs. Use a dedicated aura entry." end
    if frame.allowHideWhenInactive ~= true or frame.hideWhenInactive ~= true then
        return "enable Hide when inactive for this Buff Bars / Buff Icons group."
    end
    if viewer.visibleSetting and Enum and Enum.CooldownViewerVisibleSetting and
        viewer.visibleSetting ~= Enum.CooldownViewerVisibleSetting.Always then
        return "set this Buff Bars / Buff Icons group's visibility to Always."
    end
    if not viewer:IsShown() then return "enable and show its Buff Bars / Buff Icons group." end
    if source == "target" then return targetAuraError(entry) end
end

function SH:FindAura(aura, source)
    local input = M.Trim(aura)
    if SH.AuraAliases then input = SH.AuraAliases.Resolve(input, source, spellName) end
    if SH.WarriorStances then
        local stance, reason = SH.WarriorStances.Resolve(input, source, spellName)
        if stance or reason then return stance, reason end
    end
    -- The shared name selects the consumable opener proc. Explicit IDs can
    -- still select either buff, including the separate dodge tracker.
    if source ~= "target" and not tonumber(input) then
        local ghostlyName = spellName(14278) or spellName(1329326)
        if ghostlyName and input:lower() == ghostlyName:lower() then input = "1329326" end
    end
    local id, name = tonumber(input), input:lower()
    local best, lastError
    for _, viewerName in ipairs({"BuffBarCooldownViewer", "BuffIconCooldownViewer"}) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                local entry = describeFrame(frame, viewer)
                local match = entry and ((id and entry.ids[id]) or (not id and entry.names[name]))
                if not match and source == "target" and SH.Gouge then
                    match = SH.Gouge.Matches(entry, input, spellName)
                end
                if not match and source == "target" and SH.Judgements then
                    match = SH.Judgements.Matches(entry, input, spellName)
                end
                if not match and id and source ~= "target" and SH.GroupedPlayerBuffs and SH.GroupedPlayerBuffs.IsGroup(entry) then
                    local rankName = spellName(id)
                    match = rankName and entry.names[rankName:lower()]
                end
                if match then
                    local reason = resolveTrackerAura(entry, input, source)
                    if reason then
                        lastError = reason
                    else
                        if best and best.viewer == viewer and best.cooldownID ~= entry.cooldownID then
                            return nil, "multiple trackers match. Use an exact aura ID or remove duplicate entries."
                        end
                        if not best then entry.auraSource = source or "tracker"; best = entry end
                    end
                end
            end
        end
        if best then break end -- Prefer a valid bar entry over an icon duplicate.
    end
    if best then return best end
    -- Some applied Judgement ranks are listed in settings but omitted from
    -- the live viewer because they are not learned spells. Verify the saved
    -- tracker assignment before using an exact target-effect reader.
    if source == "target" and SH.Judgements then
        local entry, reason = SH.Judgements.FindConfigured(input, spellName)
        if entry then return entry end
        lastError = reason or lastError
    end
    return nil, lastError or "not found in Blizzard's Buff Bars or Buff Icons. Add the aura there, close settings, then Prepare. If the spell only has a cooldown entry, choose Off cooldown instead."
end

-- Players learn the summons, so looking up the effect by name can miss even
-- a familiar totem buff. Resolve its localized name before the first summon.
local totemBuffRanks = {
    {8076, 8162, 8163, 10441, 25362}, -- Strength of Earth
    {8072, 8156, 8157, 10403, 10404, 10405}, -- Stoneskin
    {8836, 10626, 25360}, -- Grace of Air
    {5677, 10491, 10493, 10494, 24853}, -- Mana Spring
    {5672, 6371, 6372, 10460, 10461}, -- Healing Stream
    {25909}, -- Tranquil Air
    {8515, 10609, 10612, exactIDs = true}, -- Windfury Totem (recipient aura, not its extra-attack proc)
    {8230, 8250, 10521, 15036, exactIDs = true}, -- Flametongue Totem
    {15108, 15109, 15110, exactIDs = true}, -- Windwall
    {8185, 10534, 10535, exactIDs = true}, -- Fire Resistance
    {8182, 10476, 10477, exactIDs = true}, -- Frost Resistance
    {10596, 10598, 10599, exactIDs = true}, -- Nature Resistance
    {16191, 17355, 17360, 1325257, exactIDs = true}, -- Mana Tide
    {8178, exactIDs = true}, -- Grounding Totem
}

local function namedTotemBuff(text)
    local id = tonumber(text)
    local lower = text:lower()
    for _, ranks in ipairs(totemBuffRanks) do
        local effect, matches
        for _, rank in ipairs(ranks) do
            effect = effect or spellName(rank)
            if rank == id or (not id and effect and lower == effect:lower()) then matches = true end
            if effect and (not id or matches) then break end
        end
        if matches and effect then
            local ids = {}
            for _, rank in ipairs(ranks) do ids[rank] = true end
            return {name = effect, ids = ids, totemBuff = true, exactIDs = ranks.exactIDs == true}
        end
    end
end

local function resolvePlayerBuff(rotation, input)
    local text = M.Trim(input)
    if SH.AuraAliases then text = SH.AuraAliases.Resolve(text, "player", spellName) end
    local totem = namedTotemBuff(text)
    if totem then return totem end
    local id = tonumber(text)
    local ghostlyName = spellName(14278) or spellName(1329326)
    local ghostlyID = id or (ghostlyName and text:lower() == ghostlyName:lower() and 1329326)
    if ghostlyID == 14278 or ghostlyID == 1329326 then
        local name = spellName(ghostlyID)
        if not name then return nil, "the selected Ghostly Strike buff could not be found on this client." end
        -- The name means the Ambush/Garrote proc; an explicit ID retains its
        -- exact meaning. Never combine it with the same-name dodge buff.
        return {name = name, ids = {[ghostlyID] = true}, memberID = ghostlyID,
            exactIDs = true, nativePlayerBuff = true}
    end
    if SH.GroupedPlayerBuffs and SH.GroupedPlayerBuffs.ResolvePlayerSeal then
        local seal = SH.GroupedPlayerBuffs.ResolvePlayerSeal(text, spellName, isLearnedSpell)
        if seal then return seal end
    end
    local info = spellInfo(id or text)
    local name = info and info.name
    local lower = text:lower()
    if name and name == spellName(8075) then
        return nil, "enter the buff " .. (spellName(8076) or "(8076)") .. " in the condition. Keep the totem in Spell name or ID."
    end
    if name and info.spellID then return {name = name, ids = {[info.spellID] = true}} end
    -- A tracker can supply the localized effect ID for a buff that isn't
    -- in the player's spellbook. Never use the summon's visibility as a buff.
    if C_CooldownViewer and type(C_CooldownViewer.GetGroupBuffItems) == "function" then
        local ok, items = pcall(C_CooldownViewer.GetGroupBuffItems)
        if ok and type(items) == "table" then
            for _, item in ipairs(items) do
                if item.name and item.spellID and item.displaySpellID and item.name:lower() == lower then
                    return {name = item.name, ids = {[item.spellID] = true, [item.displaySpellID] = true}}
                end
            end
        end
    end
    local entry = rotation:FindAura(text, "tracker")
    if entry then
        local ids = {}
        for effectID in pairs(entry.auraIDs) do
            local effectName = spellName(effectID)
            if effectName and ((id and id == effectID) or (not id and effectName:lower() == lower)) then
                name = effectName
                ids[effectID] = true
            end
        end
        if next(ids) then return {name = name, ids = ids} end
    end
    return nil, "enter the name or spell ID of the buff that appears on your character."
end

local function isShaman()
    if UnitClassBase then return UnitClassBase("player") == "SHAMAN" end
    if UnitClass then
        local _, class = UnitClass("player")
        return class == "SHAMAN"
    end
    return false
end
SH.IsShaman = isShaman

local function isHunter()
    if UnitClassBase then return UnitClassBase("player") == "HUNTER" end
    if UnitClass then
        local _, class = UnitClass("player")
        return class == "HUNTER"
    end
    return false
end
SH.IsHunter = isHunter

-- Forever's Shaman summoning spells. Classic ranks can have independent IDs
-- even when GetBaseSpell returns the supplied rank. Buff and pulse IDs differ.
local totemSummons = {}
for _, ranks in ipairs({
    {5730, 6390, 6391, 6392, 10427, 10428},     -- Stoneclaw
    {8075, 8160, 8161, 10442, 25361},           -- Strength of Earth
    {8071, 8154, 8155, 10406, 10407, 10408},    -- Stoneskin
    {2484}, {8143}, {425874},                    -- Earthbind, Tremor, Decoy
    {3599, 6363, 6364, 6365, 10437, 10438},     -- Searing
    {8190, 10585, 10586, 10587},                 -- Magma
    {8227, 8249, 10526, 16387},                  -- Flametongue
    {8181, 10478, 10479}, {27623},               -- Frost Resistance, Fire Nova
    {5394, 6375, 6377, 10462, 10463},           -- Healing Stream
    {5675, 10495, 10496, 10497, 24854},         -- Mana Spring
    {16190, 17354, 17359, 1325256},              -- Mana Tide
    {8184, 10537, 10538}, {8166}, {8170},       -- Fire Resistance, Poison/Disease Cleansing
    {8835, 10627, 25359},                        -- Grace of Air
    {8512, 10613, 10614, 27621},                 -- Windfury
    {15107, 15111, 15112},                       -- Windwall
    {10595, 10600, 10601}, {8177}, {6495},       -- Nature Resistance, Grounding, Sentry
}) do
    for _, id in ipairs(ranks) do totemSummons[id] = ranks[1] end
end

local function totemFamily(spellID)
    if totemSummons[spellID] then return totemSummons[spellID] end
    if C_Spell and C_Spell.GetBaseSpell then
        local ok, baseID = pcall(C_Spell.GetBaseSpell, spellID)
        if ok and not (issecretvalue and issecretvalue(baseID)) then return totemSummons[baseID] end
    end
end
SH.TotemFamily = totemFamily

local totemElements = {
    [5730] = "earth", [8075] = "earth", [8071] = "earth", [2484] = "earth", [8143] = "earth", [425874] = "earth",
    [3599] = "fire", [8190] = "fire", [8227] = "fire", [8181] = "fire", [27623] = "fire",
    [5394] = "water", [5675] = "water", [16190] = "water", [8184] = "water", [8166] = "water", [8170] = "water",
    [8835] = "air", [8512] = "air", [15107] = "air", [10595] = "air", [8177] = "air", [6495] = "air",
}
function SH.TotemElement(spellID)
    if issecretvalue and issecretvalue(spellID) then return nil end
    if type(spellID) ~= "number" or spellID <= 0 then return nil end
    local family = totemFamily(spellID)
    return family and totemElements[family] or nil
end

-- Consecration's cooldown entry can display the ground effect's duration.
-- Its cast ranks share a cooldown, but the displayed duration is not that cooldown.
local consecrationRanks = {[26573] = true, [20116] = true, [20922] = true, [20923] = true, [20924] = true}
local function isConsecrationRank(spellID)
    return not (issecretvalue and issecretvalue(spellID)) and type(spellID) == "number" and
        consecrationRanks[spellID] == true
end

local function isTotemSummon(entry, spellID)
    if not isShaman() or not spellID then return false end
    local family = totemFamily(spellID)
    if family and (entry.baseID == spellID or totemFamily(entry.baseID) == family) then return true, true end
    if entry.ambiguous then return false end
    -- The viewer can positively identify a new totem family while it is out.
    local data = safeMethod(entry.frame, "GetTotemData")
    if type(data) == "table" and not (issecretvalue and issecretvalue(data)) then return true end
    local slot = safeMethod(entry.frame, "GetTotemSlot")
    return type(slot) == "number" and not (issecretvalue and issecretvalue(slot)) and slot > 0
end

local function cooldownEntryError(entry, row, aura, preparing)
    local frame, info = entry.frame, entry.metadata
    local allowsAuraDisplay = safeMethod(frame, "CanUseAuraForDisplay")
    local useSpellCooldown = row.spellCooldownID
    -- An independent cooldown predicate cannot rely on the cast rule having
    -- a paired missing-buff condition. Known aura-capable entries read the
    -- referenced spell's actual cooldown instead of its display duration.
    if row.cooldownCondition and allowsAuraDisplay == true and info.hasAura == true then useSpellCooldown = true end
    local consecration = isConsecrationRank(row.spellID)
    local sameConsecrationFamily = consecration and isConsecrationRank(entry.baseID)
    if consecration and not sameConsecrationFamily then useSpellCooldown = nil end
    local sameTotemFamily = row.totemCooldownBaseID == entry.baseID
    if preparing and allowsAuraDisplay == true and not sameTotemFamily then
        local totem, exact = isTotemSummon(entry, row.spellID)
        useSpellCooldown, sameTotemFamily = useSpellCooldown or totem, exact
    end
    if entry.ambiguous and not (allowsAuraDisplay == true and sameTotemFamily) then
        return "the cooldown tracker combines different spells. Use a dedicated entry."
    end
    if safeMethod(frame, "IsForbidden") or safeMethod(frame, "IsActivelyCast") ~= true then
        return "this entry is not an accessible native spell cooldown."
    end
    if info.equipSlot or info.spellCategoryID then return "item cooldown trackers are not supported." end
    if info.charges ~= false then return "charge-based or unknown cooldown types are not supported yet. Turn off Skip while on cooldown for this rule." end
    local chargeInfo = safeMethod(frame, "GetSpellChargeInfo")
    if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
        return "charge-based cooldowns are not supported yet. Turn off Skip while on cooldown for this rule."
    end
    local reason = viewerError(entry.viewer)
    if reason then return reason end
    -- These entries can replace the spell swipe with a ground effect or totem
    -- duration. Keep the actual spell cooldown as the source from Prepare onward.
    if (allowsAuraDisplay == true and useSpellCooldown) or
        (allowsAuraDisplay ~= false and sameConsecrationFamily) then
        if not SH.TotemCooldown or not row.spellID then
            return "the spell cooldown reader is unavailable. Reinstall the complete addon."
        end
        entry.spellCooldownID = row.spellID
        entry.totemCooldownBaseID = sameTotemFamily and entry.baseID or nil
        return
    end
    local flash = safeMethod(frame, "GetCooldownFlashFrame")
    if not flash or safeMethod(flash, "IsForbidden") or type(safeMethod(flash, "IsShown")) ~= "boolean" then
        return "the native cooldown signal is unavailable on this client."
    end
    -- Native cooldown widgets hide at expiry even if the flash frame is stale.
    -- Read both in the secure selector; no native alert or addon timer is needed.
    local timer = safeMethod(frame, "GetCooldownFrame")
    if not timer or safeMethod(timer, "IsForbidden") or type(safeMethod(timer, "IsShown")) ~= "boolean" then
        return "the native cooldown timer is unavailable on this client."
    end
    -- CanUseAuraForDisplay is display permission, not proof of an aura.
    -- Known no-aura spells need no paired buff. They still use BOTH native
    -- signals: the main timer includes the GCD, while the flash marks actual
    -- cooldowns. Timer-only selection can repeatedly queue the filler on GCD.
    entry.noAuraDisplay = allowsAuraDisplay == true and info.hasAura == false and info.selfAura == false
    if entry.noAuraDisplay and (safeMethod(frame, "GetTotemData") ~= nil or safeMethod(frame, "GetTotemSlot") ~= nil) then
        return "totem-duration trackers are not supported for cooldown skipping."
    end
    if entry.noAuraDisplay and safeMethod(frame, "GetAuraDataCached") ~= nil then
        return "this cooldown-only entry is displaying an aura. Use a dedicated spell cooldown entry."
    end
    if allowsAuraDisplay ~= false and not entry.noAuraDisplay then
        -- A buff/totem timer can hide the flash while a real cooldown is active.
        -- Only an equivalent native missing-aura condition can exclude that case.
        if row.useOr or #(row.orConditions or EMPTY) > 0 or hasLogicAlternative(row) then
            return "this tracker can show buff duration, so OR could bypass its required missing-buff check. Use a separate Aura is missing rule for this spell without OR, or turn off Skip while on cooldown."
        end
        if row.condition ~= "missing" or not aura or aura.formSlot or aura.targetEffect or aura.groupedPlayerBuff then
            return "this tracker can show buff duration. Use Aura is missing for this spell's own Buff Bar/Icon entry, or turn off Skip while on cooldown. Keep its cooldown in Essential or Utility."
        end
        if info.selfAura ~= true or aura.metadata.selfAura ~= true or
            safeMethod(aura.frame, "IsActivelyCast") ~= false or
            not sameIDs(entry.ids, aura.ids) or not sameIDs(entry.linkedIDs, aura.linkedIDs) then
            return "the missing-aura tracker does not cover the cooldown's same self-buff. This pairing is not supported."
        end
        for _, key in ipairs(VARIANT_KEYS) do
            if info[key] ~= aura.metadata[key] then
                return "the buff and cooldown trackers refer to different spell variants. This pairing is not supported."
            end
        end
    end
    entry.reference = flash
    entry.timerReference = timer
end

function SH:FindCooldown(row, aura)
    local best, lastError
    local rankFamily = type(row.spell) == "number" and isShaman() and totemFamily(row.spellID)
    local consecration = type(row.spell) == "number" and isConsecrationRank(row.spellID)
    for _, viewerName in ipairs({"EssentialCooldownViewer", "UtilityCooldownViewer"}) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                local entry = describeFrame(frame, viewer)
                local match = entry and ((type(row.spell) == "number" and entry.ids[row.spell]) or
                    (rankFamily and totemFamily(entry.baseID) == rankFamily) or
                    (consecration and isConsecrationRank(entry.baseID)) or
                    (type(row.spell) ~= "number" and entry.names[row.displayName:lower()]))
                if match then
                    local reason = cooldownEntryError(entry, row, aura, true)
                    if reason then lastError = reason
                    elseif best and best.cooldownID ~= entry.cooldownID then
                        return nil, "multiple cooldown trackers match. Use an exact spell ID or remove duplicates."
                    elseif not best then best = entry end
                end
            end
        end
        if best then break end
    end
    if best and best.spellCooldownID then row.totemCooldownBaseID = best.totemCooldownBaseID end
    return best, not best and (lastError or "not found in Essential Cooldowns or Utility Cooldowns. Add the spell there, close settings, then Prepare.") or nil
end

function SH:UpdateButtonVisual()
    if not self.button then return end
    local rowIndex = self.button:GetAttribute("selected-row")
    local row = self.activeRules and self.activeRules[rowIndex or 0]
    self.button.Icon:SetTexture(row and row.icon or (self.activeRules and self.activeRules[1] and self.activeRules[1].icon) or QUESTION_MARK)
    self.button.Caption:SetText(self.label)
    self.button.Badge:SetText(self.stale and "CHECK SETUP" or (self.prepared and "" or "PREPARE"))
    self.button.Badge:SetTextColor(self.stale and 1 or 0.9, self.stale and 0.25 or 0.8, 0.2)
end

function SH:QueueDragCleanup()
    local token = self.dragToken
    C_Timer.After(0, function()
        if token ~= self.dragToken or self.dragging or InCombatLockdown() then return end
        if self.button then
            self.button:SetAttribute("sh-suppress-click", nil)
            self.button:SetAttribute("sh-dragging", nil)
        end
    end)
end

function SH:FinishButtonDrag()
    if not self.dragging or InCombatLockdown() then return end
    local button = self.button
    button:StopMovingOrSizing()
    local anchor, _, relative, x, y = button:GetPoint(1)
    self.db.point = {point = anchor, relativePoint = relative, x = x, y = y}
    self.dragging = false
    button:SetAttribute("sh-dragging", nil)
    -- Keep suppression until the release click has finished, even if Shift was released first.
    button:SetAttribute("sh-suppress-click", true)
    self:QueueDragCleanup()
end

local function updatePositionMonitoring()
    -- An actual press on another rotation supersedes an unconfirmed attempt.
    -- Keep the observer off every button when nobody has enabled this option.
    local rotations = SH.rotations or {SH}
    local watching = false
    for _, rotation in ipairs(rotations) do
        if rotation.button and rotation.button:GetAttribute("sh-has-position-skip") then watching = true; break end
    end
    SH.watchPositionFailures = watching
    for _, rotation in ipairs(rotations) do
        if rotation.button then rotation.button:SetAttribute("sh-watch-position", watching) end
    end
end

local function configureModifierClicks(button, rules)
    local ctrl, shift = false, false
    for _, row in ipairs(rules or {}) do
        ctrl = ctrl or row.skipModifier == "ctrl" or row.priorityModifier == "ctrl"
        shift = shift or row.skipModifier == "shift" or row.priorityModifier == "shift"
    end
    button:SetAttribute("sh-modifier-ctrl", ctrl)
    button:SetAttribute("sh-modifier-shift", shift)
    local overlay = button.tooltipToggle
    if not overlay then return end
    for _, prefix in ipairs({"ctrl-", "ctrl-shift-", "alt-ctrl-", "alt-ctrl-shift-"}) do
        -- A configured Ctrl rule needs physical Ctrl-left-click to cast.
        -- Keep the tooltip gesture on Ctrl-right-click for that rotation.
        overlay:SetAttribute(prefix .. "type1", not ctrl and "none" or nil)
        overlay:SetAttribute(prefix .. "type2", ctrl and "none" or nil)
    end
end

function SH:CreateCastButton()
    if self.button then return self.button end
    if InCombatLockdown() then return nil end
    local button = CreateFrame("Button", self.buttonName, UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    button:SetSize(48, 48)
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    local point = self.db.point
    button:SetPoint(point.point, UIParent, point.relativePoint, point.x, point.y)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type", "spell")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("ready", false)
    button.RefreshComboPoints = function(_, acknowledgment)
        if SH.ComboPoints then SH.ComboPoints:Refresh(acknowledgment) end
    end
    button.RefreshResource = function(_, index, acknowledgment)
        if SH.Resources then SH.Resources:Refresh(button, index, acknowledgment) end
    end
    button.RefreshHealth = function(_, index, acknowledgment)
        if SH.Health then SH.Health:Refresh(button, index, acknowledgment) end
    end
    button.RefreshStacks = function(_, index, acknowledgment)
        if SH.AuraStacks then SH.AuraStacks:Refresh(button, index, acknowledgment) end
    end
    button.RefreshAuraTime = function(_, index, acknowledgment)
        if SH.AuraTime then SH.AuraTime:Refresh(button, index, acknowledgment) end
    end
    button.RefreshPingDelay = function(_, index, acknowledgment, arm)
        if SH.PingDelay then SH.PingDelay:Refresh(button, index, acknowledgment, arm) end
    end
    button.RefreshTotemCooldown = function(_, phase, spellID, requireKnown)
        SH.TotemCooldown:Refresh(button, phase, spellID, requireKnown)
    end
    button.RefreshPlayerBuff = function(_, phase, key)
        SH.PlayerBuff:Refresh(button, phase, key)
    end
    button.RefreshTargetEffect = function(_, phase, key)
        SH.TargetEffect:Refresh(button, phase, key)
    end
    button.RefreshTargetCasting = function(_, phase)
        SH.TargetCasting:Refresh(button, phase)
    end
    button.RefreshRiposte = function(_, phase, spellID)
        SH.Riposte:Refresh(button, phase, spellID)
    end
    button:SetAttribute("sh-watch-position", SH.watchPositionFailures or false)
    button.RefreshImmunitySkip = function(_, phase, index, unit) SH.ImmunitySkip:Refresh(button, phase, index, unit) end
    button.BeginImmunityAttempt = function(_, index, unit) SH.ImmunitySkip:Begin(button, index, unit) end
    button.RefreshPositionSkip = function(_, phase, index) SH.PositionSkip:Refresh(button, phase, index) end
    button.RefreshSpellRange = function(_, phase, index) SH.Range:Refresh(button, phase, index) end
    button.RefreshSpellRangeOutside = function(_, index) SH.Range:RefreshOutside(button, index) end
    button.ConsumePositionSkip = function() SH.PositionSkip:Consume(button) end
    button.BeginPositionAttempt = function(_, index, unit) SH.PositionSkip:Begin(button, index, unit) end
    button.EndPositionAttempt = function() SH.PositionSkip:End(button) end
    button.RefreshWandShoot = function(_, acknowledgment, spellID, currentSpell)
        if SH.WandShoot then SH.WandShoot:Refresh(acknowledgment, spellID, currentSpell) end
    end
    button.NotePetAttackAttempt = function() SH.PetAttack:NoteAttempt() end
    if SH.ErrorFilter then SH.ErrorFilter:Install() end
    button:SetAttribute("sh-error-filter", SH.ErrorFilter ~= nil)
    button.NoteErrorFilterAttempt = function()
        if SH.ErrorFilter then SH.ErrorFilter:NoteAttempt(self) end
    end
    button:SetAttribute("sh-select", "self:SetAttribute('type','spell');self:SetAttribute('macrotext',nil);self:SetAttribute('spell',nil);self:SetAttribute('selected-primary',nil);self:SetAttribute('selected-or',nil);self:SetAttribute('selected-legacy-or',nil);return false")
    SecureHandlerWrapScript(button, "OnClick", button, [[
        if self:GetAttribute("sh-suppress-click") or self:GetAttribute("sh-dragging") then
            self:SetAttribute("sh-auto-followup",nil)
            self:SetAttribute("sh-suppress-click",nil)
            self:SetAttribute("sh-dragging",nil)
            self:SetAttribute("type","spell")
            self:SetAttribute("macrotext",nil)
            self:SetAttribute("spell",nil)
            self:SetAttribute("selected-row",nil)
            self:SetAttribute("selected-primary",nil)
            self:SetAttribute("selected-or",nil)
            self:SetAttribute("selected-legacy-or",nil)
            return false
        end
        local autoFollowup=self:GetAttribute("sh-auto-followup")
        local commandFollowup=self:GetAttribute("sh-command-followup")
        self:SetAttribute("sh-auto-followup",nil)
        self:SetAttribute("sh-command-followup",nil)
        if self:GetAttribute("sh-has-custom-rule") and not commandFollowup then
            self:SetAttribute("type","spell")
            self:SetAttribute("macrotext",nil)
            self:SetAttribute("spell",nil)
            self:SetAttribute("selected-row",nil)
            return false
        end
        local selectedOK=self:RunAttribute((autoFollowup or commandFollowup) and "sh-select-cast" or "sh-select")
        local watchPosition=self:GetAttribute("sh-watch-position")
        if watchPosition then
            self:SetAttribute("sh-position-awaiting-click",nil)
            self:CallMethod("ConsumePositionSkip")
        end
        if selectedOK == false then
            if not self:GetAttribute("ready") or
                not (self:GetAttribute("sh-has-counts") or self:GetAttribute("sh-has-combo") or self:GetAttribute("sh-has-resources") or self:GetAttribute("sh-has-health") or self:GetAttribute("sh-has-stacks") or self:GetAttribute("sh-has-aura-time") or self:GetAttribute("sh-has-logic") or self:GetAttribute("sh-has-ping") or self:GetAttribute("sh-has-target-casting") or self:GetAttribute("sh-has-fire-totems") or self:GetAttribute("sh-has-hawks") or self:GetAttribute("sh-has-riposte") or self:GetAttribute("sh-has-position-skip") or self:GetAttribute("sh-has-immunity-skip") or self:GetAttribute("sh-has-range") or self:GetAttribute("sh-has-out-of-combat") or self:GetAttribute("sh-has-in-combat") or self:GetAttribute("sh-has-modifiers")) then return false end
            -- An invalid observer cannot choose a spell, but a fresh press can
            -- still clear a request left in the queue before it became invalid.
            self:SetAttribute("type","macro")
            self:SetAttribute("macrotext","/cancelqueuedspell")
        end
        local selected=self:GetAttribute("selected-row")
        if self:GetAttribute("type")=="spell" and self:GetAttribute("spell") and selected and self:GetAttribute("sh-ping-enabled"..selected) then
            -- The direct dispatcher also selects before /click. Only the final
            -- action attempt arms this delay, never a selection-only read.
            if self:RunAttribute("sh-read-ping",selected,true)~=true or self:GetAttribute("sh-ping-pass")~=true then
                self:SetAttribute("spell",nil)
                self:SetAttribute("sh-valid",false)
                self:SetAttribute("selected-row",nil)
                self:SetAttribute("selected-primary",nil)
                self:SetAttribute("selected-or",nil)
                self:SetAttribute("selected-legacy-or",nil)
                self:SetAttribute("type","macro")
                self:SetAttribute("macrotext","/cancelqueuedspell")
            end
        end
        local petOrder=self:GetAttribute("sh-pet-attack") and self:GetAttribute("type")=="pet"
        if petOrder then self:CallMethod("NotePetAttackAttempt") end
        if self:GetAttribute("sh-error-filter") and (petOrder or (self:GetAttribute("type") == "spell" and self:GetAttribute("spell"))) then
            self:CallMethod("NoteErrorFilterAttempt")
        end
        if watchPosition and selected and self:GetAttribute("type")=="spell" and self:GetAttribute("spell") then
            self:CallMethod("BeginPositionAttempt",selected,self:GetAttribute("unit"))
        end
        if self:GetAttribute("sh-has-immunity-skip") and selected and self:GetAttribute("type")=="spell" and self:GetAttribute("spell") then
            self:CallMethod("BeginImmunityAttempt",selected,self:GetAttribute("unit"))
        end
        -- The two-phase launcher has already handled queue cancellation at
        -- its own macro level. Never dispatch a nested cancellation macro.
        if (autoFollowup or commandFollowup) and self:GetAttribute("type")=="macro" then return false end
        return nil,true
    ]], [[
        if self:GetAttribute("sh-watch-position") then self:CallMethod("EndPositionAttempt") end
        -- Each click selects its own action. Keep a neutral spell action between clicks.
        if self:GetAttribute("type") ~= "spell" then
            self:SetAttribute("type","spell")
            self:SetAttribute("macrotext",nil)
            self:SetAttribute("action",nil)
        end
    ]])
    button.Icon = button:CreateTexture(nil, "BACKGROUND")
    button.Icon:SetAllPoints()
    button.Icon:SetTexture(QUESTION_MARK)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button.Caption = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.Caption:SetPoint("TOP", button, "BOTTOM", 0, -3)
    button.Caption:SetWidth(180)
    button.Caption:SetText(self.label)
    button.Badge = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.Badge:SetPoint("CENTER")
    button.Badge:SetText("PREPARE")
    button:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "selected-row" or name == "ready" then self:UpdateButtonVisual() end
    end)
    local function showTooltip()
        if self.db.hideTooltip then return end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.label)
        local selected = self.activeRules and self.activeRules[button:GetAttribute("selected-row") or 0]
        if selected then GameTooltip:AddLine("Last selected: " .. selected.displayName, 1, 1, 1) end
        GameTooltip:AddLine(button:GetAttribute("sh-has-custom-rule") and
            "Custom Rules use this button, Set cast key, or a controller binding. They cannot run from the action-bar macro." or
            ("Click or use the " .. self.label .. " action-bar macro to cast. /snh opens setup."), 0.6, 0.85, 0.9, true)
        GameTooltip:AddLine("For cast interrupts, assign a key with Set cast key or a gamepad button with Controller in /snh.", 0.6, 0.85, 0.9, true)
        GameTooltip:AddLine("Hold Shift and left-drag to move outside combat.", 0.6, 0.85, 0.9, true)
        GameTooltip:AddLine(button:GetAttribute("sh-modifier-ctrl") and
            "Ctrl+right-click this button to hide or show this tooltip." or
            "Ctrl+left-click this button to hide or show this tooltip.", 0.6, 0.85, 0.9, true)
        GameTooltip:Show()
    end
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- This child receives physical clicks only. Prepare assigns the tooltip
    -- gesture without competing with a configured Ctrl rule. Macros and
    -- direct keys still address the named casting button.
    local tooltipToggle = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
    tooltipToggle:SetAllPoints(button)
    tooltipToggle:RegisterForClicks("AnyUp")
    tooltipToggle:SetAttribute("useOnKeyDown", false)
    tooltipToggle:SetAttribute("type", "click")
    tooltipToggle:SetAttribute("clickbutton", button)
    tooltipToggle:SetAttribute("ctrl-type1", "none")
    tooltipToggle:SetAttribute("ctrl-shift-type1", "none")
    tooltipToggle:SetAttribute("alt-ctrl-type1", "none")
    tooltipToggle:SetAttribute("alt-ctrl-shift-type1", "none")
    tooltipToggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tooltipToggle:SetScript("OnEnter", showTooltip)
    tooltipToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tooltipToggle:HookScript("OnClick", function(_, mouseButton)
        local tooltipMouse = button:GetAttribute("sh-modifier-ctrl") and "RightButton" or "LeftButton"
        if mouseButton ~= tooltipMouse or not IsControlKeyDown() then return end
        self.db.hideTooltip = not self.db.hideTooltip
        if self.db.hideTooltip then GameTooltip:Hide() else showTooltip() end
    end)
    button.tooltipToggle = tooltipToggle

    button:RegisterForDrag("LeftButton")
    tooltipToggle:RegisterForDrag("LeftButton")
    local function mouseDown(_, mouseButton)
        if mouseButton ~= "LeftButton" or InCombatLockdown() or IsControlKeyDown() then return end
        self.dragToken = (self.dragToken or 0) + 1
        button:SetAttribute("sh-suppress-click", IsShiftKeyDown() and not button:GetAttribute("sh-modifier-shift") and true or nil)
    end
    local function dragStart(_, mouseButton)
        if mouseButton ~= "LeftButton" or InCombatLockdown() or IsControlKeyDown() or not IsShiftKeyDown() then return end
        button:SetAttribute("sh-suppress-click", true)
        button:SetAttribute("sh-dragging", true)
        self.dragging = true
        button:StartMoving()
    end
    local function dragStop()
        self:FinishButtonDrag()
        self:QueueDragCleanup()
    end
    local function mouseUp(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        self:FinishButtonDrag()
        self:QueueDragCleanup()
    end
    for _, receiver in ipairs({button, tooltipToggle}) do
        receiver:HookScript("OnMouseDown", mouseDown)
        receiver:SetScript("OnDragStart", dragStart)
        receiver:SetScript("OnDragStop", dragStop)
        receiver:HookScript("OnMouseUp", mouseUp)
    end
    self.button = button
    button:SetShown(self:IsEnabled() and self.db.showButton ~= false)
    return button
end

function SH:SetButtonVisible(shown)
    if InCombatLockdown() then return false, "Leave combat before changing button visibility." end
    if not self:IsEnabled() then return false, "Enable " .. self.label .. " first." end
    self.db.showButton = shown and true or false
    local button = self:CreateCastButton()
    if button then button:SetShown(self.db.showButton) end
    return true, self.label .. (self.db.showButton and " shown." or " hidden; its action-bar macro still works.")
end

function SH:CreateAutoAttackButton()
    if self.autoAttackButton then return self.autoAttackButton end
    if InCombatLockdown() then return nil end
    local cast = self:CreateCastButton()
    if not cast then return nil end
    local button = CreateFrame("Button", self.buttonName .. "AutoAttack", UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type", "spell")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("unit", "target")
    button:SetFrameRef("cast", cast)
    SecureHandlerWrapScript(button, "OnClick", button, [[
        self:SetAttribute("spell",nil)
        local cast=self:GetFrameRef("cast")
        if not cast or not cast:GetAttribute("ready") or not cast:GetAttribute("sh-has-auto-attack") then return false end
        if cast:GetAttribute("sh-has-custom-rule") and not cast:GetAttribute("sh-command-followup") then return false end
        cast:SetAttribute("sh-auto-followup",true)
        if cast:GetAttribute("sh-suppress-click") or cast:GetAttribute("sh-dragging") then return false end
        -- This pass stops at the first eligible normal action, without
        -- submitting it or arming its count, delay, or positioning checks.
        cast:RunAttribute("sh-select-auto")
        if cast:GetAttribute("sh-valid")~=true or cast:GetAttribute("type")~="spell" or cast:GetAttribute("spell")~=6603 then return false end
        self:SetAttribute("spell",6603)
        if cast:GetAttribute("sh-error-filter") then cast:CallMethod("NoteErrorFilterAttempt") end
        return nil,true
    ]], [[self:SetAttribute("spell",nil)]])
    self.autoAttackButton = button
    return button
end

local function macroBodies(rotation, autoAttack)
    local buttonName = rotation.buttonName
    local action = (autoAttack and "/click " .. buttonName .. "AutoAttack\n" or "") .. "/click " .. buttonName
    local body = "#showtooltip\n" .. action
    local protected = "#showtooltip\n/cancelqueuedspell [channeling]\n" .. action
    local counted = "#showtooltip\n/cancelqueuedspell\n" .. action
    return body, protected, counted
end

local function normalizeMacroBody(body)
    if type(body) ~= "string" then return nil end
    -- Compare commands, allowing line endings and whitespace from saved macros.
    -- Keep command order, arguments, and click targets intact.
    local lines = {}
    body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in body:gmatch("[^\n]+") do
        line = line:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
        if line ~= "" then lines[#lines + 1] = line end
    end
    return table.concat(lines, "\n")
end

local function ownsMacro(rotation, body)
    body = normalizeMacroBody(body)
    local plain, protected, counted = macroBodies(rotation)
    local autoPlain, autoProtected, autoCounted = macroBodies(rotation, true)
    return body == plain or body == protected or body == counted or
        body == autoPlain or body == autoProtected or body == autoCounted or
        body == CUSTOM_RULE_MACRO_BODY or (rotation.index ~= 1 and body == DISABLED_MACRO_BODY)
end

function SH:EnsureMacro()
    if InCombatLockdown() then return false, "Leave combat before creating the macro." end
    if not self:IsEnabled() then return false, "Enable " .. self.label .. " first." end
    -- Use the applied setting, not an unprepared draft checkbox change.
    local plain, protected, counted = macroBodies(self, self.button and self.button:GetAttribute("sh-has-auto-attack"))
    local desiredBody = self.db.preparedPreventClipping ~= false and protected or plain
    if self.button and (self.button:GetAttribute("sh-has-riposte") or self.button:GetAttribute("sh-has-condition-cooldowns")) then desiredBody = counted end
    for _, row in ipairs(self.db.preparedRules or {}) do
        if row.enabled ~= false and ((tonumber(row.castCount) or 0) > 0 or row.comboPoints ~= nil or row.pingDelay == true or row.manualCooldown == true or row.targetCasting == true or row.totemCondition ~= nil or row.hawkCount ~= nil or row.skipIfNotCasted == true or row.skipIfImmune == true or row.skipOutOfRange == true or row.outOfCombatOnly == true or row.inCombatOnly == true or row.skipModifier ~= nil or row.priorityModifier ~= nil or
            (type(row.resourceConditions) == "table" and #row.resourceConditions > 0) or
            (type(row.healthConditions) == "table" and #row.healthConditions > 0) or
            (type(row.stackConditions) == "table" and #row.stackConditions > 0) or
            (type(row.logicConditions) == "table" and #row.logicConditions > 0) or row.primaryCondition ~= nil) then desiredBody = counted; break end
    end
    if self.button and self.button:GetAttribute("sh-has-custom-rule") then desiredBody = CUSTOM_RULE_MACRO_BODY end
    -- Interrupts use the directly bound dispatcher. Never run a second macro
    -- through this action-bar macro, or consume a proc on a blocked nested call.
    local index = GetMacroIndexByName(self.macroName)
    if index and index > 0 then
        local _, _, body = GetMacroInfo(index)
        if not ownsMacro(self, body) then
            return false, "You already have a " .. self.label .. " macro."
        end
    end
    if index and index > 0 then
        local name, _, body = GetMacroInfo(index)
        if name ~= self.macroName or normalizeMacroBody(body) ~= desiredBody then
            -- Keep existing action-bar placements and use the returned index.
            local ok, result = pcall(EditMacro, index, self.macroName, QUESTION_MARK, desiredBody)
            if not ok or not result or result == 0 then return false, "Could not update the " .. self.label .. " macro. Try Prepare again outside combat." end
            index = result
        end
    else
        local ok, result = pcall(CreateMacro, self.macroName, QUESTION_MARK, desiredBody, true)
        if not ok or not result or result == 0 then
            return false, "Could not create the macro. Free a character-specific macro slot, then retry."
        end
        index = result
    end
    return true, index
end

function SH:CreateOrPickupMacro()
    if InCombatLockdown() then return false, "Leave combat before creating an action-bar button." end
    if not self:IsEnabled() then return false, "Enable " .. self.label .. " first." end
    if not self.prepared or self.stale then return false, "Prepare a valid rotation first." end
    if GetCursorInfo() then return false, "Place or clear what is currently on your cursor first." end
    local ok, index = self:EnsureMacro()
    if not ok then return false, index end
    PickupMacro(index)
    return true, self.label .. " is on your cursor. Drop it into an action-bar slot and use that slot's keybind."
end

function SH:OpenTrackerSettings()
    if InCombatLockdown() then return false, "Leave combat before opening tracker settings." end
    if not CooldownViewerSettings and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
    end
    if CooldownViewerSettings then
        if CooldownViewerSettings.ShowUIPanel then CooldownViewerSettings:ShowUIPanel()
        else ShowUIPanel(CooldownViewerSettings) end
        return true, "Aura rules use Buff Bars / Icons with inactive entries hidden. Skip while on cooldown uses Essential / Utility entries. No alert is needed. Close settings before Prepare."
    end
    return false, "Open the game's Cooldown Manager settings. Use Buff Bars / Icons for auras and Essential / Utility for cooldowns."
end

function SH:DisablePrepared(message)
    self.readinessRefs, self.readinessSource, self.readinessCastSource = nil, nil, nil
    if SH.Readiness then SH.Readiness.Invalidate() end
    self.prepared = false
    self.suspendedPrepared = nil
    self.recoveryNeedsRebuild = self.recoveryPending and true or nil
    self.preparedAccessHint = nil
    self.statusText = message
    if self.button and not InCombatLockdown() then
        self.button:SetAttribute("ready", false)
        self.button:SetAttribute("type", "spell")
        self.button:SetAttribute("macrotext", nil)
        self.button:SetAttribute("spell", nil)
        self.button:SetAttribute("selected-row", nil)
        self.button:SetAttribute("selected-primary", nil)
        self.button:SetAttribute("selected-or", nil)
        self.button:SetAttribute("selected-legacy-or", nil)
        self.button:SetAttribute("sh-valid", false)
        self.button:SetAttribute("sh-auto-followup", nil)
        self.button:SetAttribute("sh-has-auto-attack", nil)
        self.button:SetAttribute("sh-select-auto", nil)
        self.button:SetAttribute("sh-select-cast", nil)
        self.button:SetAttribute("sh-has-custom-rule", nil)
        self.button:SetAttribute("sh-select-custom", nil)
        self.button:SetAttribute("sh-custom-prefix", nil)
        self.button:SetAttribute("sh-custom-followup-body", nil)
        self.button:SetAttribute("sh-command-followup", nil)
        self.button:SetAttribute("sh-command-target-dirty", nil)
        self.button:SetAttribute("sh-command-target-change", nil)
        self.button:SetAttribute("sh-command-executes", nil)
        if self.button.tooltipToggle then
            self.button.tooltipToggle:SetAttribute("type", "click")
            self.button.tooltipToggle:SetAttribute("macrotext", nil)
            self.button.tooltipToggle:SetAttribute("clickbutton", self.button)
        end
        configureModifierClicks(self.button)
        self.button:SetAttribute("sh-has-counts", nil)
        self.button:SetAttribute("sh-has-combo", nil)
        self.button:SetAttribute("sh-combo-count", -1)
        self.button:SetAttribute("sh-has-resources", nil)
        self.button:SetAttribute("sh-resource-pass", nil)
        self.button:SetAttribute("sh-has-health", nil)
        self.button:SetAttribute("sh-read-health", nil)
        self.button:SetAttribute("sh-health-pass", nil)
        self.button:SetAttribute("sh-has-stacks", nil)
        self.button:SetAttribute("sh-has-logic", nil)
        self.button:SetAttribute("sh-read-stacks", nil)
        self.button:SetAttribute("sh-stacks-pass", nil)
        self.button:SetAttribute("sh-has-aura-time", nil)
        self.button:SetAttribute("sh-read-aura-time", nil)
        self.button:SetAttribute("sh-aura-time-pass", nil)
        self.button:SetAttribute("sh-has-ping", nil)
        self.button:SetAttribute("sh-ping-pass", nil)
        self.button:SetAttribute("sh-read-totem", nil)
        self.button:SetAttribute("sh-totem-ready", nil)
        self.button:SetAttribute("shfire-read-slot", nil)
        self.button:SetAttribute("sh-has-fire-totems", nil)
        self.button:SetAttribute("sh-hawk-read", nil)
        self.button:SetAttribute("sh-hawk-count", -1)
        self.button:SetAttribute("sh-has-hawks", nil)
        self.button:SetAttribute("sh-read-player-buff", nil)
        self.button:SetAttribute("sh-read-target-effect", nil)
        self.button:SetAttribute("sh-target-effect-present", nil)
        self.button:SetAttribute("sh-has-target-casting", nil)
        self.button:SetAttribute("sh-read-target-casting", nil)
        self.button:SetAttribute("sh-target-casting", nil)
        self.button:SetAttribute("sh-read-riposte", nil)
        self.button:SetAttribute("sh-riposte-ready", nil)
        self.button:SetAttribute("sh-read-reactive", nil)
        self.button:SetAttribute("sh-reactive-ready", nil)
        self.button:SetAttribute("sh-has-riposte", nil)
        if self.button:GetAttribute("sh-has-position-skip") then
            self.button:SetAttribute("sh-has-position-skip", nil)
            updatePositionMonitoring()
        end
        self.button:SetAttribute("sh-has-immunity-skip", nil)
        self.button:SetAttribute("sh-read-immunity-skip", nil)
        self.button:SetAttribute("sh-immunity-skip", nil)
        self.button:SetAttribute("sh-position-awaiting-click", nil)
        self.button:SetAttribute("sh-read-position-skip", nil)
        self.button:SetAttribute("sh-position-skip", nil)
        self.button:SetAttribute("sh-read-range", nil)
        self.button:SetAttribute("sh-out-of-range", nil)
        self.button:SetAttribute("sh-range-outside-ready", nil)
        self.button:SetAttribute("sh-range-outside-result", nil)
        self.button:SetAttribute("sh-has-range", nil)
        self.button:SetAttribute("sh-has-out-of-combat", nil)
        self.button:SetAttribute("sh-has-in-combat", nil)
        self.button:SetAttribute("sh-has-modifiers", nil)
        self.button:SetAttribute("sh-has-condition-cooldowns", nil)
        self.button:SetAttribute("sh-buff-present", nil)
        self.button:SetAttribute("sh-wand-active", nil)
        self.button:SetAttribute("sh-wand-hold", nil)
        self.button:SetAttribute("sh-pet-attack", nil)
        self.button:SetAttribute("action", nil)
        self.button:SetAttribute("sh-count-wait", nil)
        self.button:SetAttribute("sh-pending-row", nil)
        self.button:SetAttribute("sh-pending-epoch", nil)
        for index = 1, M.MAX_RULES do
            self.button:SetAttribute("sh-command-done" .. index, nil)
            self.button:SetAttribute("sh-ping-enabled" .. index, nil)
            self.button:SetAttribute("sh-used" .. index, nil)
            self.button:SetAttribute("sh-stop" .. index, nil)
            self.button:SetAttribute("sh-stopped" .. index, nil)
            self.button:SetAttribute("sh-or-stop" .. index, nil)
            self.button:SetAttribute("sh-or-stopped" .. index, nil)
            self.button:SetAttribute("sh-stop-invalid" .. index, nil)
            self.button:SetAttribute("sh-aura-match" .. index, nil)
            self.button:SetAttribute("sh-extra" .. index, nil)
            self.button:SetAttribute("sh-extra-or" .. index, nil)
        end
        if self.directButton then
            self.directButton:SetAttribute("sh-last-row", nil)
            self.directButton:SetAttribute("macrotext", nil)
        end
    end
    if not InCombatLockdown() then
        if SH.CastCounts then SH.CastCounts.Detach(self) end
        if SH.PingDelay and self.button then SH.PingDelay:Detach(self.button) end
        if SH.TotemCooldown and self.button then SH.TotemCooldown:Release(self.button) end
        if SH.FireTotems and self.button then SH.FireTotems:Release(self.button) end
        if SH.HawkCount and self.button then SH.HawkCount:Release(self.button) end
        if SH.PlayerBuff and self.button then SH.PlayerBuff:Release(self.button) end
        if SH.TargetEffect and self.button then SH.TargetEffect:Release(self.button) end
        if SH.TargetCasting and self.button then SH.TargetCasting:Release(self.button) end
        if SH.Riposte and self.button then SH.Riposte:Release(self.button) end
        if SH.Health and self.button then SH.Health:Release(self.button) end
        if SH.AuraStacks and self.button then SH.AuraStacks:Release(self.button) end
        if SH.AuraTime and self.button then SH.AuraTime:Release(self.button) end
        if SH.PositionSkip and self.button then SH.PositionSkip:Release(self.button) end
        if SH.ImmunitySkip and self.button then SH.ImmunitySkip:Release(self.button) end
        if SH.Range and self.button then SH.Range:Release(self.button) end
        for _, guard in pairs(self.guards) do
            guard:Hide()
            guard:SetParent(UIParent)
        end
        if self.RefreshDirectKeyBindings and self:IsEnabled() and self.boundKey then
            local bound, reason = self:RefreshDirectKeyBindings({})
            if not bound then
                if self.ReleaseDirectKey then self:ReleaseDirectKey() end
                self.statusText = self.statusText .. " Cast key: " .. reason
            end
        end
    end
    self:UpdateButtonVisual()
    self:NotifyUI()
end

-- Notices belong to the last applied rotation. Draft edits never become live
-- merely because the game rebuilt a tracker or the player changed zones.
function SH:RequirePreparation(reason, cause, repeatFailure)
    if not self:IsEnabled() then return end
    if not self.db.preparedRules or #self.db.preparedRules == 0 then return end
    local request = self.db.preparationRequest
    cause = cause or reason
    if not request or request.cause ~= cause or request.reason ~= reason or repeatFailure then
        self.db.preparationSerial = (tonumber(self.db.preparationSerial) or 0) + 1
        request = {reason = reason, cause = cause, id = tostring(self.index) .. ":" .. self.db.preparationSerial}
        self.db.preparationRequest = request
    end
    self.recoveryPending, self.recoveryAttempts, self.recoveryNeedsRebuild = nil, nil, nil
    if InCombatLockdown() then
        if not self.stale then say(reason .. " Stop using Stand and Hit until combat ends.") end
        self.stale = true
        self.statusText = reason .. " Stop using the button; leave combat and Prepare again."
    else
        self:DisablePrepared("Preparation required: " .. reason)
        self.stale = true
    end
    self:UpdateButtonVisual()
    self:NotifyUI()
end

function SH:ClearPreparationRequest()
    self.db.preparationRequest = nil
    self.recoveryPending, self.recoveryAttempts, self.suspendedPrepared, self.recoveryNeedsRebuild = nil, nil, nil, nil
    self.suspendedStatus = nil
end

function SH:GetPreparationRequests()
    local requests = {}
    for _, rotation in ipairs(SH.rotations or {}) do
        local request = rotation.db.preparationRequest
        if rotation:IsEnabled() and request and request.dismissed ~= request.id then
            requests[#requests + 1] = {rotation = rotation, label = rotation.label,
                reason = request.reason, id = request.id}
        end
    end
    return requests
end

function SH:DismissPreparationRequests()
    for _, request in ipairs(SH:GetPreparationRequests()) do
        request.rotation.db.preparationRequest.dismissed = request.id
    end
    SH:NotifyUI()
end

function SH:PrepareRequestedRotations()
    if InCombatLockdown() then return false, "Leave combat, then click Prepare." end
    local errors = {}
    for _, request in ipairs(SH:GetPreparationRequests()) do
        local rotation = request.rotation
        local rules = rotation.db.preparedRules
        local ok, reason = rotation:Prepare(rules, {restore = true, requested = true,
            preventClipping = rotation.db.preparedPreventClipping})
        if not ok then errors[#errors + 1] = rotation.label .. ": " .. reason end
    end
    SH:NotifyUI()
    return #errors == 0, #errors == 0 and "Rotations prepared." or table.concat(errors, "\n")
end

function SH:SuspendPrepared(reason)
    if not self.recoveryPending then
        self.recoveryPending, self.recoveryAttempts = true, 0
        self.suspendedStatus = self.statusText
    end
    if InCombatLockdown() then
        if not self.stale then say(reason .. " Stop using Stand and Hit until combat ends.") end
        self.statusText = reason .. " Stop using the button; setup will recover after combat."
    else
        -- Keep installed observers and proc memory while their references are
        -- unchanged. Full Prepare would reset an in-progress cast batch.
        self.suspendedPrepared, self.prepared = true, false
        if self.button then self.button:SetAttribute("ready", false) end
        self.statusText = reason .. " Waiting for the trackers to become available."
    end
    self.stale = true
    self:UpdateButtonVisual()
    self:NotifyUI()
end

function SH:CheckPreparationState()
    if not SH.GetPreparationState then return true end
    local state, available = SH.GetPreparationState()
    if available == false then SH.preparationCandidate = nil; return false end
    local complete = true
    local matchesSaved, compared = true, false
    local completedTalentBaselines = {}
    for _, rotation in ipairs(SH.rotations or {}) do
        if rotation:IsEnabled() and rotation.db.preparedRules then
            local previous = rotation.db.preparationState
            if SH.preparationHydrating and previous and SH.CompletePreparationTalentBaseline then
                local completed = SH.CompletePreparationTalentBaseline(previous.talents, state.talents)
                if completed ~= previous.talents then completedTalentBaselines[rotation] = completed end
            end
            for _, key in ipairs({"talents", "spells"}) do
                local value = key == "talents" and completedTalentBaselines[rotation] or previous and previous[key]
                if value then
                    compared = true
                    if state[key] == nil then complete = false end
                    if value ~= state[key] then matchesSaved = false end
                elseif state[key] ~= nil then matchesSaved = false end
            end
        end
    end
    if SH.preparationHydrating then
        if not complete then SH.preparationCandidate = nil; return false end
        -- Matching the last complete saved baseline is already corroborated.
        -- Otherwise require a second settled reading before a login/zoning
        -- snapshot can invalidate it or establish a missing baseline.
        if next(state) and not (compared and matchesSaved) then
            local candidate = SH.preparationCandidate
            if not candidate or candidate.talents ~= state.talents or candidate.spells ~= state.spells then
                SH.preparationCandidate = M.Copy(state)
                return false
            end
        end
        for _, rotation in ipairs(SH.rotations or {}) do
            local request, previous = rotation.db.preparationRequest, rotation.db.preparationState
            if previous and completedTalentBaselines[rotation] then previous.talents = completedTalentBaselines[rotation] end
            if rotation:IsEnabled() and request and previous then
                local kind = type(request.cause) == "string" and request.cause:match("^(%a+):")
                -- Recover a transient startup notice only when its saved
                -- semantic baseline is now confirmed unchanged. Real changes
                -- and unrelated/dismissed preparation requests remain intact.
                if (kind == "talents" or kind == "spells") and previous[kind] and
                    previous[kind] == state[kind] and (request.cause ~= kind .. ":" .. state[kind] or
                    (kind == "talents" and completedTalentBaselines[rotation])) then
                    rotation:ClearPreparationRequest()
                    rotation.stale, rotation.restoreAttempts = nil, 0
                elseif request.cause == "state-unavailable" and complete then
                    rotation:ClearPreparationRequest()
                    rotation.stale, rotation.restoreAttempts = nil, 0
                end
            end
        end
        SH.preparationHydrating, SH.preparationCandidate, SH.loginPreparationPending = nil, nil, nil
    end
    for _, rotation in ipairs(SH.rotations or {}) do
        if rotation:IsEnabled() and rotation.db.preparedRules then
            local previous = rotation.db.preparationState
            local request = rotation.db.preparationRequest
            if request and request.pendingStateKind and state[request.pendingStateKind] then
                local kind = request.pendingStateKind
                -- The precise event and its later complete fingerprint describe
                -- the same change. Keep its dismissal and identity intact.
                request.cause = kind .. ":" .. state[kind]
                request.reason = kind == "talents" and "talent changes" or "changes to your learned spells or spell ranks"
                request.pendingStateKind = nil
            end
            if previous then
                for key in pairs(previous) do if state[key] == nil then complete = false end end
                if previous.talents and state.talents and previous.talents ~= state.talents then
                    rotation:RequirePreparation("talent changes", "talents:" .. state.talents)
                elseif previous.spells and state.spells and previous.spells ~= state.spells then
                    rotation:RequirePreparation("changes to your learned spells or spell ranks", "spells:" .. state.spells)
                end
                for key, value in pairs(state) do
                    if previous[key] == nil then previous[key] = value end
                end
            else
                -- Older saved rotations have no comparable baseline yet.
                rotation.db.preparationState = M.Copy(state)
            end
        end
    end
    return complete
end

local function preparedAccessHint(rotation)
    if rotation.button and rotation.button:GetAttribute("sh-has-custom-rule") then
        return " Custom Rules use the visible Hit Button, Set cast key, or a controller binding. The action-bar macro cannot run this rotation."
    end
    if rotation.boundGamePadKey then
        local keyboard = rotation.boundKey and (" Cast key: " .. rotation.boundKey .. ".") or ""
        return keyboard .. " Controller: " .. rotation.boundGamePadKey .. ". Use fresh presses for " .. rotation.label .. "."
    end
    if rotation.boundKey then
        return " Cast key: " .. rotation.boundKey .. ". Use fresh presses for " .. rotation.label .. "."
    end
    return " " .. rotation.label .. " macro is ready; drag it to your action bar or use Set cast key."
end

function SH:UpdatePreparedAccessHint()
    if not self.prepared or not self.preparedAccessHint then return end
    local first, last = self.statusText:find(self.preparedAccessHint, 1, true)
    if not first then return end
    self.preparedAccessHint = preparedAccessHint(self)
    self.statusText = self.statusText:sub(1, first - 1) .. self.preparedAccessHint .. self.statusText:sub(last + 1)
end

function SH:Prepare(rawRules, options)
    options = options or {}
    if InCombatLockdown() then return false, "Leave combat, then click Prepare." end
    if not self:IsEnabled() then return false, "Enable " .. self.label .. " first." end
    if not options.recovery then
        self.recoveryPending, self.recoveryAttempts, self.recoveryNeedsRebuild = nil, nil, nil
        self.suspendedStatus = nil
    end
    local button = self:CreateCastButton()
    self:DisablePrepared("Preparing...")
    self.stale = nil
    if not options.restore then self.db.manualPrepareFailed = true end
    local function fail(message)
        self:DisablePrepared("Not prepared. " .. message)
        if options.requested or (not options.restore and self.db.preparationRequest) then
            self:RequirePreparation(message, "prepare-failed", true)
        end
        return false, message
    end
    if settingsOpen() then return fail("Close Cooldown Manager settings and Edit Mode, then Prepare.") end
    local rules, errorText = M.NormalizeRules(rawRules, resolveSpell)
    if not rules then return fail(errorText) end
    local hasCombo, hasActionState, hasPet, hasPing, hasManual = false, false, false, false, false
    local hasTargetCasting, hasRiposte, hasPositionSkip, hasImmunitySkip = false, false, false, false
    local hasFireTotems, hasRange, hasAutoAttack, hasOutOfCombat, hasInCombat, hasHawks = false, false, false, false, false, false
    local hasModifiers, hasConditionCooldowns, customRuleText = false, false, nil
    local shaman = isShaman()
    local pingRequests = {}
    local resourceRequests = M.ResourceRequests(rules)
    local hasResources = #resourceRequests > 0
    local healthRequests = M.HealthRequests(rules)
    local hasHealth = #healthRequests > 0
    local stackRequests = M.StackRequests(rules)
    local hasStacks = #stackRequests > 0
    local auraTimeRequests = M.AuraTimeRequests(rules)
    local hasAuraTime = #auraTimeRequests > 0
    local hasLogic = false
    local reactiveSpellIDs = {}
    for _, row in ipairs(rules) do
        if row.customRule then customRuleText = row.customRule end
        if SH.Riposte and SH.Riposte.IsReactive(row.spellID) then
            if SH.Riposte.Family(row.spellID) == 7384 and row.unit ~= "target" then
                return fail("Rule " .. row.sourceIndex .. ": Overpower readiness is checked against your current target. Set Cast on to Target.")
            end
            row.reactiveReady, hasRiposte = row.spellID, true
            reactiveSpellIDs[row.spellID] = true
            -- Read the activation window, resources, stance and actual cooldown
            -- on every press. These gates also apply to Always and OR rules.
            row.skipCooldown = false
            local function markReactive(owner, marker, text, source, state, conditionKey)
                if state == "always" or (source ~= "tracker" and source ~= "player") or
                    not SH.Riposte.MatchesCondition(text, spellName, row.spellID) then return end
                owner[marker] = true
                if row.castCount > 0 and row.castCountCondition == conditionKey then
                    return true
                end
            end
            local counted = markReactive(row, "reactiveAura", row.aura, row.auraSource, row.condition, "primary")
            if row.reactiveAura then row.oncePerProc = false end
            if row.useOr then
                counted = markReactive(row, "orReactiveAura", row.orAura, row.orAuraSource, row.orCondition, "or") or counted
            end
            for _, group in ipairs({"andConditions", "notConditions", "orConditions"}) do
                for conditionIndex, item in ipairs(row[group]) do
                    counted = markReactive(item, "reactiveAura", item.aura, item.auraSource, item.condition,
                        group .. ":" .. conditionIndex) or counted
                end
            end
            if counted then
                return fail("Rule " .. row.sourceIndex .. ": " .. row.displayName .. " readiness has no aura to count. Remove Cast Count from this condition.")
            end
        end
        if row.primaryCondition ~= nil or #(row.logicConditions or {}) > 0 then hasLogic = true end
        if row.comboPoints or M.HasLogicType(row, "comboPoints") then hasCombo = true end
        if row.hawkCount or M.HasLogicType(row, "hawkCount") then
            if not isHunter() then return fail("Rule " .. row.sourceIndex .. ": Hawk conditions require a Hunter.") end
            hasHawks = true
        end
        if row.targetCasting or M.HasLogicType(row, "targetCasting") then hasTargetCasting = true end
        if row.outOfCombatOnly then hasOutOfCombat = true end
        if row.inCombatOnly then hasInCombat = true end
        if row.skipModifier or row.priorityModifier then hasModifiers = true end
        if row.useOr and row.orAuraSource == "cooldown" then hasConditionCooldowns = true end
        for _, list in ipairs({row.andConditions, row.notConditions, row.orConditions}) do
            for _, item in ipairs(list) do if item.auraSource == "cooldown" then hasConditionCooldowns = true end end
        end
        if row.totemCondition or M.HasLogicType(row, "totemCondition") then
            if not shaman then return fail("Rule " .. row.sourceIndex .. ": totem conditions require a shaman.") end
            hasFireTotems = true
        end
        if row.skipIfNotCasted then hasPositionSkip = true end
        if row.skipIfImmune then hasImmunitySkip = true end
        if row.skipOutOfRange then hasRange = true end
        if row.rangedRepeat or row.petAttack or row.startAttack or row.advanceOnToggle then hasActionState = true end
        if row.startAttack then hasAutoAttack = true end
        if row.petAttack then hasPet = true end
        if row.pingDelay or row.manualCooldown then hasPing = true end
        if row.manualCooldown then hasManual = true end
    end
    if hasCombo and (not SH.ComboPoints or type(SH.ComboPoints.READ_SNIPPET) ~= "string") then
        return fail("Combo points are unavailable. Reinstall the complete addon.")
    end
    if hasResources and (not SH.Resources or type(SH.Resources.READ_SNIPPET) ~= "string") then
        return fail("Resource conditions are unavailable. Reinstall the complete addon.")
    end
    if hasHealth and (not SH.Health or type(SH.Health.READ_SNIPPET) ~= "string") then
        return fail("Health conditions are unavailable. Reinstall the complete addon.")
    end
    if hasStacks and (not SH.AuraStacks or type(SH.AuraStacks.READ_SNIPPET) ~= "string") then
        return fail("Aura stack conditions are unavailable. Reinstall the complete addon.")
    end
    if hasAuraTime and (not SH.AuraTime or type(SH.AuraTime.READ_SNIPPET) ~= "string") then
        return fail("Aura time conditions are unavailable. Reinstall the complete addon.")
    end
    if hasTargetCasting and (not SH.TargetCasting or type(SH.TargetCasting.READ_SNIPPET) ~= "string") then
        return fail("The target casting check is unavailable. Reinstall the complete addon.")
    end
    if hasFireTotems and (not SH.FireTotems or type(SH.FireTotems.READ_SNIPPET) ~= "string") then
        return fail("Totem conditions are unavailable. Reinstall the complete addon.")
    end
    if hasHawks and (not SH.HawkCount or type(SH.HawkCount.READ_SNIPPET) ~= "string") then
        return fail("Hawk conditions are unavailable. Reinstall the complete addon.")
    end
    if hasImmunitySkip and (not SH.ImmunitySkip or type(SH.ImmunitySkip.READ_SNIPPET) ~= "string") then
        return fail("Skip if immune (bleed) is unavailable. Reinstall the complete addon.")
    end
    if hasPositionSkip and (not SH.PositionSkip or type(SH.PositionSkip.READ_SNIPPET) ~= "string") then
        return fail("Require being behind target is unavailable. Reinstall the complete addon.")
    end
    if hasRange and (not SH.Range or type(SH.Range.READ_SNIPPET) ~= "string") then
        return fail("Skip if out of range is unavailable. Reinstall the complete addon.")
    end
    if hasPing and (not SH.PingDelay or type(SH.PingDelay.READ_SNIPPET) ~= "string") then
        return fail("Manual cooldown and Ping Delay are unavailable. Reinstall the complete addon.")
    end
    if hasActionState and (not SH.WandShoot or type(SH.WandShoot.READ_SNIPPET) ~= "string") then
        return fail("Attack actions are unavailable. Reinstall the complete addon.")
    end
    if hasPet and not SH.PetAttack then
        return fail("Pet Attack is unavailable. Reinstall the complete addon.")
    end
    local preventClipping = options.preventClipping
    if preventClipping == nil then preventClipping = self.db.preventClipping ~= false end
    for index, row in ipairs(rules) do
        if row.oncePerProc and not preventClipping then
            return fail("Rule " .. (row.sourceIndex or index) .. ": enable Protect channels to use Once per proc.")
        end
    end
    local signals, orSignals, extraSignals, cooldownSignals, countSignals, errors = {}, {}, {}, {}, {}, {}
    local conditionCooldownSignals = {}
    local spellCooldownIDs = {}
    for spellID in pairs(reactiveSpellIDs) do spellCooldownIDs[spellID] = true end
    local playerBuffs, buffKeys, groupedBuffKeys = {}, {}, {}
    local targetEffects = {}
    if shaman then
        for _, row in ipairs(rules) do
            -- These summons are placed at the caster. Decoy Totem can target
            -- an ally. Keep explicit party/focus/mouseover targeting intact.
            local family = totemSummons[row.spellID]
            -- Forever's Fire Nova detonates at the active fire totem. These
            -- spell IDs are its ranks, distinct from the old Fire Nova Totem.
            local fireNova = (row.totemCondition or M.HasLogicType(row, "totemCondition")) and row.spellID and row.spellID >= 408341 and row.spellID <= 408345
            row.castAtFeet = (family ~= nil and family ~= 425874 or fireNova)
                and (row.unit == "target" or row.unit == "player")
        end
    end
    local function conditionObserver(row, conditionKey, state)
        if row.castCount > 0 and row.castCountCondition == conditionKey then return "Cast Count" end
        if row.oncePerProc and conditionKey == "primary" then return "Once per proc" end
        if row.stopCasting and state == "present" and (conditionKey == "primary" or conditionKey == "or") then
            return "Stop current cast"
        end
    end
    local function findCondition(row, owner, conditionKey)
        -- Reactive abilities have an activation window, not a player buff.
        -- Reuse the same fresh readiness result for every matching condition.
        if (conditionKey == "or" and row.orReactiveAura) or
            (conditionKey ~= "or" and owner.reactiveAura) then return end
        local text, state = owner.aura, owner.condition
        local sourceField, keyField = "auraSource", "playerBuffKey"
        if conditionKey == "or" then
            text, state = row.orAura, row.orCondition
            sourceField, keyField = "orAuraSource", "orPlayerBuffKey"
        end
        local source = owner[sourceField]
        if SH.WarriorStances then
            local stance, reason = SH.WarriorStances.Resolve(text, source, spellName)
            if reason then return nil, reason end
            if stance then
                owner[conditionKey == "or" and "orFormSlot" or "formSlot"] = stance.formSlot
                return stance
            end
        end
        if source == "cooldown" then
            local spell, reason = resolveSpell(text)
            if not spell then return nil, reason end
            local referenced = {spell = spell.cast, spellID = spell.id, displayName = spell.name, cooldownCondition = true}
            local entry, cooldownError = self:FindCooldown(referenced)
            if not entry then return nil, cooldownError end
            entry.conditionRow = referenced
            if entry.spellCooldownID then
                referenced.spellCooldownID = entry.spellCooldownID
                owner[conditionKey == "or" and "orCooldownSpellID" or "cooldownSpellID"] = entry.spellCooldownID
                spellCooldownIDs[entry.spellCooldownID] = true
            end
            return entry
        end
        local buff, reason, groupedEntry
        if source == "tracker" and shaman then
            buff = namedTotemBuff(text)
            if buff then
                -- A totem frame can stay shown after its buff leaves the player.
                -- Options that count proc transitions still need native frame events.
                local observer = conditionObserver(row, conditionKey, state)
                if observer then
                    local frame, trackerError = self:FindAura(text, source)
                    if frame then return frame end
                    return nil, observer .. " needs a dedicated tracked aura for this condition. " .. trackerError
                end
                -- Only the normalized copy changes. Old drafts and imports use
                -- the same player-buff reader as a newly configured Player buff.
                owner[sourceField] = "player"
            end
        end
        if not buff and source ~= "player" then
            local entry, trackerError = self:FindAura(text, source)
            if entry and entry.groupedPlayerBuff then
                local observer = conditionObserver(row, conditionKey, state)
                if observer then return nil, observer .. " needs a dedicated tracker for this " .. entry.groupedPlayerBuff.kind .. "." end
                -- Compile the normalized condition using the player-buff reader.
                -- Keep the original group solely for out-of-combat revalidation.
                owner[sourceField], buff, groupedEntry = "player", entry.groupedPlayerBuff, entry
            elseif entry and entry.formSlot then
                owner[conditionKey == "or" and "orFormSlot" or "formSlot"] = entry.formSlot
            elseif entry and entry.targetEffect then
                if SH.Judgements and SH.Judgements.IsEntry(entry) then
                    local observer = conditionObserver(row, conditionKey, state)
                    if observer then
                        return nil, observer .. " needs a dedicated proc tracker for Judgement debuffs. Use the present/missing condition without this option."
                    end
                end
                if SH.Gouge and SH.Gouge.IsEntry(entry) then
                    local observer = conditionObserver(row, conditionKey, state)
                    if observer then
                        return nil, observer .. " needs a dedicated target-aura tracker for Gouge. Its native entry tracks a player-side proxy."
                    end
                end
                local primaryStop, orStop = M.StopBranches(row)
                local needsProc = (conditionKey == "primary" and (row.oncePerProc or (row.stopCasting and primaryStop)))
                    or (conditionKey == "or" and row.stopCasting and orStop)
                if needsProc then
                    if not (SH.Frostbite and SH.Frostbite.IsEntry(entry)) then
                        return nil, "Once per proc and Stop current cast need a separate tracker for this curse."
                    end
                    entry.needsEffectObserver = true
                    local border = entry.frame.DebuffBorder
                    if border and safeMethod(border, "GetParent") == entry.frame and not safeMethod(border, "IsForbidden") then
                        entry.debuffReference = border
                    end
                end
                local key
                for index, effect in ipairs(targetEffects) do
                    if sameIDs(effect.ids, entry.targetEffect.ids) then key = index; break end
                end
                if not key then key = #targetEffects + 1; targetEffects[key] = entry.targetEffect end
                owner[conditionKey == "or" and "orTargetEffectKey" or "targetEffectKey"] = key
            end
            if not groupedEntry then return entry, trackerError end
        end
        if not SH.PlayerBuff then return nil, "the Player buff reader is missing. Reinstall the complete addon." end
        if not buff then buff, reason = resolvePlayerBuff(self, text) end
        if not buff then return nil, reason end
        local keys = buff.groupedPlayerBuff and groupedBuffKeys or buffKeys
        local identity = buff.memberID or buff.name
        local key = keys[identity]
        if not key then
            key = #playerBuffs + 1
            playerBuffs[key], keys[identity] = buff, key
        else
            for id in pairs(buff.ids) do playerBuffs[key].ids[id] = true end
        end
        owner[keyField] = key
        return groupedEntry
    end
    for index, row in ipairs(rules) do
        if row.pingDelay or row.manualCooldown then
            local source, reason = SH.PingDelay.FindSource(row)
            if not source then errors[#errors + 1] = "Rule " .. (row.sourceIndex or index) .. " (" .. row.displayName .. (row.manualCooldown and " manual cooldown): " or " Ping Delay): ") .. reason
            else pingRequests[index] = {delayMs = row.pingDelay and row.pingDelayMS or 0,
                cooldownSeconds = row.manualCooldown and row.manualCooldownSeconds or 0, source = source, row = row} end
        end
        if row.condition ~= "always" and not row.reactiveAura then
            local entry, reason = findCondition(row, row, "primary")
            if reason then errors[#errors + 1] = "Rule " .. (row.sourceIndex or index) .. " aura (" .. row.aura .. "): " .. reason
            else signals[index] = entry end
        end
        if row.useOr then
            local entry, reason = findCondition(row, row, "or")
            if reason then errors[#errors + 1] = "Rule " .. (row.sourceIndex or index) .. " OR aura (" .. row.orAura .. "): " .. reason
            elseif row.orAuraSource == "cooldown" then conditionCooldownSignals["orAura" .. index] = entry
            else orSignals[index] = entry end
        end
        for _, group in ipairs({{"and", "AND", "andConditions"}, {"not", "NOT", "notConditions"}, {"orExtra", "OR", "orConditions"}}) do
            for conditionIndex, condition in ipairs(row[group[3]]) do
                local entry, reason = findCondition(row, condition, group[3] .. ":" .. conditionIndex)
                if reason then
                    errors[#errors + 1] = "Rule " .. (row.sourceIndex or index) .. " " .. group[2] .. " condition " .. conditionIndex ..
                        " (" .. condition.aura .. "): " .. reason
                elseif condition.auraSource == "cooldown" then
                    conditionCooldownSignals[group[1] .. "Aura" .. index .. "_" .. conditionIndex] = entry
                else
                    extraSignals[group[1] .. "Aura" .. index .. "_" .. conditionIndex] = entry
                end
            end
        end
        -- The aura error already explains the missing dependency. Do not also
        -- report a cooldown-pairing error caused by that same missing entry.
        if row.skipCooldown and not row.manualCooldown and (row.condition == "always" or signals[index] or row.playerBuffKey) then
            local entry, reason = self:FindCooldown(row, signals[index])
            if not entry then errors[#errors + 1] = "Rule " .. (row.sourceIndex or index) .. " (" .. row.displayName .. " cooldown): " .. reason
            else
                cooldownSignals[index] = entry
                if entry.spellCooldownID then
                    row.spellCooldownID = entry.spellCooldownID
                    spellCooldownIDs[entry.spellCooldownID] = true
                end
            end
        end
        if row.castCount and row.castCount > 0 then
            if not SH.CastCounts then
                errors[#errors + 1] = "Rule " .. (row.sourceIndex or index) .. ": cast counting is unavailable. Reinstall the complete addon."
            else
                local entry, reason = SH.CastCounts.Find(row)
                if not entry then errors[#errors + 1] = "Rule " .. (row.sourceIndex or index) .. " (" .. row.displayName .. " cast count): " .. reason
                else countSignals[index] = entry end
            end
        end
    end
    if #errors > 0 then return fail(table.concat(errors, "\n")) end
    local snippet = M.Compile(rules, preventClipping)
    local ok, installError = pcall(function()
        if #targetEffects > 0 then
            local prepared, reason = SH.TargetEffect:Prepare(button, targetEffects)
            assert(prepared, reason)
            button:SetAttribute("sh-read-target-effect", SH.TargetEffect.READ_SNIPPET)
        end
        if hasTargetCasting then
            local prepared, reason = SH.TargetCasting:Prepare(button)
            assert(prepared, reason)
            button:SetAttribute("sh-read-target-casting", SH.TargetCasting.READ_SNIPPET)
        end
        button:SetAttribute("sh-has-target-casting", hasTargetCasting)
        button:SetAttribute("sh-has-out-of-combat", hasOutOfCombat)
        button:SetAttribute("sh-has-in-combat", hasInCombat)
        button:SetAttribute("sh-has-modifiers", hasModifiers)
        configureModifierClicks(button, rules)
        if hasFireTotems then
            local prepared, reason = SH.FireTotems:Prepare(button)
            assert(prepared, reason)
            button:SetAttribute("shfire-read-slot", SH.FireTotems.READ_SNIPPET)
        end
        button:SetAttribute("sh-has-fire-totems", hasFireTotems)
        if hasHawks then
            local prepared, reason = SH.HawkCount:Prepare(button)
            assert(prepared, reason)
            button:SetAttribute("sh-hawk-read", SH.HawkCount.READ_SNIPPET)
        end
        button:SetAttribute("sh-has-hawks", hasHawks)
        button:SetAttribute("sh-hawk-count", -1)
        if #playerBuffs > 0 then
            local prepared, reason = SH.PlayerBuff:Prepare(button, playerBuffs)
            assert(prepared, reason)
            button:SetAttribute("sh-read-player-buff", SH.PlayerBuff.READ_SNIPPET)
        end
        if next(spellCooldownIDs) then
            local prepared, reason = SH.TotemCooldown:Prepare(button, spellCooldownIDs)
            assert(prepared, reason)
            button:SetAttribute("sh-read-totem", SH.TotemCooldown.READ_SNIPPET)
        end
        if hasRiposte then
            local prepared, reason = SH.Riposte:Prepare(button, reactiveSpellIDs)
            assert(prepared, reason)
            button:SetAttribute("sh-read-reactive", SH.Riposte.REACTIVE_READ_SNIPPET)
        end
        button:SetAttribute("sh-has-riposte", hasRiposte)
        if hasImmunitySkip then
            local prepared, reason = SH.ImmunitySkip:Prepare(button, rules)
            assert(prepared, reason)
            button:SetAttribute("sh-read-immunity-skip", SH.ImmunitySkip.READ_SNIPPET)
            button:SetAttribute("sh-has-immunity-skip", true)
        end
        if hasPositionSkip then
            local prepared, reason = SH.PositionSkip:Prepare(button, rules)
            assert(prepared, reason)
            button:SetAttribute("sh-read-position-skip", SH.PositionSkip.READ_SNIPPET)
            button:SetAttribute("sh-has-position-skip", true)
            updatePositionMonitoring()
        end
        if hasRange then
            local prepared, reason = SH.Range:Prepare(button, rules)
            assert(prepared, reason)
            button:SetAttribute("sh-read-range", SH.Range.READ_SNIPPET)
            button:SetAttribute("sh-has-range", true)
        end
        if hasPing then
            local preparedPing, pingError = SH.PingDelay:Prepare(pingRequests)
            assert(preparedPing, pingError)
            local attachedPing, attachError = SH.PingDelay:Attach(button, pingRequests)
            assert(attachedPing, attachError)
            button:SetAttribute("sh-read-ping", SH.PingDelay.READ_SNIPPET)
        end
        button:SetAttribute("sh-has-ping", hasPing)
        button:SetAttribute("sh-ping-pass", nil)
        for index, row in ipairs(rules) do button:SetAttribute("sh-ping-enabled" .. index, row.pingDelay or row.manualCooldown or nil) end
        if hasPet then
            local preparedPet, petError = SH.PetAttack:Prepare()
            assert(preparedPet, petError)
        end
        if hasActionState then
            local preparedWand, wandError = SH.WandShoot:Prepare()
            assert(preparedWand, wandError)
            local attachedWand, attachError = SH.WandShoot:Attach(button)
            assert(attachedWand, attachError)
            button:SetAttribute("sh-read-wand", SH.WandShoot.READ_SNIPPET)
        end
        button:SetAttribute("sh-wand-active", nil)
        button:SetAttribute("sh-wand-hold", nil)
        if hasCombo then
            local preparedCombo, comboError = SH.ComboPoints:Prepare()
            assert(preparedCombo, comboError)
            local attachedCombo, attachError = SH.ComboPoints:Attach(button)
            assert(attachedCombo, attachError)
            button:SetAttribute("sh-read-combo", SH.ComboPoints.READ_SNIPPET)
        end
        button:SetAttribute("sh-has-combo", hasCombo)
        button:SetAttribute("sh-combo-count", -1)
        if hasResources then
            local preparedResources, resourceError = SH.Resources:Prepare(resourceRequests)
            assert(preparedResources, resourceError)
            local attachedResources, attachError = SH.Resources:Attach(button, resourceRequests)
            assert(attachedResources, attachError)
            button:SetAttribute("sh-read-resource", SH.Resources.READ_SNIPPET)
        end
        button:SetAttribute("sh-has-resources", hasResources)
        button:SetAttribute("sh-resource-pass", nil)
        if hasHealth then
            local preparedHealth, healthError = SH.Health:Prepare(healthRequests)
            assert(preparedHealth, healthError)
            local attachedHealth, attachError = SH.Health:Attach(button, healthRequests)
            assert(attachedHealth, attachError)
            button:SetAttribute("sh-read-health", SH.Health.READ_SNIPPET)
        end
        button:SetAttribute("sh-has-health", hasHealth)
        button:SetAttribute("sh-health-pass", nil)
        if hasStacks then
            local preparedStacks, stackError = SH.AuraStacks:Prepare(stackRequests)
            assert(preparedStacks, stackError)
            local attachedStacks, attachError = SH.AuraStacks:Attach(button, stackRequests)
            assert(attachedStacks, attachError)
            button:SetAttribute("sh-read-stacks", SH.AuraStacks.READ_SNIPPET)
        end
        button:SetAttribute("sh-has-stacks", hasStacks)
        button:SetAttribute("sh-has-logic", hasLogic)
        button:SetAttribute("sh-stacks-pass", nil)
        if hasAuraTime then
            local preparedTime, timeError = SH.AuraTime:Prepare(auraTimeRequests)
            assert(preparedTime, timeError)
            local attachedTime, attachError = SH.AuraTime:Attach(button, auraTimeRequests)
            assert(attachedTime, attachError)
            button:SetAttribute("sh-read-aura-time", SH.AuraTime.READ_SNIPPET)
        end
        button:SetAttribute("sh-has-aura-time", hasAuraTime)
        button:SetAttribute("sh-aura-time-pass", nil)
        -- Keep an ordinary, read-only reference map for the optional companion.
        self.readinessRefs = {}
        -- SetFrameRef rejects nil. Old, unused reference labels are harmless;
        -- the new immutable snippet only reads the labels it actually uses.
        local function installReference(label, frame)
            if not self.guards[frame] then
                self.guards[frame] = CreateFrame("Frame", nil, frame, "SecureHandlerShowHideTemplate")
            end
            self.guards[frame]:SetParent(frame)
            self.guards[frame]:Show()
            assert(frame:IsProtected(), "The native tracker did not become protected.")
            button:SetFrameRef(label, frame)
            self.readinessRefs[label] = frame
        end
        local function installProc(label, frame, border)
            local guard = self.guards[frame]
            guard:SetAttribute("sh-proc-epoch", 0)
            guard:SetAttribute("sh-effect-present", nil)
            guard:SetAttribute("sh-effect-seen-epoch", nil)
            guard:SetAttribute("_onhide", [[
                -- A new proc cycle requires the aura entry itself to hide.
                if self:GetParent():IsShown() == false then
                    self:SetAttribute("sh-proc-epoch", self:GetAttribute("sh-proc-epoch") + 1)
                end
            ]])
            button:SetFrameRef(label, guard)
            self.readinessRefs[label] = guard
            if border then
                local borderGuard = self.guards[border]
                borderGuard:SetFrameRef("targetProc", guard)
                borderGuard:SetAttribute("_onhide", [[
                    -- A duration display may keep the item visible after its
                    -- aura ends. The native border hides only for no aura.
                    if self:GetParent():IsShown() == false then
                        local g = self:GetFrameRef("targetProc")
                        if g then g:SetAttribute("sh-proc-epoch", g:GetAttribute("sh-proc-epoch") + 1) end
                    end
                ]])
            end
        end
        local function installAura(label, signal)
            if signal.groupedPlayerBuff or (signal.targetEffect and not signal.needsEffectObserver) then return end
            local frame = signal.frame
            if signal.formSlot then
                local formFrame, reason = SH.DruidFormSignal.Get(signal.formSlot)
                assert(formFrame, reason)
                frame = formFrame
            end
            signal.auraFrame = frame
            installReference(label, frame)
        end
        for index, signal in pairs(signals) do
            installAura("aura" .. index, signal)
            if signal.debuffReference then installReference("debuff" .. index, signal.debuffReference) end
            local primaryStop = M.StopBranches(rules[index])
            if rules[index].oncePerProc or (rules[index].stopCasting and primaryStop) then
                installProc("proc" .. index, signal.auraFrame, signal.debuffReference)
            end
        end
        for index, signal in pairs(cooldownSignals) do
            if not signal.spellCooldownID then
                installReference("cooldown" .. index, signal.reference)
                installReference("timer" .. index, signal.timerReference)
            end
        end
        for label, signal in pairs(conditionCooldownSignals) do
            if not signal.spellCooldownID then
                installReference(label .. "Cooldown", signal.reference)
                installReference(label .. "Timer", signal.timerReference)
            end
        end
        for index, signal in pairs(orSignals) do
            installAura("orAura" .. index, signal)
            if signal.debuffReference then installReference("orDebuff" .. index, signal.debuffReference) end
            local _, orStop = M.StopBranches(rules[index])
            if rules[index].stopCasting and orStop then
                installProc("orProc" .. index, signal.auraFrame, signal.debuffReference)
            end
        end
        for label, signal in pairs(extraSignals) do
            installAura(label, signal)
            if signal.debuffReference then
                installReference(label:gsub("Aura", "Debuff"), signal.debuffReference)
            end
        end
        local function installReactiveProc(index, alternative)
            button.riposteGuards = button.riposteGuards or {}
            local key = alternative and "or" .. index or index
            local guard = button.riposteGuards[key]
            if not guard then
                guard = CreateFrame("Frame", nil, button, "SecureHandlerBaseTemplate")
                button.riposteGuards[key] = guard
            end
            guard:SetAttribute("sh-proc-epoch", 0)
            guard:SetAttribute("sh-effect-present", nil)
            guard:SetAttribute("sh-effect-seen-epoch", nil)
            button:SetFrameRef((alternative and "orProc" or "proc") .. index, guard)
            self.readinessRefs[(alternative and "orProc" or "proc") .. index] = guard
        end
        for index, row in ipairs(rules) do
            local primaryStop, orStop = M.StopBranches(row)
            if row.reactiveAura and row.stopCasting and primaryStop then installReactiveProc(index, false) end
            if row.orReactiveAura and row.stopCasting and orStop then installReactiveProc(index, true) end
            if countSignals[index] then
                local attachment = M.GetCountCondition(row)
                assert(attachment and attachment.countEligible, "The cast-count condition is unavailable.")
                local signal
                if attachment.key == "primary" then signal = signals[index]
                elseif attachment.key == "or" then signal = orSignals[index]
                elseif attachment.group == "andConditions" then
                    signal = extraSignals["andAura" .. index .. "_" .. attachment.index]
                elseif attachment.group == "orConditions" then
                    signal = extraSignals["orExtraAura" .. index .. "_" .. attachment.index]
                end
                assert(signal and signal.auraFrame, "The selected cast-count aura is unavailable.")
                local counter, countError = SH.CastCounts.Install(self, index, row, signal.auraFrame, countSignals[index])
                assert(counter, countError or "The cast-count observer could not be installed.")
                self.readinessRefs["count" .. index] = counter
                local observer = self.castCountObservers and self.castCountObservers[index]
                if observer then
                    observer.readinessCheckSource = counter:GetAttribute("sh-check")
                    observer.readinessCastingSource = counter:GetAttribute("sh-casting")
                end
            end
            if row.stopCasting then
                local primaryStop, orStop = M.StopBranches(row)
                button:SetAttribute("sh-stop" .. index, primaryStop)
                button:SetAttribute("sh-or-stop" .. index, orStop)
            end
            button:SetAttribute("sh-stop-invalid" .. index, row.stopWhenInvalid or nil)
        end
        local hasCounts = next(countSignals) ~= nil
        button:SetAttribute("sh-has-counts", hasCounts)
        local directBody = preventClipping and "/cancelqueuedspell [channeling]\n/stopmacro [channeling]\n/click " or "/click "
        button:SetAttribute("sh-has-condition-cooldowns", hasConditionCooldowns)
        if hasCounts or hasCombo or hasResources or hasHealth or hasStacks or hasAuraTime or hasLogic or hasPing or hasTargetCasting or hasFireTotems or hasHawks or hasRiposte or hasPositionSkip or hasImmunitySkip or hasRange or hasOutOfCombat or hasInCombat or hasModifiers or hasConditionCooldowns then
            directBody = "/cancelqueuedspell\n" .. (preventClipping and "/stopmacro [channeling]\n" or "") .. "/click "
        end
        local nativeClicks = self.buttonName
        if hasAutoAttack then
            assert(self:CreateAutoAttackButton(), "Auto Attack is unavailable.")
            nativeClicks = self.buttonName .. "AutoAttack\n/click " .. self.buttonName
        end
        directBody = directBody .. nativeClicks
        local customPrefix = "/cancelqueuedspell\n" .. (preventClipping and "/stopmacro [channeling]\n" or "")
        local customFollowup = "/click " .. nativeClicks
        if customRuleText then
            assert(#customPrefix + #customRuleText + 1 + #customFollowup <= 1023,
                "Custom Rule is too long after adding the rotation's next action. Shorten its macro commands and Prepare again.")
        end
        button:SetAttribute("sh-has-custom-rule", customRuleText ~= nil)
        button:SetAttribute("sh-select-custom", customRuleText and M.Compile(rules, preventClipping, "custom") or nil)
        button:SetAttribute("sh-custom-prefix", customRuleText and customPrefix or nil)
        button:SetAttribute("sh-custom-followup-body", customRuleText and customFollowup or nil)
        button:SetAttribute("sh-has-auto-attack", hasAutoAttack)
        button:SetAttribute("sh-auto-followup", nil)
        button:SetAttribute("sh-select-auto", hasAutoAttack and M.Compile(rules, preventClipping, "auto") or nil)
        button:SetAttribute("sh-select-cast", customRuleText and M.Compile(rules, preventClipping, "final") or hasAutoAttack and M.Compile(rules, preventClipping, "cast") or nil)
        button:SetAttribute("sh-direct-cast", directBody)
        -- The visible overlay starts a top-level macro. Both commands in it
        -- click native spell actions, as does the generated action-bar macro.
        -- Its final selector must still see a channeling press to confirm a
        -- pending Once per proc cast. That selector also protects the channel.
        button.tooltipToggle:SetAttribute("type", hasAutoAttack and "macro" or "click")
        button.tooltipToggle:SetAttribute("macrotext", hasAutoAttack and directBody:gsub("/stopmacro %[channeling%]\n", "") or nil)
        self:CreateDirectButton()
        if customRuleText then
            button.tooltipToggle:SetAttribute("type", "click")
            button.tooltipToggle:SetAttribute("macrotext", nil)
            button.tooltipToggle:SetAttribute("clickbutton", self.directButton)
        else button.tooltipToggle:SetAttribute("clickbutton", button) end
        button:SetAttribute("sh-setup-check", nil)
        button:Execute([[self:SetAttribute("sh-setup-check",42)]])
        assert(button:GetAttribute("sh-setup-check") == 42, "Secure snippets did not run on this client.")
        button:SetAttribute("sh-select", snippet)
        self.readinessSource = snippet
        self.readinessCastSource = button:GetAttribute("sh-select-cast")
        button:SetAttribute("type", "spell")
        button:SetAttribute("macrotext", nil)
        button:SetAttribute("ready", true)
    end)
    if not ok then return fail("Secure setup failed: " .. tostring(installError)) end
    self.activeRules, self.signals, self.orSignals, self.extraSignals = rules, signals, orSignals, extraSignals
    self.cooldownSignals, self.prepared = cooldownSignals, true
    self.conditionCooldownSignals = conditionCooldownSignals
    if SH.Readiness then SH.Readiness.Invalidate() end
    self.stale = nil
    local previousRules, previousClipping = self.db.preparedRules, self.db.preparedPreventClipping
    self.db.preparedRules = M.Copy(rawRules)
    self.db.preparedPreventClipping = preventClipping
    self.db.manualPrepareFailed = nil
    self:UpdateDraftState()
    self.statusText = "Prepared " .. #rules .. " spell rule" .. (#rules == 1 and "" or "s") .. ". First matching rule wins on each press."
    if next(cooldownSignals) then
        self.statusText = self.statusText .. " Skip while on cooldown is enabled for the checked rules. No cooldown alert is needed."
    end
    if hasConditionCooldowns then self.statusText = self.statusText .. " Spell cooldown conditions use the referenced spell's Essential / Utility entry." end
    if next(countSignals) then
        self.statusText = self.statusText .. " Cast limits count completed casts. Keep their spell buttons on the same visible Blizzard bar."
    end
    if hasCombo then self.statusText = self.statusText .. " Combo-point conditions read the current target on each press." end
    for _, row in ipairs(rules) do
        if row.stopCasting or row.stopWhenInvalid then
            self.statusText = self.statusText .. " Interrupts use the direct cast key or assigned gamepad button; use Set cast key or Controller."
            break
        end
    end
    local macroOK, macroResult = self:EnsureMacro()
    if macroOK then
        self.preparedAccessHint = preparedAccessHint(self)
        self.statusText = self.statusText .. self.preparedAccessHint
    elseif next(countSignals) or hasCombo or hasResources or hasHealth or hasStacks or hasAuraTime or hasLogic or hasPing or hasTargetCasting or hasFireTotems or hasHawks or hasRiposte or hasPositionSkip or hasImmunitySkip or hasRange or hasOutOfCombat or hasInCombat or hasModifiers or hasConditionCooldowns then
        -- A previous macro may lack the queue command required by these checks.
        -- Keep the last successful snapshot and disable this incomplete setup.
        self.db.preparedRules, self.db.preparedPreventClipping = previousRules, previousClipping
        if not options.restore then self.db.manualPrepareFailed = true end
        self:UpdateDraftState()
        return fail((hasCombo and "Combo-point conditions" or hasResources and "Resource conditions" or hasHealth and "Health conditions" or hasStacks and "Aura stack conditions" or hasAuraTime and "Aura time conditions" or hasManual and "Manual cooldown rules" or hasPing and "Ping Delay rules" or hasTargetCasting and "Target casting conditions" or hasFireTotems and "Totem conditions" or hasHawks and "Hawk conditions" or hasRiposte and "Riposte rules" or hasImmunitySkip and "Rules with Skip if immune (bleed)" or hasPositionSkip and "Rules with Require being behind target" or hasRange and "Rules with Skip if out of range" or hasOutOfCombat and "Rules with Out of combat only" or hasInCombat and "Rules with In combat only" or hasModifiers and "Modifier rules" or hasConditionCooldowns and "Spell cooldown conditions" or hasLogic and "Rule conditions" or "Cast limits") .. " require the updated " .. self.label .. " macro. " .. macroResult)
    else
        self.statusText = self.statusText .. " Macro setup needs attention: " .. macroResult
    end
    if self.RefreshDirectKeyBindings then
        local bound, reason = self:RefreshDirectKeyBindings(rules)
        if not bound then
            self.db.preparedRules, self.db.preparedPreventClipping = previousRules, previousClipping
            if not options.restore then self.db.manualPrepareFailed = true end
            self:UpdateDraftState()
            return fail("Cast key: " .. reason)
        end
    end
    self:UpdateButtonVisual()
    self:ClearPreparationRequest()
    if SH.GetPreparationState then
        local state, available = SH.GetPreparationState()
        self.db.preparationState = self.db.preparationState or {}
        if available ~= false then
            for key, value in pairs(state) do self.db.preparationState[key] = value end
        end
    end
    self:NotifyUI()
    return true, self.statusText
end

local function isActiveTracker(signal)
    local pool = signal.viewer and signal.viewer.itemFramePool
    if not pool then return false end
    -- Secure pool enumeration creates an iterator on every validation tick.
    -- Its membership query checks the same active set without that allocation.
    if type(pool.IsActive) == "function" then
        local active = pool:IsActive(signal.frame)
        if type(issecretvalue) == "function" and issecretvalue(active) then return false end
        return type(active) == "boolean" and active
    end
    if type(pool.EnumerateActive) ~= "function" then return false end
    for frame in pool:EnumerateActive() do if frame == signal.frame then return true end end
    return false
end

local function checkAuraReference(signal, scratch)
    if signal.warriorStance then
        if InCombatLockdown() then return end
        if not SH.WarriorStances or SH.WarriorStances.LearnedSpellID(signal.formSlot) ~= signal.formSpellID then
            return "The stances on your stance bar changed.", "reference"
        end
        return
    end
    if signal.judgementConfig then
        if InCombatLockdown() then return end
        local reason = SH.Judgements and SH.Judgements.CheckConfigured(signal)
        if not SH.Judgements then reason = "The Judgement tracker reader is unavailable." end
        if reason then return reason, "reference" end
        return
    end
    local frame, viewer = signal.frame, signal.viewer
    if signal.targetEffect or signal.groupedPlayerBuff then
        -- The prepared ID filter follows the unit. The grouped icon can
        -- change its tooltip and active spell while its membership stays fixed.
        if InCombatLockdown() then return end
        if isActiveTracker(signal) and safeMethod(frame, "GetBaseSpellID") == signal.baseID then
            local info = safeMethod(frame, "GetCooldownInfo")
            local ids = info and info.linkedSpellIDs or EMPTY
            if info and #ids == signal.effectLinkCount then
                local matches = true
                for _, id in ipairs(ids) do
                    if not signal.linkedIDs[id] then matches = false; break end
                end
                if matches then return end
            end
        end
        if signal.groupedPlayerBuff then return "The " .. signal.groupedPlayerBuff.groupName .. " tracker or its linked spells changed.", "reference" end
        return "The target debuff's tracker entry or linked spells changed.", "reference"
    end
    if signal.formSlot then
        -- The grouped tracker identifies the member at Prepare. Combat presses
        -- only use the stance slot, including when the tracker changes its icon.
        if InCombatLockdown() then return end
        if SH.DruidForms.LearnedSpellID(signal.formSlot) ~= signal.formSpellID then
            return "The forms on your stance bar changed.", "reference"
        end
        local info = safeMethod(frame, "GetCooldownInfo")
        if isActiveTracker(signal) and safeMethod(frame, "GetBaseSpellID") == signal.baseID then
            for _, id in ipairs(info and info.linkedSpellIDs or EMPTY) do
                if id == signal.formSpellID then return end
            end
        end
        return "The Druid Forms tracker or its linked forms changed.", "reference"
    end
    local current = describeFrame(frame, viewer, scratch)
    if not isActiveTracker(signal) or not sameIdentity(signal, current) then
        return "Blizzard reassigned a tracked aura frame or changed its linked spells.", "reference"
    elseif frame.hideWhenInactive ~= true or frame.allowHideWhenInactive ~= true then
        return "A tracked aura no longer hides when inactive.", "configuration"
    elseif viewer.visibleSetting and Enum and Enum.CooldownViewerVisibleSetting and
        viewer.visibleSetting ~= Enum.CooldownViewerVisibleSetting.Always then
        return "A required tracker group is no longer set to Always visible.", "configuration"
    elseif not viewer:IsShown() then return "A required tracker group is temporarily unavailable.", "visibility"
    end
    if signal.auraSource == "target" then
        local targetError = targetAuraError(current, true)
        if targetError then return "Target debuff setup changed: " .. targetError, "configuration" end
        if current.debuffReference ~= signal.debuffReference then
            return "Blizzard changed a target debuff's aura-presence frame.", "reference"
        end
    end
end

local function checkAuraGroup(group, scratch)
    for _, signal in pairs(group or EMPTY) do
        local reason, category = checkAuraReference(signal, scratch)
        if reason then return reason, category end
    end
end

local function checkCooldownReference(signal, row, aura, scratch, auraScratch)
    local current = describeFrame(signal.frame, signal.viewer, scratch)
    if not isActiveTracker(signal) or not sameIdentity(signal, current) then
        return "Blizzard changed a tracked cooldown reference.", "reference"
    end
    if not signal.spellCooldownID and (safeMethod(signal.frame, "GetCooldownFlashFrame") ~= signal.reference or
        safeMethod(signal.frame, "GetCooldownFrame") ~= signal.timerReference) then
        return "Blizzard changed a tracked cooldown reference.", "reference"
    end
    local viewer = signal.viewer
    if viewer.visibleSetting and Enum and Enum.CooldownViewerVisibleSetting and
        viewer.visibleSetting ~= Enum.CooldownViewerVisibleSetting.Always then
        return "A required tracker group is no longer set to Always visible.", "configuration"
    elseif not viewer:IsShown() then return "A required tracker group is temporarily unavailable.", "visibility" end
    if aura and not aura.formSlot and not aura.targetEffect and not aura.groupedPlayerBuff then
        aura = describeFrame(aura.frame, aura.viewer, auraScratch)
    end
    local problem = cooldownEntryError(current, row, aura)
    if problem then return "Cooldown setup changed: " .. problem, "configuration" end
    if current.spellCooldownID ~= signal.spellCooldownID or current.noAuraDisplay ~= signal.noAuraDisplay then
        return "A tracked cooldown changed how it displays its timer.", "configuration"
    end
end

local function checkPreparedReferences(rotation)
    if settingsOpen() then return "Tracker settings / Edit Mode are open.", "settings" end
    local timingIssue, countIssue
    if SH.PingDelay and rotation.button and rotation.button:GetAttribute("sh-has-ping") then
        timingIssue = SH.PingDelay:PreparationIssue(rotation)
        if timingIssue and timingIssue.category ~= "timing-availability" then
            return timingIssue.reason, timingIssue.category
        end
    end
    if SH.CastCounts then
        countIssue = SH.CastCounts.PreparationIssue and SH.CastCounts.PreparationIssue(rotation)
        if countIssue and countIssue.category ~= "count-availability" then return countIssue.reason, countIssue.category end
        local countError = SH.CastCounts.Validate(rotation)
        if countError then return countError, "configuration" end
    end
    -- A paired cooldown check needs both descriptions alive at once. Neither
    -- scratch record is ever stored in the prepared signal tables.
    rotation.validationScratch = rotation.validationScratch or {}
    rotation.validationAuraScratch = rotation.validationAuraScratch or {}
    local scratch, auraScratch = rotation.validationScratch, rotation.validationAuraScratch
    local reason, category = checkAuraGroup(rotation.signals, scratch)
    if reason then return reason, category end
    reason, category = checkAuraGroup(rotation.orSignals, scratch)
    if reason then return reason, category end
    reason, category = checkAuraGroup(rotation.extraSignals, scratch)
    if reason then return reason, category end
    for index, signal in pairs(rotation.cooldownSignals) do
        reason, category = checkCooldownReference(signal, rotation.activeRules[index], rotation.signals[index], scratch, auraScratch)
        if reason then return reason, category end
    end
    for _, signal in pairs(rotation.conditionCooldownSignals or EMPTY) do
        reason, category = checkCooldownReference(signal, signal.conditionRow, nil, scratch, auraScratch)
        if reason then return reason, category end
    end
    -- Validate every other reference even when a spell's action bar is hidden.
    if countIssue then return countIssue.reason, countIssue.category end
    if timingIssue then return timingIssue.reason, timingIssue.category end
end

function SH:CheckPreparedReferences()
    if not self.prepared and not self.suspendedPrepared then return end
    local readable, reason, category = pcall(checkPreparedReferences, self)
    if not readable then
        local detailOK, detail = pcall(validationErrorDetail, reason)
        local message = "A tracked aura or cooldown reference could not be checked."
        if detailOK and detail and detail ~= "" then message = message .. " Details: " .. detail end
        return {reason = message, category = "reference"}
    end
    if reason then return {reason = reason, category = category} end
end

function SH:ValidatePrepared()
    if not self.prepared and not self.suspendedPrepared then return end
    if self.db.preparationRequest then
        if not InCombatLockdown() and self.prepared then
            self:DisablePrepared("Preparation required: " .. self.db.preparationRequest.reason)
        end
        return false, self.db.preparationRequest
    end
    local issue = self:CheckPreparedReferences()

    -- Timed and counted rows check their own bar availability. Keep other
    -- rules usable while a required bar is temporarily unavailable.
    if issue and (issue.category == "timing-availability" or issue.category == "count-availability") then return true end
    if issue then
        -- During loading, native settings can briefly contain their defaults.
        -- Validate the settled values before calling that a configuration edit.
        if issue.category == "configuration" and not SH.worldLoading and (SH.worldSettleRemaining or 0) <= 0 then
            self:RequirePreparation(issue.reason, issue.category .. ":" .. issue.reason)
        else
            self:SuspendPrepared(issue.reason)
        end
        return false, issue
    end
    return true
end

local function sameMeaning(left, right)
    if not right or left.baseID ~= right.baseID or not sameIDs(left.ids, right.ids) or
        not sameIDs(left.linkedIDs, right.linkedIDs) then return false end
    for key, value in pairs(left.metadata) do if right.metadata[key] ~= value then return false end end
    for key, value in pairs(right.metadata) do if left.metadata[key] ~= value then return false end end
    return true
end

function SH:CanRecoverPrepared()
    local replacements = {}
    for _, group in ipairs({self.signals, self.orSignals, self.extraSignals or {}}) do
        for _, signal in pairs(group) do
            local replacement, reason = self:FindAura(signal.effectInput or tostring(signal.formSpellID or signal.baseID), signal.auraSource)
            if not replacement then return false, reason end
            if signal.targetEffect then
                if not replacement.targetEffect or not sameIDs(signal.targetEffect.ids, replacement.targetEffect.ids) then
                    return false, "The target debuff's tracked spell IDs changed.", true
                end
            elseif signal.groupedPlayerBuff then
                if not replacement.groupedPlayerBuff or not sameIDs(signal.groupedPlayerBuff.ids, replacement.groupedPlayerBuff.ids) then
                    return false, "The selected " .. signal.groupedPlayerBuff.kind .. " is no longer in the " .. signal.groupedPlayerBuff.groupName .. " tracker.", true
                end
            elseif signal.formSlot then
                if replacement.formSpellID ~= signal.formSpellID then
                    return false, signal.warriorStance and "The selected stance is no longer on your stance bar."
                        or "The selected form is no longer in the Druid Forms tracker.", true
                end
            elseif not sameMeaning(signal, replacement) then
                return false, "A tracked aura's linked spells or options changed.", true
            end
            replacements[signal] = replacement
        end
    end
    for index, signal in pairs(self.cooldownSignals) do
        local replacement, reason = self:FindCooldown(self.activeRules[index], replacements[self.signals[index]])
        if not replacement then return false, reason end
        if not sameMeaning(signal, replacement) or signal.noAuraDisplay ~= replacement.noAuraDisplay or
            signal.spellCooldownID ~= replacement.spellCooldownID then
            return false, "A tracked cooldown's linked spells or options changed.", true
        end
    end
    for _, signal in pairs(self.conditionCooldownSignals or EMPTY) do
        local replacement, reason = self:FindCooldown(signal.conditionRow)
        if not replacement then return false, reason end
        if not sameMeaning(signal, replacement) or signal.noAuraDisplay ~= replacement.noAuraDisplay or
            signal.spellCooldownID ~= replacement.spellCooldownID then
            return false, "A spell cooldown condition's linked spells or options changed.", true
        end
    end
    return true
end

function SH:RecoverPrepared()
    if not self.recoveryPending or self.db.preparationRequest or InCombatLockdown() or
        settingsOpen() or SH.worldLoading or (SH.worldSettleRemaining or 0) > 0 then return end
    local issue = self:CheckPreparedReferences()
    if issue and (issue.category == "timing-availability" or issue.category == "count-availability") then
        -- Existing observers can resume independently. A full rebuild still
        -- needs the original action available to bind its new timing observer.
        if self.recoveryNeedsRebuild then return false end
        issue = nil
    end
    if not issue and not self.recoveryNeedsRebuild then
        self.prepared, self.suspendedPrepared, self.stale = true, nil, nil
        self.recoveryPending, self.recoveryAttempts = nil, nil
        self.statusText, self.suspendedStatus = self.suspendedStatus or "Prepared.", nil
        self.button:SetAttribute("ready", true)
        self:UpdateButtonVisual()
        self:NotifyUI()
        return true
    end
    issue = issue or {reason = "Tracker setup is still being restored.", category = "reference"}
    if issue.category == "configuration" then
        self:RequirePreparation(issue.reason, "configuration:" .. issue.reason)
        return false
    end
    local canRecover, reason, manual = self:CanRecoverPrepared()
    if manual then self:RequirePreparation(reason, "configuration:" .. reason); return false end
    self.recoveryAttempts = (self.recoveryAttempts or 0) + 1
    if canRecover then
        local attempts = self.recoveryAttempts
        local ok, message = self:Prepare(self.db.preparedRules, {restore = true, recovery = true,
            preventClipping = self.db.preparedPreventClipping})
        if ok then return true end
        self.recoveryPending, self.recoveryAttempts, self.recoveryNeedsRebuild = true, attempts, true
        reason = message
    end
    if self.recoveryAttempts >= 15 then
        self:RequirePreparation("the required trackers could not be restored: " .. (reason or issue.reason), "recovery-failed")
    end
    return false
end

function SH:SetRotationEnabled(enabled)
    if self.index == 1 then return false, "The first rotation stays enabled." end
    if InCombatLockdown() then return false, "Leave combat before turning " .. self.label .. " on or off." end
    enabled = enabled == true
    if self.db.enabled == enabled then return true, self.label .. (enabled and " is enabled." or " is off.") end
    self:FinishButtonDrag()
    self.db.enabled = enabled
    self.restoreAttempts, self.stale = 0, nil
    self.recoveryPending, self.recoveryAttempts, self.recoveryNeedsRebuild, self.suspendedStatus = nil, nil, nil, nil
    if not enabled then
        self:DisablePrepared(self.label .. " is off. Its rules and cast key are saved.")
        if self.ReleaseDirectKey then self:ReleaseDirectKey()
        else
            if self.directBindingOwner then ClearOverrideBindings(self.directBindingOwner) end
            self.boundKey, self.boundDirectKeys = nil, nil
        end
        if self.ReleaseGamePadKey then self:ReleaseGamePadKey() end
        if self.button then self.button:Hide() end
        local macroFailed
        local index = GetMacroIndexByName(self.macroName)
        if index and index > 0 then
            local _, _, body = GetMacroInfo(index)
            if ownsMacro(self, body) and normalizeMacroBody(body) ~= DISABLED_MACRO_BODY then
                local ok, result = pcall(EditMacro, index, self.macroName, QUESTION_MARK, DISABLED_MACRO_BODY)
                if not ok or not result or result == 0 then macroFailed = true end
            end
        end
        if macroFailed then
            self.statusText = self.statusText .. " Could not disable the macro's queue-clearing line; avoid its action-bar key until it is updated."
        end
    else
        self:CreateCastButton():SetShown(self.db.showButton ~= false)
        self.statusText = self.label .. " enabled. Add spell rules, then click Prepare."
        if self.db.autoPrepare and self.db.preparedRules and not self.db.manualPrepareFailed and not self.db.preparationRequest then
            self:Prepare(self.db.preparedRules, {restore = true, preventClipping = self.db.preparedPreventClipping})
        end
        self:RestoreDirectKey()
        if self.RestoreGamePadKey then self:RestoreGamePadKey() end
    end
    self:NotifyUI()
    return true, self.statusText
end

function SH:GetActiveProfileIndex()
    return SH.rootDB and SH.rootDB.activeProfile or 1
end

function SH:GetProfileNames()
    local names = {}
    for index = 1, SH.Profiles.COUNT do names[index] = SH.rootDB.profiles[index].name end
    return names
end

function SH:RenameProfile(index, name)
    if InCombatLockdown() then return false, "Leave combat before renaming a profile." end
    local ok, reason = SH.Profiles.Rename(SH.rootDB, index, name)
    if ok then SH:NotifyUI() end
    return ok, reason
end

function SH:SwitchProfile(index)
    if InCombatLockdown() then return false, "Leave combat before switching profiles." end
    if not SH.Profiles.ValidIndex(index) then return false, "Choose a profile from 1 to 5." end
    if index == SH:GetActiveProfileIndex() then return true, "This profile is already selected." end
    local root = SH.rootDB
    -- Finish dragging and capture all four rotations before releasing live state.
    for _, rotation in ipairs(SH.rotations) do rotation:FinishButtonDrag() end
    SH.Profiles.Save(root)
    SH.switchingProfile = true
    for _, rotation in ipairs(SH.rotations) do
        if rotation.ReleaseDirectKey then rotation:ReleaseDirectKey() end
        if rotation.ReleaseGamePadKey then rotation:ReleaseGamePadKey() end
        rotation:DisablePrepared("Switching profiles.")
        local macro = GetMacroIndexByName(rotation.macroName)
        if macro and macro > 0 then
            local _, _, body = GetMacroInfo(macro)
            if ownsMacro(rotation, body) then
                local idleBody = rotation.index == 1 and macroBodies(rotation) or DISABLED_MACRO_BODY
                pcall(EditMacro, macro, rotation.macroName, QUESTION_MARK, idleBody)
            end
        end
    end
    SH.Profiles.Apply(root, index)
    local dbKeys = {"secondRotation", "thirdRotation", "fourthRotation"}
    for number, rotation in ipairs(SH.rotations) do
        rotation.db = number == 1 and root or root[dbKeys[number - 1]]
        rotation.activeRules = nil
        rotation.signals, rotation.orSignals, rotation.extraSignals = {}, {}, {}
        rotation.cooldownSignals, rotation.conditionCooldownSignals = {}, {}
        rotation.restoreAttempts, rotation.stale = 0, nil
        rotation.recoveryPending, rotation.recoveryAttempts, rotation.recoveryNeedsRebuild, rotation.suspendedStatus = nil, nil, nil, nil
        rotation.statusText = rotation:IsEnabled() and "Not prepared. Add spell rules, then click Prepare." or rotation.label .. " is off. Enable it to use this rotation."
        rotation:UpdateDraftState()
        local button = rotation:CreateCastButton()
        local point = rotation.db.point
        button:ClearAllPoints()
        button:SetPoint(point.point, UIParent, point.relativePoint or point.point, point.x or 0, point.y or 0)
        button:SetShown(rotation:IsEnabled() and rotation.db.showButton ~= false)
        rotation:UpdateButtonVisual()
    end
    local stateReady = SH:CheckPreparationState()
    for _, rotation in ipairs(SH.rotations) do
        if rotation:IsEnabled() then
            if stateReady and rotation.db.autoPrepare and rotation.db.preparedRules and
                not rotation.db.manualPrepareFailed and not rotation.db.preparationRequest then
                rotation:Prepare(rotation.db.preparedRules, {restore = true, preventClipping = rotation.db.preparedPreventClipping})
            end
            rotation:RestoreDirectKey()
            if rotation.RestoreGamePadKey then rotation:RestoreGamePadKey() end
        end
    end
    SH.switchingProfile = nil
    if SH.RefreshProfileUI then SH:RefreshProfileUI() end
    SH:NotifyUI()
    return true, "Switched to " .. root.profiles[index].name .. "."
end

function SH:Initialize()
    if self.db then return end
    if type(StandAndHitDB) ~= "table" then StandAndHitDB = {} end
    for key, value in pairs(defaults) do
        if StandAndHitDB[key] == nil then StandAndHitDB[key] = M.Copy(value) end
    end
    self.db = StandAndHitDB
    SH.rootDB = StandAndHitDB
    self.db.version = 3
    self.db.binding = nil -- Retire the old binding field; directKey stores the current opt-in override.
    if type(self.db.rules) ~= "table" then self.db.rules = M.Copy(defaults.rules) end
    if type(self.db.point) ~= "table" or not self.db.point.point then self.db.point = M.Copy(defaults.point) end
    local angle = tonumber(self.db.minimapAngle)
    if not angle or angle ~= angle or angle == math.huge or angle == -math.huge then angle = 225 end
    self.db.minimapAngle = angle % 360
    self:UpdateDraftState()
    self.restoreAttempts = 0
    local rotationKeys = {"secondRotation", "thirdRotation", "fourthRotation"}
    self.rotations = {self}
    for index = 2, self.MAX_ROTATIONS do
        local dbKey = rotationKeys[index - 1]
        if type(self.db[dbKey]) ~= "table" then self.db[dbKey] = {} end
        local rotationDB = self.db[dbKey]
        local rotationDefaults = {
            enabled = false, rules = {}, preventClipping = true, autoPrepare = true, showButton = true, hideUIErrors = false, hideTooltip = false,
            point = {point = "BOTTOM", relativePoint = "BOTTOM", x = (index - 1) * 90, y = 160},
        }
        for key, value in pairs(rotationDefaults) do
            if rotationDB[key] == nil then rotationDB[key] = M.Copy(value) end
        end
        rotationDB.enabled = rotationDB.enabled == true
        if type(rotationDB.rules) ~= "table" then rotationDB.rules = {} end
        if type(rotationDB.point) ~= "table" or not rotationDB.point.point then rotationDB.point = M.Copy(rotationDefaults.point) end
        local rotation = {}
        -- Copy methods, not live state. Each button owns its references and proc memory.
        for key, value in pairs(self) do if type(value) == "function" then rotation[key] = value end end
        rotation.Model, rotation.SpellRanks, rotation.Explanation = self.Model, self.SpellRanks, self.Explanation
        local label = "Hit Button " .. index
        rotation.index, rotation.label, rotation.buttonName, rotation.macroName, rotation.directButtonName = index, label, "HitButton" .. index, label, "HitDirectButton" .. index
        rotation.db, rotation.guards, rotation.signals, rotation.orSignals, rotation.extraSignals, rotation.cooldownSignals = rotationDB, {}, {}, {}, {}, {}
        rotation.conditionCooldownSignals = {}
        rotation.restoreAttempts = 0
        rotation.statusText = rotationDB.enabled and "Not prepared. Add spell rules, then click Prepare." or label .. " is off. Enable it to use this rotation."
        self[dbKey], self.rotations[index] = rotation, rotation
        rotation:UpdateDraftState()
    end
    if SH.Profiles then SH.Profiles.Initialize(self.db) end
end

local events = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
    "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB"}) do
    -- Event availability differs between supported Classic/Forever clients.
    pcall(events.RegisterEvent, events, event)
end
local stateEvents = {SPELLS_CHANGED = true, PLAYER_TALENT_UPDATE = true, ACTIVE_TALENT_GROUP_CHANGED = true,
    PLAYER_SPECIALIZATION_CHANGED = true, TRAIT_CONFIG_UPDATED = true,
    LEARNED_SPELL_IN_SKILL_LINE = true, LEARNED_SPELL_IN_TAB = true}
local function requestEnabled(reason, cause, pendingStateKind, learnedSpellID)
    for _, rotation in ipairs(SH.rotations or {}) do
        local alreadyKnown = learnedSpellID and SH.PreparationStateKnowsSpell and
            SH.PreparationStateKnowsSpell(rotation.db.preparationState, learnedSpellID)
        if rotation:IsEnabled() and rotation.db.preparedRules and not alreadyKnown then
            rotation:RequirePreparation(reason, cause)
            if rotation.db.preparationRequest and pendingStateKind then
                rotation.db.preparationRequest.pendingStateKind = pendingStateKind
            end
        end
    end
end
events:SetScript("OnEvent", function(_, event, name, previous, guildPerk)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        recordBlockedAction(event, name, previous)
        return
    end
    if event == "ADDON_LOADED" and name ~= addonName then return end
    SH:Initialize()
    if stateEvents[event] then
        SH.stateCheckPending, SH.stateCheckRemaining = true, 0.5
        if not SH.loginPreparationPending and event == "ACTIVE_TALENT_GROUP_CHANGED" and type(name) == "number" and
            type(previous) == "number" and name >= 1 and previous >= 1 and name ~= previous then
            local state = SH.GetPreparationState and SH.GetPreparationState() or {}
            if not state.talents then requestEnabled("a talent specialization change", "talent-group:" .. name, "talents") end
        elseif not SH.loginPreparationPending and (event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB") and
            not guildPerk and type(name) == "number" then
            -- A precise learned-spell event remains useful on clients that
            -- cannot enumerate a complete spellbook for comparison.
            local state = SH.GetPreparationState and SH.GetPreparationState() or {}
            if not state.spells then requestEnabled("learning a new spell or spell rank", "learned-spell:" .. name, "spells", name) end
        end
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then
        SH.worldLoading, SH.preparationCandidate = true, nil
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        SH.worldLoading, SH.worldSettleRemaining = nil, 2
        SH.preparationHydrating, SH.preparationCandidate, SH.stateCheckAttempts = true, nil, nil
        SH.stateCheckPending, SH.stateCheckRemaining = true, 0.5
    elseif event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
        SH.preparationHydrating, SH.preparationCandidate, SH.loginPreparationPending = true, nil, true
        SH.stateCheckAttempts = nil
        SH.worldSettleRemaining = math.max(SH.worldSettleRemaining or 0, 2)
        SH.stateCheckPending, SH.stateCheckRemaining = true, 0.5
    end
    if not InCombatLockdown() then
        SH:CreateLauncher()
        for _, rotation in ipairs(SH.rotations) do
            rotation:FinishButtonDrag()
            rotation:CreateCastButton()
            if rotation:IsEnabled() then
                if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
                    rotation:RestoreDirectKey()
                    if rotation.RestoreGamePadKey then rotation:RestoreGamePadKey() end
                end
                if rotation.db.preparationRequest and rotation.prepared then
                    rotation:DisablePrepared("Preparation required: " .. rotation.db.preparationRequest.reason)
                elseif rotation.stale and rotation.recoveryPending then
                    rotation:SuspendPrepared("Waiting for the trackers to become available.")
                end
            end
        end
    end
    if event == "PLAYER_LOGIN" then say("Loaded. Click S&H by the minimap, or type /snh.") end
    if event == "PLAYER_ENTERING_WORLD" then
        for _, rotation in ipairs(SH.rotations) do if rotation:IsEnabled() then rotation:ValidatePrepared() end end
    end
    SH:NotifyUI()
end)
local elapsed, restoreElapsed = 0, 0
events:SetScript("OnUpdate", function(_, delta)
    if not SH.db then return end
    if SH.worldSettleRemaining then SH.worldSettleRemaining = math.max(0, SH.worldSettleRemaining - delta) end
    if SH.stateCheckRemaining then SH.stateCheckRemaining = math.max(0, SH.stateCheckRemaining - delta) end
    local settling = SH.worldLoading or (SH.worldSettleRemaining or 0) > 0
    if SH.stateCheckPending and not settling and (SH.stateCheckRemaining or 0) <= 0 then
        if SH:CheckPreparationState() then
            SH.stateCheckPending, SH.stateCheckAttempts = nil, nil
        else
            SH.stateCheckAttempts = (SH.stateCheckAttempts or 0) + 1
            -- Loading data is not evidence that the player changed a talent.
            -- Keep the pending comparison (with a slower retry after 15s) so
            -- a late native refresh can still restore the saved rotations.
            SH.stateCheckRemaining = SH.stateCheckAttempts >= 30 and 2 or 0.5
        end
    end
    elapsed, restoreElapsed = elapsed + delta, restoreElapsed + delta
    if elapsed >= 0.5 then
        elapsed = 0
        for _, rotation in ipairs(SH.rotations) do if rotation:IsEnabled() then rotation:ValidatePrepared() end end
    end
    if restoreElapsed >= 2 and not InCombatLockdown() and not settling and not SH.stateCheckPending and not settingsOpen() then
        restoreElapsed = 0
        for _, rotation in ipairs(SH.rotations) do
            if rotation:IsEnabled() and rotation.recoveryPending then
                rotation:RecoverPrepared()
            elseif rotation:IsEnabled() and not rotation.prepared and not rotation.stale and
                not rotation.db.preparationRequest and rotation.db.autoPrepare and rotation.db.preparedRules and
                not rotation.db.manualPrepareFailed and rotation.restoreAttempts < 15 then
                rotation.restoreAttempts = rotation.restoreAttempts + 1
                local ok, reason = rotation:Prepare(rotation.db.preparedRules, {restore = true,
                    preventClipping = rotation.db.preparedPreventClipping})
                if not ok and rotation.restoreAttempts == 15 then
                    rotation:RequirePreparation("the saved rotation could not be restored: " .. reason, "restore-failed")
                end
            end
        end
    end
end)

SLASH_STANDANDHIT1 = "/snh"
SLASH_STANDANDHIT2 = "/standandhit"
SlashCmdList.STANDANDHIT = function()
    SH:Initialize()
    SH:ShowConfig()
end

local _, SH = ...

function SH:CreateDirectButton()
    if self.directButton then return self.directButton end
    if InCombatLockdown() then return nil end
    local cast = self:CreateCastButton()
    if not cast then return nil end
    local button = CreateFrame("Button", self.directButtonName, UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type", "macro")
    button:SetAttribute("useOnKeyDown", false)
    button:SetFrameRef("cast", cast)
    SecureHandlerWrapScript(button, "OnClick", button, [[
        self:SetAttribute("macrotext",nil)
        local cast=self:GetFrameRef("cast")
        if not cast or not cast:GetAttribute("ready") then return false end
        if cast:GetAttribute("sh-suppress-click") or cast:GetAttribute("sh-dragging") then return false end
        -- Direct input previews the selection, then /click selects again. If
        -- this press never reaches /click, its empty macro still runs the post
        -- handler so the one-press skip is consumed exactly once.
        local abort=false
        if cast:GetAttribute("sh-watch-position") then
            cast:SetAttribute("sh-position-awaiting-click",true)
            abort=nil
        end
        -- Run selection first so a press during a channel confirms Once per proc.
        local autoAttack=cast:GetAttribute("sh-has-auto-attack")
        local custom=cast:GetAttribute("sh-has-custom-rule")
        if custom then
            cast:SetAttribute("sh-command-target-dirty",nil)
            cast:SetAttribute("sh-command-followup",true)
            for index=1,32 do cast:SetAttribute("sh-command-done"..index,nil) end
            cast:RunAttribute("sh-select-custom")
            local index=cast:GetAttribute("selected-row")
            local commands=cast:GetAttribute("macrotext")
            if index and cast:GetAttribute("sh-valid")==true and cast:GetAttribute("type")=="macro" and commands then
                cast:SetAttribute("sh-command-done"..index,true)
                if cast:GetAttribute("sh-command-executes")~=false then
                    cast:SetAttribute("sh-command-target-dirty",cast:GetAttribute("sh-command-target-change")==true)
                    self:SetAttribute("sh-last-row",nil)
                    self:SetAttribute("macrotext",cast:GetAttribute("sh-custom-prefix")..commands.."\n"..cast:GetAttribute("sh-custom-followup-body"))
                    return nil,true
                end
                -- Every command's native condition is false. Keep the normal
                -- stop-casting checks for this unchanged state and continue.
            end
        end
        cast:RunAttribute((autoAttack or custom) and "sh-select-cast" or "sh-select")
        if cast:GetAttribute("sh-count-wait") then
            self:SetAttribute("macrotext",autoAttack and cast:GetAttribute("sh-direct-cast") or "/cancelqueuedspell")
            return nil,true
        end
        local body=cast:GetAttribute("sh-direct-cast")
        if not body then return abort,true end
        if SecureCmdOptionParse("[channeling]1") then
            self:SetAttribute("macrotext",body)
            return nil,true
        end
        if not cast:GetAttribute("sh-valid") then
            if cast:GetAttribute("sh-has-counts") or cast:GetAttribute("sh-has-combo") or cast:GetAttribute("sh-has-resources") or cast:GetAttribute("sh-has-health") or cast:GetAttribute("sh-has-stacks") or cast:GetAttribute("sh-has-aura-time") or cast:GetAttribute("sh-has-logic") or cast:GetAttribute("sh-has-ping") or cast:GetAttribute("sh-has-target-casting") or cast:GetAttribute("sh-has-fire-totems") or cast:GetAttribute("sh-has-hawks") or cast:GetAttribute("sh-has-riposte") or cast:GetAttribute("sh-has-position-skip") or cast:GetAttribute("sh-has-immunity-skip") or cast:GetAttribute("sh-has-range") or cast:GetAttribute("sh-has-out-of-combat") or cast:GetAttribute("sh-has-in-combat") or cast:GetAttribute("sh-has-modifiers") or cast:GetAttribute("sh-has-condition-cooldowns") then
                self:SetAttribute("macrotext","/cancelqueuedspell")
                return nil,true
            end
            return abort,true
        end
        local index=cast:GetAttribute("selected-row")
        if cast:GetAttribute("sh-wand-hold") then
            -- Keep the final button read fresh without interrupting the wand
            -- merely because this rule also has a stop-casting option.
            self:SetAttribute("sh-last-row",index)
            self:SetAttribute("macrotext",body)
            return nil,true
        end
        local last=self:GetAttribute("sh-last-row")
        local shouldStop
        -- This is the last requested Stand and Hit rule, not a claim about manual casts.
        if last and cast:GetAttribute("sh-stop-invalid"..last) and
            cast:GetAttribute("sh-aura-match"..last)==false then shouldStop=true end
        local primaryEpoch,orEpoch
        if index then
            if cast:GetAttribute("sh-stop"..index) and cast:GetAttribute("selected-primary") then
                local guard=cast:GetFrameRef("proc"..index)
                if not guard then return abort,true end
                primaryEpoch=guard:GetAttribute("sh-proc-epoch")
                if primaryEpoch==nil then return abort,true end
                if cast:GetAttribute("sh-stopped"..index)~=primaryEpoch then shouldStop=true end
            end
            if cast:GetAttribute("sh-or-stop"..index) and cast:GetAttribute("selected-legacy-or") then
                local guard=cast:GetFrameRef("orProc"..index)
                if not guard then return abort,true end
                orEpoch=guard:GetAttribute("sh-proc-epoch")
                if orEpoch==nil then return abort,true end
                if cast:GetAttribute("sh-or-stopped"..index)~=orEpoch then shouldStop=true end
            end
        end
        if shouldStop then
            if primaryEpoch~=nil then cast:SetAttribute("sh-stopped"..index,primaryEpoch) end
            if orEpoch~=nil then cast:SetAttribute("sh-or-stopped"..index,orEpoch) end
            body="/cancelqueuedspell\n/stopcasting [nochanneling]\n"..body
        end
        self:SetAttribute("sh-last-row",index)
        if not index and not shouldStop and not autoAttack then
            if cast:GetAttribute("sh-has-counts") or cast:GetAttribute("sh-has-combo") or cast:GetAttribute("sh-has-resources") or cast:GetAttribute("sh-has-health") or cast:GetAttribute("sh-has-stacks") or cast:GetAttribute("sh-has-aura-time") or cast:GetAttribute("sh-has-logic") or cast:GetAttribute("sh-has-ping") or cast:GetAttribute("sh-has-target-casting") or cast:GetAttribute("sh-has-fire-totems") or cast:GetAttribute("sh-has-hawks") or cast:GetAttribute("sh-has-riposte") or cast:GetAttribute("sh-has-position-skip") or cast:GetAttribute("sh-has-immunity-skip") or cast:GetAttribute("sh-has-range") or cast:GetAttribute("sh-has-out-of-combat") or cast:GetAttribute("sh-has-in-combat") or cast:GetAttribute("sh-has-modifiers") or cast:GetAttribute("sh-has-condition-cooldowns") then
                self:SetAttribute("macrotext","/cancelqueuedspell")
                return nil,true
            end
            return abort,true
        end
        self:SetAttribute("macrotext",body)
        return nil,true
    ]], [[
        self:SetAttribute("macrotext",nil)
        local cast=self:GetFrameRef("cast")
        if cast then
            if cast:GetAttribute("sh-has-custom-rule") then
                local selected=cast:GetAttribute("selected-row")
                if selected then self:SetAttribute("sh-last-row",selected) end
                cast:SetAttribute("sh-command-followup",nil)
                cast:SetAttribute("sh-auto-followup",nil)
                cast:SetAttribute("sh-command-target-dirty",nil)
                cast:SetAttribute("sh-command-target-change",nil)
                cast:SetAttribute("sh-command-executes",nil)
                for index=1,32 do cast:SetAttribute("sh-command-done"..index,nil) end
            end
            if cast:GetAttribute("sh-position-awaiting-click") then
                cast:SetAttribute("sh-position-awaiting-click",nil)
                cast:CallMethod("ConsumePositionSkip")
            end
            cast:SetAttribute("type","spell")
            cast:SetAttribute("macrotext",nil)
        end
    ]])
    self.directButton = button
    return button
end

local modifierOrder = {"ALT", "CTRL", "SHIFT"}
local modifierNames = {ALT = true, CTRL = true, SHIFT = true}
local forbiddenBaseKeys = {ESCAPE = true, SHIFT = true, CTRL = true, ALT = true,
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    BUTTON1 = true, BUTTON2 = true}

local function canonicalKey(value)
    if type(value) ~= "string" then return nil end
    local key = value:match("^%s*(.-)%s*$"):upper()
    if key == "" or #key > 80 or key:find("[%c%s]") then return nil end
    local modifiers, base = {}, key
    while true do
        local prefix, tail = base:match("^([A-Z]+)%-(.*)$")
        if not modifierNames[prefix] then break end
        if modifiers[prefix] or tail == "" then return nil end
        modifiers[prefix], base = true, tail
    end
    if forbiddenBaseKeys[base] then return nil end
    local prefix = ""
    for _, name in ipairs(modifierOrder) do if modifiers[name] then prefix = prefix .. name .. "-" end end
    return prefix .. base, base, modifiers
end

function SH:CanonicalDirectKey(key)
    return canonicalKey(key)
end

function SH:DirectKeysEqual(first, second)
    local normalized = canonicalKey(first)
    return normalized ~= nil and normalized == canonicalKey(second)
end

local function appliedRules(rotation)
    return rotation.prepared == true and rotation.activeRules or {}
end

local function bindingKeys(key, rules)
    local normalized, base, held = canonicalKey(key)
    if not normalized then return nil end
    local wanted = {}
    for _, row in ipairs(type(rules) == "table" and rules or {}) do
        if type(row) == "table" and row.enabled ~= false then
            for _, field in ipairs({"skipModifier", "priorityModifier"}) do
                local value = row[field]
                if type(value) == "string" and modifierNames[value:upper()] then wanted[value:upper()] = true end
            end
        end
    end
    local keys, seen = {normalized}, {[normalized] = true}
    -- Add only combinations of the modifiers used by the applied rotation.
    -- Modifiers already present in its base key remain held in every alias.
    for mask = 1, 7 do
        local prefix, valid = "", true
        for index, name in ipairs(modifierOrder) do
            local selected = math.floor(mask / (2 ^ (index - 1))) % 2 == 1
            if selected and not wanted[name] then valid = false; break end
            if held[name] or selected then prefix = prefix .. name .. "-" end
        end
        local alias = prefix .. base
        if valid and not seen[alias] then keys[#keys + 1], seen[alias] = alias, true end
    end
    return keys, seen
end

local function publicBinding(key, overrides)
    local ok, value = pcall(GetBindingAction, key, overrides)
    if not ok or (issecretvalue and issecretvalue(value)) or type(value) ~= "string" then return nil end
    return value
end

local function checkBindings(rotation, keys)
    for index, key in ipairs(keys) do
        for _, other in ipairs(SH.rotations or {SH}) do
            if other:IsEnabled() then
                if rotation:DirectKeysEqual(key, other.boundGamePadKey) or rotation:DirectKeysEqual(key, other.db.gamePadKey) then
                    return false, key .. " is already assigned as a controller button for " .. other.label .. ". Choose a different key."
                end
                if other ~= rotation and ((other.boundDirectKeys and other.boundDirectKeys[key]) or
                    rotation:DirectKeysEqual(key, other.boundKey)) then
                    return false, key .. " is already assigned to " .. other.label .. ". Choose a different key."
                end
            end
        end
        -- The selected base key has always been an explicit temporary override.
        -- Generated chords may override saved WoW bindings, but must not compete
        -- with another addon's live override.
        if index > 1 and type(GetBindingAction) == "function" then
            local ordinary, active = publicBinding(key, false), publicBinding(key, true)
            if ordinary == nil or active == nil then return false, key .. " could not be checked. Try again outside combat." end
            local own = ((rotation.boundDirectKeys and rotation.boundDirectKeys[key]) or rotation:DirectKeysEqual(key, rotation.boundKey))
                and active == "CLICK " .. rotation.directButtonName .. ":LeftButton"
            if active ~= ordinary and not own then
                return false, key .. " is controlled by another binding override. Clear that assignment or choose a different cast key."
            end
        end
    end
    return true
end

local function installBindings(rotation, key, rules)
    local keys, keySet = bindingKeys(key, rules)
    if not keys then return false, "Choose a keyboard key, with optional Ctrl, Alt, or Shift." end
    local permitted, reason = checkBindings(rotation, keys)
    if not permitted then return false, reason end
    if not rotation:CreateDirectButton() then return false, "The casting button is not available." end
    -- Keep the previous complete set underneath the staging owner until every
    -- new chord succeeds. Reuse the same two owners for later changes.
    local candidate = rotation.directBindingStagingOwner or CreateFrame("Frame")
    rotation.directBindingStagingOwner = candidate
    local cleared = pcall(ClearOverrideBindings, candidate)
    if not cleared then return false, "The previous key assignment could not be cleared. Try again outside combat." end
    for _, value in ipairs(keys) do
        local ok, result = pcall(SetOverrideBindingClick, candidate, true, value, rotation.directButtonName, "LeftButton")
        if not ok or result == false then
            if not pcall(ClearOverrideBindings, candidate) then
                return false, "The incomplete key assignment could not be cleared. Reload the UI before using this cast key."
            end
            return false, value .. " could not be bound. Your previous key assignment is unchanged."
        end
    end
    local previous = rotation.directBindingOwner
    if previous and not pcall(ClearOverrideBindings, previous) then
        if not pcall(ClearOverrideBindings, candidate) then
            return false, "The incomplete key assignment could not be cleared. Reload the UI before using this cast key."
        end
        return false, "The previous key assignment could not be cleared. Try again outside combat."
    end
    rotation.directBindingOwner, rotation.directBindingStagingOwner = candidate, previous
    rotation.boundKey, rotation.boundDirectKeys = keys[1], keySet
    rotation.directBindingError = nil
    return true, keys
end

function SH:SetDirectKey(key)
    if InCombatLockdown() then return false, "Leave combat before changing the cast key." end
    if not self:IsEnabled() then return false, "Enable " .. self.label .. " first." end
    local ok, result = installBindings(self, key, appliedRules(self))
    if not ok then return false, result end
    self.db.directKey = self.boundKey
    if self.UpdatePreparedAccessHint then self:UpdatePreparedAccessHint() end
    self:NotifyUI()
    local aliases = #result > 1 and (" Includes " .. table.concat(result, ", ", 2) .. ".") or ""
    return true, "Cast key: " .. self.boundKey .. "." .. aliases .. " Use fresh presses for " .. self.label .. ", including interrupts. Clear key restores its normal bindings."
end

function SH:RefreshDirectKeyBindings(rules)
    if InCombatLockdown() then return false, "Leave combat before updating cast key modifiers." end
    if not self:IsEnabled() then return self:ReleaseDirectKey() end
    if not self.db.directKey then return true end
    local ok, result = installBindings(self, self.db.directKey, rules == nil and appliedRules(self) or rules)
    if not ok then self.directBindingError = result; return false, result end
    self.db.directKey = self.boundKey
    return true
end

function SH:ReleaseDirectKey()
    if InCombatLockdown() then return false, "Leave combat before changing the cast key." end
    if self.directBindingOwner then ClearOverrideBindings(self.directBindingOwner) end
    if self.directBindingStagingOwner then ClearOverrideBindings(self.directBindingStagingOwner) end
    self.boundKey, self.boundDirectKeys, self.directBindingError = nil, nil, nil
    return true
end

function SH:ClearDirectKey()
    local ok, reason = self:ReleaseDirectKey()
    if not ok then return false, reason end
    self.db.directKey = nil
    if self.UpdatePreparedAccessHint then self:UpdatePreparedAccessHint() end
    self:NotifyUI()
    return true, "Cast key cleared. Its normal bindings are available again."
end

function SH:RestoreDirectKey()
    if self:IsEnabled() and self.db.directKey and not InCombatLockdown() then
        local ok, message = self:SetDirectKey(self.db.directKey)
        if not ok then self.directBindingError = message; self.statusText = message end
    end
end

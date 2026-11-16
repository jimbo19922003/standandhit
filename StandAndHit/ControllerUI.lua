local _, SH = ...
local WIDTH, HEIGHT = 680, 620
local Refresh, EndCapture

local function Label(parent, text, font, color)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    label:SetText(text)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    if color then label:SetTextColor(unpack(color)) end
    return label
end

local function Button(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26)
    button:SetText(text)
    return button
end

local function Skin(frame, background)
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    frame:SetBackdropColor(unpack(background))
    frame:SetBackdropBorderColor(0.23, 0.33, 0.4, 1)
end

local function Status(dialog, ok, message)
    dialog.message, dialog.messageOK = message or "", ok ~= false
    dialog.status:SetText(dialog.message)
    dialog.status:SetTextColor(ok == false and 1 or 0.5, ok == false and 0.57 or 0.85, ok == false and 0.57 or 0.67)
end

local function Call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false, "Controller support is unavailable on this client." end
    local called, ok, message = pcall(object[method], object, ...)
    if not called then return false, "The controller setting could not be changed. Try again outside combat." end
    return ok, message
end

local function Settings()
    local controller = SH.Controller
    if controller and type(controller.GetSettings) == "function" then
        local ok, settings = pcall(controller.GetSettings, controller)
        if ok and type(settings) == "table" then return settings end
    end
    return {combatRumble = false, critRumble = false}
end

local function Rotation(index)
    return SH.GetRotation and SH:GetRotation(index) or (index == 1 and SH)
end

local function Enabled(rotation)
    return rotation and (not rotation.IsEnabled or rotation:IsEnabled())
end

local function KeyLabel(key)
    if not key then return "Not assigned" end
    local controller = SH.Controller
    if controller and type(controller.GetButtonLabel) == "function" then
        local ok, label = pcall(controller.GetButtonLabel, controller, key)
        if ok and type(label) == "string" and label ~= "" then return label end
    end
    return tostring(key)
end

local function CleanupInput(dialog)
    local capture = dialog.capture
    capture:Hide()
    capture:SetScript("OnGamePadButtonDown", nil)
    capture:SetScript("OnGamePadButtonUp", nil)
    capture:SetScript("OnKeyDown", nil)
    if InCombatLockdown() then
        -- Hidden unprotected frames receive no input. Defer protected API
        -- calls until combat ends rather than trying to change input flags.
        dialog.inputCleanupPending = true
        return
    end
    local gamepad = type(capture.EnableGamePadButton) ~= "function" or pcall(capture.EnableGamePadButton, capture, false)
    local keyboard = pcall(capture.EnableKeyboard, capture, false)
    local propagation = pcall(capture.SetPropagateKeyboardInput, capture, true)
    dialog.inputCleanupPending = not (gamepad and keyboard and propagation) or nil
end

EndCapture = function(dialog)
    dialog.captureToken = (dialog.captureToken or 0) + 1
    dialog.capturing, dialog.pendingKey, dialog.pendingAssignmentKey, dialog.pendingAssignment = nil, nil, nil, nil
    CleanupInput(dialog)
end

local function CancelCapture(dialog)
    EndCapture(dialog)
    Status(dialog, true, "Assignment canceled. Your existing buttons are unchanged.")
    Refresh(dialog)
end

local function CaptureDown(dialog, key)
    if not dialog.capturing or InCombatLockdown() or dialog.pendingKey then return end
    if type(key) ~= "string" or not key:match("^PAD[A-Z0-9]+$") then
        Status(dialog, false, "Press a controller button. Keyboard keys are assigned in the main window.")
        return
    end
    local getter = C_CVar and C_CVar.GetCVar or GetCVar
    if type(getter) == "function" then
        for _, name in ipairs({"GamePadEmulateAlt", "GamePadEmulateCtrl", "GamePadEmulateShift"}) do
            local ok, value = pcall(getter, name)
            if ok and not (issecretvalue and issecretvalue(value)) and type(value) == "string" and value:upper() == key then
                Status(dialog, true, "Hold this modifier and press another controller button to assign a combination.")
                return
            end
        end
    end
    dialog.pendingKey = key
    dialog.pendingAssignmentKey = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") ..
        (IsShiftKeyDown() and "SHIFT-" or "") .. key
    dialog.capturePrompt:SetText("Release " .. KeyLabel(dialog.pendingAssignmentKey) .. " to assign it. Escape cancels.")
end

local function CaptureUp(dialog, key)
    if not dialog.capturing or key ~= dialog.pendingKey then return end
    local rotation = dialog.capturing
    local token = dialog.captureToken
    local assignmentKey = dialog.pendingAssignmentKey
    dialog.capturing, dialog.pendingKey, dialog.pendingAssignmentKey = nil, nil, nil
    dialog.pendingAssignment = true
    CleanupInput(dialog)
    Refresh(dialog)
    -- The entire press/release is consumed before installing its new binding.
    C_Timer.After(0, function()
        if token ~= dialog.captureToken or not dialog.pendingAssignment then return end
        if InCombatLockdown() or not dialog:IsShown() or not Enabled(rotation) then
            EndCapture(dialog)
            Refresh(dialog)
            return
        end
        dialog.pendingAssignment = nil
        local ok, message = Call(rotation, "SetGamePadKey", assignmentKey)
        Status(dialog, ok, message or (ok and (KeyLabel(assignmentKey) .. " assigned to " .. rotation.label .. ".") or "That controller button could not be assigned."))
        Refresh(dialog)
    end)
end

local function StartCapture(dialog, rotation)
    if InCombatLockdown() then Status(dialog, false, "Leave combat to assign a controller button."); return end
    if not Enabled(rotation) then Status(dialog, false, "Enable this Hit Button in its setup tab before assigning a controller button."); return end
    local available, message = Call(SH.Controller, "IsAvailable")
    if not available then Status(dialog, false, message); Refresh(dialog); return end
    EndCapture(dialog)
    local capture = dialog.capture
    if dialog.inputCleanupPending or type(capture.EnableGamePadButton) ~= "function" or not C_Timer or type(C_Timer.After) ~= "function" then
        Status(dialog, false, "This client cannot capture controller buttons safely.")
        return
    end
    dialog.capturing = rotation
    capture:SetScript("OnGamePadButtonDown", function(_, key) CaptureDown(dialog, key); return false end)
    capture:SetScript("OnGamePadButtonUp", function(_, key) CaptureUp(dialog, key); return false end)
    capture:SetScript("OnKeyDown", function(_, key) if key == "ESCAPE" then CancelCapture(dialog) end end)
    local propagation = pcall(capture.SetPropagateKeyboardInput, capture, false)
    local keyboard = propagation and pcall(capture.EnableKeyboard, capture, true)
    local gamepad = keyboard and pcall(capture.EnableGamePadButton, capture, true)
    if not gamepad then
        EndCapture(dialog)
        Status(dialog, false, "Controller input capture is unavailable. Existing assignments were kept.")
    else
        capture:Show()
        Status(dialog, true, "Press and release one controller button. No spell is cast while assigning.")
    end
    Refresh(dialog)
end

local function CheckBox(dialog, text, y, changed)
    local check = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", 22, y)
    check.label = Label(dialog, text, "GameFontHighlight")
    check.label:SetPoint("LEFT", check, "RIGHT", 3, 0)
    check:SetScript("OnClick", function(self)
        if InCombatLockdown() or dialog.capturing or dialog.pendingAssignment then Refresh(dialog); return end
        local ok, message = changed(self:GetChecked() == true)
        Status(dialog, ok, message)
        Refresh(dialog)
    end)
    return check
end

Refresh = function(dialog)
    local settings = Settings()
    local enabled = Call(SH.Controller, "IsEnabled") == true
    local available, availability = Call(SH.Controller, "IsAvailable")
    local busy = dialog.capturing ~= nil or dialog.pendingAssignment == true
    local editable = not InCombatLockdown() and not busy
    dialog.enable:SetChecked(enabled)
    dialog.enable:SetEnabled(editable and SH.Controller ~= nil)
    dialog.availability:SetText(availability or (available and "Controller ready." or "Enable and connect a controller to assign buttons."))
    dialog.availability:SetTextColor(available and 0.5 or 1, available and 0.85 or 0.75, available and 0.67 or 0.4)
    for index, row in ipairs(dialog.rows) do
        local rotation = Rotation(index)
        local active = Enabled(rotation)
        row.name:SetText(rotation and rotation.label or (index == 1 and "Hit Button" or "Hit Button " .. index))
        row.bindingError = active and rotation.controllerBindingError or nil
        row.state:SetText(not active and "Off: enable it in its setup tab" or (row.bindingError and "Not active: hover for details" or "Enabled"))
        row.state:SetTextColor(row.bindingError and 1 or (active and 0.5 or 0.7), row.bindingError and 0.57 or (active and 0.85 or 0.73), row.bindingError and 0.57 or (active and 0.67 or 0.78))
        row.binding:SetText(KeyLabel(rotation and rotation.db.gamePadKey))
        row.assign:SetEnabled(editable and active and available == true)
        row.clear:SetEnabled(editable and rotation ~= nil and rotation.db.gamePadKey ~= nil)
    end
    dialog.cancel:SetShown(busy)
    dialog.capturePrompt:SetText(dialog.pendingAssignment and "Finishing assignment..."
        or (dialog.capturing and (dialog.pendingKey and ("Release " .. KeyLabel(dialog.pendingAssignmentKey) .. ". Escape cancels.")
            or ("Press a controller button for " .. dialog.capturing.label .. ". Escape cancels."))
            or "Choose Assign, then press and release a controller button. Alt, Ctrl, and Shift combinations are supported."))
    dialog.combat:SetChecked(settings.combatRumble == true)
    dialog.crit:SetChecked(settings.critRumble == true)
    dialog.combat:SetEnabled(editable)
    dialog.crit:SetEnabled(editable)
    dialog.testRumble:SetEnabled(editable and available == true)
    local critStatus
    if SH.Controller and type(SH.Controller.GetCritStatus) == "function" then
        local ok, message = pcall(SH.Controller.GetCritStatus, SH.Controller)
        if ok and type(message) == "string" and message ~= "" then critStatus = message end
    end
    dialog.critHelp:SetText(critStatus or "Rumble when your damage critically hits.")
end

local function Fit(dialog)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    dialog:SetScale(math.min(1, math.max(0.5, (width - 40) / WIDTH), math.max(0.5, (height - 50) / HEIGHT)))
end

local function CreateDialog()
    local dialog = CreateFrame("Frame", "StandAndHitController", UIParent, "BackdropTemplate")
    SH.controllerUI = dialog
    dialog:SetSize(WIDTH, HEIGHT)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) if not self.capturing then self:StartMoving() end end)
    dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    Skin(dialog, {0.035, 0.05, 0.07, 0.99})
    if UISpecialFrames then table.insert(UISpecialFrames, "StandAndHitController") end
    dialog.title = Label(dialog, "Controller", "GameFontNormalHuge", {0.36, 0.78, 0.88})
    dialog.title:SetPoint("TOPLEFT", 22, -18)
    dialog.subtitle = Label(dialog, "Assign a controller button to each Hit Button.\nChanges take effect immediately outside combat.", "GameFontHighlight")
    dialog.subtitle:SetPoint("TOPLEFT", 23, -53)
    dialog.subtitle:SetWidth(WIDTH - 46)
    dialog.close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    dialog.close:SetPoint("TOPRIGHT", -5, -5)
    dialog.close:SetScript("OnClick", function() dialog:Hide() end)

    dialog.capture = CreateFrame("Frame", nil, dialog)
    dialog.capture:SetAllPoints(dialog)
    dialog.capture:SetFrameLevel(dialog:GetFrameLevel() + 20)
    dialog.capture:Hide()
    dialog.enable = CheckBox(dialog, "Enable controller", -92, function(value) return Call(SH.Controller, "SetEnabled", value) end)
    dialog.availability = Label(dialog, "", "GameFontHighlightSmall")
    dialog.availability:SetPoint("TOPLEFT", 230, -98)
    dialog.availability:SetSize(426, 34)
    local heading = Label(dialog, "Hit Button assignments", "GameFontNormal", {0.36, 0.78, 0.88})
    heading:SetPoint("TOPLEFT", 23, -143)
    dialog.rows = {}
    for index = 1, 4 do
        local row = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 22, -166 - (index - 1) * 54)
        row:SetSize(WIDTH - 44, 46)
        Skin(row, {0.02, 0.03, 0.04, 1})
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.bindingError then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Controller assignment is not active")
            GameTooltip:AddLine(self.bindingError, 1, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.name = Label(row, "", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", 12, -6)
        row.state = Label(row, "", "GameFontHighlightSmall")
        row.state:SetPoint("TOPLEFT", 12, -25)
        row.state:SetWidth(212)
        row.binding = Label(row, "", "GameFontHighlight")
        row.binding:SetPoint("LEFT", 230, 0)
        row.binding:SetWidth(208)
        row.assign = Button(row, "Assign", 82)
        row.assign:SetPoint("RIGHT", -92, 0)
        row.assign:SetScript("OnClick", function() StartCapture(dialog, Rotation(index)) end)
        row.clear = Button(row, "Clear", 70)
        row.clear:SetPoint("RIGHT", -12, 0)
        row.clear:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            EndCapture(dialog)
            local ok, message = Call(Rotation(index), "ClearGamePadKey")
            Status(dialog, ok, message)
            Refresh(dialog)
        end)
        dialog.rows[index] = row
    end
    dialog.capturePrompt = Label(dialog, "", "GameFontHighlightSmall", {0.69, 0.75, 0.8})
    dialog.capturePrompt:SetPoint("TOPLEFT", 23, -386)
    dialog.capturePrompt:SetSize(500, 34)
    dialog.cancel = Button(dialog, "Cancel", 112)
    dialog.cancel:SetPoint("TOPRIGHT", -22, -386)
    dialog.cancel:SetScript("OnClick", function() CancelCapture(dialog) end)
    local rumbleHeading = Label(dialog, "Rumble", "GameFontNormal", {0.36, 0.78, 0.88})
    rumbleHeading:SetPoint("TOPLEFT", 23, -430)
    dialog.combat = CheckBox(dialog, "Rumble when combat starts", -452, function(value) return Call(SH.Controller, "SetRumbleOption", "combatRumble", value) end)
    dialog.crit = CheckBox(dialog, "Rumble on crit", -484, function(value) return Call(SH.Controller, "SetRumbleOption", "critRumble", value) end)
    dialog.testRumble = Button(dialog, "Test rumble", 112)
    dialog.testRumble:SetPoint("TOPRIGHT", -22, -452)
    dialog.testRumble:SetScript("OnClick", function()
        if InCombatLockdown() or dialog.capturing or dialog.pendingAssignment then return end
        local ok, message = Call(SH.Controller, "TestRumble")
        Status(dialog, ok, message)
    end)
    dialog.critHelp = Label(dialog, "", "GameFontHighlightSmall", {0.69, 0.75, 0.8})
    dialog.critHelp:SetPoint("TOPLEFT", 23, -522)
    dialog.critHelp:SetSize(WIDTH - 46, 34)
    dialog.status = Label(dialog, "", "GameFontHighlightSmall")
    dialog.status:SetPoint("TOPLEFT", 23, -569)
    dialog.status:SetSize(WIDTH - 46, 34)
    dialog:SetScript("OnHide", function(self)
        EndCapture(self)
        self:StopMovingOrSizing()
    end)
    for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CVAR_UPDATE", "GAME_PAD_ACTIVE_CHANGED", "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED"}) do
        pcall(dialog.RegisterEvent, dialog, event)
    end
    dialog:SetScript("OnEvent", function(self, event, name)
        if event == "PLAYER_REGEN_DISABLED" then self:Hide(); return end
        if event == "PLAYER_REGEN_ENABLED" and self.inputCleanupPending then CleanupInput(self) end
        if not self:IsShown() then return end
        if event == "CVAR_UPDATE" and type(name) == "string" and name:lower() ~= "gamepadenable" then return end
        if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then Fit(self) end
        if (self.capturing or self.pendingAssignment) and Call(SH.Controller, "IsAvailable") ~= true then EndCapture(self) end
        Refresh(self)
    end)
    CleanupInput(dialog)
    dialog:Hide()
    return dialog
end

function SH:RefreshControllerUI()
    local dialog = SH.controllerUI
    if not dialog or not dialog:IsShown() then return end
    if InCombatLockdown() then dialog:Hide(); return end
    if (dialog.capturing and not Enabled(dialog.capturing)) or
        ((dialog.capturing or dialog.pendingAssignment) and Call(SH.Controller, "IsAvailable") ~= true) then EndCapture(dialog) end
    Refresh(dialog)
end

function SH:ShowControllerUI()
    if InCombatLockdown() then return false, "Leave combat to open Controller settings." end
    local dialog = SH.controllerUI or CreateDialog()
    EndCapture(dialog)
    Fit(dialog)
    dialog:Show()
    dialog:Raise()
    Refresh(dialog)
    return true
end

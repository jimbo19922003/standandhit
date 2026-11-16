local _, SH = ...

local WIDTH, HEIGHT = 760, 560
local TEXT_WIDTH = WIDTH - 88

local function Fit(dialog)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if width and height and width > 24 and height > 24 then
        dialog:SetScale(math.min(1, (width - 24) / WIDTH, (height - 24) / HEIGHT))
    end
end

local function BringToFront(dialog)
    local configLevel = SH.ui and SH.ui:GetFrameLevel() or 0
    dialog:SetFrameLevel(math.max(dialog:GetFrameLevel(), configLevel + 20))
    dialog:Raise()
end

local function SetStatus(dialog, message, failed)
    dialog.status:SetText(message or "")
    if failed then dialog.status:SetTextColor(1, 0.45, 0.35)
    else dialog.status:SetTextColor(0.85, 0.91, 0.94) end
end

local function SelectExport(dialog)
    local edit = dialog.edit
    edit:SetText(dialog.exportText or "")
    edit:SetCursorPosition(0)
    dialog.scroll:SetVerticalScroll(0)
    edit:SetFocus()
    edit:HighlightText()
end

local function CopyExport(dialog)
    local text = dialog.exportText
    if not text or text == "" then return end
    SelectExport(dialog)
    SetStatus(dialog, "Press Ctrl+C to copy the selected text.")
end

local function ImportDraft(dialog)
    if not dialog.onImport then return end
    local data, message = SH.Transfer.Decode(dialog.edit:GetText())
    if not data then
        SetStatus(dialog, message or "This rotation could not be imported.", true)
        return
    end
    -- The callback belongs to the destination chosen when this dialog opened.
    local ok, result = dialog.onImport(data)
    if not ok then
        SetStatus(dialog, result or "The draft could not be replaced. Open Import again.", true)
        return
    end
    dialog:Hide()
end

local function CreateDialog()
    local dialog = CreateFrame("Frame", "StandAndHitTransfer", UIParent, "BackdropTemplate")
    SH.transferUI = dialog
    dialog:SetSize(WIDTH, HEIGHT)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    dialog:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    dialog:SetBackdropColor(0.035, 0.05, 0.07, 0.99)
    dialog:SetBackdropBorderColor(0.23, 0.33, 0.4, 1)
    if UISpecialFrames then table.insert(UISpecialFrames, "StandAndHitTransfer") end

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetTextColor(0.36, 0.78, 0.88)
    dialog.title = title

    local subtitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", 23, -54)
    subtitle:SetWidth(WIDTH - 46)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetJustifyV("TOP")
    dialog.subtitle = subtitle

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() dialog:Hide() end)
    dialog.close = close

    local panel = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 22, -115)
    panel:SetPoint("BOTTOMRIGHT", -22, 94)
    panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    panel:SetBackdropColor(0.02, 0.03, 0.04, 1)
    panel:SetBackdropBorderColor(0.23, 0.33, 0.4, 1)
    dialog.panel = panel

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", -31, 10)
    dialog.scroll = scroll
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(SH.Transfer.MAX_TEXT)
    edit:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "")
    edit:SetSize(TEXT_WIDTH, 1)
    edit:SetTextInsets(0, 0, 0, 0)
    scroll:SetScrollChild(edit)
    dialog.edit = edit
    edit:SetScript("OnTextChanged", function(self, userInput)
        if dialog.mode == "export" and userInput then
            self:SetText(dialog.exportText or "")
        elseif dialog.mode == "import" then
            dialog.action:SetEnabled(dialog.onImport ~= nil and self:GetText():find("%S") ~= nil)
            if userInput then SetStatus(dialog, "") end
        end
        scroll:UpdateScrollChildRect()
    end)
    edit:SetScript("OnSizeChanged", function() scroll:UpdateScrollChildRect() end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local offset = math.max(0, -(y or 0))
        local current = scroll:GetVerticalScroll()
        if offset < current then
            scroll:SetVerticalScroll(offset)
        elseif offset + (height or 0) > current + scroll:GetHeight() then
            scroll:SetVerticalScroll(offset + (height or 0) - scroll:GetHeight())
        end
    end)
    edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
    edit:SetScript("OnHide", function(self) self:ClearFocus() end)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)

    local status = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 23, 58)
    status:SetWidth(WIDTH - 46)
    status:SetHeight(30)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    dialog.status = status

    local action = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    action:SetSize(238, 28)
    action:SetPoint("BOTTOMLEFT", 22, 19)
    action:SetScript("OnClick", function()
        if dialog.mode == "export" then CopyExport(dialog) else ImportDraft(dialog) end
    end)
    dialog.action = action

    local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancel:SetSize(100, 28)
    cancel:SetPoint("BOTTOMRIGHT", -22, 19)
    cancel:SetScript("OnClick", function() dialog:Hide() end)
    dialog.cancel = cancel

    dialog:SetScript("OnShow", function(self) Fit(self); BringToFront(self) end)
    dialog:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        self.edit:ClearFocus()
        self.onImport = nil
    end)
    dialog:RegisterEvent("DISPLAY_SIZE_CHANGED")
    dialog:RegisterEvent("UI_SCALE_CHANGED")
    dialog:SetScript("OnEvent", function(self) if self:IsShown() then Fit(self) end end)
    dialog:Hide()
    return dialog
end

function SH:ShowRotationTransfer(mode, rotation, rules, preventClipping, onImport)
    if mode ~= "import" and mode ~= "export" then return nil, "Choose Import or Export." end
    local dialog = SH.transferUI or CreateDialog()
    local label = rotation.label or ((rotation.index or 1) > 1 and ("Hit Button " .. rotation.index) or "Hit Button")
    dialog.edit:ClearFocus()
    dialog.mode = mode
    dialog.rotation = rotation
    dialog.onImport = mode == "import" and onImport or nil
    dialog.exportText = nil
    SetStatus(dialog, "")
    if mode == "export" then
        dialog.title:SetText("Export rotation: " .. label)
        dialog.subtitle:SetText("Share " .. label .. "'s current draft, including its Protect channels setting.\nCopy the complete text below, then paste it into Import on another rotation tab.")
        dialog.action:SetText("Copy to clipboard")
        dialog.cancel:SetText("Close")
        local text, message = SH.Transfer.Encode(rules, preventClipping)
        dialog.exportText = text
        dialog.edit:SetText(text or "")
        dialog.action:SetEnabled(text ~= nil)
        if not text then SetStatus(dialog, message or "This draft could not be exported.", true) end
    else
        dialog.title:SetText("Import rotation: " .. label)
        dialog.subtitle:SetText("Paste an export below. Import replaces only " .. label .. "'s draft and its Protect channels setting.\nSet up its trackers on this character, then click Prepare to use the rotation.")
        dialog.action:SetText("Replace " .. label .. " draft")
        dialog.cancel:SetText("Cancel")
        dialog.edit:SetText("")
        dialog.action:Disable()
    end
    dialog.edit:SetCursorPosition(0)
    dialog.scroll:SetVerticalScroll(0)
    dialog:Show()
    Fit(dialog)
    BringToFront(dialog)
    dialog.edit:SetFocus()
    if mode == "export" and dialog.exportText then dialog.edit:HighlightText() end
    return dialog
end

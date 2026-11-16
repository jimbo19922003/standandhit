local _, SH = ...

local WIDTH, CONTENT_WIDTH, MAX_BODY_HEIGHT = 500, 443, 184

local function SafeText(value)
    return (tostring(value or ""):gsub("|", "||"))
end

local function RequestText(requests)
    local firstReason = tostring(requests[1].reason or "changes to the saved rotation")
    local sameReason, labels, lines, signature = true, {}, {}, {}
    for _, request in ipairs(requests) do
        local label = tostring(request.label or "Hit Button")
        local reason = tostring(request.reason or "changes to the saved rotation")
        sameReason = sameReason and reason == firstReason
        labels[#labels + 1] = label
        lines[#lines + 1] = label .. ": " .. reason
        for _, value in ipairs({tostring(request.id or ""), label, reason}) do
            signature[#signature + 1] = #value .. ":" .. value
        end
    end
    local text
    if sameReason then
        text = "Stand and Hit requires preparation due to " .. firstReason
            .. "\n\nApplies to: " .. table.concat(labels, ", ")
    else
        text = "Stand and Hit requires preparation due to:\n\n" .. table.concat(lines, "\n")
    end
    return text, table.concat(signature, "|")
end

local function Fit(dialog)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not width or not height or width <= 24 or height <= 80 then return end
    dialog:SetScale(math.min(1, (width - 24) / WIDTH, (height - 80) / dialog:GetHeight()))
    dialog:ClearAllPoints()
    dialog:SetPoint("TOP", UIParent, "TOP", 0, -math.min(100, height * 0.1))
end

local function HideQuietly(dialog)
    dialog.quietHide = true
    dialog:Hide()
    dialog.quietHide = nil
end

local function Render(dialog, text)
    dialog.message:SetText(SafeText(text))
    local bodyHeight = math.max(30, dialog.message:GetStringHeight())
    dialog.message:SetHeight(bodyHeight)
    dialog.error:ClearAllPoints()
    dialog.error:SetPoint("TOPLEFT", dialog.content, "TOPLEFT", 0, -bodyHeight - 9)
    dialog.error:SetText(SafeText(dialog.failure))
    if dialog.failure then
        dialog.error:Show()
        local errorHeight = math.max(18, dialog.error:GetStringHeight())
        dialog.error:SetHeight(errorHeight)
        bodyHeight = bodyHeight + 9 + errorHeight
    else
        dialog.error:Hide()
    end
    bodyHeight = bodyHeight + 3
    dialog.content:SetHeight(bodyHeight)
    local visibleHeight = math.min(MAX_BODY_HEIGHT, bodyHeight)
    dialog.scroll:SetHeight(visibleHeight)
    dialog.scroll:UpdateScrollChildRect()
    dialog:SetHeight(46 + visibleHeight + 91)
    local inCombat = InCombatLockdown()
    dialog.prepare:SetEnabled(not inCombat and not dialog.busy)
    dialog.combatHelp:SetText(inCombat and "Prepare after combat." or "")
    Fit(dialog)
end

local function CreateNotice()
    local dialog = CreateFrame("Frame", "StandAndHitPreparationNotice", UIParent, "BackdropTemplate")
    SH.preparationUI = dialog
    dialog:SetSize(WIDTH, 210)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    dialog:SetBackdropColor(0.035, 0.05, 0.07, 0.99)
    dialog:SetBackdropBorderColor(0.23, 0.33, 0.4, 1)

    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dialog.title:SetPoint("TOPLEFT", 20, -16)
    dialog.title:SetTextColor(0.36, 0.78, 0.88)
    dialog.title:SetText("Stand and Hit")

    dialog.scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    dialog.scroll:SetPoint("TOPLEFT", 20, -46)
    dialog.scroll:SetWidth(CONTENT_WIDTH)
    dialog.scroll:EnableMouseWheel(true)
    dialog.content = CreateFrame("Frame", nil, dialog.scroll)
    dialog.content:SetSize(CONTENT_WIDTH, 1)
    dialog.scroll:SetScrollChild(dialog.content)
    dialog.message = dialog.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.message:SetPoint("TOPLEFT")
    dialog.message:SetWidth(CONTENT_WIDTH)
    dialog.message:SetJustifyH("LEFT")
    dialog.message:SetJustifyV("TOP")
    dialog.message:SetWordWrap(true)
    dialog.message:SetNonSpaceWrap(true)
    dialog.error = dialog.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.error:SetWidth(CONTENT_WIDTH)
    dialog.error:SetJustifyH("LEFT")
    dialog.error:SetJustifyV("TOP")
    dialog.error:SetWordWrap(true)
    dialog.error:SetNonSpaceWrap(true)
    dialog.error:SetTextColor(1, 0.55, 0.45)

    dialog.note = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.note:SetPoint("BOTTOMLEFT", 20, 65)
    dialog.note:SetWidth(WIDTH - 40)
    dialog.note:SetJustifyH("LEFT")
    dialog.note:SetTextColor(0.72, 0.78, 0.83)
    dialog.note:SetText("Reapplies saved rotations; draft edits stay unchanged.")
    dialog.combatHelp = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.combatHelp:SetPoint("BOTTOMLEFT", 20, 47)
    dialog.combatHelp:SetWidth(WIDTH - 40)
    dialog.combatHelp:SetJustifyH("LEFT")

    dialog.prepare = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.prepare:SetSize(128, 26)
    dialog.prepare:SetPoint("BOTTOM", -72, 13)
    dialog.prepare:SetText("Prepare")
    dialog.prepare:SetScript("OnClick", function()
        if dialog.busy or InCombatLockdown() or not dialog:IsShown() then return end
        dialog.busy = true
        dialog.prepare:Disable()
        local ok, message = SH:PrepareRequestedRotations()
        dialog.busy = nil
        dialog.failure = not ok and (message or "Could not prepare. Try again outside combat.") or nil
        SH:RefreshPreparationNotice(true)
        if dialog.failure and dialog:IsShown() then
            dialog.scroll:SetVerticalScroll(math.max(0, dialog.content:GetHeight() - dialog.scroll:GetHeight()))
        end
    end)
    dialog.dismiss = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.dismiss:SetSize(128, 26)
    dialog.dismiss:SetPoint("BOTTOM", 72, 13)
    dialog.dismiss:SetText("Dismiss")
    dialog.dismiss:SetScript("OnClick", function() dialog:Hide() end)
    dialog.close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    dialog.close:SetPoint("TOPRIGHT", -4, -4)
    dialog.close:SetScript("OnClick", function() dialog:Hide() end)

    HideQuietly(dialog)
    dialog:SetScript("OnHide", function(self)
        -- Alt+Z hides UIParent without closing this notice itself.
        if self:IsShown() then return end
        if not self.quietHide and not self.busy then SH:DismissPreparationRequests() end
        self.failure, self.signature = nil, nil
    end)
    dialog:SetScript("OnShow", function(self)
        local level = SH.ui and SH.ui:GetFrameLevel() or 0
        self:SetFrameLevel(math.max(self:GetFrameLevel(), level + 20))
        self:Raise()
    end)
    dialog:RegisterEvent("PLAYER_REGEN_DISABLED")
    dialog:RegisterEvent("PLAYER_REGEN_ENABLED")
    dialog:RegisterEvent("DISPLAY_SIZE_CHANGED")
    dialog:RegisterEvent("UI_SCALE_CHANGED")
    dialog:SetScript("OnEvent", function() SH:RefreshPreparationNotice() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "StandAndHitPreparationNotice") end
    return dialog
end

function SH:RefreshPreparationNotice(preserveError)
    if not SH.GetPreparationRequests then return end
    local requests = SH:GetPreparationRequests()
    local dialog = SH.preparationUI
    if #requests == 0 then
        if dialog then HideQuietly(dialog) end
        return
    end
    dialog = dialog or CreateNotice()
    local text, signature = RequestText(requests)
    if signature ~= dialog.signature then
        if not preserveError then dialog.failure = nil end
        dialog.scroll:SetVerticalScroll(0)
    end
    dialog.signature = signature
    Render(dialog, text)
    if not dialog:IsShown() then dialog:Show() end
    return dialog
end

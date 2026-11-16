local _, SH = ...

local WIDTH, HEIGHT = 760, 580
local CONTENT_WIDTH = WIDTH - 78
local BOLD_OFFSET = 0.6
local fields = {"enabled", "customTarget", "customCondition", "targetCasting", "totemCondition", "outOfCombatOnly", "inCombatOnly", "advanceOnToggle", "skipModifier", "priorityModifier", "spell", "rankID", "aura", "auraSource", "condition", "unit", "skipCooldown", "manualCooldown", "manualCooldownSeconds", "skipIfNotCasted", "skipIfImmune", "skipOutOfRange", "oncePerProc", "castCount", "castCountCondition", "stopCasting", "stopWhenInvalid", "useOr", "orAura", "orAuraSource", "orCondition"}

local function ActiveRotation()
    if SH.ui and SH.ui.rotation then return SH.ui.rotation end
    return SH.GetActiveRotation and SH:GetActiveRotation() or SH
end

local function SafeText(value)
    return (tostring(value or ""):gsub("|", "||"))
end

local function ResolveName(value)
    local id = tonumber(value)
    if not id then return tostring(value or "") end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
    elseif GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and type(name) == "string" then return name end
    end
    return tostring(value or "")
end

local function ResolveRankLabel(value, rankID)
    local id = tonumber(rankID) or tonumber(value)
    if not id then return nil end
    if SH.SpellRanks and SH.SpellRanks.GetChoices then
        local ok, choices = pcall(SH.SpellRanks.GetChoices, value)
        if ok and type(choices) == "table" then
            for _, choice in ipairs(choices) do
                if choice.id == id then return choice.label end
            end
        end
    end
    return "Selected ID: " .. id
end

local function Signature(rules, protectChannels, resolved, ranks)
    local parts = {protectChannels and "1" or "0"}
    local function Append(value)
        local text = type(value) .. ":" .. tostring(value)
        parts[#parts + 1] = #text .. ":" .. text
    end
    for _, rule in ipairs(rules or {}) do
        if type(rule) == "table" then
            for _, field in ipairs(fields) do Append(rule[field]) end
            local function AppendStructured(value)
                if type(value) ~= "table" then Append(value); return end
                local keys = {}
                for key in pairs(value) do keys[#keys + 1] = key end
                table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
                Append("{")
                for _, key in ipairs(keys) do Append(key); AppendStructured(value[key]) end
                Append("}")
            end
            for _, field in ipairs({"primaryCondition", "logicConditions", "healthConditions", "stackConditions"}) do
                Append(field); AppendStructured(rule[field])
            end
            Append(type(rule.comboPoints))
            if type(rule.comboPoints) == "table" then
                Append(rule.comboPoints.operator)
                Append(rule.comboPoints.value)
            else Append(rule.comboPoints) end
            Append(type(rule.hawkCount))
            if type(rule.hawkCount) == "table" then
                Append(rule.hawkCount.operator)
                Append(rule.hawkCount.value)
            else Append(rule.hawkCount) end
            for _, field in ipairs({"spell", "aura", "orAura"}) do
                local text = tostring(rule[field] or "")
                resolved[text] = ResolveName(rule[field])
                Append(resolved[text])
            end
            for _, field in ipairs({"andConditions", "orConditions", "notConditions", "resourceConditions"}) do
                Append(field)
                local list = rule[field]
                if type(list) == "table" then
                    -- Invalid sparse lists must refresh their warnings too.
                    local keys = {}
                    for key in pairs(list) do keys[#keys + 1] = key end
                    table.sort(keys, function(first, second)
                        return (type(first) .. ":" .. tostring(first)) < (type(second) .. ":" .. tostring(second))
                    end)
                    for _, key in ipairs(keys) do
                        Append(key)
                        local condition = list[key]
                        if type(condition) == "table" then
                            if field == "resourceConditions" then
                                Append(condition.resource)
                                Append(condition.operator)
                                Append(condition.percent)
                            else
                                Append(condition.aura)
                                Append(condition.auraSource)
                                Append(condition.condition)
                                local text = tostring(condition.aura or "")
                                resolved[text] = ResolveName(condition.aura)
                                Append(resolved[text])
                            end
                        else
                            Append(condition)
                        end
                        Append(";")
                    end
                else
                    Append(list)
                end
                Append("end")
            end
            local rank = ResolveRankLabel(rule.spell, rule.rankID)
            local id = tonumber(rule.rankID) or tonumber(rule.spell)
            if id then ranks[id] = rank end
            Append(rank)
        else
            Append(rule)
        end
        parts[#parts + 1] = ";"
    end
    return table.concat(parts, "|")
end

local function Fit(dialog)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if width and height and width > 24 and height > 24 then
        dialog:SetScale(math.min(1, (width - 24) / dialog:GetWidth(), (height - 24) / dialog:GetHeight()))
    end
end

local function BringToFront(dialog)
    local configLevel = SH.ui and SH.ui:GetFrameLevel() or 0
    -- Leave room above the editor's nested rows and controls, not just its backdrop.
    dialog:SetFrameLevel(math.max(dialog:GetFrameLevel(), configLevel + 10))
    dialog:Raise()
end

local function AcquireText(dialog, text, bold, color, x, y, width, wrap)
    dialog.used = dialog.used + 1
    local item = dialog.textPool[dialog.used]
    if not item then
        item = {text = dialog.scrollChild:CreateFontString(nil, "OVERLAY")}
        dialog.textPool[dialog.used] = item
    end
    local label = item.text
    label:ClearAllPoints()
    label:SetFont(dialog.fontFile, dialog.fontSize, dialog.fontFlags)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(wrap == true)
    label:SetNonSpaceWrap(wrap == true)
    label:SetTextColor(unpack(color))
    label:SetShadowOffset(0, 0)
    label:SetWidth(width)
    label:SetText(SafeText(text))
    label:SetPoint("TOPLEFT", dialog.scrollChild, "TOPLEFT", x, -y)
    label:Show()
    if bold then
        if not item.overprint then item.overprint = dialog.scrollChild:CreateFontString(nil, "OVERLAY") end
        local overprint = item.overprint
        overprint:ClearAllPoints()
        overprint:SetFont(dialog.fontFile, dialog.fontSize, dialog.fontFlags)
        overprint:SetJustifyH("LEFT")
        overprint:SetJustifyV("TOP")
        overprint:SetWordWrap(wrap == true)
        overprint:SetNonSpaceWrap(wrap == true)
        overprint:SetTextColor(unpack(color))
        overprint:SetShadowOffset(0, 0)
        overprint:SetWidth(width)
        overprint:SetText(SafeText(text))
        -- A same-color offset thickens the keyword without shipping another font.
        overprint:SetPoint("TOPLEFT", label, "TOPLEFT", BOLD_OFFSET, 0)
        overprint:Show()
    elseif item.overprint then
        item.overprint:Hide()
    end
    return label
end

local function Measure(dialog, text)
    dialog.measure:SetText(SafeText(text))
    return dialog.measure:GetStringWidth()
end

local function RenderTokens(dialog, tokens, indent, y, color, lineHeight, spaceWidth)
    local x, pendingSpace, lineUsed = indent, false, false
    for _, token in ipairs(tokens or {}) do
        local text = tostring(token.text or "")
        local cursor = 1
        while cursor <= #text do
            local first, last = text:find("%S+", cursor)
            if not first then pendingSpace = true; break end
            if first > cursor then pendingSpace = true end
            local word = text:sub(first, last)
            local width = math.max(1, Measure(dialog, word)) + (token.bold and BOLD_OFFSET or 0)
            local gap = lineUsed and pendingSpace and spaceWidth or 0
            local available = CONTENT_WIDTH - indent
            if lineUsed and x + gap + width > CONTENT_WIDTH then
                x, y, lineUsed, gap = indent, y + lineHeight, false, 0
            end
            if width > available then
                local label = AcquireText(dialog, word, token.bold, color, indent, y, available - 1, true)
                y = y + math.max(lineHeight, label:GetStringHeight() + 5)
                x, lineUsed = indent, false
            else
                AcquireText(dialog, word, token.bold, color, x + gap, y, width + 1, false)
                x, lineUsed = x + gap + width, true
            end
            pendingSpace = false
            cursor = last + 1
        end
    end
    if lineUsed then y = y + lineHeight end
    return y
end

local function Render(dialog, paragraphs)
    for _, item in ipairs(dialog.textPool) do
        item.text:Hide()
        if item.overprint then item.overprint:Hide() end
    end
    dialog.used = 0
    local y = 3
    dialog.measure:SetText("Ag")
    local lineHeight = math.max(dialog.fontSize, dialog.measure:GetStringHeight()) + 5
    local spaceWidth = math.max(2, Measure(dialog, "x x") - Measure(dialog, "xx"))
    local bodyColor = {0.94, 0.95, 0.97}
    local headingColor = {0.36, 0.78, 0.88}
    local noteColor = {0.72, 0.78, 0.83}
    for _, paragraph in ipairs(paragraphs) do
        if paragraph.kind == "rule" then
            y = RenderTokens(dialog, paragraph.tokens, 0, y, headingColor, lineHeight, spaceWidth) + 4
            for _, bullet in ipairs(paragraph.bullets or {}) do
                local depth = math.max(0, math.min(5, tonumber(bullet.depth) or 0))
                local markerX = 9 + depth * 22
                local indent = markerX + 17
                local color = bullet.condition == false and noteColor or bodyColor
                AcquireText(dialog, "\226\128\162", false, color, markerX, y, 12, false)
                -- Continuations align with the condition, leaving the bullet in its own gutter.
                y = RenderTokens(dialog, bullet.tokens, indent, y, color, lineHeight, spaceWidth) + 3
            end
            y = y + 14
        else
            local color = paragraph.kind == "warning" and {1, 0.67, 0.36}
                or paragraph.kind == "note" and noteColor or bodyColor
            local indent = paragraph.ruleIndex and 30 or 0
            if paragraph.ruleIndex then
                AcquireText(dialog, tostring(paragraph.ruleIndex) .. ".", false, headingColor, 0, y, 27, false)
            end
            y = RenderTokens(dialog, paragraph.tokens, indent, y, color, lineHeight, spaceWidth) + 11
        end
    end
    dialog.scrollChild:SetHeight(math.max(1, y))
    dialog.scroll:UpdateScrollChildRect()
    local offset = math.min(dialog.scroll:GetVerticalScroll(), math.max(0, y - dialog.scroll:GetHeight()))
    dialog.scroll:SetVerticalScroll(offset)
    if dialog.scroll.ScrollBar then dialog.scroll.ScrollBar:SetValue(offset) end
end

local function ClipboardText(dialog)
    local text = (dialog.textTitle or dialog.title:GetText()) .. "\n\n" .. (dialog.plainText or "")
    -- Paragraph tokens are plain text. Also remove markup pasted into a draft field.
    return (text:gsub("||", "\001")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("\001", "|"))
end

local function DiagramEnabled()
    return SH.rootDB and SH.rootDB.functionBlockDiagramsEnabled == true and SH.Diagram and SH.DiagramUI
end

local function CaptureControls(capture, message)
    capture.pending, capture.requested = nil, nil
    capture.toolbar:Show()
    capture.diagram.hint:Show()
    capture.diagram.horizontal:SetShown((capture.diagram.maxHorizontal or 0) > 0)
    if capture.diagram.scroll.ScrollBar then capture.diagram.scroll.ScrollBar:Show() end
    capture.diagram.scroll:EnableMouseWheel(true)
    if message then capture.status:SetText(message) end
end

local function TakeDiagramScreenshot(capture)
    if capture.pending then return end
    if InCombatLockdown() then capture:Hide(); return end
    if type(Screenshot) ~= "function" then
        capture.status:SetText("Screenshot is unavailable on this client. You can use your normal screenshot key.")
        return
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        capture.status:SetText("A clean capture is unavailable on this client. You can use your normal screenshot key.")
        return
    end
    capture.sequence = (capture.sequence or 0) + 1
    local sequence = capture.sequence
    capture.pending, capture.requested = sequence, false
    capture.toolbar:Hide()
    capture.diagram.hint:Hide()
    capture.diagram.horizontal:Hide()
    if capture.diagram.scroll.ScrollBar then capture.diagram.scroll.ScrollBar:Hide() end
    capture.diagram.scroll:EnableMouseWheel(false)
    if GameTooltip then GameTooltip:Hide() end
    local queued = pcall(C_Timer.After, 0.12, function()
        if not capture:IsShown() or capture.pending ~= sequence then return end
        if InCombatLockdown() then capture:Hide(); return end
        capture.requested = true
        local ok = pcall(Screenshot)
        if not ok and capture.pending == sequence then
            CaptureControls(capture, "WoW could not take the screenshot. Try your normal screenshot key.")
        end
    end)
    if not queued then
        CaptureControls(capture, "WoW could not queue the screenshot. Try your normal screenshot key.")
        return
    end
    local watched = pcall(C_Timer.After, 5, function()
        if capture:IsShown() and capture.pending == sequence then
            CaptureControls(capture, "WoW hasn't confirmed the capture. Check the Screenshots folder before trying again.")
        end
    end)
    if not watched then
        CaptureControls(capture, "WoW could not queue the capture check. Try your normal screenshot key.")
    end
end

local function ShowDiagramCapture(dialog)
    if InCombatLockdown() then dialog.copyStatus:SetText("Leave combat before taking a diagram screenshot."); return end
    if not DiagramEnabled() or dialog.viewMode ~= "diagram" then return end
    SH:RefreshExplanation(true)
    local capture = dialog.capture
    if not capture then
        capture = CreateFrame("Frame", "StandAndHitDiagramCapture", UIParent, "BackdropTemplate")
        dialog.capture = capture
        capture:SetAllPoints(UIParent)
        capture:SetFrameStrata("FULLSCREEN_DIALOG")
        capture:SetFrameLevel(dialog:GetFrameLevel() + 100)
        capture:EnableMouse(true)
        capture:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
        capture:SetBackdropColor(0.035, 0.05, 0.07, 1)
        if UISpecialFrames then table.insert(UISpecialFrames, "StandAndHitDiagramCapture") end
        capture.title = capture:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        capture.title:SetPoint("TOPLEFT", 22, -20)
        capture.title:SetTextColor(0.36, 0.78, 0.88)
        capture.diagram = SH.DiagramUI.Create(capture, 1000, 600)
        capture.diagram:SetPoint("TOPLEFT", 22, -58)
        local toolbar = CreateFrame("Frame", nil, capture)
        toolbar:SetPoint("BOTTOMLEFT", 22, 17); toolbar:SetPoint("BOTTOMRIGHT", -22, 17); toolbar:SetHeight(70)
        capture.toolbar = toolbar
        capture.status = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        capture.status:SetPoint("TOPLEFT", 0, 0)
        capture.status:SetJustifyH("LEFT"); capture.status:SetWordWrap(true)
        local take = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
        take:SetSize(170, 27); take:SetPoint("BOTTOMLEFT", 0, 0); take:SetText("Take screenshot")
        take:SetScript("OnClick", function() TakeDiagramScreenshot(capture) end)
        capture.take = take
        local back = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
        back:SetSize(130, 27); back:SetPoint("BOTTOMRIGHT", 0, 0); back:SetText("Back")
        back:SetScript("OnClick", function() capture:Hide() end)
        capture.back = back
        capture:SetScript("OnHide", function(self)
            self.sequence = (self.sequence or 0) + 1
            CaptureControls(self)
        end)
        for _, event in ipairs({"SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED"}) do
            capture:RegisterEvent(event)
        end
        capture:SetScript("OnEvent", function(self, event)
            if not self:IsShown() then return end
            if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" or event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
                self:Hide()
                dialog.copyStatus:SetText("Diagram capture closed when combat, the world, or the display changed.")
            elseif self.pending and self.requested then
                if event == "SCREENSHOT_SUCCEEDED" then
                    CaptureControls(self, "Saved in WoW's Screenshots folder. Scroll to another section if you want another image.")
                elseif event == "SCREENSHOT_FAILED" then
                    CaptureControls(self, "WoW couldn't save the screenshot. Check your Screenshots folder and try again.")
                end
            end
        end)
    end
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    capture.diagram:SetSize(math.max(320, width - 44), math.max(240, height - 155))
    capture.status:SetWidth(math.max(280, width - 50))
    capture.title:SetText("Stand and Hit - " .. (dialog.rotationLabel or "Hit Button") .. " rotation diagram")
    capture:Show(); capture:Raise()
    CaptureControls(capture, "Scroll to the section you want, then click Take screenshot. Only the visible part is saved. Hold Shift and scroll to move sideways.")
    capture.diagram:Render(dialog.diagramGraph)
    local original = dialog.diagramView
    if original then
        local vertical = math.min(original.scroll:GetVerticalScroll(), math.max(0, capture.diagram.content:GetHeight() - capture.diagram.scroll:GetHeight()))
        capture.diagram.scroll:SetVerticalScroll(vertical)
        if capture.diagram.scroll.ScrollBar then capture.diagram.scroll.ScrollBar:SetValue(vertical) end
        capture.diagram.horizontal:SetValue(math.min(capture.diagram.maxHorizontal or 0, original.scroll:GetHorizontalScroll() or 0))
    end
    if GameTooltip then GameTooltip:Hide() end
end

local function RefreshPresentation(dialog)
    local enabled = DiagramEnabled() and true or false
    if enabled and not dialog.diagramWasEnabled then dialog.viewMode = "diagram" end
    if not enabled then dialog.viewMode = "text" end
    if not enabled and dialog.capture then dialog.capture:Hide() end
    dialog.diagramWasEnabled = enabled
    local diagram = enabled and dialog.viewMode == "diagram"
    dialog:SetSize(diagram and 1100 or WIDTH, diagram and 720 or HEIGHT)
    dialog.subtitle:SetWidth(dialog:GetWidth() - 66)
    dialog.textTab:SetShown(enabled); dialog.diagramTab:SetShown(enabled)
    dialog.textTab:SetEnabled(diagram); dialog.diagramTab:SetEnabled(not diagram)
    local top = enabled and 137 or 101
    dialog.scroll:ClearAllPoints()
    dialog.scroll:SetPoint("TOPLEFT", 22, -top); dialog.scroll:SetPoint("BOTTOMRIGHT", -39, 60)
    if dialog.copyPanel then
        dialog.copyPanel:ClearAllPoints()
        dialog.copyPanel:SetPoint("TOPLEFT", 22, -top); dialog.copyPanel:SetPoint("BOTTOMRIGHT", -22, 60)
    end
    if enabled and not dialog.diagramView then
        dialog.diagramView = SH.DiagramUI.Create(dialog, 1039, 523)
        dialog.diagramView:SetPoint("TOPLEFT", 22, -137)
    end
    if dialog.diagramView then dialog.diagramView:SetSize(dialog:GetWidth() - 61, dialog:GetHeight() - top - 60) end
    local copying = dialog.copyPanel and dialog.copyPanel:IsShown()
    dialog.screenshot:SetShown(diagram and not copying)
    dialog.screenshot:SetEnabled(not InCombatLockdown())
    dialog.exportImage:SetShown(diagram and not copying and SH.DiagramExport ~= nil)
    dialog.scroll:SetShown(not diagram and not copying)
    if dialog.diagramView then dialog.diagramView:SetShown(diagram and not copying) end
    if diagram and dialog.rotationLabel then dialog.title:SetText("Rotation function block diagram: " .. dialog.rotationLabel)
    elseif dialog.textTitle then dialog.title:SetText(dialog.textTitle) end
    Fit(dialog)
end

local function CloseCopyPanel(dialog)
    if dialog.copyPanel then
        dialog.copyEdit:ClearFocus()
        dialog.copyPanel:Hide()
    end
    RefreshPresentation(dialog)
    dialog.copyBack:Hide()
end

local function ShowCopyPanel(dialog, text, imageExport)
    if not dialog.copyPanel then
        local panel = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
        panel:SetPoint("TOPLEFT", 22, -101)
        panel:SetPoint("BOTTOMRIGHT", -22, 60)
        panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        panel:SetBackdropColor(0.02, 0.03, 0.04, 1)
        panel:SetBackdropBorderColor(0.23, 0.33, 0.4, 1)
        dialog.copyPanel = panel

        local instructions = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        instructions:SetPoint("TOPLEFT", 10, -10)
        instructions:SetJustifyH("LEFT"); instructions:SetWordWrap(true)
        dialog.copyInstructions = instructions

        local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 9, -9)
        scroll:SetPoint("BOTTOMRIGHT", -31, 9)
        dialog.copyScroll = scroll
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(0)
        edit:SetFont(dialog.fontFile, dialog.fontSize, dialog.fontFlags)
        edit:SetSize(CONTENT_WIDTH - 6, 1)
        edit:SetTextInsets(0, 0, 0, 0)
        scroll:SetScrollChild(edit)
        dialog.copyEdit = edit
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(self.copySnapshot or "") end
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
        edit:SetScript("OnEscapePressed", function() CloseCopyPanel(dialog); dialog.copyStatus:SetText("") end)
        edit:SetScript("OnHide", function(self) self:ClearFocus() end)
        scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    end
    dialog.scroll:Hide()
    if dialog.diagramView then dialog.diagramView:Hide() end
    dialog.copyPanel:Show()
    dialog.screenshot:Hide()
    dialog.exportImage:Hide()
    dialog.copyBack:Show()
    dialog.copyStatus:SetText("Press Ctrl+C to copy the selected text.")
    dialog.copyInstructions:SetShown(imageExport == true)
    dialog.copyInstructions:SetWidth(dialog:GetWidth() - 90)
    dialog.copyInstructions:SetText("1. Press Ctrl+C to copy the selected text.\n2. Open diagram-export.html from your StandAndHit addon folder in your browser.\n3. Paste it, click Preview diagram, then Download PNG for one image of the entire rotation.")
    dialog.copyScroll:ClearAllPoints()
    dialog.copyScroll:SetPoint("TOPLEFT", 9, imageExport and -82 or -9)
    dialog.copyScroll:SetPoint("BOTTOMRIGHT", -31, 9)
    local edit = dialog.copyEdit
    edit.copySnapshot = text
    edit:SetText(text)
    edit:SetCursorPosition(0)
    dialog.copyScroll:SetVerticalScroll(0)
    edit:SetFocus()
    edit:HighlightText()
end

local function CopyExplanation(dialog)
    SH:RefreshExplanation(true)
    ShowCopyPanel(dialog, ClipboardText(dialog))
end

local function ExportDiagramImage(dialog)
    if not DiagramEnabled() or not SH.DiagramExport then return end
    SH:RefreshExplanation(true)
    local svg, width, height = SH.DiagramExport.ToSVG(dialog.diagramGraph,
        "Stand and Hit - " .. (dialog.rotationLabel or "Hit Button") .. " rotation diagram")
    if not svg then dialog.copyStatus:SetText(width or "The diagram could not be exported."); return end
    ShowCopyPanel(dialog, svg, true)
    dialog.copyStatus:SetText("Entire rotation: " .. width .. " x " .. height .. ". Press Ctrl+C to copy.")
end

local function CreateDialog()
    local dialog = CreateFrame("Frame", "StandAndHitExplanation", UIParent, "BackdropTemplate")
    SH.explanationUI = dialog
    dialog:SetSize(WIDTH, HEIGHT)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    dialog:SetScript("OnHide", function(self)
        if self.capture then self.capture:Hide() end
        self:StopMovingOrSizing()
        CloseCopyPanel(self)
        self.copyStatus:SetText("")
    end)
    dialog:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    dialog:SetBackdropColor(0.035, 0.05, 0.07, 0.99)
    dialog:SetBackdropBorderColor(0.23, 0.33, 0.4, 1)
    if UISpecialFrames then table.insert(UISpecialFrames, "StandAndHitExplanation") end

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetTextColor(0.36, 0.78, 0.88)
    title:SetText("Rotation textual explanation")
    dialog.title = title
    local subtitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", 23, -51)
    subtitle:SetWidth(WIDTH - 66)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Your current draft, in priority order. The first matching rule wins.\nClick Prepare outside combat to apply draft changes.")
    dialog.subtitle = subtitle
    local textTab = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    textTab:SetSize(110, 27); textTab:SetPoint("TOPLEFT", 22, -96); textTab:SetText("Text")
    textTab:SetScript("OnClick", function()
        CloseCopyPanel(dialog); dialog.viewMode = "text"; SH:RefreshExplanation(true)
    end)
    textTab:Hide(); dialog.textTab = textTab
    local diagramTab = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    diagramTab:SetSize(180, 27); diagramTab:SetPoint("LEFT", textTab, "RIGHT", 8, 0); diagramTab:SetText("Function Block Diagram")
    diagramTab:SetScript("OnClick", function()
        CloseCopyPanel(dialog); dialog.viewMode = "diagram"; SH:RefreshExplanation(true)
    end)
    diagramTab:Hide(); dialog.diagramTab = diagramTab
    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() dialog:Hide() end)
    dialog.close = close

    dialog.scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    dialog.scroll:SetPoint("TOPLEFT", 22, -101)
    dialog.scroll:SetPoint("BOTTOMRIGHT", -39, 60)
    dialog.scrollChild = CreateFrame("Frame", nil, dialog.scroll)
    dialog.scrollChild:SetSize(CONTENT_WIDTH, 1)
    dialog.scroll:SetScrollChild(dialog.scrollChild)
    dialog.textPool = {}
    dialog.measure = dialog.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.fontFile, dialog.fontSize, dialog.fontFlags = dialog.measure:GetFont()
    dialog.fontFile = dialog.fontFile or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    dialog.fontSize = math.max(13, dialog.fontSize or 12)
    dialog.fontFlags = dialog.fontFlags or ""
    dialog.measure:SetFont(dialog.fontFile, dialog.fontSize, dialog.fontFlags)
    dialog.measure:SetWordWrap(false)
    dialog.measure:SetNonSpaceWrap(false)
    dialog.measure:SetText("Ag")
    dialog.measure:Hide()
    local copy = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    copy:SetSize(172, 26)
    copy:SetPoint("BOTTOMLEFT", 22, 19)
    copy:SetText("Copy to clipboard")
    copy:SetScript("OnClick", function() CopyExplanation(dialog) end)
    dialog.copy = copy
    local copyStatus = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    copyStatus:SetPoint("LEFT", copy, "RIGHT", 12, 0)
    copyStatus:SetWidth(414)
    copyStatus:SetJustifyH("LEFT")
    dialog.copyStatus = copyStatus
    local screenshot = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    screenshot:SetSize(130, 26); screenshot:SetPoint("BOTTOMRIGHT", -22, 19); screenshot:SetText("Screenshot")
    screenshot:SetScript("OnClick", function() ShowDiagramCapture(dialog) end)
    screenshot:Hide(); dialog.screenshot = screenshot
    local exportImage = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    exportImage:SetSize(140, 26); exportImage:SetPoint("RIGHT", screenshot, "LEFT", -8, 0); exportImage:SetText("Export image")
    exportImage:SetScript("OnClick", function() ExportDiagramImage(dialog) end)
    exportImage:Hide(); dialog.exportImage = exportImage
    local back = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    back:SetSize(94, 26)
    back:SetPoint("BOTTOMRIGHT", -22, 19)
    back:SetText("Back")
    back:SetScript("OnClick", function() CloseCopyPanel(dialog); dialog.copyStatus:SetText("") end)
    back:Hide()
    dialog.copyBack = back
    dialog:SetScript("OnShow", function(self)
        Fit(self)
        BringToFront(self)
        SH:RefreshExplanation(true)
    end)
    dialog:RegisterEvent("DISPLAY_SIZE_CHANGED")
    dialog:RegisterEvent("UI_SCALE_CHANGED")
    dialog:RegisterEvent("PLAYER_REGEN_DISABLED")
    dialog:RegisterEvent("PLAYER_REGEN_ENABLED")
    dialog:SetScript("OnEvent", function(self)
        if self:IsShown() then Fit(self); self.screenshot:SetEnabled(not InCombatLockdown()) end
    end)
    dialog:Hide()
    return dialog
end

function SH:RefreshExplanation(force)
    local dialog = SH.explanationUI
    if not dialog or not dialog:IsShown() then return end
    local rotation = ActiveRotation()
    local rules = SH.ui and SH.ui.rotation == rotation and SH.ui.draft or rotation:GetDraftRules()
    local protectChannels = not rotation.db or rotation.db.preventClipping ~= false
    local resolved, ranks = {}, {}
    local label = rotation.label or ((rotation.index or 1) > 1 and ("Hit Button " .. rotation.index) or "Hit Button")
    local signature = tostring(rotation.index or 1) .. ":" .. label .. ":"
        .. Signature(rules, protectChannels, resolved, ranks)
    RefreshPresentation(dialog)
    signature = signature .. ":" .. tostring(dialog.viewMode) .. ":" .. tostring(dialog.diagramWasEnabled)
    if not force and signature == dialog.signature then return end
    if dialog.rotationIndex ~= (rotation.index or 1) then
        CloseCopyPanel(dialog)
        dialog.copyStatus:SetText("")
    end
    dialog.rotationIndex = rotation.index or 1
    dialog.rotationLabel, dialog.textTitle = label, "Rotation textual explanation: " .. label
    dialog.title:SetText(dialog.viewMode == "diagram" and ("Rotation function block diagram: " .. label) or dialog.textTitle)
    local priorityModifiers = false
    for _, row in ipairs(rules) do
        if row.enabled ~= false and row.priorityModifier then priorityModifiers = true; break end
    end
    dialog.subtitle:SetText(label .. (priorityModifiers and "'s current draft. Held modifiers can change the priority order." or
        "'s current draft, in priority order. The first matching rule wins.") .. "\nClick Prepare outside combat to apply draft changes.")
    local options = {
        preventClipping = protectChannels,
        resolveName = function(value) return resolved[tostring(value or "")] or ResolveName(value) end,
        resolveRankLabel = function(value, rankID)
            local id = tonumber(rankID) or tonumber(value)
            return id and ranks[id] or ResolveRankLabel(value, rankID)
        end,
    }
    local paragraphs = SH.Explanation.Build(rules, options)
    dialog.paragraphs = paragraphs
    dialog.plainText = SH.Explanation.PlainText(paragraphs)
    if signature ~= dialog.signature and not (dialog.copyPanel and dialog.copyPanel:IsShown()) then
        dialog.copyStatus:SetText("")
    end
    Render(dialog, paragraphs)
    if dialog.viewMode == "diagram" and dialog.diagramView then
        dialog.diagramGraph = SH.Diagram.BuildRotation(rules, options)
        dialog.diagramView:Render(dialog.diagramGraph, function(node)
            if node.ruleIndex and node.editable then
                SH:ShowConfig()
                if SH.ui and SH.ui.OpenDiagramNode then SH.ui.OpenDiagramNode(node); dialog:Hide() end
            end
        end)
    end
    dialog.signature = signature
end

function SH:ShowExplanation()
    local dialog = SH.explanationUI or CreateDialog()
    Fit(dialog)
    if dialog:IsShown() then SH:RefreshExplanation(true) else dialog:Show() end
    BringToFront(dialog)
    return dialog
end

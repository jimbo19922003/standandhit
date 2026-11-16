local _, SH = ...

function SH:UpdateLauncherPosition()
    if not self.launcher or not Minimap or InCombatLockdown() then return end
    local angle = math.rad(self.db.minimapAngle or 225)
    local width, height = Minimap:GetWidth(), Minimap:GetHeight()
    local radiusX = (width > 0 and width or 140) / 2 + 10
    local radiusY = (height > 0 and height or 140) / 2 + 10
    self.launcher:ClearAllPoints()
    self.launcher:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radiusX, math.sin(angle) * radiusY)
end

function SH:MoveLauncherToCursor()
    if InCombatLockdown() or not Minimap then return end
    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then return end
    local scale = Minimap:GetEffectiveScale()
    if not scale or scale <= 0 then return end
    local cursorX, cursorY = GetCursorPosition()
    local x, y = cursorX / scale - centerX, cursorY / scale - centerY
    if x == 0 and y == 0 then return end
    local angle
    if math.atan2 then angle = math.atan2(y, x)
    elseif x == 0 then angle = y > 0 and math.pi / 2 or -math.pi / 2
    else
        angle = math.atan(y / x)
        if x < 0 then angle = angle + math.pi end
    end
    self.db.minimapAngle = math.deg(angle) % 360
    self:UpdateLauncherPosition()
end

function SH:StopLauncherDrag()
    local launcher = self.launcher
    if not launcher or not launcher.dragging then return end
    self:MoveLauncherToCursor()
    launcher.dragging = nil
    launcher:SetScript("OnUpdate", nil)
    -- Keep the release from opening settings. The next mouse-down resets this.
    launcher.suppressClick = true
end

function SH:CreateLauncher()
    if not Minimap or InCombatLockdown() then return end
    if self.launcher then self:UpdateLauncherPosition(); return end
    local launcher = CreateFrame("Button", "StandAndHitLauncher", Minimap)
    launcher:SetSize(32, 32)
    launcher:SetFrameStrata("MEDIUM")
    launcher:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    launcher:SetClampedToScreen(true)
    launcher:RegisterForClicks("LeftButtonUp")
    launcher:RegisterForDrag("LeftButton")

    -- The artwork includes its own rim and lettering; keep its full silhouette.
    launcher.Icon = launcher:CreateTexture(nil, "ARTWORK")
    launcher.Icon:SetAllPoints(launcher)
    launcher.Icon:SetTexture("Interface\\AddOns\\StandAndHit\\Media\\MinimapIcon")
    launcher:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    launcher:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.suppressClick = IsShiftKeyDown() and true or nil end
    end)
    launcher:SetScript("OnDragStart", function(self, button)
        if button ~= "LeftButton" or not IsShiftKeyDown() or InCombatLockdown() then return end
        self.dragging, self.suppressClick = true, true
        GameTooltip:Hide()
        SH:MoveLauncherToCursor()
        self:SetScript("OnUpdate", function()
            if InCombatLockdown() then SH:StopLauncherDrag()
            else SH:MoveLauncherToCursor() end
        end)
    end)
    launcher:SetScript("OnDragStop", function() SH:StopLauncherDrag() end)
    launcher:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then SH:StopLauncherDrag() end
    end)
    launcher:SetScript("OnClick", function(self)
        if self.suppressClick or self.dragging or IsShiftKeyDown() then
            self.suppressClick = nil
            return
        end
        SH:ShowConfig()
    end)
    launcher:SetScript("OnEnter", function(self)
        if self.dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Stand and Hit (S&H)")
        GameTooltip:AddLine("Left-click to open spell rules and Prepare.", 0.8, 0.85, 0.9)
        GameTooltip:AddLine("Hold Shift and left-drag around the minimap to move outside combat.", 0.6, 0.85, 0.9, true)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
    launcher:SetScript("OnHide", function() SH:StopLauncherDrag(); GameTooltip:Hide() end)
    launcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    launcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    launcher:RegisterEvent("UI_SCALE_CHANGED")
    launcher:SetScript("OnEvent", function()
        SH:StopLauncherDrag()
        SH:UpdateLauncherPosition()
    end)
    self.launcher = launcher
    Minimap:HookScript("OnSizeChanged", function() SH:UpdateLauncherPosition() end)
    self:UpdateLauncherPosition()
end

local _, SH = ...

-- Owned tooltip padding carries the actual count and an alternating challenge.
-- The commit frame is updated only after the data frame has been checked.
local C = {ready = false, reason = "Combo points have not been prepared.",
    widths = {data = {}, commit = {}}}
SH.ComboPoints = C
local TOLERANCE = 0.5

C.READ_SNIPPET = [[
    self:SetAttribute("sh-combo-count", -1)
    local data = self:GetFrameRef("combo-data")
    local commit = self:GetFrameRef("combo-commit")
    if not data or not commit then return false end
    if data:IsShown() ~= true or commit:IsShown() ~= true then return false end
    local oldWidth, oldCode = commit:GetWidth(), -1
    if rawtype(oldWidth) ~= "number" then return false end
    for code = 0, 11 do
        local width = self:GetAttribute("sh-combo-commit-width" .. code)
        if rawtype(width) ~= "number" then return false end
        if math.abs(width - oldWidth) <= 0.5 then
            if oldCode ~= -1 then return false end
            oldCode = code
        end
    end
    if oldCode < 0 then return false end
    local requested = 0
    if oldCode < 6 then requested = 1 end
    self:CallMethod("RefreshComboPoints", requested)
    if data:IsShown() ~= true or commit:IsShown() ~= true then return false end
    local dataWidth, commitWidth = data:GetWidth(), commit:GetWidth()
    if rawtype(dataWidth) ~= "number" or rawtype(commitWidth) ~= "number" then return false end
    local dataCode, commitCode = -1, -1
    for code = 0, 11 do
        local expectedData = self:GetAttribute("sh-combo-data-width" .. code)
        local expectedCommit = self:GetAttribute("sh-combo-commit-width" .. code)
        if rawtype(expectedData) ~= "number" or rawtype(expectedCommit) ~= "number" then return false end
        if math.abs(expectedData - dataWidth) <= 0.5 then
            if dataCode ~= -1 then return false end
            dataCode = code
        end
        if math.abs(expectedCommit - commitWidth) <= 0.5 then
            if commitCode ~= -1 then return false end
            commitCode = code
        end
    end
    if dataCode < 0 or dataCode ~= commitCode or commitCode == oldCode then return false end
    if not ((requested == 0 and commitCode < 6) or (requested == 1 and commitCode >= 6)) then return false end
    self:SetAttribute("sh-combo-count", commitCode % 6)
    return true
]]

local function secret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, result = pcall(issecretvalue, value)
    return not ok or type(result) ~= "boolean" or result
end

local function message(value)
    if secret(value) then return "Unreadable result" end
    if type(value) ~= "string" then return "Combo-point signal unavailable" end
    return value:gsub("[\r\n\t]", " "):sub(1, 300)
end

local function number(value)
    return not secret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function integer(value, minimum, maximum)
    return number(value) and value >= minimum and value <= maximum and value % 1 == 0
end

local function combat()
    if type(InCombatLockdown) ~= "function" then error("Combat state is unavailable", 0) end
    local value = InCombatLockdown()
    if secret(value) or type(value) ~= "boolean" then error("Combat state is unreadable", 0) end
    return value
end

local function outsideCombat()
    if combat() then error("Prepare combo points outside combat", 0) end
end

local function nativeCall(name, fn, ...)
    if secret(fn) or type(fn) ~= "function" then error(name .. " is unavailable", 0) end
    local label = "Combo points: " .. name
    -- Both tooltip setters use the same label. An actual denial on either frame
    -- stops subsequent combat attempts, including after another Prepare.
    if SH.blockedNativeCalls and SH.blockedNativeCalls[label] and combat() then
        error("Client blocked " .. label .. "; combo-point conditions are unavailable in combat this session", 0)
    end
    if SH.CallNativeDiagnostic then return SH:CallNativeDiagnostic(label, fn, ...) end
    return fn(...)
end

local function required(object, name, ...)
    if secret(object) or object == nil then error(name .. " is unavailable", 0) end
    local value = nativeCall("Frame:" .. name, object[name], object, ...)
    if secret(value) then error(name .. " returned an unreadable result", 0) end
    return value
end

local function readWidth(frame)
    if required(frame, "IsShown") ~= true then error("Combo-point signal is hidden", 0) end
    local value = required(frame, "GetWidth")
    if not number(value) or value <= 0 then error("Combo-point width is unreadable", 0) end
    return value
end

local function near(left, right)
    return number(left) and number(right) and math.abs(left - right) <= TOLERANCE
end

local function setCode(frame, code)
    if not integer(code, 0, 11) then error("Invalid combo-point signal code", 0) end
    required(frame, "SetPadding", 16 + code * 32, 0, 0, 0)
end

local function hideOwned()
    outsideCombat()
    if C.dataFrame then required(C.dataFrame, "Hide") end
    if C.commitFrame then required(C.commitFrame, "Hide") end
end

local function restoreTooltip(frame)
    outsideCombat()
    -- A hidden tooltip may have lost its owner and content. Show alone cannot
    -- rebuild it; restore the same seed before checking existing calibration.
    required(frame, "SetAlpha", 0)
    required(frame, "SetOwner", UIParent, "ANCHOR_NONE")
    -- Match SharedTooltip_OnHide's reset, which these bare frames lack.
    required(frame, "SetPadding", 0, 0, 0, 0)
    required(frame, "SetClampedToScreen", false)
    required(frame, "ClearAllPoints")
    required(frame, "SetPoint", "TOPRIGHT", UIParent, "BOTTOMLEFT", -256, -256)
    required(frame, "SetText", "0", 1, 1, 1, 0, false)
    required(frame, "Show")
    required(frame, "SetAlpha", 0)
end

local function createTooltip(kind)
    outsideCombat()
    local slot, initialized = kind .. "Frame", kind .. "Initialized"
    local name = "StandAndHitCombo" .. (kind == "data" and "Data" or "Commit")
    local frame = nativeCall("CreateFrame", CreateFrame, "GameTooltip", name, UIParent, "SecureFrameTemplate")
    -- Keep ownership even when an intermediate setup call fails.
    C[slot], C[initialized] = frame, false
    local left = required(frame, "CreateFontString", name .. "TextLeft1", "ARTWORK", "GameTooltipText")
    local right = required(frame, "CreateFontString", name .. "TextRight1", "ARTWORK", "GameTooltipText")
    required(left, "SetAlpha", 0)
    required(right, "SetAlpha", 0)
    required(frame, "AddFontStrings", left, right)
    restoreTooltip(frame)
    if required(frame, "IsProtected") ~= true then error("Combo-point signal is not protected", 0) end
    C[initialized] = true
    return frame
end

local function calibrate(kind)
    local frame, widths = C[kind .. "Frame"], C.widths[kind]
    -- Older attached buttons retain these widths. Once prepared, never replace
    -- their calibration under them when another rotation is prepared.
    local keep = C.calibrated == true
    for code = 0, 11 do
        outsideCombat()
        setCode(frame, code)
        local measured = readWidth(frame)
        if keep then
            if not near(widths[code], measured) then
                error(string.format("Combo-point layout changed (%s %d: expected %.2f, got %.2f). Reload before preparing again.",
                    kind, code, widths[code], measured), 0)
            end
        else
            widths[code] = measured
        end
        for earlier = 0, code - 1 do
            if math.abs(widths[earlier] - measured) <= 2 * TOLERANCE then
                error("Combo-point signal cannot distinguish the point counts", 0)
            end
        end
    end
    for code = 10, 0, -1 do
        outsideCombat()
        setCode(frame, code)
        if not near(widths[code], readWidth(frame)) then
            error("Combo-point signal did not return to its earlier value", 0)
        end
    end
end

function C:Prepare()
    local permitted, reason = pcall(outsideCombat)
    if not permitted then self.reason = message(reason); return false, self.reason end
    self.ready = false
    local ok, err = pcall(function()
        if type(GetComboPoints) ~= "function" then error("Target combo-point readings are unavailable", 0) end
        if type(SecureHandlerSetFrameRef) ~= "function" then error("Secure frame references are unavailable", 0) end
        if (self.dataFrame and not self.dataInitialized) or (self.commitFrame and not self.commitInitialized) then
            error("Combo-point setup was incomplete. Reload before preparing again.", 0)
        end
        for _, kind in ipairs({"data", "commit"}) do
            local frame = self[kind .. "Frame"]
            if not frame then createTooltip(kind)
            elseif required(frame, "IsShown") ~= true then restoreTooltip(frame)
            else required(frame, "SetAlpha", 0) end
            calibrate(kind)
        end
        self.calibrated = true
        if not self.lifecycle then
            self.lifecycle = nativeCall("CreateFrame", CreateFrame, "Frame")
            required(self.lifecycle, "RegisterEvent", "PLAYER_LOGOUT")
            required(self.lifecycle, "SetScript", "OnEvent", function() C:Cleanup() end)
        end
    end)
    if not ok then
        self.reason = message(err)
        pcall(hideOwned)
        return false, self.reason
    end
    self.ready, self.reason = true, nil
    return true
end

function C:Attach(button)
    local ok, err = pcall(function()
        outsideCombat()
        if not self.ready then error(self.reason or "Combo points have not been prepared", 0) end
        nativeCall("SecureHandlerSetFrameRef", SecureHandlerSetFrameRef, button, "combo-data", self.dataFrame)
        nativeCall("SecureHandlerSetFrameRef", SecureHandlerSetFrameRef, button, "combo-commit", self.commitFrame)
        for code = 0, 11 do
            required(button, "SetAttribute", "sh-combo-data-width" .. code, self.widths.data[code])
            required(button, "SetAttribute", "sh-combo-commit-width" .. code, self.widths.commit[code])
        end
    end)
    if not ok then self.reason = message(err); return false, self.reason end
    self.reason = nil
    return true
end

function C:Refresh(ack)
    local ok, err = pcall(function()
        if not self.ready then error(self.reason or "Combo points have not been prepared", 0) end
        if not integer(ack, 0, 1) then error("Invalid combo-point acknowledgment request", 0) end
        local count = nativeCall("GetComboPoints", GetComboPoints, "player", "target")
        if not integer(count, 0, 5) then error("Target combo points are unreadable or outside zero through five", 0) end
        local code = count + ack * 6
        setCode(self.dataFrame, code)
        if not near(self.widths.data[code], readWidth(self.dataFrame)) then
            error("Combo-point data did not match its request", 0)
        end
        -- A failed or blocked data update must never advance the commit frame.
        -- The final native setter can itself change size before raising a block;
        -- in that case data was already validated, and its denial stops later
        -- attempts. Ordinary callback errors are not secure return values.
        setCode(self.commitFrame, code)
        if not near(self.widths.commit[code], readWidth(self.commitFrame)) then
            error("Combo-point acknowledgment did not match its request", 0)
        end
    end)
    if not ok then self.reason = message(err); return false, self.reason end
    self.reason = nil
    return true
end

function C:Cleanup()
    local permitted, reason = pcall(outsideCombat)
    if not permitted then self.reason = message(reason); return false, self.reason end
    self.ready = false
    local ok, err = pcall(hideOwned)
    self.reason = ok and "Combo points have not been prepared." or message(err)
    if ok then return true end
    return false, self.reason
end

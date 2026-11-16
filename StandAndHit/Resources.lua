local _, SH = ...

-- Resource percentages stay opaque. A native curve and font formatter carry
-- one predicate into owned tooltip layout; a separate commit follows validation.
local R = {ready = false, reason = "Resource conditions have not been prepared.",
    widths = {data = {}, commit = {}}, sentinelWidths = {}, curves = {}, bindings = {}}
SH.Resources = R
local POWER_TYPES = {mana = 0, rage = 1, energy = 3}
local ENCODED, SENTINEL, TOLERANCE = {[0] = 1, [1] = 1111111}, 1111111111, 0.5

R.READ_SNIPPET = [[
    self:SetAttribute("sh-resource-pass", nil)
    local index = ...
    if rawtype(index) ~= "number" or index < 1 or index > 256 or index % 1 ~= 0 then return false end
    local data = self:GetFrameRef("resource-data")
    local commit = self:GetFrameRef("resource-commit")
    if not data or not commit or data:IsShown() ~= true or commit:IsShown() ~= true then return false end
    local oldWidth, oldCode = commit:GetWidth(), -1
    if rawtype(oldWidth) ~= "number" then return false end
    for code = 0, 3 do
        local width = self:GetAttribute("sh-resource-commit-width" .. code)
        if rawtype(width) ~= "number" then return false end
        if math.abs(width - oldWidth) <= 0.5 then
            if oldCode ~= -1 then return false end
            oldCode = code
        end
    end
    if oldCode < 0 then return false end
    local phase = oldCode < 2 and 1 or 0
    self:CallMethod("RefreshResource", index, phase)
    if data:IsShown() ~= true or commit:IsShown() ~= true then return false end
    local dataWidth, commitWidth = data:GetWidth(), commit:GetWidth()
    if rawtype(dataWidth) ~= "number" or rawtype(commitWidth) ~= "number" then return false end
    local dataCode, commitCode = -1, -1
    for code = 0, 3 do
        local expectedData = self:GetAttribute("sh-resource-data-width" .. code)
        local expectedCommit = self:GetAttribute("sh-resource-commit-width" .. code)
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
    if not ((phase == 0 and commitCode < 2) or (phase == 1 and commitCode >= 2)) then return false end
    self:SetAttribute("sh-resource-pass", commitCode % 2 == 1)
    return true
]]

local function secret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, result = pcall(issecretvalue, value)
    return not ok or type(result) ~= "boolean" or result
end
local function number(value)
    return not secret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function integer(value, low, high)
    return number(value) and value >= low and value <= high and value % 1 == 0
end
local function message(value)
    if secret(value) or type(value) ~= "string" then return "Resource signal is unavailable" end
    return value:gsub("[\r\n\t]", " "):sub(1, 300)
end
local function combat()
    if type(InCombatLockdown) ~= "function" then error("Combat state is unavailable", 0) end
    local value = InCombatLockdown()
    if secret(value) or type(value) ~= "boolean" then error("Combat state is unreadable", 0) end
    return value
end
local function outside()
    if combat() then error("Prepare resource conditions outside combat", 0) end
end
local function nativeCall(name, fn, ...)
    if secret(fn) or type(fn) ~= "function" then error(name .. " is unavailable", 0) end
    local label = "Resources: " .. name
    if SH.blockedNativeCalls and SH.blockedNativeCalls[label] and combat() then
        error("Client blocked " .. label .. "; resource conditions are unavailable in combat this session", 0)
    end
    -- Return opaque values without comparing, formatting, or copying them.
    if SH.CallNativeDiagnostic then return SH:CallNativeDiagnostic(label, fn, ...) end
    return fn(...)
end
local function required(object, name, ...)
    if secret(object) or object == nil then error(name .. " is unavailable", 0) end
    local result = nativeCall("Frame:" .. name, object[name], object, ...)
    if secret(result) then error(name .. " returned an unreadable result", 0) end
    return result
end
local function near(a, b)
    return number(a) and number(b) and math.abs(a - b) <= TOLERANCE
end
local function readWidth(frame)
    if required(frame, "IsShown") ~= true then error("Resource signal is hidden", 0) end
    local value = required(frame, "GetWidth")
    if not number(value) or value <= 0 then error("Resource width is unreadable", 0) end
    return value
end
local function decode(value, widths)
    if not number(value) then return -1 end
    local result = -1
    for code = 0, 3 do
        if near(value, widths[code]) then
            if result ~= -1 then return -1 end
            result = code
        end
    end
    return result
end
local function setData(encoded, phase)
    -- encoded may be secret; only the native formatter consumes it.
    required(R.dataLeft, "SetFormattedText", "%d", encoded)
    required(R.dataFrame, "SetPadding", 16 + phase * 192, 0, 0, 0)
end
local function setCode(kind, code)
    if kind == "data" then setData(ENCODED[code % 2], math.floor(code / 2))
    else required(R.commitFrame, "SetPadding", 16 + code * 32, 0, 0, 0) end
end
local function hideOwned()
    outside()
    if R.dataFrame then required(R.dataFrame, "Hide") end
    if R.commitFrame then required(R.commitFrame, "Hide") end
end
local function restoreTooltip(frame)
    outside()
    -- Restore content as well as visibility after native tooltip cleanup.
    -- Calibration below still checks the widths held by attached buttons.
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
    outside()
    local name = "StandAndHitResource" .. (kind == "data" and "Data" or "Commit")
    local frame = nativeCall("CreateFrame", CreateFrame, "GameTooltip", name, UIParent, "SecureFrameTemplate")
    R[kind .. "Frame"], R[kind .. "Initialized"] = frame, false
    local left = required(frame, "CreateFontString", name .. "TextLeft1", "ARTWORK", "GameTooltipText")
    local right = required(frame, "CreateFontString", name .. "TextRight1", "ARTWORK", "GameTooltipText")
    required(left, "SetAlpha", 0)
    required(right, "SetAlpha", 0)
    R[kind .. "Left"] = left
    required(frame, "AddFontStrings", left, right)
    restoreTooltip(frame)
    if required(frame, "IsProtected") ~= true then error("Resource signal is not protected", 0) end
    R[kind .. "Initialized"] = true
end
local function calibrate(kind)
    local frame, widths = R[kind .. "Frame"], R.widths[kind]
    for code = 0, 3 do
        outside()
        setCode(kind, code)
        local value = readWidth(frame)
        if R.calibrated then
            if not near(value, widths[code]) then
                error(string.format("Resource layout changed (%s %d: expected %.2f, got %.2f). Reload before preparing again.",
                    kind, code, widths[code], value), 0)
            end
        else widths[code] = value end
        for earlier = 0, code - 1 do
            if math.abs(widths[earlier] - value) <= 2 * TOLERANCE then
                error("Resource signal cannot distinguish the conditions", 0)
            end
        end
    end
    for code = 2, 0, -1 do
        outside()
        setCode(kind, code)
        if not near(readWidth(frame), widths[code]) then error("Resource signal did not return to its earlier value", 0) end
    end
end
local function calibrateSentinels()
    for phase = 0, 1 do
        setData(SENTINEL, phase)
        local value = readWidth(R.dataFrame)
        if R.calibrated and not near(value, R.sentinelWidths[phase]) then
            error("Resource reset layout changed. Reload before preparing again.", 0)
        end
        for code = 0, 3 do
            if math.abs(value - R.widths.data[code]) <= 2 * TOLERANCE then
                error("Resource reset cannot be distinguished from a condition", 0)
            end
        end
        R.sentinelWidths[phase] = value
    end
    setCode("data", 0)
    if not near(readWidth(R.dataFrame), R.widths.data[0]) then error("Resource reset did not return to its earlier value", 0) end
end
local function validRequest(request)
    if secret(request) or type(request) ~= "table" then error("Resource condition is invalid", 0) end
    if secret(request.resource) or type(request.resource) ~= "string" or not POWER_TYPES[request.resource] then
        error("Choose mana, rage, or energy", 0)
    end
    if secret(request.operator) or (request.operator ~= "lt" and request.operator ~= "ge") then
        error("Choose below (<) or at least (>=) for a resource condition", 0)
    end
    if not integer(request.percent, 0, 100) then error("Resource percentage must be a whole number from 0 to 100", 0) end
end
local function requestKey(request) return request.operator .. request.percent end
local function makeCurve(request)
    outside()
    local key = requestKey(request)
    if R.curves[key] then return R.curves[key] end
    if type(C_CurveUtil) ~= "table" or type(C_CurveUtil.CreateCurve) ~= "function" or
        type(Enum) ~= "table" or type(Enum.LuaCurveType) ~= "table" or not number(Enum.LuaCurveType.Step) then
        error("Native resource percentage curves are unavailable", 0)
    end
    local curve = nativeCall("C_CurveUtil.CreateCurve", C_CurveUtil.CreateCurve)
    required(curve, "SetType", Enum.LuaCurveType.Step)
    local threshold = request.percent / 100
    local low = request.operator == "lt" and ENCODED[1] or ENCODED[0]
    local high = request.operator == "lt" and ENCODED[0] or ENCODED[1]
    required(curve, "AddPoint", 0, threshold == 0 and high or low)
    if threshold > 0 then required(curve, "AddPoint", threshold, high) end
    if threshold < 1 then required(curve, "AddPoint", 1, high) end
    for _, input in ipairs({0, math.max(0, threshold - 0.0000001), threshold, math.min(1, threshold + 0.0000001), 1}) do
        local expected = input < threshold and low or high
        local value = required(curve, "Evaluate", input)
        if not number(value) or value ~= expected then error("Native resource curve did not match its percentage boundary", 0) end
    end
    -- At most 202 curves exist: two operators and 101 whole percentages.
    R.curves[key] = curve
    return curve
end
local function validateRequests(requests)
    if secret(requests) or type(requests) ~= "table" or #requests > 256 then error("Resource conditions are invalid", 0) end
    for _, request in ipairs(requests) do validRequest(request) end
end

function R:Prepare(requests)
    local permitted, reason = pcall(outside)
    if not permitted then self.reason = message(reason); return false, self.reason end
    local touched = false
    local ok, err = pcall(function()
        validateRequests(requests)
        if type(issecretvalue) ~= "function" or type(UnitPowerMax) ~= "function" or type(UnitPowerPercent) ~= "function" then
            error("Native player resource percentages are unavailable", 0)
        end
        if type(SecureHandlerSetFrameRef) ~= "function" then error("Secure frame references are unavailable", 0) end
        for _, request in ipairs(requests) do makeCurve(request) end
        if (self.dataFrame and not self.dataInitialized) or (self.commitFrame and not self.commitInitialized) then
            error("Resource setup was incomplete. Reload before preparing again.", 0)
        end
        touched, self.ready = true, false
        for _, kind in ipairs({"data", "commit"}) do
            local frame = self[kind .. "Frame"]
            if not frame then createTooltip(kind)
            elseif required(frame, "IsShown") ~= true then restoreTooltip(frame)
            else required(frame, "SetAlpha", 0) end
            calibrate(kind)
        end
        calibrateSentinels()
        self.calibrated = true
        if not self.lifecycle then
            self.lifecycle = nativeCall("CreateFrame", CreateFrame, "Frame")
            required(self.lifecycle, "RegisterEvent", "PLAYER_LOGOUT")
            required(self.lifecycle, "SetScript", "OnEvent", function() R:Cleanup() end)
        end
    end)
    if not ok then
        self.reason = message(err)
        if touched then pcall(hideOwned) end
        return false, self.reason
    end
    self.ready, self.reason = true, nil
    return true
end
function R:Attach(button, requests)
    local ok, err = pcall(function()
        outside()
        if not self.ready then error(self.reason or "Resource conditions have not been prepared", 0) end
        validateRequests(requests)
        local binding = {}
        for index, request in ipairs(requests) do
            local curve = self.curves[requestKey(request)]
            if not curve then error("Resource percentage was not prepared", 0) end
            binding[index] = {powerType = POWER_TYPES[request.resource], curve = curve}
        end
        nativeCall("SecureHandlerSetFrameRef", SecureHandlerSetFrameRef, button, "resource-data", self.dataFrame)
        nativeCall("SecureHandlerSetFrameRef", SecureHandlerSetFrameRef, button, "resource-commit", self.commitFrame)
        for code = 0, 3 do
            required(button, "SetAttribute", "sh-resource-data-width" .. code, self.widths.data[code])
            required(button, "SetAttribute", "sh-resource-commit-width" .. code, self.widths.commit[code])
        end
        self.bindings[button] = binding
    end)
    if not ok then self.reason = message(err); return false, self.reason end
    self.reason = nil
    return true
end
function R:Refresh(button, index, phase)
    local ok, err = pcall(function()
        if not self.ready then error(self.reason or "Resource conditions have not been prepared", 0) end
        if not integer(index, 1, 256) or not integer(phase, 0, 1) then error("Invalid resource read request", 0) end
        local binding = self.bindings[button]
        local request = binding and binding[index]
        if not request then error("Resource condition is not attached", 0) end
        local maximum = nativeCall("UnitPowerMax", UnitPowerMax, "player", request.powerType, false)
        if not number(maximum) or maximum < 0 then error("Resource maximum is unreadable or invalid", 0) end
        local encoded = ENCODED[0]
        -- A resource absent from this form cannot satisfy either comparison.
        if maximum > 0 then encoded = nativeCall("UnitPowerPercent", UnitPowerPercent, "player", request.powerType, false, request.curve) end
        -- Clear the previous predicate to a separately verified, invalid width.
        -- A formatter that silently ignores the new opaque value must not turn
        -- yesterday's predicate into a fresh response by changing padding alone.
        setData(SENTINEL, phase)
        if not near(readWidth(self.dataFrame), self.sentinelWidths[phase]) then error("Resource data did not reset before its update", 0) end
        setData(encoded, phase)
        local code = decode(readWidth(self.dataFrame), self.widths.data)
        if code < 0 or math.floor(code / 2) ~= phase then error("Resource data was stale or did not match its request", 0) end
        -- Do not advance the acknowledgment until the full data update validates.
        setCode("commit", code)
        if not near(readWidth(self.commitFrame), self.widths.commit[code]) then error("Resource acknowledgment did not match its request", 0) end
    end)
    if not ok then self.reason = message(err); return false, self.reason end
    self.reason = nil
    return true
end
function R:Cleanup()
    local permitted, reason = pcall(outside)
    if not permitted then self.reason = message(reason); return false, self.reason end
    self.ready = false
    local ok, err = pcall(hideOwned)
    self.reason = ok and "Resource conditions have not been prepared." or message(err)
    if ok then return true end
    return false, self.reason
end

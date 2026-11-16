local _, SH = ...

-- Both totem readers encode their native result as exactly one of two
-- numbers. The native formatter can accept the value even in combat.
local Signal = {}
SH.TotemSignal = Signal
local EMPTY, FULL, RESET = 1, 111, 111111
-- GetWidth may return e.g. 0.99994 after pixel scaling. Format geometry
-- as whole UI units.
-- Keep both labels wider than the tooltip's native minimum content width.
local prefix = string.rep("0", 24)
local geometry = {format = prefix .. "%.0f", active = FULL}
-- Use exact color endpoints for booleans. A fractional color component can
-- format differently from its calibration literal after native conversion.
-- Zero at precision zero has no digit, so fixed-width digits stay distinct.
local duration = {format = prefix .. "[%.0d]", empty = 0, active = 1}
-- Zero prints no digit at precision zero. This distinguishes a settled
-- layout even when all the font's digits are the same width.
local layoutMode = {format = prefix .. "[%.0d]", empty = 0, active = 2}
local users = {}
local comparisonUsers = {}
local frame, text

local function near(a, b)
    return math.abs(a - b) < 0.25
end

local function measure(codec, value, padding)
    text:SetFormattedText(codec.format, value)
    frame:SetPadding(padding, 0, 0, 0)
    local width = frame:GetWidth()
    if not issecretvalue(width) and type(width) == "number" and width > 0 then return width end
    error("Unreadable totem display")
end

local function prepareTooltip()
    local name = "StandAndHitTotemSignal"
    if not frame then frame = CreateFrame("GameTooltip", name, UIParent) end
    if not text then
        local left = frame:CreateFontString(name .. "TextLeft1", "ARTWORK", "GameTooltipText")
        local right = frame:CreateFontString(name .. "TextRight1", "ARTWORK", "GameTooltipText")
        left:SetAlpha(0)
        right:SetAlpha(0)
        frame:AddFontStrings(left, right)
        text = left
    end
    -- Keep native layout running even when a tooltip skin resets frame alpha.
    frame:SetAlpha(0)
    frame:SetOwner(UIParent, "ANCHOR_NONE")
    frame:SetClampedToScreen(false)
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -256, -256)
    frame:SetPadding(0, 0, 0, 0)
    frame:SetText("0", 1, 1, 1, 0, false)
    frame:Show()
    frame:SetAlpha(0)
end

local function calibrate(codec)
    -- Check both paddings so that a formatter which silently ignored the
    -- request cannot appear to succeed just because SetPadding did succeed.
    local function sample(value, padding)
        -- The client may skip a layout pass when padding did not change.
        frame:SetPadding(0, 0, 0, 0)
        return measure(codec, value, padding)
    end
    local emptyCode = codec.empty or EMPTY
    local empty = sample(emptyCode, 16)
    local active = sample(codec.active, 16)
    local reset = sample(RESET, 32)
    for _, value in ipairs({RESET, 20}) do
        local data = sample(value, 16)
        if near(data, empty) or near(data, active) then
            error("Invalid totem display width")
        end
    end
    if near(empty, active) then error("Indistinguishable totem states") end
    for _, value in ipairs({emptyCode, codec.active, 20}) do
        if near(reset, sample(value, 32)) then error("Indistinguishable totem reset") end
    end
    if codec == layoutMode then
        codec.resetAtDataPadding = sample(RESET, 16)
        local pending = {}
        for mode = 1, 4 do
            pending[mode] = sample(mode, 16)
            if math.abs(pending[mode] - empty) <= 0.5 then error("Indistinguishable aura update modes") end
        end
        codec.pendingWidths = pending
    end
    if not near(reset, sample(RESET, 32)) or not near(empty, measure(codec, emptyCode, 16)) then
        error("Unstable totem display")
    end
    codec.emptyWidth, codec.activeWidth, codec.resetWidth = empty, active, reset
end

function Signal:Acquire(owner, capability)
    if not owner or InCombatLockdown() then return false end
    local requested = (capability == "aura" or capability == "width") and geometry or capability == "cooldown" and duration
    if not next(users) or not frame or not frame:IsVisible() then
        local restoreMode = next(users) and layoutMode.ready
        geometry.ready, duration.ready, layoutMode.ready = false, false, false
        if not pcall(prepareTooltip) then
            if frame then pcall(frame.Hide, frame) end
            return false
        end
        geometry.ready = pcall(calibrate, geometry)
        duration.ready = pcall(calibrate, duration)
        if restoreMode then layoutMode.ready = pcall(calibrate, layoutMode) end
    elseif requested and not requested.ready then
        requested.ready = pcall(calibrate, requested)
    end
    local available = geometry.ready or duration.ready
    if requested then available = requested.ready end
    if capability == "aura" or capability == "comparison" then
        if not layoutMode.ready then layoutMode.ready = pcall(calibrate, layoutMode) end
        available = layoutMode.ready or (capability == "aura" and geometry.ready)
    end
    if not available then
        if not next(users) and frame then pcall(frame.Hide, frame) end
        return false
    end
    users[owner] = true
    if capability == "comparison" then comparisonUsers[owner] = true end
    if capability == "aura" then return geometry.ready, layoutMode.ready end
    return true
end

local function read(codec, encoded)
    if not codec.ready or not frame:IsVisible() then return nil end
    if not issecretvalue(encoded) then
        if type(encoded) ~= "number" or not (near(encoded, codec.empty or EMPTY) or near(encoded, codec.active)) then return nil end
    end
    if not near(measure(codec, RESET, 32), codec.resetWidth) then return nil end
    local width = measure(codec, encoded, 16)
    if near(width, codec.emptyWidth) then return false end
    if near(width, codec.activeWidth) then return true end
    if codec.pendingWidths then
        for _, pendingWidth in ipairs(codec.pendingWidths) do
            if near(width, pendingWidth) then return true end
        end
    end
end

local function compareInteger(result)
    if not layoutMode.ready or not frame:IsVisible() then return nil end
    if not near(measure(layoutMode, RESET, 32), layoutMode.resetWidth) then return nil end
    local width = measure(layoutMode, result, 16)
    if near(width, layoutMode.emptyWidth) then return true end
    -- A dropped data update leaves the reset value at either padding. An
    -- actual integer with the same width is inconclusive as well.
    if width > layoutMode.emptyWidth + 0.5 and not near(width, layoutMode.resetAtDataPadding)
        and not near(width, layoutMode.resetWidth) then return false end
end

function Signal:IsComparisonEqual(result)
    if not issecretvalue(result) then
        if type(result) == "number" then return result == 0 end
    elseif next(comparisonUsers) then
        local ok, equal = pcall(compareInteger, result)
        if ok then return equal end
    end
end

function Signal:Read(groupWidth)
    if not next(users) then return nil end
    local ok, result = pcall(read, geometry, groupWidth)
    if ok then return result end
end

function Signal:IsLayoutSettled(mode)
    if not issecretvalue(mode) then
        if type(mode) == "number" and mode >= 0 and mode <= 4 and mode % 1 == 0 then
            return mode == Enum.OnUpdateMode.Disabled
        end
        return nil
    end
    if not next(users) then return nil end
    local ok, pending = pcall(read, layoutMode, mode)
    if ok and pending ~= nil then return not pending end
end

local function readBoolean(value)
    local encoded = C_CurveUtil.EvaluateColorValueFromBoolean(value, 1, 0)
    return read(duration, encoded)
end

function Signal:ReadBoolean(value)
    if not issecretvalue(value) then
        if type(value) == "boolean" then return value end
    elseif next(users) then
        local ok, result = pcall(readBoolean, value)
        if ok then return result end
    end
end

function Signal:Release(owner)
    if InCombatLockdown() or not users[owner] then return end
    users[owner] = nil
    comparisonUsers[owner] = nil
    if not next(users) and frame then pcall(frame.Hide, frame) end
end

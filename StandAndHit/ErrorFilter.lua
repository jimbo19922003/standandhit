local _, SH = ...
local Filter = {WINDOW_SECONDS = 0.20}
SH.ErrorFilter = Filter

-- UI_ERROR_MESSAGE supplies an error type and text, but no spell or owner.
-- This short window can therefore also hide a nearby, unrelated cast error.
-- Keep the list explicit: learning, inventory, quest and system messages pass.
local castErrorNames = {
    "OUT_OF_MANA", "OUT_OF_ENERGY", "OUT_OF_RAGE", "OUT_OF_FOCUS",
    "OUT_OF_COMBO_POINTS", "OUT_OF_RUNES", "OUT_OF_RUNIC_POWER",
    "OUT_OF_HOLY_POWER", "OUT_OF_SOUL_SHARDS", "OUT_OF_CHI", "OUT_OF_PAIN",
    "OUT_OF_HEALTH", "OUT_OF_ARCANE_CHARGES", "OUT_OF_LUNAR_POWER",
    "OUT_OF_INSANITY", "OUT_OF_FURY", "OUT_OF_MAELSTROM", "OUT_OF_ESSENCE",
    "OUT_OF_POWER_DISPLAY", "OUT_OF_RANGE", "SPELL_OUT_OF_RANGE",
    "ABILITY_COOLDOWN", "SPELL_COOLDOWN", "GENERIC_NO_VALID_TARGETS",
    "SPELL_FAILED_S", "SPELL_FAILED_ANOTHER_IN_PROGRESS",
    "SPELL_FAILED_TOTEMS", "SPELL_FAILED_REAGENTS", "SPELL_FAILED_REAGENTS_GENERIC",
    "SPELL_FAILED_EQUIPPED_ITEM", "SPELL_FAILED_EQUIPPED_SPECIFIC_ITEM",
    "SPELL_FAILED_EQUIPPED_ITEM_CLASS_S", "SPELL_FAILED_NOTUNSHEATHED",
    "SPELL_FAILED_SHAPESHIFT_FORM_S", "SPELL_FAILED_ALREADY_AT_FULL_MANA",
    "SPELL_FAILED_ALREADY_AT_FULL_POWER_S", "SPELL_FAILED_ALREADY_AT_FULL_HEALTH",
    "SPELL_FAILED_CANT_FLY_HERE",
}

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function timeNow()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    if ok and readable(value) and type(value) == "number" and
        value == value and value > -math.huge and value < math.huge then return value end
end

function Filter:ShouldHide(messageType)
    if not readable(messageType) or type(messageType) ~= "number" or
        not self.castErrors or not self.castErrors[messageType] then return false end
    local rotation = self.rotation
    if not rotation or not rotation.db or rotation.db.hideUIErrors ~= true or
        not rotation:IsEnabled() then return false end
    local now = timeNow()
    return now ~= nil and self.started ~= nil and now >= self.started and now < self.cutoff
end

function Filter:NoteAttempt(rotation)
    -- An unfiltered rotation must not inherit another button's recent window.
    self.rotation, self.started, self.cutoff = nil, nil, nil
    if not self.installed and not InCombatLockdown() then self:Install() end
    if not self.installed or not rotation or not rotation.db or
        rotation.db.hideUIErrors ~= true or not rotation:IsEnabled() then return end
    local now = timeNow()
    if now then
        self.rotation, self.started, self.cutoff = rotation, now, now + self.WINDOW_SECONDS
    end
end

function Filter:Install()
    if self.installed then return true end
    if InCombatLockdown() then return false end
    local frame = UIErrorsFrame
    if not frame or type(frame.GetScript) ~= "function" or type(frame.SetScript) ~= "function" or
        type(frame.ShouldDisplayMessageType) ~= "function" then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    if frame.IsProtected and frame:IsProtected() then return false end
    local originalEvent = frame:GetScript("OnEvent")
    if type(originalEvent) ~= "function" then return false end
    self.castErrors = {}
    for _, name in ipairs(castErrorNames) do
        local id = _G["LE_GAME_ERR_" .. name]
        if readable(id) and type(id) == "number" then self.castErrors[id] = true end
    end

    -- Native TryDisplayMessage uses this gate for both text and its vocal/error
    -- sound. Keep it scoped to the matching error event, not info/system events
    -- or direct calls, and leave global sound settings and APIs untouched.
    local originalShouldDisplay = frame.ShouldDisplayMessageType
    local context
    frame.ShouldDisplayMessageType = function(owner, messageType, ...)
        if context ~= nil and readable(messageType) and messageType == context then return false end
        return originalShouldDisplay(owner, messageType, ...)
    end
    frame:SetScript("OnEvent", function(owner, event, messageType, ...)
        local previous = context
        context = event == "UI_ERROR_MESSAGE" and self:ShouldHide(messageType) and messageType or nil
        local ok, result = pcall(originalEvent, owner, event, messageType, ...)
        context = previous
        if not ok then error(result, 0) end
        return result
    end)
    -- Existing text is not cleared; suppressed repeats neither flash nor
    -- restart its fade. Unfiltered errors retain native throttling and audio.
    self.installed = true
    return true
end

local _, SH = ...

local modifierOrder = {"ALT", "CTRL", "SHIFT"}
local emulationCVars = {
    {"GamePadEmulateAlt", "Alt"}, {"GamePadEmulateCtrl", "Ctrl"},
    {"GamePadEmulateShift", "Shift"}, {"GamePadEmulateEsc", "Escape"},
}

local function normalizeKey(key)
    if type(key) ~= "string" then return nil end
    key = key:match("^%s*(.-)%s*$"):upper()
    if #key > 80 then return nil end
    local modifiers, rest = {}, key
    while rest:find("-", 1, true) do
        local modifier, tail = rest:match("^([A-Z]+)%-(.+)$")
        if not modifier or (modifier ~= "ALT" and modifier ~= "CTRL" and modifier ~= "SHIFT") or
            modifiers[modifier] then return nil end
        modifiers[modifier], rest = true, tail
    end
    if not rest:match("^PAD[A-Z0-9]+$") then return nil end
    local prefix = ""
    for _, modifier in ipairs(modifierOrder) do
        if modifiers[modifier] then prefix = prefix .. modifier .. "-" end
    end
    return prefix .. rest, rest
end

function SH:GamePadKeysEqual(first, second)
    local normalized = normalizeKey(first)
    return normalized ~= nil and normalized == normalizeKey(second)
end

local function readPublic(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

local function checkPhysicalButton(base)
    local index = readPublic(C_GamePad and C_GamePad.ButtonBindingToIndex, base)
    if type(index) ~= "number" or index < 0 or index ~= math.floor(index) then
        return false, "The client does not recognize that controller button. Choose another button."
    end
    local getter = C_CVar and C_CVar.GetCVar or GetCVar
    for _, setting in ipairs(emulationCVars) do
        local value = readPublic(getter, setting[1])
        if type(value) ~= "string" then
            return false, "The controller's " .. setting[2] .. " setting could not be checked. Try again outside combat."
        end
        if value:upper() == base then
            return false, base .. " is configured to act as " .. setting[2] ..
                ". Choose another button or change that assignment in your controller settings."
        end
    end
    return true
end

local function checkBinding(rotation, key)
    for _, other in ipairs(SH.rotations or {SH}) do
        if other:IsEnabled() then
            if other ~= rotation and (rotation:GamePadKeysEqual(key, other.boundGamePadKey) or
                rotation:GamePadKeysEqual(key, other.db.gamePadKey)) then
                return false, key .. " is already assigned to " .. other.label .. ". Choose a different button."
            end
            if rotation:GamePadKeysEqual(key, other.boundKey) or rotation:GamePadKeysEqual(key, other.db.directKey)
                or (other.boundDirectKeys and other.boundDirectKeys[key]) then
                return false, key .. " is already the cast key for " .. other.label ..
                    ". Clear that cast key first or choose a different controller button."
            end
        end
    end
    -- Ordinary bindings remain underneath this temporary override. A different
    -- addon's override is ambiguous, so do not silently compete for its button.
    local ordinary = readPublic(GetBindingAction, key, false)
    local active = readPublic(GetBindingAction, key, true)
    if type(ordinary) ~= "string" or type(active) ~= "string" then
        return false, "The controller button's current binding could not be checked. Try another button."
    end
    local ownAction = "CLICK " .. rotation.directButtonName .. ":LeftButton"
    if active ~= ordinary and not (rotation.boundGamePadKey == key and active == ownAction) then
        return false, key .. " is controlled by another binding override. Clear that assignment or choose a different button."
    end
    return true
end

local function cursorHint(base)
    local getter = C_CVar and C_CVar.GetCVar or GetCVar
    local left = readPublic(getter, "GamePadCursorLeftClick")
    local right = readPublic(getter, "GamePadCursorRightClick")
    if (type(left) == "string" and left:upper() == base) or
        (type(right) == "string" and right:upper() == base) then
        return " In cursor mode, the game may use this button for mouse clicks."
    end
    return ""
end

function SH:SetGamePadKey(key)
    if InCombatLockdown() then return false, "Leave combat before changing controller buttons." end
    if not self:IsEnabled() then return false, "Enable " .. self.label .. " first." end
    if not SH.Controller then return false, "Controller support is not available." end
    local available, reason = SH.Controller:IsAvailable()
    if not available then return false, reason or "Enable controller support first." end
    local normalized, base = normalizeKey(key)
    if not normalized then return false, "Choose a controller button, with optional Alt, Ctrl, or Shift." end
    local ok, message = checkPhysicalButton(base)
    if not ok then return false, message end
    ok, message = checkBinding(self, normalized)
    if not ok then return false, message end
    if not self:CreateDirectButton() then return false, "The casting button is not available." end

    -- Stage on a second reusable owner. A failed new binding never removes the
    -- old working one, and repeated assignments allocate at most two owners.
    local candidate = self.gamePadStagingOwner or CreateFrame("Frame")
    self.gamePadStagingOwner = candidate
    ClearOverrideBindings(candidate)
    local bound, result = pcall(SetOverrideBindingClick, candidate, true, normalized, self.directButtonName, "LeftButton")
    if not bound or result == false then
        ClearOverrideBindings(candidate)
        return false, "That controller button could not be assigned. Your previous assignment is unchanged."
    end
    local previous = self.gamePadBindingOwner
    if previous then ClearOverrideBindings(previous) end
    self.gamePadBindingOwner, self.gamePadStagingOwner = candidate, previous
    self.db.gamePadKey, self.boundGamePadKey = normalized, normalized
    self.controllerBindingError = nil
    if self.UpdatePreparedAccessHint then self:UpdatePreparedAccessHint() end
    self:NotifyUI()
    return true, self.label .. ": " .. normalized .. ". Press and release to cast. Clear restores its normal binding." .. cursorHint(base)
end

function SH:ReleaseGamePadKey()
    if InCombatLockdown() then return false, "Leave combat before changing controller buttons." end
    if self.gamePadBindingOwner then ClearOverrideBindings(self.gamePadBindingOwner) end
    if self.gamePadStagingOwner then ClearOverrideBindings(self.gamePadStagingOwner) end
    self.boundGamePadKey = nil
    if self.UpdatePreparedAccessHint then self:UpdatePreparedAccessHint() end
    return true
end

function SH:ClearGamePadKey()
    local ok, message = self:ReleaseGamePadKey()
    if not ok then return false, message end
    self.db.gamePadKey = nil
    self.controllerBindingError = nil
    self:NotifyUI()
    return true, "Controller button cleared. Its normal binding is available again."
end

function SH:RestoreGamePadKey()
    if InCombatLockdown() then return end
    local available = SH.Controller and SH.Controller:IsAvailable()
    if not self:IsEnabled() or not available or not self.db.gamePadKey then
        self:ReleaseGamePadKey()
        return
    end
    local ok, message = self:SetGamePadKey(self.db.gamePadKey)
    if not ok then
        self:ReleaseGamePadKey()
        self.controllerBindingError = message
    else
        self.controllerBindingError = nil
    end
end

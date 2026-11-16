local addonName, SH = ...
local Controller = {}
SH.Controller = Controller

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function finite(value)
    return readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function refresh()
    if SH.RefreshControllerUI then SH:RefreshControllerUI() end
end

function Controller:GetSettings()
    if not SH.db then SH:Initialize() end
    if not self.settings then
        if type(SH.db.controller) ~= "table" then SH.db.controller = {} end
        local settings = SH.db.controller
        settings.combatRumble = settings.combatRumble == true
        settings.critRumble = settings.critRumble == true
        -- Retire the incoming-damage option without opting into a new alert.
        settings.damageRumble, settings.damagePercent = nil, nil
        self.settings = settings
    end
    return self.settings
end

function Controller:IsEnabled()
    if not C_GamePad or type(C_GamePad.IsEnabled) ~= "function" then return false end
    local ok, enabled = pcall(C_GamePad.IsEnabled)
    return ok and readable(enabled) and enabled == true
end

function Controller:IsAvailable()
    if not C_GamePad or type(C_GamePad.IsEnabled) ~= "function" then
        return false, "This game client does not provide controller support."
    end
    if not self:IsEnabled() then return false, "Enable controller input to assign buttons." end
    if type(C_GamePad.GetAllDeviceIDs) == "function" then
        local ok, ids = pcall(C_GamePad.GetAllDeviceIDs)
        if ok and readable(ids) and type(ids) == "table" and next(ids) == nil then
            return false, "No controller detected. Connect it, then press a gamepad button."
        end
    end
    return true, "Controller input is enabled. Assign a gamepad button to each rotation you use."
end

function Controller:RefreshBindings()
    if InCombatLockdown() then return end
    for _, rotation in ipairs(SH.rotations or {}) do
        if self:IsEnabled() then
            if rotation.RestoreGamePadKey then rotation:RestoreGamePadKey() end
        elseif rotation.ReleaseGamePadKey then
            rotation:ReleaseGamePadKey()
        end
    end
end

function Controller:SetEnabled(enabled)
    if InCombatLockdown() then return false, "Leave combat before changing controller input." end
    if not C_GamePad or type(C_GamePad.IsEnabled) ~= "function" then
        return false, "This game client does not provide controller support."
    end
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    if type(setter) ~= "function" then return false, "Controller input could not be changed." end
    local ok, result = pcall(setter, "GamePadEnable", enabled and "1" or "0")
    if not ok or result == false or self:IsEnabled() ~= (enabled == true) then
        return false, "Controller input could not be changed. Check the game's controller settings."
    end
    if not enabled then self:StopRumble() end
    self:RefreshBindings()
    refresh()
    return true, enabled and "Controller input enabled." or "Controller input disabled; assignments are saved."
end

function Controller:GetButtonLabel(key)
    if type(key) ~= "string" or key == "" then return "Not assigned" end
    if type(GetBindingText) == "function" then
        local ok, label = pcall(GetBindingText, key, "KEY_")
        if ok and readable(label) and type(label) == "string" and label ~= "" then return label end
    end
    return key
end

function Controller:GetCritStatus()
    return self.critStatus
end

function Controller:SetCritStatus(message)
    if self.critStatus == message then return end
    self.critStatus = message
    refresh()
end

function Controller:StopRumble()
    self.rumbleGeneration = (self.rumbleGeneration or 0) + 1
    if self.rumbleTimer then self.rumbleTimer:Cancel(); self.rumbleTimer = nil end
    if self.rumbleActive and C_GamePad and type(C_GamePad.StopVibration) == "function" then
        local ok = pcall(C_GamePad.StopVibration)
        if not ok then return false, "The game could not stop controller rumble." end
    end
    self.rumbleActive = nil
    return true
end

function Controller:PulseRumble(duration)
    local available, reason = self:IsAvailable()
    if not available then return false, reason end
    if not (C_GamePad and type(C_GamePad.SetVibration) == "function"
        and type(C_GamePad.StopVibration) == "function" and C_Timer
        and type(C_Timer.NewTimer) == "function") then
        return false, "Controller rumble is unavailable in this game client."
    end
    local stopped, stopReason = self:StopRumble()
    if not stopped then return false, stopReason end
    local generation = self.rumbleGeneration
    self.rumbleActive = true
    local lowOK = pcall(C_GamePad.SetVibration, "Low", 0.5)
    local highOK = pcall(C_GamePad.SetVibration, "High", 0.5)
    if not lowOK or not highOK then
        self:StopRumble()
        return false, "The game could not start controller rumble."
    end
    local ok, timer = pcall(C_Timer.NewTimer, duration, function()
        if Controller.rumbleGeneration == generation then Controller:StopRumble() end
    end)
    if not ok or not timer then
        self:StopRumble()
        return false, "The rumble stop timer could not be started."
    end
    self.rumbleTimer = timer
    return true
end

function Controller:TestRumble()
    local ok, reason = self:PulseRumble(0.3)
    return ok, reason or "Rumble test sent. Your controller must support vibration."
end

local CRIT_UNAVAILABLE = "Rumble on crit is unavailable: this client does not expose your critical-damage events."
local CRIT_HIDDEN = "Rumble on crit is unavailable while the game restricts combat-log details."

local function combatLogReader()
    if C_CombatLog and type(C_CombatLog.GetCurrentEventInfo) == "function" then
        return C_CombatLog.GetCurrentEventInfo
    end
    if type(CombatLogGetCurrentEventInfo) == "function" then return CombatLogGetCurrentEventInfo end
end

local function combatLogReadable()
    if C_CombatLog and type(C_CombatLog.IsCombatLogRestricted) == "function" then
        local ok, restricted = pcall(C_CombatLog.IsCombatLogRestricted)
        if not ok or not readable(restricted) or restricted ~= false then return false end
    end
    return true
end

function Controller:UpdateCritEvents()
    if not self.events then return end
    if not self:GetSettings().critRumble then
        self:SetCritStatus(nil)
        -- Restricted clients can reject even an unregister for an event that
        -- was never subscribed. Only release a subscription we established.
        if not self.critEventsRegistered then self.critEventsUpdatePending = nil; return end
        if InCombatLockdown() or not combatLogReadable() then
            self.critEventsUpdatePending = true
            return
        end
        local ok, result = pcall(self.events.UnregisterEvent, self.events, "COMBAT_LOG_EVENT_UNFILTERED")
        if ok and result ~= false then self.critEventsRegistered = nil end
        self.critEventsUpdatePending = self.critEventsRegistered and true or nil
        return
    end
    if not combatLogReader() or type(UnitGUID) ~= "function" then
        self:SetCritStatus(CRIT_UNAVAILABLE)
        return
    end
    if not combatLogReadable() then self:SetCritStatus(CRIT_HIDDEN); return end
    -- Keep an accepted subscription across combat transitions. The event
    -- handler checks the option and current readability before reading data.
    if self.critEventsRegistered then
        self.critEventsUpdatePending = nil
        self:SetCritStatus(nil)
        return
    end
    if InCombatLockdown() then self.critEventsUpdatePending = true; return end
    self.critEventsUpdatePending = nil
    local ok, result = pcall(self.events.RegisterEvent, self.events, "COMBAT_LOG_EVENT_UNFILTERED")
    if not ok or not readable(result) or (result ~= nil and result ~= true) then
        self:SetCritStatus(CRIT_UNAVAILABLE)
        return
    end
    -- A protected call can return nil without raising a Lua error. Confirm
    -- the subscription before later attempting to unregister it. If this
    -- query is absent, only RegisterEvent's documented true result proves it.
    local registered = result == true
    if type(self.events.IsEventRegistered) == "function" then
        local checked, value = pcall(self.events.IsEventRegistered, self.events, "COMBAT_LOG_EVENT_UNFILTERED")
        registered = checked and readable(value) and value == true
    end
    if registered then
        self.critEventsRegistered = true
        self:SetCritStatus(nil)
    else
        self:SetCritStatus(CRIT_UNAVAILABLE)
    end
end

function Controller:SetRumbleOption(name, enabled)
    if name ~= "combatRumble" and name ~= "critRumble" then return false, "Unknown rumble option." end
    self:GetSettings()[name] = enabled == true
    if not enabled then self:StopRumble() end
    if name == "critRumble" then
        self.lastCritPulse = nil
        self:UpdateCritEvents()
    end
    refresh()
    return true, enabled and "Rumble alert enabled." or "Rumble alert disabled."
end

local spellDamage = {RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_BUILDING_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, DAMAGE_SPLIT = true}

-- Select only the known damage fields without allocating a table for each
-- combat-log message. Unrelated events never become crit alerts.
local function damageFields(timestamp, kind, hideCaster, sourceGUID, sourceName, sourceFlags,
    sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags,
    arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
    if not readable(kind) or type(kind) ~= "string" then return kind end
    if kind == "SWING_DAMAGE" then return kind, sourceGUID, arg1, arg7 end
    if spellDamage[kind] then return kind, sourceGUID, arg4, arg10 end
    return kind
end

local function readDamage(getter)
    return damageFields(getter())
end

function Controller:OnCombatLog()
    if not self:GetSettings().critRumble then return end
    if not combatLogReadable() then self:SetCritStatus(CRIT_HIDDEN); return end
    local getter = combatLogReader()
    if not getter or type(UnitGUID) ~= "function" then self:SetCritStatus(CRIT_UNAVAILABLE); return end
    local ok, kind, sourceGUID, amount, critical = pcall(readDamage, getter)
    if not ok or not readable(kind) or type(kind) ~= "string" then
        self:SetCritStatus(CRIT_HIDDEN)
        return
    end
    if kind ~= "SWING_DAMAGE" and not spellDamage[kind] then return end
    if not readable(sourceGUID) then self:SetCritStatus(CRIT_HIDDEN); return end
    if type(sourceGUID) ~= "string" or sourceGUID == "" then return end
    local guidOK, playerGUID = pcall(UnitGUID, "player")
    if not guidOK or not readable(playerGUID) or type(playerGUID) ~= "string" or playerGUID == "" then
        self:SetCritStatus(CRIT_HIDDEN)
        return
    end
    if sourceGUID ~= playerGUID then return end
    if not readable(critical) or not finite(amount) then
        self:SetCritStatus(CRIT_HIDDEN)
        return
    end
    self:SetCritStatus(nil)
    if critical ~= true or amount <= 0 then return end
    local now = type(GetTime) == "function" and GetTime() or nil
    if not finite(now) then return end
    -- No queue: rapid qualifying hits replace neither a pending alert nor a
    -- list of timers. Resume after this short tactile pulse has ended.
    if self.lastCritPulse and now >= self.lastCritPulse and now - self.lastCritPulse < 0.4 then return end
    local pulsed, reason = self:PulseRumble(0.25)
    if pulsed then self.lastCritPulse = now else self:SetCritStatus(reason) end
end

local bindingCVars = {
    gamepadenable = true, gamepademulatealt = true, gamepademulatectrl = true,
    gamepademulateshift = true, gamepademulateesc = true,
    gamepadcursorleftclick = true, gamepadcursorrightclick = true,
}
local events = CreateFrame("Frame")
Controller.events = events
for _, event in ipairs({"ADDON_LOADED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_LOGOUT", "PLAYER_LEAVING_WORLD", "PLAYER_ENTERING_WORLD", "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED", "CVAR_UPDATE"}) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= addonName then return end
        Controller:GetSettings()
        Controller:UpdateCritEvents()
        return
    end
    if not SH.db then return end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        Controller:OnCombatLog()
    elseif event == "PLAYER_REGEN_DISABLED" then
        Controller.lastCritPulse = nil
        Controller:UpdateCritEvents()
        if Controller:GetSettings().combatRumble then Controller:PulseRumble(0.2) end
    elseif event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" or event == "GAME_PAD_DISCONNECTED" then
        Controller:StopRumble()
        Controller.lastCritPulse = nil
        refresh()
    elseif event == "CVAR_UPDATE" then
        local name = ...
        if readable(name) and type(name) == "string" and bindingCVars[name:lower()] then
            if not Controller:IsEnabled() then Controller:StopRumble() end
            Controller:RefreshBindings()
            refresh()
        end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "GAME_PAD_CONNECTED" then
        Controller:RefreshBindings()
        Controller:UpdateCritEvents()
        refresh()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Controller.lastCritPulse = nil
        Controller:UpdateCritEvents()
    end
end)

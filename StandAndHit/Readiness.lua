local _, SH = ...
local Readiness = {}
SH.Readiness = Readiness

-- This module evaluates the exact prepared selector against private objects.
-- No protected frame is written, clicked, or asked to execute a snippet.
local cache, compiled = {}, setmetatable({}, {__mode = "k"})
local generation, eventFrame = 0, nil
local function plain(value, label)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret ~= false then error((label or "Reading") .. " is restricted", 0) end
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then error((label or "Reading") .. " is inaccessible", 0) end
    end
    return value
end
local function boolean(value, label)
    value = plain(value, label)
    if type(value) ~= "boolean" then error((label or "Reading") .. " is unavailable", 0) end
    return value
end
local function number(value, label)
    value = plain(value, label)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        error((label or "Numeric reading") .. " is unavailable", 0)
    end
    return value
end
Readiness.Plain, Readiness.Boolean, Readiness.Number = plain, boolean, number

function Readiness.Invalidate()
    generation = generation + 1
    cache = {}
end

local events = {
    "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "UNIT_AURA", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_COMBAT", "UNIT_PET", "UNIT_TARGET", "GROUP_ROSTER_UPDATE",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_CHARGES", "SPELLS_CHANGED",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_POSSESS_BAR", "MODIFIER_STATE_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_TOTEM_UPDATE", "PET_BAR_UPDATE",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "UI_ERROR_MESSAGE", "UI_INFO_MESSAGE", "CVAR_UPDATE",
}
local function listen()
    if eventFrame or type(CreateFrame) ~= "function" then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", Readiness.Invalidate)
    for _, event in ipairs(events) do pcall(eventFrame.RegisterEvent, eventFrame, event) end
end

local function validIndex(value, maximum)
    value = plain(value, "Index")
    return type(value) == "number" and value >= 1 and value <= maximum and value % 1 == 0
end
local function profile()
    local root = SH.rootDB
    if type(root) ~= "table" or not validIndex(root.activeProfile, 5) then return {} end
    local id = root.activeProfile
    local entry = root.profiles and root.profiles[id]
    local name = plain(entry and entry.name, "Profile name")
    return {profileID = id, profileName = type(name) == "string" and name or nil}
end
function Readiness.GetProfile()
    local ok, result = pcall(profile)
    return ok and result or {}
end

function Readiness.IsEnabled()
    local integration = SH.WeakAurasIntegration
    if type(integration) ~= "table" or type(integration.IsEnabled) ~= "function" then return false end
    local ok, enabled = pcall(integration.IsEnabled)
    if not ok then return false end
    local checked, result = pcall(boolean, enabled, "WeakAuras integration setting")
    return checked and result == true
end

local function effective(frame, key)
    if type(frame.GetEffectiveAttribute) == "function" then
        return plain(frame:GetEffectiveAttribute(key), "Action attribute")
    elseif type(SecureButton_GetModifiedAttribute) == "function" then
        return plain(SecureButton_GetModifiedAttribute(frame, key), "Action attribute")
    end
    return plain(frame:GetAttribute(key), "Action attribute")
end
local function actionPage()
    local query = GetActionBarPage or C_ActionBar and C_ActionBar.GetActionBarPage
    assert(type(query) == "function", "Action bar page unavailable")
    return number(query(), "Action bar page")
end
local function macroCondition(expression)
    assert(type(SecureCmdOptionParse) == "function", "Macro condition query unavailable")
    -- The auxiliary target return may be restricted independently of this value.
    local result = SecureCmdOptionParse(expression)
    result = plain(result, "Macro condition")
    assert(result == nil or type(result) == "string", "Macro condition unavailable")
    return result
end

local function program(rotation, code, key, environment)
    local entry = compiled[rotation]
    if not entry or entry.source ~= rotation.readinessSource or entry.castSource ~= rotation.readinessCastSource
        or entry.refs ~= rotation.readinessRefs or entry.rules ~= rotation.activeRules then
        entry = {source = rotation.readinessSource, castSource = rotation.readinessCastSource,
            refs = rotation.readinessRefs, rules = rotation.activeRules, functions = {}}
        compiled[rotation] = entry
    end
    local saved = entry.functions[key]
    if not saved or saved.code ~= code then
        assert(type(code) == "string", "Prepared readiness program unavailable")
        local wrapper = "return function(self, ...)\n" .. code .. "\nend"
        local factory, reason
        if type(loadstring) == "function" and type(setfenv) == "function" then
            factory, reason = loadstring(wrapper, "StandAndHit readiness")
            if factory then setfenv(factory, environment) end
        else
            factory, reason = load(wrapper, "StandAndHit readiness", "t", environment)
        end
        assert(factory, reason or "Readiness compiler unavailable")
        saved = {code = code, fn = factory()}
        entry.functions[key] = saved
    end
    -- Lua 5.1 functions use the current query's sandbox. Later Lua runtimes
    -- retain their original environment; its functions contain no query state.
    if type(setfenv) == "function" then setfenv(saved.fn, environment) end
    return saved.fn
end

local function preview(rotation, source)
    local button = rotation.button
    local references, countSources = {[button] = rotation.readinessRefs}, {}
    for index, record in pairs(rotation.castCountObservers or {}) do
        if record.counter and record.entry then
            references[record.counter] = {native = record.entry.button, cast = record.entry.castFrame}
            countSources[record.counter] = {index = index, ["sh-check"] = record.readinessCheckSource,
                ["sh-casting"] = record.readinessCastingSource}
        end
    end
    local environment = {
        math = {abs = math.abs}, tonumber = tonumber, tostring = tostring,
        type = function(value) return type(plain(value)) end,
        rawtype = function(value) return type(plain(value)) end,
        SecureCmdOptionParse = macroCondition, GetActionBarPage = actionPage,
        GetActionInfo = function(slot)
            assert(type(GetActionInfo) == "function", "Action information unavailable")
            local kind, id = GetActionInfo(slot)
            return plain(kind, "Action type"), plain(id, "Action spell ID")
        end,
    }
    local proxies, proxy, run = {}, nil, nil
    run = function(code, key, self, ...)
        return program(rotation, code, key, environment)(self, ...)
    end
    proxy = function(frame)
        if not frame then return nil end
        frame = plain(frame, "Prepared frame")
        if proxies[frame] then return proxies[frame] end
        if type(frame.IsForbidden) == "function" then
            assert(not boolean(frame:IsForbidden(), "Prepared frame access"), "Prepared frame is forbidden")
        end
        local values, written, shown = {}, {}, nil
        local shadow = {}
        proxies[frame] = shadow
        function shadow:GetAttribute(key)
            if written[key] then return values[key] end
            return plain(frame:GetAttribute(key), "Prepared attribute " .. key)
        end
        function shadow:SetAttribute(key, value)
            written[key], values[key] = true, plain(value, "Shadow attribute")
        end
        function shadow:GetFrameRef(key)
            -- Ordinary Lua does not have SecureHandler's GetFrameRef on every
            -- client. Core records exactly the references installed at Prepare.
            return proxy(references[frame] and references[frame][key])
        end
        function shadow:GetParent() return proxy(plain(frame:GetParent(), "Prepared parent")) end
        function shadow:IsShown()
            if shown ~= nil then return shown end
            return boolean(frame:IsShown(), "Prepared tracker visibility")
        end
        function shadow:IsVisible() return boolean(frame:IsVisible(), "Prepared frame visibility") end
        function shadow:Show() shown = true end
        function shadow:Hide()
            local changed = self:IsShown()
            shown = false
            if not changed then return end
            -- The selector refreshes Druid form signals before checking their
            -- proc/count guards. A real Hide also notifies their shown children.
            -- Reproduce only these known host effects on private objects; never
            -- fetch or execute a live OnHide script or an arbitrary child hook.
            local guard = rotation.guards and rotation.guards[frame]
            if guard then
                local child = proxy(guard)
                local epoch = child:GetAttribute("sh-proc-epoch")
                if epoch ~= nil and child:IsShown() and child:GetParent() == self then
                    child:SetAttribute("sh-proc-epoch", number(epoch, "Proc epoch") + 1)
                end
            end
            for _, record in pairs(rotation.castCountObservers or {}) do
                if record.auraFrame == frame and record.auraGuard then
                    local child = proxy(record.auraGuard)
                    if child:IsShown() and child:GetParent() == self then
                        local counter = proxy(record.counter)
                        if counter:GetAttribute("sh-active") == true then
                            counter:SetAttribute("sh-count", 0)
                            counter:SetAttribute("sh-started", false)
                        end
                    end
                end
            end
        end
        function shadow:GetID() return number(frame:GetID(), "Action button ID") end
        function shadow:GetEffectiveAttribute(key) return effective(frame, key) end
        function shadow:RunAttribute(name, ...)
            if name == "sh-check" or name == "sh-casting" then
                local allowed = countSources[frame]
                local code = allowed and allowed[name]
                assert(type(code) == "string" and self:GetAttribute(name) == code, "Cast-count reader changed; prepare again")
                return run(code, name .. allowed.index, self, ...)
            end
            assert(SH.ReadinessReaders and type(SH.ReadinessReaders.Run) == "function", "Readiness readers unavailable")
            local handled, result = SH.ReadinessReaders.Run(rotation, self, name, ...)
            assert(handled == true, "Unsupported readiness reader: " .. tostring(name))
            return result
        end
        return shadow
    end
    local shadow = proxy(button)
    run(source, source == rotation.readinessSource and "select" or "cast", shadow)
    local selected = shadow:GetAttribute("selected-row")
    if selected and shadow:GetAttribute("type") == "macro" and validIndex(selected, #rotation.activeRules)
        and rotation.activeRules[selected].customRule ~= nil then
        local row = rotation.activeRules[selected]
        return {state = "unknown", reason = "Custom Rule qualifies; the following action needs a physical press",
            ruleIndex = row.sourceIndex or selected, spellName = row.displayName, icon = row.icon}
    end
    local qualifies = selected and (shadow:GetAttribute("type") == "pet" and shadow:GetAttribute("action") ~= nil
        or shadow:GetAttribute("type") == "spell" and shadow:GetAttribute("spell") ~= nil)
    if qualifies then
        assert(validIndex(selected, #rotation.activeRules), "Selected rule unavailable")
        local row = rotation.activeRules[selected]
        return {state = "ready", reason = "Prepared action qualifies", ruleIndex = row.sourceIndex or selected,
            spellID = row.spellID, spellName = row.displayName, icon = row.icon}
    end
    if shadow:GetAttribute("sh-wand-hold") then return {state = "not-ready", reason = "Repeat attack is already active"} end
    if shadow:GetAttribute("sh-count-wait") then return {state = "not-ready", reason = "Waiting for the final counted cast"} end
    if shadow:GetAttribute("sh-valid") ~= true then
        if rotation.db.preparedPreventClipping ~= false and macroCondition("[channeling]1") then
            return {state = "not-ready", reason = "Channel protection"}
        end
        return {state = "unknown", reason = "A prepared dependency could not be validated"}
    end
    return {state = "not-ready", reason = "No prepared action qualifies"}
end

local function evaluate(index, current)
    if SH.switchingProfile then return {state = "unknown", reason = "Profile switch in progress"} end
    local rotation = SH:GetRotation(index)
    if not rotation or not rotation.db then return {state = "unknown", reason = "Hit Button unavailable"} end
    if not rotation:IsEnabled() then return {state = "not-ready", reason = "Hit Button disabled"} end
    if not rotation.prepared or not rotation.button then return {state = "unknown", reason = "Hit Button is not prepared"} end
    if rotation.stale or rotation.suspendedPrepared or rotation.db.preparationRequest then
        return {state = "unknown", reason = "Preparation is stale or suspended"}
    end
    local button = rotation.button
    if plain(button:GetAttribute("ready"), "Prepared flag") ~= true then
        return {state = "unknown", reason = "Prepared button is not ready"}
    end
    local source, castSource = rotation.readinessSource, rotation.readinessCastSource
    if type(source) ~= "string" or type(rotation.readinessRefs) ~= "table" then
        return {state = "unknown", reason = "Prepare this Hit Button again"}
    end
    -- Verify live code on every call, including repeated reads in one frame.
    if plain(button:GetAttribute("sh-select"), "Prepared selector") ~= source
        or plain(button:GetAttribute("sh-select-cast"), "Prepared cast selector") ~= castSource then
        return {state = "unknown", reason = "Prepared selector changed; prepare again"}
    end
    local followup = plain(button:GetAttribute("sh-auto-followup"), "Auto attack followup") == true
    if followup and type(castSource) ~= "string" then return {state = "unknown", reason = "Auto attack selector unavailable"} end
    if plain(button:GetAttribute("sh-suppress-click")) or plain(button:GetAttribute("sh-dragging")) then
        return {state = "not-ready", reason = "Hit Button click is suppressed"}
    end
    local now = number(GetTime(), "Client time")
    local old = cache[index]
    if old and old.at == now and old.generation == generation and old.profileID == current.profileID
        and old.profileName == current.profileName and old.rotation == rotation and old.db == rotation.db
        and old.source == source and old.castSource == castSource and old.refs == rotation.readinessRefs
        and old.rules == rotation.activeRules and old.followup == followup then return old.result end
    local result = preview(rotation, followup and castSource or source)
    cache[index] = {at = now, generation = generation, profileID = current.profileID, profileName = current.profileName,
        rotation = rotation, db = rotation.db, source = source, castSource = castSource, refs = rotation.readinessRefs,
        rules = rotation.activeRules, followup = followup, result = result}
    return result
end

local function publicResult(source, index, current)
    local result = {state = source.state, buttonIndex = index, profileID = current.profileID, profileName = current.profileName}
    for _, key in ipairs({"reason", "spellName"}) do
        local value = plain(source[key], key)
        if type(value) == "string" then result[key] = value end
    end
    for _, key in ipairs({"ruleIndex", "spellID"}) do
        local value = plain(source[key], key)
        if type(value) == "number" and value >= 1 and value < math.huge and value % 1 == 0 then result[key] = value end
    end
    local icon = plain(source.icon, "Icon")
    if type(icon) == "string" or type(icon) == "number" and icon >= 0 and icon < math.huge then result.icon = icon end
    return result
end
function Readiness.Query(index)
    local current = Readiness.GetProfile()
    local valid, accepted = pcall(validIndex, index, 4)
    if not valid or not accepted then return {state = "unknown", reason = "Invalid Hit Button index",
        profileID = current.profileID, profileName = current.profileName} end
    if not Readiness.IsEnabled() then return {state = "not-ready", reason = "WeakAuras integration is disabled", buttonIndex = index,
        profileID = current.profileID, profileName = current.profileName} end
    listen()
    local ok, result = pcall(evaluate, index, current)
    if not ok then
        local readable, reason = pcall(plain, result)
        result = {state = "unknown", reason = readable and type(reason) == "string" and reason or "Readiness unavailable"}
    end
    local copied, output = pcall(publicResult, result, index, current)
    if copied then return output end
    return {state = "unknown", reason = "Readiness result is restricted", buttonIndex = index,
        profileID = current.profileID, profileName = current.profileName}
end

_G.StandAndHitReadinessHost = {version = 1, Query = Readiness.Query, GetProfile = Readiness.GetProfile, IsEnabled = Readiness.IsEnabled}

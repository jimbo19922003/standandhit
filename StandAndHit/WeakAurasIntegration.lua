local _, SH = ...
local Integration = {}
SH.WeakAurasIntegration = Integration

local function readable(value)
    if type(issecretvalue) == "function" then
        local ok, hidden = pcall(issecretvalue, value)
        if not ok or hidden ~= false then return false end
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then return false end
    end
    return true
end

function Integration.IsEnabled()
    local root = SH.rootDB
    if type(root) ~= "table" then return false end
    local enabled = root.weakAurasIntegrationEnabled
    if not readable(enabled) then return false end
    if enabled == nil then root.weakAurasIntegrationEnabled = false end
    return enabled == true
end

function Integration.SetEnabled(enabled)
    if not readable(enabled) or type(enabled) ~= "boolean" then return false, "Choose whether WeakAuras integration is enabled." end
    if type(SH.rootDB) ~= "table" then return false, "Stand and Hit is still loading. Try again after login." end
    SH.rootDB.weakAurasIntegrationEnabled = enabled
    if SH.Readiness and type(SH.Readiness.Invalidate) == "function" then SH.Readiness.Invalidate() end
    return true, enabled and "WeakAuras integration enabled." or "WeakAuras integration disabled."
end

local function addonFunction(name)
    local fn = type(C_AddOns) == "table" and C_AddOns[name] or _G[name]
    if readable(fn) and type(fn) == "function" then return fn end
end

local function addonInfo(name)
    local fn = addonFunction("GetAddOnInfo")
    if not fn then return nil end
    local ok, found, _, _, loadable, reason = pcall(fn, name)
    if not ok or not readable(found) or not readable(loadable) or not readable(reason) then return nil end
    return {installed = type(found) == "string" and found ~= "", loadable = loadable == true,
        reason = type(reason) == "string" and reason or nil}
end

local function loaded(name, fallback)
    local fn = addonFunction("IsAddOnLoaded")
    if fn then
        local ok, loadingOrLoaded, complete = pcall(fn, name)
        if ok and readable(loadingOrLoaded) and readable(complete) then
            if type(complete) == "boolean" then return complete end
            if type(loadingOrLoaded) == "boolean" then return loadingOrLoaded end
        end
    end
    return fallback
end

local function weakAurasFunction(name)
    local wa = _G.WeakAuras
    if not readable(wa) or type(wa) ~= "table" then return nil end
    local fn = wa[name]
    if readable(fn) and type(fn) == "function" then return fn end
end

local function optionsFunction() return weakAurasFunction("OpenOptions") end

local function optionsOpen()
    local check = weakAurasFunction("IsOptionsOpen")
    if not check then return nil end
    local ok, shown = pcall(check)
    if ok and readable(shown) and type(shown) == "boolean" then return shown end
end

local function loadMessage(reason)
    if reason == "DISABLED" then return "Enable WeakAuras and WeakAuras Options in AddOns, then reload." end
    if reason == "MISSING" then return "Install a WeakAuras version for this WoW client, then restart the game." end
    if reason == "INCOMPATIBLE" or reason == "INTERFACE_VERSION" then
        return "Install a compatible WeakAuras version for this WoW client, then restart the game."
    end
    return "WeakAuras could not load. Check WeakAuras and WeakAuras Options in AddOns, then reload."
end

function Integration.OpenWeakAuras()
    if type(InCombatLockdown) ~= "function" then return false, "Combat state is unavailable. Try again after login." end
    local ok, combat = pcall(InCombatLockdown)
    if not ok or not readable(combat) or type(combat) ~= "boolean" then return false, "Combat state is unavailable. Try again after login." end
    if combat then return false, "Leave combat before opening WeakAuras." end
    local open = optionsFunction()
    if not open then
        local load = addonFunction("LoadAddOn")
        if not load then return false, "Enable WeakAuras in AddOns, then reload." end
        local called, success, reason = pcall(load, "WeakAuras")
        if not called or not readable(success) or success ~= true then
            return false, loadMessage(readable(reason) and reason or nil)
        end
        open = optionsFunction()
    end
    if not open then return false, "WeakAuras options are unavailable. Check its installation and reload." end
    local visible = optionsOpen()
    if visible == true then return true, "WeakAuras is open." end
    if visible == nil then return false, "WeakAuras options are unavailable. Wait until login finishes, then try /wa." end
    local login = weakAurasFunction("IsLoginFinished")
    if login then
        local checked, finished = pcall(login)
        if not checked or not readable(finished) or finished ~= true then
            return false, "Wait until WeakAuras finishes loading after login, then try again."
        end
    end
    -- WeakAuras owns loading its Options addon and opening/toggling its UI.
    local opened = pcall(open)
    if not opened then return false, "WeakAuras could not open its options. Check WeakAuras Options in AddOns and reload." end
    if optionsOpen() ~= true then
        return false, "WeakAuras did not open. Check WeakAuras Options in AddOns, then try /wa."
    end
    return true, "WeakAuras is open."
end

function Integration.GetTriggerCode(index)
    if not readable(index) or type(index) ~= "number" or index < 1 or index > 4 or index % 1 ~= 0 then
        return nil, "Choose Hit Button 1, 2, 3, or 4."
    end
    return "function()\n    local api = _G.StandAndHitWeakAuras\n    return api ~= nil and api.IsHitButtonReady(" .. index .. ") or false\nend"
end

function Integration.GetStatus()
    local api = _G.StandAndHitWeakAuras
    local companion = readable(api) and type(api) == "table" and type(api.IsHitButtonReady) == "function"
    local status = {enabled = Integration.IsEnabled(), companionLoaded = loaded("StandAndHitWeakAuras", companion),
        weakAurasLoaded = loaded("WeakAuras", optionsFunction() ~= nil)}
    if not status.enabled then
        status.code, status.message = "disabled", "Turn on WeakAuras integration to use Hit Button readiness triggers."
    elseif not status.companionLoaded then
        local info = addonInfo("StandAndHitWeakAuras")
        if info and not info.installed then
            status.code, status.message = "companion-missing", "Install the bundled StandAndHitWeakAuras folder beside StandAndHit, then restart the game."
        else
            status.code, status.message = "companion-disabled", "Enable Stand and Hit: WeakAuras in AddOns, then reload."
        end
    elseif not status.weakAurasLoaded then
        local info = addonInfo("WeakAuras")
        if info and not info.installed then
            status.code, status.message = "weakauras-missing", loadMessage("MISSING")
        elseif info and info.reason == "DISABLED" then
            status.code, status.message = "weakauras-disabled", loadMessage("DISABLED")
        else
            status.code, status.message = "weakauras-unloaded", "Click Open WeakAuras to load its options, then add a trigger from Setup and copy trigger."
        end
    else
        status.code, status.message = "ready", "Ready. Prepare your Hit Buttons, then add a trigger from Setup and copy trigger."
    end
    return status
end

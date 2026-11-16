-- Optional read-only bridge. Stand and Hit owns readiness evaluation and caching.
local API_VERSION = 1
local API = {version = "0.1.1", apiVersion = API_VERSION}
local STATES = {["ready"] = true, ["not-ready"] = true, ["unknown"] = true}

local function plain(value)
    if type(issecretvalue) == "function" then
        local ok, hidden = pcall(issecretvalue, value)
        if not ok or hidden ~= false then error("Restricted readiness value", 0) end
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then error("Inaccessible readiness value", 0) end
    end
    return value
end

local function validIndex(value, maximum)
    value = plain(value)
    return type(value) == "number" and value >= 1 and value < math.huge
        and value == math.floor(value) and (not maximum or value <= maximum)
end

local function text(value)
    value = plain(value)
    if type(value) == "string" and value ~= "" then return value end
end

local function copyProfile(result, source)
    source = plain(source)
    if type(source) ~= "table" then return end
    local id = rawget(source, "profileID")
    if validIndex(id, 5) then result.profileID = id end
    result.profileName = text(rawget(source, "profileName"))
end

local function unknown(index, reason, host)
    local result = {state = "unknown", reason = reason}
    if validIndex(index, 4) then result.buttonIndex = index end
    host = plain(host)
    local getProfile = type(host) == "table" and plain(rawget(host, "GetProfile"))
    if type(getProfile) == "function" then
        local ok, profile = pcall(getProfile)
        if ok then pcall(copyProfile, result, profile) end
    end
    return result
end

local function read(index)
    if not validIndex(index, 4) then return unknown(nil, "invalid-button") end
    local host = plain(_G.StandAndHitReadinessHost)
    if type(host) ~= "table" then return unknown(index, "host-unavailable") end
    if plain(rawget(host, "version")) ~= API_VERSION then
        return unknown(index, "unsupported-host-version")
    end
    local isEnabled = plain(rawget(host, "IsEnabled"))
    if type(isEnabled) ~= "function" then return unknown(index, "integration-setting-unavailable", host) end
    local enabledOK, enabled = pcall(isEnabled)
    if not enabledOK then return unknown(index, "integration-setting-unavailable", host) end
    enabled = plain(enabled)
    if enabled == false then
        local result = unknown(index, "integration-disabled", host)
        result.state = "not-ready"
        return result
    end
    if enabled ~= true then return unknown(index, "integration-setting-unavailable", host) end
    local query = plain(rawget(host, "Query"))
    if type(query) ~= "function" then return unknown(index, "host-unavailable", host) end
    local ok, source = pcall(query, index)
    if not ok then return unknown(index, "host-error", host) end
    source = plain(source)
    if type(source) ~= "table" then return unknown(index, "invalid-host-result", host) end
    local state = plain(rawget(source, "state"))
    if not STATES[state] then return unknown(index, "invalid-host-result", host) end
    local sourceIndex = plain(rawget(source, "buttonIndex"))
    if sourceIndex ~= nil and sourceIndex ~= index then
        return unknown(index, "invalid-host-result", host)
    end

    -- Return only scalar public fields in a new table. Callers cannot mutate
    -- the host's cached result, editor state, rules, or secure buttons through it.
    local result = {state = state, buttonIndex = index}
    result.reason = text(rawget(source, "reason"))
    local ruleIndex, spellID = rawget(source, "ruleIndex"), rawget(source, "spellID")
    if validIndex(ruleIndex) then result.ruleIndex = ruleIndex end
    if validIndex(spellID) then result.spellID = spellID end
    result.spellName = text(rawget(source, "spellName"))
    local icon = plain(rawget(source, "icon"))
    if type(icon) == "string" or (type(icon) == "number" and icon >= 0 and icon < math.huge) then
        result.icon = icon
    end
    copyProfile(result, source)
    return result
end

function API.GetHitButtonReadiness(index)
    local ok, result = pcall(read, index)
    if ok then return result end
    -- Never expose a restricted host value or error object to a caller. Check
    -- the requested index independently before including it in the fallback.
    local fallback = {state = "unknown", reason = "restricted-or-unavailable"}
    local checked, valid = pcall(validIndex, index, 4)
    if checked and valid then fallback.buttonIndex = index end
    return fallback
end

function API.IsHitButtonReady(index)
    return API.GetHitButtonReadiness(index).state == "ready"
end

function API.IsHitButton1Ready() return API.IsHitButtonReady(1) end
function API.IsHitButton2Ready() return API.IsHitButtonReady(2) end
function API.IsHitButton3Ready() return API.IsHitButtonReady(3) end
function API.IsHitButton4Ready() return API.IsHitButtonReady(4) end

_G.StandAndHitWeakAuras = API

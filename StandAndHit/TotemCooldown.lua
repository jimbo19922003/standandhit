local _, SH = ...

local Totem = {widths = {data = {}, commit = {}}}
SH.TotemCooldown = Totem
local signal = SH.BinarySignal.New(Totem, "Totem cooldown", "totem", "StandAndHitTotem")
local bindings, tracked = {}, {}
local events, durationSignal

Totem.READ_SNIPPET = [[
    self:SetAttribute("sh-totem-ready", nil)
    local spellID, requireKnown = ...
    if rawtype(spellID) ~= "number" or spellID < 1 or spellID % 1 ~= 0 then return false end
]] .. SH.BinarySignal.Reader("totem", "sh-totem-ready", "RefreshTotemCooldown", "phase, spellID, requireKnown")

local function secret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function knownBoolean(value)
    if not secret(value) and type(value) == "boolean" then return value end
end

local function readInfo(spellID)
    local info = signal.Call("GetSpellCooldown", C_Spell.GetSpellCooldown, spellID)
    if type(info) ~= "table" then return nil end
    -- These fields are explicitly public even when the duration is restricted.
    return knownBoolean(info.isEnabled), knownBoolean(info.isActive), info
end

local function eventGCD(spellID)
    local enabled, active, info = readInfo(spellID)
    if enabled and active then return knownBoolean(info.isOnGCD) end
end

local function onCooldownUpdate()
    -- One cast can affect other spells through a shared cooldown or GCD. Ask
    -- for each tracked spell by its own ID while the GCD flag is authoritative.
    for id, state in pairs(tracked) do
        local ok, gcd = pcall(eventGCD, id)
        if ok then state.gcd = gcd else state.gcd = nil end
    end
end

local function readDuration(spellID)
    local duration = signal.Call("GetSpellCooldownDuration", C_Spell.GetSpellCooldownDuration, spellID, true)
    if not secret(duration) and duration ~= nil then
        local busy = signal.Call("Duration:IsActive", duration.IsActive, duration)
        if secret(busy) and durationSignal then return durationSignal:ReadBoolean(busy) end
        return knownBoolean(busy)
    end
end

local function isReady(spellID, state, requireKnown)
    local ok, enabled, active = pcall(readInfo, spellID)
    if not ok or enabled ~= true or active ~= true then state.gcd = nil end
    if not ok then return nil end
    if enabled == false then
        if requireKnown then return nil end
        return false
    end
    if enabled ~= true or active == nil then return nil end
    if not active then return true end
    if type(C_Spell.GetSpellCooldownDuration) == "function" then
        local ok, busy = pcall(readDuration, spellID)
        if ok and busy ~= nil then
            local ready = not busy
            if state.gcd ~= ready then state.gcd = nil end
            return ready
        end
    end
    -- The spell has an active timer. If its duration is restricted, only a
    -- confirmed global cooldown can make it eligible before that timer ends.
    if requireKnown then return state.gcd end
    return state.gcd == true
end

-- Readers that combine cooldown and usability need an unknown result when
-- an active timer could still be either the GCD or the spell's own cooldown.
function Totem:ReadReady(button, spellID)
    local ids = bindings[button]
    if ids and ids[spellID] then return isReady(spellID, tracked[spellID], true) end
end

local function removeBinding(button)
    local old = bindings[button]
    if not old then return end
    bindings[button] = nil
    for id in pairs(old) do
        local state = tracked[id]
        state.users = state.users - 1
        if state.users == 0 then tracked[id] = nil end
    end
end

local function prepare(button, spellIDs)
    signal.Outside()
    local ids = {}
    for id, enabled in pairs(spellIDs) do
        if enabled ~= true or type(id) ~= "number" or id < 1 or id % 1 ~= 0 then
            error("Choose a learned totem spell.", 0)
        end
        local available, active = readInfo(id)
        if available == nil or active == nil then error("The spell cooldown is unavailable for spell ID " .. id .. ".", 0) end
        ids[id] = true
    end
    if not next(ids) then error("Choose a totem spell to check.", 0) end
    signal.Prepare()
    signal.Attach(button)
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", onCooldownUpdate)
    end
    if not next(bindings) and events:RegisterEvent("SPELL_UPDATE_COOLDOWN") == false then
        error("The totem cooldown update event is unavailable.", 0)
    end
    for id in pairs(ids) do
        local state = tracked[id] or {users = 0}
        state.users = state.users + 1
        tracked[id] = state
    end
    removeBinding(button)
    bindings[button] = ids
    if not durationSignal and SH.TotemSignal and SH.TotemSignal:Acquire(Totem, "cooldown") then
        durationSignal = SH.TotemSignal
    end
end

function Totem:Prepare(button, spellIDs)
    return pcall(prepare, button, spellIDs)
end

local function release(button)
    signal.Outside()
    if not bindings[button] then return end
    removeBinding(button)
    if not next(bindings) then
        events:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        if durationSignal then
            durationSignal:Release(Totem)
            durationSignal = nil
        end
        signal.Hide()
    end
end

function Totem:Release(button)
    return pcall(release, button)
end

local function refresh(button, phase, spellID, requireKnown)
    local ids = bindings[button]
    if not ids or not ids[spellID] then return false end
    local ready = isReady(spellID, tracked[spellID], requireKnown == true)
    if ready == nil then return false end
    signal.Publish(ready, phase)
    return true
end

function Totem:Refresh(button, phase, spellID, requireKnown)
    local ok, result = pcall(refresh, button, phase, spellID, requireKnown)
    if not ok then return false, result end
    return result
end

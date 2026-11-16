local _, SH = ...

local Riposte = {ID = 14251, widths = {data = {}, commit = {}}}
SH.Riposte = Riposte
local signal = SH.BinarySignal.New(Riposte, "Reactive spell", "riposte", "StandAndHitRiposte")
local bindings = {}

-- Exact player-spell ranks avoid treating an unrelated NPC spell with the
-- same name as a reactive ability. Counterattack's second rank is Forever-only.
local families = {}
for base, ranks in pairs({
    [14251] = {14251},
    [6572] = {6572, 6574, 7379, 11600, 11601, 25288},
    [7384] = {7384, 7887, 11584, 11585},
    [1495] = {1495, 14269, 14270, 14271},
    [19306] = {19306, 1242634, 20909, 20910},
}) do
    for _, id in ipairs(ranks) do families[id] = base end
end

function Riposte.Family(spellID)
    if type(issecretvalue) == "function" and issecretvalue(spellID) then return nil end
    if type(spellID) ~= "number" then return nil end
    return families[spellID]
end

function Riposte.IsReactive(spellID)
    return Riposte.Family(spellID) ~= nil
end

function Riposte.MatchesCondition(text, spellName, spellID)
    spellID = spellID or Riposte.ID
    local family = Riposte.Family(spellID)
    if not family then return false end
    text = SH.Model.Trim(text)
    local id = tonumber(text)
    if id then return Riposte.Family(id) == family end
    local name = spellName(spellID)
    return type(name) == "string" and name ~= "" and name:lower() == text:lower()
end

Riposte.READ_SNIPPET = [[
    self:SetAttribute("sh-riposte-ready", nil)
]] .. SH.BinarySignal.Reader("riposte", "sh-riposte-ready", "RefreshRiposte", "phase")

Riposte.REACTIVE_READ_SNIPPET = [[
    self:SetAttribute("sh-reactive-ready", nil)
    local spellID = ...
    if rawtype(spellID) ~= "number" or spellID < 1 or spellID % 1 ~= 0 then return false end
]] .. SH.BinarySignal.Reader("riposte", "sh-reactive-ready", "RefreshRiposte", "phase, spellID")

local function readFlag(value)
    if issecretvalue(value) then
        if SH.TotemSignal then return SH.TotemSignal:ReadBoolean(value) end
    elseif type(value) == "boolean" then
        return value
    end
end

local function readUsability(spellID)
    local usable, insufficientPower = C_Spell.IsSpellUsable(spellID)
    usable, insufficientPower = readFlag(usable), readFlag(insufficientPower)
    if type(usable) ~= "boolean" or type(insufficientPower) ~= "boolean" then return nil end
    if usable and insufficientPower then return nil end
    return usable
end

local function prepare(button, spellIDs)
    signal.Outside()
    if type(issecretvalue) ~= "function" or not C_Spell or type(C_Spell.IsSpellUsable) ~= "function"
        or not SH.TotemCooldown or type(SH.TotemCooldown.ReadReady) ~= "function" then
        error("This client cannot check reactive spell readiness.", 0)
    end
    if spellIDs == nil then spellIDs = {[Riposte.ID] = true} end
    if type(spellIDs) ~= "table" then error("Reactive spell list is invalid.", 0) end
    local allowed = {}
    for id, enabled in pairs(spellIDs) do
        if enabled ~= true or not Riposte.IsReactive(id) then error("Reactive spell ID is unsupported.", 0) end
        allowed[id] = true
    end
    if not next(allowed) then error("No reactive spells were selected.", 0) end
    if not next(bindings) or not Riposte.calibrated or not Riposte.dataFrame:IsShown()
        or not Riposte.commitFrame:IsShown() then signal.Prepare() end
    signal.Attach(button)
    bindings[button] = allowed
end

function Riposte:Prepare(button, spellIDs)
    local ok, reason = pcall(prepare, button, spellIDs)
    if not ok and not next(bindings) and not InCombatLockdown() then pcall(signal.Hide) end
    return ok, reason
end

local function release(button)
    signal.Outside()
    bindings[button] = nil
    if not next(bindings) then signal.Hide() end
end

function Riposte:Release(button)
    if not bindings[button] then return true end
    return pcall(release, button)
end

local function refresh(button, phase, spellID)
    spellID = spellID or Riposte.ID
    if not Riposte.IsReactive(spellID) or not bindings[button] or not bindings[button][spellID] then return false end
    -- Check this selected rank's activation, stance and resources. Its actual
    -- cooldown is checked separately from the global cooldown.
    local ready = signal.Call("IsSpellUsable", readUsability, spellID)
    if ready == true then ready = SH.TotemCooldown:ReadReady(button, spellID) end
    if type(ready) ~= "boolean" then return false end
    signal.Publish(ready, phase)
    return true
end

function Riposte:Refresh(button, phase, spellID)
    local ok, result = pcall(refresh, button, phase, spellID)
    if not ok then return false, result end
    return result
end

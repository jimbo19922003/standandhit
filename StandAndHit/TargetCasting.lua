local _, SH = ...

local Casting = {}
SH.TargetCasting = Casting
local signal = SH.BinarySignal.New(Casting, "Target is casting", "target-cast", "StandAndHitTargetCast")
local bindings = {}

Casting.READ_SNIPPET = [[
    self:SetAttribute("sh-target-casting", nil)
    if SecureCmdOptionParse("[@target,exists]1") ~= "1" then
        self:SetAttribute("sh-target-casting", false)
        return true
    end
]] .. SH.BinarySignal.Reader("target-cast", "sh-target-casting", "RefreshTargetCasting", "phase")

local function classify(...)
    -- Forever supplies a public boolean in position six while a cast or
    -- channel is active, even when the spell name and times are hidden.
    local isTradeskill = select(6, ...)
    if issecretvalue(isTradeskill) then return nil end
    if type(isTradeskill) == "boolean" then return true end
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if issecretvalue(value) or value ~= nil then return nil end
    end
    return false
end

local function query(api)
    return classify(api("target"))
end

local function refresh(button, phase)
    if not bindings[button] then return false end
    local castOK, cast = pcall(signal.Call, "UnitCastingInfo", query, UnitCastingInfo)
    if castOK and cast == true then
        signal.Publish(true, phase)
        return true
    end
    local channelOK, channel = pcall(signal.Call, "UnitChannelInfo", query, UnitChannelInfo)
    if channelOK and channel == true then
        signal.Publish(true, phase)
    elseif castOK and cast == false and channelOK and channel == false then
        signal.Publish(false, phase)
    else
        return false
    end
    return true
end

function Casting:Refresh(button, phase)
    local ok, result = pcall(refresh, button, phase)
    if not ok then return false, result end
    return result
end

local function prepare(button)
    signal.Outside()
    if type(issecretvalue) ~= "function" or type(UnitCastingInfo) ~= "function" or type(UnitChannelInfo) ~= "function" then
        error("This client cannot check the target's casts and channels.", 0)
    end
    if not next(bindings) or not Casting.calibrated or
        not Casting.dataFrame:IsShown() or not Casting.commitFrame:IsShown() then
        signal.Prepare()
    end
    signal.Attach(button)
    bindings[button] = true
end

function Casting:Prepare(button)
    local ok, reason = pcall(prepare, button)
    if not ok and not next(bindings) then pcall(signal.Hide) end
    return ok, reason
end

local function release(button)
    signal.Outside()
    if not bindings[button] then return end
    bindings[button] = nil
    if not next(bindings) then signal.Hide() end
end

function Casting:Release(button)
    return pcall(release, button)
end

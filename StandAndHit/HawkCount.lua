local _, SH = ...
local H = {}
SH.HawkCount = H

local signal = SH.BinarySignal.New(H, "Hawk count", "sh-hawk", "StandAndHitHawk")
local decoder = SH.TotemSignal
local users, idLabels = {}, {}
local zeroLabel
local boolOwner, comparisonOwner = {}, {}
-- Cast ranks and the summoned Hawk variants in Forever's spell data.
local hawkIDs = {1293241, 1293248, 1293525, 1293526, 1293527, 1312637, 1312639}
local hawkIDSet = {}
for _, id in ipairs(hawkIDs) do hawkIDSet[id] = true end
local MAX_SLOTS = 32

local function plain(value)
    if type(issecretvalue) == "function" and not issecretvalue(value) then return value end
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

local function number(value)
    value = plain(value)
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then return value end
end

local function bool(value)
    if issecretvalue(value) then return decoder:ReadBoolean(value) end
    if type(value) == "boolean" then return value end
end

local function matchesLabel(value, expected)
    if not expected then return nil end
    if not issecretvalue(value) then
        if type(value) ~= "string" or value == "" then return nil end
        return value == expected
    end
    if not C_Intl or type(C_Intl.CompareStrings) ~= "function" or not Enum or not Enum.CollationStrength then return nil end
    local strength = Enum.CollationStrength.Identical
    if strength == nil then return nil end
    return decoder:IsComparisonEqual(call(C_Intl.CompareStrings, value, expected, strength))
end

local function formatID(id)
    if not C_Intl or type(C_Intl.FormatNumber) ~= "function" or not Enum or not Enum.NumberStyle then return nil end
    local style = Enum.NumberStyle.Integer
    if style == nil then return nil end
    return call(C_Intl.FormatNumber, id, style)
end

local function prepareIDs()
    zeroLabel = plain(formatID(0))
    if type(zeroLabel) ~= "string" or zeroLabel == "" then zeroLabel = nil end
    for index, id in ipairs(hawkIDs) do
        local label = plain(formatID(id))
        idLabels[index] = type(label) == "string" and label ~= "" and label or nil
    end
end

local function identity(id)
    local publicID = number(id)
    if publicID then
        if publicID > 0 then return hawkIDSet[publicID] == true end
        return nil
    end
    if not issecretvalue(id) or not zeroLabel then return nil end
    -- A pet's name is editable and its timing may not describe a temporary
    -- summon. Compare exact spell IDs before consulting a slot's duration.
    -- Format both sides natively so localized separators remain identical.
    local label = formatID(id)
    local zero = matchesLabel(label, zeroLabel)
    if zero ~= false then return nil end
    local unreadable = false
    for index = 1, #hawkIDs do
        local match = matchesLabel(label, idLabels[index])
        if match == true then return true end
        if match == nil then unreadable = true end
    end
    if not unreadable then return false end
end

local function activity(slot)
    local left = number(call(GetTotemTimeLeft, slot))
    if left and left >= 0 then return left > 0 end
    local duration = plain(call(GetTotemDuration, slot))
    if duration and type(duration.IsActive) == "function" then return bool(call(duration.IsActive, duration)) end
end

local function observe()
    local slots = number(call(GetNumTotemSlots))
    if not slots or slots < 1 or slots > MAX_SLOTS or slots % 1 ~= 0 then return nil end
    local count = 0
    for slot = 1, slots do
        local ok, have, _, _, _, _, _, id = pcall(GetTotemInfo, slot)
        if not ok then return nil end
        local hawk = identity(id)
        if hawk ~= false then
            local present = bool(have)
            -- Removal can clear presence before the old ID/timer. A duration
            -- still being within its interval does not mean the Hawk is alive.
            if present ~= false then
                local active = activity(slot)
                if active == true then
                    if hawk == nil then return nil end
                    count = count + 1
                elseif active ~= false then
                    -- True can describe an unlocked, empty slot on Classic.
                    -- Unknown activity must not authorize a replacement.
                    return nil
                end
            end
        end
        if count > 2 then return nil end
    end
    return count
end

H.READ_SNIPPET = [[
    self:SetAttribute("sh-hawk-count", -1)
    if self:RunAttribute("sh-hawk-read-bit", 0) ~= true then return false end
    local low = self:GetAttribute("sh-hawk-bit")
    if self:RunAttribute("sh-hawk-read-bit", 1) ~= true then return false end
    local high = self:GetAttribute("sh-hawk-bit")
    local count
    if low == false and high == false then count = 0
    elseif low == true and high == false then count = 1
    elseif low == false and high == true then count = 2
    else return false end
    self:SetAttribute("sh-hawk-count", count)
    return true
]]

local function refresh(button, phase, bit)
    local binding = users[button]
    if not binding then return end
    local count = binding.pending
    binding.pending = nil
    if bit == 0 then
        local ok, value = pcall(observe)
        if not ok or value == nil then return end
        if pcall(signal.Publish, value % 2 == 1, phase) then binding.pending = value end
    elseif bit == 1 and count ~= nil then
        pcall(signal.Publish, count >= 2, phase)
    end
end

local readBit = [[
    local bit = ...
    self:SetAttribute("sh-hawk-bit", nil)
]] .. SH.BinarySignal.Reader("sh-hawk", "sh-hawk-bit", "RefreshHawkCount", "phase, bit")

local function stop()
    decoder:Release(boolOwner)
    decoder:Release(comparisonOwner)
    signal.Hide()
end

local function prepare(button)
    signal.Outside()
    if type(issecretvalue) ~= "function" or type(GetTotemInfo) ~= "function" or type(GetNumTotemSlots) ~= "function" then
        error("This client cannot read the Hunter's Hawk slots.", 0)
    end
    if not next(users) or not H.calibrated or not H.dataFrame:IsShown() or not H.commitFrame:IsShown() then signal.Prepare() end
    if not decoder:Acquire(boolOwner, "cooldown") or not decoder:Acquire(comparisonOwner, "comparison") then
        error("Hawk conditions could not prepare their native reading. Try Prepare again outside combat.", 0)
    end
    prepareIDs()
    if observe() == nil then error("The current Hawk count could not be checked. Try Prepare again outside combat.", 0) end
    users[button] = {}
    signal.Attach(button)
    button.RefreshHawkCount = refresh
    button:SetAttribute("sh-hawk-read-bit", readBit)
end

function H:Prepare(button)
    local ok, err = pcall(prepare, button)
    if not ok and not InCombatLockdown() then
        if users[button] then self:Release(button) elseif not next(users) then pcall(stop) end
    end
    return ok, err
end

-- Readiness observes the same native sources without touching the two-bit
-- callback transaction used by the protected action button.
function H:Preview(button)
    if not users[button] or not self.calibrated then return nil, "Hawk conditions are not prepared" end
    local ok, count = pcall(observe)
    if not ok or count == nil then return nil, "Hawk count is unavailable" end
    return count
end

function H:Release(button)
    if InCombatLockdown() then return false, "Leave combat before removing Hawk conditions." end
    if not users[button] then return true end
    users[button] = nil
    button:SetAttribute("sh-hawk-read-bit", nil)
    button:SetAttribute("sh-hawk-bit", nil)
    button:SetAttribute("sh-hawk-count", -1)
    button.RefreshHawkCount = nil
    if not next(users) then return pcall(stop) end
    return true
end

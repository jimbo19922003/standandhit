local _, SH = ...

local Range = {}
SH.Range = Range
local signal = SH.BinarySignal.New(Range, "Skip if out of range", "range", "StandAndHitRange")
local bindings = {}

Range.READ_SNIPPET = [[
    self:SetAttribute("sh-out-of-range", nil)
    local index = ...
    if rawtype(index) ~= "number" or index < 1 or index > 32 or index % 1 ~= 0 then return false end
    if SecureCmdOptionParse("[combat]1") ~= "1" then
        self:SetAttribute("sh-range-outside-ready",nil)
        self:SetAttribute("sh-range-outside-result",nil)
        self:CallMethod("RefreshSpellRangeOutside",index)
        if SecureCmdOptionParse("[combat]1") ~= "1" then
            local result = self:GetAttribute("sh-range-outside-result")
            if self:GetAttribute("sh-range-outside-ready") ~= index or rawtype(result) ~= "boolean" then return false end
            self:SetAttribute("sh-out-of-range",result)
            return true
        end
    end
]] .. SH.BinarySignal.Reader("range", "sh-out-of-range", "RefreshSpellRange", "phase, index")

local function readRange(button, index, strictPreview)
    local binding = bindings[button] and bindings[button][index]
    if not binding or not C_Spell or not C_Spell.IsSpellInRange then return end
    local inRange = C_Spell.IsSpellInRange(binding.spellID, binding.unit)
    -- WoW returns nil when the spell or recipient has no valid range check.
    if issecretvalue(inRange) then
        if strictPreview then error("Spell range is restricted", 0) end
        return
    end
    if strictPreview and type(canaccessvalue) == "function" and not canaccessvalue(inRange) then
        error("Spell range is inaccessible", 0)
    end
    if type(inRange) ~= "boolean" then
        if strictPreview and inRange ~= nil then error("Spell range result is invalid", 0) end
        return
    end
    return inRange == false
end

local function refresh(button, phase, index)
    local outOfRange = readRange(button, index)
    -- Leave the commit untouched so the secure reader rejects an older result.
    if outOfRange ~= nil then signal.Publish(outOfRange, phase) end
end

function Range:Refresh(button, phase, index)
    return pcall(refresh, button, phase, index)
end

-- Observe the prepared binding without changing the action button or signal.
-- A public nil is an optional, non-applicable check. Keep restricted or invalid
-- values distinct so readiness cannot mistake them for that benign absence.
function Range:Preview(button, index)
    return pcall(readRange, button, index, true)
end

local function refreshOutside(button, index)
    -- Outside combat, publish the result directly instead of depending on a
    -- tooltip layout update. The secure reader clears and acknowledges each
    -- request, and never reads these attributes during combat.
    if InCombatLockdown() then return end
    button:SetAttribute("sh-range-outside-ready", nil)
    button:SetAttribute("sh-range-outside-result", nil)
    local outOfRange = readRange(button, index)
    if outOfRange == nil or InCombatLockdown() then return end
    button:SetAttribute("sh-range-outside-result", outOfRange)
    button:SetAttribute("sh-range-outside-ready", index)
end

function Range:RefreshOutside(button, index)
    return pcall(refreshOutside, button, index)
end

local function release(button)
    signal.Outside()
    if bindings[button] then
        bindings[button] = nil
        if not next(bindings) then signal.Hide() end
    end
end

local function prepare(button, rules)
    signal.Outside()
    local records = {}
    for index, row in ipairs(rules) do
        if row.skipOutOfRange and row.spellID and not row.petAttack and not row.castAtFeet then
            local unit = row.unit == "custom" and row.customTarget:sub(2) or row.unit
            if unit ~= "none" and unit ~= "player" and C_Spell and C_Spell.SpellHasRange then
                local ok, hasRange = pcall(C_Spell.SpellHasRange, row.spellID)
                if ok and not issecretvalue(hasRange) and hasRange == true then
                    records[index] = {spellID = row.spellID, unit = unit}
                end
            end
        end
    end
    if next(records) then
        if not next(bindings) or not Range.calibrated or
            not Range.dataFrame:IsShown() or not Range.commitFrame:IsShown() then
            signal.Prepare()
        end
        signal.Attach(button)
        bindings[button] = records
    else
        release(button)
    end
end

function Range:Prepare(button, rules)
    local ok, reason = pcall(prepare, button, rules)
    if not ok and not InCombatLockdown() then
        bindings[button] = nil
        if not next(bindings) then pcall(signal.Hide) end
    end
    return ok, reason
end

function Range:Release(button)
    return pcall(release, button)
end

local _, SH = ...

-- A native aura group filters player buffs or the player's harmful effects on the target by ID.
-- The parent lays out at width 1 when empty and 111 for its single matching
-- icon. Its children deny addon access during combat and are never inspected.
local BuffSlot = {}
SH.TotemBuffSlot = BuffSlot
local EMPTY, PRESENT, INITIAL = 1, 111, 20
local pool, owners, records = {}, {}, {}
local updates, targetEvents, verify

local function plain(value)
    return not issecretvalue(value)
end

local function near(a, b)
    return plain(a) and type(a) == "number" and math.abs(a - b) < 0.25
end

local function acquireDecoder(group)
    group.hasDecoder, group.hasModeDecoder = SH.TotemSignal:Acquire(group, "aura")
    group.retryAfter = (not group.hasDecoder or not group.hasModeDecoder) and GetTime() + 5 or nil
end

local function targetGUID()
    if not UnitGUID then return end
    local ok, guid = pcall(UnitGUID, "target")
    if ok and plain(guid) and type(guid) == "string" then return guid end
end

local function readLayout(group)
    local frame = group.frame
    group.readStage = "aura source"
    if group.unit == "target" then
        if not group.targetReady then return nil, "target update pending" end
        local guid = targetGUID()
        if guid and guid ~= group.targetGUID then return nil, "target update pending" end
        local exists = UnitExists("target")
        if not plain(exists) then return nil, "target unavailable" end
        if exists then
            local visible = UnitIsVisible("target")
            local assist = UnitCanAssist("player", "target", true, true)
            if not plain(visible) or visible ~= true or not plain(assist) or assist ~= false then
                return nil, "target unavailable"
            end
        end
    else
        local visible = UnitIsVisible("player")
        if not plain(visible) or visible ~= true then return nil, "player hidden" end
    end
    local visible, enabled = frame:IsVisible(), frame:IsEnabled()
    if not plain(visible) or not plain(enabled) or visible ~= true or enabled ~= true then return nil, "aura group inactive" end
    local unit, preview = frame:GetUnit(), frame:IsEditModePreviewEnabled()
    if not plain(unit) or not plain(preview) or unit ~= group.unit or preview ~= false then return nil, "wrong aura source" end
    local filtered = frame:IsAuraGroupEnabled("effect")
    if not plain(filtered) or filtered ~= true then return nil, "aura filter disabled" end
    -- Blizzard manages UNIT_AURA for the enabled group and restricts access
    -- to its event registrations. Wait for its layout to finish updating.
    group.readStage = "aura update mode"
    local mode = frame:GetOnUpdateMode()
    if not plain(mode) and not group.hasModeDecoder then
        if not InCombatLockdown() and GetTime() >= group.retryAfter then acquireDecoder(group) end
        if not group.hasModeDecoder then return nil, "aura update mode unavailable" end
    end
    local settled = SH.TotemSignal:IsLayoutSettled(mode)
    if settled == nil then return nil, "aura update mode unreadable" end
    if not settled then return nil, "aura layout pending" end
    -- The native layout calls SetSize. Ignore its resolved screen rectangle,
    -- which loses precision at fractional UI scales.
    group.readStage = "buff width"
    local size = frame:GetWidth(true)
    if plain(size) then
        if near(size, EMPTY) then return false end
        if near(size, PRESENT) then return true end
        return nil, type(size) == "number" and ("unexpected group width %.3f"):format(size) or "unknown group width"
    end
    if not group.hasDecoder and not InCombatLockdown() and GetTime() >= group.retryAfter then acquireDecoder(group) end
    if not group.hasDecoder then return nil, "group width hidden" end
    local value = SH.TotemSignal:Read(size)
    return value, value == nil and "group width unreadable" or nil
end

local function sampleLayout(group)
    local ok, value, reason = pcall(readLayout, group)
    local stage = group.readStage or "layout"
    group.readStage = nil
    if ok then return value, reason end
    if plain(value) and type(value) == "string" then
        return nil, stage .. ": " .. (value:match(":%d+: (.+)$") or value):sub(1, 45)
    end
    return nil, "aura group read failed"
end

local function deactivate(group)
    group.key, group.verified, group.pending, group.record, group.directRead = nil, nil, nil, nil, nil
    group.reason = nil
    group.targetGUID, group.targetReady = nil, nil
    group.generation = group.generation + 1
    SH.TotemSignal:Release(group)
    group.hasDecoder, group.hasModeDecoder, group.retryAfter = nil, nil, nil
    if group.frame then
        pcall(group.frame.Hide, group.frame)
        pcall(group.frame.SetEnabled, group.frame, false)
    end
end

local function stopWatchingIfVerified()
    for _, group in ipairs(pool) do
        if group.key and not group.verified then return end
    end
    if updates then updates:UnregisterAllEvents() end
end

local function watchTargetChanges()
    local active = false
    for _, group in ipairs(pool) do
        if group.key and group.unit == "target" then active = true; break end
    end
    if not active then
        if targetEvents then targetEvents:UnregisterAllEvents() end
        return
    end
    if not targetEvents then
        targetEvents = CreateFrame("Frame")
        targetEvents:SetScript("OnEvent", function()
            for _, group in ipairs(pool) do
                if group.key and group.unit == "target" then
                    -- CustomAuraContainer's owner must request a full rebuild
                    -- when its unit token changes identity. A dirty layout is
                    -- unreadable until the native group has finished its update.
                    group.targetReady = pcall(group.frame.UpdateAllAuras, group.frame)
                    group.targetGUID = targetGUID()
                    if group.targetReady then verify(group) end
                end
            end
        end)
    end
    targetEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function compare(group, value, actual)
    if not plain(actual) or type(actual) ~= "boolean" then
        group.reason = "direct buff check unavailable"
    elseif value == actual then
        group.verified, group.reason = true, nil
        stopWatchingIfVerified()
    else
        group.reason = value and "group present, buff missing" or "group missing, buff present"
    end
end

local function configure(group, ids)
    if not group.frame then group.frame = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate") end
    local frame = group.frame
    frame:Hide()
    frame:SetEditModePreviewEnabled(false)
    frame:SetAlpha(0)
    -- Alpha does not disable mouse input for the native aura buttons.
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 200, 0)
    frame:SetUnit(group.unit)
    frame:SetSize(INITIAL, INITIAL)
    if not frame:HasAuraGroup("effect") then
        frame:AddAuraGroup("effect", group.filter, {
            candidateFilters = {includeSpellIDs = ids}, maxFrameCount = 1,
            layout = {elementWidth = PRESENT, elementHeight = PRESENT},
        })
    else
        frame:SetAuraGroupCandidateFilters("effect", {includeSpellIDs = ids})
    end
    frame:SetEnabled(true)
    frame:Show()
    frame:UpdateAllAuras()
    group.targetReady = true
    if group.unit == "target" then group.targetGUID = targetGUID() end
end

verify = function(group)
    if group.verified or group.pending or not group.key or InCombatLockdown() then return end
    group.pending = true
    local generation, attempts = group.generation, 0
    local function sample()
        if group.generation ~= generation then return end
        group.pending = nil
        if group.verified or InCombatLockdown() then return end
        local value, reason = sampleLayout(group)
        if value ~= nil then
            local known, actual = pcall(group.directRead, group.record)
            if known then compare(group, value, actual) else group.reason = "direct buff check failed" end
            if group.verified then return end
        else
            group.reason = reason
        end
        attempts = attempts + 1
        if attempts < 4 then group.pending = true; C_Timer.After(0.1, sample) end
    end
    C_Timer.After(0, sample)
end

local function watchVerification()
    if not updates then
        updates = CreateFrame("Frame")
        updates:SetScript("OnEvent", function()
            if InCombatLockdown() then return end
            for _, group in ipairs(pool) do verify(group) end
        end)
    end
    updates:RegisterEvent("PLAYER_REGEN_ENABLED")
    updates:RegisterEvent("PLAYER_ENTERING_WORLD")
    updates:RegisterUnitEvent("UNIT_AURA", "player", "target")
end

function BuffSlot:Acquire(record, owner, directRead)
    if InCombatLockdown() or not owner or type(directRead) ~= "function" or not C_Timer or not C_Timer.After then return false end
    local ids = {}
    for id, enabled in pairs(record.ids) do
        if enabled ~= true or type(id) ~= "number" or id < 1 or id % 1 ~= 0 then return false end
        ids[#ids + 1] = id
    end
    if #ids == 0 then return false end
    table.sort(ids)
    local unit = record.unit == "target" and "target" or "player"
    local filter = unit == "target" and "HARMFUL|PLAYER" or ((record.groupedPlayerBuff or record.nativePlayerBuff) and "HELPFUL|PLAYER" or "HELPFUL")
    local key, group, spare = filter .. ":" .. table.concat(ids, ","), nil, nil
    local allocated = 0
    for _, item in ipairs(pool) do
        if item.key == key then group = item; break end
        -- A group's native aura filter is fixed when it is first created.
        -- Keep self-cast class buffs separate from all-caster player buffs.
        if item.filter == filter then
            allocated = allocated + 1
            if not item.key then spare = item end
        end
    end
    if not group then
        if not spare and allocated >= 32 then return false end
        group = spare or {generation = 0, users = 0, unit = unit, filter = filter}
        if not spare then pool[#pool + 1] = group end
        -- A client can expose the native layout width directly even if the
        -- optional formatter for hidden widths couldn't be calibrated.
        acquireDecoder(group)
        if not pcall(configure, group, record.ids) or not pcall(watchVerification) then
            deactivate(group)
            return false
        end
        group.key, group.record, group.directRead = key, record, directRead
        if unit == "target" and not pcall(watchTargetChanges) then
            deactivate(group)
            stopWatchingIfVerified()
            pcall(watchTargetChanges)
            return false
        end
    end
    local bound = owners[owner] or {}
    owners[owner] = bound
    if not bound[record] then
        bound[record], records[record] = group, group
        group.users = group.users + 1
    end
    verify(group)
    return true
end

function BuffSlot:Read(record)
    local group = records[record]
    if not group then return nil, "no aura group" end
    if not group.verified then return nil, group.reason or "waiting for first aura check" end
    return sampleLayout(group)
end

-- A normal out-of-combat press can supply the comparison long after the
-- initial layout or login samples ran. Never reuse the observed buff in combat.
function BuffSlot:ObserveDirect(record, actual)
    local group = records[record]
    if not group or group.verified or InCombatLockdown() then return end
    local value, reason = sampleLayout(group)
    if value == nil then group.reason = reason else compare(group, value, actual) end
end

function BuffSlot:Release(owner)
    local bound = owners[owner]
    if not bound or InCombatLockdown() then return end
    owners[owner] = nil
    for record, group in pairs(bound) do
        records[record] = nil
        for _, other in pairs(owners) do
            if other[record] then records[record] = group; break end
        end
        group.users = group.users - 1
        if group.users == 0 then deactivate(group) end
    end
    stopWatchingIfVerified()
    watchTargetChanges()
end

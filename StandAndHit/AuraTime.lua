local addonName, SH = ...
-- The unchanged native Tracked Bar countdown feeds exact label comparisons.
-- An owned predicate transport publishes only a fresh, verified result.
local R = {ready = false, reason = "Aura time conditions have not been prepared.",
    widths = {data = {}, commit = {}}, resetWidths = {}, blocked = {}, bindings = {}, prepared = {},
    targetRevision = 0, targetStamps = {}, hookedFrames = {}, uiTick = 0, nextFrameID = 0,
    targetEventSerial = 0, sameGUIDEvents = 0, changedGUIDEvents = 0, uncertainGUIDEvents = 0}
SH.AuraTime = R
local ENCODED = {[0] = 1111, [1] = 111111}
local RESET, TOLERANCE = 1111111, 0.5
local FORMAT = string.rep("0", 24) .. "%.0f"
local COMPARE_FORMAT = string.rep("0", 24) .. "[%.0d]"
R.READ_SNIPPET = [[
    self:SetAttribute("sh-aura-time-pass", nil)
    local index = ...
    if rawtype(index) ~= "number" or index < 1 or index > 256 or index % 1 ~= 0 then return false end
    local data = self:GetFrameRef("aura-time-data")
    local commit = self:GetFrameRef("aura-time-commit")
    if not data or not commit or commit:GetAttribute("sh-aura-time-ready") ~= true
        or data:IsShown() ~= true or commit:IsShown() ~= true then return false end
    local oldWidth, oldCode = commit:GetWidth(), -1
    if rawtype(oldWidth) ~= "number" then return false end
    for code = 0, 3 do
        local width = self:GetAttribute("sh-aura-time-commit-width" .. code)
        if rawtype(width) ~= "number" then return false end
        if math.abs(width - oldWidth) <= 0.5 then
            if oldCode ~= -1 then return false end
            oldCode = code
        end
    end
    if oldCode < 0 then return false end
    local phase = oldCode < 2 and 1 or 0
    self:CallMethod("RefreshAuraTime", index, phase)
    if commit:GetAttribute("sh-aura-time-ready") ~= true or data:IsShown() ~= true or commit:IsShown() ~= true then return false end
    local dataWidth, commitWidth = data:GetWidth(), commit:GetWidth()
    if rawtype(dataWidth) ~= "number" or rawtype(commitWidth) ~= "number" then return false end
    local dataCode, commitCode = -1, -1
    for code = 0, 3 do
        local expectedData = self:GetAttribute("sh-aura-time-data-width" .. code)
        local expectedCommit = self:GetAttribute("sh-aura-time-commit-width" .. code)
        if rawtype(expectedData) ~= "number" or rawtype(expectedCommit) ~= "number" then return false end
        if math.abs(expectedData - dataWidth) <= 0.5 then
            if dataCode ~= -1 then return false end
            dataCode = code
        end
        if math.abs(expectedCommit - commitWidth) <= 0.5 then
            if commitCode ~= -1 then return false end
            commitCode = code
        end
    end
    if dataCode < 0 or dataCode ~= commitCode or commitCode == oldCode then return false end
    if not ((phase == 0 and commitCode < 2) or (phase == 1 and commitCode >= 2)) then return false end
    self:SetAttribute("sh-aura-time-pass", commitCode % 2 == 1)
    return true
]]

local function secret(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, result = pcall(issecretvalue, value)
    return not ok or type(result) ~= "boolean" or result
end
local function number(value)
    return not secret(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function integer(value, low, high)
    return number(value) and value >= low and value <= high and value % 1 == 0
end
local function text(value)
    if secret(value) or type(value) ~= "string" then return "Unreadable native result" end
    return value:gsub("[\r\n\t]", " "):sub(1, 240)
end
local function describe(value)
    if secret(value) then return "restricted" end
    if value == nil then return "nil" end
    if type(value) == "number" then return number(value) and string.format("number %.9g", value) or "invalid number" end
    if type(value) == "string" then return "string " .. text(value) end
    if type(value) == "boolean" then return value and "true" or "false" end
    return type(value)
end
function R:MarkBlocked(label)
    if secret(label) or type(label) ~= "string" then label = self.activeCall or "unattributed native call" end
    self.blocked[label] = true
    self.lastBlocked = label
    self.reason = "Client blocked " .. label .. "; this call will not be retried this session."
end
local function native(label, fn, ...)
    local diagnostic = "Aura time: " .. label
    if R.blocked[label] or (SH.blockedNativeCalls and SH.blockedNativeCalls[diagnostic]) then error("Client blocked " .. diagnostic, 0) end
    if secret(fn) or type(fn) ~= "function" then error(label .. " is unavailable", 0) end
    local previous = R.activeCall
    R.activeCall = label
    local ok, a, b, c, d
    if SH.CallNativeDiagnostic then ok, a, b, c, d = pcall(SH.CallNativeDiagnostic, SH, diagnostic, fn, ...)
    else ok, a, b, c, d = pcall(fn, ...) end
    R.activeCall = previous
    if R.blocked[label] then error("Client blocked " .. diagnostic, 0) end
    if not ok then error(text(a), 0) end
    return a, b, c, d
end
local function enumerate(pool)
    local packed = native("CDM:EnumerateActive", function(value) return {value:EnumerateActive()} end, pool)
    if secret(packed) or type(packed) ~= "table" then error("Tracker enumeration is unreadable", 0) end
    return packed[1], packed[2], packed[3]
end
local function method(object, name, ...)
    if secret(object) or object == nil then error(name .. " object is unavailable", 0) end
    return native("Frame:" .. name, object[name], object, ...)
end
local function publicMethod(object, name, ...)
    local value = method(object, name, ...)
    if secret(value) then error(name .. " returned a restricted value", 0) end
    return value
end
local function optional(object, name, fallback)
    if secret(object) or object == nil then return nil end
    local fn = object[name]
    if not secret(fn) and type(fn) == "function" then return method(object, name) end
    return object[fallback or name]
end
local function outside()
    local value = native("InCombatLockdown", InCombatLockdown)
    if secret(value) or value ~= false then error("Prepare aura time conditions outside combat", 0) end
end
local function near(a, b)
    return number(a) and number(b) and math.abs(a - b) <= TOLERANCE
end
local function width(frame)
    if publicMethod(frame, "IsShown") ~= true then error("Aura timer signal is hidden", 0) end
    local value = publicMethod(frame, "GetWidth")
    if not number(value) or value <= 0 then error("Aura timer layout width is unreadable", 0) end
    return value
end
local function decode(value, widths)
    if not number(value) then return -1 end
    local found = -1
    for code = 0, 3 do
        if near(value, widths[code]) then
            if found ~= -1 then return -1 end
            found = code
        end
    end
    return found
end
local function setData(encoded, phase)
    -- Only native consumers receive the possibly restricted numeric result.
    native("Data:SetPadding", R.dataFrame.SetPadding, R.dataFrame, 0, 0, 0, 0)
    native("Data:SetFormattedText", R.dataLeft.SetFormattedText, R.dataLeft, FORMAT, encoded)
    native("Data:SetPadding", R.dataFrame.SetPadding, R.dataFrame, 16 + phase * 192, 0, 0, 0)
end
local function setCode(kind, code)
    if kind == "data" then setData(ENCODED[code % 2], math.floor(code / 2))
    else
        native("Commit:SetPadding", R.commitFrame.SetPadding, R.commitFrame, 0, 0, 0, 0)
        native("Commit:SetPadding", R.commitFrame.SetPadding, R.commitFrame, 16 + code * 32, 0, 0, 0)
    end
end
local function tooltip(kind)
    local name = "StandAndHitAuraTime" .. (kind == "data" and "Data" or kind == "commit" and "Commit" or "Compare")
    local frame = R[kind .. "Frame"]
    if not frame then
        frame = native("CreateFrame", CreateFrame, "GameTooltip", name, UIParent, "SecureFrameTemplate")
        R[kind .. "Frame"] = frame
        local left = method(frame, "CreateFontString", name .. "TextLeft1", "ARTWORK", "GameTooltipText")
        local right = method(frame, "CreateFontString", name .. "TextRight1", "ARTWORK", "GameTooltipText")
        method(left, "SetAlpha", 0)
        method(right, "SetAlpha", 0)
        method(frame, "AddFontStrings", left, right)
        R[kind .. "Left"] = left
    end
    method(frame, "SetAlpha", 0)
    method(frame, "SetOwner", UIParent, "ANCHOR_NONE")
    method(frame, "SetPadding", 0, 0, 0, 0)
    method(frame, "SetClampedToScreen", false)
    method(frame, "ClearAllPoints")
    method(frame, "SetPoint", "TOPRIGHT", UIParent, "BOTTOMLEFT", -256, -256)
    method(frame, "SetText", "0", 1, 1, 1, 0, false)
    method(frame, "Show")
    method(frame, "SetAlpha", 0)
    if publicMethod(frame, "IsProtected") ~= true then error("Aura timer signal is not protected", 0) end
end
local function calibrate(kind)
    local values, frame = {}, R[kind .. "Frame"]
    setCode(kind, 3)
    for code = 0, 3 do
        setCode(kind, code)
        local measured = width(frame)
        values[code] = measured
        for previous = 0, code - 1 do
            if math.abs(values[previous] - measured) <= 2 * TOLERANCE then error("Aura timer values have indistinguishable widths", 0) end
        end
    end
    for code = 3, 0, -1 do
        setCode(kind, code)
        if not near(width(frame), values[code]) then error("Aura timer layout did not return to its earlier value", 0) end
    end
    return values
end
local function calibrateResets(widths)
    local resets = {}
    for phase = 0, 1 do
        setData(RESET, phase)
        local measured = width(R.dataFrame)
        for code = 0, 3 do
            if math.abs(measured - widths.data[code]) <= 2 * TOLERANCE then error("Aura timer reset resembles a valid count", 0) end
        end
        resets[phase] = measured
    end
    for phase = 1, 0, -1 do
        setData(RESET, phase)
        if not near(width(R.dataFrame), resets[phase]) then error("Aura timer reset did not return to its earlier value", 0) end
    end
    return resets
end
local function compareWidth(value, padding)
    method(R.compareFrame, "SetPadding", 0, 0, 0, 0)
    method(R.compareLeft, "SetFormattedText", COMPARE_FORMAT, value)
    method(R.compareFrame, "SetPadding", padding, 0, 0, 0)
    return width(R.compareFrame)
end
local function comparisonEqual(value)
    if not secret(value) then
        if not number(value) or value % 1 ~= 0 then return nil end
        return value == 0
    end
    -- An opaque zero prints no digits at precision zero. Nonzero results have
    -- digits; neither the old result nor a dropped formatter may pass the reset.
    if not near(compareWidth(RESET, 32), R.compareReset) then return nil end
    local measured = compareWidth(value, 16)
    if near(measured, R.compareZero) then return true end
    if measured > R.compareZero + TOLERANCE and not near(measured, R.compareReset) and
        not near(measured, R.compareResetData) then return false end
end
local function durationLabel(seconds)
    local format = COOLDOWN_DURATION_SEC
    if secret(format) or type(format) ~= "string" or format == "" then error("Native seconds format is unavailable", 0) end
    local label = native("Format public seconds", string.format, format, seconds)
    if secret(label) or type(label) ~= "string" or label == "" then error("Public seconds formatting returned no text", 0) end
    return label
end
local function decodeText(label)
    if not secret(label) and (type(label) ~= "string" or label == "") then error("Native countdown text is blank or unavailable", 0) end
    local found
    for seconds = 0, 60 do
        local result = native("C_Intl.CompareStrings", C_Intl.CompareStrings, label, R.secondLabels[seconds], R.strength)
        local equal = comparisonEqual(result)
        if equal == nil then error("Native countdown comparison is unreadable", 0) end
        if equal then
            if found ~= nil then error("Native countdown matched more than one seconds label", 0) end
            found = seconds
        end
    end
    if found == nil then error("Countdown text did not match a native whole-second label from 0 through 60", 0) end
    return found
end
local function prepareComparisons()
    if not C_Intl or not Enum or not Enum.CollationStrength then error("Native countdown comparisons are unavailable", 0) end
    local candidate = {strength = Enum.CollationStrength.Identical, secondLabels = {}}
    if not number(candidate.strength) then error("Native countdown comparison option is unavailable", 0) end
    for seconds = 0, 60 do candidate.secondLabels[seconds] = durationLabel(seconds) end
    for seconds = 0, 60 do
        for other = 0, seconds do
            local result = native("C_Intl.CompareStrings", C_Intl.CompareStrings, candidate.secondLabels[seconds], candidate.secondLabels[other], candidate.strength)
            if secret(result) or not number(result) or ((result == 0) ~= (seconds == other)) then error("Public seconds labels are not uniquely distinguishable", 0) end
        end
    end
    local zero = compareWidth(0, 16)
    for _, value in ipairs({-20, -1, 1, 20, RESET}) do
        if math.abs(compareWidth(value, 16) - zero) <= 2 * TOLERANCE then error("Countdown comparison cannot distinguish zero", 0) end
    end
    candidate.compareZero, candidate.compareResetData = zero, compareWidth(RESET, 16)
    candidate.compareReset = compareWidth(RESET, 32)
    if near(candidate.compareReset, candidate.compareZero) or near(candidate.compareReset, candidate.compareResetData) then error("Countdown comparison reset is ambiguous", 0) end
    for _, value in ipairs({0, -1, 1, 20}) do
        if near(compareWidth(value, 32), candidate.compareReset) then error("Countdown reset does not distinguish stale values", 0) end
    end
    for _, invalid in ipairs({"", "unknown", "-1", "1.5", "1:00", "61 seconds"}) do
        for seconds = 0, 60 do
            local result = native("C_Intl.CompareStrings", C_Intl.CompareStrings, invalid, candidate.secondLabels[seconds], candidate.strength)
            if secret(result) or not number(result) or result == 0 then error("An invalid countdown control matched a seconds label", 0) end
        end
    end
    if not near(compareWidth(0, 16), zero) then error("Countdown comparison layout did not remain stable", 0) end
    return candidate
end


local operators = {lt = true, le = true, eq = true, ne = true, ge = true, gt = true}
local function validRequest(request)
    if secret(request) or type(request) ~= "table" then error("Aura time condition is invalid", 0) end
    if secret(request.aura) or type(request.aura) ~= "string" or request.aura:match("^%s*$") then error("Enter an aura name or spell ID for its remaining time", 0) end
    if secret(request.unit) or (request.unit ~= "target" and request.unit ~= "player") then error("Choose target or player for aura time", 0) end
    if secret(request.operator) or not operators[request.operator] then error("Aura time comparison is invalid", 0) end
    if not integer(request.seconds, 0, 60) then error("Aura time threshold must be a whole number from 0 through 60", 0) end
end
local function validateRequests(requests)
    if secret(requests) or type(requests) ~= "table" or #requests > 256 then error("Aura time conditions are invalid", 0) end
    for _, request in ipairs(requests) do validRequest(request) end
end
local function requestKey(request)
    return request.unit .. ":" .. request.aura:match("^%s*(.-)%s*$"):lower()
end
local function spellInfo(value)
    if not C_Spell then error("Spell names are unavailable", 0) end
    local info = native("C_Spell.GetSpellInfo", C_Spell.GetSpellInfo, value)
    if secret(info) or type(info) ~= "table" or secret(info.name) or type(info.name) ~= "string" or info.name == "" then return nil end
    return info
end
local function newRecord(request)
    local input = request.aura:match("^%s*(.-)%s*$")
    if SH.AuraAliases then
        input = SH.AuraAliases.Resolve(input, request.unit, function(id)
            local info = spellInfo(id)
            return info and info.name
        end)
    end
    local id = tonumber(input)
    if id and not integer(id, 1, 2147483647) then error("Aura spell ID is invalid", 0) end
    local info = spellInfo(id or input)
    if id and not info then error("Aura spell ID could not be resolved", 0) end
    local name = info and info.name or input
    local record = {name = name, lower = name:lower(), unit = request.unit, ids = {}}
    if id then record.ids[id] = true end
    if info and integer(info.spellID, 1, 2147483647) then record.ids[info.spellID] = true end
    return record
end
local function family(record, id, learn)
    if not integer(id, 1, 2147483647) then return false end
    if record.ids[id] then return true end
    if learn then
        local info = spellInfo(id)
        if info and info.name:lower() == record.lower then record.ids[id] = true; return true end
    end
    return false
end
local function dedicated(frame, record, learn)
    local info = optional(frame, "GetCooldownInfo", "cooldownInfo")
    local base = optional(frame, "GetBaseSpellID", "baseID")
    if secret(info) or type(info) ~= "table" or secret(base) then return false end
    local ids = {}
    if base ~= nil then ids[#ids + 1] = base end
    for _, key in ipairs({"spellID", "overrideSpellID", "overrideTooltipSpellID"}) do
        local id = info[key]
        if secret(id) then return false end
        if id ~= nil then ids[#ids + 1] = id end
    end
    local linked = info.linkedSpellIDs
    if secret(linked) then return false end
    if type(linked) == "table" then for _, id in ipairs(linked) do ids[#ids + 1] = id end end
    local live = info.linkedSpellID
    if not secret(live) and live ~= nil then ids[#ids + 1] = live end
    if #ids == 0 then return false end
    for _, id in ipairs(ids) do if not family(record, id, learn) then return false end end
    return true, info
end
local function discover(record, learn)
    local found
    for _, name in ipairs({"BuffBarCooldownViewer"}) do
        local viewer = _G[name]
        if not secret(viewer) and viewer then
            local pool = viewer.itemFramePool
            if not secret(pool) and pool and type(pool.EnumerateActive) == "function" then
                local iterator, state, first = enumerate(pool)
                if secret(iterator) or type(iterator) ~= "function" then error("Tracker enumeration is unreadable", 0) end
                local scanned = 0
                for frame in iterator, state, first do
                    scanned = scanned + 1
                    if scanned > 256 then error("Tracker enumeration exceeded its limit", 0) end
                    if not secret(frame) and frame and publicMethod(frame, "IsForbidden") == false then
                        local same, info = dedicated(frame, record, learn)
                        if same then
                            if found then error("Keep one dedicated " .. record.name .. " entry in Tracked Bars", 0) end
                            found = {frame = frame, viewer = viewer, info = info}
                        end
                    end
                end
            end
        end
    end
    if not found then error("Track " .. record.name .. " as a dedicated entry in Blizzard's Tracked Bars", 0) end
    return found
end
local function validateUnitMetadata(entry, record)
    local selfAura = entry.info.selfAura
    if not secret(selfAura) and type(selfAura) == "boolean" and selfAura ~= (record.unit == "player") then
        error("Choose the correct player buff or target debuff source for " .. record.name, 0)
    end
end
local function now()
    local value = native("GetTime", GetTime)
    if not number(value) or value < 0 then error("Native refresh clock is unreadable", 0) end
    return value
end
local function invalidateIdentity(timestamp)
    R.targetKnown = false
    R.targetRevision = R.targetRevision + 1
    R.targetChangedTick = R.uiTick
    R.targetChangedAt = number(timestamp) and timestamp or math.huge
    for _, observed in pairs(R.hookedFrames) do observed.reconciled = nil end
end
local function syncTargetContext()
    local guid = native("UnitGUID", UnitGUID, "target")
    if secret(guid) or (guid ~= nil and type(guid) ~= "string") then
        invalidateIdentity(now())
        return nil
    end
    local key = guid or false
    if not R.targetKnown or R.targetGUID ~= key then invalidateIdentity(now()) end
    R.targetKnown, R.targetGUID = true, key
    return guid
end
local function eventCall(label, fn, ...)
    -- Event-time restrictions must not latch the physical click's API label.
    if R.blocked[label] then return false, "Client previously blocked " .. label end
    local previous = R.activeCall
    R.activeCall = label
    local ok, value = pcall(fn, ...)
    R.activeCall = previous
    if R.blocked[label] then return false, "Client blocked " .. label end
    return ok, value
end
local function onTargetEvent()
    R.targetEventSerial = R.targetEventSerial + 1
    local previous, before = R.targetGUID, R.targetRevision
    local guidOK, guid = eventCall("Target event:UnitGUID", UnitGUID, "target")
    local clockOK, timestamp = eventCall("Target event:GetTime", GetTime)
    local validGUID = guidOK and not secret(guid) and (guid == nil or type(guid) == "string")
    local validClock = clockOK and number(timestamp) and timestamp >= 0
    R.targetEventPreviousKey = previous
    R.targetEventKey = validGUID and (guid or false) or nil
    R.targetEventGUID = guidOK and describe(guid) or "getter error: " .. text(guid)
    R.targetEventClock = validClock and timestamp or nil
    R.targetEventError = nil
    if not guidOK then R.targetEventError = "UnitGUID: " .. text(guid) end
    if not clockOK then R.targetEventError = (R.targetEventError and R.targetEventError .. "; " or "") .. "GetTime: " .. text(timestamp) end
    if validGUID and R.targetKnown and (guid or false) == previous then
        -- Blizzard also deduplicates unchanged GUIDs. Its completed aura cache
        -- remains valid; the event serial still aborts an interrupted capture.
        R.sameGUIDEvents = R.sameGUIDEvents + 1
        R.targetEventOutcome = "readable unchanged GUID; identity epoch preserved"
    elseif validGUID then
        invalidateIdentity(validClock and timestamp or nil)
        if validClock then
            R.targetKnown, R.targetGUID = true, guid or false
            R.changedGUIDEvents = R.changedGUIDEvents + 1
            R.targetEventOutcome = "identity changed or recovered; fresh native completion required"
        else
            R.uncertainGUIDEvents = R.uncertainGUIDEvents + 1
            R.targetEventOutcome = "uncertain identity or event clock; fresh public identity and native completion required"
        end
    else
        -- Event callbacks can restrict getters that are public on a click.
        -- Keep the verified baseline; the click must confirm it, and mandatory
        -- native OnNewTarget observation rejects intervening viewer transitions.
        R.uncertainGUIDEvents = R.uncertainGUIDEvents + 1
        R.eventIdentityPending = true
        for _, observed in pairs(R.hookedFrames) do observed.reconciled = nil end
        R.targetEventOutcome = "event identity unreadable; awaiting public click and native target-generation proof"
    end
    R.targetEventPrevious = describe(previous)
    R.targetEventEpochBefore, R.targetEventEpochAfter = before, R.targetRevision
end
local function watchNativeTargetRefresh(frame)
    if R.hookedFrames[frame] then return end
    local retained = 0
    for _ in pairs(R.hookedFrames) do retained = retained + 1 end
    if retained >= 256 then error("Native tracker hook limit reached; reload the UI", 0) end
    if secret(frame.RefreshAuraInstance) or type(frame.RefreshAuraInstance) ~= "function" then error("Tracker has no native aura refresh to observe", 0) end
    if secret(frame.ResetCooldownData) or type(frame.ResetCooldownData) ~= "function" then error("Tracker has no native source reset to observe", 0) end
    if secret(frame.OnNewTarget) or type(frame.OnNewTarget) ~= "function" then error("Tracker has no native target transition to observe", 0) end
    if secret(frame.RefreshData) or type(frame.RefreshData) ~= "function" then error("Tracker has no complete native data refresh to observe", 0) end
    R.nextFrameID = R.nextFrameID + 1
    local observed = {id = R.nextFrameID, sequence = 0, generation = 1, resets = 0, targetChanges = 0,
        lastReject = "no native refresh observed"}
    native("hooksecurefunc RefreshAuraInstance", hooksecurefunc, frame, "RefreshAuraInstance", function()
        if not R.ready then return end
        -- Native hook context may restrict otherwise readable getters. Observe
        -- completion using owned metadata only: no GUID, clock or cache APIs.
        if observed.sequence >= 2147483647 then
            observed.lastReject = "native refresh sequence exhausted; reload the UI"
            R.targetStamps[frame] = nil
            return
        end
        observed.sequence = observed.sequence + 1
        observed.guid, observed.epoch = R.targetGUID, R.targetRevision
        observed.refreshEventSerial = R.targetEventSerial
        observed.tick, observed.time = R.uiTick, R.uiTime
        observed.stampedGeneration = observed.generation
        observed.reconciled = nil
        observed.lastReject = "awaiting physical-click validation"
        R.targetStamps[frame] = observed
    end)
    native("hooksecurefunc ResetCooldownData", hooksecurefunc, frame, "ResetCooldownData", function()
        if not R.ready then return end
        observed.generation = observed.generation + 1
        observed.resets = observed.resets + 1
        observed.reconciled, observed.completedGeneration = nil, nil
        observed.lastReject = "source reset; waiting for a native refresh"
        R.targetStamps[frame] = nil
    end)
    native("hooksecurefunc OnNewTarget", hooksecurefunc, frame, "OnNewTarget", function()
        if not R.ready then return end
        -- Native CDM calls this only for its own observed target transition.
        -- This also catches A -> B -> A hidden from our raw-event GUID reads.
        observed.generation = observed.generation + 1
        observed.targetChanges = observed.targetChanges + 1
        observed.transitionGeneration, observed.transitionSequence = observed.generation, observed.sequence
        observed.transitionEventSerial = R.targetEventSerial
        observed.completedGeneration, observed.reconciled = nil, nil
        observed.pendingTargetBarrier = true
        observed.lastReject = "native target transition; waiting for the owned clock barrier"
        R.pendingTargetBarriers = true
        R.targetStamps[frame] = nil
    end)
    if secret(frame.RefreshCooldownInfo) or type(frame.RefreshCooldownInfo) ~= "function" then error("Tracked Bar has no native countdown refresh to observe", 0) end
    native("hooksecurefunc RefreshCooldownInfo", hooksecurefunc, frame, "RefreshCooldownInfo", function()
        if not R.ready then return end
        observed.timerSequence = (observed.timerSequence or 0) + 1
        observed.timerTime, observed.timerGeneration = R.uiTime, observed.generation
    end)
    native("hooksecurefunc RefreshData", hooksecurefunc, frame, "RefreshData", function()
        if not R.ready then return end
        if observed.stampedGeneration == observed.generation and observed.sequence > (observed.transitionSequence or -1)
            and observed.timerGeneration == observed.generation then
            observed.completedGeneration, observed.completedSequence = observed.generation, observed.sequence
            observed.completedEventSerial = R.targetEventSerial
        end
    end)
    R.hookedFrames[frame] = observed
end
local function watchActivePoolFrames()
    -- Forever exposes active pool enumeration only. Retain these observations
    -- across inactive reuse; newly created/unseen frames require another Prepare.
    for _, name in ipairs({"BuffBarCooldownViewer"}) do
        local viewer = _G[name]
        if not secret(viewer) and viewer then
            local pool = viewer.itemFramePool
            if not secret(pool) and pool and type(pool.EnumerateActive) == "function" then
                local iterator, state, first = enumerate(pool)
                if secret(iterator) or type(iterator) ~= "function" then error("Tracker enumeration is unreadable", 0) end
                local scanned = 0
                for frame in iterator, state, first do
                    scanned = scanned + 1
                    if scanned > 256 then error("Tracker enumeration exceeded its limit", 0) end
                    if not secret(frame) and frame and publicMethod(frame, "IsForbidden") == false then watchNativeTargetRefresh(frame) end
                end
            end
        end
    end
end
local function updateOwnedClock()
    if not R.ready then return end
    if R.uiTick >= 2147483647 then R.uiTime = nil; R.clockError = "Owned UI clock exhausted; reload the UI"; return end
    R.uiTick = R.uiTick + 1
    local ok, value = pcall(GetTime)
    if ok and number(value) and value >= 0 then R.uiTime, R.clockError = value, nil
    else R.uiTime, R.clockError = nil, ok and "Owned UI clock was restricted or invalid" or text(value) end
    if R.pendingTargetBarriers and R.uiTime then
        for _, observed in pairs(R.hookedFrames) do
            if observed.pendingTargetBarrier then
                observed.targetChangedAt, observed.targetChangedTick = R.uiTime, R.uiTick
                observed.pendingTargetBarrier = false
            end
        end
        R.pendingTargetBarriers = false
    end
end
local function unitContext(unit)
    local exists = native("UnitExists", UnitExists, unit)
    local dead = native("UnitIsDeadOrGhost", UnitIsDeadOrGhost, unit)
    if secret(exists) or exists ~= true or secret(dead) or dead ~= false then error("Aura timers require a living unit", 0) end
    if unit == "target" then
        local visible = native("UnitIsVisible", UnitIsVisible, unit)
        local hostile = native("UnitCanAttack", UnitCanAttack, "player", unit)
        if secret(visible) or visible ~= true or secret(hostile) or hostile ~= true then error("Target aura timers require a visible enemy", 0) end
        local guid = syncTargetContext()
        if type(guid) ~= "string" then error("Target identity is unreadable", 0) end
        return guid
    end
end
local function inactive(entry, unit, cached, instance, auraUnit, shown)
    if cached ~= nil or secret(instance) or instance ~= nil or secret(auraUnit) or auraUnit ~= nil or shown ~= false then return false end
    local frame, info = entry.frame, entry.info
    local edit = optional(frame, "HasEditModeData", "hasEditModeData")
    local hidden, allowed, hasAura, selfAura = frame.hideWhenInactive, frame.allowHideWhenInactive, info.hasAura, info.selfAura
    return not secret(edit) and edit == false and not secret(hidden) and hidden == true and
        not secret(allowed) and allowed == true and not secret(hasAura) and hasAura == true and
        not secret(selfAura) and selfAura == (unit == "player")
end
local function auraField(aura, key)
    return native("Aura data." .. key, function() return aura[key] end)
end
local function validateAura(aura, instance, record)
    if secret(aura) or type(aura) ~= "table" then error("Aura cache is absent or restricted as a whole", 0) end
    local id, auraInstance = auraField(aura, "spellId"), auraField(aura, "auraInstanceID")
    if not secret(id) and not family(record, id, false) then error("Cached aura belongs to a different spell", 0) end
    if not secret(auraInstance) and not integer(auraInstance, 1, 2147483647) then error("Cached aura instance is missing", 0) end
    if not secret(instance) and not secret(auraInstance) and instance ~= auraInstance then error("Cached aura and tracker instance differ", 0) end
    local harmful, helpful = auraField(aura, "isHarmful"), auraField(aura, "isHelpful")
    local expected, opposite
    if record.unit == "target" then expected, opposite = harmful, helpful else expected, opposite = helpful, harmful end
    if (not secret(expected) and expected ~= nil and expected ~= true) or (not secret(opposite) and opposite == true) then error("Cached aura has the wrong buff/debuff type", 0) end
    if record.unit == "target" then
        local caster = auraField(aura, "sourceUnit")
        if not secret(caster) and caster ~= nil and caster ~= "player" then error("Target aura is not from the player", 0) end
    end
end
local function durationFont(frame)
    local font = optional(frame, "GetDurationFontString")
    if not font and not secret(frame.Bar) and frame.Bar then font = frame.Bar.Duration end
    if secret(font) or font == nil then error("Tracked Bar duration text is unavailable", 0) end
    if publicMethod(font, "IsShown") ~= true then error("Enable timer text for the aura in Tracked Bars", 0) end
    return font
end
local function countdownText(frame, observed)
    if not observed.timerTime or observed.timerGeneration ~= observed.generation or not observed.timerSequence then
        error("Waiting for Blizzard to refresh the displayed aura countdown", 0)
    end
    local age = now() - observed.timerTime
    if age < 0 or age > 0.5 then error("Native countdown has not refreshed within the last half-second", 0) end
    local font = durationFont(frame)
    local label = method(font, "GetText")
    return label, font
end
local function viewerTargetMatches(viewer, guid)
    local value = native("CDM viewer.currentTarget", function() return viewer.currentTarget end)
    if not secret(value) then return type(value) == "string" and value == guid end
    local result = native("C_Intl.CompareStrings viewer target", C_Intl.CompareStrings, value, guid, R.strength)
    return comparisonEqual(result) == true
end
local function reconcileTargetOrder(observed, stamp)
    if not observed or not stamp or not R.targetKnown or type(R.targetGUID) ~= "string" then return false end
    if observed.pendingTargetBarrier or stamp.stampedGeneration ~= observed.generation then return false end
    local prior = observed.reconciled
    if prior and prior.guid == R.targetGUID and prior.epoch == R.targetRevision
        and prior.generation == observed.generation and prior.sequence == observed.sequence then
        R.reconciliation = prior.reason
        return true
    end
    if observed.transitionGeneration ~= observed.generation or observed.completedGeneration ~= observed.generation
        or observed.completedSequence ~= observed.sequence or observed.sequence <= (observed.transitionSequence or math.huge) then return false end
    if observed.acceptedEpoch and observed.acceptedEpoch ~= R.targetRevision
        and observed.generation <= (observed.acceptedGeneration or math.huge) then return false end
    local sameEvent = stamp.epoch == R.targetRevision and stamp.guid == R.targetGUID
        and observed.refreshEventSerial == R.targetEventSerial and observed.completedEventSerial == R.targetEventSerial
        and observed.transitionEventSerial == R.targetEventSerial
    local nativeFirst = stamp.epoch + 1 == R.targetRevision
        and observed.refreshEventSerial + 1 == R.targetEventSerial
        and observed.completedEventSerial == observed.refreshEventSerial
        and observed.transitionEventSerial == observed.refreshEventSerial
        and R.targetEventPreviousKey == stamp.guid and R.targetEventKey == R.targetGUID
    if not sameEvent and not nativeFirst then return false end
    R.reconciliation = nativeFirst and "native batch completed before owned target event; native viewer identity verified"
        or "owned target event preceded complete native batch; native viewer identity verified"
    observed.reconciled = {guid = R.targetGUID, epoch = R.targetRevision, generation = observed.generation,
        sequence = observed.sequence, reason = R.reconciliation}
    return true
end
local function bootstrapped(entry, observed, cached, guid)
    if observed.bootstrapGeneration ~= observed.generation or observed.bootstrapCache ~= cached then return false end
    if R.uiTick <= (observed.bootstrapTick or math.huge) or now() <= (observed.bootstrapAt or math.huge) then return false end
    if entry.record.unit == "target" then
        return observed.bootstrapGUID == guid and observed.bootstrapEpoch == R.targetRevision
    end
    return true
end
local function sourceFresh(entry, observed, cached, guid)
    local stamp = R.targetStamps[entry.frame]
    if observed.pendingTargetBarrier then return false end
    if entry.record.unit == "player" then
        return (stamp == observed and observed.stampedGeneration == observed.generation) or bootstrapped(entry, observed, cached, guid)
    end
    if not viewerTargetMatches(entry.viewer, guid) then return false end
    local fresh = stamp == observed and observed.stampedGeneration == observed.generation and R.targetKnown and
        observed.guid == guid and observed.epoch == R.targetRevision and number(observed.time) and
        observed.time > (R.targetChangedAt or math.huge) and observed.tick > (R.targetChangedTick or 0) and
        (not observed.targetChangedAt or (observed.time > observed.targetChangedAt and observed.tick > observed.targetChangedTick))
    return fresh or reconcileTargetOrder(observed, stamp) or bootstrapped(entry, observed, cached, guid)
end
local function readSource(record, guid)
    local entry = discover(record, false)
    validateUnitMetadata(entry, record)
    entry.record = record
    local frame, observed = entry.frame, R.hookedFrames[entry.frame]
    if not observed then error("Aura tracker changed; Prepare outside combat", 0) end
    local cached = optional(frame, "GetAuraDataCached", "auraDataCached")
    if secret(cached) then error("Aura cache is restricted as a whole", 0) end
    if observed.readSequence == observed.sequence and observed.readCache ~= cached then error("Aura cache changed without a native refresh", 0) end
    local instance = optional(frame, "GetAuraSpellInstanceID", "auraInstanceID")
    local auraUnit = optional(frame, "GetAuraDataUnit", "auraDataUnit")
    local shown = publicMethod(frame, "IsShown")
    if publicMethod(entry.viewer, "IsVisible") ~= true then error("Aura time viewer is not visible", 0) end
    if record.unit == "target" then
        local registered = optional(frame, "NeedsTargetUpdateRegistration", "targetRegistration")
        if secret(registered) or registered ~= true then error("Aura tracker does not attest native target updates", 0) end
    end
    if not sourceFresh(entry, observed, cached, guid) then error("Waiting for the current unit's native aura timer refresh", 0) end
    local proof = {record = record, frame = frame, viewer = entry.viewer, cache = cached, sequence = observed.sequence,
        generation = observed.generation, guid = guid, epoch = R.targetRevision, eventSerial = R.targetEventSerial}
    if not secret(auraUnit) and auraUnit == record.unit and (secret(instance) or integer(instance, 1, 2147483647)) then
        if shown ~= true then error("Present aura tracker is hidden", 0) end
        validateAura(cached, instance, record)
        local label, font = countdownText(frame, observed)
        proof.font, proof.timerSequence = font, observed.timerSequence
        return decodeText(label), proof
    end
    if inactive(entry, record.unit, cached, instance, auraUnit, shown) then
        proof.absent = true
        return 0, proof
    end
    error("No confirmed current aura timer or inactive state is available", 0)
end
local function ownedFence(proof)
    if proof.record.unit == "target" and (not R.targetKnown or R.targetGUID ~= proof.guid or
        R.targetRevision ~= proof.epoch or R.targetEventSerial ~= proof.eventSerial) then error("Target changed during the aura time condition", 0) end
    local observed = R.hookedFrames[proof.frame]
    if not observed or observed.sequence ~= proof.sequence or observed.generation ~= proof.generation or
        (proof.font and observed.timerSequence ~= proof.timerSequence) or
        (proof.record.unit == "target" and observed.pendingTargetBarrier) then error("Native aura source changed during the aura time condition", 0) end
    return observed
end
local function validateProof(proof)
    local guid = unitContext(proof.record.unit)
    if proof.record.unit == "target" and guid ~= proof.guid then error("Target changed during the aura time condition", 0) end
    ownedFence(proof)
    local entry = discover(proof.record, false)
    validateUnitMetadata(entry, proof.record)
    entry.record = proof.record
    if entry.frame ~= proof.frame or entry.viewer ~= proof.viewer then error("Aura tracker changed during the aura time condition", 0) end
    local cached = optional(proof.frame, "GetAuraDataCached", "auraDataCached")
    if secret(cached) or cached ~= proof.cache then error("Aura cache changed during the aura time condition", 0) end
    if publicMethod(entry.viewer, "IsVisible") ~= true then error("Aura viewer became hidden", 0) end
    if proof.record.unit == "target" then
        local registered = optional(proof.frame, "NeedsTargetUpdateRegistration", "targetRegistration")
        if secret(registered) or registered ~= true then error("Native target update registration changed", 0) end
        if not viewerTargetMatches(entry.viewer, guid) then error("Native viewer target changed", 0) end
    end
    if proof.font and durationFont(proof.frame) ~= proof.font then error("Native countdown source changed", 0) end
    local observed = ownedFence(proof)
    if not sourceFresh(entry, observed, cached, guid) then error("Native aura source lost its freshness proof", 0) end
    observed = ownedFence(proof)
    observed.readSequence, observed.readCache = proof.sequence, proof.cache
    if proof.record.unit == "target" then observed.acceptedEpoch, observed.acceptedGeneration = proof.epoch, proof.generation end
end
local function predicate(count, operator, value)
    if operator == "lt" then return count < value end
    if operator == "le" then return count <= value end
    if operator == "eq" then return count == value end
    if operator == "ne" then return count ~= value end
    if operator == "ge" then return count >= value end
    return count > value
end
local function publishWidths(button, widths)
    for code = 0, 3 do
        method(button, "SetAttribute", "sh-aura-time-data-width" .. code, widths.data[code])
        method(button, "SetAttribute", "sh-aura-time-commit-width" .. code, widths.commit[code])
    end
    for code = 0, 3 do
        if not near(publicMethod(button, "GetAttribute", "sh-aura-time-data-width" .. code), widths.data[code]) or
            not near(publicMethod(button, "GetAttribute", "sh-aura-time-commit-width" .. code), widths.commit[code]) then error("Aura time calibration could not be applied to a button", 0) end
    end
end
local function hideOwned()
    outside()
    for _, kind in ipairs({"data", "commit", "compare"}) do if R[kind .. "Frame"] then method(R[kind .. "Frame"], "Hide") end end
end
local function lifecycle()
    if R.events then method(R.events, "SetScript", "OnUpdate", updateOwnedClock); return end
    R.events = native("CreateFrame", CreateFrame, "Frame")
    for _, event in ipairs({"ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_TARGET_CHANGED", "PLAYER_LOGOUT"}) do method(R.events, "RegisterEvent", event) end
    method(R.events, "SetScript", "OnEvent", function(_, event, owner)
        if event == "PLAYER_TARGET_CHANGED" and R.ready then
            local ok, failure = pcall(onTargetEvent)
            if not ok then invalidateIdentity(nil); R.targetEventError = text(failure) end
        elseif event == "PLAYER_LOGOUT" then R:Cleanup()
        elseif not secret(owner) and owner == addonName and R.activeCall then R:MarkBlocked(R.activeCall) end
    end)
    method(R.events, "SetScript", "OnUpdate", updateOwnedClock)
end
local function bootstrapCurrent(record)
    local entry = discover(record, false)
    local observed = R.hookedFrames[entry.frame]
    local cached = optional(entry.frame, "GetAuraDataCached", "auraDataCached")
    if secret(cached) then return end
    local instance = optional(entry.frame, "GetAuraSpellInstanceID", "auraInstanceID")
    local auraUnit = optional(entry.frame, "GetAuraDataUnit", "auraDataUnit")
    local shown = publicMethod(entry.frame, "IsShown")
    if publicMethod(entry.viewer, "IsVisible") ~= true then return end
    if record.unit == "target" then
        local registered = optional(entry.frame, "NeedsTargetUpdateRegistration", "targetRegistration")
        if not R.targetKnown or not R.targetGUID or secret(registered) or registered ~= true then return end
        local viewerGUID = entry.viewer.currentTarget
        if secret(viewerGUID) or viewerGUID ~= R.targetGUID then return end
    end
    local present = not secret(auraUnit) and auraUnit == record.unit and (secret(instance) or integer(instance, 1, 2147483647)) and
        type(cached) == "table" and shown == true
    if present or inactive(entry, record.unit, cached, instance, auraUnit, shown) then
        -- Preparation establishes a new public cache baseline. Native updates
        -- may have happened while the last binding (and its observers) was off.
        observed.readSequence, observed.readCache, observed.reconciled = nil, nil, nil
        observed.bootstrapGUID, observed.bootstrapEpoch, observed.bootstrapGeneration = R.targetGUID, R.targetRevision, observed.generation
        observed.bootstrapCache = cached
        observed.bootstrapAt, observed.bootstrapTick = now(), R.uiTick
    end
end
local function prepareRecords(requests)
    validateRequests(requests)
    local prepared = {}
    for _, binding in pairs(R.bindings) do
        for _, spec in ipairs(binding) do
            prepared[spec.key] = spec.record
            local entry = discover(spec.record, true)
            validateUnitMetadata(entry, spec.record)
            durationFont(entry.frame)
        end
    end
    for _, request in ipairs(requests) do
        local key = requestKey(request)
        prepared[key] = prepared[key] or R.prepared[key] or newRecord(request)
        local entry = discover(prepared[key], true)
        validateUnitMetadata(entry, prepared[key])
        durationFont(entry.frame)
    end
    return prepared
end
function R:Prepare(requests)
    local permitted, reason = pcall(outside)
    if not permitted then self.reason = text(reason); return false, self.reason end
    -- Invalid new metadata must not disable already attached, independent
    -- buttons. Close the shared gate only when starting layout mutation.
    local metadataOK, prepared = pcall(prepareRecords, requests)
    if not metadataOK then self.reason = text(prepared); return false, self.reason end
    self.ready = false
    local ok, err = pcall(function()
        if self.commitFrame then method(self.commitFrame, "SetAttribute", "sh-aura-time-ready", false) end
        lifecycle()
        syncTargetContext()
        watchActivePoolFrames()
        for frame, observed in pairs(self.hookedFrames) do observed.frame = frame end
        for _, record in pairs(prepared) do bootstrapCurrent(record) end
        tooltip("data"); tooltip("commit"); tooltip("compare")
        method(self.commitFrame, "SetAttribute", "sh-aura-time-ready", false)
        local comparisons = prepareComparisons()
        local widths = {data = calibrate("data"), commit = calibrate("commit")}
        local resets = calibrateResets(widths)
        if not near(compareWidth(RESET, 32), comparisons.compareReset) or not near(compareWidth(0, 16), comparisons.compareZero) then error("Aura time comparison layout changed during preparation", 0) end
        setCode("data", 0); setCode("commit", 0)
        if not near(width(self.dataFrame), widths.data[0]) or not near(width(self.commitFrame), widths.commit[0]) then error("Aura time initial layout failed", 0) end
        for button in pairs(self.bindings) do publishWidths(button, widths) end
        self.widths, self.resetWidths, self.prepared = widths, resets, prepared
        for key, value in pairs(comparisons) do self[key] = value end
        method(self.commitFrame, "SetAttribute", "sh-aura-time-ready", true)
    end)
    if not ok then self.reason = text(err); pcall(hideOwned); return false, self.reason end
    self.ready, self.reason = true, nil
    return true
end
function R:Attach(button, requests)
    local ok, err = pcall(function()
        outside()
        if not self.ready then error(self.reason or "Aura timers are not prepared", 0) end
        validateRequests(requests)
        local binding = {}
        for index, request in ipairs(requests) do
            local record = self.prepared[requestKey(request)]
            if not record then error("Aura time condition has not been prepared", 0) end
            binding[index] = {record = record, key = requestKey(request), operator = request.operator, value = request.seconds}
        end
        native("SecureHandlerSetFrameRef", SecureHandlerSetFrameRef, button, "aura-time-data", self.dataFrame)
        native("SecureHandlerSetFrameRef", SecureHandlerSetFrameRef, button, "aura-time-commit", self.commitFrame)
        publishWidths(button, self.widths)
        self.bindings[button] = binding
    end)
    if not ok then self.reason = text(err); return false, self.reason end
    self.reason = nil
    return true
end
function R:Refresh(button, index, phase)
    local publishing = false
    local ok, err = pcall(function()
        if not self.ready then error(self.reason or "Aura timers are not prepared", 0) end
        if not integer(index, 1, 256) or not integer(phase, 0, 1) then error("Invalid aura time read", 0) end
        local binding = self.bindings[button]
        local spec = binding and binding[index]
        if not spec then error("Aura time condition is not attached", 0) end
        local eventSerial = self.targetEventSerial
        local guid = unitContext(spec.record.unit)
        local count, proof = readSource(spec.record, guid)
        if spec.record.unit == "target" and eventSerial ~= self.targetEventSerial then error("Target event interrupted the aura time read", 0) end
        validateProof(proof)
        local pass = predicate(count, spec.operator, spec.value)
        setData(RESET, phase)
        if not near(width(self.dataFrame), self.resetWidths[phase]) then error("Aura time data did not reset", 0) end
        setData(ENCODED[pass and 1 or 0], phase)
        local code = decode(width(self.dataFrame), self.widths.data)
        if code < 0 or math.floor(code / 2) ~= phase or (code % 2 == 1) ~= pass then error("Aura time signal is stale or invalid", 0) end
        validateProof(proof)
        publishing = true
        setCode("commit", code)
        if not near(width(self.commitFrame), self.widths.commit[code]) then error("Aura time acknowledgment did not update", 0) end
        validateProof(proof)
    end)
    if not ok then
        -- A callback may invalidate the proof during the final native write.
        -- Erase data so the restricted reader cannot accept that acknowledgment.
        if publishing then pcall(setData, RESET, phase) end
        self.reason = text(err)
        return false, self.reason
    end
    self.reason = nil
    return true
end
function R:Cleanup()
    local ok, err = pcall(function()
        outside()
        self.ready = false
        self.prepared = {}
        self.pendingTargetBarriers = false
        for frame, observed in pairs(self.hookedFrames) do
            -- Hooks remain installed but do no work until the next preparation.
            -- Do not reuse old cache, target or countdown proofs on that restart.
            observed.generation = observed.generation + 1
            observed.readSequence, observed.readCache, observed.reconciled = nil, nil, nil
            observed.bootstrapGeneration, observed.bootstrapCache = nil, nil
            observed.acceptedEpoch, observed.acceptedGeneration = nil, nil
            observed.completedGeneration, observed.transitionGeneration = nil, nil
            observed.timerTime, observed.timerGeneration, observed.timerSequence = nil, nil, nil
            observed.pendingTargetBarrier = false
            self.targetStamps[frame] = nil
        end
        if self.commitFrame then method(self.commitFrame, "SetAttribute", "sh-aura-time-ready", false) end
        if self.events then method(self.events, "SetScript", "OnUpdate", nil) end
        hideOwned()
    end)
    self.reason = ok and "Aura time conditions have not been prepared." or text(err)
    if not ok then return false, self.reason end
    return true
end
function R:Release(button)
    local ok, err = pcall(outside)
    if not ok then return false, text(err) end
    self.bindings[button] = nil
    if not next(self.bindings) then return self:Cleanup() end
    return true
end

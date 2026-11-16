local _, SH = ...

-- A click reads an ordinary clock through the same fresh, calibrated tooltip
-- protocol as combo points. No timer callback selects or casts a spell.
local P = {ready = false, reason = "Ping Delay has not been prepared.",
    widths = {data = {}, commit = {}}, bindings = {}, sources = {}, successes = {}, recoveryAnchors = {}}
SH.PingDelay = P
local TOLERANCE, MAX_RULES, EMPTY = 0.5, 32, {}
local MAX_COOLDOWN, MAX_HISTORY = 86400, 256

local BinarySignal = {}
SH.BinarySignal = BinarySignal

-- Both readers require a fresh acknowledgment from their own pair of frames.
local readBinary = [[
    local data, commit = self:GetFrameRef("$prefix-data"), self:GetFrameRef("$prefix-commit")
    if not data or not commit or data:IsShown() ~= true or commit:IsShown() ~= true then return false end
    if commit:GetAttribute("sh-binary-ready") ~= true then return false end
    local oldWidth, oldCode = commit:GetWidth(), -1
    if rawtype(oldWidth) ~= "number" then return false end
    for code = 0, 3 do
        local width = commit:GetAttribute("sh-width" .. code)
        if rawtype(width) ~= "number" then return false end
        if math.abs(width - oldWidth) <= 0.5 then
            if oldCode ~= -1 then return false end
            oldCode = code
        end
    end
    if oldCode < 0 then return false end
    local phase = oldCode < 2 and 1 or 0
    self:CallMethod("$method", $args)
    if data:IsShown() ~= true or commit:IsShown() ~= true then return false end
    local dataWidth, commitWidth = data:GetWidth(), commit:GetWidth()
    if rawtype(dataWidth) ~= "number" or rawtype(commitWidth) ~= "number" then return false end
    local dataCode, commitCode = -1, -1
    for code = 0, 3 do
        local expectedData = data:GetAttribute("sh-width" .. code)
        local expectedCommit = commit:GetAttribute("sh-width" .. code)
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
    self:SetAttribute("$result", commitCode % 2 == 1)
    return true
]]
function BinarySignal.Reader(prefix, result, method, args)
    return (readBinary:gsub("%$(%a+)", {prefix = prefix, result = result, method = method, args = args}))
end

P.READ_SNIPPET = [[
    self:SetAttribute("sh-ping-pass", nil)
    local index, arm = ...
    if rawtype(index) ~= "number" or index < 1 or index > 32 or index % 1 ~= 0 then return false end
    if arm ~= nil and rawtype(arm) ~= "boolean" then return false end
    local native = self:GetFrameRef("ping-native" .. index)
    local slot = self:GetAttribute("sh-ping-slot" .. index)
    local expected = self:GetAttribute("sh-ping-spell-id" .. index)
    local size = self:GetAttribute("sh-ping-bar-size" .. index)
    if not native or native:IsVisible() ~= true or rawtype(slot) ~= "number"
        or rawtype(expected) ~= "number" or rawtype(size) ~= "number" then return false end
    local id, actual = native:GetID()
    if rawtype(id) ~= "number" then return false end
    if id > 0 then
        local page = native:GetEffectiveAttribute("actionpage") or GetActionBarPage()
        if rawtype(page) ~= "number" then return false end
        actual = id + (page - 1) * size
    else actual = native:GetEffectiveAttribute("action") or 1 end
    if actual ~= slot then return false end
    local kind, spellID = GetActionInfo(slot)
    if kind ~= "spell" or spellID ~= expected then return false end
]] .. BinarySignal.Reader("ping", "sh-ping-pass", "RefreshPingDelay", "index, phase, arm")

local function secret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, result = pcall(issecretvalue, value)
    return not ok or type(result) ~= "boolean" or result
end
local function number(value)
    return not secret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function integer(value, low, high)
    return number(value) and value >= low and value <= high and value % 1 == 0
end
local function message(value)
    if secret(value) or type(value) ~= "string" then return "Ping Delay signal is unavailable" end
    return value:gsub("[\r\n\t]", " "):sub(1, 300)
end
local function combat()
    if type(InCombatLockdown) ~= "function" then error("Combat state is unavailable", 0) end
    local value = InCombatLockdown()
    if secret(value) or type(value) ~= "boolean" then error("Combat state is unreadable", 0) end
    return value
end
local function outside()
    if combat() then error("Prepare Ping Delay outside combat", 0) end
end
local function callFor(component, name, fn, ...)
    if secret(fn) or type(fn) ~= "function" then error(name .. " is unavailable", 0) end
    local label = component .. ": " .. name
    if SH.blockedNativeCalls and SH.blockedNativeCalls[label] and combat() then
        error("Client blocked " .. label .. "; " .. component .. " is unavailable in combat this session", 0)
    end
    if SH.CallNativeDiagnostic then return SH:CallNativeDiagnostic(label, fn, ...) end
    return fn(...)
end
local function nativeCall(name, fn, ...)
    return callFor("Ping Delay", name, fn, ...)
end
local function frameCall(component, object, name, ...)
    if secret(object) or object == nil then error(name .. " is unavailable", 0) end
    local value = callFor(component, "Frame:" .. name, object[name], object, ...)
    if secret(value) then error(name .. " returned an unreadable result", 0) end
    return value
end
local function required(object, name, ...)
    return frameCall("Ping Delay", object, name, ...)
end
local function now()
    local value = nativeCall("GetTime", GetTime)
    if not number(value) or value < 0 or (P.lastTime and value < P.lastTime) then
        error("Spell timing clock is unreadable or moved backwards. Reload after the clock recovers.", 0)
    end
    P.lastTime = value
    return value
end
local function serverNow()
    local value = nativeCall("GetServerTime", GetServerTime)
    if not integer(value, 1, 1000000000000) or (P.lastServerTime and value < P.lastServerTime) then
        error("Manual Cooldown server clock is unreadable or moved backwards. Reload after the clock recovers.", 0)
    end
    P.lastServerTime = value
    return value
end
local function attachedSpell(spellID, requests)
    for _, request in pairs(requests or EMPTY) do
        if request.source.spellID == spellID then return true end
    end
    for _, binding in pairs(P.bindings) do
        for _, record in pairs(binding) do
            if record.source.spellID == spellID then return true end
        end
    end
    return false
end
local function trimHistory(timestamp, incoming, requests)
    local count = 0
    for spellID, success in pairs(P.successes) do
        if success + MAX_COOLDOWN < timestamp then
            P.successes[spellID] = nil
            if P.saved then P.saved[spellID] = nil end
        else
            count = count + 1
        end
    end
    -- At most 128 rules can be attached. Keep their history while bounding
    -- retained history for spells removed from a rotation.
    local maximum = incoming and P.successes[incoming] == nil and MAX_HISTORY - 1 or MAX_HISTORY
    while count > maximum do
        local oldest, oldestTime = nil, math.huge
        for spellID, success in pairs(P.successes) do
            if spellID ~= incoming and success < oldestTime and not attachedSpell(spellID, requests) then
                oldest, oldestTime = spellID, success
            end
        end
        if not oldest then error("Too many active spell timing histories", 0) end
        P.successes[oldest] = nil
        if P.saved then P.saved[oldest] = nil end
        count = count - 1
    end
end
local function restoreHistory(timestamp, requests)
    if secret(SH.rootDB) or type(SH.rootDB) ~= "table" then
        error("Manual Cooldown saved data is unavailable. Reload before preparing.", 0)
    end
    local wall = serverNow()
    if P.savedRoot == SH.rootDB then return wall end
    local original, saved, restored, count = SH.rootDB.manualCooldowns, {}, {}, 0
    if not secret(original) and type(original) == "table" then
        for spellID, success in pairs(original) do
            if integer(spellID, 1, 100000000) and number(success) and success > 0 then
                if success > wall then error("Manual Cooldown server clock moved backwards. Wait for the clock to recover before preparing.", 0) end
                -- Integer server time cannot identify either fractional
                -- endpoint. Subtract one second from elapsed time only on
                -- restore, so a reload cannot make a spell ready early.
                local elapsed = math.max(0, wall - success - 1)
                if elapsed <= MAX_COOLDOWN then
                    count = count + 1
                    if count > MAX_HISTORY then error("Manual Cooldown saved history is too large", 0) end
                    saved[spellID], restored[spellID] = success, timestamp - elapsed
                end
            end
        end
    end
    -- Do not replace valid live evidence when the first manual rule is added
    -- after a ping-only rule already observed this exact spell succeeding.
    for spellID, success in pairs(restored) do
        if P.successes[spellID] == nil then P.successes[spellID] = success
        else saved[spellID] = wall - (timestamp - P.successes[spellID]) end
    end
    P.savedRoot, P.saved = SH.rootDB, saved
    SH.rootDB.manualCooldowns = saved
    trimHistory(timestamp, nil, requests)
    return wall
end
local function saveExistingSuccesses(requests, timestamp, wall)
    for _, request in pairs(requests or EMPTY) do
        local spellID = request.source.spellID
        local success = P.successes[spellID]
        if (request.cooldownSeconds or 0) > 0 and success and success + MAX_COOLDOWN >= timestamp
            and not P.saved[spellID] then
            -- This success was observed by a ping-only rule before manual
            -- timing was enabled. Preserve its exact live clock and save a
            -- conservative wall-clock estimate for the next login.
            P.saved[spellID] = wall - (timestamp - success)
        end
    end
end
local function currentSlot(button, size)
    local id = required(button, "GetID")
    if not number(id) then error("The native action slot is unreadable", 0) end
    if id > 0 then
        local page = nativeCall("SecureButton_GetModifiedAttribute", SecureButton_GetModifiedAttribute, button, "actionpage")
        if page == nil then page = nativeCall("C_ActionBar.GetActionBarPage", C_ActionBar and C_ActionBar.GetActionBarPage) end
        if not number(page) then error("The native action page is unreadable", 0) end
        return id + (page - 1) * size
    end
    return nativeCall("SecureButton_GetModifiedAttribute", SecureButton_GetModifiedAttribute, button, "action") or 1
end
local function registered(button)
    local dispatcher = ActionBarActionEventsFrame
    return dispatcher and dispatcher.frames and dispatcher.frames[button] == button
end
local function checkSource(source, inspectAction, allowHidden)
    if type(source) ~= "table" or not source.button or not integer(source.slot, 1, 1000)
        or not integer(source.spellID, 1, 100000000) or not integer(source.barSize, 1, 100) then
        error("The timed spell source is invalid", 0)
    end
    local button = source.button
    if not registered(button) or required(button, "IsForbidden") ~= false
        or (not allowHidden and required(button, "IsVisible") ~= true) or required(button, "IsProtected") ~= true
        or type(button.OnEvent) ~= "function" or type(button.UpdateAction) ~= "function"
        or type(button.MatchesActiveButtonSpellID) ~= "function" then
        error("Keep the timed spell on its original visible Blizzard action bar, then Prepare", 0)
    end
    local watcher = P.sources[button]
    if watcher and (button.OnEvent ~= watcher.onEvent or button.UpdateAction ~= watcher.updateAction) then
        error("The timed spell's native event source changed. Prepare after reloading.", 0)
    end
    if inspectAction then
        outside()
        if currentSlot(button, source.barSize) ~= source.slot or button.action ~= source.slot then
            error("The timed spell's action slot or page changed", 0)
        end
        if type(GetActionInfo) ~= "function" then error("Native action information is unavailable", 0) end
        -- Diagnostic callbacks intentionally preserve just one return value;
        -- this read needs both values and runs only outside combat.
        local kind, id = GetActionInfo(source.slot)
        if secret(kind) or secret(id) or kind ~= "spell" or id ~= source.spellID then
            error("The timed spell rank changed", 0)
        end
    end
end

function P.FindSource(row)
    local ok, result = pcall(function()
        outside()
        if type(row) ~= "table" or not integer(row.spellID, 1, 100000000) then error("The spell rank could not be identified", 0) end
        local size, candidates = NUM_ACTIONBAR_BUTTONS or 12, {}
        for _, button in pairs(ActionBarActionEventsFrame and ActionBarActionEventsFrame.frames or EMPTY) do
            local source = {button = button, slot = button.action, spellID = row.spellID, barSize = size}
            if not button.isExtra and button.buttonType ~= "MULTICASTACTIONBUTTON" and pcall(checkSource, source, true) then
                candidates[#candidates + 1] = source
            end
        end
        table.sort(candidates, function(a, b) return (a.button:GetName() or "") < (b.button:GetName() or "") end)
        if not candidates[1] then error("Put this exact spell rank on a visible Blizzard action bar and keep that bar and slot unchanged", 0) end
        return candidates[1]
    end)
    if not ok then return nil, message(result) end
    return result
end

local EVENTS = {UNIT_SPELLCAST_START = "start", UNIT_SPELLCAST_CHANNEL_START = "channel",
    UNIT_SPELLCAST_EMPOWER_START = "channel", UNIT_SPELLCAST_SUCCEEDED = "success",
    UNIT_SPELLCAST_FAILED = "failed", UNIT_SPELLCAST_INTERRUPTED = "interrupted",
    UNIT_SPELLCAST_STOP = "stop", UNIT_SPELLCAST_CHANNEL_STOP = "channelStop",
    UNIT_SPELLCAST_EMPOWER_STOP = "channelStop"}
local function invalidate(watcher, reason)
    for record in pairs(watcher.records) do record.invalid = reason end
end
local TEMPORARY_SOURCE = "The timed spell's action bar is temporarily unavailable. It will recover when the original bar returns."
local function onTaxi()
    if type(UnitOnTaxi) ~= "function" then return false end
    local ok, value = pcall(UnitOnTaxi, "player")
    return ok and not secret(value) and value == true
end
local function pauseSource(record, mayHaveCasts)
    if not record.pendingSource then
        record.pendingSource = true
        record.gapMayHaveCasts = record.casting == true or (mayHaveCasts == true and not onTaxi())
    elseif mayHaveCasts and not onTaxi() then
        record.gapMayHaveCasts = true
    end
end
local function currentCasting(source)
    local cast = source.button.SpellCastAnimFrame
    return cast and required(cast, "IsShown") == true
        and cast.EndBurst and required(cast.EndBurst, "IsShown") == false or false
end
local function rememberRecovery(spellID, timestamp)
    local count, oldest, oldestTime = 0, nil, math.huge
    for id, anchor in pairs(P.recoveryAnchors) do
        if anchor + MAX_COOLDOWN < timestamp then P.recoveryAnchors[id] = nil
        else
            count = count + 1
            if id ~= spellID and anchor < oldestTime and not attachedSpell(id) then oldest, oldestTime = id, anchor end
        end
    end
    if not P.recoveryAnchors[spellID] and count >= MAX_HISTORY then
        if not oldest then error("Too many active spell timing recoveries", 0) end
        P.recoveryAnchors[oldest] = nil
    end
    P.recoveryAnchors[spellID] = timestamp
end
local function sourceIssue(record)
    if record.invalid then return "configuration", record.invalid end
    local source, button = record.source, record.source.button
    if combat() then
        if record.pendingSource or required(button, "IsVisible") ~= true then
            return "timing-availability", TEMPORARY_SOURCE
        end
        checkSource(source, false, true)
        return
    end
    -- An action-bar refresh is not evidence of an edit. Check the original
    -- slot's identity outside combat before asking the player to prepare.
    if type(GetActionInfo) ~= "function" then return "timing-availability", TEMPORARY_SOURCE end
    local readable, kind, id = pcall(GetActionInfo, source.slot)
    if not readable or secret(kind) or secret(id) then
        pauseSource(record, true)
        return "timing-availability", TEMPORARY_SOURCE
    end
    if kind ~= "spell" or id ~= source.spellID then
        if onTaxi() or SH.worldLoading or (SH.worldSettleRemaining or 0) > 0 then
            pauseSource(record, true)
            return "timing-availability", TEMPORARY_SOURCE
        end
        record.invalid = "The timed spell was moved or replaced in its original action-bar slot. Prepare again."
        return "configuration", record.invalid
    end
    local ok, slot = pcall(currentSlot, button, source.barSize)
    if not ok or slot ~= source.slot or not integer(button.action, 1, 1000)
        or button.action ~= source.slot or not registered(button) then
        local pageChanged = ok and slot ~= source.slot
        local cachedChanged = integer(button.action, 1, 1000) and button.action ~= source.slot
        pauseSource(record, pageChanged or cachedChanged or not registered(button))
        return "timing-availability", TEMPORARY_SOURCE
    end
    checkSource(source, false, true)
    if record.pendingSource then
        local timestamp = now()
        -- A different page may have hidden cast events from this observer.
        -- Keep real successes intact; use a separate, bounded settling wait
        -- when that gap could contain casts. Taxi-only gaps need no such wait.
        if record.gapMayHaveCasts then
            rememberRecovery(source.spellID, timestamp)
            record.recoveryDeadline = math.max(record.recoveryDeadline or 0,
                timestamp + math.max(record.delay, record.cooldown))
        end
        record.casting, record.channel = currentCasting(source), false
        record.pendingSource, record.gapMayHaveCasts = nil, nil
    end
    if required(button, "IsVisible") ~= true then return "timing-availability", TEMPORARY_SOURCE end
end
local function recheckSource(record)
    local ok, category, reason = pcall(sourceIssue, record)
    if not ok then record.invalid = message(category) end
end
local function observe(watcher, event, actionSlot)
    -- Blizzard's dispatcher has already filtered player + exact button spell.
    -- Never inspect the event's unit, cast GUID, spell ID, or other secret args.
    if secret(event) or type(event) ~= "string" then invalidate(watcher, "The native spell event is unreadable"); return end
    if event == "ACTIONBAR_SLOT_CHANGED" then
        -- Zero means a global refresh. Neither it nor a same-slot update proves
        -- the spell changed. Combat reads wait for out-of-combat verification.
        for record in pairs(watcher.records) do
            if not integer(actionSlot, 1, 1000) or actionSlot == record.source.slot then
                if combat() then pauseSource(record) else recheckSource(record) end
            end
        end
        return
    end
    local kind = EVENTS[event]
    if not kind or next(watcher.records) == nil then return end
    for record in pairs(watcher.records) do
        if record.pendingSource then
            if not combat() then recheckSource(record) end
            if record.pendingSource then record.gapMayHaveCasts = true end
        end
    end
    local ok, timestamp = pcall(now)
    if not ok then invalidate(watcher, message(timestamp)); return end
    local wall
    if kind == "success" then
        for record in pairs(watcher.records) do
            if not record.invalid and not record.pendingSource and (record.cooldown > 0 or (P.saved and P.saved[record.source.spellID])) then
                ok, wall = pcall(serverNow)
                if not ok then invalidate(watcher, message(wall)); return end
                break
            end
        end
    end
    for record in pairs(watcher.records) do
        if not record.invalid and not record.pendingSource then
            if kind == "start" or kind == "channel" then
                record.casting, record.channel = true, kind == "channel"
            elseif kind == "success" then
                if not record.channel then record.casting = false end
                record.deadline = math.max(record.deadline, timestamp + record.delay)
                local spellID = record.source.spellID
                trimHistory(timestamp, spellID)
                P.successes[spellID] = timestamp
                P.recoveryAnchors[spellID] = nil
                record.recoveryDeadline = nil
                if wall and P.saved then P.saved[spellID] = wall end
            elseif kind == "failed" then
                -- A new same-spell request can fail while the previous cast is
                -- still running. FAILED alone must not release that cast.
            elseif kind == "channelStop" then
                if record.channel then record.deadline = math.max(record.deadline, timestamp + record.delay) end
                record.casting, record.channel = false, false
            else
                record.casting, record.channel = false, false
                -- STOP commonly follows SUCCEEDED: preserve that settling time.
            end
        end
    end
end
local function watch(source)
    local button = source.button
    local watcher = P.sources[button]
    if watcher then return watcher end
    watcher = {records = {}}
    P.sources[button] = watcher
    -- Post-hooks cannot replace the native event dispatch or suppress its work.
    nativeCall("hooksecurefunc", hooksecurefunc, button, "OnEvent", function(_, event, actionSlot) observe(watcher, event, actionSlot) end)
    watcher.onEvent = button.OnEvent
    nativeCall("hooksecurefunc", hooksecurefunc, button, "UpdateAction", function(native)
        -- Native UpdateAction also runs for harmless attribute/usability
        -- refreshes. Quarantine uncertain sources, then verify actual identity.
        local slot = native.action
        for record in pairs(watcher.records) do
            if not combat() then recheckSource(record)
            elseif not integer(slot, 1, 1000) or slot ~= record.source.slot then
                pauseSource(record, integer(slot, 1, 1000) and slot ~= record.source.slot)
            end
        end
    end)
    watcher.updateAction = button.UpdateAction
    -- Native OnHide leaves the spell-event dispatcher registered. Visibility
    -- alone pauses reads; its START/STOP/SUCCEEDED hooks keep updating state.
    return watcher
end
local function validateRequests(requests)
    if secret(requests) or type(requests) ~= "table" then error("Ping Delay requests are invalid", 0) end
    local manual = false
    for index, request in pairs(requests) do
        if not integer(index, 1, MAX_RULES) or type(request) ~= "table"
            or not integer(request.delayMs, 0, 5000) then error("Ping Delay must be a whole number from 1 to 5000 ms when enabled", 0) end
        local cooldown = request.cooldownSeconds
        if cooldown == nil then cooldown = 0 end
        if not number(cooldown) or cooldown < 0 or cooldown > MAX_COOLDOWN
            or (cooldown > 0 and cooldown < 0.001)
            or math.abs(cooldown * 1000 - math.floor(cooldown * 1000 + 0.5)) > 0.000001 then
            error("Manual Cooldown must be from 0.001 to 86400 seconds, with up to 3 decimal places", 0)
        end
        if request.delayMs == 0 and cooldown == 0 then error("A timing rule needs Ping Delay or Manual Cooldown", 0) end
        manual = manual or cooldown > 0
        checkSource(request.source, true)
        if request.row and request.row.spellID ~= request.source.spellID then error("The timing request has the wrong spell rank", 0) end
    end
    return manual
end
local function near(a, b) return number(a) and number(b) and math.abs(a - b) <= TOLERANCE end
-- Each consumer owns its calibration, frames and diagnostic labels. Timing
-- observers and saved cooldown history belong exclusively to Ping Delay.
function BinarySignal.New(owner, label, prefix, framePrefix)
    local signal = {}
    local fonts = {data = {}, commit = {}}
    local function required(object, name, ...)
        return frameCall(label, object, name, ...)
    end
    function signal.Call(name, fn, ...)
        return callFor(label, name, fn, ...)
    end
    local function readWidth(frame)
        if required(frame, "IsShown") ~= true then error(label .. " signal is hidden", 0) end
        local value = required(frame, "GetWidth")
        if not number(value) or value <= 0 then error(label .. " width is unreadable", 0) end
        return value
    end
    local function setCode(kind, code)
        required(owner[kind .. "Frame"], "SetPadding", 16 + code * 32, 0, 0, 0)
    end
    local function restoreTooltip(frame)
        -- Native Hide can clear tooltip ownership/content. Rebuild it outside
        -- combat before rechecking all previously calibrated widths.
        required(frame, "SetAlpha", 0)
        required(frame, "SetOwner", UIParent, "ANCHOR_NONE")
        -- These bare tooltips do not inherit SharedTooltip_OnHide's padding reset.
        -- Seed text from the same zero-padding state used on first creation.
        required(frame, "SetPadding", 0, 0, 0, 0)
        required(frame, "SetClampedToScreen", false)
        required(frame, "ClearAllPoints")
        required(frame, "SetPoint", "TOPRIGHT", UIParent, "BOTTOMLEFT", -256, -256)
        required(frame, "SetText", "0", 1, 1, 1, 0, false)
        required(frame, "Show")
        required(frame, "SetAlpha", 0)
    end
    local function initializeTooltip(kind)
        local name = framePrefix .. (kind == "data" and "Data" or "Commit")
        local frame = owner[kind .. "Frame"]
        if not frame then
            frame = callFor(label, "CreateFrame", CreateFrame, "GameTooltip", name, UIParent, "SecureFrameTemplate")
            owner[kind .. "Frame"] = frame
        end
        if required(frame, "IsProtected") ~= true then error(label .. " signal is not protected", 0) end
        local pair = fonts[kind]
        if not pair.left then pair.left = required(frame, "CreateFontString", name .. "TextLeft1", "ARTWORK", "GameTooltipText") end
        if not pair.right then pair.right = required(frame, "CreateFontString", name .. "TextRight1", "ARTWORK", "GameTooltipText") end
        if not pair.attached then
            required(pair.left, "SetAlpha", 0)
            required(pair.right, "SetAlpha", 0)
            required(frame, "AddFontStrings", pair.left, pair.right)
            pair.attached = true
        end
        restoreTooltip(frame)
        owner[kind .. "Initialized"] = true
    end
    local function calibrate(kind)
        local widths = {}
        -- Reapplying the same native padding can be a no-op after a layout change.
        setCode(kind, 3)
        for code = 0, 3 do
            setCode(kind, code)
            local value = readWidth(owner[kind .. "Frame"])
            for earlier = 0, code - 1 do
                if math.abs(widths[earlier] - value) <= 2 * TOLERANCE then error(label .. " signal cannot distinguish its states", 0) end
            end
            widths[code] = value
        end
        for code = 2, 0, -1 do
            setCode(kind, code)
            if not near(readWidth(owner[kind .. "Frame"]), widths[code]) then error(label .. " layout did not return to its earlier state", 0) end
        end
        return widths
    end

    function signal.Outside()
        if combat() then error("Prepare " .. label .. " outside combat", 0) end
    end
    function signal.Prepare()
        signal.Outside()
        if type(SecureHandlerSetFrameRef) ~= "function" then error(label .. " frame references are unavailable", 0) end
        owner.calibrated = false
        if owner.commitFrame then required(owner.commitFrame, "SetAttribute", "sh-binary-ready", false) end
        local widths = {}
        for _, kind in ipairs({"data", "commit"}) do
            local frame = owner[kind .. "Frame"]
            if not owner[kind .. "Initialized"] then initializeTooltip(kind)
            elseif required(frame, "IsShown") ~= true then restoreTooltip(frame)
            else required(frame, "SetAlpha", 0) end
            widths[kind] = calibrate(kind)
        end
        -- Every attached rotation reads the same mapping. Publish both sets
        -- together only after they are distinct and reversible at this scale.
        for _, kind in ipairs({"data", "commit"}) do
            for code = 0, 3 do
                required(owner[kind .. "Frame"], "SetAttribute", "sh-width" .. code, widths[kind][code])
            end
        end
        required(owner.commitFrame, "SetAttribute", "sh-binary-ready", true)
        owner.widths, owner.calibrated = widths, true
    end
    function signal.Attach(button)
        signal.Outside()
        if not owner.calibrated then error(label .. " signal is not calibrated", 0) end
        for _, kind in ipairs({"data", "commit"}) do
            callFor(label, "SecureHandlerSetFrameRef", SecureHandlerSetFrameRef, button, prefix .. "-" .. kind, owner[kind .. "Frame"])
        end
    end
    function signal.Publish(value, phase)
        if not owner.calibrated then error(label .. " signal is not calibrated", 0) end
        if secret(value) or type(value) ~= "boolean" or not integer(phase, 0, 1) then
            error(label .. " reading is unavailable", 0)
        end
        local code = (value and 1 or 0) + phase * 2
        setCode("data", code)
        if not near(readWidth(owner.dataFrame), owner.widths.data[code]) then error(label .. " data did not match its request", 0) end
        setCode("commit", code)
        if not near(readWidth(owner.commitFrame), owner.widths.commit[code]) then error(label .. " acknowledgment did not match its request", 0) end
    end
    function signal.Hide()
        signal.Outside()
        if owner.dataFrame then required(owner.dataFrame, "Hide") end
        if owner.commitFrame then required(owner.commitFrame, "Hide") end
    end
    return signal
end
local pingSignal = BinarySignal.New(P, "Ping Delay", "ping", "StandAndHitPing")
function P:Prepare(requests)
    local permitted, reason = pcall(outside)
    if not permitted then self.reason = message(reason); return false, self.reason end
    local touched = false
    local ok, err = pcall(function()
        local manual = requests and validateRequests(requests)
        if type(hooksecurefunc) ~= "function" or type(SecureHandlerSetFrameRef) ~= "function" then error("Ping Delay native observers are unavailable", 0) end
        local timestamp = now()
        if manual then saveExistingSuccesses(requests, timestamp, restoreHistory(timestamp, requests)) end
        touched, self.ready = true, false
        pingSignal.Prepare()
    end)
    if not ok then
        self.reason = message(err)
        if touched then self.ready = false end
        return false, self.reason
    end
    self.ready, self.reason = true, nil
    return true
end
function P:Detach(button)
    local permitted, reason = pcall(outside)
    if not permitted then self.reason = message(reason); return false, self.reason end
    for _, record in pairs(self.bindings[button] or EMPTY) do record.watcher.records[record] = nil end
    self.bindings[button] = nil
    return true
end
function P:Attach(button, requests)
    local ok, err = pcall(function()
        outside()
        if not self.ready then error(self.reason or "Ping Delay has not been prepared", 0) end
        local manual = validateRequests(requests)
        if manual then
            local timestamp = now()
            saveExistingSuccesses(requests, timestamp, restoreHistory(timestamp, requests))
        end
        assert(self:Detach(button))
        local binding = {}
        self.bindings[button] = binding
        pingSignal.Attach(button)
        for index, request in pairs(requests) do
            local source, watcher = request.source, watch(request.source)
            local casting = currentCasting(source)
            local record = {source = source, watcher = watcher, delay = request.delayMs / 1000,
                cooldown = request.cooldownSeconds or 0, deadline = 0, casting = casting, channel = false}
            local recovery = self.recoveryAnchors[source.spellID]
            if recovery then record.recoveryDeadline = recovery + math.max(record.delay, record.cooldown) end
            binding[index], watcher.records[record] = record, true
            nativeCall("SecureHandlerSetFrameRef", SecureHandlerSetFrameRef, button, "ping-native" .. index, source.button)
            required(button, "SetAttribute", "sh-ping-slot" .. index, source.slot)
            required(button, "SetAttribute", "sh-ping-spell-id" .. index, source.spellID)
            required(button, "SetAttribute", "sh-ping-bar-size" .. index, source.barSize)
        end
    end)
    if not ok then
        -- A partial attachment must never leave live records accepting events.
        if not combat() then self:Detach(button) end
        self.reason = message(err); return false, self.reason
    end
    self.reason = nil
    return true
end
local function getRecord(button, index, allowHidden)
    if not P.ready then error(P.reason or "Ping Delay has not been prepared", 0) end
    if not integer(index, 1, MAX_RULES) then error("Invalid Ping Delay read request", 0) end
    local record = P.bindings[button] and P.bindings[button][index]
    if not record then error("Ping Delay is not attached to this rule", 0) end
    if record.invalid then error(record.invalid, 0) end
    if record.pendingSource then error(TEMPORARY_SOURCE, 0) end
    -- Spell/rank/page validation is done inside READ_SNIPPET, where action info
    -- is available. Ordinary Lua must not compare secret combat action IDs.
    checkSource(record.source, false, allowHidden)
    return record
end
local function armSpell(record, timestamp)
    -- Several enabled rules/rotations can request the same spell before its
    -- first native START or SUCCEEDED arrives. Share the attempt evidence,
    -- while preserving each rule's own configured settling duration.
    local spellID = record.source.spellID
    for _, binding in pairs(P.bindings) do
        for _, other in pairs(binding) do
            if other.source.spellID == spellID then
                other.deadline = math.max(other.deadline, timestamp + other.delay)
            end
        end
    end
end
function P:Refresh(button, index, phase, arm)
    local ok, err = pcall(function()
        if not integer(phase, 0, 1) then error("Invalid Ping Delay acknowledgment", 0) end
        if secret(arm) or (arm ~= nil and type(arm) ~= "boolean") then error("Invalid Ping Delay arm request", 0) end
        local record = getRecord(button, index)
        local timestamp = now()
        local success = self.successes[record.source.spellID]
        local recovery = self.recoveryAnchors[record.source.spellID]
        record.recoveryDeadline = recovery and recovery + math.max(record.delay, record.cooldown) or nil
        local pass = not record.casting and timestamp >= record.deadline
            and timestamp >= (record.recoveryDeadline or 0)
            and (record.cooldown == 0 or success == nil or timestamp >= success + record.cooldown)
        -- Only the final hardware-click action arms. Its fresh acknowledgment
        -- is published after the deadline exists; a failed publication can
        -- cause a short harmless wait, never an unguarded cast.
        if arm == true and pass then armSpell(record, timestamp) end
        pingSignal.Publish(pass, phase)
    end)
    if not ok then self.reason = message(err); return false, self.reason end
    self.reason = nil
    return true
end
function P:NoteAttempt(button, index)
    local ok, err = pcall(function()
        local record = getRecord(button, index)
        armSpell(record, now())
    end)
    if not ok then self.reason = message(err); return false, self.reason end
    return true
end
local function validateButton(button)
    for index in pairs(P.bindings[button] or EMPTY) do
        local record = P.bindings[button][index]
        local category, reason = sourceIssue(record)
        if category then error(reason, 0) end
        getRecord(button, index)
    end
end
function P:Validate(button)
    local ok, err = pcall(validateButton, button)
    if not ok then return message(err) end
end
local function preparationIssue(button)
    if not P.ready then error(P.reason or "Ping Delay has not been prepared", 0) end
    local temporary
    for _, record in pairs(P.bindings[button] or EMPTY) do
        local category, reason = sourceIssue(record)
        if category == "configuration" then return category, reason end
        if category then temporary = reason end
    end
    if temporary then return "timing-availability", temporary end
end
function P:PreparationIssue(rotation)
    local ok, category, reason = pcall(preparationIssue, rotation.button)
    if not ok then return {category = "configuration", reason = message(category)} end
    if category then return {category = category, reason = reason} end
end
function P:Cleanup()
    local ok, err = pcall(function()
        outside()
        for button in pairs(self.bindings) do self:Detach(button) end
        self.ready = false
        pingSignal.Hide()
    end)
    if not ok then self.reason = message(err); return false, self.reason end
    self.reason = "Ping Delay has not been prepared."
    return true
end

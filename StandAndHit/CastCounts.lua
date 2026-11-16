local _, SH = ...
local Counts = {}
SH.CastCounts = Counts

-- One animation can serve several rules, including rules in another rotation.
local animations = {}
local EMPTY = {}
local GUARD_KEYS = {"counter", "auraGuard", "startGuard", "visibilityGuard"}

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function castTime(spellID)
    local info = call(C_Spell and C_Spell.GetSpellInfo, spellID)
    if type(info) == "table" then return info.castTime end
    local _, _, _, duration = call(GetSpellInfo, spellID)
    return duration
end

local function currentSlot(button, barSize)
    local id = call(button.GetID, button)
    if type(id) ~= "number" then return nil end
    if id > 0 then
        local page = call(SecureButton_GetModifiedAttribute, button, "actionpage") or call(C_ActionBar and C_ActionBar.GetActionBarPage)
        if type(page) ~= "number" then return nil end
        return id + (page - 1) * barSize
    end
    return call(SecureButton_GetModifiedAttribute, button, "action") or 1
end

local function forbidden(frame)
    return not frame or call(frame.IsForbidden, frame) == true
end

function Counts.Find(row)
    local spellID = row and row.spellID
    if type(spellID) ~= "number" then return nil, "The spell rank could not be identified." end
    local duration = castTime(spellID)
    if type(duration) ~= "number" or duration <= 0 then
        return nil, "Cast count needs a normal spell with a cast time; instant spells and channels are not supported."
    end
    local candidates = {}
    local dispatcher = ActionBarActionEventsFrame
    local barSize = NUM_ACTIONBAR_BUTTONS or 12
    for _, button in pairs(dispatcher and dispatcher.frames or EMPTY) do
        local cast = button.SpellCastAnimFrame
        local burst = cast and cast.EndBurst
        local anim = cast and cast.Fill and cast.Fill.CastingAnim
        local slot = button.action
        local actionType, id = call(GetActionInfo, slot)
        if actionType == "spell" and id == spellID and button.enableSpellFX == true and
            not button.isExtra and button.buttonType ~= "MULTICASTACTIONBUTTON" and
            not forbidden(button) and not forbidden(cast) and not forbidden(burst) and
            anim and type(anim.GetLooping) == "function" and type(anim.SetLooping) == "function" and
            call(button.IsVisible, button) == true and currentSlot(button, barSize) == slot then
            candidates[#candidates + 1] = {
                button = button, castFrame = cast, burst = burst, animation = anim,
                slot = slot, spellID = spellID, barSize = barSize,
                buttonID = call(button.GetID, button),
            }
        end
    end
    table.sort(candidates, function(a, b)
        return (call(a.button.GetName, a.button) or "") < (call(b.button.GetName, b.button) or "")
    end)
    if candidates[1] then return candidates[1] end
    return nil, "Put this exact spell rank on a visible Blizzard action bar and keep that bar and slot unchanged."
end

local CHECK = [[
    if self:GetAttribute("sh-active")~=true or self:GetAttribute("sh-valid")~=true then return false end
    local native=self:GetFrameRef("native")
    local slot=self:GetAttribute("sh-slot")
    local expected=self:GetAttribute("sh-spell-id")
    local size=self:GetAttribute("sh-bar-size")
    local cast=self:GetFrameRef("cast")
    local valid=native and cast and slot and expected and size and
        cast:GetParent()==native and self:GetParent():GetParent()==cast
    local actual
    if valid then
        local id=native:GetID()
        if id~=self:GetAttribute("sh-button-id") then valid=false
        elseif id and id>0 then
            local page=native:GetEffectiveAttribute("actionpage") or GetActionBarPage()
            if page then actual=id+(page-1)*size end
        elseif id then
            actual=native:GetEffectiveAttribute("action") or 1
            if actual~=slot then valid=false end
        end
    end
    if valid then
        local kind,spellID=GetActionInfo(slot)
        valid=kind=="spell" and spellID==expected
    end
    if not valid then
        self:SetAttribute("sh-valid",false)
        self:SetAttribute("sh-cast-observed",false)
        return false
    end
    if native:IsVisible()~=true or actual~=slot then
        self:SetAttribute("sh-suspended",true)
        self:SetAttribute("sh-cast-observed",false)
        self:SetAttribute("sh-signal-seen",true)
        return false
    end
    self:SetAttribute("sh-suspended",false)
    return true
]]

local COMPLETED = [[
    if self:GetAttribute("sh-active")~=true or self:GetAttribute("sh-signal-seen") then return end
    self:SetAttribute("sh-signal-seen",true)
    local observed=self:GetAttribute("sh-cast-observed")
    self:SetAttribute("sh-cast-observed",false)
    if self:RunAttribute("sh-check")~=true or observed~=true or self:GetAttribute("sh-started")~=true then return end
    local count=self:GetAttribute("sh-count")
    local limit=self:GetAttribute("sh-limit")
    if type(count)~="number" or type(limit)~="number" or count<0 or count%1~=0 or limit<1 or limit%1~=0 then
        self:SetAttribute("sh-valid",false); return
    end
    if count<limit then self:SetAttribute("sh-count",count+1) end
]]

local HIDDEN_BURST = [[
    if self:GetAttribute("sh-active")==true and self:GetParent():IsShown()==false then
        self:SetAttribute("sh-signal-seen",false)
        local cast=self:GetFrameRef("cast")
        local suspended=self:GetAttribute("sh-suspended")
        local available=self:RunAttribute("sh-check")==true
        self:SetAttribute("sh-cast-observed",available and not suspended and cast and cast:IsShown()==true or false)
    end
]]

-- Setup hides EndBurst before showing its casting parent. If that parent was
-- already hidden, the EndBurst child did not receive another OnHide.
local STARTED = [[
    local counter=self:GetFrameRef("counter")
    if counter and counter:GetAttribute("sh-active")==true and counter:GetParent():IsShown()==false then
        counter:SetAttribute("sh-signal-seen",false)
        local suspended=counter:GetAttribute("sh-suspended")
        local available=counter:RunAttribute("sh-check")==true
        counter:SetAttribute("sh-cast-observed",available and not suspended)
    end
]]

local AURA_ENDED = [[
    if self:GetParent():IsShown()==false then
        local counter=self:GetFrameRef("counter")
        if counter and counter:GetAttribute("sh-active")==true then
            counter:SetAttribute("sh-count",0)
            counter:SetAttribute("sh-started",false)
        end
    end
]]

local BAR_HIDDEN = [[
    if self:GetParent():IsVisible()~=true then
        local counter=self:GetFrameRef("counter")
        if counter and counter:GetAttribute("sh-active")==true then
            counter:SetAttribute("sh-suspended",true)
            counter:SetAttribute("sh-cast-observed",false)
            counter:SetAttribute("sh-signal-seen",true)
        end
    end
]]

local function acquire(record)
    local anim = record.entry.animation
    local owner = animations[anim]
    if not owner then
        owner = { count = 0, original = anim:GetLooping() }
        anim:SetLooping("REPEAT")
        animations[anim] = owner
    else
        anim:SetLooping("REPEAT")
    end
    owner.count = owner.count + 1
    record.ownsAnimation = true
end

local function release(record)
    if record.counter then record.counter:SetAttribute("sh-active", false) end
    for _, key in ipairs(GUARD_KEYS) do
        local frame = record[key]
        if frame then
            frame:SetAttribute("_onshow", nil)
            frame:SetAttribute("_onhide", nil)
            frame:SetParent(UIParent)
            frame:Hide()
        end
    end
    if record.ownsAnimation then
        local anim = record.entry.animation
        local owner = animations[anim]
        if owner then
            owner.count = owner.count - 1
            if owner.count == 0 then
                anim:SetLooping(owner.original or "NONE")
                animations[anim] = nil
            end
        end
        record.ownsAnimation = false
    end
end

function Counts.Detach(rotation)
    if InCombatLockdown() then return false, "Leave combat before changing cast-count observers." end
    for _, record in pairs(rotation.castCountObservers or EMPTY) do release(record) end
    rotation.castCountObservers = {}
    return true
end

function Counts.Install(rotation, index, row, auraFrame, entry)
    if InCombatLockdown() then return nil, "Leave combat before preparing cast counts." end
    if not rotation.button or forbidden(auraFrame) or not entry then return nil, "The cast-count observer is unavailable." end
    if type(row.castCount) ~= "number" or row.castCount < 1 or row.castCount % 1 ~= 0 then
        return nil, "Choose a whole number of completed casts."
    end
    local attachment = SH.Model.GetCountCondition(row)
    if not attachment or not attachment.countEligible then
        return nil, attachment and attachment.countReason or "The cast-count condition no longer exists."
    end
    rotation.castCountObservers = rotation.castCountObservers or {}
    rotation.castCountPool = rotation.castCountPool or {}
    if rotation.castCountObservers[index] then release(rotation.castCountObservers[index]) end
    local record = rotation.castCountPool[index] or {}
    rotation.castCountPool[index] = record
    record.sourceIndex = row.sourceIndex or index
    record.entry, record.index, record.conditionKey, record.auraFrame = entry, index, attachment.key, auraFrame
    rotation.castCountObservers[index] = record
    local ok, reason = pcall(function()
        local function child(key, parent)
            local frame = record[key]
            if not frame then
                frame = CreateFrame("Frame", nil, parent, "SecureHandlerShowHideTemplate")
                record[key] = frame
            end
            frame:SetParent(parent)
            return frame
        end
        local counter = child("counter", entry.burst)
        counter:SetAttribute("sh-active", false)
        counter:SetAttribute("sh-count", 0)
        counter:SetAttribute("sh-started", false)
        counter:SetAttribute("sh-limit", row.castCount)
        counter:SetAttribute("sh-condition-key", attachment.key)
        counter:SetAttribute("sh-slot", entry.slot)
        counter:SetAttribute("sh-spell-id", entry.spellID)
        counter:SetAttribute("sh-bar-size", entry.barSize)
        counter:SetAttribute("sh-button-id", entry.buttonID)
        counter:SetAttribute("sh-valid", true)
        counter:SetAttribute("sh-suspended", false)
        counter:SetAttribute("sh-cast-observed", false)
        counter:SetAttribute("sh-signal-seen", entry.burst:IsShown() == true)
        counter:SetFrameRef("native", entry.button)
        counter:SetFrameRef("cast", entry.castFrame)
        counter:SetAttribute("sh-check", CHECK)
        counter:SetAttribute("sh-casting", [[
            if self:RunAttribute("sh-check")~=true then return false end
            local cast=self:GetFrameRef("cast")
            return cast and cast:IsShown()==true and self:GetParent():IsShown()==false or false
        ]])
        counter:SetAttribute("_onshow", COMPLETED)
        counter:SetAttribute("_onhide", HIDDEN_BURST)
        local start = child("startGuard", entry.castFrame)
        start:SetFrameRef("counter", counter)
        start:SetAttribute("_onshow", STARTED)
        local aura = child("auraGuard", auraFrame)
        aura:SetFrameRef("counter", counter)
        aura:SetAttribute("_onhide", AURA_ENDED)
        local visibility = child("visibilityGuard", entry.button)
        visibility:SetFrameRef("counter", counter)
        visibility:SetAttribute("_onhide", BAR_HIDDEN)
        assert(entry.burst:IsProtected() and entry.button:IsProtected() and auraFrame:IsProtected(),
            "The native cast-count frames did not become protected.")
        acquire(record)
        rotation.button:SetFrameRef("count" .. index, counter)
        counter:Show()
        start:Show()
        aura:Show()
        visibility:Show()
        counter:SetAttribute("sh-active", true)
    end)
    if not ok then
        release(record)
        rotation.castCountObservers[index] = nil
        return nil, tostring(reason)
    end
    return record.counter
end

-- The original action slot identifies the source even while the native button
-- displays another form's page. Only confirmed, observed completions are kept.
function Counts.PreparationIssue(rotation)
    local waiting
    for index, record in pairs(rotation.castCountObservers or EMPTY) do
        local entry, counter = record.entry, record.counter
        local kind, spellID = call(GetActionInfo, entry.slot)
        local cast = entry.button.SpellCastAnimFrame
        local id = call(entry.button.GetID, entry.button)
        if counter:GetAttribute("sh-valid") ~= true or
            id ~= entry.buttonID or (id <= 0 and currentSlot(entry.button, entry.barSize) ~= entry.slot) or
            kind ~= "spell" or spellID ~= entry.spellID or
            entry.button.enableSpellFX ~= true or entry.button.isExtra or entry.button.buttonType == "MULTICASTACTIONBUTTON" or
            forbidden(entry.button) or forbidden(entry.castFrame) or forbidden(entry.burst) or
            cast ~= entry.castFrame or not cast or cast.EndBurst ~= entry.burst or
            not cast.Fill or cast.Fill.CastingAnim ~= entry.animation or
            call(cast.GetParent, cast) ~= entry.button or call(entry.burst.GetParent, entry.burst) ~= cast or
            call(entry.animation.GetLooping, entry.animation) ~= "REPEAT" then
            return {category = "configuration", reason = "Rule " .. (record.sourceIndex or index) .. ": the cast-count action slot, spell rank, or native source changed."}
        end
        if call(entry.button.IsVisible, entry.button) ~= true or currentSlot(entry.button, entry.barSize) ~= entry.slot then
            waiting = {category = "count-availability", reason = "A required cast-count action bar is temporarily unavailable."}
        end
    end
    return waiting
end

function Counts.Validate(rotation)
    local issue = Counts.PreparationIssue(rotation)
    if issue and issue.category ~= "count-availability" then return issue.reason end
end

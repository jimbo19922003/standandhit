local _, SH = ...
local Signal = {}
SH.DruidFormSignal = Signal

local slots = {}

local function prepare(slot)
    if type(slot) ~= "number" or slot < 1 or slot % 1 ~= 0 or slot > GetNumShapeshiftForms() then
        return nil, "That form is no longer on your stance bar. Prepare again."
    end
    local entry = slots[slot]
    if entry and entry.ready then return entry.frame end
    if not entry then
        -- No regions or parent. Hiding the UI or changing action bars must
        -- not generate a form change for proc and cast-count guards.
        entry = {frame = CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate")}
        slots[slot] = entry
    end

    -- Blizzard applies the driver's initial visibility at registration.
    -- Subsequent show/hide transitions come from the same secure driver.
    local frame = entry.frame
    frame:SetAttribute("sh-druid-form-slot", slot)
    RegisterStateDriver(frame, "visibility", ("[form:%d] show; hide"):format(slot))
    local active = GetShapeshiftForm()
    if type(active) ~= "number" or not frame:IsProtected() or frame:IsShown() ~= (active == slot) then
        return nil, "The stance bar and the form condition disagree. Try Prepare again."
    end
    entry.ready = true
    return frame
end

function Signal.Get(slot)
    if InCombatLockdown() then return nil, "Prepare the form condition outside combat." end
    local ok, frame, reason = pcall(prepare, slot)
    if ok and frame then return frame end
    local entry = slots[slot]
    if entry and not entry.ready then pcall(UnregisterStateDriver, entry.frame, "visibility") end
    return nil, ok and reason or ("The form condition could not be prepared: " .. tostring(frame))
end

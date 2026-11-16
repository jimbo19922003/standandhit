local _, SH = ...
local Judgements = {}
SH.Judgements = Judgements

-- Verified against Forever 1.60.1.70888 CooldownSetSpell,
-- CooldownSetLinkedSpell, Spell and SpellEffect. These are the four separate
-- target-aura entries, not the Seals group or Judgement's cast cooldown.
-- Same-name healing/mana procs are deliberately absent from these families.
local families = {
    {baseID = 21183, trackerID = 200379, name = "Judgement of the Crusader",
        ranks = {21183, 20188, 20300, 20301, 20302, 20303}},
    {baseID = 20185, trackerID = 200380, name = "Judgement of Light",
        ranks = {20185, 20344, 20345, 20346}},
    {baseID = 20184, trackerID = 200381, name = "Judgement of Justice", ranks = {20184}},
    {baseID = 20186, trackerID = 200382, name = "Judgement of Wisdom", ranks = {20186, 20354, 20355}},
}
local familyByID = {}
for _, family in ipairs(families) do
    for _, id in ipairs(family.ranks) do familyByID[id] = family end
end
local metadataKeys = {"spellID", "overrideSpellID", "overrideTooltipSpellID", "selfAura", "hasAura",
    "charges", "flags", "equipSlot", "spellCategoryID"}
local spellKeys = {"spellID", "overrideSpellID", "overrideTooltipSpellID"}
local unrelated = "the Judgement tracker includes an unrelated spell. Use its dedicated entry in Tracked Buffs or Tracked Bars."
local configure = "add this Judgement to Blizzard's Tracked Buffs or Tracked Bars, close settings, then Prepare."

local function localizedName(family, spellName)
    if type(spellName) ~= "function" then return nil end
    for _, id in ipairs(family.ranks) do
        local name = spellName(id)
        if type(name) == "string" and name ~= "" then return name end
    end
end

local function inputMatches(family, input, spellName)
    local text = SH.Model.Trim(input)
    local id = tonumber(text)
    if id then return familyByID[id] == family end
    local name = localizedName(family, spellName)
    return text:lower() == (name or family.name):lower()
end

local function familyForInput(input, spellName)
    local id = tonumber(SH.Model.Trim(input))
    if id then return familyByID[id] end
    for _, family in ipairs(families) do
        if inputMatches(family, input, spellName) then return family end
    end
end

function Judgements.IsEntry(entry)
    return entry ~= nil and familyByID[entry.baseID] ~= nil
end

function Judgements.Matches(entry, input, spellName)
    local family = entry and familyByID[entry.baseID]
    return family ~= nil and inputMatches(family, input, spellName)
end

local function metadataError(info, family)
    if type(info) ~= "table" then return unrelated end
    if info.equipSlot or info.spellCategoryID then
        return "item and category trackers cannot be used as Target debuff."
    end
    -- The verified applied-effect IDs identify this family even when the
    -- viewer's selfAura/hasAura metadata is incomplete. TargetEffect checks
    -- the player's actual harmful aura on the current target separately.
    for _, key in ipairs(spellKeys) do
        local id = info[key]
        if id ~= nil and familyByID[id] ~= family then return unrelated end
    end
end

local function entryError(entry, family)
    local reason = metadataError(entry.metadata or {}, family)
    if reason then return reason end
    for id in pairs(entry.ids or {}) do
        if familyByID[id] ~= family then return unrelated end
    end
    for id in pairs(entry.linkedIDs or {}) do
        if familyByID[id] ~= family then return unrelated end
    end
end

function Judgements.Resolve(entry, input, spellName)
    if not Judgements.Matches(entry, input, spellName) then return nil end
    local family = familyByID[entry.baseID]
    local reason = entryError(entry, family)
    if reason then return nil, reason end
    local ids = {}
    for _, id in ipairs(family.ranks) do ids[id] = true end
    local name = localizedName(family, spellName)
    return {name = name or family.name, ids = ids, unit = "target", skipNameLookup = not name}
end

local function configuredInfo(family)
    local settings = CooldownViewerSettings
    if not settings or type(settings.GetDataProvider) ~= "function" then return nil end
    local ok, provider = pcall(settings.GetDataProvider, settings)
    if not ok or not provider or type(provider.GetCooldownInfoForID) ~= "function" then return nil end
    local infoOK, info = pcall(provider.GetCooldownInfoForID, provider, family.trackerID)
    if infoOK and type(info) == "table" then return info end
end

local function infoError(info, family)
    if not info then return configure end
    if info.isInvisible == true then return configure end
    if info.spellID ~= family.baseID or (info.cooldownID ~= nil and info.cooldownID ~= family.trackerID) then
        return unrelated
    end
    local reason = metadataError(info, family)
    if reason then return reason end
    if type(info.linkedSpellIDs) ~= "table" then return unrelated end
    for _, id in ipairs(info.linkedSpellIDs) do
        if familyByID[id] ~= family then return unrelated end
    end
end

local function configuredViewer(category)
    local categories = Enum and Enum.CooldownViewerCategory
    local visible = Enum and Enum.CooldownViewerVisibleSetting
    if not categories or not visible or visible.Always == nil then return nil, configure end
    local viewer
    if category == categories.TrackedBar and categories.TrackedBar ~= nil then
        viewer = BuffBarCooldownViewer
    elseif category == categories.TrackedBuff and categories.TrackedBuff ~= nil then
        viewer = BuffIconCooldownViewer
    else
        return nil, configure
    end
    if not viewer or type(viewer.IsShown) ~= "function" then return nil, configure end
    local shownOK, shown = pcall(viewer.IsShown, viewer)
    if not shownOK or shown ~= true then return nil, "enable and show this Judgement's Buff Bars or Buff Icons group." end
    if viewer.visibleSetting ~= visible.Always then
        return nil, "set this Judgement's Buff Bars or Buff Icons group's visibility to Always."
    end
    local getter = C_CVar and C_CVar.GetCVarBool or GetCVarBool
    if type(getter) == "function" then
        local ok, enabled = pcall(getter, "cooldownViewerEnabled")
        if ok and enabled == false then return nil, "enable Blizzard's Cooldown Manager, then Prepare." end
    end
    return viewer
end

local function findConfigured(input, spellName)
    local family = familyForInput(input, spellName)
    if not family then return nil end
    -- This provider applies the user's saved category changes. Reading the
    -- raw C_CooldownViewer default category would also admit hidden entries.
    -- isKnown may be false for an applied effect which is not learned itself;
    -- that is why a configured record can lack an allocated runtime frame.
    local info = configuredInfo(family)
    local reason = infoError(info, family)
    if reason then return nil, reason end
    local viewer, viewerReason = configuredViewer(info.category)
    if not viewer then return nil, viewerReason end
    local name = localizedName(family, spellName) or family.name
    local entry = {baseID = family.baseID, cooldownID = family.trackerID, viewer = viewer,
        name = name, ids = {[family.baseID] = true}, names = {[name:lower()] = true}, linkedIDs = {},
        auraIDs = {}, auraNames = {[name:lower()] = true}, metadata = {}, ambiguous = false,
        auraAmbiguous = false, effectLinkCount = #info.linkedSpellIDs, judgementConfig = true,
        configuredCategory = info.category, effectInput = input, auraSource = "target"}
    for _, key in ipairs(metadataKeys) do entry.metadata[key] = info[key] end
    for _, key in ipairs(spellKeys) do
        local id = info[key]
        if id then entry.ids[id] = true end
    end
    for _, id in ipairs(info.linkedSpellIDs) do
        entry.ids[id], entry.linkedIDs[id], entry.auraIDs[id] = true, true, true
    end
    if info.overrideTooltipSpellID then entry.auraIDs[info.overrideTooltipSpellID] = true end
    if not next(entry.auraIDs) then entry.auraIDs[info.overrideSpellID or family.baseID] = true end
    entry.targetEffect, reason = Judgements.Resolve(entry, input, spellName)
    if not entry.targetEffect then return nil, reason end
    return entry
end

local function checkConfigured(entry)
    local family = entry and familyByID[entry.baseID]
    if not family or entry.judgementConfig ~= true or entry.baseID ~= family.baseID or
        entry.cooldownID ~= family.trackerID then return configure end
    local info = configuredInfo(family)
    local reason = infoError(info, family)
    if reason then return reason end
    if info.category ~= entry.configuredCategory then return "this Judgement's tracker group changed. Prepare again." end
    local viewer, viewerReason = configuredViewer(info.category)
    if not viewer then return viewerReason end
    if viewer ~= entry.viewer then return "this Judgement's tracker was rebuilt. Prepare again." end
    -- A different active rank can legitimately change the native tooltip or
    -- spell override. infoError still rejects any alias outside this family;
    -- the target reader continues to accept every verified rank in the family.
    -- Recheck membership in both directions without allocating scratch sets.
    local linked = entry.linkedIDs
    if not linked or #info.linkedSpellIDs ~= entry.effectLinkCount then return unrelated end
    for _, id in ipairs(info.linkedSpellIDs) do
        if linked[id] ~= true then return unrelated end
    end
    for id in pairs(linked) do
        local found = false
        for _, currentID in ipairs(info.linkedSpellIDs) do
            if currentID == id then found = true; break end
        end
        if not found then return unrelated end
    end
    return nil
end

function Judgements.FindConfigured(input, spellName)
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, entry, reason = pcall(findConfigured, input, spellName)
    if not ok then return nil, "this Judgement's tracker settings are unavailable. Close settings and Prepare again." end
    return entry, reason
end

function Judgements.CheckConfigured(entry)
    -- Configuration is public setup state, never a combat aura signal. The
    -- existing TargetEffect reader owns current-target aura presence in combat.
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, reason = pcall(checkConfigured, entry)
    if not ok then return "this Judgement's tracker settings are unavailable. Prepare again." end
    return reason
end

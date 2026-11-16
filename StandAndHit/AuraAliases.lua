local _, SH = ...

local Aliases = {}
SH.AuraAliases = Aliases

-- The tracker names the talent, while the applied proc has a different name.
-- Only aura inputs use this mapping; spell actions and explicit IDs retain
-- their meaning. Resolve the two localized names from their known IDs too.
local shadowTranceID, nightfallID = 17941, 18094
local englishNames = {nightfall = true, ["shadow trance"] = true}

local function publicName(spellName, id)
    if type(spellName) ~= "function" then return nil end
    local ok, name = pcall(spellName, id)
    if not ok or (type(issecretvalue) == "function" and issecretvalue(name)) then return nil end
    if type(name) == "string" and name ~= "" then return name:lower() end
end

function Aliases.Resolve(input, source, spellName)
    if type(input) ~= "string" then return input end
    if source ~= nil and source ~= "tracker" and source ~= "player" then return input end
    local text = input:match("^%s*(.-)%s*$")
    if tonumber(text) then return input end
    local lower = text:lower()
    if englishNames[lower] or lower == publicName(spellName, shadowTranceID)
        or lower == publicName(spellName, nightfallID) then
        return tostring(shadowTranceID)
    end
    return input
end

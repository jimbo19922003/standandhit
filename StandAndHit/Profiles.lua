local _, SH = ...
local M = SH.Model
local Profiles = {COUNT = 5}
SH.Profiles = Profiles

local rotationKeys = {"secondRotation", "thirdRotation", "fourthRotation"}
-- Global Advanced, controller rumble, and minimap settings stay on the root.
local fields = {
    "enabled", "rules", "preparedRules", "preventClipping", "preparedPreventClipping",
    "autoPrepare", "showButton", "hideUIErrors", "hideTooltip", "point", "directKey",
    "gamePadKey", "manualPrepareFailed", "preparationState", "preparationRequest", "preparationSerial",
}

function Profiles.ValidIndex(index)
    return type(index) == "number" and index == math.floor(index) and index >= 1 and index <= Profiles.COUNT
end

local function copyRotation(source)
    local result = {}
    for _, key in ipairs(fields) do result[key] = M.Copy(source[key]) end
    return result
end

local function emptyRotation(index)
    return {
        enabled = index == 1, rules = {}, preventClipping = true, autoPrepare = true,
        showButton = true, hideUIErrors = false, hideTooltip = false,
        point = {point = "BOTTOM", relativePoint = "BOTTOM", x = (index - 1) * 90, y = 160},
    }
end

function Profiles.Save(root)
    local profile = root.profiles[root.activeProfile]
    profile.rotations = {copyRotation(root)}
    for index = 2, 4 do
        profile.rotations[index] = copyRotation(root[rotationKeys[index - 1]] or emptyRotation(index))
    end
end

function Profiles.Initialize(root)
    if type(root.profiles) ~= "table" then root.profiles = {} end
    if not Profiles.ValidIndex(root.activeProfile) then root.activeProfile = 1 end
    for index = 1, Profiles.COUNT do
        local profile = root.profiles[index]
        if type(profile) ~= "table" then profile = {}; root.profiles[index] = profile end
        if type(profile.name) ~= "string" or M.Trim(profile.name) == "" then profile.name = "Profile " .. index end
        if type(profile.rotations) ~= "table" then profile.rotations = {} end
        for button = 1, 4 do
            local rotation = profile.rotations[button]
            if type(rotation) ~= "table" then rotation = {}; profile.rotations[button] = rotation end
            for key, value in pairs(emptyRotation(button)) do
                if rotation[key] == nil then rotation[key] = M.Copy(value) end
            end
            if type(rotation.rules) ~= "table" then rotation.rules = {} end
            if type(rotation.point) ~= "table" or not rotation.point.point then rotation.point = emptyRotation(button).point end
        end
    end
    -- The root is the live saved profile. Refresh its snapshot on login so
    -- edits made after the last switch are never overwritten by an older copy.
    Profiles.Save(root)
    root.profileVersion = 1
end

function Profiles.Apply(root, index)
    if not Profiles.ValidIndex(index) then return false end
    local profile = root.profiles[index]
    if not profile or type(profile.rotations) ~= "table" then return false end
    for _, key in ipairs(fields) do root[key] = M.Copy(profile.rotations[1][key]) end
    for button = 2, 4 do root[rotationKeys[button - 1]] = copyRotation(profile.rotations[button]) end
    root.activeProfile = index
    return true
end

function Profiles.Rename(root, index, name)
    if not Profiles.ValidIndex(index) then return false, "Choose a profile from 1 to 5." end
    if type(name) ~= "string" then return false, "Enter a profile name." end
    name = M.Trim(name)
    if name == "" or #name > 40 or name:find("[%c|]") then
        return false, "Use a profile name from 1 to 40 characters, without formatting codes."
    end
    for other = 1, Profiles.COUNT do
        if other ~= index and root.profiles[other].name:lower() == name:lower() then
            return false, "Another profile already uses that name."
        end
    end
    root.profiles[index].name = name
    return true, "Profile renamed to " .. name .. "."
end

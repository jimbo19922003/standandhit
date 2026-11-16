Stand and Hit: WeakAuras
Version 0.1.1 | API version 1

INSTALL
Copy both StandAndHit and StandAndHitWeakAuras from the bundled ZIP into your
Interface\AddOns folder as separate folders. Restart WoW after adding a new
addon folder. In the Forever AddOns list, this companion appears under Stand
and Hit. Its checkbox can be disabled separately; Stand and Hit works without
it. Enable it and reload, then open /snh > Advanced and check WeakAuras
integration. This setting starts off and applies across all five profiles.

The companion requires StandAndHit. WeakAuras is needed to display an aura,
but is not a load dependency: other addons can read the same API.

READY MEANS
A Hit Button has a rule that currently qualifies in the active profile.
This is a display signal, not a guarantee that the next key press will cast.
Conditions, targets, cooldowns, and game restrictions may change before a
press. The API does not cast, press buttons, advance rules, or prepare macros.
It reads the four Hit Buttons from the currently active one of five profiles.
Draft edits do not take effect until you Prepare.

Skip if out of range is an optional exclusion. A confirmed out-of-range
result skips the rule. If WoW has no applicable range check, the rule can
still qualify through its other conditions. Restricted or invalid readings
return unknown; a missing range result is not a claim that the spell is in range.

WEAKAURAS EXAMPLE
Open /snh > Advanced and check WeakAuras integration. Click Setup and copy
trigger to choose a Hit Button and copy its code. The window has these
directions too. Open WeakAuras takes you to its options outside combat.

Create a Custom trigger. Choose Status and set Check On to Every Frame.
Use this Custom Trigger function for Hit Button 1:

function()
    local api = _G.StandAndHitWeakAuras
    return api ~= nil and api.IsHitButtonReady(1)
end

Change 1 to 2, 3, or 4 for another Hit Button. Both not-ready and unknown
return false, so an unavailable reading does not light up an aura.
Unchecking WeakAuras integration also returns false. Your displays stay saved.
Combat readings still need testing in game. If WoW hides an action-bar
reference used by Ping Delay or Cast Count, the API returns unknown even
though the Hit Button itself may still work.
The companion itself has no update loop; reads happen when callers request
them. Stand and Hit manages its own readiness snapshot caching.

PUBLIC API
All calls use a dot, not a colon.

StandAndHitWeakAuras.version                  -- "0.1.1"
StandAndHitWeakAuras.apiVersion               -- 1
StandAndHitWeakAuras.IsHitButtonReady(1)      -- boolean
StandAndHitWeakAuras.IsHitButton1Ready()      -- boolean
StandAndHitWeakAuras.IsHitButton2Ready()      -- boolean
StandAndHitWeakAuras.IsHitButton3Ready()      -- boolean
StandAndHitWeakAuras.IsHitButton4Ready()      -- boolean
StandAndHitWeakAuras.GetHitButtonReadiness(1) -- new result table

Result fields:
  state       "ready", "not-ready", or "unknown"
  reason      Explanation, when available
  buttonIndex Hit Button number, 1 through 4
  ruleIndex   Qualifying rule number, when available
  spellID     Spell ID, when available
  spellName   Spell name, when available
  icon        Spell texture path or numeric file ID, when available
  profileID   Actual active profile number, 1 through 5, when available
  profileName Actual active profile name, when available

Unavailable metadata is nil. Each call returns a separate table. Changing
the result does not change Stand and Hit. Invalid button indexes, a missing
host, an unsupported host contract, and failed reads return unknown.

DIAGNOSTIC
For Hit Button 1, enter this in chat:

/run local a=StandAndHitWeakAuras; if a then local r=a.GetHitButtonReadiness(1); print(r.state,r.reason or "",r.profileName or "") else print("Stand and Hit: WeakAuras is disabled or missing") end

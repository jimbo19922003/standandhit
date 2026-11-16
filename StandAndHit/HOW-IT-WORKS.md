# How Stand and Hit works

Version 1.11.1

Stand and Hit checks your rules each time you press a Hit Button and tries to
cast the first spell that qualifies. You choose the spells, their order, and
the conditions they need. For installation and setup, see README.txt.

## What happens on each press

Enabled rules normally run from top to bottom. Unchecking Enable Rule and clicking
Prepare skips that spell until you enable it and prepare again. Once a rule matches, lower rules don't get a
turn on that press. If nothing matches, the button does nothing. Put an
Always rule at the bottom if you want a filler spell.

IF, AND, OR, and NOT let you decide when each spell should be used:

- IF is the rule's starting condition.
- OR gives it another way to qualify.
- AND adds something that must also match.
- NOT blocks the rule when that condition matches.

For example, Arcane Blast can qualify when its buff is missing OR Clearcasting
is present. An added AND condition still has to match, whichever of those two
conditions allowed the spell. The casting spell's cooldown and its other
casting settings still apply.

For the first IF, choose Always or a condition type. When adding another
condition, choose AND, OR, or NOT first, then its type. These operators
work with auras, another spell's cooldown, combo points, resources, health,
stacks, aura time remaining, target casting, totems, hawks, and enabled custom macro conditions.

AND, OR, and NOT can also check another spell's cooldown. For example,
Eviscerate can require Kidney Shot to be on cooldown. Keep Kidney Shot in
Essential or Utility Cooldowns and choose Spell cooldown in the added
condition. On cooldown and Off cooldown check that spell; a global cooldown
alone doesn't count as On cooldown. A manual cooldown on Eviscerate still
applies separately.

Use fresh presses when you want the addon to choose again. Holding a key for
continuous casting keeps the spell chosen on the initial press. Release it
and press again to check the rules.

The Advanced tab lets you add a macro condition or choose a custom spell
recipient. A comma in `[harm,nodead]` means both checks must pass. In
`[@focus,help,nodead]`, the checks apply to your focus. Cast on chooses who
receives the spell.

Advanced also enables Modifiers under Other casting settings. Each rule can skip
while Ctrl, Alt, or Shift is held, or take priority while one of those keys
is held. Prioritized rules still need to pass every normal condition and
cooldown check. They run in their listed order before ordinary rules.
Skip takes precedence if both modifiers apply to the same rule. Releasing
the key restores normal priority.

Custom Rules adds a command rule such as /targetenemy. Each Hit Button can
have one enabled Custom Rule with several command lines. Its conditions
still apply. When it matches, the commands run first, then the Hit Button
checks its normal spell rules again on the same press. Use the visible Hit
Button, Set cast key, or Controller for this; action-bar macros cannot run
Custom Rules. Advanced explains the limitation and has separate examples
for Custom Target, Custom Conditions, and Custom Rules.

With Set cast key, the modifiers used by your prepared rules also work with
that key, including combinations. The cast key can be the same key as your
Hit Button macro. Click Prepare after changing rule modifiers. Clear key,
disabling the Hit Button, or removing a modifier and preparing again restores
the normal bindings for combinations no longer used. A combination assigned
to another Hit Button needs a different cast key.

For an action-bar macro without Set cast key, bind the modified keys to the
same action-bar slot yourself. The macro does not add those keybindings.

## What the conditions need

For ordinary Tracked aura and Target debuff rules, keep the tracker group
visible and set its entries to hide when inactive. Druid Forms and Curses
can share one icon for several spells. Enter the individual form or curse
you want to check. For Frostbite, enter the name of the freeze on the target.

Aura time remaining lets a rule check a buff or debuff against a number of
seconds. Track that individual aura in Tracked Bars with its timer visible.
The condition reads displayed whole seconds from 0 to 60. Timers shown in
another format do not match until they display seconds within that range.
A confirmed missing aura counts
as 0; an unreadable timer does not qualify the rule. For example, Hamstring
at most 3 seconds allows a refresh near the end, as well as a new application
when it is missing.

For hunter aspects, a Tracked aura rule follows your own active aspect.
For example, switching from Monkey to Hawk makes Monkey missing even
though the shared Aspects icon is still visible.

Paladin seals, auras, and blessings also use the individual spell name.
These Tracked aura conditions check your own buff on yourself. Normal and
Greater Blessings have separate names, so choose the one you want to check
or use OR to accept either.

Judgement of the Crusader, Light, Wisdom, and Justice use Target debuff.
These conditions check your Judgement on your current living enemy target.
Track the Judgement debuff in Tracked Buffs or Tracked Bars, with the group
visible Always. Cast on still applies to the spell you are casting, so a
seal can be cast on yourself based on a debuff missing from your target.

Player buff checks for Seal of the Crusader and Seal of Righteousness follow
your own seal across its ranks, including during combat. You can require the
seal to be missing so the rotation moves on after applying it.

Target-debuff conditions follow your debuffs on a living hostile target.
Gouge checks your incapacitate on that target. Entering Ghostly Strike in a
buff condition selects the proc that allows your next Ambush or Garrote
without Stealth. It stops matching when that proc is consumed, even if the
dodge buff is still active. Enter 14278 to check the dodge buff instead.
Changing Cast on changes who receives the spell, not which unit the tracker
watches. Skip while on cooldown needs the spell in the native cooldown tracker.

Nightfall and Shadow Trance both refer to the Shadow Trance proc, spell
17941. Use Player buff to check it without a tracker, or Tracked aura with
Nightfall in your tracker.

Riposte, Revenge, Overpower, Mongoose Bite, and Counterattack check whether
they are usable and off cooldown before the button selects them. Choose
Spell cooldown or Always and put the ability above your filler. These
spells need no aura or cooldown-tracker entry. Keep Cast on set to Target;
Overpower requires it. The ability's opening, resource cost, and stance
requirements still apply. An aura condition using the reactive ability's
own name checks its readiness, including in added AND, OR, and NOT conditions.

Battle Stance, Defensive Stance, and Berserker Stance conditions check your
current stance. Player buff and Tracked aura both accept the stance name,
without needing an aura or tracker entry.

**Target is casting** checks your current target when you press a Hit Button.
A cast or channel can qualify, including one that is immune to interrupts.
When your target is idle or the button can't confirm a cast, it tries the
next rule. Cast on still chooses who receives the spell.

**Out of combat only** skips that rule while you are in combat. Its other
conditions still apply outside combat. **In combat only** skips the rule
until combat starts. Choose either option under Other casting settings,
or leave both off to allow the rule in either state. Changing combat state
doesn't require another Prepare.

For Shaman totems, Off cooldown checks when the spell can be cast again.
Blizzard can show the remaining time on the ground in the same tracker.
Summoning, replacing, or losing the totem doesn't require another Prepare.

**Totem conditions** can check for an active totem or an empty slot.
Choose Fire, Earth, Water, or Air. Fire also lets you require Searing,
Magma, or either one. An empty-slot condition matches whether you
just logged in, the totem expired, you dismissed it, or an enemy killed it.
Each element is checked separately. Replacing one totem with another in the
same slot keeps that slot occupied, so an empty-slot rule won't overwrite it.
These conditions don't need a tracker entry.
For Fire Nova, choose **Spell cooldown** in IF, then add **AND > Totem
conditions** with **Searing or Magma active**. Nova needs an active totem
and its own cooldown must be ready.

Choose Player buff when you want to keep a totem's buff on yourself.
For Strength of Earth Totem, the buff is called Strength of Earth. As long
as you have it, even from another Shaman, a Buff is missing rule skips the
totem. Once the buff drops, that rule can cast again. If the game hides the
buff during combat, that condition can't make the rule cast.

Combo points can be added to any spell, including a builder or filler. They
check the current target's count, regardless of Cast on. You can require an
exact count, a minimum, a maximum, or anything except a chosen count. This
check doesn't need a tracker entry. An unreadable count cannot satisfy the
condition or count as a successful NOT exclusion.

Hawk conditions are available on Hunters and check how many of your Summon
Hawk hawks are active. Choose a comparison and a count from 0 to 2. The
condition works with any spell. Choose IF as its first condition, AND as a
requirement, OR as an alternative, or NOT as an exclusion.
It needs no tracker entry. If the count can't be read, rules that require a
Hawk count are skipped while other rules can still match.

Aura stacks checks a tracked player buff or target debuff against the count
you choose. AND adds a stack requirement, OR adds an alternative, and NOT
excludes a matching stack count. A confirmed missing aura counts as zero; an unreadable count skips that rule. This lets
you build Sunder Armor to five stacks, then move on to your other spells.
The tracker may take a moment to reflect a newly applied or removed aura.

Resource conditions check your Mana, Rage, or Energy as a percentage of its
maximum. Below (<) excludes the chosen percentage; At least (>=) includes it.
Resource conditions follow the operator you chose. Cast on doesn't change
whose resources are checked, and no tracker entry is needed. An unavailable
resource doesn't match. An unreadable check cannot satisfy the condition.

Enemy health checks your current living enemy's health percentage on each
press. Choose Below (<) or At least (>=) and a percentage from 0 to 100.
It works alongside the rule's other conditions and needs no tracker entry.
Cast on still chooses who receives the spell. Without a living enemy or a
readable health value, this condition cannot match.

Self health uses the same percentage choices for your own health. It
works without a target selected. You can use it alongside Enemy health
or other conditions, using AND, OR, or NOT. Cast on
still chooses who receives the spell.

## Manual cooldowns

Manual cooldown lets you enter a spell's cooldown in seconds. It starts when
the spell successfully casts and works alongside its tracked-aura conditions.
For example, a missing-buff rule only qualifies when the buff is missing and
the manual timer has finished. It replaces the cooldown-tracker check for
that rule. Keep the spell's chosen rank on a visible Blizzard action bar.

## Skip if immune (bleed)

This optional setting skips recognized bleed spells against Mechanical enemies.
For other enemy types, it watches for an Immune response immediately after
your cast. If a bleed returns Immune, all checked bleed rules skip that enemy
until combat ends. An immune Rake also skips Rip, for example. Unchecked rules
keep their usual behavior.
Misses, parries, and insufficient rage or energy do not mark an enemy immune.

The game does not identify the spell or caster in that response. This beta uses
timing, so another player's immunity result can be mistaken for yours.

## Ping Delay

Each rule has an optional Ping Delay, starting at 100 milliseconds. Use it if
a spell with a buff or debuff is double casting. That rule waits during its
cast and briefly after completion, giving the tracker time to update. Other
matching rules can still be selected. A failed attempt can be retried; the
delay never casts anything on its own. Keep the spell's chosen rank on a
visible Blizzard action bar and click Prepare after changing the setting.

## Counting completed casts

Number of times to cast attaches to one tracked-buff condition in a rule.
It counts completed casts, so failed or interrupted attempts don't advance it.
This option needs a regular cast-time spell on a fixed, visible Blizzard
action bar; instant spells and channels can't use it.

A counted missing-buff condition can keep its batch going after the buff
appears. Once the limit is reached, it waits for the buff to disappear before
starting again. A counted present-buff condition needs the buff to stay active
and rearms after it disappears and returns. Higher-priority rules and the
rule's other requirements still apply.

An uncounted OR can allow a cast without starting the counted condition's
batch. Once a batch is running, matching casts made manually or through
another rotation can count too. Repeated presses during the final cast clear
the queue so the counted condition doesn't queue an extra cast.

## Drafts and Prepare

Editing changes your draft. Prepare applies it to the button outside combat.
Until then, the button keeps its last successfully prepared rules. Each
profile has four rotations with their own drafts and prepared setups.

Choose between five profiles using the dropdown at the top of the window.
Your existing setup becomes Profile 1, and Rename lets you name any profile.
Switch outside combat. The same four Hit Buttons and macros use the selected
profile's rotations, key and controller assignments, button positions, and
casting preferences. Restore at login also restores a saved rotation when
you switch back to that profile. Advanced options, the minimap button, and
controller rumble settings are shared between profiles.

Tracker, talent, or spell changes can require preparation again. Prepare on
the preparation notice restores the saved setup; Prepare in the editor applies
your draft. Dismissing a notice doesn't restore casting. If CHECK SETUP appears
during combat, stop using the button until combat ends.

## Keys, controllers, and channels

The action-bar macro and on-screen button handle normal rotation casting.
For Stop current cast or Stop if buffs change, use a key assigned through
Set cast key or a controller button assigned in Controller. Those options
check for an interrupt when you press; changing buffs alone won't stop a cast.
Stop if buffs change tracks the last requested rule, so it can also stop a
later manual cast when that rule's buffs change.

Keep Protect channels enabled to prevent presses from clipping a channel.
Once per proc also needs that protection and a press during the channel to
confirm it. A buff refresh that never disappears can't be recognized as a
new proc.

## Auto attacks and pets

Auto Attack starts your melee swings against your current enemy and tries
the next matching ability on the same press. Repeated presses don't toggle
your swings off.

Wand Shoot and hunter Auto Shot keep firing while you press the Hit Button.
If shooting stops, another press can restart it. Put spells you want to
cast between shots above the ranged attack.

Pet Attack sends your pet to your current enemy. Once your pet has that
target, the button moves on to the next matching rule. You can put Pet
Attack above your opener and use the same Hit Button to start both.

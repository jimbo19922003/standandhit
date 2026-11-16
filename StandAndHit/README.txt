Stand and Hit (S&H): setup guide
Version 1.11.1
WoW Forever 1.60.1 / Interface 16001

Install the addon

1. Extract the StandAndHit folder from the download into your game's
   Interface/AddOns folder. The addon file should be at:
   Interface/AddOns/StandAndHit/StandAndHit.toc
   The ZIP also includes StandAndHitWeakAuras. Copy that separate folder into
   AddOns if you want the optional WeakAuras interface. It appears beneath Stand
   and Hit in the AddOns list and can be disabled independently.
2. Restart the game, then enable Stand and Hit in the AddOns list.
3. Type /snh or /standandhit, or click the S&H minimap button.

For later updates, replace the StandAndHit folder and restart the game.
Your saved settings stay. If you're moving from an earlier addon, export
its rotations before removing it. Import them into Stand and Hit, then set
up your trackers, macros, keys, and local preferences again. Don't run both
addons together.

Set up your first rotation

1. Leave combat, open /snh, choose a Profile, and select the Hit Button tab.
   Your existing setup starts in Profile 1.

2. If you'll use Tracked aura, Target debuff, Aura stacks, Aura time
   remaining, or a tracked spell cooldown,
   check Enable tracker beside Prepare. Its label is red when Blizzard's
   Cooldown Manager is disabled.
   Click Open trackers to set up the entries you need:
   - Buffs and target debuffs: add them to Buff Bars or Buff Icons. Enable
     Hide when inactive and keep the group visible Always.
   - Spell cooldowns: add them to Essential Cooldowns or Utility Cooldowns
     and keep that group visible Always.
   - Druid forms: add the Druid Forms group to Tracked Buffs or Tracked Bars.
     One entry covers all your learned forms in that group.
   - Hunter aspects: add Aspects to Tracked Buffs or Tracked Bars. The
     same entry covers the individual aspects listed under it.
   - Paladin seals: add Seals to Tracked Buffs or Tracked Bars. For auras
     and blessings, add the entry containing the spell you want to check.
     Enter the individual spell name in your rule, including Greater if
     you want to check a Greater Blessing.
   - Paladin Judgement debuffs: add Judgement of the Crusader, Light,
     Wisdom, or Justice to Tracked Buffs or Tracked Bars. Keep that group
     visible Always and use Target debuff in the rule.
   The Player buff aura condition checks your character directly and needs
   no tracker entry. Aura stacks and Aura time remaining still need one for
   player buffs. Combo points, resources, Enemy health, and Self health
   work without a tracker.

3. Close Cooldown Manager settings and Edit Mode before continuing.

4. Click + Add spell. Enter a learned spell name in your game's language or
   a spell ID. Choose Highest learned or a specific learned Rank, then set
   Cast on to Target, Self, Party 1-4, Focus, Target of focus, or Mouseover.
   Target of focus casts on whoever your focus is targeting. Party numbers
   follow the game's party slots.

5. Choose Always or a condition type from the first IF menu. For example,
   choose Resources to make the first condition Mana >= 50%, or Enemy
   health for a health threshold. Choose Aura for a buff or debuff check:
   - Aura is present or Aura is missing: choose Tracked aura and enter the
     aura's name or ID. To check a buff on your own character, choose
     Player buff and enter the buff's name or ID. For your target's debuff,
     choose Target debuff and Debuff is present or Debuff is missing.
     For a druid form, choose Tracked aura and enter the individual form's
     name or spell ID. For example, set Claw to Aura is present with Cat Form.
     Switching to Dire Bear Form makes that Cat Form condition false.
     To keep Aspect of the Monkey up, put it above your attacks, set Cast on
     to Self, and choose Tracked aura > Aura is missing. Enter Aspect of the
     Monkey in the aura field and click Prepare. Once Monkey is active, the
     button moves on to your attacks. Switching to Hawk makes Monkey missing
     again. Use Aura is present for a spell you only want while Monkey is up.
     Cast Count, Once per proc, and Stop current cast need a separate tracker
     if you attach them to the aspect itself.
     For a grouped warlock curse, track Curses and enter the individual
     curse under Target debuff. Choose Debuff is missing to apply your
     Curse of Weakness when the current target doesn't have yours.
     For a paladin, choose Tracked aura and enter the individual seal, aura,
     or blessing name. For example, set Seal of Righteousness to Self with
     Aura is missing and enter Seal of Righteousness. These conditions
     check buffs you applied to yourself. Player buff can check a blessing
     or aura on you from another paladin.
     For Ice Lance, add Frostbite to Tracked Buffs or Tracked Bars. Set IF
     to Aura, choose Target debuff and Debuff is present, and enter Frostbite.
     For Riposte and similar abilities, see Use a reactive ability below.
     For Gouge, add Gouge to Tracked Buffs or Tracked Bars, then choose
     Target debuff and enter Gouge. This checks your Gouge on the current
     target. Leave Once per proc and Stop current cast off for this condition.
     For Ghostly Strike's Ambush/Garrote proc, choose Player buff > Buff is
     present and enter Ghostly Strike. The dodge buff has the same name; enter
     14278 to check that buff instead. Neither needs a tracker entry.
     For Nightfall, choose Player buff > Buff is present and enter Nightfall
     or Shadow Trance. Both names check the Shadow Trance proc (17941).
     Tracked aura also accepts either name with Nightfall in your tracker.
     For Warrior stances, choose Player buff or Tracked aura and enter Battle
     Stance, Defensive Stance, or Berserker Stance. Present means you are in
     that stance; missing means you aren't. No tracker entry is needed.
   - Spell cooldown: checks whether this spell is off cooldown. This needs
     its Essential or Utility entry unless you use Manual cooldown or one
     of the reactive abilities listed below.
   - Always: use this for a spell that doesn't need an aura condition.
   Cast on chooses who receives the spell. It doesn't change whose aura is
   being watched. See the optional setup sections below for more conditions.

   To refresh an aura before it expires, choose Aura time remaining. Select
   Player buff or Target debuff, enter the aura's name or ID, and choose a
   comparison and whole seconds from 0 to 60. For example, Hamstring with
   At most (<=) 3 matches at 3 displayed seconds or less, or when missing.
   Add the aura to Tracked Bars with its timer visible and Hide when inactive
   enabled. Timers shown in another format do not match until they display
   seconds within that range. An unreadable timer does not match. Prepare
   outside combat.
   You can also add this condition through AND, OR, or NOT.

6. Use Up and Down to put spells in priority order. The first matching rule
   wins, so put your spammable fallback last. A simple mage setup is:
   1. Arcane Missiles: Aura is present, Missile Barrage, Target.
   2. Frostbolt: Always, Target.
   Track Missile Barrage, check Once per proc under Other casting settings
   for Arcane Missiles, and keep Protect channels checked. For another class,
   use your own proc spell and fallback. Each rotation holds up to 32 rules.
   To skip a spell, uncheck Enable Rule beside its number and click Prepare.
   Check it again and Prepare to bring it back in the same spot.
   For a spell you only want outside combat, check Out of combat only
   under the visible Other casting settings. The rule is skipped
   during combat and can match again once combat ends.
   Check In combat only instead to skip the rule until combat starts.
   Checking either option unchecks the other. Leave both off to allow the
   rule in either state. Its other conditions still need to match.

7. Click Prepare outside combat. It applies this tab's draft. If setup fails,
   follow the message and try again. Some aura entries need to appear once
   before they can be prepared; trigger the aura, leave combat, and retry.

8. Choose how to use the rotation:
   - Keyboard: click Set cast key, then press and release your chosen key.
     Ctrl, Alt, and Shift combinations work. Escape cancels assignment;
     Clear key restores the key's normal binding. You can use the same key
     as your Hit Button macro. See Use modifier keys below for rule modifiers.
   - Action bar: click Drag macro to bar and drop the generated Hit Button
     macro into a slot. Use that slot's normal keybind. There's nothing to
     paste. Keep the generated macro so Prepare can update it when needed.
   - Controller: follow Controller setup below.
   Use a direct cast key or assigned controller button for Stop current cast
   and Stop if buffs change. Target is casting works with any Hit Button input.

Press again for each cast. Holding a key keeps its first selected spell.
After editing rules or ranks, click Prepare again to apply the changes.

Use a reactive ability

Riposte, Revenge, Overpower, Mongoose Bite, and Counterattack can sit above
your filler without needing an aura condition or a tracker entry.

1. Add the spell and set Cast on to Target. Overpower requires Target.
2. Choose Spell cooldown in IF (Off cooldown), or Always if you want to
   start with no condition. The addon still checks whether the ability is
   usable and its cooldown is ready.
3. Put it above your filler, leave Once per proc off, and click Prepare.

An existing condition such as AND Player buff: Revenge is present checks
whether Revenge is ready to use. It doesn't need an actual Revenge buff.
Stance conditions still apply separately. The same handling applies to the
other reactive abilities above and to IF, OR, and NOT conditions.

The button skips the spell until its opening is available. You still need
the required stance and enough resources. Existing Riposte aura rules work
as before.

Check a Judgement debuff

1. Add the Judgement debuff to Tracked Buffs or Tracked Bars, set that group
   to Always visible, and close tracker settings.
2. Choose Target debuff and enter its name, such as Judgement of the Crusader.
   Choose Debuff is present or Debuff is missing.
3. Set Cast on for the spell being cast. Seal of the Crusader uses Self;
   Judgement uses Target. The debuff condition always watches your current
   living enemy target, whichever spell you choose.
4. Click Prepare. Leave Once per proc and Stop current cast off for this
   condition.

For a Seal of the Crusader rule, add AND / Player buff / Buff is missing /
Seal of the Crusader as well. This lets a lower Judgement rule run once the
seal is up, instead of repeatedly casting the seal while the debuff is missing.
For Seal of Righteousness, add the same Player buff / Buff is missing check
using Seal of Righteousness. These two seal checks work in combat and need
no separate Seals tracker entry.

Set a Hawk condition on a Hunter

1. Select Hawk conditions in the IF menu, or add AND > Hawk conditions.
2. Choose a comparison and a count of 0, 1, or 2. For Summon Hawk, use
   Fewer than (<) and 2 to cast it while fewer than two hawks are active.
3. Choose Spell cooldown in IF for Summon Hawk and put its cooldown in
   Essential or Utility Cooldowns. Set Cast on to Target.
4. Click Prepare outside combat. Put your other attacks below this rule.

Hawk conditions can be added to any spell. For example, add Equal to (=)
and 2 to another ability if you only want it while both hawks are out.
With AND, the count applies to every IF / OR alternative in that rule. The Hawk
condition itself needs no tracker entry; Off cooldown still needs one.

Keep an Earth, Water, or Air totem out

1. Add the totem, set Cast on to Self, and set IF to Always.
   If the spell has its own cooldown, choose Spell cooldown in IF and track it in
   Essential or Utility Cooldowns.
2. Under + Casting conditions > AND, choose Totem conditions. Choose Earth, Water,
   or Air in the element dropdown and leave the mode set to that slot being
   empty, for example Earth slot empty.
3. Put this rule above your filler and click Prepare outside combat.

The rule drops the totem when that element's slot is empty, including after
it expires, is destroyed, or is dismissed. Another totem in the same slot
keeps the rule from replacing it. Each element is checked separately.
These conditions don't need a tracker entry.

To require a totem before casting another spell, add AND > Totem conditions,
choose its element, and select Any Earth totem active (or Water, Air, or
Fire). This checks whether the totem is still out. Use Off cooldown as
well if the spell has a cooldown.
For a buff-based rule, keep using the buff's present/missing condition.

Replace a buff totem when you move away

1. Set the totem's Cast on to Self.
2. Choose Player buff > Buff is missing. Enter Windfury Totem for Windfury,
   or Strength of Earth for Strength of Earth Totem. Use the buff's name
   for other totems, such as Stoneskin, Grace of Air, or Mana Spring.
3. Remove any slot-empty condition from this rule. A totem can still
   occupy its slot after you leave its range.
4. Keep a cooldown check for totems with their own cooldown. Put the rule
   above your filler and click Prepare outside combat.

The next eligible press replaces the totem after its buff leaves your
character. Another shaman's matching buff counts too. This setup follows
your own buff, even if other party members are still near the old totem.

Use Searing Totem and Fire Nova on one Hit Button

1. Enable the tracker and put Fire Nova in Essential or Utility Cooldowns.
   Set the group to Always visible and close Cooldown Settings.
2. Put Searing Totem first. Set Cast on to Self and IF to Always. Under
   + Casting conditions > AND, choose Totem conditions. This drops Searing when your
   fire slot is empty, including before your first summon.
3. Put Fire Nova second. Set Cast on to Self and IF to Spell cooldown. Under
   + Casting conditions > AND, choose Totem conditions, select Fire, then
   Searing or Magma active. Click Prepare outside combat.

You can drop Magma by hand and keep pressing the same button. Nova uses
whichever totem is up. Once your fire slot empties, the button drops
Searing again. Add a filler below Nova if you want something to cast
while it's cooling down. Searing and Magma don't need tracker entries.

If you used the Fire Totems companion, turn it off at character select.
If you're reusing its two rules, remove the old Custom Conditions from
both rows before adding the new options.

Use Kick when your target is casting

1. Add Kick above your filler spell. Set Cast on to Target and IF to Always.
2. Open + Casting conditions > AND and choose Target is casting. Click Prepare.
3. Press the Hit Button while an enemy is casting to try Kick. Between casts,
   the button moves on to the next matching rule. Channels also qualify.
   The enemy may be casting a spell that cannot be interrupted.

To skip Kick while it is on cooldown, track Kick in Essential Cooldowns or
Utility Cooldowns and change IF to Spell cooldown. The casting check itself
works without a tracker entry.

Use a macro target or condition

1. Open Advanced next to the Hit Button tabs. Check Custom Target, Custom
   Conditions, or both. Custom Target examples and Custom Conditions examples
   each open their own reference for WoW Forever.
2. Return to a Hit Button tab. For a custom recipient, choose Custom Target
   under Cast on and enter a unit such as @focus or @party2target.
3. To add a macro check, open Casting conditions > AND and choose Custom Conditions.
   Enter [harm,nodead] to require a living enemy, or [@focus,help,nodead] to
   check for a living friendly focus. Choose Cast on separately.
4. Click Prepare. Turning either switch off hides that option for new rules.
   Rules you've already set up or imported keep their targets and conditions.

Use a Custom Rule

1. Open Advanced and check Custom Rules. Custom Rule examples lists the
   supported commands and shows how to type them.
2. Choose + Action > Custom Rule. Each Hit Button can have one enabled
   Custom Rule, with several commands on separate lines. Its IF, AND, OR,
   and NOT conditions decide when it runs.
3. For Tab-style targeting, enter /targetenemy. That cycles enemies on each
   matching press. To select an enemy only when your target is missing or
   dead, enter /targetenemy [noexists][dead] instead.
4. Keep the Custom Rule above Auto Attack. If Auto Attack uses Prioritize if,
   give the Custom Rule the same modifier so it stays first.
5. Prepare, then use the visible Hit Button, Set cast key, or Controller.
   Custom Rules cannot run through the action-bar macro. Set cast key can
   use the same key you normally press for that macro.

The commands run once, then the button checks the normal spell rules again
on the same press. After a targeting command runs, rules that depend on
the target's tracked aura wait for another press. Other commands and spell
casts still follow WoW's usual requirements and global cooldown.
Automatic cast interruption is not applied on a press that runs the commands.
Include /stopcasting if they should interrupt your current cast. If every
command's bracket conditions fail, the normal interruption settings still apply.

Use modifier keys

1. Open Advanced and check Modifiers.
2. Return to a Hit Button tab and select a rule. Its Modifiers controls
   appear below the conditions.
3. Set Skip if or Prioritize if to Ctrl, Alt, or Shift. Both start at None.
   For example, Skip if Ctrl skips that rule while you hold Ctrl.
   Prioritize if Alt checks that rule ahead of ordinary rules while Alt is held.
4. Assign a key through Set cast key, then click Prepare outside combat.
   Hold the chosen modifier while pressing that key. For example, if your
   cast key is 1 and a prepared rule uses Ctrl, Ctrl+1 casts through the same
   Hit Button. Combinations of the prepared modifiers work too. You can
   assign the same base key you already use for the Hit Button macro.

Changes to rule modifiers take effect when you click Prepare. Clear key or
disable that Hit Button to restore the affected keys' normal bindings.
Removing a modifier and preparing again also restores combinations that
are no longer used. If a combination is assigned to another Hit Button,
choose another cast key.

If you only use an action-bar macro, assign each modified key to that same
action-bar slot in WoW's keybindings, or use Set cast key. The macro alone
doesn't add those keybindings. Clicking the on-screen Hit Button while
holding a modifier also works.

Prioritize keeps the rule's conditions and cooldown checks. If several
rules are prioritized, their listed order decides which is checked first.
Skip wins when both settings apply. Release the key to return to normal
priority. Choose None or click Reset to clear a rule's modifiers.
Turning Modifiers off in Advanced hides the choice for new rules; existing
rules keep their settings and remain editable.

If this rotation uses Ctrl, Ctrl+left-click casts and Ctrl+right-click hides
or shows the Hit Button tooltip. Shift+left-click works for Shift rules;
Shift+left-drag still moves the button outside combat.

Add more conditions

Select a spell and open + Casting conditions. The add-condition menu has three choices:
AND, OR, and NOT. Choose an operator, then the condition type and fill in
its settings. The first IF offers Always and the condition types directly.
Each condition has a number and its own controls. Scroll inside the editor
for long rules.

- AND adds a requirement that must also match.
- OR gives the spell another way to qualify instead of its IF condition.
  Always already qualifies, so choose a conditional IF before adding OR.
- NOT blocks the spell when the condition matches. NOT Aura is present blocks
  while the aura is up; NOT Aura is missing blocks while it's absent.
Other casting settings stay visible below the conditions. Cast Count and
Modifiers (when enabled in Advanced) are available there too.

Choose an aura, another spell's cooldown, combo points, resources, enemy or
self health, aura stacks, or Target is casting after the operator. Shamans
also have totem conditions; Hunters have hawk conditions. Custom Conditions
appears when enabled in Advanced.

An OR match still has to pass every AND requirement and NOT exclusion, plus
the spell's cooldown and other casting settings. An unreadable check cannot
satisfy AND or NOT; a known matching alternative can still satisfy OR.

For another spell's cooldown, enter its name or ID, then choose On cooldown
or Off cooldown. Keep that spell in Essential or Utility Cooldowns, visible
Always. A global cooldown alone doesn't count. Cast Count still attaches to
an eligible tracked-aura condition, not a cooldown, resource, health, or
stack comparison. Add any required tracker entries, then click Prepare.

For Shadow Bolt only when both Corruption and Curse of Agony are on the target:
1. Track both debuffs in Buff Bars or Buff Icons.
2. Set Shadow Bolt's IF to Aura, then Target debuff / Debuff is present /
   Corruption.
3. Add AND > Aura, then choose Target debuff /
   Debuff is present / Curse of Agony.
4. Click Prepare. Both debuffs must be yours and on your current living
   hostile target. These conditions don't follow focus or mouseover.
   A target-debuff AND or NOT also requires a living hostile target.

For Eviscerate only while Kidney Shot is on cooldown:
1. Track Kidney Shot in Essential or Utility Cooldowns, visible Always.
2. Select the Eviscerate rule and keep any combo-point or other requirements
   you want. IF can be Always if no aura condition is needed.
3. Open + Casting conditions > AND > Spell cooldown.
4. Enter Kidney Shot and select On cooldown.
5. Close tracker settings and click Prepare.

For OR or NOT, choose that operator, then Spell cooldown.
For example, NOT / Spell cooldown / Off cooldown / Kidney Shot blocks the
rule while Kidney Shot is ready.

Set up cooldown rules

For a spell with a cooldown and no aura, such as Arcane Wrath:
1. Track it in Essential Cooldowns or Utility Cooldowns, visible Always.
2. Choose Spell cooldown for IF.
3. Put it above your fallback, close tracker settings, and click Prepare.

If its cooldown tracker also shows the spell's own buff duration, set up
both entries. For example, with Eureka!:
1. Track Eureka! in Essential Cooldowns and in Buff Bars or Buff Icons.
   Keep both groups visible Always; hide inactive entries in the buff group.
2. Set IF to Aura / Aura is missing / Eureka!, choose Self, and check Skip while
   on cooldown. Use this missing-buff IF without OR alternatives.
3. Put it above your fallback, close tracker settings, and click Prepare.

Use Skip while on cooldown when adding a cooldown check to an existing aura
rule. Leave it off for spells that don't need it.

For Stoneclaw Totem, track the spell in Essential or Utility Cooldowns.
Choose Spell cooldown for IF, then click Prepare. You can prepare
with the totem up or down. If it dies early or another earth totem replaces
it, your Hit Button still waits for Stoneclaw's spell cooldown to finish.
Charge-based spells and items don't support this cooldown check.

For Strength of Earth Totem, set Cast on to Self, choose Player buff and
Buff is missing, then enter Strength of Earth as the buff. Leave Skip
while on cooldown off and click Prepare. A buff from another Shaman counts
too. If you walk out of range, the rule can cast the totem again once the
buff wears off. An existing Tracked aura rule for Strength of Earth can
also check the buff on you. You can leave your tracker entries where they are.

Add combo-point requirements

1. Select Combo points in the IF menu, or add AND > Combo points.
2. Choose >=, <=, =, or != and a number from 0 to 5.
3. Put the rule in priority order and click Prepare.

For example, use IF Always with combo points >= 5 for Eviscerate, then IF
Always with combo points != 5 for Sinister Strike. You can put this condition
on any learned spell. It always uses your current target's combo points.
No separate tracker or spell slot is needed unless the rule also uses a
cooldown or Cast Count option that requires one.

Add an aura stack requirement

1. Track the aura once in Tracked Buffs or Tracked Bars. Use its own entry,
   enable Hide when inactive, and keep the tracker group visible Always.
2. Select Aura stacks in the IF menu, or add AND > Aura stacks.
3. Choose Player buff or Target debuff, then enter the aura's name or ID.
   Both sources need a tracker entry for stack conditions.
4. Choose a comparison and enter a whole number from 0 to 99.
5. Close tracker settings and click Prepare outside combat.

To build Sunder Armor to five stacks, set the Sunder Armor rule's IF to
Always. Add Aura stacks > Target debuff > Sunder Armor > Fewer than (<) > 5.
Put your filler below it. A confirmed missing debuff counts as zero, so
the rule can start the stack. At five stacks, the button moves on.

You can enter another stacking aura, such as Lacerate, or add the condition
to a different spell. Stack conditions added with AND must match even when an OR
condition allows the spell. You can choose OR or NOT instead when adding one. Target debuff watches your current living enemy;
Player buff watches you. Cast on still chooses who receives the spell.
If the stack count can't be checked, that rule is skipped until it can.

Add resource requirements

1. Select Resources in the IF menu, or add AND > Resources.
2. Choose your Mana, Rage, or Energy, then Below (<) or At least (>=).
3. Enter a whole percentage from 0 to 100 and click Prepare.

At least includes the selected percentage; Below does not. For example,
Mana >= 20% allows the spell at exactly 20%, while Mana < 20% does not.
Add another resource condition if you want both a lower and an upper limit.
Resource conditions added with AND must match even when an OR allows the
spell. Choose OR or NOT when adding one for different logic.

These checks use your resources, regardless of Cast on, and don't need a
tracker entry. If that resource isn't available in your current form, its
condition doesn't match. You can add them to any spell; Cast Count can't
attach to a resource condition.

Add an enemy-health requirement

1. Select Enemy health in the IF menu, or add AND > Enemy health.
2. Choose Below (<) or At least (>=).
3. Enter a whole percentage from 0 to 100 and click Prepare.

For example, Below 20% allows the rule when your target has less than 20%
health. At least 20% includes exactly 20%. Add another Enemy health
condition if you want both a lower and an upper limit.

This checks your current living enemy target, regardless of Cast on. Health
conditions added with AND must match even when an OR allows the spell.
You don't need a tracker entry. If you have no enemy target or its health
can't be checked, the button skips that rule and checks the next one.
Cast Count can't attach to an Enemy health condition.

Add a self-health requirement

1. Select Self health in the IF menu, or add AND > Self health.
2. Choose Below (<) or At least (>=), enter a percentage, and click Prepare.

For a defensive spell below half health, choose Below and enter 50. This
checks your own health, regardless of Cast on, and works without a target
selected. You don't need a tracker entry. The rule's other conditions still
apply, so choose Cast on > Self if the spell should be cast on you.

You can combine Self health and Enemy health on the same rule. Choose
AND for a requirement, OR for an alternative, or NOT for an exclusion.
Cast Count can't attach to health conditions.

Set a manual cooldown

Use this to enter a spell's cooldown yourself instead of using a cooldown tracker.

1. Select the rule and check Manual cooldown below Ping Delay.
2. Enter the cooldown in seconds. The timer starts when the spell successfully
   casts. Failed attempts don't start it.
3. If you want an aura check too, keep that condition in place. Aura is missing
   still has to match as well as the manual cooldown being ready. The aura
   needs its own Buff Bar or Buff Icon entry. For just the manual timer, use
   Always without an aura condition.
4. Put the spell's selected rank on a visible Blizzard action bar, keep its
   slot and page unchanged, then click Prepare outside combat.

Each rule has its own duration. Ping Delay can be used alongside it. Prepare
and reload preserve a running manual cooldown. Enter the full cooldown and
adjust it yourself if talents or other effects change it.

Skip if immune (bleed)

1. Select a bleed rule, such as Rend or Rip.
2. Check Skip if immune (bleed) under Other casting settings, then click Prepare.
3. Try a Mechanical enemy. Recognized bleeds should be skipped immediately.
4. On other enemy types, the bleed gets an attempt. If an Immune response follows
   immediately, later presses skip all checked bleed rules on that enemy until
   combat ends. An immune Rake also skips Rip if both rules have the box checked.

Leave the box unchecked to keep the rule's usual behavior. Learned immunity
does not carry over to a different enemy. In this beta, the timing check can
also catch another player's Immune result if it arrives just after your cast.

Require being behind target

1. Put Backstab above your fallback, such as Sinister Strike. On the Backstab
   rule, check Require being behind target beside Manual cooldown. Click Prepare.
2. Face an enemy from the front with enough energy for Backstab and press
   your Hit Button. If WoW reports that you must be behind the target,
   press again. That press skips Backstab and tries the next matching rule.
3. Move behind the enemy and press again once the global cooldown clears.
   Backstab has its usual priority again.

Require being behind target responds to a facing or behind-target error.
To skip Backstab for distance too, turn on Skip if out of range for that rule.

Set a Ping Delay

1. Select the rule and check Ping Delay below + Casting conditions.
2. Enter a delay from 1 to 5000 milliseconds. The default is 100 ms.
3. Put that spell's selected rank on a visible Blizzard action bar and keep
   its slot and bar page unchanged. Click Prepare outside combat.

Use this when a spell with a buff or debuff is double casting. Each rule has
its own setting. The rule waits while its spell is casting and for the chosen
delay after it finishes; other matching rules can still be selected. A failed
attempt gets a short retry delay instead of using up a cast-count batch.
The button still needs a fresh press to cast when the delay ends.

Set a cast count

1. Choose a normal cast-time spell. Leave Once per proc off. Instant spells
   and channels don't support Cast Count.
2. Drag that spell's exact selected rank from your spellbook onto a visible
   Blizzard action-bar slot. Keep the actual spell in that slot, rather than
   a macro. Prepare with that bar page visible. If changing forms switches
   the bar page, the counted rule pauses until its page returns. Other rules
   keep working, and you don't need to Prepare again for a form change.
3. Find Cast Count under Other casting settings. In Attach count to, select a
   numbered Tracked aura IF, OR, or AND condition using Aura is present or
   Aura is missing. Track that aura with Hide when inactive enabled.
   Player buff and Target debuff can't take a cast count.
4. Enter a whole number from 1 to 99. Blank or 0 means unlimited. Click Prepare
   outside combat, including any macro update it requests. Fix a macro setup
   error before using the counted rotation.

For three Arcane Blasts when its buff is missing, set Condition 1 to
Aura is missing / Arcane Blast, attach the count to Condition 1, and enter 3.
Add OR Clearcasting / Aura is present as Condition 2 if you want that proc to
allow the spell too. Clearcasting alone won't start a three-cast batch, but
its completed casts count toward a batch that's already running. The batch
can continue when the Arcane Blast buff appears; it resets when that buff
disappears. A count on AND limits all alternatives. Other AND and NOT
conditions still apply throughout a batch.

Only completed casts count. Keep the spell button visible during casts you
want counted. Matching manual casts and casts from another rotation count
too; failed or interrupted casts don't. Press again after
the last cast finishes to move on. If you change the spell slot or rank,
Prepare again.

Choose casting options

The Other casting settings section stays visible below the conditions:

- Advance on toggle: check this for a next-attack spell such as Raptor
  Strike, Heroic Strike, or Maul. Put the abilities you want to use while
  that attack is queued below it. Once the spell is queued, the next press
  skips its rule and tries the next matching ability. After the attack
  fires or is cancelled, its rule can match again. Click Prepare to apply.
- Skip if out of range: check this on a spell and click Prepare. For example,
  put Earth Shock above Lightning Bolt and check it on Earth Shock. If your
  target is too far away for Earth Shock, that press can use Lightning Bolt.
  Get close enough and Earth Shock can take priority again on the next press.
  Each spell checks its own Cast on target. If WoW can't tell whether the
  spell is in range, the rule keeps its usual priority.
- Once per proc: for a proc-consuming channel such as Arcane Missiles with
  Missile Barrage, use Aura is present in IF, enable this option, and keep
  Protect channels checked. Press again during the channel to mark that proc
  as used. The aura must disappear before the next proc can be used.
- Stop current cast: enable this when a present proc in IF or the first OR
  should interrupt another cast. Further ORs don't request an interrupt.
- Stop if buffs change: enable this to interrupt when the last requested
  rule's aura conditions stop matching. If you mix manual casts into the
  rotation, the next press can interrupt one of those too.

Keep Protect channels checked and click Prepare. Both interrupt options
need a fresh direct-key or assigned controller-button press; neither fires
on its own when a buff changes. Channels stay protected.

Start melee autoattacks

Open + Action and choose Auto Attack. Put it above your melee abilities,
leave IF on Always, and click Prepare. With a living enemy selected, the
same press starts your swings and tries the next matching ability. Repeated
presses keep your swings going. If you stop attacking, another press can
start them again.

Set up a wand or hunter rotation

1. Equip your wand or ranged weapon. Open + Action beside + Add spell and
   choose Shoot for a wand or Auto Shot for a hunter.
2. To use it as filler, move it to the bottom and set IF to Always. If you
   already have an Always filler, remove it or give it a condition.
   Keep pressing your Hit Button as usual. Once the weapon starts firing,
   another press can pick a higher spell without toggling shooting off.
3. To send your pet in first, keep Attack on your pet's action bar. Add Pet
   Attack from the same menu and move it above Auto Shot or your other
   attacks. One press sends your pet after your current enemy. The next
   press can start your own attack. Click Prepare when you're done.

Controller setup

1. Connect your controller, open /snh, and click Controller. Enable controller
   input if it's off.
2. Outside combat, click Assign beside a Hit Button, then press and release
   the gamepad button you want. Give each enabled rotation a different
   assignment. Cancel or Escape exits; Clear restores the previous binding.
3. Prepare the rotation as usual. Your keyboard cast key can stay assigned too.
4. Optionally enable Rumble when combat starts or Rumble on crit, then use
   Test rumble. Crit rumble is for your outgoing critical damage. If the game
   doesn't make those events available, the window tells you. Rumble also
   needs a controller that supports vibration.

Buttons already used as modifiers or Escape stay reserved for those jobs.
Hold a modifier with another button to assign a combination. Cursor-click
buttons still act as mouse clicks in cursor mode. If another addon overrides
an input, clear that assignment before using it here.

Use profiles

1. Leave combat and choose a profile from the dropdown near the top of /snh.
   There are five profiles, each with four Hit Buttons. Profile 1 keeps
   your existing setup; the other four start empty.
2. Click Rename to give the selected profile a name, such as Dungeons or
   Grinding. Add or import rotations into its Hit Button tabs and Prepare.
3. Switch profiles outside combat. Your four existing Hit Button macros
   now use the selected profile; you don't need another set of macros.

Each profile keeps its own rules, prepared rotations, cast keys, controller
button assignments, button positions, and casting preferences. Advanced
options, the minimap button, and controller rumble settings are shared.
Restore at login also controls whether a saved rotation is restored when
you switch back to its profile. Unprepared edits stay in its draft.

Set up extra rotations

1. Open Hit Button 2, Hit Button 3, or Hit Button 4. Add rules or import a
   rotation into that tab. The three extra rotations start disabled and empty.
2. Check that tab's Enable box outside combat, then click Prepare.
3. Assign its own cast key or controller button, or use Drag macro to bar
   for that tab's macro. Keep active assignments different between rotations.

Repeat for grinding, dungeon trash, bosses, or whatever you need. Each tab
has separate rules, macros, bindings, and button positions. To turn an extra
rotation off, uncheck its Enable box outside combat; its saved setup stays.

Copy a rule between Hit Buttons

1. Select the spell in Spell priority and click Copy Rule below the list.
2. Choose the destination profile and Hit Button tab. Select the rule you
   want the copy to follow, then click Paste Rule. In an empty rotation it
   becomes Rule 1.
3. Use Up and Down to adjust its priority, then click Prepare outside combat.

The copy includes the spell's conditions, rank, target, cast count, timers,
and Enable Rule setting. You can paste it more than once. The stored copy
is available until you reload or log out.

Import or export a rotation

1. Select a tab, click Export, and copy the complete text to keep or share it.
2. To import, select the destination tab, click Import, paste the complete
   export, and choose Replace <tab name> draft. Export its old draft first
   if you want to keep it.
3. Set up the required trackers and any cast-count spell slots on this
   character. Enable the tab if needed, then click Prepare outside combat.

Imports replace the draft, not your bindings, button positions, or local
preferences. They don't set up your trackers or action bars. Older exports
can still be imported.

Choose preferences and check the setup

- Leave Restore at login checked to restore the last prepared rotation.
  Unprepared draft edits still need Prepare in the editor. A preparation
  notice explains when a saved rotation needs preparing again. Prepare on
  that notice reapplies the saved rotation; Dismiss only hides the notice.
- Enable Hide casting errors in each tab if you want to silence common red
  casting errors and their character voice lines while pressing that button.
- Use Show Hit Button to control the on-screen button. Your bar macro still
  works while it's hidden. Shift-left-drag the button outside combat to move
  it. You can move the minimap launcher the same way.
- Ctrl+left-click an on-screen Hit Button to hide or show its tooltip.
  Use Ctrl+right-click instead if that rotation has a Ctrl modifier rule.
- Open Rotation textual explanation to review the selected draft. Click Copy to
  clipboard, then press Ctrl+C to copy the selected text. Click Prepare in
  the editor after making any rule changes you want to use.

If Prepare fails, check Enable tracker, the required entries, Hide when
inactive, and Always visibility. Close tracker settings and Edit Mode before
retrying. If a macro name conflicts, rename the conflicting custom macro or
free a character macro slot, then use Drag macro to bar again.

Try the rotation on a suitable target. If the wrong spell wins, check rule
order and conditions. Range and spell costs aren't checked automatically;
add a resource condition when you want one. If CHECK SETUP appears in combat,
stop using the button until combat ends, then follow the preparation notice if it
hasn't recovered on its own.

Use Stand and Hit with WeakAuras

1. Enable Stand and Hit: WeakAuras in the AddOns list.
2. Open /snh, choose Advanced, and check WeakAuras integration.
3. Click Setup and copy trigger. Choose a Hit Button, then press Ctrl+C to
   copy the selected code. The window has the setup directions too.
4. Click Open WeakAuras. Create an Icon, then open Trigger. Set Type to Custom,
   Event Type to Status, and Check On to Every Frame. Paste into Custom Trigger.
5. Prepare your rotation in /snh.

The icon shows when that Hit Button has a matching prepared rule in your
active profile. Turning off WeakAuras integration stops these triggers from
matching. Your WeakAuras displays and rotations stay saved.

If either addon is missing or disabled, Advanced tells you what to enable.
The companion's README.txt lists the functions for reading the selected spell,
rule number, and profile. The companion never casts for you.

Use Function Block Diagrams

1. Open /snh > Advanced and check Function Block Diagrams.
2. Choose a rule. Diagram shows its conditions feeding into the spell.
   AND needs every input to match. OR needs at least one. NOT reverses its input.
3. Click a condition block to edit its settings inside the block. You can
   change names, numbers, and conditions without leaving Diagram view.
   Edit spell / target opens those controls inside the spell block.
   Close block folds the controls away after you've made your changes.
4. Use + AND, + OR, or + NOT to add a condition. Choose its type and fill in
   its settings, just as you would in the normal editor.
5. Click Rotation explanation to see how the whole rotation fits together.
   Text and Function Block Diagram switch views. Copy to clipboard still
   gives you the written explanation.
6. To save the entire rotation as one image, click Export image and press
   Ctrl+C. Open diagram-export.html from the StandAndHit addon folder in
   your browser. Paste the copied text, click Preview diagram, then Download
   PNG. The whole diagram is included, even the parts outside the game window.
   This works offline; it does not upload your rotation. Download SVG keeps
   the original size if a very large diagram needs a smaller PNG.
7. Screenshot is still available if you only want the visible section.
   WoW saves those captures in the game's Screenshots folder.

These diagrams show your draft. Click Prepare outside combat to apply it!
They don't show which conditions are currently true in combat. Auto Attack
continues to the next matching rule on the same press; a selected spell or
pet command ends the search. Held priority modifiers can change rule order.

Scroll down for a long diagram. Hold Shift while scrolling to move sideways,
or use the horizontal scrollbar. Turn Function Block Diagrams off in Advanced
to return to the regular editor. Your rules keep their settings.

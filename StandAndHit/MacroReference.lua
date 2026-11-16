local _, SH = ...
local Reference = {Targets = {}, Conditions = {}, Rules = {}}
SH.MacroReference = Reference

local function target(syntax, description, example)
    Reference.Targets[#Reference.Targets + 1] = {syntax = syntax, description = description, example = example}
end

target("Custom Target", "Enter one target beginning with @. The spell goes to that unit while you keep your current target selected.", "@focustarget")
target("@target", "Your selected target.", "@target")
target("@player", "Your own character.", "@player")
target("@focus", "The unit you set as your focus.", "@focus")
target("@focustarget", "Whatever your focus is targeting right now.", "@focustarget")
target("@mouseover", "The unit under your pointer in the world or on a unit frame.", "@mouseover")
target("@pet", "Your current pet.", "@pet")
target("@targettarget, @pettarget and other target chains", "Append target to a unit to follow its target. You can follow more than one step. Each unit in the chain must exist.", "@party1targettarget")
target("@party1 to @party4", "Another member of your party. The number is their slot in the party.", "@party2")
target("@partypet1 to @partypet4", "The pet belonging to that party member.", "@partypet2")
target("@raid1 to @raid40", "A raid member by roster slot. The number can change when the raid changes.", "@raid15")
target("@raidpet1 to @raidpet40", "The pet belonging to that raid member.", "@raidpet15")
target("@Name or @Name-Realm", "A group member by character name. Include the realm when needed. Use your group member's actual name.", "@Thrall")
target("@boss1 to @boss5", "A boss by its encounter slot, when the encounter assigns one.", "@boss1")
target("@arena1 to @arena5", "An opponent by their arena slot, when the match supplies one.", "@arena2")
target("@arenapet1 to @arenapet5", "The pet belonging to that arena opponent.", "@arenapet2")
target("@vehicle", "The vehicle you control, when the game assigns one.", "@vehicle")
target("@softenemy, @softfriend, @softinteract", "The enemy, friendly unit or interact target highlighted by WoW's action targeting. Your targeting settings determine which are available.", "@softenemy")
target("@anyenemy, @anyfriend, @anytarget", "The game's resolved enemy, friendly or current target when using action targeting. WoW gives your selected target priority where applicable.", "@anyenemy")
target("@anyinteract, @anyleftinteract", "The current interaction target or left-click interaction target. A spell still needs a valid unit recipient.", "@anyinteract")
target("@npc, @questnpc", "The NPC you have an interaction or quest conversation open with.", "@questnpc")
target("@none", "Leave the spell without a unit. A spell that needs a target can open the targeting cursor for you to pick one.", "@none")
target("Ground placement and nameplates", "@cursor places a ground spell in a normal /cast macro. The Hit Button's Cast on field takes unit targets. For a unit under your pointer, use @mouseover. WoW also reserves numbered nameplate tokens for UI lookups.", "@mouseover")

-- UIMacroOptions keyword table in Forever 1.60.1.70790. The native parser
-- also handles @unit, target=unit and the no prefix outside this table.
local keywords = {}
local function condition(names, syntax, description, example)
    Reference.Conditions[#Reference.Conditions + 1] = {syntax = syntax, description = description, example = example}
    for name in names:gmatch("%a+") do keywords[name] = true end
end

condition("", "Custom Conditions", "Enter brackets only. Write condition names in lowercase. A comma means both tests must pass. Adjacent brackets give alternatives. Put no before a test to reverse it. Empty brackets [] always match.", "[harm,nodead][@focus,harm,nodead]")
condition("", "@unit or target=unit", "Put the unit inside the brackets to test it. This field only checks whether the rule matches. Choose the spell's recipient separately under Cast on.", "[@focus,harm,nodead]")
condition("exists", "[exists]", "The tested unit exists. Use noexists for an empty target slot.", "[@focus,exists]")
condition("help", "[help]", "You can use a friendly spell on the tested unit.", "[@mouseover,help,nodead]")
condition("harm", "[harm]", "You can attack the tested unit.", "[harm,nodead]")
condition("dead", "[dead] or [nodead]", "The tested unit is dead, or passes the opposite check. Combine nodead with exists, help or harm when a unit is required.", "[@party1,help,dead]")
condition("party raid", "[party] or [raid]", "The tested unit belongs to your party or raid. The party check excludes your own character. To check whether you are grouped, use group.", "[@mouseover,raid]")
condition("combat", "[combat]", "You are in combat.", "[nocombat]")
condition("group", "[group], [group:party], [group:raid]", "You are grouped. Add party or raid to select one kind of group.", "[group:party]")
condition("channeling", "[channeling] or [channeling:Spell Name]", "Your character is channeling. Add the spell name to check a particular channel.", "[nochanneling:Arcane Missiles]")
condition("known", "[known:Spell Name] or [known:spellID]", "You know the spell. Enter its name in your game's language or its numeric spell ID.", "[known:Kick]")
condition("form stance", "[form] or [form:number] (also stance)", "You are in a form or stance. Use its position on your stance bar. Zero means your normal form. Separate allowed positions with a slash.", "[form:1/3]")
condition("stealth", "[stealth]", "Your character is stealthed.", "[nostealth]")
condition("pet", "[pet] or [pet:name/family]", "You have an active pet. Specify its name or family to narrow the test.", "[pet:Wolf]")
condition("equipped worn", "[equipped:type] (also worn)", "You have an item of the specified equipment type or subtype equipped. Use its name in your game's language.", "[equipped:Shields]")
condition("modifier mod", "[mod] or [mod:key] (also modifier)", "A modifier is down. Use shift, ctrl or alt, or a configured modified-click action such as SELFCAST. A slash accepts either key.", "[mod:shift/ctrl]")
condition("button btn", "[button:number] (also btn)", "Checks the button WoW sees for a click. Use 1 for left, 2 for right or 3 for middle. The action-bar macro or a keybind can send a left click.", "[btn:1]")
condition("actionbar bar", "[actionbar:number] (also bar)", "Your main action bar is on that numbered page.", "[bar:2]")
condition("bonusbar", "[bonusbar:number]", "Your current bonus action bar has that index. Zero means you have no bonus bar.", "[bonusbar:1]")
condition("cursor", "[cursor] or [cursor:type]", "You are carrying something on your cursor. Specify a type such as item, spell or macro to check what you picked up.", "[cursor:item]")
condition("mounted", "[mounted]", "You are on a mount.", "[nomounted]")
condition("swimming", "[swimming]", "You are swimming.", "[swimming]")
condition("indoors outdoors", "[indoors] or [outdoors]", "Your location counts as indoors or outdoors.", "[outdoors,nomounted]")
condition("resting", "[resting]", "You are in a rest area such as an inn.", "[noresting]")
condition("flyable flying advflyable", "[flyable], [flying], [advflyable]", "The area permits flying, you are airborne on a flying mount, or the area permits advanced flying. Availability depends on the game's riding rules.", "[flyable,noflying]")
condition("possessbar overridebar extrabar shapeshift", "[possessbar], [overridebar], [extrabar], [shapeshift]", "The corresponding possession, override, extra-action or temporary shapeshift bar is active. Use form to check a particular druid form or warrior stance.", "[possessbar]")
condition("vehicleui unithasvehicleui canexitvehicle", "[vehicleui], [unithasvehicleui], [canexitvehicle]", "You have vehicle controls, the tested unit has vehicle controls, or you can leave your vehicle, respectively.", "[@player,unithasvehicleui]")
condition("spec", "[spec:number]", "Your active specialization or talent group has that index, if the client supplies one.", "[spec:2]")
condition("talent", "[talent:row/column]", "The shared parser recognizes this test for a row-and-column talent grid. For a Forever talent spell, use its name or ID with known, such as [known:Ice Block].", "[talent:1/2]")
condition("pvpcombat", "[pvpcombat]", "Checks availability of PvP talents on game modes that have them. Use combat for ordinary combat.", "[pvpcombat]")
condition("petbattle", "[petbattle]", "Checks whether you are in a companion pet battle on game modes that offer them.", "[petbattle]")
condition("house", "[house] or [house:area]", "Checks player housing on game modes that offer it. The area can be inside, plot, neighborhood or editor.", "[house:inside]")

local function command(syntax, description, example)
    Reference.Rules[#Reference.Rules + 1] = {syntax = syntax, description = description, example = example}
end

command("Custom Rules", "Enable Custom Rules in Advanced, then choose + Action > Custom Rule. Each Hit Button can have one enabled Custom Rule. It keeps its IF, AND, OR, and NOT checks, runs once when they match, then checks the next matching rule on the same press.", "/targetenemy [noexists][dead]")
command("Which buttons work", "Use the visible Hit Button, a key assigned through Set cast key, or Controller. Custom Rules do not work through action-bar macros. You can keep several disabled Custom Rules, but only one can be enabled in each Hit Button.", "/targetenemy [noexists][dead]")
command("Interrupting a cast", "Automatic cast interruption does not apply on a press that runs Custom Rule commands. Add /stopcasting if those commands should interrupt your current cast. If all of the command conditions fail, the normal interrupt settings still apply.", "/stopcasting\n/targetenemy [noexists][dead]")
command("One command per line", "Use up to 16 lines and 1023 bytes. Prepare also checks the final macro size and may ask you to shorten it. Brackets work like they do in a WoW macro. Spell casts still follow WoW's normal cast and global cooldown rules; a command does not guarantee that the spell after it can cast.", "/targetenemy [noexists][dead]\n/startattack [harm,nodead]")
command("Rule order", "Keep your Custom Rule above Auto Attack. If you use Prioritize if on Auto Attack, use the same modifier on the Custom Rule so they keep that order.", "/targetenemy [noexists][dead]")
command("Changing targets", "Put a targeting rule before the spells that need that target. Conditions that depend on the old target's tracked aura wait for another press after a target change, so they do not use the previous enemy's debuffs.", "/targetenemy [noexists][dead]")
command("/target", "Select a unit by name or a unit specified in the brackets.", "/target [@focus,exists]")
command("/targetexact", "Select a unit whose name exactly matches the name you enter.", "/targetexact Training Dummy")
command("/targetenemy", "Without brackets, /targetenemy cycles through enemies on every matching press, like Tab targeting. This example only selects an enemy when you have no target or your target is dead.", "/targetenemy [noexists][dead]")
command("/targetenemyplayer", "Select an enemy player.", "/targetenemyplayer")
command("/targetfriend", "Select a friendly unit.", "/targetfriend")
command("/targetfriendplayer", "Select a friendly player.", "/targetfriendplayer")
command("/targetparty", "Cycle through your party members.", "/targetparty")
command("/targetraid", "Cycle through your raid members.", "/targetraid")
command("/targetlasttarget", "Return to your previous target.", "/targetlasttarget")
command("/targetlastenemy", "Return to your last enemy target.", "/targetlastenemy")
command("/targetlastfriend", "Return to your last friendly target.", "/targetlastfriend")
command("/cleartarget", "Clear your target. The example only clears a dead target.", "/cleartarget [dead]")
command("/assist", "Select the target of another unit, such as your focus.", "/assist [@focus,exists]")
command("/focus", "Set your focus to a unit. The example uses the unit under your pointer.", "/focus [@mouseover,exists]")
command("/clearfocus", "Clear your focus.", "/clearfocus")
command("/startattack", "Start melee auto attack. Repeating this command does not toggle it off.", "/startattack [harm,nodead]")
command("/stopattack", "Stop melee auto attack.", "/stopattack")
command("/petattack", "Send your pet to attack a target.", "/petattack [@target,harm,nodead]")
command("/petfollow", "Call your pet back to follow you.", "/petfollow")
command("/petstay", "Tell your pet to stay where it is.", "/petstay")
command("/petpassive", "Set your pet to Passive.", "/petpassive")
command("/petdefensive", "Set your pet to Defensive, if that stance is available.", "/petdefensive")
command("/petassist", "Set your pet to Assist, if that stance is available.", "/petassist")
command("/cast", "Try to cast a spell. Put its target in brackets when needed. This command still obeys the spell's requirements and global cooldown.", "/cast [@player] Battle Shout")
command("/use", "Try to use an item by name or equipment slot. Item cooldowns still apply.", "/use 13")
command("/cancelaura", "Remove one of your cancelable buffs by name.", "/cancelaura Ice Block")
command("/cancelform", "Leave your current shapeshift form.", "/cancelform")
command("/stopcasting", "Stop the spell you are currently casting.", "/stopcasting")
command("/cancelqueuedspell", "Clear a queued spell.", "/cancelqueuedspell")
command("Supported commands", "The commands listed here are the ones Custom Rules accepts. Lua commands such as /run and /script, /click, /castsequence, and addon chat commands are not supported.", "/targetenemy [noexists][dead]")

function Reference.IsCondition(keyword)
    if type(keyword) ~= "string" then return false end
    return keywords[keyword:lower():gsub("^no", "")] == true
end

function Reference:Text(section)
    local text = {}
    local function append(entries)
        for _, entry in ipairs(entries) do
            text[#text + 1] = entry.syntax .. "\n" .. entry.description .. "\n" .. entry.example
        end
    end
    if not section or section == "targets" then append(self.Targets) end
    if not section or section == "conditions" then append(self.Conditions) end
    if not section or section == "rules" then append(self.Rules) end
    return table.concat(text, "\n\n")
end

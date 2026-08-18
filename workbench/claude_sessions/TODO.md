NICEMICE ROADMAP TASKS 2026-08-17

Tasks sorted into a handful of categorical buckets:

1. 
Is this a high-, medium-, low-, or deferred-priority task?
Strictly speaking this affects mechanical, actual gameplay. 
If something is broken, crashes the game, or creates a bad user experience, it should be prioritized.

2.
Is this an  improvement to (or replacement for) a system that already works?
If we're reinventing wheels (which we do a lot, the results are usually great) then we need to make sure it's clear why that wheel is being reinvented.

3.
Is this content?
Starbound's modding community hungers for more content and it's what keeps the mod community alive.
There is always user desire for additional content but I don't want that clogging up our other baskets.

4.
Does this meet a reasonable user's expectations?
A reasonable user would expect a species mod to have all of the different aspects of the species fleshed out and playable.
If things are missing, that's probably important.

5.
General categories for task.

6. 
Blockers?

7. 
How much of a pain in the ass is this task? Scale of 1 to 10

----

⭐ Tier 8 ship graphics + Interior redesign

Buckets:
1. High prio
2. Several new systems
3. Yes
4. Exceeds
5. Player ship, Flavor
6. Many
7. 8

Task:
The tier 8 ship has no exterior hull graphics, mostly because those come at the end of several sweeping other changes:

Unlike other species' ships, which block the exterior areas outside the ship with solid, transparent blocks, the Nicemice T8 ship allows the player to explore "space" outside the hull in their mech.
A primitive implementation of automatic generation of zero-gravity "terrain" exists to facilitate this, as player shipworlds are not zeroG by default.
This system needs significant expansion to meet all of the desired goals and expectations:
- Right now it's kind of sluggish and could be a lot more responsive.
- It is desired that players can generate new hull-exterior "terrain" each time they reposition their ship.
- It is desired that there are interesting things to find in generated asteroid areas outside the ship.
- It is desired that the T8 ship has mounted cannons which automatically engage spawned npc monsters - this is purely for flavor because the aesthetic of idle turret fire in a sci-fi game is cool.
- It is possible for a player to strand themselves outside their ship if their mech runs out of energy. If they're not parked somewhere that allows them to beam down and beam up again, they have to "swim" very slowly through zero G to get back to their ship which is excruciating.
- The upper decks of the T8 ship need a redesign anyway because the diagonal slopes didn't translate well to a buildable, navigable space for players. Looks great on paper, terrible in practice for construction.

----

⭐ More colony objects

Buckets:
1. N/A
2. No
3. Yes
4. Yes
5. Player construction, Flavor
6. None
7. 4

Task:
Nicemice do not currently have a complete set of furniture objects for colony construction.
A clear differentiation is developing between civilian Nicemice and M.A.U.S. personnel in terms of aesthetic and character- M.A.U.S. is currently dominating here but I'd like to make sure that players have access to civilian equivalents because not all players are on-board with the command-and-conquer-esque peace-through-power faction aesthetic.

----

⭐ Docking field avoidance

Buckets:
1. Low prio
2. System built but could use refining
3. No
4. Exceeds
5. QoL
6. None
7. 3

Task:
Docking field objects are used to visually separate gravity and zero-gravity areas.
In vanilla gameplay these are only ever encountered as vertical boundaries that NPCs will not have issues with.
In modded gameplay these boundaries are encountered at a variety of different angles and situations where NPCs will attempt to pathfind across, on-top-of, or occasionally through these barriers.

The current band-aid for this issue is manual placement of zoning objects that tell my NPCs to move away in a particular direction, left or right, when near the field.
This is not scalable and what they should be doing instead is checking to see whether or not the left or right side of the docking field has gravity, then biasing their movement toward the side that has gravity. 
Players have simply been putting up with this behavior in modded Starbound. Making my NPCs smart enough to do better is a flex, not a hard requirement.

----

⭐ Terrestrial towns/villages, additional space encounters, other encounter zones

1. Medium Prio
2. Situational
3. Yes
4. Yes
5. Content, Tools, QoL, Flavor
6. Situational
7. 8

Task:
Nicemice currently have one meaningful encounter zone - the M.A.U.S. Cargo Ship.
I want Nicemice settlements to exist, but some of them need system support to be implemented.
Example: A Nicemice moon base would require stagehand implementations to prevent meteor and comet impacts from becoming a problem - which would require some deep work to modernize the game's weather system. Weather is currently implemented as "each player spawns rain outside their field of vision which drifts into view". Great for gentle forest showers, bad for crowded colonies where the only configured weather is instant death meteorite bombardment.

----

⭐ Hat masking

Buckets:
1. Medium prio, not having this negatively affects user experience but not gameplay
2. Required tech already partially implemented
3. No, but makes the content we add more valuable per item
4. Exceeds
5. Cosmetics, QoL
6. None
7. 10

Task:
Nicemice take advantage of Starbound's rendering order to composite hairstyles and ears as two separate character customization options.
This creates situations where one hat will cleanly fit one set of ears but look really strange on another, and the amount of ear variety Nicemice have available isn't really a use case that vanilla Starbound's character editor planned for.
Hats can apply arbitrary alpha masks for a cleaner fit, and we already have the scripted infrastructure necessary to determine a character's hair and ear composition- but to convert all of our hats for the many permutations of ears and hairstyles will require some automation, which means we'll need a scripted solution for building masks and configuring permutations of hats which then routes through our existing swap-item tech to put the correct hat on the correct ears with the correct mask automagically.
Ideally the user won't even know this is happening. Currently they wear a hat and it's a crapshoot as to whether or not it fits. Thankfully this quality bar is very low because other mods have similar issues, but nobody else has ever actually taken the time to solve it correctly. Nicemice WILL be the first.
Needs to apply to NPCs too.

----

⭐ Respawn animations

Buckets:
1. Low prio
2. No
3. Once
4. Yes
5. Species feature-completeness, Flavor
6. None
7. 7

Task:
Nicemice currently use the Apex respawn animation which is visually inconsistent with their existence.
Slightly jarring but everyone skips the respawn animation anyway. Still needs to get done.

----

⭐ Tiered weapons

Buckets:
1. Medium prio
2. Situational
3. Yes
4. Yes
5. Species feature-completeness, Flavor
6. None
7. 6

Task:
Each vanilla species has a handful of tiered weapons and armor items that are unique to that species.
Nicemice only currently have plasma pistols, a whip for M.A.U.S. officers, and tech staff weapons. These weapons are extremely cool, but they don't facilitate player progression in a flavorful way - only endgame, where the player has probably already moved on to more-powerful weaponry made by modders who aren't interested in balancing their 9999-damage machineguns.
Crafting your own weapons as a progression step is somewhat rare - modded Starbound showers the player in options that are typically better than anything they can spend resources on for DIY armaments, but for the sake of feature completeness I eventually want an armory loadout here.

----

⭐ Better ship pets

Buckets:
1. Low prio
2. Yes
3. Yes
4. Exceeds
5. Species feature-completeness, Mechanics, Loot, Tools, QoL, Flavor
6. None
7. 8

Task:
Vanilla ship pets are very useless and very in-the-way.
I want Nicemice ship pets to be useful and have smarter behavior so they don't block access to things like storage objects or the captain's chair.
More info for this is already in the handoff doc.

----

⭐ Nicemice faction hostility differentiation

Buckets:
1. Low prio
2. Yes
3. Situational
4. Exceeds
5. Mechanics, Flavor
6. Requires more content to exist first
7. 8?

Task:
I want hostile Nicemice NPCs to be able to also engage hostile bandits and other non-Nicemice hostile npcs.
I think this just involves picking a damageTeam number and applying it consistently across our npctypes- I'm not sure though.
This is territory that many players think they want, but I'm not sure if anyone has ever really truly explored it.
"Factions" are absent in any meaningful capacity in Starbound - there are just friendly NPCs and hostile ones, but the systems exist to make them fight each other- it's simply that most modders are hobbyists without technical development experience and setting up + testing faction interactions is not a reasonable ask for them.
Eventually this task will expand to faction reputation mechanics. This one looks innocent but it's ambitious.

----

⭐ Convert Avali into fuel

Buckets:
1. Lowest prio
2. No
3. Yes
4. Exceeds?
5. Flavor, Loot
6. Requires me to care
7. 4

Task:
Avali are a species that are well-established in the Starbound modding scene.
Their creator left behind a legacy of rich lore that players have expanded upon, and the Avali are easily one of the most prominent modded species even after their mod was abandoned long ago.
Unfortunately, most of their content is unforgivably ugly (partially because old, partially because low quality) to look at and that detracts from the gameplay experience.
Many users are still willing to put up with Avali's ugliness though, and at some point when we were discussing this in Discord someone mentioned that Avali have ammonia-based blood.
What followed was a hilarious conversation about converting them into fuel to make them useful if they're going to exist in their current state. Nicemice are the vehicle for converting ugly legacy content into useful consumable FTL drive fuel.

----

⭐ Vanilla outfit conversions

Buckets:
1. Medium prio
2. Yes
3. Yes
4. Meets but also exceeds. This one is weird
5. Species feature-completeness
6. Hat masking
7. 10

Task:
Nicemice have a body template that does not conform to the standard humanoid outfit sizing.
Their small size makes them incompatible with an overwhelming majority of vanilla (and modded) content, and it's unreasonable for me to create parallel copies of every vanilla asset by myself.
Script infrastructure exists to automatically swap an incompatible vanilla item with a compatible Nicemice item, but that still requires the assets to get made for a valid target.
We need a tool that maps the pixels from vanilla's spritesheets to the Nicemice spritesheets, so I can simply run a script to generate an asset and then do a manual cleanup on the art if necessary.

---- 

⭐ More cosmetic costumes

Buckets:
1. Medium prio
2. No
3. The users hunger
4. Yes
5. Cosmetics, Loot
6. Hat masking tech, vanilla outfit conversion tech
7. 8

Task:
Nicemice have a very small number of available cosmetic outfit items, partially due to their heads having weird silhouettes from their big ears and partially because making clothes for them is pain.
Users request more customization options often and this is one of the biggest feedback points where the mod is failing to deliver what users are asking for.
The latest update added 3 new cosmetic outfits, but users want many many many.

----

⭐ Visual differences in tiered Nicemice armor

Buckets:
1. Low prio
2. No
3. Yes
4. Yes
5. Cosmetics
6. Hat masking
7. 7

Task:
Nicemice currently have one asset set used for all of their armors.
Graphics need to be made for each tier. Currently blocked by hat masking.

----

⭐ Notify player when they reach T8 ship that their previously unbreakable components are now breakable and movable

Buckets:
1. Low prio
2. No
3. No
4. Exceeds
5. QoL
6. T8 ship
7. 2

Task:
Normally, certain key objects in your ship, like the fuel hatch, captain's chair, etc are unbreakable and cannot be moved.
When the player upgrades to the final tier (T8, for now(?)) for their ship, Nicemice players have those unbreakable flags removed, but the player is never notified of this.

----

⭐ More tail cosmetic options

Buckets:
1. Medium prio
2. No
3. Yes
4. Yes
5. Cosmetics, QoL
6. Vanilla cosmetic converter (probably)
7. 8

Task:
Nicemice characters leverage the "back" cosmetic slot to wear swappable tails.
This competes with things like environmental protection backpacks, jetpacks, parachutes, lantern mounts, capes, and other similar back items.
I want vanilla back items to be supported with the default tall, but a better long-term solution would be an item-combining interface for Nicemice that allows them to choose a tail cosmetic to merge into a back cosmetic, allowing them to wear a bow on their tail and a backpack at the same time. Tails that are merged into other back cosmetics should be able to be extracted again.
The one-size-fits-most nature of the back slot being used for tails, wings, capes, and more means that there will never be a solution that correctly handles everything. This will be an exercise in choosing battles and making compromises, but right now no effort has been made at all which results in users just giving up their backpack slot to have a tail, which sucks.
At the very least we need more tail variations so that giving up the slot has some options to choose from.

----

⭐ Tail merchant

Buckets:
1. Low prio
2. No (?)
3. Yes
4. Yes
5. Cosmetics
6. Tail cosmetic options
7. 1

Task:
NPC that sells more tail cosmetics to the player.
No point in making this until we have more cosmetics to give.
Probably bundled with any tech developed to merge tails and backpacks.

----

⭐ Afterdark items + merchant

Buckets:
1. Low prio
2. No
3. Yes
4. Exceeds
5. Cosmetics, Furniture
6. Deploy area
7. 5

Task:
Some of the content in the Nicemice mod features risque or revealing items.
These include pinups of Nicemice engineers, etc.
This content is currently unobtainable through normal gameplay, but Steam's content filtering settings have already been applied to the mod to indicate that some of its content may not be suitable for all audiences.
A crafting interface to convert 'Afterdark Tokens' and SFW variations of items into their NSFW counterparts needs to be built out at some point.
All this really requires is copypasting a known-good NPC crafting interface config and adjusting the graphics and chosen recipes/items.
Having an appropriate place to put this merchant is the main blocker here. Facilitating this feature will likely require a mini-project just to build a proper habitat for it.

---- 

⭐ Lore codex entries

Buckets:
1. Low prio
2. No (Maybe)
3. Yes
4. Yes (Exceeds)
5. Lore, UI, Furniture (?)
6. UI decisions
7. 7?

Task:
It's trivial to add more codex entries to Starbound.
What's not trivial is finding unlocked codex etnries to actually read them in modded Starbound.
The overwhelming majority of mods categorize their codex entries into the "other" species category, causing a ton of congestion in a single codex category as hundreds of species mods compete for slots in the same list.
The root cause of this congestion can be traced to lack of meaningful configuration options and missing API hooks in the codex interface itself - for Nicemice I think it would be a better longterm solution to build a parallel UI from scratch specifically for Nicemice lore display.
This might turn into its own miniature project to make something a little bit more expansible for other species mods to leverage - but for v1 it can be a cool flex for Nicemice and if people like it we can grow into a one-size-fits-more-than-mice build later.

----

⭐ Pilot helmet issues

Buckets:
1. Low prio
2. Probably
3. No
4. No (Exceeds though)
5. Cosmetics, Vehicles
6. None
7. 5?

Task:
Certain vehicles automatically apply a mech helmet or pilot helmet as a temporary override for players piloting the vehicle.
This is great if your species conforms to the helmet template, but Nicemice don't do that.
I don't know if this is a simple scripted fix applied to the player or if it's an unfixable problem with content I don't have control over.
The current "fix" for this is a parallel mech vehicle config asset that Nicemice use exclusively which has the mech helmet override removed - but this "fix" makes their mechs incompatible with many other mods so a better solution here is desirable.

----

⭐ Cheesethrower / Cheesenwerfer

Buckets:
1. Lowest prio
2. No
3. Yes
4. Exceeds
5. Joke weapon
6. None
7. 6

Task:
I keep threatening to make this gun as a joke

----

⭐ Other species

Buckets:
1. Someday prio
2. No (?)
3. Yes
4. Exceeds
5. Species
6. None, but I should "finish" Nicemice feature-completeness first
7. 10

Task:
The Nicemice body template is a spectacular fit for other species and character references:
- Goblins
- Gremlins (specifically the Spiral Knights ones)
- Kobolds
- Mimigas (competition for this is coming later this year probably)
- Moogles (there's competition for this already though)
- Narehate / Hollows
- Palicoes
- Telemonster
- Ori
- Midna
- Carbuncles

When Nicemice are feature-complete, it would be cool to give players options that fall into these categories or politely nod to the characters that inspired some of these designs.
These other species variations come with some implications like habitats/settlements and equipment. No parallel species implementation is going to be small, even if they all reuse the ship.

Making a Midna-themed outpost visitor is a smaller-scoped take on this which can be reasonably accomplished without a full race expansion, though, and will likely come up later as a content task on its own.
I'm not a huge fan of copy-pasting stuff from other games or franchises directly into Starbound, but I do think there's fun in being able to put on a hat that superficially resembles something familiar. There's a balance to find here and I don't want Nicemice to become "the mod where you can be that one thing from some tv show".

----

⭐ Starter mission

Buckets:
1. Low prio
2. Yes (?)
3. Yes
4. Exceeds
5. Species, Mission, Furniture, Story, Quests, Dungeons, Enemies, Lore
6. None, but huge
7. 10

Task:
You can configure a custom starter mission for your species.
Nicemice aren't part of Starbound's Protectorate faction, so it makes sense they'd have their own starter mission.
This is, however, a ton of work - and it's also a ton of work that historically nobody has bothered to do.
I've only ever seen one species with a unique intro mission and it was badly made and cringe.
...but Nicemice could do it correctly, and that would be a big flex.

----

⭐ Holiday content

Buckets:
1. Low prio
2. No (?)
3. Yes
4. Exceeds
5. Furniture, Cosmetics, Event
6. Hat masking, vanilla asset conversion, tail asset options
7. 8

Task:
Starbound supports time-limited holiday events.
Nobody really adds anything to these in the modding scene.
I would like some Christmas content eventually.

----

⭐ Add support for spectwing race from latest Arcana update to dialogs

Buckets:
1. Low prio
2. No
3. Yes
4. Exceeds
5. Dialog, Lore
6. Actually play the Spectwing race and get a feel for their lore first
7. 2

Task:
Recently released species in newest Arcana mod update lacks Nicemice dialogs

----

⭐ Add support for other species' dialog that we haven't gotten to yet

Buckets:
1. Low prio
2. No
3. Yes
4. Exceeds
5. Dialog, Lore
6. Same as above but these come from more obscure mods or stuff we don't use actively on our server
7. 3, except for Frackin which is 8 because it has to be sandboxed or it will brick my game saves when I uninstall it

Task:
Dialog parity for Frackin Universe species
Dialog parity for Inkbound species
Dialog parity for Kitsune species
Dialog parity for various other modded species (Armol, etc)
Dialog parity for Cave Story mods - Surface Robot species, etc

Just making sure Nicemice have something snooty to say when they meet a new alien.

----

⭐ Automatic conversion patches

Buckets:
1. Medium prio
2. No
3. Sort of
4. Yes
5. Species feature-completeness
6. Assets need to exist, Hat masking, Vanilla cosmetic conversions, Tail cosmetic conversions
7. 8

Task:
Currently scripts exist to automatically swap a vanilla asset (like a Hylotl chestguard) to a Nicemice-sized equivalent item.
For every vanilla item that Nicemice supports like this, a matching .patch file needs to be created for the vanilla asset - preferably a swap that routes to a dispatcher Nicemice intermediary on the way in and an external species intermediary on the way out to reapply things like masking, directives, etc.

----

⭐ 3 tile high doors have been suggested

Buckets:
1. Lowest prio
2. No
3. Yes
4. Exceeds
5. Furniture
6. None
7. 4

Task:
Graphics for small doors for Nicemice characters.
Main reason I haven't done this is to try to maintain navigation compatibility in Nicemice builds for non-Nicemice players.

----

⭐ Verify that M.A.U.S. terminals (S.A.I.L. equivalent) actually keeps custom installed chips between ship tier upgrades

Buckets:
1. Low prio
2. Maybe
3. No
4. Exceeds
5. QoL
6. None
7. 3

Untested, but want to verify nothing gets lost or clobbered when upgrading since the implementation is custom

----

⭐ Design and implement a recipe solution

Buckets:
1. Medium prio
2. Maybe
3. Yes
4. Exceeds
5. QoL, Species feature-completeness
6. Design pass
7. 8?

Task:
As Nicemice continues to grow as a mod, it will eventually become cumbersome for non-Nicemice players to acquire all of the recipes for building the various items and furnitures that come with the mod.
Recipes do not currently exist to craft most items - including the building materials, which are important.
The way other mods do this usually distills down to picking up a single item that teaches you all of the recipes for a given species, but that is a clunky solution and I want something more elegant and flavorful.
I want to tie this into progression if possible.

----

⭐ Compatibility with "Get rid of that underwear" mod has been requested

Buckets:
1. Lowest prio
2. No
3. Questionable
4. Exceeds
5. Mod compatibility
6. None
7. 3

Task:
Users have requested a variation on the male and female base body assets with visible nipples.
This equates to literally 2 pixels being placed on the base bodies where highlights already exist.
I'd ask the mod creator for GROTU to do it but they're lazy and just put pink dots instead of using a color that would match Nicemice body accents, so this is just a small someday-project to do to make sure it's done correctly the first time.
This is one spot where it does require a separate compatibility mod, non-negotiable, which is really annoying.

----

⭐ Compatibility for "Sexbound" mod has been requested

Buckets:
1. Lowest prio
2. Probably
3. Yes
4. Exceeds
5. Mod compatibility
6. Unknown
7. 10 probably

Task:
Sexbound is one of the most popular Starbound mods in existence.
Many users have requested compatibility.
I don't use Sexbound so I don't know what that compatibility scope even entails, but it's being put on the task list so it doesn't get lost until I can either decide to do it or decide to delegate it to someone else.

----

⭐ Tenant parity with Nicemice NPC diversity

Buckets:
1. Medium prio
2. Yes
3. Yes
4. Yes
5. Player construction
6. Behavior trees need to be adjusted
7. 7

Task:
Currently only unarmed civilian Nicemice tenants can be added to player-created settlements via colony deeds.
Themed colony deeds for M.A.U.S. personnel need to be built and their appropriate behavior trees need to be created.
Tenant guard NPCs don't use the stock vanilla guard behaviors and I'm not sure what the delta is between those things but the Nicemice "guard" tenants (anybody who isn't unarmed) should have feature parity while supporting their unique combat behaviors - probably requires another dispatcher behavior.

----

⭐ Update NPC spawner object scripts

Buckets:
1. Medium prio
2. Yes, sort of
3. Not really
4. Exceeds
5. QoL
6. None
7. 4

Task:
The current behavior for NPC spawner objects (not colony deeds) is that you have to go offscreen and then it spawns the guy.
Other mods have updated their NPC spawner objects to mimic colony deeds and have the freshly-spawned NPC "beam down" (spawn in and play the beam landing animations) when the player interacts with the placed NPC spawner.
This more modern NPC spawner approach is a flat upgrade in usability and I want to update the Nicemice spawners accordingly.
Eventually I'd like this to pop a UI where you can customize the NPC before it spawns but that's a huge project.

----

⭐ Finish the vanilla object description patches

Buckets:
1. Medium prio
2. No
3. Yes
4. Yes
5. Species feature-completeness
6. None
7. 9 only because there's thousands of them

Task:
About half of the vanilla objects and tiles have Nicemice racial descriptions.
I already have a tool for this, I just need to do it.

----

⭐ Nicemice generated weapons

Buckets:
1. Medium prio
2. No
3. Yes
4. Exceeds
5. Species feature-completeness
6. Mostly just a place to put them
7. 3

Task:
Create assets for:
- Wands
- Assault Rifles
- Etc

Deploy the generated weapons to appropriate loot tables once locations are available.
With no surface dungeons and a single space encounter, there's enough weapon saturation in the one themed spot for now- as the mod grows, so too will this arsenal.

----

⭐ If the user has the "Custom S.A.I.L. Chips" mod installed, they should be able to find the M.A.U.S chip on the Cargo Ship

Buckets:
1. Lowest prio
2. Unsure
3. No
4. Exceeds
5. Mod compatibility
6. Testing
7. 5?

Task:
Starbound's mod loading order is weird and clunky.
More importantly, I hate hate hate having to make my users install a secondary compatibility mod so some other guy's mod will work correctly with my mod.
I can check for whether or not a mod is installed at runtime by querying item parameters from any item their mod introduces to the game environment - the missing piece here is scripting a chest to adjust its contents (or its loot table?) when it's instantiated so that appropriate loot can be injected if necessary.

----

⭐ Tag all light-emitting Nicemice objects with the "light" colony tag

Buckets:
1. Low prio
2. No
3. No
4. Yes
5. Species feature-completeness, QoL, Player construction
6. None
7. 3

Task:
Sweep all Nicemice assets and verify they're consistent about this for colony construction

----

⭐ Variations for M.A.U.S. Cargo ship decks

Buckets:
1. Lowest prio
2. Yes
3. Yes
4. Exceeds
5. Replay value
6. None
7. 8

Task:
The M.A.U.S. Cargo Ship has a single layout, but could theoretically support many layouts on a per-room basis.
In the interest of shipping anything at all, the single layout version is live, but in the future I'd like to revisit this and add more variations so that the ship has some personality each time you visit.

----

⭐ Redesign the Nicemice mech boosters

Buckets:
1. Low prio, existing asset is fine
2. No
3. Yes
4. Exceeds
5. OCD
6. None
7. 6

Task:
Graphics for the Hazvia boosters just don't aesthetically match the rest of the mech

----

⭐ Nicemice clothing tooltips

Buckets:
1. Medium prio
2. Sort of
3. Yes
4. Yes
5. UI readability
6. None
7. 5

Task:
A custom tooltip interface window needs to be created for Nicemice armor and cosmetics.
Currently they use the default tooltip which superimposes the items on a human mannequin, resulting in visual noise.
When the tooltip is added, Nicemice wearables need to be retrofitted to use it.

----

⭐ Nicemice progression system

Buckets:
1. Low/Medium prio
2. Yes
3. Yes
4. Vastly exceeds
5. Flavor, Lore, Mechanics
6. Probably
7. 10

Task:
Nicemice aren't part of the Protectorate, so the Protectorate storyline makes no sense.
This content gives Nicemice characters (and outsiders, if they're ambitious) an alternative content branch to explore, similar to the Bounty Hunting system, where performing tasks for M.A.U.S. Fleet Command will allow you to rise up the ranks and eventually "become a Fleet Captain", which, whatever, you already have your own ship, but it's something to do and Starbound players are starved for good content.
This will break down progression into tasks like colonizing specific types of planets, hunting down particular enemies, and other similar milestone tasks - parallel again with the Bounty Hunter system, except done correctly and with rewards a little more intrinsic than hats.
Big project. Slow burn on this one - it's not crunchable.

----

⭐ Nicemice "Outpost" - Fleet Command

Buckets:
1. Capstone
2. Yes
3. Yes
4. Vastly exceeds
5. Everything basically
6. Several
7. yes

Task:
The Outpost in Starbound functions as a quest hub and regroup area where NPC vendors fill supporting roles for the player.
It's built to be a central hub for the Protectorate story content and although many mods add more content to the Outpost, some mods in the past have taken this a step further and created their own parallel hub areas.
In particular, the Elithian Races mod adds two of these elaborate hub builds, and they are among the most beloved pieces of content ever added in the modding scene.
The goal is to learn by example here and create a themed Nicemice hub zone that grants access to Nicemice content for all players, reinforce the lore, gives you stuff to do, and gives you a place to hang out.

This is an enormous undertaking and relies on nearly everything else in this list being complete.

----

⭐ More Nicemice mech weapons

Buckets:
1. Low prio
2. Maybe
3. Yes
4. Exceeds
5. Mech
6. None
7. 8

Task:
Players will always want more guns for their giant robots.
Currently Nicemice mechs have 1 unique gun. I want this to be more like 5.

----

⭐ Mech OCD adjustments

Buckets:
1. Low prio
2. Maybe
3. No
4. Yes
5. Mech
6. None
7. 6

Task:
Figure out why some of the effects recolor blue even though I set the directives to pink-red.
Figure out how to make the Nicemice mech HP bar render in appropriate colors.
Maybe add a custom horn honking noise item for it so it squeaks

----

⭐ NPC integrations

Buckets:
1. Low prio
2. No (?)
3. Yes
4. Exceeds
5. Mod compatibility, Vanilla+
6. None
7. 4

Task:
Add Nicemice npc types for mod integration like Project Irisil's Hylotl Post Office, as well as integrating Nicemice NPCs into vanilla content like Peacekeeper stations, Bounty targets, Space stations, etc.
Not hard just needs to get done.

----

⭐ Nicemice ship upgrade tiers come with crew members

Buckets:
1. Low prio
2. No, systems already built
3. Yes
4. Vastly exceeds
5. Species feature-completeness, Flavor
6. None
7. 2

Task:
When the player upgrades their ship to higher tiers, it would be cool if the upgrade came with a pre-spawned M.A.U.S. personnel npc in the new section of the ship.
These aren't the same as "reruitable crew members", just flavor NPCs that show up in a place they normally wouldn't
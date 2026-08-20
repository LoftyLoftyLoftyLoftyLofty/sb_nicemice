# PETPORTS — handoff

`lofty_petports`. A deployable spawner ("petport") that houses a utility unit,
plus the unit behaviour that makes one worth having. Split out of the Nicemice
mod on 2025-08-19, before any public release, so that object and monster
identity names were still free to change.

Nicemice remains the intended content layer: unit types, chassis variants and
the encounter/quest loop that unit items drop from. This mod is the machinery.

## Current state

**Working, verified in game.** The petport places, opens, and spawns a unit when
a unit item is socketed. The unit persists, survives world reload, and its state
round-trips through the item — resource levels continue where they left off and
known players survive. Unsocketing despawns it. Socket-cycling does not leak
units. Placement validation is live: a unit that gets sleepy in a doorway walks
clear of it and sleeps beside it, centred in a single-tile gap.

**Not yet run.** The perch path (needs an object tagged `petports_perch`), vents
(need art and an `.object`), and everything in the design direction below.

**Known bug, low priority.** Nothing. The item-swap identity gap was closed
using `seed` as the identity token.

**Placeholder art throughout.** The drone wears firepteropod's sprites, chosen
for its fullbright layer rather than its locomotion — the drone is a GROUND
unit. The petport wears the Nicemice Rocket Cart's.

## Layout

    items/categories.config.patch                      -- the petports_unit category
    items/lofty_petports/
      petports_unit_test.item, .png
    monsters/lofty_petports/
      petports_contract.lua      -- functions the port and vent call ON a unit
      petports_placement.lua     -- "is this a polite place to stop?"
      petportsSleepAction.lua    -- replaces vanilla sleepAction
      drone/
        petports_drone.monstertype, .animation
        body/  drone_placeholder.monsterpart, art, default.frames
    objects/lofty_petports/
      petport/  petports_petport.object, .lua, .animation, art, default.frames
      petvent/  petports_petvent.lua, .animation   (.object and art still missing)

Naming convention is `petports_` + the thing's own name, hence
`petports_petport`. The vent's pet-facing API keeps plain verb names
(`petports_ventTravel`, `petports_ventTeleport`) since those are functions, not
assets.

## Open decoupling work

Descriptions still read "M.A.U.S. utility unit" — Nicemice lore in a standalone
mod. All of it is confined to `description` / `shortdescription` fields.

`colonyTags : ["petports"]` is an invented tag and may simply never match
anything tenant-side. Vanilla tags may serve better depending on what tenants
should ask for.

`petports_placement.lua` reads the avoidance marker tags `avoidMe`,
`avoidMe-goLeft` and `avoidMe-goRight`, which are Nicemice-authored objects. This
degrades safely — in a world without them nothing matches — but this mod should
eventually carry its own markers or drop the concept.

---

## Engine traps

Hard-won, mostly by getting them wrong first. Several are vanilla bugs or
undocumented engine behaviour rather than anything specific to this mod.

**`initialStorage` and `initialStatus` do NOT seed a monster's `storage`.**
`petspawner.lua` appears to nest them under `scriptConfig`; it does not —
`Pet:_scriptConfig(parameters)` returns `parameters` unchanged, so the two names
are the same table and those fields land at the TOP LEVEL of what reaches
`world.spawnMonster`. But flattening them there still did not work: a unit
spawned with a fully populated `initialStorage` came up with config-default
`petResources` and an empty `knownPlayers`.

**What does work is spawn parameters as config parameters.** `groundPet.lua`
reads

    storage.petResources = storage.petResources or config.getParameter("petResources")
    storage.knownPlayers = storage.knownPlayers or config.getParameter("knownPlayers", {})
    storage.foodLikings  = storage.foodLikings  or config.getParameter("foodLikings", {})

and a fresh monster's storage is empty, so passing saved values as SPAWN
PARAMETERS under those exact names lands them through the fallback branch. Same
path `level`, `persistent` and `anchorName` already arrive by. Omit a key and the
monstertype's default applies, so a brand new unit is unaffected.

`storage.anchorPosition` has no config fallback and cannot be restored this way —
the petport's direct `setAnchor` call is what establishes it.

**A missing SCRIPT FILE fails loudly; a missing FUNCTION fails silently.** A bad
path in a monstertype's `scripts` list throws `AssetException` and refuses to
spawn the monster at all, logging once per attempt — with `RESPAWN_GRACE` that is
once a second forever, which at least gets noticed. A bare
`world.callScriptedEntity` naming a function the target does not define returns
nil and logs nothing.

**The first `setPet` after a spawn is an echo, not news.** `spawnPet` calls
`setAnchor` immediately and `groundPet.lua` answers by pushing back state it
initialized microseconds earlier. Accepting it means a restore that silently
failed also DESTROYS the values it failed to restore — observed as config
defaults written into the item 23ms after spawn. Ignore that first callback;
`seed` is stable and safe to take from it.

**`groundPet.lua` re-calls `setAnchor` every second** via `updateAnchor`, so
`setPet` runs once per second for the life of the unit. An anchor that marks
itself dirty on every callback performs a container swap per second, forever,
replicated to every client. Compare durable fields (`knownPlayers`,
`foodLikings`, `seed`) and write on change; let resource drift ride a slow timer.

**Action state names are matched by a letters-only pattern, and petBehavior
hardcodes vanilla's.** `groundPet.lua` builds its action list with
`stateMachine.scanScripts(config.getParameter("scripts"), "(%a+Action)%.lua")`
and looks the captured name up in `_ENV`, so the global must match the capture.
`%a` is letters only: `nicemice_sleepAction.lua` captures `sleepAction` and
shadows vanilla's global name. Camel case — `petportsSleepAction.lua` — keeps
the capture whole.

But `petBehavior.actionStates` hardcodes `["sleep"] = "sleepAction"`, and
`petBehavior.run` compares `stateDesc()` against that string to decide whether
the action is already running. A replacement state must therefore expose
`description()` returning vanilla's name — `stateDesc()` prefers `description()`
when present. Without it the behaviour layer thinks sleep is not running and
re-picks it.

**Vanilla `sleepAction` reads a config path that does not exist.**
`config.getParameter("actions.sleep.minSleepy", 65)` — but the monstertype
defines `actionParams.sleep.minSleepy`. There is no top-level `actions` key, so
the lookup always misses and the hardcoded 65 is used. Any tuning of that value
has never taken effect in vanilla or in any mod that inherited the file.

**A resting footprint is centred on the position, so candidates must be snapped
to tile centres.** A unit's `mcontroller.boundBox()` is about a tile wide and
centred, so a candidate at integer x spans `[x-0.5, x+0.5]` and straddles TWO
tile columns — the search then only succeeds where two adjacent tiles are clear.
Candidate x values are inherited from wherever the unit happened to be standing,
so the alignment is arbitrary. Observed as a unit refusing to step out of a
doorway unless it had two tiles of room. `math.floor(x) + 0.5` fixes it, and
offset 0 is worth searching for the same reason: the exact position can fail
where the centre of that same tile passes.

**Declining to rest is not the same as moving away.** Placement validation gates
RESTING only — the idle and wander states are still vanilla and will park a unit
anywhere. A unit that declines to sleep just stands where it was, which looks
identical to sleeping there unless you watch for the emitter.

**`writeBackToItem` cannot run on unsocket.** It needs the item still in the
slot, and by the time `update` notices the removal it is already in the player's
inventory. The final save is a permanent no-op; whatever the item holds is
whatever the last IN-SLOT write put there. So a periodic flush is not a safety
net, it is the persistence granularity — the interval is exactly how much drift
an unsocket discards. World unload is fine: `uninit` runs while the item is
still socketed.

**Frame indexing is 1-based for anything with an `.animation` file, 0-based for
objects without one.** A state declaring `"frames" : 8` and pointing at
`<partImage>:fly.<frame>` resolves `fly.1` through `fly.8`. Vanilla's own frames
files confirm it — `firepteropod`'s grid names `fly.1`..`fly.8`, and
`petbunny.animation` declares `"idle" : { "frames" : 1 }`, which can only ever
resolve one name. Getting this backwards produces an entity with a working
collision box, working scripts and no sprite, which reads as a missing asset
rather than an off-by-one. Furniture objects WITHOUT an `.animation` file are
0-indexed, which is where the confusion comes from.

**An entity that dies on its first update never draws.** Debug bounding boxes
come from the collision system, not the animator, so "hitbox visible, sprite
missing" has two completely different causes — a broken asset chain, or an
entity that was killed before the animator resolved a part. To tell them apart,
strip the monstertype's `scripts` list down to `/scripts/util.lua` and spawn it
inert. If it renders, the assets are fine and the problem is lifecycle. (Do not
strip to an empty list; keep one script in there.)

---

## Design direction and architecture

Everything below was §7 of the Nicemice handoff.

The live project. Vanilla ship pets are widely disliked: they shadow the player,
swallow clicks meant for objects behind them, and park in front of the things you
need. The design goal is the opposite — small robotic units that find something
useful to do, inspired by Axiom Verge's ambient drones and Factorio's logistics
bots rather than by a squishy pet that wants attention.

### Design direction — petports, fuel, and specialization

Design commitments that shape the behavior rewrite. None of this is built yet;
all of it constrains what gets built.

#### Terminology: petport, not pet station

"Pet station" collides with an existing vanilla crafting station by name, and it
describes the wrong thing anyway — the object is a spawner and deployment point,
not an appliance the player crafts at. Internally and in future asset names it
is a **petport** (after Factorio's roboport, which occupies the same conceptual
slot: a structure that houses, fuels and dispatches automation units).

Rename touchpoints, all of which must move together: the object's `objectName`,
the monstertype's `anchorName` (groundPet.lua kills the unit outright if these
do not match exactly), the `.object` / `.lua` / `.animation` filenames, and the
object's `scripts` reference. `objectName` is save-game identity, so this is
free now and expensive after anything is placed in a world.

#### Fuel, not food

Each unit type accepts a **category** of fuel and, within it, has a per-unit
**preference** that refills more efficiently.

A robotic drone might accept batteries, small batteries, copper wire, RAM sticks
and silicon boards, with a particular unit preferring copper wire. A
squirrel-themed unit accepts seeds broadly and favours one. The bowl is a fuel
dispenser with a compatibility readout, not a food dish.

**This breaks vanilla's food handling and cannot be configured around.**
`groundPet.lua`'s `itemFoodLiking` returns false immediately for anything whose
`root.itemType` is not `"consumable"`. Copper wire and batteries are crafting
materials, so they are rejected before preference is ever consulted. The scoring
function must be replaced with one that checks category membership first and
preference second. Contained change — `eatAction` is its only consumer — but it
is a rewrite, not a parameter.

What survives from vanilla: `foodLikings` as a persisted per-unit map is the
right shape for preference, and the lazy-roll-then-cache pattern gives each unit
stable tastes for its lifetime without authoring them by hand.

#### The bowl, and why exclusivity is load-bearing

Status lights on the bowl read red / yellow / green for incompatible /
compatible / preferred.

That display is only unambiguous when the bowl knows which unit it speaks for,
because preference is per-unit: a communal bowl showing green for one unit shows
yellow for another standing beside it. So bowl-to-unit exclusivity is not
cosmetic — it is what makes the readout mean anything. Unbound, the light can
only honestly report "something here can use this."

Both setups have uses, so the intended shape is: bowls are communal by default,
and **wiring a bowl to a petport binds it to that petport's unit**, at which
point the lights become specific. This follows the wiring convention set out
below.

#### Fed means productive

Fuel gates the *acquisition* of work, not the *execution* of it. A unit that
runs dry finishes what it is doing and then stops taking on new tasks; it never
abandons a job halfway or freezes mid-action.

This implies a task queue layered above vanilla's action-state machine, which is
a scoring-and-pick model with no notion of committed work. The queue is a new
component, not a configuration of the existing one.

The framing matters as much as the mechanic. A unit that stops the instant
hunger crosses a threshold is a maintenance chore; a unit that works a solid
shift after a good meal is something the player plans around. Same rule,
opposite feel.

#### Discovery: the petport panel

Preferences are rolled per unit, so they cannot be looked up externally or
carried between units. The petport's interact UI is the answer — the same panel
that holds the unit slot displays known preferences, current fuel level, task
capabilities and status.

This is the strongest argument for a bespoke interface config. The borrowed
`/interface/chests/pettether.config` is a placeholder and cannot carry any of
it.

#### Locomotion classes

Three intended, in order:

- **Ground** — what is being built now. `groundPet.lua` and its action states
  assume it throughout: `approachPoint` resolves through `findGroundPosition`,
  `move()` gates on `validStandingPosition`, `sleepAction` teleports onto a
  ground target.
- **Flyer** — deferred until ground units work. Requires `gravityEnabled: false`
  plus a replaced movement layer; flipping the config alone leaves ground-based
  pathing running against a unit that never touches ground.
- **Aquatic** — flyers constrained to fluid volumes. Same movement layer as
  flyers with a containment check.

Note the current placeholder art is pteropod's, chosen for its fullbright layer
rather than its locomotion. The drone is a ground unit despite flying sprites.

`petports_placement.lua` is ground-specific in its position-finding
(`validStandingPosition`, `findGroundPosition` offsets). Its occupancy logic and
allow-list survive a flying unit unchanged; the candidate-position search does
not, and will need a hover-point and perch concept.

#### Vents are infrastructure, not a workaround

Vents stay regardless of locomotion. The original justification — a ground unit
cannot climb ladders — undersells them. They are how units enter and leave
player-built spaces without disturbing door and hatch systems, on ships and in
colony ductwork alike, and they work as cosmetic infrastructure too (a vent lets
bees in and out of a player-built hive). Fast travel is a side benefit, not the
reason they exist.

#### Proliferation is intended

Nothing limits how many petports a player deploys, by design. Full automation
coverage requires several unit types, which is the point: it drives exploration
and questing to acquire unit items that make a permanent base more convenient.

This makes pets a payoff loop for the settlement and encounter work rather than
a self-contained ship feature, and it is the reason the "Low" priority the
roadmap assigns ship pets understates them.

#### Specialization falls out of the asset layer

A task set is a monstertype, a monstertype owns its own `categories` string, and
that string binds its own pool of `.monsterpart` chassis variants. So a unit's
job and its appearance are coupled for free — a sorter cannot accidentally wear
a medic's body, because they draw from different pools. Worth preserving
deliberately: visual legibility is what lets a player glance at a deck and know
which unit is which.

The petport itself stays generic. The unit item carries the type; the port just
holds one.

#### The split, and why it happened when it did

This began inside Nicemice and was separated out on 2025-08-19, the same day the
spawn pipeline first worked end to end. The timing was the whole point:
`objectName`, a monstertype's `type`, `itemName` and a monsterpart `category`
are all save-game identity, and once players have them in worlds they cannot be
renamed without breaking those worlds. Nothing had shipped, so the rename was
free. A week later it would not have been.

The intended relationship is mechanism free, content exclusive. This mod ships
the machinery and an empty ecosystem; Nicemice fills it with unit types, chassis
variants and the encounter/quest loop that unit items drop from. That keeps
reach and exclusivity from fighting each other.

The coupling was shallow enough to make this cheap — nothing in the pet system
ever reached into Nicemice NPC, dialog, ship or species code. The dependency ran
one way. What remains is listed under "Open decoupling work" at the top.

#### Engine constraint: work only happens where a player is

Starbound ticks loaded chunks only, and a world unloads entirely when its last
player leaves. No pet task runs on an unattended world. This is the hard limit
that shapes every automation design here, and it is not something the mod can
work around.

What the mod *can* do: keep arbitrary regions of an already-loaded world in
memory. Pets register their work areas into `world.properties`, and a
player-attached script keeps those regions resident. That extends automation
range across a planet the player is standing on — a farm at the far end of a
colony keeps working while the player is at the other end.

**State the scope precisely, because it is easy to misremember as more.** The
precondition is at least one active player *on that world*. A colony nobody is
visiting does nothing, chunk-loading or not. The feature buys range within a
world, not persistence across worlds.

**Within that bound, this is new ground.** Vanilla's own long-range automation
does not attempt it — rail trams die at load distance and will not run a route
while the player is elsewhere on the planet, which is why nobody builds
transport networks that matter. Making pet tasks work reliably offscreen, at
arbitrary range on a loaded world, is the differentiating claim of this system
rather than an implementation detail of it. It is also the part most likely to
be copied, and the part most likely to draw complaints if it performs badly.

Cost is accepted: resident chunks are expensive, and the tradeoff is deliberate.
The performance risk worth watching is not the loading itself but the
`world.properties` traffic described below — it is replicated state, and in
multiplayer frequent large writes cost bandwidth, not just cycles.

#### Work claims

Units broadcast what they are doing into `world.properties` so that two units
never chase the same job — "collecting 50 lightbulbs from the crate at
(410, 389), these are spoken for."

Design requirements this implies, none of them optional:

- **Claims must expire.** A unit that dies, unloads, or is recalled mid-task
  leaves its claim behind. Without a TTL or a heartbeat, one interrupted job
  poisons that item or container permanently. Interruption is the normal case
  here, not the exception.
- **Sweep stale claims on world load**, since a world unload orphans every
  claim held at that moment.
- **Key claims by unit uniqueId**, so a returning unit can recognise and resume
  or release its own.
- **Keep the structure small.** This is replicated state written frequently.

#### Wiring conventions

The engine imposes exactly one rule: an output node connects to an input node.
Everything past that is script-defined. A wire carries no inherent meaning, so
each object type decides for itself what a connection signifies, and different
pet objects legitimately mean different things by it.

**Validate what is on the other end.** A player can wire a vent to a lightbulb.
Nothing stops them and nothing warns them. Every wired object in this system
must confirm its partner is a compatible type before acting on the connection —
`petports_petvent.lua` already does this by comparing `world.entityName` against
its own `objectName`, and crates and bowls need the same filter. Teleporting a
unit into a lamp is the failure mode this prevents.

**Use extra nodes for richer topology rather than overloading one.** Vanilla
rail trams are the reference implementation: a centre input node takes call
buttons, while separate upper and lower nodes link stops to each other, and the
tram paths across that second network to whichever stop was signalled. Two
distinct meanings, kept apart by living on different nodes rather than by
inference. Pet objects should reach for the same approach when one connection
type stops being enough — crates currently need only one in and one out, but a
filter or call node would go on its own node, not into the existing one.

**Direction is available when it matters.** `getOutputNodeIds` and
`getInputNodeIds` report each side separately, so an object can tell upstream
from downstream. Vents ignore this deliberately: one wire links a pair both
ways, and the player never has to think about which end is which. Sorter crates
depend on it: upstream is where a unit collects, downstream is where it
delivers. Neither is more correct than the other, but which one an object uses
should be stated in its header.

#### Task 1 — sorting

A petport is wired to a crate; that crate is where the unit collects. Crates
wire onward to further crates, forming a directed routing graph. Status lights
on crates follow the same red / yellow / green convention as the fuel bowl.

**Role is positional, not a property.** A crate is a pickup point because a
petport wires into it, and a destination because another crate wires into it.
The object has no mode setting — "output box" is a misnomer, since a crate can
be both. This is why crates chain.

**Routing rule:** an item goes to a downstream crate that already contains that
item and has room. Following Minecraft's copper golem in spirit, diverging in
failure handling — a unit with nowhere to put something chirps to alert the
player rather than standing inert until someone notices.

**Open decision — the empty-graph bootstrap.** "Deliver where the item already
lives" cannot match anything in a freshly built setup, so the first run alerts
on everything and moves nothing. The diagram's bacon routes correctly only
because the destination was pre-seeded. Three ways out, none chosen: a stated
seeding convention, a filter slot on the crate that declares intent without
holding stock, or a last-resort fallback to any downstream crate with space.
Whichever is picked, it needs to be discoverable in-game — a system that works
only if you already know the trick reads as broken.

**Cycles.** A directed graph the player wires by hand will contain loops. Needs
either cycle detection during traversal or a hard hop limit.

#### Task 2 — harvesting

Harvest crops across a designated area, and produce from farm animals
(Fluffalo, Mooshi). Output triages through an input crate, which is where this
task composes with sorting.

Motivated by a real pain point: large farms are tedious to work by hand.

Least-specified of the three. The mechanical question is what a unit actually
invokes — player harvesting goes through interaction paths that may not be
callable from a monster script, and animal produce works differently again from
crops. Worth an investigation spike before design.

#### Task 3 — collecting item drops

Gather item drops across a designated area, triaging through an input crate.

Motivated by monster farming, which vanilla supports poorly. The only
vanilla-friendly design — a mother poptop pen funnelling offspring into a
one-tile lava channel — requires the player to stand still to benefit, which is
not engaging. Other mods solve this with vacuum objects; a collector unit does
it in a way that fits the rest of this system.

Mechanically underspecified. Note that item drops despawn, which puts a real
deadline on claims for this task specifically.

#### Vent preference

Units should use vents to reach sealed areas, and prefer them when vent travel
shortens the route.

Two distinct cases, and only one is about preference:

- **No route exists** — the destination is sealed off. Vents are not an
  optimisation here, they are the only way in. This needs a fallback path when
  pathfinding fails, not a cost comparison.
- **A route exists but is long** — compare and prefer. True path costs are
  expensive to compute; comparing straight-line distance direct against
  (distance to vent + distance from partner vent to target) with a threshold is
  almost certainly good enough and is cheap.

#### Combat is out of scope

Healing and other combat-adjacent tasks are dropped. Nicemice NPC medics already
cover player healing for anyone playing the species, and keeping units clear of
combat preserves the line between utility pets and capture-pod monsters.

This is already reflected in the drone's config — `ghostly` damage team, zero
touch damage — and it simplifies the behavior rewrite considerably, since a unit
that never fights never needs targeting.

### Why not the vanilla pipeline

`/scripts/companions/petspawner.lua` exists to serve CAPTURE PODS, and nearly all
of its complexity is pod-shaped: pods holding several pets at once (a hemogoblin
splits when it dies), collar merging, associate/disassociate handlers, and a JSON
round-trip that keeps a pod item in sync so a pet can be carried between worlds.

None of that applies to a dedicated item. One item is one pet, there are no
collars, and the definition lives in the item's own parameters. Worth keeping
from that file is only the spine: assembling spawn parameters with
`initialStatus` / `initialStorage` (how a pet keeps learned state across a
respawn), a status heartbeat, and collision-aware spawn placement.

### The item IS the pet

`petports_unit_test.item` carries a `petData` block — `monsterType`, display
fields, and the `status` / `storage` the station writes back as the pet lives. A
found item ships with just the monster type; the rest accumulates.

This also enforces the ship-pet/wild-monster boundary **structurally**. Wild
monsters and ship pets use entirely different script stacks and are visually
magnitudes apart, and that separation must hold. A wild monster has no
`petports_unit` item, so it can never be socketed — no runtime type check
needed.

### The petport implements vanilla's anchor contract

`groundPet.lua`'s `findAnchor` calls `status.setResource("health", 0)` — it KILLS
the pet — if it cannot find an anchor object within 5 tiles of its last anchor
position. So `petports_petport.lua` implements the same `hasPet` / `setPet`
contract `techstation.lua` does, and the monstertype's `anchorName` points at it.

**`anchorName` must match the station's `objectName` exactly.** Rename the object
and pets die on the next load.

This is deliberate scaffolding: it lets vanilla's pet scripts run unmodified
while the behavior work happens separately.

### Vents: wires as links, not signals

Every other wired object uses wires as a SIGNAL (`setOutputNodeLevel` /
`getInputNodeLevel`). `petports_petvent.lua` uses them as a LINK — what matters
is which object is on the far end, via `getOutputNodeIds` / `getInputNodeIds`.

That buys a nice property: **one wire links a pair both ways.** Wire A's output
to B's input and A finds B through its output while B finds A through its input.
The player never thinks about direction and pulling the wire disconnects both
ends.

Teleporting between vents sidesteps pathfinding entirely, which is the point — a
small ground pet has no good way to climb ladders or cross decks.

UNVERIFIED: the return shape of `getOutputNodeIds`/`getInputNodeIds`.
`collectIds` tolerates either a plain list or a map of id -> node index. If
linking silently fails, log what they actually return before changing anything.

Consequence worth knowing: those nodes cannot also carry an on/off level. A vent
a switch can close would need a second input node declared for it.

### Placement validation — occupancy, not interactivity

`petports_placement.lua` answers "is this a polite place to stop?" Every
resting action needs it.

The obvious approach — "do not stand in front of interactable objects" — DOES NOT
WORK. Interactivity is a RUNTIME property: `/objects/wired/light/light.lua` calls
`object.setInteractive(config.getParameter("interactive", true))`, so a light
switch is interactive by default with nothing in its config saying so. Any
predicate built from config parameters has holes, and the holes look arbitrary to
a player.

So it checks OCCUPANCY: does the pet's footprint overlap the tiles an object
occupies (`world.objectSpaces`)? Slightly over-broad — a pet also declines to nap
in front of a decorative panel — which is a much better failure mode than napping
in front of the one thing the player needed.

**Allow-list, not deny-list.** Objects are off-limits unless tagged
`petports_perch`. A deny-list would mean enumerating every object to avoid,
which is unbounded and grows with every mod installed. An unknown object is
treated as furniture to stay off, which fails safe. Tag the pet house and any
deliberate perch.

`sleepAction` is the acute case and it is not drift: it TELEPORTS the pet onto
its target with `mcontroller.setPosition`. Use `petports_settleAt` instead —
validation that only gates approach will miss it.

UNVERIFIED: whether `world.objectSpaces` returns object-relative coordinates
(assumed, matching how `pathutil.lua`'s `objectBounds` uses it), and whether
trees surface through an `includedTypes = {"object"}` query. The tree case is
"wait for a complaint" — the failure is a pet declining to nap under a tree.

### Design decisions already made

- **Follow is the LOWEST priority action, and should be a floor rather than a
  score.** Any constant will occasionally beat a real task. Cleaner: follow only
  enters when nothing else claimed the tick.
- **Interact is a pat, not a dismissal.** "Get out of my way" as the primary
  interaction would be a bandaid on the wrong pillar. Combine affection with a
  politeness window: emote, then keep a wider distance from that player and do
  not pick a resting spot near them for N seconds.
- **Tasks come from objects, not appetites.** `petBehavior.scoreAction` is an
  appetite model — every score is a resource level (hunger, curiosity, playful,
  sleepy). Factorio bots are the inverse: work exists independently and bots
  claim it. The seam already exists: `querySurroundings` sweeps objects and hands
  each to `reactToObject`, which currently only checks for `pethouse`. Objects
  can advertise work there via a scripted call, queued through the existing
  `queueAction`, with appetite scores as the fallback layer beneath.
- **Ambient traversal is nearly free characterisation.** A pet with no task that
  picks a vent and travels LOOKS purposeful. That buys most of the Axiom Verge
  feeling before a single real task exists.

### Vanilla tuning notes

`metaBoundBox` is the cursor hit-test box. `petbunny`'s is
`[-1.625, -2.375, 1.75, 2.0]` — 3.4 x 4.4 tiles around a creature whose
`collisionPoly` is about 1.5 x 1.5. That is why vanilla ship pets swallow clicks
meant for whatever is behind them. Ours is sized to the body.

Vanilla's follow loop: `curiosity` regenerates at 1/sec against a `minScore` of
35, while `followAction` drains it at only 5/sec and its `boredTimer` does not
start until the pet has ARRIVED. Net effect is a permanent 3-tile tail. The
monstertype raises the bar and shortens the bore time, but that is TUNING, not a
fix — the rewrite is the fix.

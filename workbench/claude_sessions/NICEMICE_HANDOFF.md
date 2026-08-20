# M.A.U.S. — Design Notes & Handoff

Working notes for the nicemice Starbound mod. Started as NPC combat — wands,
staves and whips, plus weapon-aware behavior dispatch across guard, crew and
quartermaster paths — and has since grown to cover avoidance zones, ship pets,
a config-driven spawner, and wired objects. The Traps section applies mod-wide,
not just to NPCs.

Written to be picked up cold. Read "Traps" before changing anything.

**Where things stand:** everything in sections 1-6 is built, tested and shipped,
as is all of sections 10-12 (personalities, status text and dialog), which went
out in the Aug 17 release alongside the M.A.U.S. Cargo Ship encounter, eight NPC
types, three weapons and the cosmetic/furniture set. Section 13 (quest template
dialog) shipped after that release and is shallow-tested in-game. Section 7 (ship
pets) is the live work and none of it has been run. Section 3 (Traps) is the most
valuable part of this document — every entry cost a debugging cycle to find and
none of it is inferable from reading the code. Sections 10-13 exist so the
vanilla dialog configs and quest templates never need re-uploading to work on
mouse text again.

---

## 1. The architecture

### Behavior dispatch

Every mouse enters through a **scripted entry behavior** that resolves which
combat tree it should run based on what weapon it's holding, then swaps itself
out for that tree.

```
nicemice_scriptedGuardBehavior       (guards / personnel)
nicemice_scriptedCrewMemberBehavior  (recruited crew)
nicemice_quartermaster               (merchant + guard hybrid)
        |
        +-- nicemice_initHooks              (message handlers, weapon preservation)
        +-- nicemice_resolveGuardBehavior   (picks by item tag)
        +-- nicemice_scripted*Behavior      (swaps to the resolved tree)
```

`nicemice_resolveGuardBehavior` (in `/scripts/actions/nicemice_resolveGuardBehavior.lua`)
takes four behavior names as parameters and checks `self.primary or
self.sheathedPrimary` against item tags, **in this order**:

| tag matched | parameter |
|---|---|
| `whip` | `whipBehavior` |
| `wand` or `staff` | `wandstaffBehavior` |
| `ranged` | `rangedBehavior` |
| (none) | `baseBehavior` |

Order matters: a whip also carries `melee`, and `ranged` is the broadest tag, so
specific weapon families are matched first.

### The three combat chains

Each weapon family has a parallel chain mirroring vanilla's structure. Nothing
overwrites a vanilla asset; every file is a mod copy.

```
                    guard root                    crew root
                    ----------                    ---------
wand/staff   nicemice_guard-wandstaff      nicemice_crewmember-wandstaff
               -> nicemice_friendlynpccombat-wandstaff   -> nicemice_crewmember-combat-wandstaff
                    -> nicemice_npccombat-wandstaff  <-------------+
                         -> nicemice_wandstaff-approach

whip         nicemice_guard-whip           nicemice_crewmember-whip
               -> nicemice_friendlynpccombat-whip        -> nicemice_crewmember-combat-whip
                    -> nicemice_npccombat-whip  <------------------+
                         -> nicemice_melee-whip
                              -> nicemice_whip-approach
                              -> nicemice_meleecombat-aim-whip
                         -> nicemice_rangedcombat  (if a gun is drawn)

ranged       nicemice_guard-ranged         nicemice_crewmember-ranged
               -> nicemice_friendlynpccombat-ranged      -> nicemice_crewmember-combat-ranged
                    -> nicemice_npccombat-ranged  <----------------+
                         -> nicemice_rangedcombat
                         -> meleecombat (vanilla, unchanged)
```

Quartermasters use `nicemice_quartermaster_guard-{whip,wandstaff,ranged}`, which
are copies of `nicemice_quartermaster_guard` with `friendlynpccombat` swapped for
the matching mod wrapper. The wandstaff variant also carries
`nicemice_healsupport`, matching `nicemice_guard-wandstaff`.

The guard and crew paths **share** the `nicemice_npccombat-*` layer. Anything
broken in both is in that layer or below; anything broken in only one is above it.

### Lua actions

`/scripts/actions/nicemice_wandstaff.lua` — the bulk of it.
- `nicemice_resolveAbilityIntent` — reads `npcIntent` off the ability config
- `nicemice_chargedFire` — holds fire through a charge, then releases
- `nicemice_clampAimPosition` — walks aim inward so a cast lands in range
- `nicemice_clearWandstaffTargeting` — clears derived keys, releases fire, recentres aim
- `nicemice_nearSidePosition` — keeps standoff on the NPC's side of the target
- `nicemice_hasWandStaffPrimary` / `...Sheathed`
- internal: `slotDescriptor`, `handItem`, `handAbility`, `itemConfigFor`,
  `descriptorCacheKey`, `descriptorIsResolvable`

`/scripts/actions/nicemice_resolveGuardBehavior.lua` — behavior dispatch (above).

`/npcs/nicemice_npcHooks.lua` — `nicemice_initHooks`, `nicemice_npc_move`,
`nicemice_returnFromAvoid`, message handlers, the weapon-preservation update
wrapper, and the avoidance-zone scan.

`/scripts/nicemice_util.lua` — `nicemice_setNPCBehavior` (the behavior swap),
skin directive helpers.

`/scripts/actions/nicemice_whipaim.lua` — `nicemice_entityCenterPosition`,
`nicemice_signOf`, `nicemice_entityDistance`.

---

## 2. Decisions that are not obvious

### `npc.getItemSlot`, never `self.primary`

**This was the root cause of the mod's worst bug.** `bmain.lua` assigns
`self.primary` exactly twice: in `init()` and in `setNpcItemSlot()`. It is an
init-time snapshot that never refreshes. On a freshly spawned NPC it holds a
descriptor whose `parameters` is empty `{}`.

An empty `parameters` is catastrophic for ability resolution: `root.itemConfig`
re-runs the weapon's build script, which generates a **fresh time-based seed**
(see `buildweapon.lua` lines 22–30) and picks a random ability out of
`builderConfig`. The resulting config describes a weapon the NPC is not holding,
and `abilityConfigCache` then freezes that phantom for the NPC's entire life.

Symptom: roughly 1 in 6 staff mice would resolve `healing` regardless of their
actual staff, pass the heal gate, and discharge whatever their real alt ability
was — pushzone, slowzone — at wounded allies. It looked like a behavior-tree
targeting bug and absolutely was not.

`slotDescriptor()` reads from `npc.getItemSlot(slot)` (which does return the real
descriptor, and accepts `"sheathedprimary"` / `"sheathedalt"` — lowercase), and
falls back to the `self.*` fields only when the call returns nil.

### `descriptorIsResolvable` — fail closed, but only for held weapons

A descriptor with no `seed` and no `<slot>AbilityType` cannot be resolved
truthfully, so `nicemice_resolveAbilityIntent` returns false rather than acting
on a phantom.

**But the guard is skipped when `args.sheathed` is true.** Stowed descriptors
appear to stay bare for as long as they're stowed — the engine has no reason to
build an item nobody is holding. Applying the guard there doesn't fail safe, it
fails permanently: `nicemice_healsupport` resolves the *sheathed* intent to decide
whether a holstered healing staff is worth drawing, so a medic could never answer
that question and never healed. A wrong answer there is self-correcting (one
wasted draw), while a wrong answer on a drawn weapon is friendly fire.

### `dynamic` for reactive abort

The harmful and buff branches of `nicemice_npccombat-wandstaff` wrap their
charge/release/steer phases in a `dynamic` whose first child is
`inverter(isValidTarget(target))`. When the target goes invalid, the dynamic tears
down whichever phase is mid-flight. This is vanilla's own idiom — `ranged.behavior`
uses the same shape — and it's what fixed the "stand around doing nothing after
combat" stall.

Composite nodes (`sequence`, `selector`, `parallel`, `dynamic`) are **engine-native**,
not defined in `behavior.lua`. Their exact semantics can't be read from the
scripts; mirror vanilla rather than reasoning from first principles.

### `nicemice_nearSidePosition`

`/stagehands/coordinator/npccombat.lua` sorts candidate positions by
`world.magnitude(a, npcPosition)` — straight-line distance, measured *through* the
target. When near-side candidates are eliminated (no standable ground, no LOS, or
a squadmate claimed the slot), the nearest surviving candidate is on the far side
and the NPC walks through a large monster to reach it.

The node passes the coordinator's suggestion straight through when it's already on
the NPC's side, only intervening on a crossing, and falls back to the original
suggestion when the near side has nothing valid (so a mouse pinned against a wall
still repositions rather than freezing).

**Fixed NPC-side, not coordinator-side, on purpose.** `bgroup.lua`'s `joinGroup`
picks a coordinator by `compareGoals` alone — goalType and goal, never groupId or
behavior. A mod coordinator would therefore only run when our NPC happened to
spawn it first; in a mixed fight it's a coin flip.

### Ranges come from the coordinator, keyed by item name

`meleeWeaponRanges` / `rangedWeaponRanges` in **`coordinator.stagehand`** (not
`npc.config`) are looked up by `world.entityHandItem(npcId, "primary")`.

Staff and pistol mice join `taskId: "ranged"` so they get
`setRangedAttackerPositions`, which builds a circle around the target, uses true
euclidean distance, and leaves already-well-positioned NPCs alone.
`setMeleeAttackerPositions` only generates positions on a *horizontal line at the
target's height* and defaults to 1.5–3 tiles — which is why staff mice originally
walked into stab range.

Note the melee coordinator publishes only `maxRange`, no `minRange`. That's why
`nicemice_whip-approach` takes `whipMinRange` as a parameter (default 3).

### Avoidance zones

Mice wander, which is a problem in front of the captain's chair — a mouse parked
there blocks the interface that opens travel. NPCs prioritise interaction over
furniture, so they will not step aside on their own, and this applies to
following crew too: an unclickable chair is worse than a follower briefly
stepping away.

**Direction is declared by the object, never inferred.** Ship authors tag objects
they want mice to keep clear of:

| tag | effect |
|---|---|
| `avoidMe-goLeft` | always walk left from here |
| `avoidMe-goRight` | always walk right from here |
| `avoidMe` | walk away from the object (either direction is fine) |

The original implementation keyed off the vanilla `captainschair` tag and worked
out the direction by comparing positions. That is wrong on any ship whose layout
we do not know — on the M.A.U.S. cargo ship it sent crew rightwards onto the
windshield, where they got stuck. Declared tags mean a modded ship only needs a
`.patch` adding a tag to its own objects, and we assume nothing about layout.

Directional tags beat plain `avoidMe` on the same object; the nearest tagged
object wins overall.

Implementation lives in `nicemice_npcHooks.lua` because every entry behavior
already loads it. **Opt-in**: pass `returnBehavior` to `nicemice_initHooks` and
avoidance switches on, returning the mouse to that behavior afterwards. Omit it
and nothing happens, so no npc class gains this by accident.

The run-away behaviors (`nicemice_crew_avoidCaptainsChair_npcRun{Left,Right}` —
name predates the generalisation) end in `nicemice_returnFromAvoid`, which reads
the stored return behavior. They used to name
`nicemice_scriptedCrewMemberBehavior` directly, which is exactly why avoidance
was crew-only: a guard sent there would come back as a crew member.

Tuned values live in `nicemice_npcHooks.lua`: `NICEMICE_AVOID_SCAN_INTERVAL` (6s)
and `NICEMICE_AVOID_SCAN_RADIUS` (7 tiles), plus the `timeout` on
`nicemice_npc_move` in the run behaviors (5s of walking). If mice oscillate —
walk away, wander back, walk away — raise the move timeout rather than the
radius; the timeout is what controls how far they actually get.

**Tags are read from object config, not instance parameters.** The scan calls
`world.getObjectParameter(id, "itemTags")`, which resolves against an object's
own config. Tagging an arbitrary existing object through Tiled instance
parameters does *not* reach that lookup — this was tried and does not work.

So avoidance is placed with dedicated marker objects, which carry the tag
statically:

| object | tag |
|---|---|
| `nicemice_avoidmarker` | `avoidMe` |
| `nicemice_avoidmarker_left` | `avoidMe-goLeft` |
| `nicemice_avoidmarker_right` | `avoidMe-goRight` |

1×1, invisible in world (transparent sprite), with visible inventory icons.
Placeable in Tiled *and* by players in-world, which is why this was chosen over
reading instance params or building an avoidance stagehand: same mechanism for
ship authors and for a player redecorating their hold, and no script changes at
all. Costs one tile per marker.

### `root.itemHasTag` vs `root.itemConfig`

Two different lookups, and the difference matters.

- **`root.itemHasTag(name, tag)`** takes an item *name string*. Static lookup
  against the base `.activeitem` config; no build script runs. Used by every tag
  check — `nicemice_hasWandStaffPrimary`, the dispatch in
  `nicemice_resolveGuardBehavior`.
- **`root.itemConfig(descriptor)`** takes a descriptor and **re-runs the build
  script**. Used only by `itemConfigFor()`, for ability resolution.

This is why dispatch stayed correct throughout the phantom-descriptor bug while
ability intent did not: a name is a name. It also means tag checks are cheap
(no cache needed) but **per item type, not per instance** — every
`nicemice_generatedweapon_techstaff` has identical tags regardless of what it
rolled. Fine for dispatch; useless if you ever need to mark one specific
generated weapon.

### Fullbright layers and `gunParts`

`buildnicemiceweapon.lua` populates `config.fullbrightParts[k]` for every
animation part, but the assignment that actually binds a fullbright image to its
animation part —

```lua
config.animationParts[part .. "fullbright"] = config.fullbrightParts[part]
```

— used to live **only inside the `if builderConfig.gunParts then` block**. Guns
have `gunParts`; staves and wands do not. So a staff's `handlefullbright` /
`crownfullbright` parts existed in the `.animation` with no image attached and
rendered nothing in world, while the **inventory icon looked correct** because
that loop reads `config.fullbrightParts` directly. Symptom: "icon right, held
item dark."

The assignment now happens in the shared `animationParts` loop, gated on
`v.variants` — exactly the set of parts that have a fullbright sibling. Parts
without variants (the staff's `stone`, `chargeEffect`) declare `fullbright: true`
on themselves in the `.animation` and need no overlay part. Guns are unaffected;
the `gunParts` block assigns the same value afterwards.

### Weapon preservation across graduation

`recruitable.generateRecruitInfo()` hands the replacement NPC
`storage = preservedStorage()`, whose only item channel is `storage.itemSlots`.
That table is written **only** by `setNpcItemSlot()` — which `recruitable.setUniform()`
calls (hence uniforms survive) but which engine-rolled `items` and
`swapItemSlots()` bypass entirely (hence weapons did not).

`nicemice_npcHooks.lua` wraps `update` and, once per second, writes each weapon
slot through `setNpcItemSlot` — but only once its descriptor carries a roll, since
storing a bare descriptor would be worse than storing nothing. Gives up after 30s
so a permanently-stowed weapon doesn't poll forever.

Uniform preservation was **attempted and deliberately removed.** `dyeUniformItem`
force-stamps `crew.role.uniformColorIndex` onto every uniform item, so per-mouse
outfits can't survive. The chosen approach is one graduation npctype per uniform,
where the forced colour index is the intended behaviour.

---

## 3. Traps

**`.nodes` silently drops undeclared parameters.** THE most reliable trap in this
codebase — it has bitten three separate times. A parameter passed from a behavior
file that isn't in the action's `properties` block arrives as `nil` and hits
whatever `or default` fallback the Lua has. No error, anywhere.

- `rangedBehavior` — wired everywhere but undeclared, so pistol mice kept
  resolving to vanilla `guard`
- `returnBehavior` — same, would have silently disabled avoidance
- `timeout` on `nicemice_npc_move` — undeclared *and* passed as a bare scalar,
  so mice walked until they hit a ledge

**If a parameter seems ignored, check `.nodes` before anything else.** And note
parameters need the value wrapper: `"timeout": {"value": 5}`, not `"timeout": 5`.

**Anything time-based in a behavior action must accumulate the yielded `dt`.**
Behavior actions are coroutines resumed once per tick, and `coroutine.yield()`
returns the frame's `dt`. Two bugs came from ignoring that:

- `nicemice_chargedFire` kept `elapsed` as a **local**, so every teardown reset it
  to zero. An interrupted charge set the fire control true forever and never
  reached its release. Progress now lives on the board under
  `chargedFire-<nodeId>` (the pattern `behavior.lua`'s own `cooldown` and
  `limiter` decorators use), with a 0.5s staleness check.
- `nicemice_npc_move` used **`os.clock()`** — CPU time consumed by the process,
  not wall time. It crawls forward far slower than real seconds, so a 5s timeout
  effectively never expired. (`os` is also not guaranteed to exist in the
  sandbox.) The loop additionally discarded the yield's return value, so `dt`
  wasn't available even in principle.

**Every collision test in `nicemice_npc_move` is tile-based.**
`world.rectTileCollision` and `world.pointTileCollision` see TILES only. An
object with its own collision poly — a diagonal docking field, say — is invisible
to all of them, so a mouse standing on one reads as having no ground beneath it
and refuses to take a single step. It then returned `true` immediately, got
re-triggered by the next avoidance scan, and repeated forever while appearing to
"try". Vanilla dodges this because its docking zones are vertical and nobody
stands on them.

Now handled by `ledgePatience` (default 1s): being pinned is not accepted as
final. After a moment of getting nowhere the ledge requirement is dropped and the
mouse walks anyway — stepping off an object onto the deck is the wanted outcome.
Still blocked without ledge respect means a real wall, and it gives up.

**Anything else that has NPCs reasoning about walkable ground will hit this same
blindness.** It is a property of the collision API, not of that one object.

**`<frame>` is 1-indexed in `.animation` files and 0-indexed in object
`orientations`.** A state declared `"frames": 8` in an animation emits `<frame>`
values **1 through 8**, while the same `"frames": 8` on an object orientation
emits **0 through 7**. So a frames file named `name.0` ... `name.7` works from
orientations and silently breaks from an animation, which asks for a `name.8`
that does not exist.

Fix it with ALIASES, not by renaming the rows:

```json
"aliases" : { "default.8" : "default.0", "shields.8" : "shields.0", ... }
```

Renaming rows to `1..8` would fix the animation path and break the orientations
path, and an object commonly uses both (orientations for the placement preview,
the animation for actual rendering). Aliases satisfy both at once.

Also check `frameGrid.dimensions` against the real sheet size. The hologram sheet
was 8 x 25 while `dimensions` said `[8, 2]`, which makes every row past the
second unaddressable — the symptom is "only the first state ever renders."

**An object reads its OWN Tiled instance parameters, but do not count on reading
another object's.** `config.getParameter("thing", default)` inside an object's
script picks up parameters set on that object in Tiled, which makes
`storage.x = storage.x or config.getParameter("x", default)` a good pattern for
anything a ship author should be able to preset per placement.

Reading them from a DIFFERENT entity is another matter:
`world.getObjectParameter(id, "itemTags")` did not see tags set through Tiled
instance parameters, which is why avoidance uses dedicated marker objects
carrying the tag in their own config instead. Treat cross-entity parameter reads
as resolving against the object's base config until proven otherwise.

**`nicemice_setNPCBehavior` destroys the blackboard.** It builds a fresh
`behavior.behavior(...)` and a fresh board, so any board state a tree accumulates
across ticks is gone after a swap and the tree restarts cold. `storage` and `self`
survive; the board does not. Anything that must persist across a swap belongs in
`storage`.

It also used to read `config.getParameter("behaviorConfig", {})` directly, which
threw away the personality layer `bmain.init` builds:

```lua
self.behaviorConfig = config.getParameter("behaviorConfig", {})
if personality().behaviorConfig then
  self.behaviorConfig = applyDefaults(personality().behaviorConfig, self.behaviorConfig)
end
```

So every swap reset wander/idle timings to npctype defaults. Now reads
`self.behaviorConfig` with the raw parameter as fallback.

**Behavior action coroutines can be torn down mid-loop.** Locals do not survive.
`nicemice_chargedFire` originally kept `elapsed` as a local; every teardown reset
the count to zero, so an interrupted charge set the fire control true forever and
never reached its release. Progress now lives on the board under
`chargedFire-<nodeId>` (the pattern `behavior.lua`'s own `cooldown` and `limiter`
decorators use), with a 0.5s staleness check so a genuinely new cast starts fresh.

**`crewmember-catchup` sits above combat in the crew dynamic** (priority 2 vs 3)
and flickers as the recruiter moves, so it aborts running cast branches. That's
what exposed the coroutine bug. If more interruption problems appear, moving
catchup below combat and healsupport is the fix at source.

**`emptyHands: true` strands staff charges.** `crewmember-emptyhands` calls
`swapItemSlots` during the behavior run, before `bmain` reaches its
`npc.endPrimaryFire()` at the bottom of the same tick. A staff holstered mid-charge
never receives its release. **All crew npctypes must keep `emptyHands: false`**
(the base `nicemice_crewmember.npctype` already does). Dispatch is unaffected
either way, since the resolver reads the sheathed slot too.

**`bmain.update` clears the fire flags at the top of every tick.** So
`if self.primaryFire then ... end` inside a behavior node is nearly always false
and any release gated on it is dead code. `nicemice_clearWandstaffTargeting`
releases unconditionally for this reason.

**The crew combat parallel has an extra fail-fast sibling.** `entityInRange(target,
teleportRange)` with `fail: 1` collapses the whole tree the tick a target dies,
so the combat module never gets a tick with an invalid target — unlike the guard
wrapper, where `friendlyTargeting`'s `losTime` (8s) keeps it ticking. Cleanup that
needs to run at combat end must live in the crew module's **exit branch**, not
inside the combat module.

**A transplanted dialog sequence needs a `runner`.** In the guard wrapper the
announcement sequence ends with the combat module, which never completes. Stripped
of it, the sequence completes and a parallel restarts it every tick — combat
chatter spammed once per frame until a `runner` was added.

**Vanilla crew have no combat chatter** because it lives in `friendlynpccombat`,
which the crew path never routes through. Ours is transplanted from
`nicemice_friendlynpccombat-wandstaff` and is faithful to it.

**`buildweapon.lua` is a shared vanilla path** that other mods commonly override.
`nicemice_generatedweapon_techstaff` now points at `buildnicemiceweapon.lua`
instead. (Their seed/ability blocks are byte-identical; the swap was precautionary,
not the fix for anything.)

**Existing NPCs keep the behavior they resolved at spawn.** Always spawn fresh
mice when testing dispatch changes.

**`imagePosition` must be a multiple of 8 if the object is to place correctly
from Tiled.** Arbitrary pixel offsets look fine when a player places the object
in game, but Tiled-authored placement depends on the object centring on the
placement grid, which requires multiples of 8 biased one tile downward. The
exact bias differs depending on whether the object rounds to an even or odd
number of tiles in width and height. `nicemice_petport` is 88x40 px and uses
`[-48, -24]`.

This only bites on assets destined for dungeon or ship files, and it bites late
— the object works perfectly in hand and then refuses to line up in a Tiled
build. `animationPosition` must agree with `imagePosition` or the placement
preview and the placed object render in different spots.

**A container object without `frameCooldown` hard-crashes the CLIENT on
interact.** Not a Lua error, not a caught exception — the application shuts
down:

    (JsonException) Improper conversion to int from null
    [3] Star::Json::toInt
    [4] Star::ContainerObject::render
    [7] Star::WorldClient::render

`frameCooldown` has no documented default and nothing warns when it is absent.
The object places, renders and behaves normally right up until someone opens it.
Vanilla `pettether.object` carries `"frameCooldown" : 5`; copy that value.

Reading the stack correctly is the whole trick here. `WorldClient::render` means
CLIENT-SIDE RENDER, `ContainerObject::render` means the container-specific path
rather than generic object rendering, and the absence of any Lua frame means the
object's script is not involved at all. That combination points at a missing
container config key, not at anything scripted.

Adding `"frames"` and `"animationCycle"` to the orientations did NOT fix this,
though they are still required wherever `imageLayers` use `<frame>` — the
orientation's `frames` count is what that substitution resolves against.

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
shadows vanilla's global name. Camel case — `nicemiceSleepAction.lua` — keeps
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

## 4. Debugging

All instrumentation is present but dormant.

- **`trace()`** at the top of `nicemice_wandstaff.lua` — uncomment its body
- **`nicemice_debugLog`** in the same file — uncomment its body
- **`debugTargeting`** parameter in `nicemice_npccombat-wandstaff.behavior` and
  `nicemice_healsupport.behavior` — set `true`
- **`debugMovement`** parameter in `nicemice_npccombat-wandstaff.behavior` — set
  `true` to log `movePosition` / `maxRange` from the coordinator

With targeting debug on, every staff NPC logs an intent resolution per hand per
cycle. Noisy fast in a populated area — grab the log right after reproducing.

Useful one-liners:

```
/entityEval return sb.printJson(npc.getItemSlot("primary"))
/entityEval return sb.printJson(storage.itemSlots)
```

The first shows whether a descriptor carries its roll (`seed`,
`primaryAbilityType`, `altAbilityType`). The second shows what will survive
graduation.

Two traces were built and removed once they had served their purpose. Both are
worth reconstructing rather than reasoning around if the same class of question
comes up again:

- **Behavior dispatch** — a one-shot `sb.logInfo` in
  `nicemice_resolveGuardBehavior` printing the equipped weapon, its full tag
  list, which branch matched, and the resolved behavior. Log `matched` and
  `resolved` **separately**: a branch that matches but whose parameter was never
  declared in `.nodes` falls back to `baseBehavior`, which is indistinguishable
  from no branch matching at all if you only print the result. That distinction
  is what finally located the `rangedBehavior` bug.
- **Fire controls** — a change-triggered log of `self.primaryFire` /
  `self.altFire` in the update wrapper in `nicemice_npcHooks.lua`, *not* as a
  behavior node, because it has to see ticks after the tree has been torn down.
  A staff stuck visibly charged means either a branch is still setting the flag
  every tick, or nothing is and the item's own stance is stuck — opposite
  problems, and this is the only thing that tells them apart.

When a bug reproduces on one npc class but not another, the fastest split is
guard vs crew: they share the `nicemice_npccombat-*` layer and everything below
it, so a symptom in both is at that layer or lower, and a symptom in one is above
it. That single question has resolved several bugs faster than any log did.

---

## 5. Config-driven NPC spawner

`nicemice_configdrivenspawner` (V2 of Lofty's mod-friendly spawner; the older
`lofty_irisil_modfriendlynpcspawner` stays as-is in that mod). Variation tables
live in a standalone `.config` instead of being pasted into the Tiled object, so
other modders patch a small file at a stable path rather than hunting objectIds
inside dungeon map JSON.

Tiled object parameters:
```json
{ "spawner" : { "variationSource" : "/spawners/nicemice_cargoship_spawns.config",
                "variationSet" : "cargo" } }
```

`variationSource` also accepts a list of paths (sets are concatenated).
Inline `spawner.possibleVariations` still wins if present, so V1 spawners are
unaffected. Missing path or set name logs one warning and leaves the spawner
unsmashed rather than silently doing nothing.

The three script hooks (`possibleVariationsScriptHook`,
`selectedVariationScriptHook`, `finalResultScriptHook`) are unchanged, so existing
hotpatch scripts work without edits.

Note: V1 tested `fnpcParameter` (an unassigned global) where it meant
`npcParameter`, so its `scriptConfig.spawnedBy` block never ran. Corrected in V2 —
if that turns out to be unwanted, delete the block rather than restoring the typo.

---

## 6. Wired objects

### Ship diagnostic hologram

`nicemice_cargoshiphologram` cycles 24 ship areas, one per wire pulse from a
button. State names are the row names in its `.frames`, and the same names appear
in the `.animation` and in `DISPLAY_STATES` at the top of the `.lua` — **editing
one means editing all three.**

Advance on the RISING edge only. A pulse is the level going true then false, so
acting on every `onInputNodeChange` steps twice per press. Comparing against a
stored `lastLevel` also makes it behave sensibly when wired to a latching switch
rather than a button. `init` reads the current node level rather than assuming
false, and `onNodeConnectionChange` re-baselines it, so a display wired to an
already-ON switch does not advance on load.

`storage.displayIndex` falls back to `config.getParameter("displayIndex", 1)`,
so a ship author can preset the starting area from Tiled.

`nicemice_setDisplayState(name)` exists for jumping straight to a named area —
useful if anything ever reports diagnostics, or for per-deck buttons.

### NPC-exploding buttons

`reaction-touchandexplode` spawns `regularexplosionuniversal` at the react
target. It is NOT reachable by accident — the `"default"` fallback list in
`default_reactions.config` does not include it, so something names it explicitly.

It lives at the bottom of the inheritance chain in **`base.npctype`**, which
means every NPC in the game inherits it. Patching
`behaviorReactions.touchandexplode` globally would break it for every mod.

**RESOLVED — see §11.** It turned out to be reachable through exactly one route:
the `clumsy` personality, the only one of vanilla's fourteen that names
`explode`, `touchandexplode` or `burn` anywhere. Replacing the personality list
wholesale in `nicemice_base.npctype` removes the vector at the source, which is
cleaner than the `scriptConfig.reactions` override originally planned here. That
override is still the backstop if another mod ever injects an explosive reaction
into a shared pool. Verified in play: mice press buttons and survive.

## 7. Ship pets — MOVED

**This work now lives in its own mod, `lofty_petports`, with its own handoff
doc (`PETPORTS_HANDOFF.md`).** Split out 2025-08-19, before any public release,
while object and monster identity names were still free to change.

Everything that was in this section — the petport, the unit item, the vent,
placement validation, the behaviour replacements, and the design direction for
fuel, tasks and specialization — went with it. Do not maintain a second copy
here.

**What Nicemice keeps:** the content layer. Unit types, chassis variants, and
the encounter/quest loop that unit items drop from. That is the reason to
install Nicemice alongside petports rather than petports alone, and it ties the
pet work to the settlement and encounter items on the roadmap.

**What Nicemice still owes petports:** the avoidance marker objects
(`avoidMe`, `avoidMe-goLeft`, `avoidMe-goRight`) are Nicemice-authored and
`petports_placement.lua` reads their tags. It degrades safely in a world without
them, but the dependency exists and petports should eventually carry its own.

The engine traps discovered during that work are generic Starbound behaviour
rather than pet-specific, so they remain in §3 here as well as in the petports
doc — monster storage seeding, frame indexing, container `frameCooldown`, Tiled
placement offsets and the rest.

## 8. Status

**Working and tested in combat:** staff healing / buff / harmful trees; whip
combat; ranged combat; near-side kiting for staff and pistol; weapon dispatch
across guard, crew and quartermaster; crew combat chatter; crew medic combat
benefit; config-driven spawner placing mice on the cargo ship; avoidance zones
across crew, guards, quartermasters and villagers, with follow state preserved.

**Known and accepted:** large mobile monsters (adult poptop, the big bird) defeat
fixed-standoff kiting. Deliberate — further avoidance work would trivialise
challenging encounters, and the staves are already extremely strong. Slot
contention on uneven terrain (six mice, two or three near-side slots) causes
occasional clustering; a per-NPC column offset seeded from `entity.id()` would fix
it if it ever matters.

**Verified:** avoidance zones on all four npc classes, via marker objects placed
in Tiled; the walk-away timeout actually expiring; crew follow state surviving the
round trip; mice leaving a diagonal docking field they used to be pinned on;
staff fullbright layers rendering in world.

**Working and shipped (dialog/personality work, Aug 17):** eight mod-owned
personalities with no explosion vector; mouse-authored status text with a species
gate on the generator; speaker-side dialog across eleven vanilla config files;
listener-side dialog across six. One accent error survived to release across
several hundred lines (`owes` -> `oves`, now fixed and ruled out in §10);
everything else was tone-level editing.

**Ship pets — moved out.** The whole system now lives in `lofty_petports` with
its own handoff. Status for it is tracked there, not here. See §7.

**Untested:**
- Wand combat — one-handed, single-ability. **The `handAbility` off-hand fix has
  never run.** An off-hand item's alt-fire triggers its own `primaryAbility`, not
  its `altAbility`; `handItem` returns a second value (`ownsAltItem`) so
  `handAbility` can tell the cases apart. If one-handed pairs go quiet, that
  assumption is wrong.
- Whip near-side repositioning — built, never observed working. If whip mice stop
  approaching entirely, suspect `whipMinRange` vs the coordinator's `maxRange`
  producing an empty band (the node fails when `maxRange <= minRange`).
- Crew graduation for all 8 M.A.U.S. types.

**Unresolved but not currently biting:** crew in follow mode used to come back
from an avoidance walk wandering with weapons drawn. Two changes went in together
and the symptom stopped: a snapshot/restore of `storage.behaviorFollowing` +
`storage.followingOwner` around the swap, and the `behaviorConfig` fix in
`nicemice_setNPCBehavior`. **We do not know which one fixed it.** The
`behaviorConfig` bug is confirmed with a confirmed mechanism; the snapshot/restore
guards against storage loss that `nicemice_util.lua` shows cannot actually happen,
so it is probably a no-op. It is cheap and left in. If the symptom returns, the
board layer is the place to look — most likely `crewmember-emptyhands` re-swapping
the weapon off a fresh blackboard.

**Open work:**
- Ship pet behavior stack: the custom `groundPet.lua` replacement, a vent
  traversal action (needs `nicemice_ventTeleport(position)` on the pet side), the
  food bowl (one-slot container plus an action that reads `itemFoodLiking` and
  sets a status light), and interact-as-pat with a politeness window.
- Nothing calls `nicemice_petplacement.lua` yet. It is loaded and inert until
  `sleepAction` and the idle states are switched over to it.
- The pet station `uiConfig` points at vanilla `/interface/chests/pettether.config`
  so the container works; it will say "Pet Tether" until a bespoke one exists.
- `scriptConfig.reactions` override in the nicemice npctypes to stop
  `touchandexplode` firing off wall buttons.
- Three more graduation npctypes, once uniform assets are final (jumpsuit,
  officer jacket, black, red). Each needs its own `uniformColorIndex` +
  `defaultUniform`, paired with the matching `_recruitable` personnel type via
  `questGenerator.graduation.nextNpcType`.
- `nicemice_crewmember_maus_personnel.npctype` was drafted from inference and
  needs a review pass — `role.name`, `levelVariance`, and the placeholder
  `roleDescription` dialog are all guesses. (`emptyHands` was one of these guesses
  and caused a real bug; see Traps.)
- `nicemice_npccombat-wandstaff` doesn't dispatch — it assumes a staff. Only
  matters if mice can change weapon class mid-life.
- Chair-avoidance behaviors return via `nicemice_returnFromAvoid`, which reads
  the stored `returnBehavior`, so weapon dispatch re-runs instead of being
  clobbered. Confirmed working.
- The run-away behaviors are still named
  `nicemice_crew_avoidCaptainsChair_npcRun{Left,Right}` although they are no
  longer crew-specific and no longer about captain's chairs. Renaming means
  touching both files plus the two constants in `nicemice_npcHooks.lua`.
- Avoidance fires regardless of combat state, so a guard that wanders near a
  tagged object mid-fight gets pulled out of its combat tree. Not observed
  causing trouble; gating on `isValidTarget(target)` is the fix if it does.

---

## 9. Files owned by this work

**Lua**
`nicemice_wandstaff.lua`, `nicemice_resolveGuardBehavior.lua`, `nicemice_npcHooks.lua`,
`nicemice_whipaim.lua`, `nicemice_util.lua`, `nicemice_scriptedCrewMemberBehavior.lua`

**Node registry**
`nicemice.nodes` — 26 entries

**Combat trees**
`nicemice_npccombat-{wandstaff,whip,ranged}`, `nicemice_rangedcombat`,
`nicemice_melee-whip`, `nicemice_meleecombat-aim-whip`, `nicemice_healsupport`,
`nicemice_wandstaff-approach`, `nicemice_whip-approach`

**Wrappers and roots**
`nicemice_friendlynpccombat-{wandstaff,whip,ranged}`,
`nicemice_guard-{wandstaff,whip,ranged}`,
`nicemice_crewmember{,-wandstaff,-whip,-ranged}`,
`nicemice_crewmember-combat-{wandstaff,whip,ranged}`,
`nicemice_quartermaster`, `nicemice_quartermaster_guard{,-wandstaff,-whip,-ranged}`

**Entry points** (each passes its own name as `returnBehavior` to `nicemice_initHooks`)
`nicemice_scriptedGuardBehavior`, `nicemice_scriptedCrewMemberBehavior`,
`nicemice_scriptedVillagerBehavior`, `nicemice_quartermaster`,
`nicemice_crew_avoidCaptainsChair_npcRun{Left,Right}`

**Item build**
`buildnicemiceweapon.lua`

**Objects**
`nicemice_avoidmarker{,_left,_right}.object` + sprites,
`nicemice_configdrivenspawner.object` + `.lua`,
`nicemice_cargoshiphologram.object` + `.lua` + `.animation`

**Ship pets** (all untested)
`nicemice_petstation.object` + `.lua` + `.animation`,
`nicemice_petvent.object` + `.lua` + `.animation`,
`nicemice_shippet.item`, `nicemice_shippet_drone.monstertype`,
`nicemice_petplacement.lua`

**Configs**
`nicemice_crewmember_maus_personnel.npctype`, `coordinator.stagehand.patch`,
`nicemice_cargoship_spawns.config`

## 10. Nicemice speech patterns

The accent is applied by hand, not programmatically. These rules are descriptive
of what shipped — follow them and new lines will match the ~400 already in the
mod.

### Consonants

**`w` → `v`, but only as a consonant.** `when` → `vhen`, `will` → `vill`,
`worried` → `vorried`, `awake` → `avake`.

Do **not** convert a `w` that is part of a vowel sound. This is the one error
that made it to release: `owes` became `oves`, which reads wrong because the `w`
there is carrying a long `o`, not acting as a consonant. Left alone: `how`,
`owes`, `know`, `slow`, `now`, `town`, `brown`, `crown`, `own`. The test is
whether you'd *pronounce* a `w` at that position — if the sound is a vowel
glide, leave the letter alone.

**`s`, soft `c` and `x` → `z`.** `box` → `bokz`, `complacent` → `complazent`,
`suspicious` → `zuzpiziouz`. Plural `-s` → `-z` almost always. Hard `c` stays
(`carefully` → `carefullie`, not `zarefullie`).

**`th` → `z` or `t'`.** Both are in use and both are correct — `zey`, `zeir`,
`zat` alongside `t'ink`, `t'ing`, `t'ank`. Mice have dialects; inconsistency
between lines is deliberate and inconsistency *within* a line is fine too.

**`sh` → `zh`,** loosely. `should` → `zhould`, `harshly` → `harzhlie`. Not
absolute — `ship` survives unchanged in shipped lines.

### Endings

Sparingly — roughly one line in three, never every eligible word:

- `-ly` → `-lie`: `exactly` → `ekzaktlie`, `respectfully` → `rezpectfullie`
- `-ing` → `-ink`: `engineering` → `engineerink`, `searching` → `zearchink`
- `-ement` on a French pivot: `naturally` → `naturallement`
- `-y` → `-ie` on short words: `duty` → `dutie`, `body` → `bodie`

### Register

Contractions are a tone dial, not an accent rule. Formal registers spell things
out — a M.A.U.S. officer says "do not", a panicking villager says "don't". When
in doubt for a haughty or military line, expand the contraction.

Voice by context, as shipped:

- **M.A.U.S. personnel / combat** — clipped, formal, military. "Engaging
  hoztilez!" "Reporting nozing unuzual."
- **Tenants and villagers** — petty, proprietary, easily affronted. "Zomeone haz
  been touching my t'ingz."
- **Quest-givers** — transactional and faintly sniffy. "A bribe? How vulgar. I
  accept."
- **Crew** — dutiful, dry, quietly proud. "Ze zhip iz in acceptable condition,
  adjutant."
- **Fleeing / extorted** — undignified, and the mice know it. "Zat vaz
  undignified." "Never zpeak of ziz."

Everything stays in-universe. No real-world references — that was half the
complaint about other mods' status text and is the reason this work exists.

### Things that must survive verbatim

Substitution tags are filled in at runtime and break if accented or altered:
`<questGiver>`, `<item>`, `<enemy>`, `<receivedItems>`, `<selfname>`,
`<entityname>`. Vanilla's embedded `\n` in Hylotl haiku lines is likewise
literal.

### Direction matters

The accent applies **only to lines mice speak**. Listener-side dialog — other
species reacting to a mouse player — is written in *that* species' voice:
Floran hisses, Glitch leads with an emotion word, Novakid drawls, Fenerox uses
clipped triplets. Those pools have no accent at all.

Tone chosen for the galaxy's reaction to mice: curiosity and mild
condescension, not hostility. The Floran wants to pet you; the penguin is
pleased to meet someone at eye level; the devout Avian asks you not to nest in
the rafters. The asymmetry against the mice's own snobbery is the joke. Cultists
are the exception and are openly hostile.

## 11. Personalities and status text

### `nicemice_base.npctype`

An intermediate layer sitting between vanilla `base` and the three mod roots
(`nicemice_villager`, `nicemice_nakedvillager`, `nicemice_crewmember`); everything
else inherits through those. It exists to replace `scriptConfig.personalities`
wholesale — arrays are *replaced* rather than merged during npctype inheritance,
so declaring the list here overrides all fourteen vanilla entries at once.

Eight personalities: `nicemice_haughty` (1.5), `nicemice_fussy`,
`nicemice_dutiful`, `nicemice_gossip` (1.0 each), `nicemice_timid`,
`nicemice_gourmand`, `nicemice_scoundrel` (0.75 each), `nicemice_dreamer` (0.5).

**The `nicemice_` prefix is load-bearing.** Personality names are lookup keys for
status text, so a name colliding with a vanilla one lets other mods' lines back
in. That isolation is the whole point of the exercise.

Machine-interaction keys (`wallbutton`, `wallswitch`, `console`, `brokenConsole`,
`teleporter`, `turret`, `handdryer`, `vendingmachineCollect`) are declared
explicitly on every personality and deliberately **not** listed in
`additiveReactions`, so they replace the inherited pool rather than extend it.
Belt and braces against a mod injecting something explosive into a shared pool.

**Personality resolves at spawn**, exactly like behavior dispatch — existing mice
keep whatever they rolled. Spawn fresh mice when testing. A saved mouse may still
hold a vanilla personality name that no longer exists in the list, leaving
`personality().behaviorConfig` nil.

Status lines double as a personality readout in-world, which makes them the
cheapest way to confirm you're sampling across the set during a test.

### Status text

`statuses.config` is keyed by personality name, with a large `generic` pool that
vanilla merges in on top of the personality list. Mod-owned keys live in
`statuses.config.patch`: ten lines per personality plus a 20-line
`nicemice_generic` standing in for vanilla's `generic`.

The generator is overridden in `nicemice_npcHooks.lua` by capturing and wrapping
`randomStatusText`, gated on `npc.species() == "nicemice_npc"` so non-mice fall
straight through to the original. Species-flavour lines (whiskers, tail, crumbs)
live in `nicemice_generic` rather than in any personality list, since that pool
is what every mouse can draw from.

**Trap — `or` short-circuits.** The first draft read
`if personality or math.random() < 0.25 then`, which never evaluates the random
when a personality exists (generic branch unreachable) and indexes
`statuses[nil]` when one doesn't (crash on `#options`). Test the two conditions
separately, guard `#options > 0`, declare `options` `local`, and keep a real
fallback to the original function.

Don't concatenate the personality and generic pools — at 10 lines against 20 the
result is two-thirds generic and the personality voice disappears. An explicit
chance constant keeps the ratio controlled as pools grow.

## 12. Dialog architecture

### Keyed by species, not personality

Every file under `/dialog/` keys on **species**, not personality. Personality
never enters these lookups — that's `statuses.config` only.

Two distinct identifiers, and mixing them up is silent failure:

- **`nicemice_npc`** — the NPC species. Used when a mouse is *speaking*.
- **`nicemice`** — the player species. Used when someone is speaking *to* a
  mouse player.

### Nesting

The common shape is `fragment / speaker species / listener species / [lines]`,
with `default` at each level as the fallback. Two consequences:

- Patching in a `nicemice_npc` speaker key fully isolates mice: they stop
  resolving `default`, so lines other mods add under other species keys can never
  reach them. **This is why patching beats parallel copies here** — no npctype
  re-pointing needed at all.
- Adding a `nicemice` listener key *removes* the fallback for that branch. The
  new key becomes the entire pool for mouse players, so it must cover the NPC's
  whole conversational range, not just the mouse-specific joke.

Exceptions worth knowing:

- **`quest.config` is four levels** — `fragment / subfragment / speaker / listener`
  — and is speaker-side. Not to be confused with `/quests/templates/` in
  section 13, which is a separate surface with its own routing. `nicemice_villager`, `nicemice_generictenant` and every
  maus type carry `questGenerator`, so without a `nicemice_npc` key every
  generated quest comes out in plain English. 29 pools.
- **`clues.config` has no top-level `default` at all.** Its top level is the
  speaker species directly (and vanilla omits novakid entirely), so a species
  without a key has nothing to fall back to. Used by scan missions, which send
  the player into arbitrary settlements — reachable by ordinary mouse villagers.
  Three levels: `species / default / default`.
- **`merchant.config` carries duplicate copies** of the grumble and arrivedhome
  fragments (`tagCriteria`, `enclosedArea`, `otherDeed`, `severe`, `final`,
  `beacon`, `rent`). Mouse tenants resolve through `grumble.config` /
  `arrivedhome.config` instead, so those copies are dead weight — don't patch
  them. Its key names also differ from the npctype's: the npctype declares
  `start`/`end`, the file calls them `merchantStart`/`merchantEnd`.
- **`converse.config:breakObject` does not exist.** Both villager npctypes
  declare `"breakObject" : "/dialog/converse.config:breakObject"` at line 107 and
  vanilla has no such fragment — cruft inherited from the vanilla villager
  npctype. Harmless, still dead.

### Patch conventions

Established form, matching the existing patches:

```
{ "op" : "add", "path" : "/<fragment>/nicemice_npc",         "value" : {} },
{ "op" : "add", "path" : "/<fragment>/nicemice_npc/default", "value" : [ ... ] }
```

Two ops: create the species object, then fill its listener array. A single op
adding a nested object works too but reads worse in diffs. Listener-side keys
need only one op, since the speaker object already exists. CRLF line endings,
tabs, `//` comments are fine — the asset parser accepts them.

**Trap — wrong value shape deserializes at NPC load, not at patch time.** A
`/scripts/-` append with `"value" : ["/npcs/foo.lua"]` nests an array inside a
list of strings; the game fails to deserialize NPCs with an "expected string, got
array" error that points nowhere near the patch. `"value" : "/npcs/foo.lua"` is
what that op wants.

**Verify patches before shipping** by applying them to a copy of the target in
Python: confirm every parent path resolves, that nothing overwrites an existing
key, and that every `<tag>` used also appears somewhere in the vanilla file. This
catches missing parents and invented substitution tags, which are the two failure
modes that otherwise surface in-game.

### Gating and grouping — mod-wide convention

Any vanilla asset may already have been edited by another mod, so an unguarded op
is a bet that nobody got there first. Two out-of-spec features the asset parser
accepts:

**`test` ops.** `{ "op" : "test", "path" : "/x" }` passes if `/x` exists. Adding
`"inverse" : true` passes if it does *not*. Adding `"value" : <v>` tests for an
exact match instead of mere existence. No `value` is given when testing only for
existence.

**Nested groups.** A `.patch` file's top level may be an array of *arrays*. Each
inner array is applied independently, and a failed test aborts only its own
group. In a flat file a failed test stops everything after it — so one conflict
on one node silently drops every unrelated edit below it, and the asset comes out
half-modified. That is the worst failure mode available, because it reads as
sloppy authoring rather than as a patch conflict.

The standard form:

```
[
	[
		{ "op" : "test", "path" : "/<parent>" },
		{ "op" : "test", "path" : "/<parent>/<key>", "inverse" : true },
		{ "op" : "add",  "path" : "/<parent>/<key>", "value" : ... }
	],
	[ ... next independent edit ... ]
]
```

Parent-exists, then not-already-present, then write. This also makes patches
idempotent for free — a second application finds the key and skips.

**`op : replace` is heavy-handed and should be rare.** It overwrites whatever is
there, including another mod's work. Where it is genuinely unavoidable — see the
title split in section 13 — gate it behind a `test` with an exact `value` of the
stock vanilla contents, so it fires only on an untouched node and no-ops
everywhere else.

**Array appends (`/-`) have no natural idempotence** and need a value test
against the index the entry would land at. Section 13 has a worked example.

The `/dialog/` patches from section 12 predate this convention and are ungated.
They have not caused a problem, but if they are ever regenerated, gate them.

### Coverage as shipped

**Speaker side (`nicemice_npc`)** — thief, arrivedhome, converse, combat,
crewmember, flee, grumble, merchant, quest, clues, peacekeeperconverse.

**Listener side (`nicemice`)** — converse, outpost, shipcrew, devoutavian,
fenerox, cultist.

**Deliberately deferred**, with reasons:

- `guard.config` — both halves. Mouse guards have no hail behavior in the
  streamlined tree, and the reactive half (vanilla guards hailing a mouse player)
  is listener-flat: seven fresh pools of ~10 lines. Revisit with the MAUS tenant
  suite.
- `bounty.config`, `bountytarget.config` — bounty targets must be inserted
  manually, so mice cannot spawn as them. Would be ~18 pools. Also a voice the
  mod hasn't established: cornered, crooked, unhinged.
- `airship`, `alpaca`, `colourful`, `eyepatch`, `miniknog`, `gatherer`,
  `oremerchant` — confirmed unnecessary.
- Combat-bark files (`deadbeat`, `eyeguard`, `mutantminer`, `miniknogthreats`,
  `rebel`, `scientist`, `sniper`, `spacehero`, `peacekeeper`) — barks fly past
  mid-fight and don't repay per-species text. `frog.config` is entirely "..." and
  `mutantminer` is entirely "Rargh!".

`peacekeeperconverse.config` is patched speaker-side but **inert** — no mouse
peacekeeper npctypes exist yet. Same for `clues.config` until scan missions are
exercised.

### Open threads

- `nicemice_generic` only fires if the status generator merges it; check the
  chance constant in `nicemice_npcHooks.lua`.
- `devoutavian` mouse pool is 18 lines against vanilla's ~50 per listener, so
  mice loop sooner than other races. Grow it if that NPC turns out to be common.
- `crewmember.config` nests listener under speaker; a `/converse/nicemice_npc/nicemice`
  key would let crew address a *mouse* captain differently ("adjutant"). Not done.
- `combat` and `crewmember:converse` are the two places repetition is most
  audible, and the natural candidates if personality-keyed dialog is ever wanted.
  Note that would need a different mechanism — `/dialog/` files don't see
  personality.

### Files owned by this work

**Personalities**
`nicemice_base.npctype` (new; `nicemice_villager`, `nicemice_nakedvillager` and
`nicemice_crewmember` re-pointed to it)

**Status text**
`statuses.config.patch`, `randomStatusText` override in `nicemice_npcHooks.lua`

**Dialog patches**
`combat.config.patch`, `crewmember.config.patch`, `flee.config.patch`,
`grumble.config.patch`, `merchant.config.patch`, `quest.config.patch`,
`clues.config.patch`, `peacekeeperconverse.config.patch`,
`outpost.config.patch`, `shipcrew.config.patch`, `devoutavian.config.patch`,
`fenerox.config.patch`, `cultist.config.patch`
(plus the pre-existing `thief_config.patch`, `arrivedhome_config.patch`,
`converse_config.patch`)

## 13. Quest template dialog

`/quests/templates/*.questtemplate` is a **separate surface** from
`/dialog/quest.config` in section 12. That file governs the conversational
fragments around a quest; these files hold the quest's own generated text. Both
key on species, and it is easy to think the work in one covers the other.

35 patches, 206 guarded groups, 606 ops, 309 mouse lines across 159 pools.
Shipped after the Aug 17 release.

### Structure

`scriptConfig.generatedText` routes as
`fragment / [subfragment] / speaker species / [lines]`. Vanilla ships exactly
three species keys — `floran`, `glitch`, `default`. Mice get `nicemice_npc`
alongside them.

Speaker-side only. Every one of these templates carries `questGiver`, so the
species that resolves is the quest giver's, and `nicemice_villager`,
`nicemice_generictenant` and the maus types all hit it.

Fragments: `text`, `completionText`, `goalText`, `title`, `failureText`, `fluff`.
Subfragments under the first two: `first`, `next`, `last`, `default`. Not every
template has all four — `barter` has one pool per fragment; `collect_fine`,
`intimidate`, `return_stolen`, `share_secret` and `spread_rumors` have all four
on both `text` and `completionText`.

### Three fragments are not what they look like

**`failureText` is player-voiced but species-keyed on the quest giver.** It reads
"I was unable to help `<questGiver>`" — that is the player's quest log, not the
NPC. Accenting it would put a mouse accent in a *non-mouse* player's log whenever
the quest giver happened to be a mouse. Left vanilla in all 35, by the same
"direction matters" rule as section 10. 12 templates have it flat, 11 as a
`{default: [...]}` shell.

**`title` comes in two shapes and vanilla never species-varies it.** 11 templates
nest it under `default`; 12 store it as a bare array. The 11 dict-shaped ones
have no `floran`/`glitch` sibling, which means the species lookup already falls
back to `default` for every non-mouse quest giver — so both shapes are live in
the resolver and adding a key to either is safe.

**`fluff` is a tag pool, not a dialog pool.** It is an array of
`[tagName, [values]]` pairs feeding `<verb1>`, `<crime>`, `<appreciation>` and
friends, and it is not species-keyed at all. Vanilla fakes species variants by
*naming* the tag with a suffix — `<florandreams>`, `<crimefloran>`,
`<appreciationfloran>` — and referencing it only inside the floran lines. Glitch,
by contrast, reuses the neutral English pools and just prefixes an emotion word.

Mice follow the Floran model: self-contained lines plus `nicemice`-prefixed fluff
appended via `/fluff/-`. Using the neutral pools would inject plain English
mid-accent, which is the whole failure this avoids.

New fluff tags by file:

- `capture_pet` — `nicemicedreams`, `nicemiceappreciation`
- `escort` — `nicemicefriend`, `nicemiceactivity`, `nicemiceappreciation`
- `escort_trade` — `nicemiceappreciation`
- `kidnapping` — `nicemicefriend`, `nicemiceactivity`, `nicemiceappreciation`
- `kill_monster_group` — `nicemicebelonging`, `nicemicerevenge`, `nicemiceappreciation`
- `kill_monster_single` — `nicemicegiant`, `nicemicerumour`, `nicemicerequest`, `nicemiceappreciation`
- `kill_npc` — `nicemicecrime`, `nicemicerequest`, `nicemiceappreciation`
- `kill_npcs` — `nicemicecrime`, `nicemicejustice`, `nicemicerequest`, `nicemiceappreciation`

Names repeat across files; fluff is per-template, so that is fine.
`share_secret`, `spread_rumors` and `collect_fine` have fluff arrays consumed by
`secretNote` / `responseNote` / the fine-notice item rather than by
`generatedText`, so they needed no additions.

### Patch shape

Every group follows the gated form from section 12. Speech pools, all 159:

```
[
	{ "op" : "test", "path" : "/scriptConfig/generatedText/<route>" },
	{ "op" : "test", "path" : "/scriptConfig/generatedText/<route>/nicemice_npc", "inverse" : true },
	{ "op" : "add",  "path" : "/scriptConfig/generatedText/<route>/nicemice_npc", "value" : [ ... ] }
]
```

Note this is **one op**, not section 12's two — the species dict's value *is* the
line array. There is no listener level in questtemplates.

### Titles — the one place `replace` is used

The 12 bare-array titles have no species level to add into, so the node has to be
split. Every title-bearing file gets the ordinary add group; those 12 get a
second group as well:

```
[
	{ "op" : "test",    "path" : "/scriptConfig/generatedText/title", "value" : [ <exact vanilla lines> ] },
	{ "op" : "replace", "path" : "/scriptConfig/generatedText/title",
	  "value" : { "default" : [ <exact vanilla lines> ], "nicemice_npc" : [ ... ] } }
]
```

The value-test is what makes the `replace` acceptable: it fires only when the
node is still exactly stock vanilla. If another mod rewrote the title, the test
fails and their version is untouched — mice simply do not get a title on that
template.

One op covers every case, because `Json::operator==` recurses element-wise on
arrays: different contents fail, an *appended* line fails on length, and an
already-split dict fails the type check before comparison starts.

The two groups are mutually exclusive by construction:

| starting state | add group | split group | outcome |
|---|---|---|---|
| pristine flat array | skips (no `/default`) | fires | split, vanilla preserved under `default` |
| already split by another mod | fires | skips (not a bare array) | added beside their keys |
| flat array rewritten by another mod | skips | skips (value mismatch) | untouched |
| flat array with a line appended | skips | skips (length mismatch) | untouched |
| this patch re-applied | skips (`nicemice_npc` present) | skips | no-op |

Flat-title templates (need the split): `add_object_to_house`, `bribe`,
`build_home`, `collect_fine`, `gift`, `intimidate`, `protect`, `recruit_guard`,
`return_stolen`, `share_secret`, `spread_rumors`, `themed_build`.

Dict-shaped (plain add): `capture_pet`, `escort`, `hat`, `helmet`, `kidnapping`,
`kill_monster_group`, `kill_monster_single`, `kill_npc`, `kill_npcs`,
`new_stock1`, `new_stock2`.

### Trap — `/fluff/-` is unconditional

An array append has no natural idempotence, so a double install duplicates every
tag pool. The guard is an inverse *value* test on the index the entry lands at in
clean vanilla:

```
{ "op" : "test", "path" : "/scriptConfig/generatedText/fluff/<N>/0", "value" : "<tag>", "inverse" : true }
```

Note the `/0` - it tests the tag *name*, a string, rather than the whole
`[tag, [values]]` pair.

On re-application our entry is sitting at `N`, the test fails, the group skips.
If another mod appended first, `N` holds *their* entry, the test passes, and ours
still lands at the end.

That asymmetry is deliberate and worth preserving if these are ever regenerated.
A duplicated fluff entry is cosmetic — it skews a random pick. A fluff tag that
fails to land renders in-game as a literal `<nicemicedreams>` in the middle of an
otherwise finished line. The guard is tuned to prefer appending when the
situation is ambiguous.

`N` per file: `capture_pet` 9, `escort` 8, `escort_trade` 2, `kidnapping` 15,
`kill_monster_group` 19, `kill_monster_single` 14, `kill_npc` 11, `kill_npcs` 19.

### Tags that must survive verbatim

Beyond section 10's list, the dotted pronoun forms are everywhere here:
`<target.pronoun.object>`, `<target.pronoun.capitalSubject>`,
`<questGiver.pronoun.possessiveDet>`, `<enemy.pronoun.copulativePast>`,
`<victimNpcType.pronoun.subject>`, `<thief.pronoun.possessiveDet>`.

`<spawnPoint>` is always followed by `<spawnPoint.direction>` — keep the pair.
Literal `\n` appears inside `capture_pet` text lines.

### Capitalization follows vanilla per line

Vanilla is internally inconsistent: most titles are sentence case, but
`<questGiver>'s Home Makeover`, `<questGiver>'s Agenda`,
`Bring <target> to Justice`, `<questGiver> the Gift Giver` and `<monster> Hunter`
are title-cased. Mouse titles match whichever form that template's vanilla line
uses, so a mouse quest sitting beside another species' quest in the log reads as
the same register rather than as a styling slip.

Two article rules, both inherited from vanilla's own solutions:

- `A <enemy>`, never `An <enemy>` — the tag substitutes an arbitrary name, so
  `An` misfires on consonant-initial ones. Vanilla writes `A`.
- `any <item>` rather than `an <item>` in `request_craft` — vanilla's dodge
  around the same problem.

### `test` semantics, from the engine source

Read from `applyTestOperation` at the **initial commit** of the OpenStarbound
repository - that is, the retail baseline before any fork changes - so this
applies to stock Starbound:

- **A `value` comparison is deep.** The check is `testValue == *value` on `Json`
  objects, and `Json::operator==` recurses element-wise for `Type::Array` and
  `Type::Object`, comparing length and every item in order. Arrays can be tested
  whole; there is no need to break them into per-index tests.
- **Type mismatch fails cleanly.** The comparison short-circuits on
  `type() != v.type()`, so an array `value` tested against a dict returns false
  rather than doing anything surprising.
- **A missing path with `inverse : true` passes.** `TraversalException` is caught
  and the handler returns `base` when inverse is set. This is what makes an
  inverse existence test on a not-yet-present key the standard idiom, and it means
  an out-of-range array index is safe to test for.
- **A missing path without `inverse` is a clean test failure**, not a crash - it
  raises `JsonPatchTestFail`, which aborts the group and nothing else.
- **Failed tests do not write to the log.** Reported by modders on retail since
  at least 2017. This is why a wrong guard never announces itself: no error, no
  box character, just an edit that silently did not happen.
- **Numeric comparison is loose** - Int and Float compare equal when both
  `toDouble()` and `toInt()` agree. Irrelevant here, since every value tested is
  a string or an array of strings, but it would surprise someone testing `1`
  against `1.0`.

`Json::operator==` itself was read from the fork's current tree rather than the
baseline. It is core code with no reason to have been touched, but that one link
in the chain is inference rather than direct reading.

### Do not use `op : test` with a `search` operand

Third-party clients (OpenStarbound and relatives) added a `search` operand:
`{ "op" : "test", "path" : "...", "search" : <value> }`, calling `findJsonMatch`
to ask whether a container holds a value. It is **not in retail** - it is absent
from the baseline handler above.

It is tempting, because it is the natural way to write "is my entry already in
this array" without hardcoding an index, and it would let the fluff guards below
drop their `FLUFF_BASE` table. Do not. On retail the patch would fail, and
because failed tests are silent it would fail without a log line.

Noted here only so nobody rediscovers it in a fork's source and adopts it
thinking it is stock. The same caution applies to anything else found in a fork
repository: check it against the initial commit before relying on it.

### Trap - the font has no glyph for characters vanilla never uses

Em dashes shipped in 31 places across 19 templates and rendered in-game as an
empty box. Starbound's dialog font covers roughly printable ASCII; anything
outside it fails silently at render time, not at load, so nothing in the log
points at it.

Vanilla writes interruptive dashes as a spaced hyphen - 44 instances across these
templates, zero em dashes - and `converse_config.patch` already followed that
convention in 21 places. The mod had a house style and the em dashes broke it.

**Do not just scan for non-ASCII with a whitelist.** The original scan whitelisted
`—` as "obviously fine punctuation", which is exactly how it survived four rounds
of verification. The reliable check is to diff the character set of new text
against the character set vanilla actually uses:

```python
van_chars = set(open(vanilla_template).read())
novel = set(my_text) - van_chars      # anything here is suspect
```

That test is stricter than an ASCII check and catches smart quotes, ellipsis
characters and non-breaking spaces too - all of which paste in invisibly from
editors and all of which the font lacks.

### Known plain-English leaks

Two parameters resolve outside `generatedText` and stay unaccented inside mouse
lines. Both are single words; fixing them means touching the generator, not these
files.

- `<adjective>` in `hat` / `helmet` — dropping it would lose the quest's premise
- `<tag>` in `recruit_guard` / `themed_build` — furniture tag

### Verification performed

A patch simulator implementing the group-abort semantics was run per template:
parent paths resolve, no add overwrites, **idempotence** (second application
applies zero groups, document byte-identical), **conflict tolerance** (a foreign
`nicemice_npc` injected into one pool skips exactly one group and every other
group still lands), and all five title scenarios above, including a mod that appended an extra title line rather than replacing the array. Plus accent lint over all
309 lines, tag tracing, colour-code checks, the vowel-glide check from
section 10 (`own`, `owns`, `town`, `know`, `how` confirmed left alone), and a
character-set diff against vanilla (see the font trap above).

Confirmed in-game alongside a heavily-modded quest-giver set (Denelaun): mouse
titles render from `nicemice_npc` while other species continue to draw vanilla's
line from the `default` key the split wrote back. Two mods adding species keys to
the same `generatedText` node, neither displacing the other.

**Still unverified against a full unpack.** 12 vanilla templates dropped out of
the working session partway through, so the simulation covered 23 of 35. Two
constants in those were transcribed rather than read at emit time:

- flat-title value-tests — 5 of 12 checked, 0 mismatches; `gift` later confirmed
  in-game (its split fired, which requires an exact match). Unchecked:
  `add_object_to_house`, `bribe`, `collect_fine`, `intimidate`, `spread_rumors`,
  `themed_build`.
- fluff base indices — 6 of 8 checked, 0 mismatches. Unchecked: `escort`,
  `kill_monster_single`.

Both fail safe. A wrong title value-test means the split never fires and the
title stays English; a wrong fluff index means at worst a duplicate entry on
reinstall. Neither can corrupt an asset or fail a load. But both fail *silently*,
so they are worth one confirming run.

### These are scaffolding

The plan is nicemice-specific quest templates in their own pool, declared on
`nicemice_base.npctype` — the same array-replacement trick that overrode
`scriptConfig.personalities` wholesale in section 11. The motivation is not the
accent: it is that other mods pollute the shared generated-quest pool, and a
mouse being handed "build a home for a new stranger" asks the player to install a
species the Fleet does not tolerate lorewise.

**When mice get their own pool, these 35 patches stop firing.** They are keyed to
`nicemice_npc` as speaker; if mice never generate a vanilla template, the mouse
lines never resolve. Any vanilla template deliberately *kept* in the pool keeps
its accent, so there is a reasonable middle path where the neutral errands
(`fetch`, `craft`, `cooking`, `farming`, `barter`) survive as tenant quests while
the settlement-expansion ones (`build_home`, `themed_build`, `recruit_guard`) are
dropped. Those three are the lore-violating cases; the rest are tonally fine.

### Open threads

- `goalText` for `kill_monster_group`, `kill_monster_single` and `escort` is a
  single line in vanilla and a single line here; repetition will be audible if
  those quest types are common. Same for `escort` / `escort_trade` completion.
- `bounty.questtemplate` and friends were not in scope, consistent with the
  `bounty.config` deferral in section 12.
- The current voice across all 309 lines is quest-giver register — transactional
  and faintly sniffy. If the tenant suite grows, that is already the right voice;
  the Fleet's clipped military register would need separate pools, which
  `generatedText` cannot key on personality any more than `/dialog/` can.

### Files owned by this work

`/quests/templates/*.questtemplate.patch` — 35 files, one per vanilla template:
`add_object_to_house`, `barter`, `borrow`, `bribe`, `build_home`, `capture_pet`,
`collect_fine`, `collect_gift`, `cooking`, `craft`, `escort`, `escort_trade`,
`extort`, `farming`, `fetch`, `gift`, `hat`, `helmet`, `intimidate`,
`kidnapping`, `kill_monster`, `kill_monster_group`, `kill_monster_single`,
`kill_npc`, `kill_npcs`, `new_stock1`, `new_stock2`, `protect`, `recruit_guard`,
`request_craft`, `return_stolen`, `share_secret`, `spread_rumors`, `steal`,
`themed_build`.

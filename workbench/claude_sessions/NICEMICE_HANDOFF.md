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
types, three weapons and the cosmetic/furniture set. Section 7 (ship pets) is the
live work and none of it has been run. Section 3 (Traps) is the most valuable
part of this document — every entry cost a debugging cycle to find and none of it
is inferable from reading the code. Sections 10-12 exist so the vanilla dialog
configs never need re-uploading to work on mouse text again.

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

## 7. Ship pets (IN PROGRESS — nothing here has been tested)

The live project. Vanilla ship pets are widely disliked: they shadow the player,
swallow clicks meant for objects behind them, and park in front of the things you
need. The design goal is the opposite — small robotic units that find something
useful to do, inspired by Axiom Verge's ambient drones and Factorio's logistics
bots rather than by a squishy pet that wants attention.

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

`nicemice_shippet.item` carries a `petData` block — `monsterType`, display
fields, and the `status` / `storage` the station writes back as the pet lives. A
found item ships with just the monster type; the rest accumulates.

This also enforces the ship-pet/wild-monster boundary **structurally**. Wild
monsters and ship pets use entirely different script stacks and are visually
magnitudes apart, and that separation must hold. A wild monster has no
`nicemice_shippet` item, so it can never be socketed — no runtime type check
needed.

### The station implements vanilla's anchor contract

`groundPet.lua`'s `findAnchor` calls `status.setResource("health", 0)` — it KILLS
the pet — if it cannot find an anchor object within 5 tiles of its last anchor
position. So `nicemice_petstation.lua` implements the same `hasPet` / `setPet`
contract `techstation.lua` does, and the monstertype's `anchorName` points at it.

**`anchorName` must match the station's `objectName` exactly.** Rename the object
and pets die on the next load.

This is deliberate scaffolding: it lets vanilla's pet scripts run unmodified
while the behavior work happens separately.

### Vents: wires as links, not signals

Every other wired object uses wires as a SIGNAL (`setOutputNodeLevel` /
`getInputNodeLevel`). `nicemice_petvent.lua` uses them as a LINK — what matters
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

`nicemice_petplacement.lua` answers "is this a polite place to stop?" Every
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
`nicemice_petPerch`. A deny-list would mean enumerating every object to avoid,
which is unbounded and grows with every mod installed. An unknown object is
treated as furniture to stay off, which fails safe. Tag the pet house and any
deliberate perch.

`sleepAction` is the acute case and it is not drift: it TELEPORTS the pet onto
its target with `mcontroller.setPosition`. Use `nicemice_petSettleAt` instead —
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

**Untested — the entire ship pet system.** Station, item, monstertype, vent, and
placement validator are all written and none has been run. They also need
sprites: the station PNG and icon, the vent PNG and icon, and a monsterpart plus
`.frames` and `.animation` for the drone. Placeholder geometry is enough to test
the pipeline.

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
  — and is speaker-side. `nicemice_villager`, `nicemice_generictenant` and every
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

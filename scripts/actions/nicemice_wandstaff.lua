require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/rect.lua"

-- Tracing helper, gated per-node so it costs nothing when debug is off.
local function trace(enabled, text)
  -- if enabled then sb.logInfo("[nicemice " .. tostring(entity.id()) .. "] " .. text) end
end

-- root.itemConfig() re-runs the item's build script on every call, and ability
-- resolution runs once per hand per tick, so results are cached against the
-- identity of the equipped descriptor.
local abilityConfigCache = {}

local function descriptorCacheKey(descriptor)
  local parameters = descriptor.parameters or {}
  return string.format("%s|%s|%s|%s",
    tostring(descriptor.name),
    tostring(parameters.seed),
    tostring(parameters.primaryAbilityType),
    tostring(parameters.altAbilityType))
end

-- Generated weapons pick their abilities in /items/buildscripts/buildweapon.lua
-- from the roll stored in the descriptor's parameters. Calling root.itemConfig()
-- with a bare item *name* re-runs that build with no parameters and re-rolls a
-- different ability out of builderConfig, so the whole descriptor has to be
-- passed through to see what the NPC is actually holding.
local function itemConfigFor(descriptor)
  if descriptor == nil or descriptor.name == nil or descriptor.name == "" then return nil end

  local key = descriptorCacheKey(descriptor)
  local itemConfig = abilityConfigCache[key]
  if itemConfig == nil then
    itemConfig = root.itemConfig(descriptor)
    if itemConfig == nil then return nil end
    abilityConfigCache[key] = itemConfig
  end

  return itemConfig
end

-- config is the built result and is authoritative; parameters only fills in
-- keys the build did not produce.
local function itemField(itemConfig, key)
  if itemConfig == nil then return nil end
  local value = itemConfig.config and itemConfig.config[key]
  if value ~= nil then return value end
  return itemConfig.parameters and itemConfig.parameters[key]
end

-- Which item a hand's fire input actually reaches.
--
-- Two-handed staves occupy the primary slot only: the engine leaves the alt
-- hand unusable and routes alt fire to the primary item's altAbility. The same
-- is true of a one-handed primary with an empty alt slot. "alt" only means a
-- separate item when a one-handed primary leaves the alt slot free to hold one
-- -- which is why reading world.entityHandItem(id, "alt") found nothing for our
-- two-handed staves and every alt-hand branch failed.
--
-- sheathed reads the stowed pair of slots instead. Out of combat that is where
-- the staff actually is: an NPC that has never drawn a weapon has its gear in
-- sheathedprimary/sheathedalt and nothing in hand, so a support behavior that
-- wants to decide whether drawing is worth it has to be able to look there.
-- Where a slot's ItemDescriptor comes from.
--
-- self.primary / self.alt / self.sheathedPrimary / self.sheathedAlt come back
-- with EMPTY parameters. That is fatal for ability resolution: with no seed and
-- no <slot>AbilityType, root.itemConfig re-runs the build script, which rolls a
-- fresh time-based seed and picks a DIFFERENT ability out of builderConfig. The
-- config we then read describes a weapon the NPC is not holding, and
-- abilityConfigCache freezes that phantom for the rest of the NPC's life.
--
-- npc.getItemSlot returns the engine's own descriptor for the slot, and unlike
-- npc.setItemSlot it also recognizes "sheathedprimary" and "sheathedalt". If
-- that descriptor carries the roll the item was actually built with, every read
-- below becomes truthful. Falls back to the self.* fields when the call is
-- unavailable, so this is never worse than the previous behavior.
local slotFallback = {
  primary = function() return self.primary end,
  alt = function() return self.alt end,
  sheathedprimary = function() return self.sheathedPrimary end,
  sheathedalt = function() return self.sheathedAlt end,
}

-- Confirmed working: npc.getItemSlot IS bound in behavior-script context and
-- returns the real descriptor. It reports nil for a genuinely empty slot (an
-- NPC that has not drawn yet), which is why the self.* fallback stays.
local function slotDescriptor(slot)
  if npc ~= nil and npc.getItemSlot ~= nil then
    local ok, result = pcall(npc.getItemSlot, slot)
    if ok and result ~= nil then return result end
  end

  local fallback = slotFallback[slot]
  return fallback and fallback() or nil
end

-- Whether a descriptor actually tells us which abilities the item rolled.
--
-- For the first moment of an NPC's life the descriptor comes back bare
-- (parameters == {}), before the engine has populated the roll. Resolving an
-- ability from a bare descriptor is worse than useless: root.itemConfig re-runs
-- the build script, which generates a FRESH time-based seed and picks a random
-- ability out of builderConfig. The result describes a weapon the NPC is not
-- holding -- which is how a staff rolling pushzone got vetted as a heal and
-- then discharged at wounded allies.
--
-- getAbilitySource in /items/buildscripts/abilities.lua consults
-- parameters.<slot>AbilityType before falling back to the random pick, so
-- either that or a seed is enough to make the rebuild deterministic and
-- truthful. With neither, the honest answer is "unknown", and the caller
-- declines to act rather than guessing.
local function descriptorIsResolvable(descriptor)
  local parameters = descriptor and descriptor.parameters
  if parameters == nil then return false end
  return parameters.seed ~= nil
    or parameters.primaryAbilityType ~= nil
    or parameters.altAbilityType ~= nil
end

-- Returns the item, and whether that item is the alt hand's OWN item rather
-- than the primary standing in for it. Callers need the second value because
-- the two cases reach different abilities -- see handAbility.
local function handItem(hand, sheathed)
  local primary = slotDescriptor(sheathed and "sheathedprimary" or "primary")
  local alt = slotDescriptor(sheathed and "sheathedalt" or "alt")

  if hand ~= "alt" then return primary, false end

  if not itemField(itemConfigFor(primary), "twoHanded") then
    if alt ~= nil and alt.name ~= nil and alt.name ~= "" then return alt, true end
  end
  return primary, false
end

-- Ability config for a hand, e.g. config.primaryAbility / config.altAbility.
--
-- Read from config ONLY. parameters.<slot>Ability is not the ability: the build
-- scripts create it as a bag of scaling factors (fireTimeFactor, baseDpsFactor,
-- energyUsageFactor) and fold them into config. Preferring parameters here
-- returns that factor bag, which has no npcIntent, so every ability silently
-- resolved as "harmful" and heal/buff staves fell through to the attack branch.
-- "alt" reaches two different abilities depending on what is in the alt hand,
-- and reading the wrong one means vetting an ability we will not fire:
--
--   two-handed primary, or an empty alt slot -> the engine routes alt fire to
--   the PRIMARY item's altAbility. Read altAbility.
--
--   one-handed primary with its own item in the alt slot -> alt fire triggers
--   that off-hand item's own primaryAbility, NOT its altAbility. Read
--   primaryAbility.
--
-- Getting this wrong is not cosmetic. Reading altAbility off an off-hand item
-- vets its SECONDARY ability while self.altFire discharges its PRIMARY one, so
-- a staff whose secondary is a heal passes the healing gate in
-- nicemice_healsupport.behavior and then fires its harmful primary at whichever
-- injured ally nicemice_resolveHealTarget just picked.
local function handAbility(hand, sheathed)
  local item, ownsAltItem = handItem(hand, sheathed)
  local itemConfig = itemConfigFor(item)
  if itemConfig == nil or itemConfig.config == nil then return nil end

  if hand == "alt" and not ownsAltItem then
    return itemConfig.config.altAbility
  end
  return itemConfig.config.primaryAbility
end

-- Reads npcIntent/npcDoNotUse off whichever ability is actually equipped in the
-- given hand slot, and the distance the ability will let us place a cast.
--
-- param hand -- "primary" or "alt"
-- param margin -- pulled off the ability's own cast range
-- param fallbackRange -- used when an ability declares no cast range
-- param sheathed -- read the stowed slots rather than what is in hand
-- param debug
-- output intent
-- output range
function nicemice_resolveAbilityIntent(args, board)
  if args.hand == nil then return false end

  local where = args.sheathed and "sheathed " or ""
  local item = handItem(args.hand, args.sheathed)

  -- Refuse to guess -- but only about the weapon actually in hand.
  --
  -- A bare descriptor makes root.itemConfig re-roll a random ability, and
  -- acting on that phantom is what made staff NPCs drop harmful zones on
  -- wounded allies. That risk is specific to CASTING, which only ever happens
  -- with a drawn weapon.
  --
  -- The sheathed slot is different on both counts. Its descriptor appears to
  -- stay bare for as long as the item is stowed -- the engine has no reason to
  -- build an item nobody is holding -- so refusing here does not fail safe, it
  -- fails permanently: nicemice_healsupport's draw block resolves the stowed
  -- intent to decide whether a holstered healing staff is worth drawing, and a
  -- medic that can never answer that question never heals at all.
  --
  -- And a wrong answer there is self-correcting. Drawing the wrong staff costs
  -- one draw; the moment it is in hand its descriptor is real, the intent
  -- resolves truthfully, and the cast branch fails on its own.
  if not args.sheathed and not descriptorIsResolvable(item) then
    trace(args.debug, where .. args.hand .. " ability on " .. tostring(item and item.name)
      .. ": descriptor carries no seed or <slot>AbilityType, so the roll is"
      .. " unknowable -- declining rather than resolving a re-rolled phantom")
    return false
  end

  local ability = handAbility(args.hand, args.sheathed)

  if ability == nil then
    trace(args.debug, where .. args.hand .. " ability: none on "
      .. tostring(item and item.name))
    return false
  end
  if ability.npcDoNotUse then
    trace(args.debug, where .. args.hand .. " ability on " .. tostring(item and item.name)
      .. " is flagged npcDoNotUse")
    return false
  end

  -- Staff abilities cap how far from the caster a cast may be placed; vanilla
  -- controlprojectile/effectzone abilities call this maxCastRange and all of
  -- them use 25 tiles. The margin covers the gap between the ability's focus
  -- position and our entity position, which is worth a couple of tiles.
  local declaredRange = ability.maxCastRange or ability.castRange
  local range = declaredRange or args.fallbackRange
  if range == nil then return false end
  range = math.max(range - (args.margin or 0), 1)

  -- An ability with no npcIntent is treated as harmful, which is how an
  -- unpatched .weaponability turns a healing staff into an attack. Say so.
  local intent = ability.npcIntent
  trace(args.debug, where .. args.hand .. " ability on " .. tostring(item and item.name)
    .. ": npcIntent=" .. tostring(intent) .. (intent == nil and " (DEFAULTING TO harmful)" or "")
    .. " castRange=" .. tostring(declaredRange) .. " -> " .. tostring(range))

  return true, {intent = intent or "harmful", range = range}
end

-- Vanilla hasMeleeSheathed/hasRangedSheathed only recognize "melee"/"ranged"
-- itemTags, so staff/wand items (tagged "weapon","staff") never match either
-- check, and swapItemSlots never fires. This fills that gap so our gear can
-- use the same vanilla swapItemSlots action.
function nicemice_hasWandStaffSheathed(args, board)
  local item = slotDescriptor("sheathedprimary")
  if item == nil or item.name == nil then return false end
  return root.itemHasTag(item.name, "staff")
      or root.itemHasTag(item.name, "wand")
end

function nicemice_hasWandStaffPrimary(args, board)
  local item = slotDescriptor("primary")
  if item == nil or item.name == nil then return false end
  return root.itemHasTag(item.name, "staff")
      or root.itemHasTag(item.name, "wand")
end

-- param first
-- param second
function nicemice_equals(args, board)
  if args.first == nil or args.second == nil then return false end
  return args.first == args.second
end

local function teamOf(entityId)
  if entityId == entity.id() then return entity.damageTeam() end
  return world.entityDamageTeam(entityId)
end

local function describeTeam(team)
  if team == nil then return "nil" end
  return tostring(team.type) .. "/" .. tostring(team.team)
end

-- Ally check on damage team number alone. Deliberately excludes players: they
-- default to team 0 with a nil damageTeamType, and the plan is for nicemice to
-- auto-heal players on a species match rather than a team one, so weighing team
-- for players here would only be cruft to unpick later.
--
-- The previous version asked world.entityCanDamage in both directions and read
-- "neither can hurt the other" as friendship, which also swallows passive,
-- ghostly and admin-mode entities -- anything invulnerable counted as an ally.
local function nicemice_isAlly(candidate)
  if candidate == entity.id() then return true end

  local mine, theirs = teamOf(entity.id()), teamOf(candidate)
  if mine == nil or theirs == nil then return false end

  -- pvp entities only ally with their own numbered pvp team
  if mine.type == "pvp" or theirs.type == "pvp" then
    return mine.type == theirs.type and mine.team == theirs.team
  end

  return mine.team == theirs.team
end

-- entity.position() sits at a humanoid's feet, so a lineTileCollision between
-- two allies standing on the same ground grazes the floor and rejects them.
-- entity.entityInSight is the engine's own eye-level check and is what vanilla
-- targeting uses.
local function nicemice_hasSightOf(candidate, required)
  if required == false then return true end
  if candidate == entity.id() then return true end
  return entity.entityInSight(candidate)
end

local function nicemice_allyCandidates(range)
  local selfPosition = entity.position()
  return selfPosition, world.entityQuery(
    vec2.sub(selfPosition, {range, range}),
    vec2.add(selfPosition, {range, range}),
    {includedTypes = {"npc", "player"}}
  )
end

-- Reports every reason a candidate was rejected rather than the first, so one
-- log line per candidate tells you which filter is actually at fault.
local function healthRatioOf(candidate)
  local health = world.entityHealth(candidate)
  if health == nil then return nil, "no health" end
  local current, max = health[1], health[2]
  if max == nil or max <= 0 then return nil, "max health " .. tostring(max) end
  return current / max, string.format("%s/%s", tostring(current), tostring(max))
end

-- Always-eligible ally scan, lowest HP% priority, includes self.
-- Not gated behind combat state -- intended to run in or out of combat.
--
-- param range
-- param requireSight
-- param debug
-- output entity
-- output position
function nicemice_resolveHealTarget(args, board)
  if args.range == nil then return false end

  local _, candidates = nicemice_allyCandidates(args.range)
  trace(args.debug, "heal scan range=" .. tostring(args.range)
    .. " team=" .. describeTeam(teamOf(entity.id()))
    .. " candidates=" .. sb.printJson(candidates))

  local best, bestRatio = nil, 1.0
  for _, candidate in ipairs(candidates) do
    local ally = nicemice_isAlly(candidate)
    local ratio, healthText = healthRatioOf(candidate)
    local sight = nicemice_hasSightOf(candidate, args.requireSight)

    trace(args.debug, "  candidate=" .. tostring(candidate)
      .. " team=" .. describeTeam(teamOf(candidate))
      .. " ally=" .. tostring(ally)
      .. " health=" .. tostring(healthText)
      .. " sight=" .. tostring(sight))

    if ally and sight and ratio ~= nil and ratio < 1.0 and ratio < bestRatio then
      best, bestRatio = candidate, ratio
    end
  end

  if best == nil then
    trace(args.debug, "  no heal target")
    return false
  end
  trace(args.debug, "  heal target=" .. tostring(best) .. " ratio=" .. tostring(bestRatio))
  return true, {entity = best, position = world.entityPosition(best)}
end

-- A buff effectzone is placed once and then lives on its own: the projectile
-- sits where it landed for its whole timeToLive, buffing anyone standing in it.
-- Recasting before then is not just wasted energy -- EffectZone:createProjectile
-- kills the previous zone before spawning the new one, so a medic that re-picks
-- the same nearest ally every cycle spends the fight tearing down and rebuilding
-- one buff on one ally and never covers anybody else.
--
-- Keyed by entity id; the value is the world.time() that ally is worth casting
-- on again. Pruned on every scan so ids of dead allies do not accumulate.
local buffCooldowns = {}

local function pruneBuffCooldowns()
  local now = world.time()
  for candidate, readyAt in pairs(buffCooldowns) do
    if readyAt <= now or not world.entityExists(candidate) then
      buffCooldowns[candidate] = nil
    end
  end
end

local function buffCooldownRemaining(candidate)
  local readyAt = buffCooldowns[candidate]
  if readyAt == nil then return 0 end
  return math.max(readyAt - world.time(), 0)
end

-- How long the zone this hand casts will stand once it is placed. The ability
-- names a projectileType and may override its timeToLive in projectileParameters.
local function zoneLifetime(ability)
  if ability == nil then return nil end

  local overrides = ability.projectileParameters or {}
  if overrides.timeToLive ~= nil then return overrides.timeToLive end
  if ability.projectileType == nil then return nil end

  -- An ability may name a projectile that does not exist; root throws rather
  -- than returning nil, and a missing lifetime is not worth killing the tree.
  local ok, projectileConfig = pcall(root.projectileConfig, ability.projectileType)
  if not ok or projectileConfig == nil then return nil end
  return projectileConfig.timeToLive
end

-- Combat-gated ally scan for buffs. Caller is responsible for gating
-- this behind an active combat target so NPCs don't buff each other
-- while idle.
--
-- Allies whose zone is still standing are skipped, so a second ally gets the
-- next cast and a lone ally means no target at all until the zone runs out.
-- nicemice_markBuffed is what puts an ally on that cooldown.
--
-- param range
-- param requireSight
-- param debug
-- output entity
-- output position
function nicemice_resolveBuffTarget(args, board)
  if args.range == nil then return false end

  pruneBuffCooldowns()

  local selfPosition, candidates = nicemice_allyCandidates(args.range)
  trace(args.debug, "buff scan range=" .. tostring(args.range)
    .. " team=" .. describeTeam(teamOf(entity.id()))
    .. " candidates=" .. sb.printJson(candidates))

  local best, bestDistance = nil, math.huge
  for _, candidate in ipairs(candidates) do
    local ally = nicemice_isAlly(candidate)
    local sight = nicemice_hasSightOf(candidate, args.requireSight)
    local candidatePosition = world.entityPosition(candidate)
    local distance = candidatePosition and world.magnitude(selfPosition, candidatePosition)
    local cooling = buffCooldownRemaining(candidate)

    trace(args.debug, "  candidate=" .. tostring(candidate)
      .. " team=" .. describeTeam(teamOf(candidate))
      .. " ally=" .. tostring(ally)
      .. " sight=" .. tostring(sight)
      .. " distance=" .. tostring(distance)
      .. " zoneStandingFor=" .. tostring(cooling))

    if candidate ~= entity.id() and ally and sight and cooling == 0
        and distance ~= nil and distance < bestDistance then
      best, bestDistance = candidate, distance
    end
  end

  if best == nil then
    trace(args.debug, "  no buff target")
    return false
  end
  trace(args.debug, "  buff target=" .. tostring(best) .. " distance=" .. tostring(bestDistance))
  return true, {entity = best, position = world.entityPosition(best)}
end

-- Record that we have just dropped a buff zone on this ally, so
-- nicemice_resolveBuffTarget passes over them until the zone expires.
--
-- Marked at cast time rather than on a successful discharge: we cannot see from
-- here whether the discharge took, and skipping an ally we may have covered is
-- cheaper than the recast loop this exists to stop -- a missed cast just comes
-- back round one interval later.
--
-- param hand -- whose ability's zone lifetime sets the interval
-- param entity
-- param interval -- fallback when the ability names no zone we can measure
-- param debug
function nicemice_markBuffed(args, board)
  if args.entity == nil then return false end

  local lifetime = zoneLifetime(handAbility(args.hand)) or args.interval or 0
  buffCooldowns[args.entity] = world.time() + lifetime
  trace(args.debug, "buffed " .. tostring(args.entity)
    .. ", skipping them for " .. tostring(lifetime) .. "s")
  return true
end

-- Runs on every tick the combat target is invalid, undoing the three pieces of
-- state a cast leaves behind when a fight ends underneath it.
--
-- 1. THE DERIVED BOARD KEYS. The ordinary "output" mapping in a .nodes entry
--    can only WRITE a value some other action computed; it cannot null one out,
--    and a returned output table cannot either -- Lua does not distinguish
--    {someKey = nil} from {}, so a nil-valued output is indistinguishable from
--    "nothing to write" and the writer skips it, leaving the stale value.
--    board:set takes the type the value is stored under; there is no
--    type-agnostic setter (see behavior.lua's board:set/board:get, which always
--    take a type first). Types below are the ones nicemice.nodes actually
--    declares for each of these keys.
--
--    This matters because nicemice_healsupport.behavior writes the SAME key
--    names (primaryAimOffset / altAimOffset / primaryTarget / ...) for ally
--    heals. Without this, a harmful branch whose nicemice_entityDistance failed
--    could hand setAimPosition a leftover near-self offset from a heal.
--
-- 2. THE FIRE LATCH. self.primaryFire/self.altFire latch true and stay true;
--    they are only cleared by something setting them false. A phase aborted
--    mid-charge by the dynamic watchdog never reaches a release, so the latch
--    is dropped here the same way nicemice_chargedFire drops it.
--
-- 3. THE AIM. npc.setAimPosition is last-value-wins with no decay, so the arm
--    stays frozen pointing at wherever the dead target was until something
--    calls it again. Re-centres one tile ahead in the facing direction.
function nicemice_clearWandstaffTargeting(args, board)
  board:set("entity", "primaryTarget", nil)
  board:set("entity", "altTarget", nil)
  board:set("vec2", "primaryAimOffset", nil)
  board:set("vec2", "altAimOffset", nil)
  board:set("string", "primaryIntent", nil)
  board:set("string", "altIntent", nil)
  board:set("number", "primaryCastRange", nil)
  board:set("number", "altCastRange", nil)

  -- Release the fire controls unconditionally.
  --
  -- Do NOT gate this on self.primaryFire/self.altFire. bmain.update() sets both
  -- to false at the TOP of every tick, before the behavior runs, and only sets
  -- them back if a fire action runs during that tick. On the tick combat ends
  -- nothing fires, so those flags are always false here and a gated release
  -- never executes -- which is exactly how a staff aborted mid-charge keeps
  -- holding its charge.
  --
  -- Calling end*Fire on a weapon that is not firing is harmless, so the
  -- unconditional call is both correct and cheap.
  self.primaryFire = false
  self.altFire = false
  npc.endPrimaryFire()
  npc.endAltFire()

  local facing = mcontroller.facingDirection()
  npc.setAimPosition(vec2.add(entity.position(), {facing, 0}))
  return true
end

-- Pass-through tracing node: drop it anywhere in a sequence to see that the
-- tree reached that point, and to dump whatever board values you route in.
-- Always succeeds, so it never changes the shape of the branch it sits in.
--
-- param text
-- param entity
-- param number
-- param position
-- param string
-- param bool
function nicemice_debugLog(args, board)
  -- local parts = {"[nicemice " .. tostring(entity.id()) .. "] " .. tostring(args.text or "")}
  -- for _, key in ipairs({"entity", "number", "position", "string", "bool"}) do
  --   if args[key] ~= nil then
  --     table.insert(parts, key .. "=" .. sb.printJson(args[key]))
  --   end
  -- end
  -- sb.logInfo(table.concat(parts, " "))
  return true
end

-- Player input naturally releases fire when the mouse button is let go; the
-- charge/charged/discharge ability state machine relies on that release edge
-- to leave "charged" (it will otherwise hold in charged{} forever). NPCs have
-- no such input edge -- primaryFire()/altFire() just latch true permanently.
-- This holds the trigger for a short duration (long enough to pass through
-- the ability's charge stance) then explicitly releases once.
--
-- param hand
function nicemice_chargedFire(args, board, nodeId, dt)
  if args.hand == nil then return false end
  local isAlt = args.hand == "alt"

  -- Staffs take their charge stance from the item, not the ability.
  local itemConfig = itemConfigFor(handItem(args.hand))
  if itemConfig == nil then return false end

  local stances = (itemConfig.config and itemConfig.config.stances)
      or (handAbility(args.hand) or {}).stances
      or {}
  local chargeTime = (stances.charge and stances.charge.duration) or 1.0

  -- hold slightly past full charge, then release once
  local holdTime = chargeTime + 0.1

  -- Charge progress is kept on the board, not in a local.
  --
  -- This action is a coroutine, and the tree can tear it down mid-loop -- a
  -- higher-priority sibling in the owning `dynamic` becoming runnable is enough.
  -- With `elapsed` as a local, every teardown restarted the count from zero, so
  -- a branch that gets interrupted even once per charge sets the fire control
  -- true forever and NEVER reaches the release below. That is a staff that
  -- charges and holds indefinitely.
  --
  -- It bites crew mice specifically because crewmember-catchup sits above both
  -- combat and healsupport in the crewmember dynamic and flickers as the
  -- recruiter moves; guards have no equivalent.
  --
  -- Same nodeId-keyed board state that behavior.lua's own cooldown and limiter
  -- decorators use. The timestamp lets a genuinely new cast start from zero
  -- instead of inheriting a half-charge from some earlier engagement.
  local progressKey = "chargedFire-" .. nodeId
  local stampKey = "chargedFireAt-" .. nodeId
  local elapsed = board:getNumber(progressKey) or 0
  local lastTick = board:getNumber(stampKey)
  if lastTick == nil or (world.time() - lastTick) > 0.5 then
    elapsed = 0
  end

  while elapsed < holdTime do
    if isAlt then self.altFire = true else self.primaryFire = true end
    elapsed = elapsed + dt
    board:setNumber(progressKey, elapsed)
    board:setNumber(stampKey, world.time())
    dt = coroutine.yield(nil, {})
  end

  board:setNumber(progressKey, 0)

  if isAlt then
    self.altFire = false
    npc.endAltFire()
  else
    self.primaryFire = false
    npc.endPrimaryFire()
  end
  return true
end

-- Pull the aim point to somewhere the ability will actually accept.
--
-- Every staff ability gates its discharge on the same targetValid():
--     world.magnitude(focusPos, aimPos) <= maxCastRange
--     and not world.lineTileCollision(mcontroller.position(), focusPos)
--     and not world.lineTileCollision(focusPos, aimPos)
-- Fail it and discharge falls straight through to cooldown -- the whole charge
-- is spent for nothing, which is what a "failed cast" looks like from outside.
--
-- focusPos is the staff's focal point (mcontroller.position() plus the hand
-- offset), which we cannot read from here; entity.position() is the closest
-- stand-in and the caller's margin absorbs the difference.
--
-- This is only wanted while charging. controlprojectile steers its projectiles
-- to activeItem.ownerAimPosition() every tick with NO range limit once they
-- exist, so clamping after discharge is what stops projectiles reaching past
-- the cast range.
--
-- minRange is the floor the walk-in is allowed to reach, and it is what stops a
-- harmful zone being dropped on the caster. The walk-in above will happily
-- collapse a 25-tile cast down to a tile away when terrain crosses the ray the
-- whole distance -- and entityInSight can pass while it does, because sight is
-- an eye-level check and lineTileCollision here runs from entity.position(), at
-- the feet. For a healing zone landing on our own feet is merely useless. For a
-- slow/push/forcecage zone it means the NPC standing in its own field, which is
-- what "the guard keeps slowing itself" looks like.
--
-- So: when a caller sets minRange we refuse the cast outright rather than place
-- it too close, returning false so the branch fails and nothing discharges.
-- Callers that leave minRange unset (heal, buff) keep the old always-succeed
-- behaviour -- landing a heal at your own feet is a legitimate self-heal.
--
-- param range
-- param minRange -- nearest we will place a cast to ourselves; 0/unset to allow any
function nicemice_clampAimPosition(args, board)
  if args.range == nil then return true end

  local minRange = args.minRange or 0
  local selfPosition = entity.position()
  -- world.distance is wrap-safe; plain subtraction is not, and staff casts
  -- happen at ranges where a world seam between caster and target matters.
  local delta = world.distance(npc.aimPosition(), selfPosition)
  local distance = vec2.mag(delta)
  if distance == 0 then return minRange == 0 end

  local heading = vec2.norm(delta)
  distance = math.min(distance, args.range)

  -- Walk the aim in until the line from us to it is clear. Without this an
  -- otherwise in-range cast is still refused whenever terrain crosses the ray.
  local floor = math.max(minRange, 1)
  local aimPosition = vec2.add(selfPosition, vec2.mul(heading, distance))
  local step = distance / 8
  while distance > floor and world.lineTileCollision(selfPosition, aimPosition) do
    distance = distance - step
    aimPosition = vec2.add(selfPosition, vec2.mul(heading, distance))
  end

  -- Ran out of room: every point on the ray we are allowed to use is walled off.
  if minRange > 0 and (distance < minRange
      or world.lineTileCollision(selfPosition, aimPosition)) then
    return false
  end

  npc.setAimPosition(aimPosition)
  return true
end

-----------------------------------------------------------
-- STANDOFF POSITIONING
-----------------------------------------------------------

-- The coordinator hands every ranged attacker a movePosition, but it picks that
-- position by straight-line distance from the NPC:
--
--   table.sort(rangedPositions, function(a,b)
--     return world.magnitude(a, npcPosition) < world.magnitude(b, npcPosition)
--   end)
--
-- Straight-line distance is measured THROUGH the target, so when the near-side
-- candidates get eliminated -- no standable ground, no line of sight, or a
-- squadmate already claimed the slot within 2 tiles -- the nearest surviving
-- candidate is on the far side, and the NPC walks through a large monster to
-- reach it.
--
-- Fixing this in the coordinator is unreliable: /scripts/behavior/bgroup.lua
-- picks a coordinator by compareGoals alone (goalType and goal, never groupId
-- or behavior), so a mod coordinator only runs when our NPC happens to spawn it
-- first. Doing it NPC-side always runs.
--
-- Ports validAttackPosition/findGroundAttackPosition out of
-- /stagehands/coordinator/npccombat.lua; every call they make is available in
-- NPC context, with mcontroller.boundBox() standing in for self.npcBounds.
local function standableAttackPosition(position, bounds)
  local liquid = world.liquidAt(rect.translate(bounds, position))
  if liquid and liquid[2] >= 0.1 then return false end

  local groundRegion = {
    position[1] + bounds[1], position[2] + bounds[2] - 1,
    position[1] + bounds[3], position[2] + bounds[2]
  }
  return not world.rectTileCollision(rect.translate(bounds, position), {"Null", "Block"})
     and world.rectTileCollision(groundRegion, {"Null", "Block", "Dynamic", "Platform"})
end

-- Searches a vertical column for standable ground with clear line of sight to
-- the target, preferring higher ground first the way the vanilla helper does.
local function groundPositionInColumn(x, targetPosition, searchHeight, bounds)
  local baseY = math.ceil(targetPosition[2]) - (bounds[2] % 1)
  for y = searchHeight, -searchHeight, -1 do
    local candidate = {x, baseY + y}
    if standableAttackPosition(candidate, bounds)
       and not world.lineTileCollision(candidate, targetPosition) then
      return candidate
    end
  end
end

-- Keeps a standoff position on the side of the target the NPC is already on.
--
-- Passes the coordinator's suggestion straight through when it is already on
-- our side, so normal allocation (including its slot deduplication) is
-- untouched. Only when the suggestion is across the target does this search our
-- own side, preferring the standoff distance closest to where the NPC already
-- is so it does not sprint the full width of the band. Falls back to the
-- original suggestion when our side has nothing valid, so an NPC pinned against
-- a wall still repositions rather than freezing in melee range.
--
-- param entity   -- the target
-- param position -- the coordinator's suggested movePosition
-- param minRange
-- param maxRange
-- output position
function nicemice_nearSidePosition(args, board)
  if args.entity == nil or not world.entityExists(args.entity) then return false end
  local targetPosition = world.entityPosition(args.entity)
  if targetPosition == nil then return false end

  local selfPosition = mcontroller.position()
  local toTarget = world.distance(selfPosition, targetPosition)
  local side = util.toDirection(toTarget[1])
  if side == 0 then side = 1 end

  if args.position ~= nil then
    local suggestedSide = util.toDirection(world.distance(args.position, targetPosition)[1])
    if suggestedSide == 0 or suggestedSide == side then
      return true, {position = args.position}
    end
  end

  local minRange = args.minRange or 0
  local maxRange = args.maxRange or 0
  if maxRange <= minRange then return false end

  -- Try standoff distances nearest our current one first.
  local currentRange = math.abs(toTarget[1])
  local ranges = {}
  for range = math.floor(minRange), math.ceil(maxRange) do
    table.insert(ranges, math.max(minRange, math.min(maxRange, range)))
  end
  table.sort(ranges, function(a, b)
    return math.abs(a - currentRange) < math.abs(b - currentRange)
  end)

  local bounds = mcontroller.boundBox()
  for _, range in ipairs(ranges) do
    local candidate = groundPositionInColumn(targetPosition[1] + side * range,
      targetPosition, range, bounds)
    if candidate then
      return true, {position = candidate}
    end
  end

  if args.position ~= nil then
    return true, {position = args.position}
  end
  return false
end

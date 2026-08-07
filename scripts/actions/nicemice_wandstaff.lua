require "/scripts/vec2.lua"
require "/scripts/util.lua"

-- Tracing helper, gated per-node so it costs nothing when debug is off.
local function trace(enabled, text)
  if enabled then sb.logInfo("[nicemice " .. tostring(entity.id()) .. "] " .. text) end
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
local function handItem(hand)
  local primary = self.primary
  if hand ~= "alt" then return primary end

  if not itemField(itemConfigFor(primary), "twoHanded") then
    local alt = self.alt
    if alt ~= nil and alt.name ~= nil and alt.name ~= "" then return alt end
  end
  return primary
end

-- Ability config for a hand, e.g. config.primaryAbility / config.altAbility.
--
-- Read from config ONLY. parameters.<slot>Ability is not the ability: the build
-- scripts create it as a bag of scaling factors (fireTimeFactor, baseDpsFactor,
-- energyUsageFactor) and fold them into config. Preferring parameters here
-- returns that factor bag, which has no npcIntent, so every ability silently
-- resolved as "harmful" and heal/buff staves fell through to the attack branch.
local function handAbility(hand)
  local itemConfig = itemConfigFor(handItem(hand))
  if itemConfig == nil or itemConfig.config == nil then return nil end
  return itemConfig.config[(hand == "alt") and "altAbility" or "primaryAbility"]
end

-- Reads npcIntent/npcDoNotUse off whichever ability is actually equipped in the
-- given hand slot, and the distance the ability will let us place a cast.
--
-- param hand -- "primary" or "alt"
-- param margin -- pulled off the ability's own cast range
-- param fallbackRange -- used when an ability declares no cast range
-- param debug
-- output intent
-- output range
function nicemice_resolveAbilityIntent(args, board)
  if args.hand == nil then return false end

  local item = handItem(args.hand)
  local ability = handAbility(args.hand)

  if ability == nil then
    trace(args.debug, args.hand .. " ability: none on "
      .. tostring(item and item.name))
    return false
  end
  if ability.npcDoNotUse then
    trace(args.debug, args.hand .. " ability on " .. tostring(item and item.name)
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
  trace(args.debug, args.hand .. " ability on " .. tostring(item and item.name)
    .. ": npcIntent=" .. tostring(intent) .. (intent == nil and " (DEFAULTING TO harmful)" or "")
    .. " castRange=" .. tostring(declaredRange) .. " -> " .. tostring(range))

  return true, {intent = intent or "harmful", range = range}
end

-- Vanilla hasMeleeSheathed/hasRangedSheathed only recognize "melee"/"ranged"
-- itemTags, so staff/wand items (tagged "weapon","staff") never match either
-- check, and swapItemSlots never fires. This fills that gap so our gear can
-- use the same vanilla swapItemSlots action.
function nicemice_hasWandStaffSheathed(args, board)
  if self.sheathedPrimary == nil then return false end
  return root.itemHasTag(self.sheathedPrimary.name, "staff")
      or root.itemHasTag(self.sheathedPrimary.name, "wand")
end

function nicemice_hasWandStaffPrimary(args, board)
  if self.primary == nil then return false end
  return root.itemHasTag(self.primary.name, "staff")
      or root.itemHasTag(self.primary.name, "wand")
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

-- Combat-gated ally scan for buffs. Caller is responsible for gating
-- this behind an active combat target so NPCs don't buff each other
-- while idle.
--
-- param range
-- param requireSight
-- param debug
-- output entity
-- output position
function nicemice_resolveBuffTarget(args, board)
  if args.range == nil then return false end

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

    trace(args.debug, "  candidate=" .. tostring(candidate)
      .. " team=" .. describeTeam(teamOf(candidate))
      .. " ally=" .. tostring(ally)
      .. " sight=" .. tostring(sight)
      .. " distance=" .. tostring(distance))

    if candidate ~= entity.id() and ally and sight and distance ~= nil and distance < bestDistance then
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
  local parts = {"[nicemice " .. tostring(entity.id()) .. "] " .. tostring(args.text or "")}
  for _, key in ipairs({"entity", "number", "position", "string", "bool"}) do
    if args[key] ~= nil then
      table.insert(parts, key .. "=" .. sb.printJson(args[key]))
    end
  end
  sb.logInfo(table.concat(parts, " "))
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
  local elapsed = 0
  while elapsed < holdTime do
    if isAlt then self.altFire = true else self.primaryFire = true end
    elapsed = elapsed + dt
    dt = coroutine.yield(nil, {})
  end

  if isAlt then
    self.altFire = false
    npc.endAltFire()
  else
    self.primaryFire = false
    npc.endPrimaryFire()
  end
  return true
end

-- param range
function nicemice_clampAimPosition(args, board)
  if args.range == nil then return true end

  local aimPosition = npc.aimPosition()
  local selfPosition = entity.position()
  -- world.distance is wrap-safe; plain subtraction is not, and staff casts
  -- happen at ranges where a world seam between caster and target matters.
  local delta = world.distance(aimPosition, selfPosition)
  if vec2.mag(delta) > args.range then
    npc.setAimPosition(vec2.add(selfPosition, vec2.mul(vec2.norm(delta), args.range)))
  end

  return true
end

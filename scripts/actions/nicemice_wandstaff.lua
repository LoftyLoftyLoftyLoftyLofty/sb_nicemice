require "/scripts/vec2.lua"
require "/scripts/util.lua"

-- Reads npcIntent/npcDoNotUse off whichever ability is actually equipped
-- in the given hand slot. Path confirmed live via root.itemConfig dump:
-- config.primaryAbility.npcIntent / config.altAbility.npcIntent
--
-- param hand -- "primary" or "alt"
-- output intent
function nicemice_resolveAbilityIntent(args, board)
  if args.hand == nil then return false end

  local itemName = world.entityHandItem(entity.id(), args.hand == "alt" and "alt" or "primary")
  if itemName == nil or itemName == "" then return false end

  local itemConfig = root.itemConfig(itemName)
  if itemConfig == nil or itemConfig.config == nil then return false end

  local abilityKey = (args.hand == "alt") and "altAbility" or "primaryAbility"
  local ability = itemConfig.config[abilityKey]
  if ability == nil then return false end

  if ability.npcDoNotUse then return false end

  return true, {intent = ability.npcIntent or "harmful"}
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

-- Ally check built entirely on world.entityCanDamage, per the confirmed
-- team model (damageTeamType drives player<->npc hostility; damageTeam
-- numeric value is not reliably indicative on its own).
local function nicemice_isAlly(candidate)
  local selfId = entity.id()
  if candidate == selfId then return true end
  if world.entityCanDamage(selfId, candidate) then return false end
  if world.entityCanDamage(candidate, selfId) then return false end
  return true
end

-- Always-eligible ally scan, lowest HP% priority, includes self.
-- Not gated behind combat state -- intended to run in or out of combat.
--
-- param range
-- output entity
-- output position
function nicemice_resolveHealTarget(args, board)

  sb.logInfo("resolving heal targets...")
  if args.range == nil then return false end

  sb.logInfo("range = " .. sb.printJson(args.range))
  
  local selfPosition = entity.position()
  local candidates = world.entityQuery(
    vec2.sub(selfPosition, {args.range, args.range}),
    vec2.add(selfPosition, {args.range, args.range}),
    {includedTypes = {"npc", "player"}}
  )

  local best, bestRatio = nil, 1.0
  for _, candidate in ipairs(candidates) do
    if nicemice_isAlly(candidate) then
      local health = world.entityHealth(candidate)
      if health ~= nil then
        local current, max = health[1], health[2]
        if max ~= nil and max > 0 then
          local ratio = current / max
          if ratio < 1.0 and ratio < bestRatio then
            local candidatePosition = world.entityPosition(candidate)
            if candidatePosition ~= nil and not world.lineTileCollision(selfPosition, candidatePosition) then
              best, bestRatio = candidate, ratio
            end
          end
        end
      end
    end
  end

  sb.logInfo("chosen heal target: " .. sb.printJson(best))

  if best == nil then return false end
  return true, {entity = best, position = world.entityPosition(best)}
end

-- Combat-gated ally scan for buffs. Caller is responsible for gating
-- this behind an active combat target so NPCs don't buff each other
-- while idle.
--
-- param range
-- output entity
-- output position
function nicemice_resolveBuffTarget(args, board)
  if args.range == nil then return false end

  local selfPosition = entity.position()
  local candidates = world.entityQuery(
    vec2.sub(selfPosition, {args.range, args.range}),
    vec2.add(selfPosition, {args.range, args.range}),
    {includedTypes = {"npc", "player"}}
  )

  local best, bestDistance = nil, math.huge
  for _, candidate in ipairs(candidates) do
    if candidate ~= entity.id() and nicemice_isAlly(candidate) then
      local candidatePosition = world.entityPosition(candidate)
      if candidatePosition ~= nil and not world.lineTileCollision(selfPosition, candidatePosition) then
        local distance = world.magnitude(selfPosition, candidatePosition)
        if distance < bestDistance then
          best, bestDistance = candidate, distance
        end
      end
    end
  end

  if best == nil then return false end
  return true, {entity = best, position = world.entityPosition(best)}
end

-- Player input naturally releases fire when the mouse button is let go; the
-- charge/charged/discharge ability state machine relies on that release edge
-- to leave "charged" (it will otherwise hold in charged{} forever). NPCs have
-- no such input edge -- primaryFire()/altFire() just latch true permanently.
-- This holds the trigger for a short duration (long enough to pass through
-- the ability's charge stance) then explicitly releases once.
function nicemice_chargedFire(args, board, nodeId, dt)
  if args.hand == nil then return false end
  local isAlt = args.hand == "alt"

  local itemName = world.entityHandItem(entity.id(), isAlt and "alt" or "primary")
  if itemName == nil or itemName == "" then return false end

  local itemConfig = root.itemConfig(itemName)
  local abilityKey = isAlt and "altAbility" or "primaryAbility"
  local ability = itemConfig and itemConfig.config and itemConfig.config[abilityKey]
  local chargeTime = (ability and ability.stances and ability.stances.charge and ability.stances.charge.duration) or 1.0

  -- hold slightly past full charge, then release once
  local holdTime = chargeTime + 0.1
  local elapsed = 0
  while elapsed < holdTime do
    if isAlt then altFire() else primaryFire() end
    elapsed = elapsed + dt
    dt = coroutine.yield(nil, {})
  end

  if isAlt then npc.endAltFire() else endPrimaryFire() end
  return true
end

-- param range
function nicemice_clampAimPosition(args, board)
  -- sb.logInfo("clamping: " .. sb.printJson(args.range))
  if args.range == nil then return true end

  local aimPos = npc.aimPosition()
  local myPos = entity.position()
  local dist = vec2.mag(world.distance(myPos, aimPos))
  if dist > args.range then
	local delta = vec2.sub(aimPos, myPos)
	delta = vec2.norm(delta)
	delta = vec2.mul(delta, args.range)
	npc.setAimPosition( vec2.add( myPos, delta ) )
  end
  
  return true
end
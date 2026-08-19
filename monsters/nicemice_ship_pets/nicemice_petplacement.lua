require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/rect.lua"
require "/scripts/pathutil.lua"

--  M.A.U.S. UTILITY UNIT -- PLACEMENT VALIDATION
--
--  "Is this a polite place to stop?"
--
--  Every resting action needs this: sleeping, idling, and picking somewhere to
--  stand while waiting. A pet that settles in front of the captain's chair, a
--  storage crate, or a light switch is the single most complained-about thing
--  about vanilla ship pets, and it is not drift -- sleepAction actively
--  TELEPORTS the pet onto its sleep target with mcontroller.setPosition. Any
--  validation that only gates approach will miss the acute case.
--
--  WHY OCCUPANCY AND NOT INTERACTIVITY
--
--  The obvious approach is "do not stand in front of interactable objects", and
--  it does not work. Interactivity is a RUNTIME property: /objects/wired/light/
--  light.lua calls object.setInteractive(config.getParameter("interactive",
--  true)), so a light switch is interactive by default with nothing in its
--  config saying so. Any predicate built out of config parameters
--  (interactAction, slotCount, sitPosition...) will have holes, and the holes
--  will look arbitrary to a player.
--
--  So this checks OCCUPANCY instead: does the pet's footprint overlap the tiles
--  an object occupies? No guessing about intent, no per-type special cases, and
--  it covers objects from mods that do not exist yet.
--
--  Slightly over-broad -- a pet will also decline to nap in front of a purely
--  decorative wall panel. That is a much better failure mode than napping in
--  front of the one thing the player needed.
--
--  ALLOW-LIST, NOT DENY-LIST
--
--  Objects are off-limits unless they say otherwise, via the perch tag below.
--  A deny-list would mean enumerating every object a pet should avoid, which is
--  unbounded and grows with every mod installed. This way an unknown object is
--  treated as furniture to stay off, which fails safe. Tag the pet house and any
--  deliberate perch and nothing else needs to care.

--  An object carrying this in its itemTags may be rested on.
local PERCH_TAG = "nicemice_petPerch"

--  Avoidance markers, shared with the npc avoidance system so a ship author
--  marks a spot once and every entity in the mod honours it. Used for things
--  that are not objects at all -- an airlock beam, a ledge, a doorway.
local AVOID_TAGS = {
  ["avoidMe"] = true,
  ["avoidMe-goLeft"] = true,
  ["avoidMe-goRight"] = true
}

--  How far from a marker counts as too close to settle. Deliberately smaller
--  than the npc avoidance scan radius: an npc walking away needs room, a pet
--  choosing where to sit only needs to not be on top of it.
local AVOID_CLEARANCE = 4

--  How far from the player to stay while resting. The complaint is not that the
--  pet is nearby, it is that the pet is underfoot.
local PLAYER_CLEARANCE = 3

--------------------------------------------------------------------------------

local function tagsOf(entityId)
  local ok, tags = pcall(world.getObjectParameter, entityId, "itemTags")
  if ok then return tags end
  return nil
end

local function hasTag(entityId, tag)
  local tags = tagsOf(entityId)
  if tags == nil then return false end
  for _, t in ipairs(tags) do
    if t == tag then return true end
  end
  return false
end

local function isPerch(entityId)
  return hasTag(entityId, PERCH_TAG)
end

local function isAvoidMarker(entityId)
  local tags = tagsOf(entityId)
  if tags == nil then return false end
  for _, t in ipairs(tags) do
    if AVOID_TAGS[t] then return true end
  end
  return false
end

--  Rect covering the pet's body at a candidate position.
local function footprintAt(position)
  local bounds = mcontroller.boundBox()
  return rect.translate(bounds, position)
end

--  Does the footprint overlap any tile this object occupies?
--
--  world.objectSpaces reports tile coordinates relative to the object, so they
--  are offset by its position before comparing.
local function overlapsObject(footprint, objectId)
  local ok, spaces = pcall(world.objectSpaces, objectId)
  if not ok or spaces == nil then return false end

  local origin = world.entityPosition(objectId)
  if origin == nil then return false end

  for _, space in ipairs(spaces) do
    local tile = {
      math.floor(origin[1]) + space[1],
      math.floor(origin[2]) + space[2]
    }
    --  A tile occupies [tile, tile+1). Overlap on both axes means collision.
    if footprint[1] < tile[1] + 1 and footprint[3] > tile[1]
       and footprint[2] < tile[2] + 1 and footprint[4] > tile[2] then
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------------
--  PUBLIC
--------------------------------------------------------------------------------

--  Is `position` somewhere the unit may come to rest?
--
--  options (all optional):
--    ignoreEntityId -- an object to disregard, e.g. the pet house it is
--                      deliberately climbing into
--    ignorePlayers  -- skip the player-clearance test
--    searchRadius   -- how far to look for obstructions (default 8)
--
--  Returns true, or false plus a short reason string. The reason exists so a
--  caller can log WHY a pet refuses to settle somewhere; a pet standing around
--  looking indecisive is otherwise very hard to debug.
function nicemice_petCanRestAt(position, options)
  options = options or {}
  if position == nil then return false, "no position" end

  --  Must be somewhere the pet could actually stand.
  if not validStandingPosition(position) then
    return false, "not standable"
  end

  local footprint = footprintAt(position)
  local radius = options.searchRadius or 8

  local nearby = world.entityQuery(position, radius, {
    includedTypes = { "object" },
    withoutEntityId = entity.id()
  })

  for _, objectId in ipairs(nearby or {}) do
    if objectId ~= options.ignoreEntityId then
      if isAvoidMarker(objectId) then
        --  Markers are a keep-clear radius rather than a footprint: the point
        --  of a marker is the area around it, not the tile it sits on.
        local markerPosition = world.entityPosition(objectId)
        if markerPosition and world.magnitude(markerPosition, position) < AVOID_CLEARANCE then
          return false, "inside an avoidance marker"
        end
      elseif not isPerch(objectId) then
        if overlapsObject(footprint, objectId) then
          return false, "on top of an object"
        end
      end
    end
  end

  --  Do not settle underfoot. Follow can bring the pet close; resting there is
  --  what makes it a nuisance.
  if not options.ignorePlayers then
    local players = world.entityQuery(position, PLAYER_CLEARANCE, {
      includedTypes = { "player" }
    })
    if players and #players > 0 then
      return false, "too close to a player"
    end
  end

  return true
end

--  Nearest acceptable resting spot to `position`, or nil.
--
--  Searches outward in whole tiles so the result is as close as possible to
--  wherever the pet wanted to be, rather than the first spot that happens to
--  pass. Returns the candidate position, or nil if nothing within maxOffset
--  qualifies -- in which case the caller should keep doing whatever it was
--  doing rather than settling somewhere rude.
function nicemice_petFindRestPosition(position, maxOffset, options)
  maxOffset = maxOffset or 6

  if nicemice_petCanRestAt(position, options) then
    return position
  end

  for offset = 1, maxOffset do
    for _, direction in ipairs({1, -1}) do
      local candidate = findGroundPosition(
        {position[1] + direction * offset, position[2]}, -4, 4)
      if candidate and nicemice_petCanRestAt(candidate, options) then
        return candidate
      end
    end
  end

  return nil
end

--  Convenience for the acute case: sleepAction teleports onto its target with
--  mcontroller.setPosition. Call this instead, so a pet cannot end up parked
--  inside a doorway because that is where its bed happened to be.
--
--  Returns true if the unit was placed.
function nicemice_petSettleAt(position, options)
  local resting = nicemice_petFindRestPosition(position, 6, options)
  if resting == nil then return false end

  local bounds = mcontroller.boundBox()
  mcontroller.setPosition({resting[1], resting[2] - bounds[2]})
  return true
end

require "/scripts/util.lua"
require "/scripts/messageutil.lua"

--  M.A.U.S. PETPORT
--
--  A one-slot container. Socket a nicemice_ship_pet item and the unit it
--  describes wakes up nearby; take the item out and the unit goes back to sleep,
--  its state written into the item.
--
--  WHY NOT THE VANILLA PET TETHER PIPELINE
--
--  /scripts/companions/petspawner.lua exists to serve capture pods, and almost
--  all of its complexity is pod-shaped: pods holding several pets at once (a
--  hemogoblin splits when it dies), collar merging, associate/disassociate
--  handlers, and a JSON round-trip that keeps a pod item in sync so a pet can be
--  carried between worlds.
--
--  None of that applies to a dedicated item. One item is one pet, there are no
--  collars, and the definition lives in the item's own parameters. What is worth
--  keeping from that file is the spine, reproduced below:
--
--    * assembling spawn parameters and handing the monster its initialStatus /
--      initialStorage, which is how a pet keeps learned state across a respawn
--    * a status heartbeat, so the petport notices when its pet dies or unloads
--    * collision-aware spawn placement
--
--  ANCHORING
--
--  Vanilla's groundPet.lua expects an anchor object and calls setAnchor on
--  itself, which calls back into hasPet/setPet here. It kills the pet outright
--  if it cannot find one -- and note that findAnchor only SEARCHES when
--  storage.anchorPosition already exists, so it is a recovery path, not a
--  discovery path. A console-spawned unit can never survive; only this object
--  can spawn a viable one, because spawnPet's setAnchor call is what writes
--  storage.anchorPosition in the first place.
--
--  So this object implements the same contract the SAIL techstation does --
--  hasPet, setPet -- and the monstertype's anchorName points at this object.
--  That keeps vanilla's pet scripts usable unmodified while the behavior work
--  happens separately.

local STATUS_INTERVAL = 2.0
local RESPAWN_GRACE = 1.0

--  Periodic flush of drifting state into the socketed item.
--
--  Durable changes (a new known player, a new food liking, the seed) write
--  immediately. Resource drift does not, because groundPet.lua re-calls
--  setAnchor -- and therefore setPet -- once per second, and writing the item
--  back on every one of those is a container swap per second, forever,
--  replicated to every client.
--
--  THIS TIMER IS NOT A SAFETY NET. It is the actual persistence mechanism for
--  drifting values, because the final save on unsocket DOES NOT WORK and
--  cannot be made to: writeBackToItem needs the item to still be in the slot,
--  and by the time the petport notices the removal the item is already in the
--  player's inventory, out of reach. Confirmed in testing -- nicemice_petStore
--  returns fresher values than the item ends up holding.
--
--  So this interval is exactly how much resource drift an unsocket discards.
--  Only petResources are affected; durable state is written on change and
--  world unload IS covered, since uninit runs while the item is still socketed.
local WRITE_INTERVAL = 10.0

--  Instrumentation, dormant by default (see handoff §4). Flip to true to trace
--  the item <-> pet state round trip in starbound.log.
local DEBUG = true

local function trace(label, value)
  if not DEBUG then return end
  if value == nil then
    sb.logInfo("[petport] %s: nil", label)
  elseif type(value) == "table" then
    sb.logInfo("[petport] %s: %s", label, sb.printJson(value))
  else
    sb.logInfo("[petport] %s: %s", label, tostring(value))
  end
end

function init()
  self.petId = nil
  self.petUniqueId = nil
  self.petData = nil
  self.statusTimer = 0
  self.spawnTimer = 0
  self.spawning = false
  self.dirty = false
  self.writeTimer = WRITE_INTERVAL
  self.firstUpdate = true

  --  Sent by the pet when it dies or is recalled, so the petport can write the
  --  final state back into the item rather than losing it.
  message.setHandler("nicemice_petStatus", simpleHandler(function(status, storage)
    if self.petData then
      self.petData.status = status or self.petData.status
      self.petData.storage = storage or self.petData.storage
      self.dirty = true
      trace("petStatus message -> storage", self.petData.storage)
    end
  end))

  object.setInteractive(true)
end

function uninit()
  --  Petport unloading or being broken: put the unit back in its item so
  --  nothing is lost. This is why a unit does not survive the player beaming
  --  away -- the item carries the state, not the monster.
  saveAndDespawn()
end

--------------------------------------------------------------------------------
--  ANCHOR CONTRACT (see groundPet.lua setAnchor / findAnchor)
--------------------------------------------------------------------------------

function hasPet()
  return self.petId ~= nil and world.entityExists(self.petId)
end

function setPet(entityId, params)
  if self.petId ~= nil and self.petId ~= entityId then
    return false
  end
  self.petId = entityId

  --  groundPet.lua pushes its own state here ONCE PER SECOND, via updateAnchor
  --  re-calling setAnchor. So this runs constantly and must not mark the item
  --  dirty on its own -- see WRITE_INTERVAL above.
  --
  --  Durable state (known players, food likings, seed) changes rarely and is
  --  worth an immediate write. Resource levels drift every tick and are not.
  if params and self.petData then
    self.petData.storage = self.petData.storage or {}

    --  Seed is stable for the life of the monster, so it is safe to take at any
    --  time -- including from the echo below.
    if params.seed and params.seed ~= self.petData.seed then
      self.petData.seed = params.seed
      self.dirty = true
    end

    --  IGNORE THE FIRST CALLBACK AFTER A SPAWN.
    --
    --  spawnPet calls setAnchor immediately, and groundPet answers by pushing
    --  its state straight back here -- state it has only just initialized. That
    --  is an echo, not news. Accepting it overwrites the item with whatever the
    --  unit came up at, so a restore that silently failed would also DESTROY
    --  the saved values it failed to restore. Observed exactly that: defaults
    --  written into the item 23ms after spawn.
    if self.spawning then
      self.spawning = false
      return true
    end

    if params.foodLikings and not compare(params.foodLikings, self.petData.storage.foodLikings) then
      self.petData.storage.foodLikings = params.foodLikings
      self.dirty = true
    end

    if params.knownPlayers and not compare(params.knownPlayers, self.petData.storage.knownPlayers) then
      self.petData.storage.knownPlayers = params.knownPlayers
      self.dirty = true
    end

    --  Kept current in memory, flushed on the slow timer or at despawn.
    self.petData.storage.petResources = params.petResources or self.petData.storage.petResources
  end
  return true
end

--------------------------------------------------------------------------------
--  ITEM <-> PET
--------------------------------------------------------------------------------

--  The socketed item, or nil. Slot 0 because slotCount is 1.
local function socketedItem()
  local item = world.containerItemAt(entity.id(), 0)
  if item == nil or item.name == nil then return nil end
  return item
end

--  Pet definition from the item, merging the item's own instance parameters
--  over the base config. A found item may carry only monsterType; a lived-in
--  one carries status and storage too.
local function petDataFrom(item)
  local base = root.itemConfig(item)
  local data = {}
  if base and base.config and base.config.petData then
    util.mergeTable(data, copy(base.config.petData))
  end
  if item.parameters and item.parameters.petData then
    util.mergeTable(data, copy(item.parameters.petData))
  end
  if data.monsterType == nil then return nil end

  trace("read from item", data)
  return data
end

function spawnPet()
  if self.petData == nil or self.petData.monsterType == nil then return end
  if self.petId ~= nil and world.entityExists(self.petId) then return end

  local spawnPosition = object.toAbsolutePosition(config.getParameter("petSpawnOffset", {0, 2}))

  --  THESE ARE TOP-LEVEL PARAMETERS, NOT A scriptConfig SUB-TABLE.
  --
  --  petspawner.lua looks like it nests them, but only looks like it:
  --  Pet:_scriptConfig(parameters) returns `parameters` unchanged, so the local
  --  named scriptConfig IS the parameters table. Everything assigned to it
  --  lands at the top level of what reaches world.spawnMonster. Nested under a
  --  literal scriptConfig key, none of it is reachable via config.getParameter
  --  and the engine never sees initialStatus / initialStorage at all.
  local parameters = {
    --  Ship pets belong to the ship, not the world's threat level.
    level = math.max(world.threatLevel(), world.getProperty("ship.level") or 0, 1),

    --  Persistent so the unit is not garbage collected while the player is
    --  elsewhere on the ship; the petport owns its lifetime instead.
    persistent = true,

    --  Never yanked around by relocation logic meant for wild creatures.
    relocatable = false,

    damageTeamType = "ghostly",

    --  How the pet reports home. It messages the petport rather than the
    --  petport polling it, which keeps the item current even if the pet dies
    --  while the player is watching something else.
    stationUniqueId = stationUniqueId(),

    --  Resume where it left off.
    --
    --  initialStatus / initialStorage are kept because vanilla sets them, but
    --  OBSERVED NOT TO WORK for seeding a monster's storage table: a unit
    --  spawned with a populated initialStorage still came up with
    --  config-default petResources and an empty knownPlayers. Whatever consumes
    --  these, it is not what groundPet.lua reads on init.
    initialStatus = copy(self.petData.status) or {},
    initialStorage = copy(self.petData.storage) or {},

    petName = self.petData.petName
  }

  --  THE ROUTE THAT ACTUALLY RESTORES STATE.
  --
  --  groundPet.lua's init reads
  --
  --    storage.petResources = storage.petResources or config.getParameter("petResources")
  --    storage.knownPlayers = storage.knownPlayers or config.getParameter("knownPlayers", {})
  --    storage.foodLikings  = storage.foodLikings  or config.getParameter("foodLikings", {})
  --
  --  and spawn parameters ARE config parameters -- that path is proven, it is
  --  how level, persistent and anchorName already arrive. So saved values are
  --  passed as parameters and picked up by the fallback branch, since a freshly
  --  spawned monster's storage is empty.
  --
  --  nil entries simply do not appear in the table, leaving the monstertype's
  --  own defaults in play for a brand new unit.
  local saved = self.petData.storage or {}
  parameters.petResources = copy(saved.petResources)
  parameters.knownPlayers = copy(saved.knownPlayers)
  parameters.foodLikings = copy(saved.foodLikings)

  --  Seed the anchor position so the unit can self-anchor through vanilla's own
  --  recovery path if the setAnchor call below is ever missed. Belt and braces:
  --  the direct call has not failed in testing, but its success depends on the
  --  monster's script having initialized by the time spawnMonster returns.
  parameters.initialStorage.anchorPosition = entity.position()

  --  VERIFY: whether world.spawnMonster honours a seed parameter. If it does,
  --  this pins the monsterpart variant across respawns; if not, it is inert and
  --  the variant needs pinning some other way.
  if self.petData.seed then
    parameters.seed = self.petData.seed
  end

  trace("spawning with initialStorage", parameters.initialStorage)

  self.petId = world.spawnMonster(self.petData.monsterType, spawnPosition, parameters)
  if self.petId then
    self.spawning = true
    self.statusTimer = STATUS_INTERVAL

    --  Hand the pet its anchor, exactly as techstation.lua does. groundPet.lua
    --  calls back into setPet from here.
    world.callScriptedEntity(self.petId, "setAnchor", entity.id())
  else
    trace("spawnMonster returned nil for type", self.petData.monsterType)
  end
end

function saveAndDespawn()
  if self.petId and world.entityExists(self.petId) then
    --  Ask for final state before removing it. Best effort: if the pet is
    --  already gone the item simply keeps the last state we heard about.
    local ok, state = pcall(world.callScriptedEntity, self.petId, "nicemice_petStore")
    trace("petStore returned", ok and state or nil)

    if ok and state and self.petData then
      self.petData.status = state.status or self.petData.status
      self.petData.storage = state.storage or self.petData.storage
    end

    --  Defined in nicemice_ship_pet_contract.lua on the monster side. Note a
    --  bare callScriptedEntity to an UNDEFINED function returns nil silently --
    --  it does not raise -- which is how the socket-cycle unit leak went
    --  unnoticed before that script existed.
    world.callScriptedEntity(self.petId, "nicemice_petDespawn")
  end
  --  No-op when the unit is being put away because the ITEM was removed -- it
  --  has already left the container. Still worth calling: this path also runs
  --  from uninit on world unload, where the item is present.
  writeBackToItem()

  self.petId = nil
  self.spawning = false
end

--  Persist the live pet state into the socketed item, so the unit travels with
--  the item rather than living in the petport.
function writeBackToItem()
  if self.petData == nil then return end
  local item = socketedItem()
  if item == nil then return end

  item.parameters = item.parameters or {}
  item.parameters.petData = self.petData

  trace("writing back to item", self.petData)

  world.containerSwapItemsNoCombine(entity.id(), item, 0)
  self.dirty = false
end

function stationUniqueId()
  local uniqueId = entity.uniqueId()
  if not uniqueId then
    uniqueId = sb.makeUuid()
    world.setUniqueId(entity.id(), uniqueId)
  end
  return uniqueId
end

--------------------------------------------------------------------------------

function update(dt)
  if self.firstUpdate then
    self.firstUpdate = false
    stationUniqueId()
  end

  local item = socketedItem()

  if item == nil then
    --  Item removed: put the unit away.
    if self.petId ~= nil then
      saveAndDespawn()
      self.petData = nil
    end
    animator.setAnimationState("stationState", "off")
    return
  end

  --  Newly socketed.
  --
  --  KNOWN GAP: this only detects the nil -> item transition. Swapping unit
  --  item A directly for unit item B leaves petData non-nil, so the petport
  --  keeps running unit A and stamps A's state onto item B. Fixing it needs a
  --  per-item identity to compare against -- a uuid stamped into petData on
  --  first spawn, since two found items are otherwise indistinguishable.
  if self.petData == nil then
    self.petData = petDataFrom(item)
    if self.petData == nil then
      --  Not a pet item, or a malformed one. Do nothing rather than spawning
      --  something unintended.
      animator.setAnimationState("stationState", "off")
      return
    end
    self.spawnTimer = 0
  end

  animator.setAnimationState("stationState", "on")

  --  Spawn, or respawn after an unload/death.
  if self.petId == nil or not world.entityExists(self.petId) then
    self.spawnTimer = self.spawnTimer - dt
    if self.spawnTimer <= 0 then
      if self.petId ~= nil then
        --  It existed and now does not. Keep whatever state we last heard.
        self.petId = nil
      end
      spawnPet()
      self.spawnTimer = RESPAWN_GRACE
    end
  end

  --  Immediate on a durable change, otherwise on the slow timer.
  self.writeTimer = self.writeTimer - dt
  if self.dirty or self.writeTimer <= 0 then
    writeBackToItem()
    self.writeTimer = WRITE_INTERVAL
  end
end

function onInteraction(args)
  --  Falls through to the container UI declared by uiConfig on the object.
  return config.getParameter("interactAction")
end

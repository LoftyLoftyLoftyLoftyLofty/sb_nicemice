require "/scripts/util.lua"
require "/scripts/messageutil.lua"

--  M.A.U.S. PET STATION
--
--  A one-slot container. Socket a nicemice_shippet item and the unit it
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
--    * a status heartbeat, so the station notices when its pet dies or unloads
--    * collision-aware spawn placement
--
--  ANCHORING
--
--  Vanilla's groundPet.lua expects an anchor object and calls setAnchor on
--  itself, which calls back into hasPet/setPet here. It kills the pet outright
--  if it cannot find one (see findAnchor). So this object implements the same
--  contract the SAIL techstation does -- hasPet, setPet -- and the monstertype's
--  anchorName points at this object. That keeps vanilla's pet scripts usable
--  unmodified while the behavior work happens separately.

local STATUS_INTERVAL = 2.0
local RESPAWN_GRACE = 1.0

function init()
  self.petId = nil
  self.petUniqueId = nil
  self.petData = nil
  self.statusTimer = 0
  self.spawnTimer = 0
  self.spawning = false
  self.firstUpdate = true

  --  Sent by the pet when it dies or is recalled, so the station can write the
  --  final state back into the item rather than losing it.
  message.setHandler("nicemice_petStatus", simpleHandler(function(status, storage)
    if self.petData then
      self.petData.status = status or self.petData.status
      self.petData.storage = storage or self.petData.storage
      self.dirty = true
    end
  end))

  object.setInteractive(true)
end

function uninit()
  --  Station unloading or being broken: put the unit back in its item so
  --  nothing is lost.
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

  --  groundPet.lua pushes its own state here on a timer. Capture it so the
  --  item stays current without the station having to ask.
  if params and self.petData then
    self.petData.storage = self.petData.storage or {}
    self.petData.storage.foodLikings = params.foodLikings or self.petData.storage.foodLikings
    self.petData.storage.knownPlayers = params.knownPlayers or self.petData.storage.knownPlayers
    self.petData.storage.petResources = params.petResources or self.petData.storage.petResources
    self.dirty = true
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
  return data
end

function spawnPet()
  if self.petData == nil or self.petData.monsterType == nil then return end
  if self.petId ~= nil and world.entityExists(self.petId) then return end

  local spawnPosition = object.toAbsolutePosition(config.getParameter("petSpawnOffset", {0, 2}))

  local parameters = {
    --  Ship pets belong to the ship, not the world's threat level.
    level = math.max(world.threatLevel(), world.getProperty("ship.level") or 0, 1),

    --  Persistent so the unit is not garbage collected while the player is
    --  elsewhere on the ship; the station owns its lifetime instead.
    persistent = true,

    --  Never yanked around by relocation logic meant for wild creatures.
    relocatable = false,

    damageTeamType = "ghostly",

    scriptConfig = {
      --  How the pet reports home. It messages the station rather than the
      --  station polling it, which keeps the item current even if the pet dies
      --  while the player is watching something else.
      stationUniqueId = stationUniqueId(),

      --  Resume where it left off. groundPet.lua reads petResources,
      --  knownPlayers and foodLikings out of storage on init.
      initialStatus = copy(self.petData.status) or {},
      initialStorage = copy(self.petData.storage) or {},

      petName = self.petData.petName
    }
  }

  self.petId = world.spawnMonster(self.petData.monsterType, spawnPosition, parameters)
  if self.petId then
    self.spawning = true
    self.statusTimer = STATUS_INTERVAL

    --  Hand the pet its anchor, exactly as techstation.lua does. groundPet.lua
    --  calls back into setPet from here.
    world.callScriptedEntity(self.petId, "setAnchor", entity.id())
  end
end

function saveAndDespawn()
  if self.petId and world.entityExists(self.petId) then
    --  Ask for final state before removing it. Best effort: if the pet is
    --  already gone the item simply keeps the last state we heard about.
    local ok, state = pcall(world.callScriptedEntity, self.petId, "nicemice_petStore")
    if ok and state and self.petData then
      self.petData.status = state.status or self.petData.status
      self.petData.storage = state.storage or self.petData.storage
    end
    world.callScriptedEntity(self.petId, "nicemice_petDespawn")
  end
  writeBackToItem()
  self.petId = nil
  self.spawning = false
end

--  Persist the live pet state into the socketed item, so the unit travels with
--  the item rather than living in the station.
function writeBackToItem()
  if self.petData == nil then return end
  local item = socketedItem()
  if item == nil then return end

  item.parameters = item.parameters or {}
  item.parameters.petData = self.petData
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

  --  Newly socketed, or a different item swapped in.
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

  if self.dirty then
    writeBackToItem()
  end
end

function onInteraction(args)
  --  Falls through to the container UI declared by uiConfig on the object.
  return config.getParameter("interactAction")
end

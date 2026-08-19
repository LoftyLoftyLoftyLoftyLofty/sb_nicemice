require "/scripts/util.lua"
require "/scripts/vec2.lua"

--  M.A.U.S. UTILITY VENT
--
--  A node a ship pet can travel between. Wire two vents together and a unit can
--  move from one to the other instantly, which sidesteps pathfinding entirely --
--  worth doing deliberately, because a small ground pet has no good way to climb
--  ladders or cross decks on a multi-level ship.
--
--  WIRING
--
--  Every other wired object in the game uses wires as a SIGNAL: setOutputNodeLevel
--  on one end, getInputNodeLevel on the other. Vents use them as a LINK instead --
--  what matters is not the level but which object is on the far end, which is what
--  getOutputNodeIds / getInputNodeIds report.
--
--  That buys a nice property: ONE wire links a pair both ways. Wire A's output to
--  B's input and A discovers B through its output node while B discovers A through
--  its input node. The player does not have to think about direction, and pulling
--  the wire disconnects both ends at once.
--
--  A vent may have several partners; a travelling unit picks one.
--
--  UNVERIFIED: the exact return shape of getOutputNodeIds/getInputNodeIds. It is
--  documented as a list of connected entity ids, and partnerIds() below tolerates
--  either a plain list or a map of id -> node index. If linking silently fails,
--  log what these actually return before changing anything else.

local function collectIds(result, into)
  if result == nil then return end
  for key, value in pairs(result) do
    --  plain list: value is the id.  map: key is the id.
    local id = value
    if type(value) ~= "number" then id = key end
    if type(id) == "number" and id ~= entity.id() then
      into[id] = true
    end
  end
end

--  Every vent this one is wired to, in either direction.
function partnerIds()
  local ids = {}

  for i = 0, object.outputNodeCount() - 1 do
    collectIds(object.getOutputNodeIds(i), ids)
  end
  for i = 0, object.inputNodeCount() - 1 do
    collectIds(object.getInputNodeIds(i), ids)
  end

  --  Only other vents. A player may well wire a vent to a door or a light by
  --  accident, and teleporting a unit into a lamp would be impolite.
  local vents = {}
  local ventName = config.getParameter("objectName")
  for id, _ in pairs(ids) do
    if world.entityExists(id) and world.entityName(id) == ventName then
      table.insert(vents, id)
    end
  end
  return vents
end

function init()
  self.partners = {}
  self.refreshTimer = 0
  object.setInteractive(false)
  refreshPartners()
end

function onNodeConnectionChange(args)
  refreshPartners()
end

function onInputNodeChange(args)
  refreshPartners()
end

function refreshPartners()
  self.partners = partnerIds()
  if #self.partners > 0 then
    animator.setAnimationState("ventState", "linked")
  else
    animator.setAnimationState("ventState", "idle")
  end
end

--------------------------------------------------------------------------------
--  PET-FACING API
--
--  Called by a unit's behavior via world.callScriptedEntity. Kept deliberately
--  small so the pet side can stay simple.
--------------------------------------------------------------------------------

--  Is this vent usable right now? A vent with nothing wired to it is scenery.
function nicemice_ventLinked()
  return #self.partners > 0
end

--  Where a unit should stand to enter. One tile above the vent, so the pet is
--  standing on it rather than inside it.
function nicemice_ventEntryPosition()
  return object.toAbsolutePosition(config.getParameter("entryOffset", {0, 1}))
end

--  Every destination this vent can reach, as {id, position} pairs, so a pet can
--  choose by proximity to whatever it is actually trying to reach.
function nicemice_ventDestinations()
  local destinations = {}
  for _, id in ipairs(self.partners) do
    if world.entityExists(id) then
      local ok, position = pcall(world.callScriptedEntity, id, "nicemice_ventEntryPosition")
      if ok and position then
        table.insert(destinations, { id = id, position = position })
      end
    end
  end
  return destinations
end

--  Move an entity to one of this vent's partners.
--
--  destinationId is optional; without it a partner is chosen at random, which is
--  the sane default for a unit that just wants to be somewhere else.
--
--  Returns the destination position on success, nil on failure -- so the caller
--  can fall back to walking rather than assuming it arrived.
function nicemice_ventTravel(entityId, destinationId)
  if entityId == nil or not world.entityExists(entityId) then return nil end
  if #self.partners == 0 then return nil end

  local destinations = nicemice_ventDestinations()
  if #destinations == 0 then return nil end

  local chosen = nil
  if destinationId then
    for _, destination in ipairs(destinations) do
      if destination.id == destinationId then chosen = destination end
    end
  end
  chosen = chosen or destinations[math.random(#destinations)]

  --  Announce at both ends before the entity moves, so the effect plays where
  --  the player is looking regardless of which end that is.
  animator.playSound("vent")
  animator.burstParticleEmitter("vent")
  pcall(world.callScriptedEntity, chosen.id, "nicemice_ventArrival")

  world.callScriptedEntity(entityId, "nicemice_ventTeleport", chosen.position)

  return chosen.position
end

--  Played on the receiving vent, so travel reads as a journey rather than a
--  disappearance.
function nicemice_ventArrival()
  animator.playSound("vent")
  animator.burstParticleEmitter("vent")
end

function update(dt)
  --  Wire callbacks cover connection changes, but a partner can also be broken,
  --  unloaded, or replaced without any node event firing here. Re-checking on a
  --  slow timer keeps the animation state and the partner list honest.
  self.refreshTimer = self.refreshTimer - dt
  if self.refreshTimer <= 0 then
    self.refreshTimer = 2.0
    refreshPartners()
  end
end

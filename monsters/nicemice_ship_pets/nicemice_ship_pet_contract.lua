--  M.A.U.S. UTILITY UNIT -- PETPORT / VENT CONTRACT
--
--  The petport and the vent call functions ON the unit via
--  world.callScriptedEntity. groundPet.lua defines none of them, so without
--  this file those calls do nothing at all -- and they do it SILENTLY. A bare
--  world.callScriptedEntity naming a function the target does not define
--  returns nil rather than raising, so a missing contract does not error, log,
--  or crash. It just quietly fails to happen.
--
--  That is exactly how the socket-cycle leak was found: removing the item let
--  saveAndDespawn run to completion, the petport cleared self.petId, and the
--  unit carried on living because nicemice_petDespawn resolved to nothing.
--  Re-socketing then spawned a second unit alongside the orphan.
--
--  ADD THIS TO THE MONSTERTYPE'S scripts LIST, after groundPet.lua.
--
--  CRITICAL: this file must NOT define init, update or uninit. Every script in
--  a monstertype's list shares one Lua environment, so a second definition of
--  any of those silently replaces groundPet.lua's. Prefixed functions only.

--------------------------------------------------------------------------------
--  PETPORT CONTRACT
--------------------------------------------------------------------------------

--  Hand the petport everything worth keeping, so it can write it into the item.
--
--  Only `storage` round-trips for now. groundPet.lua reads knownPlayers,
--  foodLikings and petResources out of `storage` on init, and the petport feeds
--  them back as initialStorage, so storage alone covers everything that
--  currently persists.
--
--  `storage.petResources` is seeded at init and never updated as resources
--  tick, so it is refreshed here from live values before handing it over --
--  otherwise a unit would resume at its starting hunger every time.
--
--  DEFERRED: status round-tripping. `initialStatus` is engine-interpreted and
--  its reciprocal getter is not confirmed, so nothing is returned under that
--  key. Health resets to full on respawn as a result, which is harmless for a
--  unit that cannot be damaged.
function nicemice_petStore()
  storage.petResources = petResources()

  return {
    storage = copy(storage)
  }
end

--  Put the unit away.
--
--  There is no Lua call that simply removes a monster, so recall is death with
--  the funeral suppressed -- the vanilla idiom for capture-pod recall. dropPools
--  is already empty on the monstertype, so nothing is left behind.
--
--  VERIFY: setDeathParticleBurst / setDeathSound accepting nil to clear. If the
--  unit poofs audibly on recall, that is these two not taking effect, and the
--  fix is passing "" rather than nil.
function nicemice_petDespawn()
  monster.setDeathParticleBurst(nil)
  monster.setDeathSound(nil)
  status.setResource("health", 0)
  return true
end

--------------------------------------------------------------------------------
--  VENT CONTRACT
--------------------------------------------------------------------------------

--  Called by a vent to move this unit to the far end. The vent plays its own
--  effects at both ends before calling, so this only has to handle the move.
--
--  Velocity is cleared so a unit that entered mid-stride does not shoot out of
--  the destination still carrying its momentum.
function nicemice_ventTeleport(position)
  if position == nil then return false end

  mcontroller.setPosition(position)
  mcontroller.setVelocity({0, 0})

  return true
end

--  M.A.U.S. UTILITY UNIT -- SLEEP
--
--  Replaces vanilla /monsters/pets/actions/sleepAction.lua. REMOVE THAT FILE
--  FROM THE MONSTERTYPE'S scripts LIST -- both register as action states, both
--  answer to the same args key, and whichever the state machine reaches first
--  wins. Owning our own copy also means another mod's experiment on the vanilla
--  file cannot reach into how our units behave.
--
--  WHY THIS EXISTS
--
--  Vanilla sleepAction does this on arrival:
--
--      local bounds = boundingBox()
--      mcontroller.setPosition({targetPosition[1], targetPosition[2] - bounds[2]})
--
--  A hard teleport onto the sleep target, with no check of what is already
--  there. That is the acute case of the single most-complained-about vanilla
--  pet behaviour -- a pet parked in front of the thing you needed. Validation
--  that only gated approach would miss it entirely, because the pet does not
--  walk into the bad spot, it appears in it.
--
--  Both sleep paths now go through nicemice_petplacement.lua, and a unit that
--  cannot find a polite spot DECLINES to sleep rather than sleeping rudely.
--
--  NAMING
--
--  groundPet.lua builds its action list with
--
--      stateMachine.scanScripts(config.getParameter("scripts"), "(%a+Action)%.lua")
--
--  and then looks the captured name up in _ENV. %a matches letters only, so an
--  underscore would truncate the capture -- nicemice_sleepAction.lua captures
--  "sleepAction" and would shadow vanilla's global name. Camel case keeps the
--  capture whole and the global distinct.
--
--  But petBehavior.actionStates hardcodes ["sleep"] = "sleepAction", and
--  petBehavior.run compares stateDesc() against that string to decide whether
--  sleep is already running. So description() below reports "sleepAction" --
--  the state is ours, the label the behavior layer sees is vanilla's.

nicemiceSleepAction = {
  cooldown = 10
}

--  How long to keep trying to walk to a chosen resting spot before giving up.
local APPROACH_TIMEOUT = 6.0

function nicemiceSleepAction.description()
  --  Deliberately vanilla's name; see the header.
  return "sleepAction"
end

function nicemiceSleepAction.enterWith(args)
  if not args.sleepAction and not args.sleepTarget then return nil end

  if args.sleepAction and status.resourcePercentage("sleepy") < 1 then
    return nil
  end

  --  Vanilla reads "actions.sleep.minSleepy" here, but the monstertype defines
  --  actionParams.sleep.minSleepy -- there is no top-level "actions" key, so
  --  vanilla's lookup always misses and silently uses its 65 default. Reading
  --  the parameter that actually exists means the configured value is honoured.
  if args.sleepTarget and status.resource("sleepy") < config.getParameter("actionParams.sleep.minSleepy", 65) then
    return nil
  end

  return {
    targetId = args.sleepTarget,
    sleepRate = -5,
    sleeping = false,
    restPosition = nil,
    approachTimer = APPROACH_TIMEOUT
  }
end

function nicemiceSleepAction.enteringState(stateData)
  if stateData.targetId then
    emote("sleepy")
  else
    animator.setParticleEmitterActive("sleep", true)
  end
end

--  Sleeping in place, wherever the unit happens to be standing.
--
--  Vanilla just falls asleep on the spot. A unit that wandered into a doorway
--  and got tired then blocks it until it wakes. So the spot is checked, and if
--  it is rude the unit WALKS to a better one -- deliberately not a teleport,
--  because nothing here is urgent enough to justify one.
local function settleInPlace(dt, stateData)
  if stateData.restPosition == nil then
    local here = mcontroller.position()

    if nicemice_petCanRestAt(here) then
      stateData.restPosition = here
    else
      stateData.restPosition = nicemice_petFindRestPosition(here, 6)

      if stateData.restPosition == nil then
        --  Nowhere polite within reach. Stay awake rather than sleep badly.
        return true, config.getParameter("actionParams.sleep.cooldown", 15)
      end
    end
  end

  --  Already there?
  if world.magnitude(mcontroller.position(), stateData.restPosition) <= 0.5 then
    stateData.sleeping = true
    animator.setParticleEmitterActive("sleep", true)
    return false
  end

  --  Walk, but do not spend the whole nap trying.
  stateData.approachTimer = stateData.approachTimer - dt
  if stateData.approachTimer <= 0 or self.pathing.stuck then
    return true, config.getParameter("actionParams.sleep.cooldown", 15)
  end

  approachPoint(dt, stateData.restPosition, 0.5, false)
  return false
end

--  Sleeping at a target -- a pet house or similar.
local function settleAtTarget(dt, stateData)
  if not world.entityExists(stateData.targetId) then return true end

  --  Perch offset, not raw entity position -- an object's position is its
  --  anchor tile, which is rarely where the art says a unit should curl up.
  --  Falls back to the entity position when the perch declares no offset.
  local targetPosition = nicemice_petPerchPosition(stateData.targetId)
    or world.entityPosition(stateData.targetId)
  if targetPosition == nil then return true end

  if not approachPoint(dt, targetPosition, 1.5, false) then
    if self.pathing.stuck then
      return true, config.getParameter("actionParams.sleep.cooldown", 15)
    end
    return false
  end

  --  Arrived. This is where vanilla teleports blind. nicemice_petSettleAt finds
  --  the nearest acceptable spot to the target and places the unit there, or
  --  returns false if everything within reach is occupied.
  --
  --  ignoreEntityId is the target itself: the unit is deliberately climbing
  --  into that object, so its own footprint must not disqualify the spot.
  if not nicemice_petSettleAt(targetPosition, { ignoreEntityId = stateData.targetId }) then
    return true, config.getParameter("actionParams.sleep.cooldown", 15)
  end

  animator.setParticleEmitterActive("sleep", true)
  stateData.sleeping = true
  return false
end

function nicemiceSleepAction.update(dt, stateData)
  if not stateData.sleeping then
    if stateData.targetId then
      return settleAtTarget(dt, stateData)
    else
      return settleInPlace(dt, stateData)
    end
  end

  status.modifyResource("sleepy", stateData.sleepRate * dt)

  if stateData.targetId then
    if not world.entityExists(stateData.targetId) then
      return true, config.getParameter("actionParams.sleep.cooldown", 15)
    end
    animator.setAnimationState("movement", "invisible")
  else
    animator.setAnimationState("movement", "sleep")
  end

  if status.resourcePercentage("sleepy") <= 0 then
    return true, config.getParameter("actionParams.sleep.cooldown", 15)
  end

  return false
end

function nicemiceSleepAction.leavingState(stateData)
  setIdleState()
  animator.setParticleEmitterActive("sleep", false)
end

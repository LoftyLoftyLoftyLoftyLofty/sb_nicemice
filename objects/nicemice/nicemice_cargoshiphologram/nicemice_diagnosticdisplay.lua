--  SHIP DIAGNOSTIC DISPLAY
--
--  Cycles through a list of animation states, one step per wire pulse. Wire a
--  button (or any pulsing output) into node 0; each press advances the display
--  to the next state and wraps around at the end.

--  The states to cycle through, in order. These must match state names declared
--  under DISPLAY_STATE_TYPE in the object's .animation file.
local DISPLAY_STATES = {
  "bridge",
  "cargohold0",
  "cargohold1",
  "cargohold2",
  "engineering",
  "reactor",
  "lifesupport",
  "galley",
  "quarters0",
  "quarters1",
  "medbay",
  "armory",
  "hangar",
  "airlockfore",
  "airlockaft",
  "dockingfield",
  "sensors",
  "comms",
  "shields",
  "fueltanks",
  "cryostorage",
  "workshop",
  "tramline",
  "exterior"
}

--  The stateType these live under in the .animation file.
local DISPLAY_STATE_TYPE = "displayState"

--------------------------------------------------------------------------------

function init()
  --  Persisted so the display keeps its page across a reload rather than
  --  snapping back to the bridge every time the ship loads.
  storage.displayIndex = storage.displayIndex or 1

  --  Edge detection needs to know where the wire started. Reading the node here
  --  rather than assuming false means a display wired to a switch that is
  --  already ON does not advance the moment it loads.
  self.lastLevel = inputLevel()

  applyState()
end

local function wrapIndex(index)
  --  Lua is 1-based, so the modulo has to be shifted either side.
  return ((index - 1) % #DISPLAY_STATES) + 1
end

function inputLevel()
  if not config.getParameter("inputNodes") then return false end
  if object.inputNodeCount() < 1 then return false end
  return object.getInputNodeLevel(0)
end

function applyState()
  local stateName = DISPLAY_STATES[storage.displayIndex]
  if stateName == nil then
    --  Index somehow out of range (list edited between saves, say). Reset
    --  rather than leaving the display stuck on nothing.
    storage.displayIndex = 1
    stateName = DISPLAY_STATES[1]
  end

  animator.setAnimationState(DISPLAY_STATE_TYPE, stateName)

  --  Handy for a nameplate widget or a tooltip later on.
  object.setConfigParameter("currentDisplayState", stateName)
end

function advance(step)
  storage.displayIndex = wrapIndex(storage.displayIndex + (step or 1))
  applyState()

  if animator.hasSound("advance") then
    animator.playSound("advance")
  end
end

--------------------------------------------------------------------------------
--  WIRE
--------------------------------------------------------------------------------

--  Advance on the RISING edge only.
--
--  A pulse is the level going true and then false again, so acting on every
--  change would step twice per button press. Comparing against the last level
--  also makes the script behave sensibly when it is wired to a latching switch
--  instead of a button: each flip to ON advances once, and flipping back to OFF
--  does nothing.
function onInputNodeChange(args)
  local level = inputLevel()
  if level and not self.lastLevel then
    advance(1)
  end
  self.lastLevel = level
end

function onNodeConnectionChange(args)
  --  Re-baseline when the wiring changes, so plugging a live wire in does not
  --  register as a press.
  self.lastLevel = inputLevel()
end

--------------------------------------------------------------------------------
--  DIRECT USE
--------------------------------------------------------------------------------

--  Interacting with the display advances it too, unless something is wired in.
--  Mostly this is so the thing can be tested without laying wire; set
--  "interactive" false in the object config to make it wire-only.
function onInteraction(args)
  if object.isInputNodeConnected(0) then return end
  advance(1)
end

--  Lets another script step the display, e.g. a diagnostic that wants to jump
--  straight to the deck it is reporting on.
function nicemice_setDisplayState(stateName)
  for index, name in ipairs(DISPLAY_STATES) do
    if name == stateName then
      storage.displayIndex = index
      applyState()
      return true
    end
  end
  return false
end

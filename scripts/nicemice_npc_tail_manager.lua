-- NPC-side counterpart to nicemice_tail_manager.lua.
--
-- Same job, different namespace: NPCs use npc.getItemSlot / npc.setItemSlot
-- rather than player.equippedItem / player.setEquippedItem. The actual
-- directive work is shared, in nicemice_applyTailDirectives.
--
-- This lives in the base NPC script pool, so it runs on every mouse in the
-- world. Two consequences drive the shape of the code below:
--   1. It must be listed AFTER /npcs/bmain.lua in the npctype's scripts array,
--      or bmain's update will be defined last and clobber this one.
--   2. It must stay cheap. world.entityPortrait and root.itemConfig are not
--      per-tick calls, so the portrait lookup is cached and the slot scan is
--      throttled.

require "/scripts/nicemice_util.lua"

local TAIL_SLOTS = {"back", "backCosmetic"}
local TAIL_CHECK_INTERVAL = 1.0

-- Each NPC entity gets its own script context, so file-scope locals are
-- per-mouse state, not shared across the world.
local nicemiceTailDirectives = nil
local nicemiceTailTimer = 0

originalInit = init
originalUpdate = update
originalUninit = uninit

function init()
  if originalInit ~= nil then
	originalInit()
  end

  nicemiceTailDirectives = nil
  nicemiceTailTimer = 0
end

function uninit()
  if originalUninit ~= nil then
	originalUninit()
  end
end

function update(dt)

  if originalUpdate ~= nil then
	originalUpdate(dt)
  end

  nicemiceTailTimer = nicemiceTailTimer - dt
  if nicemiceTailTimer > 0 then return end
  nicemiceTailTimer = TAIL_CHECK_INTERVAL

  -- Resolved lazily rather than in init: the entity isn't necessarily
  -- portrait-ready on the first frame. Once resolved it never changes for the
  -- life of the NPC, so this is a one-time cost.
  if not nicemiceTailDirectives then
    nicemiceTailDirectives = nicemice_getEntitySkinDirectives(entity.id())
    if not nicemiceTailDirectives then return end
  end

  nicemice_applyTailDirectives(
    nicemiceTailDirectives,
    TAIL_SLOTS,
    npc.getItemSlot,
    npc.setItemSlot
  )
end

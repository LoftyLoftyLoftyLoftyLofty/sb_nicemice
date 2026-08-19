-- This script applies directives to recolorable nicemice tail items 
-- when worn by the player so that the tails don't look silly in the char select screen

-- It's worth noting that the nicemice_recolorable_tail status effect still runs,
-- and that this status effect is important because it recolors the tails for NPCs too

-- The NPC-side equivalent of this script is nicemice_npc_tail_manager.lua;
-- the shared work lives in nicemice_applyTailDirectives.

require "/scripts/nicemice_util.lua"

local TAIL_SLOTS = {"back", "backCosmetic"}

originalInit = init
originalUpdate = update
originalUninit = uninit

function init()
  --script.setUpdateDelta(10)
  if originalInit ~= nil then
	originalInit()
  end
end

function uninit()
  --script.setUpdateDelta(10)
  if originalUninit ~= nil then
	originalUninit()
  end
end

function update(dt)

  if originalUpdate ~= nil then
	originalUpdate(dt)
  end

  nicemice_applyTailDirectives(
    nicemice_getPlayerSkinDirectives(),
    TAIL_SLOTS,
    player.equippedItem,
    player.setEquippedItem
  )
end

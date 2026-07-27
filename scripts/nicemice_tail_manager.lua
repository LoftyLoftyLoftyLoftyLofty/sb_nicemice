-- This script applies directives to recolorable nicemice tail items 
-- when worn by the player so that the tails don't look silly in the char select screen

-- It's worth noting that the nicemice_recolorable_tail status effect still runs,
-- and that this status effect is important because it recolors the tails for NPCs too

require "/scripts/nicemice_util.lua"

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
  
  local directives = nicemice_getPlayerSkinDirectives()
  if not directives then return end

  local slotsToCheck = {"back", "backCosmetic"}

  for _, slotName in ipairs(slotsToCheck) do
    local backItem = player.equippedItem(slotName)

    if backItem then
      local hasTag = false

      if backItem.parameters and backItem.parameters.itemTags then
        for _, tag in ipairs(backItem.parameters.itemTags) do
          if tag == "nicemice_recolorable_tail" then hasTag = true break end
        end
      end

      if not hasTag then
        local baseConfig = root.itemConfig(backItem)
        if baseConfig and baseConfig.config and baseConfig.config.itemTags then
          for _, tag in ipairs(baseConfig.config.itemTags) do
            if tag == "nicemice_recolorable_tail" then hasTag = true break end
          end
        end
      end

      -- Check if directives need updating
      if hasTag and (not backItem.parameters.nicemiceDirectives or backItem.parameters.nicemiceDirectives ~= directives) then
        backItem.parameters.nicemiceDirectives = directives
        
        -- Dynamic Asset Lookup: Safely extract the genuine base inventory icon name
        local baseConfig = root.itemConfig(backItem)
        local baseIcon = "tailicon.png" -- Fallback default
        if baseConfig and baseConfig.config and baseConfig.config.inventoryIcon then
          baseIcon = baseConfig.config.inventoryIcon
        end
        
        -- Reapply directives cleanly over the item's actual native icon
        backItem.parameters.inventoryIcon = baseIcon .. "?" .. directives
        
        -- Force the client to use the default graphics path for the item frame
        backItem.parameters.maleFrames = nil
        backItem.parameters.femaleFrames = nil
        
        -- Slap some directives on that bad boy
        backItem.parameters.directives = "?" .. directives

        player.setEquippedItem(slotName, backItem)
      end
    end
  end
end
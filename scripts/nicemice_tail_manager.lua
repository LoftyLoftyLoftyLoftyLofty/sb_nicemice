-- This script applies directives to recolorable nicemice tail items 
-- when worn by the player so that the tails don't look silly in the char select screen

-- It's worth noting that the nicemice_recolorable_tail status effect still runs,
-- and that this status effect is important because it recolors the tails for NPCs too

require "/scripts/nicemice_util.lua"

function init()
  script.setUpdateDelta(10)
end

function update(dt)
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
        
        -- Icons are static and still need the standard append method
        local baseIcon = "tailicon.png"
        backItem.parameters.inventoryIcon = baseIcon .. "?" .. directives
        
        -- Force the client to use the default graphics path for the item
        backItem.parameters.maleFrames = nil
        backItem.parameters.femaleFrames = nil
        
        -- Slap some directives on that bad boy
        backItem.parameters.directives = "?" .. directives

        player.setEquippedItem(slotName, backItem)
      end
    end
  end
end
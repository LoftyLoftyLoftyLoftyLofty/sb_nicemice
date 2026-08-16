_nicemice_old_status_func = randomStatusText

local NICEMICE_GENERIC_CHANCE = 0.33

function randomStatusText(personality)
  if not (npc and npc.species and npc.species() == "nicemice_npc") then
    return _nicemice_old_status_func(personality)
  end

  local statuses = root.assetJson("/npcs/statuses.config:statuses")

  local options = personality and statuses[personality]
  if options and #options > 0 and math.random() >= NICEMICE_GENERIC_CHANCE then
    return options[math.random(#options)]
  end

  -- no personality list, or the generic roll came up
  options = statuses.nicemice_generic
  if options and #options > 0 then
    return options[math.random(#options)]
  end

  return _nicemice_old_status_func(personality)
end
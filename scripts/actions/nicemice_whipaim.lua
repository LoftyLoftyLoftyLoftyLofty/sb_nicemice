-- param entity
-- output position
function nicemice_entityCenterPosition(args, board)
  if args.entity == nil or not world.entityExists(args.entity) then return false end
	local p = world.entityPosition(args.entity)
	--sb.logInfo( "entity: " .. sb.printJson( args.entity ) )
    return true, {position = p, x = p[1], y = p[2]}
end

-- param number
-- output result
function nicemice_signOf(args, board)
  if args.number == nil then return false end

  if args.number > 0 then
    return true, {result = 1}
  elseif args.number < 0 then
    return true, {result = -1}
  else
    return true, {result = 0}
  end
end

-- Existence is checked, not just non-nil-ness of the board key: a dead combat
-- target leaves its id sitting on the board, and world.entityPosition of a dead
-- id gives nothing back, so the offset handed to setAimPosition collapses to
-- zero and the NPC aims at its own feet. Harmless for a heal, but it is how a
-- staff user ends up dropping a slow zone on itself. Same guard its neighbour
-- nicemice_entityCenterPosition already makes.
--
-- param from
-- param to
-- output vector
-- output x
-- output y
-- output magnitude
function nicemice_entityDistance(args, board)
  -- sb.logInfo( "dist check: " .. sb.printJson( args.fromEntity ) .. " -> " .. sb.printJson( args.toEntity ) )
  if args.fromEntity == nil or args.toEntity == nil then return false end
  if not world.entityExists(args.fromEntity) or not world.entityExists(args.toEntity) then return false end

  local from = world.entityPosition(args.fromEntity)
  local to = world.entityPosition(args.toEntity)
  if from == nil or to == nil then return false end

  local distance = world.distance(to, from)
  return true, {vector = distance, x = distance[1], y = distance[2], magnitude = world.magnitude(to, from)}
end
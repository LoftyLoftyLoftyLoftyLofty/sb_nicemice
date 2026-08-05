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

-- param from
-- param to
-- output vector
-- output x
-- output y
-- output magnitude
function nicemice_entityDistance(args, board)
  -- sb.logInfo( "dist check: " .. sb.printJson( args.fromEntity ) .. " -> " .. sb.printJson( args.toEntity ) )
  if args.fromEntity == nil or args.toEntity == nil then return false end
  
  local from = world.entityPosition(args.fromEntity)
  local to = world.entityPosition(args.toEntity)
  
  local distance = world.distance(to, from)
  return true, {vector = distance, x = distance[1], y = distance[2], magnitude = world.magnitude(to, from)}
end
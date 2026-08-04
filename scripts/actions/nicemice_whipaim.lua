-- param entity
-- output position
function nicemice_entityCenterPosition(args, board)
  if args.entity == nil or not world.entityExists(args.entity) then return false end

  local boundBox = world.entityMetaBoundBox(args.entity)
  if boundBox == nil then
    return true, {position = world.entityPosition(args.entity)}
  end

  local center = {(boundBox[1] + boundBox[3]) / 2, (boundBox[2] + boundBox[4]) / 2}
  return true, {position = center}
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
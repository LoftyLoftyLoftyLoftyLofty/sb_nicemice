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
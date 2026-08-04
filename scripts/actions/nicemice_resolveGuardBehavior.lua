-- param baseBehavior
-- param whipBehavior
-- output behavior
function nicemice_resolveGuardBehavior(args, board)
  local baseBehavior = args.baseBehavior or "guard"
  local whipBehavior = args.whipBehavior or (baseBehavior .. "-whip")

  if self.primary and root.itemHasTag(self.primary.name, "whip") then
    return true, {behavior = whipBehavior}
  else
    return true, {behavior = baseBehavior}
  end
end
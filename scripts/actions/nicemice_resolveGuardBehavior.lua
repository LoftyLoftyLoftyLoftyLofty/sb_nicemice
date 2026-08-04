-- param baseBehavior
-- param whipBehavior
-- param wandstaffBehavior
-- output behavior
function nicemice_resolveGuardBehavior(args, board)
  local baseBehavior = args.baseBehavior or "guard"
  local whipBehavior = args.whipBehavior or (baseBehavior .. "-whip")
  local wandstaffBehavior = args.wandstaffBehavior or (baseBehavior .. "-wandstaff")

  if self.primary and root.itemHasTag(self.primary.name, "whip") then
    return true, {behavior = whipBehavior}
  elseif self.primary and (root.itemHasTag(self.primary.name, "wand") or root.itemHasTag(self.primary.name, "staff")) then
    return true, {behavior = wandstaffBehavior}
  else
    return true, {behavior = baseBehavior}
  end
end
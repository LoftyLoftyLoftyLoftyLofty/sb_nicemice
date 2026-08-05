-- param baseBehavior
-- param whipBehavior
-- param wandstaffBehavior
-- output behavior
function nicemice_resolveGuardBehavior(args, board)
  local baseBehavior = args.baseBehavior or "guard"
  local whipBehavior = args.whipBehavior or baseBehavior
  local wandstaffBehavior = args.wandstaffBehavior or baseBehavior

  -- Weapons may be equipped in either "primary" (drawn) or "sheathedPrimary"
  -- (hidden, e.g. via crewmember-emptyhands) at the moment this resolver
  -- runs. Check both, since this only runs once at init and self.primary may
  -- not be populated yet if the weapon starts sheathed.
  local equipped = self.primary or self.sheathedPrimary

  if equipped and root.itemHasTag(equipped.name, "whip") then
    return true, {behavior = whipBehavior}
  elseif equipped and (root.itemHasTag(equipped.name, "wand") or root.itemHasTag(equipped.name, "staff")) then
    return true, {behavior = wandstaffBehavior}
  else
    return true, {behavior = baseBehavior}
  end
end
-- param baseBehavior
-- param whipBehavior
-- param wandstaffBehavior
-- param rangedBehavior
-- output behavior
function nicemice_resolveGuardBehavior(args, board)
  local baseBehavior = args.baseBehavior or "guard"
  local whipBehavior = args.whipBehavior or baseBehavior
  local wandstaffBehavior = args.wandstaffBehavior or baseBehavior
  local rangedBehavior = args.rangedBehavior or baseBehavior

  -- Weapons may be equipped in either "primary" (drawn) or "sheathedPrimary"
  -- (hidden, e.g. via crewmember-emptyhands) at the moment this resolver
  -- runs. Check both, since this only runs once at init and self.primary may
  -- not be populated yet if the weapon starts sheathed.
  local equipped = self.primary or self.sheathedPrimary

  -- Order matters. A whip also carries the "melee" tag and some staves carry
  -- more than one of these, so the specific weapon families are matched before
  -- the broad "ranged" tag that guns, bows and rifles all share.
  local resolved
  if equipped and root.itemHasTag(equipped.name, "whip") then
    resolved = whipBehavior
  elseif equipped and (root.itemHasTag(equipped.name, "wand") or root.itemHasTag(equipped.name, "staff")) then
    resolved = wandstaffBehavior
  elseif equipped and root.itemHasTag(equipped.name, "ranged") then
    resolved = rangedBehavior
  else
    resolved = baseBehavior
  end

  return true, {behavior = resolved}
end
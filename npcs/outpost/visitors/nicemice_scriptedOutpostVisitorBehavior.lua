require "/scripts/nicemice_util.lua"

function nicemice_scriptedOutpostVisitorBehavior(args, board)
	-- 2026 Aug 19 / this status effect is deprecated in favor of properly applying item directives
	-- status.setPersistentEffects("nicemice_recolorable_tail", {"nicemice_recolorable_tail"})
	return nicemice_setNPCBehavior(args.behavior)
end

local _update = update
function update(dt)
	_update(dt)
	
end
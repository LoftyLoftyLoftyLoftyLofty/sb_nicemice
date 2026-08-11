require "/scripts/nicemice_util.lua"

function nicemice_scriptedCrewMemberBehavior(args, board)
	status.setPersistentEffects("nicemice_recolorable_tail", {"nicemice_recolorable_tail"})
	return nicemice_setNPCBehavior(args.behavior)
end

--  Avoidance-zone handling used to live here, which is why it was crew-only.
--  It now lives in /npcs/nicemice_npcHooks.lua alongside the other shared update
--  work, so guards, quartermasters and villagers get it too. Entry behaviors opt
--  in by passing returnBehavior to nicemice_initHooks.

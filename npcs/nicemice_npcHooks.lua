require "/scripts/rect.lua"
require "/scripts/nicemice_util.lua"

function statusReply(args)

	--args will contain
	--	_senderId
	--	_requestedData : list of status properties we want
	if world.entityExists(args._senderId) then
		local data = {}
		for k in ipairs(args._requestedData) do
			data[k] = status.statusProperty(k, nil)
		end
		world.sendEntityMessage(args._senderId, "nicemice_npcStatusQueryReply", data)
	end
end

function itemsReply(args)
	--args will contain
	--  _senderId
	if world.entityExists(args._senderId) then
		local data = {}
		local slots = { "head", "headCosmetic", "chest", "chestCosmetic", "legs", "legsCosmetic", "back", "backCosmetic", "primary", "alt" }
		for i, v in ipairs(slots) do
			data[v] = npc.getItemSlot(v)
		end
		data["_senderId"] = entity.id()
		world.sendEntityMessage(args._senderId, "nicemice_npcItemsReply", data)
	end
end

function nicemice_initHooks(args, board)

	message.setHandler
	(
		"nicemice_npcStatusQuery",
		function(_, _, a)
			statusReply(a)
		end
	)
	
	message.setHandler
	(
		"nicemice_npcItemsQuery",
		function(_, _, a)
			itemsReply(a)
		end
	)
	
	--script.setUpdateDelta(1)
	--status.clearPersistentEffects("nicemice_mcontroller_hook")

	return true
end

function nicemice_npc_move(args, board, node)
	local bounds = mcontroller.boundBox()

	local startTime = os.clock()
	while true do

		--  exit movement if we hit our timeout
		if args.timeout ~= nil then
			if (os.clock() - startTime) > args.timeout then
				return true
			end
		end

		--  not sure if we really need the 'force walking backwards' flag for the applications this is used for. TODO test
		local direction = util.toDirection(args.direction)
		local run = args.run
		if config.getParameter("pathing.forceWalkingBackwards", false) then
			if run == true then 
				run = mcontroller.movingDirection() == mcontroller.facingDirection() 
			end
		end

		--  this probably softlocks the behavior, but it shouldn't happen. TODO test
		if args.direction == nil then 
			return false 
		end
		
		local position = mcontroller.position()
		--  align bottom of the bound box with the ground
		position = {position[1], math.ceil(position[2]) - (bounds[2] % 1)} 

		local move = false
		--  Check for walls
		for _,yDir in pairs({0, -1, 1}) do
		--  util.debugRect(rect.translate(bounds, vec2.add(position, {direction * 0.2, yDir})), "yellow")
			if not world.rectTileCollision(rect.translate(bounds, vec2.add(position, {direction * 0.2, yDir}))) then
				move = true
				break
			end
		end

		-- Also specifically check for a dumb collision geometry edge case where the ground goes like:
		--
		--        #
		-- ###### ######
		-- #############
		local boundsEnd = direction > 0 and bounds[3] or bounds[1]
		local wallPoint = {position[1] + boundsEnd + direction * 0.5, position[2] + bounds[2] + 0.5}
		local groundPoint = {position[1] + boundsEnd - direction * 0.5, position[2] + bounds[2] - 0.5}
		if world.pointTileCollision(wallPoint) and not world.pointTileCollision(groundPoint) then
			move = false
		end

		if args.respectLedges then
			-- Check for ground for the entire length of the bound box
			-- Makes it so the entity can stop before a ledge
			if move then
				local boundWidth = bounds[3] - bounds[1]
				local groundRect = rect.translate({bounds[1], bounds[2] - 1.0, bounds[3], bounds[2]}, position)
				local y = 0
				for x = boundWidth % 1, math.ceil(boundWidth) do
					move = false
					for _,yDir in pairs({0, -1, 1}) do
						--util.debugRect(rect.translate(groundRect, {direction * x, y + yDir}), "blue")
						if world.rectTileCollision(rect.translate(groundRect, {direction * x, y + yDir}), {"Null", "Block", "Dynamic", "Platform"}) then
							move = true
							y = y + yDir
							break
						end
					end
					if move == false then 
						break end
					end
				end
			end

			if move then
			moved = true
			mcontroller.controlMove(direction, run)
			if not self.setFacingDirection then 
				controlFace(direction) 
			end
		else
			if moved then
				mcontroller.setXVelocity(0)
				mcontroller.clearControls()
			end
			return true
		end
		coroutine.yield()
	end
end
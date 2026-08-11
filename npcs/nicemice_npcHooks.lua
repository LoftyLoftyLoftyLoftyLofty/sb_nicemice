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

-- WEAPON PRESERVATION ACROSS GRADUATION / RESPAWN
--
-- recruitable.generateRecruitInfo() hands the replacement NPC
-- `storage = preservedStorage()`, and preservedStorage() carries exactly one
-- item channel: storage.itemSlots. The only function that writes that table is
-- setNpcItemSlot(), and the only thing routinely calling it is
-- recruitable.setUniform() -- which is why clothing survives graduation and
-- weapons do not. Items rolled from the npctype's `items` table are applied
-- engine-side, and swapItemSlots() (drawing/holstering) calls npc.setItemSlot
-- directly, bypassing storage entirely. So the replacement NPC re-rolls its
-- weapon from its own npctype table and the original is lost.
--
-- Writing the weapon slots through setNpcItemSlot() once puts them in
-- storage.itemSlots alongside the uniform, and restorePreservedStorage() then
-- re-applies them to the new NPC.
--
-- TIMING MATTERS. For the first moments of an NPC's life npc.getItemSlot
-- returns a descriptor whose `parameters` are still empty. Storing THAT would
-- be worse than storing nothing: the replacement would inherit a seedless
-- descriptor, root.itemConfig would re-roll its abilities, and
-- descriptorIsResolvable() in nicemice_wandstaff.lua would (correctly) refuse
-- to resolve intent from it -- so the mouse would quietly stop using its staff
-- abilities altogether. Hence the retry: only record a slot once its
-- descriptor actually carries the roll it was built with.
local nicemice_weaponSlots = { "primary", "alt", "sheathedprimary", "sheathedalt" }

local function nicemice_descriptorCarriesRoll(descriptor)
	local parameters = descriptor and descriptor.parameters
	if parameters == nil then return false end
	return parameters.seed ~= nil
		or parameters.primaryAbilityType ~= nil
		or parameters.altAbilityType ~= nil
end

-- Returns true once every slot has been dealt with and there is no reason to
-- look again.
local function nicemice_preserveWeaponSlots()
	local settled = true

	for _, slot in ipairs(nicemice_weaponSlots) do
		local descriptor = npc.getItemSlot(slot)

		if descriptor == nil or descriptor.name == nil then
			-- Genuinely empty slot. Nothing to preserve, nothing to wait for.
		elseif nicemice_descriptorCarriesRoll(descriptor) then
			local stored = (storage.itemSlots or {})[slot]
			local storedSeed = stored and stored.parameters and stored.parameters.seed
			if storedSeed ~= descriptor.parameters.seed then
				-- Re-setting the slot with the descriptor it already holds is a
				-- no-op for the NPC; the point is the storage write inside.
				setNpcItemSlot(slot, descriptor)
			end
		else
			-- Descriptor is still bare. Leave it alone and check again later.
			settled = false
		end
	end

	return settled
end

function nicemice_installWeaponPreservation()
	if self.nicemice_weaponPreservationInstalled then return end
	self.nicemice_weaponPreservationInstalled = true

	local previousUpdate = update
	local settled = false
	local recheckTimer = 0
	-- A stowed weapon's descriptor may stay bare for as long as it is stowed,
	-- so "wait until every slot is resolvable" can never finish. Give up after
	-- a while rather than polling for the entity's whole life; anything still
	-- bare by then is a slot we cannot safely record anyway.
	local giveUpTimer = 30.0

	update = function(dt)
		previousUpdate(dt)

		if settled then return end

		giveUpTimer = giveUpTimer - dt
		recheckTimer = recheckTimer - dt
		if recheckTimer > 0 then return end
		recheckTimer = 1.0

		settled = nicemice_preserveWeaponSlots() or giveUpTimer <= 0
	end
end

function nicemice_initHooks(args, board)

	nicemice_installWeaponPreservation()

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
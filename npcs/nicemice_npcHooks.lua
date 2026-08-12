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
--  AVOIDANCE ZONES
--
--  Mice wander freely, which is a problem around a few specific spots -- most
--  obviously the captain's chair, where a mouse parks itself between the player
--  and the controls.
--
--  The direction to walk is DECLARED by the object, not inferred from geometry.
--  Working it out by comparing positions is wrong on any ship whose layout we do
--  not know; on the M.A.U.S. cargo ship it sent crew rightwards onto the
--  windshield, where they got stuck. Ship authors tag the objects they want mice
--  to keep clear of, and say which way is safe:
--
--      avoidMe-goLeft   ->  always walk left from here
--      avoidMe-goRight  ->  always walk right from here
--      avoidMe          ->  walk away from the object, for spots where either
--                           direction is fine
--
--  Tag the chair, tag a hazard, tag the airlock -- whatever a given ship needs.
--  A modded ship only needs a .patch adding a tag to its own objects.
--
--  Directional tags win over plain avoidMe, and the NEAREST tagged object wins
--  overall, so a mouse between two of them reacts to the one it is standing on.
--
--  This lives here rather than in one npc class's script because every nicemice
--  entry behavior already loads this file and calls nicemice_initHooks. Pass a
--  returnBehavior to initHooks to switch it on -- that is the behavior the mouse
--  goes back to once it has finished walking away. Omit it and avoidance is off,
--  so nothing gains this behavior by accident.

local NICEMICE_AVOID_ANY = "avoidMe"
local NICEMICE_AVOID_LEFT = "avoidMe-goLeft"
local NICEMICE_AVOID_RIGHT = "avoidMe-goRight"

local NICEMICE_RUN_LEFT = "nicemice_crew_avoidCaptainsChair_npcRunLeft"
local NICEMICE_RUN_RIGHT = "nicemice_crew_avoidCaptainsChair_npcRunRight"

local NICEMICE_AVOID_SCAN_INTERVAL = 3
local NICEMICE_AVOID_SCAN_RADIUS = 10

--  Which way this object says to go, or nil if it is not an avoidance object.
--  Returns "left", "right", or "away".
local function nicemice_avoidDirectionFor(objectId)
	local tags = world.getObjectParameter(objectId, "itemTags")
	if tags == nil then return nil end

	local direction = nil
	for _, tag in ipairs(tags) do
		if tag == NICEMICE_AVOID_LEFT then
			return "left"
		elseif tag == NICEMICE_AVOID_RIGHT then
			return "right"
		elseif tag == NICEMICE_AVOID_ANY then
			--  keep looking: an explicit direction on the same object wins
			direction = "away"
		end
	end
	return direction
end

--  Crew recruitment state does not reliably survive the behavior swap: a mouse
--  that was following the player comes back wandering with its weapon out. The
--  exact mechanism is not established -- storage is supposed to persist across a
--  swap -- so rather than guess, the state is snapshotted going out and put back
--  coming in. Preserving it works whatever is clearing it.
--
--  Both flags are captured because recruitable has three states, not two:
--    behaviorFollowing true                       -> following the player
--    behaviorFollowing false, followingOwner true -> told to hold position
--    both false                                   -> dismissed to this world
--  Restoring from one flag alone would silently promote "hold position" back to
--  "follow", which is a worse bug than the one being fixed.
function nicemice_saveFollowState()
	if recruitable == nil or recruitable.ownerUuid() == nil then return end
	storage.nicemice_savedBehaviorFollowing = storage.behaviorFollowing
	storage.nicemice_savedFollowingOwner = storage.followingOwner
end

local function nicemice_restoreFollowState()
	if recruitable == nil or recruitable.ownerUuid() == nil then return end

	local behaviorFollowing = storage.nicemice_savedBehaviorFollowing
	local followingOwner = storage.nicemice_savedFollowingOwner
	if behaviorFollowing == nil and followingOwner == nil then return end

	storage.nicemice_savedBehaviorFollowing = nil
	storage.nicemice_savedFollowingOwner = nil

	--  re-apply through recruitable rather than writing storage directly: these
	--  calls also restore persistence, keepAlive and damage team, which are set
	--  together with the flags and would otherwise drift out of sync.
	--  skipNotification, because the mouse is not being re-recruited.
	if behaviorFollowing then
		recruitable.confirmFollow(true)
	elseif followingOwner then
		recruitable.confirmUnfollowBehavior(true)
	else
		recruitable.confirmUnfollow(true)
	end
end

local function nicemice_avoidanceScan()
	local curPos = mcontroller.position()
	if curPos == nil then return end

	local objects = world.objectQuery(curPos, NICEMICE_AVOID_SCAN_RADIUS)
	if objects == nil then return end

	local closestId = nil
	local closestDirection = nil
	local closestDistance = nil

	for _, objectId in pairs(objects) do
		local direction = nicemice_avoidDirectionFor(objectId)
		if direction ~= nil then
			local objectPos = world.entityPosition(objectId)
			if objectPos ~= nil then
				local distance = world.magnitude(objectPos, curPos)
				if closestDistance == nil or distance < closestDistance then
					closestId = objectId
					closestDirection = direction
					closestDistance = distance
				end
			end
		end
	end

	if closestId == nil then return end

	--  "away" is the only case that still infers a direction, and only because
	--  the object explicitly said either way is acceptable.
	if closestDirection == "away" then
		local objectPos = world.entityPosition(closestId)
		if objectPos == nil then return end
		if objectPos[1] < curPos[1] then
			closestDirection = "right"
		else
			closestDirection = "left"
		end
	end

	nicemice_saveFollowState()

	if closestDirection == "right" then
		nicemice_setNPCBehavior(NICEMICE_RUN_RIGHT)
	else
		nicemice_setNPCBehavior(NICEMICE_RUN_LEFT)
	end
end

--  Where a mouse goes after it has finished walking away.
--
--  The run-away behaviors used to name nicemice_scriptedCrewMemberBehavior
--  directly, which is why avoidance was crew-only: a guard sent there would come
--  back as a crew member. Storing it instead lets one pair of run behaviors
--  serve every npc class. storage rather than self, so it survives the behavior
--  swap regardless of how the swap is implemented.
function nicemice_returnFromAvoid(args, board)
	local behavior = storage.nicemice_returnBehavior
	if behavior == nil then return false end
	nicemice_restoreFollowState()
	return nicemice_setNPCBehavior(behavior)
end

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

	local avoidTimer = 999

	update = function(dt)
		previousUpdate(dt)

		--  only runs when an entry behavior supplied a returnBehavior
		if storage.nicemice_returnBehavior ~= nil then
			avoidTimer = avoidTimer + dt
			if avoidTimer > NICEMICE_AVOID_SCAN_INTERVAL then
				avoidTimer = 0
				nicemice_avoidanceScan()
			end
		end

		if settled then return end

		giveUpTimer = giveUpTimer - dt
		recheckTimer = recheckTimer - dt
		if recheckTimer > 0 then return end
		recheckTimer = 1.0

		settled = nicemice_preserveWeaponSlots() or giveUpTimer <= 0
	end
end

--  param returnBehavior -- optional. Enables avoidance-zone handling and names
--                          the behavior to come back to afterwards.
function nicemice_initHooks(args, board)

	if args ~= nil and args.returnBehavior ~= nil and args.returnBehavior ~= "" then
		storage.nicemice_returnBehavior = args.returnBehavior
	end

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

--  param direction
--  param run
--  param respectLedges
--  param timeout -- seconds of walking before giving up. MUST be declared in
--                   nicemice.nodes or it arrives nil and is ignored.
function nicemice_npc_move(args, board, nodeId, dt)
	local bounds = mcontroller.boundBox()

	--  Elapsed time comes from the dt the engine hands back through
	--  coroutine.yield, accumulated here.
	--
	--  This used to read os.clock(), which is CPU time consumed by the process,
	--  not wall time -- it crawls forward far slower than real seconds, so a
	--  5 second timeout effectively never expired and the mouse walked until it
	--  hit a ledge. (os is also not guaranteed to exist in the sandbox at all.)
	--  The old loop additionally threw away the yield's return value, so dt was
	--  not available even in principle.
	local elapsed = 0
	local moved = false

	--  Ledge respect is dropped if it keeps us pinned. See the blocked branch at
	--  the bottom of the loop for why.
	local respectLedges = args.respectLedges
	local blockedTime = 0
	local ledgePatience = args.ledgePatience or 1.0

	while true do

		--  exit movement if we hit our timeout
		if args.timeout ~= nil then
			if elapsed > args.timeout then
				mcontroller.setXVelocity(0)
				mcontroller.clearControls()
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

		if respectLedges then
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
			blockedTime = 0
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

			blockedTime = blockedTime + dt

			if blockedTime > ledgePatience then
				if respectLedges then
					--  Every ground test above is world.rectTileCollision, which
					--  only sees TILES. An object with its own collision poly --
					--  a diagonal docking field, say -- is invisible to it, so an
					--  npc standing on one reads as having no ground beneath it
					--  and refuses to take a single step. It then gives up, gets
					--  re-triggered by the next avoidance scan, and repeats
					--  forever while appearing to "try".
					--
					--  So being pinned is not accepted as final. After a moment
					--  of getting nowhere, walk anyway. Stepping off an object
					--  onto the deck below is the outcome we wanted; standing on
					--  the thing forever is not.
					respectLedges = false
					blockedTime = 0
				else
					--  Blocked even without ledge respect: that is a real wall,
					--  and no amount of patience gets through it.
					return true
				end
			end
		end
		dt = coroutine.yield() or 0
		elapsed = elapsed + dt
	end
end
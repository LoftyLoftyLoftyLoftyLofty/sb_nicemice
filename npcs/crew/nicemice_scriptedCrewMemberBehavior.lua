require "/scripts/nicemice_util.lua"

function nicemice_scriptedCrewMemberBehavior(args, board)
	status.setPersistentEffects("nicemice_recolorable_tail", {"nicemice_recolorable_tail"})
	return nicemice_setNPCBehavior(args.behavior)
end

local _update = update
function update(dt)
	_update(dt)
	
	avoidCaptainsChair(dt)
end

--  AVOIDANCE ZONES
--
--  Crew wander freely, which is a problem around a few specific spots on a ship
--  -- most obviously the captain's chair, where a mouse standing in front of it
--  parks itself between the player and the controls.
--
--  This used to key off the "captainschair" tag and work out which way to run by
--  comparing positions: chair on our left, run right, and vice versa. That is
--  wrong on any ship whose layout we do not know. On the M.A.U.S. cargo ship it
--  sent crew rightwards onto the windshield, where they got stuck.
--
--  So the direction is not inferred any more, it is declared. Ship authors tag
--  the objects they want crew to keep clear of, and say which way is safe:
--
--      avoidMe-goLeft   ->  always walk left from here
--      avoidMe-goRight  ->  always walk right from here
--      avoidMe          ->  walk away from the object (the old behaviour, for
--                           cases where either direction is fine)
--
--  Tag the chair, tag a hazard, tag the airlock -- whatever a given ship needs.
--  Nothing is assumed about layout, so a modded ship only needs a .patch adding
--  a tag to its own objects.
--
--  Directional tags win over plain avoidMe, and the NEAREST tagged object wins
--  overall, so a mouse between two tagged objects reacts to the one it is
--  actually standing on.

local NICEMICE_AVOID_ANY = "avoidMe"
local NICEMICE_AVOID_LEFT = "avoidMe-goLeft"
local NICEMICE_AVOID_RIGHT = "avoidMe-goRight"

local NICEMICE_RUN_LEFT = "nicemice_crew_avoidCaptainsChair_npcRunLeft"
local NICEMICE_RUN_RIGHT = "nicemice_crew_avoidCaptainsChair_npcRunRight"

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

local timeSinceLastCaptainChairScan = 999
function avoidCaptainsChair(dt)
--  scan every 5 sec
	timeSinceLastCaptainChairScan = timeSinceLastCaptainChairScan + dt
	if timeSinceLastCaptainChairScan <= 5 then return end

	--  reset timer
	timeSinceLastCaptainChairScan = 0

	local curPos = mcontroller.position()
	if curPos == nil then return end

	--  query nearby objects
	local objects = world.objectQuery(curPos, 5)
	if objects == nil then return end

	--  find the NEAREST tagged object, so a mouse standing between two of them
	--  reacts to the one it is actually on rather than whichever the query
	--  happened to list first
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

	--  "away" keeps the old position-comparison behaviour, for objects where
	--  either direction is fine. The explicit tags skip it entirely -- that is
	--  the whole point: on an unfamiliar ship layout, guessing is what walked
	--  crew onto the windshield.
	if closestDirection == "away" then
		local objectPos = world.entityPosition(closestId)
		if objectPos == nil then return end
		if objectPos[1] < curPos[1] then
			closestDirection = "right"
		else
			closestDirection = "left"
		end
	end

	if closestDirection == "right" then
		nicemice_setNPCBehavior(NICEMICE_RUN_RIGHT)
	else
		nicemice_setNPCBehavior(NICEMICE_RUN_LEFT)
	end
end

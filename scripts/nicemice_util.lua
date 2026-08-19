local NICEMICE_TAIL_TAG = "nicemice_recolorable_tail"

function nicemice_getPlayerSkinDirectives()
	return nicemice_getEntitySkinDirectives(entity.id())
end

function nicemice_getEntitySkinDirectives(id)
	local portrait = world.entityPortrait(id, "full")
	if not portrait then return nil end
	for key, value in pairs(portrait) do
		if portrait[key].image and string.find(portrait[key].image, "body.png") then
			local body_image =  portrait[key].image
			local directive_location = string.find(body_image, "replace")
			-- Not every species' body layer carries replace directives; bail out
			-- instead of feeding nil to string.sub and erroring the whole context.
			if not directive_location then return nil end
			local directives = string.sub(body_image,directive_location)
			return directives
		end
	end
	return nil
end

-- Checks an ItemDescriptor for a tag, preferring the instance's own itemTags
-- and only paying for root.itemConfig when the instance doesn't answer.
function nicemice_itemHasTag(item, tag)
	if item.parameters and item.parameters.itemTags then
		for _, t in ipairs(item.parameters.itemTags) do
			if t == tag then return true end
		end
	end

	local baseConfig = root.itemConfig(item)
	if baseConfig and baseConfig.config and baseConfig.config.itemTags then
		for _, t in ipairs(baseConfig.config.itemTags) do
			if t == tag then return true end
		end
	end

	return false
end

-- Applies skin directives to any recolorable tail sitting in the given slots.
--
-- getSlot/setSlot are passed in because the player and NPC equipment APIs are
-- different namespaces with different names for the same operation:
--   player.equippedItem / player.setEquippedItem
--   npc.getItemSlot     / npc.setItemSlot
-- Both take/return plain ItemDescriptors, so everything below this line is
-- identical for the two contexts.
--
-- Returns true if at least one item was actually written back.
function nicemice_applyTailDirectives(directives, slots, getSlot, setSlot)
	if not directives then return false end

	local applied = false

	for _, slotName in ipairs(slots) do
		local item = getSlot(slotName)

		if item and nicemice_itemHasTag(item, NICEMICE_TAIL_TAG) then
			-- NPC items built from an npctype's item list often arrive with no
			-- parameters table at all, so don't assume one exists.
			item.parameters = item.parameters or {}

			-- Check if directives need updating
			if item.parameters.nicemiceDirectives ~= directives then
				item.parameters.nicemiceDirectives = directives

				-- Dynamic Asset Lookup: Safely extract the genuine base inventory icon name
				local baseConfig = root.itemConfig(item)
				local baseIcon = "tailicon.png" -- Fallback default
				if baseConfig and baseConfig.config and baseConfig.config.inventoryIcon then
					baseIcon = baseConfig.config.inventoryIcon
				end

				-- Reapply directives cleanly over the item's actual native icon
				item.parameters.inventoryIcon = baseIcon .. "?" .. directives

				-- Force the client to use the default graphics path for the item frame
				item.parameters.maleFrames = nil
				item.parameters.femaleFrames = nil

				-- Slap some directives on that bad boy
				item.parameters.directives = "?" .. directives

				-- npc.setItemSlot returns false on a bad slot name;
				-- player.setEquippedItem returns nil. Treat only false as failure.
				if setSlot(slotName, item) ~= false then
					applied = true
				end
			end
		end
	end

	return applied
end

function nicemice_setNPCBehavior(b)
	--copypasted from npcs/bmain.lua @ line 34
	--
	--  Use self.behaviorConfig rather than reading the parameter fresh. bmain
	--  builds self.behaviorConfig by layering the NPC's personality over the
	--  npctype's behaviorConfig:
	--
	--      self.behaviorConfig = config.getParameter("behaviorConfig", {})
	--      if personality().behaviorConfig then
	--        self.behaviorConfig = applyDefaults(personality().behaviorConfig, self.behaviorConfig)
	--      end
	--
	--  Reading config.getParameter directly here threw the personality layer
	--  away on every swap, so a mouse that had run away from an avoidance zone
	--  came back with default wander and idle timings instead of its own.
	self.behavior = behavior.behavior(b, self.behaviorConfig or config.getParameter("behaviorConfig", {}), _ENV)
    self.board = self.behavior:blackboard()
    self.board:setPosition("spawn", storage.spawnPosition)
	return true
end

function nicemice_initWorldId()
	if not world.getProperty("nicemice_worldId") then
		world.setProperty("nicemice_worldId", sb.makeUuid())
	end
end

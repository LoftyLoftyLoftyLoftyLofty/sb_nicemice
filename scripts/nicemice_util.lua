function nicemice_getPlayerSkinDirectives()
	return nicemice_getEntitySkinDirectives(entity.id())
end

function nicemice_getEntitySkinDirectives(id)
	local portrait = world.entityPortrait(id, "full")
	if not portrait then return nil end
	for key, value in pairs(portrait) do
		if string.find(portrait[key].image, "body.png") then
			local body_image =  portrait[key].image
			local directive_location = string.find(body_image, "replace")
			local directives = string.sub(body_image,directive_location)
			return directives
		end
	end
	return nil
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
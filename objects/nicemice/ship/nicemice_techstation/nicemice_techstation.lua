function init()

	if config.getParameter("npcMode") then 
		object.setInteractive(false)
		return 
	end
	
	message.setHandler("activateShip", function()
		animator.playSound("shipUpgrade")
		world.setProperty("nicemice_needsWakeUpDialog",true)
	end)

	message.setHandler("wakePlayer", function()
		self.dialog = config.getParameter("dialog.wakePlayer")
		self.dialogTimer = 0.0
		self.dialogInterval = 14.0
		self.drawMoreIndicator = false
		object.setOfferedQuests({})
	end)

	-- (\_/) Fix crash when placing 2x (or more) S.A.I.L
	--  		Lofty 2025/05/13
	-- 
	--  When placing any techstation, verify whether or not an object
	--  with the uniqueId "techstation" already exists in the world.
	--  
	--  If another object already exists with this uniqueId, save its
	--  entityId locally.
	-- 
	--  If another object does not already exist with this uniqueId,
	--  update our uniqueId for quest tracking.
	--
	--  Periodically check on the last known uniqueId in case it has
	--  been destroyed. If it has been destroyed, run the search again.

	self.findTechStation = coroutine.create(findTechstationByUniqueId)
	self.lastKnownTechStation = nil
	
	-- (\_/) Scripted Artificial Intelligence Lattice integration begins here
	if usingCustomSAIL() then
		self.fallback = false
		object.setConfigParameter("retainScriptStorageInItem", true)
		object.setConfigParameter("animationScripts", {"/objects/scripts/changeObjectSprite.lua"})
		storage.data = storage.data or {}
		storage.imageconfig = storage.imageconfig or nil
		object.setAnimationParameter("imageConfig", storage.imageconfig) 
		message.setHandler
		(
			"setFallback", 
			function(_,_, value) 
				self.fallback = value 
			end
		)
		message.setHandler
		(
			"storeData", 
			function(_,_, widget, data) 
				storage.data[widget] = data 
			end
		)
		message.setHandler
		(
			"returnData", 
			function() 
				return storage.data 
			end
		)
		message.setHandler
		(
			"screwdriverInteraction", 
			function() 
				return {config.getParameter("screwdriverInteractAction"), config.getParameter("screwdriverInteractData")} 
			end
		)
		message.setHandler
		(
			"setImage", 
			function(_,_, imageconfig)
				storage.imageconfig = imageconfig
				object.setAnimationParameter("imageConfig", imageconfig) 
			end
		)
		message.setHandler
		(
			"setInterfaceObj", 
			function(_,_, itemDesc) 
				storage.interfaceObjIDesc = itemDesc 
			end
		)
		message.setHandler
		(
			"gibInterfaceObj", 
			function() 
				return storage.interfaceObjIDesc 
			end
		)
	end
end

function usingCustomSAIL()
	if root.itemConfig("screwdriver") ~= nil then
		return true
	end
	return false
end

function findTechstationByUniqueId()
	local id = "techstation"
	-- (\_/) see also: loadBountyManager in bounty.lua
	while true do
		local findManager = world.findUniqueEntity(id)
		while not findManager:finished() do
			coroutine.yield()
		end
		if findManager:succeeded() then
			--  findManager:result() returns Vec2f position of entity in question
			--  fire an entityQuery and iterate results to pinpoint desired target
			local wQuery = world.entityQuery(findManager:result(), 1, {})
			for v in ipairs(wQuery) do
				if world.entityUniqueId(v) == id then
					self.lastKnownTechStation = v
					break
				end
			end
		else
			world.setUniqueId(entity.id(),id)
			self.lastKnownTechStation = entity.id()
		end
		coroutine.yield()
	end
end

function onInteraction()
	if self.dialogTimer then
		sayNext()
		return nil
	else
		if usingCustomSAIL() then
			if not self.fallback then
				return {config.getParameter("interactAction"), config.getParameter("interactData")}
			else
				return {config.getParameter("fallbackInteractAction"), config.getParameter("fallbackInteractData")}
			end
		else
			return config.getParameter("vanillaInteractAction")
		end
	end
end

function sayNext()
	if self.dialog and #self.dialog > 0 then
		if #self.dialog > 0 then
		local options = 
		{
			drawMoreIndicator = self.drawMoreIndicator
		}
		self.dialogTimer = self.dialogInterval
		if #self.dialog == 1 then
			options.drawMoreIndicator = false
			self.dialogTimer = 0.0
		end
		object.sayPortrait(self.dialog[1][1], self.dialog[1][2], nil, options)
		table.remove(self.dialog, 1)
		return true
		end
	else
		self.dialog = nil
		return false
	end
end

function update(dt)
	
	if config.getParameter("npcMode") then 
		object.setInteractive(false)
		return 
	end
	
	if world.getProperty("nicemice_needsWakeUpDialog") then
		if self.talking == nil then
			self.talking = true
			self.dialog = config.getParameter("dialog.wakeUp")
			self.dialogTimer = 0.0
			self.dialogInterval = 5.0
			self.drawMoreIndicator = true
			object.setOfferedQuests({})
		end
	end
	if self.dialogTimer then
		self.dialogTimer = math.max(self.dialogTimer - dt, 0.0)
		if self.dialogTimer == 0 and not sayNext() then
			self.dialogTimer = nil
			world.setProperty("nicemice_needsWakeUpDialog", false)
			object.setOfferedQuests(config.getParameter("offeredQuests"))
		end
	end
	--  (\_/) resume async find if necessary
	if self.lastKnownTechStation == nil or not world.entityExists(self.lastKnownTechStation) then
		coroutine.resume(self.findTechStation)
	end
end
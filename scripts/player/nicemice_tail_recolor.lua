local _init = init
local _update = update
local _uninit = uninit

function init()
	_init()
	
	-- +0.5 is where drowning begins
	-- -2.5 is where drowning begins
	-- we can infer from these numbers that -1.25 is our center
	-- the boundingbox encompasses 22 pixels vertically coming upward from our feet
	-- mouth position is +16 pixels from our feet
	-- 16 / 22 = 0.727272 R
	-- 72% / 2 = 36
	-- 36% of 3.0 = 1.08
	-- -1.25 + 1.08 = -0.17
	status.setStatusProperty("mouthPosition",{0,-0.17})
end

function update(dt)
	_update(dt)
	if player.species() == "nicemice" then
		if not player.getProperty("nicemice_starterTail") then
			player.giveItem("nicemice_tail_mouse")
			player.setProperty("nicemice_starterTail", true)
		end
		
		-- 2026 Aug 19 / this status effect is deprecated in favor of properly applying item directives
		-- status.setPersistentEffects("nicemice_recolorable_tail", {"nicemice_recolorable_tail"})
	end
end

function uninit()
	_uninit()
	
end
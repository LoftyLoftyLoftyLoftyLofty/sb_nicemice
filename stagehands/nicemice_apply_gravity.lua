require "/scripts/util.lua"
require "/scripts/rect.lua"
function init()
	gravity = config.getParameter("gravity") or 80.0
end

function update(dt)
	world.setDungeonGravity(0, gravity)
end
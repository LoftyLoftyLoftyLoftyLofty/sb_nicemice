-- this is a spliced version of the radiomessage script included by default,
-- modified to also set world fuel for npc ship worlds if the param is set in Tiled

require "/scripts/stagehandutil.lua"

function init()
	local fuel = config.getParameter("setFuelValue")
	if fuel then 
		world.setProperty("ship.fuel", fuel)
	end
	fuel = config.getParameter("setMaxFuelValue")
	if fuel then 
		world.setProperty("ship.maxFuel", fuel)
	end
	
	self.containsPlayers = {}
	self.radioMessages = config.getParameter("radioMessages") or {config.getParameter("radioMessage")}
end

function update(dt)
  local newPlayers = broadcastAreaQuery({includedTypes = {"player"}})
  local oldPlayers = table.concat(self.containsPlayers, ",")
  for _, id in pairs(newPlayers) do
    if not string.find(oldPlayers, id) then
      for _, message in ipairs(self.radioMessages) do
        world.sendEntityMessage(id, "queueRadioMessage", message)
      end
    end
  end
  self.containsPlayers = newPlayers
end
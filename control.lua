require "defines"
require "util"

-- ~yellow = 10, ~red =6
local outputThrottle = 10
local inputThrottle = 20
local railCheckThrottle = 120
local voidThrottle = 180
local energy_per_action = 8000
local idleDraw = 500
local dataVersion = 3

-- How many a chest can pull from a belt lane 0-8
local inputMultiplier = 8
-- Inventory to Inventory transfer stack size
local maxStackSize = 4

-- Cardinal Directions
local NORTH = defines.direction.north
local EAST = defines.direction.east
local SOUTH = defines.direction.south
local WEST = defines.direction.west

-- Adjacent tiles
function areaNorth(position) return {{position.x - 0.5, position.y - 1.5},{position.x + 0.5, position.y - 0.5}} end
function areaSouth(position) return {{position.x - 0.5, position.y + 0.5},{position.x + 0.5, position.y + 1.5}} end
function areaEast(position)  return {{position.x + 0.5, position.y - 0.5},{position.x + 1.5, position.y + 0.5}} end
function areaWest(position)  return {{position.x - 1.5, position.y - 0.5},{position.x - 0.5, position.y + 0.5}} end

-- Area around tile
function getBoundingBox(position, radius)
  return {{x=position.x-radius-.5,y=position.y-radius-.5},{x=position.x+radius+.5,y=position.y+radius+.5}}
end

-------------------
function InterfaceChest_Initialize(event)	
	if global.InterfaceChest_MasterList == nil then
		global.InterfaceChest_MasterList = {}
	end
	if global.InterfaceChest_DataVersion == nil then
		global.InterfaceChest_DataVersion = dataVersion
	end
end

-------------------
function InterfaceChest_Create(event)
	local entity = event.created_entity
	if entity.name == "interface-chest" or entity.name == "interface-chest-trash" then
		local nextIndex = #global.InterfaceChest_MasterList+1
		global.InterfaceChest_MasterList[nextIndex] = updateInterfaceChest(entity)
		--debugPrint("Interface Chest count: " .. nextIndex)
	end
	if isTransport(entity) or isInventory(entity) then
		handleChange(entity, 2)
	end
end

-------------------
function InterfaceChest_Rotated(event)
	local entity = event.entity 
	if isTransport(entity) or isInventory(entity) then
		handleChange(entity, 2)
	end
end

function InterfaceChest_Mined(event)
	local entity = event.entity 
	if isTransport(entity) or isInventory(entity) then
		scheduleUpdate(entity, 2)
	end
end

-------------------
function scheduleUpdate (entity, range)
	local masterList = global.InterfaceChest_MasterList
	for index=1, #masterList do
		local interfaceChest = masterList[index]
		local chest = interfaceChest.chest
		--debugPrint( entity.name .. " " .. serpent.block(entity.position))
		if chest and chest.valid and math.abs(chest.position.x - entity.position.x) < range and math.abs(chest.position.y - entity.position.y) < range then
			global.InterfaceChest_MasterList[index].dirty = true
		end
	end
end

-------------------
function handleChange (entity, range)
	local masterList = global.InterfaceChest_MasterList
	for index=1, #masterList do
		local interfaceChest = masterList[index]
		local chest = interfaceChest.chest
		--debugPrint( entity.name .. " " .. serpent.block(entity.position))
		if chest and chest.valid and math.abs(chest.position.x - entity.position.x) < range and math.abs(chest.position.y - entity.position.y) < range then
			global.InterfaceChest_MasterList[index] = updateInterfaceChest(interfaceChest.chest)
		end
	end
end

-------------------
function InterfaceChest_RunStep(event)
	if global.InterfaceChest_DataVersion ~= dataVersion then
		-- Find all this mod's chests and index them
		local trashCan = game.get_surface(1).find_entities_filtered{area={{-5000, -5000},{5000, 5000}}, name="interface-chest-trash"}
		local interfaceChests = game.get_surface(1).find_entities_filtered{area={{-5000, -5000},{5000, 5000}}, name="interface-chest"}
		local masterList = {}
		for index=1, #trashCan do
			local chest = trashCan[index]
			masterList[#masterList+1] = updateInterfaceChest(chest)
		end
		
		for index=1, #interfaceChests do
			local chest = interfaceChests[index]
			masterList[#masterList+1] = updateInterfaceChest(chest)
		end
		
		global.InterfaceChest_MasterList = masterList
		global.InterfaceChest_DataVersion = dataVersion	
	else
		local masterList = global.InterfaceChest_MasterList
		local chestsToDelete = {}
		for index=1, #masterList do
			local interfaceChest = masterList[index]
			local stagger = game.tick + index
			if 0 == (stagger % outputThrottle) then				
				if interfaceChest and interfaceChest.chest and interfaceChest.chest.valid then					
					if interfaceChest.power == nil or interfaceChest.power.valid == false then
						interfaceChest = updateInterfaceChest(interfaceChest.chest)
						global.InterfaceChest_MasterList[index] = interfaceChest
					else
						if interfaceChest.power and interfaceChest.power.valid and interfaceChest.power.energy >= (idleDraw) then
							interfaceChest.power.energy = interfaceChest.power.energy - idleDraw
						
							if interfaceChest.chest.name == "interface-chest-trash" then
								voidChest(interfaceChest, stagger, index)
							else
								-- No good way to check for nearby train, so if on rail check for train
								if interfaceChest.onRail and 0 == (stagger % railCheckThrottle) then
									interfaceChest = updateInterfaceChest(interfaceChest.chest)
									global.InterfaceChest_MasterList[index] = interfaceChest
								end

								local chestPosition = getBoundingBox(interfaceChest.chest.position, 0)
								if 0 == (stagger % inputThrottle) then							
									if interfaceChest.dirty then
										interfaceChest = updateInterfaceChest(interfaceChest.chest)
										global.InterfaceChest_MasterList[index] = interfaceChest
									end

									-- Input items Into Chest							
									for i=1, #interfaceChest.inputBelts do 
										local belt = interfaceChest.inputBelts[i]
										if belt.valid then
											if belt.type == "splitter" then
												if (belt.position.x == chestPosition[1].x and belt.position.y < chestPosition[1].y) or (belt.position.x == chestPosition[2].x and belt.position.y > chestPosition[1].y) or (belt.position.y == chestPosition[1].y and belt.position.x > chestPosition[2].x)  or (belt.position.y == chestPosition[2].y and belt.position.x < chestPosition[2].x) then
													beltToChest(belt, defines.transport_line.left_split_line, interfaceChest.chest, interfaceChest.power)
													beltToChest(belt, defines.transport_line.right_split_line, interfaceChest.chest, interfaceChest.power)
												else
													beltToChest(belt, defines.transport_line.secondary_left_split_line, interfaceChest.chest, interfaceChest.power)
													beltToChest(belt, defines.transport_line.secondary_right_split_line, interfaceChest.chest, interfaceChest.power)
												end
											else
											  beltToChest(belt, defines.transport_line.left_line, interfaceChest.chest, interfaceChest.power)
											  beltToChest(belt, defines.transport_line.right_line, interfaceChest.chest, interfaceChest.power)								
											end
										end 
									end

									-- Input Items from adjacent Inventories
									if #interfaceChest.inputBelts == 0 and #interfaceChest.outputBelts > 0 then							
										for i=1, #interfaceChest.inventories do
											local inventory = interfaceChest.inventories[i]
											if inventory and inventory.valid and inventory.get_inventory(1).is_empty() == false then
												sourceToTargetInventory(inventory, interfaceChest.chest, interfaceChest.power)
											end
										end
									end
								end
								
								-- Output items to adjacent Belts
								if interfaceChest.chest.get_inventory(1).is_empty() == false then					
									for i=1, #interfaceChest.outputBelts do
										local belt = interfaceChest.outputBelts[i]
										if belt.valid then
											if belt.type == "splitter" then
												if (belt.position.x == chestPosition[1].x and belt.position.y > chestPosition[1].y) or (belt.position.x == chestPosition[2].x and belt.position.y < chestPosition[1].y) or (belt.position.y == chestPosition[1].y and belt.position.x < chestPosition[2].x)  or (belt.position.y == chestPosition[2].y and belt.position.x > chestPosition[2].x) then
													chestToBelt(belt, defines.transport_line.left_line, interfaceChest.chest, interfaceChest.power)
													chestToBelt(belt, defines.transport_line.right_line, interfaceChest.chest, interfaceChest.power)
												else
													chestToBelt(belt, defines.transport_line.secondary_left_line, interfaceChest.chest, interfaceChest.power)
													chestToBelt(belt, defines.transport_line.secondary_right_line, interfaceChest.chest, interfaceChest.power)
												end
											else
											  chestToBelt(belt, defines.transport_line.left_line, interfaceChest.chest, interfaceChest.power)
											  chestToBelt(belt, defines.transport_line.right_line, interfaceChest.chest, interfaceChest.power)
											end
										end
									end
									
									-- Output items to adjacent inventories
									if #interfaceChest.outputBelts == 0 and #interfaceChest.inputBelts > 0 then
										for i=1, #interfaceChest.inventories do 
											local inventory = interfaceChest.inventories[i]
											sourceToTargetInventory(interfaceChest.chest, inventory, interfaceChest.power)
										end
									end
								end
							end
						end
					end
				else	
					if interfaceChest.power and interfaceChest.power.valid then
						interfaceChest.power.destroy()
					end
					chestsToDelete[#chestsToDelete+1] = index
				end
			end
		end
		-- Clean up Dead Chests
		for index=1, #chestsToDelete do			
			local deleteKey = chestsToDelete[index]
			table.remove(global.InterfaceChest_MasterList, deleteKey)			
		end
	end
end

function updateInterfaceChest(chest)
	local center = getBoundingBox(chest.position, 0)
	local entities = game.get_surface(1).find_entities(getBoundingBox(chest.position, 1))
	local gridTransport = {}
	local gridInventory = {}
	local isRail = false
	local powerDraw
		
	for index=1, #entities do 
		local entity = entities[index]
		if entity.type ~= "decorative" then
			if isRail == false and entity.type == "straight-rail" then
				isRail = true
			elseif entity.name == "interface-chest-power" and entity.position.x >= center[1].x and entity.position.x <= center[2].x and entity.position.y >= center[1].y and entity.position.y <= center[2].y then
				powerDraw = entity
			else
				-- North
				if entity.position.x >= center[1].x and entity.position.x <= center[2].x and entity.position.y < center[1].y then
					if isTransport(entity) then gridTransport.north = entity end
					if isInventory(entity) then gridInventory.north = entity end
				-- South
				elseif entity.position.x >= center[1].x and entity.position.x <= center[2].x and entity.position.y > center[2].y then		
					if isTransport(entity) then gridTransport.south = entity end
					if isInventory(entity) then gridInventory.south = entity end
				-- East
				elseif entity.position.x > center[2].x and entity.position.y >= center[1].y and entity.position.y <= center[2].y then
					if isTransport(entity) then gridTransport.east = entity end
					if isInventory(entity) then gridInventory.east = entity end
				-- West
				elseif entity.position.x < center[1].x and entity.position.y >= center[1].y and entity.position.y <= center[2].y then
					if isTransport(entity) then gridTransport.west = entity end
					if isInventory(entity) then gridInventory.west = entity end
				end
							
				-- North West
				if entity.position.x <= center[1].x and entity.position.y <= center[1].y then
					if isTransport(entity) then gridTransport.northWest = entity end
					if isTrain(entity) then gridInventory.northWest = entity end
				-- North East
				elseif entity.position.x >= center[2].x and entity.position.y <= center[1].y then
					if isTransport(entity) then gridTransport.northEast = entity end
					if isTrain(entity) then gridInventory.northEast = entity end
				-- South West
				elseif entity.position.x <= center[1].x and entity.position.y >= center[2].y then
					if isTransport(entity) then gridTransport.southWest = entity end
					if isTrain(entity) then gridInventory.southWest = entity end
				-- South East
				elseif entity.position.x >= center[2].x and entity.position.y >= center[2].y then
					if isTransport(entity) then gridTransport.southEast = entity end
					if isTrain(entity) then gridInventory.southEast = entity end
				end
			end
		end
	end
	
	if powerDraw == nil then
		powerDraw = chest.surface.create_entity{name="interface-chest-power", position=chest.position, force=game.players[1].force}		
	end
	
	return {chest = chest, inputBelts = getInputBelts(gridTransport), outputBelts = getOutputBelts(gridTransport), inventories = getInventories(gridInventory), onRail = isRail, dirty = false, power = powerDraw}
end

function voidChest(interfaceChest, stagger, index)
	if 0 == (stagger % inputThrottle) then	
		if interfaceChest.chest and interfaceChest.chest.valid and interfaceChest.power and interfaceChest.power.valid and interfaceChest.power.energy >= energy_per_action then
			if interfaceChest.dirty then
				interfaceChest = updateInterfaceChest(interfaceChest.chest)
				global.InterfaceChest_MasterList[index] = interfaceChest
			end
			
			if 0 == (stagger % voidThrottle) then		
				interfaceChest.chest.get_inventory(1).clear()
				interfaceChest.power.energy = interfaceChest.power.energy - energy_per_action
			end
			
			for i=1, #interfaceChest.inputBelts do 
				local belt = interfaceChest.inputBelts[i]
				if belt.valid then
					if belt.type == "splitter" then	
						if (belt.position.x > interfaceChest.chest.position.x and belt.position.y > interfaceChest.chest.position.y) or (belt.position.x < interfaceChest.chest.position.x and belt.position.y < interfaceChest.chest.position.y) then
							beltToVoid(belt, defines.transport_line.left_split_line, interfaceChest.power)
							beltToVoid(belt, defines.transport_line.right_split_line, interfaceChest.power)
						else
							beltToVoid(belt, defines.transport_line.secondary_left_split_line, interfaceChest.power)
							beltToVoid(belt, defines.transport_line.secondary_right_split_line, interfaceChest.power)
						end
					else
					  beltToVoid(belt, defines.transport_line.left_line, interfaceChest.power)
					  beltToVoid(belt, defines.transport_line.right_line, interfaceChest.power)
					end
				end
			end
		end
	end
end


function beltToVoid(belt, laneNumber, power)
	if power and power.valid and power.energy >= energy_per_action then
		local lane = belt.get_transport_line(laneNumber).get_contents()
		for item, size in pairs(lane) do
			local itemstack = {name=item, count=size}
			belt.get_transport_line(laneNumber).remove_item(itemstack)
			power.energy = power.energy - energy_per_action		
		end
	end
end

function beltToChest(belt, laneNumber, chest, power)
	if chest and chest.valid and power and power.valid and power.energy >= energy_per_action then
		local items = belt.get_transport_line(laneNumber).get_contents()
		for item, size in pairs(items) do
			local itemstack = {name=item, count=math.min(inputMultiplier,size)}
			if chest and chest.valid and chest.can_insert(itemstack) then
				itemstack.count = chest.insert(itemstack)
				belt.get_transport_line(laneNumber).remove_item(itemstack)
				power.energy = power.energy - energy_per_action		
			end
			break
		end
	end
end

function chestToBelt(belt, laneNumber, chest, power)
	if chest and chest.valid and power and power.valid and power.energy >= energy_per_action then
		local _inventory = chest.get_inventory(1).get_contents()
		for item, size in pairs(_inventory) do
			local itemstack = {name=item, count=1}
			if belt.get_transport_line(laneNumber).insert_at_back(itemstack) then
				chest.get_inventory(1).remove(itemstack)
				power.energy = power.energy - energy_per_action
			end
			break
		end
	end
end

function sourceToTargetInventory(source, target, power)
  if source and source.valid and power and power.valid and power.energy >= energy_per_action then
	  local _inventory = source.get_inventory(1).get_contents()
	  for item, size in pairs(_inventory) do
		local itemstack = {name=item, count=math.min(maxStackSize,size)}
		if target and target.valid and target.can_insert(itemstack) then
			itemstack.count = target.insert(itemstack)
			source.get_inventory(1).remove(itemstack)
			power.energy = power.energy - energy_per_action
		end
		break
	  end
	end
end

function getInputBelts(grid)
	local belts = {}
	local belt
	
	-- North
	belt = checkTransportEntity(grid.north, SOUTH, "output")
	if belt then  
		belts[#belts+1] = belt
	end
	
	-- South
	belt = checkTransportEntity(grid.south, NORTH, "output")
	if belt then   
		belts[#belts+1] = belt
	end
	
	-- East
	belt = checkTransportEntity(grid.east, WEST, "output")
	if belt then   
		belts[#belts+1] = belt
	end
	
	-- West
	belt = checkTransportEntity(grid.west, EAST, "output")
	if belt then
		belts[#belts+1] = belt
	end
	
    return belts 
end

function getOutputBelts(grid)
	local belts = {}
	local belt
	local checkNorth
	local checkEast
	local checkSouth
	local checkWest
	
	-- North
	belt = checkTransportEntity(grid.north, NORTH, "input")
	if belt then
		if belt.type == "transport-belt" then
			checkWest = checkTransportEntity(grid.northWest, EAST, "output")
			checkEast = checkTransportEntity(grid.northEast, WEST, "output")
			if (checkWest and checkEast) or (checkWest == nil and checkEast == nil) then
				belts[#belts+1] = belt
			end
		else
			belts[#belts+1] = belt
		end
	end
	
	-- South
	belt = checkTransportEntity(grid.south, SOUTH, "input")
	if belt then
		if belt.type == "transport-belt" then
			checkWest = checkTransportEntity(grid.southWest, EAST, "output")
			checkEast = checkTransportEntity(grid.southEast, WEST, "output")
			if (checkWest and checkEast) or (checkWest == nil and checkEast == nil) then
				belts[#belts+1] = belt
			end
		else
			belts[#belts+1] = belt
		end
	end
	
	-- East
	belt = checkTransportEntity(grid.east, EAST, "input")
	if belt then
		if belt.type == "transport-belt" then
			checkNorth = checkTransportEntity(grid.northEast, SOUTH, "output")
			checkSouth = checkTransportEntity(grid.southEast, NORTH, "output")
			if (checkNorth and checkSouth) or (checkNorth == nil and checkSouth == nil) then
				belts[#belts+1] = belt
			end
		else
			belts[#belts+1] = belt
		end
	end
	
	-- West
	belt = checkTransportEntity(grid.west, WEST, "input")
	if belt then
		if belt.type == "transport-belt" then
			checkNorth = checkTransportEntity(grid.northWest, SOUTH, "output")
			checkSouth = checkTransportEntity(grid.southWest, NORTH, "output")
			if (checkNorth and checkSouth) or (checkNorth == nil and checkSouth == nil) then
				belts[#belts+1] = belt
			end
		else
			belts[#belts+1] = belt
		end
	end
	
    return belts 
end

function getInventories(grid)
	local inventories = {}
	local inventory

	-- North
	inventory = grid.north
	if inventory then
		inventories[#inventories+1] = inventory
	end
	
	-- South
	inventory  = grid.south
	if inventory then
		inventories[#inventories+1] = inventory
	end
	
	-- East
	inventory = grid.east
	if inventory then
		inventories[#inventories+1] = inventory
	end
	
	--West
	inventory = grid.west
	if inventory then
		inventories[#inventories+1] = inventory
	end
	
	-- North East
	inventory = grid.northEast
	if inventory then
		inventories[#inventories+1] = inventory
	end
	
	-- South East
	inventory  = grid.southEast
	if inventory then
		inventories[#inventories+1] = inventory
	end
	
	-- North West
	inventory = grid.northWest
	if inventory then
		inventories[#inventories+1] = inventory
	end
	
	-- South West
	inventory = grid.southWest
	if inventory then
		inventories[#inventories+1] = inventory
	end
	
	return inventories
end

function checkTransportEntity(entity, direction, undergroundType)
	if entity and (entity.type ~= "transport-belt-to-ground" or (entity.type == "transport-belt-to-ground" and entity.belt_to_ground_type == undergroundType)) and entity.direction == direction then
		return entity
	else
		return nil
	end
end

function isInventory (entity)
	if entity and (entity.type == "logistic-container" or (entity.type == "smart-container" and entity.name ~= "interface-chest") or isTrain(entity)) then
		return entity
	else
		return nil
	end
end

function isTrain (entity)
	if entity and ((entity.type == "cargo-wagon" and entity.train.speed == 0) or (entity.type == "locomotive"  and entity.train.speed == 0) or isWarehouse(entity)) then
		return entity
	else
		return nil
	end
end

function isWarehouse(entity)
	if entity and (entity.name == "warehouse-basic" or entity.name == "warehouse-smart" or entity.name == "warehouse-storage" or entity.name == "warehouse-smart-passive-provider" or entity.name == "warehouse-active-provider" or entity.name == "warehouse-requestor")  then
		return entity
	else
		return nil
	end
end

function isTransport (entity)
	if entity and (entity.type == "transport-belt" or entity.type == "splitter" or entity.type == "transport-belt-to-ground") then
		return entity
	else
		return nil
	end
end

function debugPrint(thing)
	for _, player in pairs(game.players) do	
		player.print(serpent.block(thing))
	end
end

-- Once per save
script.on_init(InterfaceChest_Initialize)

-- Every Tick
script.on_event(defines.events.on_tick, InterfaceChest_RunStep)

-- On create
script.on_event(defines.events.on_built_entity, InterfaceChest_Create)
script.on_event(defines.events.on_robot_built_entity, InterfaceChest_Create)

-- On change 
script.on_event(defines.events.on_player_rotated_entity, InterfaceChest_Rotated)

-- On remove
script.on_event(defines.events.on_preplayer_mined_item, InterfaceChest_Mined)
script.on_event(defines.events.on_robot_pre_mined, InterfaceChest_Mined)

require "util"

-- Belts lanes have 4 slots: yellow 36 ticks, red 18 ticks, blue 12 ticks
-- Ticks to clear a slot 9, 4.5, 3 
-- Splitters/underground 2 slots: need twice the tick rate
-- Red splitter/underground do some magic -- cuase technically they should have a gap
-- Should take 9 ticks for 2 items to clear out of the way, but on splitter/underground they dissapear ahead of schedule.
-- On red splitter/underground belt they alternate sending items on tick 0, 6, 18, 24, 30 = 9 average

local chestThrottle = 6
local railCheckThrottle = chestThrottle * 15
local voidThrottle = chestThrottle * 20
local energy_per_action = 8000
local idleDraw = 500

local beltBalancerThrottle = 12

-- Internal Use
local dataVersion = 14

-- How many a chest can pull from a belt lane 0-8
local inputMultiplier = 8
-- Inventory to Inventory transfer stack size
local maxStackSize = 4

-- Cardinal Directions
local NORTH = defines.direction.north
local EAST = defines.direction.east
local SOUTH = defines.direction.south
local WEST = defines.direction.west

-- Optimal places on a belt to place item
local beltPositions = {0, .182, .463, .744}
local splitterPositions = {0, .28}

-- Adjacent tiles
function areaNorth(position) return {{position.x - 0.5, position.y - 1.5},{position.x + 0.5, position.y - 0.5}} end
function areaSouth(position) return {{position.x - 0.5, position.y + 0.5},{position.x + 0.5, position.y + 1.5}} end
function areaEast(position)  return {{position.x + 0.5, position.y - 0.5},{position.x + 1.5, position.y + 0.5}} end
function areaWest(position)  return {{position.x - 1.5, position.y - 0.5},{position.x - 0.5, position.y + 0.5}} end

-- Area around tile
function getBoundingBox(position, radius)
	return {{x=position.x-radius-.5,y=position.y-radius-.5},{x=position.x+radius+.5,y=position.y+radius+.5}}
end

-- Area around tile
function getBoundingBoxX(position, radius)
	return {{x=position.x-radius-.5,y=position.y-.5},{x=position.x+radius+.5,y=position.y+.5}}
end


-- Area around tile
function getBoundingBoxY(position, radius)
	return {{x=position.x-.5,y=position.y-radius-.5},{x=position.x+.5,y=position.y+radius+.5}}
end


-------------------
function InterfaceChest_Initialize()
	if global.InterfaceChest_MasterList == nil then
		global.InterfaceChest_MasterList = {}
	end
	
	if global.InterfaceChest_DataVersion == nil then
		global.InterfaceChest_DataVersion = 0
	end

	if global.InterfaceBelt_MasterList == nil then
		global.InterfaceBelt_MasterList = {}
	end
	
	if global.InterfaceBelt_DataVersion == nil then
		global.InterfaceBelt_DataVersion = 0
	end
end

-------------------
function getKey (entity)
	return "if_x" .. entity.position.x .. "y".. entity.position.y .. entity.surface.index
end

function InterfaceChest_Create(event)
	local entity = event.created_entity
	if isInterfaceChest(entity) then
		local modTick = game.tick % chestThrottle
		local key = getKey(entity)
		if global.InterfaceChest_MasterList[modTick] == nil then
			global.InterfaceChest_MasterList[modTick] = {}
		end
		global.InterfaceChest_MasterList[modTick][key] = updateInterfaceChest(entity)
		--debugPrint("Interface Chest created: " .. key)
	end

	if entity.name == "interface-belt-balancer" then
		local key = getKey(entity)
		local modTick = game.tick % beltBalancerThrottle
		if global.InterfaceBelt_MasterList[modTick] == nil then
			global.InterfaceBelt_MasterList[modTick] = {}
		end
		global.InterfaceBelt_MasterList[modTick][key] = entity
		--debugPrint("Interface Belt count: " .. key)
	end

	if isTransport(entity) or isInventory(entity) or entity.type == "straight-rail" then
		scheduleUpdate(entity, 3)
	end
end

-------------------
function InterfaceChest_Rotated(event)
	local entity = event.entity 
	if isTransport(entity) or isInventory(entity) or entity.type == "straight-rail" then
		scheduleUpdate(entity, 3)
	end
end

function InterfaceChest_Mined(event)
	local entity = event.entity 
	if isTransport(entity) or isInventory(entity) or entity.type == "straight-rail" then
		scheduleUpdate(entity, 3)
	end
end

-------------------
function scheduleUpdate (entity, range)
	local entities = entity.surface.find_entities(getBoundingBox(entity.position, range))
	for index=1, #entities do
		if isInterfaceChest( entities[index]) then
			local chest = entities[index]
			if chest and chest.valid then
				for modTick=0, chestThrottle-1 do
					if global.InterfaceChest_MasterList[modTick][getKey(chest)] then 
						global.InterfaceChest_MasterList[modTick][getKey(chest)].dirty = true 
					end
				end
			end
		end
	end
end

-------------------
function InterfaceBelt_RunStep()
	if global.InterfaceBelt_DataVersion ~= dataVersion then
		-- Initialize
		InterfaceChest_Initialize()

		local beltBalancer = game.surfaces[1].find_entities_filtered{area={{-10000, -10000},{10000, 10000}}, name="interface-belt-balancer"}
		
		local masterList = {}
		for index=0, beltBalancerThrottle-1 do
			masterList[index] = {}
		end
		
		for index=1, #beltBalancer do
			local entity = beltBalancer[index]
			local modTick = math.random(beltBalancerThrottle) - 1
			masterList[modTick][getKey(entity)] = entity
		end

		global.InterfaceBelt_MasterList = masterList
		global.InterfaceBelt_DataVersion = dataVersion

	else
		local modTick = game.tick % beltBalancerThrottle
		local masterList = global.InterfaceBelt_MasterList[modTick]
		if masterList then
			for index, value in pairs(masterList) do
				local belt = value
				if belt and belt.valid then
					local left = belt.get_transport_line(1)
					local right = belt.get_transport_line(2)
					balanceBelt(right, left)
					balanceBelt(left, right)
				else
					global.InterfaceBelt_MasterList[modTick][index] = nil
				end
			end
		end
	end
end

function balanceBelt (source, target)
	local action = false
	for item, size in pairs(source.get_contents()) do
		local diff = size - target.get_item_count(item)
		local itemstack = {name=item, count=1}
		if diff > 2 and size > 2 then
			if target.insert_at(beltPositions[1], itemstack) then
				source.remove_item(itemstack)
				action = true
			end
			if target.insert_at(beltPositions[2], itemstack) then
				source.remove_item(itemstack)
				action = true
			end
		elseif diff > 1 and size > 1 then
			if target.insert_at(beltPositions[1], itemstack) then
				source.remove_item(itemstack)
				action = true
			end
		end
	end
	return action
end

-------------------
function InterfaceChest_RunStep(event)
	if global.InterfaceChest_DataVersion ~= dataVersion then
		
		-- Initialize
		InterfaceChest_Initialize()

		-- Find all this mod's chests and index them
		trashCan = {}
		for index=1,#game.surfaces do
			local temp = game.surfaces[index].find_entities_filtered{area={{-10000, -10000},{10000, 10000}}, name="interface-chest-trash"}
			for k,v in pairs(temp) do table.insert(trashCan, v) end
		end

		interfaceChests = {}
		for index=1,#game.surfaces do
			local temp = game.surfaces[index].find_entities_filtered{area={{-10000, -10000},{10000, 10000}}, name="interface-chest"}
			for k,v in pairs(temp) do table.insert(interfaceChests, v) end
		end

		local masterList = {}
		for index=0, chestThrottle-1 do
			masterList[index] = {}
		end

		for index=1, #trashCan do
			local modTick = math.random(chestThrottle) - 1
			local chest = trashCan[index]
			masterList[modTick][getKey(chest)] = updateInterfaceChest(chest)
		end

		for index=1, #interfaceChests do
			local modTick = math.random(chestThrottle) - 1
			local chest = interfaceChests[index]
			masterList[modTick][getKey(chest)] = updateInterfaceChest(chest)
		end

		global.InterfaceChest_MasterList = masterList
		global.InterfaceChest_DataVersion = dataVersion
	else
		InterfaceBelt_RunStep()
		local modTick = game.tick % chestThrottle
		local masterList = global.InterfaceChest_MasterList[modTick]

		if masterList then
			for index, value in pairs(masterList) do
				local interfaceChest = value
				if interfaceChest.chest and interfaceChest.chest.valid then					
					if interfaceChest.power == nil or interfaceChest.power.valid == false then
						interfaceChest = updateInterfaceChest(interfaceChest.chest)
						global.InterfaceChest_MasterList[modTick][index] = interfaceChest
						--debugPrint("Create missing power for: " .. index)
					else
						if interfaceChest.power and interfaceChest.power.valid and interfaceChest.power.energy >= (idleDraw) then
							interfaceChest.power.energy = interfaceChest.power.energy - idleDraw
							if interfaceChest.chest.name == "interface-chest-trash" then
								voidChest(interfaceChest, modTick, index)
							else
								
								-- No good way to check for nearby train, so if on rail check for train
								if interfaceChest.onRail and modTick == (game.tick % railCheckThrottle) then
									interfaceChest.dirty = true
								end

								local chestPosition = getBoundingBox(interfaceChest.chest.position, 0)
								if interfaceChest.dirty then
									interfaceChest = updateInterfaceChest(interfaceChest.chest)
									global.InterfaceChest_MasterList[index] = interfaceChest
								end

							-- Input items Into Chest
								for i=1, #interfaceChest.inputBelts do
									local belt = interfaceChest.inputBelts[i]
									if belt.valid then
										if belt.type == "splitter" then
											local chestPosition = getBoundingBox(interfaceChest.chest.position, 0)
											if (belt.position.x == chestPosition[1].x and belt.position.y < chestPosition[1].y) or (belt.position.x == chestPosition[2].x and belt.position.y > chestPosition[1].y) or (belt.position.y == chestPosition[1].y and belt.position.x > chestPosition[2].x) or (belt.position.y == chestPosition[2].y and belt.position.x < chestPosition[2].x) then
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

								-- Pull Items from adjacent Inventories
								if #interfaceChest.inputBelts == 0 and #interfaceChest.outputBelts > 0 then
									for i=1, #interfaceChest.inventories do
										local inventory = interfaceChest.inventories[i]
										local inventoryIndex = 1
										if inventory and inventory.valid then
											if inventory.get_output_inventory() and inventory.get_output_inventory().is_empty() == false then
												sourceToTargetInventory(inventory, interfaceChest.chest, interfaceChest.power)
											end
										end
									end
								end

								-- Output items to adjacent Belts
								if interfaceChest.chest.get_output_inventory().is_empty() == false then
									for i=1, #interfaceChest.outputBelts do
										local belt = interfaceChest.outputBelts[i]
										if belt.valid then
											if belt.type == "splitter" then
												local chestPosition = getBoundingBox(interfaceChest.chest.position, 0)
												if (belt.position.x == chestPosition[1].x and belt.position.y > chestPosition[1].y) or (belt.position.x == chestPosition[2].x and belt.position.y < chestPosition[1].y) or (belt.position.y == chestPosition[1].y and belt.position.x < chestPosition[2].x) or (belt.position.y == chestPosition[2].y and belt.position.x > chestPosition[2].x) then
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
					if interfaceChest ~= nil and interfaceChest.power and interfaceChest.power.valid then
						if interfaceChest.power.destroy() then
							--debugPrint("Power removed: " ..   index)
							global.InterfaceChest_MasterList[modTick][index] = nil
						end
					end
					--debugPrint("Loaded: " ..   index)
				end
			end
		end
	end
end

function updateInterfaceChest(chest)
	local center = getBoundingBox(chest.position, 0)
	local entities = chest.surface.find_entities(getBoundingBox(chest.position, 1))
	local entitiesX = chest.surface.find_entities(getBoundingBoxX(chest.position, 1))
	local entitiesY = chest.surface.find_entities(getBoundingBoxY(chest.position, 1))
	local gridTransport = {}
	local gridInventory = {}
	local isRail = false
	local powerSource = nil

	for index=1, #entities do
		local entity = entities[index]
		if entity.type ~= "decorative" then
			if isRail == false and entity.type == "straight-rail" then
				isRail = true
			elseif powerSource == nil and entity.name == "interface-chest-power" and entity.position.x > center[1].x and entity.position.x < center[2].x and entity.position.y > center[1].y and entity.position.y < center[2].y then
				--debugPrint("Power: " .. entity.position.x .. " > " .. center[1].x .. " and " .. entity.position.x .. " < " ..  center[2].x .. " and " .. entity.position.y .. " > " ..  center[1].y .. " and " .. entity.position.y .. " < " ..  center[2].y)
				powerSource = entity
			end
		end
	end
	
	for index=1, #entitiesX do
		local entity = entitiesX[index]
		if entity.type ~= "decorative" then
			-- East
			if entity.position.x > center[2].x then
				if isTransport(entity) then gridTransport.east = entity end
				if isInventory(entity, isRail) then gridInventory.east = entity end
			-- West
			elseif entity.position.x < center[1].x then
				if isTransport(entity) then gridTransport.west = entity end
				if isInventory(entity, isRail) then gridInventory.west = entity end
			end
		end
	end
	
	for index=1, #entitiesY do
		local entity = entitiesY[index]
		if entity.type ~= "decorative" then
			-- North
			if entity.position.y < center[1].y then
				if isTransport(entity) then gridTransport.north = entity end
				if isInventory(entity, isRail) then gridInventory.north = entity end
			-- South
			elseif entity.position.y > center[2].y then
				if isTransport(entity) then gridTransport.south = entity end
				if isInventory(entity, isRail) then gridInventory.south = entity end
			end
		end
	end

	for index=1, #entities do 
		local entity = entities[index]
		if entity.type ~= "decorative" then
			-- North West
			if entity.position.x <= center[1].x and entity.position.y <= center[1].y then
				if isTransport(entity) then gridTransport.northWest = entity end
				if isTrain(entity, isRail) then gridInventory.northWest = entity end
			-- North East
			elseif entity.position.x >= center[2].x and entity.position.y <= center[1].y then
				if isTransport(entity) then gridTransport.northEast = entity end
				if isTrain(entity, isRail) then gridInventory.northEast = entity end
			-- South West
			elseif entity.position.x <= center[1].x and entity.position.y >= center[2].y then
				if isTransport(entity) then gridTransport.southWest = entity end
				if isTrain(entity, isRail) then gridInventory.southWest = entity end
			-- South East
			elseif entity.position.x >= center[2].x and entity.position.y >= center[2].y then
				if isTransport(entity) then gridTransport.southEast = entity end
				if isTrain(entity, isRail) then gridInventory.southEast = entity end
			end
		end
	end

	if powerSource == nil then
		--debugPrint("Create power: " .. serpent.block(chest.position))
		powerSource = chest.surface.create_entity{name="interface-chest-power", position=chest.position, force=chest.force}
	end

	return {chest = chest, inputBelts = getInputBelts(gridTransport), outputBelts = getOutputBelts(gridTransport), inventories = getInventories(gridInventory), onRail = isRail, dirty = false, power = powerSource}
end

function voidChest(interfaceChest, modTick, index)
	if interfaceChest.chest and interfaceChest.chest.valid and interfaceChest.power and interfaceChest.power.valid and interfaceChest.power.energy >= energy_per_action then
		if interfaceChest.dirty then
			interfaceChest = updateInterfaceChest(interfaceChest.chest)
			global.InterfaceChest_MasterList[modTick][index] = interfaceChest
		end

		if modTick == (game.tick % voidThrottle) then
			interfaceChest.chest.get_output_inventory().clear()
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


function beltToVoid(belt, laneNumber, power)
	if power and power.valid and power.energy >= energy_per_action then
		if belt.get_transport_line(laneNumber).can_insert_at(0) == false then
			local items = belt.get_transport_line(laneNumber).get_contents()
			local item = next(items)
			local size = items[item]
			if size then
				local itemstack = {name=item, count=size}
				belt.get_transport_line(laneNumber).remove_item(itemstack)
				power.energy = power.energy - energy_per_action
			end
		end
	end
end

function beltToChest(belt, laneNumber, chest, power)
	if chest and chest.valid and power and power.valid and power.energy >= energy_per_action then
		if belt.get_transport_line(laneNumber).can_insert_at(0) == false then
			local lane = belt.get_transport_line(laneNumber)
			local contents = lane.get_contents()
			local item = next(contents)
			local size = contents[item]
			--debugPrint(item .. " " .. size)
			if size then
				local itemstack = {name=item, count=math.min(inputMultiplier,size)}
				if chest and chest.valid and chest.can_insert(itemstack) then
					itemstack.count = chest.insert(itemstack)
					lane.remove_item(itemstack)
					power.energy = power.energy - energy_per_action
				end
			end
		end
	end
end

function chestToBelt(belt, laneNumber, chest, power)
	if chest and chest.valid and power and power.valid and power.energy >= energy_per_action then
		local positions = {}
		if belt.type == "transport-belt" then
			positions = beltPositions
		else
			positions = splitterPositions
		end
		if belt.get_transport_line(laneNumber).can_insert_at(positions[1]) then
		

			
		
			local inventory = chest.get_output_inventory()
			local contents = inventory.get_contents()
			local item = next(contents)
			local size = contents[item]
			local itemstack = {name=item, count=1}
			

			
			if size then 
			
			--[[
			--Find Positions 0 to 1
			for i=0, 1000 do
			if belt.get_transport_line(laneNumber).insert_at(i/1000, itemstack) then
					debugPrint("Inserted: " .. i/1000 .. " tick: " .. game.tick)
					power.energy = power.energy - energy_per_action
					inventory.remove({name=item, count=1})
				end
			end
			
			--Find Positions 1 to 0
			for i=1, 1000 do
			if belt.get_transport_line(laneNumber).insert_at((1001-i)/1000, itemstack) then
					debugPrint("Inserted: " .. (1001-i)/1000 .. " tick: " .. game.tick)
					power.energy = power.energy - energy_per_action
					inventory.remove({name=item, count=1})
				end
			end
			]]--
			
				local toTransfer = math.min(#positions, size)
				for i=1, toTransfer do
					if belt.get_transport_line(laneNumber).insert_at(positions[i], itemstack) then
						--debugPrint("Inserted: " .. positions[i] .. " tick: " .. game.tick)
						power.energy = power.energy - energy_per_action
						inventory.remove({name=item, count=1})
					end
				end
				
			end
		end
	end
end

function sourceToTargetInventory(source, target, power)
	if source and source.valid and power and power.valid and power.energy >= energy_per_action then
		local inventory = source.get_output_inventory()
		local contents = inventory.get_contents()
		local item = next(contents)
		local size = contents[item]
		if size then 
			local itemstack = {name=item, count=math.min(maxStackSize,size)}
			if target and target.valid and target.can_insert(itemstack) then
				itemstack.count = target.insert(itemstack)
				inventory.remove(itemstack)
				power.energy = power.energy - energy_per_action
			end
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
	inventory = grid.south
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
	inventory = grid.southEast
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
	if entity and (entity.type ~= "underground-belt" or (entity.type == "underground-belt" and entity.belt_to_ground_type == undergroundType)) and entity.direction == direction then
		return entity
	else
		return nil
	end
end

function isInventory (entity, onTrack)
	if entity and entity.name ~= "interface-chest" and entity.type ~= "beacon" and entity.get_output_inventory() ~= nil and (isMoveable(entity) == false or isTrain(entity, onTrack)) then
		return entity
	else
		return nil
	end
end

function isMoveable (entity)
	if (entity.type == "cargo-wagon" or entity.type == "locomotive" or entity.type == "car" or entity.type == "player") then
		return true
	else
		return false
	end
end

--or (entity.type == "player" and entity.walking_state == false)
function isTrain (entity, onTrack)
	if entity and onTrack and ((entity.type == "cargo-wagon" and entity.train.speed == 0) or (entity.type == "locomotive" and entity.train.speed == 0) or (entity.type == "car" and entity.speed == 0)) then
		return entity
	else
		return nil
	end
end

function isTransport (entity)
	if entity and (entity.type == "transport-belt" or entity.type == "splitter" or entity.type == "underground-belt") then
		return entity
	else
		return nil
	end
end

function isInterfaceChest (entity)
	 if entity.name == "interface-chest" or entity.name == "interface-chest-trash"  then
		return true
	 else
		return false
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

script.on_event(defines.events.on_entity_died, function(event)
	local entity = event.entity
	if entity.name == "interface-chest-power" then
		local entities = entity.surface.find_entities(getBoundingBox(entity.position, 0))
		for index=1, #entities do
			if isInterfaceChest( entities[index]) then
				local chest = entities[index]
				if chest and chest.valid then
					--debugPrint("Chest Destoyed: " .. getKey(chest.location))
					chest.destroy()
				end
			end
		end
	end
end)

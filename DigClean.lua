if _G.DigCleanUnload then
    pcall(_G.DigCleanUnload)
    task.wait(0.3)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local function notify(title, content, duration)
    Fluent:Notify({ Title = title, Content = content, Duration = duration or 4 })
end

local frameworkOk, frameworkCore = pcall(function()
    return require(ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out)
end)

if not frameworkOk then
    notify("Dig & Clean", "Game framework not found", 8)
    return
end

local Flamework = frameworkCore.Flamework

local function getController(id)
    local ok, value = pcall(Flamework.resolveDependency, id)
    if ok then
        return value
    end
    return nil
end

local DigController = getController("client/controllers/world/DigController@DigController")
local SweepController = getController("client/controllers/world/DetectorSweepController@DetectorSweepController")
local ShovelController = getController("client/controllers/world/ShovelController@ShovelController")
local WorkbenchController = getController("client/controllers/world/WorkbenchController@WorkbenchController")
local SprayController = getController("client/controllers/world/SprayBottleController@SprayBottleController")
local TransitionController = getController("client/controllers/world/TransitionController@TransitionController")
local DataController = getController("client/controllers/data/DataController@DataController")
local PlotController = getController("client/controllers/plot/PlotController@PlotController")
local IslandController = getController("client/controllers/world/IslandController@IslandController")

local netFolder = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("TS"):WaitForChild("network")
local ShovelNet = require(netFolder.ShovelNetwork)
local PedestalNet = require(netFolder.PedestalNetwork)
local ShopNet = require(netFolder.ShopNetwork)
local SellNet = require(netFolder.SellNetwork)
local TravelNet = require(netFolder.TravelNetwork)

local Shovels = require(ReplicatedStorage.TS.constants.digging.Shovels)
local Detectors = require(ReplicatedStorage.TS.constants.digging.Detectors)
local Sprays = require(ReplicatedStorage.TS.constants.cleaning.SprayBottles)
local Islands = require(ReplicatedStorage.TS.constants.world.Islands)
local ItemsModule = require(ReplicatedStorage.TS.constants.items.Items)
local DigZoneSpawn = require(ReplicatedStorage.TS.utils.world.DigZoneSpawn)
local teleportStreamed = require(ReplicatedStorage.TS.utils.world.teleportStreamed).teleportStreamed

local RARITY_ORDER = ItemsModule.RARITY_ORDER
local DIG_ZONE_TAG = Shovels.DIG_ZONE_TAG
local ISLAND_ATTRIBUTE = Islands.ISLAND_ID_ATTRIBUTE
local POWER_PERIOD = 0.55
local POWER_PEAK = 0.275
local BACKPACK_LIMIT = 50

local GearCatalog = {
    shovel = {
        label = "Shovel",
        order = Shovels.SHOVEL_TIER_ORDER,
        defs = Shovels.Shovels,
        ownedKey = "OwnedShovels",
        equippedKey = "EquippedShovel"
    },
    detector = {
        label = "Detector",
        order = Detectors.DETECTOR_TIER_ORDER,
        defs = Detectors.Detectors,
        ownedKey = "OwnedDetectors",
        equippedKey = "EquippedDetector"
    },
    spray = {
        label = "Spray",
        order = Sprays.SPRAY_TIER_ORDER,
        defs = Sprays.SprayBottles,
        ownedKey = "OwnedSprays",
        equippedKey = "EquippedSpray"
    }
}

local State = {
    AutoDig = false,
    AutoClean = false,
    AutoPlace = false,
    AutoSell = false,
    AutoShovel = false,
    AutoDetector = false,
    AutoSpray = false,
    UseSurfaced = true,
    SmartPlace = true,
    SellDirty = false,
    SafeTeleport = true,
    AntiAfk = true,
    SearchRadius = 200,
    CleanThreshold = 1,
    GoldReserve = 0,
    Rarities = {},
    Unloaded = false
}

for _, rarity in ipairs(RARITY_ORDER) do
    State.Rarities[rarity] = true
end

local Stats = {
    digs = 0,
    cleans = 0,
    places = 0,
    swaps = 0,
    sold = 0,
    earned = 0,
    buys = 0,
    action = "Idle"
}

local SurfacedItems = {}
local IslandNames = {}
local CachedSlots = nil
local LastWander = 0
local CleanCooldown = 0
local StuckSince = 0
local releaseWorkbench

local function character()
    return LocalPlayer.Character
end

local function humanoid()
    local char = character()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function rootPart()
    local char = character()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function isAlive()
    local hum = humanoid()
    return hum ~= nil and hum.Health > 0 and rootPart() ~= nil
end

local function getData()
    if not DataController then
        return nil
    end
    local ok, value = pcall(function()
        return DataController:getDataIfLoaded()
    end)
    if ok then
        return value
    end
    return nil
end

local function waitUntil(predicate, timeout, interval)
    local started = os.clock()
    while os.clock() - started < timeout do
        if State.Unloaded then
            return false
        end
        local ok, result = pcall(predicate)
        if ok and result then
            return true
        end
        task.wait(interval or 0.08)
    end
    return false
end

local function formatNumber(value)
    local text = tostring(math.floor(value or 0))
    local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    result = result:gsub("^,", "")
    return result
end

local function itemValue(item)
    if not item or not item.id then
        return 0
    end
    local ok, value
    if item.dirty == true or item.condition == nil then
        ok, value = pcall(ItemsModule.dirtyItemValueFor, item.id, item.kg)
    else
        ok, value = pcall(ItemsModule.itemValueFor, item.id, item.condition, item.kg)
    end
    if ok and type(value) == "number" then
        return value
    end
    return 0
end

local function teleport(position)
    local root = rootPart()
    if not root then
        return false
    end
    if not State.SafeTeleport then
        root.CFrame = CFrame.new(position)
        return true
    end
    local origin = root.Position
    local distance = (position - origin).Magnitude
    local steps = math.clamp(math.ceil(distance / 14), 1, 90)
    for index = 1, steps do
        local current = rootPart()
        if not current then
            return false
        end
        current.CFrame = CFrame.new(origin:Lerp(position, index / steps))
        RunService.Heartbeat:Wait()
    end
    return true
end

local function currentIsland()
    local data = getData()
    return (data and data.CurrentIsland) or Islands.STARTER_ISLAND_ID
end

local function islandZones()
    local island = currentIsland()
    local parts = {}
    for _, zone in ipairs(CollectionService:GetTagged(DIG_ZONE_TAG)) do
        if zone:IsA("BasePart") and zone:GetAttribute(ISLAND_ATTRIBUTE) == island then
            table.insert(parts, zone)
        end
    end
    return parts
end

local function randomZonePoint()
    local parts = islandZones()
    if #parts == 0 then
        return nil
    end
    local ok, result = pcall(DigZoneSpawn.randomDigZonePoint, parts)
    if ok and type(result) == "table" and typeof(result.position) == "Vector3" then
        return result.position
    end
    for _ = 1, 8 do
        local zone = parts[math.random(1, #parts)]
        local half = zone.Size * 0.5
        local offset = Vector3.new((math.random() * 2 - 1) * half.X * 0.8, 0, (math.random() * 2 - 1) * half.Z * 0.8)
        local point = zone.CFrame:PointToWorldSpace(offset)
        local okZone, found = pcall(DigZoneSpawn.digZoneAt, point)
        if okZone and found == zone then
            return point
        end
    end
    return nil
end

local function insideDigZone()
    local root = rootPart()
    if not root then
        return false
    end
    local ok, zone = pcall(DigZoneSpawn.digZoneAt, root.Position)
    if not ok or not zone then
        return false
    end
    return zone:GetAttribute(ISLAND_ATTRIBUTE) == currentIsland()
end

local function inventoryCount()
    local data = getData()
    if not data or not data.Inventory then
        return 0
    end
    local count = 0
    for _, item in pairs(data.Inventory) do
        if item.pedestalSlot == nil then
            count = count + 1
        end
    end
    return count
end

local function backpackFull()
    return inventoryCount() >= BACKPACK_LIMIT
end

local function dirtyTools()
    local list = {}
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("dirty") == true then
                table.insert(list, tool)
            end
        end
    end
    local char = character()
    if char then
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("dirty") == true then
                table.insert(list, tool)
            end
        end
    end
    return list
end

local function toolForUid(uid)
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("inventoryId") == uid then
                return tool
            end
        end
    end
    local char = character()
    if char then
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("inventoryId") == uid then
                return tool
            end
        end
    end
    return nil
end

local function refreshSurfaced()
    local ok, promise = pcall(function()
        return ShovelNet.ShovelFunctions.GetSurfacedItems:invoke()
    end)
    if not ok then
        return
    end
    local success, list = promise:await()
    if not success or type(list) ~= "table" then
        return
    end
    table.clear(SurfacedItems)
    for _, entry in pairs(list) do
        if entry.id and entry.position then
            SurfacedItems[entry.id] = entry
        end
    end
end

local function bindSurfacedEvents()
    local events = ShovelNet.ShovelEvents
    pcall(function()
        events.SurfacedItemSpawned:connect(function(entry)
            if entry and entry.id then
                SurfacedItems[entry.id] = entry
            end
        end)
    end)
    pcall(function()
        events.SurfacedItemReleased:connect(function(entry)
            if entry and entry.id then
                SurfacedItems[entry.id] = entry
            end
        end)
    end)
    pcall(function()
        events.SurfacedItemRemoved:connect(function(id)
            SurfacedItems[id] = nil
        end)
    end)
    pcall(function()
        events.SurfacedItemClaimed:connect(function(id)
            SurfacedItems[id] = nil
        end)
    end)
end

local function nodeCount()
    if not SweepController then
        return 0
    end
    local count = 0
    for _, node in pairs(SweepController.nodes) do
        if State.Rarities[node.rarity] == true then
            count = count + 1
        end
    end
    return count
end

local function rarityRank(rarity)
    return (table.find(RARITY_ORDER, rarity) or 1) - 1
end

local function bestDigTarget()
    local root = rootPart()
    if not root then
        return nil
    end
    local origin = root.Position
    local best, bestScore = nil, -math.huge
    if SweepController then
        for _, node in pairs(SweepController.nodes) do
            if node.position and State.Rarities[node.rarity] == true then
                local distance = (node.position - origin).Magnitude
                if distance <= State.SearchRadius then
                    local score = rarityRank(node.rarity) * 10000 - distance
                    if score > bestScore then
                        best, bestScore = node.position, score
                    end
                end
            end
        end
    end
    if State.UseSurfaced then
        for _, entry in pairs(SurfacedItems) do
            local definition = ItemsModule.Items[entry.itemId]
            if definition and State.Rarities[definition.rarity] == true then
                local distance = (entry.position - origin).Magnitude
                if distance <= State.SearchRadius then
                    local score = 1000000 - distance
                    if score > bestScore then
                        best, bestScore = entry.position, score
                    end
                end
            end
        end
    end
    return best
end

local function driveDigSession()
    local session = DigController.session
    if not session then
        return
    end
    local started = os.clock()
    while DigController.session == session and not State.Unloaded do
        if os.clock() - started > 45 then
            break
        end
        local phase = session.phase
        if phase == "power" then
            if not session.powerStopping then
                local powerStartedAt = session.powerStartedAt or 0
                if powerStartedAt > 0 then
                    local now = Workspace:GetServerTimeNow()
                    local elapsed = now - powerStartedAt
                    local cycles = math.max(0, math.ceil((elapsed - POWER_PEAK) / POWER_PERIOD))
                    local target = powerStartedAt + POWER_PEAK + POWER_PERIOD * cycles
                    if target - now <= 0.01 then
                        pcall(function()
                            DigController:stopPower()
                        end)
                    end
                elseif os.clock() - started > 0.35 then
                    pcall(function()
                        DigController:stopPower()
                    end)
                end
            end
        elseif phase == "minigame" then
            pcall(function()
                DigController:onDigInput()
            end)
        elseif phase == "success" or phase == "loss" then
            break
        end
        RunService.Heartbeat:Wait()
    end
    waitUntil(function()
        return DigController.session == nil
    end, 6)
end

local function wanderStep()
    if os.clock() - LastWander < 4 then
        task.wait(0.4)
        return
    end
    local point = randomZonePoint()
    if not point then
        task.wait(0.5)
        return
    end
    LastWander = os.clock()
    teleport(point + Vector3.new(0, 3.5, 0))
    task.wait(0.6)
end

local function digStep()
    if not DigController or not ShovelController then
        return
    end
    if backpackFull() then
        Stats.action = "Backpack full"
        task.wait(1)
        return
    end
    local hum = humanoid()
    if hum then
        pcall(function()
            hum:UnequipTools()
        end)
    end
    if not insideDigZone() then
        local point = randomZonePoint()
        if point then
            Stats.action = "Heading to the sand"
            teleport(point + Vector3.new(0, 3.5, 0))
        else
            Stats.action = "No dig area found"
            task.wait(1)
        end
        return
    end
    local target = bestDigTarget()
    if not target then
        Stats.action = "Looking for spots"
        wanderStep()
        return
    end
    Stats.action = "Going to spot"
    teleport(target + Vector3.new(0, 3.5, 0))
    local root = rootPart()
    if not root then
        return
    end
    if (target - root.Position).Magnitude > 12 then
        return
    end
    if not waitUntil(function()
        local current = rootPart()
        return current and DigController:hasDigSpotNear(current.Position)
    end, 6) then
        return
    end
    Stats.action = "Digging"
    pcall(function()
        DigController:requestSession()
    end)
    if not waitUntil(function()
        return DigController.session ~= nil
    end, 3) then
        task.wait(0.3)
        return
    end
    driveDigSession()
    Stats.digs = Stats.digs + 1
end

local function transitionIdle()
    if not TransitionController then
        return true
    end
    return TransitionController.busy ~= true
end

releaseWorkbench = function()
    if not WorkbenchController then
        return
    end
    pcall(function()
        if WorkbenchController.session then
            WorkbenchController:endCleaning()
        end
        WorkbenchController.finishing = false
        WorkbenchController.cleaning = false
        WorkbenchController:refreshPrompt()
    end)
end

local function cleanTool(tool)
    if not WorkbenchController or not SprayController then
        return false
    end
    if WorkbenchController.cleaning and not WorkbenchController.session then
        releaseWorkbench()
        task.wait(0.3)
    end
    local bench = WorkbenchController.workbench
    if not bench then
        return false
    end
    local pivot = bench:GetPivot()
    teleport(pivot.Position + Vector3.new(0, 4, 5))
    task.wait(0.3)
    local hum = humanoid()
    if not hum or not tool or not tool.Parent then
        return false
    end
    pcall(function()
        hum:EquipTool(tool)
    end)
    if not waitUntil(function()
        return WorkbenchController:getHeldDirtyTool() ~= nil
    end, 4) then
        return false
    end
    if not waitUntil(transitionIdle, 10) then
        return false
    end
    pcall(function()
        WorkbenchController:onTriggered()
    end)
    if not waitUntil(function()
        return WorkbenchController.session ~= nil
    end, 10) then
        releaseWorkbench()
        return false
    end
    waitUntil(function()
        return SprayController.dirtCells ~= nil
    end, 12)
    task.wait(0.25)
    pcall(function()
        SprayController:forceFinish()
    end)
    if not waitUntil(function()
        return WorkbenchController.cleaning == false
    end, 25) then
        releaseWorkbench()
        return false
    end
    waitUntil(transitionIdle, 8)
    task.wait(0.2)
    Stats.cleans = Stats.cleans + 1
    return true
end

local function cleanStep()
    if os.clock() < CleanCooldown then
        return false
    end
    local pending = dirtyTools()
    if #pending == 0 then
        return false
    end
    if #pending < State.CleanThreshold and not backpackFull() then
        return false
    end
    local root = rootPart()
    local anchor = root and root.Position
    local guard = 0
    while State.AutoClean and not State.Unloaded and guard < 60 do
        local list = dirtyTools()
        if #list == 0 then
            break
        end
        Stats.action = "Cleaning (" .. tostring(#list) .. " left)"
        if not cleanTool(list[1]) then
            CleanCooldown = os.clock() + 10
            break
        end
        guard = guard + 1
    end
    if anchor and State.AutoDig then
        teleport(anchor)
    end
    return true
end

local function pedestalSlots()
    if CachedSlots and #CachedSlots > 0 then
        return CachedSlots
    end
    local slots = {}
    local ok, number = pcall(function()
        return PlotController:awaitPlotNumber():expect()
    end)
    if not ok or not number then
        return slots
    end
    local plots = Workspace:FindFirstChild("Plots")
    local plot = plots and plots:FindFirstChild("Plot_" .. tostring(number))
    local holder = plot and plot:FindFirstChild("Plot")
    local pedestals = holder and holder:FindFirstChild("Pedestals")
    if not pedestals then
        return slots
    end
    for _, pedestal in ipairs(pedestals:GetChildren()) do
        local slot = pedestal:GetAttribute("Slot")
        if type(slot) == "number" then
            table.insert(slots, slot)
        end
    end
    table.sort(slots)
    CachedSlots = slots
    return slots
end

local function placeAt(slot, uid)
    local ok, promise = pcall(function()
        return PedestalNet.PedestalFunctions.placeItem:invoke(slot, uid)
    end)
    if not ok then
        return false
    end
    local success, result = promise:await()
    return success and result == true
end

local function pickupAt(slot)
    local ok, promise = pcall(function()
        return PedestalNet.PedestalFunctions.pickupItem:invoke(slot)
    end)
    if not ok then
        return false
    end
    local success, result = promise:await()
    return success and result == true
end

local function readPedestals()
    local data = getData()
    local occupied, pending = {}, {}
    if not data or not data.Inventory then
        return occupied, pending
    end
    for _, item in pairs(data.Inventory) do
        if item.pedestalSlot ~= nil then
            occupied[item.pedestalSlot] = item
        elseif item.dirty == false then
            table.insert(pending, item)
        end
    end
    table.sort(pending, function(a, b)
        return itemValue(a) > itemValue(b)
    end)
    return occupied, pending
end

local function placeStep()
    local slots = pedestalSlots()
    if #slots == 0 then
        return
    end
    local occupied, pending = readPedestals()
    if #pending == 0 then
        return
    end
    for _, slot in ipairs(slots) do
        if #pending == 0 then
            break
        end
        if not occupied[slot] then
            local item = table.remove(pending, 1)
            if placeAt(slot, item.uid) then
                occupied[slot] = item
                Stats.places = Stats.places + 1
            end
            task.wait(0.2)
        end
    end
    if not State.SmartPlace then
        return
    end
    local guard = 0
    while #pending > 0 and guard < 20 and not State.Unloaded do
        guard = guard + 1
        local candidate = pending[1]
        local candidateValue = itemValue(candidate)
        local worstSlot, worstValue
        for _, slot in ipairs(slots) do
            local current = occupied[slot]
            if current then
                local value = itemValue(current)
                if not worstValue or value < worstValue then
                    worstSlot, worstValue = slot, value
                end
            end
        end
        if not worstSlot or candidateValue <= worstValue then
            break
        end
        if not pickupAt(worstSlot) then
            break
        end
        occupied[worstSlot] = nil
        task.wait(0.2)
        if placeAt(worstSlot, candidate.uid) then
            occupied[worstSlot] = candidate
            table.remove(pending, 1)
            Stats.places = Stats.places + 1
            Stats.swaps = Stats.swaps + 1
        else
            break
        end
        task.wait(0.2)
    end
end

local function nearestModel(name)
    local root = rootPart()
    local best, bestDistance
    local scope = Workspace:FindFirstChild("Islands") or Workspace
    for _, model in ipairs(scope:GetDescendants()) do
        if model:IsA("Model") and model.Name == name then
            local ok, pivot = pcall(function()
                return model:GetPivot().Position
            end)
            if ok then
                local distance = root and (pivot - root.Position).Magnitude or 0
                if not bestDistance or distance < bestDistance then
                    best, bestDistance = pivot, distance
                end
            end
        end
    end
    return best
end

local function nearestSeller()
    return nearestModel("SellerNPC")
end

local function sellCandidates()
    local slots = pedestalSlots()
    local data = getData()
    if not data or not data.Inventory or #slots == 0 then
        return {}
    end
    local occupied = {}
    local lowestPlaced = math.huge
    for _, item in pairs(data.Inventory) do
        if item.pedestalSlot ~= nil then
            occupied[item.pedestalSlot] = item
            lowestPlaced = math.min(lowestPlaced, itemValue(item))
        end
    end
    local hasFreeSlot = false
    for _, slot in ipairs(slots) do
        if not occupied[slot] then
            hasFreeSlot = true
            break
        end
    end
    local list = {}
    for _, item in pairs(data.Inventory) do
        if item.pedestalSlot == nil then
            if item.dirty == true then
                if State.SellDirty and (not State.AutoClean or backpackFull()) then
                    table.insert(list, item)
                end
            elseif not hasFreeSlot and itemValue(item) <= lowestPlaced then
                table.insert(list, item)
            end
        end
    end
    table.sort(list, function(a, b)
        return itemValue(a) < itemValue(b)
    end)
    return list
end

local function sellStep()
    local list = sellCandidates()
    if #list == 0 then
        return false
    end
    local seller = nearestSeller()
    if not seller then
        return false
    end
    local root = rootPart()
    local anchor = root and root.Position
    Stats.action = "Selling (" .. tostring(#list) .. ")"
    teleport(seller + Vector3.new(0, 3, 4))
    task.wait(0.5)
    for _, item in ipairs(list) do
        if State.Unloaded or not State.AutoSell then
            break
        end
        local tool = toolForUid(item.uid)
        local hum = humanoid()
        if tool and hum then
            pcall(function()
                hum:EquipTool(tool)
            end)
            task.wait(0.35)
            local ok, promise = pcall(function()
                return SellNet.SellFunctions.sellHeldItem:invoke()
            end)
            if ok then
                local success, gold = promise:await()
                if success and type(gold) == "number" then
                    Stats.sold = Stats.sold + 1
                    Stats.earned = Stats.earned + gold
                end
            end
            task.wait(0.25)
        end
    end
    local hum = humanoid()
    if hum then
        pcall(function()
            hum:UnequipTools()
        end)
    end
    if anchor and State.AutoDig then
        teleport(anchor)
    end
    return true
end

local function upgradeGear(category)
    local info = GearCatalog[category]
    local data = getData()
    if not info or not data then
        return
    end
    local ownedList = data[info.ownedKey]
    if type(ownedList) ~= "table" then
        return
    end
    local owned = {}
    for _, id in pairs(ownedList) do
        owned[id] = true
    end
    local bestIndex = 0
    for index, id in ipairs(info.order) do
        if owned[id] then
            bestIndex = index
        end
    end
    local bestId = info.order[math.max(bestIndex, 1)]
    if bestId and data[info.equippedKey] ~= bestId then
        pcall(function()
            ShopNet.ShopFunctions.equipGear:invoke(category, bestId)
        end)
        task.wait(0.3)
    end
    local nextId = info.order[bestIndex + 1]
    if not nextId or owned[nextId] then
        return
    end
    local definition = info.defs[nextId]
    if not definition then
        return
    end
    local unlocked = true
    pcall(function()
        unlocked = Islands.isIslandUnlocked(definition.islandId, data.UnlockedIslands) and true or false
    end)
    if not unlocked then
        return
    end
    local gold = data.Gold or 0
    if gold - definition.cost < State.GoldReserve then
        return
    end
    local ok, promise = pcall(function()
        return ShopNet.ShopFunctions.buyGear:invoke(category, nextId)
    end)
    if not ok then
        return
    end
    local success, result = promise:await()
    if success and result then
        Stats.buys = Stats.buys + 1
        notify("Upgrade", info.label .. ": " .. tostring(definition.displayName or nextId), 4)
        task.wait(0.4)
        pcall(function()
            ShopNet.ShopFunctions.equipGear:invoke(category, nextId)
        end)
    end
end

local function fetchIslands()
    if IslandController then
        local ok, list = pcall(function()
            return IslandController:getIslands()
        end)
        if ok and type(list) == "table" and #list > 0 then
            return list
        end
    end
    for _ = 1, 10 do
        local ok, promise = pcall(function()
            return TravelNet.TravelFunctions.getIslands:invoke()
        end)
        if ok then
            local success, list = promise:await()
            if success and type(list) == "table" and #list > 0 then
                return list
            end
        end
        task.wait(1)
    end
    return {}
end

local function travelToIsland(entry)
    if not entry or not entry.spawn then
        return
    end
    local destination = entry.spawn + Vector3.new(0, 4, 0)
    local current = nil
    if IslandController then
        local ok, value = pcall(function()
            return IslandController:getCurrentIslandId()
        end)
        current = ok and value or nil
    end
    if current == entry.id then
        teleport(destination.Position)
        return
    end
    local ok, promise = pcall(function()
        return TravelNet.TravelFunctions.travel:invoke(entry.id)
    end)
    if not ok then
        return
    end
    local success, result = promise:await()
    if not success or result == nil then
        notify("Travel", "Could not travel to " .. tostring(entry.name), 4)
        return
    end
    if result == "poor" then
        local definition = Islands.Islands[entry.id]
        notify("Travel", "Need " .. formatNumber(definition and definition.cost or 0) .. " gold to unlock " .. tostring(entry.name), 5)
        return
    end
    local streamed = nil
    pcall(function()
        streamed = teleportStreamed(LocalPlayer, destination)
    end)
    if type(streamed) == "table" and type(streamed.await) == "function" then
        pcall(function()
            streamed:await()
        end)
    end
    task.wait(0.4)
    local root = rootPart()
    if root and (root.Position - destination.Position).Magnitude > 25 then
        teleport(destination.Position)
    end
    CachedSlots = nil
    task.spawn(refreshSurfaced)
    notify("Travel", "Arrived at " .. tostring(entry.name), 4)
end

local Window = Fluent:CreateWindow({
    Title = "Dig & Clean",
    SubTitle = "Auto Farm",
    Search = true,
    Icon = "shovel",
    TabWidth = IsMobile and 120 or 150,
    Size = IsMobile and UDim2.fromOffset(470, 350) or UDim2.fromOffset(580, 450),
    Acrylic = not IsMobile,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
    UserInfo = true,
    UserInfoTop = false,
    UserInfoTitle = LocalPlayer.DisplayName,
    UserInfoSubtitle = "Dig & Clean",
    UserInfoSubtitleColor = Color3.fromRGB(96, 205, 255)
})

local Minimizer = Fluent:CreateMinimizer({
    Icon = "shovel",
    Size = UDim2.fromOffset(46, 46),
    Position = IsMobile and UDim2.new(0, 18, 0, 150) or UDim2.new(0, 320, 0, 24),
    Acrylic = not IsMobile,
    Corner = 12,
    Transparency = 1,
    Draggable = true,
    Visible = true
})

local Tabs = {
    Farm = Window:AddTab({ Title = "Farm", Icon = "pickaxe" }),
    Items = Window:AddTab({ Title = "Items", Icon = "package" }),
    Upgrades = Window:AddTab({ Title = "Upgrades", Icon = "arrow-up-circle" }),
    Travel = Window:AddTab({ Title = "Travel", Icon = "map" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

Tabs.Farm:AddSection("Digging", "zap")

local StatusParagraph = Tabs.Farm:AddParagraph({
    Icon = "activity",
    Title = "Status",
    Content = "Loading..."
})

Tabs.Farm:AddToggle("AutoDig", { Title = "Auto Dig", Description = "Finds spots and digs them out", Default = false }):OnChanged(function(value)
    State.AutoDig = value
end)

local rarityValues = {}
local rarityDefaults = {}
for _, rarity in ipairs(RARITY_ORDER) do
    table.insert(rarityValues, rarity)
    table.insert(rarityDefaults, rarity)
end

Tabs.Farm:AddDropdown("DigRarities", {
    Title = "Spot rarities",
    Description = "Only dig spots with these rarities",
    Values = rarityValues,
    Multi = true,
    Search = false,
    Default = rarityDefaults
}):OnChanged(function(value)
    local selected = {}
    local any = false
    for _, rarity in ipairs(RARITY_ORDER) do
        selected[rarity] = false
    end
    for rarity, enabled in pairs(value) do
        if enabled then
            selected[rarity] = true
            any = true
        end
    end
    if not any then
        for _, rarity in ipairs(RARITY_ORDER) do
            selected[rarity] = true
        end
    end
    State.Rarities = selected
end)

Tabs.Farm:AddToggle("UseSurfaced", { Title = "Target surfaced items", Description = "Also dig rare items that spawn on the beach", Default = true }):OnChanged(function(value)
    State.UseSurfaced = value
end)

Tabs.Farm:AddSlider("SearchRadius", {
    Title = "Search radius",
    Description = "Maximum distance to a dig spot",
    Default = 200,
    Min = 40,
    Max = 500,
    Rounding = 0,
    Callback = function(value)
        State.SearchRadius = value
    end
})

Tabs.Items:AddSection("Cleaning", "droplets")

Tabs.Items:AddToggle("AutoClean", { Title = "Auto Clean", Description = "Cleans dirty items at your workbench", Default = false }):OnChanged(function(value)
    State.AutoClean = value
end)

Tabs.Items:AddSlider("CleanThreshold", {
    Title = "Clean after",
    Description = "Dirty items required before going to the workbench",
    Default = 1,
    Min = 1,
    Max = 20,
    Rounding = 0,
    Callback = function(value)
        State.CleanThreshold = value
    end
})

Tabs.Items:AddSection("Pedestals", "layout-grid")

local PedestalParagraph = Tabs.Items:AddParagraph({
    Icon = "list",
    Title = "Display",
    Content = "Loading..."
})

Tabs.Items:AddToggle("AutoPlace", { Title = "Auto Place", Description = "Fills free pedestals with your best items", Default = false }):OnChanged(function(value)
    State.AutoPlace = value
end)

Tabs.Items:AddToggle("SmartPlace", { Title = "Replace cheaper items", Description = "Swaps out low value items when a better one is found", Default = true }):OnChanged(function(value)
    State.SmartPlace = value
end)

Tabs.Items:AddSection("Selling", "coins")

Tabs.Items:AddToggle("AutoSell", { Title = "Auto Sell", Description = "Sells items that cannot go on a pedestal", Default = false }):OnChanged(function(value)
    State.AutoSell = value
end)

Tabs.Items:AddToggle("SellDirty", { Title = "Sell dirty items", Description = "Sells uncleaned items for a much lower price", Default = false }):OnChanged(function(value)
    State.SellDirty = value
end)

Tabs.Upgrades:AddSection("Auto Upgrade", "shopping-cart")

Tabs.Upgrades:AddParagraph({
    Icon = "info",
    Title = "How it works",
    Content = "Buys the next gear tier as soon as you can afford it and equips the best one you own."
})

Tabs.Upgrades:AddToggle("AutoShovel", { Title = "Auto Shovel", Description = "Buy and equip the best shovel", Default = false }):OnChanged(function(value)
    State.AutoShovel = value
end)

Tabs.Upgrades:AddToggle("AutoDetector", { Title = "Auto Detector", Description = "Buy and equip the best detector", Default = false }):OnChanged(function(value)
    State.AutoDetector = value
end)

Tabs.Upgrades:AddToggle("AutoSpray", { Title = "Auto Spray", Description = "Buy and equip the best spray bottle", Default = false }):OnChanged(function(value)
    State.AutoSpray = value
end)

Tabs.Upgrades:AddSlider("GoldReserve", {
    Title = "Gold reserve",
    Description = "Never spend below this amount",
    Default = 0,
    Min = 0,
    Max = 1000000,
    Rounding = 0,
    Callback = function(value)
        State.GoldReserve = value
    end
})

local GearParagraph = Tabs.Upgrades:AddParagraph({
    Icon = "package",
    Title = "Equipped gear",
    Content = "Loading..."
})

Tabs.Travel:AddSection("Islands", "map")

local TravelParagraph = Tabs.Travel:AddParagraph({
    Icon = "compass",
    Title = "Current island",
    Content = "Loading..."
})

task.spawn(function()
    local islands = fetchIslands()
    if #islands == 0 then
        Tabs.Travel:AddParagraph({ Icon = "alert-triangle", Title = "Islands", Content = "Island list is unavailable." })
        return
    end
    for _, entry in ipairs(islands) do
        IslandNames[entry.id] = entry.name
        local definition = Islands.Islands[entry.id]
        local cost = definition and definition.cost or 0
        local luck = definition and definition.luck or 1
        local description = "Luck x" .. tostring(luck)
        local unlocked = true
        pcall(function()
            local data = getData()
            unlocked = Islands.isIslandUnlocked(entry.id, data and data.UnlockedIslands) and true or false
        end)
        if cost > 0 and not unlocked then
            description = description .. "  |  unlock for " .. formatNumber(cost) .. " gold"
        end
        Tabs.Travel:AddButton({
            Title = entry.name,
            Description = description,
            Callback = function()
                task.spawn(travelToIsland, entry)
            end
        })
    end
end)

Tabs.Travel:AddSection("Places", "map-pin")

Tabs.Travel:AddButton({
    Title = "Dig area",
    Description = "Random spot on the sand of your island",
    Callback = function()
        task.spawn(function()
            local point = randomZonePoint()
            if point then
                teleport(point + Vector3.new(0, 3.5, 0))
            else
                notify("Travel", "No dig area on this island", 4)
            end
        end)
    end
})

Tabs.Travel:AddButton({
    Title = "Workbench",
    Description = "Your own plot",
    Callback = function()
        task.spawn(function()
            local bench = WorkbenchController and WorkbenchController.workbench
            if bench then
                teleport(bench:GetPivot().Position + Vector3.new(0, 4, 5))
            else
                notify("Travel", "Workbench not found", 4)
            end
        end)
    end
})

Tabs.Travel:AddButton({
    Title = "Seller",
    Description = "The NPC that buys your items",
    Callback = function()
        task.spawn(function()
            local seller = nearestSeller()
            if seller then
                teleport(seller + Vector3.new(0, 3, 4))
            else
                notify("Travel", "Seller not found", 4)
            end
        end)
    end
})

Tabs.Travel:AddButton({
    Title = "Gear shop",
    Description = "Shovels, detectors and sprays",
    Callback = function()
        task.spawn(function()
            local shop = nearestModel("GearNPC")
            if shop then
                teleport(shop + Vector3.new(0, 3, 4))
            else
                notify("Travel", "Gear shop not found", 4)
            end
        end)
    end
})

Tabs.Settings:AddSection("Behaviour", "sliders-horizontal")

Tabs.Settings:AddToggle("SafeTeleport", { Title = "Smooth teleport", Description = "Move in steps instead of instant jumps", Default = true }):OnChanged(function(value)
    State.SafeTeleport = value
end)

Tabs.Settings:AddToggle("AntiAfk", { Title = "Anti AFK", Description = "Prevents the idle kick", Default = true }):OnChanged(function(value)
    State.AntiAfk = value
end)

Tabs.Settings:AddButton({
    Title = "Unload",
    Description = "Stops every loop and closes the menu",
    Callback = function()
        if _G.DigCleanUnload then
            _G.DigCleanUnload()
        end
    end
})

_G.DigCleanUnload = function()
    State.Unloaded = true
    State.AutoDig = false
    State.AutoClean = false
    State.AutoPlace = false
    State.AutoSell = false
    State.AutoShovel = false
    State.AutoDetector = false
    State.AutoSpray = false
    _G.DigCleanUnload = nil
    task.delay(0.5, function()
        if WorkbenchController and WorkbenchController.cleaning and not WorkbenchController.session then
            releaseWorkbench()
        end
    end)
    pcall(function()
        Fluent:Destroy()
    end)
end

local function gearName(category)
    local info = GearCatalog[category]
    local data = getData()
    if not info or not data then
        return "?"
    end
    local id = data[info.equippedKey]
    local definition = id and info.defs[id]
    return (definition and definition.displayName) or tostring(id)
end

task.spawn(function()
    bindSurfacedEvents()
    refreshSurfaced()
    while not State.Unloaded do
        task.wait(20)
        refreshSurfaced()
    end
end)

task.spawn(function()
    while not State.Unloaded do
        local ok, err = pcall(function()
            if not isAlive() then
                Stats.action = "Waiting for character"
                task.wait(1)
                return
            end
            if WorkbenchController and WorkbenchController.cleaning then
                if WorkbenchController.session then
                    StuckSince = 0
                    Stats.action = "Cleaning"
                elseif StuckSince == 0 then
                    StuckSince = os.clock()
                elseif os.clock() - StuckSince > 8 then
                    StuckSince = 0
                    releaseWorkbench()
                end
                task.wait(0.3)
                return
            end
            StuckSince = 0
            if DigController and DigController.session then
                task.wait(0.2)
                return
            end
            if State.AutoClean and cleanStep() then
                return
            end
            if State.AutoSell and sellStep() then
                return
            end
            if State.AutoDig then
                digStep()
                return
            end
            Stats.action = "Idle"
        end)
        if not ok then
            Stats.action = "Error"
            warn("[Dig & Clean] " .. tostring(err))
            task.wait(1)
        end
        task.wait(0.15)
    end
end)

task.spawn(function()
    while not State.Unloaded do
        if State.AutoPlace then
            pcall(placeStep)
        end
        task.wait(2.5)
    end
end)

task.spawn(function()
    while not State.Unloaded do
        if State.AutoShovel then
            pcall(upgradeGear, "shovel")
        end
        if State.AutoDetector then
            pcall(upgradeGear, "detector")
        end
        if State.AutoSpray then
            pcall(upgradeGear, "spray")
        end
        task.wait(5)
    end
end)

task.spawn(function()
    while not State.Unloaded do
        pcall(function()
            local data = getData()
            local gold = data and data.Gold or 0
            local dirty = #dirtyTools()
            StatusParagraph:SetDesc(table.concat({
                "Action: " .. Stats.action,
                "Gold: " .. formatNumber(gold),
                "Backpack: " .. tostring(inventoryCount()) .. " / " .. tostring(BACKPACK_LIMIT),
                "Dirty items: " .. tostring(dirty),
                "Spots nearby: " .. tostring(nodeCount()),
                "Dug: " .. tostring(Stats.digs) .. "  Cleaned: " .. tostring(Stats.cleans)
            }, "\n"))
            local occupied, pending = readPedestals()
            local slots = pedestalSlots()
            local used, total = 0, 0
            local lowest, lowestName = math.huge, "-"
            for _, slot in ipairs(slots) do
                total = total + 1
                local item = occupied[slot]
                if item then
                    used = used + 1
                    local value = itemValue(item)
                    if value < lowest then
                        lowest, lowestName = value, tostring(item.id)
                    end
                end
            end
            PedestalParagraph:SetDesc(table.concat({
                "Pedestals: " .. tostring(used) .. " / " .. tostring(total),
                "Weakest: " .. lowestName .. " (" .. formatNumber(lowest == math.huge and 0 or lowest) .. ")",
                "Ready to place: " .. tostring(#pending),
                "Placed: " .. tostring(Stats.places) .. "  Swapped: " .. tostring(Stats.swaps),
                "Sold: " .. tostring(Stats.sold) .. " for " .. formatNumber(Stats.earned)
            }, "\n"))
            local islandId = data and data.CurrentIsland or "?"
            local islandDef = Islands.Islands[islandId]
            local unlocked = {}
            for _, id in pairs((data and data.UnlockedIslands) or {}) do
                table.insert(unlocked, IslandNames[id] or tostring(id))
            end
            TravelParagraph:SetDesc(table.concat({
                "Island: " .. (IslandNames[islandId] or tostring(islandId)),
                "Luck: x" .. tostring(islandDef and islandDef.luck or 1),
                "Unlocked: " .. (#unlocked > 0 and table.concat(unlocked, ", ") or "-")
            }, "\n"))
            GearParagraph:SetDesc(table.concat({
                "Shovel: " .. gearName("shovel"),
                "Detector: " .. gearName("detector"),
                "Spray: " .. gearName("spray"),
                "Purchases: " .. tostring(Stats.buys)
            }, "\n"))
        end)
        task.wait(1)
    end
end)

pcall(function()
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        if not State.AntiAfk or State.Unloaded then
            return
        end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end)

pcall(function()
    SaveManager:SetLibrary(Fluent)
    InterfaceManager:SetLibrary(Fluent)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({})
    InterfaceManager:SetFolder("DigAndClean")
    SaveManager:SetFolder("DigAndClean/config")
    InterfaceManager:BuildInterfaceSection(Tabs.Settings)
    SaveManager:BuildConfigSection(Tabs.Settings)
    SaveManager:LoadAutoloadConfig()
end)

Window:SelectTab(1)

notify("Dig & Clean", "Script loaded", 6)

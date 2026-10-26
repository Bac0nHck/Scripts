local environment = getgenv and getgenv() or _G
local previous = environment.SavetheKrustyKrab
local upgradeBudget = type(previous) == "table" and previous.UpgradeBudget
local repairBudget = type(previous) == "table" and previous.RepairBudget
if type(previous) == "table" and type(previous.Unload) == "function" then
	previous.Unload()
	task.wait(0.3)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualUser = game:GetService("VirtualUser")
local player = Players.LocalPlayer
if game.PlaceId ~= 77709018585862 then
	warn("Save the Krusty Krab: this place is not supported")
	return
end

local session = {Alive = true, Generation = 0, State = {}, Controls = {}, Connections = {}, Busy = false,
	UpgradeBudget = upgradeBudget, RepairBudget = repairBudget, Log = {}, LogStarted = os.clock(), LogDirty = true, ManualUntil = 0}
environment.SavetheKrustyKrab = session
local state, controls, connections = session.State, session.Controls, session.Connections
state.EnergyThreshold = 50
state.AutoFarm = false
state.Upgrades = false
state.Repair = false
state.DutchmanDeals = true
local features = {"Accept", "Cook", "Serve", "Bosses", "Plankton", "Troublemakers", "Revive", "Fire", "Clean", "Energy", "Skip", "NextShift", "Repair"}
local prompts, cooldowns = {}, setmetatable({}, {__mode = "k"})
local window, airflow, worker, ownedRegister, idleConnection, kickPath, cleaningBoss, cleaningStarted
local activeExtinguisher
local jobRank, jobKind, prioritySerial, jobSerial, actionLockUntil = 0, nil, 0, 0, 0
local generation, lastWarning = 0, 0
local libraryUrl = "https://github.com/PookiePepelsss/Airflow-UI"

local function addLog(message)
	if not session.Alive then return end
	message = tostring(message):gsub("[\r\n]+", " "):gsub("%.+%s*$", ""):sub(1, 180)
	table.insert(session.Log, {Time = os.clock() - session.LogStarted, Message = message})
	if #session.Log > 50 then table.remove(session.Log, 1) end
	session.LogDirty = true
end

local function syncAutoFarm()
	local enabled = true
	for _, name in features do if not state[name] then enabled = false break end end
	state.AutoFarm = enabled
	if controls.AutoFarm then controls.AutoFarm:Set(enabled, true) end
end

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function fetch(url)
	local ok, value = pcall(function() return game:HttpGet(url, true) end)
	return ok and type(value) == "string" and value or nil
end

local function notify(message)
	if session.Alive and window then window:Notify({Title = "Save the Krusty Krab", Content = tostring(message):gsub("%.+%s*$", ""), Duration = 3}) end
end

local function report(message)
	if os.clock() - lastWarning < 5 then return end
	lastWarning = os.clock()
	addLog("Action failed: " .. (tostring(message):match("^[^\r\n]+") or "Unknown error"))
	warn("Save the Krusty Krab: " .. tostring(message))
end

local function current()
	return session.Alive and generation == session.Generation and (jobRank == 0 or jobSerial == prioritySerial)
end

local function due(object, key)
	local times = cooldowns[object]
	return not times or (times[key] or 0) <= os.clock()
end

local function awaitResult(callback)
	local ok, success, result = pcall(function()
		local promise = callback()
		if type(promise) == "table" and type(promise.await) == "function" then
			return promise:timeout(3):await()
		end
		return true, promise
	end)
	if not ok then report(success) return false end
	if success == false then report(result) return false end
	return result ~= false, result
end

local function ready(object, key, delay)
	local times = cooldowns[object]
	if not times then times = {} cooldowns[object] = times end
	if (times[key] or 0) > os.clock() then return false end
	times[key] = os.clock() + (delay or 0.8)
	return true
end

local function invoke(object, key, callback, delay)
	if not current() or not ready(object, key, delay) then return false end
	return awaitResult(callback)
end

local function releaseRegister()
	local register = ownedRegister
	ownedRegister = nil
	if register and not register:IsDestroyed() and register.Instance:GetAttribute("OccupantId") == player.UserId then
		awaitResult(function() return register.Server:SetWorking(false) end)
	end
end

local function stopBossCleaning()
	local boss = cleaningBoss
	cleaningBoss, cleaningStarted = nil, nil
	if boss and not boss:IsDestroyed() then
		local token = {}
		session.CleaningRelease = token
		task.spawn(function()
			awaitResult(function() return boss.Server:SetCleaning(false) end)
			if session.CleaningRelease == token then session.CleaningRelease = nil end
		end)
	end
end

local function stopExtinguishing()
	local item = activeExtinguisher
	activeExtinguisher = nil
	if item and not item:IsDestroyed() then
		item:RemoveTask("ShootTask")
		local tool = item:GetTool()
		if tool then tool:Deactivate() end
	end
end

local function prepareAction()
	if cleaningBoss and jobKind ~= "BossHold" then stopBossCleaning() end
	if activeExtinguisher and jobKind ~= "Fire" then stopExtinguishing() end
	while current() and session.CleaningRelease do task.wait(0.05) end
	return current()
end

function session.StopAll(silent, farmOnly)
	session.Generation += 1
	session.PendingTeleport = nil
	session.PendingSip = nil
	session.ManualUntil = 0
	for _, name in features do
		state[name] = false
		if controls[name] then controls[name]:Set(false, true) end
	end
	if not farmOnly then
		state.Upgrades = false
		if controls.Upgrades then controls.Upgrades:Set(false, true) end
	end
	syncAutoFarm()
	stopBossCleaning()
	stopExtinguishing()
	if ownedRegister then task.spawn(releaseRegister) end
	if not silent then addLog("All tasks stopped") notify("All tasks stopped") end
end

local function setAntiAfk(enabled)
	if idleConnection then idleConnection:Disconnect() idleConnection = nil end
	state.AntiAfk = enabled == true
	if not state.AntiAfk then return end
	idleConnection = player.Idled:Connect(function()
		if not session.Alive or not state.AntiAfk then return end
		local ok, err = pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.zero)
		end)
		if not ok then report(err) end
	end)
end

function session.Unload()
	if not session.Alive then return end
	session.StopAll(true)
	session.Alive = false
	setAntiAfk(false)
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	if worker and coroutine.running() ~= worker and coroutine.status(worker) ~= "dead" then task.cancel(worker) end
	if kickPath then kickPath:Destroy() end
	if window then window:Destroy() end
	if environment.SavetheKrustyKrab == session then environment.SavetheKrustyKrab = nil end
end

local function module(path)
	local object = ReplicatedStorage:WaitForChild("src", 15)
	for part in path:gmatch("[^.]+") do object = object and object:WaitForChild(part, 10) end
	assert(object, "Game module unavailable: " .. path)
	return require(object)
end

local ok, setupError = xpcall(function()
	local restaurant = module("Systems.Restaurant.RestaurantStore")
	local restaurantController = module("Systems.Restaurant.RestaurantController")
	local restaurantToolkit = module("Systems.Restaurant.RestaurantToolkit")
	local cycle = module("Systems.GameCycle.GameCycleStore")
	local cycleController = module("Systems.GameCycle.GameCycleController")
	local workstation = module("Systems.Workstation.WorkstationStore")
	local registerSlice = module("Systems.Register.RegisterSlice")
	local tableToolkit = module("Systems.Table.TableToolkit")
	local npcToolkit = module("Systems.NPC.NPCToolkit")
	local grouperToolkit = module("Systems.NPC.DonGrouperToolkit")
	local planktonToolkit = module("Systems.NPC.PlanktonBallToolkit")
	local orbToolkit = module("Systems.Workstation.OrbOfConfusionToolkit")
	local dennisToolkit = module("Systems.NPC.DennisToolkit")
	local bubbleToolkit = module("Systems.NPC.DirtyBubbleToolkit")
	local upgradeToolkit = module("Systems.Upgrade.UpgradeToolkit")
	local dutchman = module("Systems.Dutchman.DutchmanStore")
	local dutchmanController = module("Systems.Dutchman.DutchmanController")
	local customPlayers = module("Systems.CustomPlayer.CustomPlayerHandler_ClientClass")
	local backpack = module("Systems.Backpack.BackpackHandler")
	local backpackSlice = module("Systems.Backpack.BackpackSlice")
	local inventoryController = module("Systems.Inventory.InventoryController")
	local itemToolkit = module("Shared.Item.ItemToolkit")
	local charm = module("Packages.Charm")
	local cameraController = module("Systems.Camera.CameraController")
	local cameraSlice = module("Systems.Camera.CameraSlice")
	local newspaper = module("Systems.Newspaper.NewspaperStore")
	local newspaperSlice = module("Systems.Newspaper.NewspaperSlice")
	local guiViews = module("Systems.UI.GuiViewManager")
	local dialogSlice = module("Systems.NPC.CharacterDialogSlice")
	local farmStats = {Started = os.clock(), ActiveTime = 0, Earned = 0, Spent = 0, Orders = 0, Served = 0, Shifts = 0, Repairs = 0, Revives = 0}
	local completedShifts = {}
	session.Stats = farmStats
	local function resetFarmStats()
		farmStats.Started = os.clock()
		for _, key in {"ActiveTime", "Earned", "Spent", "Orders", "Served", "Shifts", "Repairs", "Revives"} do farmStats[key] = 0 end
		table.clear(completedShifts)
		if cycle.State.CurrentPhase() == "EndOfDayReport" then completedShifts[cycle.State.CurrentDay()] = true end
	end
	local function observe(atom, callback)
		table.insert(connections, {Disconnect = charm.subscribe(atom, callback)})
	end
	observe(restaurant.State.Balance, function(value, previousValue)
		local id = tostring(player.UserId)
		local balance, previousBalance = value[id], previousValue and previousValue[id]
		if type(balance) == "number" and type(previousBalance) == "number" then
			local change = balance - previousBalance
			farmStats.Earned += math.max(0, change)
			farmStats.Spent += math.max(0, -change)
			if change ~= 0 then addLog(string.format("Cash %s$%d / balance $%d", change > 0 and "+" or "-", math.abs(change), balance)) end
		end
	end)
	observe(restaurant.State.DailyStats, function(value, previousValue)
		if not previousValue then return end
		local taken = math.max(0, (value.Orders or 0) - (previousValue.Orders or 0))
		local served = math.max(0, (value.OrdersCompleted or 0) - (previousValue.OrdersCompleted or 0))
		farmStats.Orders += taken
		farmStats.Served += served
		if taken > 0 then addLog("Crew accepted " .. taken .. " order(s)") end
		if served > 0 then addLog("Crew served " .. served .. " order(s)") end
	end)
	observe(cycle.State.CurrentPhase, function(phase)
		local day = cycle.State.CurrentDay()
		if phase == "EndOfDayReport" and not completedShifts[day] then
			completedShifts[day] = true
			farmStats.Shifts += 1
			addLog("Shift " .. day .. " completed")
		end
		if phase == "DayShift" then addLog("Shift " .. day .. " started") end
	end)
	observe(dutchman.State.Visit, function(visit, previousVisit)
		if visit and visit.TakenBy ~= nil and (not previousVisit or previousVisit.TakenBy == nil) then
			addLog("Dutchman deal taken by " .. tostring(visit.TakenBy))
		end
	end)
	local components = {}
	for _, name in {"Grill", "Fryer", "SodaMachine", "MilkShakeMachine", "AssemblingTable", "TrayCounter", "KelpShakeMachine", "OrbOfConfusionMachine"} do
		components[name] = module("Systems.Workstation.Components." .. name .. "_ClientComponent")
	end
	for name, path in {
		Register = "Register.Components.Register", Customer = "NPC.Components.Customer", Table = "Table.Components.Table",
		TrashBin = "Workstation.Components.TrashBin", Dumpster = "Workstation.Components.Dumpster",
		ShiftClock = "Restaurant.Components.ShiftClock", Tray = "Restaurant.Components.Tray",
		OrderBoard = "Restaurant.Components.RestaurantOrderBoard", MopGiver = "Trash.Components.MopGiver", Puddle = "Trash.Components.Puddle",
		Plankton = "NPC.Components.Plankton",
		Villain = "NPC.Components.Villain", DirtyBubble = "NPC.Components.DirtyBubble", Dennis = "NPC.Components.Dennis",
		UpgradeTable = "Upgrade.Components.UpgradeTable", DutchmanVendor = "Dutchman.Components.DutchmanVendor",
		Extinguisher = "Fire.Components.FireExtinguisher", ExtinguisherVendor = "Fire.Components.FireExtinguisherVendor",
	} do components[name] = module("Systems." .. path .. "_ClientComponent") end
	components.MagicConch = module("Components.MagicConch_ClientComponent")
	local fires = {}
	for _, object in CollectionService:GetTagged("Fire") do fires[object] = true end
	connect(CollectionService:GetInstanceAddedSignal("Fire"), function(object) fires[object] = true end)
	connect(CollectionService:GetInstanceRemovedSignal("Fire"), function(object) fires[object] = nil end)
	local exitNodes = {}
	local exitFolder = workspace:FindFirstChild("_PERSISTENT")
	for _, name in {"Villains", "Plankton", "PlanktonExitNodes"} do exitFolder = exitFolder and exitFolder:FindFirstChild(name) end
	if exitFolder then
		for _, node in exitFolder:GetDescendants() do if node:IsA("BasePart") then table.insert(exitNodes, node) end end
	end
	local function all(name) return components[name]:GetAll() end
	local function usable(component)
		local object = component.Instance
		return object:IsDescendantOf(workspace) and not component:IsDestroyed() and object:GetAttribute("Locked") ~= true
			and object:GetAttribute("Disabled") ~= true and object:GetAttribute("MischiefBlocked") ~= true
	end
	local function alive()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart")
	end
	local function moveTo(target, standoff)
		local root = alive()
		if not current() or not root or not target or not target.Parent then return false end
		local part = target:IsA("Model") and (target:FindFirstChild("ProximityPart") or target.PrimaryPart) or target
		if not part then return false end
		if not prepareAction() then return false end
		local zone = target:GetAttribute("ReachZoneCFrame")
		local zoneSize = target:GetAttribute("ReachZoneSize")
		local hasZone = typeof(zone) == "CFrame" and typeof(zoneSize) == "Vector3"
		local position = part:IsA("Attachment") and part.WorldPosition or part.Position
		local distance = (root.Position - position).Magnitude
		local localRoot = hasZone and zone:PointToObjectSpace(root.Position)
		local outsideZone = hasZone and (math.abs(localRoot.X) > zoneSize.X / 2 or math.abs(localRoot.Z) > zoneSize.Z / 2)
		if distance > (standoff and standoff + 2 or 4) or (standoff and distance < standoff - 1) or outsideZone then
			local desired = position + Vector3.new(0, 2, standoff or 3)
			if hasZone then
				local point = zone:PointToObjectSpace(desired)
				local halfX, halfZ = math.max(0, zoneSize.X / 2 - 0.5), math.max(0, zoneSize.Z / 2 - 0.5)
				desired = zone:PointToWorldSpace(Vector3.new(math.clamp(point.X, -halfX, halfX), point.Y, math.clamp(point.Z, -halfZ, halfZ)))
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = {player.Character, target}
			local ground = workspace:Raycast(desired + Vector3.new(0, 5, 0), Vector3.new(0, -18, 0), params)
			if ground then desired = Vector3.new(desired.X, ground.Position.Y + player.Character.Humanoid.HipHeight + root.Size.Y / 2, desired.Z) end
			root.CFrame = CFrame.lookAt(desired, Vector3.new(position.X, desired.Y, position.Z) + Vector3.new(0.001, 0, 0))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			task.wait(0.12)
		end
		return current() and alive() ~= nil
	end
	local function firePrompt(prompt, validate)
		if not current() or not prompt.Parent or not ready(prompt, "Prompt", 1) then return false end
		local target = prompt.Parent:IsA("Attachment") and prompt.Parent.Parent or prompt.Parent
		local model = target:FindFirstAncestorOfClass("Model")
		if not moveTo(model and model:GetAttribute("ReachZoneCFrame") and model or target) then return false end
		local deadline = os.clock() + 0.3
		while current() and prompt.Parent and not prompt.Enabled and os.clock() < deadline do task.wait(0.05) end
		if not prompt.Parent or not prompt.Enabled or not current() then return false end
		if validate and not validate() then return false end
		local fired, err = pcall(function()
			assert(type(fireproximityprompt) == "function", "Prompt interaction is unavailable")
			fireproximityprompt(prompt, prompt.HoldDuration)
		end)
		if not fired then report(err) end
		if fired and (prompt:HasTag("CleaningPrompt") or prompt.ActionText == "Wipe Table" or prompt.ActionText == "Mop") then actionLockUntil = os.clock() + 0.35 end
		return fired
	end
	local function tools()
		local result, seen = {}, {}
		for _, container in {player.Character, player:FindFirstChildOfClass("Backpack")} do
			if container then for _, tool in container:GetChildren() do
				if tool:IsA("Tool") then seen[tool] = true table.insert(result, tool) end
			end end
		end
		for _, list in {backpackSlice.State.HotbarContents(), backpackSlice.State.InventoryContents()} do
			for _, tool in list do
				if typeof(tool) == "Instance" and tool:IsA("Tool") and not seen[tool] then seen[tool] = true table.insert(result, tool) end
			end
		end
		return result
	end
	local function findTool(reference)
		for _, tool in tools() do
			if (tool:GetAttribute("ReferenceName") or tool.Name:match("^([%w]+)_[%x%-]+$") or tool.Name) == reference then return tool end
		end
	end
	local function hasInventoryRoom(amount)
		local inventory = inventoryController:GetMatchInventory()
		return not inventory or inventory:CanAddItem(amount or 1)
	end
	local function equip(tool)
		if not current() or not tool or not alive() then return false end
		if tool.Parent ~= player.Character then
			if not prepareAction() then return false end
			backpack:EquipTool(tool)
			task.wait(0.08)
		end
		return current() and tool.Parent == player.Character
	end
	local function firePosition(object)
		if object:IsA("BasePart") then return object, object.Position end
		if object:IsA("Attachment") then return object, object.WorldPosition end
		if object:IsA("Model") then return object, object:GetPivot().Position end
		local parent = object:FindFirstAncestorWhichIsA("BasePart") or object:FindFirstAncestorOfClass("Model")
		if parent then return parent, parent:IsA("Model") and parent:GetPivot().Position or parent.Position end
	end
	local function ownedExtinguisher()
		local blue
		for _, item in all("Extinguisher") do
			if item:IsDestroyed() or item:GetOwner() ~= player or not item:GetTool() then continue end
			if item:GetBaseData().ReferenceName == "FireExtinguisher" then return item end
			if (item:GetAttribute("Charge") or 0) >= 1 then blue = item end
		end
		return blue
	end
	local function aimAtFire(object, point, distance)
		local root = alive()
		if not root or not current() then return false end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {player.Character, object, workspace.CurrentCamera}
		params.RespectCanCollide = true
		params.CollisionGroup = root.CollisionGroup
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = params.FilterDescendantsInstances
		overlap.RespectCanCollide = true
		overlap.CollisionGroup = root.CollisionGroup
		overlap.MaxParts = 1
		local best, score
		local reach = math.min(14, distance * 0.7)
		for _, offset in {Vector3.new(0, 0, reach), Vector3.new(0, 0, -reach), Vector3.new(reach, 0, 0), Vector3.new(-reach, 0, 0)} do
			local stand = point + offset
			local ground = workspace:Raycast(stand + Vector3.new(0, 7, 0), Vector3.new(0, -24, 0), params)
			if not ground then continue end
			stand = Vector3.new(stand.X, ground.Position.Y + player.Character.Humanoid.HipHeight + root.Size.Y / 2, stand.Z)
			if math.abs(stand.Y - point.Y) > 6 or (stand - point).Magnitude > distance - 2 then continue end
			local obstruction = workspace:Raycast(stand, point - stand, params)
			if obstruction and (obstruction.Position - point).Magnitude > 6 then continue end
			local facing = CFrame.lookAt(stand, Vector3.new(point.X, stand.Y, point.Z))
			if #workspace:GetPartBoundsInBox(facing, Vector3.new(2.2, 2.5, 2.2), overlap) > 0 then continue end
			local gap = (root.Position - stand).Magnitude
			if not score or gap < score then best, score = facing, gap end
		end
		if not best then return false end
		if not prepareAction() then return false end
		root.CFrame = best
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if score > 1 then task.wait(0.12) end
		return current() and alive() == root
	end
	local fireActive, fireClearAt = false, nil
	local function returnExtinguisher(vendor)
		stopExtinguishing()
		if not ready(vendor, "FireReturn", 2) or not moveTo(vendor.Instance) or not current() or not state.Fire
			or vendor.Instance:GetAttribute("OccupantId") ~= player.UserId then return false end
		local success = awaitResult(function() return vendor.Server:ReturnExtinguisher() end)
		local deadline = os.clock() + 2
		while current() and success and vendor.Instance:GetAttribute("OccupantId") == player.UserId and os.clock() < deadline do task.wait(0.1) end
		if vendor.Instance:GetAttribute("OccupantId") ~= player.UserId then addLog("Fire extinguisher returned") end
		return true
	end
	local function extinguishFires(activeOnly)
		if not current() or not state.Fire then return false end
		local root = alive()
		if not root then return false end
		local target, targetFire, point, nearest, burning
		for object in fires do
			if not object:IsDescendantOf(workspace) or object:GetAttribute("Extinguished") == true or object:IsA("Fire") and not object.Enabled then continue end
			burning = true
			local anchor, position = firePosition(object)
			if not position then continue end
			local gap = (position - root.Position).Magnitude
			if not nearest or gap < nearest then target, targetFire, point, nearest = anchor, object, position, gap end
		end
		local ownedVendor, availableVendor
		for _, vendor in all("ExtinguisherVendor") do
			if not usable(vendor) then continue end
			local occupant = vendor.Instance:GetAttribute("OccupantId")
			if occupant == player.UserId then ownedVendor = vendor end
			if not occupant and (vendor.Instance:GetAttribute("CurrentCharge") or 0) >= 1 then availableVendor = vendor end
		end
		if not burning then
			if fireActive then fireActive = false addLog("All fires extinguished") end
			local previousTool = activeExtinguisher and not activeExtinguisher:IsDestroyed() and activeExtinguisher:GetTool()
			stopExtinguishing()
			if previousTool and previousTool.Parent == player.Character then backpack:UnequipTools() end
			if activeOnly then return false end
			if not ownedVendor then fireClearAt = nil return false end
			fireClearAt = fireClearAt or os.clock()
			if os.clock() - fireClearAt < 0.5 then return true end
			return returnExtinguisher(ownedVendor)
		end
		fireClearAt = nil
		if not fireActive then fireActive = true addLog("Fire detected") end
		if not target then return false end
		stopBossCleaning()
		local item = ownedExtinguisher()
		if not item then
			if not hasInventoryRoom() or ownedVendor or not availableVendor or not ready(availableVendor, "FireTake", 2) or not moveTo(availableVendor.Instance)
				or not current() or not state.Fire or availableVendor.Instance:GetAttribute("OccupantId") then return false end
			local success = awaitResult(function() return availableVendor.Server:TakeExtinguisher() end)
			local deadline = os.clock() + 2
			while current() and success and not ownedExtinguisher() and os.clock() < deadline do task.wait(0.1) end
			if ownedExtinguisher() then addLog("Fire extinguisher taken") return true end
			return false
		end
		if (item:GetAttribute("Charge") or 0) < 1 then
			stopExtinguishing()
			if ownedVendor then return returnExtinguisher(ownedVendor) end
			return false
		end
		if not due(item, "FireShot") or not item:_CanShoot() then return fireActive end
		local tool = item:GetTool()
		if not tool or not equip(tool) then return false end
		activeExtinguisher = item
		item:RemoveTask("ShootTask")
		local data = item:GetBaseData()
		if not aimAtFire(target, point, data.FireDistance or 20) or not target.Parent or not current() or not state.Fire then return false end
		if not fires[targetFire] or not targetFire:IsDescendantOf(workspace) or targetFire:GetAttribute("Extinguished") == true
			or targetFire:IsA("Fire") and not targetFire.Enabled then return false end
		if not item:_CanShoot() then return true end
		invoke(item, "FireShot", function() return item.Server:Shoot() end, math.max(0.2, data.FireRate or 0.2))
		return true
	end
	local function ordered()
		local list, ranks = table.clone(restaurant.Actions.sortRestaurantOrders()), {}
		for index, order in list do ranks[order] = index end
		table.sort(list, function(a, b)
			local first, second = a.CustomerReference == grouperToolkit.Constants.ReferenceName, b.CustomerReference == grouperToolkit.Constants.ReferenceName
			if first ~= second then return first end
			return ranks[a] < ranks[b]
		end)
		return list
	end
	local function energyValues()
		local cp = customPlayers:GetCustomPlayer()
		return cp and cp:GetAttribute("Energy"), cp and cp:GetAttribute("MaxEnergy")
	end
	local function canRefillEnergy(critical)
		if not state.Energy then return false end
		local energy, maximum = energyValues()
		local threshold = critical and math.min(state.EnergyThreshold, 15) or state.EnergyThreshold
		if type(energy) ~= "number" or type(maximum) ~= "number" or maximum <= 0 or energy >= maximum or energy > maximum * threshold / 100 then return false end
		local drink = findTool("KelpShake")
		if drink then return due(drink, "Drink") end
		if not hasInventoryRoom() then return false end
		for _, machine in all("KelpShakeMachine") do
			local timestamp = machine._remotes.ReadyTimestamp:Get()
			if usable(machine) and type(timestamp) == "number" and timestamp <= workspace:GetServerTimeNow() and due(machine, "Claim") then return true end
		end
		return false
	end
	local function customer(id)
		for _, component in all("Customer") do if component.Instance:GetAttribute("NPCUid") == id then return component end end
	end
	local planktonShots = setmetatable({}, {__mode = "k"})
	local function planktonClear(position, target, params)
		local lift = Vector3.new(0, 0.15, 0)
		local hit = workspace:Spherecast(position + lift, planktonToolkit.Constants.Diameter / 2 - 0.08, target - position, params)
		return not hit or hit.Normal.Y > 0.7
	end
	local function planktonTarget(position, goal, params)
		local box = planktonToolkit.getGoalBox(goal)
		local target = Vector3.new(box.Position.X, position.Y, box.Position.Z)
		if planktonClear(position, target, params) then return target end
		if not kickPath then kickPath = PathfindingService:CreatePath({AgentRadius = 1.6, AgentHeight = 3, AgentCanJump = false, WaypointSpacing = 8}) end
		local ok = pcall(function() kickPath:ComputeAsync(position, box.Position) end)
		local waypoint
		if ok and kickPath.Status == Enum.PathStatus.Success then
			for _, step in kickPath:GetWaypoints() do
				local point = Vector3.new(step.Position.X, position.Y, step.Position.Z)
				if (point - position).Magnitude > 3 then
					if not planktonClear(position, point, params) then break end
					waypoint = point
				end
			end
		end
		if waypoint then return waypoint end
		local best, score
		for _, node in exitNodes do
			if node.Parent then
				local point = Vector3.new(node.Position.X, position.Y, node.Position.Z)
				local distance = (point - position).Magnitude
				local cost = (point - target).Magnitude + distance * 0.05
				if distance > 4 and (not score or cost < score) and planktonClear(position, point, params) then best, score = point, cost end
			end
		end
		return best or target
	end
	local function planktonShot(position, target, goal, params, failures)
		local base = planktonToolkit.getKickDirection(target - position)
		if not base then return nil end
		local bestPower, bestDirection, bestScore
		for _, angle in {0, -40, 40, -80, 80, 180} do
			local direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(base)
			for _, power in {0, 0.25, 0.5, 0.75, 1} do
				if not current() then return nil end
				local velocity = planktonToolkit.getKickVelocity(direction, power)
				local points = planktonToolkit.predictPath(position, velocity, params)
				local last, scored = points[#points], false
				for _, point in points do if planktonToolkit.isInGoal(goal, point) then scored = true break end end
				local landing = Vector3.new(last.X, position.Y, last.Z)
				local moved = (landing - position).Magnitude
				local score = (landing - target).Magnitude + math.abs(last.Y - position.Y) * 0.3
				if moved < 2 then score += 40 end
				if scored then score -= 200 end
				for _, failed in failures do
					if direction:Dot(failed.Direction) > 0.9 and power <= failed.Power + 0.15 then score += 300 end
				end
				if scored and #failures == 0 then return power, direction end
				if not bestScore or score < bestScore then bestPower, bestDirection, bestScore = power, direction, score end
			end
			task.wait()
		end
		return bestPower, bestDirection
	end
	local function standForPlankton(npc, direction, range)
		local root = alive()
		if not root or not current() then return false end
		local object, position = npc.Instance, npc.Instance.PrimaryPart.Position
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {object, player.Character, workspace.CurrentCamera}
		params.RespectCanCollide = true
		params.CollisionGroup = root.CollisionGroup
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = params.FilterDescendantsInstances
		overlap.RespectCanCollide = true
		overlap.CollisionGroup = root.CollisionGroup
		overlap.MaxParts = 1
		for _, distance in {range > 5 and 4.5 or 3, 3.5} do
			for _, angle in {0, -40, 40, -80, 80} do
				local away = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(direction)
				local stand = position - away * distance
				local ground = workspace:Raycast(stand + Vector3.new(0, 7, 0), Vector3.new(0, -24, 0), params)
				if not ground then continue end
				stand = Vector3.new(stand.X, ground.Position.Y + player.Character.Humanoid.HipHeight + root.Size.Y / 2, stand.Z)
				if (stand - position).Magnitude > range - 0.3 then continue end
				local facing = CFrame.lookAt(stand, stand + direction)
				if #workspace:GetPartBoundsInBox(facing, Vector3.new(2.2, 2.5, 2.2), overlap) > 0 then continue end
				if not prepareAction() then return false end
				root.CFrame = facing
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				task.wait(0.12)
				return current() and root == alive() and usable(npc) and (root.Position - object.PrimaryPart.Position).Magnitude <= range
			end
		end
		return false
	end
	local function kickPlankton(urgentOnly)
		local goal = planktonToolkit.findGoal()
		for _, npc in all("Plankton") do
			local object, part = npc.Instance, npc.Instance.PrimaryPart
			if not usable(npc) or not part or object:GetAttribute("EscapedWithFormula") == true then continue end
			local record = planktonShots[npc]
			if not record then record = {Failures = {}} planktonShots[npc] = record end
			local scored = object:GetAttribute("GoalScoredAt")
			if type(scored) == "number" and scored > 0 then
				if not record.GoalLogged then record.GoalLogged = true addLog("Plankton kicked into the exit zone") end
				continue
			end
			if object:GetAttribute("Kicked") == true then continue end
			local ball = object:GetAttribute("Ball") == true
			local escaping = object:GetAttribute("HasFormula") == true and object:GetAttribute("Stopped") ~= true
			if urgentOnly and (ball or not escaping) then continue end
			if not ball then
				if escaping and ready(npc, "StopAim", 1) then
					local target = goal and planktonToolkit.getGoalBox(goal).Position or part.Position + Vector3.new(1, 0, 0)
					local direction = planktonToolkit.getKickDirection(target - part.Position)
					if direction and standForPlankton(npc, direction, 4.8) then
						return invoke(npc, "Stop", function() return npc.Server:Kick(nil, direction) end, 1)
					end
				end
				continue
			end
			if not goal then continue end
			local position, now = part.Position, os.clock()
			local velocity = part.AssemblyLinearVelocity
			local speed = (velocity * Vector3.new(1, 0, 1)).Magnitude
			if record.LastPosition and now > record.LastTime then
				speed = math.max(speed, ((position - record.LastPosition) * Vector3.new(1, 0, 1)).Magnitude / (now - record.LastTime))
			end
			record.LastPosition, record.LastTime = position, now
			local shot = record.Shot
			if shot then
				shot.Moved = math.max(shot.Moved, ((position - shot.Position) * Vector3.new(1, 0, 1)).Magnitude)
				if now - shot.Time < 1 or speed > 5 or math.abs(velocity.Y) > 7 then continue end
				if ((position - shot.Position) * Vector3.new(1, 0, 1)).Magnitude < 2 then
					table.insert(record.Failures, {Direction = shot.Direction, Power = shot.Power})
					if #record.Failures > 4 then table.remove(record.Failures, 1) end
					if ready(npc, "StuckLog", 10) then addLog("Plankton is stuck / changing kick direction") end
				else
					table.clear(record.Failures)
				end
				if (object:GetAttribute("BallKicks") or 0) <= shot.Count and ready(npc, "KickLog", 10) then addLog("Plankton kick was not confirmed / retrying from a clear position") end
				record.Shot = nil
			end
			if speed > 5 or math.abs(velocity.Y) > 7 or not ready(npc, "Aim", 0.8) then continue end
			local params = planktonToolkit.newRayParams({object, player.Character, workspace.CurrentCamera})
			local target = planktonTarget(position, goal, params)
			local power, direction = planktonShot(position, target, goal, params, record.Failures)
			if not direction or not current() or not (state.Plankton or state.Bosses) then return false end
			if (part.Position - position).Magnitude > 2 or not standForPlankton(npc, direction, 7.5) then continue end
			if not current() or not (state.Plankton or state.Bosses) or object:GetAttribute("Ball") ~= true
				or object:GetAttribute("Kicked") == true or object:GetAttribute("EscapedWithFormula") == true then return false end
			if not ready(npc, "Kick", 1) then continue end
			record.Shot = {Position = part.Position, Time = os.clock(), Count = object:GetAttribute("BallKicks") or 0,
				Direction = direction, Power = power, Moved = 0}
			awaitResult(function() return npc.Server:Kick(power, direction) end)
			return true
		end
		return false
	end
	local function removalAction(object)
		local action = object:GetAttribute("CustomerAction")
		if action == "Leaving" then return nil end
		if object:GetAttribute("ReferenceName") == "BubbleBass" and action == "TickleReady" and (object:GetAttribute("TickleChances") or 1) > 0 then return "Tickle" end
		if action == "Squatting" then return "KickOutSquatter" end
		if npcToolkit.isNuisance(object) then return "Shoo" end
	end
	local tickles = setmetatable({}, {__mode = "k"})
	local function removeTroublemakers()
		for _, npc in all("Customer") do
			if not usable(npc) then tickles[npc] = nil continue end
			local action, pending = removalAction(npc.Instance), tickles[npc]
			if pending then
				local phase = npc.Instance:GetAttribute("CustomerAction")
				if phase == "Tickling" and due(npc, "FinishTickle") and moveTo(npc:GetVisualModel() or npc.Instance) then
					invoke(npc, "FinishTickle", function() return npc.Server:BehaviorAction("FinishTickle", true) end, 2)
					return true
				elseif phase ~= "Tickling" and phase ~= "TickleReady" then
					tickles[npc] = nil
					addLog("Bubble Bass tickle completed")
				elseif os.clock() - pending > 5 and phase == "TickleReady" then tickles[npc] = nil end
			elseif action == "Tickle" and ready(npc, "Tickle", 3) then
				if not moveTo(npc:GetVisualModel() or npc.Instance) or removalAction(npc.Instance) ~= "Tickle" then continue end
				tickles[npc] = os.clock()
				local success, started = awaitResult(function() return npc.Server:BehaviorAction("StartTickle") end)
				if not success and started == false then tickles[npc] = nil end
				if success and started == true and session.Alive and generation == session.Generation and state.Troublemakers then
					if ready(npc, "FinishTickle", 2) then awaitResult(function() return npc.Server:BehaviorAction("FinishTickle", true) end) end
				end
				return true
			elseif action and action ~= "Tickle" and due(npc, "Remove") and type(npc.Server[action]) == "function" then
				if moveTo(npc:GetVisualModel() or npc.Instance) and removalAction(npc.Instance) == action then
					return invoke(npc, "Remove", function() return npc.Server[action](npc.Server) end, 2)
				end
			end
		end
		return false
	end
	local function busyCleaning()
		for _, name in {"Table", "Puddle", "Grill", "Fryer", "SodaMachine", "MilkShakeMachine", "AssemblingTable", "TrayCounter"} do
			for _, component in all(name) do if component.Instance:GetAttribute("CleaningPlayer") == player.UserId then return true end end
		end
		return false
	end
	local skippedCutscene
	observe(cameraSlice.State.InCutscene, function(inCutscene)
		if not inCutscene and skippedCutscene then addLog("Cutscene skipped") skippedCutscene = nil end
	end)
	local function closePopups()
		if not current() or not state.Skip or not ready(session, "Popups", 0.5) then return end
		local phase, day = cycle.State.CurrentPhase(), cycle.State.CurrentDay()
		local issue = newspaper.State.Today()
		if issue and issue.Event and issue.Day == day and phase == "DayShift" and not cycle.State.SpecialDay() then
			local key = tostring(issue.Day) .. ":" .. tostring(issue.Event)
			if newspaperSlice.State.DismissedKey() ~= key then
				newspaperSlice.Actions.dismiss(key)
				addLog("Dismissed newspaper: " .. tostring(issue.Event))
			end
		end
		if phase == "EndOfDayReport" then
			if session.DismissedReportDay ~= day and current() then
				session.DismissedReportDay = day
				cycleController.Server.DismissReport:Fire()
				addLog("Closed shift report")
			end
		elseif not ownedRegister then
			local name = guiViews:GetCurrentView()
			guiViews:CloseDismissibleViews()
			if name and name ~= guiViews.NoView and guiViews:GetCurrentView() ~= name then addLog("Closed game window: " .. name) end
		end
		local dialog = dialogSlice.State.Active()
		if dialog and dialog.Skippable then
			dialogSlice.Actions.skipActive()
			addLog("Skipped dialog")
		end
	end
	local function skipCutscene()
		if not current() or not state.Skip then return false end
		closePopups()
		local scene = cameraController._activeCutscene
		if not scene or scene == skippedCutscene or type(scene.Skip) ~= "function" then return false end
		if not ready(scene, "Skip", 1) then return false end
		cameraController:VoteSkipCutscene()
		if current() and state.Skip and cameraController._activeCutscene == scene then
			skippedCutscene = scene
			local success, err = pcall(scene.Skip)
			if not success then skippedCutscene = nil report(err) return false end
			return true
		end
		return false
	end
	local function reviveTeammates()
		local conch = findTool("MagicConch")
		for _, teammate in Players:GetPlayers() do
			if teammate == player then continue end
			local cp = customPlayers:GetCustomPlayer(teammate)
			local target = teammate.Character and (teammate.Character:FindFirstChild("HumanoidRootPart") or teammate.Character:FindFirstChild("ROOT_EFFECT_PART"))
			if not cp or cp:GetState("Alive") ~= false or not target then continue end
			if not conch then
				if ready(session, "NoConch", 30) then addLog("Revive waiting for a Magic Conch") end
				return false
			end
			for _, item in all("MagicConch") do
				if item:GetOwner() == player and item:GetTool() == conch and item._remotes and not item._processingRequest
					and ready(teammate, "Revive", 5) and moveTo(target) and equip(conch) and cp:GetState("Alive") == false then
					if not current() or not state.Revive then return false end
					local success = awaitResult(function() return item._remotes:AttemptRevive(teammate) end)
					local deadline = os.clock() + 3
					while current() and success and cp:GetState("Alive") == false and os.clock() < deadline do task.wait(0.1) end
					if cp:GetState("Alive") == true then
						farmStats.Revives += 1
						addLog("Revived " .. teammate.DisplayName)
					end
					return true
				end
			end
		end
		return false
	end
	local teleportLocations = {
		{"Cash Register", "Register", "EmployeeTarget"}, {"Kitchen", "AssemblingTable"}, {"Order Counter", "TrayCounter"},
		{"Free Kelp Shake", "KelpShakeMachine"}, {"Mop Rack", "MopGiver"}, {"Dumpster", "Dumpster"},
		{"Shift Clock", "ShiftClock"}, {"Upgrade Shop", "UpgradeTable"}, {"Flying Dutchman", "DutchmanVendor"},
	}
	local function queueTeleport(name)
		if not session.Alive then return end
		session.Generation += 1
		session.PendingTeleport = name
		session.ManualUntil = 0
		stopBossCleaning()
		stopExtinguishing()
		if ownedRegister then task.spawn(releaseRegister) end
		addLog("Teleport queued: " .. name)
	end
	local function teleportQueued()
		local name = session.PendingTeleport
		local root = alive()
		if not name or not root or not current() then return false end
		session.PendingTeleport = nil
		local origin, target, returning = root.CFrame, nil, name == "Previous Position"
		if returning then
			local saved = session.ReturnPosition
			if saved and saved.Character == player.Character then target = saved.CFrame end
		else
			for _, entry in teleportLocations do
				if entry[1] ~= name then continue end
				if entry[2] == "Dumpster" then
					for _, object in CollectionService:GetTagged("Dumpster") do if object:IsDescendantOf(workspace) then target = object break end end
				else
					for _, component in all(entry[2]) do
						local object = component.Instance
						if not object:IsDescendantOf(workspace) or component:IsDestroyed() then continue end
						if entry[2] == "UpgradeTable" and object:GetAttribute("Open") ~= true then continue end
						if entry[2] == "DutchmanVendor" and object:GetAttribute("Mode") ~= "Vendor" then continue end
						target = entry[3] and object:FindFirstChild(entry[3]) or object
						break
					end
				end
				break
			end
		end
		if not target then
			addLog(name .. " is unavailable")
			notify(name .. " is unavailable")
			return false
		end
		if returning then
			root.CFrame = target
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		elseif not moveTo(target) then return false end
		if not current() then return false end
		session.ReturnPosition = {Character = player.Character, CFrame = origin}
		session.ManualUntil = os.clock() + 5
		addLog("Teleported to " .. name)
		return true
	end
	local function serve(heldOnly)
		local carried = {}
		for _, tool in tools() do if tool.Parent then carried[tool] = true end end
		for _, order in ordered() do
			if order.OrderStatus == "Delivered" then continue end
			local npc = customer(order.CustomerId)
			if not npc or not usable(npc) or not due(npc, "Deliver") then continue end
			for _, component in all("Tray") do
				local tray = component:GetTool()
				if not tray or not carried[tray] or heldOnly == true and tray.Parent ~= player.Character or not component:_IsTrayCorrectForOrder(order) then continue end
				if equip(tray) and moveTo(npc:GetVisualModel() or npc.Instance) then
					local live = restaurant.State.RestaurantOrders()[order.OrderId]
					if live and live.OrderStatus ~= "Delivered" and usable(npc) and component:_IsTrayCorrectForOrder(live) then
						local success = invoke(npc, "Deliver", function() return restaurantController.Server:DeliverOrder(live.CustomerId) end)
						local deadline = os.clock() + 1
						while current() and success and tray.Parent and os.clock() < deadline do
							local latest = restaurant.State.RestaurantOrders()[order.OrderId]
							if not latest or latest.OrderStatus == "Delivered" then break end
							task.wait(0.05)
						end
						return success
					end
				end
				return false
			end
		end
		if heldOnly then return false end
		if not hasInventoryRoom() then return false end
		for _, order in ordered() do
			if order.OrderStatus ~= "Prepared" then continue end
			for _, counter in all("TrayCounter") do
				for _, model in counter.Instance:GetChildren() do
					if model:IsA("Model") and model:GetAttribute("OrderId") == order.OrderId then
						local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
						if prompt and prompt.Enabled and due(prompt, "Prompt") then
							return firePrompt(prompt, function()
								local live = restaurant.State.RestaurantOrders()[order.OrderId]
								return hasInventoryRoom() and live ~= nil and live.OrderStatus == "Prepared"
							end)
						end
					end
				end
			end
		end
		return false
	end
	local function collectMoney()
		for prompt in prompts do
			if prompt.Parent and prompt.Enabled and prompt.ObjectText == "Money" and prompt.ActionText == "Collect" and due(prompt, "Prompt") then return firePrompt(prompt) end
		end
		return false
	end
	local function refillEnergy()
		local energy, maximum = energyValues()
		if type(energy) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then return false end
		local pending = session.PendingSip
		if pending then
			if energy > pending.Energy or not pending.Tool.Parent or pending.Tool.Parent ~= player.Character or os.clock() >= pending.Deadline then
				session.PendingSip = nil
			else
				return true
			end
		end
		if energy >= maximum or energy > maximum * state.EnergyThreshold / 100 then return false end
		local drink = findTool("KelpShake")
		if drink then
			if due(drink, "Drink") and equip(drink) and current() and state.Energy and ready(drink, "Drink", 2) then
				if not prepareAction() then return false end
				session.PendingSip = {Tool = drink, Energy = energy, Deadline = os.clock() + 0.9}
				drink:Activate()
				return true
			end
			return false
		end
		if not hasInventoryRoom() then return false end
		for _, machine in all("KelpShakeMachine") do
			local timestamp = machine._remotes.ReadyTimestamp:Get()
			if usable(machine) and type(timestamp) == "number" and workspace:GetServerTimeNow() >= timestamp and due(machine, "Claim") and moveTo(machine.Instance) then
				return invoke(machine, "Claim", function() return machine._remotes:AttemptClaimKelpShake() end, 2)
			end
		end
		return false
	end
	local foodReady = setmetatable({}, {__mode = "k"})
	local function updateReadyFood()
		for _, name in {"Grill", "Fryer", "SodaMachine", "MilkShakeMachine"} do for _, machine in all(name) do
			local guid = usable(machine) and machine:_GetClaimableGuid()
			if not guid then foodReady[machine] = nil
			elseif not foodReady[machine] or foodReady[machine].Guid ~= guid then foodReady[machine] = {Guid = guid, Since = os.clock()} end
		end end
	end
	local function finishCooking(olderOnly)
		if not hasInventoryRoom() then return false end
		updateReadyFood()
		local selected, record
		for machine, entry in foodReady do
			if due(machine, entry.Guid) and (not olderOnly or os.clock() - entry.Since >= 0.75)
				and (not record or entry.Since < record.Since) then selected, record = machine, entry end
		end
		if selected and moveTo(selected.Instance) and current() and selected:_GetClaimableGuid() == record.Guid and ready(selected, record.Guid, 1) then
			selected:_FireFinishProcessing(record.Guid, true)
			return true
		end
		return false
	end
	local function acceptOrder()
		if not tableToolkit.AreSeatsAvailable() then return false end
		for _, register in all("Register") do
			local object = register.Instance
			local occupant = object:GetAttribute("OccupantId")
			if usable(register) and object:GetAttribute("HasCustomers") and (occupant == nil or ownedRegister == register) and ready(register, "Accept", 0.8) then
				if not moveTo(object:FindFirstChild("EmployeeTarget") or object) then return false end
				ownedRegister = register
				if occupant ~= player.UserId and not awaitResult(function() return register.Server:SetWorking(true) end) then
					releaseRegister()
					return false
				end
				local deadline, sent = os.clock() + 3, false
				while current() and state.Accept and os.clock() < deadline and tableToolkit.AreSeatsAvailable() do
					local correct = registerSlice.State.CorrectMenuItem()
					if correct and registerSlice.State.WorkingRegisterId() == object:GetAttribute("RegisterUID") then
						registerSlice.Signals.MenuItemSelected:Fire(correct)
						sent = true
						task.wait(0.06)
					elseif sent then break
					else task.wait(0.05) end
				end
				releaseRegister()
				return sent
			end
		end
		return false
	end
	local function cook()
		local pending, demand = {}, {}
		for _, order in ordered() do
			if (order.OrderStatus == "Pending" or order.OrderStatus == "Preparing") and (not order.WorkingPlayerId or order.WorkingPlayerId == player.UserId) then
				table.insert(pending, order)
				for _, item in order.OrderItems do
					for _, reference in item.Ingredients or {item.ReferenceName} do
						if not restaurantToolkit.isInfiniteIngredient(reference) then demand[reference] = (demand[reference] or 0) + 1 end
					end
				end
			end
		end
		if #pending == 0 then return false end
		local stock = workstation.State.AssemblingTableStash()
		local machines, processing = {}, {}
		for _, name in {"Grill", "Fryer", "SodaMachine", "MilkShakeMachine"} do for _, machine in all(name) do
			if usable(machine) and machine:IsClean() then
				local data = machine:GetProcessingData()
				if data then
					table.insert(machines, {Machine = machine, Data = data})
					for _, item in machine.Instance:GetChildren() do
						if item.Name:match("^ProcessingItem_") then
							local raw, output = item:GetAttribute("ReferenceName"), data.OutputItem
							for _, option in data.Options or {} do if option.ProcessingItem == raw then output = option.OutputItem end end
							if output then processing[output] = (processing[output] or 0) + (data.OutputAmount or 1) end
						end
					end
				end
			end
		end end
		local availableSupply, priorities = table.clone(stock), {}
		for reference, amount in processing do availableSupply[reference] = (availableSupply[reference] or 0) + amount end
		for index, order in pending do
			for _, item in order.OrderItems do for _, reference in item.Ingredients or {item.ReferenceName} do
				if not restaurantToolkit.isInfiniteIngredient(reference) then
					if (availableSupply[reference] or 0) > 0 then availableSupply[reference] -= 1
					elseif not priorities[reference] then priorities[reference] = index end
				end
			end end
		end
		for _, order in pending do
			local available, counts, items = true, {}, {}
			for _, item in order.OrderItems do
				for _, reference in item.Ingredients or {item.ReferenceName} do
					if not restaurantToolkit.isInfiniteIngredient(reference) then counts[reference] = (counts[reference] or 0) + 1 end
				end
				table.insert(items, {ReferenceName = item.ReferenceName, Finished = true, Metadata = {Ingredients = item.Ingredients and table.clone(item.Ingredients)}})
			end
			for reference, amount in counts do if (stock[reference] or 0) < amount then available = false break end end
			if available then
				for _, station in all("AssemblingTable") do
					if usable(station) and station:IsClean() and (station.Instance:GetAttribute("AvailableSlots") or 0) > 0 and due(station, "Assemble") then
						if not moveTo(station.Instance) then return false end
						local live = restaurant.State.RestaurantOrders()[order.OrderId]
						if not live or live.OrderStatus ~= "Pending" and live.OrderStatus ~= "Preparing" or live.WorkingPlayerId and live.WorkingPlayerId ~= player.UserId then return false end
						if not order.WorkingPlayerId then
							local board = all("OrderBoard")[1]
							if board and not invoke(board, order.OrderId, function() return board.Server:DeclareRestaurantOrderIntention(order.OrderId) end) then return false end
						end
						if not current() or not restaurant.State.RestaurantOrders()[order.OrderId] then return false end
						return invoke(station, "Assemble", function() return station.Server:AttemptToAssemble(items, order.OrderId) end)
					end
				end
			end
		end
		local selected, bestRank, bestDistance
		local root = alive()
		for _, entry in machines do
			local machine, data = entry.Machine, entry.Data
			if (machine.Instance:GetAttribute("AvailableSlots") or 0) > 0 and due(machine, "Start") then
				local options = data.Options or {Default = data}
				for optionName, option in options do
					local output = option.OutputItem or data.OutputItem
					if (stock[output] or 0) + (processing[output] or 0) < (demand[output] or 0) then
						local rank = priorities[output] or math.huge
						local distance = root and (machine.Instance:GetPivot().Position - root.Position).Magnitude or 0
						if not bestRank or rank < bestRank or rank == bestRank and distance < bestDistance then
							selected, bestRank, bestDistance = {Machine = machine, Option = data.Options and optionName or nil}, rank, distance
						end
					end
				end
			end
		end
		if selected and moveTo(selected.Machine.Instance) then
			local order = pending[bestRank]
			local live = order and restaurant.State.RestaurantOrders()[order.OrderId]
			if live and (live.OrderStatus == "Pending" or live.OrderStatus == "Preparing") then
				return invoke(selected.Machine, "Start", function() return selected.Machine._remotes:AttemptStartProcessing(selected.Option) end)
			end
		end
		return false
	end
	local function disposeTrash(tool, reference, validate, message)
		local destinations = reference == "Tray" and {"TrashBin"} or reference == "TrashBag" and {"Dumpster"} or {"TrashBin", "Dumpster"}
		for _, name in destinations do
			for _, container in all(name) do
				if validate and not validate() then return false end
				local object = container.Instance
				local prompt = object:FindFirstChildWhichIsA("ProximityPrompt", true)
				if not usable(container) or object:GetAttribute("Hidden") == true or object:GetAttribute("FullCapacity") == true
					or not prompt or not due(prompt, "Prompt") or not due(container, "Dispose") or not container:CanDisposeTool(tool) then continue end
				if not ready(container, "Dispose", 1.5) or not equip(tool) then return false end
				local count, amount = object:GetAttribute("DisposedCount") or 0, tool:GetAttribute("Amount") or 1
				if not firePrompt(prompt, function()
					return tool.Parent == player.Character and container:CanDisposeTool(tool) and prompt.ActionText == "Throw Away"
						and (not validate or validate())
				end) then continue end
				local deadline = os.clock() + 1.5
				repeat
					if not tool.Parent or (tool:GetAttribute("Amount") or amount) < amount
						or (object:GetAttribute("DisposedCount") or 0) > count and object:GetAttribute("LastDisposedBy") == player.UserId then
						addLog(message or (reference == "Tray" and "Removed an expired order tray" or reference == "TrashBag" and "Trash bag disposed" or "Trash disposed"))
						return true
					end
					if not current() then return false end
					task.wait(0.05)
				until os.clock() >= deadline
				ready(container, "Dispose", 3)
			end
		end
		return false
	end
	local function slasherActive()
		for _, object in CollectionService:GetTagged("HashSlingingSlasher") do
			if object:IsDescendantOf(workspace) and object:GetAttribute("Departing") ~= true and object:GetAttribute("Defeated") ~= true then return true end
		end
		return false
	end
	local orphanTrays = setmetatable({}, {__mode = "k"})
	local function trayHasSand(component)
		for _, item in component._trayItemsList or {} do
			if item.ReferenceName == grouperToolkit.Constants.SandyPatty then return true end
		end
		return false
	end
	local function trayNeedsDisposal(component, tool)
		if not tool.Parent or component:GetOwner() ~= player then return false end
		if trayHasSand(component) then return true end
		local id = tool:GetAttribute("OrderId")
		if type(id) ~= "string" or id == "" then return false end
		for _, order in restaurant.State.RestaurantOrders() do
			if order.OrderStatus == "Delivered" then continue end
			if order.OrderId == id then return false end
			local npc = customer(order.CustomerId)
			if npc and npc.Instance:GetAttribute("CustomerAction") ~= "Leaving" and npc.Instance:GetAttribute("Departing") ~= true
				and component:_IsTrayCorrectForOrder(order) then return false end
		end
		return true
	end
	local function manageInventory()
		if slasherActive() then return false end
		if not hasInventoryRoom() and state.Serve and serve("carried") then return true end
		for _, component in all("Tray") do
			local tool = component:GetTool()
			if not tool or component:GetOwner() ~= player or not tool.Parent then continue end
			if not trayNeedsDisposal(component, tool) then orphanTrays[tool] = nil continue end
			orphanTrays[tool] = orphanTrays[tool] or os.clock()
			local sandy = trayHasSand(component)
			if sandy or os.clock() - orphanTrays[tool] >= 3 then
				if disposeTrash(tool, "Tray", function() return trayNeedsDisposal(component, tool) end,
					sandy and "Reset a sand-covered order" or nil) then orphanTrays[tool] = nil return true end
			end
		end
		if not hasInventoryRoom() then
			for _, tool in tools() do
				local reference = tool:GetAttribute("ReferenceName")
				local data = reference and itemToolkit.getItemData(reference)
				if reference == "TrashBag" or reference == "TrashTray" or data and data.ItemType == "Trash" then
					if disposeTrash(tool, reference) then return true end
				end
			end
		end
		return false
	end
	local function clean(mode)
		if slasherActive() then return false end
		local bagsOnly, urgent = mode == "bags", mode == "urgent"
		local heldTrash, heldReference
		for _, tool in tools() do
			local reference = tool:GetAttribute("ReferenceName") or tool.Name:match("^([%w]+)_[%x%-]+$") or tool.Name
			local data = itemToolkit.getItemData(reference)
			if reference == "TrashBag" then heldTrash, heldReference = tool, reference break
			elseif not heldTrash and not bagsOnly and (reference == "TrashTray" or data and data.ItemType == "Trash") then heldTrash, heldReference = tool, reference end
		end
		if heldTrash then
			if disposeTrash(heldTrash, heldReference) then return true end
			if heldReference == "TrashBag" then return false end
		end
		local room = not heldTrash and hasInventoryRoom()
		local needed, pendingOrders = {}, false
		if urgent then
			local stock = workstation.State.AssemblingTableStash()
			for _, order in ordered() do
				if order.OrderStatus == "Pending" or order.OrderStatus == "Preparing" then
					pendingOrders = true
					for _, item in order.OrderItems do for _, reference in item.Ingredients or {item.ReferenceName} do
						if not restaurantToolkit.isInfiniteIngredient(reference) and (stock[reference] or 0) < 1 then needed[reference] = true end
					end end
				end
			end
		end
		local selected, best
		local root = alive()
		for prompt in prompts do
			if not prompt.Parent or not prompt.Enabled or not due(prompt, "Prompt") then continue end
			local model = prompt.Parent
			while model and model ~= workspace and not model:IsA("Tool") and not model:GetAttribute("ReferenceName") and not model:HasTag("DeliveredTray") do model = model.Parent end
			if model == workspace then model = nil end
			local reference = model and (model:GetAttribute("ReferenceName") or model.Name:match("^([%w]+)_[%x%-]+$") or model.Name)
			local data = reference and itemToolkit.getItemData(reference)
			local action, rank = prompt.ActionText, nil
			local pickup = action == "Empty Trash" or action == "Take Trash Bag" or action:lower():find("pick", 1, true) ~= nil
			if pickup and not room then continue end
			if reference == "TrashBag" and action:lower():find("pick", 1, true) then rank = 1
			elseif not bagsOnly then
				if room and model and (reference == "TrashTray" or model:HasTag("TrashTray") or model:HasTag("DeliveredTray")) then rank = 1
				elseif not urgent and data and data.ItemType == "Trash" and action:lower():find("pick", 1, true) then rank = 4
				elseif action == "Wipe Table" then
					if not urgent or not tableToolkit.AreSeatsAvailable() then rank = 2 end
				elseif prompt:HasTag("CleaningPrompt") then
					if not urgent then rank = 3
					elseif pendingOrders then
						for _, name in {"Grill", "Fryer", "SodaMachine", "MilkShakeMachine", "AssemblingTable", "TrayCounter"} do
							for _, station in all(name) do
								if usable(station) and prompt:IsDescendantOf(station.Instance) and not station:IsClean() then
									local processing = station.GetProcessingData and station:GetProcessingData()
									if name == "AssemblingTable" or name == "TrayCounter" or processing and needed[processing.OutputItem] then rank = 2 end
									for _, option in processing and processing.Options or {} do if needed[option.OutputItem] then rank = 2 end end
								end
							end
						end
					end
				end
			end
			if (action == "Empty Trash" or action == "Take Trash Bag") and (not urgent or heldTrash) then rank = bagsOnly and 2 or 5 end
			if rank then
				local target = prompt.Parent:IsA("Attachment") and prompt.Parent.Parent or prompt.Parent
				local point = target:IsA("BasePart") and target.Position or model and model:IsA("Model") and model:GetPivot().Position
				local score = rank * 10000 + (point and root and (point - root.Position).Magnitude or 0)
				if not best or score < best then selected, best = prompt, score end
			end
		end
		if selected then return firePrompt(selected) end
		if room and not urgent then
			for _, container in all("TrashBin") do
				local object = container.Instance
				if usable(container) and object:GetAttribute("Hidden") ~= true
					and (object:GetAttribute("FullCapacity") == true or object:GetAttribute("ReadyToEmpty") == true or object:GetAttribute("BagPile") == true) then
					local prompt = object:FindFirstChildWhichIsA("ProximityPrompt", true)
					if prompt and due(prompt, "Prompt") and moveTo(object) then
						if object:GetAttribute("FullCapacity") ~= true then
							if not prepareAction() then return false end
							backpack:UnequipTools()
							task.wait(0.05)
						end
						if firePrompt(prompt) then return true end
					end
				end
			end
		end
		if bagsOnly or urgent then return false end
		for _, puddle in all("Puddle") do
			if usable(puddle) and not puddle.Instance:GetAttribute("IsCleaning") and due(puddle, "Clean") then
				local mop = findTool("Mop") or findTool("InstaMop")
				if not mop then
					local giver = all("MopGiver")[1]
					if giver and hasInventoryRoom() and due(giver, "Mop") and moveTo(giver.Instance) then return invoke(giver, "Mop", function() return giver.Server:TakeMop() end) end
				elseif equip(mop) and moveTo(puddle.Instance) then
					local success = invoke(puddle, "Clean", function() return puddle.Server:AttemptMop() end)
					if success then actionLockUntil = os.clock() + 0.35 end
					return success
				end
			end
		end
		return false
	end
	local function bossModel(boss)
		return boss._visualModel or boss.Instance:FindFirstChild("VisualModel") or boss.Instance
	end
	local function bossEnded(object)
		return object:GetAttribute("Defeated") == true or object:GetAttribute("Departing") == true
			or object:GetAttribute("Stopped") == true or object:GetAttribute("IsCleaned") == true
			or object:GetAttribute("Confused") == true
	end
	local function escapeBosses()
		for _, boss in all("DirtyBubble") do
			if usable(boss) and boss.Instance:GetAttribute("CapturedPlayerId") == player.UserId then
				stopBossCleaning()
				stopExtinguishing()
				invoke(boss, "EscapeBoss", function() return boss.Server:EscapeBubble() end, 0.5)
				return true
			end
		end
		return false
	end
	local function useBossOrb(boss)
		local orb = findTool("OrbOfConfusion")
		if not orb and orbToolkit.isRecharged(player:GetAttribute("OrbOfConfusionReadyDay")) then orb = findTool("RechargingOrbOfConfusion") end
		if orb then
			session.PendingOrbClaim = nil
			if ready(orb, "UseBossOrb", 3) and equip(orb) and moveTo(bossModel(boss), 8) and current() and state.Bosses then
				if usable(boss) and not bossEnded(boss.Instance) then orb:Activate() return true, true end
			end
			return false, true
		end
		local claim = session.PendingOrbClaim
		if claim then
			local machine = claim.Machine
			local occupant = not machine:IsDestroyed() and machine.Instance:GetAttribute("OccupantId")
			if not machine:IsDestroyed() and (occupant == player.UserId or not occupant and os.clock() - claim.SentAt < 5) then return false, true end
			session.PendingOrbClaim = nil
		end
		for _, machine in all("OrbOfConfusionMachine") do
			local pending = cooldowns[machine]
			if usable(machine) and machine.Instance:GetAttribute("OccupantId") == player.UserId
				and orbToolkit.isRecharged(player:GetAttribute("OrbOfConfusionReadyDay")) and orbToolkit.isRecharged(machine._remotes.ReadyDay:Get())
				and pending and (pending.ClaimBossOrb or 0) > os.clock() then return false, true end
			if hasInventoryRoom() and usable(machine) and machine.Instance:GetAttribute("Unlocked") == true and not machine.Instance:GetAttribute("OccupantId")
					and orbToolkit.isRecharged(machine._remotes.ReadyDay:Get()) and due(machine, "ClaimBossOrb") and moveTo(machine.Instance) then
				if not current() or not ready(machine, "ClaimBossOrb", 3) then return false, false end
				session.PendingOrbClaim = {Machine = machine, SentAt = os.clock()}
				local claimed, result = awaitResult(function() return machine._remotes:AttemptClaimOrb() end)
				if not claimed and result == false then session.PendingOrbClaim = nil end
				return claimed, session.PendingOrbClaim ~= nil
			end
		end
		return false, false
	end
	local bossPayments = setmetatable({}, {__mode = "k"})
	local function defeatBosses(quickOnly)
		if not current() or not state.Bosses then return false end
		if quickOnly then
			local orbTarget, orbPriority = nil, -1
			for _, boss in all("Villain") do
				if usable(boss) and not bossEnded(boss.Instance) then
					local name = boss.Instance:GetAttribute("ReferenceName")
					if name == "HashSlingingSlasher" then continue end
					if name == "TattletaleStrangler" then
						for _, officer in CollectionService:GetTagged("PoliceOfficer") do
							local target = officer:FindFirstChild("Strangler")
							local prompt = officer:FindFirstChildWhichIsA("ProximityPrompt", true)
							if officer:IsDescendantOf(workspace) and target and target.Value == boss.Instance and prompt and prompt.Enabled and due(prompt, "Prompt") then
								if firePrompt(prompt) then return true end
							end
						end
					end
					if name ~= "Plankton" and name ~= "DirtyBubble" and name ~= "MiniDirtyBubble" then
						local priority = name == "ManRay" and 3 or name == "Dennis" and 2 or 1
						if priority > orbPriority then orbTarget, orbPriority = boss, priority end
					end
				end
			end
			local orbAvailable = false
			if orbTarget then
				local used
				used, orbAvailable = useBossOrb(orbTarget)
				if used then return true end
			end
			if not orbAvailable then
				for _, boss in all("Dennis") do
					if not bossPayments[boss] and usable(boss) and not bossEnded(boss.Instance) and workspace:GetServerTimeNow() >= (boss.Instance:GetAttribute("BribeableAt") or math.huge)
						and restaurant.Actions.getBalance(player) >= dennisToolkit.getBounty() and due(boss, "DennisPayoff") and moveTo(bossModel(boss), 9) then
						local bounty = dennisToolkit.getBounty()
						if not current() or not state.Bosses or not usable(boss) or bossEnded(boss.Instance)
							or workspace:GetServerTimeNow() < (boss.Instance:GetAttribute("BribeableAt") or math.huge)
							or restaurant.Actions.getBalance(player) < bounty or not ready(boss, "DennisPayoff", 2) then return false end
						bossPayments[boss] = true
						local success, paid = awaitResult(function() return boss.Server:AttemptPayOff() end)
						if not success and paid == false then bossPayments[boss] = nil end
						if success and (paid == true or bossEnded(boss.Instance)) then addLog("Paid Dennis $" .. bounty) end
						return success
					end
				end
			end
			return false
		end
		if cleaningBoss then
			local boss = cleaningBoss
			local object = boss.Instance
			if not usable(boss) or bossEnded(object) or object:GetAttribute("Airborne") == true
				or os.clock() - cleaningStarted > 20 then
				stopBossCleaning()
			else
				local mop = findTool("Mop") or findTool("InstaMop")
				if not mop or not equip(mop) or not moveTo(bossModel(boss), 8) then stopBossCleaning() return false end
				if object:GetAttribute("BeingCleaned") ~= true then
					invoke(boss, "CleanBoss", function() return boss.Server:SetCleaning(true) end, 1)
				end
				return true
			end
		end
		for _, boss in all("DirtyBubble") do
			local object = boss.Instance
			if usable(boss) and not bossEnded(object) and object:GetAttribute("Settled") == true and object:GetAttribute("Airborne") ~= true then
				local mop = findTool("Mop") or findTool("InstaMop")
				if not mop then
					local giver = all("MopGiver")[1]
					if giver and hasInventoryRoom() and due(giver, "BossMop") and moveTo(giver.Instance) then return invoke(giver, "BossMop", function() return giver.Server:TakeMop() end) end
				elseif due(boss, "CleanBoss") and equip(mop) and moveTo(bossModel(boss), 8) then
					if invoke(boss, "CleanBoss", function() return boss.Server:SetCleaning(true) end, 1) then
						cleaningBoss, cleaningStarted = boss, os.clock()
						if not current() or not state.Bosses then stopBossCleaning() end
						return true
					end
				end
			end
		end
		return false
	end
	local function mopNeeded()
		if state.Clean then
			for _, puddle in all("Puddle") do if usable(puddle) then return true end end
		end
		if state.Bosses then
			for _, boss in all("DirtyBubble") do if usable(boss) and not bossEnded(boss.Instance) then return true end end
		end
		return false
	end
	local function returnMop()
		if not current() or not (state.Clean or state.Bosses) then return false end
		local mop = findTool("Mop") or findTool("InstaMop")
		if not mop or mopNeeded() or cleaningBoss or session.CleaningRelease or busyCleaning() or os.clock() < actionLockUntil then
			session.MopIdleSince = nil
			return false
		end
		session.MopIdleSince = session.MopIdleSince or os.clock()
		if os.clock() - session.MopIdleSince < 0.5 then return false end
		for _, giver in all("MopGiver") do
			if not usable(giver) or giver._processingRequest or not due(giver, "MopReturn") then continue end
			if not moveTo(giver.Instance) or mopNeeded() or busyCleaning() or session.CleaningRelease or os.clock() < actionLockUntil then return false end
			if not findTool("Mop") and not findTool("InstaMop") then return false end
			local success = invoke(giver, "MopReturn", function() return giver.Server:ReturnMop() end, 3)
			local deadline = os.clock() + 1.5
			while current() and success and (findTool("Mop") or findTool("InstaMop")) and os.clock() < deadline do task.wait(0.05) end
			if not findTool("Mop") and not findTool("InstaMop") then
				session.MopIdleSince = nil
				addLog("Mop returned")
			end
			return success
		end
		return false
	end
	local pendingRepairs = setmetatable({}, {__mode = "k"})
	local function reconcileRepairs()
		for object, record in pendingRepairs do
			if object.Parent and object:GetAttribute("Destroyed") ~= true then
				record.Budget.Attempted[object] = nil
				pendingRepairs[object] = nil
				farmStats.Repairs += 1
				addLog("Repaired " .. object.Name .. " for $" .. record.Cost)
			elseif not object.Parent or os.clock() - record.SentAt > 10 then pendingRepairs[object] = nil end
		end
	end
	local function smartRepair(emergencyOnly)
		if not current() or not state.Repair then return false end
		for _, boss in all("Villain") do
			local name = boss.Instance:GetAttribute("ReferenceName")
			if usable(boss) and not bossEnded(boss.Instance) and (name == "Dennis" or name == "ManRay") then return false end
		end
		local phase = cycle.State.CurrentPhase()
		if phase ~= "NightShift" and phase ~= "DayShift" then return false end
		local used, seats = tableToolkit.getSeatUsage()
		local urgent = seats == 0 or used >= seats
		if emergencyOnly and not urgent then return false end
		if phase == "DayShift" and not urgent then return false end
		local selected, cost = nil, math.huge
		local existing = session.RepairBudget
		for _, item in all("Table") do
			if not usable(item) then continue end
			if item.Instance:GetAttribute("Destroyed") ~= true then continue end
			if existing and existing.Day == cycle.State.CurrentDay() and existing.Server == game.JobId and existing.Attempted[item.Instance] then continue end
			local price = tableToolkit.getRepairCost(item.Instance:GetAttribute("DestroyedStyle"))
			if type(price) == "number" and price >= 0 and price < cost then selected, cost = item, price end
		end
		if not selected then return false end
		local balance, day = restaurant.Actions.getBalance(player), cycle.State.CurrentDay()
		local budget = session.RepairBudget
		if not budget or budget.Day ~= day or budget.Server ~= game.JobId then
			budget = {Day = day, Server = game.JobId, Opening = balance, Spent = 0, Attempted = {}}
			session.RepairBudget = budget
		end
		budget.Limit = math.floor(budget.Opening * (urgent and 0.5 or 0.25))
		for object in budget.Attempted do if not object.Parent or object:GetAttribute("Destroyed") ~= true then budget.Attempted[object] = nil end end
		local object = selected.Instance
		if budget.Attempted[object] or balance - cost < 50 or budget.Spent + cost > budget.Limit
			or not ready(selected, "Repair", 8) or not moveTo(object) then return false end
		cost = tableToolkit.getRepairCost(object:GetAttribute("DestroyedStyle"))
		if not current() or not state.Repair or not usable(selected) or object:GetAttribute("Destroyed") ~= true
			or restaurant.Actions.getBalance(player) - cost < 50 or budget.Spent + cost > budget.Limit then return false end
		budget.Attempted[object] = true
		budget.Spent += cost
		pendingRepairs[object] = {Budget = budget, Cost = cost, SentAt = os.clock()}
		local success, result = awaitResult(function() return selected.Server:AttemptRepair() end)
		if not success and result == false then budget.Spent -= cost budget.Attempted[object] = nil pendingRepairs[object] = nil end
		local deadline = os.clock() + 3
		while current() and success and object.Parent and object:GetAttribute("Destroyed") == true and os.clock() < deadline do task.wait(0.1) end
		reconcileRepairs()
		return true
	end
	local function upgradeScore(reference)
		local data = upgradeToolkit.getUpgradeData(reference)
		if not data or data.Available == false or not (data.IsUnique or data.IsUniquePerPlayer)
			or upgradeToolkit.isUpgradeOwnedByPlayer(player, reference) or upgradeToolkit.isSuperseded(reference, player)
			or not upgradeToolkit.meetsPreRequisites(reference, player) or not upgradeToolkit.isTargetUnlocked(reference) then return 0 end
		local advanced = cycle.State.CurrentDay() >= upgradeToolkit.Constants.AdvancedTierDay
		if (data.Tier or 1) > 2 and not advanced then return 0 end
		local target = data.Metadata and data.Metadata.TargetWorkstation
		if target and target ~= "TrayCounter" then
			if reference:match("^Auto") then return 0 end
			local slots = 0
			for _, station in all(target) do
				if usable(station) then slots = math.max(slots, station.Instance:GetAttribute("UnlockedSlots") or 1) end
			end
			if slots == 0 then return 0 end
			if reference:match("^Insta") then return 130 end
			if reference:find("Speed", 1, true) then return 100 end
			if reference:find("Capacity", 1, true) and (slots < 3 or advanced) then return slots < 2 and 110 or 55 end
		elseif reference:match("^MoppingSpeed") or reference == "InstaMop" then return 95
		elseif reference:match("^CleaningSpeed") or reference == "InstaClean" then return 85
		elseif reference:match("^TrashCapacity") then return 50
		elseif advanced then
			if reference:match("^Jukebox") then return 75 end
			if reference:match("^MoreTables") or reference:match("^Metronome") then return 65 end
			if reference:match("^KelpShakeObsessed") then return 45 end
			if target == "TrayCounter" then return 30 end
			if reference == "InventoryCapacity1" then return 25 end
		end
		return 0
	end
	local function smartUpgrades()
		if not current() or not state.Upgrades or cycle.State.CurrentPhase() ~= "NightShift" then return false end
		local balance, day = restaurant.Actions.getBalance(player), cycle.State.CurrentDay()
		local budget = session.UpgradeBudget
		if not budget or budget.Day ~= day or budget.Server ~= game.JobId then
			budget = {Day = day, Server = game.JobId, Opening = balance, Limit = math.floor(balance * 0.3), Spent = 0, Attempted = {}, Started = os.clock()}
			session.UpgradeBudget = budget
		end
		local visit = dutchman.State.Visit()
		local waiting = os.clock() - (budget.Started or 0) < 8
		if state.DutchmanDeals and dutchman.State.Arriving() and waiting then return true end
		local dealKey = visit and ("Deal:" .. tostring(visit.Day) .. ":" .. tostring(visit.Tier))
		if state.DutchmanDeals and visit and visit.TakenBy == nil and #visit.Items > 0 and not budget.Attempted[dealKey] then
			for _, vendor in all("DutchmanVendor") do
				if usable(vendor) and vendor.Instance:GetAttribute("Mode") == "Vendor" then
					local prompt = vendor.Instance:FindFirstChildWhichIsA("ProximityPrompt", true)
					if prompt and prompt.Enabled and moveTo(prompt.Parent) and current() and state.Upgrades and state.DutchmanDeals
						and cycle.State.CurrentPhase() == "NightShift" and dutchman.State.Visit() == visit then
						budget.Attempted[dealKey] = true
						awaitResult(function() return dutchmanController.Server:TakeDeal() end)
						local deadline = os.clock() + 3
						while current() and os.clock() < deadline do
							local latest = dutchman.State.Visit()
							if not latest or latest.TakenBy ~= nil then break end
							task.wait(0.1)
						end
						return true
					end
				end
			end
			if waiting then return true end
		end
		local freeItems = {}
		if state.DutchmanDeals and visit and visit.TakenBy == nil then
			for _, item in visit.Items do if item.Upgrade then freeItems[item.Upgrade] = true end end
		end
		local customPlayer = customPlayers:GetCustomPlayer()
		local discount = customPlayer and customPlayer:GetAttribute("UpgradeShopDiscount") or 0
		local shop, selected, selectedCost, bestScore, shopOpening
		for _, vendor in all("UpgradeTable") do
			if not usable(vendor) then continue end
			if vendor.Instance:GetAttribute("Open") ~= true or vendor._purchaseRequest then shopOpening = true continue end
			for _, offer in vendor:GetAvailableUpgrades() or {} do
				local reference = offer.ReferenceName
				if offer.Amount <= 0 or budget.Attempted[reference] or freeItems[reference] then continue end
				local score = upgradeScore(reference)
				local data = upgradeToolkit.getUpgradeData(reference)
				local cost = data and upgradeToolkit.getDiscountedCost(data.Cost, discount)
				if score > 0 and cost and cost >= 0 and balance - cost >= 50 and budget.Spent + cost <= budget.Limit then
					local value = score / math.max(cost, 10)
					if not bestScore or value > bestScore then shop, selected, selectedCost, bestScore = vendor, offer, cost, value end
				end
			end
		end
		if not selected then return shopOpening and waiting or false end
		local display = (shop._upgradeDisplays or {})[selected.Slot]
		if not display or not moveTo(display.Model) or not current() or not state.Upgrades or cycle.State.CurrentPhase() ~= "NightShift" then return false end
		local latest = (shop:GetAvailableUpgrades() or {})[selected.Slot]
		balance = restaurant.Actions.getBalance(player)
		discount = customPlayer:GetAttribute("UpgradeShopDiscount") or 0
		selectedCost = upgradeToolkit.getDiscountedCost(upgradeToolkit.getUpgradeData(selected.ReferenceName).Cost, discount)
		if not latest or latest.ReferenceName ~= selected.ReferenceName or latest.Amount <= 0 or upgradeScore(selected.ReferenceName) <= 0
			or balance - selectedCost < 50 or budget.Spent + selectedCost > budget.Limit then return false end
		budget.Attempted[selected.ReferenceName] = true
		budget.Spent += selectedCost
		local success, result = awaitResult(function() return shop._remotes:AttemptPurchaseUpgrade(selected.Slot) end)
		if not success and result == false then budget.Spent -= selectedCost end
		local deadline = os.clock() + 3
		while current() and success and os.clock() < deadline and not upgradeToolkit.isUpgradeOwnedByPlayer(player, selected.ReferenceName) do task.wait(0.1) end
		if upgradeToolkit.isUpgradeOwnedByPlayer(player, selected.ReferenceName) then
			addLog("Purchased " .. upgradeToolkit.getUpgradeData(selected.ReferenceName).DisplayName .. " for $" .. selectedCost)
		end
		return true
	end
	local function fireThreat(nearOnly)
		if not state.Fire then return false end
		local root = alive()
		if not root then return false end
		local burning = false
		for object in fires do
			if object:IsDescendantOf(workspace) and object:GetAttribute("Extinguished") ~= true and (not object:IsA("Fire") or object.Enabled) then
				local _, point = firePosition(object)
				if point and (not nearOnly or (point - root.Position).Magnitude <= 12) then burning = true break end
			end
		end
		if not burning then return false end
		local item = ownedExtinguisher()
		if item and (item:GetAttribute("Charge") or 0) >= 1 then return true end
		if not hasInventoryRoom() then return false end
		for _, vendor in all("ExtinguisherVendor") do
			if usable(vendor) and not vendor.Instance:GetAttribute("OccupantId") and (vendor.Instance:GetAttribute("CurrentCharge") or 0) >= 1
				and due(vendor, "FireTake") then return true end
		end
		return false
	end
	local function bubbleAlmostDone()
		if not cleaningBoss or cleaningBoss:IsDestroyed() then return false end
		local rate = cleaningBoss.Instance:GetAttribute("CleanRate") or 0
		return rate > 0 and bubbleToolkit.getDirtiness(cleaningBoss.Instance) / rate <= 0.8
	end
	local function unresolvedThreat()
		if state.Bosses then for _, boss in all("Villain") do
			if usable(boss) and boss.Instance:GetAttribute("ReferenceName") ~= "HashSlingingSlasher" and not bossEnded(boss.Instance) then return true end
		end end
		if state.Plankton or state.Bosses then for _, npc in all("Plankton") do
			local object = npc.Instance
			if usable(npc) and object:GetAttribute("EscapedWithFormula") ~= true and object:GetAttribute("Kicked") ~= true and (object:GetAttribute("GoalScoredAt") or 0) <= 0
				and (object:GetAttribute("Ball") == true or object:GetAttribute("HasFormula") == true and object:GetAttribute("Stopped") ~= true) then return true end
		end end
		if state.Fire then
			for object in fires do
				if object:IsDescendantOf(workspace) and object:GetAttribute("Extinguished") ~= true and (not object:IsA("Fire") or object.Enabled) then return true end
			end
			for _, vendor in all("ExtinguisherVendor") do if usable(vendor) and vendor.Instance:GetAttribute("OccupantId") == player.UserId then return true end end
		end
		return false
	end
	local function nextShift()
		local phase = cycle.State.CurrentPhase()
		local pending = session.PendingClock
		if pending then
			if phase ~= "NightShift" or pending.Day ~= cycle.State.CurrentDay() then session.PendingClock = nil
			elseif not pending.Clock:IsDestroyed() and (pending.Clock.Instance:GetAttribute("Interactable") ~= true
				or (pending.Clock.Instance:GetAttribute("DayStartTimestamp") or 0) > workspace:GetServerTimeNow() or os.clock() - pending.SentAt < 8) then return false
			else session.PendingClock = nil end
		end
		if phase == "EndOfDayReport" then
			local day = cycle.State.CurrentDay()
			if session.DismissedReportDay ~= day and current() then
				session.DismissedReportDay = day
				cycleController.Server.DismissReport:Fire()
				return true
			end
		elseif phase == "NightShift" and not unresolvedThreat() and not busyCleaning() and not session.CleaningRelease then
			for _, clock in all("ShiftClock") do
				if usable(clock) and clock.Instance:GetAttribute("Interactable") == true and due(clock, "Clock")
					and (clock.Instance:GetAttribute("DayStartTimestamp") or 0) <= workspace:GetServerTimeNow() and moveTo(clock.Instance) then
					if cycle.State.CurrentPhase() ~= "NightShift" or not cycle.State.Running() or unresolvedThreat()
						or not usable(clock) or clock.Instance:GetAttribute("Interactable") ~= true
						or (clock.Instance:GetAttribute("DayStartTimestamp") or 0) > workspace:GetServerTimeNow() then return false end
					if not current() or not ready(clock, "Clock", 2) then return false end
					session.PendingClock = {Clock = clock, Day = cycle.State.CurrentDay(), SentAt = os.clock()}
					local success, result = awaitResult(function() return clock.Server:PunchClock() end)
					if not success and result == false then session.PendingClock = nil end
					return success
				end
			end
		end
		return false
	end
	local function runJob(rank, kind, callback, ...)
		if not current() then return true end
		jobRank, jobKind, jobSerial = rank, kind, prioritySerial
		session.ActiveTask = kind
		local ok, result = pcall(callback, ...)
		local cancelled = not current()
		jobRank, jobKind = 0, nil
		session.ActiveTask = nil
		if not ok or cancelled then
			stopBossCleaning()
			stopExtinguishing()
			if ownedRegister then task.spawn(releaseRegister) end
		end
		if not ok then error(result, 0) end
		return cancelled or result == true
	end
	local priorityFacts = {}
	local function refreshPriorities()
		local facts = {}
		local function fact(rank, kind, object) facts[kind .. ":" .. tostring(object)] = {Rank = rank, Kind = kind} end
		if state.Plankton or state.Bosses then for _, npc in all("Plankton") do
			local object, part = npc.Instance, npc.Instance.PrimaryPart
			if not usable(npc) or not part or object:GetAttribute("EscapedWithFormula") == true or object:GetAttribute("Kicked") == true
				or (object:GetAttribute("GoalScoredAt") or 0) > 0 then continue end
			if object:GetAttribute("Ball") ~= true then
				if object:GetAttribute("HasFormula") == true and object:GetAttribute("Stopped") ~= true and due(npc, "StopAim") and due(npc, "Stop") then fact(1, "Formula", npc) end
			else
				local velocity, shot = part.AssemblyLinearVelocity, planktonShots[npc] and planktonShots[npc].Shot
				if (velocity * Vector3.new(1, 0, 1)).Magnitude <= 5 and math.abs(velocity.Y) <= 7 and (not shot or os.clock() - shot.Time >= 1)
					and due(npc, "Aim") and due(npc, "Kick") and planktonToolkit.findGoal() then fact(1.5, "Plankton", npc) end
			end
		end end
		if state.Bosses then
			local orb = findTool("OrbOfConfusion")
			if not orb and orbToolkit.isRecharged(player:GetAttribute("OrbOfConfusionReadyDay")) then orb = findTool("RechargingOrbOfConfusion") end
			local orbReady = orb and due(orb, "UseBossOrb")
			if not orb then for _, machine in all("OrbOfConfusionMachine") do
				if hasInventoryRoom() and usable(machine) and machine.Instance:GetAttribute("Unlocked") == true and not machine.Instance:GetAttribute("OccupantId")
					and orbToolkit.isRecharged(machine._remotes.ReadyDay:Get()) and due(machine, "ClaimBossOrb") then orbReady = true end
			end end
			for _, boss in all("Villain") do
				if not usable(boss) or bossEnded(boss.Instance) or boss.Instance:GetAttribute("ReferenceName") == "HashSlingingSlasher" then continue end
				local name = boss.Instance:GetAttribute("ReferenceName")
				if orbReady and name ~= "Plankton" and name ~= "DirtyBubble" and name ~= "MiniDirtyBubble" then fact(1, "BossQuick", boss) end
			end
			for _, boss in all("Dennis") do
				if not orb and not bossPayments[boss] and not session.PendingOrbClaim and usable(boss) and not bossEnded(boss.Instance) and due(boss, "DennisPayoff")
					and workspace:GetServerTimeNow() >= (boss.Instance:GetAttribute("BribeableAt") or math.huge)
					and restaurant.Actions.getBalance(player) >= dennisToolkit.getBounty() then fact(1, "BossQuick", boss) end
			end
			for _, officer in CollectionService:GetTagged("PoliceOfficer") do
				local target, prompt = officer:FindFirstChild("Strangler"), officer:FindFirstChildWhichIsA("ProximityPrompt", true)
				if officer:IsDescendantOf(workspace) and target and target.Value and prompt and prompt.Enabled and due(prompt, "Prompt") then fact(1, "BossQuick", officer) end
			end
			for _, boss in all("DirtyBubble") do
				local object = boss.Instance
				if usable(boss) and object:GetAttribute("CapturedPlayerId") == player.UserId then fact(0.5, "Escape", boss)
				elseif usable(boss) and not bossEnded(object) and object:GetAttribute("Settled") == true and object:GetAttribute("Airborne") ~= true then
					local giver = all("MopGiver")[1]
					if findTool("Mop") or findTool("InstaMop") or giver and hasInventoryRoom() and due(giver, "BossMop") then fact(1.5, "BossHold", boss) end
				end
			end
		end
		if not bubbleAlmostDone() then
			if canRefillEnergy(true) then fact(1.25, "Energy", "Critical") end
			if fireThreat(true) then fact(1.25, "Fire", "Nearby") end
		end
		if fireThreat(false) then fact(2, "Fire", "Active") end
		if canRefillEnergy(false) then fact(2, "Energy", "Low") end
		if cycle.State.CurrentPhase() == "DayShift" then
			if state.Cook then
				updateReadyFood()
				for machine, entry in foodReady do if due(machine, entry.Guid) then fact(3, "Food", machine) end end
			end
			for id, order in restaurant.State.RestaurantOrders() do
				if state.Serve and order.OrderStatus == "Prepared" then fact(3, "Serve", id)
				elseif state.Cook and (order.OrderStatus == "Pending" or order.OrderStatus == "Preparing") then fact(3.5, "Cook", id) end
			end
		end
		if jobRank > 0 and jobSerial == prioritySerial then for key, entry in facts do
			if entry.Rank < jobRank and entry.Kind ~= jobKind and not priorityFacts[key] then
				prioritySerial += 1
				session.PriorityInterruptions = (session.PriorityInterruptions or 0) + 1
				break
			end
		end end
		priorityFacts = facts
	end
	local function farmTick()
		if state.Bosses and runJob(0.5, "Escape", escapeBosses) then return end
		local cp = customPlayers:GetCustomPlayer()
		if not cp then return end
		if session.PendingTeleport then
			if cp:CanPerformAction() and not busyCleaning() and os.clock() >= actionLockUntil and not cameraSlice.State.InCutscene() then teleportQueued() end
			return
		end
		if not cycle.State.Running() or session.ManualUntil > os.clock() or cameraSlice.State.InCutscene() then return end
		if not cp:CanPerformAction() or busyCleaning() or os.clock() < actionLockUntil then stopBossCleaning() stopExtinguishing() return end
		if state.NextShift and cycle.State.CurrentPhase() == "NightShift" and slasherActive() then
			if runJob(1, "NextShift", nextShift) then return end
		end
		if (state.Plankton or state.Bosses) and runJob(1, "Formula", kickPlankton, true) then return end
		if state.Bosses and runJob(1, "BossQuick", defeatBosses, true) then return end
		if state.Energy and session.PendingSip and runJob(1.25, "Energy", refillEnergy) then return end
		if not bubbleAlmostDone() then
			if canRefillEnergy(true) and runJob(1.25, "Energy", refillEnergy) then return end
			if fireThreat(true) and runJob(1.25, "Fire", extinguishFires, true) then return end
		end
		if state.Bosses and runJob(1.5, "BossHold", defeatBosses, false) then return end
		if (state.Plankton or state.Bosses) and runJob(1.5, "Plankton", kickPlankton, false) then return end
		if state.Fire and runJob(2, "Fire", extinguishFires, true) then return end
		if state.Energy and runJob(2, "Energy", refillEnergy) then return end
		if (state.Serve or state.Cook or state.Clean or state.Energy) and runJob(2.5, "Inventory", manageInventory) then return end
		if (state.Clean or state.Bosses) and runJob(2.75, "MopReturn", returnMop) then return end
		if cycle.State.CurrentPhase() == "DayShift" then
			if state.Serve and runJob(3, "Serve", serve, "carried") then return end
			if state.Cook and runJob(3, "Food", finishCooking, true) then return end
			if state.Serve and runJob(3, "Serve", serve, false) then return end
			if state.Cook and runJob(3, "Food", finishCooking, false) then return end
			if state.Repair and runJob(3.25, "Repair", smartRepair, true) then return end
			if state.Troublemakers and runJob(3.5, "Troublemakers", removeTroublemakers) then return end
			if state.Cook and runJob(3.5, "Cook", cook) then return end
			if state.Clean and runJob(3.5, "Clean", clean, "urgent") then return end
			if state.Accept and runJob(4, "Accept", acceptOrder) then return end
		else
			if state.Troublemakers and runJob(4, "Troublemakers", removeTroublemakers) then return end
		end
		if state.Revive and runJob(4.5, "Revive", reviveTeammates) then return end
		if state.Serve and runJob(5, "Money", collectMoney) then return end
		if state.Fire and runJob(5, "Fire", extinguishFires, false) then return end
		if state.Clean and runJob(5, "Clean", clean) then return end
		if state.Repair and runJob(5.5, "Repair", smartRepair, false) then return end
		if state.Upgrades and runJob(6, "Upgrades", smartUpgrades) then return end
		if state.NextShift then runJob(7, "NextShift", nextShift) end
	end
	local source = assert(fetch("https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"), "Airflow download failed")
	airflow = assert(loadstring(source, "@SavetheKrustyKrabAirflow"))()
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	airflow:AddTheme("Krusty", {Background = rgb(21, 20, 16), Surface = rgb(29, 27, 21), Surface2 = rgb(32, 30, 24),
		Surface3 = rgb(48, 43, 32), Stroke = rgb(67, 58, 38), StrokeHover = rgb(116, 94, 45),
		Accent = rgb(255, 189, 65), AccentDark = rgb(35, 26, 10), Text = rgb(242, 238, 228), Muted = rgb(174, 164, 142), Glow = rgb(219, 180, 105)})
	window = airflow:CreateWindow({Name = "Krusty Krab", LoadingSubtitle = "Save the Krusty Krab", Theme = "Krusty", Icon = "utensils",
		Size = UDim2.fromOffset(620, 500), MinSize = Vector2.new(280, 260), MaxSize = Vector2.new(620, 500),
		Parent = player:WaitForChild("PlayerGui"), ToggleUIKeybind = "RightControl", Loading = false,
		OpenButton = {Title = "Krusty Krab", Icon = "utensils"}, KeepOnScreen = true})
	session.Window = window
	local main = window:CreateTab({Name = "Main", Icon = "utensils"})
	local teleports = window:CreateTab({Name = "Teleports", Icon = "map-pin"})
	local statsTab = window:CreateTab({Name = "Stats", Icon = "chart-column"})
	local settings = window:CreateTab({Name = "Settings", Icon = "settings"})
	local tabs = {main, teleports, statsTab, settings}
	session.StatsTab = statsTab
	session.TeleportsTab = teleports
	controls.AutoFarm = main:CreateToggle({Name = "Auto Farm", CurrentValue = false, Callback = function(value)
		if not value then session.StopAll(true, true) return end
		session.Generation += 1
		for _, name in features do
			state[name] = true
			controls[name]:Set(true, true)
		end
		state.Upgrades = true
		controls.Upgrades:Set(true, true)
		syncAutoFarm()
	end})
	main:CreateDivider()
	for index, title in {"Auto Accept Orders", "Auto Cook", "Auto Serve", "Auto Defeat Bosses", "Auto Kick Plankton", "Auto Remove Troublemakers", "Auto Revive Teammates", "Auto Extinguish Fires", "Auto Clean", "Auto Refill Energy", "Auto Skip Cutscenes", "Auto Next Shift"} do
		local name = features[index]
		state[name] = false
		controls[name] = main:CreateToggle({Name = title, Desc = name == "Revive" and "Uses your Magic Conch" or name == "Skip" and "Scenes and game popups"
			or name == "Bosses" and "Orb first / Dennis bounty" or nil,
			CurrentValue = false, Callback = function(value)
			state[name] = value
			session.Generation += 1
			syncAutoFarm()
			if name == "Accept" and not value and ownedRegister then task.spawn(releaseRegister) end
			if name == "Bosses" and not value then stopBossCleaning() end
			if name == "Fire" and not value then stopExtinguishing() end
		end})
		if name == "Energy" then
			controls.EnergyThreshold = main:CreateSlider({Name = "Energy Threshold", Range = {1, 100}, Increment = 1,
				CurrentValue = state.EnergyThreshold, Suffix = "%", Callback = function(value)
					state.EnergyThreshold = value
				end})
		end
	end
	main:CreateSection("Spending")
	controls.Upgrades = main:CreateToggle({Name = "Smart Auto Upgrades", Desc = "30% nightly limit / $50 reserve", CurrentValue = false,
		Callback = function(value) state.Upgrades = value session.Generation += 1 end})
	controls.DutchmanDeals = main:CreateToggle({Name = "Flying Dutchman Deals", Desc = "Take every free deal", CurrentValue = state.DutchmanDeals,
		Callback = function(value) state.DutchmanDeals = value session.Generation += 1 end})
	local dealRow = controls.DutchmanDeals._frame
	dealRow.Size = UDim2.new(1, -16, 0, dealRow.Size.Y.Offset)
	dealRow.Parent:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Right
	controls.Repair = main:CreateToggle({Name = "Smart Auto Repair", Desc = "Tables / $50 reserve", CurrentValue = false,
		Callback = function(value) state.Repair = value session.Generation += 1 syncAutoFarm() end})
	main:CreateSection("Activity Log")
	local logPanel = main:Paragraph({Name = "Recent Activity", Content = ""})._frame
	logPanel:FindFirstChild("Content").Visible = false
	local logScroll = Instance.new("ScrollingFrame")
	logScroll.Name = "ActivityLog"
	logScroll.Size = UDim2.new(1, 0, 0, 180)
	logScroll.BackgroundTransparency = 1
	logScroll.BorderSizePixel = 0
	logScroll.ScrollBarThickness = 3
	logScroll.ScrollBarImageColor3 = airflow.Theme.Accent
	logScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logScroll.CanvasSize = UDim2.new()
	logScroll.LayoutOrder = 2
	logScroll.Parent = logPanel
	local logText = Instance.new("TextLabel")
	logText.Name = "Entries"
	logText.Size = UDim2.new(1, -8, 0, 0)
	logText.AutomaticSize = Enum.AutomaticSize.Y
	logText.BackgroundTransparency = 1
	logText.FontFace = airflow.Fonts.Regular
	logText.TextSize = 14
	logText.TextColor3 = airflow.Theme.Text
	logText.TextXAlignment = Enum.TextXAlignment.Left
	logText.TextYAlignment = Enum.TextYAlignment.Top
	logText.TextWrapped = true
	logText.Parent = logScroll
	local logFollow = true
	connect(logScroll:GetPropertyChangedSignal("CanvasPosition"), function()
		logFollow = logScroll.AbsoluteCanvasSize.Y - logScroll.AbsoluteWindowSize.Y - logScroll.CanvasPosition.Y <= 24
	end)
	connect(logScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"), function()
		if logFollow then logScroll.CanvasPosition = Vector2.new(0, math.max(0, logScroll.AbsoluteCanvasSize.Y - logScroll.AbsoluteWindowSize.Y)) end
	end)
	local function renderLog()
		if not session.LogDirty then return end
		local lines = {}
		for _, entry in session.Log do
			table.insert(lines, string.format("[%02d:%02d] %s", entry.Time // 60, math.floor(entry.Time) % 60, entry.Message))
		end
		logText.Text = #lines > 0 and table.concat(lines, "\n") or "No activity yet"
		session.LogDirty = false
	end
	controls.ClearLog = main:CreateButton({Name = "Clear Activity Log", Icon = "trash-2", Callback = function()
		table.clear(session.Log)
		session.LogDirty = true
		renderLog()
	end})
	session.LogView = logScroll
	session.TeleportControls = {}
	for _, entry in teleportLocations do
		local name = entry[1]
		session.TeleportControls[name] = teleports:CreateButton({Name = name, Icon = "map-pin", Callback = function() queueTeleport(name) end})
	end
	session.TeleportControls["Previous Position"] = teleports:CreateButton({Name = "Previous Position", Icon = "undo-2", Callback = function() queueTeleport("Previous Position") end})
	local statValues = {}
	local function statGroup(title, entries)
		local group = statsTab:Paragraph({Name = title, Content = ""})._frame
		group:FindFirstChild("Content").Visible = false
		for index, entry in entries do
			local row = Instance.new("Frame")
			row.Name = entry[1]
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 28)
			row.LayoutOrder = index + 1
			row.Parent = group
			for column = 1, 2 do
				local label = Instance.new("TextLabel")
				label.Name = column == 1 and "Title" or "Value"
				label.BackgroundTransparency = 1
				label.Size = UDim2.new(column == 1 and 0.58 or 0.42, -4, 1, 0)
				label.Position = UDim2.fromScale(column == 1 and 0 or 0.58, 0)
				label.FontFace = column == 1 and airflow.Fonts.Regular or airflow.Fonts.Medium
				label.TextSize = 14
				label.TextColor3 = column == 1 and airflow.Theme.Muted or airflow.Theme.Text
				label.TextXAlignment = column == 1 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
				label.Text = column == 1 and entry[2] or "--"
				label.Parent = row
				if column == 2 then statValues[entry[1]] = label end
			end
		end
	end
	statsTab:Label({Text = "Cash: you / Orders: whole crew"})
	statGroup("Game", {{"Day", "Day"}, {"Phase", "Phase"}, {"TimeLeft", "Time Left"}, {"Cash", "Cash"}, {"Energy", "Energy"},
		{"Rating", "Restaurant Rating"}, {"Orders", "Active Orders"}, {"Seats", "Seats Occupied"}, {"Customers", "Customers Left"}})
	statGroup("Farm Session", {{"Status", "Farm Status"}, {"Runtime", "Session Time"}, {"ActiveTime", "Farm Time"}, {"Earned", "Cash Earned"},
		{"Spent", "Cash Spent"}, {"Net", "Net Cash"}, {"Rate", "Net Cash / Hour"}, {"Taken", "Crew Orders Taken"},
		{"Served", "Crew Orders Served"}, {"Shifts", "Shifts Completed"}, {"Repairs", "Tables Repaired"}, {"Revives", "Teammates Revived"}})
	statGroup("Spending", {{"Budget", "Night Budget"}, {"RepairBudget", "Repair Budget"}, {"Reserve", "Cash Reserve"}, {"Deal", "Dutchman Deal"}})
	local function cashText(amount)
		local absolute = math.abs(amount)
		local value = absolute >= 1000000 and string.format("%.1fM", absolute / 1000000)
			or absolute >= 10000 and string.format("%.1fK", absolute / 1000) or tostring(math.floor(absolute + 0.5))
		return (amount < 0 and "-$" or "$") .. value
	end
	local function timeText(seconds)
		seconds = math.max(0, math.floor(seconds))
		return string.format("%02d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
	end
	local function refreshStats(elapsed)
		local enabled = state.Upgrades and 1 or 0
		for _, name in features do if state[name] then enabled += 1 end end
		local running, root = cycle.State.Running(), alive()
		local paused = session.ManualUntil > os.clock() or session.PendingTeleport ~= nil
		if enabled > 0 and running and root and not paused then farmStats.ActiveTime += elapsed end
		local runtime = os.clock() - farmStats.Started
		local net = farmStats.Earned - farmStats.Spent
		local day, phase = cycle.State.CurrentDay(), cycle.State.CurrentPhase()
		local active, prepared = 0, 0
		for _, order in restaurant.State.RestaurantOrders() do
			if order.OrderStatus ~= "Delivered" then active += 1 end
			if order.OrderStatus == "Prepared" then prepared += 1 end
		end
		local usedSeats, seats = tableToolkit.getSeatUsage()
		local cp = customPlayers:GetCustomPlayer()
		local energy, maximum = cp and cp:GetAttribute("Energy"), cp and cp:GetAttribute("MaxEnergy")
		local budget = session.UpgradeBudget
		local budgetCurrent = budget and budget.Day == day and budget.Server == game.JobId
		local repairs = session.RepairBudget
		local repairsCurrent = repairs and repairs.Day == day and repairs.Server == game.JobId
		local visit = dutchman.State.Visit()
		local endTime = cycle.State.PhaseEndTimestamp()
		local values = {
			Day = tostring(day), Phase = phase == "EndOfDayReport" and "Shift Report" or phase:gsub("(%l)(%u)", "%1 %2"),
			TimeLeft = phase == "DayShift" and endTime > 0 and timeText(endTime - workspace:GetServerTimeNow()) or "--",
			Cash = cashText(restaurant.Actions.getBalance(player)), Energy = type(energy) == "number" and type(maximum) == "number" and maximum > 0
				and string.format("%d%%", math.clamp(math.floor(energy / maximum * 100 + 0.5), 0, 100)) or "--",
			Rating = string.format("%.2f / 5", restaurant.State.StarRating()), Orders = tostring(active) .. " / " .. tostring(prepared) .. " ready",
			Seats = tostring(usedSeats) .. " / " .. tostring(seats), Customers = tostring(cycle.State.CustomersRemaining()),
			Status = paused and "Paused" or not running and "Paused" or not root and "Respawning" or enabled == 0 and "Idle" or "Running (" .. enabled .. ")",
			Runtime = timeText(runtime), ActiveTime = timeText(farmStats.ActiveTime), Earned = cashText(farmStats.Earned), Spent = cashText(farmStats.Spent),
			Net = cashText(net), Rate = runtime >= 10 and cashText(net * 3600 / runtime) or "--", Taken = tostring(farmStats.Orders),
			Served = tostring(farmStats.Served), Shifts = tostring(farmStats.Shifts), Reserve = "$50",
			Repairs = tostring(farmStats.Repairs), Revives = tostring(farmStats.Revives),
			Budget = budgetCurrent and (cashText(budget.Spent) .. " / " .. cashText(budget.Limit)) or "--",
			RepairBudget = repairsCurrent and (cashText(repairs.Spent) .. " / " .. cashText(repairs.Limit)) or "--",
			Deal = not state.Upgrades and "Paused" or not state.DutchmanDeals and "Disabled" or not visit and "Unavailable"
				or visit.TakenBy ~= nil and "Taken" or "Available",
		}
		for key, value in values do if statValues[key].Text ~= value then statValues[key].Text = value end end
	end
	local statsElapsed, priorityElapsed = 0, 0
	controls.ResetStats = statsTab:CreateButton({Name = "Reset Session Stats", Icon = "rotate-ccw", Callback = function()
		resetFarmStats()
		statsElapsed = 0
		refreshStats(0)
	end})
	connect(RunService.Heartbeat, function(elapsed)
		priorityElapsed += elapsed
		if priorityElapsed >= 0.1 then
			priorityElapsed = 0
			local success, err = pcall(refreshPriorities)
			if not success then report(err) end
		end
		statsElapsed += elapsed
		if statsElapsed < 1 then return end
		local interval = statsElapsed
		statsElapsed = 0
		refreshStats(interval)
		reconcileRepairs()
		renderLog()
	end)
	refreshStats(0)
	renderLog()
	settings:CreateSection("Session")
	controls.AntiAfk = settings:CreateToggle({Name = "Anti AFK", CurrentValue = true, Callback = setAntiAfk})
	settings:CreateButton({Name = "Stop All", Icon = "square", Callback = function() session.StopAll() end})
	controls.Keybind = settings:CreateKeybind({Name = "Menu Keybind", CurrentKeybind = "RightControl", OnChanged = function(key)
		if not key then key = Enum.KeyCode.RightControl controls.Keybind:Set(key, true) end
		window:SetKeybind(key)
	end})
	settings:CreateButton({Name = "Unload", Icon = "power", Callback = session.Unload})
	settings:CreateSection("Credits")
	local copyField
	local function copyLink(value)
		if not value then notify("The link is unavailable") return end
		local copy = setclipboard or toclipboard
		if type(copy) == "function" and pcall(copy, value) then notify("Link copied") return end
		if not copyField then copyField = settings:CreateInput({Name = "Link", Callback = function() end}) end
		copyField:Set(value, true)
		notify("Select and copy the link")
	end
	local creditsLink
	local creditsButton = settings:CreateButton({Name = "Credits - Loading", Icon = "copy", Callback = function() copyLink(creditsLink) end})
	settings:CreateButton({Name = "UI Library - Airflow", Icon = "copy", Callback = function() copyLink(libraryUrl) end})
	connect(workspace.DescendantAdded, function(object) if object:IsA("ProximityPrompt") then prompts[object] = true end end)
	connect(workspace.DescendantRemoving, function(object) prompts[object] = nil end)
	for _, object in workspace:GetDescendants() do if object:IsA("ProximityPrompt") then prompts[object] = true end end
	task.spawn(function()
		local text = fetch("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram.")
		if not text or not text:find("t.me/", 1, true) then text = fetch("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram") end
		if not session.Alive then return end
		local address = text and text:gsub("%s+", ""):match("^(https?://[^<>]+)$")
		if not address and text then address = text:gsub("%s+", ""):match("^(t%.me/[%w_/%-]+)$") end
		creditsLink = address and (address:match("^https?://") and address or "https://" .. address)
		creditsButton:SetTitle("Credits - " .. (address and address:gsub("^https?://", "") or "Unavailable"))
	end)

	local sidebar = window.Body:FindFirstChild("Sidebar")
	local separator
	for _, object in window.Body:GetChildren() do
		if object:IsA("Frame") and object.Size.X.Offset == 1 and object.Position.X.Offset == 170 then separator = object break end
	end
	local nav = Instance.new("Frame")
	nav.Name = "CompactNavigation"
	nav.BackgroundTransparency = 1
	nav.Size = UDim2.new(1, -52, 0, 88)
	nav.Parent = window.Body
	local navButtons = {}
	for index, tab in tabs do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0.5, -4, 0, 44)
		button.Position = UDim2.new((index - 1) % 2 * 0.5, 2, 0, (index - 1) // 2 * 44)
		button.BackgroundTransparency = 1
		button.Text = tab.Name
		button.TextSize = 14
		button.FontFace = airflow.Fonts.Medium
		button.TextColor3 = airflow.Theme.Text
		button.Parent = nav
		connect(button.Activated, function()
			window:SelectTab(tab)
			for target, item in navButtons do item.TextColor3 = target == tab and airflow.Theme.Accent or airflow.Theme.Muted end
		end)
		navButtons[tab] = button
	end
	window.OpenButton.Size = UDim2.fromOffset(0, 44)
	for _, object in controls.Keybind._frame:GetChildren() do
		if object:IsA("TextButton") then object.Size = UDim2.fromOffset(math.max(44, object.Size.X.Offset), 44) end
	end
	for _, object in window.Content:GetChildren() do
		if object:IsA("TextButton") then object.Size = UDim2.fromOffset(44, 44) end
	end
	local function resize(override)
		if not session.Alive then return end
		local viewport = typeof(override) == "Vector2" and override or window.Gui.AbsoluteSize
		if viewport.X <= 0 or viewport.Y <= 0 then return end
		local compact = viewport.X < 600
		window.Root.Size = UDim2.fromOffset(math.min(620, viewport.X - 24), math.min(500, viewport.Y - 24))
		sidebar.Visible = not compact
		if separator then separator.Visible = not compact end
		nav.Visible = compact
		window.Content.Position = UDim2.fromOffset(compact and 0 or 171, compact and 88 or 0)
		window.Content.Size = UDim2.new(1, compact and 0 or -171, 1, compact and -88 or 0)
		for _, tab in tabs do
			local padding = tab.List:FindFirstChildOfClass("UIPadding")
			padding.PaddingLeft = UDim.new(0, compact and 12 or 24)
			padding.PaddingRight = UDim.new(0, compact and 12 or 24)
		end
		window:_fitToScreen(true)
		window:_clampToScreen()
	end
	connect(window.Gui:GetPropertyChangedSignal("AbsoluteSize"), resize)
	connect(window.Content:GetPropertyChangedSignal("AbsoluteSize"), function()
		if nav.Visible then window.Indicator.Visible = false end
		for tab, button in navButtons do button.TextColor3 = window.CurrentTab == tab and airflow.Theme.Accent or airflow.Theme.Muted end
	end)
	connect(window.Gui.Destroying, function() if session.Alive then session.Unload() end end)
	resize()
	task.delay(0.3, function() if session.Alive then resize() end end)
	session.Resize = resize
	connect(player.CharacterRemoving, function()
		session.Generation += 1
		session.PendingSip = nil
		stopBossCleaning()
		stopExtinguishing()
		if ownedRegister then task.spawn(releaseRegister) end
	end)
	worker = task.spawn(function()
		while session.Alive do
			generation = session.Generation
			if state.Skip then
				local success, err = pcall(skipCutscene)
				if not success then report(err) end
			end
			local running = cycle.State.Running()
			local customPlayer = customPlayers:GetCustomPlayer()
			if (running or session.PendingTeleport) and alive() and customPlayer then
				session.Busy = true
				local success, err = pcall(farmTick)
				if not success then
					jobRank, jobKind = 0, nil
					stopBossCleaning()
					stopExtinguishing()
					if ownedRegister then task.spawn(releaseRegister) end
					report(err)
				end
				session.Busy = false
			elseif cleaningBoss or activeExtinguisher then
				stopBossCleaning()
				stopExtinguishing()
			end
			task.wait(0.15)
		end
	end)
end, debug.traceback)

if not ok then
	warn("Save the Krusty Krab: " .. tostring(setupError))
	session.Unload()
end

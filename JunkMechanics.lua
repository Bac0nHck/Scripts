local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Environment = type(getgenv) == "function" and getgenv() or _G

if type(Environment.JunkMechanicsHub) == "table" and type(Environment.JunkMechanicsHub.Unload) == "function" then
	pcall(Environment.JunkMechanicsHub.Unload)
end

local Hub = {
	Running = true,
	Connections = {},
	Cleanups = {},
	Toggles = {},
}
Environment.JunkMechanicsHub = Hub

local LibraryUrl = "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"
local CreditsUrl = "https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram"

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameData = Shared:WaitForChild("Data")
local ClientFolder = ReplicatedStorage:WaitForChild("Client")

local function findPath(root, path)
	local current = root
	for _, name in ipairs(path) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name) or current:WaitForChild(name, 5)
	end
	return current
end

local function loadModule(root, path)
	local module = findPath(root, path)
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok then
		return result
	end
	return nil
end

local Net = loadModule(Shared, { "Net" })
local ReplicaClient = loadModule(Shared, { "Libs", "ReplicaClient" })
local VehicleData = loadModule(GameData, { "Vehicles", "Data" }) or {}
local Pricing = loadModule(GameData, { "Vehicles", "Pricing" })
local CarPartsData = loadModule(GameData, { "CarParts", "Data" })
local JunkConstants = loadModule(GameData, { "Junk", "Constants" }) or {}
local Junkyards = loadModule(GameData, { "Junk", "Junkyards" })
local Networth = loadModule(GameData, { "Analytics", "Networth" })
local SellConstants = loadModule(GameData, { "Sell", "Constants" }) or {}
local Sellers = loadModule(GameData, { "Sell", "Sellers" }) or {}
local MachineCatalog = loadModule(GameData, { "Machines", "Catalog" }) or {}
local ProfileReplica = loadModule(ClientFolder, { "Services", "ProfileReplica" })
local ConfirmationService = loadModule(ClientFolder, { "Services", "ConfirmationService" })
local PaintMaterials = loadModule(GameData, { "PaintShop", "Materials" })
local RoadData = loadModule(GameData, { "RoadGraph" })
local PaintCosts = loadModule(GameData, { "PaintShop", "Costs" })
local VehicleModel = loadModule(Shared, { "Util", "VehicleModel" })
local GeneralData = loadModule(GameData, { "General", "Gen" })

if type(Net) ~= "table" then
	warn("Junk Mechanics: network module not found")
	return
end

local SellActions = SellConstants.Actions or { Accept = "Accept", Decline = "Decline", Negotiate = "Negotiate" }

local HoistStates, HoistActions
do
	local gameplay = findPath(ClientFolder, { "Controllers", "Gameplay" })
	local hoist = gameplay and gameplay:FindFirstChild("HoistMinigame")
	local seen = {}
	local function isEnum(value)
		local count = 0
		for key, item in pairs(value) do
			if type(key) ~= "string" or (type(item) ~= "string" and type(item) ~= "number") then
				return false
			end
			count = count + 1
		end
		return count >= 2 and count <= 12
	end
	local function scan(value, depth)
		if type(value) ~= "table" or seen[value] or depth > 3 then
			return
		end
		seen[value] = true
		if HoistActions == nil and rawget(value, "Complete") ~= nil and rawget(value, "Cancel") ~= nil and isEnum(value) then
			HoistActions = value
		end
		if HoistStates == nil and rawget(value, "Active") ~= nil and rawget(value, "Complete") == nil and isEnum(value) then
			HoistStates = value
		end
		for _, inner in pairs(value) do
			scan(inner, depth + 1)
		end
	end
	if hoist then
		for _, item in ipairs(hoist:GetDescendants()) do
			if item:IsA("ModuleScript") then
				local ok, result = pcall(require, item)
				if ok then
					scan(result, 0)
				end
			end
		end
	end
	if type(HoistActions) ~= "table" or type(HoistActions.Complete) ~= "number" then
		HoistActions = { Cancel = 0, Complete = 1 }
	end
	if type(HoistStates) ~= "table" or type(HoistStates.Active) ~= "number" then
		HoistStates = { Active = 0, Complete = 1, Cancelled = 2 }
	end
end

local Suffixes = { "", "K", "M", "B", "T", "Qa" }

local function formatNumber(value)
	value = tonumber(value) or 0
	local negative = value < 0
	value = math.abs(value)
	local index = 1
	while value >= 1000 and index < #Suffixes do
		value = value / 1000
		index = index + 1
	end
	local text
	if index == 1 then
		text = tostring(math.floor(value + 0.5))
	else
		text = string.gsub(string.format("%.2f", value), "%.?0+$", "") .. Suffixes[index]
	end
	return (negative and "-" or "") .. text
end

local function formatMoney(value)
	value = tonumber(value) or 0
	local sign = value < 0 and "-" or ""
	local digits = tostring(math.floor(math.abs(value) + 0.5))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	grouped = string.gsub(grouped, "^,", "")
	return sign .. "$" .. grouped
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	local rest = seconds % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, rest)
	end
	return string.format("%d:%02d", minutes, rest)
end

local function parseAmount(text)
	text = string.gsub(tostring(text or ""), "[%s,%$]", "")
	if text == "" then
		return 0
	end
	local number, suffix = string.match(text, "^(%d*%.?%d+)(%a*)$")
	number = tonumber(number)
	if not number then
		return nil
	end
	if suffix == "" then
		return number
	end
	for index, name in ipairs(Suffixes) do
		if name ~= "" and string.lower(name) == string.lower(suffix) then
			return number * 1000 ^ (index - 1)
		end
	end
	return nil
end

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function unit(vector, fallback)
	if vector.Magnitude < 0.001 then
		return fallback or Vector3.new(1, 0, 0)
	end
	return vector.Unit
end

local function getRoot()
	local character = LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
	local character = LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function raycast(origin, direction, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude or {}
	params.IgnoreWater = true
	return Workspace:Raycast(origin, direction, params)
end

local function getProfile()
	if type(ProfileReplica) ~= "table" then
		return nil
	end
	local replica = rawget(ProfileReplica, "_replica")
	if type(replica) == "table" and type(replica.Data) == "table" then
		return replica.Data
	end
	local ok, snapshot = pcall(function()
		return ProfileReplica:GetSnapshot()
	end)
	if ok and type(snapshot) == "table" then
		return snapshot
	end
	return nil
end

local function getMoney()
	local profile = getProfile()
	local economy = profile and profile.Economy
	return type(economy) == "table" and tonumber(economy.Money) or 0
end

local Status = {
	Text = "Idle",
	Detail = "",
	Since = os.clock(),
	Message = "-",
	Npc = "-",
	Log = {},
}

local function setStatus(text, detail)
	detail = detail and tostring(detail) or ""
	if Status.Text ~= text or Status.Detail ~= detail then
		Status.Since = os.clock()
		table.insert(Status.Log, 1, os.date("%H:%M:%S") .. " " .. text .. (detail ~= "" and (" - " .. detail) or ""))
		if #Status.Log > 60 then
			table.remove(Status.Log)
		end
	end
	Status.Text = text
	Status.Detail = detail
end

local Stats = {
	StartMoney = nil,
	StartTime = os.clock(),
	Bought = 0,
	Sold = 0,
	Spent = 0,
	Earned = 0,
	Errors = 0,
	Repaired = 0,
	Wheels = 0,
	WheelSpent = 0,
	LastCar = nil,
	LastProfit = nil,
	BestProfit = nil,
	Cycles = 0,
	CycleTime = 0,
}

local Job = {
	Running = false,
	Cancel = false,
	Name = nil,
}

local function checkpoint()
	if not Hub.Running or Job.Cancel then
		error("JobCancelled", 0)
	end
end

local function sleep(seconds)
	local deadline = os.clock() + (seconds or 0)
	repeat
		checkpoint()
		task.wait(math.clamp(deadline - os.clock(), 0, 0.1))
	until os.clock() >= deadline
	checkpoint()
end

local function waitFor(predicate, timeout, step)
	local deadline = os.clock() + (timeout or 5)
	while os.clock() < deadline do
		checkpoint()
		local ok, result = pcall(predicate)
		if ok and result then
			return result
		end
		task.wait(step or 0.1)
	end
	local ok, result = pcall(predicate)
	if ok and result then
		return result
	end
	return nil
end

function Hub.On(event, callback)
	if type(event) ~= "table" or type(event.On) ~= "function" then
		return
	end
	local ok, disconnect = pcall(event.On, callback)
	if ok and disconnect ~= nil then
		table.insert(Hub.Cleanups, disconnect)
	end
end

function Hub.Fire(event, ...)
	if type(event) ~= "table" or type(event.Fire) ~= "function" then
		return false
	end
	local ok = pcall(event.Fire, ...)
	return ok
end

local State = {
	Farm = false,
	AutoBuy = false,
	AutoRepair = false,
	AutoSell = false,
	AutoMinigames = true,
	AntiAfk = true,
	QuickTravel = true,
	DriveSpeed = 70,
	TravelMode = "Teleport",
	GlideSpeed = 150,
	PlayerTeleport = true,
	RepairBattery = true,
	RepairMechanical = true,
	RepairEngine = true,
	RepairRadiator = true,
	AutoMissingParts = true,
	FixWheels = true,
	WheelMinWear = 0.3,
	Paint = true,
	PaintColor = "Random",
	UseGarage = true,
	UseAllGarageCars = false,
	MinWear = 0.02,
	WashDelay = 3,
	WeldDelay = 6,
	Seller = "Juan",
	UseLupin = true,
	Negotiate = false,
	MaxRisk = 20,
	RickMinPercent = 90,
}

local Filter = {
	Tiers = {},
	Cars = {},
	Junkyards = {},
	MinPrice = 0,
	MaxPrice = 0,
	MinProfit = 0,
	MinMargin = 0,
	Reserve = 0,
	Sort = "Best Profit",
}

local CarOptions, CarByLabel = {}, {}
do
	local list = {}
	for key, info in pairs(VehicleData) do
		if type(info) == "table" and tonumber(info.Price) then
			table.insert(list, {
				Key = key,
				Name = tostring(info.DisplayName or key),
				Tier = tonumber(info.Tier) or 0,
				Price = tonumber(info.Price) or 0,
			})
		end
	end
	table.sort(list, function(a, b)
		if a.Tier ~= b.Tier then
			return a.Tier < b.Tier
		end
		return a.Price < b.Price
	end)
	for _, entry in ipairs(list) do
		local label = string.format("T%d %s", entry.Tier, entry.Name)
		if CarByLabel[label] then
			label = label .. " (" .. entry.Key .. ")"
		end
		CarByLabel[label] = entry.Key
		table.insert(CarOptions, label)
	end
end

local JunkyardList = {}
if type(Junkyards) == "table" and type(Junkyards.ByGrade) == "table" then
	for grade, info in pairs(Junkyards.ByGrade) do
		if type(info) == "table" then
			table.insert(JunkyardList, {
				Grade = grade,
				Name = tostring(info.DisplayName or ("Junkyard " .. tostring(grade))),
				Required = tonumber(info.RequiredNetworth) or 0,
				Fee = tonumber(info.TeleportFee) or 5000,
			})
		end
	end
	table.sort(JunkyardList, function(a, b)
		return a.Grade < b.Grade
	end)
end

local JunkyardOptions, JunkyardByLabel = {}, {}
for _, entry in ipairs(JunkyardList) do
	JunkyardByLabel[entry.Name] = entry.Grade
	table.insert(JunkyardOptions, entry.Name)
end

local JunkyardFallback = {
	[1] = Vector3.new(553, 83, -1828),
	[2] = Vector3.new(486, 83, -2052),
	[3] = Vector3.new(1949, 83, -198),
	[4] = Vector3.new(2053, 83, 845),
}

local Places = {
	Workshop = Vector3.new(524, 84, -1330),
	Juan = Vector3.new(860, 83, -1596),
	Rick = Vector3.new(497, 83, -1714),
	MrLupin = Vector3.new(1258, 84, -100),
}

local function junkyardInfo(grade)
	for _, entry in ipairs(JunkyardList) do
		if entry.Grade == grade then
			return entry
		end
	end
	return nil
end

local function junkyardCenter(grade)
	local buildings = Workspace:FindFirstChild("Buildings")
	local yard = buildings and buildings:FindFirstChild("JunkYard")
	local grades = yard and yard:FindFirstChild("Grades")
	local folder = grades and grades:FindFirstChild(tostring(grade))
	local npc = folder and folder:FindFirstChild("Zack")
	if npc and npc:IsA("Model") then
		return npc:GetPivot().Position
	end
	return JunkyardFallback[grade]
end

local function junkyardUnlocked(grade)
	local info = junkyardInfo(grade)
	if not info or info.Required <= 0 then
		return true
	end
	local profile = getProfile()
	if not (profile and type(Networth) == "table" and type(Networth.Compute) == "function") then
		return true
	end
	local ok, value = pcall(Networth.Compute, profile)
	if not ok then
		return true
	end
	return (tonumber(value) or 0) >= info.Required
end

local function nearestJunkyard(position)
	local bestGrade, bestDistance
	for _, entry in ipairs(JunkyardList) do
		local center = junkyardCenter(entry.Grade)
		if center then
			local distance = (flat(center) - flat(position)).Magnitude
			if not bestDistance or distance < bestDistance then
				bestGrade, bestDistance = entry.Grade, distance
			end
		end
	end
	return bestGrade, bestDistance
end

local Car = {}

function Car.Get()
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return nil
	end
	local named = folder:FindFirstChild(tostring(LocalPlayer.UserId))
	if named and named:IsA("Model") and named:GetAttribute("OwnerUserId") == LocalPlayer.UserId and named.PrimaryPart then
		return named
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("OwnerUserId") == LocalPlayer.UserId and model:GetAttribute("IsGarageDisplayVehicle") ~= true and model:GetAttribute("TutorialForUserId") == nil and model:GetAttribute("IsTestDrive") ~= true then
			return model
		end
	end
	return nil
end

function Car.Record(car)
	local profile = getProfile()
	local id = car and car:GetAttribute("GarageVehicleId")
	local garage = profile and profile.Garage
	local vehicles = type(garage) == "table" and garage.Vehicles
	if id and type(vehicles) == "table" then
		return vehicles[id]
	end
	return nil
end

function Car.Name(car)
	local key = car and car:GetAttribute("VehicleName")
	local info = key and VehicleData[key]
	return info and tostring(info.DisplayName or key) or tostring(key or "?"), key
end

function Car.Value(car)
	local record = Car.Record(car)
	local key = car and car:GetAttribute("VehicleName")
	if record and key and type(Pricing) == "table" and Pricing.ComputeStoredValue then
		local ok, value = pcall(Pricing.ComputeStoredValue, key, record)
		if ok and tonumber(value) then
			return value
		end
	end
	return nil
end

function Car.Condition(car)
	local record = Car.Record(car)
	local key = car and car:GetAttribute("VehicleName")
	if record and key and type(Pricing) == "table" and Pricing.ComputeStoredCondition then
		local ok, value = pcall(Pricing.ComputeStoredCondition, key, record)
		if ok and tonumber(value) then
			return value
		end
	end
	return nil
end

function Car.FullValue(key)
	if type(Pricing) == "table" and Pricing.ComputeSellPayout then
		local ok, value = pcall(Pricing.ComputeSellPayout, key, 1, 1)
		if ok and tonumber(value) then
			return value
		end
	end
	local info = VehicleData[key]
	local price = info and tonumber(info.Price) or 0
	local rate = info and tonumber(info.Profit) or 0
	return math.floor(price * (1 + math.clamp(rate, 0, 0.95)))
end

function Car.Seat(car)
	local seats = car and car:FindFirstChild("Seats")
	local seat = seats and seats:FindFirstChild("Drive")
	if seat and seat:IsA("BasePart") then
		return seat
	end
	return car and car:FindFirstChildWhichIsA("VehicleSeat", true)
end

function Car.Forward(car)
	local seat = Car.Seat(car)
	local look = seat and seat.CFrame.LookVector or -car:GetPivot().LookVector
	return unit(flat(look), Vector3.new(0, 0, -1))
end

function Car.Size(car)
	local _, size = car:GetBoundingBox()
	return math.max(size.X, size.Z) / 2, math.min(size.X, size.Z) / 2
end

function Car.PartsFolder(car)
	local primary = car and car.PrimaryPart
	return primary and primary:FindFirstChild("CarParts")
end

function Car.Installed(car, slot)
	local folder = Car.PartsFolder(car)
	if not folder then
		return nil
	end
	for _, item in ipairs(folder:GetChildren()) do
		if item.Name == slot and not item:IsA("Attachment") and item:GetAttribute("CarPart") == true then
			return item
		end
	end
	return nil
end

function Car.Drop(car)
	local primary = car and car.PrimaryPart
	local hitboxes = primary and primary:FindFirstChild("Hitboxes")
	local drop = hitboxes and hitboxes:FindFirstChild("Drop")
	if drop and drop:IsA("BasePart") then
		return drop
	end
	return nil
end

function Car.Hood(car)
	for _, item in ipairs(car:GetDescendants()) do
		if item:IsA("BasePart") and CollectionService:HasTag(item, "HoodPart") then
			return item
		end
	end
	local body = car:FindFirstChild("Body")
	local hood = body and body:FindFirstChild("Hood")
	if hood then
		if hood:IsA("BasePart") then
			return hood
		end
		return hood:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

function Car.HoodOpen(car)
	local hood = Car.Hood(car)
	local primary = car and car.PrimaryPart
	if not (hood and primary) then
		return nil
	end
	local relative = primary.CFrame:ToObjectSpace(hood.CFrame)
	return math.deg(math.acos(math.clamp(relative.UpVector.Y, -1, 1))) > 25
end

function Car.StandPoint(car, point)
	local center = car:GetPivot().Position
	local forward = Car.Forward(car)
	local halfLength = Car.Size(car)
	local front = center + forward * (halfLength + 3.5)
	local back = center - forward * (halfLength + 3.5)
	local choice = back
	if (front - point).Magnitude < (back - point).Magnitude then
		choice = front
	end
	local root = getRoot()
	return Vector3.new(choice.X, root and root.Position.Y or point.Y, choice.Z)
end

local SlotNeeds = {
	CylinderHead = "Engine",
	Transmission = "Engine",
	IntakeManifold = "CylinderHead",
	ExhaustManifold = "CylinderHead",
	Turbocharger = "CylinderHead",
	Supercharger = "CylinderHead",
}

function Car.SlotFilled(car, slot)
	local record = Car.Record(car)
	local slots = record and record.CarParts
	local info = type(slots) == "table" and slots[slot]
	if type(info) ~= "table" then
		return true
	end
	return type(info.Variant) == "string" and info.Variant ~= ""
end

function Car.MissingSlots(car)
	local list = {}
	local record = Car.Record(car)
	local slots = record and record.CarParts
	if type(slots) ~= "table" then
		return list
	end
	local groups = type(CarPartsData) == "table" and CarPartsData.Groups
	for slot, info in pairs(slots) do
		local group = type(groups) == "table" and groups[slot]
		local optional = type(group) == "table" and group.Optional == true
		if not optional and type(info) == "table" and info.Variant == "" then
			table.insert(list, slot)
		end
	end
	return list
end

local ExtractOrder = { "IntakeManifold", "ExhaustManifold", "Radiator", "Battery", "CylinderHead", "Transmission", "Engine" }
local ExtractRank = {}
for index, slot in ipairs(ExtractOrder) do
	ExtractRank[slot] = index
end

local Parts = {}

function Parts.Kind(slot)
	if slot == "Engine" then
		return "Engine"
	end
	local groups = type(CarPartsData) == "table" and CarPartsData.Groups
	local group = type(groups) == "table" and groups[slot]
	local partType = type(group) == "table" and group.Type
	if partType == "Mechanical" or partType == "Battery" or partType == "Washable" then
		return partType
	end
	if slot == "Battery" then
		return "Battery"
	end
	if slot == "Radiator" then
		return "Washable"
	end
	return nil
end

function Parts.Enabled(kind)
	if kind == "Battery" then
		return State.RepairBattery
	elseif kind == "Mechanical" then
		return State.RepairMechanical
	elseif kind == "Engine" then
		return State.RepairEngine
	elseif kind == "Washable" then
		return State.RepairRadiator
	end
	return false
end

function Parts.Worn(car)
	local list = {}
	local record = Car.Record(car)
	local slots = record and record.CarParts
	if type(slots) ~= "table" then
		return list
	end
	for slot, info in pairs(slots) do
		if type(info) == "table" and type(info.Variant) == "string" and info.Variant ~= "" then
			local wear = tonumber(info.Wear) or 0
			local kind = Parts.Kind(slot)
			if kind and wear > State.MinWear and Parts.Enabled(kind) then
				table.insert(list, { Slot = slot, Kind = kind, Wear = wear })
			end
		end
	end
	table.sort(list, function(a, b)
		return (ExtractRank[a.Slot] or 99) < (ExtractRank[b.Slot] or 99)
	end)
	return list
end

function Parts.Slot(item)
	local slot = item:GetAttribute("Slot")
	if type(slot) == "string" and slot ~= "" then
		return slot
	end
	local name = item:GetAttribute("CarPartName")
	if type(name) ~= "string" then
		return nil
	end
	if type(CarPartsData) == "table" and type(CarPartsData.GetVariant) == "function" then
		local ok, variant = pcall(CarPartsData.GetVariant, name)
		if ok and type(variant) == "table" and type(variant.Group) == "string" then
			return variant.Group
		end
	end
	return (string.match(name, "^([^:]+)"))
end

function Parts.Extracted(vehicleKey)
	local list = {}
	local folder = Workspace:FindFirstChild("ExtractedCarParts")
	if not folder then
		return list
	end
	for _, item in ipairs(folder:GetChildren()) do
		if item:GetAttribute("OwnerUserId") == LocalPlayer.UserId and Parts.Slot(item) ~= nil then
			local source = item:GetAttribute("SourceVehicleName")
			if vehicleKey == nil or source == nil or source == vehicleKey then
				table.insert(list, item)
			end
		end
	end
	return list
end

function Parts.FindExtracted(slot, vehicleKey)
	for _, item in ipairs(Parts.Extracted(vehicleKey)) do
		if Parts.Slot(item) == slot then
			return item
		end
	end
	return nil
end

function Parts.Body(target)
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

function Parts.Position(target)
	local body = Parts.Body(target)
	if body then
		return body.Position
	end
	if target:IsA("Model") then
		return target:GetPivot().Position
	end
	return nil
end

function Parts.Wear(target)
	return tonumber(target:GetAttribute("Wear")) or 0
end

local Carry = {
	Target = nil,
	Goal = nil,
	LastSend = 0,
}

table.insert(Hub.Connections, RunService.PostSimulation:Connect(function()
	local target = Carry.Target
	if not target then
		return
	end
	if not target.Parent or target:GetAttribute("DraggedByUserId") ~= LocalPlayer.UserId then
		return
	end
	local root = getRoot()
	if not root then
		return
	end
	local goal = Carry.Goal
	if typeof(goal) ~= "Vector3" then
		goal = root.Position + unit(flat(root.CFrame.LookVector)) * 4.5 + Vector3.new(0, Carry.Height or 1.5, 0)
	end
	local body = Parts.Body(target)
	local align = body and body:FindFirstChildOfClass("AlignPosition")
	if align then
		align.Position = goal
	end
	local now = os.clock()
	if now - Carry.LastSend >= 1 / 30 then
		Carry.LastSend = now
		pcall(Net.DragPositionUpdated.Fire, goal.X, goal.Y, goal.Z)
	end
end))

function Parts.Grab(target)
	if target:GetAttribute("DraggedByUserId") == LocalPlayer.UserId then
		Carry.Target = target
		Carry.Goal = nil
		return true
	end
	for _ = 1, 3 do
		checkpoint()
		if not target.Parent or target:GetAttribute("InMachine") == true then
			return false
		end
		Hub.Fire(Net.DragGrabRequested, target)
		local grabbed = waitFor(function()
			local body = Parts.Body(target)
			return target:GetAttribute("DraggedByUserId") == LocalPlayer.UserId and body ~= nil and body:FindFirstChildOfClass("AlignPosition") ~= nil
		end, 2)
		if grabbed then
			Carry.Target = target
			Carry.Goal = nil
			return true
		end
		sleep(0.3)
	end
	return false
end

function Parts.Release()
	Carry.Target = nil
	Carry.Goal = nil
	Hub.Fire(Net.DragReleaseRequested)
end

local Machines = {}

local MachineTags = {
	Battery = MachineCatalog.BatteryCharger and MachineCatalog.BatteryCharger.Tag or "BATTERY_CHARGER",
	Mechanical = MachineCatalog.GrindingMachine and MachineCatalog.GrindingMachine.Tag or "GRINDING_MACHINE",
	Engine = MachineCatalog.Hoist and MachineCatalog.Hoist.Tag or "HOIST_MACHINE",
	Washable = MachineCatalog.Sink and MachineCatalog.Sink.Tag or "SINK",
}

local MachineSpots = {
	Battery = MachineCatalog.BatteryCharger and MachineCatalog.BatteryCharger.PositionTag or "BatteryChargerPos",
	Mechanical = MachineCatalog.GrindingMachine and MachineCatalog.GrindingMachine.PositionTag or "GRINDING_VISUALS",
	Washable = MachineCatalog.Sink and MachineCatalog.Sink.PositionTag or "WATER_VISUALS",
}

local MachineTimeouts = {
	Battery = 35,
	Mechanical = 45,
	Engine = 50,
	Washable = 40,
}

local LiftTag = MachineCatalog.Hydraulics and MachineCatalog.Hydraulics.Tag or "HYDRAULICS"

function Machines.Zone(machine, kind)
	local hitbox = machine:FindFirstChild("Hitbox", true)
	if hitbox and hitbox:IsA("BasePart") then
		return hitbox.Position
	end
	local pivot = machine:GetPivot().Position
	local tag = MachineSpots[kind]
	if tag then
		local best, bestDistance
		for _, item in ipairs(CollectionService:GetTagged(tag)) do
			local position
			if item:IsA("Attachment") then
				position = item.WorldPosition
			elseif item:IsA("BasePart") then
				position = item.Position
			end
			if position then
				local distance = (position - pivot).Magnitude
				if distance < 10 and (not bestDistance or distance < bestDistance) then
					best, bestDistance = position, distance
				end
			end
		end
		if best then
			return best + Vector3.new(0, 0.8, 0)
		end
	end
	return pivot + Vector3.new(0, 1.5, 0)
end

function Machines.Find(kind, near, reserved)
	local tag = MachineTags[kind]
	if not tag then
		return nil
	end
	local best, bestDistance
	for _, machine in ipairs(CollectionService:GetTagged(tag)) do
		if machine:IsA("Model") and machine:IsDescendantOf(Workspace) and not reserved[machine] and machine:GetAttribute("Occupied") ~= true then
			local position = Machines.Zone(machine, kind)
			if position.Y > -40 then
				local distance = (position - near).Magnitude
				if distance < 160 and (not bestDistance or distance < bestDistance) then
					best, bestDistance = machine, distance
				end
			end
		end
	end
	return best
end

function Machines.LiftBusy(lift, myCar)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { vehicles }
	local parts = Workspace:GetPartBoundsInBox(lift:GetPivot(), Vector3.new(9, 14, 9), params)
	for _, part in ipairs(parts) do
		if not (myCar and part:IsDescendantOf(myCar)) then
			return true
		end
	end
	return false
end

function Machines.FindLift(near, myCar)
	local best, bestDistance
	for _, lift in ipairs(CollectionService:GetTagged(LiftTag)) do
		if lift:IsA("Model") and lift:IsDescendantOf(Workspace) then
			local position = lift:GetPivot().Position
			if position.Y > 0 and (flat(position) - flat(Places.Workshop)).Magnitude < 150 then
				local blocked = lift:GetAttribute("BlockedByUserId")
				local free = lift:GetAttribute("Occupied") ~= true and (blocked == nil or blocked == LocalPlayer.UserId)
				if free and not Machines.LiftBusy(lift, myCar) then
					local distance = (position - near).Magnitude
					if not bestDistance or distance < bestDistance then
						best, bestDistance = lift, distance
					end
				end
			end
		end
	end
	return best
end

function Machines.LiftLayout(lift)
	local pivot = lift:GetPivot()
	local exclude = { LocalPlayer.Character, Workspace:FindFirstChild("Vehicles"), Workspace:FindFirstChild("ExtractedCarParts") }
	local floor = raycast(pivot.Position + Vector3.new(0, 2, 0), Vector3.new(0, -20, 0), exclude)
	local floorY = floor and floor.Position.Y or (pivot.Position.Y - 6)
	local center = Vector3.new(pivot.Position.X, floorY, pivot.Position.Z)
	local look = unit(flat(pivot.LookVector), Vector3.new(0, 0, -1))
	local across = Vector3.new(-look.Z, 0, look.X)
	local origin = center + Vector3.new(0, 2.5, 0)
	local hitA = raycast(origin, across * 40, exclude)
	local hitB = raycast(origin, -across * 40, exclude)
	local freeA = hitA and hitA.Distance or 40
	local freeB = hitB and hitB.Distance or 40
	local entrance = freeA >= freeB and across or -across
	return center, entrance
end

local Move = {}
local Travel = { Last = nil }

local function ownsPart(part)
	if type(isnetworkowner) ~= "function" or not part then
		return true
	end
	local ok, result = pcall(isnetworkowner, part)
	return not ok or result == true
end


function Move.Stream(position)
	pcall(function()
		LocalPlayer:RequestStreamAroundAsync(position, 2)
	end)
end

function Move.Path(from, to, radius, walking)
	local path = PathfindingService:CreatePath({
		AgentRadius = radius,
		AgentHeight = walking and 5 or 6,
		AgentCanJump = walking == true,
		AgentCanClimb = false,
		WaypointSpacing = walking and 4 or 10,
	})
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		if #waypoints >= 2 then
			return waypoints
		end
	end
	return nil
end

function Move.Distance(goal)
	local root = getRoot()
	if not root then
		return math.huge
	end
	return (flat(root.Position) - flat(goal)).Magnitude
end

local Pace = {
	HopRange = 80,
	Limit = 200,
	Recover = 16,
	Debt = 0,
	Stamp = os.clock(),
	Penalty = 0,
	Resets = 0,
	Sprinting = false,
}

function Pace.Settle()
	local now = os.clock()
	Pace.Debt = math.max(0, Pace.Debt - (now - Pace.Stamp) * Pace.Recover)
	Pace.Stamp = now
	return Pace.Debt
end

function Pace.Allows(distance)
	return os.clock() > Pace.Penalty and Pace.Settle() + distance <= Pace.Limit
end

function Move.Sprint(on)
	on = on == true
	if Pace.Sprinting == on then
		return
	end
	Pace.Sprinting = on
	Hub.Fire(Net.StaminaSprintToggled, on)
end

function Move.Unseat()
	local humanoid = getHumanoid()
	if not (humanoid and humanoid.SeatPart) then
		return true
	end
	local seat = humanoid.SeatPart
	local vehicle = seat:FindFirstAncestorOfClass("Model")
	while vehicle and vehicle.Parent and vehicle.Parent ~= Workspace:FindFirstChild("Vehicles") do
		vehicle = vehicle.Parent:FindFirstAncestorOfClass("Model")
	end
	if vehicle then
		Move.ExitCar(vehicle)
	else
		humanoid.Sit = false
		sleep(0.6)
	end
	return humanoid.SeatPart == nil
end

function Move.Fly(goal, tolerance, speed)
	local character = LocalPlayer.Character
	local root, humanoid = getRoot(), getHumanoid()
	if not (character and root and humanoid) then
		return false
	end
	if not Move.Unseat() then
		return false
	end
	tolerance = tolerance or 2
	local stopDistance = tolerance > 3 and (tolerance - 1.5) or 0.3
	if Move.Distance(goal) <= stopDistance then
		return true
	end
	speed = speed or State.GlideSpeed
	if Carry.Target then
		speed = math.min(speed, 90)
	end
	local saved, touch = {}, {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			saved[part] = part.CanCollide
			touch[part] = part.CanTouch
			part.CanCollide = false
			part.CanTouch = false
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, Workspace:FindFirstChild("Vehicles"), Workspace:FindFirstChild("ExtractedCarParts") }
	params.RespectCanCollide = true
	local floor = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	local hip = floor and (root.Position.Y - floor.Position.Y) or 3
	if hip < 2 or hip > 5 then
		hip = 3
	end
	local origin = root.Position
	local commanded = origin
	local lastY = commanded.Y
	local finished, reset = false, false
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not Hub.Running or Job.Cancel or not root.Parent or humanoid.SeatPart then
			finished = true
			connection:Disconnect()
			return
		end
		dt = math.max(dt, 1 / 240)
		if (flat(root.Position) - flat(commanded)).Magnitude > speed * dt * 1.5 + 6 then
			Pace.Last = string.format("%s %s | flew %.0f/%.0f | jumped %.0f | anchored %s", os.date("%H:%M:%S"), Status.Text .. (Status.Detail ~= "" and (" - " .. Status.Detail) or ""), (flat(commanded) - flat(origin)).Magnitude, (flat(goal) - flat(origin)).Magnitude, (flat(root.Position) - flat(commanded)).Magnitude, tostring(root.Anchored))
			reset = true
			finished = true
			connection:Disconnect()
			return
		end
		local delta = flat(goal - commanded)
		local distance = delta.Magnitude
		if distance <= stopDistance then
			root.CFrame = CFrame.new(commanded) * root.CFrame.Rotation
			root.AssemblyLinearVelocity = Vector3.zero
			finished = true
			connection:Disconnect()
			return
		end
		local direction = delta.Unit
		local nextPosition = commanded + direction * math.min(speed * dt, distance)
		local hit = Workspace:Raycast(Vector3.new(nextPosition.X, lastY + 4, nextPosition.Z), Vector3.new(0, -14, 0), params)
		if hit then
			local candidate = hit.Position.Y + hip
			if math.abs(candidate - lastY) < 3 then
				lastY = candidate
			end
		end
		commanded = Vector3.new(nextPosition.X, lastY, nextPosition.Z)
		root.CFrame = CFrame.lookAt(commanded, commanded + direction)
		root.AssemblyLinearVelocity = direction * speed
	end)
	table.insert(Hub.Connections, connection)
	local deadline = os.clock() + 4 + Move.Distance(goal) / math.max(speed, 1) * 2
	while not finished and os.clock() < deadline do
		task.wait(0.03)
	end
	if connection.Connected then
		connection:Disconnect()
	end
	for part, value in pairs(saved) do
		if part.Parent then
			part.CanCollide = value
		end
	end
	root.AssemblyLinearVelocity = Vector3.zero
	task.delay(0.5, function()
		for part, value in pairs(touch) do
			if part.Parent then
				part.CanTouch = value
			end
		end
	end)
	Pace.Settle()
	Pace.Debt = Pace.Debt + (flat(commanded) - flat(origin)).Magnitude
	if reset then
		Pace.Resets = Pace.Resets + 1
		Pace.Penalty = os.clock() + 120
		Pace.Debt = Pace.Limit
		sleep(0.5)
		return false
	end
	if Carry.Target then
		sleep(0.1)
	elseif (flat(commanded) - flat(origin)).Magnitude < 25 then
		sleep(0.2)
	else
		sleep(0.4)
	end
	return Move.Distance(goal) <= math.max(tolerance, stopDistance + 0.5)
end

function Move.Run(goal, tolerance, timeout)
	tolerance = tolerance or 3
	local deadline = os.clock() + (timeout or 45)
	if not Move.Unseat() then
		return false
	end
	local humanoid
	Move.Sprint(true)
	local ok, result = pcall(function()
		local failures = 0
		while os.clock() < deadline do
			checkpoint()
			local root
			humanoid, root = getHumanoid(), getRoot()
			if not (humanoid and root) then
				sleep(0.5)
			elseif humanoid.SeatPart then
				return false
			else
				if Move.Distance(goal) <= tolerance then
					return true
				end
				local waypoints = Move.Path(root.Position, goal, 2, true) or {
					{ Position = root.Position, Action = Enum.PathWaypointAction.Walk },
					{ Position = goal, Action = Enum.PathWaypointAction.Walk },
				}
				local moved = 0
				local stuck = false
				for index = 2, #waypoints do
					local waypoint = waypoints[index]
					if waypoint.Action == Enum.PathWaypointAction.Jump then
						humanoid.Jump = true
					end
					humanoid:MoveTo(waypoint.Position)
					local last, lastMove = root.Position, os.clock()
					while (flat(root.Position) - flat(waypoint.Position)).Magnitude > 2 do
						checkpoint()
						if Move.Distance(goal) <= tolerance then
							return true
						end
						if os.clock() > deadline or humanoid.SeatPart then
							return Move.Distance(goal) <= tolerance
						end
						local step = (root.Position - last).Magnitude
						if step > 1 then
							moved = moved + step
							last, lastMove = root.Position, os.clock()
						elseif os.clock() - lastMove > 0.7 then
							humanoid.Jump = true
							if os.clock() - lastMove > 2 then
								stuck = true
								break
							end
						end
						task.wait(0.05)
					end
					if stuck then
						break
					end
				end
				if Move.Distance(goal) <= tolerance then
					return true
				end
				if moved < 4 then
					failures = failures + 1
					if failures >= 4 then
						return false
					end
					local direction = unit(flat(goal - root.Position))
					if Pace.Allows(8) then
						Move.Fly(root.Position + direction * math.min(8, Move.Distance(goal)), 1.5, 40)
					else
						humanoid.Jump = true
						humanoid:MoveTo(root.Position - direction * 4 + Vector3.new(direction.Z, 0, -direction.X) * 4)
						task.wait(0.6)
					end
				end
			end
		end
		return Move.Distance(goal) <= tolerance
	end)
	Move.Sprint(false)
	local stopHumanoid, stopRoot = getHumanoid(), getRoot()
	if stopHumanoid and stopRoot then
		stopHumanoid:MoveTo(stopRoot.Position)
	end
	if not ok then
		error(result, 0)
	end
	return result == true
end

function Move.WalkTo(goal, tolerance, timeout)
	tolerance = tolerance or 3
	local distance = Move.Distance(goal)
	if State.PlayerTeleport and distance <= Pace.HopRange and Pace.Allows(distance) then
		if Move.Fly(goal, tolerance) then
			return true
		end
		if os.clock() > Pace.Penalty then
			return Move.Distance(goal) <= tolerance
		end
	end
	return Move.Run(goal, tolerance, timeout)
end

function Move.Hop(target)
	local root = getRoot()
	if not root then
		return
	end
	local delta = target - root.Position
	if delta.Magnitude > 14 then
		target = root.Position + delta.Unit * 14
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(target) * root.CFrame.Rotation
end

function Move.StopCar(car)
	local primary = car and car.PrimaryPart
	if primary then
		primary.AssemblyLinearVelocity = Vector3.new(0, math.min(primary.AssemblyLinearVelocity.Y, 0), 0)
		primary.AssemblyAngularVelocity = Vector3.zero
	end
end

function Move.Reverse(car, seconds)
	local primary = car.PrimaryPart
	local deadline = os.clock() + seconds
	while os.clock() < deadline and primary.Parent do
		checkpoint()
		local back = -Car.Forward(car)
		primary.AssemblyLinearVelocity = Vector3.new(back.X * 14, math.min(primary.AssemblyLinearVelocity.Y, 4), back.Z * 14)
		task.wait()
	end
	Move.StopCar(car)
end

local Roads = { Graph = nil, Edges = nil }

function Roads.Sample(a, b, link)
	local points = { a }
	if link.UseSpline == true and typeof(link.CP1) == "Vector3" and typeof(link.CP2) == "Vector3" then
		local p1, p2 = a + link.CP1, b + link.CP2
		local steps = math.max(4, math.ceil((tonumber(link.Length) or (b - a).Magnitude) / 6))
		for i = 1, steps - 1 do
			local t = i / steps
			local u = 1 - t
			table.insert(points, a * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + b * (t * t * t))
		end
	else
		local steps = math.max(1, math.floor((b - a).Magnitude / 10))
		for i = 1, steps - 1 do
			table.insert(points, a:Lerp(b, i / steps))
		end
	end
	table.insert(points, b)
	return points
end

function Roads.Load()
	if Roads.Graph then
		return Roads.Graph
	end
	if type(RoadData) ~= "table" then
		return nil
	end
	local graph, edges = {}, {}
	for id, info in pairs(RoadData) do
		if type(info) == "table" and typeof(info.Position) == "Vector3" then
			graph[id] = { Id = id, Position = info.Position, Links = {} }
		end
	end
	for id, info in pairs(RoadData) do
		local from = graph[id]
		if from and type(info.Connections) == "table" then
			for other, link in pairs(info.Connections) do
				local to = graph[other]
				if to and type(link) == "table" then
					local points = Roads.Sample(from.Position, to.Position, link)
					local length = 0
					for i = 2, #points do
						length = length + (points[i] - points[i - 1]).Magnitude
					end
					local edge = { From = id, To = other, Points = points, Length = length, Both = link.Direction ~= "forward" }
					table.insert(edges, edge)
					table.insert(from.Links, { To = other, Edge = edge, Reverse = false })
					if edge.Both then
						table.insert(to.Links, { To = id, Edge = edge, Reverse = true })
					end
				end
			end
		end
	end
	Roads.Graph, Roads.Edges = graph, edges
	return graph
end

local function segmentClosest(position, a, b)
	local ab = flat(b - a)
	local denominator = ab:Dot(ab)
	local t = 0
	if denominator > 0 then
		t = math.clamp(flat(position - a):Dot(ab) / denominator, 0, 1)
	end
	return a + (b - a) * t, t
end

function Roads.Project(position)
	local best
	for _, edge in ipairs(Roads.Edges or {}) do
		local points = edge.Points
		for i = 1, #points - 1 do
			local point, t = segmentClosest(position, points[i], points[i + 1])
			local score = (flat(point) - flat(position)).Magnitude + math.abs(point.Y - position.Y) * 3
			if not best or score < best.Score then
				best = { Edge = edge, Index = i, T = t, Point = point, Score = score }
			end
		end
	end
	return best
end

local function forwardPart(spot)
	local points = spot.Edge.Points
	local list = { spot.Point }
	local length = (points[spot.Index + 1] - spot.Point).Magnitude
	for i = spot.Index + 1, #points do
		table.insert(list, points[i])
		if i > spot.Index + 1 then
			length = length + (points[i] - points[i - 1]).Magnitude
		end
	end
	return list, length
end

local function backwardPart(spot)
	local points = spot.Edge.Points
	local list = { spot.Point }
	local length = (spot.Point - points[spot.Index]).Magnitude
	for i = spot.Index, 1, -1 do
		table.insert(list, points[i])
		if i < spot.Index then
			length = length + (points[i] - points[i + 1]).Magnitude
		end
	end
	return list, length
end

local function reversed(list)
	local result = {}
	for i = #list, 1, -1 do
		table.insert(result, list[i])
	end
	return result
end

local function appendPoints(target, source, skipFirst)
	for i = skipFirst and 2 or 1, #source do
		local point = source[i]
		local last = target[#target]
		if not last or (point - last).Magnitude > 0.5 then
			table.insert(target, point)
		end
	end
end

function Roads.Route(from, to)
	local graph = Roads.Load()
	if not graph then
		return nil
	end
	local startSpot = Roads.Project(from)
	local goalSpot = Roads.Project(to)
	if not startSpot or not goalSpot then
		return nil
	end
	if startSpot.Edge == goalSpot.Edge then
		local a = startSpot.Index + startSpot.T
		local b = goalSpot.Index + goalSpot.T
		if b >= a or startSpot.Edge.Both then
			local points = startSpot.Edge.Points
			local list = { startSpot.Point }
			if b >= a then
				for i = startSpot.Index + 1, goalSpot.Index do
					table.insert(list, points[i])
				end
			else
				for i = startSpot.Index, goalSpot.Index + 1, -1 do
					table.insert(list, points[i])
				end
			end
			table.insert(list, goalSpot.Point)
			return list, startSpot, goalSpot
		end
	end
	local distance, previous, entry, done = {}, {}, {}, {}
	local starts = {}
	local forwardList, forwardLength = forwardPart(startSpot)
	starts[startSpot.Edge.To] = { Points = forwardList, Length = forwardLength }
	if startSpot.Edge.Both then
		local backList, backLength = backwardPart(startSpot)
		local current = starts[startSpot.Edge.From]
		if not current or backLength < current.Length then
			starts[startSpot.Edge.From] = { Points = backList, Length = backLength }
		end
	end
	for id, start in pairs(starts) do
		distance[id] = start.Length
		previous[id] = false
	end
	while true do
		local node, best = nil, math.huge
		for id, value in pairs(distance) do
			if not done[id] and value < best then
				node, best = id, value
			end
		end
		if not node then
			break
		end
		done[node] = true
		for _, link in ipairs(graph[node].Links) do
			local cost = best + link.Edge.Length
			if not done[link.To] and (distance[link.To] == nil or cost < distance[link.To]) then
				distance[link.To] = cost
				previous[link.To] = node
				entry[link.To] = link
			end
		end
	end
	local goalPoints = goalSpot.Edge.Points
	local finish, finishTail, finishCost
	if distance[goalSpot.Edge.From] then
		local tail = {}
		for i = 1, goalSpot.Index do
			table.insert(tail, goalPoints[i])
		end
		table.insert(tail, goalSpot.Point)
		local length = 0
		for i = 2, #tail do
			length = length + (tail[i] - tail[i - 1]).Magnitude
		end
		finish, finishTail, finishCost = goalSpot.Edge.From, tail, distance[goalSpot.Edge.From] + length
	end
	if goalSpot.Edge.Both and distance[goalSpot.Edge.To] then
		local tail = {}
		for i = #goalPoints, goalSpot.Index + 1, -1 do
			table.insert(tail, goalPoints[i])
		end
		table.insert(tail, goalSpot.Point)
		local length = 0
		for i = 2, #tail do
			length = length + (tail[i] - tail[i - 1]).Magnitude
		end
		local cost = distance[goalSpot.Edge.To] + length
		if not finishCost or cost < finishCost then
			finish, finishTail, finishCost = goalSpot.Edge.To, tail, cost
		end
	end
	if not finish then
		return nil
	end
	local chain = {}
	local node = finish
	while node do
		table.insert(chain, 1, node)
		local before = previous[node]
		if before == false or before == nil then
			break
		end
		node = before
	end
	local list = {}
	appendPoints(list, starts[chain[1]].Points, false)
	for i = 2, #chain do
		local link = entry[chain[i]]
		local points = link.Reverse and reversed(link.Edge.Points) or link.Edge.Points
		appendPoints(list, points, true)
	end
	appendPoints(list, finishTail, true)
	return list, startSpot, goalSpot
end

function Move.Densify(points, spacing)
	local result = {}
	for i = 1, #points do
		local point = points[i]
		if i > 1 then
			local previousPoint = points[i - 1]
			local gap = (point - previousPoint).Magnitude
			local steps = math.floor(gap / spacing)
			for step = 1, steps - 1 do
				table.insert(result, previousPoint:Lerp(point, step / steps))
			end
		end
		table.insert(result, point)
	end
	return result
end

function Move.StartPoint(car, goal)
	local center = car:GetPivot().Position
	local forward = Car.Forward(car)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local halfLength, halfWidth = Car.Size(car)
	local toGoal = unit(flat(goal - center), forward)
	local sides = {
		forward * (halfLength + 4),
		(right:Dot(toGoal) >= 0 and right or -right) * (halfWidth + 4),
		(right:Dot(toGoal) >= 0 and -right or right) * (halfWidth + 4),
		-forward * (halfLength + 4),
	}
	local exclude = { car, LocalPlayer.Character }
	local origin = center + Vector3.new(0, 1.5, 0)
	for _, offset in ipairs(sides) do
		if not raycast(origin, offset, exclude) then
			local ground = raycast(origin + offset + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), exclude)
			if ground then
				return Vector3.new(ground.Position.X, center.Y, ground.Position.Z)
			end
		end
	end
	return center + forward * (halfLength + 4)
end

function Move.CarPathPoints(car, from, to)
	local _, halfWidth = Car.Size(car)
	for _, radius in ipairs({ math.clamp(halfWidth + 1.5, 3, 6.5), math.clamp(halfWidth + 0.5, 2.5, 5), 2.5 }) do
		local waypoints = Move.Path(from, to, radius, false)
		if waypoints then
			local list = {}
			for _, waypoint in ipairs(waypoints) do
				table.insert(list, waypoint.Position)
			end
			return list
		end
	end
	return nil
end

function Move.Occupied(position, car)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { vehicles }
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(position + Vector3.new(0, 2, 0), 5, params)) do
		if not part:IsDescendantOf(car) then
			return true
		end
	end
	return false
end

function Move.ClearBlocked(car, points)
	local count = #points
	local cache = {}
	local function occupied(index)
		local value = cache[index]
		if value == nil then
			value = Move.Occupied(points[index], car)
			cache[index] = value
		end
		return value
	end
	local result = {}
	local i = 1
	local detours = 0
	while i <= count do
		if i > 2 and i < count - 1 and occupied(i) and detours < 6 then
			local j = i
			while j < count and occupied(j) do
				j = j + 1
			end
			local after = math.min(count, j + 2)
			for _ = 1, 2 do
				if #result > 2 then
					table.remove(result)
				end
			end
			local before = result[#result] or points[1]
			local detour = Move.CarPathPoints(car, before, points[after])
			detours = detours + 1
			if detour and #detour >= 2 then
				appendPoints(result, detour, true)
			else
				for k = i, after do
					table.insert(result, points[k])
				end
			end
			i = after + 1
		else
			table.insert(result, points[i])
			i = i + 1
		end
	end
	return result
end

function Move.Plan(car, goal)
	local position = car:GetPivot().Position
	local start = Move.StartPoint(car, goal)
	local points
	if (flat(goal) - flat(position)).Magnitude > 140 and Roads.Load() then
		local road = Roads.Route(start, goal)
		if road and #road >= 2 then
			points = { position }
			if (flat(road[1]) - flat(start)).Magnitude > 12 then
				appendPoints(points, Move.CarPathPoints(car, start, road[1]) or { start, road[1] }, false)
			else
				appendPoints(points, { start }, false)
			end
			appendPoints(points, road, false)
			if (flat(goal) - flat(road[#road])).Magnitude > 8 then
				appendPoints(points, Move.CarPathPoints(car, road[#road], goal) or { road[#road], goal }, true)
			else
				appendPoints(points, { goal }, false)
			end
		end
	end
	if not points then
		points = { position }
		appendPoints(points, Move.CarPathPoints(car, start, goal) or { start, goal }, false)
	end
	return Move.Densify(Move.ClearBlocked(car, Move.Densify(points, 5)), 5)
end

function Move.Obstacle(car, forward, speed)
	local pivot = car:GetPivot()
	local halfLength, halfWidth = Car.Size(car)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local reach = math.clamp(speed * 0.45, 5, 26)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car, LocalPlayer.Character }
	params.RespectCanCollide = true
	local nearest
	for _, side in ipairs({ -0.85, 0, 0.85 }) do
		local origin = pivot.Position + forward * (halfLength - 1) + right * (halfWidth * side) + Vector3.new(0, 1.2, 0)
		local hit = Workspace:Raycast(origin, forward * reach, params)
		if hit and hit.Normal.Y < 0.6 then
			nearest = math.min(nearest or math.huge, hit.Distance)
		end
	end
	return nearest
end

function Move.Track(car, points, options)
	options = options or {}
	local primary = car.PrimaryPart
	local maxSpeed = options.Speed or State.DriveSpeed
	local arrive = options.Arrive or 5
	local offset = options.Offset or 0
	local offsetUntil = options.OffsetUntil or 0
	local goal = points[#points]
	local cumulative = { 0 }
	for i = 2, #points do
		cumulative[i] = cumulative[i - 1] + (flat(points[i]) - flat(points[i - 1])).Magnitude
	end
	local position0 = car:GetPivot().Position
	local index, nearest = 1, math.huge
	for i = 1, #points do
		local gap = (flat(points[i]) - flat(position0)).Magnitude
		if gap < nearest then
			index, nearest = i, gap
		end
	end
	local speed = math.max(0, flat(primary.AssemblyLinearVelocity):Dot(Car.Forward(car)))
	local lastProgress, bestGap = os.clock(), math.huge
	local ownerCheck, unownedSince = 0, nil
	local blockedSince = nil
	local finished, result = false, nil
	local connection
	local function finish(value)
		if not finished then
			finished, result = true, value
			connection:Disconnect()
		end
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		if not Hub.Running or Job.Cancel or not car.Parent or not primary.Parent then
			finish("gone")
			return
		end
		local humanoid = getHumanoid()
		if not (humanoid and humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(car)) then
			finish("unseated")
			return
		end
		if os.clock() - ownerCheck > 0.5 then
			ownerCheck = os.clock()
			if ownsPart(primary) then
				unownedSince = nil
			else
				unownedSince = unownedSince or os.clock()
				if os.clock() - unownedSince > 1 then
					finish("unowned")
					return
				end
			end
		end
		dt = math.max(dt, 1 / 240)
		local pivot = car:GetPivot()
		local position = pivot.Position
		local closest, closestGap = index, (flat(points[index]) - flat(position)).Magnitude
		for i = index + 1, math.min(#points, index + 20) do
			local gap = (flat(points[i]) - flat(position)).Magnitude
			if gap < closestGap then
				closest, closestGap = i, gap
			end
		end
		if closest > index then
			index = closest
			lastProgress = os.clock()
			bestGap = math.huge
		end
		local toGoal = (flat(goal) - flat(position)).Magnitude
		if toGoal <= arrive and index >= #points - 4 then
			finish("arrived")
			return
		end
		local look = math.clamp(speed * 0.35, 6, 18)
		local targetIndex = index
		while targetIndex < #points and cumulative[targetIndex] - cumulative[index] < look do
			targetIndex = targetIndex + 1
		end
		local target = points[targetIndex]
		local forward = Car.Forward(car)
		if offset ~= 0 and cumulative[targetIndex] < offsetUntil then
			local segment = unit(flat(points[math.min(targetIndex + 1, #points)] - points[math.max(targetIndex - 1, 1)]), forward)
			target = target + Vector3.new(-segment.Z, 0, segment.X) * offset
		end
		local desired = unit(flat(target - position), forward)
		local angle = math.atan2(forward:Cross(desired).Y, forward:Dot(desired))
		local sharp = math.abs(angle)
		local scan = cumulative[index] + 12 + speed * 0.8
		local i = index
		while i < #points - 1 and cumulative[i] < scan do
			local direction = flat(points[i + 1] - points[i])
			if direction.Magnitude > 0.1 then
				local turnAhead = math.acos(math.clamp(direction.Unit:Dot(desired), -1, 1))
				if turnAhead > sharp then
					sharp = turnAhead
				end
			end
			i = i + 1
		end
		local limit = maxSpeed
		if sharp > math.rad(20) then
			limit = math.min(limit, maxSpeed * math.clamp(1 - (sharp - math.rad(20)) / math.rad(80), 0.2, 1))
		end
		limit = math.min(limit, math.max(7, toGoal * 1.4))
		if math.abs(angle) > math.rad(55) then
			limit = math.min(limit, 5)
		end
		local blocked = Move.Obstacle(car, forward, speed)
		if blocked and blocked > toGoal - 1 then
			blocked = nil
		end
		if blocked then
			limit = math.min(limit, math.max(0, blocked - 3) * 1.8)
			if blocked < 6 and speed < 2 then
				blockedSince = blockedSince or os.clock()
				if os.clock() - blockedSince > 1 then
					finish("blocked")
					return
				end
			else
				blockedSince = nil
			end
		else
			blockedSince = nil
		end
		if speed < limit then
			speed = math.min(limit, speed + 40 * dt)
		else
			speed = math.max(limit, speed - 90 * dt)
		end
		local maxTurn = math.rad(speed < 12 and 150 or 100) * dt
		local turn = math.clamp(angle, -maxTurn, maxTurn)
		local rotation = CFrame.Angles(0, turn, 0)
		car:PivotTo(CFrame.new(position) * rotation * pivot.Rotation)
		local heading = rotation:VectorToWorldSpace(forward)
		local velocity = primary.AssemblyLinearVelocity
		primary.AssemblyLinearVelocity = Vector3.new(heading.X * speed, math.min(velocity.Y, 4), heading.Z * speed)
		primary.AssemblyAngularVelocity = Vector3.zero
		local nextGap = (flat(points[math.min(index + 1, #points)]) - flat(position)).Magnitude
		if nextGap < bestGap - 0.75 then
			bestGap = nextGap
			lastProgress = os.clock()
		elseif os.clock() - lastProgress > 2.2 then
			finish("stuck")
		end
	end)
	table.insert(Hub.Connections, connection)
	while not finished do
		task.wait(0.05)
	end
	return result, index
end

function Move.Detour(car, points, index)
	local cumulative = { [index] = 0 }
	for i = index + 1, #points do
		cumulative[i] = cumulative[i - 1] + (flat(points[i]) - flat(points[i - 1])).Magnitude
	end
	for candidate = index + 1, #points do
		local ahead = cumulative[candidate]
		if ahead > 90 then
			break
		end
		if ahead >= 25 and (candidate == #points or ahead % 10 < 5) and not Move.Occupied(points[candidate], car) then
			local from = Move.StartPoint(car, points[candidate])
			local path = Move.CarPathPoints(car, from, points[candidate])
			if path and #path >= 2 then
				local list = { car:GetPivot().Position }
				appendPoints(list, path, false)
				for i = candidate + 1, #points do
					table.insert(list, points[i])
				end
				return Move.Densify(list, 5)
			end
		end
	end
	return nil
end

function Move.Glide(car, goal, finalForward, speed)
	speed = speed or State.GlideSpeed
	local primary = car.PrimaryPart
	if not primary then
		return false, "no car"
	end
	if not Move.EnterCar(car) then
		return false, "unseated"
	end
	Move.Stream(goal)
	local bounds, size = car:GetBoundingBox()
	local bottomOffset = car:GetPivot().Position.Y - (bounds.Position.Y - size.Y / 2)
	local saved = {}
	for _, root in ipairs({ car, LocalPlayer.Character }) do
		if root then
			for _, item in ipairs(root:GetDescendants()) do
				if item:IsA("BasePart") then
					saved[item] = item.CanCollide
					item.CanCollide = false
				end
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car, LocalPlayer.Character, Workspace:FindFirstChild("Vehicles"), Workspace:FindFirstChild("ExtractedCarParts") }
	params.RespectCanCollide = true
	local finalDirection = finalForward and unit(flat(finalForward)) or nil
	local lastY = car:GetPivot().Position.Y
	local finished, result = false, nil
	local ownerCheck, unownedSince = 0, nil
	local connection
	local function finish(value)
		if not finished then
			finished, result = true, value
			connection:Disconnect()
			primary.AssemblyLinearVelocity = Vector3.zero
			primary.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local function groundAtPoint(point)
		local hit = Workspace:Raycast(Vector3.new(point.X, lastY + 6, point.Z), Vector3.new(0, -24, 0), params)
		if hit then
			local candidate = hit.Position.Y + bottomOffset + 0.3
			if math.abs(candidate - lastY) < 4 then
				return candidate
			end
		end
		return lastY
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		if not Hub.Running or Job.Cancel or not car.Parent or not primary.Parent then
			finish("gone")
			return
		end
		local humanoid = getHumanoid()
		if not (humanoid and humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(car)) then
			finish("unseated")
			return
		end
		if os.clock() - ownerCheck > 0.5 then
			ownerCheck = os.clock()
			if ownsPart(primary) then
				unownedSince = nil
			else
				unownedSince = unownedSince or os.clock()
				if os.clock() - unownedSince > 1 then
					finish("unowned")
					return
				end
			end
		end
		dt = math.max(dt, 1 / 240)
		local pivot = car:GetPivot()
		local position = pivot.Position
		local delta = flat(goal - position)
		local forward = Car.Forward(car)
		if delta.Magnitude <= speed * dt + 0.5 then
			local y = groundAtPoint(goal)
			local facing = finalDirection or forward
			local angle = math.atan2(forward:Cross(facing).Y, forward:Dot(facing))
			car:PivotTo(CFrame.new(goal.X, y, goal.Z) * CFrame.Angles(0, angle, 0) * pivot.Rotation)
			finish("arrived")
			return
		end
		local direction = delta.Unit
		local nextPosition = position + direction * (speed * dt)
		local y = groundAtPoint(nextPosition)
		lastY = y
		local facing = direction
		if finalDirection and delta.Magnitude < 25 then
			facing = finalDirection
		end
		local angle = math.atan2(forward:Cross(facing).Y, forward:Dot(facing))
		local turn = math.clamp(angle, -math.rad(540) * dt, math.rad(540) * dt)
		car:PivotTo(CFrame.new(nextPosition.X, y, nextPosition.Z) * CFrame.Angles(0, turn, 0) * pivot.Rotation)
		primary.AssemblyLinearVelocity = direction * speed
		primary.AssemblyAngularVelocity = Vector3.zero
	end)
	table.insert(Hub.Connections, connection)
	while not finished do
		task.wait(0.05)
	end
	task.wait(0.1)
	for item, value in pairs(saved) do
		if item.Parent then
			item.CanCollide = value
		end
	end
	primary.AssemblyLinearVelocity = Vector3.zero
	primary.AssemblyAngularVelocity = Vector3.zero
	checkpoint()
	return result == "arrived", result
end

function Move.Drive(car, goal, speed, arrive, finalForward)
	if State.TravelMode == "Teleport" then
		local ok, reason = Move.Glide(car, goal, finalForward)
		if ok or reason == "gone" then
			return ok, reason
		end
		local again, why = Move.Glide(car, goal, finalForward)
		return again, why
	end
	speed = speed or State.DriveSpeed
	arrive = arrive or 6
	if not car.PrimaryPart then
		return false, "no car"
	end
	Move.Stream(goal)
	local points = Move.Plan(car, goal)
	local stuck = 0
	local offset = 0
	local offsetUntil = 0
	for _ = 1, 12 do
		checkpoint()
		if (flat(car:GetPivot().Position) - flat(goal)).Magnitude <= arrive then
			Move.StopCar(car)
			return true
		end
		local result, index = Move.Track(car, points, { Speed = speed, Arrive = arrive, Offset = offset, OffsetUntil = offsetUntil })
		checkpoint()
		if result == "arrived" then
			Move.StopCar(car)
			return true
		elseif result == "gone" then
			Move.StopCar(car)
			return false, result
		elseif result == "unseated" or result == "unowned" then
			Move.StopCar(car)
			if not Move.EnterCar(car) then
				return false, result
			end
		else
			stuck = stuck + 1
			Move.StopCar(car)
			Move.Reverse(car, 0.6)
			local detour = stuck <= 4 and Move.Detour(car, points, index or 1)
			if detour then
				points = detour
				offset = 0
			elseif stuck >= 3 and stuck % 3 == 0 then
				points = Move.Plan(car, goal)
				offset = 0
			else
				offset = stuck % 2 == 1 and 5 or -5
				local cumulative = 0
				for i = 2, math.min(index or 1, #points) do
					cumulative = cumulative + (flat(points[i]) - flat(points[i - 1])).Magnitude
				end
				offsetUntil = cumulative + 35
			end
			if stuck >= 7 then
				break
			end
		end
	end
	Move.StopCar(car)
	return false, "stuck"
end

function Move.Park(car, target, forward, speed, tolerance, timeout)
	forward = unit(flat(forward))
	local primary = car.PrimaryPart
	local finished = false
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not Hub.Running or Job.Cancel or not car.Parent or not primary.Parent then
			connection:Disconnect()
			finished = true
			return
		end
		local pivot = car:GetPivot()
		local position = pivot.Position
		local delta = flat(target - position)
		local current = Car.Forward(car)
		local angle = math.atan2(current:Cross(forward).Y, current:Dot(forward))
		if (delta.Magnitude < (tolerance or 0.5) and math.abs(angle) < math.rad(tolerance and 6 or 1.5)) or os.clock() - started > (timeout or 12) then
			Move.StopCar(car)
			connection:Disconnect()
			finished = true
			return
		end
		local maxTurn = math.rad(150) * math.max(dt, 1 / 60)
		local turn = math.clamp(angle, -maxTurn, maxTurn)
		car:PivotTo(CFrame.new(position) * CFrame.Angles(0, turn, 0) * pivot.Rotation)
		local pace = math.abs(angle) > math.rad(10) and 0 or math.min(speed or 12, delta.Magnitude * 3)
		local velocity = delta.Magnitude > 0.05 and delta.Unit * pace or Vector3.zero
		primary.AssemblyLinearVelocity = Vector3.new(velocity.X, math.min(primary.AssemblyLinearVelocity.Y, 3), velocity.Z)
		primary.AssemblyAngularVelocity = Vector3.zero
	end)
	table.insert(Hub.Connections, connection)
	while not finished do
		task.wait(0.05)
	end
	checkpoint()
	return (flat(car:GetPivot().Position) - flat(target)).Magnitude
end

function Move.FreeSpot(car, prefer)
	local center = car:GetPivot().Position
	local forward = Car.Forward(car)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local halfLength, halfWidth = Car.Size(car)
	local options = {}
	if prefer then
		table.insert(options, unit(flat(prefer)) * (halfLength + 4))
	end
	table.insert(options, -forward * (halfLength + 4))
	table.insert(options, forward * (halfLength + 4))
	table.insert(options, right * (halfWidth + 4))
	table.insert(options, -right * (halfWidth + 4))
	local exclude = { car, LocalPlayer.Character }
	local origin = center + Vector3.new(0, 2.5, 0)
	for _, offset in ipairs(options) do
		if not raycast(origin, offset, exclude) then
			local ground = raycast(origin + offset, Vector3.new(0, -14, 0), exclude)
			if ground then
				return ground.Position
			end
		end
	end
	return nil
end

function Move.ExitCar(car, prefer)
	local humanoid, root = getHumanoid(), getRoot()
	if not (humanoid and root) then
		return false
	end
	if not humanoid.SeatPart then
		return true
	end
	for _ = 1, 4 do
		checkpoint()
		humanoid.Sit = false
		waitFor(function()
			return humanoid.SeatPart == nil
		end, 1.5)
		local spot = car and car.Parent and Move.FreeSpot(car, prefer)
		if spot then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.new(spot + Vector3.new(0, 3, 0))
		end
		sleep(0.6)
		if humanoid.SeatPart == nil then
			return true
		end
	end
	return humanoid.SeatPart == nil
end

function Move.EnterCar(car)
	local humanoid, root = getHumanoid(), getRoot()
	local seat = Car.Seat(car)
	if not (humanoid and root and seat) then
		return false
	end
	if humanoid.SeatPart == seat and ownsPart(car.PrimaryPart) then
		return true
	end
	for _ = 1, 5 do
		checkpoint()
		if humanoid.SeatPart == seat and not waitFor(function()
			return ownsPart(car.PrimaryPart)
		end, 1.5) then
			humanoid.Sit = false
			sleep(0.8)
		elseif humanoid.SeatPart == seat then
			return true
		end
		if humanoid.SeatPart and humanoid.SeatPart ~= seat then
			humanoid.Sit = false
			sleep(0.4)
		end
		if (root.Position - seat.Position).Magnitude > 12 then
			Move.WalkTo(seat.Position, 8, 15)
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = seat.CFrame * CFrame.new(0, 1, 0)
		local seated = waitFor(function()
			return humanoid.SeatPart == seat
		end, 1.5)
		if not seated then
			pcall(function()
				seat:Sit(humanoid)
			end)
			seated = waitFor(function()
				return humanoid.SeatPart == seat
			end, 1)
		end
		if seated and waitFor(function()
			return ownsPart(car.PrimaryPart)
		end, 2) then
			return true
		end
	end
	return humanoid.SeatPart == seat and ownsPart(car.PrimaryPart)
end

function Move.QuickTravel(pointId)
	local humanoid = getHumanoid()
	if humanoid and humanoid.SeatPart then
		return false, "Seated"
	end
	for _ = 1, 3 do
		checkpoint()
		Travel.Last = nil
		Hub.Fire(Net.RequestTeleport, pointId)
		local result = waitFor(function()
			return Travel.Last
		end, 8)
		if result and result.Success then
			sleep(1.5)
			return true
		end
		local reason = result and tostring(result.Reason) or "Timeout"
		if reason ~= "Cooldown" and reason ~= "Busy" then
			return false, reason
		end
		sleep(4)
	end
	return false, "Cooldown"
end

local function groundAt(position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character, Workspace:FindFirstChild("Vehicles") }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), params)
	return hit and hit.Position or position
end

local Farm = { Current = nil, YardIndex = 0, Done = {}, PaintTries = {}, Hooks = {}, Pick = { Repair = {}, Sell = {} }, Favorites = {}, FavoritesFile = "JunkMechanics_favorites.json" }
local Garage = { File = "JunkMechanics_cars.json", Owned = {} }
local Wheels = {
	Slots = type(VehicleModel) == "table" and type(VehicleModel.WheelSlots) == "table" and VehicleModel.WheelSlots or { "FL", "FR", "RL", "RR" },
	MachineTag = type(MachineCatalog.WheelsMachine) == "table" and MachineCatalog.WheelsMachine.Tag or "WHEELS_MACHINE",
	Prices = { Tire = 350, Rim = 300 },
	Fields = { Tire = "Tires", Rim = "Rims" },
	Bought = {},
	Attempts = {},
	Margin = 150,
	MaxBuy = 4,
}

local Minigame = {
	Engine = setmetatable({}, { __mode = "k" }),
	WashToken = nil,
	SellConfirm = nil,
}

local UIController = loadModule(ClientFolder, { "Controllers", "Gameplay", "UIController" })

function Minigame.FrameOpen(name)
	local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local frames = gui and gui:FindFirstChild("Frames")
	local frame = frames and frames:FindFirstChild(name)
	return frame ~= nil and frame:IsA("GuiObject") and frame.Visible, frame
end

function Minigame.RestoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera or camera.CameraType ~= Enum.CameraType.Scriptable then
		return
	end
	if Minigame.FrameOpen("Cleaning") or Minigame.FrameOpen("BatteryMiniGame") then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = getHumanoid()
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

function Minigame.CloseFrame(name, buttonPath)
	local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local frames = gui and gui:FindFirstChild("Frames")
	local frame = frames and frames:FindFirstChild(name)
	if not frame then
		return
	end
	local button = frame
	for _, part in ipairs(buttonPath or {}) do
		button = button and button:FindFirstChild(part)
	end
	local pressed = false
	if button and button:IsA("GuiButton") then
		if type(getconnections) == "function" then
			local ok, list = pcall(getconnections, button.Activated)
			if ok and type(list) == "table" and #list > 0 then
				for _, connection in ipairs(list) do
					pcall(function()
						connection:Fire()
					end)
				end
				pressed = true
			end
		end
		if not pressed and type(firesignal) == "function" then
			pressed = pcall(firesignal, button.Activated)
		end
	end
	task.wait(0.4)
	if frame:IsA("GuiObject") and frame.Visible and type(UIController) == "table" and type(UIController.Close) == "function" then
		pcall(function()
			UIController:Close(name)
		end)
		task.wait(0.3)
	end
	Minigame.RestoreCamera()
end

function Minigame.Blocking()
	local camera = Workspace.CurrentCamera
	return Minigame.FrameOpen("Cleaning") or Minigame.FrameOpen("BatteryMiniGame") or (camera ~= nil and camera.CameraType == Enum.CameraType.Scriptable)
end

local function minigamesActive()
	return Hub.Running and (State.AutoMinigames or Job.Running)
end

Hub.On(Net.BatteryChargePrompted, function(machine, battery, opened, blue, red)
	if not minigamesActive() or opened ~= true or typeof(machine) ~= "Instance" then
		return
	end
	task.spawn(function()
		task.wait(0.35 + math.random() * 0.3)
		if not Hub.Running then
			return
		end
		if not blue then
			Hub.Fire(Net.BatteryClampRequested, machine, 1)
		elseif not red then
			Hub.Fire(Net.BatteryClampRequested, machine, 2)
		end
	end)
end)

Hub.On(Net.WashPrompted, function(part, opened)
	if not minigamesActive() then
		return
	end
	if opened then
		local token = {}
		Minigame.WashToken = token
		task.delay(State.WashDelay, function()
			if Minigame.WashToken == token and Hub.Running then
				Minigame.WashToken = nil
				Hub.Fire(Net.WashFinishRequested, true)
				local deadline = os.clock() + 14
				while os.clock() < deadline and Hub.Running do
					if typeof(part) ~= "Instance" or not part.Parent or part:GetAttribute("InMachine") ~= true then
						break
					end
					task.wait(0.25)
				end
				task.wait(0.5)
				Minigame.CloseFrame("Cleaning", { "Buttons", "Cancel" })
			end
		end)
	else
		Minigame.WashToken = nil
	end
end)

Hub.On(Net.EngineRepairPrompted, function(machine, engine, state)
	if not minigamesActive() or typeof(machine) ~= "Instance" then
		return
	end
	if type(HoistStates) == "table" and HoistStates.Active ~= nil and state ~= HoistStates.Active then
		return
	end
	local pending = Minigame.Engine[machine]
	if pending and pending.Engine == engine and not pending.Fired then
		return
	end
	local token = { Engine = engine, Fired = false }
	Minigame.Engine[machine] = token
	task.delay(State.WeldDelay, function()
		if Hub.Running and Minigame.Engine[machine] == token then
			token.Fired = true
			Hub.Fire(Net.EngineWeldRequested, machine, HoistActions.Complete, Vector3.zero)
		end
	end)
end)

Hub.On(Net.SellCarConfirmationRequested, function(name, amount)
	Minigame.SellConfirm = { Name = name, Amount = tonumber(amount) or 0, Time = os.clock() }
end)

Hub.On(Net.TeleportCompleted, function(success, reason)
	Travel.Last = { Success = success == true, Reason = reason, Time = os.clock() }
end)

Hub.On(Net.NotificationPushed, function(kind, text, category, key)
	Status.Message = tostring(text or key or "-")
end)

Hub.On(Net.NpcDialogueReplied, function(...)
	local parts = {}
	for _, value in ipairs({ ... }) do
		if type(value) == "string" or type(value) == "number" then
			table.insert(parts, tostring(value))
		end
	end
	if #parts > 0 then
		Status.Npc = table.concat(parts, " ")
	end
end)

local Shop = { Blacklist = setmetatable({}, { __mode = "k" }) }

local Sorters = {
	["Best Profit"] = function(a, b)
		return a.Profit > b.Profit
	end,
	["Best Margin"] = function(a, b)
		return a.Margin > b.Margin
	end,
	["Cheapest"] = function(a, b)
		return a.Price < b.Price
	end,
	["Closest"] = function(a, b)
		return a.Distance < b.Distance
	end,
}

function Shop.Passes(entry, money)
	if next(Filter.Tiers) and not Filter.Tiers[entry.Tier] then
		return false
	end
	if next(Filter.Cars) and not Filter.Cars[entry.Key] then
		return false
	end
	if next(Filter.Junkyards) and not (entry.Grade and Filter.Junkyards[entry.Grade]) then
		return false
	end
	if entry.Grade and not junkyardUnlocked(entry.Grade) then
		return false
	end
	if Filter.MinPrice > 0 and entry.Price < Filter.MinPrice then
		return false
	end
	if Filter.MaxPrice > 0 and entry.Price > Filter.MaxPrice then
		return false
	end
	if Filter.MinProfit > 0 and entry.Profit < Filter.MinProfit then
		return false
	end
	if Filter.MinMargin > 0 and entry.Margin * 100 < Filter.MinMargin then
		return false
	end
	if money ~= nil and entry.Price > money - Filter.Reserve then
		return false
	end
	return true
end

function Shop.Candidates(ignoreMoney)
	local list = {}
	local money = nil
	if not ignoreMoney then
		money = getMoney()
	end
	local root = getRoot()
	local now = os.clock()
	local tag = JunkConstants.JunkVehicleTag or "JunkVehicle"
	for _, model in ipairs(CollectionService:GetTagged(tag)) do
		if model:IsA("Model") and model:IsDescendantOf(Workspace) and model:GetAttribute("VehicleSpawnLocked") ~= true and (Shop.Blacklist[model] or 0) < now then
			local key = model:GetAttribute(JunkConstants.VehicleNameAttribute or "VehicleName")
			local price = tonumber(model:GetAttribute(JunkConstants.PriceAttribute or "JunkPrice"))
			local info = key and VehicleData[key]
			if type(info) == "table" and price and price > 0 then
				local position = model:GetPivot().Position
				local sell = Car.FullValue(key)
				local entry = {
					Model = model,
					Key = key,
					Display = tostring(info.DisplayName or key),
					Price = price,
					Tier = tonumber(model:GetAttribute(JunkConstants.TierAttribute or "JunkTier")) or tonumber(info.Tier) or 0,
					Sell = sell,
					Profit = sell - price,
					Margin = (sell - price) / price,
					Grade = nearestJunkyard(position),
					Distance = root and (position - root.Position).Magnitude or 0,
				}
				if Shop.Passes(entry, money) then
					table.insert(list, entry)
				end
			end
		end
	end
	table.sort(list, Sorters[Filter.Sort] or Sorters["Best Profit"])
	return list
end

function Shop.Approach(model, reach)
	for attempt = 1, 4 do
		checkpoint()
		if not model.Parent then
			return false
		end
		local root = getRoot()
		if not root then
			sleep(0.5)
		else
			local pivot = model:GetPivot()
			local position = pivot.Position
			if (root.Position - position).Magnitude <= reach then
				return true
			end
			local _, size = model:GetBoundingBox()
			local halfLength, halfWidth = math.max(size.X, size.Z) / 2, math.min(size.X, size.Z) / 2
			local length = unit(flat(pivot.LookVector))
			local lateral = Vector3.new(-length.Z, 0, length.X)
			local first = flat(root.Position - position):Dot(lateral) >= 0 and lateral or -lateral
			local sides = {
				{ Dir = first, Extent = halfWidth },
				{ Dir = -first, Extent = halfWidth },
				{ Dir = length, Extent = halfLength },
				{ Dir = -length, Extent = halfLength },
			}
			local side = sides[attempt]
			local goal = position + side.Dir * math.min(side.Extent + 2.5, reach - 1)
			Move.WalkTo(Vector3.new(goal.X, root.Position.Y, goal.Z), 2.5, 30)
			local current = getRoot()
			if current and (current.Position - position).Magnitude <= reach then
				return true
			end
		end
	end
	local root = getRoot()
	if root and model.Parent then
		local position = model:GetPivot().Position
		local distance = (root.Position - position).Magnitude
		if distance <= reach then
			return true
		end
		if distance <= reach + 12 then
			local goal = position + unit(flat(root.Position - position)) * (reach - 3)
			Move.Hop(Vector3.new(goal.X, root.Position.Y + 0.5, goal.Z))
			sleep(0.5)
			local again = getRoot()
			return again ~= nil and (again.Position - position).Magnitude <= reach
		end
	end
	return false
end

function Shop.Buy(entry)
	local model = entry.Model
	if not model.Parent then
		return false, "Car is gone"
	end
	Move.Unseat()
	setStatus("Walking to car", entry.Display .. " " .. formatMoney(entry.Price))
	local reach = (tonumber(JunkConstants.MaxActivationDistanceStuds) or 12) - 2.5
	if not Shop.Approach(model, reach) then
		Shop.Blacklist[model] = os.clock() + 90
		return false, "Could not reach the car"
	end
	if getMoney() < entry.Price then
		return false, "Not enough money"
	end
	setStatus("Buying", entry.Display .. " " .. formatMoney(entry.Price))
	local previous = Car.Get()
	local previousId = previous and previous:GetAttribute("GarageVehicleId")
	local car
	for attempt = 1, 3 do
		Status.Message = "-"
		Hub.Fire(Net.JunkBuyRequested, model)
		car = waitFor(function()
			local current = Car.Get()
			if current and current:GetAttribute("GarageVehicleId") ~= previousId then
				return current
			end
			local message = string.lower(Status.Message)
			return string.find(message, "closer", 1, true) ~= nil or string.find(message, "garages are full", 1, true) ~= nil
		end, 6)
		if car ~= true then
			break
		end
		car = nil
		if string.find(string.lower(Status.Message), "garages are full", 1, true) then
			return false, "GarageFull"
		end
		if not model.Parent then
			break
		end
		Shop.Approach(model, (tonumber(JunkConstants.MaxActivationDistanceStuds) or 12) - 4)
		sleep(0.6)
	end
	if not car then
		Shop.Blacklist[model] = os.clock() + 60
		return false, Status.Message
	end
	Stats.Bought = Stats.Bought + 1
	Stats.Spent = Stats.Spent + entry.Price
	Garage.Mark(car:GetAttribute("GarageVehicleId"), true, entry.Price)
	Farm.Current = {
		Id = car:GetAttribute("GarageVehicleId"),
		Key = entry.Key,
		Display = entry.Display,
		Paid = entry.Price,
		Tier = entry.Tier,
		Started = os.clock(),
	}
	if Farm.Hooks.Bought then
		pcall(Farm.Hooks.Bought, entry)
	end
	return true
end

local Repair = {
	Hood = setmetatable({}, { __mode = "k" }),
	Attempts = {},
	Entrance = nil,
}

function Repair.ToggleHood(car, open)
	local actual = Car.HoodOpen(car)
	if actual ~= nil then
		Repair.Hood[car] = actual
	end
	if (Repair.Hood[car] == true) == (open == true) then
		return
	end
	local hood = Car.Hood(car)
	local root = getRoot()
	if hood and root and (root.Position - hood.Position).Magnitude > 12 then
		Move.WalkTo(Car.StandPoint(car, hood.Position), 3, 15)
	end
	Hub.Fire(Net.VehicleHingeToggleRequested, "Hood")
	Repair.Hood[car] = open == true
	sleep(0.7)
end

function Repair.EquipWrench()
	local character = LocalPlayer.Character
	local humanoid = getHumanoid()
	if not (character and humanoid) or character:FindFirstChild("Wrench") then
		return
	end
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	local wrench = backpack and backpack:FindFirstChild("Wrench")
	if wrench then
		pcall(function()
			humanoid:EquipTool(wrench)
		end)
		sleep(0.3)
	end
end

function Repair.Unequip()
	local humanoid = getHumanoid()
	if humanoid then
		pcall(function()
			humanoid:UnequipTools()
		end)
	end
end

function Repair.NearLift(car)
	local position = car:GetPivot().Position
	for _, lift in ipairs(CollectionService:GetTagged(LiftTag)) do
		if lift:IsA("Model") and lift:IsDescendantOf(Workspace) and (flat(lift:GetPivot().Position) - flat(position)).Magnitude < 4 then
			local _, entrance = Machines.LiftLayout(lift)
			return lift, entrance
		end
	end
	return nil
end

function Repair.Prepare(car)
	Wheels.Unlift(car)
	local humanoid = getHumanoid()
	if not (humanoid and humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(car)) then
		setStatus("Getting in the car")
		if not Move.EnterCar(car) then
			error("Could not get into the car", 0)
		end
	end
	local lift
	local started = os.clock()
	repeat
		lift = Machines.FindLift(car:GetPivot().Position, car)
		if not lift then
			setStatus("Waiting for a free lift")
			sleep(3)
		end
	until lift or os.clock() - started > 60
	if not lift then
		error("No free lift in the workshop", 0)
	end
	local center, entrance = Machines.LiftLayout(lift)
	setStatus("Teleporting to workshop", (Car.Name(car)))
	if State.TravelMode == "Teleport" then
		local ok, reason = Move.Drive(car, center, nil, nil, -entrance)
		if not ok then
			error("Teleport to workshop failed: " .. tostring(reason), 0)
		end
	else
		local approach = center + entrance * 16
		local ok, reason = Move.Drive(car, approach, State.DriveSpeed, 7)
		if not ok and (flat(car:GetPivot().Position) - flat(approach)).Magnitude > 18 then
			error("Drive to workshop failed: " .. tostring(reason), 0)
		end
		setStatus("Parking on lift")
		if (flat(car:GetPivot().Position) - flat(approach)).Magnitude > 3 then
			Move.Park(car, approach, -entrance, 10, 1.5, 8)
		end
		Move.Park(car, center, -entrance, 10)
	end
	sleep(0.6)
	Repair.Entrance = entrance
	setStatus("Leaving the car")
	if not Move.ExitCar(car, entrance) then
		error("Could not leave the car", 0)
	end
end

function Repair.Extract(car, slot)
	local key = car:GetAttribute("VehicleName")
	local existing = Parts.FindExtracted(slot, key)
	if existing then
		return existing
	end
	local installed = Car.Installed(car, slot)
	if not installed then
		return nil
	end
	local position = Parts.Position(installed) or car:GetPivot().Position
	if Move.Distance(position) > 9 then
		Move.WalkTo(Car.StandPoint(car, position), 2.5, 20)
	end
	Repair.EquipWrench()
	setStatus("Extracting", slot)
	for _ = 1, 2 do
		checkpoint()
		Hub.Fire(Net.WrenchExtractRequested, car, slot)
		local part = waitFor(function()
			return Parts.FindExtracted(slot, key)
		end, 2.5)
		if part then
			return part
		end
	end
	return nil
end

function Repair.Place(car, item, machine)
	Move.Unseat()
	local zone = Machines.Zone(machine, item.Kind)
	for _ = 1, 2 do
		checkpoint()
		local part = item.Part
		if not part.Parent then
			return false
		end
		local position = Parts.Position(part)
		if position and Move.Distance(position) > 14 then
			Move.WalkTo(position, 6, 20)
		end
		if Parts.Grab(part) then
			local root = getRoot()
			local from = car:GetPivot().Position
			local approach = unit(flat(from - zone), unit(flat((root and root.Position or from) - zone)))
			local stand = zone + approach * 4.5
			Move.WalkTo(Vector3.new(stand.X, root and root.Position.Y or stand.Y, stand.Z), 2.5, 25)
			Carry.Goal = zone
			waitFor(function()
				local current = Parts.Position(part)
				return current ~= nil and (current - zone).Magnitude < 1.3
			end, 2.5)
			sleep(0.25)
			Parts.Release()
			if waitFor(function()
				return part:GetAttribute("InMachine") == true
			end, 5) then
				sleep(0.4)
				return true
			end
		else
			sleep(0.5)
		end
	end
	return false
end

function Repair.Install(car, part, careful)
	local drop = Car.Drop(car)
	if not drop or not part.Parent then
		return false
	end
	if careful then
		Wheels.Carry(part, drop.Position, { Height = 7, Above = 4, Tolerance = 1.5, StandAt = Car.StandPoint(car, drop.Position), Action = function(target)
			Hub.Fire(Net.DropCarPartRequested, target)
		end })
		return waitFor(function()
			return part:IsDescendantOf(car)
		end, 3) ~= nil
	end
	local position = Parts.Position(part)
	if position and Move.Distance(position) > 14 then
		Move.WalkTo(position, 6, 20)
	end
	if not Parts.Grab(part) then
		return false
	end
	Move.WalkTo(Car.StandPoint(car, drop.Position), 2.5, 25)
	Carry.Goal = drop.Position
	waitFor(function()
		local current = Parts.Position(part)
		return current ~= nil and (current - drop.Position).Magnitude < 1.5
	end, 2.5)
	Hub.Fire(Net.DropCarPartRequested, part)
	Parts.Release()
	return waitFor(function()
		return part:IsDescendantOf(car)
	end, 3) ~= nil
end

function Repair.Cancel(item)
	local machine = item.Machine
	if not machine then
		return
	end
	if item.Kind == "Battery" then
		Hub.Fire(Net.BatteryClampRequested, machine, 0)
	elseif item.Kind == "Washable" then
		Hub.Fire(Net.WashFinishRequested, false)
	elseif item.Kind == "Engine" then
		Hub.Fire(Net.EngineWeldRequested, machine, HoistActions.Cancel, Vector3.zero)
	end
	sleep(1)
end

function Repair.Process(car, tasks)
	local reserved = {}
	local deadline = os.clock() + 300
	while os.clock() < deadline do
		checkpoint()
		local now = os.clock()
		for _, item in ipairs(tasks) do
			if item.State == "Placed" then
				local part = item.Part
				if not part.Parent then
					item.State = "Lost"
					if item.Machine then
						reserved[item.Machine] = nil
					end
				elseif part:GetAttribute("InMachine") ~= true and now - item.PlacedAt > 1.5 then
					if item.Machine then
						reserved[item.Machine] = nil
					end
					local wear = Parts.Wear(part)
					if wear <= math.max(State.MinWear, 0.05) then
						item.State = "Repaired"
						Stats.Repaired = Stats.Repaired + 1
					else
						item.Fails = (item.Fails or 0) + 1
						item.Wear = wear
						item.State = item.Fails < 2 and "Extracted" or "Failed"
					end
				elseif item.Machine and not item.Nudged and (item.Kind == "Engine" or item.Kind == "Washable") and now - item.PlacedAt > (item.Kind == "Engine" and State.WeldDelay or State.WashDelay) + 10 then
					item.Nudged = true
					if item.Kind == "Engine" then
						Hub.Fire(Net.EngineWeldRequested, item.Machine, HoistActions.Complete, Vector3.zero)
					else
						Hub.Fire(Net.WashFinishRequested, true)
						task.delay(2, function()
							if Hub.Running and Minigame.FrameOpen("Cleaning") then
								Minigame.CloseFrame("Cleaning", { "Buttons", "Cancel" })
							end
						end)
					end
				elseif now - item.PlacedAt > (MachineTimeouts[item.Kind] or 45) then
					Repair.Cancel(item)
					if item.Machine then
						reserved[item.Machine] = nil
					end
					item.Fails = (item.Fails or 0) + 1
					item.State = item.Fails < 2 and "Extracted" or "Failed"
				end
			end
		end
		for _, item in ipairs(tasks) do
			if item.State == "Extracted" and item.Part.Parent and Parts.Wear(item.Part) <= math.max(State.MinWear, 0.001) then
				item.State = "Repaired"
			end
		end
		for _, item in ipairs(tasks) do
			if item.State == "Extracted" and not item.Machine and item.Part.Parent and item.Part:GetAttribute("InMachine") == true then
				item.State = "Placed"
				item.PlacedAt = os.clock()
			end
		end
		for _, item in ipairs(tasks) do
			if item.State == "Extracted" then
				local machine = Machines.Find(item.Kind, car:GetPivot().Position, reserved)
				if machine then
					reserved[machine] = true
					setStatus("Repairing", item.Slot)
					if Repair.Place(car, item, machine) then
						item.State = "Placed"
						item.Machine = machine
						item.PlacedAt = os.clock()
					else
						reserved[machine] = nil
						if Minigame.Blocking() then
							Minigame.CloseFrame("Cleaning", { "Buttons", "Cancel" })
							sleep(1)
						else
							item.Places = (item.Places or 0) + 1
							if item.Places >= 3 then
								item.State = "Unplaced"
							end
						end
					end
				end
			end
		end
		local working, queued = 0, 0
		for _, item in ipairs(tasks) do
			if item.State == "Placed" then
				working = working + 1
			elseif item.State == "Extracted" then
				queued = queued + 1
			end
		end
		if working == 0 and queued == 0 then
			return true
		end
		setStatus("Waiting for machines", tostring(working) .. " in work, " .. tostring(queued) .. " queued")
		sleep(0.5)
	end
	return false
end

function Repair.Run(car)
	local key = car:GetAttribute("VehicleName")
	local id = car:GetAttribute("GarageVehicleId") or key or "car"
	for _, slot in ipairs(Car.MissingSlots(car)) do
		if not Parts.FindExtracted(slot, nil) then
			local itemId = Repair.InventoryFor(slot)
			if itemId then
				setStatus("Taking part from inventory", slot)
				Hub.Fire(Net.SpawnCarPartFromInventoryRequested, itemId)
				waitFor(function()
					return Parts.FindExtracted(slot, nil)
				end, 4)
			end
		end
	end
	local worn = Parts.Worn(car)
	local leftovers = Parts.Extracted(key)
	if #worn == 0 and #leftovers == 0 then
		return true
	end
	local lift, entrance = Repair.NearLift(car)
	if lift and (flat(lift:GetPivot().Position) - flat(Places.Workshop)).Magnitude > 150 then
		lift = nil
	end
	if lift then
		Repair.Entrance = entrance
		local humanoid = getHumanoid()
		if humanoid and humanoid.SeatPart then
			Move.ExitCar(car, entrance)
		end
	else
		Repair.Prepare(car)
	end
	Repair.Attempts[id] = (Repair.Attempts[id] or 0) + 1
	local tasks = {}
	local known = {}
	for _, part in ipairs(leftovers) do
		local slot = Parts.Slot(part)
		local kind = Parts.Kind(slot)
		local wear = Parts.Wear(part)
		known[slot] = true
		table.insert(tasks, {
			Slot = slot,
			Kind = kind,
			Part = part,
			Wear = wear,
			State = (kind and Parts.Enabled(kind) and wear > State.MinWear) and "Extracted" or "Unplaced",
		})
	end
	Repair.ToggleHood(car, true)
	local first = true
	for _, info in ipairs(worn) do
		if not known[info.Slot] then
			local part = Repair.Extract(car, info.Slot)
			if not part and first then
				Repair.Hood[car] = not Repair.Hood[car]
				Hub.Fire(Net.VehicleHingeToggleRequested, "Hood")
				sleep(0.8)
				part = Repair.Extract(car, info.Slot)
				if not part then
					Repair.Hood[car] = not Repair.Hood[car]
					Hub.Fire(Net.VehicleHingeToggleRequested, "Hood")
					sleep(0.8)
				end
			end
			first = false
			if part then
				known[info.Slot] = true
				local wear = Parts.Wear(part)
				table.insert(tasks, { Slot = info.Slot, Kind = info.Kind, Part = part, Wear = wear, State = wear > State.MinWear and "Extracted" or "Repaired" })
			end
		end
	end
	Repair.Unequip()
	Repair.Process(car, tasks)
	Repair.Recover(car)
	Repair.ToggleHood(car, false)
	Repair.Unequip()
	return true
end

local function dialogTitle()
	local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local frames = gui and gui:FindFirstChild("Frames")
	local notification = frames and frames:FindFirstChild("Notification")
	local contents = notification and notification:FindFirstChild("Contents")
	local topBar = contents and contents:FindFirstChild("TopBar")
	local header = topBar and topBar:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	if notification and notification:IsA("GuiObject") and notification.Visible and title and title:IsA("TextLabel") then
		return title.Text
	end
	return nil
end

local function dismissDialog(expectedTitle)
	if dialogTitle() ~= expectedTitle then
		return
	end
	if type(ConfirmationService) == "table" and type(ConfirmationService.Dismiss) == "function" then
		pcall(function()
			ConfirmationService:Dismiss()
		end)
	end
end

Hub.On(Net.MissingPartResolutionPrompted, function(id, text)
	if not (Hub.Running and State.AutoMissingParts) then
		return
	end
	task.spawn(function()
		task.wait(0.4)
		if not Hub.Running then
			return
		end
		Hub.Fire(Net.MissingPartResolutionResolved, id, true)
		Status.Message = "Install from inventory: " .. string.gsub(tostring(text or ""), "<[^>]+>", "")
		task.wait(0.2)
		dismissDialog("Missing Part")
	end)
end)

local function slotDepth(slot)
	local depth = 0
	local need = SlotNeeds[slot]
	while need and depth < 5 do
		depth = depth + 1
		need = SlotNeeds[need]
	end
	return depth
end

local function slotOfPartName(partName)
	if type(CarPartsData) == "table" and type(CarPartsData.GetVariant) == "function" then
		local ok, variant = pcall(CarPartsData.GetVariant, partName)
		if ok and type(variant) == "table" and type(variant.Group) == "string" then
			return variant.Group
		end
	end
	return (string.match(tostring(partName), "^([^:]+)"))
end

function Repair.InventoryFor(slot)
	local profile = getProfile()
	local inventory = profile and profile.Inventory
	local items = type(inventory) == "table" and inventory.CarParts
	if type(items) ~= "table" then
		return nil
	end
	for id, item in pairs(items) do
		if type(item) == "table" and slotOfPartName(item.PartName) == slot then
			return id, item
		end
	end
	return nil
end

function Repair.RecoverByDialog(car)
	local missing = Car.MissingSlots(car)
	local owned = false
	for _, slot in ipairs(missing) do
		if Repair.InventoryFor(slot) or Parts.FindExtracted(slot, nil) then
			owned = true
		end
	end
	if not owned or not State.AutoMissingParts then
		return #missing == 0
	end
	local before = #missing
	setStatus("Installing missing parts", table.concat(missing, ", "))
	for _ = 1, 3 do
		checkpoint()
		local humanoid = getHumanoid()
		if humanoid and humanoid.SeatPart then
			humanoid.Sit = false
			sleep(1)
		end
		Move.EnterCar(car)
		waitFor(function()
			return #Car.MissingSlots(car) == 0
		end, 6 + 7 * before)
		local left = #Car.MissingSlots(car)
		if left == 0 or left >= before then
			break
		end
		before = left
	end
	return #Car.MissingSlots(car) == 0
end

function Repair.Recover(car)
	local missing = Car.MissingSlots(car)
	if #missing == 0 then
		return true
	end
	table.sort(missing, function(a, b)
		return slotDepth(a) < slotDepth(b)
	end)
	local key = car:GetAttribute("VehicleName")
	local opened = false
	for _, slot in ipairs(missing) do
		checkpoint()
		if not Car.SlotFilled(car, slot) then
			local part = Parts.FindExtracted(slot, key) or Parts.FindExtracted(slot, nil)
			if not part then
				local itemId = Repair.InventoryFor(slot)
				if itemId then
					setStatus("Taking part from inventory", slot)
					Hub.Fire(Net.SpawnCarPartFromInventoryRequested, itemId)
					part = waitFor(function()
						return Parts.FindExtracted(slot, nil) or (Car.SlotFilled(car, slot) and true)
					end, 5)
				end
			end
			if part and part ~= true and not Car.SlotFilled(car, slot) then
				local humanoid = getHumanoid()
				if humanoid and humanoid.SeatPart then
					Move.ExitCar(car, Repair.Entrance)
				end
				if not opened then
					Repair.ToggleHood(car, true)
					opened = true
				end
				setStatus("Installing", slot)
				for attempt = 1, 3 do
					if Repair.Install(car, part, attempt > 1) or Car.SlotFilled(car, slot) then
						break
					end
					sleep(1)
				end
			end
		end
	end
	if opened then
		Repair.ToggleHood(car, false)
	end
	if #Car.MissingSlots(car) > 0 then
		Repair.RecoverByDialog(car)
	end
	return #Car.MissingSlots(car) == 0
end

local Seller = { Replica = nil, LastScan = 0 }

if type(ReplicaClient) == "table" and type(ReplicaClient.OnNew) == "function" then
	pcall(function()
		local connection = ReplicaClient.OnNew(SellConstants.ReplicaToken or "SellOffer", function(replica)
			local tags = type(replica) == "table" and replica.Tags
			if type(tags) ~= "table" or tags.PlayerUserId == nil or tags.PlayerUserId == LocalPlayer.UserId then
				Seller.Replica = replica
			end
		end)
		if connection ~= nil then
			table.insert(Hub.Cleanups, connection)
		end
	end)
end

function Seller.FindReplica()
	local replica = Seller.Replica
	if type(replica) == "table" and type(replica.Data) == "table" then
		return replica
	end
	if type(ReplicaClient) ~= "table" or type(ReplicaClient.FromId) ~= "function" or os.clock() - Seller.LastScan < 5 then
		return nil
	end
	Seller.LastScan = os.clock()
	local token = SellConstants.ReplicaToken or "SellOffer"
	for id = 1, 60000 do
		local ok, item = pcall(ReplicaClient.FromId, id)
		if ok and type(item) == "table" and tostring(item.Token) == token then
			local tags = item.Tags
			if type(tags) ~= "table" or tags.PlayerUserId == nil or tags.PlayerUserId == LocalPlayer.UserId then
				Seller.Replica = item
				return item
			end
		end
	end
	return nil
end

function Seller.Deals()
	local replica = Seller.FindReplica()
	local data = replica and replica.Data
	local deals = type(data) == "table" and data.Deals
	if type(deals) == "table" then
		return deals
	end
	return {}
end

function Seller.Zone(sellerId)
	for _, part in ipairs(CollectionService:GetTagged(SellConstants.HitboxTag or "SellHitbox")) do
		if part:IsA("BasePart") and part:IsDescendantOf(Workspace) and part:GetAttribute("SellerId") == sellerId then
			return part
		end
	end
	return nil
end

function Seller.Prompt(tag)
	for _, prompt in ipairs(CollectionService:GetTagged(tag)) do
		if prompt:IsA("ProximityPrompt") and prompt:IsDescendantOf(Workspace) then
			return prompt
		end
	end
	return nil
end

function Seller.PromptPosition(prompt)
	local parent = prompt.Parent
	if not parent then
		return nil
	end
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	if parent:IsA("BasePart") then
		return parent.Position
	end
	if parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

function Seller.LeaveLift(car)
	if State.TravelMode == "Teleport" then
		return
	end
	local lift, entrance = Repair.NearLift(car)
	if not lift then
		return
	end
	setStatus("Backing out of the lift")
	local center = Machines.LiftLayout(lift)
	Move.Park(car, center + entrance * 18, Car.Forward(car), 12, 2, 5)
	sleep(0.3)
end

function Seller.Trigger(prompt)
	local ok = pcall(function()
		prompt:InputHoldBegin()
		task.wait((tonumber(prompt.HoldDuration) or 0) + 0.15)
		prompt:InputHoldEnd()
	end)
	if not ok and type(fireproximityprompt) == "function" then
		ok = pcall(fireproximityprompt, prompt)
	end
	return ok
end

function Seller.Gone(car, id)
	local profile = getProfile()
	local garage = profile and profile.Garage
	local vehicles = type(garage) == "table" and garage.Vehicles
	if id and type(vehicles) == "table" then
		return vehicles[id] == nil
	end
	return not car.Parent
end

function Seller.Settle(id, earned)
	if Seller.Late and Seller.Late.Id == id then
		Seller.Late = nil
	end
	Garage.Mark(id, false)
	Farm.RecordSale(earned)
	Farm.Forget(id)
end

function Seller.CheckLate(car)
	local late = Seller.Late
	if not late or (car and late.Car ~= car) or not Seller.Gone(late.Car, late.Id) then
		return false
	end
	Seller.Settle(late.Id, (late.Offer and late.Offer > 0) and late.Offer or math.max(0, getMoney() - late.Before))
	return true
end

function Seller.Finish(car, action, offer)
	local before = getMoney()
	local id = car:GetAttribute("GarageVehicleId")
	action()
	local sold = waitFor(function()
		return not car.Parent or Seller.Gone(car, id) or getMoney() > before + math.max(1, (offer or 0) * 0.5)
	end, 30, 0.2)
	if not sold then
		Seller.Late = { Car = car, Id = id, Offer = offer, Before = before }
		return false
	end
	sleep(0.6)
	Seller.Settle(id, (offer and offer > 0) and offer or math.max(0, getMoney() - before))
	return true
end

function Seller.Negotiate(dealKey)
	for _ = 1, 6 do
		checkpoint()
		local deal = Seller.Deals()[dealKey]
		if type(deal) ~= "table" or deal.Rejected == true then
			return
		end
		local risk = tonumber(deal.RiskPct) or 100
		if risk > State.MaxRisk then
			return
		end
		local offer = tonumber(deal.OfferAmount) or 0
		setStatus("Negotiating", formatMoney(offer) .. " | risk " .. tostring(math.floor(risk)) .. "%")
		Hub.Fire(Net.RequestSellDecision, dealKey, SellActions.Negotiate)
		local changed = waitFor(function()
			local current = Seller.Deals()[dealKey]
			return type(current) ~= "table" or current.Rejected == true or (tonumber(current.OfferAmount) or 0) ~= offer
		end, 5)
		if not changed then
			return
		end
		sleep(0.5)
	end
end

function Seller.SellNpc(car, sellerId, talkTag, fallback)
	if not Move.EnterCar(car) then
		error("Could not get into the car", 0)
	end
	Seller.LeaveLift(car)
	local zone = Seller.Zone(sellerId)
	if not zone then
		Move.Stream(fallback)
		zone = Seller.Zone(sellerId)
	end
	if not zone then
		setStatus("Teleporting to " .. sellerId)
		Move.Drive(car, groundAt(fallback), State.DriveSpeed, 45)
		zone = waitFor(function()
			return Seller.Zone(sellerId)
		end, 6)
	end
	if not zone then
		error("Seller zone not found", 0)
	end
	local axis = zone.Size.Z >= zone.Size.X and zone.CFrame.LookVector or zone.CFrame.RightVector
	axis = unit(flat(axis))
	if axis:Dot(Car.Forward(car)) < 0 then
		axis = -axis
	end
	local prompt
	local function present()
		if not Move.EnterCar(car) then
			error("Could not get into the car", 0)
		end
		setStatus("Teleporting to " .. sellerId)
		local ok, reason = Move.Drive(car, groundAt(zone.Position), State.DriveSpeed, 6, axis)
		if not ok and (flat(car:GetPivot().Position) - flat(zone.Position)).Magnitude > 18 then
			error("Drive to seller failed: " .. tostring(reason), 0)
		end
		if State.TravelMode ~= "Teleport" then
			setStatus("Parking", sellerId)
			Move.Park(car, zone.Position, axis, 8)
		end
		sleep(1)
		setStatus("Leaving the car")
		Move.ExitCar(car)
		prompt = Seller.Prompt(talkTag)
		if not prompt then
			error("Seller not found", 0)
		end
		local promptPosition = Seller.PromptPosition(prompt)
		local reach = math.max(4, (prompt.MaxActivationDistance or 10) - 4)
		if promptPosition and Move.Distance(promptPosition) > reach then
			setStatus("Walking to " .. sellerId)
			Move.WalkTo(promptPosition, reach, 20)
		end
	end
	present()
	local known = {}
	for dealKey, deal in pairs(Seller.Deals()) do
		known[dealKey] = type(deal) == "table" and tonumber(deal.ExpiresAt) or true
	end
	local id = car:GetAttribute("GarageVehicleId")
	local found
	for attempt = 1, 3 do
		checkpoint()
		if attempt > 1 then
			if Seller.Gone(car, id) then
				found = { Gone = true }
				break
			end
			setStatus("No offer yet", "parking the car again")
			sleep(1)
			present()
		end
		setStatus("Talking to " .. sellerId)
		Seller.Trigger(prompt)
		found = waitFor(function()
			if Seller.Gone(car, id) then
				return { Gone = true }
			end
			for dealKey, deal in pairs(Seller.Deals()) do
				if type(deal) == "table" and (known[dealKey] == nil or known[dealKey] ~= tonumber(deal.ExpiresAt)) then
					return { Key = dealKey }
				end
			end
			return nil
		end, 10)
		if found then
			break
		end
	end
	if found and found.Gone then
		if Seller.CheckLate(car) then
			return true
		end
		error("The car is gone", 0)
	end
	if not found then
		error("No offer: " .. tostring(Status.Npc ~= "-" and Status.Npc or Status.Message), 0)
	end
	local dealKey = found.Key
	local deal = Seller.Deals()[dealKey]
	local revealAt = type(deal) == "table" and tonumber(deal.RevealAt)
	if revealAt then
		setStatus("Waiting for the offer")
		waitFor(function()
			return Workspace:GetServerTimeNow() >= revealAt
		end, 15)
	end
	if State.Negotiate then
		Seller.Negotiate(dealKey)
	end
	deal = Seller.Deals()[dealKey]
	if type(deal) ~= "table" then
		error("Offer disappeared", 0)
	end
	local offer = tonumber(deal.OfferAmount) or 0
	setStatus("Accepting offer", formatMoney(offer))
	local sold = Seller.Finish(car, function()
		Hub.Fire(Net.RequestSellDecision, dealKey, SellActions.Accept)
	end, offer)
	if not sold then
		error("Sale was not confirmed", 0)
	end
	return true
end

function Seller.SellRick(car)
	if not Move.EnterCar(car) then
		return false, "Could not get into the car"
	end
	Seller.LeaveLift(car)
	local prompt = Seller.Prompt("SellACar")
	local target = prompt and Seller.PromptPosition(prompt) or Places.Rick
	setStatus("Teleporting to Rick")
	local away = unit(flat(car:GetPivot().Position - target), Vector3.new(1, 0, 0))
	local ok, reason = Move.Drive(car, groundAt(target + away * 14), State.DriveSpeed, 16)
	if not ok then
		return false, "Drive failed: " .. tostring(reason)
	end
	Move.ExitCar(car)
	prompt = prompt or waitFor(function()
		return Seller.Prompt("SellACar")
	end, 5)
	if not prompt then
		return false, "Rick not found"
	end
	local position = Seller.PromptPosition(prompt)
	local reach = math.max(4, (prompt.MaxActivationDistance or 10) - 4)
	if position and Move.Distance(position) > reach then
		Move.WalkTo(position, reach, 20)
	end
	Minigame.SellConfirm = nil
	setStatus("Talking to Rick")
	Seller.Trigger(prompt)
	local confirm = waitFor(function()
		return Minigame.SellConfirm
	end, 8)
	if type(ConfirmationService) == "table" and type(ConfirmationService.Dismiss) == "function" then
		pcall(function()
			ConfirmationService:Dismiss()
		end)
	end
	if not confirm then
		return false, "Rick made no offer"
	end
	local expected = Car.Value(car) or 0
	if expected > 0 and confirm.Amount < expected * State.RickMinPercent / 100 then
		return false, "Rick offered " .. formatMoney(confirm.Amount) .. " of " .. formatMoney(expected)
	end
	setStatus("Selling to Rick", formatMoney(confirm.Amount))
	if Seller.Finish(car, function()
		Hub.Fire(Net.SellCarConfirmed)
	end, confirm.Amount) then
		return true
	end
	return false, "Rick sale was not confirmed"
end

function Seller.Sell(car)
	Wheels.Unlift(car)
	local key = car:GetAttribute("VehicleName")
	local info = key and VehicleData[key]
	local tier = type(info) == "table" and tonumber(info.Tier) or 1
	if State.Seller == "Rick (Quick Sell)" then
		local ok, reason = Seller.SellRick(car)
		if ok then
			return true
		end
		if not car.Parent then
			return true
		end
		setStatus("Rick skipped", reason)
		sleep(1)
	end
	local lupin = Sellers.MrLupin
	local allowed = false
	if type(lupin) == "table" and type(lupin.AllowedTiers) == "table" then
		for _, value in ipairs(lupin.AllowedTiers) do
			if value == tier then
				allowed = true
			end
		end
	end
	if State.UseLupin and allowed then
		return Seller.SellNpc(car, "MrLupin", "MrLupin_Talk", Places.MrLupin)
	end
	return Seller.SellNpc(car, "Juan", "Juan_Talk", Places.Juan)
end

local Paint = {
	Fallback = Vector3.new(1005, 84, -786),
	Material = type(PaintMaterials) == "table" and type(PaintMaterials.Default) == "string" and PaintMaterials.Default or "CarPaint",
	Cost = type(PaintCosts) == "table" and tonumber(PaintCosts.Paint) or 250,
}

local PaintColors = {
	Black = Color3.fromRGB(20, 20, 22),
	White = Color3.fromRGB(235, 235, 235),
	Red = Color3.fromRGB(190, 25, 30),
	Blue = Color3.fromRGB(25, 70, 190),
	Silver = Color3.fromRGB(165, 170, 175),
	Green = Color3.fromRGB(30, 140, 60),
	Yellow = Color3.fromRGB(240, 200, 30),
}

function Paint.Hitboxes()
	local list = {}
	for _, part in ipairs(CollectionService:GetTagged("PAINT_HITBOX")) do
		if part:IsA("BasePart") and part:IsDescendantOf(Workspace) then
			table.insert(list, part)
		end
	end
	return list
end

function Paint.Free(zone, car)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return true
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { vehicles }
	for _, part in ipairs(Workspace:GetPartBoundsInBox(zone.CFrame, zone.Size, params)) do
		if not part:IsDescendantOf(car) then
			return false
		end
	end
	return true
end

function Paint.Color()
	local name = State.PaintColor
	if not PaintColors[name] then
		local names = {}
		for key in pairs(PaintColors) do
			table.insert(names, key)
		end
		name = names[math.random(1, #names)]
	end
	return PaintColors[name]
end

function Paint.Run(car)
	if not State.Paint or car:GetAttribute("Painted") == true then
		return true
	end
	if getMoney() < Paint.Cost + Filter.Reserve then
		return false
	end
	Wheels.Unlift(car)
	if not Move.EnterCar(car) then
		error("Could not get into the car", 0)
	end
	Seller.LeaveLift(car)
	local zones = Paint.Hitboxes()
	if #zones == 0 then
		Move.Stream(Paint.Fallback)
		zones = Paint.Hitboxes()
	end
	if #zones == 0 then
		setStatus("Teleporting to paint shop")
		Move.Drive(car, groundAt(Paint.Fallback), State.DriveSpeed, 40)
		zones = Paint.Hitboxes()
	end
	local position = car:GetPivot().Position
	table.sort(zones, function(a, b)
		return (a.Position - position).Magnitude < (b.Position - position).Magnitude
	end)
	local zone
	for _, candidate in ipairs(zones) do
		if Paint.Free(candidate, car) then
			zone = candidate
			break
		end
	end
	zone = zone or zones[1]
	if not zone then
		error("Paint shop not found", 0)
	end
	local axis = zone.Size.X >= zone.Size.Z and zone.CFrame.RightVector or zone.CFrame.LookVector
	axis = unit(flat(axis))
	if axis:Dot(Car.Forward(car)) < 0 then
		axis = -axis
	end
	setStatus("Teleporting to paint shop")
	local ok, reason = Move.Drive(car, groundAt(zone.Position), State.DriveSpeed, 6, axis)
	if not ok and (flat(car:GetPivot().Position) - flat(zone.Position)).Magnitude > 18 then
		error("Drive to paint shop failed: " .. tostring(reason), 0)
	end
	if State.TravelMode ~= "Teleport" then
		setStatus("Parking in paint shop")
		Move.Park(car, zone.Position, axis, 8)
	end
	sleep(0.5)
	local color = Paint.Color()
	for attempt = 1, 2 do
		checkpoint()
		setStatus("Painting", "attempt " .. tostring(attempt))
		Hub.Fire(Net.PaintShopPaintRequested, "Primary", color.R, color.G, color.B, Paint.Material)
		if waitFor(function()
			return car:GetAttribute("Painted") == true
		end, 5) then
			Stats.Painted = (Stats.Painted or 0) + 1
			return true
		end
		Move.ExitCar(car)
		sleep(0.5)
	end
	return car:GetAttribute("Painted") == true
end

function Wheels.Mine(item)
	return item:GetAttribute("OwnerUserId") == LocalPlayer.UserId
end

function Wheels.Loose(kind)
	local list = {}
	local folder = Workspace:FindFirstChild("ExtractedCarParts")
	for _, item in ipairs(folder and folder:GetChildren() or {}) do
		if Wheels.Mine(item) and item:GetAttribute("CarPartType") == kind then
			table.insert(list, item)
		end
	end
	return list
end

function Wheels.Snapshot()
	local set = {}
	local folder = Workspace:FindFirstChild("ExtractedCarParts")
	for _, item in ipairs(folder and folder:GetChildren() or {}) do
		set[item] = true
	end
	return set
end

function Wheels.Fresh(kind, before)
	for _, item in ipairs(Wheels.Loose(kind)) do
		if not before[item] then
			return item
		end
	end
	return nil
end

function Wheels.HasRim(tire)
	if not (tire and tire.Parent and tire:IsA("Model")) then
		return false
	end
	for _, child in ipairs(tire:GetChildren()) do
		if child:GetAttribute("CarPartType") == "Rim" then
			return true
		end
	end
	return false
end

function Wheels.Entry(car, kind, slot)
	local record = Car.Record(car)
	local list = record and record[Wheels.Fields[kind]]
	if type(list) ~= "table" then
		return nil, false
	end
	local entry = list[slot]
	return type(entry) == "table" and entry or nil, true
end

function Wheels.Installed(car, slot)
	local entry, known = Wheels.Entry(car, "Tire", slot)
	if not known then
		return true
	end
	return entry ~= nil and type(entry.Variant) == "string" and entry.Variant ~= ""
end

function Wheels.Incomplete(car)
	for _, slot in ipairs(Wheels.Slots) do
		if not Wheels.Installed(car, slot) then
			return true
		end
	end
	return false
end

function Wheels.Price(kind, variant)
	if type(variant) == "string" and type(CarPartsData) == "table" and type(CarPartsData.GetPrice) == "function" then
		local ok, price = pcall(CarPartsData.GetPrice, variant)
		if ok and tonumber(price) and tonumber(price) > 0 then
			return tonumber(price)
		end
	end
	return Wheels.Prices[kind] or 300
end

function Wheels.Gain(car, kind, slot)
	local record = Car.Record(car)
	local key = car:GetAttribute("VehicleName")
	local field = Wheels.Fields[kind]
	if not (record and key and type(record[field]) == "table" and type(Pricing) == "table" and type(Pricing.ComputeStoredValue) == "function") then
		return 0
	end
	local copy, list = {}, {}
	for name, value in pairs(record) do
		copy[name] = value
	end
	for name, value in pairs(record[field]) do
		list[name] = value
	end
	local current = list[slot]
	list[slot] = { Variant = type(current) == "table" and current.Variant ~= "" and current.Variant or kind, Wear = 0 }
	copy[field] = list
	local okBefore, before = pcall(Pricing.ComputeStoredValue, key, record)
	local okAfter, after = pcall(Pricing.ComputeStoredValue, key, copy)
	if okBefore and okAfter and tonumber(before) and tonumber(after) then
		return after - before
	end
	return 0
end

function Wheels.Plan(car)
	local plan = {}
	local info = VehicleData[car:GetAttribute("VehicleName")]
	local defaults = type(info) == "table" and info or {}
	for _, slot in ipairs(Wheels.Slots) do
		local tire, tiresKnown = Wheels.Entry(car, "Tire", slot)
		local rim, rimsKnown = Wheels.Entry(car, "Rim", slot)
		local entry = { Slot = slot }
		if tiresKnown and not Wheels.Installed(car, slot) then
			entry.Missing, entry.Tire, entry.Rim = true, true, true
		elseif State.FixWheels then
			if tire and (tonumber(tire.Wear) or 0) >= State.WheelMinWear and Wheels.Gain(car, "Tire", slot) > Wheels.Price("Tire", tire.Variant) + Wheels.Margin then
				entry.Tire = true
			end
			if rimsKnown and (not rim or rim.Variant == "" or ((tonumber(rim.Wear) or 0) >= State.WheelMinWear and Wheels.Gain(car, "Rim", slot) > Wheels.Price("Rim", rim.Variant) + Wheels.Margin)) then
				entry.Rim = true
			end
		end
		if entry.Tire or entry.Rim then
			entry.TireVariant = tire and tire.Variant ~= "" and tire.Variant or (type(defaults.Tires) == "table" and defaults.Tires.Default) or nil
			entry.RimVariant = rim and rim.Variant ~= "" and rim.Variant or (type(defaults.Rims) == "table" and defaults.Rims.Default) or nil
			table.insert(plan, entry)
		end
	end
	return plan
end

function Wheels.Inside(machine, item)
	local hitbox = machine:FindFirstChild("Hitbox")
	local position = item and item.Parent and Parts.Position(item)
	if not (hitbox and hitbox:IsA("BasePart") and position) then
		return false
	end
	local relative = hitbox.CFrame:PointToObjectSpace(position)
	local half = hitbox.Size / 2 + Vector3.new(0.3, 0.8, 0.3)
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

function Wheels.Foreign(machine)
	local folder = Workspace:FindFirstChild("ExtractedCarParts")
	for _, item in ipairs(folder and folder:GetChildren() or {}) do
		if not Wheels.Mine(item) and Wheels.Inside(machine, item) then
			return true
		end
	end
	return false
end

function Wheels.Machine(position, radius)
	local best, bestDistance
	for _, machine in ipairs(CollectionService:GetTagged(Wheels.MachineTag)) do
		if machine:IsA("Model") and machine:IsDescendantOf(Workspace) and machine:GetAttribute("Occupied") ~= true then
			local hitbox = machine:FindFirstChild("Hitbox")
			local spot = hitbox and hitbox:IsA("BasePart") and hitbox.Position or machine:GetPivot().Position
			local distance = (spot - position).Magnitude
			if distance <= radius and (not bestDistance or distance < bestDistance) and not Wheels.Foreign(machine) then
				best, bestDistance = machine, distance
			end
		end
	end
	return best
end

function Wheels.ShopSpot()
	for _, item in ipairs(CollectionService:GetTagged("TireZone")) do
		if item:IsA("Attachment") and item:IsDescendantOf(Workspace) then
			return item.WorldPosition
		end
	end
	return nil
end

function Wheels.FindLift(car)
	local anchor = Wheels.ShopSpot() or car:GetPivot().Position
	local best, bestDistance
	for _, lift in ipairs(CollectionService:GetTagged(LiftTag)) do
		if lift:IsA("Model") and lift:IsDescendantOf(Workspace) and lift:FindFirstChild("Up") and lift:FindFirstChild("Down") then
			local position = lift:GetPivot().Position
			local blocked = lift:GetAttribute("BlockedByUserId")
			local free = lift:GetAttribute("Occupied") ~= true and (blocked == nil or blocked == LocalPlayer.UserId)
			if position.Y > 0 and free and Wheels.Machine(position, 40) and not Machines.LiftBusy(lift, car) then
				local distance = (position - anchor).Magnitude
				if not bestDistance or distance < bestDistance then
					best, bestDistance = lift, distance
				end
			end
		end
	end
	return best
end

function Wheels.CurrentLift(car)
	local lift, entrance = Repair.NearLift(car)
	if lift and Wheels.Machine(lift:GetPivot().Position, 40) then
		return lift, entrance
	end
	return nil
end

function Wheels.Press(part, prompt)
	if not (part and prompt) then
		return false
	end
	if Move.Distance(part.Position) > 3.5 then
		Move.WalkTo(part.Position, 3)
	end
	Status.Message = "-"
	if type(fireproximityprompt) == "function" and pcall(fireproximityprompt, prompt) then
		return true
	end
	return Seller.Trigger(prompt)
end

function Wheels.Control(lift, name)
	local part = lift and lift:FindFirstChild(name)
	return part, part and part:FindFirstChildWhichIsA("ProximityPrompt", true)
end

function Wheels.Raise(car, lift)
	local part, prompt = Wheels.Control(lift, "Up")
	for _ = 1, 3 do
		checkpoint()
		if car.PrimaryPart and car.PrimaryPart.Anchored then
			return true
		end
		if not prompt then
			return false
		end
		setStatus("Raising the lift")
		Wheels.Press(part, prompt)
		if waitFor(function()
			return car.PrimaryPart and car.PrimaryPart.Anchored
		end, 2.5) then
			sleep(0.3)
			return true
		end
	end
	return car.PrimaryPart ~= nil and car.PrimaryPart.Anchored
end

function Wheels.Lower(car, lift)
	local part, prompt = Wheels.Control(lift, "Down")
	if not prompt then
		return
	end
	for _ = 1, 8 do
		checkpoint()
		local height = tonumber(lift:GetAttribute("LiftHeight")) or 0
		if height <= 0 then
			break
		end
		setStatus("Lowering the lift")
		Wheels.Press(part, prompt)
		waitFor(function()
			return (tonumber(lift:GetAttribute("LiftHeight")) or 0) < height
		end, 2.5)
	end
	waitFor(function()
		return not (car.PrimaryPart and car.PrimaryPart.Anchored)
	end, 5)
end

function Wheels.Unlift(car)
	if not (car and car.Parent and car.PrimaryPart and car.PrimaryPart.Anchored) then
		return
	end
	local lift = Repair.NearLift(car)
	if lift then
		Wheels.Lower(car, lift)
	end
end

function Wheels.Park(car)
	local lift, entrance = Wheels.CurrentLift(car)
	if not lift then
		Wheels.Unlift(car)
		local started = os.clock()
		repeat
			lift = Wheels.FindLift(car)
			if not lift then
				setStatus("Waiting for a tire shop lift")
				sleep(3)
			end
		until lift or os.clock() - started > 45
		if not lift then
			error("No free lift at the tire shop", 0)
		end
		local center
		center, entrance = Machines.LiftLayout(lift)
		setStatus("Teleporting to tire shop", (Car.Name(car)))
		local ok, reason = Move.Drive(car, center, nil, nil, -entrance)
		if not ok then
			error("Teleport to tire shop failed: " .. tostring(reason), 0)
		end
		sleep(0.6)
	end
	local humanoid = getHumanoid()
	if humanoid and humanoid.SeatPart then
		setStatus("Leaving the car")
		if not Move.ExitCar(car, entrance) then
			error("Could not leave the car", 0)
		end
	end
	return lift
end

function Wheels.Carry(target, zone, options)
	options = options or {}
	for _ = 1, 2 do
		checkpoint()
		if not target.Parent then
			return false
		end
		local position = Parts.Position(target)
		if position and Move.Distance(position) > 3.5 then
			Move.WalkTo(position, 2.5)
		end
		if Parts.Grab(target) then
			local saved = {}
			if target:IsA("BasePart") then
				saved[target] = target.CanCollide
			end
			for _, item in ipairs(target:GetDescendants()) do
				if item:IsA("BasePart") then
					saved[item] = item.CanCollide
				end
			end
			for item in pairs(saved) do
				item.CanCollide = false
			end
			local ok, err = pcall(function()
				Carry.Goal = (Parts.Position(target) or zone) + Vector3.new(0, options.Height or 3, 0)
				sleep(0.25)
				Carry.Goal = nil
				Carry.Height = options.Height or 3
				local root = getRoot()
				local here = root and root.Position or zone
				local stand = options.StandAt or (zone + unit(flat(here - zone), Vector3.new(1, 0, 0)) * (options.Stand or 3.5))
				Move.WalkTo(Vector3.new(stand.X, here.Y, stand.Z), 1.5)
				Carry.Height = nil
				if options.Above then
					Carry.Goal = zone + Vector3.new(0, options.Above, 0)
					waitFor(function()
						local current = Parts.Position(target)
						return current ~= nil and (current - Carry.Goal).Magnitude < 1
					end, 2)
				end
				Carry.Goal = zone + (options.Offset or Vector3.zero)
				waitFor(function()
					local current = Parts.Position(target)
					return current ~= nil and (current - Carry.Goal).Magnitude < (options.Tolerance or 0.8)
				end, 2)
				if options.Action then
					options.Action(target)
				end
			end)
			Carry.Height = nil
			for item, value in pairs(saved) do
				if item.Parent then
					item.CanCollide = value
				end
			end
			task.wait(0.15)
			Parts.Release()
			if not ok then
				error(err, 0)
			end
			return true
		end
		sleep(0.4)
	end
	return false
end

function Wheels.PlaceOn(machine, item)
	local hitbox = machine:FindFirstChild("Hitbox")
	if not (hitbox and hitbox:IsA("BasePart")) then
		return false
	end
	for _ = 1, 3 do
		checkpoint()
		if not item.Parent then
			return false
		end
		if Wheels.Inside(machine, item) then
			return true
		end
		Wheels.Carry(item, hitbox.Position, { Above = 2.5, Offset = Vector3.new(0, 0.4, 0) })
		sleep(0.25)
	end
	return Wheels.Inside(machine, item)
end

function Wheels.Trash(item)
	if not (item and item.Parent) then
		return true
	end
	local position = Parts.Position(item) or Vector3.zero
	local bin, binDistance
	for _, part in ipairs(CollectionService:GetTagged("Garbage")) do
		if part:IsA("BasePart") and part:IsDescendantOf(Workspace) then
			local distance = (part.Position - position).Magnitude
			if not binDistance or distance < binDistance then
				bin, binDistance = part, distance
			end
		end
	end
	if not bin or binDistance > 200 then
		return false
	end
	setStatus("Throwing away", tostring(item:GetAttribute("CarPartName") or item.Name))
	for _ = 1, 2 do
		checkpoint()
		Wheels.Carry(item, bin.Position, { Above = 3, Offset = Vector3.new(0, 0.5, 0), Tolerance = 1.5, Action = function(target)
			task.wait(0.3)
			Hub.Fire(Net.ThrowCarPartRequested, target)
		end })
		if waitFor(function()
			return not item.Parent
		end, 2.5) then
			return true
		end
	end
	return not item.Parent
end

function Wheels.Displays(kind)
	local list = {}
	for _, item in ipairs(CollectionService:GetTagged("BuyCarPart")) do
		local variant = item:GetAttribute("BuyCarPartVariant")
		if item:IsDescendantOf(Workspace) and type(variant) == "string" and slotOfPartName(variant) == kind then
			table.insert(list, item)
		end
	end
	return list
end

function Wheels.Buy(kind, variant, count)
	local displays = Wheels.Displays(kind)
	if #displays == 0 then
		local spot = Wheels.ShopSpot()
		if spot then
			Move.Stream(spot)
		end
		displays = Wheels.Displays(kind)
	end
	if #displays == 0 then
		return nil, "Tire shop not found"
	end
	local root = getRoot()
	local here = root and root.Position or Vector3.zero
	table.sort(displays, function(a, b)
		local aMatch = a:GetAttribute("BuyCarPartVariant") == variant
		local bMatch = b:GetAttribute("BuyCarPartVariant") == variant
		if aMatch ~= bMatch then
			return aMatch
		end
		return ((Parts.Position(a) or here) - here).Magnitude < ((Parts.Position(b) or here) - here).Magnitude
	end)
	local display = displays[1]
	local name = display:GetAttribute("BuyCarPartVariant")
	local price = tonumber(display:GetAttribute("BuyCarPartPrice")) or Wheels.Price(kind, name)
	count = math.clamp(count, 1, Wheels.MaxBuy)
	if getMoney() < price * count + Filter.Reserve then
		return nil, "Not enough money"
	end
	setStatus("Buying " .. string.lower(kind) .. (count > 1 and "s" or ""), tostring(count) .. "x " .. formatMoney(price))
	local position = Parts.Position(display)
	if position then
		Move.WalkTo(position, 5)
	end
	local before = Wheels.Snapshot()
	Status.Message = "-"
	Hub.Fire(Net.BuyCarPartRequested, display, count)
	local parts = waitFor(function()
		local list = {}
		for _, item in ipairs(Wheels.Loose(kind)) do
			if not before[item] then
				table.insert(list, item)
			end
		end
		return #list >= count and list or nil
	end, 5)
	if not parts then
		return nil, Status.Message
	end
	Wheels.Bought[kind] = name
	Stats.WheelSpent = Stats.WheelSpent + price * count
	return parts
end

function Wheels.FromInventory(kind, variants, any)
	local profile = getProfile()
	local inventory = profile and profile.Inventory
	local items = type(inventory) == "table" and inventory.CarParts
	if type(items) ~= "table" then
		return nil
	end
	local fallback
	for id, item in pairs(items) do
		if type(item) == "table" and type(item.PartName) == "string" and slotOfPartName(item.PartName) == kind and (tonumber(item.Wear) or 0) < State.WheelMinWear then
			if variants[item.PartName] then
				return id
			end
			fallback = fallback or id
		end
	end
	return any and fallback or nil
end

function Wheels.Take(kind, variant, stock, any)
	local list = stock[kind]
	while list and #list > 0 do
		local item = table.remove(list, 1)
		if item.Parent and Wheels.Mine(item) then
			return item
		end
	end
	local variants = {}
	if variant then
		variants[variant] = true
	end
	if Wheels.Bought[kind] then
		variants[Wheels.Bought[kind]] = true
	end
	local id = Wheels.FromInventory(kind, variants, any)
	if id then
		local before = Wheels.Snapshot()
		setStatus("Taking part from inventory", kind)
		Hub.Fire(Net.SpawnCarPartFromInventoryRequested, id)
		local item = waitFor(function()
			return Wheels.Fresh(kind, before)
		end, 4)
		if item then
			return item
		end
	end
	local bought = Wheels.Buy(kind, variant, 1)
	return bought and bought[1] or nil
end

function Wheels.Removed(car, slot)
	local key = car:GetAttribute("VehicleName")
	for _, item in ipairs(Wheels.Loose("Tire")) do
		local source = item:GetAttribute("SourceVehicleName")
		if item:GetAttribute("Slot") == slot and (source == nil or source == key) then
			return item
		end
	end
	return nil
end

function Wheels.Extract(car, slot)
	local existing = Wheels.Removed(car, slot)
	if existing then
		return existing
	end
	local tire = type(VehicleModel) == "table" and type(VehicleModel.GetInstalledTire) == "function" and VehicleModel.GetInstalledTire(car, slot)
	local position = tire and tire:GetPivot().Position or car:GetPivot().Position
	if Move.Distance(position) > 5 then
		Move.WalkTo(position, 3)
	end
	Repair.EquipWrench()
	setStatus("Removing wheel", slot)
	local wheel
	for _ = 1, 2 do
		checkpoint()
		Hub.Fire(Net.WrenchExtractRequested, car, slot)
		wheel = waitFor(function()
			return Wheels.Removed(car, slot)
		end, 2.5)
		if wheel then
			break
		end
	end
	Repair.Unequip()
	return wheel
end

function Wheels.Separate(machine, wheel)
	local button, prompt = Wheels.Control(machine, "Button")
	if not prompt then
		return nil
	end
	for _ = 1, 3 do
		checkpoint()
		if not Wheels.PlaceOn(machine, wheel) then
			return nil
		end
		local before = Wheels.Snapshot()
		setStatus("Separating tire and rim")
		Wheels.Press(button, prompt)
		local rim = waitFor(function()
			if Wheels.HasRim(wheel) then
				return nil
			end
			return Wheels.Fresh("Rim", before)
		end, 3)
		if rim then
			return rim
		end
	end
	return nil
end

function Wheels.Assemble(machine, tire, rim)
	local button, prompt = Wheels.Control(machine, "Button")
	if not prompt then
		return false
	end
	for _ = 1, 3 do
		checkpoint()
		if not (tire.Parent and rim.Parent) then
			return false
		end
		Wheels.PlaceOn(machine, rim)
		Wheels.PlaceOn(machine, tire)
		if not Wheels.Inside(machine, rim) then
			Wheels.PlaceOn(machine, rim)
		end
		setStatus("Assembling wheel")
		Wheels.Press(button, prompt)
		waitFor(function()
			return Minigame.FrameOpen("WheelSlider") or Wheels.HasRim(tire)
		end, 3)
		if Minigame.FrameOpen("WheelSlider") then
			Minigame.CloseFrame("WheelSlider", { "Buttons", "Set" })
		end
		local done = waitFor(function()
			return Wheels.HasRim(tire)
		end, 3)
		local root = getRoot()
		if root and root.Anchored then
			root.Anchored = false
		end
		if done then
			return true
		end
	end
	return false
end

function Wheels.Hitbox(car, slot)
	if type(VehicleModel) == "table" and type(VehicleModel.GetHitbox) == "function" then
		local ok, hitbox = pcall(VehicleModel.GetHitbox, car, slot)
		if ok and hitbox then
			return hitbox
		end
	end
	local primary = car.PrimaryPart
	local folder = primary and primary:FindFirstChild("Hitboxes")
	return folder and folder:FindFirstChild(slot)
end

function Wheels.Install(car, slot, wheel)
	local hitbox = Wheels.Hitbox(car, slot)
	if not (hitbox and hitbox:IsA("BasePart")) then
		return false
	end
	setStatus("Installing wheel", slot)
	for _ = 1, 3 do
		checkpoint()
		if Wheels.Installed(car, slot) then
			return true
		end
		if not wheel.Parent then
			return false
		end
		Wheels.Carry(wheel, hitbox.Position, { Stand = 4, Tolerance = 1, Action = function(target)
			Hub.Fire(Net.DropCarPartRequested, target)
			task.wait(0.15)
		end })
		if waitFor(function()
			return Wheels.Installed(car, slot)
		end, 3) then
			return true
		end
	end
	return Wheels.Installed(car, slot)
end

function Wheels.Swap(car, entry, lift, stock)
	local slot = entry.Slot
	local machine = Wheels.Machine(lift:GetPivot().Position, 40)
	if not machine then
		error("No free wheel machine", 0)
	end
	local tire, rim
	local wheel
	if entry.Missing then
		wheel = Wheels.Removed(car, slot)
		if wheel and Wheels.HasRim(wheel) then
			if Wheels.Install(car, slot, wheel) then
				Stats.Wheels = Stats.Wheels + 1
				return true
			end
			error("Could not install the " .. slot .. " wheel", 0)
		end
		tire = wheel
	else
		wheel = Wheels.Extract(car, slot)
		if not wheel then
			error("Could not remove the " .. slot .. " wheel", 0)
		end
		if entry.Tire and entry.Rim then
			Wheels.Trash(wheel)
		else
			tire = wheel
			if Wheels.HasRim(wheel) then
				rim = Wheels.Separate(machine, wheel)
				if not rim then
					error("Could not separate the " .. slot .. " wheel", 0)
				end
			end
			if entry.Rim and rim then
				Wheels.Trash(rim)
				rim = nil
			end
			if entry.Tire then
				Wheels.Trash(tire)
				tire = nil
			end
		end
	end
	tire = tire or Wheels.Take("Tire", entry.TireVariant, stock, entry.Missing)
	rim = rim or Wheels.Take("Rim", entry.RimVariant, stock, entry.Missing)
	if not (tire and rim) then
		error("No parts for the " .. slot .. " wheel", 0)
	end
	if not Wheels.Assemble(machine, tire, rim) then
		error("Could not assemble the " .. slot .. " wheel", 0)
	end
	if not Wheels.Install(car, slot, tire) then
		error("Could not install the " .. slot .. " wheel", 0)
	end
	Stats.Wheels = Stats.Wheels + 1
	return true
end

function Wheels.Finish(car, lift, stock)
	for _ = 1, 2 do
		local missing = {}
		for _, entry in ipairs(Wheels.Plan(car)) do
			if entry.Missing then
				table.insert(missing, entry)
			end
		end
		if #missing == 0 then
			break
		end
		for _, entry in ipairs(missing) do
			local ok, err = pcall(Wheels.Swap, car, entry, lift, stock)
			if not ok then
				if err == "JobCancelled" then
					error(err, 0)
				end
				setStatus("Wheel failed", entry.Slot .. ": " .. tostring(err))
			end
		end
	end
	Wheels.Lower(car, lift)
end

function Wheels.Run(car)
	local plan = Wheels.Plan(car)
	if #plan == 0 then
		return true
	end
	local id = car:GetAttribute("GarageVehicleId") or car:GetAttribute("VehicleName") or "car"
	Wheels.Attempts[id] = (Wheels.Attempts[id] or 0) + 1
	local cost, orders = 0, {}
	for _, entry in ipairs(plan) do
		for _, kind in ipairs({ "Tire", "Rim" }) do
			if entry[kind] then
				local variant = entry[kind .. "Variant"]
				cost = cost + Wheels.Price(kind, variant)
				local key = kind .. "|" .. tostring(variant)
				orders[key] = orders[key] or { Kind = kind, Variant = variant, Count = 0 }
				orders[key].Count = orders[key].Count + 1
			end
		end
	end
	if getMoney() < cost + Filter.Reserve then
		setStatus("Wheels skipped", "Not enough money")
		return false
	end
	local lift = Wheels.Park(car)
	local stock = { Tire = {}, Rim = {} }
	for _, order in pairs(orders) do
		local parts = Wheels.Buy(order.Kind, order.Variant, order.Count)
		for _, item in ipairs(parts or {}) do
			table.insert(stock[order.Kind], item)
		end
	end
	if not Wheels.Raise(car, lift) then
		error("Could not raise the lift", 0)
	end
	local failed = 0
	for _, entry in ipairs(plan) do
		local ok, err = pcall(Wheels.Swap, car, entry, lift, stock)
		if not ok then
			if err == "JobCancelled" then
				error(err, 0)
			end
			failed = failed + 1
			setStatus("Wheel failed", entry.Slot .. ": " .. tostring(err))
		end
	end
	Wheels.Finish(car, lift, stock)
	return failed == 0
end

function Garage.Load()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then
		return
	end
	local ok, content = pcall(function()
		if isfile(Garage.File) then
			return readfile(Garage.File)
		end
		return nil
	end)
	if not ok or type(content) ~= "string" then
		return
	end
	local decoded, list = pcall(function()
		return HttpService:JSONDecode(content)
	end)
	if decoded and type(list) == "table" then
		for key, value in pairs(list) do
			if type(key) == "number" and type(value) == "string" then
				Garage.Owned[value] = true
			elseif type(key) == "string" then
				local paid = tonumber(value)
				Garage.Owned[key] = paid and paid > 0 and paid or true
			end
		end
	end
end

function Garage.Save()
	if type(writefile) ~= "function" then
		return
	end
	local map = {}
	for id, value in pairs(Garage.Owned) do
		map[id] = type(value) == "number" and value or 0
	end
	pcall(function()
		writefile(Garage.File, HttpService:JSONEncode(map))
	end)
end

function Garage.Mark(id, owned, paid)
	if type(id) ~= "string" then
		return
	end
	if owned then
		local known = Garage.Owned[id]
		Garage.Owned[id] = tonumber(paid) or (type(known) == "number" and known) or true
	else
		Garage.Owned[id] = nil
	end
	Garage.Save()
end

function Garage.Paid(id)
	local value = id and Garage.Owned[id]
	return type(value) == "number" and value or nil
end

function Garage.Slots()
	local list = type(GeneralData) == "table" and type(GeneralData.Garages) == "table" and GeneralData.Garages.Slots
	if type(list) ~= "table" then
		return math.huge
	end
	local function size(name)
		local info = list[name]
		return type(info) == "table" and tonumber(info.Slots) or 0
	end
	local total = size("Default")
	local profile = getProfile()
	local garage = profile and profile.Garage
	local owned = type(garage) == "table" and garage.OwnedGarages
	if type(owned) == "table" then
		for key, value in pairs(owned) do
			local name = type(key) == "string" and key or value
			if type(name) == "string" and name ~= "Default" and value then
				total = total + size(name)
			end
		end
	end
	return total > 0 and total or math.huge
end

function Garage.Count()
	local profile = getProfile()
	local garage = profile and profile.Garage
	local vehicles = type(garage) == "table" and garage.Vehicles
	local count = 0
	if type(vehicles) == "table" then
		for _ in pairs(vehicles) do
			count = count + 1
		end
	end
	return count
end

function Garage.Full()
	return Garage.Count() >= Garage.Slots()
end

function Garage.NeedsWork(id)
	local profile = getProfile()
	local garage = profile and profile.Garage
	local vehicles = type(garage) == "table" and garage.Vehicles
	local record = type(vehicles) == "table" and vehicles[id]
	if type(record) ~= "table" then
		return false
	end
	local groups = type(CarPartsData) == "table" and CarPartsData.Groups
	for slot, info in pairs(type(record.CarParts) == "table" and record.CarParts or {}) do
		if type(info) == "table" then
			local group = type(groups) == "table" and groups[slot]
			if info.Variant == "" then
				if not (type(group) == "table" and group.Optional == true) then
					return true
				end
			else
				local kind = Parts.Kind(slot)
				if kind and Parts.Enabled(kind) and (tonumber(info.Wear) or 0) > State.MinWear then
					return true
				end
			end
		end
	end
	for _, slot in ipairs(Wheels.Slots) do
		local tire = type(record.Tires) == "table" and record.Tires[slot]
		local rim = type(record.Rims) == "table" and record.Rims[slot]
		if type(record.Tires) == "table" and (type(tire) ~= "table" or tire.Variant == "") then
			return true
		end
		if State.FixWheels and ((type(tire) == "table" and (tonumber(tire.Wear) or 0) >= State.WheelMinWear) or (type(rim) == "table" and (tonumber(rim.Wear) or 0) >= State.WheelMinWear)) then
			return true
		end
	end
	return State.Paint and type(record.Paint) == "table" and record.Paint.Rusty == true
end

function Garage.Workable()
	local list = {}
	for _, entry in ipairs(Garage.Stored(true)) do
		local id = entry.Id
		local mine = Garage.Owned[id] or State.UseAllGarageCars
		local sell = State.AutoSell and Farm.Allowed("Sell", id) and (mine or Farm.Pick.Sell[id])
		local repair = State.AutoRepair and Farm.Allowed("Repair", id) and (mine or Farm.Pick.Repair[id]) and not Farm.Done[id] and Garage.NeedsWork(id)
		if sell or repair then
			table.insert(list, entry)
		end
	end
	return list
end

function Garage.Label(id, info)
	local data = VehicleData[info.VehicleName]
	local name = type(data) == "table" and tostring(data.DisplayName or info.VehicleName) or tostring(info.VehicleName)
	return name .. " #" .. tostring(string.match(id, "(%d+)$") or id)
end

function Garage.Options()
	local list, byLabel = {}, {}
	local profile = getProfile()
	local garage = profile and profile.Garage
	local vehicles = type(garage) == "table" and garage.Vehicles
	if type(vehicles) ~= "table" then
		return list, byLabel, false
	end
	for id, info in pairs(vehicles) do
		if type(info) == "table" then
			local label = Garage.Label(id, info)
			byLabel[label] = id
			table.insert(list, label)
		end
	end
	table.sort(list)
	return list, byLabel, true
end

function Garage.Stored(all)
	local list = {}
	local profile = getProfile()
	local garage = profile and profile.Garage
	local vehicles = type(garage) == "table" and garage.Vehicles
	if type(vehicles) ~= "table" then
		return list
	end
	local spawned = Car.Get()
	local spawnedId = spawned and spawned:GetAttribute("GarageVehicleId")
	for id, info in pairs(vehicles) do
		if id ~= spawnedId and type(info) == "table" and (all or Garage.Owned[id] or State.UseAllGarageCars) then
			table.insert(list, { Id = id, Key = info.VehicleName, Garage = type(info.Garage) == "string" and info.Garage or "Default" })
		end
	end
	return list
end

function Garage.TakeOut(entry)
	Move.Unseat()
	local info = VehicleData[entry.Key]
	local name = type(info) == "table" and tostring(info.DisplayName or entry.Key) or tostring(entry.Key)
	if LocalPlayer:GetAttribute("InGarage") ~= true then
		setStatus("Going to garage", entry.Garage)
		Move.QuickTravel("Garage_" .. tostring(entry.Garage))
		waitFor(function()
			return LocalPlayer:GetAttribute("InGarage") == true
		end, 8)
	end
	local display = waitFor(function()
		local folder = Workspace:FindFirstChild("Vehicles")
		for _, model in ipairs(folder and folder:GetChildren() or {}) do
			if model:IsA("Model") and model:GetAttribute("GarageVehicleId") == entry.Id and model:GetAttribute("IsGarageDisplayVehicle") == true then
				return model
			end
		end
		return nil
	end, 8)
	if display then
		Move.WalkTo(display:GetPivot().Position, 7, 20)
	end
	setStatus("Taking car out of garage", name)
	local car
	for _ = 1, 3 do
		checkpoint()
		Hub.Fire(Net.RequestDriveVehiclePrompt, entry.Id)
		car = waitFor(function()
			local current = Car.Get()
			return current and current:GetAttribute("GarageVehicleId") == entry.Id and current or nil
		end, 6)
		if car then
			break
		end
	end
	if car then
		Farm.Current = { Id = entry.Id, Key = entry.Key, Display = name, Paid = Garage.Paid(entry.Id), Started = os.clock() }
	end
	return car
end

Garage.Load()

function Farm.LoadFavorites()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then
		return
	end
	local ok, content = pcall(function()
		if isfile(Farm.FavoritesFile) then
			return readfile(Farm.FavoritesFile)
		end
		return nil
	end)
	if not ok or type(content) ~= "string" then
		return
	end
	local decoded, list = pcall(function()
		return HttpService:JSONDecode(content)
	end)
	if decoded and type(list) == "table" then
		for _, id in ipairs(list) do
			if type(id) == "string" then
				Farm.Favorites[id] = true
			end
		end
	end
end

function Farm.SaveFavorites()
	if type(writefile) ~= "function" then
		return
	end
	local list = {}
	for id in pairs(Farm.Favorites) do
		table.insert(list, id)
	end
	pcall(function()
		writefile(Farm.FavoritesFile, HttpService:JSONEncode(list))
	end)
end

function Farm.Forget(id)
	if not id then
		return
	end
	for _, kind in ipairs({ "Repair", "Sell" }) do
		local set = Farm.Pick[kind]
		if set[id] then
			set[id] = nil
			if not next(set) and Farm.Hooks.PickDone then
				Farm.Hooks.PickDone(kind)
			end
		end
	end
end

function Farm.Targets(kind)
	local list = {}
	local current = Car.Get()
	local currentId = current and current:GetAttribute("GarageVehicleId")
	local profile = getProfile()
	local garage = profile and profile.Garage
	local vehicles = type(garage) == "table" and garage.Vehicles or {}
	for id in pairs(Farm.Pick[kind]) do
		local info = vehicles[id]
		if type(info) == "table" and not (kind == "Sell" and Farm.Favorites[id]) then
			table.insert(list, { Id = id, Key = info.VehicleName, Garage = type(info.Garage) == "string" and info.Garage or "Default", Current = id == currentId })
		end
	end
	table.sort(list, function(a, b)
		return a.Current and not b.Current
	end)
	return list
end

function Farm.Each(kind, action)
	local targets = Farm.Targets(kind)
	if #targets == 0 then
		local car = Car.Get()
		if not car then
			error("No car out of the garage", 0)
		end
		if kind == "Sell" and Farm.Favorites[car:GetAttribute("GarageVehicleId") or ""] then
			error("This car is in Favorite Cars", 0)
		end
		action(car)
		return
	end
	for _, entry in ipairs(targets) do
		checkpoint()
		local car = Car.Get()
		if not (car and car:GetAttribute("GarageVehicleId") == entry.Id) then
			car = Garage.TakeOut(entry)
		end
		if car then
			action(car)
		end
	end
end

function Farm.Allowed(kind, id)
	if kind == "Sell" and id and Farm.Favorites[id] then
		return false
	end
	local set = Farm.Pick[kind]
	if type(set) == "table" and next(set) then
		return id ~= nil and set[id] == true
	end
	return true
end

Farm.LoadFavorites()

function Farm.RecordSale(amount)
	Stats.Sold = Stats.Sold + 1
	Stats.Earned = Stats.Earned + amount
	local current = Farm.Current
	local sale = { Amount = amount }
	if current then
		Stats.LastCar = current.Display
		if current.Paid then
			local profit = amount - current.Paid
			Stats.LastProfit = profit
			if not Stats.BestProfit or profit > Stats.BestProfit then
				Stats.BestProfit = profit
			end
		else
			Stats.LastProfit = nil
		end
		local duration = os.clock() - (current.Started or os.clock())
		Stats.Cycles = Stats.Cycles + 1
		Stats.CycleTime = Stats.CycleTime + duration
		sale.Display, sale.Key, sale.Paid, sale.Profit, sale.Duration = current.Display, current.Key, current.Paid, Stats.LastProfit, duration
	else
		Stats.LastCar = "Car"
		Stats.LastProfit = nil
	end
	Farm.Current = nil
	if Farm.Hooks.Sold then
		pcall(Farm.Hooks.Sold, sale)
	end
end

function Farm.Yards()
	local list = {}
	for _, entry in ipairs(JunkyardList) do
		if (not next(Filter.Junkyards) or Filter.Junkyards[entry.Grade]) and junkyardUnlocked(entry.Grade) then
			table.insert(list, entry.Grade)
		end
	end
	return list
end

function Farm.TravelTo(grade)
	local info = junkyardInfo(grade)
	local center = junkyardCenter(grade)
	if not info or not center then
		return false
	end
	if Move.Distance(center) < 200 then
		return true
	end
	if not junkyardUnlocked(grade) then
		return false
	end
	Move.Unseat()
	if State.QuickTravel and info.Fee <= math.max(0, getMoney() - Filter.Reserve) then
		setStatus("Quick travel", info.Name)
		local ok = Move.QuickTravel("Junkyard_" .. tostring(grade))
		if ok then
			return true
		end
	end
	setStatus("Walking to junkyard", info.Name)
	return Move.WalkTo(center, 30, 120)
end

function Farm.BuyNext()
	for pass = 1, 3 do
		checkpoint()
		setStatus("Looking for cars")
		local entry = Shop.Candidates()[1]
		if entry then
			if entry.Distance > 180 and entry.Grade then
				Farm.TravelTo(entry.Grade)
			end
			local ok, reason = Shop.Buy(entry)
			if ok then
				return true
			end
			if reason == "GarageFull" then
				Farm.GarageFull()
				return false
			end
			setStatus("Buy failed", entry.Display .. ": " .. tostring(reason))
			sleep(1)
		else
			local yards = Farm.Yards()
			if #yards == 0 then
				setStatus("No junkyard", "Check the junkyard filter")
				sleep(5)
				return false
			end
			Farm.YardIndex = Farm.YardIndex % #yards + 1
			if pass < 3 and Farm.TravelTo(yards[Farm.YardIndex]) then
				sleep(2.5)
			else
				setStatus("Waiting for cars", "Nothing matches the filters")
				sleep(8)
			end
		end
	end
	return false
end

function Farm.GarageFull()
	State.AutoBuy = false
	setStatus("Garage full", "Auto Buy turned off")
	if Farm.Hooks.GarageFull then
		Farm.Hooks.GarageFull()
	end
end

function Farm.Key(car)
	return car:GetAttribute("GarageVehicleId") or car:GetAttribute("VehicleName") or "car"
end

function Farm.NeedsRepair(car)
	local key = car:GetAttribute("VehicleName")
	if #Parts.Extracted(key) > 0 then
		return true
	end
	if (Repair.Attempts[Farm.Key(car)] or 0) >= 2 then
		return false
	end
	return #Parts.Worn(car) > 0
end

function Farm.Restored(car)
	local key = car:GetAttribute("VehicleName")
	if #Parts.Extracted(key) > 0 or #Car.MissingSlots(car) > 0 or Wheels.Incomplete(car) or #Parts.Worn(car) > 0 then
		return false
	end
	return not State.FixWheels or #Wheels.Plan(car) == 0
end

function Farm.Pending(car)
	local garageId = car:GetAttribute("GarageVehicleId")
	if State.AutoSell and Farm.Allowed("Sell", garageId) then
		return true
	end
	if not (State.AutoRepair and Farm.Allowed("Repair", garageId)) then
		return false
	end
	local id = Farm.Key(car)
	if Farm.Done[id] then
		return false
	end
	if Farm.NeedsRepair(car) or #Car.MissingSlots(car) > 0 or Wheels.Incomplete(car) then
		return true
	end
	if State.FixWheels and (Wheels.Attempts[id] or 0) < 2 and #Wheels.Plan(car) > 0 then
		return true
	end
	return State.Paint and car:GetAttribute("Painted") ~= true and (Farm.PaintTries[id] or 0) < 2
end

function Farm.PaintCar(car)
	local id = Farm.Key(car)
	Farm.PaintTries[id] = (Farm.PaintTries[id] or 0) + 1
	local ok, err = pcall(Paint.Run, car)
	if not ok then
		if err == "JobCancelled" then
			error(err, 0)
		end
		setStatus("Paint skipped", tostring(err))
	end
end

function Farm.Restore(car)
	local id = Farm.Key(car)
	local garageId = car:GetAttribute("GarageVehicleId")
	local function wanted()
		return State.AutoRepair and Farm.Allowed("Repair", garageId) or Job.Name ~= "Auto Farm"
	end
	if Farm.NeedsRepair(car) then
		Repair.Run(car)
	end
	checkpoint()
	if car.Parent and #Car.MissingSlots(car) > 0 then
		Farm.RecoverTries = (Farm.RecoverTries or 0) + 1
		Repair.Recover(car)
		local missing = Car.MissingSlots(car)
		if #missing > 0 and Farm.RecoverTries < 3 then
			error("Car is missing parts: " .. table.concat(missing, ", "), 0)
		end
	end
	Farm.RecoverTries = 0
	checkpoint()
	if car.Parent and (Wheels.Incomplete(car) or (wanted() and State.FixWheels and (Wheels.Attempts[id] or 0) < 2)) then
		local ok, err = pcall(Wheels.Run, car)
		if not ok then
			if err == "JobCancelled" then
				error(err, 0)
			end
			setStatus("Wheels skipped", tostring(err))
		end
		Wheels.Unlift(car)
		if Wheels.Incomplete(car) then
			error("Car is missing wheels", 0)
		end
	end
	checkpoint()
	if car.Parent and wanted() and State.Paint and car:GetAttribute("Painted") ~= true and (Farm.PaintTries[id] or 0) < 2 then
		Farm.PaintCar(car)
	end
end

function Farm.Active()
	return State.AutoBuy or State.AutoRepair or State.AutoSell
end

function Farm.Cycle()
	Seller.CheckLate()
	local car = Car.Get()
	local finished = false
	if car and not Farm.Pending(car) then
		if State.AutoRepair and Farm.Allowed("Repair", car:GetAttribute("GarageVehicleId")) then
			Farm.Done[Farm.Key(car)] = true
		end
		finished = true
		car = nil
	end
	if not car and State.UseGarage and (State.AutoRepair or State.AutoSell) then
		local entry = Garage.Workable()[1]
		if entry then
			car = Garage.TakeOut(entry)
		end
	end
	if not car then
		if not State.AutoBuy then
			setStatus("Idle", finished and "This car is done" or "No car to work on")
			sleep(3)
			return
		end
		if Garage.Full() then
			Farm.GarageFull()
			return
		end
		if not Farm.BuyNext() then
			return
		end
		car = waitFor(function()
			return Car.Get()
		end, 5)
		if not car then
			return
		end
	end
	local id = car:GetAttribute("GarageVehicleId")
	if not Farm.Current or Farm.Current.Id ~= id then
		local display, key = Car.Name(car)
		Farm.Current = { Id = id, Key = key, Display = display, Paid = Garage.Paid(id), Started = os.clock() }
	end
	checkpoint()
	if State.AutoRepair and Farm.Allowed("Repair", id) then
		Farm.Restore(car)
	end
	checkpoint()
	if State.AutoSell and Farm.Allowed("Sell", id) and car.Parent then
		if State.Paint and car:GetAttribute("Painted") ~= true and (Farm.PaintTries[Farm.Key(car)] or 0) < 2 and Farm.Restored(car) then
			Farm.PaintCar(car)
		end
		checkpoint()
		if State.AutoSell and Farm.Allowed("Sell", id) and car.Parent then
			Seller.Sell(car)
		end
	end
end

function Farm.Loop()
	Stats.StartMoney = Stats.StartMoney or getMoney()
	local failures = 0
	while true do
		checkpoint()
		if not Farm.Active() then
			return
		end
		local ok, err = pcall(Farm.Cycle)
		if ok then
			failures = 0
			sleep(0.5)
		else
			if err == "JobCancelled" then
				error(err, 0)
			end
			failures = failures + 1
			Stats.Errors = Stats.Errors + 1
			Parts.Release()
			setStatus("Recovering", tostring(err))
			if failures >= 5 then
				error("Stopped after 5 errors in a row: " .. tostring(err), 0)
			end
			sleep(3)
		end
	end
end

local UI = {}

function Job.Start(name, callback, guard)
	local run = Farm.Run
	task.spawn(function()
		if Job.Running then
			Job.Cancel = true
			local deadline = os.clock() + 6
			while Job.Running and os.clock() < deadline do
				task.wait(0.1)
			end
			if Job.Running then
				return
			end
		end
		if guard and not guard() then
			return
		end
		Job.Running = true
		Job.Cancel = false
		Job.Name = name
		local ok, err = pcall(callback)
		Job.Running = false
		Job.Name = nil
		Carry.Target = nil
		Carry.Goal = nil
		Carry.Height = nil
		pcall(Move.Sprint, false)
		local car = Car.Get()
		if car then
			pcall(Move.StopCar, car)
		end
		local humanoid, root = getHumanoid(), getRoot()
		if humanoid and root then
			pcall(function()
				humanoid:MoveTo(root.Position)
			end)
		end
		if ok then
			if name ~= "Auto Farm" then
				setStatus("Done", name)
			end
		elseif err == "JobCancelled" then
			setStatus("Stopped", name)
		else
			Stats.Errors = Stats.Errors + 1
			setStatus("Error", tostring(err))
			if UI.Notify then
				UI.Notify(name, tostring(err), "Error")
			end
			if Farm.Hooks.Stopped then
				pcall(Farm.Hooks.Stopped, name, tostring(err))
			end
		end
		if name == "Auto Farm" and Hub.Running and run == Farm.Run and (Farm.Active() or State.Farm) and UI.SetAuto then
			UI.SetAuto(false)
			UI.SyncFarm()
		end
	end)
end

function Job.Stop()
	if Job.Running then
		Job.Cancel = true
	end
end

function Hub.Debug(lines)
	local car = Car.Get()
	local log = {}
	for index = 1, math.min(#Status.Log, lines or 12) do
		log[index] = Status.Log[index]
	end
	return {
		Status = Status.Text .. (Status.Detail ~= "" and (" | " .. Status.Detail) or ""),
		Job = Job.Name,
		Farm = State.Farm,
		Auto = (State.AutoBuy and "B" or "-") .. (State.AutoRepair and "R" or "-") .. (State.AutoSell and "S" or "-"),
		Picks = (function()
			local function ids(set)
				local list = {}
				for id in pairs(set) do
					table.insert(list, id)
				end
				table.sort(list)
				return table.concat(list, ",")
			end
			return "repair[" .. ids(Farm.Pick.Repair) .. "] sell[" .. ids(Farm.Pick.Sell) .. "] fav[" .. ids(Farm.Favorites) .. "]"
		end)(),
		Garage = Garage.Count() .. "/" .. tostring(Garage.Slots()),
		Car = car and (tostring(car:GetAttribute("VehicleName")) .. " cond=" .. string.format("%.2f", Car.Condition(car) or -1)) or "none",
		Missing = car and table.concat(Car.MissingSlots(car), ",") or "",
		Money = math.floor(getMoney()),
		Stats = string.format("bought %d sold %d fixed %d wheels %d errors %d resets %d", Stats.Bought, Stats.Sold, Stats.Repaired, Stats.Wheels, Stats.Errors, Pace.Resets),
		Wheels = car and #Wheels.Plan(car) or 0,
		Reset = Pace.Last,
		Message = Status.Message,
		Npc = Status.Npc,
		Log = log,
	}
end

Hub.State = State
Hub.Filter = Filter
Hub.Stats = Stats
Hub.Garage = Garage
Hub.Internal = { Move = Move, Roads = Roads, Car = Car, Machines = Machines, Repair = Repair, Seller = Seller, Paint = Paint, Shop = Shop, Wheels = Wheels, Parts = Parts, Pace = Pace, Carry = Carry }

function Hub.SetFarm(value)
	if UI.FarmToggle then
		pcall(function()
			UI.FarmToggle:Set(value == true)
		end)
	end
end

function Hub.SetAuto(buy, repair, sell)
	local deadline = os.clock() + 20
	while not UI.ApplyAuto and os.clock() < deadline do
		task.wait(0.2)
	end
	if not UI.ApplyAuto then
		return false
	end
	State.AutoBuy, State.AutoRepair, State.AutoSell = buy == true, repair == true, sell == true
	UI.Syncing = true
	UI.SetToggle(UI.BuyToggle, State.AutoBuy)
	UI.SetToggle(UI.RepairToggle, State.AutoRepair)
	UI.SetToggle(UI.SellToggle, State.AutoSell)
	UI.Syncing = false
	UI.ApplyAuto()
end

function Hub.Pick(kind, ids)
	local dropdown = ({ Buy = UI.BuyCars, Repair = UI.RepairCars, Sell = UI.SellCars, Favorite = UI.FavoriteCars })[kind]
	if not dropdown then
		return false
	end
	local wanted, labels = {}, {}
	for _, id in ipairs(ids or {}) do
		wanted[id] = true
	end
	for label, id in pairs(kind == "Buy" and CarByLabel or UI.CarLabels) do
		if wanted[id] then
			table.insert(labels, label)
		end
	end
	dropdown:Set(labels)
	return labels
end

Hub.Tasks = {
	Repair = function()
		Job.Start("Repair", function()
			local car = Car.Get()
			if not car then
				error("No car out of the garage", 0)
			end
			Repair.Run(car)
			Repair.Recover(car)
		end)
	end,
	Paint = function()
		Job.Start("Paint", function()
			local car = Car.Get()
			if not car then
				error("No car out of the garage", 0)
			end
			if not Paint.Run(car) then
				error("Paint failed", 0)
			end
		end)
	end,
	Recover = function()
		Job.Start("Recover", function()
			local car = Car.Get()
			if not car then
				error("No car out of the garage", 0)
			end
			Repair.Recover(car)
		end)
	end,
	Wheels = function()
		Job.Start("Wheels", function()
			local car = Car.Get()
			if not car then
				error("No car out of the garage", 0)
			end
			Wheels.Run(car)
			Wheels.Unlift(car)
		end)
	end,
	Sell = function()
		Job.Start("Sell", function()
			local car = Car.Get()
			if not car then
				error("No car out of the garage", 0)
			end
			Seller.Sell(car)
		end)
	end,
	Buy = function()
		Job.Start("Buy", function()
			if Car.Get() then
				error("Sell your current car first", 0)
			end
			if not Farm.BuyNext() then
				error("No car was bought", 0)
			end
		end)
	end,
	Stop = function()
		if UI.SetAuto then
			UI.SetAuto(false)
			UI.SyncFarm()
		end
		State.Farm = false
		Job.Stop()
	end,
}

local function stopAll()
	State.Farm = false
	for _, toggle in ipairs(Hub.Toggles) do
		pcall(function()
			toggle:Set(false)
		end)
	end
	Job.Stop()
end

table.insert(Hub.Connections, LocalPlayer.Idled:Connect(function()
	if not State.AntiAfk then
		return
	end
	pcall(function()
		local virtualUser = game:GetService("VirtualUser")
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end)
end))

function Hub.Unload()
	if not Hub.Running then
		return
	end
	Job.Cancel = true
	State.Farm = false
	Hub.Running = false
	if Carry.Target then
		Carry.Target = nil
		pcall(Net.DragReleaseRequested.Fire)
	end
	for _, connection in ipairs(Hub.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(Hub.Connections)
	for _, cleanup in ipairs(Hub.Cleanups) do
		pcall(function()
			if type(cleanup) == "function" then
				cleanup()
			elseif typeof(cleanup) == "RBXScriptConnection" then
				cleanup:Disconnect()
			elseif type(cleanup) == "table" and type(cleanup.Disconnect) == "function" then
				cleanup:Disconnect()
			end
		end)
	end
	table.clear(Hub.Cleanups)
	if Hub.Window then
		pcall(function()
			Hub.Window:Destroy()
		end)
	end
	if Environment.JunkMechanicsHub == Hub then
		Environment.JunkMechanicsHub = nil
	end
end

local Airflow = loadstring(game:HttpGet(LibraryUrl))()

local WindowTitle = "Junk Mechanics"

local Window = Airflow:CreateWindow({
	Name = WindowTitle,
	Icon = "car",
	ToggleUIKeybind = "RightControl",
	OpenButton = { Title = WindowTitle, Icon = "car" },
	KeepOnScreen = true,
	Loading = {
		Enabled = true,
		Title = WindowTitle,
		Text = "Starting",
		Duration = 1.2,
	},
})
Hub.Window = Window

function UI.Notify(title, content, kind)
	pcall(function()
		Window:Notify({
			Title = title,
			Content = content,
			Type = kind or "Info",
			Duration = 4,
		})
	end)
end

local function asList(selection)
	if type(selection) == "table" then
		return selection
	end
	if type(selection) == "string" and selection ~= "" then
		return { selection }
	end
	return {}
end

local function live(tab, getter, rate)
	local function text()
		local ok, value = pcall(getter)
		if ok then
			return tostring(value)
		end
		return "-"
	end
	return tab:CreateLabel({
		Text = text(),
		UpdateRate = rate or 0.5,
		Update = text,
	})
end

local function signedMoney(value)
	if value >= 0 then
		return "+" .. formatMoney(value)
	end
	return formatMoney(value)
end

local Webhook = {
	File = "JunkMechanics_webhook.json",
	Settings = {
		Url = "",
		Enabled = true,
		Stats = true,
		Interval = 10,
		Sales = true,
		Purchases = false,
		Alerts = true,
		Spawns = true,
		Bought = true,
		Ping = false,
		Cars = {},
	},
	Cars = {},
	Queue = {},
	Images = {},
	Sent = 0,
	Failed = 0,
	Colors = {
		Info = 0x5865F2,
		Sale = 0x57F287,
		Loss = 0xED4245,
		Buy = 0x3498DB,
		Warning = 0xE67E22,
		Highlight = 0xFFC450,
	},
	Request = (type(request) == "function" and request)
		or (type(http_request) == "function" and http_request)
		or (type(syn) == "table" and type(syn.request) == "function" and syn.request)
		or (type(http) == "table" and type(http.request) == "function" and http.request)
		or (type(fluxus) == "table" and type(fluxus.request) == "function" and fluxus.request)
		or nil,
}
Webhook.Alerted = type(Environment.JunkMechanicsAlerted) == "table" and Environment.JunkMechanicsAlerted or {}
Environment.JunkMechanicsAlerted = Webhook.Alerted
Hub.Internal.Webhook = Webhook

function Webhook.Load()
	if type(readfile) == "function" and type(isfile) == "function" then
		local ok, data = pcall(function()
			if isfile(Webhook.File) then
				return HttpService:JSONDecode(readfile(Webhook.File))
			end
			return nil
		end)
		if ok and type(data) == "table" then
			for key, default in pairs(Webhook.Settings) do
				if type(data[key]) == type(default) then
					Webhook.Settings[key] = data[key]
				end
			end
		end
	end
	Webhook.Settings.Interval = math.clamp(math.floor(tonumber(Webhook.Settings.Interval) or 10), 1, 60)
	local set = {}
	for _, key in ipairs(Webhook.Settings.Cars) do
		if type(key) == "string" and VehicleData[key] then
			set[key] = true
		end
	end
	Webhook.Cars = set
end

function Webhook.Save()
	if type(writefile) ~= "function" then
		return
	end
	pcall(function()
		writefile(Webhook.File, HttpService:JSONEncode(Webhook.Settings))
	end)
end

function Webhook.Valid(url)
	return type(url) == "string" and string.match(url, "^https://[%w%.%-]*discord%w*%.com/api/webhooks/%d+/[%w_%-]+") ~= nil
end

function Webhook.Target()
	return Webhook.Valid(Webhook.Settings.Url) and Webhook.Settings.Url or nil
end

function Webhook.Ready()
	return Webhook.Settings.Enabled and Webhook.Request ~= nil and Webhook.Target() ~= nil
end

function Webhook.Image(key)
	local cached = Webhook.Images[key]
	if cached ~= nil then
		return cached or nil
	end
	local info = VehicleData[key]
	local id = type(info) == "table" and string.match(tostring(info.Image or ""), "%d+")
	if not id or not Webhook.Request then
		Webhook.Images[key] = false
		return nil
	end
	local ok, response = pcall(Webhook.Request, {
		Url = "https://thumbnails.roblox.com/v1/assets?assetIds=" .. id .. "&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false",
		Method = "GET",
	})
	if not (ok and type(response) == "table" and tonumber(response.StatusCode) == 200) then
		return nil
	end
	local url
	pcall(function()
		local item = HttpService:JSONDecode(response.Body).data[1]
		if item.state == "Completed" and type(item.imageUrl) == "string" and item.imageUrl ~= "" then
			url = item.imageUrl
		end
	end)
	Webhook.Images[key] = url or false
	return url
end

function Webhook.Build(item)
	local embed = {
		title = item.Title,
		color = item.Color or Webhook.Colors.Info,
		description = "Player: ||" .. LocalPlayer.Name .. "||" .. (item.Text and ("\n" .. item.Text) or ""),
		fields = item.Fields or {},
		footer = { text = WindowTitle .. (UI.Credits and (" | " .. UI.Credits) or "") },
		timestamp = item.Time or DateTime.now():ToIsoDate(),
	}
	if item.Car then
		local url = Webhook.Image(item.Car)
		if url and item.Big then
			embed.image = { url = url }
		elseif url then
			embed.thumbnail = { url = url }
		end
	end
	return {
		content = item.Ping and "@everyone" or nil,
		embeds = { embed },
		allowed_mentions = { parse = item.Ping and { "everyone" } or {} },
	}
end

function Webhook.Post(url, payload)
	local ok, response = pcall(function()
		return Webhook.Request({
			Url = url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(payload),
		})
	end)
	if not ok or type(response) ~= "table" then
		return 0, tostring(response)
	end
	return tonumber(response.StatusCode) or 0, tostring(response.Body or "")
end

function Webhook.Describe(code)
	if code == 0 then
		return "the request failed"
	elseif code == 401 or code == 403 then
		return "wrong webhook token"
	elseif code == 404 then
		return "webhook not found, it may be deleted"
	elseif code == 400 then
		return "Discord rejected the message"
	end
	return "Discord answered HTTP " .. tostring(code)
end

function Webhook.Push(item)
	if not Webhook.Ready() then
		return false
	end
	item.Time = DateTime.now():ToIsoDate()
	if #Webhook.Queue >= 20 then
		table.remove(Webhook.Queue, 1)
	end
	table.insert(Webhook.Queue, item)
	return true
end

function Webhook.Flush()
	while Hub.Running and #Webhook.Queue > 0 do
		local target = Webhook.Ready() and Webhook.Target()
		if not target then
			table.clear(Webhook.Queue)
			return
		end
		local item = Webhook.Queue[1]
		if not item.Payload then
			local ok, payload = pcall(Webhook.Build, item)
			item.Payload = ok and payload or false
		end
		local code, body = 0, ""
		if item.Payload then
			code, body = Webhook.Post(target, item.Payload)
		end
		if code == 429 and (item.Tries or 0) < 3 then
			item.Tries = (item.Tries or 0) + 1
			local delay = 2
			pcall(function()
				delay = tonumber(HttpService:JSONDecode(body).retry_after) or 2
			end)
			task.wait(math.clamp(delay, 0.5, 30))
		else
			local index = table.find(Webhook.Queue, item)
			if index then
				table.remove(Webhook.Queue, index)
			end
			if code >= 200 and code < 300 then
				Webhook.Sent = Webhook.Sent + 1
				Webhook.LastError = nil
			else
				Webhook.Failed = Webhook.Failed + 1
				Webhook.LastError = Webhook.Describe(code)
			end
			task.wait(0.6)
		end
	end
end

function Webhook.StatsFields()
	local money = getMoney()
	local start = Stats.StartMoney or money
	local elapsed = os.clock() - Stats.StartTime
	local slots = Garage.Slots()
	local status = Status.Text .. (Status.Detail ~= "" and (" - " .. Status.Detail) or "")
	local last = "-"
	if Stats.LastCar then
		last = Stats.LastCar .. (Stats.LastProfit and (" " .. signedMoney(Stats.LastProfit)) or "")
	end
	return {
		{ name = "Money", value = formatMoney(money), inline = true },
		{ name = "Session", value = signedMoney(money - start), inline = true },
		{ name = "Per Hour", value = signedMoney((money - start) / (math.max(elapsed, 60) / 3600)), inline = true },
		{ name = "Cars Bought", value = tostring(Stats.Bought), inline = true },
		{ name = "Cars Sold", value = tostring(Stats.Sold), inline = true },
		{ name = "Avg Car Time", value = Stats.Cycles > 0 and formatTime(Stats.CycleTime / Stats.Cycles) or "-", inline = true },
		{ name = "Last Sale", value = last, inline = true },
		{ name = "Best Profit", value = Stats.BestProfit and signedMoney(Stats.BestProfit) or "-", inline = true },
		{ name = "Uptime", value = formatTime(elapsed), inline = true },
		{ name = "Repaired", value = string.format("%d parts, %d wheels, %d paints", Stats.Repaired, Stats.Wheels, Stats.Painted or 0), inline = true },
		{ name = "Garage", value = Garage.Count() .. "/" .. (slots == math.huge and "?" or tostring(slots)), inline = true },
		{ name = "Errors", value = tostring(Stats.Errors), inline = true },
		{ name = "Status", value = string.sub(status, 1, 1000), inline = false },
	}
end

function Webhook.Entry(model)
	local key = model:GetAttribute(JunkConstants.VehicleNameAttribute or "VehicleName")
	local info = key and VehicleData[key]
	if type(info) ~= "table" then
		return nil
	end
	local price = tonumber(model:GetAttribute(JunkConstants.PriceAttribute or "JunkPrice")) or 0
	local sell = Car.FullValue(key)
	return {
		Key = key,
		Display = tostring(info.DisplayName or key),
		Price = price,
		Tier = tonumber(model:GetAttribute(JunkConstants.TierAttribute or "JunkTier")) or tonumber(info.Tier) or 0,
		Sell = sell,
		Profit = sell - price,
		Grade = nearestJunkyard(model:GetPivot().Position),
	}
end

function Webhook.CarFields(entry, bought)
	local yard = entry.Grade and junkyardInfo(entry.Grade)
	local fields = {
		{ name = "Car", value = entry.Display, inline = true },
		{ name = "Tier", value = "Tier " .. tostring(entry.Tier), inline = true },
		{ name = bought and "Paid" or "Price", value = formatMoney(entry.Price), inline = true },
		{ name = "Max Value", value = formatMoney(entry.Sell), inline = true },
		{ name = "Potential Profit", value = signedMoney(entry.Profit), inline = true },
		{ name = "Junkyard", value = yard and (yard.Name .. (junkyardUnlocked(entry.Grade) and "" or " (locked)")) or "-", inline = true },
	}
	if bought then
		table.insert(fields, { name = "Money Left", value = formatMoney(getMoney()), inline = true })
	end
	return fields
end

function Webhook.Check(model)
	if not (Hub.Running and Webhook.Settings.Spawns and next(Webhook.Cars) and Webhook.Ready()) then
		return
	end
	if not (model:IsA("Model") and model:IsDescendantOf(Workspace)) then
		return
	end
	local entry = Webhook.Entry(model)
	if not (entry and Webhook.Cars[entry.Key]) then
		return
	end
	local mark = tostring(model:GetAttribute(JunkConstants.SpawnIdAttribute or "JunkSpawnId")) .. ":" .. entry.Key .. ":" .. tostring(entry.Price)
	if Webhook.Alerted[mark] then
		return
	end
	Webhook.Alerted[mark] = true
	Webhook.Push({
		Title = "⭐ Highlighted Car Spawned!",
		Color = Webhook.Colors.Highlight,
		Ping = Webhook.Settings.Ping,
		Car = entry.Key,
		Big = true,
		Fields = Webhook.CarFields(entry, false),
	})
end

function Webhook.Scan()
	for _, model in ipairs(CollectionService:GetTagged(JunkConstants.JunkVehicleTag or "JunkVehicle")) do
		pcall(Webhook.Check, model)
	end
end

function Webhook.Test()
	if not Webhook.Request then
		return false, "Your executor cannot send web requests"
	end
	local target = Webhook.Target()
	if not target then
		return false, "Paste a Discord webhook link first"
	end
	local code = Webhook.Post(target, Webhook.Build({
		Title = "✅ Webhook Connected",
		Text = "Farm stats will arrive here.",
		Fields = Webhook.StatsFields(),
	}))
	if code >= 200 and code < 300 then
		Webhook.Sent = Webhook.Sent + 1
		Webhook.LastError = nil
		return true
	end
	Webhook.Failed = Webhook.Failed + 1
	Webhook.LastError = Webhook.Describe(code)
	return false, "Not sent: " .. Webhook.LastError
end

function Webhook.Tick()
	if not (Webhook.Settings.Stats and Webhook.Ready() and Farm.Active()) then
		Webhook.LastStats = nil
		return
	end
	local now = os.clock()
	if not Webhook.LastStats then
		Webhook.LastStats = now
	elseif now - Webhook.LastStats >= Webhook.Settings.Interval * 60 then
		Webhook.LastStats = now
		Webhook.Push({ Title = "📊 Farm Stats", Fields = Webhook.StatsFields() })
	end
end

function Webhook.StatusText()
	if not Webhook.Request then
		return "Webhook: your executor cannot send requests"
	end
	if not Webhook.Target() then
		return "Webhook: paste your Discord webhook link"
	end
	if not Webhook.Settings.Enabled then
		return "Webhook: off"
	end
	if Webhook.LastError then
		return "Webhook: " .. Webhook.LastError
	end
	return "Webhook: ready | Sent " .. Webhook.Sent .. (#Webhook.Queue > 0 and (" | Queued " .. #Webhook.Queue) or "")
end

Webhook.Load()

Farm.Hooks.Bought = function(entry)
	if Webhook.Cars[entry.Key] and Webhook.Settings.Bought then
		Webhook.Push({
			Title = "⭐ Highlighted Car Bought!",
			Color = Webhook.Colors.Highlight,
			Ping = Webhook.Settings.Ping,
			Car = entry.Key,
			Big = true,
			Fields = Webhook.CarFields(entry, true),
		})
	elseif Webhook.Settings.Purchases then
		Webhook.Push({ Title = "🛒 Car Bought", Color = Webhook.Colors.Buy, Car = entry.Key, Fields = Webhook.CarFields(entry, true) })
	end
end

Farm.Hooks.Sold = function(sale)
	if not Webhook.Settings.Sales then
		return
	end
	Webhook.Push({
		Title = "💰 Car Sold",
		Color = (sale.Profit or 0) < 0 and Webhook.Colors.Loss or Webhook.Colors.Sale,
		Car = sale.Key,
		Fields = {
			{ name = "Car", value = sale.Display or "Car", inline = true },
			{ name = "Sold For", value = formatMoney(sale.Amount), inline = true },
			{ name = "Paid", value = sale.Paid and formatMoney(sale.Paid) or "?", inline = true },
			{ name = "Profit", value = sale.Profit and signedMoney(sale.Profit) or "?", inline = true },
			{ name = "Flip Time", value = sale.Duration and formatTime(sale.Duration) or "-", inline = true },
			{ name = "Money", value = formatMoney(getMoney()), inline = true },
		},
	})
end

Farm.Hooks.Stopped = function(name, reason)
	if name ~= "Auto Farm" or not Webhook.Settings.Alerts then
		return
	end
	local fields = Webhook.StatsFields()
	table.insert(fields, 1, { name = "Reason", value = string.sub(reason, 1, 1000), inline = false })
	Webhook.Push({ Title = "⚠️ Farm Stopped", Color = Webhook.Colors.Warning, Fields = fields })
end

table.insert(Hub.Connections, CollectionService:GetInstanceAddedSignal(JunkConstants.JunkVehicleTag or "JunkVehicle"):Connect(function(model)
	task.delay(1, function()
		pcall(Webhook.Check, model)
	end)
end))

task.spawn(function()
	task.wait(3)
	pcall(Webhook.Scan)
	while Hub.Running do
		pcall(Webhook.Tick)
		pcall(Webhook.Flush)
		task.wait(1)
	end
end)

local FarmTab = Window:CreateTab({ Name = "Farm", Icon = "car" })
local FilterTab = Window:CreateTab({ Name = "Filters", Icon = "funnel" })
local RepairTab = Window:CreateTab({ Name = "Repair", Icon = "wrench" })
local SellTab = Window:CreateTab({ Name = "Sell", Icon = "coins" })
local WebhookTab = Window:CreateTab({ Name = "Webhook", Icon = "webhook" })
local SettingsTab = Window:CreateTab({ Name = "Settings", Icon = "settings" })

function UI.SetCarFilter(selection, other)
	local set, labels = {}, {}
	for _, label in ipairs(asList(selection)) do
		local key = CarByLabel[label]
		if key then
			set[key] = true
			table.insert(labels, label)
		end
	end
	Filter.Cars = set
	if other then
		pcall(function()
			other:Set(labels, true)
		end)
	end
end

UI.CarLabels = {}

function UI.CarIds(selection)
	local set = {}
	for _, label in ipairs(asList(selection)) do
		local id = UI.CarLabels[label]
		if id then
			set[id] = true
		end
	end
	return set
end

function UI.RefreshCars()
	local options, byLabel, ready = Garage.Options()
	if not ready then
		return
	end
	local signature = table.concat(options, "|")
	if signature == UI.CarSignature then
		return
	end
	UI.CarSignature = signature
	UI.CarLabels = byLabel
	local exists = {}
	for _, id in pairs(byLabel) do
		exists[id] = true
	end
	local function prune(set)
		local kept = {}
		for id in pairs(set) do
			if exists[id] then
				kept[id] = true
			end
		end
		return kept
	end
	Farm.Pick.Repair = prune(Farm.Pick.Repair)
	Farm.Pick.Sell = prune(Farm.Pick.Sell)
	local favorites = prune(Farm.Favorites)
	local changed = false
	for id in pairs(Farm.Favorites) do
		if not favorites[id] then
			changed = true
		end
	end
	Farm.Favorites = favorites
	if changed then
		Farm.SaveFavorites()
	end
	for _, entry in ipairs({ { UI.RepairCars, Farm.Pick.Repair }, { UI.SellCars, Farm.Pick.Sell }, { UI.FavoriteCars, Farm.Favorites } }) do
		local dropdown, set = entry[1], entry[2]
		if dropdown then
			pcall(function()
				dropdown:Refresh(options, true)
				local selected = {}
				for _, label in ipairs(options) do
					if set[byLabel[label]] then
						table.insert(selected, label)
					end
				end
				dropdown:Set(selected, true)
			end)
		end
	end
end

function UI.SetToggle(toggle, value)
	if toggle then
		pcall(function()
			toggle:Set(value)
		end)
	end
end

function UI.SyncFarm()
	local all = State.AutoBuy and State.AutoRepair and State.AutoSell
	if all ~= State.Farm then
		State.Farm = all
		UI.Syncing = true
		UI.SetToggle(UI.FarmToggle, all)
		UI.Syncing = false
	end
end

function UI.SetAuto(value)
	value = value == true
	State.AutoBuy, State.AutoRepair, State.AutoSell = value, value, value
	UI.Syncing = true
	UI.SetToggle(UI.BuyToggle, value)
	UI.SetToggle(UI.RepairToggle, value)
	UI.SetToggle(UI.SellToggle, value)
	UI.Syncing = false
end

function UI.ApplyAuto()
	UI.SyncFarm()
	if Farm.Active() then
		if Job.Name ~= "Auto Farm" or Job.Cancel then
			Stats.StartMoney = Stats.StartMoney or getMoney()
			Farm.Run = (Farm.Run or 0) + 1
			Job.Start("Auto Farm", Farm.Loop, Farm.Active)
		end
	elseif Job.Name == "Auto Farm" then
		Farm.Run = (Farm.Run or 0) + 1
		Job.Stop()
	end
end

Farm.Hooks.PickDone = function(kind)
	if State.AutoBuy then
		return
	end
	if kind == "Sell" and State.AutoSell then
		State.AutoSell = false
		UI.Syncing = true
		UI.SetToggle(UI.SellToggle, false)
		UI.Syncing = false
	elseif kind == "Repair" and State.AutoRepair then
		State.AutoRepair = false
		UI.Syncing = true
		UI.SetToggle(UI.RepairToggle, false)
		UI.Syncing = false
	else
		return
	end
	UI.SyncFarm()
	UI.Notify("Cars To " .. kind, "All selected cars are done, so Auto " .. kind .. " was turned off.", "Info")
	if Webhook.Settings.Alerts then
		Webhook.Push({ Title = "✅ Selected Cars Done", Text = "All cars picked in Cars To " .. kind .. " are done, so Auto " .. kind .. " was turned off.", Fields = Webhook.StatsFields() })
	end
end

Farm.Hooks.GarageFull = function()
	UI.Syncing = true
	UI.SetToggle(UI.BuyToggle, false)
	UI.Syncing = false
	UI.SyncFarm()
	UI.Notify("Garage Full", "All your garages are full, so Auto Buy was turned off. Sell cars or buy a bigger garage.", "Warning")
	if Webhook.Settings.Alerts then
		Webhook.Push({ Title = "🏠 Garage Full", Color = Webhook.Colors.Warning, Text = "Auto Buy was turned off. Sell cars or buy a bigger garage.", Fields = Webhook.StatsFields() })
	end
end

UI.FarmToggle = FarmTab:CreateToggle({
	Name = "Auto Farm",
	CurrentValue = false,
	Callback = function(value)
		if UI.Syncing then
			return
		end
		value = value == true
		UI.SetAuto(value)
		State.Farm = value
		UI.ApplyAuto()
	end,
})
table.insert(Hub.Toggles, UI.FarmToggle)

FarmTab:CreateSection("Status")

live(FarmTab, function()
	local modes = {}
	if State.AutoBuy then
		table.insert(modes, "Buy")
	end
	if State.AutoRepair then
		table.insert(modes, "Repair")
	end
	if State.AutoSell then
		table.insert(modes, "Sell")
	end
	return "Auto: " .. (#modes > 0 and table.concat(modes, " + ") or "off") .. " | Garage " .. Garage.Count() .. "/" .. (Garage.Slots() == math.huge and "?" or tostring(Garage.Slots()))
end)

live(FarmTab, function()
	local detail = Status.Detail ~= "" and (" | " .. Status.Detail) or ""
	return "Status: " .. Status.Text .. detail .. " (" .. formatTime(os.clock() - Status.Since) .. ")"
end)

live(FarmTab, function()
	local car = Car.Get()
	if not car then
		return "Car: none"
	end
	local display, key = Car.Name(car)
	local value = Car.Value(car)
	local condition = Car.Condition(car)
	local paid = Farm.Current and Farm.Current.Paid
	return string.format("Car: %s | Paid %s | Now %s | Max %s | %d%%", display, paid and formatMoney(paid) or "?", value and formatMoney(value) or "?", formatMoney(Car.FullValue(key)), math.floor((condition or 0) * 100 + 0.5))
end)

live(FarmTab, function()
	local money = getMoney()
	local start = Stats.StartMoney or money
	return "Money: " .. formatMoney(money) .. " | Session: " .. signedMoney(money - start)
end)

live(FarmTab, function()
	local elapsed = os.clock() - Stats.StartTime
	local money = getMoney()
	local start = Stats.StartMoney or money
	local perHour = (money - start) / (math.max(elapsed, 60) / 3600)
	local average = Stats.Cycles > 0 and formatTime(Stats.CycleTime / Stats.Cycles) or "-"
	return "Per hour: " .. signedMoney(perHour) .. " | Avg car: " .. average .. " | Uptime: " .. formatTime(elapsed)
end)

live(FarmTab, function()
	return string.format("Bought %d | Sold %d | Fixed %d | Wheels %d | Painted %d | Errors %d", Stats.Bought, Stats.Sold, Stats.Repaired, Stats.Wheels, Stats.Painted or 0, Stats.Errors)
end)

live(FarmTab, function()
	if not Stats.LastCar then
		return "Last sale: -"
	end
	local profit = Stats.LastProfit and signedMoney(Stats.LastProfit) or "?"
	local best = Stats.BestProfit and signedMoney(Stats.BestProfit) or "-"
	return "Last sale: " .. Stats.LastCar .. " " .. profit .. " | Best: " .. best
end)

live(FarmTab, function()
	return "Game: " .. tostring(Status.Message)
end, 1)

live(FarmTab, function()
	return "Before: " .. tostring(Status.Log[2] or "-")
end, 1)

FarmTab:CreateSection("Manual")

UI.BuyToggle = FarmTab:CreateToggle({
	Name = "Auto Buy",
	CurrentValue = false,
	Callback = function(value)
		State.AutoBuy = value == true
		if not UI.Syncing then
			UI.ApplyAuto()
		end
	end,
})
table.insert(Hub.Toggles, UI.BuyToggle)

UI.RepairToggle = FarmTab:CreateToggle({
	Name = "Auto Repair",
	CurrentValue = false,
	Callback = function(value)
		State.AutoRepair = value == true
		if not UI.Syncing then
			UI.ApplyAuto()
		end
	end,
})
table.insert(Hub.Toggles, UI.RepairToggle)

UI.SellToggle = FarmTab:CreateToggle({
	Name = "Auto Sell",
	CurrentValue = false,
	Callback = function(value)
		State.AutoSell = value == true
		if not UI.Syncing then
			UI.ApplyAuto()
		end
	end,
})
table.insert(Hub.Toggles, UI.SellToggle)

FarmTab:CreateLabel({ Text = "---------------" })

UI.BuyCars = FarmTab:CreateDropdown({
	Name = "Cars To Buy",
	Options = CarOptions,
	CurrentOption = {},
	MultipleOptions = true,
	Callback = function(selection)
		UI.SetCarFilter(selection, UI.FilterCars)
	end,
})

UI.RepairCars = FarmTab:CreateDropdown({
	Name = "Cars To Repair",
	Options = {},
	CurrentOption = {},
	MultipleOptions = true,
	Callback = function(selection)
		Farm.Pick.Repair = UI.CarIds(selection)
		for id in pairs(Farm.Pick.Repair) do
			Farm.Done[id] = nil
			Repair.Attempts[id] = nil
			Wheels.Attempts[id] = nil
			Farm.PaintTries[id] = nil
		end
	end,
})

UI.SellCars = FarmTab:CreateDropdown({
	Name = "Cars To Sell",
	Options = {},
	CurrentOption = {},
	MultipleOptions = true,
	Callback = function(selection)
		Farm.Pick.Sell = UI.CarIds(selection)
	end,
})

UI.FavoriteCars = FarmTab:CreateDropdown({
	Name = "Favorite Cars",
	Options = {},
	CurrentOption = {},
	MultipleOptions = true,
	Callback = function(selection)
		Farm.Favorites = UI.CarIds(selection)
		Farm.SaveFavorites()
	end,
})

FarmTab:CreateLabel({ Text = "Favorite cars are never sold by the script" })

task.spawn(function()
	while Hub.Running do
		pcall(UI.RefreshCars)
		task.wait(2)
	end
end)

FarmTab:CreateButton({
	Name = "Buy Best Car",
	Icon = "shopping-cart",
	Callback = function()
		Job.Start("Buy", function()
			if Garage.Full() then
				error("All your garages are full", 0)
			end
			if not Farm.BuyNext() then
				error("No car was bought", 0)
			end
		end)
	end,
})

FarmTab:CreateButton({
	Name = "Repair My Car",
	Icon = "wrench",
	Callback = function()
		Job.Start("Repair", function()
			Farm.Each("Repair", function(car)
				local id = Farm.Key(car)
				Repair.Attempts[id] = 0
				Wheels.Attempts[id] = 0
				Farm.PaintTries[id] = 0
				Farm.Done[id] = nil
				Farm.Restore(car)
			end)
		end)
	end,
})

FarmTab:CreateButton({
	Name = "Sell My Car",
	Icon = "coins",
	Callback = function()
		Job.Start("Sell", function()
			Farm.Each("Sell", function(car)
				Seller.Sell(car)
			end)
		end)
	end,
})

FarmTab:CreateButton({
	Name = "Stop Current Task",
	Icon = "square",
	Callback = function()
		UI.SetAuto(false)
		UI.SyncFarm()
		State.Farm = false
		Job.Stop()
	end,
})

FilterTab:CreateSection("Which Cars To Buy")

FilterTab:CreateDropdown({
	Name = "Tiers",
	Options = { "Tier 1", "Tier 2", "Tier 3", "Tier 4", "Tier 5" },
	CurrentOption = {},
	MultipleOptions = true,
	Callback = function(selection)
		local set = {}
		for _, label in ipairs(asList(selection)) do
			local tier = tonumber(string.match(tostring(label), "%d+"))
			if tier then
				set[tier] = true
			end
		end
		Filter.Tiers = set
	end,
})

UI.FilterCars = FilterTab:CreateDropdown({
	Name = "Cars",
	Options = CarOptions,
	CurrentOption = {},
	MultipleOptions = true,
	Callback = function(selection)
		UI.SetCarFilter(selection, UI.BuyCars)
	end,
})

FilterTab:CreateDropdown({
	Name = "Junkyards",
	Options = JunkyardOptions,
	CurrentOption = {},
	MultipleOptions = true,
	Callback = function(selection)
		local set = {}
		for _, label in ipairs(asList(selection)) do
			local grade = JunkyardByLabel[label]
			if grade then
				set[grade] = true
			end
		end
		Filter.Junkyards = set
	end,
})

FilterTab:CreateDropdown({
	Name = "Pick By",
	Options = { "Best Profit", "Best Margin", "Cheapest", "Closest" },
	MultipleOptions = false,
	Callback = function(selection)
		local value = asList(selection)[1]
		if value and Sorters[value] then
			Filter.Sort = value
		end
	end,
})

local function amountInput(tab, name, placeholder, apply)
	tab:CreateInput({
		Name = name,
		PlaceholderText = placeholder,
		CurrentValue = "",
		Callback = function(text)
			local amount = parseAmount(text)
			if amount then
				apply(amount)
			else
				UI.Notify(name, "Use a number like 25K or 1.5M", "Warning")
			end
		end,
	})
end

amountInput(FilterTab, "Min Price", "0 = any", function(amount)
	Filter.MinPrice = amount
end)

amountInput(FilterTab, "Max Price", "0 = any", function(amount)
	Filter.MaxPrice = amount
end)

amountInput(FilterTab, "Min Profit", "0 = any, e.g. 5K", function(amount)
	Filter.MinProfit = amount
end)

amountInput(FilterTab, "Min Margin %", "0 = any, e.g. 40", function(amount)
	Filter.MinMargin = amount
end)

amountInput(FilterTab, "Keep Money", "Never spend below, e.g. 10K", function(amount)
	Filter.Reserve = amount
end)

FilterTab:CreateSection("Preview")

live(FilterTab, function()
	local entry = Shop.Candidates()[1]
	if not entry then
		return "Best now: nothing matches nearby"
	end
	return string.format("Best now: %s T%d | %s -> %s | %s | %d studs", entry.Display, entry.Tier, formatMoney(entry.Price), formatMoney(entry.Sell), signedMoney(entry.Profit), math.floor(entry.Distance))
end, 2)

live(FilterTab, function()
	return "Matching cars nearby: " .. #Shop.Candidates() .. " (" .. #Shop.Candidates(true) .. " without money limit)"
end, 3)

RepairTab:CreateSection("Parts To Repair")

RepairTab:CreateToggle({
	Name = "Battery (Charger)",
	CurrentValue = true,
	Callback = function(value)
		State.RepairBattery = value == true
	end,
})

RepairTab:CreateToggle({
	Name = "Mechanical Parts (Grinder)",
	CurrentValue = true,
	Callback = function(value)
		State.RepairMechanical = value == true
	end,
})

RepairTab:CreateToggle({
	Name = "Engine (Hoist)",
	CurrentValue = true,
	Callback = function(value)
		State.RepairEngine = value == true
	end,
})

RepairTab:CreateToggle({
	Name = "Radiator (Sink)",
	CurrentValue = true,
	Callback = function(value)
		State.RepairRadiator = value == true
	end,
})

RepairTab:CreateSlider({
	Name = "Skip Parts With Wear Below %",
	Range = { 0, 50 },
	Increment = 1,
	CurrentValue = 2,
	Callback = function(value)
		State.MinWear = (tonumber(value) or 0) / 100
	end,
})

RepairTab:CreateToggle({
	Name = "Auto Install Missing Parts",
	CurrentValue = true,
	Callback = function(value)
		State.AutoMissingParts = value == true
	end,
})

RepairTab:CreateSection("Wheels")

RepairTab:CreateToggle({
	Name = "Replace Rusty Rims & Worn Tires",
	CurrentValue = true,
	Callback = function(value)
		State.FixWheels = value == true
	end,
})

RepairTab:CreateSlider({
	Name = "Replace Wheel Parts From Wear %",
	Range = { 10, 90 },
	Increment = 5,
	CurrentValue = 30,
	Callback = function(value)
		State.WheelMinWear = (tonumber(value) or 30) / 100
	end,
})

RepairTab:CreateButton({
	Name = "Fix My Wheels",
	Icon = "disc",
	Callback = function()
		Job.Start("Wheels", function()
			local car = Car.Get()
			if not car then
				error("No car out of the garage", 0)
			end
			Wheels.Run(car)
			Wheels.Unlift(car)
		end)
	end,
})

RepairTab:CreateSection("Minigames")

RepairTab:CreateToggle({
	Name = "Auto Minigames",
	CurrentValue = true,
	Callback = function(value)
		State.AutoMinigames = value == true
	end,
})

RepairTab:CreateSlider({
	Name = "Wash Time (s)",
	Range = { 2, 12 },
	Increment = 1,
	CurrentValue = 3,
	Callback = function(value)
		State.WashDelay = tonumber(value) or 3
	end,
})

RepairTab:CreateSlider({
	Name = "Weld Time (s)",
	Range = { 3, 20 },
	Increment = 1,
	CurrentValue = 6,
	Callback = function(value)
		State.WeldDelay = tonumber(value) or 6
	end,
})

RepairTab:CreateParagraph({
	Title = "Auto Minigames",
	Content = "Also works when you repair by hand: battery clamps, radiator washing and engine welding finish by themselves.",
})

SellTab:CreateSection("Paint")

SellTab:CreateToggle({
	Name = "Paint Before Selling ($250)",
	CurrentValue = true,
	Callback = function(value)
		State.Paint = value == true
	end,
})

SellTab:CreateDropdown({
	Name = "Paint Color",
	Options = { "Random", "Black", "White", "Red", "Blue", "Silver", "Green", "Yellow" },
	MultipleOptions = false,
	Callback = function(selection)
		local value = asList(selection)[1]
		if type(value) == "string" then
			State.PaintColor = value
		end
	end,
})

SellTab:CreateSection("Seller")

SellTab:CreateDropdown({
	Name = "Seller",
	Options = { "Juan", "Rick (Quick Sell)" },
	MultipleOptions = false,
	Callback = function(selection)
		local value = asList(selection)[1]
		if value == "Juan" or value == "Rick (Quick Sell)" then
			State.Seller = value
		end
	end,
})

SellTab:CreateToggle({
	Name = "Mr. Lupin For Tier 4-5",
	CurrentValue = true,
	Callback = function(value)
		State.UseLupin = value == true
	end,
})

SellTab:CreateSlider({
	Name = "Rick Min % Of Car Value",
	Range = { 50, 100 },
	Increment = 1,
	CurrentValue = 90,
	Callback = function(value)
		State.RickMinPercent = tonumber(value) or 90
	end,
})

SellTab:CreateSection("Negotiation")

SellTab:CreateToggle({
	Name = "Negotiate",
	CurrentValue = false,
	Callback = function(value)
		State.Negotiate = value == true
	end,
})

SellTab:CreateSlider({
	Name = "Max Risk %",
	Range = { 5, 60 },
	Increment = 1,
	CurrentValue = 20,
	Callback = function(value)
		State.MaxRisk = tonumber(value) or 20
	end,
})

live(SellTab, function()
	return "Seller says: " .. tostring(Status.Npc)
end, 1)

UI.LabelByKey = {}
for label, key in pairs(CarByLabel) do
	UI.LabelByKey[key] = label
end

function UI.WebhookToggle(name, field, after)
	return WebhookTab:CreateToggle({
		Name = name,
		CurrentValue = Webhook.Settings[field] == true,
		Callback = function(value)
			Webhook.Settings[field] = value == true
			Webhook.Save()
			if after then
				after(value == true)
			end
		end,
	})
end

function UI.RescanSoon(value)
	if value ~= false then
		task.delay(1, Webhook.Scan)
	end
end

WebhookTab:CreateSection("Discord")

WebhookTab:CreateInput({
	Name = "Webhook URL",
	PlaceholderText = "Paste your Discord webhook link",
	CurrentValue = Webhook.Settings.Url,
	Callback = function(text)
		text = string.match(tostring(text or ""), "^%s*(.-)%s*$") or ""
		if text == Webhook.Settings.Url then
			return
		end
		if text ~= "" and not Webhook.Valid(text) then
			UI.Notify("Webhook", "This is not a Discord webhook link", "Warning")
			return
		end
		Webhook.Settings.Url = text
		Webhook.LastError = nil
		Webhook.Save()
		if text ~= "" then
			UI.Notify("Webhook", "Saved. Press Send Test Message to check it.", "Success")
			UI.RescanSoon()
		end
	end,
})

UI.WebhookToggle("Enable Webhook", "Enabled", UI.RescanSoon)

WebhookTab:CreateButton({
	Name = "Send Test Message",
	Icon = "send",
	Callback = function()
		task.spawn(function()
			local ok, reason = Webhook.Test()
			UI.Notify("Webhook", ok and "Test message sent, check Discord" or reason, ok and "Success" or "Warning")
		end)
	end,
})

live(WebhookTab, Webhook.StatusText, 1)

WebhookTab:CreateSection("Farm Stats")

UI.WebhookToggle("Send Farm Stats", "Stats")

WebhookTab:CreateSlider({
	Name = "Stats Every (Minutes)",
	Range = { 1, 60 },
	Increment = 1,
	CurrentValue = Webhook.Settings.Interval,
	Callback = function(value)
		Webhook.Settings.Interval = math.clamp(math.floor(tonumber(value) or 10), 1, 60)
		Webhook.Save()
	end,
})

UI.WebhookToggle("Send Each Sale", "Sales")
UI.WebhookToggle("Send Each Purchase", "Purchases")
UI.WebhookToggle("Send Farm Stops & Garage Full", "Alerts")

WebhookTab:CreateSection("Highlighted Cars")

UI.HighlightCars = WebhookTab:CreateDropdown({
	Name = "Cars To Highlight",
	Options = CarOptions,
	CurrentOption = (function()
		local labels = {}
		for _, key in ipairs(Webhook.Settings.Cars) do
			if UI.LabelByKey[key] then
				table.insert(labels, UI.LabelByKey[key])
			end
		end
		return labels
	end)(),
	MultipleOptions = true,
	Callback = function(selection)
		local keys, set = {}, {}
		for _, label in ipairs(asList(selection)) do
			local key = CarByLabel[label]
			if key and not set[key] then
				set[key] = true
				table.insert(keys, key)
			end
		end
		Webhook.Cars = set
		Webhook.Settings.Cars = keys
		Webhook.Save()
		UI.RescanSoon()
	end,
})

WebhookTab:CreateLabel({ Text = "Highlighted cars get a gold message in Discord" })

UI.WebhookToggle("Alert When One Spawns", "Spawns", UI.RescanSoon)
UI.WebhookToggle("Alert When Script Buys One", "Bought")
UI.WebhookToggle("Ping @everyone", "Ping")

SettingsTab:CreateSection("Farm")

SettingsTab:CreateSlider({
	Name = "Teleport Speed",
	Range = { 60, 300 },
	Increment = 10,
	CurrentValue = 150,
	Callback = function(value)
		State.GlideSpeed = tonumber(value) or 150
	end,
})

SettingsTab:CreateToggle({
	Name = "Quick Travel To Junkyards",
	CurrentValue = true,
	Callback = function(value)
		State.QuickTravel = value == true
	end,
})

SettingsTab:CreateToggle({
	Name = "Continue Farm Cars From Garage",
	CurrentValue = true,
	Callback = function(value)
		State.UseGarage = value == true
	end,
})

SettingsTab:CreateToggle({
	Name = "Also Sell My Other Garage Cars",
	CurrentValue = false,
	Callback = function(value)
		State.UseAllGarageCars = value == true
	end,
})

SettingsTab:CreateToggle({
	Name = "Anti AFK",
	CurrentValue = true,
	Callback = function(value)
		State.AntiAfk = value == true
	end,
})

SettingsTab:CreateSection("Menu")

SettingsTab:CreateKeybind({
	Name = "Toggle UI",
	CurrentKeybind = "RightControl",
	OnChanged = function(key)
		Window:SetKeybind(key)
	end,
})

SettingsTab:CreateButton({
	Name = "Stop All",
	Icon = "square",
	Callback = function()
		stopAll()
		UI.Notify("Stopped", "Auto Farm is off", "Success")
	end,
})

SettingsTab:CreateButton({
	Name = "Unload UI",
	Icon = "power",
	Callback = function()
		Hub.Unload()
	end,
})

SettingsTab:CreateSection("Credits")

local CreditsLabel = SettingsTab:CreateLabel("Credits - loading...")
SettingsTab:CreateLabel("UI Library - airflowlib.lol")

task.spawn(function()
	local ok, text = pcall(function()
		return game:HttpGet(CreditsUrl)
	end)
	text = ok and type(text) == "string" and string.match(text, "^%s*(.-)%s*$") or ""
	UI.Credits = text ~= "" and #text <= 100 and text or nil
	if Hub.Running then
		pcall(function()
			CreditsLabel:Set(text ~= "" and ("Credits - " .. text) or "Credits - unavailable")
		end)
	end
end)

UI.Notify(WindowTitle, "Loaded", "Success")

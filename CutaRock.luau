local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local environment = type(getgenv) == "function" and getgenv() or shared or _G
if type(environment) ~= "table" then environment = _G end
local function capability(...)
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if type(value) == "function" then return value end
	end
end
local identitySetter = capability(setthreadidentity, setidentity, set_thread_identity, syn and syn.set_thread_identity)
local nativePrompt = capability(fireproximityprompt, environment.fireproximityprompt)
local httpRequest = capability(request, http_request, http and http.request, syn and syn.request, fluxus and fluxus.request)
local host = {
	global = environment,
	load = capability(loadstring, environment.loadstring),
	clipboard = capability(setclipboard, toclipboard, set_clipboard, syn and syn.write_clipboard),
}
if identitySetter then
	host.identity = function(level) pcall(identitySetter, level) end
end
function host.http(url)
	local ok, body = pcall(function() return game:HttpGet(url, true) end)
	if ok and type(body) == "string" and #body > 0 then return body end
	if httpRequest then
		local response = httpRequest({ Url = url, Method = "GET" })
		if type(response) == "table" then
			local code = tonumber(response.StatusCode or response.Status)
			local text = response.Body or response.body
			if response.Success ~= false and (not code or code >= 200 and code < 300) and type(text) == "string" and #text > 0 then return text end
		end
	end
	error("HTTP download failed: " .. url)
end
function host.releasePrompt()
	local prompt = host.heldPrompt
	host.heldPrompt = nil
	if prompt then pcall(function() prompt:InputHoldEnd() end) end
end
function host.prompt(prompt)
	if not prompt.Parent or not prompt.Enabled then return end
	if nativePrompt then
		local ok = pcall(nativePrompt, prompt)
		if ok then return end
	end
	host.heldPrompt = prompt
	local ok, err = pcall(function()
		prompt:InputHoldBegin()
		task.wait(math.max(0, prompt.HoldDuration) + 0.1)
	end)
	host.releasePrompt()
	if not ok then error("Prompt interaction is unavailable: " .. tostring(err)) end
end
assert(game.PlaceId == 113742027864370, "Open Cut a Rock before running this script.")
assert(host.load, "This script requires an executor with loadstring support.")
if host.global.CutARockHub then host.global.CutARockHub:Destroy() end

local library, libraryError = host.load(host.http("https://raw.githubusercontent.com/Footagesus/WindUI/d2c9bac5f96f997418d680d19cb759892542e492/dist/main.lua"))
assert(library, libraryError)
local WindUI = library()
local machineData = require(ReplicatedStorage:WaitForChild("MachineLevelData"))
local bagData = require(ReplicatedStorage:WaitForChild("CantaAyarlari"))
local indexData = require(ReplicatedStorage:WaitForChild("IndexIlerleme"))
local rockData = require(ReplicatedStorage:WaitForChild("ARockList"))
local stoneStyle = require(ReplicatedStorage:WaitForChild("TasStili"))
local pickaxeData = require(ReplicatedStorage:WaitForChild("PickaxeList")).Normal
local upgradeData = require(ReplicatedStorage:WaitForChild("UpgradePrice"))
local formatNumber = require(ReplicatedStorage:WaitForChild("FormatNumber")).format_number
local discoveries = player:WaitForChild("IndexKesifleri")
local ownedPickaxes = player:WaitForChild("KazmaSahipligi")
local pocket = player:WaitForChild("Cep")
local inventory = player:WaitForChild("Envanter")
local rooms = workspace:WaitForChild("Rooms")
local models = workspace:WaitForChild("Models")
local bases = models:WaitForChild("Bases")
local stations = models.World.AfkFarm.Istasyonlar
local state = {
	alive = true, flags = {}, selected = {}, connections = {}, rocks = {}, machines = {},
	retry = setmetatable({}, { __mode = "k" }),
	reserved = setmetatable({}, { __mode = "k" }),
	nextAction = 0, nextCut = 0, lastReturn = -10, status = "Ready",
	floorMode = "Deepest unlocked", unlockPercent = 80,
	phase = "Train", trainDuration = 30, trainRemaining = 30, cycleTick = 0, machineBusyUntil = 0,
	notifications = true, noticeTimes = {}, nextEconomy = 0, nextSell = 0,
	sellMode = "Duplicates only", sellRarities = {}, upgradeTargets = { Machines = true, Pocket = true, Eyesight = true },
	sequence = math.floor(os.clock() * 1000), indexDirty = true, indexCategory = "Common",
	machineStates = setmetatable({}, { __mode = "k" }),
}
local rarities = {}
for _, rarity in rockData.Rarety do table.insert(rarities, rarity.Name) end
local ranks = {}
for i, name in rarities do ranks[name] = i state.selected[name] = true state.sellRarities[name] = true end

local catalog, indexCategories = {}, {}
for _, group in rockData.All do
	catalog[group.Name] = group
	table.insert(indexCategories, group.Name)
end

local function notify(key, title, text, cooldown)
	if not state.alive or not state.notifications then return end
	local now = os.clock()
	if now - (state.noticeTimes[key] or -math.huge) < (cooldown or 4) then return end
	state.noticeTimes[key] = now
	if host.identity then host.identity(8) end
	WindUI:Notify({ Title = title, Content = text, Duration = 4 })
end

local function indexProgress(name)
	local group = catalog[name]
	local missing, found = {}, 0
	for _, material in group and group.material_list or {} do
		if discoveries:FindFirstChild(name .. "|" .. material.Name) then found += 1
		else table.insert(missing, material.Name) end
	end
	return found, missing
end

local function isNewMaterial(stone)
	local rarity = stoneStyle.NadirlikAdi(stone:GetAttribute("TasTuru"))
	local material = stone:GetAttribute("MalzemeAdi")
	return rarity and material and not discoveries:FindFirstChild(rarity .. "|" .. material)
end

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(state.connections, connection)
	return connection
end

local function character()
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then return model, root, humanoid end
end

local function moveTo(cf)
	local model, root = character()
	if not model then return false end
	if (root.Position - cf.Position).Magnitude > 2 then
		model:PivotTo(cf)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	return true
end

local function weight(folder)
	local total = 0
	for _, item in folder:GetChildren() do total += item:GetAttribute("Agirlik") or 1 end
	return total
end

local function pocketFull()
	local capacity = (player:GetAttribute("PocketLevel") or 1) + (player:GetAttribute("is_bought_bag_bonus") and 1 or 0)
	return #pocket:GetChildren() >= capacity
end

local function returnHome()
	if os.clock() - state.lastReturn < 2 then return end
	state.lastReturn = os.clock()
	state.returnRequested = false
	state.pending = nil
	ReplicatedStorage.BaseaIsinlanEvent:FireServer(false)
	state.nextAction = os.clock() + 1
	state.status = "Returning to base"
	if state.flags.Train and state.flags.Mine then state.phase = "Return" end
end

local function trackRock(instance)
	if not instance:IsA("ProximityPrompt") or instance.Name ~= "ToplaPrompt" then return end
	local rock = instance.Parent and instance.Parent.Parent
	local room = rock and rock.Parent and rock.Parent.Parent
	if not room or room.Parent ~= rooms then return end
	state.rocks[instance] = { model = rock, room = tonumber(room.Name:match("%d+")) or 1 }
end
for _, instance in rooms:GetDescendants() do trackRock(instance) end
connect(rooms.DescendantAdded, trackRock)
connect(rooms.DescendantRemoving, function(instance) state.rocks[instance] = nil end)

local function refreshMachines()
	table.clear(state.machines)
	for _, base in bases:GetChildren() do
		if base:GetAttribute("OwnerUserId") == player.UserId then
			for _, prompt in base:GetDescendants() do
				if prompt:IsA("ProximityPrompt") and prompt.Name == "CutMachinePrompt" then
					local reference = prompt:FindFirstChild("MakineNode")
					if reference and reference.Value then
						state.machines[prompt] = reference.Value
						local current = prompt:GetAttribute("Durum")
						if state.machineStates[prompt] and state.machineStates[prompt] ~= current and current == "Hazir" and prompt.Enabled then
							notify("machine-ready-" .. tostring(reference.Value:GetAttribute("YuvaNo")), "Core ready", "Machine " .. tostring(reference.Value:GetAttribute("YuvaNo") or "") .. " finished cutting.", 10)
						end
						state.machineStates[prompt] = current
					end
				end
			end
			break
		end
	end
end

local function cash()
	local stats = player:FindFirstChild("Statlar")
	local money = stats and stats:FindFirstChild("Money")
	return money and money.Value or 0
end

function state:SellCandidates()
	local keep, ids = {}, {}
	for _, stone in inventory:GetChildren() do
		if stone:GetAttribute("Kesildi") == true and not stone:GetAttribute("Kesimde") then
			local rarity = stoneStyle.NadirlikAdi(stone:GetAttribute("TasTuru"))
			local material = stone:GetAttribute("MalzemeAdi")
			local key = tostring(rarity) .. "|" .. tostring(material)
			local duplicate = keep[key] == true
			keep[key] = true
			if state.sellRarities[rarity] and discoveries:FindFirstChild(key) and not stoneStyle.KilitliMi(stone)
				and (state.sellMode ~= "Duplicates only" or duplicate) then
				table.insert(ids, stoneStyle.TasKimligi(stone))
			end
		end
	end
	return ids
end

local function confirmPurchase(text)
	local pending = state.purchasePending
	if not pending then return end
	state.purchasePending = nil
	state.nextEconomy = os.clock() + 1
	notify("purchase", pending.title, text, 0.5)
end

local function processEconomy(now)
	local pending = state.purchasePending
	if pending then
		if pending.kind == "Pickaxe" and ownedPickaxes:FindFirstChild(tostring(pending.level)) then
			confirmPurchase(pending.name .. " purchased")
		elseif pending.kind == "Equip" and player:GetAttribute("KusanilanKazma") == pending.level then
			confirmPurchase(pending.name .. " equipped")
		elseif now >= pending.deadline then
			state.purchasePending = nil
			state.nextEconomy = now + 5
			notify("purchase-timeout", "Purchase not confirmed", pending.name .. ": retrying later", 15)
		end
	end
	if state.flags.Sell and not player:GetAttribute("Madende") and now >= state.nextSell then
		state.nextSell = now + 4
		local ids = state:SellCandidates()
		if #ids > 0 then
			state.salePending = now
			ReplicatedStorage.SellEvent:FireServer("SellSelected", ids)
		end
	end
	if state.purchasePending or now < state.nextEconomy then return end
	state.nextEconomy = now + 1.5
	local money = cash()
	if state.flags.Pickaxe then
		local current = tonumber(player:GetAttribute("KusanilanKazma")) or 1
		local bestOwned = current
		for level, data in pickaxeData do
			if ownedPickaxes:FindFirstChild(tostring(level)) and data.Growth > (pickaxeData[bestOwned] and pickaxeData[bestOwned].Growth or 0) then bestOwned = level end
		end
		if bestOwned ~= current then
			state.sequence += 1
			state.purchasePending = { kind = "Equip", title = "Auto Pickaxe", name = pickaxeData[bestOwned].Name, level = bestOwned, seq = state.sequence, deadline = now + 6 }
			ReplicatedStorage.PickaxeEquipEvent:FireServer(bestOwned, state.sequence)
			return
		end
		local bestBuy
		for level, data in pickaxeData do
			if level > bestOwned and data.Price <= money and not ownedPickaxes:FindFirstChild(tostring(level)) then
				if not bestBuy or data.Growth > pickaxeData[bestBuy].Growth then bestBuy = level end
			end
		end
		if bestBuy then
			state.purchasePending = { kind = "Pickaxe", title = "Auto Pickaxe", name = pickaxeData[bestBuy].Name, level = bestBuy, deadline = now + 6 }
			ReplicatedStorage.PickaxeBuyEvent:FireServer(bestBuy)
			return
		end
	end
	if not state.flags.Upgrade then return end
	local best
	local function offer(kind, price, level, object)
		if type(price) == "number" and price >= 0 and price <= money and (not best or price < best.price) then
			best = { kind = kind, price = price, level = level, object = object }
		end
	end
	if state.upgradeTargets.Pocket then
		local level = player:GetAttribute("PocketLevel") or 1
		offer("Pocket", upgradeData.pocket_price[level + 1], level)
	end
	if state.upgradeTargets.Eyesight then
		local level = player:GetAttribute("Sight") or 1
		offer("Eyesight", upgradeData.sight_price[level + 1], level)
	end
	if state.upgradeTargets.Machines then
		for prompt, machine in state.machines do
			if prompt.Parent and prompt.Enabled then
				offer("Machine", machine:GetAttribute("SonrakiSeviyeFiyati"), machine:GetAttribute("Seviye") or 1, machine)
			end
		end
	end
	if best then
		state.sequence += 1
		best.seq = state.sequence
		best.deadline = now + 6
		best.title = "Auto Upgrade"
		best.name = best.kind == "Machine" and "Machine " .. (best.object:GetAttribute("YuvaNo") or "") or best.kind
		state.purchasePending = best
		if best.kind == "Machine" then ReplicatedStorage.LevelUpMachineEvent:FireServer(best.object, best.seq)
		else ReplicatedStorage.UpgradeEvent:FireServer(best.kind, best.seq) end
	end
end

local function train()
	local best, multiplier = nil, 0
	local completed = indexData.Tamamlanan(player.IndexKesifleri)
	for _, station in stations:GetChildren() do
		local value = station:GetAttribute("Carpan") or 0
		local floor = station:GetAttribute("GerekenKat") or 0
		local index = station:GetAttribute("GerekenIndex")
		local allowed = (player:GetAttribute("MaximumRoom") or 0) >= floor
		if index then allowed = completed >= index or player:GetAttribute("RobuxOrs_" .. value) == true end
		if allowed and value > multiplier then best, multiplier = station, value end
	end
	local target = best and best:FindFirstChild("DurmaNoktasi")
	if target then
		moveTo(target.CFrame)
		state.status = "Training at x" .. multiplier .. " anvil"
	else state.status = "Waiting for an available anvil" end
end

local function queuePrompt(prompt, cf, kind)
	if not moveTo(cf) then return end
	state.pending = { prompt = prompt, kind = kind }
	state.nextAction = os.clock() + 0.35
end

local function processMachines(now)
	if now < state.machineBusyUntil then state.status = "Loading cutting machines" return true end
	if state.flags.Collect and (not state.flags.Mine or not player:GetAttribute("Madende")) then
		for prompt in state.machines do
			if prompt.Parent and prompt.Enabled and prompt.ActionText == "Collect" and (state.retry[prompt] or 0) <= now then
				if player:GetAttribute("Madende") then returnHome() return true end
				state.status = "Collecting finished core"
				queuePrompt(prompt, prompt.Parent.CFrame * CFrame.new(0, 0, -6), "Collect")
				return true
			end
		end
	end
	if not state.flags.Cut or now < state.nextCut then return false end
	state.nextCut = now + 0.65
	local placed = false
	local stones = inventory:GetChildren()
	if state.flags.Index then
		table.sort(stones, function(a, b)
			local aNew, bNew = isNewMaterial(a) and 1 or 0, isNewMaterial(b) and 1 or 0
			if aNew ~= bNew then return aNew > bNew end
			return (a:GetAttribute("Resistance") or 0) < (b:GetAttribute("Resistance") or 0)
		end)
	end
	for prompt, machine in state.machines do
		if prompt.Parent and prompt.Enabled and prompt:GetAttribute("Durum") == "Bos" and (state.retry[prompt] or 0) <= now then
			for _, stone in stones do
				local resistance = stone:GetAttribute("Resistance")
				if not stone:GetAttribute("Kesildi") and not stone:GetAttribute("Kesimde") and (state.reserved[stone] or 0) <= now
					and type(resistance) == "number" and machineData.KesebilirMi(machine:GetAttribute("Seviye") or 1, resistance) then
					state.reserved[stone] = now + 4
					state.retry[prompt] = now + 3
					ReplicatedStorage.PlaceStoneInMachineEvent:FireServer(machine, stone.Name)
					placed = true
					break
				end
			end
		end
	end
	if placed then
		state.machineBusyUntil = now + 0.8
		state.status = "Loading cutting machines"
	end
	return placed
end

function state:UnlockReady(power, health)
	return health > 0 and power >= health * self.unlockPercent / 100
end

local function tryUnlock(root, humanoid)
	local maximum = math.max(1, player:GetAttribute("MaximumRoom") or 1)
	if state.unlockRoom and maximum > state.unlockRoom then
		state.unlockRoom = nil
		return false, true
	end
	local floor = state.unlockRoom or maximum
	local room = rooms:FindFirstChild("Room_" .. floor)
	local nextRoom = rooms:FindFirstChild("Room_" .. (floor + 1))
	local exit = room and room:FindFirstChild("ExitDigBlocks")
	if not exit or not nextRoom then state.unlockRoom = nil return false end
	local block, order, health = nil, math.huge, 0
	for _, part in exit:GetChildren() do
		if part:IsA("BasePart") and part.CanCollide then
			health += part:GetAttribute("MaxHealth") or 0
			local value = part:GetAttribute("Order") or 1
			if value < order then block, order = part, value end
		end
	end
	if block then
		if not state.unlockRoom and not state:UnlockReady(player:GetAttribute("Power") or 0, health) then
			return false
		end
		state.unlockRoom = floor
		local y = block.Size.Y / 2 + humanoid.HipHeight + root.Size.Y / 2
		moveTo(block.CFrame * CFrame.new(0, y, 0))
		state.status = "Opening next floor | " .. state.unlockPercent .. "% power threshold"
		return true
	end
	local landing, area = nil, 0
	for _, part in nextRoom:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Zemin" and part.Size.X * part.Size.Z > area then
			landing, area = part, part.Size.X * part.Size.Z
		end
	end
	if landing then
		state.unlockRoom = floor
		moveTo(landing.CFrame * CFrame.new(0, landing.Size.Y / 2 + humanoid.HipHeight + root.Size.Y / 2, 0))
		state.status = "Entering newly opened floor"
		return true
	end
	return false
end

local function mine(now, skipUnlock)
	local _, root, humanoid = character()
	if not root then return end
	if not skipUnlock and tryUnlock(root, humanoid) then return "Opening" end
	if next(state.selected) == nil then state.status = "Select at least one rarity" return "Empty" end
	if pocketFull() then state.status = "Pocket full - enable Auto Return" return "Full" end
	if weight(inventory) + weight(pocket) >= bagData.Kapasite(player) then
		state.status = "Backpack full - make space to continue"
		return "BackpackFull"
	end
	local maxRoom = math.max(1, player:GetAttribute("MaximumRoom") or 1)
	local selectedRoom = tonumber(state.floorMode:match("^Floor (%d+)$"))
	local targetRoom = selectedRoom and math.clamp(selectedRoom, 1, maxRoom) or maxRoom
	local best, bestScore, retryPending
	for prompt, data in state.rocks do
		if prompt.Parent and prompt.Enabled and data.room == targetRoom then
			local rarity = data.model:GetAttribute("Rarity")
			if state.selected[rarity] then
				if (state.retry[prompt] or 0) > now then retryPending = true continue end
				local distance = (root.Position - prompt.Parent.Position).Magnitude
				local score = (ranks[rarity] or 0) * 10000 - distance
				if state.flags.Index then
					local found, missing = indexProgress(rarity)
					if #missing > 0 then score += 1000000 + found * 100000 end
				end
				if not bestScore or score > bestScore then best, bestScore = prompt, score end
			end
		end
	end
	if best then
		local rock = state.rocks[best].model
		local position = best.Parent.Position
		local y = (rock:GetAttribute("ZeminY") or position.Y) + humanoid.HipHeight + root.Size.Y / 2
		state.status = "Mining " .. rock:GetAttribute("Rarity") .. " | Floor " .. targetRoom
		queuePrompt(best, CFrame.new(position.X, y, position.Z + 3), "Mine")
		return "Mining"
	end
	state.status = "Waiting for matching rocks on Floor " .. targetRoom
	return retryPending and "Waiting" or "Empty"
end

local function beginTraining(now)
	state.phase = "Train"
	state.trainRemaining = state.trainDuration
	state.cycleTick = now
end

local function runCycle(now)
	local _, root, humanoid = character()
	if not root then return end
	local dt = math.clamp(now - state.cycleTick, 0, 0.5)
	state.cycleTick = now
	if state.unlockRoom then
		local opening, opened = tryUnlock(root, humanoid)
		if opening then return end
		if opened then state.phase = "Mine" end
	end
	if weight(inventory) >= bagData.Kapasite(player) then
		if state.phase ~= "Train" then beginTraining(now) end
		state.trainRemaining = state.trainDuration
		train()
		state.status ..= " | Backpack full"
		return
	end
	if state.phase == "Return" then
		if not player:GetAttribute("Madende") and #pocket:GetChildren() == 0 then
			state.phase = "Service"
		elseif state.flags.Return then
			returnHome()
			return
		else beginTraining(now) end
	end
	if state.phase == "Service" then
		if processMachines(now) then return end
		beginTraining(now)
	end
	if pocketFull() and state.flags.Return then
		returnHome()
		return
	end
	local blocked
	if pocketFull() then blocked = "Pocket full"
	elseif weight(inventory) + weight(pocket) >= bagData.Kapasite(player) then blocked = "Backpack full"
	elseif next(state.selected) == nil then blocked = "No rarities selected" end
	if blocked then
		if state.phase ~= "Train" then beginTraining(now) end
		state.trainRemaining = state.trainDuration
		train()
		state.status ..= " | " .. blocked
		return
	end
	local opening, opened = tryUnlock(root, humanoid)
	if opening then return end
	if opened then state.phase = "Mine" end
	if state.phase == "Train" then
		local wasTraining = player:GetAttribute("TrainOrsu") ~= nil
		train()
		if wasTraining then state.trainRemaining = math.max(0, state.trainRemaining - dt) end
		state.status ..= " | " .. math.ceil(state.trainRemaining) .. "s"
		if state.trainRemaining > 0 then return end
		state.phase = "Mine"
	end
	local result = mine(now, true)
	if result == "Empty" then
		beginTraining(now)
		train()
		state.status ..= " | No matching rocks"
	end
end

local viewport = workspace.CurrentCamera.ViewportSize
local window = WindUI:CreateWindow({
	Title = "Cut a Rock", Author = "Mining assistant", Icon = "pickaxe", Folder = "CutARockHub",
	Size = UDim2.fromOffset(math.min(560, viewport.X - 24), math.min(470, viewport.Y - 70)),
	MinSize = Vector2.new(290, 250), SideBarWidth = 130, Theme = "Dark", HideSearchBar = true,
	OpenButton = {
		Title = "Rock Hub", Enabled = true, Draggable = true, OnlyMobile = false,
		CornerRadius = UDim.new(1, 0), Color = ColorSequence.new(Color3.fromRGB(223, 175, 90)),
	},
})
state.Window = window
host.global.CutARockHub = state
local automation = window:Tab({ Title = "Main", Icon = "pickaxe" })
local filters = window:Tab({ Title = "Mining filters", Icon = "list-filter" })
local economy = window:Tab({ Title = "Economy", Icon = "coins" })
local indexTab = window:Tab({ Title = "Index", Icon = "book-open" })
local settings = window:Tab({ Title = "Settings", Icon = "settings" })
local status = automation:Paragraph({ Title = "Ready" })
state.Controls = {}

local function addToggle(key, title, tab)
	state.flags[key] = false
	state.Controls[key] = (tab or automation):Toggle({ Title = title, Value = false, Callback = function(value)
		local wasEnabled = state.flags[key]
		state.flags[key] = value
		if key == "Train" or key == "Mine" then beginTraining(os.clock()) end
		if key == "Mine" and not value then state.unlockRoom = nil end
		if not value and state.pending and ((key == "Mine" and state.pending.kind == "Mine") or (key == "Collect" and state.pending.kind == "Collect")) then state.pending = nil end
		if wasEnabled and not value and (key == "Train" or key == "Mine") then
			local model, root = character()
			if model then model:PivotTo(root.CFrame * CFrame.new(8, 0, 0)) end
		end
	end })
end
addToggle("Train", "Auto Train")
state.TrainDurationSlider = automation:Slider({ Title = "Training time (seconds)", Step = 1, Value = { Min = 5, Max = 60, Default = 30 }, Callback = function(value)
	local duration = math.clamp(math.floor(tonumber(value) or 30), 5, 60)
	local elapsed = math.max(0, state.trainDuration - state.trainRemaining)
	state.trainDuration = duration
	if state.phase == "Train" then state.trainRemaining = math.max(0, duration - elapsed) end
end })
addToggle("Mine", "Auto Mine")
addToggle("Return", "Auto Return")
addToggle("Cut", "Auto Cut")
addToggle("Collect", "Auto Collect")
addToggle("Sell", "Auto Sell")
addToggle("Upgrade", "Auto Upgrade")
addToggle("Pickaxe", "Auto Pickaxe")
state.RarityDropdown = filters:Dropdown({ Title = "Rarities", Values = rarities, Value = table.clone(rarities), Multi = true, AllowNone = true, Callback = function(values)
	table.clear(state.selected)
	for _, value in values do state.selected[type(value) == "table" and value.Title or value] = true end
end })
local function floorOptions()
	local options = { "Deepest unlocked" }
	for floor = 1, math.max(1, player:GetAttribute("MaximumRoom") or 1) do
		table.insert(options, "Floor " .. floor)
	end
	return options
end
state.FloorDropdown = filters:Dropdown({ Title = "Target floor", Values = floorOptions(), Value = "Deepest unlocked", Callback = function(value)
	state.floorMode = value
	if state.pending and state.pending.kind == "Mine" then state.pending = nil end
end })
connect(player:GetAttributeChangedSignal("MaximumRoom"), function()
	if host.identity then host.identity(8) end
	state.FloorDropdown:Refresh(floorOptions())
	notify("floor", "Floor unlocked", "Deepest unlocked: " .. tostring(player:GetAttribute("MaximumRoom")))
end)
filters:Slider({ Title = "Unlock power threshold", Step = 5, Value = { Min = 10, Max = 100, Default = 80 }, Callback = function(value)
	state.unlockPercent = tonumber(value) or 80
end })

economy:Dropdown({ Title = "Sell mode", Values = { "Duplicates only", "All discovered cores" }, Value = "Duplicates only", Callback = function(value) state.sellMode = value end })
economy:Dropdown({ Title = "Sell rarities", Values = rarities, Value = table.clone(rarities), Multi = true, AllowNone = true, Callback = function(values)
	table.clear(state.sellRarities)
	for _, value in values do state.sellRarities[value] = true end
end })
economy:Dropdown({ Title = "Upgrade targets", Values = { "Machines", "Pocket", "Eyesight" }, Value = { "Machines", "Pocket", "Eyesight" }, Multi = true, AllowNone = true, Callback = function(values)
	table.clear(state.upgradeTargets)
	for _, value in values do state.upgradeTargets[value] = true end
end })

addToggle("Index", "Index Helper", indexTab)
local indexSummary = indexTab:Paragraph({ Title = "Index progress" })
local missingLabel = indexTab:Paragraph({ Title = "Missing materials" })
state.IndexDropdown = indexTab:Dropdown({ Title = "Collection", Values = indexCategories, Value = state.indexCategory, Callback = function(value)
	state.indexCategory = value
	state.indexDirty = true
end })
function state:TargetIndex()
	local category = state.indexCategory
	if not table.find(rarities, category) then notify("index-target", "Index", "This collection is not a regular mining rarity.") return end
	local floor = 0
	local maximum = math.max(1, player:GetAttribute("MaximumRoom") or 1)
	for _, data in state.rocks do
		if data.model.Parent and data.model:GetAttribute("Rarity") == category and data.room <= maximum then floor = math.max(floor, data.room) end
	end
	if floor == 0 then notify("index-target", "Index", "No matching rocks on your unlocked floors.") return end
	state.RarityDropdown:Select({ category })
	state.FloorDropdown:Select("Floor " .. floor)
	notify("index-target", "Mining target updated", category .. " | Floor " .. floor, 0)
end
indexTab:Button({ Title = "Target this rarity", Icon = "crosshair", Callback = function() state:TargetIndex() end })
indexTab:Button({ Title = "Claim available auras", Icon = "sparkles", Callback = function()
	local claimed = "," .. (player:GetAttribute("ToplananAuralar") or "") .. ","
	local count = 0
	for _, category in indexCategories do
		local found, missing = indexProgress(category)
		if found > 0 and #missing == 0 and not claimed:find("," .. category .. ",", 1, true) then
			ReplicatedStorage.AuraTopla:FireServer(category)
			count += 1
		end
	end
	if count == 0 then notify("aura-none", "Index", "No unclaimed auras are available.") end
end })

local function refreshIndex()
	if not state.indexDirty then return end
	state.indexDirty = false
	local complete, total = indexData.Tamamlanan(discoveries)
	local found, missing = indexProgress(state.indexCategory)
	if host.identity then host.identity(8) end
	indexSummary:SetTitle(string.format("Collections: %d/%d | %s: %d/%d", complete, total, state.indexCategory, found, found + #missing))
	missingLabel:SetTitle(#missing == 0 and "Collection complete" or "Missing: " .. table.concat(missing, ", "))
end

function state:Destroy()
	if not self.alive then return end
	self.alive = false
	self.pending = nil
	host.releasePrompt()
	for _, connection in self.connections do connection:Disconnect() end
	table.clear(self.connections)
	if self.worker then task.cancel(self.worker) end
	local model, root = character()
	if model and (self.flags.Train or self.flags.Mine) then model:PivotTo(root.CFrame * CFrame.new(8, 0, 0)) end
	window:Destroy()
	if host.global.CutARockHub == self then host.global.CutARockHub = nil end
end
state.autoAFK = true
settings:Toggle({ Title = "Notifications", Value = true, Callback = function(value) state.notifications = value end })
local VirtualUser = game:GetService("VirtualUser")
state.AFKToggle = settings:Toggle({ Title = "Anti AFK", Value = true, Callback = function(value)
	state.autoAFK = value
end })
connect(player.Idled, function()
	if not state.alive or not state.autoAFK then return end
	local ok, err = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
	if not ok then warn("[Cut a Rock] Anti AFK: " .. tostring(err)) end
end)
function state:StopAll()
	for _, toggle in state.Controls do toggle:Set(false) end
	state.pending = nil
	host.releasePrompt()
	state.status = "Stopped"
end
settings:Button({ Title = "Stop All", Icon = "square", Callback = function() state:StopAll() end })
settings:Button({ Title = "Unload UI", Icon = "x", Callback = function() state:Destroy() end })
settings:Section({ Title = "Credits" })
local function copyLink(url)
	if host.clipboard then
		host.clipboard(url)
		WindUI:Notify({ Title = "Link copied", Content = url, Duration = 3 })
	else
		WindUI:Notify({ Title = "Link", Content = url, Duration = 10 })
	end
end
local telegram = "t.me/arceusxcommunity"
local fetched, text = pcall(function()
	return host.http("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
end)
if fetched and type(text) == "string" then
	local value = text:match("^%s*(.-)%s*$")
	if value:match("^t%.me/[%w_]+$") or value:match("^https://t%.me/[%w_]+$") then
		telegram = value:gsub("^https://", "")
	end
end
state.Telegram = telegram
settings:Button({ Title = telegram, Icon = "send", Callback = function() copyLink("https://" .. telegram) end })
settings:Button({ Title = "WindUI", Icon = "external-link", Callback = function() copyLink("https://github.com/Footagesus/WindUI") end })
window:OnDestroy(function() if state.alive then state:Destroy() end end)
connect(ReplicatedStorage.SellEvent.OnClientEvent, function(action, data)
	if action ~= "Satildi" or not state.salePending then return end
	state.salePending = nil
	if type(data) == "table" and (data.kazanc or 0) > 0 then
		notify("sold", "Auto Sell", tostring(data.adet or "") .. " cores sold for $" .. formatNumber(data.kazanc), 1)
	end
end)
connect(ReplicatedStorage.UpgradeEvent.OnClientEvent, function(action, data, seq)
	local pending = state.purchasePending
	if action ~= "Durum" or not pending or pending.seq ~= seq or (pending.kind ~= "Pocket" and pending.kind ~= "Eyesight") or type(data) ~= "table" then return end
	local attribute = pending.kind == "Pocket" and "PocketLevel" or "Sight"
	if data.attribute ~= attribute or type(data.seviye) ~= "number" then return end
	player:SetAttribute(attribute, data.seviye)
	if type(data.para) == "number" then player.Statlar.Money.Value = data.para end
	if data.seviye > pending.level then confirmPurchase(pending.name .. " upgraded to level " .. data.seviye)
	else state.purchasePending = nil state.nextEconomy = os.clock() + 5 end
end)
connect(ReplicatedStorage.LevelUpMachineEvent.OnClientEvent, function(action, machine, level, price, money, seq)
	local pending = state.purchasePending
	if action ~= "Durum" or not pending or pending.kind ~= "Machine" or pending.seq ~= seq or pending.object ~= machine or type(level) ~= "number" then return end
	machine:SetAttribute("Seviye", level)
	machine:SetAttribute("SonrakiSeviyeFiyati", price)
	if type(money) == "number" then player.Statlar.Money.Value = money end
	if level > pending.level then confirmPurchase(pending.name .. " upgraded to level " .. level)
	else state.purchasePending = nil state.nextEconomy = os.clock() + 5 end
end)
connect(ReplicatedStorage.PickaxeEquipEvent.OnClientEvent, function(action, level, seq)
	local pending = state.purchasePending
	if action == "Durum" and pending and pending.kind == "Equip" and pending.seq == seq and type(level) == "number" then
		player:SetAttribute("KusanilanKazma", level)
		if level == pending.level then confirmPurchase(pending.name .. " equipped")
		else state.purchasePending = nil state.nextEconomy = os.clock() + 5 end
	end
end)
connect(discoveries.ChildAdded, function(discovery)
	state.indexDirty = true
	local category, material = discovery.Name:match("^(.-)|(.+)$")
	if category and category ~= "Tas" then
		notify("discovery-" .. discovery.Name, "New Index discovery", category .. " | " .. material, 30)
		local found, missing = indexProgress(category)
		if found > 0 and #missing == 0 then notify("complete-" .. category, "Collection complete", category .. " aura is ready to claim.", 30) end
	end
end)
connect(discoveries.ChildRemoved, function() state.indexDirty = true end)
connect(player:GetAttributeChangedSignal("ToplananAuralar"), function()
	state.indexDirty = true
	notify("aura-claimed", "Index", "Aura collection updated.", 2)
end)
connect(ReplicatedStorage.LimitedBelirdi.OnClientEvent, function()
	notify("limited-rock", "Limited rock", "A limited rock has spawned.", 10)
end)
connect(ReplicatedStorage.CepDoluEvent.OnClientEvent, function() state.returnRequested = true end)
connect(player.CharacterAdded, function()
	state.pending = nil
	host.releasePrompt()
	state.unlockRoom = nil
	state.nextAction = os.clock() + 1
	beginTraining(os.clock())
end)
connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function()
	local size = workspace.CurrentCamera.ViewportSize
	window:SetSize(UDim2.fromOffset(math.max(290, math.min(560, size.X - 24)), math.max(250, math.min(470, size.Y - 70))))
	window:SetToTheCenter()
end)
refreshMachines()
window:SelectTab(1)

state.worker = task.spawn(function()
	local nextRefresh, nextStatus = 0, 0
	while state.alive do
		local now = os.clock()
		local ok, err = xpcall(function()
			if now >= nextRefresh then refreshMachines() nextRefresh = now + 3 end
			if now >= state.nextAction and character() then
				if not state.pending and not state.unlockRoom then processEconomy(now) end
				if state.pending then
					local pending = state.pending
					state.pending = nil
					local prompt = pending.prompt
					if prompt.Parent and prompt.Enabled then
						state.retry[prompt] = now + 4
						host.prompt(prompt)
						state.nextAction = os.clock() + math.max(0.4, prompt.HoldDuration + 0.15)
					end
				elseif state.flags.Train and state.flags.Mine then
					runCycle(now)
				elseif state.flags.Mine and state.unlockRoom then
					mine(now)
				elseif state.flags.Return and (pocketFull() or state.returnRequested) then
					state.returnRequested = false
					returnHome()
				elseif not processMachines(now) then
					if state.flags.Mine then mine(now)
					elseif state.flags.Train then train()
					else state.status = "Idle" end
				end
			end
			if now >= nextStatus then
				nextStatus = now + 1
				if host.identity then host.identity(8) end
				refreshIndex()
				status:SetTitle(state.status)
				status:SetDesc(string.format("Power: %s  |  Pocket: %d  |  Floor: %d", tostring(math.floor(player:GetAttribute("Power") or 0)), #pocket:GetChildren(), player:GetAttribute("MaximumRoom") or 0))
			end
		end, debug.traceback)
		if not ok then
			warn("[Cut a Rock] " .. tostring(err))
			state.status = "Retrying after an error"
			state.nextAction = os.clock() + 2
		end
		task.wait(0.15)
	end
end)
print("[Cut a Rock] Ready. Mining, economy and Index helper loaded.")

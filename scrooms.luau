local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

if game.GameId ~= 10292064735 then
	warn("Scrooms: join SCROOMS before running this script.")
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local registry = require(ReplicatedStorage.Client.Core.Registry)
local deadline = os.clock() + 20
while not (registry.C.Minigame and registry.C.Inventory and registry.C.Data and registry.C.Input and registry.C.Settings and registry.C.Data:IsReady()) do
	if os.clock() > deadline then
		warn("Scrooms: the game is still loading. Run the script again.")
		return
	end
	task.wait(0.2)
end

local host = {
	environment = if type(getgenv) == "function" then getgenv() else _G,
	objects = if type(getgc) == "function" then getgc else nil,
	fire = if type(firesignal) == "function" then firesignal else nil,
	connections = if type(getconnections) == "function" then getconnections else nil,
	read = if type(readfile) == "function" then readfile else nil,
	write = if type(writefile) == "function" then writefile else nil,
	folder = if type(makefolder) == "function" then makefolder else nil,
	isFolder = if type(isfolder) == "function" then isfolder else nil,
	exists = if type(isfile) == "function" then isfile else nil,
	uiParent = CoreGui,
}
if type(gethui) == "function" then
	local ok, container = pcall(gethui)
	if ok and typeof(container) == "Instance" then host.uiParent = container end
end

local previous = host.environment.ScroomsHub
if type(previous) == "table" and type(previous.Destroy) == "function" then previous.Destroy() end
for _, container in { playerGui, host.uiParent } do
	local oldGui = container:FindFirstChild("ScroomsHub")
	if oldGui then oldGui:Destroy() end
end

host.environment.__ScroomsHubSessions = host.environment.__ScroomsHubSessions or {}
local scope = tostring(game.GameId) .. "_" .. tostring(player.UserId)
local shared = host.environment.__ScroomsHubSessions[scope] or {}
host.environment.__ScroomsHubSessions[scope] = shared
local minigame = registry.C.Minigame
local inventory = registry.C.Inventory
local data = registry.C.Data
local definitions = require(ReplicatedStorage.Shared.Data.Items)
local sellingRules = require(ReplicatedStorage.Shared.Utils.Selling)
local questRules = require(ReplicatedStorage.Shared.Utils.Quest)
local dialogueRemote = ReplicatedStorage.Network.Remotes.Dialogue
local inventoryRemote = ReplicatedStorage.Network.Remotes.Inventory
local token = "ScroomsHub_" .. HttpService:GenerateGUID(false)
local rarityRows = {
	{ "common", "Common", "sellCommon" },
	{ "uncommon", "Uncommon", "sellUncommon" },
	{ "rare", "Rare", "sellRare" },
	{ "wondrous", "Wondrous", "sellWondrous" },
	{ "fabled", "Fabled", "sellFabled" },
	{ "eversung", "Eversung", "sellEversung" },
	{ "shard", "Shard", "sellShard" },
	{ "songsheet", "Songsheet", "sellSongsheet" },
}
local rarityKeys = {}
for _, row in rarityRows do rarityKeys[row[1]] = true end
local defaultFilters = {
	keepQuestItems = true,
	keepFavorites = true,
	keepMutations = false,
	keepVariants = false,
	keepRarities = {},
}
local function copyFilters(value)
	local copy = {}
	for key, fallback in defaultFilters do
		if key ~= "keepRarities" then
			copy[key] = if type(value) == "table" and type(value[key]) == "boolean" then value[key] else fallback
		end
	end
	copy.keepRarities = {}
	if type(value) == "table" and type(value.keepRarities) == "table" then
		for key in rarityKeys do copy.keepRarities[key] = value.keepRarities[key] == true end
	end
	return copy
end

local storageReady = host.read ~= nil and host.write ~= nil and host.folder ~= nil
if storageReady then
	local ok = pcall(function()
		if not host.isFolder or not host.isFolder("ScroomsHub") then host.folder("ScroomsHub") end
	end)
	storageReady = ok
end
local function readDocument(path)
	if not storageReady then return { version = 1, scopes = {} } end
	local ok, result = pcall(function()
		if host.exists and not host.exists(path) then return nil end
		return HttpService:JSONDecode(host.read(path))
	end)
	if ok and type(result) == "table" and type(result.scopes) == "table" then return result end
	return { version = 1, scopes = {} }
end
local settingsDocument = readDocument("ScroomsHub/settings.json")
local journalDocument = readDocument("ScroomsHub/sale-recovery.json")
local saved = shared.config or settingsDocument.scopes[scope] or {}
local function normalizedPosition(value, fallback)
	if type(value) ~= "table" then return table.clone(fallback) end
	local x, y = value.x, value.y
	if type(x) ~= "number" or x ~= x or type(y) ~= "number" or y ~= y then return table.clone(fallback) end
	return { x = math.clamp(x, 0, 1), y = math.clamp(y, 0, 1) }
end
local state = {
	alive = true,
	instantCatch = false,
	autoMinigame = false,
	autoStart = false,
	selling = false,
	recovering = true,
	recoveryFailed = false,
	minimized = false,
	visible = true,
	filtersOpen = false,
	filters = copyFilters(saved.filters),
	windowPosition = normalizedPosition(saved.windowPosition, { x = 0.04, y = 0.25 }),
	floatPosition = normalizedPosition(saved.floatPosition, { x = 0.04, y = 0.5 }),
	stage = nil,
	game = nil,
	caught = 0,
	message = "",
	messageUntil = 0,
	messageError = false,
	nextCast = 0,
	saveAt = nil,
	layoutDirty = true,
	viewDirty = true,
}
local api = {}
local connections, patches, tweens = {}, {}, {}
local gui
local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end
local function message(text, isError)
	state.message, state.messageUntil, state.messageError = text, os.clock() + 5, isError == true
end
local function saveConfig()
	local config = {
		filters = copyFilters(state.filters),
		windowPosition = table.clone(state.windowPosition),
		floatPosition = table.clone(state.floatPosition),
	}
	shared.config = config
	if storageReady then
		settingsDocument.scopes[scope] = config
		local ok = pcall(host.write, "ScroomsHub/settings.json", HttpService:JSONEncode(settingsDocument))
		if not ok then message("Settings are saved for this session only", true) end
	end
	state.saveAt = nil
end
local function journalValid(journal)
	if type(journal) ~= "table" or type(journal.favorites) ~= "table" or type(journal.settings) ~= "table" then return false end
	for uid, value in journal.favorites do
		if type(uid) ~= "string" or type(value) ~= "boolean" then return false end
	end
	local allowed = {}
	for _, row in rarityRows do allowed[row[3]] = true end
	for key, value in journal.settings do
		if not allowed[key] or type(value) ~= "boolean" then return false end
	end
	return true
end
local function currentJournal()
	local journal = shared.journal or journalDocument.scopes[scope]
	return if journalValid(journal) then journal else nil
end
local function writeJournal(journal)
	shared.journal = journal
	journalDocument.scopes[scope] = journal
	if not storageReady then return true end
	return pcall(host.write, "ScroomsHub/sale-recovery.json", HttpService:JSONEncode(journalDocument))
end
local function items()
	return data:Get({ "Inventory", "Items" }) or {}
end
local lastNetwork = shared.lastNetwork or 0
local lastFavoriteNetwork = shared.lastFavoriteNetwork or 0
local function paceNetwork()
	local remaining = 0.125 - (os.clock() - lastNetwork)
	if remaining > 0 then task.wait(remaining) end
	lastNetwork = os.clock()
	shared.lastNetwork = lastNetwork
end
local function setFavorite(uid, value)
	local item = items()[uid]
	if not item or (item.favorited == true) == value then return true end
	local remaining = 1 - (os.clock() - lastFavoriteNetwork)
	if remaining > 0 then task.wait(remaining) end
	paceNetwork()
	inventoryRemote:FireServer("toggleFavorite", { uid = uid })
	lastFavoriteNetwork = os.clock()
	shared.lastFavoriteNetwork = lastFavoriteNetwork
	local endAt = os.clock() + 4
	repeat
		task.wait(0.05)
		item = items()[uid]
		if not item or (item.favorited == true) == value then return true end
	until os.clock() >= endAt
	return false
end
local function setSaleSetting(name, value)
	if registry.C.Settings:Get(name) == value then return true end
	paceNetwork()
	registry.C.Settings:Set(name, value)
	local endAt = os.clock() + 4
	repeat
		task.wait(0.05)
		if data:Get({ "Settings", name }) == value then return true end
	until os.clock() >= endAt
	return false
end
local function restoreJournal(journal)
	local complete = true
	for uid, value in journal.favorites do
		local ok, restored = pcall(setFavorite, uid, value)
		if not ok or not restored then complete = false end
	end
	for name, value in journal.settings do
		local ok, restored = pcall(setSaleSetting, name, value)
		if not ok or not restored then complete = false end
	end
	if complete then
		task.wait(0.2)
		for uid, value in journal.favorites do
			local item = items()[uid]
			if item and (item.favorited == true) ~= value then complete = false end
		end
		for name, value in journal.settings do
			if registry.C.Settings:Get(name) ~= value then complete = false end
		end
	end
	if complete then return writeJournal(nil) end
	return false
end
local function recoverSale()
	state.recovering = true
	while shared.saleRunning do
		if shared.saleWorker and coroutine.status(shared.saleWorker) == "dead" then
			shared.saleRunning, shared.saleWorker = nil, nil
			break
		end
		if not state.alive then return end
		task.wait(0.1)
	end
	if not state.alive then return end
	local journal = currentJournal()
	if journal then
		shared.saleRunning = token
		minigame:SetCastBlock(token, true)
		local ok, restored = pcall(restoreJournal, journal)
		minigame:SetCastBlock(token, false)
		shared.saleRunning = nil
		if not ok or not restored then
			state.recovering = true
			state.recoveryFailed = true
			message("Recovery needed. Run the script again", true)
			return
		end
		message("Sale settings restored")
	end
	state.recovering = false
	state.recoveryFailed = false
end

local function restorePatches()
	for index = #patches, 1, -1 do
		local entry = patches[index]
		if rawget(entry.object, entry.key) == entry.replacement then rawset(entry.object, entry.key, entry.original) end
	end
	table.clear(patches)
end
local function patch(object, key, replacement)
	table.insert(patches, { object = object, key = key, original = rawget(object, key), replacement = replacement })
	rawset(object, key, replacement)
end
local function beginPending()
	if shared.pending then return end
	local before = {}
	for uid in items() do before[uid] = true end
	shared.pending = { beforeItems = before, beforeCount = player:GetAttribute("catches") or 0, startedAt = os.clock() }
	minigame:SetCastBlock(token .. "_pending", true)
end
local function finishPending()
	shared.pending = nil
	minigame:SetCastBlock(token .. "_pending", false)
	state.nextCast = os.clock() + 0.35
end
local function assistStage(stage, object)
	restorePatches()
	if not (state.alive and object and object._jan) then return end
	if stage == "main" then
		local originalWin = object._winMinigame
		patch(object, "_winMinigame", function(self)
			if state.alive then beginPending() end
			return originalWin(self)
		end)
	end
	if state.instantCatch then
		task.defer(function()
			if not state.alive or not state.instantCatch or state.game ~= object or not object._jan then return end
			if stage == "ring" and not object._complete then
				object.OnComplete:Fire(1)
			elseif stage == "tune" then
				object._elapsed = object._targetTime
			elseif stage == "main" and not object._scroomsClaimed then
				object._scroomsClaimed = true
				beginPending()
				object:SetProgress(1)
				object:_winMinigame()
			end
		end)
	elseif state.autoMinigame then
		if stage == "ring" and not object._complete then
			task.defer(function()
				if state.alive and state.autoMinigame and not state.instantCatch and state.game == object and object._jan and not object._complete then
					object._tween:Cancel()
					object._ui.Ring.Tick.Rotation = object._targetRot
					object:Complete()
				end
			end)
		elseif stage == "tune" then
			local original = object._step
			patch(object, "_step", function(self, deltaTime)
				self._needleX, self._needleVel = self._target, 0
				return original(self, deltaTime)
			end)
		elseif stage == "main" then
			for _, tracked in { object._marker, object._item } do
				patch(tracked, "Step", function(self)
					local low, high = object._zone:GetBounds()
					self._pos, self._vel = (low + high) / 2, 0
					self._frame.Position = UDim2.fromScale(self._pos, self._y)
				end)
			end
		end
	end
end
local function recoverStage()
	if state.game and state.game._jan or not host.objects then return end
	for _, object in host.objects(true) do
		if type(object) ~= "table" or not rawget(object, "_jan") then continue end
		local ui = rawget(object, "_ui")
		if typeof(ui) ~= "Instance" or not ui:IsDescendantOf(playerGui) then continue end
		local stage = if rawget(object, "_targetRot") then "ring"
			elseif rawget(object, "_targetTime") then "tune"
			elseif rawget(object, "_zone") and rawget(object, "_item") then "main" else nil
		if stage then state.stage, state.game = stage, object return end
	end
end
function api.SetInstantCatch(value)
	if not state.alive then return false end
	state.instantCatch, state.viewDirty = value == true, true
	recoverStage()
	assistStage(state.stage, state.game)
	return true
end
function api.SetAutoMinigame(value)
	if not state.alive then return false end
	state.autoMinigame, state.viewDirty = value == true, true
	recoverStage()
	assistStage(state.stage, state.game)
	return true
end
function api.SetAutoStart(value)
	if not state.alive then return false end
	if value and not (host.fire or host.connections) then message("Input support is unavailable", true) return false end
	state.autoStart, state.viewDirty = value == true, true
	state.nextCast = os.clock() + 0.3
	return true
end
connect(minigame.StageChanged, function(stage, object)
	state.stage, state.game = stage, object
	if not stage then state.nextCast = os.clock() + 1 end
	assistStage(stage, object)
end)
connect(minigame.Caught, function()
	state.caught += 1
	if shared.pending then finishPending() end
end)
connect(ReplicatedStorage.Network.Remotes.Minigame.OnClientEvent, function(action)
	if action == "refused" and shared.pending then
		finishPending()
		message("Catch refused. Waiting to retry", true)
		state.nextCast = os.clock() + 2
	end
end)
recoverStage()

local function protectedItem(uid, item, filters, reserved)
	local definition = definitions[item.id]
	return (filters.keepQuestItems and reserved[uid] == true)
		or (filters.keepFavorites and item.favorited == true)
		or (definition and filters.keepRarities[definition.rarity] == true)
		or (filters.keepMutations and item.mutation ~= nil and item.mutation ~= "none")
		or (filters.keepVariants and #(item.variants or {}) > 0)
end
local function selection(filters)
	local reserved = if filters.keepQuestItems then questRules:GetQuestStock(function(path) return data:Get(path) end) else {}
	local targets, kept = {}, {}
	for uid, item in items() do
		if sellingRules:GetPrice(item) then
			if protectedItem(uid, item, filters, reserved) then kept[uid] = true else targets[uid] = true end
		end
	end
	return targets, kept
end
local function countEntries(value)
	local count = 0
	for _ in value do count += 1 end
	return count
end
local merchants = { julian_sg = true, gregory_bc = true, pip_sm = true, justin_tt = true, drew_ug = true }
local function nearestMerchant(root)
	local world = workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("NPCs")
	local nearest, distance = nil, math.huge
	if folder then
		for _, npc in folder:GetDescendants() do
			if npc:IsA("Model") and merchants[npc.Name] then
				local length = (npc:GetPivot().Position - root.Position).Magnitude
				if length < distance then nearest, distance = npc, length end
			end
		end
	end
	return nearest
end
function api.SetSaleFilters(value)
	if not state.alive or state.selling or state.recovering or type(value) ~= "table" then return false end
	local merged = copyFilters(state.filters)
	for key in defaultFilters do
		if key == "keepRarities" then
			if type(value[key]) == "table" then merged[key] = table.clone(value[key]) end
		elseif type(value[key]) == "boolean" then merged[key] = value[key] end
	end
	state.filters = copyFilters(merged)
	state.viewDirty, state.saveAt = true, os.clock() + 0.5
	return true
end
function api.PreviewSale()
	local targets, kept = selection(state.filters)
	return { sell = countEntries(targets), keep = countEntries(kept) }
end
function api.SellAll()
	if not state.alive or state.selling or state.recovering or shared.saleRunning then return false end
	local filters = copyFilters(state.filters)
	local targets = selection(filters)
	if not next(targets) and not minigame.InSession and not shared.pending then
		message("Nothing to sell. Protected items are kept")
		return false
	end
	state.selling = true
	minigame:SetCastBlock(token .. "_sale", true)
	shared.saleRunning = token
	shared.saleWorker = task.defer(function()
		local root, origin, previousItem, equipped, journal, moved
		local ok, result = xpcall(function()
			local waitUntil = os.clock() + 90
			while state.alive and (minigame.InSession or shared.pending) and os.clock() < waitUntil do task.wait(0.1) end
			if not state.alive then return "Sale cancelled" end
			if minigame.InSession or shared.pending then return "Finish the catch and try again" end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			root = registry.C.Character:GetRoot()
			if not root or not humanoid or humanoid.Health <= 0 then return "Wait for your character" end
			local merchant = nearestMerchant(root)
			if not merchant then return "No merchant loaded nearby" end
			targets = selection(filters)
			if not next(targets) then return "Nothing to sell. Protected items are kept" end
			journal = { settings = {}, favorites = {} }
			local desiredSettings, desiredFavorites = {}, {}
			for _, row in rarityRows do
				local value = not filters.keepRarities[row[1]]
				local original = registry.C.Settings:Get(row[3])
				if type(original) == "boolean" and original ~= value then
					journal.settings[row[3]], desiredSettings[row[3]] = original, value
				end
			end
			for uid, item in items() do
				local definition = definitions[item.id]
				if not sellingRules:GetPrice(item) or (definition and filters.keepRarities[definition.rarity]) then continue end
				local special = (filters.keepMutations and item.mutation ~= nil and item.mutation ~= "none")
					or (filters.keepVariants and #(item.variants or {}) > 0)
				local original = item.favorited == true
				local desired = if special then true elseif not filters.keepFavorites then false else original
				if original ~= desired then journal.favorites[uid], desiredFavorites[uid] = original, desired end
			end
			if not writeJournal(journal) then error("Could not save the recovery journal") end
			for uid, value in desiredFavorites do
				if not state.alive then return "Sale cancelled" end
				state.salePhase = "Protecting inventory..."
				if not setFavorite(uid, value) then error("Could not confirm item protection") end
			end
			for name, value in desiredSettings do
				if not state.alive then return "Sale cancelled" end
				state.salePhase = "Applying sale filters..."
				if not setSaleSetting(name, value) then error("Could not confirm sale filters") end
			end
			for uid, value in desiredFavorites do
				local item = items()[uid]
				if item and (item.favorited == true) ~= value then error("Item protection changed. Sale cancelled") end
			end
			if not state.alive then return "Sale cancelled" end
			origin, previousItem, equipped = root.CFrame, inventory:GetEquipped(), true
			local beforeChimes = player:GetAttribute("chimes") or 0
			inventory:Equip(nil)
			if (root.Position - merchant:GetPivot().Position).Magnitude > 10 then
				moved = true
				root.CFrame = merchant:GetPivot() * CFrame.new(0, 0, -5)
				root.AssemblyLinearVelocity = Vector3.zero
			end
			task.wait(0.65)
			if not state.alive or registry.C.Character:GetRoot() ~= root or humanoid.Health <= 0 then return "Sale cancelled" end
			local node = if filters.keepQuestItems then "sellAllKeepDone" else "sellAllDone"
			state.salePhase = "Selling inventory..."
			paceNetwork()
			dialogueRemote:FireServer("nodeAction", { npc = merchant.Name, node = node })
			local endAt, sold = os.clock() + 4, 0
			repeat
				task.wait(0.1)
				sold = 0
				local current = items()
				for uid in targets do if not current[uid] then sold += 1 end end
			until sold >= countEntries(targets) or os.clock() >= endAt
			if sold <= 0 then return "Sale refused. Try again near a merchant" end
			return string.format("Sold %d items | +%d chimes", sold, (player:GetAttribute("chimes") or beforeChimes) - beforeChimes)
		end, debug.traceback)
		local restored = true
		if journal then
			state.salePhase = "Restoring sale settings..."
			local success, completed = pcall(restoreJournal, journal)
			restored = success and completed == true
		end
		local returned, returnError = pcall(function()
			if root and root.Parent and registry.C.Character:GetRoot() == root then
				if moved and origin then
					root.CFrame = origin
					root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
				end
				if equipped then inventory:Equip(if previousItem and inventory.Cache[previousItem] then previousItem else nil) end
			end
		end)
		minigame:SetCastBlock(token .. "_sale", false)
		state.selling, state.nextCast = false, os.clock() + 1.2
		state.salePhase = nil
		if shared.saleRunning == token then shared.saleRunning, shared.saleWorker = nil, nil end
		if not restored then
			state.recovering = true
			state.recoveryFailed = true
			message("Recovery needed. Run the script again", true)
		elseif not returned then
			message("Sale ended. Check your position", true)
		else
			message(if ok then result or "Ready" else "Sale failed. Try again", not ok)
		end
		if not ok then warn("Scrooms: " .. tostring(result)) end
		if not returned then warn("Scrooms: " .. tostring(returnError)) end
	end)
	return true
end

local theme = {
	surface = Color3.fromRGB(25, 28, 32),
	row = Color3.fromRGB(35, 39, 44),
	border = Color3.fromRGB(57, 63, 68),
	text = Color3.fromRGB(240, 242, 239),
	muted = Color3.fromRGB(157, 166, 166),
	accent = Color3.fromRGB(155, 188, 162),
	error = Color3.fromRGB(231, 151, 137),
	radius = 6,
}
local function create(className, properties, parent)
	local object = Instance.new(className)
	if object:IsA("ScreenGui") or object:IsA("GuiButton") then object:SetAttribute("NoScaleTrack", true) end
	if object:IsA("GuiButton") then object:SetAttribute("NoAudioTrack", true) end
	for key, value in properties do object[key] = value end
	object.Parent = parent
	return object
end
local function round(object, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or theme.radius) }, object)
end
local function animate(object, properties)
	if tweens[object] then tweens[object]:Cancel() end
	local tween = TweenService:Create(object, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
	tweens[object] = tween
	tween:Play()
end
local function label(parent, name, text, position, size, textSize, color)
	return create("TextLabel", {
		Name = name, Text = text, Position = position, Size = size,
		BackgroundTransparency = 1, TextColor3 = color or theme.text,
		TextSize = textSize or 14, Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
end

gui = create("ScreenGui", {
	Name = "ScroomsHub", ResetOnSpawn = false, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 90,
}, host.uiParent)
local safeArea = create("Frame", {
	Name = "SafeArea", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
}, gui)
local window = create("Frame", {
	Name = "Window", BackgroundTransparency = 1, Size = UDim2.fromOffset(340, 300),
}, safeArea)
local panel = create("Frame", {
	Name = "Panel", Size = UDim2.fromScale(1, 1), BackgroundColor3 = theme.surface,
	BorderSizePixel = 0, Active = true,
}, window)
round(panel)
create("UIStroke", { Color = theme.border, Thickness = 1 }, panel)
local header = create("Frame", {
	Name = "Header", Size = UDim2.new(1, -88, 0, 44), BackgroundTransparency = 1, Active = true,
}, panel)
label(header, "Title", "Scrooms", UDim2.fromOffset(14, 0), UDim2.new(1, -14, 1, 0), 18)
local function headerButton(name, text, offset)
	return create("TextButton", {
		Name = name, Text = text, Position = UDim2.new(1, offset, 0, 0),
		Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1,
		TextSize = 22, TextColor3 = theme.muted, Font = Enum.Font.Gotham,
		AutoButtonColor = false, Selectable = true,
	}, panel)
end
local minimizeButton = headerButton("Minimize", "-", -88)
local closeButton = headerButton("Close", "x", -44)
local body = create("ScrollingFrame", {
	Name = "Controls", Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 0, 172),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
	ScrollBarImageColor3 = theme.muted, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)
local saleRow = create("Frame", {
	Name = "SaleRow", Size = UDim2.new(1, -24, 0, 44), BackgroundTransparency = 1,
}, panel)
local filterButton = create("TextButton", {
	Name = "Filters", Text = "", Size = UDim2.fromOffset(44, 44),
	BackgroundColor3 = theme.row, BorderSizePixel = 0, AutoButtonColor = false, Selectable = true,
}, saleRow)
round(filterButton)
local chevron = label(filterButton, "Chevron", ">", UDim2.new(), UDim2.fromScale(1, 1), 24, theme.muted)
chevron.TextXAlignment = Enum.TextXAlignment.Center
chevron.Rotation = 90
local sellButton = create("TextButton", {
	Name = "SellAll", Text = "Sell inventory", Position = UDim2.fromOffset(52, 0),
	Size = UDim2.new(1, -52, 1, 0), BackgroundColor3 = theme.accent, BorderSizePixel = 0,
	TextSize = 14, TextColor3 = theme.surface, Font = Enum.Font.GothamMedium,
	AutoButtonColor = true, Selectable = true,
}, saleRow)
round(sellButton)
local status = label(panel, "Status", "Ready", UDim2.new(), UDim2.new(1, -28, 0, 18), 13, theme.muted)
status.Font = Enum.Font.Gotham
status.TextTruncate = Enum.TextTruncate.AtEnd
local drawer = create("Frame", {
	Name = "SaleFilters", BackgroundColor3 = theme.surface, BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 0), Visible = false, ClipsDescendants = true, Active = true,
}, window)
round(drawer)
create("UIStroke", { Color = theme.border, Thickness = 1 }, drawer)
label(drawer, "Title", "Sale filters", UDim2.fromOffset(12, 0), UDim2.new(1, -24, 0, 32), 14)
local filterList = create("ScrollingFrame", {
	Name = "Options", Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 1, -44),
	BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 2, ScrollBarImageColor3 = theme.muted,
}, drawer)
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, filterList)
local floatingButton = create("TextButton", {
	Name = "FloatingButton", Text = "S", Size = UDim2.fromOffset(48, 48),
	BackgroundColor3 = theme.surface, BorderSizePixel = 0, Visible = false,
	TextColor3 = theme.accent, TextSize = 18, Font = Enum.Font.GothamMedium,
	AutoButtonColor = false, Selectable = true,
}, safeArea)
round(floatingButton)
create("UIStroke", { Color = theme.border, Thickness = 1 }, floatingButton)
local controls = {}
local function toggle(parent, name, text, order, getter, setter, isFilter)
	local button = create("TextButton", {
		Name = name, Text = "", Size = UDim2.new(1, -4, 0, 46), LayoutOrder = order,
		BackgroundColor3 = theme.row, BorderSizePixel = 0, AutoButtonColor = false, Selectable = true,
	}, parent)
	round(button)
	label(button, "Label", text, UDim2.fromOffset(12, 0), UDim2.new(1, -104, 1, 0), 14)
	local stateLabel = label(button, "Value", "Off", UDim2.new(1, -94, 0, 0), UDim2.new(0, 32, 1, 0), 12, theme.muted)
	stateLabel.TextXAlignment = Enum.TextXAlignment.Center
	local track = create("Frame", {
		Name = "Track", Position = UDim2.new(1, -52, 0.5, -12), Size = UDim2.fromOffset(40, 24),
		BackgroundColor3 = theme.border, BorderSizePixel = 0,
	}, button)
	round(track)
	local thumb = create("Frame", {
		Name = "Thumb", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = theme.text, BorderSizePixel = 0,
	}, track)
	round(thumb, 4)
	table.insert(controls, {
		button = button, track = track, thumb = thumb, valueLabel = stateLabel,
		getter = getter, isFilter = isFilter,
	})
	connect(button.Activated, function()
		if state.alive and not (isFilter and (state.selling or state.recovering)) then setter(not getter()) end
	end)
end
toggle(body, "InstantCatch", "Instant catch", 1, function() return state.instantCatch end, api.SetInstantCatch)
local divider = create("Frame", {
	Name = "Divider", Size = UDim2.new(1, -4, 0, 9), LayoutOrder = 2, BackgroundTransparency = 1,
}, body)
create("Frame", {
	Size = UDim2.new(1, -16, 0, 1), Position = UDim2.fromOffset(8, 4),
	BorderSizePixel = 0, BackgroundColor3 = theme.border,
}, divider)
toggle(body, "AutoMinigame", "Auto minigame", 3, function() return state.autoMinigame end, api.SetAutoMinigame)
toggle(body, "AutoStart", "Auto start catching", 4, function() return state.autoStart end, api.SetAutoStart)
local filterRows = {
	{ "keepQuestItems", "Keep quest items" }, { "keepFavorites", "Keep favorites" },
	{ "keepMutations", "Keep mutations" }, { "keepVariants", "Keep variants" },
}
for index, row in filterRows do
	local key = row[1]
	toggle(filterList, key, row[2], index, function() return state.filters[key] end, function(value)
		api.SetSaleFilters({ [key] = value })
	end, true)
end
local rarityLabel = label(filterList, "RarityTitle", "Keep rarities", UDim2.new(), UDim2.new(1, -4, 0, 30), 14, theme.muted)
rarityLabel.LayoutOrder = 5
for index, row in rarityRows do
	local key = row[1]
	toggle(filterList, "Keep_" .. key, row[2], index + 5, function() return state.filters.keepRarities[key] == true end, function(value)
		local selected = table.clone(state.filters.keepRarities)
		selected[key] = value
		api.SetSaleFilters({ keepRarities = selected })
	end, true)
end

function api.SetFiltersOpen(value)
	if not state.alive then return false end
	state.filtersOpen = value == true
	state.layoutDirty, state.viewDirty = true, true
	return true
end
function api.SetMinimized(value)
	if not state.alive then return false end
	state.minimized, state.visible = value == true, true
	state.layoutDirty, state.viewDirty = true, true
	state.drag = nil
	return true
end
function api.SetVisible(value)
	if not state.alive then return false end
	state.visible, state.viewDirty = value == true, true
	state.layoutDirty = true
	return true
end

local geometry = {}
local function place(normalized, bounds, size)
	local tx, ty = math.max(0, bounds.X - size.X - 16), math.max(0, bounds.Y - size.Y - 16)
	return 8 + normalized.x * tx, 8 + normalized.y * ty, tx, ty
end
local function applyLayout(animateChanges)
	local bounds = safeArea.AbsoluteSize
	if bounds.X <= 0 or bounds.Y <= 0 then return end
	local width = math.max(160, math.min(340, bounds.X - 16))
	local maxHeight = math.max(128, bounds.Y - 16)
	local drawerHeight = if state.filtersOpen then math.min(260, math.max(60, maxHeight - 176)) else 0
	local gap = if state.filtersOpen then 4 else 0
	local mainHeight = math.max(128, math.min(300, maxHeight - drawerHeight - gap))
	local bodyHeight = math.max(1, mainHeight - 128)
	local totalHeight = mainHeight + drawerHeight + gap
	local x, y, tx, ty = place(state.windowPosition, bounds, Vector2.new(width, totalHeight))
	local fx, fy, ftx, fty = place(state.floatPosition, bounds, Vector2.new(48, 48))
	geometry = { x = x, y = y, tx = tx, ty = ty, fx = fx, fy = fy, ftx = ftx, fty = fty }
	window.Size = UDim2.fromOffset(width, totalHeight)
	window.Position = UDim2.fromOffset(x, y)
	floatingButton.Position = UDim2.fromOffset(fx, fy)
	local changes = {
		{ panel, { Size = UDim2.fromOffset(width, mainHeight) } },
		{ body, { Size = UDim2.new(1, -24, 0, bodyHeight) } },
		{ saleRow, { Position = UDim2.fromOffset(12, 52 + bodyHeight) } },
		{ status, { Position = UDim2.fromOffset(14, 100 + bodyHeight) } },
		{ drawer, { Position = UDim2.fromOffset(0, mainHeight + gap), Size = UDim2.fromOffset(width, drawerHeight) } },
	}
	for _, change in changes do
		if animateChanges then animate(change[1], change[2])
		else
			if tweens[change[1]] then tweens[change[1]]:Cancel() end
			for key, value in change[2] do change[1][key] = value end
		end
	end
	if animateChanges then animate(chevron, { Rotation = if state.filtersOpen then -90 else 90 })
	else chevron.Rotation = if state.filtersOpen then -90 else 90 end
	state.layoutDirty = false
end
local function beginDrag(kind, input)
	if state.drag or not state.visible then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	state.drag = {
		kind = kind, input = input, start = input.Position, moved = false,
		x = if kind == "float" then geometry.fx or 8 else geometry.x or 8,
		y = if kind == "float" then geometry.fy or 8 else geometry.y or 8,
	}
end
connect(header.InputBegan, function(input) beginDrag("window", input) end)
connect(floatingButton.InputBegan, function(input) beginDrag("float", input) end)
connect(UserInputService.InputChanged, function(input)
	local drag = state.drag
	if not drag then return end
	if input ~= drag.input and not (drag.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then return end
	local delta = input.Position - drag.start
	if delta.Magnitude > 6 then drag.moved = true end
	if not drag.moved then return end
	local tx = if drag.kind == "float" then geometry.ftx or 0 else geometry.tx or 0
	local ty = if drag.kind == "float" then geometry.fty or 0 else geometry.ty or 0
	local position = {
		x = if tx > 0 then math.clamp((drag.x + delta.X - 8) / tx, 0, 1) else 0,
		y = if ty > 0 then math.clamp((drag.y + delta.Y - 8) / ty, 0, 1) else 0,
	}
	if drag.kind == "float" then state.floatPosition = position else state.windowPosition = position end
	state.layoutDirty = true
end)
connect(UserInputService.InputEnded, function(input)
	local drag = state.drag
	if drag and input == drag.input then
		if drag.kind == "float" and drag.moved then state.suppressFloatClickUntil = os.clock() + 0.25 end
		state.drag = nil
		state.saveAt = os.clock()
	end
end)
connect(floatingButton.Activated, function()
	if (state.drag and state.drag.moved) or os.clock() < (state.suppressFloatClickUntil or 0) then return end
	api.SetMinimized(false)
end)
connect(minimizeButton.Activated, function() api.SetMinimized(true) end)
connect(filterButton.Activated, function() api.SetFiltersOpen(not state.filtersOpen) end)
connect(sellButton.Activated, api.SellAll)
connect(UserInputService.InputBegan, function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.RightControl then api.SetMinimized(not state.minimized) end
end)
connect(safeArea:GetPropertyChangedSignal("AbsoluteSize"), function() state.layoutDirty = true end)

local function cast()
	local action = registry.C.Input.Actions.Cast
	if host.fire then host.fire(action.Pressed)
	elseif host.connections then
		for _, connection in host.connections(action.Pressed) do
			if connection.Enabled then connection:Fire() end
		end
	end
end
local logicElapsed = 0
connect(RunService.Heartbeat, function(deltaTime)
	logicElapsed += deltaTime
	if logicElapsed < 0.1 then return end
	logicElapsed = 0
	if state.game and not state.game._jan then state.stage, state.game = nil, nil restorePatches() end
	local pending = shared.pending
	if pending then
		minigame:SetCastBlock(token .. "_pending", true)
		if os.clock() - pending.startedAt >= 12 then
			local hasNewItem = false
			for uid in items() do if not pending.beforeItems[uid] then hasNewItem = true break end end
			if hasNewItem and (player:GetAttribute("catches") or 0) > pending.beforeCount then
				finishPending()
			else
				finishPending()
				state.autoStart, state.viewDirty = false, true
				message("Catch timed out. Auto start stopped", true)
			end
		end
	end
	if state.saveAt and os.clock() >= state.saveAt then saveConfig() end
	if state.autoStart and not state.selling and not state.recovering and not shared.pending and not minigame.InSession
		and not state.stage and os.clock() >= state.nextCast then
		state.nextCast = os.clock() + 1
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not next(minigame.CastBlocks) and not next(inventory.EquipLocks)
			and not inventory.EquipBlock and not registry.C.Dialogue.Session and not UserInputService:GetFocusedTextBox() then
			if inventory:GetEquipped() ~= "instrument" then
				if inventory.Cache.instrument then inventory:Equip("instrument") end
			elseif os.clock() >= minigame._readyAt then
				local ok, err = pcall(cast)
				if not ok then
					state.autoStart, state.viewDirty = false, true
					message("Could not start catching", true)
					warn("Scrooms: " .. tostring(err))
				end
			end
		end
	end
end)

local lastBounds, lastOpen, lastMinimized
local renderElapsed = 0
connect(RunService.RenderStepped, function(deltaTime)
	if not state.alive then return end
	local bounds = safeArea.AbsoluteSize
	if state.layoutDirty or bounds ~= lastBounds then
		applyLayout(lastBounds == bounds and lastOpen ~= nil and lastOpen ~= state.filtersOpen and not state.drag)
		lastBounds, lastOpen = bounds, state.filtersOpen
	end
	if gui.Enabled ~= state.visible then gui.Enabled = state.visible end
	if window.Visible == state.minimized then window.Visible = not state.minimized end
	if floatingButton.Visible ~= state.minimized then floatingButton.Visible = state.minimized end
	local drawerVisible = not state.minimized and (state.filtersOpen or drawer.AbsoluteSize.Y > 0.5)
	if drawer.Visible ~= drawerVisible then drawer.Visible = drawerVisible end
	if state.viewDirty or lastMinimized ~= state.minimized then
		for _, control in controls do
			local value = control.getter() == true
			if control.lastValue ~= value then
				control.valueLabel.Text = if value then "On" else "Off"
				control.valueLabel.TextColor3 = if value then theme.accent else theme.muted
				animate(control.track, { BackgroundColor3 = if value then theme.accent else theme.border })
				animate(control.thumb, { Position = UDim2.fromOffset(if value then 20 else 4, 4) })
				control.lastValue = value
			end
		end
		state.viewDirty, lastMinimized = false, state.minimized
	end
	local locked = state.selling or state.recovering
	for _, control in controls do
		if control.isFilter and control.button.Interactable == locked then control.button.Interactable = not locked end
	end
	if sellButton.Interactable == locked then sellButton.Interactable = not locked end
	renderElapsed += deltaTime
	if renderElapsed < 0.1 then return end
	renderElapsed = 0
	local saleText = if state.recoveryFailed then "Recovery needed" elseif state.recovering then "Restoring..."
		elseif state.selling then "Selling..." else "Sell inventory"
	if sellButton.Text ~= saleText then sellButton.Text = saleText end
	local showingMessage = os.clock() < state.messageUntil
	local text = if state.recoveryFailed then "Recovery needed. Run the script again"
		elseif state.recovering then "Restoring sale settings..."
		elseif shared.pending then "Waiting for catch..."
		elseif showingMessage then state.message
		elseif state.selling then state.salePhase or (if state.stage then "Finishing the current catch..." else "Selling inventory...")
		elseif state.stage == "ring" then "Casting..."
		elseif state.stage == "tune" then "Tuning..."
		elseif state.stage == "main" then "Catching..."
		elseif state.autoStart then "Waiting to cast..." else "Ready"
	if state.caught > 0 and not showingMessage and not shared.pending then text ..= " | " .. state.caught .. " caught" end
	if status.Text ~= text then status.Text = text end
	local color = if showingMessage and state.messageError then theme.error else theme.muted
	if status.TextColor3 ~= color then status.TextColor3 = color end
end)

local idleWarningShown = false
connect(player.Idled, function()
	if not state.alive then return end
	local ok, err = pcall(function()
		VirtualUser:CaptureController()
		local camera = workspace.CurrentCamera
		VirtualUser:ClickButton2(Vector2.zero, if camera then camera.CFrame else CFrame.identity)
	end)
	if not ok and not idleWarningShown then
		idleWarningShown = true
		warn("Scrooms: anti-AFK input is unavailable: " .. tostring(err))
	end
end)
function api.GetState()
	return {
		alive = state.alive, instantCatch = state.instantCatch, autoMinigame = state.autoMinigame,
		autoStart = state.autoStart, selling = state.selling, recovering = state.recovering,
		stage = state.stage, caught = state.caught, minimized = state.minimized, visible = state.visible,
		catchPending = shared.pending ~= nil, filtersOpen = state.filtersOpen, filters = copyFilters(state.filters),
		windowPosition = table.clone(state.windowPosition), floatPosition = table.clone(state.floatPosition),
	}
end
function api.Destroy()
	if not state.alive then return end
	state.alive, state.autoStart, state.autoMinigame, state.instantCatch = false, false, false, false
	saveConfig()
	restorePatches()
	minigame:SetCastBlock(token, false)
	minigame:SetCastBlock(token .. "_pending", false)
	if not state.selling then minigame:SetCastBlock(token .. "_sale", false) end
	for _, connection in connections do connection:Disconnect() end
	for _, tween in tweens do tween:Cancel() end
	table.clear(connections)
	table.clear(tweens)
	if host.environment.ScroomsHub == api then host.environment.ScroomsHub = nil end
	gui:Destroy()
end
connect(closeButton.Activated, api.Destroy)
connect(gui.Destroying, api.Destroy)
host.environment.ScroomsHub = api
task.spawn(recoverSale)
warn("t.me/arceusxcommunity")

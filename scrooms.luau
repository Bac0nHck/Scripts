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
while not (registry.C.Minigame and registry.C.Inventory and registry.C.Data and registry.C.Input) do
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
	uiParent = CoreGui,
}
if type(gethui) == "function" then
	local ok, container = pcall(gethui)
	if ok and typeof(container) == "Instance" then
		host.uiParent = container
	end
end
local previous = host.environment.ScroomsHub
if type(previous) == "table" and type(previous.Destroy) == "function" then
	previous.Destroy()
end
for _, container in { playerGui, host.uiParent } do
	local oldGui = container:FindFirstChild("ScroomsHub")
	if oldGui then
		oldGui:Destroy()
	end
end

local minigame = registry.C.Minigame
local inventory = registry.C.Inventory
local data = registry.C.Data
local sellingRules = require(ReplicatedStorage.Shared.Utils.Selling)
local questRules = require(ReplicatedStorage.Shared.Utils.Quest)
local dialogueRemote = ReplicatedStorage.Network.Remotes.Dialogue
local token = "ScroomsHub_" .. HttpService:GenerateGUID(false)
local alive, autoMinigame, autoStart, selling = true, false, false, false
local currentStage, currentGame = nil, nil
local connections, patches, tweens = {}, {}, {}
local nextCast, lastMessage, messageUntil, caught = 0, "", 0, 0
local messageIsError = false
local api = {}
local theme = {
	surface = Color3.fromRGB(25, 28, 32),
	row = Color3.fromRGB(35, 39, 44),
	border = Color3.fromRGB(57, 63, 68),
	text = Color3.fromRGB(240, 242, 239),
	muted = Color3.fromRGB(157, 166, 166),
	accent = Color3.fromRGB(155, 188, 162),
	error = Color3.fromRGB(231, 151, 137),
	radius = 6,
	motion = 0.14,
}

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local idleWarningShown = false
connect(player.Idled, function()
	if not alive then return end
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

local function create(className, properties, parent)
	local object = Instance.new(className)
	if object:IsA("ScreenGui") or object:IsA("GuiButton") then
		object:SetAttribute("NoScaleTrack", true)
	end
	if object:IsA("GuiButton") then
		object:SetAttribute("NoAudioTrack", true)
	end
	for key, value in properties do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function round(object, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or theme.radius) }, object)
end

local function animate(object, properties)
	if tweens[object] then
		tweens[object]:Cancel()
	end
	local tween = TweenService:Create(object, TweenInfo.new(theme.motion), properties)
	tweens[object] = tween
	tween:Play()
end

local gui = create("ScreenGui", {
	Name = "ScroomsHub",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 90,
}, host.uiParent)
local safeArea = create("Frame", {
	Name = "SafeArea",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Active = false,
}, gui)
local panel = create("Frame", {
	Name = "Panel",
	Position = UDim2.new(0, 16, 0.22, 0),
	Size = UDim2.new(0.88, 0, 0, 242),
	BackgroundColor3 = theme.surface,
	BorderSizePixel = 0,
	Active = true,
}, safeArea)
round(panel)
create("UISizeConstraint", { MaxSize = Vector2.new(310, 242) }, panel)
create("UIStroke", { Color = theme.border, Thickness = 1 }, panel)
local header = create("Frame", {
	Name = "Header",
	Size = UDim2.new(1, -88, 0, 48),
	BackgroundTransparency = 1,
	Active = true,
}, panel)
create("TextLabel", {
	Name = "Title",
	Position = UDim2.fromOffset(14, 0),
	Size = UDim2.new(1, -14, 1, 0),
	BackgroundTransparency = 1,
	Text = "Scrooms",
	TextColor3 = theme.text,
	TextSize = 18,
	Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local function headerButton(name, text, offset)
	return create("TextButton", {
		Name = name,
		Position = UDim2.new(1, offset, 0, 2),
		Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1,
		Text = text,
		TextSize = 22,
		TextColor3 = theme.muted,
		Font = Enum.Font.Gotham,
		AutoButtonColor = false,
		Selectable = true,
	}, panel)
end
local minimizeButton = headerButton("Minimize", "-", -88)
local closeButton = headerButton("Close", "x", -44)
local content = create("Frame", {
	Name = "Content",
	Position = UDim2.fromOffset(12, 54),
	Size = UDim2.new(1, -24, 0, 154),
	BackgroundTransparency = 1,
}, panel)
create("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, content)
local status = create("TextLabel", {
	Name = "Status",
	Position = UDim2.fromOffset(14, 216),
	Size = UDim2.new(1, -28, 0, 16),
	BackgroundTransparency = 1,
	Text = "Ready",
	TextColor3 = theme.muted,
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, panel)

local function message(text, isError)
	lastMessage, messageUntil = text, os.clock() + 5
	messageIsError = isError == true
end

local function toggle(name, text, order, callback)
	local button = create("TextButton", {
		Name = name,
		Size = UDim2.new(1, 0, 0, 46),
		LayoutOrder = order,
		BackgroundColor3 = theme.row,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Selectable = true,
	}, content)
	round(button)
	create("TextLabel", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -100, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = theme.text,
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, button)
	local stateLabel = create("TextLabel", {
		Position = UDim2.new(1, -92, 0, 0),
		Size = UDim2.new(0, 30, 1, 0),
		BackgroundTransparency = 1,
		Text = "Off",
		TextColor3 = theme.muted,
		TextSize = 12,
		Font = Enum.Font.Gotham,
	}, button)
	local track = create("Frame", {
		Position = UDim2.new(1, -52, 0.5, -12),
		Size = UDim2.fromOffset(40, 24),
		BackgroundColor3 = theme.border,
		BorderSizePixel = 0,
	}, button)
	round(track)
	local thumb = create("Frame", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = theme.text,
		BorderSizePixel = 0,
	}, track)
	round(thumb, 4)
	local enabled = false
	local function set(value)
		if not alive then return end
		enabled = value == true
		stateLabel.Text = if enabled then "On" else "Off"
		stateLabel.TextColor3 = if enabled then theme.accent else theme.muted
		animate(track, { BackgroundColor3 = if enabled then theme.accent else theme.border })
		animate(thumb, { Position = UDim2.fromOffset(if enabled then 20 else 4, 4) })
		callback(enabled)
	end
	connect(button.Activated, function() set(not enabled) end)
	return set
end

local function restorePatches()
	for index = #patches, 1, -1 do
		local patch = patches[index]
		if rawget(patch.object, patch.key) == patch.replacement then
			rawset(patch.object, patch.key, patch.original)
		end
	end
	table.clear(patches)
end

local function patch(object, key, replacement)
	table.insert(patches, {
		object = object,
		key = key,
		original = rawget(object, key),
		replacement = replacement,
	})
	rawset(object, key, replacement)
end

local function assistStage(stage, object)
	restorePatches()
	if not (alive and autoMinigame and object and object._jan) then return end
	if stage == "ring" then
		if object._complete then return end
		task.defer(function()
			if alive and autoMinigame and currentGame == object and object._jan and not object._complete then
				object._tween:Cancel()
				object._ui.Ring.Tick.Rotation = object._targetRot
				object:Complete()
			end
		end)
	elseif stage == "tune" then
		local originalStep = object._step
		patch(object, "_step", function(self, deltaTime)
			self._needleX, self._needleVel = self._target, 0
			return originalStep(self, deltaTime)
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

local function recoverStage()
	if currentGame and currentGame._jan then return end
	if not host.objects then return end
	for _, object in host.objects(true) do
		if type(object) ~= "table" or not rawget(object, "_jan") then continue end
		local ui = rawget(object, "_ui")
		if typeof(ui) ~= "Instance" or not ui:IsDescendantOf(playerGui) then continue end
		local stage = if rawget(object, "_targetRot") then "ring"
			elseif rawget(object, "_targetTime") then "tune"
			elseif rawget(object, "_zone") and rawget(object, "_item") then "main" else nil
		if stage then
			currentStage, currentGame = stage, object
			return
		end
	end
end

connect(minigame.StageChanged, function(stage, object)
	currentStage, currentGame = stage, object
	if stage == nil then nextCast = os.clock() + 1 end
	assistStage(stage, object)
end)
connect(minigame.Caught, function() caught += 1 end)
recoverStage()

api.SetAutoMinigame = toggle("AutoMinigame", "Auto minigame", 1, function(value)
	autoMinigame = value
	if value then recoverStage() end
	assistStage(currentStage, currentGame)
end)
api.SetAutoStart = toggle("AutoStart", "Auto start catching", 2, function(value)
	autoStart = value
	nextCast = os.clock() + 0.3
	if value and not (host.fire or host.connections) then
		autoStart = false
		task.defer(function()
			api.SetAutoStart(false)
			message("Input support is unavailable", true)
		end)
	end
end)
local sellButton = create("TextButton", {
	Name = "SellAll",
	Size = UDim2.new(1, 0, 0, 46),
	LayoutOrder = 3,
	BackgroundColor3 = theme.accent,
	BorderSizePixel = 0,
	Text = "Sell inventory (keep quest items)",
	TextColor3 = theme.surface,
	TextSize = 14,
	Font = Enum.Font.GothamMedium,
	AutoButtonColor = true,
	Selectable = true,
}, content)
round(sellButton)

local function saleItems()
	local reserved = questRules:GetQuestStock(function(path)
		return data:Get(path)
	end)
	local result = {}
	for uid, item in data:Get({ "Inventory", "Items" }) or {} do
		if not reserved[uid] and not item.favorited and sellingRules:GetPrice(item) then
			result[uid] = true
		end
	end
	return result
end

local merchants = { julian_sg = true, gregory_bc = true, pip_sm = true, justin_tt = true, drew_ug = true }
local saleFilters = { "sellCommon", "sellUncommon", "sellRare", "sellWondrous", "sellFabled", "sellEversung", "sellShard", "sellSongsheet" }
local function nearestMerchant(root)
	local folder = workspace:FindFirstChild("World")
	folder = folder and folder:FindFirstChild("NPCs")
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

local function countSold(targets)
	local items = data:Get({ "Inventory", "Items" }) or {}
	local count = 0
	for uid in targets do
		if not items[uid] then count += 1 end
	end
	return count
end

function api.SellAll()
	if not alive or selling then return end
	local targets = saleItems()
	if next(targets) == nil then message("Nothing to sell. Quest items are kept") return end
	selling = true
	minigame:SetCastBlock(token, true)
	task.spawn(function()
		local root, origin, previousItem, moved
		local previousFilters = {}
		local ok, result = xpcall(function()
			local waitUntil = os.clock() + 90
			while alive and minigame.InSession and os.clock() < waitUntil do task.wait(0.1) end
			if not alive then return "Cancelled" end
			if minigame.InSession then return "Finish the catch and try again" end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			root = registry.C.Character:GetRoot()
			if not root or not humanoid or humanoid.Health <= 0 then return "Wait for your character" end
			local merchant = nearestMerchant(root)
			if not merchant then return "No merchant loaded nearby" end
			targets = saleItems()
			if not next(targets) then return "Nothing to sell. Quest items are kept" end
			for _, name in saleFilters do
				if registry.C.Settings:Get(name) == false then
					previousFilters[name] = false
					registry.C.Settings:Set(name, true)
				end
			end
			if next(previousFilters) then
				local endAt = os.clock() + 4
				while alive do
					local confirmed = true
					for name in previousFilters do
						if data:Get({ "Settings", name }) ~= true then confirmed = false break end
					end
					if confirmed then break end
					if os.clock() >= endAt then return "Could not update sale filters. Try again" end
					task.wait(0.1)
				end
			end
			if not alive then return "Sale cancelled" end
			local beforeChimes = player:GetAttribute("chimes") or 0
			origin, previousItem = root.CFrame, inventory:GetEquipped()
			inventory:Equip(nil)
			if (root.Position - merchant:GetPivot().Position).Magnitude > 10 then
				moved = true
				root.CFrame = merchant:GetPivot() * CFrame.new(0, 0, -5)
				root.AssemblyLinearVelocity = Vector3.zero
			end
			task.wait(0.65)
			if not alive or registry.C.Character:GetRoot() ~= root then return "Sale cancelled" end
			dialogueRemote:FireServer("nodeAction", { npc = merchant.Name, node = "sellAllKeepDone" })
			local endAt = os.clock() + 4
			repeat task.wait(0.1) until not alive or not next(saleItems()) or os.clock() >= endAt
			local sold = countSold(targets)
			if sold <= 0 then return "Sale refused. Try again near a merchant" end
			local earned = (player:GetAttribute("chimes") or beforeChimes) - beforeChimes
			return string.format("Sold %d items | +%d chimes", sold, earned)
		end, debug.traceback)
		local filtersRestored = true
		for name, value in previousFilters do
			local restored = pcall(function()
				if registry.C.Settings:Get(name) == true then registry.C.Settings:Set(name, value) end
			end)
			if not restored then filtersRestored = false end
		end
		local restored, restoreError = pcall(function()
			if root and root.Parent and registry.C.Character:GetRoot() == root then
				if moved and origin then
					root.CFrame = origin
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
				if previousItem then
					local restore = if inventory.Cache[previousItem] then previousItem else "instrument"
					inventory:Equip(restore)
				end
			end
		end)
		minigame:SetCastBlock(token, false)
		selling, nextCast = false, os.clock() + 1.2
		if alive then
			if not filtersRestored then
				message("Sale ended. Check your sale filters", true)
			elseif not restored then
				message("Sale ended. Check your position", true)
			else
				message(if ok then result or "Ready" else "Sale failed. Try again", not ok)
			end
		end
		if not ok then warn("Scrooms: " .. tostring(result)) end
		if not restored then warn("Scrooms: could not restore character: " .. tostring(restoreError)) end
	end)
end
connect(sellButton.Activated, api.SellAll)

local collapsed = false
local function clampPanel()
	local bounds, size = safeArea.AbsoluteSize, panel.AbsoluteSize
	local x = panel.Position.X.Scale * bounds.X + panel.Position.X.Offset
	local y = panel.Position.Y.Scale * bounds.Y + panel.Position.Y.Offset
	panel.Position = UDim2.fromOffset(
		math.clamp(x, 8, math.max(8, bounds.X - size.X - 8)),
		math.clamp(y, 8, math.max(8, bounds.Y - size.Y - 8))
	)
end
function api.SetMinimized(value)
	if not alive then return end
	collapsed = value == true
	local height = if collapsed then 48 else 242
	panel.Size = UDim2.new(0.88, 0, 0, height)
	content.Visible = not collapsed
	status.Visible = not collapsed
	minimizeButton.Text = if collapsed then "+" else "-"
	task.defer(clampPanel)
end
function api.SetVisible(value)
	if not alive then return end
	gui.Enabled = value == true
end
connect(minimizeButton.Activated, function()
	api.SetMinimized(not collapsed)
end)
connect(UserInputService.InputBegan, function(input, gameProcessedEvent)
	if gameProcessedEvent or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.RightControl then
		api.SetVisible(not gui.Enabled)
	end
end)
connect(safeArea:GetPropertyChangedSignal("AbsoluteSize"), function() task.defer(clampPanel) end)

local dragInput, dragStart, dragOrigin
connect(header.InputBegan, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragInput, dragStart, dragOrigin = input, input.Position, panel.Position
	end
end)
connect(UserInputService.InputChanged, function(input)
	if not dragInput or not gui.Enabled then return end
	if input == dragInput or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
		local delta = input.Position - dragStart
		panel.Position = UDim2.fromOffset(dragOrigin.X.Offset + delta.X, dragOrigin.Y.Offset + delta.Y)
		clampPanel()
	end
end)
connect(UserInputService.InputEnded, function(input)
	if input == dragInput then dragInput = nil end
end)

local function cast()
	local action = registry.C.Input.Actions.Cast
	if host.fire then
		host.fire(action.Pressed)
	elseif host.connections then
		for _, connection in host.connections(action.Pressed) do
			if connection.Enabled then connection:Fire() end
		end
	end
end

local elapsed = 0
connect(RunService.Heartbeat, function(deltaTime)
	elapsed += deltaTime
	if elapsed < 0.2 then return end
	elapsed = 0
	if currentGame and not currentGame._jan then currentStage, currentGame = nil, nil restorePatches() end
	if autoStart and not selling and not minigame.InSession and not currentStage and os.clock() >= nextCast then
		nextCast = os.clock() + 1.2
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not next(minigame.CastBlocks) and not next(inventory.EquipLocks) and not inventory.EquipBlock and not registry.C.Dialogue.Session and not UserInputService:GetFocusedTextBox() then
			if inventory:GetEquipped() ~= "instrument" then
				if inventory.Cache.instrument then inventory:Equip("instrument") end
			elseif os.clock() >= minigame._readyAt then
				local ok, err = pcall(cast)
				if not ok then
					api.SetAutoStart(false)
					message("Could not start catching", true)
					warn("Scrooms: " .. tostring(err))
				end
			end
		end
	end
end)

local renderElapsed = 0
connect(RunService.Heartbeat, function(deltaTime)
	renderElapsed += deltaTime
	if renderElapsed < 0.2 then return end
	renderElapsed = 0
	local buttonText = if selling then (if minigame.InSession then "Sell after catch..." else "Selling...")
		else "Sell inventory (keep quest items)"
	if sellButton.Text ~= buttonText then sellButton.Text = buttonText end
	if sellButton.Active == selling then sellButton.Active = not selling end
	local showingMessage = os.clock() < messageUntil
	local text = if showingMessage then lastMessage
		elseif selling then (if minigame.InSession then "Finishing the current catch..." else "Selling inventory...")
		elseif currentStage == "ring" then "Casting..."
		elseif currentStage == "tune" then "Tuning..."
		elseif currentStage == "main" then "Catching..."
		elseif autoStart then "Waiting to cast..." else "Ready"
	if caught > 0 and not showingMessage then text ..= " | " .. caught .. " caught" end
	if status.Text ~= text then status.Text = text end
	local color = if showingMessage and messageIsError then theme.error else theme.muted
	if status.TextColor3 ~= color then status.TextColor3 = color end
end)

function api.GetState()
	return {
		autoMinigame = autoMinigame,
		autoStart = autoStart,
		selling = selling,
		stage = currentStage,
		caught = caught,
		minimized = collapsed,
		visible = gui.Enabled,
		alive = alive,
	}
end

function api.Destroy()
	if not alive then return end
	alive, autoMinigame, autoStart = false, false, false
	restorePatches()
	minigame:SetCastBlock(token, false)
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
task.defer(clampPanel)
warn("t.me/arceusxcommunity")

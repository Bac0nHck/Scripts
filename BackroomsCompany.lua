local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local function cleanupCall(callback)
	local ok, failure = pcall(callback)
	local getIdentity = getthreadidentity or getidentity
	local setIdentity = setthreadidentity or setidentity
	if not ok and tostring(failure):find("capability Plugin", 1, true)
		and type(getIdentity) == "function" and type(setIdentity) == "function" then
		local identityOk, identity = pcall(getIdentity)
		if identityOk then
			for _, cleanupIdentity in ipairs({ 6, 8 }) do
				if pcall(setIdentity, cleanupIdentity) then
					ok, failure = pcall(callback)
				end
				pcall(setIdentity, identity)
				if ok then break end
			end
		end
	end
	return ok, failure
end

local function destroyVisual(object)
	if not object then return end
	local ok, failure = cleanupCall(function() object:Destroy() end)
	if not ok then warn("[TheBackrooms] Cleanup: " .. tostring(failure)) end
	return ok
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end
while not Players.LocalPlayer do
	task.wait()
end

local Environment = type(getgenv) == "function" and getgenv() or _G
local LoadingToken = {}
Environment.TheBackroomsLoading = LoadingToken
local LibraryUrl = "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/2910b3532195935a00dacb479a0ded50f1f38a0a/Source.luau"
local loaded, Airflow = pcall(function()
	return loadstring(game:HttpGet(LibraryUrl))()
end)
if Environment.TheBackroomsLoading ~= LoadingToken then
	return
end
Environment.TheBackroomsLoading = nil
if not loaded or type(Airflow) ~= "table" then
	warn("[TheBackrooms] Airflow failed to load: " .. tostring(Airflow))
	return
end

local RestoreFullBright = type(Environment.TheBackroomsHub) == "table"
	and Environment.TheBackroomsHub.FullBright
	and Environment.TheBackroomsHub.FullBright.Enabled == true
local RestoreItemsAura = type(Environment.TheBackroomsHub) == "table"
	and Environment.TheBackroomsHub.Aura
	and Environment.TheBackroomsHub.Aura.Enabled == true
local RestoreAutoDeliver = type(Environment.TheBackroomsHub) == "table"
	and Environment.TheBackroomsHub.Delivery
	and Environment.TheBackroomsHub.Delivery.Enabled == true
local RestoreAutoReturn = type(Environment.TheBackroomsHub) == "table"
	and Environment.TheBackroomsHub.ReturnToRoom
	and Environment.TheBackroomsHub.ReturnToRoom.Enabled == true
local RestoreInfStamina = type(Environment.TheBackroomsHub) == "table"
	and Environment.TheBackroomsHub.Stamina
	and Environment.TheBackroomsHub.Stamina.Enabled == true
local RestoreAntiEffects = type(Environment.TheBackroomsHub) == "table"
	and Environment.TheBackroomsHub.AntiEffects
	and Environment.TheBackroomsHub.AntiEffects.Enabled == true
local RestoreLightItems = type(Environment.TheBackroomsHub) == "table"
	and Environment.TheBackroomsHub.LightItems
	and Environment.TheBackroomsHub.LightItems.Enabled == true
local RestorePlayer
if type(Environment.TheBackroomsHub) == "table" and Environment.TheBackroomsHub.Player then
	local previous = Environment.TheBackroomsHub.Player
	RestorePlayer = {
		Speed = previous.Speed, JumpPower = previous.JumpPower, FOV = previous.FOV,
		EnableJump = previous.EnableJump, InfJump = previous.InfJump, Noclip = previous.Noclip,
	}
end
local RestoreFarm
if type(Environment.TheBackroomsHub) == "table" and Environment.TheBackroomsHub.Farm then
	local previous = Environment.TheBackroomsHub.Farm
	RestoreFarm = {
		Enabled = previous.Enabled, Stats = table.clone(previous.Stats), NoclipBackup = previous.NoclipBackup,
		Elapsed = previous.Elapsed + (previous.Enabled and os.clock() - previous.StartedAt or 0),
	}
end
if type(Environment.TheBackroomsHub) == "table" and type(Environment.TheBackroomsHub.Unload) == "function" then
	local previous = Environment.TheBackroomsHub
	local ok, failure = cleanupCall(previous.Unload)
	if not ok or not previous.Unloaded then
		previous.Running = false
		for _, key in ipairs({ "Worker", "AuraWorker", "DeliveryWorker", "FarmWorker" }) do
			if previous[key] then pcall(task.cancel, previous[key]) end
		end
		for _, connection in ipairs(previous.Connections or {}) do pcall(function() connection:Disconnect() end) end
		for _, record in pairs(previous.Records or {}) do
			for _, connection in ipairs(record.Connections or {}) do pcall(function() connection:Disconnect() end) end
		end
		destroyVisual(previous.VisualFolder)
		destroyVisual(previous.LabelGui)
		if previous.Window then cleanupCall(function() previous.Window:Destroy() end) end
	end
	if not ok then warn("[TheBackrooms] Previous session cleanup: " .. tostring(failure)) end
end

local Hub = { Running = true, Connections = {}, Records = {}, Controls = {}, AntiAFK = false }
Environment.TheBackroomsHub = Hub
local Esp = {
	Enabled = false,
	MonstersEnabled = false,
	ShowLabels = true,
	Color = Color3.fromRGB(255, 211, 110),
	TextColor = Color3.fromRGB(140, 235, 255),
	MonsterColor = Color3.fromRGB(255, 70, 95),
	MonsterTextColor = Color3.fromRGB(255, 160, 190),
}
Hub.Esp = Esp
local FullBright = { Enabled = false, Saved = {}, Connections = {} }
Hub.FullBright = FullBright
local Aura = { Enabled = false, Cooldowns = setmetatable({}, { __mode = "k" }), LastAttempt = 0 }
Hub.Aura = Aura
local Delivery = { Enabled = false, Busy = false, NextAttempt = 0 }
Hub.Delivery = Delivery
local ReturnToRoom = { Enabled = false, Completed = nil }
Hub.ReturnToRoom = ReturnToRoom
local Stamina = { Enabled = false, NextProbe = 0 }
Hub.Stamina = Stamina
local AntiEffects = { Enabled = false, Saved = {}, Connections = {} }
Hub.AntiEffects = AntiEffects
local LightItems = { Enabled = false, Connections = {} }
Hub.LightItems = LightItems
local PlayerSettings = {
	Ready = false, Syncing = false, EnableJump = false, InfJump = false, Noclip = false,
	Connections = {}, HumanoidConnections = {}, CollisionParts = {}, LastJump = 0,
	DefaultSpeed = 10, DefaultJumpPower = 0, DefaultFOV = 70,
}
Hub.Player = PlayerSettings
local Farm = {
	Enabled = false, Epoch = 0, Status = "Disabled", Elapsed = RestoreFarm and RestoreFarm.Elapsed or 0,
	Stats = RestoreFarm and RestoreFarm.Stats or { Collected = 0, Delivered = 0, Value = 0, Floors = 0, Skipped = 0, Escapes = 0 },
	Cooldowns = setmetatable({}, { __mode = "k" }), Avoided = {}, NextAction = 0, NextStats = 0,
}
Hub.Farm = Farm

local function connect(signal, callback, list)
	local connection = signal:Connect(callback)
	table.insert(list or Hub.Connections, connection)
	return connection
end

local function itemsContainer()
	local triggers = Workspace:FindFirstChild("GameTriggers")
	return triggers and triggers:FindFirstChild("Items")
end

local function isMonster(item)
	if not (item:IsA("Model") or item:IsA("BasePart")) then
		return false
	end
	local triggers = Workspace:FindFirstChild("GameTriggers")
	local entities = triggers and triggers:FindFirstChild("SpawnedEntities")
	return (entities ~= nil and item.Parent == entities)
		or CollectionService:HasTag(item, "NpcReadyGameTag")
end

local function isCandidate(item)
	if not (item:IsA("Tool") or item:IsA("Model") or item:IsA("BasePart")) then
		return false
	end
	return isMonster(item) or CollectionService:HasTag(item, "CollectableItem")
		or CollectionService:HasTag(item, "ItemHighlightGameTag")
		or item.Parent == itemsContainer()
end

local function isFreeInWorld(item)
	if not item:IsDescendantOf(Workspace) then
		return false
	end
	if item:GetAttribute("CartHeld") == true or item:GetAttribute("RoverHeld") == true then
		return false
	end
	local triggers = Workspace:FindFirstChild("GameTriggers")
	local deposited = triggers and triggers:FindFirstChild("DepositedItems")
	if deposited and item:IsDescendantOf(deposited) then
		return false
	end
	local ancestor = item.Parent
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Backpack") or (ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid")) then
			return false
		end
		ancestor = ancestor.Parent
	end
	return ancestor == Workspace
end

local function anchorPart(item)
	if item:IsA("BasePart") then
		return item
	end
	local handle = item:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end
	if item:IsA("Model") and item.PrimaryPart then
		return item.PrimaryPart
	end
	return item:FindFirstChildWhichIsA("BasePart", true)
end

local function numberText(value)
	local number = tonumber(value)
	if not number then
		return "?"
	end
	return number == math.floor(number) and string.format("%.0f", number) or string.format("%.1f", number)
end

local function clearVisual(record)
	if record.Highlight then
		destroyVisual(record.Highlight)
		record.Highlight = nil
	end
	if record.Billboard then
		destroyVisual(record.Billboard)
		record.Billboard = nil
		record.Label = nil
	end
end

local function forget(item)
	local record = Hub.Records[item]
	if not record then
		return
	end
	Hub.Records[item] = nil
	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end
	clearVisual(record)
end

local function refresh(item, record)
	if not Hub.Running or Hub.Records[item] ~= record then
		return
	end
	if (record.IsMonster and not Esp.MonstersEnabled) or (not record.IsMonster and not Esp.Enabled) then
		forget(item)
		return
	end
	if not item:IsDescendantOf(Workspace) or not isCandidate(item) then
		forget(item)
		return
	end
	local anchor = anchorPart(item)
	if not anchor or (not record.IsMonster and (not isFreeInWorld(item) or tonumber(item:GetAttribute("price")) == nil)) then
		clearVisual(record)
		return
	end
	if record.IsMonster then
		local humanoid = item:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then
			clearVisual(record)
			return
		end
	end
	if not record.Highlight then
		local highlight = Instance.new("Highlight")
		highlight.Name = record.IsMonster and "BackroomsMonsterHighlight" or "BackroomsItemHighlight"
		highlight.Adornee = item
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.7
		highlight.OutlineTransparency = 0
		highlight.Parent = Hub.VisualFolder
		record.Highlight = highlight
	end
	if not record.Billboard then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = record.IsMonster and "BackroomsMonsterLabel" or "BackroomsItemLabel"
		billboard.Size = UDim2.fromOffset(240, 42)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 0
		billboard.LightInfluence = 0
		billboard.Parent = Hub.LabelGui
		local label = Instance.new("TextLabel")
		label.Name = "Details"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamMedium
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
		label.TextWrapped = true
		label.Parent = billboard
		record.Billboard = billboard
		record.Label = label
	end
	local name = record.IsMonster and (item:GetAttribute("EntityType") or item:GetAttribute("DisplayName")) or item:GetAttribute("name")
	if type(name) ~= "string" or name == "" then
		name = item.Name
		if record.IsMonster then
			name = name:gsub("NPC$", ""):gsub("(%l)(%u)", "%1 %2")
		end
	end
	local color = record.IsMonster and Esp.MonsterColor or Esp.Color
	record.Highlight.FillColor = color
	record.Highlight.OutlineColor = color
	record.Billboard.Adornee = anchor
	record.Billboard.StudsOffsetWorldSpace = Vector3.new(0, record.IsMonster and 3.5 or 2, 0)
	record.Billboard.Enabled = record.IsMonster or Esp.ShowLabels
	record.Label.TextColor3 = record.IsMonster and Esp.MonsterTextColor or Esp.TextColor
	record.Label.TextSize = 12
	record.Label.Text = record.IsMonster and name or string.format("%s\nWeight: %s lb  |  Value: $%s", name, numberText(item:GetAttribute("weight")), numberText(item:GetAttribute("price")))
end

local function queueRefresh(item, record)
	if record.Pending then
		return
	end
	record.Pending = true
	task.defer(function()
		record.Pending = false
		refresh(item, record)
	end)
end

local function watch(item)
	if not Hub.Running or not item:IsDescendantOf(Workspace) or not isCandidate(item) then
		return
	end
	local monster = isMonster(item)
	if (monster and not Esp.MonstersEnabled) or (not monster and not Esp.Enabled) then
		return
	end
	local record = Hub.Records[item]
	if record then
		queueRefresh(item, record)
		return
	end
	record = { Connections = {}, IsMonster = monster }
	Hub.Records[item] = record
	local function changed()
		queueRefresh(item, record)
	end
	connect(item.AncestryChanged, changed, record.Connections)
	connect(item.Destroying, function()
		forget(item)
	end, record.Connections)
	connect(item:GetPropertyChangedSignal("Name"), changed, record.Connections)
	connect(item.AttributeChanged, function(attribute)
		if attribute == "name" or attribute == "weight" or attribute == "price" or attribute == "CartHeld" or attribute == "RoverHeld" or attribute == "EntityType" or attribute == "DisplayName" then
			changed()
		end
	end, record.Connections)
	connect(item.DescendantAdded, function(descendant)
		if descendant:IsA("BasePart") then
			changed()
		end
	end, record.Connections)
	connect(item.DescendantRemoving, function(descendant)
		if descendant:IsA("BasePart") then
			changed()
		end
	end, record.Connections)
	refresh(item, record)
end

local function discover()
	if not Hub.Running or not (Esp.Enabled or Esp.MonstersEnabled) then
		return
	end
	for _, tag in ipairs({ "CollectableItem", "ItemHighlightGameTag", "NpcReadyGameTag" }) do
		for _, item in ipairs(CollectionService:GetTagged(tag)) do
			watch(item)
		end
	end
	local container = itemsContainer()
	if container then
		for _, item in ipairs(container:GetChildren()) do
			watch(item)
		end
	end
	local triggers = Workspace:FindFirstChild("GameTriggers")
	local entities = triggers and triggers:FindFirstChild("SpawnedEntities")
	if entities then
		for _, entity in ipairs(entities:GetChildren()) do
			watch(entity)
		end
	end
end

local function refreshAll()
	for item, record in pairs(Hub.Records) do
		refresh(item, record)
	end
end

local function clearRecords(monstersOnly)
	local items = {}
	for item, record in pairs(Hub.Records) do
		if monstersOnly == nil or record.IsMonster == monstersOnly then
			table.insert(items, item)
		end
	end
	for _, item in ipairs(items) do
		forget(item)
	end
end

function Hub.SetEsp(enabled)
	Esp.Enabled = enabled == true and Hub.Running
	if Esp.Enabled then
		discover()
	else
		clearRecords(false)
	end
end

function Hub.SetMonsters(enabled)
	Esp.MonstersEnabled = enabled == true and Hub.Running
	if Esp.MonstersEnabled then
		discover()
	else
		clearRecords(true)
	end
end

function Hub.SetFullBright(enabled)
	enabled = enabled == true and Hub.Running
	if enabled == FullBright.Enabled then
		return
	end
	FullBright.Enabled = enabled
	if not enabled then
		for _, connection in ipairs(FullBright.Connections) do
			connection:Disconnect()
		end
		table.clear(FullBright.Connections)
		if FullBright.CameraConnection then
			FullBright.CameraConnection:Disconnect()
			FullBright.CameraConnection = nil
		end
		for object, properties in pairs(FullBright.Saved) do
			for property, value in pairs(properties) do
				pcall(function()
					local effect = AntiEffects.Enabled and AntiEffects.Saved[object]
					if effect and effect.Property == property then
						effect.Value = value
						object[property] = false
					else
						object[property] = value
					end
				end)
			end
		end
		table.clear(FullBright.Saved)
		return
	end

	local function override(object, targets)
		if FullBright.Saved[object] then
			return
		end
		local saved = {}
		FullBright.Saved[object] = saved
		for property, target in pairs(targets) do
			saved[property] = object[property]
			local effect = AntiEffects.Enabled and AntiEffects.Saved[object]
			if effect and effect.Property == property then
				saved[property] = effect.Value
			end
			connect(object:GetPropertyChangedSignal(property), function()
				if not FullBright.Enabled then
					return
				end
				local current = object[property]
				local matches = current == target
					or (type(current) == "number" and type(target) == "number" and math.abs(current - target) < 0.0001)
				if not matches then
					saved[property] = current
					object[property] = target
				end
			end, FullBright.Connections)
			object[property] = target
		end
	end
	local function effectAdded(effect)
		if effect:IsA("Atmosphere") then
			override(effect, { Density = 0, Haze = 0 })
		elseif effect:IsA("ColorCorrectionEffect") then
			override(effect, { Enabled = false })
		end
	end
	override(Lighting, {
		Brightness = 1,
		ClockTime = 14,
		Ambient = Color3.fromRGB(115, 115, 115),
		OutdoorAmbient = Color3.fromRGB(115, 115, 115),
		GlobalShadows = false,
		FogStart = 1000000,
		FogEnd = 1000000,
		ExposureCompensation = -0.15,
	})
	for _, effect in ipairs(Lighting:GetChildren()) do
		effectAdded(effect)
	end
	connect(Lighting.ChildAdded, effectAdded, FullBright.Connections)
	local function watchCamera()
		if FullBright.CameraConnection then
			FullBright.CameraConnection:Disconnect()
			FullBright.CameraConnection = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			for _, effect in ipairs(camera:GetChildren()) do
				effectAdded(effect)
			end
			FullBright.CameraConnection = camera.ChildAdded:Connect(effectAdded)
		end
	end
	connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera, FullBright.Connections)
	watchCamera()
end

function Hub.SetAntiEffects(enabled)
	enabled = enabled == true and Hub.Running
	if enabled == AntiEffects.Enabled then
		return
	end
	AntiEffects.Enabled = enabled
	local function release(object)
		local record = AntiEffects.Saved[object]
		if not record then return end
		AntiEffects.Saved[object] = nil
		for _, connection in ipairs(record.Connections) do
			connection:Disconnect()
		end
		pcall(function()
			local lightingState = FullBright.Enabled and FullBright.Saved[object]
			if lightingState and lightingState[record.Property] ~= nil then
				lightingState[record.Property] = record.Value
				object[record.Property] = false
			else
				object[record.Property] = record.Value
			end
		end)
	end
	if not enabled then
		for _, connection in ipairs(AntiEffects.Connections) do connection:Disconnect() end
		table.clear(AntiEffects.Connections)
		for _, key in ipairs({ "CameraConnection", "GuiConnection" }) do
			if AntiEffects[key] then
				AntiEffects[key]:Disconnect()
				AntiEffects[key] = nil
			end
		end
		local objects = {}
		for object in pairs(AntiEffects.Saved) do objects[#objects + 1] = object end
		for _, object in ipairs(objects) do release(object) end
		return
	end
	local function suppress(object, property)
		if AntiEffects.Saved[object] then return end
		local value = object[property]
		local lightingState = FullBright.Enabled and FullBright.Saved[object]
		if lightingState and lightingState[property] ~= nil then value = lightingState[property] end
		local record = { Property = property, Value = value, Connections = {} }
		AntiEffects.Saved[object] = record
		connect(object:GetPropertyChangedSignal(property), function()
			if AntiEffects.Enabled and object[property] ~= false then
				record.Value = object[property]
				local shared = FullBright.Enabled and FullBright.Saved[object]
				if shared and shared[property] ~= nil then shared[property] = record.Value end
				object[property] = false
			end
		end, record.Connections)
		connect(object.Destroying, function()
			AntiEffects.Saved[object] = nil
			for _, connection in ipairs(record.Connections) do connection:Disconnect() end
		end, record.Connections)
		object[property] = false
	end
	local function postEffectAdded(object)
		if object:IsA("PostEffect") then suppress(object, "Enabled") end
	end
	local function watchCamera()
		if AntiEffects.CameraConnection then AntiEffects.CameraConnection:Disconnect() end
		local camera = Workspace.CurrentCamera
		local obsolete = {}
		for object in pairs(AntiEffects.Saved) do
			if object:IsA("PostEffect") and object.Parent ~= Lighting and object.Parent ~= camera then
				obsolete[#obsolete + 1] = object
			end
		end
		for _, object in ipairs(obsolete) do release(object) end
		if camera then
			for _, object in ipairs(camera:GetChildren()) do postEffectAdded(object) end
			AntiEffects.CameraConnection = camera.ChildAdded:Connect(postEffectAdded)
		end
	end
	local function watchGui(gui)
		if AntiEffects.GuiConnection then AntiEffects.GuiConnection:Disconnect() end
		local function overlayAdded(object)
			if not object:IsA("GuiObject") then return end
			local parent = object.Parent
			if not parent then return end
			if parent.Parent == gui then
				if (parent.Name == "StaticGui" and object.Name == "Static")
					or (parent.Name == "DamageFeedback" and object.Name == "RedFlash")
					or (parent.Name == "DigitalCameraGui" and object.Name == "Flash")
					or (parent.Name == "MainHud" and object.Name == "AlarmFlash") then
					suppress(object, "Visible")
				end
			elseif parent.Name == "Frame" and parent.Parent and parent.Parent.Name == "MainHud"
				and parent.Parent.Parent == gui and (object.Name == "LowStamina" or object.Name == "CriticalInjury") then
				suppress(object, "Visible")
			end
		end
		for _, object in ipairs(gui:QueryDescendants("#Static, #RedFlash, #Flash, #AlarmFlash, #LowStamina, #CriticalInjury")) do
			overlayAdded(object)
		end
		AntiEffects.GuiConnection = gui.DescendantAdded:Connect(overlayAdded)
	end
	for _, object in ipairs(Lighting:GetChildren()) do postEffectAdded(object) end
	connect(Lighting.ChildAdded, postEffectAdded, AntiEffects.Connections)
	connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera, AntiEffects.Connections)
	connect(Players.LocalPlayer.ChildAdded, function(child)
		if child:IsA("PlayerGui") then watchGui(child) end
	end, AntiEffects.Connections)
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if gui then watchGui(gui) end
	watchCamera()
end

function Hub.Notify(title, content, kind)
	if Hub.Running and Hub.Window then
		pcall(function()
			Hub.Window:Notify({ Title = title, Content = content, Type = kind or "Info", Duration = 5 })
		end)
	end
end

function Hub.Copy(text)
	if type(setclipboard) == "function" and pcall(setclipboard, text) then
		Hub.Notify("Copied", text, "Success")
	else
		Hub.Notify("Link", text, "Info")
	end
end

local function syncPlayerControl(name, value)
	local control = Hub.Controls[name]
	if not control then return end
	PlayerSettings.Syncing = true
	local ok, failure = pcall(function() control:Set(value) end)
	PlayerSettings.Syncing = false
	if not ok then warn("[TheBackrooms] Player control: " .. tostring(failure)) end
end

local function playerCanMove(humanoid)
	local player = Players.LocalPlayer
	local character = PlayerSettings.Character
	return Hub.Running and humanoid and humanoid.Health > 0 and character == player.Character
		and not player:GetAttribute("Dead") and not player:GetAttribute("Dying")
		and not player:GetAttribute("Stunned") and not player:GetAttribute("Rooted")
		and not player:GetAttribute("InLocker") and not character:GetAttribute("AnimationLocked")
end

local function applyPlayerHumanoid()
	local humanoid = PlayerSettings.Humanoid
	if not playerCanMove(humanoid) then return end
	if PlayerSettings.Speed ~= nil and math.abs(humanoid.WalkSpeed - PlayerSettings.Speed) > 0.0001 then
		humanoid.WalkSpeed = PlayerSettings.Speed
	end
	local allowJump = PlayerSettings.EnableJump or PlayerSettings.InfJump
	if allowJump or PlayerSettings.JumpPower ~= nil then
		local power = PlayerSettings.JumpPower
		if power == nil then power = 50 end
		if not humanoid.UseJumpPower then humanoid.UseJumpPower = true end
		if math.abs(humanoid.JumpPower - power) > 0.0001 then humanoid.JumpPower = power end
		if allowJump and not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end
end

local function restorePlayerJump()
	local humanoid = PlayerSettings.Humanoid
	local defaults = PlayerSettings.HumanoidDefaults
	if humanoid and defaults then
		humanoid.UseJumpPower = defaults.UseJumpPower
		humanoid.JumpPower = defaults.JumpPower
		humanoid.JumpHeight = defaults.JumpHeight
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, defaults.JumpEnabled)
	end
end

local function restoreCollisions()
	for part, canCollide in pairs(PlayerSettings.CollisionParts) do
		pcall(function() part.CanCollide = canCollide end)
	end
	table.clear(PlayerSettings.CollisionParts)
end

local function trackCollision(part)
	if PlayerSettings.Noclip and part:IsA("BasePart") and PlayerSettings.CollisionParts[part] == nil then
		PlayerSettings.CollisionParts[part] = part.CanCollide
	end
end

local function bindPlayerCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == PlayerSettings.Character and humanoid == PlayerSettings.Humanoid then return end
	for _, connection in ipairs(PlayerSettings.HumanoidConnections) do connection:Disconnect() end
	table.clear(PlayerSettings.HumanoidConnections)
	restoreCollisions()
	PlayerSettings.Character, PlayerSettings.Humanoid = character, humanoid
	PlayerSettings.HumanoidDefaults = nil
	if not humanoid then return end
	local movements = character:FindFirstChild("Movements")
	PlayerSettings.HumanoidDefaults = {
		Speed = humanoid.WalkSpeed,
		JumpPower = movements and 0 or humanoid.JumpPower,
		JumpHeight = movements and 0 or humanoid.JumpHeight,
		UseJumpPower = movements ~= nil or humanoid.UseJumpPower,
		JumpEnabled = movements == nil and humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
	}
	PlayerSettings.DefaultSpeed = humanoid.WalkSpeed
	PlayerSettings.DefaultJumpPower = PlayerSettings.HumanoidDefaults.JumpPower
	for _, property in ipairs({ "WalkSpeed", "JumpPower", "UseJumpPower" }) do
		connect(humanoid:GetPropertyChangedSignal(property), applyPlayerHumanoid, PlayerSettings.HumanoidConnections)
	end
	connect(humanoid.StateEnabledChanged, function(state)
		if state == Enum.HumanoidStateType.Jumping then applyPlayerHumanoid() end
	end, PlayerSettings.HumanoidConnections)
	connect(character.DescendantAdded, trackCollision, PlayerSettings.HumanoidConnections)
	if PlayerSettings.Noclip then
		for _, part in ipairs(character:QueryDescendants("BasePart")) do trackCollision(part) end
	end
	applyPlayerHumanoid()
end

local function applyPlayerFOV()
	local camera = PlayerSettings.Camera
	if Hub.Running and camera and camera == Workspace.CurrentCamera and PlayerSettings.FOV ~= nil
		and math.abs(camera.FieldOfView - PlayerSettings.FOV) > 0.0001 then
		camera.FieldOfView = PlayerSettings.FOV
	end
end

local function bindPlayerCamera()
	if PlayerSettings.CameraConnection then PlayerSettings.CameraConnection:Disconnect() end
	local previous = PlayerSettings.Camera
	if previous and PlayerSettings.FOV ~= nil then
		pcall(function() previous.FieldOfView = PlayerSettings.DefaultFOV end)
	end
	PlayerSettings.Camera = Workspace.CurrentCamera
	if PlayerSettings.Camera then
		PlayerSettings.CameraConnection = PlayerSettings.Camera:GetPropertyChangedSignal("FieldOfView"):Connect(applyPlayerFOV)
		applyPlayerFOV()
	end
end

function Hub.SetSpeed(value)
	if PlayerSettings.Syncing or not PlayerSettings.Ready then return end
	value = tonumber(value)
	if not value or value ~= value then return end
	PlayerSettings.Speed = math.clamp(value, 0, 200)
	applyPlayerHumanoid()
end

function Hub.ResetSpeed()
	PlayerSettings.Speed = nil
	local defaults = PlayerSettings.HumanoidDefaults
	local value = defaults and defaults.Speed or PlayerSettings.DefaultSpeed
	if PlayerSettings.Humanoid and defaults then PlayerSettings.Humanoid.WalkSpeed = value end
	syncPlayerControl("Speed", value)
end

function Hub.SetJumpPower(value)
	if PlayerSettings.Syncing or not PlayerSettings.Ready then return end
	value = tonumber(value)
	if not value or value ~= value then return end
	PlayerSettings.JumpPower = math.clamp(value, 0, 250)
	applyPlayerHumanoid()
end

function Hub.SetEnableJump(enabled)
	if PlayerSettings.Syncing or not PlayerSettings.Ready then return end
	PlayerSettings.EnableJump = enabled == true
	if not PlayerSettings.EnableJump and not PlayerSettings.InfJump then restorePlayerJump() end
	applyPlayerHumanoid()
end

function Hub.SetInfJump(enabled)
	if PlayerSettings.Syncing or not PlayerSettings.Ready then return end
	PlayerSettings.InfJump = enabled == true
	if not PlayerSettings.EnableJump and not PlayerSettings.InfJump then restorePlayerJump() end
	applyPlayerHumanoid()
end

function Hub.ResetJumpPower()
	PlayerSettings.JumpPower, PlayerSettings.EnableJump, PlayerSettings.InfJump = nil, false, false
	restorePlayerJump()
	syncPlayerControl("JumpPower", PlayerSettings.DefaultJumpPower)
	syncPlayerControl("EnableJump", false)
	syncPlayerControl("InfJump", false)
end

function Hub.SetFOV(value)
	if PlayerSettings.Syncing or not PlayerSettings.Ready then return end
	value = tonumber(value)
	if not value or value ~= value then return end
	PlayerSettings.FOV = math.clamp(value, 30, 120)
	applyPlayerFOV()
end

function Hub.ResetFOV()
	PlayerSettings.FOV = nil
	if PlayerSettings.Camera then PlayerSettings.Camera.FieldOfView = PlayerSettings.DefaultFOV end
	syncPlayerControl("FOV", PlayerSettings.DefaultFOV)
end

function Hub.SetNoclip(enabled)
	if PlayerSettings.Syncing or not PlayerSettings.Ready then return end
	PlayerSettings.Noclip = enabled == true
	if not PlayerSettings.Noclip then
		restoreCollisions()
	elseif PlayerSettings.Character then
		for _, part in ipairs(PlayerSettings.Character:QueryDescendants("BasePart")) do trackCollision(part) end
	end
end

function Hub.ResetPlayer()
	Hub.ResetSpeed()
	Hub.ResetJumpPower()
	Hub.ResetFOV()
	PlayerSettings.Noclip = false
	restoreCollisions()
	syncPlayerControl("Noclip", false)
end

function Hub.SetupPlayer()
	bindPlayerCharacter(Players.LocalPlayer.Character)
	bindPlayerCamera()
	connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), bindPlayerCamera, PlayerSettings.Connections)
	connect(RunService.PreSimulation, function()
		if not Hub.Running then return end
		bindPlayerCharacter(Players.LocalPlayer.Character)
		applyPlayerHumanoid()
		if PlayerSettings.Noclip then
			local active = playerCanMove(PlayerSettings.Humanoid)
			for part, canCollide in pairs(PlayerSettings.CollisionParts) do
				if not PlayerSettings.Character or not part:IsDescendantOf(PlayerSettings.Character) then
					pcall(function() part.CanCollide = canCollide end)
					PlayerSettings.CollisionParts[part] = nil
				elseif active and part.CanCollide then
					part.CanCollide = false
				elseif not active and part.CanCollide ~= canCollide then
					part.CanCollide = canCollide
				end
			end
		end
	end, PlayerSettings.Connections)
	connect(UserInputService.JumpRequest, function()
		if not PlayerSettings.InfJump or not playerCanMove(PlayerSettings.Humanoid)
			or os.clock() - PlayerSettings.LastJump < 0.15 then return end
		PlayerSettings.LastJump = os.clock()
		applyPlayerHumanoid()
		PlayerSettings.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end, PlayerSettings.Connections)
end

local function staminaStep()
	if not Hub.Running or not Stamina.Enabled then
		return
	end
	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or player:GetAttribute("Dead") or player:GetAttribute("Dying") then
		return
	end
	local gui = player:FindFirstChild("PlayerGui")
	local hud = gui and gui:FindFirstChild("MainHud")
	local frame = hud and hud:FindFirstChild("Frame")
	local playerFrame = frame and frame:FindFirstChild("PlayerFrame")
	local body = playerFrame and playerFrame:FindFirstChild("Body")
	local widget = body and body:FindFirstChild("Stamina")
	local movements = character:FindFirstChild("Movements")
	if character ~= Stamina.Character or widget ~= Stamina.Widget or movements ~= Stamina.Movements then
		Stamina.Character, Stamina.Widget, Stamina.Movements = character, widget, movements
		Stamina.Restore, Stamina.MissingSince = nil, nil
		Stamina.NextProbe = 0
	end
	if not widget or not movements then
		return
	end
	if not Stamina.Restore and os.clock() >= Stamina.NextProbe then
		Stamina.NextProbe = os.clock() + 1
		local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
		local playerRemotes = remotes and remotes:FindFirstChild("Player")
		local restoreEvent = playerRemotes and playerRemotes:FindFirstChild("StaminaRestore")
		if restoreEvent then
			local ok, connections = pcall(getconnections, restoreEvent.OnClientEvent)
			if ok then
				for _, connection in ipairs(connections) do
					local callback = connection.Function
					if connection.Enabled and type(callback) == "function" then
						local envOk, env = pcall(getfenv, callback)
						if envOk and env.script == movements then
							local valuesOk, values = pcall(debug.getupvalues, callback)
							if valuesOk then
								for _, value in pairs(values) do
									if value == widget then
										Stamina.Restore = callback
										break
									end
								end
							end
						end
					end
					if Stamina.Restore then break end
				end
			end
		end
		if not Stamina.Restore then
			Stamina.MissingSince = Stamina.MissingSince or os.clock()
			if os.clock() - Stamina.MissingSince >= 8 then
				Hub.Controls.InfStamina:Set(false)
				Hub.Notify("Inf Stamina", "The stamina restore handler could not be found.", "Warning")
			end
		end
	end
	if not Stamina.Restore or player:GetAttribute("Stunned") or player:GetAttribute("Rooted")
		or character:GetAttribute("AnimationLocked") then
		return
	end
	local current = tonumber(widget:GetAttribute("StaminaValue"))
	local maximum = tonumber(widget:GetAttribute("StaminaValueMAX"))
	if current and maximum and current < maximum then
		local ok, failure = pcall(Stamina.Restore, 1, 0)
		if not ok then
			Hub.Controls.InfStamina:Set(false)
			Hub.Notify("Inf Stamina", "Stamina restore failed. The feature is paused.", "Warning")
			warn("[TheBackrooms] Inf Stamina: " .. tostring(failure))
		end
	end
end

function Hub.SetInfStamina(enabled)
	Stamina.Enabled = enabled == true and Hub.Running
	if Stamina.Connection then
		Stamina.Connection:Disconnect()
		Stamina.Connection = nil
	end
	Stamina.Restore, Stamina.Character, Stamina.Widget, Stamina.Movements = nil, nil, nil, nil
	Stamina.MissingSince, Stamina.NextProbe = nil, 0
	if not Stamina.Enabled then
		return
	end
	if type(getconnections) ~= "function" or type(debug.getupvalues) ~= "function" then
		Stamina.Enabled = false
		Hub.Controls.InfStamina:Set(false, true)
		Hub.Notify("Inf Stamina", "This executor cannot access the stamina restore handler.", "Warning")
		return
	end
	Stamina.Connection = RunService.Heartbeat:Connect(staminaStep)
	staminaStep()
end

function Hub.SetItemsAura(enabled)
	Aura.Enabled = enabled == true and Hub.Running
	if Aura.Enabled and type(fireproximityprompt) ~= "function" then
		Aura.Enabled = false
		Hub.Controls.ItemsAura:Set(false, true)
		Hub.Notify("Items Aura", "This executor does not support fireproximityprompt.", "Warning")
	end
	if not Aura.Enabled then
		table.clear(Aura.Cooldowns)
	end
end

function Hub.InventoryState()
	local inventories = ReplicatedStorage:FindFirstChild("Inventories")
	local inventory = inventories and inventories:FindFirstChild(tostring(Players.LocalPlayer.UserId))
	local capacity = Players.LocalPlayer:GetAttribute("HasExtraInventorySlot") == true and 5 or 4
	return inventory, inventory and inventory:GetChildren() or {}, capacity
end

function Hub.CarryWeight()
	local inventory, items = Hub.InventoryState()
	if not inventory then return nil end
	local weight = 0
	for _, item in ipairs(items) do
		weight += tonumber(item:GetAttribute("weight")) or 0
	end
	local player = Players.LocalPlayer
	local towWeight = tonumber(player:GetAttribute("TowWeight")) or 0
	local multiplier = tonumber(player:GetAttribute("PerkWeightMult")) or 1
	return math.round((weight + towWeight) * multiplier)
end

function Hub.SetLightItems(enabled)
	enabled = enabled == true and Hub.Running
	if enabled == LightItems.Enabled then return end
	LightItems.Enabled = enabled
	local player = Players.LocalPlayer
	if not enabled then
		for _, connection in ipairs(LightItems.Connections) do connection:Disconnect() end
		table.clear(LightItems.Connections)
		local weight = Hub.CarryWeight()
		player:SetAttribute("weight", weight ~= nil and weight or LightItems.SavedWeight)
		LightItems.SavedWeight = nil
		return
	end
	LightItems.SavedWeight = player:GetAttribute("weight")
	local function apply()
		if LightItems.Enabled and player:GetAttribute("weight") ~= 0 then
			LightItems.SavedWeight = player:GetAttribute("weight")
			player:SetAttribute("weight", 0)
		end
	end
	connect(player:GetAttributeChangedSignal("weight"), apply, LightItems.Connections)
	connect(player.CharacterAdded, function()
		task.defer(apply)
	end, LightItems.Connections)
	player:SetAttribute("weight", 0)
end

local function heldTelevision()
	local player = Players.LocalPlayer
	if ReplicatedStorage:GetAttribute("LevelVariant") ~= "Level188-SpecialLevel" or player:GetAttribute("DraggingTv") ~= true then return nil end
	local container = itemsContainer()
	if container then
		for _, item in ipairs(container:GetChildren()) do
			if item:IsA("Model") and item:GetAttribute("Level188Tv") == true
				and tonumber(item:GetAttribute("HeldBy")) == player.UserId and item:GetAttribute("depositedAt") == nil then
				return item
			end
		end
	end
	return nil
end

function Hub.ShouldDeliver()
	local tv = heldTelevision()
	if tv then
		return true, math.max(0, tonumber(tv:GetAttribute("price")) or 0), tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit")) or 0, tv
	end
	local inventory, items, capacity = Hub.InventoryState()
	if not inventory or #items == 0 then
		return false, 0, 0
	end
	local player = Players.LocalPlayer
	local full = #items >= capacity or player:GetAttribute("HandsFull") == true
		or player:GetAttribute("BothHandsHold") == true
	local value = 0
	for _, item in ipairs(items) do
		value += math.max(0, tonumber(item:GetAttribute("price")) or 0)
		if item:GetAttribute("requiresBothHands") == true then
			full = true
		end
	end
	local profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit"))
	local quota = tonumber(ReplicatedStorage:GetAttribute("ProfitQuota"))
	local coversGoal = profit ~= nil and quota ~= nil and quota > profit and value >= quota - profit
	return full or coversGoal, value, profit or 0
end

function Hub.GoalMet()
	if ReplicatedStorage:GetAttribute("QuotaMet") == true then
		return true
	end
	local profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit"))
	local quota = tonumber(ReplicatedStorage:GetAttribute("ProfitQuota"))
	if profit and quota and quota > 0 then
		return profit >= quota
	end
	return nil
end

local function roomDestination(root, humanoid)
	local triggers = Workspace:FindFirstChild("GameTriggers")
	local entrance = triggers and triggers:FindFirstChild("AutoDropItems")
	local room = triggers and triggers:FindFirstChild("HQZone")
	if not entrance or not entrance:IsA("BasePart") or not room or not room:IsA("BasePart") then
		return nil
	end
	local inward = Vector3.new(room.Position.X - entrance.Position.X, 0, room.Position.Z - entrance.Position.Z)
	inward = inward.Magnitude > 0.1 and inward.Unit or -entrance.CFrame.RightVector
	local floorY = entrance.Position.Y - entrance.Size.Y / 2
	local position = Vector3.new(entrance.Position.X, floorY + humanoid.HipHeight + root.Size.Y / 2 + 0.9, entrance.Position.Z)
	local inside = position + inward * 3
	return CFrame.lookAt(position, position + inward), CFrame.lookAt(inside, inside + inward), triggers, entrance
end

function Hub.SetAutoReturn(enabled)
	ReturnToRoom.Enabled = enabled == true and Hub.Running
	ReturnToRoom.Completed = nil
end

local function autoReturnStep()
	if not Hub.Running or not ReturnToRoom.Enabled or Delivery.Busy or Farm.Enabled then
		return
	end
	if Hub.GoalMet() ~= true then
		ReturnToRoom.Completed = nil
		return
	end
	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or player:GetAttribute("Dead")
		or player:GetAttribute("Dying") or player:GetAttribute("InLocker") then
		return
	end
	local _, target, triggers, entrance = roomDestination(root, humanoid)
	if not target then
		return
	end
	local level = ReplicatedStorage:GetAttribute("LevelNumber")
	local map = triggers:FindFirstChild("GeneratedMap")
	local completed = ReturnToRoom.Completed
	if completed and completed.Character == character and completed.Level == level
		and completed.Map == map and completed.Entrance == entrance then
		return
	end
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	ReturnToRoom.Completed = { Character = character, Level = level, Map = map, Entrance = entrance }
	Hub.Notify("Auto Return", "Goal complete. Returned to the delivery room.", "Success")
end

local function finishDelivery(job)
	if Delivery.Job ~= job then
		return
	end
	Delivery.Job = nil
	Delivery.Busy = false
	Delivery.NextAttempt = os.clock() + 3
end

function Hub.SetAutoDeliver(enabled)
	Delivery.Enabled = enabled == true and Hub.Running
	if not Delivery.Enabled and Delivery.Job then
		Delivery.Job.Cancelled = true
		finishDelivery(Delivery.Job)
	end
end

function Hub.TeleportToRoom()
	if not Hub.Running then
		return
	end
	if Farm.Enabled then Hub.Controls.FarmEnabled:Set(false) end
	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or player:GetAttribute("Dead")
		or player:GetAttribute("Dying") or player:GetAttribute("InLocker") then
		return
	end
	local _, target = roomDestination(root, humanoid)
	if not target then
		Hub.Notify("Teleport to Room", "The delivery room is not available yet.", "Warning")
		return
	end
	if Delivery.Job then
		Delivery.Job.Cancelled = true
		finishDelivery(Delivery.Job)
	end
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function deliveryActive(job)
	return Hub.Running and Delivery.Enabled and Delivery.Job == job and not job.Cancelled
		and Players.LocalPlayer.Character == job.Character and job.Root.Parent ~= nil
		and job.Humanoid.Health > 0 and not Players.LocalPlayer:GetAttribute("Dead")
		and not Players.LocalPlayer:GetAttribute("Dying")
		and ReplicatedStorage:GetAttribute("LevelNumber") == job.Level
		and Workspace:FindFirstChild("GameTriggers") == job.Triggers
		and job.Triggers:FindFirstChild("GeneratedMap") == job.Map
end

local function deliveryWait(job, seconds, condition)
	local deadline = os.clock() + seconds
	repeat
		if not deliveryActive(job) then
			return false
		end
		if condition and condition() then
			return true
		end
		task.wait(0.1)
	until os.clock() >= deadline
	return deliveryActive(job) and (not condition or condition())
end

local function deliveryStep()
	if not Hub.Running or not Delivery.Enabled or Delivery.Busy or Farm.Enabled or os.clock() < Delivery.NextAttempt then
		return
	end
	if ReturnToRoom.Enabled and Hub.GoalMet() == true then
		return
	end
	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local shouldDeliver, deliveredValue, profitBefore, tv = Hub.ShouldDeliver()
	if not root or not humanoid or humanoid.Health <= 0 or player:GetAttribute("Dead")
		or player:GetAttribute("Dying") or (player:GetAttribute("inventoryLocked") and not tv)
		or player:GetAttribute("InLocker") or player:GetAttribute("Swinging") or player:GetAttribute("Throwing") then
		return
	end
	if not shouldDeliver then
		return
	end
	local entryTarget, insideTarget, triggers = roomDestination(root, humanoid)
	if not entryTarget then
		return
	end
	if tv then entryTarget = insideTarget end
	local job = {
		Character = character, Root = root, Humanoid = humanoid,
		Level = ReplicatedStorage:GetAttribute("LevelNumber"),
		Triggers = triggers, Map = triggers:FindFirstChild("GeneratedMap"),
		Origin = root.CFrame,
		ProfitBefore = profitBefore,
	}
	Delivery.Job = job
	Delivery.Busy = true
	local confirmed = false
	local result
	local ok, failure = xpcall(function()
		root.CFrame = entryTarget
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		confirmed = deliveryWait(job, 5, function()
			if tv then return tv:GetAttribute("depositedAt") ~= nil and player:GetAttribute("DraggingTv") ~= true end
			local inventory, items = Hub.InventoryState()
			return inventory ~= nil and #items == 0
		end)
		if not confirmed then
			return
		end
		deliveryWait(job, 0.8, function()
			local profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit"))
			return Hub.GoalMet() == true or (profit ~= nil and profit >= job.ProfitBefore + deliveredValue)
		end)
		if not deliveryActive(job) then
			return
		end
		local goalMet = Hub.GoalMet()
		if goalMet == false then
			root.CFrame = job.Origin
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			result = "Returned"
		else
			result = goalMet and "Goal complete" or "Goal unavailable"
		end
	end, debug.traceback)
	local cancelled = not deliveryActive(job)
	finishDelivery(job)
	Delivery.LastResult = result or (cancelled and "Cancelled" or "Unconfirmed")
	if result == "Returned" then
		Hub.Notify("Auto Deliver", "Items delivered. Returned to the previous position.", "Success")
	elseif result == "Goal complete" then
		Hub.Notify("Auto Deliver", "Goal complete. Staying in the delivery room.", "Success")
	elseif result == "Goal unavailable" then
		Hub.Notify("Auto Deliver", "Items delivered. Waiting in the room because Goal is unavailable.", "Warning")
	elseif not cancelled then
		Hub.Controls.AutoDeliver:Set(false)
		Hub.Notify("Auto Deliver", tv and "The television deposit was not confirmed. Auto Deliver is paused." or "Entered the room, but the inventory is still full. Auto Deliver is paused.", "Warning")
		if not ok then
			warn("[TheBackrooms] Auto Deliver: " .. tostring(failure))
		end
	end
end
local function auraStep()
	if not Hub.Running or not Aura.Enabled or Delivery.Busy or Farm.Enabled then
		return
	end
	if ReturnToRoom.Enabled and Hub.GoalMet() == true then
		return
	end
	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not humanoid or humanoid.Health <= 0 or player:GetAttribute("Dead") or player:GetAttribute("Dying") then
		return
	end
	local now = os.clock()
	if now - Aura.LastAttempt < 0.3 then
		return
	end
	local candidates = {}
	local container = itemsContainer()
	if container then
		for _, item in ipairs(container:GetChildren()) do
			candidates[item] = true
		end
	end
	for _, item in ipairs(CollectionService:GetTagged("CollectableItem")) do
		if item:IsDescendantOf(Workspace) then
			candidates[item] = true
		end
	end
	local nearestItem, nearestPrompt
	local nearestDistance = math.huge
	for item in pairs(candidates) do
		if not isMonster(item) and isFreeInWorld(item) and now >= (Aura.Cooldowns[item] or 0) then
			local anchor = anchorPart(item)
			local prompt = anchor and anchor:FindFirstChildOfClass("ProximityPrompt")
			if anchor and prompt and prompt.Enabled then
				local distance = (root.Position - anchor.Position).Magnitude
				if distance <= math.min(prompt.MaxActivationDistance, 8) and distance < nearestDistance then
					local visible = true
					if prompt.RequiresLineOfSight then
						local camera = Workspace.CurrentCamera
						local origin = camera and camera.CFrame.Position or root.Position
						local parameters = RaycastParams.new()
						parameters.FilterType = Enum.RaycastFilterType.Exclude
						parameters.FilterDescendantsInstances = { character }
						local hit = Workspace:Raycast(origin, anchor.Position - origin, parameters)
						visible = not hit or hit.Instance == item or hit.Instance:IsDescendantOf(item)
					end
					if visible then
						nearestItem, nearestPrompt, nearestDistance = item, prompt, distance
					end
				end
			end
		end
	end
	if nearestPrompt and Aura.Enabled and Hub.Running then
		Aura.LastAttempt = now
		Aura.Cooldowns[nearestItem] = now + 1.5
		local success, failure = pcall(fireproximityprompt, nearestPrompt)
		if not success then
			Hub.Controls.ItemsAura:Set(false)
			Hub.Notify("Items Aura", "Pickup failed: " .. tostring(failure), "Warning")
		end
	end
end

function Hub.FarmMonsters()
	local triggers = Workspace:FindFirstChild("GameTriggers")
	local entities = triggers and triggers:FindFirstChild("SpawnedEntities")
	local candidates, result = {}, {}
	if entities then for _, item in ipairs(entities:GetChildren()) do candidates[item] = true end end
	for _, item in ipairs(CollectionService:GetTagged("NpcReadyGameTag")) do candidates[item] = true end
	for item in pairs(candidates) do
		if item:IsDescendantOf(Workspace) and isMonster(item) then
			local humanoid = item:IsA("Model") and item:FindFirstChildOfClass("Humanoid")
			local anchor = item:FindFirstChild("HumanoidRootPart") or anchorPart(item)
			if anchor and (not humanoid or humanoid.Health > 0) then
				result[#result + 1] = { Item = item, Position = anchor.Position, Radius = math.min(anchor.Size.Magnitude / 2, 12) }
			end
		end
	end
	return result
end

function Hub.FarmDangerDistance(position, monsters)
	local distance = math.huge
	for _, monster in ipairs(monsters) do
		distance = math.min(distance, (monster.Position - position).Magnitude - monster.Radius)
	end
	return distance
end

local function farmPayload()
	local inventory, items, capacity = Hub.InventoryState()
	local payload = { Items = {}, Value = 0, Full = false }
	local player = Players.LocalPlayer
	payload.Full = #items >= capacity or player:GetAttribute("HandsFull") == true or player:GetAttribute("BothHandsHold") == true
	for _, item in ipairs(items) do
		if item:GetAttribute("requiresBothHands") == true then payload.Full = true end
		local value = tonumber(item:GetAttribute("price")) or 0
		if value > 0 and item:GetAttribute("useful") ~= true then
			payload.Items[#payload.Items + 1] = item
			payload.Value += value
		end
	end
	return inventory, items, payload
end

function Hub.FarmCandidates(root, monsters)
	local candidates, seen = {}, {}
	local container = itemsContainer()
	if container then for _, item in ipairs(container:GetChildren()) do seen[item] = true end end
	for _, item in ipairs(CollectionService:GetTagged("CollectableItem")) do seen[item] = true end
	local _, carried = Hub.InventoryState()
	local now = os.clock()
	for item in pairs(seen) do
		local price = tonumber(item:GetAttribute("price")) or 0
		if price > 0 and not isMonster(item) and isFreeInWorld(item) and item:GetAttribute("inShip") ~= true
			and item:GetAttribute("useful") ~= true and now >= (Farm.Cooldowns[item] or 0)
			and not (#carried > 0 and item:GetAttribute("requiresBothHands") == true) then
			local anchor = anchorPart(item)
			local prompt = anchor and anchor:FindFirstChildOfClass("ProximityPrompt")
			if anchor and prompt and prompt.Enabled then
				if Hub.FarmDangerDistance(anchor.Position, monsters) >= 36 then
					candidates[#candidates + 1] = {
						Item = item, Anchor = anchor, Prompt = prompt, Price = price,
						UID = item:GetAttribute("UID"), Distance = (root.Position - anchor.Position).Magnitude,
					}
				elseif not Farm.Avoided[item] then
					Farm.Avoided[item] = true
					Farm.Stats.Skipped += 1
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.Price ~= b.Price then return a.Price > b.Price end
		return a.Distance < b.Distance
	end)
	return candidates
end

local function farmStandingTarget(position, root, humanoid, monsters, maxDistance)
	local triggers = Workspace:FindFirstChild("GameTriggers")
	local excluded = { Players.LocalPlayer.Character }
	if triggers then
		for _, name in ipairs({ "Items", "SpawnedEntities", "DepositedItems" }) do
			local container = triggers:FindFirstChild(name)
			if container then excluded[#excluded + 1] = container end
		end
	end
	local rayParameters = RaycastParams.new()
	rayParameters.FilterType = Enum.RaycastFilterType.Exclude
	rayParameters.FilterDescendantsInstances = excluded
	rayParameters.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = excluded
	overlap.RespectCanCollide = true
	local offsets = {
		Vector3.zero, Vector3.new(2.5, 0, 0), Vector3.new(-2.5, 0, 0),
		Vector3.new(0, 0, 2.5), Vector3.new(0, 0, -2.5),
		Vector3.new(2, 0, 2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, -2),
	}
	for _, offset in ipairs(offsets) do
		local start = position + offset + Vector3.new(0, 3, 0)
		local hit = Workspace:Raycast(start, Vector3.new(0, -24, 0), rayParameters)
		if hit and hit.Normal.Y > 0.7 then
			local point = Vector3.new(start.X, hit.Position.Y + humanoid.HipHeight + root.Size.Y / 2 + 0.15, start.Z)
			if (point - position).Magnitude <= maxDistance and Hub.FarmDangerDistance(point, monsters) >= 30 then
				local lookAt = Vector3.new(position.X, point.Y, position.Z)
				if (lookAt - point).Magnitude < 0.1 then lookAt = point + Vector3.new(1, 0, 0) end
				local target = CFrame.lookAt(point, lookAt)
				local obstacles = Workspace:GetPartBoundsInBox(target, Vector3.new(2.2, 4.6, 2.2), overlap)
				if #obstacles == 0 then return target end
			end
		end
	end
	return nil
end

local function farmTeleport(root, target)
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function farmSafeRoom(root, humanoid, monsters)
	local entry, inside = roomDestination(root, humanoid)
	if not entry then return nil end
	local inward = (inside.Position - entry.Position).Unit
	return farmStandingTarget(entry.Position + inward * 15, root, humanoid, monsters, 10)
		or (Hub.FarmDangerDistance(inside.Position, monsters) >= 30 and inside or nil)
end

function Hub.UpdateFarmStats()
	if not Hub.FarmLabels then return end
	local elapsed = Farm.Elapsed + (Farm.Enabled and os.clock() - Farm.StartedAt or 0)
	local profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit")) or 0
	local quota = tonumber(ReplicatedStorage:GetAttribute("ProfitQuota")) or 0
	local rows = {
		Status = "Status: " .. Farm.Status,
		Collected = "Items Collected: " .. Farm.Stats.Collected,
		Delivered = "Items Delivered: " .. Farm.Stats.Delivered,
		Value = "Value Delivered: $" .. numberText(Farm.Stats.Value),
		Floors = "Floors Completed: " .. Farm.Stats.Floors,
		Skipped = "Unsafe Items Skipped: " .. Farm.Stats.Skipped,
		Escapes = "Monster Escapes: " .. Farm.Stats.Escapes,
		Goal = "Goal: $" .. numberText(profit) .. " / $" .. numberText(quota),
		Time = string.format("Session Time: %02d:%02d", math.floor(elapsed / 60), math.floor(elapsed % 60)),
	}
	for key, text in pairs(rows) do Hub.FarmLabels[key]:Set(text) end
end

function Hub.SetAutoFarm(enabled)
	enabled = enabled == true and Hub.Running
	if enabled == Farm.Enabled then return end
	Farm.Epoch += 1
	Farm.Job, Farm.WaitingLevel, Farm.RoomArrival, Farm.RunStage = nil, nil, nil, nil
	if not enabled then
		Farm.Elapsed += os.clock() - Farm.StartedAt
		Farm.Enabled, Farm.Status = false, "Disabled"
		if Farm.NoclipBackup and not Hub.Unloading then Hub.Controls.Noclip:Set(true) end
		Farm.NoclipBackup = nil
		Hub.UpdateFarmStats()
		return
	end
	if type(fireproximityprompt) ~= "function" then
		Hub.Controls.FarmEnabled:Set(false, true)
		Farm.Status = "Pickup unavailable"
		Hub.Notify("Auto Farm", "This executor does not support item collection.", "Warning")
		Hub.UpdateFarmStats()
		return
	end
	if Delivery.Job then
		Delivery.Job.Cancelled = true
		finishDelivery(Delivery.Job)
	end
	Farm.Enabled, Farm.StartedAt, Farm.Status = true, os.clock(), "Starting"
	Farm.NoclipBackup = PlayerSettings.Noclip
	if PlayerSettings.Noclip then Hub.Controls.Noclip:Set(false) end
	Farm.Level, Farm.Map, Farm.Character = nil, nil, nil
	Farm.NextAction, Farm.NextEscape = os.clock() + 0.4, 0
	Farm.Cooldowns, Farm.Avoided = setmetatable({}, { __mode = "k" }), {}
	Hub.UpdateFarmStats()
end

local function farmBeginDelivery(root, humanoid, payload, monsters)
	local entry = roomDestination(root, humanoid)
	if not entry then Farm.Status = "Waiting for delivery room"; return end
	if Hub.FarmDangerDistance(entry.Position, monsters) < 28 then
		local safe = farmSafeRoom(root, humanoid, monsters)
		if safe then farmTeleport(root, safe) end
		Farm.Status, Farm.NextAction = "Waiting for safe delivery", os.clock() + 1
		return
	end
	Farm.Job = {
		Stage = "Deliver", Count = #payload.Items, Value = payload.Value,
		Profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit")) or 0,
		Expires = os.clock() + 6,
	}
	Farm.Status = "Delivering items"
	farmTeleport(root, entry)
end

local function farmRunFloor(root, monsters)
	if ReplicatedStorage:GetAttribute("LevelVariant") ~= "LevelRun" or Hub.GoalMet() == true then return false end
	local player = Players.LocalPlayer
	local map = Farm.Map
	if player:GetAttribute("LevelRunFalling") then
		Farm.Status = "Waiting for route cutscene"
		return true
	end
	if Farm.RunStage == "Exit" then
		Farm.Status = "Waiting for chase floor completion"
		return true
	end
	if player:GetAttribute("LevelRunChase") == true then
		local exit = map:FindFirstChild("EndFallTrigger", true)
		if exit and exit:IsA("BasePart") and Hub.FarmDangerDistance(exit.Position, monsters) >= 36 then
			Farm.RunStage, Farm.Status = "Exit", "Completing chase floor"
			farmTeleport(root, exit.CFrame)
		else
			Farm.Status = "Waiting for safe chase exit"
		end
		return true
	end
	if player:GetAttribute("LevelRunActive") == true then
		if Farm.RunStage ~= "Chase" then
			local start = map:FindFirstChild("StartChase", true)
			if start and start:IsA("BasePart") and Hub.FarmDangerDistance(start.Position, monsters) >= 30 then
				Farm.RunStage, Farm.Status = "Chase", "Entering chase route"
				farmTeleport(root, start.CFrame)
			else
				Farm.Status = "Waiting for safe chase entry"
			end
		else
			Farm.Status = "Waiting for chase route"
		end
		return true
	end
	if not Farm.RunStage then
		local entry = map:FindFirstChild("FallCutsceneTrigger", true)
		if entry and entry:IsA("BasePart") and Hub.FarmDangerDistance(entry.Position, monsters) >= 36 then
			Farm.RunStage, Farm.Status = "Entry", "Entering chase floor"
			farmTeleport(root, entry.CFrame)
		else
			Farm.Status = "Waiting for safe special floor"
		end
	else
		Farm.Status = "Waiting for chase entry cutscene"
	end
	return true
end

function Hub.FarmTVs(root, monsters)
	local result = {}
	local container = itemsContainer()
	if not container then return result end
	for _, item in ipairs(container:GetChildren()) do
		if item:IsA("Model") and item:GetAttribute("Level188Tv") == true
			and item:GetAttribute("depositedAt") == nil and (tonumber(item:GetAttribute("HeldBy")) or 0) == 0
			and os.clock() >= (Farm.Cooldowns[item] or 0) then
			local prompt = item:FindFirstChild("DragPrompt", true)
			local anchor = prompt and prompt.Parent
			if prompt and prompt.Enabled and anchor and anchor:IsA("BasePart") then
				if Hub.FarmDangerDistance(anchor.Position, monsters) >= 36 then
					result[#result + 1] = {
						Item = item, Anchor = anchor, Prompt = prompt,
						Price = tonumber(item:GetAttribute("price")) or 0,
						Distance = (root.Position - anchor.Position).Magnitude,
					}
				elseif not Farm.Avoided[item] then
					Farm.Avoided[item], Farm.Stats.Skipped = true, Farm.Stats.Skipped + 1
				end
			end
		end
	end
	table.sort(result, function(a, b)
		if a.Price ~= b.Price then return a.Price > b.Price end
		return a.Distance < b.Distance
	end)
	return result
end

local function farmTVDeliveryTarget(root, humanoid, monsters)
	local _, inside = roomDestination(root, humanoid)
	if inside and Hub.FarmDangerDistance(inside.Position, monsters) >= 30 then return inside end
	return nil
end

local function farmTVFloor(root, humanoid, monsters)
	if ReplicatedStorage:GetAttribute("LevelVariant") ~= "Level188-SpecialLevel" then return false end
	local player = Players.LocalPlayer
	local now = os.clock()
	local job = Farm.Job
	if job and job.TV then
		local tv = job.TV
		if not tv.Parent then Farm.Job = nil; return true end
		local deposited = tv:GetAttribute("depositedAt") ~= nil
		local held = tonumber(tv:GetAttribute("HeldBy")) == player.UserId
		if deposited and job.Stage ~= "TVConfirm" then
			job.Stage, job.Expires = "TVConfirm", now + 3
		end
		if job.Stage == "TVPickup" then
			if held and player:GetAttribute("DraggingTv") == true then
				Farm.Stats.Collected += 1
				job.Stage, job.Expires = "TVCarry", now + 8
			elseif now >= job.Expires then
				Farm.Cooldowns[tv], Farm.Job = now + 10, nil
			elseif not job.Fired and now >= job.FireAt then
				if not job.Prompt.Parent or not job.Prompt.Enabled
					or Hub.FarmDangerDistance(job.Anchor.Position, monsters) < 36
					or (root.Position - job.Anchor.Position).Magnitude > job.Prompt.MaxActivationDistance then
					Farm.Cooldowns[tv], Farm.Job = now + 10, nil
					return true
				end
				job.Fired = true
				local ok, failure = pcall(fireproximityprompt, job.Prompt, job.Prompt.HoldDuration)
				if not ok then error(failure) end
			end
		elseif job.Stage == "TVCarry" then
			if not held and player:GetAttribute("DraggingTv") ~= true then
				Farm.Cooldowns[tv], Farm.Job = now + 8, nil
				return true
			end
			local target = farmTVDeliveryTarget(root, humanoid, monsters)
			if target then
				farmTeleport(root, target)
				job.Stage, job.Expires = "TVDeliver", now + 6
				Farm.Status = "Delivering television"
			else
				Farm.Status = "Waiting for safe TV delivery"
			end
		elseif job.Stage == "TVDeliver" then
			if now >= job.Expires then
				Hub.Controls.FarmEnabled:Set(false)
				Farm.Status = "Paused: television transport failed"
			end
		elseif job.Stage == "TVConfirm" then
			local profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit")) or 0
			if deposited and profit > job.Profit then
				Farm.Stats.Delivered += 1
				Farm.Stats.Value += math.min(job.Price, profit - job.Profit)
				Farm.Job, Farm.NextAction = nil, now + 0.2
			elseif now >= job.Expires then
				Hub.Controls.FarmEnabled:Set(false)
				Farm.Status = "Paused: television deposit was not confirmed"
				Hub.Notify("Auto Farm", "The television deposit was not confirmed. Auto Farm is paused.", "Warning")
			end
		end
		return true
	end
	local container = itemsContainer()
	if container and player:GetAttribute("DraggingTv") == true then
		for _, tv in ipairs(container:GetChildren()) do
			if tv:GetAttribute("Level188Tv") and tonumber(tv:GetAttribute("HeldBy")) == player.UserId then
				Farm.Job = {
					Stage = "TVCarry", TV = tv, Price = tonumber(tv:GetAttribute("price")) or 0,
					Profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit")) or 0,
				}
				return true
			end
		end
		Farm.Status = "Waiting for television"
		return true
	end
	if Hub.GoalMet() == true then return false end
	if Hub.FarmDangerDistance(root.Position, monsters) < 24 and now >= Farm.NextEscape then
		local safe = farmSafeRoom(root, humanoid, monsters)
		if safe then
			farmTeleport(root, safe)
			Farm.Stats.Escapes += 1
			Farm.Status, Farm.NextAction, Farm.NextEscape = "Escaping monster", now + 0.6, now + 2
			return true
		end
	end
	for _, candidate in ipairs(Hub.FarmTVs(root, monsters)) do
		local collider = candidate.Item:FindFirstChild("Collider")
		local front = collider and candidate.Anchor.Position - collider.Position or candidate.Anchor.CFrame.LookVector
		front = Vector3.new(front.X, 0, front.Z)
		front = front.Magnitude > 0.01 and front.Unit or Vector3.new(1, 0, 0)
		local point = candidate.Anchor.Position + front * 3
		local target = farmStandingTarget(point, root, humanoid, monsters, math.max(2, candidate.Prompt.MaxActivationDistance - 3.2))
		if target and (target.Position - candidate.Anchor.Position).Magnitude < candidate.Prompt.MaxActivationDistance - 0.2 then
			Farm.Job = {
				Stage = "TVPickup", TV = candidate.Item, Anchor = candidate.Anchor, Prompt = candidate.Prompt,
				Price = candidate.Price, Profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit")) or 0,
				FireAt = now + 0.3, Expires = now + 3,
			}
			Farm.Status = "Collecting television"
			farmTeleport(root, target)
			return true
		end
		Farm.Cooldowns[candidate.Item] = now + 8
	end
	Farm.Status, Farm.NextAction = "Waiting for safe televisions", now + 1
	return true
end

function Hub.AutoFarmStep()
	if not Hub.Running or not Farm.Enabled then return end
	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or player:GetAttribute("Dead") or player:GetAttribute("Dying") then
		Farm.Job, Farm.Status = nil, "Waiting for respawn"
		return
	end
	local now = os.clock()
	local triggers = Workspace:FindFirstChild("GameTriggers")
	local map = triggers and triggers:FindFirstChild("GeneratedMap")
	local level = ReplicatedStorage:GetAttribute("LevelNumber")
	if level ~= Farm.Level or map ~= Farm.Map or character ~= Farm.Character then
		if Farm.Level and level and level > Farm.Level then
			Farm.Stats.Floors += level - Farm.Level
		end
		Farm.Level, Farm.Map, Farm.Character = level, map, character
		Farm.Job, Farm.WaitingLevel, Farm.RoomArrival, Farm.RunStage = nil, nil, nil, nil
		Farm.Cooldowns, Farm.Avoided = setmetatable({}, { __mode = "k" }), {}
		Farm.NextAction, Farm.Status = now + 0.7, "Waiting for floor"
	end
	if not map or #map:GetChildren() == 0 or ReplicatedStorage:GetAttribute("Mode") ~= "HQ" then
		Farm.Status = "Waiting for floor transition"
		return
	end
	local draggingTV = ReplicatedStorage:GetAttribute("LevelVariant") == "Level188-SpecialLevel" and player:GetAttribute("DraggingTv") == true
	if not playerCanMove(humanoid) or (player:GetAttribute("inventoryLocked") and not draggingTV) or player:GetAttribute("Swinging") or player:GetAttribute("Throwing") then
		Farm.Status = "Waiting for player"
		return
	end
	if PlayerSettings.Noclip then Hub.Controls.Noclip:Set(false) end
	if now < Farm.NextAction then return end
	local inventory, carried, payload = farmPayload()
	if not inventory then Farm.Status = "Waiting for inventory"; return end
	local monsters = Hub.FarmMonsters()
	if farmRunFloor(root, monsters) then return end
	if farmTVFloor(root, humanoid, monsters) then return end
	local job = Farm.Job
	if job and job.Stage == "Pickup" then
		local acquired = false
		for _, item in ipairs(carried) do
			if job.UID ~= nil and item:GetAttribute("UID") == job.UID then acquired = true; break end
		end
		if job.UID == nil then acquired = #carried > job.BeforeCount end
		if acquired then
			Farm.Stats.Collected += 1
			Farm.Job, job = nil, nil
			Farm.NextAction = now + 0.15
		end
	end
	if Hub.FarmDangerDistance(root.Position, monsters) < 24 and now >= Farm.NextEscape then
		local safe = farmSafeRoom(root, humanoid, monsters)
		if safe then
			farmTeleport(root, safe)
			Farm.Stats.Escapes += 1
			Farm.Job, Farm.Status, Farm.NextAction, Farm.NextEscape = nil, "Escaping monster", now + 0.6, now + 2
			return
		end
	end
	job = Farm.Job
	if job and job.Stage == "Pickup" then
		if now >= job.Expires or (not job.Fired and (not isFreeInWorld(job.Item) or not job.Prompt.Parent)) then
			Farm.Cooldowns[job.Item] = now + 8
			Farm.Job, Farm.Status = nil, "Choosing another item"
			return
		end
		if not job.Fired and now >= job.FireAt then
			if Hub.FarmDangerDistance(job.Anchor.Position, monsters) < 36
				or (root.Position - job.Anchor.Position).Magnitude > job.Prompt.MaxActivationDistance then
				Farm.Cooldowns[job.Item], Farm.Job = now + 8, nil
				return
			end
			job.Fired = true
			local epoch = Farm.Epoch
			local ok, failure = pcall(fireproximityprompt, job.Prompt, job.Prompt.HoldDuration)
			if not ok and Farm.Enabled and Farm.Epoch == epoch then error(failure) end
		end
		return
	elseif job and job.Stage == "Deliver" then
		if #payload.Items == 0 then
			job.Stage, job.Expires = "ConfirmDelivery", now + 1.5
		elseif now >= job.Expires then
			Hub.Controls.FarmEnabled:Set(false)
			Farm.Status = "Paused: delivery was not confirmed"
			Hub.Notify("Auto Farm", "Items were not delivered. Auto Farm is paused.", "Warning")
		end
		return
	elseif job and job.Stage == "ConfirmDelivery" then
		local profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit")) or 0
		if profit >= job.Profit + job.Value or now >= job.Expires then
			if profit > job.Profit then
				Farm.Stats.Delivered += job.Count
				Farm.Stats.Value += math.min(job.Value, profit - job.Profit)
				Farm.Job = nil
			else
				Hub.Controls.FarmEnabled:Set(false)
				Farm.Status = "Paused: deposit was not credited"
				Hub.Notify("Auto Farm", "The deposit was not credited. Auto Farm is paused.", "Warning")
			end
		end
		return
	end
	local profit = tonumber(ReplicatedStorage:GetAttribute("CurrentLevelProfit"))
	local quota = tonumber(ReplicatedStorage:GetAttribute("ProfitQuota"))
	local goalMet = Hub.GoalMet() == true
	if #payload.Items > 0 and (payload.Full or goalMet or (profit and quota and quota > profit and payload.Value >= quota - profit)) then
		farmBeginDelivery(root, humanoid, payload, monsters)
		return
	end
	if goalMet then
		Farm.WaitingLevel = level
		if not Farm.RoomArrival then
			local safe = farmSafeRoom(root, humanoid, monsters)
			if not safe then Farm.Status = "Waiting for safe room"; return end
			farmTeleport(root, safe)
			Farm.RoomArrival = true
		end
		local countdown = tonumber(ReplicatedStorage:GetAttribute("AutoDeepIn"))
		Farm.Status = countdown and string.format("Next floor in %ds", countdown) or "Waiting for automatic next floor"
		return
	end
	if payload.Full then Farm.Status = "Free an inventory slot to continue"; return end
	local candidates = Hub.FarmCandidates(root, monsters)
	for _, candidate in ipairs(candidates) do
		local target = farmStandingTarget(candidate.Anchor.Position, root, humanoid, monsters, candidate.Prompt.MaxActivationDistance - 0.2)
		if target then
			Farm.Job = {
				Stage = "Pickup", Item = candidate.Item, Anchor = candidate.Anchor, Prompt = candidate.Prompt,
				UID = candidate.UID, BeforeCount = #carried, FireAt = now + 0.3, Expires = now + 2.5,
			}
			Farm.Status = "Collecting " .. tostring(candidate.Item:GetAttribute("name") or candidate.Item.Name)
			farmTeleport(root, target)
			return
		else
			Farm.Cooldowns[candidate.Item] = now + 10
		end
	end
	if #payload.Items > 0 then
		farmBeginDelivery(root, humanoid, payload, monsters)
	else
		Farm.Status, Farm.NextAction = "Waiting for safe items", now + 1
	end
end

function Hub.SetAntiAFK(enabled)
	Hub.AntiAFK = enabled == true and Hub.Running
	if Hub.AntiAFK and not Hub.IdleConnection then
		Hub.IdleConnection = Players.LocalPlayer.Idled:Connect(function()
			if not Hub.Running or not Hub.AntiAFK then
				return
			end
			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:Button2Down(Vector2.zero, camera.CFrame)
			end)
			task.delay(0.2, function()
				pcall(function()
					VirtualUser:Button2Up(Vector2.zero, camera.CFrame)
				end)
			end)
		end)
	elseif not Hub.AntiAFK and Hub.IdleConnection then
		Hub.IdleConnection:Disconnect()
		Hub.IdleConnection = nil
	end
end

function Hub.StopAll()
	Hub.Controls.FarmEnabled:Set(false)
	Hub.ResetPlayer()
	Hub.Controls.ItemsAura:Set(false)
	Hub.Controls.AutoDeliver:Set(false)
	Hub.Controls.AutoReturn:Set(false)
	Hub.Controls.InfStamina:Set(false)
	Hub.Controls.LightItems:Set(false)
	Hub.Controls.Esp:Set(false)
	Hub.Controls.Monsters:Set(false)
	Hub.Controls.FullBright:Set(false)
	Hub.Controls.AntiEffects:Set(false)
end

function Hub.Unload()
	if Hub.Unloading or Hub.Unloaded then
		return
	end
	Hub.Unloading = true
	Hub.SetAutoFarm(false)
	Hub.ResetPlayer()
	for _, connection in ipairs(PlayerSettings.Connections) do connection:Disconnect() end
	table.clear(PlayerSettings.Connections)
	for _, connection in ipairs(PlayerSettings.HumanoidConnections) do connection:Disconnect() end
	table.clear(PlayerSettings.HumanoidConnections)
	if PlayerSettings.CameraConnection then PlayerSettings.CameraConnection:Disconnect() end
	Hub.SetAntiAFK(false)
	Hub.SetFullBright(false)
	Hub.SetAntiEffects(false)
	Hub.SetItemsAura(false)
	Hub.SetAutoDeliver(false)
	Hub.SetAutoReturn(false)
	Hub.SetInfStamina(false)
	Hub.SetLightItems(false)
	Hub.Running = false
	Esp.Enabled = false
	Esp.MonstersEnabled = false
	for _, connection in ipairs(Hub.Connections) do
		connection:Disconnect()
	end
	table.clear(Hub.Connections)
	clearRecords()
	if Hub.Worker then
		pcall(task.cancel, Hub.Worker)
	end
	if Hub.AuraWorker then
		pcall(task.cancel, Hub.AuraWorker)
	end
	if Hub.DeliveryWorker then
		pcall(task.cancel, Hub.DeliveryWorker)
	end
	if Hub.FarmWorker then
		pcall(task.cancel, Hub.FarmWorker)
	end
	if Hub.VisualFolder then
		destroyVisual(Hub.VisualFolder)
	end
	if Hub.LabelGui then
		destroyVisual(Hub.LabelGui)
	end
	if Hub.Window then
		local ok, failure = cleanupCall(function() Hub.Window:Destroy() end)
		if not ok then warn("[TheBackrooms] UI cleanup: " .. tostring(failure)) end
	end
	Hub.Unloading, Hub.Unloaded = false, true
	if Environment.TheBackroomsHub == Hub then
		Environment.TheBackroomsHub = nil
	end
end

local ok, failure = xpcall(function()
	Airflow.Theme.Background = Color3.fromRGB(18, 17, 14)
	Airflow.Theme.Surface = Color3.fromRGB(24, 22, 18)
	Airflow.Theme.Surface2 = Color3.fromRGB(31, 28, 23)
	Airflow.Theme.Surface3 = Color3.fromRGB(50, 45, 37)
	Airflow.Theme.Stroke = Color3.fromRGB(46, 41, 33)
	Airflow.Theme.StrokeHover = Color3.fromRGB(150, 114, 58)
	Airflow.Theme.Accent = Color3.fromRGB(244, 182, 74)
	Airflow.Theme.AccentDark = Color3.fromRGB(40, 28, 9)
	Airflow.Theme.Text = Color3.fromRGB(242, 238, 229)
	Airflow.Theme.Muted = Color3.fromRGB(160, 151, 137)
	local Window = Airflow:CreateWindow({
		Name = "Backrooms",
		Icon = "scan-eye",
		ToggleUIKeybind = Enum.KeyCode.RightControl,
		OpenButton = { Title = "Backrooms", Icon = "eye" },
		Size = UDim2.fromOffset(640, 470),
		MinSize = Vector2.new(280, 220),
		KeepOnScreen = true,
		MaxNotifications = 4,
		Loading = false,
		ConfigurationSaving = { Enabled = false },
	})
	Hub.Window = Window
	if Window._titleLabel then
		Window._titleLabel.Position = UDim2.fromOffset(60, 31)
	end
	Hub.VisualFolder = Instance.new("Folder")
	Hub.VisualFolder.Name = "BackroomsEspVisuals"
	Hub.VisualFolder.Parent = Workspace
	Hub.LabelGui = Instance.new("ScreenGui")
	Hub.LabelGui.Name = "BackroomsEspLabels"
	Hub.LabelGui.ResetOnSpawn = false
	Hub.LabelGui.Parent = Window.Gui.Parent

	Hub.SetupPlayer()
	local Main = Window:CreateTab({ Name = "Main", Icon = "hand" })
	local FarmTab = Window:CreateTab({ Name = "Auto Farm", Icon = "bot" })
	local PlayerTab = Window:CreateTab({ Name = "Player", Icon = "user" })
	local Visuals = Window:CreateTab({ Name = "Visuals", Icon = "eye" })
	local Settings = Window:CreateTab({ Name = "Settings", Icon = "settings" })
	Hub.Controls.ItemsAura = Main:CreateToggle({
		Name = "Items Aura",
		CurrentValue = false,
		Callback = Hub.SetItemsAura,
	})
	Hub.Controls.AutoDeliver = Main:CreateToggle({
		Name = "Auto Deliver",
		Desc = "Delivers when full or enough for Goal. Returns if Goal is incomplete.",
		CurrentValue = false,
		Callback = Hub.SetAutoDeliver,
	})
	Hub.Controls.AutoReturn = Main:CreateToggle({
		Name = "Auto Return",
		Desc = "Returns to the delivery room when Goal is complete.",
		CurrentValue = false,
		Callback = Hub.SetAutoReturn,
	})
	Hub.Controls.TeleportToRoom = Main:CreateButton({
		Name = "Teleport to Room",
		Icon = "door-open",
		Callback = Hub.TeleportToRoom,
	})
	Hub.Controls.InfStamina = Main:CreateToggle({
		Name = "Inf Stamina",
		CurrentValue = false,
		Callback = Hub.SetInfStamina,
	})
	Hub.Controls.LightItems = Main:CreateToggle({
		Name = "Light Items",
		CurrentValue = false,
		Callback = Hub.SetLightItems,
	})
	Hub.Controls.FarmEnabled = FarmTab:CreateToggle({
		Name = "Enabled", CurrentValue = false, Callback = Hub.SetAutoFarm,
	})
	FarmTab:CreateSection("Statistics")
	Hub.FarmLabels = {}
	for _, key in ipairs({ "Status", "Collected", "Delivered", "Value", "Floors", "Skipped", "Escapes", "Goal", "Time" }) do
		Hub.FarmLabels[key] = FarmTab:CreateLabel("")
	end
	Hub.UpdateFarmStats()
	Hub.Controls.Speed = PlayerTab:CreateSlider({
		Name = "Change Speed",
		Range = { 0, 200 }, Increment = 0.1,
		CurrentValue = PlayerSettings.DefaultSpeed,
		Callback = Hub.SetSpeed,
	})
	Hub.Controls.JumpPower = PlayerTab:CreateSlider({
		Name = "Change JumpPower",
		Range = { 0, 250 }, Increment = 1,
		CurrentValue = PlayerSettings.DefaultJumpPower,
		Callback = Hub.SetJumpPower,
	})
	Hub.Controls.FOV = PlayerTab:CreateSlider({
		Name = "Change FOV",
		Range = { 30, 120 }, Increment = 1,
		CurrentValue = PlayerSettings.DefaultFOV,
		Callback = Hub.SetFOV,
	})
	Hub.Controls.EnableJump = PlayerTab:CreateToggle({
		Name = "Enable Jump", CurrentValue = false, Callback = Hub.SetEnableJump,
	})
	Hub.Controls.InfJump = PlayerTab:CreateToggle({
		Name = "Inf Jump", CurrentValue = false, Callback = Hub.SetInfJump,
	})
	Hub.Controls.Noclip = PlayerTab:CreateToggle({
		Name = "Noclip", CurrentValue = false, Callback = Hub.SetNoclip,
	})
	PlayerTab:CreateButton({ Name = "Default Speed", Icon = "rotate-ccw", Callback = Hub.ResetSpeed })
	PlayerTab:CreateButton({ Name = "Default JumpPower", Icon = "rotate-ccw", Callback = Hub.ResetJumpPower })
	PlayerTab:CreateButton({ Name = "Default FOV", Icon = "rotate-ccw", Callback = Hub.ResetFOV })
	PlayerSettings.Ready = true
	Visuals:CreateSection("Items")
	Hub.Controls.Esp = Visuals:CreateToggle({
		Name = "Items ESP",
		CurrentValue = false,
		Callback = Hub.SetEsp,
	})
	Hub.Controls.Labels = Visuals:CreateToggle({
		Name = "Name, Weight and Value",
		CurrentValue = true,
		Callback = function(value)
			Esp.ShowLabels = value
			refreshAll()
		end,
	})
	Visuals:CreateSection("Monsters")
	Hub.Controls.Monsters = Visuals:CreateToggle({
		Name = "Monsters ESP",
		CurrentValue = false,
		Callback = Hub.SetMonsters,
	})
	Hub.Status = Visuals:CreateLabel("Items: 0 | Monsters: 0")
	Hub.Controls.FullBright = Visuals:CreateToggle({
		Name = "FullBright",
		CurrentValue = false,
		Callback = Hub.SetFullBright,
	})
	Hub.Controls.AntiEffects = Visuals:CreateToggle({
		Name = "Anti Effects",
		CurrentValue = false,
		Callback = Hub.SetAntiEffects,
	})
	Settings:CreateSection("Session")
	Hub.Controls.AntiAFK = Settings:CreateToggle({ Name = "Anti AFK", CurrentValue = false, Callback = Hub.SetAntiAFK })
	Settings:CreateButton({ Name = "Stop All", Icon = "square", Callback = function()
		Hub.StopAll()
		Hub.Notify("Stopped", "Every feature is off. Anti AFK stays as it is.", "Success")
	end })
	Hub.Controls.Keybind = Settings:CreateKeybind({
		Name = "Menu Keybind",
		CurrentKeybind = Enum.KeyCode.RightControl,
		OnChanged = function(key)
			if typeof(key) == "EnumItem" then
				Window:SetKeybind(key)
			end
		end,
	})
	Settings:CreateButton({ Name = "Unload", Icon = "power", Callback = Hub.Unload })
	Settings:CreateSection("Credits")
	local creditText
	local creditButton = Settings:CreateButton({ Name = "Credits - loading...", Icon = "copy", Callback = function()
		if creditText then
			Hub.Copy(creditText)
		else
			Hub.Notify("Credits", "The credits text is not available yet.", "Info")
		end
	end })
	Settings:CreateButton({ Name = "UI Library - airflowlib.lol", Icon = "copy", Callback = function()
		Hub.Copy("https://airflowlib.lol")
	end })
	task.spawn(function()
		local fetched, text = pcall(function()
			return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
		end)
		if not Hub.Running then
			return
		end
		if fetched and type(text) == "string" then
			text = text:match("^%s*(.-)%s*$")
			if text ~= "" and #text <= 200 and not text:find("[<>\r\n]") then
				creditText = text
				creditButton:SetText("Credits - " .. text)
				return
			end
		end
		creditButton:SetText("Credits - unavailable")
	end)

	local originalToggle = Window.Toggle
	function Window:Toggle(value)
		if value == nil and UserInputService:GetFocusedTextBox() and UserInputService:GetLastInputType() == Enum.UserInputType.Keyboard then
			return
		end
		return originalToggle(self, value)
	end

	local Sidebar = Window.Body:FindFirstChild("Sidebar")
	local TabLayout = Window.TabList:FindFirstChildOfClass("UIListLayout")
	local TabPadding = Window.TabList:FindFirstChildOfClass("UIPadding")
	local Remembered = {}
	local function remember(object, properties)
		if not object then
			return
		end
		local values = Remembered[object] or {}
		for _, property in ipairs(properties) do
			values[property] = object[property]
		end
		Remembered[object] = values
	end
	remember(Sidebar, { "Size" })
	remember(Window.Content, { "Position", "Size" })
	remember(Window.TabList, { "Position", "Size", "AutomaticCanvasSize", "ScrollingDirection", "CanvasSize" })
	remember(TabLayout, { "FillDirection" })
	remember(TabPadding, { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" })
	if Sidebar then
		for _, child in ipairs(Sidebar:GetChildren()) do
			if child ~= Window.TabList and child ~= Window.Indicator and child:IsA("GuiObject") then
				remember(child, { "Visible" })
			end
		end
	end
	for _, child in ipairs(Window.Body:GetChildren()) do
		if child:IsA("Frame") and child.Size.X.Offset == 1 and child.Position.X.Offset == 170 then
			remember(child, { "Visible" })
		end
	end
	for _, tab in ipairs(Window.Tabs) do
		remember(tab._button, { "Size" })
		remember(tab._label, { "Position", "Size", "TextXAlignment" })
		remember(tab._icon, { "Visible" })
	end
	local originalIndicator = Window._placeIndicator
	function Window:_placeIndicator(tab)
		if Hub.Compact then
			self.Indicator.Visible = false
			return
		end
		return originalIndicator(self, tab)
	end
	function Hub.Layout()
		if not Hub.Running then
			return
		end
		local viewport = Window.Gui.AbsoluteSize
		if viewport.X < 1 or viewport.Y < 1 then
			return
		end
		for object, properties in pairs(Remembered) do
			for property, value in pairs(properties) do
				object[property] = value
			end
		end
		local width = math.clamp(viewport.X - 24, 280, 640)
		local height = math.clamp(viewport.Y - 24, 220, 470)
		Window.Root.Size = UDim2.fromOffset(width, height)
		Hub.Compact = width < 560
		if Hub.Compact and Sidebar and TabLayout then
			Sidebar.Size = UDim2.new(1, 0, 0, 52)
			for object, properties in pairs(Remembered) do
				if properties.Visible ~= nil and not object:IsDescendantOf(Window.TabList) then
					object.Visible = false
				end
			end
			Window.TabList.Position = UDim2.fromOffset(8, 5)
			Window.TabList.Size = UDim2.new(1, -16, 0, 42)
			Window.TabList.ScrollingDirection = Enum.ScrollingDirection.X
			Window.TabList.AutomaticCanvasSize = Enum.AutomaticSize.X
			Window.TabList.CanvasSize = UDim2.new()
			TabLayout.FillDirection = Enum.FillDirection.Horizontal
			if TabPadding then
				TabPadding.PaddingLeft = UDim.new()
				TabPadding.PaddingRight = UDim.new()
				TabPadding.PaddingTop = UDim.new()
				TabPadding.PaddingBottom = UDim.new()
			end
			Window.Content.Position = UDim2.fromOffset(0, 52)
			Window.Content.Size = UDim2.new(1, 0, 1, -52)
			for _, tab in ipairs(Window.Tabs) do
				tab._button.Size = UDim2.fromOffset(math.max(72, #tab.Name * 8 + 26), 40)
				tab._label.Position = UDim2.new()
				tab._label.Size = UDim2.fromScale(1, 1)
				tab._label.TextXAlignment = Enum.TextXAlignment.Center
				if tab._icon then
					tab._icon.Visible = false
				end
			end
			Window.Indicator.Visible = false
		end
		Window:_fitToScreen(true)
		Window:_clampToScreen()
		if Window.CurrentTab and not Hub.Compact then
			Window:_placeIndicator(Window.CurrentTab)
		end
	end
	connect(Window.Gui:GetPropertyChangedSignal("AbsoluteSize"), Hub.Layout)
	connect(Window.Gui.Destroying, Hub.Unload)
	task.defer(Hub.Layout)

	for _, tag in ipairs({ "CollectableItem", "ItemHighlightGameTag", "NpcReadyGameTag" }) do
		connect(CollectionService:GetInstanceAddedSignal(tag), watch)
		connect(CollectionService:GetInstanceRemovedSignal(tag), function(item)
			local record = Hub.Records[item]
			if record then
				queueRefresh(item, record)
			end
		end)
	end
	connect(Workspace.DescendantAdded, function(instance)
		if (Esp.Enabled or Esp.MonstersEnabled) and (instance:IsA("Tool") or instance:IsA("Model") or instance:IsA("BasePart")) then
			watch(instance)
		end
	end)
	Hub.Worker = task.spawn(function()
		while Hub.Running do
			discover()
			refreshAll()
			local count, monsters = 0, 0
			for _, record in pairs(Hub.Records) do
				if record.Highlight then
					if record.IsMonster then
						monsters += 1
					else
						count += 1
					end
				end
			end
			Hub.Status:Set("Items: " .. count .. " | Monsters: " .. monsters)
			task.wait(2)
		end
	end)
	Hub.AuraWorker = task.spawn(function()
		while Hub.Running do
			auraStep()
			task.wait(0.2)
		end
	end)
	Hub.DeliveryWorker = task.spawn(function()
		while Hub.Running do
			autoReturnStep()
			deliveryStep()
			task.wait(0.25)
		end
	end)
	Hub.FarmWorker = task.spawn(function()
		while Hub.Running do
			if Farm.Enabled then
				local ok, failure = xpcall(Hub.AutoFarmStep, debug.traceback)
				if not ok then
					Hub.Controls.FarmEnabled:Set(false)
					Farm.Status = "Paused: an action failed"
					Hub.Notify("Auto Farm", "An action failed. Auto Farm is paused.", "Warning")
					warn("[TheBackrooms] Auto Farm: " .. tostring(failure))
				end
			end
			if os.clock() >= Farm.NextStats then
				Farm.NextStats = os.clock() + 0.5
				Hub.UpdateFarmStats()
			end
			task.wait(0.1)
		end
	end)
	Hub.Controls.Esp:Set(true)
	Hub.Controls.Monsters:Set(true)
	Hub.Controls.AntiAFK:Set(true)
	if RestoreFullBright then
		Hub.Controls.FullBright:Set(true)
	end
	if RestoreItemsAura then
		Hub.Controls.ItemsAura:Set(true)
	end
	if RestoreAutoDeliver then
		Hub.Controls.AutoDeliver:Set(true)
	end
	if RestoreAutoReturn then
		Hub.Controls.AutoReturn:Set(true)
	end
	if RestoreInfStamina then
		Hub.Controls.InfStamina:Set(true)
	end
	if RestoreAntiEffects then
		Hub.Controls.AntiEffects:Set(true)
	end
	if RestoreLightItems then
		Hub.Controls.LightItems:Set(true)
	end
	if RestorePlayer then
		for _, key in ipairs({ "Speed", "JumpPower", "FOV" }) do
			if RestorePlayer[key] ~= nil then Hub.Controls[key]:Set(RestorePlayer[key]) end
		end
		for _, key in ipairs({ "EnableJump", "InfJump", "Noclip" }) do
			if RestorePlayer[key] then Hub.Controls[key]:Set(true) end
		end
	end
	if RestoreFarm and RestoreFarm.Enabled then
		Hub.Controls.FarmEnabled:Set(true)
		Farm.NoclipBackup = RestoreFarm.NoclipBackup
	end
end, debug.traceback)

if not ok then
	Hub.Unload()
	warn("[TheBackrooms] " .. tostring(failure))
end

return Hub

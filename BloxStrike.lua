local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local Environment = getgenv and getgenv() or shared
local DrawingAPI = Drawing
local Library
local State = { Running = true, Entries = {}, Connections = {}, LastError = nil }
local Aim = { Objects = {}, Ready = false, Target = nil, NextSelect = 0, Redirects = 0 }
State.Silent = Aim
local Trigger = { Ready = false, Focused = true, Hooks = {}, NextScan = 0, NextShot = 0, Shots = 0 }
State.Trigger = Trigger
local World = { Entries = {}, NextScan = 0 }
State.World = World
local Skeleton = {}
State.Skeleton = Skeleton
local Grenades = { Ready = false, Entries = {}, Previews = {}, Profiles = {}, Jobs = {}, Captures = 0 }
State.Grenades = Grenades
local WeaponMods = { Ready = false, Hooks = {}, Weapons = setmetatable({}, { __mode = "k" }) }
State.WeaponMods = WeaponMods
local SkinChanger = { Ready = false, Loadout = {}, Catalog = {}, Weapons = {}, Knives = {}, KnifeSet = {}, Records = {}, NextUpdate = 0 }
State.SkinChanger = SkinChanger
local BunnyHop = { Ready = false, Focused = true, Requests = 0 }
State.BunnyHop = BunnyHop
local AntiAim = { Ready = false, Focused = true, Commands = 0, Random = Random.new() }
State.AntiAim = AntiAim
local Visuals = { Ready = false, Parts = {}, Hidden = {}, World = {}, Hooks = {}, SkyPresets = {}, ThirdActive = false }
State.Visuals = Visuals
local Effects = { Ready = false, Records = {}, Roots = {}, FlashActive = false }
State.Effects = Effects
local Animations = { Ready = false, Request = 0, Cache = {}, Results = { ["Take The L"] = "73593666217037" }, Values = { "Take The L" } }
State.Animations = Animations
local Repository = "https://raw.githubusercontent.com/Ali-lov3/Obsidian-UiLibs/refs/heads/main/"
local ConfigPath = "BloxStrike.json"

local function report(message)
    if Library and not Library.Unloaded then
        Library:Notify({ Title = "BloxStrike", Description = message, Time = 5 })
    else
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "BloxStrike ESP", Text = message, Duration = 8,
            })
        end)
        warn("BloxStrike ESP: " .. message)
    end
end

if not DrawingAPI or type(DrawingAPI.new) ~= "function" then
    report("This executor needs Drawing.new with Line, Square and Text support.")
    return
end

local function removeDrawing(object)
    pcall(function() object:Remove() end)
end

local probeObjects = {}
local supported, supportError = pcall(function()
    for _, kind in ipairs({ "Line", "Square", "Text" }) do
        local object = DrawingAPI.new(kind)
        table.insert(probeObjects, object)
        object.Visible = false
        object.Transparency = 1
        object.Color = Color3.new(1, 1, 1)
        if kind == "Text" then
            object.Text = "ESP"
            object.Size = 14
            object.Font = 2
            object.Center = true
            object.Outline = true
            object.OutlineColor = Color3.new()
            object.Position = Vector2.zero
        elseif kind == "Square" then
            object.Filled = true
            object.Position = Vector2.zero
            object.Size = Vector2.one
        else
            object.Thickness = 1
            object.From = Vector2.zero
            object.To = Vector2.one
        end
    end
end)
for _, object in ipairs(probeObjects) do removeDrawing(object) end
if not supported then
    report("Drawing is incomplete: " .. tostring(supportError))
    return
end

local fetched, source = pcall(function() return game:HttpGet(Repository .. "Library.lua") end)
if not fetched then
    report("Could not download Obsidian. Check HTTP access and run again.")
    return
end

source = source:gsub("local Location = Mouse%.X", "local Location = Input.UserInputType == Enum.UserInputType.Touch and Input.Position.X or Mouse.X")
source = source:gsub("math%.clamp%(Mouse%.X, MinX, MaxX%)", "math.clamp(Input.UserInputType == Enum.UserInputType.Touch and Input.Position.X or Mouse.X, MinX, MaxX)")
source = source:gsub("math%.clamp%(Mouse%.Y, MinY, MaxY%)", "math.clamp(Input.UserInputType == Enum.UserInputType.Touch and Input.Position.Y or Mouse.Y, MinY, MaxY)")
source = source:gsub("math%.clamp%(Mouse%.Y, Min, Max%)", "math.clamp(Input.UserInputType == Enum.UserInputType.Touch and Input.Position.Y or Mouse.Y, Min, Max)")
source = source:gsub("_WMFrame%.BackgroundColor3 = Library%.Scheme%.BackgroundColor", "_WMFrame.BackgroundColor3 = Library.WatermarkConfig.BackgroundColor")
source = source:gsub("_WMLabel%.TextColor3 = Library%.Scheme%.FontColor", "_WMLabel.TextColor3 = Library.WatermarkConfig.TextColor")

local chunk, compileError = loadstring(source)
if not chunk then
    report("Could not load Obsidian: " .. tostring(compileError))
    return
end
local previous = Environment.BloxStrikeESP
if previous and previous.Grenades and previous.Grenades.Profiles then
    for name, config in pairs(previous.Grenades.Profiles) do Grenades.Profiles[name] = table.clone(config) end
end
if previous and type(previous.Unload) == "function" then previous:Unload() end
local loaded, result = pcall(chunk)
if not loaded or type(result) ~= "table" then
    report("Obsidian failed to initialize: " .. tostring(result))
    return
end
Library = result
State.Library = Library
Environment.BloxStrikeESP = State

local Settings = {
    Enabled = true,
    ShowEnemies = true,
    TeamCheck = false,
    MaxDistance = 2000,
    VisibilityCheck = false,
    VisibleColor = false,
    Boxes = true,
    Skeleton = false,
    SkeletonTeamColor = true,
    SkeletonColor = Color3.fromRGB(242, 244, 250),
    SkeletonThickness = 1,
    SkeletonOutline = true,
    BoxStyle = "Full",
    BoxFill = false,
    FillOpacity = 12,
    Outlines = true,
    HealthBar = true,
    HealthText = true,
    HealthFormat = "HP / Max",
    Names = true,
    NameMode = "Display name",
    NameLength = 24,
    Distance = true,
    DistanceUnit = "Studs",
    HeldWeapon = true,
    BombCarrier = true,
    DroppedWeapons = true,
    DroppedBomb = true,
    PlantedBomb = true,
    BombTimer = true,
    WorldDistance = true,
    WorldMaxDistance = 2000,
    GrenadeEnabled = true,
    GrenadePreview = true,
    GrenadePreviewMode = "Auto",
    GrenadePrediction = true,
    GrenadeTrails = true,
    GrenadeBounces = true,
    GrenadeEndpoint = true,
    GrenadeNames = true,
    GrenadeHE = true,
    GrenadeFlash = true,
    GrenadeSmoke = true,
    GrenadeMolotov = true,
    GrenadeIncendiary = true,
    GrenadeDecoy = true,
    GrenadeMaxDistance = 1500,
    GrenadeHorizon = 5,
    GrenadeRefresh = 6,
    GrenadeTrailTime = 4,
    GrenadeThickness = 1,
    GrenadeOpacity = 90,
    GrenadeOutline = true,
    GrenadeMarkerSize = 4,
    GrenadePreviewColor = Color3.fromRGB(115, 238, 159),
    GrenadeHEColor = Color3.fromRGB(255, 95, 105),
    GrenadeFlashColor = Color3.fromRGB(245, 239, 180),
    GrenadeSmokeColor = Color3.fromRGB(150, 190, 245),
    GrenadeFireColor = Color3.fromRGB(255, 160, 80),
    GrenadeDecoyColor = Color3.fromRGB(207, 140, 240),
    WorldTextSize = 14,
    WorldOpacity = 100,
    WorldOutlines = true,
    WorldMarkers = true,
    WorldMarkerSize = 5,
    BombWarningTime = 10,
    Tracers = false,
    TracerOrigin = "Bottom",
    TextSize = 14,
    TextFont = "Plex",
    Thickness = 1,
    Opacity = 100,
    DistanceFade = false,
    RefreshRate = UserInputService.TouchEnabled and 30 or 60,
    HideWithMenu = true,
    TouchControls = UserInputService.TouchEnabled,
    UIScale = 100,
    UIWidth = 700,
    UIHeight = 600,
    UIFont = "Gotham",
    UICursor = false,
    UIKeybindMenu = false,
    UINotificationSide = "Right",
    WatermarkVisible = false,
    WatermarkName = false,
    WatermarkFPS = true,
    WatermarkPing = true,
    WatermarkText = "BloxStrike",
    WatermarkTextColor = Color3.new(1, 1, 1),
    WatermarkBgColor = Color3.fromRGB(15, 15, 15),
    WatermarkTransparency = 30,
    SpectatorList = true,
    SpectatorCounter = true,
    SpectatorHideEmpty = false,
    SpectatorNameMode = "Display name",
    SpectatorWidth = 260,
    SpectatorRows = 8,
    SpectatorTextSize = 14,
    EnemyColor = Color3.fromRGB(255, 95, 105),
    TeammateColor = Color3.fromRGB(87, 181, 255),
    InSightColor = Color3.fromRGB(115, 238, 159),
    TextColor = Color3.fromRGB(242, 244, 250),
    OutlineColor = Color3.fromRGB(10, 12, 18),
    HealthLowColor = Color3.fromRGB(255, 78, 86),
    HealthHighColor = Color3.fromRGB(102, 230, 142),
    DroppedWeaponColor = Color3.fromRGB(217, 226, 242),
    BombColor = Color3.fromRGB(255, 195, 80),
    BombUrgentColor = Color3.fromRGB(255, 95, 105),
    SilentEnabled = false,
    SilentTeamCheck = true,
    SilentVisibleOnly = true,
    SilentTargetPart = "Head",
    SilentPriority = "Crosshair",
    SilentMaxDistance = 1200,
    SilentHitChance = 100,
    SilentFOV = 150,
    SilentFOVThickness = 1,
    SilentFOVOpacity = 75,
    SilentShowTarget = true,
    SilentFOVColor = Color3.fromRGB(190, 207, 239),
    SilentTargetColor = Color3.fromRGB(115, 238, 159),
    TriggerEnabled = false,
    TriggerMode = "Crosshair or FOV",
    TriggerDelay = 75,
    TriggerInterval = 0,
    TriggerMaxDistance = 1200,
    TriggerScopedOnly = false,
    WeaponModsEnabled = false,
    WeaponSpreadEnabled = true,
    WeaponSpreadScale = 0,
    WeaponRecoilEnabled = true,
    WeaponRecoilScale = 0,
    WeaponKickEnabled = true,
    WeaponKickScale = 0,
    WeaponWallbang = false,
    WeaponPenetration = 50,
    WeaponWallbangSurfaces = 8,
    WeaponWallbangTargeting = true,
    WeaponAutomatic = false,
    SkinEnabled = false,
    SkinWeapon = "AWP",
    SkinLoadout = "{}",
    SkinPreview = true,
    SkinPreviewHeight = 180,
    AnimationAsset = "73593666217037",
    AnimationQuery = "dance",
    AnimationSpeed = 1,
    AnimationLoop = true,
    AnimationStopMoving = true,
    AnimationStopAction = true,
    BunnyHopEnabled = false,
    BunnyHopMode = UserInputService.TouchEnabled and "Automatic" or "Hold jump",
    BunnyHopMovingOnly = true,
    BunnyHopPauseWithMenu = true,
    BunnyHopDelay = 0,
    AntiAimEnabled = false,
    AntiAimMode = "Static",
    AntiAimBase = "Camera",
    AntiAimYaw = 180,
    AntiAimJitter = 60,
    AntiAimInterval = 150,
    AntiAimSpinSpeed = 360,
    AntiAimSpinDirection = "Clockwise",
    AntiAimRandomRange = 180,
    AntiAimPitch = "Camera",
    AntiAimPitchAngle = 0,
    AntiAimPauseWithMenu = true,
    AntiAimPauseOnFire = true,
    AntiAimPauseScoped = true,
    ThirdPersonEnabled = false,
    ThirdPersonDistance = 8,
    ThirdPersonScoped = true,
    EffectsNoFlash = false,
    EffectsNoSmoke = false,
    SkyEnabled = false,
    SkyPreset = "Oasis",
    SkyRotation = 0,
    SkyStars = 3000,
    SkyCelestial = true,
    SkyBack = "",
    SkyDown = "",
    SkyFront = "",
    SkyLeft = "",
    SkyRight = "",
    SkyUp = "",
    LightEnabled = false,
    LightTime = Lighting.ClockTime,
    LightBrightness = Lighting.Brightness,
    LightExposure = Lighting.ExposureCompensation,
    LightAmbient = Lighting.Ambient,
    LightOutdoor = Lighting.OutdoorAmbient,
    LightShadows = Lighting.GlobalShadows,
    LightNoFog = false,
    LightFogColor = Lighting.FogColor,
    LightFogStart = Lighting.FogStart,
    LightFogEnd = math.min(Lighting.FogEnd, 10000),
    ToneEnabled = false,
    ToneTint = Color3.new(1, 1, 1),
    ToneSaturation = 0,
    ToneContrast = 0,
    BloomEnabled = false,
    BloomIntensity = 1,
    BloomSize = 24,
    BloomThreshold = 1,
    ViewArmsEnabled = false,
    ViewArmsColor = Color3.fromRGB(116, 167, 255),
    ViewArmsMaterial = "Neon",
    ViewArmsRainbow = false,
    ViewWeaponEnabled = false,
    ViewWeaponColor = Color3.fromRGB(255, 110, 170),
    ViewWeaponMaterial = "Neon",
    ViewWeaponRainbow = false,
    ViewSolidColor = true,
    ViewRainbowSpeed = 0.2,
    ViewPositionEnabled = false,
    ViewPositionScoped = true,
    ViewX = 0,
    ViewY = 0,
    ViewZ = 0,
    ViewPitch = 0,
    ViewYaw = 0,
    ViewRoll = 0,
}
State.Settings = Settings
local Defaults = table.clone(Settings)
local BodyNames = {
    "Head", "UpperTorso", "LowerTorso", "Torso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "Left Arm", "Right Arm", "Left Leg", "Right Leg",
}
local SkeletonEdges = {
    { "Head", "Neck" }, { "Neck", "Waist" },
    { "Neck", "LeftShoulder" }, { "LeftShoulder", "LeftElbow" }, { "LeftElbow", "LeftWrist" }, { "LeftWrist", "LeftHand" },
    { "Neck", "RightShoulder" }, { "RightShoulder", "RightElbow" }, { "RightElbow", "RightWrist" }, { "RightWrist", "RightHand" },
    { "Waist", "LeftHip" }, { "LeftHip", "LeftKnee" }, { "LeftKnee", "LeftAnkle" }, { "LeftAnkle", "LeftFoot" },
    { "Waist", "RightHip" }, { "RightHip", "RightKnee" }, { "RightKnee", "RightAnkle" }, { "RightAnkle", "RightFoot" },
}
local Fonts = DrawingAPI.Fonts or { UI = 0, System = 1, Plex = 2, Monospace = 3 }
local BoxEdges = { {1,2}, {1,3}, {1,5}, {2,4}, {2,6}, {3,4}, {3,7}, {4,8}, {5,6}, {5,7}, {6,8}, {7,8} }
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(State.Connections, connection)
    return connection
end

local function installHook(hooks, module, key, factory)
    local original = module[key]
    assert(type(original) == "function", "Missing game function: " .. key)
    local wrapper = factory(original)
    table.insert(hooks, { Module = module, Key = key, Original = original, Wrapper = wrapper })
    module[key] = wrapper
end

local function restoreHooks(hooks)
    for index = #hooks, 1, -1 do
        local hook = hooks[index]
        if hook.Module[hook.Key] == hook.Wrapper then hook.Module[hook.Key] = hook.Original end
    end
    table.clear(hooks)
end

local function hide(entry)
    if entry.Shown then
        for _, object in ipairs(entry.Objects) do object.Visible = false end
        entry.Shown = false
    end
end

local function hideAll()
    for _, entry in pairs(State.Entries) do hide(entry) end
    for _, entry in pairs(World.Entries) do hide(entry) end
end

local function removeEntry(player)
    local entry = State.Entries[player]
    if not entry then return end
    for _, object in ipairs(entry.Objects) do removeDrawing(object) end
    State.Entries[player] = nil
end

local function removeWorldEntry(model)
    local entry = World.Entries[model]
    if not entry then return end
    for _, object in ipairs(entry.Objects) do removeDrawing(object) end
    World.Entries[model] = nil
end

local function cleanup()
    if not State.Running then return end
    State.Running = false
    if Trigger.RestoreAll then Trigger:RestoreAll() end
    if Animations.RestoreAll then Animations:RestoreAll() end
    if Grenades.RestoreAll then Grenades:RestoreAll() end
    if AntiAim.RestoreAll then AntiAim:RestoreAll() end
    if Effects.RestoreAll then Effects:RestoreAll() end
    if Visuals.RestoreAll then Visuals:RestoreAll() end
    if BunnyHop.Module and BunnyHop.Module.SampleInput == BunnyHop.Wrapper then
        BunnyHop.Module.SampleInput = BunnyHop.Original
    end
    BunnyHop.Ready = false
    if BunnyHop.Reset then BunnyHop:Reset() end
    restoreHooks(WeaponMods.Hooks)
    if WeaponMods.RestoreRecoil then WeaponMods.RestoreRecoil() end
    if WeaponMods.RestoreWeapons then WeaponMods.RestoreWeapons() end
    if SkinChanger.RestoreAll then SkinChanger:RestoreAll() end
    WeaponMods.Ready = false
    if Aim.Module and Aim.Module._performRaycast == Aim.Wrapper then
        pcall(function() Aim.Module._performRaycast = Aim.Original end)
    end
    Aim.Ready = false
    Aim.Target = nil
    for _, object in ipairs(Aim.Objects) do removeDrawing(object) end
    table.clear(Aim.Objects)
    for _, connection in ipairs(State.Connections) do connection:Disconnect() end
    table.clear(State.Connections)
    for player in pairs(State.Entries) do removeEntry(player) end
    for model in pairs(World.Entries) do removeWorldEntry(model) end
    if State.Watermark and State.Watermark.Frame then
        local gui = State.Watermark.Frame:FindFirstAncestorOfClass("ScreenGui")
        if gui then gui:Destroy() end
    end
    if Environment.BloxStrikeESP == State then Environment.BloxStrikeESP = nil end
end

function State:Unload()
    if not self.Running then return end
    if Library and not Library.Unloaded then
        pcall(function() Library:Toggle(false) end)
        local ok = pcall(function() Library:Unload() end)
        if not ok and Library.ScreenGui then Library.ScreenGui:Destroy() end
    end
    cleanup()
end
Library:OnUnload(cleanup)

local function newDrawing(entry, kind, properties)
    local object = DrawingAPI.new(kind)
    table.insert(entry.Objects, object)
    object.Visible = false
    object.Transparency = 1
    for key, value in pairs(properties or {}) do object[key] = value end
    return object
end

local function createEntry(player)
    local entry = { Player = player, Objects = {}, Lines = {}, Borders = {}, Parts = {}, NextRay = 0, InSight = false }
    State.Entries[player] = entry
    entry.Fill = newDrawing(entry, "Square", { Filled = true })
    for i = 1, 8 do
        entry.Borders[i] = newDrawing(entry, "Line")
        entry.Lines[i] = newDrawing(entry, "Line")
    end
    entry.HealthBack = newDrawing(entry, "Square", { Filled = true })
    entry.Health = newDrawing(entry, "Square", { Filled = true })
    entry.TracerBorder = newDrawing(entry, "Line")
    entry.Tracer = newDrawing(entry, "Line")
    entry.Name = newDrawing(entry, "Text", { Center = true })
    entry.Username = newDrawing(entry, "Text", { Center = true })
    entry.Info = newDrawing(entry, "Text", { Center = true })
    entry.Weapon = newDrawing(entry, "Text", { Center = true })
    entry.Bomb = newDrawing(entry, "Text", { Center = true })
    return entry
end

local function decodeObject(value)
    if type(value) ~= "string" or value == "" then return nil end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, value)
    if ok and type(data) == "table" then return data end
    return nil
end

local function equipmentOf(entry)
    local raw = entry.Player:GetAttribute("CurrentEquipped")
    if raw ~= entry.EquippedRaw then
        entry.EquippedRaw = raw
        local data = decodeObject(raw)
        entry.WeaponName = data and type(data.Name) == "string" and data.Name ~= "" and data.Name or nil
    end
    local slot = entry.Player:GetAttribute("Slot5")
    if slot ~= entry.BombSlotRaw then
        entry.BombSlotRaw = slot
        local data = decodeObject(slot)
        entry.HasBomb = data ~= nil and data.Weapon == "C4"
    end
    return entry.WeaponName, entry.HasBomb or entry.WeaponName == "C4"
end

local function addWorldEntry(model)
    if World.Entries[model] or not model:IsDescendantOf(workspace)
        or not (model:IsA("Model") or model:IsA("BasePart")) then return end
    local entry = { Model = model, Objects = {} }
    World.Entries[model] = entry
    local ok, err = pcall(function()
        entry.Label = newDrawing(entry, "Text", { Center = true })
        entry.Distance = newDrawing(entry, "Text", { Center = true })
        entry.Marker = newDrawing(entry, "Square", { Filled = false, Thickness = 1 })
    end)
    if not ok then removeWorldEntry(model) World.LastError = tostring(err) end
end

local function syncWorld(now)
    if now < World.NextScan then return end
    World.NextScan = now + 0.5
    local found = {}
    for _, tag in ipairs({ "WeaponDropped", "Bomb" }) do
        for _, model in ipairs(CollectionService:GetTagged(tag)) do
            if model:IsDescendantOf(workspace) then
                found[model] = true
                addWorldEntry(model)
            end
        end
    end
    for model in pairs(World.Entries) do if not found[model] then removeWorldEntry(model) end end
end

local function bombStatus(entry, serverNow)
    local model = entry.Model
    if model:GetAttribute("Exploded") then return "Exploded" end
    if model:GetAttribute("Defused") then return "Defused" end
    if model:GetAttribute("Exploding") then return "Exploding", 0 end
    local raw = model:GetAttribute("BombPlanted")
    if raw ~= entry.BombRaw then
        entry.BombRaw = raw
        entry.ExplodeAt = nil
        local data = decodeObject(raw)
        if data and type(data.Time) == "number" and data.Time == data.Time and math.abs(data.Time) < math.huge then
            local duration = type(data.TimeUntilExplode) == "number" and data.TimeUntilExplode or 40
            if duration == duration and math.abs(duration) < math.huge then
                entry.ExplodeAt = data.Time + math.max(duration, 0.1)
            end
        end
    end
    return "Planted", entry.ExplodeAt and math.max(0, entry.ExplodeAt - serverNow) or nil
end
World.BombStatus = bombStatus

local function createSpectatorList()
    local frame, container = Library:AddDraggableMenu("Server spectators")
    frame.Name = "BloxStrikeSpectators"
    frame.AutomaticSize = Enum.AutomaticSize.None
    container:FindFirstChildOfClass("UIListLayout").SortOrder = Enum.SortOrder.LayoutOrder
    local title = frame:FindFirstChildWhichIsA("TextLabel")
    title.TextTruncate = Enum.TextTruncate.AtEnd
    local counter = Instance.new("TextLabel")
    counter.Name = "WatchingYou"
    counter.BackgroundTransparency = 1
    counter.TextXAlignment = Enum.TextXAlignment.Left
    counter.TextTruncate = Enum.TextTruncate.AtEnd
    counter.TextSize = 14
    counter.Size = UDim2.new(1, 0, 0, 24)
    counter.LayoutOrder = 1
    counter.ZIndex = 12
    counter.Parent = container
    local list = Instance.new("ScrollingFrame")
    list.Name = "SpectatorNames"
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.CanvasSize = UDim2.new()
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.ScrollingDirection = Enum.ScrollingDirection.Y
    list.ScrollBarThickness = 3
    list.LayoutOrder = 2
    list.ZIndex = 12
    list.Parent = container
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = list
    local spectators = { Frame = frame, List = list, Counter = counter, Items = {}, Names = {}, NextUpdate = 0 }
    State.Spectators = spectators
    local function makeRow(name)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.BackgroundTransparency = 1
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.Size = UDim2.new(1, -8, 0, 24)
        label.ZIndex = 13
        label.Parent = list
        return label
    end
    local empty = makeRow("Empty")
    empty.Text = "No active spectators"
    local clamping = false
    local function clampPosition()
        if clamping or not State.Running then return end
        clamping = true
        local available = State.AvailableSize or Library.ScreenGui.AbsoluteSize
        local x = math.clamp(frame.Position.X.Offset, 12, math.max(12, available.X - frame.AbsoluteSize.X - 12))
        local y = math.clamp(frame.Position.Y.Offset, 12, math.max(12, available.Y - frame.AbsoluteSize.Y - 12))
        frame.Position = UDim2.fromOffset(x, y)
        clamping = false
    end
    function State:FitSpectators(reset)
        local available = self.AvailableSize or Library.ScreenGui.AbsoluteSize
        local dpi = Library.DPIScale or 1
        local width = math.max(140, math.min(Settings.SpectatorWidth, (available.X - 24) / dpi))
        local header = Settings.TouchControls and 44 or 34
        local counterHeight = Settings.SpectatorCounter and 31 or 0
        local listHeight = math.max(20, math.min(spectators.ContentHeight or 24, (available.Y - 24) / dpi - header - counterHeight - 16))
        title.Size = UDim2.new(1, 0, 0, header)
        for _, child in ipairs(frame:GetChildren()) do
            if child:IsA("Frame") and child ~= container and child.Size.Y.Offset == 1 then
                child.Position = UDim2.fromOffset(0, header)
            end
        end
        container.Position = UDim2.fromOffset(0, header + 1)
        container.Size = UDim2.new(1, 0, 1, -header - 1)
        list.Size = UDim2.new(1, 0, 0, listHeight)
        list.ScrollBarThickness = Settings.TouchControls and 5 or 3
        frame.Size = UDim2.fromOffset(width, header + counterHeight + listHeight + 15)
        if reset or not spectators.Positioned then
            spectators.Positioned = true
            frame.Position = UDim2.fromOffset(available.X - width * dpi - 18, 96)
        end
        clampPosition()
    end
    function State:UpdateSpectators()
        if not self.Running then return end
        local names = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player:GetAttribute("IsSpectating") == true then
                table.insert(names, player)
            end
        end
        table.sort(names, function(a, b) return a.Name:lower() < b.Name:lower() end)
        local watching = LocalPlayer:GetAttribute("Spectators")
        watching = type(watching) == "number" and watching == watching and watching >= 0 and math.floor(watching) or nil
        spectators.Names, spectators.WatchingYou = names, watching
        title.Text = "Server spectators: " .. #names
        counter.Text = "Watching you: " .. (watching and tostring(watching) or "?")
        counter.Visible = Settings.SpectatorCounter
        counter.TextColor3 = Library.Scheme.FontColor
        counter.Font = Enum.Font[Settings.UIFont]
        list.ScrollBarImageColor3 = Library.Scheme.AccentColor
        local found, height = {}, 0
        for index, player in ipairs(names) do
            found[player] = true
            local row = spectators.Items[player]
            if not row then row = makeRow(player.Name) spectators.Items[player] = row end
            local both = Settings.SpectatorNameMode == "Both" and player.DisplayName ~= player.Name
            row.Text = Settings.SpectatorNameMode == "Username" and player.Name or player.DisplayName
            if both then row.Text = row.Text .. "\n@" .. player.Name end
            local rowHeight = (Settings.SpectatorTextSize + 2) * (both and 2 or 1) + 6
            row.Size = UDim2.new(1, -8, 0, rowHeight)
            row.TextSize = Settings.SpectatorTextSize
            row.Font = Enum.Font[Settings.UIFont]
            row.TextColor3 = Library.Scheme.FontColor
            row.LayoutOrder = index
            if index <= Settings.SpectatorRows then height = height + rowHeight end
        end
        for player, row in pairs(spectators.Items) do
            if not found[player] then row:Destroy() spectators.Items[player] = nil end
        end
        empty.Visible = #names == 0
        empty.TextSize, empty.Font = Settings.SpectatorTextSize, Enum.Font[Settings.UIFont]
        empty.TextColor3 = Library.Scheme.FontColor
        empty.Size = UDim2.new(1, -8, 0, Settings.SpectatorTextSize + 8)
        spectators.ContentHeight = #names == 0 and Settings.SpectatorTextSize + 8 or height
        frame.Visible = Settings.SpectatorList and not (Settings.SpectatorHideEmpty and #names == 0 and (watching or 0) == 0)
        self:FitSpectators()
    end
    connect(frame:GetPropertyChangedSignal("Position"), clampPosition)
    connect(frame:GetPropertyChangedSignal("AbsoluteSize"), clampPosition)
    connect(RunService.Heartbeat, function()
        local now = os.clock()
        if now < spectators.NextUpdate then return end
        spectators.NextUpdate = now + 0.2
        local ok, err = pcall(function() State:UpdateSpectators() end)
        if not ok and spectators.LastError ~= tostring(err) then
            spectators.LastError = tostring(err)
            frame.Visible = false
            report("Spectator list: " .. spectators.LastError)
        end
    end)
    State:UpdateSpectators()
end

local function teamOf(player)
    local name = player:GetAttribute("Team")
    if name == "Counter-Terrorists" or name == "Terrorists" then return name end
    return nil
end

local function teamAllowed(player)
    local myTeam, theirTeam = teamOf(LocalPlayer), teamOf(player)
    if not theirTeam then return false, false end
    local teammate = myTeam == theirTeam
    if teammate then return not Settings.TeamCheck, true end
    return Settings.ShowEnemies, false
end

local function healthOf(character)
    local health, maximum = character:GetAttribute("Health"), character:GetAttribute("MaxHealth")
    if type(health) ~= "number" then return nil end
    if health ~= health or health == math.huge then return nil end
    if type(maximum) ~= "number" or maximum ~= maximum or maximum <= 0 then maximum = 100 end
    return health, maximum
end

local function matchCharacter(player)
    local character = player.Character
    local characters = workspace:FindFirstChild("Characters")
    if not teamOf(player) or not character or not characters or not character:IsDescendantOf(characters)
        or character:GetAttribute("CharacterType") ~= "PlayerCustomCharacter"
        or player:GetAttribute("IsSpectating") == true or player:GetAttribute("Dead") == true
        or character:GetAttribute("Dead") == true then return nil end
    local health, maximum = healthOf(character)
    if not health or health <= 0 then return nil end
    return character, health, maximum
end

local function hideAim()
    for _, object in ipairs(Aim.Objects) do object.Visible = false end
end

local function installAnimations()
    function Animations:SetStatus(message)
        self.Status = message
        if self.StatusLabel and not Library.Unloaded then self.StatusLabel:SetText(message) end
    end
    function Animations:ClearTrack()
        self.Request += 1
        self.Loading = false
        if self.Ended then self.Ended:Disconnect() self.Ended = nil end
        if self.Track then pcall(function() self.Track:Stop(0) self.Track:Destroy() end) self.Track = nil end
        if self.Asset then self.Asset:Destroy() self.Asset = nil end
        self.Character, self.Weapon, self.PlayingName = nil, nil, nil
    end
    function Animations:Stop(message)
        self.Playback = nil
        self:ClearTrack()
        self:SetStatus(message or "Stopped")
    end
    function Animations:PauseForRespawn()
        if not self.Playback or Settings.AnimationStopMoving or Settings.AnimationStopAction then self:Stop() return end
        if self.Track and not self.Loading then self.Playback.Position = self.Track.TimePosition end
        self:ClearTrack()
        self:SetStatus("Waiting for respawn...")
    end
    function Animations:RestoreAll()
        self.Ready = false
        self:Stop()
        self.Pages = nil
    end
    function Animations:AssetId(value)
        if type(value) == "number" then
            if value ~= value or value <= 0 or value > 9007199254740991 or value % 1 ~= 0 then return nil end
            return string.format("%.0f", value)
        end
        value = tostring(value):match("^%s*(.-)%s*$")
        local id = value:match("^(%d+)$") or value:match("^rbxassetid://(%d+)$")
            or value:match("^https?://[%w%.]*roblox%.com/catalog/(%d+)")
            or value:match("^https?://[%w%.]*roblox%.com/library/(%d+)")
            or value:match("^https?://[%w%.]*roblox%.com/asset/%?id=(%d+)")
        local number = tonumber(id)
        if not number or number <= 0 or number > 9007199254740991 then return nil end
        return string.format("%.0f", number)
    end
    function Animations:Resolve(value)
        local id = assert(self:AssetId(value), "Enter a Roblox animation ID or catalog link.")
        if self.Cache[id] then return self.Cache[id] end
        local info = game:GetService("MarketplaceService"):GetProductInfo(tonumber(id), Enum.InfoType.Asset)
        local animationId
        if info.AssetTypeId == Enum.AssetType.Animation.Value then
            animationId = id
        elseif info.AssetTypeId == Enum.AssetType.EmoteAnimation.Value then
            local objects = game:GetObjects("rbxassetid://" .. id)
            for _, object in ipairs(objects) do
                local animation = object:IsA("Animation") and object or object:FindFirstChildWhichIsA("Animation", true)
                if animation then animationId = self:AssetId(animation.AnimationId) or animationId end
                object:Destroy()
            end
            assert(animationId, "This catalog emote does not contain an accessible animation.")
        else
            error("This item is not an animation or emote.", 0)
        end
        local result = { Id = animationId, Name = tostring(info.Name):gsub("%c", " ") }
        self.Cache[id] = result
        return result
    end
    function Animations:Refresh()
        if self.Playback and not self.Character and (Settings.AnimationStopMoving or Settings.AnimationStopAction) then self:Stop() return end
        if self.Track and not self.Loading then
            self.Track.Looped = Settings.AnimationLoop
            self.Track:AdjustSpeed(Settings.AnimationSpeed)
        end
    end
    function Animations:Play(resume)
        if not State.Running or not self.Ready then return end
        local playback = resume and self.Playback or { Value = Settings.AnimationAsset, Position = 0 }
        if not playback then return end
        self:ClearTrack()
        self.Playback = playback
        local character = matchCharacter(LocalPlayer)
        local controller = character and character:FindFirstChildOfClass("AnimationController")
        local animator = controller and controller:FindFirstChildOfClass("Animator")
        if not animator then
            if Settings.AnimationStopMoving or Settings.AnimationStopAction then self:Stop("Join the match to play an animation.")
            else self:SetStatus("Waiting for respawn...") end
            return
        end
        local request, value = self.Request, playback.Value
        self.Character, self.Loading = character, true
        self:SetStatus("Loading animation...")
        local function current()
            return State.Running and self.Ready and self.Request == request and matchCharacter(LocalPlayer) == character
        end
        task.delay(15, function()
            if current() and self.Loading then self:Stop("Animation loading timed out. Try again.") end
        end)
        task.spawn(function()
            local ok, failure = pcall(function()
                local info = self:Resolve(value)
                if not current() then return end
                local asset = Instance.new("Animation")
                asset.Name, asset.AnimationId = "BloxStrikeDance", "rbxassetid://" .. info.Id
                self.Asset = asset
                local track = animator:LoadAnimation(asset)
                self.Track = track
                local deadline = os.clock() + 8
                while current() and track.Length <= 0 and os.clock() < deadline do task.wait(0.05) end
                if not current() then return end
                assert(track.Length > 0, "Roblox could not load this animation in the current game.")
                track.Priority = Enum.AnimationPriority.Action4
                self.Loading, self.PlayingName = false, info.Name
                self.Weapon = SkinChanger.GetWeapon and SkinChanger.GetWeapon()
                self:Refresh()
                self.Ended = track.Ended:Connect(function()
                    if self.Request == request then self:Stop("Finished") end
                end)
                track:Play(0.15, 1, Settings.AnimationSpeed)
                if playback.Position > 0 then
                    track.TimePosition = Settings.AnimationLoop and playback.Position % track.Length or math.min(playback.Position, track.Length)
                end
                self.LastError = nil
                self:SetStatus("Playing: " .. info.Name)
            end)
            if not ok and self.Request == request and State.Running then
                self.LastError = tostring(failure)
                self:Stop("Could not play this animation.")
                report("Animation: " .. self.LastError)
            end
        end)
    end
    function Animations:Search(more)
        if self.Searching or not State.Running then return end
        if more and (not self.Pages or self.Pages.IsFinished) then return end
        self.Searching = true
        local query = Settings.AnimationQuery
        self.CatalogLabel:SetText("Searching catalog...")
        task.spawn(function()
            local ok, failure = pcall(function()
                local pages = self.Pages
                if more then
                    pages:AdvanceToNextPageAsync()
                else
                    local params = CatalogSearchParams.new()
                    params.AssetTypes = { Enum.AvatarAssetType.EmoteAnimation }
                    params.SearchKeyword, params.Limit = query, 30
                    pages = game:GetService("AvatarEditorService"):SearchCatalogAsync(params)
                end
                if not State.Running then return end
                local results, values = more and self.Results or {}, more and self.Values or {}
                local seen = {}
                for _, id in pairs(results) do seen[id] = true end
                for _, item in ipairs(pages:GetCurrentPage()) do
                    local id = self:AssetId(item.Id)
                    if id and item.AssetType == "EmoteAnimation" and not seen[id] then
                        local name = tostring(item.Name):gsub("%c", " ")
                        if results[name] then name ..= " (" .. id .. ")" end
                        results[name], seen[id] = id, true
                        table.insert(values, name)
                    end
                end
                self.Pages, self.Results, self.Values = pages, results, values
                self.ResultControl:SetValues(values)
                if not more then self.ResultControl:SetValue(values[1]) end
                self.MoreButton:SetDisabled(pages.IsFinished)
                self.CatalogLabel:SetText(#values == 0 and "No emotes found." or tostring(#values) .. " emotes loaded")
                if State.FitWindow then State:FitWindow() end
            end)
            self.Searching = false
            if not ok and State.Running then
                self.CatalogLabel:SetText("Catalog unavailable. Try again.")
                self.SearchError = tostring(failure)
            end
        end)
    end
    local ok, failure = pcall(function()
        local storage = game:GetService("ReplicatedStorage")
        local getVelocity = require(storage.Components.Common.GetCharacterVelocity)
        local characterController = require(storage.Controllers.CharacterController)
        local nextUpdate = 0
        connect(RunService.Heartbeat, function()
            if not Animations.Playback or os.clock() < nextUpdate then return end
            nextUpdate = os.clock() + 0.05
            local success, err = pcall(function()
                local character = matchCharacter(LocalPlayer)
                if not Animations.Character then
                    if Settings.AnimationStopMoving or Settings.AnimationStopAction then Animations:Stop() return end
                    local controller = character and character:FindFirstChildOfClass("AnimationController")
                    if controller and controller:FindFirstChildOfClass("Animator") then Animations:Play(true) end
                    return
                end
                if not character or character ~= Animations.Character then Animations:PauseForRespawn() return end
                local native = characterController.getCurrentCharacter()
                if Settings.AnimationStopMoving and (getVelocity(character).Magnitude > 0.75 or (native and native.JumpInputDown)) then
                    Animations:Stop("Stopped on movement")
                    return
                end
                if Settings.AnimationStopAction and not Animations.Loading then
                    local weapon = SkinChanger.GetWeapon and SkinChanger.GetWeapon()
                    if weapon ~= Animations.Weapon or (weapon and (weapon.IsFireHeld or weapon.IsShooting or weapon.IsReloading or weapon.IsAiming))
                        or (native and native.IsPlantingBomb) or LocalPlayer:GetAttribute("IsDefusingBomb") == true
                        or LocalPlayer:GetAttribute("IsLocallyDefusingBomb") == true then Animations:Stop("Stopped on action") end
                end
            end)
            if not success then Animations.LastError = tostring(err) Animations:Stop("Animation stopped") end
        end)
        connect(LocalPlayer.CharacterRemoving, function() Animations:PauseForRespawn() end)
        Animations.Ready = true
    end)
    if not ok then Animations.LastError = tostring(failure) end
end

local function installBunnyHop()
    local ok, failure = pcall(function()
        local storage = game:GetService("ReplicatedStorage")
        local module = require(storage.Classes.Character)
        local buttons = require(storage.MovementV2.Buttons)
        local guiService = game:GetService("GuiService")
        assert(type(module.SampleInput) == "function" and not table.isfrozen(module), "Movement input is unavailable")
        BunnyHop.Module, BunnyHop.Original = module, module.SampleInput
        function BunnyHop:Reset()
            self.Character, self.GroundSince, self.LastJumpDown = nil, nil, false
        end
        function BunnyHop:Allowed(character)
            local model = matchCharacter(LocalPlayer)
            return State.Running and self.Ready and Settings.BunnyHopEnabled and self.Focused
                and model ~= nil and not character.IsDestroyed and character.Character == model
                and not guiService.MenuIsOpen and not UserInputService:GetFocusedTextBox()
                and LocalPlayer:GetAttribute("IsPlayerChatting") ~= true
                and not (Settings.BunnyHopPauseWithMenu and Library.Toggled)
        end
        function BunnyHop:Process(character, context, input)
            if self.Character ~= character then
                self:Reset()
                self.Character = character
                self.LastJumpDown = buttons.has((context.State and context.State.PreviousButtons) or 0, buttons.Jump)
            end
            local requested = Settings.BunnyHopMode == "Automatic" or character.JumpInputDown
                or buttons.has(input.Buttons, buttons.Jump)
            if not requested or (Settings.BunnyHopMovingOnly and input.Move.Magnitude < 0.05) then
                self.GroundSince = nil
                self.LastJumpDown = buttons.has(input.Buttons, buttons.Jump)
                return input
            end
            local movement = context.State
            if not movement then self:Reset() return input end
            local now = context.ScheduledServerTime or os.clock()
            if movement.OnGround then self.GroundSince = self.GroundSince or now
            else self.GroundSince = nil end
            local jump = movement.OnGround == true and not self.LastJumpDown
                and now - self.GroundSince >= Settings.BunnyHopDelay / 1000
            local modified = table.clone(input)
            modified.Buttons = buttons.with(input.Buttons, buttons.Jump, jump)
            self.LastJumpDown = jump
            if jump then self.Requests += 1 end
            return modified
        end
        BunnyHop.Wrapper = function(character, context, ...)
            local input = BunnyHop.Original(character, context, ...)
            if not input then return input end
            local success, modified = pcall(function()
                if not BunnyHop:Allowed(character) then BunnyHop:Reset() return input end
                return BunnyHop:Process(character, context, input)
            end)
            if success then return modified end
            BunnyHop.LastError = tostring(modified)
            Settings.BunnyHopEnabled = false
            BunnyHop:Reset()
            task.defer(function()
                if not State.Running then return end
                local control = Library.Toggles.BunnyHopEnabled
                if control then control:SetValue(false) end
                report("Bunny hop paused: " .. BunnyHop.LastError)
            end)
            return input
        end
        module.SampleInput = BunnyHop.Wrapper
        BunnyHop.Ready = true
        connect(UserInputService.WindowFocusReleased, function() BunnyHop.Focused = false BunnyHop:Reset() end)
        connect(UserInputService.WindowFocused, function() BunnyHop.Focused = true end)
        connect(LocalPlayer.CharacterRemoving, function() BunnyHop:Reset() end)
    end)
    if not ok then BunnyHop.LastError = tostring(failure) end
end

local function installAntiAim()
    function AntiAim:Reset()
        self.Character, self.Started, self.LastStep, self.RandomYaw = nil, nil, nil, nil
        self.Active, self.FireUntil = false, 0
    end
    function AntiAim:RestoreAll()
        self.Ready = false
        if self.Module and self.Module.SampleInput == self.Wrapper then self.Module.SampleInput = self.Original end
        self:Reset()
    end
    local ok, failure = pcall(function()
        local module = require(game:GetService("ReplicatedStorage").Classes.Character)
        local guiService = game:GetService("GuiService")
        assert(type(module.SampleInput) == "function" and not table.isfrozen(module), "Character rotation is unavailable")
        AntiAim.Module, AntiAim.Original = module, module.SampleInput
        function AntiAim:Allowed(character, context)
            local model = matchCharacter(LocalPlayer)
            if not State.Running or not self.Ready or not Settings.AntiAimEnabled or not self.Focused
                or not model or character.IsDestroyed or character.Character ~= model
                or guiService.MenuIsOpen or UserInputService:GetFocusedTextBox()
                or LocalPlayer:GetAttribute("IsPlayerChatting") == true
                or (Settings.AntiAimPauseWithMenu and Library.Toggled) then return false end
            local movement = context.State
            if character.IsClimbing or (movement and movement.MovementMode == "Ladder")
                or character.IsPlantingBomb or LocalPlayer:GetAttribute("IsDefusingBomb") == true
                or LocalPlayer:GetAttribute("IsLocallyDefusingBomb") == true
                or LocalPlayer:GetAttribute("IsRescuingHostage") == true then return false end
            local weapon = SkinChanger.GetWeapon and SkinChanger.GetWeapon()
            local view = weapon and weapon.Viewmodel
            if Settings.AntiAimPauseScoped and view and view.Bobble and view.Bobble.IsAiming then return false end
            if Settings.AntiAimPauseOnFire then
                local now = os.clock()
                if weapon and (weapon.IsFireHeld or weapon.IsShooting or weapon.IsBurstShooting) then self.FireUntil = now + 0.2 end
                if now < (self.FireUntil or 0) then return false end
            end
            return true
        end
        function AntiAim:Process(character, context, input)
            local now = context.ScheduledServerTime or os.clock()
            if self.Character ~= character or not self.Started or now < self.Started then
                self:Reset()
                self.Character, self.Started = character, now
            end
            local elapsed = now - self.Started
            local step = math.floor(elapsed / math.max(Settings.AntiAimInterval / 1000, 0.02))
            local side = step % 2 == 0 and -1 or 1
            local yaw = (Settings.AntiAimBase == "Camera" and input.LookYaw or 0) + math.rad(Settings.AntiAimYaw)
            if Settings.AntiAimMode == "Jitter" then
                yaw += math.rad(Settings.AntiAimJitter) * side
            elseif Settings.AntiAimMode == "Spin" then
                local direction = Settings.AntiAimSpinDirection == "Clockwise" and -1 or 1
                yaw += math.rad(elapsed * Settings.AntiAimSpinSpeed * direction % 360)
            elseif Settings.AntiAimMode == "Random" then
                if self.LastStep ~= step or not self.RandomYaw then
                    self.RandomYaw = math.rad(self.Random:NextNumber(-Settings.AntiAimRandomRange, Settings.AntiAimRandomRange))
                end
                yaw += self.RandomYaw
            end
            self.LastStep = step
            yaw = (yaw + math.pi) % (math.pi * 2) - math.pi
            local pitch = input.VerticalLook
            if Settings.AntiAimPitch == "Up" then pitch = 1
            elseif Settings.AntiAimPitch == "Down" then pitch = -1
            elseif Settings.AntiAimPitch == "Level" then pitch = 0
            elseif Settings.AntiAimPitch == "Custom" then pitch = math.sin(math.rad(Settings.AntiAimPitchAngle))
            elseif Settings.AntiAimPitch == "Jitter" then pitch = side end
            local move = input.Move
            if move.Magnitude > 1 then move = move.Unit end
            local delta = yaw - input.LookYaw
            local c, s = math.cos(delta), math.sin(delta)
            local modified = table.clone(input)
            modified.Move = Vector2.new(move.X * c - move.Y * s, move.X * s + move.Y * c)
            modified.LookYaw, modified.VerticalLook = yaw, math.clamp(pitch, -1, 1)
            self.Active, self.LastYaw, self.LastPitch = true, yaw, modified.VerticalLook
            self.Commands += 1
            return modified
        end
        AntiAim.Wrapper = function(character, context, ...)
            local input = AntiAim.Original(character, context, ...)
            if not input then return input end
            local success, modified = pcall(function()
                if not AntiAim:Allowed(character, context) then AntiAim.Active = false return input end
                return AntiAim:Process(character, context, input)
            end)
            if success then return modified end
            AntiAim.LastError = tostring(modified)
            Settings.AntiAimEnabled = false
            AntiAim:Reset()
            task.defer(function()
                if not State.Running then return end
                local control = Library.Toggles.AntiAimEnabled
                if control then control:SetValue(false) end
                report("Anti-aim paused: " .. AntiAim.LastError)
            end)
            return input
        end
        module.SampleInput = AntiAim.Wrapper
        AntiAim.Ready = true
        connect(UserInputService.WindowFocusReleased, function() AntiAim.Focused = false AntiAim:Reset() end)
        connect(UserInputService.WindowFocused, function() AntiAim.Focused = true end)
        connect(LocalPlayer.CharacterRemoving, function() AntiAim:Reset() end)
    end)
    if not ok then AntiAim.LastError = tostring(failure) AntiAim:RestoreAll() end
end

local function aimAllowed()
    return State.Running and Aim.Ready and Settings.SilentEnabled and not Library.Toggled
        and not UserInputService:GetFocusedTextBox() and matchCharacter(LocalPlayer) ~= nil
end

local AimParts = { "Head", "UpperTorso", "LowerTorso" }
local AimRandom = Random.new()

local function weaponModsActive()
    return State.Running and WeaponMods.Ready and Settings.WeaponModsEnabled
        and matchCharacter(LocalPlayer) ~= nil
end

local function weaponPenetration(properties)
    local penetration = properties.Penetration or 0
    if weaponModsActive() and Settings.WeaponWallbang then
        return penetration + Settings.WeaponPenetration, Settings.WeaponWallbangSurfaces
    end
    return penetration, 100
end

local function castWeaponShot(origin, direction, range, penetration, maxSurfaces)
    local ignore = Aim.GetRayIgnore()
    local result = { Origin = origin, Direction = direction, Distance = range, Hits = {} }
    local first = Aim.Raycast.cast(origin, direction * range, nil, ignore)
    if not first.instance then return result end
    result.Distance = (first.position - origin).Magnitude
    local hits = Aim.Raycast.castThrough(first.position - direction * 0.001, direction * (penetration + 0.001), penetration, ignore)
    for index, hit in ipairs(hits) do
        if index > maxSurfaces * 2 then break end
        if hit.instance and hit.material then
            if (hit.position - origin).Magnitude > range + 0.01 then break end
            table.insert(result.Hits, {
                Position = hit.position, Instance = hit.instance, Material = hit.material.Name,
                Normal = hit.normal or Vector3.zero, Exit = index % 2 == 0,
            })
        end
    end
    return result
end
WeaponMods.CastShot = castWeaponShot

local function selectAimTarget(camera, origin, maximumRange, randomizePart, enemiesOnly)
    if not aimAllowed() then return nil end
    local center = camera.ViewportSize * 0.5
    local limit = math.min(Settings.SilentMaxDistance, maximumRange or math.huge)
    local candidates = {}
    local myTeam = teamOf(LocalPlayer)
    local randomPart = Settings.SilentTargetPart == "Random"
    for player in pairs(State.Entries) do
        local character, health = matchCharacter(player)
        if character and player ~= LocalPlayer and (not (Settings.SilentTeamCheck or enemiesOnly) or teamOf(player) ~= myTeam) then
            local names = (Settings.SilentTargetPart == "Closest" or randomPart) and AimParts
                or { Settings.SilentTargetPart == "Chest" and "UpperTorso" or "Head" }
            for _, name in ipairs(names) do
                local part = character:FindFirstChild(name)
                if part and part:IsA("BasePart") then
                    local point, onScreen = camera:WorldToViewportPoint(part.Position)
                    local screen = Vector2.new(point.X, point.Y)
                    local radius = (screen - center).Magnitude
                    local distance = (part.Position - origin).Magnitude
                    if onScreen and point.Z > 0 and radius <= Settings.SilentFOV and distance > 0.05 and distance <= limit then
                        local score = Settings.SilentPriority == "Distance" and distance
                            or Settings.SilentPriority == "Health" and health or radius
                        table.insert(candidates, {
                            Player = player, Character = character, Part = part, Position = part.Position,
                            Radius = radius, Score = score,
                        })
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.Score ~= b.Score then return a.Score < b.Score end
        if a.Radius ~= b.Radius then return a.Radius < b.Radius end
        return a.Player.UserId < b.Player.UserId
    end)
    local through = weaponModsActive() and Settings.WeaponWallbang and Settings.WeaponWallbangTargeting
    local weapon = through and WeaponMods.GetWeapon and WeaponMods.GetWeapon() or nil
    through = through and weapon and weapon.Bullet and weapon.Player == LocalPlayer
    local ignore = (Settings.SilentVisibleOnly or through) and Aim.GetRayIgnore() or nil
    local selectedPlayer, availableParts = nil, {}
    for _, candidate in ipairs(candidates) do
        if selectedPlayer and candidate.Player ~= selectedPlayer then continue end
        local visible = true
        if Settings.SilentVisibleOnly or through then
            local offset = candidate.Position - origin
            local hit = Aim.Raycast.cast(origin, offset.Unit * (offset.Magnitude + 0.05), nil, ignore)
            visible = not hit.instance or hit.instance:IsDescendantOf(candidate.Character)
            if not visible and through then
                local penetration, surfaces = weaponPenetration(weapon.Bullet.Properties)
                local shot = castWeaponShot(origin, offset.Unit, math.min(limit, weapon.Bullet.Properties.Range or 500), penetration, surfaces)
                for _, impact in ipairs(shot.Hits) do
                    if not impact.Exit and impact.Instance:IsDescendantOf(candidate.Character) then visible = true break end
                end
            end
        end
        if visible then
            if not randomPart then return candidate end
            selectedPlayer = candidate.Player
            table.insert(availableParts, candidate)
        end
    end
    if #availableParts > 0 then
        if randomizePart then return availableParts[AimRandom:NextInteger(1, #availableParts)] end
        for _, candidate in ipairs(availableParts) do
            if Aim.Target and candidate.Part == Aim.Target.Part then return candidate end
        end
        return availableParts[1]
    end
    return nil
end
Aim.SelectTarget = selectAimTarget

local function redirectedShot(bullet, shot, target)
    local offset = target.Position - shot.Origin
    if offset.Magnitude < 0.05 then return nil end
    local direction = offset.Unit
    local properties = bullet.Properties
    local penetration, surfaces = weaponPenetration(properties)
    local result = castWeaponShot(shot.Origin, direction, properties.Range or 500, penetration, surfaces)
    Aim.Redirects = Aim.Redirects + 1
    Aim.Target = target
    Aim.LastShot = {
        Player = target.Player, Part = target.Part, Origin = result.Origin,
        Direction = direction, Position = target.Position, Time = os.clock(),
    }
    return result
end

local function installSilent()
    local ok, failure = pcall(function()
        local storage = game:GetService("ReplicatedStorage")
        local bullet = require(storage.Components.Weapon.Classes.Bullet)
        local raycast = require(storage.Shared.Raycast)
        local getIgnore = require(storage.Components.Common.GetRayIgnore)
        assert(type(bullet._performRaycast) == "function" and type(raycast.cast) == "function"
            and type(raycast.castThrough) == "function" and type(getIgnore) == "function", "Unsupported weapon system")
        Aim.Module, Aim.Original, Aim.Raycast, Aim.GetRayIgnore = bullet, bullet._performRaycast, raycast, getIgnore
        Aim.Wrapper = function(self, spread, ...)
            local localShot = State.Running and self.IsActive and not self.IsDestroyed and self.Weapon
                and self.Weapon.Player == LocalPlayer
            local modified = localShot and weaponModsActive()
            local effectiveSpread = modified and Settings.WeaponSpreadEnabled and type(spread) == "number"
                and spread * Settings.WeaponSpreadScale / 100 or spread
            local shot = Aim.Original(self, effectiveSpread, ...)
            if not localShot or type(shot) ~= "table" then return shot end
            if Visuals.ThirdActive and Visuals.AdjustShot then
                local success, adjusted = pcall(function() return Visuals:AdjustShot(shot, self.Properties) end)
                if success then shot = adjusted else Visuals.LastError = tostring(adjusted) end
            end
            if modified and Settings.WeaponWallbang then
                local success, expanded = pcall(function()
                    local penetration, surfaces = weaponPenetration(self.Properties)
                    return castWeaponShot(shot.Origin, shot.Direction, self.Properties.Range or 500, penetration, surfaces)
                end)
                if success then
                    shot = expanded
                else
                    WeaponMods.LastError = tostring(expanded)
                    Settings.WeaponModsEnabled = false
                    task.defer(function()
                        if State.Running then
                            Library.Toggles.WeaponModsEnabled:SetValue(false)
                            report("Weapon mods paused: " .. WeaponMods.LastError)
                        end
                    end)
                end
            end
            if not aimAllowed() then return shot end
            if AimRandom:NextInteger(1, 100) > Settings.SilentHitChance then return shot end
            local success, redirected = pcall(function()
                local camera = workspace.CurrentCamera
                if not camera then return nil end
                local target = Trigger.ShotTarget
                if not target or not target.Silent then
                    target = selectAimTarget(camera, shot.Origin, self.Properties.Range or 500, true, Trigger.ShotTarget ~= nil)
                end
                if not target then return nil end
                return redirectedShot(self, shot, target)
            end)
            if success then return redirected or shot end
            Aim.LastError = tostring(redirected)
            Settings.SilentEnabled = false
            Aim.Target = nil
            task.defer(function()
                if State.Running then
                    Library.Toggles.SilentEnabled:SetValue(false)
                    report("Silent aim paused: " .. tostring(redirected))
                end
            end)
            return shot
        end
        bullet._performRaycast = Aim.Wrapper
        Aim.Ready = bullet._performRaycast == Aim.Wrapper
    end)
    if not ok then Aim.LastError = tostring(failure) end
end

local function installWeaponMods()
    WeaponMods.RestoreRecoil = function()
        local record = WeaponMods.RecoilRecord
        if record and record.Recoil.RotationValue == record.Applied then record.Recoil.RotationValue = record.Original end
        WeaponMods.RecoilRecord = nil
    end
    local function restoreWeapon(weapon, record)
        if record.Automatic and weapon.Properties == record.Automatic then weapon.Properties = record.Properties end
        WeaponMods.Weapons[weapon] = nil
    end
    WeaponMods.RestoreWeapons = function()
        for weapon, record in pairs(WeaponMods.Weapons) do restoreWeapon(weapon, record) end
    end
    local function applyWeapon(weapon)
        if not weapon or weapon.Player ~= LocalPlayer or weapon.IsDestroyed or not weapon.Bullet then return nil end
        local record = WeaponMods.Weapons[weapon]
        if not (weaponModsActive() and Settings.WeaponAutomatic) then
            if record then restoreWeapon(weapon, record) end
            return nil
        end
        if not record then record = {} WeaponMods.Weapons[weapon] = record end
        if weapon.Properties ~= record.Automatic then
            record.Properties = weapon.Properties
            local properties = table.clone(weapon.Properties)
            properties.Automatic = true
            if properties.ShootingOptions == "Burst" then properties.ShootingOptions = "Default" end
            if properties.FireModes then
                local modes = table.clone(properties.FireModes)
                for key, mode in pairs(modes) do
                    if type(mode) == "table" then
                        local changed = table.clone(mode)
                        changed.HoldRepeat = true
                        modes[key] = table.freeze(changed)
                    end
                end
                properties.FireModes = table.freeze(modes)
            end
            record.Automatic = table.freeze(properties)
            weapon.Properties = record.Automatic
        end
        return record
    end
    WeaponMods.ApplyWeapon = applyWeapon
    function State:UpdateWeaponMods()
        for weapon, record in pairs(WeaponMods.Weapons) do
            if weapon.IsDestroyed or weapon.IsEquipped ~= true or not weaponModsActive() then restoreWeapon(weapon, record)
            else applyWeapon(weapon) end
        end
        if WeaponMods.GetWeapon then applyWeapon(WeaponMods.GetWeapon()) end
    end
    local ok, failure = pcall(function()
        assert(Aim.Ready, "Weapon raycast is unavailable")
        local storage = game:GetService("ReplicatedStorage")
        local camera = require(storage.Controllers.CameraController)
        local inventory = require(storage.Controllers.InventoryController)
        local weapons = require(storage.Components.Weapon)
        assert(type(inventory.peekCurrentEquippedForMovement) == "function", "Weapon inventory is unavailable")
        WeaponMods.GetWeapon = inventory.peekCurrentEquippedForMovement
        for _, key in ipairs({ "equip", "shoot" }) do
            installHook(WeaponMods.Hooks, weapons, key, function(original)
                return function(self, ...)
                    applyWeapon(self)
                    return original(self, ...)
                end
            end)
        end
        installHook(WeaponMods.Hooks, camera, "setWeaponRecoil", function(original)
            return function(config, ...)
                if weaponModsActive() and Settings.WeaponRecoilEnabled and type(config) == "table" then
                    local scaled = table.clone(config)
                    scaled.Value = config.Value * Settings.WeaponRecoilScale / 100
                    local weapon = WeaponMods.GetWeapon()
                    if weapon and weapon.Player == LocalPlayer and weapon.Recoil then
                        WeaponMods.RecoilRecord = { Recoil = weapon.Recoil, Original = weapon.Recoil.RotationValue, Applied = scaled.Value }
                        weapon.Recoil.RotationValue = scaled.Value
                    end
                    return original(scaled, ...)
                end
                return original(config, ...)
            end
        end)
        installHook(WeaponMods.Hooks, camera, "weaponKick", function(original)
            return function(rotation, position, ...)
                if weaponModsActive() and Settings.WeaponKickEnabled then
                    local scaledRotation, scaledPosition = table.clone(rotation), table.clone(position)
                    scaledRotation.Value = rotation.Value * Settings.WeaponKickScale / 100
                    scaledPosition.Value = position.Value * Settings.WeaponKickScale / 100
                    return original(scaledRotation, scaledPosition, ...)
                end
                return original(rotation, position, ...)
            end
        end)
        WeaponMods.Ready = true
        local nextUpdate = 0
        connect(RunService.Heartbeat, function()
            if os.clock() < nextUpdate then return end
            nextUpdate = os.clock() + 0.15
            local success, err = pcall(function() State:UpdateWeaponMods() end)
            if not success then
                WeaponMods.LastError = tostring(err)
                Library.Toggles.WeaponModsEnabled:SetValue(false)
                report("Weapon mods paused: " .. WeaponMods.LastError)
            end
        end)
    end)
    if not ok then
        WeaponMods.LastError = tostring(failure)
        restoreHooks(WeaponMods.Hooks)
        WeaponMods.RestoreWeapons()
    end
end

local function installTrigger()
    function Trigger:Invoke(callback, ...)
        local readIdentity, writeIdentity = getthreadidentity or getidentity, setthreadidentity or setidentity
        local identity = type(readIdentity) == "function" and readIdentity()
        local restore = identity and type(writeIdentity) == "function"
        if restore then writeIdentity(2) end
        local result = table.pack(pcall(callback, ...))
        if restore then writeIdentity(identity) end
        if not result[1] then error(result[2], 0) end
        return table.unpack(result, 2, result.n)
    end
    function Trigger:Reset()
        self.Target, self.Since, self.Weapon, self.NextScan = nil, nil, nil, 0
        local pending = self.Pending
        if not pending then return end
        pending.Cancelled = true
        local weapon = pending.Weapon
        if pending.Kind == "Charge" then
            self.Pending = nil
            if not weapon.IsDestroyed and weapon.FireInputBinding == nil then
                pcall(function() self:Invoke(weapon.cancelRevolverCharge, weapon, false) end)
            end
        end
    end
    function Trigger:RestoreAll()
        self.Ready = false
        self:Reset()
        restoreHooks(self.Hooks)
        self.Pending, self.ShotTarget = nil, nil
    end
    function Trigger:Fail(message)
        self.LastError = tostring(message)
        self:Reset()
        Settings.TriggerEnabled = false
        task.defer(function()
            if not State.Running then return end
            local control = Library.Toggles.TriggerEnabled
            if control then control:SetValue(false) end
            report("Trigger bot paused: " .. self.LastError)
        end)
    end
    function Trigger:Allowed(weapon)
        if not State.Running or not self.Ready or not Settings.TriggerEnabled or not self.Focused
            or Library.Toggled or self.GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox()
            or LocalPlayer:GetAttribute("IsPlayerChatting") == true or not matchCharacter(LocalPlayer)
            or self.GameState.GetState() == "Buy Period" or self.CaseScene.IsActive() or self.Inspect.IsActive()
            or LocalPlayer:GetAttribute("IsDefusingBomb") == true or LocalPlayer:GetAttribute("IsLocallyDefusingBomb") == true then return false end
        if not weapon or weapon.Player ~= LocalPlayer or weapon.IsDestroyed or not weapon.IsEquipped
            or not weapon.Properties or weapon.Properties.Class ~= "Weapon" or not weapon.Bullet
            or not weapon.Bullet.IsActive or weapon.Bullet.IsDestroyed or type(weapon.shoot) ~= "function"
            or type(weapon.Rounds) ~= "number" or weapon.Rounds <= 0 or weapon.IsReloading or weapon.IsAdjustingSuppressor then return false end
        if Settings.TriggerScopedOnly and not (weapon.IsAiming or weapon.IsSniperScoped) then return false end
        return self.GetWeapon() == weapon
    end
    function Trigger:FromHit(hit)
        if not hit or not hit.instance then return nil end
        local myTeam = teamOf(LocalPlayer)
        if not myTeam then return nil end
        for player in pairs(State.Entries) do
            local character = matchCharacter(player)
            if character and hit.instance:IsDescendantOf(character) then
                if player == LocalPlayer or teamOf(player) == myTeam then return nil end
                return { Player = player, Character = character, Part = hit.instance, Position = hit.position }
            end
        end
        return nil
    end
    function Trigger:Acquire(weapon, randomizePart)
        local camera = workspace.CurrentCamera
        if not camera or not Aim.Ready then return nil end
        local origin = Visuals.ShotOrigin and Visuals:ShotOrigin() or camera.CFrame.Position
        local range = math.min(Settings.TriggerMaxDistance, weapon.Bullet.Properties.Range or 500)
        local ignore = Aim.GetRayIgnore()
        if Settings.TriggerMode ~= "Silent Aim FOV" then
            local direction = camera.CFrame.LookVector * range
            local target = self:FromHit(Aim.Raycast.cast(camera.CFrame.Position, direction, nil, ignore))
            if target then
                local actual = self:FromHit(Aim.Raycast.cast(origin, direction, nil, ignore))
                if actual and actual.Character == target.Character then return actual end
            end
        end
        if Settings.TriggerMode == "Crosshair" or not aimAllowed() then return nil end
        local target = selectAimTarget(camera, origin, range, randomizePart, true)
        if not target then return nil end
        target.Silent = true
        local offset = target.Position - origin
        local hit = Aim.Raycast.cast(origin, offset.Unit * (offset.Magnitude + 0.05), nil, ignore)
        if hit.instance and hit.instance:IsDescendantOf(target.Character) then return target end
        if weaponModsActive() and Settings.WeaponWallbang and Settings.WeaponWallbangTargeting then
            local penetration, surfaces = weaponPenetration(weapon.Bullet.Properties)
            local shot = castWeaponShot(origin, offset.Unit, range, penetration, surfaces)
            for _, impact in ipairs(shot.Hits) do
                if not impact.Exit and impact.Instance:IsDescendantOf(target.Character) then return target end
            end
        end
        return nil
    end
    function Trigger:Update(now)
        if not Settings.TriggerEnabled and not self.Pending then return end
        if self.Pending then
            local pending, weapon = self.Pending, self.Pending.Weapon
            local active = pending.Kind == "Burst" and weapon.IsBurstShooting or pending.Kind == "Charge" and weapon.IsChargeFiring
            if weapon.IsDestroyed or not active then self.Pending = nil end
        end
        if now < self.NextScan then return end
        self.NextScan = now + 1 / 60
        local weapon = self.GetWeapon()
        if not self:Allowed(weapon) then self:Reset() return end
        if self.Input.isActionPressed("Fire") or weapon.IsAlternativeFireHeld
            or (weapon.IsFireHeld and not (self.Pending and self.Pending.Kind == "Charge" and self.Pending.Weapon == weapon)) then self:Reset() return end
        local target = self:Acquire(weapon)
        if not target then self:Reset() return end
        if not self.Target or self.Target.Character ~= target.Character or self.Weapon ~= weapon then
            self:Reset()
            self.Target, self.Weapon, self.Since = target, weapon, now
        else
            self.Target = target
        end
        if self.Pending or weapon.IsShooting or weapon.IsBurstShooting or weapon.IsChargeFiring
            or now < self.NextShot or now < (weapon.NextShotDue or 0) or now - self.Since < Settings.TriggerDelay / 1000 then return end
        local animation = weapon.Viewmodel and weapon.Viewmodel.Animation
        local equip = animation and animation:getAnimation("Equip")
        if not equip or tick() - (weapon.WeaponEquippedTick or tick()) <= equip.Length * 0.925
            or tick() - (weapon.AlternativeSwitchTick or 0) <= (weapon.Properties.FireRate or 0.1) then return end
        local kind = weapon.Properties.ShootingOptions == "Revolver" and "Charge" or weapon.AlternativeShootingOption == "Burst" and "Burst" or "Single"
        self.Pending = { Weapon = weapon, Character = target.Character, Kind = kind }
        self.NextShot = now + math.max(Settings.TriggerInterval / 1000, 1 / 60)
        if kind == "Charge" then
            self:Invoke(weapon.startRevolverCharge, weapon, nil)
        elseif kind == "Burst" then
            self:Invoke(weapon.fireBurst, weapon)
        else
            self:Invoke(weapon.shoot, weapon)
            self.Pending = nil
        end
    end
    local ok, failure = pcall(function()
        assert(Aim.Ready, "Weapon raycast is unavailable")
        local storage = game:GetService("ReplicatedStorage")
        local module = require(storage.Components.Weapon)
        Trigger.GetWeapon = require(storage.Controllers.InventoryController).peekCurrentEquippedForMovement
        Trigger.GameState = require(storage.Database.Components.GameState)
        Trigger.Input = require(storage.Controllers.InputController)
        Trigger.CaseScene = require(storage.Controllers.CaseSceneController)
        Trigger.Inspect = require(storage.Controllers.InspectController)
        Trigger.GuiService = game:GetService("GuiService")
        installHook(Trigger.Hooks, module, "shoot", function(original)
            return function(weapon, ...)
                local pending = Trigger.Pending
                if not pending or pending.Weapon ~= weapon then return original(weapon, ...) end
                local allowed, target = pcall(function()
                    if pending.Cancelled or not Trigger:Allowed(weapon) then return nil end
                    return Trigger:Acquire(weapon, true)
                end)
                if not allowed then Trigger:Fail(target) return end
                if not target or target.Character ~= pending.Character then return end
                Trigger.ShotTarget = target
                local rounds = weapon.Rounds
                local result = table.pack(pcall(original, weapon, ...))
                Trigger.ShotTarget = nil
                if pending.Kind == "Charge" and weapon.FireInputBinding == nil then weapon.IsFireHeld = false end
                if not result[1] then Trigger:Fail(result[2]) return end
                if weapon.Rounds < rounds then Trigger.Shots += 1 end
                return table.unpack(result, 2, result.n)
            end
        end)
        Trigger.Ready = true
        connect(RunService.Heartbeat, function()
            local success, err = pcall(function() Trigger:Update(os.clock()) end)
            if not success then Trigger:Fail(err) end
        end)
        connect(UserInputService.WindowFocusReleased, function() Trigger.Focused = false Trigger:Reset() end)
        connect(UserInputService.WindowFocused, function() Trigger.Focused = true end)
        connect(LocalPlayer.CharacterRemoving, function() Trigger:Reset() end)
    end)
    if not ok then Trigger.LastError = tostring(failure) Trigger:RestoreAll() end
end

local function installSkinChanger()
    local storage = game:GetService("ReplicatedStorage")
    local ok, failure = pcall(function()
        SkinChanger.Library = require(storage.Database.Components.Libraries.Skins)
        SkinChanger.Assets = storage.Assets.Skins
        SkinChanger.WeaponAssets = storage.Assets.Weapons
        SkinChanger.GetWeapon = require(storage.Controllers.InventoryController).peekCurrentEquippedForMovement
        assert(type(SkinChanger.GetWeapon) == "function", "Weapon inventory is unavailable")
    end)
    if not ok then SkinChanger.LastError = tostring(failure) return end
    local library = SkinChanger.Library
    local wearOrder = { "Factory New", "Minimal Wear", "Field-Tested", "Well-Worn", "Battle-Scarred" }
    function SkinChanger:RefreshCatalog()
        local catalog, weapons, knives, knifeSet = {}, {}, {}, {}
        for _, folder in ipairs(self.WeaponAssets:GetChildren()) do
            local skins = self.Assets:FindFirstChild(folder.Name)
            if not folder:IsA("Folder") or not folder:FindFirstChild("Camera") or not skins then continue end
            local items = {}
            for _, info in ipairs(library.GetAllSkinsForWeapon(folder.Name) or {}) do
                if type(info) ~= "table" or type(info.skin) ~= "string" then continue end
                local asset = skins:FindFirstChild(info.skin)
                if asset and asset:FindFirstChild("Camera") then items[info.skin] = info end
            end
            local _, sample = next(items)
            if sample then
                catalog[folder.Name] = items
                if sample.type == "Melee" then table.insert(knives, folder.Name) knifeSet[folder.Name] = true
                else table.insert(weapons, folder.Name) end
            end
        end
        if #knives > 0 then table.insert(weapons, "Knife") end
        table.sort(weapons)
        table.sort(knives)
        self.Catalog, self.Weapons, self.Knives, self.KnifeSet = catalog, weapons, knives, knifeSet
        if self.WeaponControl then self.WeaponControl:SetValues(weapons) end
        if self.KnifeControl then
            local values = table.clone(knives)
            table.insert(values, 1, "Original")
            self.KnifeControl:SetValues(values)
        end
        if self.RefreshEditor then self:RefreshEditor() end
    end
    function SkinChanger:TextureFolder(weapon, skin, wear)
        local info = self.Catalog[weapon] and self.Catalog[weapon][skin]
        if not info then return nil end
        local folder = self.Assets:FindFirstChild(weapon)
        folder = folder and folder:FindFirstChild(skin)
        folder = folder and folder:FindFirstChild("Camera")
        if not folder then return nil end
        local wearName = library.GetWearNameForFloat(info, wear)
        local selected = folder:FindFirstChild(wearName)
        if selected then return selected, info, wearName end
        for _, name in ipairs(wearOrder) do
            selected = folder:FindFirstChild(name)
            if selected then return selected, info, name end
        end
    end
    function SkinChanger:RestoreModel(model)
        if Visuals.RestoreModel then Visuals:RestoreModel(model) end
        local record = self.Records[model]
        if not record then return end
        for _, item in ipairs(record.Items) do
            local owned = item.Applied.Parent == item.Part
            item.Applied:Destroy()
            for _, original in ipairs(item.Originals) do
                if owned and item.Part.Parent and model.Parent then original.Parent = item.Part
                else original:Destroy() end
            end
        end
        self.Records[model] = nil
    end
    function SkinChanger:RestoreAll()
        for model in pairs(self.Records) do self:RestoreModel(model) end
        if self.RestoreKnife then self:RestoreKnife() end
    end
    function SkinChanger:ConstructKnife(view, character, weapon)
        local readIdentity = getthreadidentity or getidentity
        local writeIdentity = setthreadidentity or setidentity
        local identity = readIdentity and writeIdentity and readIdentity()
        local success, failure = pcall(function()
            if identity then writeIdentity(2) end
            local getProperties = require(storage.Components.Common.GetWeaponProperties)
            assert(getProperties(view.CameraModelWeapon or view.Weapon or weapon.Name), "Knife properties are unavailable")
            view:construct(character, weapon)
        end)
        if identity then writeIdentity(identity) end
        if not success then error(failure, 0) end
    end
    function SkinChanger:RestoreKnife()
        local record = self.ModifiedKnife
        self.ModifiedKnife = nil
        if not record then return end
        local view, weapon = record.View, record.Weapon
        if view.IsDestroyed or weapon.IsDestroyed then return end
        view.CameraModelWeapon, view.Skin, view.Float = record.CameraModelWeapon, record.Skin, record.Float
        local character = weapon.Character or LocalPlayer.Character
        if character and character.Parent then self:ConstructKnife(view, character, weapon) end
    end
    function SkinChanger:ApplyKnife(weapon, selection)
        local view = weapon.Viewmodel
        if not view or not selection or not self.KnifeSet[selection.Weapon] then self:RestoreKnife() return end
        if self.ModifiedKnife and self.ModifiedKnife.View ~= view then self:RestoreKnife() end
        if not self.ModifiedKnife then
            self.ModifiedKnife = { View = view, Weapon = weapon, CameraModelWeapon = view.CameraModelWeapon, Skin = view.Skin, Float = view.Float }
        end
        local changed = view.CameraModelWeapon ~= selection.Weapon
        view.CameraModelWeapon, view.Skin, view.Float = selection.Weapon, selection.Skin, selection.Float
        if changed then
            if view.Model then self:RestoreModel(view.Model) end
            local character = weapon.Character or LocalPlayer.Character
            if character and character.Parent then self:ConstructKnife(view, character, weapon) end
        end
    end
    function SkinChanger:ApplyModel(model, weapon, selection)
        local folder = self:TextureFolder(weapon, selection.Skin, selection.Float)
        if not folder then return false end
        local key = weapon .. "\0" .. selection.Skin .. "\0" .. folder.Name
        local previous = self.Records[model]
        if previous and previous.Key == key then return true end
        self:RestoreModel(model)
        local materials = {}
        for _, paint in ipairs(folder:GetChildren()) do
            if paint:IsA("SurfaceAppearance") then materials[paint.Name] = paint end
        end
        local record = { Key = key, Items = {} }
        self.Records[model] = record
        for _, part in ipairs(model:QueryDescendants("MeshPart")) do
            local paint = materials[part.Name]
            if not paint then continue end
            local applied = paint:Clone()
            local originals = {}
            for _, child in ipairs(part:GetChildren()) do
                if child:IsA("SurfaceAppearance") then table.insert(originals, child) child.Parent = nil end
            end
            table.insert(record.Items, { Part = part, Originals = originals, Applied = applied })
            applied.Parent = part
        end
        return #record.Items > 0
    end
    function SkinChanger:Update()
        if not State.Running or not Settings.SkinEnabled then self:RestoreAll() return end
        local weapon = self.GetWeapon()
        local view = weapon and weapon.Viewmodel
        if not weapon or weapon.Player ~= LocalPlayer or weapon.IsDestroyed or not view
            or LocalPlayer:GetAttribute("IsSpectating") == true then self:RestoreAll() return end
        local knife = self.KnifeSet[weapon.Name] or weapon.Properties and weapon.Properties.Class == "Melee"
        if knife then self:ApplyKnife(weapon, self.Loadout.Knife) else self:RestoreKnife() end
        local model = view.Model
        if not model or not model.Parent then self:RestoreAll() return end
        local name = view.CameraModelWeapon or view.Weapon or weapon.Name
        local selection = knife and self.Loadout.Knife or self.Loadout[name]
        for previous in pairs(self.Records) do
            if previous ~= model or not selection then self:RestoreModel(previous) end
        end
        if selection then self:ApplyModel(model, name, selection) end
    end
    function SkinChanger:Store()
        Settings.SkinLoadout = HttpService:JSONEncode(self.Loadout)
        if self.LoadoutControl then self.LoadoutControl.Value = Settings.SkinLoadout end
        self.NextUpdate = 0
    end
    function SkinChanger:Import(value)
        local data = decodeObject(value)
        if not data then return end
        local loadout = {}
        local names = {}
        for name in pairs(data) do if type(name) == "string" then table.insert(names, name) end end
        table.sort(names)
        for _, name in ipairs(names) do
            local selection = data[name]
            local weapon = type(selection) == "table" and (name == "Knife" and selection.Weapon or name)
            if type(selection) == "table" and self.Catalog[weapon] and self.Catalog[weapon][selection.Skin] then
                local wear = selection.Float
                if type(wear) ~= "number" or wear ~= wear or math.abs(wear) == math.huge then wear = 0 end
                if self.KnifeSet[weapon] then
                    if name == "Knife" or not loadout.Knife then loadout.Knife = { Weapon = weapon, Skin = selection.Skin, Float = math.clamp(wear, 0, 1) } end
                elseif name ~= "Knife" then
                    loadout[name] = { Skin = selection.Skin, Float = math.clamp(wear, 0, 1) }
                end
            end
        end
        self.Loadout = loadout
        self:Store()
        if self.RefreshEditor then self:RefreshEditor() end
    end
    function State:UpdateSkins(key)
        if not SkinChanger.Ready or SkinChanger.Syncing then return end
        if key == "SkinWeapon" and SkinChanger.RefreshEditor then SkinChanger:RefreshEditor()
        elseif SkinChanger.RefreshPreview then SkinChanger:RefreshPreview() end
        SkinChanger.NextUpdate = 0
        if not Settings.SkinEnabled then SkinChanger:RestoreAll() end
    end
    SkinChanger:RefreshCatalog()
    SkinChanger.Ready = true
    connect(storage:GetAttributeChangedSignal("AvaiableSkins"), function()
        task.defer(function()
            if State.Running then
                local success, err = pcall(function() SkinChanger:RefreshCatalog() end)
                if not success then SkinChanger.LastError = tostring(err) end
            end
        end)
    end)
    connect(RunService.Heartbeat, function()
        if SkinChanger.Updating or os.clock() < SkinChanger.NextUpdate then return end
        SkinChanger.NextUpdate = os.clock() + 0.2
        SkinChanger.Updating = true
        local success, err = pcall(function() SkinChanger:Update() end)
        SkinChanger.Updating = false
        if not success then
            SkinChanger.LastError = tostring(err)
            Settings.SkinEnabled = false
            SkinChanger:RestoreAll()
            if Library.Toggles.SkinEnabled then Library.Toggles.SkinEnabled:SetValue(false) end
            report("Skin changer paused: " .. SkinChanger.LastError)
        end
    end)
end

local function installEffects()
    local transparent = NumberSequence.new(1)
    local function equal(a, b)
        if typeof(a) ~= "NumberSequence" or typeof(b) ~= "NumberSequence" then return a == b end
        local left, right = a.Keypoints, b.Keypoints
        if #left ~= #right then return false end
        for i, point in ipairs(left) do
            local other = right[i]
            if point.Time ~= other.Time or point.Value ~= other.Value or point.Envelope ~= other.Envelope then return false end
        end
        return true
    end
    function Effects:Restore(object)
        local record = self.Records[object]
        if not record then return end
        self.Records[object] = nil
        if record.Changed then record.Changed:Disconnect() end
        if record.Ancestry then record.Ancestry:Disconnect() end
        pcall(function()
            if equal(object[record.Property], record.Applied) then object[record.Property] = record.Original end
        end)
    end
    function Effects:Track(object)
        if not self.Ready or not State.Running or self.Records[object] then return end
        local property, value, root, setting
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if Settings.EffectsNoFlash then
            if object:IsA("ScreenGui") and object.Parent == playerGui
                and (object.Name == "FlashbangEffect" or object.Name == "FlashScreenshot") then
                property, value, root, setting = "Enabled", false, playerGui, "EffectsNoFlash"
            elseif object:IsA("ColorCorrectionEffect") and object.Parent == Lighting and object.Name == "FlashbangColorCorrection" then
                property, value, root, setting = "Enabled", false, Lighting, "EffectsNoFlash"
            end
        end
        if Settings.EffectsNoSmoke and object:IsA("ParticleEmitter") then
            local voxel = object:FindFirstAncestor("SmokeVoxel")
            local folder = voxel and voxel.Parent
            local debris = workspace:FindFirstChild("Debris")
            if voxel and voxel:IsA("BasePart") and folder and folder:IsA("Folder")
                and folder.Name:sub(1, 11) == "VoxelSmoke_" and debris and folder.Parent == debris then
                property, value, root, setting = "Transparency", transparent, debris, "EffectsNoSmoke"
            end
        end
        if not property then return end
        local record = { Property = property, Original = object[property], Setting = setting }
        self.Records[object] = record
        object[property] = value
        record.Applied = object[property]
        record.Changed = object:GetPropertyChangedSignal(property):Connect(function()
            if not self.Ready or not State.Running or not Settings[setting] or self.Records[object] ~= record then return end
            local current = object[property]
            if equal(current, record.Applied) then return end
            record.Original = current
            object[property] = value
            record.Applied = object[property]
        end)
        record.Ancestry = object.AncestryChanged:Connect(function()
            if not object:IsDescendantOf(root) then self:Restore(object) end
        end)
    end
    function Effects:Inspect(object)
        local ok, err = pcall(function() self:Track(object) end)
        if not ok then self.LastError = tostring(err) end
    end
    function Effects:BindRoot(key, root)
        local current = self.Roots[key]
        if current and current.Object == root then return end
        if current then current.Connection:Disconnect() self.Roots[key] = nil end
        if root then
            self.Roots[key] = { Object = root, Connection = root.DescendantAdded:Connect(function(object) self:Inspect(object) end) }
        end
    end
    function Effects:Refresh()
        if not self.Ready or not State.Running then return end
        if Settings.EffectsNoFlash and not self.FlashActive and self.Module then
            local readIdentity = getthreadidentity or getidentity
            local writeIdentity = setthreadidentity or setidentity
            local identity = readIdentity and readIdentity()
            local ok, err = pcall(self.Module.CancelFlash)
            if identity and writeIdentity then writeIdentity(identity) end
            if not ok then self.LastError = tostring(err) end
        end
        self.FlashActive = Settings.EffectsNoFlash
        for object, record in pairs(self.Records) do
            if not Settings[record.Setting] then self:Restore(object) end
        end
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local debris = workspace:FindFirstChild("Debris")
        self:BindRoot("PlayerGui", Settings.EffectsNoFlash and playerGui or nil)
        self:BindRoot("Lighting", Settings.EffectsNoFlash and Lighting or nil)
        self:BindRoot("Debris", Settings.EffectsNoSmoke and debris or nil)
        if Settings.EffectsNoFlash then
            if playerGui then for _, object in ipairs(playerGui:GetChildren()) do self:Inspect(object) end end
            for _, object in ipairs(Lighting:GetChildren()) do self:Inspect(object) end
        end
        if Settings.EffectsNoSmoke and debris then
            for _, object in ipairs(debris:QueryDescendants("#SmokeVoxel >> ParticleEmitter")) do self:Inspect(object) end
        end
    end
    function Effects:RestoreAll()
        self.Ready, self.FlashActive = false, false
        if self.Module and self.Module.Flash == self.Wrapper then self.Module.Flash = self.Original end
        for key, root in pairs(self.Roots) do root.Connection:Disconnect() self.Roots[key] = nil end
        for object in pairs(self.Records) do self:Restore(object) end
    end
    local ok, err = pcall(function()
        local module = require(game:GetService("ReplicatedStorage").Components.Common.VFXLibary.FlashEffect)
        local original = assert(module.Flash)
        Effects.Module, Effects.Original = module, original
        Effects.Wrapper = function(...)
            if State.Running and Effects.Ready and Settings.EffectsNoFlash then return false end
            return original(...)
        end
        module.Flash = Effects.Wrapper
    end)
    if not ok then Effects.LastError = tostring(err) end
    Effects.Ready = true
    connect(workspace.ChildAdded, function(object) if object.Name == "Debris" then Effects:Refresh() end end)
    connect(LocalPlayer.ChildAdded, function(object) if object:IsA("PlayerGui") then Effects:Refresh() end end)
    Effects:Refresh()
end

local function installVisuals()
    local storage = game:GetService("ReplicatedStorage")
    local faces = { SkyBack = "SkyboxBk", SkyDown = "SkyboxDn", SkyFront = "SkyboxFt", SkyLeft = "SkyboxLf", SkyRight = "SkyboxRt", SkyUp = "SkyboxUp" }
    local materials = { Neon = Enum.Material.Neon, SmoothPlastic = Enum.Material.SmoothPlastic, Glass = Enum.Material.Glass, Metal = Enum.Material.Metal, ForceField = Enum.Material.ForceField }
    local function restoreProperties(records, object)
        local values = records[object]
        if not values then return end
        records[object] = nil
        for property, record in pairs(values) do
            pcall(function() if object[property] == record.Applied then object[property] = record.Original end end)
        end
    end
    local function applyProperties(records, object, values)
        local saved = records[object] or {}
        records[object] = saved
        for property, record in pairs(saved) do
            if values[property] == nil then
                if object[property] == record.Applied then object[property] = record.Original end
                saved[property] = nil
            end
        end
        for property, value in pairs(values) do
            local current = object[property]
            local record = saved[property]
            if not record then record = { Original = current } saved[property] = record
            elseif current ~= record.Applied then record.Original = current end
            if current ~= value then object[property] = value end
            record.Applied = object[property]
        end
        if next(saved) == nil then records[object] = nil end
    end
    Visuals.ApplyProperties, Visuals.RestoreProperties = applyProperties, restoreProperties
    function Visuals:RestoreModel(model)
        local record = self.Parts[model]
        if not record then return end
        self.Parts[model] = nil
        for part in pairs(record.Properties) do
            restoreProperties(record.Properties, part)
        end
        for _, item in ipairs(record.Surfaces) do
            if item.Surface.Parent == nil then
                if item.Part.Parent and model.Parent then item.Surface.Parent = item.Part
                else item.Surface:Destroy() end
            end
        end
    end
    function Visuals:RestorePosition()
        local record = self.PositionRecord
        self.PositionRecord = nil
        if record and record.Model.Parent and record.Model:GetPivot() == record.Applied then
            record.Model:PivotTo(record.Original)
            if record.Large and record.Large.Parent and record.Small and record.Small.Parent then record.Large:PivotTo(record.Small:GetPivot()) end
        end
    end
    function Visuals:IsScoped(weapon)
        local view = weapon and weapon.Viewmodel
        return view and view.Bobble and view.Bobble.IsAiming == true
    end
    function Visuals:WantsThirdPerson()
        local weapon = SkinChanger.GetWeapon and SkinChanger.GetWeapon()
        return State.Running and Settings.ThirdPersonEnabled and matchCharacter(LocalPlayer) ~= nil
            and not (Settings.ThirdPersonScoped and self:IsScoped(weapon))
    end
    function Visuals:RestoreCamera()
        self.ThirdActive = false
        local saved = self.CameraRecord
        self.CameraRecord = nil
        if saved then
            LocalPlayer.CameraMode = saved.Mode
            LocalPlayer.CameraMinZoomDistance = math.min(saved.Min, LocalPlayer.CameraMaxZoomDistance)
            LocalPlayer.CameraMaxZoomDistance = saved.Max
            LocalPlayer.CameraMinZoomDistance = saved.Min
        end
        for part in pairs(self.Hidden) do restoreProperties(self.Hidden, part) end
    end
    function Visuals:UpdateCamera()
        local active = self:WantsThirdPerson()
        if not active then self:RestoreCamera() return end
        if not self.CameraRecord then
            self.CameraRecord = { Mode = LocalPlayer.CameraMode, Min = LocalPlayer.CameraMinZoomDistance, Max = LocalPlayer.CameraMaxZoomDistance }
        end
        local distance = Settings.ThirdPersonDistance
        LocalPlayer.CameraMode = Enum.CameraMode.Classic
        LocalPlayer.CameraMinZoomDistance = math.min(distance, LocalPlayer.CameraMaxZoomDistance)
        LocalPlayer.CameraMaxZoomDistance = distance
        LocalPlayer.CameraMinZoomDistance = distance
        self.ThirdActive = true
    end
    function Visuals:ShotOrigin()
        if not self.ThirdActive then return nil end
        local model = matchCharacter(LocalPlayer)
        local part = model and (model:FindFirstChild("CameraPart") or model:FindFirstChild("Head"))
        return part and part.Position
    end
    function Visuals:AdjustShot(shot, properties)
        local origin = self:ShotOrigin()
        if not origin then return shot end
        return castWeaponShot(origin, shot.Direction, properties.Range or 500, properties.Penetration or 0, 32)
    end
    local function category(part, root, weaponOnly)
        if weaponOnly then return "Weapon" end
        local current = part
        while current and current ~= root do
            local name = current.Name
            if name == "Left Arm" or name == "Right Arm" or name == "LeftHand" or name == "RightHand"
                or name == "LeftUpperArm" or name == "RightUpperArm" or name == "LeftLowerArm" or name == "RightLowerArm" then return "Arms" end
            if name == "Weapon" or name == "WeaponL" or name == "WeaponR" then return "Weapon" end
            current = current.Parent
        end
    end
    function Visuals:PaintModel(model, weaponOnly, now)
        local record = self.Parts[model]
        if not record then
            record = { Properties = {}, Surfaces = {}, Parts = {} }
            self.Parts[model] = record
            for _, part in ipairs(model:QueryDescendants("BasePart")) do
                local groupName = category(part, model, weaponOnly)
                if groupName and part.Transparency < 1 then
                    table.insert(record.Parts, { Part = part, Group = groupName })
                end
            end
        end
        for _, item in ipairs(record.Parts) do
            local part = item.Part
            if not part.Parent then continue end
            local prefix = "View" .. item.Group
            if not Settings[prefix .. "Enabled"] then continue end
            local color = Settings[prefix .. "Rainbow"] and Color3.fromHSV(now * Settings.ViewRainbowSpeed % 1, 1, 1) or Settings[prefix .. "Color"]
            local values = { Color = color }
            local material = materials[Settings[prefix .. "Material"]]
            if material then values.Material = material values.MaterialVariant = "" end
            if Settings.ViewSolidColor then
                if part:IsA("MeshPart") then values.TextureID = "" end
                for _, child in ipairs(part:GetChildren()) do
                    if child:IsA("SurfaceAppearance") then
                        table.insert(record.Surfaces, { Surface = child, Part = part })
                        child.Parent = nil
                    elseif child:IsA("Decal") or child:IsA("Texture") then
                        applyProperties(record.Properties, child, { Transparency = 1 })
                    elseif child:IsA("SpecialMesh") then
                        applyProperties(record.Properties, child, { TextureId = "" })
                    end
                end
            end
            applyProperties(record.Properties, part, values)
        end
    end
    function Visuals:OffsetViewmodel(view, camera)
        local original = view.Model:GetPivot()
        local offset = CFrame.new(Settings.ViewX, Settings.ViewY, Settings.ViewZ)
            * CFrame.Angles(math.rad(Settings.ViewPitch), math.rad(Settings.ViewYaw), math.rad(Settings.ViewRoll))
        view.Model:PivotTo(camera.CFrame * offset * camera.CFrame:ToObjectSpace(original))
        if view.LargeWeaponModel and view.SmallWeaponModel then view.LargeWeaponModel:PivotTo(view.SmallWeaponModel:GetPivot()) end
        self.PositionRecord = { Model = view.Model, Original = original, Applied = view.Model:GetPivot(), Large = view.LargeWeaponModel, Small = view.SmallWeaponModel }
    end
    function Visuals:RenderView(view)
        if not State.Running or view.Player ~= LocalPlayer or not view.Model or not view.Model.Parent then return end
        local weapon = SkinChanger.GetWeapon and SkinChanger.GetWeapon()
        if not weapon or weapon.Viewmodel ~= view or not matchCharacter(LocalPlayer) then return end
        if Settings.ViewPositionEnabled and not self.ThirdActive and not (Settings.ViewPositionScoped and self:IsScoped(weapon)) then
            self:OffsetViewmodel(view, workspace.CurrentCamera)
        else self.PositionRecord = nil end
        local now = os.clock()
        if Settings.ViewArmsEnabled or Settings.ViewWeaponEnabled then
            self:PaintModel(view.Model, false, now)
            if view.LargeWeaponModel and view.LargeWeaponModel.Parent then self:PaintModel(view.LargeWeaponModel, true, now) end
        end
    end
    function Visuals:UpdateVisibility()
        local wanted = {}
        if self.ThirdActive then
            local character = matchCharacter(LocalPlayer)
            local camera = workspace.CurrentCamera
            if character and camera then
                local anchor = character:FindFirstChild("CameraPart") or character:FindFirstChild("Head")
                local show = anchor and (camera.CFrame.Position - anchor.Position).Magnitude > 1.1
                for _, part in ipairs(character:QueryDescendants("BasePart, Decal")) do
                    wanted[part] = true
                    applyProperties(self.Hidden, part, { LocalTransparencyModifier = show and 0 or 1 })
                end
            end
            local weapon = SkinChanger.GetWeapon and SkinChanger.GetWeapon()
            local view = weapon and weapon.Viewmodel
            if view then
                for _, model in pairs({ view.Model, view.LargeWeaponModel, view.Bobble and view.Bobble.Scope }) do
                    if model and model.Parent then
                        for _, part in ipairs(model:QueryDescendants("BasePart, Decal")) do
                            wanted[part] = true
                            applyProperties(self.Hidden, part, { LocalTransparencyModifier = 1 })
                        end
                    end
                end
            end
        end
        for part in pairs(self.Hidden) do if not wanted[part] then restoreProperties(self.Hidden, part) end end
    end
    local function imageAsset(value)
        value = tostring(value):match("^%s*(.-)%s*$")
        if value:match("^%d+$") then return "rbxassetid://" .. value end
        if value:match("^rbxassetid://%d+$") or value:match("^rbxasset://[%w%p]+$") then return value end
    end
    function Visuals:UpdateWorld()
        local wanted = {}
        local function apply(object, values) wanted[object] = true applyProperties(self.World, object, values) end
        if Settings.LightEnabled then
            apply(Lighting, { ClockTime = Settings.LightTime, Brightness = Settings.LightBrightness,
                ExposureCompensation = Settings.LightExposure, Ambient = Settings.LightAmbient,
                OutdoorAmbient = Settings.LightOutdoor, GlobalShadows = Settings.LightShadows,
                FogColor = Settings.LightFogColor, FogStart = Settings.LightNoFog and 0 or Settings.LightFogStart,
                FogEnd = Settings.LightNoFog and 100000 or math.max(Settings.LightFogStart + 1, Settings.LightFogEnd) })
            if Settings.LightNoFog then
                for _, atmosphere in ipairs(Lighting:QueryDescendants("Atmosphere")) do apply(atmosphere, { Density = 0, Haze = 0 }) end
            end
        end
        if Settings.SkyEnabled then
            local sky = Lighting:FindFirstChildOfClass("Sky")
            if not sky then sky = Instance.new("Sky") sky.Name = "BloxStrikeSky" self.CreatedSky = sky sky.Parent = Lighting end
            local values = { SkyboxOrientation = Vector3.new(0, Settings.SkyRotation, 0), StarCount = Settings.SkyStars, CelestialBodiesShown = Settings.SkyCelestial }
            local preset = self.SkyPresets[Settings.SkyPreset]
            for key, property in pairs(faces) do
                local value = Settings.SkyPreset == "Custom" and imageAsset(Settings[key]) or preset and preset[property]
                if value then values[property] = value end
            end
            apply(sky, values)
        elseif self.CreatedSky then
            restoreProperties(self.World, self.CreatedSky)
            self.CreatedSky:Destroy()
            self.CreatedSky = nil
        end
        if Settings.ToneEnabled then
            if not self.Tone or not self.Tone.Parent then self.Tone = Instance.new("ColorCorrectionEffect") self.Tone.Name = "BloxStrikeTone" self.Tone.Parent = Lighting end
            self.Tone.TintColor, self.Tone.Saturation, self.Tone.Contrast = Settings.ToneTint, Settings.ToneSaturation, Settings.ToneContrast
        elseif self.Tone then self.Tone:Destroy() self.Tone = nil end
        if Settings.BloomEnabled then
            if not self.Bloom or not self.Bloom.Parent then self.Bloom = Instance.new("BloomEffect") self.Bloom.Name = "BloxStrikeBloom" self.Bloom.Parent = Lighting end
            self.Bloom.Intensity, self.Bloom.Size, self.Bloom.Threshold = Settings.BloomIntensity, Settings.BloomSize, Settings.BloomThreshold
        elseif self.Bloom then self.Bloom:Destroy() self.Bloom = nil end
        for object in pairs(self.World) do if not wanted[object] then restoreProperties(self.World, object) end end
        local weapon = SkinChanger.GetWeapon and SkinChanger.GetWeapon()
        local view = weapon and weapon.Viewmodel
        for model in pairs(self.Parts) do
            if not view or (model ~= view.Model and model ~= view.LargeWeaponModel) then self:RestoreModel(model) end
        end
    end
    function Visuals:Refresh()
        for model in pairs(self.Parts) do self:RestoreModel(model) end
        self:RestorePosition()
        self:UpdateCamera()
        self:UpdateWorld()
    end
    function Visuals:RestoreAll()
        self.Ready = false
        restoreHooks(self.Hooks)
        self:RestoreCamera()
        self:RestorePosition()
        for model in pairs(self.Parts) do self:RestoreModel(model) end
        for object in pairs(self.World) do restoreProperties(self.World, object) end
        if self.CreatedSky then self.CreatedSky:Destroy() self.CreatedSky = nil end
        if self.Tone then self.Tone:Destroy() self.Tone = nil end
        if self.Bloom then self.Bloom:Destroy() self.Bloom = nil end
    end
    local ok, failure = pcall(function()
        local assets = storage.Assets:FindFirstChild("Lighting")
        if assets then
            for _, sky in ipairs(assets:QueryDescendants("Sky")) do Visuals.SkyPresets[sky.Parent.Name] = sky end
        end
        local viewmodel = require(storage.Classes.WeaponComponent.Classes.Viewmodel)
        local cameraController = require(storage.Controllers.CameraController)
        installHook(Visuals.Hooks, cameraController, "setPerspective", function(original)
            return function(firstPerson, mouseEnabled, distance, ...)
                if Visuals.Ready and Visuals:WantsThirdPerson() then
                    return original(false, mouseEnabled, Settings.ThirdPersonDistance, ...)
                end
                return original(firstPerson, mouseEnabled, distance, ...)
            end
        end)
        installHook(Visuals.Hooks, viewmodel, "render", function(original)
            return function(view, ...)
                local results = table.pack(original(view, ...))
                if Visuals.Ready then
                    local success, err = pcall(function() Visuals:RenderView(view) end)
                    if not success then Visuals.LastError = tostring(err) end
                end
                return table.unpack(results, 1, results.n)
            end
        end)
        local melee = require(storage.Components.Melee)
        installHook(Visuals.Hooks, melee, "shoot", function(original)
            return function(weapon, ...)
                local origin = weapon.Player == LocalPlayer and Visuals:ShotOrigin()
                local camera = workspace.CurrentCamera
                if not origin or not camera then return original(weapon, ...) end
                local saved = camera.CFrame
                local applied = CFrame.new(origin) * saved.Rotation
                camera.CFrame = applied
                local results = table.pack(pcall(original, weapon, ...))
                if camera.CFrame == applied then camera.CFrame = saved end
                if not results[1] then error(results[2], 0) end
                return table.unpack(results, 2, results.n)
            end
        end)
        Visuals.Ready = true
        connect(RunService.RenderStepped, function()
            if not State.Running then return end
            local success, err = pcall(function() Visuals:UpdateCamera() Visuals:UpdateVisibility() end)
            if not success then Visuals.LastError = tostring(err) Visuals:RestoreCamera() end
        end)
        local nextUpdate = 0
        connect(RunService.Heartbeat, function()
            if os.clock() < nextUpdate then return end
            nextUpdate = os.clock() + 0.2
            local success, err = pcall(function() Visuals:UpdateWorld() end)
            if not success then Visuals.LastError = tostring(err) end
        end)
    end)
    if not ok then Visuals.LastError = tostring(failure) Visuals:RestoreAll() end
end

local function createAimDrawings()
    local holder = { Objects = {} }
    local ok = pcall(function()
        Aim.FOVOutline = newDrawing(holder, "Circle", { Filled = false, NumSides = 96, Radius = Settings.SilentFOV })
        Aim.FOVCircle = newDrawing(holder, "Circle", { Filled = false, NumSides = 96, Radius = Settings.SilentFOV })
    end)
    if ok then
        for _, object in ipairs(holder.Objects) do table.insert(Aim.Objects, object) end
    else
        for _, object in ipairs(holder.Objects) do removeDrawing(object) end
        Aim.FOVOutline, Aim.FOVCircle = nil, nil
        Aim.FOVLines, Aim.FOVBorders = {}, {}
        for i = 1, 48 do
            Aim.FOVBorders[i] = newDrawing(Aim, "Line")
            Aim.FOVLines[i] = newDrawing(Aim, "Line")
        end
    end
    Aim.MarkerOutline = newDrawing(Aim, "Square", { Filled = false, Thickness = 3 })
    Aim.Marker = newDrawing(Aim, "Square", { Filled = false, Thickness = 1 })
end

local function updateAim(now, camera)
    hideAim()
    if not Settings.SilentEnabled or not Aim.Ready or Library.Toggled or not matchCharacter(LocalPlayer) then Aim.Target = nil return end
    if aimAllowed() then
        if now >= Aim.NextSelect then
            Aim.NextSelect = now + 0.05
            Aim.Target = selectAimTarget(camera, Visuals.ShotOrigin and Visuals:ShotOrigin() or camera.CFrame.Position)
        end
    else
        Aim.Target = nil
    end
    local target = Aim.Target
    if target and (not target.Part.Parent or matchCharacter(target.Player) ~= target.Character) then
        target = nil
        Aim.Target = nil
    end
    local center = camera.ViewportSize * 0.5
    local opacity = Settings.SilentFOVOpacity / 100
    local color = target and Settings.SilentTargetColor or Settings.SilentFOVColor
    if Aim.FOVCircle then
        for _, circle in ipairs({ Aim.FOVOutline, Aim.FOVCircle }) do
            circle.Position, circle.Radius = center, Settings.SilentFOV
            circle.Transparency = opacity
            circle.Visible = true
        end
        Aim.FOVOutline.Color, Aim.FOVOutline.Thickness = Color3.fromRGB(10, 12, 18), Settings.SilentFOVThickness + 2
        Aim.FOVCircle.Color, Aim.FOVCircle.Thickness = color, Settings.SilentFOVThickness
    else
        for i = 1, 48 do
            local a, b = (i - 1) * math.pi / 24, i * math.pi / 24
            local from = center + Vector2.new(math.cos(a), math.sin(a)) * Settings.SilentFOV
            local to = center + Vector2.new(math.cos(b), math.sin(b)) * Settings.SilentFOV
            for index, object in ipairs({ Aim.FOVBorders[i], Aim.FOVLines[i] }) do
                object.From, object.To = from, to
                object.Color = index == 1 and Color3.fromRGB(10, 12, 18) or color
                object.Thickness = Settings.SilentFOVThickness + (index == 1 and 2 or 0)
                object.Transparency, object.Visible = opacity, true
            end
        end
    end
    if Settings.SilentShowTarget and target then
        local projected, onScreen = camera:WorldToViewportPoint(target.Part.Position)
        local position = Vector2.new(projected.X, projected.Y)
        if onScreen and (position - center).Magnitude <= Settings.SilentFOV then
            for _, marker in ipairs({ Aim.MarkerOutline, Aim.Marker }) do
                marker.Position, marker.Size = position - Vector2.new(4, 4), Vector2.new(8, 8)
                marker.Transparency, marker.Visible = opacity, true
            end
            Aim.MarkerOutline.Color = Color3.fromRGB(10, 12, 18)
            Aim.Marker.Color = Settings.SilentTargetColor
        end
    end
end

local function bindCharacter(entry, character, now)
    entry.Character = character
    entry.Root = character:FindFirstChild("HumanoidRootPart")
    entry.Head = character:FindFirstChild("Head")
    entry.Parts = {}
    entry.SkeletonNodes = nil
    for _, name in ipairs(BodyNames) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then table.insert(entry.Parts, part) end
    end
    entry.NextParts = now + 1
    entry.NextRay = 0
end

local function projectedBox(entry, camera)
    local root = entry.Root
    local frame = root.CFrame
    local minimum = Vector3.new(math.huge, math.huge, math.huge)
    local maximum = -minimum
    local count = 0
    for _, part in ipairs(entry.Parts) do
        if part.Parent == entry.Character then
            local relative = frame:ToObjectSpace(part.CFrame)
            local half = part.Size * 0.5
            local right, up, look = relative.RightVector, relative.UpVector, relative.LookVector
            local extent = Vector3.new(
                math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z,
                math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z,
                math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
            )
            minimum = minimum:Min(relative.Position - extent)
            maximum = maximum:Max(relative.Position + extent)
            count = count + 1
        end
    end
    if count == 0 then return nil end
    local vertices, depths = {}, {}
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local function include(point)
        local projected = camera:WorldToViewportPoint(point)
        minX, minY = math.min(minX, projected.X), math.min(minY, projected.Y)
        maxX, maxY = math.max(maxX, projected.X), math.max(maxY, projected.Y)
    end
    for x = 0, 1 do
        for y = 0, 1 do
            for z = 0, 1 do
                local point = frame:PointToWorldSpace(Vector3.new(
                    x == 0 and minimum.X or maximum.X,
                    y == 0 and minimum.Y or maximum.Y,
                    z == 0 and minimum.Z or maximum.Z
                ))
                local depth = -camera.CFrame:PointToObjectSpace(point).Z
                table.insert(vertices, point)
                table.insert(depths, depth)
                if depth >= 0.1 then include(point) end
            end
        end
    end
    for _, edge in ipairs(BoxEdges) do
        local a, b = edge[1], edge[2]
        if (depths[a] >= 0.1) ~= (depths[b] >= 0.1) then
            include(vertices[a]:Lerp(vertices[b], (0.1 - depths[a]) / (depths[b] - depths[a])))
        end
    end
    local viewport = camera.ViewportSize
    if minX == math.huge or maxX < 0 or maxY < 0 or minX > viewport.X or minY > viewport.Y then return nil end
    minX, minY = math.clamp(minX, 1, viewport.X - 2), math.clamp(minY, 1, viewport.Y - 2)
    maxX, maxY = math.clamp(maxX, 2, viewport.X - 1), math.clamp(maxY, 2, viewport.Y - 1)
    if maxX - minX < 2 or maxY - minY < 3 then return nil end
    return math.floor(minX), math.floor(minY), math.ceil(maxX), math.ceil(maxY)
end

local function line(object, from, to, color, thickness, opacity)
    object.From, object.To = from, to
    object.Color, object.Thickness, object.Transparency = color, thickness, opacity
    object.Visible = true
end

function Skeleton:Bind(entry)
    local character = entry.Character
    local parts, joints, nodes = {}, {}, {}
    for _, part in ipairs(entry.Parts) do if part.Parent == character then parts[part.Name] = part end end
    for _, joint in ipairs(character:QueryDescendants("Motor6D")) do
        if joint.Part0 and joint.Part1 and parts[joint.Part0.Name] == joint.Part0 and parts[joint.Part1.Name] == joint.Part1 then
            joints[joint.Name:gsub("%s", "")] = joint
        end
    end
    local function node(name, part, offset)
        local joint = joints[name]
        if joint then nodes[name] = { Part = joint.Part1, Joint = joint }
        elseif part then nodes[name] = { Part = part, Offset = offset or Vector3.zero } end
    end
    node("Head", parts.Head)
    node("Neck", parts.UpperTorso or parts.Torso, Vector3.new(0, 0.5, 0))
    node("Waist", parts.LowerTorso or parts.Torso, parts.LowerTorso and Vector3.zero or Vector3.new(0, -0.5, 0))
    for _, side in ipairs({ "Left", "Right" }) do
        local arm = parts[side .. " Arm"]
        local leg = parts[side .. " Leg"]
        node(side .. "Shoulder", parts[side .. "UpperArm"] or arm, Vector3.new(0, 0.5, 0))
        node(side .. "Elbow", parts[side .. "LowerArm"] or arm, parts[side .. "LowerArm"] and Vector3.new(0, 0.5, 0) or Vector3.zero)
        node(side .. "Wrist", parts[side .. "Hand"] or arm, parts[side .. "Hand"] and Vector3.new(0, 0.5, 0) or Vector3.new(0, -0.5, 0))
        node(side .. "Hand", parts[side .. "Hand"] or arm, Vector3.new(0, -0.5, 0))
        node(side .. "Hip", parts[side .. "UpperLeg"] or leg, Vector3.new(0, 0.5, 0))
        node(side .. "Knee", parts[side .. "LowerLeg"] or leg, parts[side .. "LowerLeg"] and Vector3.new(0, 0.5, 0) or Vector3.zero)
        node(side .. "Ankle", parts[side .. "Foot"] or leg, parts[side .. "Foot"] and Vector3.new(0, 0.5, 0) or Vector3.new(0, -0.5, 0))
        node(side .. "Foot", parts[side .. "Foot"] or leg, parts[side .. "Foot"] and Vector3.zero or Vector3.new(0, -0.5, 0))
    end
    entry.SkeletonNodes = nodes
end

function Skeleton:Project(camera, a, b)
    local near = 0.1
    local za, zb = -camera.CFrame:PointToObjectSpace(a).Z, -camera.CFrame:PointToObjectSpace(b).Z
    if za < near and zb < near then return end
    if za < near then a = a:Lerp(b, (near - za) / (zb - za))
    elseif zb < near then b = a:Lerp(b, (near - za) / (zb - za)) end
    local pa, pb = camera:WorldToViewportPoint(a), camera:WorldToViewportPoint(b)
    local dx, dy = pb.X - pa.X, pb.Y - pa.Y
    local lower, upper, viewport = 0, 1, camera.ViewportSize
    for edge = 1, 4 do
        local p = edge == 1 and -dx or edge == 2 and dx or edge == 3 and -dy or dy
        local q = edge == 1 and pa.X or edge == 2 and viewport.X - pa.X or edge == 3 and pa.Y or viewport.Y - pa.Y
        if math.abs(p) < 0.000001 then
            if q < 0 then return end
        else
            local t = q / p
            if p < 0 then lower = math.max(lower, t) else upper = math.min(upper, t) end
            if lower > upper then return end
        end
    end
    local from = Vector2.new(pa.X + dx * lower, pa.Y + dy * lower)
    local to = Vector2.new(pa.X + dx * upper, pa.Y + dy * upper)
    if (to - from).Magnitude < 0.25 then return end
    return from, to
end

function Skeleton:Draw(entry, camera, playerColor, opacity)
    if not entry.SkeletonNodes then self:Bind(entry) end
    if not entry.SkeletonLines then
        entry.SkeletonLines, entry.SkeletonBorders = {}, {}
        for i = 1, #SkeletonEdges do
            entry.SkeletonBorders[i] = newDrawing(entry, "Line")
            entry.SkeletonLines[i] = newDrawing(entry, "Line")
        end
    end
    local positions = {}
    for name, node in pairs(entry.SkeletonNodes) do
        local part, joint = node.Part, node.Joint
        if part.Parent == entry.Character then
            if joint and joint.Parent and joint.Part1 == part then positions[name] = (part.CFrame * joint.C1).Position
            elseif not joint then positions[name] = part.CFrame:PointToWorldSpace(part.Size * node.Offset) end
        end
    end
    local color = Settings.SkeletonTeamColor and playerColor or Settings.SkeletonColor
    for i, edge in ipairs(SkeletonEdges) do
        local stroke, border = entry.SkeletonLines[i], entry.SkeletonBorders[i]
        stroke.Visible, border.Visible = false, false
        local a, b = positions[edge[1]], positions[edge[2]]
        if a and b then
            local from, to = self:Project(camera, a, b)
            if from then
                if Settings.SkeletonOutline then line(border, from, to, Settings.OutlineColor, Settings.SkeletonThickness + 2, opacity) end
                line(stroke, from, to, color, Settings.SkeletonThickness, opacity)
            end
        end
    end
end

local function shortName(name)
    name = name:gsub("[%c]", "")
    local ok, offset = pcall(utf8.offset, name, Settings.NameLength + 1)
    if ok and offset then return name:sub(1, offset - 1) .. "..." end
    return name
end

local function distanceText(distance)
    local meters = Settings.DistanceUnit == "Meters"
    return tostring(math.floor(distance * (meters and 0.28 or 1) + 0.5)) .. (meters and " m" or " studs")
end

local function text(object, value, x, y, color, opacity, viewport, size, outlined)
    size = size or Settings.TextSize
    if outlined == nil then outlined = Settings.Outlines end
    object.Text, object.Size, object.Font = value, size, Fonts[Settings.TextFont] or 2
    object.Color, object.OutlineColor = color, Settings.OutlineColor
    object.Outline, object.Transparency = outlined, opacity
    local half = math.min(object.TextBounds.X * 0.5, viewport.X * 0.5 - 3)
    object.Position = Vector2.new(math.clamp(x, half + 2, viewport.X - half - 2), y)
    object.Visible = y >= 0 and y + size + 2 <= viewport.Y
end

local function installGrenades()
    local fuseTimes = { ["HE Grenade"] = 1.6, Flashbang = 1.5, Molotov = 2.4, ["Incendiary Grenade"] = 2.4 }
    local kinds = {
        ["HE Grenade"] = { "GrenadeHE", "GrenadeHEColor" }, Flashbang = { "GrenadeFlash", "GrenadeFlashColor" },
        ["Smoke Grenade"] = { "GrenadeSmoke", "GrenadeSmokeColor" }, Molotov = { "GrenadeMolotov", "GrenadeFireColor" },
        ["Incendiary Grenade"] = { "GrenadeIncendiary", "GrenadeFireColor" }, ["Decoy Grenade"] = { "GrenadeDecoy", "GrenadeDecoyColor" },
    }
    local function record(name)
        return { Name = name, Objects = {}, Strokes = {}, Markers = {}, History = {}, NextPrediction = 0 }
    end
    function Grenades:Remove(entry)
        entry.Removed, entry.Job = true, nil
        for _, object in ipairs(entry.Objects) do removeDrawing(object) end
        table.clear(entry.Objects)
    end
    function Grenades:HideAll()
        for _, entry in pairs(self.Entries) do hide(entry) end
        for _, entry in pairs(self.Previews) do hide(entry) end
    end
    function Grenades:Refresh()
        table.clear(self.Jobs)
        for _, entries in ipairs({ self.Entries, self.Previews }) do
            for _, entry in pairs(entries) do entry.Job, entry.Forecast, entry.NextPrediction = nil, nil, 0 hide(entry) end
        end
        if not Settings.GrenadeEnabled then
            for model, entry in pairs(self.Entries) do self:Remove(entry) self.Entries[model] = nil end
        end
    end
    function Grenades:RestoreAll()
        self.Ready = false
        if self.Module and self.Module.simulate == self.Wrapper then self.Module.simulate = self.Original end
        for _, entries in ipairs({ self.Entries, self.Previews }) do
            for key, entry in pairs(entries) do self:Remove(entry) entries[key] = nil end
        end
        table.clear(self.Jobs)
    end
    function Grenades:AddHistory(entry, position, now, bounce)
        local last = entry.History[#entry.History]
        if last and not bounce and (now - last.Time < 0.075 or (last.Position - position).Magnitude < 0.03) then return end
        table.insert(entry.History, { Position = position, Time = now, Bounce = bounce })
        while #entry.History > 160 do table.remove(entry.History, 1) end
    end
    function Grenades:Capture(result, config, params)
        local model = params.FilterDescendantsInstances[1]
        if not model or not model:IsA("Model") or not model:HasTag("Grenade") then return end
        local name = model:GetAttribute("GrenadeName")
        if not kinds[name] then return end
        self.Profiles[name] = table.clone(config)
        if not Settings.GrenadeEnabled then return end
        local entry = self.Entries[model]
        if not entry then entry = record(name) entry.Model = model self.Entries[model] = entry end
        local now = os.clock()
        entry.State, entry.Config, entry.Params = table.clone(result.state), table.clone(config), params
        entry.Position = result.state.position
        for _, event in ipairs(result.events) do
            if event.type == "bounce" then
                self:AddHistory(entry, event.position, now, true)
                entry.NextPrediction = 0
                entry.Job, entry.Forecast = nil, nil
            end
        end
        self:AddHistory(entry, entry.Position, now, false)
        self.Captures += 1
    end
    function Grenades:NewJob(entry, initial, config, params, now)
        local job = {
            Entry = entry, Current = table.clone(initial), Config = table.clone(config), Params = params,
            StartTime = initial.simulationTime, Horizon = Settings.GrenadeHorizon, Steps = 0, Created = now,
            Points = { { Position = initial.position, Time = initial.simulationTime } }, Bounces = {}, LastPointTime = initial.simulationTime,
        }
        entry.Job, entry.NextPrediction = job, now + 1 / Settings.GrenadeRefresh
        table.insert(self.Jobs, job)
        return job
    end
    function Grenades:Advance(job)
        if job.Current.isAtRest then
            job.EndPosition, job.EndTime, job.Reason = job.Current.position, job.Current.simulationTime, "rest"
            job.Entry.Forecast, job.Entry.Job = job, nil
            return true
        end
        local state, event = self.Step(job.Current, job.Config, job.Params, self.StepTime)
        job.Current, job.Steps = state, job.Steps + 1
        if event and event.type == "bounce" then table.insert(job.Bounces, event.position) end
        local terminal = state.isAtRest or state.simulationTime - job.StartTime >= job.Horizon or job.Steps >= 1280
        if event or terminal or state.simulationTime - job.LastPointTime >= 0.0625 then
            table.insert(job.Points, { Position = state.position, Time = state.simulationTime })
            job.LastPointTime = state.simulationTime
        end
        if terminal then
            job.EndPosition, job.EndTime = state.position, state.simulationTime
            job.Reason = event and event.type or "limit"
            job.Entry.Forecast, job.Entry.Job = job, nil
        end
        return terminal
    end
    function Grenades:PreparePreview(camera, now)
        local weapon = SkinChanger.GetWeapon and SkinChanger.GetWeapon()
        local character = matchCharacter(LocalPlayer)
        local active = Settings.GrenadePreview and character and weapon and not weapon.IsDestroyed
            and kinds[weapon.Name] and not weapon.ThrowFinished and Settings[kinds[weapon.Name][1]]
        local selected = Settings.GrenadePreviewMode
        if selected == "Auto" then
            selected = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) and "Near" or "Far"
        end
        for _, mode in ipairs({ "Far", "Near" }) do
            local entry = self.Previews[mode]
            if not entry then entry = record("") entry.Preview = mode self.Previews[mode] = entry end
            entry.Active = active and (selected == mode or selected == "Both") or false
            if not entry.Active then hide(entry) entry.Job, entry.Forecast = nil, nil continue end
            if entry.Weapon ~= weapon then entry.Weapon, entry.Name, entry.Job, entry.Forecast = weapon, weapon.Name, nil, nil end
            if entry.Job or now < entry.NextPrediction then continue end
            local root = character:FindFirstChild("HumanoidRootPart")
            if not root then continue end
            local config = self.Profiles[weapon.Name] and table.clone(self.Profiles[weapon.Name])
            if not config then
                local asset = self.Storage.Assets.Weapons:FindFirstChild(weapon.Name)
                local model = asset and asset:FindFirstChild("Character")
                local radius = model and model:GetExtentsSize().Magnitude * 0.5 or 0.3
                local fire = weapon.Name == "Molotov" or weapon.Name == "Incendiary Grenade"
                config = self.Module.createConfig(radius, 1, mode == "Near", fuseTimes[weapon.Name], fire and 0.1 or nil, fire or nil)
            end
            config.rangeScale, config.isNearThrow = 1, mode == "Near"
            local base = root.Position
            if LocalPlayer:GetAttribute("IsCrouching") == true then base = Vector3.new(base.X, camera.CFrame.Position.Y - 2.4, base.Z) end
            local position, direction = self.Module.calculateThrowParameters(base, camera.CFrame.LookVector, mode, config.rangeScale)
            local initial = self.Module.createInitialState(position, direction, mode, self.GetVelocity(character), config.rangeScale, workspace:GetServerTimeNow())
            local params = RaycastParams.new()
            params.FilterType, params.IgnoreWater, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true, false
            local ignore = { character, camera }
            local debris = workspace:FindFirstChild("Debris")
            if debris then table.insert(ignore, debris) end
            params.FilterDescendantsInstances = ignore
            params.CollisionGroup = teamOf(LocalPlayer) == "Terrorists" and "TGrenade" or "CTGrenade"
            entry.Position = position
            self:NewJob(entry, initial, config, params, now)
        end
    end
    function Grenades:Update(now)
        local camera = workspace.CurrentCamera
        if not self.Ready or not State.Running or not camera then return end
        for model, entry in pairs(self.Entries) do
            if not model.Parent or model:GetAttribute("SimulationFinished") == true then entry.Ended = entry.Ended or now entry.Job, entry.Forecast = nil, nil end
            while entry.History[1] and now - entry.History[1].Time > Settings.GrenadeTrailTime do table.remove(entry.History, 1) end
            if entry.Ended and now - entry.Ended > Settings.GrenadeTrailTime then self:Remove(entry) self.Entries[model] = nil end
        end
        if not Settings.GrenadeEnabled or (Settings.HideWithMenu and Library.Toggled) then self:HideAll() return end
        self:PreparePreview(camera, now)
        if Settings.GrenadePrediction then
            for _, entry in pairs(self.Entries) do
                if not entry.Ended and not entry.Job and now >= entry.NextPrediction and Settings[kinds[entry.Name][1]]
                    and (entry.Position - camera.CFrame.Position).Magnitude <= Settings.GrenadeMaxDistance then
                    self:NewJob(entry, entry.State, entry.Config, entry.Params, now)
                end
            end
        end
        local deadline, steps = os.clock() + 0.0025, 0
        while #self.Jobs > 0 and steps < 256 and os.clock() < deadline do
            local job = self.Jobs[1]
            if now - job.Created > 0.5 and job.Entry.Job == job then job.Entry.Job = nil end
            if job.Entry.Removed or job.Entry.Job ~= job then table.remove(self.Jobs, 1) continue end
            local done = false
            for i = 1, 8 do
                done = self:Advance(job)
                steps += 1
                if done then break end
            end
            table.remove(self.Jobs, 1)
            if not done then table.insert(self.Jobs, job) end
        end
    end
    function Grenades:Stroke(entry, key, index, camera, a, b, color, alpha)
        local from, to = Skeleton:Project(camera, a, b)
        if not from then return end
        local pool = entry.Strokes[key]
        if not pool then pool = {} entry.Strokes[key] = pool end
        local pair = pool[index]
        if not pair then pair = { newDrawing(entry, "Line"), newDrawing(entry, "Line") } pool[index] = pair end
        if Settings.GrenadeOutline then line(pair[1], from, to, Settings.OutlineColor, Settings.GrenadeThickness + 2, alpha) end
        line(pair[2], from, to, color, Settings.GrenadeThickness, alpha)
    end
    function Grenades:Marker(entry, index, camera, position, color, alpha)
        local point, onScreen = camera:WorldToViewportPoint(position)
        if not onScreen or point.Z < 0.1 then return end
        local marker = entry.Markers[index]
        if not marker then marker = newDrawing(entry, "Square", { Filled = false }) entry.Markers[index] = marker end
        local size = Settings.GrenadeMarkerSize
        marker.Position, marker.Size = Vector2.new(point.X - size, point.Y - size), Vector2.new(size * 2, size * 2)
        marker.Color, marker.Transparency, marker.Thickness, marker.Visible = color, alpha, Settings.GrenadeThickness, true
    end
    function Grenades:Draw(entry, camera, now)
        hide(entry)
        local kind = kinds[entry.Name]
        if not kind or not Settings[kind[1]] or not entry.Position then return end
        if entry.Preview and not entry.Active or (entry.Position - camera.CFrame.Position).Magnitude > Settings.GrenadeMaxDistance then return end
        local color = entry.Preview and Settings.GrenadePreviewColor or Settings[kind[2]]
        local alpha = Settings.GrenadeOpacity / 100
        if entry.Preview == "Near" then color = color:Lerp(Color3.fromRGB(95, 180, 255), 0.5) end
        entry.Shown = true
        local forecast = entry.Forecast
        if forecast and (entry.Preview or Settings.GrenadePrediction) then
            local previous = not entry.Preview and entry.State and entry.State.position or forecast.Points[1].Position
            local currentTime = not entry.Preview and entry.State and entry.State.simulationTime or -math.huge
            for i, point in ipairs(forecast.Points) do
                if point.Time < currentTime then continue end
                self:Stroke(entry, "Prediction", i, camera, previous, point.Position, color, alpha)
                previous = point.Position
            end
            if Settings.GrenadeBounces then
                for i, point in ipairs(forecast.Bounces) do self:Marker(entry, i, camera, point, color, alpha) end
            end
            if Settings.GrenadeEndpoint then self:Marker(entry, 50, camera, forecast.EndPosition, color, alpha) end
        end
        if not entry.Preview and Settings.GrenadeTrails then
            for i = 2, #entry.History do
                local a, b = entry.History[i - 1], entry.History[i]
                local faded = alpha * math.clamp(1 - (now - b.Time) / Settings.GrenadeTrailTime, 0, 1)
                self:Stroke(entry, "History", i, camera, a.Position, b.Position, color, faded)
            end
            if Settings.GrenadeBounces then
                local index = 60
                for _, point in ipairs(entry.History) do
                    if point.Bounce then self:Marker(entry, index, camera, point.Position, color, alpha) index += 1 end
                end
            end
        end
        if Settings.GrenadeNames and not entry.Ended then
            local position = entry.Preview and forecast and forecast.EndPosition or entry.Position
            local point, onScreen = camera:WorldToViewportPoint(position)
            if onScreen and point.Z > 0.1 then
                if not entry.Label then entry.Label = newDrawing(entry, "Text", { Center = true }) end
                local label = entry.Name .. (entry.Preview and " | " .. entry.Preview .. " estimate" or "")
                text(entry.Label, label, point.X, point.Y + Settings.GrenadeMarkerSize + 3, color, alpha, camera.ViewportSize, Settings.WorldTextSize, Settings.GrenadeOutline)
            end
        end
    end
    function Grenades:Render(camera, now)
        if not self.Ready or not Settings.GrenadeEnabled or (Settings.HideWithMenu and Library.Toggled) then self:HideAll() return end
        for _, entry in pairs(self.Entries) do self:Draw(entry, camera, now) end
        for _, entry in pairs(self.Previews) do self:Draw(entry, camera, now) end
    end
    local ok, failure = pcall(function()
        Grenades.Storage = game:GetService("ReplicatedStorage")
        local module = require(Grenades.Storage.Shared.GrenadeSimulator)
        Grenades.GetVelocity = require(Grenades.Storage.Components.Common.GetCharacterVelocity)
        Grenades.Module, Grenades.Original, Grenades.Step = module, module.simulate, module.step
        Grenades.StepTime = module.Constants.FIXED_TIMESTEP
        assert(type(Grenades.Original) == "function" and type(Grenades.Step) == "function" and not table.isfrozen(module), "Grenade physics is unavailable")
        Grenades.Wrapper = function(initial, config, params, delta)
            local result = Grenades.Original(initial, config, params, delta)
            if State.Running and Grenades.Ready then
                local success, err = pcall(function() Grenades:Capture(result, config, params) end)
                if not success then Grenades.LastError = tostring(err) end
            end
            return result
        end
        module.simulate = Grenades.Wrapper
        Grenades.Ready = true
        connect(RunService.Heartbeat, function()
            local success, err = pcall(function() Grenades:Update(os.clock()) end)
            if not success then Grenades.LastError = tostring(err) Grenades:HideAll() end
        end)
    end)
    if not ok then Grenades.LastError = tostring(failure) Grenades:RestoreAll() end
end

local function renderWorld(camera, origin, now)
    syncWorld(now)
    local viewport = camera.ViewportSize
    local serverNow = workspace:GetServerTimeNow()
    local alpha, size = Settings.WorldOpacity / 100, Settings.WorldTextSize
    for model, entry in pairs(World.Entries) do
        hide(entry)
        if not model:IsDescendantOf(workspace) then removeWorldEntry(model) continue end
        local planted = CollectionService:HasTag(model, "Bomb")
        local dropped = CollectionService:HasTag(model, "WeaponDropped")
        if not planted and not dropped then removeWorldEntry(model) continue end
        local weapon = model:GetAttribute("Weapon")
        local bomb = planted or weapon == "C4"
        if planted and not Settings.PlantedBomb or not planted and bomb and not Settings.DroppedBomb
            or not bomb and not Settings.DroppedWeapons then continue end
        local part = model:IsA("BasePart") and model or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        if not part then continue end
        local distance = (origin - part.Position).Magnitude
        if distance > Settings.WorldMaxDistance then continue end
        local point, onScreen = camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 then continue end
        local label, color = weapon, Settings.DroppedWeaponColor
        if bomb then
            color = Settings.BombColor
            if planted then
                local status, remaining = bombStatus(entry, serverNow)
                if status == "Exploded" then continue end
                if status == "Defused" then
                    label, color = "C4 | DEFUSED", Settings.HealthHighColor
                elseif status == "Exploding" then
                    label, color = "C4 | EXPLODING", Settings.BombUrgentColor
                else
                    label = Settings.BombTimer and remaining and string.format("C4 | %.1fs", remaining) or "C4 | PLANTED"
                    if remaining and remaining <= Settings.BombWarningTime then color = Settings.BombUrgentColor end
                end
            else
                label = "C4 | DROPPED"
            end
        end
        if type(label) ~= "string" or label == "" then continue end
        entry.Shown = true
        entry.Kind = planted and "Planted bomb" or bomb and "Dropped bomb" or "Weapon"
        local lineHeight = size + 2
        local labelHeight = lineHeight * (Settings.WorldDistance and 2 or 1)
        local top = math.clamp(point.Y - labelHeight - 8, 1, math.max(1, viewport.Y - labelHeight - 3))
        text(entry.Label, label, point.X, top, color, alpha, viewport, size, Settings.WorldOutlines)
        if Settings.WorldDistance then
            text(entry.Distance, distanceText(distance), point.X, top + lineHeight,
                Settings.TextColor, alpha, viewport, size, Settings.WorldOutlines)
        end
        if Settings.WorldMarkers then
            local markerSize = Settings.WorldMarkerSize
            entry.Marker.Position = Vector2.new(point.X - markerSize * 0.5, point.Y - markerSize * 0.5)
            entry.Marker.Size = Vector2.new(markerSize, markerSize)
            entry.Marker.Color, entry.Marker.Transparency = color, alpha
            entry.Marker.Visible = true
        end
    end
end

local function renderEntry(entry, camera, origin, now)
    local player = entry.Player
    local character, health, maximum = matchCharacter(player)
    if not character then hide(entry) return end
    local allowed, teammate = teamAllowed(player)
    if not allowed then hide(entry) return end
    if entry.Character ~= character or now >= (entry.NextParts or 0) then bindCharacter(entry, character, now) end
    local root = entry.Root
    if not root or not root.Parent then hide(entry) return end
    local subject = camera.CameraSubject
    if subject and subject:IsDescendantOf(character) then hide(entry) return end
    local distance = (origin - root.Position).Magnitude
    if distance > Settings.MaxDistance or (camera.CFrame.Position - root.Position).Magnitude < 1 then hide(entry) return end
    local x1, y1, x2, y2 = projectedBox(entry, camera)
    if not x1 then hide(entry) return end
    if (Settings.VisibilityCheck or Settings.VisibleColor) and now >= entry.NextRay then
        entry.NextRay = now + 0.12
        local target = entry.Head and entry.Head.Parent and entry.Head.Position or root.Position
        local hit = workspace:Raycast(camera.CFrame.Position, target - camera.CFrame.Position, RayParams)
        entry.InSight = hit == nil or hit.Instance:IsDescendantOf(character)
    end
    if Settings.VisibilityCheck and not entry.InSight then hide(entry) return end
    hide(entry)
    entry.Shown = true
    local color = teammate and Settings.TeammateColor or Settings.EnemyColor
    if Settings.VisibleColor and entry.InSight then color = Settings.InSightColor end
    local alpha = Settings.Opacity / 100
    if Settings.DistanceFade then
        alpha = alpha * (1 - 0.85 * math.clamp((distance / Settings.MaxDistance - 0.7) / 0.3, 0, 1))
    end
    local width, height = x2 - x1, y2 - y1
    local midpoint = (x1 + x2) * 0.5
    if Settings.Boxes then
        if Settings.BoxFill then
            entry.Fill.Position, entry.Fill.Size = Vector2.new(x1, y1), Vector2.new(width, height)
            entry.Fill.Color, entry.Fill.Transparency = color, alpha * Settings.FillOpacity / 100
            entry.Fill.Visible = true
        end
        local segments
        if Settings.BoxStyle == "Corners" then
            local w, h = width * 0.25, height * 0.2
            segments = {
                {x1,y1,x1+w,y1}, {x1,y1,x1,y1+h}, {x2-w,y1,x2,y1}, {x2,y1,x2,y1+h},
                {x1,y2,x1+w,y2}, {x1,y2-h,x1,y2}, {x2-w,y2,x2,y2}, {x2,y2-h,x2,y2},
            }
        else
            segments = { {x1,y1,x2,y1}, {x2,y1,x2,y2}, {x2,y2,x1,y2}, {x1,y2,x1,y1} }
        end
        for i, segment in ipairs(segments) do
            local from, to = Vector2.new(segment[1], segment[2]), Vector2.new(segment[3], segment[4])
            if Settings.Outlines then line(entry.Borders[i], from, to, Settings.OutlineColor, Settings.Thickness + 2, alpha) end
            line(entry.Lines[i], from, to, color, Settings.Thickness, alpha)
        end
    end
    if Settings.Skeleton then Skeleton:Draw(entry, camera, color, alpha) end
    local fraction = math.clamp(health / maximum, 0, 1)
    if Settings.HealthBar and x1 >= 8 then
        local filled = math.max(1, math.floor(height * fraction))
        entry.HealthBack.Position, entry.HealthBack.Size = Vector2.new(x1 - 7, y1 - 1), Vector2.new(4, height + 2)
        entry.HealthBack.Color, entry.HealthBack.Transparency = Settings.OutlineColor, alpha
        entry.HealthBack.Visible = true
        entry.Health.Position, entry.Health.Size = Vector2.new(x1 - 6, y2 - filled), Vector2.new(2, filled)
        entry.Health.Color, entry.Health.Transparency = Settings.HealthLowColor:Lerp(Settings.HealthHighColor, fraction), alpha
        entry.Health.Visible = true
    end
    local viewport = camera.ViewportSize
    local weapon, hasBomb
    if Settings.HeldWeapon or Settings.BombCarrier then weapon, hasBomb = equipmentOf(entry) end
    local carrier = Settings.BombCarrier and hasBomb
    local both = Settings.Names and Settings.NameMode == "Both" and player.DisplayName ~= player.Name
    local nameRows = Settings.Names and (both and 2 or 1) or 0
    local nameTop = math.max(1, y1 - (nameRows + (carrier and 1 or 0)) * (Settings.TextSize + 2) - 3)
    if carrier then
        text(entry.Bomb, "BOMB", midpoint, nameTop, Settings.BombColor, alpha, viewport)
        nameTop = nameTop + Settings.TextSize + 2
    end
    if Settings.Names then
        local label = Settings.NameMode == "Username" and player.Name or player.DisplayName
        text(entry.Name, shortName(label), midpoint, nameTop, Settings.TextColor, alpha, viewport)
        if both then text(entry.Username, "@" .. shortName(player.Name), midpoint, nameTop + Settings.TextSize + 2, Settings.TextColor, alpha, viewport) end
    end
    local info = {}
    if Settings.HealthText then
        if Settings.HealthFormat == "Percent" then
            table.insert(info, tostring(math.floor(fraction * 100 + 0.5)) .. "% HP")
        elseif Settings.HealthFormat == "HP" then
            table.insert(info, tostring(math.ceil(health)) .. " HP")
        else
            table.insert(info, tostring(math.ceil(health)) .. "/" .. tostring(math.ceil(maximum)) .. " HP")
        end
    end
    if Settings.Distance then table.insert(info, distanceText(distance)) end
    local showWeapon = Settings.HeldWeapon and weapon ~= nil
    local bottomRows = (#info > 0 and 1 or 0) + (showWeapon and 1 or 0)
    local bottom = math.min(y2 + 3, viewport.Y - bottomRows * (Settings.TextSize + 2) - 3)
    if #info > 0 then
        text(entry.Info, table.concat(info, " | "), midpoint, bottom, Settings.TextColor, alpha, viewport)
        bottom = bottom + Settings.TextSize + 2
    end
    if showWeapon then
        text(entry.Weapon, weapon, midpoint, bottom, Settings.TextColor, alpha, viewport)
    end
    if Settings.Tracers then
        local from = Vector2.new(viewport.X * 0.5, Settings.TracerOrigin == "Top" and 2 or Settings.TracerOrigin == "Center" and viewport.Y * 0.5 or viewport.Y - 2)
        local to = Vector2.new(midpoint, y2)
        if Settings.Outlines then line(entry.TracerBorder, from, to, Settings.OutlineColor, Settings.Thickness + 2, alpha) end
        line(entry.Tracer, from, to, color, Settings.Thickness, alpha)
    end
end

local function render(now)
    local camera = workspace.CurrentCamera
    if not camera then hideAll() hideAim() if Grenades.HideAll then Grenades:HideAll() end return end
    State.LastCamera = camera.CFrame
    State.LastFOV = camera.FieldOfView
    local aimOK, aimError = pcall(updateAim, now, camera)
    if not aimOK then
        hideAim()
        Aim.Target = nil
        if not Aim.LastError then
            Aim.LastError = tostring(aimError)
            Settings.SilentEnabled = false
            Library.Toggles.SilentEnabled:SetValue(false)
            report("Silent aim paused: " .. tostring(aimError))
        end
    end
    if Grenades.Ready then
        local success, err = pcall(function() Grenades:Render(camera, now) end)
        if not success then Grenades.LastError = tostring(err) Grenades:HideAll() end
    end
    if not Settings.Enabled or (Settings.HideWithMenu and Library.Toggled) then hideAll() return end
    local own = LocalPlayer.Character
    local ownRoot = own and own:FindFirstChild("HumanoidRootPart")
    local ownHealth = own and healthOf(own)
    local spectating = LocalPlayer:GetAttribute("IsSpectating") == true
    local origin = not spectating and ownRoot and ownHealth and ownHealth > 0 and ownRoot.Position or camera.CFrame.Position
    local ignore = { camera }
    if own then table.insert(ignore, own) end
    if spectating and camera.CameraSubject then
        local viewedCharacter = camera.CameraSubject:FindFirstAncestorOfClass("Model")
        if viewedCharacter then table.insert(ignore, viewedCharacter) end
    end
    local debris = workspace:FindFirstChild("Debris")
    if debris then table.insert(ignore, debris) end
    RayParams.FilterDescendantsInstances = ignore
    for _, entry in pairs(State.Entries) do renderEntry(entry, camera, origin, now) end
    local worldOK, worldError = pcall(renderWorld, camera, origin, now)
    if not worldOK then
        for _, entry in pairs(World.Entries) do hide(entry) end
        if World.LastError ~= tostring(worldError) then
            World.LastError = tostring(worldError)
            report("World ESP: " .. World.LastError)
        end
    end
end

local function start()
    Library.ShowCustomCursor = false
    Library.IsMobile = Library.IsMobile or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
    Library.Scheme.BackgroundColor = Color3.fromRGB(16, 18, 24)
    Library.Scheme.MainColor = Color3.fromRGB(23, 27, 35)
    Library.Scheme.OutlineColor = Color3.fromRGB(47, 53, 66)
    Library.Scheme.AccentColor = Color3.fromRGB(116, 167, 255)
    local makeResizable = Library.MakeResizable
    Library.MakeResizable = function(_, frame, handle)
        State.ResizeHandle = handle
        local pointer, origin, initialSize, scale
        local function stop() pointer = nil end
        connect(handle.InputBegan, function(input)
            if pointer or not State.Running or not Library.Toggled then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
            pointer, origin, initialSize, scale = input, input.Position, frame.Size, Library.DPIScale or 1
        end)
        connect(UserInputService.InputChanged, function(input)
            if not pointer then return end
            if not State.Running or not Library.Toggled then stop() return end
            if pointer.UserInputType == Enum.UserInputType.Touch then
                if input ~= pointer then return end
            elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            if State.ResizeWindow then
                local delta = (input.Position - origin) / scale
                State:ResizeWindow(initialSize.X.Offset + delta.X, initialSize.Y.Offset + delta.Y)
            end
        end)
        connect(UserInputService.InputEnded, function(input)
            if input == pointer or (pointer and pointer.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then stop() end
        end)
        connect(UserInputService.WindowFocusReleased, stop)
        connect(frame:GetPropertyChangedSignal("Visible"), function() if not frame.Visible then stop() end end)
    end
    local window = Library:CreateWindow({
        Title = "BloxStrike", Footer = "BloxStrike | t.me/arceusxcommunity", Size = UDim2.fromOffset(Settings.UIWidth, Settings.UIHeight),
        Font = Enum.Font.Gotham, CornerRadius = 7, AutoShow = false, Center = true,
        ShowCustomCursor = false, ShowMobileButtons = true, DisableSearch = true,
        SidebarCompacted = false, MinSidebarWidth = 128, MinContainerWidth = 220,
        Resizable = true, ToggleKeybind = Enum.KeyCode.RightShift,
    })
    Library.MakeResizable = makeResizable
    local setCornerRadius = window.SetCornerRadius
    window.SetCornerRadius = function(self, radius)
        setCornerRadius(self, radius)
        State.ResizeHandle.Position = UDim2.fromScale(1, 1)
    end
    local footer = State.ResizeHandle.Parent:FindFirstChildWhichIsA("TextLabel")
    if footer then
        State.FooterLabel = footer
        footer.RichText = false
        footer.TextTruncate = Enum.TextTruncate.AtEnd
        footer.Position = UDim2.fromOffset(8, 0)
        footer.Size = UDim2.new(1, -40, 1, 0)
    end
    task.spawn(function()
        local ok, content = pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
        end)
        if not ok or type(content) ~= "string" or not State.Running or Library.Unloaded then return end
        content = content:gsub("%c", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
        local length = utf8.len(content)
        if not length or length == 0 then return end
        if length > 160 then content = content:sub(1, utf8.offset(content, 161) - 1) end
        window:SetFooter("BloxStrike | " .. content)
    end)
    Library:UpdateColorsUsingRegistry()
    local mainTab = window:AddTab("Main", "wrench", "Aim, weapons and movement")
    local espTab = window:AddTab("ESP", "scan-eye", "Players, dropped weapons and C4")
    local styleTab = window:AddTab("Style", "palette", "Colors and appearance")
    local grenadeTab = window:AddTab("Grenades", "route", "Trajectories, bounces and trails")
    local viewTab = window:AddTab("Viewmodel", "hand", "Hands, weapon appearance and camera")
    local skinTab = window:AddTab("Skins", "paintbrush", "Weapon finishes and preview")
    local animationTab = window:AddTab("Animations", "music", "Dances and Roblox catalog emotes")
    local environmentTab = window:AddTab("Environment", "sun", "Sky, lighting and color")
    local settingsTab = window:AddTab("UI Settings", "settings", "Menu, scaling and watermark")
    local profileTab = window:AddTab("Profiles", "folder-cog", "Themes and configurations")
    local tabs = { mainTab, espTab, styleTab, grenadeTab, viewTab, skinTab, animationTab, environmentTab, settingsTab, profileTab }
    State.MainTab, State.ESPTab, State.StyleTab, State.SettingsTab = mainTab, espTab, styleTab, settingsTab
    State.GrenadeTab = grenadeTab
    State.AntiAimTab = mainTab
    State.WorldTab = espTab
    State.WeaponTab = mainTab
    State.SkinTab = skinTab
    State.AnimationTab = animationTab
    State.MovementTab = mainTab
    State.EnvironmentTab, State.ViewTab = environmentTab, viewTab
    State.Tabs = tabs
    State.Window = window
    local groups = {}
    local controls = {}
    local function group(tab, name, side)
        local box = side == 2 and tab:AddRightGroupbox(name) or tab:AddLeftGroupbox(name)
        table.insert(groups, { Box = box, Tab = tab, Side = side })
        box.BoxHolder.LayoutOrder = #groups
        return box
    end
    local function register(key, control)
        controls[key] = control
        return control
    end
    local function updateInterface(key)
        if key:sub(1, 7) == "Trigger" and Trigger.Reset then Trigger:Reset() end
        if key:sub(1, 9) == "Animation" and Animations.Ready then Animations:Refresh() end
        if key:sub(1, 7) == "Grenade" and Grenades.Refresh then Grenades:Refresh() end
        if key:sub(1, 7) == "AntiAim" and AntiAim.Reset then AntiAim:Reset() end
        if Effects.Ready and key:sub(1, 7) == "Effects" then Effects:Refresh() end
        if Visuals.Ready and (key:sub(1, 5) == "Third" or key:sub(1, 3) == "Sky"
            or key:sub(1, 5) == "Light" or key:sub(1, 4) == "Tone" or key:sub(1, 5) == "Bloom" or key:sub(1, 4) == "View") then
            local success, err = pcall(function() Visuals:Refresh() end)
            if not success then Visuals.LastError = tostring(err) report("Visual settings: " .. tostring(err)) end
        end
        if key:sub(1, 8) == "BunnyHop" and BunnyHop.Reset then BunnyHop:Reset() end
        if State.UpdateUI and (key:sub(1, 2) == "UI" or key:sub(1, 9) == "Watermark") then State:UpdateUI(key) end
        if State.UpdateSpectators and key:sub(1, 9) == "Spectator" then State:UpdateSpectators() end
        if key:sub(1, 4) == "Skin" and State.UpdateSkins then State:UpdateSkins(key) end
        if key:sub(1, 6) == "Weapon" then
            Aim.Target, Aim.NextSelect = nil, 0
            if WeaponMods.RestoreRecoil then WeaponMods.RestoreRecoil() end
            if State.UpdateWeaponMods then State:UpdateWeaponMods() end
        end
    end
    local function toggle(box, key, label, tooltip)
        return register(key, box:AddToggle(key, {
            Text = label, Default = Settings[key], Tooltip = tooltip,
            Callback = function(value)
                Settings[key] = value
                if key == "Enabled" and not value then hideAll() end
                if key:sub(1, 6) == "Silent" then Aim.Target = nil Aim.NextSelect = 0 end
                if key == "TouchControls" and State.FitWindow then State:FitWindow() end
                updateInterface(key)
            end,
        }))
    end
    local function slider(box, key, label, minimum, maximum, decimals, suffix)
        return register(key, box:AddSlider(key, {
            Text = label, Default = Settings[key], Min = minimum, Max = maximum,
            Rounding = decimals or 0, Suffix = suffix or "", HideMax = true, Compact = false,
            Callback = function(value) Settings[key] = value Aim.NextSelect = 0 updateInterface(key) end,
        }))
    end
    local function dropdown(box, key, label, values, id)
        return register(key, box:AddDropdown(id or key, {
            Text = label, Default = Settings[key], Values = values, Multi = false,
            Callback = function(value) Settings[key] = value Aim.NextSelect = 0 updateInterface(key) end,
        }))
    end
    local function color(box, key, label)
        local id = key == "OutlineColor" and "ESPOutlineColor" or key
        box:AddLabel(label):AddColorPicker(id, {
            Title = label, Default = Settings[key], Callback = function(value) Settings[key] = value updateInterface(key) end,
        })
        controls[key] = Library.Options[id]
    end

    local targets = group(espTab, "Players", 1)
    toggle(targets, "Enabled", "Enable ESP")
    toggle(targets, "ShowEnemies", "Show enemies")
    toggle(targets, "TeamCheck", "Team check", "Hide teammates and show enemies only.")
    slider(targets, "MaxDistance", "Maximum distance", 50, 5000, 0, " studs")
    toggle(targets, "VisibilityCheck", "Visible only")
    toggle(targets, "VisibleColor", "Recolor visible players")

    local skeletonGroup = group(espTab, "Skeleton", 1)
    toggle(skeletonGroup, "Skeleton", "Show skeleton")
    toggle(skeletonGroup, "SkeletonTeamColor", "Use player colors")
    color(skeletonGroup, "SkeletonColor", "Custom color")
    slider(skeletonGroup, "SkeletonThickness", "Line thickness", 1, 4)
    toggle(skeletonGroup, "SkeletonOutline", "Skeleton outline")
    local information = group(espTab, "Information", 2)
    toggle(information, "Names", "Show names")
    dropdown(information, "NameMode", "Name display", { "Username", "Display name", "Both" })
    toggle(information, "HealthBar", "Health bar")
    toggle(information, "HealthText", "Health numbers")
    dropdown(information, "HealthFormat", "Health format", { "HP", "HP / Max", "Percent" })
    toggle(information, "Distance", "Show distance")
    dropdown(information, "DistanceUnit", "Distance unit", { "Studs", "Meters" })
    toggle(information, "HeldWeapon", "Held weapon")
    toggle(information, "BombCarrier", "Bomb carrier")

    local worldItems = group(espTab, "Dropped items and bomb", 1)
    toggle(worldItems, "DroppedWeapons", "Dropped weapons")
    toggle(worldItems, "DroppedBomb", "Dropped bomb")
    toggle(worldItems, "PlantedBomb", "Planted bomb")
    toggle(worldItems, "BombTimer", "Explosion timer")
    toggle(worldItems, "WorldDistance", "Item distance")
    slider(worldItems, "WorldMaxDistance", "Maximum distance", 50, 5000, 0, " studs")
    slider(worldItems, "BombWarningTime", "Bomb warning at", 3, 30, 0, " s")
    local worldStyle = group(espTab, "Item appearance", 2)
    slider(worldStyle, "WorldTextSize", "Text size", 10, 24)
    slider(worldStyle, "WorldOpacity", "Opacity", 10, 100, 0, "%")
    toggle(worldStyle, "WorldOutlines", "Text outline")
    toggle(worldStyle, "WorldMarkers", "Position markers")
    slider(worldStyle, "WorldMarkerSize", "Marker size", 3, 12, 0, " px")
    color(worldStyle, "DroppedWeaponColor", "Dropped weapons")
    color(worldStyle, "BombColor", "Bomb and carrier")
    color(worldStyle, "BombUrgentColor", "Bomb warning")

    installGrenades()
    local grenadeDisplay = group(grenadeTab, "Display", 1)
    toggle(grenadeDisplay, "GrenadeEnabled", "Enable grenade ESP")
    toggle(grenadeDisplay, "GrenadePreview", "Preview held grenade")
    dropdown(grenadeDisplay, "GrenadePreviewMode", "Throw preview", { "Auto", "Far", "Near", "Both" })
    toggle(grenadeDisplay, "GrenadePrediction", "Predict flying grenades")
    toggle(grenadeDisplay, "GrenadeTrails", "Grenade trails")
    toggle(grenadeDisplay, "GrenadeBounces", "Bounce markers")
    toggle(grenadeDisplay, "GrenadeEndpoint", "Endpoint marker")
    toggle(grenadeDisplay, "GrenadeNames", "Grenade names")
    local grenadeTypes = group(grenadeTab, "Grenade types", 2)
    for _, item in ipairs({ { "GrenadeHE", "HE grenade" }, { "GrenadeFlash", "Flashbang" }, { "GrenadeSmoke", "Smoke grenade" },
        { "GrenadeMolotov", "Molotov" }, { "GrenadeIncendiary", "Incendiary grenade" }, { "GrenadeDecoy", "Decoy grenade" } }) do
        toggle(grenadeTypes, item[1], item[2])
    end
    local grenadeTiming = group(grenadeTab, "Prediction and trails", 1)
    slider(grenadeTiming, "GrenadeMaxDistance", "Maximum distance", 50, 5000, 0, " studs")
    slider(grenadeTiming, "GrenadeHorizon", "Prediction length", 1, 10, 1, " s")
    slider(grenadeTiming, "GrenadeRefresh", "Prediction refresh", 2, 15, 0, " Hz")
    slider(grenadeTiming, "GrenadeTrailTime", "Trail duration", 0.5, 10, 1, " s")
    local grenadeStyle = group(grenadeTab, "Appearance", 2)
    slider(grenadeStyle, "GrenadeThickness", "Line thickness", 1, 4)
    slider(grenadeStyle, "GrenadeOpacity", "Opacity", 10, 100, 0, "%")
    slider(grenadeStyle, "GrenadeMarkerSize", "Marker size", 2, 8, 0, " px")
    toggle(grenadeStyle, "GrenadeOutline", "Outlines")
    for _, item in ipairs({ { "GrenadePreviewColor", "Throw preview" }, { "GrenadeHEColor", "HE grenade" }, { "GrenadeFlashColor", "Flashbang" },
        { "GrenadeSmokeColor", "Smoke grenade" }, { "GrenadeFireColor", "Fire grenades" }, { "GrenadeDecoyColor", "Decoy grenade" } }) do
        color(grenadeStyle, item[1], item[2])
    end
    if not Grenades.Ready then
        Library.Toggles.GrenadeEnabled:SetDisabled(true)
        report("Grenade visuals could not initialize: " .. tostring(Grenades.LastError))
    end
    local geometry = group(styleTab, "Drawing", 1)
    toggle(geometry, "Boxes", "Bounding boxes")
    dropdown(geometry, "BoxStyle", "Box style", { "Full", "Corners" })
    toggle(geometry, "BoxFill", "Fill boxes")
    slider(geometry, "FillOpacity", "Fill opacity", 0, 60, 0, "%")
    toggle(geometry, "Outlines", "Outlines")
    slider(geometry, "Thickness", "Line thickness", 1, 4)
    toggle(geometry, "Tracers", "Tracer lines")
    dropdown(geometry, "TracerOrigin", "Tracer origin", { "Bottom", "Center", "Top" })
    local colors = group(styleTab, "Colors", 2)
    color(colors, "EnemyColor", "Enemies")
    color(colors, "TeammateColor", "Teammates")
    color(colors, "InSightColor", "Visible players")
    color(colors, "TextColor", "Text")
    color(colors, "OutlineColor", "Outline")
    color(colors, "HealthLowColor", "Low health")
    color(colors, "HealthHighColor", "Full health")
    local lettering = group(styleTab, "Text and opacity", 2)
    slider(lettering, "TextSize", "Text size", 10, 24)
    dropdown(lettering, "TextFont", "Font", { "UI", "System", "Plex", "Monospace" })
    slider(lettering, "NameLength", "Name length", 8, 32)
    slider(lettering, "Opacity", "ESP opacity", 10, 100, 0, "%")
    toggle(lettering, "DistanceFade", "Fade with distance")
    local silentTargets = group(mainTab, "Silent Aim", 1)
    toggle(silentTargets, "SilentEnabled", "Enable silent aim")
    toggle(silentTargets, "SilentTeamCheck", "Team check")
    toggle(silentTargets, "SilentVisibleOnly", "Visible targets only")
    dropdown(silentTargets, "SilentTargetPart", "Aim part", { "Head", "Chest", "Closest", "Random" })
    dropdown(silentTargets, "SilentPriority", "Target priority", { "Crosshair", "Distance", "Health" })
    slider(silentTargets, "SilentMaxDistance", "Maximum distance", 50, 5000, 0, " studs")
    slider(silentTargets, "SilentHitChance", "Hit chance", 0, 100, 0, "%")
    slider(silentTargets, "SilentFOV", "FOV radius", 10, 800, 0, " px")
    slider(silentTargets, "SilentFOVThickness", "Circle thickness", 1, 4)
    slider(silentTargets, "SilentFOVOpacity", "Circle opacity", 10, 100, 0, "%")
    color(silentTargets, "SilentFOVColor", "Circle color")
    toggle(silentTargets, "SilentShowTarget", "Mark selected target")
    color(silentTargets, "SilentTargetColor", "Target color")
    local weaponControl = group(mainTab, "Weapon Mods", 2)
    toggle(weaponControl, "WeaponModsEnabled", "Enable weapon mods")
    toggle(weaponControl, "WeaponSpreadEnabled", "Modify spread")
    slider(weaponControl, "WeaponSpreadScale", "Spread amount", 0, 100, 0, "%")
    toggle(weaponControl, "WeaponRecoilEnabled", "Modify recoil")
    slider(weaponControl, "WeaponRecoilScale", "Recoil amount", 0, 100, 0, "%")
    toggle(weaponControl, "WeaponAutomatic", "Automatic fire")
    toggle(weaponControl, "WeaponWallbang", "Enable wallbang")
    slider(weaponControl, "WeaponPenetration", "Extra penetration", 0, 500, 0, " studs")
    slider(weaponControl, "WeaponWallbangSurfaces", "Maximum surfaces", 1, 32)
    toggle(weaponControl, "WeaponWallbangTargeting", "Silent Aim through cover", "Allow Silent Aim to select targets reachable through cover.")
    toggle(weaponControl, "WeaponKickEnabled", "Modify weapon shake")
    slider(weaponControl, "WeaponKickScale", "Shake amount", 0, 100, 0, "%")
    weaponControl:AddButton({ Text = "Reset weapon settings", Func = function()
        State:ApplySettings(Defaults, "Weapon")
    end })
    createAimDrawings()
    installSilent()
    installWeaponMods()
    if not WeaponMods.Ready then
        Library.Toggles.WeaponModsEnabled:SetDisabled(true)
        report("Weapon mods could not initialize: " .. tostring(WeaponMods.LastError))
    end
    if not Aim.Ready then
        Library.Toggles.SilentEnabled:SetDisabled(true)
        silentTargets:AddLabel("Silent aim is unavailable in this session.", true)
        report("Silent aim could not initialize: " .. tostring(Aim.LastError))
    end
    installTrigger()
    local triggerGroup = group(mainTab, "Trigger Bot", 2)
    toggle(triggerGroup, "TriggerEnabled", "Enable trigger bot"):AddKeyPicker("TriggerKey", {
        Default = "None", Mode = "Toggle", SyncToggleState = true, Text = "Trigger bot", NoUI = false,
    })
    dropdown(triggerGroup, "TriggerMode", "Target mode", { "Crosshair", "Silent Aim FOV", "Crosshair or FOV" })
    slider(triggerGroup, "TriggerDelay", "Reaction delay", 0, 500, 0, " ms")
    slider(triggerGroup, "TriggerInterval", "Minimum shot interval", 0, 1000, 0, " ms")
    slider(triggerGroup, "TriggerMaxDistance", "Maximum distance", 50, 5000, 0, " studs")
    toggle(triggerGroup, "TriggerScopedOnly", "Only while scoped")
    if not Trigger.Ready then
        Library.Toggles.TriggerEnabled:SetDisabled(true)
        report("Trigger bot could not initialize: " .. tostring(Trigger.LastError))
    end
    installBunnyHop()
    installAntiAim()
    local antiMain = group(mainTab, "Anti-Aim", 1)
    toggle(antiMain, "AntiAimEnabled", "Enable anti-aim"):AddKeyPicker("AntiAimKey", {
        Default = "None", Mode = "Toggle", SyncToggleState = true, Text = "Anti-aim", NoUI = false,
    })
    dropdown(antiMain, "AntiAimMode", "Mode", { "Static", "Jitter", "Spin", "Random" })
    dropdown(antiMain, "AntiAimBase", "Yaw base", { "Camera", "World" })
    slider(antiMain, "AntiAimYaw", "Yaw offset", -180, 180, 0, " deg")
    slider(antiMain, "AntiAimJitter", "Jitter angle", 0, 180, 0, " deg")
    slider(antiMain, "AntiAimInterval", "Jitter / random interval", 20, 1000, 0, " ms")
    slider(antiMain, "AntiAimRandomRange", "Random angle range", 0, 180, 0, " deg")
    slider(antiMain, "AntiAimSpinSpeed", "Spin speed", 30, 1440, 0, " deg/s")
    dropdown(antiMain, "AntiAimSpinDirection", "Spin direction", { "Clockwise", "Counterclockwise" })
    dropdown(antiMain, "AntiAimPitch", "Pitch mode", { "Camera", "Up", "Down", "Level", "Custom", "Jitter" })
    slider(antiMain, "AntiAimPitchAngle", "Custom pitch angle", -89, 89, 0, " deg")
    toggle(antiMain, "AntiAimPauseOnFire", "Pause while firing")
    toggle(antiMain, "AntiAimPauseScoped", "Pause while aiming")
    toggle(antiMain, "AntiAimPauseWithMenu", "Pause with menu")
    if not AntiAim.Ready then
        Library.Toggles.AntiAimEnabled:SetDisabled(true)
        report("Anti-aim could not initialize: " .. tostring(AntiAim.LastError))
    end
    local hopping = group(mainTab, "Bunny Hop", 2)
    toggle(hopping, "BunnyHopEnabled", "Enable bunny hop")
    dropdown(hopping, "BunnyHopMode", "Activation", { "Hold jump", "Automatic" })
    toggle(hopping, "BunnyHopMovingOnly", "Only while moving")
    slider(hopping, "BunnyHopDelay", "Jump delay", 0, 250, 0, " ms")
    toggle(hopping, "BunnyHopPauseWithMenu", "Pause with menu")
    hopping:AddLabel("Hold jump uses your current jump button. Automatic also works with touch controls.", true)
    hopping:AddButton({ Text = "Reset movement settings", Func = function()
        State:ApplySettings(Defaults, "BunnyHop")
    end })
    if not BunnyHop.Ready then
        Library.Toggles.BunnyHopEnabled:SetDisabled(true)
        report("Bunny hop could not initialize: " .. tostring(BunnyHop.LastError))
    end
    installSkinChanger()
    local skinSelection = group(skinTab, "Skin changer", 1)
    toggle(skinSelection, "SkinEnabled", "Enable skin changer", "Changes the appearance of your weapon on this client.")
    SkinChanger.WeaponControl = register("SkinWeapon", skinSelection:AddDropdown("SkinWeapon", {
        Text = "Weapon", Values = SkinChanger.Weapons, Default = Settings.SkinWeapon, Searchable = true,
        Callback = function(value)
            if not value or SkinChanger.Syncing then return end
            Settings.SkinWeapon = value
            if State.UpdateSkins then State:UpdateSkins("SkinWeapon") end
        end,
    }))
    local knifeValues = table.clone(SkinChanger.Knives)
    table.insert(knifeValues, 1, "Original")
    SkinChanger.KnifeControl = register("SkinKnifeModel", skinSelection:AddDropdown("SkinKnifeModel", {
        Text = "Knife model", Values = knifeValues, Default = "Original", Searchable = true, Visible = false,
        Callback = function(value)
            if SkinChanger.Syncing or not SkinChanger.FinishControl or not SkinChanger.Ready then return end
            if value == "Original" then SkinChanger.Loadout.Knife = nil
            elseif SkinChanger.KnifeSet[value] then
                local finishes = SkinChanger.Catalog[value]
                local finish = finishes.Stock and "Stock" or next(finishes)
                SkinChanger.Loadout.Knife = { Weapon = value, Skin = finish, Float = 0 }
            else return end
            SkinChanger:Store()
            SkinChanger:RefreshEditor()
        end,
    }))
    local function storeSkinSelection()
        if SkinChanger.Syncing or not SkinChanger.Ready or not SkinChanger.FinishControl or not SkinChanger.WearControl then return end
        local name = Settings.SkinWeapon
        local weapon = name == "Knife" and SkinChanger.KnifeControl.Value or name
        local finish = SkinChanger.FinishControl.Value
        if finish == "Original" then SkinChanger.Loadout[name] = nil
        elseif SkinChanger.Catalog[weapon] and SkinChanger.Catalog[weapon][finish] then
            SkinChanger.Loadout[name] = { Skin = finish, Float = SkinChanger.WearControl.Value, Weapon = name == "Knife" and weapon or nil }
        else return end
        SkinChanger:Store()
        SkinChanger:RefreshPreview()
    end
    SkinChanger.FinishControl = register("SkinFinish", skinSelection:AddDropdown("SkinFinish", {
        Text = "Skin", Values = { "Original" }, Default = "Original", Searchable = true,
        Callback = storeSkinSelection,
    }))
    SkinChanger.WearControl = register("SkinWear", skinSelection:AddSlider("SkinWear", {
        Text = "Wear float", Min = 0, Max = 1, Default = 0, Rounding = 4, HideMax = true,
        Callback = storeSkinSelection,
    }))
    skinSelection:AddButton({ Text = "Use held weapon", Func = function()
        local weapon = SkinChanger.GetWeapon and SkinChanger.GetWeapon()
        local view = weapon and weapon.Viewmodel
        local name = view and (view.CameraModelWeapon or view.Weapon) or weapon and weapon.Name
        if name and SkinChanger.Catalog[name] then SkinChanger.WeaponControl:SetValue(SkinChanger.KnifeSet[name] and "Knife" or name)
        else report("Equip a weapon with available skins.") end
    end })
    skinSelection:AddButton({ Text = "Reset this weapon", Func = function()
        if Settings.SkinWeapon == "Knife" then SkinChanger.KnifeControl:SetValue("Original")
        else SkinChanger.FinishControl:SetValue("Original") end
    end })
    skinSelection:AddButton({ Text = "Reset all skins", Func = function()
        if not SkinChanger.Ready then return end
        table.clear(SkinChanger.Loadout)
        SkinChanger:Store()
        SkinChanger:RefreshEditor()
    end })
    local skinPreview = group(skinTab, "Selected skin", 2)
    SkinChanger.Preview = skinPreview:AddImage("SkinImage", {
        Image = "image", Height = Settings.SkinPreviewHeight, ScaleType = Enum.ScaleType.Fit, BackgroundTransparency = 1,
    })
    SkinChanger.PreviewLabel = skinPreview:AddLabel("Select a finish to preview.", true)
    SkinChanger.PreviewImage = SkinChanger.Preview.Holder:FindFirstChildWhichIsA("ImageLabel", true)
    if SkinChanger.PreviewImage then SkinChanger.PreviewImage.ZIndex = 3 end
    local skinAppearance = group(skinTab, "Preview settings", 2)
    toggle(skinAppearance, "SkinPreview", "Show skin image")
    slider(skinAppearance, "SkinPreviewHeight", "Image height", 120, 280, 0, " px")
    function SkinChanger:RefreshPreview()
        if not self.FinishControl or not self.Preview then return end
        local selected = self.Loadout[Settings.SkinWeapon]
        local name = Settings.SkinWeapon == "Knife" and selected and selected.Weapon or Settings.SkinWeapon
        local info = selected and self.Catalog[name] and self.Catalog[name][selected.Skin]
        local image = info and self.Library.GetItemIconImage(info, { Name = name, Float = selected.Float }) or ""
        if type(image) ~= "string" or image == "" then image = "image" end
        self.Preview:SetImage(image)
        self.Preview:SetRectOffset(self.Preview.RectOffset or Vector2.zero)
        self.Preview:SetRectSize(self.Preview.RectSize or Vector2.zero)
        self.Preview:SetVisible(Settings.SkinPreview)
        self.Preview:SetHeight(Settings.SkinPreviewHeight)
        self.WearControl:SetDisabled(not info)
        if info then
            local _, wear = self.Library.GetWearNameForFloat(info, selected.Float)
            self.PreviewLabel:SetText(name .. " | " .. selected.Skin .. "\n" .. tostring(wear) .. " | " .. tostring(info.rarity or "Stock"))
        else
            self.PreviewLabel:SetText("Select a finish to preview.")
        end
    end
    function SkinChanger:RefreshEditor()
        if not self.FinishControl then return end
        self.Syncing = true
        local name = Settings.SkinWeapon
        local knife = name == "Knife"
        if not knife and not self.Catalog[name] and #self.Weapons > 0 then
            name = self.Weapons[1]
            Settings.SkinWeapon = name
            self.WeaponControl:SetValue(name)
        end
        local selected = self.Loadout[name]
        self.KnifeControl:SetVisible(knife)
        self.KnifeControl:SetValue(knife and selected and selected.Weapon or "Original")
        local weapon = knife and selected and selected.Weapon or name
        local values = {}
        for finish in pairs(self.Catalog[weapon] or {}) do table.insert(values, finish) end
        table.sort(values)
        if not knife or not selected then table.insert(values, 1, "Original") end
        self.FinishControl:SetValues(values)
        self.FinishControl:SetValue(selected and selected.Skin or "Original")
        self.WearControl:SetValue(selected and selected.Float or 0)
        self.Syncing = false
        self:RefreshPreview()
    end
    SkinChanger.LoadoutControl = register("SkinLoadout", {
        Type = "Input", Value = Settings.SkinLoadout,
        SetValue = function(_, value) if SkinChanger.Ready then SkinChanger:Import(value) end end,
    })
    Library.Options.SkinLoadout = SkinChanger.LoadoutControl
    if SkinChanger.Ready then SkinChanger:RefreshEditor()
    else
        Library.Toggles.SkinEnabled:SetDisabled(true)
        report("Skin changer could not initialize: " .. tostring(SkinChanger.LastError))
    end
    installVisuals()
    installEffects()
    installAnimations()
    local playback = group(animationTab, "Playback", 1)
    register("AnimationAsset", playback:AddInput("AnimationAsset", {
        Text = "Animation ID or catalog URL", Default = Settings.AnimationAsset, Finished = true,
        Callback = function(value) Settings.AnimationAsset = value end,
    }))
    Animations.PlayButton = playback:AddButton({ Text = "Play animation", Disabled = not Animations.Ready, Func = function() Animations:Play() end })
    Animations.StopButton = playback:AddButton({ Text = "Stop animation", Func = function() Animations:Stop() end })
    Animations.StatusLabel = playback:AddLabel(Animations.Ready and "Stopped" or "Animations are unavailable.", true)
    local animationSettings = group(animationTab, "Playback settings", 1)
    slider(animationSettings, "AnimationSpeed", "Playback speed", 0.25, 3, 2, "x")
    toggle(animationSettings, "AnimationLoop", "Loop animation")
    toggle(animationSettings, "AnimationStopMoving", "Stop on movement")
    toggle(animationSettings, "AnimationStopAction", "Stop on weapon action")
    local catalog = group(animationTab, "Roblox catalog", 2)
    register("AnimationQuery", catalog:AddInput("AnimationQuery", {
        Text = "Search emotes", Default = Settings.AnimationQuery, Finished = true,
        Callback = function(value) Settings.AnimationQuery = value end,
    }))
    catalog:AddButton({ Text = "Search catalog", Func = function() Animations:Search(false) end })
    Animations.ResultControl = catalog:AddDropdown("AnimationResult", {
        Text = "Catalog emote", Default = "Take The L", Values = Animations.Values, Searchable = true,
        Callback = function(value)
            local id = Animations.Results[value]
            if id then controls.AnimationAsset:SetValue(id) end
        end,
    })
    Animations.MoreButton = catalog:AddButton({ Text = "Load more", Disabled = true, Func = function() Animations:Search(true) end })
    Animations.CatalogLabel = catalog:AddLabel("Take The L is ready to select.", true)
    local thirdPerson = group(viewTab, "Third person", 2)
    toggle(thirdPerson, "ThirdPersonEnabled", "Enable third person"):AddKeyPicker("ThirdPersonKey", {
        Default = "None", Mode = "Toggle", SyncToggleState = true, Text = "Third person", NoUI = false,
    })
    slider(thirdPerson, "ThirdPersonDistance", "Camera distance", 2, 20, 1, " studs")
    toggle(thirdPerson, "ThirdPersonScoped", "First person while aiming")
    local removalGroup = group(environmentTab, "Effects", 1)
    toggle(removalGroup, "EffectsNoFlash", "No flash")
    toggle(removalGroup, "EffectsNoSmoke", "Remove smoke")
    local skyGroup = group(environmentTab, "Skybox", 1)
    toggle(skyGroup, "SkyEnabled", "Override skybox")
    local skyNames = { "Current", "Custom" }
    local sortedSkies = {}
    for name in pairs(Visuals.SkyPresets) do table.insert(sortedSkies, name) end
    table.sort(sortedSkies)
    for _, name in ipairs(sortedSkies) do table.insert(skyNames, name) end
    dropdown(skyGroup, "SkyPreset", "Sky preset", skyNames)
    slider(skyGroup, "SkyRotation", "Sky rotation", 0, 360, 0, " deg")
    slider(skyGroup, "SkyStars", "Star count", 0, 10000, 0)
    toggle(skyGroup, "SkyCelestial", "Sun and moon")
    local customSky = group(environmentTab, "Custom sky textures", 1)
    for _, face in ipairs({ { "SkyBack", "Back" }, { "SkyDown", "Bottom" }, { "SkyFront", "Front" }, { "SkyLeft", "Left" }, { "SkyRight", "Right" }, { "SkyUp", "Top" } }) do
        local key = face[1]
        register(key, customSky:AddInput(key, {
            Text = face[2], Default = Settings[key], Placeholder = "Asset ID", Finished = true,
            Callback = function(value) Settings[key] = value updateInterface(key) end,
        }))
    end
    local lightGroup = group(environmentTab, "Lighting", 2)
    toggle(lightGroup, "LightEnabled", "Override lighting")
    slider(lightGroup, "LightTime", "Time of day", 0, 24, 2)
    slider(lightGroup, "LightBrightness", "Brightness", 0, 10, 2)
    slider(lightGroup, "LightExposure", "Exposure", -3, 3, 2)
    color(lightGroup, "LightAmbient", "Ambient color")
    color(lightGroup, "LightOutdoor", "Outdoor ambient")
    toggle(lightGroup, "LightShadows", "Global shadows")
    local fogGroup = group(environmentTab, "Fog", 2)
    toggle(fogGroup, "LightNoFog", "Remove fog and haze")
    color(fogGroup, "LightFogColor", "Fog color")
    slider(fogGroup, "LightFogStart", "Fog start", 0, 10000, 0, " studs")
    slider(fogGroup, "LightFogEnd", "Fog end", 1, 10000, 0, " studs")
    local toneGroup = group(environmentTab, "Color correction", 1)
    toggle(toneGroup, "ToneEnabled", "Enable color correction")
    color(toneGroup, "ToneTint", "Screen tint")
    slider(toneGroup, "ToneSaturation", "Saturation", -1, 1, 2)
    slider(toneGroup, "ToneContrast", "Contrast", -1, 1, 2)
    local bloomGroup = group(environmentTab, "Bloom", 2)
    toggle(bloomGroup, "BloomEnabled", "Enable bloom")
    slider(bloomGroup, "BloomIntensity", "Intensity", 0, 3, 2)
    slider(bloomGroup, "BloomSize", "Size", 0, 56, 0)
    slider(bloomGroup, "BloomThreshold", "Threshold", 0, 5, 2)
    local materialNames = { "Original", "Neon", "SmoothPlastic", "Glass", "Metal", "ForceField" }
    for index, name in ipairs({ "Arms", "Weapon" }) do
        local box = group(viewTab, name == "Arms" and "Hands and sleeves" or "Weapon appearance", index)
        local prefix = "View" .. name
        toggle(box, prefix .. "Enabled", name == "Arms" and "Customize hands" or "Customize weapon")
        color(box, prefix .. "Color", "Color")
        dropdown(box, prefix .. "Material", "Material", materialNames)
        toggle(box, prefix .. "Rainbow", "Rainbow color")
    end
    local viewEffects = group(viewTab, "Viewmodel appearance", 1)
    toggle(viewEffects, "ViewSolidColor", "Use solid colors", "Temporarily hides textures on customized parts.")
    slider(viewEffects, "ViewRainbowSpeed", "Rainbow speed", 0.05, 2, 2)
    local positionGroup = group(viewTab, "Viewmodel position", 2)
    toggle(positionGroup, "ViewPositionEnabled", "Custom viewmodel position")
    toggle(positionGroup, "ViewPositionScoped", "Default position while aiming")
    slider(positionGroup, "ViewX", "Horizontal offset", -2, 2, 2, " studs")
    slider(positionGroup, "ViewY", "Vertical offset", -2, 2, 2, " studs")
    slider(positionGroup, "ViewZ", "Depth offset", -2, 2, 2, " studs")
    slider(positionGroup, "ViewPitch", "Pitch", -45, 45, 0, " deg")
    slider(positionGroup, "ViewYaw", "Yaw", -45, 45, 0, " deg")
    slider(positionGroup, "ViewRoll", "Roll", -90, 90, 0, " deg")
    positionGroup:AddButton({ Text = "Reset viewmodel settings", Func = function()
        State:ApplySettings(Defaults, "View")
    end })
    if not Visuals.Ready then
        controls.ThirdPersonEnabled:SetDisabled(true)
        report("Visual controls could not initialize: " .. tostring(Visuals.LastError))
    end
    local windowSettings = group(settingsTab, "Window size", 1)
    slider(windowSettings, "UIWidth", "Window width", 320, 1600, 0, " px")
    slider(windowSettings, "UIHeight", "Window height", 240, 1200, 0, " px")
    slider(windowSettings, "UIScale", "UI scale", 50, 200, 0, "%")
    windowSettings:AddButton({ Text = "Reset window size", Func = function()
        controls.UIWidth:SetValue(Defaults.UIWidth)
        controls.UIHeight:SetValue(Defaults.UIHeight)
        controls.UIScale:SetValue(Defaults.UIScale)
        if State.FitWindow then State:FitWindow(nil, true) end
    end })
    local performance = group(settingsTab, "Controls", 1)
    slider(performance, "RefreshRate", "ESP refresh rate", 15, 144, 0, " FPS")
    toggle(performance, "HideWithMenu", "Hide ESP with menu")
    toggle(performance, "TouchControls", "Large touch controls")
    toggle(performance, "UICursor", "Custom cursor")
    toggle(performance, "UIKeybindMenu", "Keybind menu")
    dropdown(performance, "UINotificationSide", "Notifications", { "Left", "Right" })
    local fonts = {}
    for _, font in ipairs(Enum.Font:GetEnumItems()) do if font.Name ~= "Unknown" then table.insert(fonts, font.Name) end end
    dropdown(performance, "UIFont", "Interface font", fonts, "FontFace")
    performance:AddLabel("Menu key"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu key" })
    Library.ToggleKeybind = Library.Options.MenuKeybind
    performance:AddButton({ Text = "Hide menu", Func = function() Library:Toggle(false) end })
    performance:AddButton({ Text = "Unload script", Func = function() State:Unload() end })
    performance:AddLabel("Scale adapts to the available screen size.", true)

    local watermark = Library:SetupWatermark({ ShowWatermark = false, ScriptName = "BloxStrike" })
    State.Watermark = watermark
    local watermarkGroup = group(settingsTab, "Watermark", 2)
    toggle(watermarkGroup, "WatermarkVisible", "Show watermark")
    toggle(watermarkGroup, "WatermarkName", "Show player name")
    toggle(watermarkGroup, "WatermarkFPS", "Show FPS")
    toggle(watermarkGroup, "WatermarkPing", "Show ping")
    register("WatermarkText", watermarkGroup:AddInput("WatermarkText", {
        Text = "Watermark text", Default = Settings.WatermarkText, Finished = true,
        Callback = function(value) Settings.WatermarkText = value updateInterface("WatermarkText") end,
    }))
    color(watermarkGroup, "WatermarkTextColor", "Text color")
    color(watermarkGroup, "WatermarkBgColor", "Background color")
    slider(watermarkGroup, "WatermarkTransparency", "Background transparency", 0, 100, 0, "%")
    local spectatorGroup = group(settingsTab, "Spectators", 2)
    toggle(spectatorGroup, "SpectatorList", "Show spectator list")
    toggle(spectatorGroup, "SpectatorCounter", "Show watcher count")
    toggle(spectatorGroup, "SpectatorHideEmpty", "Hide when empty")
    dropdown(spectatorGroup, "SpectatorNameMode", "Name display", { "Username", "Display name", "Both" })
    slider(spectatorGroup, "SpectatorWidth", "List width", 180, 400, 0, " px")
    slider(spectatorGroup, "SpectatorRows", "Visible rows", 3, 15)
    slider(spectatorGroup, "SpectatorTextSize", "Text size", 11, 20)
    spectatorGroup:AddButton({ Text = "Reset list position", Func = function() if State.FitSpectators then State:FitSpectators(true) end end })
    createSpectatorList()
    function State:UpdateUI(key)
        if not key or key == "UICursor" then Library.ShowCustomCursor = Settings.UICursor end
        if not key or key == "UIKeybindMenu" then Library.KeybindFrame.Visible = Settings.UIKeybindMenu end
        if not key or key == "UINotificationSide" then Library:SetNotifySide(Settings.UINotificationSide) end
        if not key or key == "UIFont" then Library:SetFont(Enum.Font[Settings.UIFont]) end
        if not key or key:sub(1, 9) == "Watermark" then
            watermark:SetVisible(Settings.WatermarkVisible)
            watermark:ShowName(Settings.WatermarkName)
            watermark:ShowFPS(Settings.WatermarkFPS)
            watermark:ShowPing(Settings.WatermarkPing)
            watermark:SetScriptName(Settings.WatermarkText ~= "" and Settings.WatermarkText or "BloxStrike")
            watermark:SetTextColor(Settings.WatermarkTextColor)
            watermark:SetBackgroundColor(Settings.WatermarkBgColor)
            watermark:SetBackgroundTransparency(Settings.WatermarkTransparency / 100)
        end
        if self.FitWindow and not self.ResizingWindow and (not key or key == "UIScale" or key == "UIFont" or key == "UIWidth" or key == "UIHeight") then self:FitWindow() end
    end

    local profiles = group(profileTab, "Quick actions", 2)
    local storage = type(writefile) == "function" and type(readfile) == "function"
    function State:ApplySettings(values, prefix)
        if type(values) ~= "table" then return end
        for key, default in pairs(Defaults) do
            local value, control = values[key], controls[key]
            if control and value ~= nil and (not prefix or key:sub(1, #prefix) == prefix) then
                if typeof(default) == "Color3" then
                    if typeof(value) == "Color3" then
                        control:SetValueRGB(value)
                    elseif type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" and type(value[3]) == "number" then
                        control:SetValueRGB(Color3.new(math.clamp(value[1], 0, 1), math.clamp(value[2], 0, 1), math.clamp(value[3], 0, 1)))
                    end
                elseif type(value) == type(default) then
                    if control.Type == "Dropdown" then
                        if table.find(control.Values, value) then control:SetValue(value) end
                    elseif type(value) ~= "number" or (value == value and math.abs(value) < math.huge) then
                        control:SetValue(value)
                    end
                end
            end
        end
    end
    profiles:AddButton({ Text = "Import old profile", Disabled = not storage, Func = function()
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(ConfigPath)) end)
        if ok and type(data) == "table" and data.Version == 1 and type(data.Settings) == "table" then
            State:ApplySettings(data.Settings)
            report("Settings loaded.")
        else
            report("No valid saved profile was found.")
        end
    end })
    profiles:AddButton({ Text = "Reset settings", Func = function() State:ApplySettings(Defaults) end })
    profiles:AddLabel(storage and "Profiles are saved on this device." or "This executor does not provide file storage.", true)
    State.Controls = controls

    local function loadAddon(name)
        local addonSource = game:HttpGet(Repository .. "addons/" .. name .. ".lua")
        addonSource = addonSource:gsub('Folder = "Obsidian"', 'Folder = "BloxStrike"')
        if name == "SaveManager" then
            addonSource = addonSource:gsub("task%.spawn%(self%.Parser%[option%.type%]%.Load, option%.idx, option%)", "self.Parser[option.type].Load(option.idx, option)")
        end
        return assert(loadstring(addonSource))()
    end
    local addonsOK, addonsError = pcall(function()
        assert(storage and type(isfolder) == "function" and type(makefolder) == "function"
            and type(listfiles) == "function" and type(isfile) == "function", "File storage is unavailable")
        local themes, saves = loadAddon("ThemeManager"), loadAddon("SaveManager")
        State.ThemeManager, State.SaveManager = themes, saves
        themes:SetLibrary(Library)
        themes:SetFolder("BloxStrike")
        themes.BuiltInThemes.BloxStrike = { 0, {
            BackgroundColor = "101218", MainColor = "171B23", OutlineColor = "2F3542",
            AccentColor = "74A7FF", FontColor = "F2F4FA", FontFace = "Gotham",
        } }
        themes.DefaultTheme = "BloxStrike"
        themes:ApplyToGroupbox(group(profileTab, "Themes", 1))
        saves:SetLibrary(Library)
        saves:SetThemeManager(themes)
        saves:IgnoreThemeSettings()
        saves:SetFolder("BloxStrike")
        saves:SetSubFolder(tostring(game.PlaceId))
        saves:SetIgnoreIndexes({ "ThemeManager_CustomThemeName", "ThemeManager_CustomThemeList", "ThemeManager_ImportThemeData", "SaveManager_ImportData", "SkinFinish", "SkinWear", "SkinKnifeModel", "AnimationResult" })
        saves.Load = function(self, name)
            local ok, data = self:ExportConfig(name)
            if not ok then return false, data end
            return self:ImportConfig(data)
        end
        saves:BuildConfigSection({ AddRightGroupbox = function(_, name) return group(profileTab, name, 2) end })
    end)
    if not addonsOK then
        State.AddonError = tostring(addonsError)
        profiles:AddLabel("Theme and config tools are unavailable in this executor.", true)
        report("Interface addons: " .. State.AddonError)
    end
    State:UpdateUI()

    local main = Library.ScreenGui:FindFirstChild("Main")
    assert(main, "Obsidian window was not created")
    State.Main = main
    local menus = {}
    local function closeMenus()
        for _, menu in ipairs(menus) do if menu.Active then menu:Close() end end
    end
    for _, control in pairs(Library.Options) do
        for _, field in ipairs({ "Menu", "ColorMenu", "ContextMenu" }) do
            local menu = control[field]
            if menu and menu.Open and menu.Menu then
                table.insert(menus, menu)
                local object = menu.Menu
                local open = menu.Open
                local automaticSize = object.AutomaticSize
                local fitting = false
                local function fitMenu()
                    if fitting or not menu.Active or not State.Running then return end
                    fitting = true
                    local size = State.AvailableSize or Library.ScreenGui.AbsoluteSize
                    local width, height = math.min(object.AbsoluteSize.X, size.X - 16), math.min(object.AbsoluteSize.Y, size.Y - 16)
                    if object:IsA("ScrollingFrame") and object.AbsoluteSize.Y > height then
                        object.AutomaticSize = Enum.AutomaticSize.None
                        object.AutomaticCanvasSize = Enum.AutomaticSize.Y
                        object.ScrollBarThickness = 4
                        local scale = Library.DPIScale or 1
                        object.Size = UDim2.fromOffset(width / scale, height / scale)
                    end
                    local x = math.clamp(object.Position.X.Offset, 8, math.max(8, size.X - width - 8))
                    local y = object.Position.Y.Offset
                    if y + height > size.Y - 8 then y = menu.Holder.AbsolutePosition.Y - height - 4 end
                    y = math.clamp(y, 8, math.max(8, size.Y - height - 8))
                    object.Position = UDim2.fromOffset(x, y)
                    fitting = false
                end
                menu.Open = function(self)
                    object.AutomaticSize = automaticSize
                    open(self)
                    task.defer(fitMenu)
                end
                connect(object:GetPropertyChangedSignal("AbsoluteSize"), fitMenu)
            end
        end
        if control.Type == "Dropdown" then
            local recalculate = control.RecalculateListSize
            control.RecalculateListSize = function(self, count)
                recalculate(self, count)
                local rowHeight = Settings.TouchControls and 44 / math.min(1, Library.DPIScale or 1) or 25
                for _, row in ipairs(self.Menu.Menu:GetChildren()) do
                    if row:IsA("Frame") then
                        row.Size = UDim2.new(1, 0, 0, rowHeight)
                        for _, button in ipairs(row:GetChildren()) do
                            if button:IsA("TextButton") then button.Size = UDim2.fromScale(1, 1) end
                        end
                    end
                end
                local holder = self.Holder
                self.Menu:SetSize(function()
                    return UDim2.fromOffset(holder.AbsoluteSize.X / (Library.DPIScale or 1) + 1, math.min(count or #self.Values, 6) * rowHeight)
                end)
            end
        end
    end
    local narrow = false
    local function layoutTabs()
        for _, info in ipairs(groups) do
            info.Box.BoxHolder.Parent = info.Tab.Sides[narrow and 1 or info.Side]
        end
        for _, tab in ipairs(tabs) do tab:RefreshSides() end
    end
    for _, tab in ipairs(tabs) do
        local originalShow = tab.Show
        tab.Show = function(self) closeMenus() originalShow(self) end
        for _, side in ipairs(tab.Sides) do
            connect(side:GetPropertyChangedSignal("CanvasPosition"), closeMenus)
        end
        local originalRefresh = tab.RefreshSides
        tab.RefreshSides = function(self)
            originalRefresh(self)
            self.Sides[2].Visible = not narrow
            if narrow then self.Sides[1].Size = UDim2.new(1, 0, 1, 0) end
            for _, side in ipairs(self.Sides) do
                side.ScrollBarThickness = Settings.TouchControls and 5 or 3
                side.ScrollBarImageTransparency = 0.3
            end
        end
    end
    local function resizeControls()
        for _, info in ipairs(groups) do
            for _, control in ipairs(info.Box.Elements) do
                local holder = control.Holder
                if holder and (control.Type == "Toggle" or control.Type == "Slider" or control.Type == "Dropdown" or control.Type == "Button" or control.Type == "Input") then
                    local field = control.Type == "Dropdown" or control.Type == "Input"
                    local normal = control.Type == "Toggle" and 22 or control.Type == "Slider" and 37 or field and 43 or 28
                    local height = Settings.TouchControls and (control.Type == "Slider" and 66 or field and 62 or 44) / math.min(1, Library.DPIScale or 1) or normal
                    holder.Size = UDim2.new(holder.Size.X.Scale, holder.Size.X.Offset, 0, height)
                    if control.Type == "Slider" or field then
                        for _, child in ipairs(holder:GetChildren()) do
                            if child:IsA("TextButton") or child:IsA("TextBox") then child.Size = UDim2.new(child.Size.X.Scale, child.Size.X.Offset, 0, Settings.TouchControls and 44 / math.min(1, Library.DPIScale or 1) or (control.Type == "Slider" and 19 or 25)) end
                        end
                    elseif control.Type == "Toggle" then
                        for _, child in ipairs(holder:GetChildren()) do
                            if child:IsA("Frame") then
                                child.AnchorPoint = Vector2.new(1, 0.5)
                                child.Position = UDim2.fromScale(1, 0.5)
                            end
                        end
                    end
                    if control.Type == "Dropdown" then control:RecalculateListSize() end
                elseif holder and control.Type == "Label" and not control.DoesWrap then
                    local hasButton = false
                    for _, child in ipairs(holder:GetChildren()) do
                        if child:IsA("TextButton") then
                            local side = Settings.TouchControls and 36 or 18
                            child.Size = UDim2.fromOffset(side, side)
                            hasButton = true
                        elseif child:IsA("UIListLayout") then
                            child.VerticalAlignment = Enum.VerticalAlignment.Center
                        end
                    end
                    if hasButton then holder.Size = UDim2.new(1, 0, 0, Settings.TouchControls and 44 or 22) end
                end
            end
            info.Box:Resize()
        end
    end
    function State:FitWindow(available, center)
        if not self.Running then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local size = available or Library.ScreenGui.AbsoluteSize
        if size.X < 100 or size.Y < 100 then size = camera.ViewportSize end
        self.AvailableSize = size
        closeMenus()
        local dpi = math.max(0.5, math.min(Settings.UIScale / 100, (size.X - 24) / 320, (size.Y - 68) / 240))
        if math.abs((Library.DPIScale or 1) - dpi) > 0.001 then Library:SetDPIScale(dpi * 100) end
        local width = math.min(math.clamp(Settings.UIWidth, 320, 1600), (size.X - 24) / dpi)
        local height = math.min(math.clamp(Settings.UIHeight, 240, 1200), (size.Y - 68) / dpi)
        narrow = width < 620
        main.Size = UDim2.fromOffset(math.max(260, width), math.max(180, height))
        if center or not self.WindowFitted then
            main.Position = UDim2.fromOffset(math.floor((size.X - main.Size.X.Offset * dpi) / 2), math.max(56, math.floor((size.Y - main.Size.Y.Offset * dpi) / 2)))
        else
            main.Position = UDim2.fromOffset(
                math.clamp(main.Position.X.Offset, 12, math.max(12, size.X - width * dpi - 12)),
                math.clamp(main.Position.Y.Offset, 56, math.max(56, size.Y - height * dpi - 12))
            )
        end
        self.WindowFitted = true
        Library.OriginalMinSize = Vector2.new(math.min(width, 320), math.min(height, 240))
        Library.MinSize = Library.OriginalMinSize * dpi
        window:SetSidebarWidth(narrow and 48 or 140)
        local handle = self.ResizeHandle
        local handleSize = (Settings.TouchControls and 44 or 24) / math.min(1, dpi)
        handle.AnchorPoint = Vector2.new(1, 1)
        handle.Position = UDim2.fromScale(1, 1)
        handle.SizeConstraint = Enum.SizeConstraint.RelativeXY
        handle.Size = UDim2.fromOffset(handleSize, handleSize)
        handle.ZIndex = 10
        local icon = handle:FindFirstChildWhichIsA("ImageLabel")
        if icon then
            icon.AnchorPoint = Vector2.new(1, 1)
            icon.Position = UDim2.new(1, -3, 1, -3)
            icon.Size = UDim2.fromOffset(16, 16)
        end
        if self.FooterLabel then self.FooterLabel.Size = UDim2.new(1, -handleSize - 16, 1, 0) end
        if self.ControlScale ~= dpi or self.ControlTouch ~= Settings.TouchControls or self.ControlFont ~= Settings.UIFont then
            self.ControlScale, self.ControlTouch, self.ControlFont = dpi, Settings.TouchControls, Settings.UIFont
            resizeControls()
        end
        layoutTabs()
        if self.FitSpectators then self:FitSpectators() end
    end
    function State:ResizeWindow(width, height)
        if not self.Running then return end
        local size = self.AvailableSize or Library.ScreenGui.AbsoluteSize
        local dpi = Library.DPIScale or 1
        width = math.floor(math.clamp(width, 320, math.max(320, math.min(1600, (size.X - self.Main.Position.X.Offset - 12) / dpi))) + 0.5)
        height = math.floor(math.clamp(height, 240, math.max(240, math.min(1200, (size.Y - self.Main.Position.Y.Offset - 12) / dpi))) + 0.5)
        if Settings.UIWidth == width and Settings.UIHeight == height then return end
        self.ResizingWindow = true
        controls.UIWidth:SetValue(width)
        controls.UIHeight:SetValue(height)
        self.ResizingWindow = false
        self:FitWindow()
    end
    State:FitWindow()
    connect(Library.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"), function() State:FitWindow() end)
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function() State:FitWindow() end)
    for _, player in ipairs(Players:GetPlayers()) do if player ~= LocalPlayer then createEntry(player) end end
    connect(Players.PlayerAdded, function(player)
        if player ~= LocalPlayer and not State.Entries[player] then
            local ok, err = pcall(createEntry, player)
            if not ok then removeEntry(player) State.LastError = tostring(err) report("Could not allocate ESP for a player.") end
        end
    end)
    connect(Players.PlayerRemoving, removeEntry)
    for _, tag in ipairs({ "WeaponDropped", "Bomb" }) do
        connect(CollectionService:GetInstanceAddedSignal(tag), function(model)
            if State.Running then addWorldEntry(model) World.NextScan = 0 end
        end)
        connect(CollectionService:GetInstanceRemovedSignal(tag), function(model)
            if not CollectionService:HasTag(model, "WeaponDropped") and not CollectionService:HasTag(model, "Bomb") then removeWorldEntry(model) end
            World.NextScan = 0
        end)
    end
    syncWorld(0)
    local elapsed = 0
    local queued = false
    local pendingDelta = 0
    local function update(delta)
        if not State.Running then return end
        elapsed = elapsed + delta
        local camera = workspace.CurrentCamera
        local interval = 1 / Settings.RefreshRate
        local changedCamera = camera and (camera.CFrame ~= State.LastCamera or camera.FieldOfView ~= State.LastFOV)
        if elapsed + 0.0001 < interval and not changedCamera and LocalPlayer:GetAttribute("IsSpectating") ~= true then return end
        elapsed = elapsed % interval
        local ok, err = pcall(render, os.clock())
        if not ok then
            State.LastError = tostring(err)
            Settings.Enabled = false
            hideAll()
            Library.Toggles.Enabled:SetValue(false)
            report("ESP paused: " .. tostring(err))
        end
    end
    local function queueUpdate(delta)
        if not State.Running then return end
        pendingDelta = pendingDelta + delta
        if queued then return end
        queued = true
        task.defer(function()
            queued = false
            local deltaTime = pendingDelta
            pendingDelta = 0
            update(deltaTime)
        end)
    end
    connect(RunService.RenderStepped, queueUpdate)
    local cameraSignals = {}
    local function bindCamera()
        for _, signal in ipairs(cameraSignals) do signal:Disconnect() end
        table.clear(cameraSignals)
        local camera = workspace.CurrentCamera
        if not camera then hideAll() return end
        for _, property in ipairs({ "CFrame", "FieldOfView", "ViewportSize", "CameraSubject" }) do
            table.insert(cameraSignals, connect(camera:GetPropertyChangedSignal(property), function() queueUpdate(0) end))
        end
        State.LastCamera = nil
        queueUpdate(0)
    end
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)
    bindCamera()
    if State.SaveManager then
        local autoloadOK, autoloadError = pcall(function() State.SaveManager:LoadAutoloadConfig() end)
        if not autoloadOK then report("Could not load the startup config: " .. tostring(autoloadError)) end
    end
    Library:Toggle(true)
end

local ok, failure = xpcall(start, function(err) return tostring(err) end)
if not ok then
    State:Unload()
    report("Initialization failed: " .. tostring(failure))
end

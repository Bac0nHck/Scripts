local Environment = getgenv()
local Previous = Environment.SomethingEvilHub

if Previous and Previous.Unload then
    pcall(Previous.Unload)
elseif Previous then
    Previous.Running = false
end

local RunToken = {}
Environment.SomethingEvilHubLoading = RunToken

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local IsMobile = UserInputService.TouchEnabled

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Client = ReplicatedStorage:WaitForChild("Resources"):WaitForChild("Client")
local MovementHandler = require(Client:WaitForChild("MovementHandler"))
local Stamina = require(Client.MovementHandler:WaitForChild("Stamina"))
local Sprint = require(Client.MovementHandler:WaitForChild("Sprint"))
local Jump = require(Client.MovementHandler:WaitForChild("Jump"))
local BodyTrauma = require(Client:WaitForChild("BodyTrauma"))
local CameraHandler = require(Client:WaitForChild("CameraHandler"))
local EventHandler = require(ReplicatedStorage:WaitForChild("Communication"):WaitForChild("EventHandler"))

local Hub = {
    Running = true,
    Unloading = false,
    Connections = {},
    EspObjects = {},
    NoclipDefaults = setmetatable({}, {__mode = "k"}),
    ProtectedParts = setmetatable({}, {__mode = "k"}),
    WeatherDefaults = setmetatable({}, {__mode = "k"}),
    CharacterDefaults = setmetatable({}, {__mode = "k"}),
    FarmTween = nil,
    FarmTweenConnection = nil,
    FarmPlatform = nil,
    FarmCharacter = nil,
    FarmReadyAt = 0,
    PromptCooldowns = setmetatable({}, {__mode = "k"})
}

if Environment.SomethingEvilHubLoading ~= RunToken then
    return
end

Environment.SomethingEvilHub = Hub

local State = {
    AFKFarm = false,
    AntiAFK = false,
    AFKFarmSpeed = 2000,
    AFKFarmHeight = 12,
    AFKFarmPlatformSize = 28,
    AFKFarmStartDelay = 0.35,
    AutoInteract = false,
    InteractRange = 18,
    AutoEquip = false,
    AutoUse = false,
    InfiniteStamina = false,
    GodMode = false,
    AntiRagdoll = false,
    SpeedEnabled = false,
    WalkSpeed = 36,
    JumpEnabled = false,
    JumpPower = 80,
    InfiniteJump = false,
    Noclip = false,
    Fly = false,
    FlySpeed = 70,
    PlayerESP = false,
    NpcESP = false,
    ItemESP = false,
    InteractableESP = false,
    HazardESP = false,
    ESPDistance = 1000,
    ProjectileProtection = false,
    HazardProtection = false,
    NoCameraShake = false,
    FullBright = false,
    NoWeather = false
}

Hub.State = State

local Originals = {
    FireServer = EventHandler.FireServer,
    InvokeServer = EventHandler.InvokeServer,
    ShakeCamera = CameraHandler.ShakeCamera,
    ShakeOnce = CameraHandler.ShakeOnce,
    Lighting = {
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        GlobalShadows = Lighting.GlobalShadows
    }
}

local VisualParent = gethui and gethui() or CoreGui
local VisualFolder = Instance.new("Folder")
VisualFolder.Name = "SomethingEvilHubVisuals"
VisualFolder.Parent = VisualParent

local STAMINA_FACTOR = "SomethingEvilHub_InfiniteStamina"
local SPEED_FACTOR = "SomethingEvilHub_Speed"
local JUMP_FACTOR = "SomethingEvilHub_Jump"
local BLOCKED_DAMAGE_EVENTS = {
    HurtSelf = true,
    CharHit = true,
    HitFromLingerLightningFury = true,
    HitFirewall = true,
    ResetCharacter = true,
    ClientResetTeleport = true
}
local HAZARD_TAGS = {
    "damage_player_only",
    "Fling2Damage",
    "Explosion",
    "Debris"
}
local PROTECTION_TAGS = {
    "Immortal",
    "NoRagdoll",
    "NoTrauma"
}

local function addConnection(Connection)
    table.insert(Hub.Connections, Connection)
    return Connection
end

local TouchFlyState = {
    Up = false,
    Down = false
}

local TouchGui = Instance.new("ScreenGui")
TouchGui.Name = "SomethingEvilHubTouchControls"
TouchGui.ResetOnSpawn = false
TouchGui.IgnoreGuiInset = true
TouchGui.DisplayOrder = 1000
TouchGui.Enabled = false
TouchGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
Hub.TouchGui = TouchGui

local function createTouchButton(Name, Text, Position)
    local Button = Instance.new("TextButton")
    Button.Name = Name
    Button.AnchorPoint = Vector2.new(0.5, 0.5)
    Button.Position = Position
    Button.Size = UDim2.fromOffset(62, 62)
    Button.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
    Button.BackgroundTransparency = 0.15
    Button.Text = Text
    Button.TextColor3 = Color3.new(1, 1, 1)
    Button.TextSize = 16
    Button.Font = Enum.Font.GothamBold
    Button.AutoButtonColor = true
    Button.Parent = TouchGui
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(1, 0)
    Corner.Parent = Button
    local Stroke = Instance.new("UIStroke")
    Stroke.Color = Color3.fromRGB(90, 170, 255)
    Stroke.Thickness = 2
    Stroke.Transparency = 0.2
    Stroke.Parent = Button
    return Button
end

local TouchUpButton = createTouchButton("FlyUp", "UP", UDim2.new(1, -150, 1, -245))
local TouchDownButton = createTouchButton("FlyDown", "DOWN", UDim2.new(1, -82, 1, -178))

local function bindTouchButton(Button, Key)
    addConnection(Button.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
            TouchFlyState[Key] = true
        end
    end))
    addConnection(Button.InputEnded:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
            TouchFlyState[Key] = false
        end
    end))
end

bindTouchButton(TouchUpButton, "Up")
bindTouchButton(TouchDownButton, "Down")

local function syncTouchControls()
    TouchGui.Enabled = IsMobile and State.Fly and Hub.Running
    if not TouchGui.Enabled then
        TouchFlyState.Up = false
        TouchFlyState.Down = false
    end
end

local function queryInstances(Root, Selector, ClassName)
    local Success, Result = pcall(function()
        return Root:QueryDescendants(Selector)
    end)
    if Success then
        return Result
    end
    local Results = {}
    for _, Object in Root:GetDescendants() do
        if Object:IsA(ClassName) then
            table.insert(Results, Object)
        end
    end
    return Results
end

local function getCharacter()
    local Character = LocalPlayer.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    local Root = Character and (Character:FindFirstChild("HumanoidRootPart") or Character.PrimaryPart)
    return Character, Humanoid, Root
end

local function getCharacterDefaults(Character, Humanoid)
    if not Character or not Humanoid then
        return nil
    end
    local Defaults = Hub.CharacterDefaults[Character]
    if not Defaults then
        Defaults = {
            MaxHealth = Humanoid.MaxHealth,
            AutoRotate = Humanoid.AutoRotate,
            DeadEnabled = Humanoid:GetStateEnabled(Enum.HumanoidStateType.Dead),
            RagdollEnabled = Humanoid:GetStateEnabled(Enum.HumanoidStateType.Ragdoll),
            FallingDownEnabled = Humanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown),
            Tags = {}
        }
        for _, Tag in PROTECTION_TAGS do
            Defaults.Tags[Tag] = Character:HasTag(Tag)
        end
        Hub.CharacterDefaults[Character] = Defaults
    end
    return Defaults
end

local function setTag(Character, Tag, Enabled)
    pcall(function()
        if Enabled and not Character:HasTag(Tag) then
            Character:AddTag(Tag)
        elseif not Enabled and Character:HasTag(Tag) then
            Character:RemoveTag(Tag)
        end
    end)
end

local function syncCharacterProtection()
    local Character, Humanoid = getCharacter()
    if not Character or not Humanoid then
        return
    end
    local Defaults = getCharacterDefaults(Character, Humanoid)
    local RagdollProtection = State.GodMode or State.AntiRagdoll
    setTag(Character, "Immortal", State.GodMode or Defaults.Tags.Immortal)
    setTag(Character, "NoRagdoll", RagdollProtection or Defaults.Tags.NoRagdoll)
    setTag(Character, "NoTrauma", RagdollProtection or Defaults.Tags.NoTrauma)
    pcall(function()
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, State.GodMode and false or Defaults.DeadEnabled)
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, RagdollProtection and false or Defaults.RagdollEnabled)
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, RagdollProtection and false or Defaults.FallingDownEnabled)
    end)
    if State.GodMode then
        pcall(function()
            Humanoid.MaxHealth = 1000000000
            Humanoid.Health = 1000000000
        end)
    elseif Humanoid.MaxHealth >= 1000000000 then
        pcall(function()
            Humanoid.MaxHealth = Defaults.MaxHealth
            Humanoid.Health = math.min(Humanoid.Health, Defaults.MaxHealth)
        end)
    end
    if State.AntiRagdoll or State.GodMode then
        pcall(BodyTrauma.SetRagdollTimer, 0)
        pcall(BodyTrauma.Unragdoll, false)
    end
end

local function restoreCharacter(Character)
    local Defaults = Hub.CharacterDefaults[Character]
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    if not Defaults or not Humanoid then
        return
    end
    for _, Tag in PROTECTION_TAGS do
        setTag(Character, Tag, Defaults.Tags[Tag])
    end
    pcall(function()
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, Defaults.DeadEnabled)
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, Defaults.RagdollEnabled)
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, Defaults.FallingDownEnabled)
        Humanoid.AutoRotate = Defaults.AutoRotate
        if Humanoid.MaxHealth >= 1000000000 then
            Humanoid.MaxHealth = Defaults.MaxHealth
            Humanoid.Health = math.min(Humanoid.Health, Defaults.MaxHealth)
        end
    end)
end

EventHandler.FireServer = function(Self, Name, ...)
    if State.GodMode and BLOCKED_DAMAGE_EVENTS[Name] then
        return nil
    end
    if (State.GodMode or State.AntiRagdoll) and Name == "UpdateRagdoll" and select(1, ...) == true then
        return nil
    end
    return Originals.FireServer(Self, Name, ...)
end

EventHandler.InvokeServer = function(Self, Name, ...)
    if State.GodMode and Name == "ClientFell" then
        return false
    end
    return Originals.InvokeServer(Self, Name, ...)
end

local function syncCameraShake()
    if State.NoCameraShake then
        CameraHandler.ShakeCamera = function()
            return nil
        end
        CameraHandler.ShakeOnce = function()
            return nil
        end
        pcall(CameraHandler.StopShake)
    else
        CameraHandler.ShakeCamera = Originals.ShakeCamera
        CameraHandler.ShakeOnce = Originals.ShakeOnce
    end
end

local function applyInfiniteStamina()
    pcall(Stamina.DestroyFactor, STAMINA_FACTOR)
    if State.InfiniteStamina then
        pcall(Stamina.CreateFactor, STAMINA_FACTOR, {
            MaxStamina = 1000000,
            DrainRateMulti = -1,
            RegenRate = 1000000
        })
        pcall(Stamina.DrainStamina, -1000000, 0, true)
    end
end

local function applySpeed()
    pcall(Sprint.DestroyFactor, SPEED_FACTOR)
    if State.SpeedEnabled then
        pcall(Sprint.CreateFactor, SPEED_FACTOR, {
            Walkspeed = State.WalkSpeed - 18
        })
    end
end

local function applyJump()
    pcall(Jump.RemoveJumpPowerModifier, JUMP_FACTOR)
    if State.JumpEnabled then
        pcall(Jump.AddJumpPowerModifier, JUMP_FACTOR, State.JumpPower - 50)
    end
end

local function restoreNoclip()
    for Part, CanCollide in Hub.NoclipDefaults do
        if Part.Parent then
            pcall(function()
                Part.CanCollide = CanCollide
            end)
        end
        Hub.NoclipDefaults[Part] = nil
    end
end

local function applyNoclip()
    local Character = LocalPlayer.Character
    if not Character then
        return
    end
    for _, Part in queryInstances(Character, "BasePart", "BasePart") do
        if Hub.NoclipDefaults[Part] == nil then
            Hub.NoclipDefaults[Part] = Part.CanCollide
        end
        Part.CanCollide = false
    end
end

local FlyObjects = {}

local function clearFly()
    if FlyObjects.Velocity then
        FlyObjects.Velocity:Destroy()
    end
    if FlyObjects.Gyro then
        FlyObjects.Gyro:Destroy()
    end
    FlyObjects = {}
    local Character, Humanoid = getCharacter()
    local Defaults = Character and Hub.CharacterDefaults[Character]
    if Humanoid then
        Humanoid.AutoRotate = Defaults and Defaults.AutoRotate or true
    end
end

local function ensureFly(Root, Humanoid)
    if FlyObjects.Root == Root and FlyObjects.Velocity and FlyObjects.Velocity.Parent then
        return
    end
    clearFly()
    local Velocity = Instance.new("BodyVelocity")
    Velocity.Name = "SomethingEvilHubVelocity"
    Velocity.MaxForce = Vector3.new(1000000000, 1000000000, 1000000000)
    Velocity.P = 50000
    Velocity.Velocity = Vector3.zero
    Velocity.Parent = Root
    local Gyro = Instance.new("BodyGyro")
    Gyro.Name = "SomethingEvilHubGyro"
    Gyro.MaxTorque = Vector3.new(1000000000, 1000000000, 1000000000)
    Gyro.P = 50000
    Gyro.CFrame = Root.CFrame
    Gyro.Parent = Root
    FlyObjects = {
        Root = Root,
        Velocity = Velocity,
        Gyro = Gyro
    }
    Humanoid.AutoRotate = false
end

local function updateFly()
    if not State.Fly or State.AFKFarm then
        if FlyObjects.Root then
            clearFly()
        end
        syncTouchControls()
        return
    end
    local _, Humanoid, Root = getCharacter()
    local Camera = workspace.CurrentCamera
    if not Humanoid or not Root or not Camera then
        clearFly()
        return
    end
    getCharacterDefaults(LocalPlayer.Character, Humanoid)
    Root.Anchored = false
    ensureFly(Root, Humanoid)
    local Direction = Vector3.zero
    if IsMobile then
        syncTouchControls()
        Direction = Humanoid.MoveDirection
        if TouchFlyState.Up then
            Direction = Direction + Vector3.yAxis
        end
        if TouchFlyState.Down then
            Direction = Direction - Vector3.yAxis
        end
    else
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            Direction = Direction + Camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            Direction = Direction - Camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            Direction = Direction + Camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            Direction = Direction - Camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            Direction = Direction + Vector3.yAxis
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            Direction = Direction - Vector3.yAxis
        end
    end
    if Direction.Magnitude > 0 then
        Direction = Direction.Unit
    end
    FlyObjects.Velocity.Velocity = Direction * State.FlySpeed
    FlyObjects.Gyro.CFrame = CFrame.lookAt(Root.Position, Root.Position + Camera.CFrame.LookVector)
end

local function stopAFKFarmMovement()
    if Hub.FarmTweenConnection then
        Hub.FarmTweenConnection:Disconnect()
        Hub.FarmTweenConnection = nil
    end
    if Hub.FarmTween then
        pcall(Hub.FarmTween.Cancel, Hub.FarmTween)
        Hub.FarmTween = nil
    end
    if Hub.FarmPlatform then
        Hub.FarmPlatform:Destroy()
        Hub.FarmPlatform = nil
    end
    Hub.FarmCharacter = nil
    Hub.FarmReadyAt = 0
end

local function isAFKFarmRoundActive(Character)
    return Character and Character == LocalPlayer.Character and Character.Parent and (Character:HasTag("ValidChar") or Character:HasTag("Participant"))
end

local function isAFKFarmCharacterAlive(Character, Humanoid, Root)
    return isAFKFarmRoundActive(Character) and Humanoid and Humanoid.Parent == Character and Root and Root.Parent == Character and Humanoid.Health > 0 and Humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

local function getAFKFarmTarget(Root, Humanoid)
    local Map = workspace:FindFirstChild("Map")
    local Middle = Map and Map:FindFirstChild("Middle")
    local TopHeight = Map and Map:FindFirstChild("TopHeight")
    if not Middle or not Middle:IsA("BasePart") or not TopHeight or not TopHeight:IsA("BasePart") then
        return nil
    end
    local PlatformPosition = Vector3.new(Middle.Position.X, TopHeight.Position.Y + State.AFKFarmHeight, Middle.Position.Z)
    local RootPosition = PlatformPosition + Vector3.new(0, 0.5 + Humanoid.HipHeight + Root.Size.Y * 0.5, 0)
    return PlatformPosition, RootPosition
end

local function ensureAFKFarmPlatform(Position)
    local Platform = Hub.FarmPlatform
    if not Platform or not Platform.Parent then
        Platform = Instance.new("Part")
        Platform.Name = "SomethingEvilHubAFKPlatform"
        Platform.Anchored = true
        Platform.CanCollide = true
        Platform.CanTouch = false
        Platform.CanQuery = false
        Platform.Material = Enum.Material.Neon
        Platform.Color = Color3.fromRGB(75, 170, 255)
        Platform.Transparency = 0.25
        Platform.CastShadow = false
        Platform.Parent = workspace
        Hub.FarmPlatform = Platform
    end
    Platform.Size = Vector3.new(State.AFKFarmPlatformSize, 1, State.AFKFarmPlatformSize)
    Platform.Position = Position
    return Platform
end

local function isPlayerOnAFKFarmPlatform(Humanoid, Root)
    local Platform = Hub.FarmPlatform
    if not Platform or not Platform.Parent then
        return false
    end
    local RelativePosition = Platform.CFrame:PointToObjectSpace(Root.Position)
    local HalfX = math.max(Platform.Size.X * 0.5 - 1, 1)
    local HalfZ = math.max(Platform.Size.Z * 0.5 - 1, 1)
    local StandingHeight = Platform.Size.Y * 0.5 + Humanoid.HipHeight + Root.Size.Y * 0.5
    return math.abs(RelativePosition.X) <= HalfX and math.abs(RelativePosition.Z) <= HalfZ and math.abs(RelativePosition.Y - StandingHeight) <= 5
end

local function startAFKFarmTween(Character, Humanoid, Root)
    if not State.AFKFarm or not isAFKFarmCharacterAlive(Character, Humanoid, Root) then
        return
    end
    local PlatformPosition, RootPosition = getAFKFarmTarget(Root, Humanoid)
    if not PlatformPosition then
        return
    end
    ensureAFKFarmPlatform(PlatformPosition)
    if isPlayerOnAFKFarmPlatform(Humanoid, Root) then
        return
    end
    if Hub.FarmTweenConnection then
        Hub.FarmTweenConnection:Disconnect()
        Hub.FarmTweenConnection = nil
    end
    if Hub.FarmTween then
        pcall(Hub.FarmTween.Cancel, Hub.FarmTween)
        Hub.FarmTween = nil
    end
    clearFly()
    local Distance = (Root.Position - RootPosition).Magnitude
    local Duration = math.clamp(Distance / math.max(State.AFKFarmSpeed, 1), 0.15, 2)
    local Tween = TweenService:Create(Root, TweenInfo.new(Duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
        CFrame = CFrame.new(RootPosition) * Root.CFrame.Rotation
    })
    Hub.FarmTween = Tween
    local Connection
    Connection = Tween.Completed:Connect(function()
        if Hub.FarmTween ~= Tween then
            return
        end
        Hub.FarmTween = nil
        if Hub.FarmTweenConnection == Connection then
            Hub.FarmTweenConnection = nil
        end
        Connection:Disconnect()
    end)
    Hub.FarmTweenConnection = Connection
    Tween:Play()
end

local function updateAFKFarm()
    if not State.AFKFarm then
        if Hub.FarmCharacter or Hub.FarmPlatform or Hub.FarmTween then
            stopAFKFarmMovement()
        end
        return
    end
    local Character, Humanoid, Root = getCharacter()
    if not isAFKFarmCharacterAlive(Character, Humanoid, Root) then
        if Hub.FarmCharacter or Hub.FarmPlatform or Hub.FarmTween then
            stopAFKFarmMovement()
        end
        return
    end
    if Hub.FarmCharacter ~= Character then
        stopAFKFarmMovement()
        Hub.FarmCharacter = Character
        Hub.FarmReadyAt = os.clock() + State.AFKFarmStartDelay
    end
    if os.clock() < Hub.FarmReadyAt or Hub.FarmTween then
        return
    end
    local PlatformPosition = getAFKFarmTarget(Root, Humanoid)
    if not PlatformPosition then
        return
    end
    ensureAFKFarmPlatform(PlatformPosition)
    if not isPlayerOnAFKFarmPlatform(Humanoid, Root) then
        startAFKFarmTween(Character, Humanoid, Root)
    end
end

local function getBasePart(Object)
    if not Object or not Object.Parent then
        return nil
    end
    if Object:IsA("BasePart") then
        return Object
    end
    if Object:IsA("ProximityPrompt") then
        local Parent = Object.Parent
        if Parent and Parent:IsA("Attachment") then
            Parent = Parent.Parent
        end
        if Parent and Parent:IsA("BasePart") then
            return Parent
        end
    end
    if Object:IsA("Model") then
        return Object.PrimaryPart or Object:FindFirstChild("HumanoidRootPart") or Object:FindFirstChildWhichIsA("BasePart", true)
    end
    return Object:FindFirstChild("Handle") or Object:FindFirstChildWhichIsA("BasePart", true)
end

local function getPlayerFromObject(Object)
    local Current = Object
    while Current and Current ~= workspace do
        if Current:IsA("Model") then
            local Player = Players:GetPlayerFromCharacter(Current)
            if Player then
                return Player
            end
        end
        Current = Current.Parent
    end
    return nil
end

local function destroyEsp(Object)
    local Entry = Hub.EspObjects[Object]
    if not Entry then
        return
    end
    if Entry.Highlight then
        Entry.Highlight:Destroy()
    end
    if Entry.Billboard then
        Entry.Billboard:Destroy()
    end
    Hub.EspObjects[Object] = nil
end

local function createEsp(Object, Data)
    local BasePart = getBasePart(Object)
    if not BasePart then
        return
    end
    local Highlight = Instance.new("Highlight")
    Highlight.Name = "SomethingEvilHubHighlight"
    Highlight.Adornee = Data.Adornee or Object
    Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    Highlight.FillColor = Data.Color
    Highlight.FillTransparency = 0.72
    Highlight.OutlineColor = Data.Color
    Highlight.OutlineTransparency = 0.08
    Highlight.Parent = VisualFolder
    local Billboard = Instance.new("BillboardGui")
    Billboard.Name = "SomethingEvilHubBillboard"
    Billboard.Adornee = BasePart
    Billboard.AlwaysOnTop = true
    Billboard.LightInfluence = 0
    Billboard.Size = UDim2.fromOffset(220, 44)
    Billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    Billboard.Parent = VisualFolder
    local Label = Instance.new("TextLabel")
    Label.BackgroundTransparency = 1
    Label.Size = UDim2.fromScale(1, 1)
    Label.Font = Enum.Font.GothamBold
    Label.TextColor3 = Data.Color
    Label.TextSize = 14
    Label.TextStrokeColor3 = Color3.new(0, 0, 0)
    Label.TextStrokeTransparency = 0
    Label.TextWrapped = true
    Label.Parent = Billboard
    Hub.EspObjects[Object] = {
        Object = Object,
        BasePart = BasePart,
        Highlight = Highlight,
        Billboard = Billboard,
        Label = Label,
        Text = Data.Text,
        Color = Data.Color,
        Kind = Data.Kind
    }
end

local function addDesired(Desired, Object, Kind, Color, Text, Adornee)
    if Object and Object.Parent and not Desired[Object] then
        Desired[Object] = {
            Kind = Kind,
            Color = Color,
            Text = Text,
            Adornee = Adornee
        }
    end
end

local function buildDesiredEsp()
    local Desired = {}
    if State.PlayerESP then
        for _, Player in Players:GetPlayers() do
            if Player ~= LocalPlayer and Player.Character then
                addDesired(Desired, Player.Character, "Player", Color3.fromRGB(75, 170, 255), Player.DisplayName .. " (@" .. Player.Name .. ")")
            end
        end
    end
    if State.NpcESP then
        for _, Tag in {"Enemy", "NPC"} do
            for _, Object in CollectionService:GetTagged(Tag) do
                if Object:IsDescendantOf(workspace) and not getPlayerFromObject(Object) then
                    local Model = Object:IsA("Model") and Object or Object:FindFirstAncestorOfClass("Model") or Object
                    addDesired(Desired, Model, "NPC", Color3.fromRGB(255, 80, 80), Model.Name)
                end
            end
        end
    end
    if State.ItemESP then
        for _, Tool in queryInstances(workspace, "Tool", "Tool") do
            if Tool:IsDescendantOf(workspace) and not Tool:IsDescendantOf(LocalPlayer.Character or VisualFolder) then
                addDesired(Desired, Tool, "Item", Color3.fromRGB(90, 255, 140), Tool.Name)
            end
        end
    end
    if State.InteractableESP then
        for _, Prompt in queryInstances(workspace, "ProximityPrompt[Enabled = true]", "ProximityPrompt") do
            local Parent = getBasePart(Prompt)
            local ObjectText = Prompt.ObjectText ~= "" and Prompt.ObjectText or (Parent and Parent.Name or Prompt.Name)
            local ActionText = Prompt.ActionText ~= "" and Prompt.ActionText or Prompt.Name
            addDesired(Desired, Prompt, "Interactable", Color3.fromRGB(255, 220, 75), ActionText .. " | " .. ObjectText, Parent)
        end
    end
    if State.HazardESP then
        local Projectiles = workspace:FindFirstChild("Projectiles")
        if Projectiles then
            for _, Object in Projectiles:GetChildren() do
                addDesired(Desired, Object, "Hazard", Color3.fromRGB(255, 120, 40), Object.Name)
            end
        end
        local DisasterTemp = workspace:FindFirstChild("DisasterTemp")
        if DisasterTemp then
            for _, Object in DisasterTemp:GetChildren() do
                addDesired(Desired, Object, "Hazard", Color3.fromRGB(255, 70, 170), Object.Name)
            end
        end
        for _, Tag in HAZARD_TAGS do
            for _, Object in CollectionService:GetTagged(Tag) do
                if Object:IsDescendantOf(workspace) then
                    addDesired(Desired, Object, "Hazard", Color3.fromRGB(255, 110, 35), Object.Name)
                end
            end
        end
    end
    return Desired
end

local function syncEsp()
    local Desired = buildDesiredEsp()
    for Object in Hub.EspObjects do
        if not Desired[Object] or not Object.Parent then
            destroyEsp(Object)
        end
    end
    for Object, Data in Desired do
        local Entry = Hub.EspObjects[Object]
        if not Entry then
            createEsp(Object, Data)
        elseif Entry.Kind ~= Data.Kind or Entry.Text ~= Data.Text then
            destroyEsp(Object)
            createEsp(Object, Data)
        end
    end
end

local function updateEspLabels()
    local _, _, Root = getCharacter()
    for Object, Entry in Hub.EspObjects do
        if not Object.Parent or not Entry.BasePart or not Entry.BasePart.Parent then
            destroyEsp(Object)
        else
            local Distance = Root and (Root.Position - Entry.BasePart.Position).Magnitude or 0
            local Enabled = not Root or Distance <= State.ESPDistance
            Entry.Highlight.Enabled = Enabled
            Entry.Billboard.Enabled = Enabled
            if Enabled then
                local HealthText = ""
                local Model = Object:IsA("Model") and Object or Object:FindFirstAncestorOfClass("Model")
                local Humanoid = Model and Model:FindFirstChildOfClass("Humanoid")
                if Humanoid then
                    HealthText = string.format(" | %.0f/%.0f HP", Humanoid.Health, Humanoid.MaxHealth)
                end
                Entry.Label.Text = string.format("%s%s | %.0f studs", Entry.Text, HealthText, Distance)
            end
        end
    end
end

local function restoreProtectedParts()
    for Part, Defaults in Hub.ProtectedParts do
        if Part.Parent then
            pcall(function()
                Part.CanTouch = Defaults.CanTouch
                Part.CanQuery = Defaults.CanQuery
                Part.CanCollide = Defaults.CanCollide
            end)
        end
        Hub.ProtectedParts[Part] = nil
    end
end

local function protectPart(Part, DisableCollision)
    if not Part:IsA("BasePart") then
        return
    end
    if not Hub.ProtectedParts[Part] then
        Hub.ProtectedParts[Part] = {
            CanTouch = Part.CanTouch,
            CanQuery = Part.CanQuery,
            CanCollide = Part.CanCollide
        }
    end
    Part.CanTouch = false
    Part.CanQuery = false
    if DisableCollision then
        Part.CanCollide = false
    end
end

local function protectObject(Object, DisableCollision)
    if Object:IsA("BasePart") then
        protectPart(Object, DisableCollision)
    end
    for _, Part in queryInstances(Object, "BasePart", "BasePart") do
        protectPart(Part, DisableCollision)
    end
end

local function applyWorldProtection()
    if State.ProjectileProtection then
        local Projectiles = workspace:FindFirstChild("Projectiles")
        if Projectiles then
            for _, Object in Projectiles:GetChildren() do
                protectObject(Object, false)
            end
        end
    end
    if State.HazardProtection then
        for _, Tag in HAZARD_TAGS do
            for _, Object in CollectionService:GetTagged(Tag) do
                if Object:IsDescendantOf(workspace) then
                    protectObject(Object, true)
                end
            end
        end
    end
end

local function refreshWorldProtection()
    restoreProtectedParts()
    applyWorldProtection()
end

local function rememberWeather(Object, Property)
    local Defaults = Hub.WeatherDefaults[Object]
    if not Defaults then
        Defaults = {}
        Hub.WeatherDefaults[Object] = Defaults
    end
    if Defaults[Property] == nil then
        Defaults[Property] = Object[Property]
    end
end

local function disableWeatherObject(Object)
    if Object:IsA("ParticleEmitter") or Object:IsA("Trail") or Object:IsA("Beam") or Object:IsA("PostEffect") then
        rememberWeather(Object, "Enabled")
        Object.Enabled = false
    elseif Object:IsA("Atmosphere") then
        rememberWeather(Object, "Density")
        rememberWeather(Object, "Haze")
        Object.Density = 0
        Object.Haze = 0
    elseif Object:IsA("Clouds") then
        rememberWeather(Object, "Cover")
        rememberWeather(Object, "Density")
        Object.Cover = 0
        Object.Density = 0
    end
end

local function applyNoWeather()
    if not State.NoWeather then
        return
    end
    for _, Object in Lighting:GetChildren() do
        disableWeatherObject(Object)
    end
    local Terrain = workspace:FindFirstChildOfClass("Terrain")
    if Terrain then
        for _, Object in Terrain:GetChildren() do
            disableWeatherObject(Object)
        end
    end
    for _, FolderName in {"Temp", "DisasterTemp", "LightingTemp"} do
        local Folder = workspace:FindFirstChild(FolderName)
        if Folder then
            for _, Object in Folder:GetDescendants() do
                disableWeatherObject(Object)
            end
        end
    end
end

local function restoreWeather()
    for Object, Defaults in Hub.WeatherDefaults do
        if Object.Parent then
            for Property, Value in Defaults do
                pcall(function()
                    Object[Property] = Value
                end)
            end
        end
        Hub.WeatherDefaults[Object] = nil
    end
end

local function applyLighting()
    if State.FullBright then
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.FogStart = 0
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
    end
    applyNoWeather()
end

local function restoreLighting()
    for Property, Value in Originals.Lighting do
        pcall(function()
            Lighting[Property] = Value
        end)
    end
    restoreWeather()
end

local function refreshLighting()
    restoreLighting()
    applyLighting()
end

local function fireAntiAFK(UseVirtualInput)
    if not State.AntiAFK and not State.AFKFarm then
        return
    end
    if UseVirtualInput then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.zero, workspace.CurrentCamera.CFrame)
        end)
    end
    if LocalPlayer:GetAttribute("AFK") == true then
        pcall(function()
            Originals.FireServer(EventHandler, "UpdateAFK", false)
        end)
    end
end

local function getPromptPosition(Prompt)
    local Part = getBasePart(Prompt)
    return Part and Part.Position or nil
end

local function autoInteract()
    if not State.AutoInteract or not fireproximityprompt then
        return
    end
    local _, _, Root = getCharacter()
    if not Root then
        return
    end
    local Now = os.clock()
    for _, Prompt in queryInstances(workspace, "ProximityPrompt[Enabled = true]", "ProximityPrompt") do
        local Position = getPromptPosition(Prompt)
        if Position and (Root.Position - Position).Magnitude <= State.InteractRange and (Hub.PromptCooldowns[Prompt] or 0) <= Now then
            Hub.PromptCooldowns[Prompt] = Now + 0.75
            pcall(fireproximityprompt, Prompt)
        end
    end
end

local function autoTools()
    local Character, Humanoid = getCharacter()
    if not Character or not Humanoid then
        return
    end
    if State.AutoEquip then
        local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local Tool = Backpack and Backpack:FindFirstChildOfClass("Tool")
        if Tool then
            pcall(Humanoid.EquipTool, Humanoid, Tool)
        end
    end
    if State.AutoUse then
        for _, Tool in Character:GetChildren() do
            if Tool:IsA("Tool") then
                pcall(Tool.Activate, Tool)
            end
        end
    end
end

addConnection(LocalPlayer.Idled:Connect(function()
    fireAntiAFK(true)
end))

addConnection(UserInputService.JumpRequest:Connect(function()
    if not State.InfiniteJump then
        return
    end
    local _, Humanoid = getCharacter()
    if Humanoid and Humanoid.Health > 0 then
        Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end))

addConnection(LocalPlayer.CharacterAdded:Connect(function(Character)
    task.wait(0.5)
    if not Hub.Running or Character ~= LocalPlayer.Character then
        return
    end
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if Humanoid then
        getCharacterDefaults(Character, Humanoid)
    end
    applyInfiniteStamina()
    applySpeed()
    applyJump()
    syncCharacterProtection()
end))

addConnection(RunService.Stepped:Connect(function()
    if not Hub.Running then
        return
    end
    if State.Noclip then
        applyNoclip()
    end
end))

addConnection(RunService.RenderStepped:Connect(function()
    if not Hub.Running then
        return
    end
    updateFly()
    updateEspLabels()
end))

task.spawn(function()
    while Hub.Running do
        if State.InfiniteStamina then
            pcall(Stamina.DrainStamina, -1000000, 0, true)
        end
        if State.GodMode or State.AntiRagdoll then
            syncCharacterProtection()
        end
        updateAFKFarm()
        task.wait(0.1)
    end
end)

task.spawn(function()
    while Hub.Running do
        fireAntiAFK(false)
        task.wait(20)
    end
end)

task.spawn(function()
    while Hub.Running do
        autoInteract()
        autoTools()
        task.wait(0.35)
    end
end)

task.spawn(function()
    while Hub.Running do
        syncEsp()
        applyWorldProtection()
        applyLighting()
        task.wait(0.75)
    end
end)

local Window = Fluent:CreateWindow({
    Title = "Something Evil Hub",
    SubTitle = "",
    Search = true,
    Icon = "shield",
    TabWidth = IsMobile and 130 or 160,
    Size = IsMobile and UDim2.fromOffset(540, 410) or UDim2.fromOffset(620, 500),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
    UserInfo = true,
    UserInfoTop = false,
    UserInfoTitle = LocalPlayer.DisplayName,
    UserInfoSubtitle = "@" .. LocalPlayer.Name,
    UserInfoSubtitleColor = Color3.fromRGB(90, 170, 255)
})

Fluent:CreateMinimizer({
    Icon = "shield",
    Size = UDim2.fromOffset(44, 44),
    Position = IsMobile and UDim2.new(0, 18, 0, 110) or UDim2.new(0, 24, 0.5, -22),
    Acrylic = false,
    Corner = 10,
    Transparency = 1,
    Draggable = true,
    Visible = true
})

local Tabs = {
    Farm = Window:AddTab({Title = "Farm", Icon = "bot"}),
    Survival = Window:AddTab({Title = "Survival", Icon = "heart-pulse"}),
    Movement = Window:AddTab({Title = "Movement", Icon = "move-3d"}),
    ESP = Window:AddTab({Title = "ESP", Icon = "eye"}),
    World = Window:AddTab({Title = "World", Icon = "sun"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
}

Hub.Options = Fluent.Options

Tabs.Farm:AddSection("AFK Farming", "clock")
Tabs.Farm:AddToggle("AFKFarm", {Title = "AFK Farm", Default = false}):OnChanged(function(Value)
    State.AFKFarm = Value
    if Value then
        fireAntiAFK(false)
    else
        stopAFKFarmMovement()
    end
end)
Tabs.Farm:AddToggle("AntiAFK", {Title = "Anti AFK", Default = false}):OnChanged(function(Value)
    State.AntiAFK = Value
    if Value then
        fireAntiAFK(false)
    end
end)
Tabs.Farm:AddSlider("AFKFarmSpeed", {
    Title = "Tween Flight Speed",
    Default = State.AFKFarmSpeed,
    Min = 100,
    Max = 2000,
    Rounding = 0,
    Callback = function(Value)
        State.AFKFarmSpeed = Value
    end
})
Tabs.Farm:AddSlider("AFKFarmHeight", {
    Title = "Height Above TopHeight",
    Default = State.AFKFarmHeight,
    Min = 5,
    Max = 50,
    Rounding = 0,
    Callback = function(Value)
        State.AFKFarmHeight = Value
        if Hub.FarmPlatform then
            local _, Humanoid, Root = getCharacter()
            local Position = Humanoid and Root and getAFKFarmTarget(Root, Humanoid)
            if Position then
                Hub.FarmPlatform.Position = Position
            end
        end
    end
})
Tabs.Farm:AddSlider("AFKFarmPlatformSize", {
    Title = "Platform Size",
    Default = State.AFKFarmPlatformSize,
    Min = 16,
    Max = 60,
    Rounding = 0,
    Callback = function(Value)
        State.AFKFarmPlatformSize = Value
        if Hub.FarmPlatform then
            Hub.FarmPlatform.Size = Vector3.new(Value, 1, Value)
        end
    end
})
Tabs.Farm:AddSection("Automation", "zap")
Tabs.Farm:AddToggle("AutoInteract", {Title = "Auto Interact Nearby", Default = false}):OnChanged(function(Value)
    State.AutoInteract = Value
end)
Tabs.Farm:AddSlider("InteractRange", {
    Title = "Interact Range",
    Default = State.InteractRange,
    Min = 5,
    Max = 50,
    Rounding = 0,
    Callback = function(Value)
        State.InteractRange = Value
    end
})
Tabs.Farm:AddToggle("AutoEquip", {Title = "Auto Equip First Gear", Default = false}):OnChanged(function(Value)
    State.AutoEquip = Value
end)
Tabs.Farm:AddToggle("AutoUse", {Title = "Auto Use Equipped Gear", Default = false}):OnChanged(function(Value)
    State.AutoUse = Value
end)

Tabs.Survival:AddSection("Core", "shield-check")
Tabs.Survival:AddToggle("InfiniteStamina", {Title = "Infinite Stamina", Default = false}):OnChanged(function(Value)
    State.InfiniteStamina = Value
    applyInfiniteStamina()
end)
Tabs.Survival:AddToggle("GodMode", {Title = "God Mode", Default = false}):OnChanged(function(Value)
    State.GodMode = Value
    syncCharacterProtection()
end)
Tabs.Survival:AddToggle("AntiRagdoll", {Title = "Anti Ragdoll", Default = false}):OnChanged(function(Value)
    State.AntiRagdoll = Value
    syncCharacterProtection()
end)
Tabs.Survival:AddToggle("ProjectileProtection", {Title = "Projectile Protection", Default = false}):OnChanged(function(Value)
    State.ProjectileProtection = Value
    refreshWorldProtection()
end)
Tabs.Survival:AddToggle("HazardProtection", {Title = "Hazard Protection", Default = false}):OnChanged(function(Value)
    State.HazardProtection = Value
    refreshWorldProtection()
end)
Tabs.Survival:AddToggle("NoCameraShake", {Title = "No Camera Shake", Default = false}):OnChanged(function(Value)
    State.NoCameraShake = Value
    syncCameraShake()
end)

Tabs.Movement:AddSection("Speed and Jump", "gauge")
Tabs.Movement:AddToggle("SpeedEnabled", {Title = "Speed Boost", Default = false}):OnChanged(function(Value)
    State.SpeedEnabled = Value
    applySpeed()
end)
Tabs.Movement:AddSlider("WalkSpeed", {
    Title = "Walk Speed",
    Default = State.WalkSpeed,
    Min = 18,
    Max = 150,
    Rounding = 0,
    Callback = function(Value)
        State.WalkSpeed = Value
        if State.SpeedEnabled then
            applySpeed()
        end
    end
})
Tabs.Movement:AddToggle("JumpEnabled", {Title = "Jump Boost", Default = false}):OnChanged(function(Value)
    State.JumpEnabled = Value
    applyJump()
end)
Tabs.Movement:AddSlider("JumpPower", {
    Title = "Jump Power",
    Default = State.JumpPower,
    Min = 50,
    Max = 200,
    Rounding = 0,
    Callback = function(Value)
        State.JumpPower = Value
        if State.JumpEnabled then
            applyJump()
        end
    end
})
Tabs.Movement:AddToggle("InfiniteJump", {Title = "Infinite Jump", Default = false}):OnChanged(function(Value)
    State.InfiniteJump = Value
end)
Tabs.Movement:AddSection("Traversal", "navigation")
Tabs.Movement:AddToggle("Noclip", {Title = "Noclip", Default = false}):OnChanged(function(Value)
    State.Noclip = Value
    if not Value then
        restoreNoclip()
    end
end)
Tabs.Movement:AddToggle("Fly", {Title = "Fly", Default = false}):OnChanged(function(Value)
    State.Fly = Value
    syncTouchControls()
    if not Value then
        clearFly()
    end
end)
Tabs.Movement:AddSlider("FlySpeed", {
    Title = "Fly Speed",
    Default = State.FlySpeed,
    Min = 20,
    Max = 250,
    Rounding = 0,
    Callback = function(Value)
        State.FlySpeed = Value
    end
})

Tabs.ESP:AddSection("Targets", "scan-eye")
Tabs.ESP:AddToggle("PlayerESP", {Title = "Player ESP", Default = false}):OnChanged(function(Value)
    State.PlayerESP = Value
    syncEsp()
end)
Tabs.ESP:AddToggle("NpcESP", {Title = "NPC and Enemy ESP", Default = false}):OnChanged(function(Value)
    State.NpcESP = Value
    syncEsp()
end)
Tabs.ESP:AddToggle("ItemESP", {Title = "Gear ESP", Default = false}):OnChanged(function(Value)
    State.ItemESP = Value
    syncEsp()
end)
Tabs.ESP:AddToggle("InteractableESP", {Title = "Interactable ESP", Default = false}):OnChanged(function(Value)
    State.InteractableESP = Value
    syncEsp()
end)
Tabs.ESP:AddToggle("HazardESP", {Title = "Projectile and Hazard ESP", Default = false}):OnChanged(function(Value)
    State.HazardESP = Value
    syncEsp()
end)
Tabs.ESP:AddSlider("ESPDistance", {
    Title = "ESP Distance",
    Default = State.ESPDistance,
    Min = 100,
    Max = 5000,
    Rounding = 0,
    Callback = function(Value)
        State.ESPDistance = Value
    end
})

Tabs.World:AddSection("Visibility", "sun")
Tabs.World:AddToggle("FullBright", {Title = "Full Bright", Default = false}):OnChanged(function(Value)
    State.FullBright = Value
    refreshLighting()
end)
Tabs.World:AddToggle("NoWeather", {Title = "Remove Weather and Screen Effects", Default = false}):OnChanged(function(Value)
    State.NoWeather = Value
    refreshLighting()
end)
Tabs.World:AddSection("Session", "refresh-cw")
Tabs.World:AddButton({
    Title = "Rejoin Current Server",
    Callback = function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
})

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("SomethingEvilHub")
SaveManager:SetFolder("SomethingEvilHub/16991287194")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

for Name, Value in {
    AFKFarmSpeed = 2000,
    AFKFarmHeight = 12,
    AFKFarmPlatformSize = 28,
    InteractRange = 18,
    WalkSpeed = 36,
    JumpPower = 80,
    FlySpeed = 70,
    ESPDistance = 1000
} do
    if Fluent.Options[Name] then
        Fluent.Options[Name]:SetValue(Value)
    end
end

for _, Name in {
    "AFKFarm",
    "AntiAFK",
    "AutoInteract",
    "AutoEquip",
    "AutoUse",
    "InfiniteStamina",
    "GodMode",
    "AntiRagdoll",
    "SpeedEnabled",
    "JumpEnabled",
    "InfiniteJump",
    "Noclip",
    "Fly",
    "PlayerESP",
    "NpcESP",
    "ItemESP",
    "InteractableESP",
    "HazardESP",
    "ProjectileProtection",
    "HazardProtection",
    "NoCameraShake",
    "FullBright",
    "NoWeather"
} do
    if Fluent.Options[Name] then
        Fluent.Options[Name]:SetValue(false)
    end
end

function Hub.Unload()
    if Hub.Unloading then
        return
    end
    Hub.Unloading = true
    Hub.Running = false
    State.AFKFarm = false
    State.AntiAFK = false
    State.InfiniteStamina = false
    State.GodMode = false
    State.AntiRagdoll = false
    State.SpeedEnabled = false
    State.JumpEnabled = false
    State.InfiniteJump = false
    State.Noclip = false
    State.Fly = false
    State.ProjectileProtection = false
    State.HazardProtection = false
    State.NoCameraShake = false
    State.FullBright = false
    State.NoWeather = false
    EventHandler.FireServer = Originals.FireServer
    EventHandler.InvokeServer = Originals.InvokeServer
    CameraHandler.ShakeCamera = Originals.ShakeCamera
    CameraHandler.ShakeOnce = Originals.ShakeOnce
    pcall(Stamina.DestroyFactor, STAMINA_FACTOR)
    pcall(Sprint.DestroyFactor, SPEED_FACTOR)
    pcall(Jump.RemoveJumpPowerModifier, JUMP_FACTOR)
    clearFly()
    stopAFKFarmMovement()
    restoreNoclip()
    restoreProtectedParts()
    restoreLighting()
    for Character in Hub.CharacterDefaults do
        if Character.Parent then
            restoreCharacter(Character)
        end
    end
    for Object in Hub.EspObjects do
        destroyEsp(Object)
    end
    for _, Connection in Hub.Connections do
        pcall(function()
            Connection:Disconnect()
        end)
    end
    if VisualFolder then
        VisualFolder:Destroy()
    end
    if TouchGui then
        TouchGui:Destroy()
    end
    if Environment.SomethingEvilHub == Hub then
        Environment.SomethingEvilHub = nil
    end
    if Environment.SomethingEvilHubLoading == RunToken then
        Environment.SomethingEvilHubLoading = nil
    end
    pcall(function()
        Fluent:Destroy()
    end)
end

Tabs.Settings:AddButton({
    Title = "Unload Script",
    Callback = Hub.Unload
})

local Character, Humanoid = getCharacter()
if Character and Humanoid then
    getCharacterDefaults(Character, Humanoid)
end

Window:SelectTab(1)
Fluent:Notify({
    Title = "Something Evil Hub",
    Content = "Loaded for something evil will happen.",
    Duration = 6
})

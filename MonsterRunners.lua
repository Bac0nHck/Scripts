local Environment = getgenv()

for _, Key in ipairs({"MonsterRunnersFinal", "MonsterRunnersMain", "MonsterRunnersHub"}) do
    local Previous = Environment[Key]
    if type(Previous) == "table" and type(Previous.Unload) == "function" then
        pcall(Previous.Unload)
    end
end

local repo = "https://raw.githubusercontent.com/Ali-lov3/Obsidian-UiLibs/refs/heads/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/Ali-lov3/Obsidian-UiLibs/refs/heads/main/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/Ali-lov3/Obsidian-UiLibs/refs/heads/main/addons/SaveManager.lua"))()
local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true
Library.TweenInfo = TweenInfo.new(0)
Library.NotifyTweenInfo = TweenInfo.new(0)

ThemeManager:SetLibrary(Library)
ThemeManager:SetDefaultTheme({
    BackgroundColor = Color3.fromRGB(8, 12, 19),
    MainColor = Color3.fromRGB(14, 20, 31),
    AccentColor = Color3.fromRGB(86, 156, 255),
    OutlineColor = Color3.fromRGB(34, 48, 70),
    FontColor = Color3.fromRGB(232, 240, 255),
    FontFace = Enum.Font.Gotham
})
Library.Scheme.DestructiveColor = Color3.fromRGB(235, 74, 90)
Library.Scheme.BackgroundImageEnabled = false
Library.Scheme.BackgroundImage = ""
Library.Scheme.WindowGlow = true
Library.Scheme.GradientEnabled = false

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local Monsters = Teams:WaitForChild("Monsters")
local Runners = Teams:WaitForChild("Runners")
local RoundValues = ReplicatedStorage:WaitForChild("RoundValues")
local SelectedMonster = RoundValues:WaitForChild("SelectedMonster")
local RoundState = RoundValues:WaitForChild("RoundState")
local Cutscene = RoundValues:WaitForChild("Cutscene")
local RoundEnded = RoundValues:WaitForChild("Ended")
local RankInfo = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CosmeticSystem"):WaitForChild("RankInfo"))
local GetHiddenProperty = typeof(gethiddenproperty) == "function" and gethiddenproperty or nil
local SetHiddenProperty = typeof(sethiddenproperty) == "function" and sethiddenproperty or nil
local HttpRequest = typeof(request) == "function" and request or typeof(http_request) == "function" and http_request or typeof(syn) == "table" and typeof(syn.request) == "function" and syn.request or typeof(http) == "table" and typeof(http.request) == "function" and http.request or nil

local Platform = UserInputService:GetPlatform()
local IsMobile = Platform == Enum.Platform.IOS or Platform == Enum.Platform.Android
local IsPublicServer = game.PrivateServerId == "" and game.PrivateServerOwnerId == 0
local AutoRunnerEscapeLimit = 4
local AutoRunnerRetryLimit = 4
local AutoTicketDelay = 1.25
local AutoRollDelay = 12

local SavedWebhookRate = Environment.MonsterRunnersWebhookRate
if type(SavedWebhookRate) ~= "table" or SavedWebhookRate.JobId ~= game.JobId or SavedWebhookRate.PlaceId ~= game.PlaceId or SavedWebhookRate.UserId ~= LocalPlayer.UserId then
    SavedWebhookRate = {
        JobId = game.JobId,
        PlaceId = game.PlaceId,
        UserId = LocalPlayer.UserId,
        LastRequestAt = 0,
        BackoffAt = 0,
        InFlightUntil = 0,
        InFlightToken = nil
    }
    Environment.MonsterRunnersWebhookRate = SavedWebhookRate
end

local function getCharacter(Player)
    local Character = Player and Player.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    local Root = Character and Character:FindFirstChild("HumanoidRootPart")
    return Character, Humanoid, Root
end

local function getInitialMovement()
    local _, Humanoid = getCharacter(LocalPlayer)
    local SpeedValue = LocalPlayer:FindFirstChild("WalkSpeed")
    local JumpValue = LocalPlayer:FindFirstChild("JumpHeight")
    local Speed = SpeedValue and SpeedValue.Value or Humanoid and Humanoid.WalkSpeed or 31
    local Jump = JumpValue and JumpValue.Value or Humanoid and Humanoid.JumpHeight or 12
    return Speed, Jump
end

local InitialSpeed, InitialJump = getInitialMovement()
local Hub = {
    Alive = true,
    Unloading = false,
    Connections = {},
    ESP = {},
    MonsterESP = false,
    PlayerESP = false,
    SpeedEnabled = false,
    JumpEnabled = false,
    InfiniteJump = false,
    Noclip = false,
    Fly = false,
    NoRollCooldown = false,
    RollSpeedBoost = false,
    RollSpeed = 140,
    RollGeneration = 0,
    LocalRollSession = nil,
    NativeRollWindow = nil,
    RollAnimationTrack = nil,
    RollAnimationEndsAt = 0,
    RollMobileButton = nil,
    RollMobileConnection = nil,
    RollInputToken = 0,
    NextLocalRollAt = 0,
    MoveWhileKilling = false,
    NoCrawlSlowdown = false,
    MonsterMovementApplied = false,
    KillAura = false,
    AutoMonsterFarm = false,
    AutoRunnerWin = false,
    AutoTicketExchange = false,
    AutoRankUp = false,
    AutoRoll = false,
    AntiAFK = false,
    WebhookURL = "",
    WebhookNotifications = false,
    WebhookPlayerInfo = true,
    WebhookWins = true,
    WebhookKills = true,
    WebhookScrap = true,
    WebhookEconomy = true,
    WebhookRank = true,
    WebhookGameState = true,
    WebhookBusy = false,
    WebhookQueued = false,
    WebhookQueueReason = "Periodic Update",
    WebhookInterval = 30,
    WebhookReadyAt = 0,
    WebhookBackoffAt = type(SavedWebhookRate.BackoffAt) == "number" and SavedWebhookRate.BackoffAt or 0,
    WebhookLastSentAt = 0,
    WebhookLastTestAt = 0,
    WebhookLastRequestAt = type(SavedWebhookRate.LastRequestAt) == "number" and SavedWebhookRate.LastRequestAt or 0,
    WebhookInFlightUntil = type(SavedWebhookRate.InFlightUntil) == "number" and SavedWebhookRate.InFlightUntil or 0,
    WebhookNotifyAt = 0,
    WebhookGeneration = 0,
    AutoMonsterBusy = false,
    AutoRunnerBusy = false,
    AutoTicketBusy = false,
    AutoRankBusy = false,
    AutoRollBusy = false,
    AutoRunnerPending = false,
    AutoRunnerPendingSince = 0,
    AutoRunnerAwaitingRespawn = false,
    AutoRunnerPendingCharacter = nil,
    AutoRunnerPendingRoot = nil,
    AutoRunnerPendingEscapes = nil,
    AutoRunnerSession = nil,
    AutoRunnerConfirmedAt = 0,
    AutoRunnerEndingSignalAt = 0,
    AutoRunnerReadyAt = 0,
    AutoRunnerCompleted = false,
    AutoRunnerRoundEscapes = 0,
    AutoMonsterGeneration = 0,
    AutoRunnerGeneration = 0,
    AutoTicketGeneration = 0,
    AutoRankGeneration = 0,
    AutoRollGeneration = 0,
    AutoRunnerAttempts = 0,
    NextAutoMonsterAction = 0,
    NextAutoRunnerAttempt = 0,
    NextAutoTicketAttempt = 0,
    NextAutoRankAttempt = 0,
    NextAutoRollAttempt = 0,
    AutoRankNotifyAt = 0,
    AutoRollNotifyAt = 0,
    AutoTicketNotifyAt = 0,
    AutoFarmResumeAt = 0,
    EndRoomPreloading = false,
    NextEndRoomPreload = 0,
    PlayerHitboxes = false,
    GameplayPauseBypass = false,
    Fullbright = false,
    NoFog = false,
    ColorGrade = false,
    Speed = math.clamp(math.floor(InitialSpeed + 0.5), 10, 150),
    Jump = math.clamp(math.floor(InitialJump + 0.5), 0, 75),
    FlySpeed = 1,
    AuraRange = 20,
    HitboxSize = 10,
    ColorGradePreset = "Balanced",
    ColorGradeStrength = 80,
    NextAura = 0,
    ElevatorChoice = "Nearest",
    ElevatorTeleporting = false,
    ElevatorWarningRequest = nil,
    ElevatorWarningDialog = nil,
    ElevatorWarningPermit = nil,
    ElevatorAnchoredRoot = nil,
    ElevatorOriginalAnchored = nil,
    PlayerTeleporting = false,
    NextElevatorTeleport = 0,
    NextPlayerTeleport = 0,
    SelectedPlayerUserId = nil,
    SelectedPlayerLabel = nil,
    PlayerValueToId = {},
    NoclipOriginals = setmetatable({}, {__mode = "k"}),
    HitboxOriginals = setmetatable({}, {__mode = "k"}),
    StreamingSnapshotSaved = false,
    StreamingModeApplied = false,
    NotificationSnapshotSaved = false,
    NotificationModeApplied = false,
    FullbrightSnapshotSaved = false,
    NoFogSnapshotSaved = false,
    AtmosphereSnapshots = setmetatable({}, {__mode = "k"}),
    StatsInitialized = false,
    StatsStartedAt = 0,
    StatsLast = {},
    StatsEarned = {Wins = 0, Kills = 0, Scrap = 0},
    StatsLabels = {},
    StatsText = {},
    StatsSignalsBound = false,
    PrivacyMode = false,
    PrivacyRestoring = false,
    PrivacyRecords = setmetatable({}, {__mode = "k"}),
    PrivacyConnections = {},
    PrivacyWatchedRoots = setmetatable({}, {__mode = "k"}),
    Privacy = {},
    SchedulerClock = {ESP = 0, Hitbox = 0, Aura = 0, State = 0, AutoFarm = 0, Stats = 0},
    RenderName = "MonsterRunnersFinalRender"
}

local SavedRunnerSession = Environment.MonsterRunnersRunnerSession
local SavedRunnerSessionIsTable = type(SavedRunnerSession) == "table"
local InitialRooms = Workspace:FindFirstChild("Rooms")
local InitialEndRoom = InitialRooms and InitialRooms:FindFirstChild("EndRoom")
local InitialRoundEscapes = LocalPlayer:FindFirstChild("EscapesInOneRound")
local SavedEndRoomMatches = not SavedRunnerSessionIsTable or not InitialEndRoom or not SavedRunnerSession.EndRoom or SavedRunnerSession.EndRoom == InitialEndRoom
local SavedCounterNotReset = not InitialRoundEscapes or not InitialRoundEscapes:IsA("NumberValue") or SavedRunnerSessionIsTable and type(SavedRunnerSession.PendingEscapes) == "number" and InitialRoundEscapes.Value >= SavedRunnerSession.PendingEscapes
if SavedRunnerSessionIsTable and SavedRunnerSession.Active and SavedRunnerSession.JobId == game.JobId and SavedRunnerSession.PlaceId == game.PlaceId and SavedRunnerSession.UserId == LocalPlayer.UserId and type(SavedRunnerSession.PendingEscapes) == "number" and SavedEndRoomMatches and SavedCounterNotReset and IsPublicServer and RoundState.Value == "Game" and LocalPlayer.Team == Runners then
    local RestoredRunnerSession = {
        Active = true,
        JobId = game.JobId,
        PlaceId = game.PlaceId,
        UserId = LocalPlayer.UserId,
        PendingEscapes = SavedRunnerSession.PendingEscapes,
        PendingCharacter = SavedRunnerSession.PendingCharacter,
        PendingRoot = SavedRunnerSession.PendingRoot,
        PendingSince = SavedRunnerSession.PendingSince or os.clock(),
        AwaitingRespawn = SavedRunnerSession.AwaitingRespawn == true,
        ConfirmedAt = SavedRunnerSession.ConfirmedAt or 0,
        EndingSignalAt = SavedRunnerSession.EndingSignalAt or 0,
        Attempts = SavedRunnerSession.Attempts or 0,
        EndRoom = SavedRunnerSession.EndRoom or InitialEndRoom
    }
    Environment.MonsterRunnersRunnerSession = RestoredRunnerSession
    Hub.AutoRunnerSession = RestoredRunnerSession
    Hub.AutoRunnerPending = true
    Hub.AutoRunnerPendingSince = RestoredRunnerSession.PendingSince
    Hub.AutoRunnerAwaitingRespawn = RestoredRunnerSession.AwaitingRespawn
    Hub.AutoRunnerPendingCharacter = RestoredRunnerSession.PendingCharacter
    Hub.AutoRunnerPendingRoot = RestoredRunnerSession.PendingRoot
    Hub.AutoRunnerPendingEscapes = RestoredRunnerSession.PendingEscapes
    Hub.AutoRunnerConfirmedAt = RestoredRunnerSession.ConfirmedAt
    Hub.AutoRunnerEndingSignalAt = RestoredRunnerSession.EndingSignalAt
    Hub.AutoRunnerRoundEscapes = RestoredRunnerSession.PendingEscapes
    Hub.AutoRunnerAttempts = RestoredRunnerSession.Attempts
else
    if type(SavedRunnerSession) == "table" then
        SavedRunnerSession.Active = false
    end
    Environment.MonsterRunnersRunnerSession = nil
end

Environment.MonsterRunnersFinal = Hub

local function connect(Signal, Callback)
    local Connection = Signal:Connect(Callback)
    Hub.Connections[#Hub.Connections + 1] = Connection
    return Connection
end

local function isMonster(Player)
    return RoundState.Value == "Game" and Player.Team == Monsters
end

local function getNativeMovement()
    if LocalPlayer.Team == Monsters then
        local Killing = LocalPlayer:FindFirstChild("Killing")
        local Stunned = LocalPlayer:FindFirstChild("Stunned")
        local Crawl = LocalPlayer:FindFirstChild("Crawl")
        if Killing and Killing.Value then
            return 0, 0
        end
        if Stunned and Stunned.Value then
            return 15, 0
        end
        if Crawl and Crawl.Value then
            return 25, 0
        end
        return 42, 15
    end

    local InShop = LocalPlayer:FindFirstChild("InShop")
    local Healing = LocalPlayer:FindFirstChild("Healing")
    local Cutscene = RoundValues:FindFirstChild("Cutscene")
    if InShop and InShop.Value or Healing and Healing.Value or Cutscene and Cutscene.Value then
        return 0, 0
    end

    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local CurrentClass = Values and Values:FindFirstChild("CurrentClass")
    return CurrentClass and CurrentClass.Value == "Runner" and 31 or 30, 12
end

local function isRunnerRollActive()
    local Dash = LocalPlayer:FindFirstChild("Dash")
    return Hub.LocalRollSession ~= nil or Dash and Dash.Value or false
end

local function applyMovement()
    local _, Humanoid = getCharacter(LocalPlayer)
    local SpeedValue = LocalPlayer:FindFirstChild("WalkSpeed")
    local JumpValue = LocalPlayer:FindFirstChild("JumpHeight")
    local Crawl = Hub.NoCrawlSlowdown and LocalPlayer.Team == Monsters and LocalPlayer:FindFirstChild("Crawl")
    local Crawling = Crawl and Crawl.Value
    local Speed = Crawling and Hub.Speed == 42 and 42.001 or Hub.Speed
    local Jump = Crawling and Hub.Jump == 15 and 15.001 or Hub.Jump

    if Hub.SpeedEnabled then
        if SpeedValue then
            SpeedValue.Value = Speed
        end
        if Humanoid and not isRunnerRollActive() then
            Humanoid.WalkSpeed = Speed
        end
    end

    if Hub.JumpEnabled then
        if JumpValue then
            JumpValue.Value = Jump
        end
        if Humanoid and not isRunnerRollActive() then
            Humanoid.UseJumpPower = false
            Humanoid.JumpHeight = Jump
        end
    end
end

local function restoreSpeed()
    local NativeSpeed = getNativeMovement()
    local _, Humanoid = getCharacter(LocalPlayer)
    local SpeedValue = LocalPlayer:FindFirstChild("WalkSpeed")
    if SpeedValue then
        SpeedValue.Value = NativeSpeed
    end
    if Humanoid and not isRunnerRollActive() then
        Humanoid.WalkSpeed = NativeSpeed
    end
end

local function restoreJump()
    local _, NativeJump = getNativeMovement()
    local _, Humanoid = getCharacter(LocalPlayer)
    local JumpValue = LocalPlayer:FindFirstChild("JumpHeight")
    if JumpValue then
        JumpValue.Value = NativeJump
    end
    if Humanoid and not isRunnerRollActive() then
        Humanoid.UseJumpPower = false
        Humanoid.JumpHeight = NativeJump
    end
end

local function getMonsterMovementState()
    if LocalPlayer.Team ~= Monsters then
        return false, false
    end

    local Killing = LocalPlayer:FindFirstChild("Killing")
    local Crawl = LocalPlayer:FindFirstChild("Crawl")
    local Stunned = LocalPlayer:FindFirstChild("Stunned")
    local Character, Humanoid = getCharacter(LocalPlayer)
    return Killing and Killing.Value or false, Crawl and Crawl.Value or false, Stunned and Stunned.Value or false, Character, Humanoid
end

local function applyMonsterMovementBypasses()
    local Killing, Crawling, Stunned, Character, Humanoid = getMonsterMovementState()
    local Ready = Hub.Alive and RoundState.Value == "Game" and Character and Humanoid and Humanoid.Health > 0 and not Stunned
    local Speed

    if Ready and not Hub.SpeedEnabled then
        if Killing and Hub.MoveWhileKilling then
            Speed = Crawling and (Hub.NoCrawlSlowdown and 42.001 or 25) or 42
        elseif not Killing and Crawling and Hub.NoCrawlSlowdown then
            Speed = 42.001
        end
    end

    if Speed then
        local SpeedValue = LocalPlayer:FindFirstChild("WalkSpeed")
        if SpeedValue then
            SpeedValue.Value = Speed
        end
        Humanoid.WalkSpeed = Speed
        Hub.MonsterMovementApplied = true
        return true
    end

    if Hub.MonsterMovementApplied then
        Hub.MonsterMovementApplied = false
        if not Hub.SpeedEnabled then
            restoreSpeed()
        end
    end

    return false
end

local function getRunnerRollMode()
    local MovementDirection = LocalPlayer:FindFirstChild("MovementDirection")
    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local DirectionalRolling = Values and Values:FindFirstChild("DirectionalRolling")
    if not DirectionalRolling or not DirectionalRolling.Value then
        return "Forward"
    end
    local Mode = MovementDirection and MovementDirection.Value or "Forward"
    if Mode == "Backward" or Mode == "Left" or Mode == "Right" then
        return Mode
    end
    return "Forward"
end

local function getRunnerRollDirection(Root, Mode)
    local Direction
    if Mode == "Backward" then
        Direction = -Root.CFrame.LookVector
    elseif Mode == "Left" then
        Direction = -Root.CFrame.RightVector
    elseif Mode == "Right" then
        Direction = Root.CFrame.RightVector
    else
        Direction = Root.CFrame.LookVector
    end
    local Flat = Vector3.new(Direction.X, 0, Direction.Z)
    if Flat.Magnitude <= 0.001 then
        return nil
    end
    return Flat.Unit
end

local function stopRunnerRollAnimation()
    local Track = Hub.RollAnimationTrack
    Hub.RollAnimationTrack = nil
    Hub.RollAnimationEndsAt = 0
    if Track then
        pcall(Track.Stop, Track, 0)
        pcall(Track.Destroy, Track)
    end
end

local function clearLocalRunnerRoll(StopAnimation)
    local Session = Hub.LocalRollSession
    Hub.LocalRollSession = nil
    if StopAnimation then
        stopRunnerRollAnimation()
    end
    if Session and Session.Humanoid and Session.Humanoid.Parent and LocalPlayer.Character == Session.Character then
        local SpeedValue = LocalPlayer:FindFirstChild("WalkSpeed")
        local JumpValue = LocalPlayer:FindFirstChild("JumpHeight")
        Session.Humanoid.WalkSpeed = Hub.SpeedEnabled and Hub.Speed or SpeedValue and SpeedValue.Value or Session.Humanoid.WalkSpeed
        Session.Humanoid.UseJumpPower = false
        Session.Humanoid.JumpHeight = Hub.JumpEnabled and Hub.Jump or JumpValue and JumpValue.Value or Session.Humanoid.JumpHeight
    end
end

local function clearRunnerRollState(StopAnimation)
    Hub.RollGeneration += 1
    Hub.RollInputToken += 1
    Hub.NativeRollWindow = nil
    Hub.NextLocalRollAt = 0
    clearLocalRunnerRoll(StopAnimation)
end

local function isRunnerRollBlocked(Character, Humanoid, Root)
    if not Hub.Alive or Environment.MonsterRunnersFinal ~= Hub or Cutscene.Value or LocalPlayer.Team ~= Runners or LocalPlayer.Character ~= Character or not Character.Parent or not Humanoid.Parent or Humanoid.Health <= 0 or not Root.Parent or Root.Anchored then
        return true
    end
    if Hub.Fly or Hub.ElevatorTeleporting or Hub.PlayerTeleporting or Hub.AutoMonsterBusy or Hub.AutoRunnerBusy or Hub.AutoRunnerPending or isAutoRollInFlight and isAutoRollInFlight() then
        return true
    end
    local InShop = LocalPlayer:FindFirstChild("InShop")
    local Dying = LocalPlayer:FindFirstChild("Dying")
    return InShop and InShop.Value or Dying and Dying.Value or false
end

local function armNativeRunnerRoll(Dash)
    if not Hub.RollSpeedBoost then
        return
    end
    local Character, Humanoid, Root = getCharacter(LocalPlayer)
    if not Character or not Humanoid or not Root or isRunnerRollBlocked(Character, Humanoid, Root) then
        return
    end
    local Mode = getRunnerRollMode()
    local StartAt = os.clock() + (Mode == "Backward" and 0.1 or 0)
    Hub.NativeRollWindow = {
        Character = Character,
        Humanoid = Humanoid,
        Root = Root,
        Dash = Dash,
        Mode = Mode,
        StartAt = StartAt,
        EndAt = StartAt + 0.32
    }
end

local function startLocalRunnerRoll()
    if not Hub.Alive or not Hub.NoRollCooldown or Hub.LocalRollSession or os.clock() < Hub.NextLocalRollAt then
        return
    end
    local Dash = LocalPlayer:FindFirstChild("Dash")
    local DashCooldown = LocalPlayer:FindFirstChild("DashCooldown")
    local MovementDirection = LocalPlayer:FindFirstChild("MovementDirection")
    if not Dash or not DashCooldown or not MovementDirection or Dash.Value or not DashCooldown.Value or MovementDirection.Value == "Idle" then
        return
    end
    local Character, Humanoid, Root = getCharacter(LocalPlayer)
    if not Character or not Humanoid or not Root or isRunnerRollBlocked(Character, Humanoid, Root) then
        return
    end
    local State = Humanoid:GetState()
    local PlanarVelocity = Vector3.new(Root.AssemblyLinearVelocity.X, 0, Root.AssemblyLinearVelocity.Z)
    if State == Enum.HumanoidStateType.Jumping or State == Enum.HumanoidStateType.Freefall or State == Enum.HumanoidStateType.FallingDown or Humanoid.FloorMaterial == Enum.Material.Air or Humanoid.MoveDirection.Magnitude <= 0.01 and PlanarVelocity.Magnitude <= 1 then
        return
    end
    local Mode = getRunnerRollMode()
    local UserInputScript = Character:FindFirstChild("Scripts")
    UserInputScript = UserInputScript and UserInputScript:FindFirstChild("UserInputScript")
    local Animation = UserInputScript and UserInputScript:FindFirstChild(Mode .. "RollAnim")
    local Animator = Humanoid:FindFirstChildOfClass("Animator")
    if not Animation or not Animation:IsA("Animation") or not Animator then
        return
    end
    local Loaded, Track = pcall(Animator.LoadAnimation, Animator, Animation)
    if not Loaded or not Track then
        return
    end
    stopRunnerRollAnimation()
    local Now = os.clock()
    local Generation = Hub.RollGeneration
    local Duration = Mode == "Backward" and 1 or 0.9
    Hub.RollAnimationTrack = Track
    Hub.RollAnimationEndsAt = Now + Duration
    Hub.LocalRollSession = {
        Generation = Generation,
        Character = Character,
        Humanoid = Humanoid,
        Root = Root,
        Dash = Dash,
        DashCooldown = DashCooldown,
        Mode = Mode,
        MotionStartAt = Now + (Mode == "Backward" and 0.1 or 0),
        MotionEndAt = Now + (Mode == "Backward" and 0.4 or 0.3),
        EndAt = Now + Duration
    }
    Hub.NextLocalRollAt = Now + Duration
    Hub.AutoFarmResumeAt = math.max(Hub.AutoFarmResumeAt, Now + Duration)
    pcall(Track.Play, Track, 0)
end

local function requestLocalRunnerRoll()
    if not Hub.Alive or not Hub.NoRollCooldown then
        return
    end
    local Dash = LocalPlayer:FindFirstChild("Dash")
    local DashCooldown = LocalPlayer:FindFirstChild("DashCooldown")
    if not Dash or not DashCooldown or Dash.Value or not DashCooldown.Value then
        return
    end
    Hub.RollInputToken += 1
    local Token = Hub.RollInputToken
    local Character = LocalPlayer.Character
    task.defer(function()
        if Hub.Alive and Hub.NoRollCooldown and Hub.RollInputToken == Token and Environment.MonsterRunnersFinal == Hub and LocalPlayer.Character == Character and Dash.Parent and not Dash.Value and DashCooldown.Parent and DashCooldown.Value then
            startLocalRunnerRoll()
        end
    end)
end

local function applyRunnerRollMotion()
    local Now = os.clock()
    if Hub.RollAnimationTrack and Now >= Hub.RollAnimationEndsAt then
        stopRunnerRollAnimation()
    end

    local Session = Hub.LocalRollSession
    if Session then
        local Valid = Hub.NoRollCooldown and Hub.RollGeneration == Session.Generation and Now < Session.EndAt and Session.Dash.Parent and not Session.Dash.Value and Session.DashCooldown.Parent and Session.DashCooldown.Value and not isRunnerRollBlocked(Session.Character, Session.Humanoid, Session.Root)
        if not Valid then
            clearLocalRunnerRoll(Now < Session.EndAt)
            Session = nil
        end
    end

    local Root
    local Mode
    local Speed
    if Session and Now >= Session.MotionStartAt and Now < Session.MotionEndAt then
        Root = Session.Root
        Mode = Session.Mode
        Speed = Hub.RollSpeedBoost and Hub.RollSpeed or 85
    else
        local Window = Hub.NativeRollWindow
        if Window then
            local Valid = Hub.RollSpeedBoost and Window.Dash.Parent and Window.Dash.Value and Now < Window.EndAt and not isRunnerRollBlocked(Window.Character, Window.Humanoid, Window.Root)
            if not Valid then
                Hub.NativeRollWindow = nil
            elseif Now >= Window.StartAt then
                Root = Window.Root
                Mode = Window.Mode
                Speed = Hub.RollSpeed
            end
        end
    end

    if Root and Speed then
        local Direction = getRunnerRollDirection(Root, Mode)
        if Direction then
            local Velocity = Root.AssemblyLinearVelocity
            Root.AssemblyLinearVelocity = Vector3.new(Direction.X * Speed, Velocity.Y, Direction.Z * Speed)
        end
    end
    if Session and Session.Humanoid.Parent then
        Session.Humanoid.WalkSpeed = 10
        Session.Humanoid.UseJumpPower = false
        Session.Humanoid.JumpHeight = 0
    end
end

local function syncRollMobileButton()
    if not IsMobile then
        return
    end
    local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local MobileButtons = PlayerGui and PlayerGui:FindFirstChild("MobileButtons")
    local Button = MobileButtons and MobileButtons:FindFirstChild("DashButton")
    if Button == Hub.RollMobileButton and Hub.RollMobileConnection and Hub.RollMobileConnection.Connected then
        return
    end
    if Hub.RollMobileConnection then
        Hub.RollMobileConnection:Disconnect()
        Hub.RollMobileConnection = nil
    end
    Hub.RollMobileButton = Button
    if Button and Button:IsA("GuiButton") then
        Hub.RollMobileConnection = Button.MouseButton1Click:Connect(requestLocalRunnerRoll)
    end
end

local function removeESP(Player)
    local Bundle = Hub.ESP[Player]
    if not Bundle then
        return
    end
    if Bundle.Highlight then
        Bundle.Highlight:Destroy()
    end
    if Bundle.Billboard then
        Bundle.Billboard:Destroy()
    end
    Hub.ESP[Player] = nil
end

local function createESP(Player, Character, Root)
    local Highlight = Instance.new("Highlight")
    Highlight.Name = Player.Name
    Highlight.Adornee = Character
    Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    Highlight.FillTransparency = 0.55
    Highlight.OutlineTransparency = 0
    Highlight.Parent = Character

    local Billboard = Instance.new("BillboardGui")
    Billboard.Name = Player.Name
    Billboard.Adornee = Root
    Billboard.AlwaysOnTop = true
    Billboard.LightInfluence = 0
    Billboard.MaxDistance = 5000
    Billboard.Size = UDim2.fromOffset(210, 28)
    Billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    Billboard.Parent = Root

    local Label = Instance.new("TextLabel")
    Label.BackgroundTransparency = 1
    Label.Size = UDim2.fromScale(1, 1)
    Label.Font = Enum.Font.GothamBold
    Label.TextSize = IsMobile and 13 or 14
    Label.TextStrokeTransparency = 0
    Label.Parent = Billboard

    local Bundle = {
        Character = Character,
        Root = Root,
        Highlight = Highlight,
        Billboard = Billboard,
        Label = Label
    }
    Hub.ESP[Player] = Bundle
    return Bundle
end

local function clearESP()
    local PlayersToRemove = {}
    for Player in pairs(Hub.ESP) do
        PlayersToRemove[#PlayersToRemove + 1] = Player
    end
    for _, Player in ipairs(PlayersToRemove) do
        removeESP(Player)
    end
end

local function syncESP()
    if not Hub.MonsterESP and not Hub.PlayerESP then
        clearESP()
        return
    end

    local _, _, LocalRoot = getCharacter(LocalPlayer)
    local Active = {}

    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then
            local Monster = isMonster(Player)
            local Wanted = Monster and Hub.MonsterESP or not Monster and Hub.PlayerESP
            local Character, Humanoid, Root = getCharacter(Player)

            if Wanted and Character and Humanoid and Root and Humanoid.Health > 0 then
                Active[Player] = true
                local Bundle = Hub.ESP[Player]
                if not Bundle or Bundle.Character ~= Character or Bundle.Root ~= Root then
                    removeESP(Player)
                    Bundle = createESP(Player, Character, Root)
                end

                local Color = Monster and Color3.fromRGB(255, 65, 65) or Color3.fromRGB(65, 180, 255)
                Bundle.Highlight.FillColor = Color
                Bundle.Highlight.OutlineColor = Color3.new(1, 1, 1)
                Bundle.Label.TextColor3 = Color
                local Distance = LocalRoot and math.floor((Root.Position - LocalRoot.Position).Magnitude + 0.5)
                Bundle.Label.Text = Player.DisplayName .. (Distance and " [" .. Distance .. "m]" or "")
            else
                removeESP(Player)
            end
        end
    end

    local PlayersToRemove = {}
    for Player in pairs(Hub.ESP) do
        if not Active[Player] then
            PlayersToRemove[#PlayersToRemove + 1] = Player
        end
    end
    for _, Player in ipairs(PlayersToRemove) do
        removeESP(Player)
    end
end

local function captureFullbright()
    if Hub.FullbrightSnapshotSaved then
        return
    end
    Hub.FullbrightOriginal = {
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        ExposureCompensation = Lighting.ExposureCompensation,
        GlobalShadows = Lighting.GlobalShadows
    }
    Hub.FullbrightSnapshotSaved = true
end

local function applyFullbright()
    captureFullbright()
    Lighting.Ambient = Color3.fromRGB(200, 200, 200)
    Lighting.OutdoorAmbient = Color3.fromRGB(185, 185, 185)
    Lighting.Brightness = 1.5
    Lighting.ClockTime = 14
    Lighting.ExposureCompensation = 0
    Lighting.GlobalShadows = false
end

local function restoreFullbright()
    if not Hub.FullbrightSnapshotSaved or not Hub.FullbrightOriginal then
        return
    end
    local Original = Hub.FullbrightOriginal
    Lighting.Ambient = Original.Ambient
    Lighting.OutdoorAmbient = Original.OutdoorAmbient
    Lighting.Brightness = Original.Brightness
    Lighting.ClockTime = Original.ClockTime
    Lighting.ExposureCompensation = Original.ExposureCompensation
    Lighting.GlobalShadows = Original.GlobalShadows
    Hub.FullbrightOriginal = nil
    Hub.FullbrightSnapshotSaved = false
end

local function captureAtmosphere(Atmosphere)
    if Hub.AtmosphereSnapshots[Atmosphere] then
        return
    end
    Hub.AtmosphereSnapshots[Atmosphere] = {
        Density = Atmosphere.Density,
        Haze = Atmosphere.Haze,
        Glare = Atmosphere.Glare
    }
end

local function applyNoFog()
    if not Hub.NoFogSnapshotSaved then
        Hub.NoFogOriginal = {
            FogStart = Lighting.FogStart,
            FogEnd = Lighting.FogEnd
        }
        Hub.NoFogSnapshotSaved = true
    end
    Lighting.FogStart = 0
    Lighting.FogEnd = 1000000
    for _, Descendant in ipairs(Lighting:GetDescendants()) do
        if Descendant:IsA("Atmosphere") then
            captureAtmosphere(Descendant)
            Descendant.Density = 0
            Descendant.Haze = 0
            Descendant.Glare = 0
        end
    end
end

local function restoreNoFog()
    if Hub.NoFogSnapshotSaved and Hub.NoFogOriginal then
        Lighting.FogStart = Hub.NoFogOriginal.FogStart
        Lighting.FogEnd = Hub.NoFogOriginal.FogEnd
    end
    for Atmosphere, Original in pairs(Hub.AtmosphereSnapshots) do
        if Atmosphere.Parent then
            Atmosphere.Density = Original.Density
            Atmosphere.Haze = Original.Haze
            Atmosphere.Glare = Original.Glare
        end
    end
    Hub.NoFogOriginal = nil
    Hub.NoFogSnapshotSaved = false
    Hub.AtmosphereSnapshots = setmetatable({}, {__mode = "k"})
end

local ColorGradePresets = {
    Balanced = {
        Brightness = 0.03,
        Contrast = 0.16,
        Saturation = 0.12,
        TintColor = Color3.fromRGB(255, 246, 235)
    },
    Cinematic = {
        Brightness = -0.02,
        Contrast = 0.22,
        Saturation = -0.06,
        TintColor = Color3.fromRGB(255, 238, 220)
    },
    Vibrant = {
        Brightness = 0.02,
        Contrast = 0.18,
        Saturation = 0.28,
        TintColor = Color3.fromRGB(255, 248, 235)
    },
    Cold = {
        Brightness = 0,
        Contrast = 0.16,
        Saturation = 0.08,
        TintColor = Color3.fromRGB(220, 238, 255)
    }
}

local function clearColorGrade()
    if Hub.ColorGradeEffect then
        Hub.ColorGradeEffect:Destroy()
        Hub.ColorGradeEffect = nil
    end
end

local function applyColorGrade()
    if not Hub.ColorGrade then
        clearColorGrade()
        return
    end

    local Effect = Hub.ColorGradeEffect
    if not Effect or Effect.Parent ~= Lighting then
        if Effect then
            Effect:Destroy()
        end
        Effect = Instance.new("ColorCorrectionEffect")
        Effect.Name = "MonsterRunnersColorGrade"
        Effect.Parent = Lighting
        Hub.ColorGradeEffect = Effect
    end

    local Preset = ColorGradePresets[Hub.ColorGradePreset] or ColorGradePresets.Balanced
    local Strength = math.clamp(Hub.ColorGradeStrength / 100, 0, 1)
    Effect.Brightness = Preset.Brightness * Strength
    Effect.Contrast = Preset.Contrast * Strength
    Effect.Saturation = Preset.Saturation * Strength
    Effect.TintColor = Color3.new(1, 1, 1):Lerp(Preset.TintColor, Strength)
    Effect.Enabled = true
end

local function restoreNoclip()
    if Hub.NoclipConnection then
        Hub.NoclipConnection:Disconnect()
        Hub.NoclipConnection = nil
    end
    for Part, CanCollide in pairs(Hub.NoclipOriginals) do
        if Part.Parent then
            Part.CanCollide = CanCollide
        end
        Hub.NoclipOriginals[Part] = nil
    end
    Hub.NoclipCharacter = nil
end

local function trackNoclipPart(Part)
    if Part:IsA("BasePart") and Hub.NoclipOriginals[Part] == nil then
        Hub.NoclipOriginals[Part] = Part.CanCollide
    end
end

local function applyNoclip()
    local Character = LocalPlayer.Character
    if not Character then
        return
    end

    if Hub.NoclipCharacter ~= Character then
        restoreNoclip()
        Hub.NoclipCharacter = Character
        for _, Part in ipairs(Character:GetDescendants()) do
            trackNoclipPart(Part)
        end
        Hub.NoclipConnection = Character.DescendantAdded:Connect(trackNoclipPart)
    end

    for Part in pairs(Hub.NoclipOriginals) do
        if Part.Parent then
            Part.CanCollide = false
        else
            Hub.NoclipOriginals[Part] = nil
        end
    end
end

local function getFlyControlModule()
    if Hub.FlyControlModule and type(Hub.FlyControlModule.GetMoveVector) == "function" then
        return Hub.FlyControlModule
    end
    local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
    local PlayerModule = PlayerScripts:WaitForChild("PlayerModule")
    local ControlModule = require(PlayerModule:WaitForChild("ControlModule"))
    Hub.FlyControlModule = ControlModule
    return ControlModule
end

local function disconnectFlyInputs()
    if Hub.FlyKeyDown then
        Hub.FlyKeyDown:Disconnect()
        Hub.FlyKeyDown = nil
    end
    if Hub.FlyKeyUp then
        Hub.FlyKeyUp:Disconnect()
        Hub.FlyKeyUp = nil
    end
    if Hub.MobileFlyConnection then
        Hub.MobileFlyConnection:Disconnect()
        Hub.MobileFlyConnection = nil
    end
end

local function clearFly()
    local Velocity = Hub.FlyBodyVelocity
    local Gyro = Hub.FlyBodyGyro
    local Humanoid = Hub.FlyHumanoid
    local Session = Hub.FlySession
    local HadFlyState = Session ~= nil or Velocity ~= nil or Gyro ~= nil or Humanoid ~= nil

    if Session then
        Session.Active = false
    end
    disconnectFlyInputs()
    Hub.FlyBodyVelocity = nil
    Hub.FlyBodyGyro = nil
    Hub.FlyCharacter = nil
    Hub.FlyHumanoid = nil
    Hub.FlyRoot = nil
    Hub.FlyControls = nil
    Hub.FlySession = nil

    if Velocity then
        Velocity:Destroy()
    end
    if Gyro then
        Gyro:Destroy()
    end
    if Humanoid and Humanoid.Parent then
        Humanoid.PlatformStand = false
    end
    if HadFlyState and not IsMobile then
        pcall(function()
            Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        end)
    end
end

local function setFlyControl(Controls, KeyCode, Pressed)
    local Speed = Hub.FlySpeed
    if KeyCode == Enum.KeyCode.W then
        Controls.F = Pressed and Speed or 0
    elseif KeyCode == Enum.KeyCode.S then
        Controls.B = Pressed and -Speed or 0
    elseif KeyCode == Enum.KeyCode.A then
        Controls.L = Pressed and -Speed or 0
    elseif KeyCode == Enum.KeyCode.D then
        Controls.R = Pressed and Speed or 0
    elseif KeyCode == Enum.KeyCode.E then
        Controls.Q = Pressed and Speed * 2 or 0
    elseif KeyCode == Enum.KeyCode.Q then
        Controls.E = Pressed and -Speed * 2 or 0
    end
end

local function connectFlyInputs(Controls)
    disconnectFlyInputs()
    Hub.FlyKeyDown = UserInputService.InputBegan:Connect(function(Input, Processed)
        if Processed or not Hub.Alive or not Hub.Fly or Hub.FlyControls ~= Controls then
            return
        end
        setFlyControl(Controls, Input.KeyCode, true)
    end)
    Hub.FlyKeyUp = UserInputService.InputEnded:Connect(function(Input, Processed)
        if Processed or Hub.FlyControls ~= Controls then
            return
        end
        setFlyControl(Controls, Input.KeyCode, false)
    end)
end

local function stopFlySession(Session)
    if not Session.Active then
        return
    end
    Session.Active = false
    task.defer(function()
        if Hub.FlySession ~= Session then
            return
        end
        if Hub.Alive and Hub.Fly and Toggles.Fly then
            Toggles.Fly:SetValue(false)
        else
            clearFly()
        end
    end)
end

local function runDesktopFly(Session)
    task.spawn(function()
        repeat
            task.wait()
            if not Session.Active or Hub.FlySession ~= Session then
                break
            end
            local Humanoid = Session.Humanoid
            local Velocity = Session.Velocity
            local Gyro = Session.Gyro
            local Camera = Workspace.CurrentCamera
            if not Humanoid.Parent or not Velocity.Parent or not Gyro.Parent or not Camera then
                stopFlySession(Session)
                break
            end
            Humanoid.PlatformStand = true
            local Controls = Session.Controls
            local Forward = Controls.F + Controls.B
            local Strafe = Controls.L + Controls.R
            local Vertical = Controls.Q + Controls.E
            if Forward ~= 0 or Strafe ~= 0 or Vertical ~= 0 then
                local CameraCFrame = Camera.CFrame
                local Offset = (CameraCFrame * CFrame.new(Strafe, (Forward + Vertical) * 0.2, 0)).Position - CameraCFrame.Position
                Velocity.Velocity = (CameraCFrame.LookVector * Forward + Offset) * 50
            else
                Velocity.Velocity = Vector3.zero
            end
            Gyro.CFrame = Camera.CFrame
        until not Hub.Fly
    end)
end

local function runMobileFly(Session, ControlModule)
    Hub.MobileFlyConnection = RunService.RenderStepped:Connect(function()
        if not Session.Active or Hub.FlySession ~= Session or not Hub.Fly then
            return
        end
        local Humanoid = Session.Humanoid
        local Velocity = Session.Velocity
        local Gyro = Session.Gyro
        local Camera = Workspace.CurrentCamera
        if not Humanoid.Parent or not Velocity.Parent or not Gyro.Parent or not Camera then
            stopFlySession(Session)
            return
        end
        Velocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        Gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        Humanoid.PlatformStand = true
        Gyro.CFrame = Camera.CFrame
        Velocity.Velocity = Vector3.zero
        local Direction = ControlModule:GetMoveVector()
        local Speed = Hub.FlySpeed * 50
        if Direction.X > 0 then
            Velocity.Velocity += Camera.CFrame.RightVector * Direction.X * Speed
        end
        if Direction.X < 0 then
            Velocity.Velocity += Camera.CFrame.RightVector * Direction.X * Speed
        end
        if Direction.Z > 0 then
            Velocity.Velocity -= Camera.CFrame.LookVector * Direction.Z * Speed
        end
        if Direction.Z < 0 then
            Velocity.Velocity -= Camera.CFrame.LookVector * Direction.Z * Speed
        end
    end)
end

local function ensureFly()
    local Character, Humanoid, Root = getCharacter(LocalPlayer)
    if not Hub.Alive or not Hub.Fly or not Character or not Humanoid or not Root or Humanoid.Health <= 0 then
        clearFly()
        return nil, nil
    end

    if Hub.FlyRoot == Root and Hub.FlyBodyVelocity and Hub.FlyBodyVelocity.Parent == Root and Hub.FlyBodyGyro and Hub.FlyBodyGyro.Parent == Root then
        return Humanoid, Root
    end

    clearFly()

    local ControlModule
    if IsMobile then
        ControlModule = getFlyControlModule()
        local CurrentCharacter, CurrentHumanoid, CurrentRoot = getCharacter(LocalPlayer)
        if not Hub.Alive or not Hub.Fly or CurrentCharacter ~= Character or CurrentHumanoid ~= Humanoid or CurrentRoot ~= Root or Humanoid.Health <= 0 then
            return nil, nil
        end
    end

    local Velocity = Instance.new("BodyVelocity")
    Velocity.Name = "MonsterRunnersFlyVelocity"
    Velocity.MaxForce = IsMobile and Vector3.zero or Vector3.new(9e9, 9e9, 9e9)
    Velocity.Velocity = Vector3.zero
    Velocity.Parent = Root

    local Gyro = Instance.new("BodyGyro")
    Gyro.Name = "MonsterRunnersFlyGyro"
    Gyro.P = IsMobile and 1000 or 9e4
    if IsMobile then
        Gyro.D = 50
    end
    Gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    Gyro.CFrame = Root.CFrame
    Gyro.Parent = Root

    Hub.FlyCharacter = Character
    Hub.FlyHumanoid = Humanoid
    Hub.FlyRoot = Root
    Hub.FlyBodyVelocity = Velocity
    Hub.FlyBodyGyro = Gyro
    Humanoid.PlatformStand = true

    local Session = {
        Active = true,
        Humanoid = Humanoid,
        Velocity = Velocity,
        Gyro = Gyro
    }
    Hub.FlySession = Session
    if IsMobile then
        runMobileFly(Session, ControlModule)
    else
        local Controls = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
        Session.Controls = Controls
        Hub.FlyControls = Controls
        connectFlyInputs(Controls)
        runDesktopFly(Session)
    end
    return Humanoid, Root
end

local function restoreHitboxes()
    for Part, Original in pairs(Hub.HitboxOriginals) do
        if Part.Parent then
            Part.Size = Original.Size
            Part.Transparency = Original.Transparency
            Part.CanCollide = Original.CanCollide
        end
        Hub.HitboxOriginals[Part] = nil
    end
end

local function syncHitboxes()
    if not Hub.PlayerHitboxes then
        restoreHitboxes()
        return
    end

    local Active = {}
    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then
            local _, Humanoid, Root = getCharacter(Player)
            if Humanoid and Root and Humanoid.Health > 0 then
                Active[Root] = true
                if Hub.HitboxOriginals[Root] == nil then
                    Hub.HitboxOriginals[Root] = {
                        Size = Root.Size,
                        Transparency = Root.Transparency,
                        CanCollide = Root.CanCollide
                    }
                end
                Root.Size = Vector3.new(Hub.HitboxSize, Hub.HitboxSize, Hub.HitboxSize)
                Root.Transparency = 0.7
                Root.CanCollide = false
            end
        end
    end

    for Part, Original in pairs(Hub.HitboxOriginals) do
        if not Active[Part] then
            if Part.Parent then
                Part.Size = Original.Size
                Part.Transparency = Original.Transparency
                Part.CanCollide = Original.CanCollide
            end
            Hub.HitboxOriginals[Part] = nil
        end
    end
end

local isAutoRollInFlight
local isAutoRankInFlight
local isAutoRankUpgradeReady
local cancelElevatorWarning

local function runKillAura()
    if not Hub.KillAura or Hub.AutoMonsterFarm or isAutoRollInFlight and isAutoRollInFlight() or LocalPlayer.Team ~= Monsters or os.clock() < Hub.NextAura then
        return
    end

    local Character, Humanoid, Root = getCharacter(LocalPlayer)
    local Killing = LocalPlayer:FindFirstChild("Killing")
    if not Character or not Humanoid or not Root or Humanoid.Health <= 0 or Killing and Killing.Value then
        return
    end

    local Scripts = Character:FindFirstChild("Scripts")
    local MonsterKillScript = Scripts and Scripts:FindFirstChild("MonsterKill")
    local Remote = MonsterKillScript and MonsterKillScript:FindFirstChild("MonsterKill")
    if not Remote or not Remote:IsA("RemoteEvent") then
        return
    end

    local TargetCharacter
    local Nearest = Hub.AuraRange
    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer and Player.Team == Runners then
            local CharacterToKill, HumanoidToKill, RootToKill = getCharacter(Player)
            local Dying = Player:FindFirstChild("Dying")
            local Dash = Player:FindFirstChild("Dash")
            if CharacterToKill and HumanoidToKill and RootToKill and HumanoidToKill.Health > 0 and not (Dying and Dying.Value) and not (Dash and Dash.Value) then
                local Distance = (RootToKill.Position - Root.Position).Magnitude
                if Distance <= Nearest then
                    Nearest = Distance
                    TargetCharacter = CharacterToKill
                end
            end
        end
    end

    if TargetCharacter then
        Hub.NextAura = os.clock() + 0.8
        pcall(Remote.FireServer, Remote, TargetCharacter)
    end
end

local function enableGameplayPauseBypass()
    if not Hub.StreamingSnapshotSaved and GetHiddenProperty then
        local Success, Value = pcall(GetHiddenProperty, Workspace, "StreamingIntegrityMode")
        if Success then
            Hub.StreamingOriginalMode = Value
            Hub.StreamingSnapshotSaved = true
        end
    end

    if not Hub.NotificationSnapshotSaved then
        local Success, Value = pcall(GuiService.GetGameplayPausedNotificationEnabled, GuiService)
        if Success then
            Hub.NotificationOriginalMode = Value
            Hub.NotificationSnapshotSaved = true
        end
    end

    local StreamingSuccess = false
    if SetHiddenProperty then
        StreamingSuccess = pcall(SetHiddenProperty, Workspace, "StreamingIntegrityMode", Enum.StreamingIntegrityMode.Disabled)
        Hub.StreamingModeApplied = StreamingSuccess
    end

    local NotificationSuccess = pcall(GuiService.SetGameplayPausedNotificationEnabled, GuiService, false)
    Hub.NotificationModeApplied = NotificationSuccess
    return StreamingSuccess
end

local function restoreGameplayPauseBypass()
    if Hub.StreamingModeApplied and Hub.StreamingSnapshotSaved and SetHiddenProperty then
        pcall(SetHiddenProperty, Workspace, "StreamingIntegrityMode", Hub.StreamingOriginalMode)
    end
    if Hub.NotificationModeApplied and Hub.NotificationSnapshotSaved then
        pcall(GuiService.SetGameplayPausedNotificationEnabled, GuiService, Hub.NotificationOriginalMode)
    end
    Hub.StreamingModeApplied = false
    Hub.NotificationModeApplied = false
end

local function getTemplateEndRoom()
    local StoredRooms = ReplicatedStorage:FindFirstChild("StoredRooms")
    return StoredRooms and StoredRooms:FindFirstChild("EndRoom")
end

local function getLiveEndRoom()
    local Rooms = Workspace:FindFirstChild("Rooms")
    return Rooms and Rooms:FindFirstChild("EndRoom")
end

local function getElevatorFloor(EndRoom, Name)
    local Elevator = EndRoom and EndRoom:FindFirstChild(Name)
    local Floor = Elevator and Elevator:FindFirstChild("floor", true)
    return Floor and Floor:IsA("BasePart") and Floor or nil
end

local function getEndRoomStartPart(EndRoom)
    local Scene = EndRoom and EndRoom:FindFirstChild("Scene")
    local Start = Scene and Scene:FindFirstChild("Start")
    local StartPart = Start and Start:FindFirstChild("StartPart")
    return StartPart and StartPart:IsA("BasePart") and StartPart or nil
end

local function predictPartCFrame(LiveEndRoom, TemplateEndRoom, TemplatePart)
    local LiveStartPart = getEndRoomStartPart(LiveEndRoom)
    local TemplateStartPart = getEndRoomStartPart(TemplateEndRoom)
    if not LiveStartPart or not TemplateStartPart then
        return nil
    end
    return LiveStartPart.CFrame:ToWorldSpace(TemplateStartPart.CFrame:ToObjectSpace(TemplatePart.CFrame))
end

local function getStandingCFrame(FloorCFrame, FloorSize, Humanoid, Root)
    local Character = Humanoid.Parent
    local LeftLeg = Character and Character:FindFirstChild("Left Leg")
    local LegHeight = Humanoid.RigType == Enum.HumanoidRigType.R6 and LeftLeg and LeftLeg:IsA("BasePart") and LeftLeg.Size.Y or 0
    local Height = FloorSize.Y * 0.5 + Root.Size.Y * 0.5 + math.max(Humanoid.HipHeight, LegHeight) + 0.25
    return FloorCFrame * CFrame.new(0, Height, 0)
end

local function chooseElevator(LiveEndRoom, TemplateEndRoom, Root)
    if Hub.ElevatorChoice == "Elevator 1" then
        return "Elevator1"
    end
    if Hub.ElevatorChoice == "Elevator 2" then
        return "Elevator2"
    end

    local BestName
    local BestDistance = math.huge
    for Index = 1, 2 do
        local Name = "Elevator" .. Index
        local LiveFloor = getElevatorFloor(LiveEndRoom, Name)
        local TemplateFloor = getElevatorFloor(TemplateEndRoom, Name)
        if LiveFloor or TemplateFloor then
            local FloorCFrame = LiveFloor and LiveFloor.CFrame or predictPartCFrame(LiveEndRoom, TemplateEndRoom, TemplateFloor)
            if FloorCFrame then
                local Distance = (FloorCFrame.Position - Root.Position).Magnitude
                if Distance < BestDistance then
                    BestDistance = Distance
                    BestName = Name
                end
            end
        end
    end
    return BestName or "Elevator1"
end

local function notify(Title, Content, Duration)
    if not Library.Unloaded then
        pcall(Library.Notify, Library, {
            Title = Title,
            Description = Content,
            Time = Duration or 3
        })
    end
end

local function saveAutoRunnerPending(Detach)
    if Environment.MonsterRunnersFinal ~= Hub or not Hub.AutoRunnerPending or type(Hub.AutoRunnerPendingEscapes) ~= "number" then
        return
    end
    local Session = Hub.AutoRunnerSession
    if Detach then
        if type(Session) == "table" then
            Session.Active = false
        end
        Session = {}
    elseif type(Session) ~= "table" or Environment.MonsterRunnersRunnerSession ~= Session then
        Session = {}
    end
    Session.Active = true
    Session.JobId = game.JobId
    Session.PlaceId = game.PlaceId
    Session.UserId = LocalPlayer.UserId
    Session.PendingEscapes = Hub.AutoRunnerPendingEscapes
    Session.PendingCharacter = Hub.AutoRunnerPendingCharacter
    Session.PendingRoot = Hub.AutoRunnerPendingRoot
    Session.PendingSince = Hub.AutoRunnerPendingSince
    Session.AwaitingRespawn = Hub.AutoRunnerAwaitingRespawn
    Session.ConfirmedAt = Hub.AutoRunnerConfirmedAt
    Session.EndingSignalAt = Hub.AutoRunnerEndingSignalAt
    Session.Attempts = Hub.AutoRunnerAttempts
    Session.EndRoom = getLiveEndRoom()
    Hub.AutoRunnerSession = Detach and nil or Session
    Environment.MonsterRunnersRunnerSession = Session
end

local function clearAutoRunnerPending(ResetAttempts)
    local Session = Hub.AutoRunnerSession
    if type(Session) == "table" then
        Session.Active = false
    end
    if Environment.MonsterRunnersRunnerSession == Session then
        Environment.MonsterRunnersRunnerSession = nil
    end
    Hub.AutoRunnerSession = nil
    Hub.AutoRunnerPending = false
    Hub.AutoRunnerPendingSince = 0
    Hub.AutoRunnerAwaitingRespawn = false
    Hub.AutoRunnerPendingCharacter = nil
    Hub.AutoRunnerPendingRoot = nil
    Hub.AutoRunnerPendingEscapes = nil
    Hub.AutoRunnerConfirmedAt = 0
    Hub.AutoRunnerEndingSignalAt = 0
    if ResetAttempts then
        Hub.AutoRunnerAttempts = 0
    end
end

local function syncAutoRunnerCounter()
    local EscapesInOneRound = LocalPlayer:FindFirstChild("EscapesInOneRound")
    local Current = EscapesInOneRound and EscapesInOneRound.Value or 0
    Hub.AutoRunnerRoundEscapes = Current
    Hub.AutoRunnerCompleted = RoundState.Value == "Game" and LocalPlayer.Team == Runners and Current >= AutoRunnerEscapeLimit
    return Current
end

local function restoreElevatorAnchor()
    local Root = Hub.ElevatorAnchoredRoot
    local OriginalAnchored = Hub.ElevatorOriginalAnchored
    Hub.ElevatorAnchoredRoot = nil
    Hub.ElevatorOriginalAnchored = nil
    if Root and Root.Parent then
        Root.Anchored = OriginalAnchored == true
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
    end
end

local function teleportToEndElevator(Automatic, ManualPermit)
    Automatic = Automatic == true
    local ExpectedEscapes
    if not Automatic then
        local EscapesInOneRound = LocalPlayer:FindFirstChild("EscapesInOneRound")
        local RequiresConfirmation = IsPublicServer and LocalPlayer.Team == Runners and EscapesInOneRound and EscapesInOneRound:IsA("NumberValue") and EscapesInOneRound.Value >= AutoRunnerEscapeLimit
        if type(ManualPermit) == "table" then
            local Character, _, Root = getCharacter(LocalPlayer)
            local PermitValid = Hub.ElevatorWarningPermit == ManualPermit and ManualPermit.Active and RequiresConfirmation and ManualPermit.Counter == EscapesInOneRound and ManualPermit.CounterValue == EscapesInOneRound.Value and ManualPermit.Character == Character and ManualPermit.Root == Root and ManualPermit.Team == LocalPlayer.Team and ManualPermit.RoundState == RoundState.Value and ManualPermit.EndRoom == getLiveEndRoom()
            Hub.ElevatorWarningPermit = nil
            ManualPermit.Active = false
            if not PermitValid then
                notify("End Elevator", "Teleport state changed. Confirm again", 3)
                return false
            end
        elseif RequiresConfirmation then
            notify("End Elevator", "Confirmation is required after 4 escapes", 3)
            return false
        end
    end
    if isAutoRollInFlight and isAutoRollInFlight() then
        if not Automatic then
            notify("End Elevator", "Wait for the wheel roll to finish", 3)
        end
        return false
    end
    if Hub.ElevatorTeleporting or os.clock() < Hub.NextElevatorTeleport then
        return false
    end
    if Hub.PlayerTeleporting or Hub.AutoMonsterBusy then
        if not Automatic then
            notify("End Elevator", "Another movement action is in progress", 3)
        end
        return false
    end
    if Automatic then
        local EscapesInOneRound = LocalPlayer:FindFirstChild("EscapesInOneRound")
        if not IsPublicServer or not Hub.AutoRunnerWin or Hub.AutoRunnerCompleted or RoundState.Value ~= "Game" or LocalPlayer.Team ~= Runners or Cutscene.Value or RoundEnded.Value or not EscapesInOneRound or not EscapesInOneRound:IsA("NumberValue") or EscapesInOneRound.Value >= AutoRunnerEscapeLimit or EscapesInOneRound.Value ~= Hub.AutoRunnerRoundEscapes then
            return false
        end
        ExpectedEscapes = EscapesInOneRound.Value
    end

    clearRunnerRollState(true)
    Hub.ElevatorTeleporting = true
    Hub.NextElevatorTeleport = os.clock() + 3
    if not Automatic then
        Hub.AutoFarmResumeAt = os.clock() + 3
    end
    local AutoGeneration = Hub.AutoRunnerGeneration
    if Automatic then
        Hub.AutoRunnerBusy = true
        Hub.NextAutoRunnerAttempt = os.clock() + 3
    end

    task.spawn(function()
        local AnchoredRoot
        local OriginalAnchored
        local StagedAtEnd = false
        local ExpectedCharacter
        local ExpectedEndRoom
        local AttemptArmed = false
        local AttemptDispatched = false
        local function autoValid()
            if not Automatic then
                return Hub.Alive
            end
            local EscapesInOneRound = LocalPlayer:FindFirstChild("EscapesInOneRound")
            local Dying = LocalPlayer:FindFirstChild("Dying")
            local InShop = LocalPlayer:FindFirstChild("InShop")
            local Character, Humanoid, Root = getCharacter(LocalPlayer)
            return Hub.Alive and Hub.AutoRunnerWin and not Hub.AutoRunnerCompleted and Hub.AutoRunnerGeneration == AutoGeneration and RoundState.Value == "Game" and LocalPlayer.Team == Runners and not Cutscene.Value and not RoundEnded.Value and EscapesInOneRound and EscapesInOneRound:IsA("NumberValue") and EscapesInOneRound.Value < AutoRunnerEscapeLimit and EscapesInOneRound.Value == ExpectedEscapes and not (Dying and Dying.Value) and not (InShop and InShop.Value) and Character and Humanoid and Root and Humanoid.Health > 0 and Root.CanTouch and (not ExpectedCharacter or Character == ExpectedCharacter) and (not ExpectedEndRoom or getLiveEndRoom() == ExpectedEndRoom)
        end
        local Success, ErrorMessage = xpcall(function()
            local Character, Humanoid, Root = getCharacter(LocalPlayer)
            local LiveEndRoom = getLiveEndRoom()
            local TemplateEndRoom = getTemplateEndRoom()
            if not Character or not Humanoid or not Root or Humanoid.Health <= 0 then
                error("Character is unavailable")
            end
            if not LiveEndRoom or not TemplateEndRoom then
                error("End room is unavailable")
            end
            ExpectedCharacter = Character
            ExpectedEndRoom = LiveEndRoom
            if not autoValid() then
                return
            end

            local EscapesInOneRound = LocalPlayer:FindFirstChild("EscapesInOneRound")
            if Automatic and IsPublicServer and LocalPlayer.Team == Runners and EscapesInOneRound and EscapesInOneRound.Value >= AutoRunnerEscapeLimit then
                error("Round escape limit reached")
            end

            local SelectionRoot = {Position = Root.Position}
            local ElevatorName = chooseElevator(LiveEndRoom, TemplateEndRoom, SelectionRoot)
            local TemplateFloor = getElevatorFloor(TemplateEndRoom, ElevatorName)
            if not TemplateFloor then
                error("Elevator template is unavailable")
            end

            local PredictedFloor = predictPartCFrame(LiveEndRoom, TemplateEndRoom, TemplateFloor)
            if not PredictedFloor then
                pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, LiveEndRoom:GetPivot().Position, 6)
                if not autoValid() then
                    return
                end
                ElevatorName = chooseElevator(LiveEndRoom, TemplateEndRoom, SelectionRoot)
                TemplateFloor = getElevatorFloor(TemplateEndRoom, ElevatorName)
                if not TemplateFloor then
                    error("Elevator template is unavailable")
                end
                PredictedFloor = predictPartCFrame(LiveEndRoom, TemplateEndRoom, TemplateFloor)
            end
            if not PredictedFloor then
                local CurrentCharacter, CurrentHumanoid, CurrentRoot = getCharacter(LocalPlayer)
                if CurrentCharacter ~= Character or not CurrentHumanoid or not CurrentRoot or CurrentHumanoid.Health <= 0 then
                    error("Character changed during teleport")
                end
                AnchoredRoot = CurrentRoot
                OriginalAnchored = CurrentRoot.Anchored
                Hub.ElevatorAnchoredRoot = CurrentRoot
                Hub.ElevatorOriginalAnchored = OriginalAnchored
                CurrentRoot.Anchored = true
                CurrentCharacter:PivotTo(LiveEndRoom:GetPivot() * CFrame.new(0, 6, 0))
                CurrentRoot.AssemblyLinearVelocity = Vector3.zero
                CurrentRoot.AssemblyAngularVelocity = Vector3.zero
                StagedAtEnd = true
                if not Automatic then
                    notify("End Elevator", "Loading the end of the map", 2)
                end
                pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, LiveEndRoom:GetPivot().Position, 8)
                local AnchorDeadline = os.clock() + 8
                while not getEndRoomStartPart(LiveEndRoom) and os.clock() < AnchorDeadline and autoValid() do
                    task.wait(0.15)
                end
                if not autoValid() then
                    return
                end
                ElevatorName = chooseElevator(LiveEndRoom, TemplateEndRoom, SelectionRoot)
                TemplateFloor = getElevatorFloor(TemplateEndRoom, ElevatorName)
                PredictedFloor = TemplateFloor and predictPartCFrame(LiveEndRoom, TemplateEndRoom, TemplateFloor)
                if not PredictedFloor then
                    error("End room anchor is unavailable")
                end
            end
            local PredictedStanding = getStandingCFrame(PredictedFloor, TemplateFloor.Size, Humanoid, Root)
            pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, PredictedStanding.Position, 4)
            if not autoValid() then
                return
            end

            local Deadline = os.clock() + 3
            local LiveFloor = getElevatorFloor(LiveEndRoom, ElevatorName)
            while not LiveFloor and os.clock() < Deadline and autoValid() do
                task.wait(0.15)
                LiveFloor = getElevatorFloor(LiveEndRoom, ElevatorName)
            end

            if not autoValid() then
                return
            end

            if not LiveFloor then
                local CurrentCharacter, CurrentHumanoid, CurrentRoot = getCharacter(LocalPlayer)
                if CurrentCharacter ~= Character or not CurrentHumanoid or not CurrentRoot or CurrentHumanoid.Health <= 0 then
                    error("Character changed during teleport")
                end

                if AnchoredRoot ~= CurrentRoot then
                    AnchoredRoot = CurrentRoot
                    OriginalAnchored = CurrentRoot.Anchored
                    Hub.ElevatorAnchoredRoot = CurrentRoot
                    Hub.ElevatorOriginalAnchored = OriginalAnchored
                    CurrentRoot.Anchored = true
                end
                if not StagedAtEnd then
                    CurrentCharacter:PivotTo(LiveEndRoom:GetPivot() * CFrame.new(0, 6, 0))
                    CurrentRoot.AssemblyLinearVelocity = Vector3.zero
                    CurrentRoot.AssemblyAngularVelocity = Vector3.zero
                    StagedAtEnd = true
                    if not Automatic then
                        notify("End Elevator", "Loading the end of the map", 2)
                    end
                end

                pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, LiveEndRoom:GetPivot().Position, 6)
                if not autoValid() then
                    return
                end
                pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, PredictedStanding.Position, 10)
                if not autoValid() then
                    return
                end

                Deadline = os.clock() + 12
                LiveFloor = getElevatorFloor(LiveEndRoom, ElevatorName)
                while not LiveFloor and os.clock() < Deadline and autoValid() do
                    task.wait(0.15)
                    LiveFloor = getElevatorFloor(LiveEndRoom, ElevatorName)
                end
            end

            if not autoValid() then
                return
            end

            local CurrentCharacter, CurrentHumanoid, CurrentRoot = getCharacter(LocalPlayer)
            if CurrentCharacter ~= Character or not CurrentHumanoid or not CurrentRoot or CurrentHumanoid.Health <= 0 then
                error("Character changed during teleport")
            end
            if getLiveEndRoom() ~= LiveEndRoom then
                error("End room changed during teleport")
            end

            local CurrentEscapes = LocalPlayer:FindFirstChild("EscapesInOneRound")
            if Automatic and (not CurrentEscapes or not CurrentEscapes:IsA("NumberValue") or CurrentEscapes.Value ~= ExpectedEscapes or CurrentEscapes.Value >= AutoRunnerEscapeLimit or not CurrentRoot.CanTouch) then
                return
            end

            local LiveElevator = LiveEndRoom:FindFirstChild(ElevatorName)
            local LiveTrigger = LiveElevator and LiveElevator:FindFirstChild("HitPart")
            if Automatic and LiveTrigger and LiveTrigger:IsA("BasePart") and not LiveTrigger.CanTouch then
                return
            end

            local Target = LiveFloor and getStandingCFrame(LiveFloor.CFrame, LiveFloor.Size, CurrentHumanoid, CurrentRoot) or PredictedStanding
            if Automatic then
                Hub.AutoRunnerAttempts += 1
                Hub.AutoRunnerPending = true
                Hub.AutoRunnerPendingSince = os.clock()
                Hub.AutoRunnerAwaitingRespawn = false
                Hub.AutoRunnerPendingCharacter = CurrentCharacter
                Hub.AutoRunnerPendingRoot = CurrentRoot
                Hub.AutoRunnerPendingEscapes = ExpectedEscapes
                AttemptArmed = true
                saveAutoRunnerPending()
            end
            CurrentCharacter:PivotTo(Target)
            AttemptDispatched = true
            CurrentRoot.AssemblyLinearVelocity = Vector3.zero
            CurrentRoot.AssemblyAngularVelocity = Vector3.zero
            if AnchoredRoot == CurrentRoot then
                CurrentRoot.Anchored = OriginalAnchored
                if Hub.ElevatorAnchoredRoot == CurrentRoot then
                    Hub.ElevatorAnchoredRoot = nil
                    Hub.ElevatorOriginalAnchored = nil
                end
                AnchoredRoot = nil
            end
            if not Automatic then
                notify("End Elevator", "Teleported inside " .. ElevatorName:gsub("Elevator", "Elevator "), 3)
            end
        end, function(Message)
            return tostring(Message)
        end)

        if AnchoredRoot and Hub.ElevatorAnchoredRoot == AnchoredRoot then
            if AnchoredRoot.Parent then
                AnchoredRoot.Anchored = OriginalAnchored == true
                AnchoredRoot.AssemblyLinearVelocity = Vector3.zero
                AnchoredRoot.AssemblyAngularVelocity = Vector3.zero
            end
            Hub.ElevatorAnchoredRoot = nil
            Hub.ElevatorOriginalAnchored = nil
        end
        if Automatic and AttemptArmed and not AttemptDispatched and Hub.AutoRunnerPendingCharacter == ExpectedCharacter and Hub.AutoRunnerPendingEscapes == ExpectedEscapes then
            clearAutoRunnerPending(false)
        end
        Hub.ElevatorTeleporting = false
        if Automatic then
            Hub.AutoRunnerBusy = false
        else
            Hub.AutoFarmResumeAt = os.clock() + 2
        end
        if not Success and Hub.Alive and not Automatic then
            notify("End Elevator", ErrorMessage, 4)
        end
    end)
    return true
end

local PlayerDropdown

local function buildPlayerValues()
    local Values = {}
    local ValueToId = {}
    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then
            local Value = Player.DisplayName .. " (@" .. Player.Name .. ")"
            Values[#Values + 1] = Value
            ValueToId[Value] = Player.UserId
        end
    end
    table.sort(Values, function(A, B)
        return string.lower(A) < string.lower(B)
    end)
    return Values, ValueToId
end

local function refreshPlayerDropdown()
    if not Hub.Alive or Library.Unloaded or not PlayerDropdown then
        return
    end
    local Values, ValueToId = buildPlayerValues()
    Hub.PlayerValueToId = ValueToId
    PlayerDropdown:SetValues(Values)
    if Hub.SelectedPlayerLabel and not ValueToId[Hub.SelectedPlayerLabel] then
        Hub.SelectedPlayerLabel = nil
        Hub.SelectedPlayerUserId = nil
        PlayerDropdown:SetValue(nil)
    end
end

local function teleportToSelectedPlayer()
    if isAutoRollInFlight and isAutoRollInFlight() then
        notify("Player Teleport", "Wait for the wheel roll to finish", 3)
        return
    end
    if Hub.PlayerTeleporting or os.clock() < Hub.NextPlayerTeleport then
        return
    end
    if Hub.ElevatorTeleporting or Hub.AutoMonsterBusy then
        notify("Player Teleport", "Another movement action is in progress", 3)
        return
    end
    if not Hub.SelectedPlayerUserId then
        notify("Player Teleport", "Select a player first", 3)
        return
    end

    clearRunnerRollState(true)
    Hub.PlayerTeleporting = true
    Hub.NextPlayerTeleport = os.clock() + 2
    Hub.AutoFarmResumeAt = os.clock() + 2

    task.spawn(function()
        local Success, ErrorMessage = xpcall(function()
            local TargetPlayer = Players:GetPlayerByUserId(Hub.SelectedPlayerUserId)
            if not TargetPlayer or TargetPlayer == LocalPlayer then
                error("Selected player is unavailable")
            end

            local TargetCharacter = TargetPlayer.Character
            if not TargetCharacter then
                error("Target character is unavailable")
            end

            local TargetRoot = TargetCharacter:FindFirstChild("HumanoidRootPart")
            if not TargetRoot then
                local PivotSuccess, Pivot = pcall(TargetCharacter.GetPivot, TargetCharacter)
                if PivotSuccess then
                    pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, Pivot.Position, 6)
                end
                local Deadline = os.clock() + 6
                repeat
                    task.wait(0.15)
                    TargetRoot = TargetCharacter:FindFirstChild("HumanoidRootPart")
                until TargetRoot or os.clock() >= Deadline or TargetPlayer.Parent ~= Players
            else
                pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, TargetRoot.Position, 6)
            end

            if not TargetRoot or TargetPlayer.Parent ~= Players or TargetPlayer.Character ~= TargetCharacter then
                error("Target player did not finish loading")
            end

            if not Hub.Alive then
                return
            end

            local Character, Humanoid, Root = getCharacter(LocalPlayer)
            if not Character or not Humanoid or not Root or Humanoid.Health <= 0 then
                error("Character is unavailable")
            end

            Character:PivotTo(TargetRoot.CFrame * CFrame.new(0, 0, 3))
            Root.AssemblyLinearVelocity = Vector3.zero
            Root.AssemblyAngularVelocity = Vector3.zero
            notify("Player Teleport", "Teleported to " .. TargetPlayer.DisplayName, 3)
        end, function(Message)
            return tostring(Message)
        end)

        Hub.PlayerTeleporting = false
        Hub.AutoFarmResumeAt = os.clock() + 2
        if not Success and Hub.Alive then
            notify("Player Teleport", ErrorMessage, 4)
        end
    end)
end

local function getAutoFarmElevatorPositions()
    local LiveEndRoom = getLiveEndRoom()
    local TemplateEndRoom = getTemplateEndRoom()
    if not LiveEndRoom or not TemplateEndRoom then
        return nil
    end

    local Positions = {}
    for Index = 1, 2 do
        local Name = "Elevator" .. Index
        local LiveFloor = getElevatorFloor(LiveEndRoom, Name)
        local TemplateFloor = getElevatorFloor(TemplateEndRoom, Name)
        if LiveFloor then
            Positions[#Positions + 1] = LiveFloor.Position
        elseif TemplateFloor then
            local Predicted = predictPartCFrame(LiveEndRoom, TemplateEndRoom, TemplateFloor)
            if Predicted then
                Positions[#Positions + 1] = Predicted.Position
            end
        end
    end

    if #Positions == 0 then
        return nil
    end
    return Positions, LiveEndRoom
end

local function preloadEndRoomAnchor()
    if Hub.EndRoomPreloading or os.clock() < Hub.NextEndRoomPreload then
        return
    end
    local LiveEndRoom = getLiveEndRoom()
    if not LiveEndRoom then
        return
    end
    Hub.EndRoomPreloading = true
    Hub.NextEndRoomPreload = os.clock() + 3
    task.spawn(function()
        pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, LiveEndRoom:GetPivot().Position, 4)
        Hub.EndRoomPreloading = false
    end)
end

local function getNativeRollModule()
    local Modules = ReplicatedStorage:FindFirstChild("Modules")
    local CosmeticSystem = Modules and Modules:FindFirstChild("CosmeticSystem")
    local RollModuleScript = CosmeticSystem and CosmeticSystem:FindFirstChild("RollItemTween")
    local ItemChanceScript = CosmeticSystem and CosmeticSystem:FindFirstChild("ItemChance")
    if not RollModuleScript or not RollModuleScript:IsA("ModuleScript") or not ItemChanceScript or not ItemChanceScript:IsA("ModuleScript") then
        return nil
    end
    local Success, RollModule = pcall(require, RollModuleScript)
    local ItemSuccess, ItemChance = pcall(require, ItemChanceScript)
    if Success and type(RollModule) == "table" and ItemSuccess and type(ItemChance) == "table" and type(ItemChance.getItem) == "function" then
        return RollModule, ItemChance
    end
    return nil
end

local function getAutoRollCooldown()
    local Cooldown = Environment.MonsterRunnersRollCooldown
    if type(Cooldown) ~= "table" or Cooldown.JobId ~= game.JobId or Cooldown.PlaceId ~= game.PlaceId or Cooldown.UserId ~= LocalPlayer.UserId or type(Cooldown.ReadyAt) ~= "number" or Cooldown.ReadyAt <= os.clock() then
        if Environment.MonsterRunnersRollCooldown == Cooldown then
            Environment.MonsterRunnersRollCooldown = nil
        end
        return 0
    end
    return Cooldown.ReadyAt
end

local function isNativeWheelRolling()
    local RollModule = getNativeRollModule()
    return RollModule and RollModule.rolling == true or false
end

local function disconnectWheelSessionSignals(Session)
    if type(Session) ~= "table" then
        return
    end
    for _, Key in ipairs({"RollsConnection", "ScrapConnection"}) do
        local Connection = Session[Key]
        if typeof(Connection) == "RBXScriptConnection" then
            pcall(Connection.Disconnect, Connection)
        end
        Session[Key] = nil
    end
end

local function getActiveWheelSession()
    local Session = Environment.MonsterRunnersWheelSession
    if type(Session) ~= "table" or not Session.Active then
        return nil
    end
    if Session.JobId and (Session.JobId ~= game.JobId or Session.PlaceId ~= game.PlaceId or Session.UserId ~= LocalPlayer.UserId) then
        disconnectWheelSessionSignals(Session)
        Session.Active = false
        if Environment.MonsterRunnersWheelSession == Session then
            Environment.MonsterRunnersWheelSession = nil
        end
        return nil
    end
    if Session.Background then
        local Values = LocalPlayer:FindFirstChild("BVFolder")
        local Rolls = Values and Values:FindFirstChild("Rolls")
        local Scrap = Values and Values:FindFirstChild("Scrap")
        if Rolls and Rolls:IsA("NumberValue") and type(Session.LastRolls) == "number" then
            if Rolls.Value < Session.LastRolls then
                Session.RollsSpent = (Session.RollsSpent or 0) + Session.LastRolls - Rolls.Value
            end
            Session.LastRolls = Rolls.Value
        end
        if Scrap and Scrap:IsA("NumberValue") and type(Session.LastScrap) == "number" then
            if Scrap.Value < Session.LastScrap then
                Session.ScrapSpent = (Session.ScrapSpent or 0) + Session.LastScrap - Scrap.Value
            end
            Session.LastScrap = Scrap.Value
        end
        local Confirmed = Session.Payment == "Roll" and Session.RollsSpent == 1 and (Session.ScrapSpent or 0) == 0 or Session.Payment == "Scrap" and Session.ScrapSpent == 100 and (Session.RollsSpent or 0) == 0
        if Confirmed and not Session.Unconfirmed and not isNativeWheelRolling() then
            disconnectWheelSessionSignals(Session)
            Session.Active = false
            if Environment.MonsterRunnersWheelSession == Session then
                Environment.MonsterRunnersWheelSession = nil
            end
            return nil
        end
    end
    if type(Session.ExpiresAt) == "number" and os.clock() <= Session.ExpiresAt then
        return Session
    end
    if isNativeWheelRolling() then
        Session.ExpiresAt = os.clock() + 20
        return Session
    end
    disconnectWheelSessionSignals(Session)
    Session.Active = false
    if Environment.MonsterRunnersWheelSession == Session then
        Environment.MonsterRunnersWheelSession = nil
    end
    return nil
end

isAutoRollInFlight = function()
    local Session = getActiveWheelSession()
    return isNativeWheelRolling() or Session ~= nil and Session.Background ~= true
end

local function releaseWheelSession(Session)
    if type(Session) == "table" then
        disconnectWheelSessionSignals(Session)
        Session.Active = false
    end
    if Environment.MonsterRunnersWheelSession == Session then
        Environment.MonsterRunnersWheelSession = nil
    end
end

local function getAutoFarmRunner(Player, RequireRoot)
    if not Player or Player == LocalPlayer or Player.Parent ~= Players or Player.Team ~= Runners then
        return nil
    end

    local EscapesInOneRound = Player:FindFirstChild("EscapesInOneRound")
    local Dying = Player:FindFirstChild("Dying")
    local Dash = Player:FindFirstChild("Dash")
    local InShop = Player:FindFirstChild("InShop")
    if EscapesInOneRound and EscapesInOneRound.Value > 0 or Dying and Dying.Value or Dash and Dash.Value or InShop and InShop.Value then
        return nil
    end

    local Character, Humanoid, Root = getCharacter(Player)
    if not Character or not Humanoid or Humanoid.Health <= 0 or RequireRoot and not Root then
        return nil
    end

    local Position = Root and Root.Position
    if not Position then
        local Success, Pivot = pcall(Character.GetPivot, Character)
        if Success then
            Position = Pivot.Position
        end
    end
    if not Position then
        return nil
    end
    return Character, Humanoid, Root, Position
end

local function selectAutoMonsterTarget(ElevatorPositions, MonsterRoot)
    local Best
    for _, Player in ipairs(Players:GetPlayers()) do
        local Character, Humanoid, Root, Position = getAutoFarmRunner(Player, false)
        if Character then
            local ElevatorDistance = math.huge
            for _, ElevatorPosition in ipairs(ElevatorPositions) do
                ElevatorDistance = math.min(ElevatorDistance, (Position - ElevatorPosition).Magnitude)
            end
            local MonsterDistance = (Position - MonsterRoot.Position).Magnitude
            if not Best or ElevatorDistance < Best.ElevatorDistance or ElevatorDistance == Best.ElevatorDistance and MonsterDistance < Best.MonsterDistance then
                Best = {
                    Player = Player,
                    Character = Character,
                    Humanoid = Humanoid,
                    Root = Root,
                    Position = Position,
                    ElevatorDistance = ElevatorDistance,
                    MonsterDistance = MonsterDistance
                }
            end
        end
    end
    return Best
end

local function validateAutoMonsterSession(Generation, Character, LiveEndRoom, TargetPlayer, TargetCharacter)
    if not Hub.Alive or not Hub.AutoMonsterFarm or Hub.AutoMonsterGeneration ~= Generation or RoundState.Value ~= "Game" or Cutscene.Value or RoundEnded.Value or LocalPlayer.Team ~= Monsters or LocalPlayer.Character ~= Character or getLiveEndRoom() ~= LiveEndRoom then
        return nil
    end

    local CurrentCharacter, Humanoid, Root = getCharacter(LocalPlayer)
    local Killing = LocalPlayer:FindFirstChild("Killing")
    local Stunned = LocalPlayer:FindFirstChild("Stunned")
    if CurrentCharacter ~= Character or not Humanoid or not Root or Humanoid.Health <= 0 or Killing and Killing.Value or Stunned and Stunned.Value then
        return nil
    end

    local CurrentTargetCharacter, TargetHumanoid, TargetRoot = getAutoFarmRunner(TargetPlayer, true)
    if CurrentTargetCharacter ~= TargetCharacter or not TargetHumanoid or not TargetRoot then
        return nil
    end
    return Root, TargetRoot
end

local function runAutoMonsterFarm()
    if not Hub.AutoMonsterFarm or Hub.AutoMonsterBusy or isAutoRollInFlight() or Hub.ElevatorTeleporting or Hub.PlayerTeleporting or os.clock() < Hub.NextAutoMonsterAction or os.clock() < Hub.AutoFarmResumeAt or RoundState.Value ~= "Game" or Cutscene.Value or RoundEnded.Value or LocalPlayer.Team ~= Monsters then
        return
    end
    local Character, Humanoid, Root = getCharacter(LocalPlayer)
    local Killing = LocalPlayer:FindFirstChild("Killing")
    local Stunned = LocalPlayer:FindFirstChild("Stunned")
    if not Character or not Humanoid or not Root or Humanoid.Health <= 0 or Killing and Killing.Value or Stunned and Stunned.Value then
        return
    end

    local ElevatorPositions, LiveEndRoom = getAutoFarmElevatorPositions()
    if not ElevatorPositions then
        preloadEndRoomAnchor()
        return
    end
    local Target = selectAutoMonsterTarget(ElevatorPositions, Root)
    if not Target then
        return
    end

    Hub.AutoMonsterBusy = true
    Hub.NextAutoMonsterAction = os.clock() + 0.5
    local Generation = Hub.AutoMonsterGeneration

    task.spawn(function()
        xpcall(function()
            local TargetRoot = Target.Root
            if not TargetRoot then
                pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, Target.Position, 4)
                local Deadline = os.clock() + 4
                repeat
                    if not Hub.Alive or not Hub.AutoMonsterFarm or Hub.AutoMonsterGeneration ~= Generation or RoundState.Value ~= "Game" then
                        return
                    end
                    local CurrentTargetCharacter, _, CurrentTargetRoot = getAutoFarmRunner(Target.Player, false)
                    TargetRoot = CurrentTargetRoot
                    if CurrentTargetCharacter ~= Target.Character then
                        return
                    end
                    if TargetRoot then
                        break
                    end
                    task.wait(0.1)
                until os.clock() >= Deadline
            end

            local CurrentRoot, CurrentTargetRoot = validateAutoMonsterSession(Generation, Character, LiveEndRoom, Target.Player, Target.Character)
            if not CurrentRoot or not CurrentTargetRoot then
                return
            end

            local CurrentElevatorPositions, CurrentEndRoom = getAutoFarmElevatorPositions()
            local CurrentTarget = CurrentElevatorPositions and selectAutoMonsterTarget(CurrentElevatorPositions, CurrentRoot)
            if CurrentEndRoom ~= LiveEndRoom or not CurrentTarget or CurrentTarget.Player ~= Target.Player then
                return
            end

            if Hub.Fly and Hub.Toggles and Hub.Toggles.Fly then
                Hub.Toggles.Fly:SetValue(false)
            end
            CurrentRoot, CurrentTargetRoot = validateAutoMonsterSession(Generation, Character, LiveEndRoom, Target.Player, Target.Character)
            if not CurrentRoot or not CurrentTargetRoot then
                return
            end

            Character:PivotTo(CurrentTargetRoot.CFrame * CFrame.new(0, 0, 1.5))
            CurrentRoot.AssemblyLinearVelocity = Vector3.zero
            CurrentRoot.AssemblyAngularVelocity = Vector3.zero
            RunService.Heartbeat:Wait()

            CurrentRoot, CurrentTargetRoot = validateAutoMonsterSession(Generation, Character, LiveEndRoom, Target.Player, Target.Character)
            if not CurrentRoot or not CurrentTargetRoot then
                return
            end

            local Scripts = Character:FindFirstChild("Scripts")
            local MonsterKillScript = Scripts and Scripts:FindFirstChild("MonsterKill")
            local Remote = MonsterKillScript and MonsterKillScript:FindFirstChild("MonsterKill")
            if Remote and Remote:IsA("RemoteEvent") then
                pcall(Remote.FireServer, Remote, Target.Character)
                Hub.NextAutoMonsterAction = os.clock() + 0.8
            end
        end, function(Message)
            return tostring(Message)
        end)

        if Hub.AutoMonsterGeneration == Generation then
            Hub.AutoMonsterBusy = false
            Hub.NextAutoMonsterAction = math.max(Hub.NextAutoMonsterAction, os.clock() + 0.8)
        end
    end)
end

local function runAutoRunnerWin()
    local EscapesInOneRound = LocalPlayer:FindFirstChild("EscapesInOneRound")
    if Hub.AutoRunnerPending then
        local PendingRoot = Hub.AutoRunnerPendingRoot
        local PendingCharacter = Hub.AutoRunnerPendingCharacter
        local PendingEscapes = Hub.AutoRunnerPendingEscapes
        if EscapesInOneRound and PendingEscapes and EscapesInOneRound.Value > PendingEscapes then
            Hub.AutoRunnerRoundEscapes = EscapesInOneRound.Value
            Hub.AutoRunnerCompleted = EscapesInOneRound.Value >= AutoRunnerEscapeLimit
            Hub.AutoRunnerAttempts = 0
            if Hub.AutoRunnerCompleted then
                clearAutoRunnerPending(true)
            else
                Hub.AutoRunnerAwaitingRespawn = true
                Hub.AutoRunnerConfirmedAt = Hub.AutoRunnerConfirmedAt > 0 and Hub.AutoRunnerConfirmedAt or os.clock()
                saveAutoRunnerPending()
            end
        elseif PendingRoot and PendingRoot.Parent and not PendingRoot.CanTouch then
            Hub.AutoRunnerAwaitingRespawn = true
            Hub.AutoRunnerConfirmedAt = Hub.AutoRunnerConfirmedAt > 0 and Hub.AutoRunnerConfirmedAt or os.clock()
        elseif not Hub.AutoRunnerAwaitingRespawn and os.clock() - Hub.AutoRunnerPendingSince >= 8 then
            if LocalPlayer.Character == PendingCharacter and PendingRoot and PendingRoot.Parent and PendingRoot.CanTouch and EscapesInOneRound and EscapesInOneRound.Value == PendingEscapes then
                clearAutoRunnerPending(false)
                Hub.NextAutoRunnerAttempt = os.clock() + 1
            else
                Hub.AutoRunnerAwaitingRespawn = true
                Hub.AutoRunnerConfirmedAt = Hub.AutoRunnerConfirmedAt > 0 and Hub.AutoRunnerConfirmedAt or os.clock()
            end
        end
        if Hub.AutoRunnerAwaitingRespawn and not Hub.AutoRunnerCompleted then
            local Character, Humanoid, Root = getCharacter(LocalPlayer)
            if Character and Character ~= PendingCharacter and Humanoid and Humanoid.Health > 0 and Root and Root.CanTouch and EscapesInOneRound and PendingEscapes and EscapesInOneRound.Value > PendingEscapes then
                clearAutoRunnerPending(true)
                Hub.AutoRunnerReadyAt = os.clock() + 1
            elseif Hub.AutoRunnerConfirmedAt > 0 and os.clock() - Hub.AutoRunnerConfirmedAt >= 15 then
                Hub.AutoRunnerCompleted = true
                clearAutoRunnerPending(true)
                notify("Auto Win", "Respawn was not confirmed, so Auto Win stopped for safety", 5)
            end
        end
    end
    if not IsPublicServer or not Hub.AutoRunnerWin or Hub.AutoRunnerCompleted or Hub.AutoRunnerBusy or Hub.AutoRunnerPending or isAutoRollInFlight() or Hub.ElevatorTeleporting or Hub.PlayerTeleporting or Hub.AutoMonsterBusy or Hub.AutoRunnerAttempts >= AutoRunnerRetryLimit or os.clock() < Hub.NextAutoRunnerAttempt or os.clock() < Hub.AutoRunnerReadyAt or os.clock() < Hub.AutoFarmResumeAt or RoundState.Value ~= "Game" or Cutscene.Value or RoundEnded.Value or LocalPlayer.Team ~= Runners then
        return
    end

    local Character, Humanoid, Root = getCharacter(LocalPlayer)
    local Dying = LocalPlayer:FindFirstChild("Dying")
    local InShop = LocalPlayer:FindFirstChild("InShop")
    if not Character or not Humanoid or not Root or Humanoid.Health <= 0 or not Root.CanTouch or not EscapesInOneRound or not EscapesInOneRound:IsA("NumberValue") or EscapesInOneRound.Value >= AutoRunnerEscapeLimit or EscapesInOneRound.Value ~= Hub.AutoRunnerRoundEscapes or Dying and Dying.Value or InShop and InShop.Value then
        return
    end

    if Hub.Fly and Hub.Toggles and Hub.Toggles.Fly then
        Hub.Toggles.Fly:SetValue(false)
    end
    Hub.NextAutoRunnerAttempt = os.clock() + 3
    teleportToEndElevator(true)
end

local function getAutoTicketCooldown()
    local Cooldown = Environment.MonsterRunnersTicketCooldown
    if type(Cooldown) ~= "table" or Cooldown.JobId ~= game.JobId or Cooldown.PlaceId ~= game.PlaceId or Cooldown.UserId ~= LocalPlayer.UserId or type(Cooldown.ReadyAt) ~= "number" or Cooldown.ReadyAt <= os.clock() then
        if Environment.MonsterRunnersTicketCooldown == Cooldown then
            Environment.MonsterRunnersTicketCooldown = nil
        end
        return 0
    end
    return Cooldown.ReadyAt
end

local function releaseAutoTicketSession(Session)
    if type(Session) == "table" then
        Session.Active = false
    end
    if Environment.MonsterRunnersTicketSession == Session then
        Environment.MonsterRunnersTicketSession = nil
    end
end

local function inspectAutoTicketSession()
    local Session = Environment.MonsterRunnersTicketSession
    if type(Session) ~= "table" or not Session.Active then
        return nil
    end
    if Session.JobId ~= game.JobId or Session.PlaceId ~= game.PlaceId or Session.UserId ~= LocalPlayer.UserId or type(Session.TicketsBefore) ~= "number" or type(Session.ScrapBefore) ~= "number" or type(Session.DispatchedAt) ~= "number" or type(Session.ExpiresAt) ~= "number" then
        releaseAutoTicketSession(Session)
        return nil, "invalid", Session
    end

    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local Tickets = Values and Values:FindFirstChild("Tickets")
    local Scrap = Values and Values:FindFirstChild("Scrap")
    if Tickets and Tickets:IsA("NumberValue") and Scrap and Scrap:IsA("NumberValue") and Tickets.Value <= Session.TicketsBefore - 1 and Scrap.Value >= Session.ScrapBefore + 75 then
        releaseAutoTicketSession(Session)
        return nil, "confirmed", Session
    end
    if os.clock() >= Session.ExpiresAt then
        releaseAutoTicketSession(Session)
        return nil, "expired", Session
    end
    return Session, "active", Session
end

local function isAutoTicketInFlight()
    local Session = Environment.MonsterRunnersTicketSession
    return type(Session) == "table" and Session.Active == true
end

local function resolveAutoTicketContext()
    if not Hub.Alive or not Hub.AutoTicketExchange or Cutscene.Value or RoundEnded.Value then
        return nil
    end

    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local JoinedBefore = Values and Values:FindFirstChild("JoinedBefore")
    local Tickets = Values and Values:FindFirstChild("Tickets")
    local Scrap = Values and Values:FindFirstChild("Scrap")
    if not JoinedBefore or not JoinedBefore:IsA("BoolValue") or not JoinedBefore.Value or not Tickets or not Tickets:IsA("NumberValue") or Tickets.Value < 1 or not Scrap or not Scrap:IsA("NumberValue") then
        return nil
    end

    local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local TicketUI = PlayerGui and PlayerGui:FindFirstChild("TicketExchangeUI")
    local UIServer = TicketUI and TicketUI:FindFirstChild("UIServer")
    local ExchangeEvent = UIServer and UIServer:FindFirstChild("ExchangeEvent")
    if not TicketUI or not UIServer or not ExchangeEvent or not ExchangeEvent:IsA("RemoteEvent") then
        return nil
    end

    return {
        Tickets = Tickets,
        Scrap = Scrap,
        TicketUI = TicketUI,
        UIServer = UIServer,
        ExchangeEvent = ExchangeEvent
    }
end

local function isCurrentAutoTicketContext(Context)
    local Current = resolveAutoTicketContext()
    return Current ~= nil and Current.Tickets == Context.Tickets and Current.Scrap == Context.Scrap and Current.TicketUI == Context.TicketUI and Current.UIServer == Context.UIServer and Current.ExchangeEvent == Context.ExchangeEvent
end

local function isAutoTicketReady()
    if not Hub.AutoTicketExchange or Hub.AutoTicketBusy or isAutoTicketInFlight() then
        return false
    end
    return resolveAutoTicketContext() ~= nil
end

local function runAutoTicketExchange()
    local ActiveSession, SessionState, PreviousSession = inspectAutoTicketSession()
    if ActiveSession then
        Hub.AutoTicketBusy = true
        if ActiveSession.Unconfirmed and Hub.Alive and Hub.AutoTicketExchange and Hub.Toggles and Hub.Toggles.AutoTicketExchange and Hub.Toggles.AutoTicketExchange.Value then
            if os.clock() >= Hub.AutoTicketNotifyAt then
                Hub.AutoTicketNotifyAt = os.clock() + 10
                notify("Auto Ticket Exchange", "The previous ticket exchange was not confirmed", 5)
            end
            Hub.Toggles.AutoTicketExchange:SetValue(false)
        end
        return
    end

    Hub.AutoTicketBusy = false
    if SessionState == "expired" then
        if Hub.Alive and Hub.AutoTicketExchange and Hub.Toggles and Hub.Toggles.AutoTicketExchange and Hub.Toggles.AutoTicketExchange.Value then
            if os.clock() >= Hub.AutoTicketNotifyAt then
                Hub.AutoTicketNotifyAt = os.clock() + 10
                notify("Auto Ticket Exchange", "The previous ticket exchange was not confirmed", 5)
            end
            Hub.Toggles.AutoTicketExchange:SetValue(false)
        end
        return
    end
    if SessionState == "confirmed" and PreviousSession then
        Hub.NextAutoTicketAttempt = math.max(Hub.NextAutoTicketAttempt, PreviousSession.DispatchedAt + AutoTicketDelay)
    end
    Hub.NextAutoTicketAttempt = math.max(Hub.NextAutoTicketAttempt, getAutoTicketCooldown())
    if not Hub.Alive or not Hub.AutoTicketExchange or Hub.AutoRankBusy or isAutoRankInFlight and isAutoRankInFlight() or Hub.AutoRollBusy or getActiveWheelSession() ~= nil or isNativeWheelRolling() or os.clock() < Hub.NextAutoTicketAttempt then
        return
    end

    local Context = resolveAutoTicketContext()
    if not Context then
        return
    end

    Hub.AutoTicketBusy = true
    local Generation = Hub.AutoTicketGeneration
    local TicketsBefore = Context.Tickets.Value
    local ScrapBefore = Context.Scrap.Value
    Hub.NextAutoTicketAttempt = os.clock() + AutoTicketDelay
    task.spawn(function()
        local Current = resolveAutoTicketContext()
        if not Hub.Alive or not Hub.AutoTicketExchange or Hub.AutoTicketGeneration ~= Generation or Environment.MonsterRunnersFinal ~= Hub or Hub.AutoRankBusy or isAutoRankInFlight and isAutoRankInFlight() or Hub.AutoRollBusy or getActiveWheelSession() ~= nil or isNativeWheelRolling() or not Current or not isCurrentAutoTicketContext(Context) or Current.Tickets.Value ~= TicketsBefore or Current.Scrap.Value ~= ScrapBefore then
            if Hub.AutoTicketGeneration == Generation and Environment.MonsterRunnersFinal == Hub then
                Hub.AutoTicketBusy = false
            end
            return
        end

        local Session = {
            Active = true,
            JobId = game.JobId,
            PlaceId = game.PlaceId,
            UserId = LocalPlayer.UserId,
            TicketsBefore = TicketsBefore,
            ScrapBefore = ScrapBefore,
            DispatchedAt = os.clock(),
            ExpiresAt = os.clock() + 30
        }
        Environment.MonsterRunnersTicketSession = Session
        local Fired = pcall(Current.ExchangeEvent.FireServer, Current.ExchangeEvent, LocalPlayer)
        if not Fired then
            releaseAutoTicketSession(Session)
            if Hub.AutoTicketGeneration == Generation and Environment.MonsterRunnersFinal == Hub then
                Hub.AutoTicketBusy = false
                if os.clock() >= Hub.AutoTicketNotifyAt then
                    Hub.AutoTicketNotifyAt = os.clock() + 10
                    notify("Auto Ticket Exchange", "The ticket exchange could not be sent", 4)
                end
                if Hub.Toggles and Hub.Toggles.AutoTicketExchange and Hub.Toggles.AutoTicketExchange.Value then
                    Hub.Toggles.AutoTicketExchange:SetValue(false)
                end
            end
            return
        end

        Session.DispatchedAt = os.clock()
        local ReadyAt = Session.DispatchedAt + AutoTicketDelay
        Hub.NextAutoTicketAttempt = math.max(Hub.NextAutoTicketAttempt, ReadyAt)
        Environment.MonsterRunnersTicketCooldown = {
            JobId = game.JobId,
            PlaceId = game.PlaceId,
            UserId = LocalPlayer.UserId,
            ReadyAt = ReadyAt
        }

        local Deadline = os.clock() + 5
        while Context.Tickets.Parent and Context.Scrap.Parent and os.clock() < Deadline do
            if Context.Tickets.Value <= TicketsBefore - 1 and Context.Scrap.Value >= ScrapBefore + 75 then
                break
            end
            task.wait(0.05)
        end
        if Context.Tickets.Value <= TicketsBefore - 1 and Context.Scrap.Value >= ScrapBefore + 75 then
            releaseAutoTicketSession(Session)
            if Hub.AutoTicketGeneration == Generation and Environment.MonsterRunnersFinal == Hub then
                Hub.AutoTicketBusy = false
                Hub.NextAutoTicketAttempt = math.max(Hub.NextAutoTicketAttempt, Session.DispatchedAt + AutoTicketDelay)
            end
            return
        end

        Session.Unconfirmed = true
        if Hub.AutoTicketGeneration == Generation and Environment.MonsterRunnersFinal == Hub then
            Hub.AutoTicketBusy = true
            if Hub.Alive and os.clock() >= Hub.AutoTicketNotifyAt then
                Hub.AutoTicketNotifyAt = os.clock() + 10
                notify("Auto Ticket Exchange", "The server did not confirm the ticket exchange", 5)
            end
            if Hub.Toggles and Hub.Toggles.AutoTicketExchange and Hub.Toggles.AutoTicketExchange.Value then
                Hub.Toggles.AutoTicketExchange:SetValue(false)
            end
        end
    end)
end

local function resolveAutoRankContext()
    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local Leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local JoinedBefore = Values and Values:FindFirstChild("JoinedBefore")
    local Scrap = Values and Values:FindFirstChild("Scrap")
    local MaxRank = Values and Values:FindFirstChild("MaxRank")
    local Escapes = Leaderstats and Leaderstats:FindFirstChild("Escapes")
    if not JoinedBefore or not JoinedBefore:IsA("BoolValue") or not JoinedBefore.Value or not Scrap or not Scrap:IsA("NumberValue") or not MaxRank or not MaxRank:IsA("NumberValue") or not Escapes or not Escapes:IsA("NumberValue") or MaxRank.Value >= 20 then
        return nil
    end

    local Requirement
    for _, Rank in pairs(RankInfo) do
        if type(Rank) == "table" and Rank.ID == MaxRank.Value + 1 then
            Requirement = Rank
            break
        end
    end
    if not Requirement or type(Requirement.Scrap) ~= "number" or type(Requirement.Escapes) ~= "number" or type(Requirement.ID) ~= "number" then
        return nil
    end

    local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local RankUI = PlayerGui and PlayerGui:FindFirstChild("RankUI")
    local UIServer = RankUI and RankUI:FindFirstChild("UIServer")
    local IncreaseRank = UIServer and UIServer:FindFirstChild("IncreaseRank")
    if not IncreaseRank or not IncreaseRank:IsA("RemoteEvent") then
        return nil
    end

    return {
        Scrap = Scrap,
        MaxRank = MaxRank,
        Escapes = Escapes,
        Requirement = Requirement,
        IncreaseRank = IncreaseRank
    }
end

local function releaseAutoRankSession(Session)
    if type(Session) == "table" then
        Session.Active = false
    end
    if Environment.MonsterRunnersRankSession == Session then
        Environment.MonsterRunnersRankSession = nil
    end
end

local function inspectAutoRankSession()
    local Session = Environment.MonsterRunnersRankSession
    if type(Session) ~= "table" or not Session.Active then
        return nil
    end
    if Session.JobId ~= game.JobId or Session.PlaceId ~= game.PlaceId or Session.UserId ~= LocalPlayer.UserId or type(Session.ExpectedRank) ~= "number" or type(Session.TargetRank) ~= "number" or type(Session.ExpiresAt) ~= "number" then
        releaseAutoRankSession(Session)
        return nil, "invalid"
    end

    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local MaxRank = Values and Values:FindFirstChild("MaxRank")
    if MaxRank and MaxRank:IsA("NumberValue") then
        if MaxRank.Value >= Session.TargetRank then
            releaseAutoRankSession(Session)
            return nil, "confirmed"
        end
        if MaxRank.Value ~= Session.ExpectedRank then
            releaseAutoRankSession(Session)
            return nil, "changed"
        end
    end
    if os.clock() >= Session.ExpiresAt then
        releaseAutoRankSession(Session)
        return nil, "expired"
    end
    return Session, "active"
end

isAutoRankInFlight = function()
    local Session = Environment.MonsterRunnersRankSession
    return type(Session) == "table" and Session.Active == true
end

local function isCurrentAutoRankContext(Context, ExpectedRank)
    local Current = resolveAutoRankContext()
    return Current ~= nil and Current.Scrap == Context.Scrap and Current.MaxRank == Context.MaxRank and Current.Escapes == Context.Escapes and Current.IncreaseRank == Context.IncreaseRank and Current.Requirement.ID == Context.Requirement.ID and Current.MaxRank.Value == ExpectedRank and Current.Scrap.Value >= Current.Requirement.Scrap and Current.Escapes.Value >= Current.Requirement.Escapes
end

isAutoRankUpgradeReady = function()
    if not Hub.AutoRankUp then
        return false
    end
    local Context = resolveAutoRankContext()
    return Context ~= nil and Context.Scrap.Value >= Context.Requirement.Scrap and Context.Escapes.Value >= Context.Requirement.Escapes
end

local function runAutoRankUp()
    local ActiveSession, SessionState = inspectAutoRankSession()
    if ActiveSession then
        Hub.AutoRankBusy = true
        if ActiveSession.Unconfirmed and Hub.Alive and Hub.AutoRankUp and Hub.Toggles and Hub.Toggles.AutoRankUp and Hub.Toggles.AutoRankUp.Value then
            if os.clock() >= Hub.AutoRankNotifyAt then
                Hub.AutoRankNotifyAt = os.clock() + 10
                notify("Auto Rank", "The previous rank request was not confirmed", 5)
            end
            Hub.Toggles.AutoRankUp:SetValue(false)
        end
        return
    end
    Hub.AutoRankBusy = false
    if SessionState == "expired" then
        if Hub.Alive and Hub.AutoRankUp and Hub.Toggles and Hub.Toggles.AutoRankUp and Hub.Toggles.AutoRankUp.Value then
            if os.clock() >= Hub.AutoRankNotifyAt then
                Hub.AutoRankNotifyAt = os.clock() + 10
                notify("Auto Rank", "The previous rank request was not confirmed", 5)
            end
            Hub.Toggles.AutoRankUp:SetValue(false)
        end
        return
    end
    if SessionState == "confirmed" or SessionState == "changed" then
        Hub.NextAutoRankAttempt = math.max(Hub.NextAutoRankAttempt, os.clock() + 0.25)
    end
    if not Hub.Alive or not Hub.AutoRankUp or Hub.AutoTicketBusy or isAutoTicketInFlight() or isAutoTicketReady() or Hub.AutoRollBusy or getActiveWheelSession() ~= nil or isNativeWheelRolling() or os.clock() < Hub.NextAutoRankAttempt then
        return
    end

    local Context = resolveAutoRankContext()
    if not Context then
        local Values = LocalPlayer:FindFirstChild("BVFolder")
        local MaxRank = Values and Values:FindFirstChild("MaxRank")
        if MaxRank and MaxRank:IsA("NumberValue") and MaxRank.Value >= 20 and Hub.Toggles and Hub.Toggles.AutoRankUp and Hub.Toggles.AutoRankUp.Value then
            notify("Auto Rank", "Maximum rank reached", 4)
            Hub.Toggles.AutoRankUp:SetValue(false)
        end
        return
    end
    if Context.Scrap.Value < Context.Requirement.Scrap or Context.Escapes.Value < Context.Requirement.Escapes then
        return
    end

    Hub.AutoRankBusy = true
    Hub.NextAutoRankAttempt = os.clock() + 1
    local Generation = Hub.AutoRankGeneration
    local ExpectedRank = Context.MaxRank.Value
    local TargetRank = Context.Requirement.ID
    task.spawn(function()
        if not Hub.Alive or not Hub.AutoRankUp or Hub.AutoRankGeneration ~= Generation or Environment.MonsterRunnersFinal ~= Hub or not isCurrentAutoRankContext(Context, ExpectedRank) then
            if Hub.AutoRankGeneration == Generation and Environment.MonsterRunnersFinal == Hub then
                Hub.AutoRankBusy = false
            end
            return
        end

        local Session = {
            Active = true,
            JobId = game.JobId,
            PlaceId = game.PlaceId,
            UserId = LocalPlayer.UserId,
            ExpectedRank = ExpectedRank,
            TargetRank = TargetRank,
            DispatchedAt = os.clock(),
            ExpiresAt = os.clock() + 30
        }
        Environment.MonsterRunnersRankSession = Session
        local Fired = pcall(Context.IncreaseRank.FireServer, Context.IncreaseRank, Context.Requirement.Scrap, Context.Requirement.Escapes, TargetRank)
        if not Fired then
            releaseAutoRankSession(Session)
            if Hub.AutoRankGeneration == Generation and Environment.MonsterRunnersFinal == Hub then
                Hub.AutoRankBusy = false
                if os.clock() >= Hub.AutoRankNotifyAt then
                    Hub.AutoRankNotifyAt = os.clock() + 10
                    notify("Auto Rank", "The rank request could not be sent", 4)
                end
                if Hub.Toggles and Hub.Toggles.AutoRankUp and Hub.Toggles.AutoRankUp.Value then
                    Hub.Toggles.AutoRankUp:SetValue(false)
                end
            end
            return
        end

        local Deadline = os.clock() + 5
        while Context.MaxRank.Parent and Context.MaxRank.Value == ExpectedRank and os.clock() < Deadline do
            task.wait(0.05)
        end
        if Context.MaxRank.Value >= TargetRank then
            releaseAutoRankSession(Session)
            if Hub.AutoRankGeneration == Generation and Environment.MonsterRunnersFinal == Hub then
                Hub.AutoRankBusy = false
                Hub.NextAutoRankAttempt = os.clock() + 0.25
            end
            return
        end

        Session.Unconfirmed = true
        if Hub.AutoRankGeneration == Generation and Environment.MonsterRunnersFinal == Hub then
            Hub.AutoRankBusy = true
            if Hub.Alive and os.clock() >= Hub.AutoRankNotifyAt then
                Hub.AutoRankNotifyAt = os.clock() + 10
                notify("Auto Rank", "The server did not confirm the rank upgrade", 5)
            end
            if Hub.Toggles and Hub.Toggles.AutoRankUp and Hub.Toggles.AutoRankUp.Value then
                Hub.Toggles.AutoRankUp:SetValue(false)
            end
        end
    end)
end

local function resolveAutoRollContext()
    if not Hub.Alive or not Hub.AutoRoll or Hub.AutoRollBusy or Hub.AutoTicketBusy or isAutoTicketInFlight() or isAutoTicketReady() or Hub.AutoRankBusy or isAutoRankInFlight() or isAutoRankUpgradeReady() or getActiveWheelSession() ~= nil or isNativeWheelRolling() or os.clock() < Hub.NextAutoRollAttempt or Cutscene.Value or RoundEnded.Value then
        return nil
    end

    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local JoinedBefore = Values and Values:FindFirstChild("JoinedBefore")
    local Scrap = Values and Values:FindFirstChild("Scrap")
    local Rolls = Values and Values:FindFirstChild("Rolls")
    local InShop = LocalPlayer:FindFirstChild("InShop")
    if not JoinedBefore or not JoinedBefore:IsA("BoolValue") or not JoinedBefore.Value or not Scrap or not Rolls or not Scrap:IsA("NumberValue") or not Rolls:IsA("NumberValue") or not InShop or not InShop:IsA("BoolValue") or InShop.Value or Rolls.Value < 1 and Scrap.Value < 100 then
        return nil
    end

    local ShopArea = Workspace:FindFirstChild("ShopArea")
    local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local ShopUI = PlayerGui and PlayerGui:FindFirstChild("ShopUI")
    local UIServer = ShopUI and ShopUI:FindFirstChild("UIServer")
    local AwardItemEvent = UIServer and UIServer:FindFirstChild("AwardItemEvent")
    if not AwardItemEvent or not AwardItemEvent:IsA("RemoteEvent") then
        return nil
    end

    local Wheel = ShopArea and ShopArea:FindFirstChild("Wheel")
    local WheelPart = Wheel and Wheel:FindFirstChild("Wheel")
    local SurfaceGui = WheelPart and WheelPart:FindFirstChild("SurfaceGui")
    local Set1 = SurfaceGui and SurfaceGui:FindFirstChild("Set1Image")
    local Set2 = SurfaceGui and SurfaceGui:FindFirstChild("Set2Image")
    if not Set1 or not Set2 or Set1.Visible == Set2.Visible then
        return nil
    end

    local ShopServer = ShopArea:FindFirstChild("ShopServer")
    local RecentSet = ShopServer and ShopServer:FindFirstChild("RecentSet")
    local VisibleSet = Set1.Visible and "Set1Image" or "Set2Image"
    if not RecentSet or not RecentSet:IsA("StringValue") or RecentSet.Value ~= VisibleSet then
        return nil
    end

    local RollModule, ItemChance = getNativeRollModule()
    if not RollModule or not ItemChance or RollModule.rolling then
        return nil
    end

    return {
        ShopUI = ShopUI,
        ShopArea = ShopArea,
        Wheel = Wheel,
        SurfaceGui = SurfaceGui,
        UIServer = UIServer,
        AwardItemEvent = AwardItemEvent,
        RollModule = RollModule,
        ItemChance = ItemChance,
        InShop = InShop,
        Set1 = Set1,
        Set2 = Set2,
        RecentSet = RecentSet,
        Scrap = Scrap,
        Rolls = Rolls
    }
end

local function isAutoRollContextReady(Context, Generation, Session)
    if not Hub.Alive or not Hub.AutoRoll or Hub.AutoRollGeneration ~= Generation or Environment.MonsterRunnersFinal ~= Hub or Session and Environment.MonsterRunnersWheelSession ~= Session or Hub.AutoTicketBusy or isAutoTicketInFlight() or isAutoTicketReady() or Hub.AutoRankBusy or isAutoRankInFlight() or isAutoRankUpgradeReady() or Cutscene.Value or RoundEnded.Value then
        return false
    end
    local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local ShopUI = PlayerGui and PlayerGui:FindFirstChild("ShopUI")
    local UIServer = ShopUI and ShopUI:FindFirstChild("UIServer")
    local AwardItemEvent = UIServer and UIServer:FindFirstChild("AwardItemEvent")
    if ShopUI ~= Context.ShopUI or UIServer ~= Context.UIServer or AwardItemEvent ~= Context.AwardItemEvent or not AwardItemEvent or not AwardItemEvent:IsA("RemoteEvent") then
        return false
    end
    local ShopArea = Workspace:FindFirstChild("ShopArea")
    local Wheel = ShopArea and ShopArea:FindFirstChild("Wheel")
    local WheelPart = Wheel and Wheel:FindFirstChild("Wheel")
    local SurfaceGui = WheelPart and WheelPart:FindFirstChild("SurfaceGui")
    local Set1 = SurfaceGui and SurfaceGui:FindFirstChild("Set1Image")
    local Set2 = SurfaceGui and SurfaceGui:FindFirstChild("Set2Image")
    local ShopServer = ShopArea and ShopArea:FindFirstChild("ShopServer")
    local RecentSet = ShopServer and ShopServer:FindFirstChild("RecentSet")
    if ShopArea ~= Context.ShopArea or Wheel ~= Context.Wheel or SurfaceGui ~= Context.SurfaceGui or Set1 ~= Context.Set1 or Set2 ~= Context.Set2 or RecentSet ~= Context.RecentSet then
        return false
    end
    if not Context.Scrap.Parent or not Context.Rolls.Parent or LocalPlayer:FindFirstChild("InShop") ~= Context.InShop or Context.InShop.Value or Context.Rolls.Value < 1 and Context.Scrap.Value < 100 or Context.RollModule.rolling then
        return false
    end
    local CurrentRollModule, CurrentItemChance = getNativeRollModule()
    if CurrentRollModule ~= Context.RollModule or CurrentItemChance ~= Context.ItemChance then
        return false
    end
    if not Context.Set1.Parent or not Context.Set2.Parent or Context.Set1.Visible == Context.Set2.Visible then
        return false
    end
    local VisibleSet = Context.Set1.Visible and "Set1Image" or "Set2Image"
    if not Context.RecentSet.Parent or Context.RecentSet.Value ~= VisibleSet then
        return false
    end
    return true
end

local function stopAutoRoll(Generation, Message)
    if not Hub.Alive or Hub.AutoRollGeneration ~= Generation then
        return
    end
    if os.clock() >= Hub.AutoRollNotifyAt then
        Hub.AutoRollNotifyAt = os.clock() + 10
        notify("Auto Roll", Message, 5)
    end
    if Hub.Toggles and Hub.Toggles.AutoRoll and Hub.Toggles.AutoRoll.Value then
        Hub.Toggles.AutoRoll:SetValue(false)
    else
        Hub.AutoRoll = false
        Hub.AutoRollGeneration += 1
        Hub.AutoRollBusy = false
    end
end

local function runAutoRoll()
    local ExistingSession = getActiveWheelSession()
    if ExistingSession then
        Hub.AutoRollBusy = ExistingSession.Background == true
        if ExistingSession.Unconfirmed and Hub.Alive and Hub.AutoRoll and Hub.Toggles and Hub.Toggles.AutoRoll and Hub.Toggles.AutoRoll.Value then
            if os.clock() >= Hub.AutoRollNotifyAt then
                Hub.AutoRollNotifyAt = os.clock() + 10
                notify("Auto Roll", "The previous roll was not confirmed", 5)
            end
            Hub.Toggles.AutoRoll:SetValue(false)
        end
        return
    end
    Hub.AutoRollBusy = false
    Hub.NextAutoRollAttempt = math.max(Hub.NextAutoRollAttempt, getAutoRollCooldown())
    local Context = resolveAutoRollContext()
    if not Context then
        return
    end

    Hub.AutoRollBusy = true
    Hub.NextAutoRollAttempt = os.clock() + 1
    local Generation = Hub.AutoRollGeneration
    local Session = {
        Active = true,
        Background = true,
        JobId = game.JobId,
        PlaceId = game.PlaceId,
        UserId = LocalPlayer.UserId,
        RollsBefore = Context.Rolls.Value,
        ScrapBefore = Context.Scrap.Value,
        LastRolls = Context.Rolls.Value,
        LastScrap = Context.Scrap.Value,
        RollsSpent = 0,
        ScrapSpent = 0,
        Payment = Context.Rolls.Value >= 1 and "Roll" or "Scrap",
        ExpiresAt = os.clock() + 30
    }
    Environment.MonsterRunnersWheelSession = Session

    task.spawn(function()
        local Cleaned = false

        local function OwnsHubState()
            return Hub.AutoRollGeneration == Generation and Environment.MonsterRunnersFinal == Hub
        end

        local function IsCurrent()
            return OwnsHubState() and Hub.Alive and Hub.AutoRoll
        end

        local function IsAccepted()
            if Session.Payment == "Roll" then
                return Session.RollsSpent == 1 and Session.ScrapSpent == 0
            end
            return Session.ScrapSpent == 100 and Session.RollsSpent == 0
        end

        local function Cleanup(KeepSession)
            if Cleaned then
                return
            end
            Cleaned = true
            if not KeepSession then
                releaseWheelSession(Session)
            end
            if OwnsHubState() then
                Hub.AutoRollBusy = false
            end
        end

        local function PreserveSession()
            Session.Unconfirmed = true
            Cleanup(true)
            task.spawn(function()
                while Environment.MonsterRunnersWheelSession == Session and Session.Active do
                    local Remaining = Session.ExpiresAt - os.clock()
                    if Remaining > 0 then
                        task.wait(math.min(Remaining, 5))
                    elseif isNativeWheelRolling() then
                        Session.ExpiresAt = os.clock() + 20
                    else
                        releaseWheelSession(Session)
                        break
                    end
                end
            end)
        end

        local Success, ErrorMessage = xpcall(function()
        if not isAutoRollContextReady(Context, Generation, Session) then
            Cleanup()
            return
        end

        Session.RollsConnection = Context.Rolls:GetPropertyChangedSignal("Value"):Connect(function()
            local Current = Context.Rolls.Value
            if Current < Session.LastRolls then
                Session.RollsSpent += Session.LastRolls - Current
            end
            Session.LastRolls = Current
        end)
        Session.ScrapConnection = Context.Scrap:GetPropertyChangedSignal("Value"):Connect(function()
            local Current = Context.Scrap.Value
            if Current < Session.LastScrap then
                Session.ScrapSpent += Session.LastScrap - Current
            end
            Session.LastScrap = Current
        end)

        if not isAutoRollContextReady(Context, Generation, Session) then
            Cleanup()
            return
        end

        local Selected = pcall(Context.ItemChance.getItem, Context.SurfaceGui)
        if not Selected or not isAutoRollContextReady(Context, Generation, Session) then
            local Current = IsCurrent()
            Cleanup()
            if Current then
                Hub.NextAutoRollAttempt = os.clock() + 10
                stopAutoRoll(Generation, "The wheel item could not be selected")
            end
            return
        end

        local Item = Context.ItemChance.itemRolled
        local Rarity = Context.ItemChance.rarityRolled
        if type(Item) ~= "string" or Item == "" or type(Rarity) ~= "string" or Rarity == "" then
            local Current = IsCurrent()
            Cleanup()
            if Current then
                Hub.NextAutoRollAttempt = os.clock() + 10
                stopAutoRoll(Generation, "The wheel item was invalid")
            end
            return
        end

        Session.Dispatched = true
        Session.DispatchedAt = os.clock()
        local Fired = pcall(Context.AwardItemEvent.FireServer, Context.AwardItemEvent, Item, Rarity)
        if not Fired then
            local Current = IsCurrent()
            PreserveSession()
            if Current then
                Hub.NextAutoRollAttempt = os.clock() + 10
                stopAutoRoll(Generation, "The roll request could not be confirmed")
            end
            return
        end
        local ReadyAt = Session.DispatchedAt + AutoRollDelay
        Hub.NextAutoRollAttempt = math.max(Hub.NextAutoRollAttempt, ReadyAt)
        Environment.MonsterRunnersRollCooldown = {
            JobId = game.JobId,
            PlaceId = game.PlaceId,
            UserId = LocalPlayer.UserId,
            ReadyAt = ReadyAt
        }

        local AcceptDeadline = os.clock() + 6
        local NativeOverlap = Context.RollModule.rolling
        while not NativeOverlap and not IsAccepted() and os.clock() < AcceptDeadline do
            task.wait(0.05)
            NativeOverlap = Context.RollModule.rolling
        end

        local Current = IsCurrent()
        local Accepted = not NativeOverlap and IsAccepted()
        if not Accepted then
            Session.Unconfirmed = true
            Session.NativeOverlap = NativeOverlap
        end
        if Accepted then
            Cleanup(false)
        else
            PreserveSession()
        end
        if not Current then
            return
        end
        if not Accepted then
            Hub.NextAutoRollAttempt = os.clock() + 10
            stopAutoRoll(Generation, "The server did not confirm the roll cost")
            return
        end
        Hub.NextAutoRollAttempt = math.max(Hub.NextAutoRollAttempt, Session.DispatchedAt + AutoRollDelay)
        end, debug.traceback)
        if not Success then
            local Current = IsCurrent()
            if Session.Dispatched then
                PreserveSession()
            else
                Cleanup(false)
            end
            if Current then
                Hub.NextAutoRollAttempt = os.clock() + 10
                stopAutoRoll(Generation, "The background roll stopped")
            end
        end
    end)
end

Hub.Privacy.Alias = "Anonymous"
Hub.Privacy.Hidden = "Hidden"

function Hub.Privacy:ReplaceToken(Text, Needle, Replacement)
    if type(Text) ~= "string" or type(Needle) ~= "string" or Needle == "" then
        return Text
    end
    local LowerText = string.lower(Text)
    local LowerNeedle = string.lower(Needle)
    local Pieces = {}
    local Last = 1
    local SearchAt = 1
    while true do
        local StartAt, EndAt = string.find(LowerText, LowerNeedle, SearchAt, true)
        if not StartAt then
            break
        end
        local Before = StartAt > 1 and string.sub(Text, StartAt - 1, StartAt - 1) or ""
        local After = EndAt < #Text and string.sub(Text, EndAt + 1, EndAt + 1) or ""
        local First = string.sub(Needle, 1, 1)
        local LastCharacter = string.sub(Needle, -1)
        local BeforeBlocked = First:match("[%w_]") and Before:match("[%w_]")
        local AfterBlocked = LastCharacter:match("[%w_]") and After:match("[%w_]")
        if not BeforeBlocked and not AfterBlocked then
            Pieces[#Pieces + 1] = string.sub(Text, Last, StartAt - 1)
            Pieces[#Pieces + 1] = Replacement
            Last = EndAt + 1
            SearchAt = EndAt + 1
        else
            SearchAt = StartAt + 1
        end
    end
    if #Pieces == 0 then
        return Text
    end
    Pieces[#Pieces + 1] = string.sub(Text, Last)
    return table.concat(Pieces)
end

function Hub.Privacy:MaskIdentity(Text)
    if type(Text) ~= "string" then
        return Text
    end
    local Result = self:ReplaceToken(Text, tostring(LocalPlayer.UserId), self.Hidden)
    if #LocalPlayer.DisplayName >= #LocalPlayer.Name then
        Result = self:ReplaceToken(Result, LocalPlayer.DisplayName, self.Alias)
        Result = self:ReplaceToken(Result, LocalPlayer.Name, self.Alias)
    else
        Result = self:ReplaceToken(Result, LocalPlayer.Name, self.Alias)
        Result = self:ReplaceToken(Result, LocalPlayer.DisplayName, self.Alias)
    end
    return Result
end

function Hub.Privacy:GetNative(Object, Property)
    local Properties = Hub.PrivacyRecords[Object]
    local Record = Properties and Properties[Property]
    local Success, Current = pcall(function()
        return Object[Property]
    end)
    if not Success then
        return nil
    end
    if Record and Record.Forced ~= nil and Current == Record.Forced then
        return Record.Native
    end
    return Current
end

function Hub.Privacy:Evaluate(Object, Property, Record)
    if not Hub.PrivacyMode or Hub.PrivacyRestoring or not Object or not Object.Parent then
        return
    end
    local Success, Current = pcall(function()
        return Object[Property]
    end)
    if not Success then
        return
    end
    local Native = Current
    if Record.Forced ~= nil and Current == Record.Forced then
        Native = Record.Native
    end
    local MaskedSuccess, Forced = pcall(Record.Masker, Native, Object)
    if not MaskedSuccess then
        return
    end
    if Forced ~= nil then
        if Current ~= Record.Forced then
            Record.Native = Current
        end
        Record.Forced = Forced
        if Current ~= Forced then
            Record.Writing = true
            pcall(function()
                Object[Property] = Forced
            end)
            Record.Writing = false
        end
    else
        if Record.Forced ~= nil and Current == Record.Forced then
            Record.Writing = true
            pcall(function()
                Object[Property] = Record.Native
            end)
            Record.Writing = false
        elseif Current ~= Record.Forced then
            Record.Native = Current
        end
        Record.Forced = nil
    end
end

function Hub.Privacy:Bind(Object, Property, Masker)
    if not Hub.PrivacyMode or not Object or not Object.Parent then
        return
    end
    local Properties = Hub.PrivacyRecords[Object]
    if not Properties then
        Properties = {}
        Hub.PrivacyRecords[Object] = Properties
    end
    local Record = Properties[Property]
    if not Record then
        local Success, Native = pcall(function()
            return Object[Property]
        end)
        if not Success then
            return
        end
        Record = {
            Native = Native,
            Forced = nil,
            Writing = false,
            Masker = Masker
        }
        Properties[Property] = Record
        local Connected, Connection = pcall(function()
            return Object:GetPropertyChangedSignal(Property):Connect(function()
                if Hub.PrivacyMode and not Hub.PrivacyRestoring and not Record.Writing then
                    Hub.Privacy:Evaluate(Object, Property, Record)
                end
            end)
        end)
        if Connected and Connection then
            Hub.PrivacyConnections[#Hub.PrivacyConnections + 1] = Connection
        end
    else
        Record.Masker = Masker
    end
    self:Evaluate(Object, Property, Record)
end

function Hub.Privacy:GetScreenName(Object)
    local Current = Object
    while Current and Current ~= LocalPlayer do
        if Current:IsA("ScreenGui") then
            return Current.Name
        end
        Current = Current.Parent
    end
    return nil
end

function Hub.Privacy:GetTextMask(Object, Text)
    if not Hub.PrivacyMode or type(Text) ~= "string" then
        return nil
    end
    local ScreenName = self:GetScreenName(Object)
    if ScreenName == "CutsceneUI" and SelectedMonster.Value == LocalPlayer.Name then
        if Object.Name == "DisplayName" then
            return self.Alias
        end
        if Object.Name == "UserName" then
            return "(" .. self.Alias .. ")"
        end
    end
    if ScreenName == "SettingsUI" and (Object.Name == "KillsText" or Object.Name == "EscapesText") then
        return self.Hidden
    end
    if ScreenName == "RankUI" and (Object.Name == "EscapesText" or Object.Name == "ScrapText" or Object.Name == "ScrapPerEscapeAmount") then
        return self.Hidden
    end
    if ScreenName == "MonsterChanceUI" and Object.Name == "ChanceText" then
        return "Monster Chance: " .. self.Hidden
    end
    if ScreenName == "MonsterScrap" and Object.Name == "ScrapValue" then
        return self.Hidden
    end
    if ScreenName == "ClassesUI" and (Object.Name == "ScrapText" or Object.Name == "TextLabel" and Object.Parent and Object.Parent.Name == "CurrencyFrame") then
        return self.Hidden
    end
    if ScreenName == "TicketExchangeUI" and Object.Name == "TicketsLabel" then
        return "Tickets: " .. self.Hidden
    end
    if ScreenName == "TicketExchangeUI" and Object.Name == "ScrapLabel" then
        return "Scrap: " .. self.Hidden
    end
    if ScreenName == "ShopUI" and Object.Parent and Object.Parent.Name == "kills" and tonumber(Text) then
        return self.Hidden
    end
    if ScreenName == "ShopUI" and Object.Name == "ScrapCost" and string.find(string.lower(Text), "rolls left", 1, true) then
        return "Rolls Left: " .. self.Hidden
    end
    if Object.Name == "ScrapLabel" then
        local ShopArea = Workspace:FindFirstChild("ShopArea")
        local ScrapCount = ShopArea and ShopArea:FindFirstChild("ScrapCount")
        if ScrapCount and Object:IsDescendantOf(ScrapCount) then
            return self.Hidden
        end
    end
    local Masked = self:MaskIdentity(Text)
    return Masked ~= Text and Masked or nil
end

function Hub.Privacy:IsLocalWorldRow(Row)
    if not Row or not Row.Parent or Row.Name ~= "PlayerFrame" then
        return false
    end
    local NameLabel = Row:FindFirstChild("Name")
    if not NameLabel or not NameLabel:IsA("TextLabel") then
        return false
    end
    local Text = self:GetNative(NameLabel, "Text")
    return type(Text) == "string" and self:MaskIdentity(Text) ~= Text
end

function Hub.Privacy:ShouldHideRow(Row)
    if not Hub.PrivacyMode or not Row or not Row.Parent then
        return nil
    end
    local Name = Row.Name
    if Name == "PlayerEntry_" .. LocalPlayer.UserId or Name == "PlayerLabel" .. LocalPlayer.Name or Name == "player_" .. LocalPlayer.UserId or Name == "player" .. LocalPlayer.UserId then
        return false
    end
    if Name == "PlayerFrame" and self:IsLocalWorldRow(Row) then
        return false
    end
    if Name == "Item" then
        local SettingsShield = game:GetService("CoreGui"):FindFirstChild("SettingsClippingShield", true)
        if SettingsShield and Row:IsDescendantOf(SettingsShield) then
            for _, Descendant in ipairs(Row:GetDescendants()) do
                if Descendant:IsA("TextLabel") or Descendant:IsA("TextButton") or Descendant:IsA("TextBox") then
                    local Text = self:GetNative(Descendant, "Text")
                    if type(Text) == "string" and self:MaskIdentity(Text) ~= Text then
                        return false
                    end
                end
            end
        end
    end
    return nil
end

function Hub.Privacy:GetRow(Object)
    local SettingsShield = game:GetService("CoreGui"):FindFirstChild("SettingsClippingShield", true)
    local EscapesBoard = Workspace:FindFirstChild("EscapesLeaderboard")
    local KillsBoard = Workspace:FindFirstChild("KillsLeaderboard")
    local InSettings = SettingsShield and Object:IsDescendantOf(SettingsShield)
    local InBoard = EscapesBoard and Object:IsDescendantOf(EscapesBoard) or KillsBoard and Object:IsDescendantOf(KillsBoard)
    local Current = Object
    for _ = 1, 18 do
        if not Current then
            break
        end
        if Current:IsA("GuiObject") then
            local Name = Current.Name
            if Name == "PlayerEntry_" .. LocalPlayer.UserId or Name == "PlayerLabel" .. LocalPlayer.Name or Name == "player_" .. LocalPlayer.UserId or Name == "player" .. LocalPlayer.UserId then
                return Current
            end
            if InSettings and Name == "Item" then
                return Current
            end
            if InBoard and Name == "PlayerFrame" then
                return Current
            end
        end
        Current = Current.Parent
    end
    return nil
end

function Hub.Privacy.RowMasker(_, Object)
    return Hub.Privacy:ShouldHideRow(Object)
end

function Hub.Privacy.TextMasker(Text, Object)
    local Masked = Hub.Privacy:GetTextMask(Object, Text)
    local Row = Hub.Privacy:GetRow(Object)
    if Row then
        local Properties = Hub.PrivacyRecords[Row]
        if Masked ~= nil or Properties and Properties.Visible then
            Hub.Privacy:Bind(Row, "Visible", Hub.Privacy.RowMasker)
        end
        return nil
    end
    return Masked
end

function Hub.Privacy.ImageMasker(Image, Object)
    local Row = Hub.Privacy:GetRow(Object)
    if Hub.PrivacyMode and type(Image) == "string" and string.find(Image, tostring(LocalPlayer.UserId), 1, true) then
        if Row then
            Hub.Privacy:Bind(Row, "Visible", Hub.Privacy.RowMasker)
            return nil
        end
        return ""
    end
    local Properties = Row and Hub.PrivacyRecords[Row]
    if Properties and Properties.Visible then
        Hub.Privacy:Bind(Row, "Visible", Hub.Privacy.RowMasker)
    end
    return nil
end

function Hub.Privacy.DisplayMasker()
    if Hub.PrivacyMode then
        return Enum.HumanoidDisplayDistanceType.None
    end
    return nil
end

function Hub.Privacy:ApplyObject(Object)
    if not Hub.PrivacyMode or not Object or not Object.Parent then
        return
    end
    if Object:IsA("GuiObject") and (Object.Name == "PlayerEntry_" .. LocalPlayer.UserId or Object.Name == "PlayerLabel" .. LocalPlayer.Name or Object.Name == "player_" .. LocalPlayer.UserId or Object.Name == "player" .. LocalPlayer.UserId) then
        self:Bind(Object, "Visible", self.RowMasker)
        return
    end
    if Object:IsA("TextLabel") or Object:IsA("TextButton") then
        self:Bind(Object, "Text", self.TextMasker)
        return
    end
    if Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
        self:Bind(Object, "Image", self.ImageMasker)
    end
end

function Hub.Privacy:ScanRoot(Root)
    if not Hub.PrivacyMode or not Root or not Root.Parent then
        return
    end
    self:ApplyObject(Root)
    local Success, Descendants = pcall(Root.GetDescendants, Root)
    if Success then
        for _, Object in ipairs(Descendants) do
            self:ApplyObject(Object)
        end
    end
end

function Hub.Privacy:WatchRoot(Root, Scan)
    if not Hub.PrivacyMode or not Root or Hub.PrivacyWatchedRoots[Root] then
        return
    end
    Hub.PrivacyWatchedRoots[Root] = true
    local Success, Connection = pcall(function()
        return Root.DescendantAdded:Connect(function(Object)
            if Hub.PrivacyMode then
                task.defer(function()
                    if Hub.PrivacyMode and Hub.Alive and Object.Parent then
                        Hub.Privacy:ApplyObject(Object)
                    end
                end)
            end
        end)
    end)
    if Success and Connection then
        Hub.PrivacyConnections[#Hub.PrivacyConnections + 1] = Connection
    end
    if Scan then
        self:ScanRoot(Root)
    end
end

function Hub.Privacy:Sync()
    if not Hub.PrivacyMode then
        return
    end
    for Index = #Hub.PrivacyConnections, 1, -1 do
        local Connection = Hub.PrivacyConnections[Index]
        local Success, Connected = pcall(function()
            return Connection.Connected
        end)
        if not Success or not Connected then
            table.remove(Hub.PrivacyConnections, Index)
        end
    end
    local CoreGui = game:GetService("CoreGui")
    local PlayerEntry = CoreGui:FindFirstChild("PlayerEntry_" .. LocalPlayer.UserId, true)
    if PlayerEntry then
        self:ApplyObject(PlayerEntry)
    end
    local Character = LocalPlayer.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    if Humanoid then
        self:Bind(Humanoid, "DisplayDistanceType", self.DisplayMasker)
    end
    local CharacterNameTag = Character and Character:FindFirstChild("NameTag", true)
    if CharacterNameTag then
        self:ScanRoot(CharacterNameTag)
    end
    local CustomizationArea = Workspace:FindFirstChild("CustomizationArea")
    local Preview = CustomizationArea and CustomizationArea:FindFirstChild("PlayerModel")
    local PreviewNameTag = Preview and Preview:FindFirstChild("NameTag", true)
    if PreviewNameTag then
        self:ScanRoot(PreviewNameTag)
    end
    local CutsceneUI = LocalPlayer:FindFirstChildOfClass("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("CutsceneUI")
    if CutsceneUI then
        local DisplayName = CutsceneUI:FindFirstChild("DisplayName", true)
        local UserName = CutsceneUI:FindFirstChild("UserName", true)
        if DisplayName then
            self:ApplyObject(DisplayName)
        end
        if UserName then
            self:ApplyObject(UserName)
        end
    end
    local ShopArea = Workspace:FindFirstChild("ShopArea")
    local ScrapCount = ShopArea and ShopArea:FindFirstChild("ScrapCount")
    if ScrapCount then
        local ScrapLabel = ScrapCount:FindFirstChild("ScrapLabel", true)
        if ScrapLabel then
            self:ApplyObject(ScrapLabel)
        end
    end
    if Hub.Watermark then
        pcall(Hub.Watermark.ShowName, Hub.Watermark, false)
    end
end

function Hub.Privacy:Enable()
    if Hub.PrivacyMode then
        self:Sync()
        return
    end
    Hub.PrivacyMode = true
    Hub.PrivacyRestoring = false
    local CoreGui = game:GetService("CoreGui")
    local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    self:WatchRoot(CoreGui, true)
    if PlayerGui then
        self:WatchRoot(PlayerGui, true)
    end
    local Character = LocalPlayer.Character
    if Character then
        self:WatchRoot(Character, true)
    end
    for _, Name in ipairs({"CustomizationArea", "CutsceneRoom", "EscapesLeaderboard", "KillsLeaderboard"}) do
        local Root = Workspace:FindFirstChild(Name)
        if Root then
            self:WatchRoot(Root, true)
        end
    end
    local ShopArea = Workspace:FindFirstChild("ShopArea")
    local ScrapCount = ShopArea and ShopArea:FindFirstChild("ScrapCount")
    if ScrapCount then
        self:WatchRoot(ScrapCount, true)
    end
    local WorkspaceConnection = Workspace.ChildAdded:Connect(function(Child)
        if Hub.PrivacyMode and (Child == LocalPlayer.Character or Child.Name == "CustomizationArea" or Child.Name == "CutsceneRoom" or Child.Name == "EscapesLeaderboard" or Child.Name == "KillsLeaderboard") then
            task.defer(function()
                if Hub.PrivacyMode and Child.Parent then
                    Hub.Privacy:WatchRoot(Child, true)
                end
            end)
        end
    end)
    Hub.PrivacyConnections[#Hub.PrivacyConnections + 1] = WorkspaceConnection
    local WorkspaceDescendantConnection = Workspace.DescendantAdded:Connect(function(Object)
        if Hub.PrivacyMode and (Object:IsA("TextLabel") or Object:IsA("TextButton") or Object:IsA("ImageLabel") or Object:IsA("ImageButton")) then
            task.defer(function()
                if not Hub.PrivacyMode or not Object.Parent then
                    return
                end
                local Surface = Object:FindFirstAncestorWhichIsA("SurfaceGui") or Object:FindFirstAncestorWhichIsA("BillboardGui")
                if Surface then
                    Hub.Privacy:ApplyObject(Object)
                end
            end)
        end
    end)
    Hub.PrivacyConnections[#Hub.PrivacyConnections + 1] = WorkspaceDescendantConnection
    for _, Object in ipairs(Workspace:GetDescendants()) do
        if Object:IsA("TextLabel") or Object:IsA("TextButton") or Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
            local Surface = Object:FindFirstAncestorWhichIsA("SurfaceGui") or Object:FindFirstAncestorWhichIsA("BillboardGui")
            if Surface then
                self:ApplyObject(Object)
            end
        end
    end
    local MenuConnection = GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function()
        if Hub.PrivacyMode and GuiService.MenuIsOpen then
            task.defer(function()
                if Hub.PrivacyMode then
                    local SettingsShield = CoreGui:FindFirstChild("SettingsClippingShield", true)
                    if SettingsShield then
                        Hub.Privacy:ScanRoot(SettingsShield)
                    end
                end
            end)
        end
    end)
    Hub.PrivacyConnections[#Hub.PrivacyConnections + 1] = MenuConnection
    self:Sync()
end

function Hub.Privacy:Disable()
    Hub.PrivacyMode = false
    Hub.PrivacyRestoring = true
    for _, Connection in ipairs(Hub.PrivacyConnections) do
        pcall(Connection.Disconnect, Connection)
    end
    table.clear(Hub.PrivacyConnections)
    for Object, Properties in pairs(Hub.PrivacyRecords) do
        if Object and Object.Parent then
            for Property, Record in pairs(Properties) do
                local Success, Current = pcall(function()
                    return Object[Property]
                end)
                if Success and Record.Forced ~= nil and Current == Record.Forced then
                    pcall(function()
                        Object[Property] = Record.Native
                    end)
                end
            end
        end
    end
    Hub.PrivacyRecords = setmetatable({}, {__mode = "k"})
    Hub.PrivacyWatchedRoots = setmetatable({}, {__mode = "k"})
    Hub.PrivacyRestoring = false
    if Hub.Watermark then
        local ShowName = Toggles.WatermarkShowName == nil or Toggles.WatermarkShowName.Value
        pcall(Hub.Watermark.ShowName, Hub.Watermark, ShowName)
    end
end

local function normalizeWebhookURL(Value)
    if type(Value) ~= "string" then
        return ""
    end
    return Value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function isValidWebhookURL(Value)
    local URL = normalizeWebhookURL(Value)
    return URL:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+$") ~= nil
end

local function getCurrentRankName(RankId)
    for _, Rank in pairs(RankInfo) do
        if type(Rank) == "table" and Rank.ID == RankId and type(Rank.Name) == "string" then
            return Rank.Name
        end
    end
    return "Unknown"
end

local function formatSessionDuration(Elapsed)
    local Hours = math.floor(Elapsed / 3600)
    local Minutes = math.floor(Elapsed % 3600 / 60)
    local Seconds = math.floor(Elapsed % 60)
    return string.format("%02d:%02d:%02d", Hours, Minutes, Seconds)
end

local function formatWebhookRate(Value, Elapsed)
    if Elapsed < 60 then
        return "Pending"
    end
    return tostring(math.floor(Value * 3600 / math.max(Elapsed, 1) + 0.5))
end

local function buildWebhookPayload(IsTest, Reason)
    local Fields = {}
    local function addField(Name, Value, Inline)
        Fields[#Fields + 1] = {
            name = Name,
            value = Value,
            inline = Inline == true
        }
    end

    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local Leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local Wins = Leaderstats and Leaderstats:FindFirstChild("Escapes")
    local Kills = Values and Values:FindFirstChild("Kills")
    local Deaths = Values and Values:FindFirstChild("Deaths")
    local Scrap = Values and Values:FindFirstChild("Scrap")
    local Tickets = Values and Values:FindFirstChild("Tickets")
    local Rolls = Values and Values:FindFirstChild("Rolls")
    local Chance = Values and Values:FindFirstChild("Chance")
    local MaxRank = Values and Values:FindFirstChild("MaxRank")
    local MonsterEarnings = LocalPlayer:FindFirstChild("MonsterEarnings")
    local Elapsed = Hub.StatsInitialized and math.max(os.clock() - Hub.StatsStartedAt, 0) or 0

    if Hub.WebhookPlayerInfo then
        if Hub.PrivacyMode then
            addField("Player", "Privacy Mode enabled", false)
        else
            addField("Player", "||" .. LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")||\nUser ID: ||" .. LocalPlayer.UserId .. "||\nAccount Age: ||" .. LocalPlayer.AccountAge .. " days||", false)
        end
    end
    if Hub.PrivacyMode then
        return {
            username = "Monster Runners",
            allowed_mentions = {parse = {}},
            embeds = {{
                title = IsTest and "Webhook Test" or "Player Statistics",
                description = (IsTest and "Test message sent successfully from the script." or tostring(Reason or "Statistics Updated")) .. "\nPrivacy Mode is hiding player statistics.",
                color = 5676287,
                fields = Fields,
                footer = {text = "Monster Runners"},
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        }
    end
    if Hub.WebhookWins then
        addField("Wins", "Total: " .. (Wins and Wins.Value or 0) .. "\nSession: +" .. Hub.StatsEarned.Wins .. "\nEstimated / Hour: " .. formatWebhookRate(Hub.StatsEarned.Wins, Elapsed), true)
    end
    if Hub.WebhookKills then
        addField("Combat", "Kills: " .. (Kills and Kills.Value or 0) .. "\nSession Kills: +" .. Hub.StatsEarned.Kills .. "\nDeaths: " .. (Deaths and Deaths.Value or 0) .. "\nEstimated Kills / Hour: " .. formatWebhookRate(Hub.StatsEarned.Kills, Elapsed), true)
    end
    if Hub.WebhookScrap then
        addField("Scrap", "Balance: " .. (Scrap and Scrap.Value or 0) .. "\nSession Earned: +" .. Hub.StatsEarned.Scrap .. "\nPending Monster Earnings: " .. (MonsterEarnings and MonsterEarnings.Value or 0) .. "\nEstimated / Hour: " .. formatWebhookRate(Hub.StatsEarned.Scrap, Elapsed), true)
    end
    if Hub.WebhookEconomy then
        addField("Economy", "Tickets: " .. (Tickets and Tickets.Value or 0) .. "\nRolls: " .. (Rolls and Rolls.Value or 0) .. "\nMonster Chance: " .. (Chance and Chance.Value or 0), true)
    end
    if Hub.WebhookRank then
        local RankId = MaxRank and MaxRank.Value or 0
        addField("Rank", getCurrentRankName(RankId) .. "\nRank ID: " .. RankId, true)
    end
    if Hub.WebhookGameState then
        local TeamName = LocalPlayer.Team and LocalPlayer.Team.Name or "None"
        local ServerType = IsPublicServer and "Public" or "Private"
        addField("Game State", "Round: " .. tostring(RoundState.Value) .. "\nTeam: " .. TeamName .. "\nPlayers: " .. #Players:GetPlayers() .. "\nServer: " .. ServerType .. "\nSession Time: " .. formatSessionDuration(Elapsed), false)
    end

    local Description = IsTest and "Test message sent successfully from the script." or tostring(Reason or "Statistics Updated")
    if #Fields == 0 then
        Description ..= "\nNo statistic categories are enabled."
    end
    return {
        username = "Monster Runners",
        allowed_mentions = {parse = {}},
        embeds = {{
            title = IsTest and "Webhook Test" or "Player Statistics",
            description = Description,
            color = 5676287,
            fields = Fields,
            footer = {text = "Monster Runners"},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }
end

local function sendWebhook(IsTest, Reason)
    if Hub.WebhookBusy then
        if IsTest then
            notify("Webhook", "Another webhook request is in progress", 3)
        end
        return
    end
    if not HttpRequest then
        notify("Webhook", "HTTP requests are unsupported by this executor", 5)
        return
    end
    local URL = normalizeWebhookURL(Hub.WebhookURL)
    if not isValidWebhookURL(URL) then
        notify("Webhook", "Enter a valid Discord webhook URL first", 4)
        return
    end

    local Now = os.clock()
    local FeatureReadyAt = IsTest and (Hub.WebhookLastTestAt > 0 and Hub.WebhookLastTestAt + 5 or 0) or (Hub.WebhookLastSentAt > 0 and Hub.WebhookLastSentAt + Hub.WebhookInterval or 0)
    local RequestReadyAt = Hub.WebhookLastRequestAt > 0 and Hub.WebhookLastRequestAt + 5 or 0
    local SharedBackoffAt = tonumber(SavedWebhookRate.BackoffAt) or 0
    local SharedInFlightUntil = tonumber(SavedWebhookRate.InFlightUntil) or 0
    local RateReadyAt = math.max(Hub.WebhookBackoffAt, FeatureReadyAt, RequestReadyAt, SharedBackoffAt)
    local InFlightBlocked = Now < SharedInFlightUntil
    if InFlightBlocked or Now < RateReadyAt then
        if IsTest then
            local WaitUntil = math.max(RateReadyAt, InFlightBlocked and SharedInFlightUntil or 0)
            notify("Webhook", "Wait " .. math.ceil(WaitUntil - Now) .. " seconds before testing again", 4)
        else
            Hub.WebhookQueued = true
            if not InFlightBlocked then
                Hub.WebhookReadyAt = math.max(Hub.WebhookReadyAt, RateReadyAt)
            end
        end
        return
    end

    local Encoded
    local EncodedSuccess = pcall(function()
        Encoded = HttpService:JSONEncode(buildWebhookPayload(IsTest, Reason))
    end)
    if not EncodedSuccess then
        notify("Webhook", "Could not prepare the webhook message", 4)
        return
    end

    local Generation = Hub.WebhookGeneration
    local RequestToken = {}
    Hub.WebhookLastRequestAt = Now
    Hub.WebhookInFlightUntil = Now + 60
    SavedWebhookRate.LastRequestAt = Now
    SavedWebhookRate.InFlightUntil = Hub.WebhookInFlightUntil
    SavedWebhookRate.InFlightToken = RequestToken
    Hub.WebhookBusy = true
    if not IsTest then
        Hub.WebhookQueued = false
    end
    task.spawn(function()
        local RequestSuccess = false
        local StatusCode = 0
        local RetryAfter = 0
        local ResponseBody
        if Environment.MonsterRunnersFinal == Hub and Hub.WebhookGeneration == Generation then
            local Success, Response = pcall(HttpRequest, {
                Url = URL,
                Method = "POST",
                Headers = {['Content-Type'] = "application/json"},
                Body = Encoded
            })
            if Success and type(Response) == "table" then
                StatusCode = tonumber(Response.StatusCode or Response.Status or Response.status_code) or 0
                RequestSuccess = StatusCode >= 200 and StatusCode < 300
                ResponseBody = Response.Body or Response.body
                local Headers = Response.Headers or Response.headers
                if type(Headers) == "table" then
                    for Key, Value in pairs(Headers) do
                        if string.lower(tostring(Key)) == "retry-after" then
                            RetryAfter = tonumber(Value) or 0
                            break
                        end
                    end
                end
                if StatusCode == 429 and RetryAfter <= 0 and type(ResponseBody) == "string" then
                    pcall(function()
                        local Decoded = HttpService:JSONDecode(ResponseBody)
                        if type(Decoded) == "table" then
                            RetryAfter = tonumber(Decoded.retry_after) or 0
                        end
                    end)
                end
            end
        end

        if StatusCode == 429 then
            SavedWebhookRate.BackoffAt = math.max(tonumber(SavedWebhookRate.BackoffAt) or 0, os.clock() + math.max(RetryAfter, 5))
        end
        if SavedWebhookRate.InFlightToken == RequestToken then
            SavedWebhookRate.InFlightUntil = 0
            SavedWebhookRate.InFlightToken = nil
        end
        if Environment.MonsterRunnersFinal ~= Hub then
            return
        end
        if Hub.WebhookGeneration ~= Generation then
            Hub.WebhookBusy = false
            return
        end
        Hub.WebhookBusy = false
        Hub.WebhookInFlightUntil = 0
        if RequestSuccess then
            if IsTest then
                Hub.WebhookLastTestAt = os.clock()
                notify("Webhook", "Test message sent successfully", 4)
            else
                Hub.WebhookLastSentAt = os.clock()
                if Hub.WebhookNotifications then
                    Hub.WebhookQueued = true
                    Hub.WebhookReadyAt = Hub.WebhookLastSentAt + Hub.WebhookInterval
                end
            end
            return
        end

        local FailedAt = os.clock()
        if IsTest then
            Hub.WebhookLastTestAt = FailedAt
            if StatusCode == 429 then
                Hub.WebhookBackoffAt = FailedAt + math.max(RetryAfter, 5)
                SavedWebhookRate.BackoffAt = math.max(tonumber(SavedWebhookRate.BackoffAt) or 0, Hub.WebhookBackoffAt)
            end
        else
            Hub.WebhookBackoffAt = FailedAt + (StatusCode == 429 and math.max(RetryAfter, 5) or 5)
            if StatusCode == 429 then
                SavedWebhookRate.BackoffAt = math.max(tonumber(SavedWebhookRate.BackoffAt) or 0, Hub.WebhookBackoffAt)
            end
            Hub.WebhookReadyAt = StatusCode == 429 and Hub.WebhookBackoffAt or FailedAt + Hub.WebhookInterval
            if Hub.WebhookNotifications then
                Hub.WebhookQueued = true
            end
        end
        if not IsTest and StatusCode >= 400 and StatusCode < 500 and StatusCode ~= 429 and Hub.WebhookNotifications and Hub.Toggles and Hub.Toggles.WebhookNotifications and Hub.Toggles.WebhookNotifications.Value then
            task.defer(function()
                if Hub.Alive and Hub.Toggles.WebhookNotifications and Hub.Toggles.WebhookNotifications.Value then
                    Hub.Toggles.WebhookNotifications:SetValue(false)
                end
            end)
        end
        if os.clock() >= Hub.WebhookNotifyAt then
            Hub.WebhookNotifyAt = os.clock() + 10
            local Detail = StatusCode > 0 and "HTTP " .. StatusCode or "request failed"
            notify("Webhook", "Webhook delivery failed: " .. Detail, 5)
        end
    end)
end

local function runWebhookQueue()
    if not Hub.WebhookNotifications then
        Hub.WebhookQueued = false
        return
    end
    if not isValidWebhookURL(Hub.WebhookURL) then
        Hub.WebhookQueued = false
        return
    end
    Hub.WebhookBackoffAt = math.max(Hub.WebhookBackoffAt, tonumber(SavedWebhookRate.BackoffAt) or 0)
    if not Hub.WebhookQueued and not Hub.WebhookBusy then
        Hub.WebhookQueued = true
        Hub.WebhookReadyAt = math.max(os.clock() + Hub.WebhookInterval, Hub.WebhookBackoffAt)
    end
    if Hub.WebhookQueued and not Hub.WebhookBusy and os.clock() >= math.max(Hub.WebhookReadyAt, Hub.WebhookBackoffAt) then
        sendWebhook(false, Hub.WebhookQueueReason)
    end
end

local function setStatsText(Key, Text)
    local Label = Hub.StatsLabels[Key]
    if Label and Hub.StatsText[Key] ~= Text and Hub.Alive and not Library.Unloaded then
        Hub.StatsText[Key] = Text
        pcall(Label.SetText, Label, Text)
    end
end

local bindSessionStatSignals

local function updateSessionStats()
    local Leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local Wins = Leaderstats and Leaderstats:FindFirstChild("Escapes")
    local Kills = Values and Values:FindFirstChild("Kills")
    local Deaths = Values and Values:FindFirstChild("Deaths")
    local Scrap = Values and Values:FindFirstChild("Scrap")
    local Tickets = Values and Values:FindFirstChild("Tickets")
    local Rolls = Values and Values:FindFirstChild("Rolls")
    local Chance = Values and Values:FindFirstChild("Chance")
    local MaxRank = Values and Values:FindFirstChild("MaxRank")
    local MonsterEarnings = LocalPlayer:FindFirstChild("MonsterEarnings")
    local JoinedBefore = Values and Values:FindFirstChild("JoinedBefore")

    if not Wins or not Kills or not Scrap or not JoinedBefore or not JoinedBefore.Value then
        for _, Key in ipairs({"Player", "Wins", "Combat", "Scrap", "Economy", "Rank", "GameState"}) do
            setStatsText(Key, Key .. ": Waiting for player data")
        end
        return
    end

    if not Hub.StatsInitialized then
        Hub.StatsInitialized = true
        Hub.StatsStartedAt = os.clock()
        Hub.StatsLast.Wins = Wins.Value
        Hub.StatsLast.Kills = Kills.Value
        Hub.StatsLast.Scrap = Scrap.Value
    else
        local Current = {Wins = Wins.Value, Kills = Kills.Value, Scrap = Scrap.Value}
        for Key, Value in pairs(Current) do
            local Last = Hub.StatsLast[Key]
            if Last and Value > Last then
                Hub.StatsEarned[Key] += Value - Last
            end
            Hub.StatsLast[Key] = Value
        end
    end

    local Elapsed = math.max(os.clock() - Hub.StatsStartedAt, 0)
    local RankId = MaxRank and MaxRank.Value or 0
    if Hub.PrivacyMode then
        setStatsText("Player", "Player: Anonymous\nUser ID: Hidden | Account Age: Hidden")
        setStatsText("Wins", "Wins: Hidden")
        setStatsText("Combat", "Combat: Hidden")
        setStatsText("Scrap", "Scrap: Hidden")
        setStatsText("Economy", "Economy: Hidden")
        setStatsText("Rank", "Rank: Hidden")
        setStatsText("GameState", "Game State: Hidden")
        if bindSessionStatSignals then
            bindSessionStatSignals()
        end
        return
    end
    local PlayerText = "Player: " .. LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")\nUser ID: " .. LocalPlayer.UserId .. " | Account Age: " .. LocalPlayer.AccountAge .. " days"
    setStatsText("Player", PlayerText)
    setStatsText("Wins", "Wins: " .. Wins.Value .. " | Session: +" .. Hub.StatsEarned.Wins .. " | / Hour: " .. formatWebhookRate(Hub.StatsEarned.Wins, Elapsed))
    setStatsText("Combat", "Kills: " .. Kills.Value .. " | Session: +" .. Hub.StatsEarned.Kills .. " | Deaths: " .. (Deaths and Deaths.Value or 0) .. " | / Hour: " .. formatWebhookRate(Hub.StatsEarned.Kills, Elapsed))
    setStatsText("Scrap", "Scrap: " .. Scrap.Value .. " | Session: +" .. Hub.StatsEarned.Scrap .. " | Pending: " .. (MonsterEarnings and MonsterEarnings.Value or 0) .. " | / Hour: " .. formatWebhookRate(Hub.StatsEarned.Scrap, Elapsed))
    setStatsText("Economy", "Tickets: " .. (Tickets and Tickets.Value or 0) .. " | Rolls: " .. (Rolls and Rolls.Value or 0) .. " | Monster Chance: " .. (Chance and Chance.Value or 0) .. "%")
    setStatsText("Rank", "Rank: " .. getCurrentRankName(RankId) .. " | ID: " .. RankId)
    setStatsText("GameState", "Round: " .. tostring(RoundState.Value) .. " | Team: " .. (LocalPlayer.Team and LocalPlayer.Team.Name or "None") .. " | Players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers .. "\nServer: " .. (IsPublicServer and "Public" or "Private") .. " | Session: " .. formatSessionDuration(Elapsed))
    if bindSessionStatSignals then
        bindSessionStatSignals()
    end
end

bindSessionStatSignals = function()
    if Hub.StatsSignalsBound then
        return
    end
    local Leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local Values = LocalPlayer:FindFirstChild("BVFolder")
    local Wins = Leaderstats and Leaderstats:FindFirstChild("Escapes")
    local Kills = Values and Values:FindFirstChild("Kills")
    local Scrap = Values and Values:FindFirstChild("Scrap")
    if not Wins or not Kills or not Scrap then
        return
    end
    Hub.StatsSignalsBound = true
    local ValuesByKey = {Wins = Wins, Kills = Kills, Scrap = Scrap}
    for Key, Value in pairs(ValuesByKey) do
        connect(Value:GetPropertyChangedSignal("Value"), function()
            if Hub.StatsInitialized then
                local Current = Value.Value
                local Last = Hub.StatsLast[Key]
                if Last and Current > Last then
                    Hub.StatsEarned[Key] += Current - Last
                end
                Hub.StatsLast[Key] = Current
            end
        end)
    end
end

local function unload(SkipLibrary)
    if Hub.Unloading then
        return
    end

    Hub.Unloading = true
    Hub.Alive = false

    if Hub.SpeedEnabled or Hub.MonsterMovementApplied then
        restoreSpeed()
    end
    if Hub.JumpEnabled then
        restoreJump()
    end

    Hub.SpeedEnabled = false
    Hub.JumpEnabled = false
    Hub.InfiniteJump = false
    Hub.Noclip = false
    Hub.Fly = false
    Hub.NoRollCooldown = false
    Hub.RollSpeedBoost = false
    clearRunnerRollState(true)
    if Hub.RollMobileConnection then
        Hub.RollMobileConnection:Disconnect()
        Hub.RollMobileConnection = nil
    end
    Hub.RollMobileButton = nil
    Hub.MoveWhileKilling = false
    Hub.NoCrawlSlowdown = false
    Hub.MonsterMovementApplied = false
    Hub.KillAura = false
    Hub.AutoMonsterFarm = false
    Hub.AutoRunnerWin = false
    Hub.AutoTicketExchange = false
    Hub.AutoRankUp = false
    Hub.AutoRoll = false
    Hub.AntiAFK = false
    Hub.Privacy:Disable()
    if cancelElevatorWarning then
        cancelElevatorWarning(false)
    end
    Hub.WebhookURL = ""
    Hub.WebhookNotifications = false
    Hub.WebhookBusy = false
    Hub.WebhookQueued = false
    Hub.WebhookGeneration += 1
    if Hub.Options and Hub.Options.WebhookURL then
        pcall(Hub.Options.WebhookURL.SetValue, Hub.Options.WebhookURL, "")
    end
    Hub.AutoMonsterGeneration += 1
    Hub.AutoRunnerGeneration += 1
    Hub.AutoTicketGeneration += 1
    Hub.AutoRankGeneration += 1
    Hub.AutoRollGeneration += 1
    Hub.AutoMonsterBusy = false
    Hub.AutoRunnerBusy = false
    Hub.AutoTicketBusy = false
    Hub.AutoRankBusy = false
    Hub.AutoRollBusy = false
    Hub.NextAutoTicketAttempt = 0
    Hub.NextAutoRankAttempt = 0
    Hub.NextAutoRollAttempt = 0
    if Hub.AutoRunnerPending then
        saveAutoRunnerPending(true)
    else
        clearAutoRunnerPending(true)
    end
    Hub.AutoRunnerReadyAt = 0
    Hub.AutoRunnerCompleted = false
    Hub.EndRoomPreloading = false
    Hub.PlayerHitboxes = false
    Hub.MonsterESP = false
    Hub.PlayerESP = false
    Hub.GameplayPauseBypass = false
    Hub.Fullbright = false
    Hub.NoFog = false
    Hub.ColorGrade = false

    restoreElevatorAnchor()
    restoreNoclip()
    clearFly()
    restoreHitboxes()
    clearESP()
    restoreGameplayPauseBypass()
    restoreFullbright()
    restoreNoFog()
    clearColorGrade()
    RunService:UnbindFromRenderStep(Hub.RenderName)

    for _, Connection in ipairs(Hub.Connections) do
        Connection:Disconnect()
    end
    table.clear(Hub.Connections)

    if not SkipLibrary and not Library.Unloaded then
        pcall(Library.Unload, Library)
    end

    if Environment.MonsterRunnersFinal == Hub then
        Environment.MonsterRunnersFinal = nil
    end
end

Hub.Unload = function()
    unload(false)
end
Hub.TeleportToSelectedPlayer = teleportToSelectedPlayer

local function fetchWindowFooter()
    local Success, Message = pcall(game.HttpGet, game, "https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram?refresh=" .. tostring(os.time()), false)
    if not Success or type(Message) ~= "string" then
        return nil
    end
    Message = Message:gsub("%c", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    local Length = utf8.len(Message)
    if Message == "" or not Length then
        return nil
    end
    if Length > 100 then
        local EndByte = utf8.offset(Message, 101)
        Message = EndByte and Message:sub(1, EndByte - 1) or Message
    end
    Message = Message:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    return "Monster Runners | " .. Message
end

local Window = Library:CreateWindow({
    Title = "Monster Runners",
    Footer = "Monster Runners",
    Icon = "skull",
    NotifySide = "Right",
    ShowCustomCursor = not IsMobile,
    Size = UDim2.fromOffset(720, 520),
    ToggleKeybind = Enum.KeyCode.RightShift,
    ShowMobileButtons = true,
    MobileButtonsSide = "Left",
    GlobalSearch = true,
    EnableCompacting = true,
    SidebarCompacted = true
})

local function closeElevatorWarning(Request, Permit, RestoreWindow)
    if Hub.ElevatorWarningRequest ~= Request then
        return false
    end
    local Dialog = Hub.ElevatorWarningDialog
    Hub.ElevatorWarningRequest = nil
    Hub.ElevatorWarningDialog = nil
    Hub.ElevatorWarningPermit = Permit
    if Dialog then
        pcall(Dialog.Dismiss, Dialog)
    end
    if RestoreWindow and Request.RestoreClosed then
        task.defer(function()
            if Hub.Alive and Environment.MonsterRunnersFinal == Hub and not Library.Unloaded and Library.Toggled and not Library.ActiveDialog then
                Library:Toggle(false)
            end
        end)
    end
    return true
end

cancelElevatorWarning = function(RestoreWindow)
    local Request = Hub.ElevatorWarningRequest
    Hub.ElevatorWarningPermit = nil
    if Request then
        closeElevatorWarning(Request, nil, RestoreWindow == true)
    else
        Hub.ElevatorWarningDialog = nil
    end
end

local function isElevatorWarningCurrent(Request)
    if Hub.ElevatorWarningRequest ~= Request or not Hub.Alive or Environment.MonsterRunnersFinal ~= Hub or os.clock() > Request.ExpiresAt then
        return false
    end
    local Character, Humanoid, Root = getCharacter(LocalPlayer)
    return Request.Counter.Parent == LocalPlayer and Request.Counter:IsA("NumberValue") and Request.Counter.Value == Request.CounterValue and Request.Counter.Value >= AutoRunnerEscapeLimit and LocalPlayer.Team == Request.Team and LocalPlayer.Team == Runners and RoundState.Value == Request.RoundState and Character == Request.Character and Humanoid and Humanoid.Health > 0 and Root == Request.Root and getLiveEndRoom() == Request.EndRoom
end

local function requestManualElevatorTeleport()
    if not Hub.Alive or Environment.MonsterRunnersFinal ~= Hub then
        return false
    end

    local EscapesInOneRound = LocalPlayer:FindFirstChild("EscapesInOneRound")
    if not IsPublicServer or LocalPlayer.Team ~= Runners then
        return teleportToEndElevator(false)
    end
    if not EscapesInOneRound or not EscapesInOneRound:IsA("NumberValue") then
        notify("End Elevator", "Round escape counter is unavailable", 3)
        return false
    end
    if EscapesInOneRound.Value < AutoRunnerEscapeLimit then
        return teleportToEndElevator(false)
    end
    if isAutoRollInFlight and isAutoRollInFlight() then
        notify("End Elevator", "Wait for the wheel roll to finish", 3)
        return false
    end
    if Hub.ElevatorTeleporting or os.clock() < Hub.NextElevatorTeleport then
        notify("End Elevator", "Elevator teleport is not ready", 3)
        return false
    end
    if Hub.PlayerTeleporting or Hub.AutoMonsterBusy then
        notify("End Elevator", "Another movement action is in progress", 3)
        return false
    end
    if Hub.ElevatorWarningRequest then
        return false
    end
    if Library.ActiveDialog then
        notify("End Elevator", "Close the current dialog first", 3)
        return false
    end

    local Character, Humanoid, Root = getCharacter(LocalPlayer)
    local EndRoom = getLiveEndRoom()
    if not Character or not Humanoid or not Root or Humanoid.Health <= 0 then
        notify("End Elevator", "Character is unavailable", 3)
        return false
    end
    if not EndRoom then
        notify("End Elevator", "End room is unavailable", 3)
        return false
    end

    local Request = {
        Counter = EscapesInOneRound,
        CounterValue = EscapesInOneRound.Value,
        Character = Character,
        Root = Root,
        Team = LocalPlayer.Team,
        RoundState = RoundState.Value,
        EndRoom = EndRoom,
        ExpiresAt = os.clock() + 30,
        RestoreClosed = not Library.Toggled
    }
    Hub.ElevatorWarningRequest = Request
    if Request.RestoreClosed then
        Library:Toggle(true)
    end

    local Success, Dialog = pcall(Window.AddDialog, Window, "ElevatorBanWarning", {
        Title = "Ban Risk Warning",
        Description = "You already have " .. tostring(Request.CounterValue) .. " escapes this round. The next accepted elevator escape triggers an anti-cheat kick and may result in a ban. Teleport anyway?",
        AutoDismiss = false,
        OutsideClickDismiss = false,
        FooterButtons = {
            Cancel = {
                Title = "Cancel",
                Variant = "Secondary",
                Order = 1,
                Callback = function()
                    closeElevatorWarning(Request, nil, true)
                end
            },
            Confirm = {
                Title = "Teleport Anyway",
                Variant = "Destructive",
                Order = 2,
                Callback = function()
                    if not isElevatorWarningCurrent(Request) then
                        if closeElevatorWarning(Request, nil, true) then
                            notify("End Elevator", "Teleport state changed. Try again", 3)
                        end
                        return
                    end
                    local Permit = {
                        Active = true,
                        Counter = Request.Counter,
                        CounterValue = Request.CounterValue,
                        Character = Request.Character,
                        Root = Request.Root,
                        Team = Request.Team,
                        RoundState = Request.RoundState,
                        EndRoom = Request.EndRoom
                    }
                    if closeElevatorWarning(Request, Permit, true) then
                        teleportToEndElevator(false, Permit)
                    end
                end
            }
        }
    })
    if not Success or not Dialog then
        closeElevatorWarning(Request, nil, true)
        notify("End Elevator", "Unable to open the warning dialog", 3)
        return false
    end
    Hub.ElevatorWarningDialog = Dialog
    task.delay(30, function()
        if Hub.ElevatorWarningRequest == Request and closeElevatorWarning(Request, nil, true) then
            notify("End Elevator", "Confirmation expired", 3)
        end
    end)
    return false
end

Hub.TeleportToEndElevator = requestManualElevatorTeleport

local Tabs = {
    Visuals = Window:AddTab("Visuals", "eye", ""),
    Movement = Window:AddTab("Movement", "person-standing", ""),
    Combat = Window:AddTab("Combat", "swords", ""),
    Teleport = Window:AddTab("Teleport", "map-pin", ""),
    AutoFarm = Window:AddTab("Auto Farm", "bot", ""),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings", "")
}

local Watermark = Library:SetupWatermark({
    ShowWatermark = false,
    ScriptName = "Monster Runners",
    ShowName = true,
    ShowFPS = true,
    ShowPing = true,
    TextColor = Color3.fromRGB(235, 240, 255),
    BackgroundColor = Color3.fromRGB(12, 14, 20),
    BackgroundTransparency = 0.25
})

Hub.Library = Library
Hub.Window = Window
Hub.Watermark = Watermark
Hub.Options = Options
Hub.Toggles = Toggles

task.spawn(function()
    while Hub.Alive and Environment.MonsterRunnersFinal == Hub do
        local Footer = fetchWindowFooter()
        if not Hub.Alive or Environment.MonsterRunnersFinal ~= Hub or Library.Unloaded then
            return
        end
        if Footer then
            pcall(Window.SetFooter, Window, Footer)
        end
        task.wait(60)
    end
end)

Library:OnUnload(function()
    unload(true)
end)

do
    local ESPGroup = Tabs.Visuals:AddLeftGroupbox("ESP", "scan-eye")

    ESPGroup:AddToggle("MonsterESP", {
        Text = "Monster ESP",
        Tooltip = "Highlights the current monster",
        Default = false,
        Callback = function(Value)
            if Hub.MonsterESP == Value then
                return
            end
            Hub.MonsterESP = Value
            syncESP()
        end
    })
    Toggles.MonsterESP:AddKeyPicker("MonsterESPKeybind", {
        Default = "M",
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Monster ESP"
    })

    ESPGroup:AddToggle("PlayerESP", {
        Text = "Player ESP",
        Tooltip = "Highlights all other players",
        Default = false,
        Callback = function(Value)
            if Hub.PlayerESP == Value then
                return
            end
            Hub.PlayerESP = Value
            syncESP()
        end
    })
    Toggles.PlayerESP:AddKeyPicker("PlayerESPKeybind", {
        Default = "P",
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Player ESP"
    })

    local PrivacyGroup = Tabs.Visuals:AddLeftGroupbox("Privacy", "shield-user")

    PrivacyGroup:AddToggle("PrivacyMode", {
        Text = "Privacy Mode",
        Tooltip = "Hides your identity and personal statistics locally",
        Default = false,
        Callback = function(Value)
            if Hub.PrivacyMode == Value then
                return
            end
            Hub.WebhookGeneration += 1
            if Value then
                Hub.Privacy:Enable()
            else
                Hub.Privacy:Disable()
            end
            updateSessionStats()
        end
    })

    local WorldGroup = Tabs.Visuals:AddRightGroupbox("World", "sun")

    WorldGroup:AddToggle("Fullbright", {
        Text = "Fullbright",
        Tooltip = "Brightens the map and removes shadows",
        Default = false,
        Callback = function(Value)
            if Hub.Fullbright == Value then
                return
            end
            Hub.Fullbright = Value
            if Value then
                applyFullbright()
            else
                restoreFullbright()
            end
        end
    })
    WorldGroup:AddToggle("NoFog", {
        Text = "No Fog",
        Tooltip = "Removes Lighting fog and Atmosphere haze",
        Default = false,
        Callback = function(Value)
            if Hub.NoFog == Value then
                return
            end
            Hub.NoFog = Value
            if Value then
                applyNoFog()
            else
                restoreNoFog()
            end
        end
    })
    WorldGroup:AddDivider()

    WorldGroup:AddToggle("ColorGrade", {
        Text = "Color Grade",
        Tooltip = "Applies a balanced post-processing preset",
        Default = false,
        Callback = function(Value)
            if Hub.ColorGrade == Value then
                return
            end
            Hub.ColorGrade = Value
            if Value then
                applyColorGrade()
            else
                clearColorGrade()
            end
        end
    })
    WorldGroup:AddDropdown("ColorGradePreset", {
        Values = {"Balanced", "Cinematic", "Vibrant", "Cold"},
        Default = Hub.ColorGradePreset,
        Multi = false,
        Text = "Color Grade Preset",
        Searchable = false,
        AllowNull = false,
        Callback = function(Value)
            Hub.ColorGradePreset = Value or "Balanced"
            if Hub.ColorGrade then
                applyColorGrade()
            end
        end
    })

    WorldGroup:AddSlider("ColorGradeStrength", {
        Text = "Color Grade Strength",
        Default = Hub.ColorGradeStrength,
        Min = 0,
        Max = 100,
        Rounding = 0,
        Suffix = "%",
        Callback = function(Value)
            Hub.ColorGradeStrength = Value
            if Hub.ColorGrade then
                applyColorGrade()
            end
        end
    })

    local MovementGroup = Tabs.Movement:AddLeftGroupbox("Movement", "gauge")

    MovementGroup:AddToggle("CustomSpeed", {
        Text = "Custom Speed",
        Default = false,
        Callback = function(Value)
            if Hub.SpeedEnabled == Value then
                return
            end
            Hub.SpeedEnabled = Value
            if Value then
                Hub.MonsterMovementApplied = false
                applyMovement()
            else
                if not applyMonsterMovementBypasses() then
                    restoreSpeed()
                end
            end
        end
    })

    MovementGroup:AddSlider("SpeedValue", {
        Text = "Walk Speed",
        Default = Hub.Speed,
        Min = 10,
        Max = 150,
        Rounding = 0,
        Callback = function(Value)
            Hub.Speed = Value
            if Hub.SpeedEnabled then
                applyMovement()
            end
        end
    })

    MovementGroup:AddToggle("CustomJump", {
        Text = "Custom Jump",
        Default = false,
        Callback = function(Value)
            if Hub.JumpEnabled == Value then
                return
            end
            Hub.JumpEnabled = Value
            if Value then
                applyMovement()
            else
                restoreJump()
            end
        end
    })

    MovementGroup:AddSlider("JumpValue", {
        Text = "Jump Height",
        Default = Hub.Jump,
        Min = 0,
        Max = 75,
        Rounding = 0,
        Callback = function(Value)
            Hub.Jump = Value
            if Hub.JumpEnabled then
                applyMovement()
            end
        end
    })

    MovementGroup:AddToggle("InfiniteJump", {
        Text = "Infinite Jump",
        Default = false,
        Callback = function(Value)
            Hub.InfiniteJump = Value
        end
    })
    Toggles.InfiniteJump:AddKeyPicker("InfiniteJumpKeybind", {
        Default = "J",
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Infinite Jump"
    })

    local TraversalGroup = Tabs.Movement:AddRightGroupbox("Traversal", "navigation")

    TraversalGroup:AddToggle("Noclip", {
        Text = "Noclip",
        Default = false,
        Callback = function(Value)
            if Hub.Noclip == Value then
                return
            end
            Hub.Noclip = Value
            if Value then
                applyNoclip()
            else
                restoreNoclip()
            end
        end
    })
    Toggles.Noclip:AddKeyPicker("NoclipKeybind", {
        Default = "N",
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Noclip"
    })

    TraversalGroup:AddToggle("Fly", {
        Text = "Fly",
        Default = false,
        Callback = function(Value)
            if Hub.Fly == Value then
                return
            end
            if Value and isAutoRollInFlight and isAutoRollInFlight() then
                notify("Fly", "Wait for the wheel roll to finish", 3)
                task.defer(function()
                    if Hub.Alive and Toggles.Fly and Toggles.Fly.Value then
                        Toggles.Fly:SetValue(false)
                    end
                end)
                return
            end
            Hub.Fly = Value
            if Value then
                clearRunnerRollState(true)
                ensureFly()
            else
                clearFly()
            end
        end
    })
    Toggles.Fly:AddKeyPicker("FlyKeybind", {
        Default = "V",
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Fly"
    })

    TraversalGroup:AddSlider("IYFlySpeed", {
        Text = "Fly Speed",
        Default = Hub.FlySpeed,
        Min = 0.1,
        Max = 10,
        Rounding = 1,
        Suffix = "x",
        Callback = function(Value)
            Hub.FlySpeed = Value
        end
    })

    TraversalGroup:AddLabel(IsMobile and "Use the thumbstick and camera direction to fly" or "Use WASD to move, E to ascend, and Q to descend", true)

    local RunnerRollGroup = Tabs.Movement:AddRightGroupbox("Runner Roll", "wind")

    RunnerRollGroup:AddToggle("NoRollCooldown", {
        Text = "No Roll Cooldown",
        Default = false,
        Callback = function(Value)
            if Hub.NoRollCooldown == Value then
                return
            end
            Hub.NoRollCooldown = Value
            clearRunnerRollState(true)
            if Value then
                syncRollMobileButton()
            end
        end
    })

    RunnerRollGroup:AddToggle("RollSpeedBoost", {
        Text = "Roll Speed Boost",
        Default = false,
        Callback = function(Value)
            Hub.RollSpeedBoost = Value
            if Value then
                local Dash = LocalPlayer:FindFirstChild("Dash")
                local Character, Humanoid, Root = getCharacter(LocalPlayer)
                if Dash and Dash:IsA("BoolValue") and Dash.Value and Character and Humanoid and Root and not isRunnerRollBlocked(Character, Humanoid, Root) then
                    local Mode = getRunnerRollMode()
                    Hub.NativeRollWindow = {
                        Character = Character,
                        Humanoid = Humanoid,
                        Root = Root,
                        Dash = Dash,
                        Mode = Mode,
                        StartAt = os.clock(),
                        EndAt = os.clock() + 0.12
                    }
                end
            else
                Hub.NativeRollWindow = nil
            end
        end
    })

    RunnerRollGroup:AddSlider("RollSpeed", {
        Text = "Roll Speed",
        Default = Hub.RollSpeed,
        Min = 85,
        Max = 250,
        Rounding = 0,
        Suffix = " studs/s",
        Callback = function(Value)
            Hub.RollSpeed = Value
        end
    })

    RunnerRollGroup:AddLabel(IsMobile and "Use the normal mobile roll button" or "Use Left Shift or the left stick button", true)

    local MonsterGroup = Tabs.Combat:AddLeftGroupbox("Monster", "skull")

    MonsterGroup:AddToggle("MoveWhileKilling", {
        Text = "Move While Killing",
        Tooltip = "Keeps normal movement during the monster kill animation",
        Default = false,
        Callback = function(Value)
            Hub.MoveWhileKilling = Value
            applyMonsterMovementBypasses()
        end
    })

    MonsterGroup:AddToggle("NoCrawlSlowdown", {
        Text = "No Crawl Slowdown",
        Tooltip = "Keeps normal monster speed while crawling",
        Default = false,
        Callback = function(Value)
            Hub.NoCrawlSlowdown = Value
            applyMonsterMovementBypasses()
        end
    })

    MonsterGroup:AddToggle("KillAura", {
        Text = "Kill Aura",
        Tooltip = "Only activates while you are the monster",
        Default = false,
        Callback = function(Value)
            if Hub.KillAura == Value then
                return
            end
            Hub.KillAura = Value
            if Value and LocalPlayer.Team ~= Monsters then
                notify("Kill Aura", "Waiting for the monster role", 3)
            end
        end
    })
    Toggles.KillAura:AddKeyPicker("KillAuraKeybind", {
        Default = "K",
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Kill Aura"
    })

    MonsterGroup:AddSlider("AuraRange", {
        Text = "Kill Aura Range",
        Default = Hub.AuraRange,
        Min = 5,
        Max = 60,
        Rounding = 0,
        Callback = function(Value)
            Hub.AuraRange = Value
        end
    })

    local HitboxGroup = Tabs.Combat:AddRightGroupbox("Player Hitboxes", "box")

    HitboxGroup:AddToggle("PlayerHitboxes", {
        Text = "Player Hitboxes",
        Tooltip = "Client-side only",
        Default = false,
        Callback = function(Value)
            if Hub.PlayerHitboxes == Value then
                return
            end
            Hub.PlayerHitboxes = Value
            if Value then
                syncHitboxes()
            else
                restoreHitboxes()
            end
        end
    })
    Toggles.PlayerHitboxes:AddKeyPicker("PlayerHitboxesKeybind", {
        Default = "H",
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Player Hitboxes"
    })

    HitboxGroup:AddSlider("HitboxSize", {
        Text = "Hitbox Size",
        Default = Hub.HitboxSize,
        Min = 3,
        Max = 30,
        Rounding = 0,
        Callback = function(Value)
            Hub.HitboxSize = Value
            if Hub.PlayerHitboxes then
                syncHitboxes()
            end
        end
    })

    local ElevatorGroup = Tabs.Teleport:AddLeftGroupbox("End Elevator", "door-open")

    ElevatorGroup:AddDropdown("ElevatorChoice", {
        Values = {"Nearest", "Elevator 1", "Elevator 2"},
        Default = "Nearest",
        Multi = false,
        Text = "End Elevator",
        Searchable = false,
        AllowNull = false,
        Callback = function(Value)
            Hub.ElevatorChoice = Value or "Nearest"
        end
    })

    ElevatorGroup:AddButton({
        Text = "Teleport Inside Elevator",
        Tooltip = "Loads the end room before teleporting",
        Func = requestManualElevatorTeleport
    })
    ElevatorGroup:AddLabel("Elevator teleport keybind"):AddKeyPicker("ElevatorTeleportKeybind", {
        Default = "T",
        Mode = "Press",
        Text = "Teleport Inside Elevator",
        Callback = function()
            if Hub.Alive then
                requestManualElevatorTeleport()
            end
        end
    })

    local StreamingGroup = Tabs.Teleport:AddLeftGroupbox("Streaming", "radio")

    StreamingGroup:AddToggle("GameplayPauseBypass", {
        Text = "Gameplay Paused Bypass",
        Tooltip = "Prevents streaming from pausing gameplay",
        Default = false,
        Callback = function(Value)
            if Hub.GameplayPauseBypass == Value then
                return
            end
            Hub.GameplayPauseBypass = Value
            if Value then
                local Success = enableGameplayPauseBypass()
                if Success then
                    notify("Gameplay Paused Bypass", "Streaming pause disabled", 3)
                else
                    notify("Gameplay Paused Bypass", "Unsupported by this executor", 4)
                end
            else
                restoreGameplayPauseBypass()
            end
        end
    })
    local PlayerGroup = Tabs.Teleport:AddRightGroupbox("Players", "users")
    local InitialPlayerValues, InitialPlayerMap = buildPlayerValues()
    Hub.PlayerValueToId = InitialPlayerMap

    PlayerDropdown = PlayerGroup:AddDropdown("PlayerTeleportTarget", {
        Values = InitialPlayerValues,
        Multi = false,
        Text = "Player",
        Searchable = true,
        AllowNull = true,
        Callback = function(Value)
            Hub.SelectedPlayerLabel = Value
            Hub.SelectedPlayerUserId = Value and Hub.PlayerValueToId[Value] or nil
        end
    })

    PlayerGroup:AddButton({
        Text = "Teleport to Player",
        Func = teleportToSelectedPlayer
    })
    PlayerGroup:AddButton({
        Text = "Refresh Player List",
        Func = refreshPlayerDropdown
    })

    local AutomationGroup = Tabs.AutoFarm:AddLeftGroupbox("Automation", "bot")

    AutomationGroup:AddToggle("AutoMonsterFarm", {
        Text = "Auto Kill as Monster",
        Tooltip = "Targets the active runner closest to either elevator",
        Default = false,
        Callback = function(Value)
            if Hub.AutoMonsterFarm == Value then
                return
            end
            Hub.AutoMonsterFarm = Value
            Hub.AutoMonsterGeneration += 1
            Hub.AutoMonsterBusy = false
            Hub.NextAutoMonsterAction = 0
        end
    })

    AutomationGroup:AddToggle("AutoRunnerWin", {
        Text = "Auto Win as Runner",
        Tooltip = "Teleports into the elevator up to four times per round",
        Default = false,
        Callback = function(Value)
            if Hub.AutoRunnerWin == Value then
                return
            end
            Hub.AutoRunnerWin = Value
            Hub.AutoRunnerGeneration += 1
            Hub.NextAutoRunnerAttempt = 0
            if Value then
                syncAutoRunnerCounter()
                if not Hub.AutoRunnerPending then
                    clearAutoRunnerPending(true)
                    Hub.AutoRunnerReadyAt = os.clock() + 0.5
                end
                if not IsPublicServer then
                    notify("Auto Win", "Wins are unavailable in private servers", 5)
                    task.defer(function()
                        if Hub.Alive and Toggles.AutoRunnerWin and Toggles.AutoRunnerWin.Value then
                            Toggles.AutoRunnerWin:SetValue(false)
                        end
                    end)
                end
            else
                restoreElevatorAnchor()
                Hub.AutoRunnerBusy = false
                Hub.AutoRunnerReadyAt = 0
            end
        end
    })

    AutomationGroup:AddToggle("AutoTicketExchange", {
        Text = "Auto Ticket Exchange",
        Tooltip = "Exchanges all Tickets for Scrap from anywhere",
        Default = false,
        Callback = function(Value)
            if Hub.AutoTicketExchange == Value then
                return
            end
            Hub.AutoTicketExchange = Value
            Hub.AutoTicketGeneration += 1
            local Session = Environment.MonsterRunnersTicketSession
            Hub.AutoTicketBusy = type(Session) == "table" and Session.Active == true
            Hub.NextAutoTicketAttempt = math.max(Hub.NextAutoTicketAttempt, getAutoTicketCooldown())
        end
    })

    AutomationGroup:AddToggle("AutoRoll", {
        Text = "Auto Roll",
        Tooltip = "Uses free rolls first, then 100 Scrap, from anywhere",
        Default = false,
        Callback = function(Value)
            if Hub.AutoRoll == Value then
                return
            end
            Hub.AutoRoll = Value
            Hub.AutoRollGeneration += 1
            Hub.AutoRollBusy = false
            Hub.NextAutoRollAttempt = math.max(Hub.NextAutoRollAttempt, getAutoRollCooldown())
        end
    })

    AutomationGroup:AddToggle("AutoRankUp", {
        Text = "Auto Rank Up",
        Tooltip = "Automatically upgrades ranks whenever the Scrap and escape requirements are met",
        Default = false,
        Callback = function(Value)
            if Hub.AutoRankUp == Value then
                return
            end
            Hub.AutoRankUp = Value
            Hub.AutoRankGeneration += 1
            local Session = Environment.MonsterRunnersRankSession
            Hub.AutoRankBusy = type(Session) == "table" and Session.Active == true
            Hub.NextAutoRankAttempt = 0
        end
    })

    AutomationGroup:AddToggle("AntiAFK", {
        Text = "Anti-AFK",
        Tooltip = "Prevents the Roblox inactivity kick",
        Default = false,
        Callback = function(Value)
            Hub.AntiAFK = Value
        end
    })

    local StatisticsGroup = Tabs.AutoFarm:AddRightGroupbox("Statistics", "chart-no-axes-combined")
    Hub.StatsLabels.Player = StatisticsGroup:AddLabel("Player: Waiting for player data", true)
    Hub.StatsLabels.Wins = StatisticsGroup:AddLabel("Wins: Waiting for player data", true)
    Hub.StatsLabels.Combat = StatisticsGroup:AddLabel("Combat: Waiting for player data", true)
    Hub.StatsLabels.Scrap = StatisticsGroup:AddLabel("Scrap: Waiting for player data", true)
    Hub.StatsLabels.Economy = StatisticsGroup:AddLabel("Economy: Waiting for player data", true)
    Hub.StatsLabels.Rank = StatisticsGroup:AddLabel("Rank: Waiting for player data", true)
    Hub.StatsLabels.GameState = StatisticsGroup:AddLabel("Game State: Waiting for player data", true)
    updateSessionStats()

    local WebhookGroup = Tabs.AutoFarm:AddRightGroupbox("Webhook", "webhook")

    WebhookGroup:AddInput("WebhookURL", {
        Text = "Discord Webhook URL",
        Default = "",
        Finished = false,
        ClearTextOnFocus = false,
        ClearTextOnBlur = false,
        Placeholder = "https://discord.com/api/webhooks/...",
        AllowEmpty = true,
        Callback = function(Value)
            local URL = normalizeWebhookURL(Value)
            if Hub.WebhookURL == URL then
                return
            end
            Hub.WebhookURL = URL
            Hub.WebhookGeneration += 1
            Hub.WebhookBackoffAt = math.max(tonumber(SavedWebhookRate.BackoffAt) or 0, 0)
            Hub.WebhookQueued = Hub.WebhookNotifications and isValidWebhookURL(URL)
            Hub.WebhookReadyAt = Hub.WebhookQueued and os.clock() + Hub.WebhookInterval or 0
        end
    })

    WebhookGroup:AddToggle("WebhookNotifications", {
        Text = "Webhook Notifications",
        Tooltip = "Sends selected statistics at the configured interval",
        Default = false,
        Callback = function(Value)
            if Hub.WebhookNotifications == Value then
                return
            end
            Hub.WebhookNotifications = Value
            Hub.WebhookQueued = false
            if Value then
                if not HttpRequest then
                    notify("Webhook", "HTTP requests are unsupported by this executor", 5)
                    task.defer(function()
                        if Hub.Alive and Toggles.WebhookNotifications and Toggles.WebhookNotifications.Value then
                            Toggles.WebhookNotifications:SetValue(false)
                        end
                    end)
                elseif not isValidWebhookURL(Hub.WebhookURL) then
                    notify("Webhook", "Enter a valid Discord webhook URL first", 4)
                    task.defer(function()
                        if Hub.Alive and Toggles.WebhookNotifications and Toggles.WebhookNotifications.Value then
                            Toggles.WebhookNotifications:SetValue(false)
                        end
                    end)
                else
                    Hub.WebhookQueueReason = "Periodic Update"
                    Hub.WebhookQueued = true
                    Hub.WebhookReadyAt = math.max(os.clock() + Hub.WebhookInterval, Hub.WebhookBackoffAt)
                end
            end
        end
    })

    WebhookGroup:AddSlider("WebhookInterval", {
        Text = "Notification Interval",
        Default = Hub.WebhookInterval,
        Min = 5,
        Max = 600,
        Rounding = 0,
        Suffix = " seconds",
        Tooltip = "Time between automatic webhook messages",
        Callback = function(Value)
            Hub.WebhookInterval = Value
            if Hub.WebhookNotifications and isValidWebhookURL(Hub.WebhookURL) then
                Hub.WebhookQueued = true
                Hub.WebhookReadyAt = math.max(os.clock() + Value, Hub.WebhookBackoffAt)
            end
        end
    })

    local WebhookCategories = {
        {Id = "WebhookPlayerInfo", Text = "Player Info"},
        {Id = "WebhookWins", Text = "Wins"},
        {Id = "WebhookKills", Text = "Kills and Deaths"},
        {Id = "WebhookScrap", Text = "Scrap"},
        {Id = "WebhookEconomy", Text = "Tickets, Rolls and Chance"},
        {Id = "WebhookRank", Text = "Rank"},
        {Id = "WebhookGameState", Text = "Game State"}
    }
    for _, Category in ipairs(WebhookCategories) do
        WebhookGroup:AddToggle(Category.Id, {
            Text = Category.Text,
            Default = true,
            Callback = function(Value)
                Hub[Category.Id] = Value
            end
        })
    end

    WebhookGroup:AddButton({
        Text = "Send Test Webhook",
        Tooltip = "Sends one test message with the selected statistics",
        Func = function()
            sendWebhook(true, "Webhook Test")
        end
    })
    local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")

    MenuGroup:AddToggle("KeybindMenuOpen", {
        Text = "Show Keybind List",
        Default = Library.KeybindFrame.Visible,
        Callback = function(Value)
            Library.KeybindFrame.Visible = Value
        end
    })
    MenuGroup:AddLabel("Feature keybinds are shown next to their toggles and can be changed", true)

    MenuGroup:AddToggle("ShowCustomCursor", {
        Text = "Custom Cursor",
        Default = not IsMobile,
        Callback = function(Value)
            Library.ShowCustomCursor = Value
        end
    })

    MenuGroup:AddDropdown("NotificationSide", {
        Values = {"Left", "Right"},
        Default = "Right",
        Multi = false,
        Text = "Notification Side",
        AllowNull = false,
        Callback = function(Value)
            Library:SetNotifySide(Value)
        end
    })

    MenuGroup:AddDropdown("DPIDropdown", {
        Values = IsMobile and {"75%", "100%"} or {"75%", "100%", "125%", "150%", "175%", "200%"},
        Default = "100%",
        Multi = false,
        Text = "DPI Scale",
        AllowNull = false,
        Callback = function(Value)
            Library:SetDPIScale(tonumber(Value:gsub("%%", "")))
        end
    })

    MenuGroup:AddDivider()

    MenuGroup:AddLabel("Menu keybind"):AddKeyPicker("MenuKeybind", {
        Default = "RightShift",
        NoUI = true,
        Text = "Menu keybind"
    })

    MenuGroup:AddButton({
        Text = "Unload",
        Risky = true,
        Func = Hub.Unload
    })

    local WatermarkGroup = Tabs["UI Settings"]:AddRightGroupbox("Watermark", "monitor")

    WatermarkGroup:AddToggle("WatermarkVisible", {
        Text = "Show Watermark",
        Default = false,
        Callback = function(Value)
            Watermark:SetVisible(Value)
        end
    })

    WatermarkGroup:AddToggle("WatermarkShowName", {
        Text = "Show Player Name",
        Default = true,
        Callback = function(Value)
            Watermark:ShowName(Value and not Hub.PrivacyMode)
        end
    })

    WatermarkGroup:AddToggle("WatermarkShowFPS", {
        Text = "Show FPS",
        Default = true,
        Callback = function(Value)
            Watermark:ShowFPS(Value)
        end
    })

    WatermarkGroup:AddToggle("WatermarkShowPing", {
        Text = "Show Ping",
        Default = true,
        Callback = function(Value)
            Watermark:ShowPing(Value)
        end
    })

    connect(UserInputService.JumpRequest, function()
        if not Hub.Alive or not Hub.InfiniteJump or Hub.Fly or isRunnerRollActive() then
            return
        end
        local _, Humanoid = getCharacter(LocalPlayer)
        if Humanoid and Humanoid.Health > 0 then
            Humanoid.Jump = true
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    connect(UserInputService.InputBegan, function(Input, Processed)
        if Processed then
            return
        end
        if Input.KeyCode == Enum.KeyCode.LeftShift or Input.KeyCode == Enum.KeyCode.ButtonL3 then
            requestLocalRunnerRoll()
        end
    end)

    local Dash = LocalPlayer:FindFirstChild("Dash")
    if Dash and Dash:IsA("BoolValue") then
        connect(Dash:GetPropertyChangedSignal("Value"), function()
            if Dash.Value then
                clearLocalRunnerRoll(true)
                armNativeRunnerRoll(Dash)
            else
                Hub.NativeRollWindow = nil
            end
        end)
    end

    local DashCooldown = LocalPlayer:FindFirstChild("DashCooldown")
    if DashCooldown and DashCooldown:IsA("BoolValue") then
        connect(DashCooldown:GetPropertyChangedSignal("Value"), function()
            if not DashCooldown.Value and Hub.LocalRollSession then
                clearLocalRunnerRoll(true)
            end
        end)
    end

    syncRollMobileButton()

    connect(Players.PlayerAdded, function()
        task.defer(refreshPlayerDropdown)
    end)

    connect(Players.PlayerRemoving, function(Player)
        removeESP(Player)
        task.defer(refreshPlayerDropdown)
    end)

    connect(RoundState:GetPropertyChangedSignal("Value"), function()
        cancelElevatorWarning(true)
        clearRunnerRollState(true)
        Hub.AutoMonsterGeneration += 1
        Hub.AutoRunnerGeneration += 1
        Hub.AutoRollGeneration += 1
        Hub.AutoMonsterBusy = false
        Hub.AutoRollBusy = false
        restoreElevatorAnchor()
        Hub.AutoRunnerBusy = false
        clearAutoRunnerPending(true)
        syncAutoRunnerCounter()
        Hub.AutoRunnerReadyAt = RoundState.Value == "Game" and os.clock() + 0.5 or 0
        Hub.NextAutoMonsterAction = 0
        Hub.NextAutoRunnerAttempt = 0
        Hub.NextAutoRollAttempt = 0
        if Hub.MonsterESP or Hub.PlayerESP then
            syncESP()
        end
    end)

    connect(SelectedMonster:GetPropertyChangedSignal("Value"), function()
        if Hub.MonsterESP or Hub.PlayerESP then
            syncESP()
        end
        if Hub.PrivacyMode then
            task.defer(function()
                if Hub.PrivacyMode then
                    Hub.Privacy:Sync()
                end
            end)
        end
    end)

    local function cancelAutoFarmActions()
        cancelElevatorWarning(true)
        clearRunnerRollState(true)
        Hub.AutoMonsterGeneration += 1
        Hub.AutoRunnerGeneration += 1
        Hub.AutoRollGeneration += 1
        Hub.AutoMonsterBusy = false
        Hub.AutoRunnerBusy = false
        Hub.AutoRollBusy = false
        clearAutoRunnerPending(true)
        Hub.AutoRunnerReadyAt = 0
        Hub.NextAutoRollAttempt = 0
        restoreElevatorAnchor()
    end

    connect(Cutscene:GetPropertyChangedSignal("Value"), function()
        if Cutscene.Value then
            cancelAutoFarmActions()
        end
    end)

    connect(RoundEnded:GetPropertyChangedSignal("Value"), function()
        if RoundEnded.Value then
            cancelAutoFarmActions()
        end
    end)

    connect(LocalPlayer:GetPropertyChangedSignal("Team"), function()
        cancelElevatorWarning(true)
        clearRunnerRollState(true)
        Hub.AutoMonsterGeneration += 1
        Hub.AutoRunnerGeneration += 1
        Hub.AutoRollGeneration += 1
        Hub.AutoMonsterBusy = false
        Hub.AutoRollBusy = false
        restoreElevatorAnchor()
        Hub.AutoRunnerBusy = false
        clearAutoRunnerPending(true)
        syncAutoRunnerCounter()
        Hub.AutoRunnerReadyAt = LocalPlayer.Team == Runners and RoundState.Value == "Game" and os.clock() + 0.5 or 0
        Hub.NextAutoMonsterAction = 0
        Hub.NextAutoRunnerAttempt = 0
        Hub.NextAutoRollAttempt = 0
        if Hub.PrivacyMode then
            task.defer(function()
                if Hub.PrivacyMode then
                    Hub.Privacy:Sync()
                end
            end)
        end
    end)

    connect(LocalPlayer.Idled, function()
        if Hub.Alive and Hub.AntiAFK then
            local Camera = Workspace.CurrentCamera
            pcall(VirtualUser.CaptureController, VirtualUser)
            if Camera then
                pcall(VirtualUser.ClickButton2, VirtualUser, Vector2.zero, Camera.CFrame)
            end
        end
    end)

    local Events = ReplicatedStorage:FindFirstChild("Events")
    local EndingEvent = Events and Events:FindFirstChild("EndingEvent")
    if EndingEvent and EndingEvent:IsA("RemoteEvent") then
        connect(EndingEvent.OnClientEvent, function()
            if Hub.AutoRunnerPending then
                local Now = os.clock()
                Hub.AutoRunnerEndingSignalAt = Now
                Hub.AutoRunnerConfirmedAt = Hub.AutoRunnerConfirmedAt > 0 and Hub.AutoRunnerConfirmedAt or Now
                Hub.AutoRunnerAwaitingRespawn = true
            end
        end)
    end

    local EscapesInOneRound = LocalPlayer:FindFirstChild("EscapesInOneRound")
    if EscapesInOneRound then
        syncAutoRunnerCounter()
        connect(EscapesInOneRound:GetPropertyChangedSignal("Value"), function()
            cancelElevatorWarning(true)
            local Previous = Hub.AutoRunnerRoundEscapes
            local Current = EscapesInOneRound.Value
            Hub.AutoRunnerRoundEscapes = Current
            Hub.AutoRunnerCompleted = RoundState.Value == "Game" and LocalPlayer.Team == Runners and Current >= AutoRunnerEscapeLimit
            if Current > Previous then
                Hub.AutoRunnerGeneration += 1
                Hub.AutoRunnerBusy = false
                Hub.AutoRunnerAttempts = 0
                Hub.NextAutoRunnerAttempt = 0
                restoreElevatorAnchor()
                if Hub.AutoRunnerPending and Hub.AutoRunnerPendingEscapes and Current > Hub.AutoRunnerPendingEscapes and Current < AutoRunnerEscapeLimit then
                Hub.AutoRunnerPendingSince = os.clock()
                Hub.AutoRunnerAwaitingRespawn = true
                Hub.AutoRunnerConfirmedAt = os.clock()
                else
                    clearAutoRunnerPending(true)
                end
            elseif Current < Previous then
                Hub.AutoRunnerGeneration += 1
                Hub.AutoRunnerBusy = false
                restoreElevatorAnchor()
                clearAutoRunnerPending(true)
                Hub.AutoRunnerReadyAt = RoundState.Value == "Game" and os.clock() + 0.5 or 0
            end
        end)
    end

    connect(LocalPlayer.CharacterAdded, function()
        cancelElevatorWarning(true)
        clearRunnerRollState(true)
        local CurrentEscapes = LocalPlayer:FindFirstChild("EscapesInOneRound")
        local Current = CurrentEscapes and CurrentEscapes.Value or 0
        local Previous = Hub.AutoRunnerRoundEscapes
        local WasPending = Hub.AutoRunnerPending
        local PendingEscapes = Hub.AutoRunnerPendingEscapes
        local ConfirmedPending = WasPending and PendingEscapes ~= nil and Current > PendingEscapes
        Hub.AutoMonsterGeneration += 1
        Hub.AutoRunnerGeneration += 1
        Hub.AutoRollGeneration += 1
        Hub.AutoMonsterBusy = false
        Hub.AutoRunnerBusy = false
        Hub.AutoRollBusy = false
        Hub.AutoRunnerRoundEscapes = Current
        Hub.AutoRunnerCompleted = RoundState.Value == "Game" and LocalPlayer.Team == Runners and Current >= AutoRunnerEscapeLimit
        if ConfirmedPending or Current ~= Previous or Hub.AutoRunnerCompleted then
            clearAutoRunnerPending(true)
            Hub.AutoRunnerReadyAt = os.clock() + 1
        elseif WasPending then
            Hub.AutoRunnerAwaitingRespawn = true
            Hub.AutoRunnerConfirmedAt = Hub.AutoRunnerConfirmedAt > 0 and Hub.AutoRunnerConfirmedAt or os.clock()
        else
            clearAutoRunnerPending(false)
            Hub.AutoRunnerReadyAt = os.clock() + 0.5
        end
        Hub.NextAutoMonsterAction = 0
        Hub.NextAutoRunnerAttempt = 0
        Hub.NextAutoRollAttempt = 0
        restoreElevatorAnchor()
        Hub.MonsterMovementApplied = false
        if Hub.Fly then
            Toggles.Fly:SetValue(false)
        else
            clearFly()
        end
        restoreNoclip()
        task.defer(function()
            if not Hub.Alive then
                return
            end
            if Hub.PrivacyMode and LocalPlayer.Character then
                Hub.Privacy:WatchRoot(LocalPlayer.Character, true)
                Hub.Privacy:Sync()
            end
            syncRollMobileButton()
            if Hub.Noclip then
                applyNoclip()
            end
            if Hub.SpeedEnabled or Hub.JumpEnabled then
                applyMovement()
            end
            applyMonsterMovementBypasses()
        end)
    end)

    connect(RunService.Stepped, function()
        if Hub.Alive and Hub.Noclip then
            applyNoclip()
        end
    end)

    RunService:UnbindFromRenderStep(Hub.RenderName)
    RunService:BindToRenderStep(Hub.RenderName, Enum.RenderPriority.Last.Value, function()
        if not Hub.Alive then
            return
        end
        if Hub.SpeedEnabled or Hub.JumpEnabled then
            applyMovement()
        end
        if Hub.MoveWhileKilling or Hub.NoCrawlSlowdown or Hub.MonsterMovementApplied then
            applyMonsterMovementBypasses()
        end
        local Session = Hub.LocalRollSession
        if Session and Session.Humanoid and Session.Humanoid.Parent and LocalPlayer.Character == Session.Character then
            Session.Humanoid.WalkSpeed = 10
            Session.Humanoid.UseJumpPower = false
            Session.Humanoid.JumpHeight = 0
        end
    end)

    connect(RunService.PreSimulation, function()
        if not Hub.Alive then
            return
        end
        if Hub.MoveWhileKilling or Hub.NoCrawlSlowdown or Hub.MonsterMovementApplied then
            if Hub.SpeedEnabled or Hub.JumpEnabled then
                applyMovement()
            end
            applyMonsterMovementBypasses()
        end
        if Hub.NoRollCooldown or Hub.RollSpeedBoost or Hub.LocalRollSession or Hub.NativeRollWindow or Hub.RollAnimationTrack then
            applyRunnerRollMotion()
        end
    end)

    connect(RunService.Heartbeat, function(Delta)
        if not Hub.Alive then
            return
        end

        local Clock = Hub.SchedulerClock
        Clock.ESP += Delta
        Clock.Hitbox += Delta
        Clock.Aura += Delta
        Clock.State += Delta
        Clock.AutoFarm += Delta
        Clock.Stats += Delta

        if Clock.ESP >= 0.25 then
            Clock.ESP = 0
            if Hub.MonsterESP or Hub.PlayerESP then
                syncESP()
            end
        end

        if Clock.Hitbox >= 0.25 then
            Clock.Hitbox = 0
            if Hub.PlayerHitboxes then
                syncHitboxes()
            end
        end

        if Clock.Aura >= 0.1 then
            Clock.Aura = 0
            runKillAura()
        end

        if Clock.AutoFarm >= 0.2 then
            Clock.AutoFarm = 0
            runAutoTicketExchange()
            runAutoRankUp()
            runAutoRoll()
            runAutoMonsterFarm()
            runAutoRunnerWin()
        end

        if Clock.Stats >= 1 then
            Clock.Stats = 0
            updateSessionStats()
            runWebhookQueue()
        end

        if Clock.State >= 0.5 then
            Clock.State = 0
            if Hub.PrivacyMode then
                Hub.Privacy:Sync()
            end
            if Hub.NoRollCooldown then
                syncRollMobileButton()
            end
            if Hub.Fullbright then
                applyFullbright()
            end
            if Hub.NoFog then
                applyNoFog()
            end
            if Hub.ColorGrade then
                applyColorGrade()
            end
            if Environment.MonsterRunnersFinal ~= Hub then
                unload(false)
                return
            end
            if Library.Unloaded then
                unload(true)
            end
        end
    end)
end

Library.ToggleKeybind = Options.MenuKeybind

SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind", "PlayerTeleportTarget", "WebhookURL", "WebhookNotifications"})
ThemeManager:SetFolder("MonsterRunnersObsidian")
SaveManager:SetFolder("MonsterRunnersObsidian")
SaveManager:SetSubFolder(tostring(game.PlaceId))
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()

Library:Notify({
    Title = "Monster Runners",
    Description = "Script loaded",
    Time = 6
})

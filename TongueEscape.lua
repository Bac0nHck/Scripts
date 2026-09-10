-- https://www.roblox.com/games/122245938604556/1-Tongue-Escape
if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.PlaceId ~= 122245938604556 then
    error("This script supports +1 Tongue Escape only.")
end

local Environment = getgenv()
local Previous = Environment.__TongueEscape
if Previous and type(Previous.Unload) == "function" then
    Previous.Unload()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")
local Player = Players.LocalPlayer
local Events = ReplicatedStorage:WaitForChild("Events", 15)
local Modules = ReplicatedStorage:WaitForChild("Modules", 15)
local SharedModule = ReplicatedStorage:WaitForChild("TongueShared", 15)
assert(Events and Modules and SharedModule, "Game data is unavailable. Rejoin and try again.")

local Shared = require(SharedModule)
local PlaytimeConfig = require(Modules:WaitForChild("PlaytimeRewardsConfig", 10))
local TrailConfig = require(Modules:WaitForChild("TrailConfigurations", 10))
local GameName = "+1 Tongue Escape \240\159\152\155"
local FooterText = "t.me/arceusxcommunity"
pcall(function()
    local Value = game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
    Value = Value:gsub("^%s+", ""):gsub("%s+$", "")
    if #Value > 0 and #Value <= 300 and not Value:find("<html") then
        FooterText = Value
    end
end)

local LibraryUrl = "https://raw.githubusercontent.com/Ali-lov3/Obsidian-UiLibs/refs/heads/main/Library.lua"
local Loaded, Library = pcall(function()
    return loadstring(game:HttpGet(LibraryUrl))()
end)
assert(Loaded and type(Library) == "table", "Unable to load Obsidian. Check your connection and try again.")

local State = {
    Alive = true,
    Flags = {AutoTongue = false, AutoRebirth = false, AutoWins = false, AutoRewards = false, AutoTrails = false, AntiAFK = false, BypassPause = false},
    Status = {AutoTongue = "Off", AutoRebirth = "Off", AutoWins = "Off", AutoRewards = "Off", AutoTrails = "Off", AntiAFK = "Off", BypassPause = "Off"},
    Connections = {},
    Threads = {},
    IdleConnections = {},
    RetryAt = {},
    LastError = {},
    TongueInterval = 0.02,
    WinInterval = 1.5,
    WinGeneration = 0,
    WinMisses = 0,
    Library = Library,
    Ready = false,
}
Environment.__TongueEscape = State

local function Stat(Name)
    local Stats = Player:FindFirstChild("leaderstats")
    local Value = Stats and Stats:FindFirstChild(Name)
    return Value and tonumber(Value.Value) or 0
end

local function CharacterParts()
    local Character = Player.Character
    local Root = Character and Character:FindFirstChild("HumanoidRootPart")
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    if Root and Humanoid and Humanoid.Health > 0 then
        return Character, Root, Humanoid
    end
end

local function Number(Value)
    local Text = string.format("%.0f", Value)
    return Text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function NotifyFailure(Key, Message)
    State.Status[Key] = "Retrying"
    local Now = os.clock()
    if Now - (State.LastError[Key] or -math.huge) > 30 then
        State.LastError[Key] = Now
        Library:Notify({Title = "Tongue Escape", Description = Message, Time = 5})
    end
end

local function Fire(Name, ...)
    local Remote = Events:FindFirstChild(Name)
    assert(Remote and Remote:IsA("RemoteEvent"), "Missing game event: " .. Name)
    Remote:FireServer(...)
end

local function ReadProperty(Object, Property)
    local Success, Value = pcall(function()
        return Object[Property]
    end)
    if not Success and type(gethiddenproperty) == "function" then
        Success, Value = pcall(gethiddenproperty, Object, Property)
    end
    return Success, Value
end

local function WriteProperty(Object, Property, Value)
    local Success = pcall(function()
        Object[Property] = Value
    end)
    if not Success and type(sethiddenproperty) == "function" then
        Success = pcall(sethiddenproperty, Object, Property, Value)
    end
    return Success
end

local function RestorePause()
    if State.PauseConnection then
        State.PauseConnection:Disconnect()
        State.PauseConnection = nil
    end
    if State.PauseModeChanged and State.OriginalPauseMode ~= nil then
        WriteProperty(workspace, "StreamingIntegrityMode", State.OriginalPauseMode)
    end
    if State.OriginalPauseNotice ~= nil then
        pcall(function()
            GuiService:SetGameplayPausedNotificationEnabled(State.OriginalPauseNotice)
        end)
    end
    State.PauseModeChanged = nil
    State.OriginalPauseMode = nil
    State.OriginalPauseNotice = nil
end

local function ClearPause()
    if not State.Alive or not State.Flags.BypassPause then
        return
    end
    if Player.GameplayPaused then
        local Cleared = WriteProperty(Player, "GameplayPaused", false)
        State.Status.BypassPause = Cleared and "Active" or "Overlay hidden; loading map"
    end
end

local function SetPauseBypass(Enabled)
    RestorePause()
    if not Enabled then
        State.Status.BypassPause = "Off"
        return
    end
    local ReadMode, Mode = ReadProperty(workspace, "StreamingIntegrityMode")
    if ReadMode then
        State.OriginalPauseMode = Mode
        State.PauseModeChanged = WriteProperty(workspace, "StreamingIntegrityMode", Enum.StreamingIntegrityMode.Disabled)
    end
    local ReadNotice, Notice = pcall(function()
        return GuiService:GetGameplayPausedNotificationEnabled()
    end)
    if ReadNotice then
        State.OriginalPauseNotice = Notice
        pcall(function()
            GuiService:SetGameplayPausedNotificationEnabled(false)
        end)
    end
    State.PauseConnection = Player:GetPropertyChangedSignal("GameplayPaused"):Connect(ClearPause)
    State.Status.BypassPause = "Active"
    ClearPause()
end

local function RestoreAFK()
    if State.IdleHandler then
        State.IdleHandler:Disconnect()
        State.IdleHandler = nil
    end
    for _, Connection in State.IdleConnections do
        pcall(function()
            Connection:Enable()
        end)
    end
    table.clear(State.IdleConnections)
    if State.GameAFKScript and State.GameAFKScript.Parent and State.GameAFKWasEnabled then
        pcall(function()
            State.GameAFKScript.Enabled = true
        end)
    end
    State.GameAFKScript = nil
    State.GameAFKWasEnabled = nil
end

local function SetAFK(Enabled)
    RestoreAFK()
    if not Enabled then
        State.Status.AntiAFK = "Off"
        return
    end
    local Scripts = Player:FindFirstChild("PlayerScripts")
    local AFKScript = Scripts and Scripts:FindFirstChild("AntiAfkSystem")
    if AFKScript and AFKScript:IsA("LocalScript") then
        local Success, WasEnabled = pcall(function()
            local Old = AFKScript.Enabled
            AFKScript.Enabled = false
            return Old
        end)
        if Success then
            State.GameAFKScript = AFKScript
            State.GameAFKWasEnabled = WasEnabled
        end
    end
    if type(getconnections) == "function" then
        pcall(function()
            for _, Connection in getconnections(Player.Idled) do
                if Connection.Enabled then
                    local Success = pcall(function()
                        Connection:Disable()
                    end)
                    if Success then
                        table.insert(State.IdleConnections, Connection)
                    end
                end
            end
        end)
    end
    State.IdleHandler = Player.Idled:Connect(function()
        if not State.Alive or not State.Flags.AntiAFK then
            return
        end
        local Success = pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.zero)
        end)
        if not Success and #State.IdleConnections == 0 then
            State.Status.AntiAFK = "Input unavailable"
        end
    end)
    State.Status.AntiAFK = "Active"
end

local function StopAll()
    for Key in State.Flags do
        local Toggle = Library.Toggles[Key]
        if Toggle then
            Toggle:SetValue(false)
        else
            State.Flags[Key] = false
        end
    end
end

local function Cleanup()
    if not State.Alive then
        return
    end
    State.Alive = false
    State.WinGeneration += 1
    for Key in State.Flags do
        State.Flags[Key] = false
    end
    for _, Connection in State.Connections do
        Connection:Disconnect()
    end
    for _, Thread in State.Threads do
        if Thread ~= coroutine.running() then
            pcall(task.cancel, Thread)
        end
    end
    RestoreAFK()
    RestorePause()
    if Environment.__TongueEscape == State then
        Environment.__TongueEscape = nil
    end
end

State.Unload = function()
    if not Library.Unloaded then
        Library:Unload()
    else
        Cleanup()
    end
end
Library:OnUnload(Cleanup)
Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = false
Library.Scheme.AccentColor = Color3.fromRGB(255, 106, 143)

local Viewport = workspace.CurrentCamera.ViewportSize
local TouchLayout = Library.IsMobile or UserInputService.TouchEnabled
Library.OriginalMinSize = Vector2.new(280, 240)
Library.MinSize = Library.OriginalMinSize

local Window = Library:CreateWindow({
    Title = "Tongue Escape",
    Footer = GameName .. " | " .. FooterText,
    Icon = "activity",
    Size = UDim2.fromOffset(math.min(570, Viewport.X - 64), math.min(610, Viewport.Y - 64)),
    Font = Enum.Font.Gotham,
    Center = true,
    AutoShow = true,
    Resizable = true,
    ShowCustomCursor = false,
    ShowMobileButtons = true,
    MobileButtonsSide = "Left",
    SidebarCompacted = true,
    ToggleKeybind = Enum.KeyCode.RightControl,
    CornerRadius = 8,
    Glow = false,
    DisableSearch = true,
    NotifySide = "Right",
})
State.Window = Window

local FarmTab = Window:AddFullSizeTab("Farm", "sprout", "Automation")
local SettingsTab = Window:AddFullSizeTab("Settings", "settings", "Timing and controls")
local Automation = FarmTab:AddGroupbox("Automatic", "repeat")
local StatusBox = FarmTab:AddGroupbox("Live progress", "chart-no-axes-combined")
local TeleportBox = FarmTab:AddGroupbox("Teleport", "map-pin")
local Timing = SettingsTab:AddGroupbox("Timing", "timer")
local Menu = SettingsTab:AddGroupbox("Menu", "settings")
State.Tabs = {Farm = FarmTab, Settings = SettingsTab}

local ToggleNames = {
    {"AutoTongue", "Auto Farm Tongue"},
    {"AutoRebirth", "Auto Rebirth"},
    {"AutoWins", "Auto Farm Wins"},
    {"AutoRewards", "Auto Claim Rewards"},
    {"AutoTrails", "Auto Buy Trails"},
    {"AntiAFK", "Anti-AFK"},
    {"BypassPause", "Bypass Gameplay Paused"},
}

for _, Item in ToggleNames do
    local Key = Item[1]
    local Toggle = Automation:AddToggle(Key, {
        Text = Item[2],
        Default = false,
        Callback = function(Value)
            State.Flags[Key] = Value
            State.Status[Key] = Value and "Starting" or "Off"
            if Key == "AntiAFK" then
                SetAFK(Value)
            elseif Key == "BypassPause" then
                SetPauseBypass(Value)
            elseif Key == "AutoWins" then
                State.WinGeneration += 1
                State.WinMisses = 0
            end
        end,
    })
    Toggle.Holder.Size = UDim2.new(1, 0, 0, TouchLayout and 44 or 32)
    Toggle.TextLabel.TextSize = TouchLayout and 16 or 15
    Toggle.TextLabel.TextWrapped = true
    for _, Child in Toggle.Holder:GetChildren() do
        if Child:IsA("Frame") then
            Child.AnchorPoint = Vector2.new(1, 0.5)
            Child.Position = UDim2.fromScale(1, 0.5)
        end
    end
end
Automation:Resize()

local StatsLabel = StatusBox:AddLabel("Loading stats...", true)
local RebirthLabel = StatusBox:AddLabel("Loading rebirth requirement...", true)
local WorkLabel = StatusBox:AddLabel("All automation is off.", true)
local RewardsLabel = StatusBox:AddLabel("Loading rewards...", true)

local StageList = {}
local StageTargets = {}
local Map = workspace:FindFirstChild("Map")
local Stages = Map and Map:FindFirstChild("Stages")
if Stages then
    local Sorted = {}
    for _, Stage in Stages:GetChildren() do
        local Index = tonumber(Stage.Name:match("^Stage(%d+)$"))
        if Index then
            table.insert(Sorted, {Index = Index, Folder = Stage})
        end
    end
    table.sort(Sorted, function(A, B)
        return A.Index < B.Index
    end)
    for _, Entry in Sorted do
        local Label = "Stage " .. Entry.Index
        table.insert(StageList, Label)
        StageTargets[Label] = Entry
    end
    local FinalStage = Sorted[#Sorted]
    local Portal = FinalStage and FinalStage.Folder:FindFirstChild("Portal", true)
    if Portal and Portal:IsA("Model") then
        local Label = "Finish / Portal"
        table.insert(StageList, Label)
        StageTargets[Label] = {Folder = FinalStage.Folder, Anchor = Portal}
    end
end
State.SelectedStage = StageList[1]
local StageDropdown = TeleportBox:AddDropdown("TeleportStage", {
    Text = "Destination",
    Values = StageList,
    Default = 1,
    Multi = false,
    Searchable = false,
    MaxVisibleDropdownItems = 5,
    Callback = function(Value)
        State.SelectedStage = Value
    end,
})
local TeleportButton
local function TeleportToStage()
    if not State.Alive or State.TeleportBusy then
        return
    end
    local Selected = State.SelectedStage
    local Entry = StageTargets[Selected]
    local Character, Root, Humanoid = CharacterParts()
    if not Entry or not Root then
        Library:Notify({Title = "Teleport", Description = "Select a destination and wait for your character to spawn.", Time = 4})
        return
    end
    local Anchor = Entry.Anchor or Entry.Folder:FindFirstChild("StagePillars" .. Entry.Index, true)
    if not Anchor or not Anchor:IsA("Model") then
        Library:Notify({Title = "Teleport", Description = "The stage entrance is not available yet.", Time = 4})
        return
    end
    State.TeleportBusy = true
    Library.Toggles.AutoWins:SetValue(false)
    TeleportButton:SetDisabled(true)
    TeleportButton:SetText("Loading...")
    table.insert(State.Threads, task.spawn(function()
        local Success, Problem = pcall(function()
            local Entrance = Anchor:GetPivot().Position
            pcall(function()
                Player:RequestStreamAroundAsync(Entrance, 4)
            end)
            local Params = RaycastParams.new()
            Params.FilterType = Enum.RaycastFilterType.Exclude
            local Excluded = {}
            for _, Other in Players:GetPlayers() do
                if Other.Character then
                    table.insert(Excluded, Other.Character)
                end
            end
            Params.FilterDescendantsInstances = Excluded
            Params.RespectCanCollide = true
            local Ground
            local Deadline = os.clock() + 3
            repeat
                if not State.Alive or Player.Character ~= Character or Humanoid.Health <= 0 then
                    return
                end
                for _, Offset in {14, 6, 0, -6} do
                    local Hit = workspace:Raycast(Entrance + Vector3.new(Offset, 20, 0), Vector3.new(0, -120, 0), Params)
                    if Hit and Hit.Normal.Y > 0.7 and not Hit.Instance.Name:lower():find("kill") and not Hit.Instance.Parent.Name:lower():find("kill") then
                        Ground = Hit.Position
                        break
                    end
                end
                if not Ground then
                    task.wait(0.15)
                end
            until Ground or os.clock() >= Deadline
            if not Ground then
                error("The stage floor is still loading. Try again.", 0)
            end
            if not State.Alive or Player.Character ~= Character or Humanoid.Health <= 0 then
                return
            end
            local Position = Ground + Vector3.new(0, Humanoid.HipHeight + Root.Size.Y / 2 + 0.5, 0)
            Humanoid.Sit = false
            Root.AssemblyLinearVelocity = Vector3.zero
            Root.AssemblyAngularVelocity = Vector3.zero
            Character:PivotTo(CFrame.lookAt(Position, Position + Vector3.new(-1, 0, 0)))
            State.LastTeleport = {Stage = Selected, Position = Position}
        end)
        State.TeleportBusy = false
        if State.Alive then
            TeleportButton:SetDisabled(false)
            TeleportButton:SetText("Teleport")
            if not Success then
                Library:Notify({Title = "Teleport", Description = tostring(Problem), Time = 5})
            end
        end
    end))
end
TeleportButton = TeleportBox:AddButton({Text = "Teleport", Func = TeleportToStage})
TeleportButton.Holder.Size = UDim2.new(1, 0, 0, TouchLayout and 44 or 30)
State.TeleportToStage = TeleportToStage
State.TeleportButton = TeleportButton
State.TeleportBox = TeleportBox
if TouchLayout then
    StageDropdown.Holder.Size = UDim2.new(1, 0, 0, 62)
    for _, Child in StageDropdown.Holder:GetChildren() do
        if Child:IsA("TextButton") then
            Child.Size = UDim2.new(1, 0, 0, 44)
        end
    end
end
TeleportBox:Resize()

Timing:AddSlider("TongueInterval", {
    Text = "Tongue interval",
    Default = 0.02,
    Min = 0.02,
    Max = 1,
    Rounding = 2,
    Suffix = "s",
    Callback = function(Value)
        State.TongueInterval = Value
    end,
})
Timing:AddSlider("WinInterval", {
    Text = "Win interval",
    Default = 1.5,
    Min = 0.5,
    Max = 5,
    Rounding = 1,
    Suffix = "s",
    Callback = function(Value)
        State.WinInterval = Value
    end,
})
Menu:AddLabel("Menu key"):AddKeyPicker("MenuKeybind", {
    Default = "RightControl",
    NoUI = true,
    Text = "Menu key",
})
Library.ToggleKeybind = Library.Options.MenuKeybind
Menu:AddButton({Text = "Stop All", Func = StopAll})
Menu:AddButton({Text = "Unload", Func = State.Unload})

local MainFrame = Library.ScreenGui:FindFirstChild("Main")
local FooterLabel
for _, Label in Library.ScreenGui:QueryDescendants("TextLabel") do
    if Label.Text == GameName .. " | " .. FooterText then
        FooterLabel = Label
        FooterLabel.RichText = false
        FooterLabel.TextTransparency = 0.2
        break
    end
end

local function FitWindow(Size)
    if not MainFrame or not MainFrame.Parent then
        return
    end
    Size = Size or workspace.CurrentCamera.ViewportSize
    local Width = math.max(240, math.min(570, Size.X - 64))
    local Height = math.max(200, math.min(610, Size.Y - 64))
    MainFrame.Size = UDim2.fromOffset(Width, Height)
    MainFrame.Position = UDim2.fromOffset((Size.X - Width) / 2, (Size.Y - Height) / 2)
    MainFrame.AnchorPoint = Vector2.zero
    if FooterLabel then
        FooterLabel.TextSize = Width < 400 and 10 or 12
    end
    FarmTab:Resize()
    SettingsTab:Resize()
end
State.FitWindow = FitWindow
local CameraConnection
local function WatchCamera()
    if CameraConnection then
        CameraConnection:Disconnect()
    end
    local Camera = workspace.CurrentCamera
    if Camera then
        CameraConnection = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            FitWindow()
        end)
        table.insert(State.Connections, CameraConnection)
        FitWindow()
    end
end
table.insert(State.Connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(WatchCamera))
WatchCamera()
Library.Toggles.BypassPause:SetValue(true)

local function StartLoop(Key, Interval, Action)
    local Thread = task.spawn(function()
        while State.Alive do
            if State.Flags[Key] then
                local Success = pcall(Action)
                if not Success and State.Alive and State.Flags[Key] then
                    NotifyFailure(Key, "A game action is temporarily unavailable. Retrying automatically.")
                    task.wait(2)
                end
            end
            task.wait(type(Interval) == "function" and Interval() or Interval)
        end
    end)
    table.insert(State.Threads, Thread)
end

StartLoop("AutoTongue", function()
    return State.TongueInterval
end, function()
    if not CharacterParts() then
        State.Status.AutoTongue = "Waiting for respawn"
        return
    end
    Fire("AddTongue")
    State.Status.AutoTongue = "Training"
end)

StartLoop("AutoRebirth", 1, function()
    local Required = Shared.levelForRebirth(Stat("Rebirths"))
    if Stat("Level") < Required then
        State.Status.AutoRebirth = "Waiting for level " .. Number(Required)
        return
    end
    local Remote = Events:FindFirstChild("RequestRebirth")
    assert(Remote and Remote:IsA("RemoteFunction"), "Rebirth is unavailable")
    State.Status.AutoRebirth = "Rebirthing"
    local Accepted = Remote:InvokeServer()
    if State.Alive and State.Flags.AutoRebirth then
        State.Status.AutoRebirth = Accepted and "Rebirth complete" or "Waiting for server"
    end
end)

StartLoop("AutoTrails", 1, function()
    local Owned = Player:FindFirstChild("Trails")
    if not Owned then
        State.Status.AutoTrails = "Waiting for inventory"
        return
    end
    local BestOwned, Purchase
    local Remaining = 0
    local Wins = Stat("Wins")
    for _, Trail in TrailConfig.Trails do
        if Owned:FindFirstChild(Trail.ID) then
            if not BestOwned or Trail.TongueBoost > BestOwned.TongueBoost then
                BestOwned = Trail
            end
        elseif type(Trail.WinCost) == "number" and Trail.WinCost >= 0 then
            Remaining += 1
            if Trail.WinCost <= Wins and (not Purchase or Trail.TongueBoost > Purchase.TongueBoost) then
                Purchase = Trail
            end
        end
    end
    local Now = os.clock()
    local Equipped = Owned:FindFirstChild("Equipped")
    if BestOwned and Equipped and Equipped.Value ~= BestOwned.ID and Now >= (State.RetryAt.EquipTrail or 0) then
        Fire("TrailAction", "Equip", BestOwned.ID)
        State.RetryAt.EquipTrail = Now + 3
    end
    if State.PendingTrail then
        if Owned:FindFirstChild(State.PendingTrail.ID) then
            State.PendingTrail = nil
        elseif Now < State.PendingTrail.Until then
            State.Status.AutoTrails = "Buying " .. State.PendingTrail.Name
            return
        else
            State.PendingTrail = nil
        end
    end
    if Purchase then
        Fire("TrailAction", "BuyWins", Purchase.ID)
        State.PendingTrail = {ID = Purchase.ID, Name = Purchase.Name, Until = Now + 5}
        State.Status.AutoTrails = "Buying " .. Purchase.Name
    elseif Remaining == 0 then
        State.Status.AutoTrails = "All trails owned"
    else
        State.Status.AutoTrails = "Waiting for Wins"
    end
end)

local function BestWinButton()
    local Map = workspace:FindFirstChild("Map")
    local GiveWins = Map and Map:FindFirstChild("GiveWins")
    local Row = GiveWins and GiveWins:FindFirstChild("OneWin")
    if not Row then
        return
    end
    local Best, BestAmount = nil, -1
    for _, Model in Row:GetChildren() do
        local Amount = tonumber(Model:GetAttribute("WinAmount")) or 0
        if Model:IsA("Model") and Amount > BestAmount then
            Best, BestAmount = Model, Amount
        end
    end
    return Best, BestAmount
end

StartLoop("AutoWins", function()
    return State.WinInterval
end, function()
    local Character, Root, Humanoid = CharacterParts()
    if not Root then
        State.Status.AutoWins = "Waiting for respawn"
        return
    end
    local Generation = State.WinGeneration
    local Model, Amount = BestWinButton()
    if not Model then
        State.Status.AutoWins = "Waiting for map"
        return
    end
    local Pivot = Model:GetPivot()
    local Touch = Model:FindFirstChild("Touch")
    if not Touch then
        State.Status.AutoWins = "Loading finish area"
        pcall(function()
            Player:RequestStreamAroundAsync(Pivot.Position, 3)
        end)
        Touch = Model:FindFirstChild("Touch")
    end
    if not State.Alive or not State.Flags.AutoWins or Generation ~= State.WinGeneration or Player.Character ~= Character then
        return
    end
    local Before = Stat("Wins")
    State.Status.AutoWins = "Collecting " .. Number(Amount) .. " wins"
    local UsedTouch = false
    if Touch and Touch:IsA("BasePart") and type(firetouchinterest) == "function" and State.WinMisses < 2 then
        UsedTouch = pcall(function()
            firetouchinterest(Root, Touch, 0)
            task.wait(0.1)
            if Root.Parent and Touch.Parent then
                firetouchinterest(Root, Touch, 1)
            end
        end)
    end
    if not State.Alive or not State.Flags.AutoWins or Generation ~= State.WinGeneration or Player.Character ~= Character then
        return
    end
    if not UsedTouch then
        local Target = Touch and Touch.CFrame or Pivot
        Humanoid.Sit = false
        if (Root.Position - Target.Position).Magnitude < 12 then
            Character:PivotTo(Target + Vector3.new(0, 7, 14))
            task.wait(0.15)
            if not State.Alive or not State.Flags.AutoWins or Generation ~= State.WinGeneration or Player.Character ~= Character then
                return
            end
        end
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Character:PivotTo(Target + Vector3.new(0, 3, 0))
    end
    local Deadline = os.clock() + 1.2
    repeat
        task.wait(0.1)
    until not State.Alive or not State.Flags.AutoWins or Generation ~= State.WinGeneration or Stat("Wins") > Before or os.clock() >= Deadline
    if State.Alive and State.Flags.AutoWins and Generation == State.WinGeneration then
        local Collected = Stat("Wins") > Before
        State.WinMisses = Collected and 0 or State.WinMisses + 1
        State.Status.AutoWins = Collected and "Wins collected" or "Waiting for finish cooldown"
    end
end)

local function ClaimOnce(Key, Remote, Cooldown, ...)
    if not State.Flags.AutoRewards or not State.Alive then
        return
    end
    local Now = os.clock()
    if Now < (State.RetryAt[Key] or 0) then
        return
    end
    Fire(Remote, ...)
    State.RetryAt[Key] = Now + Cooldown
    task.wait(0.2)
end

StartLoop("AutoRewards", 5, function()
    local Now = workspace:GetServerTimeNow()
    local Start = Player:GetAttribute("PlaytimeStart")
    local Elapsed = typeof(Start) == "number" and math.max(0, (tonumber(Player:GetAttribute("PlaytimeBase")) or 0) + Now - Start) or 0
    local Claimed = {}
    for Index in tostring(Player:GetAttribute("PlaytimeClaimed") or ""):gmatch("%d+") do
        Claimed[tonumber(Index)] = true
    end
    for Index, Reward in PlaytimeConfig.Rewards do
        if not Claimed[Index] and Elapsed >= Reward.Minute * 60 then
            ClaimOnce("Playtime" .. Index, "PlaytimeClaim", 10, Index)
        end
    end
    local LastDaily = tonumber(Player:GetAttribute("DailyLastClaim"))
    if LastDaily and (LastDaily <= 0 or Now - LastDaily >= 86400) then
        ClaimOnce("Daily", "DailyClaim", 15)
    end
    if Player:GetAttribute("LeaveBonusClaimed") == false then
        ClaimOnce("LeaveBonus", "LeaveBonusClaim", 30)
    end
    if Player:GetAttribute("GroupRewardClaimed") == false then
        local CheckAt = State.RetryAt.GroupCheck or 0
        if os.clock() >= CheckAt then
            State.RetryAt.GroupCheck = os.clock() + 120
            local Success, Member = pcall(function()
                return Player:IsInGroupAsync(602332660)
            end)
            if not Success then
                Success, Member = pcall(function()
                    return Player:IsInGroup(602332660)
                end)
            end
            if Success and Member then
                ClaimOnce("Group", "GroupRewardClaim", 120)
            end
        end
    end
    if State.Flags.AutoRewards then
        State.Status.AutoRewards = "Watching reward timers"
    end
end)

local function RefreshStatus()
    StatsLabel:SetText("Tongue: " .. Number(Stat("Tongue")) .. "   |   Level: " .. Number(Stat("Level")) .. "\nWins: " .. Number(Stat("Wins")) .. "   |   Rebirths: " .. Number(Stat("Rebirths")))
    RebirthLabel:SetText("Next rebirth: level " .. Number(Shared.levelForRebirth(Stat("Rebirths"))))
    local Active = {}
    for _, Item in ToggleNames do
        if State.Flags[Item[1]] then
            table.insert(Active, Item[2] .. ": " .. State.Status[Item[1]])
        end
    end
    WorkLabel:SetText(#Active > 0 and table.concat(Active, "\n") or "All automation is off.")
    local Count = 0
    for _ in tostring(Player:GetAttribute("PlaytimeClaimed") or ""):gmatch("%d+") do
        Count += 1
    end
    RewardsLabel:SetText("Playtime rewards: " .. Count .. "/" .. #PlaytimeConfig.Rewards .. " claimed")
end

table.insert(State.Threads, task.spawn(function()
    while State.Alive do
        pcall(RefreshStatus)
        task.wait(1)
    end
end))

Library:UpdateColorsUsingRegistry()
State.Ready = true
FarmTab:Show()

if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 605887098 then
    error("Halloween Farm: this game is not supported", 0)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Player = Players.LocalPlayer
local Environment = type(getgenv) == "function" and getgenv() or _G
local AppKey = "CDTHalloweenWindUI"
for _, key in ipairs({AppKey, "CDTHalloweenAirflow"}) do
    local previous = Environment[key]
    if type(previous) == "table" and type(previous.Unload) == "function" then
        pcall(previous.Unload, previous)
    end
end

local function moduleAt(folder, name)
    local root = ReplicatedStorage:WaitForChild(folder, 20)
    local source = root and root:WaitForChild(name, 20)
    if not source then
        error("Halloween Farm: required module is unavailable: " .. folder .. "." .. name, 0)
    end
    local ok, value = pcall(require, source)
    if not ok then
        error("Halloween Farm: could not load " .. name .. ": " .. tostring(value), 0)
    end
    return value
end

local Event = moduleAt("Databases", "HalloweenEvent")
local EventUtil = moduleAt("Util", "HalloweenEventUtil")
if not EventUtil.IsActive(Workspace:GetServerTimeNow()) then
    error("Halloween Farm: the Halloween event is not active", 0)
end
local Collectibles = moduleAt("Databases", "Collectibles")
local RolledUtil = moduleAt("Util", "RolledCollectibleUtil")
local PumpkinController = moduleAt("Controllers", "HalloweenPumpkinController")
local CrystalComponent = moduleAt("Components", "Collectible")
local PlayerData = moduleAt("Controllers", "PlayerDataController")
local UIState = moduleAt("UIStates", "HalloweenEvent")
local PumpkinGroup = Event.CollectibleGroup
local CrystalGroup = Event.CrystalGroup
local Roll = Collectibles[PumpkinGroup] and Collectibles[PumpkinGroup].Roll
if type(Roll) ~= "table" or type(RolledUtil.GetSpawn) ~= "function" then
    error("Halloween Farm: the collectible configuration is not supported", 0)
end

local App = {
    Running = true,
    Settings = {AutoPumpkins = false, AutoCrystals = false, AutoClaimRewards = false, AutoRace = false, AutoDriveDistance = false, AutoSpeedTraps = false, RaceVehicle = "Auto", QuestVehicle = "Auto", RaceLaps = 5, RaceDelay = 0.75, TeleportDelay = 0.75, AntiAFK = true},
    Controls = {},
    Connections = {},
    Tasks = {},
    Troves = {},
    Crystals = {},
    CrystalCollected = {},
    ConfirmedCrystals = {},
    ConfirmedPumpkins = {},
    InFlight = {},
    Cooldowns = {},
    Spots = {},
    Discovery = {},
    DiscoveryIndex = 1,
    Generation = 0,
    SessionPumpkins = 0,
    SessionCrystals = 0,
    SessionCurrency = 0,
    SessionRewards = 0,
    RewardAttempts = {},
    ClaimStatus = "Auto Claim Rewards is off",
    RaceStatus = "Auto Race is off",
    RaceVehicleName = "None",
    RacePointName = "None",
    RaceVehicleRecords = {},
    RaceVehicleLabels = {"Auto"},
    RaceState = {},
    QuestState = {},
    QuestStatus = "Quest automation is off",
    QuestVehicleName = "None",
    QuestCameras = {},
    SessionRaces = 0,
    SessionRacePumpkins = 0,
    Status = "Initializing",
    TargetName = "None",
    NextTeleportAt = 0,
    CrystalGoal = 50,
}
Environment[AppKey] = App

for _, objective in ipairs(Event.Objectives or {}) do
    if objective.Name == "GreenCrystals" then
        App.CrystalGoal = tonumber(objective.Goal) or 50
    end
end

function App:Warn(context, failure)
    self.LastError = context .. ": " .. tostring(failure)
    if os.clock() >= (self.NextWarning or 0) then
        self.NextWarning = os.clock() + 10
        warn("[Halloween Farm] " .. self.LastError)
    end
end

function App:Connect(signal, callback)
    if not self.Running then
        return
    end
    local connection = signal:Connect(function(...)
        if not self.Running then
            return
        end
        local ok, failure = pcall(callback, ...)
        if not ok then
            self:Warn("Event handler", failure)
        end
    end)
    table.insert(self.Connections, connection)
    return connection
end

function App:Spawn(callback)
    if not self.Running then
        return
    end
    local thread
    thread = task.spawn(function()
        local ok, failure = xpcall(callback, debug.traceback)
        if not ok and self.Running then
            self:Warn("Worker", failure)
        end
        if thread then
            self.Tasks[thread] = nil
        end
    end)
    if coroutine.status(thread) ~= "dead" then
        self.Tasks[thread] = true
    end
    return thread
end

function App:WithUI(callback, ...)
    local bridge = type(syn) == "table" and syn
    local getter = getthreadidentity or getidentity or get_thread_identity or bridge and bridge.get_thread_identity
    local setter = setthreadidentity or setidentity or set_thread_identity or bridge and bridge.set_thread_identity
    local original
    if type(getter) == "function" then
        local ok, value = pcall(getter)
        if ok and type(value) == "number" then
            original = value
        end
    end
    if type(setter) == "function" then
        pcall(setter, 8)
    end
    local result = table.pack(pcall(callback, ...))
    if original and type(setter) == "function" then
        pcall(setter, original)
    end
    if not result[1] then
        error(result[2], 0)
    end
    return table.unpack(result, 2, result.n)
end

function App:Notify(title, text, kind)
    return self:WithUI(function()
        if self.WindUI and self.Window and self.Running then
            local icons = {Success = "check", Warning = "triangle-alert", Info = "info"}
            pcall(self.WindUI.Notify, self.WindUI, {Title = title, Content = text, Icon = icons[kind] or "info", Duration = 4})
        end
    end)
end

function App:Copy(text)
    local clipboard = setclipboard or toclipboard
    if type(clipboard) == "function" then
        local ok = pcall(clipboard, text)
        if ok then
            self:Notify("Clipboard", "Copied to clipboard", "Success")
            return
        end
    end
    self:Notify("Clipboard", text, "Info")
end

function App:Balance()
    local ok, value = pcall(UIState.Pumpkins.get, UIState.Pumpkins)
    return ok and tonumber(value) or 0
end

function App:CrystalProgress()
    local count = 0
    for _, value in pairs(self.CrystalCollected) do
        if type(value) == "number" then
            count = count + 1
        end
    end
    local ok, objectives = pcall(UIState.Objectives.get, UIState.Objectives)
    local objective = ok and type(objectives) == "table" and objectives.GreenCrystals
    if type(objective) == "table" then
        count = math.max(count, tonumber(objective.Current) or 0)
    end
    return math.min(count, self.CrystalGoal)
end

function App:Enabled()
    return self.Settings.AutoPumpkins or self.Settings.AutoCrystals
end

function App:QuestEnabled()
    return self.Settings.AutoDriveDistance or self.Settings.AutoSpeedTraps
end

function App:Valid(generation, kind)
    return self.Running and self.Generation == generation and self:Enabled()
        and (not kind or self.Settings[kind == "Pumpkin" and "AutoPumpkins" or "AutoCrystals"])
end

function App:Wait(seconds, generation, kind)
    local deadline = os.clock() + math.max(seconds, 0)
    repeat
        if not self:Valid(generation, kind) then
            return false
        end
        if os.clock() >= deadline then
            return true
        end
        task.wait(math.min(0.05, math.max(deadline - os.clock(), 0.01)))
    until false
end

function App:SetOption(key, value)
    if not self.Running or self.Settings[key] == nil then
        return
    end
    if key == "TeleportDelay" or key == "RaceDelay" then
        value = tonumber(value)
        if not value or value ~= value then
            return
        end
        value = math.clamp(value, 0.2, 3)
    elseif key == "RaceLaps" then
        value = tonumber(value)
        if value ~= 1 and value ~= 3 and value ~= 5 then
            return
        end
    elseif key == "RaceVehicle" or key == "QuestVehicle" then
        value = tostring(value)
        if value ~= "Auto" and not self.RaceVehicleRecords[value] then
            return
        end
    else
        value = value == true
    end
    if key == "AutoCrystals" and value and self:CrystalProgress() >= self.CrystalGoal then
        local control = self.Controls[key]
        if control then
            pcall(control.Set, control, false, true)
        end
        self:Notify("Crystals", "All green crystals have already been collected", "Success")
        return
    end
    if value and (key == "AutoDriveDistance" or key == "AutoSpeedTraps") then
        local objective = key == "AutoDriveDistance" and "DriveMiles" or "SpeedTraps"
        local _, _, completed = self:QuestProgress(objective)
        if completed then
            if self.Settings[key] then
                self:SetOption(key, false)
            end
            if self.Controls[key] then
                self.Controls[key]:Set(false, true)
            end
            self.QuestStatus = objective == "DriveMiles" and "Drive Distance completed" or "Speed Traps completed"
            return
        end
    end
    if self.Settings[key] == value then
        return
    end
    self.Settings[key] = value
    local questOption = key == "AutoDriveDistance" or key == "AutoSpeedTraps"
        or key == "QuestVehicle" and self:QuestEnabled()
    if questOption then
        self.Generation = self.Generation + 1
        self:QuestCancel()
        if self:QuestEnabled() then
            if self.Settings.AutoRace then
                self.Settings.AutoRace = false
                self:RaceCancel()
                self.RaceStatus = "Auto Race is off"
            end
            for _, name in ipairs({"AutoPumpkins", "AutoCrystals", "AutoRace"}) do
                self.Settings[name] = false
                if self.Controls[name] then
                    self.Controls[name]:Set(false, true)
                end
            end
            self.QuestStatus = "Preparing your vehicle"
            self.Status = "Quest mode is active"
        else
            self.QuestStatus = "Quest automation is off"
            self.Status = "Idle"
        end
        self.TargetName = "None"
    end
    if key == "AutoRace" or key == "RaceVehicle" and self.Settings.AutoRace then
        self.Generation = self.Generation + 1
        if self.RaceState then
            self:RaceCancel()
        end
        if self.Settings.AutoRace then
            if self:QuestEnabled() then
                self.Settings.AutoDriveDistance = false
                self.Settings.AutoSpeedTraps = false
                self:QuestCancel()
                self.QuestStatus = "Quest automation is off"
                for _, name in ipairs({"AutoDriveDistance", "AutoSpeedTraps"}) do
                    if self.Controls[name] then
                        self.Controls[name]:Set(false, true)
                    end
                end
            end
            self.Settings.AutoPumpkins = false
            self.Settings.AutoCrystals = false
            for _, name in ipairs({"AutoPumpkins", "AutoCrystals"}) do
                if self.Controls[name] then
                    self.Controls[name]:Set(false, true)
                end
            end
            self.RaceStatus = "Preparing your vehicle"
            self.Status = "Race mode is active"
        else
            self.RaceStatus = "Auto Race is off"
            self.TargetName = "None"
            self.Status = self:Enabled() and "Finding the nearest collectible" or "Idle"
        end
    end
    if key == "AutoClaimRewards" then
        self.ClaimStatus = value and "Waiting for completed quests" or "Auto Claim Rewards is off"
    end
    if key == "AutoPumpkins" or key == "AutoCrystals" then
        if value and self:QuestEnabled() then
            self.Settings.AutoDriveDistance = false
            self.Settings.AutoSpeedTraps = false
            self:QuestCancel()
            self.QuestStatus = "Quest automation is off"
            for _, name in ipairs({"AutoDriveDistance", "AutoSpeedTraps"}) do
                if self.Controls[name] then
                    self.Controls[name]:Set(false, true)
                end
            end
        end
        if value and self.Settings.AutoRace then
            self.Settings.AutoRace = false
            if self.RaceState then
                self:RaceCancel()
            end
            self.RaceStatus = "Auto Race is off"
            if self.Controls.AutoRace then
                self.Controls.AutoRace:Set(false, true)
            end
        end
        self.Generation = self.Generation + 1
        self.TargetName = "None"
        self.Status = self:Enabled() and "Finding the nearest collectible" or "Idle"
    end
end

function App:StopAll()
    self.Settings.AutoPumpkins = false
    self.Settings.AutoCrystals = false
    self.Settings.AutoClaimRewards = false
    self.Settings.AutoRace = false
    self.Settings.AutoDriveDistance = false
    self.Settings.AutoSpeedTraps = false
    if self.QuestState then
        self:QuestCancel()
    end
    self.QuestStatus = "Quest automation is off"
    if self.RaceState then
        self:RaceCancel()
    end
    self.RaceStatus = "Auto Race is off"
    self.ClaimStatus = "Auto Claim Rewards is off"
    self.Generation = self.Generation + 1
    self.TargetName = "None"
    self.Status = "Stopped"
    for _, key in ipairs({"AutoPumpkins", "AutoCrystals", "AutoClaimRewards", "AutoRace", "AutoDriveDistance", "AutoSpeedTraps"}) do
        if self.Controls[key] then
            pcall(self.Controls[key].Set, self.Controls[key], false, true)
        end
    end
end

function App:Unload()
    if self.Unloading or not self.Running then
        return
    end
    self.Unloading = true
    self:StopAll()
    self.Running = false
    self.Settings.AntiAFK = false
    for _, connection in ipairs(self.Connections) do
        pcall(connection.Disconnect, connection)
    end
    for thread in pairs(self.Tasks) do
        if thread ~= coroutine.running() then
            pcall(task.cancel, thread)
        end
    end
    for _, trove in ipairs(self.Troves) do
        pcall(trove.Destroy, trove)
    end
    pcall(function()
        self:WithUI(function()
            if self.Window and not self.Window.Destroyed then
                pcall(self.Window.Destroy, self.Window)
            end
            if self.CleanupLibrary then
                self:CleanupLibrary()
            end
        end)
    end)
    if Environment[AppKey] == self then
        Environment[AppKey] = nil
    end
    self.Unloaded = true
    self.Unloading = false
end

function App:Character()
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if character and character.Parent and humanoid and humanoid.Health > 0 and root then
        return character, humanoid, root
    end
end

function App:ReadSpots()
    local folder = self.PumpkinFolder
    local raw = folder and folder:GetAttribute("RolledSpots")
    local spots = {}
    if type(raw) == "string" then
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok and type(decoded) == "table" then
            for _, value in ipairs(decoded) do
                if value.Id ~= nil and type(value.X) == "number" and type(value.Y) == "number" and type(value.Z) == "number" then
                    table.insert(spots, {Id = tostring(value.Id), Position = Vector3.new(value.X, value.Y, value.Z), Remote = value.Remote == true})
                end
            end
        end
    end
    if #spots == 0 then
        for _, value in ipairs(PumpkinController._Spots or {}) do
            table.insert(spots, {Id = tostring(value.Id), Position = value.Position, Remote = value.Remote == true})
        end
    end
    if #spots == 0 then
        return
    end
    self.Spots = spots
    local discovery = {}
    local lowX, lowZ, highX, highZ, totalY = math.huge, math.huge, -math.huge, -math.huge, 0
    for _, spot in ipairs(spots) do
        table.insert(discovery, spot.Position)
        lowX, lowZ = math.min(lowX, spot.Position.X), math.min(lowZ, spot.Position.Z)
        highX, highZ = math.max(highX, spot.Position.X), math.max(highZ, spot.Position.Z)
        totalY = totalY + spot.Position.Y
    end
    local reference = Player.Character and Player.Character:GetPivot().Position or spots[1].Position
    table.sort(discovery, function(a, b)
        return (a - reference).Magnitude < (b - reference).Magnitude
    end)
    local row = 0
    local gridY = totalY / #spots
    for x = lowX - 512, highX + 512, 256 do
        row = row + 1
        local line = {}
        for z = lowZ - 512, highZ + 512, 256 do
            table.insert(line, Vector3.new(x, gridY, z))
        end
        if row % 2 == 0 then
            for index = #line, 1, -1 do
                table.insert(discovery, line[index])
            end
        else
            for _, position in ipairs(line) do
                table.insert(discovery, position)
            end
        end
    end
    self.Discovery = discovery
    self.DiscoveryIndex = 1
end

function App:ScanCrystals()
    local folder = self.CrystalFolder
    if not folder or not folder.Parent then
        return
    end
    for _, instance in ipairs(folder:GetChildren()) do
        if instance:IsA("Model") or instance:IsA("BasePart") then
            local id = tostring(instance.Name)
            local record = self.Crystals[id] or {Id = id}
            record.Instance = instance
            record.Position = instance:GetPivot().Position
            local component = CrystalComponent:FromInstance(instance)
            if component and type(component.LastCollected) == "number" then
                self.CrystalCollected[id] = component.LastCollected
            end
            self.Crystals[id] = record
        end
    end
end

function App:KnownCrystals()
    local count = 0
    for _ in pairs(self.Crystals) do
        count = count + 1
    end
    return count
end

function App:StreamAt(position, generation, kind, priority, predicate)
    local function valid()
        return self.Running and (predicate and predicate() or (not predicate and self:Valid(generation, kind)))
    end
    local started = os.clock()
    local deadline = started + 2
    if priority then
        self.MovementStreamWanted = true
    end
    while self.Running and (self.StreamOwner or (not priority and self.MovementStreamWanted)) do
        if not valid() or os.clock() >= deadline then
            if priority then
                self.MovementStreamWanted = false
            end
            return false
        end
        task.wait(0.05)
    end
    if priority then
        self.MovementStreamWanted = false
    end
    if not valid() then
        return false
    end
    local owner = {Done = false, Deadline = deadline}
    self.StreamOwner = owner
    if Workspace.StreamingEnabled then
        owner.Thread = self:Spawn(function()
            owner.Ok, owner.Failure = pcall(Player.RequestStreamAroundAsync, Player, position, 1)
            owner.Done = true
            if self.StreamOwner == owner then
                self.StreamOwner = nil
            end
        end)
        while not owner.Done do
            if not valid() or os.clock() >= deadline then
                owner.Cancelled = true
                local stopped = not owner.Thread or coroutine.status(owner.Thread) == "dead"
                if not stopped then
                    local cancelled = pcall(task.cancel, owner.Thread)
                    stopped = cancelled and coroutine.status(owner.Thread) == "dead"
                end
                if stopped then
                    if owner.Thread then
                        self.Tasks[owner.Thread] = nil
                    end
                    if self.StreamOwner == owner then
                        self.StreamOwner = nil
                    end
                end
                return false
            end
            task.wait(math.min(0.05, math.max(deadline - os.clock(), 0.01)))
        end
        if not owner.Ok then
            if valid() then
                self:Warn("Streaming", owner.Failure)
            end
            return false
        end
    end
    if self.StreamOwner == owner then
        self.StreamOwner = nil
    end
    if not valid() or os.clock() > deadline then
        return false
    end
    self:ScanCrystals()
    return true
end

function App:RaceStreamAt(position, generation, character, car, requireDriver)
    return self:StreamAt(position, generation, nil, true, function()
        return self:RaceValid(generation, character, car, requireDriver)
    end)
end

function App:SelectTarget(position)
    local best, bestDistance
    local now = os.clock()
    local serverNow = Workspace:GetServerTimeNow()
    if self.Settings.AutoPumpkins then
        local cycles = PumpkinController._Cycles or {}
        local pending = PumpkinController._Pending or {}
        for _, spot in ipairs(self.Spots) do
            local key = "Pumpkin:" .. spot.Id
            if now >= (self.Cooldowns[key] or 0) and (not pending[spot.Id] or now - pending[spot.Id] >= 10) then
                local at, rarity = RolledUtil.GetSpawn(Roll, Player.UserId, spot.Id, cycles[spot.Id] or 0, spot.Remote)
                if at and rarity and at <= serverNow then
                    local distance = (spot.Position - position).Magnitude
                    if not bestDistance or distance < bestDistance then
                        bestDistance = distance
                        best = {Kind = "Pumpkin", Id = spot.Id, Position = spot.Position, Key = key, Rarity = rarity.Name, Amount = rarity.Amount, Cycle = cycles[spot.Id] or 0}
                    end
                end
            end
        end
    end
    if self.Settings.AutoCrystals then
        for id, record in pairs(self.Crystals) do
            local key = "Crystal:" .. id
            if type(self.CrystalCollected[id]) ~= "number" and now >= (self.Cooldowns[key] or 0) then
                local instance = record.Instance
                local component = instance and instance.Parent and CrystalComponent:FromInstance(instance)
                if not component or component.State == true then
                    local distance = (record.Position - position).Magnitude
                    if not bestDistance or distance < bestDistance then
                        bestDistance = distance
                        best = {Kind = "Crystal", Id = id, Position = record.Position, Key = key}
                    end
                end
            end
        end
    end
    return best
end

function App:Confirmed(target)
    if target.Kind == "Pumpkin" then
        local value = (PumpkinController._Cycles or {})[target.Id] or 0
        return value ~= target.Cycle, value
    end
    local value = self.CrystalCollected[target.Id]
    local record = self.Crystals[target.Id]
    local instance = record and record.Instance
    local component = instance and instance.Parent and CrystalComponent:FromInstance(instance)
    if component and type(component.LastCollected) == "number" then
        value = component.LastCollected
        self.CrystalCollected[target.Id] = value
    end
    return type(value) == "number", value
end

function App:Record(target, stamp)
    if target.Kind == "Pumpkin" then
        if self.ConfirmedPumpkins[target.Id] ~= stamp then
            self.ConfirmedPumpkins[target.Id] = stamp
            self.SessionPumpkins = self.SessionPumpkins + 1
            self.SessionCurrency = self.SessionCurrency + (tonumber(target.Amount) or 0)
        end
    elseif not self.ConfirmedCrystals[target.Id] then
        self.ConfirmedCrystals[target.Id] = true
        self.SessionCrystals = self.SessionCrystals + 1
    end
    self.Cooldowns[target.Key] = nil
    self.InFlight[target.Key] = nil
end

function App:Reconcile()
    for key, pending in pairs(self.InFlight) do
        local success, stamp = self:Confirmed(pending.Target)
        if success then
            self:Record(pending.Target, stamp)
        elseif os.clock() >= pending.Deadline then
            self.InFlight[key] = nil
        end
    end
end

function App:CollectTarget(target, generation)
    local character, humanoid = self:Character()
    if not character or not self:Valid(generation, target.Kind) then
        return
    end
    if humanoid.SeatPart then
        self.Status = "Leaving the vehicle"
        humanoid.Sit = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        local deadline = os.clock() + 1
        while humanoid.SeatPart and os.clock() < deadline do
            if not self:Wait(0.05, generation, target.Kind) then
                return
            end
        end
        if humanoid.SeatPart then
            self.Status = "Waiting to leave the vehicle"
            return
        end
    end
    self.TargetName = (target.Rarity and target.Rarity .. " " or "") .. target.Kind .. " #" .. target.Id
    self.Status = "Loading the target area"
    self:StreamAt(target.Position, generation, target.Kind, true)
    if not self:Valid(generation, target.Kind) then
        return
    end
    for attempt = 1, 2 do
        if not self:Wait(math.max(0, self.NextTeleportAt - os.clock()), generation, target.Kind) then
            return
        end
        local already, stamp = self:Confirmed(target)
        if already then
            if self.InFlight[target.Key] then
                self:Record(target, stamp)
            end
            return
        end
        local current, _, root = self:Character()
        if current ~= character or not root then
            return
        end
        self.Status = "Collecting " .. target.Kind:lower() .. " (" .. attempt .. "/2)"
        self.InFlight[target.Key] = {Target = target, Deadline = os.clock() + 15}
        current:PivotTo(CFrame.new(target.Position + Vector3.new(0, 4, 0)) * root.CFrame.Rotation)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        self.NextTeleportAt = os.clock() + self.Settings.TeleportDelay
        local deadline = os.clock() + 3
        repeat
            local success, stamp = self:Confirmed(target)
            if success then
                self:Record(target, stamp)
                if self:Valid(generation, target.Kind) then
                    self.Status = "Collected " .. target.Kind:lower()
                end
                return
            end
            if not self:Valid(generation, target.Kind) or Player.Character ~= character or humanoid.Health <= 0 then
                return
            end
            task.wait(0.05)
        until os.clock() >= deadline
    end
    self.Cooldowns[target.Key] = os.clock() + 30
    self.Status = "Target did not confirm; trying another collectible"
end

function App:FarmStep()
    if not self:Enabled() then
        return
    end
    if not EventUtil.IsActive(Workspace:GetServerTimeNow()) then
        self:StopAll()
        self.Status = "The Halloween event has ended"
        self:Notify("Event ended", self.Status, "Warning")
        return
    end
    if self.Settings.AutoCrystals and self:CrystalProgress() >= self.CrystalGoal then
        self:SetOption("AutoCrystals", false)
        if self.Controls.AutoCrystals then
            self.Controls.AutoCrystals:Set(false, true)
        end
        self:Notify("Crystals complete", "All green crystals have been collected", "Success")
    end
    if not self:Enabled() then
        return
    end
    local character = self:Character()
    if not character then
        self.Status = "Waiting for your character"
        return
    end
    local target = self:SelectTarget(character:GetPivot().Position)
    if not target then
        self.TargetName = "None"
        self.Status = self.Settings.AutoCrystals and "Searching streamed areas for crystals" or "Waiting for pumpkins to respawn"
        return
    end
    self:CollectTarget(target, self.Generation)
    if self:Enabled() then
        self.TargetName = "None"
    end
end

function App:VehicleDependencies()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes or not remotes:FindFirstChild("Spawn") or not remotes:FindFirstChild("ExitSeat") then
        return nil, "Vehicle controls are unavailable"
    end
    if not self.RaceCarData then
        local ok, result = pcall(function()
            return require(ReplicatedStorage.Controllers.CarDataController)
        end)
        if not ok or type(result) ~= "table" or type(result.GetOwnedCars) ~= "function" then
            return nil, "Owned vehicle data is unavailable"
        end
        self.RaceCarData = result
    end
    if not self.RaceLegacy then
        local ok, result = pcall(function()
            return require(ReplicatedStorage.ModuleScript)
        end)
        if not ok or type(result) ~= "table" then
            return nil, "Vehicle controls are unavailable"
        end
        self.RaceLegacy = result
    end
    self.VehicleDeps = {Spawn = remotes.Spawn, ExitSeat = remotes.ExitSeat, CarData = self.RaceCarData, Legacy = self.RaceLegacy}
    return self.VehicleDeps
end

function App:RaceDependencies()
    local races = Workspace:FindFirstChild("Races")
    local model = races and races:FindFirstChild("Halloween")
    local script = model and model:FindFirstChild("Script")
    local handler = races and races:FindFirstChild("RaceHandler")
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local menu = Player.PlayerGui:FindFirstChild("Menu")
    local values = menu and menu:FindFirstChild("RaceValues")
    local data = ReplicatedStorage:FindFirstChild("Data")
    data = data and data:FindFirstChild("Races")
    data = data and data:FindFirstChild("Halloween")
    local flag = data and data:FindFirstChild("FlagPosition")
    if not model or not script or not handler or not remotes or not values or not flag then
        return nil, "The Halloween race is unavailable"
    end
    for _, name in ipairs({"Racing", "Active", "PointToReach", "Laps"}) do
        if not values:FindFirstChild(name) then
            return nil, "Race progress data is unavailable"
        end
    end
    if not handler:FindFirstChild("StartLobby") or not script:FindFirstChild("Vote")
        or not script:FindFirstChild("ResetRacerEvent") or not script:FindFirstChild("Laps")
        or not script:FindFirstChild("LobbyProgress") or not script:FindFirstChild("RaceProgress")
        or not remotes:FindFirstChild("Spawn") or not remotes:FindFirstChild("ExitSeat") then
        return nil, "The Halloween race controls are unavailable"
    end
    local vehicles, vehicleFailure = self:VehicleDependencies()
    if not vehicles then
        return nil, vehicleFailure
    end
    self.RaceTrack = self.RaceTrack or {Checkpoints = {}}
    local checkpoints = model:FindFirstChild("Checkpoints")
    if checkpoints then
        for _, folder in ipairs(checkpoints:GetChildren()) do
            local checkpoint = folder:FindFirstChild("Checkpoint")
            if checkpoint and checkpoint:IsA("BasePart") then
                self.RaceTrack.Checkpoints[folder.Name] = {
                    CFrame = checkpoint.CFrame,
                    Position = checkpoint.Position - Vector3.new(0, checkpoint.Size.Y / 2, 0),
                }
            end
        end
    end
    local goal = model:FindFirstChild("GoalPart")
    if goal and goal:IsA("BasePart") then
        self.RaceTrack.Goal = {CFrame = goal.CFrame, Position = goal.Position}
    end
    self.RaceDeps = {
        Model = model,
        Script = script,
        StartLobby = handler.StartLobby,
        Spawn = vehicles.Spawn,
        ExitSeat = vehicles.ExitSeat,
        CarData = self.RaceCarData,
        Legacy = self.RaceLegacy,
        Values = values,
        FlagPosition = flag.Value,
    }
    return self.RaceDeps
end

function App:RefreshRaceVehicles()
    if not self.RaceCarData then
        local loaded, result = pcall(function()
            return require(ReplicatedStorage.Controllers.CarDataController)
        end)
        if not loaded or type(result) ~= "table" or type(result.GetOwnedCars) ~= "function" then
            return false, "Owned vehicle data is unavailable"
        end
        self.RaceCarData = result
    end
    local ok, owned = pcall(self.RaceCarData.GetOwnedCars, self.RaceCarData, Player)
    if not ok or type(owned) ~= "table" then
        return false, "Owned vehicle data is unavailable"
    end
    local list, names, records, labels, byLabel = {}, {}, {}, {"Auto"}, {Auto = "Auto"}
    for _, record in ipairs(owned) do
        if type(record) == "table" and type(record.Name) == "string" and type(record.Id) == "string" then
            list[#list + 1] = {Name = record.Name, Id = record.Id}
            names[record.Name] = (names[record.Name] or 0) + 1
        end
    end
    table.sort(list, function(a, b)
        return a.Name == b.Name and a.Id < b.Id or a.Name < b.Name
    end)
    for _, record in ipairs(list) do
        record.Label = record.Name .. (names[record.Name] > 1 and " [" .. record.Id:sub(1, 8) .. "]" or "")
        records[record.Id] = record
        labels[#labels + 1] = record.Label
        byLabel[record.Label] = record.Id
    end
    local previous = self.RaceVehicleRecords or {}
    self.RaceVehicleList = list
    self.RaceVehicleRecords = records
    for _, key in ipairs({"RaceVehicle", "QuestVehicle"}) do
        local selected = self.Settings[key] or "Auto"
        local selectedRecord = previous[selected]
        local currentLabels, currentByLabel = {}, {}
        for _, label in ipairs(labels) do
            currentLabels[#currentLabels + 1] = label
            currentByLabel[label] = byLabel[label]
        end
        local missing
        if selected ~= "Auto" and not records[selected] then
            missing = selectedRecord and selectedRecord.Label or self[key .. "MissingLabel"] or "Unavailable [" .. selected:sub(1, 8) .. "]"
            currentLabels[#currentLabels + 1] = missing
            currentByLabel[missing] = selected
        end
        self[key .. "MissingLabel"] = missing
        self[key .. "Labels"] = currentLabels
        self[key .. "ByLabel"] = currentByLabel
        local signature = table.concat(currentLabels, "\n")
        local control = self.Controls[key]
        if self[key .. "Signature"] ~= signature and control and control.Native then
            self.SyncingControls = (self.SyncingControls or 0) + 1
            local updated, updateFailure = pcall(function()
                self:WithUI(function()
                    control.Native:Refresh(currentLabels)
                    local record = records[selected]
                    control.Native:Select(record and record.Label or missing or "Auto")
                end)
            end)
            self.SyncingControls = self.SyncingControls - 1
            if not updated then
                self:Warn("Vehicle list", updateFailure)
            else
                self[key .. "Signature"] = signature
            end
        else
            self[key .. "Signature"] = signature
        end
    end
    return true
end

function App:RaceValid(generation, character, car, requireDriver)
    if not self.Running or not self.Settings.AutoRace or self.Generation ~= generation then
        return false
    end
    if character then
        local current, humanoid = self:Character()
        if current ~= character or not humanoid then
            return false
        end
        if car then
            if not car.Parent then
                return false
            end
            local info = self:RaceVehicleInfo(car)
            if not info then
                return false
            end
            if requireDriver and (humanoid.SeatPart ~= info.Seat or info.Seat.Occupant ~= humanoid) then
                return false
            end
        end
    elseif car and not car.Parent then
        return false
    end
    return true
end

function App:RaceWait(seconds, generation, character, car, requireDriver)
    local deadline = os.clock() + math.max(tonumber(seconds) or 0, 0)
    repeat
        if not self:RaceValid(generation, character, car, requireDriver) then
            return false
        end
        if os.clock() >= deadline then
            return true
        end
        task.wait(math.min(0.05, math.max(deadline - os.clock(), 0.01)))
    until false
end

function App:RaceDisable(message)
    self:SetOption("AutoRace", false)
    if self.Controls.AutoRace then
        self.Controls.AutoRace:Set(false, true)
    end
    self.RaceStatus = message
    self:Notify("Auto Race", message, "Warning")
end

function App:RaceCancel()
    local state = self.RaceState
    if not state then
        return
    end
    local deps = self.RaceDeps
    local run = state.Run
    if run and not run.Counted then
        if deps and deps.Values.Parent and deps.Values.Racing.Value ~= "Halloween" and run.ActiveSeen then
            run.EndedAt = run.EndedAt or os.clock()
        else
            run.Cancelled = true
        end
    end
    if state.Owned and not state.ResetSent then
        state.ResetSent = true
        state.Owned = false
        if self.Running and deps and deps.Script.Parent then
            local remote = deps.Script:FindFirstChild("ResetRacerEvent")
            if remote then
                local ok, failure = pcall(remote.FireServer, remote)
                if not ok then
                    self:Warn("Race reset", failure)
                end
            end
        end
    end
    state.Target = nil
    state.JoinStarted = nil
    state.VoteSent = nil
    state.SeatAttempt = nil
    state.ExitAttempt = nil
    state.SpawnPending = nil
    state.LobbyArrival = nil
    state.NextJoinAt = math.max(state.NextJoinAt or 0, os.clock() + 1)
    self.RacePointName = "None"
end

function App:VehicleInfo(car)
    if not car or not car.Parent then
        return nil
    end
    local body = car:FindFirstChild("Body")
    local stats = car:FindFirstChild("Stats")
    local chassis = car:FindFirstChild("ChassisMain")
    local main = body and body:FindFirstChild("Main")
    local start = body and body:FindFirstChild("Start")
    local seat = body and body:FindFirstChild("VehicleSeat")
    local remote = chassis and chassis:FindFirstChild("Seat")
    if not stats or stats:FindFirstChild("Airplane") or not main or not start or not seat or not remote then
        return nil
    end
    if not main:IsA("BasePart") or not start:IsA("BasePart") or not seat:IsA("VehicleSeat") then
        return nil
    end
    local owner = stats:FindFirstChild("Owner")
    return {Main = main, Start = start, Seat = seat, SeatRemote = remote, Owner = owner and owner.Value,
        Id = car:GetAttribute("CarId"), Name = car:GetAttribute("CarType") or car.Name}
end

function App:VehicleRecordForCar(car)
    local records = self.RaceVehicleRecords or {}
    local id = car:GetAttribute("CarId")
    if type(id) == "string" then
        return records[id]
    end
    local name = car:GetAttribute("CarType") or car.Name
    local found
    for _, record in ipairs(self.RaceVehicleList or {}) do
        if record.Name == name then
            if found then
                return nil
            end
            found = record
        end
    end
    return found
end

function App:RaceVehicleInfo(car)
    return self:VehicleInfo(car)
end

function App:RaceRecordForCar(car)
    return self:VehicleRecordForCar(car)
end

function App:VehicleSelect(context, character, humanoid, root)
    local folder = Workspace:FindFirstChild("Cars")
    if not folder then
        return nil
    end
    local selected = context.Selected or "Auto"
    local nearest, nearestInfo, nearestRecord, distance
    for _, car in ipairs(folder:GetChildren()) do
        local info = self:VehicleInfo(car)
        local record = info and self:VehicleRecordForCar(car)
        if info and car ~= context.IgnoreCar and (selected == "Auto" or record and record.Id == selected) then
            if humanoid.SeatPart == info.Seat and info.Seat.Occupant == humanoid then
                return car, info, record
            end
            if info.Owner == Player.Name and not info.Seat.Occupant then
                local current = (info.Main.Position - root.Position).Magnitude
                if not distance or current < distance then
                    nearest, nearestInfo, nearestRecord, distance = car, info, record, current
                end
            end
        end
    end
    return nearest, nearestInfo, nearestRecord
end

function App:RaceSelectVehicle(character, humanoid, root)
    return self:VehicleSelect({Selected = self.Settings.RaceVehicle}, character, humanoid, root)
end

function App:VehicleEnsure(context, generation, character, humanoid, root)
    local state = context.State
    if not context.Valid(generation, character) then
        return nil
    end
    local deps, failure = context.Deps
    if not deps then
        deps, failure = self:VehicleDependencies()
    end
    if not context.Valid(generation, character) then
        return nil
    end
    if not deps then
        context.Disable(failure or "Vehicle controls are unavailable")
        return nil
    end
    local now = os.clock()
    local replacement = context.Mode == "Quest" and state.ReplaceVehicle
    if replacement and (type(replacement.Id) ~= "string" or not self.RaceVehicleRecords[replacement.Id]) then
        context.SetStatus("The vehicle selected for recovery is no longer owned")
        return nil
    end
    local selection = replacement and {Selected = replacement.Id, IgnoreCar = replacement.PreviousCar} or context
    local car, info, record = self:VehicleSelect(selection, character, humanoid, root)
    if not car then
        context.SetVehicleName("None")
        local selected = replacement and replacement.Id or context.Selected or "Auto"
        if selected == "Auto" then
            record = self.RaceVehicleRecords[self.LastVehicleId or self.LastRaceVehicleId or ""]
        else
            record = self.RaceVehicleRecords[selected]
        end
        state.Incompatible = state.Incompatible or {}
        if selected == "Auto" and (not record or state.Incompatible[record.Id]) then
            record = nil
            for _, candidate in ipairs(self.RaceVehicleList or {}) do
                if not state.Incompatible[candidate.Id] then
                    record = candidate
                    break
                end
            end
        end
        if not record then
            context.SetStatus(selected == "Auto" and "Waiting for an owned compatible vehicle" or "The selected vehicle is no longer owned")
            return nil
        end
        context.SetVehicleName(record.Label or record.Name)
        local folder = Workspace:FindFirstChild("Cars")
        if folder then
            for _, existing in ipairs(folder:GetChildren()) do
                if existing:GetAttribute("CarId") == record.Id and not self:VehicleInfo(existing)
                    and (not replacement or existing ~= replacement.PreviousCar) then
                    local stats = existing:FindFirstChild("Stats")
                    local loading = state.ModelLoading
                    if not loading or loading.Car ~= existing then
                        loading = {Car = existing, Deadline = now + 8}
                        state.ModelLoading = loading
                    end
                    if stats and stats:FindFirstChild("Airplane") or now >= loading.Deadline then
                        state.ModelLoading = nil
                        if selected ~= "Auto" then
                            context.Disable(context.Mode == "Race" and "The selected vehicle cannot enter this race" or "The selected vehicle is incompatible with quest driving")
                        else
                            state.Incompatible[record.Id] = true
                            context.SetStatus("Skipping an incompatible vehicle")
                        end
                        return nil
                    end
                    context.SetStatus("Waiting for the vehicle chassis to load")
                    return nil
                end
            end
        end
        state.ModelLoading = nil
        if state.SpawnPending and now < state.SpawnPending.Deadline then
            context.SetStatus("Waiting for the vehicle to spawn")
            return nil
        end
        state.SpawnPending = nil
        if now < math.max(state.NextSpawnAt or 0, self.NextVehicleSpawnAt or 0) then
            context.SetStatus("Waiting before retrying vehicle spawn")
            return nil
        end
        if not context.Valid(generation, character) then
            return nil
        end
        local platform = UserInputService.TouchEnabled and "Touch" or "Desktop"
        if type(deps.Legacy.getPlatform) == "function" then
            local ok, value = pcall(deps.Legacy.getPlatform)
            if ok and type(value) == "string" then
                platform = value
            end
        end
        state.NextSpawnAt = now + 10
        self.NextVehicleSpawnAt = state.NextSpawnAt
        state.SpawnPending = {Id = record.Id, Deadline = now + 8}
        context.SetStatus("Spawning " .. (record.Label or record.Name))
        local ok, failure = pcall(deps.Spawn.FireServer, deps.Spawn, record.Name, record.Id, platform)
        if not ok then
            state.SpawnPending = nil
            self:Warn("Vehicle spawn", failure)
        end
        return nil
    end
    state.SpawnPending = nil
    state.ModelLoading = nil
    context.SetVehicleName(record and (record.Label or record.Name) or info.Name)
    if humanoid.SeatPart == info.Seat and info.Seat.Occupant == humanoid then
        state.SeatAttempt = nil
        state.ExitAttempt = nil
        if replacement and car ~= replacement.PreviousCar and info.Id == replacement.Id then
            state.ReplaceVehicle = nil
        end
        if record then
            self.LastVehicleId = record.Id
            if context.Mode == "Race" then
                self.LastRaceVehicleId = record.Id
            end
        end
        return car
    end
    if not context.Valid(generation, character, car) then
        return nil
    end
    if humanoid.SeatPart then
        context.SetStatus("Moving to the driver's seat")
        if not state.ExitAttempt or now >= state.ExitAttempt then
            state.ExitAttempt = now + 3
            deps.ExitSeat:FireServer()
        end
        return nil
    end
    local attempt = state.SeatAttempt
    if attempt and attempt.Car == car and now < attempt.Deadline then
        context.SetStatus("Waiting for the driver's seat")
        return nil
    end
    local attempts = attempt and attempt.Car == car and attempt.Attempts or 0
    if attempts >= 2 then
        state.SeatAttempt = {Car = car, Attempts = 0, Deadline = now + 10}
        context.SetStatus("Could not enter the vehicle; retrying later")
        return nil
    end
    if not context.Valid(generation, character, car) then
        return nil
    end
    character:PivotTo(info.Seat.CFrame * CFrame.new(0, 2.5, 4))
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    if not context.Wait(0.15, generation, character, car, false) then
        return nil
    end
    if not context.Valid(generation, character, car) or info.Seat.Occupant then
        return nil
    end
    state.SeatAttempt = {Car = car, Attempts = attempts + 1, Deadline = os.clock() + 3}
    context.SetStatus("Entering the driver's seat")
    info.SeatRemote:FireServer(info.Seat)
    return nil
end

function App:RaceEnsureVehicle(generation, character, humanoid, root)
    return self:VehicleEnsure({
        Mode = "Race",
        State = self.RaceState,
        Selected = self.Settings.RaceVehicle,
        Deps = self.RaceDeps,
        Valid = function(...) return self:RaceValid(...) end,
        Wait = function(...) return self:RaceWait(...) end,
        Disable = function(message) self:RaceDisable(message) end,
        SetStatus = function(message) self.RaceStatus = message end,
        SetVehicleName = function(name) self.RaceVehicleName = name end,
    }, generation, character, humanoid, root)
end

function App:RaceMoveCar(car, reference, target, generation, character, destinationPart)
    if not self:RaceValid(generation, character, car, true) then
        return false
    end
    if (not destinationPart and not self:RaceStreamAt(target.Position, generation, character, car, true))
        or not self:RaceValid(generation, character, car, true) or not reference.Parent
        or destinationPart and not destinationPart.Parent then
        return false
    end
    local offset = reference.CFrame:ToObjectSpace(car:GetPivot())
    car:PivotTo(target * offset)
    reference.AssemblyLinearVelocity = Vector3.zero
    reference.AssemblyAngularVelocity = Vector3.zero
    self.RaceState.NextMoveAt = os.clock() + self.Settings.RaceDelay
    return true
end

function App:RacePrize(instance)
    if not self.Running or instance.Name ~= "PrizeWithEventCurrency" then
        return
    end
    self.RacePrizeRuns = self.RacePrizeRuns or setmetatable({}, {__mode = "k"})
    local run = self.RacePrizeRuns[instance]
    if run == nil then
        run = self.RaceState and self.RaceState.Run or false
        self.RacePrizeRuns[instance] = run
        if run then
            self:Connect(instance:GetAttributeChangedSignal("HalloweenPumpkins"), function()
                self:RacePrize(instance)
            end)
        end
    end
    if not run or run.Cancelled or run.Counted or run.Prize then
        return
    end
    local amount = instance:GetAttribute("HalloweenPumpkins")
    if type(amount) == "number" and amount > 0 and amount == amount then
        run.Prize = instance
        run.Pumpkins = amount
        self:RaceReconcile()
    end
end

function App:RaceReconcile()
    local state, deps = self.RaceState, self.RaceDeps
    local run = state and state.Run
    if not self.Running or not run or run.Cancelled or run.Counted or not deps or not deps.Values.Parent then
        return
    end
    if run.ActiveSeen and deps.Values.Racing.Value ~= "Halloween" then
        run.EndedAt = run.EndedAt or os.clock()
    end
    if run.EndedAt and run.Prize and run.Pumpkins and run.Pumpkins > 0 then
        run.Counted = true
        state.Owned = false
        state.Target = nil
        state.JoinStarted = nil
        state.NextJoinAt = math.max(state.NextJoinAt or 0, os.clock() + 1)
        self.SessionRaces = (self.SessionRaces or 0) + 1
        self.SessionRacePumpkins = (self.SessionRacePumpkins or 0) + run.Pumpkins
        if self.Settings.AutoRace then
            self.RaceStatus = "Race complete; preparing the next race"
        end
    end
end

function App:RaceRestart(message)
    self:RaceCancel()
    self.RaceState.Run = nil
    self.RaceState.NextJoinAt = os.clock() + 10
    self.RaceState.CooldownUntil = os.clock() + 10
    if self.Settings.AutoRace then
        self.RaceStatus = message
    end
end

function App:RaceStep()
    if not self.Running or not self.Settings.AutoRace then
        return
    end
    if not EventUtil.IsActive(Workspace:GetServerTimeNow()) then
        self:StopAll()
        self.RaceStatus = "The Halloween event has ended"
        return
    end
    local deps, failure = self:RaceDependencies()
    if not deps then
        self:RaceDisable(failure)
        return
    end
    self.RaceState = self.RaceState or {}
    local state = self.RaceState
    local now = os.clock()
    if state.Run and state.Run.Cancelled then
        state.Run = nil
    end
    if now < (state.CooldownUntil or 0) then
        return
    end
    if now >= (state.NextVehiclesAt or 0) then
        self:RefreshRaceVehicles()
        state.NextVehiclesAt = now + 5
    end
    local generation = self.Generation
    local character, humanoid, root = self:Character()
    if not character then
        self.RaceStatus = "Waiting for your character"
        return
    end
    local racing = deps.Values.Racing.Value
    if racing ~= "" and racing ~= "Halloween" then
        self.RaceStatus = "Waiting for the current race to end"
        return
    end
    self:RaceReconcile()
    local run = state.Run
    if run and run.EndedAt then
        if not run.Counted and (now - run.EndedAt < 10
            or deps.Script.RaceProgress.Value and now - run.EndedAt < 90) then
            self.RaceStatus = "Waiting for the race reward confirmation"
            return
        end
        if not run.Counted then
            self:RaceRestart("Race reward was not confirmed; retrying later")
            return
        end
        if now < (state.NextJoinAt or 0) then
            return
        end
        state.Run = nil
    end
    local car = self:RaceEnsureVehicle(generation, character, humanoid, root)
    if not car or not self:RaceValid(generation, character, car, true) then
        if state.Run and state.Run.ActiveSeen and racing == "Halloween" then
            self:RaceRestart("The vehicle was lost; preparing another race")
        end
        return
    end
    local info = self:RaceVehicleInfo(car)
    if racing == "" then
        if state.Run and state.Run.ActiveSeen then
            self:RaceReconcile()
            return
        end
        if state.JoinStarted and now - state.JoinStarted >= 90 then
            self:RaceRestart("Race start timed out; retrying later")
            return
        end
        if state.JoinStarted then
            if not deps.Script.LobbyProgress.Value then
                if deps.Script.RaceProgress.Value then
                    self.RaceStatus = "Waiting for the Halloween race lobby to reopen"
                    return
                end
                if now >= (state.NextJoinAt or 0) then
                    if not self:RaceValid(generation, character, car, true) then
                        return
                    end
                    state.NextJoinAt = now + 10
                    self.RaceStatus = "Retrying entry to the Halloween race lobby"
                    deps.StartLobby:FireServer("Halloween")
                else
                    self.RaceStatus = string.format("Waiting for the race lobby to accept entry; retry in %d seconds", math.max(math.ceil(state.NextJoinAt - now), 0))
                end
                return
            end
            if not state.VoteSent and deps.Script.LobbyProgress.Value then
                if not self:RaceValid(generation, character, car, true) then
                    return
                end
                state.VoteSent = true
                deps.Script.Vote:FireServer(tostring(self.Settings.RaceLaps), "Vote")
            end
            self.RaceStatus = "Waiting in the Halloween race lobby"
            return
        end
        if now < (state.NextJoinAt or 0) then
            self.RaceStatus = "Waiting before starting the next race"
            return
        end
        if deps.Script.RaceProgress.Value then
            self.RaceStatus = "Waiting for the Halloween race lobby to reopen"
            return
        end
        local arrival = state.LobbyArrival
        if not arrival or arrival.Car ~= car or arrival.Generation ~= generation then
            local anchor = deps.Model:FindFirstChild("Main")
            if not self:RaceMoveCar(car, info.Main, CFrame.new(deps.FlagPosition + Vector3.new(0, 4, 0)) * info.Main.CFrame.Rotation, generation, character, anchor) then
                return
            end
            state.LobbyArrival = {Car = car, Generation = generation, ReadyAt = os.clock() + 0.75}
            self.RaceStatus = "Arriving at the Halloween race lobby"
            return
        end
        if now < arrival.ReadyAt then
            return
        end
        if not self:RaceValid(generation, character, car, true) then
            return
        end
        state.JoinStarted = os.clock()
        state.LobbyArrival = nil
        state.NextJoinAt = state.JoinStarted + 10
        state.Owned = true
        state.ResetSent = false
        state.VoteSent = false
        self.RaceStatus = "Joining the Halloween race lobby"
        deps.StartLobby:FireServer("Halloween")
        return
    end
    if not state.Run then
        state.Run = {StartedAt = now, ActiveSeen = false, Car = car}
        state.Target = nil
        state.JoinStarted = state.JoinStarted or now
    end
    run = state.Run
    if run.Car ~= car then
        self:RaceRestart("The race vehicle changed; retrying later")
        return
    end
    if not deps.Values.Active.Value then
        if now - (state.JoinStarted or run.StartedAt) >= 90 then
            self:RaceRestart("Race countdown timed out; retrying later")
        else
            self.RaceStatus = "Waiting for the race countdown"
        end
        return
    end
    run.ActiveSeen = true
    local point = tonumber(deps.Values.PointToReach.Value)
    local lap = tonumber(deps.Values.Laps.Value) or 1
    local laps = tonumber(deps.Script.Laps.Value) or self.Settings.RaceLaps
    if run.TimedLap ~= lap then
        run.TimedLap = lap
        run.LapStartedAt = now
    end
    self.RaceLap = lap
    self.RaceLaps = laps
    self.RacePointName = point == 0 and "Finish line" or "Checkpoint " .. tostring(point or "?")
    local target = state.Target
    if target then
        local advanced = target.Point == 0 and (lap ~= target.Lap or racing ~= "Halloween")
            or target.Point ~= 0 and (point ~= target.Point or lap ~= target.Lap)
        if advanced then
            state.Target = nil
            target = nil
        elseif now < target.Deadline then
            self.RaceStatus = "Waiting for " .. self.RacePointName:lower() .. " confirmation"
            return
        elseif target.Attempts >= 2 then
            self:RaceRestart("A checkpoint was not confirmed; retrying later")
            return
        end
    end
    if now < (state.NextMoveAt or 0) then
        return
    end
    if point == 0 and now - run.LapStartedAt < 30 then
        self.RaceStatus = "Waiting for the lap finish window"
        return
    end
    local reference, destination, destinationPart
    if point == 0 then
        local goal = deps.Model:FindFirstChild("GoalPart")
        if goal and goal:IsA("BasePart") then
            reference = info.Start
            destination = goal.CFrame
            destinationPart = goal
        end
    elseif point and point >= 1 then
        local folder = deps.Model:FindFirstChild("Checkpoints")
        local checkpoint = folder and folder:FindFirstChild(tostring(point))
        checkpoint = checkpoint and checkpoint:FindFirstChild("Checkpoint")
        if checkpoint and checkpoint:IsA("BasePart") then
            reference = info.Main
            destination = CFrame.new(checkpoint.Position - Vector3.new(0, checkpoint.Size.Y / 2, 0) + Vector3.new(0, 4, 0)) * info.Main.CFrame.Rotation
            destinationPart = checkpoint
        end
    end
    if not destination then
        self.RaceStatus = "Waiting for the race checkpoint to load"
        local track = self.RaceTrack
        local cached = track and (point == 0 and track.Goal or track.Checkpoints[tostring(point)])
        self:RaceStreamAt(cached and cached.Position or deps.FlagPosition, generation, character, car, true)
        return
    end
    if self:RaceMoveCar(car, reference, destination, generation, character, destinationPart) then
        state.Target = {Point = point, Lap = lap, Attempts = target and target.Attempts + 1 or 1, Deadline = os.clock() + 3}
    self.RaceStatus = "Passing " .. self.RacePointName:lower()
    end
end


function App:QuestProgress(name)
    local goal = 0
    for _, objective in ipairs(Event.Objectives or {}) do
        if objective.Name == name then
            goal = tonumber(objective.Goal) or 0
            break
        end
    end
    local ok, values = pcall(UIState.Objectives.get, UIState.Objectives, false)
    local value = ok and type(values) == "table" and values[name]
    return type(value) == "table" and tonumber(value.Current) or 0, goal, type(value) == "table" and value.Completed == true
end

function App:QuestDependencies()
    if self.QuestDeps then
        return self.QuestDeps
    end
    local vehicles, failure = self:VehicleDependencies()
    if not vehicles then
        return nil, failure
    end
    local map = Workspace:FindFirstChild("New Map Folder")
    local roads = map and map:FindFirstChild("Roads")
    local databases = ReplicatedStorage:FindFirstChild("Databases")
    local source = databases and databases:FindFirstChild("Speedtrap")
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local services = remotes and remotes:FindFirstChild("Services")
    local speedSource = services and services:FindFirstChild("SpeedtrapServiceRemotes")
    if not roads or not source or not speedSource then
        return nil, "Quest roads or speed trap modules are unavailable"
    end
    local ok, database = pcall(require, source)
    local loaded, speedtrap = pcall(require, speedSource)
    if not ok or not loaded or type(database) ~= "table" or type(speedtrap) ~= "table" or not speedtrap.OnSpeedtrapTriggered then
        return nil, "Speed trap modules could not be loaded"
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {roads}
    params.IgnoreWater = true
    self.QuestDeps = {Roads = roads, RoadParams = params, Cooldown = math.max(tonumber(database.Cooldown) or 60, 1), Speedtrap = speedtrap}
    self.QuestCameras = self.QuestCameras or {}
    self.QuestState = self.QuestState or {}
    self.QuestState.CameraCooldowns = self.QuestState.CameraCooldowns or {}
    self.QuestState.ProgressWatch = self.QuestState.ProgressWatch or {}
    self:Connect(speedtrap.OnSpeedtrapTriggered.OnClientEvent, function(payload)
        if type(payload) ~= "table" or not tonumber(payload.Speed) then
            return
        end
        local state = self.QuestState
        if self:QuestEnabled() and state and state.Attempt and os.clock() <= state.Attempt.ExpiresAt then
            state.Attempt.NativeSpeed = tonumber(payload.Speed)
            state.Attempt.SpeedSeenAt = os.clock()
            if state.Attempt.Camera then
                state.CameraCooldowns = state.CameraCooldowns or {}
                local camera = state.Attempt.Camera
                state.CameraCooldowns[camera] = math.max(state.CameraCooldowns[camera] or 0, os.clock() + self.QuestDeps.Cooldown)
            end
            self.QuestLastSpeed = tonumber(payload.Speed)
        end
    end)
    self:QuestScanCameras()
    return self.QuestDeps
end

function App:QuestScanCameras()
    self.QuestCameras = self.QuestCameras or {}
    for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Speedtrap_Model")) do
        local part = model:FindFirstChild("DetectionPart")
        if part and part:IsA("BasePart") then
            local camera = self.QuestCameras[model.Name] or {Name = model.Name}
            camera.Part = part
            camera.Position = part.Position
            camera.CFrame = part.CFrame
            camera.Size = part.Size
            self.QuestCameras[model.Name] = camera
        end
    end
end

function App:QuestValid(generation, character, car, requireDriver)
    if not self.Running or not self:QuestEnabled() or self.Generation ~= generation then
        return false
    end
    if character then
        local current, humanoid = self:Character()
        if current ~= character or not humanoid then
            return false
        end
        if car then
            local info = car.Parent and self:VehicleInfo(car)
            if not info or requireDriver and (humanoid.SeatPart ~= info.Seat or info.Seat.Occupant ~= humanoid) then
                return false
            end
        end
    elseif car and not car.Parent then
        return false
    end
    return true
end

function App:QuestWait(seconds, generation, character, car, requireDriver)
    local deadline = os.clock() + math.max(tonumber(seconds) or 0, 0)
    repeat
        if not self:QuestValid(generation, character, car, requireDriver) then
            return false
        end
        if os.clock() >= deadline then
            return true
        end
        task.wait(math.min(0.05, math.max(deadline - os.clock(), 0.01)))
    until false
end

function App:QuestStopMotion()
    local state = self.QuestState
    local motion = state and state.Motion
    if not motion then
        return
    end
    pcall(self.QuestNativeThrottle, self, motion, 0)
    state.Motion = nil
    if motion.Connection then
        motion.Connection:Disconnect()
        for index = #(self.Connections or {}), 1, -1 do
            if self.Connections[index] == motion.Connection then
                table.remove(self.Connections, index)
                break
            end
        end
    end
    for _, instance in ipairs({motion.Velocity, motion.Gyro}) do
        if instance then
            instance:Destroy()
        end
    end
    if motion.Main and motion.Main.Parent then
        motion.Main.AssemblyLinearVelocity = Vector3.zero
        motion.Main.AssemblyAngularVelocity = Vector3.zero
    end
end

function App:QuestNativeThrottle(motion, value)
    local controls = motion and motion.NativeControls
    if not controls or not controls.Parent then
        return false
    end
    value = value == 1 and self:QuestValid(motion.Generation, motion.Character, motion.Car, true) and 1 or 0
    local throttle = controls:FindFirstChild("Throttle")
    local gas = controls:FindFirstChild("Gas")
    local brake = controls:FindFirstChild("Brake")
    local event = controls:FindFirstChild("SetThrottle")
    if not throttle or not gas or not brake or not event or not event:IsA("BindableEvent") then
        return false
    end
    if motion.NativeThrottle == value and throttle.Value == value and gas.Value == value and brake.Value == 0 then
        return true
    end
    throttle.Value = value
    gas.Value = value
    brake.Value = 0
    event:Fire(value)
    motion.NativeThrottle = value
    return true
end

function App:QuestCancel()
    self:QuestStopMotion()
    local state = self.QuestState
    if state then
        state.Attempt = nil
        state.Route = nil
        state.Prepared = nil
        state.SpawnPending = nil
        state.SeatAttempt = nil
        state.ReplaceVehicle = nil
    end
end

function App:QuestDisable(key, message)
    if key then
        self:SetOption(key, false)
        if self.Controls[key] then
            self.Controls[key]:Set(false, true)
        end
    else
        for _, option in ipairs({"AutoDriveDistance", "AutoSpeedTraps"}) do
            self:SetOption(option, false)
            if self.Controls[option] then
                self.Controls[option]:Set(false, true)
            end
        end
    end
    self.QuestStatus = message
end

function App:QuestReconcile()
    for _, pair in ipairs({{"AutoDriveDistance", "DriveMiles"}, {"AutoSpeedTraps", "SpeedTraps"}}) do
        local _, _, completed = self:QuestProgress(pair[2])
        if completed and self.Settings[pair[1]] then
            self:QuestDisable(pair[1], pair[2] == "DriveMiles" and "Drive Distance completed" or "Speed Traps completed")
        end
    end
end

function App:QuestRoadPoint(position)
    local deps = self.QuestDeps
    if not deps then
        return nil
    end
    local hit = Workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -80, 0), deps.RoadParams)
    if not hit or hit.Normal.Y < 0.94 then
        return nil
    end
    return hit
end

function App:QuestBuildCorridor(camera)
    local axis = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
    if axis.Magnitude < 0.9 then
        return nil
    end
    axis = axis.Unit
    local center = self:QuestRoadPoint(camera.Position)
    if not center then
        return nil
    end
    local ends = {}
    local flatness = 0
    for _, sign in ipairs({-1, 1}) do
        local last = center.Position
        local length = 0
        for distance = 25, 700, 25 do
            local point = self:QuestRoadPoint(camera.Position + axis * distance * sign)
            if not point or math.abs(point.Position.Y - last.Y) > 5 or math.abs(point.Position.Y - center.Position.Y) > 65 then
                break
            end
            local width = math.min(camera.Size.Z * 0.2, 10)
            local side = Vector3.new(-axis.Z, 0, axis.X) * width
            local left = self:QuestRoadPoint(point.Position + side)
            local right = self:QuestRoadPoint(point.Position - side)
            if not left or not right or math.abs(left.Position.Y - point.Position.Y) > 2 or math.abs(right.Position.Y - point.Position.Y) > 2 then
                break
            end
            flatness = math.max(flatness, math.abs(point.Position.Y - center.Position.Y))
            last = point.Position
            length = distance
        end
        ends[sign] = {Position = last, Length = length}
    end
    if ends[-1].Length < 100 or ends[1].Length < 100 then
        return nil
    end
    local corridor = {Camera = camera, A = ends[-1].Position + axis * 30, B = ends[1].Position - axis * 30, Length = ends[-1].Length + ends[1].Length - 60, Flatness = flatness, Axis = axis, Center = center.Position}
    camera.Corridor = corridor
    return corridor
end

function App:QuestChooseCamera(position)
    local best, distance
    local cooldowns = self.QuestState.CameraCooldowns or {}
    for _, camera in pairs(self.QuestCameras or {}) do
        if camera.Corridor and os.clock() >= (cooldowns[camera.Name] or 0) then
            local current = (camera.Position - position).Magnitude
            if not distance or current < distance or current == distance and camera.Name < best.Name then
                best, distance = camera, current
            end
        end
    end
    return best
end

function App:QuestChooseCorridor()
    local preferred = self.QuestCameras and self.QuestCameras.Speedcam4
    if preferred and preferred.Corridor and preferred.Corridor.Length >= 600 and preferred.Corridor.Flatness < 3 then
        return preferred.Corridor
    end
    local best
    for _, camera in pairs(self.QuestCameras or {}) do
        local corridor = camera.Corridor
        if corridor and (not best or corridor.Length > best.Length or corridor.Length == best.Length and corridor.Flatness < best.Flatness) then
            best = corridor
        end
    end
    return best
end

function App:QuestMode(position)
    if self.Settings.AutoSpeedTraps then
        local camera = self:QuestChooseCamera(position)
        if camera then
            return "SpeedTraps", camera.Corridor
        end
    end
    if self.Settings.AutoDriveDistance then
        return "DriveMiles", self:QuestChooseCorridor()
    end
    return nil
end

function App:QuestObserveProgress(seconds)
    local state = self.QuestState
    state.ProgressWatch = state.ProgressWatch or {}
    for _, pair in ipairs({{"AutoDriveDistance", "DriveMiles"}, {"AutoSpeedTraps", "SpeedTraps"}}) do
        if self.Settings[pair[1]] then
            local current = self:QuestProgress(pair[2])
            local watch = state.ProgressWatch[pair[2]] or {Current = current, Moving = 0, Failures = 0}
            state.ProgressWatch[pair[2]] = watch
            if current > watch.Current then
                watch.Current = current
                watch.Moving = 0
                watch.Failures = 0
            elseif state.Motion and (pair[2] == "DriveMiles" or state.Motion.Kind == "SpeedTraps") then
                watch.Moving = watch.Moving + math.max(seconds or 0, 0)
            end
            if watch.Moving >= 60 then
                watch.Moving = 0
                watch.Failures = watch.Failures + 1
                local motion = state.Motion
                local info = motion and motion.Car and self:VehicleInfo(motion.Car)
                local record = info and info.Owner == Player.Name and self:VehicleRecordForCar(motion.Car)
                self:QuestStopMotion()
                if record then
                    state.ReplaceVehicle = {Id = record.Id, PreviousCar = motion.Car}
                end
                state.Prepared = nil
                state.Attempt = nil
                state.NextPrepareAt = os.clock() + 10
                if watch.Failures >= 3 then
                    self:QuestDisable(pair[1], pair[2] == "DriveMiles" and "Drive Distance stopped after three server progress timeouts" or "Speed Traps stopped after three server progress timeouts")
                else
                    self.QuestStatus = "Server progress did not increase; preparing again in 10 seconds"
                end
                return false
            end
        end
    end
    return true
end

function App:QuestCruiseSpeed(car)
    local speed = 55
    local source = car:FindFirstChild("StatsModule")
    if source then
        local ok, stats = pcall(require, source)
        if type(setthreadidentity) == "function" then
            pcall(setthreadidentity, self.UIThreadIdentity or 8)
        end
        if ok and type(stats) == "table" and type(stats.GearSpeeds) == "table" then
            local maximum = 0
            for gear, value in pairs(stats.GearSpeeds) do
                if tonumber(gear) and tonumber(gear) > 0 then
                    maximum = math.max(maximum, tonumber(value) or 0)
                end
            end
            if maximum > 0 then
                speed = math.min(180, maximum * 1.6 * 0.9)
            end
        end
    end
    return math.max(math.min(speed, 180), 10)
end

function App:QuestClearAhead(motion, heading, distance)
    local road = self:QuestRoadPoint(motion.Main.Position + heading * distance)
    if not road or math.abs(road.Position.Y - motion.GroundY) > distance * 0.22 + 3 then
        return false
    end
    local side = Vector3.new(-heading.Z, 0, heading.X) * math.min(motion.Main.Size.X * 0.35, 3)
    for _, offset in ipairs({Vector3.zero, side, -side}) do
        local origin = Vector3.new(motion.Main.Position.X, motion.GroundY + 3, motion.Main.Position.Z) + offset
        local hit = Workspace:Raycast(origin, heading * distance, motion.ObstacleParams)
        if hit then
            return false
        end
    end
    return true
end

function App:QuestMotionStart(car, character, generation, corridor, kind)
    if not self:QuestValid(generation, character, car, true) then
        return false
    end
    self:QuestStopMotion()
    local info = self:VehicleInfo(car)
    local cruise = self:QuestCruiseSpeed(car)
    if not self:QuestValid(generation, character, car, true) then
        return false
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclusions = {car, character, self.QuestDeps.Roads}
    local cameras = Workspace:FindFirstChild("SpeedCameras")
    if cameras then
        exclusions[#exclusions + 1] = cameras
    end
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = true
    params.RespectCanCollide = true
    local velocity = Instance.new("BodyVelocity")
    velocity.Name = "HalloweenQuestVelocity"
    velocity.MaxForce = Vector3.new(info.Main.AssemblyMass * 120, 0, info.Main.AssemblyMass * 120)
    velocity.P = info.Main.AssemblyMass * 12
    velocity.Velocity = Vector3.zero
    local gyro = Instance.new("BodyGyro")
    gyro.Name = "HalloweenQuestOrientation"
    gyro.MaxTorque = Vector3.new(1, 1, 1) * info.Main.AssemblyMass * 12000
    gyro.P = info.Main.AssemblyMass * 1800
    gyro.D = info.Main.AssemblyMass * 100
    gyro.CFrame = info.Main.CFrame
    local motion = {Car = car, Character = character, Generation = generation, Main = info.Main, Velocity = velocity, Gyro = gyro, Corridor = corridor, Kind = kind, Target = corridor.B, Direction = corridor.Axis, Speed = 0, Cruise = cruise, Phase = "Driving", GroundY = corridor.A.Y, ObstacleParams = params, StartedAt = os.clock(), SegmentStartedAt = os.clock(), LastTick = os.clock(), LastPosition = info.Main.Position, StuckPosition = info.Main.Position, NextStuckCheck = os.clock() + 10}
    local scripts = Player:FindFirstChild("PlayerScripts")
    motion.NativeControls = scripts and scripts:FindFirstChild("Controls")
    velocity.Parent = info.Main
    gyro.Parent = info.Main
    self.QuestState.Motion = motion
    motion.Connection = self:Connect(RunService.Heartbeat, function(dt)
        local ok, failure = pcall(function()
        if self.QuestState.Motion ~= motion then
            return
        end
        if not self:QuestValid(generation, character, car, true) then
            self:QuestStopMotion()
            self.QuestState.Prepared = nil
            return
        end
        dt = math.min(math.max(dt, 0.001), 0.1)
        local now = os.clock()
        if kind == "SpeedTraps" and self.QuestState.Attempt and now > self.QuestState.Attempt.ExpiresAt then
            motion.Failure = "The speed trap approach timed out; preparing another section"
        elseif now - motion.SegmentStartedAt > math.max(corridor.Length / math.max(motion.Cruise * 0.3, 1) + 20, 45) then
            motion.Failure = "Vehicle movement timed out; preparing another section"
        elseif now >= motion.NextStuckCheck then
            if motion.Phase == "Driving" and (motion.Main.Position - motion.StuckPosition).Magnitude < 3 then
                motion.Failure = "The vehicle could not move; preparing another section"
            end
            motion.StuckPosition = motion.Main.Position
            motion.NextStuckCheck = now + 10
        end
        local road = self:QuestRoadPoint(motion.Main.Position)
        if not road then
            motion.Failure = "The road is unavailable; preparing another section"
        elseif math.abs(motion.Main.Position.Y - road.Position.Y) > 15 then
            motion.Failure = "The vehicle left the road; preparing another section"
        end
        if motion.Failure then
            self:QuestStopMotion()
            self.QuestState.Prepared = nil
            self.QuestState.NextPrepareAt = os.clock() + 10
            self.QuestStatus = motion.Failure
            return
        end
        motion.GroundY = road.Position.Y
        local delta = motion.Target - motion.Main.Position
        local planar = Vector3.new(delta.X, 0, delta.Z)
        local along = planar:Dot(motion.Direction)
        local stopping = motion.Speed * motion.Speed / 160 + 5
        local desired = motion.Phase == "Driving" and math.min(motion.Cruise, math.sqrt(math.max(along - 3, 0) * 160)) or 0
        if motion.Phase == "Driving" and along <= 4 then
            motion.Phase = "Braking"
            desired = 0
        end
        local change = (desired > motion.Speed and 55 or 80) * dt
        motion.Speed = motion.Speed + math.clamp(desired - motion.Speed, -change, change)
        if motion.Phase == "Driving" and not self:QuestClearAhead(motion, motion.Direction, math.max(12, math.min(stopping + 5, 220))) then
            motion.Failure = "An obstacle or missing road interrupted movement"
            self:QuestStopMotion()
            self.QuestState.Prepared = nil
            self.QuestState.NextPrepareAt = os.clock() + 10
            self.QuestStatus = motion.Failure
            return
        end
        if motion.Phase == "Braking" and motion.Speed < 0.5 and motion.Main.AssemblyLinearVelocity.Magnitude < 5 then
            if kind == "SpeedTraps" then
                motion.Done = true
                self:QuestStopMotion()
                local attempt = self.QuestState.Attempt
                if attempt then
                    attempt.FinishedAt = os.clock()
                    attempt.Deadline = os.clock() + 5
                end
                return
            end
            self:QuestNativeThrottle(motion, 0)
            motion.Velocity.Velocity = Vector3.zero
            if not self:QuestValid(generation, character, car, true) then
                self:QuestStopMotion()
                return
            end
            local direction = -motion.Direction
            local tangent = direction - road.Normal * direction:Dot(road.Normal)
            local target = CFrame.lookAt(motion.Main.Position, motion.Main.Position + tangent.Unit, road.Normal)
            local offset = car:GetPivot():ToObjectSpace(motion.Main.CFrame)
            car:PivotTo(target * offset:Inverse())
            if not self:QuestValid(generation, character, car, true) then
                self:QuestStopMotion()
                return
            end
            motion.Main.AssemblyLinearVelocity = Vector3.zero
            motion.Main.AssemblyAngularVelocity = Vector3.zero
            motion.Gyro.CFrame = target
            motion.Direction = direction
            motion.Target = motion.Target == corridor.B and corridor.A or corridor.B
            motion.Phase = "Driving"
            motion.Speed = 0
            motion.SegmentStartedAt = os.clock()
            motion.NextStuckCheck = os.clock() + 10
            motion.StuckPosition = motion.Main.Position
            return
        end
        local sideError = planar - motion.Direction * along
        local correction = sideError.Magnitude > 0.1 and sideError.Unit * math.min(sideError.Magnitude * 1.5, 8) or Vector3.zero
        local requestedVelocity = motion.Direction * motion.Speed + (motion.Phase == "Driving" and correction or Vector3.zero)
        if requestedVelocity.Magnitude > motion.Cruise then
            requestedVelocity = requestedVelocity.Unit * motion.Cruise
        end
        self:QuestNativeThrottle(motion, motion.Phase == "Driving" and 1 or 0)
        motion.Velocity.Velocity = requestedVelocity
        local tangent = motion.Direction - road.Normal * motion.Direction:Dot(road.Normal)
        motion.Gyro.CFrame = CFrame.lookAt(motion.Main.Position, motion.Main.Position + tangent.Unit, road.Normal)
        if motion.Main.AssemblyLinearVelocity.Magnitude > 2 then
            self:QuestObserveProgress(dt)
        end
        end)
        if not ok and self.QuestState.Motion == motion then
            self:QuestStopMotion()
            self.QuestState.Prepared = nil
            self.QuestState.NextPrepareAt = os.clock() + 10
            self.QuestStatus = "Movement was interrupted; preparing another section"
            self:Warn("Quest movement", failure)
        end
    end)
    return true
end

function App:QuestPrepareCorridors(generation, character, car)
    self:QuestScanCameras()
    local state = self.QuestState
    local info = self:VehicleInfo(car)
    local candidates = {}
    for _, camera in pairs(self.QuestCameras or {}) do
        if not camera.Corridor and os.clock() >= (camera.NextScanAt or 0) then
            candidates[#candidates + 1] = camera
        end
    end
    table.sort(candidates, function(a, b)
        if self.Settings.AutoDriveDistance and not self.Settings.AutoSpeedTraps then
            if a.Name == "Speedcam4" then
                return true
            elseif b.Name == "Speedcam4" then
                return false
            end
        end
        return (a.Position - info.Main.Position).Magnitude < (b.Position - info.Main.Position).Magnitude
    end)
    local camera = candidates[1]
    if camera then
        self.QuestStatus = "Checking the road near " .. camera.Name
        self:StreamAt(camera.Position, generation, nil, true, function()
            return self:QuestValid(generation, character, car, true)
        end)
        if not self:QuestValid(generation, character, car, true) then
            return false
        end
        self:QuestBuildCorridor(camera)
        camera.NextScanAt = os.clock() + 15
    end
    state.NextScanAt = os.clock() + 1
    return true
end

function App:QuestStep()
    if not self.Running or not self:QuestEnabled() then
        return
    end
    if not EventUtil.IsActive(Workspace:GetServerTimeNow()) then
        self:StopAll()
        self.QuestStatus = "The Halloween event has ended"
        return
    end
    local generation = self.Generation
    local deps, failure = self:QuestDependencies()
    if not self:QuestValid(generation) then
        return
    end
    if not deps then
        self:QuestDisable(nil, failure)
        return
    end
    self:QuestReconcile()
    if not self:QuestEnabled() then
        return
    end
    local state = self.QuestState
    local now = os.clock()
    if now < (state.NextPrepareAt or 0) then
        return
    end
    local character, humanoid, root = self:Character()
    if not character then
        self:QuestStopMotion()
        self.QuestStatus = "Waiting for your character"
        return
    end
    local context = {
        Mode = "Quest", State = state, Selected = self.Settings.QuestVehicle,
        Valid = function(g, c, v, d) return self:QuestValid(g, c, v, d) end,
        Wait = function(s, g, c, v, d) return self:QuestWait(s, g, c, v, d) end,
        Disable = function(message) self:QuestDisable(nil, message) end,
        SetStatus = function(message) self.QuestStatus = message end,
        SetVehicleName = function(name) self.QuestVehicleName = name end,
    }
    local car = self:VehicleEnsure(context, generation, character, humanoid, root)
    if not car or not self:QuestValid(generation, character, car, true) then
        self:QuestStopMotion()
        state.Prepared = nil
        return
    end
    local motion = state.Motion
    if motion then
        if motion.Kind == "DriveMiles" and self.Settings.AutoSpeedTraps and self:QuestChooseCamera(motion.Main.Position) then
            self:QuestStopMotion()
            state.Prepared = nil
        else
            self.QuestStatus = motion.Kind == "SpeedTraps" and "Passing " .. motion.Corridor.Camera.Name or "Driving on " .. motion.Corridor.Camera.Name
            return
        end
    end
    if state.Attempt then
        local attempt = state.Attempt
        local current = self:QuestProgress("SpeedTraps")
        if current > attempt.Before then
            self.QuestStatus = "Speed trap progress confirmed"
            state.Attempt = nil
            state.Prepared = nil
        elseif not attempt.FinishedAt and now < attempt.ExpiresAt then
            return
        elseif attempt.Deadline and now < attempt.Deadline then
            self.QuestStatus = attempt.NativeSpeed and "Speed trap recorded; waiting for quest confirmation" or "Waiting for speed trap confirmation"
            return
        else
            self.QuestStatus = "Speed trap progress was not confirmed; waiting for its cooldown"
            state.Attempt = nil
            state.Prepared = nil
        end
    end
    if now >= (state.NextScanAt or 0) then
        if not self:QuestPrepareCorridors(generation, character, car) then
            return
        end
    end
    if not self:QuestValid(generation, character, car, true) then
        return
    end
    local info = self:VehicleInfo(car)
    local kind, corridor = self:QuestMode(info.Main.Position)
    if not corridor then
        self:QuestStopMotion()
        self.QuestStatus = self.Settings.AutoDriveDistance and "Waiting for a safe road section" or "Waiting for speed trap cooldowns or available roads"
        return
    end
    local center = corridor.Camera
    self:StreamAt(center.Position, generation, nil, true, function()
        return self:QuestValid(generation, character, car, true)
    end)
    if not self:QuestValid(generation, character, car, true) then
        return
    end
    local currentCorridor = self:QuestBuildCorridor(center)
    if not currentCorridor then
        center.Corridor = nil
        center.NextScanAt = os.clock() + 15
        self.QuestStatus = "The road section is unavailable; checking another camera"
        return
    end
    corridor = currentCorridor
    local start = corridor.A
    if kind == "SpeedTraps" then
        local offset = math.min((corridor.Center - corridor.A).Magnitude - 20, 220)
        start = corridor.Center - corridor.Axis * math.max(offset, 80)
        local ground = self:QuestRoadPoint(start)
        if not ground then
            center.Corridor = nil
            return
        end
        start = ground.Position
        local finish = corridor.Center + corridor.Axis * math.min((corridor.B - corridor.Center).Magnitude - 20, 150)
        local finishGround = self:QuestRoadPoint(finish)
        if not finishGround then
            center.Corridor = nil
            return
        end
        corridor = {Camera = center, A = start, B = finishGround.Position, Axis = corridor.Axis, Length = (finishGround.Position - start).Magnitude, Center = corridor.Center}
    end
    if not self:QuestValid(generation, character, car, true) then
        return
    end
    local heading = (corridor.B - corridor.A).Unit
    local target = CFrame.lookAt(start + Vector3.new(0, 3.5, 0), start + Vector3.new(0, 3.5, 0) + heading)
    local offset = car:GetPivot():ToObjectSpace(info.Main.CFrame)
    car:PivotTo(target * offset:Inverse())
    info.Main.AssemblyLinearVelocity = Vector3.zero
    info.Main.AssemblyAngularVelocity = Vector3.zero
    state.Prepared = {Car = car, Generation = generation, Camera = center.Name}
    if not self:QuestWait(0.4, generation, character, car, true) then
        return
    end
    if kind == "SpeedTraps" then
        local before = self:QuestProgress("SpeedTraps")
        state.CameraCooldowns[center.Name] = os.clock() + deps.Cooldown
        state.Attempt = {Camera = center.Name, Before = before, StartedAt = os.clock(), ExpiresAt = os.clock() + 45}
    end
    if self:QuestMotionStart(car, character, generation, corridor, kind) then
        self.QuestStatus = kind == "SpeedTraps" and "Accelerating toward " .. center.Name or "Driving on " .. center.Name
    end
end

function App:ClaimRewardsStep()
    if not self.Running then
        return
    end
    if not self.Settings.AutoClaimRewards and not next(self.RewardAttempts) then
        return
    end
    local ok, states = pcall(UIState.Objectives.get, UIState.Objectives)
    if not ok or type(states) ~= "table" then
        if self.Settings.AutoClaimRewards then
            self.ClaimStatus = "Waiting for quest data"
        end
        return
    end
    local now = os.clock()
    for name, attempt in pairs(self.RewardAttempts) do
        local state = states[name]
        if attempt.Sent and not attempt.Confirmed and type(state) == "table" and state.Rewarded == true then
            attempt.Confirmed = true
            self.SessionRewards = self.SessionRewards + 1
            if self.ClaimPending == name then
                self.ClaimPending = nil
            end
        end
    end
    if not self.Settings.AutoClaimRewards then
        return
    end
    if not EventUtil.IsActive(Workspace:GetServerTimeNow()) then
        self:SetOption("AutoClaimRewards", false)
        if self.Controls.AutoClaimRewards then
            self.Controls.AutoClaimRewards:Set(false, true)
        end
        self.ClaimStatus = "The Halloween event has ended"
        return
    end
    if self.ClaimPending then
        local pending = self.RewardAttempts[self.ClaimPending]
        if pending and now < pending.Deadline then
            self.ClaimStatus = "Waiting for confirmation: " .. pending.DisplayName
            return
        end
        if pending then
            pending.NextAttempt = now + 10
        end
        self.ClaimPending = nil
    end
    local unclaimed = false
    for _, objective in ipairs(Event.Objectives or {}) do
        local name = objective.Name
        local state = states[name]
        local attempt = self.RewardAttempts[name]
        if type(state) ~= "table" or state.Rewarded ~= true then
            unclaimed = true
        end
        if type(state) == "table" and state.Completed == true and state.Rewarded ~= true
            and not (attempt and attempt.Confirmed) and now >= (attempt and attempt.NextAttempt or 0) then
            attempt = attempt or {}
            attempt.DisplayName = objective.DisplayName or name
            attempt.Deadline = now + 5
            attempt.NextAttempt = now + 5
            self.RewardAttempts[name] = attempt
            self.ClaimPending = name
            self.ClaimStatus = "Claiming: " .. attempt.DisplayName
            local sent, failure = pcall(function()
                Event.ClaimObjectiveRemote:FireServer(name)
            end)
            if sent then
                attempt.Sent = true
            else
                self.ClaimPending = nil
                attempt.NextAttempt = now + 10
                if self.Settings.AutoClaimRewards then
                    self.ClaimStatus = "Could not claim " .. attempt.DisplayName .. "; retrying later"
                end
                self:Warn("Quest reward", failure)
            end
            return
        end
    end
    self.ClaimStatus = unclaimed and "Waiting for completed quests" or "All Halloween quest rewards are claimed"
end

function App:Start()
    local folder = Workspace:WaitForChild("Collectibles", 20)
    self.PumpkinFolder = folder and folder:WaitForChild(PumpkinGroup, 20)
    self.CrystalFolder = folder and folder:WaitForChild(CrystalGroup, 20)
    if not self.Running then
        return
    end
    if not self.PumpkinFolder or not self.CrystalFolder then
        error("Halloween Farm: collectible folders are unavailable", 0)
    end
    self:ReadSpots()
    self:ScanCrystals()
    self:Connect(self.PumpkinFolder:GetAttributeChangedSignal("RolledSpots"), function()
        self:ReadSpots()
    end)
    self:Connect(self.CrystalFolder.ChildAdded, function()
        self:ScanCrystals()
    end)
    local trove = PlayerData:Observe({"CollectibleService", CrystalGroup}, function(value)
        if self.Running and type(value) == "table" then
            local collected = {}
            for id, stamp in pairs(value) do
                if type(stamp) == "number" then
                    collected[tostring(id)] = stamp
                end
            end
            self.CrystalCollected = collected
        end
    end)
    if not self.Running then
        trove:Destroy()
        return
    end
    table.insert(self.Troves, trove)
    self:Connect(Player.CharacterAdded, function()
        self.Generation = self.Generation + 1
        self.TargetName = "None"
        if self.RaceState then
            self:RaceCancel()
        end
        if self.QuestState then
            self:QuestCancel()
        end
        if self:QuestEnabled() then
            self.QuestStatus = "Waiting for your character"
        end
        if self.Settings.AutoRace then
            self.RaceStatus = "Waiting for your character"
        end
        if self:Enabled() then
            self.Status = "Waiting for your character"
        end
    end)
    self:Connect(Player.Idled, function()
        if self.Settings.AntiAFK then
            local ok, failure = pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
            if not ok then
                self:Warn("Anti AFK", failure)
            end
        end
    end)
    self:Connect(Player.PlayerGui.ChildAdded, function(instance)
        self:RacePrize(instance)
    end)
    pcall(self.RefreshRaceVehicles, self)
    local legacyLoaded, legacy = pcall(function()
        return require(ReplicatedStorage.ModuleScript)
    end)
    if legacyLoaded and type(legacy) == "table" then
        self.RaceLegacy = legacy
    end
    local questLoaded, questFailure = pcall(self.QuestDependencies, self)
    if not questLoaded then
        self:Warn("Quest modules", questFailure)
    end
    self:BuildUI()
    if not self.Running then
        return
    end
    self:Spawn(function()
        while self.Running do
            local ok, failure = xpcall(function()
                self:RaceReconcile()
                self:QuestReconcile()
                if (self:QuestEnabled() or self.Settings.AutoRace or self:Enabled() or self.Settings.AutoClaimRewards)
                    and not EventUtil.IsActive(Workspace:GetServerTimeNow()) then
                    self:StopAll()
                    self.Status = "The Halloween event has ended"
                    self.QuestStatus = self.Status
                    self.RaceStatus = self.Status
                    return
                end
                if self.Settings.AutoRace then
                    self:RaceStep()
                elseif self:QuestEnabled() then
                    self:QuestStep()
                else
                    self:FarmStep()
                end
            end, debug.traceback)
            if not ok then
                self:Warn("Movement", failure)
                if self.Settings.AutoRace then
                    self:RaceRestart("Race error; retrying later")
                elseif self:QuestEnabled() then
                    self:QuestCancel()
                    self.QuestStatus = "Quest error; retrying later"
                else
                    self.Status = "Collector error; retrying"
                end
                task.wait(1)
            end
            task.wait(0.15)
        end
    end)
    self:Spawn(function()
        while self.Running do
            self:Reconcile()
            self:ScanCrystals()
            if self.Settings.AutoCrystals and self:CrystalProgress() < self.CrystalGoal and self:KnownCrystals() < self.CrystalGoal and #self.Discovery > 0 then
                local position = self.Discovery[self.DiscoveryIndex]
                if self:StreamAt(position, self.Generation, "Crystal", false) then
                    self.DiscoveryIndex = self.DiscoveryIndex % #self.Discovery + 1
                end
            end
            task.wait(0.5)
        end
    end)
    self:Spawn(function()
        while self.Running do
            local ok, failure = xpcall(function()
                self:ClaimRewardsStep()
            end, debug.traceback)
            if not ok then
                self:Warn("Quest rewards", failure)
                self.ClaimStatus = "Reward check failed; retrying later"
            end
            task.wait(0.75)
        end
    end)
    self:Spawn(function()
        while self.Running do
            local ok, failure = pcall(self.RefreshRaceVehicles, self)
            if not ok then
                self:Warn("Vehicle list", failure)
            end
            task.wait(5)
        end
    end)
end

function App:BindControl(native, key, kind)
    local owner = self
    local adapter = {Native = native}
    function adapter:Set(value, silent)
        local suppress = silent == true
        owner.SyncingControls = (owner.SyncingControls or 0) + (suppress and 1 or 0)
        local ok, failure = pcall(function()
            return owner:WithUI(function()
                if kind == "Toggle" then
                    native:Set(value == true, not suppress)
                elseif kind == "Keybind" then
                    native:Set(typeof(value) == "EnumItem" and value.Name or tostring(value))
                elseif kind == "Dropdown" then
                    native:Select(tostring(value))
                elseif kind == "Vehicle" then
                    local record = owner.RaceVehicleRecords[value]
                    native:Select(record and record.Label or "Auto")
                else
                    native:Set(value)
                end
            end)
        end)
        owner.SyncingControls = owner.SyncingControls - (suppress and 1 or 0)
        if not ok then
            error(failure, 0)
        end
    end
    self.Controls[key] = adapter
    return adapter
end

function App:ApplyUIOption(key, value)
    if not self.Running or (self.SyncingControls or 0) > 0 then
        return
    end
    self:SetOption(key, value)
    if self.Settings[key] ~= value then
        self:Spawn(function()
            task.wait()
            local control = self.Controls[key]
            if self.Running and control then
                control:Set(self.Settings[key], true)
            end
        end)
    end
end

function App:ToggleMenu(open)
    return self:WithUI(function()
    local window = self.Window
    if not self.Running or not window or window.Destroyed then
        return
    end
    if open == nil then
        open = window.Closed
    end
    if open and window.Closed then
        self:Layout()
        window:Open()
    elseif not open and not window.Closed then
        window:Close()
    end
    end)
end

function App:UpdateUI()
    if not self.Running or not self.Window or self.Window.Destroyed then
        return
    end
    local updates = {
        {self.Controls.StatusParagraph, tostring(self.Status) .. "\nTarget: " .. tostring(self.TargetName)},
        {self.Controls.ProgressParagraph, string.format("Pumpkin Balance: %d\nCrystal Progress: %d / %d\nKnown Crystal Locations: %d", self:Balance(), self:CrystalProgress(), self.CrystalGoal, self:KnownCrystals())},
        {self.Controls.SessionParagraph, string.format("Pumpkins: %d\nCrystals: %d\nCurrency Earned: %d", self.SessionPumpkins, self.SessionCrystals, self.SessionCurrency)},
    }
    if self.Controls.RewardsParagraph then
        updates[#updates + 1] = {self.Controls.RewardsParagraph, string.format("Claimed this session: %d\n%s", self.SessionRewards, self.ClaimStatus)}
    end
    if self.Controls.RaceStatusParagraph then
        updates[#updates + 1] = {self.Controls.RaceStatusParagraph, string.format("%s\nVehicle: %s\nCheckpoint: %s", self.RaceStatus, self.RaceVehicleName, self.RacePointName)}
        local ok, objectives = pcall(UIState.Objectives.get, UIState.Objectives)
        local objective = ok and type(objectives) == "table" and objectives.HalloweenRaceLaps
        local current = type(objective) == "table" and tonumber(objective.Current) or 0
        local goal = 100
        for _, item in ipairs(Event.Objectives or {}) do
            if item.Name == "HalloweenRaceLaps" then
                goal = tonumber(item.Goal) or goal
            end
        end
        local values = self.RaceDeps and self.RaceDeps.Values
        local lap = values and values.Parent and values:FindFirstChild("Laps")
        local laps = self.RaceDeps and self.RaceDeps.Script and self.RaceDeps.Script:FindFirstChild("Laps")
        updates[#updates + 1] = {self.Controls.RaceProgressParagraph, string.format("Current Lap: %d / %d\nHalloween Race Quest: %d / %d", lap and lap.Value or 0, laps and laps.Value or self.Settings.RaceLaps, current or 0, goal)}
        updates[#updates + 1] = {self.Controls.RaceSessionParagraph, string.format("Confirmed Races: %d\nRace Pumpkins: %d", self.SessionRaces, self.SessionRacePumpkins)}
    end
    if self.Controls.QuestStatusParagraph then
        updates[#updates + 1] = {self.Controls.QuestStatusParagraph, string.format("%s\nVehicle: %s", self.QuestStatus, self.QuestVehicleName)}
        local miles, milesGoal = self:QuestProgress("DriveMiles")
        local speed, speedGoal = self:QuestProgress("SpeedTraps")
        updates[#updates + 1] = {self.Controls.QuestProgressParagraph, string.format("Drive Distance: %.2f / %g MI\nSpeed Traps: %d / %g MPH", miles, milesGoal, math.floor(speed), speedGoal)}
    end
    return self:WithUI(function()
        if not self.Running or not self.Window or self.Window.Destroyed then
            return
        end
        for _, update in ipairs(updates) do
            if update[1] then
                update[1]:SetDesc(update[2])
            end
        end
    end)
end

function App:CleanupLibrary()
    return self:WithUI(function()
    local library = self.WindUI
    if not library then
        return
    end
    local signals = {UserInputService.InputBegan, UserInputService.InputChanged, UserInputService.InputEnded, RunService.Heartbeat, RunService.RenderStepped, RunService.Stepped, Workspace:GetPropertyChangedSignal("CurrentCamera")}
    local camera = Workspace.CurrentCamera
    if camera then
        table.insert(signals, camera:GetPropertyChangedSignal("ViewportSize"))
        table.insert(signals, camera:GetPropertyChangedSignal("CFrame"))
        table.insert(signals, camera:GetPropertyChangedSignal("FieldOfView"))
    end
    if self.LibraryEnvironment and type(getconnections) == "function" and type(getfenv) == "function" then
        for _, signal in ipairs(signals) do
            local ok, connections = pcall(getconnections, signal)
            if ok and type(connections) == "table" then
                for _, connection in ipairs(connections) do
                    local matched, belongs = pcall(function()
                        return type(connection.Function) == "function" and getfenv(connection.Function) == self.LibraryEnvironment
                    end)
                    if matched and belongs then
                        pcall(connection.Disconnect, connection)
                    end
                end
            end
        end
    end
    if library.Creator and library.Creator.DisconnectAll then
        pcall(library.Creator.DisconnectAll)
    end
    if not self.Window then
        for _, name in ipairs({"ScreenGui", "NotificationGui", "DropdownGui", "TooltipGui"}) do
            local gui = library[name]
            if gui then
                pcall(gui.Destroy, gui)
            end
        end
    end
    end)
end

function App:Layout(viewportOverride)
    return self:WithUI(function()
    local window = self.Window
    local library = self.WindUI
    if not self.Running or not window or window.Destroyed or not library.ScreenGui.Parent then
        return
    end
    local viewport = typeof(viewportOverride) == "Vector2" and viewportOverride or library.ScreenGui.AbsoluteSize
    if viewport.X < 1 or viewport.Y < 1 then
        return
    end
    local maxWidth = math.max(1, viewport.X - 24)
    local maxHeight = math.max(1, viewport.Y - 24)
    window.MinSize = Vector2.new(math.min(320, maxWidth), math.min(240, maxHeight))
    window.MaxSize = Vector2.new(maxWidth, maxHeight)
    if not window.IsFullscreen then
        local width = math.clamp(window.Size.X.Offset, window.MinSize.X, maxWidth)
        local height = math.clamp(window.Size.Y.Offset, window.MinSize.Y, maxHeight)
        if window.Size.X.Offset ~= width or window.Size.Y.Offset ~= height then
            window:SetSize(UDim2.fromOffset(width, height))
        end
        local main = window.UIElements.Main
        local center = main.AbsolutePosition + main.AbsoluteSize / 2 - library.ScreenGui.AbsolutePosition
        main.Position = UDim2.fromOffset(
            math.clamp(center.X, width / 2, math.max(width / 2, viewport.X - width / 2)),
            math.clamp(center.Y, height / 2, math.max(height / 2, viewport.Y - height / 2))
        )
    end
    local button = self.FloatingButton
    if button then
        local position = button.AbsolutePosition - library.ScreenGui.AbsolutePosition
        button.AnchorPoint = Vector2.zero
        button.Position = UDim2.fromOffset(
            math.clamp(position.X, 0, math.max(viewport.X - button.AbsoluteSize.X, 0)),
            math.clamp(position.Y, 0, math.max(viewport.Y - button.AbsoluteSize.Y, 0))
        )
    end
    end)
end

function App:ResetWindow()
    return self:WithUI(function()
    local window = self.Window
    if not self.Running or not window or window.Destroyed then
        return
    end
    self.WindUI.CurrentInput = nil
    if window.IsFullscreen then
        window:ToggleFullscreen()
    end
    window:IsResizable(true)
    if self.WindowDrag then
        self.WindowDrag:Set(true)
    end
    self:Spawn(function()
        task.wait(0.5)
        self:WithUI(function()
        if not self.Running or window.Destroyed then
            return
        end
        window:SetSize(UDim2.fromOffset(600, 360))
        window:SetToTheCenter()
        self:Layout()
        end)
    end)
    end)
end

function App:PrepareWindSource(source)
    source = source:gsub("\r\n", "\n")
    local function replace(before, after)
        local first, last = source:find(before, 1, true)
        if not first then
            error("WindUI compatibility patch is unavailable", 0)
        end
        source = source:sub(1, first - 1) .. after .. source:sub(last + 1)
    end
    replace([[av.WindUI.CurrentInput=M

if aw.CanResize then
startResizing(N)
end]], [[if not aw.CanResize or aw.IsFullscreen then
return
end
av.WindUI.CurrentInput=M
startResizing(N)]])
    replace([[local function startResizing(N)
if aw.CanResize then
isResizing=true]], [[local resizeInput
local function startResizing(N)
if aw.CanResize then
resizeInput=N
isResizing=true]])
    replace([[if isResizing and aw.CanResize then]], [[if isResizing and aw.CanResize and resizeInput and (N==resizeInput or (resizeInput.UserInputType==Enum.UserInputType.MouseButton1 and N.UserInputType==Enum.UserInputType.MouseMovement)) then]])
    replace([[isResizing=false
aB.Active=false]], [[isResizing=false
resizeInput=nil
aB.Active=false]])
    replace([[e.InputEnded:Connect(function(L)
if not C or m.CurrentInput~=A then
return
end]], [[e.InputEnded:Connect(function(L)
if not C then
return
end]])
    replace([[m.CurrentInput=nil
C=false
H=nil
B=nil]], [[if m.CurrentInput==A then
m.CurrentInput=nil
end
C=false
H=nil
B=nil]])
    replace([[if N.UserInputState==Enum.UserInputState.End then
if av.WindUI.CurrentInput and av.WindUI.CurrentInput~=M then
return
end

av.WindUI.CurrentInput=nil]], [[if (N.UserInputState==Enum.UserInputState.End or N.UserInputState==Enum.UserInputState.Cancel) and resizeInput==N then
if av.WindUI.CurrentInput==M then
av.WindUI.CurrentInput=nil
end]])
    return source
end

function App:PrepareWindFonts(creator)
    creator.UpdateFont = function(font)
        return self:WithUI(function()
            creator.Font = font
            for index = #creator.FontObjects, 1, -1 do
                local object = creator.FontObjects[index]
                local ok = pcall(function()
                    local face = object.FontFace
                    object.FontFace = Font.new(font, face.Weight, face.Style)
                end)
                if not ok then
                    table.remove(creator.FontObjects, index)
                end
            end
        end)
    end
end

function App:BuildUI()
    return self:WithUI(function()
    if type(getthreadidentity) == "function" then
        local ok, identity = pcall(getthreadidentity)
        if ok and type(identity) == "number" then
            self.UIThreadIdentity = identity
        end
    end
    local libraryUrl = "https://raw.githubusercontent.com/Footagesus/WindUI/d2c9bac5f96f997418d680d19cb759892542e492/dist/main.lua"
    local loaded, library = pcall(function()
        local source = self:PrepareWindSource(game:HttpGet(libraryUrl))
        local loader, failure = loadstring(source)
        if not loader then
            error("WindUI compilation failed: " .. tostring(failure), 0)
        end
        if type(setfenv) == "function" and type(getfenv) == "function" then
            self.LibraryEnvironment = setmetatable({}, {__index = getfenv()})
            setfenv(loader, self.LibraryEnvironment)
        end
        return loader()
    end)
    if not loaded or type(library) ~= "table" then
        error("WindUI failed to load: " .. tostring(library), 0)
    end
    self.WindUI = library
    local creator = library.Creator
    self:PrepareWindFonts(creator)
    self.DragControllers = {}
    local originalDrag = creator.Drag
    creator.Drag = function(target, handles, callback)
        local controller = originalDrag(target, handles, callback)
        self.DragControllers[target] = controller
        return controller
    end
    if creator and type(creator.Signals) == "table" then
        creator.DisconnectAll = function()
            for index = #creator.Signals, 1, -1 do
                local connection = table.remove(creator.Signals, index)
                pcall(connection.Disconnect, connection)
            end
        end
    end
    if not self.Running then
        self:CleanupLibrary()
        return
    end
    local theme = {}
    for key, value in pairs(library.Themes.Dark) do
        theme[key] = value
    end
    theme.Name = "Halloween"
    theme.Accent = Color3.fromRGB(194, 100, 35)
    theme.Background = Color3.fromRGB(22, 17, 25)
    theme.ElementBackground = Color3.fromRGB(42, 30, 42)
    library:AddTheme(theme)
    local window = library:CreateWindow({
        Title = "CDT Halloween Farm",
        Icon = "ghost",
        Theme = "Halloween",
        Size = UDim2.fromOffset(600, 360),
        MinSize = Vector2.new(320, 240),
        MaxSize = Vector2.new(600, 460),
        SideBarWidth = 110,
        Resizable = true,
        AutoScale = false,
        Acrylic = false,
        Transparent = false,
        HideSearchBar = true,
        NewElements = false,
        User = {Enabled = false},
        OpenButton = {Enabled = false, Draggable = false, OnlyMobile = false},
    })
    self.Window = window
    self.WindowDrag = self.DragControllers[window.UIElements.Main]
    self.Status = "Idle"
    self.SyncingControls = 0
    for index, name in ipairs({"ScreenGui", "DropdownGui", "TooltipGui", "NotificationGui"}) do
        library[name].Name = "CDT Halloween Farm" .. (index == 1 and "" or "/" .. name)
        library[name].ResetOnSpawn = false
        library[name].DisplayOrder = 10000 + index
    end
    window:OnDestroy(function()
        self:Unload()
    end)
    self:Connect(library.ScreenGui.Destroying, function()
        self:Unload()
    end)
    local constructing = true
    local function update(key, value)
        if self.Running and not constructing and self.SyncingControls == 0 then
            self:ApplyUIOption(key, value)
        end
    end
    local function toggle(tab, key, title, description)
        local native = tab:Toggle({
            Title = title,
            Desc = description,
            Value = self.Settings[key],
            Callback = function(value)
                update(key, value == true)
            end,
        })
        return self:BindControl(native, key, "Toggle")
    end
    local collection = window:Tab({Title = "Collect", Icon = "leaf"})
    local race = window:Tab({Title = "Race", Icon = "flag"})
    local quests = window:Tab({Title = "Quests", Icon = "list-checks"})
    local settings = window:Tab({Title = "Settings", Icon = "settings"})
    self.Tabs = {Collection = collection, Race = race, Quests = quests, Settings = settings}
    collection:Section({Title = "Collectibles"})
    toggle(collection, "AutoPumpkins", "Auto Pumpkins")
    toggle(collection, "AutoCrystals", "Auto Crystals")
    toggle(collection, "AutoClaimRewards", "Auto Claim Rewards")
    local delay = collection:Slider({
        Title = "Teleport Delay",
        Desc = "Seconds between teleports",
        Step = 0.05,
        Width = 110,
        IsTooltip = false,
        IsTextbox = true,
        Value = {Min = 0.2, Max = 3, Default = self.Settings.TeleportDelay},
        Callback = function(value)
            update("TeleportDelay", tonumber(value) or 0.75)
        end,
    })
    self:BindControl(delay, "TeleportDelay", "Slider")
    collection:Section({Title = "Progress"})
    self.Controls.StatusParagraph = collection:Paragraph({Title = "Status", Desc = "Idle"})
    self.Controls.ProgressParagraph = collection:Paragraph({Title = "Event Progress", Desc = "Loading progress"})
    self.Controls.SessionParagraph = collection:Paragraph({Title = "Session", Desc = "No collectibles collected yet"})
    self.Controls.RewardsParagraph = collection:Paragraph({Title = "Quest Rewards", Desc = self.ClaimStatus})
    race:Section({Title = "Halloween Race"})
    toggle(race, "AutoRace", "Auto Race")
    local vehicle = race:Dropdown({
        Title = "Vehicle",
        Values = self.RaceVehicleLabels,
        Value = "Auto",
        Callback = function(label)
            update("RaceVehicle", self.RaceVehicleByLabel and self.RaceVehicleByLabel[label] or "Auto")
        end,
    })
    self:BindControl(vehicle, "RaceVehicle", "Vehicle")
    local laps = race:Dropdown({
        Title = "Race Laps",
        Values = {"1", "3", "5"},
        Value = "5",
        Callback = function(value)
            update("RaceLaps", tonumber(value))
        end,
    })
    self:BindControl(laps, "RaceLaps", "Dropdown")
    local raceDelay = race:Slider({
        Title = "Checkpoint Delay",
        Desc = "Seconds between checkpoint movements",
        Step = 0.05,
        Width = 110,
        IsTooltip = false,
        IsTextbox = true,
        Value = {Min = 0.2, Max = 3, Default = self.Settings.RaceDelay},
        Callback = function(value)
            update("RaceDelay", tonumber(value) or 0.75)
        end,
    })
    self:BindControl(raceDelay, "RaceDelay", "Slider")
    race:Section({Title = "Progress"})
    self.Controls.RaceStatusParagraph = race:Paragraph({Title = "Race Status", Desc = self.RaceStatus})
    self.Controls.RaceProgressParagraph = race:Paragraph({Title = "Race Progress", Desc = "Waiting for a race"})
    self.Controls.RaceSessionParagraph = race:Paragraph({Title = "Race Session", Desc = "No confirmed races yet"})
    quests:Section({Title = "Halloween Quests"})
    toggle(quests, "AutoDriveDistance", "Auto Drive Distance")
    toggle(quests, "AutoSpeedTraps", "Auto Speed Traps")
    local questVehicle = quests:Dropdown({
        Title = "Vehicle",
        Values = self.QuestVehicleLabels or self.RaceVehicleLabels,
        Value = "Auto",
        Callback = function(label)
            update("QuestVehicle", self.QuestVehicleByLabel and self.QuestVehicleByLabel[label] or "Auto")
        end,
    })
    self:BindControl(questVehicle, "QuestVehicle", "Vehicle")
    quests:Section({Title = "Progress"})
    self.Controls.QuestStatusParagraph = quests:Paragraph({Title = "Quest Status", Desc = self.QuestStatus})
    self.Controls.QuestProgressParagraph = quests:Paragraph({Title = "Confirmed Progress", Desc = "Loading progress"})
    settings:Section({Title = "Session"})
    toggle(settings, "AntiAFK", "Anti AFK", "Prevent idle disconnection during this session")
    settings:Button({
        Title = "Reset Window",
        Icon = "maximize",
        Callback = function()
            self:ResetWindow()
        end,
    })
    settings:Button({
        Title = "Stop All",
        Icon = "square",
        Callback = function()
            self:StopAll()
            self:Notify("Stopped", "All automation is off; Anti AFK keeps its current setting", "Success")
        end,
    })
    local keybind = settings:Keybind({
        Title = "Menu Keybind",
        Value = "RightControl",
        Callback = function()
            if self.Running then
                self:ToggleMenu()
            end
        end,
    })
    self:BindControl(keybind, "MenuKeybind", "Keybind")
    settings:Button({
        Title = "Unload",
        Icon = "power",
        Callback = function()
            self:Unload()
        end,
    })
    settings:Section({Title = "Credits"})
    local creditText
    local credit = settings:Button({
        Title = "Credits - loading",
        Icon = "copy",
        Callback = function()
            if creditText then
                self:Copy(creditText)
            else
                self:Notify("Credits", "The credits text is not available yet", "Info")
            end
        end,
    })
    settings:Button({
        Title = "UI Library - WindUI",
        Icon = "copy",
        Callback = function()
            self:Copy("https://github.com/Footagesus/WindUI")
        end,
    })
    self:Spawn(function()
        local ok, text = pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
        end)
        if not self.Running or window.Destroyed then
            return
        end
        if ok and type(text) == "string" then
            text = text:match("^%s*(.-)%s*$")
            if text ~= "" and #text <= 200 and not text:find("[<>\r\n]") and not text:find("[^ -~]") then
                creditText = text
                self:WithUI(function()
                    credit:SetTitle("Credits - " .. text)
                end)
                return
            end
        end
        self:WithUI(function()
            credit:SetTitle("Credits - unavailable")
        end)
    end)
    local button = Instance.new("TextButton")
    button.Name = "HalloweenFloatingButton"
    button.Size = UDim2.fromOffset(140, 48)
    button.Position = UDim2.new(1, -152, 0, 12)
    button.BackgroundColor3 = Color3.fromRGB(42, 28, 34)
    button.TextColor3 = Color3.fromRGB(255, 188, 111)
    button.Text = "Halloween"
    button.TextSize = 16
    button.Font = Enum.Font.GothamMedium
    button.AutoButtonColor = false
    button.ZIndex = 100
    button.Parent = library.ScreenGui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = button
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = Color3.fromRGB(218, 130, 61)
    stroke.Thickness = 1.5
    stroke.Parent = button
    self.FloatingButton = button
    local pointer
    local isMouse = false
    local dragged = false
    local pressedAt = Vector2.zero
    local offset = Vector2.zero
    local function position(event)
        return Vector2.new(event.Position.X, event.Position.Y)
    end
    local function begin(event)
        return self:WithUI(function()
        if not self.Running or pointer then
            return
        end
        if event.UserInputType ~= Enum.UserInputType.Touch and event.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        pointer = event
        isMouse = event.UserInputType == Enum.UserInputType.MouseButton1
        dragged = false
        pressedAt = position(event)
        offset = pressedAt - button.AbsolutePosition
        end)
    end
    local function move(event)
        return self:WithUI(function()
        if not pointer or not self.Running then
            return
        end
        if event ~= pointer and not (isMouse and event.UserInputType == Enum.UserInputType.MouseMovement) then
            return
        end
        local current = position(event)
        if (current - pressedAt).Magnitude > 4 then
            dragged = true
        end
        if dragged then
            local localPosition = current - offset - library.ScreenGui.AbsolutePosition
            local viewport = library.ScreenGui.AbsoluteSize
            button.AnchorPoint = Vector2.zero
            button.Position = UDim2.fromOffset(
                math.clamp(localPosition.X, 0, math.max(viewport.X - button.AbsoluteSize.X, 0)),
                math.clamp(localPosition.Y, 0, math.max(viewport.Y - button.AbsoluteSize.Y, 0))
            )
        end
        end)
    end
    local function finish(event)
        if not pointer or (event ~= pointer and not (isMouse and event.UserInputType == Enum.UserInputType.MouseButton1)) then
            return
        end
        local tapped = not dragged
        pointer = nil
        if tapped then
            self:ToggleMenu()
        end
    end
    self.FloatingInput = {Begin = begin, Move = move, Finish = finish}
    self:Connect(button.InputBegan, begin)
    self:Connect(UserInputService.InputChanged, move)
    self:Connect(UserInputService.InputEnded, finish)
    self:Connect(library.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"), function()
        self:Layout()
    end)
    constructing = false
    self:UpdateUI()
    self:Spawn(function()
        task.wait(0.9)
        if self.Running then
            self:Layout()
            if not window.Closed and not window.IsFullscreen and self.WindowDrag then
                self.WindowDrag:Set(true)
            end
        end
    end)
    self:Spawn(function()
        while self.Running do
            local ok, failure = pcall(self.UpdateUI, self)
            if not ok then
                self:Warn("Interface update", failure)
            end
            task.wait(0.5)
        end
    end)
    return window
    end)
end

local initialized, failure = xpcall(function()
    App:Start()
end, debug.traceback)
if not initialized then
    App:Unload()
    error("Halloween Farm: initialization failed: " .. tostring(failure), 0)
end

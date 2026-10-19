local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")
if not game:IsLoaded() then game.Loaded:Wait() end
local Player = Players.LocalPlayer
local Environment = type(getgenv) == "function" and getgenv() or _G
local Key = "MM2Candy"
local AccountId = tostring(Player.UserId)
local StateMemoryKey = Key .. "Remembered"
local Remembered = type(Environment[StateMemoryKey]) == "table" and Environment[StateMemoryKey] or {}
Environment[StateMemoryKey] = Remembered

local function cleanup(callback)
    local ok, err = pcall(callback)
    local getIdentity, setIdentity = getthreadidentity or getidentity, setthreadidentity or setidentity
    if not ok and tostring(err):find("capability Plugin", 1, true)
        and type(getIdentity) == "function" and type(setIdentity) == "function" then
        local got, identity = pcall(getIdentity)
        if got then
            for _, level in ipairs({6, 8}) do
                if pcall(setIdentity, level) then ok, err = pcall(callback) end
                pcall(setIdentity, identity)
                if ok then break end
            end
        end
    end
    return ok, err
end

local function pendingWebhook(app)
    local ok, value = pcall(function()
        local box = app.WebhookBox
        local control = app.Controls and app.Controls.WebhookURL
        if not box and control and control._frame then box = control._frame:QueryDescendants("TextBox")[1] end
        return box and box.Text
    end)
    return ok and type(value) == "string" and value:sub(1, 300):match("^%s*(.-)%s*$") or nil
end

local prior = Environment[Key]
if type(prior) == "table" and type(prior.Settings) == "table" and prior.Player
    and tostring(prior.Player.UserId) == AccountId and not prior.Unloaded and prior.Running ~= false
    and prior.StateLoaded ~= false then
    prior.Settings.WebhookURL = pendingWebhook(prior) or prior.Settings.WebhookURL
    Remembered[AccountId] = table.clone(prior.Settings)
end
local function unloadPrevious(previous)
    if type(previous) ~= "table" or type(previous.Unload) ~= "function" then return end
    local ok = cleanup(function() previous:Unload() end)
    if not ok then
        previous.Running = false
        for _, connection in ipairs(previous.Connections or {}) do pcall(function() connection:Disconnect() end) end
        if type(previous.ReleaseFlight) == "function" then cleanup(function() previous:ReleaseFlight(false) end) end
        if type(previous.RestoreAntiFling) == "function" then cleanup(function() previous:RestoreAntiFling() end) end
        if previous.Webhook then cleanup(function() previous.Webhook:Close() end) end
        if previous.Window then cleanup(function() previous.Window:Destroy() end) end
    end
end
unloadPrevious(prior)
if game.PlaceId ~= 142823291 then
    warn("[MM2 Candy] Open Murder Mystery 2 before running this script.")
    return
end

local Defaults = {
    FarmEnabled = false, AutoReset = false, AutoEndRound = false, AntiAFK = true, AntiFling = true, AutoReconnect = true,
    MenuKeybind = "RightControl",
    TravelSpeed = 55, TravelSpeedPresetVersion = 1, UnderfloorDepth = 6,
    TouchAssist = true,
    WebhookEnabled = false, WebhookURL = "", WebhookInterval = 10, WebhookOnFull = true,
}
local App = {
    Running = true, Player = Player, Settings = table.clone(Defaults),
    Connections = {}, Controls = {}, Collision = {}, TouchFlags = {}, Coins = {}, AntiFlingParts = {},
    TouchSupported = type(firetouchinterest) == "function",
    Cooldowns = setmetatable({}, {__mode = "k"}),
    Stats = {Collected = 0, Bags = 0, Rounds = 0, Deaths = 0, Corrections = 0},
    StartedAt = os.clock(), ActiveElapsed = 0, Status = "Disabled", BagCount = 0,
    BagCapacity = nil, BagFull = false, RoundBlocked = false, RoundSerial = 0,
    Map = nil, Target = nil, FullHandled = false, ResetRequested = false,
    PauseUntil = 0, NextScan = 0, NextRound = 0, DeathRecorded = false,
    StorageRoot = Key, AccountRoot = Key .. "/" .. AccountId,
    StatePath = Key .. "/" .. AccountId .. "/state.json",
    StateLoaded = false,
    DeathBootstrapAllowed = true,
    Flow = {Phase = "Waiting", Owner = nil, Epoch = 0, ChangedAt = os.clock()},
    ReturnTween = type(prior) == "table" and prior.ReturnTween or nil,
}
Environment[Key] = App

function App:Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self.Connections, connection)
    return connection
end

function App:Notify(title, message, kind)
    if self.Window and not self.Window._destroyed then
        self.Window:Notify({Title = title, Content = message, Type = kind or "Info", Duration = 4})
    end
end

function App:Transition(phase, reason)
    local flow = self.Flow
    if flow.Phase == phase then flow.Reason = reason; return end
    local owner = phase == "Farming" and "Farm" or (phase == "Starting" and "Start")
        or ((phase == "Contact" or phase == "Confirming" or phase == "EndReady") and "EndRound") or nil
    if owner ~= "Farm" then self.HarvestPause = nil end
    if flow.Owner ~= owner or phase == "Contact" or flow.Phase == "Farming" then
        self:CancelMove()
        self:ResetPickup()
        self.Target, self.WaitingPosition = nil, nil
    end
    flow.Epoch, flow.Phase, flow.Owner, flow.Reason, flow.ChangedAt = flow.Epoch + 1, phase, owner, reason, os.clock()
end

function App:CancelEndRoundSequence(reason)
    self:StopEndRound(reason)
    if self.EndRoundCycle then
        if self.EndRoundCycle.Outcome == "Pending" then self.EndRoundCycle.Outcome = "Cancelled" end
        self.LastEndRoundReport = table.clone(self.EndRoundCycle)
    end
    self.EndRoundCycle = nil
    self.EndRoundRetryAt = 0
    self:Transition("Waiting", reason)
end

function App:RequestEndRound(reason)
    if not self.Settings.FarmEnabled then return end
    if self.Flow.Phase == "Farming" or self.Flow.Phase == "Waiting" then self:Transition("EndReady", reason) end
end

local function pathChild(parent, ...)
    for _, name in ipairs({...}) do
        parent = parent and parent:FindFirstChild(name)
    end
    return parent
end

local function finite(value, fallback, low, high)
    local number = tonumber(value)
    if not number or number ~= number or math.abs(number) == math.huge then return fallback end
    return math.clamp(number, low, high)
end

local function finiteFrame(frame)
    for _, value in ipairs({frame:GetComponents()}) do
        if value ~= value or math.abs(value) == math.huge then return false end
    end
    return true
end

local function sanitize(data)
    local settings = table.clone(Defaults)
    for k, default in pairs(Defaults) do
        if type(data) == "table" and type(data[k]) == type(default) then settings[k] = data[k] end
    end
    settings.TravelSpeed = finite(settings.TravelSpeed, 55, 10, 100)
    settings.UnderfloorDepth = finite(settings.UnderfloorDepth, 6, 2, 6)
    settings.WebhookInterval = finite(settings.WebhookInterval, 10, 1, 60)
    local validKey, key = pcall(function() return Enum.KeyCode[settings.MenuKeybind] end)
    if not validKey or not key then settings.MenuKeybind = "RightControl" end
    if #settings.WebhookURL > 300 then settings.WebhookURL = "" end
    return settings
end

function App:StateReady()
    if type(writefile) ~= "function" or type(readfile) ~= "function" or type(isfile) ~= "function"
        or type(makefolder) ~= "function" or type(isfolder) ~= "function" then return false end
    local ok = pcall(function()
        if not isfolder(self.StorageRoot) then makefolder(self.StorageRoot) end
        if not isfolder(self.AccountRoot) then makefolder(self.AccountRoot) end
    end)
    return ok
end

function App:RememberState()
    Remembered[AccountId] = table.clone(self.Settings)
end

function App:ScheduleSave()
    if self.Unloading or not self.Running or not self.StateLoaded then return end
    self:RememberState()
    self.SaveDue = os.clock() + 0.35
end

function App:SaveState()
    if not self.StateLoaded then return false, "State has not loaded yet." end
    self:RememberState()
    if not self:StateReady() then
        self.SaveDue = os.clock() + 5
        self.PersistenceMode = "Memory"
        return false, "Disk saving is unavailable."
    end
    local ok, err = pcall(function()
        writefile(self.StatePath, HttpService:JSONEncode({Version = 1, UserId = Player.UserId, Settings = self.Settings}))
    end)
    self.SaveDue = not ok and os.clock() + 5 or nil
    self.PersistenceMode, self.SaveError = ok and "Disk" or "Memory", not ok and tostring(err) or nil
    return ok, err
end

function App:LoadState()
    local saved = Remembered[AccountId]
    if type(saved) ~= "table" and self:StateReady() then
        local ok, data = pcall(function()
            if not isfile(self.StatePath) then return nil end
            return HttpService:JSONDecode(readfile(self.StatePath))
        end)
        if ok and type(data) == "table" and tostring(data.UserId) == AccountId
            and type(data.Settings) == "table" then saved = data.Settings end
    end
    local speedPresetVersion = type(saved) == "table" and saved.TravelSpeedPresetVersion
    local migrateSpeed = type(speedPresetVersion) ~= "number" or speedPresetVersion ~= speedPresetVersion
        or speedPresetVersion < 1 or speedPresetVersion == math.huge
    self.Settings = sanitize(saved)
    if migrateSpeed then
        self.Settings.TravelSpeed = 55
        self.Settings.TravelSpeedPresetVersion = 1
    end
    self.RestoredState = type(saved) == "table"
    self.StateLoaded = true
    self:RememberState()
    if migrateSpeed then self:SaveState() end
end

local function enumName(value)
    return tostring(value):match("([^%.]+)$")
end

local function isDisconnect(name)
    return type(name) == "string" and (name == "ServerShutdown"
        or (name:sub(1, 10) == "Disconnect" and name ~= "DisconnectClientRequest" and name ~= "DisconnectRejoin"))
end

local disconnectCodes
local function connectionErrorName(value)
    if value == nil then return nil end
    local named, name = pcall(function() return value.Name end)
    if named and type(name) == "string" then return name end
    local number = tonumber(value)
    if not number then
        local valued, numberValue = pcall(function() return value.Value end)
        if valued then number = tonumber(numberValue) end
    end
    if not number then return enumName(value) end
    if not disconnectCodes then
        local codes = {[288] = "ServerShutdown", [276] = "DisconnectRejoin", [285] = "DisconnectClientRequest"}
        pcall(function()
            for _, item in ipairs(Enum.ConnectionError:GetEnumItems()) do codes[item.Value] = item.Name end
        end)
        disconnectCodes = codes
    end
    return disconnectCodes[number]
end

function App:DisconnectReason()
    local ok, code = pcall(function() return GuiService:GetErrorCode() end)
    local name = ok and connectionErrorName(code) or nil
    if isDisconnect(name) then return name end
    if name == "DisconnectClientRequest" or name == "DisconnectRejoin" then return nil end
    if not ok or code == nil then
        local typed, kind = pcall(function() return GuiService:GetErrorType() end)
        local kindName = typed and connectionErrorName(kind) or nil
        if isDisconnect(kindName) then return kindName end
        if kindName == "DisconnectClientRequest" or kindName == "DisconnectRejoin" then return nil end
    end
    local readable, reason = pcall(function()
        local gui = CoreGui:FindFirstChild("RobloxPromptGui")
        local overlay = gui and gui:FindFirstChild("promptOverlay")
        local prompt = overlay and overlay:FindFirstChild("ErrorPrompt")
        if not prompt or prompt.Visible ~= true or overlay.Visible == false or gui.Enabled == false then return end
        local message = pathChild(prompt, "MessageArea", "ErrorFrame", "ErrorMessage")
        local suffix = message and tostring(message.Text):match("%(([^()]*)%)%s*$")
        local number = suffix and tonumber(suffix:match("(%d+)%s*$"))
        local promptName = number and connectionErrorName(number)
        return isDisconnect(promptName) and promptName or nil
    end)
    return readable and reason or nil
end

function App:CancelReconnect()
    self.ReconnectPending = nil
    self.ReconnectStatus = "Off"
end

function App:QueueReconnect(reason)
    if not self.Running or self.Unloading or not self.Settings.AutoReconnect or self.ReconnectPending then return end
    self.StartGuard = nil
    self.ReconnectPending = {Reason = reason, Attempts = 0, NextAt = os.clock() + 3, InFlight = false}
    self.ReconnectStatus = "Reconnecting in 3 seconds"
    self.Settings.WebhookURL = pendingWebhook(self) or self.Settings.WebhookURL
    self:SaveState()
    cleanup(function() self:ReleaseFlight(false) end)
    self:Transition("Reconnecting", reason)
    self:Notify("Auto Reconnect", "Disconnected. Rejoining the game...", "Info")
end

function App:ReconnectFailed(message)
    local pending = self.ReconnectPending
    if not pending or not pending.InFlight then return end
    pending.InFlight = false
    pending.NextAt = os.clock() + math.min(30, 3 * 2 ^ math.min(pending.Attempts - 1, 4))
    self.ReconnectError = tostring(message)
    self.ReconnectStatus = "Reconnect failed; retrying"
end

function App:ReconnectTick()
    if not self.Running or self.Unloading or not self.Settings.AutoReconnect then return end
    if not self.ReconnectPending then
        local reason = self:DisconnectReason()
        if not reason then self.ReconnectStatus = "Waiting for disconnect"; return end
        self:QueueReconnect(reason)
    end
    local pending, now = self.ReconnectPending, os.clock()
    if pending.InFlight then
        if now >= pending.Deadline then self:ReconnectFailed("Teleport did not complete") end
        return
    end
    if now < pending.NextAt then return end
    pending.Attempts, pending.InFlight, pending.Deadline = pending.Attempts + 1, true, now + 30
    self.ReconnectStatus = "Joining game (attempt " .. pending.Attempts .. ")"
    local ok, err = pcall(function() TeleportService:Teleport(game.PlaceId, Player) end)
    if self.ReconnectPending ~= pending then return end
    if not ok then self:ReconnectFailed(err) end
end

function App:StartReconnect()
    self.ReconnectMonitor = {}
    self.ReconnectMonitor.ErrorSignal = pcall(function()
        self:Connect(GuiService.ErrorMessageChanged, function() self:ReconnectTick() end)
    end)
    self.ReconnectMonitor.TeleportFailure = pcall(function()
        self:Connect(TeleportService.TeleportInitFailed, function(player, result, message, placeId)
            if player ~= Player or placeId ~= game.PlaceId or enumName(result) == "IsTeleporting" then return end
            self:ReconnectFailed(message)
        end)
    end)
    self.ReconnectMonitor.TeleportState = pcall(function()
        self:Connect(Player.OnTeleport, function(state)
            if state == Enum.TeleportState.Failed then self:ReconnectFailed("Teleport failed") end
        end)
    end)
    self.ReconnectWorker = task.spawn(function()
        while self.Running do
            local ok, err = pcall(function() self:ReconnectTick() end)
            if not ok then self.ReconnectError = tostring(err) end
            task.wait(1)
        end
    end)
end

local gameplay = pathChild(ReplicatedStorage, "Remotes", "Gameplay")
local roundModule = pathChild(ReplicatedStorage, "Modules", "CurrentRoundClient")
local profileModule = pathChild(ReplicatedStorage, "Modules", "ProfileData")
local roundOK, RoundData = pcall(require, roundModule)
local profileOK, Profile = pcall(require, profileModule)
if not roundOK or type(RoundData) ~= "table" or not gameplay then
    App.Running = false
    warn("[MM2 Candy] CurrentRoundClient/Gameplay unavailable; no movement started.")
    return
end
if not profileOK then Profile = nil end

function App:GetMap()
    for _, map in ipairs(CollectionService:GetTagged("CurrentMap")) do
        if map:IsA("Model") and map.Name ~= "Lobby" and map:IsDescendantOf(workspace) then return map end
    end
    for _, map in ipairs(workspace:GetChildren()) do
        if map:IsA("Model") and map.Name ~= "Lobby" and map:FindFirstChild("CoinContainer", true) then return map end
    end
    return nil
end

function App:ScanCoins()
    local coins, seen = {}, {}
    local function add(coin)
        if coin and not seen[coin] then
            seen[coin] = true
            if self:CoinVisual(coin) then coins[#coins + 1] = coin end
        end
    end
    for _, coin in ipairs(CollectionService:GetTagged("ServerCoinPart")) do add(coin) end
    for _, visual in ipairs(CollectionService:GetTagged("CoinVisual")) do add(visual.Parent) end
    if self.Map and self.Map:IsDescendantOf(workspace) then
        for _, coin in ipairs(self.Map:QueryDescendants('BasePart[$CoinID = "Candy"]')) do add(coin) end
    end
    self.Coins = coins
end

function App:GetCharacter()
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return character, humanoid, root
end

function App:IsRoundParticipantAlive(entry)
    if not entry or type(entry.Role) ~= "string" or entry.Dead == true or entry.Killed == true then return false end
    local alive = Player:GetAttribute("Alive")
    if entry.Role == "Survivor" or entry.Role == "Zombie" then return entry.Dead == false or alive ~= false end
    return entry.Dead == false and alive == true
end

function App:RoundState()
    local character, humanoid, root = self:GetCharacter()
    if not character or not humanoid or not root or humanoid.Health <= 0
        or humanoid:GetState() == Enum.HumanoidStateType.Dead then return false, "Dead / respawning" end
    local timer = workspace:FindFirstChild("RoundTimerPart")
    local remaining = timer and timer:GetAttribute("Time")
    if type(remaining) ~= "number" or remaining <= 0 or remaining ~= remaining then
        return false, "Waiting for an active round"
    end
    local entry = RoundData.PlayerData and RoundData.PlayerData[Player.Name]
    if self.RoundBlocked or not self.Map or not self.Map.Parent or not self:IsRoundParticipantAlive(entry) then
        return false, "Waiting for an active round"
    end
    if self.BoundsMap ~= self.Map then
        self.BoundsFrame, self.BoundsSize = self.Map:GetBoundingBox()
        self.BoundsMap = self.Map
    end
    local offset = root.Position - self.BoundsFrame.Position
    if math.abs(offset.X) > self.BoundsSize.X / 2 + 100
        or math.abs(offset.Z) > self.BoundsSize.Z / 2 + 100
        or math.abs(offset.Y) > self.BoundsSize.Y / 2 + 200 then
        return false, "Outside the active map"
    end
    return true, "Active", character, humanoid, root
end

function App:RoundOngoing()
    local timer = workspace:FindFirstChild("RoundTimerPart")
    local remaining = timer and timer:GetAttribute("Time")
    return not self.RoundBlocked and self.Map and self.Map.Parent ~= nil
        and type(remaining) == "number" and remaining > 0 and remaining == remaining
end

function App:QueueDeathEndRound(character, entry)
    if not self.Running or not self.Settings.FarmEnabled or not self.Settings.AutoEndRound
        or not self:RoundOngoing() then return false end
    character = character or Player.Character
    entry = entry or (RoundData.PlayerData and RoundData.PlayerData[Player.Name])
    if not entry or (entry.Role ~= "Innocent" and entry.Role ~= "Sheriff" and entry.Role ~= "Hero") then return false end
    if not self.DeathBootstrapAllowed and self.DeathObservedRoundSerial ~= self.RoundSerial then return false end
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local physicalDeath = humanoid and (humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead)
        and self.DeathEligibleCharacter == character
    if entry.Dead ~= true and entry.Killed ~= true and not physicalDeath then return false end
    local context = self.DeathEndRoundContext
    if context and context.Serial == self.RoundSerial and context.Map == self.Map then return true end
    self:ReleaseFlight(false)
    self.DeathEndRoundContext = {Serial = self.RoundSerial, Map = self.Map, Role = entry.Role, ReadyAt = os.clock() + 0.5}
    if self.EndRoundCycle then self.EndRoundCycle.Trigger, self.EndRoundCycle.ConfirmUntil = "Death", 0 end
    self.EndRoundRetryAt = 0
    self.Target = nil
    self:RequestEndRound("Death")
    return true
end

function App:DeathEndRoundAllowed()
    local context = self.DeathEndRoundContext
    local entry = RoundData.PlayerData and RoundData.PlayerData[Player.Name]
    return context ~= nil and self.Running and self.Settings.FarmEnabled and self.Settings.AutoEndRound
        and context.Serial == self.RoundSerial and context.Map == self.Map and self:RoundOngoing()
        and (not entry or entry.Role ~= "Murderer")
end

function App:DeathEndRoundState()
    if not self:DeathEndRoundAllowed() then return false, "Waiting for an active round" end
    if os.clock() < self.DeathEndRoundContext.ReadyAt then return false, "Auto End Round: waiting for respawn" end
    local character, humanoid, root = self:GetCharacter()
    if not character or not character:IsDescendantOf(workspace) or not humanoid or not root
        or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead or root.Anchored then
        return false, "Auto End Round: waiting for respawn"
    end
    if self.BoundsMap ~= self.Map then
        self.BoundsFrame, self.BoundsSize = self.Map:GetBoundingBox()
        self.BoundsMap = self.Map
    end
    return true, "Auto End Round after death", character, humanoid, root
end

function App:CancelDeathEndRound(restorePosition)
    local context = self.DeathEndRoundContext
    if not context then return end
    self.DeathEndRoundContext = nil
    self:ReleaseFlight(false)
    local character, humanoid, root = self:GetCharacter()
    if restorePosition and character == context.ControlCharacter and humanoid and humanoid.Health > 0
        and root and context.ReturnCFrame and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
        root.CFrame = context.ReturnCFrame
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    end
end

function App:CoinVisual(coin)
    if not coin or not coin:IsA("BasePart") or not coin.Parent or not self.Map
        or not coin:IsDescendantOf(self.Map) or coin:GetAttribute("CoinID") ~= "Candy"
        or coin:GetAttribute("Collected") or coin:GetAttribute("RoundEnd") or coin:GetAttribute("Delete") then return nil end
    local visual = coin:FindFirstChild("CoinVisual")
    if not visual or not visual:IsA("BasePart") or visual.Transparency >= 0.99
        or 1 - (1 - visual.Transparency) * (1 - visual.LocalTransparencyModifier) >= 0.99 or visual:GetAttribute("Collected")
        or visual:GetAttribute("RoundEnd") or visual:GetAttribute("Delete") then return nil end
    return visual
end

function App:ReadBag()
    local bag = pathChild(Player:FindFirstChild("PlayerGui"), "MainGUI", "Game", "CoinBags", "Container", "Candy")
    local label = pathChild(bag, "CurrencyFrame", "Icon", "Coins")
    local baseline
    if label then
        local count = tonumber((label.Text:gsub(",", "")))
        if count and count == count and count >= 0 and count < math.huge then
            self.BagCount, baseline = math.max(self.BagCount, count), count
        end
    end
    local full = bag and bag:FindFirstChild("Full")
    if full and full.Visible and bag.Visible then self.BagFull = true end
    if self.BagCapacity and self.BagCount >= self.BagCapacity then self.BagFull = true end
    if self.AcknowledgedCount == nil and baseline ~= nil then self.AcknowledgedCount = baseline end
end

function App:TotalCandy()
    local materials = Profile and Profile.Materials and Profile.Materials.Owned
    if type(materials) ~= "table" then return nil end
    local value, year = nil, 0
    for key, count in pairs(materials) do
        local candidate = tonumber(tostring(key):match("^Candies(%d%d%d%d)$"))
        if candidate and candidate > year then year, value = candidate, tonumber(count) end
    end
    return value
end

function App:Snapshot()
    local elapsed = math.max(0, os.clock() - self.StartedAt)
    return {
        Collected = self.Stats.Collected, Bags = self.Stats.Bags, Rounds = self.Stats.Rounds,
        Deaths = self.Stats.Deaths, Elapsed = elapsed,
        Rate = self.ActiveElapsed > 0 and self.Stats.Collected * 3600 / self.ActiveElapsed or 0,
        BagCount = self.BagCount, BagCapacity = self.BagCapacity,
        Map = self.Map and self.Map.Name or "Lobby", Status = self.Status, TotalCandy = self:TotalCandy(),
    }
end

function App:RestoreTouchFlags()
    for part, value in pairs(self.TouchFlags) do
        if part.Parent then pcall(function() part.CanTouch = value end) end
    end
    table.clear(self.TouchFlags)
end

function App:RestoreCollision()
    for part, value in pairs(self.Collision) do
        if part.Parent then pcall(function() part.CanCollide = value end) end
    end
    table.clear(self.Collision)
    self:RestoreTouchFlags()
end

function App:FinishTouch()
    local contact = self.TouchContact
    self.TouchContact = nil
    if contact and contact.Root.Parent and contact.Coin.Parent and type(firetouchinterest) == "function" then
        local ok, err = pcall(firetouchinterest, contact.Root, contact.Coin, 1)
        if not ok then self:DisableTouchAssist(err) end
    end
end

function App:ResetPickup()
    self:FinishTouch()
    self.ArrivedAt, self.NextTouchAt, self.TouchAttempts, self.TouchSent = nil, 0, 0, false
end

function App:CalculateHarvestDelay(distance, speed)
    distance = tonumber(distance)
    if not distance or distance ~= distance or math.abs(distance) == math.huge then return 2.5 end
    speed = finite(speed or self.Settings.TravelSpeed, 55, 10, 100)
    return math.clamp(0.2 + math.max(0, distance) / speed, 0.35, 2.5)
end

function App:UpdateHarvestPause(pause, root, force)
    local now = os.clock()
    if not force and now < (pause.NextPlanAt or 0) and pause.Speed == self.Settings.TravelSpeed
        and pause.Depth == self.Settings.UnderfloorDepth and pause.TouchAssist == self.Settings.TouchAssist
        and (not pause.NextCoin or self:CoinVisual(pause.NextCoin)) then return end
    local route = self:PlanCoinRoute(root, pause.PickupCoin)
    local candidate = route[1]
    pause.NextCoin = candidate and candidate.Coin
    pause.Distance = candidate and (candidate.Position - pause.Position).Magnitude or 0
    pause.Duration = self:CalculateHarvestDelay(pause.Distance)
    pause.Until, pause.NextPlanAt = pause.StartedAt + pause.Duration, now + 0.15
    pause.Speed, pause.Depth, pause.TouchAssist = self.Settings.TravelSpeed, self.Settings.UnderfloorDepth, self.Settings.TouchAssist
end

function App:BeginHarvestPause()
    if not self.Running or self.Unloading or not self.Settings.FarmEnabled or self.BagFull
        or self.Flow.Phase ~= "Farming" then return end
    local active, _, character, _, root = self:RoundState()
    if not active then return end
    local now, pause = os.clock(), self.HarvestPause
    if pause and pause.Root == root and pause.Map == self.Map and pause.Serial == self.RoundSerial
        and now < pause.Until then
        pause.StartedAt = now
        self:ScanCoins()
        self:UpdateHarvestPause(pause, root, true)
        return
    end
    local pickupCoin = self.ArrivedAt and (self.TouchSent or not self.Settings.TouchAssist) and self.Target or nil
    self:CancelMove()
    self:ResetPickup()
    self.Target, self.WaitingPosition = nil, nil
    pause = {StartedAt = now, Position = root.Position, Root = root, PickupCoin = pickupCoin,
        Character = character, Map = self.Map, Serial = self.RoundSerial}
    self.HarvestPause = pause
    self:ScanCoins()
    self:UpdateHarvestPause(pause, root, true)
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    self.Expected = root.Position
    self.Status = "Candy collected: waiting before next flight"
end

function App:CancelMove()
    local motion = self.Motion
    self.Motion = nil
    if motion then pcall(function() motion.Tween:Cancel() end) end
    if self.ReturnTween then
        pcall(function() self.ReturnTween:Cancel() end)
        self.ReturnTween = nil
    end
end

function App:DisableTouchAssist(reason)
    local changed = self.Settings.TouchAssist
    self.TouchSupported, self.Settings.TouchAssist = false, false
    if reason then self.LastTouchError = tostring(reason) end
    if changed then
        self:ResetPickup()
        self:CancelMove()
        self.Target, self.WaitingPosition = nil, nil
        self:ScheduleSave()
    end
    local control = self.Controls.TouchAssist
    if control and not self.Unloading then
        control:Set(false, true)
        control:SetLocked(true)
        control:SetDesc("requires executor support")
    end
end

function App:ReleaseFlight(restorePosition)
    self.HarvestPause = nil
    self:StopEndRound("Movement stopped")
    self:CancelMove()
    self:ResetPickup()
    local _, humanoid, root = self:GetCharacter()
    local flightHumanoid = self.FlightCharacter and self.FlightCharacter:FindFirstChildOfClass("Humanoid")
    if restorePosition and root and humanoid and humanoid.Health > 0 and self:RoundState()
        and self.LastSurface and self.FlightCharacter == Player.Character then
        local duration = math.max(0.1, (root.Position - self.LastSurface.Position).Magnitude / self.Settings.TravelSpeed)
        self.ReturnTween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = self.LastSurface})
        self.ReturnTween:Play()
        root.AssemblyLinearVelocity = Vector3.zero
    end
    self:RestoreCollision()
    if flightHumanoid and self.SavedAutoRotate ~= nil then
        flightHumanoid.AutoRotate = self.SavedAutoRotate
        flightHumanoid.PlatformStand = self.SavedPlatformStand == true
        if flightHumanoid.Health > 0 and not self.SavedPlatformStand then
            flightHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
    self.SavedAutoRotate, self.SavedPlatformStand, self.FlightCharacter, self.Expected, self.WaitingPosition = nil, nil, nil, nil, nil
end

function App:PrepareFlight(character, humanoid, root)
    if self.EndRoundAttempt and self.EndRoundAttempt.Character == character and self.FlightCharacter == character then
        return
    end
    if self.FlightCharacter ~= character then
        self:ReleaseFlight(false)
        self.FlightCharacter, self.SavedAutoRotate = character, humanoid.AutoRotate
        self.SavedPlatformStand = humanoid.PlatformStand
        self.LastSurface = root.CFrame
    end
    for _, part in ipairs(character:QueryDescendants("BasePart")) do
        if self.Collision[part] == nil then self.Collision[part] = part.CanCollide end
        part.CanCollide = false
        if not self.Settings.TouchAssist then
            if self.TouchFlags[part] == nil then self.TouchFlags[part] = part.CanTouch end
            part.CanTouch = true
        end
    end
    humanoid.AutoRotate = false
    humanoid.PlatformStand = true
end

function App:RestoreAntiFling()
    for part, value in pairs(self.AntiFlingParts) do
        if part.Parent then pcall(function() part.CanCollide = value end) end
        self.AntiFlingParts[part] = nil
    end
    self.AntiFlingStable = nil
end

function App:UpdateAntiFling()
    if not self.Running or self.Unloading or not self.Settings.AntiFling then self:RestoreAntiFling(); return end
    local exempt = self.Flow.Phase == "Contact" and self.EndRoundAttempt and self.EndRoundAttempt.TargetCharacter
    local seen = {}
    for _, other in ipairs(Players:GetPlayers()) do
        local character = other ~= Player and other.Character
        if character and character:IsDescendantOf(workspace) then
            for _, part in ipairs(character:QueryDescendants("BasePart")) do
                seen[part] = true
                if character == exempt then
                    local original = self.AntiFlingParts[part]
                    if original ~= nil then part.CanCollide = original; self.AntiFlingParts[part] = nil end
                else
                    if self.AntiFlingParts[part] == nil then self.AntiFlingParts[part] = part.CanCollide end
                    if part.CanCollide then part.CanCollide = false end
                end
            end
        end
    end
    for part, original in pairs(self.AntiFlingParts) do
        if not seen[part] then
            if part.Parent then pcall(function() part.CanCollide = original end) end
            self.AntiFlingParts[part] = nil
        end
    end
end

function App:GuardLocalFling()
    if not self.Settings.AntiFling or self.Flow.Phase == "Contact" then self.AntiFlingStable = nil; return end
    local character, humanoid, root = self:GetCharacter()
    if not character or not humanoid or not root or root.Anchored or humanoid.Health <= 0
        or humanoid:GetState() == Enum.HumanoidStateType.Dead then self.AntiFlingStable = nil; return end
    local velocity = root.AssemblyLinearVelocity or Vector3.zero
    local speed = velocity.Magnitude
    local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    local spin = (root.AssemblyAngularVelocity or Vector3.zero).Magnitude
    local valid = finiteFrame(root.CFrame)
    if speed ~= speed or spin ~= spin or speed == math.huge or spin == math.huge
        or horizontal > 180 or velocity.Y > 180 or spin > 100 or not valid then
        local stable = self.AntiFlingStable
        self:CancelMove()
        self:ResetPickup()
        self.Target, self.WaitingPosition, self.Expected = nil, nil, nil
        if stable and stable.Character == character and stable.Map == self.Map and stable.Serial == self.RoundSerial
            and os.clock() - stable.At <= 2 then root.CFrame = stable.Frame end
        for _, part in ipairs(character:QueryDescendants("BasePart")) do
            part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        end
        self.FlingBlocks = (self.FlingBlocks or 0) + 1
    elseif valid and speed <= 80 and spin <= 50 then
        self.AntiFlingStable = {Character = character, Map = self.Map, Serial = self.RoundSerial, Frame = root.CFrame, At = os.clock()}
    end
end

function App:MovementState()
    if self.DeathEndRoundContext then return self:DeathEndRoundState() end
    local active, reason, character, humanoid, root = self:RoundState()
    if not active and reason == "Outside the active map" and self.EndRoundAttempt then
        character, humanoid, root = self:GetCharacter()
        if character == self.EndRoundAttempt.Character and root == self.EndRoundAttempt.Root and finiteFrame(root.CFrame) then
            return true, "Auto End Round contact", character, humanoid, root
        end
    end
    return active, reason, character, humanoid, root
end

function App:PhysicsTick()
    if not self.Running then return end
    self:UpdateAntiFling()
    if self:StepEndRoundRecovery() then return end
    if self:StepRoundStart(true) then return end
    self:GuardLocalFling()
    if not self.Settings.FarmEnabled or not self.FlightCharacter or os.clock() < self.PauseUntil then return end
    local active, _, character, humanoid, root = self:MovementState()
    if active and character == self.FlightCharacter then
        if self.EndRoundAttempt then return end
        self:PrepareFlight(character, humanoid, root)
    else
        self.Target = nil
        self:ReleaseFlight(false)
    end
end

function App:Move(root, position)
    if self.Flow.Owner == "EndRound" then return false end
    local distance = (position - root.Position).Magnitude
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    if distance <= 0.35 then
        self:CancelMove()
        root.CFrame = CFrame.new(position) * root.CFrame.Rotation
        self.Expected = position
        return true
    end
    local motion = self.Motion
    if not motion or motion.Root ~= root or (motion.Destination - position).Magnitude > 0.05
        or motion.Speed ~= self.Settings.TravelSpeed then
        self:CancelMove()
        local duration = math.max(0.05, distance / self.Settings.TravelSpeed)
        local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
            CFrame = CFrame.new(position) * root.CFrame.Rotation,
        })
        self.Motion = {Tween = tween, Root = root, Start = root.Position, Destination = position,
            Duration = duration, StartedAt = os.clock(), Speed = self.Settings.TravelSpeed}
        tween:Play()
    end
    self.Expected = root.Position
    return false
end

function App:SafePoint()
    if not self.Map then return nil end
    if self.SafeMap ~= self.Map or not self.SafeCFrame then
        local frame, size = self.Map:GetBoundingBox()
        local point = Vector3.new(frame.Position.X, frame.Position.Y + size.Y / 2 + 80, frame.Position.Z)
        self.SafeCFrame, self.SafeMap = CFrame.new(point), self.Map
        if self.SafePlatform then cleanup(function() self.SafePlatform:Destroy() end) end
        local platform = Instance.new("Part")
        platform.Name, platform.Size = "MM2Candy_SafePlatform", Vector3.new(14, 1, 14)
        platform.Anchored, platform.CanCollide, platform.CanTouch = true, true, false
        platform.Transparency, platform.Material = 0.55, Enum.Material.Neon
        platform.Color = Color3.fromRGB(255, 144, 55)
        platform.CFrame, platform.Parent = CFrame.new(point - Vector3.new(0, 3, 0)), workspace
        self.SafePlatform = platform
    end
    return self.SafeCFrame.Position
end

function App:Park(root, dt, status)
    self.HarvestPause = nil
    self:StopEndRound("Safe zone")
    self:CancelMove()
    self:ResetPickup()
    local point = self:SafePoint()
    if point then
        root.CFrame = CFrame.new(point) * root.CFrame.Rotation
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        self.Expected = point
    end
    self.Status = status or "Safe zone"
    self.Target = nil
    self.WaitingPosition = nil
end

function App:RoundTimerStarted()
    local timer = workspace:FindFirstChild("RoundTimerPart")
    local remaining = timer and timer:GetAttribute("Time")
    return type(remaining) == "number" and remaining > 0 and remaining < math.huge
end

function App:ArmRoundStart(excludedMap, entry)
    if not self.Settings.FarmEnabled or self.ReconnectPending or self.Unloading
        or (not excludedMap and self.StartCompletedMap == self.Map and self.Map ~= nil) then return end
    local guard = not excludedMap and self.StartGuard or nil
    guard = guard or {ExcludedMap = excludedMap}
    if type(entry) == "table" then guard.Entry = entry end
    self.StartGuard = guard
end

function App:OnRoundRoleSelected(role)
    if type(role) == "table" then role = role.SelectedRole end
    if role ~= "Innocent" and role ~= "Sheriff" and role ~= "Hero" and role ~= "Murderer"
        and role ~= "Survivor" and role ~= "Zombie" then return end
    if not self.Running or self:RoundTimerStarted() then return end
    self:ArmRoundStart()
    if self.StartGuard then self.StartGuard.ExcludedMap = nil end
end

function App:StepRoundStart(holdOnly)
    local guard = self.StartGuard
    if not guard then return false end
    if not self.Running or self.Unloading or not self.Settings.FarmEnabled or self.ReconnectPending
        or self.BagFull or self.DeathEndRoundContext or self.EndRoundAttempt or self.EndRoundCycle
        or os.clock() < self.PauseUntil then self.StartGuard = nil; return false end
    local map = self.Map
    if not map or map == guard.ExcludedMap or not map:IsDescendantOf(workspace) then return false end
    local character, humanoid, root = self:GetCharacter()
    local entry = RoundData.PlayerData and RoundData.PlayerData[Player.Name]
    if self:IsRoundParticipantAlive(entry) then guard.Entry = nil else entry = guard.Entry or entry end
    local role = entry and entry.Role
    local participant = role == "Innocent" or role == "Sheriff" or role == "Hero" or role == "Murderer"
        or role == "Survivor" or role == "Zombie"
    if not participant or not self:IsRoundParticipantAlive(entry) or not character or not humanoid or not root
        or not character:IsDescendantOf(workspace) or not humanoid:IsDescendantOf(character)
        or not root:IsDescendantOf(character) or root.Anchored or humanoid.Health <= 0
        or humanoid:GetState() == Enum.HumanoidStateType.Dead or not finiteFrame(root.CFrame)
        or (guard.Character and (guard.Character ~= character or guard.Root ~= root or guard.Map ~= map)) then
        if guard.Character then self.StartGuard = nil end
        return false
    end
    guard.Character, guard.Root, guard.Map = character, root, map
    self.DeathEligibleCharacter, self.DeathObservedRoundSerial = character, self.RoundSerial
    self:Transition("Starting", "Round start protection")
    self:PrepareFlight(character, humanoid, root)
    if not holdOnly and self:RoundState() then
        self:ScanCoins()
        self.NextScan = os.clock() + 0.75
        local coin = self:PickCoin(root)
        if coin then
            local position = self:CoinDestination(coin)
            self:Transition("Farming", "First candy after round start")
            self:CancelMove()
            self:ResetPickup()
            root.CFrame = CFrame.new(position) * root.CFrame.Rotation
            root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
            self.Target, self.Expected, self.AntiFlingStable = coin, position, nil
            self.ArrivedAt, self.ProgressAt, self.BestDistance = os.clock(), os.clock(), 0
            self.StartGuard, self.StartCompletedMap = nil, map
            self.LastStartTeleport = {Map = map, Serial = self.RoundSerial, Coin = coin, At = os.clock()}
            return false
        end
    end
    self:Park(root, 0, self:RoundTimerStarted() and "Safe zone: waiting for candies" or "Safe zone: waiting for round start")
    return true
end

function App:SetFarm(enabled)
    enabled = enabled == true
    self.StartGuard = nil
    if not enabled then self:CancelDeathEndRound(true) end
    self:CancelEndRoundSequence("Farm changed")
    self:CancelMove()
    self:ResetPickup()
    self.Settings.FarmEnabled = enabled
    self.Target, self.ManualPark, self.WaitingPosition = nil, false, nil
    self:ScheduleSave()
    if not enabled then
        self.DeathEligibleCharacter = nil
        self:ReleaseFlight(true)
        self.Status = "Disabled"
        self:Transition("Disabled", "Manual stop")
    elseif self.Map and not self:RoundTimerStarted() then
        self:ArmRoundStart()
    end
    if self.Controls.FarmEnabled and not self.Unloading then self.Controls.FarmEnabled:Set(enabled, true) end
end

function App:Set(key, value)
    if key ~= "FarmEnabled" and self.Settings[key] == value then return end
    if key == "TouchAssist" and value == true and (not self.TouchSupported or type(firetouchinterest) ~= "function") then
        self:DisableTouchAssist()
        return
    end
    if key == "TravelSpeed" or key == "UnderfloorDepth" or key == "TouchAssist" then
        self:CancelMove()
        self:ResetPickup()
        self.Target, self.WaitingPosition = nil, nil
        table.clear(self.Cooldowns)
    end
    if key == "FarmEnabled" then self:SetFarm(value) else self.Settings[key] = value end
    if key == "AutoEndRound" and not value then
        self:CancelDeathEndRound(true)
        self:CancelEndRoundSequence("Auto End Round disabled")
    end
    if key == "AntiFling" then self:UpdateAntiFling(); self.AntiFlingStable = nil end
    if key == "AutoReconnect" and not value then self:CancelReconnect() end
    if key == "TouchAssist" and value == true then self:RestoreTouchFlags() end
    if key == "WebhookURL" and self.Controls.WebhookURL and not self.Unloading then
        self.Controls.WebhookURL:Set(value, true)
    end
    self:ScheduleSave()
end

function App:ResetRound()
    self.StartGuard = nil
    self.AntiFlingStable = nil
    self:CancelDeathEndRound(false)
    self.DeathBootstrapAllowed, self.DeathObservedRoundSerial = false, nil
    self:CancelEndRoundSequence("New round")
    self.EndRoundRetryAt, self.EndRoundTries, self.EndRoundResult = 0, 0, nil
    self:CancelMove()
    self:ResetPickup()
    self.RoundSerial = self.RoundSerial + 1
    self.BagCount, self.BagCapacity, self.BagFull = 0, nil, false
    self.AcknowledgedCount = 0
    self.FullHandled, self.ResetRequested, self.DeathRecorded = false, false, false
    self.Target, self.ManualPark, self.PauseUntil, self.WaitingPosition = nil, false, 0, nil
    self.LastSurface = nil
    self.DeathEligibleCharacter = nil
    table.clear(self.Cooldowns)
end

function App:EndRound()
    self.StartGuard = nil
    if self.EndRoundCycle then
        if not self:ObserveEndRound(self.EndRoundCycle) then self.EndRoundCycle.Outcome = "RoundEnded" end
        self.LastEndRoundReport = table.clone(self.EndRoundCycle)
    end
    self.AntiFlingStable = nil
    self:CancelDeathEndRound(false)
    self:ResetPickup()
    self.RoundBlocked = true
    self.Target, self.ManualPark = nil, false
    self.DeathEligibleCharacter = nil
    self:ReleaseFlight(false)
    self:CancelEndRoundSequence("Round ended")
    self:Transition("WaitingRound", "Round ended")
end

local RouteCandidateLimit, RoutePasses, RouteEpsilon = 32, 2, 0.0001

function App:CoinDestination(coin)
    return self.Settings.TouchAssist
        and coin.Position - Vector3.new(0, self.Settings.UnderfloorDepth, 0) or coin.Position
end

function App:PlanCoinRoute(root, excludedCoin)
    local candidates, seen = {}, {}
    local now, origin = os.clock(), root.Position
    for order, coin in ipairs(self.Coins) do
        if not seen[coin] then
            seen[coin] = true
            if coin ~= excludedCoin and self:CoinVisual(coin) and (self.Cooldowns[coin] or 0) <= now then
                local position = self:CoinDestination(coin)
                local distance = (position - origin).Magnitude
                if distance == distance and distance < math.huge
                    and (#candidates < RouteCandidateLimit or distance < candidates[#candidates].StartDistance) then
                    local insertAt = #candidates + 1
                    while insertAt > 1 and distance < candidates[insertAt - 1].StartDistance do insertAt = insertAt - 1 end
                    table.insert(candidates, insertAt, {Coin = coin, Position = position, StartDistance = distance, Order = order})
                    if #candidates > RouteCandidateLimit then table.remove(candidates) end
                end
            end
        end
    end
    local route, used, distances = {}, {}, {}
    for index, candidate in ipairs(candidates) do
        candidate.RouteIndex = index
        distances[index] = {[index] = 0}
    end
    for first = 1, #candidates - 1 do
        for last = first + 1, #candidates do
            local distance = (candidates[first].Position - candidates[last].Position).Magnitude
            distances[first][last], distances[last][first] = distance, distance
        end
    end
    local function distance(first, last)
        return first and distances[first.RouteIndex][last.RouteIndex] or last.StartDistance
    end
    local previous, greedyLength = nil, 0
    for _ = 1, #candidates do
        local best, bestDistance
        for _, candidate in ipairs(candidates) do
            if not used[candidate] then
                local cost = distance(previous, candidate)
                if not bestDistance or cost < bestDistance or (cost == bestDistance and candidate.Order < best.Order) then
                    best, bestDistance = candidate, cost
                end
            end
        end
        route[#route + 1], used[best] = best, true
        greedyLength, previous = greedyLength + bestDistance, best
    end
    local nearestDistance = candidates[1] and candidates[1].StartDistance
    local firstLimit, swaps = nearestDistance and nearestDistance * 1.25 or 0, 0
    for _ = 1, RoutePasses do
        local improved = false
        for first = 1, #route - 1 do
            for last = first + 1, #route do
                if first > 1 or route[last].StartDistance <= firstLimit + RouteEpsilon then
                    local before, after = route[first - 1], route[last + 1]
                    local oldCost = distance(before, route[first]) + (after and distance(route[last], after) or 0)
                    local newCost = distance(before, route[last]) + (after and distance(route[first], after) or 0)
                    if newCost + RouteEpsilon < oldCost then
                        local left, right = first, last
                        while left < right do
                            route[left], route[right] = route[right], route[left]
                            left, right = left + 1, right - 1
                        end
                        swaps, improved = swaps + 1, true
                    end
                end
            end
        end
        if not improved then break end
    end
    local length = 0
    previous = nil
    for _, candidate in ipairs(route) do
        length, previous = length + distance(previous, candidate), candidate
    end
    self.LastCoinRoute = {Candidates = #route, GreedyLength = greedyLength, Length = length,
        FirstDistance = route[1] and route[1].StartDistance, NearestDistance = nearestDistance, Swaps = swaps}
    return route
end

function App:PickCoin(root)
    local route = self:PlanCoinRoute(root)
    return route[1] and route[1].Coin
end

function App:FindMurderer()
    local data = RoundData.PlayerData
    local own = data and data[Player.Name]
    if not data or (not own and not self:DeathEndRoundAllowed()) or (own and own.Role == "Murderer") then return nil end
    local target, character, humanoid, root
    for _, other in ipairs(Players:GetPlayers()) do
        local entry = data[other.Name]
        local model = other.Character
        local health = model and model:FindFirstChildOfClass("Humanoid")
        local part = model and model:FindFirstChild("HumanoidRootPart")
        if other ~= Player and entry and entry.Role == "Murderer" and entry.Dead == false
            and entry.Killed ~= true and other:GetAttribute("Alive") == true
            and model and model:IsDescendantOf(workspace) and health and health.Health > 0
            and health:GetState() ~= Enum.HumanoidStateType.Dead and part and not part.Anchored then
            if target then return nil end
            target, character, humanoid, root = other, model, health, part
        end
    end
    return target, character, humanoid, root
end

function App:ObserveEndRound(cycle)
    if not cycle or cycle.Serial ~= self.RoundSerial or cycle.Map ~= self.Map then return false end
    local entry = cycle.Player and RoundData.PlayerData and RoundData.PlayerData[cycle.Player.Name]
    if entry and entry.Role == "Murderer" and (entry.Dead == true or entry.Killed == true) then
        cycle.Confirmed, cycle.Outcome = true, "TargetDead"
        cycle.FirstAttemptConfirmed = cycle.Attempts == 1
        self.LastEndRoundReport = table.clone(cycle)
        return true
    end
    return cycle.Confirmed == true
end

local function restoreEndRound(attempt, label, action)
    local ok, err = pcall(action)
    if not ok then
        attempt.CleanupErrors = attempt.CleanupErrors or {}
        table.insert(attempt.CleanupErrors, label .. ": " .. tostring(err))
    end
end

local function placeEndRoundCharacter(character, root, pose)
    if character.PrimaryPart == root then
        character:SetPrimaryPartCFrame(pose)
    else
        local pivot = root.CFrame:ToObjectSpace(character:GetPivot())
        character:PivotTo(pose * pivot)
    end
end

function App:RestoreEndRoundPose(attempt)
    local character, humanoid, root = attempt.Character, attempt.Humanoid, attempt.Root
    local alive = Player.Character == character and root:IsDescendantOf(character) and humanoid:IsDescendantOf(character)
        and humanoid.Health > 0
    if alive then
        restoreEndRound(attempt, "position", function()
            placeEndRoundCharacter(character, root, attempt.ReturnCFrame)
        end)
    end
    local ok, parts = pcall(function() return character:QueryDescendants("BasePart") end)
    if ok then
        for _, part in ipairs(parts) do
            restoreEndRound(attempt, "linear_velocity", function() part.AssemblyLinearVelocity = Vector3.zero end)
            restoreEndRound(attempt, "angular_velocity", function() part.AssemblyAngularVelocity = Vector3.zero end)
        end
    elseif root:IsDescendantOf(character) then
        restoreEndRound(attempt, "root_linear_velocity", function() root.AssemblyLinearVelocity = Vector3.zero end)
        restoreEndRound(attempt, "root_angular_velocity", function() root.AssemblyAngularVelocity = Vector3.zero end)
    end
    if alive then restoreEndRound(attempt, "getting_up", function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
    return alive
end

function App:StepEndRoundRecovery()
    local recovery = self.EndRoundRecovery
    if not recovery then return false end
    if not self.Running or self.Unloading or Player.Character ~= recovery.Attempt.Character
        or self.Map ~= recovery.Attempt.Map or self.RoundSerial ~= recovery.Attempt.Serial
        or self.Flow.Phase ~= "Confirming" or self.Flow.Owner ~= "EndRound" then
        self.EndRoundRecovery = nil; return false
    end
    local alive = self:RestoreEndRoundPose(recovery.Attempt)
    recovery.Remaining = recovery.Remaining - 1
    if not alive or recovery.Remaining <= 0 then self.EndRoundRecovery = nil end
    return alive
end

function App:StopEndRound(reason)
    local attempt = self.EndRoundAttempt
    if not attempt then self.EndRoundRecovery = nil; return end
    self.EndRoundAttempt, self.EndRoundRecovery = nil, nil
    restoreEndRound(attempt, "velocity_controller_force", function()
        if attempt.VelocityController then attempt.VelocityController.MaxForce = Vector3.zero end
    end)
    restoreEndRound(attempt, "velocity_controller_speed", function()
        if attempt.VelocityController then attempt.VelocityController.Velocity = Vector3.zero end
    end)
    restoreEndRound(attempt, "velocity_controller", function()
        if attempt.VelocityController then attempt.VelocityController:Destroy() end
    end)
    restoreEndRound(attempt, "kill_plane", function()
        if attempt.FallenHeightSaved then workspace.FallenPartsDestroyHeight = attempt.FallenHeight end
    end)
    restoreEndRound(attempt, "seated", function()
        if attempt.SeatedSaved and attempt.Humanoid.Parent then
            attempt.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, attempt.SeatedEnabled)
        end
    end)
    restoreEndRound(attempt, "auto_rotate", function()
        if attempt.PostureSaved and attempt.Humanoid.Parent then attempt.Humanoid.AutoRotate = attempt.AutoRotate end
    end)
    restoreEndRound(attempt, "platform_stand", function()
        if attempt.PostureSaved and attempt.Humanoid.Parent then attempt.Humanoid.PlatformStand = attempt.PlatformStand end
    end)
    restoreEndRound(attempt, "camera", function()
        local camera = attempt.Camera
        if attempt.CameraSaved and camera and camera.Parent then
            local currentHumanoid = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
            local subject = attempt.CameraSubject
            camera.CameraSubject = subject and subject.Parent and subject or currentHumanoid
        end
    end)
    for part, saved in pairs(attempt.Parts) do
        restoreEndRound(attempt, "collision", function() if part.Parent then part.CanCollide = saved.CanCollide end end)
        restoreEndRound(attempt, "collision_group", function() if part.Parent then part.CollisionGroup = saved.CollisionGroup end end)
    end
    local recover = attempt.SetupStarted and self:RestoreEndRoundPose(attempt)
    local now, cycle = os.clock(), self.EndRoundCycle
    self.EndRoundResult = reason
    self.LastEndRoundAttempt = {Reason = reason, PhysicsSteps = attempt.PhysicsSteps or 0,
        Duration = attempt.SpinStarted and now - attempt.SpinStarted or 0,
        ClosestDistance = attempt.ClosestDistance, ContactPart = attempt.ContactPart and attempt.ContactPart.Name,
        PrePhysicsDistance = attempt.PrePhysicsDistance,
        ContactObserved = attempt.ContactObserved == true, ProximityObserved = attempt.ProximityObserved == true,
        MaxTargetSpeed = attempt.MaxTargetSpeed or 0, MaxTargetDisplacement = attempt.MaxTargetDisplacement or 0,
        SampleIndex = attempt.SampleIndex, Index = attempt.Index, CleanupErrors = attempt.CleanupErrors}
    self.EndRoundRetryAt = now + 4
    if cycle then
        cycle.ConfirmUntil = self.EndRoundRetryAt
        cycle.LastAttempt = self.LastEndRoundAttempt
        cycle.MaxTargetSpeed = math.max(cycle.MaxTargetSpeed or 0, attempt.MaxTargetSpeed or 0)
        self.LastEndRoundReport = table.clone(cycle)
    end
    self:CancelMove()
    self.Expected, self.AntiFlingStable = nil, nil
    self:Transition("Confirming", reason)
    self:UpdateAntiFling()
    if recover and self.Running and not self.Unloading then self.EndRoundRecovery = {Attempt = attempt, Remaining = 4} end
end

function App:FlingContactPart(character, root)
    local head = character:FindFirstChild("Head")
    return head and head:IsA("BasePart") and (head.Position - root.Position).Magnitude > 5 and head or root
end

function App:PauseForCorrection()
    self.StartGuard = nil
    self.Stats.Corrections = self.Stats.Corrections + 1
    self.PauseUntil, self.Target = os.clock() + 8, nil
    self:ReleaseFlight(false)
    self:Transition("Cooldown", "Movement interrupted")
    self.Status = "Movement correction: retrying in 8 seconds"
    if os.clock() >= (self.NextCorrectionNotice or 0) then
        self.NextCorrectionNotice = os.clock() + 30
        self:Notify("Farm retrying", "Movement was interrupted. Auto Farm will resume in 8 seconds.", "Warning")
    end
end

local ContactSeconds = 2

function App:ApplyEndRoundPhysics(simulationStep, expectedAttempt)
    local attempt, cycle, flow = self.EndRoundAttempt, self.EndRoundCycle, self.Flow
    if not attempt or not simulationStep or (expectedAttempt and expectedAttempt ~= attempt) then return end
    local now = os.clock()
    local target, character, targetHumanoid, targetRoot = self:FindMurderer()
    if not cycle or flow.Phase ~= "Contact" or flow.Owner ~= "EndRound" or attempt.FlowEpoch ~= flow.Epoch
        or not self.Settings.AutoEndRound or not self.Settings.FarmEnabled
        or (not self.BagFull and not self:DeathEndRoundState()) or not self:RoundOngoing()
        or attempt.Serial ~= self.RoundSerial or attempt.Map ~= self.Map or Player.Character ~= attempt.Character
        or target ~= attempt.Player or character ~= attempt.TargetCharacter or targetRoot ~= attempt.TargetRoot
        or targetHumanoid ~= attempt.TargetHumanoid or not attempt.Humanoid.Parent or attempt.Humanoid.Health <= 0
        or attempt.Humanoid:GetState() == Enum.HumanoidStateType.Dead or attempt.Humanoid.Sit
        or not attempt.Root:IsDescendantOf(attempt.Character) or attempt.Root.Anchored or targetHumanoid.Sit then
        self:StopEndRound("Contact context changed"); return
    end
    if not finiteFrame(attempt.Root.CFrame) or not finiteFrame(targetRoot.CFrame) then self:StopEndRound("Invalid transform"); return end
    local collider = attempt.TargetPart
    if not collider.Parent or not collider:IsDescendantOf(character) or collider.Anchored or not finiteFrame(collider.CFrame) then
        self:StopEndRound("No valid target contact part"); return
    end
    local velocity = collider.Velocity
    local speed = velocity.Magnitude
    if speed ~= speed or speed == math.huge then self:StopEndRound("Invalid target velocity"); return end
    attempt.MaxTargetSpeed = math.max(attempt.MaxTargetSpeed or speed, speed)
    attempt.MaxTargetDisplacement = math.max(attempt.MaxTargetDisplacement or 0, (targetRoot.Position - attempt.InitialTargetPosition).Magnitude)
    if attempt.BatchFinished then
        attempt.BatchFinished = false
        if speed > 500 then
            cycle.MotionObserved = true
            self:StopEndRound("Target motion observed; awaiting server confirmation"); return
        end
    end
    if now >= attempt.Deadline then self:StopEndRound("Contact window elapsed"); return end
    local offset = targetRoot.Position - self.BoundsFrame.Position
    if math.abs(offset.X) > self.BoundsSize.X / 2 + 40 or math.abs(offset.Z) > self.BoundsSize.Z / 2 + 40
        or math.abs(offset.Y) > self.BoundsSize.Y / 2 + 100 then self:StopEndRound("Target outside map"); return end
    if not attempt.SpinStarted then
        attempt.AutoRotate, attempt.PlatformStand = attempt.Humanoid.AutoRotate, attempt.Humanoid.PlatformStand
        attempt.PostureSaved = true
        self:RestoreCollision()
        if self.SavedAutoRotate ~= nil then attempt.Humanoid.AutoRotate = self.SavedAutoRotate end
        attempt.Humanoid.PlatformStand = self.SavedPlatformStand == true
        if not attempt.Humanoid.PlatformStand then attempt.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
        attempt.Camera = workspace.CurrentCamera
        attempt.CameraSubject = attempt.Camera and attempt.Camera.CameraSubject
        attempt.CameraSaved = true
        attempt.FallenHeight = workspace.FallenPartsDestroyHeight
        attempt.FallenHeightSaved = true
        attempt.SeatedEnabled = attempt.Humanoid:GetStateEnabled(Enum.HumanoidStateType.Seated)
        attempt.SeatedSaved, attempt.SetupStarted = true, true
        if attempt.Camera then
            local head = character:FindFirstChild("Head")
            attempt.Camera.CameraSubject = head or targetHumanoid
        end
        workspace.FallenPartsDestroyHeight = 0 / 0
        attempt.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        local controller = Instance.new("BodyVelocity")
        attempt.VelocityController = controller
        controller.Name = "TeleportFlingTemporaryVelocity"
        controller.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        controller.Velocity = Vector3.new(9e8, 9e8, 9e8)
        controller.Parent = attempt.Root
        attempt.SpinStarted, attempt.Deadline = now, now + ContactSeconds
        cycle.Attempts = cycle.Attempts + 1
        attempt.Index = cycle.Attempts
        self.EndRoundTries = (self.EndRoundTries or 0) + 1
    end
    local observedDistance = (attempt.Root.Position - collider.Position).Magnitude
    attempt.PrePhysicsDistance = math.min(attempt.PrePhysicsDistance or math.huge, observedDistance)
    local overlapRadius = math.clamp((attempt.Root.Size.Magnitude + collider.Size.Magnitude) * 0.5, 1, 8)
    attempt.ProximityObserved = attempt.ProximityObserved or observedDistance <= overlapRadius
    local ok, touching = pcall(function() return attempt.Root:GetTouchingParts() end)
    if ok then
        for _, part in ipairs(touching) do
            if part:IsDescendantOf(character) then attempt.ContactObserved = true; break end
        end
    end
    local sample = (attempt.SampleIndex or 0) + 1
    if not attempt.Offsets or sample > #attempt.Offsets then
        sample = 1
        attempt.Rotations = nil
        if speed < 50 then
            attempt.Angle = (attempt.Angle or 0) + 100
            local lead = targetHumanoid.MoveDirection * speed / 1.25
            attempt.Offsets = {
                CFrame.new(0, 1.5, 0) + lead, CFrame.new(0, -1.5, 0) + lead,
                CFrame.new(2.25, 1.5, -2.25) + lead, CFrame.new(-2.25, -1.5, 2.25) + lead,
                CFrame.new(0, 1.5, 0) + targetHumanoid.MoveDirection,
                CFrame.new(0, -1.5, 0) + targetHumanoid.MoveDirection,
            }
        else
            local walk = targetHumanoid.WalkSpeed
            local reach = targetRoot.Velocity.Magnitude / 1.25
            attempt.Offsets = {
                CFrame.new(0, 1.5, walk), CFrame.new(0, -1.5, -walk),
                CFrame.new(0, 1.5, walk), CFrame.new(0, 1.5, reach),
                CFrame.new(0, -1.5, -reach), CFrame.new(0, 1.5, reach),
                CFrame.new(0, -1.5, 0), CFrame.new(0, -1.5, 0),
                CFrame.new(0, -1.5, 0), CFrame.new(0, -1.5, 0),
            }
            attempt.Rotations = {90, 0, 90, 90, 0, 90, 90, 0, -90, 0}
        end
    end
    local pitch = math.rad(attempt.Rotations and attempt.Rotations[sample] or attempt.Angle)
    local goal = CFrame.new(collider.Position) * attempt.Offsets[sample] * CFrame.Angles(pitch, 0, 0)
    if not finiteFrame(goal) then self:StopEndRound("Invalid contact pose"); return end
    placeEndRoundCharacter(attempt.Character, attempt.Root, goal)
    local placedDistance = (attempt.Root.Position - collider.Position).Magnitude
    attempt.ClosestDistance = math.min(attempt.ClosestDistance or math.huge, placedDistance)
    attempt.Root.Velocity = Vector3.new(9e7, 9e8, 9e7)
    attempt.Root.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
    attempt.PhysicsSteps = attempt.PhysicsSteps + 1
    attempt.ContactPart, attempt.OwnContactPart, attempt.SampleIndex = collider, attempt.Root, sample
    attempt.BatchFinished = sample == #attempt.Offsets
    self.Expected = nil
end

function App:RunEndRoundWorker(attempt)
    if self.EndRoundAttempt ~= attempt or attempt.WorkerStarted then return end
    attempt.WorkerStarted = true
    attempt.Worker = task.spawn(function()
        local ok, err = xpcall(function()
            while self.Running and self.EndRoundAttempt == attempt do
                self:ApplyEndRoundPhysics(true, attempt)
                if self.EndRoundAttempt ~= attempt then break end
                task.wait()
            end
        end, function(failure) return tostring(failure) end)
        if not ok then
            attempt.Error = tostring(err)
            if self.EndRoundAttempt == attempt then
                self.LastError = tostring(err)
                self:StopEndRound("Fling error")
                self:SetFarm(false)
                self:Notify("Farm stopped", "Fling error; details are in the executor console.", "Warning")
                warn("[MM2 Candy] Fling: " .. tostring(err))
            end
        elseif self.EndRoundAttempt == attempt then
            self:StopEndRound("Fling cancelled")
        end
    end)
end

function App:TryEndRound(character, root)
    local own = RoundData.PlayerData and RoundData.PlayerData[Player.Name]
    if not self.Settings.AutoEndRound or (not own and not self:DeathEndRoundAllowed()) or (own and own.Role == "Murderer") then
        self:CancelEndRoundSequence("Local murderer / disabled"); return false
    end
    local now, cycle = os.clock(), self.EndRoundCycle
    local prefix = self.DeathEndRoundContext and "After death: " or "Bag full: "
    if self.EndRoundRecovery then self.Status = prefix .. "restoring position"; return true end
    if cycle and self:ObserveEndRound(cycle) then
        self:StopEndRound("Server confirmed murderer death")
        self:Transition("Confirming", "TargetDead")
        self:Park(root, 0, prefix .. "murderer death confirmed; waiting for round end")
        return true
    end
    local target, targetCharacter, targetHumanoid, targetRoot = self:FindMurderer()
    if cycle and (cycle.Serial ~= self.RoundSerial or cycle.Map ~= self.Map
        or (target and (target ~= cycle.Player or targetCharacter ~= cycle.TargetCharacter))) then
        self:CancelEndRoundSequence("Target context changed"); cycle = nil
    end
    if not cycle then
        cycle = {Serial = self.RoundSerial, Map = self.Map, Trigger = self.DeathEndRoundContext and "Death" or "BagFull",
            Player = target, TargetCharacter = targetCharacter, Attempts = 0, ConfirmUntil = 0, Outcome = "Pending"}
        self.EndRoundCycle = cycle
    elseif not cycle.Player and target then cycle.Player, cycle.TargetCharacter = target, targetCharacter end
    if not target then
        self:StopEndRound("No live murderer")
        self:Transition("Confirming", "Waiting for target / round end")
        self:Park(root, 0, prefix .. "waiting for round end in safe zone"); return true
    end
    if self.EndRoundAttempt then
        local attempt = self.EndRoundAttempt
        if attempt.Root ~= root or attempt.Character ~= character or attempt.TargetRoot ~= targetRoot then
            self:StopEndRound("Character changed")
        elseif now >= attempt.Deadline then self:StopEndRound("Contact window elapsed")
        else self.Status = prefix .. "flinging murderer"; return true end
    end
    if self.EndRoundRecovery then self.Status = prefix .. "restoring position"; return true end
    if now < cycle.ConfirmUntil then
        self:Transition("Confirming", "Waiting for server result")
        self:Park(root, 0, prefix .. "waiting for murderer death in safe zone"); return true
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Sit or root.Anchored or targetHumanoid.Sit or not finiteFrame(targetRoot.CFrame) then
        self:Transition("Confirming", "Invalid target")
        self:Park(root, 0, prefix .. "waiting for a valid murderer"); return true
    end
    local offset = targetRoot.Position - self.BoundsFrame.Position
    local targetSpeed = (targetRoot.AssemblyLinearVelocity or Vector3.zero).Magnitude
    if math.abs(offset.X) > self.BoundsSize.X / 2 + 40 or math.abs(offset.Z) > self.BoundsSize.Z / 2 + 40
        or math.abs(offset.Y) > self.BoundsSize.Y / 2 + 100 or targetSpeed ~= targetSpeed or targetSpeed > 180 then
        self:Transition("Confirming", "Waiting for target to settle")
        self:Park(root, 0, prefix .. "waiting for murderer in safe zone"); return true
    end
    self:Transition("Contact", "Auto End Round")
    local attempt = {Player = target, TargetCharacter = targetCharacter, TargetRoot = targetRoot,
        TargetHumanoid = targetHumanoid, TargetPart = self:FlingContactPart(targetCharacter, targetRoot),
        Character = character, Humanoid = humanoid, Root = root, ReturnCFrame = root.CFrame,
        Map = self.Map, Serial = self.RoundSerial, FlowEpoch = self.Flow.Epoch,
        Parts = {}, CleanupErrors = {}, CreatedAt = now, HardDeadline = now + 2.2, Deadline = now + 2.2, PhysicsSteps = 0,
        InitialTargetPosition = targetRoot.Position, InitialSpeed = targetSpeed}
    self.EndRoundAttempt, self.AntiFlingStable = attempt, nil
    self:UpdateAntiFling()
    self.Status = prefix .. "preparing contact"
    self:RunEndRoundWorker(attempt)
    return true
end

function App:Tick(dt)
    if not self.Running then return end
    if self.ReconnectPending then
        self:Transition("Reconnecting", self.ReconnectPending.Reason)
        self.Status = self.ReconnectStatus; return
    end
    if self.Settings.TouchAssist and (not self.TouchSupported or type(firetouchinterest) ~= "function") then self:DisableTouchAssist() end
    local now = os.clock()
    if now >= self.NextRound then
        self.NextRound = now + 0.25
        local map = self:GetMap()
        if map ~= self.Map then
            local startGuard = self.StartGuard
            self:ReleaseFlight(false)
            self.Map = map
            self:ResetRound()
            if startGuard then
                startGuard.Character, startGuard.Root, startGuard.Map = nil, nil, nil
                self.StartGuard = startGuard
            elseif map and not self:RoundTimerStarted() then self:ArmRoundStart() end
            self.Coins, self.NextScan = {}, 0
            if self.SafePlatform then cleanup(function() self.SafePlatform:Destroy() end); self.SafePlatform = nil end
            self.SafeCFrame, self.SafeMap = nil, nil
        end
    end
    if not self.Settings.FarmEnabled then self:Transition("Disabled", "Auto Farm off"); self.Status = "Disabled"; return end
    self.ActiveElapsed = self.ActiveElapsed + dt
    if self:StepRoundStart(false) then return end
    if self.DeathEndRoundContext and not self:DeathEndRoundAllowed() then self:CancelDeathEndRound(false) end
    local active, reason, character, humanoid, root = self:MovementState()
    if not active then self:QueueDeathEndRound() end
    local afterDeath = self.DeathEndRoundContext ~= nil
    if afterDeath then active, reason, character, humanoid, root = self:DeathEndRoundState() end
    if not active then
        if reason ~= "Dead / respawning" and not afterDeath then self.DeathEligibleCharacter = nil end
        self:ReleaseFlight(false)
        self:Transition(afterDeath and "WaitRespawn" or "WaitingRound", reason)
        self.Status = reason; return
    end
    if afterDeath then
        local context = self.DeathEndRoundContext
        if context.ControlCharacter ~= character then
            self:ReleaseFlight(false)
            context.ControlCharacter, context.ReturnCFrame = character, root.CFrame
        end
    else
        self.DeathEligibleCharacter, self.DeathObservedRoundSerial = character, self.RoundSerial
        if self.CountedRoundSerial ~= self.RoundSerial then
            self.CountedRoundSerial = self.RoundSerial
            self.Stats.Rounds = self.Stats.Rounds + 1
        end
    end
    if now < self.PauseUntil then self:Transition("Cooldown", "Movement interrupted"); self.Status = "Movement correction: cooling down"; return end
    if afterDeath or self.BagFull then
        if self.BagFull and not afterDeath and not self.FullHandled then
            self.FullHandled = true
            self.Stats.Bags = self.Stats.Bags + 1
            if self.Webhook and self.Settings.WebhookOnFull then self.Webhook:Queue("Candy bag full") end
        end
        self:PrepareFlight(character, humanoid, root)
        if self:TryEndRound(character, root) then return end
        self:Transition("Holding", "Full bag fallback")
        if not afterDeath and self.Settings.AutoReset then
            self.Status = "Bag full: resetting"
            if not self.ResetRequested then
                self.ResetRequested = true
                self:ReleaseFlight(false)
                humanoid.Health = 0
                humanoid:ChangeState(Enum.HumanoidStateType.Dead)
            end
        else self:Park(root, dt, "Bag full: waiting in safe zone") end
        return
    end
    if self.EndRoundCycle or self.EndRoundAttempt then self:CancelEndRoundSequence("Candy farming resumed") end
    self:Transition("Farming", "Candy collection")
    local expected = self.Expected
    if self.Motion and self.Motion.Root == root then
        local motion = self.Motion
        local alpha = math.clamp((now - motion.StartedAt) / motion.Duration, 0, 1)
        expected = motion.Start + (motion.Destination - motion.Start) * alpha
    end
    if expected and (root.Position - expected).Magnitude > 14 then self:PauseForCorrection(); return end
    self:PrepareFlight(character, humanoid, root)
    self:StepCandy(dt, root)
end

function App:StepCandy(dt, root)
    local now = os.clock()
    if self.ManualPark then self:Park(root, dt, "Safe zone: resume farm to continue"); return end
    if now >= self.NextScan then
        self.NextScan = now + 0.75
        self:ScanCoins()
    end
    local pause = self.HarvestPause
    if pause then
        if pause.Root ~= root or pause.Character ~= Player.Character or pause.Map ~= self.Map
            or pause.Serial ~= self.RoundSerial then
            self.HarvestPause, self.NextScan = nil, 0
            self:CancelMove()
        else
            self:UpdateHarvestPause(pause, root)
            if now >= pause.Until then
                self:ScanCoins()
                self.NextScan = now + 0.75
                self:UpdateHarvestPause(pause, root, true)
            end
            if now < pause.Until then
                self:Move(root, pause.Position)
                self.Status = string.format("Collected: next flight in %.1fs", pause.Until - now)
                return
            end
            self.HarvestPause = nil
            self:CancelMove()
        end
    end
    local target = self.Target
    if target and not self:CoinVisual(target) then
        self:CancelMove()
        self:ResetPickup()
        self.Target, target = nil, nil
    end
    if not target then
        self:ResetPickup()
        target = self:PickCoin(root)
        self.Target, self.ArrivedAt, self.TouchSent = target, nil, false
        self.ProgressAt, self.BestDistance = now, nil
    end
    if not target then
        self.WaitingPosition = self.WaitingPosition or root.Position
        self:Move(root, self.WaitingPosition)
        self.Status = "Waiting for visible candies"
        return
    end
    self.WaitingPosition = nil
    local position = self:CoinDestination(target)
    local distance = (position - root.Position).Magnitude
    if distance > 0.7 and self.ArrivedAt then self:ResetPickup() end
    if not self.BestDistance or distance < self.BestDistance - 1 then
        self.BestDistance, self.ProgressAt = distance, now
    elseif not self.ArrivedAt and now - (self.ProgressAt or now) > 3 then
        self.Cooldowns[target], self.Target = now + 20, nil
        self.Status = "Blocked route: choosing another candy"
        return
    end
    local arrived = self:Move(root, position)
    self.Status = arrived and "Collecting candy" or "Flying to candy"
    if arrived then
        self.LastSurface = CFrame.new(target.Position + Vector3.new(0, 3, 0))
        self.ArrivedAt = self.ArrivedAt or now
        if self.TouchContact and now >= self.TouchContact.EndAt then
            self:FinishTouch()
            if self.ArrivedAt == nil then return end
        end
        local touchReady = now - self.ArrivedAt >= 0.15 and (self.TouchAttempts or 0) < 3
            and now >= (self.NextTouchAt or 0) and not self.TouchContact
        if touchReady
            and self.Settings.TouchAssist and type(firetouchinterest) == "function"
            and self:RoundState() and not self.BagFull and self:CoinVisual(target)
            and (root.Position - target.Position).Magnitude <= 7 then
            self.TouchSent = true
            self.TouchAttempts = (self.TouchAttempts or 0) + 1
            self.NextTouchAt = now + 0.4
            local ok, err = pcall(firetouchinterest, root, target, 0)
            if ok then
                self.TouchContact = {Root = root, Coin = target, EndAt = now + 0.06}
            else self:DisableTouchAssist(err); return end
        end
        if now - self.ArrivedAt > 1.8 then
            self:ResetPickup()
            self.Cooldowns[target] = now + 8
            self.Target = nil
        end
    end
end

function App:Unload()
    if not self.Running then return end
    self.Unloading = true
    self:CancelReconnect()
    self:FinishTouch()
    self.Settings.WebhookURL = pendingWebhook(self) or self.Settings.WebhookURL
    self:SaveState()
    self:SetFarm(false)
    self.Running = false
    self:RestoreAntiFling()
    if self.Webhook then self.Webhook:Close() end
    for _, connection in ipairs(self.Connections) do pcall(function() connection:Disconnect() end) end
    table.clear(self.Connections)
    if self.SafePlatform then cleanup(function() self.SafePlatform:Destroy() end) end
    if self.Window and not self.Window._destroyed then cleanup(function() self.Window:Destroy() end) end
    self.Unloaded = true
    if Environment[Key] == self then Environment[Key] = nil end
end

local function createWebhook(App)
    local HttpService = game:GetService("HttpService")
    local requestFn = (type(request) == "function" and request)
        or (type(http_request) == "function" and http_request)
        or (type(syn) == "table" and type(syn.request) == "function" and syn.request)
        or (type(http) == "table" and type(http.request) == "function" and http.request)
        or (type(fluxus) == "table" and type(fluxus.request) == "function" and fluxus.request)
    local Webhook = {Status = requestFn and "Off" or "HTTP unavailable", Sent = 0, Failed = 0}
    local pending, closed, busy, generation = {}, false, false, 0
    local lastPeriodic = os.clock()
    local hosts = { ["discord.com"] = true, ["discordapp.com"] = true,
        ["canary.discord.com"] = true, ["ptb.discord.com"] = true }

    local function target()
        local url = tostring(App.Settings.WebhookURL or ""):match("^%s*(.-)%s*$")
        local host, path = url:match("^https://([^/]+)(/.*)$")
        if not host or not hosts[host:lower()] then return nil end
        if not path:match("^/api/webhooks/%d+/[%w_%-]+$") then return nil end
        return url
    end

    local function active()
        return not closed and App.Running == true
    end

    local function number(value)
        value = tonumber(value)
        return value and value == value and value > -math.huge and value < math.huge and value or 0
    end

    local function integer(value)
        return tostring(math.floor(math.max(0, number(value))))
    end

    local function text(value, limit)
        return tostring(value or "Unknown"):sub(1, limit or 1000)
    end

    local function payload(reason)
        local snapshot = App:Snapshot()
        local elapsed = math.max(0, number(snapshot.Elapsed))
        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor(elapsed / 60) % 60
        local seconds = math.floor(elapsed) % 60
        local playerName = App.Player and App.Player.Name or "Unknown"
        return HttpService:JSONEncode({
            allowed_mentions = {parse = {}},
            embeds = {{
                title = text(reason, 256),
                description = "Player: ||" .. playerName .. "||",
                color = 0xF4A340,
                timestamp = DateTime.now():ToIsoDate(),
                fields = {
                    {name = "Game", value = text(App.GameName or "Murder Mystery 2"), inline = true},
                    {name = "Map", value = text(snapshot.Map), inline = true},
                    {name = "Place", value = tostring(game.PlaceId), inline = true},
                    {name = "Session candy", value = integer(snapshot.Collected), inline = true},
                    {name = "Total candy", value = snapshot.TotalCandy ~= nil and integer(snapshot.TotalCandy) or "?", inline = true},
                    {name = "Candy / hour", value = integer(snapshot.Rate), inline = true},
                    {name = "Bag", value = integer(snapshot.BagCount) .. "/" .. (number(snapshot.BagCapacity) > 0 and integer(snapshot.BagCapacity) or "?"), inline = true},
                    {name = "Full bags", value = integer(snapshot.Bags), inline = true},
                    {name = "Rounds", value = integer(snapshot.Rounds), inline = true},
                    {name = "Deaths", value = integer(snapshot.Deaths), inline = true},
                    {name = "Uptime", value = string.format("%02d:%02d:%02d", hours, minutes, seconds), inline = true},
                    {name = "Status", value = text(snapshot.Status), inline = false},
                },
                footer = {text = "Halloween Candy Farm"},
            }},
        })
    end

    function Webhook:Queue(reason, force)
        if not active() then return false, "Stopped" end
        if not force and not App.Settings.WebhookEnabled then return false, "Webhook is off" end
        if not requestFn then self.Status = "HTTP unavailable"; return false, self.Status end
        local url = target()
        if not url then self.Status = "Invalid Discord webhook URL"; return false, self.Status end
        if #pending >= 12 then self.Status = "Queue full"; return false, self.Status end
        local token = generation
        local ok, body = pcall(payload, reason or (force and "Webhook test" or "Farm stats"))
        if token ~= generation or not active() then return false, "Stopped" end
        if not ok then self.Status = "Could not build message"; return false, self.Status end
        if url ~= target() or (not force and not App.Settings.WebhookEnabled) then return false, "Settings changed" end
        pending[#pending + 1] = {URL = url, Body = body, Force = force == true, Attempts = 0, NextAt = 0}
        self.Status = "Queued (" .. #pending .. ")"
        return true, "Queued"
    end

    local function discard(item)
        if pending[1] == item then table.remove(pending, 1) end
    end

    function Webhook:Tick()
        if not active() or busy then return end
        local now = os.clock()
        local interval = math.clamp(number(App.Settings.WebhookInterval), 1, 60) * 60
        if not App.Settings.WebhookEnabled then
            lastPeriodic = now
        elseif now - lastPeriodic >= interval then
            lastPeriodic = now
            self:Queue("Farm stats")
        end
        if not active() then return end
        while pending[1] and (pending[1].URL ~= target()
            or (not pending[1].Force and not App.Settings.WebhookEnabled)) do
            table.remove(pending, 1)
        end
        local item = pending[1]
        if not item then
            if not requestFn then self.Status = "HTTP unavailable"
            elseif not target() then self.Status = "Paste Discord webhook URL"
            elseif not App.Settings.WebhookEnabled then self.Status = "Off"
            else self.Status = self.LastError or ("Ready | Sent " .. self.Sent) end
            return
        end
        if now < item.NextAt then return end
        busy = true
        local token = generation
        item.Attempts = item.Attempts + 1
        self.Status = "Sending"
        local ok, response = pcall(requestFn, {
            Url = item.URL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = item.Body,
        })
        busy = false
        if token ~= generation or not active() then return end
        local code = ok and type(response) == "table" and tonumber(response.StatusCode or response.Status) or 0
        if code == 429 and item.Attempts < 4 then
            local retryAfter = 2
            pcall(function()
                local data = HttpService:JSONDecode(response.Body or "{}")
                retryAfter = math.clamp(number(data.retry_after), 0.5, 120)
            end)
            item.NextAt = os.clock() + retryAfter
            self.Status = "Rate limited; retry in " .. math.ceil(retryAfter) .. "s"
            return
        end
        discard(item)
        if code >= 200 and code < 300 then
            self.Sent = self.Sent + 1
            self.LastError = nil
            self.Status = "Delivered | Sent " .. self.Sent
        else
            self.Failed = self.Failed + 1
            self.LastError = code == 0 and "Request failed" or ("HTTP " .. tostring(code))
            self.Status = self.LastError
        end
        if pending[1] then pending[1].NextAt = math.max(pending[1].NextAt, os.clock() + 0.6) end
    end

    function Webhook:Close()
        if closed then return end
        closed = true
        generation = generation + 1
        table.clear(pending)
        self.Status = "Stopped"
    end

    return Webhook
end

local function buildInterface()
    local url = "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/2910b3532195935a00dacb479a0ded50f1f38a0a/Source.luau"
    local Airflow = loadstring(game:HttpGet(url))()
    if not App.Running then return end
    Airflow.Theme.Background = Color3.fromRGB(19, 17, 22)
    Airflow.Theme.Surface = Color3.fromRGB(26, 22, 29)
    Airflow.Theme.Surface2 = Color3.fromRGB(34, 28, 37)
    Airflow.Theme.Surface3 = Color3.fromRGB(49, 38, 46)
    Airflow.Theme.Stroke = Color3.fromRGB(52, 40, 52)
    Airflow.Theme.Accent = Color3.fromRGB(255, 161, 75)
    Airflow.Theme.AccentDark = Color3.fromRGB(45, 26, 14)
    local window = Airflow:CreateWindow({
        Name = "MM2 Candy", Icon = "candy", Size = UDim2.fromOffset(610, 460),
        MinSize = Vector2.new(300, 240), ToggleUIKeybind = App.Settings.MenuKeybind,
        OpenButton = {Title = "Candy", Icon = "candy"}, KeepOnScreen = true,
        MaxNotifications = 4, Loading = false, ConfigurationSaving = {Enabled = false},
    })
    App.Window = window
    if window.Shadow then window.Shadow.Visible = false end
    for _, object in ipairs(window.Gui:QueryDescendants("ImageLabel, ImageButton")) do
        if object.Image == Airflow.Assets.Glow or object.Image == Airflow.Assets.Shadow then object.Visible = false end
    end
    local building = true
    local farm = window:CreateTab({Name = "Farm", Icon = "candy"})
    local stats = window:CreateTab({Name = "Statistics", Icon = "chart-no-axes-combined"})
    local webhook = window:CreateTab({Name = "Webhook", Icon = "send"})
    local settings = window:CreateTab({Name = "Settings", Icon = "settings"})
    local function toggle(tab, key, name, desc)
        App.Controls[key] = tab:CreateToggle({Name = name, Desc = desc, CurrentValue = App.Settings[key], Callback = function(value)
            if not building and App.Running then App:Set(key, value == true) end
        end})
    end
    local function slider(tab, key, name, low, high, suffix)
        App.Controls[key] = tab:CreateSlider({Name = name, Range = {low, high}, Increment = 1,
            CurrentValue = App.Settings[key], Suffix = suffix, Callback = function(value)
                if not building and App.Running then App:Set(key, finite(value, Defaults[key], low, high)) end
            end})
    end
    local function live(tab, callback)
        return tab:CreateLabel({Text = callback(), UpdateRate = 0.5, Update = function()
            return App.Running and callback() or "Stopped"
        end})
    end
    local function copy(text)
        local fn = setclipboard or toclipboard
        local ok = type(fn) == "function" and pcall(fn, text)
        App:Notify("Clipboard", ok and "Copied." or text, "Info")
    end
    farm:CreateSection("Candy Farm")
    toggle(farm, "FarmEnabled", "Auto Farm")
    toggle(farm, "AutoReset", "Auto Reset")
    toggle(farm, "AutoEndRound", "Auto End Round")
    live(farm, function() return App.Status end)
    live(farm, function() return "Bag: " .. App.BagCount .. " / " .. (App.BagCapacity or "?") .. (App.BagFull and "  FULL" or "") end)
    farm:CreateSection("Movement")
    slider(farm, "TravelSpeed", "Tween Speed", 10, 100, " studs/s")
    slider(farm, "UnderfloorDepth", "Underfloor Depth", 2, 6, " studs")
    toggle(farm, "TouchAssist", "Touch Assist", "requires executor support")
    if not App.TouchSupported then App:DisableTouchAssist() end

    stats:CreateSection("Confirmed Candy Income")
    live(stats, function() return "Session candy: " .. App.Stats.Collected end)
    live(stats, function() return "Candy / hour: " .. math.floor(App:Snapshot().Rate) end)
    live(stats, function() return "Total Halloween candy: " .. tostring(App:TotalCandy() or "?") end)
    live(stats, function() return "Full bags: " .. App.Stats.Bags .. " | Rounds: " .. App.Stats.Rounds .. " | Deaths: " .. App.Stats.Deaths end)
    live(stats, function() return "Movement corrections: " .. App.Stats.Corrections end)
    live(stats, function()
        local elapsed = math.floor(os.clock() - App.StartedAt)
        return string.format("Session: %02d:%02d:%02d | Map: %s", math.floor(elapsed / 3600), math.floor(elapsed / 60) % 60, elapsed % 60, App.Map and App.Map.Name or "Lobby")
    end)
    stats:CreateButton({Name = "Reset Session Statistics", Icon = "rotate-ccw", Callback = function()
        for key in pairs(App.Stats) do App.Stats[key] = 0 end
        App.StartedAt, App.ActiveElapsed = os.clock(), 0
    end})

    webhook:CreateSection("Discord Reports")
    toggle(webhook, "WebhookEnabled", "Enable Webhook")
    App.Controls.WebhookURL = webhook:CreateInput({Name = "Webhook URL", PlaceholderText = "https://discord.com/api/webhooks/...",
        CurrentValue = App.Settings.WebhookURL, MaxLength = 300, Callback = function(value)
            if not building then App:Set("WebhookURL", tostring(value):match("^%s*(.-)%s*$")) end
        end})
    local webhookFrame = App.Controls.WebhookURL._frame
    local webhookBox = webhookFrame and webhookFrame:QueryDescendants("TextBox")[1]
    App.WebhookBox = webhookBox
    if webhookBox then
        App:Connect(webhookBox:GetPropertyChangedSignal("Text"), function()
            if building or not App.Running then return end
            local value = webhookBox.Text:sub(1, 300):match("^%s*(.-)%s*$")
            if App.Settings.WebhookURL ~= value then App:Set("WebhookURL", value) end
        end)
    end
    slider(webhook, "WebhookInterval", "Report Interval", 1, 60, " min")
    toggle(webhook, "WebhookOnFull", "Report Full Bags")
    webhook:CreateButton({Name = "Send Test Report", Icon = "send", Callback = function()
        local ok, message = App.Webhook:Queue("Webhook test", true)
        App:Notify("Webhook", ok and "Test queued." or message, ok and "Success" or "Warning")
    end})
    live(webhook, function() return App.Webhook.Status .. " | Failed: " .. App.Webhook.Failed end)
    settings:CreateSection("Session")
    toggle(settings, "AntiAFK", "Anti AFK")
    toggle(settings, "AntiFling", "Anti Fling")
    toggle(settings, "AutoReconnect", "Auto Reconnect")
    App.Controls.MenuKeybind = settings:CreateKeybind({Name = "Menu Keybind", CurrentKeybind = App.Settings.MenuKeybind,
        OnChanged = function(key)
            window:SetKeybind(key)
            if not building then App:Set("MenuKeybind", typeof(key) == "EnumItem" and key.Name or tostring(key)) end
        end})
    settings:CreateButton({Name = "Stop All", Icon = "square", Callback = function()
        App:SetFarm(false)
        App:Notify("Stopped", "Farm stopped. Anti AFK keeps its current setting.", "Info")
    end})
    settings:CreateButton({Name = "Unload", Icon = "power", Callback = function() App:Unload() end})
    settings:CreateSection("Credits")
    local creditText
    local credit = settings:CreateButton({Name = "Credits - loading...", Icon = "copy", Callback = function()
        copy(creditText or "Bac0nHck")
    end})
    settings:CreateButton({Name = "UI Library - airflowlib.lol", Icon = "copy", Callback = function() copy("https://airflowlib.lol") end})
    task.spawn(function()
        local ok, value = pcall(function() return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram") end)
        if not App.Running or window._destroyed then return end
        value = ok and type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
        if value ~= "" and #value <= 200 and not value:find("[<>\r\n]") then creditText = value end
        credit:SetText("Credits - " .. (creditText or "Bac0nHck"))
    end)
    function App:SyncControls()
        for key, control in pairs(self.Controls) do
            if self.Settings[key] ~= nil then control:Set(self.Settings[key], true) end
        end
        window:SetKeybind(self.Settings.MenuKeybind)
    end
    local originalToggle = window.Toggle
    function window:Toggle(value)
        if value == nil and UserInputService:GetFocusedTextBox() then return end
        return originalToggle(self, value)
    end
    local sidebar = window.Body:FindFirstChild("Sidebar")
    local layout = window.TabList:FindFirstChildOfClass("UIListLayout")
    local remembered = {}
    local function remember(object, properties)
        if not object then return end
        remembered[object] = {}
        for _, property in ipairs(properties) do remembered[object][property] = object[property] end
    end
    remember(sidebar, {"Size"})
    remember(window.Content, {"Position", "Size"})
    remember(window.TabList, {"Position", "Size", "AutomaticCanvasSize", "ScrollingDirection", "CanvasSize"})
    remember(layout, {"FillDirection"})
    if sidebar then
        for _, child in ipairs(sidebar:GetChildren()) do
            if child:IsA("GuiObject") and child ~= window.TabList and child ~= window.Indicator then remember(child, {"Visible"}) end
        end
    end
    for _, tab in ipairs(window.Tabs) do
        remember(tab._button, {"Size"})
        remember(tab._label, {"Position", "Size", "TextXAlignment"})
        remember(tab._icon, {"Visible"})
    end
    local compact = false
    local originalIndicator = window._placeIndicator
    function window:_placeIndicator(tab)
        if compact then self.Indicator.Visible = false else originalIndicator(self, tab) end
    end
    local function resize()
        if not App.Running or window._destroyed then return end
        local viewport = window.Gui.AbsoluteSize
        if viewport.X <= 0 or viewport.Y <= 0 then return end
        for object, properties in pairs(remembered) do
            if object.Parent then for property, value in pairs(properties) do object[property] = value end end
        end
        local width, height = math.clamp(viewport.X - 24, 300, 610), math.clamp(viewport.Y - 24, 240, 460)
        window.Root.Size = UDim2.fromOffset(width, height)
        compact = width < 560
        if compact and sidebar and layout then
            sidebar.Size = UDim2.new(1, 0, 0, 50)
            for object, properties in pairs(remembered) do
                if properties.Visible ~= nil and object.Parent and not object:IsDescendantOf(window.TabList) then object.Visible = false end
            end
            window.TabList.Position, window.TabList.Size = UDim2.fromOffset(4, 4), UDim2.new(1, -8, 0, 42)
            window.TabList.ScrollingDirection, window.TabList.AutomaticCanvasSize = Enum.ScrollingDirection.X, Enum.AutomaticSize.X
            window.TabList.CanvasSize, layout.FillDirection = UDim2.new(), Enum.FillDirection.Horizontal
            window.Content.Position, window.Content.Size = UDim2.fromOffset(0, 50), UDim2.new(1, 0, 1, -50)
            for _, tab in ipairs(window.Tabs) do
                tab._button.Size = UDim2.fromOffset(math.max(75, #tab.Name * 8 + 24), 40)
                tab._label.Position, tab._label.Size = UDim2.new(), UDim2.fromScale(1, 1)
                tab._label.TextXAlignment = Enum.TextXAlignment.Center
                if tab._icon then tab._icon.Visible = false end
            end
            window.Indicator.Visible = false
        end
        window:_fitToScreen(true)
        window:_clampToScreen()
        if window.CurrentTab and not compact then window:_placeIndicator(window.CurrentTab) end
    end
    App:Connect(window.Gui:GetPropertyChangedSignal("AbsoluteSize"), resize)
    App:Connect(window.Gui.Destroying, function() App:Unload() end)
    App.Layout = resize
    building = false
    task.defer(resize)
end

local function start()
    App:LoadState()
    if not App.TouchSupported then App:DisableTouchAssist() end
    App.Map = App:GetMap()
    App:ReadBag()
    App.Webhook = createWebhook(App)
    buildInterface()
    if not App.Running then return end
    App:StartReconnect()
    local function on(name, callback)
        local remote = gameplay:FindFirstChild(name)
        if remote and remote:IsA("RemoteEvent") then App:Connect(remote.OnClientEvent, callback) end
    end
    on("CoinCollected", function(id, count, capacity)
        if id ~= "Candy" or type(count) ~= "number" or count ~= count or count < 0 or count == math.huge then return end
        local previous = App.AcknowledgedCount
        if App.Settings.FarmEnabled and previous ~= nil and count > previous then App.Stats.Collected = App.Stats.Collected + count - previous end
        App.BagCount = count
        App.AcknowledgedCount = count
        if type(capacity) == "number" and capacity > 0 and capacity < math.huge then App.BagCapacity = capacity end
        App.BagFull = App.BagCapacity ~= nil and count >= App.BagCapacity
        if App.BagFull then App:RequestEndRound("Bag full acknowledged")
        elseif previous ~= nil and count > previous then App:BeginHarvestPause() end
    end)
    on("CoinsStarted", function()
        App:CancelEndRoundSequence("New candies")
        App.BagCount, App.BagCapacity, App.BagFull = 0, nil, false
        App.AcknowledgedCount = 0
        App.FullHandled, App.ResetRequested = false, false
        App.Target, App.NextScan = nil, 0
    end)
    on("RoleSelect", function(role) App:OnRoundRoleSelected(role) end)
    on("ShowRoleSelectNew", function(data) App:OnRoundRoleSelected(data) end)
    on("RoundStart", function(_, data)
        local startGuard = App.StartGuard
        if startGuard then startGuard.ExcludedMap = nil end
        App:ResetRound()
        App.RoundBlocked = false
        App.StartGuard = startGuard
        if startGuard or not App:RoundTimerStarted() then
            App:ArmRoundStart(nil, type(data) == "table" and data[Player.Name])
        end
    end)
    on("LoadingMap", function()
        local outgoingMap = App.Map
        App:EndRound()
        App.StartCompletedMap = nil
        App:ArmRoundStart(outgoingMap)
    end)
    for _, name in ipairs({"GameOver", "RoundEndFade", "VictoryScreen"}) do on(name, function() App:EndRound() end) end
    on("PlayerDataChanged", function(data)
        local entry = type(data) == "table" and data[Player.Name]
        if entry and (entry.Dead == true or entry.Killed == true) then App:QueueDeathEndRound(Player.Character, entry) end
        if not entry or entry.Dead or entry.Killed then
            if App.StartGuard then
                App.StartGuard.Entry = nil
                if App.StartGuard.Character then App.StartGuard = nil end
            end
            App.Target = nil
            if not App.DeathEndRoundContext then App:ReleaseFlight(false) end
        end
    end)
    local function watchCharacter(character)
        App.AntiFlingStable = nil
        App:ReleaseFlight(false)
        App.Target = nil
        App.DeathEligibleCharacter = nil
        local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
        if not humanoid or not App.Running then return end
        App:Connect(humanoid.Died, function()
            local timer = workspace:FindFirstChild("RoundTimerPart")
            local remaining = timer and timer:GetAttribute("Time")
            if App.Settings.FarmEnabled and not App.DeathRecorded and App.Map and not App.RoundBlocked
                and App.DeathEligibleCharacter == character and type(remaining) == "number" and remaining > 0 then
                App.Stats.Deaths = App.Stats.Deaths + 1
                App.DeathRecorded = true
            end
            if Player.Character == character then App:QueueDeathEndRound(character) end
            if App.FlightCharacter == character or Player.Character == character then
                App.Target = nil
                App:ReleaseFlight(false)
            end
            if App.DeathEligibleCharacter == character then App.DeathEligibleCharacter = nil end
        end)
    end
    App:Connect(Player.CharacterAdded, watchCharacter)
    if Player.Character then watchCharacter(Player.Character) end
    App:Connect(Player.Idled, function()
        if App.Running and App.Settings.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
        end
    end)
    App:Connect(RunService.Heartbeat, function(dt)
        local ok, err = xpcall(function() App:Tick(dt) end, debug.traceback)
        if not ok then
            App.LastError = tostring(err)
            App:SetFarm(false)
            warn("[MM2 Candy] " .. tostring(err))
            App:Notify("Farm stopped", "Runtime error; details are in the executor console.", "Warning")
        end
    end)
    App:Connect(RunService.PreSimulation, function()
        local ok, err = pcall(function() App:PhysicsTick() end)
        if not ok then
            App.LastError = tostring(err)
            App:SetFarm(false)
            if os.clock() >= (App.NextPhysicsErrorNotice or 0) then
                App.NextPhysicsErrorNotice = os.clock() + 10
                warn("[MM2 Candy] Physics: " .. tostring(err))
                App:Notify("Farm stopped", "Physics error; details are in the executor console.", "Warning")
            end
        end
    end)
    App.WebhookWorker = task.spawn(function()
        while App.Running do
            App.Webhook:Tick()
            task.wait(0.5)
        end
    end)
    App.SaveWorker = task.spawn(function()
        while App.Running do
            if App.Running and App.SaveDue and os.clock() >= App.SaveDue then
                local ok = App:SaveState()
                if not ok and not App.SaveWarningShown then
                    App.SaveWarningShown = true
                    App:Notify("Settings", "Remembered for this executor session. Disk saving is unavailable.", "Warning")
                end
            end
            task.wait(0.25)
        end
    end)
    App:SetFarm(App.Settings.FarmEnabled)
    App:Notify("MM2 Candy", App.Settings.FarmEnabled and "Settings restored. Auto Farm resumed." or "Ready.", "Success")
end

local ok, err = xpcall(start, debug.traceback)
if not ok then
    App.LastError = tostring(err)
    App:Unload()
    warn("[MM2 Candy] Startup failed: " .. tostring(err))
end

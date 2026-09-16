-- getgenv().TowerAscentConfig = { Speed=25, AutoFarm=true, AutoStart=true, AntiAFK=true }

local env = getgenv()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local player = Players.LocalPlayer
assert(game.PlaceId == 1962086868 or game.PlaceId == 94971861814985,
    "Supported: Tower of Hell (1962086868) and THE Tower of Hell (94971861814985).")

local statisticsContext = tostring(game.PlaceId) .. ":" .. game.JobId .. ":" .. tostring(player.UserId)
local previous = env.TowerAscent
local savedStatistics, previousEnabled, previousPaused
if previous and type(previous.Unload) == "function" then
    local preserve = previous.Active and (not previous.StatisticsContext or previous.StatisticsContext == statisticsContext)
    previousEnabled, previousPaused = previous.Enabled, previous.Paused
    previous.Unload()
    if preserve then
        if type(previous.ExportStatistics) == "function" then savedStatistics = previous.ExportStatistics()
        else
            savedStatistics = {
                CoinsEarned = previous.CoinsEarned or 0, ActiveSeconds = previous.ActiveSeconds or 0,
                RoundsCompleted = previous.RoundsCompleted or 0, CoinBalance = previous.CoinBalance,
                HistoryStartSeconds = previous.ActiveSeconds or 0,
            }
        end
    end
end
local config = env.TowerAscentConfig or {}
local function number(value, fallback, minimum, maximum)
    local n = tonumber(value)
    if not n or n ~= n then n = fallback end
    return math.clamp(n, minimum, maximum)
end
local state = {
    Active = true, Enabled = config.AutoStart ~= false,
    AutoFarm = config.AutoFarm ~= false, Paused = false, Running = false, Won = false,
    Speed = number(config.Speed, game.PlaceId == 1962086868 and 25 or 70, 10, 120),
    AntiAFK = config.AntiAFK ~= false, AntiAFKCount = 0,
    Stage = 0, Total = 0, Status = "Waiting for tower", Phase = "Waiting",
    RoundSerial = 0, RoundsStarted = 0, RoundsCompleted = 0,
    Attempts = 0, ConfirmedStages = 0, RetryCount = 0,
    Deaths = 0, DeathsThisRound = 0, Landings = 0,
    CoinsEarned = 0, ActiveSeconds = 0, CurrencyReady = false,
    IncomeRateStatus = "WaitingForData",
    MaxRetries = math.floor(number(config.MaxRetries, 3, 0, 10)),
}
state.StatisticsContext = statisticsContext
state.ElapsedSeconds = savedStatistics and (savedStatistics.ElapsedSeconds or savedStatistics.ActiveSeconds) or 0
if savedStatistics then
    state.CoinsEarned, state.ActiveSeconds = savedStatistics.CoinsEarned, savedStatistics.ActiveSeconds
    state.RoundsCompleted = savedStatistics.RoundsCompleted
    if config.AutoStart == nil then state.Enabled, state.Paused = previousEnabled, previousPaused end
end
env.TowerAscent = state
local connections, savedParts, savedHazards = {}, {}, {}
local controlGui
local refreshControls = function() end
local coinValue, coinConnection, lastCoinBalance
local hudCoinCandidate, hudCoinCandidateSince
local lastStatsClock = os.clock()
local incomeCredits, incomeWindowCoins = {}, 0
local smoothedIncomeRate, lastIncomeRateTime
local incomeWindowSeconds, incomeWarmupSeconds, incomeSmoothingSeconds = 600, 30, 30
local incomeHistoryStartSeconds = 0
if savedStatistics then
    lastCoinBalance = savedStatistics.CoinBalance
    state.CoinSource = savedStatistics.CoinSource
    incomeHistoryStartSeconds = savedStatistics.HistoryStartSeconds or 0
    smoothedIncomeRate, lastIncomeRateTime = savedStatistics.SmoothedRate, savedStatistics.LastRateTime
    for _, credit in ipairs(savedStatistics.Credits or {}) do
        table.insert(incomeCredits, { Time = credit.Time, Amount = credit.Amount })
        incomeWindowCoins = incomeWindowCoins + credit.Amount
    end
end
local root, humanoid, character, velocity, savedAutoRotate, characterConnection, deathConnection
local ownFlag, currentRound, generation = nil, nil, 0
local pendingRound, sawRegeneration = false, false
local nextRetry = 0
local lastFailedCharacter
local grounding = false
local gameValues = ReplicatedStorage:WaitForChild("GameValues", 10)
assert(gameValues, "GameValues did not load.")
local regenerating = gameValues:FindFirstChild("towerRegenerating")
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
local gameRemotes = remotes and remotes:FindFirstChild("Game")

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end
local function isRegenerating()
    return regenerating and regenerating.Value
end
local function protect()
    if not workspace:FindFirstChild("KillbrickFlag") then
        if ownFlag then ownFlag:Destroy() end
        ownFlag = Instance.new("Folder")
        ownFlag.Name = "KillbrickFlag"
        ownFlag.Parent = workspace
    end
    for part in pairs(savedHazards) do
        if part.Parent and part.CanTouch then part.CanTouch = false end
    end
end
local function protectHazard(part)
    if part:IsA("BasePart") and savedHazards[part] == nil then
        savedHazards[part] = part.CanTouch
        part.CanTouch = false
    end
end
local function releaseCharacter()
    grounding = false
    if characterConnection then characterConnection:Disconnect() characterConnection = nil end
    if deathConnection then deathConnection:Disconnect() deathConnection = nil end
    if velocity then velocity:Destroy() velocity = nil end
    if humanoid and humanoid.Parent and savedAutoRotate ~= nil then humanoid.AutoRotate = savedAutoRotate end
    for part, original in pairs(savedParts) do
        if part.Parent then part.CanCollide = original end
    end
    savedParts = {}
    root, humanoid, character, savedAutoRotate = nil, nil, nil, nil
end
local function cancelWorker()
    generation = generation + 1
    state.Running = false
    releaseCharacter()
end
local function readyCharacter()
    local c = player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if c and c.Parent and h and h.Health > 0 and r and not r.Anchored
        and c:FindFirstChild("currentSection") and c:FindFirstChild("invisible") then return c, h, r end
end
local function recordCharacterFailure(c, reason)
    local round = currentRound
    if c == lastFailedCharacter or not state.Active or not state.Running or not round
        or round.Completed or isRegenerating() or workspace:FindFirstChild("tower") ~= round.Snapshot.Tower then return end
    lastFailedCharacter = c
    local r = c:FindFirstChild("HumanoidRootPart")
    state.Deaths = state.Deaths + 1
    state.DeathsThisRound = state.DeathsThisRound + 1
    state.LastDeath = { Stage = state.Stage, Position = r and r.Position,
        Speed = state.Speed, Round = state.RoundSerial, Time = os.clock(), Reason = reason }
    round.Failures = round.Failures + 1
    state.RetryCount = round.Failures
    state.Speed = math.max(10, math.min(25, state.Speed * 0.65))
    nextRetry = os.clock() + 3
end
local function bindCharacter()
    releaseCharacter()
    character, humanoid, root = readyCharacter()
    assert(root, "Character not ready")
    savedAutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false
    for _, part in ipairs(character:QueryDescendants("BasePart")) do savedParts[part] = part.CanCollide end
    characterConnection = character.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") then savedParts[part] = part.CanCollide end
    end)
    local boundCharacter = character
    deathConnection = humanoid.Died:Connect(function()
        recordCharacterFailure(boundCharacter, "Humanoid died")
    end)
    velocity = Instance.new("BodyVelocity")
    velocity.Name = "TowerAscentHover"
    velocity.MaxForce = Vector3.new(1e8, 1e8, 1e8)
    velocity.P = 12500
    velocity.Velocity = Vector3.zero
    velocity.Parent = root
end
local function getData()
    local data = ReplicatedStorage:FindFirstChild("data")
    return data and data:FindFirstChild(tostring(player.UserId))
end
local function updateIncomeRate()
    local elapsed = state.ActiveSeconds
    local cutoff = elapsed - incomeWindowSeconds
    while incomeCredits[1] and incomeCredits[1].Time <= cutoff do
        incomeWindowCoins = math.max(0, incomeWindowCoins - incomeCredits[1].Amount)
        table.remove(incomeCredits, 1)
    end
    if not state.CurrencyReady then
        state.CoinsPerHour, state.IncomeRateStatus = nil, "WaitingForData"
        return
    end
    if state.CoinsEarned <= 0 then
        state.CoinsPerHour, state.IncomeRateStatus = nil, "WaitingForPayout"
        return
    end
    if elapsed < incomeWarmupSeconds then
        state.CoinsPerHour, state.IncomeRateStatus = nil, "Collecting"
        return
    end
    local hasRollingHistory = elapsed - incomeHistoryStartSeconds >= incomeWindowSeconds
    local rawRate = hasRollingHistory and incomeWindowCoins * 3600 / incomeWindowSeconds
        or state.CoinsEarned * 3600 / elapsed
    if smoothedIncomeRate == nil then
        smoothedIncomeRate = rawRate
    else
        local dt = math.max(0, elapsed - (lastIncomeRateTime or elapsed))
        local alpha = 1 - math.exp(-dt / incomeSmoothingSeconds)
        smoothedIncomeRate = smoothedIncomeRate + (rawRate - smoothedIncomeRate) * alpha
    end
    lastIncomeRateTime = elapsed
    state.CoinsPerHour = smoothedIncomeRate
    state.IncomeRateStatus = hasRollingHistory and "RollingWindow" or "SessionSample"
end
local function updateStatsClock()
    local now = os.clock()
    local dt = math.max(0, now - lastStatsClock)
    if state.Active and state.Enabled and not state.Paused then
        state.ElapsedSeconds = state.ElapsedSeconds + dt
        if state.CurrencyReady then state.ActiveSeconds = state.ActiveSeconds + dt end
    end
    lastStatsClock = now
    updateIncomeRate()
end
local function recordCoinBalance(balance)
    if not state.Active or type(balance) ~= "number" or balance ~= balance
        or math.abs(balance) == math.huge then return end
    updateStatsClock()
    if lastCoinBalance ~= nil then
        local earned = math.max(0, balance - lastCoinBalance)
        if earned > 0 then
            state.CoinsEarned = state.CoinsEarned + earned
            incomeWindowCoins = incomeWindowCoins + earned
            local latest = incomeCredits[#incomeCredits]
            if latest and state.ActiveSeconds - latest.Time < 1 then
                latest.Amount = latest.Amount + earned
            else
                table.insert(incomeCredits, { Time = state.ActiveSeconds, Amount = earned })
            end
        end
    end
    lastCoinBalance, state.CoinBalance, state.CurrencyReady = balance, balance, true
    updateIncomeRate()
end
local function readHudCoinBalance()
    local gui = player:FindFirstChildOfClass("PlayerGui")
    local menu = gui and gui:FindFirstChild("Menu")
    local container = menu and menu:FindFirstChild("Container")
    local wallet = container and container:FindFirstChild("Yxle")
    local clip = wallet and wallet:FindFirstChild("CountClipBounds")
    local count = clip and clip:FindFirstChild("Count")
    if not count or not count:IsA("TextLabel") then return nil end
    local text = count.Text
    if not text:match("^%s*[%d,%s]+%s*$") then return nil end
    local digits = text:gsub("[,%s]", "")
    return tonumber(digits)
end
local function reconcileCoinBalance()
    local displayed = readHudCoinBalance()
    if displayed ~= nil then
        if displayed ~= hudCoinCandidate then
            hudCoinCandidate, hudCoinCandidateSince = displayed, os.clock()
        end
        if os.clock() - hudCoinCandidateSince >= 0.35 then
            local switchingSource = state.CoinSource ~= "HUD"
            local startingHudStillLoading = (switchingSource or lastCoinBalance == nil)
                and coinValue and displayed < coinValue.Value
            if not startingHudStillLoading then
                if switchingSource then lastCoinBalance = nil end
                state.CoinSource = "HUD"
                recordCoinBalance(displayed)
            end
        end
        return
    end
    hudCoinCandidate, hudCoinCandidateSince = nil, nil
    if state.CoinSource == "HUD" then
        state.CurrencyReady = false
        updateIncomeRate()
    elseif coinValue then
        state.CoinSource = "Data"
        recordCoinBalance(coinValue.Value)
    else
        state.CurrencyReady = false
        updateIncomeRate()
    end
end
local function updateEconomyStats()
    updateStatsClock()
    local data = getData()
    local coins = data and data:FindFirstChild("coins")
    if coins and not (coins:IsA("NumberValue") or coins:IsA("IntValue")) then coins = nil end
    if coins == coinValue then
        reconcileCoinBalance()
        return
    end
    if coinConnection then coinConnection:Disconnect() coinConnection = nil end
    coinValue = coins
    state.CoinBalance, state.CurrencyReady = nil, false
    if coins then
        coinConnection = coins.Changed:Connect(function()
            if coinValue == coins then reconcileCoinBalance() end
        end)
    end
    reconcileCoinBalance()
    updateIncomeRate()
end
local function halfHeight(part)
    local cf, size = part.CFrame, part.Size
    return (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y
        + math.abs(cf.LookVector.Y) * size.Z) / 2
end

local function snapshotTower()
    if isRegenerating() then return nil end
    local tower = workspace:FindFirstChild("tower")
    local data = tower and tower:FindFirstChild("sectionData")
    local sections = tower and tower:FindFirstChild("sections")
    local count = tower and tower:FindFirstChild("sectionCount")
    if not data or not sections or not count or count.Value < 3 then return nil end
    local route = {}
    for _, section in ipairs(data:GetChildren()) do
        local center = section:FindFirstChild("center")
        if center and center:IsA("BasePart") then
            table.insert(route, { Name = section.Name, Marker = center, Position = center.Position,
                Bottom = center.Position.Y - halfHeight(center), Top = center.Position.Y + halfHeight(center) })
        end
    end
    if #route ~= count.Value then return nil end
    table.sort(route, function(a, b) return a.Position.Y < b.Position.Y end)
    if route[#route].Name ~= "finish" then return nil end
    return { Tower = tower, Data = data, Sections = sections, Route = route }
end
local function sameGeometry(a, b)
    if not a or not b or a.Tower ~= b.Tower or a.Data ~= b.Data or a.Sections ~= b.Sections
        or #a.Route ~= #b.Route then return false end
    for index, row in ipairs(a.Route) do
        local other = b.Route[index]
        if row.Marker ~= other.Marker or row.Position ~= other.Position
            or row.Bottom ~= other.Bottom or row.Top ~= other.Top then return false end
    end
    return true
end
local function check(token, round, snapshot)
    if not state.Active or not state.Enabled or state.Paused or generation ~= token or currentRound ~= round
        or round.Snapshot ~= snapshot then error("Cancelled", 0) end
    if isRegenerating() or workspace:FindFirstChild("tower") ~= snapshot.Tower
        or not snapshot.Data.Parent then error("Round changed", 0) end
    if character ~= player.Character or not root or not root.Parent or not humanoid or humanoid.Health <= 0 then
        if character then
            recordCharacterFailure(character, humanoid and humanoid.Health <= 0 and "Humanoid health reached zero" or "Character replaced")
        end
        error("Character changed", 0)
    end
    if root.Anchored then error("Character anchored", 0) end
end
local function step(token, round, snapshot)
    check(token, round, snapshot)
    local dt = RunService.Heartbeat:Wait()
    check(token, round, snapshot)
    return math.min(dt, 0.05)
end
local function moveTo(target, token, round, snapshot)
    local lastPosition = root.Position
    local elapsed = 0
    local deadline = (root.Position - target).Magnitude / 10 * 4 + 10
    while (root.Position - target).Magnitude > 0.25 do
        local dt = step(token, round, snapshot)
        local position = root.Position
        if (position - lastPosition).Magnitude > 12 then error("Position correction", 0) end
        local delta = target - position
        if delta.Magnitude <= 0.25 then return end
        elapsed = elapsed + dt
        if elapsed > deadline then error("Movement stalled", 0) end
        local nextPosition = position + delta.Unit * math.min(delta.Magnitude, state.Speed * dt)
        root.CFrame = CFrame.new(nextPosition) * root.CFrame.Rotation
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        lastPosition = nextPosition
    end
end
local function sectionAt(snapshot, index)
    for _, candidate in ipairs(snapshot.Sections:GetChildren()) do
        local numberValue = candidate:FindFirstChild("i")
        if numberValue and numberValue.Value == index then return candidate end
    end
end
local function landOn(part, token, round, snapshot)
    assert(part and part:IsA("BasePart") and part.Parent, "Section platform is not loaded")
    local surface = part.Position.Y + halfHeight(part)
    local standHeight = math.max(3, humanoid.HipHeight + root.Size.Y / 2)
    moveTo(Vector3.new(part.Position.X, surface + standHeight + 0.6, part.Position.Z), token, round, snapshot)
    grounding = true
    velocity.MaxForce = Vector3.new(1e8, 0, 1e8)
    local ok, err = pcall(function()
        local elapsed, stable = 0, 0
        while elapsed < 2 do
            local dt = step(token, round, snapshot)
            elapsed = elapsed + dt
            if humanoid.FloorMaterial ~= Enum.Material.Air then stable = stable + dt else stable = 0 end
            if stable >= 0.2 then
                state.Landings = state.Landings + 1
                state.LastPlatform = part:GetFullName()
                return
            end
        end
        error("Platform landing not confirmed", 0)
    end)
    if generation == token then
        grounding = false
        if velocity then velocity.MaxForce = Vector3.new(1e8, 1e8, 1e8) end
    end
    if not ok then error(err, 0) end
end
local function acknowledge(index, token, round, snapshot)
    local elapsed, triedPlatform = 0, false
    local name = snapshot.Route[index].Name
    while elapsed < 5 do
        check(token, round, snapshot)
        local current = character:FindFirstChild("currentSection")
        local data = getData()
        local visited = data and data:FindFirstChild("visitedSections")
        local completed = visited and string.find(visited.Value, ";" .. name .. ";", 1, true)
        if current and (current.Value == index or (current.Value == index + 1 and completed)) then
            state.ConfirmedStages = state.ConfirmedStages + 1
            state.LastConfirmed = index
            return
        end
        if elapsed >= 0.35 and not triedPlatform then
            local section = sectionAt(snapshot, index)
            local stop = section and section:FindFirstChild("stop")
            if stop and stop:IsA("BasePart") then
                triedPlatform = true
                moveTo(stop.Position + Vector3.new(0, 2, 0), token, round, snapshot)
            end
        end
        elapsed = elapsed + step(token, round, snapshot)
    end
    error("Section " .. index .. " not confirmed", 0)
end

local function finishRoute(token, round, snapshot)
    local finish = snapshot.Sections:FindFirstChild("finish")
    local glow = finish and finish:FindFirstChild("FinishGlow")
    local exitModel = finish and finish:FindFirstChild("exit")
    local carpet = exitModel and exitModel:FindFirstChild("carpet")
    assert(glow and glow:IsA("BasePart") and carpet and carpet:IsA("BasePart"), "Finish not loaded")
    local outward = Vector3.new(glow.Position.X - carpet.Position.X, 0, glow.Position.Z - carpet.Position.Z)
    assert(outward.Magnitude > 1, "Invalid finish orientation")
    outward = outward.Unit
    local y = carpet.Position.Y + halfHeight(carpet) + math.max(3, humanoid.HipHeight + root.Size.Y / 2)
    local function atHeight(position) return Vector3.new(position.X, y, position.Z) end
    moveTo(atHeight(snapshot.Route[#snapshot.Route].Position), token, round, snapshot)
    moveTo(atHeight(carpet.Position), token, round, snapshot)
    moveTo(atHeight(glow.Position - outward * 6.5), token, round, snapshot)
    moveTo(atHeight(glow.Position - outward * 1.0), token, round, snapshot)
    local elapsed = 0
    while not round.Completed and elapsed < 10 do elapsed = elapsed + step(token, round, snapshot) end
    if not round.Completed then error("Finish reached without server victory", 0) end
end

local function markCompleted(round, fromEvent)
    if not round or currentRound ~= round or isRegenerating()
        or workspace:FindFirstChild("tower") ~= round.Snapshot.Tower then return end
    if not round.Completed then
        round.Completed = true
        if fromEvent then state.RoundsCompleted = state.RoundsCompleted + 1 end
        state.FinishedAt = os.clock()
    end
    state.Won = true
end
local function run(token, round, snapshot)
    local route = snapshot.Route
    state.Total = #route
    local first = 1
    for index, row in ipairs(route) do if root.Position.Y >= row.Bottom then first = index end end
    local current = character:FindFirstChild("currentSection")
    if current and current.Value >= 1 then first = math.min(first, current.Value) end
    for index = first, #route do
        check(token, round, snapshot)
        state.Stage = index
        state.Status = "Ascending " .. index .. "/" .. #route .. " - " .. route[index].Name
        local section = sectionAt(snapshot, index)
        local elapsed = 0
        while not section and elapsed < 5 do
            elapsed = elapsed + step(token, round, snapshot)
            section = sectionAt(snapshot, index)
        end
        assert(section, "Section platforms are not streamed in")
        local entry, exitPlatform = section:FindFirstChild("start"), section:FindFirstChild("stop")
        if entry and entry:IsA("BasePart") then
            landOn(entry, token, round, snapshot)
        elseif exitPlatform and exitPlatform:IsA("BasePart") then
            landOn(exitPlatform, token, round, snapshot)
        else
            local y = math.max(root.Position.Y, route[index].Bottom + 4)
            moveTo(Vector3.new(route[index].Position.X, y, route[index].Position.Z), token, round, snapshot)
        end
        acknowledge(index, token, round, snapshot)
        if exitPlatform and exitPlatform:IsA("BasePart") and exitPlatform ~= entry and entry then
            landOn(exitPlatform, token, round, snapshot)
        end
    end
    state.Phase, state.Status = "Finish", "Entering the finish"
    finishRoute(token, round, snapshot)
    state.Phase, state.Status = "WaitingNextRound", "Victory confirmed; waiting for the next round"
end

local function launch(round)
    generation = generation + 1
    local token, snapshot = generation, round.Snapshot
    local ok, err = pcall(bindCharacter)
    if not ok then state.Error = tostring(err) nextRetry = os.clock() + 1 return end
    protect()
    if not round.Started then round.Started = true state.RoundsStarted = state.RoundsStarted + 1 end
    round.Attempts = round.Attempts + 1
    state.Attempts = state.Attempts + 1
    state.RetryCount = round.Failures
    state.Running, state.Won = true, false
    state.Error, state.LastConfirmed, state.FinishedAt = nil, nil, nil
    state.ConfirmedStages, state.StartedAt, state.Phase = 0, os.clock(), "Ascending"
    task.spawn(function()
        local succeeded, failure = pcall(run, token, round, snapshot)
        if not state.Active or generation ~= token or currentRound ~= round then return end
        state.Running = false
        if succeeded then return end
        state.Error = tostring(failure)
        state.LastError = state.Error
        if round.Completed then
            state.Phase, state.Status = "WaitingNextRound", "Victory confirmed; waiting for the next round"
            return
        end
        if state.Error == "Round changed" or state.Error == "Character changed" or state.Error == "Character anchored" then
            releaseCharacter()
            nextRetry = os.clock() + 1
            state.Phase, state.Status = "Waiting", "Waiting for tower / character"
            return
        end
        round.Failures = round.Failures + 1
        state.RetryCount = round.Failures
        if state.Error == "Position correction" or string.find(state.Error, "not confirmed", 1, true) then
            state.Speed = math.max(10, state.Speed * 0.8)
        end
        nextRetry = os.clock() + 3
        state.Phase = "Retry"
        state.Status = round.Failures <= state.MaxRetries and "Retrying shortly: " .. state.Error
            or "Retry limit; waiting for next round: " .. state.Error
    end)
end

local function beginRound(snapshot)
    local hadRound = state.RoundSerial > 0
    cancelWorker()
    state.RoundSerial = state.RoundSerial + 1
    currentRound = {
        Snapshot = snapshot, StableAt = os.clock() + 3,
        Completed = false, Attempts = 0, Failures = 0, Started = false, AwaitLobby = hadRound,
    }
    pendingRound = false
    nextRetry = 0
    state.Won, state.Error, state.LastConfirmed, state.FinishedAt = false, nil, nil, nil
    state.Stage, state.Total, state.RetryCount = 0, #snapshot.Route, 0
    state.DeathsThisRound = 0
    state.Phase, state.Status = "Waiting", "New tower; waiting for generation / respawn"
    local round = currentRound
    local fetch = gameRemotes and gameRemotes:FindFirstChild("fetchRoundWinners")
    if fetch and fetch:IsA("RemoteFunction") then
        round.CheckingWinners = true
        round.WinnerCheckDeadline = os.clock() + 3
        task.spawn(function()
            local ok, winners = pcall(function() return fetch:InvokeServer() end)
            if state.Active and currentRound == round then
                round.CheckingWinners = false
                if ok and type(winners) == "table" then
                    for _, winner in pairs(winners) do
                        if winner == player then markCompleted(round, false) break end
                    end
                end
            end
        end)
    end
end

function state.ExportStatistics()
    local credits = {}
    for _, credit in ipairs(incomeCredits) do
        table.insert(credits, { Time = credit.Time, Amount = credit.Amount })
    end
    return {
        CoinsEarned = state.CoinsEarned, ActiveSeconds = state.ActiveSeconds,
        ElapsedSeconds = state.ElapsedSeconds,
        RoundsCompleted = state.RoundsCompleted, CoinBalance = lastCoinBalance,
        CoinSource = state.CoinSource,
        HistoryStartSeconds = incomeHistoryStartSeconds, Credits = credits,
        SmoothedRate = smoothedIncomeRate, LastRateTime = lastIncomeRateTime,
    }
end
function state.Start()
    if not state.Active then return end
    updateStatsClock()
    state.Enabled, state.Paused = true, false
    if currentRound and not currentRound.Completed and not state.Running then currentRound.Failures = 0 end
    nextRetry = 0
    refreshControls()
end
function state.Stop()
    if not state.Active then return end
    updateStatsClock()
    state.Paused = true
    cancelWorker()
    refreshControls()
end
function state.Toggle()
    if not state.Active then return end
    if not state.Enabled or state.Paused then state.Start()
    else state.Stop() end
end
function state.SetSpeed(value)
    state.Speed = number(value, state.Speed, 10, 120)
    return state.Speed
end
function state.PokeIdle()
    if not state.Active or not state.AntiAFK then return false end
    local ok, err = pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    if ok then
        state.LastAntiAFK, state.AntiAFKError = os.clock(), nil
        state.AntiAFKCount = state.AntiAFKCount + 1
    else state.AntiAFKError = tostring(err) end
    return ok, err
end
function state.Unload()
    if not state.Active then return end
    updateStatsClock()
    state.Active, state.Enabled = false, false
    cancelWorker()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    connections = {}
    refreshControls = function() end
    if coinConnection then coinConnection:Disconnect() coinConnection = nil end
    if controlGui then controlGui:Destroy() controlGui = nil end
    for part, original in pairs(savedHazards) do if part.Parent then part.CanTouch = original end end
    savedHazards = {}
    if ownFlag then ownFlag:Destroy() ownFlag = nil end
    state.Phase, state.Status = "Unloaded", "Unloaded; properties restored"
end

local function createControls()
    local playerGui = player:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui did not load.")
    local colors = {
        Surface = Color3.fromRGB(16, 16, 18), Text = Color3.fromRGB(240, 240, 240),
        Title = Color3.fromRGB(41, 74, 122), Border = Color3.fromRGB(79, 79, 89),
        Row = Color3.fromRGB(29, 29, 32), RowAlternate = Color3.fromRGB(23, 23, 26),
        Muted = Color3.fromRGB(164, 164, 173), Accent = Color3.fromRGB(37, 76, 124),
        Button = Color3.fromRGB(49, 49, 55), Paused = Color3.fromRGB(232, 198, 109),
    }
    local titleHeight = Input.TouchEnabled and 44 or 30
    local buttonHeight = Input.TouchEnabled and 44 or 32
    local expandedHeight = titleHeight + buttonHeight + 210
    local collapsed = false
    local function make(className, parent, properties)
        local object = Instance.new(className)
        for key, value in pairs(properties) do object[key] = value end
        object.Parent = parent
        return object
    end
    controlGui = Instance.new("ScreenGui")
    controlGui.Name = "TowerAscentControls"
    controlGui.ResetOnSpawn = false
    controlGui.DisplayOrder = 20
    controlGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    controlGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    controlGui.Parent = playerGui
    local bounds = make("Frame", controlGui, {
        Name = "SafeArea", Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, BorderSizePixel = 0,
    })
    local panel = make("Frame", bounds, {
        Name = "Panel", Size = UDim2.fromOffset(320, expandedHeight),
        BackgroundColor3 = colors.Surface, BorderSizePixel = 0, Active = true,
    })
    make("UIStroke", panel, { Color = colors.Border, Thickness = 1 })
    local titleBar = make("Frame", panel, {
        Name = "TitleBar", Size = UDim2.new(1, 0, 0, titleHeight),
        BackgroundColor3 = colors.Title, BorderSizePixel = 0,
    })
    local collapse = make("TextButton", titleBar, {
        Name = "Collapse", Size = UDim2.fromOffset(titleHeight, titleHeight),
        BackgroundColor3 = colors.Title, BorderSizePixel = 0,
        Text = "v", TextSize = 16, Font = Enum.Font.Code, TextColor3 = colors.Text,
        AutoButtonColor = true,
    })
    local header = make("TextButton", titleBar, {
        Name = "DragHandle", Position = UDim2.fromOffset(titleHeight, 0),
        Size = UDim2.new(1, -titleHeight * 2, 1, 0),
        BackgroundTransparency = 1, AutoButtonColor = false, Selectable = false,
        Text = "Tower of Farm", TextSize = 15,
        Font = Enum.Font.Code, TextColor3 = colors.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local close = make("TextButton", titleBar, {
        Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
        Size = UDim2.fromOffset(titleHeight, titleHeight),
        BackgroundColor3 = colors.Title, BorderSizePixel = 0,
        Text = "x", TextSize = 16, Font = Enum.Font.Code, TextColor3 = colors.Text,
        AutoButtonColor = true,
    })
    local body = make("ScrollingFrame", panel, {
        Name = "Body", Position = UDim2.fromOffset(8, titleHeight + 8),
        Size = UDim2.new(1, -16, 1, -titleHeight - 16), BackgroundTransparency = 1,
        BorderSizePixel = 0, CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 2, ScrollBarImageColor3 = colors.Border,
    })
    make("UIListLayout", body, {
        Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local function separator(order)
        make("Frame", body, {
            Name = "Separator", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 1),
            BorderSizePixel = 0, BackgroundColor3 = colors.Border,
        })
    end
    local statusLabel = make("TextLabel", body, {
        Name = "Status", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1, Text = "", TextSize = 14,
        Font = Enum.Font.Code, TextColor3 = colors.Muted,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    separator(2)
    local stats = make("Frame", body, {
        Name = "Stats", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 104),
        BackgroundTransparency = 1,
    })
    make("UIListLayout", stats, {
        Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local function stat(name, label, order)
        local cell = make("Frame", stats, {
            Name = name, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = order % 2 == 1 and colors.Row or colors.RowAlternate,
            BorderSizePixel = 0,
        })
        make("TextLabel", cell, {
            Name = "Label", Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0.65, -6, 1, 0),
            BackgroundTransparency = 1, Text = label, TextSize = 14,
            Font = Enum.Font.Code, TextColor3 = colors.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        return make("TextLabel", cell, {
            Name = "Value", Position = UDim2.fromScale(0.65, 0), Size = UDim2.new(0.35, -6, 1, 0),
            BackgroundTransparency = 1, Text = "0", TextSize = 14,
            Font = Enum.Font.Code, TextColor3 = colors.Text,
            TextXAlignment = Enum.TextXAlignment.Right,
        })
    end
    local winsValue = stat("Wins", "Wins", 1)
    local earnedValue = stat("Earned", "Earned (coins)", 2)
    local rateValue = stat("Hourly", "Est. coins / hour", 3)
    local elapsedValue = stat("Elapsed", "Elapsed", 4)
    local function compact(value)
        if value >= 1e9 then return string.format("%.1fb", value / 1e9) end
        if value >= 1e6 then return string.format("%.1fm", value / 1e6) end
        if value >= 1e3 then return string.format("%.1fk", value / 1e3) end
        return string.format("%.0f", value)
    end
    separator(4)
    local actions = make("Frame", body, {
        Name = "Actions", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, buttonHeight),
        BackgroundTransparency = 1,
    })
    make("UIListLayout", actions, {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local function button(name, text, order, color)
        local result = make("TextButton", actions, {
            Name = name, Text = text, LayoutOrder = order,
            Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = color,
            BorderSizePixel = 0, TextColor3 = colors.Text,
            Font = Enum.Font.Code, TextSize = 14, AutoButtonColor = true,
        })
        return result
    end
    local toggle = button("PauseResume", "Pause", 1, colors.Accent)
    local unload = button("Unload", "Stop script", 2, colors.Button)
    local hint = make("TextLabel", body, {
        Name = "Hint", LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1, Text = "", TextSize = 12,
        Font = Enum.Font.Code, TextColor3 = colors.Muted,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local footer = make("TextLabel", body, {
        Name = "Community", LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1, Text = "t.me/arceusxcommunity", TextSize = 12,
        Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(139, 183, 232),
        TextXAlignment = Enum.TextXAlignment.Left, RichText = false,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    task.spawn(function()
        local ok, text = pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
        end)
        if not ok or type(text) ~= "string" or not state.Active or not footer.Parent then return end
        text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]+", " ")
        if #text > 0 and #text <= 200 then footer.Text = text end
    end)
    local phaseLabels = {
        Waiting = "Waiting for tower / character", Regenerating = "Generating a new tower",
        Finish = "Entering the finish", WaitingNextRound = "Waiting for the next round",
        Retry = "Retrying shortly",
    }
    refreshControls = function()
        if not state.Active then return end
        local paused = state.Paused or not state.Enabled
        toggle.Text = not state.Enabled and "Start" or (paused and "Resume" or "Pause")
        statusLabel.TextColor3 = paused and colors.Paused or colors.Muted
        winsValue.Text = compact(state.RoundsCompleted)
        earnedValue.Text = state.CurrencyReady and compact(state.CoinsEarned) or "--"
        rateValue.Text = state.CoinsPerHour and compact(state.CoinsPerHour) or "--"
        local elapsed = math.floor(state.ElapsedSeconds)
        elapsedValue.Text = string.format("%02d:%02d:%02d",
            math.floor(elapsed / 3600), math.floor(elapsed / 60) % 60, elapsed % 60)
        if state.IncomeRateStatus == "WaitingForData" then hint.Text = "Hourly rate: waiting for coin data"
        elseif state.IncomeRateStatus == "WaitingForPayout" then hint.Text = "Hourly rate: waiting for first payout"
        elseif state.IncomeRateStatus == "Collecting" then
            hint.Text = string.format("Hourly rate: sampling (%ds left)", math.max(0, math.ceil(incomeWarmupSeconds - state.ActiveSeconds)))
        elseif state.IncomeRateStatus == "SessionSample" then hint.Text = "Hourly rate: early, smoothed estimate"
        else hint.Text = "Hourly rate: last 10 active minutes" end
        if not state.Enabled then statusLabel.Text = "Ready to start"
        elseif state.Paused then statusLabel.Text = string.format("Paused - stage %d / %d", state.Stage, state.Total)
        elseif state.Phase == "Ascending" then
            statusLabel.Text = string.format("Climbing - stage %d / %d", state.Stage, state.Total)
        elseif state.Phase == "Retry" and state.RetryCount > state.MaxRetries then
            statusLabel.Text = "Retry limit - waiting for next tower"
        else statusLabel.Text = phaseLabels[state.Phase] or "Waiting" end
    end
    connect(toggle.Activated, function()
        if state.Active then state.Toggle() end
    end)
    local function stopScript()
        if not state.Active then return end
        state.Unload()
    end
    connect(unload.Activated, stopScript)
    connect(close.Activated, stopScript)

    local dragInput, dragStart, panelStart
    local positioned = false
    local function endDrag()
        dragInput, dragStart, panelStart = nil, nil, nil
    end
    local function placePanel(position)
        local area, size = bounds.AbsoluteSize, panel.Size
        local maxX = math.max(0, area.X - size.X.Offset - 12)
        local maxY = math.max(0, area.Y - size.Y.Offset - 12)
        panel.Position = UDim2.fromOffset(
            math.clamp(position.X, math.min(12, maxX), maxX),
            math.clamp(position.Y, math.min(12, maxY), maxY))
    end
    local function fitPanel()
        if not state.Active then return end
        local area = bounds.AbsoluteSize
        if area.X <= 0 or area.Y <= 0 then return end
        endDrag()
        panel.Size = UDim2.fromOffset(math.min(320, math.max(0, area.X - 24)),
            collapsed and titleHeight or math.min(expandedHeight, math.max(titleHeight + 40, area.Y - 24)))
        local position = positioned and Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
            or Vector2.new(12, math.floor(area.Y * 0.25))
        placePanel(position)
        positioned = true
    end
    connect(collapse.Activated, function()
        if not state.Active then return end
        collapsed = not collapsed
        collapse.Text = collapsed and ">" or "v"
        body.Visible = not collapsed
        fitPanel()
    end)
    connect(header.InputBegan, function(input)
        if dragInput or not state.Active then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragInput = input
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        panelStart = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
    end)
    connect(Input.InputChanged, function(input)
        if not dragInput then return end
        local mouseMove = dragInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement
        if input == dragInput or mouseMove then
            placePanel(panelStart + Vector2.new(input.Position.X, input.Position.Y) - dragStart)
        end
    end)
    connect(Input.InputEnded, function(input)
        if input == dragInput or (dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseButton1) then endDrag() end
    end)
    connect(Input.WindowFocusReleased, endDrag)
    connect(bounds:GetPropertyChangedSignal("AbsoluteSize"), fitPanel)
    fitPanel()
    refreshControls()
end

updateEconomyStats()
local controlsReady, controlsError = pcall(createControls)
if not controlsReady then
    state.Unload()
    error("Could not create Tower of Farm controls: " .. tostring(controlsError), 0)
end

protect()
for _, part in ipairs(CollectionService:GetTagged("KillBrick")) do protectHazard(part) end
connect(CollectionService:GetInstanceAddedSignal("KillBrick"), protectHazard)
connect(CollectionService:GetInstanceRemovedSignal("KillBrick"), function(part)
    local original = savedHazards[part]
    if original ~= nil then
        if part.Parent then part.CanTouch = original end
        savedHazards[part] = nil
    end
end)
connect(player.Idled, function()
    if state.Active and state.AntiAFK then
        state.PokeIdle()
    end
end)
connect(RunService.Stepped, function()
    if velocity and root and root.Parent then
        for part, original in pairs(savedParts) do
            if part.Parent then part.CanCollide = grounding and original or false end
        end
    end
end)
connect(player.CharacterRemoving, function(c)
    recordCharacterFailure(c, "Character removed during ascent")
    cancelWorker()
    nextRetry = os.clock() + 1
end)
connect(player.CharacterAdded, function()
    cancelWorker()
    nextRetry = os.clock() + 1
    state.Phase, state.Status = "Waiting", "Respawned; auto-farm will continue"
end)
if regenerating then
    connect(regenerating.Changed, function(value)
        if value then
            pendingRound, sawRegeneration = true, true
            cancelWorker()
            state.Won = false
            state.Phase, state.Status = "Regenerating", "Waiting for the next tower"
        end
    end)
end
local wonEvent = gameRemotes and gameRemotes:FindFirstChild("playerWonEvent")
assert(wonEvent and wonEvent:IsA("RemoteEvent"), "Server victory event is unavailable.")
connect(wonEvent.OnClientEvent, function(winner)
    if winner == player then markCompleted(currentRound, true) end
end)

local function supervise()
    protect()
    if isRegenerating() then
        if not sawRegeneration then pendingRound = true cancelWorker() end
        sawRegeneration = true
        state.Phase, state.Status = "Regenerating", "Waiting for the next tower"
        return
    end
    sawRegeneration = false
    local snapshot = snapshotTower()
    if not snapshot then
        if state.Running then cancelWorker() end
        if currentRound then currentRound.StableAt = os.clock() + 1 end
        state.Phase, state.Status = "Waiting", "Waiting for complete tower data"
        return
    end
    if not currentRound or snapshot.Tower ~= currentRound.Snapshot.Tower or pendingRound then
        beginRound(snapshot)
    elseif not sameGeometry(currentRound.Snapshot, snapshot) then
        cancelWorker()
        currentRound.Snapshot = snapshot
        currentRound.StableAt = os.clock() + 1
        currentRound.Attempts = 0
    end
    local round = currentRound
    if not state.Enabled or state.Paused then return end
    if round.Completed then
        state.Won = true
        if not state.Running then state.Phase, state.Status = "WaitingNextRound", "Victory confirmed; waiting for the next round" end
        return
    end
    if not state.AutoFarm and state.RoundsStarted > 0 and not round.Started then return end
    if state.Running or os.clock() < round.StableAt or os.clock() < nextRetry
        or round.Failures > state.MaxRetries then return end
    if round.CheckingWinners and os.clock() < round.WinnerCheckDeadline then return end
    local _, _, readyRoot = readyCharacter()
    if not readyRoot then state.Phase, state.Status = "Waiting", "Waiting for character" return end
    if round.AwaitLobby then
        if readyRoot.Position.Y > snapshot.Route[1].Top + 12 then
            state.Phase, state.Status = "Waiting", "Waiting for the server to return the character to the lobby"
            return
        end
        round.AwaitLobby = false
    end
    launch(round)
end

task.spawn(function()
    while state.Active do
        local ok, err = pcall(function()
            updateEconomyStats()
            supervise()
        end)
        if not ok then
            cancelWorker()
            state.Error, state.LastError = tostring(err), tostring(err)
            state.Phase, state.Status = "Waiting", "Waiting after error: " .. tostring(err)
            nextRetry = os.clock() + 3
        end
        refreshControls()
        task.wait(0.25)
    end
end)

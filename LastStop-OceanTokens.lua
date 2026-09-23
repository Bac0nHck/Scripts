--[[
getgenv().settings = {
    webhook = "",
    performance = true,
}
]]
local function queueFarmTeleport(options, statistics)
    local queue_on_teleport = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    if type(queue_on_teleport) ~= "function" then
        return false, "Automatic restart requires queue_on_teleport support."
    end
    local continuation = string.format([[
getgenv().OceanCoinFarmResume = {
    Settings = { webhook = %s, performance = %s },
    TotalCollected = %s,
    CompletedRuns = %s,
    StartedAt = %s,
}
]], string.format("%q", options.webhook), tostring(options.performance),
        tostring(statistics.TotalCollected), tostring(statistics.CompletedRuns), tostring(statistics.StartedAt)) .. [[
loadstring(game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Scripts/refs/heads/main/LastStop-OceanTokens.lua"))()
]]
    return pcall(function()
        queue_on_teleport(continuation)
    end)
end

local function createPerformanceController(context)
    local lighting = game:GetService("Lighting")
    local terrain = workspace.Terrain
    local runService = game:GetService("RunService")
    local originals = setmetatable({}, { __mode = "k" })
    local listeners = {}
    local pending = {}
    local pendingIndex = 1
    local generation = 0
    local enabled = false
    local renderingDisabled = false
    local selector = "BasePart, Decal, Texture, SpecialMesh, SurfaceAppearance, ParticleEmitter, Trail, Beam, Smoke, Fire, Sparkles, Light, PostEffect, Atmosphere, Sky, Clouds, BillboardGui, SurfaceGui"

    local function setProperty(object, property, value)
        pcall(function()
            local current = object[property]
            if current == value then
                return
            end
            local saved = originals[object]
            if not saved then
                saved = {}
                originals[object] = saved
            end
            if saved[property] == nil then
                saved[property] = current
            end
            object[property] = value
        end)
    end

    local function optimize(object)
        if object:IsA("BasePart") then
            setProperty(object, "Material", Enum.Material.SmoothPlastic)
            setProperty(object, "MaterialVariant", "")
            setProperty(object, "Reflectance", 0)
            setProperty(object, "CastShadow", false)
            if object:IsA("MeshPart") then
                setProperty(object, "TextureID", "")
            end
        elseif object:IsA("Decal") or object:IsA("Texture") then
            setProperty(object, "Texture", "")
            setProperty(object, "Transparency", 1)
        elseif object:IsA("SpecialMesh") then
            setProperty(object, "TextureId", "")
        elseif object:IsA("SurfaceAppearance") then
            for _, property in ipairs({ "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" }) do
                setProperty(object, property, "")
            end
        elseif object:IsA("Atmosphere") then
            setProperty(object, "Density", 0)
            setProperty(object, "Haze", 0)
            setProperty(object, "Glare", 0)
        elseif object:IsA("Sky") then
            for _, property in ipairs({ "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId" }) do
                setProperty(object, property, "")
            end
            setProperty(object, "CelestialBodiesShown", false)
            setProperty(object, "StarCount", 0)
        elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles")
            or object:IsA("Light") or object:IsA("PostEffect") or object:IsA("Clouds")
            or object:IsA("BillboardGui") or object:IsA("SurfaceGui") then
            setProperty(object, "Enabled", false)
            if object:IsA("ParticleEmitter") then
                setProperty(object, "Rate", 0)
            end
        end
    end

    local function applyGlobalSettings()
        setProperty(lighting, "GlobalShadows", false)
        setProperty(lighting, "EnvironmentDiffuseScale", 0)
        setProperty(lighting, "EnvironmentSpecularScale", 0)
        setProperty(lighting, "FogEnd", 1000000)
        setProperty(terrain, "WaterWaveSize", 0)
        setProperty(terrain, "WaterWaveSpeed", 0)
        setProperty(terrain, "WaterReflectance", 0)
        setProperty(terrain, "WaterTransparency", 1)
        pcall(function()
            setProperty(UserSettings():GetService("UserGameSettings"), "SavedQualityLevel", Enum.SavedQualitySetting.QualityLevel1)
        end)
    end

    local function restore()
        enabled = false
        generation = generation + 1
        for _, connection in ipairs(listeners) do
            connection:Disconnect()
        end
        listeners = {}
        pending = {}
        pendingIndex = 1
        if renderingDisabled then
            pcall(function()
                runService:Set3dRenderingEnabled(true)
            end)
            renderingDisabled = false
        end
        for object, properties in pairs(originals) do
            for property, value in pairs(properties) do
                pcall(function()
                    object[property] = value
                end)
            end
        end
        originals = setmetatable({}, { __mode = "k" })
        context.State.PerformanceEnabled = false
        context.State.RenderingDisabled = false
    end

    local function setEnabled(value)
        value = value == true
        if value == enabled then
            return
        end
        if not value then
            restore()
            return
        end
        enabled = true
        generation = generation + 1
        local currentGeneration = generation
        context.State.PerformanceEnabled = true
        applyGlobalSettings()
        renderingDisabled = pcall(function()
            runService:Set3dRenderingEnabled(false)
        end)
        context.State.RenderingDisabled = renderingDisabled
        local function enqueue(object)
            if enabled and generation == currentGeneration then
                pending[#pending + 1] = object
            end
        end
        for _, root in ipairs({ workspace, lighting }) do
            listeners[#listeners + 1] = root.DescendantAdded:Connect(enqueue)
            local ok, objects = pcall(function()
                return root:QueryDescendants(selector)
            end)
            if ok then
                for _, object in ipairs(objects) do
                    enqueue(object)
                end
            end
        end
        task.spawn(function()
            local lastRefresh = os.clock()
            while enabled and generation == currentGeneration and context.State.Running do
                local deadline = os.clock() + 0.003
                local processed = 0
                while pendingIndex <= #pending and processed < 100 and os.clock() < deadline do
                    local object = pending[pendingIndex]
                    pending[pendingIndex] = false
                    pendingIndex = pendingIndex + 1
                    processed = processed + 1
                    if object and object.Parent then
                        pcall(optimize, object)
                    end
                end
                if pendingIndex > #pending then
                    pending = {}
                    pendingIndex = 1
                end
                if os.clock() - lastRefresh >= 2 then
                    applyGlobalSettings()
                    lastRefresh = os.clock()
                end
                task.wait(#pending > 0 and 0.03 or 0.2)
            end
        end)
    end

    return { SetEnabled = setEnabled, Restore = restore }
end

local function createReporter(context)
    local httpService = game:GetService("HttpService")
    local state = context.State
    local reported = false

    local function send(outcome)
        if reported then
            return
        end
        reported = true
        local options = context.GetOptions()
        local url = options.webhook:match("^%s*(.-)%s*$")
        if url == "" then
            state.WebhookStatus = "Disabled"
            return
        end
        if not url:match("^https://[^%s/]+/[^%s]+$") then
            state.WebhookStatus = "Invalid webhook URL"
            return
        end
        local requestFunction = context.Request()
        if type(requestFunction) ~= "function" then
            state.WebhookStatus = "HTTP requests are unavailable"
            return
        end
        if url:match("^https://[%w.]*discord%.com/api/") or url:match("^https://[%w.]*discordapp%.com/api/") then
            url = url:gsub("([?&])wait=[^&]*", "%1wait=true")
            if not url:find("[?&]wait=") then
                url = url .. (url:find("?", 1, true) and "&" or "?") .. "wait=true"
            end
        end
        local elapsed = math.max(1, os.time() - state.StartedAt)
        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor(elapsed / 60) % 60
        local seconds = elapsed % 60
        local payload = {
            username = "Ocean Coin Farm",
            embeds = {{
                title = "Last Stop - Ocean Coins",
                description = outcome,
                color = 4364287,
                fields = {
                    { name = "Collected this run", value = tostring(state.Collected), inline = true },
                    { name = "Collected this session", value = tostring(state.TotalCollected), inline = true },
                    { name = "Ocean Coin balance", value = tostring(state.Balance), inline = true },
                    { name = "Completed runs", value = tostring(state.CompletedRuns), inline = true },
                    { name = "Session time", value = string.format("%02d:%02d:%02d", hours, minutes, seconds), inline = true },
                    { name = "Coins per minute", value = string.format("%.1f", state.TotalCollected * 60 / elapsed), inline = true }
                },
                footer = { text = "Ocean Coin Farm" }
            }}
        }
        local encoded, body = pcall(function()
            return httpService:JSONEncode(payload)
        end)
        if not encoded then
            state.WebhookStatus = "Could not encode the report"
            return
        end
        state.WebhookStatus = "Sending"
        local finished = false
        local expired = false
        local deadline = os.clock() + 7
        task.spawn(function()
            local function finish(status)
                if not expired then
                    state.WebhookStatus = status
                end
                finished = true
            end
            for attempt = 1, 2 do
                if expired or not state.Running then
                    finish("Cancelled")
                    return
                end
                local ok, response = pcall(requestFunction, {
                    Url = url,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = body,
                    Timeout = 5
                })
                if not ok or type(response) ~= "table" then
                    finish("Request failed")
                    return
                end
                local status = tonumber(response.StatusCode or response.Status)
                if status and status >= 200 and status < 300 then
                    finish("Sent")
                    return
                end
                if status == 429 and attempt == 1 then
                    local headers = response.Headers or {}
                    local retryAfter = tonumber(headers["Retry-After"] or headers["retry-after"])
                    local parsed, details = pcall(function()
                        return httpService:JSONDecode(response.Body or "")
                    end)
                    if parsed and type(details) == "table" then
                        retryAfter = tonumber(details.retry_after) or retryAfter
                    end
                    retryAfter = math.max(0.1, retryAfter or 1)
                    if retryAfter >= deadline - os.clock() - 1 then
                        finish("Rate limited")
                        return
                    end
                    task.wait(retryAfter)
                else
                    finish(status and ("HTTP " .. tostring(status)) or "Invalid HTTP response")
                    return
                end
            end
        end)
        while not finished and state.Running and os.clock() < deadline do
            task.wait(0.05)
        end
        if not finished then
            expired = true
            state.WebhookStatus = state.Running and "Request timed out" or "Cancelled"
        end
    end

    return { Send = send }
end

local version = "2026.09.23.6"
local settings = {
    AutoRestart = true,
    TravelHeight = 100,
    RouteStep = 640,
    LoadDelay = 1.2,
    ApproachDelay = 0.5,
    CollectDelay = 0.55,
    CollectOffset = -3,
    MinimumHealth = 75,
    RetryLimit = 2,
    LobbyPlaceId = 85967844112283,
    GamePlaceId = 122776220269735
}

local environment = getgenv and getgenv() or _G
local carried = environment.OceanCoinFarmResume
environment.OceanCoinFarmResume = nil
if type(carried) ~= "table" then
    carried = nil
end
if carried and type(carried.Settings) == "table" then
    environment.settings = carried.Settings
end
if type(environment.settings) ~= "table" then
    environment.settings = { webhook = "", performance = true }
end
local function getOptions()
    local options = type(environment.settings) == "table" and environment.settings or {}
    return {
        webhook = type(options.webhook) == "string" and options.webhook or "",
        performance = options.performance ~= false
    }
end
local previous = environment.OceanCoinFarm
if previous and previous.Running then
    if carried and previous.Version == version then
        return
    end
    previous.Stop()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local player = Players.LocalPlayer
while not player do
    task.wait(0.1)
    player = Players.LocalPlayer
end
local state = {
    Version = version,
    Running = true,
    Status = "Loading",
    Collected = 0,
    TotalCollected = carried and carried.TotalCollected or 0,
    CompletedRuns = carried and carried.CompletedRuns or 0,
    StartedAt = carried and tonumber(carried.StartedAt) or os.time(),
    Balance = 0,
    Health = 0,
    LastError = nil
}
environment.OceanCoinFarm = state
local performance = createPerformanceController({ State = state })
local reporter = createReporter({
    State = state,
    GetOptions = getOptions,
    Request = function()
        return request or http_request or (http and http.request) or (syn and syn.request) or (fluxus and fluxus.request)
    end
})

local connections = {}
local physicsConnection
local characterConnection
local hover
local activeRoot
local originalPosition
local collisionStates = {}

local function releasePhysics(restorePosition)
    if characterConnection then
        characterConnection:Disconnect()
        characterConnection = nil
    end
    if physicsConnection then
        physicsConnection:Disconnect()
        physicsConnection = nil
    end
    if restorePosition and activeRoot and activeRoot.Parent and originalPosition then
        activeRoot.CFrame = originalPosition
        activeRoot.AssemblyLinearVelocity = Vector3.zero
        activeRoot.AssemblyAngularVelocity = Vector3.zero
    end
    if hover then
        hover:Destroy()
        hover = nil
    end
    for part, value in pairs(collisionStates) do
        if part.Parent then
            part.CanCollide = value
        end
    end
    collisionStates = {}
    activeRoot = nil
end

function state.Stop()
    state.Running = false
    state.Status = "Stopped"
    releasePhysics(true)
    performance.Restore()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    connections = {}
end

function state.SetPerformance(value)
    if type(environment.settings) ~= "table" then
        environment.settings = { webhook = "", performance = true }
    end
    environment.settings.performance = value == true
    performance.SetEnabled(state.Running and value == true)
end

local function pause(duration)
    local deadline = os.clock() + duration
    repeat
        if not state.Running then
            return false
        end
        task.wait(math.min(0.1, math.max(0, deadline - os.clock())))
    until os.clock() >= deadline
    return state.Running
end

local function waitUntil(callback, timeout)
    local deadline = os.clock() + timeout
    repeat
        if not state.Running then
            return nil
        end
        local ok, value = pcall(callback)
        if ok and value then
            return value
        end
        if not pause(0.2) then
            return nil
        end
    until os.clock() >= deadline
    return nil
end

local function queueContinuation()
    if state.TeleportQueued then
        return true
    end
    local ok, err = queueFarmTeleport(getOptions(), state)
    if not ok then
        state.LastError = tostring(err)
        return false
    end
    state.TeleportQueued = true
    return true
end

table.insert(connections, player.Idled:Connect(function()
    if state.Running then
        pcall(function()
            local virtualUser = game:GetService("VirtualUser")
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.zero)
        end)
    end
end))

local function returnToLobby()
    releasePhysics(true)
    if not state.Running then
        return
    end
    if not settings.AutoRestart or not queueContinuation() then
        state.Stop()
        state.Status = "Complete"
        if state.LastError then
            warn("Ocean Coin Farm: " .. state.LastError)
        end
        return
    end
    state.Status = "Returning to lobby"
    for attempt = 1, 3 do
        if not state.Running then
            return
        end
        local ok, err = pcall(function()
            TeleportService:Teleport(settings.LobbyPlaceId, player)
        end)
        if not ok then
            state.LastError = tostring(err)
        end
        if not pause(18) then
            return
        end
    end
    error("Could not return to the lobby.")
end

local function runMatch(source)
    if type(fireproximityprompt) ~= "function" then
        error("This executor must support fireproximityprompt.")
    end
    local gameController = require(source.Game.Controllers.GameController)
    local dataController = require(source.Mutual.Controllers.DataController)
    local data = waitUntil(function()
        local replica = gameController.Replica
        return replica and replica.Data.Ready and replica.Data.MapInitialized and replica.Data
    end, 120)
    if not data then
        error("The match did not finish loading.")
    end
    local character = waitUntil(function()
        local current = player.Character
        local humanoid = current and current:FindFirstChildOfClass("Humanoid")
        return humanoid and humanoid.Health > 0 and current:FindFirstChild("HumanoidRootPart") and current
    end, 60)
    if not character then
        returnToLobby()
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    activeRoot = root
    originalPosition = root.CFrame
    local function balance()
        local replica = dataController.Replica
        local wallet = replica and replica.Data.Wallet
        return wallet and tonumber(wallet.OceanToken) or 0
    end
    state.Balance = balance()
    local startingBalance = state.Balance
    local function healthy()
        state.Health = humanoid.Health
        return state.Running and player.Character == character and root.Parent and humanoid.Health >= settings.MinimumHealth
    end
    local function addPart(part)
        if part:IsA("BasePart") then
            if collisionStates[part] == nil then
                collisionStates[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
    for _, part in ipairs(character:GetChildren()) do
        addPart(part)
        for _, child in ipairs(part:GetChildren()) do
            addPart(child)
        end
    end
    characterConnection = character.DescendantAdded:Connect(addPart)
    hover = Instance.new("BodyVelocity")
    hover.Name = "OceanFarmHover"
    hover.MaxForce = Vector3.new(1e8, 1e8, 1e8)
    hover.Velocity = Vector3.zero
    hover.P = 25000
    hover.Parent = root
    physicsConnection = RunService.Stepped:Connect(function()
        for part in pairs(collisionStates) do
            if part.Parent then
                part.CanCollide = false
            end
        end
    end)
    local attempts = {}
    local completed = {}
    local itemContainer = workspace:WaitForChild("ITEM_CONTAINER", 30)
    if not itemContainer then
        error("The item container is unavailable.")
    end
    local function moveTo(position)
        if not healthy() then
            return false
        end
        root.CFrame = CFrame.new(position)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end
    local function collectNearby()
        local deadline = os.clock() + 40
        while healthy() and os.clock() < deadline do
            local chosen
            local nearest = math.huge
            for _, item in ipairs(itemContainer:GetChildren()) do
                if not completed[item.Name] and (attempts[item.Name] or 0) < settings.RetryLimit then
                    local main = item:FindFirstChild("Main")
                    local prompt = main and main:FindFirstChild("CollectOceanTokenPrompt")
                    if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled and main:IsA("BasePart") then
                        local distance = (root.Position - main.Position).Magnitude
                        if distance < nearest then
                            nearest = distance
                            chosen = { Item = item, Main = main, Prompt = prompt }
                        end
                    end
                end
            end
            if not chosen then
                return
            end
            local id = chosen.Item.Name
            attempts[id] = (attempts[id] or 0) + 1
            state.Status = "Collecting Ocean Tokens"
            local before = balance()
            if not moveTo(chosen.Main.Position + Vector3.new(0, settings.CollectOffset, 0)) then
                return
            end
            if not pause(settings.ApproachDelay) or not healthy() then
                return
            end
            if chosen.Prompt:IsDescendantOf(itemContainer) then
                pcall(fireproximityprompt, chosen.Prompt)
            end
            if not pause(settings.CollectDelay) then
                return
            end
            local after = balance()
            state.Balance = after
            if after > before then
                local gained = after - before
                completed[id] = true
                state.Collected = state.Collected + gained
                state.TotalCollected = state.TotalCollected + gained
            elseif not chosen.Prompt:IsDescendantOf(itemContainer) then
                completed[id] = true
            end
        end
    end
    local config = require(ReplicatedStorage.Assets.Game.Game.src.Config)
    local mode = config[data.GameMode] or config.Classic
    local generation = mode and mode.MapGeneration
    if not generation then
        error("Ocean map configuration is unavailable.")
    end
    local chunkSize = generation.ChunkSize or 2048
    local chunks = {}
    for index, biomes in pairs(generation.StaticBiomes or {}) do
        if biomes.Ocean and tonumber(index) then
            table.insert(chunks, tonumber(index))
        end
    end
    table.sort(chunks)
    if #chunks == 0 then
        error("This game mode has no configured ocean region.")
    end
    local direction = (data.EndPosition - data.StartPosition).Unit
    local firstProgress = (chunks[1] - 1) * chunkSize
    local lastProgress = chunks[#chunks] * chunkSize
    local function visit(progress)
        state.Status = "Searching the ocean"
        state.Progress = progress
        local destination = data.StartPosition + direction * progress + Vector3.new(0, settings.TravelHeight, 0)
        if not moveTo(destination) or not pause(settings.LoadDelay) then
            return false
        end
        collectNearby()
        return healthy()
    end
    for progress = firstProgress, lastProgress, settings.RouteStep do
        if not visit(progress) then
            break
        end
    end
    local completedRun = healthy() and visit(lastProgress)
    if completedRun then
        state.CompletedRuns = state.CompletedRuns + 1
    end
    state.Balance = balance()
    state.Health = humanoid.Health
    local confirmedCollected = math.max(state.Collected, state.Balance - startingBalance)
    state.TotalCollected = state.TotalCollected + confirmedCollected - state.Collected
    state.Collected = confirmedCollected
    if state.Running then
        releasePhysics(true)
        reporter.Send(completedRun and "Run completed" or "Run interrupted; returning to the lobby")
    end
    returnToLobby()
end

local function runLobby(source)
    if not queueContinuation() then
        error(state.LastError)
    end
    local controller = require(source.Lobby.Controllers.LobbyController)
    local remotes = source.Mutual.Packages.Knit.Services.LobbyService.RF
    local function ownsLobby(data)
        return data and (data.Owner == player or data.Owner == player.Name or data.Owner == player.UserId)
    end
    local function startLobby()
        local createWindow = player.PlayerGui:FindFirstChild("CreateLobby")
        if createWindow then
            createWindow:Destroy()
        end
        state.Status = "Starting a solo match"
        local ok, result = pcall(function()
            return remotes.LobbyMethod:InvokeServer("Start")
        end)
        if not ok then
            state.LastError = tostring(result)
        end
        state.StartRequested = ok and result ~= false
        state.StartResult = result
    end
    state.Status = "Preparing a solo match"
    local character = waitUntil(function()
        local current = player.Character
        return current and current:FindFirstChild("HumanoidRootPart") and current
    end, 60)
    if not character then
        error("The lobby character did not load.")
    end
    for attempt = 1, 5 do
        if not state.Running then
            return
        end
        local lobby = controller.GetLobby()
        local data = lobby and lobby.Data
        local ready = ownsLobby(data) and data.MaxPlayers == 1 and data.Mode == "Classic"
        if not ready then
            if data and data.Owner then
                pcall(function()
                    remotes.LobbyMethod:InvokeServer("Leave")
                end)
                if not pause(0.8) then
                    return
                end
            end
            local zone = waitUntil(function()
                for _, candidate in ipairs(controller.GetZones()) do
                    if candidate.State == "Empty" and candidate.Zone then
                        return candidate.Zone
                    end
                end
            end, 60)
            if not zone then
                error("No empty lobby is available.")
            end
            character:PivotTo(zone.CFrame + Vector3.new(0, 3, 0))
            local assigned = waitUntil(function()
                return player.PlayerGui:FindFirstChild("CreateLobby")
            end, 12)
            if assigned and state.Running then
                local created = remotes.LobbyMethod:InvokeServer("Create", {
                    MaxPlayers = 1,
                    Private = true,
                    FriendsAllowed = false,
                    Mode = "Classic"
                })
                if created then
                    state.StartRequested = false
                    startLobby()
                    ready = waitUntil(function()
                        local current = controller.GetLobby()
                        local currentData = current and current.Data
                        return ownsLobby(currentData) and currentData.MaxPlayers == 1
                    end, 10)
                end
            end
        end
        if ready then
            if not state.StartRequested then
                startLobby()
            end
            if not pause(45) then
                return
            end
        elseif not pause(2) then
            return
        end
    end
    error("Could not start a solo match.")
end

task.spawn(function()
    local ok, err = xpcall(function()
        state.Status = "Waiting for the game"
        if not game:IsLoaded() then
            game.Loaded:Wait()
        end
        if not state.Running then
            return
        end
        performance.SetEnabled(getOptions().performance)
        task.spawn(function()
            while state.Running do
                performance.SetEnabled(getOptions().performance)
                task.wait(1)
            end
        end)
        state.Status = "Loading game modules"
        local source = waitUntil(function()
            return ReplicatedStorage:FindFirstChild("ClientSource")
        end, 90)
        if not source then
            error("Last Stop did not finish loading.")
        end
        if game.PlaceId == settings.GamePlaceId then
            runMatch(source)
        elseif game.PlaceId == settings.LobbyPlaceId then
            runLobby(source)
        else
            error("This script only supports Last Stop.")
        end
    end, function(message)
        return tostring(message)
    end)
    if not ok and state.Running then
        state.LastError = err
        state.Stop()
        state.Status = "Error"
        warn("Ocean Coin Farm: " .. err)
    end
end)


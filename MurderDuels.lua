local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Environment = getgenv()
local Startup = {}
Environment.__MurderDuelsStartup = Startup

while not game:IsLoaded() or not Players.LocalPlayer do
    task.wait(0.1)
    if Environment.__MurderDuelsStartup ~= Startup then
        return
    end
end

if Environment.__MurderDuelsStartup ~= Startup then
    return
end

local LocalPlayer = Players.LocalPlayer

assert(Drawing and type(Drawing.new) == "function", "Drawing library is required")
assert(type(hookfunction) == "function", "hookfunction is required")
assert(type(filtergc) == "function" or type(getgc) == "function", "filtergc or getgc is required")

local Bridge = Environment.__MurderDuelsAimBridge
if not Bridge then
    Bridge = { Installed = setmetatable({}, { __mode = "k" }) }
    Environment.__MurderDuelsAimBridge = Bridge
end
if Bridge.Runtime then
    Bridge.Runtime:Destroy()
end
Bridge.Magnetism = Bridge.Magnetism or setmetatable({}, { __mode = "k" })

local Runtime = {
    Active = true,
    Connections = {},
    Records = {},
    Drawings = {},
    Target = nil,
    HookCount = 0,
    LastError = nil,
    ThrowContexts = setmetatable({}, { __mode = "k" }),
    PredictionCount = 0,
}
Bridge.Runtime = Runtime
Environment.MurderDuels = Runtime

local EnemyColor = Color3.fromRGB(255, 110, 120)
local White = Color3.fromRGB(245, 247, 250)
local Black = Color3.new(0, 0, 0)
local AimNames = {
    getAimPoint = "World",
    getAdjustedScreenPoint = "Screen",
    getSecuredScreenPoint = "Screen",
    doThrow = "Throw",
}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    Runtime.Connections[#Runtime.Connections + 1] = connection
    return connection
end

local function draw(kind, properties)
    local object = Drawing.new(kind)
    Runtime.Drawings[object] = true
    object.Visible = false
    object.Transparency = 1
    for key, value in pairs(properties) do
        object[key] = value
    end
    return object
end

local function removeDrawing(object)
    Runtime.Drawings[object] = nil
    pcall(function()
        object:Remove()
    end)
end

local function hide(record)
    record.Border.Visible = false
    record.Box.Visible = false
    record.Name.Visible = false
    record.Distance.Visible = false
end

local function addPlayer(player)
    if player == LocalPlayer or Runtime.Records[player] then
        return
    end
    Runtime.Records[player] = {
        Border = draw("Square", { Color = Black, Thickness = 3, Filled = false }),
        Box = draw("Square", { Color = EnemyColor, Thickness = 1, Filled = false }),
        Name = draw("Text", {
            Color = White,
            Size = 15,
            Font = 2,
            Center = true,
            Outline = true,
            OutlineColor = Black,
            Text = player.Name == player.DisplayName and player.Name or player.Name .. " | " .. player.DisplayName,
        }),
        Distance = draw("Text", {
            Color = White,
            Size = 14,
            Font = 2,
            Center = true,
            Outline = true,
            OutlineColor = Black,
            Text = "",
        }),
    }
end

local function removePlayer(player)
    local record = Runtime.Records[player]
    if not record then
        return
    end
    removeDrawing(record.Border)
    removeDrawing(record.Box)
    removeDrawing(record.Name)
    removeDrawing(record.Distance)
    Runtime.Records[player] = nil
    if Runtime.Target == player then
        Runtime.Target = nil
    end
end

local function getEnemy(player)
    if player == LocalPlayer or player.Parent ~= Players then
        return
    end
    local match = LocalPlayer:GetAttribute("MatchId")
    if type(match) == "string" and match ~= "" and player:GetAttribute("MatchId") ~= match then
        return
    end
    if LocalPlayer:GetAttribute("InMatch") == false or player:GetAttribute("InMatch") == false then
        return
    end
    local side = LocalPlayer:GetAttribute("MatchSide")
    local otherSide = player:GetAttribute("MatchSide")
    if side ~= nil and side ~= "" and otherSide ~= nil and otherSide ~= "" then
        if side == otherSide then
            return
        end
    elseif LocalPlayer.Team and not LocalPlayer.Neutral and not player.Neutral and player.Team == LocalPlayer.Team then
        return
    end
    if player:GetAttribute("Alive") == false then
        return
    end
    local character = player.Character
    if not character or not character.Parent then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    if not humanoid or humanoid.Health <= 0 or not root or not head then
        return
    end
    return character, humanoid, root, head
end

local function getFOV(camera)
    local viewport = camera.ViewportSize
    return viewport * 0.5, math.clamp(math.min(viewport.X, viewport.Y) * 0.22, 60, 180)
end

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local function refreshRayFilter(camera)
    local ignored = { camera }
    if LocalPlayer.Character then
        ignored[#ignored + 1] = LocalPlayer.Character
    end
    local bin = Workspace:FindFirstChild("Bin")
    if bin then
        ignored[#ignored + 1] = bin
    end
    RayParams.FilterDescendantsInstances = ignored
end

local function visible(character, point, camera)
    local origin = camera.CFrame.Position
    local hit = Workspace:Raycast(origin, point - origin, RayParams)
    return not hit or hit.Instance:IsDescendantOf(character)
end

local MotionParams = RaycastParams.new()
MotionParams.FilterType = Enum.RaycastFilterType.Exclude
MotionParams.IgnoreWater = true

local function limitVector(vector, maximum)
    local magnitude = vector.Magnitude
    return magnitude > maximum and vector * (maximum / magnitude) or vector
end

local function sampleMotion()
    local now = os.clock()
    for player, record in pairs(Runtime.Records) do
        local character, humanoid, root = getEnemy(player)
        if character then
            local position = root.Position
            local velocity = root.AssemblyLinearVelocity
            local previous = record.Motion
            local acceleration = Vector3.zero
            if previous and previous.Root == root then
                local dt = now - previous.Time
                local displacement = position - previous.Position
                if dt >= 1 / 120 and dt <= 0.2 and displacement.Magnitude <= math.max(12, velocity.Magnitude * dt * 3) then
                    local observed = displacement / dt
                    if (observed - velocity).Magnitude < math.max(8, velocity.Magnitude * 0.5) then
                        velocity = velocity:Lerp(observed, 0.15)
                    end
                    if root.AssemblyLinearVelocity.Magnitude < 0.5 then
                        velocity = root.AssemblyLinearVelocity
                    else
                        local change = (velocity - previous.Velocity) / dt
                        change = limitVector(Vector3.new(change.X, 0, change.Z), 40)
                        acceleration = previous.Acceleration:Lerp(change, 1 - math.exp(-dt * 12))
                    end
                end
            end
            record.Motion = {
                Root = root,
                Position = position,
                Velocity = velocity,
                Acceleration = acceleration,
                Time = now,
                Grounded = humanoid.FloorMaterial ~= Enum.Material.Air,
            }
        else
            record.Motion = nil
        end
    end
end

local function flightAtRange(flight, origin, aim, goal, power, explosive)
    local offset = goal - origin
    local distance = offset.Magnitude
    if distance < 0.01 then
        return origin, 0
    end
    local axis = offset / distance
    local state = flight.newState(origin, aim, power, explosive)
    local step = flight.FIXED_DT
    local previous = origin
    local previousProgress = 0
    for index = 1, math.ceil(3 / step) do
        flight.advance(state, step)
        local progress = (state.position - origin):Dot(axis)
        if progress >= distance then
            local alpha = math.clamp((distance - previousProgress) / math.max(progress - previousProgress, 0.00001), 0, 1)
            return previous:Lerp(state.position, alpha), (index - 1 + alpha) * step
        end
        if index > 6 and state.velocity:Dot(axis) <= 0 then
            return
        end
        previous = state.position
        previousProgress = progress
    end
end

local function solveIntercept(flight, origin, power, explosive, targetAt)
    local speed = flight.PARAMS.THROW_SPEED * flight.computePowerScalar(power, explosive)
    local time = math.clamp((targetAt(0) - origin).Magnitude / math.max(speed, 1), 0, 3)
    local aim = targetAt(time)
    local residual = math.huge
    for _ = 1, 9 do
        local position, nextTime = flightAtRange(flight, origin, aim, targetAt(time), power, explosive)
        if not position then
            return
        end
        local correction = targetAt(nextTime) - position
        residual = correction.Magnitude
        aim = aim + correction
        local converged = residual < 0.07 and math.abs(nextTime - time) < 0.001
        time = nextTime
        if converged then
            break
        end
    end
    if residual > 0.75 then
        return
    end
    return aim, time, residual
end

function Runtime:PredictKnife(player, context)
    local flight = self.KnifeFlight
    local character, humanoid, root, head = getEnemy(player)
    if not flight or not character then
        return
    end
    local record = self.Records[player]
    local motion = record and record.Motion
    local fresh = motion and motion.Root == root and os.clock() - motion.Time < 0.2
    local velocity = fresh and motion.Velocity or root.AssemblyLinearVelocity
    local acceleration = fresh and motion.Acceleration or Vector3.zero
    local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
    local rootPosition = root.Position
    local headOffset = head.Position - rootPosition
    local clearance = root.Size.Y * 0.5 + (humanoid.RigType == Enum.HumanoidRigType.R6 and 2 or humanoid.HipHeight)
    local ignored = { character }
    for _, object in ipairs({ Workspace:FindFirstChild("Characters"), Workspace:FindFirstChild("Bin"), Workspace.CurrentCamera }) do
        if object then
            ignored[#ignored + 1] = object
        end
    end
    if LocalPlayer.Character then
        ignored[#ignored + 1] = LocalPlayer.Character
    end
    MotionParams.FilterDescendantsInstances = ignored
    local floor = Workspace:Raycast(rootPosition, Vector3.new(0, -clearance - 0.4, 0), MotionParams)
    grounded = (grounded or floor ~= nil) and math.abs(velocity.Y) < 3
    local pingOK, ping = pcall(LocalPlayer.GetNetworkPing, LocalPlayer)
    local latency = pingOK and math.clamp(ping * 0.5, 0, 0.15) or 0
    local function targetAt(time)
        local duration = time + latency
        local horizontal = Vector3.new(velocity.X, 0, velocity.Z) * duration
        horizontal = horizontal + acceleration * (0.12 * (duration - 0.12 * (1 - math.exp(-duration / 0.12))))
        if horizontal.Magnitude > 0.01 then
            local wall = Workspace:Raycast(rootPosition, horizontal, MotionParams)
            if wall then
                horizontal = horizontal.Unit * math.max(0, wall.Distance - root.Size.X * 0.5)
            end
        end
        local vertical = grounded and 0 or velocity.Y * duration - 0.5 * Workspace.Gravity * duration * duration
        local future = rootPosition + horizontal + Vector3.new(0, vertical, 0)
        local height = math.max(rootPosition.Y, future.Y) + 3
        local ground = Workspace:Raycast(
            Vector3.new(future.X, height, future.Z),
            Vector3.new(0, -math.max(12, height - future.Y + clearance + 3), 0),
            MotionParams
        )
        if ground then
            local standingHeight = ground.Position.Y + clearance
            if grounded and math.abs(standingHeight - rootPosition.Y) <= 4 then
                future = Vector3.new(future.X, standingHeight, future.Z)
            elseif not grounded then
                future = Vector3.new(future.X, math.max(future.Y, standingHeight), future.Z)
            end
        end
        return future + headOffset
    end
    local point, time, residual = solveIntercept(flight, context.Origin, context.Power, context.Explosive, targetAt)
    if point then
        self.PredictionCount = self.PredictionCount + 1
        self.LastPrediction = {
            Target = player.Name,
            Point = point,
            Origin = context.Origin,
            Expected = targetAt(time),
            FlightTime = time,
            Power = context.Power,
            Explosive = context.Explosive,
            Residual = residual,
            Velocity = velocity,
            Latency = latency,
            CreatedAt = os.clock(),
        }
    end
    return point
end

function Runtime:GetTargetPoint()
    if not self.Active or LocalPlayer:GetAttribute("Alive") == false then
        return
    end
    local ownCharacter = LocalPlayer.Character
    local ownHumanoid = ownCharacter and ownCharacter:FindFirstChildOfClass("Humanoid")
    local camera = Workspace.CurrentCamera
    if not camera or not ownHumanoid or ownHumanoid.Health <= 0 then
        return
    end
    local context = self.ThrowContexts[coroutine.running()]
    local knifeThrow = context and os.clock() - context.CreatedAt < 0.25
    local center, radius = getFOV(camera)
    local bestDistance = radius
    local bestPoint, bestPlayer
    refreshRayFilter(camera)
    for player in pairs(self.Records) do
        local character, _, _, head = getEnemy(player)
        if character then
            local projected, onScreen = camera:WorldToViewportPoint(head.Position)
            if onScreen and projected.Z > 0 then
                local distance = (Vector2.new(projected.X, projected.Y) - center).Magnitude
                if distance <= bestDistance and (knifeThrow or visible(character, head.Position, camera)) then
                    bestDistance = distance
                    bestPoint = head.Position
                    bestPlayer = player
                end
            end
        end
    end
    self.Target = bestPlayer
    if bestPlayer and knifeThrow then
        return self:PredictKnife(bestPlayer, context) or bestPoint
    end
    return bestPoint
end

local FOV = draw("Circle", {
    Color = White,
    Thickness = 1,
    NumSides = 96,
    Filled = false,
    Transparency = 0.75,
    Radius = 180,
})
Runtime.FOV = FOV

function Runtime:Destroy()
    if not self.Active then
        return
    end
    self.Active = false
    for _, connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    for object in pairs(self.Drawings) do
        removeDrawing(object)
    end
    table.clear(self.Records)
    table.clear(self.Connections)
    table.clear(self.ThrowContexts)
    self.Target = nil
    if Bridge.Runtime == self then
        Bridge.Runtime = nil
    end
    if Environment.MurderDuels == self then
        Environment.MurderDuels = nil
    end
end

local function render()
    local camera = Workspace.CurrentCamera
    if not camera then
        FOV.Visible = false
        for _, record in pairs(Runtime.Records) do
            hide(record)
        end
        return
    end
    local center, radius = getFOV(camera)
    FOV.Position = center
    FOV.Radius = radius
    FOV.Visible = true
    local ownCharacter = LocalPlayer.Character
    local ownRoot = ownCharacter and ownCharacter:FindFirstChild("HumanoidRootPart")
    local origin = ownRoot and ownRoot.Position or camera.CFrame.Position
    for player, record in pairs(Runtime.Records) do
        local character, humanoid, root, head = getEnemy(player)
        if character then
            local projected, onScreen = camera:WorldToViewportPoint(root.Position)
            local legHeight = humanoid.RigType == Enum.HumanoidRigType.R6 and 2 or humanoid.HipHeight
            local top = camera:WorldToViewportPoint(head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.3, 0))
            local bottom = camera:WorldToViewportPoint(root.Position - Vector3.new(0, root.Size.Y * 0.5 + legHeight + 0.15, 0))
            if onScreen and projected.Z > 0.1 and top.Z > 0.1 and bottom.Z > 0.1 then
                local height = math.max(8, math.abs(bottom.Y - top.Y))
                local width = height * 0.55
                local x = projected.X - width * 0.5
                local y = math.min(top.Y, bottom.Y)
                local position = Vector2.new(math.floor(x), math.floor(y))
                local size = Vector2.new(math.floor(width), math.floor(height))
                record.Border.Position = position
                record.Border.Size = size
                record.Box.Position = position
                record.Box.Size = size
                record.Name.Text = player.Name == player.DisplayName and player.Name or player.Name .. " | " .. player.DisplayName
                record.Name.Position = Vector2.new(math.floor(projected.X), math.floor(y - 19))
                record.Distance.Text = tostring(math.floor((root.Position - origin).Magnitude + 0.5)) .. " studs"
                record.Distance.Position = Vector2.new(math.floor(projected.X), math.floor(y + height + 3))
                record.Border.Visible = true
                record.Box.Visible = true
                record.Name.Visible = true
                record.Distance.Visible = true
            else
                hide(record)
            end
        else
            hide(record)
        end
    end
end

local function installHook(callback, mode)
    if Bridge.Installed[callback] then
        return
    end
    local source = debug.info(callback, "s")
    if mode == "World" or mode == "Throw" then
        if not source:find("Players." .. LocalPlayer.Name .. ".", 1, true)
            or not (source:find("KnifeClient", 1, true) or source:find("RevolverClient", 1, true)) then
            return
        end
    elseif not source:find("ReplicatedStorage.Extensions.AimMagnetism", 1, true) then
        return
    end
    local original
    if mode == "Throw" then
        if not source:find("KnifeClient", 1, true) then
            return
        end
        local magnetism, getEffects
        for _, value in pairs(debug.getupvalues(callback)) do
            if type(value) == "table" and type(value.getAdjustedScreenPoint) == "function" then
                magnetism = value
            elseif type(value) == "function" and debug.info(value, "n") == "getEffects" then
                getEffects = value
            end
        end
        if magnetism and not Bridge.Magnetism[magnetism] then
            local adjusted = magnetism.getAdjustedScreenPoint
            magnetism.getAdjustedScreenPoint = function(self, ...)
                local current = Bridge.Runtime
                local context = current and current.Active and current.ThrowContexts[coroutine.running()]
                if context and os.clock() - context.CreatedAt < 0.25 then
                    return nil
                end
                return adjusted(self, ...)
            end
            Bridge.Magnetism[magnetism] = true
        end
        local function throw(power, ...)
            local current = Bridge.Runtime
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not current or not current.Active or not current.KnifeFlight or not root or type(power) ~= "number" then
                return original(power, ...)
            end
            local arm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
            local origin = arm and arm.Position or root.Position + root.CFrame.LookVector * 2
            local explosive = false
            if getEffects then
                local success, effects = pcall(getEffects)
                explosive = success and type(effects) == "table" and (tonumber(effects.Explosive) or 0) > 0
            end
            local thread = coroutine.running()
            local previous = current.ThrowContexts[thread]
            local context = { Origin = origin, Power = math.clamp(power, 0, 1), Explosive = explosive, CreatedAt = os.clock() }
            current.ThrowContexts[thread] = context
            task.defer(function()
                if current.ThrowContexts[thread] == context then
                    current.ThrowContexts[thread] = previous
                end
            end)
            local results = table.pack(pcall(original, power, ...))
            current.ThrowContexts[thread] = previous
            if not results[1] then
                error(results[2], 0)
            end
            return table.unpack(results, 2, results.n)
        end
        original = hookfunction(callback, type(newcclosure) == "function" and newcclosure(throw) or throw)
        Bridge.Installed[callback] = true
        Bridge.Installed[original] = true
        Runtime.HookCount = Runtime.HookCount + 1
        return
    end
    local replacement = function(...)
        local current = Bridge.Runtime
        if current and current.Active then
            local ok, point = pcall(current.GetTargetPoint, current)
            if ok and point then
                if mode == "World" then
                    return point
                end
                local camera = Workspace.CurrentCamera
                if camera then
                    local projected, onScreen = camera:WorldToViewportPoint(point)
                    if onScreen and projected.Z > 0 then
                        return Vector2.new(projected.X, projected.Y)
                    end
                end
            end
        end
        return original(...)
    end
    original = hookfunction(callback, type(newcclosure) == "function" and newcclosure(replacement) or replacement)
    Bridge.Installed[callback] = true
    Bridge.Installed[original] = true
    Runtime.HookCount = Runtime.HookCount + 1
end

local function installHooks()
    if not Runtime.KnifeFlight then
        local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
        local module = shared and shared:FindFirstChild("KnifeFlight")
        if module then
            local success, flight = pcall(require, module)
            if success and type(flight) == "table" and type(flight.newState) == "function" and type(flight.advance) == "function" then
                Runtime.KnifeFlight = flight
            end
        end
    end
    if type(filtergc) == "function" then
        for name, mode in pairs(AimNames) do
            for _, callback in ipairs(filtergc("function", { Name = name, IgnoreExecutor = true }, false)) do
                installHook(callback, mode)
            end
        end
    else
        for _, callback in ipairs(getgc(false)) do
            if type(callback) == "function" then
                local mode = AimNames[debug.info(callback, "n")]
                if mode then
                    installHook(callback, mode)
                end
            end
        end
    end
end

local ok, failure = pcall(function()
    connect(Players.PlayerAdded, addPlayer)
    connect(Players.PlayerRemoving, removePlayer)
    for _, player in ipairs(Players:GetPlayers()) do
        addPlayer(player)
    end
    local motionElapsed = 0
    connect(RunService.Heartbeat, function(dt)
        motionElapsed = motionElapsed + dt
        if motionElapsed >= 1 / 30 then
            motionElapsed = 0
            sampleMotion()
        end
    end)
    connect(RunService.RenderStepped, function()
        local success, message = pcall(render)
        if not success and Runtime.LastError ~= tostring(message) then
            Runtime.LastError = tostring(message)
            warn("Murder Duels ESP: " .. Runtime.LastError)
        end
    end)
end)

if not ok then
    Runtime:Destroy()
    error("Murder Duels initialization failed: " .. tostring(failure))
end

task.spawn(function()
    while Runtime.Active do
        local success, message = pcall(installHooks)
        if not success and Runtime.LastError ~= tostring(message) then
            Runtime.LastError = tostring(message)
            warn("Murder Duels Silent Aim: " .. Runtime.LastError)
        end
        task.wait(2)
    end
end)

pcall(function()
    warn("t.me/arceusxcommunity")
end)

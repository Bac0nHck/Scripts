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
if Bridge and Bridge.Version ~= 4 then
    if Bridge.Runtime then
        Bridge.Runtime:Destroy()
    end
    local restore = restorefunction or restorefunc
    if next(Bridge.Installed) and type(restore) ~= "function" then
        error("Rejoin once to replace the previous weapon hooks")
    end
    for callback in pairs(Bridge.Installed) do
        pcall(restore, callback)
    end
    Bridge = nil
end
if not Bridge then
    Bridge = {
        Version = 4,
        Installed = setmetatable({}, { __mode = "k" }),
        Hooks = setmetatable({}, { __mode = "k" }),
    }
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

local function estimateVelocity(history, raw)
    local horizontal = Vector3.new(raw.X, 0, raw.Z)
    local speed = horizontal.Magnitude
    if speed < 0.75 then
        return Vector3.new(0, raw.Y, 0)
    end
    if #history < 3 or history[#history].Time - history[1].Time < 0.05 then
        return raw
    end
    local latest = history[#history]
    local weightSum, meanTime = 0, 0
    local meanPosition = Vector3.zero
    for _, sample in ipairs(history) do
        local time = sample.Time - latest.Time
        local weight = math.exp(time / 0.06)
        weightSum = weightSum + weight
        meanTime = meanTime + time * weight
        meanPosition = meanPosition + (sample.Position - latest.Position) * weight
    end
    meanTime = meanTime / weightSum
    meanPosition = meanPosition / weightSum
    local numerator = Vector3.zero
    local denominator = 0
    for _, sample in ipairs(history) do
        local time = sample.Time - latest.Time
        local weight = math.exp(time / 0.06)
        local centered = time - meanTime
        numerator = numerator + (sample.Position - latest.Position - meanPosition) * (centered * weight)
        denominator = denominator + centered * centered * weight
    end
    if denominator < 0.000001 then
        return raw
    end
    local fitted = numerator / denominator
    fitted = Vector3.new(fitted.X, 0, fitted.Z)
    if fitted:Dot(horizontal) < 0 or fitted.Magnitude > speed * 2 + 8 then
        return raw
    end
    local blended = horizontal:Lerp(fitted, 0.75)
    blended = limitVector(blended, math.min(speed, fitted.Magnitude + 1))
    return Vector3.new(blended.X, raw.Y, blended.Z)
end

local function sampleMotion()
    local now = os.clock()
    for player, record in pairs(Runtime.Records) do
        local character, humanoid, root = getEnemy(player)
        if character then
            local position = root.Position
            local raw = root.AssemblyLinearVelocity
            local previous = record.Motion
            local history = previous and previous.Root == root and previous.History or {}
            if previous and previous.Root == root then
                local dt = now - previous.Time
                local displacement = position - previous.Position
                local oldDirection = Vector3.new(previous.Raw.X, 0, previous.Raw.Z)
                local newDirection = Vector3.new(raw.X, 0, raw.Z)
                local turned = oldDirection.Magnitude > 1 and newDirection.Magnitude > 1
                    and oldDirection.Unit:Dot(newDirection.Unit) < 0.5
                if dt > 0.2 or displacement.Magnitude > math.max(12, raw.Magnitude * dt * 3)
                    or turned or newDirection.Magnitude < 0.75 then
                    history = {}
                end
            end
            history[#history + 1] = { Time = now, Position = position }
            while #history > 6 or (#history > 1 and now - history[1].Time > 0.18) do
                table.remove(history, 1)
            end
            record.Motion = {
                Root = root,
                Position = position,
                Velocity = estimateVelocity(history, raw),
                Raw = raw,
                History = history,
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
    local state = flight.newState(origin, aim - origin, power, explosive)
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
    local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
    local rootPosition = root.Position
    local body = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or root
    local bodyOffset = body.Position - rootPosition
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
    local function targetAt(time)
        local duration = time
        local horizontal = Vector3.new(velocity.X, 0, velocity.Z) * duration
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
        return future + bodyOffset
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
            Latency = 0,
            CreatedAt = os.clock(),
        }
    end
    return point
end

function Runtime:GetTargetPoint()
    if not self.Active or LocalPlayer:GetAttribute("InMatch") ~= true or LocalPlayer:GetAttribute("Alive") ~= true then
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
    if knifeThrow and context.Point then
        return context.Point
    end
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

function Runtime:RedirectKnife(data)
    if not self.Active or not self.KnifeFlight or type(data) ~= "table"
        or typeof(data.origin) ~= "Vector3" or typeof(data.target) ~= "Vector3"
        or type(data.power) ~= "number" or LocalPlayer:GetAttribute("InMatch") ~= true
        or LocalPlayer:GetAttribute("Alive") ~= true
        or (data.ownerUserId ~= nil and data.ownerUserId ~= LocalPlayer.UserId) then
        return
    end
    local now = os.clock()
    local cached = self.KnifeShot
    if cached and now - cached.CreatedAt < 0.12 and cached.Id == data.id
        and (cached.Origin - data.origin).Magnitude < 0.01 and math.abs(cached.Power - data.power) < 0.001 then
        return cached.Point
    end
    local thread = coroutine.running()
    local previous = self.ThrowContexts[thread]
    local context = {
        Origin = data.origin,
        Power = math.clamp(data.power, 0, 1),
        Explosive = data.isExplosive == true,
        CreatedAt = now,
    }
    self.ThrowContexts[thread] = context
    local success, point = pcall(self.GetTargetPoint, self)
    self.ThrowContexts[thread] = previous
    if not success then
        self.LastKnifeError = tostring(point)
        return
    end
    self.KnifeShot = { CreatedAt = now, Id = data.id, Origin = data.origin, Power = data.power, Point = point }
    return point
end

local function installKnifeDispatch()
    local storage = game:GetService("ReplicatedStorage")
    local bindables = storage:FindFirstChild("Bindables")
    local remotes = storage:FindFirstChild("Remotes")
    Runtime.KnifeSpawn = bindables and bindables:FindFirstChild("SpawnKnife")
    Runtime.KnifeRemote = remotes and remotes:FindFirstChild("ThrowReplicate")
    if not Runtime.KnifeSpawn or not Runtime.KnifeRemote then
        return
    end
    local dispatch = Environment.__MurderDuelsKnifeDispatch
    if dispatch and dispatch.Version ~= 3 then
        dispatch.Runtime = nil
        dispatch = nil
    end
    if not dispatch then
        if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
            Runtime.LastKnifeError = "Knife prediction requires hookmetamethod and getnamecallmethod"
            return
        end
        dispatch = { Version = 3 }
        local clone = clonefunction or clonefunc
        if type(clone) == "function" and type(getrawmetatable) == "function" then
            dispatch.Original = clone(getrawmetatable(game).__namecall)
        end
        local function intercept(instance, ...)
            local current = dispatch.Runtime
            if current and current.Active and (instance == current.KnifeSpawn or instance == current.KnifeRemote) then
                local method = getnamecallmethod()
                if (instance == current.KnifeSpawn and method == "Fire") or (instance == current.KnifeRemote and method == "FireServer") then
                    local forward = method == "Fire" and instance.Fire or instance.FireServer
                    local args = table.pack(...)
                    local data = args[1]
                    local channel = instance == current.KnifeSpawn and "Local" or "Server"
                    current.KnifeCalls = current.KnifeCalls or {}
                    current.KnifeCalls[channel] = { Count = args.n, First = typeof(data), Second = typeof(args[2]), Third = typeof(args[3]) }
                    if type(data) == "table" then
                        local worker = coroutine.create(current.RedirectKnife)
                        local success, point = coroutine.resume(worker, current, data)
                        local finished = coroutine.status(worker) == "dead"
                        if not finished and type(coroutine.close) == "function" then
                            coroutine.close(worker)
                        end
                        if success and finished and typeof(point) == "Vector3" then
                            data.target = point
                            if typeof(data.dir) == "Vector3" and (point - data.origin).Magnitude > 0.001 then
                                data.dir = (point - data.origin).Unit
                            end
                        elseif not success then
                            current.LastKnifeError = tostring(point)
                        end
                    end
                    return forward(instance, table.unpack(args, 1, args.n))
                end
            end
            return dispatch.Original(instance, ...)
        end
        local original = hookmetamethod(game, "__namecall", type(newcclosure) == "function" and newcclosure(intercept) or intercept)
        if type(original) == "function" then
            dispatch.Original = original
        end
        Environment.__MurderDuelsKnifeDispatch = dispatch
    end
    dispatch.Runtime = Runtime
    Runtime.KnifeDispatchReady = true
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
    local dispatch = Environment.__MurderDuelsKnifeDispatch
    if dispatch and dispatch.Runtime == self then
        dispatch.Runtime = nil
    end
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
    if mode == "World" then
        if not source:find("Players." .. LocalPlayer.Name .. ".", 1, true)
            or not (source:find("KnifeClient", 1, true) or source:find("RevolverClient", 1, true)) then
            return
        end
        local script = getfenv(callback).script
        local tool = typeof(script) == "Instance" and script.Parent
        if not tool or not tool:IsA("Tool") or (tool.Parent ~= LocalPlayer.Character and tool.Parent ~= LocalPlayer:FindFirstChildOfClass("Backpack")) then
            return
        end
        if mode == "World" then
            local ready = false
            for _, value in pairs(debug.getupvalues(callback)) do
                if type(value) == "function" and debug.info(value, "n") == "getAimIgnoreList" then
                    ready = true
                    break
                end
            end
            if not ready then
                return
            end
        end
    elseif not source:find("ReplicatedStorage.Extensions.AimMagnetism", 1, true) then
        return
    end
    local Hook = {}
    local clone = clonefunction or clonefunc
    if type(clone) == "function" then
        Hook.Original = clone(callback)
        Bridge.Installed[Hook.Original] = true
    end
    local function attach(replacement)
        local original = hookfunction(callback, type(newcclosure) == "function" and newcclosure(replacement) or replacement)
        if type(original) == "function" then
            Hook.Original = original
        end
        if type(Hook.Original) ~= "function" then
            local restore = restorefunction or restorefunc
            if type(restore) == "function" then
                pcall(restore, callback)
            end
            error("The executor did not preserve the original weapon function")
        end
        Bridge.Installed[callback] = true
        Bridge.Installed[Hook.Original] = true
        Bridge.Hooks[callback] = Hook
        Runtime.HookCount = Runtime.HookCount + 1
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
        return Hook.Original(...)
    end
    attach(replacement)
end

local function installHooks()
    if not Runtime.KnifeObservation then
        local bindables = game:GetService("ReplicatedStorage"):FindFirstChild("Bindables")
        local spawned = bindables and bindables:FindFirstChild("SpawnKnife")
        if spawned then
            Runtime.KnifeObservation = connect(spawned.Event, function(data)
                if type(data) == "table" and data.ownerUserId == LocalPlayer.UserId then
                    local prediction = Runtime.LastPrediction
                    Runtime.LastActualThrow = {
                        Power = data.power,
                        Origin = data.origin,
                        Target = data.target,
                        Explosive = data.isExplosive,
                        PredictionAge = prediction and os.clock() - prediction.CreatedAt,
                        OriginError = prediction and (data.origin - prediction.Origin).Magnitude,
                        AimError = prediction and (data.target - prediction.Point).Magnitude,
                    }
                end
            end)
        end
    end
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
    installKnifeDispatch()
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

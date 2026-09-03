local function createESP(context)
    local players = context.Players
    local localPlayer = context.LocalPlayer
    local config = context.Config
    local records = {}
    local connections = {}
    local destroyed = false
    local controller = {}
    local bodyNames = {
        Head = true,
        HumanoidRootPart = true,
        Torso = true,
        UpperTorso = true,
        LowerTorso = true,
        LeftUpperArm = true,
        LeftLowerArm = true,
        LeftHand = true,
        RightUpperArm = true,
        RightLowerArm = true,
        RightHand = true,
        LeftUpperLeg = true,
        LeftLowerLeg = true,
        LeftFoot = true,
        RightUpperLeg = true,
        RightLowerLeg = true,
        RightFoot = true,
        ["Left Arm"] = true,
        ["Right Arm"] = true,
        ["Left Leg"] = true,
        ["Right Leg"] = true,
    }
    local corners = {
        Vector3.new(-1, -1, -1),
        Vector3.new(-1, -1, 1),
        Vector3.new(-1, 1, -1),
        Vector3.new(-1, 1, 1),
        Vector3.new(1, -1, -1),
        Vector3.new(1, -1, 1),
        Vector3.new(1, 1, -1),
        Vector3.new(1, 1, 1),
    }

    local function disconnectAll(list)
        for _, connection in ipairs(list) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(list)
    end

    local function hide(record)
        for _, drawing in ipairs(record.Drawings) do
            drawing.Visible = false
        end
    end

    local function clearCharacter(record)
        disconnectAll(record.CharacterConnections)
        record.Character = nil
        record.Root = nil
        record.Humanoid = nil
        record.BoundsAt = 0
        table.clear(record.Parts)
        hide(record)
    end

    local function removePlayer(player)
        local record = records[player]
        if not record then
            return
        end
        records[player] = nil
        disconnectAll(record.Connections)
        clearCharacter(record)
        for _, drawing in ipairs(record.Drawings) do
            pcall(function()
                drawing:Remove()
            end)
        end
        table.clear(record.Drawings)
    end

    function controller:Destroy()
        if destroyed then
            return
        end
        destroyed = true
        disconnectAll(connections)
        local pending = {}
        for player in pairs(records) do
            pending[#pending + 1] = player
        end
        for _, player in ipairs(pending) do
            removePlayer(player)
        end
    end

    local function newDrawing(record, kind, properties)
        local drawing = assert(Drawing.new(kind), "Drawing creation failed")
        record.Drawings[#record.Drawings + 1] = drawing
        drawing.Visible = false
        drawing.Transparency = 1
        for key, value in pairs(properties) do
            drawing[key] = value
        end
        return drawing
    end

    local function bindCharacter(record, character)
        if record.Character == character then
            return
        end
        clearCharacter(record)
        if not character then
            return
        end
        record.Character = character
        local function track(instance)
            if instance:IsA("Humanoid") then
                record.Humanoid = instance
            elseif instance:IsA("BasePart") and bodyNames[instance.Name] then
                record.Parts[instance] = true
                record.BoundsAt = 0
                if instance.Name == "HumanoidRootPart" then
                    record.Root = instance
                end
            end
        end
        for name in pairs(bodyNames) do
            local part = character:FindFirstChild(name, true)
            if part then
                track(part)
            end
        end
        record.Humanoid = character:FindFirstChildWhichIsA("Humanoid", true)
        record.Root = record.Root or character.PrimaryPart or character:FindFirstChild("Torso", true)
            or character:FindFirstChild("UpperTorso", true) or character:FindFirstChild("Head", true)
        record.CharacterConnections[#record.CharacterConnections + 1] = character.DescendantAdded:Connect(track)
        record.CharacterConnections[#record.CharacterConnections + 1] = character.DescendantRemoving:Connect(function(instance)
            record.Parts[instance] = nil
            if record.Root == instance then
                record.Root = nil
            end
            if record.Humanoid == instance then
                record.Humanoid = nil
            end
            record.BoundsAt = 0
        end)
    end

    local function addPlayer(player)
        if destroyed or player == localPlayer or records[player] then
            return
        end
        local record = {
            Drawings = {},
            Connections = {},
            CharacterConnections = {},
            Parts = {},
            BoundsAt = 0,
        }
        records[player] = record
        local ok, problem = pcall(function()
            record.Outline = newDrawing(record, "Square", {Filled = false, Thickness = 3, Color = Color3.new(0, 0, 0), ZIndex = 1})
            record.Box = newDrawing(record, "Square", {Filled = false, Thickness = 1, ZIndex = 2})
            record.Name = newDrawing(record, "Text", {Center = true, Outline = true, Size = 13, Font = 2, ZIndex = 3})
            record.Distance = newDrawing(record, "Text", {Center = true, Outline = true, Size = 12, Font = 2, ZIndex = 3})
            record.Connections[#record.Connections + 1] = player.CharacterAdded:Connect(function(character)
                bindCharacter(record, character)
            end)
            record.Connections[#record.Connections + 1] = player.CharacterRemoving:Connect(function(character)
                if record.Character == character then
                    clearCharacter(record)
                end
            end)
            bindCharacter(record, player.Character)
        end)
        if not ok then
            removePlayer(player)
            warn(problem, 0)
        end
    end

    local function updateBounds(record, root, now)
        if now < record.BoundsAt then
            return
        end
        record.BoundsAt = now + 0.2
        local rootFrame = root.CFrame
        local minimum = Vector3.new(math.huge, math.huge, math.huge)
        local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
        local count = 0
        for part in pairs(record.Parts) do
            if part.Parent and part:IsDescendantOf(record.Character) then
                local relative = rootFrame:ToObjectSpace(part.CFrame)
                local half = part.Size * 0.5
                local right, up, look = relative.RightVector, relative.UpVector, relative.LookVector
                local extent = Vector3.new(
                    math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z,
                    math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z,
                    math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
                )
                local low, high = relative.Position - extent, relative.Position + extent
                minimum = Vector3.new(math.min(minimum.X, low.X), math.min(minimum.Y, low.Y), math.min(minimum.Z, low.Z))
                maximum = Vector3.new(math.max(maximum.X, high.X), math.max(maximum.Y, high.Y), math.max(maximum.Z, high.Z))
                count = count + 1
            end
        end
        if count < 2 then
            minimum = Vector3.new(-1.5, -3, -1)
            maximum = Vector3.new(1.5, 2.5, 1)
        end
        record.Center = (minimum + maximum) * 0.5
        record.HalfSize = (maximum - minimum) * 0.5 + Vector3.new(0.08, 0.08, 0.08)
    end

    function controller:Update(camera)
        if destroyed then
            return
        end
        if not camera then
            for _, record in pairs(records) do
                hide(record)
            end
            return
        end
        local viewport = camera.ViewportSize
        local now = os.clock()
        for player, record in pairs(records) do
            local character = player.Character
            bindCharacter(record, character)
            local root = record.Root
            if character and (not root or not root.Parent) then
                root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
                    or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
                record.Root = root
            end
            local humanoid = record.Humanoid
            if not character or not character.Parent or not root or not root:IsA("BasePart")
                or not context.IsEnemy(player) or not humanoid or humanoid.Health <= 0 then
                hide(record)
                continue
            end
            local distance = (camera.CFrame.Position - root.Position).Magnitude
            if distance > config.MaxDistance then
                hide(record)
                continue
            end
            updateBounds(record, root, now)
            local rootFrame = root.CFrame
            local lowX, lowY, highX, highY = math.huge, math.huge, -math.huge, -math.huge
            local clipped = false
            for _, corner in ipairs(corners) do
                local point = rootFrame:PointToWorldSpace(record.Center + record.HalfSize * corner)
                local projected = camera:WorldToViewportPoint(point)
                if projected.Z <= 0.1 then
                    clipped = true
                    break
                end
                lowX, lowY = math.min(lowX, projected.X), math.min(lowY, projected.Y)
                highX, highY = math.max(highX, projected.X), math.max(highY, projected.Y)
            end
            if clipped or highX < 0 or highY < 0 or lowX > viewport.X or lowY > viewport.Y then
                hide(record)
                continue
            end
            lowX, lowY = math.floor(lowX), math.floor(lowY)
            highX, highY = math.ceil(highX), math.ceil(highY)
            local width, height = highX - lowX, highY - lowY
            if width < 2 or height < 2 then
                hide(record)
                continue
            end
            local color = config.EnemyColor
            local position, size = Vector2.new(lowX, lowY), Vector2.new(width, height)
            record.Outline.Position, record.Outline.Size, record.Outline.Visible = position, size, true
            record.Box.Position, record.Box.Size, record.Box.Color, record.Box.Visible = position, size, color, true
            record.Name.Text = player.DisplayName ~= "" and player.DisplayName or player.Name
            record.Name.Position, record.Name.Color = Vector2.new(lowX + width * 0.5, lowY - 16), color
            record.Name.Visible = true
            record.Distance.Text = tostring(math.floor(distance + 0.5)) .. " studs"
            record.Distance.Position, record.Distance.Color = Vector2.new(lowX + width * 0.5, highY + 2), color
            record.Distance.Visible = true
        end
    end

    local ok, problem = pcall(function()
        connections[#connections + 1] = players.PlayerAdded:Connect(function(player)
            local added, failure = pcall(addPlayer, player)
            if not added then
                warn("ESP initialization failed: " .. tostring(failure))
            end
        end)
        connections[#connections + 1] = players.PlayerRemoving:Connect(removePlayer)
        for _, player in ipairs(players:GetPlayers()) do
            addPlayer(player)
        end
    end)
    if not ok then
        controller:Destroy()
        warn(problem, 0)
    end
    return controller
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Environment = type(getgenv) == "function" and getgenv() or _G

assert(game.PlaceId == 136801880565837, "This script supports Flick")
assert(Drawing and type(Drawing.new) == "function", "This executor requires Drawing API support")

local function waitFor(parent, name)
    return assert(parent:WaitForChild(name, 20), "Missing game module: " .. name)
end

local ModuleScripts = waitFor(ReplicatedStorage, "ModuleScripts")
local GunModules = waitFor(ModuleScripts, "GunModules")
local BulletHandler = require(waitFor(GunModules, "BulletHandler"))
assert(type(BulletHandler) == "table" and type(BulletHandler.Fire) == "function", "Unsupported weapon handler")

local Previous = Environment.FlickESPAndSilentAim
if type(Previous) == "table" and type(Previous.Destroy) == "function" then
    Previous:Destroy()
end

local Config = {
    FOVRadius = 150,
    FOVReferenceSize = 720,
    MobileFOVMultiplier = 1.8,
    MaxDistance = 2500,
    EnemyColor = Color3.fromRGB(255, 90, 90),
}

local State = {
    Active = true,
}

local OriginalFire = BulletHandler.Fire
local WrappedFire
local aimWarningShown = false
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local function isEnemy(player)
    local team = player.Team
    return player ~= LocalPlayer and player.Parent == Players and team ~= nil and team.Name == "Play"
end

local function getRadius(viewport)
    local shortestSide = math.min(viewport.X, viewport.Y)
    local radius = Config.FOVRadius * shortestSide / Config.FOVReferenceSize
    if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
        radius = radius * Config.MobileFOVMultiplier
    end
    return math.max(1, math.min(radius, shortestSide * 0.48))
end

local function isLocalAlive()
    if LocalPlayer.Team and LocalPlayer.Team.Name == "Lobby" then
        return false
    end
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

local function updateRayFilter(camera)
    local excluded = {camera}
    if LocalPlayer.Character then
        excluded[#excluded + 1] = LocalPlayer.Character
    end
    local storage = workspace:FindFirstChild("bulletStorage")
    if storage then
        excluded[#excluded + 1] = storage
    end
    RayParams.FilterDescendantsInstances = excluded
end

local function isVisible(origin, position, character)
    local difference = position - origin
    if difference.Magnitude < 0.01 then
        return true
    end
    local hit = workspace:Raycast(origin, difference, RayParams)
    return not hit or hit.Instance:IsDescendantOf(character)
end

local function selectTarget(camera, origin)
    if not camera or not isLocalAlive() then
        return nil
    end
    updateRayFilter(camera)
    local viewport = camera.ViewportSize
    local center = viewport * 0.5
    local radius = getRadius(viewport)
    local bestDistance = radius * radius
    local best
    for _, player in ipairs(Players:GetPlayers()) do
        if not isEnemy(player) then
            continue
        end
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local part = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
        if not humanoid or humanoid.Health <= 0 or not part or not part:IsA("BasePart")
            or character:FindFirstChildOfClass("ForceField") then
            continue
        end
        local position = part.Position
        if (position - origin).Magnitude > Config.MaxDistance then
            continue
        end
        local point, onScreen = camera:WorldToViewportPoint(position)
        if not onScreen or point.Z <= 0 then
            continue
        end
        local dx, dy = point.X - center.X, point.Y - center.Y
        local distance = dx * dx + dy * dy
        if distance <= bestDistance and isVisible(origin, position, character) then
            bestDistance = distance
            best = part
        end
    end
    return best
end

local function solveDirection(origin, part, force, gravity)
    local speed = (tonumber(force) or 0) * 20.224489795918366
    if speed <= 0 then
        return nil
    end
    local relative = part.Position - origin
    local velocity = part.AssemblyLinearVelocity
    local acceleration = Vector3.new(0, -(tonumber(gravity) or 0) * workspace.Gravity, 0)
    local time = relative.Magnitude / speed
    for _ = 1, 16 do
        if time ~= time or time <= 0 or time > 5 then
            return nil
        end
        local displacement = relative + velocity * time - acceleration * (0.5 * time * time)
        local nextTime = displacement.Magnitude / speed
        if math.abs(nextTime - time) * speed < 0.01 then
            return displacement.Unit
        end
        time = nextTime
    end
    return nil
end

local function getShotLook(data, direction)
    local misc = data.Misc
    if type(misc) ~= "table" or typeof(misc.CamCFrame) ~= "CFrame" then
        return nil
    end
    local spread = tonumber(misc.Spread) or 0
    if spread == 0 then
        return direction
    end
    if type(misc.NewSeed) ~= "number" then
        return nil
    end
    math.randomseed(misc.NewSeed)
    local offset = Vector3.new(math.random(-spread, spread) / 100,
        math.random(-spread, spread) / 100, math.random(-spread, spread) / 100)
    if ((misc.CamCFrame.LookVector + offset).Unit - data.Direction).Magnitude > 0.0001 then
        return nil
    end
    local dot = direction:Dot(offset)
    local discriminant = 1 - offset:Dot(offset) + dot * dot
    if discriminant <= 0 then
        return nil
    end
    local scale = dot + math.sqrt(discriminant)
    if scale <= 0 then
        return nil
    end
    return (direction * scale - offset).Unit
end

local function redirectShot(data)
    if type(data) ~= "table" or typeof(data.Origin) ~= "Vector3"
        or typeof(data.Direction) ~= "Vector3" or type(data.Network) ~= "table"
        or data.Network.Player ~= LocalPlayer or data.Network.Character ~= LocalPlayer.Character then
        return data
    end
    local target = selectTarget(workspace.CurrentCamera, data.Origin)
    if not target then
        return data
    end
    local direction = solveDirection(data.Origin, target, data.Force, data.Gravity)
    local look = direction and getShotLook(data, direction)
    if not look then
        return data
    end
    local shot = table.clone(data)
    shot.Misc = table.clone(data.Misc)
    shot.Direction = direction
    local up = data.Misc.CamCFrame.UpVector
    if math.abs(look:Dot(up)) > 0.99 then
        up = Vector3.xAxis
    end
    shot.Misc.CamCFrame = CFrame.lookAt(data.Origin, data.Origin + look, up)
    return shot
end

function State:Destroy()
    if not self.Active then
        return
    end
    self.Active = false
    if self.Connection then
        self.Connection:Disconnect()
        self.Connection = nil
    end
    if BulletHandler.Fire == WrappedFire then
        BulletHandler.Fire = OriginalFire
    end
    if self.ESP then
        self.ESP:Destroy()
    end
    if self.Circle then
        pcall(function()
            self.Circle:Remove()
        end)
        self.Circle = nil
    end
    if Environment.FlickESPAndSilentAim == self then
        Environment.FlickESPAndSilentAim = nil
    end
end

local ok, problem = pcall(function()
    State.ESP = createESP({
        Players = Players,
        LocalPlayer = LocalPlayer,
        Config = Config,
        IsEnemy = isEnemy,
    })
    State.Circle = Drawing.new("Circle")
    State.Circle.Visible = false
    State.Circle.Filled = false
    State.Circle.NumSides = 96
    State.Circle.Thickness = 1.5
    State.Circle.Transparency = 1
    State.Circle.Color = Color3.new(1, 1, 1)
    State.Circle.ZIndex = 5

    WrappedFire = function(data, ...)
        if State.Active then
            local redirected, result = pcall(redirectShot, data)
            if redirected then
                data = result
            elseif not aimWarningShown then
                aimWarningShown = true
                warn("Flick shot redirection failed: " .. tostring(result))
            end
        end
        return OriginalFire(data, ...)
    end
    BulletHandler.Fire = WrappedFire
    Environment.FlickESPAndSilentAim = State

    local function update()
        local camera = workspace.CurrentCamera
        State.ESP:Update(camera)
        if camera then
            local viewport = camera.ViewportSize
            State.Circle.Position = viewport * 0.5
            State.Circle.Radius = getRadius(viewport)
            State.Circle.Visible = viewport.X > 0 and viewport.Y > 0
        else
            State.Circle.Visible = false
        end
    end

    update()
    State.Connection = RunService.RenderStepped:Connect(function()
        if not State.Active then
            return
        end
        local updated, failure = pcall(update)
        if not updated then
            State:Destroy()
            warn("Flick display update failed: " .. tostring(failure))
        end
    end)
end)

if not ok then
    State:Destroy()
    warn("Flick initialization failed: " .. tostring(problem), 0)
end

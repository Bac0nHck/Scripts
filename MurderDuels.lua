local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Environment = getgenv()

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

local Runtime = {
    Active = true,
    Connections = {},
    Records = {},
    Drawings = {},
    Target = nil,
    HookCount = 0,
    LastError = nil,
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
                if distance <= bestDistance and visible(character, head.Position, camera) then
                    bestDistance = distance
                    bestPoint = head.Position
                    bestPlayer = player
                end
            end
        end
    end
    self.Target = bestPlayer
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
    if mode == "World" then
        if not source:find("Players." .. LocalPlayer.Name .. ".", 1, true)
            or not (source:find("KnifeClient", 1, true) or source:find("RevolverClient", 1, true)) then
            return
        end
    elseif not source:find("ReplicatedStorage.Extensions.AimMagnetism", 1, true) then
        return
    end
    local original
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
    for _, player in ipairs(Players:GetPlayers()) do
        addPlayer(player)
    end
    connect(Players.PlayerAdded, addPlayer)
    connect(Players.PlayerRemoving, removePlayer)
    installHooks()
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
        task.wait(2)
        if Runtime.Active then
            local success, message = pcall(installHooks)
            if not success and Runtime.LastError ~= tostring(message) then
                Runtime.LastError = tostring(message)
                warn("Murder Duels Silent Aim: " .. Runtime.LastError)
            end
        end
    end
end)

pcall(function()
    warn("t.me/arceusxcommunity")
end)

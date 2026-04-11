local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local localPlayer  = Players.LocalPlayer

local isAlive        = true
local isRespawning   = false
local flingEnabled   = false
local character      = nil
local rootPart       = nil
local humanoid       = nil
local savedVelocity  = nil

local flingPower     = 100
local bounceDelta    = 0.1
local godmodeConnection = nil

local IS_SPECIAL_PLACE = game.PlaceId == 189707

local kickAnim       = nil
local superpunchAnim = nil
local uppercutAnim   = nil

local lib    = loadstring(game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Scripts/refs/heads/main/akadmin-lib.lua"))()
local window = lib.new("Dropkick")
local mainTab = window:addTab("Main")
window:switchTab(mainTab)

local GC_SCAN_INTERVAL = 5
local ZERO_VECTOR      = Vector3.new()
local INF              = math.huge
local lastGcScanTime   = 0

local function scanGcAndHeal()
    local now = os.clock()
    if now - lastGcScanTime < GC_SCAN_INTERVAL then return end
    lastGcScanTime = now

    for _, obj in pairs(getgc(true)) do
        if type(obj) == "table" then
            local hp = rawget(obj, "Health")
            if hp and hp ~= INF then
                rawset(obj, "Health",    INF)
                rawset(obj, "MaxHealth", INF)
            end
        end
    end
end

local function applyGodmodeToCharacter()
    scanGcAndHeal()

    if not localPlayer.Character then return end

    for _, part in pairs(localPlayer.Character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.5)
            part.CanCollide = true
        end
    end

    local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.MaxHealth = INF
        hum.Health    = INF
        hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    end
end

local function enableGodmode()
    applyGodmodeToCharacter()

    if godmodeConnection then
        godmodeConnection:Disconnect()
        godmodeConnection = nil
    end

    local gcTimer = 0
    local GC_HEARTBEAT_FREQ = 5

    godmodeConnection = RunService.Heartbeat:Connect(function(dt)
        if not localPlayer.Character then return end

        local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if hum.MaxHealth ~= INF then hum.MaxHealth = INF end
            hum.Health = hum.MaxHealth
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        end

        gcTimer = gcTimer + dt
        if gcTimer >= GC_HEARTBEAT_FREQ then
            gcTimer = 0
            for _, obj in pairs(getgc(true)) do
                if type(obj) == "table" then
                    local hp = rawget(obj, "Health")
                    if hp and hp ~= INF then
                        rawset(obj, "Health",    INF)
                        rawset(obj, "MaxHealth", INF)
                    end
                end
            end
        end
    end)
end

local function doFling()
    if not flingEnabled or isRespawning or not isAlive then return end
    if not (character and character.Parent) then return end
    if not (rootPart  and rootPart.Parent)  then return end
    if not humanoid or humanoid.Health <= 0  then return end

    savedVelocity = rootPart.AssemblyLinearVelocity
    rootPart.AssemblyLinearVelocity = savedVelocity * flingPower
        + Vector3.new(0, flingPower, 0)

    RunService.RenderStepped:Wait()

    if character and character.Parent and rootPart and rootPart.Parent then
        rootPart.AssemblyLinearVelocity = savedVelocity
    end

    RunService.Stepped:Wait()

    if character and character.Parent and rootPart and rootPart.Parent then
        rootPart.AssemblyLinearVelocity = savedVelocity + Vector3.new(0, bounceDelta, 0)
        bounceDelta = bounceDelta * -1
    end
end

window:addConnection(RunService.Heartbeat, function()
    if localPlayer.Character and not isRespawning then
        local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            isAlive = true
        end
    end
end)

character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
rootPart  = character:WaitForChild("HumanoidRootPart", 5)
humanoid  = character:WaitForChild("Humanoid", 5)

if humanoid then
    humanoid.Died:Connect(function()
        isAlive = false
    end)
end

if IS_SPECIAL_PLACE then
    flingEnabled = true
    enableGodmode()
end

window:addConnection(localPlayer.CharacterAdded, function(newCharacter)
    isRespawning = true
    isAlive      = false
    task.wait(0.2)

    character = newCharacter
    rootPart  = newCharacter:WaitForChild("HumanoidRootPart", 5)
    humanoid  = newCharacter:WaitForChild("Humanoid", 5)

    if humanoid then
        humanoid.Died:Connect(function()
            isAlive = false
        end)
    end

    isAlive = true
    task.wait(1)

    flingEnabled = IS_SPECIAL_PLACE or flingEnabled
    enableGodmode()
    isRespawning = false
end)

local ownPartsCache  = {}
local lastOwnChar    = nil
local otherCharCache = {}

local function rebuildOwnCache(char)
    ownPartsCache = {}
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(ownPartsCache, part)
        end
    end
    lastOwnChar = char
end

local function rebuildOtherCache(player, char)
    local parts = {}
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(parts, part)
        end
    end

    char.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end)

    otherCharCache[player] = { char = char, parts = parts }
end

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= localPlayer then
        if player.Character then
            rebuildOtherCache(player, player.Character)
        end
        window:addConnection(player.CharacterAdded, function(char)
            task.wait(0.1)
            rebuildOtherCache(player, char)
        end)
        window:addConnection(player.CharacterRemoving, function()
            otherCharCache[player] = nil
        end)
    end
end

window:addConnection(Players.PlayerAdded, function(player)
    if player == localPlayer then return end

    if player.Character then
        task.wait(0.1)
        rebuildOtherCache(player, player.Character)
    end

    window:addConnection(player.CharacterAdded, function(char)
        task.wait(0.1)
        rebuildOtherCache(player, char)
    end)
    window:addConnection(player.CharacterRemoving, function()
        otherCharCache[player] = nil
    end)
end)

window:addConnection(Players.PlayerRemoving, function(player)
    otherCharCache[player] = nil
end)

window:addConnection(RunService.Stepped, function()
    local currentChar = localPlayer.Character
    if currentChar then
        if currentChar ~= lastOwnChar then
            rebuildOwnCache(currentChar)
            window:addConnection(currentChar.DescendantAdded, function(d)
                if d:IsA("BasePart") then
                    table.insert(ownPartsCache, d)
                end
            end)
        end

        for _, part in ipairs(ownPartsCache) do
            if part and part.Parent then
                part.CanCollide = false
            end
        end
    end

    for _, data in pairs(otherCharCache) do
        if data.char and data.char.Parent then
            pcall(function()
                for _, part in ipairs(data.parts) do
                    if part and part.Parent and part.CanCollide then
                        part.CanCollide = false
                        if part.Name == "Torso" then
                            part.Massless = true
                        end
                        part.AssemblyLinearVelocity  = ZERO_VECTOR
                        part.AssemblyAngularVelocity = ZERO_VECTOR
                    end
                end
            end)
        end
    end
end)

window:addConnection(RunService.Heartbeat, doFling)

window:onClose(function()
    if godmodeConnection then
        godmodeConnection:Disconnect()
        godmodeConnection = nil
    end
    flingEnabled = false
    isAlive      = false
end)

if not IS_SPECIAL_PLACE then
    window:addToggle("Fling", false, function(state)
        flingEnabled = state
    end)
end

window:addSlider("Fling Power", 0, 300, flingPower, function(value)
    flingPower = value
end)

window:addHoldButton("Kick", Enum.KeyCode.E, 1,
    function()
        if not character then return end
        local hum = character:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if animator then
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://133566007754001"
            kickAnim = animator:LoadAnimation(anim)
            kickAnim:Play()
        end
    end,
    function()
        if kickAnim and kickAnim.IsPlaying then
            kickAnim:Stop()
        end
    end
)

window:addHoldButton("Superpunch", Enum.KeyCode.Q, 4.3,
    function()
        if not character then return end
        local hum = character:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if animator then
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://120660579076199"
            superpunchAnim = animator:LoadAnimation(anim)
            superpunchAnim:Play()
            superpunchAnim:AdjustSpeed(4.3)
        end
    end,
    function()
        if superpunchAnim and superpunchAnim.IsPlaying then
            superpunchAnim:Stop()
        end
    end
)

window:addHoldButton("Uppercut", Enum.KeyCode.R, 1,
    function()
        if not character then return end
        local hum = character:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if animator then
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://127690758361013"
            uppercutAnim = animator:LoadAnimation(anim)
            uppercutAnim:Play()
        end
    end,
    function()
        if uppercutAnim and uppercutAnim.IsPlaying then
            uppercutAnim:Stop()
        end
    end
)

window:switchTab(mainTab)

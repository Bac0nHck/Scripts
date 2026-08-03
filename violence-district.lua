if getgenv and getgenv().VDHub and type(getgenv().VDHub.Unload) == "function" then
    pcall(getgenv().VDHub.Unload)
    task.wait(0.2)
end

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local function detectMobile()
    if LP:GetAttribute("platform") == "Mobile" then return true end
    if LP:GetAttribute("platform") == "PC" or LP:GetAttribute("platform") == "Console" then return false end
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local IS_MOBILE = detectMobile()

local State = {
    AutoRepair = false,
    RepairRadius = 60,
    RepairTeleport = true,
    RepairPreferProgress = true,
    RepairResume = true,
    AutoSafe = true,
    SafeDistance = 40,
    SafeFlee = true,
    AutoSkillCheck = false,
    SkillCheckOffset = 2,
    SkillCheckMode = "Great",
    SkillCheckMethod = "Input",
    UnlockMouse = true,
    AutoHealSelf = false,
    AutoHealTeam = false,
    HealTeleport = true,
    HealRadius = 40,
    AutoUnhook = false,
    UnhookTeleport = true,
    UnhookRadius = 150,
    AutoSelfUnhook = false,
    SelfUnhookInterval = 1.5,
    AutoLever = false,
    LeverTeleport = true,
    AutoEscape = false,
    AutoVault = false,
    AutoPalletDrop = false,
    AutoPalletSlide = false,
    DangerDistance = 22,
    LoopRadius = 26,
    AlwaysSprint = false,
    AutoBandage = false,
    AutoAdrenaline = false,
    AutoParry = false,
    ParryRange = 14,
    ParryCooldown = 1.2,
    AutoGun = false,
    GunRange = 90,
    AutoShield = false,
    AutoHolyWater = false,
    AutoTracker = false,
    AfkFarm = false,
    HideSkillCheck = false,

    KillerAutoAttack = false,
    KillerAttackRange = 12,
    KillerHoldTime = 0.2,
    KillerFaceOnly = true,
    KillerAutoFace = false,
    KillerFaceSmooth = 0.35,
    KillerAutoCarry = false,
    KillerAutoHook = false,
    KillerAutoBreakPallet = false,
    KillerAutoBreakGen = false,
    KillerAutoVault = false,
    KillerActionRadius = 45,
    KillerChase = false,
    KillerChaseDistance = 6,
    KillerChaseHeight = 0,
    KillerAutoPower = false,
    KillerPowerInterval = 6,
    KillerAutoSecondary = false,
    KillerFastStun = false,
    KillerKillAura = false,

    EspMaster = false,
    EspSurvivor = true,
    EspKiller = true,
    EspGenerator = true,
    EspHook = false,
    EspPallet = false,
    EspWindow = false,
    EspExit = true,
    EspEscape = true,
    EspItem = false,
    EspCustomTag = "",
    RevealInvisible = false,
    EspHighlight = not IS_MOBILE,
    EspTracer = false,
    EspDistance = true,
    EspHealth = true,
    EspStatus = true,
    EspMaxDistance = 1200,
    EspRate = IS_MOBILE and 6 or 15,
    EspTextSize = IS_MOBILE and 13 or 14,
    ColorSurvivor = Color3.fromRGB(85, 255, 140),
    ColorKiller = Color3.fromRGB(255, 65, 65),
    ColorGenerator = Color3.fromRGB(255, 205, 75),
    ColorHook = Color3.fromRGB(190, 120, 255),
    ColorPallet = Color3.fromRGB(120, 200, 255),
    ColorWindow = Color3.fromRGB(90, 160, 255),
    ColorExit = Color3.fromRGB(255, 140, 60),
    ColorEscape = Color3.fromRGB(120, 255, 255),
    ColorItem = Color3.fromRGB(255, 255, 255),

    WalkSpeed = 0,
    JumpPower = 0,
    InfiniteJump = false,
    NoClip = false,
    Fly = false,
    FlySpeed = 60,
    FreeCam = false,
    FreeCamSpeed = 2,
    UnlimitedZoom = false,
    ThirdPerson = false,
    NoShadows = false,
    NoAtmosphere = false,
    AntiFlashlight = false,
    FieldOfView = 0,
    FullBright = false,
    BrightnessValue = 2,
    NoFog = false,
    NoBlind = false,
    NoShake = false,
    AntiAfk = false,
    KeepAfterTeleport = true,
    KillerWarning = false,
    WarningDistance = 30,
    FpsCap = 0,
}

local Connections = {}
local Threads = {}
local Unloaded = false
local interfaceOpen

local function track(conn)
    table.insert(Connections, conn)
    return conn
end

local LastWarn = 0

local function loop(interval, fn)
    local thread = task.spawn(function()
        while not Unloaded and not Fluent.Unloaded do
            local ok, err = pcall(fn)
            if not ok and err and os.clock() - LastWarn > 5 then
                LastWarn = os.clock()
                warn("[VD] " .. tostring(err))
            end
            local wait = type(interval) == "function" and interval() or interval
            task.wait(math.max(wait or 0, 0))
        end
    end)
    table.insert(Threads, thread)
    return thread
end

local function notify(title, content, duration)
    Fluent:Notify({ Title = title, Content = content, Duration = duration or 4 })
end

local function getCharacter()
    return LP.Character
end

local function getRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getInteract()
    local c = LP.Character
    return c and c:FindFirstChild("CheckInterractable")
end

local function teamName()
    return LP.Team and LP.Team.Name or "None"
end

local function isSurvivor()
    return teamName() == "Survivors"
end

local function isKiller()
    return teamName() == "Killer"
end

local function alive()
    local h = getHumanoid()
    return h and h.Health > 0
end

local RemoteCache = {}

local function remote(path)
    local cached = RemoteCache[path]
    if cached then
        if cached.Parent and cached:IsDescendantOf(game) then return cached end
        RemoteCache[path] = nil
    end
    local node = ReplicatedStorage:FindFirstChild("Remotes")
    if not node then return nil end
    for part in string.gmatch(path, "[^/]+") do
        node = node and node:FindFirstChild(part)
        if not node then return nil end
    end
    RemoteCache[path] = node
    return node
end

local function fire(path, ...)
    local r = remote(path)
    if not r then return false end
    local ok = pcall(function(...)
        if r:IsA("RemoteEvent") then
            r:FireServer(...)
        elseif r:IsA("BindableEvent") then
            r:Fire(...)
        end
    end, ...)
    return ok
end

local function busy()
    local root = getRoot()
    if not root then return true end
    local ok, res = pcall(function() return root:HasTag("doing action") end)
    return ok and res or false
end

local function blockedState()
    local c = getCharacter()
    if not c then return true end
    if c:GetAttribute("IsHooked") or c:GetAttribute("IsCarried") or c:GetAttribute("Knocked") then return true end
    local rag = c:FindFirstChild("RagdollTrigger")
    if rag and rag:IsA("ValueBase") and rag.Value == true then return true end
    return false
end

local function tagged(tag)
    local ok, res = pcall(function() return CollectionService:GetTagged(tag) end)
    if ok then return res end
    return {}
end

local function partPosition(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then
        if inst.PrimaryPart then return inst.PrimaryPart.Position end
        local ok, pivot = pcall(function() return inst:GetPivot().Position end)
        if ok then return pivot end
    end
    return nil
end

local function distanceTo(inst)
    local root = getRoot()
    local pos = partPosition(inst)
    if not root or not pos then return math.huge end
    return (pos - root.Position).Magnitude
end

local function nearestTagged(tag, maxDistance, filter)
    local root = getRoot()
    if not root then return nil, math.huge end
    local best, bestDistance = nil, maxDistance or math.huge
    local own = LP.Character
    for _, inst in ipairs(tagged(tag)) do
        if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) and not (own and inst:IsDescendantOf(own)) then
            local blocked = inst.Parent and CollectionService:HasTag(inst.Parent, "Blocked")
            if not blocked and (not filter or filter(inst)) then
                local d = (inst.Position - root.Position).Magnitude
                if d < bestDistance then
                    best, bestDistance = inst, d
                end
            end
        end
    end
    return best, bestDistance
end

local function killerCharacter()
    for _, inst in ipairs(tagged("Killer")) do
        if inst:IsA("Model") and inst:IsDescendantOf(Workspace) then return inst end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Team and p.Team.Name == "Killer" and p.Character then return p.Character end
    end
    return nil
end

local function survivorCharacters(includeSelf)
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if (includeSelf or p ~= LP) and p.Team and p.Team.Name == "Survivors" then
            local c = p.Character
            if c and c:FindFirstChild("HumanoidRootPart") then
                table.insert(list, c)
            end
        end
    end
    return list
end

local function killerDistance()
    local root = getRoot()
    local kc = killerCharacter()
    if not root or not kc then return math.huge end
    local krp = kc:FindFirstChild("HumanoidRootPart")
    if not krp then return math.huge end
    return (krp.Position - root.Position).Magnitude
end

local function safeTeleport(cframe)
    local root = getRoot()
    if not root or not cframe then return false end
    pcall(function() root.CFrame = cframe end)
    return true
end

local function faceCFrame(fromPosition, targetPosition)
    return CFrame.lookAt(fromPosition, Vector3.new(targetPosition.X, fromPosition.Y, targetPosition.Z))
end

local function mobileActionButton()
    local gui = LP:FindFirstChild("PlayerGui")
    if not gui then return nil end
    for _, name in ipairs({ "Survivor-mob", "Slasher-mob" }) do
        local mob = gui:FindFirstChild(name)
        local controls = mob and mob:FindFirstChild("Controls")
        local action = controls and controls:FindFirstChild("action")
        if action and action:IsA("GuiButton") then return action end
    end
    return nil
end

local function pressAction()
    local done = false
    pcall(function()
        local box = UserInputService:GetFocusedTextBox()
        if box then box:ReleaseFocus(false) end
    end)
    local button = mobileActionButton()
    if button and firesignal then
        pcall(function()
            firesignal(button.MouseButton1Down)
            done = true
        end)
    end
    if VIM then
        task.spawn(function()
            pcall(function()
                VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.wait(0.03)
                VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
        end)
        done = true
    end
    return done
end

local function pressAttack(holdTime)
    if not VIM then return end
    task.spawn(function()
        pcall(function()
            local vp = Camera.ViewportSize
            local x, y = vp.X * 0.5, vp.Y * 0.5
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
            task.wait(math.clamp(holdTime or 0.15, 0.02, 0.6))
            VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
        end)
    end)
end

local function pressKey(keyCode, holdTime)
    if not VIM then return end
    task.spawn(function()
        pcall(function()
            VIM:SendKeyEvent(true, keyCode, false, game)
            task.wait(holdTime or 0.05)
            VIM:SendKeyEvent(false, keyCode, false, game)
        end)
    end)
end

local function pressRightMouse(holdTime)
    if not VIM then return end
    task.spawn(function()
        pcall(function()
            local vp = Camera.ViewportSize
            local x, y = vp.X * 0.5, vp.Y * 0.5
            VIM:SendMouseButtonEvent(x, y, 1, true, game, 1)
            task.wait(holdTime or 0.1)
            VIM:SendMouseButtonEvent(x, y, 1, false, game, 1)
        end)
    end)
end

local ItemNames = nil

local function itemNameSet()
    if ItemNames then return ItemNames end
    local folder = ReplicatedStorage:FindFirstChild("Items")
    if not folder then return nil end
    ItemNames = {}
    for _, item in ipairs(folder:GetChildren()) do ItemNames[item.Name] = true end
    return ItemNames
end

local function heldItem()
    local c = getCharacter()
    if not c then return nil end
    local names = itemNameSet()
    if not names then return nil end
    for _, obj in ipairs(c:GetChildren()) do
        if (obj:IsA("Tool") or obj:IsA("Model")) and names[obj.Name] then return obj end
    end
    return nil
end

local Parry = { last = 0, hook = nil, killer = nil }

local function doParry()
    local now = tick()
    if now - Parry.last < State.ParryCooldown then return end
    Parry.last = now
    fire("Items/Parrying Dagger/parry")
end

local function bindParryWatcher()
    if Parry.hook then
        pcall(function() Parry.hook:Disconnect() end)
        Parry.hook = nil
    end
    local kc = killerCharacter()
    if not kc then return end
    local hum = kc:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    Parry.killer = kc
    Parry.hook = animator.AnimationPlayed:Connect(function(track)
        if not State.AutoParry or not isSurvivor() then return end
        if track.Priority ~= Enum.AnimationPriority.Action and track.Priority ~= Enum.AnimationPriority.Action2 then return end
        if killerDistance() <= State.ParryRange then doParry() end
    end)
    track(Parry.hook)
end

local function autoGunTick()
    if not State.AutoGun or not isSurvivor() or not alive() then return end
    local tool = heldItem()
    if not tool or tool.Name ~= "Twist of Fate" then return end
    local kc = killerCharacter()
    local hrp = kc and kc:FindFirstChild("HumanoidRootPart")
    local root = getRoot()
    if not hrp or not root then return end
    local dist = (hrp.Position - root.Position).Magnitude
    if dist > State.GunRange then return end
    local direction = (hrp.Position - Camera.CFrame.Position).Unit
    fire("Items/Twist of Fate/Fire", tool, direction)
end

local function autoShieldTick()
    if not State.AutoShield or not isSurvivor() then return end
    if killerDistance() > 18 then return end
    fire("Items/Riot Shield/Rush")
end

local function autoHolyWaterTick()
    if not State.AutoHolyWater or not isSurvivor() then return end
    local kc = killerCharacter()
    local hrp = kc and kc:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if killerDistance() > 40 then return end
    fire("Items/Holy Water/Throw", hrp.Position)
end

local Fly = { velocity = nil, gyro = nil, connection = nil }

local function stopFly()
    if Fly.connection then pcall(function() Fly.connection:Disconnect() end) Fly.connection = nil end
    if Fly.velocity then pcall(function() Fly.velocity:Destroy() end) Fly.velocity = nil end
    if Fly.gyro then pcall(function() Fly.gyro:Destroy() end) Fly.gyro = nil end
    local hum = getHumanoid()
    if hum then pcall(function() hum.PlatformStand = false end) end
end

local function startFly()
    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum then return end
    stopFly()
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bv.Velocity = Vector3.zero
    bv.Parent = root
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    bg.P = 9000
    bg.CFrame = root.CFrame
    bg.Parent = root
    Fly.velocity = bv
    Fly.gyro = bg
    Fly.connection = track(RunService.RenderStepped:Connect(function()
        if not State.Fly or not Fly.velocity or not Fly.velocity.Parent then return end
        local move = Vector3.zero
        local cf = Camera.CFrame
        if IS_MOBILE then
            local h = getHumanoid()
            local dir = h and h.MoveDirection or Vector3.zero
            move = dir * State.FlySpeed
            if move.Magnitude < 0.1 then move = Vector3.zero end
        else
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + cf.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - cf.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then move = move - Vector3.new(0, 1, 0) end
            if move.Magnitude > 0 then move = move.Unit * State.FlySpeed end
        end
        Fly.velocity.Velocity = move
        Fly.gyro.CFrame = cf
    end))
end

local FreeCam = { connection = nil, inputConnection = nil, position = nil, yaw = 0, pitch = 0, prevType = nil }

local function stopFreeCam()
    if FreeCam.connection then pcall(function() FreeCam.connection:Disconnect() end) FreeCam.connection = nil end
    if FreeCam.inputConnection then pcall(function() FreeCam.inputConnection:Disconnect() end) FreeCam.inputConnection = nil end
    pcall(function()
        Camera.CameraType = FreeCam.prevType or Enum.CameraType.Custom
        if FreeCam.prevSubject and FreeCam.prevSubject.Parent then
            Camera.CameraSubject = FreeCam.prevSubject
        else
            local hum = getHumanoid()
            if hum then Camera.CameraSubject = hum end
        end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end)
    FreeCam.prevType = nil
    FreeCam.prevSubject = nil
    FreeCam.position = nil
end

local function startFreeCam()
    stopFreeCam()
    local cf = Camera.CFrame
    FreeCam.prevType = Camera.CameraType
    FreeCam.prevSubject = Camera.CameraSubject
    FreeCam.position = cf.Position
    local look = cf.LookVector
    FreeCam.yaw = math.atan2(-look.X, -look.Z)
    FreeCam.pitch = math.asin(math.clamp(look.Y, -1, 1))
    Camera.CameraType = Enum.CameraType.Scriptable

    FreeCam.inputConnection = track(UserInputService.InputChanged:Connect(function(input, processed)
        if not State.FreeCam then return end
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Delta
        FreeCam.yaw = FreeCam.yaw - delta.X * 0.005
        FreeCam.pitch = math.clamp(FreeCam.pitch - delta.Y * 0.005, -1.45, 1.45)
    end))

    FreeCam.connection = track(RunService.RenderStepped:Connect(function(dt)
        if not State.FreeCam or not FreeCam.position then return end
        if Camera.CameraType ~= Enum.CameraType.Scriptable then
            Camera.CameraType = Enum.CameraType.Scriptable
        end
        if not IS_MOBILE and not interfaceOpen() and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
        local rotation = CFrame.fromEulerAnglesYXZ(FreeCam.pitch, FreeCam.yaw, 0)
        local move = Vector3.zero
        if IS_MOBILE then
            local hum = getHumanoid()
            local dir = hum and hum.MoveDirection or Vector3.zero
            if dir.Magnitude > 0.05 then
                move = rotation.LookVector * -dir.Z + rotation.RightVector * dir.X
            end
        else
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + rotation.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - rotation.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - rotation.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + rotation.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.E) then move = move + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) then move = move - Vector3.new(0, 1, 0) end
        end
        if move.Magnitude > 0 then move = move.Unit end
        FreeCam.position = FreeCam.position + move * State.FreeCamSpeed * dt * 20
        Camera.CFrame = CFrame.new(FreeCam.position) * rotation
    end))
end

local function revealInvisibleStep()
    if not State.RevealInvisible then return end
    local kc = killerCharacter()
    if not kc then return end
    for _, part in ipairs(kc:GetDescendants()) do
        if part:IsA("BasePart") and part.Transparency > 0.4 and part.Name ~= "HumanoidRootPart" then
            pcall(function() part.LocalTransparencyModifier = 0 part.Transparency = 0.25 end)
        end
    end
end

local Persist = { source = nil, status = "not armed" }

local function resolveLoaderSource()
    if getgenv then
        local custom = getgenv().VDHubLoader
        if type(custom) == "string" and #custom > 8 then return custom, "custom loader" end
    end
    if isfile and readfile then
        for _, name in ipairs({ "vd.lua", "VDHub.lua", "violence-district.lua", "ViolenceDistrict.lua" }) do
            local ok, exists = pcall(isfile, name)
            if ok and exists then
                return "local ok, src = pcall(readfile, \"" .. name .. "\") if ok and src then pcall(loadstring(src, \"vd\")) end", name
            end
        end
    end
    return nil, "no source found"
end

local function armTeleportPersist()
    if not State.KeepAfterTeleport then
        Persist.status = "disabled"
        return
    end
    local queueFn = queue_on_teleport or (syn and syn.queue_on_teleport) or queueonteleport
    if not queueFn then
        Persist.status = "executor has no queue_on_teleport"
        return
    end
    local source, label = resolveLoaderSource()
    if not source then
        Persist.status = "no loader source, set getgenv().VDHubLoader"
        return
    end
    Persist.source = label
    local ok = pcall(queueFn, "task.wait(4)\n" .. source)
    Persist.status = ok and ("armed via " .. tostring(label)) or "queue call failed"
end

local EspFolder = Instance.new("Folder")
EspFolder.Name = "VDEsp_" .. tostring(math.random(10000, 99999))
pcall(function()
    EspFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not EspFolder.Parent then EspFolder.Parent = LP:WaitForChild("PlayerGui") end

local TracerGui = Instance.new("ScreenGui")
TracerGui.Name = "VDTracers"
TracerGui.ResetOnSpawn = false
TracerGui.IgnoreGuiInset = true
TracerGui.DisplayOrder = 9
TracerGui.Parent = EspFolder

local EspEntries = {}

local function destroyEntry(key)
    local entry = EspEntries[key]
    if not entry then return end
    if entry.highlight then pcall(function() entry.highlight:Destroy() end) end
    if entry.billboard then pcall(function() entry.billboard:Destroy() end) end
    if entry.tracer then pcall(function() entry.tracer:Destroy() end) end
    EspEntries[key] = nil
end

local function clearEsp()
    for key in pairs(EspEntries) do destroyEntry(key) end
end

local function ensureEntry(inst, color, text, adornee)
    local entry = EspEntries[inst]
    if not entry then
        entry = { instance = inst }
        EspEntries[inst] = entry
    end
    entry.alive = true
    entry.color = color

    if State.EspHighlight then
        if not entry.highlight or not entry.highlight.Parent then
            local hl = Instance.new("Highlight")
            hl.FillTransparency = 0.72
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = EspFolder
            entry.highlight = hl
        end
        entry.highlight.Adornee = inst
        entry.highlight.FillColor = color
        entry.highlight.OutlineColor = color
        entry.highlight.Enabled = true
    elseif entry.highlight then
        entry.highlight.Enabled = false
    end

    if not entry.billboard or not entry.billboard.Parent then
        local bb = Instance.new("BillboardGui")
        bb.Name = "VDTag"
        bb.AlwaysOnTop = true
        bb.Size = UDim2.fromOffset(220, 40)
        bb.StudsOffset = Vector3.new(0, 2.6, 0)
        bb.MaxDistance = State.EspMaxDistance
        bb.LightInfluence = 0
        bb.Parent = EspFolder
        local label = Instance.new("TextLabel")
        label.Name = "Text"
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextSize = State.EspTextSize
        label.TextStrokeTransparency = 0.35
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.RichText = false
        label.Parent = bb
        entry.billboard = bb
        entry.label = label
    end

    local target = adornee or inst
    if target:IsA("Model") then
        target = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
    end
    entry.billboard.Adornee = target
    entry.billboard.MaxDistance = State.EspMaxDistance
    entry.label.TextSize = State.EspTextSize
    entry.label.Text = text
    entry.label.TextColor3 = color

    if State.EspTracer then
        if not entry.tracer or not entry.tracer.Parent then
            local frame = Instance.new("Frame")
            frame.Name = "Tracer"
            frame.BorderSizePixel = 0
            frame.AnchorPoint = Vector2.new(0.5, 0.5)
            frame.Size = UDim2.fromOffset(1, 1)
            frame.Parent = TracerGui
            entry.tracer = frame
        end
        entry.tracer.BackgroundColor3 = color
    elseif entry.tracer then
        entry.tracer.Visible = false
    end
end

local function statusOf(model)
    local parts = {}
    if model:GetAttribute("IsHooked") then table.insert(parts, "HOOKED") end
    if model:GetAttribute("IsCarried") then table.insert(parts, "CARRIED") end
    if model:GetAttribute("Knocked") then table.insert(parts, "DOWN") end
    if model:GetAttribute("IsChased") then table.insert(parts, "CHASED") end
    local repairing = model:GetAttribute("repairing")
    if typeof(repairing) == "number" and repairing > 0 then table.insert(parts, "GEN") end
    if model:GetAttribute("IsUnhooking") then table.insert(parts, "RESCUE") end
    if #parts == 0 then return "" end
    return " [" .. table.concat(parts, "/") .. "]"
end

local function buildLabel(name, dist, extra)
    local text = name
    if extra and extra ~= "" then text = text .. extra end
    if State.EspDistance and dist then text = text .. " " .. math.floor(dist) .. "m" end
    return text
end

local function refreshEsp()
    if not State.EspMaster then
        if next(EspEntries) then clearEsp() end
        return
    end

    for _, entry in pairs(EspEntries) do entry.alive = false end

    local root = getRoot()
    local origin = root and root.Position or (Camera and Camera.CFrame.Position)
    if not origin then return end

    local function consider(inst, color, text, adornee)
        local pos = partPosition(inst)
        if not pos then return end
        if (pos - origin).Magnitude > State.EspMaxDistance then return end
        ensureEntry(inst, color, text, adornee)
    end

    if State.EspSurvivor then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Team and p.Team.Name == "Survivors" and p ~= LP then
                local c = p.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local hum = c:FindFirstChildOfClass("Humanoid")
                    local name = p.DisplayName ~= "" and p.DisplayName or p.Name
                    if State.EspHealth and hum then
                        name = name .. " " .. math.floor(hum.Health)
                    end
                    local extra = State.EspStatus and statusOf(c) or ""
                    consider(c, State.ColorSurvivor, buildLabel(name, (hrp.Position - origin).Magnitude, extra), hrp)
                end
            end
        end
    end

    if State.EspKiller then
        local kc = killerCharacter()
        if kc and kc ~= LP.Character then
            local hrp = kc:FindFirstChild("HumanoidRootPart")
            if hrp then
                local bl = kc:GetAttribute("BloodLust") or 0
                local extra = State.EspStatus and (" [KILLER BL" .. tostring(bl) .. "]") or " [KILLER]"
                consider(kc, State.ColorKiller, buildLabel(kc.Name, (hrp.Position - origin).Magnitude, extra), hrp)
            end
        end
    end

    if State.EspGenerator then
        for _, gen in ipairs(tagged("Generator")) do
            if gen:IsDescendantOf(Workspace) then
                local body = gen:IsA("Model") and (gen:FindFirstChild("GeneratorBody") or gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart")) or gen
                if body and not body:IsA("BasePart") then body = body:FindFirstChildWhichIsA("BasePart", true) end
                if body then
                    local progress = gen:GetAttribute("RepairProgress") or 0
                    local tagText = "GEN " .. string.format("%.0f%%", progress)
                    if gen:GetAttribute("Regressing") then tagText = tagText .. " -" end
                    local count = gen:GetAttribute("PlayersRepairingCount") or 0
                    if count > 0 then tagText = tagText .. " (" .. count .. ")" end
                    local color = State.ColorGenerator
                    if progress >= 100 then color = Color3.fromRGB(120, 255, 120) end
                    consider(gen, color, buildLabel(tagText, (body.Position - origin).Magnitude, ""), body)
                end
            end
        end
    end

    if State.EspHook then
        for _, hook in ipairs(tagged("HookPoint")) do
            if hook:IsA("BasePart") then
                consider(hook, State.ColorHook, buildLabel("Hook", (hook.Position - origin).Magnitude, ""), hook)
            end
        end
    end

    if State.EspPallet then
        for _, pal in ipairs(tagged("PalletPoint")) do
            if pal:IsA("BasePart") then
                consider(pal, State.ColorPallet, buildLabel("Pallet", (pal.Position - origin).Magnitude, ""), pal)
            end
        end
        for _, pal in ipairs(tagged("PalletPointSlide")) do
            if pal:IsA("BasePart") then
                consider(pal, State.ColorPallet, buildLabel("Pallet Down", (pal.Position - origin).Magnitude, ""), pal)
            end
        end
    end

    if State.EspWindow then
        for _, win in ipairs(tagged("VaultPoint")) do
            if win:IsA("BasePart") then
                consider(win, State.ColorWindow, buildLabel("Window", (win.Position - origin).Magnitude, ""), win)
            end
        end
    end

    if State.EspExit then
        for _, ex in ipairs(tagged("Exit")) do
            if ex:IsA("BasePart") then
                consider(ex, State.ColorExit, buildLabel("Exit Lever", (ex.Position - origin).Magnitude, ""), ex)
            end
        end
        for _, ex in ipairs(tagged("ExitPoint")) do
            if ex:IsA("BasePart") then
                consider(ex, State.ColorExit, buildLabel("Lever Ready", (ex.Position - origin).Magnitude, ""), ex)
            end
        end
    end

    if State.EspEscape then
        for _, ep in ipairs(tagged("EscapePart")) do
            if ep:IsA("BasePart") then
                consider(ep, State.ColorEscape, buildLabel("ESCAPE", (ep.Position - origin).Magnitude, ""), ep)
            end
        end
    end

    if State.EspItem then
        for _, item in ipairs(tagged("Item")) do
            if item:IsDescendantOf(Workspace) then
                local pos = partPosition(item)
                if pos then
                    consider(item, State.ColorItem, buildLabel(item.Name, (pos - origin).Magnitude, ""), item)
                end
            end
        end
    end

    if State.EspCustomTag ~= "" then
        for _, obj in ipairs(tagged(State.EspCustomTag)) do
            if obj:IsDescendantOf(Workspace) then
                local pos = partPosition(obj)
                if pos then
                    consider(obj, Color3.fromRGB(255, 0, 200), buildLabel(State.EspCustomTag, (pos - origin).Magnitude, ""), obj)
                end
            end
        end
    end

    for key, entry in pairs(EspEntries) do
        if not entry.alive or not key or not key.Parent then
            destroyEntry(key)
        end
    end
end

local function updateTracers()
    if not State.EspMaster or not State.EspTracer then
        for _, entry in pairs(EspEntries) do
            if entry.tracer then entry.tracer.Visible = false end
        end
        return
    end
    local vp = Camera.ViewportSize
    local originX, originY = vp.X * 0.5, vp.Y
    for inst, entry in pairs(EspEntries) do
        local frame = entry.tracer
        if frame then
            local pos = partPosition(inst)
            if pos then
                local screen, onScreen = Camera:WorldToViewportPoint(pos)
                if onScreen then
                    local dx, dy = screen.X - originX, screen.Y - originY
                    local length = math.sqrt(dx * dx + dy * dy)
                    frame.Visible = true
                    frame.Size = UDim2.fromOffset(1, length)
                    frame.Position = UDim2.fromOffset(originX + dx * 0.5, originY + dy * 0.5)
                    frame.Rotation = math.deg(math.atan2(dy, dx)) - 90
                else
                    frame.Visible = false
                end
            else
                frame.Visible = false
            end
        end
    end
end

local Repair = { point = nil }
local Heal = { target = nil }
local Lever = { point = nil }
local SkillCheck = {
    candidates = {},
    nextBuild = 0,
    fired = false,
    lastRotation = nil,
    seen = 0,
    attempts = 0,
    lastInfo = "waiting",
    lastArgs = nil,
    lastKind = nil,
}

local function stopRepair()
    if Repair.point then
        fire("Generator/RepairEvent", Repair.point, false)
        Repair.point = nil
    end
    local ci = getInteract()
    if ci then ci:SetAttribute("isRepairing", false) end
    local root = getRoot()
    if root then root.Anchored = false end
    local hum = getHumanoid()
    if hum then hum.AutoRotate = true end
end

local function settle(seconds)
    task.wait(seconds or 0.35)
    return not Unloaded
end

local function startRepair(point)
    local root, hum, ci = getRoot(), getHumanoid(), getInteract()
    if not root or not hum then return end
    local parent = point.Parent
    local body = parent and (parent:FindFirstChild("GeneratorBody") or parent.PrimaryPart)
    local lookAt = body and body.Position or point.Position
    local goal = faceCFrame(point.Position, lookAt)
    if State.RepairTeleport and (root.Position - point.Position).Magnitude > 2 then
        root.CFrame = goal
        if not settle(0.35) then return end
        root = getRoot()
        hum = getHumanoid()
        ci = getInteract()
        if not root or not hum then return end
        if not State.AutoRepair or not isSurvivor() then return end
    end
    if ci then ci:SetAttribute("isRepairing", true) end
    hum.AutoRotate = false
    root.CFrame = goal
    root.Anchored = true
    fire("Generator/RepairEvent", point, true)
    Repair.point = point
end

local function generatorOf(point)
    return point and point.Parent
end

local function generatorValid(point)
    local gen = generatorOf(point)
    if not gen then return false end
    local progress = gen:GetAttribute("RepairProgress") or 0
    return progress < 100
end

local function killerRootPart()
    local kc = killerCharacter()
    return kc and kc:FindFirstChild("HumanoidRootPart") or nil
end

local function killerDistanceTo(position)
    local krp = killerRootPart()
    if not krp or not position then return math.huge end
    return (krp.Position - position).Magnitude
end

local function pointIsSafe(point)
    if not State.AutoSafe then return true end
    if not point then return false end
    return killerDistanceTo(point.Position) > State.SafeDistance
end

local function pickGenerator()
    local root = getRoot()
    if not root then return nil end
    local maxDistance = State.RepairTeleport and 1500 or State.RepairRadius
    local best, bestScore = nil, nil
    for _, point in ipairs(tagged("GeneratorPoint")) do
        if point:IsA("BasePart") and point:IsDescendantOf(Workspace) and pointIsSafe(point) then
            local gen = point.Parent
            local progress = gen and gen:GetAttribute("RepairProgress") or 0
            local dist = (point.Position - root.Position).Magnitude
            if progress < 100 and dist <= maxDistance and not CollectionService:HasTag(point, "GeneratorPointInUse") then
                local score = State.RepairPreferProgress and (1000 - progress * 8 + dist * 0.05) or dist
                if not bestScore or score < bestScore then
                    best, bestScore = point, score
                end
            end
        end
    end
    return best
end

local ForceSkillCheck = nil

local function skillCheckOnScreen()
    for _, entry in ipairs(SkillCheck.candidates) do
        if entry.check.Parent and entry.check.Visible then return true end
    end
    return false
end

local function autoRepairTick()
    if State.AutoRepair and not State.AutoSkillCheck then
        State.AutoSkillCheck = true
        if ForceSkillCheck then pcall(ForceSkillCheck, true) end
    end
    if not State.AutoRepair or not isSurvivor() or not alive() then
        if Repair.point then stopRepair() end
        return
    end
    if blockedState() then
        if Repair.point then stopRepair() end
        return
    end
    local hum = getHumanoid()
    if hum and hum.Health <= 50 and (State.AutoHealSelf or State.AutoHealTeam) then
        if Repair.point and not skillCheckOnScreen() then stopRepair() end
        return
    end
    if Repair.point then
        if not Repair.point.Parent or not generatorValid(Repair.point) then
            stopRepair()
        elseif State.AutoSafe and not pointIsSafe(Repair.point) then
            stopRepair()
            Repair.fleeUntil = os.clock() + 1
        else
            if skillCheckOnScreen() then return end
            local ci = getInteract()
            if ci and ci:GetAttribute("isRepairing") == false and State.RepairResume then
                stopRepair()
            else
                return
            end
        end
    end
    local point = pickGenerator()
    if point then
        startRepair(point)
    elseif State.AutoSafe and State.SafeFlee and Repair.fleeUntil and os.clock() < Repair.fleeUntil + 6 then
        local root = getRoot()
        local krp = killerRootPart()
        if root and krp then
            local away = (root.Position - krp.Position)
            if away.Magnitude > 0.1 and away.Magnitude < State.SafeDistance then
                local hum = getHumanoid()
                if hum then hum:Move(Vector3.new(away.Unit.X, 0, away.Unit.Z), false) end
            end
        end
    end
end

local function buildSkillCandidates()
    local list = {}
    local gui = LP:FindFirstChild("PlayerGui")
    if gui then
        for _, obj in ipairs(gui:GetDescendants()) do
            if obj.Name == "Check" and obj:IsA("GuiObject") then
                local line = obj:FindFirstChild("Line")
                local goal = obj:FindFirstChild("Goal")
                if line and goal and line:IsA("GuiObject") and goal:IsA("GuiObject") then
                    table.insert(list, { check = obj, line = line, goal = goal })
                end
            end
        end
    end
    SkillCheck.candidates = list
    SkillCheck.nextBuild = os.clock() + 2
end

local function activeSkillCheck()
    local sc = SkillCheck
    local now = os.clock()
    local stale = false
    for _, entry in ipairs(sc.candidates) do
        if not entry.check.Parent or not entry.line.Parent then stale = true break end
    end
    if stale or #sc.candidates == 0 or now >= sc.nextBuild then buildSkillCandidates() end
    for _, entry in ipairs(sc.candidates) do
        if entry.check.Visible then return entry end
    end
    return nil
end

local function skillCheckParts()
    local entry = activeSkillCheck()
    if not entry then
        for _, e in ipairs(SkillCheck.candidates) do return e.check, e.line, e.goal end
        return nil
    end
    return entry.check, entry.line, entry.goal
end

local function instantSkillCheck()
    local sc = SkillCheck
    if not sc.lastArgs or not sc.lastKind then return false end
    if os.clock() - (sc.lastArgsTime or 0) > 6 then
        sc.lastArgs = nil
        return false
    end
    local path = sc.lastKind == "heal" and "Healing/SkillCheckResultEvent" or "Generator/SkillCheckResultEvent"
    local grade = State.SkillCheckMode == "Good" and "neutral" or "success"
    local score = grade == "success" and 1 or 0
    local sent = fire(path, grade, score, sc.lastArgs[1], sc.lastArgs[2])
    sc.lastArgs = nil
    if sent then
        sc.instantSent = (sc.instantSent or 0) + 1
        sc.lastMethod = "Instant"
    end
    return sent
end

local function skillCheckStep(delta)
    local sc = SkillCheck
    if not State.AutoSkillCheck then
        sc.fired = false
        sc.lastRotation = nil
        return
    end
    local entry = activeSkillCheck()
    if not entry then
        sc.fired = false
        sc.lastRotation = nil
        return
    end
    local rotation = entry.line.Rotation
    local goalRotation = entry.goal.Rotation
    if sc.lastRotation and rotation < sc.lastRotation - 5 then
        sc.fired = false
    end
    if sc.lastRotation == nil then
        sc.seen = sc.seen + 1
    end
    if sc.fired then
        sc.lastRotation = rotation
        return
    end
    local ci = getInteract()
    if ci and not ci:GetAttribute("isRepairing") and not ci:GetAttribute("isHealing") then
        if Repair.point then
            ci:SetAttribute("isRepairing", true)
        elseif Heal.target then
            ci:SetAttribute("isHealing", true)
        end
    end
    local low, high
    if State.SkillCheckMode == "Good" then
        low, high = 118 + goalRotation, 157 + goalRotation
    else
        low, high = 102 + goalRotation, 116 + goalRotation
    end
    low = low + State.SkillCheckOffset
    high = high + State.SkillCheckOffset
    local dt = math.clamp(delta or (1 / 60), 1 / 480, 1 / 15)
    local speed = 0
    if sc.lastRotation and rotation > sc.lastRotation then
        speed = (rotation - sc.lastRotation) / dt
    end
    local predicted = rotation + speed * dt
    local inside = rotation >= low and rotation <= high
    local entering = predicted >= low and rotation <= high
    local overshooting = rotation < low and predicted > high
    if inside or entering or overshooting then
        sc.fired = true
        sc.attempts = sc.attempts + 1
        sc.lastInfo = string.format("hit at %.0f in [%.0f - %.0f]%s", rotation, low, high, overshooting and " lowfps" or "")
        if State.SkillCheckMethod == "Instant" then
            if not instantSkillCheck() then
                sc.lastMethod = "Input (instant had no data)"
                pressAction()
            end
        else
            sc.lastMethod = "Input"
            pressAction()
        end
    end
    sc.lastRotation = rotation
end

local function bindSkillCheckCapture()
    local generator = remote("Generator/SkillCheckEvent")
    local healing = remote("Healing/SkillCheckEvent")
    if generator then
        track(generator.OnClientEvent:Connect(function(a, b)
            SkillCheck.lastArgs = { a, b }
            SkillCheck.lastKind = "gen"
            SkillCheck.lastArgsTime = os.clock()
            SkillCheck.received = (SkillCheck.received or 0) + 1
        end))
    end
    if healing then
        track(healing.OnClientEvent:Connect(function(a, b)
            SkillCheck.lastArgs = { a, b }
            SkillCheck.lastKind = "heal"
            SkillCheck.lastArgsTime = os.clock()
            SkillCheck.received = (SkillCheck.received or 0) + 1
        end))
    end
    local function bump()
        SkillCheck.validated = (SkillCheck.validated or 0) + 1
    end
    for _, path in ipairs({ "Generator/Skillcheckvalidated", "Healing/Skillcheckvalidated" }) do
        local validated = remote(path)
        if validated then
            if validated:IsA("RemoteEvent") then
                track(validated.OnClientEvent:Connect(bump))
            elseif validated:IsA("BindableEvent") then
                track(validated.Event:Connect(bump))
            end
        end
    end
end

local function stopHeal()
    if Heal.target then
        fire("Healing/HealEvent", Heal.target, false)
        Heal.target = nil
    end
    local ci = getInteract()
    if ci then ci:SetAttribute("isHealing", false) end
end

local function startHeal(target)
    local ci = getInteract()
    if ci then ci:SetAttribute("isHealing", true) end
    fire("Healing/HealEvent", target, true)
    Heal.target = target
end

local function findHealTarget()
    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum then return nil end
    if State.AutoHealSelf and hum.Health <= 50 then
        return root
    end
    if not State.AutoHealTeam then return nil end
    local best, bestDistance = nil, State.HealRadius
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local c = p.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if hrp and h and h.Health > 0 and hrp:GetAttribute("CanGetHealed") == true then
                local d = (hrp.Position - root.Position).Magnitude
                if d < bestDistance then best, bestDistance = hrp, d end
            end
        end
    end
    return best
end

local function autoHealTick()
    if not isSurvivor() or not alive() or blockedState() then
        if Heal.target then stopHeal() end
        return
    end
    if not State.AutoHealSelf and not State.AutoHealTeam then
        if Heal.target then stopHeal() end
        return
    end
    if Heal.target then
        local ci = getInteract()
        if ci and not ci:GetAttribute("isHealing") then
            Heal.target = nil
        else
            local hum = getHumanoid()
            if Heal.target == getRoot() and hum and hum.Health > 95 then stopHeal() end
            return
        end
    end
    local target = findHealTarget()
    if not target then return end
    local root = getRoot()
    if target ~= root and root then
        local gap = (target.Position - root.Position).Magnitude
        if gap > 4 then
            if not State.HealTeleport then return end
            if Repair.point then stopRepair() end
            root.CFrame = faceCFrame(target.Position + target.CFrame.LookVector * 2.5, target.Position)
            if not settle(0.35) then return end
        end
    end
    startHeal(target)
end

local function autoUnhookTick()
    if not State.AutoUnhook or not isSurvivor() or not alive() or blockedState() then return end
    if busy() then return end
    local ci = getInteract()
    if ci and ci:GetAttribute("isUnhooking") then return end
    local point, dist = nearestTagged("UnhookPoint", State.UnhookRadius)
    if not point then return end
    if State.UnhookTeleport and dist > 3.5 then
        local root = getRoot()
        if root then
            if Repair.point then stopRepair() end
            root.CFrame = faceCFrame(point.Position + Vector3.new(0, 0, 2), point.Position)
            if not settle(0.35) then return end
        end
    end
    if ci then ci:SetAttribute("isUnhooking", true) end
    fire("Carry/UnHookEvent", point)
    task.delay(2.2, function()
        local c = getInteract()
        if c then c:SetAttribute("isUnhooking", false) end
    end)
end

local function autoSelfUnhookTick()
    if not State.AutoSelfUnhook or not isSurvivor() then return end
    local c = getCharacter()
    if not c or not c:GetAttribute("IsHooked") then return end
    fire("Carry/SelfUnHookEvent")
end

local function stopLever()
    if Lever.point then
        fire("Exit/LeverEvent", Lever.point, false)
        Lever.point = nil
    end
    local ci = getInteract()
    if ci then ci:SetAttribute("isExiting", false) end
end

local function autoLeverTick()
    if not State.AutoLever or not isSurvivor() or not alive() or blockedState() then
        if Lever.point then stopLever() end
        return
    end
    if Lever.point then
        local ci = getInteract()
        if ci and not ci:GetAttribute("isExiting") then Lever.point = nil else return end
    end
    local point, dist = nearestTagged("ExitPoint", math.huge)
    if not point then return end
    if State.LeverTeleport and dist > 3.5 then
        local root = getRoot()
        if root then
            if Repair.point then stopRepair() end
            root.CFrame = faceCFrame(point.Position + Vector3.new(0, 0, 2), point.Position)
            if not settle(0.35) then return end
        end
    end
    local ci = getInteract()
    if ci then ci:SetAttribute("isExiting", true) end
    fire("Exit/LeverEvent", point, true)
    Lever.point = point
end

local function autoEscapeTick()
    if not State.AutoEscape or not isSurvivor() or not alive() then return end
    local part, dist = nearestTagged("EscapePart", math.huge)
    if not part then return end
    local root = getRoot()
    if root and dist > 4 then
        if Repair.point then stopRepair() end
        root.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
    end
end

local function sprintFlag()
    local c = getCharacter()
    if not c then return false end
    if c:GetAttribute("Crouching") then return false end
    return c:GetAttribute("Sprinting") == true
end

local function autoLoopTick()
    if not isSurvivor() or not alive() or blockedState() then return end
    local hum = getHumanoid()
    if hum and hum.Health <= 50 then return end
    if busy() then return end
    local kd = killerDistance()
    if kd > State.DangerDistance then return end
    local ci = getInteract()

    if State.AutoPalletDrop then
        local point, dist = nearestTagged("PalletPoint", State.LoopRadius)
        if point and dist <= 5 then
            if ci then ci:SetAttribute("isDroppingPallet", true) end
            fire("Pallet/PalletDropEvent", point)
            task.delay(1.2, function()
                local c = getInteract()
                if c then c:SetAttribute("isDroppingPallet", false) end
            end)
            return
        end
    end

    if State.AutoPalletSlide then
        local point, dist = nearestTagged("PalletPointSlide", State.LoopRadius)
        if point and dist <= 5 then
            if ci then ci:SetAttribute("isSliding", true) end
            local sprint = sprintFlag()
            fire("Pallet/PalletSlideEvent", point, sprint)
            fire("Pallet/Slidebindable", point, sprint)
            task.delay(1.4, function()
                local c = getInteract()
                if c then c:SetAttribute("isSliding", false) end
            end)
            return
        end
    end

    if State.AutoVault then
        local point, dist = nearestTagged("VaultPoint", State.LoopRadius)
        if point and dist <= 5 then
            if ci then ci:SetAttribute("isVaulting", true) end
            local sprint = sprintFlag()
            fire("Window/VaultEvent", point, sprint)
            fire("Window/Vaultbindable", point, sprint)
            task.delay(1.5, function()
                local c = getInteract()
                if c then c:SetAttribute("isVaulting", false) end
            end)
        end
    end
end

local function autoItemTick()
    if not isSurvivor() or not alive() then return end
    local hum = getHumanoid()
    local c = getCharacter()
    if not hum or not c then return end
    if State.AutoBandage and hum.Health <= 50 and not c:GetAttribute("Knocked") then
        fire("Items/Bandage/Fire")
    end
    if State.AutoAdrenaline and c:GetAttribute("Knocked") then
        fire("Items/Adrenaline Shot/Knocked")
    end
end

local function nearestSurvivorModel(maxDistance, filter)
    local root = getRoot()
    if not root then return nil, math.huge end
    local best, bestDistance = nil, maxDistance or math.huge
    for _, c in ipairs(survivorCharacters(false)) do
        local hrp = c:FindFirstChild("HumanoidRootPart")
        local hum = c:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 and (not filter or filter(c)) then
            local d = (hrp.Position - root.Position).Magnitude
            if d < bestDistance then best, bestDistance = c, d end
        end
    end
    return best, bestDistance
end

local function validAttackTarget(model)
    if model:GetAttribute("IsCarried") or model:GetAttribute("IsHooked") then return false end
    if model:GetAttribute("Knocked") then return false end
    if model:GetAttribute("Iframes") then return false end
    local rag = model:FindFirstChild("RagdollTrigger")
    if rag and rag:IsA("ValueBase") and rag.Value == true then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return true
end

local function killerAutoAttackTick()
    if not State.KillerAutoAttack or not isKiller() or not alive() then return end
    local c = getCharacter()
    if not c or c:GetAttribute("Immobile") or c:GetAttribute("IsStunned") or c:GetAttribute("IsCarrying") then return end
    local root = getRoot()
    if not root then return end
    local target, dist = nearestSurvivorModel(State.KillerAttackRange, validAttackTarget)
    if not target then return end
    local hrp = target:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if State.KillerFaceOnly then
        local dir = (hrp.Position - root.Position).Unit
        if root.CFrame.LookVector:Dot(dir) < 0.55 then return end
    end
    pressAttack(State.KillerHoldTime)
end

local function killerAutoFaceStep()
    if not State.KillerAutoFace or not isKiller() then return end
    local root = getRoot()
    if not root then return end
    local c = getCharacter()
    if c and (c:GetAttribute("Immobile") or c:GetAttribute("IsStunned")) then return end
    local target = nearestSurvivorModel(State.KillerAttackRange * 2.5, validAttackTarget)
    if not target then return end
    local hrp = target:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local goal = faceCFrame(root.Position, hrp.Position)
    root.CFrame = root.CFrame:Lerp(goal, math.clamp(State.KillerFaceSmooth, 0.05, 1))
end

local ActionLock = 0
local Cooldowns = { carry = 0, hook = 0, pallet = 0, gen = 0, vault = 0 }

local function lockActions(duration)
    ActionLock = os.clock() + duration
end

local function actionsLocked()
    return os.clock() < ActionLock
end

local function killerBusy()
    local c = getCharacter()
    if not c then return true end
    if c:GetAttribute("Immobile") or c:GetAttribute("IsStunned") or c:GetAttribute("LakeMist") then return true end
    local ci = getInteract()
    if ci and ci:GetAttribute("action") == true then return true end
    return false
end

local function killerCommit(targetCFrame, remotePath, remoteArg, verify, duration)
    lockActions(duration or 1.4)
    safeTeleport(targetCFrame)
    if not settle(0.4) then return end
    pressAction()
    if not settle(0.6) then return end
    if verify and verify() then
        fire(remotePath, remoteArg)
    end
end

local function killerAutoCarryTick()
    if not State.KillerAutoCarry or not isKiller() or not alive() then return end
    if actionsLocked() or os.clock() < Cooldowns.carry or killerBusy() then return end
    local c = getCharacter()
    if not c or c:GetAttribute("IsCarrying") then return end
    local target = nearestSurvivorModel(State.KillerActionRadius, function(model)
        return model:GetAttribute("Knocked") == true and not model:GetAttribute("IsCarried") and not model:GetAttribute("IsHooked")
    end)
    if not target then return end
    local hrp = target:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    Cooldowns.carry = os.clock() + 3
    killerCommit(faceCFrame(hrp.Position + hrp.CFrame.LookVector * 2, hrp.Position), "Carry/CarrySurvivorEvent", target, function()
        local ch = getCharacter()
        return ch and not ch:GetAttribute("IsCarrying")
    end)
end

local function killerAutoHookTick()
    if not State.KillerAutoHook or not isKiller() or not alive() then return end
    if actionsLocked() or os.clock() < Cooldowns.hook or killerBusy() then return end
    local c = getCharacter()
    if not c or not c:GetAttribute("IsCarrying") then return end
    local point = nearestTagged("HookPoint", math.huge)
    if not point then return end
    Cooldowns.hook = os.clock() + 4
    killerCommit(point.CFrame * CFrame.new(0, 1.5, 0), "Carry/HookEvent", point, function()
        local ch = getCharacter()
        return ch and ch:GetAttribute("IsCarrying") == true
    end, 2)
end

local function killerBreakPalletTick()
    if not State.KillerAutoBreakPallet or not isKiller() or not alive() then return end
    if actionsLocked() or os.clock() < Cooldowns.pallet or killerBusy() then return end
    local c = getCharacter()
    if not c or c:GetAttribute("IsCarrying") then return end
    local point = nearestTagged("PalletPointSlide", State.KillerActionRadius)
    if not point then return end
    Cooldowns.pallet = os.clock() + 4
    killerCommit(point.CFrame * CFrame.new(0, 1.75, 2), "Pallet/Jason/Destroy-Global", point, function()
        return point.Parent ~= nil
    end, 2.5)
end

local function killerBreakGenTick()
    if not State.KillerAutoBreakGen or not isKiller() or not alive() then return end
    if actionsLocked() or os.clock() < Cooldowns.gen or killerBusy() then return end
    local c = getCharacter()
    if not c or c:GetAttribute("IsCarrying") then return end
    local root = getRoot()
    if not root then return end
    local point = nil
    local bestDistance = State.KillerActionRadius
    for _, p in ipairs(tagged("GeneratorPoint")) do
        if p:IsA("BasePart") and p:IsDescendantOf(Workspace) then
            local gen = p.Parent
            local progress = gen and gen:GetAttribute("RepairProgress") or 0
            local kicks = gen and gen:GetAttribute("kickcount") or 0
            local d = (p.Position - root.Position).Magnitude
            if progress > 0 and progress < 100 and kicks <= 8 and d < bestDistance then
                point, bestDistance = p, d
            end
        end
    end
    if not point then return end
    local gen = point.Parent
    local before = gen and gen:GetAttribute("kickcount") or 0
    Cooldowns.gen = os.clock() + 4
    killerCommit(point.CFrame * CFrame.new(0, 0.8, 1), "Generator/BreakGenEvent", point, function()
        return gen and (gen:GetAttribute("kickcount") or 0) == before
    end, 2.5)
end

local function killerVaultTick()
    if not State.KillerAutoVault or not isKiller() or not alive() then return end
    if actionsLocked() or os.clock() < Cooldowns.vault or killerBusy() then return end
    local c = getCharacter()
    if not c or c:GetAttribute("IsCarrying") then return end
    local point = nearestTagged("VaultPoint", 8)
    if not point then return end
    local target = nearestSurvivorModel(State.KillerAttackRange * 2, validAttackTarget)
    if not target then return end
    Cooldowns.vault = os.clock() + 3
    killerCommit(point.CFrame, "Window/VaultEvent-jason", point, function()
        local ch = getCharacter()
        return ch and not ch:GetAttribute("Immobile")
    end, 2)
end

local function killerChaseStep()
    if not State.KillerChase or not isKiller() or not alive() then return end
    if actionsLocked() then return end
    local root = getRoot()
    if not root then return end
    local target = nearestSurvivorModel(math.huge, validAttackTarget)
    if not target then return end
    local hrp = target:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local direction = (root.Position - hrp.Position)
    if direction.Magnitude < 0.1 then return end
    local offset = direction.Unit * State.KillerChaseDistance
    local goal = faceCFrame(hrp.Position + Vector3.new(offset.X, State.KillerChaseHeight, offset.Z), hrp.Position)
    root.CFrame = root.CFrame:Lerp(goal, 0.35)
end

local function killerPowerTick()
    if not isKiller() or not alive() then return end
    local c = getCharacter()
    if not c or c:GetAttribute("IsStunned") or c:GetAttribute("Immobile") then return end
    if State.KillerAutoPower then pressKey(Enum.KeyCode.Q, 0.08) end
    if State.KillerAutoSecondary then pressRightMouse(0.12) end
end

local function killerFastStunTick()
    if not State.KillerFastStun or not isKiller() then return end
    local c = getCharacter()
    if not c then return end
    if c:GetAttribute("IsStunned") then
        fire("Pallet/Jason/Stunover")
        c:SetAttribute("IsStunned", false)
        c:SetAttribute("Immobile", false)
    end
end

local function antiFlashlightStep()
    if not State.AntiFlashlight then return end
    local gui = LP:FindFirstChild("PlayerGui")
    if not gui then return end
    for _, screen in ipairs(gui:GetChildren()) do
        if screen:IsA("ScreenGui") and (screen.Name == "Darkness" or screen.Name == "effects" or screen.Name == "Killerblood") then
            screen.Enabled = false
        end
    end
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("BlurEffect") or obj:IsA("ColorCorrectionEffect") or obj:IsA("SunRaysEffect") then
            pcall(function() obj.Enabled = false end)
        end
    end
end

local HideApplied = nil

local function hideSkillCheckStep()
    if State.HideSkillCheck == HideApplied then return end
    HideApplied = State.HideSkillCheck
    local value = State.HideSkillCheck and 1 or 0
    for _, entry in ipairs(SkillCheck.candidates) do
        if entry.check.Parent then
            for _, obj in ipairs(entry.check:GetDescendants()) do
                if obj:IsA("ImageLabel") and obj.Name ~= "Line" and obj.Name ~= "Goal" then
                    obj.ImageTransparency = value
                end
            end
        end
    end
end

local LightingDefaults = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
}

local LightingTouched = { bright = false, fog = false, shadows = false }

local function applyLighting()
    if State.FullBright then
        LightingTouched.bright = true
        Lighting.Brightness = State.BrightnessValue
        Lighting.ClockTime = 14
        Lighting.Ambient = Color3.fromRGB(160, 160, 160)
        Lighting.OutdoorAmbient = Color3.fromRGB(160, 160, 160)
    elseif LightingTouched.bright then
        LightingTouched.bright = false
        Lighting.Brightness = LightingDefaults.Brightness
        Lighting.ClockTime = LightingDefaults.ClockTime
        Lighting.Ambient = LightingDefaults.Ambient
        Lighting.OutdoorAmbient = LightingDefaults.OutdoorAmbient
    end
    if State.NoFog then
        LightingTouched.fog = true
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 999999
    elseif LightingTouched.fog then
        LightingTouched.fog = false
        Lighting.FogEnd = LightingDefaults.FogEnd
        Lighting.FogStart = LightingDefaults.FogStart
    end
    if State.NoShadows or State.FullBright then
        LightingTouched.shadows = true
        Lighting.GlobalShadows = false
    elseif LightingTouched.shadows then
        LightingTouched.shadows = false
        Lighting.GlobalShadows = LightingDefaults.GlobalShadows
    end
end

local function applyBlindness()
    local gui = LP:FindFirstChild("PlayerGui")
    if not gui then return end
    for _, name in ipairs({ "Darkness", "Killerblood", "effects" }) do
        local screen = gui:FindFirstChild(name)
        if screen and screen:IsA("ScreenGui") then
            screen.Enabled = not State.NoBlind
        end
    end
    if State.NoBlind then
        for _, obj in ipairs(Lighting:GetChildren()) do
            if obj:IsA("BlurEffect") or obj:IsA("ColorCorrectionEffect") then
                pcall(function() obj.Enabled = false end)
            end
        end
    end
end

local MovementDefaults = { walk = nil, jump = nil, usePower = nil }

local function applyMovement()
    local hum = getHumanoid()
    if not hum then return end
    if State.WalkSpeed > 0 then
        if MovementDefaults.walk == nil then MovementDefaults.walk = hum.WalkSpeed end
        if math.abs(hum.WalkSpeed - State.WalkSpeed) > 0.01 then
            hum.WalkSpeed = State.WalkSpeed
        end
    elseif MovementDefaults.walk ~= nil then
        if MovementDefaults.walk > 0 then hum.WalkSpeed = MovementDefaults.walk end
        MovementDefaults.walk = nil
    end
    if State.JumpPower > 0 then
        if MovementDefaults.jump == nil then
            MovementDefaults.jump = hum.JumpPower
            MovementDefaults.usePower = hum.UseJumpPower
        end
        hum.UseJumpPower = true
        if math.abs(hum.JumpPower - State.JumpPower) > 0.01 then
            hum.JumpPower = State.JumpPower
        end
    elseif MovementDefaults.jump ~= nil then
        hum.JumpPower = MovementDefaults.jump
        hum.UseJumpPower = MovementDefaults.usePower
        MovementDefaults.jump = nil
    end
end

local CollisionMemory = {}

local function applyNoClip()
    local c = getCharacter()
    if not c then return end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            if CollisionMemory[part] == nil then CollisionMemory[part] = part.CanCollide end
            if part.CanCollide then part.CanCollide = false end
        end
    end
end

local function restoreCollision()
    for part, value in pairs(CollisionMemory) do
        if part and part.Parent then pcall(function() part.CanCollide = value end) end
    end
    CollisionMemory = {}
end

local CameraDefaults = { fov = Camera.FieldOfView, maxZoom = LP.CameraMaxZoomDistance, minZoom = LP.CameraMinZoomDistance }

local function applyFov()
    if State.FieldOfView > 0 then
        Camera.FieldOfView = State.FieldOfView
    end
end

local function fpsBoost()
    task.spawn(function()
        local count = 0
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                obj.Material = Enum.Material.SmoothPlastic
                obj.Reflectance = 0
            elseif obj:IsA("Decal") or obj:IsA("Texture") then
                obj.Transparency = 1
            elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
                obj.Enabled = false
            end
            count = count + 1
            if count % 800 == 0 then task.wait() end
        end
        for _, obj in ipairs(Lighting:GetDescendants()) do
            if obj:IsA("PostEffect") then obj.Enabled = false end
        end
        Lighting.GlobalShadows = false
        pcall(function() Workspace.Terrain.WaterWaveSize = 0 end)
        pcall(function() Workspace.Terrain.WaterReflectance = 0 end)
        notify("FPS Boost", "Textures, particles and shadows stripped.", 4)
    end)
end

local Mouse = {
    active = false,
    hooked = false,
    utils = nil,
    realSet = nil,
    modal = nil,
    prevIcon = nil,
    status = "not installed",
}

local function findCameraUtils()
    if Mouse.utils then return Mouse.utils end
    local scripts = LP:FindFirstChildOfClass("PlayerScripts")
    local node = scripts and scripts:FindFirstChild("PlayerModule")
    node = node and node:FindFirstChild("CameraModule")
    node = node and node:FindFirstChild("CameraUtils")
    if node then
        local ok, mod = pcall(require, node)
        if ok and type(mod) == "table" and type(mod.setMouseBehaviorOverride) == "function" then
            Mouse.utils = mod
            return mod
        end
    end
    if getloadedmodules then
        local ok, modules = pcall(getloadedmodules)
        if ok and modules then
            for _, m in ipairs(modules) do
                if m.Name == "CameraUtils" then
                    local ok2, mod = pcall(require, m)
                    if ok2 and type(mod) == "table" and type(mod.setMouseBehaviorOverride) == "function" then
                        Mouse.utils = mod
                        return mod
                    end
                end
            end
        end
    end
    return nil
end

local function installMouseHook()
    if Mouse.hooked then return true end
    local utils = findCameraUtils()
    if not utils then
        Mouse.status = "camera module not found"
        return false
    end
    local real = utils.setMouseBehaviorOverride
    Mouse.realSet = real
    utils.setMouseBehaviorOverride = function(behavior)
        if Mouse.active and behavior == Enum.MouseBehavior.LockCenter then
            return real(Enum.MouseBehavior.Default)
        end
        return real(behavior)
    end
    Mouse.hooked = true
    Mouse.status = "camera hook active"
    return true
end

local function removeMouseHook()
    if not Mouse.hooked or not Mouse.utils or not Mouse.realSet then return end
    pcall(function() Mouse.utils.setMouseBehaviorOverride = Mouse.realSet end)
    Mouse.hooked = false
    Mouse.status = "removed"
end

local function ensureModalButton()
    if Mouse.modal and Mouse.modal.Parent then return Mouse.modal end
    local holder = Instance.new("ScreenGui")
    holder.Name = "VDModalHolder"
    holder.ResetOnSpawn = false
    holder.IgnoreGuiInset = true
    holder.DisplayOrder = -100
    holder.Parent = EspFolder
    local button = Instance.new("TextButton")
    button.Name = "VDModal"
    button.Text = ""
    button.AutoButtonColor = false
    button.BackgroundTransparency = 1
    button.Size = UDim2.fromOffset(1, 1)
    button.Position = UDim2.fromOffset(0, 0)
    button.Modal = true
    button.Visible = false
    button.Parent = holder
    Mouse.modal = button
    return button
end

local function inFirstPerson()
    return LP.CameraMaxZoomDistance <= 1.5
end

local function setMouseUnlock(on)
    if on == Mouse.active then return end
    Mouse.active = on
    local button = ensureModalButton()
    if button then button.Visible = on and inFirstPerson() end
    if on then
        Mouse.prevIcon = UserInputService.MouseIconEnabled
        UserInputService.MouseIconEnabled = true
        if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
    else
        if Mouse.prevIcon ~= nil then UserInputService.MouseIconEnabled = Mouse.prevIcon end
        Mouse.prevIcon = nil
        pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
    end
end

local WindowSize = IS_MOBILE and UDim2.fromOffset(430, 340) or UDim2.fromOffset(600, 470)

local Window = Fluent:CreateWindow({
    Title = "Violence District",
    SubTitle = "Survivor / Killer Suite",
    Search = true,
    Icon = "skull",
    TabWidth = IS_MOBILE and 110 or 150,
    Size = WindowSize,
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
    UserInfo = true,
    UserInfoTop = false,
    UserInfoTitle = LP.DisplayName,
    UserInfoSubtitle = IS_MOBILE and "Mobile" or "Desktop",
    UserInfoSubtitleColor = Color3.fromRGB(255, 90, 90)
})

local Minimizer = Fluent:CreateMinimizer({
    Icon = "skull",
    Size = UDim2.fromOffset(IS_MOBILE and 52 or 44, IS_MOBILE and 52 or 44),
    Position = UDim2.new(0, 20, 0, IS_MOBILE and 120 or 24),
    Acrylic = false,
    Corner = 12,
    Transparency = 1,
    Draggable = true,
    Visible = true
})

local GuiHome = { target = nil, moved = false }

local function shieldInterface()
    local gui = Fluent.GUI
    if not gui then return end
    if not GuiHome.target then
        local candidate = (gethui and gethui()) or nil
        if not candidate then
            local ok, core = pcall(function() return game:GetService("CoreGui") end)
            if ok then candidate = core end
        end
        GuiHome.target = candidate
    end
    if GuiHome.target and gui.Parent ~= GuiHome.target then
        local ok = pcall(function() gui.Parent = GuiHome.target end)
        GuiHome.moved = ok
    end
    if gui.Enabled == false then
        pcall(function() gui.Enabled = true end)
    end
    if gui.ResetOnSpawn then
        pcall(function() gui.ResetOnSpawn = false end)
    end
end

shieldInterface()

local Tabs = {
    Survivor = Window:AddTab({ Title = "Survivor", Icon = "wrench" }),
    Killer = Window:AddTab({ Title = "Killer", Icon = "axe" }),
    Esp = Window:AddTab({ Title = "ESP", Icon = "eye" }),
    Player = Window:AddTab({ Title = "Player", Icon = "user" }),
    Misc = Window:AddTab({ Title = "Misc", Icon = "list" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

function interfaceOpen()
    if Unloaded or Fluent.Unloaded then return false end
    if not Window then return false end
    if Window.Minimized == true then return false end
    local root = Window.Root
    if not root or not root.Parent then return false end
    return root.Visible == true
end

local function mouseUnlockStep()
    if not State.UnlockMouse then
        if Mouse.active then setMouseUnlock(false) end
        return
    end
    local open = interfaceOpen()
    if open ~= Mouse.active then setMouseUnlock(open) end
    if Mouse.modal and Mouse.modal.Parent then
        local want = Mouse.active and inFirstPerson()
        if Mouse.modal.Visible ~= want then Mouse.modal.Visible = want end
    end
    if open and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
end

local function section(tab, title, icon)
    local ok, result = pcall(function() return tab:AddSection(title, icon) end)
    if ok and result and type(result.AddToggle) == "function" then return result end
    return tab
end

local SurvivorGens = section(Tabs.Survivor, "Generators", "zap")

SurvivorGens:AddToggle("AutoRepair", {
    Title = "Auto Repair",
    Description = "Locks onto the best generator and repairs it, skill checks turn on with it",
    Default = false
}):OnChanged(function(v)
    State.AutoRepair = v
    if v then
        State.AutoSkillCheck = true
        if ForceSkillCheck then pcall(ForceSkillCheck, true) end
    else
        stopRepair()
    end
end)

SurvivorGens:AddToggle("RepairTeleport", { Title = "Teleport To Generator", Description = "Snap to the repair point instead of walking", Default = true }):OnChanged(function(v)
    State.RepairTeleport = v
end)

SurvivorGens:AddToggle("RepairPreferProgress", { Title = "Prefer Highest Progress", Default = true }):OnChanged(function(v)
    State.RepairPreferProgress = v
end)

SurvivorGens:AddToggle("RepairResume", { Title = "Auto Resume After Interrupt", Default = true }):OnChanged(function(v)
    State.RepairResume = v
end)

SurvivorGens:AddToggle("AutoSafe", {
    Title = "Auto Safe",
    Description = "Never take a generator the killer is guarding, and bail out if he walks up",
    Default = true
}):OnChanged(function(v) State.AutoSafe = v end)

SurvivorGens:AddSlider("SafeDistance", {
    Title = "Safe Distance",
    Description = "Generators closer than this to the killer are skipped",
    Default = 40, Min = 10, Max = 150, Rounding = 0,
    Callback = function(v) State.SafeDistance = v end
})

SurvivorGens:AddToggle("SafeFlee", {
    Title = "Run Away After Bailing",
    Description = "Walk away from the killer while no safe generator exists",
    Default = true
}):OnChanged(function(v) State.SafeFlee = v end)

SurvivorGens:AddSlider("RepairRadius", {
    Title = "Search Radius",
    Description = "Used when teleport is off",
    Default = 60, Min = 10, Max = 400, Rounding = 0,
    Callback = function(v) State.RepairRadius = v end
})

SurvivorGens:AddButton({
    Title = "Force Stop Repair",
    Description = "Releases the generator and unanchors you",
    Callback = function() stopRepair() notify("Repair", "Stopped.", 3) end
})

local SurvivorChecks = section(Tabs.Survivor, "Skill Checks", "target")

local SkillCheckToggle = SurvivorChecks:AddToggle("AutoSkillCheck", {
    Title = "Auto Skill Check",
    Description = "Hits generator and healing skill checks, forced on while Auto Repair runs",
    Default = false
})

SkillCheckToggle:OnChanged(function(v)
    if not v and State.AutoRepair then
        State.AutoSkillCheck = true
        task.defer(function() pcall(function() SkillCheckToggle:SetValue(true) end) end)
        return
    end
    State.AutoSkillCheck = v
end)

ForceSkillCheck = function(value)
    SkillCheckToggle:SetValue(value)
end

SurvivorChecks:AddDropdown("SkillCheckMode", {
    Title = "Skill Check Zone",
    Values = { "Great", "Good" },
    Multi = false,
    Default = 1
}):OnChanged(function(v) State.SkillCheckMode = v end)

SurvivorChecks:AddDropdown("SkillCheckMethod", {
    Title = "Skill Check Method",
    Description = "Input presses the real key and is the tested one, Instant answers the remote itself",
    Values = { "Input", "Instant" },
    Multi = false,
    Default = 1
}):OnChanged(function(v) State.SkillCheckMethod = v end)

SurvivorChecks:AddSlider("SkillCheckOffset", {
    Title = "Timing Offset",
    Description = "Higher = later hit, use if you overshoot",
    Default = 2, Min = 0, Max = 12, Rounding = 0,
    Callback = function(v) State.SkillCheckOffset = v end
})

local SkillCheckParagraph = SurvivorChecks:AddParagraph({
    Title = "Skill Check Debug",
    Content = "No skill check seen yet."
})

local SurvivorHeal = section(Tabs.Survivor, "Healing", "heart-pulse")

SurvivorHeal:AddToggle("AutoHealSelf", { Title = "Auto Self Heal", Description = "Heals when you drop under 50 HP", Default = false }):OnChanged(function(v)
    State.AutoHealSelf = v
    if not v and Heal.target == getRoot() then stopHeal() end
end)

SurvivorHeal:AddToggle("AutoHealTeam", { Title = "Auto Heal Teammates", Default = false }):OnChanged(function(v)
    State.AutoHealTeam = v
    if not v and Heal.target and Heal.target ~= getRoot() then stopHeal() end
end)

SurvivorHeal:AddToggle("HealTeleport", { Title = "Teleport To Heal Target", Default = true }):OnChanged(function(v)
    State.HealTeleport = v
end)

SurvivorHeal:AddSlider("HealRadius", {
    Title = "Heal Radius",
    Default = 40, Min = 5, Max = 200, Rounding = 0,
    Callback = function(v) State.HealRadius = v end
})

SurvivorHeal:AddButton({ Title = "Force Stop Heal", Callback = function() stopHeal() end })

local SurvivorRescue = section(Tabs.Survivor, "Hooks & Rescue", "life-buoy")

SurvivorRescue:AddToggle("AutoUnhook", { Title = "Auto Rescue Teammates", Description = "Frees hooked survivors automatically", Default = false }):OnChanged(function(v)
    State.AutoUnhook = v
end)

SurvivorRescue:AddToggle("UnhookTeleport", { Title = "Teleport To Hook", Default = true }):OnChanged(function(v)
    State.UnhookTeleport = v
end)

SurvivorRescue:AddSlider("UnhookRadius", {
    Title = "Rescue Radius",
    Default = 150, Min = 10, Max = 600, Rounding = 0,
    Callback = function(v) State.UnhookRadius = v end
})

SurvivorRescue:AddToggle("AutoSelfUnhook", { Title = "Auto Self Unhook", Description = "Spams the self rescue attempt while hooked", Default = false }):OnChanged(function(v)
    State.AutoSelfUnhook = v
end)

SurvivorRescue:AddSlider("SelfUnhookInterval", {
    Title = "Self Unhook Interval",
    Default = 1.5, Min = 0.3, Max = 5, Rounding = 1,
    Callback = function(v) State.SelfUnhookInterval = v end
})

local SurvivorExit = section(Tabs.Survivor, "Escape", "door-open")

SurvivorExit:AddToggle("AutoLever", { Title = "Auto Open Exit Gate", Description = "Pulls the lever once gates are powered", Default = false }):OnChanged(function(v)
    State.AutoLever = v
    if not v then stopLever() end
end)

SurvivorExit:AddToggle("LeverTeleport", { Title = "Teleport To Lever", Default = true }):OnChanged(function(v)
    State.LeverTeleport = v
end)

SurvivorExit:AddToggle("AutoEscape", { Title = "Auto Escape", Description = "Rushes the exit zone when it exists", Default = false }):OnChanged(function(v)
    State.AutoEscape = v
end)

SurvivorExit:AddButton({
    Title = "Teleport To Exit Gate",
    Callback = function()
        local point = select(1, nearestTagged("Exit", math.huge)) or select(1, nearestTagged("ExitPoint", math.huge))
        if point then
            safeTeleport(faceCFrame(point.Position + Vector3.new(0, 3, 2), point.Position))
        else
            notify("Exit", "No exit lever found yet.", 3)
        end
    end
})

SurvivorExit:AddButton({
    Title = "Teleport To Escape Zone",
    Callback = function()
        local part = select(1, nearestTagged("EscapePart", math.huge))
        if part then
            safeTeleport(CFrame.new(part.Position + Vector3.new(0, 3, 0)))
        else
            notify("Escape", "Escape zone is not active.", 3)
        end
    end
})

local SurvivorLoop = section(Tabs.Survivor, "Loops & Chase", "repeat")

SurvivorLoop:AddToggle("AutoVault", { Title = "Auto Vault Window", Description = "Vaults when the killer closes in", Default = false }):OnChanged(function(v)
    State.AutoVault = v
end)

SurvivorLoop:AddToggle("AutoPalletDrop", { Title = "Auto Drop Pallet", Default = false }):OnChanged(function(v)
    State.AutoPalletDrop = v
end)

SurvivorLoop:AddToggle("AutoPalletSlide", { Title = "Auto Pallet Slide", Default = false }):OnChanged(function(v)
    State.AutoPalletSlide = v
end)

SurvivorLoop:AddSlider("DangerDistance", {
    Title = "Killer Danger Distance",
    Description = "Loop actions only trigger inside this range",
    Default = 22, Min = 5, Max = 80, Rounding = 0,
    Callback = function(v) State.DangerDistance = v end
})

SurvivorLoop:AddSlider("LoopRadius", {
    Title = "Object Search Radius",
    Default = 26, Min = 5, Max = 120, Rounding = 0,
    Callback = function(v) State.LoopRadius = v end
})

SurvivorLoop:AddToggle("AlwaysSprint", { Title = "Always Sprinting", Description = "Keeps the sprint flag on", Default = false }):OnChanged(function(v)
    State.AlwaysSprint = v
end)

local SurvivorItems = section(Tabs.Survivor, "Items", "package")

SurvivorItems:AddToggle("AutoBandage", { Title = "Auto Bandage When Injured", Default = false }):OnChanged(function(v)
    State.AutoBandage = v
end)

SurvivorItems:AddToggle("AutoAdrenaline", { Title = "Auto Adrenaline When Downed", Default = false }):OnChanged(function(v)
    State.AutoAdrenaline = v
end)

SurvivorItems:AddToggle("AutoParry", { Title = "Auto Parry", Description = "Parrying Dagger reacts to the killer swing", Default = false }):OnChanged(function(v)
    State.AutoParry = v
    if v then bindParryWatcher() end
end)

SurvivorItems:AddSlider("ParryRange", {
    Title = "Parry Trigger Range",
    Default = 14, Min = 5, Max = 40, Rounding = 0,
    Callback = function(v) State.ParryRange = v end
})

SurvivorItems:AddSlider("ParryCooldown", {
    Title = "Parry Cooldown",
    Default = 1.2, Min = 0.3, Max = 5, Rounding = 1,
    Callback = function(v) State.ParryCooldown = v end
})

SurvivorItems:AddToggle("AutoGun", { Title = "Auto Twist Of Fate", Description = "Fires the revolver at the killer", Default = false }):OnChanged(function(v)
    State.AutoGun = v
end)

SurvivorItems:AddSlider("GunRange", {
    Title = "Gun Range",
    Default = 90, Min = 20, Max = 300, Rounding = 0,
    Callback = function(v) State.GunRange = v end
})

SurvivorItems:AddToggle("AutoShield", { Title = "Auto Riot Shield Rush", Default = false }):OnChanged(function(v) State.AutoShield = v end)
SurvivorItems:AddToggle("AutoHolyWater", { Title = "Auto Holy Water", Default = false }):OnChanged(function(v) State.AutoHolyWater = v end)

SurvivorItems:AddToggle("AutoBandageItem", { Title = "Keep Motion Tracker Active", Default = false }):OnChanged(function(v)
    State.AutoTracker = v
end)

SurvivorItems:AddButton({ Title = "Use Flashlight", Callback = function() fire("Items/Flashlight/Activate", heldItem(), true) end })
SurvivorItems:AddButton({ Title = "Use Bandage", Callback = function() fire("Items/Bandage/Fire", true, heldItem()) end })
SurvivorItems:AddButton({ Title = "Use Wax Candle", Callback = function() fire("Items/WaxBound Candle/Fire") end })
SurvivorItems:AddButton({ Title = "Spawn Shadow Clone", Callback = function() fire("Items/Shadow Clone/clonespawn") end })
SurvivorItems:AddButton({ Title = "Reset Heal State", Callback = function() fire("Healing/Reset", getRoot()) end })

local SurvivorAuto = section(Tabs.Survivor, "AFK Mode", "bot")

SurvivorAuto:AddToggle("AfkFarm", {
    Title = "AFK Farm Mode",
    Description = "Repair + skill checks + heal + rescue + escape in one switch",
    Default = false
}):OnChanged(function(v)
    State.AfkFarm = v
    local members = { "AutoRepair", "AutoSkillCheck", "AutoHealSelf", "AutoUnhook", "AutoSelfUnhook", "AutoLever", "AutoEscape", "AntiAfk" }
    for _, key in ipairs(members) do
        State[key] = v
        pcall(function()
            local option = Fluent.Options[key]
            if option and option.SetValue then option:SetValue(v) end
        end)
    end
    if v then
        notify("AFK Farm", "Full survivor automation enabled.", 5)
    else
        pcall(stopRepair)
        pcall(stopHeal)
        pcall(stopLever)
    end
end)

SurvivorAuto:AddToggle("HideSkillCheck", { Title = "Hide Skill Check Visuals", Description = "Keeps auto hit working, removes the ring", Default = false }):OnChanged(function(v)
    State.HideSkillCheck = v
end)

SurvivorAuto:AddButton({
    Title = "Teleport To Killer",
    Callback = function()
        local kc = killerCharacter()
        local hrp = kc and kc:FindFirstChild("HumanoidRootPart")
        if hrp then safeTeleport(hrp.CFrame * CFrame.new(0, 0, 6)) else notify("Teleport", "Killer not found.", 3) end
    end
})

local KillerCombat = section(Tabs.Killer, "Combat", "sword")

KillerCombat:AddToggle("KillerAutoAttack", { Title = "Auto Attack", Description = "Swings when a survivor enters range", Default = false }):OnChanged(function(v)
    State.KillerAutoAttack = v
end)

KillerCombat:AddSlider("KillerAttackRange", {
    Title = "Attack Range",
    Default = 12, Min = 4, Max = 40, Rounding = 0,
    Callback = function(v) State.KillerAttackRange = v end
})

KillerCombat:AddSlider("KillerHoldTime", {
    Title = "Lunge Hold Time",
    Description = "Longer hold means a bigger lunge",
    Default = 0.2, Min = 0.02, Max = 0.6, Rounding = 2,
    Callback = function(v) State.KillerHoldTime = v end
})

KillerCombat:AddToggle("KillerFaceOnly", { Title = "Only Swing When Facing", Default = true }):OnChanged(function(v)
    State.KillerFaceOnly = v
end)

KillerCombat:AddToggle("KillerAutoFace", { Title = "Auto Face Target", Description = "Rotates you toward the closest survivor", Default = false }):OnChanged(function(v)
    State.KillerAutoFace = v
end)

KillerCombat:AddSlider("KillerFaceSmooth", {
    Title = "Face Smoothness",
    Default = 0.35, Min = 0.05, Max = 1, Rounding = 2,
    Callback = function(v) State.KillerFaceSmooth = v end
})

local KillerActions = section(Tabs.Killer, "Actions", "hand")

KillerActions:AddToggle("KillerAutoCarry", { Title = "Auto Pick Up Downed", Default = false }):OnChanged(function(v)
    State.KillerAutoCarry = v
end)

KillerActions:AddToggle("KillerAutoHook", { Title = "Auto Hook Carried", Description = "Teleports to the nearest hook and hangs them", Default = false }):OnChanged(function(v)
    State.KillerAutoHook = v
end)

KillerActions:AddToggle("KillerAutoBreakPallet", { Title = "Auto Break Pallets", Default = false }):OnChanged(function(v)
    State.KillerAutoBreakPallet = v
end)

KillerActions:AddToggle("KillerAutoBreakGen", { Title = "Auto Kick Generators", Default = false }):OnChanged(function(v)
    State.KillerAutoBreakGen = v
end)

KillerActions:AddToggle("KillerAutoVault", { Title = "Auto Vault Windows", Default = false }):OnChanged(function(v)
    State.KillerAutoVault = v
end)

KillerActions:AddSlider("KillerActionRadius", {
    Title = "Action Radius",
    Default = 45, Min = 5, Max = 300, Rounding = 0,
    Callback = function(v) State.KillerActionRadius = v end
})

KillerActions:AddButton({ Title = "Drop Carried Survivor", Callback = function() fire("Carry/DropSurvivorEvent") end })
KillerActions:AddButton({ Title = "Start Mori", Callback = function() fire("Killers/Startmori") end })

local KillerPower = section(Tabs.Killer, "Power", "flame")

KillerPower:AddToggle("KillerKillAura", { Title = "Kill Aura", Description = "Swings at anything in range, ignores facing", Default = false }):OnChanged(function(v)
    State.KillerKillAura = v
    State.KillerAutoAttack = v
    State.KillerFaceOnly = not v
    pcall(function()
        Fluent.Options.KillerAutoAttack:SetValue(v)
        Fluent.Options.KillerFaceOnly:SetValue(not v)
    end)
end)

KillerPower:AddToggle("KillerAutoPower", { Title = "Auto Primary Power (Q)", Default = false }):OnChanged(function(v)
    State.KillerAutoPower = v
end)

KillerPower:AddToggle("KillerAutoSecondary", { Title = "Auto Secondary Power (RMB)", Default = false }):OnChanged(function(v)
    State.KillerAutoSecondary = v
end)

KillerPower:AddSlider("KillerPowerInterval", {
    Title = "Power Interval",
    Default = 6, Min = 1, Max = 30, Rounding = 0,
    Callback = function(v) State.KillerPowerInterval = v end
})

KillerPower:AddToggle("KillerFastStun", { Title = "Fast Stun Recovery", Description = "Client side stun clear after a pallet hit", Default = false }):OnChanged(function(v)
    State.KillerFastStun = v
end)

KillerPower:AddButton({ Title = "Reset Bloodlust", Callback = function() fire("Mechanics/resetbloodlustremote") end })

local KillerMove = section(Tabs.Killer, "Pursuit", "footprints")

KillerMove:AddToggle("KillerChase", { Title = "Sticky Chase", Description = "Glues you behind the closest survivor", Default = false }):OnChanged(function(v)
    State.KillerChase = v
end)

KillerMove:AddSlider("KillerChaseDistance", {
    Title = "Chase Offset",
    Default = 6, Min = 2, Max = 30, Rounding = 0,
    Callback = function(v) State.KillerChaseDistance = v end
})

KillerMove:AddSlider("KillerChaseHeight", {
    Title = "Chase Height",
    Default = 0, Min = -5, Max = 20, Rounding = 0,
    Callback = function(v) State.KillerChaseHeight = v end
})

KillerMove:AddButton({
    Title = "Teleport To Nearest Survivor",
    Callback = function()
        local target = nearestSurvivorModel(math.huge)
        local hrp = target and target:FindFirstChild("HumanoidRootPart")
        if hrp then
            safeTeleport(faceCFrame(hrp.Position + hrp.CFrame.LookVector * -4, hrp.Position))
        else
            notify("Teleport", "No survivor found.", 3)
        end
    end
})

KillerMove:AddButton({
    Title = "Teleport To Nearest Generator",
    Callback = function()
        local point = select(1, nearestTagged("GeneratorPoint", math.huge))
        if point then safeTeleport(point.CFrame * CFrame.new(0, 0, 3)) end
    end
})

KillerMove:AddButton({
    Title = "Teleport To Nearest Hook",
    Callback = function()
        local point = select(1, nearestTagged("HookPoint", math.huge))
        if point then safeTeleport(point.CFrame * CFrame.new(0, 0.6, 0)) end
    end
})

local KillerInfo = section(Tabs.Killer, "Status", "activity")
local KillerParagraph = KillerInfo:AddParagraph({ Title = "Match Status", Content = "Waiting for round data." })

local EspGeneral = section(Tabs.Esp, "General", "eye")

EspGeneral:AddToggle("EspMaster", { Title = "Enable ESP", Default = false }):OnChanged(function(v)
    State.EspMaster = v
    if not v then clearEsp() end
end)

EspGeneral:AddToggle("EspHighlight", { Title = "Use Highlights", Description = "Turn off on weak phones", Default = not IS_MOBILE }):OnChanged(function(v)
    State.EspHighlight = v
    clearEsp()
end)

EspGeneral:AddToggle("EspTracer", { Title = "Tracers", Default = false }):OnChanged(function(v)
    State.EspTracer = v
    if not v then
        for _, entry in pairs(EspEntries) do
            if entry.tracer then entry.tracer.Visible = false end
        end
    end
end)

EspGeneral:AddToggle("EspDistance", { Title = "Show Distance", Default = true }):OnChanged(function(v) State.EspDistance = v end)
EspGeneral:AddToggle("EspHealth", { Title = "Show Health", Default = true }):OnChanged(function(v) State.EspHealth = v end)
EspGeneral:AddToggle("EspStatus", { Title = "Show State Tags", Default = true }):OnChanged(function(v) State.EspStatus = v end)

EspGeneral:AddSlider("EspMaxDistance", {
    Title = "Max Distance",
    Default = 1200, Min = 100, Max = 5000, Rounding = 0,
    Callback = function(v) State.EspMaxDistance = v end
})

EspGeneral:AddSlider("EspRate", {
    Title = "Refresh Rate",
    Description = "Lower is lighter on mobile",
    Default = IS_MOBILE and 6 or 15, Min = 2, Max = 30, Rounding = 0,
    Callback = function(v) State.EspRate = v end
})

EspGeneral:AddSlider("EspTextSize", {
    Title = "Text Size",
    Default = IS_MOBILE and 13 or 14, Min = 9, Max = 26, Rounding = 0,
    Callback = function(v) State.EspTextSize = v end
})

local EspTargets = section(Tabs.Esp, "Targets", "crosshair")

EspTargets:AddToggle("EspSurvivor", { Title = "Survivors", Default = true }):OnChanged(function(v) State.EspSurvivor = v end)
EspTargets:AddToggle("EspKiller", { Title = "Killer", Default = true }):OnChanged(function(v) State.EspKiller = v end)
EspTargets:AddToggle("EspGenerator", { Title = "Generators + Progress", Default = true }):OnChanged(function(v) State.EspGenerator = v end)
EspTargets:AddToggle("EspHook", { Title = "Hooks", Default = false }):OnChanged(function(v) State.EspHook = v end)
EspTargets:AddToggle("EspPallet", { Title = "Pallets", Default = false }):OnChanged(function(v) State.EspPallet = v end)
EspTargets:AddToggle("EspWindow", { Title = "Windows", Default = false }):OnChanged(function(v) State.EspWindow = v end)
EspTargets:AddToggle("EspExit", { Title = "Exit Levers", Default = true }):OnChanged(function(v) State.EspExit = v end)
EspTargets:AddToggle("EspEscape", { Title = "Escape Zone", Default = true }):OnChanged(function(v) State.EspEscape = v end)
EspTargets:AddToggle("EspItem", { Title = "Items", Default = false }):OnChanged(function(v) State.EspItem = v end)

EspTargets:AddToggle("RevealInvisible", { Title = "Reveal Invisible Killer", Description = "Forces cloaked killer bodies visible", Default = false }):OnChanged(function(v)
    State.RevealInvisible = v
end)

EspTargets:AddInput("EspCustomTag", {
    Title = "Custom Tag ESP",
    Description = "Type a CollectionService tag, e.g. gatespot or Item",
    Default = "",
    Placeholder = "tag name",
    Numeric = false,
    Finished = true,
    Callback = function(v) State.EspCustomTag = v or "" end
})

local EspColors = section(Tabs.Esp, "Colors", "palette")

EspColors:AddColorpicker("ColorSurvivor", { Title = "Survivor", Default = State.ColorSurvivor }):OnChanged(function(v) State.ColorSurvivor = v end)
EspColors:AddColorpicker("ColorKiller", { Title = "Killer", Default = State.ColorKiller }):OnChanged(function(v) State.ColorKiller = v end)
EspColors:AddColorpicker("ColorGenerator", { Title = "Generator", Default = State.ColorGenerator }):OnChanged(function(v) State.ColorGenerator = v end)
EspColors:AddColorpicker("ColorHook", { Title = "Hook", Default = State.ColorHook }):OnChanged(function(v) State.ColorHook = v end)
EspColors:AddColorpicker("ColorPallet", { Title = "Pallet", Default = State.ColorPallet }):OnChanged(function(v) State.ColorPallet = v end)
EspColors:AddColorpicker("ColorWindow", { Title = "Window", Default = State.ColorWindow }):OnChanged(function(v) State.ColorWindow = v end)
EspColors:AddColorpicker("ColorExit", { Title = "Exit", Default = State.ColorExit }):OnChanged(function(v) State.ColorExit = v end)
EspColors:AddColorpicker("ColorEscape", { Title = "Escape", Default = State.ColorEscape }):OnChanged(function(v) State.ColorEscape = v end)
EspColors:AddColorpicker("ColorItem", { Title = "Item", Default = State.ColorItem }):OnChanged(function(v) State.ColorItem = v end)

local EspAlerts = section(Tabs.Esp, "Alerts", "bell")

EspAlerts:AddToggle("KillerWarning", { Title = "Killer Proximity Warning", Default = false }):OnChanged(function(v) State.KillerWarning = v end)

EspAlerts:AddSlider("WarningDistance", {
    Title = "Warning Distance",
    Default = 30, Min = 10, Max = 120, Rounding = 0,
    Callback = function(v) State.WarningDistance = v end
})

local PlayerMove = section(Tabs.Player, "Movement", "move")

PlayerMove:AddSlider("WalkSpeed", {
    Title = "Walk Speed",
    Description = "0 keeps the game value",
    Default = 0, Min = 0, Max = 60, Rounding = 0,
    Callback = function(v) State.WalkSpeed = v end
})

PlayerMove:AddSlider("JumpPower", {
    Title = "Jump Power",
    Description = "0 keeps the game value",
    Default = 0, Min = 0, Max = 200, Rounding = 0,
    Callback = function(v) State.JumpPower = v end
})

PlayerMove:AddToggle("InfiniteJump", { Title = "Infinite Jump", Default = false }):OnChanged(function(v) State.InfiniteJump = v end)

PlayerMove:AddToggle("NoClip", { Title = "NoClip", Default = false }):OnChanged(function(v)
    State.NoClip = v
    if not v then restoreCollision() end
end)

PlayerMove:AddToggle("Fly", { Title = "Fly", Description = "WASD + Space/Shift, on mobile use the joystick", Default = false }):OnChanged(function(v)
    State.Fly = v
    if v then startFly() else stopFly() end
end)

PlayerMove:AddSlider("FlySpeed", {
    Title = "Fly Speed",
    Default = 60, Min = 10, Max = 250, Rounding = 0,
    Callback = function(v) State.FlySpeed = v end
})

PlayerMove:AddButton({
    Title = "Unanchor Character",
    Description = "Use if you get stuck after an action",
    Callback = function()
        local root = getRoot()
        if root then root.Anchored = false end
        local hum = getHumanoid()
        if hum then hum.AutoRotate = true end
        local ci = getInteract()
        if ci then
            for _, key in ipairs({ "isRepairing", "isHealing", "isVaulting", "isSliding", "isUnhooking", "isExiting", "isDroppingPallet" }) do
                ci:SetAttribute(key, false)
            end
        end
        notify("Player", "Character released.", 3)
    end
})

local PlayerVisual = section(Tabs.Player, "Visuals", "sun")

PlayerVisual:AddToggle("FullBright", { Title = "Full Bright", Default = false }):OnChanged(function(v)
    State.FullBright = v
    applyLighting()
end)

PlayerVisual:AddSlider("BrightnessValue", {
    Title = "Brightness",
    Default = 2, Min = 1, Max = 6, Rounding = 1,
    Callback = function(v) State.BrightnessValue = v applyLighting() end
})

PlayerVisual:AddToggle("NoFog", { Title = "Remove Fog", Default = false }):OnChanged(function(v)
    State.NoFog = v
    applyLighting()
end)

PlayerVisual:AddToggle("NoBlind", { Title = "Remove Blind & Blood Overlays", Default = false }):OnChanged(function(v)
    State.NoBlind = v
    applyBlindness()
end)

PlayerVisual:AddToggle("NoShake", { Title = "Disable Camera Shake", Default = false }):OnChanged(function(v) State.NoShake = v end)

PlayerVisual:AddToggle("NoShadows", { Title = "No Shadows", Default = false }):OnChanged(function(v)
    State.NoShadows = v
    applyLighting()
end)

PlayerVisual:AddToggle("NoAtmosphere", { Title = "Remove Atmosphere", Default = false }):OnChanged(function(v)
    State.NoAtmosphere = v
    if not v then return end
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("Atmosphere") then pcall(function() obj:Destroy() end) end
    end
    pcall(function()
        local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
        if clouds then clouds.Enabled = false end
    end)
end)

PlayerVisual:AddToggle("AntiFlashlight", { Title = "Anti Blind / Anti Flashlight", Default = false }):OnChanged(function(v)
    State.AntiFlashlight = v
end)

PlayerVisual:AddToggle("UnlimitedZoom", { Title = "Unlimited Zoom", Default = false }):OnChanged(function(v)
    State.UnlimitedZoom = v
    if v then
        LP.CameraMaxZoomDistance = 2000
    else
        LP.CameraMaxZoomDistance = CameraDefaults.maxZoom
    end
end)

PlayerVisual:AddToggle("FreeCam", { Title = "Free Cam", Description = "WASD + Q/E to move the camera", Default = false }):OnChanged(function(v)
    State.FreeCam = v
    if v then startFreeCam() else stopFreeCam() end
end)

PlayerVisual:AddSlider("FreeCamSpeed", {
    Title = "Free Cam Speed",
    Default = 2, Min = 0.5, Max = 15, Rounding = 1,
    Callback = function(v) State.FreeCamSpeed = v end
})

PlayerVisual:AddSlider("FieldOfView", {
    Title = "Field Of View",
    Description = "0 keeps the game value",
    Default = 0, Min = 0, Max = 120, Rounding = 0,
    Callback = function(v)
        State.FieldOfView = v
        if v == 0 then Camera.FieldOfView = CameraDefaults.fov end
    end
})

local PlayerPerf = section(Tabs.Player, "Performance", "gauge")

PlayerPerf:AddButton({ Title = "FPS Boost", Description = "Strip textures, particles and shadows", Callback = fpsBoost })

PlayerPerf:AddSlider("FpsCap", {
    Title = "FPS Cap",
    Description = "0 leaves it untouched",
    Default = 0, Min = 0, Max = 240, Rounding = 0,
    Callback = function(v)
        State.FpsCap = v
        if setfpscap and v > 0 then pcall(function() setfpscap(v) end) end
    end
})

PlayerPerf:AddToggle("AntiAfk", { Title = "Anti AFK", Default = false }):OnChanged(function(v) State.AntiAfk = v end)

local MiscRound = section(Tabs.Misc, "Round Info", "info")
local RoundParagraph = MiscRound:AddParagraph({ Title = "Live Stats", Content = "Loading..." })

local MiscInput = section(Tabs.Misc, "Input", "mouse-pointer")

MiscInput:AddToggle("UnlockMouse", {
    Title = "Unlock Mouse With Interface",
    Description = "Cursor frees itself only while this window is open, relocks when hidden",
    Default = true
}):OnChanged(function(v)
    State.UnlockMouse = v
    if not v and Mouse.active then setMouseUnlock(false) end
end)

local MouseParagraph = MiscInput:AddParagraph({ Title = "Mouse Status", Content = "Loading..." })

local MiscPersist = section(Tabs.Misc, "Persistence", "refresh-cw")

MiscPersist:AddToggle("KeepAfterTeleport", {
    Title = "Reload After Teleport",
    Description = "Round end teleports you to a new server and wipes the script, this queues it to load again",
    Default = true
}):OnChanged(function(v)
    State.KeepAfterTeleport = v
    armTeleportPersist()
end)

local PersistParagraph = MiscPersist:AddParagraph({ Title = "Reload Status", Content = "Loading..." })

MiscPersist:AddButton({
    Title = "Re-arm Reload",
    Callback = function()
        armTeleportPersist()
        notify("Persistence", Persist.status, 5)
    end
})

MiscPersist:AddParagraph({
    Title = "If Reload Says No Source",
    Content = "Save this script as vd.lua in your executor workspace folder, or run getgenv().VDHubLoader = [[your loadstring line]] before executing it."
})

local MiscTools = section(Tabs.Misc, "Tools", "wrench")

local playerDropdown = MiscTools:AddDropdown("TargetPlayer", {
    Title = "Target Player",
    Values = {},
    Multi = false,
    Search = true,
    Default = nil
})

local function refreshPlayerList()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then table.insert(names, p.Name) end
    end
    pcall(function() playerDropdown:SetValues(names) end)
end

MiscTools:AddButton({ Title = "Refresh Player List", Callback = refreshPlayerList })

MiscTools:AddButton({
    Title = "Teleport To Target",
    Callback = function()
        local name = playerDropdown.Value
        local target = name and Players:FindFirstChild(name)
        local hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            safeTeleport(hrp.CFrame * CFrame.new(0, 0, 4))
        else
            notify("Teleport", "Target not available.", 3)
        end
    end
})

MiscTools:AddButton({
    Title = "Copy Job ID",
    Callback = function()
        if setclipboard then
            pcall(function() setclipboard(game.JobId) end)
            notify("Misc", "Job ID copied.", 3)
        end
    end
})

MiscTools:AddButton({
    Title = "Rejoin Server",
    Callback = function()
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end)
    end
})

MiscTools:AddButton({
    Title = "Server Hop",
    Callback = function()
        pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
    end
})

local function unloadHub()
    if Unloaded then return end
    Unloaded = true
    pcall(stopRepair)
    pcall(stopHeal)
    pcall(stopLever)
    pcall(stopFly)
    pcall(stopFreeCam)
    pcall(restoreCollision)
    pcall(function() setMouseUnlock(false) end)
    pcall(removeMouseHook)
    pcall(clearEsp)
    State.WalkSpeed = 0
    State.JumpPower = 0
    State.NoClip = false
    pcall(applyMovement)
    pcall(function()
        Camera.FieldOfView = CameraDefaults.fov
        LP.CameraMaxZoomDistance = CameraDefaults.maxZoom
        LP.CameraMinZoomDistance = CameraDefaults.minZoom
    end)
    pcall(function()
        local gui = LP:FindFirstChild("PlayerGui")
        if gui then
            for _, name in ipairs({ "Darkness", "Killerblood", "effects" }) do
                local screen = gui:FindFirstChild(name)
                if screen and screen:IsA("ScreenGui") then screen.Enabled = true end
            end
        end
    end)
    State.FullBright = false
    State.NoFog = false
    State.NoShadows = false
    pcall(applyLighting)
    pcall(function() EspFolder:Destroy() end)
    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
    for _, thread in ipairs(Threads) do pcall(task.cancel, thread) end
    pcall(function() Fluent:Destroy() end)
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("DepthOfFieldEffect") and obj.FarIntensity == 0 and obj.NearIntensity == 1 then
            pcall(function() obj:Destroy() end)
        end
    end
    if getgenv and getgenv().VDHub and getgenv().VDHub.Unload == unloadHub then getgenv().VDHub = nil end
end

MiscTools:AddButton({
    Title = "Unload Script",
    Description = "Removes ESP, stops every loop and closes the UI",
    Callback = function()
        Window:Dialog({
            Title = "Unload",
            Content = "Disable everything and close the menu?",
            Buttons = {
                { Title = "Unload", Callback = unloadHub },
                { Title = "Cancel", Callback = function() end }
            }
        })
    end
})

local MiscKeys = section(Tabs.Misc, "Keybinds", "keyboard")

MiscKeys:AddParagraph({
    Title = "Menu Toggle",
    Content = "LeftControl hides and shows this window. Change it under Settings, Interface, Minimize Bind."
})

MiscKeys:AddKeybind("PanicKey", {
    Title = "Panic (Disable Automation)",
    Mode = "Toggle",
    Default = "P",
    Callback = function()
        local keys = {
            "AutoRepair", "AutoSkillCheck", "AutoHealSelf", "AutoHealTeam", "AutoUnhook",
            "AutoSelfUnhook", "AutoLever", "AutoEscape", "AutoVault", "AutoPalletDrop",
            "AutoPalletSlide", "AutoParry", "AutoGun", "AutoShield", "AutoHolyWater",
            "AutoBandage", "AutoAdrenaline", "AutoTracker", "AfkFarm", "AlwaysSprint",
            "KillerAutoAttack", "KillerAutoCarry", "KillerAutoHook", "KillerAutoBreakGen",
            "KillerAutoBreakPallet", "KillerAutoVault", "KillerChase", "KillerAutoFace",
            "KillerKillAura", "KillerAutoPower", "KillerAutoSecondary", "KillerFastStun",
            "Fly", "FreeCam", "NoClip", "InfiniteJump",
        }
        for _, key in ipairs(keys) do
            State[key] = false
            pcall(function()
                local option = Fluent.Options[key]
                if option and option.SetValue then option:SetValue(false) end
            end)
        end
        pcall(stopFly)
        pcall(stopFreeCam)
        pcall(restoreCollision)
        pcall(stopRepair)
        pcall(stopHeal)
        pcall(stopLever)
        notify("Panic", "All automation disabled.", 4)
    end
})

track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if Workspace.CurrentCamera then Camera = Workspace.CurrentCamera end
end))

track(RunService.RenderStepped:Connect(function(delta)
    if Unloaded or Fluent.Unloaded then return end
    pcall(mouseUnlockStep)
    pcall(skillCheckStep, delta)
    pcall(hideSkillCheckStep)
    pcall(applyMovement)
    pcall(killerAutoFaceStep)
    pcall(killerChaseStep)
    pcall(updateTracers)
    pcall(applyFov)
    if State.NoClip then pcall(applyNoClip) end
    if State.RevealInvisible then pcall(revealInvisibleStep) end
end))

track(UserInputService.JumpRequest:Connect(function()
    if State.InfiniteJump then
        local hum = getHumanoid()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

track(LP.Idled:Connect(function()
    if State.AntiAfk and VIM then
        pcall(function()
            VIM:SendMouseMoveEvent(math.random(50, 200), math.random(50, 200), game)
        end)
    end
end))

track(LP.CharacterAdded:Connect(function()
    task.wait(1.5)
    Repair.point = nil
    Heal.target = nil
    Lever.point = nil
    CollisionMemory = {}
    MovementDefaults.walk = nil
    MovementDefaults.jump = nil
    ItemNames = nil
    for key in pairs(RemoteCache) do RemoteCache[key] = nil end
    buildSkillCandidates()
    applyMovement()
    applyBlindness()
    if State.Fly then startFly() end
    if State.FreeCam then startFreeCam() end
    if State.AutoParry then bindParryWatcher() end
end))

track(LP:GetAttributeChangedSignal("platform"):Connect(function()
    IS_MOBILE = detectMobile()
end))

track(Players.PlayerAdded:Connect(refreshPlayerList))
track(Players.PlayerRemoving:Connect(function() task.delay(0.5, refreshPlayerList) end))

loop(function() return 1 / math.clamp(State.EspRate, 2, 30) end, refreshEsp)

loop(0.35, autoRepairTick)
loop(0.4, autoHealTick)
loop(0.4, autoLeverTick)
loop(0.5, autoUnhookTick)
loop(0.6, autoEscapeTick)
loop(0.2, autoLoopTick)

loop(0.5, shieldInterface)

loop(1, function()
    autoItemTick()
    if State.AlwaysSprint then
        local c = getCharacter()
        if c and isSurvivor() and not c:GetAttribute("Crouching") then
            c:SetAttribute("Sprinting", true)
        end
    end
    if State.NoShake then
        local c = getCharacter()
        local shaker = c and c:FindFirstChild("CamShake")
        if shaker and shaker:IsA("BaseScript") then pcall(function() shaker.Disabled = true end) end
    end
    if State.NoBlind then applyBlindness() end
    if State.FullBright or State.NoFog then applyLighting() end
end)

loop(function() return State.SelfUnhookInterval end, autoSelfUnhookTick)

loop(0.15, killerAutoAttackTick)
loop(0.3, killerAutoCarryTick)
loop(0.3, killerAutoHookTick)
loop(0.35, killerBreakPalletTick)
loop(0.35, killerBreakGenTick)
loop(0.4, killerVaultTick)

loop(0.25, function()
    killerFastStunTick()
    autoGunTick()
end)

loop(1.5, function()
    autoShieldTick()
    autoHolyWaterTick()
    antiFlashlightStep()
    if State.AutoTracker then fire("Items/Tracker/active", true) end
end)

loop(1, function()
    if State.KillerAutoPower or State.KillerAutoSecondary then
        killerPowerTick()
        task.wait(math.max(0, State.KillerPowerInterval - 1))
    end
end)

loop(4, function()
    local kc = killerCharacter()
    if State.AutoParry and kc ~= Parry.killer then bindParryWatcher() end
end)

loop(1.5, function()
    local gens = tagged("Generator")
    local done, total = 0, #gens
    local sum = 0
    for _, gen in ipairs(gens) do
        local p = gen:GetAttribute("RepairProgress") or 0
        sum = sum + p
        if p >= 100 then done = done + 1 end
    end
    local survivorsAlive, hooked = 0, 0
    for _, c in ipairs(survivorCharacters(true)) do
        local hum = c:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then survivorsAlive = survivorsAlive + 1 end
        if c:GetAttribute("IsHooked") then hooked = hooked + 1 end
    end
    local kd = killerDistance()
    local kdText = kd == math.huge and "n/a" or (math.floor(kd) .. "m")
    pcall(function()
        RoundParagraph:SetDesc(string.format(
            "Role: %s\nGenerators: %d/%d done (avg %.0f%%)\nSurvivors alive: %d (hooked %d)\nKiller distance: %s",
            teamName(), done, total, total > 0 and (sum / total) or 0, survivorsAlive, hooked, kdText))
    end)

    local c = getCharacter()
    if c and isKiller() then
        pcall(function()
            KillerParagraph:SetDesc(string.format(
                "Bloodlust: %s\nTerror radius: %s\nHooks used: %s\nCarrying: %s\nNearest survivor: %s",
                tostring(c:GetAttribute("BloodLust") or 0),
                tostring(c:GetAttribute("TerrorRadius") or 0),
                tostring(c:GetAttribute("HookCount") or 0),
                tostring(c:GetAttribute("IsCarrying") == true),
                (function()
                    local t, d = nearestSurvivorModel(math.huge)
                    if t then return math.floor(d) .. "m" end
                    return "none"
                end)()))
        end)
    end

    if State.KillerWarning and isSurvivor() and kd <= State.WarningDistance then
        notify("Killer Nearby", math.floor(kd) .. " studs away", 2)
    end
end)

loop(0.5, function()
    pcall(function()
        SkillCheckParagraph:SetDesc(string.format(
            "Rings found: %d   Sent by server: %d\nRings seen: %d   Answered: %d   Instant sent: %d\nServer validated: %d\nLast answer: %s\nLast timing: %s\nMode: %s",
            #SkillCheck.candidates, SkillCheck.received or 0,
            SkillCheck.seen, SkillCheck.attempts, SkillCheck.instantSent or 0,
            SkillCheck.validated or 0,
            SkillCheck.lastMethod or "none", SkillCheck.lastInfo, State.SkillCheckMode))
    end)
    pcall(function()
        PersistParagraph:SetDesc(Persist.status)
    end)
    pcall(function()
        MouseParagraph:SetDesc(string.format(
            "Interface open: %s\nCursor unlocked: %s\nHook: %s\nBehavior: %s",
            tostring(interfaceOpen()), tostring(Mouse.active), Mouse.status,
            tostring(UserInputService.MouseBehavior):gsub("Enum.MouseBehavior.", "")))
    end)
end)

refreshPlayerList()
applyLighting()
buildSkillCandidates()
bindSkillCheckCapture()
installMouseHook()
armTeleportPersist()

track(LP.OnTeleport:Connect(function(state)
    if state == Enum.TeleportState.Started or state == Enum.TeleportState.RequestedFromServer then
        armTeleportPersist()
    end
end))

if getgenv then
    getgenv().VDHub = {
        State = State,
        SkillCheck = SkillCheck,
        Mouse = Mouse,
        Persist = Persist,
        Arm = armTeleportPersist,
        Window = Window,
        Fluent = Fluent,
        InterfaceOpen = interfaceOpen,
        Unload = unloadHub,
        EspFolder = EspFolder,
        Press = pressAction,
        PickGenerator = pickGenerator,
        PointIsSafe = pointIsSafe,
        KillerDistanceTo = killerDistanceTo,
    }
end

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "PanicKey", "MenuKeybind" })
InterfaceManager:SetFolder("ViolenceDistrictHub")
SaveManager:SetFolder("ViolenceDistrictHub/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

Fluent:Notify({
    Title = "Violence District",
    Content = "Loaded. Role detected: " .. teamName(),
    SubContent = IS_MOBILE and "Mobile mode active" or "Desktop mode active",
    Duration = 7
})

SaveManager:LoadAutoloadConfig()

task.defer(function()
    task.wait(0.4)
    pcall(function()
        if Window.Minimized == true then Window:Minimize() end
    end)
end)

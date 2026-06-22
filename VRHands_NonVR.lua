do
    local qot = queue_on_teleport or (syn and syn.queue_on_teleport)
    local checks = {
        { "getrawmetatable",   getrawmetatable   },
        { "setreadonly",       setreadonly       },
        { "newcclosure",       newcclosure       },
        { "getnamecallmethod", getnamecallmethod },
        { "getgc",             getgc             },
        { "queue_on_teleport", qot               },
    }
    local missing, report = {}, "[VR Hands No-VR] UNC test:\n"
    for _, c in ipairs(checks) do
        local ok = type(c[2]) == "function"
        report = report .. ("  [%s] %s\n"):format(ok and "+" or "-", c[1])
        if not ok then table.insert(missing, c[1]) end
    end
    print(report)
    if #missing > 0 then
        warn("[VR Hands No-VR] Missing functions: " .. table.concat(missing, ", "))
        warn("[VR Hands No-VR] Executor not supported - aborting (no teleport).")
        return
    end
    print("[VR Hands No-VR] UNC test passed - launching.")
end

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local hrs = [==[
local VRService   = game:GetService("VRService")
local UIS         = game:GetService("UserInputService")
local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local identity    = CFrame.identity

do
    local mt = getrawmetatable(game)
    local oldIndex    = mt.__index
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__index = newcclosure(function(self, k)
        if k == "VREnabled" and (self == VRService or self == UIS) then return true end
        return oldIndex(self, k)
    end)
    mt.__namecall = newcclosure(function(self, ...)
        if self == VRService then
            local m = getnamecallmethod()
            if m == "GetUserCFrameEnabled" then return true end
            if m == "GetUserCFrame" then return identity end
        end
        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
end

task.spawn(function()
    local function ensureFolder(p, n)
        local f = p:FindFirstChild(n)
        if not f then f = Instance.new("Folder"); f.Name = n; f.Parent = p end
        return f
    end
    local function ensurePart(p, n)
        local x = p:FindFirstChild(n)
        if not x then
            x = Instance.new("Part"); x.Name = n
            x.Anchored = true; x.CanCollide = false; x.Transparency = 1
            x.Size = Vector3.new(1,1,1); x.Parent = p
        end
        return x
    end
    local function populate(cam)
        if not cam then return end
        ensurePart(ensureFolder(cam, "VRCoreEffectParts"), "Cursor")
        ensurePart(ensureFolder(cam, "VRCorePanelParts"), "BottomBar_Part")
    end
    populate(workspace.CurrentCamera)
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        populate(workspace.CurrentCamera)
    end)
    local t0 = os.clock()
    while os.clock() - t0 < 30 do
        populate(workspace.CurrentCamera)
        task.wait(0.1)
    end
end)

task.spawn(function()
    local lp = Players.LocalPlayer
    while not lp do task.wait() lp = Players.LocalPlayer end
    local uid = tostring(lp.UserId)

    local vrPlayers = workspace:WaitForChild("VRPlayers", 60)
    if not vrPlayers then warn("[NoVR] no VRPlayers") return end
    local rig = vrPlayers:WaitForChild(uid, 60)
    if not rig then warn("[NoVR] The server did not issue a rig") return end
    rig:WaitForChild("VRHead", 20)
    rig:WaitForChild("LeftHand", 20)
    rig:WaitForChild("RightHand", 20)
    local scaleVal = rig:FindFirstChild("VRScale")
    local cam = workspace.CurrentCamera

    local S = {
        reach  = 0.55, spread = 0.34, height = -0.25,
        sens   = 0.0025, moveK = 0.16, look = true,
        scale  = 10,
    }

    local ok, VRUtils = pcall(function()
        return require(lp.PlayerScripts.ClientLoader.PlayerModule.VRModule.VRUtils)
    end)
    if ok and type(VRUtils) == "table" then
        VRUtils.GetUserCFrame = function(uc, scale)
            scale = scale or cam.HeadScale
            if scale <= 1 then scale = math.max((scaleVal and scaleVal.Value or 1) * 60, 6) end
            if uc == Enum.UserCFrame.LeftHand then
                local c = CFrame.new(-S.spread, S.height, -S.reach)
                return c.Rotation + c.Position * scale
            elseif uc == Enum.UserCFrame.RightHand then
                local c = CFrame.new(S.spread, S.height, -S.reach)
                return c.Rotation + c.Position * scale
            end
            return identity
        end
    else
        warn("[NoVR] failed to intercept VRUtils")
    end

    local vrm, Input
    for _ = 1, 250 do
        for _, o in pairs(getgc(true)) do
            if type(o) == "table"
               and rawget(o,"HeadsetPart") ~= nil and rawget(o,"Input") ~= nil
               and rawget(o,"CharacterScale") ~= nil and rawget(o,"DataManager") ~= nil then
                vrm = o; Input = rawget(o,"Input"); break
            end
        end
        if Input then break end
        for _, o in pairs(getgc(true)) do
            if type(o) == "table" and rawget(o,"directionLateral") ~= nil
               and rawget(o,"rFist") ~= nil and rawget(o,"turnDirection") ~= nil then
                Input = o; break
            end
        end
        if Input then break end
        task.wait(0.1)
    end
    if not Input then warn("[NoVR] Input object not found - grip will not work") end

    task.spawn(function()
        for _ = 1, 100 do
            pcall(function() RunService:UnbindFromRenderStep("Inputs") end)
            task.wait(0.1)
        end
    end)

    pcall(function()
        local pmMT = getrawmetatable(vrm.PropManager)
        if pmMT and rawget(pmMT, "GetBestGrabPartInRadius") then
            local orig = pmMT.GetBestGrabPartInRadius
            setreadonly(pmMT, false)
            pmMT.GetBestGrabPartInRadius = function(self, root, prox, radius, scale, ...)
                return orig(self, root, prox, (radius or 0) * 3.5, scale, ...)
            end
            setreadonly(pmMT, true)
        end
        local cmMT = getrawmetatable(vrm.CharacterManager)
        if cmMT and rawget(cmMT, "GetClosestCharacterInRadius") then
            local orig = cmMT.GetClosestCharacterInRadius
            setreadonly(cmMT, false)
            cmMT.GetClosestCharacterInRadius = function(self, pos, radius, ...)
                return orig(self, pos, (radius or 0) * 3.5, ...)
            end
            setreadonly(cmMT, true)
        end
    end)

    local function setScale(n)
        n = math.clamp(math.floor(n + 0.5), 1, 10)
        S.scale = n
        if scaleVal then pcall(function() scaleVal.Value = n / 10 end) end
        if vrm and vrm.DataManager and vrm.DataManager.SettingsManager then
            pcall(function() vrm.DataManager.SettingsManager:SetValue("vrscale", n) end)
        end
    end
    setScale(10)

    cam.HeadLocked = true
    local yaw, pitch
    do
        local lv = cam.CFrame.LookVector
        yaw   = math.atan2(-lv.X, -lv.Z)
        pitch = math.asin(math.clamp(lv.Y, -1, 1))
    end
    local camPos = cam.CFrame.Position
    local keys = {}

    local function setLook(v)
        S.look = v
        UIS.MouseBehavior    = v and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
        UIS.MouseIconEnabled = not v
    end
    setLook(true)

    UIS.InputBegan:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.Keyboard then
            keys[io.KeyCode] = true
            if io.KeyCode == Enum.KeyCode.LeftAlt then setLook(not S.look) end
            if io.KeyCode == Enum.KeyCode.Equals  then setScale(S.scale + 1) end
            if io.KeyCode == Enum.KeyCode.Minus   then setScale(S.scale - 1) end

            if Input and io.KeyCode == Enum.KeyCode.E then Input.rIndex = 1; Input.rFist = 0; Input.rThumb = 0 end
            if Input and io.KeyCode == Enum.KeyCode.Q then Input.lIndex = 1; Input.lFist = 0; Input.lThumb = 0 end
        elseif io.UserInputType == Enum.UserInputType.MouseButton1 then
            if Input then Input.rFist = 1; Input.rIndex = 1 end
        elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
            if Input then Input.lFist = 1; Input.lIndex = 1 end
        end
    end)
    UIS.InputEnded:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.Keyboard then
            keys[io.KeyCode] = false
            if Input and io.KeyCode == Enum.KeyCode.E then Input.rIndex = 0 end
            if Input and io.KeyCode == Enum.KeyCode.Q then Input.lIndex = 0 end
        elseif io.UserInputType == Enum.UserInputType.MouseButton1 then
            if Input then Input.rFist = 0; Input.rIndex = 0 end
        elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
            if Input then Input.lFist = 0; Input.lIndex = 0 end
        end
    end)
    UIS.InputChanged:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseWheel then
            S.reach = math.clamp(S.reach - io.Position.Z * 0.07, 0.15, 2.5)
        end
    end)

    RunService:BindToRenderStep("NoVR_Control", Enum.RenderPriority.Camera.Value + 1, function(dt)
        if S.look then
            local d = UIS:GetMouseDelta()
            yaw   = yaw - d.X * S.sens
            pitch = math.clamp(pitch - d.Y * S.sens, -1.45, 1.45)
            UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
        local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)

        local hs  = cam.HeadScale; if hs <= 1 then hs = S.scale * 6 end
        local spd = (10 + S.scale * 4) * hs * S.moveK
        local mv  = Vector3.zero
        if keys[Enum.KeyCode.W] then mv += Vector3.new(0,0,-1) end
        if keys[Enum.KeyCode.S] then mv += Vector3.new(0,0, 1) end
        if keys[Enum.KeyCode.A] then mv += Vector3.new(-1,0,0) end
        if keys[Enum.KeyCode.D] then mv += Vector3.new( 1,0,0) end
        if keys[Enum.KeyCode.Space]     then mv += Vector3.new(0, 1,0) end
        if keys[Enum.KeyCode.LeftShift] then mv += Vector3.new(0,-1,0) end
        if mv.Magnitude > 0 then camPos = camPos + (rot * mv.Unit) * spd * dt end

        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = CFrame.new(camPos) * rot

        if Input then
            Input.directionLateral  = Vector2.zero
            Input.directionVertical = 0
            Input.turnDirection     = 0
        end
    end)

    pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "NoVR_HUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
        gui.Parent = lp:WaitForChild("PlayerGui")
        local lbl = Instance.new("TextLabel", gui)
        lbl.AnchorPoint = Vector2.new(0,1)
        lbl.Position = UDim2.new(0,10,1,-10); lbl.Size = UDim2.new(0,340,0,170)
        lbl.BackgroundColor3 = Color3.fromRGB(0,0,0); lbl.BackgroundTransparency = 0.45
        lbl.TextColor3 = Color3.fromRGB(255,255,255)
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.Font = Enum.Font.Code; lbl.TextSize = 14
        RunService.Heartbeat:Connect(function()
            lbl.Text = ("[VR Hands :: No-VR]\n"
                .."Mouse - look  |  WASD - fly\n"
                .."Space/Shift - up / down\n"
                .."LMB/RMB - grab objects (R/L)\n"
                .."E/Q - pinch: grab PLAYERS (R/L)\n"
                .."Wheel - hand reach\n"
                .."+/- - body size: %d/10\n"
                .."LeftAlt - free the cursor")
                :format(math.floor(S.scale))
        end)
    end)

    print("[NoVR] control active.")
end)
]==]

if queue_on_teleport then
    queue_on_teleport(hrs)
elseif syn and syn.queue_on_teleport then
    syn.queue_on_teleport(hrs)
end

TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)

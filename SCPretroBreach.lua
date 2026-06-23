-- // t.me/arceusxcommunity <3
if _G.__TeamESP_Cleanup then pcall(_G.__TeamESP_Cleanup) end

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local Workspace     = game:GetService("Workspace")

local LocalPlayer   = Players.LocalPlayer
local Camera        = Workspace.CurrentCamera

local Settings = {
    -- ESP
    Enabled       = true,
    TeamColors    = true,                       -- use team color; if false use static colors
    EnemyColor    = Color3.fromRGB(255, 64, 64),
    AllyColor     = Color3.fromRGB(64, 255, 96),
    ShowTeam      = true,                        -- draw teammates too
    Box           = true,
    Name          = true,
    Distance      = true,
    Healthbar     = true,
    Tracer        = false,
    TracerFrom    = "Bottom",                    -- Bottom / Center / Mouse
    TextSize      = 13,
    MaxDistance   = 1000,

    -- Aimbot
    AimEnabled    = false,
    AimPart       = "Head",            -- Head / Torso / HumanoidRootPart
    AimKey        = "MB2",             -- hold to aim (right mouse button)
    AimFOV        = 120,               -- pixels radius; only targets inside the circle
    AimShowFOV    = true,
    AimSmooth     = 0.25,              -- 0 = instant snap, 1 = very slow
    AimTeamCheck  = true,              -- never aim at teammates
    AimWallCheck  = false,             -- skip targets behind walls
    AimVisibleOnly= false,             -- only target on-screen players

    -- Mobile lock button
    AimMobileButton = false,           -- show floating tap-to-lock button
    AimLocked       = false,           -- currently locked onto a player

    -- Local player tweaks
    SpeedEnabled  = false,
    WalkSpeed     = 16,                 -- default walkspeed
    Noclip        = false,
    Fullbright    = false,

    -- Item ESP
    ItemEnabled   = false,
    ItemCats      = { Weapons = true, Grenades = true, Medical = true, Keycards = true, Utility = true, Ammo = true, SCP = true },
    ItemDistance  = true,
    ItemMaxDist   = 700,
}

local function newLine(thickness)
    local l = Drawing.new("Line")
    l.Visible = false
    l.Thickness = thickness or 1
    l.Transparency = 1
    return l
end

local function newText()
    local t = Drawing.new("Text")
    t.Visible = false
    t.Center = true
    t.Outline = true
    t.OutlineColor = Color3.new(0, 0, 0)
    t.Size = Settings.TextSize
    t.Font = 2
    return t
end

local function newSquare()
    local s = Drawing.new("Square")
    s.Visible = false
    s.Thickness = 1
    s.Filled = false
    s.Transparency = 1
    return s
end

local ESP = {}

local function createESP(player)
    if ESP[player] then return end
    ESP[player] = {
        box        = newSquare(),
        name       = newText(),
        distance   = newText(),
        tracer     = newLine(1),
        hpBg       = newSquare(),
        hpFill     = newSquare(),
    }
    ESP[player].hpBg.Filled = true
    ESP[player].hpBg.Color = Color3.new(0, 0, 0)
    ESP[player].hpFill.Filled = true
end

local function destroyESP(player)
    local e = ESP[player]
    if not e then return end
    for _, d in pairs(e) do
        pcall(function() d:Remove() end)
    end
    ESP[player] = nil
end

local function hideESP(e)
    e.box.Visible = false
    e.name.Visible = false
    e.distance.Visible = false
    e.tracer.Visible = false
    e.hpBg.Visible = false
    e.hpFill.Visible = false
end

local function getColor(player)
    if Settings.TeamColors then
        local team = player.Team
        if team then
            return team.TeamColor.Color
        end
        return Color3.new(1, 1, 1)
    else
        if player.Team == LocalPlayer.Team and LocalPlayer.Team ~= nil then
            return Settings.AllyColor
        end
        return Settings.EnemyColor
    end
end

local function tracerOrigin()
    if Settings.TracerFrom == "Center" then
        return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    elseif Settings.TracerFrom == "Mouse" then
        local m = LocalPlayer:GetMouse()
        return Vector2.new(m.X, m.Y)
    else
        return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
    end
end

local function updateESP()
    for player, e in pairs(ESP) do
        local ok = false
        repeat
            if not Settings.Enabled then break end
            if player == LocalPlayer then break end

            local char = player.Character
            if not char then break end
            local root = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not root or not humanoid or humanoid.Health <= 0 then break end

            local sameTeam = (player.Team == LocalPlayer.Team and LocalPlayer.Team ~= nil)
            if sameTeam and not Settings.ShowTeam then break end

            local dist = (Camera.CFrame.Position - root.Position).Magnitude
            if dist > Settings.MaxDistance then break end

            local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)
            if not onScreen then break end

            local headPos = (char:FindFirstChild("Head") and char.Head.Position)
                or (root.Position + Vector3.new(0, 2.5, 0))
            local topV    = Camera:WorldToViewportPoint(headPos + Vector3.new(0, 0.5, 0))
            local botV    = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))

            local height = math.abs(topV.Y - botV.Y)
            local width  = height * 0.55
            local x      = rootPos.X - width / 2
            local y      = topV.Y

            local color = getColor(player)
            ok = true

            if Settings.Box then
                e.box.Visible = true
                e.box.Color = color
                e.box.Size = Vector2.new(width, height)
                e.box.Position = Vector2.new(x, y)
            else
                e.box.Visible = false
            end

            if Settings.Healthbar then
                local hp = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                local barH = height
                local barX = x - 5
                e.hpBg.Visible = true
                e.hpBg.Size = Vector2.new(3, barH)
                e.hpBg.Position = Vector2.new(barX, y)

                e.hpFill.Visible = true
                e.hpFill.Size = Vector2.new(3, barH * hp)
                e.hpFill.Position = Vector2.new(barX, y + barH * (1 - hp))
                e.hpFill.Color = Color3.fromRGB(255 - math.floor(255 * hp), math.floor(255 * hp), 60)
            else
                e.hpBg.Visible = false
                e.hpFill.Visible = false
            end

            if Settings.Name then
                e.name.Visible = true
                e.name.Color = color
                e.name.Size = Settings.TextSize
                e.name.Text = player.DisplayName ~= "" and player.DisplayName or player.Name
                e.name.Position = Vector2.new(rootPos.X, y - 16)
            else
                e.name.Visible = false
            end

            if Settings.Distance then
                e.distance.Visible = true
                e.distance.Color = color
                e.distance.Size = Settings.TextSize
                local teamName = player.Team and player.Team.Name or "Neutral"
                e.distance.Text = string.format("[%s] %dm", teamName, math.floor(dist))
                e.distance.Position = Vector2.new(rootPos.X, y + height + 2)
            else
                e.distance.Visible = false
            end

            if Settings.Tracer then
                e.tracer.Visible = true
                e.tracer.Color = color
                e.tracer.From = tracerOrigin()
                e.tracer.To = Vector2.new(rootPos.X, y + height)
            else
                e.tracer.Visible = false
            end
        until true

        if not ok then
            hideESP(e)
        end
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then createESP(p) end
end
Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then createESP(p) end
end)
Players.PlayerRemoving:Connect(function(p)
    destroyESP(p)
end)

local renderConn = RunService.RenderStepped:Connect(function()
    local ok, err = pcall(updateESP)
    if not ok then warn("[ESP] update error:", err) end
end)

local UserInputService = game:GetService("UserInputService")

local fovCircle = Drawing.new("Circle")
fovCircle.Visible = false
fovCircle.Thickness = 1.5
fovCircle.Transparency = 1
fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.NumSides = 64
fovCircle.Filled = false

local KeyMap = {
    MB1 = Enum.UserInputType.MouseButton1,
    MB2 = Enum.UserInputType.MouseButton2,
    E   = Enum.KeyCode.E,
    Q   = Enum.KeyCode.Q,
    C   = Enum.KeyCode.C,
    LeftShift = Enum.KeyCode.LeftShift,
    LeftAlt   = Enum.KeyCode.LeftAlt,
    F = Enum.KeyCode.F,
    V = Enum.KeyCode.V,
}

local function aimKeyHeld()
    local bind = KeyMap[Settings.AimKey]
    if not bind then return false end
    if typeof(bind) == "EnumItem" and bind.EnumType == Enum.UserInputType then
        return UserInputService:IsMouseButtonPressed(bind)
    else
        return UserInputService:IsKeyDown(bind)
    end
end

local function visibleCheck(targetChar)
    if not Settings.AimWallCheck then return true end
    local origin = Camera.CFrame.Position
    local target = targetChar:FindFirstChild("HumanoidRootPart")
    if not target then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, targetChar }
    local dir = target.Position - origin
    local hit = Workspace:Raycast(origin, dir, params)
    return hit == nil
end

local function partForPlayer(player)
    if not player or player == LocalPlayer then return nil end
    local char = player.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local part = char:FindFirstChild(Settings.AimPart) or char:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not part then return nil end
    return part
end

local function getAimTarget()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local best, bestPlayer, bestDist
    for _, player in ipairs(Players:GetPlayers()) do
        repeat
            if player == LocalPlayer then break end
            if Settings.AimTeamCheck and player.Team == LocalPlayer.Team and LocalPlayer.Team ~= nil then break end

            local part = partForPlayer(player)
            if not part then break end
            local char = player.Character

            local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
            if Settings.AimVisibleOnly and not onScreen then break end
            if screenPos.Z <= 0 then break end

            local d = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
            if d > Settings.AimFOV then break end
            if not visibleCheck(char) then break end

            if not bestDist or d < bestDist then
                bestDist = d
                best = part
                bestPlayer = player
            end
        until true
    end
    return best, bestPlayer
end

local lockedPlayer = nil

local function aimAtPart(target)
    local aimAt = CFrame.new(Camera.CFrame.Position, target.Position)
    if Settings.AimSmooth <= 0 then
        Camera.CFrame = CFrame.new(Camera.CFrame.Position) * (aimAt - aimAt.Position)
    else
        local smooth = math.clamp(1 - Settings.AimSmooth, 0.02, 1)
        Camera.CFrame = Camera.CFrame:Lerp(
            CFrame.new(Camera.CFrame.Position) * (aimAt - aimAt.Position),
            smooth
        )
    end
end

local aimConn = RunService.RenderStepped:Connect(function()
    if Settings.AimEnabled and Settings.AimShowFOV then
        fovCircle.Visible = true
        fovCircle.Radius = Settings.AimFOV
        fovCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    else
        fovCircle.Visible = false
    end

    if not Settings.AimEnabled then return end

    if Settings.AimLocked then
        local part = partForPlayer(lockedPlayer)
        if part then
            aimAtPart(part)
        end
        return
    end

    if not aimKeyHeld() then return end
    local ok, target = pcall(getAimTarget)
    if not ok or not target then return end
    aimAtPart(target)
end)

local mobileGui, mobileBtn

local function setLockVisual()
    if not mobileBtn then return end
    if Settings.AimLocked then
        mobileBtn.Text = "LOCKED"
        mobileBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    else
        mobileBtn.Text = "AIM"
        mobileBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    end
end

local function toggleLock()
    if Settings.AimLocked then
        Settings.AimLocked = false
        lockedPlayer = nil
    else
        local _, player = getAimTarget()
        if player then
            lockedPlayer = player
            Settings.AimLocked = true
        else
            lockedPlayer = nil
            Settings.AimLocked = false
        end
    end
    setLockVisual()
end

local function createMobileButton()
    if mobileGui then return end
    mobileGui = Instance.new("ScreenGui")
    mobileGui.Name = "TeamESP_AimButton"
    mobileGui.ResetOnSpawn = false
    mobileGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    mobileGui.IgnoreGuiInset = true
    local ok = pcall(function()
        mobileGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not ok then mobileGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    mobileBtn = Instance.new("TextButton")
    mobileBtn.Size = UDim2.fromOffset(86, 86)
    mobileBtn.Position = UDim2.new(0.78, 0, 0.45, 0)
    mobileBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    mobileBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    mobileBtn.BackgroundTransparency = 0.25
    mobileBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    mobileBtn.Font = Enum.Font.GothamBold
    mobileBtn.TextSize = 18
    mobileBtn.Text = "AIM"
    mobileBtn.AutoButtonColor = false
    mobileBtn.Parent = mobileGui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = mobileBtn
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.5
    stroke.Parent = mobileBtn

    local dragging, moved, startPos, startInput
    mobileBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            moved = false
            startInput = input
            startPos = Vector2.new(input.Position.X, input.Position.Y)
            local bp = mobileBtn.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved then toggleLock() end
                end
            end)
            mobileBtn:SetAttribute("bx", bp.X.Offset)
            mobileBtn:SetAttribute("by", bp.Y.Offset)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == startInput then
            local cur = Vector2.new(input.Position.X, input.Position.Y)
            local delta = cur - startPos
            if delta.Magnitude > 6 then moved = true end
            mobileBtn.Position = UDim2.new(
                mobileBtn.Position.X.Scale, mobileBtn:GetAttribute("bx") + delta.X,
                mobileBtn.Position.Y.Scale, mobileBtn:GetAttribute("by") + delta.Y
            )
        end
    end)

    setLockVisual()
end

local function destroyMobileButton()
    Settings.AimLocked = false
    lockedPlayer = nil
    if mobileGui then pcall(function() mobileGui:Destroy() end) end
    mobileGui, mobileBtn = nil, nil
end

local Lighting = game:GetService("Lighting")

local function getHumanoid()
    local char = LocalPlayer.Character
    if not char then return nil, nil end
    return char:FindFirstChildOfClass("Humanoid"), char
end

local fbOld
local function applyFullbright(on)
    if on then
        if not fbOld then
            fbOld = {
                Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
                FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows,
                Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
            }
        end
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1e9
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    elseif fbOld then
        Lighting.Brightness = fbOld.Brightness
        Lighting.ClockTime = fbOld.ClockTime
        Lighting.FogEnd = fbOld.FogEnd
        Lighting.GlobalShadows = fbOld.GlobalShadows
        Lighting.Ambient = fbOld.Ambient
        Lighting.OutdoorAmbient = fbOld.OutdoorAmbient
    end
end

local noclipOrig = setmetatable({}, { __mode = "k" })

local function setNoclip(on)
    if not on then
        for p, orig in pairs(noclipOrig) do
            if typeof(p) == "Instance" and p.Parent then
                p.CanCollide = orig
            end
            noclipOrig[p] = nil
        end
    end
end

local origWalkSpeed = nil

local function enableSpeed(on)
    local hum = getHumanoid()
    if on then
        if hum and not origWalkSpeed then origWalkSpeed = hum.WalkSpeed end
    else
        if hum then hum.WalkSpeed = origWalkSpeed or 16 end
        origWalkSpeed = nil
    end
end

local playerConn = RunService.Heartbeat:Connect(function()
    local hum, char = getHumanoid()
    if not hum then return end
    if Settings.SpeedEnabled then hum.WalkSpeed = Settings.WalkSpeed end
    if Settings.Noclip and char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                if noclipOrig[p] == nil then noclipOrig[p] = p.CanCollide end
                p.CanCollide = false
            end
        end
    end
end)

local itemDraws = {}
local itemRefreshT = 0

local catColor = {
    Weapons  = Color3.fromRGB(255, 170, 60),
    Grenades = Color3.fromRGB(255, 80, 80),
    Medical  = Color3.fromRGB(90, 255, 120),
    Keycards = Color3.fromRGB(80, 200, 255),
    Utility  = Color3.fromRGB(255, 230, 90),
    Ammo     = Color3.fromRGB(200, 200, 200),
    SCP      = Color3.fromRGB(225, 90, 255),
}

local function classifyItem(name)
    local n = string.lower(name)
    if n:find("scp") then return "SCP" end
    if n:find("ammo") then return "Ammo" end
    if n:find("card") then return "Keycards" end
    if n:find("grenade") or n:find("flashbang") or n:find("flash bang") then return "Grenades" end
    if n:find("medkit") or n:find("bandage") or n:find("cola") or n:find("pills")
        or n:find("adrenaline") or n:find("first aid") or n:find("medical") or n:find("500") then
        return "Medical"
    end
    if n:find("hacking") or n:find("device") or n:find("radio") or n:find("disk") or n:find("remote") then
        return "Utility"
    end
    return "Weapons"
end

local itemSpawns = Workspace:FindFirstChild("ItemSpawns")

local function promptInfo(pp)
    local act = pp.ActionText or ""
    local part = pp.Parent
    if not part then return nil end

    local name
    if act:sub(1, 7) == "Pick up" then
        name = act:sub(9)
    elseif part.Name == "PrimAmmo" then
        name = "Primary Ammo"
    elseif part.Name == "SecAmmo" or part.Name == "Ammo" then
        name = "Ammo"
    else
        return nil
    end

    local pos
    if part:IsA("BasePart") then
        pos = part.Position
    elseif part:IsA("Model") then
        pos = part:GetPivot().Position
    end
    if not pos then return nil end
    return name, pos
end

local function toolInfo(t)
    local h = t:FindFirstChild("Handle")
    if not h then return nil end
    return t.Name, h.Position
end

local function infoFor(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("ProximityPrompt") then return promptInfo(obj) end
    if obj:IsA("Tool") then return toolInfo(obj) end
    return nil
end

local function clearItemDraws()
    for k, d in pairs(itemDraws) do
        pcall(function() d.text:Remove() end)
        pcall(function() d.dot:Remove() end)
        itemDraws[k] = nil
    end
end

local function collectItems()
    local found = {}
    local camPos = Camera.CFrame.Position
    local maxD = Settings.ItemMaxDist

    if not itemSpawns or not itemSpawns.Parent then
        itemSpawns = Workspace:FindFirstChild("ItemSpawns")
    end
    if itemSpawns then
        for _, pp in ipairs(itemSpawns:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                local name, pos = promptInfo(pp)
                if name and (camPos - pos).Magnitude <= maxD then found[pp] = true end
            end
        end
    end

    local function consider(t)
        local name, pos = toolInfo(t)
        if name and (camPos - pos).Magnitude <= maxD then found[t] = true end
    end
    local dead = Workspace:FindFirstChild("DeadBodies")
    if dead then
        for _, t in ipairs(dead:GetDescendants()) do
            if t:IsA("Tool") then consider(t) end
        end
    end
    for _, c in ipairs(Workspace:GetChildren()) do
        if c:IsA("Tool") then
            consider(c)
        elseif c:IsA("Model") then
            local hum = c:FindFirstChildOfClass("Humanoid")
            if (not hum) or hum.Health <= 0 then
                local t = c:FindFirstChildOfClass("Tool")
                if t then consider(t) end
            end
        end
    end
    return found
end

local itemConn = RunService.RenderStepped:Connect(function(dt)
    if not Settings.ItemEnabled then
        for _, d in pairs(itemDraws) do d.text.Visible = false; d.dot.Visible = false end
        return
    end

    itemRefreshT = itemRefreshT + dt
    if itemRefreshT > 0.5 then
        itemRefreshT = 0
        local found = collectItems()
        for k, d in pairs(itemDraws) do
            if not found[k] then
                pcall(function() d.text:Remove() end)
                pcall(function() d.dot:Remove() end)
                itemDraws[k] = nil
            end
        end
        for obj in pairs(found) do
            if not itemDraws[obj] then
                local t = Drawing.new("Text")
                t.Center = true; t.Outline = true; t.Size = 13; t.Font = 2; t.Visible = false
                local dot = Drawing.new("Square")
                dot.Filled = true; dot.Thickness = 1; dot.Size = Vector2.new(6, 6); dot.Visible = false
                itemDraws[obj] = { text = t, dot = dot }
            end
        end
    end

    for obj, d in pairs(itemDraws) do
        local ok = false
        repeat
            local name, pos = infoFor(obj)
            if not name then break end
            local cat = classifyItem(name)
            if not Settings.ItemCats[cat] then break end

            local dist = (Camera.CFrame.Position - pos).Magnitude
            if dist > Settings.ItemMaxDist then break end
            local sp, on = Camera:WorldToViewportPoint(pos)
            if not on then break end

            ok = true
            local col = catColor[cat] or Color3.new(1, 1, 1)
            d.dot.Visible = true
            d.dot.Color = col
            d.dot.Position = Vector2.new(sp.X - 3, sp.Y - 3)

            d.text.Visible = true
            d.text.Color = col
            d.text.Text = Settings.ItemDistance
                and string.format("%s [%dm]", name, math.floor(dist))
                or name
            d.text.Position = Vector2.new(sp.X, sp.Y - 16)
        until true
        if not ok then d.text.Visible = false; d.dot.Visible = false end
    end
end)

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()

local Window = Fluent:CreateWindow({
    Title = "SCP retroBreach",
    SubTitle = "t.me/arceusxcommunity",
    TabWidth = 150,
    Size = UDim2.fromOffset(540, 420),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

local Minimizer = Fluent:CreateMinimizer({
    Icon = "home",
    Size = UDim2.fromOffset(44, 44),
    Position = UDim2.new(0, 320, 0, 24),
    Acrylic = true,
    Corner = 10,
    Transparency = 1,
    Draggable = true,
    Visible = true, 
})

local Tabs = {
    Main   = Window:AddTab({ Title = "ESP",     Icon = "eye" }),
    Aim    = Window:AddTab({ Title = "Aim",     Icon = "crosshair" }),
    Player = Window:AddTab({ Title = "Player",  Icon = "user" }),
    Items  = Window:AddTab({ Title = "Items",   Icon = "package" }),
    Colors = Window:AddTab({ Title = "Colors",  Icon = "palette" }),
}

Tabs.Main:AddToggle("Enabled", { Title = "Enabled", Default = Settings.Enabled })
    :OnChanged(function() Settings.Enabled = Fluent.Options.Enabled.Value end)

Tabs.Main:AddToggle("ShowTeam", { Title = "Show teammates", Default = Settings.ShowTeam })
    :OnChanged(function() Settings.ShowTeam = Fluent.Options.ShowTeam.Value end)

Tabs.Main:AddSection("Features")

local function feature(key, title)
    Tabs.Main:AddToggle(key, { Title = title, Default = Settings[key] })
        :OnChanged(function() Settings[key] = Fluent.Options[key].Value end)
end
feature("Box", "Box")
feature("Name", "Name")
feature("Distance", "Distance + Team")
feature("Healthbar", "Health bar")
feature("Tracer", "Tracer")

Tabs.Main:AddDropdown("TracerFrom", {
    Title = "Tracer origin",
    Values = { "Bottom", "Center", "Mouse" },
    Default = 1,
}):OnChanged(function(v) Settings.TracerFrom = v end)

Tabs.Main:AddSlider("MaxDistance", {
    Title = "Max distance",
    Default = Settings.MaxDistance, Min = 100, Max = 5000, Rounding = 0,
    Callback = function(v) Settings.MaxDistance = v end,
})

Tabs.Main:AddSlider("TextSize", {
    Title = "Text size",
    Default = Settings.TextSize, Min = 10, Max = 24, Rounding = 0,
    Callback = function(v) Settings.TextSize = v end,
})

Tabs.Aim:AddToggle("AimEnabled", { Title = "Aimbot enabled", Default = Settings.AimEnabled })
    :OnChanged(function() Settings.AimEnabled = Fluent.Options.AimEnabled.Value end)


Tabs.Aim:AddToggle("AimMobileButton", { Title = "Mobile lock button", Default = Settings.AimMobileButton })
    :OnChanged(function()
        Settings.AimMobileButton = Fluent.Options.AimMobileButton.Value
        if Settings.AimMobileButton then createMobileButton() else destroyMobileButton() end
    end)

Tabs.Aim:AddDropdown("AimKey", {
    Title = "Aim key (hold)",
    Values = { "MB2", "MB1", "E", "Q", "C", "F", "V", "LeftShift", "LeftAlt" },
    Default = 1,
}):OnChanged(function(v) Settings.AimKey = v end)

Tabs.Aim:AddDropdown("AimPart", {
    Title = "Target part",
    Values = { "Head", "Torso", "HumanoidRootPart" },
    Default = 1,
}):OnChanged(function(v) Settings.AimPart = v end)

Tabs.Aim:AddSlider("AimFOV", {
    Title = "FOV (pixels)",
    Default = Settings.AimFOV, Min = 20, Max = 600, Rounding = 0,
    Callback = function(v) Settings.AimFOV = v end,
})

Tabs.Aim:AddSlider("AimSmooth", {
    Title = "Smoothness (0 = snap)",
    Default = Settings.AimSmooth, Min = 0, Max = 0.95, Rounding = 2,
    Callback = function(v) Settings.AimSmooth = v end,
})

Tabs.Aim:AddSection("Filters")

Tabs.Aim:AddToggle("AimShowFOV", { Title = "Show FOV circle", Default = Settings.AimShowFOV })
    :OnChanged(function() Settings.AimShowFOV = Fluent.Options.AimShowFOV.Value end)

Tabs.Aim:AddToggle("AimTeamCheck", { Title = "Ignore teammates", Default = Settings.AimTeamCheck })
    :OnChanged(function() Settings.AimTeamCheck = Fluent.Options.AimTeamCheck.Value end)

Tabs.Aim:AddToggle("AimWallCheck", { Title = "Wall check (skip behind walls)", Default = Settings.AimWallCheck })
    :OnChanged(function() Settings.AimWallCheck = Fluent.Options.AimWallCheck.Value end)

Tabs.Aim:AddToggle("AimVisibleOnly", { Title = "On-screen targets only", Default = Settings.AimVisibleOnly })
    :OnChanged(function() Settings.AimVisibleOnly = Fluent.Options.AimVisibleOnly.Value end)


Tabs.Player:AddToggle("SpeedEnabled", { Title = "Speed hack", Default = Settings.SpeedEnabled })
    :OnChanged(function()
        Settings.SpeedEnabled = Fluent.Options.SpeedEnabled.Value
        enableSpeed(Settings.SpeedEnabled)
    end)

Tabs.Player:AddSlider("WalkSpeed", {
    Title = "Walk / sprint speed",
    Default = Settings.WalkSpeed, Min = 16, Max = 150, Rounding = 0,
    Callback = function(v) Settings.WalkSpeed = v end,
})

Tabs.Player:AddSection("Misc")

Tabs.Player:AddToggle("Noclip", { Title = "Noclip", Default = Settings.Noclip })
    :OnChanged(function()
        Settings.Noclip = Fluent.Options.Noclip.Value
        setNoclip(Settings.Noclip)
    end)

Tabs.Player:AddToggle("Fullbright", { Title = "Fullbright", Default = Settings.Fullbright })
    :OnChanged(function()
        Settings.Fullbright = Fluent.Options.Fullbright.Value
        applyFullbright(Settings.Fullbright)
    end)

Tabs.Items:AddToggle("ItemEnabled", { Title = "Item ESP enabled", Default = Settings.ItemEnabled })
    :OnChanged(function() Settings.ItemEnabled = Fluent.Options.ItemEnabled.Value end)


Tabs.Items:AddDropdown("ItemCats", {
    Title = "Categories",
    Values = { "Weapons", "Grenades", "Medical", "Keycards", "Utility", "Ammo", "SCP" },
    Multi = true,
    Default = { "Weapons", "Grenades", "Medical", "Keycards", "Utility", "Ammo", "SCP" },
}):OnChanged(function(value) Settings.ItemCats = value end)

Tabs.Items:AddToggle("ItemDistance", { Title = "Show distance", Default = Settings.ItemDistance })
    :OnChanged(function() Settings.ItemDistance = Fluent.Options.ItemDistance.Value end)

Tabs.Items:AddSlider("ItemMaxDist", {
    Title = "Max distance",
    Default = Settings.ItemMaxDist, Min = 100, Max = 5000, Rounding = 0,
    Callback = function(v) Settings.ItemMaxDist = v end,
})

Tabs.Colors:AddToggle("TeamColors", { Title = "Use team colors", Default = Settings.TeamColors })
    :OnChanged(function() Settings.TeamColors = Fluent.Options.TeamColors.Value end)

Tabs.Colors:AddParagraph({
    Title = "Static colors",
    Content = "Used only when 'Use team colors' is OFF.",
})

local EnemyCP = Tabs.Colors:AddColorpicker("EnemyColor", { Title = "Enemy color", Default = Settings.EnemyColor })
EnemyCP:OnChanged(function() Settings.EnemyColor = EnemyCP.Value end)

local AllyCP = Tabs.Colors:AddColorpicker("AllyColor", { Title = "Ally color", Default = Settings.AllyColor })
AllyCP:OnChanged(function() Settings.AllyColor = AllyCP.Value end)

Fluent:Notify({ Title = "Team ESP", Content = "Loaded. Press RightCtrl to toggle UI.", Duration = 5 })

-- Cleanup (on UI destroy or re-execute)
local function cleanup()
    pcall(function() renderConn:Disconnect() end)
    pcall(function() aimConn:Disconnect() end)
    pcall(function() playerConn:Disconnect() end)
    pcall(function() itemConn:Disconnect() end)
    pcall(function() fovCircle:Remove() end)
    pcall(destroyMobileButton)
    pcall(clearItemDraws)
    pcall(function() Minimizer:Destroy() end)
    pcall(function() applyFullbright(false) end)
    pcall(function() setNoclip(false) end)
    Settings.SpeedEnabled = false
    pcall(function() enableSpeed(false) end)
    for p in pairs(ESP) do destroyESP(p) end
    pcall(function() Window:Destroy() end)
    _G.__TeamESP_Cleanup = nil
end
_G.__TeamESP_Cleanup = cleanup
Window.Root.Destroying:Once(cleanup)

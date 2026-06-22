-- // t.me/arceusxcommunity <3
if getgenv().SPLATTER_ESP then getgenv().SPLATTER_ESP.stop() end

local Players = game:GetService("Players")
local RunS    = game:GetService("RunService")
local LP      = Players.LocalPlayer
local Cam     = workspace.CurrentCamera

local CFG = {
    Enabled    = true,
    ShowBox    = true,
    ShowName   = true,
    ShowDist   = true,
    ShowTracer = true,
    Hiders     = true,
    Seekers    = true,
    MaxDist    = 2000,
    HiderColor  = Color3.fromRGB(60, 255, 90),
    SeekerColor = Color3.fromRGB(255, 60, 60),
}

local objs = {}

local function newText(size)
    local t = Drawing.new("Text")
    t.Size = size or 13; t.Center = true; t.Outline = true
    t.Font = 2; t.Visible = false
    return t
end
local function ensure(p)
    if objs[p] then return objs[p] end
    local box = Drawing.new("Square"); box.Thickness = 1; box.Filled = false; box.Visible = false
    local tr  = Drawing.new("Line");   tr.Thickness = 1; tr.Visible = false
    objs[p] = { box = box, name = newText(13), dist = newText(12), tracer = tr }
    return objs[p]
end
local function clear(p)
    local o = objs[p]; if not o then return end
    for _,d in pairs(o) do pcall(function() d:Remove() end) end
    objs[p] = nil
end
local function hideAll(o) o.box.Visible=false o.name.Visible=false o.dist.Visible=false o.tracer.Visible=false end

local function roleColor(p)
    if p == LP then return nil end
    if p:GetAttribute("Eliminated") or p:GetAttribute("DeadThisRound") then return nil end
    local role = p:GetAttribute("Role")
    if role == "hider"  and CFG.Hiders  then return CFG.HiderColor  end
    if role == "seeker" and CFG.Seekers then return CFG.SeekerColor end
    return nil
end

local conn = RunS.RenderStepped:Connect(function()
    for _,p in ipairs(Players:GetPlayers()) do
        local o = ensure(p)
        local col = CFG.Enabled and roleColor(p) or nil
        local char = p.Character
        local root = char and (char:FindFirstChild("VisibleBody") or char:FindFirstChild("HumanoidRootPart"))
        if not col or not root then hideAll(o) ; continue end

        local cf, sz = char:GetBoundingBox()
        local _, onScreen = Cam:WorldToViewportPoint(cf.Position)
        local dist = (Cam.CFrame.Position - cf.Position).Magnitude
        if not onScreen or dist > CFG.MaxDist then hideAll(o) ; continue end

        local minX,minY,maxX,maxY = math.huge,math.huge,-math.huge,-math.huge
        local hx,hz   = sz.X/2*0.7, sz.Z/2*0.7
        local yTop,yBot = sz.Y/2*0.6, sz.Y/2*0.82
        for x=-1,1,2 do for _,y in ipairs({yTop,-yBot}) do for z=-1,1,2 do
            local corner = (cf * CFrame.new(x*hx, y, z*hz)).Position
            local sp = Cam:WorldToViewportPoint(corner)
            minX=math.min(minX,sp.X); minY=math.min(minY,sp.Y)
            maxX=math.max(maxX,sp.X); maxY=math.max(maxY,sp.Y)
        end end end
        local w, h = maxX-minX, maxY-minY

        o.box.Visible = CFG.ShowBox
        o.box.Color = col
        o.box.Position = Vector2.new(minX, minY)
        o.box.Size = Vector2.new(w, h)

        o.name.Visible = CFG.ShowName
        o.name.Color = col
        o.name.Text = p.DisplayName ~= p.Name and (p.DisplayName.." (@"..p.Name..")") or p.Name
        o.name.Position = Vector2.new(minX + w/2, minY - 16)

        o.dist.Visible = CFG.ShowDist
        o.dist.Color = col
        o.dist.Text = string.format("%d studs", math.floor(dist))
        o.dist.Position = Vector2.new(minX + w/2, maxY + 2)

        o.tracer.Visible = CFG.ShowTracer
        o.tracer.Color = col
        o.tracer.From = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y)
        o.tracer.To   = Vector2.new(minX + w/2, maxY)
    end
end)

local pr = Players.PlayerRemoving:Connect(clear)

local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("SPLATTER [ESP]")

w:Toggle("Enabled", CFG.Enabled, function(b) CFG.Enabled = b end)
w:Toggle("Hiders (green)",  CFG.Hiders,  function(b) CFG.Hiders  = b end)
w:Toggle("Seekers (red)",   CFG.Seekers, function(b) CFG.Seekers = b end)
w:Toggle("Box",      CFG.ShowBox,    function(b) CFG.ShowBox    = b end)
w:Toggle("Name",     CFG.ShowName,   function(b) CFG.ShowName   = b end)
w:Toggle("Distance", CFG.ShowDist,   function(b) CFG.ShowDist   = b end)
w:Toggle("Tracer",   CFG.ShowTracer, function(b) CFG.ShowTracer = b end)
w:Slider("Max distance", 50, 5000, CFG.MaxDist, function(v) CFG.MaxDist = v end)
w:Label("RightShift = toggle menu", Color3.fromRGB(127, 143, 166))
w:Button("Unload", function() getgenv().SPLATTER_ESP.stop() end)

lib:Keybind("RightShift")

getgenv().SPLATTER_ESP = {
    cfg = CFG,
    stop = function()
        conn:Disconnect(); pr:Disconnect()
        for p,_ in pairs(objs) do clear(p) end
        pcall(function() lib:Destroy() end)
        getgenv().SPLATTER_ESP = nil
    end
}

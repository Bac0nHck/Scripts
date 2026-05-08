-- https://robloxscripts.com/script/slime-rng-script
local Players=game:GetService("Players")
local UserInputSrv=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local LocalPlayer=Players.LocalPlayer
local isMobile=UserInputSrv.TouchEnabled

local C={
    Main=Color3.fromRGB(0,160,60),Secondary=Color3.fromRGB(0,200,80),
    Accent=Color3.fromRGB(100,255,140),Bg=Color3.fromRGB(12,18,12),
    Panel=Color3.fromRGB(18,28,18),BtnIdle=Color3.fromRGB(28,42,28),
    BtnOn=Color3.fromRGB(0,120,50),SliderBg=Color3.fromRGB(20,32,20),
    SliderFill=Color3.fromRGB(0,160,60),Knob=Color3.fromRGB(120,255,160),
    Text=Color3.fromRGB(210,240,210),TextDim=Color3.fromRGB(120,160,120),
}

_G.Binds={}
_G.InfJump=false
_G.SpeedBoost=false
_G.SpeedValue=16
_G.JumpBoost=false
_G.JumpPower=50
_G.NoClip=false
_G.AutoRoll=false
_G.AttackEnemies=false
_G.EquipBest=false
_G.AutoLoot=false
_G.AntiAfk=false

local function getBindName(b)
    if not b then return "–" end
    if typeof(b)=="EnumItem" then
        if b.EnumType==Enum.KeyCode then return b.Name
        elseif b==Enum.UserInputType.MouseButton2 then return "RMB"
        elseif b==Enum.UserInputType.MouseButton3 then return "MMB"
        end
    end return "–"
end

local function bindMatches(b,i)
    if not b then return false end
    if i.UserInputType==Enum.UserInputType.Keyboard then
        return typeof(b)=="EnumItem" and b.EnumType==Enum.KeyCode and i.KeyCode==b
    elseif i.UserInputType==Enum.UserInputType.MouseButton2 then
        return b==Enum.UserInputType.MouseButton2
    elseif i.UserInputType==Enum.UserInputType.MouseButton3 then
        return b==Enum.UserInputType.MouseButton3
    end return false
end

local function makeDraggable(de,tf)
    local d,ds,sp=false,nil,nil
    local h=Instance.new("TextButton")
    h.Size=UDim2.new(1,0,1,0);h.BackgroundTransparency=1;h.Text="";h.ZIndex=10;h.Parent=de
    h.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            d=true;ds=i.Position;sp=tf.Position
            i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then d=false end end)
        end
    end)
    UserInputSrv.InputChanged:Connect(function(i)
        if d and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then
            local delta=i.Position-ds
            tf.Position=UDim2.new(sp.X.Scale,sp.X.Offset+delta.X,sp.Y.Scale,sp.Y.Offset+delta.Y)
        end
    end)
end

local SG=Instance.new("ScreenGui")
SG.Name="slime_rng";SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;SG.Parent=game:GetService("CoreGui")

local pW,pH=340,270
local M=Instance.new("Frame")
M.Size=UDim2.new(0,pW,0,pH);M.Position=UDim2.new(0.5,-pW/2,0,-pH-50)
M.BackgroundColor3=C.Bg;M.BorderSizePixel=0;M.Active=true
M.Visible=false;M.ClipsDescendants=true;M.Parent=SG
Instance.new("UICorner",M).CornerRadius=UDim.new(0,12)
local ms=Instance.new("UIStroke",M);ms.Color=C.Main;ms.Thickness=2;ms.Transparency=0.4

local menuOpen = false
local function toggleMenu()
    menuOpen = not menuOpen
    if menuOpen then 
        M.Visible = true
        TweenService:Create(M, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, -pW/2, 0.5, -pH/2)}):Play()
    else
        local t = TweenService:Create(M, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Position = UDim2.new(0.5, -pW/2, 0, -pH-50)})
        t:Play()
        t.Completed:Connect(function() if not menuOpen then M.Visible = false end end)
    end
end

local b = Instance.new("TextButton")
local UICorner = Instance.new("UICorner")
b.Name = "FloatingButton"; b.Parent = SG; b.Text = "+"
b.Font = Enum.Font.SourceSansBold
b.Size = UDim2.new(0, 50, 0, 50); b.Position = UDim2.new(0.1, 0, 0.4, 0)
b.BackgroundColor3 = C.Main; b.BackgroundTransparency = 0.2
b.TextColor3 = Color3.fromRGB(255, 255, 255); b.TextSize = 40; b.TextWrapped = true
b.BorderSizePixel = 0; b.Active = true; b.Draggable = true
UICorner.CornerRadius = UDim.new(0, 10); UICorner.Parent = b

b.MouseButton1Click:Connect(function()
    toggleMenu()
end)

local TB=Instance.new("Frame")
TB.Size=UDim2.new(1,0,0,34);TB.BackgroundColor3=C.Panel;TB.BorderSizePixel=0;TB.Parent=M
Instance.new("UICorner",TB).CornerRadius=UDim.new(0,12)
local tc=Instance.new("Frame");tc.Size=UDim2.new(1,0,0,14)
tc.Position=UDim2.new(0,0,1,-14);tc.BackgroundColor3=C.Panel;tc.BorderSizePixel=0;tc.Parent=TB
local TL=Instance.new("TextLabel")
TL.Size=UDim2.new(1,-14,1,0);TL.Position=UDim2.new(0,14,0,0)
TL.BackgroundTransparency=1;TL.RichText=true
TL.Text="😎 <b>slime rng</b> <font color='#64FF8C'>v1.0</font>"
TL.TextColor3=C.Text;TL.Font=Enum.Font.GothamBold;TL.TextSize=13
TL.TextXAlignment=Enum.TextXAlignment.Left;TL.Parent=TB
makeDraggable(TB,M)

local Bd=Instance.new("Frame")
Bd.Size=UDim2.new(1,0,1,-34);Bd.Position=UDim2.new(0,0,0,34)
Bd.BackgroundTransparency=1;Bd.Parent=M

local Sd=Instance.new("Frame")
Sd.Size=UDim2.new(0,72,1,-14);Sd.Position=UDim2.new(0,6,0,7)
Sd.BackgroundColor3=C.Panel;Sd.BorderSizePixel=0;Sd.Parent=Bd
Instance.new("UICorner",Sd).CornerRadius=UDim.new(0,10)

local CA=Instance.new("Frame")
CA.Size=UDim2.new(1,-92,1,-14);CA.Position=UDim2.new(0,86,0,7)
CA.BackgroundTransparency=1;CA.Parent=Bd

local tabNames={"PLR","AUTO","CRD"}
local tabLabels={PLR="PLAYER",AUTO="AUTO",CRD="CREDITS"}
local tabFrames,tabBtns={},{}
local activeTab="PLR"

for _,tName in ipairs(tabNames) do
    local sf=Instance.new("ScrollingFrame")
    sf.Size=UDim2.new(1,0,1,0);sf.BackgroundTransparency=1
    sf.ScrollBarThickness=isMobile and 0 or 3;sf.ScrollBarImageColor3=C.Main
    sf.CanvasSize=UDim2.new(0,0,0,0);sf.Visible=(tName==activeTab)
    sf.Parent=CA;tabFrames[tName]=sf
end

local function showTab(name)
    activeTab=name
    for tN,f in pairs(tabFrames) do f.Visible=(tN==name) end
    for tN,b in pairs(tabBtns) do
        TweenService:Create(b,TweenInfo.new(0.25),
            {BackgroundColor3=(tN==name) and C.Main or C.BtnIdle}):Play()
    end
end

for i,tName in ipairs(tabNames) do
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(0.88,0,0,24);b.Position=UDim2.new(0.06,0,0,5+(i-1)*30)
    b.BackgroundColor3=(tName==activeTab) and C.Main or C.BtnIdle
    b.Text=tabLabels[tName];b.TextColor3=C.Text;b.Font=Enum.Font.GothamBold
    b.TextSize=10;b.BorderSizePixel=0;b.Parent=Sd
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,7)
    tabBtns[tName]=b;b.MouseButton1Click:Connect(function() showTab(tName) end)
end

local yTrackers={}
for _,t in ipairs(tabNames) do yTrackers[t]=0 end
local function nextY(t,h) local y=yTrackers[t];yTrackers[t]=y+h+4;tabFrames[t].CanvasSize=UDim2.new(0,0,0,yTrackers[t]+8);return y end

local function makeToggle(t,lb,pr)
    local y=nextY(t,28)
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,-8,0,28);btn.Position=UDim2.new(0,4,0,y)
    btn.BackgroundColor3=_G[pr] and C.BtnOn or C.BtnIdle
    btn.Text="  "..lb;btn.TextColor3=C.Text;btn.Font=Enum.Font.GothamMedium
    btn.TextSize=11;btn.TextXAlignment=Enum.TextXAlignment.Left
    btn.BorderSizePixel=0;btn.Parent=tabFrames[t]
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,7)
    local dot=Instance.new("Frame")
    dot.Size=UDim2.new(0,26,0,14);dot.Position=UDim2.new(1,-90,0.5,-7)
    dot.BackgroundColor3=_G[pr] and Color3.new(1,1,1) or Color3.fromRGB(80,80,80)
    dot.Parent=btn;Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
    local bb=Instance.new("TextButton")
    bb.Size=UDim2.new(0,52,0,20);bb.Position=UDim2.new(1,-58,0.5,-10)
    bb.BackgroundColor3=Color3.fromRGB(20,30,20);bb.Text="–"
    bb.TextColor3=C.TextDim;bb.Font=Enum.Font.GothamBold;bb.TextSize=10
    bb.BorderSizePixel=0;bb.Parent=btn
    Instance.new("UICorner",bb).CornerRadius=UDim.new(0,4)
    local w,fi=false,{}
    local function rf()
        TweenService:Create(btn,TweenInfo.new(0.2),{BackgroundColor3=_G[pr] and C.BtnOn or C.BtnIdle}):Play()
        TweenService:Create(dot,TweenInfo.new(0.2),{BackgroundColor3=_G[pr] and Color3.new(1,1,1) or Color3.fromRGB(80,80,80)}):Play()
    end
    btn.MouseButton1Click:Connect(function() _G[pr]=not _G[pr];rf() end)
    bb.MouseButton1Click:Connect(function() w=true;bb.Text="...";bb.TextColor3=C.Main end)
    UserInputSrv.InputBegan:Connect(function(i,gpe)
        if w then
            if i.UserInputType==Enum.UserInputType.Keyboard then w=false
                if i.KeyCode==Enum.KeyCode.Escape then _G.Binds[pr]=nil;bb.Text="–"
                else _G.Binds[pr]=i.KeyCode;bb.Text=i.KeyCode.Name end
                bb.TextColor3=C.TextDim
            elseif i.UserInputType==Enum.UserInputType.MouseButton2 then
                w=false;_G.Binds[pr]=Enum.UserInputType.MouseButton2;bb.Text="RMB";bb.TextColor3=C.TextDim
            elseif i.UserInputType==Enum.UserInputType.MouseButton3 then
                w=false;_G.Binds[pr]=Enum.UserInputType.MouseButton3;bb.Text="MMB";bb.TextColor3=C.TextDim
            end return
        end
        if not gpe and _G.Binds[pr] and bindMatches(_G.Binds[pr],i) and not fi[_G.Binds[pr]] then
            fi[_G.Binds[pr]]=true;_G[pr]=not _G[pr];rf()
        end
    end)
    UserInputSrv.InputEnded:Connect(function(i)
        if _G.Binds[pr] and bindMatches(_G.Binds[pr],i) then fi[_G.Binds[pr]]=nil end
    end)
end

local function makeSlider(t,lb,pr,mn,mx,st)
    local y=nextY(t,38)
    local f=Instance.new("Frame");f.Size=UDim2.new(1,-8,0,38)
    f.Position=UDim2.new(0,4,0,y);f.BackgroundTransparency=1;f.Parent=tabFrames[t]
    local l=Instance.new("TextLabel");l.Size=UDim2.new(1,0,0,16)
    l.BackgroundTransparency=1;l.RichText=true
    l.Text=lb..": <font color='#64FF8C'>".._G[pr].."</font>"
    l.TextColor3=C.Text;l.Font=Enum.Font.GothamMedium;l.TextSize=11
    l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=f
    local tr=Instance.new("Frame");tr.Size=UDim2.new(1,0,0,6)
    tr.Position=UDim2.new(0,0,0,22);tr.BackgroundColor3=C.SliderBg
    tr.BorderSizePixel=0;tr.Parent=f
    Instance.new("UICorner",tr).CornerRadius=UDim.new(0,4)
    local p=math.clamp((_G[pr]-mn)/(mx-mn),0,1)
    local fl=Instance.new("Frame");fl.Size=UDim2.new(p,0,1,0)
    fl.BackgroundColor3=C.SliderFill;fl.BorderSizePixel=0;fl.Parent=tr
    Instance.new("UICorner",fl).CornerRadius=UDim.new(0,4)
    local kn=Instance.new("Frame");kn.Size=UDim2.new(0,12,0,12)
    kn.Position=UDim2.new(p,-6,0.5,-6);kn.BackgroundColor3=C.Knob
    kn.BorderSizePixel=0;kn.ZIndex=3;kn.Parent=tr
    Instance.new("UICorner",kn).CornerRadius=UDim.new(0.5,0)
    local dg=false
    local function u(ix)
        local r=math.clamp((ix-tr.AbsolutePosition.X)/tr.AbsoluteSize.X,0,1)
        local v=mn+r*(mx-mn)
        if st>=1 then v=math.floor(v/st+0.5)*st
        else v=tonumber(string.format("%.2f",math.floor(v/st+0.5)*st)) end
        v=math.clamp(v,mn,mx);_G[pr]=v;local np=(v-mn)/(mx-mn)
        fl.Size=UDim2.new(np,0,1,0);kn.Position=UDim2.new(np,-6,0.5,-6)
        l.Text=lb..": <font color='#64FF8C'>"..v.."</font>"
    end
    tr.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dg=true;u(i.Position.X) end
    end)
    kn.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dg=true end
    end)
    UserInputSrv.InputChanged:Connect(function(i)
        if dg and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then u(i.Position.X) end
    end)
    UserInputSrv.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dg=false end
    end)
end

makeToggle("PLR","Infinite Jump","InfJump")
makeToggle("PLR","Speed Boost","SpeedBoost")
makeSlider("PLR","Walk Speed","SpeedValue",16,200,1)
makeToggle("PLR","Jump Boost","JumpBoost")
makeSlider("PLR","Jump Power","JumpPower",50,500,10)
makeToggle("PLR","Noclip","NoClip")

makeToggle("AUTO","Auto Roll","AutoRoll")
makeToggle("AUTO","Equip Best","EquipBest")
makeToggle("AUTO","Attack Enemies","AttackEnemies")
makeToggle("AUTO","Auto Loot","AutoLoot")
makeToggle("AUTO","Anti AFK","AntiAfk")

do
    local cf=tabFrames["CRD"]
    local cy=0

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-8,0,30);title.Position=UDim2.new(0,4,0,cy)
    title.BackgroundTransparency=1;title.RichText=true
    title.Text="<font color='#64FF8C'>script by</font> <b>veedsi</b>"
    title.TextColor3=C.Text;title.Font=Enum.Font.GothamBold;title.TextSize=14
    title.TextXAlignment=Enum.TextXAlignment.Center;title.Parent=cf
    cy=cy+36

    local yt=Instance.new("TextButton")
    yt.Size=UDim2.new(1,-8,0,26);yt.Position=UDim2.new(0,4,0,cy)
    yt.BackgroundColor3=C.BtnIdle;yt.BorderSizePixel=0
    yt.Text="  youtube.com/@veedsi  (click to copy)"
    yt.TextColor3=C.Accent;yt.Font=Enum.Font.GothamMedium;yt.TextSize=10
    yt.Parent=cf
    Instance.new("UICorner",yt).CornerRadius=UDim.new(0,6)
    yt.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard("https://www.youtube.com/@veedsi")
        elseif toclipboard then
            toclipboard("https://www.youtube.com/@veedsi")
        end
        yt.Text="  copied!"
        task.delay(1.5,function() yt.Text="  youtube.com/@veedsi  (click to copy)" end)
    end)

    cf.CanvasSize=UDim2.new(0,0,0,cy+40)
end

local menuOpen=false
function toggleMenu()
    menuOpen=not menuOpen
    if menuOpen then M.Visible=true
        TweenService:Create(M,TweenInfo.new(0.45,Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out),{Position=UDim2.new(0.5,-pW/2,0.5,-pH/2)}):Play()
    else
        local t=TweenService:Create(M,TweenInfo.new(0.4,Enum.EasingStyle.Quart,
            Enum.EasingDirection.In),{Position=UDim2.new(0.5,-pW/2,0,-pH-50)})
        t:Play();t.Completed:Connect(function() if not menuOpen then M.Visible=false end end)
    end
end

if isMobile then
    local ob=Instance.new("TextButton")
    ob.Size=UDim2.new(0,50,0,50);ob.Position=UDim2.new(0,10,0.4,0)
    ob.BackgroundColor3=C.Main;ob.Text="HUB";ob.TextColor3=C.Text
    ob.Font=Enum.Font.GothamBold;ob.TextSize=14;ob.Parent=SG
    Instance.new("UICorner",ob).CornerRadius=UDim.new(1,0)
    ob.MouseButton1Click:Connect(function() toggleMenu() end)
end

UserInputSrv.InputBegan:Connect(function(i,g)
    if not g and i.KeyCode==Enum.KeyCode.RightShift then toggleMenu() end
end)

local WF=Instance.new("Frame")
WF.Size=UDim2.new(0,160,0,52);WF.Position=UDim2.new(0,8,0,8)
WF.BackgroundColor3=C.Bg;WF.BackgroundTransparency=0.15
WF.BorderSizePixel=0;WF.Parent=SG
Instance.new("UICorner",WF).CornerRadius=UDim.new(0,6)
local ws=Instance.new("UIStroke",WF);ws.Color=C.Main;ws.Thickness=1

local WL=Instance.new("TextLabel")
WL.Size=UDim2.new(1,-10,1,-6);WL.Position=UDim2.new(0,6,0,3)
WL.BackgroundTransparency=1;WL.TextColor3=C.Text
WL.Font=Enum.Font.GothamBold;WL.TextSize=10;WL.RichText=true
WL.TextXAlignment=Enum.TextXAlignment.Left
WL.TextYAlignment=Enum.TextYAlignment.Top;WL.Parent=WF
makeDraggable(WF,WF)

local _fps,_fc,_lt=0,0,tick()

UserInputSrv.JumpRequest:Connect(function()
    if _G.InfJump and LocalPlayer.Character then
        local h=LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

RunService.RenderStepped:Connect(function()
    _fc=_fc+1
    if tick()-_lt>=1 then _fps=_fc;_fc=0;_lt=tick()
        local ok,pg=pcall(function() return math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()) end)
        local ping=ok and pg or 0
        WL.Text="<font color='#"..C.Main:ToHex().."'>slime rng</font>\nFPS: <font color='#"..C.Accent:ToHex().."'>".._fps.."</font> | PING: <font color='#"..C.Accent:ToHex().."'>"..ping.."ms</font>\n[<font color='#"..C.Secondary:ToHex().."'>R-SHIFT</font>]"
    end
    local c=LocalPlayer.Character;if not c then return end
    local h=c:FindFirstChildOfClass("Humanoid")
    local root=c:FindFirstChild("HumanoidRootPart")
    if not h or not root then return end
    if _G.SpeedBoost then h.WalkSpeed=_G.SpeedValue end
    if _G.JumpBoost then h.UseJumpPower=true;h.JumpPower=_G.JumpPower end
    if _G.NoClip then
        for _,p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=false end
        end
    end
end)

local function findGameplayFolder()
    for _,child in ipairs(workspace:GetChildren()) do
        if child.Name:match("^Gameplay%d+$") then
            return child
        end
    end
    return nil
end

local function findEnemiesFolder()
    local gp=findGameplayFolder()
    if not gp then return nil end
    return gp:FindFirstChild("Enemies")
end

local function getAliveEnemy()
    local folder=findEnemiesFolder()
    if not folder then return nil end
    for _,enemy in ipairs(folder:GetChildren()) do
        if enemy:IsA("Model") then
            local hrp=enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChildWhichIsA("BasePart")
            local hum=enemy:FindFirstChildOfClass("Humanoid")
            if hrp and (not hum or hum.Health>0) then
                return enemy
            end
        end
    end
    return nil
end

task.spawn(function()
    while true do
        if _G.AutoRoll then
            pcall(function()
                local remote=game:GetService("ReplicatedStorage")
                    :WaitForChild("Packages",2)
                    :WaitForChild("_Index",2)
                    :WaitForChild("leifstout_networker@0.3.1",2)
                    :WaitForChild("networker",2)
                    :WaitForChild("_remotes",2)
                    :WaitForChild("RollService",2)
                    :WaitForChild("RemoteFunction",2)
                remote:InvokeServer("requestRoll")
            end)
            task.wait(0.1)
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        if _G.AttackEnemies then
            local enemy=getAliveEnemy()
            if enemy then
                local char=LocalPlayer.Character
                local myRoot=char and char:FindFirstChild("HumanoidRootPart")
                if myRoot then
                    local targetPart=enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChildWhichIsA("BasePart")
                    if targetPart then
                        myRoot.CFrame=targetPart.CFrame*CFrame.new(0,0,3)
                    end
                end
            end
            task.wait(0.15)
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        if _G.EquipBest then
            pcall(function()
                game:GetService("ReplicatedStorage")
                    :WaitForChild("Packages",2)
                    :WaitForChild("_Index",2)
                    :WaitForChild("leifstout_networker@0.3.1",2)
                    :WaitForChild("networker",2)
                    :WaitForChild("_remotes",2)
                    :WaitForChild("InventoryService",2)
                    :WaitForChild("RemoteFunction",2)
                    :InvokeServer("requestEquipBest")
            end)
            task.wait(1)
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        if _G.AutoLoot then
            local char=LocalPlayer.Character
            local myRoot=char and char:FindFirstChild("HumanoidRootPart")
            if myRoot then
                local lootFolder=workspace:FindFirstChild("Loot")
                if lootFolder then
                    local loot=lootFolder:GetChildren()
                    if #loot>0 then
                        local target=loot[1]
                        local targetPart=target:FindFirstChild("HumanoidRootPart")
                            or target:FindFirstChildWhichIsA("BasePart")
                        if targetPart then
                            myRoot.CFrame=targetPart.CFrame
                        end
                    end
                end
            end
            task.wait(0.2)
        else
            task.wait(0.5)
        end
    end
end)

showTab("PLR")

local VU=game:GetService("VirtualUser")
LocalPlayer.Idled:Connect(function()
    if _G.AntiAfk then
        VU:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        task.wait(1)
        VU:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    end
end)

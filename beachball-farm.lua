local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("MM2 Summer")
local plr = game.Players.LocalPlayer
local character = plr.Character or plr.CharacterAdded:Wait()
local humPart = character:WaitForChild("HumanoidRootPart")
plr.CharacterAdded:Connect(function(char)
    character = char
    humPart = char:WaitForChild("HumanoidRootPart")
end)
local map
game.Workspace.DescendantAdded:Connect(function(m)
    if m:IsA("Model") and m:GetAttribute("MapID") then
        map = m
    end
end)
game.Workspace.DescendantRemoving:Connect(function(m)
    if m == map then
        map = nil
    end
end)
local tweenService = game:GetService("TweenService")
local function teleport(obj)
    if obj and obj:IsDescendantOf(workspace) and humPart and humPart:IsDescendantOf(workspace) then
        local distance = (humPart.Position - obj.Position).Magnitude
        local time = math.clamp(distance / 20, 0.2, 5)

        local tween = tweenService:Create(humPart, TweenInfo.new(time, Enum.EasingStyle.Linear), {CFrame = obj.CFrame * CFrame.new(0, -4, 0)})
        tween:Play()
        tween.Completed:Wait(.6)

        local touchInterest = obj:FindFirstChild("TouchInterest")
        if touchInterest then
            firetouchinterest(humPart, obj, 0)
            firetouchinterest(humPart, obj, 1)
        end
    end
end
getgenv().farm = false
w:Toggle("BeachBall Farm", false, function(bool)
    getgenv().farm = bool
    if not getgenv().farm then
        if workspace.Gravity ~= 196.2 then workspace.Gravity = 196.2 end
        return
    end
    while getgenv().farm do
        local container = map and map:FindFirstChild("CoinContainer")
        if (not map) or (not map.Parent) then
            for _,m in ipairs(game.Workspace:GetDescendants()) do
                if m:IsA("Model") and m:GetAttribute("MapID") then
                    map = m
                    break
                end
            end
        end
        if map then
            if container then
                if workspace.Gravity ~= 0 then workspace.Gravity = 0 end

                local anyCoin = false

                for _,coin in ipairs(container:GetChildren()) do
                    if not getgenv().farm then break end
                    if coin:IsA("Part") and coin.Name=="Coin_Server" and coin:GetAttribute("CoinID")=="BeachBall" then
                        local cv = coin:FindFirstChild("CoinVisual")
                        if cv and cv.Transparency~=1 then
                            anyCoin = true
                            if not humPart or not humPart.Parent then
                                humPart = character and character:FindFirstChild("HumanoidRootPart")
                                if not humPart then break end
                            end
                            for _,p in pairs(character:GetChildren()) do
                                if p:IsA("BasePart") and p.CanCollide then p.CanCollide=false end
                            end
                            teleport(coin)
                        end
                    end
                end

                if not anyCoin then
                    if workspace.Gravity ~= 196.2 then workspace.Gravity = 196.2 end
                    humPart.CFrame = CFrame.new(93, 140, 61)
                end
            end
        else
            if workspace.Gravity ~= 196.2 then workspace.Gravity = 196.2 end
            humPart.CFrame = CFrame.new(93, 140, 61)
        end
        task.wait(1)
    end
end)
local GC = getconnections or get_signal_cons
w:Button("Anti AFK", function()
    if GC then
        for _,v in pairs(GC(plr.Idled)) do
            if v.Disable then v:Disable() elseif v.Disconnect then v:Disconnect() end
        end
    else
        local vu = cloneref(game:GetService("VirtualUser"))
        plr.Idled:Connect(function()
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
    end
end)
w:Label("~ t.me/arceusxscripts", Color3.fromRGB(127, 143, 166))

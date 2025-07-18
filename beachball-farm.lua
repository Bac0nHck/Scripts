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
    if m:IsA("Model") and m.Name == "CoinContainer" then
        map = m
    end
end)
getgenv().farm = false
w:Toggle("BeachBall Farm", false, function(bool)
    getgenv().farm = bool
    while getgenv().farm do
        if (not map) or (not map.Parent) then
            for _,m in ipairs(game.Workspace:GetDescendants()) do
                if m:IsA("Model") and m.Name == "CoinContainer" then
                    map = m
                    break
                end
            end
        end
        if map and map.Parent then
            for _,coin in ipairs(map:GetChildren()) do
                if not getgenv().farm then break end
                if coin:IsA("Part") and coin.Name=="Coin_Server" and coin:GetAttribute("CoinID")=="BeachBall" then
                    local cv = coin:FindFirstChild("CoinVisual")
                    if cv and cv.Transparency~=1 then
                        if not humPart or not humPart.Parent then
                            humPart = character and character:FindFirstChild("HumanoidRootPart")
                            if not humPart then break end
                        end
                        for _,p in pairs(character:GetChildren()) do
                            if p:IsA("BasePart") and p.CanCollide then p.CanCollide=false end
                        end
                        humPart.CFrame = coin.CFrame * CFrame.new(0,6,0)
                        task.wait(2.5)
                    end
                end
            end
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

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()

local Window = Fluent:CreateWindow({
    Title = "The Button",
    SubTitle = "by baconhackoff",
    Search = true, 
    Icon = "home", 
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true, 
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.V
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "command" }),
    Esp = Window:AddTab({ Title = "ESP", Icon = "annoyed" }),
    Misc = Window:AddTab({ Title = "Misc", Icon = "stretch-horizontal" })
}

local Minimizer = Fluent:CreateMinimizer({
    Icon = "minimize-2",
    Size = UDim2.fromOffset(44, 44),
    Position = UDim2.new(0, 320, 0, 24),
    Acrylic = true,
    Corner = 10,
    Transparency = 1,
    Draggable = true,
    Visible = true 
})

local Options = Fluent.Options

local players = game:GetService("Players")
local RunService = game:GetService("RunService")

local plr = players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hum = char and char:FindFirstChildWhichIsA("Humanoid")

-- // Item ESP
local function clearESP()
    for _, item in pairs(workspace:GetDescendants()) do
        if item.Name == "ESP_Folder" then
            item:Destroy()
        end
    end
end

local function createESP(obj)
    local toolType = obj:GetAttribute("ToolType")

    if toolType and obj then
        local folder = obj:FindFirstChild("ESP_Folder")
        if not folder then
            folder = Instance.new("Folder")
            folder.Name = "ESP_Folder"
            folder.Parent = obj

            local bgui = Instance.new("BillboardGui")
            bgui.Name = "NameESP"
            bgui.Size = UDim2.new(0, 200, 0, 50)
            bgui.StudsOffset = Vector3.new(0, 3, 0)
            bgui.Enabled = true
            bgui.AlwaysOnTop = true
            bgui.Parent = folder
            bgui.Adornee = obj
            
            local text = Instance.new("TextLabel")
            text.Size = UDim2.new(1, 0, 1, 0)
            text.BackgroundTransparency = 1
            text.TextColor3 = Color3.fromRGB(255, 0, 0)
            text.TextStrokeTransparency = 0
            text.Text = obj.Name .. " : " .. tostring(toolType)
            text.Parent = bgui
            
            local highlight = Instance.new("Highlight")
            highlight.Name = "ToolHighlight"
            highlight.FillColor = Color3.fromRGB(255, 0, 0)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.OutlineTransparency = 1
            highlight.Parent = folder
            highlight.Adornee = obj
            highlight.FillTransparency = 0.7
        end
    end
end

-- // Players ESP
local function createPlayerESP(player)
    local folder = player.Character and player.Character:FindFirstChild("PlayerESP_Folder")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "PlayerESP_Folder"
        folder.Parent = player.Character

        local bgui = Instance.new("BillboardGui")
        bgui.Name = "NameESP"
        bgui.Size = UDim2.new(0, 200, 0, 50)
        bgui.StudsOffset = Vector3.new(0, 3, 0)
        bgui.Enabled = true
        bgui.AlwaysOnTop = true
        bgui.Parent = folder
        bgui.Adornee = player.Character
        
        local text = Instance.new("TextLabel")
        text.Size = UDim2.new(1, 0, 1, 0)
        text.BackgroundTransparency = 1
        text.TextColor3 = Color3.fromRGB(0, 255, 0)
        text.TextStrokeTransparency = 0
        text.Text = player.Name .. " : " .. tostring(math.floor(player.Character:FindFirstChildWhichIsA("Humanoid").Health))
        text.Parent = bgui
        
        local highlight = Instance.new("Highlight")
        highlight.Name = "PlayerHighlight"
        highlight.FillColor = Color3.fromRGB(0, 255, 0)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        highlight.FillTransparency = 0.7
        highlight.OutlineTransparency = 1
        highlight.Parent = folder
        highlight.Adornee = player.Character
    end
end

local function clearPlayerESP()
    for _, esp in pairs(workspace:GetDescendants()) do
        if esp.Name == "PlayerESP_Folder" then
            esp:Destroy()
        end
    end
end

-- // Get Items
local lastPos
local function getItems()
    lastPos = char:FindFirstChildWhichIsA("Humanoid").RootPart.CFrame
    for _, item in pairs(game:GetService("Workspace"):GetChildren()) do
        if item:GetAttribute("ToolType") then
            for _, trigger in pairs(item:GetDescendants()) do
                if trigger:IsA("ProximityPrompt") and trigger.Name == "DropPrompt" then
                    char:FindFirstChildWhichIsA("Humanoid").RootPart.CFrame = trigger.Parent.CFrame + Vector3.new(0, 3, 0)
                    task.wait(.5)
                    fireproximityprompt(trigger, trigger.MaxActivationDistance)
                    task.wait(.5)
                end
            end
        end
    end
    char:FindFirstChildWhichIsA("Humanoid").RootPart.CFrame = lastPos
end

do
    local labels = {"More scripts:", "Made by:", "Join the Telegram for more!", "I'm here:"}
    Tabs.Main:AddParagraph({
        Icon = "send",
        Title = labels[math.random(1, #labels)],
        Content = "Telegram: " .. game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
    })

    -- // Main Toggles
    local SpeedBoost = Tabs.Main:AddToggle("SpeedBoost", {Title = "Speed Boost", Default = false })
    local Noclip = Tabs.Main:AddToggle("Noclip", {Title = "Noclip", Default = false })
    local RmvFallDamage = Tabs.Main:AddToggle("RmvFallDamage", {Title = "Remove FallDamage", Default = false })
    local ItemAura = Tabs.Main:AddToggle("ItemAura", {Title = "Item Aura", Default = false })
    local InstantItem = Tabs.Main:AddToggle("InstantItem", {Title = "Instant Collect Items", Default = false })
    Tabs.Main:AddButton({
        Title = "Collect All Items",
        Description = "",
        Callback = function()
            getItems()
        end
    })

    -- // Misc Toggles
    local RmvHitCooldown = Tabs.Misc:AddToggle("RmvHitCooldown", {Title = "Remove Hit Cooldown", Default = false })
    local InfJump = Tabs.Misc:AddToggle("InfJump", {Title = "Inf Jump", Default = false })

    local infJump
    infJumpDebounce = false
    InfJump:OnChanged(function()
        if (Options.InfJump.Value) then
            if infJump then infJump:Disconnect() end
            infJumpDebounce = false
            infJump = game:GetService("UserInputService").JumpRequest:Connect(function()
                if not infJumpDebounce then
                    infJumpDebounce = true
                    plr.Character:FindFirstChildWhichIsA("Humanoid"):ChangeState(Enum.HumanoidStateType.Jumping)
                    wait()
                    infJumpDebounce = false
                end
            end)
        else
            if infJump then infJump:Disconnect() end
	        infJumpDebounce = false
        end
    end)
    -- // ESP Toggles
    local ItemESP = Tabs.Esp:AddToggle("ItemESP", {Title = "Items ESP", Default = false })
    local PlayerESP = Tabs.Esp:AddToggle("PlayerESP", {Title = "Players ESP", Default = false }) 

    Tabs.Main:AddButton({
        Title = "FullBright",
        Description = "",
        Callback = function()
            game:GetService("Lighting").Brightness = 2
            game:GetService("Lighting").ClockTime = 14
            game:GetService("Lighting").FogEnd = 100000
            game:GetService("Lighting").GlobalShadows = false
            game:GetService("Lighting").OutdoorAmbient = Color3.fromRGB(128, 128, 128)
        end
    })

    -- // Main Logic
    getgenv().zone = false
    Tabs.Main:AddButton({
        Title = "Safe Zone",
        Description = "Teleport to a safe area and back",
        Callback = function()
            local char = game.Players.LocalPlayer.Character
            local rootPart = char and char:FindFirstChild("HumanoidRootPart")
            
            if not rootPart then return end

            local safeZone = workspace:FindFirstChild("SafeZone")
            if not safeZone then
                safeZone = Instance.new("Part")
                safeZone.Name = "SafeZone"
                safeZone.Size = Vector3.new(50, 1, 50)
                safeZone.Transparency = 0.5
                safeZone.Color = Color3.fromRGB(0, 255, 0)
                safeZone.Anchored = true
                safeZone.CanCollide = true 
                safeZone.Position = Vector3.new(0, 500, 0)
                safeZone.Parent = workspace
            end

            if not getgenv().zone then
                lastPos = rootPart.CFrame
                rootPart.CFrame = safeZone.CFrame + Vector3.new(0, 5, 0)
                getgenv().zone = true
            else
                if lastPos then
                    rootPart.CFrame = lastPos
                end
                getgenv().zone = false
            end
        end
    })

    Tabs.Main:AddButton({
        Title = "Visible Landmines",
        Description = "",
        Callback = function()
            local mineField = game:GetService("Workspace"):FindFirstChild("Minefield")
            if mineField then
                for _, landmine in ipairs(mineField) do
                    landmine.Transparency = 0
                end
            end
        end
    })

    local playerESPUpdate
    PlayerESP:OnChanged(function()
        if (Options.PlayerESP.Value) then
            for _, player in pairs(players:GetPlayers()) do
                if player ~= plr and player.Character and player.Character:FindFirstChildWhichIsA("Humanoid") then
                    createPlayerESP(player)
                end
            end
            if not playerESPUpdate then
                playerESPUpdate = RunService.Heartbeat:Connect(function()
                    for _, player in pairs(players:GetPlayers()) do
                        if player ~= plr and player.Character then
                            local folder = player.Character:FindFirstChild("PlayerESP_Folder")
                            if folder then
                                local bgui = folder:FindFirstChild("NameESP")
                                if bgui then
                                    local text = bgui:FindFirstChild("TextLabel")
                                    if text then
                                        local humanoid = player.Character:FindFirstChildWhichIsA("Humanoid")
                                        if humanoid then
                                            text.Text = player.Name .. " : " .. tostring(math.floor(humanoid.Health))
                                            if player:GetAttribute("Ghost") and text.TextColor3 ~= Color3.fromRGB(0, 255, 255) then
                                                text.TextColor3 = Color3.fromRGB(0, 255, 255)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        else
            clearPlayerESP()
            if playerESPUpdate then
                playerESPUpdate:Disconnect()
                playerESPUpdate = nil
            end
        end
    end)

    RmvHitCooldown:OnChanged(function()
        hum:GetAttributeChangedSignal("HitCooldown"):Connect(function()
            if Options.RmvHitCooldown.Value then
                hum:SetAttribute("HitCooldown", false)
            end
        end)
    end)

    Tabs.Misc:AddButton({
        Title = "Inf Stamina",
        Description = "",
        Callback = function()
            -- Ye, that's everything..
            hum:SetAttribute("MaxStamina", math.huge)
            hum:SetAttribute("Stamina", math.huge)
        end
    })

    Tabs.Misc:AddButton({
        Title = "Inf Inventory Size",
        Description = "",
        Callback = function()
            hum:SetAttribute("InventorySize", math.huge)
        end
    })

    local Noclipping = nil
    Noclip:OnChanged(function()
        if (Options.Noclip.Value) then
            local function NoclipLoop()
                if plr.Character ~= nil then
                    for _, child in pairs(plr.Character:GetDescendants()) do
                        if child:IsA("BasePart") and child.CanCollide == true then
                            child.CanCollide = false
                        end
                    end
                end
            end
            Noclipping = RunService.Stepped:Connect(NoclipLoop)
        else
            if Noclipping then
                Noclipping:Disconnect()
            end
        end
    end)

    InstantItem:OnChanged(function()
        while Options.InstantItem.Value do
            getItems()
            task.wait(1)
        end
    end)

    ItemAura:OnChanged(function()
        if (Options.ItemAura.Value) then
            while Options.ItemAura.Value do
                for _, item in pairs(game:GetService("Workspace"):GetChildren()) do
                    if item:GetAttribute("ToolType") then
                        for _, trigger in pairs(item:GetDescendants()) do
                            if trigger:IsA("ProximityPrompt") and trigger.Name == "DropPrompt" then
                                fireproximityprompt(trigger, trigger.MaxActivationDistance)
                            end
                        end
                    end
                end
                task.wait(.3)
            end
        end
    end)

    SpeedBoost:OnChanged(function()
        if (Options.SpeedBoost.Value) then
            local delta = RunService.Heartbeat:Wait()
            tpwalk = RunService.Heartbeat:Connect(function(delta)
                local char = plr.Character or plr.CharacterAdded:Wait()
                local hum = char and char:FindFirstChildWhichIsA("Humanoid")
                if not (char and hum and hum.Parent) then
                    tpwalk:Disconnect()
                    return
                end

                if hum.MoveDirection.Magnitude > 0 then
                    char:TranslateBy(hum.MoveDirection * 2.3 * delta * 10)
                end
            end)
        else
            if tpwalk then
                tpwalk:Disconnect()
            end
        end
    end)

    RmvFallDamage:OnChanged(function()
        local falldamage = char:FindFirstChild("FallDamage")
        if falldamage then 
            falldamage.Enabled = not Options.RmvFallDamage.Value 
        end
    end)

    ItemESP:OnChanged(function()
        if (Options.ItemESP.Value) then
            for _, item in pairs(game:GetService("Workspace"):GetChildren()) do
                createESP(item)
            end
        else
            clearESP()
        end
    end)
end

-- // New Item ESP
game:GetService("Workspace").ChildAdded:Connect(function(obj)
    if Options.ItemESP.Value then
        createESP(obj)
    end
end)

Window:SelectTab(1)

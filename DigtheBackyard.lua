local lib = loadstring(game:HttpGet("https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/SaveManager.luau"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/InterfaceManager.luau"))()

local w = lib:CreateWindow{
    Title = "Dig the Backyard",
    SubTitle = "by t.me/arceusxscripts",
    TabWidth = 160,
    Size = UDim2.fromOffset(830, 525),
    Resize = true,
    MinSize = Vector2.new(470, 380),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
}

local Tabs = {
    Main = w:CreateTab{
        Title = "Main",
        Icon = "align-justify"
    },
    Player = w:CreateTab{
        Title = "Player",
        Icon = "user"
    },
    Teleports = w:CreateTab{
        Title = "Teleports",
        Icon = "phosphor-map-pin-bold"
    },
    Esp = w:CreateTab{
        Title = "ESP",
        Icon = "eye"
    },
    Settings = w:CreateTab{
        Title = "Settings",
        Icon = "settings"
    }
}

local Options = lib.Options

local players = game:GetService("Players")
local plr = players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local humPart = char:FindFirstChild("HumanoidRootPart")

local ores = workspace:FindFirstChild("SpawnedOres")
local invOres = plr:FindFirstChild("Ores")
local rooms = workspace:FindFirstChild("SpawnedRooms")
local mobs = workspace:FindFirstChild("Mobs")

local lastPos

-- // Main

Tabs.Main:CreateButton{
    Title = "Auto Pickup Lootbag",
    Description = "",
    Callback = function ()
        lastPos = humPart.CFrame
        for _, loot in pairs(rooms:GetDescendants()) do
            if loot:IsA("Model") and loot.Name == "LootBag" then
                local handle = loot:FindFirstChild("Handle")
                if handle then
                    local prox = handle:FindFirstChild("Attachment"):FindFirstChild("ProximityPrompt")
                    if prox then
                        humPart.CFrame = handle.CFrame
                        task.wait(0.25)
                        fireproximityprompt(prox, prox.MaxActivationDistance)
                        task.wait(0.75)
                    end
                end
            end
        end
        humPart.CFrame = lastPos
    end
}

Tabs.Main:CreateParagraph("Paragraph", {
    Title = "Ores",
    Content = ""
})

local SellOres = Tabs.Main:CreateToggle("SellOres", {Title = "Auto Sell Ores", Default = false })
Tabs.Main:CreateButton{
    Title = "Sell Ores",
    Description = "",
    Callback = function()
        game:GetService("ReplicatedStorage")
            :WaitForChild("Framework")
            :WaitForChild("Features")
            :WaitForChild("MiningSystem")
            :WaitForChild("MineUtil")
            :WaitForChild("RemoteEvent")
            :FireServer("SellOres")
    end
}

Tabs.Main:CreateParagraph("Paragraph", {
    Title = "Cake",
    Content = ""
})

local AutoEnergy = Tabs.Main:CreateToggle("AutoEnergy", {Title = "Auto Eat Cake", Default = false })

AutoEnergy:OnChanged(function()
    if Options.AutoEnergy.Value then
        task.spawn(function()
            while Options.AutoEnergy.Value do
                local energy = plr:GetAttribute("Energy")
                local maxEnergy = plr:GetAttribute("MaxEnergy")

                if energy <= 30 then
                    local cake = workspace:FindFirstChild("Cake") and workspace.Cake:FindFirstChild("Base")
                    local prox = cake and cake:FindFirstChildOfClass("ProximityPrompt")

                    if cake and prox then
                        lastPos = humPart.CFrame

                        humPart.CFrame = cake.CFrame * CFrame.new(0, -5, 0)

                        repeat
                            fireproximityprompt(prox, prox.MaxActivationDistance)
                            task.wait(0.1)
                            energy = plr:GetAttribute("Energy")
                        until energy >= maxEnergy or not Options.AutoEnergy.Value

                        humPart.CFrame = lastPos
                    end
                end
                
                task.wait(1)
            end
        end)
    end
end)

Tabs.Main:CreateButton{
    Title = "Eat Cake",
    Description = "",
    Callback = function()
        local energy = plr:GetAttribute("Energy")
        local maxEnergy = plr:GetAttribute("MaxEnergy")
        
        local cake = workspace:FindFirstChild("Cake") and workspace.Cake:FindFirstChild("Base")
        local prox = cake and cake:FindFirstChildOfClass("ProximityPrompt")

        if cake and prox then
            local lastPos = humPart.CFrame

            humPart.CFrame = cake.CFrame * CFrame.new(0, -5, 0)

            repeat
                fireproximityprompt(prox, prox.MaxActivationDistance)
                task.wait(0.1)
                energy = plr:GetAttribute("Energy")
                cake = workspace:FindFirstChild("Cake") and workspace.Cake:FindFirstChild("Base")
                prox = cake and cake:FindFirstChildOfClass("ProximityPrompt")
            until energy >= maxEnergy or not Options.AutoEnergy.Value

            humPart.CFrame = lastPos
        end
    end
}

SellOres:OnChanged(function()
    if Options.SellOres.Value then
        task.spawn(function()
            while Options.SellOres.Value do
                local maxInventory = invOres:GetAttribute("MaxInventory")
                local oreCount = 0
                
                for _, ore in pairs(invOres:GetChildren()) do
                    if ore:IsA("IntValue") then
                        oreCount += ore.Value
                    end
                end
                
                if oreCount == maxInventory then
                    game:GetService("ReplicatedStorage")
                        :WaitForChild("Framework")
                        :WaitForChild("Features")
                        :WaitForChild("MiningSystem")
                        :WaitForChild("MineUtil")
                        :WaitForChild("RemoteEvent")
                        :FireServer("SellOres")
                end
                
                task.wait(1)
            end
        end)
    end
end)

Tabs.Main:CreateParagraph("Paragraph", {
    Title = "Upgrade",
    Content = ""
})

local allUpgrade = Tabs.Main:CreateToggle("allUpgrade", {Title = "Auto All Upgrade", Default = false })
local shovelUpgrade = Tabs.Main:CreateToggle("shovelUpgrade", {Title = "Auto Shovel Upgrade", Default = false })
local backpackUpgrade = Tabs.Main:CreateToggle("backpackUpgrade", {Title = "Auto Backpack Upgrade", Default = false })
local energyUpgrade = Tabs.Main:CreateToggle("energyUpgrade", {Title = "Auto Energy Upgrade", Default = false })
local jetpackUpgrade = Tabs.Main:CreateToggle("jetpackUpgrade", {Title = "Auto Jetpack Upgrade", Default = false })

allUpgrade:OnChanged(function()
    Options.shovelUpgrade:SetValue(Options.allUpgrade.Value)
    Options.backpackUpgrade:SetValue(Options.allUpgrade.Value)
    Options.energyUpgrade:SetValue(Options.allUpgrade.Value)
    Options.jetpackUpgrade:SetValue(Options.allUpgrade.Value)
end)
shovelUpgrade:OnChanged(function ()
    task.spawn(function ()
        while Options.shovelUpgrade.Value do
            local args = {
                [1] = "BuyUpgrade",
                [2] = "Shovel"
            }
            game:GetService("ReplicatedStorage"):WaitForChild("Framework"):WaitForChild("Features"):WaitForChild("MiningSystem"):WaitForChild("UpgradeUtil"):WaitForChild("RemoteEvent"):FireServer(unpack(args))
            task.wait(1)
        end
    end)
end)

jetpackUpgrade:OnChanged(function ()
    task.spawn(function ()
        while Options.jetpackUpgrade.Value do
            local args = {
                [1] = "BuyUpgrade",
                [2] = "Jetpack"
            }
            game:GetService("ReplicatedStorage"):WaitForChild("Framework"):WaitForChild("Features"):WaitForChild("MiningSystem"):WaitForChild("UpgradeUtil"):WaitForChild("RemoteEvent"):FireServer(unpack(args))
            task.wait(1)
        end
    end)
end)

energyUpgrade:OnChanged(function ()
    task.spawn(function ()
        while Options.energyUpgrade.Value do
            local args = {
                [1] = "BuyUpgrade",
                [2] = "Energy"
            }
            game:GetService("ReplicatedStorage"):WaitForChild("Framework"):WaitForChild("Features"):WaitForChild("MiningSystem"):WaitForChild("UpgradeUtil"):WaitForChild("RemoteEvent"):FireServer(unpack(args))
            task.wait(1)
        end
    end)
end)

backpackUpgrade:OnChanged(function ()
    task.spawn(function ()
        while Options.backpackUpgrade.Value do
            local args = {
                [1] = "BuyUpgrade",
                [2] = "Backpack"
            }
            game:GetService("ReplicatedStorage"):WaitForChild("Framework"):WaitForChild("Features"):WaitForChild("MiningSystem"):WaitForChild("UpgradeUtil"):WaitForChild("RemoteEvent"):FireServer(unpack(args))
            task.wait(1)
        end
    end)
end)

-- // Player

Tabs.Player:CreateInput("walkspeed", {
    Title = "WalkSpeed",
    Default = char:WaitForChild("Humanoid").WalkSpeed,
    Placeholder = "",
    Numeric = true,
    Finished = false,
    Callback = function(Value)
        char:WaitForChild("Humanoid").WalkSpeed = Value
    end
})

Tabs.Player:CreateInput("fov", {
    Title = "FOV",
    Default = game:GetService("Workspace").Camera.FieldOfView,
    Placeholder = "",
    Numeric = true,
    Finished = false,
    Callback = function(Value)
        game:GetService("Workspace").Camera.FieldOfView = Value
    end
})

-- // Teleports

Tabs.Teleports:CreateButton{
    Title = "Teleport to House",
    Description = "",
    Callback = function()
        humPart.CFrame = CFrame.new(471, 24, -684)
    end
}

local createdButtons = {}

local function createRoomButton(room)
    if createdButtons[room.Name] then return end

    local part = room:FindFirstChildOfClass("Part")
    if part then
        Tabs.Teleports:CreateButton{
            Title = "Teleport to " .. room.Name,
            Description = "",
            Callback = function()
                humPart.CFrame = part.CFrame
            end
        }
        createdButtons[room.Name] = true
    end
end

for _, room in pairs(rooms:GetChildren()) do
    createRoomButton(room)
end

rooms.ChildAdded:Connect(function(newRoom)
    task.wait(0.5)
    createRoomButton(newRoom)
end)

-- // ESP
local OresESP = Tabs.Esp:CreateToggle("OresESP", {Title = "Ores ESP", Default = false })
local RoomsESP = Tabs.Esp:CreateToggle("RoomsESP", {Title = "Rooms ESP", Default = false })
local PlayersESP = Tabs.Esp:CreateToggle("PlayersESP", {Title = "Players ESP", Default = false })
local MobsESP = Tabs.Esp:CreateToggle("MobsESP", {Title = "Mobs ESP", Default = false })
local lootESP = Tabs.Esp:CreateToggle("lootESP", {Title = "LootBag ESP", Default = false })

lootESP:OnChanged(function ()
    if Options.lootESP.Value then
        for _, loot in pairs(rooms:GetDescendants()) do
            if loot:IsA("Model") and loot.Name == "LootBag" then
                local box = Instance.new("BoxHandleAdornment", loot)
                box.Name = "loot_ESP"
                box.Adornee = loot
                box.AlwaysOnTop = true
                box.Size = Vector3.new(5, 5, 5)
                box.ZIndex = 0
                box.Transparency = 0.3
                box.Color3 = Color3.new(1, 1, 0)
            end
        end
    else
        for _, e in pairs(rooms:GetDescendants()) do
            if e.Name == "loot_ESP" then
                e:Destroy()
            end
        end 
    end
end)

MobsESP:OnChanged(function ()
    if Options.MobsESP.Value then
        task.spawn(function()
            while Options.MobsESP.Value do
                for _, mob in pairs(mobs:GetChildren()) do
                    if mob:IsA("Model") and mob:FindFirstChild("Humanoid") then
                        local box = Instance.new("BoxHandleAdornment", mob)
                        box.Name = "ESP"
                        box.Adornee = mob
                        box.AlwaysOnTop = true
                        box.Size = Vector3.new(14, 15, 5)
                        box.ZIndex = 0
                        box.Transparency = 0.6
                        box.Color3 = Color3.new(1, 0, 0)
                    end
                end
                task.wait(1)
            end
        end)
    else
        for _, e in pairs(mobs:GetDescendants()) do
            if e.Name == "ESP" then
                e:Destroy()
            end
        end 
    end
end)

PlayersESP:OnChanged(function()
    if Options.PlayersESP.Value then
        task.spawn(function()
            while Options.PlayersESP.Value do
                for _, player in pairs(players:GetPlayers()) do
                    if player ~= plr then
                        local character = player.Character
                        if not character:FindFirstChild("ESP") then
                            local box = Instance.new("BoxHandleAdornment", character)
                            box.Name = "ESP"
                            box.Adornee = character
                            box.AlwaysOnTop = true
                            box.Size = Vector3.new(14, 15, 5)
                            box.ZIndex = 0
                            box.Transparency = 0.6
                            box.Color3 = Color3.new(0, 1, 0)
                        end
                    end
                end
                task.wait(1)
            end
        end)
    else
        for _, player in pairs(players:GetPlayers()) do
            local character = player.Character
            if character then
                local esp = character:FindFirstChild("ESP")
                if esp then esp:Destroy() end
            end
        end
    end
end)

RoomsESP:OnChanged(function()
    if Options.RoomsESP.Value then
        if rooms then
            for _, room in pairs(rooms:GetChildren()) do
                createRoomESP(room)
            end
        end
    else
        for _, e in pairs(rooms:GetDescendants()) do
            if e.Name == "ESP" then
                e:Destroy()
            end
        end 
    end
end)

function createRoomESP(room)
    if not room:FindFirstChild("ESP") then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ESP"
        billboard.Size = UDim2.new(0, 100, 0, 50)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.Adornee = room
        billboard.Parent = room

        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        textLabel.TextStrokeTransparency = 0
        textLabel.Font = Enum.Font.SourceSansBold
        textLabel.TextSize = 20
        textLabel.Text = room.Name
        textLabel.Parent = billboard
    end
end
rooms.ChildAdded:Connect(function(newRoom)
    task.wait(0.5)
    if Options.RoomsESP.Value then
        createRoomESP(newRoom)
    end
end)

OresESP:OnChanged(function()
    if Options.OresESP.Value then
        if ores then
            while Options.OresESP.Value do
                for _, ore in pairs(ores:GetChildren()) do
                    if not Options.OresESP.Value then break end
                    if ore then
                        local mPart = ore:FindFirstChildOfClass("MeshPart")
                        if mPart then
                            if not ore:FindFirstChild("ESP") then
                                local box = Instance.new("BoxHandleAdornment", ore)
                                box.Name = "ESP"
                                box.Adornee = ore
                                box.AlwaysOnTop = true
                                box.Size = Vector3.new(5,5,5)
                                box.ZIndex = 0
                                box.Transparency = .3
                                box.Color3 = mPart.Color
                            end
                        end
                    end
                end
                task.wait(1)
            end
        end
    else
        for _,e in pairs(ores:GetDescendants()) do
            if e.Name == "ESP" then
                e:Destroy()
            end
        end
    end
end)
SaveManager:SetLibrary(lib)
InterfaceManager:SetLibrary(lib)
InterfaceManager:SetFolder("DigtheBackyard")
SaveManager:SetFolder("DigtheBackyard/game")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
w:SelectTab(1)
SaveManager:LoadAutoloadConfig()

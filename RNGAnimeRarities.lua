local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()
local w = Fluent:CreateWindow({
    Title = "RNG Anime Rarities",
    SubTitle = "by baconhackoff",
    Search = true,
    Icon = "home",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftAlt,

    UserInfo = false,
    UserInfoTop = false,
    UserInfoTitle = game:GetService("Players").LocalPlayer.DisplayName,
    UserInfoSubtitle = "User",
    UserInfoSubtitleColor = Color3.fromRGB(71, 123, 255)
})
local Tabs = {
    Main = w:AddTab({ Title = "Main", Icon = "" })
}

local Options = Fluent.Options

-- Services
local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local humanoid = char:WaitForChild("Humanoid")
local hrp = char:WaitForChild("HumanoidRootPart")
local cam = workspace.CurrentCamera

local debrisFolder = workspace:FindFirstChild("Debris")
local pickup = debrisFolder and debrisFolder:FindFirstChild("Pickup_Debris_1")
local monsters = debrisFolder and debrisFolder:FindFirstChild("Monsters")

-- Anti AFK
task.spawn(function()
    while true do
        task.wait(20) 
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end
end)

-- ===== FARM LOGIC =====
getgenv().debrisFarm = false

local function collect(folder)
    if not folder then return end

    for _, item in ipairs(folder:GetChildren()) do
        if not getgenv().debrisFarm then return end

        local part =
            item:IsA("BasePart") and item
            or item:FindFirstChildWhichIsA("BasePart", true)

        local prompt = item:FindFirstChildOfClass("ProximityPrompt", true)

        if part and prompt then
            hrp.CFrame = part.CFrame + Vector3.new(0, 2, 0)
            task.wait(0.2)
            fireproximityprompt(prompt)
            task.wait(0.4)
        end
    end
end

local function attack(boss)
    if not boss or not boss.Parent then return end
    local hrpEnemie = boss:FindFirstChild("HumanoidRootPart")
    local humanoidEnemie = boss:FindFirstChild("Humanoid")
    if not hrpEnemie or not humanoidEnemie then return end

    local originalHumanoid = char:FindFirstChild("Humanoid")
    if not originalHumanoid then return end

    cam.CameraType = "Custom"
    cam.CameraSubject = humanoidEnemie

    repeat
        if not boss or not boss.Parent then break end

        hrp.CFrame = hrpEnemie.CFrame + Vector3.new(0,2,0)

        local args = { { Id = boss:GetAttribute("Id"), Action = "Mouse_Click" } }
        local event = game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("To_Server")
        event:FireServer(unpack(args))

        task.wait(0.1)
    until not boss or not boss.Parent or not getgenv().bossFarm

    cam.CameraSubject = originalHumanoid
end

local bossesName = {}
local bossesSet = {}

for _, boss in ipairs(monsters:GetChildren()) do
    local title = boss:GetAttribute("Title")
    if title and not bossesSet[title] then
        bossesSet[title] = true
        table.insert(bossesName, title)
    end
end

-- ===== UI =====
local debrisToggle = Tabs.Main:AddToggle("debrisFarm", {
    Title = "Trash Farm",
    Default = false
})
local debrisList = Tabs.Main:AddDropdown("debrisList", {
    Title = "Select Debris",
    Description = "",
    Values = {
        "Coins",
        "Devil_Fruits",
        "Potions"
    },
    Multi = true,
    Search = false,
    Default = {
        Coins = true
    }
})

local bossesToggle = Tabs.Main:AddToggle("bossesFarm", {
    Title = "Boss Farm",
    Default = false
})

local bossesList = Tabs.Main:AddDropdown("bossesList", {
    Title = "Select Boss",
    Values = bossesName,
    Multi = true,
    Search = true,
    Default = {}
})

-- ===== TOGGLE HANDLER =====
debrisToggle:OnChanged(function(value)
    getgenv().debrisFarm = value

    if value then
        task.spawn(function()
            while getgenv().debrisFarm do
                local selected = Options.debrisList.Value

                for itemName, enabled in pairs(selected) do
                    if enabled then
                        local folder = pickup and pickup:FindFirstChild(itemName)
                        if folder then
                            collect(folder)
                        end
                    end
                end

                task.wait(1)
            end
        end)
    end
end)

bossesToggle:OnChanged(function (value)
    getgenv().bossFarm = value

    if value then
        task.spawn(function ()
            while getgenv().bossFarm do
                local selectedBosses = Options.bossesList.Value
                if selectedBosses then
                    for _, boss in ipairs(monsters:GetChildren()) do
                        local title = boss:GetAttribute("Title")
                        if title and selectedBosses[title] then
                            attack(boss)
                        end
                    end
                end
                task.wait(0.5)
            end
        end)
    end
end)

local function addBossToDropdown(title)
    if not bossesSet[title] then
        bossesSet[title] = true
        table.insert(bossesName, title)

        bossesList:SetValues(bossesName)
    end
end
monsters.ChildAdded:Connect(function(child)
    local title = child:GetAttribute("Title")
    if title then
        addBossToDropdown(title)
    end
end)

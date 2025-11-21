--[[
getgenv().ESP = true

getgenv().settings = {
    playerTransparency = 0.7, -- 0-1
    droneTransparency = 0.3, -- 0-1
    maxDistance = 200, -- studs
}
--]]

local Players = game:GetService("Players")
local COREGUI = (gethui and gethui()) or game.CoreGui
local minDistace = (getgenv().settings.maxDistance) / 3
local ESPFolder = COREGUI:FindFirstChild("ESPFolder")
if not ESPFolder then
    ESPFolder = Instance.new("Folder")
    ESPFolder.Name = "ESPFolder"
    ESPFolder.Parent = COREGUI
end

local drones = nil
local teams = nil
for _, child in pairs(game:GetService("Workspace"):GetChildren()) do
    local lowerString = string.lower(child.Name)
    if string.find(lowerString, "team") then
        teams = child
        break
    end
end
for _, child in pairs(game:GetService("Workspace"):GetChildren()) do
    local lowerString = string.lower(child.Name)
    if string.find(lowerString, "drone") then
        drones = child
        break
    end
end

local attackers = teams and teams:FindFirstChild("attackers") or nil
local defenders = teams and teams:FindFirstChild("defenders") or nil

local function color3ToHex(c)
    local r = math.clamp(math.floor(c.R * 255), 0, 255)
    local g = math.clamp(math.floor(c.G * 255), 0, 255)
    local b = math.clamp(math.floor(c.B * 255), 0, 255)
    return string.format("#%02X%02X%02X", r, g, b)
end

local function droneESP(part, color)
    if not part or not part.Parent then return end
    
    local droneBox = Instance.new("BoxHandleAdornment")
    droneBox.Name = "Shahed_esp"
    droneBox.Adornee = part
    droneBox.AlwaysOnTop = true
    droneBox.ZIndex = 10
    droneBox.Size = part.Size * 1.05
    droneBox.Transparency = getgenv().settings.droneTransparency or 0.3
    droneBox.Color = BrickColor.new(color)
    droneBox.Parent = ESPFolder
end

local function createESP(part, color, name, distance)
    if not part or not part.Parent then return end

    local model = part:FindFirstAncestorWhichIsA("Model") or part.Parent
    local humanoid = nil
    if model then
        humanoid = model:FindFirstChildOfClass("Humanoid")
    end

    for _, partChild in pairs(model:GetDescendants()) do
        if partChild:IsA("BasePart") then
            local box = Instance.new("BoxHandleAdornment")
            box.Name = partChild.Name
            box.Adornee = partChild
            box.AlwaysOnTop = true
            box.ZIndex = 10
            box.Size = partChild.Size * 1.05
            box.Transparency = getgenv().settings.playerTransparency or 0.5
            box.Color = BrickColor.new(color)
            box.Parent = ESPFolder
        end
    end

    if distance >= getgenv().settings.maxDistance then
        return
    end

    local minD = minDistace
    local maxD = getgenv().settings.maxDistance
    local t = 0
    if distance < minD then
        t = 0
    else
        t = math.clamp((distance - minD) / (maxD - minD), 0, 1)
    end

    local textTransparency = t
    local strokeTransparency = math.clamp(0.25 + t * 0.75, 0, 1)

    local hpText = "HP: N/A"
    if humanoid then
        local current = math.floor(humanoid.Health or 0)
        local maxhp = math.floor(humanoid.MaxHealth or 0)
        if maxhp > 0 then
            hpText = string.format("HP: %d/%d", current, maxhp)
        else
            hpText = string.format("HP: %d", current)
        end
    end

    local hpColorHex = "#FFFFFF"
    if humanoid and humanoid.MaxHealth and humanoid.MaxHealth > 0 then
        local pct = (humanoid.Health / humanoid.MaxHealth)
        if pct > 0.66 then
            hpColorHex = "#00FF00"
        elseif pct > 0.33 then
            hpColorHex = "#FFFF00"
        else
            hpColorHex = "#FF0000"
        end
    end

    local nameColorHex = color3ToHex(color)
    local distanceText = math.floor(distance) .. " studs"

    local billboard = Instance.new("BillboardGui")
    billboard.Name = name .. "_Billboard"
    billboard.Adornee = part
    billboard.Size = UDim2.new(0, 220, 0, 64)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = ESPFolder

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.RichText = true

    local rich = ("<font color=\"%s\"><b>%s</b></font>\n%s\n<font color=\"%s\">%s</font>"):format(
        nameColorHex,
        name,
        distanceText,
        hpColorHex,
        hpText
    )

    textLabel.Text = rich
    textLabel.TextColor3 = color 
    textLabel.TextSize = 14
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextStrokeTransparency = strokeTransparency
    textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    textLabel.TextTransparency = textTransparency
    textLabel.Parent = billboard

    return billboard
end

function ClearESP()
    if not ESPFolder then return end
    for _, child in pairs(ESPFolder:GetChildren()) do
        child:Destroy()
    end
end

function UpdateESP()
    ClearESP()

    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    local playerRoot = character.HumanoidRootPart

    if attackers then
        for _, player in pairs(attackers:GetChildren()) do
            if player:IsA("Model") then
                if player.Name ~= Players.LocalPlayer.Name then
                    local targetPart = player:FindFirstChild("HumanoidRootPart") or player:FindFirstChild("Head") or player.PrimaryPart
                    if targetPart then
                        local distance = (playerRoot.Position - targetPart.Position).Magnitude
                        createESP(targetPart, Color3.fromRGB(255, 0, 0), "Name: " .. player.Name, distance)
                    end
                end
            end
        end
    end

    if defenders then
        for _, player in pairs(defenders:GetChildren()) do
            if player:IsA("Model") then
                if player.Name ~= Players.LocalPlayer.Name then
                    local targetPart = player:FindFirstChild("HumanoidRootPart") or player:FindFirstChild("Head") or player.PrimaryPart
                    if targetPart then
                        local distance = (playerRoot.Position - targetPart.Position).Magnitude
                        createESP(targetPart, Color3.fromRGB(0, 0, 255), "Name: " .. player.Name, distance)
                    end
                end
            end
        end
    end

    if drones then
        for _, droneModel in pairs(drones:GetChildren()) do
            if droneModel:IsA("Model") then
                local fpvPart = droneModel:FindFirstChild("FPV")
                if fpvPart then
                    local teamValue = fpvPart:FindFirstChild("Team")
                    if teamValue then
                        local color = teamValue.Value == "attackers" and Color3.fromRGB(255,100,0) or Color3.fromRGB(0,100,255)
                        for _, part in pairs(droneModel:GetDescendants()) do
                            if part:IsA("BasePart") then
                                droneESP(part, color)
                            end
                        end
                    end
                end
            end
        end
    end
end

task.spawn(function ()
    while true do
        task.wait(.5)
        if getgenv().ESP then
            UpdateESP()
        else
            ClearESP()
        end
    end
end)

--[[
getgenv().esp = true

getgenv().playerTransparency = 0.5
getgenv().droneTransparency = 0.3
getgenv().droneScale = 9
]]

local Players = game:GetService("Players")
local COREGUI = gethui()

local teams = workspace:FindFirstChild("teams__")
local dronesFolder = workspace:FindFirstChild("drones")
if not teams then return end

local function createESP(target, teamName)
    if not target then return end
    if target.Name == Players.LocalPlayer.Name then return end
    if COREGUI:FindFirstChild(target.Name.."_ESP") then return end

    local ESPholder = Instance.new("Folder")
    ESPholder.Name = target.Name.."_ESP"
    ESPholder.Parent = COREGUI

    local color
    local transparency = playerTransparency
    local scale = 1
    local t = string.lower(teamName)
    if t == "attackers" then
        color = BrickColor.new("Bright red")
    elseif t == "defenders" then
        color = BrickColor.new("Bright blue")
    elseif t == "drones" then
        color = BrickColor.new("Bright green")
        transparency = droneTransparency
        scale = droneScale
    else
        color = BrickColor.new("White")
    end

    for _, part in pairs(target:GetChildren()) do
        if part:IsA("BasePart") then
            local box = Instance.new("BoxHandleAdornment")
            box.Name = part.Name
            box.Adornee = part
            box.AlwaysOnTop = true
            box.ZIndex = 10
            box.Size = part.Size * scale
            box.Transparency = transparency
            box.Color = color
            box.Parent = ESPholder
        end
    end

    if target:FindFirstChild("Head") then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = target.Name.."_Billboard"
        billboard.Adornee = target.Head
        billboard.Size = UDim2.new(0, 0, 0, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = ESPholder
    end
end

local function removeESP(target)
    if not target then return end
    local esp = COREGUI:FindFirstChild(target.Name.."_ESP")
    if esp then esp:Destroy() end
end

-----------------------------
local function refreshESP()
    for _, team in pairs(teams:GetChildren()) do
        for _, child in pairs(team:GetChildren()) do
            if getgenv().esp then
                createESP(child, team.Name)
            else
                removeESP(child)
            end
        end
    end

    if dronesFolder then
        for _, drone in pairs(dronesFolder:GetChildren()) do
            if getgenv().esp then
                createESP(drone, "drones")
            else
                removeESP(drone)
            end
        end
    end
end
-----------------------------
for _, team in pairs(teams:GetChildren()) do
    team.ChildAdded:Connect(function(child)
        if getgenv().esp then
            createESP(child, team.Name)
        end
    end)
    team.ChildRemoved:Connect(removeESP)
end

if dronesFolder then
    dronesFolder.ChildAdded:Connect(function(child)
        if getgenv().esp then
            createESP(child, "drones")
        end
    end)
    dronesFolder.ChildRemoved:Connect(removeESP)
end

refreshESP()

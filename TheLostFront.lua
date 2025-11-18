-- getgenv().esp = true

local teams = workspace:FindFirstChild("teams__")
local dronesFolder = workspace:FindFirstChild("drones")
if not teams then return end

local function createHighlight(target, teamName)
    if not target or target:FindFirstChild("ESP") then return end

    local h = Instance.new("Highlight")
    h.Name = "ESP"

    local t = string.lower(teamName)

    if t == "attackers" then
        h.FillColor = Color3.new(1, 0, 0)
        h.OutlineColor = Color3.new(0.4, 0, 0)
        h.OutlineTransparency = 0.5
    elseif t == "defenders" then
        h.FillColor = Color3.new(0, 0, 1)
        h.OutlineColor = Color3.new(0, 0, 0.4)
        h.OutlineTransparency = 0.5
    elseif t == "drones" then
        h.FillColor = Color3.new(0, 1, 0)
        h.OutlineColor = Color3.new(0, 0.4, 0)
    end

    h.FillTransparency = 0.3
    h.OutlineTransparency = 0.5
    h.Adornee = target
    h.Parent = target
end

local function removeHighlight(target)
    if not target then return end
    local esp = target:FindFirstChild("ESP")
    if esp then esp:Destroy() end
end

-----------------------------
local function a()
    for _, team in pairs(teams:GetChildren()) do
        for _, child in pairs(team:GetChildren()) do
            if getgenv().esp then
                createHighlight(child, team.Name)
            else
                removeHighlight(child)
            end
        end
    end
    if dronesFolder then
        for _, drone in pairs(dronesFolder:GetChildren()) do
            if getgenv().esp then
                createHighlight(drone, "drones")
            else
                removeHighlight(drone)
            end
        end
    end
end
-----------------------------
for _, team in pairs(teams:GetChildren()) do
    team.ChildAdded:Connect(function(child)
        if getgenv().esp then
            createHighlight(child, team.Name)
        end
    end)
    team.ChildRemoved:Connect(removeHighlight)
end

if dronesFolder then
    dronesFolder.ChildAdded:Connect(function(child)
        if getgenv().esp then
            createHighlight(child, "drones")
        end
    end)
    dronesFolder.ChildRemoved:Connect(removeHighlight)
end

a()

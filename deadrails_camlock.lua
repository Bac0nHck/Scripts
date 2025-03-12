-- https://www.tiktok.com/@giobolqvi?_t=ZM-8ucgNOQ2Qx3&_r=1

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local cam = Workspace.CurrentCamera
local camlockEnabled = false
local camlockConnection
local targetESP = nil
local hitboxToggleEnabled = false

local defaultHRPValues = {}

local trackedNPCs = {}

for _, obj in ipairs(Workspace:GetDescendants()) do
    if obj:IsA("Model") 
       and obj:FindFirstChild("HumanoidRootPart") 
       and obj:FindFirstChild("Humanoid") 
       and not Players:GetPlayerFromCharacter(obj) then

        local hrp = obj.HumanoidRootPart
        local humanoid = obj.Humanoid

        if defaultHRPValues[hrp] == nil then
            defaultHRPValues[hrp] = {
                Size = hrp.Size,
                Transparency = hrp.Transparency,
                CanCollide = hrp.CanCollide
            }
        end

        humanoid.Died:Connect(function()
            task.wait(0.2)
            local defaults = defaultHRPValues[hrp]
            if defaults then
                hrp.Size = defaults.Size
                hrp.Transparency = defaults.Transparency
                hrp.CanCollide = defaults.CanCollide
            end
        end)
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NPCCamlockGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = game:GetService("CoreGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 200, 0, 120)
mainFrame.Position = UDim2.new(0.85, -100, 0.75, -60)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BackgroundTransparency = 0.3
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1/1.2
uiScale.Parent = mainFrame

local uicorner = Instance.new("UICorner")
uicorner.CornerRadius = UDim.new(0, 12)
uicorner.Parent = mainFrame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(1, -20, 0, 40)
toggleButton.Position = UDim2.new(0, 10, 0, 10)
toggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
toggleButton.BackgroundTransparency = 0.4
toggleButton.Text = "NPC Camlock: OFF"
toggleButton.TextColor3 = Color3.new(1, 1, 1)
toggleButton.Font = Enum.Font.Fantasy
toggleButton.TextSize = 22
toggleButton.Parent = mainFrame

local uicorner2 = Instance.new("UICorner")
uicorner2.CornerRadius = UDim.new(0, 12)
uicorner2.Parent = toggleButton

local toggleHitboxButton = Instance.new("TextButton")
toggleHitboxButton.Size = UDim2.new(1, -20, 0, 40)
toggleHitboxButton.Position = UDim2.new(0, 10, 0, 70)
toggleHitboxButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
toggleHitboxButton.BackgroundTransparency = 0.4
toggleHitboxButton.Text = "NPC Hitbox: Default"
toggleHitboxButton.TextColor3 = Color3.new(1, 1, 1)
toggleHitboxButton.Font = Enum.Font.Fantasy
toggleHitboxButton.TextSize = 22
toggleHitboxButton.Parent = mainFrame

local uicorner3 = Instance.new("UICorner")
uicorner3.CornerRadius = UDim.new(0, 12)
uicorner3.Parent = toggleHitboxButton

mainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
end)
mainFrame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    end
end)

local function createESP(target)
    if target and target.Parent then
        if targetESP then targetESP:Destroy() end
        targetESP = Instance.new("Highlight")
        targetESP.FillTransparency = 1
        targetESP.OutlineColor = Color3.fromRGB(255, 0, 0)
        targetESP.OutlineTransparency = 0
        targetESP.Parent = target.Parent
    end
end

local function removeESP()
    if targetESP then
        targetESP:Destroy()
        targetESP = nil
    end
end

local function hasClearLineOfSight(targetHead)
    local origin = cam.CFrame.Position
    local direction = (targetHead.Position - origin).unit * (targetHead.Position - origin).Magnitude
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {player.Character}
    
    local result = Workspace:Raycast(origin, direction, raycastParams)
    return result == nil or result.Instance:IsDescendantOf(targetHead.Parent)
end

local function getClosestNPCTarget()
    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return nil
    end

    local closestNPCHead = nil  
    local shortestDistance = math.huge  

    for npc, _ in pairs(trackedNPCs) do  
        if npc and npc.Parent then
            local humanoid = npc:FindFirstChild("Humanoid")
            local head = npc:FindFirstChild("Head")
            if humanoid and head then
                local distance = (head.Position - character.HumanoidRootPart.Position).Magnitude  
                if distance <= 330 
                   and humanoid.Health > 0 
                   and humanoid:GetState() ~= Enum.HumanoidStateType.Dead 
                   and distance < shortestDistance 
                   and hasClearLineOfSight(head) then  

                    shortestDistance = distance  
                    closestNPCHead = head  
                end  
            end
        else
            trackedNPCs[npc] = nil
        end
    end  

    return closestNPCHead
end

local targetHead = nil
local lastTargetUpdate = 0
local targetUpdateInterval = 0.1

local function startCamlock()
    camlockConnection = RunService.RenderStepped:Connect(function()
        local currentTime = tick()
        if currentTime - lastTargetUpdate >= targetUpdateInterval then
            targetHead = getClosestNPCTarget()
            lastTargetUpdate = currentTime
        end

        if targetHead then
            local distance = (targetHead.Position - cam.CFrame.Position).Magnitude
            if distance > 300 then
                removeESP()
            else
                local heightCompensation = math.clamp(distance * 0, 0.2, 1.8)
                local headPos = targetHead.Position + Vector3.new(0, targetHead.Size.Y / 2 - heightCompensation, 0)
                local camPos = cam.CFrame.Position  
                local direction = (headPos - camPos).unit  
                local newCF = CFrame.lookAt(camPos, camPos + direction)  
                cam.CFrame = newCF  
                createESP(targetHead)
            end  
        else  
            removeESP()  
        end  
    end)
end

local function stopCamlock()
    if camlockConnection then
        camlockConnection:Disconnect()
        camlockConnection = nil
    end
    removeESP()
end

toggleButton.MouseButton1Click:Connect(function()
    camlockEnabled = not camlockEnabled
    if camlockEnabled then
        toggleButton.Text = "NPC Camlock: ON"
        startCamlock()
    else
        toggleButton.Text = "NPC Camlock: OFF"
        stopCamlock()
    end
end)

local function updateNPCHitbox(npc)
    if npc:IsA("Model") and npc:FindFirstChild("Humanoid") and npc:FindFirstChild("HumanoidRootPart") then
        if Players:GetPlayerFromCharacter(npc) then
            return
        end
        if npc.Name == "Horse" then
            return
        end

        local humanoid = npc.Humanoid
        local hrp = npc.HumanoidRootPart

        if defaultHRPValues[hrp] == nil then
            defaultHRPValues[hrp] = {
                Size = hrp.Size,
                Transparency = hrp.Transparency,
                CanCollide = hrp.CanCollide
            }
        end

        if humanoid.Health <= 0 then
            local defaults = defaultHRPValues[hrp]
            if defaults then
                hrp.Size = defaults.Size
                hrp.Transparency = defaults.Transparency
                hrp.CanCollide = defaults.CanCollide
            end
            return
        end

        if hitboxToggleEnabled then
            hrp.Size = Vector3.new(10, 10, 10)
            hrp.Transparency = 0.85
            hrp.CanCollide = false
        else
            local defaults = defaultHRPValues[hrp]
            if defaults then
                hrp.Size = defaults.Size
                hrp.Transparency = defaults.Transparency
                hrp.CanCollide = defaults.CanCollide
            end
        end
    end
end

local function updateAllNPCsHitbox()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") 
           and obj:FindFirstChild("HumanoidRootPart") 
           and obj:FindFirstChild("Humanoid") 
           and not Players:GetPlayerFromCharacter(obj) then
            updateNPCHitbox(obj)
        end
    end
end

toggleHitboxButton.MouseButton1Click:Connect(function()
    hitboxToggleEnabled = not hitboxToggleEnabled
    if hitboxToggleEnabled then
        toggleHitboxButton.Text = "NPC Hitbox: ON"
    else
        toggleHitboxButton.Text = "NPC Hitbox: Default"
    end
    updateAllNPCsHitbox()
end)

Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") then
        local humanoid = obj:FindFirstChild("Humanoid") or obj:WaitForChild("Humanoid", 5)
        if humanoid then
            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:WaitForChild("HumanoidRootPart", 5)
            if hrp and not Players:GetPlayerFromCharacter(obj) then
                if defaultHRPValues[hrp] == nil then
                    defaultHRPValues[hrp] = {
                        Size = hrp.Size,
                        Transparency = hrp.Transparency,
                        CanCollide = hrp.CanCollide
                    }
                end

                humanoid.Died:Connect(function()
                    task.wait(0.2)
                    local defaults = defaultHRPValues[hrp]
                    if defaults then
                        hrp.Size = defaults.Size
                        hrp.Transparency = defaults.Transparency
                        hrp.CanCollide = defaults.CanCollide
                    end
                end)

                task.wait(0.5)
                updateNPCHitbox(obj)
            end
        end
    end
end)

local function addNPC(npc)
    if npc:IsA("Model") 
       and npc:FindFirstChild("Humanoid") 
       and npc:FindFirstChild("HumanoidRootPart") 
       and not Players:GetPlayerFromCharacter(npc)
       and npc.Name ~= "Horse" then
        trackedNPCs[npc] = true
    end
end

for _, obj in ipairs(Workspace:GetDescendants()) do
    if obj:IsA("Model") 
       and obj:FindFirstChild("Humanoid") 
       and obj:FindFirstChild("HumanoidRootPart") 
       and not Players:GetPlayerFromCharacter(obj)
       and obj.Name ~= "Horse" then
        addNPC(obj)
    end
end

Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") then
        task.wait(0.5)
        addNPC(obj)
    end
end)

Workspace.DescendantRemoving:Connect(function(obj)
    if trackedNPCs[obj] then
        trackedNPCs[obj] = nil
    end
end)

spawn(function()
    while task.wait(1) do
        for npc, _ in pairs(trackedNPCs) do
            if npc and npc.Parent then
                local humanoid = npc:FindFirstChild("Humanoid")
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if humanoid and hrp and humanoid.Health <= 0 then
                    local defaults = defaultHRPValues[hrp]
                    if defaults then
                        hrp.Size = defaults.Size
                        hrp.Transparency = defaults.Transparency
                        hrp.CanCollide = defaults.CanCollide
                    end
                end
            else
                trackedNPCs[npc] = nil
            end
        end
    end
end)

game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "code by GioBolqvi",
    Text = "on Roblox",
    Duration = 10
})

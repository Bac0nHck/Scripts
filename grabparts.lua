-- Modified thanks to: t.me/arceusxscripts
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

humanoid.Died:Connect(function()
    if heldModel then
        restoreModelCollisions()
        if bodyVelocity then
            bodyVelocity:Destroy()
            bodyVelocity = nil
        end
        heldModel = nil
    end
end)

-- Throw settings (default values)
local throwForce = 50
local throwUpForce = 10

-- GUI variables
local gui = nil
local frame = nil

-- Tool logic
local grabTool = Instance.new("Tool")
grabTool.Name = "Grab"
grabTool.RequiresHandle = false

local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Size = Vector3.new(0.5, 0.5, 0.5)
handle.Transparency = 1
handle.CanCollide = false
handle.Parent = grabTool

-- GUI creation function
local function createGUI()
    if gui then gui:Destroy() end
    
    gui = Instance.new("ScreenGui")
    gui.Name = "GrabToolGUI"
    gui.ResetOnSpawn = false
    gui.Parent = player.PlayerGui

    frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 120)
    frame.Position = UDim2.new(0, 10, 1, -130) -- Bottom left corner with padding
    frame.AnchorPoint = Vector2.new(0, 1)
    frame.BackgroundTransparency = 0.7
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    frame.Parent = gui

    local title = Instance.new("TextLabel")
    title.Text = "Throw Settings"
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Parent = frame

    -- Horizontal force slider
    local forceLabel = Instance.new("TextLabel")
    forceLabel.Text = "Throw Force: "..throwForce
    forceLabel.Size = UDim2.new(1, 0, 0, 20)
    forceLabel.Position = UDim2.new(0, 0, 0, 30)
    forceLabel.BackgroundTransparency = 1
    forceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    forceLabel.Parent = frame

    local forceSlider = Instance.new("TextBox")
    forceSlider.Size = UDim2.new(0.9, 0, 0, 20)
    forceSlider.Position = UDim2.new(0.05, 0, 0, 50)
    forceSlider.Text = tostring(throwForce)
    forceSlider.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    forceSlider.TextColor3 = Color3.fromRGB(255, 255, 255)
    forceSlider.Parent = frame

    -- Vertical force slider
    local upForceLabel = Instance.new("TextLabel")
    upForceLabel.Text = "Upward Force: "..throwUpForce
    upForceLabel.Size = UDim2.new(1, 0, 0, 20)
    upForceLabel.Position = UDim2.new(0, 0, 0, 70)
    upForceLabel.BackgroundTransparency = 1
    upForceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    upForceLabel.Parent = frame

    local upForceSlider = Instance.new("TextBox")
    upForceSlider.Size = UDim2.new(0.9, 0, 0, 20)
    upForceSlider.Position = UDim2.new(0.05, 0, 0, 90)
    upForceSlider.Text = tostring(throwUpForce)
    upForceSlider.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    upForceSlider.TextColor3 = Color3.fromRGB(255, 255, 255)
    upForceSlider.Parent = frame

    -- Value change handlers
    forceSlider.FocusLost:Connect(function(enterPressed)
        local newValue = tonumber(forceSlider.Text)
        if newValue and newValue >= 0 and newValue <= 500 then
            throwForce = newValue
            forceLabel.Text = "Throw Force: "..throwForce
        else
            forceSlider.Text = tostring(throwForce)
        end
    end)

    upForceSlider.FocusLost:Connect(function(enterPressed)
        local newValue = tonumber(upForceSlider.Text)
        if newValue and newValue >= 0 and newValue <= 100 then
            throwUpForce = newValue
            upForceLabel.Text = "Upward Force: "..throwUpForce
        else
            upForceSlider.Text = tostring(throwUpForce)
        end
    end)
end

-- Tool equip/unequip handlers
grabTool.Equipped:Connect(function()
    createGUI()
end)

grabTool.Unequipped:Connect(function()
    if gui then
        gui:Destroy()
        gui = nil
    end
end)

-- Add tool to inventory
grabTool.Parent = player.Backpack

-- Rest of the tool logic remains the same
local mouse = player:GetMouse()
local heldModel = nil
local originalCollisions = {}
local bodyVelocity = nil

local function disableModelCollisions(model)
    originalCollisions = {}
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            originalCollisions[part] = part.CanCollide
            part.CanCollide = false
        end
    end
end

local function restoreModelCollisions()
    for part, canCollide in pairs(originalCollisions) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end
    end
    originalCollisions = {}
end

local function pullItem(target)
    if heldModel then return end

    if target:IsA("Part") then
        local model = Instance.new("Model")
        target.Parent = model
        model.PrimaryPart = target
        model.Parent = workspace
        heldModel = model
    else
        heldModel = target:FindFirstAncestorOfClass("Model") or target
        if heldModel:IsA("Part") then
            local model = Instance.new("Model")
            target.Parent = model
            model.PrimaryPart = target
            model.Parent = workspace
            heldModel = model
        end
    end

    if not heldModel.PrimaryPart then
        local candidate = heldModel:FindFirstChildWhichIsA("BasePart")
        if candidate then
            heldModel.PrimaryPart = candidate
        else
            return
        end
    end

    disableModelCollisions(heldModel)

    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Velocity = Vector3.new(0, 0, 0)
    bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bodyVelocity.Parent = heldModel.PrimaryPart

    game:GetService("RunService").Heartbeat:Connect(function()
        if not heldModel or not bodyVelocity then return end
        if not heldModel.PrimaryPart or not grabTool:FindFirstChild("Handle") then
            if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
            heldModel = nil
            return
        end
    
        local handlePos = grabTool.Handle.Position
        local partPos = heldModel.PrimaryPart.Position
        local direction = (handlePos - partPos).Unit * 50
    
        bodyVelocity.Velocity = direction
    end)


end


local function throwItem()
    if not heldModel then return end

    local primaryPart = heldModel.PrimaryPart or heldModel:FindFirstChildWhichIsA("BasePart")
    if not primaryPart then return end

    restoreModelCollisions()

    if bodyVelocity then
        bodyVelocity:Destroy()
        bodyVelocity = nil
    end

    local camera = workspace.CurrentCamera
    local throwDirection = (mouse.Hit.Position - camera.CFrame.Position).Unit

    local throwVelocity = Instance.new("BodyVelocity")
    throwVelocity.Velocity = throwDirection * throwForce + Vector3.new(0, throwUpForce, 0)
    throwVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    throwVelocity.Parent = primaryPart

    game:GetService("Debris"):AddItem(throwVelocity, 0.5)

    heldModel = nil
end

grabTool.Activated:Connect(function()
    if not grabTool.Parent:IsA("Model") then return end
    
    if heldModel then
        throwItem()
        return
    end
    
    local target = mouse.Target
    if target and not target.Anchored and not target:IsDescendantOf(character) then
        pullItem(target)
    end
end)

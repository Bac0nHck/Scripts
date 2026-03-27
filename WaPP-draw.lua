-- // Main Script
loadstring(game:HttpGet("https://raw.githubusercontent.com/VP2H/pizzascript/refs/heads/main/script"))()
-- // Mobile Button
task.spawn(function()
    local gui = game:GetService("CoreGui"):WaitForChild("ExtinguisherGui", 999)
    local UserInputService = game:GetService("UserInputService")
    local s = Instance.new("ScreenGui")
    local b = Instance.new("TextButton")
    local UICorner = Instance.new("UICorner")
    s.Name = "MenuButton"
    s.Parent = game:GetService("CoreGui")
    s.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    b.Name = "ToggleButton"
    b.Parent = s
    b.Text = "+"
    b.Font = Enum.Font.SourceSans
    b.Size = UDim2.new(0, 50, 0, 50)
    b.Position = UDim2.new(0.1959, 0, 0.3771, 0)
    b.BackgroundColor3 = Color3.fromRGB(109, 109, 109)
    b.BackgroundTransparency = 0.4
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 34
    b.TextWrapped = true
    b.Active = true
    b.Draggable = true
    UICorner.CornerRadius = UDim.new(0, 5)
    UICorner.Parent = b
    b.MouseButton1Click:Connect(function()
        if gui then
            gui.Enabled = not gui.Enabled
        end
    end)
end)

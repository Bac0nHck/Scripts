--// from t.me/arceusxscripts to t.me/olegroblox1
--// https://www.roblox.com/games/7074772062/Speed-Draw

if getgenv().a then return end
pcall(function() getgenv().a = true end)

local gui = Instance.new("ScreenGui")
local frame = Instance.new("Frame")
local label = Instance.new("TextLabel")
local UITextSizeConstraint = Instance.new("UITextSizeConstraint")
local box = Instance.new("TextBox")
local UITextSizeConstraint_2 = Instance.new("UITextSizeConstraint")
local UICorner = Instance.new("UICorner")

gui.Name = "gui"
gui.Parent = game:GetService("CoreGui")
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

frame.Name = "frame"
frame.Parent = gui
frame.BackgroundColor3 = Color3.fromRGB(182, 182, 182)
frame.BackgroundTransparency = 0.3
frame.BorderSizePixel = 0
frame.Position = UDim2.new(0.07, 0, 0.44, 0)
frame.Size = UDim2.new(0.19, 0, 0.15, 0)
frame.Active = true
frame.Draggable = true

label.Name = "label"
label.Parent = frame
label.BackgroundTransparency = 0.45
label.Size = UDim2.new(1, 0, 0.28, 0)
label.Font = Enum.Font.SourceSansBold
label.Text = "HEX Changer | By: Bac0nH1ckOff"
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.TextWrapped = true

UITextSizeConstraint.Parent = label
UITextSizeConstraint.MaxTextSize = 17

box.Name = "box"
box.Parent = frame
box.BackgroundTransparency = 0.45
box.Position = UDim2.new(0.05, 0, 0.37, 0)
box.Size = UDim2.new(0.89, 0, 0.56, 0)
box.Font = Enum.Font.SourceSansBold
box.PlaceholderText = "HEX here"
box.Text = ""
box.TextColor3 = Color3.fromRGB(255, 255, 255)
box.TextScaled = true
box.TextWrapped = true

UITextSizeConstraint_2.Parent = box
UITextSizeConstraint_2.MaxTextSize = 28

UICorner.CornerRadius = UDim.new(0, 3)
UICorner.Parent = frame

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DrawingToolReplication = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DrawingToolReplication")

local function hexToColor3(hex)
    hex = hex:gsub("#", "")
    if #hex == 6 then
        local r = tonumber(hex:sub(1, 2), 16) / 255
        local g = tonumber(hex:sub(3, 4), 16) / 255
        local b = tonumber(hex:sub(5, 6), 16) / 255
        return Color3.new(r, g, b)
    end
    return Color3.new(1, 1, 1)
end

local chosenColor = Color3.new(1, 1, 1)

local mt = getrawmetatable(game)
setreadonly(mt, false)

local oldNamecall = mt.__namecall
mt.__namecall = newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    if self == DrawingToolReplication and method == "FireServer" then
        if typeof(args[1]) == "table" and typeof(args[2]) == "Color3" then
            args[2] = chosenColor
        end
        return oldNamecall(self, table.unpack(args))
    end
    return oldNamecall(self, ...)
end)

local function setupHexInput()
    local script = Instance.new("LocalScript", box)

    script.Parent.FocusLost:Connect(function(enter)
        if enter then
            chosenColor = hexToColor3(box.Text)
        end
    end)
end
coroutine.wrap(setupHexInput)()

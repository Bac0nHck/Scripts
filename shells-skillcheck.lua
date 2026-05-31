local QTE = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("QTE")
local function getAngle()
    return QTE.Main.Line.Rotation % 360
end
local function getTargetAngle()
    local bars = QTE.Main.Bars:GetChildren()
    for _, bar in ipairs(bars) do
        if bar.Visible then
            return bar.Rotation % 360
        end
    end
end
local function angleDiff(a, b)
    return math.abs(((a - b + 180) % 360) - 180)
end
game:GetService("RunService").RenderStepped:Connect(function()
    local line = getAngle()
    local target = getTargetAngle()
    if not target then return end
    if angleDiff(line, target) <= 4 then
        mouse1click()
    end
end)

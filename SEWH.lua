local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("S.E.W.H")
getgenv().settings = { inf_health = false, ragdoll = false }
local function getDisaster()
    return game:GetService("Workspace"):GetAttribute("currentDisaster") or "None"
end
local function getMap()
    return game:GetService("Workspace"):GetAttribute("currentMap") or "Unknown"
end
w:Label("Current Disaster: " .. getDisaster(), Color3.new(1.000000, 0.282353, 0.282353))
w:Label("Current Map: " .. getMap(), Color3.new(0.372549, 0.635294, 1.000000))
local window = game:GetService("CoreGui"):FindFirstChild("TurtleUiLib"):FindFirstChild("UiWindow"):FindFirstChild("Header"):WaitForChild("Window")
game:GetService("Workspace"):GetAttributeChangedSignal("currentDisaster"):Connect(function()
    if window then
        for _, d in pairs(window:GetChildren()) do
            if d:IsA("TextLabel") and string.find(d.Text, "Current Disaster") then
                d.Text = "Current Disaster: " .. getDisaster()
            end
        end
    end
end)
game:GetService("Workspace"):GetAttributeChangedSignal("currentMap"):Connect(function()
    if window then
        for _, d in pairs(window:GetChildren()) do
            if d:IsA("TextLabel") and string.find(d.Text, "Current Map") then
                d.Text = "Current Map: " .. getMap()
            end
        end
    end
end)
w:Toggle("Inf Health", settings.inf_health, function(bool)
    settings.inf_health = bool
    if settings.inf_health then
        while settings.inf_health do
            if getDisaster() ~= "None" then
                game:GetService("ReplicatedStorage"):WaitForChild("Resources"):WaitForChild("Communication"):WaitForChild("Asynchronous"):FireServer("charHit", -9e9, false, "Left Leg")
            end
            task.wait(0.5)
        end
    end
end)
w:Toggle("Ragdoll", settings.ragdoll, function(bool)
    settings.ragdoll = bool
    game:GetService("ReplicatedStorage"):WaitForChild("Resources"):WaitForChild("Communication"):WaitForChild("Asynchronous"):FireServer("updateRagdoll", settings.ragdoll)
end)
w:Button("Anti AFK", function ()
    local bb = game:GetService("VirtualUser")
    game:GetService("Players").LocalPlayer.Idled:connect(function()
        bb:CaptureController()
        bb:ClickButton2(Vector2.new())
    end)
end)
w:Label("By: t.me/arceusxscripts", Color3.fromRGB(127, 143, 166))
w:Button("Destroy Gui", function ()
    settings.inf_health = false
    settings.ragdoll = false
    lib:Destroy()
end)

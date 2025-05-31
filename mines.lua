local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("Mines")
local t = lib:Window("Teleports")
local s = lib:Window("Settings")
getgenv().settings = {ores_esp = false, auto_sell = false, always_perfect = false, auto_collect_ores = false}

local players = game:GetService("Players")
local plr = players.LocalPlayer

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local targetEvent = ReplicatedStorage:WaitForChild("shared/network/MiningNetwork@GlobalMiningEvents"):WaitForChild("Mine")

local items = workspace:FindFirstChild("Items")

w:Box("WalkSpeed", function (ws)
    plr.Character:FindFirstChild("Humanoid").WalkSpeed = tonumber(ws)
end)
w:Toggle("Ores ESP", false, function (bool)
    settings.ores_esp = bool
    if settings.ores_esp then
        pcall(function ()
            while settings.ores_esp do
                for _, item in pairs(items:GetChildren()) do
                    if not item:FindFirstChild("OreESP") then
                        for _, item in pairs(items:GetChildren()) do
                            if not item:FindFirstChild("OreESP") then
                                local box = Instance.new("BoxHandleAdornment", item)
                                box.Name = "OreESP"
                                box.Adornee = item
                                box.AlwaysOnTop = true
                                box.Size = item.Size
                                box.ZIndex = 0
                                box.Transparency = 0.5
                                box.Color3 = item.Color
                            end
                        end
                    end
                end
                task.wait(.75)
            end
        end)
    else
        for _, item in pairs(items:GetDescendants()) do
            if item.Name == "OreESP" then
                item:Destroy()
            end
        end
    end
end)
local tom = nil
for _, npc in pairs(game:GetService("Workspace"):GetChildren()) do
    if npc:IsA("Model") and npc:GetAttribute("Name") == "Trader Tom" then
        tom = npc
        break
    end
end
local lastPos = nil
w:Toggle("Auto Sell", false, function (bool)
    settings.auto_sell = bool
    while settings.auto_sell do
        lastPos = plr.Character:FindFirstChild("HumanoidRootPart").CFrame
        plr.Character:FindFirstChild("HumanoidRootPart").CFrame = tom:FindFirstChild("HumanoidRootPart").CFrame
        task.wait(.5)
        game:GetService("ReplicatedStorage"):WaitForChild("Ml"):WaitForChild("SellInventory"):FireServer()
        task.wait(.5)
        plr.Character:FindFirstChild("HumanoidRootPart").CFrame = lastPos
        task.wait(10)
    end
end)
w:Button("Sell Inventory", function ()
    lastPos = plr.Character:FindFirstChild("HumanoidRootPart").CFrame
    plr.Character:FindFirstChild("HumanoidRootPart").CFrame = tom:FindFirstChild("HumanoidRootPart").CFrame
    task.wait(.5)
    game:GetService("ReplicatedStorage"):WaitForChild("Ml"):WaitForChild("SellInventory"):FireServer()
    task.wait(.5)
    plr.Character:FindFirstChild("HumanoidRootPart").CFrame = lastPos
end)
w:Toggle("Always Perfect", false, function (bool)
    settings.always_perfect = bool
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if self == targetEvent and method == "FireServer" then
            if settings.always_perfect and typeof(args[2]) == "number" then
                args[2] = 1
                return old(self, unpack(args))
            end
        end

        return old(self, ...)
    end))
end)
w:Toggle("Auto Collect Ores", false, function (bool)
    settings.auto_collect_ores = bool
    while settings.auto_collect_ores do
        for _, item in pairs(items:GetChildren()) do
            local args = {
                item.Name
            }
            game:GetService("ReplicatedStorage"):WaitForChild("shared/network/MiningNetwork@GlobalMiningEvents"):WaitForChild("CollectItem"):FireServer(unpack(args))
        end
        task.wait(.5)
    end
end)

t:Button("Surface", function ()
    plr.Character:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(998, 245, -70)
end)
t:Button("Sally", function ()
    plr.Character:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(1055, 245, -279)
end)
t:Button("Bob", function ()
    plr.Character:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(1090, 245, -467)
end)
t:Button("Doorkeeper Dale", function ()
    plr.Character:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(996, 245, -346)
end)
t:Button("Driller Dan", function ()
    plr.Character:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(913, 245, -441)
end)
t:Button("Miner Mike", function ()
    plr.Character:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(956, 245, -229)
end)

s:Button("Anti AFK", function ()
	local bb = game:GetService("VirtualUser")
	plr.Idled:connect(function()
		bb:CaptureController()
		bb:ClickButton2(Vector2.new())
	end)
end)
s:Label("Press LeftControl to Hide UI", Color3.fromRGB(127, 143, 166))
s:Button("Destroy Gui", function ()
	lib:Destroy()
end)
s:Label("~ t.me/arceusxscripts", Color3.fromRGB(127, 143, 166))
lib:Keybind("LeftControl")

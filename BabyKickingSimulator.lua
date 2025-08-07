local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("Baby Kicking Simulator")

w:Toggle("Auto Kick Kid", false, function (bool)
    getgenv().kick = bool
    while kick do
        game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("KickBaby"):FireServer(1)
        task.wait()
    end
end)
w:Toggle("Farm Daily Rewards", false, function (bool)
    getgenv().rewards = bool
    while rewards do
        game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("RedeemDailyReward"):FireServer()
        task.wait()
    end
end)

local item = nil
local items_list = {}
for _, obj in pairs(game:GetService("Players").LocalPlayer:FindFirstChild("Values"):FindFirstChild("Items"):GetChildren()) do
    table.insert(items_list, obj.Name)
end
w:Dropdown("Choose Tool", items_list, function (name)
    item = name
end)
w:Toggle("Tool Spam", false, function (bool)
    getgenv().tool = bool
    while tool and item do
        game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("UseItem"):FireServer(item)
        task.wait()
    end
end)

local zone = nil
local zones_list = {}
local NPC_ANIMATIONS = workspace:FindFirstChild("NPC_ANIMATIONS")
for _, obj in pairs(NPC_ANIMATIONS:GetChildren()) do
    if obj:IsA("Folder") then
        local npc = obj:FindFirstChild("NPC")
        if npc and npc.Value then
            table.insert(zones_list, npc.Value.Name)
        end
    end
end
w:Dropdown("Choose NPC", zones_list, function (name)
    zone = name
end)
w:Button("Teleport to NPC", function ()
    if zone then
        for _, npcFolder in pairs(NPC_ANIMATIONS:GetChildren()) do
            if npcFolder:IsA("Folder") and npcFolder:FindFirstChild("NPC") and npcFolder.NPC.Value.Name == zone then
                local target = npcFolder:FindFirstChildOfClass("Part")
                if target then
                    game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = target.CFrame
                    return
                end
            end
        end
    end
end)

-- getgenv().farm = true
-- https://www.roblox.com/games/17685184035/Mining-MANIA

local plr = game:GetService("Players").LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EasyEvents = require(ReplicatedStorage.Shared.WhiteHatReplicated.Utilities.EasyEvents)
local OreLocator = require(ReplicatedStorage.Shared.WhiteHatReplicated.Modules.OreLocator)
local RequestDamageOre = ReplicatedStorage.FrameworkEvents.RequestDamageOre
local GC = getconnections or get_signal_cons
-- auto mine
task.spawn(function()
    while farm do
        local phase = workspace:GetAttribute("phaseName")
        if phase == "Game" then
            local mine = workspace:FindFirstChild("Mine")
            local chunks = mine and mine:FindFirstChild("Chunks")

            if chunks then
                for _, ore in pairs(chunks:GetDescendants()) do
                    if not farm then break end
                    if ore:IsA("MeshPart") and ore:GetAttribute("IsOre") then
                        local humPart = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                        if humPart then
                            local distance = (humPart.Position - ore.Position).Magnitude
                            if distance <= 25 then
                                local serializedOre = OreLocator.Serialize(ore, plr)

                                local hl = ore:FindFirstChild("Highlight")
                                if not hl then
                                    hl = Instance.new("Highlight")
                                    hl.Name = "Highlight"
                                    hl.FillColor = Color3.fromRGB(0, 255, 0)
                                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                                    hl.FillTransparency = 0.7
                                    hl.Adornee = ore
                                    hl.Parent = ore
                                end

                                for i = 1, 2 do RequestDamageOre:InvokeServer(serializedOre, 999) end

                                task.delay(0.2, function()
                                    if hl and hl.Parent then
                                        hl:Destroy()
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
        task.wait(0.1)
    end
end)
-- auto join
workspace:GetAttributeChangedSignal("phaseName"):Connect(function()
    local phase = workspace:GetAttribute("phaseName")
    if farm and phase == "ReadyToPlay" then
        EasyEvents:SendEvent("RequestToEnterMine")
    end
end)
-- anti afk
if GC then
    for i,v in pairs(GC(plr.Idled)) do
        if v["Disable"] then
            v["Disable"](v)
        elseif v["Disconnect"] then
            v["Disconnect"](v)
        end
    end
else
    local VirtualUser = cloneref(game:GetService("VirtualUser"))
    plr.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end
-- by: t.me/arceusxscripts

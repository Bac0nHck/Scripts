-- getgenv().farm = true -- false/true

-- Made By: Bac0nH1ckOff | a.k.a t.me/arceusxscripts
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local tickets = game:GetService("Workspace"):FindFirstChild("Game") and game:GetService("Workspace").Game:FindFirstChild("Effects") and game:GetService("Workspace").Game.Effects:FindFirstChild("Tickets")

player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

if tickets then
    while getgenv().farm do
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

        if character and humanoidRootPart then
            if character:GetAttribute("Downed") then
                ReplicatedStorage.Events.Player.ChangePlayerMode:FireServer(true)
            end
            
            for _, ticket in ipairs(tickets:GetChildren()) do
                local ticketPart = ticket:FindFirstChild("HumanoidRootPart")
                if ticketPart then
                    humanoidRootPart.CFrame = ticketPart.CFrame
                    task.wait(0.1)
                    -- stealler cookie roblox security send > @Bac0nH1ckOff
                end
            end
        end
        task.wait(1)
    end
end

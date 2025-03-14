-- https://scriptblox.com/script/Chained-2-Player-Obby-RAGDOLL-ALL-31917
local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("Chained | Ragdoll All")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
getgenv().ragdoll = false
w:Toggle("Toggle", false, function(bool)
    getgenv().ragdoll = bool
    while getgenv().ragdoll do
        for _, player in pairs(players:GetPlayers()) do
            if player ~= players.LocalPlayer then
                local ohInstance1 = player
                local ohBoolean2 = true
    
                replicatedStorage.Remotes.Ragdoll:FireServer(ohInstance1, ohBoolean2)
            end
        end
        task.wait()
    end
end)
w:Label("~ t.me/arceusxscripts", Color3.fromRGB(127, 143, 166))
w:Button("Destroy Gui", function()
    getgenv().ragdoll = false
    lib:Destroy()
end)

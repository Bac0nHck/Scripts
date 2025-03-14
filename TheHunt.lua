local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
if game.GameId == 6215464786 then -- Chained
    if game.PlaceId == 134363685332033 then
        local w = lib:Window("Chained | The Hunt")
        w:Label("The script requires a pair", Color3.fromRGB(127, 143, 166))
        w:Button("Instant checkpoints", function ()
            for i = 1, 31 do
                local a = {
                    [1] = i
                }
                game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("ClaimCheckpoint"):FireServer(unpack(a))
            end
        end)
        w:Label("By: t.me/arceusxscripts", Color3.fromRGB(127, 143, 166))
    else
        game:GetService("TeleportService"):Teleport(134363685332033, game:GetService("Players").LocalPlayer.Character)
    end
end

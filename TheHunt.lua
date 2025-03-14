local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()

local plr = game:GetService("Players").LocalPlayer

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
        game:GetService("TeleportService"):Teleport(134363685332033, plr.Character)
    end
elseif game.GameId == 65241 then -- Natural Disasters Survival
    local bb = game:GetService("VirtualUser") -- Anti Afk
    plr.Idled:connect(function()
        bb:CaptureController()
        bb:ClickButton2(Vector2.new())
    end)
    local lastPos
    local w = lib:Window("NDS | The Hunt") 
    w:Toggle("Auto Win", false, function(bool) -- Main Function
        getgenv().win = bool
        if getgenv().win then
            lastPos = plr.Character.HumanoidRootPart.CFrame
        else
            plr.Character.HumanoidRootPart.CFrame = lastPos
        end
        while getgenv().win do
            plr.Character.HumanoidRootPart.CFrame = CFrame.new(-282, 157, 339)
            task.wait()
        end
    end)
    w:Label("By: t.me/arceusxscripts", Color3.fromRGB(127, 143, 166))
end

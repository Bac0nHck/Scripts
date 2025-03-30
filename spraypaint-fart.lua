local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("SP | Fart")
local function f()
    game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Misc"):WaitForChild("Fart"):FireServer()
end
w:Button("Fart", f)
local t = 0.1
getgenv().af = false
w:Box("Delay", function(w)
    t = w
end)
w:Toggle("Auto Fart", false, function (bool)
    af = bool
    while af do
        f()
        task.wait(t)
    end
end)
w:Label("~ t.me/arceusxscripts", Color3.fromRGB(127, 143, 166))
w:Button("Destroy GUI", function()
    af = false
    lib:Destroy()
end)

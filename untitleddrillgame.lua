local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("untitled drill game")

getgenv().settings = {drill = false, sell = false, collect = false, storage = false}
local plr = game:GetService("Players").LocalPlayer
local sellPart = workspace:FindFirstChild("Scripted"):FindFirstChild("Sell")
local drillsUi = plr.PlayerGui:FindFirstChild("Menu"):FindFirstChild("CanvasGroup").Buy
local handdrillsUi = plr.PlayerGui:FindFirstChild("Menu"):FindFirstChild("CanvasGroup").HandDrills
local plot = nil

if plr then
    for _, p in ipairs(workspace.Plots:GetChildren()) do
        if p:FindFirstChild("Owner") and p.Owner.Value == plr then
            plot = p
            break
        end
    end
end

w:Toggle(
    "Auto Drill",
    false,
    function(bool)
        settings.drill = bool
        if settings.drill then
            task.spawn(
                function()
                    while settings.drill do
                        game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild(
                            "Services"
                        ):WaitForChild("OreService"):WaitForChild("RE"):WaitForChild("RequestRandomOre"):FireServer()
                        task.wait(0.01)
                    end
                end
            )
        end
    end
)

local lastPos = nil
local function sell()
    lastPos = plr.Character:FindFirstChild("HumanoidRootPart").CFrame

    plr.Character:FindFirstChild("HumanoidRootPart").CFrame = sellPart.CFrame
    task.wait(0.2)

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Knit = require(ReplicatedStorage.Packages:WaitForChild("Knit"))
    local OreService = Knit.GetService("OreService")

    OreService.SellAll:Fire()
    task.wait(0.2)

    if lastPos then
        plr.Character:FindFirstChild("HumanoidRootPart").CFrame = lastPos
    end
end

w:Button(
    "Sell All",
    function()
        sell()
    end
)

w:Toggle(
    "Auto Sell All",
    false,
    function(bool)
        settings.sell = bool
        if settings.sell then
            task.spawn(
                function()
                    while settings.sell do
                        sell()
                        task.wait(10)
                    end
                end
            )
        end
    end
)

w:Toggle(
    "Auto Collect Drills",
    false,
    function(bool)
        settings.collect = bool
        if settings.collect then
            task.spawn(
                function()
                    while settings.collect do
                        if plot and plot:FindFirstChild("Drills") then
                            for _, drill in pairs(plot.Drills:GetChildren()) do
                                if not settings.collect then
                                    break
                                end
                                game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild(
                                    "Services"
                                ):WaitForChild("PlotService"):WaitForChild("RE"):WaitForChild("CollectDrill"):FireServer(
                                    drill
                                )
                            end
                        end
                        task.wait(1)
                    end
                end
            )
        end
    end
)

w:Toggle(
    "Auto Collect Storage",
    false,
    function (bool)
        settings.storage = bool
        if settings.storage then
            task.spawn(
                function ()
                    while settings.storage do
                        if plot and plot:FindFirstChild("Storage") then
                            for _, storage in pairs(plot.Storage:GetChildren()) do
                                if not settings.storage then
                                    break
                                end
                                game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild(
                                    "Services"
                                ):WaitForChild("PlotService"):WaitForChild("RE"):WaitForChild("CollectDrill"):FireServer(
                                    storage
                                )
                            end
                        end
                        task.wait(1)
                    end
                end
            )
        end
    end
)

w:Toggle(
    "Drills Shop UI",
    false,
    function(bool)
        drillsUi.Visible = bool
    end
)

w:Toggle(
    "Handdrills Shop UI",
    false,
    function(bool)
        handdrillsUi.Visible = bool
    end
)

w:Button(
    "Anti AFK",
    function()
        local bb = game:GetService("VirtualUser")
        plr.Idled:Connect(
            function()
                bb:CaptureController()
                bb:ClickButton2(Vector2.new())
            end
        )
    end
)

w:Label("~ t.me/arceusxscripts", Color3.fromRGB(127, 143, 166))

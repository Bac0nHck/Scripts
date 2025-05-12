-- // https://scriptblox.com/script/Steal-a-Garden!-Pickup-Aura-Auto-Sell-And-More-39737
if not game:IsLoaded() then
    print("Waiting for game to load...")
    game.Loaded:Wait()
    print("Loaded Game")
end

--// Services
local replicated_storage = game:GetService("ReplicatedStorage")
local local_player = game:GetService("Players").LocalPlayer
local proximity_prompt_service = game:GetService("ProximityPromptService")
local workspace = game:GetService("Workspace")

--// GUI setup
local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local window = lib:Window("Steal a Garden!")

--// State variables
local flags = {
    pickup_aura = false,
    goto_nearest = false,
    auto_sell = false,
    always_gold = false,
    no_hold = false,
    remove_coins = false,
}

local pickup_aura_range = 15
local pickup_aura_delay = 0.1
local sell_delay = 0.1

--// Helper functions
local function nearest_plant()
    local closest, shortest = nil, math.huge
    for _, plant in ipairs(workspace.Plants:GetChildren()) do
        if plant:IsA("Model") and plant.PrimaryPart and local_player.Character then
            local dist = (plant:GetPivot().Position - local_player.Character:GetPivot().Position).Magnitude
            if dist < shortest then
                closest = plant
                shortest = dist
            end
        end
    end
    return closest
end

local function start_pickup_aura()
    task.spawn(function()
        while flags.pickup_aura do
            for _, plant in ipairs(workspace.Plants:GetChildren()) do
                if plant:IsA("Model") and plant.PrimaryPart and local_player.Character and
                   (plant:GetPivot().Position - local_player.Character:GetPivot().Position).Magnitude < pickup_aura_range then
                    fireproximityprompt(plant.PrimaryPart:FindFirstChildOfClass("ProximityPrompt"))
                end
            end
            task.wait(pickup_aura_delay)
        end
    end)
end

local function start_tp_to_plant()
    task.spawn(function()
        while flags.goto_nearest do
            local target = nearest_plant()
            if target and local_player.Character and local_player.Character:FindFirstChild("HumanoidRootPart") then
                local_player.Character.HumanoidRootPart.CFrame = target:GetPivot() + Vector3.new(0, 5, 0)
            end
            task.wait(0.2)
        end
    end)
end

local function start_auto_sell()
    task.spawn(function()
        while flags.auto_sell do
            local crate = local_player.Character and local_player.Character:FindFirstChild("Crate")
            if crate then
                for _, item in ipairs(crate:GetChildren()) do
                    if item:IsA("Model") then
                        replicated_storage.Remotes.SellPlantFromCrate:FireServer({
                            IsGold = flags.always_gold,
                            Name = item.Name,
                            UID = item:GetAttribute("UID")
                        })
                    end
                end
            end
            task.wait(sell_delay)
        end
    end)
end

--// GUI controls
window:Toggle("Pickup Aura", false, function(value)
    flags.pickup_aura = value
    if value then start_pickup_aura() end
end)

window:Toggle("TP to Nearest Plant", false, function(value)
    flags.goto_nearest = value
    if value then start_tp_to_plant() end
end)

window:Slider("Pickup Aura Range", 5, 25, pickup_aura_range, function(val)
    pickup_aura_range = val
end)

window:Slider("Pickup Aura Delay", 0.1, 5, pickup_aura_delay, function(val)
    pickup_aura_delay = val
end)

window:Toggle("Auto Sell", false, function(value)
    flags.auto_sell = value
    if value then start_auto_sell() end
end)

window:Toggle("Always Gold Sell", false, function(value)
    flags.always_gold = value
end)

window:Slider("Sell Delay", 0.1, 5, sell_delay, function(val)
    sell_delay = val
end)

window:Toggle("No Prompt Hold", false, function(value)
    flags.no_hold = value
end)

window:Toggle("Destroy Coins", false, function(value)
    flags.remove_coins = value
    if value then
        for _, v in ipairs(workspace:GetChildren()) do
            if v.Name == "Coin" then
                v:Destroy()
            end
        end
    end
end)

--// Connections
proximity_prompt_service.PromptButtonHoldBegan:Connect(function(prompt)
    if flags.no_hold then
        prompt.HoldDuration = 0
    end
end)

workspace.ChildAdded:Connect(function(child)
    if flags.remove_coins and child.Name == "Coin" then
        child:Destroy()
    end
end)

local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("Exam Week")
local s = lib:Window("Settings")
if not isfile("hide.png") then
    writefile(
        "hide.png",
        game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/hides.png")
    )
end
local enemie = (function()
	for _,v in pairs(game:GetService("Workspace"):GetDescendants()) do
		if v.Name == "LunchLady" and v:FindFirstChildOfClass("Humanoid") then
			return v
		end
	end
end)()
getgenv().enabled_esp = {keys = true, medkits = true, pages = true}
local players = game:GetService("Players")
local map = workspace:FindFirstChild("GameAssets"):FindFirstChild("Map")
local items = map:FindFirstChild("Items")
local hidelockers = map:FindFirstChild("HideLockers")
w:Label("Made by " .. game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram"), Color3.fromRGB(127, 143, 166))
w:Toggle("Lunchy Lady ESP", false, function(bool)
    if enemie then
        if bool then
            local highlight = enemie:FindFirstChild("LL_ESP")
            if not highlight then
                local highlight = Instance.new("Highlight")
                highlight.Name = "LL_ESP"
                highlight.Parent = enemie
                highlight.Adornee = enemie
                highlight.FillColor = Color3.fromRGB(255,0,0)
                highlight.FillTransparency = 0.7
            end
        else
            local highlight = enemie:FindFirstChild("LL_ESP")
            if highlight then
                highlight:Destroy()
            end
        end
    end
end)

local items_esp_enabled = false

local function UpdateItemsESP()
    if not items then
        return
    end

    for _, v in ipairs(items:GetDescendants()) do
        if v:IsA("Highlight") and v.Name == "Item_ESP" then
            v:Destroy()
        end
    end

    if not items_esp_enabled then
        return
    end

    for _, item in ipairs(items:GetChildren()) do
        local allowed = false

        if item.Name == "DoorKey" and enabled_esp.keys then
            allowed = true
        elseif item.Name == "Medkit" and enabled_esp.medkits then
            allowed = true
        elseif item.Name == "Collectible" and enabled_esp.pages then
            allowed = true
        end

        if allowed then
            local highlight = Instance.new("Highlight")
            highlight.Name = "Item_ESP"
            highlight.Parent = item
            highlight.Adornee = item
            highlight.FillTransparency = 0.7

            if item.Name == "Collectible" then
                highlight.FillColor = Color3.fromRGB(0,255,0)
                highlight.OutlineTransparency = 1

            elseif item.Name == "DoorKey" then
                local stripe = item:FindFirstChild("Stripe")

                if stripe then
                    highlight.FillColor = stripe.Color
                    highlight.OutlineColor = stripe.Color
                end

            elseif item.Name == "Medkit" then
                highlight.FillColor = Color3.fromRGB(255,0,0)
                highlight.OutlineColor = Color3.fromRGB(255,0,0)
            end
        end
    end
end
w:Toggle("Items ESP", false, function(bool)
    items_esp_enabled = bool
    UpdateItemsESP()
end)
w:Toggle("Hide Lockers ESP", false, function(bool)
    if not hidelockers then
        return
    end

    if bool then
        for _, locker in ipairs(hidelockers:GetChildren()) do
            if locker and not locker:FindFirstChild("Locker_ESP") then
                local adornee = locker:FindFirstChildWhichIsA("BasePart")

                if adornee then
                    local billboard = Instance.new("BillboardGui")
                    billboard.Name = "Locker_ESP"
                    billboard.Parent = locker
                    billboard.Adornee = adornee

                    billboard.Size = UDim2.new(0, 40, 0, 40)

                    billboard.SizeOffset = Vector2.new(0, 0)

                    billboard.AlwaysOnTop = true
                    billboard.LightInfluence = 0
                    billboard.MaxDistance = 500

                    local image = Instance.new("ImageLabel")
                    image.Parent = billboard
                    image.BackgroundTransparency = 1
                    image.Size = UDim2.new(1, 0, 1, 0)

                    image.Image = getcustomasset("hide.png")
                end
            end
        end
    else
        for _, locker in ipairs(hidelockers:GetChildren()) do
            local esp = locker:FindFirstChild("Locker_ESP")

            if esp then
                esp:Destroy()
            end
        end
    end
end)

local playersCount = #players:GetPlayers()
if playersCount > 1 then
    w:Toggle("Players ESP", false, function(bool)
        if bool then
            for _, player in pairs(players:GetChildren()) do
                local highlight = player.Character:FindFirstChild("Player_ESP") 
                if not highlight then
                    local highlight = Instance.new("Highlight")
                    highlight.Name = "Player_ESP"
                    highlight.Parent = player.Character
                    highlight.Adornee = player.Character
                    highlight.FillColor = Color3.fromRGB(0,255,0)
                    highlight.FillTransparency = 0.7
                    highlight.OutlineColor = Color3.fromRGB(0,255,0)
                end
            end
        else
            for _, player in pairs(players:GetChildren()) do
                local highlight = player.Character:FindFirstChild("Player_ESP") 
                if highlight then
                    highlight:Destroy()
                end
            end
        end
    end)
end

w:Button("FullBright", function()
    game:GetService("Lighting").Brightness = 2
	game:GetService("Lighting").ClockTime = 14
	game:GetService("Lighting").FogEnd = 100000
	game:GetService("Lighting").GlobalShadows = false
	game:GetService("Lighting").OutdoorAmbient = Color3.fromRGB(128, 128, 128)
end)

local plr = players.LocalPlayer
local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
w:Box("Walkspeed", function(speed)
    local val = tonumber(speed)

    if hum and val and val >= 9 then
        currentSpeed = val
        hum.WalkSpeed = val

        if walkspeedConnection then
            walkspeedConnection:Disconnect()
        end

        walkspeedConnection = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if hum.WalkSpeed ~= currentSpeed then
                hum.WalkSpeed = currentSpeed
            end
        end)
    end
end)

w:Button("Destoy GUI", function()
    lib:Destroy()
end)

s:Toggle("Keys ESP", true, function(bool)
    enabled_esp.keys = bool
    UpdateItemsESP()
end)
s:Toggle("Medkits ESP", true, function(bool)
    enabled_esp.medkits = bool
    UpdateItemsESP()
end)
s:Toggle("Pages ESP", true, function(bool)
    enabled_esp.pages = bool
    UpdateItemsESP()
end)

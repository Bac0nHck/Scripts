if getgenv and getgenv().GardenCleanerHub then
    pcall(getgenv().GardenCleanerHub.Unload)
    getgenv().GardenCleanerHub = nil
    task.wait(0.5)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

local ProximityPromptService = game:GetService("ProximityPromptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local LeafData = require(Modules:WaitForChild("LeafData"))
local UpgradeManager = require(Modules:WaitForChild("UpgradeManager"))
local ShopConfig = require(Modules:WaitForChild("ShopConfig"))
local QuestData = require(Modules:WaitForChild("QuestData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LeafPickedUp = Remotes:WaitForChild("LeafPickedUp")
local UpgradeRequest = Remotes:WaitForChild("UpgradeRequest")
local BuyEquipment = Remotes:WaitForChild("BuyEquipment")
local RebirthEvent = Remotes:WaitForChild("RebirthEvent")
local ResetPlotEvent = Remotes:WaitForChild("ResetPlotEvent")
local ClaimQuest = Remotes:WaitForChild("ClaimQuest")
local EquipTitle = Remotes:WaitForChild("EquipTitle")

local PlayerData = LocalPlayer:WaitForChild("PlayerData")
local HiddenData = LocalPlayer:WaitForChild("HiddenData")
local leaderstats = LocalPlayer:WaitForChild("leaderstats")
local Leaves = PlayerData:WaitForChild("Leaves")
local MaxHold = PlayerData:WaitForChild("MaxHold")
local Cash = PlayerData:WaitForChild("Cash")
local InfiniteCapacityExpiry = PlayerData:WaitForChild("InfiniteCapacityExpiry")
local UpgradeLevels = PlayerData:WaitForChild("UpgradeLevels")
local QuestProgress = LocalPlayer:WaitForChild("QuestProgress", 10)
local CompletedQuests = LocalPlayer:WaitForChild("CompletedQuests", 10)

local SellZones = Workspace:WaitForChild("SellZones")
local SecretStars = Workspace:WaitForChild("SecretStars")
local Areas = Workspace:WaitForChild("Areas")
local LockedDoors = Workspace:WaitForChild("LockedDoors")

local UPGRADE_LIST = {
    "Capacity", "Yield", "Cooldown",
    "RakeSpeed", "RakeArea", "RakeRange",
    "BlowerRange", "BlowerRadius", "BlowerCooldown"
}

local UPGRADE_REQUIREMENT = {
    RakeSpeed = "hasRake",
    RakeArea = "hasRake",
    RakeRange = "hasRake",
    BlowerRange = "hasLeafblower",
    BlowerRadius = "hasLeafblower",
    BlowerCooldown = "hasLeafblower"
}

local KEY_DOORS = {
    ["Shed Key"] = "ClosedShed",
    ["Garden Key"] = "ClosedGarden",
    ["Garage Key"] = "ClosedGarage",
    ["Grand Tree Key"] = "ClosedGrandTree",
    ["Greenhouse Key"] = "ClosedGreenhouse"
}

local REBIRTH_GATED = {
    Playground = 5,
    Skatepark = 10,
    Court = 25
}

local RARITY_ORDER = {
    Common = 1,
    Uncommon = 2,
    Rare = 3,
    Epic = 4,
    Legendary = 5
}

local State = {
    AutoCollect = false,
    Radius = 45,
    Delay = 0.12,
    BatchSize = 120,
    Settle = 0.35,
    AutoFarm = false,
    AreaFilter = {},
    RespectCapacity = true,
    AutoSell = true,
    SellPercent = 95,
    ReturnAfterSell = true,
    PreferredCan = "Auto",
    AutoUpgrade = false,
    UpgradeFilter = {},
    CashReserve = 0,
    AutoBuyRake = false,
    AutoBuyBlower = false,
    AutoRebirth = false,
    AutoStars = false,
    StarEsp = false,
    AutoDoors = false,
    AutoClaimQuests = false,
    AutoEquipTitle = false,
    InstantPrompt = false,
    SpeedEnabled = false,
    SpeedValue = 16,
    JumpEnabled = false,
    JumpValue = 50,
    InfiniteJump = false,
    Noclip = false,
    AntiAfk = true,
    Collected = 0,
    Sold = 0
}

local Unloaded = false
local Selling = false
local Busy = false
local Connections = {}
local BlockedAreas = {}
local VerifiedAreas = {}
local StarEspObjects = {}

local function trackConnection(connection)
    table.insert(Connections, connection)
    return connection
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getRoot()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function teleportTo(position)
    local root = getRoot()
    if not root then
        return false
    end
    root.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
    return true
end

local function getRebirth()
    local value = leaderstats:FindFirstChild("Rebirth")
    return value and value.Value or 0
end

local function isAreaUnlocked(areaName)
    local required = REBIRTH_GATED[areaName]
    if not required then
        return true
    end
    local unlocked = HiddenData:FindFirstChild("UnlockedDoors")
    if unlocked and unlocked:FindFirstChild(areaName) then
        return true
    end
    return getRebirth() >= required
end

local function isAreaSelected(areaName)
    if not next(State.AreaFilter) then
        return true
    end
    return State.AreaFilter[areaName] == true
end

local function hasInfiniteCapacity()
    return InfiniteCapacityExpiry.Value > os.time()
end

local function capacityLeft()
    if not State.RespectCapacity or hasInfiniteCapacity() then
        return math.huge
    end
    return math.max(0, MaxHold.Value - Leaves.Value)
end

local function leavesAround(position, radius)
    local result = {}
    if not LeafData.ready then
        return result
    end
    local keys = LeafData.GetCellKeysNearPosition(position, radius)
    for _, key in ipairs(keys) do
        local cell = LeafData.grid[key]
        if cell then
            for _, index in ipairs(cell) do
                local leaf = LeafData.leaves[index]
                if leaf and not leaf.pickedUp and leaf.cframe then
                    if (leaf.cframe.Position - position).Magnitude <= radius then
                        result[#result + 1] = index
                    end
                end
            end
        end
    end
    return result
end

local function findNearestLeaf(position)
    if not LeafData.ready then
        return nil
    end
    local bestIndex, bestDistance
    for index, leaf in ipairs(LeafData.leaves) do
        if not leaf.pickedUp and leaf.cframe then
            local areaName = leaf.areaName or "Unknown"
            if not BlockedAreas[areaName] and isAreaUnlocked(areaName) and isAreaSelected(areaName) then
                local distance = (leaf.cframe.Position - position).Magnitude
                if not bestDistance or distance < bestDistance then
                    bestDistance = distance
                    bestIndex = index
                end
            end
        end
    end
    if bestIndex then
        return LeafData.leaves[bestIndex].cframe.Position
    end
end

local ResyncAttempts = {}

local function resyncAreas()
    local saved = HiddenData:FindFirstChild("SavedLeafCounts")
    if not saved or not LeafData.ready then
        return 0
    end
    local localLeft = {}
    for _, leaf in ipairs(LeafData.leaves) do
        if not leaf.pickedUp then
            local areaName = leaf.areaName or "Unknown"
            localLeft[areaName] = (localLeft[areaName] or 0) + 1
        end
    end
    local stale = {}
    for _, value in ipairs(saved:GetChildren()) do
        local attempts = ResyncAttempts[value.Name] or 0
        if value.Value > (localLeft[value.Name] or 0) and attempts < 3 then
            stale[value.Name] = true
            ResyncAttempts[value.Name] = attempts + 1
        end
    end
    if not next(stale) then
        return 0
    end
    local restored = 0
    for _, leaf in ipairs(LeafData.leaves) do
        if leaf.pickedUp and stale[leaf.areaName or "Unknown"] then
            leaf.pickedUp = false
            restored = restored + 1
        end
    end
    if restored > 0 then
        BlockedAreas = {}
    end
    return restored
end

local function countRemaining()
    local total = 0
    if not LeafData.ready then
        return total
    end
    for _, leaf in ipairs(LeafData.leaves) do
        if not leaf.pickedUp then
            local areaName = leaf.areaName or "Unknown"
            if isAreaUnlocked(areaName) and isAreaSelected(areaName) then
                total = total + 1
            end
        end
    end
    return total
end

local function consumeLeaves(indices)
    for _, index in ipairs(indices) do
        pcall(LeafData.MarkPickedUp, index)
    end
end

local function fireBatch(areaName, indices)
    if #indices == 0 then
        return 0
    end
    local batch = {}
    for _, index in ipairs(indices) do
        local leaf = LeafData.leaves[index]
        batch[#batch + 1] = {
            AreaName = leaf.areaName,
            IsLucky = false,
            LeafIndex = index,
            Position = leaf.cframe.Position
        }
    end
    local needsCheck = not VerifiedAreas[areaName] and capacityLeft() > #batch
    local before = Leaves.Value
    LeafPickedUp:FireServer(batch)
    if needsCheck then
        local start = os.clock()
        repeat
            task.wait(0.1)
        until Leaves.Value > before or os.clock() - start > 1.5
        if Leaves.Value <= before then
            BlockedAreas[areaName] = true
            return 0
        end
        VerifiedAreas[areaName] = true
    end
    consumeLeaves(indices)
    return #indices
end

local function collectAt(position)
    if Selling or Busy or LocalPlayer:GetAttribute("IsSelling") then
        return 0
    end
    local room = capacityLeft()
    if room <= 0 then
        return 0
    end
    local indices = leavesAround(position, State.Radius)
    if #indices == 0 then
        return 0
    end
    local groups = {}
    for _, index in ipairs(indices) do
        local leaf = LeafData.leaves[index]
        local areaName = leaf.areaName or "Unknown"
        if not BlockedAreas[areaName] and isAreaUnlocked(areaName) and isAreaSelected(areaName) then
            local group = groups[areaName]
            if not group then
                group = {}
                groups[areaName] = group
            end
            if #group < State.BatchSize then
                group[#group + 1] = index
            end
        end
    end
    local collected = 0
    for areaName, group in pairs(groups) do
        if room <= 0 then
            break
        end
        if #group > room then
            local trimmed = {}
            for i = 1, room do
                trimmed[i] = group[i]
            end
            group = trimmed
        end
        local picked = fireBatch(areaName, group)
        collected = collected + picked
        room = room - picked
        if picked > 0 then
            task.wait(State.Delay)
        end
    end
    State.Collected = State.Collected + collected
    return collected
end

local function getBin()
    if State.PreferredCan ~= "Auto" then
        local can = SellZones:FindFirstChild(State.PreferredCan)
        if can then
            return can:FindFirstChild("Bin") or can:FindFirstChild("Part")
        end
    end
    local root = getRoot()
    if not root then
        return nil
    end
    local bestBin, bestDistance
    for _, can in ipairs(SellZones:GetChildren()) do
        local bin = can:FindFirstChild("Bin") or can:FindFirstChild("Part")
        if bin and bin:IsA("BasePart") then
            local distance = (bin.Position - root.Position).Magnitude
            if not bestDistance or distance < bestDistance then
                bestDistance = distance
                bestBin = bin
            end
        end
    end
    return bestBin
end

local function triggerPrompt(prompt)
    if not prompt then
        return
    end
    if fireproximityprompt then
        local ok = pcall(fireproximityprompt, prompt)
        if ok then
            return
        end
    end
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration + 0.15)
        prompt:InputHoldEnd()
    end)
end

local function sellNow()
    if Selling then
        return false
    end
    local root = getRoot()
    if not root then
        return false
    end
    if Leaves.Value <= 0 then
        return false
    end
    local bin = getBin()
    if not bin then
        return false
    end
    Selling = true
    local amount = Leaves.Value
    local origin = root.CFrame
    local target = CFrame.new(bin.Position + Vector3.new(0, 4, 0))
    root.CFrame = target
    task.wait(0.4)
    triggerPrompt(bin:FindFirstChildOfClass("ProximityPrompt"))
    local start = os.clock()
    while Leaves.Value > 0 and os.clock() - start < 25 and not Unloaded do
        local current = getRoot()
        if current then
            current.CFrame = target
        end
        task.wait(0.2)
    end
    task.wait(0.4)
    if State.ReturnAfterSell then
        local current = getRoot()
        if current then
            current.CFrame = origin
        end
    end
    State.Sold = State.Sold + (amount - Leaves.Value)
    Selling = false
    return true
end

local function collectStars()
    if Busy or Selling then
        return 0
    end
    local root = getRoot()
    if not root then
        return 0
    end
    Busy = true
    local origin = root.CFrame
    local collected = 0
    for _, star in ipairs(SecretStars:GetChildren()) do
        if star:IsA("BasePart") and not LocalPlayer:GetAttribute("Collected_" .. star.Name) then
            local current = getRoot()
            if not current then
                break
            end
            current.CFrame = CFrame.new(star.Position)
            task.wait(0.7)
            if LocalPlayer:GetAttribute("Collected_" .. star.Name) then
                collected = collected + 1
            end
        end
    end
    local current = getRoot()
    if current then
        current.CFrame = origin
    end
    Busy = false
    return collected
end

local function starsLeft()
    local total, left = 0, 0
    for _, star in ipairs(SecretStars:GetChildren()) do
        if star:IsA("BasePart") then
            total = total + 1
            if not LocalPlayer:GetAttribute("Collected_" .. star.Name) then
                left = left + 1
            end
        end
    end
    return left, total
end

local function clearStarEsp()
    for _, object in ipairs(StarEspObjects) do
        pcall(function()
            object:Destroy()
        end)
    end
    StarEspObjects = {}
end

local function buildStarEsp()
    clearStarEsp()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    for _, star in ipairs(SecretStars:GetChildren()) do
        if star:IsA("BasePart") then
            local highlight = Instance.new("Highlight")
            highlight.Adornee = star
            highlight.FillColor = Color3.fromRGB(255, 205, 40)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = 0.35
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Parent = parent
            table.insert(StarEspObjects, highlight)

            local billboard = Instance.new("BillboardGui")
            billboard.Adornee = star
            billboard.Size = UDim2.fromOffset(160, 30)
            billboard.StudsOffset = Vector3.new(0, 3, 0)
            billboard.AlwaysOnTop = true
            billboard.Parent = parent

            local label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.Size = UDim2.fromScale(1, 1)
            label.Font = Enum.Font.GothamBold
            label.TextSize = 14
            label.TextStrokeTransparency = 0.4
            label.TextColor3 = Color3.fromRGB(255, 215, 80)
            label.Text = star.Name
            label.Parent = billboard
            table.insert(StarEspObjects, billboard)
        end
    end
end

local function buyUpgrade(name)
    local levelValue = UpgradeLevels:FindFirstChild(name .. "Level")
    local level = levelValue and levelValue.Value or 1
    if level >= (UpgradeManager.MAX_LEVEL or 5) then
        return false
    end
    local requirement = UPGRADE_REQUIREMENT[name]
    if requirement then
        local flag = PlayerData:FindFirstChild(requirement)
        if not (flag and flag.Value == true) then
            return false
        end
    end
    local cost = UpgradeManager.GetModifiedCost(LocalPlayer, name, level)
    if cost <= 0 or Cash.Value - State.CashReserve < cost then
        return false
    end
    UpgradeRequest:FireServer(name)
    return true
end

local function buyEquipment(kind)
    local flagName = kind == "Rake" and "hasRake" or "hasLeafblower"
    local flag = PlayerData:FindFirstChild(flagName)
    if flag and flag.Value == true then
        return false
    end
    local cost = ShopConfig.GetModifiedCost(LocalPlayer, kind)
    if cost <= 0 or Cash.Value - State.CashReserve < cost then
        return false
    end
    BuyEquipment:FireServer(kind)
    return true
end

local function capacityMaxed()
    local capacity = UpgradeLevels:FindFirstChild("CapacityLevel")
    if not capacity or capacity.Value < 5 then
        return false
    end
    if getRebirth() < 1 then
        return true
    end
    local basement = UpgradeLevels:FindFirstChild("BasementCapacityLevel")
    return basement ~= nil and basement.Value >= 4
end

local function clearRatio()
    local saved = HiddenData:FindFirstChild("SavedLeafCounts")
    if not saved then
        return 0
    end
    local rebirth = getRebirth()
    local total, left = 0, 0
    for _, area in ipairs(Areas:GetChildren()) do
        if area:IsA("Folder") then
            local gate = REBIRTH_GATED[area.Name]
            if not gate or rebirth >= gate then
                local amount = area:GetAttribute("LeafAmount") or 50
                total = total + amount
                local value = saved:FindFirstChild(area.Name)
                left = left + (value and value.Value or amount)
            end
        end
    end
    if total <= 0 then
        return 0
    end
    return (total - left) / total
end

local function plotCleared()
    local cleared = HiddenData:FindFirstChild("HasClearedPlotThisRebirth")
    if cleared and cleared.Value == true then
        return true
    end
    return clearRatio() >= 0.999
end

local function canRebirth()
    return capacityMaxed() and plotCleared()
end

local function rebirthBlocker()
    local capacity = UpgradeLevels:FindFirstChild("CapacityLevel")
    if not capacity or capacity.Value < 5 then
        return "Capacity upgrade not maxed"
    end
    if getRebirth() >= 1 then
        local basement = UpgradeLevels:FindFirstChild("BasementCapacityLevel")
        if not basement or basement.Value < 4 then
            local folder = Workspace:FindFirstChild("BasementUpgrades")
            local button = folder and folder:FindFirstChild("CapacityUpgradeButton")
            local price = button and button:FindFirstChildWhichIsA("TextLabel", true)
            return "Basement capacity " .. (basement and basement.Value or 0) .. "/4 (" .. (price and price.Text or "?") .. ")"
        end
    end
    if not plotCleared() then
        return "Plot " .. math.floor(clearRatio() * 1000) / 10 .. "%"
    end
    return "ready"
end

local function upgradeBasementCapacity()
    if Busy or Selling then
        return false
    end
    local folder = Workspace:FindFirstChild("BasementUpgrades")
    local button = folder and folder:FindFirstChild("CapacityUpgradeButton")
    local levelValue = UpgradeLevels:FindFirstChild("BasementCapacityLevel")
    local root = getRoot()
    if not (button and levelValue and root) then
        return false
    end
    if levelValue.Value >= 4 then
        return false
    end
    Busy = true
    local origin = root.CFrame
    local target = CFrame.new(button.Position + Vector3.new(0, 3, 0))
    local startLevel = levelValue.Value
    local lastLevel = startLevel
    local lastChange = os.clock()
    while levelValue.Value < 4 and not Unloaded do
        local current = getRoot()
        if not current then
            break
        end
        current.CFrame = target
        task.wait(0.4)
        if levelValue.Value ~= lastLevel then
            lastLevel = levelValue.Value
            lastChange = os.clock()
        elseif os.clock() - lastChange > 3 then
            break
        end
    end
    local current = getRoot()
    if current then
        current.CFrame = origin
    end
    Busy = false
    return levelValue.Value > startLevel
end

local function useKeys()
    if Busy or Selling then
        return 0
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then
        return 0
    end
    local used = 0
    local tools = {}
    for _, tool in ipairs(backpack:GetChildren()) do
        if KEY_DOORS[tool.Name] then
            table.insert(tools, tool.Name)
        end
    end
    local character = getCharacter()
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if KEY_DOORS[tool.Name] then
                table.insert(tools, tool.Name)
            end
        end
    end
    if #tools == 0 then
        return 0
    end
    Busy = true
    for _, keyName in ipairs(tools) do
        local door = LockedDoors:FindFirstChild(KEY_DOORS[keyName])
        if door then
            local root = getRoot()
            if not root then
                break
            end
            local origin = root.CFrame
            local position = door:IsA("Model") and door:GetPivot().Position or door.Position
            root.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
            task.wait(0.9)
            local current = getRoot()
            if current then
                current.CFrame = origin
            end
            used = used + 1
            task.wait(0.3)
        end
    end
    Busy = false
    return used
end

local function questIsReady(id, info)
    if not (QuestProgress and CompletedQuests) then
        return false
    end
    if CompletedQuests:FindFirstChild(id) then
        return false
    end
    if info.Prerequisite then
        local gate = QuestProgress:FindFirstChild(info.Prerequisite.Target)
        if (gate and gate.Value or 0) < info.Prerequisite.Value then
            return false
        end
    end
    local progress = QuestProgress:FindFirstChild(info.Target)
    return (progress and progress.Value or 0) >= (info.GoalValue or math.huge)
end

local function claimableQuests()
    local ready = 0
    for id, info in pairs(QuestData.Quests) do
        if questIsReady(id, info) then
            ready = ready + 1
        end
    end
    return ready
end

local function claimQuests()
    local claimed = 0
    for id, info in pairs(QuestData.Quests) do
        if Unloaded then
            break
        end
        if questIsReady(id, info) then
            ClaimQuest:FireServer(id)
            claimed = claimed + 1
            task.wait(0.25)
        end
    end
    return claimed
end

local function bestTitle()
    local earned = PlayerData:FindFirstChild("EarnedTitles")
    if not earned then
        return nil
    end
    local bestName, bestRank
    for _, info in pairs(QuestData.Quests) do
        local title = info.RewardTitle
        if title and earned:FindFirstChild(title) then
            local rank = RARITY_ORDER[info.Rarity or "Common"] or 1
            if not bestRank or rank > bestRank then
                bestRank = rank
                bestName = title
            end
        end
    end
    return bestName
end

local function equipBestTitle()
    local title = bestTitle()
    if not title then
        return false
    end
    local equipped = PlayerData:FindFirstChild("EquippedTitle")
    if equipped and equipped.Value == title then
        return false
    end
    EquipTitle:FireServer(title)
    return true
end

local function areaNames()
    local names = {}
    for _, area in ipairs(Areas:GetChildren()) do
        if area:IsA("Folder") then
            table.insert(names, area.Name)
        end
    end
    table.sort(names)
    return names
end

local function areaPosition(name)
    local area = Areas:FindFirstChild(name)
    if not area then
        return nil
    end
    for _, descendant in ipairs(area:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant.Position
        end
    end
end

local function canNames()
    local names = { "Auto" }
    for _, can in ipairs(SellZones:GetChildren()) do
        table.insert(names, can.Name)
    end
    return names
end

local function formatNumber(value)
    local formatted = tostring(math.floor(value))
    while true do
        local replaced
        formatted, replaced = formatted:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
        if replaced == 0 then
            break
        end
    end
    return formatted
end

local FluentSource = game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua")
if gethui then
    FluentSource = FluentSource:gsub('Parent = LocalPlayer:WaitForChild%("PlayerGui"%)', "Parent = gethui()")
end
local Fluent = loadstring(FluentSource)()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Garden Cleaner Evolution",
    SubTitle = "Leaf Farm Hub",
    Search = true,
    Icon = "leaf",
    TabWidth = 150,
    Size = UDim2.fromOffset(580, 470),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl,
    UserInfo = true,
    UserInfoTop = false,
    UserInfoTitle = LocalPlayer.DisplayName,
    UserInfoSubtitle = "Gardener",
    UserInfoSubtitleColor = Color3.fromRGB(102, 214, 122)
})

local Minimizer = Fluent:CreateMinimizer({
    Icon = "leaf",
    Size = UDim2.fromOffset(44, 44),
    Position = UDim2.new(0, 40, 0, 140),
    Acrylic = false,
    Corner = 12,
    Transparency = 0.1,
    Draggable = true,
    Visible = true
})

local Tabs = {
    Farm = Window:AddTab({ Title = "Farm", Icon = "leaf" }),
    Sell = Window:AddTab({ Title = "Sell", Icon = "dollar-sign" }),
    Upgrades = Window:AddTab({ Title = "Upgrades", Icon = "arrow-big-up" }),
    Stars = Window:AddTab({ Title = "Stars", Icon = "star" }),
    Quests = Window:AddTab({ Title = "Quests", Icon = "book" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Player = Window:AddTab({ Title = "Player", Icon = "user" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

local setIdentity = setthreadidentity or setidentity or set_thread_identity

local function elevate()
    if setIdentity then
        pcall(setIdentity, 8)
    end
end

local function updateParagraph(paragraph, title, content)
    if not paragraph then
        return
    end
    elevate()
    pcall(function()
        paragraph:SetTitle(title)
    end)
    pcall(function()
        paragraph:SetDesc(content)
    end)
end

Tabs.Farm:AddSection("Collection", "sparkles")

local StatsParagraph = Tabs.Farm:AddParagraph({
    Icon = "activity",
    Title = "Status",
    Content = "Loading..."
})

Tabs.Farm:AddToggle("GCAutoCollect", {
    Title = "Auto Collect Leaves",
    Description = "Picks up every leaf inside the aura radius",
    Default = false
}):OnChanged(function()
    State.AutoCollect = Options.GCAutoCollect.Value
end)

Tabs.Farm:AddToggle("GCAutoFarm", {
    Title = "Auto Farm (Teleport)",
    Description = "Moves to the next leaf cluster when the aura is empty",
    Default = false
}):OnChanged(function()
    State.AutoFarm = Options.GCAutoFarm.Value
end)

Tabs.Farm:AddSlider("GCRadius", {
    Title = "Aura Radius",
    Description = "Server accepts up to 60 studs",
    Default = 45,
    Min = 10,
    Max = 60,
    Rounding = 0,
    Callback = function(value)
        State.Radius = value
    end
})

Tabs.Farm:AddSlider("GCDelay", {
    Title = "Collect Delay",
    Description = "Seconds between batches",
    Default = 0.12,
    Min = 0.05,
    Max = 1,
    Rounding = 2,
    Callback = function(value)
        State.Delay = value
    end
})

Tabs.Farm:AddSlider("GCBatch", {
    Title = "Batch Size",
    Description = "Leaves sent per request",
    Default = 120,
    Min = 10,
    Max = 250,
    Rounding = 0,
    Callback = function(value)
        State.BatchSize = value
    end
})

Tabs.Farm:AddSlider("GCSettle", {
    Title = "Teleport Settle",
    Description = "Wait after each teleport so the server sees the new position",
    Default = 0.35,
    Min = 0.1,
    Max = 1.5,
    Rounding = 2,
    Callback = function(value)
        State.Settle = value
    end
})

Tabs.Farm:AddToggle("GCRespectCapacity", {
    Title = "Respect Capacity",
    Description = "Stops collecting when the bag is full",
    Default = true
}):OnChanged(function()
    State.RespectCapacity = Options.GCRespectCapacity.Value
end)

Tabs.Farm:AddDropdown("GCAreaFilter", {
    Title = "Areas",
    Description = "Empty selection farms every unlocked area",
    Values = areaNames(),
    Multi = true,
    Search = true,
    Default = {}
}):OnChanged(function(value)
    local filter = {}
    for name, selected in pairs(value) do
        if selected then
            filter[name] = true
        end
    end
    State.AreaFilter = filter
end)

Tabs.Farm:AddButton({
    Title = "Collect Around Me Once",
    Description = "Single aura pass at the current position",
    Callback = function()
        task.spawn(function()
            local root = getRoot()
            if not root then
                return
            end
            local picked = collectAt(root.Position)
            Fluent:Notify({ Title = "Garden Cleaner", Content = "Collected " .. picked .. " leaves", Duration = 4 })
        end)
    end
})

Tabs.Farm:AddButton({
    Title = "Resync With Server",
    Description = "Restores leaves the server still counts and retries blocked areas",
    Callback = function()
        task.spawn(function()
            BlockedAreas = {}
            VerifiedAreas = {}
            ResyncAttempts = {}
            local restored = resyncAreas()
            Fluent:Notify({ Title = "Garden Cleaner", Content = "Restored " .. restored .. " leaves", Duration = 5 })
        end)
    end
})

Tabs.Sell:AddSection("Selling", "shopping-cart")

Tabs.Sell:AddToggle("GCAutoSell", {
    Title = "Auto Sell",
    Description = "Teleports to a bin and dumps leaves when full",
    Default = true
}):OnChanged(function()
    State.AutoSell = Options.GCAutoSell.Value
end)

Tabs.Sell:AddSlider("GCSellPercent", {
    Title = "Sell At Capacity",
    Description = "Percent of the bag before selling",
    Default = 95,
    Min = 30,
    Max = 100,
    Rounding = 0,
    Callback = function(value)
        State.SellPercent = value
    end
})

Tabs.Sell:AddToggle("GCReturnAfterSell", {
    Title = "Return After Sell",
    Description = "Teleports back to the farming spot",
    Default = true
}):OnChanged(function()
    State.ReturnAfterSell = Options.GCReturnAfterSell.Value
end)

Tabs.Sell:AddDropdown("GCPreferredCan", {
    Title = "Trash Can",
    Values = canNames(),
    Multi = false,
    Search = false,
    Default = 1
}):OnChanged(function(value)
    State.PreferredCan = value
end)

Tabs.Sell:AddButton({
    Title = "Sell Now",
    Description = "Dump every leaf immediately",
    Callback = function()
        task.spawn(sellNow)
    end
})

Tabs.Upgrades:AddSection("Shop", "coins")

local UpgradeParagraph = Tabs.Upgrades:AddParagraph({
    Icon = "list",
    Title = "Levels",
    Content = "Loading..."
})

Tabs.Upgrades:AddToggle("GCAutoUpgrade", {
    Title = "Auto Upgrade",
    Description = "Buys the selected upgrades whenever they are affordable",
    Default = false
}):OnChanged(function()
    State.AutoUpgrade = Options.GCAutoUpgrade.Value
end)

Tabs.Upgrades:AddDropdown("GCUpgradeFilter", {
    Title = "Upgrades",
    Description = "Empty selection buys everything available",
    Values = UPGRADE_LIST,
    Multi = true,
    Search = true,
    Default = { "Capacity", "Yield", "Cooldown" }
}):OnChanged(function(value)
    local filter = {}
    for name, selected in pairs(value) do
        if selected then
            filter[name] = true
        end
    end
    State.UpgradeFilter = filter
end)

Tabs.Upgrades:AddInput("GCCashReserve", {
    Title = "Keep Cash",
    Default = "0",
    Placeholder = "0",
    Numeric = true,
    Finished = true,
    Callback = function(value)
        State.CashReserve = tonumber(value) or 0
    end
})

Tabs.Upgrades:AddToggle("GCAutoBuyRake", {
    Title = "Auto Buy Rake",
    Default = false
}):OnChanged(function()
    State.AutoBuyRake = Options.GCAutoBuyRake.Value
end)

Tabs.Upgrades:AddToggle("GCAutoBuyBlower", {
    Title = "Auto Buy Leafblower",
    Default = false
}):OnChanged(function()
    State.AutoBuyBlower = Options.GCAutoBuyBlower.Value
end)

Tabs.Upgrades:AddToggle("GCAutoRebirth", {
    Title = "Auto Rebirth",
    Description = "Rebirths as soon as the plot is clear and capacity is maxed",
    Default = false
}):OnChanged(function()
    State.AutoRebirth = Options.GCAutoRebirth.Value
end)

Tabs.Upgrades:AddButton({
    Title = "Buy Everything Affordable",
    Description = "One pass over the whole upgrade list",
    Callback = function()
        task.spawn(function()
            local bought = 0
            for _, name in ipairs(UPGRADE_LIST) do
                while buyUpgrade(name) do
                    bought = bought + 1
                    task.wait(0.2)
                end
            end
            Fluent:Notify({ Title = "Garden Cleaner", Content = "Bought " .. bought .. " upgrades", Duration = 4 })
        end)
    end
})

Tabs.Upgrades:AddButton({
    Title = "Max Basement Capacity",
    Description = "Touches the basement capacity button until level 4",
    Callback = function()
        task.spawn(function()
            upgradeBasementCapacity()
            local basement = UpgradeLevels:FindFirstChild("BasementCapacityLevel")
            Fluent:Notify({ Title = "Garden Cleaner", Content = "Basement capacity " .. (basement and basement.Value or 0) .. "/4", Duration = 4 })
        end)
    end
})

Tabs.Upgrades:AddButton({
    Title = "Rebirth Now",
    Callback = function()
        RebirthEvent:FireServer()
    end
})

Tabs.Stars:AddSection("Secret Stars", "star")

local StarParagraph = Tabs.Stars:AddParagraph({
    Icon = "star",
    Title = "Progress",
    Content = "Loading..."
})

Tabs.Stars:AddButton({
    Title = "Collect All Stars",
    Description = "Teleports through every uncollected star and returns",
    Callback = function()
        task.spawn(function()
            local collected = collectStars()
            Fluent:Notify({ Title = "Garden Cleaner", Content = "Collected " .. collected .. " stars", Duration = 5 })
        end)
    end
})

Tabs.Stars:AddToggle("GCAutoStars", {
    Title = "Auto Collect Stars",
    Description = "Grabs stars that appear after a rebirth",
    Default = false
}):OnChanged(function()
    State.AutoStars = Options.GCAutoStars.Value
end)

Tabs.Stars:AddToggle("GCStarEsp", {
    Title = "Star ESP",
    Default = false
}):OnChanged(function()
    State.StarEsp = Options.GCStarEsp.Value
    if State.StarEsp then
        buildStarEsp()
    else
        clearStarEsp()
    end
end)

Tabs.Quests:AddSection("Quests And Titles", "book")

local QuestParagraph = Tabs.Quests:AddParagraph({
    Icon = "list",
    Title = "Quests",
    Content = "Loading..."
})

Tabs.Quests:AddToggle("GCAutoClaimQuests", {
    Title = "Auto Claim Quests",
    Description = "Claims every quest that reached its goal",
    Default = false
}):OnChanged(function()
    State.AutoClaimQuests = Options.GCAutoClaimQuests.Value
end)

Tabs.Quests:AddToggle("GCAutoEquipTitle", {
    Title = "Auto Equip Best Title",
    Description = "Equips the rarest title you own",
    Default = false
}):OnChanged(function()
    State.AutoEquipTitle = Options.GCAutoEquipTitle.Value
end)

Tabs.Quests:AddButton({
    Title = "Claim All Now",
    Callback = function()
        task.spawn(function()
            local claimed = claimQuests()
            Fluent:Notify({ Title = "Garden Cleaner", Content = "Claimed " .. claimed .. " quests", Duration = 4 })
        end)
    end
})

Tabs.Quests:AddButton({
    Title = "Equip Best Title",
    Callback = function()
        task.spawn(function()
            local title = bestTitle()
            equipBestTitle()
            Fluent:Notify({ Title = "Garden Cleaner", Content = title and ("Equipped " .. title) or "No titles owned", Duration = 4 })
        end)
    end
})

Tabs.Teleport:AddSection("Areas", "map")

local selectedArea = areaNames()[1]

Tabs.Teleport:AddDropdown("GCTeleportArea", {
    Title = "Area",
    Values = areaNames(),
    Multi = false,
    Search = true,
    Default = 1
}):OnChanged(function(value)
    selectedArea = value
end)

Tabs.Teleport:AddButton({
    Title = "Teleport To Area",
    Callback = function()
        local position = areaPosition(selectedArea)
        if position then
            teleportTo(position)
        end
    end
})

Tabs.Teleport:AddSection("Landmarks", "flag")

local landmarks = {
    { "Nearest Trash Can", function()
        local bin = getBin()
        return bin and bin.Position
    end },
    { "Upgrade Area", function()
        local part = Workspace:FindFirstChild("UpgradeArea")
        return part and part.Position
    end },
    { "Rake Shop", function()
        local part = Workspace:FindFirstChild("RakeShopArea")
        return part and part.Position
    end },
    { "Leafblower Shop", function()
        local part = Workspace:FindFirstChild("LeafblowerShopArea")
        return part and part.Position
    end },
    { "Rebirth Fountain", function()
        local model = Workspace:FindFirstChild("Fountain Of Rebirth")
        local part = model and model:FindFirstChild("PromptPart")
        return part and part.Position
    end },
    { "Basement Entrance", function()
        local basement = Workspace:FindFirstChild("Basement")
        local entrance = basement and basement:FindFirstChild("BasementEntrance")
        local part = entrance and entrance:FindFirstChild("BasementProximityPart")
        return part and part.Position
    end },
    { "Spawn", function()
        local part = Workspace:FindFirstChild("SpawnLocation")
        return part and part.Position
    end }
}

for _, entry in ipairs(landmarks) do
    Tabs.Teleport:AddButton({
        Title = entry[1],
        Callback = function()
            local position = entry[2]()
            if position then
                teleportTo(position)
            end
        end
    })
end

Tabs.Teleport:AddSection("Doors", "key")

Tabs.Teleport:AddToggle("GCAutoDoors", {
    Title = "Auto Use Keys",
    Description = "Visits locked doors while a matching key is in the backpack",
    Default = false
}):OnChanged(function()
    State.AutoDoors = Options.GCAutoDoors.Value
end)

Tabs.Teleport:AddButton({
    Title = "Open Doors Now",
    Callback = function()
        task.spawn(function()
            local used = useKeys()
            Fluent:Notify({ Title = "Garden Cleaner", Content = "Visited " .. used .. " doors", Duration = 4 })
        end)
    end
})

Tabs.Player:AddSection("Movement", "footprints")

Tabs.Player:AddToggle("GCSpeedEnabled", {
    Title = "Custom Walk Speed",
    Default = false
}):OnChanged(function()
    State.SpeedEnabled = Options.GCSpeedEnabled.Value
    if not State.SpeedEnabled then
        local humanoid = getHumanoid()
        local preferred = PlayerData:FindFirstChild("PreferredSpeed")
        if humanoid then
            humanoid.WalkSpeed = preferred and preferred.Value or 16
        end
    end
end)

Tabs.Player:AddSlider("GCSpeedValue", {
    Title = "Walk Speed",
    Default = 30,
    Min = 16,
    Max = 200,
    Rounding = 0,
    Callback = function(value)
        State.SpeedValue = value
    end
})

Tabs.Player:AddToggle("GCJumpEnabled", {
    Title = "Custom Jump Power",
    Default = false
}):OnChanged(function()
    State.JumpEnabled = Options.GCJumpEnabled.Value
    if not State.JumpEnabled then
        local humanoid = getHumanoid()
        if humanoid then
            humanoid.JumpPower = 50
        end
    end
end)

Tabs.Player:AddSlider("GCJumpValue", {
    Title = "Jump Power",
    Default = 50,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(value)
        State.JumpValue = value
    end
})

Tabs.Player:AddToggle("GCInfiniteJump", {
    Title = "Infinite Jump",
    Default = false
}):OnChanged(function()
    State.InfiniteJump = Options.GCInfiniteJump.Value
end)

Tabs.Player:AddToggle("GCNoclip", {
    Title = "Noclip",
    Default = false
}):OnChanged(function()
    State.Noclip = Options.GCNoclip.Value
end)

Tabs.Player:AddToggle("GCAntiAfk", {
    Title = "Anti AFK",
    Default = true
}):OnChanged(function()
    State.AntiAfk = Options.GCAntiAfk.Value
end)

Tabs.Player:AddToggle("GCInstantPrompt", {
    Title = "Instant Interact",
    Description = "Zeroes the hold time of a prompt only while you interact with it",
    Default = false
}):OnChanged(function()
    State.InstantPrompt = Options.GCInstantPrompt.Value
end)

Tabs.Player:AddSection("Server", "server")

Tabs.Player:AddButton({
    Title = "Rejoin Server",
    Callback = function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end
})

local function unloadHub()
    Unloaded = true
    State.AutoCollect = false
    State.AutoFarm = false
    State.AutoSell = false
    State.AutoUpgrade = false
    State.AutoStars = false
    State.AutoDoors = false
    State.AutoClaimQuests = false
    State.AutoEquipTitle = false
    State.InstantPrompt = false
    State.SpeedEnabled = false
    State.JumpEnabled = false
    State.InfiniteJump = false
    State.Noclip = false
    clearStarEsp()
    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    pcall(function()
        Fluent:Destroy()
    end)
end

if getgenv then
    getgenv().GardenCleanerHub = { Unload = unloadHub }
end

Tabs.Player:AddButton({
    Title = "Unload Hub",
    Description = "Stops every loop and removes the interface",
    Callback = unloadHub
})

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("GardenCleanerEvolution")
SaveManager:SetFolder("GardenCleanerEvolution/hub")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

trackConnection(LocalPlayer.Idled:Connect(function()
    if not State.AntiAfk or Unloaded then
        return
    end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end))

local PromptOriginals = {}

local function restorePrompt(prompt)
    local original = PromptOriginals[prompt]
    if original == nil then
        return
    end
    PromptOriginals[prompt] = nil
    pcall(function()
        if prompt.Parent then
            prompt.HoldDuration = original
        end
    end)
end

trackConnection(ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
    if Unloaded or not State.InstantPrompt or player ~= LocalPlayer then
        return
    end
    if PromptOriginals[prompt] ~= nil or prompt.HoldDuration <= 0 then
        return
    end
    PromptOriginals[prompt] = prompt.HoldDuration
    elevate()
    pcall(function()
        prompt.HoldDuration = 0
    end)
    triggerPrompt(prompt)
    pcall(function()
        prompt:InputHoldEnd()
    end)
    task.delay(0.35, function()
        restorePrompt(prompt)
    end)
end))

trackConnection(ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, player)
    if player ~= LocalPlayer then
        return
    end
    task.delay(0.35, function()
        restorePrompt(prompt)
    end)
end))

trackConnection(UserInputService.JumpRequest:Connect(function()
    if not State.InfiniteJump or Unloaded then
        return
    end
    local humanoid = getHumanoid()
    if humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end))

trackConnection(RunService.Stepped:Connect(function()
    if Unloaded then
        return
    end
    local humanoid = getHumanoid()
    if humanoid then
        if State.SpeedEnabled then
            humanoid.WalkSpeed = State.SpeedValue
        end
        if State.JumpEnabled then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = State.JumpValue
        end
    end
    if State.Noclip then
        local character = getCharacter()
        if character then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end
end))

local function waitForLeafData()
    BlockedAreas = {}
    VerifiedAreas = {}
    ResyncAttempts = {}
    local start = os.clock()
    while not LeafData.ready and os.clock() - start < 60 and not Unloaded do
        task.wait(0.5)
    end
    task.wait(1)
end

trackConnection(RebirthEvent.OnClientEvent:Connect(function()
    State.Collected = 0
    task.spawn(waitForLeafData)
end))

trackConnection(ResetPlotEvent.OnClientEvent:Connect(function()
    task.spawn(waitForLeafData)
end))

trackConnection(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(2)
    if State.StarEsp then
        buildStarEsp()
    end
end))

task.spawn(function()
    while not Unloaded do
        if State.AutoCollect and not Selling and not Busy then
            local root = getRoot()
            if root then
                local picked = collectAt(root.Position)
                if picked == 0 and State.AutoFarm and capacityLeft() > 0 and not Selling and not Busy then
                    local target = findNearestLeaf(root.Position)
                    if not target then
                        resyncAreas()
                        target = findNearestLeaf(root.Position)
                    end
                    if target then
                        teleportTo(target)
                        task.wait(State.Settle)
                    else
                        task.wait(2)
                    end
                end
            end
        end
        task.wait(State.Delay)
    end
end)

task.spawn(function()
    while not Unloaded do
        task.wait(0.5)
        if State.AutoSell and not Selling then
            local capacity = MaxHold.Value
            if capacity > 0 then
                local threshold = math.floor(capacity * State.SellPercent / 100)
                if hasInfiniteCapacity() then
                    threshold = capacity * 5
                end
                if Leaves.Value >= threshold then
                    sellNow()
                end
            end
        end
    end
end)

task.spawn(function()
    while not Unloaded do
        task.wait(2)
        local capacityLevel = UpgradeLevels:FindFirstChild("CapacityLevel")
        local basementLevel = UpgradeLevels:FindFirstChild("BasementCapacityLevel")
        local savingForBasement = State.AutoRebirth
            and capacityLevel and capacityLevel.Value >= 5
            and getRebirth() >= 1
            and basementLevel and basementLevel.Value < 4
        if State.AutoUpgrade and not savingForBasement then
            for _, name in ipairs(UPGRADE_LIST) do
                if Unloaded then
                    break
                end
                if not next(State.UpgradeFilter) or State.UpgradeFilter[name] then
                    if buyUpgrade(name) then
                        task.wait(0.3)
                    end
                end
            end
        end
        if State.AutoBuyRake and not savingForBasement then
            buyEquipment("Rake")
        end
        if State.AutoBuyBlower and not savingForBasement then
            buyEquipment("Blower")
        end
        if State.AutoRebirth and not Busy and not Selling then
            if savingForBasement then
                upgradeBasementCapacity()
            end
            if canRebirth() then
                RebirthEvent:FireServer()
                task.wait(6)
            end
        end
    end
end)

task.spawn(function()
    while not Unloaded do
        task.wait(5)
        if State.AutoStars and not Selling and not Busy then
            local left = starsLeft()
            if left > 0 then
                collectStars()
            end
        end
        if State.AutoDoors and not Selling and not Busy then
            useKeys()
        end
        if State.AutoClaimQuests then
            claimQuests()
        end
        if State.AutoEquipTitle then
            equipBestTitle()
        end
    end
end)

task.spawn(function()
    local lastCount = os.clock()
    local remaining = countRemaining()
    while not Unloaded do
        task.wait(1)
        if os.clock() - lastCount > 4 then
            lastCount = os.clock()
            remaining = countRemaining()
        end
        local left, total = starsLeft()
        local capacityText = hasInfiniteCapacity() and "Infinite" or formatNumber(MaxHold.Value)
        updateParagraph(StatsParagraph, "Status", table.concat({
            "Leaves: " .. formatNumber(Leaves.Value) .. " / " .. capacityText,
            "Cash: " .. formatNumber(Cash.Value) .. "   Rebirth: " .. getRebirth(),
            "Collected this session: " .. formatNumber(State.Collected),
            "Leaves left in selection: " .. formatNumber(remaining),
            "Plot cleared: " .. math.floor(clearRatio() * 1000) / 10 .. "%",
            "Rebirth: " .. rebirthBlocker()
        }, "\n"))

        local lines = {}
        for _, name in ipairs(UPGRADE_LIST) do
            local levelValue = UpgradeLevels:FindFirstChild(name .. "Level")
            local level = levelValue and levelValue.Value or 1
            local maxLevel = UpgradeManager.MAX_LEVEL or 5
            if level >= maxLevel then
                table.insert(lines, name .. ": MAX")
            else
                local cost = UpgradeManager.GetModifiedCost(LocalPlayer, name, level)
                table.insert(lines, name .. ": " .. level .. "/" .. maxLevel .. "  $" .. formatNumber(cost))
            end
        end
        updateParagraph(UpgradeParagraph, "Levels", table.concat(lines, "\n"))
        updateParagraph(StarParagraph, "Progress", "Collected: " .. (total - left) .. " / " .. total)

        local completed = CompletedQuests and #CompletedQuests:GetChildren() or 0
        local equipped = PlayerData:FindFirstChild("EquippedTitle")
        updateParagraph(QuestParagraph, "Quests", table.concat({
            "Ready to claim: " .. claimableQuests(),
            "Completed: " .. completed,
            "Title: " .. (equipped and equipped.Value ~= "" and equipped.Value or "none"),
            "Best owned: " .. (bestTitle() or "none")
        }, "\n"))
    end
end)

Fluent:Notify({
    Title = "Garden Cleaner Evolution",
    Content = "Hub loaded",
    SubContent = formatNumber(countRemaining()) .. " leaves available",
    Duration = 6
})

SaveManager:LoadAutoloadConfig()

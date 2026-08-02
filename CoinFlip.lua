if _G.CoinFlipHubUnload then
    pcall(_G.CoinFlipHubUnload)
    task.wait(0.2)
end

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 30)
if not Remotes then
    Fluent:Notify({ Title = "Coin Flip Hub", Content = "RemoteEvents not found. Wrong game?", Duration = 8 })
    return
end

local function grab(name)
    return Remotes:FindFirstChild(name)
end

local R = {
    Flip = grab("CoinFlipResult"),
    FlipOutcome = grab("FlipOutcome"),
    StatsChanged = grab("StatsChanged"),
    MoneyChanged = grab("MoneyChanged"),
    CritLanded = grab("CritLanded"),
    ItemDropped = grab("ItemDropped"),
    ChestDropped = grab("ChestDropped"),
    PotionDropped = grab("PotionDropped"),
    FrenzyActivated = grab("FrenzyActivated"),
    PityActivated = grab("PityActivated"),
    ShinyFlip = grab("ShinyFlip"),
    CycleChoiceOffer = grab("CycleChoiceOffer"),
    ChooseCycleBonus = grab("ChooseCycleBonus"),
    GetPlayerStats = grab("GetPlayerStats"),
    PurchaseUpgrade = grab("PurchaseUpgrade"),
    RebirthRequested = grab("RebirthRequested"),
    AscendRequested = grab("AscendRequested"),
    BuyAscensionPerk = grab("BuyAscensionPerk"),
    GetInventory = grab("GetInventory"),
    SellItem = grab("SellItem"),
    SellItems = grab("SellItems"),
    EquipItem = grab("EquipItem"),
    UnequipItem = grab("UnequipItem"),
    SetAutoSellRarity = grab("SetAutoSellRarity"),
    GetAutoSellRarities = grab("GetAutoSellRarities"),
    OpenChest = grab("OpenChest"),
    GetStash = grab("GetStash"),
    UsePotion = grab("UsePotion"),
    GetQuests = grab("GetQuests"),
    ClaimQuest = grab("ClaimQuest"),
    RerollDailyQuests = grab("RerollDailyQuests"),
    ClaimAllAchievementRewards = grab("ClaimAllAchievementRewards"),
    GetDailyLoginStatus = grab("GetDailyLoginStatus"),
    ClaimDailyLogin = grab("ClaimDailyLogin"),
    GetOfflineEarnings = grab("GetOfflineEarnings"),
    ClaimOfflineEarnings = grab("ClaimOfflineEarnings"),
    CheckGroupBonus = grab("CheckGroupBonus"),
    RedeemCode = grab("RedeemCode"),
    UnlockAutoFlip = grab("UnlockAutoFlip"),
}

local Config, QuestDefs, MoneyFormat
pcall(function() Config = require(ReplicatedStorage:WaitForChild("CoinFlipConfig", 10)) end)
pcall(function() QuestDefs = require(ReplicatedStorage:WaitForChild("QuestDefs", 10)) end)
pcall(function() MoneyFormat = require(ReplicatedStorage:WaitForChild("MoneyFormat", 10)) end)
Config = Config or {}

local UPGRADES = {
    { id = "CoinMultiplier", name = "Coin Multiplier" },
    { id = "HeadsChance", name = "Heads Chance" },
    { id = "FlipSpeed", name = "Flip Speed" },
    { id = "StreakPower", name = "Streak Power" },
    { id = "LuckyFlip", name = "Lucky Flip" },
    { id = "CritChance", name = "Crit Chance" },
    { id = "CritPower", name = "Crit Power" },
    { id = "FrenzyMastery", name = "Frenzy Mastery" },
}

local UPGRADE_NAMES, UPGRADE_BY_NAME = {}, {}
for _, u in ipairs(UPGRADES) do
    table.insert(UPGRADE_NAMES, u.name)
    UPGRADE_BY_NAME[u.name] = u.id
end

local RARITIES = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Secret", "Unobtainable" }
local RARITY_RANK = {}
for i, r in ipairs(RARITIES) do RARITY_RANK[r] = i end

local CHESTS = { "Basic", "Silver", "Legendary", "Exclusive" }
local QUEST_CATEGORIES = { daily = "Daily", weekly = "Weekly", milestone = "Milestone" }
local CYCLE_OPTIONS = {}
do
    local opts = Config.CycleChoice and Config.CycleChoice.Options
    if type(opts) == "table" then
        for _, o in ipairs(opts) do
            if type(o) == "table" and o.id then
                table.insert(CYCLE_OPTIONS, { id = o.id, name = o.name or o.id })
            end
        end
    end
    if #CYCLE_OPTIONS == 0 then
        CYCLE_OPTIONS = { { id = "lucky", name = "LUCKY CYCLE" }, { id = "magnet", name = "MAGNET CYCLE" }, { id = "head_start", name = "HEAD START" } }
    end
end
local CYCLE_NAMES, CYCLE_BY_NAME = {}, {}
for _, o in ipairs(CYCLE_OPTIONS) do
    table.insert(CYCLE_NAMES, o.name)
    CYCLE_BY_NAME[o.name] = o.id
end

local POTION_EFFECT_LABEL = {
    coinMult = "Coin Boost",
    dropLuckBonus = "Luck",
    xpBoost = "XP Boost",
    speedBoost = "Flip Speed",
    critBoost = "Crit Boost",
    headsBoost = "Heads Chance",
}

local function invoke(remote, ...)
    if not remote then return nil end
    local packed = table.pack(...)
    local ok, a, b = pcall(function()
        return remote:InvokeServer(table.unpack(packed, 1, packed.n))
    end)
    if not ok then return nil end
    return a, b
end

local function fire(remote, ...)
    if not remote then return end
    pcall(function(...) remote:FireServer(...) end, ...)
end

local Stats = {}

local flipCooldown = 1.2

local function pullStats()
    local s = invoke(R.GetPlayerStats)
    if type(s) == "table" then
        Stats = s
        flipCooldown = tonumber(s.flipCooldown) or flipCooldown
    end
    return Stats
end
pullStats()

local Session = {
    started = os.clock(),
    activeTime = 0,
    requests = 0,
    flips = 0,
    heads = 0,
    tails = 0,
    streak = 0,
    bestStreak = 0,
    crits = 0,
    shields = 0,
    frenzy = 0,
    pity = 0,
    shiny = 0,
    upgrades = 0,
    rebirths = 0,
    ascends = 0,
    perks = 0,
    quests = 0,
    chestsOpened = 0,
    potionsUsed = 0,
    itemsSold = 0,
    sellValue = 0,
    drops = 0,
    dropsByRarity = {},
    chestDrops = 0,
    potionDrops = 0,
    baseEarned = tonumber(Stats.totalEarnedCents) or 0,
    baseFlips = tonumber(Stats.totalFlips) or 0,
    earned = 0,
}

local function resetSession()
    local now = os.clock()
    for k, v in pairs(Session) do
        if type(v) == "number" then Session[k] = 0 end
    end
    Session.dropsByRarity = {}
    Session.started = now
    Session.baseEarned = tonumber(Stats.totalEarnedCents) or 0
    Session.baseFlips = tonumber(Stats.totalFlips) or 0
end

local function money(cents)
    cents = tonumber(cents) or 0
    if MoneyFormat and MoneyFormat.format then
        local ok, res = pcall(MoneyFormat.format, cents)
        if ok and type(res) == "string" then return res end
    end
    return string.format("$%.2f", cents / 100)
end

local function comma(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    return out
end

local function pct(v, digits)
    return string.format("%." .. (digits or 2) .. "f%%", (tonumber(v) or 0) * 100)
end

local function clockStr(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%dh %02dm %02ds", h, m, s) end
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

local function setOf(value)
    local out = {}
    if type(value) == "table" then
        for k, v in pairs(value) do
            if v == true then out[k] = true end
        end
    end
    return out
end

local State = {
    autoFlip = false,
    autoInterval = true,
    flipDelay = 0.2,
    smartPace = true,
    blockFX = true,

    autoUpgrade = false,
    upgradeTargets = { ["Coin Multiplier"] = true, ["Heads Chance"] = true, ["Flip Speed"] = true },
    buyMode = "MAX",
    priority = "Cheapest first",
    keepRebirth = true,

    autoRebirth = false,
    rebirthMult = 1,
    autoAscend = false,
    autoPerks = false,
    autoCycle = false,
    cyclePick = CYCLE_NAMES[1],

    autoQuests = false,
    autoAchievements = false,
    autoDaily = false,
    autoOffline = false,

    antiAfk = true,
    hud = false,
    notifyDrops = false,
    dropNotifyRarity = "Legendary",

    autoSell = false,
    sellRarities = {},
    syncAutoSell = false,
    autoChest = false,
    chestTypes = { Basic = true, Silver = true, Legendary = true, Exclusive = true },
    autoPotion = false,
    potionEffects = {},
    potionTier = "Lowest first",
    autoEquip = false,
}

local hudGui, hudBody, hudFrame

local nextFlipAt = 0
local lastOutcome = 0

local gameFlipConnections = {}
pcall(function()
    if getconnections and R.FlipOutcome then
        for _, c in ipairs(getconnections(R.FlipOutcome.OnClientEvent)) do
            table.insert(gameFlipConnections, c)
        end
    end
end)

local function setFlipVisuals(enabled)
    for _, c in ipairs(gameFlipConnections) do
        pcall(function()
            if enabled then c:Enable() else c:Disable() end
        end)
    end
end

if R.StatsChanged then
    R.StatsChanged.OnClientEvent:Connect(function(s)
        if type(s) == "table" and s.balanceCents then
            Stats = s
            flipCooldown = tonumber(s.flipCooldown) or flipCooldown
        end
    end)
end

if R.FlipOutcome then
    R.FlipOutcome.OnClientEvent:Connect(function(isHeads, consec)
        lastOutcome = os.clock()
        Session.flips = Session.flips + 1
        if isHeads == true then
            Session.heads = Session.heads + 1
            Session.streak = (tonumber(consec) or Session.streak) + 0
            if Session.streak > Session.bestStreak then Session.bestStreak = Session.streak end
        else
            Session.tails = Session.tails + 1
            Session.streak = 0
        end
        if State.smartPace then
            nextFlipAt = os.clock() + math.max(0.05, (flipCooldown or 1.2) * 0.7)
        end
    end)
end

if R.CritLanded then
    R.CritLanded.OnClientEvent:Connect(function() Session.crits = Session.crits + 1 end)
end
if R.FrenzyActivated then
    R.FrenzyActivated.OnClientEvent:Connect(function() Session.frenzy = Session.frenzy + 1 end)
end
if R.PityActivated then
    R.PityActivated.OnClientEvent:Connect(function() Session.pity = Session.pity + 1 end)
end
if R.ShinyFlip then
    R.ShinyFlip.OnClientEvent:Connect(function() Session.shiny = Session.shiny + 1 end)
end
if R.ChestDropped then
    R.ChestDropped.OnClientEvent:Connect(function() Session.chestDrops = Session.chestDrops + 1 end)
end
if R.PotionDropped then
    R.PotionDropped.OnClientEvent:Connect(function() Session.potionDrops = Session.potionDrops + 1 end)
end
if R.ItemDropped then
    R.ItemDropped.OnClientEvent:Connect(function(itemId, _, rarity, name)
        Session.drops = Session.drops + 1
        local r = tostring(rarity or "Common")
        Session.dropsByRarity[r] = (Session.dropsByRarity[r] or 0) + 1
        if State.notifyDrops then
            local need = RARITY_RANK[State.dropNotifyRarity] or 4
            if (RARITY_RANK[r] or 1) >= need then
                Fluent:Notify({
                    Title = r .. " drop",
                    Content = tostring(name or itemId or "Unknown item"),
                    Duration = 5,
                })
            end
        end
    end)
end

if R.CycleChoiceOffer and R.ChooseCycleBonus then
    R.CycleChoiceOffer.OnClientEvent:Connect(function()
        if not State.autoCycle then return end
        task.wait(0.5)
        local id = CYCLE_BY_NAME[State.cyclePick] or CYCLE_OPTIONS[1].id
        invoke(R.ChooseCycleBonus, id)
    end)
end

local afkConnection
local function setAntiAfk(on)
    if afkConnection then
        afkConnection:Disconnect()
        afkConnection = nil
    end
    if on then
        afkConnection = LocalPlayer.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end)
    end
end

local Window = Fluent:CreateWindow({
    Title = "Coin Flip Hub",
    SubTitle = "Fauna Studio | " .. tostring(game:GetService("MarketplaceService") and "UPDATE 2" or ""),
    Search = true,
    Icon = "circle-dollar-sign",
    TabWidth = 150,
    Size = UDim2.fromOffset(600, 470),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
    UserInfo = true,
    UserInfoTitle = LocalPlayer.DisplayName,
    UserInfoSubtitle = "Coin Flip",
    UserInfoSubtitleColor = Color3.fromRGB(255, 196, 76),
})

pcall(function()
    Fluent:CreateMinimizer({
        Icon = "circle-dollar-sign",
        Size = UDim2.fromOffset(44, 44),
        Position = UDim2.new(0, 24, 0, 120),
        Acrylic = false,
        Corner = 12,
        Draggable = true,
        Visible = true,
    })
end)

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "zap" }),
    Items = Window:AddTab({ Title = "Items", Icon = "package" }),
    Stats = Window:AddTab({ Title = "Stats", Icon = "bar-chart-3" }),
    Misc = Window:AddTab({ Title = "Misc", Icon = "wrench" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local FlipSection = Tabs.Main:AddSection("Auto Flip", "repeat")

local livePanel = FlipSection:AddParagraph({
    Title = "Live",
    Content = "Waiting for data...",
})

FlipSection:AddToggle("AutoFlip", {
    Title = "Auto Flip",
    Description = "Sends flip requests straight to the server, no animation needed",
    Default = false,
    Callback = function(v)
        State.autoFlip = v
        if v then
            nextFlipAt = 0
            if State.blockFX then setFlipVisuals(false) end
        else
            setFlipVisuals(true)
        end
    end,
})

FlipSection:AddToggle("AutoInterval", {
    Title = "Auto interval",
    Description = "Derives the request rate from your live flip cooldown, ignores the slider below",
    Default = true,
    Callback = function(v) State.autoInterval = v end,
})

FlipSection:AddSlider("FlipDelay", {
    Title = "Request interval",
    Description = "Manual seconds between requests. The server accepts one flip per cooldown, extras are ignored",
    Default = 0.2,
    Min = 0.05,
    Max = 1.5,
    Rounding = 2,
    Callback = function(v) State.flipDelay = v end,
})

FlipSection:AddToggle("SmartPace", {
    Title = "Smart pacing",
    Description = "Pauses requests while the server cooldown is still running",
    Default = true,
    Callback = function(v) State.smartPace = v end,
})

FlipSection:AddToggle("BlockFX", {
    Title = "Skip flip animation",
    Description = "Stops the coin spin and result queue from building up while farming",
    Default = true,
    Callback = function(v)
        State.blockFX = v
        setFlipVisuals(not (v and State.autoFlip))
    end,
})

FlipSection:AddButton({
    Title = "Unlock Auto Flip in game",
    Description = "Buys the in-game auto flip button, not required for this script",
    Callback = function()
        local ok = invoke(R.UnlockAutoFlip)
        Fluent:Notify({ Title = "Auto Flip", Content = ok and "Unlocked" or "Failed or already owned", Duration = 5 })
        pullStats()
    end,
})

local UpgradeSection = Tabs.Main:AddSection("Auto Upgrade", "trending-up")

local upgradePanel = UpgradeSection:AddParagraph({
    Title = "Upgrade levels",
    Content = "Waiting for data...",
})

UpgradeSection:AddToggle("AutoUpgrade", {
    Title = "Auto Upgrade",
    Description = "Buys the selected upgrades whenever they are affordable",
    Default = false,
    Callback = function(v) State.autoUpgrade = v end,
})

UpgradeSection:AddDropdown("UpgradeTargets", {
    Title = "Upgrades to buy",
    Values = UPGRADE_NAMES,
    Multi = true,
    Search = false,
    Default = { "Coin Multiplier", "Heads Chance", "Flip Speed" },
    Callback = function(v) State.upgradeTargets = setOf(v) end,
})

UpgradeSection:AddDropdown("BuyMode", {
    Title = "Buy amount",
    Values = { "1", "10", "25", "MAX" },
    Multi = false,
    Search = false,
    Default = 4,
    Callback = function(v) State.buyMode = v end,
})

UpgradeSection:AddDropdown("UpgradePriority", {
    Title = "Priority",
    Values = { "Cheapest first", "List order" },
    Multi = false,
    Search = false,
    Default = 1,
    Callback = function(v) State.priority = v end,
})

UpgradeSection:AddToggle("KeepRebirth", {
    Title = "Keep rebirth money",
    Description = "Never spends below the current rebirth cost",
    Default = true,
    Callback = function(v) State.keepRebirth = v end,
})

UpgradeSection:AddButton({
    Title = "Buy MAX on every upgrade",
    Callback = function()
        for _, u in ipairs(UPGRADES) do
            invoke(R.PurchaseUpgrade, u.id, "max")
            task.wait(0.06)
        end
        pullStats()
        Fluent:Notify({ Title = "Upgrades", Content = "Bought everything affordable", Duration = 4 })
    end,
})

local ProgressSection = Tabs.Main:AddSection("Progression", "sparkles")

local progressPanel = ProgressSection:AddParagraph({
    Title = "Rebirth / Ascension",
    Content = "Waiting for data...",
})

ProgressSection:AddToggle("AutoRebirth", {
    Title = "Auto Rebirth",
    Description = "Rebirths as soon as the cost is covered, unlocks the next coin",
    Default = false,
    Callback = function(v) State.autoRebirth = v end,
})

ProgressSection:AddSlider("RebirthMult", {
    Title = "Rebirth at cost x",
    Description = "Waits until the balance reaches this multiple of the rebirth cost",
    Default = 1,
    Min = 1,
    Max = 10,
    Rounding = 1,
    Callback = function(v) State.rebirthMult = v end,
})

ProgressSection:AddToggle("AutoAscend", {
    Title = "Auto Ascend",
    Description = "Ascends whenever the game reports it is available",
    Default = false,
    Callback = function(v) State.autoAscend = v end,
})

ProgressSection:AddToggle("AutoPerks", {
    Title = "Auto Ascension Perks",
    Description = "Spends ascension points following the game perk order",
    Default = false,
    Callback = function(v) State.autoPerks = v end,
})

ProgressSection:AddToggle("AutoCycle", {
    Title = "Auto Cycle Bonus",
    Description = "Picks the rebirth cycle bonus automatically",
    Default = false,
    Callback = function(v) State.autoCycle = v end,
})

ProgressSection:AddDropdown("CyclePick", {
    Title = "Preferred cycle bonus",
    Values = CYCLE_NAMES,
    Multi = false,
    Search = false,
    Default = 1,
    Callback = function(v) State.cyclePick = v end,
})

local ClaimSection = Tabs.Main:AddSection("Auto Claim", "gift")

ClaimSection:AddToggle("AutoQuests", {
    Title = "Auto Claim Quests",
    Description = "Daily, weekly and milestone quests",
    Default = false,
    Callback = function(v) State.autoQuests = v end,
})

ClaimSection:AddToggle("AutoAchievements", {
    Title = "Auto Claim Achievements",
    Default = false,
    Callback = function(v) State.autoAchievements = v end,
})

ClaimSection:AddToggle("AutoDaily", {
    Title = "Auto Daily Login",
    Default = false,
    Callback = function(v) State.autoDaily = v end,
})

ClaimSection:AddToggle("AutoOffline", {
    Title = "Auto Offline Earnings",
    Default = false,
    Callback = function(v) State.autoOffline = v end,
})

ClaimSection:AddButton({
    Title = "Claim everything now",
    Callback = function()
        task.spawn(function()
            local claimed = 0
            for key, cat in pairs(QUEST_CATEGORIES) do
                local q = invoke(R.GetQuests)
                local block = type(q) == "table" and q[key]
                local entries = type(block) == "table" and block.entries
                if type(entries) == "table" then
                    for _, e in ipairs(entries) do
                        if type(e) == "table" and not e.claimed then
                            if invoke(R.ClaimQuest, cat, e.id) then claimed = claimed + 1 end
                        end
                    end
                end
            end
            invoke(R.ClaimAllAchievementRewards)
            invoke(R.ClaimDailyLogin)
            invoke(R.ClaimOfflineEarnings)
            invoke(R.CheckGroupBonus)
            pullStats()
            Fluent:Notify({ Title = "Claim", Content = "Claimed " .. claimed .. " quests plus rewards", Duration = 5 })
        end)
    end,
})

local UtilSection = Tabs.Main:AddSection("Utility", "shield")

UtilSection:AddToggle("AntiAfk", {
    Title = "Anti AFK",
    Description = "Blocks the 20 minute idle kick and the in-game AFK teleport",
    Default = true,
    Callback = function(v)
        State.antiAfk = v
        setAntiAfk(v)
    end,
})

UtilSection:AddToggle("StatsHud", {
    Title = "Stats HUD",
    Description = "Draggable on-screen counter",
    Default = false,
    Callback = function(v) State.hud = v end,
})

UtilSection:AddToggle("NotifyDrops", {
    Title = "Notify on rare drops",
    Default = false,
    Callback = function(v) State.notifyDrops = v end,
})

UtilSection:AddDropdown("DropNotifyRarity", {
    Title = "Minimum rarity to notify",
    Values = RARITIES,
    Multi = false,
    Search = false,
    Default = 4,
    Callback = function(v) State.dropNotifyRarity = v end,
})

local SellSection = Tabs.Items:AddSection("Auto Sell", "coins")

SellSection:AddToggle("AutoSell", {
    Title = "Auto Sell",
    Description = "Sells unequipped items of the selected rarities",
    Default = false,
    Callback = function(v) State.autoSell = v end,
})

SellSection:AddDropdown("SellRarities", {
    Title = "Rarities to sell",
    Values = RARITIES,
    Multi = true,
    Search = false,
    Default = { "Common" },
    Callback = function(v) State.sellRarities = setOf(v) end,
})

SellSection:AddToggle("SyncAutoSell", {
    Title = "Also set the in-game auto sell",
    Description = "Mirrors the selection into the game own auto sell filter",
    Default = false,
    Callback = function(v)
        State.syncAutoSell = v
        task.spawn(function()
            for _, r in ipairs(RARITIES) do
                invoke(R.SetAutoSellRarity, r, v and (State.sellRarities[r] == true) or false)
                task.wait(0.05)
            end
        end)
    end,
})

SellSection:AddButton({
    Title = "Sell selected rarities now",
    Callback = function()
        task.spawn(function()
            local inv = invoke(R.GetInventory)
            local keys, value = {}, 0
            if type(inv) == "table" then
                for _, item in pairs(inv) do
                    if type(item) == "table" and item.key and not item.equipped and State.sellRarities[item.rarity] then
                        local base = tostring(item.key):gsub("\1%d+$", "")
                        for _ = 1, math.max(1, tonumber(item.count) or 1) do
                            table.insert(keys, base)
                            value = value + (tonumber(item.sell) or 0)
                        end
                    end
                end
            end
            if #keys == 0 then
                Fluent:Notify({ Title = "Auto Sell", Content = "Nothing to sell", Duration = 4 })
                return
            end
            invoke(R.SellItems, keys)
            Session.itemsSold = Session.itemsSold + #keys
            Session.sellValue = Session.sellValue + value
            pullStats()
            Fluent:Notify({ Title = "Auto Sell", Content = "Sold " .. #keys .. " items", Duration = 4 })
        end)
    end,
})

local ChestSection = Tabs.Items:AddSection("Chests", "box")

local chestPanel = ChestSection:AddParagraph({
    Title = "Owned chests",
    Content = "Waiting for data...",
})

ChestSection:AddToggle("AutoChest", {
    Title = "Auto Open Chests",
    Default = false,
    Callback = function(v) State.autoChest = v end,
})

ChestSection:AddDropdown("ChestTypes", {
    Title = "Chest types",
    Values = CHESTS,
    Multi = true,
    Search = false,
    Default = { "Basic", "Silver", "Legendary", "Exclusive" },
    Callback = function(v) State.chestTypes = setOf(v) end,
})

ChestSection:AddButton({
    Title = "Open all chests now",
    Callback = function()
        task.spawn(function()
            pullStats()
            local opened = 0
            local owned = type(Stats.chests) == "table" and Stats.chests or {}
            for _, id in ipairs(CHESTS) do
                local n = tonumber(owned[id]) or 0
                while n > 0 do
                    local batch = math.min(n, 10)
                    local res = invoke(R.OpenChest, id, batch)
                    if type(res) ~= "table" then break end
                    opened = opened + batch
                    n = n - batch
                    task.wait(0.1)
                end
            end
            Session.chestsOpened = Session.chestsOpened + opened
            pullStats()
            Fluent:Notify({ Title = "Chests", Content = "Opened " .. opened .. " chests", Duration = 4 })
        end)
    end,
})

local PotionSection = Tabs.Items:AddSection("Potions", "flask-conical")

local POTION_EFFECTS, POTION_STASH = {}, {}
do
    local stash = invoke(R.GetStash)
    if type(stash) == "table" then
        POTION_STASH = stash
        local seen = {}
        for id, def in pairs(stash) do
            if type(def) == "table" and def.effect and not seen[def.effect] then
                seen[def.effect] = true
                table.insert(POTION_EFFECTS, POTION_EFFECT_LABEL[def.effect] or def.effect)
            end
        end
    end
    if #POTION_EFFECTS == 0 then POTION_EFFECTS = { "Coin Boost", "Luck", "XP Boost", "Flip Speed" } end
    table.sort(POTION_EFFECTS)
end

local function labelToEffect(label)
    for raw, pretty in pairs(POTION_EFFECT_LABEL) do
        if pretty == label then return raw end
    end
    return label
end

local potionPanel = PotionSection:AddParagraph({
    Title = "Potion stash",
    Content = "Waiting for data...",
})

PotionSection:AddToggle("AutoPotion", {
    Title = "Auto Use Potions",
    Description = "Drinks an owned potion when no potion of that effect is active",
    Default = false,
    Callback = function(v) State.autoPotion = v end,
})

PotionSection:AddDropdown("PotionEffects", {
    Title = "Effects to keep active",
    Values = POTION_EFFECTS,
    Multi = true,
    Search = false,
    Default = {},
    Callback = function(v) State.potionEffects = setOf(v) end,
})

PotionSection:AddDropdown("PotionTier", {
    Title = "Tier order",
    Values = { "Lowest first", "Highest first" },
    Multi = false,
    Search = false,
    Default = 1,
    Callback = function(v) State.potionTier = v end,
})

local EquipSection = Tabs.Items:AddSection("Equipment", "swords")

EquipSection:AddToggle("AutoEquip", {
    Title = "Auto Equip Best",
    Description = "Fills free equip slots with the highest rarity items you own",
    Default = false,
    Callback = function(v) State.autoEquip = v end,
})

EquipSection:AddButton({
    Title = "Equip best now",
    Callback = function()
        task.spawn(function()
            local inv = invoke(R.GetInventory)
            if type(inv) ~= "table" then return end
            local slots = 1 + (tonumber(Stats.extraBackpackSlots) or 0)
            local pool, used = {}, 0
            for _, item in pairs(inv) do
                if type(item) == "table" and item.key then
                    if item.equipped then
                        used = used + (tonumber(item.count) or 1)
                    else
                        table.insert(pool, item)
                    end
                end
            end
            table.sort(pool, function(a, b)
                return (RARITY_RANK[a.rarity] or 0) > (RARITY_RANK[b.rarity] or 0)
            end)
            local free = slots - used
            local n = 0
            for _, item in ipairs(pool) do
                if free <= 0 then break end
                if invoke(R.EquipItem, item.key) then n = n + 1 end
                free = free - 1
                task.wait(0.08)
            end
            Fluent:Notify({ Title = "Equipment", Content = "Equipped " .. n .. " items", Duration = 4 })
        end)
    end,
})

local sessionPanel = Tabs.Stats:AddParagraph({ Title = "Session", Content = "..." })
local flipPanel = Tabs.Stats:AddParagraph({ Title = "Flips", Content = "..." })
local economyPanel = Tabs.Stats:AddParagraph({ Title = "Economy", Content = "..." })
local dropPanel = Tabs.Stats:AddParagraph({ Title = "Drops", Content = "..." })
local accountPanel = Tabs.Stats:AddParagraph({ Title = "Account", Content = "..." })

local statsText = ""

Tabs.Stats:AddButton({
    Title = "Copy statistics",
    Description = "Copies the full report to the clipboard",
    Callback = function()
        if setclipboard then
            setclipboard(statsText)
            Fluent:Notify({ Title = "Statistics", Content = "Copied to clipboard", Duration = 4 })
        else
            Fluent:Notify({ Title = "Statistics", Content = "Clipboard not supported", Duration = 4 })
        end
    end,
})

Tabs.Stats:AddButton({
    Title = "Reset session counters",
    Callback = function()
        resetSession()
        Fluent:Notify({ Title = "Statistics", Content = "Session reset", Duration = 3 })
    end,
})

local CodeSection = Tabs.Misc:AddSection("Codes", "ticket")

local codeValue = ""
CodeSection:AddInput("CodeInput", {
    Title = "Code",
    Default = "",
    Placeholder = "Enter a code",
    Numeric = false,
    Finished = false,
    Callback = function(v) codeValue = v end,
})

CodeSection:AddButton({
    Title = "Redeem",
    Callback = function()
        if codeValue == "" then return end
        local res = invoke(R.RedeemCode, codeValue)
        local msg = type(res) == "table" and res.message or "No response"
        Fluent:Notify({ Title = "Redeem", Content = tostring(msg), Duration = 6 })
        pullStats()
    end,
})

local ServerSection = Tabs.Misc:AddSection("Server", "globe")

ServerSection:AddButton({
    Title = "Rejoin server",
    Callback = function()
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
    end,
})

ServerSection:AddButton({
    Title = "Server hop",
    Description = "Jumps to another public server of this game",
    Callback = function()
        task.spawn(function()
            local ok, err = pcall(function()
                local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100"
                local data = HttpService:JSONDecode(game:HttpGet(url))
                local list = {}
                for _, s in ipairs(data.data or {}) do
                    if type(s.id) == "string" and s.id ~= game.JobId and (s.playing or 0) < (s.maxPlayers or 100) then
                        table.insert(list, s.id)
                    end
                end
                if #list == 0 then error("no servers found") end
                TeleportService:TeleportToPlaceInstance(game.PlaceId, list[math.random(1, #list)], LocalPlayer)
            end)
            if not ok then
                Fluent:Notify({ Title = "Server hop", Content = tostring(err), Duration = 6 })
            end
        end)
    end,
})

local HubSection = Tabs.Misc:AddSection("Hub", "power")

local function unloadHub()
    State.autoFlip = false
    State.autoUpgrade = false
    State.hud = false
    setFlipVisuals(true)
    setAntiAfk(false)
    _G.CoinFlipHubUnload = nil
    pcall(function()
        if hudGui then hudGui:Destroy() end
    end)
    pcall(function() Fluent:Destroy() end)
end

HubSection:AddButton({
    Title = "Unload hub",
    Description = "Stops every automation and closes the interface",
    Callback = unloadHub,
})

local function buildHud()
    if hudGui then return end
    local parent = CoreGui
    pcall(function() if gethui then parent = gethui() end end)

    hudGui = Instance.new("ScreenGui")
    hudGui.Name = "CoinFlipHudGui"
    hudGui.ResetOnSpawn = false
    hudGui.IgnoreGuiInset = true
    hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudGui.DisplayOrder = 999
    hudGui.Parent = parent

    hudFrame = Instance.new("Frame")
    hudFrame.Size = UDim2.fromOffset(232, 176)
    hudFrame.Position = UDim2.new(0, 18, 0, 210)
    hudFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    hudFrame.BackgroundTransparency = 0.15
    hudFrame.BorderSizePixel = 0
    hudFrame.Parent = hudGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = hudFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 196, 76)
    stroke.Thickness = 1
    stroke.Transparency = 0.4
    stroke.Parent = hudFrame

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -16, 0, 22)
    title.Position = UDim2.new(0, 8, 0, 6)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextColor3 = Color3.fromRGB(255, 196, 76)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "COIN FLIP HUB"
    title.Parent = hudFrame

    hudBody = Instance.new("TextLabel")
    hudBody.BackgroundTransparency = 1
    hudBody.Size = UDim2.new(1, -16, 1, -34)
    hudBody.Position = UDim2.new(0, 8, 0, 28)
    hudBody.Font = Enum.Font.Code
    hudBody.TextSize = 13
    hudBody.TextColor3 = Color3.fromRGB(235, 235, 240)
    hudBody.TextXAlignment = Enum.TextXAlignment.Left
    hudBody.TextYAlignment = Enum.TextYAlignment.Top
    hudBody.RichText = true
    hudBody.Text = ""
    hudBody.Parent = hudFrame

    local dragging, dragStart, startPos
    hudFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = hudFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            hudFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local function runtime()
    return os.clock() - Session.started
end

local function farmTime()
    return Session.activeTime > 1 and Session.activeTime or runtime()
end

local function earnedThisSession()
    local total = tonumber(Stats.totalEarnedCents) or 0
    return math.max(0, total - Session.baseEarned)
end

local function perHour(value)
    local t = farmTime()
    if t < 5 then return 0 end
    return value * 3600 / t
end

task.spawn(function()
    while not Fluent.Unloaded do
        local dt = RunService.Heartbeat:Wait()
        if State.autoFlip and R.Flip then
            Session.activeTime = Session.activeTime + dt
            local now = os.clock()
            if now >= nextFlipAt then
                fire(R.Flip)
                Session.requests = Session.requests + 1
                local interval = State.autoInterval
                    and math.clamp((flipCooldown or 1.2) * 0.3, 0.05, 0.4)
                    or math.max(0.05, State.flipDelay)
                nextFlipAt = now + interval
            end
        end
    end
end)

local function affordable(cost)
    local bal = tonumber(Stats.balanceCents) or 0
    local reserve = 0
    if State.keepRebirth and State.autoRebirth then
        reserve = tonumber(Stats.nextRebirthCost) or 0
        if tostring(Stats.nextCoinVariant) == "MAX" then reserve = 0 end
    end
    return bal - reserve >= cost
end

local function autoUpgradeTick()
    local costs = Stats.upgradeCosts
    local levels = Stats.upgrades or {}
    local maxes = Stats.upgradeMaxLevels or {}
    if type(costs) ~= "table" then return end

    local candidates = {}
    for _, u in ipairs(UPGRADES) do
        if State.upgradeTargets[u.name] then
            local cost = tonumber(costs[u.id])
            local lvl = tonumber(levels[u.id]) or 0
            local cap = tonumber(maxes[u.id])
            if cost and cost > 0 and (not cap or lvl < cap) then
                table.insert(candidates, { id = u.id, cost = cost })
            end
        end
    end
    if #candidates == 0 then return end
    if State.priority == "Cheapest first" then
        table.sort(candidates, function(a, b) return a.cost < b.cost end)
    end

    for _, c in ipairs(candidates) do
        if affordable(c.cost) then
            local amount = State.buyMode == "MAX" and "max" or (tonumber(State.buyMode) or 1)
            if amount == "max" and State.keepRebirth and State.autoRebirth then amount = 1 end
            local ok, newStats = invoke(R.PurchaseUpgrade, c.id, amount)
            if ok then
                Session.upgrades = Session.upgrades + 1
                if type(newStats) == "table" and newStats.balanceCents then Stats = newStats end
            elseif amount ~= 1 then
                local ok2, s2 = invoke(R.PurchaseUpgrade, c.id, 1)
                if ok2 then
                    Session.upgrades = Session.upgrades + 1
                    if type(s2) == "table" and s2.balanceCents then Stats = s2 end
                end
            end
            return
        end
    end
end

local function autoRebirthTick()
    if tostring(Stats.nextCoinVariant) == "MAX" then return end
    local cost = tonumber(Stats.nextRebirthCost) or 0
    if cost <= 0 then return end
    local bal = tonumber(Stats.balanceCents) or 0
    if bal >= cost * State.rebirthMult then
        local ok, newStats = invoke(R.RebirthRequested)
        if ok then
            Session.rebirths = Session.rebirths + 1
            if type(newStats) == "table" and newStats.balanceCents then Stats = newStats end
            Fluent:Notify({ Title = "Rebirth", Content = "Rebirth " .. tostring(Stats.rebirthCount or "?") .. " done", Duration = 4 })
        end
    end
end

local function autoAscendTick()
    if Stats.canAscend ~= true then return end
    local ok, newStats = invoke(R.AscendRequested)
    if ok then
        Session.ascends = Session.ascends + 1
        if type(newStats) == "table" and newStats.balanceCents then Stats = newStats end
        Fluent:Notify({ Title = "Ascension", Content = "Ascended", Duration = 5 })
    end
end

local function autoPerkTick()
    local perks = Config.Ascension and Config.Ascension.Perks
    local order = (Config.Ascension and Config.Ascension.PerkOrder) or {}
    if type(perks) ~= "table" then return end
    local points = tonumber(Stats.ascensionPoints) or 0
    if points <= 0 then return end
    local owned = Stats.ascensionPerks or {}
    for _, id in ipairs(order) do
        local def = perks[id]
        local lvl = tonumber(owned[id]) or 0
        if type(def) == "table" and lvl < (tonumber(def.maxLevel) or 0) then
            local cost = tonumber(def.costs and def.costs[lvl + 1]) or 1
            if points >= cost then
                local ok, newStats = invoke(R.BuyAscensionPerk, id)
                if ok then
                    Session.perks = Session.perks + 1
                    if type(newStats) == "table" and newStats.balanceCents then Stats = newStats end
                    return
                end
            end
        end
    end
end

task.spawn(function()
    while not Fluent.Unloaded do
        task.wait(0.8)
        local ok = pcall(function()
            if State.autoUpgrade then autoUpgradeTick() end
            if State.autoRebirth then autoRebirthTick() end
            if State.autoAscend then autoAscendTick() end
            if State.autoPerks then autoPerkTick() end
        end)
        if not ok then task.wait(1) end
    end
end)

local function autoQuestTick()
    local q = invoke(R.GetQuests)
    if type(q) ~= "table" then return end
    local byId = QuestDefs and QuestDefs.BY_ID
    for key, cat in pairs(QUEST_CATEGORIES) do
        local block = q[key]
        local entries = type(block) == "table" and block.entries
        if type(entries) == "table" then
            for _, e in ipairs(entries) do
                if type(e) == "table" and e.claimed == false then
                    local def = byId and byId[e.id]
                    local goal = def and tonumber(def.goal)
                    if not goal or (tonumber(e.progress) or 0) >= goal then
                        if invoke(R.ClaimQuest, cat, e.id) then
                            Session.quests = Session.quests + 1
                        end
                        task.wait(0.1)
                    end
                end
            end
        end
    end
end

local function autoSellTick()
    local inv = invoke(R.GetInventory)
    if type(inv) ~= "table" then return end
    local keys, value = {}, 0
    for _, item in pairs(inv) do
        if type(item) == "table" and item.key and not item.equipped and State.sellRarities[item.rarity] then
            local base = tostring(item.key):gsub("\1%d+$", "")
            for _ = 1, math.max(1, tonumber(item.count) or 1) do
                table.insert(keys, base)
                value = value + (tonumber(item.sell) or 0)
            end
        end
    end
    if #keys > 0 then
        invoke(R.SellItems, keys)
        Session.itemsSold = Session.itemsSold + #keys
        Session.sellValue = Session.sellValue + value
    end
end

local function autoChestTick()
    local owned = type(Stats.chests) == "table" and Stats.chests or {}
    for _, id in ipairs(CHESTS) do
        if State.chestTypes[id] then
            local n = tonumber(owned[id]) or 0
            if n > 0 then
                local batch = math.min(n, 10)
                if type(invoke(R.OpenChest, id, batch)) == "table" then
                    Session.chestsOpened = Session.chestsOpened + batch
                end
                task.wait(0.15)
            end
        end
    end
end

local function autoPotionTick()
    local stash = invoke(R.GetStash)
    if type(stash) ~= "table" then return end
    POTION_STASH = stash
    local wanted = {}
    for label in pairs(State.potionEffects) do
        wanted[labelToEffect(label)] = true
    end
    if not next(wanted) then return end

    local activeByEffect = {}
    for _, def in pairs(stash) do
        if type(def) == "table" and def.effect and (def.active == true or (tonumber(def.timeLeft) or 0) > 0) then
            activeByEffect[def.effect] = true
        end
    end

    for effect in pairs(wanted) do
        if not activeByEffect[effect] then
            local best
            for id, def in pairs(stash) do
                if type(def) == "table" and def.effect == effect and (tonumber(def.count) or 0) > 0 then
                    local order = tonumber(def.order) or 0
                    if not best then
                        best = { id = id, order = order }
                    elseif State.potionTier == "Highest first" then
                        if order > best.order then best = { id = id, order = order } end
                    else
                        if order < best.order then best = { id = id, order = order } end
                    end
                end
            end
            if best then
                if invoke(R.UsePotion, best.id) then
                    Session.potionsUsed = Session.potionsUsed + 1
                end
                task.wait(0.15)
            end
        end
    end
end

local function autoEquipTick()
    local inv = invoke(R.GetInventory)
    if type(inv) ~= "table" then return end
    local slots = 1 + (tonumber(Stats.extraBackpackSlots) or 0)
    local pool, used = {}, 0
    for _, item in pairs(inv) do
        if type(item) == "table" and item.key then
            if item.equipped then
                used = used + (tonumber(item.count) or 1)
            else
                table.insert(pool, item)
            end
        end
    end
    if used >= slots or #pool == 0 then return end
    table.sort(pool, function(a, b)
        return (RARITY_RANK[a.rarity] or 0) > (RARITY_RANK[b.rarity] or 0)
    end)
    local free = slots - used
    for _, item in ipairs(pool) do
        if free <= 0 then break end
        invoke(R.EquipItem, item.key)
        free = free - 1
        task.wait(0.1)
    end
end

task.spawn(function()
    while not Fluent.Unloaded do
        task.wait(8)
        pcall(function()
            if State.autoQuests then autoQuestTick() end
            if State.autoAchievements then invoke(R.ClaimAllAchievementRewards) end
            if State.autoDaily then
                local st = invoke(R.GetDailyLoginStatus)
                if type(st) == "table" and st.available == true then invoke(R.ClaimDailyLogin) end
            end
            if State.autoOffline then
                local amount = invoke(R.GetOfflineEarnings)
                if type(amount) == "number" and amount > 0 then invoke(R.ClaimOfflineEarnings) end
            end
            if State.autoSell then autoSellTick() end
            if State.autoChest then autoChestTick() end
            if State.autoPotion then autoPotionTick() end
            if State.autoEquip then autoEquipTick() end
        end)
    end
end)

task.spawn(function()
    while not Fluent.Unloaded do
        task.wait(4)
        pcall(pullStats)
    end
end)

local function buildStatsText()
    local t = runtime()
    local ft = farmTime()
    local earned = earnedThisSession()
    local total = Session.heads + Session.tails
    local headsPct = total > 0 and (Session.heads / total) or 0
    local fpm = ft > 5 and (Session.flips * 60 / ft) or 0
    local level = type(Stats.level) == "table" and Stats.level or {}

    local lines = {
        "=== COIN FLIP HUB REPORT ===",
        "Runtime: " .. clockStr(t) .. " | farming: " .. clockStr(Session.activeTime),
        "Flips: " .. comma(Session.flips) .. " (" .. string.format("%.1f", fpm) .. "/min)",
        "Requests sent: " .. comma(Session.requests),
        "Heads: " .. comma(Session.heads) .. " | Tails: " .. comma(Session.tails) .. " | Heads rate: " .. pct(headsPct),
        "Current streak: " .. Session.streak .. " | Best streak: " .. Session.bestStreak,
        "Crits: " .. comma(Session.crits) .. " | Frenzy: " .. Session.frenzy .. " | Pity: " .. Session.pity .. " | Shiny: " .. Session.shiny,
        "Earned: " .. money(earned) .. " (" .. money(perHour(earned)) .. "/h)",
        "Balance: " .. money(Stats.balanceCents) .. " | Lifetime: " .. money(Stats.totalEarnedCents),
        "Upgrades bought: " .. Session.upgrades .. " | Rebirths: " .. Session.rebirths .. " | Ascends: " .. Session.ascends,
        "Quests claimed: " .. Session.quests .. " | Perks: " .. Session.perks,
        "Drops: " .. Session.drops .. " | Chests found: " .. Session.chestDrops .. " | Potions found: " .. Session.potionDrops,
        "Chests opened: " .. Session.chestsOpened .. " | Potions used: " .. Session.potionsUsed,
        "Items sold: " .. Session.itemsSold,
        "Coin: " .. tostring(Stats.coinVariant) .. " | Rebirth: " .. tostring(Stats.rebirthCount) .. " | Ascension: " .. tostring(Stats.ascensionCount),
        "Level: " .. tostring(level[1] or "?") .. " (" .. tostring(level[2] or 0) .. "/" .. tostring(level[3] or 0) .. " XP)",
        "Coin multiplier: x" .. string.format("%.3f", tonumber(Stats.totalCoinMult) or 1),
        "Heads chance: " .. pct(Stats.headsChance or Stats.rawHeadsChance) .. " | Crit: " .. pct(Stats.critChance) .. " x" .. tostring(Stats.critMultiplier),
        "Flip cooldown: " .. string.format("%.2fs", tonumber(Stats.flipCooldown) or 0),
    }
    return table.concat(lines, "\n")
end

task.spawn(function()
    while not Fluent.Unloaded do
        task.wait(0.5)
        pcall(function()
            local t = runtime()
            local ft = farmTime()
            local total = Session.heads + Session.tails
            local headsPct = total > 0 and (Session.heads / total) or 0
            local fpm = ft > 5 and (Session.flips * 60 / ft) or 0
            local earned = earnedThisSession()
            local level = type(Stats.level) == "table" and Stats.level or {}

            livePanel:SetDesc(table.concat({
                "Balance: " .. money(Stats.balanceCents),
                "Flips: " .. comma(Session.flips) .. "  |  " .. string.format("%.1f", fpm) .. "/min",
                "Heads: " .. pct(headsPct) .. "  |  streak " .. Session.streak .. " (best " .. Session.bestStreak .. ")",
                "Earned: " .. money(earned) .. "  |  " .. money(perHour(earned)) .. "/h",
                "Server cooldown: " .. string.format("%.2fs", tonumber(Stats.flipCooldown) or 0),
            }, "\n"))

            local upLines = {}
            local costs = Stats.upgradeCosts or {}
            local levels = Stats.upgrades or {}
            local maxes = Stats.upgradeMaxLevels or {}
            for _, u in ipairs(UPGRADES) do
                local lvl = tonumber(levels[u.id]) or 0
                local cap = tonumber(maxes[u.id]) or 0
                local cost = tonumber(costs[u.id]) or -1
                local costText = cost > 0 and money(cost) or "MAXED"
                table.insert(upLines, string.format("%s: %d/%d  -  %s", u.name, lvl, cap, costText))
            end
            upgradePanel:SetDesc(table.concat(upLines, "\n"))

            local nextCost = tonumber(Stats.nextRebirthCost) or 0
            local bal = tonumber(Stats.balanceCents) or 0
            local progress = nextCost > 0 and math.min(1, bal / nextCost) or 1
            progressPanel:SetDesc(table.concat({
                "Rebirth " .. tostring(Stats.rebirthCount or 0) .. "  |  coin: " .. tostring(Stats.coinVariant),
                "Next coin: " .. tostring(Stats.nextCoinVariant) .. " for " .. money(nextCost) .. "  (" .. pct(progress, 1) .. ")",
                "Ascension " .. tostring(Stats.ascensionCount or 0) .. "  |  points: " .. tostring(Stats.ascensionPoints or 0),
                "Ascend at rebirth " .. tostring(Stats.ascendRequirement or "?") .. "  |  ready: " .. tostring(Stats.canAscend == true),
                "Level " .. tostring(level[1] or "?") .. "  (" .. tostring(level[2] or 0) .. "/" .. tostring(level[3] or 0) .. " XP)",
            }, "\n"))

            local chestLines = {}
            local owned = type(Stats.chests) == "table" and Stats.chests or {}
            for _, id in ipairs(CHESTS) do
                table.insert(chestLines, id .. ": " .. tostring(tonumber(owned[id]) or 0))
            end
            table.insert(chestLines, "Opened this session: " .. Session.chestsOpened)
            chestPanel:SetDesc(table.concat(chestLines, "\n"))

            local potLines, shown = {}, 0
            for id, def in pairs(POTION_STASH) do
                if type(def) == "table" and (tonumber(def.count) or 0) > 0 and shown < 8 then
                    shown = shown + 1
                    table.insert(potLines, string.format("%s x%d%s", tostring(def.name or id), tonumber(def.count) or 0, def.active and " (active)" or ""))
                end
            end
            if #potLines == 0 then potLines = { "No potions owned" } end
            table.insert(potLines, "Used this session: " .. Session.potionsUsed)
            potionPanel:SetDesc(table.concat(potLines, "\n"))

            sessionPanel:SetDesc(table.concat({
                "Runtime: " .. clockStr(t) .. "  |  farming: " .. clockStr(Session.activeTime),
                "Requests sent: " .. comma(Session.requests) .. "  |  accepted flips: " .. comma(Session.flips),
                "Upgrades: " .. Session.upgrades .. "  |  rebirths: " .. Session.rebirths .. "  |  ascends: " .. Session.ascends,
                "Perks: " .. Session.perks .. "  |  quests claimed: " .. Session.quests,
            }, "\n"))

            flipPanel:SetDesc(table.concat({
                "Flips: " .. comma(Session.flips) .. "  (" .. string.format("%.1f", fpm) .. "/min, " .. comma(math.floor(perHour(Session.flips))) .. "/h)",
                "Heads: " .. comma(Session.heads) .. "  |  Tails: " .. comma(Session.tails),
                "Heads rate: " .. pct(headsPct) .. "  |  game chance: " .. pct(Stats.headsChance or Stats.rawHeadsChance),
                "Streak: " .. Session.streak .. "  |  best: " .. Session.bestStreak .. "  |  record: " .. tostring(Stats.highestHeadsStreak or 0),
                "Crits: " .. comma(Session.crits) .. "  |  frenzy: " .. Session.frenzy .. "  |  pity: " .. Session.pity .. "  |  shiny: " .. Session.shiny,
                "Lifetime flips: " .. comma(Stats.totalFlips or 0),
            }, "\n"))

            economyPanel:SetDesc(table.concat({
                "Balance: " .. money(Stats.balanceCents),
                "Earned this session: " .. money(earned),
                "Rate: " .. money(perHour(earned)) .. " per hour",
                "Per flip: " .. money(Session.flips > 0 and earned / Session.flips or 0),
                "Lifetime earned: " .. money(Stats.totalEarnedCents),
                "Coin multiplier: x" .. string.format("%.3f", tonumber(Stats.totalCoinMult) or 1),
                "Items sold: " .. Session.itemsSold,
            }, "\n"))

            local dropLines = { "Items: " .. Session.drops .. "  |  chests: " .. Session.chestDrops .. "  |  potions: " .. Session.potionDrops }
            for _, r in ipairs(RARITIES) do
                local n = Session.dropsByRarity[r]
                if n and n > 0 then table.insert(dropLines, r .. ": " .. n) end
            end
            table.insert(dropLines, "Index discovered: " .. tostring(Stats.discoveredCount or 0))
            table.insert(dropLines, "Drop luck bonus: " .. pct(Stats.dropLuckBonus))
            dropPanel:SetDesc(table.concat(dropLines, "\n"))

            accountPanel:SetDesc(table.concat({
                "Coin: " .. tostring(Stats.coinVariant) .. "  |  rebirths: " .. tostring(Stats.rebirthCount or 0),
                "Ascensions: " .. tostring(Stats.ascensionCount or 0) .. "  |  points: " .. tostring(Stats.ascensionPoints or 0),
                "Crit: " .. pct(Stats.critChance) .. " for x" .. tostring(Stats.critMultiplier or 1),
                "Streak bonus: " .. pct(Stats.streakBonus) .. "  |  shield: " .. tostring(Stats.streakShieldAvailable == true),
                "Refinery shards: " .. tostring(Stats.refineryShards or 0),
                "Equip slots: " .. tostring(1 + (tonumber(Stats.extraBackpackSlots) or 0)),
                "Flip cooldown: " .. string.format("%.2fs", tonumber(Stats.flipCooldown) or 0),
            }, "\n"))

            statsText = buildStatsText()

            if State.hud then
                buildHud()
                if hudGui then
                    hudGui.Enabled = true
                    hudBody.Text = table.concat({
                        "Time    " .. clockStr(Session.activeTime),
                        "Flips   " .. comma(Session.flips),
                        "Rate    " .. string.format("%.1f", fpm) .. "/min",
                        "Heads   " .. pct(headsPct, 1),
                        "Streak  " .. Session.streak .. " / " .. Session.bestStreak,
                        "Earned  " .. money(earned),
                        "Per h   " .. money(perHour(earned)),
                        "Bal     " .. money(Stats.balanceCents),
                        "Reb     " .. tostring(Stats.rebirthCount or 0) .. "  Drops " .. Session.drops,
                    }, "\n")
                end
            elseif hudGui then
                hudGui.Enabled = false
            end
        end)
    end
end)

setAntiAfk(true)
_G.CoinFlipHubUnload = unloadHub

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("CoinFlipHub")
SaveManager:SetFolder("CoinFlipHub/coinflip")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

Fluent:Notify({
    Title = "Coin Flip Hub",
    Content = "Loaded. Enable Auto Flip in the Main tab.",
    SubContent = "Server cooldown: " .. string.format("%.2fs", tonumber(Stats.flipCooldown) or 1.2),
    Duration = 7,
})

SaveManager:LoadAutoloadConfig()

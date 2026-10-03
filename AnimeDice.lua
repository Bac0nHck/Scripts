if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10708913337 and game.PlaceId ~= 113290951185459 then
    error("Anime Dice: this game is not supported.", 0)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local VirtualUser = game:GetService("VirtualUser")
local Player = Players.LocalPlayer
local Environment = type(getgenv) == "function" and getgenv() or _G
local AppKey = "AnimeDiceAirflow"

local Previous = Environment[AppKey]
if type(Previous) == "table" and type(Previous.Unload) == "function" then
    pcall(Previous.Unload, Previous)
end

local Framework = ReplicatedStorage:WaitForChild("Framework", 60)
local Network = ReplicatedStorage:WaitForChild("Network", 60)
if not Framework or not Network then
    error("Anime Dice: the game framework did not load.", 0)
end
local readyDeadline = os.clock() + 60
while not Framework:GetAttribute("IsLoaded") and os.clock() < readyDeadline do
    task.wait(0.25)
end

local Features = Framework:WaitForChild("Features")
local Modules = {}
local modulesLoaded, modulesError = pcall(function()
    Modules.Data = require(Features.Data.DataController)
    Modules.Buffs = require(Features.Buffs.BuffController)
    Modules.Registry = require(Features.Inventory.EntryRegistry)
    Modules.UnitUtil = require(Features.Inventory.Kinds.Unit.UnitUtil)
    Modules.UnitController = require(Features.Inventory.Kinds.Unit.UnitController)
    Modules.Dice = require(Features.Rolling.Dice)
    Modules.Cutscene = require(Features.Rolling.RollCutscene)
    Modules.HUD = require(Features.UI.HUDController)
    Modules.UI = require(Features.UI.UIReferences)
    Modules.Upgrades = require(Features.Upgrades.Upgrades)
    Modules.Tree = require(Features.Upgrades.TreeStructure)
    Modules.Rebirths = require(Features.Rebirth.Rebirths)
    Modules.Daily = require(Features.Rewards.DailyRewardConfig)
    Modules.Group = require(Features.Rewards.GroupRewardConfig)
    Modules.Quests = require(Features.Quests.QuestConfig)
    Modules.Towers = require(Features.Towers.Towers)
    Modules.TowerRefs = require(Features.Towers.TowerRefs)
    Modules.Traits = require(Features.Traits.Traits)
    Modules.Grades = require(Features.Grades.Grades)
    Modules.Plot = require(Features.Plot.PlotController)
    Modules.PlotConfig = require(Features.Plot.PlotConfig)
    Modules.Format = require(ReplicatedStorage.Packages.NumberFormatter)
end)
if not modulesLoaded then
    error("Anime Dice: failed to read game modules - " .. tostring(modulesError), 0)
end

local function findRemote(...)
    local current = Network
    for _, name in ipairs({...}) do
        current = current and current:FindFirstChild(name)
    end
    return current
end

local Remotes = {
    RollDice = findRemote("RollService", "RF", "RollDice"),
    SetAutoRoll = findRemote("RollService", "RE", "SetAutoRoll"),
    BuyDice = findRemote("DiceShopService", "RE", "BuyDice"),
    EquipDice = findRemote("DiceShopService", "RE", "EquipDice"),
    CollectBalance = findRemote("PlotService", "RE", "CollectBalance"),
    LevelUpSlot = findRemote("PlotService", "RE", "LevelUpSlot"),
    EquipBest = findRemote("PlotService", "RE", "EquipBest"),
    SellInventory = findRemote("SellService", "RF", "SellInventory"),
    BuyUpgrade = findRemote("RE", "BuyUpgrade"),
    Rebirth = findRemote("RebirthService", "RE", "Rebirth"),
    DailyClaim = findRemote("DailyRewardService", "RE", "Claim"),
    GroupClaim = findRemote("GroupRewardService", "RE", "Claim"),
    OfflineClaim = findRemote("OfflineEarningsService", "RE", "Claim"),
    QuestClaim = findRemote("QuestService", "RE", "Claim"),
    UseSpin = findRemote("SpinService", "RE", "Use"),
    UseBoost = findRemote("BoostService", "RE", "Use"),
    PlayTower = findRemote("Towers", "RF", "PlayTower"),
    CompleteFloor = findRemote("Towers", "RF", "CompleteTowerFloor"),
    CancelTower = findRemote("Towers", "RF", "CancelTower"),
    EquipBestTeam = findRemote("Towers", "RE", "EquipBestTowerTeam"),
    RollTrait = findRemote("TraitService", "RE", "Roll"),
    RollGrade = findRemote("GradeService", "RE", "Roll"),
}

local RarityOrder = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Divine", "Exotic", "Celestial", "Secret I", "Secret II", "Heavenly"}
local RarityRank = {}
for index, name in ipairs(RarityOrder) do
    RarityRank[name] = index
end
local SellNames = {"Off"}
for index = 2, #RarityOrder do
    table.insert(SellNames, RarityOrder[index])
end

local DiceNames = {}
for name, config in pairs(Modules.Dice.GetAll()) do
    if type(config) == "table" and type(config.price) == "number" and type(config.luck) == "number" then
        table.insert(DiceNames, name)
    end
end
table.sort(DiceNames, function(a, b)
    return Modules.Dice.Get(a).luck < Modules.Dice.Get(b).luck
end)

local TowerNames = {}
for name in pairs(Modules.Towers.GetAll()) do
    table.insert(TowerNames, name)
end
table.sort(TowerNames, function(a, b)
    local first, second = Modules.Towers.Get(a), Modules.Towers.Get(b)
    local x, y = first and first.order or 0, second and second.order or 0
    if x == y then
        return a < b
    end
    return x < y
end)

local function orderedNames(source)
    local names = {}
    for name, config in pairs(source) do
        if type(config) == "table" then
            table.insert(names, name)
        end
    end
    table.sort(names, function(a, b)
        local x, y = source[a].order or 0, source[b].order or 0
        if x == y then
            return a < b
        end
        return x < y
    end)
    return names
end

local TraitOptions = {"Any"}
for _, name in ipairs(orderedNames(Modules.Traits)) do
    table.insert(TraitOptions, name)
end
local GradeOptions = {"Any"}
for _, name in ipairs(orderedNames(Modules.Grades)) do
    table.insert(GradeOptions, name)
end

local ZoneOrder = {"HubArea", "DiceShop", "Shop", "ShopArea", "Selling", "Quests", "Towers", "Traits", "Grades", "Trade", "Fusing"}

local Airflow = loadstring(game:HttpGet("https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"))()

local App = {
    Alive = true,
    Connections = {},
    Controls = {},
    Features = {},
    State = {},
    Tokens = {},
    Original = {},
    Collisions = {},
    Prompts = {},
    WarnedAt = {},
    Values = {
        TargetDice = DiceNames[#DiceNames],
        SellBelow = "Off",
        Tower = TowerNames[1],
        UnitKey = nil,
        UntilTrait = "Any",
        UntilGrade = "Any",
        WalkSpeed = 24,
        JumpPower = 50,
        FlySpeed = 50,
        Gravity = math.floor(workspace.Gravity + 0.5),
        MinZoom = 0,
        MaxZoom = math.floor(Player.CameraMaxZoomDistance + 0.5),
        FOV = 70,
    },
    Tower = {
        Active = false,
        Busy = false,
        Ending = false,
        Name = nil,
        Floor = 0,
        Best = 0,
        Runs = 0,
        NextAt = 0,
        RetryAt = 0,
        Rewards = {},
        LastRewards = nil,
        Message = "Idle",
    },
    Units = {Options = {"None"}, Map = {}, Labels = {}},
}
Environment[AppKey] = App

function App:Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self.Connections, connection)
    return connection
end

function App:Notify(title, content, kind)
    if self.Alive and self.Window then
        pcall(function()
            self.Window:Notify({Title = title, Content = content, Type = kind or "Info", Duration = 4})
        end)
    end
end

function App:Warn(key, message)
    local now = os.clock()
    if now >= (self.WarnedAt[key] or 0) then
        self.WarnedAt[key] = now + 15
        warn("[Anime Dice] " .. key .. ": " .. tostring(message))
    end
end

function App:Format(value)
    local ok, text = pcall(Modules.Format.FormatCompact, tonumber(value) or 0)
    return ok and tostring(text) or tostring(value)
end

function App:Data()
    local ok, data = pcall(Modules.Data)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

function App:Fire(remote, ...)
    if not remote then
        return false
    end
    return (pcall(remote.FireServer, remote, ...))
end

function App:Invoke(remote, ...)
    if not remote then
        return nil
    end
    local result = table.pack(pcall(remote.InvokeServer, remote, ...))
    if result[1] then
        return table.unpack(result, 2, result.n)
    end
    return nil
end

function App:Buff(name)
    local getter = self.Original.GetBuff or Modules.Buffs.GetBuff
    local ok, value = pcall(getter, name)
    return ok and tonumber(value) or nil
end

function App:Amount(data, name)
    local entry = data and data.Inventory and data.Inventory[name]
    return entry and tonumber(entry.amount) or 0
end

function App:UnitConfig(entry)
    if type(entry) ~= "table" or type(entry.name) ~= "string" then
        return nil
    end
    local config = Modules.Registry.getEntryConfig(entry.name)
    if config and config.kind == "Unit" then
        return config
    end
    return nil
end

function App:EntryKind(entry)
    if type(entry) ~= "table" or type(entry.name) ~= "string" then
        return nil
    end
    local config = Modules.Registry.getEntryConfig(entry.name)
    return config and config.kind, config
end

function App:Character()
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if root and humanoid then
        return character, root, humanoid
    end
    return nil
end

function App:Slot(data, index)
    local slots = data.Slots or {}
    return slots[tostring(index)] or slots[index]
end

function App:SlotUnlocked(data, index)
    local ok, requirement = pcall(Modules.PlotConfig.GetSlotRebirthRequirement, index)
    return ok and (tonumber(data.Rebirth) or 0) >= (tonumber(requirement) or 0)
end

function App:Spendable(data)
    local money = tonumber(data.Money) or 0
    if self.State.AutoRebirth then
        local nextRebirth = Modules.Rebirths.GetNext(tonumber(data.Rebirth) or 0)
        if nextRebirth and money >= nextRebirth.cost then
            return 0
        end
    end
    return money
end

function App:Feature(key, definition)
    self.Features[key] = definition
    self.State[key] = false
end

function App:SetFeature(key, value)
    local feature = self.Features[key]
    if not feature or not self.Alive then
        return
    end
    value = value == true
    local control = self.Controls[key]
    if control and control:Get() ~= value then
        control:Set(value, true)
    end
    if self.State[key] == value then
        return
    end
    self.State[key] = value
    self.Tokens[key] = (self.Tokens[key] or 0) + 1
    local token = self.Tokens[key]
    if value then
        if feature.Enable then
            local ok, err = pcall(feature.Enable)
            if not ok then
                self:Warn(key, err)
            end
        end
        if feature.Step then
            task.spawn(function()
                while self.Alive and self.State[key] and self.Tokens[key] == token do
                    local ok, delay = pcall(feature.Step)
                    if not ok then
                        self:Warn(key, delay)
                        delay = 1
                    end
                    if not (self.Alive and self.State[key] and self.Tokens[key] == token) then
                        break
                    end
                    task.wait(tonumber(delay) or feature.Interval or 1)
                end
            end)
        end
    elseif feature.Disable then
        local ok, err = pcall(feature.Disable)
        if not ok then
            self:Warn(key, err)
        end
    end
end

function App:SyncFeature(key, value)
    if not self.Alive then
        return
    end
    self.State[key] = value == true
    local control = self.Controls[key]
    if control and control:Get() ~= self.State[key] then
        control:Set(self.State[key], true)
    end
end

function App:SyncGameState()
    if os.clock() < (self.AutoRollGrace or 0) then
        return
    end
    local data = self:Data()
    if data and self.State.ServerAutoRoll ~= (data.AutoRoll == true) then
        self:SyncFeature("ServerAutoRoll", data.AutoRoll == true)
    end
end

function App:InstallFastRoll()
    if self.FastRollHook then
        return
    end
    local original = Modules.Buffs.GetBuff
    self.Original.GetBuff = original
    local hook = function(name, ...)
        local value = original(name, ...)
        if name == "Roll Duration" and App.Alive and App.State.FastRoll and type(value) == "number" then
            return value * 0.68
        end
        return value
    end
    self.FastRollHook = hook
    Modules.Buffs.GetBuff = hook
end

function App:RemoveFastRoll()
    if self.FastRollHook and Modules.Buffs.GetBuff == self.FastRollHook then
        Modules.Buffs.GetBuff = self.Original.GetBuff
    end
    self.FastRollHook = nil
end

function App:RollFrames()
    local rolling = Modules.UI.Root:FindFirstChild("Rolling")
    local frames = {}
    if rolling then
        for _, name in ipairs({"Frame", "DarkBackground", "Options"}) do
            local object = rolling:FindFirstChild(name)
            if object and object:IsA("GuiObject") then
                table.insert(frames, object)
            end
        end
    end
    return frames
end

function App:InstallSkip()
    if self.SkipInstalled then
        return
    end
    self.SkipInstalled = true
    local hud = Modules.HUD
    local hideAll = hud.hideAll
    self.Original.HideAll = hideAll
    local hook = function(reason, ...)
        if reason == "rolling" and App.Alive and App.State.SkipAnimation then
            return
        end
        return hideAll(reason, ...)
    end
    self.HideHook = hook
    hud.hideAll = hook
    if type(hookfunction) == "function" and type(Modules.Cutscene) == "function" then
        local original
        local ok = pcall(function()
            original = hookfunction(Modules.Cutscene, function(...)
                if App.Alive and App.State.SkipAnimation then
                    return
                end
                return original(...)
            end)
        end)
        self.CutsceneHooked = ok and original ~= nil
    end
    for _, object in ipairs(self:RollFrames()) do
        self:Connect(object:GetPropertyChangedSignal("Visible"), function()
            if App.State.SkipAnimation and object.Visible then
                object.Visible = false
            end
        end)
    end
end

function App:RemoveSkip()
    if self.HideHook and Modules.HUD.hideAll == self.HideHook then
        Modules.HUD.hideAll = self.Original.HideAll
    end
    self.HideHook = nil
    if self.CutsceneHooked and type(restorefunction) == "function" then
        pcall(restorefunction, Modules.Cutscene)
    end
    self.CutsceneHooked = false
end

function App:InventoryFull(data)
    local count = 0
    for _, entry in pairs(data.Inventory or {}) do
        if self:UnitConfig(entry) then
            count += 1
        end
    end
    local pending = data.PendingTrade
    if type(pending) == "table" and not pending.applied then
        count += tonumber(pending.reservedUnits) or 0
    end
    local storage = self:Buff("Unit Storage") or 100
    local rolls = self:Buff("Rolls") or 1
    return storage + rolls - 1 <= count
end

function App:AutoRollStep()
    local data = self:Data()
    if not data then
        return 1
    end
    if self:InventoryFull(data) then
        if os.clock() >= (self.FullNoticeAt or 0) then
            self.FullNoticeAt = os.clock() + 45
            self:Notify("Inventory full", "Rolling is paused until you have free unit storage. Auto Sell can clear junk units.", "Warning")
        end
        return 2
    end
    local results = self:Invoke(Remotes.RollDice)
    if type(results) == "table" then
        return math.max(self:Buff("Roll Duration") or 2.5, 0.1) + 0.03
    end
    return 0.35
end

function App:AutoDiceStep()
    local data = self:Data()
    if not data then
        return 1
    end
    local owned = data.OwnedDice or {}
    local bestName, bestLuck = nil, 0
    for _, name in ipairs(DiceNames) do
        local config = Modules.Dice.Get(name)
        if owned[name] and config.luck > bestLuck then
            bestName, bestLuck = name, config.luck
        end
    end
    local limit = table.find(DiceNames, self.Values.TargetDice) or #DiceNames
    local money = self:Spendable(data)
    local choice
    for index = 1, limit do
        local name = DiceNames[index]
        local config = Modules.Dice.Get(name)
        if not owned[name] and config.luck > bestLuck and config.price <= money then
            choice = name
        end
    end
    if choice then
        self:Fire(Remotes.BuyDice, choice)
        task.wait(1)
        local fresh = self:Data()
        if fresh and fresh.OwnedDice and fresh.OwnedDice[choice] then
            self:Notify("Dice purchased", choice .. " dice is now equipped.", "Success")
        end
        return 1
    end
    local current = type(data.Dice) == "string" and Modules.Dice.Get(data.Dice)
    if bestName and data.Dice ~= bestName and (not current or current.luck < bestLuck) then
        self:Fire(Remotes.EquipDice, bestName)
        return 1.5
    end
    return 2
end

function App:CollectStep()
    local data = self:Data()
    if not data then
        return 1
    end
    for key, slot in pairs(data.Slots or {}) do
        local index = tonumber(key)
        if index and type(slot) == "table" and (tonumber(slot.balance) or 0) > 0 and self:SlotUnlocked(data, index) then
            self:Fire(Remotes.CollectBalance, index)
        end
    end
    return 2
end

function App:LevelStep()
    local data = self:Data()
    if not data then
        return 1
    end
    local money = self:Spendable(data)
    local bestIndex, bestPrice
    for key, slot in pairs(data.Slots or {}) do
        local index = tonumber(key)
        if index and type(slot) == "table" and slot.unitId and self:SlotUnlocked(data, index) then
            local entry = data.Inventory and data.Inventory[slot.unitId]
            if self:UnitConfig(entry) then
                local ok, price = pcall(Modules.UnitUtil.GetLevelPrice, entry.name, entry.attributes or {})
                price = ok and tonumber(price) or nil
                if price and price <= money and (not bestPrice or price < bestPrice) then
                    bestIndex, bestPrice = index, price
                end
            end
        end
    end
    if bestIndex then
        self:Fire(Remotes.LevelUpSlot, bestIndex)
        return 0.2
    end
    return 1
end

function App:EquipBestStep()
    local data = self:Data()
    if not data then
        return 2
    end
    local units = {}
    for key, entry in pairs(data.Inventory or {}) do
        local config = self:UnitConfig(entry)
        if config then
            local ok, income = pcall(config.income, entry.attributes or {})
            table.insert(units, {Key = key, Income = ok and tonumber(income) or 0})
        end
    end
    table.sort(units, function(a, b)
        if a.Income == b.Income then
            return a.Key < b.Key
        end
        return a.Income > b.Income
    end)
    local unlocked = {}
    for index = 1, Modules.PlotConfig.GetMaxSlots() do
        if self:SlotUnlocked(data, index) then
            table.insert(unlocked, index)
        end
    end
    local wanted = {}
    for index = 1, math.min(#units, #unlocked) do
        wanted[units[index].Key] = true
    end
    local changed = false
    for _, index in ipairs(unlocked) do
        local slot = self:Slot(data, index)
        local unitId = type(slot) == "table" and slot.unitId
        if unitId then
            if wanted[unitId] then
                wanted[unitId] = nil
            else
                changed = true
            end
        end
    end
    if changed or next(wanted) then
        self:Fire(Remotes.EquipBest)
        return 5
    end
    return 3
end

function App:EquippedUnit()
    local ok, key = pcall(function()
        return Modules.UnitController.EquippedUnit()
    end)
    return ok and key or nil
end

function App:JunkKeys(limit)
    local data = self:Data()
    if not data then
        return {}
    end
    local keep = {}
    for _, slot in pairs(data.Slots or {}) do
        if type(slot) == "table" and slot.unitId then
            keep[slot.unitId] = true
        end
    end
    for _, key in pairs(data.TowerTeam or {}) do
        keep[key] = true
    end
    local equipped = self:EquippedUnit()
    if equipped then
        keep[equipped] = true
    end
    if self.Values.UnitKey then
        keep[self.Values.UnitKey] = true
    end
    local keys = {}
    for key, entry in pairs(data.Inventory or {}) do
        local config = self:UnitConfig(entry)
        local attributes = type(entry) == "table" and entry.attributes or {}
        if config and type(config.chance) == "function" and not keep[key] and not attributes.locked and not attributes.trait and not attributes.grade then
            local rank = RarityRank[self:UnitRarity(config, attributes)]
            if rank and rank < limit then
                table.insert(keys, key)
            end
        end
    end
    return keys
end

function App:UnitRarity(config, attributes)
    if type(config.getRarity) == "function" then
        local ok, rarity = pcall(config.getRarity, attributes)
        if ok and type(rarity) == "string" then
            return rarity
        end
    end
    return config.rarity
end

function App:SellJunk(manual)
    local limit = RarityRank[self.Values.SellBelow]
    if not limit then
        if manual then
            self:Notify("Sell Junk", "Choose a rarity in Sell Below first.", "Warning")
        end
        return
    end
    local keys = self:JunkKeys(limit)
    if #keys == 0 then
        if manual then
            self:Notify("Sell Junk", "No sellable units below " .. self.Values.SellBelow .. ".", "Info")
        end
        return
    end
    local earned, sold = self:Invoke(Remotes.SellInventory, keys)
    if manual then
        if tonumber(sold) and sold > 0 then
            self:Notify("Sell Junk", "Sold " .. sold .. " units for $" .. self:Format(earned) .. ".", "Success")
        else
            self:Notify("Sell Junk", "Nothing was sold. Try again in a moment.", "Warning")
        end
    end
end

function App:UpgradeStep()
    local data = self:Data()
    if not data then
        return 1
    end
    local owned = data.Upgrades or {}
    local money = self:Spendable(data)
    local choice, price
    local visited = {}
    local function visit(name)
        if visited[name] then
            return
        end
        visited[name] = true
        for _, child in ipairs(Modules.Tree.GetChildren(name)) do
            if owned[child] then
                visit(child)
            else
                local config = Modules.Upgrades[child]
                local cost = config and tonumber(config.price)
                if cost and cost <= money and (not price or cost < price) then
                    choice, price = child, cost
                end
            end
        end
    end
    visit("Start")
    if choice then
        self:Fire(Remotes.BuyUpgrade, choice)
        return 0.35
    end
    return 1.5
end

function App:RebirthStep()
    local data = self:Data()
    if not data then
        return 1
    end
    local nextRebirth = Modules.Rebirths.GetNext(tonumber(data.Rebirth) or 0)
    if nextRebirth and (tonumber(data.Money) or 0) >= nextRebirth.cost then
        self:Fire(Remotes.Rebirth)
        return 2
    end
    return 1
end

function App:RewardsStep()
    local data = self:Data()
    if not data then
        return 2
    end
    local clock = os.clock()
    local serverNow = workspace:GetServerTimeNow()
    local lastDaily = tonumber(data.LastDailyRewardClaim) or 0
    if (lastDaily == 0 or serverNow - lastDaily >= (tonumber(Modules.Daily.Cooldown) or 82800) + 3) and clock >= (self.DailyAt or 0) then
        self.DailyAt = clock + 30
        self:Fire(Remotes.DailyClaim)
    end
    if (tonumber(data.PendingOfflineEarnings) or 0) > 0 and clock >= (self.OfflineAt or 0) then
        self.OfflineAt = clock + 5
        self:Fire(Remotes.OfflineClaim)
    end
    if not data.ClaimedGroupReward and clock >= (self.GroupAt or 0) then
        self.GroupAt = clock + 120
        local ok, member = pcall(Player.IsInGroup, Player, Modules.Group.GroupId)
        if ok and member then
            self:Fire(Remotes.GroupClaim)
        end
    end
    for period, config in pairs(Modules.Quests.Periods or {}) do
        local quest = data.Quests and data.Quests[period]
        if type(quest) == "table" and (tonumber(quest.expiresAt) or 0) > serverNow then
            for _, entry in ipairs(config.quests or {}) do
                local progress = quest.progress and tonumber(quest.progress[entry.id]) or 0
                local claimed = quest.claimed and quest.claimed[entry.id]
                if progress >= entry.target and not claimed then
                    self:Fire(Remotes.QuestClaim, period, entry.id, quest.expiresAt)
                    task.wait(0.3)
                end
            end
        end
    end
    return 5
end

function App:SpinStep()
    local data = self:Data()
    if not data then
        return 2
    end
    for _, entry in pairs(data.ActiveEntries or {}) do
        if self:EntryKind(entry) == "Spin" then
            return 2
        end
    end
    local choice, bestMultiplier
    for key, entry in pairs(data.Inventory or {}) do
        local kind, config = self:EntryKind(entry)
        if kind == "Spin" and (tonumber(entry.amount) or 0) > 0 then
            local multiplier = tonumber(config.luckMultiplier) or 0
            if not bestMultiplier or multiplier > bestMultiplier then
                choice, bestMultiplier = key, multiplier
            end
        end
    end
    if choice then
        self:Fire(Remotes.UseSpin, choice)
        return 2
    end
    return 4
end

function App:BoostStep()
    local data = self:Data()
    if not data then
        return 2
    end
    local active = data.ActiveEntries or {}
    for key, entry in pairs(data.Inventory or {}) do
        if self:EntryKind(entry) == "Boost" and (tonumber(entry.amount) or 0) > 0 and active[entry.name] == nil then
            self:Fire(Remotes.UseBoost, key)
            task.wait(0.4)
            if not (self.Alive and self.State.AutoBoosts) then
                break
            end
        end
    end
    return 4
end

function App:GameTowerActive()
    local root = Modules.UI.Root
    local tower = root and root:FindFirstChild("Tower")
    if not tower then
        return false
    end
    local screen, hidden = tower:FindFirstChild("Screen"), tower:FindFirstChild("Hidden")
    return (screen and screen.Visible) or (hidden and hidden.Visible) or false
end

function App:SequenceTime(sequence)
    local refs = Modules.TowerRefs
    local actions, waits, starts = refs.Actions, refs.ActionWaitTime, refs.FloorStartedWaitTime
    local total = 0
    for index, action in ipairs(sequence) do
        if action.action == actions.floorStarted then
            local previous = sequence[index - 1]
            if index == 1 then
                total += action.floor == 1 and starts.initial or starts.transition
            elseif previous and previous.action == actions.memberDefeated then
                total += starts.transition
            else
                total += starts.repeated
            end
        else
            total += waits[action.action] or 0
        end
    end
    return total
end

function App:ReadSequence(sequence)
    local tower = self.Tower
    local actions = Modules.TowerRefs.Actions
    for _, action in ipairs(sequence) do
        if action.action == actions.floorStarted then
            tower.Floor = tonumber(action.floor) or tower.Floor
        elseif action.action == actions.floorCompleted then
            tower.Best = math.max(tower.Best, tonumber(action.floor) or 0)
            for name, amount in pairs(action.rewards or {}) do
                tower.Rewards[name] = (tower.Rewards[name] or 0) + (tonumber(amount) or 0)
            end
        elseif action.action == actions.ended then
            tower.Active = false
            tower.Ending = false
            tower.Runs += 1
            tower.LastRewards = tower.Rewards
            tower.Rewards = {}
            tower.RetryAt = os.clock() + 3.2
            tower.Message = "Finished " .. tostring(tower.Name or "tower") .. " on floor " .. tower.Floor
        end
    end
    tower.NextAt = os.clock() + self:SequenceTime(sequence) + 0.05
    if tower.Active then
        tower.Message = "Running " .. tostring(tower.Name) .. " - floor " .. tower.Floor
    end
end

function App:CompleteFloor(manual)
    local tower = self.Tower
    if tower.Busy then
        return false
    end
    if self:GameTowerActive() then
        if manual then
            self:Notify("Tower", "This tower is being played from the game menu.", "Warning")
        end
        return false
    end
    if os.clock() < tower.NextAt then
        if manual then
            self:Notify("Tower", "The next floor is not ready yet.", "Info")
        end
        return false
    end
    tower.Busy = true
    local sequence = self:Invoke(Remotes.CompleteFloor)
    tower.Busy = false
    if type(sequence) == "table" and #sequence > 0 then
        if not tower.Active then
            tower.Active = true
            tower.Name = tower.Name or self.Values.Tower
            tower.Rewards = {}
        end
        self:ReadSequence(sequence)
        return true
    end
    if tower.Active then
        tower.Active = false
        tower.Ending = false
        tower.Message = "Idle"
    elseif manual then
        self:Notify("Tower", "There is no active tower run.", "Warning")
    end
    return false
end

function App:StartTower(manual)
    local tower = self.Tower
    if tower.Busy then
        return false
    end
    if tower.Active then
        if manual then
            self:Notify("Tower", "A tower run is already active.", "Warning")
        end
        return false
    end
    if self:GameTowerActive() then
        tower.RetryAt = os.clock() + 3
        if manual then
            self:Notify("Tower", "A tower is already running from the game menu.", "Warning")
        end
        return false
    end
    local name = self.Values.Tower
    tower.Busy = true
    tower.Message = "Starting " .. name
    local ok, started = pcall(function()
        local data = self:Data()
        if data and #(data.TowerTeam or {}) == 0 then
            self:Fire(Remotes.EquipBestTeam)
            task.wait(1.2)
        end
        return self:Invoke(Remotes.PlayTower, name)
    end)
    tower.Busy = false
    if ok and started then
        tower.Active = true
        tower.Ending = false
        tower.Name = name
        tower.Floor = 1
        tower.Rewards = {}
        tower.NextAt = os.clock() + 0.3
        tower.Message = "Running " .. name .. " - floor 1"
        return true
    end
    tower.RetryAt = os.clock() + 3.5
    if self:CompleteFloor(false) then
        return true
    end
    tower.Message = "Waiting to start " .. name
    if manual then
        self:Notify("Tower", "Could not start " .. name .. ". Wait a few seconds between runs and make sure you own units.", "Warning")
    end
    return false
end

function App:CancelTower()
    local tower = self.Tower
    local cancelled = self:Invoke(Remotes.CancelTower)
    if cancelled then
        if tower.Active then
            tower.Ending = true
            tower.Message = "Ending " .. tostring(tower.Name or "tower")
        end
        self:Notify("Tower", "The run ends after the current floor.", "Info")
    else
        tower.Active = false
        tower.Ending = false
        tower.Message = "Idle"
        self:Notify("Tower", "There is no active tower run.", "Warning")
    end
end

function App:TowerStep()
    local tower = self.Tower
    if tower.Busy then
        return
    end
    local now = os.clock()
    if tower.Active then
        if (self.State.AutoPlayTower or self.State.AutoCompleteFloor or tower.Ending) and now >= tower.NextAt then
            self:CompleteFloor(false)
        end
    elseif self.State.AutoPlayTower and now >= tower.RetryAt then
        self:StartTower(false)
    end
end

function App:Meets(kind, current, target)
    if not current then
        return false
    end
    if current == target then
        return true
    end
    if kind == "Grade" then
        local a, b = Modules.Grades[current], Modules.Grades[target]
        return a ~= nil and b ~= nil and (a.order or 0) >= (b.order or 0)
    end
    local a, b = Modules.Traits[current], Modules.Traits[target]
    if not (a and b) then
        return false
    end
    local ai, ad, ah = a.incomeMultiplier or 1, a.damageMultiplier or 1, a.healthMultiplier or 1
    local bi, bd, bh = b.incomeMultiplier or 1, b.damageMultiplier or 1, b.healthMultiplier or 1
    return ai >= bi and ad >= bd and ah >= bh and (ai > bi or ad > bd or ah > bh)
end

function App:RerollStep(kind)
    local isTrait = kind == "Trait"
    local key = isTrait and "RollTrait" or "RollGrade"
    local item = isTrait and "Trait Reroll" or "Gems"
    local itemLabel = isTrait and "Trait Rerolls" or "Gems"
    local target = (isTrait and self.Values.UntilTrait or self.Values.UntilGrade) or "Any"
    local function stop(title, message, style)
        self:SetFeature(key, false)
        self:Notify(title, message, style)
        self:RefreshUnits(false)
        return 1
    end
    local unitKey = self.Values.UnitKey
    if not unitKey then
        return stop(kind .. " Roll", "Select a unit first.", "Warning")
    end
    local data = self:Data()
    if not data then
        return 1
    end
    local entry = data.Inventory and data.Inventory[unitKey]
    if not self:UnitConfig(entry) then
        return stop(kind .. " Roll", "The selected unit is no longer in your inventory.", "Warning")
    end
    local attributes = entry.attributes or {}
    local current = isTrait and attributes.trait or attributes.grade
    local protected = (isTrait and data.ProtectedTraits or data.ProtectedGrades) or {}
    if target == "Any" then
        if current and protected[current] then
            return stop(kind .. " Roll", entry.name .. " has the protected " .. kind:lower() .. " " .. tostring(current) .. ".", "Success")
        end
    else
        if self:Meets(kind, current, target) then
            return stop(kind .. " Roll", entry.name .. " got " .. tostring(current) .. ".", "Success")
        end
        if current and protected[current] then
            return stop(kind .. " Roll", tostring(current) .. " is protected in game. Pick it as the target or unprotect it to keep rolling.", "Warning")
        end
    end
    local before = self:Amount(data, item)
    if before < 1 then
        return stop(kind .. " Roll", "You are out of " .. itemLabel .. ".", "Warning")
    end
    self:Fire(isTrait and Remotes.RollTrait or Remotes.RollGrade, unitKey)
    local deadline = os.clock() + 2.5
    repeat
        task.wait(0.05)
    until not (self.Alive and self.State[key]) or self:Amount(self:Data(), item) < before or os.clock() > deadline
    return 0.27
end

function App:BuildUnitOptions()
    local data = self:Data()
    local items = {}
    for key, entry in pairs(data and data.Inventory or {}) do
        local config = self:UnitConfig(entry)
        if config then
            local ok, income = pcall(config.income, entry.attributes or {})
            table.insert(items, {Key = key, Entry = entry, Income = ok and tonumber(income) or 0})
        end
    end
    table.sort(items, function(a, b)
        if a.Income == b.Income then
            return a.Key < b.Key
        end
        return a.Income > b.Income
    end)
    local options, map, labels, used = {"None"}, {}, {}, {None = true}
    for _, item in ipairs(items) do
        local attributes = item.Entry.attributes or {}
        local parts = {item.Entry.name}
        if attributes.mutation then
            table.insert(parts, tostring(attributes.mutation))
        end
        table.insert(parts, "Lv " .. tostring(attributes.level or 1))
        if attributes.trait then
            table.insert(parts, tostring(attributes.trait))
        end
        if attributes.grade then
            table.insert(parts, "Grade " .. tostring(attributes.grade))
        end
        local base = table.concat(parts, " | ")
        local label, count = base, 1
        while used[label] do
            count += 1
            label = base .. " #" .. count
        end
        used[label] = true
        table.insert(options, label)
        map[label] = item.Key
        labels[item.Key] = label
    end
    self.Units = {Options = options, Map = map, Labels = labels}
    return options
end

function App:RefreshUnits(announce)
    local options = self:BuildUnitOptions()
    local control = self.Controls.Unit
    if control then
        local label = self.Values.UnitKey and self.Units.Labels[self.Values.UnitKey]
        if not label then
            self.Values.UnitKey = nil
        end
        pcall(function()
            control:Refresh(options, false)
            control:Set(label or "None", true)
        end)
    end
    if announce then
        self:Notify("Units refreshed", tostring(#options - 1) .. " units found.", "Success")
    end
end

function App:SetWalkSpeed(restore)
    local _, _, humanoid = self:Character()
    if humanoid and restore then
        humanoid.WalkSpeed = self:Buff("Walkspeed") or 16
    end
end

function App:CaptureJump()
    local _, _, humanoid = self:Character()
    if humanoid and not self.Original.Jump then
        self.Original.Jump = {UseJumpPower = humanoid.UseJumpPower, JumpPower = humanoid.JumpPower, JumpHeight = humanoid.JumpHeight}
    end
end

function App:RestoreJump()
    local _, _, humanoid = self:Character()
    local original = self.Original.Jump
    if humanoid and original then
        humanoid.UseJumpPower = original.UseJumpPower
        humanoid.JumpPower = original.JumpPower
        humanoid.JumpHeight = original.JumpHeight
    end
    self.Original.Jump = nil
end

function App:RestoreCollisions()
    for part in pairs(self.Collisions) do
        if part.Parent then
            part.CanCollide = true
        end
    end
    table.clear(self.Collisions)
end

function App:MoveControls()
    if self.ControlModule == nil then
        local ok, controls = pcall(function()
            local scripts = Player:FindFirstChild("PlayerScripts")
            local module = scripts and scripts:FindFirstChild("PlayerModule")
            return module and require(module):GetControls()
        end)
        self.ControlModule = ok and controls or false
    end
    return self.ControlModule or nil
end

function App:ClearFly()
    for _, object in ipairs(self.FlyObjects or {}) do
        pcall(object.Destroy, object)
    end
    self.FlyObjects = nil
end

function App:StartFly()
    self:ClearFly()
    local _, root, humanoid = self:Character()
    if not root then
        return
    end
    local velocity = Instance.new("BodyVelocity")
    velocity.Name = "AnimeDiceFlyVelocity"
    velocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    velocity.Velocity = Vector3.zero
    velocity.Parent = root
    local gyro = Instance.new("BodyGyro")
    gyro.Name = "AnimeDiceFlyGyro"
    gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    gyro.P = 9e4
    gyro.CFrame = root.CFrame
    gyro.Parent = root
    self.FlyObjects = {velocity, gyro}
    humanoid.PlatformStand = true
end

function App:StopFly()
    self:ClearFly()
    local _, _, humanoid = self:Character()
    if humanoid then
        humanoid.PlatformStand = false
        pcall(humanoid.ChangeState, humanoid, Enum.HumanoidStateType.GettingUp)
    end
end

function App:FlyStep()
    local _, root, humanoid = self:Character()
    if not root then
        return
    end
    local objects = self.FlyObjects
    if not objects or objects[1].Parent ~= root or objects[2].Parent ~= root then
        self:StartFly()
        objects = self.FlyObjects
        if not objects then
            return
        end
    end
    local camera = workspace.CurrentCamera
    local move = Vector3.zero
    local controls = self:MoveControls()
    if controls then
        local ok, vector = pcall(controls.GetMoveVector, controls)
        if ok and typeof(vector) == "Vector3" and vector.Magnitude > 0 then
            move = camera.CFrame:VectorToWorldSpace(Vector3.new(vector.X, 0, vector.Z))
        end
    end
    if move.Magnitude == 0 then
        move = humanoid.MoveDirection
    end
    local vertical = 0
    if humanoid.Jump or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        vertical += 1
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
        vertical -= 1
    end
    local direction = move + Vector3.new(0, vertical, 0)
    if direction.Magnitude > 1 then
        direction = direction.Unit
    end
    objects[1].Velocity = direction * self.Values.FlySpeed
    objects[2].CFrame = camera.CFrame
    if not humanoid.PlatformStand then
        humanoid.PlatformStand = true
    end
end

function App:ApplyPrompt(prompt)
    if self.Prompts[prompt] == nil then
        self.Prompts[prompt] = prompt.HoldDuration
    end
    if prompt.HoldDuration ~= 0 then
        prompt.HoldDuration = 0
    end
end

function App:PromptStep()
    for _, prompt in ipairs(workspace:QueryDescendants("ProximityPrompt")) do
        self:ApplyPrompt(prompt)
    end
    return 2
end

function App:RestorePrompts()
    for prompt, value in pairs(self.Prompts) do
        if prompt.Parent then
            prompt.HoldDuration = value
        end
    end
    table.clear(self.Prompts)
end

function App:ApplyStep()
    local _, _, humanoid = self:Character()
    if humanoid then
        if self.State.Speed and humanoid.WalkSpeed ~= self.Values.WalkSpeed then
            humanoid.WalkSpeed = self.Values.WalkSpeed
        end
        if self.State.JumpPower then
            if not self.Original.Jump then
                self:CaptureJump()
            end
            if not humanoid.UseJumpPower then
                humanoid.UseJumpPower = true
            end
            if humanoid.JumpPower ~= self.Values.JumpPower then
                humanoid.JumpPower = self.Values.JumpPower
            end
        end
    end
    if self.State.Gravity and workspace.Gravity ~= self.Values.Gravity then
        workspace.Gravity = self.Values.Gravity
    end
    local camera = workspace.CurrentCamera
    if self.State.FOV and camera and camera.FieldOfView ~= self.Values.FOV then
        camera.FieldOfView = self.Values.FOV
    end
    if self.State.CameraZoom then
        local minimum = self.Values.MinZoom
        local maximum = math.max(self.Values.MaxZoom, minimum)
        if Player.CameraMaxZoomDistance ~= maximum or Player.CameraMinZoomDistance ~= minimum then
            Player.CameraMaxZoomDistance = math.max(maximum, Player.CameraMinZoomDistance)
            Player.CameraMinZoomDistance = minimum
            Player.CameraMaxZoomDistance = maximum
        end
    end
    if self.State.Fly then
        self:FlyStep()
    end
end

function App:NoclipStep()
    local character = Player.Character
    if not character then
        return
    end
    for _, part in ipairs(character:QueryDescendants("BasePart")) do
        if part.CanCollide then
            self.Collisions[part] = true
            part.CanCollide = false
        end
    end
end

function App:Reconnect()
    if self.Reconnecting then
        return
    end
    self.Reconnecting = true
    task.spawn(function()
        task.wait(2)
        while self.Alive and self.State.AutoReconnect do
            pcall(TeleportService.Teleport, TeleportService, game.PlaceId, Player)
            task.wait(10)
        end
        self.Reconnecting = false
    end)
end

function App:Rejoin()
    self:Notify("Rejoin", "Rejoining this server...", "Info")
    local ok = pcall(function()
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, Player)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Player)
        end
    end)
    if not ok then
        self:Notify("Rejoin", "Teleport failed. Try again.", "Error")
    end
end

function App:ServerHop()
    if self.Hopping then
        return
    end
    self.Hopping = true
    self:Notify("Server Hop", "Looking for another server...", "Info")
    task.spawn(function()
        local cursor, candidates = nil, {}
        for _ = 1, 3 do
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
            if cursor then
                url ..= "&cursor=" .. HttpService:UrlEncode(cursor)
            end
            local ok, body = pcall(function()
                return game:HttpGet(url)
            end)
            if not ok or type(body) ~= "string" then
                break
            end
            local decoded, page = pcall(HttpService.JSONDecode, HttpService, body)
            if not decoded or type(page) ~= "table" then
                break
            end
            for _, server in ipairs(page.data or {}) do
                local playing, maximum = tonumber(server.playing), tonumber(server.maxPlayers)
                if server.id ~= game.JobId and playing and maximum and playing < maximum then
                    table.insert(candidates, server.id)
                end
            end
            cursor = page.nextPageCursor
            if #candidates >= 15 or not cursor then
                break
            end
        end
        if not self.Alive then
            return
        end
        if #candidates == 0 then
            self:Notify("Server Hop", "No other servers were found.", "Warning")
        else
            local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, candidates[math.random(1, #candidates)], Player)
            if not ok then
                self:Notify("Server Hop", "Teleport failed. Try again.", "Error")
            end
        end
        self.Hopping = false
    end)
end

function App:TeleportTo(cframe)
    local _, root = self:Character()
    if not root then
        self:Notify("Teleport", "Your character is not loaded.", "Warning")
        return
    end
    if not cframe then
        self:Notify("Teleport", "This location is not available right now.", "Warning")
        return
    end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = cframe
end

function App:PlotCFrame()
    local plot = Modules.Plot.plot
    if not (plot and plot.Parent) then
        plot = nil
        local plots = workspace:FindFirstChild("Plots")
        local claimed = plots and plots:FindFirstChild("Claimed")
        for _, model in ipairs(claimed and claimed:GetChildren() or {}) do
            local label = model:FindFirstChild("Label")
            local gui = label and label:FindFirstChild("BillboardGui")
            local owner = gui and gui:FindFirstChild("PlayerName")
            if owner and (owner.Text == Player.DisplayName or owner.Text == Player.Name) then
                plot = model
                break
            end
        end
    end
    if not plot then
        return nil
    end
    local spawn = plot:FindFirstChild("Spawn")
    if spawn and spawn:IsA("BasePart") then
        return spawn.CFrame * CFrame.new(0, 5, 0)
    end
    return plot:GetPivot() * CFrame.new(0, 5, 0)
end

function App:ZoneCFrame(name)
    local zones = workspace:FindFirstChild("Zones")
    local part = zones and zones:FindFirstChild(name)
    if not (part and part:IsA("BasePart")) then
        return nil
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {zones, Player.Character}
    local hit = workspace:Raycast(part.Position, Vector3.new(0, -(part.Size.Y + 60), 0), params)
    local height = hit and hit.Position.Y + 3.5 or part.Position.Y - part.Size.Y / 2 + 3.5
    return CFrame.new(part.Position.X, height, part.Position.Z)
end

function App:Copy(text)
    if type(setclipboard) == "function" and pcall(setclipboard, text) then
        self:Notify("Copied", text, "Success")
    else
        self:Notify("Link", text, "Info")
    end
end

function App:UpdateStatus()
    if self.TowerStatus then
        local tower = self.Tower
        local lines = {}
        if tower.Active then
            table.insert(lines, (tower.Ending and "Ending " or "Running ") .. tostring(tower.Name) .. " - floor " .. tower.Floor)
        elseif self:GameTowerActive() then
            table.insert(lines, "A tower is running from the game menu")
        else
            table.insert(lines, tower.Message)
        end
        table.insert(lines, "Runs: " .. tower.Runs .. " | Best floor: " .. tower.Best)
        if tower.LastRewards and next(tower.LastRewards) then
            local rewards = {}
            for name, amount in pairs(tower.LastRewards) do
                table.insert(rewards, name .. " x" .. self:Format(amount))
            end
            table.sort(rewards)
            table.insert(lines, "Last rewards: " .. table.concat(rewards, ", "))
        end
        local text = table.concat(lines, "\n")
        if text ~= self.TowerText then
            self.TowerText = text
            self.TowerStatus:Set(text)
        end
    end
    if self.RerollStatus then
        local data = self:Data()
        local key = self.Values.UnitKey
        local entry = data and key and data.Inventory and data.Inventory[key]
        local lines = {}
        if self:UnitConfig(entry) then
            local attributes = entry.attributes or {}
            table.insert(lines, entry.name .. " | Lv " .. tostring(attributes.level or 1) .. (attributes.mutation and (" | " .. tostring(attributes.mutation)) or ""))
            table.insert(lines, "Trait: " .. tostring(attributes.trait or "None") .. " | Grade: " .. tostring(attributes.grade or "None"))
        else
            table.insert(lines, "No unit selected")
        end
        table.insert(lines, "Trait Rerolls: " .. self:Format(self:Amount(data, "Trait Reroll")) .. " | Gems: " .. self:Format(self:Amount(data, "Gems")))
        local text = table.concat(lines, "\n")
        if text ~= self.RerollText then
            self.RerollText = text
            self.RerollStatus:Set(text)
        end
    end
end

App:Feature("FastRoll", {
    Enable = function()
        App:InstallFastRoll()
    end,
    Disable = function()
        App:RemoveFastRoll()
    end,
})
App:Feature("ServerAutoRoll", {
    Enable = function()
        App.AutoRollGrace = os.clock() + 2
        App:Fire(Remotes.SetAutoRoll, true)
    end,
    Disable = function()
        App.AutoRollGrace = os.clock() + 2
        App:Fire(Remotes.SetAutoRoll, false)
    end,
})
App:Feature("AutoRoll", {Step = function() return App:AutoRollStep() end})
App:Feature("SkipAnimation", {
    Enable = function()
        App:InstallSkip()
        for _, object in ipairs(App:RollFrames()) do
            object.Visible = false
        end
        task.spawn(pcall, Modules.HUD.showAll, "rolling")
    end,
})
App:Feature("AutoBuyDice", {Step = function() return App:AutoDiceStep() end})
App:Feature("AutoCollect", {Step = function() return App:CollectStep() end})
App:Feature("AutoLevel", {Step = function() return App:LevelStep() end})
App:Feature("AutoEquipBest", {Step = function() return App:EquipBestStep() end})
App:Feature("AutoSell", {
    Enable = function()
        if not RarityRank[App.Values.SellBelow] then
            App:Notify("Auto Sell", "Choose a rarity in Sell Below to start selling.", "Warning")
        end
    end,
    Step = function()
        local limit = RarityRank[App.Values.SellBelow]
        if limit then
            App:SellJunk(false)
            local data = App:Data()
            if data and os.clock() >= (App.SellNoticeAt or 0) and App:InventoryFull(data) and #App:JunkKeys(limit) == 0 then
                App.SellNoticeAt = os.clock() + 60
                App:Notify("Inventory full", "No units below " .. App.Values.SellBelow .. " are left to sell. Raise Sell Below to free space.", "Warning")
            end
        end
        return 3
    end,
})
App:Feature("AutoUpgrades", {Step = function() return App:UpgradeStep() end})
App:Feature("AutoRebirth", {Step = function() return App:RebirthStep() end})
App:Feature("AutoRewards", {Step = function() return App:RewardsStep() end})
App:Feature("AutoSpins", {Step = function() return App:SpinStep() end})
App:Feature("AutoBoosts", {Step = function() return App:BoostStep() end})
App:Feature("AutoPlayTower", {
    Enable = function()
        App.Tower.RetryAt = 0
    end,
})
App:Feature("AutoCompleteFloor", {})
App:Feature("RollTrait", {Step = function() return App:RerollStep("Trait") end})
App:Feature("RollGrade", {Step = function() return App:RerollStep("Grade") end})
App:Feature("Speed", {
    Disable = function()
        App:SetWalkSpeed(true)
    end,
})
App:Feature("JumpPower", {
    Enable = function()
        App:CaptureJump()
    end,
    Disable = function()
        App:RestoreJump()
    end,
})
App:Feature("InfiniteJump", {})
App:Feature("Noclip", {
    Disable = function()
        App:RestoreCollisions()
    end,
})
App:Feature("Fly", {
    Enable = function()
        App:StartFly()
    end,
    Disable = function()
        App:StopFly()
    end,
})
App:Feature("Gravity", {
    Enable = function()
        App.Original.Gravity = App.Original.Gravity or workspace.Gravity
    end,
    Disable = function()
        if App.Original.Gravity then
            workspace.Gravity = App.Original.Gravity
            App.Original.Gravity = nil
        end
    end,
})
App:Feature("InstantPrompt", {
    Step = function()
        return App:PromptStep()
    end,
    Disable = function()
        App:RestorePrompts()
    end,
})
App:Feature("CameraZoom", {
    Enable = function()
        App.Original.Zoom = App.Original.Zoom or {Player.CameraMinZoomDistance, Player.CameraMaxZoomDistance}
    end,
    Disable = function()
        local zoom = App.Original.Zoom
        if zoom then
            Player.CameraMaxZoomDistance = math.max(zoom[2], Player.CameraMinZoomDistance)
            Player.CameraMinZoomDistance = zoom[1]
            Player.CameraMaxZoomDistance = zoom[2]
            App.Original.Zoom = nil
        end
    end,
})
App:Feature("FOV", {
    Enable = function()
        local camera = workspace.CurrentCamera
        App.Original.FOV = App.Original.FOV or (camera and camera.FieldOfView)
    end,
    Disable = function()
        local camera = workspace.CurrentCamera
        if camera and App.Original.FOV then
            camera.FieldOfView = App.Original.FOV
        end
        App.Original.FOV = nil
    end,
})
App:Feature("Disable3D", {
    Enable = function()
        RunService:Set3dRenderingEnabled(false)
    end,
    Disable = function()
        RunService:Set3dRenderingEnabled(true)
    end,
})
App:Feature("AntiAFK", {
    Enable = function()
        if App.IdleConnection then
            return
        end
        App.IdleConnection = Player.Idled:Connect(function()
            if not (App.Alive and App.State.AntiAFK) then
                return
            end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
            end)
            task.delay(0.2, function()
                pcall(function()
                    VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
                end)
            end)
        end)
    end,
    Disable = function()
        if App.IdleConnection then
            App.IdleConnection:Disconnect()
            App.IdleConnection = nil
        end
    end,
})
App:Feature("AutoReconnect", {})

function App:StopAll(keepGame)
    for key in pairs(self.Features) do
        if key ~= "AntiAFK" and not (keepGame and key == "ServerAutoRoll") then
            self:SetFeature(key, false)
        end
    end
    if self.Tower.Active and not self.Tower.Ending then
        task.spawn(function()
            self:CancelTower()
        end)
    end
end

function App:Unload()
    if not self.Alive then
        return
    end
    self:StopAll(true)
    self:SetFeature("AntiAFK", false)
    self:RemoveFastRoll()
    self:RemoveSkip()
    self.Alive = false
    for _, connection in ipairs(self.Connections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(self.Connections)
    if self.Window then
        pcall(self.Window.Destroy, self.Window)
    end
    if Environment[AppKey] == self then
        Environment[AppKey] = nil
    end
end

local walkBuff = App:Buff("Walkspeed")
if walkBuff then
    App.Values.WalkSpeed = math.floor(walkBuff + 0.5)
end
local currentCamera = workspace.CurrentCamera
if currentCamera then
    App.Values.FOV = math.floor(currentCamera.FieldOfView + 0.5)
end

Airflow.Theme.Background = Color3.fromRGB(16, 16, 21)
Airflow.Theme.Surface = Color3.fromRGB(22, 22, 29)
Airflow.Theme.Surface2 = Color3.fromRGB(28, 28, 37)
Airflow.Theme.Surface3 = Color3.fromRGB(46, 45, 58)
Airflow.Theme.Stroke = Color3.fromRGB(42, 41, 54)
Airflow.Theme.StrokeHover = Color3.fromRGB(150, 96, 62)
Airflow.Theme.Accent = Color3.fromRGB(255, 146, 72)
Airflow.Theme.AccentDark = Color3.fromRGB(40, 21, 10)
Airflow.Theme.Text = Color3.fromRGB(238, 236, 243)
Airflow.Theme.Muted = Color3.fromRGB(148, 144, 162)

local Window = Airflow:CreateWindow({
    Name = "Anime Dice",
    LoadingSubtitle = "Auto Farm",
    Icon = "dices",
    Size = UDim2.fromOffset(700, 520),
    MinSize = Vector2.new(280, 220),
    ToggleUIKeybind = Enum.KeyCode.RightControl,
    KeepOnScreen = true,
    MaxNotifications = 4,
    OpenButton = {Title = "Anime Dice", Icon = "dices"},
    Loading = false,
    ConfigurationSaving = {Enabled = false},
})
App.Window = Window

local RollTab = Window:CreateTab({Name = "Roll", Icon = "dices"})
local PlotTab = Window:CreateTab({Name = "Plot", Icon = "warehouse"})
local ProgressionTab = Window:CreateTab({Name = "Progression", Icon = "trending-up"})
local TowerTab = Window:CreateTab({Name = "Tower", Icon = "castle"})
local RerollsTab = Window:CreateTab({Name = "Rerolls", Icon = "refresh-cw"})
local TeleportsTab = Window:CreateTab({Name = "Teleports", Icon = "map-pin"})
local PlayerTab = Window:CreateTab({Name = "Player", Icon = "user"})
local SettingsTab = Window:CreateTab({Name = "Settings", Icon = "settings"})

function App:AddToggle(tab, key, name, desc)
    local control = tab:CreateToggle({
        Name = name,
        Desc = desc,
        CurrentValue = false,
        Callback = function(value)
            App:SetFeature(key, value)
        end,
    })
    self.Controls[key] = control
    return control
end

function App:AddSlider(tab, key, name, range, increment)
    local control = tab:CreateSlider({
        Name = name,
        Range = range,
        Increment = increment or 1,
        CurrentValue = math.clamp(self.Values[key], range[1], range[2]),
        Callback = function(value)
            value = tonumber(value)
            if value then
                App.Values[key] = value
            end
        end,
    })
    self.Values[key] = math.clamp(self.Values[key], range[1], range[2])
    self.Controls["Value" .. key] = control
    return control
end

function App:AddChoice(tab, key, name, desc, options)
    local control
    control = tab:CreateDropdown({
        Name = name,
        Desc = desc,
        Options = options,
        CurrentOption = self.Values[key],
        Callback = function(value)
            if value == nil then
                task.defer(function()
                    if App.Alive then
                        control:Set(App.Values[key], true)
                    end
                end)
                return
            end
            App.Values[key] = value
            if key == "SellBelow" and App.State.AutoSell and not RarityRank[value] then
                App:Notify("Auto Sell", "Auto Sell is idle while Sell Below is Off.", "Warning")
            end
        end,
    })
    self.Controls[key] = control
    return control
end

RollTab:CreateSection("Dice Engine")
App:AddToggle(RollTab, "FastRoll", "Fast Roll", "Cuts the game's roll animation down to the server cooldown")
App:AddToggle(RollTab, "ServerAutoRoll", "Server Auto Roll", "The game's built-in auto roll")
App:AddToggle(RollTab, "AutoRoll", "Auto Roll", "Rolls straight through the server without animations")
App:AddToggle(RollTab, "SkipAnimation", "Skip Roll Animation", "Hides roll cards and rare roll cutscenes")
App:AddChoice(RollTab, "TargetDice", "Target Dice", "Highest dice Auto Buy may purchase", DiceNames)
App:AddToggle(RollTab, "AutoBuyDice", "Auto Buy Best Dice")

PlotTab:CreateSection("Income")
App:AddToggle(PlotTab, "AutoCollect", "Auto Collect Income")
App:AddToggle(PlotTab, "AutoLevel", "Auto Level Slots")
PlotTab:CreateSection("Units")
App:AddToggle(PlotTab, "AutoEquipBest", "Auto Equip Best")
App:AddToggle(PlotTab, "AutoSell", "Auto Sell", "Keeps placed, locked, team, traited and graded units")
App:AddChoice(PlotTab, "SellBelow", "Sell Below", "Units rarer than this are kept", SellNames)
PlotTab:CreateButton({Name = "Sell Junk Now", Icon = "coins", Callback = function()
    task.spawn(function()
        App:SellJunk(true)
    end)
end})

ProgressionTab:CreateSection("Progress")
App:AddToggle(ProgressionTab, "AutoUpgrades", "Auto Buy Upgrades")
App:AddToggle(ProgressionTab, "AutoRebirth", "Auto Rebirth")
ProgressionTab:CreateSection("Rewards")
App:AddToggle(ProgressionTab, "AutoRewards", "Auto Claim Rewards", "Daily, offline, group and quest rewards")
App:AddToggle(ProgressionTab, "AutoSpins", "Auto Use Spins")
App:AddToggle(ProgressionTab, "AutoBoosts", "Auto Use Boosts")

TowerTab:CreateSection("Tower Run")
App:AddChoice(TowerTab, "Tower", "Tower", nil, TowerNames)
App:AddToggle(TowerTab, "AutoPlayTower", "Auto Play Tower", "Starts, clears and restarts the selected tower")
App:AddToggle(TowerTab, "AutoCompleteFloor", "Auto Complete Floor", "Clears floors of a run started with Start Tower")
TowerTab:CreateButton({Name = "Start Tower", Icon = "castle", Callback = function()
    task.spawn(function()
        App:StartTower(true)
    end)
end})
TowerTab:CreateButton({Name = "Complete Floor", Icon = "swords", Callback = function()
    task.spawn(function()
        App:CompleteFloor(true)
    end)
end})
TowerTab:CreateButton({Name = "Cancel Tower", Icon = "square", Callback = function()
    task.spawn(function()
        App:CancelTower()
    end)
end})
App.TowerStatus = TowerTab:CreateParagraph({Title = "Tower Status", Content = "Idle"})

RerollsTab:CreateSection("Unit Rerolls")
App:BuildUnitOptions()
local unitControl
unitControl = RerollsTab:CreateDropdown({
    Name = "Unit",
    Options = App.Units.Options,
    CurrentOption = "None",
    SearchAfter = 6,
    Callback = function(value)
        if value == nil then
            task.defer(function()
                if App.Alive then
                    unitControl:Set("None", true)
                end
            end)
            App.Values.UnitKey = nil
            return
        end
        App.Values.UnitKey = App.Units.Map[value]
    end,
})
App.Controls.Unit = unitControl
App:AddToggle(RerollsTab, "RollTrait", "Roll Trait")
App:AddChoice(RerollsTab, "UntilTrait", "Until Trait", "Any stops on a protected trait", TraitOptions)
App:AddToggle(RerollsTab, "RollGrade", "Roll Grade")
App:AddChoice(RerollsTab, "UntilGrade", "Until Grade", "Any stops on a protected grade", GradeOptions)
RerollsTab:CreateButton({Name = "Refresh Units", Icon = "refresh-cw", Callback = function()
    App:RefreshUnits(true)
end})
App.RerollStatus = RerollsTab:CreateParagraph({Title = "Reroll Status", Content = "No unit selected"})

TeleportsTab:CreateSection("Travel")
TeleportsTab:CreateButton({Name = "My Plot", Icon = "house", Callback = function()
    App:TeleportTo(App:PlotCFrame())
end})
local zoneNames = {}
local zoneFolder = workspace:FindFirstChild("Zones")
for _, name in ipairs(ZoneOrder) do
    if not zoneFolder or zoneFolder:FindFirstChild(name) then
        table.insert(zoneNames, name)
    end
end
if zoneFolder then
    local extra = {}
    for _, child in ipairs(zoneFolder:GetChildren()) do
        if child:IsA("BasePart") and not table.find(zoneNames, child.Name) then
            table.insert(extra, child.Name)
        end
    end
    table.sort(extra)
    for _, name in ipairs(extra) do
        table.insert(zoneNames, name)
    end
end
for _, name in ipairs(zoneNames) do
    TeleportsTab:CreateButton({Name = (name:gsub("(%l)(%u)", "%1 %2")), Icon = "map-pin", Callback = function()
        App:TeleportTo(App:ZoneCFrame(name))
    end})
end

PlayerTab:CreateSection("General")
App:AddToggle(PlayerTab, "Speed", "Speed")
App:AddSlider(PlayerTab, "WalkSpeed", "Speed", {16, 250})
App:AddToggle(PlayerTab, "JumpPower", "Jump Power")
App:AddSlider(PlayerTab, "JumpPower", "Jump Power", {50, 300})
App:AddToggle(PlayerTab, "InfiniteJump", "Infinite Jump")
App:AddToggle(PlayerTab, "Noclip", "Noclip")
App:AddToggle(PlayerTab, "Fly", "Fly")
App:AddSlider(PlayerTab, "FlySpeed", "Fly Speed", {10, 300})
App:AddToggle(PlayerTab, "Gravity", "Gravity")
App:AddSlider(PlayerTab, "Gravity", "Gravity", {0, 400})
App:AddToggle(PlayerTab, "InstantPrompt", "Instant Prompt")
PlayerTab:CreateSection("Game")
App:AddToggle(PlayerTab, "CameraZoom", "Camera Zoom")
App:AddSlider(PlayerTab, "MinZoom", "Min Zoom", {0, 100})
App:AddSlider(PlayerTab, "MaxZoom", "Max Zoom", {10, 1000})
App:AddToggle(PlayerTab, "FOV", "FOV")
App:AddSlider(PlayerTab, "FOV", "FOV", {30, 120})
App:AddToggle(PlayerTab, "Disable3D", "Disable 3D Rendering")
PlayerTab:CreateSection("Server")
App:AddToggle(PlayerTab, "AntiAFK", "Anti AFK")
App:AddToggle(PlayerTab, "AutoReconnect", "Auto Reconnect")
PlayerTab:CreateButton({Name = "Server Hop", Icon = "shuffle", Callback = function()
    App:ServerHop()
end})
PlayerTab:CreateButton({Name = "Rejoin", Icon = "refresh-cw", Callback = function()
    App:Rejoin()
end})

SettingsTab:CreateSection("Session")
SettingsTab:CreateButton({Name = "Stop All", Icon = "square", Callback = function()
    App:StopAll(false)
    App:Notify("Stopped", "Every feature is off. Anti AFK stays as it is.", "Success")
end})
App.Controls.Keybind = SettingsTab:CreateKeybind({
    Name = "Menu Keybind",
    CurrentKeybind = Enum.KeyCode.RightControl,
    OnChanged = function(key)
        if typeof(key) == "EnumItem" then
            Window:SetKeybind(key)
        end
    end,
})
SettingsTab:CreateButton({Name = "Unload", Icon = "power", Callback = function()
    App:Unload()
end})
SettingsTab:CreateSection("Credits")
local creditText
local creditButton = SettingsTab:CreateButton({Name = "Credits - loading...", Icon = "copy", Callback = function()
    if creditText then
        App:Copy(creditText)
    else
        App:Notify("Credits", "The credits text is not available yet.", "Info")
    end
end})
SettingsTab:CreateButton({Name = "UI Library - airflowlib.lol", Icon = "copy", Callback = function()
    App:Copy("https://airflowlib.lol")
end})
task.spawn(function()
    local ok, text = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
    end)
    if not App.Alive then
        return
    end
    if ok and type(text) == "string" then
        text = text:match("^%s*(.-)%s*$")
        if text ~= "" and #text <= 200 and not text:find("[<>\r\n]") then
            creditText = text
            creditButton:SetText("Credits - " .. text)
            return
        end
    end
    creditButton:SetText("Credits - unavailable")
end)

local originalToggle = Window.Toggle
function Window:Toggle(value)
    if value == nil and UserInputService:GetFocusedTextBox() and UserInputService:GetLastInputType() == Enum.UserInputType.Keyboard then
        return
    end
    return originalToggle(self, value)
end

local Sidebar = Window.Body:FindFirstChild("Sidebar")
local TabLayout = Window.TabList:FindFirstChildOfClass("UIListLayout")
local TabPadding = Window.TabList:FindFirstChildOfClass("UIPadding")
local Remembered = {}
local function remember(object, properties)
    if not object then
        return
    end
    local values = Remembered[object] or {}
    for _, property in ipairs(properties) do
        values[property] = object[property]
    end
    Remembered[object] = values
end
remember(Sidebar, {"Size"})
remember(Window.Content, {"Position", "Size"})
remember(Window.TabList, {"Position", "Size", "AutomaticCanvasSize", "ScrollingDirection", "CanvasSize"})
remember(TabLayout, {"FillDirection"})
remember(TabPadding, {"PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom"})
if Sidebar then
    for _, child in ipairs(Sidebar:GetChildren()) do
        if child ~= Window.TabList and child ~= Window.Indicator and child:IsA("GuiObject") then
            remember(child, {"Visible"})
        end
    end
end
for _, child in ipairs(Window.Body:GetChildren()) do
    if child:IsA("Frame") and child.Size.X.Offset == 1 and child.Position.X.Offset == 170 then
        remember(child, {"Visible"})
    end
end
for _, tab in ipairs(Window.Tabs) do
    remember(tab._button, {"Size"})
    remember(tab._label, {"Position", "Size", "TextXAlignment"})
    if tab._icon then
        remember(tab._icon, {"Visible"})
    end
end

local originalIndicator = Window._placeIndicator
function Window:_placeIndicator(tab)
    if App.Compact then
        self.Indicator.Visible = false
        return
    end
    return originalIndicator(self, tab)
end

function App:Layout()
    if not self.Alive then
        return
    end
    local viewport = Window.Gui.AbsoluteSize
    if viewport.X < 1 or viewport.Y < 1 then
        return
    end
    for object, properties in pairs(Remembered) do
        for property, value in pairs(properties) do
            pcall(function()
                object[property] = value
            end)
        end
    end
    local width = math.clamp(viewport.X - 24, 280, 700)
    local height = math.clamp(viewport.Y - 24, 220, 520)
    Window.Root.Size = UDim2.fromOffset(width, height)
    self.Compact = width < 560
    if self.Compact and Sidebar and TabLayout then
        Sidebar.Size = UDim2.new(1, 0, 0, 52)
        for object, properties in pairs(Remembered) do
            if properties.Visible ~= nil and not object:IsDescendantOf(Window.TabList) then
                object.Visible = false
            end
        end
        Window.TabList.Position = UDim2.fromOffset(8, 5)
        Window.TabList.Size = UDim2.new(1, -16, 0, 42)
        Window.TabList.ScrollingDirection = Enum.ScrollingDirection.X
        Window.TabList.AutomaticCanvasSize = Enum.AutomaticSize.X
        Window.TabList.CanvasSize = UDim2.new()
        TabLayout.FillDirection = Enum.FillDirection.Horizontal
        if TabPadding then
            TabPadding.PaddingLeft = UDim.new(0, 0)
            TabPadding.PaddingRight = UDim.new(0, 0)
            TabPadding.PaddingTop = UDim.new(0, 0)
            TabPadding.PaddingBottom = UDim.new(0, 0)
        end
        Window.Content.Position = UDim2.fromOffset(0, 52)
        Window.Content.Size = UDim2.new(1, 0, 1, -52)
        for _, tab in ipairs(Window.Tabs) do
            tab._button.Size = UDim2.fromOffset(math.max(72, #tab.Name * 8 + 26), 40)
            tab._label.Position = UDim2.new()
            tab._label.Size = UDim2.fromScale(1, 1)
            tab._label.TextXAlignment = Enum.TextXAlignment.Center
            if tab._icon then
                tab._icon.Visible = false
            end
        end
        Window.Indicator.Visible = false
    end
    Window:_fitToScreen(true)
    Window:_clampToScreen()
    if Window.CurrentTab and not self.Compact then
        Window:_placeIndicator(Window.CurrentTab)
    end
end

App:Connect(Window.Gui:GetPropertyChangedSignal("AbsoluteSize"), function()
    App:Layout()
end)
App:Connect(Window.Gui.Destroying, function()
    App:Unload()
end)
App:Connect(RunService.Heartbeat, function()
    if App.Alive then
        local ok, err = pcall(App.ApplyStep, App)
        if not ok then
            App:Warn("Player", err)
        end
    end
end)
App:Connect(RunService.Stepped, function()
    if App.Alive and App.State.Noclip then
        pcall(App.NoclipStep, App)
    end
end)
App:Connect(UserInputService.JumpRequest, function()
    if App.State.InfiniteJump and not App.State.Fly then
        local _, _, humanoid = App:Character()
        if humanoid and humanoid.Health > 0 then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)
App:Connect(Player.CharacterAdded, function(character)
    table.clear(App.Collisions)
    App.FlyObjects = nil
    if App.State.Fly then
        task.spawn(function()
            character:WaitForChild("HumanoidRootPart", 10)
            character:WaitForChild("Humanoid", 10)
            if App.Alive and App.State.Fly then
                App:StartFly()
            end
        end)
    end
end)
App:Connect(workspace.DescendantAdded, function(object)
    if App.State.InstantPrompt and object:IsA("ProximityPrompt") then
        App:ApplyPrompt(object)
    end
end)
App:Connect(GuiService.ErrorMessageChanged, function(message)
    if App.State.AutoReconnect and type(message) == "string" and message ~= "" then
        App:Reconnect()
    end
end)
pcall(function()
    local promptGui = game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
    local overlay = promptGui and promptGui:FindFirstChild("promptOverlay")
    if overlay then
        App:Connect(overlay.ChildAdded, function(child)
            if App.State.AutoReconnect and child.Name == "ErrorPrompt" then
                App:Reconnect()
            end
        end)
    end
end)

App:SyncGameState()
App:SetFeature("AntiAFK", true)

task.spawn(function()
    while App.Alive do
        local ok, err = pcall(App.TowerStep, App)
        if not ok then
            App:Warn("Tower", err)
        end
        task.wait(0.2)
    end
end)
task.spawn(function()
    while App.Alive do
        pcall(App.SyncGameState, App)
        pcall(App.UpdateStatus, App)
        task.wait(0.5)
    end
end)
task.defer(function()
    if App.Alive then
        App:Layout()
    end
end)

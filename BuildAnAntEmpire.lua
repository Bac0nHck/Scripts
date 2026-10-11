if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10436530264 and game.PlaceId ~= 78490532994307 then
    error("Ant Empire: this game is not supported.", 0)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Player = Players.LocalPlayer
local Environment = type(getgenv) == "function" and getgenv() or _G
local AppKey = "AntEmpireAirflow"

local Previous = Environment[AppKey]
if type(Previous) == "table" and type(Previous.Unload) == "function" then
    pcall(Previous.Unload, Previous)
end

local function findPath(root, ...)
    local current = root
    for _, name in ipairs({...}) do
        current = current and current:FindFirstChild(name)
    end
    return current
end

local Packages = ReplicatedStorage:WaitForChild("Packages", 60)
local EventBus = Packages and Packages:WaitForChild("EventBus", 60)
local EventRemote = EventBus and EventBus:WaitForChild("RemoteEvent", 60)
if not EventRemote then
    error("Ant Empire: the game network did not load.", 0)
end

local readyDeadline = os.clock() + 60
while not Player:GetAttribute("Init") and os.clock() < readyDeadline do
    task.wait(0.25)
end

local function isolate(callback, ...)
    local arguments = table.pack(...)
    local results
    task.spawn(function()
        results = table.pack(pcall(callback, table.unpack(arguments, 1, arguments.n)))
    end)
    local deadline = os.clock() + 10
    while not results and os.clock() < deadline do
        task.wait()
    end
    if not results then
        return false, "timed out"
    end
    return table.unpack(results, 1, results.n)
end

local Game = {}
isolate(function()
    Game.Units = require(ReplicatedStorage._genConfigs.battle_tbunit)
end)
isolate(function()
    Game.Tags = require(ReplicatedStorage._genConfigs.battle_tbtag)
end)
isolate(function()
    Game.Context = require(ReplicatedStorage.Battle.Game.Context)
    Game.Helper = Game.Context.Helper.PlayerDataHelper
end)
isolate(function()
    Game.Store = require(ReplicatedStorage.WuKongHooks.BackPackStore)
end)
isolate(function()
    Game.Backpack = require(ReplicatedStorage.UI.Backpack.Model.BackpackModel)
end)
if type(Game.Units) ~= "table" then
    Game.Units = {}
end
if type(Game.Tags) ~= "table" then
    Game.Tags = {}
end

local ActionRemote = findPath(ReplicatedStorage, "WuKong", "RemoteActionFunction")
local EquipBestAction = "/\232\131\140\229\140\133\231\179\187\231\187\159/\232\131\140\229\140\133\232\163\133\229\164\135\230\156\128\228\189\179\229\141\149\228\189\141?\232\180\173\228\185\176"

local RarityOrder = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Exotic", "Secret", "Divine", "OP", "Celestial", "Eternal"}
local RarityRank = {}
local AntNames = {}
local RemoveNames = {}

local function sortedNames(ants)
    table.sort(ants, function(a, b)
        if a.Price ~= b.Price then
            return a.Price < b.Price
        end
        return a.Name < b.Name
    end)
    local names = {}
    for _, ant in ipairs(ants) do
        table.insert(names, ant.Name)
    end
    return names
end

do
    local cheapest = {}
    local ants = {}
    local seen = {}
    local allAnts = {}
    local allSeen = {}
    for _, unit in pairs(Game.Units) do
        if type(unit) == "table" and type(unit.DisplayName) == "string" and type(unit.Rarity) == "string" then
            local price = tonumber(unit.Price) or 0
            if unit.Type == "Normal" then
                if not cheapest[unit.Rarity] or price < cheapest[unit.Rarity] then
                    cheapest[unit.Rarity] = price
                end
                if not seen[unit.DisplayName] then
                    seen[unit.DisplayName] = true
                    table.insert(ants, {Name = unit.DisplayName, Price = price})
                end
            end
            if (unit._type_ == "AntCfg" or unit.Type == "Normal" or unit.Type == "Limited") and not allSeen[unit.DisplayName] then
                allSeen[unit.DisplayName] = true
                table.insert(allAnts, {Name = unit.DisplayName, Price = price})
            end
        end
    end
    local found = {}
    for rarity in pairs(cheapest) do
        table.insert(found, rarity)
    end
    if #found > 0 then
        table.sort(found, function(a, b)
            if cheapest[a] ~= cheapest[b] then
                return cheapest[a] < cheapest[b]
            end
            return a < b
        end)
        RarityOrder = found
    end
    for index, rarity in ipairs(RarityOrder) do
        RarityRank[rarity] = index
    end
    AntNames = sortedNames(ants)
    RemoveNames = sortedNames(allAnts)
end

local RarityOptions = {"Any"}
for _, rarity in ipairs(RarityOrder) do
    table.insert(RarityOptions, rarity)
end

isolate(function()
    Game.NestUnlock = require(ReplicatedStorage._genConfigs.battle_tbnestunlock)
end)
isolate(function()
    Game.LuckQueen = require(ReplicatedStorage.Helper.LuckQueenProgression)
end)
Game.Rewards = {}
for key, path in pairs({
    Online = {"OnlineReward", "Model", "OnlineState"},
    SevenDay = {"7DAY", "Model", "SevenDayState"},
    Ride = {"Ride", "Model", "State"},
    Group = {"LikeReward", "Model", "LikeRewardEvent"},
    Index = {"Index", "Model", "IndexModel"},
    Activity = {"ActivityEvent", "Model", "State"},
}) do
    isolate(function()
        local module = findPath(ReplicatedStorage, "UI", table.unpack(path))
        if module then
            Game.Rewards[key] = require(module)
        end
    end)
end

isolate(function()
    Game.Wheel = require(findPath(ReplicatedStorage, "UI", "SreawberrySkin", "Model", "State"))
end)
local StarItem = "Star"
isolate(function()
    local config = require(ReplicatedStorage.Battle.Game.Config.StarRollConfig)
    if type(config) == "table" and type(config.ItemId) == "string" then
        StarItem = config.ItemId
    end
end)

local LuckAttribute = "\229\185\184\232\191\144\229\128\188"
local QueenAttribute = "\232\154\129\229\144\142\231\173\137\231\186\167"
local UpgradeDefs = {
    {Label = "Egg Luck", Attribute = LuckAttribute, Gate = "Luck"},
    {Label = "Egg Rolls", Attribute = "\229\141\149\230\138\189\230\149\176\233\135\143"},
    {Label = "Ant Queen", Attribute = QueenAttribute, Gate = "Queen"},
    {Label = "Ant Nest", Attribute = "\229\183\162\231\169\180\229\177\130\230\149\176"},
    {Label = "Food Gain", Attribute = "\232\154\130\232\154\129\230\148\187\229\135\187\229\138\155"},
    {Label = "Ant Speed", Attribute = "\232\154\130\232\154\129\231\167\187\233\128\159"},
    {Label = "Compost Machine", Compost = true},
}
local UpgradeLabels = {}
for _, def in ipairs(UpgradeDefs) do
    table.insert(UpgradeLabels, def.Label)
end

isolate(function()
    Game.Items = require(ReplicatedStorage._genConfigs.ui_tbbackpackitem)
end)
isolate(function()
    Game.Mutations = require(ReplicatedStorage.Configs.MutationCrystalConfig)
end)
if type(Game.Items) ~= "table" then
    Game.Items = {}
end

local GearNames = {}
local GearByName = {}
local JellyNames = {}
local PotionNames = {}

do
    local function addsMutation(id)
        local config = Game.Mutations
        if type(config) == "table" and type(config.Get) == "function" then
            local ok, info = isolate(config.Get, id)
            if ok and type(info) == "table" then
                return info.Mode == "Apply"
            end
        end
        return string.find(id, "^Remove") == nil
    end
    local list = {}
    for id, config in pairs(Game.Items) do
        if type(id) == "string" and type(config) == "table" and config.Tag ~= "EventItem" then
            table.insert(list, {
                Id = id,
                Name = tostring(config.DisplayName or id),
                Price = math.max(math.floor(tonumber(config.CoinPrice) or 0), 0),
                Sort = tonumber(config.sort or config.Index) or math.huge,
                Tag = config.Tag,
            })
        end
    end
    table.sort(list, function(a, b)
        if a.Sort ~= b.Sort then
            return a.Sort < b.Sort
        end
        return a.Id < b.Id
    end)
    for _, item in ipairs(list) do
        if not GearByName[item.Name] then
            GearByName[item.Name] = item
            table.insert(GearNames, item.Name)
            if item.Tag == "Jelly" then
                table.insert(JellyNames, item.Name)
            elseif item.Tag == "Potion" and addsMutation(item.Id) then
                table.insert(PotionNames, item.Name)
            end
        end
    end
end

local Suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "N", "D", "Ud", "Dd", "Td", "Qt", "Qd", "Sd", "St", "Od", "Nod", "V", "Cv"}
local SuffixPower = {}
for index, suffix in ipairs(Suffixes) do
    SuffixPower[string.lower(suffix)] = index * 3
end

local function formatAmount(value)
    value = tonumber(value) or 0
    if value < 1000 then
        return tostring(math.floor(value))
    end
    local index = math.min(math.floor(math.log10(value) / 3), #Suffixes)
    local text = string.format("%.2f", value / 10 ^ (index * 3))
    return (string.gsub(text, "%.?0+$", "")) .. Suffixes[index]
end

local function parseAmount(text)
    if type(text) ~= "string" then
        return nil
    end
    text = string.gsub(text, "[%s,%$]", "")
    if text == "" then
        return nil
    end
    local value = tonumber(text)
    if not value then
        local number, suffix = string.match(text, "^([%d%.]+)(%a+)$")
        local power = suffix and SuffixPower[string.lower(suffix)]
        value = power and tonumber(number)
        if value then
            value *= 10 ^ power
        end
    end
    if value and value == value and value >= 0 and value ~= math.huge then
        return value
    end
    return nil
end

local function decodeAnt(value)
    value = tonumber(value)
    if not value or value < 1 then
        return nil
    end
    local raw = math.floor(value) - 1
    local rest = math.floor(raw / 512)
    return math.floor(rest / 64) + 1, rest % 64, raw % 512
end

local Airflow = loadstring(game:HttpGet("https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"))()
local App = {
    Alive = true,
    Features = {},
    State = {},
    Tokens = {},
    Controls = {},
    Connections = {},
    WarnedAt = {},
    NotifiedAt = {},
    Batches = {},
    Claims = {},
    Buying = false,
    Options = {MinRarity = "Any", MinRank = 0, MinCost = nil, MinCostText = "", Names = {}},
    Roll = {NextAt = 0, SentAt = 0, Fails = 0, Awaiting = false, Confirmed = false},
    Equip = {Signature = nil, RetryAt = 0},
    Removal = {Method = "Compost", MaxRarity = "Any", MaxRank = 0, MaxCost = nil, MaxCostText = "", Names = {}, KeepTraits = true},
    Compost = {RetryAt = 0, PullAt = 0, Coin = nil, Need = nil, At = 0, Waiting = nil, Result = nil},
    Discards = {},
    Expect = {},
    RemoveBlocked = {},
    UpgradeBlocked = {},
    Boards = {Selected = {}, Blocked = {}, Waiting = nil, Result = nil},
    Slots = {RetryAt = 0, Waiting = false, Result = nil},
    RewardRetry = {},
    Gear = {Selected = {}, Stock = nil, NextRefreshAt = 0, RequestAt = 0, Waiting = nil, Result = nil, Blocked = {}},
    Jelly = {Selected = {}, Waiting = nil, Result = nil, Blocked = {}},
    Potion = {Selected = {}, Blocked = {}},
    Star = {EnterAt = 0, EnterBlocked = false, RetryAt = 0, ReturnAt = 0, Origin = nil, Entered = false},
    Dungeon = {Snapshot = nil, At = 0, StartAt = 0, CoinTried = {}},
    DungeonRun = {Origin = nil, Entered = false, ReturnAt = 0, Tried = setmetatable({}, {__mode = "k"}), LastPrompt = nil, Rejected = false},
    Strawberry = {Tried = setmetatable({}, {__mode = "k"}), Origin = nil, SpinAt = 0},
    Food = {MinX = 1, Price = nil, PriceAt = 0, Remaining = 0, RequestAt = 0, NextAt = 0, Waiting = false, Result = nil},
}
Environment[AppKey] = App
for _, label in ipairs(UpgradeLabels) do
    App.Boards.Selected[label] = true
end
for _, name in ipairs(JellyNames) do
    App.Jelly.Selected[name] = true
end
for _, name in ipairs(PotionNames) do
    App.Potion.Selected[name] = true
end

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

function App:Alert(key, title, content, kind)
    local now = os.clock()
    if now >= (self.NotifiedAt[key] or 0) then
        self.NotifiedAt[key] = now + 15
        self:Notify(title, content, kind)
    end
end

function App:Warn(key, message)
    local now = os.clock()
    if now >= (self.WarnedAt[key] or 0) then
        self.WarnedAt[key] = now + 15
        warn("[Ant Empire] " .. key .. ": " .. tostring(message))
    end
end

function App:Copy(text)
    if type(setclipboard) == "function" and pcall(setclipboard, text) then
        self:Notify("Copied", text, "Success")
    else
        self:Notify("Link", text, "Info")
    end
end

function App:HideCloverLabel(label)
    if not label:IsA("GuiObject") or string.sub(label.Name, 1, 12) ~= "RollLuckRain" then
        return
    end
    label.Visible = false
    self.CloverSeen = self.CloverSeen or setmetatable({}, {__mode = "k"})
    if not self.CloverSeen[label] then
        self.CloverSeen[label] = true
        label:GetPropertyChangedSignal("Visible"):Connect(function()
            if App.Alive and App.HideClover and label.Visible then
                label.Visible = false
            end
        end)
    end
end

function App:SetCloverHidden(hidden)
    self.HideClover = hidden == true
    if self.CloverConnection then
        self.CloverConnection:Disconnect()
        self.CloverConnection = nil
    end
    local frame = findPath(Player:FindFirstChildOfClass("PlayerGui"), "HUDContainer", "EffectFrame")
    self.CloverFrame = frame
    if not frame then
        return
    end
    for _, child in ipairs(frame:GetChildren()) do
        if self.HideClover then
            self:HideCloverLabel(child)
        elseif child:IsA("GuiObject") and string.sub(child.Name, 1, 12) == "RollLuckRain" then
            child.Visible = true
        end
    end
    if self.HideClover then
        self.CloverConnection = frame.ChildAdded:Connect(function(child)
            self:HideCloverLabel(child)
            task.defer(function()
                if App.Alive and App.HideClover and child.Parent then
                    self:HideCloverLabel(child)
                end
            end)
        end)
    end
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
                    local ok, delay = pcall(feature.Step, token)
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

function App:Send(command, payload)
    EventRemote:FireServer("ECS_COMMAND", command, payload)
end

function App:Fire(name, payload)
    EventRemote:FireServer(name, payload)
end

function App:Cash()
    local helper = Game.Helper
    if type(helper) == "table" and type(helper.GetPlayerGold) == "function" then
        local ok, value = isolate(helper.GetPlayerGold, Player.UserId)
        value = ok and tonumber(value)
        if value then
            return value
        end
    end
    local stats = Player:FindFirstChild("leaderstats")
    local cash = stats and stats:FindFirstChild("Cash")
    local parsed = cash and parseAmount(tostring(cash.Value))
    if parsed then
        return parsed * 0.99
    end
    return nil
end

function App:RollInterval()
    local helper = Game.Helper
    if type(helper) == "table" and type(helper.GetPlayerRollInterval) == "function" then
        local ok, value = isolate(helper.GetPlayerRollInterval, Game.Context, Player.UserId)
        value = ok and tonumber(value)
        if value and value > 0 and value < 60 then
            return value
        end
    end
    return 3
end

function App:AntName(result)
    local unit = Game.Units[result.UnitId]
    if type(unit) == "table" and type(unit.DisplayName) == "string" then
        return unit.DisplayName
    end
    return tostring(result.UnitId or result.ItemId or "Ant")
end

function App:Matches(result, cost)
    local options = self.Options
    if options.MinRank > 0 then
        local unit = Game.Units[result.UnitId]
        local rarity = result.Rarity or type(unit) == "table" and unit.Rarity
        if (RarityRank[rarity] or 0) < options.MinRank then
            return false
        end
    end
    if options.MinCost and cost < options.MinCost then
        return false
    end
    if next(options.Names) and not options.Names[self:AntName(result)] then
        return false
    end
    return true
end

function App:Reserved()
    local total = 0
    local now = os.clock()
    for _, claim in pairs(self.Claims) do
        if claim.Pending then
            if now - claim.At > 8 then
                claim.Pending = false
            else
                total += claim.Cost
            end
        elseif now < (claim.SettleUntil or 0) then
            total += claim.Cost
        end
    end
    return total
end

function App:Prune()
    local live = {}
    for _, results in pairs(self.Batches) do
        for _, result in ipairs(results) do
            if type(result) == "table" and result.ClaimId then
                live[result.ClaimId] = true
            end
        end
    end
    local now = os.clock()
    for id, claim in pairs(self.Claims) do
        if not live[id] and not claim.Pending and now >= (claim.SettleUntil or 0) then
            self.Claims[id] = nil
        end
    end
end

function App:BuyBatch(results)
    if self.Buying or type(results) ~= "table" then
        return
    end
    self.Buying = true
    local ok, err = pcall(function()
        local picks = {}
        for _, result in ipairs(results) do
            if type(result) == "table" and type(result.ClaimId) == "string" and not self.Claims[result.ClaimId] then
                local cost = math.max(math.floor(tonumber(result.Cost) or 0), 0)
                if result.ResultType == "Item" then
                    if cost == 0 then
                        table.insert(picks, {Result = result, Cost = 0, Rank = math.huge})
                    end
                elseif self:Matches(result, cost) then
                    table.insert(picks, {Result = result, Cost = cost, Rank = RarityRank[result.Rarity] or 0})
                end
            end
        end
        if #picks == 0 then
            return
        end
        table.sort(picks, function(a, b)
            if a.Rank ~= b.Rank then
                return a.Rank > b.Rank
            end
            return a.Cost > b.Cost
        end)
        local budget
        for _, pick in ipairs(picks) do
            if pick.Cost > 0 and budget == nil then
                local cash = self:Cash()
                if cash then
                    budget = cash - self:Reserved()
                else
                    budget = -1
                    self:Alert("Cash", "Auto Buy", "Your cash could not be read, so nothing was bought.", "Warning")
                end
            end
            local id = pick.Result.ClaimId
            if (pick.Cost == 0 or budget >= pick.Cost) and not self.Claims[id] then
                self.Claims[id] = {Cost = pick.Cost, At = os.clock(), Pending = true, Name = self:AntName(pick.Result)}
                if pick.Cost > 0 then
                    budget -= pick.Cost
                end
                self:Send("ClaimRolledAnt", {ClaimId = id})
            end
        end
    end)
    self.Buying = false
    if not ok then
        self:Warn("AutoBuy", err)
    end
end

function App:HandleRoll(payload)
    if type(payload) ~= "table" then
        return
    end
    local results = payload.Results
    if type(results) ~= "table" then
        results = type(payload.Result) == "table" and {payload.Result} or {}
    end
    self.Batches[payload.Source or "Normal"] = results
    self:Prune()
    if payload.Source == nil then
        local roll = self.Roll
        if roll.Awaiting then
            roll.Confirmed = true
        else
            roll.NextAt = math.max(roll.NextAt, os.clock() + self:RollInterval())
        end
    end
    if self.State.AutoBuy then
        self:BuyBatch(results)
    end
end

function App:HandleClaim(payload)
    if type(payload) ~= "table" or type(payload.ClaimId) ~= "string" then
        return
    end
    local claim = self.Claims[payload.ClaimId]
    if not claim then
        self.Claims[payload.ClaimId] = {Cost = 0, At = os.clock(), Pending = false}
        return
    end
    if not claim.Pending then
        return
    end
    claim.Pending = false
    if payload.Success then
        claim.SettleUntil = os.clock() + 1
        return
    end
    local name = claim.Name or "that ant"
    if payload.PromptRobuxPurchase or payload.Reason == "NotEnoughGold" then
        self:Alert("NotEnough", "Auto Buy", "Not enough cash for " .. name .. ". Close the purchase prompt if one opened.", "Warning")
    elseif payload.Reason == "RobuxPurchasePending" then
        self:Alert("Pending", "Auto Buy", "A purchase prompt is still open. Close it to keep buying.", "Warning")
    elseif payload.Reason == "AddBackpackFailed" then
        self:Alert("Backpack", "Auto Buy", "Your backpack could not take " .. name .. ".", "Warning")
    end
end

function App:Power(value)
    local index, tag, level = decodeAnt(value)
    local unit = index and Game.Units["Unit" .. index]
    if type(unit) ~= "table" then
        return 0, level or 0
    end
    local tagConfig = Game.Tags[tag]
    local multiplier = math.max(tonumber(type(tagConfig) == "table" and tagConfig.Mul) or 1, 0)
    local attack = math.ceil((tonumber(unit.Attack) or 0) * 1.1 ^ level * multiplier)
    return attack * (tonumber(unit.AttackSpeed) or 0), level
end

function App:BackpackData()
    local store = Game.Store
    if type(store) == "table" and type(store.Load) == "function" then
        local ok, success, _, data = isolate(store.Load, Player.UserId)
        if ok and success and type(data) == "table" then
            return data
        end
    end
    local model = Game.Backpack
    local data = type(model) == "table" and model.BackPackData
    if type(data) == "table" then
        return data
    end
    return nil
end

function App:Loadout(data)
    local slots = 0
    for _, unlocked in pairs(type(data.UnlockedAntSlots) == "table" and data.UnlockedAntSlots or {}) do
        if unlocked then
            slots += 1
        end
    end
    slots = math.max(slots, 1)
    local pool = {}
    local function add(value, count)
        value = tonumber(value)
        if not value or value < 1 then
            return nil
        end
        value = math.floor(value)
        local power, level = self:Power(value)
        for _ = 1, math.min(count, slots) do
            table.insert(pool, {V = value, Power = power, Level = level})
        end
        return value
    end
    for value, count in pairs(type(data.Stacks) == "table" and data.Stacks or {}) do
        add(value, math.max(math.floor(tonumber(count) or 1), 1))
    end
    local have = {}
    local equipped = {}
    for _, entry in pairs(type(data.EquippedBySlot) == "table" and data.EquippedBySlot or {}) do
        local value = type(entry) == "table" and add(entry.V, 1)
        if value then
            have[value] = (have[value] or 0) + 1
            table.insert(equipped, value)
        end
    end
    table.sort(pool, function(a, b)
        if a.Power ~= b.Power then
            return a.Power > b.Power
        end
        if a.Level ~= b.Level then
            return a.Level > b.Level
        end
        return a.V < b.V
    end)
    local want = {}
    local best = {}
    for index = 1, math.min(slots, #pool) do
        local value = pool[index].V
        want[value] = (want[value] or 0) + 1
        best[index] = value
    end
    local differs = false
    for value, count in pairs(want) do
        if have[value] ~= count then
            differs = true
            break
        end
    end
    if not differs then
        for value, count in pairs(have) do
            if want[value] ~= count then
                differs = true
                break
            end
        end
    end
    table.sort(equipped)
    return {
        Differs = differs,
        Signature = table.concat(best, ",") .. "|" .. table.concat(equipped, ","),
        Want = want,
        Have = have,
    }
end

function App:EquipPlan()
    local data = self:BackpackData()
    if not data then
        return nil
    end
    local loadout = self:Loadout(data)
    return loadout.Differs, loadout.Signature
end

function App:EquipBest()
    local model = Game.Backpack
    if type(model) == "table" and type(model.EquipBest) == "function" then
        local ok, result = isolate(model.EquipBest, model)
        if ok then
            return result == true
        end
    end
    if ActionRemote then
        local ok, result = isolate(function()
            return ActionRemote:InvokeServer(EquipBestAction, "__null__", "__null__", {"[]"})
        end)
        return ok and result ~= false
    end
    return false
end

function App:StackCount(value, count)
    local expect = self.Expect[value]
    if expect then
        if os.clock() < expect.Until and count > expect.Count then
            return expect.Count
        end
        self.Expect[value] = nil
    end
    return count
end

function App:NoteRemoved(value, total, removed)
    self.Expect[value] = {Count = math.max(total - removed, 0), Until = os.clock() + 3}
end

function App:RemoveMatches(unit, tag, price)
    local options = self.Removal
    if options.KeepTraits and tag > 0 then
        return false
    end
    if options.MaxRank > 0 and (RarityRank[unit.Rarity] or math.huge) > options.MaxRank then
        return false
    end
    if options.MaxCost and price > options.MaxCost then
        return false
    end
    if next(options.Names) and not options.Names[unit.DisplayName] then
        return false
    end
    return true
end

function App:RemoveCandidates(data)
    local options = self.Removal
    if options.MaxRank == 0 and not options.MaxCost and not next(options.Names) then
        return nil
    end
    local loadout = self:Loadout(data)
    local favorites = type(data.Favorites) == "table" and data.Favorites or {}
    local positions = type(data.Positions) == "table" and data.Positions or {}
    local now = os.clock()
    local list = {}
    for key, count in pairs(type(data.Stacks) == "table" and data.Stacks or {}) do
        local value = tonumber(key)
        local index, tag = decodeAnt(value)
        local unit = index and Game.Units["Unit" .. index]
        if type(unit) == "table" then
            value = math.floor(value)
            local entryKey = "Ant:" .. value
            local price = math.max(math.floor(tonumber(unit.Price) or 0), 0)
            if favorites[entryKey] ~= true and now >= (self.RemoveBlocked[value] or 0) and self:RemoveMatches(unit, tag, price) then
                local total = self:StackCount(value, math.max(math.floor(tonumber(count) or 0), 0))
                local keep = math.max((loadout.Want[value] or 0) - (loadout.Have[value] or 0), 0)
                if total > keep then
                    table.insert(list, {
                        V = value,
                        Count = total - keep,
                        Total = total,
                        Price = price,
                        Name = tostring(unit.DisplayName),
                        EntryKey = entryKey,
                        Pos = positions[entryKey],
                    })
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.Price ~= b.Price then
            return a.Price < b.Price
        end
        return a.V < b.V
    end)
    return list
end

function App:DeleteOne(entry)
    local key = entry.EntryKey
    self:Fire("SetBackpackHeldEntry", {Kind = "Ant", EntryKey = key, V = entry.V, Pos = entry.Pos})
    local deadline = os.clock() + 2
    while Player:GetAttribute("BackpackHeldEntryKey") ~= key and os.clock() < deadline do
        task.wait(0.03)
    end
    if Player:GetAttribute("BackpackHeldEntryKey") ~= key then
        return false, "HoldFailed"
    end
    local id = HttpService:GenerateGUID(false)
    self.Discards[id] = false
    self:Fire("DiscardHeldAnt", {
        RequestId = id,
        RoomIndex = Player:GetAttribute("RoomIndex"),
        Kind = "Ant",
        V = entry.V,
        EntryKey = key,
    })
    deadline = os.clock() + 3
    while self.Discards[id] == false and os.clock() < deadline do
        task.wait(0.03)
    end
    local result = self.Discards[id]
    self.Discards[id] = nil
    if type(result) == "table" then
        return result.Success == true, result.Reason
    end
    return false, "Timeout"
end

function App:DeleteStep(list, token)
    local function running()
        return self.Alive and self.State.AutoRemove and self.Tokens.AutoRemove == token
    end
    local previous = {
        Kind = Player:GetAttribute("BackpackHeldKind"),
        EntryKey = Player:GetAttribute("BackpackHeldEntryKey"),
        V = Player:GetAttribute("BackpackHeldAntValue"),
        ItemId = Player:GetAttribute("BackpackHeldItemId"),
        PetKey = Player:GetAttribute("BackpackHeldPetKey"),
    }
    local budget = 8
    local failures = 0
    for _, entry in ipairs(list) do
        local removed = 0
        while removed < entry.Count and budget > 0 and running() do
            local ok, reason = self:DeleteOne(entry)
            if not ok then
                failures += 1
                self.RemoveBlocked[entry.V] = os.clock() + (reason == "ProtectedOrMissing" and 60 or 5)
                break
            end
            removed += 1
            budget -= 1
        end
        if removed > 0 then
            self:NoteRemoved(entry.V, entry.Total, removed)
        end
        if failures >= 2 or budget <= 0 or not running() then
            break
        end
    end
    if type(previous.Kind) == "string" and type(previous.EntryKey) == "string" and Player:GetAttribute("BackpackHeldEntryKey") == nil then
        self:Fire("SetBackpackHeldEntry", previous)
    end
    return failures > 0 and 2 or 0.3
end

function App:CompostState()
    local compost = self.Compost
    if os.clock() - compost.At < 2 and compost.Coin and compost.Need then
        return compost.Coin, compost.Need
    end
    local helper = Game.Helper
    local coin, need
    if type(helper) == "table" and type(helper.GetCompostState) == "function" then
        local ok, success, state = isolate(helper.GetCompostState, Player.UserId)
        if ok and success and type(state) == "table" then
            coin = tonumber(state.CompostCoin)
            local level = tonumber(state.CompostLevel)
            if level and type(helper.GetCompostTierConfig) == "function" then
                local tierOk, tier = isolate(helper.GetCompostTierConfig, Game.Context, level)
                if tierOk and type(tier) == "table" then
                    need = tonumber(tier.NeedValue)
                end
            end
        end
    end
    return coin or compost.Coin, need or compost.Need
end

function App:CompostRequest(operation, command, payload)
    local compost = self.Compost
    compost.Result = nil
    compost.Waiting = operation
    self:Send(command, payload)
    local deadline = os.clock() + 4
    while compost.Result == nil and os.clock() < deadline and self.Alive do
        task.wait(0.03)
    end
    compost.Waiting = nil
    local response = compost.Result
    compost.Result = nil
    local result = type(response) == "table" and type(response.Result) == "table" and response.Result or {}
    if tonumber(result.CompostCoin) then
        compost.Coin = tonumber(result.CompostCoin)
        compost.At = os.clock()
    end
    if tonumber(result.NeedValue) then
        compost.Need = tonumber(result.NeedValue)
    end
    return type(response) == "table" and response.Success == true, result
end

function App:CompostStep(list)
    local compost = self.Compost
    local now = os.clock()
    if now < compost.RetryAt then
        return 1
    end
    local coin, need = self:CompostState()
    local known = coin ~= nil and need ~= nil and need > 0
    if known and coin >= need then
        if now < compost.PullAt then
            return 2
        end
        local ok, result = self:CompostRequest("PullLever", "CompostPullLever", {})
        if ok then
            compost.Coin = 0
            compost.At = os.clock()
            self:Notify("Compost", "The lever was pulled and the reward was claimed.", "Success")
            return 1
        end
        if result.Reason == "Cooldown" then
            compost.PullAt = os.clock() + (tonumber(result.CooldownRemaining) or 30) + 1
        elseif result.Reason == "Locked" then
            compost.RetryAt = os.clock() + 30
            self:Alert("CompostLocked", "Auto Remove", "The Compost Machine is locked. Unlock it or switch to Delete.", "Warning")
        else
            compost.PullAt = os.clock() + 10
        end
        return 1
    end
    if #list == 0 then
        return 1.5
    end
    local remaining = known and need - coin or math.huge
    local items = {}
    local taken = {}
    local added = 0
    for _, entry in ipairs(list) do
        if added >= remaining then
            break
        end
        local count = entry.Count
        if entry.Price > 0 and remaining ~= math.huge then
            count = math.min(count, math.ceil((remaining - added) / entry.Price))
        end
        if count > 0 then
            table.insert(items, {V = entry.V, Count = count})
            table.insert(taken, {Entry = entry, Count = count})
            added += entry.Price * count
        end
    end
    if #items == 0 then
        return 1.5
    end
    table.sort(items, function(a, b)
        return a.V < b.V
    end)
    local ok, result = self:CompostRequest("AddAnts", "CompostAddAnts", {Items = items})
    if ok then
        for _, take in ipairs(taken) do
            self:NoteRemoved(take.Entry.V, take.Entry.Total, take.Count)
        end
        return 0.5
    end
    if result.Reason == "Locked" then
        compost.RetryAt = os.clock() + 30
        self:Alert("CompostLocked", "Auto Remove", "The Compost Machine is locked. Unlock it or switch to Delete.", "Warning")
    elseif result.Reason == "FavoriteLocked" and tonumber(result.V) then
        self.RemoveBlocked[math.floor(tonumber(result.V))] = os.clock() + 60
    else
        compost.RetryAt = os.clock() + 3
    end
    return 1
end

function App:UpgradeList(data)
    local now = os.clock()
    local list = {}
    for slot, entry in pairs(type(data.EquippedBySlot) == "table" and data.EquippedBySlot or {}) do
        local index = tonumber(slot)
        local value = type(entry) == "table" and tonumber(entry.V) or nil
        local unitIndex, _, level = decodeAnt(value)
        local unit = unitIndex and Game.Units["Unit" .. unitIndex]
        if index and type(unit) == "table" and level < 511 and now >= (self.UpgradeBlocked[index] or 0) then
            local cost = math.max(math.floor((tonumber(unit.Price) or 0) * 0.05 * 1.35 ^ level), 0)
            local power = self:Power(value)
            table.insert(list, {
                Slot = index,
                V = math.floor(value),
                Cost = cost,
                Score = cost > 0 and power / cost or math.huge,
            })
        end
    end
    table.sort(list, function(a, b)
        if a.Score ~= b.Score then
            return a.Score > b.Score
        end
        if a.Cost ~= b.Cost then
            return a.Cost < b.Cost
        end
        return a.Slot < b.Slot
    end)
    return list
end

function App:FoodAmount()
    local helper = Game.Helper
    if type(helper) == "table" and type(helper.GetPlayerFood) == "function" then
        local ok, value = isolate(helper.GetPlayerFood, Player.UserId)
        value = ok and tonumber(value)
        if value then
            return math.max(math.floor(value), 0)
        end
    end
    return nil
end

function App:HandlePrice(payload)
    local price = type(payload) == "table" and tonumber(payload.GoldPerFood)
    if not price then
        return
    end
    local food = self.Food
    food.Price = price
    food.PriceAt = os.clock()
    food.Remaining = math.max(tonumber(payload.RemainingSeconds) or 0, 0)
    food.Max = tonumber(payload.MaxGoldPerFood) or food.Max
end

App:Feature("AutoRoll", {
    Enable = function()
        App.Roll.Fails = 0
        App.Roll.Awaiting = false
    end,
    Disable = function()
        App.Roll.Awaiting = false
    end,
    Step = function(token)
        if not Player:GetAttribute("Init") then
            return 0.5
        end
        local roll = App.Roll
        local now = os.clock()
        if now < roll.NextAt then
            return math.min(roll.NextAt - now, 0.2)
        end
        roll.Confirmed = false
        roll.Awaiting = true
        roll.SentAt = now
        App:Send("RollAnt", {Source = "ProximityPrompt"})
        while not roll.Confirmed and os.clock() - now < 1 and App.Alive and App.State.AutoRoll and App.Tokens.AutoRoll == token do
            task.wait(0.03)
        end
        roll.Awaiting = false
        if roll.Confirmed then
            roll.Fails = 0
            roll.NextAt = roll.SentAt + App:RollInterval() + 0.1
        else
            roll.Fails += 1
            roll.NextAt = os.clock() + (roll.Fails >= 5 and 2 or 0.2)
            if roll.Fails == 12 then
                App:Notify("Auto Roll", "Rolls are not going through. Close any open purchase prompt.", "Warning")
            end
        end
        return 0
    end,
})

App:Feature("AutoBuy", {
    Step = function()
        for _, results in pairs(App.Batches) do
            App:BuyBatch(results)
        end
        return 0.25
    end,
})

App:Feature("AutoEquip", {
    Enable = function()
        App.Equip.Signature = nil
        App.Equip.RetryAt = 0
    end,
    Step = function()
        local differs, signature = App:EquipPlan()
        if differs == nil then
            App:EquipBest()
            return 10
        end
        if differs then
            local equip = App.Equip
            local now = os.clock()
            if equip.Signature ~= signature or now >= equip.RetryAt then
                equip.Signature = signature
                equip.RetryAt = now + 30
                App:EquipBest()
                return 1.5
            end
        end
        return 1
    end,
})

App:Feature("AutoRemove", {
    Enable = function()
        App.Compost.RetryAt = 0
        App.Compost.PullAt = 0
        App.Compost.Waiting = nil
    end,
    Step = function(token)
        local data = App:BackpackData()
        if not data then
            return 2
        end
        local list = App:RemoveCandidates(data)
        if not list then
            App:Alert("RemoveFilters", "Auto Remove", "Set at least one filter below it first.", "Warning")
            return 2
        end
        if App.Removal.Method == "Delete" then
            if #list == 0 then
                return 1.5
            end
            return App:DeleteStep(list, token)
        end
        return App:CompostStep(list)
    end,
})

App:Feature("AutoUpgrade", {
    Step = function(token)
        local data = App:BackpackData()
        if not data then
            return 2
        end
        local list = App:UpgradeList(data)
        if #list == 0 then
            return 2
        end
        local cash = App:Cash()
        if not cash then
            return 2
        end
        local budget = cash - App:Reserved()
        for _, pick in ipairs(list) do
            if pick.Cost <= budget then
                App:Send("UpgradeEquippedAnt", {Source = "RoomAntInfoGui", AntIndex = pick.Slot})
                local deadline = os.clock() + 1.5
                local changed = false
                while not changed and os.clock() < deadline and App.Alive and App.State.AutoUpgrade and App.Tokens.AutoUpgrade == token do
                    task.wait(0.05)
                    local fresh = App:BackpackData()
                    local slots = fresh and type(fresh.EquippedBySlot) == "table" and fresh.EquippedBySlot or nil
                    local entry = slots and slots[tostring(pick.Slot)]
                    changed = type(entry) == "table" and tonumber(entry.V) ~= pick.V
                end
                if not changed then
                    App.UpgradeBlocked[pick.Slot] = os.clock() + 5
                    return 0.5
                end
                return 0.05
            end
        end
        return 1
    end,
})

App:Feature("AutoSellFood", {
    Enable = function()
        App.Food.RequestAt = 0
        App.Food.Waiting = false
    end,
    Disable = function()
        App.Food.Waiting = false
    end,
    Step = function(token)
        local food = App.Food
        local now = os.clock()
        local expiresAt = food.PriceAt + food.Remaining - 1
        if not food.Price or now >= expiresAt then
            if now >= food.RequestAt then
                food.RequestAt = now + 2
                App:Send("RequestSellFoodPrice", {Source = "SellShopModel", UserId = Player.UserId})
            end
            return 0.3
        end
        if food.Price < food.MinX then
            return math.clamp(expiresAt - now, 0.3, 2)
        end
        if now < food.NextAt then
            return 0.3
        end
        local amount = App:FoodAmount()
        if not amount then
            App:Alert("Food", "Auto Sell Food", "Your food could not be read, so nothing was sold.", "Warning")
            return 5
        end
        if amount < 1 then
            return 1
        end
        food.Result = nil
        food.Waiting = true
        App:Send("SellPlayerFood", {FoodAmount = amount, Source = "PlayerFoodPrompt"})
        while food.Result == nil and os.clock() - now < 3 and App.Alive and App.State.AutoSellFood and App.Tokens.AutoSellFood == token do
            task.wait(0.03)
        end
        food.Waiting = false
        food.Result = nil
        food.NextAt = os.clock() + 2
        return 0.3
    end,
})

function App:BoardInfo(def)
    local helper = Game.Helper
    if type(helper) ~= "table" then
        return nil
    end
    if def.Compost then
        if type(helper.GetCompostState) ~= "function" or type(helper.GetCompostTierConfig) ~= "function" then
            return nil
        end
        local ok, success, state = isolate(helper.GetCompostState, Player.UserId)
        local level = ok and success and type(state) == "table" and tonumber(state.CompostLevel)
        if not level then
            return nil
        end
        local tierOk, tier = isolate(helper.GetCompostTierConfig, Game.Context, level)
        local nextOk, nextTier = isolate(helper.GetCompostTierConfig, Game.Context, level + 1)
        if not (tierOk and type(tier) == "table" and nextOk and type(nextTier) == "table" and nextTier ~= tier) then
            return nil
        end
        return {Def = def, Price = math.max(math.floor(tonumber(tier.UpgradePrice) or 0), 0)}
    end
    if type(helper.GetPlayerUpgradeAttributeInfo) ~= "function" then
        return nil
    end
    local ok, info = isolate(helper.GetPlayerUpgradeAttributeInfo, Game.Context, Player.UserId, def.Attribute)
    if not ok or type(info) ~= "table" or info.IsMax then
        return nil
    end
    return {Def = def, Price = math.max(math.floor(tonumber(info.Price) or 0), 0)}
end

function App:QueenRequired()
    local helper, progression = Game.Helper, Game.LuckQueen
    if type(helper) ~= "table" or type(helper.GetPlayerUpgradeAttributeLevel) ~= "function" then
        return nil
    end
    if type(progression) ~= "table" or type(progression.GetState) ~= "function" then
        return nil
    end
    local luckOk, luck = isolate(helper.GetPlayerUpgradeAttributeLevel, Player.UserId, LuckAttribute)
    local queenOk, queen = isolate(helper.GetPlayerUpgradeAttributeLevel, Player.UserId, QueenAttribute)
    if not (luckOk and queenOk and tonumber(luck) and tonumber(queen)) then
        return nil
    end
    local ok, state = isolate(progression.GetState, luck, queen)
    if ok and type(state) == "table" then
        return state.IsQueenUpgradeRequired == true
    end
    return nil
end

function App:BuyBoard(info, token)
    local boards = self.Boards
    local def = info.Def
    if def.Compost then
        local ok, result = self:CompostRequest("Upgrade", "CompostUpgrade", {})
        if not ok then
            boards.Blocked[def.Label] = os.clock() + (result.Reason == "Locked" and 300 or 30)
        end
        return ok
    end
    boards.Result = nil
    boards.Waiting = def.Attribute
    self:Send("UpgradePlayerAttribute", {AttributeName = def.Attribute})
    local deadline = os.clock() + 3
    while boards.Result == nil and os.clock() < deadline and self.Alive and self.State.AutoBoards and self.Tokens.AutoBoards == token do
        task.wait(0.03)
    end
    boards.Waiting = nil
    local response = boards.Result
    boards.Result = nil
    if type(response) == "table" and response.Success then
        return true
    end
    local reason = type(response) == "table" and type(response.Result) == "table" and response.Result.Reason
    local pause = 15
    if reason == "MaxReached" then
        pause = 600
    elseif reason == "QueenLevelRequired" or reason == "LuckLevelRequired" then
        pause = 20
    elseif reason == "Busy" or reason == "NotEnoughGold" then
        pause = 3
    end
    boards.Blocked[def.Label] = os.clock() + pause
    return false
end

function App:NextSlot(data)
    local unlocked = {}
    local count = 0
    for key, value in pairs(type(data.UnlockedAntSlots) == "table" and data.UnlockedAntSlots or {}) do
        local index = tonumber(key)
        if index and value then
            unlocked[math.floor(index)] = true
            count += 1
        end
    end
    local roomIndex = Player:GetAttribute("RoomIndex")
    local antPos = findPath(workspace, "Rooms", tostring(roomIndex), "AntPos")
    if not antPos then
        return nil
    end
    local best, bestSlot
    for _, layer in ipairs(antPos:GetChildren()) do
        for _, slot in ipairs(layer:GetChildren()) do
            local index = tonumber(slot.Name)
            if index and not unlocked[index] and (not best or index < best) then
                best, bestSlot = index, slot
            end
        end
    end
    if not best then
        return nil
    end
    local config = type(Game.NestUnlock) == "table" and Game.NestUnlock[count]
    local price = type(config) == "table" and tonumber(config.Price) or nil
    if not price then
        local prompt = findPath(bestSlot, "AntInfo", "UnlockPrompt")
        price = prompt and parseAmount(prompt.ObjectText) or nil
    end
    return best, price, roomIndex
end

function App:ClaimRewards()
    local models = Game.Rewards
    local function attempt(key, callback)
        if not models[key] or os.clock() < (self.RewardRetry[key] or 0) then
            return
        end
        local ok, claimed = isolate(callback, models[key])
        if not ok or claimed == false then
            self.RewardRetry[key] = os.clock() + 60
        elseif claimed == true then
            self.RewardRetry[key] = os.clock() + 2
        end
    end
    attempt("Online", function(model)
        local index = model:GetFirstClaimableRewardIndex()
        if index then
            return model:GetReward(index) == true
        end
        return nil
    end)
    attempt("SevenDay", function(model)
        if model:IsAward() then
            return model:GetReward() == true
        end
        return nil
    end)
    attempt("Activity", function(model)
        model:Refresh()
        for _, day in ipairs(model:GetDays()) do
            if day.Status == "Claim" then
                return model:Claim(day.DayId) == true
            end
        end
        return nil
    end)
    attempt("Index", function(model)
        for _, tab in ipairs({"Ants", "Mutations"}) do
            local state = model:GetRewardState(tab)
            if type(state) == "table" and state.CanClaim then
                return model:ClaimReward(tab) ~= false
            end
        end
        return nil
    end)
    attempt("Ride", function(model)
        local state = model:GetRewardState()
        if type(state) == "table" and state.CanClaim and state.RewardIndex then
            return model:ClaimProgressReward(state.RewardIndex) == true
        end
        return nil
    end)
    attempt("Group", function(model)
        if model:GetCanGetLikeReward() == true then
            return model:GetLikeReward() == true
        end
        return nil
    end)
end

App:Feature("AutoBoards", {
    Disable = function()
        App.Boards.Waiting = nil
    end,
    Step = function(token)
        local boards = App.Boards
        local now = os.clock()
        local infos = {}
        local gated = false
        for _, def in ipairs(UpgradeDefs) do
            if boards.Selected[def.Label] and now >= (boards.Blocked[def.Label] or 0) then
                local info = App:BoardInfo(def)
                if info then
                    table.insert(infos, info)
                    gated = gated or def.Gate ~= nil
                end
            end
        end
        if #infos == 0 then
            return 3
        end
        local queenRequired
        if gated then
            queenRequired = App:QueenRequired()
        end
        table.sort(infos, function(a, b)
            if a.Price ~= b.Price then
                return a.Price < b.Price
            end
            return a.Def.Label < b.Def.Label
        end)
        local cash = App:Cash()
        if not cash then
            return 3
        end
        local budget = cash - App:Reserved()
        for _, info in ipairs(infos) do
            local gate = info.Def.Gate
            local allowed = true
            if gate == "Luck" and queenRequired == true then
                allowed = false
            elseif gate == "Queen" and queenRequired == false then
                allowed = false
            end
            if allowed and info.Price <= budget then
                return App:BuyBoard(info, token) and 0.3 or 1
            end
        end
        return 1.5
    end,
})

App:Feature("AutoSlots", {
    Enable = function()
        App.Slots.RetryAt = 0
    end,
    Disable = function()
        App.Slots.Waiting = false
    end,
    Step = function(token)
        local slots = App.Slots
        if os.clock() < slots.RetryAt then
            return 1
        end
        local data = App:BackpackData()
        if not data then
            return 2
        end
        local index, price, roomIndex = App:NextSlot(data)
        if not index or not price then
            return 3
        end
        local cash = App:Cash()
        if not cash or cash - App:Reserved() < price then
            return 1.5
        end
        slots.Result = nil
        slots.Waiting = true
        App:Send("AddAntSlot", {Source = "ProximityPrompt", RoomIndex = roomIndex, SlotIndex = index})
        local deadline = os.clock() + 3
        while slots.Result == nil and os.clock() < deadline and App.Alive and App.State.AutoSlots and App.Tokens.AutoSlots == token do
            task.wait(0.03)
        end
        slots.Waiting = false
        local result = slots.Result
        slots.Result = nil
        if type(result) == "table" and result.Success then
            return 0.5
        end
        slots.RetryAt = os.clock() + 15
        if type(result) == "table" and (result.PromptRobuxPurchase or result.Reason == "NotEnoughGold") then
            App:Alert("SlotCash", "Auto Unlock Ant Slots", "Not enough cash for the next slot. Close the purchase prompt if one opened.", "Warning")
        end
        return 1
    end,
})

function App:HandleGearSnapshot(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.StockByItem) ~= "table" then
        return
    end
    local gear = self.Gear
    gear.Stock = snapshot.StockByItem
    gear.NextRefreshAt = tonumber(snapshot.NextRefreshAt) or 0
end

function App:GearCandidates()
    local gear = self.Gear
    local list = {}
    local now = os.clock()
    for name in pairs(gear.Selected) do
        local item = GearByName[name]
        if item and gear.Stock and (tonumber(gear.Stock[item.Id]) or 0) >= 1 and now >= (gear.Blocked[item.Id] or 0) then
            table.insert(list, item)
        end
    end
    table.sort(list, function(a, b)
        if a.Price ~= b.Price then
            return a.Price < b.Price
        end
        return a.Id < b.Id
    end)
    return list
end

function App:PurchaseGear(item)
    local gear = self.Gear
    if gear.Waiting then
        return false, "Busy"
    end
    gear.Result = nil
    gear.Waiting = item.Id
    self:Fire("GearShopRequest", {Action = "Purchase", ItemId = item.Id})
    local deadline = os.clock() + 3
    while gear.Result == nil and os.clock() < deadline and self.Alive do
        task.wait(0.03)
    end
    gear.Waiting = nil
    local result = gear.Result
    gear.Result = nil
    if type(result) == "table" and result.Success then
        return true
    end
    return false, type(result) == "table" and result.Reason or "Timeout"
end

function App:BuyGearNow()
    local gear = self.Gear
    if not next(gear.Selected) then
        self:Notify("Buy Gear", "Select at least one gear item first.", "Warning")
        return
    end
    if not gear.Stock then
        self:Notify("Buy Gear", "The shop stock is still loading.", "Info")
        return
    end
    local bought = 0
    local short
    for _ = 1, 30 do
        local list = self:GearCandidates()
        if #list == 0 then
            break
        end
        local cash = self:Cash()
        local budget = cash and cash - self:Reserved() or -1
        local picked
        for _, item in ipairs(list) do
            if item.Price <= budget then
                picked = item
                break
            end
            short = short or item.Name
        end
        if not picked then
            break
        end
        local ok, reason = self:PurchaseGear(picked)
        if ok then
            bought += 1
        else
            gear.Blocked[picked.Id] = os.clock() + 5
            if reason == "Busy" then
                break
            end
        end
    end
    if bought > 0 then
        self:Notify("Buy Gear", "Bought " .. bought .. (bought == 1 and " item." or " items."), "Success")
    elseif short then
        self:Notify("Buy Gear", "Not enough cash for " .. short .. ".", "Warning")
    else
        self:Notify("Buy Gear", "None of the selected gear is in stock.", "Info")
    end
end

function App:GearStockText()
    local gear = self.Gear
    if not gear.Stock then
        return "Loading..."
    end
    local lines = {}
    for _, name in ipairs(GearNames) do
        local item = GearByName[name]
        local count = math.floor(tonumber(gear.Stock[item.Id]) or 0)
        if count >= 1 then
            table.insert(lines, string.format("%s x%d - $%s", name, count, formatAmount(item.Price)))
        end
    end
    if #lines == 0 then
        table.insert(lines, "Nothing in stock")
    end
    local remaining = math.max(math.floor(gear.NextRefreshAt - workspace:GetServerTimeNow()), 0)
    table.insert(lines, string.format("Restock in %d:%02d", math.floor(remaining / 60), remaining % 60))
    return table.concat(lines, "\n")
end

function App:HeldEntry()
    return {
        Kind = Player:GetAttribute("BackpackHeldKind"),
        EntryKey = Player:GetAttribute("BackpackHeldEntryKey"),
        V = Player:GetAttribute("BackpackHeldAntValue"),
        ItemId = Player:GetAttribute("BackpackHeldItemId"),
        PetKey = Player:GetAttribute("BackpackHeldPetKey"),
    }
end

function App:FreeSlot(data, blocked, needsNoMutation)
    local now = workspace:GetServerTimeNow()
    local best, bestPower
    for slot, entry in pairs(type(data.EquippedBySlot) == "table" and data.EquippedBySlot or {}) do
        local index = tonumber(slot)
        local value = type(entry) == "table" and tonumber(entry.V) or nil
        if index and value and os.clock() >= (blocked[index] or 0) then
            local open
            if needsNoMutation then
                local _, tag = decodeAnt(value)
                open = tag == 0
            else
                local effect = entry.PotionEffect
                open = not (type(effect) == "table" and (tonumber(effect.ExpiresAt) or 0) > now)
            end
            if open then
                local power = self:Power(value)
                if not best or power > bestPower then
                    best, bestPower = index, power
                end
            end
        end
    end
    return best
end

function App:BestOwned(names, selected, stacks)
    for index = #names, 1, -1 do
        local item = GearByName[names[index]]
        if item and selected[item.Name] and (tonumber(stacks[item.Id]) or 0) >= 1 then
            return item
        end
    end
    return nil
end

App:Feature("AutoGear", {
    Enable = function()
        App.Gear.RequestAt = 0
    end,
    Disable = function()
        App.Gear.Waiting = nil
    end,
    Step = function(token)
        local gear = App.Gear
        if not next(gear.Selected) then
            App:Alert("GearPick", "Auto Buy Gear", "Select at least one gear item first.", "Warning")
            return 2
        end
        local now = os.clock()
        local serverNow = workspace:GetServerTimeNow()
        if not gear.Stock or serverNow >= gear.NextRefreshAt then
            if now >= gear.RequestAt then
                gear.RequestAt = now + 3
                App:Fire("GearShopRequest", {Action = "Snapshot"})
            end
            return 0.5
        end
        local list = App:GearCandidates()
        if #list == 0 then
            return math.clamp(gear.NextRefreshAt - serverNow, 1, 5)
        end
        local cash = App:Cash()
        if not cash then
            return 3
        end
        local budget = cash - App:Reserved()
        for _, item in ipairs(list) do
            if item.Price <= budget then
                local ok, reason = App:PurchaseGear(item)
                if ok then
                    return 0.3
                end
                if reason ~= "Busy" then
                    gear.Blocked[item.Id] = os.clock() + 10
                end
                return 1
            end
        end
        return 2
    end,
})

App:Feature("AutoJelly", {
    Disable = function()
        App.Jelly.Waiting = nil
    end,
    Step = function(token)
        local jelly = App.Jelly
        local data = App:BackpackData()
        if not data then
            return 2
        end
        local item = App:BestOwned(JellyNames, jelly.Selected, type(data.ItemStacks) == "table" and data.ItemStacks or {})
        if not item then
            return 3
        end
        local slot = App:FreeSlot(data, jelly.Blocked, false)
        if not slot then
            return 2
        end
        local id = HttpService:GenerateGUID(false)
        jelly.Result = nil
        jelly.Waiting = id
        App:Fire("UseAutoToolPotion", {RequestId = id, SlotIndex = slot, PotionId = item.Id})
        local deadline = os.clock() + 3
        while jelly.Result == nil and os.clock() < deadline and App.Alive and App.State.AutoJelly and App.Tokens.AutoJelly == token do
            task.wait(0.03)
        end
        jelly.Waiting = nil
        local result = jelly.Result
        jelly.Result = nil
        if type(result) == "table" and result.Success then
            jelly.Blocked[slot] = os.clock() + 5
            return 0.3
        end
        jelly.Blocked[slot] = os.clock() + 15
        return 1
    end,
})

App:Feature("AutoPotion", {
    Step = function(token)
        local potion = App.Potion
        local data = App:BackpackData()
        if not data then
            return 2
        end
        local stacks = type(data.ItemStacks) == "table" and data.ItemStacks or {}
        local item = App:BestOwned(PotionNames, potion.Selected, stacks)
        if not item then
            return 3
        end
        local slot = App:FreeSlot(data, potion.Blocked, true)
        if not slot then
            return 3
        end
        local key = "Item:" .. item.Id
        local previous = App:HeldEntry()
        local positions = type(data.Positions) == "table" and data.Positions or {}
        App:Fire("SetBackpackHeldEntry", {Kind = "Item", EntryKey = key, ItemId = item.Id, Pos = positions[key]})
        local deadline = os.clock() + 2
        while Player:GetAttribute("BackpackHeldEntryKey") ~= key and os.clock() < deadline do
            task.wait(0.03)
        end
        if Player:GetAttribute("BackpackHeldEntryKey") ~= key then
            potion.Blocked[slot] = os.clock() + 10
            return 1
        end
        local before = tonumber(stacks[item.Id]) or 0
        App:Fire("UsePotionOnRoomSlot", {RoomIndex = Player:GetAttribute("RoomIndex"), SlotIndex = slot, ItemId = item.Id})
        local used = false
        deadline = os.clock() + 3
        while not used and os.clock() < deadline and App.Alive and App.State.AutoPotion and App.Tokens.AutoPotion == token do
            task.wait(0.1)
            local fresh = App:BackpackData()
            local freshStacks = fresh and type(fresh.ItemStacks) == "table" and fresh.ItemStacks or nil
            used = freshStacks ~= nil and (tonumber(freshStacks[item.Id]) or 0) < before
        end
        if previous.EntryKey ~= key then
            App:Fire("SetBackpackHeldEntry", type(previous.Kind) == "string" and previous or {})
        end
        potion.Blocked[slot] = os.clock() + (used and 5 or 30)
        return used and 0.5 or 1
    end,
})

function App:Root()
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if root and humanoid and humanoid.Health > 0 then
        return root
    end
    return nil
end

function App:FirePrompt(prompt)
    if type(fireproximityprompt) ~= "function" then
        self:Alert("Prompt", "Events", "This executor does not provide fireproximityprompt.", "Warning")
        return false
    end
    return (isolate(fireproximityprompt, prompt))
end

function App:HoldItem(id, data)
    local key = "Item:" .. id
    if Player:GetAttribute("BackpackHeldEntryKey") == key then
        return true
    end
    local positions = data and type(data.Positions) == "table" and data.Positions or {}
    self:Fire("SetBackpackHeldEntry", {Kind = "Item", EntryKey = key, ItemId = id, Pos = positions[key]})
    local deadline = os.clock() + 1.5
    while Player:GetAttribute("BackpackHeldEntryKey") ~= key and os.clock() < deadline do
        task.wait(0.03)
    end
    return Player:GetAttribute("BackpackHeldEntryKey") == key
end

function App:DungeonStep(snapshot)
    local dungeon = self.Dungeon
    local now = os.clock()
    local id = snapshot.sessionId
    local status = snapshot.status
    if status == "ready" then
        if now >= dungeon.StartAt then
            dungeon.StartAt = now + 0.7
            self:Send("DungeonCommand", {Action = "Start", SessionId = id})
        end
        return 0.2
    end
    if status ~= "fighting" and status ~= "intermission" and status ~= "dropping" then
        return 0.3
    end
    local root = self:Root()
    local serverNow = workspace:GetServerTimeNow()
    for _, coin in ipairs(type(snapshot.timeCoins) == "table" and snapshot.timeCoins or {}) do
        local coinId = type(coin) == "table" and tonumber(coin.id or coin.Id or coin.coinId)
        local position = coinId and coin.position
        if root and typeof(position) == "Vector3" and (tonumber(coin.landsAt) or 0) <= serverNow and now >= (dungeon.CoinTried[coinId] or 0) then
            dungeon.CoinTried[coinId] = now + 1.5
            root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
            root.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.25)
            self:Send("DungeonCommand", {Action = "PickupTimeCoin", SessionId = id, CoinId = coinId})
            return 0.1
        end
    end
    if status == "fighting" then
        self:Send("DungeonCommand", {Action = "Click", SessionId = id})
    end
    return 0.1
end

function App:DungeonEntrance(tried, now)
    local star = workspace:FindFirstChild("StarEvent")
    local function usable(prompt)
        return prompt and prompt.Enabled and now >= (tried[prompt] or 0) and not (star and prompt:IsDescendantOf(star))
    end
    for _, holder in ipairs(workspace:QueryDescendants("[$DungeonEntranceId]")) do
        local prompt = holder:IsA("ProximityPrompt") and holder or holder:FindFirstChildWhichIsA("ProximityPrompt", true)
        if usable(prompt) then
            return prompt
        end
    end
    local folder = workspace:FindFirstChild("DungeonEntrances")
    if folder then
        for _, prompt in ipairs(folder:QueryDescendants("ProximityPrompt")) do
            if usable(prompt) then
                return prompt
            end
        end
    end
    return nil
end

App:Feature("AutoDungeon", {
    Enable = function()
        local run = App.DungeonRun
        run.Origin = nil
        run.Entered = false
        run.Rejected = false
        run.LastPrompt = nil
        table.clear(App.Dungeon.CoinTried)
    end,
    Disable = function()
        local run = App.DungeonRun
        local root = App:Root()
        if run.Origin and root and not Player:GetAttribute("DungeonSessionId") then
            root.CFrame = run.Origin
        end
        run.Origin = nil
        run.Entered = false
    end,
    Step = function()
        local run = App.DungeonRun
        local dungeon = App.Dungeon
        local now = os.clock()
        local snapshot = dungeon.Snapshot
        if snapshot and snapshot.sessionId and snapshot.status ~= "ended" and snapshot.status ~= "rejected" and now - dungeon.At < 5 then
            if not run.Entered and run.LastPrompt then
                run.Tried[run.LastPrompt] = now + 700
            end
            run.Entered = true
            return App:DungeonStep(snapshot)
        end
        if Player:GetAttribute("DungeonSessionId") then
            run.Entered = true
            return 0.5
        end
        if run.Rejected then
            run.Rejected = false
            if run.LastPrompt then
                run.Tried[run.LastPrompt] = now + 700
            end
        end
        local root = App:Root()
        if run.Origin and (run.Entered or now >= run.ReturnAt) then
            if root then
                root.CFrame = run.Origin
            end
            run.Origin = nil
            run.Entered = false
        end
        if not root or run.Origin then
            return 0.5
        end
        local prompt = App:DungeonEntrance(run.Tried, now)
        local holder = prompt and prompt.Parent
        local position
        if holder and holder:IsA("Attachment") then
            position = holder.WorldPosition
        elseif holder and holder:IsA("BasePart") then
            position = holder.Position
        elseif holder and holder:IsA("Model") then
            position = holder:GetPivot().Position
        end
        if not position then
            return 2
        end
        run.Tried[prompt] = now + 20
        run.LastPrompt = prompt
        run.Origin = root.CFrame
        run.ReturnAt = now + 8
        run.Entered = false
        root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
        root.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.4)
        App:FirePrompt(prompt)
        return 1
    end,
})

App:Feature("AutoStar", {
    Enable = function()
        local star = App.Star
        star.RetryAt = 0
        star.EnterBlocked = false
        star.Origin = nil
        star.Entered = false
        table.clear(App.Dungeon.CoinTried)
    end,
    Disable = function()
        local star = App.Star
        local root = App:Root()
        if star.Origin and root and not Player:GetAttribute("DungeonSessionId") then
            root.CFrame = star.Origin
        end
        star.Origin = nil
        star.Entered = false
    end,
    Step = function()
        local star = App.Star
        local dungeon = App.Dungeon
        local now = os.clock()
        local snapshot = dungeon.Snapshot
        if snapshot and snapshot.sessionId and snapshot.status ~= "ended" and snapshot.status ~= "rejected" and now - dungeon.At < 5 then
            star.Entered = true
            if App.State.AutoDungeon then
                return 0.3
            end
            return App:DungeonStep(snapshot)
        end
        if Player:GetAttribute("DungeonSessionId") then
            star.Entered = true
            return 0.5
        end
        if star.Origin and (star.Entered or now >= star.ReturnAt) then
            local root = App:Root()
            if root then
                root.CFrame = star.Origin
            end
            star.Origin = nil
            star.Entered = false
        end
        if now < star.RetryAt then
            return 0.5
        end
        local folder = workspace:FindFirstChild("StarEvent")
        local enter = findPath(folder, "Enterpromt", "ProximityPrompt")
        local flip = findPath(folder, "Flippromt", "ProximityPrompt")
        if enter and enter.Enabled then
            if not star.EnterBlocked and Player:GetAttribute("StarEventUsedCycleId") == nil and now >= star.EnterAt then
                star.EnterAt = now + 4
                local root = App:Root()
                local part = enter.Parent
                if root and part and part:IsA("BasePart") then
                    if (root.Position - part.Position).Magnitude > 10 then
                        star.Origin = star.Origin or root.CFrame
                        star.ReturnAt = now + 8
                        star.Entered = false
                        root.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
                        root.AssemblyLinearVelocity = Vector3.zero
                        task.wait(0.4)
                    end
                    App:FirePrompt(enter)
                end
            end
            return 0.5
        end
        star.EnterBlocked = false
        if not (flip and flip.Enabled) then
            return 1
        end
        local data = App:BackpackData()
        local stacks = data and type(data.ItemStacks) == "table" and data.ItemStacks or {}
        if (tonumber(stacks[StarItem]) or 0) < 1 then
            return 3
        end
        if not App:HoldItem(StarItem, data) then
            return 1
        end
        App:FirePrompt(flip)
        return 0.45
    end,
})

App:Feature("AutoStrawberry", {
    Disable = function()
        local strawberry = App.Strawberry
        local root = App:Root()
        if strawberry.Origin and root then
            root.CFrame = strawberry.Origin
        end
        strawberry.Origin = nil
    end,
    Step = function()
        local strawberry = App.Strawberry
        local root = App:Root()
        if not root or Player:GetAttribute("DungeonSessionId") then
            return 1
        end
        local now = os.clock()
        if workspace:GetAttribute("CurrentActivityId") == "StrawberryKing" then
            for _, prompt in ipairs(workspace:QueryDescendants("ProximityPrompt")) do
                if prompt.Name == "ActivityCoinPrompt" and prompt.Enabled and now >= (strawberry.Tried[prompt] or 0) then
                    local part = prompt.Parent
                    if part and part:IsA("BasePart") then
                        strawberry.Tried[prompt] = now + 2
                        strawberry.Origin = strawberry.Origin or root.CFrame
                        root.CFrame = CFrame.new(part.Position + Vector3.new(0, 4, 0))
                        root.AssemblyLinearVelocity = Vector3.zero
                        task.wait(0.3)
                        App:FirePrompt(prompt)
                        task.wait(0.15)
                        return 0
                    end
                end
            end
        end
        if strawberry.Origin then
            root.CFrame = strawberry.Origin
            strawberry.Origin = nil
        end
        return 0.5
    end,
})

App:Feature("AutoWheel", {
    Step = function()
        local model = Game.Wheel
        if type(model) ~= "table" then
            return 10
        end
        local ok, spun = isolate(function()
            if model:CanSpin() then
                return model:Spin(1) ~= false
            end
            return nil
        end)
        if ok and spun == true then
            return 1.5
        end
        return 5
    end,
})

App:Feature("AutoRewards", {
    Step = function()
        App:ClaimRewards()
        return 10
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

function App:StopAll()
    for key in pairs(self.Features) do
        if key ~= "AntiAFK" then
            self:SetFeature(key, false)
        end
    end
end

function App:Unload()
    if not self.Alive then
        return
    end
    self:StopAll()
    self:SetFeature("AntiAFK", false)
    pcall(self.SetCloverHidden, self, false)
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

App:Connect(EventRemote.OnClientEvent, function(name, payload)
    if not App.Alive then
        return
    end
    if name == "RollAntResult" then
        local ok, err = pcall(App.HandleRoll, App, payload)
        if not ok then
            App:Warn("Roll", err)
        end
    elseif name == "ClaimRolledAntResult" then
        local ok, err = pcall(App.HandleClaim, App, payload)
        if not ok then
            App:Warn("Claim", err)
        end
    elseif name == "DiscardHeldAntResult" then
        if type(payload) == "table" and App.Discards[payload.RequestId] == false then
            App.Discards[payload.RequestId] = payload
        end
    elseif name == "CompostMachineResult" then
        if type(payload) == "table" and App.Compost.Waiting == payload.Operation then
            App.Compost.Result = payload
        end
    elseif name == "UpgradePlayerAttributeResult" then
        local result = type(payload) == "table" and payload.Result
        if App.Boards.Waiting and type(result) == "table" and result.AttributeName == App.Boards.Waiting then
            App.Boards.Result = payload
        end
    elseif name == "DungeonState" then
        if type(payload) == "table" then
            App.Dungeon.Snapshot = payload
            App.Dungeon.At = os.clock()
            if payload.status == "rejected" then
                App.DungeonRun.Rejected = true
            end
        end
    elseif name == "StarEventResult" then
        if type(payload) == "table" and not payload.Success then
            local star = App.Star
            if payload.Action == "Enter" and payload.Reason == "DungeonAlreadyChallenged" then
                star.EnterBlocked = true
            elseif payload.Reason == "EventNotStarted" or payload.Reason == "EventExpired" or payload.Reason == "EventUnavailable" then
                star.RetryAt = os.clock() + 30
            end
        end
    elseif name == "GearShopSnapshot" then
        App:HandleGearSnapshot(payload)
    elseif name == "GearShopResult" then
        if type(payload) == "table" then
            App:HandleGearSnapshot(payload.Snapshot)
            if App.Gear.Waiting and payload.ItemId == App.Gear.Waiting then
                App.Gear.Result = payload
            end
        end
    elseif name == "AutoUsePotionResult" then
        if type(payload) == "table" and App.Jelly.Waiting and payload.RequestId == App.Jelly.Waiting then
            App.Jelly.Result = payload
        end
    elseif name == "AddAntSlotResult" then
        if App.Slots.Waiting then
            App.Slots.Result = type(payload) == "table" and payload or false
        end
    elseif name == "SellFoodPriceUpdate" then
        App:HandlePrice(payload)
    elseif name == "SellResuit" then
        if App.Food.Waiting then
            App.Food.Result = type(payload) == "table" and payload or false
        end
    end
end)
App:Send("RequestSellFoodPrice", {Source = "SellShopModel", UserId = Player.UserId})

Airflow.Theme.Background = Color3.fromRGB(18, 17, 14)
Airflow.Theme.Surface = Color3.fromRGB(24, 22, 18)
Airflow.Theme.Surface2 = Color3.fromRGB(31, 28, 23)
Airflow.Theme.Surface3 = Color3.fromRGB(50, 45, 37)
Airflow.Theme.Stroke = Color3.fromRGB(46, 41, 33)
Airflow.Theme.StrokeHover = Color3.fromRGB(150, 114, 58)
Airflow.Theme.Accent = Color3.fromRGB(244, 182, 74)
Airflow.Theme.AccentDark = Color3.fromRGB(40, 28, 9)
Airflow.Theme.Text = Color3.fromRGB(242, 238, 229)
Airflow.Theme.Muted = Color3.fromRGB(160, 151, 137)

local Window = Airflow:CreateWindow({
    Name = "Ant Empire",
    Icon = "bug",
    Size = UDim2.fromOffset(640, 470),
    MinSize = Vector2.new(280, 220),
    ToggleUIKeybind = Enum.KeyCode.RightControl,
    KeepOnScreen = true,
    MaxNotifications = 4,
    OpenButton = {Title = "Ant Empire", Icon = "bug"},
    Loading = false,
    ConfigurationSaving = {Enabled = false},
})
App.Window = Window
if Window._titleLabel then
    Window._titleLabel.Position = UDim2.fromOffset(60, 31)
end

local MainTab = Window:CreateTab({Name = "Main", Icon = "bug"})
local UpgradesTab = Window:CreateTab({Name = "Upgrades", Icon = "trending-up"})
local GearTab = Window:CreateTab({Name = "Gear", Icon = "flask-conical"})
local FoodTab = Window:CreateTab({Name = "Food", Icon = "apple"})
local BackpackTab = Window:CreateTab({Name = "Backpack", Icon = "backpack"})
local EventsTab = Window:CreateTab({Name = "Events", Icon = "star"})
local RewardsTab = Window:CreateTab({Name = "Rewards", Icon = "gift"})
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

App:AddToggle(MainTab, "AutoRoll", "Auto Roll Ants")

MainTab:CreateDivider()

App:AddToggle(MainTab, "AutoBuy", "Auto Buy Ants")
local rarityControl
rarityControl = MainTab:CreateDropdown({
    Name = "Minimum Rarity",
    Options = RarityOptions,
    CurrentOption = "Any",
    SearchAfter = 20,
    Callback = function(value)
        if value == nil then
            task.defer(function()
                if App.Alive then
                    rarityControl:Set(App.Options.MinRarity, true)
                end
            end)
            return
        end
        App.Options.MinRarity = value
        App.Options.MinRank = RarityRank[value] or 0
    end,
})
App.Controls.MinRarity = rarityControl
local costControl
costControl = MainTab:CreateInput({
    Name = "Min Cost",
    Desc = "e.g. 50K or 2M",
    Placeholder = "No limit",
    CurrentValue = "",
    MaxLength = 24,
    Callback = function(text)
        text = type(text) == "string" and string.match(text, "^%s*(.-)%s*$") or ""
        if text == "" then
            App.Options.MinCost = nil
            App.Options.MinCostText = ""
            return
        end
        local amount = parseAmount(text)
        if amount then
            App.Options.MinCost = amount
            App.Options.MinCostText = text
            return
        end
        App:Notify("Min Cost", "That amount could not be read. Use values like 50000, 50K or 2.5M.", "Warning")
        task.defer(function()
            if App.Alive then
                costControl:Set(App.Options.MinCostText, true)
            end
        end)
    end,
})
App.Controls.MinCost = costControl
App.Controls.Names = MainTab:CreateDropdown({
    Name = "Ant Names",
    Options = AntNames,
    CurrentOption = {},
    MultipleOptions = true,
    Placeholder = "Any",
    SearchAfter = 6,
    Callback = function(values)
        local names = {}
        for _, name in ipairs(type(values) == "table" and values or {}) do
            names[name] = true
        end
        App.Options.Names = names
    end,
})

MainTab:CreateDivider()

App:AddToggle(MainTab, "AutoEquip", "Auto Equip Best Ants")

App:AddToggle(BackpackTab, "AutoRemove", "Auto Remove Ants", "Needs at least one filter below")
local methodControl
methodControl = BackpackTab:CreateDropdown({
    Name = "Remove Method",
    Options = {"Compost", "Delete"},
    CurrentOption = "Compost",
    SearchAfter = 20,
    Callback = function(value)
        if value == nil then
            task.defer(function()
                if App.Alive then
                    methodControl:Set(App.Removal.Method, true)
                end
            end)
            return
        end
        App.Removal.Method = value
    end,
})
App.Controls.RemoveMethod = methodControl
local removeRarityControl
removeRarityControl = BackpackTab:CreateDropdown({
    Name = "Maximum Rarity",
    Options = RarityOptions,
    CurrentOption = "Any",
    SearchAfter = 20,
    Callback = function(value)
        if value == nil then
            task.defer(function()
                if App.Alive then
                    removeRarityControl:Set(App.Removal.MaxRarity, true)
                end
            end)
            return
        end
        App.Removal.MaxRarity = value
        App.Removal.MaxRank = RarityRank[value] or 0
    end,
})
App.Controls.RemoveRarity = removeRarityControl
local removeCostControl
removeCostControl = BackpackTab:CreateInput({
    Name = "Max Cost",
    Desc = "e.g. 50K or 2M",
    Placeholder = "No limit",
    CurrentValue = "",
    MaxLength = 24,
    Callback = function(text)
        text = type(text) == "string" and string.match(text, "^%s*(.-)%s*$") or ""
        if text == "" then
            App.Removal.MaxCost = nil
            App.Removal.MaxCostText = ""
            return
        end
        local amount = parseAmount(text)
        if amount then
            App.Removal.MaxCost = amount
            App.Removal.MaxCostText = text
            return
        end
        App:Notify("Max Cost", "That amount could not be read. Use values like 50000, 50K or 2.5M.", "Warning")
        task.defer(function()
            if App.Alive then
                removeCostControl:Set(App.Removal.MaxCostText, true)
            end
        end)
    end,
})
App.Controls.RemoveCost = removeCostControl
App.Controls.RemoveNames = BackpackTab:CreateDropdown({
    Name = "Ant Names To Remove",
    Options = RemoveNames,
    CurrentOption = {},
    MultipleOptions = true,
    Placeholder = "Any",
    SearchAfter = 6,
    Callback = function(values)
        local names = {}
        for _, name in ipairs(type(values) == "table" and values or {}) do
            names[name] = true
        end
        App.Removal.Names = names
    end,
})
App.Controls.KeepTraits = BackpackTab:CreateToggle({
    Name = "Keep Trait Ants",
    CurrentValue = true,
    Callback = function(value)
        App.Removal.KeepTraits = value == true
    end,
})

App:AddToggle(UpgradesTab, "AutoUpgrade", "Auto Upgrade Ants", "Levels up equipped ants")

UpgradesTab:CreateDivider()

App:AddToggle(UpgradesTab, "AutoBoards", "Auto Buy Upgrades")
App.Controls.Boards = UpgradesTab:CreateDropdown({
    Name = "Upgrades",
    Options = UpgradeLabels,
    CurrentOption = table.clone(UpgradeLabels),
    MultipleOptions = true,
    Placeholder = "None",
    SearchAfter = 20,
    Callback = function(values)
        local selected = {}
        for _, label in ipairs(type(values) == "table" and values or {}) do
            selected[label] = true
        end
        App.Boards.Selected = selected
    end,
})

UpgradesTab:CreateDivider()

App:AddToggle(UpgradesTab, "AutoSlots", "Auto Unlock Ant Slots")

local function selectionCallback(target)
    return function(values)
        local selected = {}
        for _, name in ipairs(type(values) == "table" and values or {}) do
            selected[name] = true
        end
        target.Selected = selected
    end
end

App:AddToggle(GearTab, "AutoGear", "Auto Buy Gear")
App.Controls.Gear = GearTab:CreateDropdown({
    Name = "Gear",
    Options = GearNames,
    CurrentOption = {},
    MultipleOptions = true,
    Placeholder = "None",
    SearchAfter = 20,
    Callback = selectionCallback(App.Gear),
})
App.GearStock = GearTab:CreateParagraph({Title = "In Stock", Content = "Loading..."})
GearTab:CreateButton({Name = "Buy Selected Gear", Icon = "shopping-cart", Callback = function()
    task.spawn(function()
        App:BuyGearNow()
    end)
end})

GearTab:CreateDivider()

App:AddToggle(GearTab, "AutoJelly", "Auto Use Speed Jelly")
App.Controls.Jelly = GearTab:CreateDropdown({
    Name = "Jelly",
    Options = JellyNames,
    CurrentOption = table.clone(JellyNames),
    MultipleOptions = true,
    Placeholder = "None",
    SearchAfter = 20,
    Callback = selectionCallback(App.Jelly),
})

GearTab:CreateDivider()

App:AddToggle(GearTab, "AutoPotion", "Auto Use Mutation Potions", "Permanent. Strongest unmutated ant first")
App.Controls.Potions = GearTab:CreateDropdown({
    Name = "Potions",
    Options = PotionNames,
    CurrentOption = table.clone(PotionNames),
    MultipleOptions = true,
    Placeholder = "None",
    SearchAfter = 20,
    Callback = selectionCallback(App.Potion),
})

App:AddToggle(EventsTab, "AutoDungeon", "Auto Dungeon", "Enters when an entrance appears and fights the boss")

EventsTab:CreateDivider()

App:AddToggle(EventsTab, "AutoStar", "Auto Star Event", "Submits Stars, enters the portal and fights the boss")

EventsTab:CreateDivider()

App:AddToggle(EventsTab, "AutoStrawberry", "Auto Strawberry Event", "Teleports to strawberry coins and picks them up")
App:AddToggle(EventsTab, "AutoWheel", "Auto Spin Wheel", "Spends strawberry coins on the King's wheel")

App:AddToggle(RewardsTab, "AutoRewards", "Auto Claim Rewards")
RewardsTab:CreateParagraph({
    Title = "What is claimed",
    Content = "Online rewards, 7 day login, 14 day event login, ant and mutation index rewards, mount progress and the daily group reward.",
})

App:AddToggle(FoodTab, "AutoSellFood", "Auto Sell Food")
local priceDeadline = os.clock() + 1.5
while not App.Food.Max and os.clock() < priceDeadline do
    task.wait(0.05)
end
local highestX = math.ceil(math.max(App.Food.Max or 2, 2) * 20 - 0.001) / 20
App.Controls.MinX = FoodTab:CreateSlider({
    Name = "Minimum X",
    Range = {0.5, highestX},
    Increment = 0.05,
    Suffix = "x",
    CurrentValue = 1,
    Callback = function(value)
        value = tonumber(value)
        if value then
            App.Food.MinX = value
        end
    end,
})

SettingsTab:CreateSection("Session")
App:AddToggle(SettingsTab, "AntiAFK", "Anti AFK")
App.Controls.HideClover = SettingsTab:CreateToggle({
    Name = "Hide Clover Effect",
    CurrentValue = false,
    Callback = function(value)
        App:SetCloverHidden(value)
    end,
})
SettingsTab:CreateButton({Name = "Stop All", Icon = "square", Callback = function()
    App:StopAll()
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
    local width = math.clamp(viewport.X - 24, 280, 640)
    local height = math.clamp(viewport.Y - 24, 220, 470)
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
    local ok, err = pcall(App.Layout, App)
    if not ok then
        App:Warn("Layout", err)
    end
end)
App:Connect(Window.Gui.Destroying, function()
    App:Unload()
end)

App:SetFeature("AntiAFK", true)

task.spawn(function()
    local shown
    while App.Alive do
        local gear = App.Gear
        local now = os.clock()
        if (not gear.Stock or workspace:GetServerTimeNow() >= gear.NextRefreshAt) and now >= gear.RequestAt then
            gear.RequestAt = now + 3
            pcall(App.Fire, App, "GearShopRequest", {Action = "Snapshot"})
        end
        if App.HideClover and not (App.CloverFrame and App.CloverFrame.Parent) then
            pcall(App.SetCloverHidden, App, true)
        end
        local text = App:GearStockText()
        if text ~= shown then
            shown = text
            pcall(function()
                App.GearStock:Set(text)
            end)
        end
        task.wait(1)
    end
end)

task.defer(function()
    if App.Alive then
        local ok, err = pcall(App.Layout, App)
        if not ok then
            App:Warn("Layout", err)
        end
    end
end)

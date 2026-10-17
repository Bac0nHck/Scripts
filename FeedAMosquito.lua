if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10747719434 and game.PlaceId ~= 125310131519813 then
    error("Feed A Mosquito: this game is not supported.", 0)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local Player = Players.LocalPlayer
local Environment = type(getgenv) == "function" and getgenv() or _G
local AppKey = "FeedAMosquitoAirflow"
local Previous = Environment[AppKey]
if type(Previous) == "table" and type(Previous.Unload) == "function" then
    pcall(Previous.Unload, Previous)
end

local function path(root, ...)
    for _, name in ipairs({...}) do
        root = root and root:FindFirstChild(name)
    end
    return root
end

local function selectAll(options)
    local selected = {}
    for _, option in ipairs(options) do
        selected[option] = true
    end
    return selected
end

local ConfigFolder = ReplicatedStorage:WaitForChild("Scripts", 30)
ConfigFolder = ConfigFolder and ConfigFolder:WaitForChild("Configs", 30)
if not ConfigFolder then
    error("Feed A Mosquito: game configuration did not load.", 0)
end

local Configs = {}
for _, name in ipairs({"Weapon", "Mosquito", "Size", "Area", "Base", "BloodTransfusion", "DamageUpgrade", "SpeedUpgrade"}) do
    local source = ConfigFolder:FindFirstChild(name .. "Config")
    local ok, value = pcall(require, source)
    if not ok or type(value) ~= "table" then
        error("Feed A Mosquito: could not load " .. name .. " configuration.", 0)
    end
    Configs[name] = value
end

local Rarities = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Divine", "Secret", "Cosmic"}
local Sizes = {"Mini", "Small", "Normal", "Middle", "Big", "Large", "ExtraLarge"}
local Zones = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Divine", "Secret"}
local WeaponList = {}
for _, config in pairs(Configs.Weapon) do
    if config.CoinId == "Main" and tonumber(config.CoinCount) then
        table.insert(WeaponList, config)
    end
end
table.sort(WeaponList, function(a, b)
    return (a.Damage or 0) < (b.Damage or 0)
end)
local WeaponNames = {}
for _, config in ipairs(WeaponList) do
    table.insert(WeaponNames, config.Name or config.Id)
end

local EggByName = {}
for id, config in pairs(Configs.Mosquito) do
    if config.Prefab then
        local name = config.Prefab .. "Egg"
        if EggByName[name] ~= nil then
            EggByName[name] = false
        else
            EggByName[name] = {ItemId = id, Config = config}
        end
    end
end

local App = {
    Running = true,
    Connections = {},
    Workers = {},
    Controls = {},
    Data = {},
    CharacterData = {},
    Bindings = {},
    Cooldowns = {},
    Pending = {},
    PromptOriginals = setmetatable({}, {__mode = "k"}),
    EggCooldowns = setmetatable({}, {__mode = "k"}),
    Config = {Rarities = Rarities, Sizes = Sizes, Zones = Zones, Weapons = WeaponNames},
    Status = "Waiting for player data",
    Revision = 0,
    Settings = {
        AutoKill = false,
        BossZones = {Common = true},
        BossPriority = "Weakest",
        FarmDistance = 4,
        MovementMode = "Smooth",
        TravelSpeed = 100,
        RetreatHealth = 25,
        AutoCollectEggs = false,
        AutoPlaceEggs = false,
        AutoHatch = false,
        EggRarities = selectAll(Rarities),
        EggSizes = selectAll(Sizes),
        AutoPlaceBest = false,
        AutoFeed = false,
        FeedRarities = selectAll(Rarities),
        FeedPriority = "Highest Income",
        AutoBlood = false,
        FeedHealth = 20,
        AutoCollectMoney = false,
        AutoClaimOffline = false,
        AutoUpgrade = false,
        UpgradeTypes = selectAll({"Base", "Blood Transfusion", "Damage", "Speed"}),
        GoldReserve = 0,
        AutoBuyWeapon = false,
        AutoEquipBest = false,
        WeaponFilter = selectAll(WeaponNames),
        InstantPrompts = false,
        AntiAFK = true,
    },
}
Environment[AppKey] = App

function App:Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self.Connections, connection)
    return connection
end

function App:Notify(title, text, kind)
    if self.Window and self.Running then
        pcall(self.Window.Notify, self.Window, {Title = title, Content = text, Type = kind or "Info", Duration = 4})
    end
end

function App:Warn(key, failure)
    local now = os.clock()
    self.Warnings = self.Warnings or {}
    if now >= (self.Warnings[key] or 0) then
        self.Warnings[key] = now + 15
        warn("[Feed A Mosquito] " .. key .. ": " .. tostring(failure))
    end
end

function App:PlayerActor()
    local id = Player:FindFirstChild("ActorId")
    return id and id.Value or "Player_" .. Player.UserId
end

function App:Remote(actor, category, name)
    return path(ReplicatedStorage, "Runtime", "Actors", actor, category, name)
end

function App:Fire(actor, name, delay, ...)
    if not self.Running or not actor then
        return false
    end
    local key = actor .. "/" .. name
    local now = os.clock()
    if now < (self.Cooldowns[key] or 0) then
        return false
    end
    local remote = self:Remote(actor, "Events", name)
    if not remote or not remote:IsA("RemoteEvent") then
        return false
    end
    self.Cooldowns[key] = now + (delay or 1)
    local arguments = table.pack(...)
    local ok, failure = pcall(function()
        remote:FireServer(table.unpack(arguments, 1, arguments.n))
    end)
    if not ok then
        self:Warn(name, failure)
    end
    return ok
end

function App:Invoke(name, callback, ...)
    if not self.Running or self.Pending[name] then
        return false
    end
    local remote = self:Remote(self:PlayerActor(), "Functions", name)
    if not remote or not remote:IsA("RemoteFunction") then
        return false
    end
    local pending = {Time = os.clock()}
    local arguments = table.pack(...)
    self.Pending[name] = pending
    pending.Thread = task.spawn(function()
        local results = table.pack(pcall(function()
            return remote:InvokeServer(table.unpack(arguments, 1, arguments.n))
        end))
        if self.Pending[name] ~= pending then
            return
        end
        self.Pending[name] = nil
        if not self.Running then
            return
        end
        if not results[1] then
            self:Warn(name, results[2])
        elseif callback then
            callback(table.unpack(results, 2, results.n))
        end
    end)
    return true
end

function App:BindData(slot, actor)
    local current = self.Bindings[slot]
    local remote = path(ReplicatedStorage, "Runtime", "SyncEntities", actor, "SyncEvent")
    if current and current.Actor == actor and current.Remote == remote and remote and remote.Parent then
        if not current.Ready and os.clock() >= current.RetryAt then
            current.RetryAt = os.clock() + 5
            remote:FireServer("require_all")
        end
        return
    end
    if current and current.Connection then
        current.Connection:Disconnect()
    end
    self.Bindings[slot] = nil
    if slot == "Player" then
        self.Ready = false
        self.Data = {}
    else
        self.CharacterData = {}
    end
    if not remote then
        return
    end
    local binding = {Actor = actor, Remote = remote, Ready = false, RetryAt = os.clock() + 5}
    self.Bindings[slot] = binding
    binding.Connection = remote.OnClientEvent:Connect(function(operation, payload)
        if not self.Running or self.Bindings[slot] ~= binding or type(payload) ~= "table" then
            return
        end
        if operation ~= "sync_all" and operation ~= "sync_value" then
            return
        end
        local data = slot == "Player" and self.Data or self.CharacterData
        if operation == "sync_all" then
            table.clear(data)
            binding.Ready = true
        end
        for key, entry in pairs(payload) do
            if type(entry) == "table" then
                local value = entry.Value
                if value == "__nil__" then
                    data[key] = nil
                else
                    data[key] = value
                end
                if slot == "Player" and key == "Coins" then
                    self.CoinRevision = (self.CoinRevision or 0) + 1
                end
            end
        end
        if slot == "Player" then
            self.Ready = binding.Ready
            self.Revision = self.Revision + 1
            if operation == "sync_all" and self.Spending and self.Spending.Resync and not self.Pending.BuyWeapon then
                self.Spending = nil
            end
        end
    end)
    remote:FireServer("require_all")
end

function App:RefreshData()
    for name, pending in pairs(self.Pending) do
        if os.clock() - pending.Time > 12 then
            self.Pending[name] = nil
            if pending.Thread then
                pcall(task.cancel, pending.Thread)
            end
            if name == "BuyWeapon" then
                self:Set("AutoBuyWeapon", false)
                self:Set("AutoUpgrade", false)
                for _, key in ipairs({"AutoBuyWeapon", "AutoUpgrade"}) do
                    if self.Controls[key] then
                        self.Controls[key]:Set(false, true)
                    end
                end
            elseif name == "UseWeapon" then
                self:Set("AutoEquipBest", false)
                if self.Controls.AutoEquipBest then
                    self.Controls.AutoEquipBest:Set(false, true)
                end
            end
            self:Notify("Request timed out", "The related automation has been stopped.", "Warning")
        end
    end
    local now = os.clock()
    if now >= (self.CleanupAt or 0) then
        self.CleanupAt = now + 30
        for key, expires in pairs(self.Cooldowns) do
            if expires < now - 30 then
                self.Cooldowns[key] = nil
            end
        end
    end
    self:BindData("Player", self:PlayerActor())
    local character = Player.Character
    local id = character and character:FindFirstChild("ActorId")
    self:BindData("Character", id and id.Value or "")
end

function App:Character()
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and root and humanoid.Health > 0 then
        return character, humanoid, root
    end
end

function App:Base()
    local bases = path(workspace, "SafeZone", "Bases")
    if bases then
        for _, base in ipairs(bases:GetChildren()) do
            local owner = base:FindFirstChild("Player")
            if owner and owner:IsA("ObjectValue") and owner.Value == Player then
                return base
            end
        end
    end
end

function App:Gold()
    local coins = self.Data.Coins
    return type(coins) == "table" and (tonumber(coins.Main) or 0) or tonumber(coins) or 0
end

function App:GetStatus()
    if not self.Running then
        return "Unloaded"
    end
    if not self.Ready then
        return "Waiting for player data"
    end
    return self.Status .. " | Gold: " .. tostring(math.floor(self:Gold()))
end

function App:CancelCollect()
    if self.Collecting then
        local prompt = self.Collecting.Prompt
        if prompt and prompt.Parent then
            pcall(prompt.InputHoldEnd, prompt)
        end
        if self.Collecting.Thread then
            pcall(task.cancel, self.Collecting.Thread)
        end
        self.Collecting = nil
    end
end

function App:Feeding()
    local value = path(Player.Character, "FeedingMosquitoUid")
    if value and value.Value ~= "" then
        return value.Value
    end
    return self.FeedingUid
end

function App:StopFeeding()
    local uid = self:Feeding()
    if uid and uid ~= self.StoppedFeedingUid then
        if self:Fire("Mosquito_" .. uid, "StopFeedMosquito", 0.5) then
            self.StoppedFeedingUid = uid
        end
    elseif not uid then
        self.StoppedFeedingUid = nil
    end
    self.FeedingUid = nil
    self.FeedStarted = nil
end

function App:LeaveSeat()
    if not self.Transfusing then
        return
    end
    self:Fire(self:PlayerActor(), "StopTransfuseBlood", 0.3)
    local _, humanoid = self:Character()
    if humanoid then
        humanoid.Sit = false
    end
    self.Transfusing = nil
end

function App:Move(position, target)
    local _, humanoid, root = self:Character()
    if not root then
        return false
    end
    self:LeaveSeat()
    if humanoid.Sit then
        humanoid.Sit = false
    end
    self.MoveRequested = true
    self.MoveGoal = {Position = position, Target = target, Root = root}
    return true
end

function App:MovementFrame(delta)
    local goal = self.MoveGoal
    if not goal or not goal.Root.Parent or not self.Running then
        return
    end
    local root = goal.Root
    local displacement = goal.Position - root.Position
    local position = goal.Position
    if self.Settings.MovementMode ~= "Teleport" then
        local step = math.clamp(tonumber(self.Settings.TravelSpeed) or 100, 30, 250) * math.min(delta, 0.05)
        if displacement.Magnitude > step then
            position = root.Position + displacement.Unit * step
        end
    end
    local target = goal.Target
    if displacement.Magnitude > 0.1 or target then
        if target and (target - position).Magnitude > 0.1 then
            root.CFrame = CFrame.lookAt(position, target)
        else
            root.CFrame = CFrame.new(position) * root.CFrame.Rotation
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

function App:ReturnBase()
    local base = self:Base()
    local spawn = base and (base:FindFirstChild("SpawnPoint") or base:FindFirstChild("BasePart"))
    if spawn then
        self:Move(spawn.Position + Vector3.new(0, 3, 0))
        return true
    end
    return false
end

function App:PatchPrompt(prompt)
    if not self.Settings.InstantPrompts or not prompt:IsA("ProximityPrompt") then
        return
    end
    if self.PromptOriginals[prompt] == nil then
        self.PromptOriginals[prompt] = prompt.HoldDuration
    end
    prompt.HoldDuration = 0
end

function App:RestorePrompts()
    for prompt, duration in pairs(self.PromptOriginals) do
        if prompt.Parent then
            pcall(function()
                prompt.HoldDuration = duration
            end)
        end
    end
    table.clear(self.PromptOriginals)
end

function App:Set(key, value)
    if not self.Running or self.Settings[key] == nil then
        return
    end
    self.Settings[key] = value
    if key == "InstantPrompts" then
        if value then
            for _, prompt in ipairs(workspace:QueryDescendants("ProximityPrompt")) do
                self:PatchPrompt(prompt)
            end
        else
            self:RestorePrompts()
        end
    elseif key == "AutoCollectEggs" and not value then
        self:CancelCollect()
    elseif key == "AutoFeed" and not value then
        self:StopFeeding()
    elseif key == "AutoBlood" and not value then
        self:LeaveSeat()
    end
    if (key == "AutoKill" or key == "AutoFeed" or key == "AutoCollectEggs") and not self.Settings.AutoKill and not self.Settings.AutoFeed and not self.Settings.AutoCollectEggs then
        self.Recovering = nil
        self.FeedRecovering = nil
    end
    if (key == "AutoKill" or key == "AutoCollectEggs" or key == "AutoFeed" or key == "AutoBlood") and not value then
        self.MoveGoal = nil
    end
    if key == "EggRarities" or key == "EggSizes" then
        self:CancelCollect()
    end
    self.UpgradeNext = 0
    self.WeaponNext = 0
    self.BestSignature = nil
end

function App:StopAll()
    self:CancelCollect()
    self:StopFeeding()
    self:LeaveSeat()
    self.Recovering = nil
    self.FeedRecovering = nil
    self.MoveGoal = nil
    for key, value in pairs(self.Settings) do
        if type(value) == "boolean" and key ~= "AntiAFK" then
            self.Settings[key] = false
            local control = self.Controls[key]
            if control then
                pcall(control.Set, control, false, true)
            end
        end
    end
    self:RestorePrompts()
    self.Status = "Stopped"
end

function App:Unload()
    if self.Unloading or not self.Running then
        return
    end
    self.Unloading = true
    self:StopAll()
    self.Running = false
    for _, binding in pairs(self.Bindings) do
        if binding.Connection then
            pcall(binding.Connection.Disconnect, binding.Connection)
        end
    end
    for _, connection in ipairs(self.Connections) do
        pcall(connection.Disconnect, connection)
    end
    for _, thread in ipairs(self.Workers) do
        if thread ~= coroutine.running() then
            pcall(task.cancel, thread)
        end
    end
    for _, pending in pairs(self.Pending) do
        if pending.Thread then
            pcall(task.cancel, pending.Thread)
        end
    end
    if self.Window then
        pcall(self.Window.Destroy, self.Window)
    end
    if Environment[AppKey] == self then
        Environment[AppKey] = nil
    end
    self.Unloading = false
    self.Unloaded = true
end

function App:MatchesEgg(info)
    local config = info and Configs.Mosquito[info.ItemId]
    return config and self.Settings.EggRarities[config.Rarity] == true and self.Settings.EggSizes[info.SizeId] == true
end

function App:Potential(info)
    local config = info and Configs.Mosquito[info.ItemId]
    local size = info and Configs.Size[info.SizeId]
    return config and size and (config.MaxIncome or 0) * (size.BaseMultiplier or 1) or 0
end

function App:EggRarity(model)
    local label = path(model, "EggGui", "MainFrame", "Rarity")
    if label and label:IsA("TextLabel") then
        local plain = label.Text:gsub("<[^>]+>", "")
        for _, rarity in ipairs(Rarities) do
            if plain == rarity then
                return rarity
            end
        end
    end
    local id = model.Name:gsub("Egg$", "")
    local config = Configs.Mosquito[id]
    return config and config.Rarity
end

function App:WorldEggInfo(model)
    local item = EggByName[model.Name]
    local rarity = self:EggRarity(model)
    local sizeId
    if item and tonumber(item.Config.EggBaseScale) and item.Config.EggBaseScale > 0 then
        local ratio = model:GetScale() / item.Config.EggBaseScale
        for id, config in pairs(Configs.Size) do
            if math.abs(ratio - config.Scale) <= 0.001 * math.max(1, config.Scale) then
                if sizeId then
                    return {Rarity = rarity}
                end
                sizeId = id
            end
        end
    end
    return {ItemId = item and item.ItemId, Rarity = rarity, SizeId = sizeId}
end

function App:MatchesWorldEgg(info)
    if not info.Rarity or not self.Settings.EggRarities[info.Rarity] then
        return false
    end
    if info.SizeId then
        return self.Settings.EggSizes[info.SizeId] == true
    end
    for _, id in ipairs(Sizes) do
        if not self.Settings.EggSizes[id] then
            return false
        end
    end
    return true
end

function App:FindEgg()
    local areas = workspace:FindFirstChild("SpawnAreas")
    local _, _, root = self:Character()
    if not areas or not root then
        return
    end
    if os.clock() < (self.EggScanAt or 0) then
        return
    end
    self.EggScanAt = os.clock() + 1.5
    local best, distance
    for _, prompt in ipairs(areas:QueryDescendants("ProximityPrompt#CarryPrompt")) do
        local attachment = prompt.Parent
        local part = attachment and attachment.Parent
        local model = part and part.Parent
        if prompt.Enabled and model and model:IsA("Model") and os.clock() >= (self.EggCooldowns[prompt] or 0) then
            local info = self:WorldEggInfo(model)
            if self:MatchesWorldEgg(info) then
                local owner = model:FindFirstChild("Player")
                local actorId = model:FindFirstChild("ActorId")
                local localActor = actorId and path(Player, "PlayerScripts", "Runtime", "Actors", actorId.Value)
                owner = owner or (localActor and localActor:FindFirstChild("Player"))
                if not owner or owner.Value == nil then
                    local position = attachment:IsA("Attachment") and attachment.WorldPosition or part.Position
                    local length = (position - root.Position).Magnitude
                    if not distance or length < distance then
                        distance = length
                        best = {Prompt = prompt, Model = model, Position = position, Rarity = info.Rarity, SizeId = info.SizeId, Deadline = os.clock() + 10}
                    end
                end
            end
        end
    end
    return best
end

function App:CollectStep()
    if not self.Settings.AutoCollectEggs then
        self:CancelCollect()
        return false
    end
    local record = self.Collecting
    if not record then
        record = self:FindEgg()
        self.Collecting = record
    end
    if not record then
        return false
    end
    local prompt = record.Prompt
    if not prompt.Parent or not prompt.Enabled or not record.Model.Parent then
        self:CancelCollect()
        return false
    end
    if os.clock() > record.Deadline then
        self.EggCooldowns[prompt] = os.clock() + 5
        self:CancelCollect()
        return false
    end
    local _, _, root = self:Character()
    if not root then
        return true
    end
    self:StopFeeding()
    self.Status = "Collecting " .. record.Rarity .. " egg"
    local position = prompt.Parent:IsA("Attachment") and prompt.Parent.WorldPosition or record.Position
    local distance = math.max(1, math.min(prompt.MaxActivationDistance - 1, 5))
    if (root.Position - position).Magnitude > distance then
        self:Move(position + Vector3.new(0, 2, math.min(distance * 0.6, 2)), position)
        return true
    end
    if not record.Triggered then
        record.Triggered = true
        self:PatchPrompt(prompt)
        local duration = prompt.HoldDuration
        record.Deadline = os.clock() + duration + 4
        record.Thread = task.spawn(function()
            local ok = false
            if type(fireproximityprompt) == "function" then
                ok = pcall(fireproximityprompt, prompt, duration)
            end
            if not ok and self.Running and self.Collecting == record and prompt.Parent then
                pcall(prompt.InputHoldBegin, prompt)
                task.wait(duration + 0.1)
                if self.Running and self.Collecting == record and prompt.Parent then
                    pcall(prompt.InputHoldEnd, prompt)
                end
            end
            record.Thread = nil
        end)
    end
    return true
end

function App:BasePosition(uid)
    local base = self:Base()
    local part = base and base:FindFirstChild("BasePart")
    if not part then
        return
    end
    local hash = 0
    for index = 1, #tostring(uid) do
        hash = (hash * 31 + string.byte(tostring(uid), index)) % 100000
    end
    local width = math.max(1, part.Size.X / 2 - 3)
    local depth = math.max(1, part.Size.Z / 2 - 3)
    local occupied = {}
    for _, name in ipairs({"Eggs", "Mosquitoes"}) do
        local folder = base:FindFirstChild(name)
        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") then
                    table.insert(occupied, model:GetPivot().Position)
                end
            end
        end
    end
    local fallback
    for offset = 0, 35 do
        local index = (hash + offset) % 36
        local localPosition = Vector3.new(-width + width * 2 * (index % 6) / 5, part.Size.Y / 2, -depth + depth * 2 * math.floor(index / 6) / 5)
        local position = part.CFrame:PointToWorldSpace(localPosition)
        fallback = position
        local free = true
        for _, used in ipairs(occupied) do
            if (used - position).Magnitude < 5 then
                free = false
                break
            end
        end
        if free then
            return position
        end
    end
    return fallback
end

function App:OwnedEggStep()
    local now = os.clock()
    if now < (self.OwnedEggAt or 0) then
        return false
    end
    if self.Settings.AutoHatch then
        for uid, info in pairs(self.Data.HatchInfos or {}) do
            if type(info) == "table" and self:MatchesEgg(info) and tonumber(info.LeftTime) and info.LeftTime <= 0 then
                local actor = "Egg_" .. tostring(info.ItemUid or uid)
                if self:Fire(actor, "Hatch", 4) then
                    self.OwnedEggAt = now + 0.6
                    self.Status = "Hatching ready egg"
                    return true
                end
            end
        end
    end
    if self.Settings.AutoPlaceEggs then
        local best, bestUid
        for uid, info in pairs(self.Data.Eggs or {}) do
            if not info.InBase and self:MatchesEgg(info) and not (self.Data.HatchInfos or {})[uid] then
                if not best or self:Potential(info) > self:Potential(best) then
                    best, bestUid = info, info.ItemUid or uid
                end
            end
        end
        if best then
            local position = self:BasePosition(bestUid)
            if position and self:Fire(self:PlayerActor(), "PlaceEgg", 2, bestUid, position) then
                self.OwnedEggAt = now + 0.6
                self.Status = "Placing egg on base"
                return true
            end
        end
    end
    return false
end

function App:BestStep()
    if not self.Settings.AutoPlaceBest or not self.Ready then
        return
    end
    local parts = {tostring(self.Data.BaseLevel or 1)}
    local count = 0
    for uid, info in pairs(self.Data.Mosquitoes or {}) do
        count = count + 1
        table.insert(parts, tostring(uid) .. ":" .. tostring(info.InBase == true) .. ":" .. tostring(self:Potential(info)))
    end
    if count == 0 then
        return
    end
    table.sort(parts)
    local signature = table.concat(parts, "|")
    if signature ~= self.BestSignature and self:Fire(self:PlayerActor(), "PlaceBest", 3) then
        self.BestSignature = signature
    end
end

function App:FeedStep()
    if not self.Settings.AutoFeed then
        return false
    end
    local _, humanoid, root = self:Character()
    if not root then
        return false
    end
    local current = self:Feeding()
    local info = current and (self.Data.Mosquitoes or {})[current]
    local config = info and Configs.Mosquito[info.ItemId]
    if current and (not info or not info.InBase or (tonumber(info.FeedProgress) or 0) >= 1 or not config or not self.Settings.FeedRarities[config.Rarity]) then
        self:StopFeeding()
        current, info = nil, nil
    end
    if humanoid.Health / math.max(1, humanoid.MaxHealth) * 100 <= self.Settings.FeedHealth then
        self:StopFeeding()
        self.FeedRecovering = true
        return false
    end
    if self.FeedRecovering then
        if humanoid.Health < humanoid.MaxHealth * 0.9 then
            return false
        end
        self.FeedRecovering = nil
    end
    local base = self:Base()
    local folder = base and base:FindFirstChild("Mosquitoes")
    local candidates = {}
    for uid, entry in pairs(self.Data.Mosquitoes or {}) do
        local mosquito = Configs.Mosquito[entry.ItemId]
        local model = folder and folder:FindFirstChild(tostring(entry.ItemUid or uid))
        if entry.InBase and (tonumber(entry.FeedProgress) or 0) < 1 and mosquito and self.Settings.FeedRarities[mosquito.Rarity] and model then
            table.insert(candidates, {Uid = entry.ItemUid or uid, Info = entry, Model = model, Distance = (model:GetPivot().Position - root.Position).Magnitude})
        end
    end
    table.sort(candidates, function(a, b)
        if self.Settings.FeedPriority == "Nearest" then
            return a.Distance < b.Distance
        elseif self.Settings.FeedPriority == "Lowest Progress" then
            local left, right = tonumber(a.Info.FeedProgress) or 0, tonumber(b.Info.FeedProgress) or 0
            if left ~= right then
                return left < right
            end
        end
        local left, right = self:Potential(a.Info), self:Potential(b.Info)
        if left ~= right then
            return left > right
        end
        return tostring(a.Uid) < tostring(b.Uid)
    end)
    local target
    for _, entry in ipairs(candidates) do
        if entry.Uid == current then
            target = entry
            break
        end
    end
    target = target or candidates[1]
    if not target then
        return false
    end
    self.Status = "Feeding " .. (Configs.Mosquito[target.Info.ItemId].Name or target.Info.ItemId) .. " to maximum"
    local position = target.Model:GetPivot().Position
    if (root.Position - position).Magnitude > 8 then
        self:Move(position + Vector3.new(0, 2, 4), position)
        return true
    end
    if not current and self:Fire("Mosquito_" .. target.Uid, "FeedMosquito", 2) then
        self.FeedingUid = target.Uid
        self.StoppedFeedingUid = nil
        self.FeedStarted = os.clock()
    elseif self.FeedingUid and os.clock() - (self.FeedStarted or 0) > 4 then
        local value = path(Player.Character, "FeedingMosquitoUid")
        if value and value.Value == "" then
            self.FeedingUid = nil
        end
    end
    return true
end

function App:BloodStep()
    if not self.Settings.AutoBlood then
        return false
    end
    local base = self:Base()
    local _, humanoid, root = self:Character()
    if not base or not root then
        return false
    end
    local seat
    for _, candidate in ipairs(base:QueryDescendants("Seat")) do
        if not candidate.Disabled then
            seat = candidate
            break
        end
    end
    if not seat then
        return false
    end
    self.Status = "Blood transfusion"
    if humanoid.SeatPart ~= seat then
        if (root.Position - seat.Position).Magnitude > 4 then
            self:Move(seat.Position + Vector3.new(0, 2, 0))
            return true
        end
        if os.clock() >= (self.SeatAttemptAt or 0) then
            self.SeatAttemptAt = os.clock() + 2
            seat:Sit(humanoid)
        end
    end
    self.Transfusing = true
    return true
end

function App:FindBoss(root)
    local areas = workspace:FindFirstChild("SpawnAreas")
    if not areas then
        return
    end
    local candidates = {}
    for id, config in pairs(Configs.Area) do
        if self.Settings.BossZones[config.Rarity] then
            local area = areas:FindFirstChild(id)
            local model = area and area:FindFirstChild(config.MotherPrefab)
            local humanoid = model and model:FindFirstChildOfClass("Humanoid")
            local part = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
            if humanoid and humanoid.Health > 0 and part then
                table.insert(candidates, {Model = model, Humanoid = humanoid, Part = part, Config = config, Distance = (root.Position - part.Position).Magnitude})
            end
        end
    end
    table.sort(candidates, function(a, b)
        if self.Settings.BossPriority == "Nearest" then
            return a.Distance < b.Distance
        elseif self.Settings.BossPriority == "Strongest" then
            return (a.Config.Health or 0) > (b.Config.Health or 0)
        end
        return (a.Config.Health or 0) < (b.Config.Health or 0)
    end)
    return candidates[1]
end

function App:CombatStep()
    if not self.Settings.AutoKill then
        return false
    end
    local character, humanoid, root = self:Character()
    if not root then
        return false
    end
    local target = self:FindBoss(root)
    if not target then
        self.Status = "Waiting for a selected boss"
        return false
    end
    local selected
    for _, container in ipairs({character, Player:FindFirstChildOfClass("Backpack")}) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and Configs.Weapon[tool.Name] then
                if not selected or Configs.Weapon[tool.Name].Damage > Configs.Weapon[selected.Name].Damage then
                    selected = tool
                end
            end
        end
    end
    if not selected then
        self.Status = "Waiting for a weapon"
        return false
    end
    self:StopFeeding()
    self:LeaveSeat()
    if selected.Parent ~= character then
        humanoid:EquipTool(selected)
    end
    local part = target.Part
    if self.CombatTarget ~= target.Model then
        self.CombatTarget = target.Model
        local offset = root.Position - part.Position
        offset = Vector3.new(offset.X, 0, offset.Z)
        self.CombatOffset = offset.Magnitude > 0.1 and offset.Unit or Vector3.new(0, 0, 1)
    end
    local distance = math.clamp(tonumber(self.Settings.FarmDistance) or 4, 3, 30)
    local position = part.Position + self.CombatOffset * distance + Vector3.new(0, 1, 0)
    self:Move(position, part.Position)
    self.Status = "Fighting " .. target.Config.Rarity .. " boss"
    local config = Configs.Weapon[selected.Name]
    local now = os.clock()
    if (root.Position - part.Position).Magnitude <= distance + 2 and now >= (self.AttackAt or 0) then
        self.AttackAt = now + (tonumber(config.CD) or 0.7) + 0.05
        selected:Activate()
    end
    return true
end

function App:MotionStep()
    if not self.Ready then
        self.Status = "Waiting for player data"
        return
    end
    local _, humanoid = self:Character()
    if not humanoid then
        self:CancelCollect()
        self.FeedingUid = nil
        self.Transfusing = nil
        self.Status = "Waiting for respawn"
        return
    end
    local ratio = humanoid.Health / math.max(1, humanoid.MaxHealth) * 100
    local threshold = (self.Settings.AutoKill or self.Settings.AutoCollectEggs) and self.Settings.RetreatHealth or 0
    if self.Settings.AutoFeed then
        threshold = math.max(threshold, self.Settings.FeedHealth)
    end
    if ratio <= threshold and (self.Settings.AutoKill or self.Settings.AutoFeed or self.Settings.AutoCollectEggs) then
        self.Recovering = true
    end
    if self.Recovering then
        if ratio >= 90 then
            self.Recovering = nil
            self.FeedRecovering = nil
            self:LeaveSeat()
        else
            self:CancelCollect()
            self:StopFeeding()
            if not self:BloodStep() then
                self:ReturnBase()
                self.Status = "Recovering health at base"
            end
            return
        end
    end
    if self.Collecting and self:CollectStep() then
        return
    end
    if self:OwnedEggStep() then
        return
    end
    if self:MoneyStep() then
        return
    end
    if self:CollectStep() then
        return
    end
    if self:FeedStep() then
        return
    end
    if self:CombatStep() then
        return
    end
    if self:BloodStep() then
        return
    end
    self.Status = self.Settings.AutoKill and "Waiting for a selected boss" or "Idle"
end

function App:IncomeStep()
    if self.Spending then
        return
    end
    if self.Settings.AutoClaimOffline and (tonumber(self.Data.OfflineIncome) or 0) > 0 then
        self:Fire(self:PlayerActor(), "ClaimOfflineIncome", 3)
    end
end

function App:MoneyStep()
    if not self.Settings.AutoCollectMoney or self.Spending or os.clock() < (self.MoneyNext or 0) or (tonumber(self.Data.TotalIncome) or 0) <= 0 then
        return false
    end
    local base = self:Base()
    local button = base and base:FindFirstChild("CollectButton")
    local part = button and (button.PrimaryPart or button:FindFirstChild("BasePart"))
    local _, _, root = self:Character()
    if not part or not root then
        return false
    end
    self.Status = "Collecting base income"
    self:StopFeeding()
    if (root.Position - part.Position).Magnitude > 7 then
        self:Move(part.Position + Vector3.new(0, 3, 0))
        return true
    end
    if self:Fire(self:PlayerActor(), "CollectIncome", 2) then
        self.MoneyNext = os.clock() + 15
    end
    return true
end

function App:BeginSpend(cost)
    if self.Spending or self.Pending.BuyWeapon or cost > self:Gold() - self.Settings.GoldReserve then
        return false
    end
    self.Spending = {Cost = cost, Before = self:Gold(), Revision = self.CoinRevision or 0, Time = os.clock()}
    return true
end

function App:CheckSpending()
    local spending = self.Spending
    if not spending or self.Pending.BuyWeapon then
        return
    end
    if (self.CoinRevision or 0) > spending.Revision and self:Gold() <= spending.Before - spending.Cost + 0.001 then
        self.Spending = nil
    elseif os.clock() - spending.Time > 8 and not spending.Resync then
        local binding = self.Bindings.Player
        if binding and binding.Remote.Parent then
            spending.Resync = true
            binding.Remote:FireServer("require_all")
        end
    end
end

function App:UpgradeStep()
    if not self.Settings.AutoUpgrade or self.Spending or self.Pending.BuyWeapon or os.clock() < (self.UpgradeNext or 0) or os.clock() < (self.SpendAt or 0) then
        return
    end
    local choices = {}
    local definitions = {
        {Name = "Base", Key = "BaseLevel", Config = Configs.Base, Remote = "UpgradeBase"},
        {Name = "Blood Transfusion", Key = "BloodTransfusionLevel", Config = Configs.BloodTransfusion, Remote = "UpgradeBloodTransfusion"},
        {Name = "Damage", Key = "DamageLevel", Config = Configs.DamageUpgrade, Remote = "UpgradeDamage"},
        {Name = "Speed", Key = "SpeedLevel", Config = Configs.SpeedUpgrade, Remote = "UpgradeSpeed"},
    }
    local budget = math.max(0, self:Gold() - self.Settings.GoldReserve)
    for _, definition in ipairs(definitions) do
        if self.Settings.UpgradeTypes[definition.Name] then
            local level = math.max(1, math.floor(tonumber(self.Data[definition.Key]) or 1))
            local config = definition.Config[level]
            local price = config and tonumber(config.UpgradePrice or config.Price)
            if config and level < #definition.Config and price and price > 0 and price <= budget then
                table.insert(choices, {Definition = definition, Price = price})
            end
        end
    end
    table.sort(choices, function(a, b)
        return a.Price < b.Price
    end)
    local choice = choices[1]
    if choice and self:BeginSpend(choice.Price) then
        if self:Fire(self:PlayerActor(), choice.Definition.Remote, 2.5) then
            self.UpgradeNext = os.clock() + 2.5
            self.SpendAt = os.clock() + 1.8
        else
            self.Spending = nil
        end
    end
end

function App:WeaponStep()
    if os.clock() < (self.WeaponNext or 0) then
        return
    end
    self.WeaponNext = os.clock() + 2
    local owned = self.Data.Weapons or {}
    local best, currentDamage = nil, 0
    for id, entry in pairs(owned) do
        local config = Configs.Weapon[entry.ItemId or id]
        if config then
            if entry.InBackpack then
                currentDamage = math.max(currentDamage, config.Damage or 0)
            end
            if self.Settings.WeaponFilter[config.Name or config.Id] and (not best or config.Damage > best.Damage) then
                best = config
            end
        end
    end
    if self.Settings.AutoEquipBest and best and not (owned[best.Id] and owned[best.Id].InBackpack) then
        self:Invoke("UseWeapon", nil, best.Id)
    end
    if not self.Settings.AutoBuyWeapon or self.Spending or self.Pending.BuyWeapon or os.clock() < (self.SpendAt or 0) then
        return
    end
    local budget = math.max(0, self:Gold() - self.Settings.GoldReserve)
    local candidate
    for _, config in ipairs(WeaponList) do
        if self.Settings.WeaponFilter[config.Name or config.Id] and not owned[config.Id] and config.Damage > math.max(currentDamage, best and best.Damage or 0) and config.CoinCount <= budget then
            candidate = config
        end
    end
    if candidate and self:BeginSpend(candidate.CoinCount) then
        if self:Invoke("BuyWeapon", function()
            self.WeaponNext = os.clock() + 0.5
        end, candidate.Id) then
            self.SpendAt = os.clock() + 2
        else
            self.Spending = nil
        end
    end
end

function App:EconomyStep()
    if not self.Ready then
        return
    end
    self:CheckSpending()
    self:IncomeStep()
    self:BestStep()
    self:WeaponStep()
    self:UpgradeStep()
end

function App:Loop(name, interval, callback)
    local thread = task.spawn(function()
        while self.Running do
            local ok, failure = xpcall(callback, debug.traceback)
            if not ok then
                self:Warn(name, failure)
            end
            task.wait(interval)
        end
    end)
    table.insert(self.Workers, thread)
end

local function buildInterface(App)
    local UserInputService = game:GetService("UserInputService")
    local LibraryUrl = "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/2910b3532195935a00dacb479a0ded50f1f38a0a/Source.luau"
    local loaded, Airflow = pcall(function()
        return loadstring(game:HttpGet(LibraryUrl))()
    end)
    if not App.Running then
        return
    end
    if not loaded or type(Airflow) ~= "table" then
        error("Airflow failed to load: " .. tostring(Airflow))
    end

    Airflow.Theme.Background = Color3.fromRGB(15, 19, 19)
    Airflow.Theme.Surface = Color3.fromRGB(20, 26, 25)
    Airflow.Theme.Surface2 = Color3.fromRGB(26, 33, 31)
    Airflow.Theme.Surface3 = Color3.fromRGB(39, 49, 45)
    Airflow.Theme.Stroke = Color3.fromRGB(37, 48, 44)
    Airflow.Theme.StrokeHover = Color3.fromRGB(78, 133, 105)
    Airflow.Theme.Accent = Color3.fromRGB(163, 225, 163)
    Airflow.Theme.AccentDark = Color3.fromRGB(12, 29, 18)
    Airflow.Theme.Text = Color3.fromRGB(233, 240, 232)
    Airflow.Theme.Muted = Color3.fromRGB(140, 159, 145)

    local window = Airflow:CreateWindow({
        Name = "Feed A Mosquito",
        Icon = "bug",
        Size = UDim2.fromOffset(580, 430),
        MinSize = Vector2.new(280, 220),
        ToggleUIKeybind = Enum.KeyCode.RightControl,
        OpenButton = {Title = "Mosquito", Icon = "bug"},
        KeepOnScreen = true,
        MaxNotifications = 4,
        Loading = false,
        ConfigurationSaving = {Enabled = false},
    })
    App.Window = window
    if window.Shadow then
        window.Shadow.Visible = false
    end
    for _, image in ipairs(window.Body:QueryDescendants("ImageLabel, ImageButton")) do
        if image.Image == Airflow.Assets.Glow or image.Image == Airflow.Assets.Shadow then
            image.Visible = false
        end
    end
    App.Controls = App.Controls or {}
    if window._titleLabel then
        window._titleLabel.Position = UDim2.fromOffset(60, 31)
    end

    local disposed = false
    local constructing = true
    local function update(key, value)
        if not constructing and not disposed then
            App:Set(key, value)
        end
    end
    local function toggle(tab, key, name, desc)
        local control = tab:CreateToggle({
            Name = name,
            Desc = desc,
            CurrentValue = App.Settings[key] == true,
            Callback = function(value)
                update(key, value == true)
            end,
        })
        App.Controls[key] = control
        return control
    end
    local function slider(tab, key, name, minimum, maximum, increment, suffix)
        local control = tab:CreateSlider({
            Name = name,
            Range = {minimum, maximum},
            Increment = increment,
            Suffix = suffix,
            CurrentValue = App.Settings[key],
            Callback = function(value)
                update(key, tonumber(value) or minimum)
            end,
        })
        App.Controls[key] = control
        return control
    end
    local function dropdown(tab, key, name, options)
        local control = tab:CreateDropdown({
            Name = name,
            Options = options,
            CurrentOption = App.Settings[key],
            MultipleOptions = false,
            Callback = function(selection)
                local value = type(selection) == "table" and selection[1] or selection
                if type(value) == "string" then
                    update(key, value)
                end
            end,
        })
        App.Controls[key] = control
        return control
    end
    local function multi(tab, key, name, options)
        local selected = {}
        local current = App.Settings[key] or {}
        for _, option in ipairs(options) do
            if current[option] then
                table.insert(selected, option)
            end
        end
        local control = tab:CreateDropdown({
            Name = name,
            Options = options,
            CurrentOption = selected,
            MultipleOptions = true,
            Callback = function(selection)
                local values = {}
                local list = type(selection) == "table" and selection or {selection}
                for _, option in ipairs(options) do
                    values[option] = table.find(list, option) ~= nil
                end
                update(key, values)
            end,
        })
        App.Controls[key] = control
        return control
    end

    local Farm = window:CreateTab({Name = "Farm", Icon = "swords"})
    local Eggs = window:CreateTab({Name = "Eggs", Icon = "egg"})
    local Mosquitoes = window:CreateTab({Name = "Mosquitoes", Icon = "bug"})
    local Upgrades = window:CreateTab({Name = "Upgrades", Icon = "trending-up"})
    local Settings = window:CreateTab({Name = "Settings", Icon = "settings"})

    Farm:CreateSection("Bosses")
    toggle(Farm, "AutoKill", "Auto Kill Bosses")
    multi(Farm, "BossZones", "Boss Zones", App.Config.Zones)
    dropdown(Farm, "BossPriority", "Boss Priority", {"Weakest", "Strongest", "Nearest"})
    slider(Farm, "FarmDistance", "Attack Distance", 3, 30, 1, " studs")
    slider(Farm, "RetreatHealth", "Retreat Below Health", 0, 90, 1, "%")
    Farm:CreateSection("Movement")
    dropdown(Farm, "MovementMode", "Movement Mode", {"Smooth", "Teleport"})
    slider(Farm, "TravelSpeed", "Travel Speed", 30, 250, 1, " studs/s")
    Farm:CreateSection("Income")
    toggle(Farm, "AutoCollectMoney", "Auto Collect Base Income")
    toggle(Farm, "AutoClaimOffline", "Auto Claim Offline Income")
    Farm:CreateLabel({
        Text = "Ready",
        UpdateRate = 0.5,
        Update = function()
            return (disposed or App.Running == false or window._destroyed) and "Stopped" or App:GetStatus()
        end,
    })

    Eggs:CreateSection("Automation")
    toggle(Eggs, "AutoCollectEggs", "Auto Collect Eggs")
    toggle(Eggs, "AutoPlaceEggs", "Auto Place Eggs")
    toggle(Eggs, "AutoHatch", "Auto Hatch Ready Eggs")
    Eggs:CreateSection("Filters")
    multi(Eggs, "EggRarities", "Egg Rarities", App.Config.Rarities)
    multi(Eggs, "EggSizes", "Egg Sizes", App.Config.Sizes)

    Mosquitoes:CreateSection("Base")
    toggle(Mosquitoes, "AutoPlaceBest", "Auto Place Best Mosquitoes")
    toggle(Mosquitoes, "AutoFeed", "Auto Feed Mosquitoes")
    dropdown(Mosquitoes, "FeedPriority", "Feed Priority", {"Highest Income", "Lowest Progress", "Nearest"})
    multi(Mosquitoes, "FeedRarities", "Feed Rarities", App.Config.Rarities)
    slider(Mosquitoes, "FeedHealth", "Minimum Health To Feed", 0, 90, 1, "%")
    Mosquitoes:CreateSection("Health")
    toggle(Mosquitoes, "AutoBlood", "Auto Blood Transfusion")

    Upgrades:CreateSection("Gold Upgrades")
    toggle(Upgrades, "AutoUpgrade", "Auto Upgrade")
    multi(Upgrades, "UpgradeTypes", "Upgrade Types", {"Base", "Blood Transfusion", "Damage", "Speed"})
    Upgrades:CreateParagraph({
        Title = "Gold Only",
        Content = "Automatic upgrades and weapon purchases use gold. Robux purchases are never automated.",
    })
    App.Controls.GoldReserve = Upgrades:CreateInput({
        Name = "Gold Reserve",
        PlaceholderText = "Gold to keep",
        CurrentValue = tostring(App.Settings.GoldReserve or 0),
        Numeric = true,
        MaxLength = 20,
        Callback = function(value)
            local number = tonumber(value)
            if number and number == number and number < math.huge then
                update("GoldReserve", math.max(0, math.floor(number)))
            end
        end,
    })
    Upgrades:CreateSection("Weapons")
    toggle(Upgrades, "AutoBuyWeapon", "Auto Buy Stronger Weapons")
    toggle(Upgrades, "AutoEquipBest", "Auto Equip Best Weapon")
    multi(Upgrades, "WeaponFilter", "Allowed Weapons", App.Config.Weapons)

    Settings:CreateSection("Session")
    toggle(Settings, "AntiAFK", "Anti AFK")
    toggle(Settings, "InstantPrompts", "Instant Prompts")
    Settings:CreateButton({
        Name = "Stop All",
        Icon = "square",
        Callback = function()
            App:StopAll()
            App:Notify("Stopped", "Every feature is off. Anti AFK stays as it is.", "Success")
        end,
    })
    App.Controls.MenuKeybind = Settings:CreateKeybind({
        Name = "Menu Keybind",
        CurrentKeybind = Enum.KeyCode.RightControl,
        OnChanged = function(key)
            if not disposed and typeof(key) == "EnumItem" then
                window:SetKeybind(key)
            end
        end,
    })
    Settings:CreateButton({
        Name = "Unload",
        Icon = "power",
        Callback = function()
            App:Unload()
        end,
    })
    Settings:CreateSection("Credits")
    local creditText
    local function copy(text)
        local clipboard = setclipboard or toclipboard
        if type(clipboard) == "function" then
            local ok = pcall(clipboard, text)
            App:Notify("Clipboard", ok and "Copied to clipboard." or "Could not copy the text.", ok and "Success" or "Warning")
        else
            App:Notify("Clipboard", text, "Info")
        end
    end
    local creditButton = Settings:CreateButton({
        Name = "Credits - loading...",
        Icon = "copy",
        Callback = function()
            if creditText then
                copy(creditText)
            else
                App:Notify("Credits", "The credits text is not available yet.", "Info")
            end
        end,
    })
    Settings:CreateButton({
        Name = "UI Library - airflowlib.lol",
        Icon = "copy",
        Callback = function()
            copy("https://airflowlib.lol")
        end,
    })
    task.spawn(function()
        local ok, text = pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
        end)
        if disposed or App.Running == false or window._destroyed then
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

    local originalToggle = window.Toggle
    function window:Toggle(value)
        if value == nil and UserInputService:GetFocusedTextBox() and UserInputService:GetLastInputType() == Enum.UserInputType.Keyboard then
            return
        end
        if self.OpenButton then
            self.OpenButton.Visible = true
        end
        return originalToggle(self, value)
    end

    local sidebar = window.Body:FindFirstChild("Sidebar")
    local tabLayout = window.TabList:FindFirstChildOfClass("UIListLayout")
    local tabPadding = window.TabList:FindFirstChildOfClass("UIPadding")
    local remembered = {}
    local compact = false
    local function remember(object, properties)
        if not object then
            return
        end
        local values = remembered[object] or {}
        for _, property in ipairs(properties) do
            values[property] = object[property]
        end
        remembered[object] = values
    end
    remember(sidebar, {"Size"})
    remember(window.Content, {"Position", "Size"})
    remember(window.TabList, {"Position", "Size", "AutomaticCanvasSize", "ScrollingDirection", "CanvasSize"})
    remember(tabLayout, {"FillDirection"})
    remember(tabPadding, {"PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom"})
    if sidebar then
        for _, child in ipairs(sidebar:GetChildren()) do
            if child ~= window.TabList and child ~= window.Indicator and child:IsA("GuiObject") then
                remember(child, {"Visible"})
            end
        end
    end
    for _, child in ipairs(window.Body:GetChildren()) do
        if child:IsA("Frame") and child.Size.X.Offset == 1 and child.Position.X.Offset == 170 then
            remember(child, {"Visible"})
        end
    end
    for _, tab in ipairs(window.Tabs) do
        remember(tab._button, {"Size"})
        remember(tab._label, {"Position", "Size", "TextXAlignment"})
        remember(tab._icon, {"Visible"})
    end
    local originalIndicator = window._placeIndicator
    function window:_placeIndicator(tab)
        if compact then
            self.Indicator.Visible = false
            return
        end
        return originalIndicator(self, tab)
    end
    local function layout(viewportOverride)
        if disposed or App.Running == false or window._destroyed or not window.Gui.Parent then
            return
        end
        local viewport = typeof(viewportOverride) == "Vector2" and viewportOverride or window.Gui.AbsoluteSize
        if viewport.X < 1 or viewport.Y < 1 then
            return
        end
        for object, properties in pairs(remembered) do
            if object.Parent then
                for property, value in pairs(properties) do
                    object[property] = value
                end
            end
        end
        local width = math.clamp(viewport.X - 24, 280, 580)
        local height = math.clamp(viewport.Y - 24, 220, 430)
        window.Root.Size = UDim2.fromOffset(width, height)
        compact = width < 560
        if compact and sidebar and tabLayout then
            sidebar.Size = UDim2.new(1, 0, 0, 52)
            for object, properties in pairs(remembered) do
                if properties.Visible ~= nil and not object:IsDescendantOf(window.TabList) then
                    object.Visible = false
                end
            end
            window.TabList.Position = UDim2.fromOffset(8, 5)
            window.TabList.Size = UDim2.new(1, -16, 0, 42)
            window.TabList.ScrollingDirection = Enum.ScrollingDirection.X
            window.TabList.AutomaticCanvasSize = Enum.AutomaticSize.X
            window.TabList.CanvasSize = UDim2.new()
            tabLayout.FillDirection = Enum.FillDirection.Horizontal
            if tabPadding then
                tabPadding.PaddingLeft = UDim.new()
                tabPadding.PaddingRight = UDim.new()
                tabPadding.PaddingTop = UDim.new()
                tabPadding.PaddingBottom = UDim.new()
            end
            window.Content.Position = UDim2.fromOffset(0, 52)
            window.Content.Size = UDim2.new(1, 0, 1, -52)
            for _, tab in ipairs(window.Tabs) do
                tab._button.Size = UDim2.fromOffset(math.max(72, #tab.Name * 8 + 26), 40)
                tab._label.Position = UDim2.new()
                tab._label.Size = UDim2.fromScale(1, 1)
                tab._label.TextXAlignment = Enum.TextXAlignment.Center
                if tab._icon then
                    tab._icon.Visible = false
                end
            end
            window.Indicator.Visible = false
        end
        window:_fitToScreen(true)
        window:_clampToScreen()
        if window.CurrentTab and not compact then
            window:_placeIndicator(window.CurrentTab)
        end
        local button = window.OpenButton
        if button then
            button.Visible = true
            local position = button.AbsolutePosition - window.Gui.AbsolutePosition
            local size = button.AbsoluteSize
            local x = math.clamp(position.X, 0, math.max(viewport.X - size.X, 0))
            local y = math.clamp(position.Y, 0, math.max(viewport.Y - size.Y, 0))
            if math.abs(x - position.X) > 0.5 or math.abs(y - position.Y) > 0.5 then
                button.AnchorPoint = Vector2.zero
                button.Position = UDim2.fromOffset(x, y)
            end
        end
    end
    App.Layout = function(self, viewport)
        layout(viewport)
    end
    App:Connect(window.Gui:GetPropertyChangedSignal("AbsoluteSize"), function()
        layout()
    end)
    App:Connect(window.Gui.Destroying, function()
        disposed = true
        App:Unload()
    end)
    for _, image in ipairs(window.Gui:QueryDescendants("ImageLabel, ImageButton")) do
        if image.Image == Airflow.Assets.Glow or image.Image == Airflow.Assets.Shadow or image.Image == "rbxassetid://120997033468887" then
            image.Visible = false
        end
    end
    constructing = false
    task.defer(layout)
    window:Toggle(false)
    if not window._introDone then
        task.defer(function()
            if App.Running and not window._destroyed then
                window:Toggle(false)
            end
        end)
    end
    return window
end

local initialized, failure = xpcall(function()
    buildInterface(App)
    if not App.Running then
        return
    end
    App:Connect(workspace.DescendantAdded, function(instance)
        if App.Settings.InstantPrompts and instance:IsA("ProximityPrompt") then
            App:PatchPrompt(instance)
        end
    end)
    App:Connect(ProximityPromptService.PromptShown, function(prompt)
        App:PatchPrompt(prompt)
    end)
    App:Connect(Player.Idled, function()
        if App.Settings.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
        end
    end)
    App:Connect(RunService.Heartbeat, function(delta)
        if App.MoveGoal then
            local ok, problem = pcall(App.MovementFrame, App, delta)
            if not ok then
                App:Warn("Movement frame", problem)
                App.MoveGoal = nil
            end
        end
    end)
    App:RefreshData()
    App:Loop("Player data", 1, function()
        App:RefreshData()
    end)
    App:Loop("Movement", 0.15, function()
        App.MoveRequested = false
        App:MotionStep()
        if not App.MoveRequested then
            App.MoveGoal = nil
        end
    end)
    App:Loop("Economy", 0.75, function()
        App:EconomyStep()
    end)
    App:Notify("Feed A Mosquito", "Loaded. Use the floating button to show or hide the menu.", "Success")
end, debug.traceback)

if not initialized then
    App:Unload()
    warn("[Feed A Mosquito] " .. tostring(failure))
end

return App

local Environment = getgenv()
local Previous = Environment.MagicLootHub

if Previous and Previous.Unload then
    pcall(Previous.Unload)
elseif Previous then
    Previous.Running = false
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local UtilsSystem = require(ReplicatedFirst:WaitForChild("AllSideCode"):WaitForChild("UtilsSystem"))
local NetWork = UtilsSystem.NetWork
local NetMsg = UtilsSystem.NetMsg
local PlayerData = UtilsSystem.PlayerData
local GetData = UtilsSystem.GetData
local CfgFind = UtilsSystem.CfgFind
local EnumMgr = UtilsSystem.EnumMgr
local EquipShop = UtilsSystem.EquipShop
local EnemyVisibilityUtil = UtilsSystem.EnemyVisibilityUtil
local SkillManager = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Manager"):WaitForChild("PlayerSkillClientManager")
local PlayerSkillInput = require(SkillManager:WaitForChild("PlayerSkillInput"))
local SkillSlotConfig = require(SkillManager:WaitForChild("SkillSlotConfig"))

local Hub = {
    Running = true,
    Unloading = false,
    Connections = {},
    CollisionDefaults = setmetatable({}, {__mode = "k"}),
    FarmTarget = nil,
    ForcedTarget = nil,
    CollectingLoot = false,
    Retreating = false,
    NoclipActive = false,
    LastJumpRequest = 0,
    JumpAttemptAt = 0,
    LastStageRequest = 0,
    LastReturnRequest = 0,
    LastLootAt = 0,
    LastSellAt = 0,
    LastUpgradeAt = 0,
    LastRebirthAt = 0,
    LastClickAt = 0,
    LastPotionAt = 0,
    LastOnlineRewardAt = 0,
    PotionBusy = false,
    OnlineRewardBusy = false,
    PotionAttempts = {},
    OnlineAnchorRaw = nil,
    OnlineAnchorSeconds = 0,
    OnlineAnchorAt = 0,
    LastBackpackCheck = 0,
    BackpackFull = false,
    BackpackCurrent = 0,
    BackpackMaximum = 0,
    StageEmptyAt = 0,
    EmptyStage = 0,
    NextRunAt = 0,
    StopAfterTown = false,
    UpgradeCursor = 1,
    Fluent = Fluent
}

Environment.MagicLootHub = Hub

local State = {
    AutoClick = false,
    AutoSell = false,
    AutoUpgrade = false,
    UpgradeWeapon = true,
    UpgradeArmor = true,
    UpgradeBroom = true,
    AutoRebirth = false,
    AutoUsePotions = false,
    AutoCollectOnlineRewards = false,
    AntiAFK = true,
    AutoFarm = false,
    ReturnIfBackpackFull = false,
    MaxDungeon = 1,
    FarmHeight = 14,
    AutoLoot = true,
    LootMinRarity = 1,
    LootMinValue = 0,
    RepeatRuns = true,
    EmergencyRetreat = true,
    RetreatHealth = 25,
    ResumeHealth = 70
}

Hub.State = State

local ShopSpecs = {
    {
        Name = "Weapon",
        ConfName = "weaponConf",
        SaveKey = "Weapon",
        ItemType = EnumMgr.ItemType.Weapon
    },
    {
        Name = "Armor",
        ConfName = "armorConf",
        SaveKey = "Armor",
        ItemType = EnumMgr.ItemType.Armor
    },
    {
        Name = "Broom",
        ConfName = "broomConf",
        SaveKey = "NowBroom",
        ItemType = EnumMgr.ItemType.Broom
    }
}

local function addConnection(Connection)
    table.insert(Hub.Connections, Connection)
    return Connection
end

local function getCharacter()
    local Character = LocalPlayer.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    local Root = Character and (Character:FindFirstChild("HumanoidRootPart") or Character.PrimaryPart)
    return Character, Humanoid, Root
end

local function getNumber(Name)
    local Value = LocalPlayer:FindFirstChild(Name)
    if Value and Value:IsA("NumberValue") then
        return math.floor(tonumber(Value.Value) or 0)
    end
    return 0
end

local function moveRoot(CFrameValue)
    local _, Humanoid, Root = getCharacter()
    if not Root or not Root:IsA("BasePart") or not Humanoid or Humanoid.Health <= 0 then
        return false
    end
    Root.CFrame = CFrameValue
    Root.AssemblyLinearVelocity = Vector3.zero
    Root.AssemblyAngularVelocity = Vector3.zero
    return true
end

local function setNoclip(Enabled)
    local Character = LocalPlayer.Character
    if Enabled then
        if not Character then
            return
        end
        for _, Object in Character:GetDescendants() do
            if Object:IsA("BasePart") then
                if not Hub.CollisionDefaults[Object] then
                    Hub.CollisionDefaults[Object] = {CanCollide = Object.CanCollide}
                end
                Object.CanCollide = false
            end
        end
        Hub.NoclipActive = true
        return
    end
    for Part, Defaults in Hub.CollisionDefaults do
        if Part and Part.Parent then
            Part.CanCollide = Defaults.CanCollide
        end
        Hub.CollisionDefaults[Part] = nil
    end
    Hub.NoclipActive = false
end

local function hasStageMarkers(Container)
    if not Container or not Container.Parent then
        return false
    end
    for _, Child in Container:GetChildren() do
        if Child:IsA("Model") and tonumber(Child.Name) then
            for _, Object in Child:GetDescendants() do
                if Object:IsA("BasePart") and (Object:GetAttribute("BattleArea") == true or Object:GetAttribute("SafeArea") == true) then
                    return true
                end
            end
        end
    end
    return false
end

local function findScene()
    if Hub.Scene and Hub.Scene.Parent and hasStageMarkers(Hub.Scene) then
        return Hub.Scene
    end
    Hub.Scene = nil
    local Best
    local BestCount = 0
    for _, Container in workspace:GetChildren() do
        if (Container:IsA("Folder") or Container:IsA("Model")) and hasStageMarkers(Container) then
            local Count = 0
            for _, Child in Container:GetChildren() do
                if Child:IsA("Model") and tonumber(Child.Name) then
                    Count += 1
                end
            end
            if Count > BestCount then
                Best = Container
                BestCount = Count
            end
        end
    end
    Hub.Scene = Best
    return Best
end

local function getStageNumbers()
    local Result = {}
    local Scene = findScene()
    if Scene then
        for _, Child in Scene:GetChildren() do
            local Number = Child:IsA("Model") and tonumber(Child.Name) or nil
            if Number and Number > 0 then
                table.insert(Result, math.floor(Number))
            end
        end
    end
    table.sort(Result)
    local Unique = {}
    local Last
    for _, Number in Result do
        if Number ~= Last then
            table.insert(Unique, Number)
            Last = Number
        end
    end
    if #Unique == 0 then
        for Number = 1, 27 do
            table.insert(Unique, Number)
        end
    end
    return Unique
end

local function getStageModel(Stage)
    local Scene = findScene()
    return Scene and Scene:FindFirstChild(tostring(Stage)) or nil
end

local function findStagePart(Stage, Attribute)
    local Model = getStageModel(Stage)
    if not Model then
        return nil
    end
    for _, Object in Model:GetDescendants() do
        if Object:IsA("BasePart") and Object:GetAttribute(Attribute) == true then
            return Object
        end
    end
    if Attribute == "BattleArea" then
        local Root = Model:FindFirstChild("Root", true)
        if Root and Root:IsA("BasePart") then
            return Root
        end
    end
    return nil
end

local StageNumbers = getStageNumbers()
local DungeonValues = {}

for _, Stage in StageNumbers do
    table.insert(DungeonValues, "Dungeon " .. tostring(Stage))
end

State.MaxDungeon = StageNumbers[#StageNumbers] or 1

local function getCareerMaxStage()
    local Direct = LocalPlayer:FindFirstChild("CareerMaxStage")
    if Direct and Direct:IsA("NumberValue") then
        return math.max(0, math.floor(tonumber(Direct.Value) or 0))
    end
    return math.max(0, math.floor(tonumber(PlayerData.GetPlrDataByKey(LocalPlayer, "CareerMaxStage")) or 0))
end

local function getBroomJumpMax()
    local BroomId = tonumber(PlayerData.GetPlrDataByKey(LocalPlayer, "NowBroom")) or 0
    if BroomId <= 0 then
        local Direct = LocalPlayer:FindFirstChild("NowBroom")
        if Direct and Direct:IsA("NumberValue") then
            BroomId = math.floor(tonumber(Direct.Value) or 0)
        end
    end
    if BroomId <= 0 then
        return 0
    end
    local Config = CfgFind.FindCfgByID(BroomId, EnumMgr.ItemType.Broom)
    return Config and math.max(0, math.floor(tonumber(Config.Dungeon) or 0)) or 0
end

local function getJumpStage(Maximum)
    local Allowed = math.min(Maximum, getCareerMaxStage() + 1)
    local BroomMax = getBroomJumpMax()
    if BroomMax > 0 then
        Allowed = math.min(Allowed, BroomMax)
    end
    Allowed = math.max(1, Allowed)
    local Best = 1
    local Configs = CfgFind.GetCfgByName("dungeonConf")
    if type(Configs) == "table" then
        for Id, Config in pairs(Configs) do
            local Stage = tonumber(Id)
            if Stage and Stage <= Allowed and type(Config) == "table" then
                local TeleIcon = Config.TeleIcon
                if type(TeleIcon) == "string" and TeleIcon ~= "" and Stage > Best then
                    Best = math.floor(Stage)
                end
            end
        end
    end
    return Best
end

local function canInteractEnemy(Model)
    if EnemyVisibilityUtil and EnemyVisibilityUtil.canPlayerInteract then
        local Success, Result = pcall(EnemyVisibilityUtil.canPlayerInteract, Model, LocalPlayer.UserId)
        if Success then
            return Result == true
        end
    end
    local Allowed = Model:GetAttribute("AllowedPlayerIds")
    if type(Allowed) == "string" and Allowed ~= "" then
        return string.find(Allowed, tostring(LocalPlayer.UserId), 1, true) ~= nil
    end
    return true
end

local function resolveEnemy(Root, Stage)
    local Folder = workspace:FindFirstChild("LocalMonster")
    if not Folder or not Root or not Root:IsA("BasePart") then
        return nil
    end
    local Model = Root:FindFirstAncestorOfClass("Model")
    if not Model or not Model:IsDescendantOf(Folder) then
        return nil
    end
    if Model:GetAttribute("IsLogicalEnemy") ~= true or not tonumber(Model.Name) then
        return nil
    end
    local Humanoid = Model:FindFirstChildOfClass("Humanoid")
    if not Humanoid or Humanoid.Health <= 0 then
        return nil
    end
    if Model:GetAttribute("CombatReady") == false or not canInteractEnemy(Model) then
        return nil
    end
    local EnemyStage = tonumber(Model:GetAttribute("Stage")) or tonumber(Model:GetAttribute("SpecialEnemyStageId"))
    if Stage and Stage > 0 and EnemyStage and math.floor(EnemyStage) ~= math.floor(Stage) then
        return nil
    end
    return Model, Root, Humanoid
end

local function getEnemies(Stage)
    local Result = {}
    local Seen = {}
    for _, Tagged in CollectionService:GetTagged("Enemy") do
        local Model, Root, Humanoid = resolveEnemy(Tagged, Stage)
        if Model and not Seen[Model] then
            Seen[Model] = true
            table.insert(Result, {Model = Model, Root = Root, Humanoid = Humanoid})
        end
    end
    local Folder = workspace:FindFirstChild("LocalMonster")
    if Folder then
        for _, Model in Folder:GetChildren() do
            if Model:IsA("Model") and not Seen[Model] then
                local Root = Model.PrimaryPart or Model:FindFirstChild("HumanoidRootPart") or Model:FindFirstChildWhichIsA("BasePart")
                local ValidModel, ValidRoot, Humanoid = resolveEnemy(Root, Stage)
                if ValidModel then
                    Seen[ValidModel] = true
                    table.insert(Result, {Model = ValidModel, Root = ValidRoot, Humanoid = Humanoid})
                end
            end
        end
    end
    return Result
end

local function findNearestEnemy(Stage, Range)
    local _, _, CharacterRoot = getCharacter()
    if not CharacterRoot then
        return nil
    end
    local Best
    local BestDistance = Range or math.huge
    for _, Enemy in getEnemies(Stage) do
        local Distance = (Enemy.Root.Position - CharacterRoot.Position).Magnitude
        if Distance <= BestDistance then
            Best = Enemy
            BestDistance = Distance
        end
    end
    return Best
end

local function getTargetValue()
    local Current = ReplicatedStorage:FindFirstChild("NowTargetCurrent")
    if Current and Current:IsA("ObjectValue") then
        return Current
    end
    return nil
end

local function clearForcedTarget()
    local TargetValue = getTargetValue()
    if TargetValue and TargetValue.Value == Hub.ForcedTarget then
        TargetValue.Value = nil
    end
    Hub.ForcedTarget = nil
end

local function castAt(Root)
    if not Root or not Root.Parent then
        return false
    end
    local TargetValue = getTargetValue()
    if TargetValue then
        TargetValue.Value = Root
        Hub.ForcedTarget = Root
    end
    for Slot = 1, SkillSlotConfig.MAX_SKILL_COUNT do
        local Success, Result = pcall(PlayerSkillInput.simulateSlotPressRelease, Slot, false)
        if Success and Result then
            return true
        end
    end
    local DerivedSuccess, DerivedResult = pcall(PlayerSkillInput.tryAutoCastNormalAttackDerive)
    if DerivedSuccess and DerivedResult then
        return true
    end
    local Success, Result = pcall(PlayerSkillInput.simulateSlotPressRelease, SkillSlotConfig.NORMAL_ATTACK_SLOT_INDEX, true)
    return Success and Result == true
end

local function manualClick()
    local Success, Result = pcall(function()
        return NetWork.InvokeServer(NetMsg.TRAIN_MANUAL_CLICK, {})
    end)
    return Success and type(Result) == "table" and Result.ok == true
end

local function isMarkedMaterial(Id)
    if GetData.Alchemy and GetData.Alchemy.IsMarkedRecipeMaterial then
        local Success, Result = pcall(GetData.Alchemy.IsMarkedRecipeMaterial, LocalPlayer, Id)
        return Success and Result == true
    end
    return false
end

local function collectSellableMaterials()
    local Bag = PlayerData.GetPlrDataByKey(LocalPlayer, "Bag")
    local Result = {}
    if type(Bag) ~= "table" then
        return Result
    end
    for _, Item in pairs(Bag) do
        if type(Item) == "table"
            and tonumber(Item.tp) == EnumMgr.ItemType.Material
            and Item.lock ~= true
            and Item.lock ~= 1
            and (tonumber(Item.count) or 1) > 0
            and not isMarkedMaterial(tonumber(Item.id)) then
            local OnlyId = tonumber(Item.onlyID)
            local Config = CfgFind.FindCfgByID(Item.id, EnumMgr.ItemType.Material)
            local Price = 0
            if Config and GetData.GetSellPrice then
                local Success, Value = pcall(GetData.GetSellPrice, LocalPlayer, Config)
                Price = Success and tonumber(Value) or 0
            end
            if OnlyId and Price and Price > 0 then
                table.insert(Result, OnlyId)
            end
        end
    end
    return Result
end

local function sellMaterials()
    local OnlyIds = collectSellableMaterials()
    if #OnlyIds == 0 then
        return false
    end
    local Success, Result = pcall(function()
        return NetWork.InvokeServer(NetMsg.SELL_MATERIAL, {onlyIDList = OnlyIds})
    end)
    return Success and Result == true
end

local function isBroomChangeBlocked()
    local Flying = false
    if GetData.GetIsFly then
        local Success, Result = pcall(GetData.GetIsFly, LocalPlayer)
        Flying = Success and Result == true
    end
    return Flying or getNumber("StageJumping") > 0
end

local function isUpgradeEnabled(Spec)
    if Spec.Name == "Weapon" then
        return State.UpgradeWeapon
    end
    if Spec.Name == "Armor" then
        return State.UpgradeArmor
    end
    return State.UpgradeBroom
end

local function findBestUpgrade(Spec)
    local Coins = tonumber(GetData.GetItemCountByID(LocalPlayer, EnumMgr.ItemID.Coin)) or 0
    local CurrentId = EquipShop.GetEquippedCfgId(LocalPlayer, Spec.SaveKey)
    local CurrentConfig = EquipShop.FindShopCfg(CurrentId, Spec.ItemType)
    local Best
    local Shop = EquipShop.BuildShopList(Spec.ConfName)
    if type(Shop) ~= "table" then
        return nil
    end
    for _, Entry in ipairs(Shop) do
        local Config = Entry.cfg
        local Owned = EquipShop.OwnsInBag(LocalPlayer, Entry.id, Spec.ItemType)
        local Price = Config and tonumber(Config.Price) or 0
        local Available = Owned or Config and EquipShop.IsCoinPurchasable(Config) and Price > 0 and Price <= Coins
        local ImprovesCurrent = Config and (not CurrentConfig or EquipShop.IsAutoEquipBetter(Config, CurrentConfig, Spec.ItemType))
        local ImprovesBest = Config and (not Best or EquipShop.IsAutoEquipBetter(Config, Best.Config, Spec.ItemType))
        if Available and ImprovesCurrent and ImprovesBest then
            Best = {Id = Entry.id, Config = Config, Owned = Owned}
        end
    end
    return Best
end

local function upgradeEquipment(Spec)
    if not isUpgradeEnabled(Spec) then
        return false
    end
    if Spec.ItemType == EnumMgr.ItemType.Broom and isBroomChangeBlocked() then
        return false
    end
    local Best = findBestUpgrade(Spec)
    if not Best then
        return false
    end
    local Message = Best.Owned and NetMsg.EQUIP_SHOP_EQUIP or NetMsg.EQUIP_SHOP_BUY
    local Success, Result = pcall(function()
        return NetWork.InvokeServer(Message, {equipID = Best.Id, itemType = Spec.ItemType})
    end)
    return Success and Result == true
end

local function upgradeNextEquipment()
    for Offset = 0, #ShopSpecs - 1 do
        local Index = (Hub.UpgradeCursor + Offset - 1) % #ShopSpecs + 1
        local Spec = ShopSpecs[Index]
        if isUpgradeEnabled(Spec) then
            Hub.UpgradeCursor = Index % #ShopSpecs + 1
            return upgradeEquipment(Spec)
        end
    end
    return false
end

local function rebirth()
    local Success, Result = pcall(function()
        return NetWork.InvokeServer(NetMsg.PLAYER_REBIRTH)
    end)
    return Success and Result == true
end

local function potionAttributesOverlap(First, Second)
    if type(First) ~= "table" or type(Second) ~= "table" then
        return false
    end
    for _, FirstAttribute in ipairs(First) do
        for _, SecondAttribute in ipairs(Second) do
            if tostring(FirstAttribute) == tostring(SecondAttribute) then
                return true
            end
        end
    end
    return false
end

local function hasActivePotionGroup(BuffConfig)
    local BuffFolder = LocalPlayer:FindFirstChild("BUFF")
    if not BuffFolder then
        return false
    end
    for _, Value in ipairs(BuffFolder:GetChildren()) do
        if Value:IsA("NumberValue") and Value.Value > 0 then
            local ActiveConfig = CfgFind.GetBuffCfgByID(Value.Name)
            if ActiveConfig and potionAttributesOverlap(BuffConfig.buffAttr, ActiveConfig.buffAttr) then
                return true
            end
        end
    end
    return false
end

local function getPotionGroupKey(BuffConfig, BuffId)
    local Attributes = {}
    if type(BuffConfig.buffAttr) == "table" then
        for _, Attribute in ipairs(BuffConfig.buffAttr) do
            table.insert(Attributes, tostring(Attribute))
        end
    end
    table.sort(Attributes)
    return #Attributes > 0 and table.concat(Attributes, ":") or tostring(BuffId)
end

local function findPotionCandidate()
    local Bag = PlayerData.GetPlrDataByKey(LocalPlayer, "Bag")
    if type(Bag) ~= "table" then
        return nil
    end
    local BestByGroup = {}
    for Key, Item in pairs(Bag) do
        if type(Item) == "table"
            and tonumber(Item.tp) == EnumMgr.ItemType.Potion
            and (tonumber(Item.count) or 0) > 0
            and Item.lock ~= true
            and Item.lock ~= 1 then
            local OnlyId = tonumber(Item.onlyID) or tonumber(Key)
            local ItemId = tonumber(Item.id) or 0
            local Config = CfgFind.FindCfgByID(ItemId, EnumMgr.ItemType.Potion)
            local BuffId = Config and (tonumber(Config.BuffID) or 0) or 0
            local SkillId = Config and (tonumber(Config.SkillID) or 0) or 0
            local BuffConfig = BuffId > 0 and CfgFind.GetBuffCfgByID(BuffId) or nil
            if OnlyId and OnlyId > 0 and BuffId > 0 and SkillId <= 0 and BuffConfig and not hasActivePotionGroup(BuffConfig) then
                local Group = getPotionGroupKey(BuffConfig, BuffId)
                local Candidate = {
                    OnlyId = OnlyId,
                    Group = Group,
                    Power = tonumber(BuffConfig.addPower) or 0,
                    Rarity = tonumber(Config.xyd) or 0,
                    ItemId = ItemId
                }
                local Current = BestByGroup[Group]
                if not Current
                    or Candidate.Power > Current.Power
                    or Candidate.Power == Current.Power and Candidate.Rarity > Current.Rarity
                    or Candidate.Power == Current.Power and Candidate.Rarity == Current.Rarity and Candidate.ItemId > Current.ItemId then
                    BestByGroup[Group] = Candidate
                end
            end
        end
    end
    local Candidates = {}
    for _, Candidate in pairs(BestByGroup) do
        table.insert(Candidates, Candidate)
    end
    table.sort(Candidates, function(First, Second)
        if First.Power == Second.Power then
            if First.Rarity == Second.Rarity then
                return First.ItemId > Second.ItemId
            end
            return First.Rarity > Second.Rarity
        end
        return First.Power > Second.Power
    end)
    local Now = os.clock()
    for _, Candidate in ipairs(Candidates) do
        if Now - (Hub.PotionAttempts[Candidate.Group] or 0) >= 2 then
            return Candidate
        end
    end
    return nil
end

local function useNextPotion()
    if Hub.PotionBusy or getNumber("InDungeonChallenge") > 0 or getNumber("StageJumping") > 0 then
        return false
    end
    local Candidate = findPotionCandidate()
    if not Candidate then
        return false
    end
    Hub.PotionAttempts[Candidate.Group] = os.clock()
    Hub.PotionBusy = true
    local Success = pcall(function()
        NetWork.InvokeServer(NetMsg.DRINK_POTION, {onlyID = Candidate.OnlyId})
    end)
    Hub.PotionBusy = false
    return Success
end

local function getOnlineRewardView(OnlineBox)
    local View = {}
    for Key, Value in pairs(OnlineBox) do
        View[Key] = Value
    end
    local RawSeconds = tonumber(OnlineBox.OnlineSeconds) or 0
    local Now = os.clock()
    if Hub.OnlineAnchorRaw == nil or RawSeconds ~= Hub.OnlineAnchorRaw then
        Hub.OnlineAnchorRaw = RawSeconds
        Hub.OnlineAnchorSeconds = RawSeconds
        Hub.OnlineAnchorAt = Now
    end
    View.OnlineSeconds = Hub.OnlineAnchorSeconds + math.max(0, Now - Hub.OnlineAnchorAt)
    return View
end

local function collectOnlineReward()
    if Hub.OnlineRewardBusy then
        return false
    end
    local OnlineBox = PlayerData.GetPlrDataByKey(LocalPlayer, "OnlineBox")
    if type(OnlineBox) ~= "table" then
        return false
    end
    local OnlineView = getOnlineRewardView(OnlineBox)
    for _, Config in ipairs(CfgFind.GetOnlineAwardList()) do
        local TierId = tonumber(Config.id)
        if TierId and CfgFind.IsOnlineTierClaimable(OnlineView, Config) then
            Hub.OnlineRewardBusy = true
            local Success, Result = pcall(function()
                return NetWork.InvokeServer(NetMsg.CLAIM_ONLINE_AWARD, TierId)
            end)
            Hub.OnlineRewardBusy = false
            if Success and Result ~= nil and Result ~= false then
                local UpdatedBox = PlayerData.GetPlrDataByKey(LocalPlayer, "OnlineBox")
                local UpdatedSeconds = type(UpdatedBox) == "table" and (tonumber(UpdatedBox.OnlineSeconds) or 0) or 0
                Hub.OnlineAnchorRaw = UpdatedSeconds
                Hub.OnlineAnchorSeconds = UpdatedSeconds
                Hub.OnlineAnchorAt = os.clock()
            end
            return Success and Result ~= nil and Result ~= false
        end
    end
    return false
end

local function readValue(Root, Name)
    local Value = Root and Root:FindFirstChild(Name, true)
    if Value and Value:IsA("ValueBase") then
        return Value.Value
    end
    return nil
end

local function getActiveDrops()
    local Drops = workspace:FindFirstChild("DropsClient")
    local Result = {}
    if not Drops then
        return Result
    end
    for _, RarityContainer in Drops:GetChildren() do
        if RarityContainer:IsA("Model") and tonumber(RarityContainer.Name) then
            for _, Item in RarityContainer:GetChildren() do
                if Item:IsA("Model") and Item.Name == "DropItem" then
                    local Primary = Item.PrimaryPart or Item:FindFirstChildWhichIsA("BasePart", true)
                    local Prompt = Primary and Primary:FindFirstChild("PickupPrompt") or Item:FindFirstChild("PickupPrompt", true)
                    local Landed = Item:GetAttribute("DropLanded")
                    if Landed == nil then
                        Landed = readValue(Item, "DropLanded")
                    end
                    local Rarity = tonumber(Item:GetAttribute("Xyd")) or tonumber(readValue(Item, "Xyd")) or tonumber(RarityContainer.Name) or 0
                    local GoldValue = tonumber(Item:GetAttribute("GoldValue")) or tonumber(readValue(Item, "GoldValue")) or 0
                    if Primary and Prompt and Prompt:IsA("ProximityPrompt") and (Landed == nil or Landed == true) and Rarity >= State.LootMinRarity and GoldValue >= State.LootMinValue then
                        table.insert(Result, {
                            Slot = Item,
                            Primary = Primary,
                            Prompt = Prompt,
                            Rarity = Rarity,
                            GoldValue = GoldValue
                        })
                    end
                end
            end
        end
    end
    table.sort(Result, function(A, B)
        if A.GoldValue == B.GoldValue then
            return A.Rarity > B.Rarity
        end
        return A.GoldValue > B.GoldValue
    end)
    return Result
end

local function triggerPrompt(Prompt)
    if fireproximityprompt then
        return pcall(fireproximityprompt, Prompt)
    end
    local Success = pcall(function()
        Prompt:InputHoldBegin()
        task.wait(math.max(0.05, Prompt.HoldDuration + 0.05))
        Prompt:InputHoldEnd()
    end)
    return Success
end

local function collectDrops(Duration)
    if Hub.CollectingLoot or not State.AutoLoot then
        return false
    end
    Hub.CollectingLoot = true
    Hub.FarmTarget = nil
    local Collected = false
    local Deadline = os.clock() + (Duration or 2)
    while Hub.Running and State.AutoFarm and os.clock() < Deadline do
        local Drops = getActiveDrops()
        if #Drops == 0 then
            break
        end
        local Progress = false
        for _, Drop in Drops do
            if not Hub.Running or not State.AutoFarm or os.clock() >= Deadline then
                break
            end
            if Drop.Primary.Parent and Drop.Prompt.Parent then
                moveRoot(Drop.Primary.CFrame + Vector3.new(0, 3, 0))
                task.wait(0.1)
                if triggerPrompt(Drop.Prompt) then
                    Progress = true
                    Collected = true
                end
                task.wait(0.12)
            end
        end
        if not Progress then
            break
        end
    end
    Hub.CollectingLoot = false
    Hub.LastLootAt = os.clock()
    return Collected
end

local function requestStageJump(Stage)
    local Now = os.clock()
    if Now - Hub.LastJumpRequest < 6 then
        return false
    end
    if Hub.JumpAttemptAt <= 0 then
        Hub.JumpAttemptAt = Now
    end
    Hub.LastJumpRequest = Now
    Hub.LastStageRequest = Now
    pcall(NetWork.FireServer, NetMsg.STAGE_JUMP_REQUEST, Stage)
    return true
end

local function requestStageSpawn(Stage)
    local Now = os.clock()
    if Now - Hub.LastStageRequest < 2.5 then
        return false
    end
    Hub.LastStageRequest = Now
    local BattleArea = findStagePart(Stage, "BattleArea")
    if BattleArea then
        moveRoot(BattleArea.CFrame + Vector3.new(0, math.min(2, BattleArea.Size.Y * 0.1), 0))
        task.wait(0.18)
    end
    pcall(NetWork.FireServer, NetMsg.DUNGEON_SPAWN_STAGE, Stage)
    return true
end

local function isBackpackFull()
    local Now = os.clock()
    if Now - Hub.LastBackpackCheck < 0.5 then
        return Hub.BackpackFull
    end
    Hub.LastBackpackCheck = Now
    local UsedValue = LocalPlayer:FindFirstChild("LimitBagUsed")
    local BagValues = LocalPlayer:FindFirstChild("Bag")
    local MaximumValue = BagValues and BagValues:FindFirstChild(tostring(EnumMgr.ItemID.LimitBagSize))
    local Current = UsedValue and UsedValue:IsA("NumberValue") and math.max(0, math.floor(tonumber(UsedValue.Value) or 0)) or 0
    local Maximum = MaximumValue and MaximumValue:IsA("NumberValue") and math.max(0, math.floor(tonumber(MaximumValue.Value) or 0)) or 0
    Hub.BackpackCurrent = Current
    Hub.BackpackMaximum = Maximum
    Hub.BackpackFull = Maximum > 0 and Current >= Maximum
    return Hub.BackpackFull
end

local function requestReturnTown()
    local Now = os.clock()
    if Now - Hub.LastReturnRequest < 2 then
        return false
    end
    Hub.LastReturnRequest = Now
    Hub.NextRunAt = Now + 3
    pcall(NetWork.FireServer, NetMsg.DUNGEON_RETURN_TOWN)
    return true
end

local function handleRetreat(Stage)
    if not State.EmergencyRetreat then
        Hub.Retreating = false
        return false
    end
    local _, Humanoid = getCharacter()
    if not Humanoid or Humanoid.MaxHealth <= 0 then
        Hub.Retreating = false
        return false
    end
    local HealthPercent = Humanoid.Health / Humanoid.MaxHealth * 100
    if not Hub.Retreating and HealthPercent <= State.RetreatHealth then
        Hub.Retreating = true
        Hub.FarmTarget = nil
    elseif Hub.Retreating and HealthPercent >= math.max(State.RetreatHealth, State.ResumeHealth) then
        Hub.Retreating = false
    end
    if not Hub.Retreating then
        return false
    end
    local SafeArea = findStagePart(Stage, "SafeArea")
    if SafeArea and not Hub.CollectingLoot then
        moveRoot(SafeArea.CFrame + Vector3.new(0, 2, 0))
    end
    return true
end

local function stopFarmAfterTown()
    Hub.StopAfterTown = false
    if Hub.Options and Hub.Options.AutoFarm then
        Hub.Options.AutoFarm:SetValue(false)
    else
        State.AutoFarm = false
    end
end

local function farmStep()
    if not State.AutoFarm or Hub.CollectingLoot then
        return
    end
    local Character, Humanoid = getCharacter()
    if not Character or not Humanoid or Humanoid.Health <= 0 then
        Hub.FarmTarget = nil
        return
    end
    if getNumber("StageJumping") > 0 or Character:GetAttribute("StageJumpAnimating") then
        Hub.FarmTarget = nil
        return
    end
    local InDungeon = getNumber("InDungeonChallenge")
    if InDungeon <= 0 then
        Hub.FarmTarget = nil
        Hub.Retreating = false
        if Hub.StopAfterTown then
            stopFarmAfterTown()
            return
        end
        if os.clock() < Hub.NextRunAt then
            return
        end
        local BroomMax = getBroomJumpMax()
        if BroomMax <= 0 then
            if Hub.JumpAttemptAt <= 0 then
                Hub.JumpAttemptAt = os.clock()
            end
            requestStageSpawn(1)
        else
            local JumpStage = getJumpStage(State.MaxDungeon)
            requestStageJump(JumpStage)
        end
        if BroomMax > 0 and Hub.JumpAttemptAt > 0 and os.clock() - Hub.JumpAttemptAt >= 8 then
            requestStageSpawn(1)
        end
        return
    end
    Hub.JumpAttemptAt = 0
    if State.ReturnIfBackpackFull and isBackpackFull() then
        Hub.FarmTarget = nil
        Hub.Retreating = false
        requestReturnTown()
        return
    end
    local Cleared = getNumber("DungeonRunMaxClear")
    local ActiveStage = math.max(1, Cleared + 1)
    if handleRetreat(math.max(1, getNumber("DungeonAggroStage"), InDungeon, ActiveStage)) then
        return
    end
    if Cleared >= State.MaxDungeon then
        Hub.FarmTarget = nil
        if State.AutoLoot and os.clock() - Hub.LastLootAt > 0.5 then
            collectDrops(2.5)
        end
        if not State.RepeatRuns then
            Hub.StopAfterTown = true
        end
        requestReturnTown()
        return
    end
    local Enemy = findNearestEnemy(ActiveStage, math.huge)
    if Enemy then
        Hub.FarmTarget = Enemy.Root
        Hub.EmptyStage = 0
        Hub.StageEmptyAt = 0
        return
    end
    Hub.FarmTarget = nil
    if State.AutoLoot and os.clock() - Hub.LastLootAt > 0.8 then
        collectDrops(1.5)
        Cleared = getNumber("DungeonRunMaxClear")
        ActiveStage = math.max(1, Cleared + 1)
        if Cleared >= State.MaxDungeon then
            return
        end
        Enemy = findNearestEnemy(ActiveStage, math.huge)
        if Enemy then
            Hub.FarmTarget = Enemy.Root
            return
        end
    end
    if Hub.EmptyStage ~= ActiveStage then
        Hub.EmptyStage = ActiveStage
        Hub.StageEmptyAt = os.clock()
    end
    if os.clock() - Hub.StageEmptyAt >= 0.5 then
        requestStageSpawn(ActiveStage)
    end
end

local Window = Fluent:CreateWindow({
    Title = "Magic Loot",
    SubTitle = "",
    Search = true,
    Icon = "wand-sparkles",
    TabWidth = 170,
    Size = UDim2.fromOffset(620, 500),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({Title = "Main", Icon = "home"}),
    Dungeon = Window:AddTab({Title = "Dungeon Farm", Icon = "castle"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
}

Fluent:CreateMinimizer({
    Icon = "wand-sparkles",
    Size = UDim2.fromOffset(44, 44),
    Position = UDim2.new(0, 24, 0, 180),
    Acrylic = true,
    Corner = 10,
    Transparency = 1,
    Draggable = true,
    Visible = true
})

local Options = Fluent.Options
Hub.Options = Options

Tabs.Main:AddSection("Progression", "trending-up")
Tabs.Main:AddToggle("AutoClick", {
    Title = "Auto Click",
    Default = false
}):OnChanged(function(Value)
    State.AutoClick = Value
end)
Tabs.Main:AddToggle("AutoSell", {
    Title = "Auto Sell",
    Default = false
}):OnChanged(function(Value)
    State.AutoSell = Value
end)
Tabs.Main:AddToggle("AutoRebirth", {
    Title = "Auto Rebirth",
    Default = false
}):OnChanged(function(Value)
    State.AutoRebirth = Value
end)
Tabs.Main:AddToggle("AutoUsePotions", {
    Title = "Auto Use Potions",
    Default = false
}):OnChanged(function(Value)
    State.AutoUsePotions = Value
    Hub.LastPotionAt = 0
end)
Tabs.Main:AddToggle("AutoCollectOnlineRewards", {
    Title = "Auto Collect Online Rewards",
    Default = false
}):OnChanged(function(Value)
    State.AutoCollectOnlineRewards = Value
    Hub.LastOnlineRewardAt = 0
end)
Tabs.Main:AddToggle("AutoUpgrade", {
    Title = "Auto Upgrade",
    Default = false
}):OnChanged(function(Value)
    State.AutoUpgrade = Value
end)
Tabs.Main:AddToggle("UpgradeWeapon", {Title = "Upgrade Weapon", Default = true}):OnChanged(function(Value)
    State.UpgradeWeapon = Value
end)
Tabs.Main:AddToggle("UpgradeArmor", {Title = "Upgrade Armor", Default = true}):OnChanged(function(Value)
    State.UpgradeArmor = Value
end)
Tabs.Main:AddToggle("UpgradeBroom", {Title = "Upgrade Broom", Default = true}):OnChanged(function(Value)
    State.UpgradeBroom = Value
end)

Tabs.Main:AddSection("Session", "clock")
Tabs.Main:AddToggle("AntiAFK", {Title = "Anti AFK", Default = true}):OnChanged(function(Value)
    State.AntiAFK = Value
end)

Tabs.Dungeon:AddSection("Route", "route")
Tabs.Dungeon:AddToggle("AutoFarm", {
    Title = "Auto Farm",
    Default = false
}):OnChanged(function(Value)
    State.AutoFarm = Value
    Hub.FarmTarget = nil
    Hub.Retreating = false
    Hub.EmptyStage = 0
    Hub.StageEmptyAt = 0
    Hub.StopAfterTown = false
    if Value then
        Hub.NextRunAt = 0
        Hub.LastJumpRequest = 0
        Hub.JumpAttemptAt = 0
        Hub.LastStageRequest = 0
    elseif Hub.NoclipActive then
        setNoclip(false)
    end
    if not Value then
        clearForcedTarget()
    end
end)
Tabs.Dungeon:AddDropdown("MaxDungeon", {
    Title = "Maximum Dungeon",
    Description = "Return after the selected dungeon.",
    Values = DungeonValues,
    Multi = false,
    Search = true,
    Default = #DungeonValues
}):OnChanged(function(Value)
    local Number = tonumber(tostring(Value):match("%d+"))
    if Number then
        State.MaxDungeon = math.floor(Number)
    end
end)
Tabs.Dungeon:AddToggle("RepeatRuns", {
    Title = "Repeat Runs",
    Default = true
}):OnChanged(function(Value)
    State.RepeatRuns = Value
end)
Tabs.Dungeon:AddToggle("ReturnIfBackpackFull", {
    Title = "Return If Backpack Full",
    Default = false
}):OnChanged(function(Value)
    State.ReturnIfBackpackFull = Value
    Hub.LastBackpackCheck = 0
    Hub.BackpackFull = false
end)
Tabs.Dungeon:AddSlider("FarmHeight", {
    Title = "Height Above Enemy",
    Default = 14,
    Min = 7,
    Max = 25,
    Rounding = 0,
    Callback = function(Value)
        State.FarmHeight = Value
    end
})

Tabs.Dungeon:AddSection("Loot", "gem")
Tabs.Dungeon:AddToggle("AutoLoot", {
    Title = "Auto Loot",
    Default = true
}):OnChanged(function(Value)
    State.AutoLoot = Value
end)
Tabs.Dungeon:AddSlider("LootMinRarity", {
    Title = "Minimum Loot Rarity",
    Description = "Set 1 to collect everything.",
    Default = 1,
    Min = 1,
    Max = 10,
    Rounding = 0,
    Callback = function(Value)
        State.LootMinRarity = Value
    end
})
Tabs.Dungeon:AddInput("LootMinValue", {
    Title = "Minimum Loot Value",
    Description = "Set 0 to collect everything.",
    Default = "0",
    Placeholder = "0",
    Numeric = true,
    Finished = true,
    Callback = function(Value)
        State.LootMinValue = math.max(0, math.floor(tonumber(Value) or 0))
    end
})

Tabs.Dungeon:AddSection("Survival", "shield")
Tabs.Dungeon:AddToggle("EmergencyRetreat", {
    Title = "Emergency Retreat",
    Default = true
}):OnChanged(function(Value)
    State.EmergencyRetreat = Value
    if not Value then
        Hub.Retreating = false
    end
end)
Tabs.Dungeon:AddSlider("RetreatHealth", {
    Title = "Retreat Health Percent",
    Default = 25,
    Min = 5,
    Max = 60,
    Rounding = 0,
    Callback = function(Value)
        State.RetreatHealth = Value
    end
})
Tabs.Dungeon:AddSlider("ResumeHealth", {
    Title = "Resume Health Percent",
    Default = 70,
    Min = 30,
    Max = 100,
    Rounding = 0,
    Callback = function(Value)
        State.ResumeHealth = Value
    end
})

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("MagicLootHub")
SaveManager:SetFolder("MagicLootHub/MagicLoot")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

addConnection(LocalPlayer.Idled:Connect(function()
    if State.AntiAFK then
        VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
    end
end))

addConnection(RunService.Heartbeat:Connect(function()
    if State.AutoFarm then
        setNoclip(true)
        local Target = Hub.FarmTarget
        if Target and Target.Parent and not Hub.CollectingLoot and not Hub.Retreating then
            local Position = Target.Position + Vector3.new(0, State.FarmHeight, 0)
            moveRoot(CFrame.new(Position) * CFrame.Angles(0, math.rad(Target.Orientation.Y), 0))
        end
    elseif Hub.NoclipActive then
        setNoclip(false)
    end
end))

task.spawn(function()
    while Hub.Running do
        if State.AutoClick and getNumber("InDungeonChallenge") <= 0 and os.clock() - Hub.LastClickAt >= 0.16 then
            Hub.LastClickAt = os.clock()
            manualClick()
        end
        task.wait(0.04)
    end
end)

task.spawn(function()
    while Hub.Running do
        if State.AutoSell and getNumber("InDungeonChallenge") <= 0 and os.clock() - Hub.LastSellAt >= 2 then
            Hub.LastSellAt = os.clock()
            sellMaterials()
        end
        task.wait(0.25)
    end
end)

task.spawn(function()
    while Hub.Running do
        if State.AutoUpgrade and getNumber("InDungeonChallenge") <= 0 and getNumber("StageJumping") <= 0 and os.clock() - Hub.LastUpgradeAt >= 0.8 then
            Hub.LastUpgradeAt = os.clock()
            upgradeNextEquipment()
        end
        task.wait(0.2)
    end
end)

task.spawn(function()
    while Hub.Running do
        if State.AutoRebirth and getNumber("InDungeonChallenge") <= 0 and getNumber("StageJumping") <= 0 and os.clock() - Hub.LastRebirthAt >= 2 then
            Hub.LastRebirthAt = os.clock()
            rebirth()
        end
        task.wait(0.25)
    end
end)

task.spawn(function()
    while Hub.Running do
        if State.AutoUsePotions and getNumber("InDungeonChallenge") <= 0 and getNumber("StageJumping") <= 0 and os.clock() - Hub.LastPotionAt >= 1 then
            Hub.LastPotionAt = os.clock()
            useNextPotion()
        end
        task.wait(0.2)
    end
end)

task.spawn(function()
    while Hub.Running do
        if State.AutoCollectOnlineRewards and os.clock() - Hub.LastOnlineRewardAt >= 1 then
            Hub.LastOnlineRewardAt = os.clock()
            collectOnlineReward()
        end
        task.wait(0.25)
    end
end)

task.spawn(function()
    while Hub.Running do
        if State.AutoFarm then
            farmStep()
        else
            Hub.FarmTarget = nil
        end
        task.wait(0.12)
    end
end)

task.spawn(function()
    while Hub.Running do
        local Target
        if State.AutoFarm and Hub.FarmTarget and not Hub.CollectingLoot and not Hub.Retreating then
            Target = Hub.FarmTarget
        end
        if Target and Target.Parent then
            castAt(Target)
        end
        task.wait(0.16)
    end
end)

function Hub.Unload(FromFluent)
    if Hub.Unloading then
        return
    end
    Hub.Unloading = true
    Hub.Running = false
    State.AutoClick = false
    State.AutoSell = false
    State.AutoUpgrade = false
    State.AutoRebirth = false
    State.AutoUsePotions = false
    State.AutoCollectOnlineRewards = false
    State.AutoFarm = false
    Hub.FarmTarget = nil
    Hub.CollectingLoot = false
    Hub.Retreating = false
    setNoclip(false)
    clearForcedTarget()
    for _, Connection in Hub.Connections do
        pcall(function()
            Connection:Disconnect()
        end)
    end
    if Environment.MagicLootHub == Hub then
        Environment.MagicLootHub = nil
    end
    if not FromFluent and Fluent and not Fluent.Unloaded then
        pcall(function()
            Fluent:Destroy()
        end)
    end
end

if Fluent.OnUnload then
    pcall(function()
        Fluent:OnUnload(function()
            Hub.Unload(true)
        end)
    end)
end

task.spawn(function()
    while Hub.Running and not Fluent.Unloaded do
        task.wait(0.25)
    end
    if Hub.Running then
        Hub.Unload(true)
    end
end)

local SafeStartupOptions = {"AutoClick", "AutoSell", "AutoUpgrade", "AutoRebirth", "AutoUsePotions", "AutoCollectOnlineRewards", "AutoFarm"}
for _, Name in SafeStartupOptions do
    local Option = Options[Name]
    if Option and Option.SetValue then
        Option:SetValue(false)
    else
        State[Name] = false
    end
end
clearForcedTarget()
setNoclip(false)

Window:SelectTab(1)
Fluent:Notify({
    Title = "Magic Loot Hub",
    Content = "Loaded with live game mappings.",
    Duration = 6
})

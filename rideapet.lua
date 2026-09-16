local Env = getgenv and getgenv() or _G
if game.PlaceId ~= 124216119978534 then error("Ride A Pet: this game is not supported.") end
if Env.RideAPetCompact and Env.RideAPetCompact.Unload then Env.RideAPetCompact:Unload() end
local A = {
    Alive = true, Epoch = 0, Connections = {}, Threads = {}, Markers = {}, Cooldowns = {},
    FailedEggs = {}, Errors = {}, Collected = 0, Hatched = 0, Placed = 0, Claimed = 0,
    Status = "Ready", Cache = {}, States = {}, FilterStates = {}, PreviewAngle = 0,
    Options = {
        AntiAFK = true, EggESP = false, AutoCollect = false, AutoPlace = false,
        AutoHatch = false, AutoIndex = false, AutoBest = false, TweenSpeed = 180,
        ESPDistance = 5000, ESPCount = 40, ESPSize = 15, ESPBoxes = false,
        ESPTracers = false, ESPName = true, ESPRarity = true, ESPWeight = true,
        ESPMutation = true, ESPLuck = true, ESPShowDistance = true,
        MaxDistance = 6000, EggPriority = "Nearest", SelectedEgg = nil,
        BestMetric = "Income", RotatePreview = true,
        AutoBuyFood = false, AutoFeed = false, AutoSell = false, AutoFavorites = false, ManualFeedCount = 1,
    },
    Filters = {
        Eggs = {Rarities = {}, Types = {}, Mutations = {}, MinLuck = 0, MinWeight = 0, MaxDistance = 15000, Search = "", MutatedOnly = false},
        ESP = {Rarities = {}, Types = {}, Mutations = {}, MinLuck = 0, MinWeight = 0, Search = "", MutatedOnly = false},
        Collect = {Rarities = {}, Types = {}, Mutations = {}, MinLuck = 0, MinWeight = 0, Search = "", MutatedOnly = false},
    },
    RarityNames = {"Common", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Ethereal"},
    RarityOrder = {Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Divine = 6, Ethereal = 7},
    RarityColors = {
        Common = Color3.fromRGB(230,235,237), Rare = Color3.fromRGB(100,195,255),
        Epic = Color3.fromRGB(197,145,255), Legendary = Color3.fromRGB(255,213,104),
        Mythic = Color3.fromRGB(255,125,160), Divine = Color3.fromRGB(255,245,182),
        Ethereal = Color3.fromRGB(120,255,215),
    },
}
Env.RideAPetCompact = A
A.Players = game:GetService("Players")
A.Player = A.Players.LocalPlayer
A.RS = game:GetService("ReplicatedStorage")
A.Run = game:GetService("RunService")
A.TweenService = game:GetService("TweenService")
A.UIS = game:GetService("UserInputService")
A.VirtualUser = game:GetService("VirtualUser")
A.Remotes = A.RS:WaitForChild("Remotes",15):WaitForChild("Game",15)
A.Saved = A.Player:WaitForChild("SavedData",15)
A.ActiveEggs = A.RS:WaitForChild("ServerData",15):WaitForChild("ActiveEggs",15)
A.Data, A.Services = {}, {}
for _,name in ipairs({"Eggs","Pets","General","Mutations","EggBaskets","IndexRewards"}) do
    A.Data[name] = require(A.RS.GameData:WaitForChild(name,10))
end
for _,name in ipairs({"PetAging","DayNight"}) do A.Services[name] = require(A.RS.GameServices:WaitForChild(name,10)) end
pcall(function() A.Renderer = require(A.Player.PlayerScripts.Game.Pets.PetRenderer) end)
A.EggNames, A.MutationNames = {}, {"None"}
for name,data in pairs(A.Data.Eggs) do
    if type(data)=="table" and not data.Premium then table.insert(A.EggNames,name) end
end
table.sort(A.EggNames,function(a,b) return (A.Data.Eggs[a].Luck or 0)<(A.Data.Eggs[b].Luck or 0) end)
for name,data in pairs(A.Data.Mutations) do if type(data)=="table" then table.insert(A.MutationNames,name) end end
table.sort(A.MutationNames)
for _,f in pairs(A.Filters) do
    for _,name in ipairs(A.RarityNames) do f.Rarities[name]=true end
    for _,name in ipairs(A.EggNames) do f.Types[name]=true end
    for _,name in ipairs(A.MutationNames) do f.Mutations[name]=true end
end

function A:Connect(signal, callback)
    local connection = signal:Connect(function(...)
        if self.Alive then callback(...) end
    end)
    table.insert(self.Connections, connection)
    return connection
end

function A:Value(name, default)
    local value = self.Saved:FindFirstChild(name)
    if value then return value.Value end
    return default
end

function A:Character()
    local character = self.Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and root and humanoid.Health > 0 then return character, humanoid, root end
end

function A:Plot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        local data = plot:FindFirstChild("Data")
        local owner = data and data:FindFirstChild("Owner")
        if owner and owner.Value == self.Player then return plot end
    end
end

function A:OnPlot()
    local _, _, root = self:Character()
    local plot = self:Plot()
    local base = plot and plot:FindFirstChild("Baseplate")
    if not root or not base then return false end
    local point = base.CFrame:PointToObjectSpace(root.Position)
    return math.abs(point.X) < base.Size.X / 2 and math.abs(point.Z) < base.Size.Z / 2 and math.abs(point.Y) < 35
end

function A:Tools()
    local result = {}
    for _, root in ipairs({self.Player:FindFirstChild("Backpack"), self.Player.Character}) do
        if root then
            for _, item in ipairs(root:GetChildren()) do
                if item:IsA("Tool") then table.insert(result, item) end
            end
        end
    end
    return result
end

function A:Tool(name, key)
    for _, tool in ipairs(self:Tools()) do
        if (not name or tool.Name == name) and (not key or tool:GetAttribute("PetKey") == key) then return tool end
    end
end

function A:Equip(tool)
    local _, humanoid = self:Character()
    if humanoid and tool and tool.Parent then
        humanoid:EquipTool(tool)
        return true
    end
    return false
end

function A:Fire(name, ...)
    if not self.Alive then return false end
    local remote = self.Remotes:FindFirstChild(name)
    if not remote or not remote:IsA("RemoteEvent") then return false end
    remote:FireServer(...)
    return true
end

function A:Ready(key, interval)
    local now = os.clock()
    if now < (self.Cooldowns[key] or 0) then return false end
    self.Cooldowns[key] = now + interval
    return true
end

function A:Valid(token)
    return self.Alive and self.Epoch == token
end

function A:WaitFor(predicate, seconds, token)
    local deadline = os.clock() + seconds
    repeat
        if token and not self:Valid(token) then return false end
        if not self.Alive then return false end
        local value = predicate()
        if value then return value end
        task.wait(0.1)
    until os.clock() >= deadline
    return false
end

function A:Time(seconds)
    seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
    if seconds >= 3600 then return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
end

function A:Basket()
    local basket = self.Player:FindFirstChild("Basket")
    return basket and basket:GetChildren() or {}
end

function A:EggTools()
    local result = {}
    for _, tool in ipairs(self:Tools()) do
        if self.Data.Eggs[tool.Name] and not tool:GetAttribute("PetKey") then table.insert(result, tool) end
    end
    table.sort(result, function(a, b) return (self.Data.Eggs[a.Name].Luck or 0) > (self.Data.Eggs[b.Name].Luck or 0) end)
    return result
end

function A:Capacity()
    local config = self.Data.EggBaskets[self:Value("EquippedEggBasket", "Wooden")]
    return config and config.Capacity or 1
end

function A:FreeNests()
    local out = {}
    local plot = self:Plot()
    local nests = plot and plot:FindFirstChild("Nests")
    if nests then
        for _, nest in ipairs(nests:GetChildren()) do
            if nest:GetAttribute("Unlocked") and not nest:GetAttribute("Occupied") then table.insert(out, nest) end
        end
    end
    table.sort(out, function(a, b) return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0) end)
    return out
end

function A:PetList()
    local result, seen = {}, {}
    local function add(object, state, placed)
        local key = object:GetAttribute("PetKey")
        local name = object:GetAttribute("PetName") or object.Name
        local data = self.Data.Pets[name]
        if not key or not data or seen[key] then return end
        seen[key] = true
        local age = object:GetAttribute("Age") or (state and state.CurrentAge) or 1
        local weight = object:GetAttribute("Weight") or 10
        local mutation = object:GetAttribute("Mutation")
        local spawnMutation = object:GetAttribute("SpawnMutation")
        local factor = self.Data.Mutations.CombinedFactor(mutation, spawnMutation)
        local income = state and (state.DisplayIncome or state.Income)
        if not income then income = (data.Income or 0) * weight / 10 * factor end
        local speed = self.Services.PetAging.DisplaySpeedFor(data.Speed or 0, weight) * factor
        table.insert(result, {Key = key, Name = name, Object = object, State = state, Placed = placed, Age = age, Weight = weight, Income = income, Speed = speed, Rarity = data.Rarity, Mutation = mutation, SpawnMutation = spawnMutation, Favorite = object:GetAttribute("Favorited") == true})
    end
    if self.Renderer then
        for _, state in pairs(self.Renderer.GetAll()) do
            if state.OwnerUserId == self.Player.UserId and state.Model and state.Model.Parent then add(state.Model, state, true) end
        end
    end
    local plot = self:Plot()
    if plot and plot:FindFirstChild("Pets") then
        for _, pet in ipairs(plot.Pets:GetChildren()) do add(pet, nil, true) end
    end
    for _, tool in ipairs(self:Tools()) do add(tool, nil, false) end
    local _, _, root = self:Character()
    local joint = root and root:FindFirstChild("PetMountJoint")
    if joint and joint.Part1 then add(joint.Part1.Parent, nil, false) end
    table.sort(result, function(a, b) return a.Income > b.Income end)
    return result
end

function A:EggTimers()
    local rows = {}
    local plot = self:Plot()
    local eggs = plot and plot:FindFirstChild("Eggs")
    if not eggs then return rows end
    for _, egg in ipairs(eggs:GetChildren()) do
        local info = egg:FindFirstChild("EggData", true)
        local data = self.Data.Eggs[egg.Name]
        local start = info and info:FindFirstChild("PlaceTime")
        local weight = info and info:FindFirstChild("Weight")
        if data and start then
            local total = self.Data.General.GrowthTimeFor(data.GrowthTime or 0, weight and weight.Value or 1)
            local remaining = self.Services.DayNight.GrowthRealRemaining(start.Value, total)
            table.insert(rows, {Object = egg, Key = egg:GetAttribute("EggKey"), Name = egg.Name, Remaining = remaining})
        end
    end
    table.sort(rows, function(a, b) return a.Remaining < b.Remaining end)
    return rows
end

function A:Dismount(token)
    if self.Player:GetAttribute("IsRiding") then
        self:Fire("PetDismount")
        return self:WaitFor(function() return not self.Player:GetAttribute("IsRiding") end, 3, token)
    end
    return true
end

function A:SetAntiAFK(enabled)
    if self.AFKConnection then self.AFKConnection:Disconnect() self.AFKConnection = nil end
    if self.AFKRelease then
        pcall(function() self.VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame) end)
        self.AFKRelease = false
    end
    if enabled and self.Alive then
        self.AFKConnection = self.Player.Idled:Connect(function()
            if not self.Alive or not self.Options.AntiAFK then return end
            local ok, err = pcall(function()
                self.VirtualUser:CaptureController()
                self.VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
                self.AFKRelease = true
            end)
            if not ok then self:Error("Anti-AFK", err) return end
            task.delay(0.2, function()
                if self.AFKRelease then
                    pcall(function() self.VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame) end)
                    self.AFKRelease = false
                end
            end)
            self.LastAFK = os.clock()
        end)
    end
end

function A:PlaceEggs(token)
    if #self:Basket() == 0 and #self:EggTools() == 0 then return false end
    self.Status = "Returning with eggs"
    if not self:Home(token) then return false end
    local nests = self:FreeNests()
    if #nests == 0 then self.Status = "Eggs delivered; waiting for a free nest" return false end
    self:WaitFor(function() return #self:EggTools() > 0 end, 2, token)
    for _, nest in ipairs(nests) do
        if not self:Valid(token) then break end
        local tool = self:EggTools()[1]
        if not tool then break end
        self:Equip(tool)
        task.wait(0.15)
        if not self:Valid(token) then return false end
        self.Status = "Placing egg in nest " .. nest.Name
        self:Fire("EggPlaced", {NestId = nest.Name})
        if not self:WaitFor(function() return nest:GetAttribute("Occupied") end, 3, token) then return false end
    end
    self.Status = "Eggs placed in available nests"
    return true
end

function A:HatchReady(token)
    for _, egg in ipairs(self:EggTimers()) do
        if not self:Valid(token) then return end
        if egg.Remaining <= 0 and egg.Key and self:Ready("Hatch:" .. egg.Key, 5) then
            local _, _, root = self:Character()
            if not root then return end
            if (root.Position - egg.Object:GetPivot().Position).Magnitude > 12 then
                if not self:MoveTo(egg.Object:GetPivot().Position, token, 6, 20) then return end
            end
            if not self:Valid(token) then return end
            self:Fire("Hatch", {EggKey = egg.Key})
            if self:WaitFor(function() return not egg.Object.Parent end, 8, token) then self.Hatched = self.Hatched + 1 self.Status = "Hatched " .. egg.Name end
        end
    end
end

function A:ClaimIndex(token)
    local stage = tonumber(self:Value("IndexRewardStage", 0)) or 0
    local reward = self.Data.IndexRewards.StageAt(stage)
    local count = self.Data.IndexRewards.DiscoveredCount(self:Value("OwnedPets", ""))
    if reward and count >= reward.Goal then
        self:Fire("ClaimIndexReward")
        if self:WaitFor(function() return self:Value("IndexRewardStage", 0) ~= stage end, 2, token) then self.Claimed = self.Claimed + 1 self.Status = "Index reward claimed" else self.Status = "Index reward was not confirmed" end
    else
        self.Status = "No index reward is available yet"
    end
end

function A:Format(value)
    if value==nil then return "Unknown" end
    value=tonumber(value)
    if not value then return "Unknown" end
    if value==math.huge then return "Unlimited" end
    for _,unit in ipairs({{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"}}) do
        if math.abs(value)>=unit[1] then return string.format("%.2f%s",value/unit[1],unit[2]) end
    end
    return (string.format("%.2f",value):gsub("%.?0+$",""))
end

function A:Error(context, message)
    local value=context..": "..tostring(message)
    self.Status=value
    if self.Errors[#self.Errors]~=value then
        table.insert(self.Errors,value)
        if #self.Errors>8 then table.remove(self.Errors,1) end
        warn("[Ride A Pet] "..value)
    end
end

function A:EggList(filterName)
    local out={}
    local _,_,root=self:Character()
    local collected=","..tostring(self.Player:GetAttribute("CollectedEggs") or "")..","
    for _,object in ipairs(self.ActiveEggs:GetChildren()) do
        local name=object:GetAttribute("Egg")
        local data=name and self.Data.Eggs[name]
        local pos=object:GetAttribute("Position")
        local private=object:GetAttribute("PrivateTo")
        if data and typeof(pos)=="Vector3" and (not private or private==self.Player.UserId)
            and not string.find(collected,","..object.Name..",",1,true) then
            local rawWeight=object:GetAttribute("Weight") or 1
            local mutation=object:GetAttribute("Mutation")
            local spawn=object:GetAttribute("SpawnMutation")
            local row={ID=object.Name,Object=object,Name=name,Data=data,Position=pos,
                Distance=root and (root.Position-pos).Magnitude or math.huge,
                Rarity=data.Rarity or "Common",Mutation=mutation,SpawnMutation=spawn,
                Weight=rawWeight,KG=self.Data.General.ShownEggKG(rawWeight),Luck=data.Luck}
            row.MutationLabel=(mutation and mutation~="" and mutation) or "None"
            if spawn and spawn~="" and spawn~=mutation then
                row.MutationLabel=row.MutationLabel=="None" and spawn or row.MutationLabel.." + "..spawn
            end
            if not filterName or self:Matches(row,filterName) then table.insert(out,row) end
        end
    end
    table.sort(out,function(a,b)
        if filterName=="Collect" then
            local mode=self.Options.EggPriority
            if mode=="Highest luck" and a.Luck~=b.Luck then return (a.Luck or 0)>(b.Luck or 0) end
            if mode=="Rarest" and a.Rarity~=b.Rarity then return (self.RarityOrder[a.Rarity] or 0)>(self.RarityOrder[b.Rarity] or 0) end
            if mode=="Heaviest" and a.KG~=b.KG then return a.KG>b.KG end
        end
        if a.Distance==b.Distance then return a.ID<b.ID end
        return a.Distance<b.Distance
    end)
    return out
end

function A:Matches(egg,filterName)
    local f=self.Filters[filterName]
    local maxDistance=filterName=="ESP" and self.Options.ESPDistance or filterName=="Eggs" and f.MaxDistance or self.Options.MaxDistance
    local hasMutation,mutationOK=false,false
    for _,name in ipairs({egg.Mutation or "",egg.SpawnMutation or ""}) do
        if name~="" then hasMutation=true mutationOK=mutationOK or f.Mutations[name]==true end
    end
    if not hasMutation then mutationOK=f.Mutations.None==true end
    return f.Rarities[egg.Rarity]==true and f.Types[egg.Name]==true and mutationOK
        and (not f.MutatedOnly or egg.MutationLabel~="None")
        and (egg.Luck or 0)>=f.MinLuck and egg.KG>=f.MinWeight
        and string.find(string.lower(egg.Name),string.lower(f.Search),1,true)~=nil
        and egg.Distance<=maxDistance
end

function A:StopMovement()
    if self.FlightConnection then self.FlightConnection:Disconnect() self.FlightConnection=nil end
    if self.FlightTween then self.FlightTween:Cancel() self.FlightTween:Destroy() self.FlightTween=nil end
    local flight=self.Flight
    self.Flight=nil
    if flight then
        for part,value in pairs(flight.Collisions) do if part.Parent then part.CanCollide=value end end
        if flight.Humanoid.Parent then
            flight.Humanoid.PlatformStand=flight.PlatformStand
            flight.Humanoid.AutoRotate=flight.AutoRotate
        end
        if flight.Root.Parent then
            flight.Root.AssemblyLinearVelocity=Vector3.zero
            flight.Root.AssemblyAngularVelocity=Vector3.zero
        end
    end
end

function A:CancelJob()
    self.Epoch=self.Epoch+1
    local thread=self.JobThread
    self.JobThread=nil
    self.Job=nil
    self.CurrentFeedFood=nil
    self.CurrentFeedPet=nil
    self:StopMovement()
    if thread and thread~=coroutine.running() then pcall(task.cancel,thread) end
end

function A:StopCollecting()
    local collecting=self.Job and (self.Job:sub(1,11)=="Collecting " or self.Job=="Delivering eggs")
    local enabled=self.Options.AutoCollect
    self.Options.AutoCollect=false
    if collecting or enabled then self.EggDeliveryPaused=true end
    if collecting then self:CancelJob() end
    if self.ControlRefresh then self:ControlRefresh() end
    if collecting or enabled or not self.Job then self.Status="Egg collection stopped" end
end

function A:StartJob(name,callback)
    if not self.Alive or self.Job then self.Status="Finish or stop the current action first" return false end
    local token=self.Epoch
    self.Job=name
    self.Status=name
    self.JobThread=task.defer(function()
        local ok,err=xpcall(function() callback(token) end,debug.traceback)
        if not ok and self:Valid(token) then self:Error(name,err) end
        if self:Valid(token) then self:StopMovement() self.Job=nil self.JobThread=nil self.CurrentFeedFood=nil self.CurrentFeedPet=nil end
    end)
    return true
end

function A:MoveTo(position,token,radius)
    if not self:Valid(token) or not self:Dismount(token) then return false end
    local character,humanoid,root=self:Character()
    if not root then return false end
    self:StopMovement()
    humanoid:UnequipTools()
    local target=position+Vector3.new(0,math.max(3,humanoid.HipHeight+root.Size.Y/2),0)
    local collisions={}
    for _,part in ipairs(character:QueryDescendants("BasePart")) do collisions[part]=part.CanCollide end
    self.Flight={Root=root,Humanoid=humanoid,Collisions=collisions,PlatformStand=humanoid.PlatformStand,AutoRotate=humanoid.AutoRotate}
    humanoid.PlatformStand=true
    humanoid.AutoRotate=false
    local duration=math.max(0.1,(root.Position-target).Magnitude/math.clamp(self.Options.TweenSpeed,40,350))
    local tween=self.TweenService:Create(root,TweenInfo.new(duration,Enum.EasingStyle.Linear),{CFrame=CFrame.new(target)*root.CFrame.Rotation})
    self.FlightTween=tween
    self.FlightConnection=self.Run.Stepped:Connect(function()
        if root.Parent and humanoid.Health>0 then
            for part in pairs(collisions) do if part.Parent then part.CanCollide=false end end
            root.AssemblyLinearVelocity=Vector3.zero
            root.AssemblyAngularVelocity=Vector3.zero
        end
    end)
    tween:Play()
    local deadline=os.clock()+duration+3
    while self:Valid(token) and root.Parent and humanoid.Health>0 and os.clock()<deadline and tween.PlaybackState==Enum.PlaybackState.Playing do
        self.Status="Flying | "..self:Format((root.Position-target).Magnitude).." studs remaining"
        task.wait(0.05)
    end
    local completed=tween.PlaybackState==Enum.PlaybackState.Completed
    self:StopMovement()
    if not completed or not self:Valid(token) then return false end
    task.wait(0.25)
    local _,_,current=self:Character()
    if current~=root or (root.Position-target).Magnitude>math.max(radius or 9,12) then
        self.Status="The server rejected movement; waiting before retrying"
        return false
    end
    return true
end

function A:ReturnWithEggs(token)
    if self.EggDeliveryPaused then self.Status="Egg delivery paused. Collect again or enable Auto Collect to resume." return false end
    local plot=self:Plot()
    if not plot then self.Status="Waiting for your ranch" return false end
    local before,expected={},{}
    for _,tool in ipairs(self:EggTools()) do before[tool]=true end
    for _,egg in ipairs(self:Basket()) do
        local name=egg:GetAttribute("Egg")
        if name then expected[name]=(expected[name] or 0)+1 end
    end
    if not next(expected) then return false end
    local function delivered()
        if #self:Basket()>0 then return false end
        local received={}
        for _,tool in ipairs(self:EggTools()) do if not before[tool] then received[tool.Name]=(received[tool.Name] or 0)+1 end end
        for name,count in pairs(expected) do if (received[name] or 0)<count then return false end end
        return true
    end
    self:MoveTo(plot.Baseplate.Position+Vector3.new(0,3,0),token,12)
    if not self:Valid(token) then return false end
    if self:WaitFor(delivered,4,token) then self.Status="Eggs delivered to inventory" return true end
    self:SetOption("AutoCollect",false)
    self:SetOption("AutoPlace",false)
    self.Status="Delivery was not confirmed. Egg automation has stopped."
    return false
end

function A:Home(token)
    if not self:Valid(token) then return false end
    if #self:Basket()>0 then return self:ReturnWithEggs(token) end
    if self:OnPlot() then return true end
    local plot=self:Plot()
    return plot and self:MoveTo(plot.Baseplate.Position+Vector3.new(0,3,0),token,12) or false
end

function A:CollectEgg(egg,token)
    if not egg or not self:Valid(token) then return false end
    self.EggDeliveryPaused=false
    if #self:Basket()>=self:Capacity() then
        if not self:ReturnWithEggs(token) then return false end
    end
    if egg.Object.Parent~=self.ActiveEggs then self.Status="The selected egg is no longer available" return false end
    if not self:MoveTo(egg.Position,token,9) then self.FailedEggs[egg.ID]=os.clock()+30 return false end
    if not self:Valid(token) or egg.Object.Parent~=self.ActiveEggs then return false end
    local before=#self:Basket()
    self:Fire("EggPickup",egg.ID)
    if not self:WaitFor(function() return #self:Basket()>before end,3,token) then
        self.FailedEggs[egg.ID]=os.clock()+30
        self.Status="Pickup was not confirmed; egg skipped for 30 seconds"
        return false
    end
    self.Collected=self.Collected+1
    return self:ReturnWithEggs(token)
end

function A:PlaceBest(token)
    if not self:Home(token) or not self:Dismount(token) then return end
    local pets=self:PetList()
    local metric=self.Options.BestMetric
    table.sort(pets,function(a,b)
        local av,bv=metric=="Speed" and a.Speed or a.Income,metric=="Speed" and b.Speed or b.Income
        if av==bv then return a.Key<b.Key end
        return av>bv
    end)
    local capacity=tonumber(self.Player:GetAttribute("MaxPets")) or tonumber(self:Value("MaxPets",5)) or 5
    local desired={}
    for i=1,math.min(capacity,#pets) do desired[pets[i].Key]=true end
    for _,pet in ipairs(pets) do
        if not self:Valid(token) then return end
        if pet.Placed and not desired[pet.Key] then
            self:Fire("PickupPet",pet.Key)
            if not self:WaitFor(function() return self:Tool(nil,pet.Key) end,3,token) then self.Status="Pet pickup was not confirmed" return end
        end
    end
    local plot=self:Plot()
    for i=1,math.min(capacity,#pets) do
        if not self:Valid(token) then return end
        local pet=pets[i]
        local tool=self:Tool(nil,pet.Key)
        if tool then
            self:Equip(tool)
            task.wait(0.15)
            if not self:Valid(token) then return end
            local base=plot.Baseplate
            local cols=math.max(1,math.ceil(math.sqrt(capacity)))
            local spacing=math.min(9,(math.min(base.Size.X,base.Size.Z)-12)/cols)
            local pos=(base.CFrame*CFrame.new(((i-1)%cols-(cols-1)/2)*spacing,4,math.floor((i-1)/cols)*spacing)).Position
            self:Fire("PlacePet",pet.Key,pos)
            local confirmed=self:WaitFor(function()
                for _,p in ipairs(self:PetList()) do if p.Key==pet.Key and p.Placed then return true end end
                return false
            end,3,token)
            if not confirmed then self.Status="Pet placement was not confirmed" return end
        end
    end
    self.Status="Best pets placed by "..string.lower(metric)
end

function A:SetOption(key,value)
    self.Options[key]=value
    if value==true and (key=="AutoCollect" or key=="AutoPlace") then self.EggDeliveryPaused=false end
    if self.ControlRefresh then self:ControlRefresh() end
    if key=="AntiAFK" then self:SetAntiAFK(value) end
    if key=="EggESP" and not value then self:ClearESP() end
    if value==false and string.sub(key,1,4)=="Auto" and (key~="AutoFeed" or self.Job=="Auto feeding pet")
        and (key~="AutoSell" or self.Job=="Selling inventory pet")
        and (key~="AutoFavorites" or self.Job=="Adding pet to favorites") then self:CancelJob() end
    if key=="AutoSell" then self.SellStatus=value and "Waiting for inventory pets" or "Auto Sell stopped" end
    if key=="AutoFavorites" then self.SellStatus=value and "Auto Favorites enabled" or "Auto Favorites stopped" end
end

function A:StopAll()
    self:CancelJob()
    for _,key in ipairs({"AutoCollect","AutoPlace","AutoHatch","AutoBest","AutoIndex","AutoBuyFood","AutoFeed","AutoSell","AutoFavorites"}) do self:SetOption(key,false) end
    self.Status="Automation stopped"
end

function A:Tick()
    self:UpdateFavoriteRequests()
    if self.Job or not self:Character() then return end
    local o=self.Options
    if o.AutoFavorites and self:Ready("FavoritePets",0.5) then
        local pet=self:NextFavoritePet()
        if pet then self:StartJob("Adding pet to favorites",function(token) self:FavoriteInventoryPet(token,pet.Key) end) return end
    end
    if o.AutoIndex and self:Ready("Index",4) then
        local stage=self:Value("IndexRewardStage",0)
        local reward=self.Data.IndexRewards.StageAt(stage)
        if reward and self.Data.IndexRewards.DiscoveredCount(self:Value("OwnedPets",""))>=reward.Goal then
            self:StartJob("Claiming index reward",function(token) self:ClaimIndex(token) end) return
        end
    end
    if o.AutoHatch and self:Ready("HatchScan",2) then
        local eggs=self:EggTimers()
        if eggs[1] and eggs[1].Remaining<=0 then self:StartJob("Hatching ready eggs",function(token) self:HatchReady(token) end) return end
    end
    if not self.EggDeliveryPaused and (o.AutoCollect or o.AutoPlace) and #self:Basket()>0 and self:Ready("Deliver",2) then
        self:StartJob("Delivering eggs",function(token) self:ReturnWithEggs(token) end) return
    end
    if o.AutoPlace and (not self.EggDeliveryPaused or #self:Basket()==0) and #self:EggTools()>0 and #self:FreeNests()>0 and self:Ready("Place",3) then
        self:StartJob("Placing eggs",function(token) self:PlaceEggs(token) end) return
    end
    if o.AutoBest and self:Ready("Best",25) then self:StartJob("Placing best pets",function(token) self:PlaceBest(token) end) return end
    if o.AutoSell and self:Ready("SellPets",1) then
        local pet=self:InventorySellPets()[1]
        if pet then self:StartJob("Selling inventory pet",function(token) self:SellInventoryPet(token,pet.Key) end) return end
        self.SellStatus="Waiting for inventory pets"
    end
    if o.AutoFeed and self:Ready("FoodFeed",3) then
        local key=self:NextFoodPet()
        if key then
            self:StartJob("Auto feeding pet",function(token)
                self.LastAutoFedPet=key
                self:FeedSelectedPet(token,true,key)
            end)
            return
        end
    end
    if o.AutoBuyFood and self:Ready("FoodShop",0.5) then
        local name=self:NextFoodPurchase()
        if name then
            local amount=math.clamp(self:FoodStock(name) or 1,1,5)
            self:StartJob("Buying "..name,function(token) self:BuyFood(token,name,amount,true) end)
            return
        end
    end
    if o.AutoCollect and self:Ready("Collect",1) then
        for _,egg in ipairs(self:EggList("Collect")) do
            if os.clock()>=(self.FailedEggs[egg.ID] or 0) then self:StartJob("Collecting "..egg.Name,function(token) self:CollectEgg(egg,token) end) return end
        end
        self.Status="Waiting for eggs that match collection filters"
    end
end

function A:ClearESP()
    for id,marker in pairs(self.Markers) do
        for _,object in pairs(marker.Drawings) do pcall(function() object.Visible=false object:Remove() end) end
        self.Markers[id]=nil
    end
end

function A:UpdateESP()
    if not self.Options.EggESP then return end
    if not Drawing or type(Drawing.new)~="function" then
        self:SetOption("EggESP",false)
        self.Status="Drawing API is unavailable in this executor"
        return
    end
    local keep={}
    for i,egg in ipairs(self:EggList("ESP")) do
        if i>self.Options.ESPCount then break end
        keep[egg.ID]=true
        local marker=self.Markers[egg.ID]
        if not marker then
            marker={Drawings={}}
            self.Markers[egg.ID]=marker
            for key,class in pairs({Text="Text",Box="Square",Tracer="Line"}) do
                local d=Drawing.new(class)
                marker.Drawings[key]=d
                d.Visible=false
                d.Transparency=1
                if key=="Text" then
                    d.Center=true d.Outline=true d.OutlineColor=Color3.new(0,0,0) d.Font=2 d.ZIndex=3
                else d.Thickness=1 d.ZIndex=2 end
                if key=="Box" then d.Filled=false end
            end
        end
        marker.Egg=egg
        for _,d in pairs(marker.Drawings) do d.Color=self.RarityColors[egg.Rarity] or Color3.new(1,1,1) end
        marker.Drawings.Text.Size=self.Options.ESPSize
    end
    for id,marker in pairs(self.Markers) do
        if not keep[id] then
            for _,d in pairs(marker.Drawings) do pcall(function() d:Remove() end) end
            self.Markers[id]=nil
        end
    end
end

function A:RenderESP()
    local camera=workspace.CurrentCamera
    local _,_,root=self:Character()
    local o=self.Options
    for _,marker in pairs(self.Markers) do
        local egg,d=marker.Egg,marker.Drawings
        local visible=false
        if o.EggESP and camera and root and egg.Object.Parent==self.ActiveEggs then
            local distance=(root.Position-egg.Position).Magnitude
            local point,onScreen=camera:WorldToViewportPoint(egg.Position+Vector3.new(0,4,0))
            visible=onScreen and point.Z>0 and distance<=o.ESPDistance
            if visible and self.Panel and self.Panel.Visible then
                local inset=game:GetService("GuiService"):GetGuiInset()
                local position,size=self.Panel.AbsolutePosition+inset,self.Panel.AbsoluteSize
                if point.X>=position.X-95 and point.X<=position.X+size.X+95
                    and point.Y>=position.Y-110 and point.Y<=position.Y+size.Y then visible=false end
            end
            if visible then
                local lines={}
                if o.ESPName then lines[#lines+1]=egg.Name end
                if o.ESPRarity then lines[#lines+1]=egg.Rarity end
                if o.ESPShowDistance then lines[#lines+1]=string.format("%d studs",distance) end
                if o.ESPWeight then lines[#lines+1]=self:Format(egg.KG).." kg" end
                if o.ESPMutation then lines[#lines+1]="Mutation: "..egg.MutationLabel end
                if o.ESPLuck then lines[#lines+1]="Luck: "..self:Format(egg.Luck).."x" end
                d.Text.Text=table.concat(lines,"\n")
                d.Text.Position=Vector2.new(point.X,point.Y)
                local center=camera:WorldToViewportPoint(egg.Position+Vector3.new(0,1.5,0))
                local size=math.clamp(2600/math.max(point.Z,1),8,90)
                d.Box.Position=Vector2.new(center.X-size/2,center.Y-size/2)
                d.Box.Size=Vector2.new(size,size)
                d.Tracer.From=Vector2.new(camera.ViewportSize.X/2,camera.ViewportSize.Y-12)
                d.Tracer.To=Vector2.new(center.X,center.Y)
            end
        end
        d.Text.Visible=visible
        d.Box.Visible=visible and o.ESPBoxes
        d.Tracer.Visible=visible and o.ESPTracers
    end
end

function A:InitFood()
    self.Data.Foods=require(self.RS.GameData:WaitForChild("Foods",10))
    self.Data.Shop=require(self.RS.GameData:WaitForChild("Shop",10))
    self.FoodNames={}
    for name,definition in pairs(self.Data.Shop.Food) do
        if type(definition)=="table" and self.Data.Foods[name] then table.insert(self.FoodNames,name) end
    end
    table.sort(self.FoodNames,function(a,b) return self.Data.Shop.Food[a].Price<self.Data.Shop.Food[b].Price end)
    self.FoodBuyItems=self.FoodBuyItems or {Grass=true}
    self.FoodFeedItems=self.FoodFeedItems or {Grass=true}
    self.FoodFeedPets=self.FoodFeedPets or {}
    self.FoodBought=self.FoodBought or 0
    self.FoodFed=self.FoodFed or 0
    self.FoodStatus=self.FoodStatus or "Choose food and a pet"
end

function A:FoodAmount(tool)
    if not tool or not tool.Parent then return 0 end
    local data=tool:FindFirstChild("Data")
    local amount=data and data:FindFirstChild("Amount")
    if amount and amount:IsA("ValueBase") then return math.max(0,math.floor(tonumber(amount.Value) or 0)) end
    return 1
end

function A:FoodCount(name)
    local count=0
    for _,tool in ipairs(self:Tools()) do if tool.Name==name then count=count+self:FoodAmount(tool) end end
    return count
end

function A:FoodStock(name)
    local main=self.Player.PlayerGui:FindFirstChild("Main")
    local shop=main and main:FindFirstChild("Shop")
    local holders=shop and shop:FindFirstChild("Holders")
    local food=holders and holders:FindFirstChild("Food")
    local card=food and food:FindFirstChild(name)
    local stock=card and card:FindFirstChild("Stock",true)
    if stock and stock:IsA("TextLabel") then return tonumber(stock.Text:match("(%d+)")) end
    return nil
end

function A:CanBuyFood(name)
    local item=self.Data.Shop.Food[name]
    if not item or type(item.Price)~="number" then return false,"Choose an available food" end
    local stock=self:FoodStock(name)
    if stock==nil then return false,"Open the game's Food shop to load stock" end
    if stock<=0 then return false,name.." is out of stock" end
    if (tonumber(self:Value("Cash",0)) or 0)<item.Price then return false,"Not enough cash" end
    return true
end

function A:NextFoodPurchase()
    local reason,start="Select food in Food shop",0
    for i,name in ipairs(self.FoodNames) do if name==self.LastFoodPurchase then start=i break end end
    for step=1,#self.FoodNames do
        local name=self.FoodNames[(start+step-1)%#self.FoodNames+1]
        if self.FoodBuyItems[name] then
            local allowed,message=self:CanBuyFood(name)
            if allowed then return name end
            reason=message
        end
    end
    self.FoodStatus=reason
    return nil
end

function A:BuyFood(token,name,amount,automatic)
    amount=math.clamp(math.floor(amount or 1),1,100)
    local bought=0
    for _=1,amount do
        if not self:Valid(token) or not self.FoodBuyItems[name] or (automatic and not self.Options.AutoBuyFood) then return false end
        local allowed,reason=self:CanBuyFood(name)
        if not allowed then self.FoodStatus=reason break end
        local before=self:FoodCount(name)
        self.FoodStatus="Buying "..name
        self:Fire("BuyWithCash","Food",name)
        local confirmed=self:WaitFor(function() return self:FoodCount(name)>before end,3,token)
        if not confirmed then
            self.FoodStatus="Purchase was not confirmed; try again later"
            if automatic then self.Cooldowns.FoodShop=os.clock()+2 end
            break
        end
        self.FoodBought=self.FoodBought+1
        self.LastFoodPurchase=name
        bought=bought+1
        self.FoodStatus="Bought "..name.." x"..bought
        if bought<amount then task.wait(0.15) end
    end
    self.Status=self.FoodStatus
    return bought>0
end

function A:BuySelectedFoods(token)
    local selected,before=0,self.FoodBought
    for _,name in ipairs(self.FoodNames) do
        if not self:Valid(token) then return false end
        if self.FoodBuyItems[name] then selected=selected+1 self:BuyFood(token,name,1,false) end
    end
    if not self:Valid(token) then return false end
    local bought=self.FoodBought-before
    if selected==0 then self.FoodStatus="Select food in Food shop"
    elseif bought>0 then self.FoodStatus="Bought "..bought.." selected food portions" end
    self.Status=self.FoodStatus
    return bought>0
end

function A:FindFoodPet(key)
    for _,pet in ipairs(self:PetList()) do if pet.Key==key then return pet end end
    return nil
end

function A:CanFeedPet(key,name)
    local pet=self:FindFoodPet(key)
    if not pet then return false,"Select an owned pet first" end
    if pet.Age>=(self.Services.PetAging.MaxAge or 100) then return false,pet.Name.." is at maximum age" end
    if self:FoodCount(name)<=0 then return false,"No "..tostring(name).." in inventory" end
    return true
end

function A:NextFeedingFood()
    local start,selected=0,0
    for i,name in ipairs(self.FoodNames) do if name==self.LastFedFood then start=i break end end
    for step=1,#self.FoodNames do
        local name=self.FoodNames[(start+step-1)%#self.FoodNames+1]
        if self.FoodFeedItems[name] then
            selected=selected+1
            if self:FoodCount(name)>0 then return name end
        end
    end
    return nil,selected>0 and "No selected feeding food in inventory" or "Choose foods for feeding"
end

function A:FeedingFoodSelectionChanged()
    if (self.Job=="Feeding selected pets" or self.Job=="Auto feeding pet") and self.CurrentFeedFood and not self.FoodFeedItems[self.CurrentFeedFood] then self:CancelJob() end
    if not self.Job then self.FoodStatus="Feeding food selection updated" self.Status=self.FoodStatus end
    self:RefreshFoodUI()
end

function A:NextFoodPet()
    local candidates,selected={},0
    for _,pet in ipairs(self:PetList()) do
        if self.FoodFeedPets[pet.Key] then
            selected=selected+1
            if pet.Age<(self.Services.PetAging.MaxAge or 100) then candidates[#candidates+1]=pet end
        end
    end
    if selected==0 then self.FoodStatus="Select pets for feeding" return nil end
    if #candidates==0 then self.FoodStatus="Selected pets are at maximum age" return nil end
    table.sort(candidates,function(a,b) return a.Key<b.Key end)
    local chosen=candidates[1]
    for _,pet in ipairs(candidates) do
        if not self.LastAutoFedPet or pet.Key>self.LastAutoFedPet then chosen=pet break end
    end
    local name,message=self:NextFeedingFood()
    if not name then self.FoodStatus=message return nil end
    local allowed,reason=self:CanFeedPet(chosen.Key,name)
    if not allowed then self.FoodStatus=reason return nil end
    return chosen.Key
end

function A:FoodFeedFilterChanged()
    if (self.Job=="Feeding selected pets" or self.Job=="Auto feeding pet") and self.CurrentFeedPet and not self.FoodFeedPets[self.CurrentFeedPet] then self:CancelJob() end
    if not self.Job then self.FoodStatus="Pet selection updated" self.Status=self.FoodStatus end
    self:RefreshFoodUI()
end

function A:FeedSelectedPet(token,automatic,key)
    local function finish(success,message)
        self.CurrentFeedFood=nil
        self.CurrentFeedPet=nil
        if message then self.FoodStatus=message self.Status=message end
        return success
    end
    local name,message=self:NextFeedingFood()
    if not name then return finish(false,message) end
    local function active()
        return self:Valid(token) and self.FoodFeedItems[name]==true and self.FoodFeedPets[key]==true and (not automatic or self.Options.AutoFeed)
    end
    if not active() then return finish(false) end
    self.CurrentFeedPet=key
    self.CurrentFeedFood=name
    local allowed,reason=self:CanFeedPet(key,name)
    if not allowed then return finish(false,reason) end
    local pet=self:FindFoodPet(key)
    local food=self:Tool(name)
    if pet.Placed and pet.Object:IsA("Model") then
        local _,_,root=self:Character()
        if not root then return finish(false) end
        local position=pet.Object:GetPivot().Position
        if (root.Position-position).Magnitude>18 and not self:MoveTo(position,token,10) then return finish(false) end
    end
    self:Equip(food)
    task.wait(0.15)
    if not active() then return finish(false) end
    allowed,reason=self:CanFeedPet(key,name)
    if not allowed then return finish(false,reason) end
    local before=self:FoodAmount(food)
    if before<=0 then return finish(false,"Food is no longer available") end
    self:Fire("FeedPet",key,name)
    local consumed=self:WaitFor(function() return self:FoodAmount(food)<before end,3,token)
    if not self:Valid(token) then return finish(false) end
    if not consumed then return finish(false,"Feeding was not confirmed. Place the pet on your ranch and retry.") end
    self.FoodFed=self.FoodFed+1
    self.LastFedFood=name
    self.FoodStatus="Fed "..pet.Name.." | "..name
    self.Status=self.FoodStatus
    task.wait(0.35)
    return finish(true)
end

function A:ClampManualFeedCount(value)
    local count=tonumber(value) or tonumber(self.Options.ManualFeedCount) or 1
    if count~=count or count==math.huge or count==-math.huge then count=1 end
    return math.clamp(math.floor(count),1,1000)
end

function A:FeedSelectedPets(token,amount)
    amount=self:ClampManualFeedCount(amount)
    local selected,fed,fedPets,partial=0,0,0,false
    for _,pet in ipairs(self:PetList()) do
        if not self:Valid(token) then return false end
        if self.FoodFeedPets[pet.Key] then
            selected=selected+1
            local portions=0
            for _=1,amount do
                if not self:Valid(token) then return false end
                if not self.FoodFeedPets[pet.Key] or not self:FeedSelectedPet(token,false,pet.Key) then partial=true break end
                fed=fed+1
                portions=portions+1
            end
            if portions>0 then fedPets=fedPets+1 end
        end
    end
    if not self:Valid(token) then return false end
    if selected==0 then self.FoodStatus="Select pets for feeding"
    elseif fed>0 then self.FoodStatus="Fed "..fed.." portions to "..fedPets.." pets"..(partial and " (partial)" or "") end
    self.Status=self.FoodStatus
    return fed>0
end

A:InitFood()

function A:InitSell()
    self.SoldPets=self.SoldPets or 0
    self.FavoritedPets=self.FavoritedPets or 0
    self.FavoriteRequests=self.FavoriteRequests or {}
    self.FavoriteFilters=self.FavoriteFilters or {Types={},Rarities={}}
    self.FavoritePetNames={}
    for name,data in pairs(self.Data.Pets) do
        if type(data)=="table" and data.Rarity then
            self.FavoritePetNames[#self.FavoritePetNames+1]=name
            if self.FavoriteFilters.Types[name]==nil then self.FavoriteFilters.Types[name]=true end
        end
    end
    table.sort(self.FavoritePetNames)
    self.SellStatus=self.SellStatus or "Ready"
    self.SellDialogueRevision=self.SellDialogueRevision or 0
    local dialogue=self.RS:FindFirstChild("Dialogue")
    local modules=dialogue and dialogue:FindFirstChild("Modules")
    local module=modules and modules:FindFirstChild("DialogueModule")
    local remotes=dialogue and dialogue:FindFirstChild("Remotes")
    if not module or not remotes then return false end
    local ok,api=pcall(require,module)
    if not ok or type(api)~="table" or type(api.SelectOption)~="function" then return false end
    self.SellAPI=api
    if not self.SellDialogueConnected then
        for _,name in ipairs({"DialogueSend","DialogueUpdate"}) do
            local remote=remotes:FindFirstChild(name)
            if not remote then return false end
            self:Connect(remote.OnClientEvent,function(data)
                self.SellDialogue=type(data)=="table" and data or nil
                self.SellDialogueRevision=self.SellDialogueRevision+1
            end)
        end
        self.SellDialogueConnected=true
    end
    return true
end

function A:SellVendor()
    local stalls=workspace:FindFirstChild("Stalls")
    local stall=stalls and stalls:FindFirstChild("Sell")
    local npc=stall and stall:FindFirstChild("Richie")
    local root=npc and npc:FindFirstChild("HumanoidRootPart")
    local prompt=root and root:FindFirstChildOfClass("ProximityPrompt")
    return npc,root,prompt
end

function A:InventoryPets()
    local placed,seen,result={},{},{}
    for _,pet in ipairs(self:PetList()) do if pet.Placed then placed[pet.Key]=true end end
    local _,_,root=self:Character()
    local joint=root and root:FindFirstChild("PetMountJoint")
    local mounted=joint and joint.Part1 and joint.Part1.Parent
    local mountedKey=mounted and mounted:GetAttribute("PetKey")
    local backpack=self.Player:FindFirstChild("Backpack")
    local character=self.Player.Character
    for _,tool in ipairs(self:Tools()) do
        local key=tool:GetAttribute("PetKey")
        local name=tool:GetAttribute("PetName") or tool.Name
        local data=self.Data.Pets[name]
        if key and data and not seen[key] and not placed[key] and key~=mountedKey
            and (tool.Parent==backpack or tool.Parent==character) then
            seen[key]=true
            result[#result+1]={Key=key,Name=name,Rarity=data.Rarity,Tool=tool,Favorite=tool:GetAttribute("Favorited")==true}
        end
    end
    table.sort(result,function(a,b) if a.Name==b.Name then return a.Key<b.Key end return a.Name<b.Name end)
    return result
end

function A:MatchesFavorite(pet)
    local filters=self.FavoriteFilters
    return filters.Types[pet.Name]==true and filters.Rarities[pet.Rarity]==true
end

function A:InventorySellPets()
    local result={}
    for _,pet in ipairs(self:InventoryPets()) do
        if not pet.Favorite and not self.FavoriteRequests[pet.Key]
            and not (self.Options.AutoFavorites and self:MatchesFavorite(pet)) then
            result[#result+1]=pet
        end
    end
    return result
end

function A:UpdateFavoriteRequests()
    if not next(self.FavoriteRequests) then return end
    for _,pet in ipairs(self:PetList()) do
        if pet.Favorite and self.FavoriteRequests[pet.Key] then
            self.FavoriteRequests[pet.Key]=nil
            self.FavoritedPets=self.FavoritedPets+1
        end
    end
end

function A:NextFavoritePet()
    for _,pet in ipairs(self:InventoryPets()) do
        if not pet.Favorite and not self.FavoriteRequests[pet.Key] and self:MatchesFavorite(pet) then return pet end
    end
end

function A:FavoriteInventoryPet(token,key)
    if not self:Valid(token) or not self.Options.AutoFavorites or self.FavoriteRequests[key] then return false end
    local pet
    for _,candidate in ipairs(self:InventoryPets()) do if candidate.Key==key then pet=candidate break end end
    if not pet or pet.Favorite or not self:MatchesFavorite(pet) then return false end
    self.FavoriteRequests[key]=true
    local ok,sent=pcall(self.Fire,self,"FavoritePet",key)
    if not ok or not sent then
        self.FavoriteRequests[key]=nil
        self.SellStatus="Favorite request failed"
        return false
    end
    local confirmed=self:WaitFor(function()
        for _,owned in ipairs(self:PetList()) do if owned.Key==key and owned.Favorite then return true end end
        return false
    end,3,token)
    self:UpdateFavoriteRequests()
    if not self:Valid(token) then return false end
    self.SellStatus=confirmed and ("Added "..pet.Name.." to favorites") or "Waiting for favorite confirmation"
    return confirmed
end

function A:FindSellPet(key)
    for _,pet in ipairs(self:InventorySellPets()) do if pet.Key==key then return pet end end
    return nil
end

function A:SellOptionReady(npc)
    local data=self.SellDialogue
    if not data or data.Model~=npc then return false end
    local offered=false
    for _,option in ipairs(data.Options or {}) do if option.Text=="I would like to sell this" then offered=true break end end
    if not offered then return false end
    local options=self.Player.PlayerGui:FindFirstChild("Options")
    local button=options and options:FindFirstChild("I would like to sell this")
    return button and button:IsA("GuiButton") and button.Visible and button.Active and options.Enabled
end

function A:OpenSellDialogue(npc,prompt,token,manual)
    if self:SellOptionReady(npc) then return true end
    if type(fireproximityprompt)~="function" then return false end
    if not self:WaitFor(function() return prompt.Parent and prompt.Enabled end,4,token) then return false end
    if not self:Valid(token) or (not manual and not self.Options.AutoSell) then return false end
    local revision=self.SellDialogueRevision
    local ok=pcall(fireproximityprompt,prompt)
    if not ok then return false end
    return self:WaitFor(function()
        return self.SellDialogueRevision>revision and self:SellOptionReady(npc)
    end,5,token)
end

function A:StopSelling(message)
    self.Options.AutoSell=false
    self.SellStatus=message
    self.Status=message
    if self.Job=="Selling inventory pet" or self.Job=="Selling all inventory pets" then self:CancelJob() end
    if self.ControlRefresh then self:ControlRefresh() end
end

function A:SellInventoryPet(token,key,manual)
    local function active() return self:Valid(token) and (manual or self.Options.AutoSell) end
    if not active() then return false end
    local pet=self:FindSellPet(key)
    if not pet then return false end
    local npc,vendorRoot,prompt=self:SellVendor()
    if not npc or not vendorRoot or not prompt or not self.SellAPI then
        self:StopSelling("Sell vendor is unavailable")
        return false
    end
    local _,_,root=self:Character()
    if not root then return false end
    self.SellStatus="Selling "..pet.Name
    local range=math.max(5,math.min(18,prompt.MaxActivationDistance-3))
    if (root.Position-vendorRoot.Position).Magnitude>range then
        self.SellStatus="Flying to Richie"
        if not self:MoveTo(vendorRoot.Position+vendorRoot.CFrame.LookVector*8,token,12) then return false end
    end
    if not active() then return false end
    pet=self:FindSellPet(key)
    if not pet then return false end
    if not self:Equip(pet.Tool) then return false end
    task.wait(0.2)
    if not active() then return false end
    if not self:OpenSellDialogue(npc,prompt,token,manual) then
        if active() then self:StopSelling("Could not open Richie's sell dialogue") end
        return false
    end
    if not active() then return false end
    local current=self:FindSellPet(key)
    local character,_,currentRoot=self:Character()
    if not current or current.Tool~=pet.Tool or pet.Tool.Parent~=character then return false end
    if not currentRoot or (currentRoot.Position-vendorRoot.Position).Magnitude>prompt.MaxActivationDistance then return false end
    if not self:SellOptionReady(npc) then return false end
    self.SellStatus="Selling "..pet.Name
    local requested=pcall(self.SellAPI.SelectOption,"I would like to sell this")
    if not requested then self:StopSelling("Sale request failed. Selling stopped.") return false end
    local confirmed=self:WaitFor(function()
        if pet.Tool.Parent or self:Tool(nil,key) then return false end
        for _,owned in ipairs(self:PetList()) do if owned.Key==key then return false end end
        return true
    end,5,token)
    if not active() then return false end
    if not confirmed then self:StopSelling("Sale was not confirmed. Selling stopped.") return false end
    self.SoldPets=self.SoldPets+1
    self.SellStatus="Sold "..pet.Name
    self.Status=self.SellStatus
    return true
end

function A:SellAllInventoryPets(token,pets)
    pets=pets or self:InventorySellPets()
    if #pets==0 then self.SellStatus="No inventory pets available to sell" return end
    local sold=0
    for _,pet in ipairs(pets) do
        if not self:Valid(token) then return end
        if self:FindSellPet(pet.Key) then
            if not self:SellInventoryPet(token,pet.Key,true) then
                if not self:Valid(token) or self:FindSellPet(pet.Key) then return end
            else
                sold=sold+1
                task.wait(0.2)
            end
        end
    end
    if self:Valid(token) then
        self.SellStatus="Sell All complete: "..sold.." sold"
        self.Status=self.SellStatus
    end
end

A:InitSell()

function A:MakePreview()
    if self.Viewport then return end
    self.Viewport=Instance.new("ViewportFrame")
    self.Viewport.Name="SelectedEggPreview"
    self.Viewport.Size=UDim2.new(1,0,0,self.PreviewHeight or 140)
    self.Viewport.BackgroundColor3=Color3.fromRGB(18,21,27)
    self.Viewport.BorderSizePixel=0
    self.Viewport.Ambient=Color3.fromRGB(195,195,195)
    self.Viewport.LightColor=Color3.fromRGB(255,245,223)
    self.Viewport.LightDirection=Vector3.new(-1,-1,-1)
    self.PreviewCamera=Instance.new("Camera")
    self.PreviewCamera.FieldOfView=35
    self.PreviewCamera.Parent=self.Viewport
    self.Viewport.CurrentCamera=self.PreviewCamera
    self.PreviewWorld=Instance.new("WorldModel")
    self.PreviewWorld.Parent=self.Viewport
    self:Connect(self.Viewport.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            self.PreviewDrag=input
            self.PreviewLastX=input.Position.X
        end
    end)
    self:Connect(self.UIS.InputChanged,function(input)
        if self.PreviewDrag and (input==self.PreviewDrag or input.UserInputType==Enum.UserInputType.MouseMovement) then
            self.PreviewAngle=self.PreviewAngle+(input.Position.X-self.PreviewLastX)*0.015
            self.PreviewLastX=input.Position.X
        end
    end)
    self:Connect(self.UIS.InputEnded,function(input)
        if input==self.PreviewDrag or input.UserInputType==Enum.UserInputType.MouseButton1 then self.PreviewDrag=nil end
    end)
end

function A:Preview(egg)
    self:MakePreview()
    local signature=egg and egg.ID..":"..egg.MutationLabel or ""
    if self.PreviewSignature==signature then return end
    self.PreviewSignature=signature
    self.PreviewWorld:ClearAllChildren()
    self.PreviewModel=nil
    if not egg then return end
    local source
    local rendered=workspace:FindFirstChild("RenderedEggs")
    if rendered then
        local nearest=math.huge
        for _,model in ipairs(rendered:GetChildren()) do
            if model.Name==egg.Name and model:IsA("Model") then
                local d=(model:GetPivot().Position-egg.Position).Magnitude
                if d<nearest and d<30 then nearest=d source=model end
            end
        end
    end
    source=source or self.RS.Assets.Eggs:FindFirstChild(egg.Name)
    if not source then self.PreviewMissing=true return end
    local clone=source:Clone()
    local model=Instance.new("Model")
    model.Name="EggPreview"
    for _,part in ipairs(clone:GetChildren()) do part.Parent=model end
    clone:Destroy()
    for _,object in ipairs(model:QueryDescendants("LuaSourceContainer, ProximityPrompt, Highlight, BillboardGui, SurfaceGui, Sound, JointInstance, Constraint")) do object:Destroy() end
    for _,part in ipairs(model:QueryDescendants("BasePart")) do
        part.Anchored=true part.CanCollide=false part.CanTouch=false part.CanQuery=false
        if part.Name=="EggBase" then part.Transparency=1 end
    end
    model.Parent=self.PreviewWorld
    local cf,size=model:GetBoundingBox()
    model:PivotTo(CFrame.new(-cf.Position)*model:GetPivot())
    self.PreviewModel=model
    self.PreviewRadius=math.max(size.X,size.Y,size.Z)*0.5
    self.PreviewMissing=false
end

function A:RenderPreview(dt)
    if not self.PreviewModel or not self.Panel.Visible or self.Collapsed or self.Page~="Eggs" then return end
    if self.Options.RotatePreview and not self.PreviewDrag then self.PreviewAngle=self.PreviewAngle+dt*0.45 end
    local aspect=self.Viewport.AbsoluteSize.X/math.max(self.Viewport.AbsoluteSize.Y,1)
    local radius=self.PreviewRadius or 2
    local distance=radius/math.sin(math.rad(self.PreviewCamera.FieldOfView/2))*1.3/math.min(aspect,1)
    local pos=Vector3.new(math.sin(self.PreviewAngle)*distance,distance*0.16,math.cos(self.PreviewAngle)*distance)
    self.PreviewCamera.CFrame=CFrame.lookAt(pos,Vector3.zero)
end

function A:Refresh()
    self.Cache.Eggs=self:EggList()
    self.Cache.Timers=self:EggTimers()
    self.Cache.Tools=#self:EggTools()
    self.Cache.Basket=#self:Basket()
    self.Cache.Nests=#self:FreeNests()
    self.Cache.Pets=self:PetList()
    self.Cache.Stage=self:Value("IndexRewardStage",0)
    self.Cache.Discovered=self.Data.IndexRewards.DiscoveredCount(self:Value("OwnedPets",""))
    self.Cache.Reward=self.Data.IndexRewards.StageAt(self.Cache.Stage)
end

A.Colors={Surface=Color3.fromRGB(16,16,18),Text=Color3.fromRGB(240,240,240),
    Title=Color3.fromRGB(41,74,122),Border=Color3.fromRGB(79,79,89),
    Row=Color3.fromRGB(29,29,32),RowAlternate=Color3.fromRGB(23,23,26),
    Muted=Color3.fromRGB(164,164,173),Accent=Color3.fromRGB(37,76,124),
    Button=Color3.fromRGB(49,49,55),Good=Color3.fromRGB(139,183,232)}
A.Controls={}
A.Pages={}
A.PageNames={"Farm","Collect filters","Eggs","ESP","ESP Filters","Pets","Sell","Food","Settings"}
A.Page="Farm"
A.PreviewHeight=140
A.RowHeight=A.UIS.TouchEnabled and 44 or 30
A.TitleHeight=A.UIS.TouchEnabled and 44 or 30
A.UpdateLabels={}
A.FilterButtons={}
A.Options.MenuKey=Enum.KeyCode.RightControl

function A:RefreshKeybind()
    if not self.KeybindButton then return end
    local name=self.Options.MenuKey.Name:gsub("(%l)(%u)","%1 %2"):gsub("Control","Ctrl")
    self.KeybindButton.Text=self.BindingKey and "Press a key (Esc cancels)" or "Menu key: "..name
    self.KeybindButton.BackgroundColor3=self.BindingKey and self.Colors.Accent or self.Colors.Row
end

function A:CancelKeybind()
    self.BindingKey=false
    self:RefreshKeybind()
end

function A:SetMenuVisible(visible)
    self:CancelKeybind()
    self.Panel.Visible=visible
    self:ClosePopup()
    self:RefreshUI()
end

function A:IsMobileDevice()
    local ok,platform=pcall(function() return self.UIS:GetPlatform() end)
    if ok and platform~=Enum.Platform.None then return platform==Enum.Platform.Android or platform==Enum.Platform.IOS end
    return self.UIS.TouchEnabled and not self.UIS.KeyboardEnabled
end

function A:RefreshMenuButtons()
    local mobile=self.MobileMenu and self.MobileMenu.Parent~=nil
    if self.Menu then self.Menu.Visible=not mobile and not self.Panel.Visible end
    if mobile then
        self.MobileMenu.Visible=true
        self.MobileMenu.Text=self.Panel.Visible and "Hide UI" or "Show UI"
        self.MobileMenu.BackgroundColor3=self.Panel.Visible and self.Colors.Title or self.Colors.Accent
    end
end

function A:ClampMobileMenu(pos)
    if not self.MobileMenu then return end
    local area,size=self.Bounds.AbsoluteSize,self.MobileMenu.AbsoluteSize
    if area.X<=0 or area.Y<=0 then return end
    self.MobileMenu.Position=UDim2.fromOffset(math.clamp(pos.X,8,math.max(8,area.X-size.X-8)),
        math.clamp(pos.Y,8,math.max(8,area.Y-size.Y-8)))
end

function A:LayoutMobileMenu()
    if not self.MobileMenu then return end
    self:EndMobileMenuDrag()
    local pos=self.MobileMenuPositioned and Vector2.new(self.MobileMenu.Position.X.Offset,self.MobileMenu.Position.Y.Offset)
        or Vector2.new(self.Bounds.AbsoluteSize.X-80,12)
    self:ClampMobileMenu(pos)
    self.MobileMenuPositioned=true
end

function A:BeginMobileMenuDrag(input)
    if not self.MobileMenu or self.MobileMenuDrag then return end
    if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    self.MobileMenuSkipTap=false
    self.MobileMenuDrag={Input=input,Start=Vector2.new(input.Position.X,input.Position.Y),
        Position=Vector2.new(self.MobileMenu.Position.X.Offset,self.MobileMenu.Position.Y.Offset),Moved=false}
end

function A:MoveMobileMenuDrag(input)
    local drag=self.MobileMenuDrag
    if not drag then return end
    if input~=drag.Input and not (drag.Input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then return end
    local delta=Vector2.new(input.Position.X,input.Position.Y)-drag.Start
    if delta.Magnitude>=8 then drag.Moved=true self.MobileMenuSkipTap=true end
    if drag.Moved then self:ClampMobileMenu(drag.Position+delta) end
end

function A:EndMobileMenuDrag(input)
    local drag=self.MobileMenuDrag
    if not drag then return end
    if input and input~=drag.Input and not (drag.Input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1) then return end
    if not input or drag.Moved then self.MobileMenuSkipTap=true end
    self.MobileMenuDrag=nil
end

function A:ActivateMobileMenu()
    if not self.Alive or self.MobileMenuSkipTap then return end
    self:SetMenuVisible(not self.Panel.Visible)
end

function A:BuildMobileMenu()
    if self.MobileMenu or not self:IsMobileDevice() then return end
    self.MobileMenu=self:Button(self.Bounds,"Hide UI",function() self:ActivateMobileMenu() end,self.Colors.Title)
    self.MobileMenu.Name="MobileMenuToggle"
    self.MobileMenu.Size=UDim2.fromOffset(72,48)
    self.MobileMenu.TextSize=13
    self.MobileMenu.ZIndex=30
    self:Make("UICorner",self.MobileMenu,{CornerRadius=UDim.new(0,8)})
    self:Make("UIStroke",self.MobileMenu,{Color=self.Colors.Border,Thickness=1})
    self:Connect(self.MobileMenu.InputBegan,function(input) self:BeginMobileMenuDrag(input) end)
    self:Connect(self.UIS.InputChanged,function(input) self:MoveMobileMenuDrag(input) end)
    self:Connect(self.UIS.InputEnded,function(input) self:EndMobileMenuDrag(input) end)
    self:Connect(self.UIS.WindowFocusReleased,function() self:EndMobileMenuDrag() end)
    self:LayoutMobileMenu()
    self:RefreshMenuButtons()
end

function A:HandleMenuInput(input,processed)
    if not self.Alive or input.UserInputType~=Enum.UserInputType.Keyboard then return end
    if self.UIS:GetFocusedTextBox() then self:CancelKeybind() return end
    if self.BindingKey then
        if input.KeyCode==Enum.KeyCode.Escape then self:CancelKeybind()
        elseif input.KeyCode~=Enum.KeyCode.Unknown then
            self.Options.MenuKey=input.KeyCode
            self:CancelKeybind()
        end
        return
    end
    if not processed and input.KeyCode==self.Options.MenuKey then self:SetMenuVisible(not self.Panel.Visible) end
end

function A:Make(class,parent,props)
    local object=Instance.new(class)
    for k,v in pairs(props) do object[k]=v end
    object.Parent=parent
    return object
end

function A:Text(parent,text,height)
    return self:Make("TextLabel",parent,{Name="Label",Size=UDim2.new(1,0,0,height or 22),
        BackgroundTransparency=1,Text=text,TextSize=14,Font=Enum.Font.Code,
        TextColor3=self.Colors.Text,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})
end

function A:Button(parent,text,callback,color)
    local button=self:Make("TextButton",parent,{Name=text:gsub("[^%w]",""),Text=text,
        Size=UDim2.new(1,0,0,self.RowHeight),BackgroundColor3=color or self.Colors.Button,
        BorderSizePixel=0,TextColor3=self.Colors.Text,Font=Enum.Font.Code,TextSize=14,
        AutoButtonColor=true,TextWrapped=true})
    self:Connect(button.Activated,callback)
    return button
end

function A:LoadTelegramText()
    if not self.Alive or self.TelegramLoading then return end
    self.TelegramLoading=true
    if self.TelegramButton then self.TelegramButton.Text="Loading Telegram..." end
    local thread=task.defer(function()
        local ok,body=pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram",true)
        end)
        if not self.Alive then return end
        self.TelegramLoading=false
        local content=ok and type(body)=="string" and body:match("^%s*(.-)%s*$") or nil
        if content and content~="" then
            self.TelegramText=content
            if self.TelegramButton and self.TelegramButton.Parent then self.TelegramButton.Text=content end
        else
            self.TelegramText=nil
            self.Status="Could not load Telegram text. Click to retry."
            if self.TelegramButton and self.TelegramButton.Parent then self.TelegramButton.Text="Retry loading Telegram" end
        end
    end)
    table.insert(self.Threads,thread)
end

function A:CopyTelegramText()
    if not self.Alive then return false end
    if not self.TelegramText then self:LoadTelegramText() return false end
    local copy=type(setclipboard)=="function" and setclipboard or type(toclipboard)=="function" and toclipboard
    if not copy then self.Status="Clipboard is unavailable in this executor" return false end
    local ok=pcall(copy,self.TelegramText)
    self.Status=ok and "Copied to clipboard" or "Could not copy to clipboard"
    return ok
end

function A:BuildTelegramButton(parent)
    if self.TelegramButton and self.TelegramButton.Parent then return end
    self.TelegramButton=self:Button(parent,"Loading Telegram...",function() self:CopyTelegramText() end,self.Colors.Accent)
    self.TelegramButton.Name="TelegramLink"
    self.TelegramButton.AutomaticSize=Enum.AutomaticSize.Y
    self:Make("UIPadding",self.TelegramButton,{PaddingLeft=UDim.new(0,7),PaddingRight=UDim.new(0,7),
        PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,6)})
    self:LoadTelegramText()
end

function A:Section(parent,text)
    local label=self:Text(parent,text,26)
    label.TextColor3=self.Colors.Good
    return label
end

function A:Toggle(parent,key,label)
    local button=self:Button(parent,"",function() self:SetOption(key,not self.Options[key]) end)
    button.Name=key
    button.TextXAlignment=Enum.TextXAlignment.Left
    self:Make("UIPadding",button,{PaddingLeft=UDim.new(0,7),PaddingRight=UDim.new(0,7)})
    self.Controls[key]={Button=button,Label=label,Toggle=true}
end

function A:NumberInput(parent,key,label,step,minimum,maximum,source,integer)
    source=source or self.Options
    local group=self:Make("Frame",parent,{Name=key,Size=UDim2.new(1,0,0,22+self.RowHeight),BackgroundTransparency=1})
    self:Text(group,label,20)
    local input=self:Make("TextBox",group,{Name="Value",Position=UDim2.fromOffset(self.RowHeight+4,22),
        Size=UDim2.new(1,-self.RowHeight*2-8,0,self.RowHeight),BackgroundColor3=self.Colors.Row,
        BorderSizePixel=0,Text=tostring(source[key]),ClearTextOnFocus=false,TextColor3=self.Colors.Text,
        Font=Enum.Font.Code,TextSize=14})
    local function set(value)
        value=tonumber(value)
        if not value or value~=value then input.Text=tostring(source[key]) return end
        value=math.clamp(value,minimum,maximum)
        if integer then value=math.floor(value) end
        source[key]=value
        input.Text=tostring(value)
    end
    local minus=self:Button(group,"-",function() set(source[key]-step) end)
    minus.Position=UDim2.fromOffset(0,22)
    minus.Size=UDim2.fromOffset(self.RowHeight,self.RowHeight)
    local plus=self:Button(group,"+",function() set(source[key]+step) end)
    plus.AnchorPoint=Vector2.new(1,0)
    plus.Position=UDim2.new(1,0,0,22)
    plus.Size=UDim2.fromOffset(self.RowHeight,self.RowHeight)
    self:Connect(input.FocusLost,function() set(input.Text) end)
    return input
end

function A:ClosePopup()
    if self.Popup then self.Popup:Destroy() self.Popup=nil end
    self.PopupAnchor=nil
end

function A:OpenPopup(anchor,title,items,selected,multi,onChange,searchable)
    self:ClosePopup()
    self.PopupAnchor=anchor
    local layer=self:Make("Frame",self.Bounds,{Name="Dropdown",Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,ZIndex=20})
    self.Popup=layer
    local backdrop=self:Make("TextButton",layer,{Name="Dismiss",Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,Text="",AutoButtonColor=false,ZIndex=1})
    backdrop.Activated:Connect(function() self:ClosePopup() end)
    local area=self.Bounds.AbsoluteSize
    local width=math.min(math.max(anchor.AbsoluteSize.X,280),area.X-16)
    local height=math.min(330,math.max(140,area.Y-24))
    local pos=anchor.AbsolutePosition-self.Bounds.AbsolutePosition
    local x=math.clamp(pos.X,8,math.max(8,area.X-width-8))
    local y=pos.Y+anchor.AbsoluteSize.Y+4
    if y+height>area.Y-8 then y=math.max(8,pos.Y-height-4) end
    y=math.clamp(y,8,math.max(8,area.Y-height-8))
    local box=self:Make("Frame",layer,{Name="Options",Position=UDim2.fromOffset(x,y),
        Size=UDim2.fromOffset(width,height),BackgroundColor3=self.Colors.Surface,BorderSizePixel=0,ZIndex=2})
    self:Make("UIStroke",box,{Color=self.Colors.Border,Thickness=1})
    local header=self:Make("TextLabel",box,{Name="Title",Size=UDim2.new(1,0,0,self.RowHeight),
        Text=title,TextSize=14,Font=Enum.Font.Code,TextColor3=self.Colors.Text,BackgroundColor3=self.Colors.Title,BorderSizePixel=0})
    local top=self.RowHeight+5
    local search
    if searchable then
        search=self:Make("TextBox",box,{Name="Search",Position=UDim2.fromOffset(6,top),
            Size=UDim2.new(1,-12,0,self.RowHeight),Text="",PlaceholderText="Search...",ClearTextOnFocus=false,
            Font=Enum.Font.Code,TextSize=14,TextColor3=self.Colors.Text,PlaceholderColor3=self.Colors.Muted,
            BackgroundColor3=self.Colors.Row,BorderSizePixel=0})
        top=top+self.RowHeight+5
    end
    local list=self:Make("ScrollingFrame",box,{Name="List",Position=UDim2.fromOffset(6,top),
        Size=UDim2.new(1,-12,1,-top-self.RowHeight-10),BackgroundTransparency=1,BorderSizePixel=0,
        CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,
        ScrollingDirection=Enum.ScrollingDirection.Y,ScrollBarThickness=3,ScrollBarImageColor3=self.Colors.Border})
    self:Make("UIListLayout",list,{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder})
    if #items==0 then self:Text(list,"No matches",self.RowHeight).TextColor3=self.Colors.Muted end
    local rows={}
    for index,item in ipairs(items) do
        local id,label=type(item)=="table" and item.ID or item,type(item)=="table" and item.Label or item
        local row=self:Make("TextButton",list,{Name="Option"..index,Size=UDim2.new(1,-4,0,self.RowHeight),
            Text="",TextSize=14,Font=Enum.Font.Code,TextColor3=self.Colors.Text,
            TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,
            BackgroundColor3=self.Colors.Row,BorderSizePixel=0,AutoButtonColor=true,LayoutOrder=index})
        self:Make("UIPadding",row,{PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6)})
        local function paint()
            local enabled=multi and selected[id]==true or not multi and selected==id
            row.Text=(enabled and "[x] " or "[ ] ")..label
            row.TextColor3=(type(item)=="table" and item.Color) or self.Colors.Text
            row.BackgroundColor3=enabled and self.Colors.Accent or self.Colors.Row
        end
        paint()
        row.Activated:Connect(function()
            if not self.Alive then return end
            if multi then selected[id]=not selected[id] onChange(id,selected[id]) paint()
            else onChange(id) self:ClosePopup() end
        end)
        rows[#rows+1]={Row=row,ID=id,Label=string.lower(label),Paint=paint}
    end
    if search then search:GetPropertyChangedSignal("Text"):Connect(function()
        local query=string.lower(search.Text)
        for _,r in ipairs(rows) do r.Row.Visible=string.find(r.Label,query,1,true)~=nil end
        list.CanvasPosition=Vector2.zero
    end) end
    local function footer(text,index,count,callback)
        local button=self:Make("TextButton",box,{Name=text,Position=UDim2.new((index-1)/count,6,1,-self.RowHeight-5),
            Size=UDim2.new(1/count,-12,0,self.RowHeight),Text=text,Font=Enum.Font.Code,TextSize=14,
            TextColor3=self.Colors.Text,BackgroundColor3=self.Colors.Button,BorderSizePixel=0})
        button.Activated:Connect(callback)
    end
    if multi then
        for index,entry in ipairs({{"All",true},{"None",false}}) do
            footer(entry[1],index,3,function()
                for _,r in ipairs(rows) do selected[r.ID]=entry[2] onChange(r.ID,entry[2]) r.Paint() end
            end)
        end
        footer("Done",3,3,function() self:ClosePopup() end)
    else footer("Close",1,1,function() self:ClosePopup() end) end
end

function A:Choice(parent,key,label,values)
    self:Text(parent,label,20)
    local button
    button=self:Button(parent,"",function()
        self:OpenPopup(button,label,values,self.Options[key],false,function(value)
            self:SetOption(key,value)
        end,false)
    end,self.Colors.Row)
    self.Controls[key]={Button=button,Choice=true}
end

function A:FilterPanel(parent,kind)
    local f=self.Filters[kind]
    self:Section(parent,kind=="ESP" and "ESP Filters" or kind=="Eggs" and "Egg list filters" or "Collection filters")
    local function changed()
        if kind=="Eggs" then self:RefreshUI() else self:ControlRefresh() end
    end
    for _,entry in ipairs({{"Rarities",self.RarityNames},{"Types",self.EggNames},{"Mutations",self.MutationNames}}) do
        local group,names=entry[1],entry[2]
        local button
        button=self:Button(parent,"",function()
            self:OpenPopup(button,group,names,f[group],true,changed,group=="Types")
        end,self.Colors.Row)
        button.Name=kind..group.."Filter"
        self.FilterButtons[#self.FilterButtons+1]={Button=button,Group=group,Names=names,Filter=f}
    end
    local mutated=self:Button(parent,"",function() f.MutatedOnly=not f.MutatedOnly changed() end)
    self.FilterButtons[#self.FilterButtons+1]={Button=mutated,Mutated=true,Filter=f}
    self:Text(parent,"Search egg names",20)
    local search=self:Make("TextBox",parent,{Name=kind.."Search",Size=UDim2.new(1,0,0,self.RowHeight),
        BackgroundColor3=self.Colors.Row,BorderSizePixel=0,Text="",PlaceholderText="All egg names",
        ClearTextOnFocus=false,TextSize=14,Font=Enum.Font.Code,TextColor3=self.Colors.Text,PlaceholderColor3=self.Colors.Muted})
    self:Connect(search:GetPropertyChangedSignal("Text"),function() f.Search=search.Text end)
    self:NumberInput(parent,"MinLuck","Minimum luck",10,0,1e15,f)
    self:NumberInput(parent,"MinWeight","Minimum weight (kg)",1,0,1e9,f)
    if kind=="Eggs" then self:NumberInput(parent,"MaxDistance","Maximum distance (studs)",100,0,100000,f) end
end

function A:BuildEggFilters()
    if self.EggFiltersToggle then return end
    local parent=self.Pages.Eggs
    self.EggFiltersToggle=self:Button(parent,"Filters >",function()
        self:ClosePopup()
        self.EggFiltersBody.Visible=not self.EggFiltersBody.Visible
        self:RefreshUI()
    end,self.Colors.Row)
    self.EggFiltersToggle.Name="EggFiltersToggle"
    self.EggFiltersBody=self:Make("Frame",parent,{Name="EggFilters",Size=UDim2.new(1,0,0,0),
        AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Visible=false})
    self:Make("UIListLayout",self.EggFiltersBody,{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder})
    self:FilterPanel(self.EggFiltersBody,"Eggs")
    local index=0
    for _,child in ipairs(self.EggFiltersBody:GetChildren()) do
        if child:IsA("GuiObject") then index=index+1 child.LayoutOrder=index end
    end
end

function A:OpenEggPicker()
    local rows={}
    for _,egg in ipairs(self:EggList("Eggs")) do rows[#rows+1]={ID=egg.ID,
        Label=egg.Name.." | "..egg.Rarity.." | "..egg.ID:sub(1,5),Color=self.RarityColors[egg.Rarity]} end
    self:OpenPopup(self.EggPicker,"Map eggs ("..#rows..")",rows,self.Options.SelectedEgg,false,
        function(id) self.Options.SelectedEgg=id self:RefreshUI() end,true)
end

function A:CollectSelectedEgg(token)
    for _,egg in ipairs(self:EggList("Eggs")) do
        if egg.ID==self.Options.SelectedEgg then self:CollectEgg(egg,token) return end
    end
    self.Status="Select an available egg that matches your filters"
end

function A:CreatePage(name)
    if self.Pages[name] then return self.Pages[name] end
    local page=self:Make("ScrollingFrame",self.Container,{Name=name:gsub(" ",""),Position=UDim2.fromOffset(0,self.RowHeight+6),
        Size=UDim2.new(1,0,1,-self.RowHeight-56),BackgroundTransparency=1,BorderSizePixel=0,
        CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,
        ScrollingDirection=Enum.ScrollingDirection.Y,ScrollBarThickness=3,ScrollBarImageColor3=self.Colors.Border,Visible=name==self.Page})
    self:Make("UIListLayout",page,{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder})
    self:Make("UIPadding",page,{PaddingRight=UDim.new(0,5),PaddingBottom=UDim.new(0,5)})
    self.Pages[name]=page
    return page
end

function A:OpenPagePicker()
    self:OpenPopup(self.Navigation,"Pages",self.PageNames,self.Page,false,function(v) self:SwitchPage(v) end,false)
end

function A:OpenFoodFeedPicker()
    local rows={}
    for _,pet in ipairs(self:PetList()) do
        rows[#rows+1]={ID=pet.Key,Label=pet.Name.." | age "..pet.Age.." | "..pet.Key:sub(1,5),Color=self.RarityColors[pet.Rarity]}
    end
    self:OpenPopup(self.FoodFeedPetsButton,"Select Pet",rows,self.FoodFeedPets,true,
        function() self:FoodFeedFilterChanged() end,true)
end

function A:OpenFeedingFoodPicker()
    local rows={}
    for _,name in ipairs(self.FoodNames) do
        rows[#rows+1]={ID=name,Label=name.." | owned "..self:FoodCount(name).." | XP "..self:Format(self.Data.Foods[name].XP),
            Color=self.RarityColors[self.Data.Shop.Food[name].Rarity]}
    end
    self:OpenPopup(self.FoodFeedItemsButton,"Feeding foods",rows,self.FoodFeedItems,true,
        function() self:FeedingFoodSelectionChanged() end,true)
end

function A:OpenShoppingFoodPicker()
    local rows={}
    for _,name in ipairs(self.FoodNames) do
        local data=self.Data.Shop.Food[name]
        rows[#rows+1]={ID=name,Label=name.." | $"..self:Format(data.Price).." | stock "..tostring(self:FoodStock(name) or "?"),Color=self.RarityColors[data.Rarity]}
    end
    self:OpenPopup(self.FoodBuyItemsButton,"Food shop",rows,self.FoodBuyItems,true,function() self:RefreshFoodUI() end,true)
end

function A:BuildFoodPage()
    if self.FoodFeedItemsButton then return end
    local page=self:CreatePage("Food")
    self:Section(page,"Feeding")
    self.FoodFeedItemsButton=self:Button(page,"Food  v",function() self:OpenFeedingFoodPicker() end,self.Colors.Row)
    self.FoodFeedItemsButton.Name="FeedingFoodsFilter"
    self.FoodFeedPetsButton=self:Button(page,"Select Pet  v",function() self:OpenFoodFeedPicker() end,self.Colors.Row)
    self.FoodFeedPetsButton.Name="FeedingPetsFilter"
    self.ManualFeedCountBox=self:NumberInput(page,"ManualFeedCount","Feeds per pet (button only)",1,1,1000,nil,true)
    self:Button(page,"Feed Selected Pets",function()
        local amount=self:ClampManualFeedCount(self.ManualFeedCountBox.Text)
        self.Options.ManualFeedCount=amount
        self.ManualFeedCountBox.Text=tostring(amount)
        self:StartJob("Feeding selected pets",function(token) self:FeedSelectedPets(token,amount) end)
    end,self.Colors.Accent)
    self:Toggle(page,"AutoFeed","Auto Feed")
    self:Section(page,"Food shop")
    self.FoodBuyItemsButton=self:Button(page,"Food  v",function() self:OpenShoppingFoodPicker() end,self.Colors.Row)
    self.FoodBuyItemsButton.Name="ShoppingFoodsFilter"
    self:Button(page,"Buy Selected Food",function()
        self:StartJob("Buying selected food",function(token) self:BuySelectedFoods(token) end)
    end,self.Colors.Accent)
    self:Toggle(page,"AutoBuyFood","Auto-buy foods")
    local order=0
    for _,child in ipairs(page:GetChildren()) do if child:IsA("GuiObject") then order=order+1 child.LayoutOrder=order end end
end

function A:RefreshFoodUI()
    if not self.FoodFeedItemsButton then return end
    local feeding,buying=0,0
    for _,name in ipairs(self.FoodNames) do
        if self.FoodFeedItems[name] then feeding=feeding+1 end
        if self.FoodBuyItems[name] then buying=buying+1 end
    end
    self.FoodFeedItemsButton.Text="Food: "..feeding.." / "..#self.FoodNames.."  v"
    self.FoodBuyItemsButton.Text="Food: "..buying.." / "..#self.FoodNames.."  v"
    local selected,total=0,0
    for _,pet in ipairs(self:PetList()) do
        total=total+1
        if self.FoodFeedPets[pet.Key] then selected=selected+1 end
    end
    self.FoodFeedPetsButton.Text="Select Pet: "..selected.." / "..total.."  v"
end

function A:ConfirmSellAll()
    if not self.Alive then return end
    if self.Job then self.SellStatus="Finish the current action first" return end
    local pets=self:InventorySellPets()
    if #pets==0 then self.SellStatus="No inventory pets available to sell" return end
    self:ClosePopup()
    local layer=self:Make("Frame",self.Bounds,{Name="SellConfirmation",Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,ZIndex=20})
    self.Popup=layer
    local function cancel()
        if self.Popup==layer then self:ClosePopup() end
    end
    local backdrop=self:Make("TextButton",layer,{Name="Dismiss",Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,Text="",AutoButtonColor=false,BorderSizePixel=0})
    self:Connect(backdrop.Activated,cancel)
    self:Make("Frame",layer,{Name="PanelShade",Position=self.Panel.Position,Size=self.Panel.Size,
        AnchorPoint=self.Panel.AnchorPoint,BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.45,BorderSizePixel=0,ZIndex=1})
    local area=self.Bounds.AbsoluteSize
    local width=math.min(304,area.X-16)
    local height=self.RowHeight*2+104
    local center=self.Panel.AbsolutePosition-self.Bounds.AbsolutePosition+self.Panel.AbsoluteSize/2
    local x=math.clamp(center.X-width/2,8,math.max(8,area.X-width-8))
    local y=math.clamp(center.Y-height/2,8,math.max(8,area.Y-height-8))
    local box=self:Make("Frame",layer,{Name="Dialog",Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,height),
        BackgroundColor3=self.Colors.Surface,BorderSizePixel=0,ZIndex=2})
    self:Make("UIStroke",box,{Color=self.Colors.Border,Thickness=1})
    self:Make("TextLabel",box,{Name="Title",Size=UDim2.new(1,0,0,self.RowHeight),Text="Confirm Sell All",
        Font=Enum.Font.Code,TextSize=14,TextColor3=self.Colors.Text,BackgroundColor3=self.Colors.Title,BorderSizePixel=0})
    local message=self:Text(box,"Sell "..#pets.." inventory "..(#pets==1 and "pet" or "pets").."?\nFavorites and protected pets will be kept.",70)
    message.Name="Message"
    message.Position=UDim2.fromOffset(10,self.RowHeight+8)
    message.Size=UDim2.new(1,-20,0,70)
    local dismiss=self:Button(box,"Cancel",cancel)
    dismiss.Position=UDim2.new(0,10,1,-self.RowHeight-10)
    dismiss.Size=UDim2.new(0.5,-15,0,self.RowHeight)
    local confirm=self:Button(box,"Sell "..#pets,function()
        if not self.Alive or self.Popup~=layer then return end
        self:ClosePopup()
        if not self:StartJob("Selling all inventory pets",function(token) self:SellAllInventoryPets(token,pets) end) then
            self.SellStatus="Finish the current action first"
        end
    end,self.Colors.Accent)
    confirm.Name="Confirm"
    confirm.Position=UDim2.new(0.5,5,1,-self.RowHeight-10)
    confirm.Size=UDim2.new(0.5,-15,0,self.RowHeight)
end

function A:BuildSellPage()
    if self.SellInfo then return end
    local page=self:CreatePage("Sell")
    self.SellAllButton=self:Button(page,"Sell All",function() self:ConfirmSellAll() end,self.Colors.Accent)
    self:Toggle(page,"AutoSell","Auto Sell Inventory Pets")
    self:Text(page,"Inventory pets only. Favorites are kept.",44).TextColor3=self.Colors.Muted
    self.SellStats=self:Text(page,"",24)
    self:Section(page,"Inventory pets to sell")
    self.SellInfo=self:Text(page,"",24)
    self.SellInfo.TextColor3=self.Colors.Muted
    self.SellInfo.TextSize=13
    self.SellInfo.TextYAlignment=Enum.TextYAlignment.Top
    self:Section(page,"Auto Favorites")
    self:Toggle(page,"AutoFavorites","Auto Favorites")
    self.FavoriteFilterButtons={}
    for _,entry in ipairs({{"Rarities",self.RarityNames},{"Types",self.FavoritePetNames}}) do
        local group,names=entry[1],entry[2]
        local button
        button=self:Button(page,"",function()
            local rows={}
            for _,name in ipairs(names) do
                local rarity=group=="Rarities" and name or self.Data.Pets[name].Rarity
                rows[#rows+1]={ID=name,Label=name,Color=self.RarityColors[rarity]}
            end
            self:OpenPopup(button,group=="Types" and "Pet types" or "Rarities",rows,self.FavoriteFilters[group],true,
                function() self:RefreshSellUI() end,group=="Types")
        end,self.Colors.Row)
        button.Name="Favorite"..group.."Filter"
        self.FavoriteFilterButtons[group]=button
    end
    self.FavoriteInfo=self:Text(page,"",44)
    self.FavoriteInfo.TextColor3=self.Colors.Muted
    self.FavoriteInfo.TextSize=13
    local order=0
    for _,child in ipairs(page:GetChildren()) do if child:IsA("GuiObject") then order=order+1 child.LayoutOrder=order end end
end

function A:RefreshSellUI()
    if not self.SellInfo then return end
    local pets=self:InventorySellPets()
    local lines={}
    for _,pet in ipairs(pets) do lines[#lines+1]=pet.Name.." | "..(pet.Rarity or "Unknown") end
    self.SellStats.Text="Available: "..#pets.." | Sold: "..(self.SoldPets or 0)
    self.SellInfo.Text=#lines>0 and table.concat(lines,"\n") or "No inventory pets available"
    self.SellInfo.Size=UDim2.new(1,0,0,math.max(24,#lines*24))
    local selected={}
    for _,entry in ipairs({{"Rarities",self.RarityNames},{"Types",self.FavoritePetNames}}) do
        local group,names=entry[1],entry[2]
        local count=0
        for _,name in ipairs(names) do if self.FavoriteFilters[group][name] then count=count+1 end end
        selected[group]=count
        self.FavoriteFilterButtons[group].Text=(group=="Types" and "Pet types" or "Rarities")..": "
            ..(count==#names and "All" or count.." / "..#names).."  v"
    end
    local pending=0
    for _ in pairs(self.FavoriteRequests) do pending=pending+1 end
    self.FavoriteInfo.Text=(selected.Rarities==0 or selected.Types==0)
        and "Choose at least one rarity and pet type."
        or "Inventory pets matching both filters are kept."
    if pending>0 then self.FavoriteInfo.Text="Waiting for confirmation: "..pending.."\nThese pets are kept from sale." end
    self.SellAllButton.Text=self.Job=="Selling all inventory pets" and "Selling..." or "Sell All"
end

function A:ControlRefresh()
    for key,control in pairs(self.Controls) do
        local value=self.Options[key]
        if control.Toggle then
            control.Button.Text=(value and "[x] " or "[ ] ")..control.Label
            control.Button.BackgroundColor3=value and self.Colors.Accent or self.Colors.Row
        elseif control.Choice then control.Button.Text=tostring(value).."  v" end
    end
    for _,row in ipairs(self.FilterButtons) do
        if row.Mutated then row.Button.Text=(row.Filter.MutatedOnly and "[x] " or "[ ] ").."Mutated eggs only"
        else
            local count=0
            for _,name in ipairs(row.Names) do if row.Filter[row.Group][name] then count=count+1 end end
            row.Button.Text=row.Group..": "..(count==#row.Names and "All" or tostring(count).." / "..#row.Names).."  v"
        end
    end
end

function A:SwitchPage(name)
    self:CancelKeybind()
    self:ClosePopup()
    self.Page=name
    for key,page in pairs(self.Pages) do page.Visible=key==name end
    self.Navigation.Text=name.."  v"
    self:RefreshUI()
end

function A:ClampPanel(pos)
    local area,size=self.Bounds.AbsoluteSize,self.Panel.AbsoluteSize
    self.Panel.Position=UDim2.fromOffset(math.clamp(pos.X,8,math.max(8,area.X-size.X-8)),
        math.clamp(pos.Y,8,math.max(8,area.Y-size.Y-8)))
end

function A:Layout(size)
    size=size or self.Bounds.AbsoluteSize
    if size.X<=0 or size.Y<=0 then return end
    self:ClosePopup()
    local height=self.Collapsed and self.TitleHeight or math.min(480,math.max(160,size.Y-24))
    self.Panel.Size=UDim2.fromOffset(math.min(320,math.max(200,size.X-24)),height)
    self.Container.Visible=not self.Collapsed
    local pos=self.Positioned and Vector2.new(self.Panel.Position.X.Offset,self.Panel.Position.Y.Offset)
        or Vector2.new(12,math.floor(size.Y*0.2))
    self:ClampPanel(pos)
    self.Positioned=true
    self:LayoutMobileMenu()
end

function A:RefreshUI()
    if not self.StatusLabel then return end
    self:ControlRefresh()
    self.StatusLabel.Text=self.Page=="Food" and self.FoodStatus or self.Page=="Sell" and self.SellStatus or self.Status
    self.StatusLabel.TextColor3=self.Job and self.Colors.Good or self.Colors.Muted
    self.FarmStats.Text=string.format("Basket %d/%s | Stored %d | Nests %d",self.Cache.Basket or 0,self:Format(self:Capacity()),self.Cache.Tools or 0,self.Cache.Nests or 0)
    local lines={}
    for _,egg in ipairs(self.Cache.Timers or {}) do lines[#lines+1]=egg.Name..": "..(egg.Remaining<=0 and "Ready" or self:Time(egg.Remaining)) end
    self.NestInfo.Text=#lines>0 and table.concat(lines,"\n") or "No eggs in nests"
    self.NestInfo.Size=UDim2.new(1,0,0,math.max(22,#lines*20))
    local reward=self.Cache.Reward
    self.IndexInfo.Text=reward and ("Index: "..tostring(self.Cache.Discovered).." / "..reward.Goal) or "Index rewards complete"
    local egg,matchingCount,filteredSelection=nil,0,false
    for _,row in ipairs(self.Cache.Eggs or {}) do
        local matches=self:Matches(row,"Eggs")
        if matches then matchingCount=matchingCount+1 end
        if row.ID==self.Options.SelectedEgg then
            if matches then egg=row else filteredSelection=true end
        end
    end
    if filteredSelection then self.Options.SelectedEgg=nil end
    if self.EggFiltersToggle then self.EggFiltersToggle.Text="Filters "..(self.EggFiltersBody.Visible and "v" or ">").." | "..matchingCount.." eggs" end
    self.EggPicker.Text=egg and egg.Name.." | "..egg.ID:sub(1,5).."  v" or (matchingCount==0 and "No matching eggs  v" or "Select an egg  v")
    self:Preview(egg)
    self.EggName.Text=egg and egg.Name or (self.Options.SelectedEgg and "Egg no longer available" or "Choose an egg")
    self.EggName.TextColor3=egg and self.RarityColors[egg.Rarity] or self.Colors.Muted
    for key,label in pairs(self.EggInfo) do
        local value="-"
        if egg then
            if key=="Rarity" then value=egg.Rarity elseif key=="Luck" then value=self:Format(egg.Luck).."x"
            elseif key=="Weight" then value=self:Format(egg.KG).." kg" elseif key=="Mutation" then value=egg.MutationLabel
            elseif key=="Distance" then value=self:Format(egg.Distance).." studs" end
        end
        label.Text=value
    end
    local pets={}
    for _,pet in ipairs(self.Cache.Pets or {}) do
        pets[#pets+1]=pet.Name.." | $"..self:Format(pet.Income).."/s\n"..self:Format(pet.Speed).." speed | "..(pet.Placed and "Placed" or "Inventory")
    end
    self.PetInfo.Text=#pets>0 and table.concat(pets,"\n\n") or "No pets available"
    self.PetInfo.Size=UDim2.new(1,0,0,math.max(24,#pets*56))
    self.ErrorInfo.Text=#self.Errors>0 and self.Errors[#self.Errors] or "No errors"
    self.ErrorInfo.Size=UDim2.new(1,0,0,#self.Errors>0 and 70 or 22)
    self:RefreshMenuButtons()
    self:RefreshFoodUI()
    self:RefreshSellUI()
end

A.Gui=A:Make("ScreenGui",A.Player:WaitForChild("PlayerGui"),{Name="RideAPetCompact",ResetOnSpawn=false,
    DisplayOrder=250,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets})
A.Bounds=A:Make("Frame",A.Gui,{Name="SafeArea",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0})
A.Panel=A:Make("Frame",A.Bounds,{Name="Panel",Size=UDim2.fromOffset(320,480),BackgroundColor3=A.Colors.Surface,BorderSizePixel=0,Active=true})
A:Make("UIStroke",A.Panel,{Color=A.Colors.Border,Thickness=1})
A.Title=A:Make("Frame",A.Panel,{Name="TitleBar",Size=UDim2.new(1,0,0,A.TitleHeight),BackgroundColor3=A.Colors.Title,BorderSizePixel=0})
A.Collapse=A:Button(A.Title,"v",function() A.Collapsed=not A.Collapsed A.Collapse.Text=A.Collapsed and ">" or "v" A:Layout() end,A.Colors.Title)
A.Collapse.Name="Collapse"
A.Collapse.Size=UDim2.fromOffset(A.TitleHeight,A.TitleHeight)
A.Header=A:Button(A.Title,"Ride A Pet",function() end,A.Colors.Title)
A.Header.Name="DragHandle"
A.Header.Position=UDim2.fromOffset(A.TitleHeight,0)
A.Header.Size=UDim2.new(1,-A.TitleHeight*2,1,0)
A.Header.TextXAlignment=Enum.TextXAlignment.Left
A.Header.AutoButtonColor=false
A.Close=A:Button(A.Title,"x",function() A:SetMenuVisible(false) end,A.Colors.Title)
A.Close.Name="Close"
A.Close.AnchorPoint=Vector2.new(1,0)
A.Close.Position=UDim2.fromScale(1,0)
A.Close.Size=UDim2.fromOffset(A.TitleHeight,A.TitleHeight)
A.Container=A:Make("Frame",A.Panel,{Name="Container",Position=UDim2.fromOffset(8,A.TitleHeight+6),
    Size=UDim2.new(1,-16,1,-A.TitleHeight-12),BackgroundTransparency=1})
A.Navigation=A:Button(A.Container,"Farm  v",function() A:OpenPagePicker() end,A.Colors.Row)
A.Navigation.Name="PagePicker"
local footerHeight=44
for _,name in ipairs(A.PageNames) do A:CreatePage(name) end
A.StatusLabel=A:Text(A.Container,"Ready",44)
A.StatusLabel.Name="Status"
A.StatusLabel.Position=UDim2.new(0,0,1,-footerHeight)
A.StatusLabel.TextSize=12
A.StatusLabel.TextYAlignment=Enum.TextYAlignment.Top

local farm=A.Pages.Farm
A:Toggle(farm,"AutoCollect","Auto Collect Eggs")
A:Toggle(farm,"AutoPlace","Auto Place Eggs")
A:Toggle(farm,"AutoHatch","Auto Hatch Eggs")
A:Toggle(farm,"AutoIndex","Auto Claim Index")
A.FarmStats=A:Text(farm,"",36)
A.FarmStats.TextSize=12
A:Choice(farm,"EggPriority","Collection priority",{"Nearest","Rarest","Highest luck","Heaviest"})
A:NumberInput(farm,"TweenSpeed","Flight speed (studs / second)",10,40,350)
A:NumberInput(farm,"MaxDistance","Collection range (studs)",100,100,15000)
A:Button(farm,"Place Eggs Now",function() A:StartJob("Placing eggs",function(token) A.EggDeliveryPaused=false A:PlaceEggs(token) end) end)
A:Button(farm,"Hatch Ready Eggs",function() A:StartJob("Hatching eggs",function(token) A:HatchReady(token) end) end)
A:Button(farm,"Claim Index Reward",function() A:StartJob("Claiming index",function(token) A:ClaimIndex(token) end) end)
A:Button(farm,"Fly to Ranch",function() A:StartJob("Returning to ranch",function(token) A.EggDeliveryPaused=false A:Home(token) end) end)
A.NestInfo=A:Text(farm,"",22)
A.IndexInfo=A:Text(farm,"",22)

local eggs=A.Pages.Eggs
A:BuildEggFilters()
A.EggPicker=A:Button(eggs,"Select an egg  v",function() A:OpenEggPicker() end,A.Colors.Row)
A:MakePreview()
A.Viewport.Parent=eggs
A.EggName=A:Text(eggs,"Choose an egg",24)
A.EggName.TextXAlignment=Enum.TextXAlignment.Center
A.EggInfo={}
for index,key in ipairs({"Rarity","Luck","Weight","Mutation","Distance"}) do
    local row=A:Make("Frame",eggs,{Name=key,Size=UDim2.new(1,0,0,24),BorderSizePixel=0,
        BackgroundColor3=index%2==1 and A.Colors.Row or A.Colors.RowAlternate})
    local label=A:Text(row,key,24)
    label.Position=UDim2.fromOffset(6,0)
    label.Size=UDim2.new(0.35,-6,1,0)
    local value=A:Text(row,"-",24)
    value.Position=UDim2.fromScale(0.35,0)
    value.Size=UDim2.new(0.65,-6,1,0)
    value.TextXAlignment=Enum.TextXAlignment.Right
    value.TextSize=13
    A.EggInfo[key]=value
end
A:Button(eggs,"Collect Selected Egg",function()
    A:StartJob("Collecting selected egg",function(token)
        A:CollectSelectedEgg(token)
    end)
end,A.Colors.Accent)
A:Button(eggs,"Stop Collecting",function() A:StopCollecting() end)
A:Toggle(eggs,"RotatePreview","Rotate preview")
A:Text(eggs,"Drag the model to rotate.",20).TextSize=12

local esp=A.Pages.ESP
for _,entry in ipairs({{"EggESP","Enable Egg ESP"},{"ESPName","Show name"},{"ESPRarity","Show rarity"},
    {"ESPShowDistance","Show distance"},{"ESPWeight","Show weight"},{"ESPMutation","Show mutation"},
    {"ESPLuck","Show luck"},{"ESPBoxes","Show egg markers"},{"ESPTracers","Show tracers"}}) do A:Toggle(esp,entry[1],entry[2]) end
A:NumberInput(esp,"ESPSize","Text size",1,12,25)
A:NumberInput(esp,"ESPCount","Maximum labels",5,1,100)
A:NumberInput(esp,"ESPDistance","ESP range (studs)",100,100,15000)
A:FilterPanel(A.Pages["ESP Filters"],"ESP")
A:FilterPanel(A.Pages["Collect filters"],"Collect")

local pets=A.Pages.Pets
A:Toggle(pets,"AutoBest","Auto Place Best Pets")
A:Choice(pets,"BestMetric","Rank pets by",{"Income","Speed"})
A:Button(pets,"Place Best Pets Now",function() A:StartJob("Placing best pets",function(token) A:PlaceBest(token) end) end)
A.PetInfo=A:Text(pets,"",24)
A.PetInfo.TextYAlignment=Enum.TextYAlignment.Top
A:BuildSellPage()
A:BuildFoodPage()
local settings=A.Pages.Settings
A:Toggle(settings,"AntiAFK","Anti-AFK")
A.KeybindButton=A:Button(settings,"Menu key: Right Ctrl",function()
    A:ClosePopup()
    A.BindingKey=not A.BindingKey
    A:RefreshKeybind()
end,A.Colors.Row)
A.KeybindButton.Name="MenuKeybind"
A:Text(settings,"Click Menu key, then press a key. Esc cancels. Drag the blue title bar to move the window.",60).TextColor3=A.Colors.Muted
A:Button(settings,"Center Window",function() local s=A.Bounds.AbsoluteSize A:ClampPanel((s-A.Panel.AbsoluteSize)/2) end)
A:BuildTelegramButton(settings)
A:Button(settings,"Unload",function() A:Unload() end)
A:Section(settings,"Last error")
A.ErrorInfo=A:Text(settings,"No errors",22)
A.ErrorInfo.TextColor3=A.Colors.Muted

for _,page in pairs(A.Pages) do
    local index=0
    for _,child in ipairs(page:GetChildren()) do if child:IsA("GuiObject") then index=index+1 child.LayoutOrder=index end end
end

A.Menu=A:Button(A.Bounds,"Menu",function() A:SetMenuVisible(true) end,A.Colors.Title)
A.Menu.Size=UDim2.fromOffset(74,44)
A.Menu.Position=UDim2.new(1,-82,1,-52)
A.Menu.ZIndex=30
A.Menu.Visible=false
A:BuildMobileMenu()

local dragInput,dragStart,panelStart
local function endDrag() dragInput,dragStart,panelStart=nil,nil,nil end
A:Connect(A.Header.InputBegan,function(input)
    if dragInput then return end
    if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
    A:ClosePopup()
    dragInput=input
    dragStart=Vector2.new(input.Position.X,input.Position.Y)
    panelStart=Vector2.new(A.Panel.Position.X.Offset,A.Panel.Position.Y.Offset)
end)
A:Connect(A.UIS.InputChanged,function(input)
    if dragInput and (input==dragInput or (dragInput.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)) then
        A:ClampPanel(panelStart+Vector2.new(input.Position.X,input.Position.Y)-dragStart)
    end
end)
A:Connect(A.UIS.InputEnded,function(input)
    if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then endDrag() end
end)
A:Connect(A.UIS.WindowFocusReleased,function() endDrag() A.PreviewDrag=nil A:CancelKeybind() end)
A.MenuInputConnection=A:Connect(A.UIS.InputBegan,function(input,processed) A:HandleMenuInput(input,processed) end)
A:Connect(A.Bounds:GetPropertyChangedSignal("AbsoluteSize"),function() endDrag() A:Layout() end)
A:Connect(A.Player.CharacterAdded,function() A:CancelJob() A.Status="Character respawned; waiting for the ranch" end)
A:Connect(A.ActiveEggs.ChildRemoved,function(egg) A.FailedEggs[egg.Name]=nil end)
A:Connect(A.Run.RenderStepped,function(dt)
    local ok,err=pcall(function() A:RenderESP() A:RenderPreview(dt) end)
    if not ok then A:SetOption("EggESP",false) A:Error("Rendering",err) end
end)

function A:Unload()
    if not self.Alive then return end
    self.Alive=false
    self:CancelJob()
    self:SetAntiAFK(false)
    self:ClearESP()
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    for _,thread in ipairs(self.Threads) do pcall(task.cancel,thread) end
    if self.Gui then self.Gui:Destroy() end
    if Env.RideAPetCompact==self then Env.RideAPetCompact=nil end
end

A:Refresh()
A:RefreshUI()
A:Layout()
A:SetAntiAFK(true)
table.insert(A.Threads,task.spawn(function()
    while A.Alive do
        local ok,err=xpcall(function() A:Tick() end,debug.traceback)
        if not ok then A:Error("Automation",err) end
        task.wait(0.4)
    end
end))
table.insert(A.Threads,task.spawn(function()
    while A.Alive do
        local ok,err=xpcall(function()
            A:Refresh()
            local rendered,message=pcall(function() A:UpdateESP() end)
            if not rendered then A:SetOption("EggESP",false) A:Error("Drawing ESP",message) end
            A:RefreshUI()
        end,debug.traceback)
        if not ok then A:Error("Data refresh",err) end
        task.wait(0.7)
    end
end))
return A

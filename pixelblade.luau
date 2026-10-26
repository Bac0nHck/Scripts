local launchMode, resumed = ...
local host: any = getgenv and getgenv() or _G
if launchMode == "teleport" then
	if host.__PixelBladeRemoteLoaded == game.JobId then return end
	if type(readfile) == "function" then
		local ok, saved = pcall(function()
			return game:GetService("HttpService"):JSONDecode(readfile("pixelblade.teleport.json"))
		end)
		if ok and type(saved) == "table" then
			if saved.Enabled == false then return end
			resumed = saved.Data
		end
	end
	host.__PixelBladeRemoteLoaded = game.JobId
end
if type(resumed) ~= "table" and type(host.__PixelBladeTeleportState) == "table" then
	resumed = host.__PixelBladeTeleportState
end
host.__PixelBladeTeleportState = nil
local previous = host.PixelBlade
if type(previous) == "table" and type(previous.Unload) == "function" then
	previous.Unload()
	task.wait(0.25)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
if game.GameId ~= 6161049307 then
	warn("[Pixel Blade] This game is not supported.")
	return
end
if not game:IsLoaded() then game.Loaded:Wait() end

local LIBRARY_URL = "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"
local LIBRARY_PAGE = "https://github.com/PookiePepelsss/Airflow-UI"
local CREDITS_URL = "https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram"
local CONFIG_FILE = "pixelblade.preferences.json"
local TELEPORT_FILE = "pixelblade.teleport.json"
local featureNames = { "AutoFarm", "AutoPickBanner", "AutoReplay", "AutoStartRun", "AutoFishing", "AutoUpgradeItems", "AutoOpenChests", "KillAura", "InfiniteDash", "AutoSkills", "AutoParry", "AutoDodge", "AutoRevive", "EnemyChams", "EnemyInfo" }
local farmFeatures = { "AutoPickBanner", "AutoReplay", "AutoStartRun", "KillAura", "InfiniteDash", "AutoSkills", "AutoParry", "AutoDodge", "AutoRevive" }
local campaignOrder = { "Grasslands", "AncientSands", "HauntedTundra", "CrimsonAbyss", "SunkenDepths" }
local campaignSet: {[string]: boolean} = {}
for _, name in campaignOrder do campaignSet[name] = true end

local session: any = {
	Alive = true, Ready = false, State = { AntiAfk = true }, Controls = {}, Connections = {}, Patches = {},
	Options = { Map = "Grasslands", Difficulty = "Normal", AuraRadius = 15, InfoDistance = 250, MenuKey = "RightControl", BannerMode = "Smart", BannerPriority = {}, UpgradeScope = "All Items", ChestNames = { "All Owned" } },
	Status = "Connecting", Errors = {}, Overlay = {}, AuraRecords = setmetatable({}, { __mode = "k" }),
	Diagnostics = { Hits = 0, DeniedHits = 0, Parries = 0, Dodges = 0, Skills = 0, BannerPicks = 0, ReviveRequests = 0, RunStarts = 0, ReplayVotes = 0, FarmTeleports = 0, DashStarts = 0, FishingCatches = 0, FishingCasts = 0, PerfectBubbles = 0 },
}
for _, name in featureNames do session.State[name] = false end
host.PixelBlade = session
local state = session.State
local options = session.Options
local controls = session.Controls
local deps: any = {}
local world: any, context: any, C: any
local window: any, airflow: any
local enemyRows: {any} = {}
local root: any, humanoid: any, character: any, localEntity: any, target: any
local progress: any = {}
local roomEntity: any, roomData: any
local attackOwned = false
local blockOwned = false
local defenseUntil = 0
local nextMove = 0
local nextSkill = 0
local skillSlot = 1
local bannerOffer: any, pickedOffer: any
local bannerSeenAt = 0
local reviveAttempt: any, replayAttempt: any
local startAttemptAt = 0
local nextConnect = 0
local saveGeneration = 0
local lastUnlockSignature = ""
local previousDash: any
local persistTeleport: any = function(_enabled: boolean?) end
local fishing: any = { Engaged = false, NextAction = 0, NextScan = 0, NextPress = 0, NextRuntimeScan = 0, ValidCast = false, CastDistance = 0 }
local fishingRay = RaycastParams.new()
fishingRay.RespectCanCollide = true
local inventory: any = { NextScan = 0, HoldUntil = 0, LastKind = "Upgrade", UpgradeBlocked = {}, ChestBlocked = {} }
local rarityRanks = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Vaulted = 5 }
local legacyChestType: string?

local function connect(signal: any, callback: any): any
	local connection = signal:Connect(callback)
	table.insert(session.Connections, connection)
	return connection
end

local function notify(title: string, content: string?, kind: string?)
	if session.Alive and window then
		window:Notify({ Title = title, Content = content, Type = kind or "Info", Duration = 3 })
	end
end

local function report(key: string, message: any)
	local now = os.clock()
	if now - (session.Errors[key] or -math.huge) > 12 then
		session.Errors[key] = now
		warn("[Pixel Blade] " .. key .. ": " .. tostring(message))
		notify(key, tostring(message), "Warning")
	end
end

local function fetch(url: string): (string?, string?)
	local ok, result = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and type(result) == "string" and #result > 0 then return result, nil end
	return nil, tostring(result)
end

local function readPreferences()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
	local ok, saved = pcall(function()
		if not isfile(CONFIG_FILE) then return nil end
		return HttpService:JSONDecode(readfile(CONFIG_FILE))
	end)
	if ok and type(saved) == "table" and saved.Version == 1 and type(saved.Options) == "table" then
		if type(saved.Options.ChestNames) ~= "table" and type(saved.Options.ChestType) == "string" then legacyChestType = saved.Options.ChestType end
		for key in options do
			if typeof(saved.Options[key]) == typeof(options[key]) then options[key] = saved.Options[key] end
		end
		if type(saved.AntiAfk) == "boolean" then state.AntiAfk = saved.AntiAfk end
	end
end
readPreferences()
if type(resumed) == "table" then
	if type(resumed.Options) == "table" then
		if type(resumed.Options.ChestNames) == "table" then legacyChestType = nil
		elseif type(resumed.Options.ChestType) == "string" then legacyChestType = resumed.Options.ChestType end
		for key in options do
			if typeof(resumed.Options[key]) == typeof(options[key]) then options[key] = resumed.Options[key] end
		end
	end
	if type(resumed.State) == "table" then
		for key in state do if type(resumed.State[key]) == "boolean" then state[key] = resumed.State[key] end end
	end
end
options.AuraRadius = math.clamp(tonumber(options.AuraRadius) or 15, 5, 50)
options.InfoDistance = math.clamp(tonumber(options.InfoDistance) or 250, 25, 1000)
if not campaignSet[options.Map] then options.Map = "Grasslands" end
if options.BannerMode ~= "Manual" then options.BannerMode = "Smart" end
if not table.find({ "All Items", "Equipped", "Weapons", "Armor" }, options.UpgradeScope) then options.UpgradeScope = "All Items" end
if not table.find({ "Normal", "Heroic", "Nightmare" }, options.Difficulty) then options.Difficulty = "Normal" end
if not pcall(function() return Enum.KeyCode[options.MenuKey] end) then options.MenuKey = "RightControl" end

local function savePreferences()
	persistTeleport()
	saveGeneration += 1
	local generation = saveGeneration
	task.delay(0.4, function()
		if not session.Alive or generation ~= saveGeneration or type(writefile) ~= "function" then return end
		local ok, reason = pcall(function()
			writefile(CONFIG_FILE, HttpService:JSONEncode({ Version = 1, Options = options, AntiAfk = state.AntiAfk }))
		end)
		if not ok then report("Settings", reason) end
	end)
end

local function moduleAt(path: string): any
	local item = ReplicatedStorage:WaitForChild("src", 15)
	for part in path:gmatch("[^.]+") do
		item = item and item:WaitForChild(part, 8)
		if not item then error("Missing game module: " .. path) end
	end
	return require(item)
end

local function findContext(): boolean
	if type(getgc) ~= "function" then return false end
	for _, value in getgc(true) do
		if type(value) == "table" and rawget(value, "is_client") == true and rawget(value, "local_player_entity") then
			local replicator = rawget(value, "replicator")
			local candidate = type(replicator) == "table" and rawget(replicator, "world")
			if type(candidate) == "table" and type(candidate.get) == "function" and candidate:contains(value.local_player_entity) then
				context, world = value, candidate
				return true
			end
		end
	end
	return false
end

local function has(entity: any, component: any): boolean
	return entity ~= nil and component ~= nil and world:contains(entity) and world:has(entity, component)
end

local function ancestor(entity: any, component: any): any
	for _ = 1, 16 do
		if not entity or not world:contains(entity) then return nil end
		if world:has(entity, component) then return entity end
		entity = world:parent(entity)
	end
	return nil
end

local function inCampaign(): boolean
	if not session.Ready or not world then return false end
	local place = world:get(C.Place, C.Place)
	return place ~= nil and campaignSet[place.id] == true and context.place_kind == "Run"
end

local function validRoot(part: any): boolean
	return typeof(part) == "Instance" and part:IsA("BasePart") and part.Parent ~= nil
end

local function alive(): boolean
	return localEntity ~= nil and world:contains(localEntity) and validRoot(root)
		and not (has(localEntity, C.Dead) or has(localEntity, C.Eliminated))
end

local function heldByGame(): boolean
	return deps.Cutscene.is_holding_player(world, context)
		or has(localEntity, C.ManningStation) or has(localEntity, C.VaultMinigame)
		or has(localEntity, C.CrystalAiming) or has(localEntity, C.RodHeld)
end

local function releaseAttack()
	if attackOwned and deps.Input then deps.Input.set_attack_held(false) end
	attackOwned = false
end

local function releaseBlock()
	if blockOwned and deps.Input then deps.Input.set_blocking(false) end
	blockOwned = false
end

local function clearFishingSpot(restore: boolean)
	local platform = fishing.Platform
	if restore and platform and platform.Parent and validRoot(root) and fishing.HomeRoot == root
		and fishing.Home and fishing.StandPosition and (root.Position - fishing.StandPosition).Magnitude < 24 then
		root.CFrame = fishing.Home
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if platform then platform:Destroy() end
	fishing.Platform = nil
	fishing.Home = nil
	fishing.HomeRoot = nil
	fishing.Hole = nil
	fishing.HoleData = nil
	fishing.StandPosition = nil
	fishing.ValidCast = false
	fishing.NextScan = 0
	session.FishingLuck = nil
	session.FishingHole = nil
	session.FishingHolePosition = nil
end

local function stopFishing(stow: boolean)
	if fishing.Engaged and deps.FishingIntents then deps.FishingIntents.auto_off:Fire(os.clock()) end
	if fishing.Engaged and stow and session.Ready and localEntity and has(localEntity, C.RodHeld) then
		deps.Network.toggle_rod.fire()
	end
	if stow then fishing.Engaged = false clearFishingSpot(true) end
	fishing.NextAction = 0
	fishing.NextPress = 0
end

local function clearOverlays()
	for entity, record in session.Overlay do
		if record.Highlight then record.Highlight:Destroy() end
		if record.Billboard then record.Billboard:Destroy() end
		session.Overlay[entity] = nil
	end
end

local function restoreAura()
	for hitbox, record in session.AuraRecords do
		if hitbox.inner == record.Applied then hitbox.inner = record.Original end
		session.AuraRecords[hitbox] = nil
	end
end

local function bump(name: string)
	session.Diagnostics[name] = (session.Diagnostics[name] or 0) + 1
end

function session.Snapshot(): any
	local savedOptions = table.clone(options)
	savedOptions.BannerPriority = table.clone(options.BannerPriority)
	savedOptions.ChestNames = table.clone(options.ChestNames)
	return { Version = 1, Options = savedOptions, State = table.clone(state) }
end

persistTeleport = function(enabled: boolean?)
	if type(writefile) ~= "function" then return end
	local ok, reason = pcall(function()
		writefile(TELEPORT_FILE, HttpService:JSONEncode({ Enabled = enabled ~= false, Data = session.Snapshot() }))
	end)
	if not ok and session.Ready then report("Teleport settings", reason) end
end

function session.SetFeature(name: string, enabled: boolean, silent: boolean?)
	if not session.Alive or state[name] == nil then return end
	if enabled and name ~= "AntiAfk" and not session.Ready then
		notify("Still connecting", nil, "Warning")
		if controls[name] then controls[name]:Set(false, true) end
		return
	end
	if enabled and name == "AutoFishing" then
		if state.AutoFarm then session.SetFeature("AutoFarm", false, true) end
		if state.AutoStartRun then session.SetFeature("AutoStartRun", false, true) end
		releaseAttack()
		releaseBlock()
	elseif enabled and (name == "AutoFarm" or name == "AutoStartRun") and state.AutoFishing then
		session.SetFeature("AutoFishing", false, true)
	end
	state[name] = enabled == true
	if controls[name] then controls[name]:Set(state[name], true) end
	if name == "AutoFarm" then
		for _, key in farmFeatures do session.SetFeature(key, enabled, true) end
		if not enabled then releaseAttack() releaseBlock() end
	elseif name == "KillAura" then
		if not enabled then restoreAura() if not state.AutoFarm then releaseAttack() end end
	elseif name == "AutoParry" and not enabled then releaseBlock()
	elseif name == "AutoFishing" then
		if not enabled then stopFishing(true) session.Status = "Idle" end
	elseif name == "AutoUpgradeItems" then
		if enabled then table.clear(inventory.UpgradeBlocked) end
		inventory.NextScan = 0
		if controls.UpgradeStatus then controls.UpgradeStatus:Set(enabled and "Waiting for upgrades" or "Idle") end
	elseif name == "AutoOpenChests" then
		if enabled then table.clear(inventory.ChestBlocked) end
		inventory.NextScan = 0
		if controls.ChestStatus then controls.ChestStatus:Set(enabled and "Waiting for chests" or "Idle") end
	elseif name == "EnemyChams" or name == "EnemyInfo" then clearOverlays()
	elseif name == "AntiAfk" then savePreferences()
	end
	if not silent and name == "AutoFarm" then session.Status = enabled and "Starting farm" or "Idle" end
	persistTeleport()
end

function session.StopAll(silent: boolean?)
	for _, name in featureNames do
		state[name] = false
		if controls[name] then controls[name]:Set(false, true) end
	end
	releaseAttack()
	releaseBlock()
	stopFishing(true)
	restoreAura()
	clearOverlays()
	defenseUntil = 0
	session.Status = "Stopped"
	if controls.UpgradeStatus then controls.UpgradeStatus:Set("Idle") end
	if controls.ChestStatus then controls.ChestStatus:Set("Idle") end
	persistTeleport()
	if not silent then notify("Stopped") end
end

function session.Unload()
	if not session.Alive then return end
	session.StopAll(true)
	persistTeleport(false)
	session.Alive = false
	saveGeneration += 1
	for _, connection in session.Connections do pcall(function() connection:Disconnect() end) end
	table.clear(session.Connections)
	for index = #session.Patches, 1, -1 do
		local patch = session.Patches[index]
		if patch.Owner[patch.Key] == patch.Replacement then patch.Owner[patch.Key] = patch.Original end
	end
	table.clear(session.Patches)
	if window then window:Destroy() end
	if host.PixelBlade == session then host.PixelBlade = nil end
end

local function patch(owner: any, key: string, replacement: any)
	assert(type(owner[key]) == "function" and not table.isfrozen(owner), "Cannot adapt game function: " .. key)
	table.insert(session.Patches, { Owner = owner, Key = key, Original = owner[key], Replacement = replacement })
	owner[key] = replacement
end

local function isOwnAttack(entity: any, hitbox: any): boolean
	return state.KillAura and inCampaign() and alive() and not heldByGame()
		and hitbox.damage_type == deps.DamageType.Attack and ancestor(entity, C.Player) == localEntity
end

local function installAdapters()
	local originalCollect = deps.Hurtbox.collect_candidates
	patch(deps.Hurtbox, "collect_candidates", function(w: any, source: any, position: any, radius: any, output: any)
		local hitbox = w == world and w:get(source, C.Hitbox)
		if not (hitbox and isOwnAttack(source, hitbox)) then
			return originalCollect(w, source, position, radius, output)
		end
		local record = session.AuraRecords[hitbox]
		if not record then
			record = { Original = hitbox.inner, Source = source }
			session.AuraRecords[hitbox] = record
		end
		local shape = { shape = deps.HitboxShape.Sphere, radius = options.AuraRadius }
		record.Applied = shape
		hitbox.inner = shape
		originalCollect(w, source, root.Position, options.AuraRadius, output)
		for index = #output, 1, -1 do
			local enemy = ancestor(output[index], C.Enemy)
			if not enemy or has(enemy, C.Friendly) or has(enemy, C.Dead)
				or (roomEntity and ancestor(enemy, C.Room) ~= roomEntity) then table.remove(output, index) end
		end
	end)
	local originalOverlap = deps.Hitbox.get_overlap_intersection
	patch(deps.Hitbox, "get_overlap_intersection", function(hitbox: any, transform: any, part: any, bounding: any, sweep: any)
		local record = session.AuraRecords[hitbox]
		if record and isOwnAttack(record.Source, hitbox) then
			return originalOverlap(hitbox, root.CFrame, part, options.AuraRadius, nil)
		end
		return originalOverlap(hitbox, transform, part, bounding, sweep)
	end)
	local originalCost = deps.Stat.get_dash_energy_cost
	patch(deps.Stat, "get_dash_energy_cost", function(w: any, entity: any, ...: any)
		if session.Alive and state.InfiniteDash and w == world and entity == localEntity and inCampaign() then return 0 end
		return originalCost(w, entity, ...)
	end)
	local originalDefense = deps.Damage.get_defense
	local defending = false
	patch(deps.Damage, "get_defense", function(w: any, entity: any, source: any, damageType: any, unblockable: any, projectile: any, attackPosition: any, forced: any, undodgeable: any, pierces: any, omnidirectional: any)
		if not defending and w == world and entity == localEntity and inCampaign() and alive() and not heldByGame()
			and (state.AutoParry or state.AutoDodge) then
			defending = true
			local ok, reason = pcall(function()
				local weaponEntity = w:get(entity, C.EquippedWeapon)
				local weapon = weaponEntity and w:get(weaponEntity, C.Weapon)
				local kind = weapon and weapon.attributes and weapon.attributes.type
				local currentBlock = w:get(entity, C.Block)
				local parryAllowed = damageType ~= deps.DamageType.Element and not unblockable
					and not ancestor(source, C.UNPARRYABLE) and kind ~= deps.WeaponType.Spear and kind ~= deps.WeaponType.DualBlades
					and weapon ~= nil and not has(weaponEntity, C.Skill) and not has(entity, C.Dash)
					and (currentBlock == nil or currentBlock.active == true)
				if state.AutoParry and parryAllowed then
					local sourceEntity = source and (ancestor(source, C.Actor) or source)
					local sourceRoot = sourceEntity and w:get(sourceEntity, C.RootPart)
					local point = typeof(attackPosition) == "Vector3" and attackPosition or (validRoot(sourceRoot) and sourceRoot.Position)
					if point then
						local flat = Vector3.new(point.X, root.Position.Y, point.Z)
						if (flat - root.Position).Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, flat) end
					end
					releaseAttack()
					if not deps.Input.is_blocking() then deps.Input.set_blocking(true) blockOwned = true end
					if not currentBlock then
						w:set(entity, C.Block, { active = true, timestamp = os.clock(), duration = deps.Gameplay.players.block_duration, cooldown = deps.Gameplay.players.block_cooldown })
					end
					defenseUntil = os.clock() + 0.16
				elseif state.AutoDodge and not undodgeable and not deps.Damage.is_source_undodgeable(w, source) then
					local counter = w:get(entity, C.DashCounter)
					local energy = w:get(entity, C.Energy)
					local cost = deps.Stat.get_dash_energy_cost(w, entity)
					if not has(entity, C.Dash) and counter and counter.count > 0 and energy and energy.value >= cost then
						releaseAttack() releaseBlock()
						deps.Input.dash:Fire(os.clock())
						deps.LocalDash.system(w, context)
						if has(entity, C.Dash) then defenseUntil = os.clock() + 0.15 end
					end
				end
			end)
			defending = false
			if not ok then report("Auto defense", reason) end
		end
		local result = originalDefense(w, entity, source, damageType, unblockable, projectile, attackPosition, forced, undodgeable, pierces, omnidirectional)
		if w == world and entity == localEntity then
			if result.parry and state.AutoParry then bump("Parries") end
			if result.dodged and state.AutoDodge then bump("Dodges") end
		end
		return result
	end)
end

local function updateWorld()
	localEntity = context.local_player_entity
	if not localEntity or not world:contains(localEntity) then return end
	root = world:get(localEntity, C.RootPart)
	humanoid = world:get(localEntity, C.Humanoid)
	character = world:get(localEntity, C.Character)
	progress = deps.Room.get_run_progress(world)
	roomEntity = progress.objective_entity or progress.entered_entity
	roomData = roomEntity and world:get(roomEntity, C.Room)
	table.clear(enemyRows)
	for entity, enemy, model in world:query(C.Enemy, C.Model) do
		local hp = world:get(entity, C.Health)
		local enemyRoot = world:get(entity, C.RootPart)
		if model.Parent and hp and hp.value > 0 and not has(entity, C.Dead) and not has(entity, C.Friendly) and validRoot(enemyRoot) then
			table.insert(enemyRows, { Entity = entity, Enemy = enemy, Model = model, Root = enemyRoot, Health = hp,
				Room = ancestor(entity, C.Room), Boss = has(entity, C.BOSS), Distance = validRoot(root) and (enemyRoot.Position - root.Position).Magnitude or math.huge })
		end
	end
	table.sort(enemyRows, function(a, b) return a.Distance < b.Distance end)
	target = nil
	for _, row in enemyRows do if row.Room == roomEntity then target = row break end end
	session.CurrentRoom = roomData and roomData.level
	session.EnemyCount = #enemyRows
	session.Target = target and target.Enemy.id
	local dash = world:get(localEntity, C.Dash)
	if dash and dash ~= previousDash and (not previousDash or dash.timestamp ~= previousDash.timestamp) then bump("DashStarts") end
	previousDash = dash
end

local function refillDash()
	if not (state.InfiniteDash and inCampaign() and alive()) then return end
	local counter = world:get(localEntity, C.DashCounter)
	if counter and counter.count < counter.max then
		local replacement = table.clone(counter)
		replacement.count = counter.max
		world:set(localEntity, C.DashCounter, replacement)
	end
end

local function moveTo(position: Vector3, face: Vector3?)
	if not validRoot(root) or os.clock() < nextMove then return end
	local difference = (position - root.Position).Magnitude
	if difference > 3 then
		local look = face and Vector3.new(face.X, position.Y, face.Z)
		root.CFrame = look and (look - position).Magnitude > 0.01 and CFrame.lookAt(position, look) or CFrame.new(position) * root.CFrame.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
		nextMove = os.clock() + 0.3
		bump("FarmTeleports")
	elseif face then
		local look = Vector3.new(face.X, root.Position.Y, face.Z)
		if (look - root.Position).Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, look) end
	end
end

local function farmStep()
	if not state.AutoFarm then return end
	if not inCampaign() then session.Status = "Waiting for run" releaseAttack() return end
	if not alive() then session.Status = "Waiting for revive" releaseAttack() return end
	if has(localEntity, C.Banners) then session.Status = "Choosing banner" releaseAttack() return end
	if heldByGame() then session.Status = "Waiting for scene" releaseAttack() return end
	if has(localEntity, C.Stun) or os.clock() < defenseUntil or has(localEntity, C.Dash) then releaseAttack() return end
	if roomData and not roomData.fight_started and not roomData.cleared then
		session.Status = "Entering room " .. tostring(roomData.level)
		local position = roomData.fight_point or roomData.teleport_cframe.Position
		moveTo(position)
		releaseAttack()
		return
	end
	if target then
		session.Status = "Room " .. tostring(roomData and roomData.level or "?") .. " / " .. tostring(target.Enemy.id)
		local position = target.Root.Position
		local direction = target.Root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if direction.Magnitude < 0.01 then direction = Vector3.new(0, 0, 1) end
		local destination = position - direction.Unit * 4
		local rayParameters = RaycastParams.new()
		rayParameters.FilterType = Enum.RaycastFilterType.Exclude
		rayParameters.FilterDescendantsInstances = { character, target.Model }
		local floor = Workspace:Raycast(destination + Vector3.new(0, 8, 0), Vector3.new(0, -24, 0), rayParameters)
		if floor then destination = Vector3.new(destination.X, floor.Position.Y + (humanoid and humanoid.HipHeight or 2) + root.Size.Y * 0.5, destination.Z) end
		moveTo(destination, position)
	elseif roomData and roomData.cleared and roomData.exit_door_open then
		session.Status = "Next room"
		local nextRoom = deps.Room.get_next_room_entity(world)
		local nextData = nextRoom and world:get(nextRoom, C.Room)
		if nextData then
			moveTo(nextData.fight_point or nextData.teleport_cframe.Position)
		elseif roomData.exit_door then
			local exit = roomData.exit_door.origin.Position
			local start = roomData.teleport_cframe.Position
			local delta = (exit - start) * Vector3.new(1, 0, 1)
			if delta.Magnitude > 0.01 then moveTo(Vector3.new(exit.X, start.Y, exit.Z) + delta.Unit * 8) end
		end
	else
		session.Status = "Waiting for room"
		releaseAttack()
	end
end

local function attackStep()
	local active = (state.KillAura or state.AutoFarm) and inCampaign() and alive() and target ~= nil
		and not heldByGame() and not has(localEntity, C.Banners) and not has(localEntity, C.Stun)
		and not has(localEntity, C.Dash) and os.clock() >= defenseUntil
	local weaponEntity = localEntity and world:get(localEntity, C.EquippedWeapon)
	if active and weaponEntity and not has(weaponEntity, C.Skill) and not has(weaponEntity, C.SkillAiming)
		and target.Distance <= (state.KillAura and options.AuraRadius or 8) then
		if not attackOwned then deps.Input.set_attack_held(true) attackOwned = true end
	else releaseAttack() end
end

local function skillsStep()
	if not (state.AutoSkills and inCampaign() and alive() and target) or os.clock() < nextSkill
		or os.clock() < defenseUntil or heldByGame() or has(localEntity, C.Banners) or has(localEntity, C.Stun) or has(localEntity, C.Dash) then return end
	local equipped = world:get(localEntity, C.EquippedWeapon)
	if not equipped or has(equipped, C.Attack) or has(equipped, C.Skill) or has(equipped, C.Activated) then return end
	for _ = 1, 2 do
		local slot = skillSlot
		skillSlot = skillSlot % 2 + 1
		if deps.Ability.takes_press(world, localEntity, slot) then
			releaseAttack()
			world:set(equipped, C.Activated, { timestamp = os.clock(), inner = {
				activation_type = slot == 1 and deps.ActivationType.SkillOne or deps.ActivationType.SkillTwo,
				aim_position = target.Root.Position,
			} })
			nextSkill = os.clock() + 0.35
			bump("Skills")
			return
		end
	end
end

local function bannerBuild(): any
	local upgrades = world:get(localEntity, C.BannerUpgrades) or {}
	local weaponEntity = world:get(localEntity, C.EquippedWeapon)
	local weapon = weaponEntity and world:contains(weaponEntity) and world:get(weaponEntity, C.Weapon)
	local stats = weapon and weapon.stats or {}
	local health = world:get(localEntity, C.Health)
	local energy = world:get(localEntity, C.Energy)
	local skills, energyDemand = 0, 0
	for _, skill in weapon and weapon.skills or {} do
		if type(skill.cooldown) == "number" and skill.cooldown > 0 then
			skills += 1
			energyDemand += math.max(0, skill.energy_cost or 0) / skill.cooldown
		end
	end
	local elements = {}
	for _, element in { "Flame", "Frost", "Poison" } do
		elements[element] = (stats.Elements and stats.Elements[element] or 0)
			+ deps.Ring.get_stat_boost(world, weaponEntity or localEntity, element .. "Element")
	end
	local soul = deps.Spirit.is_soul_boosted(world, localEntity)
	local spiritConfig = deps.SpiritConfig
	local held = deps.Spirit.get_held(world, localEntity)
	local capacity = deps.Spirit.get_capacity(world, localEntity)
	return {
		Upgrades = upgrades,
		Health = health and math.clamp(health.value / math.max(health.max, 1), 0, 1) or 1,
		Energy = energy and math.clamp(energy.value / math.max(energy.max, 1), 0, 1) or 1,
		EnergyDemand = energyDemand / math.max(energy and energy.fill_rate or 1, 0.1),
		Skills = skills, AutoSkills = state.AutoSkills, InfiniteDash = state.InfiniteDash,
		Defending = state.AutoParry or state.AutoDodge, Farming = state.AutoFarm,
		CriticalChance = (stats.CriticalChance or 0) + deps.Ring.get_stat_boost(world, weaponEntity or localEntity, "CriticalChance"),
		CriticalBonus = deps.Damage.CRIT_BONUS * deps.Enchant.get_stat_multiplier(world, weaponEntity or localEntity, "CritDamage"),
		DodgeChance = deps.Ring.get_stat_boost(world, localEntity, "DodgeChance"),
		Elements = elements, SpiritCapacity = capacity, SpiritCount = math.max(#held, capacity * 0.65),
		SpiritWeight = soul and spiritConfig.soul_armor.small_speed_boost or spiritConfig.speed_boost.Small,
		SpiritDamage = deps.Enchant.get_stat_multiplier(world, weaponEntity or localEntity, "SpiritDamage")
			* (soul and spiritConfig.soul_armor.rage_damage_multiplier or 1),
		SpiritHeal = deps.Enchant.get_stat_multiplier(world, localEntity, "SpiritHeal")
			* (soul and spiritConfig.soul_armor.heal_multiplier or 1),
	}
end

local function scoreBanner(id: string, build: any): number
	local tiers = deps.Banners.tier_modifiers[id]
	if not tiers then return 0.001 end
	local level = math.max(0, math.floor(tonumber(build.Upgrades[id]) or 0))
	local nextTier = tiers[level + 1]
	if not nextTier then return -math.huge end
	local current = tiers[level] or {}
	local function delta(key: string): number
		return (nextTier[key] or 0) - (current[key] or 0)
	end
	local function modifier(banner: string, key: string): number
		local values = deps.Banners.tier_modifiers[banner]
		local value = values and values[build.Upgrades[banner] or 0]
		return value and value[key] or 0
	end
	local urgency = math.clamp((0.7 - build.Health) / 0.7, 0, 1)
	if id == "Agility" then
		local dodge = math.clamp(build.DodgeChance + (current.dodge_chance or 0), 0, 1)
		local extraDodge = math.min(delta("dodge_chance"), 1 - dodge)
		return delta("attack_speed_percent") / (1 + (current.attack_speed_percent or 0)) * 100
			+ extraDodge / math.max(1 - dodge, 0.1) * (30 + urgency * 90)
	elseif id == "CriticalBoost" then
		local chance = math.clamp(build.CriticalChance + (current.critical_chance or 0), 0, 1)
		local extra = math.min(delta("critical_chance"), 1 - chance)
		return extra * build.CriticalBonus / (1 + chance * build.CriticalBonus) * 100
	elseif id == "Recovery" then
		if build.Skills == 0 then return 0 end
		return delta("cooldown_reduction_percent") / math.max(0.1, 1 - (current.cooldown_reduction_percent or 0))
			* (build.AutoSkills and 85 or 55) * math.min(1, build.Skills / 2 + 0.5)
	elseif id == "HealthBoost" then
		return delta("health_percent") / (1 + (current.health_percent or 0)) * (35 + urgency * 200)
	elseif id == "LifeSteal" then
		return delta("health_percent") * (100 + urgency * 1100) * build.SpiritHeal
	elseif id == "Stamina" then
		local demand = math.clamp(build.EnergyDemand, 0, 2)
		local need = build.Skills > 0 and (0.7 + demand + (1 - build.Energy) * 1.5) or 0.35
		if not build.InfiniteDash then need += 0.35 end
		return (delta("max_energy") / (1 + (current.max_energy or 0)) * 10
			+ delta("energy_regen") / (1 + (current.energy_regen or 0)) * 15) * need
	elseif id == "ElementCircle" then
		local before = current.interval_seconds and 1 / current.interval_seconds or 0
		local after = 1 / nextTier.interval_seconds
		local synergy = modifier("FlameElement", "bonus_stacks") + modifier("FrostElement", "bonus_stacks") + modifier("PoisonElement", "bonus_stacks")
		return (after - before) * (18 + math.min(synergy, 2) * 3)
	elseif id == "FlameElement" or id == "FrostElement" or id == "PoisonElement" then
		local element = id:gsub("Element$", "")
		local existing = (build.Elements[element] or 0) + (current.bonus_stacks or 0)
		local weight = element == "Flame" and 0.55 or element == "Frost" and (0.38 + urgency * 0.3) or (0.45 + urgency * 0.4)
		local circle = math.min(build.Upgrades.ElementCircle or 0, 4)
		return delta("bonus_stacks") / (1 + existing) * 100 * weight * (1 + circle * 0.08)
	elseif id == "RageSpirits" then
		local held = build.SpiritCount * build.SpiritWeight * build.SpiritDamage
		return delta("damage_boost_percent") * held / (1 + (current.damage_boost_percent or 0) * held) * 100
	elseif id == "SpiritCapacity" then
		local rage = modifier("RageSpirits", "damage_boost_percent")
		return delta("spirit") * (rage * build.SpiritWeight * build.SpiritDamage * 100 + (build.Farming and 0.5 or 2.5))
	elseif id == "Thorns" then
		return delta("damage_back_multiplier") * (1 + urgency) * (build.Defending and 0.5 or 1)
	end
	return 0.001
end

local function chooseBanner(offer: {string}, build: any): (string?, number)
	local best, bestScore, bestRank = nil, -math.huge, math.huge
	local ranks = {}
	for index, id in options.BannerPriority do ranks[id] = index end
	for _, id in offer do
		local rank = ranks[id] or math.huge
		local score = options.BannerMode == "Smart" and scoreBanner(id, build) or -rank
		if score > -math.huge and (not best or score > bestScore or score == bestScore and rank < bestRank) then
			best, bestScore, bestRank = id, score, rank
		end
	end
	if options.BannerMode == "Manual" then best = best or offer[1] end
	return best, bestScore
end

local function bannerStep()
	if not localEntity then return end
	local offer = world:get(localEntity, C.Banners)
	if offer ~= bannerOffer then bannerOffer, pickedOffer, bannerSeenAt = offer, nil, os.clock() end
	if not state.AutoPickBanner or not alive() or not offer or offer == pickedOffer or os.clock() - bannerSeenAt < 1.65 then return end
	local build = options.BannerMode == "Smart" and bannerBuild() or nil
	local best, score = chooseBanner(offer, build)
	if best then
		deps.Network.select_banner.fire(best)
		pickedOffer = offer
		session.LastBanner = { Id = best, Mode = options.BannerMode, Score = score, Tier = build and (build.Upgrades[best] or 0) + 1 }
		bump("BannerPicks")
	end
end

local function reviveStep()
	if not state.AutoRevive or not inCampaign() or not localEntity then return end
	local timer = world:get(localEntity, C.ReviveTimer)
	if not timer then reviveAttempt = nil return end
	local stamp = timer.timestamp or timer
	if reviveAttempt == stamp then return end
	local revives = world:get(localEntity, C.Revives)
	local available = revives and (revives.infinite == true or (revives.count or 0) > 0)
	if not available then available = deps.Gamepass.owns(world, localEntity, deps.GamepassId.VIP) end
	if available then deps.Network.request_revive.fire() reviveAttempt = stamp bump("ReviveRequests") end
end

local function replayStep()
	local vote = world:get(C.RunVote, C.RunVote)
	if not vote then replayAttempt = nil return end
	if not state.AutoReplay or not inCampaign() or vote.resolved or replayAttempt ~= nil then return end
	if vote.kind == deps.RunVoteKind.RaidContinue then return end
	local myVote = vote.votes and vote.votes[tostring(player.UserId)]
	if myVote ~= deps.RunVoteChoice.Replay then deps.Network.run_end_vote.fire(deps.RunVoteChoice.Replay) bump("ReplayVotes") end
	replayAttempt = true
end

local function unlocked(map: string, difficulty: string): boolean
	if not localEntity then return false end
	return deps.Unlock.is_unlocked(world:get(localEntity, C.WorldUnlocks), map, difficulty)
end

local function startStep()
	local place = world:get(C.Place, C.Place)
	if not state.AutoStartRun or not place or place.id ~= "Lobby" or not alive() or os.clock() - startAttemptAt < 3 then return end
	if inventory.Pending or os.clock() < inventory.HoldUntil then return end
	if not unlocked(options.Map, options.Difficulty) then session.Status = "Selected run is locked" return end
	local ownSession: any
	for _, pad in world:query(C.PadSession) do
		if pad.owner_user_id == player.UserId then ownSession = pad break end
	end
	if ownSession then
		if ownSession.phase == deps.PadPhase.Open then
			deps.Network.start_pad_session.fire()
			startAttemptAt = os.clock()
			session.Status = "Launching run"
		end
		return
	end
	local party = world:get(localEntity, C.Party)
	local maxPlayers = party and math.max(1, #party.members) or 1
	deps.Network.create_play_session.fire(options.Map, options.Difficulty, maxPlayers)
	startAttemptAt = os.clock()
	bump("RunStarts")
	session.Status = "Creating run"
end

local function bestFishingHole(): (any, any, number)
	local best, bestData = nil, nil
	local bestBoost, bestDistance = -math.huge, math.huge
	local config = deps.FishingConfig.circles
	for entity, circle in world:query(C.EnchantCircle) do
		local boost = config.boosts[circle.rarity]
		if type(boost) == "number" and typeof(circle.position) == "Vector3" and circle.radius > 0 then
			local distance = ((circle.position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
			if boost > bestBoost or boost == bestBoost and distance < bestDistance then
				best, bestData, bestBoost, bestDistance = entity, circle, boost, distance
			end
		end
	end
	return best, bestData, bestBoost
end

local function prepareFishingHole(now: number, rod: any): boolean
	if fishing.HomeRoot and fishing.HomeRoot ~= root then clearFishingSpot(false) end
	if now >= fishing.NextScan or not fishing.Hole or not has(fishing.Hole, C.EnchantCircle) then
		fishing.NextScan = now + 0.5
		local entity, circle, boost = bestFishingHole()
		if not entity then fishing.ValidCast = false return false end
		if fishing.Hole ~= entity or not fishing.Platform or not fishing.Platform.Parent then
			if not fishing.Home then fishing.Home, fishing.HomeRoot = root.CFrame, root end
			local direction = (fishing.Home.Position - circle.position) * Vector3.new(1, 0, 1)
			if direction.Magnitude < 0.01 then direction = Vector3.new(0, 0, 1) end
			direction = direction.Unit
			local distance = math.min(rod.range - 2, math.clamp(circle.radius * 0.6, 3.5, 8))
			local height = (humanoid and humanoid.HipHeight or 2) + root.Size.Y * 0.5
			local position = circle.position + direction * distance + Vector3.new(0, height, 0)
			local platform = fishing.Platform
			if not platform then
				platform = Instance.new("Part")
				platform.Name = "PixelBladeFishingSupport"
				platform.Size = Vector3.new(4, 1, 4)
				platform.Anchored = true
				platform.Transparency = 1
				platform.CanCollide = true
				platform.CanTouch = false
				platform.CanQuery = false
				fishing.Platform = platform
			end
			platform.CFrame = CFrame.new(position.X, circle.position.Y - 0.5, position.Z)
			platform.Parent = Workspace
			root.CFrame = CFrame.lookAt(position, Vector3.new(circle.position.X, position.Y, circle.position.Z))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			fishing.StandPosition = position
			fishing.Hole = entity
			fishing.NextPress = now + 0.35
			bump("FishingTeleports")
		end
		fishing.HoleData = circle
		fishing.CastDistance = ((circle.position - fishing.StandPosition) * Vector3.new(1, 0, 1)).Magnitude
		fishing.ValidCast = true
		session.FishingLuck = boost
		session.FishingHole = circle.rarity
		session.FishingHolePosition = circle.position
	end
	return fishing.ValidCast
end

local function fishingStep()
	if not state.AutoFishing then return end
	local place = world:get(C.Place, C.Place)
	if not place or place.id ~= "Lobby" then
		stopFishing(false)
		clearFishingSpot(false)
		session.Status = "Waiting for lobby"
		return
	end
	if not alive() then stopFishing(false) clearFishingSpot(false) session.Status = "Waiting for character" return end
	if not deps.FishingUnlock.has_fishing(world:get(localEntity, C.Quests)) then
		session.SetFeature("AutoFishing", false, true)
		notify("Fishing locked", "Complete the fishing tutorial", "Warning")
		return
	end
	local data = world:get(localEntity, C.Fishing)
	local rod = data and deps.FishingConfig.rods[data.equipped_rod]
	if not data or not rod or not data.owned_rods[data.equipped_rod] then
		session.SetFeature("AutoFishing", false, true)
		notify("No fishing rod", nil, "Warning")
		return
	end
	if deps.StashCapacity.is_full(data) then
		session.SetFeature("AutoFishing", false, true)
		notify("Fishing stash full", nil, "Warning")
		return
	end
	local now = os.clock()
	local busy = has(localEntity, C.FishingCharging) or has(localEntity, C.FishingLineOut)
	local phase = fishing.Runtime and fishing.Runtime.phase
	if not busy and (not phase or phase == "idle") and not prepareFishingHole(now, rod) then
		session.Status = "Waiting for luck holes"
		return
	end
	if fishing.Platform and fishing.StandPosition and (root.Position - fishing.StandPosition).Magnitude > 2 then
		local point = fishing.StandPosition
		local center = fishing.HoleData.position
		root.CFrame = CFrame.lookAt(point, Vector3.new(center.X, point.Y, center.Z))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	if not has(localEntity, C.RodHeld) then
		session.Status = "Equipping fishing rod"
		if now >= fishing.NextAction then
			deps.Network.toggle_rod.fire()
			fishing.Engaged = true
			fishing.NextAction = now + 2
		end
		return
	end
	fishing.Engaged = true
	if deps.Cutscene.is_holding_player(world, context) or has(localEntity, C.ManningStation)
		or has(localEntity, C.VaultMinigame) or has(localEntity, C.CrystalAiming) then
		stopFishing(false)
		session.Status = "Waiting for scene"
		return
	end
	local engine = fishing.Runtime
	local ui = engine and rawget(engine, "minigame")
	local container = type(ui) == "table" and rawget(ui, "container")
	if not engine or typeof(container) ~= "Instance" or not container.Parent then
		fishing.Runtime = nil
		if now >= fishing.NextRuntimeScan then
			fishing.NextRuntimeScan = now + 0.5
			for _, value in getgc(true) do
				if type(value) == "table" and rawget(value, "ghost_progress") ~= nil and rawget(value, "reel_count") ~= nil then
					local screen = rawget(value, "minigame")
					local frame = type(screen) == "table" and rawget(screen, "container")
					if typeof(frame) == "Instance" and frame.Parent then fishing.Runtime = value break end
				end
			end
		end
		engine = fishing.Runtime
	end
	if not engine then session.Status = "Connecting fishing" return end
	if engine.auto then deps.FishingIntents.auto_off:Fire(now) end
	session.FishingPhase = engine.phase
	if now < fishing.NextAction or now < fishing.NextPress then return end
	if engine.phase == "idle" then
		deps.Input.skill_one:Fire(now)
		fishing.NextPress = now + 0.18
		bump("FishingCasts")
	elseif engine.phase == "charging" then
		local circle = fishing.Hole and has(fishing.Hole, C.EnchantCircle) and world:get(fishing.Hole, C.EnchantCircle)
		if not circle then
			engine.valid = false
			deps.Input.skill_one_up:Fire(now)
			fishing.NextScan = 0
			fishing.NextPress = now + 0.15
			return
		end
		if engine.charge_distance >= fishing.CastDistance then
			local center = circle.position
			local direction = (center - root.Position) * Vector3.new(1, 0, 1)
			if direction.Magnitude > 0.01 then direction = direction.Unit else direction = Vector3.new(0, 0, 1) end
			local result = Workspace:Raycast(center, Vector3.new(0, -100, 0), fishingRay)
			engine.landing = center
			engine.direction = direction
			engine.valid = result == nil or result.Material == Enum.Material.Water
			if engine.bob and engine.bob.Parent then engine.bob.CFrame = CFrame.lookAt(center, center + direction) end
			deps.Input.skill_one_up:Fire(now)
			fishing.NextPress = now + 0.08
		end
	elseif engine.phase == "bubbles" then
		if not engine.holding then
			deps.FishingIntents.bubble_down:Fire(now)
		else
			engine.progress = 0.95
			engine.direction_changes = 0
			engine.fill_direction = 1
			deps.FishingIntents.bubble_up:Fire(now)
			bump("PerfectBubbles")
		end
		fishing.NextPress = now + 0.06
	elseif engine.phase == "reel" then
		for _ = 1, math.clamp(engine.reel_count, 0, 10) do deps.FishingIntents.reel_press:Fire(now) end
		fishing.NextPress = now + 0.1
	end
	local luck = session.FishingLuck and string.format(" / +%d%% Luck", math.round(session.FishingLuck * 100)) or ""
	session.Status = (engine.phase == "waiting" and "Waiting for bite" or "Fishing") .. luck .. " / " .. tostring(session.Diagnostics.FishingCatches) .. " caught"
end

local function inventoryLabel(control: any, text: string)
	if control and control:Get() ~= text then control:Set(text) end
end

local function itemName(id: string, kind: string): string
	local value = deps.DropModel.display_name(id, kind)
	if type(value) == "table" then return tostring(value.source or id) end
	return tostring(value or id)
end

local function chestName(id: string): string
	return deps.ChestLabels.display_name(id) or id
end

local function refreshChestNames()
	if not localEntity or not controls.ChestType or controls.ChestType.Open then return end
	local choices, seen = {}, { ["All Owned"] = true }
	for id, count in world:get(localEntity, C.Loot) or {} do
		if type(count) == "number" and count > 0 and deps.Chests.chests[id] then
			local name = chestName(id)
			if not seen[name] then seen[name] = true table.insert(choices, name) end
		end
	end
	for _, name in options.ChestNames do
		if not seen[name] and session.ChestFamilies[name] then seen[name] = true table.insert(choices, name) end
	end
	table.sort(choices)
	table.insert(choices, 1, "All Owned")
	local signature = table.concat(choices, "\n")
	if signature ~= inventory.ChestChoices then
		controls.ChestType:Refresh(choices, true)
		controls.ChestType:Set(options.ChestNames, true)
		inventory.ChestChoices = signature
	end
end

local function upgradeCandidate(): any
	local equippedWeapon = world:get(localEntity, C.EquippedWeapon)
	local equippedArmor = world:get(localEntity, C.EquippedArmor)
	local rows = {}
	for entity, item in world:query(C.Item) do
		if world:parent(entity) ~= localEntity or (item.type ~= "Weapon" and item.type ~= "Armor") then continue end
		local equipped = entity == equippedWeapon or entity == equippedArmor
		if options.UpgradeScope == "Equipped" and not equipped then continue end
		if options.UpgradeScope == "Weapons" and item.type ~= "Weapon" then continue end
		if options.UpgradeScope == "Armor" and item.type ~= "Armor" then continue end
		local requirement = deps.Upgrade.get_upgrade_requirement(world, entity)
		if not requirement.resolved or not requirement.can_upgrade or requirement.maxed then continue end
		local signature = tostring(item.tier) .. ":" .. tostring(item.count) .. ":" .. tostring(requirement.current_coins)
		if inventory.UpgradeBlocked[entity] == signature then continue end
		local serverEntity = context.replicator:get_server_entity(entity)
		if serverEntity then
			table.insert(rows, { Entity = entity, Item = item, Requirement = requirement, ServerEntity = serverEntity,
				Signature = signature, Equipped = equipped, Rarity = rarityRanks[requirement.rarity] or 0 })
		end
	end
	table.sort(rows, function(a, b)
		if a.Equipped ~= b.Equipped then return a.Equipped end
		if a.Rarity ~= b.Rarity then return a.Rarity > b.Rarity end
		if a.Requirement.needed_coins ~= b.Requirement.needed_coins then return a.Requirement.needed_coins < b.Requirement.needed_coins end
		if a.Item.id ~= b.Item.id then return a.Item.id < b.Item.id end
		return a.Entity < b.Entity
	end)
	return rows[1]
end

local function chestCandidate(): (string?, number)
	local loot = world:get(localEntity, C.Loot) or {}
	local best, bestRank = nil, math.huge
	for id, count in loot do
		local config = deps.Chests.chests[id]
		if type(count) ~= "number" or count < 1 or not config then continue end
		if not table.find(options.ChestNames, "All Owned") and not table.find(options.ChestNames, chestName(id)) then continue end
		if inventory.ChestBlocked[id] == count then continue end
		local rank = (rarityRanks[config.rarity] or 9) * 10 + (deps.ChestLabels.tier(id) or 1)
		if rank < bestRank or rank == bestRank and (not best or id < best) then best, bestRank = id, rank end
	end
	return best, best and loot[best] or 0
end

local function chestResult(pulls: any, coins: any)
	if type(pulls) ~= "table" then return end
	local pending = inventory.Pending
	local ownedRequest = pending and pending.Kind == "Chest"
	local grouped, rows = {}, {}
	for _, drop in pulls do
		if type(drop) ~= "table" or type(drop.id) ~= "string" or type(drop.type) ~= "string" or type(drop.count) ~= "number" or drop.count <= 0 then continue end
		local key = drop.type .. ":" .. drop.id .. ":" .. tostring(drop.rarity)
		local row = grouped[key]
		if not row then
			row = { Id = drop.id, Type = drop.type, Name = itemName(drop.id, drop.type), Rarity = drop.rarity, Count = 0 }
			grouped[key] = row
			table.insert(rows, row)
		end
		row.Count += drop.count
	end
	table.sort(rows, function(a, b)
		local rankA, rankB = rarityRanks[a.Rarity] or 0, rarityRanks[b.Rarity] or 0
		if rankA ~= rankB then return rankA > rankB end
		return a.Name < b.Name
	end)
	local lines = {}
	if ownedRequest then table.insert(lines, chestName(pending.Id)) end
	for _, row in rows do
		table.insert(lines, row.Name .. " x" .. tostring(row.Count) .. (row.Rarity and " [" .. row.Rarity .. "]" or ""))
	end
	local reward = type(coins) == "number" and coins or 0
	if reward > 0 then table.insert(lines, "Coins +" .. tostring(reward)) end
	if #lines == 0 then table.insert(lines, "No items") end
	session.LastChest = { Id = ownedRequest and pending.Id or nil, Items = rows, Coins = reward }
	controls.ChestDrops:Set(table.concat(lines, "\n"))
	if ownedRequest then
		inventory.Pending = nil
		inventory.LastKind = "Chest"
		inventory.NextScan = os.clock() + 0.5
		inventory.HoldUntil = os.clock() + 0.8
		bump("ChestsOpened")
		inventoryLabel(controls.ChestStatus, "Opened " .. chestName(pending.Id))
	end
end

local function inventoryStep()
	local now = os.clock()
	local pending = inventory.Pending
	if pending then
		if pending.Kind == "Upgrade" then
			local item = world:contains(pending.Entity) and world:get(pending.Entity, C.Item)
			if item and item.tier > pending.Tier then
				inventory.Pending = nil
				inventory.LastKind = "Upgrade"
				inventory.NextScan = now + 0.4
				inventory.HoldUntil = now + 0.7
				inventory.LastUpgrade = pending.Name .. " / T" .. tostring(item.tier)
				bump("ItemUpgrades")
				inventoryLabel(controls.UpgradeStatus, "Upgraded " .. inventory.LastUpgrade)
				return
			end
		end
		if now < pending.Deadline then return end
		if pending.Kind == "Upgrade" then
			inventory.UpgradeBlocked[pending.Entity] = pending.Signature
			inventoryLabel(controls.UpgradeStatus, "Upgrade not confirmed")
		else
			local loot = world:get(localEntity, C.Loot) or {}
			inventory.ChestBlocked[pending.Id] = loot[pending.Id] or 0
			inventoryLabel(controls.ChestStatus, "No chest response")
		end
		inventory.Pending = nil
		inventory.NextScan = now + 1
	end
	if not (state.AutoUpgradeItems or state.AutoOpenChests) or now < inventory.NextScan then return end
	inventory.NextScan = now + 0.5
	local place = world:get(C.Place, C.Place)
	if not place or place.id ~= "Lobby" or not alive() then
		if state.AutoUpgradeItems then inventoryLabel(controls.UpgradeStatus, "Waiting for lobby") end
		if state.AutoOpenChests then inventoryLabel(controls.ChestStatus, "Waiting for lobby") end
		return
	end
	local upgrade = state.AutoUpgradeItems and upgradeCandidate()
	local chest, count
	if state.AutoOpenChests then chest, count = chestCandidate() end
	if upgrade and (not chest or inventory.LastKind == "Chest") then
		local item = upgrade.Item
		local name = itemName(item.id, item.type .. "Id")
		inventory.Pending = { Kind = "Upgrade", Entity = upgrade.Entity, Tier = item.tier, Signature = upgrade.Signature, Name = name, Deadline = now + 8 }
		inventory.HoldUntil = now + 9
		inventoryLabel(controls.UpgradeStatus, "Upgrading " .. name .. " / T" .. tostring(upgrade.Requirement.next_tier))
		bump("UpgradeRequests")
		deps.Network.upgrade_item.fire(upgrade.ServerEntity)
	elseif chest then
		inventory.Pending = { Kind = "Chest", Id = chest, Count = count, Deadline = now + 10 }
		inventory.HoldUntil = now + 11
		inventoryLabel(controls.ChestStatus, "Opening " .. chestName(chest))
		bump("ChestRequests")
		deps.Network.open_chest.fire(chest, 1)
	else
		if state.AutoUpgradeItems then inventoryLabel(controls.UpgradeStatus, inventory.LastUpgrade and "Last: " .. inventory.LastUpgrade or "No affordable upgrades") end
		if state.AutoOpenChests then inventoryLabel(controls.ChestStatus, #options.ChestNames == 0 and "Select chest names" or "No matching chests") end
	end
end

local function visualsStep()
	if not (state.EnemyChams or state.EnemyInfo) or not inCampaign() then
		if next(session.Overlay) then clearOverlays() end
		return
	end
	local present = {}
	for _, row in enemyRows do
		if row.Distance <= options.InfoDistance then
			local entity = row.Entity
			present[entity] = true
			local record = session.Overlay[entity]
			if record and record.Model ~= row.Model then
				if record.Highlight then record.Highlight:Destroy() end
				if record.Billboard then record.Billboard:Destroy() end
				record = nil
			end
			if not record then record = { Model = row.Model } session.Overlay[entity] = record end
			if state.EnemyChams and not record.Highlight then
				local highlight = Instance.new("Highlight")
				highlight.Name = "PixelBladeEnemy"
				highlight.Adornee = row.Model
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.FillColor = row.Boss and Color3.fromRGB(255, 105, 95) or Color3.fromRGB(255, 187, 66)
				highlight.OutlineColor = highlight.FillColor
				highlight.FillTransparency = 0.72
				highlight.OutlineTransparency = 0.08
				highlight.Parent = session.VisualFolder
				record.Highlight = highlight
			elseif not state.EnemyChams and record.Highlight then record.Highlight:Destroy() record.Highlight = nil end
			if state.EnemyInfo and not record.Billboard then
				local billboard = Instance.new("BillboardGui")
				billboard.Name = "PixelBladeEnemyInfo"
				billboard.Size = UDim2.fromOffset(220, 48)
				billboard.StudsOffsetWorldSpace = Vector3.new(0, row.Model:GetExtentsSize().Y * 0.5 + 1.5, 0)
				billboard.AlwaysOnTop = true
				billboard.MaxDistance = options.InfoDistance
				billboard.Adornee = row.Root
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.GothamMedium
				label.TextSize = 13
				label.TextColor3 = row.Boss and Color3.fromRGB(255, 151, 132) or Color3.fromRGB(255, 243, 213)
				label.TextStrokeTransparency = 0.25
				label.TextWrapped = true
				label.Parent = billboard
				billboard.Parent = player:WaitForChild("PlayerGui")
				record.Billboard, record.Label = billboard, label
			elseif not state.EnemyInfo and record.Billboard then record.Billboard:Destroy() record.Billboard = nil end
			if record.Billboard then
				local name = deps.EnemyInfo.display_name[row.Enemy.id] or row.Enemy.id
				local hp = row.Health
				local shield = (hp.shield or 0) > 0 and string.format(" +%d shield", math.ceil(hp.shield)) or ""
				local text = string.format("%s%s\n%d / %d HP%s  ·  %d studs", row.Boss and "★ " or "", name, math.ceil(math.max(hp.value, 0)), math.ceil(hp.max), shield, math.floor(row.Distance))
				if record.Label.Text ~= text then record.Label.Text = text end
				record.Billboard.Adornee = row.Root
				record.Billboard.MaxDistance = options.InfoDistance
			end
		end
	end
	for entity, record in session.Overlay do
		if not present[entity] then
			if record.Highlight then record.Highlight:Destroy() end
			if record.Billboard then record.Billboard:Destroy() end
			session.Overlay[entity] = nil
		end
	end
end

local function copyText(value: string?)
	if not value then return end
	local clipboard = setclipboard or toclipboard
	if type(clipboard) == "function" then
		local ok, reason = pcall(clipboard, value)
		if ok then notify("Copied") else report("Clipboard", reason) end
	elseif window then
		window:Dialog({ Title = "Copy link", Content = value, Buttons = { { Title = "Close" } } })
	end
end

local narrowBar: any
local navigation = {}
local sidebar: any, sidebarDivider: any
function session.FitWindow(viewportOverride: Vector2?)
	if not window or not session.Alive then return end
	local viewport = viewportOverride or window.Gui.AbsoluteSize
	if viewport.X < 1 or viewport.Y < 1 then return end
	local width = math.max(280, math.min(660, viewport.X - 24))
	local height = math.max(220, math.min(540, viewport.Y - 28))
	local narrow = width < 560
	window.Root.Size = UDim2.fromOffset(width, height)
	if sidebar then sidebar.Visible = not narrow end
	if sidebarDivider then sidebarDivider.Visible = not narrow end
	if narrowBar then narrowBar.Visible = narrow end
	window.Content.Position = narrow and UDim2.fromOffset(0, 44) or UDim2.fromOffset(171, 0)
	window.Content.Size = narrow and UDim2.new(1, 0, 1, -44) or UDim2.new(1, -171, 1, 0)
	window:_fitToScreen(true)
	window:_clampToScreen()
	local pill = window.OpenButton
	if pill then
		pill.Size = UDim2.new(pill.Size.X.Scale, pill.Size.X.Offset, 0, 44)
		local position = pill.AbsolutePosition - window.Gui.AbsolutePosition
		pill.AnchorPoint = Vector2.zero
		pill.Position = UDim2.fromOffset(math.clamp(position.X, 0, math.max(0, viewport.X - pill.AbsoluteSize.X)), math.clamp(position.Y, 0, math.max(0, viewport.Y - 44)))
	end
	session.NarrowLayout = narrow
end

local function refreshRunOptions()
	if not session.Ready or not controls.Map then return end
	local labels = {}
	local mapByLabel = {}
	for _, id in campaignOrder do
		local text = id:gsub("(%l)(%u)", "%1 %2") .. (unlocked(id, options.Difficulty) and "" or " (Locked)")
		table.insert(labels, text)
		mapByLabel[text] = id
	end
	session.MapLabels = mapByLabel
	controls.Map:Refresh(labels, true)
	for label, id in mapByLabel do if id == options.Map then controls.Map:Set(label, true) break end end
	local difficulties = {}
	for _, id in { "Normal", "Heroic", "Nightmare" } do
		table.insert(difficulties, id .. (unlocked(options.Map, id) and "" or " (Locked)"))
	end
	controls.Difficulty:Refresh(difficulties, true)
	controls.Difficulty:Set(options.Difficulty .. (unlocked(options.Map, options.Difficulty) and "" or " (Locked)"), true)
end

local function buildUI()
	local librarySource, reason = fetch(LIBRARY_URL)
	assert(librarySource, "Airflow could not be downloaded: " .. tostring(reason))
	local loader, compileError = loadstring(librarySource, "@PixelBladeAirflow")
	assert(loader, compileError)
	airflow = loader()
	airflow:AddTheme("PixelBladeAmber", {
		Background = Color3.fromRGB(20, 19, 15), Surface = Color3.fromRGB(26, 24, 18),
		Surface2 = Color3.fromRGB(32, 29, 22), Surface3 = Color3.fromRGB(46, 40, 28),
		Stroke = Color3.fromRGB(54, 47, 32), StrokeHover = Color3.fromRGB(101, 82, 42),
		Accent = Color3.fromRGB(255, 188, 64), AccentDark = Color3.fromRGB(34, 25, 11),
		Text = Color3.fromRGB(241, 237, 225), Muted = Color3.fromRGB(158, 150, 132),
		Glow = Color3.fromRGB(238, 199, 117),
	})
	window = airflow:CreateWindow({ Name = "Pixel Blade", LoadingSubtitle = "PvE", Icon = "swords", Theme = "PixelBladeAmber",
		ToggleUIKeybind = options.MenuKey, Size = UDim2.fromOffset(660, 540), MinSize = Vector2.new(280, 220),
		MaxSize = Vector2.new(1000, 750), KeepOnScreen = true, MaxNotifications = 3,
		OpenButton = { Title = "Pixel Blade", Icon = "swords" }, Loading = false, Parent = player:WaitForChild("PlayerGui") })
	session.Window = window
	window.Gui.IgnoreGuiInset = false
	window.Gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local automation = window:CreateTab({ Name = "Automation", Icon = "play" })
	local combat = window:CreateTab({ Name = "Combat", Icon = "swords" })
	local visuals = window:CreateTab({ Name = "Visuals", Icon = "eye" })
	local settings = window:CreateTab({ Name = "Settings", Icon = "settings" })
	local function toggle(tab: any, name: string, key: string, description: string?)
		controls[key] = tab:CreateToggle({ Name = name, Default = state[key], Desc = description,
			Callback = function(value: boolean) session.SetFeature(key, value) end })
	end
	automation:CreateSection("Run")
	toggle(automation, "Auto Farm", "AutoFarm", "Enables the full run cycle")
	controls.Status = automation:CreateLabel({ Text = "Connecting" })
	controls.Map = automation:CreateDropdown({ Name = "Map", Options = campaignOrder, Default = options.Map,
		Callback = function(label: string)
			local id = session.MapLabels and session.MapLabels[label] or label
			if campaignSet[id] and unlocked(id, options.Difficulty) then options.Map = id savePreferences()
			else notify("Map locked", nil, "Warning") end
			refreshRunOptions()
		end })
	controls.Difficulty = automation:CreateDropdown({ Name = "Difficulty", Options = { "Normal", "Heroic", "Nightmare" }, Default = options.Difficulty,
		Callback = function(label: string)
			local id = label:gsub(" %(Locked%)$", "")
			if unlocked(options.Map, id) then options.Difficulty = id savePreferences()
			else notify("Difficulty locked", nil, "Warning") end
			refreshRunOptions()
		end })
	toggle(automation, "Auto Start Run", "AutoStartRun")
	toggle(automation, "Auto Replay", "AutoReplay")
	toggle(automation, "Auto Revive", "AutoRevive", "Uses available revives")
	automation:CreateSection("Inventory")
	toggle(automation, "Auto Upgrade Items", "AutoUpgradeItems", "Uses coins and copies")
	controls.UpgradeScope = automation:CreateDropdown({ Name = "Upgrade Scope", Options = { "All Items", "Equipped", "Weapons", "Armor" }, Default = options.UpgradeScope,
		Callback = function(value: string) options.UpgradeScope = value inventory.NextScan = 0 savePreferences() end })
	controls.UpgradeStatus = automation:CreateLabel({ Text = "Idle" })
	controls.ChestType = automation:CreateDropdown({ Name = "Chest Names", Multi = true, Options = { "All Owned" }, Default = options.ChestNames, Placeholder = "Select chests",
		Callback = function(values: {string})
			local selected = table.clone(values)
			if table.find(selected, "All Owned") and #selected > 1 then
				if table.find(options.ChestNames, "All Owned") then
					table.remove(selected, table.find(selected, "All Owned"))
				else selected = { "All Owned" } end
			end
			options.ChestNames = selected
			controls.ChestType:Set(selected, true)
			inventory.NextScan = 0
			savePreferences()
		end })
	toggle(automation, "Auto Open Chests", "AutoOpenChests", "Opens owned chests")
	controls.ChestDrops = automation:CreateParagraph({ Name = "Last Chest", Content = "None yet" })
	controls.ChestStatus = automation:CreateLabel({ Text = "Idle" })
	automation:CreateSection("Fishing")
	toggle(automation, "Auto Fishing", "AutoFishing", "Teleports to the highest luck hole")
	automation:CreateSection("Banners")
	toggle(automation, options.BannerMode == "Smart" and "Smart Auto Pick Banner" or "Auto Pick Banner", "AutoPickBanner")
	local manualBannerControls = {}
	local function showBannerMode()
		local manual = options.BannerMode == "Manual"
		controls.AutoPickBanner:SetTitle(manual and "Auto Pick Banner" or "Smart Auto Pick Banner")
		for _, control in manualBannerControls do control:SetVisible(manual) end
	end
	controls.BannerMode = automation:CreateDropdown({ Name = "Banner Mode", Options = { "Smart", "Manual" }, Default = options.BannerMode,
		Callback = function(value: string)
			options.BannerMode = value == "Manual" and "Manual" or "Smart"
			showBannerMode()
			savePreferences()
		end })
	controls.Priority = automation:CreateParagraph({ Name = "Priority", Content = "Loading" })
	controls.Banner = automation:CreateDropdown({ Name = "Banner", Options = {}, Placeholder = "Select" })
	table.insert(manualBannerControls, controls.Priority)
	table.insert(manualBannerControls, controls.Banner)
	local function updatePriority()
		local names = {}
		for index, id in options.BannerPriority do names[index] = tostring(index) .. ". " .. (deps.Banners.name[id] or id) end
		controls.Priority:Set(table.concat(names, "\n"))
	end
	session.UpdatePriority = updatePriority
	local function shiftPriority(direction: number)
		local selected = controls.Banner:Get()
		local id = session.BannerLabels and session.BannerLabels[selected]
		local index = id and table.find(options.BannerPriority, id)
		if not index then return end
		local destination = math.clamp(index + direction, 1, #options.BannerPriority)
		options.BannerPriority[index], options.BannerPriority[destination] = options.BannerPriority[destination], options.BannerPriority[index]
		updatePriority()
		savePreferences()
	end
	table.insert(manualBannerControls, automation:CreateButton({ Name = "Move Up", Icon = "arrow-up", Callback = function() shiftPriority(-1) end }))
	table.insert(manualBannerControls, automation:CreateButton({ Name = "Move Down", Icon = "arrow-down", Callback = function() shiftPriority(1) end }))
	showBannerMode()
	combat:CreateSection("Attacks")
	toggle(combat, "Kill Aura", "KillAura")
	controls.AuraRadius = combat:CreateSlider({ Name = "Aura Radius", Min = 5, Max = 50, Step = 1, Default = options.AuraRadius,
		Callback = function(value: number) options.AuraRadius = value savePreferences() end })
	toggle(combat, "Auto Skills", "AutoSkills")
	combat:CreateSection("Defense")
	toggle(combat, "Auto Parry", "AutoParry")
	toggle(combat, "Auto Dodge", "AutoDodge")
	toggle(combat, "Infinite Dash", "InfiniteDash")
	visuals:CreateSection("Enemies")
	toggle(visuals, "Enemy Chams", "EnemyChams")
	toggle(visuals, "Enemy Info", "EnemyInfo")
	controls.InfoDistance = visuals:CreateSlider({ Name = "Render Distance", Min = 25, Max = 1000, Step = 25, Default = options.InfoDistance,
		Callback = function(value: number) options.InfoDistance = value savePreferences() end })
	settings:CreateSection("Session")
	toggle(settings, "Anti AFK", "AntiAfk")
	settings:CreateButton({ Name = "Stop All", Icon = "square", Callback = function() session.StopAll() end })
	controls.MenuKey = settings:CreateKeybind({ Name = "Menu Keybind", Default = options.MenuKey,
		OnChanged = function(key: any)
			if not key or key == Enum.KeyCode.Escape or key == Enum.KeyCode.Return then
				controls.MenuKey:Set(options.MenuKey, true)
				return
			end
			options.MenuKey = key.Name
			window:SetKeybind(key)
			savePreferences()
		end })
	settings:CreateButton({ Name = "Unload", Icon = "power", Callback = session.Unload })
	settings:CreateSection("Credits")
	controls.Credits = settings:CreateButton({ Name = "Credits - Loading...", Icon = "copy", Callback = function() copyText(session.Credits) end })
	settings:CreateButton({ Name = "UI Library - Airflow", Icon = "copy", Callback = function() copyText(LIBRARY_PAGE) end })
	controls.Compatibility = settings:CreateLabel({ Text = "Connecting" })
	sidebar = window.Body:FindFirstChild("Sidebar")
	for _, child in window.Body:GetChildren() do
		if child:IsA("Frame") and child.Position.X.Offset == 170 and child.Size.X.Offset == 1 then sidebarDivider = child end
	end
	narrowBar = Instance.new("Frame")
	narrowBar.Name = "PixelBladeNavigation"
	narrowBar.Size = UDim2.new(1, -16, 0, 44)
	narrowBar.Position = UDim2.fromOffset(8, 0)
	narrowBar.BackgroundTransparency = 1
	narrowBar.Visible = false
	narrowBar:SetAttribute("NoDrag", true)
	for index, tab in { automation, combat, visuals, settings } do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0.25, -2, 1, 0)
		button.Position = UDim2.new((index - 1) / 4, 0, 0, 0)
		button.BackgroundTransparency = 1
		button.Text = index == 1 and "Auto" or tab.Name
		button.FontFace = airflow.Fonts.Medium
		button.TextSize = 13
		button.TextColor3 = airflow.Theme.Muted
		button.AutoButtonColor = false
		button.Parent = narrowBar
		connect(button.Activated, function() window:SelectTab(tab) end)
		navigation[tab] = button
	end
	narrowBar.Parent = window.Body
	connect(window.Gui:GetPropertyChangedSignal("AbsoluteSize"), function() session.FitWindow() end)
	task.defer(session.FitWindow)
	task.spawn(function()
		local text = fetch(CREDITS_URL .. "?launch=" .. tostring(DateTime.now().UnixTimestampMillis))
		if not session.Alive then return end
		text = text and text:match("^%s*(.-)%s*$")
		if text and #text > 0 then
			session.Credits = text
			controls.Credits:SetTitle("Credits - " .. text:gsub("%s+", " "))
		else controls.Credits:SetTitle("Credits - Unavailable") end
	end)
end

local function initializeGame()
	local modules = {
		Components = "ecs.components", Input = "client.user_input", Room = "room_util", Cutscene = "cutscene_state_util",
		Network = "network", Hurtbox = "hurtbox_query", Hitbox = "hitbox_util", Damage = "damage_util", Stat = "stat_util",
		Gameplay = "configs.gameplay", Ability = "client.ability_slot_util", LocalDash = "client.systems.local_dash",
		Banners = "configs.banner_upgrade_config", EnemyInfo = "configs.enemy_info", Gamepass = "gamepass_util",
		GamepassId = "types.enums.GamepassId", HitboxShape = "types.enums.HitboxShape", DamageType = "types.enums.DamageType",
		WeaponType = "types.enums.WeaponType", ActivationType = "types.enums.ActivationType", RunVoteChoice = "types.enums.RunVoteChoice",
		RunVoteKind = "types.enums.RunVoteKind", PadPhase = "types.enums.PadPhase", Unlock = "world_unlock_util",
		FishingIntents = "client.fishing_intents", FishingConfig = "configs.fishing_config",
		FishingUnlock = "fishing_unlock_util", StashCapacity = "stash_capacity_util",
		Spirit = "spirit_util", SpiritConfig = "configs.spirit_config", Ring = "ring_util", Enchant = "enchant_util",
		Upgrade = "upgrade_util", Chests = "configs.chest_config", ChestLabels = "chest_label_util", DropModel = "client.drops.drop_model_util",
	}
	for name, path in modules do deps[name] = moduleAt(path) end
	C = deps.Components
	assert(type(deps.Input.set_attack_held) == "function" and type(deps.Input.set_blocking) == "function", "Game input changed")
	assert(type(deps.Ability.takes_press) == "function", "Game abilities changed")
	local contextDeadline = os.clock() + 20
	while not findContext() and os.clock() < contextDeadline do task.wait(0.5) end
	assert(context and world, "Game context unavailable; getgc is required")
	updateWorld()
	assert(type(deps.Upgrade.get_upgrade_requirement) == "function" and type(deps.Network.upgrade_item.fire) == "function", "Game upgrades changed")
	assert(type(deps.Chests.chests) == "table" and type(deps.Network.open_chest.fire) == "function", "Game chests changed")
	session.ChestFamilies = {}
	for id in deps.Chests.chests do session.ChestFamilies[chestName(id)] = true end
	if legacyChestType then
		options.ChestNames = { legacyChestType == "All Owned" and "All Owned" or chestName(legacyChestType) }
		legacyChestType = nil
	end
	local selected, seenNames = {}, {}
	for _, name in options.ChestNames do
		if type(name) == "string" and not seenNames[name] and (name == "All Owned" or session.ChestFamilies[name]) then
			table.insert(selected, name)
			seenNames[name] = true
		end
	end
	options.ChestNames = table.find(selected, "All Owned") and { "All Owned" } or selected
	refreshChestNames()
	controls.ChestType:Set(options.ChestNames, true)
	installAdapters()
	local allBanners = {}
	local bannerLabels = {}
	for id, name in deps.Banners.name do table.insert(allBanners, id) bannerLabels[name] = id end
	table.sort(allBanners, function(a, b) return deps.Banners.name[a] < deps.Banners.name[b] end)
	local priority, seen = {}, {}
	for _, id in options.BannerPriority do
		if deps.Banners.name[id] and not seen[id] then table.insert(priority, id) seen[id] = true end
	end
	if #priority == 0 then
		for _, id in { "Agility", "CriticalBoost", "Recovery" } do
			if deps.Banners.name[id] then table.insert(priority, id) seen[id] = true end
		end
	end
	for _, id in allBanners do if not seen[id] then table.insert(priority, id) end end
	options.BannerPriority = priority
	session.BannerLabels = bannerLabels
	local names = {}
	for _, id in allBanners do table.insert(names, deps.Banners.name[id]) end
	controls.Banner:Refresh(names, true)
	controls.Banner:Set(names[1], true)
	session.UpdatePriority()
	local visualFolder = Instance.new("Folder")
	visualFolder.Name = "PixelBladeLocalVisuals"
	visualFolder.Parent = Workspace
	session.VisualFolder = visualFolder
	table.insert(session.Connections, { Disconnect = function() visualFolder:Destroy() end })
	session.Ready = true
	session.Status = "Idle"
	refreshRunOptions()
	local capabilities = {}
	if type(writefile) ~= "function" or type(readfile) ~= "function" then table.insert(capabilities, "Settings: session only") end
	if type(queue_on_teleport or queueonteleport) ~= "function" then
		table.insert(capabilities, "Teleport loader unavailable")
	elseif type(readfile) ~= "function" or type(writefile) ~= "function" then
		table.insert(capabilities, "Teleport state unavailable")
	end
	controls.Compatibility:Set(#capabilities > 0 and table.concat(capabilities, " · ") or "Connected")
	if type(resumed) == "table" then
		for _, name in featureNames do if controls[name] then controls[name]:Set(state[name], true) end end
	end
	connect(deps.Network.hit_denied.event, function() bump("DeniedHits") end)
	connect(deps.Network.replicate_hit.client_event, function(_, hit)
		if hit and hit.source then bump("Hits") end
	end)
	for _, event in { deps.Network.fishing_caught_item.event, deps.Network.fishing_caught_charm.event, deps.Network.fishing_caught_wish.event } do
		connect(event, function() if state.AutoFishing then bump("FishingCatches") end end)
	end
	connect(deps.Network.fishing_denied.event, function()
		if state.AutoFishing then fishing.NextAction = os.clock() + 8 end
	end)
	connect(deps.Network.chest_open_result.event, chestResult)
	connect(player.Idled, function()
		if not session.Alive or not state.AntiAfk then return end
		local ok, reason = pcall(function()
			local virtualUser = game:GetService("VirtualUser")
			virtualUser:CaptureController()
			virtualUser:ClickButton2(Vector2.zero)
		end)
		if not ok then report("Anti AFK", reason) end
	end)
	connect(player.OnTeleport, function(teleportState)
		if session.Alive and teleportState.Name ~= "Failed" then persistTeleport() end
	end)
	connect(game:GetService("TeleportService").TeleportInitFailed, function(who)
		if who == player then startAttemptAt = os.clock() end
	end)
	local elapsed = 0
	local visualElapsed = 0
	local unlockElapsed = 0
	connect(RunService.PreSimulation, function()
		if not session.Alive or not session.Ready then return end
		refillDash()
	end)
	connect(RunService.Heartbeat, function(deltaTime)
		if not session.Alive or not session.Ready then return end
		elapsed += deltaTime
		visualElapsed += deltaTime
		unlockElapsed += deltaTime
		if elapsed < 0.05 then return end
		elapsed = 0
		local ok, reason = xpcall(function()
			if not context.local_player_entity or not world:contains(context.local_player_entity) then
				releaseAttack() releaseBlock()
				if os.clock() > nextConnect then findContext() nextConnect = os.clock() + 2 end
				return
			end
			updateWorld()
			if os.clock() >= defenseUntil then releaseBlock() end
			refillDash()
			bannerStep()
			reviveStep()
			replayStep()
			inventoryStep()
			startStep()
			fishingStep()
			farmStep()
			skillsStep()
			attackStep()
			if visualElapsed >= 0.2 then
				visualElapsed = 0
				visualsStep()
				local text = session.Status
				if controls.Status:Get() ~= text then controls.Status:Set(text) end
				for tab, button in navigation do button.TextColor3 = window.CurrentTab == tab and airflow.Theme.Accent or airflow.Theme.Muted end
			end
			if unlockElapsed >= 2 then
				unlockElapsed = 0
				refreshChestNames()
				local unlocks = world:get(localEntity, C.WorldUnlocks)
				local signature = HttpService:JSONEncode(unlocks or {})
				if signature ~= lastUnlockSignature then lastUnlockSignature = signature refreshRunOptions() end
			end
		end, debug.traceback)
		if not ok then releaseAttack() releaseBlock() report("Game connection", reason) end
	end)
	print("[Pixel Blade] Ready / " .. tostring(game.PlaceId) .. " / " .. tostring(game.PlaceVersion))
end

local interfaceOK, interfaceError = xpcall(buildUI, debug.traceback)
if not interfaceOK then
	warn("[Pixel Blade] Interface failed: " .. tostring(interfaceError))
	session.Unload()
	return
end
local gameOK, gameError = xpcall(initializeGame, debug.traceback)
if not gameOK then
	session.Ready = false
	session.Status = "Game connection unavailable"
	controls.Status:Set(session.Status)
	controls.Compatibility:Set("Game update or executor incompatibility")
	for _, name in featureNames do controls[name]:SetLocked(true, "Unavailable") end
	notify("Game connection unavailable", "See executor console", "Error")
	warn("[Pixel Blade] " .. tostring(gameError))
end

if gameOK then
	do
		local queue = queue_on_teleport or queueonteleport
		persistTeleport()
		if type(queue) == "function" and host.__PixelBladeRemoteQueuedJob ~= game.JobId then
			local ok, reason = pcall(queue, [[
loadstring(game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Scripts/refs/heads/main/pixelblade.luau", true))("teleport")
]])
			if ok then
				host.__PixelBladeRemoteQueuedJob = game.JobId
			else
				controls.Compatibility:Set("Teleport loader unavailable")
				report("Teleport loader", reason)
			end
		end
	end
end

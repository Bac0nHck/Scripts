local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()

if _G.ThrowACoinHub then
	pcall(function()
		_G.ThrowACoinHub:Destroy()
	end)
end
_G.ThrowACoinHub = Fluent

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Assets = ReplicatedStorage:WaitForChild("Assets")
local Events = Assets:WaitForChild("Events")
local Modules = Assets:WaitForChild("Modules")

local Progression = require(Modules:WaitForChild("ProgressionModule"))
local NumberManipulator = require(Modules:WaitForChild("NumberManipulator"))

local CoinThrow = Events:WaitForChild("CoinThrow")
local CoinLanded = Events:WaitForChild("CoinLanded")
local ThrowReady = Events:WaitForChild("ThrowReady")
local ThrowRejected = Events:WaitForChild("ThrowRejected")
local BuyCoin = Events:WaitForChild("BuyCoin")
local SyncCoins = Events:WaitForChild("SyncCoins")
local RequestUpgrade = Events:WaitForChild("RequestUpgrade")
local SyncUpgrades = Events:WaitForChild("SyncUpgrades")
local SellAll = Events:WaitForChild("SellAll")
local RedeemCode = Events:WaitForChild("RedeemCode")

local CODES = { "candy", "Luckyducky", "WORLD3" }

local State = {
	perfectLand = false,
	landMult = 2,
	landings = 0,
	lastMult = 0,
	hooked = false,

	autoThrow = false,
	throws = 0,
	throwInfo = "Idle",

	autoBuyCoin = false,
	coinInfo = "Idle",

	autoUpgrades = false,
	upgradePicks = { ["Luck Multiplier"] = true, ["Value Multiplier"] = true },
	upgradeDelay = 30,
	upgradeInfo = "Idle",
	upgradeNext = 0,

	autoSell = false,
	sellDelay = 30,
	sellInfo = "Idle",
	sellNext = 0,
	sellCount = 0,

	codeInfo = "No codes redeemed yet",

	antiAfk = false,
}

local ownedCoins = {}
local upgradeLevels = {}
local readySet = {}
local rejectCount = 0
local throwId = 1000

local function fmt(n)
	local ok, res = pcall(function()
		return NumberManipulator:formatNumber(n)
	end)
	return ok and tostring(res) or tostring(n)
end

local function getCash()
	local stats = LocalPlayer:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("Cash")
	return cash and cash.Value or 0
end

local function getWorld()
	local ok, res = pcall(function()
		return Progression:GetWorldForPlaceId(game.PlaceId)
	end)
	return ok and tonumber(res) or 1
end

local function getCoinShopScroll()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local folder = gui and gui:FindFirstChild("UiFolder")
	local main = folder and folder:FindFirstChild("Main")
	local frames = main and main:FindFirstChild("Frames")
	local shop = frames and frames:FindFirstChild("CoinShop")
	if not shop then
		return nil
	end
	for _, v in ipairs(shop:GetDescendants()) do
		if v:IsA("ScrollingFrame") then
			return v
		end
	end
	return nil
end

local function refreshOwnedFromUI()
	local scroll = getCoinShopScroll()
	if not scroll then
		return
	end
	local found = {}
	local any = false
	for _, card in ipairs(scroll:GetChildren()) do
		if card:IsA("Frame") and Progression.Coins[card.Name] then
			local main = card:FindFirstChild("Main")
			local container = main and main:FindFirstChild("ButtonContainer")
			local button = container and container:FindFirstChild("BuyButton")
			local price = button and button:FindFirstChild("Price")
			if price then
				local text = price.Text
				if text == "Equip" or text == "Equipped" then
					found[card.Name] = true
					any = true
				end
			end
		end
	end
	if any then
		ownedCoins = found
	end
end

local function getBestOwnedCoin()
	local best, bestLuck = nil, -1
	for name in pairs(ownedCoins) do
		local data = Progression.Coins[name]
		if data and (data.Luck or 0) > bestLuck then
			best, bestLuck = name, data.Luck or 0
		end
	end
	return best
end

local function getNextCoin()
	local world = getWorld()
	local best, bestLuck = nil, math.huge
	for name, data in pairs(Progression.Coins) do
		local cost = data.Cost or 0
		if not ownedCoins[name] and cost > 0 and (data.World or 1) <= world then
			local luck = data.Luck or 0
			if luck < bestLuck then
				best, bestLuck = name, luck
			end
		end
	end
	return best
end

local function getCharacter()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char and hrp and hum then
		return char, hrp, hum
	end
	return nil
end

local function getThrowTarget(hrp)
	local waypoints = workspace:FindFirstChild("Waypoints")
	if not waypoints then
		return nil
	end
	local target = waypoints:FindFirstChild("CoinTarget")
	local vip = waypoints:FindFirstChild("CoinTargetVIP")
	if LocalPlayer:GetAttribute("VIP") and target and vip and hrp then
		if (hrp.Position - target.Position).Magnitude > (hrp.Position - vip.Position).Magnitude then
			return vip
		end
	end
	return target or vip
end

local nc = newcclosure or function(f)
	return f
end

local function getGameAutoButton()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local folder = gui and gui:FindFirstChild("UiFolder")
	local main = folder and folder:FindFirstChild("Main")
	local hud = main and main:FindFirstChild("HUD")
	local coin = hud and hud:FindFirstChild("Coin")
	return coin and coin:FindFirstChild("AutoButton")
end

local function disableGameAutoThrow()
	local button = getGameAutoButton()
	local label = button and button:FindFirstChild("OffOn")
	if not label or label.Text ~= "ON" then
		return
	end
	if firesignal then
		pcall(function()
			firesignal(button.MouseButton1Click)
		end)
	end
end

do
	local ok = pcall(function()
		if not (hookmetamethod and getnamecallmethod and checkcaller) then
			error("unsupported")
		end
		local old
		old = hookmetamethod(game, "__namecall", nc(function(self, ...)
			if State.perfectLand and self == CoinLanded and getnamecallmethod() == "FireServer" and not checkcaller() then
				local count = select("#", ...)
				local args = table.pack(...)
				args[1] = State.landMult
				State.landings = State.landings + 1
				State.lastMult = State.landMult
				return old(self, table.unpack(args, 1, count))
			end
			return old(self, ...)
		end))
	end)
	State.hooked = ok
end

ThrowReady.OnClientEvent:Connect(function(id)
	readySet[tonumber(id) or -1] = true
end)

ThrowRejected.OnClientEvent:Connect(function()
	rejectCount = rejectCount + 1
end)

SyncCoins.OnClientEvent:Connect(function(list)
	local found = {}
	for _, name in ipairs(list or {}) do
		found[name] = true
	end
	ownedCoins = found
end)

SyncUpgrades.OnClientEvent:Connect(function(levels)
	upgradeLevels = levels or {}
end)

task.spawn(function()
	pcall(function()
		SyncUpgrades:FireServer()
	end)
	refreshOwnedFromUI()
end)

local function moveIntoRange(char, hrp, target)
	if (hrp.Position - target.Position).Magnitude <= 34 then
		return true
	end
	local angle = math.random() * 2 * math.pi
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local spot = Vector3.new(target.Position.X, hrp.Position.Y, target.Position.Z) + offset * 25
	char:PivotTo(CFrame.lookAt(spot, Vector3.new(target.Position.X, spot.Y, target.Position.Z)))
	task.wait(0.35)
	return true
end

local function performThrow()
	disableGameAutoThrow()

	local char, hrp, hum = getCharacter()
	if not char then
		State.throwInfo = "Waiting for character"
		return false
	end
	if hum.Sit then
		hum.Sit = false
		task.wait(0.2)
	end

	local target = getThrowTarget(hrp)
	if not target then
		State.throwInfo = "Fountain not found"
		return false
	end

	moveIntoRange(char, hrp, target)
	char, hrp = getCharacter()
	if not hrp then
		return false
	end

	local coin = getBestOwnedCoin()
	if not coin then
		refreshOwnedFromUI()
		coin = getBestOwnedCoin() or "Basic Coin"
	end

	local flat = Vector3.new(hrp.Position.X, target.Position.Y, hrp.Position.Z) - target.Position
	local dir = flat.Magnitude > 0 and flat.Unit or Vector3.new(0, 0, 1)
	local landing = target.Position + dir * 8

	throwId = throwId + 1
	local id = throwId
	readySet[id] = nil

	local rejectBase = rejectCount
	local mult = State.perfectLand and State.landMult or 1

	State.throwInfo = string.format("Throwing %s (x%d landing)", coin, mult)
	CoinThrow:FireServer(coin, landing)

	local waited = 0
	while waited < 1.6 do
		if rejectCount > rejectBase or not State.autoThrow then
			break
		end
		task.wait(0.1)
		waited = waited + 0.1
	end

	if rejectCount > rejectBase then
		State.throwInfo = "Server busy, retrying"
		task.wait(1)
		return false
	end
	if not State.autoThrow then
		return false
	end

	CoinLanded:FireServer(mult, landing, coin, nil, tonumber(LocalPlayer:GetAttribute("DesiredLuck")), id)
	State.landings = State.landings + 1
	State.lastMult = mult

	local start = os.clock()
	while not readySet[id] and os.clock() - start < 20 do
		if not State.autoThrow then
			break
		end
		task.wait(0.1)
	end
	readySet[id] = nil

	State.throws = State.throws + 1
	State.throwInfo = string.format("Thrown %d coins with %s", State.throws, coin)
	task.wait(0.4)
	return true
end

task.spawn(function()
	while not Fluent.Unloaded do
		if State.autoThrow then
			local ok = pcall(performThrow)
			if not ok then
				task.wait(1)
			end
		else
			task.wait(0.3)
		end
		task.wait(0.05)
	end
end)

task.spawn(function()
	while not Fluent.Unloaded do
		if State.autoBuyCoin then
			refreshOwnedFromUI()
			local nextCoin = getNextCoin()
			if not nextCoin then
				State.coinInfo = "All coins of this world are owned"
			else
				local cost = Progression.Coins[nextCoin].Cost or 0
				local cash = getCash()
				if cash >= cost then
					BuyCoin:FireServer(nextCoin)
					State.coinInfo = string.format("Bought %s for $%s", nextCoin, fmt(cost))
					task.wait(1.5)
					refreshOwnedFromUI()
				else
					State.coinInfo = string.format("Next: %s | $%s / $%s", nextCoin, fmt(cash), fmt(cost))
				end
			end
			task.wait(2)
		else
			task.wait(0.5)
		end
	end
end)

task.spawn(function()
	while not Fluent.Unloaded do
		if State.autoUpgrades then
			if os.clock() >= State.upgradeNext then
				State.upgradeNext = os.clock() + State.upgradeDelay
				local bought = {}
				for name, enabled in pairs(State.upgradePicks) do
					if enabled and Progression.Upgrades[name] then
						local level = tonumber(upgradeLevels[name]) or 0
						local cost = 0
						pcall(function()
							cost = Progression:GetUpgradeCost(name, level) or 0
						end)
						if cost > 0 and getCash() >= cost then
							RequestUpgrade:FireServer(name)
							table.insert(bought, string.format("%s -> %d", name, level + 1))
							task.wait(0.5)
						end
					end
				end
				local lines = {}
				for name, enabled in pairs(State.upgradePicks) do
					if enabled and Progression.Upgrades[name] then
						local level = tonumber(upgradeLevels[name]) or 0
						local cost = 0
						pcall(function()
							cost = Progression:GetUpgradeCost(name, level) or 0
						end)
						table.insert(lines, string.format("%s: lvl %d ($%s)", name, level, fmt(cost)))
					end
				end
				if #lines == 0 then
					State.upgradeInfo = "No upgrades selected"
				else
					State.upgradeInfo = table.concat(lines, "\n")
					if #bought > 0 then
						State.upgradeInfo = State.upgradeInfo .. "\nBought: " .. table.concat(bought, ", ")
					end
				end
			end
			task.wait(0.5)
		else
			State.upgradeNext = 0
			task.wait(0.5)
		end
	end
end)

task.spawn(function()
	while not Fluent.Unloaded do
		if State.autoSell then
			if os.clock() >= State.sellNext then
				State.sellNext = os.clock() + State.sellDelay
				local before = getCash()
				SellAll:FireServer()
				task.wait(1.5)
				local gained = getCash() - before
				State.sellCount = State.sellCount + 1
				if gained > 0 then
					State.sellInfo = string.format("Sold %d times | Last gain: $%s", State.sellCount, fmt(gained))
				else
					State.sellInfo = string.format("Sold %d times | Nothing to sell", State.sellCount)
				end
			end
			task.wait(0.5)
		else
			State.sellNext = 0
			task.wait(0.5)
		end
	end
end)

local redeeming = false

local function redeemCodes()
	if redeeming then
		return
	end
	redeeming = true
	local results = {}
	for index, code in ipairs(CODES) do
		State.codeInfo = string.format("Redeeming %d/%d: %s", index, #CODES, code)
		local ok, res = pcall(function()
			return RedeemCode:InvokeServer(code)
		end)
		local text = ok and tostring(res) or "Request failed"
		if text == "Slow down!" then
			task.wait(2.5)
			local retryOk, retryRes = pcall(function()
				return RedeemCode:InvokeServer(code)
			end)
			text = retryOk and tostring(retryRes) or "Request failed"
		end
		table.insert(results, code .. ": " .. text)
		task.wait(2.2)
	end
	State.codeInfo = table.concat(results, "\n")
	redeeming = false
end

local Window = Fluent:CreateWindow({
	Title = "Throw a Coin",
	SubTitle = "Automation Hub",
	Search = true,
	Icon = "coins",
	TabWidth = 150,
	Size = UDim2.fromOffset(560, 440),
	Acrylic = false,
	Theme = "Dark",
	MinimizeKey = Enum.KeyCode.LeftControl,
	UserInfo = true,
	UserInfoTitle = LocalPlayer.DisplayName,
	UserInfoSubtitle = "Throw a Coin",
	UserInfoSubtitleColor = Color3.fromRGB(255, 196, 71),
})

Fluent:CreateMinimizer({
	Icon = "coins",
	Size = UDim2.fromOffset(44, 44),
	Position = UDim2.new(0, 320, 0, 24),
	Acrylic = false,
	Corner = 10,
	Transparency = 1,
	Draggable = true,
	Visible = true,
})

local Tabs = {
	Main = Window:AddTab({ Title = "Main", Icon = "zap" }),
}

local OpSection = Tabs.Main:AddSection("Op", "star")

OpSection:AddToggle("PerfectLand", {
	Title = "Always Perfect Land",
	Description = "Forces the landing multiplier on every throw",
	Default = false,
	Callback = function(value)
		State.perfectLand = value
	end,
})

local LandMultiplier = OpSection:AddDropdown("LandMultiplier", {
	Title = "Land Multiplier",
	Values = { "X2", "X3" },
	Multi = false,
	Search = false,
	Default = 1,
	Callback = function(value)
		State.landMult = value == "X3" and 3 or 2
	end,
})

LandMultiplier:SetValue("X2")

local LandingStatus = OpSection:AddParagraph({
	Title = "Landing Status",
	Content = "Idle",
})

local ThrowingSection = Tabs.Main:AddSection("Throwing", "circle-dollar-sign")

ThrowingSection:AddToggle("AutoThrow", {
	Title = "Auto Throw",
	Description = "Throws your best owned coin non stop",
	Default = false,
	Callback = function(value)
		State.autoThrow = value
		if value then
			disableGameAutoThrow()
		else
			State.throwInfo = "Idle"
		end
	end,
})

local CoinsSection = Tabs.Main:AddSection("Coins", "shopping-cart")

CoinsSection:AddToggle("AutoBuyCoin", {
	Title = "Auto Buy Next Coin",
	Description = "Buys the next coin as soon as you can afford it",
	Default = false,
	Callback = function(value)
		State.autoBuyCoin = value
		if not value then
			State.coinInfo = "Idle"
		end
	end,
})

local CoinStatus = CoinsSection:AddParagraph({
	Title = "Coin Status",
	Content = "Idle",
})

local UpgradesSection = Tabs.Main:AddSection("Upgrades", "trending-up")

UpgradesSection:AddToggle("AutoUpgrades", {
	Title = "Auto Upgrades",
	Description = "Buys the selected upgrades on a timer",
	Default = false,
	Callback = function(value)
		State.autoUpgrades = value
		if not value then
			State.upgradeInfo = "Idle"
		end
	end,
})

UpgradesSection:AddDropdown("SelectUpgrades", {
	Title = "Select Upgrades",
	Values = { "Luck Multiplier", "Value Multiplier" },
	Multi = true,
	Search = false,
	Default = { "Luck Multiplier", "Value Multiplier" },
	Callback = function(value)
		State.upgradePicks = value or {}
	end,
})

UpgradesSection:AddSlider("UpgradeDelay", {
	Title = "Upgrade Delay",
	Description = "Seconds between upgrade attempts",
	Default = 30,
	Min = 5,
	Max = 300,
	Rounding = 0,
	Callback = function(value)
		State.upgradeDelay = value
	end,
})

local UpgradeStatus = UpgradesSection:AddParagraph({
	Title = "Upgrade Status",
	Content = "Idle",
})

local EconomySection = Tabs.Main:AddSection("Economy", "banknote")

EconomySection:AddToggle("AutoSellAll", {
	Title = "Auto Sell All",
	Description = "Sells your whole inventory on a timer",
	Default = false,
	Callback = function(value)
		State.autoSell = value
		if not value then
			State.sellInfo = "Idle"
		end
	end,
})

EconomySection:AddSlider("SellDelay", {
	Title = "Sell Delay",
	Description = "Seconds between sells",
	Default = 30,
	Min = 5,
	Max = 300,
	Rounding = 0,
	Callback = function(value)
		State.sellDelay = value
	end,
})

local SellStatus = EconomySection:AddParagraph({
	Title = "Sell Status",
	Content = "Idle",
})

local CodesSection = Tabs.Main:AddSection("Codes", "gift")

CodesSection:AddButton({
	Title = "Redeem Active Codes",
	Description = "Redeems every code that is currently active",
	Callback = function()
		task.spawn(redeemCodes)
	end,
})

local CodeStatus = CodesSection:AddParagraph({
	Title = "Code Status",
	Content = "No codes redeemed yet",
})

local MiscSection = Tabs.Main:AddSection("Misc", "shield")

MiscSection:AddToggle("AntiAfk", {
	Title = "Anti AFK",
	Description = "Keeps you in the server while farming",
	Default = false,
	Callback = function(value)
		State.antiAfk = value
	end,
})

LocalPlayer.Idled:Connect(function()
	if not State.antiAfk or Fluent.Unloaded then
		return
	end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end)

task.spawn(function()
	while not Fluent.Unloaded do
		local landing
		if State.perfectLand then
			landing = string.format(
				"Enabled | Forcing x%d\nHook: %s\nLandings: %d | Last: x%d",
				State.landMult,
				State.hooked and "active" or "auto throw only",
				State.landings,
				State.lastMult
			)
		else
			landing = string.format("Disabled | Landings: %d", State.landings)
		end
		if State.autoThrow then
			landing = landing .. "\n" .. State.throwInfo
		end
		LandingStatus:SetDesc(landing)

		local coinLine = State.coinInfo
		local equipped = getBestOwnedCoin()
		if equipped then
			coinLine = coinLine .. "\nBest owned: " .. equipped
		end
		CoinStatus:SetDesc(coinLine)

		local upgradeLine = State.upgradeInfo
		if State.autoUpgrades and State.upgradeNext > 0 then
			upgradeLine = upgradeLine .. string.format("\nNext pass in %ds", math.max(0, math.floor(State.upgradeNext - os.clock())))
		end
		UpgradeStatus:SetDesc(upgradeLine)

		local sellLine = State.sellInfo
		if State.autoSell and State.sellNext > 0 then
			sellLine = sellLine .. string.format("\nNext sell in %ds", math.max(0, math.floor(State.sellNext - os.clock())))
		end
		sellLine = sellLine .. "\nCash: $" .. fmt(getCash())
		SellStatus:SetDesc(sellLine)

		CodeStatus:SetDesc(State.codeInfo)

		task.wait(0.5)
	end
end)

Window:SelectTab(1)

Fluent:Notify({
	Title = "Throw a Coin",
	Content = "Hub loaded",
	SubContent = State.hooked and "Landing hook ready" or "Landing hook unsupported",
	Duration = 6,
})

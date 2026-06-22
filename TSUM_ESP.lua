-- // t.me/arceusxcommunity <3
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local TIER_RED    = 4000
local TIER_ORANGE = 1500

local COL_RED    = Color3.fromRGB(255, 70, 70)
local COL_ORANGE = Color3.fromRGB(255, 170, 40)
local COL_GREEN  = Color3.fromRGB(70, 230, 120)

local function fmt(n)
	n = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1,1) == "," then out = out:sub(2) end
	return (n < 0 and "-" or "") .. out
end

local function safeRequire(inst)
	if not inst then return nil end
	local ok, mod = pcall(require, inst)
	return ok and mod or nil
end

local function notify(text)
	pcall(function()
		game.StarterGui:SetCore("SendNotification", {
			Title = "TSUM ESP", Text = text, Duration = 4,
		})
	end)
	print("[TSUM ESP] " .. text)
end

local function getHiddenParent()
	local ok, hui
	if typeof(gethui) == "function" then ok, hui = pcall(gethui) end
	if (not ok or not hui) and typeof(get_hidden_gui) == "function" then
		ok, hui = pcall(get_hidden_gui)
	end
	if ok and hui then return hui end
	return PlayerGui
end
local HIDDEN = getHiddenParent()

local function protect(inst)
	pcall(function()
		if syn and syn.protect_gui then syn.protect_gui(inst) end
		if typeof(protect_gui) == "function" then protect_gui(inst) end
	end)
end

local Configs        = ReplicatedStorage:FindFirstChild("Configs")
local ClothingConfig = safeRequire(ReplicatedStorage:FindFirstChild("ClothingConfig"))
local Economy        = safeRequire(Configs and Configs:FindFirstChild("EconomyProfiles"))
local AccessoryCfg   = safeRequire(Configs and Configs:FindFirstChild("AccessoryConfig"))

local function resaleValue(fair, profile)
	local mult = 0.9
	if Economy and Economy.getExpectedReturn then
		mult = Economy.getExpectedReturn(profile or "normal", true) or mult
	end
	return math.floor((fair or 0) * mult)
end

local NAME_INDEX = {}
do
	local function add(name, fair, profile)
		if name and fair then
			NAME_INDEX[tostring(name):lower()] = { fair = fair, profile = profile or "normal" }
		end
	end
	local items = ClothingConfig and ClothingConfig.SHOP_ITEMS
	if type(items) == "table" then
		local function scan(node, depth)
			if type(node) ~= "table" or depth > 6 then return end
			if node.name and (node.fairPrice or node.value) then
				add(node.name, node.fairPrice or node.value, node.economyProfile)
				return
			end
			for _, c in pairs(node) do scan(c, depth + 1) end
		end
		scan(items, 0)
	end
	if AccessoryCfg then
		local function scanAcc(node, depth)
			if type(node) ~= "table" or depth > 6 then return end
			if node.name and (node.fairPrice or node.value) then
				add(node.name, node.fairPrice or node.value, node.economyProfile)
				return
			end
			for _, c in pairs(node) do scanAcc(c, depth + 1) end
		end
		scanAcc(AccessoryCfg, 0)
	end
end

local function valueByName(name)
	local rec = NAME_INDEX[tostring(name or ""):lower()]
	if rec then return rec.fair, rec.profile end
	return nil, nil
end

local function tierFor(profit)
	if not profit or profit <= 0 then return nil end
	if profit >= TIER_RED then return COL_RED end
	if profit >= TIER_ORANGE then return COL_ORANGE end
	return COL_GREEN
end

local ShopRemotes     = ReplicatedStorage:FindFirstChild("ShopRemotes")
local SlotPriceReveal = ShopRemotes and ShopRemotes:FindFirstChild("SlotPriceReveal")
local SlotInfoClear   = ShopRemotes and ShopRemotes:FindFirstChild("SlotInfoClear")

local espHolder = Instance.new("Folder")
espHolder.Name = "TSUM_ESP_Holder"
protect(espHolder)
espHolder.Parent = HIDDEN

local ESP = { enabled = true, live = {}, objs = {} }

local function destroyObjs(slotRef)
	local o = ESP.objs[slotRef]
	if o then
		if o.hl then o.hl:Destroy() end
		if o.bb then o.bb:Destroy() end
	end
	ESP.objs[slotRef] = nil
end

local function drawSlot(entry, color)
	local slotRef = entry.slotRef
	if not (slotRef and slotRef.Parent) then return end
	local o = ESP.objs[slotRef]
	if not o then
		o = {}
		local hl = Instance.new("Highlight")
		hl.Name = "TSUM_HL"
		hl.Adornee = slotRef
		hl.FillTransparency = 0.5
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = espHolder
		o.hl = hl

		local bb = Instance.new("BillboardGui")
		bb.Name = "TSUM_BB"
		bb.Adornee = slotRef
		bb.AlwaysOnTop = true
		bb.Size = UDim2.fromOffset(190, 64)
		bb.StudsOffset = Vector3.new(0, 3.2, 0)
		bb.MaxDistance = 80
		bb.Parent = espHolder

		local card = Instance.new("Frame")
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		card.BackgroundTransparency = 0.15
		card.BorderSizePixel = 0
		card.Parent = bb
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = card
		local st = Instance.new("UIStroke"); st.Thickness = 2; st.Parent = card
		o.stroke = st

		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.new(1, -10, 0, 22); nameL.Position = UDim2.fromOffset(5, 3)
		nameL.BackgroundTransparency = 1; nameL.Font = Enum.Font.GothamBold
		nameL.TextSize = 14; nameL.TextColor3 = Color3.fromRGB(255,255,255)
		nameL.TextTruncate = Enum.TextTruncate.AtEnd; nameL.Parent = card
		o.nameL = nameL

		local infoL = Instance.new("TextLabel")
		infoL.Size = UDim2.new(1, -10, 0, 34); infoL.Position = UDim2.fromOffset(5, 26)
		infoL.BackgroundTransparency = 1; infoL.Font = Enum.Font.GothamBold
		infoL.TextSize = 13; infoL.TextWrapped = true; infoL.Parent = card
		o.infoL = infoL

		o.bb = bb
		ESP.objs[slotRef] = o
	end
	o.hl.FillColor = color
	o.hl.OutlineColor = color
	o.stroke.Color = color
	o.nameL.Text = entry.name or "??"
	o.infoL.TextColor3 = color
	local roi = entry.price and entry.price > 0 and math.floor((entry.profit / entry.price) * 100) or 0
	o.infoL.Text = ("Купить $%s  →  +$%s (%d%%)"):format(fmt(entry.price), fmt(entry.profit), roi)
end

local function applySlot(entry)
	if not ESP.enabled then destroyObjs(entry.slotRef); return end
	local color = tierFor(entry.profit)
	if color then drawSlot(entry, color) else destroyObjs(entry.slotRef) end
end

local function buildEntry(e)
	local nm = tostring(e.name or ""):lower()
	local price = tonumber(e.price)
	local value, profile = valueByName(e.name)
	local profit = (value and price) and (resaleValue(value, profile) - price) or nil
	return nm, { slotRef = e.slotRef, name = e.name or nm, price = price, profit = profit }
end

local function onReveal(payload)
	if type(payload) ~= "table" then
		for s in pairs(ESP.objs) do destroyObjs(s) end
		ESP.live = {}
		return
	end
	local present, newLive = {}, {}
	for _, e in ipairs(payload) do
		if type(e) == "table" and e.slotRef then
			local nm, entry = buildEntry(e)
			newLive[nm] = entry
			present[entry.slotRef] = true
			applySlot(entry)
		end
	end
	for slotRef in pairs(ESP.objs) do
		if not present[slotRef] then destroyObjs(slotRef) end
	end
	ESP.live = newLive
end

local function refreshESP()
	local present = {}
	for _, entry in pairs(ESP.live) do
		present[entry.slotRef] = true
		applySlot(entry)
	end
	for slotRef in pairs(ESP.objs) do
		if not present[slotRef] then destroyObjs(slotRef) end
	end
end

if SlotPriceReveal then SlotPriceReveal.OnClientEvent:Connect(onReveal) end
if SlotInfoClear then
	SlotInfoClear.OnClientEvent:Connect(function()
		for s in pairs(ESP.objs) do destroyObjs(s) end
	end)
end

local oldGui = HIDDEN:FindFirstChild("TSUM_ESP_UI")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "TSUM_ESP_UI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
protect(gui)
gui.Parent = HIDDEN

local function corner(p, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 8) c.Parent = p return c end

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(250, 190)
main.Position = UDim2.fromOffset(20, 120)
main.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
corner(main, 12)
local mstroke = Instance.new("UIStroke"); mstroke.Color = Color3.fromRGB(255,210,70); mstroke.Thickness = 1.5; mstroke.Transparency = 0.3; mstroke.Parent = main

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
header.BorderSizePixel = 0
header.Parent = main
corner(header, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0); title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold
title.TextSize = 15; title.TextColor3 = Color3.fromRGB(255, 210, 70)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "TSUM ESP 💎"; title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(26, 26); closeBtn.Position = UDim2.new(1, -34, 0, 7)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 69, 58)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 15
closeBtn.TextColor3 = Color3.fromRGB(255,255,255); closeBtn.Text = "X"
closeBtn.Parent = header
corner(closeBtn, 7)

local floatBtn = Instance.new("TextButton")
floatBtn.Size = UDim2.fromOffset(54, 54)
floatBtn.Position = UDim2.fromOffset(20, 120)
floatBtn.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
floatBtn.Font = Enum.Font.GothamBold; floatBtn.TextSize = 26
floatBtn.Text = "💎"; floatBtn.AutoButtonColor = true
floatBtn.Visible = false
floatBtn.Active = true
floatBtn.Parent = gui
corner(floatBtn, 27)
local fstroke = Instance.new("UIStroke"); fstroke.Color = Color3.fromRGB(255,210,70); fstroke.Thickness = 1.5; fstroke.Transparency = 0.3; fstroke.Parent = floatBtn

closeBtn.Activated:Connect(function()
	main.Visible = false
	floatBtn.Position = main.Position
	floatBtn.Visible = true
end)

local function openPanel()
	floatBtn.Visible = false
	main.Position = floatBtn.Position
	main.Visible = true
end

local UserInputService = game:GetService("UserInputService")
local dragging, moved, dragStart, startPos = false, false, nil, nil

floatBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging, moved = true, false
		dragStart = input.Position
		startPos = floatBtn.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - dragStart
		if d.Magnitude > 6 then moved = true end
		floatBtn.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + d.X,
			startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		dragging = false
		if not moved then openPanel() end
	end
end)

local espBtn = Instance.new("TextButton")
espBtn.Size = UDim2.new(1, -20, 0, 36); espBtn.Position = UDim2.fromOffset(10, 48)
espBtn.BackgroundColor3 = COL_GREEN
espBtn.Font = Enum.Font.GothamBold; espBtn.TextSize = 14
espBtn.TextColor3 = Color3.fromRGB(20,20,24); espBtn.Text = "👁 ESP: ВКЛ"
espBtn.Parent = main
corner(espBtn, 8)

local function legend(y, col, text)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(14, 14); dot.Position = UDim2.fromOffset(14, y)
	dot.BackgroundColor3 = col; dot.BorderSizePixel = 0; dot.Parent = main
	corner(dot, 4)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -40, 0, 16); t.Position = UDim2.fromOffset(36, y - 1)
	t.BackgroundTransparency = 1; t.Font = Enum.Font.Gotham
	t.TextSize = 12; t.TextColor3 = Color3.fromRGB(220,220,225)
	t.TextXAlignment = Enum.TextXAlignment.Left; t.Text = text; t.Parent = main
end
legend(96,  COL_RED,    ("Топ-выгода  (+$%s и выше)"):format(fmt(TIER_RED)))
legend(122, COL_ORANGE, ("Средняя  (+$%s…)"):format(fmt(TIER_ORANGE)))
legend(148, COL_GREEN,  "Небольшая  (любой плюс)")

espBtn.Activated:Connect(function()
	ESP.enabled = not ESP.enabled
	espBtn.Text = ESP.enabled and "👁 ESP: ВКЛ" or "👁 ESP: ВЫКЛ"
	espBtn.BackgroundColor3 = ESP.enabled and COL_GREEN or Color3.fromRGB(120,120,130)
	refreshESP()
	notify(ESP.enabled and "ESP включён — ходи по рядам" or "ESP выключен")
end)

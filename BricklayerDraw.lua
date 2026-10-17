-- original: https://robloxscripts.com/script/bricklayer-auto-painter-text-printer
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local event = game.ReplicatedStorage.BrickBuilderEvent
local spieler = Players.LocalPlayer

local hoehe = 12
local breite = 8
local luecke = 3
local schritt = 1
local pause = 0.05
local flaeche = 40

local buchstaben = {
	A = {{{0, 0}, {.5, 1}, {1, 0}}, {{.2, .35}, {.8, .35}}},
	B = {{{0, 0}, {0, 1}, {.75, 1}, {1, .85}, {1, .65}, {.75, .5}, {0, .5}}, {{.75, .5}, {1, .35}, {1, .15}, {.75, 0}, {0, 0}}},
	C = {{{1, .85}, {.75, 1}, {.25, 1}, {0, .8}, {0, .2}, {.25, 0}, {.75, 0}, {1, .15}}},
	D = {{{0, 0}, {0, 1}, {.65, 1}, {1, .7}, {1, .3}, {.65, 0}, {0, 0}}},
	E = {{{1, 1}, {0, 1}, {0, 0}, {1, 0}}, {{0, .5}, {.8, .5}}},
	F = {{{1, 1}, {0, 1}, {0, 0}}, {{0, .5}, {.8, .5}}},
	G = {{{1, .85}, {.75, 1}, {.25, 1}, {0, .8}, {0, .2}, {.25, 0}, {.75, 0}, {1, .2}, {1, .45}, {.55, .45}}},
	H = {{{0, 0}, {0, 1}}, {{1, 0}, {1, 1}}, {{0, .5}, {1, .5}}},
	I = {{{.2, 1}, {.8, 1}}, {{.5, 1}, {.5, 0}}, {{.2, 0}, {.8, 0}}},
	J = {{{1, 1}, {1, .2}, {.75, 0}, {.25, 0}, {0, .2}}},
	K = {{{0, 0}, {0, 1}}, {{1, 1}, {0, .45}, {1, 0}}},
	L = {{{0, 1}, {0, 0}, {1, 0}}},
	M = {{{0, 0}, {0, 1}, {.5, .45}, {1, 1}, {1, 0}}},
	N = {{{0, 0}, {0, 1}, {1, 0}, {1, 1}}},
	O = {{{.25, 0}, {0, .2}, {0, .8}, {.25, 1}, {.75, 1}, {1, .8}, {1, .2}, {.75, 0}, {.25, 0}}},
	P = {{{0, 0}, {0, 1}, {.75, 1}, {1, .85}, {1, .65}, {.75, .5}, {0, .5}}},
	Q = {{{.25, 0}, {0, .2}, {0, .8}, {.25, 1}, {.75, 1}, {1, .8}, {1, .2}, {.75, 0}, {.25, 0}}, {{.6, .3}, {1, 0}}},
	R = {{{0, 0}, {0, 1}, {.75, 1}, {1, .85}, {1, .65}, {.75, .5}, {0, .5}}, {{.5, .5}, {1, 0}}},
	S = {{{1, .9}, {.75, 1}, {.25, 1}, {0, .85}, {0, .65}, {.25, .5}, {.75, .5}, {1, .35}, {1, .15}, {.75, 0}, {.25, 0}, {0, .1}}},
	T = {{{0, 1}, {1, 1}}, {{.5, 1}, {.5, 0}}},
	U = {{{0, 1}, {0, .2}, {.25, 0}, {.75, 0}, {1, .2}, {1, 1}}},
	V = {{{0, 1}, {.5, 0}, {1, 1}}},
	W = {{{0, 1}, {.25, 0}, {.5, .55}, {.75, 0}, {1, 1}}},
	X = {{{0, 1}, {1, 0}}, {{1, 1}, {0, 0}}},
	Y = {{{0, 1}, {.5, .5}, {1, 1}}, {{.5, .5}, {.5, 0}}},
	Z = {{{0, 1}, {1, 1}, {0, 0}, {1, 0}}},
	["0"] = {{{.25, 0}, {0, .2}, {0, .8}, {.25, 1}, {.75, 1}, {1, .8}, {1, .2}, {.75, 0}, {.25, 0}}, {{.2, .15}, {.8, .85}}},
	["1"] = {{{.2, .8}, {.5, 1}, {.5, 0}}, {{.2, 0}, {.8, 0}}},
	["2"] = {{{0, .85}, {.25, 1}, {.75, 1}, {1, .85}, {1, .65}, {0, 0}, {1, 0}}},
	["3"] = {{{0, .9}, {.25, 1}, {.75, 1}, {1, .85}, {1, .65}, {.75, .5}, {.3, .5}}, {{.75, .5}, {1, .35}, {1, .15}, {.75, 0}, {.25, 0}, {0, .1}}},
	["4"] = {{{.8, 0}, {.8, 1}, {0, .3}, {1, .3}}},
	["5"] = {{{1, 1}, {0, 1}, {0, .55}, {.75, .55}, {1, .4}, {1, .15}, {.75, 0}, {.25, 0}, {0, .1}}},
	["6"] = {{{1, .9}, {.75, 1}, {.25, 1}, {0, .8}, {0, .2}, {.25, 0}, {.75, 0}, {1, .2}, {1, .4}, {.75, .55}, {0, .55}}},
	["7"] = {{{0, 1}, {1, 1}, {.35, 0}}},
	["8"] = {{{.25, .5}, {0, .65}, {0, .85}, {.25, 1}, {.75, 1}, {1, .85}, {1, .65}, {.75, .5}, {.25, .5}, {0, .35}, {0, .15}, {.25, 0}, {.75, 0}, {1, .15}, {1, .35}, {.75, .5}}},
	["9"] = {{{1, .45}, {.25, .45}, {0, .6}, {0, .85}, {.25, 1}, {.75, 1}, {1, .85}, {1, .2}, {.75, 0}, {.25, 0}, {0, .1}}},
}

local function mitPunkten(basis)
	local kopie = table.clone(buchstaben[basis])
	table.insert(kopie, {{.25, 1.25}, {.3, 1.25}})
	table.insert(kopie, {{.7, 1.25}, {.75, 1.25}})
	return kopie
end

buchstaben["Ä"] = mitPunkten("A")
buchstaben["Ö"] = mitPunkten("O")
buchstaben["Ü"] = mitPunkten("U")

local umlaute = {["ä"] = "Ä", ["ö"] = "Ö", ["ü"] = "Ü"}

local laeuft = false
local abbruch = false

local function ausrichtung(gesamtBreite)
	local wurzel = spieler.Character.HumanoidRootPart
	local blick = wurzel.CFrame.LookVector
	local seite = wurzel.CFrame.RightVector
	local vorne = Vector3.new(blick.X, 0, blick.Z).Unit
	local rechts = Vector3.new(seite.X, 0, seite.Z).Unit
	local ursprung = wurzel.Position - Vector3.new(0, 2.5, 0) + vorne * 8 - rechts * (gesamtBreite / 2)
	return ursprung, vorne, rechts
end

local function linie(von, bis)
	local anzahl = math.max(1, math.ceil((bis - von).Magnitude / schritt))
	for i = 0, anzahl do
		if abbruch then
			return
		end
		event:FireServer("Cement", von:Lerp(bis, i / anzahl), Vector3.new(0, 1, 0), workspace.Baseplate, Vector3.new(0.5, 0.5, 0.5))
		task.wait(pause)
	end
end

local function starten(arbeit)
	if laeuft then
		return
	end
	laeuft = true
	abbruch = false
	task.spawn(function()
		pcall(arbeit)
		laeuft = false
	end)
end

local function schreiben(wort)
	local zeichen = {}
	for _, code in utf8.codes(wort) do
		local z = utf8.char(code)
		table.insert(zeichen, umlaute[z] or z:upper())
	end
	if #zeichen == 0 then
		return
	end

	local gesamt = #zeichen * breite + (#zeichen - 1) * luecke
	local ursprung, vorne, rechts = ausrichtung(gesamt)

	for i, z in ipairs(zeichen) do
		local striche = buchstaben[z]
		if striche then
			local versatz = (i - 1) * (breite + luecke)
			for _, strich in ipairs(striche) do
				for j = 1, #strich - 1 do
					local a = ursprung + rechts * (versatz + strich[j][1] * breite) + vorne * (strich[j][2] * hoehe)
					local b = ursprung + rechts * (versatz + strich[j + 1][1] * breite) + vorne * (strich[j + 1][2] * hoehe)
					linie(a, b)
				end
			end
		end
	end
end

local zeichnung = {}

local function malenBauen(vorlage)
	local ursprung, vorne, rechts = ausrichtung(flaeche)
	for _, strich in ipairs(vorlage) do
		local punkte = {}
		for _, p in ipairs(strich) do
			table.insert(punkte, ursprung + rechts * (p.X * flaeche) + vorne * ((1 - p.Y) * flaeche))
		end
		if #punkte == 1 then
			linie(punkte[1], punkte[1])
		end
		for j = 1, #punkte - 1 do
			linie(punkte[j], punkte[j + 1])
		end
	end
end

local function neu(klasse, eigenschaften, eltern)
	local o = Instance.new(klasse)
	for k, v in pairs(eigenschaften) do
		o[k] = v
	end
	o.Parent = eltern
	return o
end

local playerGui = spieler:WaitForChild("PlayerGui")
local vorher = playerGui:FindFirstChild("CementPrinter")
if vorher then
	vorher:Destroy()
end

local gui = neu("ScreenGui", {
	Name = "CementPrinter",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local bildschirm = neu("Frame", {
	Name = "SafeArea",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, gui)

local fenster = neu("Frame", {
	Name = "Window",
	Size = UDim2.fromOffset(340, 452),
	BackgroundColor3 = Color3.fromRGB(24, 24, 28),
	BorderSizePixel = 0,
	Active = true,
}, bildschirm)
local skalierung = neu("UIScale", {Scale = 1}, fenster)

local kopf = neu("Frame", {
	Name = "TitleBar",
	BackgroundColor3 = Color3.fromRGB(34, 34, 40),
	BorderSizePixel = 0,
	Active = true,
}, fenster)

neu("TextLabel", {
	Text = "Cement Printer",
	Position = UDim2.fromOffset(10, 0),
	Size = UDim2.new(1, -64, 1, 0),
	BackgroundTransparency = 1,
	TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
}, kopf)

local function knopf(name, text, farbe, eltern)
	local k = neu("TextButton", {
		Name = name,
		Text = text,
		BackgroundColor3 = farbe,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		BorderSizePixel = 0,
	}, eltern)
	neu("UICorner", {CornerRadius = UDim.new(0, 6)}, k)
	return k
end

local schliessen = knopf("Close", "X", Color3.fromRGB(150, 50, 50), kopf)
local oeffnen = knopf("OpenMenu", "CP", Color3.fromRGB(200, 110, 30), bildschirm)
oeffnen.Size = UDim2.fromOffset(52, 52)
oeffnen.Visible = false
oeffnen.Active = true
oeffnen.ZIndex = 10
oeffnen:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
local leinwand = neu("Frame", {
	Name = "Canvas",
	BackgroundColor3 = Color3.fromRGB(44, 44, 52),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Active = true,
}, fenster)

local bauen = knopf("PrintDrawing", "Print", Color3.fromRGB(46, 125, 80), fenster)
local leeren = knopf("ClearDrawing", "Clear", Color3.fromRGB(70, 70, 80), fenster)
local stopp = knopf("StopPrinting", "Stop", Color3.fromRGB(150, 50, 50), fenster)
local eingabe = neu("TextBox", {
	Name = "TextInput",
	Text = "Made By VEXA",
	PlaceholderText = "Text",
	BackgroundColor3 = Color3.fromRGB(40, 40, 46),
	TextColor3 = Color3.new(1, 1, 1),
	PlaceholderColor3 = Color3.fromRGB(140, 140, 150),
	ClearTextOnFocus = false,
	Font = Enum.Font.Gotham,
	TextSize = 14,
	BorderSizePixel = 0,
}, fenster)
neu("UICorner", {CornerRadius = UDim.new(0, 6)}, eingabe)
local drucken = knopf("PrintText", "Print Text", Color3.fromRGB(200, 110, 30), fenster)

local seitenlaenge = 320
local function punkt(p)
	neu("Frame", {
		Size = UDim2.fromOffset(4, 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(p.X, p.Y),
		BackgroundColor3 = Color3.fromRGB(255, 150, 50),
		BorderSizePixel = 0,
	}, leinwand)
end

local function segment(a, b)
	local d = (b - a) * seitenlaenge
	neu("Frame", {
		Size = UDim2.fromOffset(d.Magnitude, 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		BackgroundColor3 = Color3.fromRGB(255, 150, 50),
		BorderSizePixel = 0,
	}, leinwand)
end

local function neuZeichnen()
	leinwand:ClearAllChildren()
	for _, strich in ipairs(zeichnung) do
		punkt(strich[1])
		for i = 2, #strich do
			segment(strich[i - 1], strich[i])
		end
	end
end

local zeichnenInput, ziehenInput, aktiverStrich, letzter, ziehStart, fensterStart
local knopfInput, knopfZiehStart, knopfPositionStart, knopfLetzteEingabe
local knopfGezogen = false
local function eingabeBeenden()
	zeichnenInput, ziehenInput, aktiverStrich, letzter = nil, nil, nil, nil
	knopfInput = nil
end

local function eingabeAbbrechen()
	if knopfInput then
		knopfGezogen = true
	end
	eingabeBeenden()
end

local rand = 8
local function positionSetzen(x, y)
	local groesse = bildschirm.AbsoluteSize
	local breitePx = fenster.Size.X.Offset * skalierung.Scale
	local hoehePx = fenster.Size.Y.Offset * skalierung.Scale
	fenster.Position = UDim2.fromOffset(
		math.clamp(x, rand, math.max(rand, groesse.X - breitePx - rand)),
		math.clamp(y, rand, math.max(rand, groesse.Y - hoehePx - rand))
	)
end

local function knopfPositionSetzen(x, y)
	local groesse = bildschirm.AbsoluteSize
	oeffnen.Position = UDim2.fromOffset(
		math.clamp(x, rand, math.max(rand, groesse.X - oeffnen.Size.X.Offset - rand)),
		math.clamp(y, rand, math.max(rand, groesse.Y - oeffnen.Size.Y.Offset - rand))
	)
end

local function rechteck(objekt, x, y, b, h)
	objekt.Position = UDim2.fromOffset(x, y)
	objekt.Size = UDim2.fromOffset(b, h)
end

local erstesLayout = true
local erstesKnopfLayout = true
local function layout()
	local groesse = bildschirm.AbsoluteSize
	if groesse.X <= rand * 2 or groesse.Y <= rand * 2 then
		return
	end
	eingabeAbbrechen()
	local maxB, maxH = groesse.X - rand * 2, groesse.Y - rand * 2
	local faktor = math.min(1, maxB / 280, maxH / 260)
	skalierung.Scale = faktor
	maxB, maxH = maxB / faktor, maxH / faktor
	local abstand, lueckePx = 10, 8
	local taste = UserInputService.TouchEnabled and 40 or 32
	local kopfH = taste
	local unten = kopfH + abstand * 2 + lueckePx * 2 + taste * 2
	local hochkant = math.min(320, maxB - abstand * 2, maxH - unten)
	local spalte = 144
	local quer = math.min(320, maxB - abstand * 2 - lueckePx - spalte, maxH - kopfH - abstand * 2)
	local spalteH = taste * 4 + lueckePx * 3
	local seitlich = hochkant < 240 and quer > hochkant and quer >= spalteH
	local b, h

	if seitlich then
		seitenlaenge = math.floor(quer)
		b = abstand * 2 + seitenlaenge + lueckePx + spalte
		h = kopfH + abstand * 2 + seitenlaenge
		local x, y = abstand + seitenlaenge + lueckePx, kopfH + abstand
		rechteck(bauen, x, y, spalte, taste)
		y = y + taste + lueckePx
		local halb = (spalte - lueckePx) / 2
		rechteck(leeren, x, y, halb, taste)
		rechteck(stopp, x + halb + lueckePx, y, halb, taste)
		y = y + taste + lueckePx
		rechteck(eingabe, x, y, spalte, taste)
		rechteck(drucken, x, y + taste + lueckePx, spalte, taste)
	else
		seitenlaenge = math.floor(hochkant)
		b, h = seitenlaenge + abstand * 2, seitenlaenge + unten
		local y = kopfH + abstand + seitenlaenge + lueckePx
		local drittel = (seitenlaenge - lueckePx * 2) / 3
		rechteck(bauen, abstand, y, drittel, taste)
		rechteck(leeren, abstand + drittel + lueckePx, y, drittel, taste)
		rechteck(stopp, abstand + (drittel + lueckePx) * 2, y, drittel, taste)
		y = y + taste + lueckePx
		local textTaste = math.min(100, seitenlaenge * 0.34)
		rechteck(eingabe, abstand, y, seitenlaenge - textTaste - lueckePx, taste)
		rechteck(drucken, abstand + seitenlaenge - textTaste, y, textTaste, taste)
	end
	rechteck(fenster, fenster.Position.X.Offset, fenster.Position.Y.Offset, b, h)
	rechteck(kopf, 0, 0, b, kopfH)
	rechteck(schliessen, b - taste, 0, taste, taste)
	rechteck(leinwand, abstand, kopfH + abstand, seitenlaenge, seitenlaenge)
	if erstesLayout then
		erstesLayout = false
		positionSetzen(40, 60)
	else
		positionSetzen(fenster.Position.X.Offset, fenster.Position.Y.Offset)
	end
	local knopfGroesse = math.min(52, groesse.X - rand * 2, groesse.Y - rand * 2)
	oeffnen.Size = UDim2.fromOffset(knopfGroesse, knopfGroesse)
	if erstesKnopfLayout then
		erstesKnopfLayout = false
		knopfPositionSetzen(16, (groesse.Y - knopfGroesse) / 2)
	else
		knopfPositionSetzen(oeffnen.Position.X.Offset, oeffnen.Position.Y.Offset)
	end
	neuZeichnen()
end

local function relativ(pos)
	local start, groesse = leinwand.AbsolutePosition, leinwand.AbsoluteSize
	return Vector2.new(
		math.clamp((pos.X - start.X) / groesse.X, 0, 1),
		math.clamp((pos.Y - start.Y) / groesse.Y, 0, 1)
	)
end

local function istEingabe(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function gleicheBewegung(input, anfang)
	if anfang.UserInputType == Enum.UserInputType.Touch then
		return input == anfang
	end
	return input.UserInputType == Enum.UserInputType.MouseMovement
end

local function gleichesEnde(input, anfang)
	return anfang and (input == anfang or (anfang.UserInputType == Enum.UserInputType.MouseButton1
		and input.UserInputType == Enum.UserInputType.MouseButton1))
end

local verbindungen = {}
local function verbinden(signal, funktion)
	table.insert(verbindungen, signal:Connect(funktion))
end

verbinden(leinwand.InputBegan, function(input)
	if not fenster.Visible or not istEingabe(input) or zeichnenInput or ziehenInput or knopfInput then
		return
	end
	if leinwand.AbsoluteSize.X <= 0 or leinwand.AbsoluteSize.Y <= 0 then
		return
	end
	zeichnenInput = input
	letzter = relativ(input.Position)
	aktiverStrich = {letzter}
	table.insert(zeichnung, aktiverStrich)
	punkt(letzter)
end)

verbinden(kopf.InputBegan, function(input)
	if fenster.Visible and istEingabe(input) and not zeichnenInput and not ziehenInput and not knopfInput
		and input.Position.X < schliessen.AbsolutePosition.X then
		ziehenInput = input
		ziehStart = input.Position
		fensterStart = fenster.Position
	end
end)

verbinden(oeffnen.InputBegan, function(input)
	if not oeffnen.Visible or not istEingabe(input) or zeichnenInput or ziehenInput or knopfInput then
		return
	end
	knopfInput, knopfLetzteEingabe = input, input
	knopfGezogen = false
	knopfZiehStart = input.Position
	knopfPositionStart = oeffnen.Position
end)

verbinden(UserInputService.InputChanged, function(input)
	if input.UserInputState == Enum.UserInputState.Cancel then
		if gleichesEnde(input, zeichnenInput) or gleichesEnde(input, ziehenInput) or gleichesEnde(input, knopfInput) then
			eingabeAbbrechen()
		end
		return
	end
	if zeichnenInput and gleicheBewegung(input, zeichnenInput) then
		local p = relativ(input.Position)
		if (p - letzter).Magnitude * leinwand.AbsoluteSize.X >= 3 then
			table.insert(aktiverStrich, p)
			segment(letzter, p)
			letzter = p
		end
	elseif ziehenInput and gleicheBewegung(input, ziehenInput) then
		local d = input.Position - ziehStart
		positionSetzen(fensterStart.X.Offset + d.X, fensterStart.Y.Offset + d.Y)
	elseif knopfInput and gleicheBewegung(input, knopfInput) then
		local d = input.Position - knopfZiehStart
		if d.Magnitude > 6 then
			knopfGezogen = true
		end
		if knopfGezogen then
			knopfPositionSetzen(knopfPositionStart.X.Offset + d.X, knopfPositionStart.Y.Offset + d.Y)
		end
	end
end)

verbinden(UserInputService.InputEnded, function(input)
	if gleichesEnde(input, zeichnenInput) or gleichesEnde(input, ziehenInput) then
		eingabeBeenden()
	elseif gleichesEnde(input, knopfInput) then
		knopfInput = nil
	end
end)
verbinden(UserInputService.WindowFocusReleased, eingabeAbbrechen)
verbinden(bildschirm:GetPropertyChangedSignal("AbsoluteSize"), layout)
verbinden(UserInputService:GetPropertyChangedSignal("TouchEnabled"), layout)

verbinden(bauen.Activated, function()
	if laeuft then
		return
	end
	eingabeBeenden()
	local vorlage = {}
	for i, strich in ipairs(zeichnung) do
		vorlage[i] = table.clone(strich)
	end
	starten(function()
		malenBauen(vorlage)
	end)
end)

verbinden(leeren.Activated, function()
	eingabeBeenden()
	leinwand:ClearAllChildren()
	table.clear(zeichnung)
end)

verbinden(stopp.Activated, function()
	abbruch = true
end)

verbinden(drucken.Activated, function()
	local wort = eingabe.Text
	starten(function()
		schreiben(wort)
	end)
end)

local function menueAnzeigen(zeigen)
	eingabeBeenden()
	fenster.Visible = zeigen
	oeffnen.Visible = not zeigen
	if not zeigen then
		eingabe:ReleaseFocus()
	end
end

verbinden(schliessen.Activated, function()
	menueAnzeigen(false)
end)

verbinden(oeffnen.Activated, function(input)
	if not oeffnen.Visible then
		return
	end
	if not input or istEingabe(input) then
		if knopfGezogen then
			return
		end
		if input and knopfLetzteEingabe and not gleichesEnde(input, knopfLetzteEingabe) then
			return
		end
	end
	menueAnzeigen(true)
end)

verbinden(gui.Destroying, function()
	abbruch = true
	eingabeBeenden()
	for _, v in ipairs(verbindungen) do
		v:Disconnect()
	end
	table.clear(verbindungen)
end)

layout()

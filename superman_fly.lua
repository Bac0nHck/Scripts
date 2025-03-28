--------------------------------------------------
-- COMPLETTES FLUGSYSTEM MIT BOBBING & BACKWARDS-ANIMATION
--------------------------------------------------

-- Dienste laden
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Lokale Variablen
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")
local originalGravity = Workspace.Gravity

local isFlying = false
local flightSpeed = 50           -- Standardfluggeschwindigkeit
local toggleKey = Enum.KeyCode.X   -- Standard Umschalttaste
local waitingForKeybind = false

-- Steuerungstabelle für Flugbewegung (W, A, S, D)
local moveState = {
	forward = 0,    -- W
	backward = 0,   -- S
	left = 0,       -- A
	right = 0       -- D
}

-- Zustände für Flugausrichtung (Rotation)
local currentCF = nil       -- Aktuell interpolierter CFrame der Rotation
local currentRoll = 0       -- Aktueller Rollwinkel (für seitliches Neigen)
local maxRoll = 45          -- Maximaler Rollwinkel in Grad
local lerpCoef = 0.1        -- Übergangskoeffizient für Rotation

-- Variable für den Sliding-Effekt (inertiales Gleiten)
local slideDamping = 0.05   -- Wert zwischen 0 und 1 (kleiner = mehr Slide)
local currentVelocity = Vector3.new(0, 0, 0)

-- Parameter für den Bobbing-Effekt (sanftes Auf- und Abgleiten beim Schweben)
local bobbingFrequency = 1    -- Frequenz des Sinus (je kleiner = längere Periode)
local bobbingAmplitude = 0.5  -- Amplitude des Bobbings (Höhe der Schwankung)

-- Verbindungstabellen, um alle Events später sauber zu trennen
local flightConns = {}
local globalConns = {}

-- Variable für aktuell laufende Animation
local currentAnimTrack = nil

--------------------------------------------------
-- ANIMATIONEN (Starten/Stoppen)
--------------------------------------------------
local function disableDefaultAnimate()
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate.Disabled = true
	end
end

local function enableDefaultAnimate()
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate.Disabled = false
	end
end

local function playAnimation(animId, startTime, speed)
	-- Beende vorherige Animation
	if currentAnimTrack then
		currentAnimTrack:Stop(0.1)
		currentAnimTrack = nil
	end
	disableDefaultAnimate()
	-- Stoppe alle bereits laufenden Animationen
	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		track:Stop()
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)
	currentAnimTrack = humanoid:LoadAnimation(anim)
	currentAnimTrack:Play()
	currentAnimTrack.TimePosition = startTime
	currentAnimTrack:AdjustSpeed(speed)
end

local function stopAnimation()
	if currentAnimTrack then
		currentAnimTrack:Stop(0.1)
		currentAnimTrack = nil
	end
	enableDefaultAnimate()
	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		track:Stop()
	end
end

--------------------------------------------------
-- HILFSFUNKTION: UI-Elemente erstellen
--------------------------------------------------
local function createElement(className, properties, parent)
	local obj = Instance.new(className)
	for prop, val in pairs(properties) do
		obj[prop] = val
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end

--------------------------------------------------
-- GUI ERSTELLEN (Sauber innerhalb des Rahmens)
--------------------------------------------------
local flyGui = createElement("ScreenGui", {Name = "FlyGui", ResetOnSpawn = false}, player:WaitForChild("PlayerGui"))

-- Hauptfenster: Größe 220x170, sodass alles reinpasst
local mainFrame = createElement("Frame", {
	Name = "MainFrame",
	Size = UDim2.new(0, 220, 0, 170),
	Position = UDim2.new(0.5, -110, 0.5, -85),
	BackgroundColor3 = Color3.fromRGB(35, 35, 40),
	BorderSizePixel = 0,
	Active = true
}, flyGui)
createElement("UICorner", {CornerRadius = UDim.new(0, 10)}, mainFrame)

-- Titel
local titleLabel = createElement("TextLabel", {
	Name = "TitleLabel",
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.new(0, 0, 0, 0),
	BackgroundTransparency = 1,
	Text = "Superman Fly",
	Font = Enum.Font.GothamBold,
	TextSize = 24,
	TextColor3 = Color3.new(1, 1, 1)
}, mainFrame)

-- Toggle Button (An/Aus Flugmodus)
local toggleButton = createElement("TextButton", {
	Name = "ToggleButton",
	Size = UDim2.new(0.9, 0, 0, 30),
	Position = UDim2.new(0.05, 0, 0, 45),
	BackgroundColor3 = Color3.fromRGB(200, 50, 50),
	Text = "FLY: OFF",
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0
}, mainFrame)
createElement("UICorner", {CornerRadius = UDim.new(0, 8)}, toggleButton)

-- Speed Control Panel
local speedFrame = createElement("Frame", {
	Name = "SpeedFrame",
	Size = UDim2.new(0, 200, 0, 30),
	Position = UDim2.new(0, 10, 0, 80),
	BackgroundTransparency = 1
}, mainFrame)

local minusButton = createElement("TextButton", {
	Name = "MinusButton",
	Size = UDim2.new(0, 30, 0, 30),
	Position = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = Color3.fromRGB(50, 50, 50),
	Text = "–",
	Font = Enum.Font.GothamBold,
	TextSize = 24,
	TextColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0
}, speedFrame)
createElement("UICorner", {CornerRadius = UDim.new(0, 8)}, minusButton)

local speedTextBox = createElement("TextBox", {
	Name = "SpeedTextBox",
	Size = UDim2.new(0, 140, 0, 30),
	Position = UDim2.new(0, 30, 0, 0),
	BackgroundColor3 = Color3.fromRGB(50, 50, 50),
	Text = tostring(flightSpeed),
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1),
	ClearTextOnFocus = false,
	BorderSizePixel = 0,
	TextScaled = true
}, speedFrame)
createElement("UICorner", {CornerRadius = UDim.new(0, 8)}, speedTextBox)

local plusButton = createElement("TextButton", {
	Name = "PlusButton",
	Size = UDim2.new(0, 30, 0, 30),
	Position = UDim2.new(0, 170, 0, 0),
	BackgroundColor3 = Color3.fromRGB(50, 50, 50),
	Text = "+",
	Font = Enum.Font.GothamBold,
	TextSize = 24,
	TextColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0
}, speedFrame)
createElement("UICorner", {CornerRadius = UDim.new(0, 8)}, plusButton)

-- Keybind Button
local keybindButton = createElement("TextButton", {
	Name = "KeybindButton",
	Size = UDim2.new(0.9, 0, 0, 30),
	Position = UDim2.new(0.05, 0, 0, 120),
	BackgroundColor3 = Color3.fromRGB(50, 50, 50),
	Text = "KEYBIND: " .. toggleKey.Name,
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0
}, mainFrame)
createElement("UICorner", {CornerRadius = UDim.new(0, 8)}, keybindButton)

-- Close Button (Bleibt in der Ecke)
local closeButton = createElement("TextButton", {
	Name = "CloseButton",
	Size = UDim2.new(0, 30, 0, 30),
	Position = UDim2.new(1, -35, 0, 5),
	BackgroundColor3 = Color3.fromRGB(200, 50, 50),
	Text = "X",
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0
}, mainFrame)
createElement("UICorner", {CornerRadius = UDim.new(0, 8)}, closeButton)

--------------------------------------------------
-- GUI: Drag & Drop (Hauptframe verschiebbar)
--------------------------------------------------
local dragging = false
local dragStartPos, dragStartMousePos

mainFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStartPos = mainFrame.Position
		dragStartMousePos = input.Position
	end
end)

mainFrame.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStartMousePos
		mainFrame.Position = UDim2.new(dragStartPos.X.Scale, dragStartPos.X.Offset + delta.X, dragStartPos.Y.Scale, dragStartPos.Y.Offset + delta.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)

--------------------------------------------------
-- Fluggeschwindigkeit anpassen
--------------------------------------------------
speedTextBox.FocusLost:Connect(function()
	local newSpeed = tonumber(speedTextBox.Text)
	if newSpeed then
		flightSpeed = newSpeed
	else
		speedTextBox.Text = tostring(flightSpeed)
	end
end)

-- Plus/Minus Button Ereignisse zum Erhöhen/Verringern der Geschwindigkeit
local speedStep = 5  -- Schrittweite

plusButton.MouseButton1Click:Connect(function()
	flightSpeed = flightSpeed + speedStep
	speedTextBox.Text = tostring(flightSpeed)
end)

minusButton.MouseButton1Click:Connect(function()
	flightSpeed = math.max(0, flightSpeed - speedStep)
	speedTextBox.Text = tostring(flightSpeed)
end)

--------------------------------------------------
-- Umschalten des Keybinds
--------------------------------------------------
keybindButton.MouseButton1Click:Connect(function()
	waitingForKeybind = true
	keybindButton.Text = "PRESS ANY KEY..."
	keybindButton.BackgroundColor3 = Color3.fromRGB(75, 255, 75)
end)

--------------------------------------------------
-- GLOBALE TASTEN- UND KEYBIND-VERARBEITUNG
--------------------------------------------------
local function onGlobalInput(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if waitingForKeybind then
			-- Ignoriere Modifier
			local ignored = {
				Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
				Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl,
				Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt,
				Enum.KeyCode.LeftSuper, Enum.KeyCode.RightSuper,
				Enum.KeyCode.Unknown
			}
			for _, key in ipairs(ignored) do
				if input.KeyCode == key then
					return
				end
			end
			waitingForKeybind = false
			toggleKey = input.KeyCode
			keybindButton.Text = "KEYBIND: " .. toggleKey.Name
			keybindButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		elseif input.KeyCode == toggleKey then
			-- Umschalten des Flugmodus
			if not isFlying then
				-- Flugmodus starten
				isFlying = true
				toggleButton.Text = "FLY: ON"
				local ti = TweenInfo.new(0.3)
				local tween = TweenService:Create(toggleButton, ti, {BackgroundColor3 = Color3.fromRGB(75, 255, 75)})
				tween:Play()
				
				-------------------------------
				-- FLUGMODUS STARTEN
				-------------------------------
				Workspace.Gravity = 0
				humanoid.PlatformStand = true
				-- Sofort-Animation beim Aktivieren (ID 10714347256, Startzeit 4 s, Speed 0)
				playAnimation(10714347256, 4, 0)
				
				-- Erstelle BodyGyro für Drehung
				local gyro = Instance.new("BodyGyro")
				gyro.Name = "FlyGyro"
				gyro.Parent = hrp
				gyro.P = 90000
				gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
				gyro.CFrame = hrp.CFrame
				
				-- Erstelle BodyVelocity für Bewegung
				local bv = Instance.new("BodyVelocity")
				bv.Name = "FlyVelocity"
				bv.Parent = hrp
				bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
				-- Setze einen minimalen Y-Vektor, damit die Physik aktiv bleibt
				bv.Velocity = Vector3.new(0, 0.1, 0)
				
				-- Reset des aktuellen Geschwindigkeitsvektors
				currentVelocity = Vector3.new(0, 0, 0)
				
				-- RenderStep-Update: Berechnet in jedem Frame die neue Position und Rotation
				local flightUpdate = RunService.RenderStepped:Connect(function(deltaTime)
					local cam = Workspace.CurrentCamera
					
					-- Berechne Input: Vorwärts (W) minus Rückwärts (S) und seitlich (A/D)
					local fwd = moveState.forward - moveState.backward
					local side = moveState.right - moveState.left
					
					-- Input-Vektor basierend auf der Kameraausrichtung
					local inputVec = (cam.CFrame.LookVector * fwd) + (cam.CFrame.RightVector * side)
					
					-- Falls Vorwärts gedrückt: füge einen leichten Höhenoffset hinzu
					if fwd ~= 0 then
						inputVec = inputVec + Vector3.new(0, 0.2 * fwd, 0)
					end
					
					-- Bobbing-Effekt: Wenn keinerlei Input vorhanden ist (Schwebezustand)
					local bobbing = math.sin(tick() * bobbingFrequency) * bobbingAmplitude
					local desiredVelocity = Vector3.new(0, 0, 0)
					if inputVec.Magnitude > 0 then
						desiredVelocity = inputVec.Unit * flightSpeed
					else
						-- Beim Schweben: sanftes Auf und Ab
						desiredVelocity = Vector3.new(0, bobbing, 0)
					end
					
					-- Sanfte Interpolation (Sliding/Inertia)
					currentVelocity = currentVelocity:Lerp(desiredVelocity, 0.1)
					bv.Velocity = currentVelocity
					
					-- Berechne gewünschte Rotation:
					-- Bei Vorwärtsflug neigen wir den Pitch auf -90° plus Roll,
					-- ansonsten erfolgt eine leichtere Pitch-Anpassung, wobei auch rückwärts
					-- (fwd < 0) geneigt wird.
					local desiredCF
					if fwd > 0 then
						desiredCF = cam.CFrame * CFrame.Angles(math.rad(-90), 0, math.rad(currentRoll))
					else
						desiredCF = cam.CFrame * CFrame.Angles(math.rad(-45 * fwd), 0, math.rad(currentRoll))
					end
					if currentCF then
						currentCF = currentCF:Lerp(desiredCF, lerpCoef)
					else
						currentCF = desiredCF
					end
					gyro.CFrame = currentCF
				end)
				table.insert(flightConns, flightUpdate)
				
				-- Verbinde Tasteneingaben für Richtungssteuerung im Flugmodus
				local function onFlyInputBegan(input, gameProc)
					if gameProc then return end
					if input.UserInputType == Enum.UserInputType.Keyboard then
						local key = input.KeyCode
						if key == Enum.KeyCode.W then
							moveState.forward = 1
							playAnimation(10714177846, 4.65, 0)
						elseif key == Enum.KeyCode.S then
							-- Bei Rückwärtsflug: Verwende dieselbe Animation wie beim Stehen (10714347256)
							moveState.backward = 1
							playAnimation(10714347256, 4, 0)
						elseif key == Enum.KeyCode.A then
							moveState.left = 1
							if moveState.forward > 0 then
								playAnimation(10714177846, 4.65, 0)
							end
						elseif key == Enum.KeyCode.D then
							moveState.right = 1
							if moveState.forward > 0 then
								playAnimation(10714177846, 4.65, 0)
							end
						end
					end
				end
				local flyBegan = UserInputService.InputBegan:Connect(onFlyInputBegan)
				table.insert(flightConns, flyBegan)
				
				local function onFlyInputEnded(input, gameProc)
					if input.UserInputType == Enum.UserInputType.Keyboard then
						local key = input.KeyCode
						if key == Enum.KeyCode.W then
							moveState.forward = 0
							playAnimation(10714347256, 4, 0)
						elseif key == Enum.KeyCode.S then
							moveState.backward = 0
							playAnimation(10714347256, 4, 0)
						elseif key == Enum.KeyCode.A then
							moveState.left = 0
							if moveState.forward > 0 then
								playAnimation(10714177846, 4.65, 0)
							end
						elseif key == Enum.KeyCode.D then
							moveState.right = 0
							if moveState.forward > 0 then
								playAnimation(10714177846, 4.65, 0)
							end
						end
					end
				end
				local flyEnded = UserInputService.InputEnded:Connect(onFlyInputEnded)
				table.insert(flightConns, flyEnded)
				
			else
				-- Flugmodus beenden
				isFlying = false
				toggleButton.Text = "FLY: OFF"
				local ti = TweenInfo.new(0.3)
				local tween = TweenService:Create(toggleButton, ti, {BackgroundColor3 = Color3.fromRGB(200, 50, 50)})
				tween:Play()
				
				Workspace.Gravity = originalGravity
				humanoid.PlatformStand = false
				stopAnimation()
				if hrp:FindFirstChild("FlyGyro") then hrp.FlyGyro:Destroy() end
				if hrp:FindFirstChild("FlyVelocity") then hrp.FlyVelocity:Destroy() end
				-- Trenne alle im Flugmodus verbundenen Events
				for _, conn in ipairs(flightConns) do
					if conn.Connected then conn:Disconnect() end
				end
				flightConns = {}
				moveState = {forward = 0, backward = 0, left = 0, right = 0}
			end
		end
	end
end
local globalInputConn = UserInputService.InputBegan:Connect(onGlobalInput)
table.insert(globalConns, globalInputConn)

--------------------------------------------------
-- Toggle-Button: Gleicher Effekt wie die Umschalttaste
--------------------------------------------------
toggleButton.MouseButton1Click:Connect(function()
	onGlobalInput({KeyCode = toggleKey, UserInputType = Enum.UserInputType.Keyboard}, false)
end)

--------------------------------------------------
-- CHARACTER-RELOAD: Aktualisiere Referenzen und beende Flugmodus (zur Sicherheit)
--------------------------------------------------
player.CharacterAdded:Connect(function(newChar)
	character = newChar
	humanoid = character:WaitForChild("Humanoid")
	hrp = character:WaitForChild("HumanoidRootPart")
	if isFlying then
		isFlying = false
		toggleButton.Text = "FLY: OFF"
		Workspace.Gravity = originalGravity
		humanoid.PlatformStand = false
		stopAnimation()
		if hrp:FindFirstChild("FlyGyro") then hrp.FlyGyro:Destroy() end
		if hrp:FindFirstChild("FlyVelocity") then hrp.FlyVelocity:Destroy() end
		for _, conn in ipairs(flightConns) do
			if conn.Connected then conn:Disconnect() end
		end
		flightConns = {}
		moveState = {forward = 0, backward = 0, left = 0, right = 0}
	end
end)

--------------------------------------------------
-- CLOSE-BUTTON: Aufräumen und Skript beenden
--------------------------------------------------
closeButton.MouseButton1Click:Connect(function()
	if isFlying then
		isFlying = false
		Workspace.Gravity = originalGravity
		humanoid.PlatformStand = false
		stopAnimation()
		if hrp:FindFirstChild("FlyGyro") then hrp.FlyGyro:Destroy() end
		if hrp:FindFirstChild("FlyVelocity") then hrp.FlyVelocity:Destroy() end
		for _, conn in ipairs(flightConns) do
			if conn.Connected then conn:Disconnect() end
		end
		flightConns = {}
	end
	for _, conn in ipairs(globalConns) do
		if conn.Connected then conn:Disconnect() end
	end
	flyGui:Destroy()
	script:Destroy()
end)
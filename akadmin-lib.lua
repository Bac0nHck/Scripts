-- https://absent.wtf/AKADMINLIB/LIB.lua
local pl = game:GetService("Players")
local ui = game:GetService("UserInputService")
local tw = game:GetService("TweenService")
local ss = game:GetService("SoundService")
local db = game:GetService("Debris")
local hs = game:GetService("HttpService")
local lp = pl.LocalPlayer
local cg = game:GetService("CoreGui")

local guiParent = cg
do
	local ok = pcall(function()
		local sg = Instance.new("ScreenGui")
		sg.Parent = cg
		sg:Destroy()
	end)
	if not ok then
		guiParent = lp:WaitForChild("PlayerGui")
	end
end

local notifQueue = {}
local notifGap = 10
local notifBaseY = 200

local guiCounter = 0
local activeInstances = {}

local LibClass = {}
LibClass.__index = LibClass

local function make(className, props)
	local obj = Instance.new(className)
	for k, v in pairs(props or {}) do
		obj[k] = v
	end
	return obj
end

local function addCorner(parent, radius)
	local c = make("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
	c.Parent = parent
	return c
end

local function tween(obj, goals, duration, style, direction)
	local info = TweenInfo.new(
		duration or 0.25,
		style or Enum.EasingStyle.Quint,
		direction or Enum.EasingDirection.Out
	)
	local t = tw:Create(obj, info, goals)
	t:Play()
	return t
end

local activeSounds = {}
local function playSound()
	for i = #activeSounds, 1, -1 do
		local sd = activeSounds[i]
		if not sd or not sd.Parent then
			table.remove(activeSounds, i)
		end
	end
	if #activeSounds < 8 then
		local sd = make("Sound", {
			SoundId = "rbxassetid://3023237993",
			Volume = 1,
			Parent = ss,
		})
		sd:Play()
		table.insert(activeSounds, sd)
		db:AddItem(sd, 5)
		sd.Ended:Connect(function()
			for i = #activeSounds, 1, -1 do
				if activeSounds[i] == sd then
					table.remove(activeSounds, i)
					break
				end
			end
		end)
	end
end

local function reflowNotifs()
	for i, nd in ipairs(notifQueue) do
		local yp = notifBaseY + (i - 1) * (nd.fh + notifGap)
		if nd.frame and nd.frame.Parent then
			tween(nd.frame, { Position = UDim2.new(1, -(nd.fw + 10), 0, yp) }, 0.3)
			nd.ypos = yp
		end
	end
end

local function sendNotif(title, subtitle, imageId, persistent)
	local nd = { fh = 0, fw = 0, ypos = 0, frame = nil, _persistent = false, _spawned = false }

	nd.dismiss = function()
		if not nd._spawned then
			nd._dismissed = true
			return
		end
		for i, v in ipairs(notifQueue) do
			if v == nd then
				table.remove(notifQueue, i)
				break
			end
		end
		if nd.frame and nd.frame.Parent then
			local fr = nd.frame
			local exitTween = tween(
				fr,
				{ Position = UDim2.new(1, 10, 0, nd.ypos) },
				0.4,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.In
			)
			exitTween.Completed:Connect(function()
				if fr and fr.Parent then fr:Destroy() end
			end)
		end
		reflowNotifs()
	end

	task.spawn(function()
		local hasImage = imageId ~= nil and imageId ~= ""
		local fh = hasImage and 105 or 72
		local fw = hasImage and 320 or 280
		nd.fh = fh
		nd.fw = fw

		local notifGui = guiParent:FindFirstChild("AK_NOTIF_GUI")
		if not notifGui then
			notifGui = make("ScreenGui", {
				Name = "AK_NOTIF_GUI",
				ResetOnSpawn = false,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				Parent = guiParent,
			})
		end

		if nd._dismissed then return end

		table.insert(notifQueue, nd)

		local yp = notifBaseY
		for i = 1, #notifQueue - 1 do
			yp = yp + notifQueue[i].fh + notifGap
		end
		nd.ypos = yp

		local fr = make("Frame", {
			Size = UDim2.new(0, fw, 0, fh),
			Position = UDim2.new(1, 10, 0, yp),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Parent = notifGui,
		})
		addCorner(fr, 12)
		nd.frame = fr

		make("TextLabel", {
			Size = UDim2.new(1, -12, 0, 16),
			Position = UDim2.new(0, 10, 0, 8),
			BackgroundTransparency = 1,
			Text = title and ("AK ADMIN  •  " .. title) or "AK ADMIN",
			TextColor3 = Color3.fromRGB(180, 180, 180),
			TextSize = 11,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = fr,
		})

		local textOffsetX = hasImage and 60 or 10
		local textOffsetW = hasImage and -65 or -20

		if hasImage then
			make("ImageLabel", {
				Size = UDim2.new(0, 38, 0, 38),
				Position = UDim2.new(0, 12, 0, 34),
				BackgroundTransparency = 1,
				Image = "rbxassetid://" .. tostring(imageId),
				ImageColor3 = Color3.fromRGB(255, 255, 255),
				Parent = fr,
			})
		end

		make("TextLabel", {
			Size = UDim2.new(1, textOffsetW, 0, 22),
			Position = UDim2.new(0, textOffsetX, 0, hasImage and 30 or 22),
			BackgroundTransparency = 1,
			Text = title or "",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 15,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = fr,
		})

		make("TextLabel", {
			Size = UDim2.new(1, textOffsetW, 0, hasImage and 34 or 22),
			Position = UDim2.new(0, textOffsetX, 0, hasImage and 54 or 46),
			BackgroundTransparency = 1,
			Text = subtitle or "",
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextSize = 12,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Parent = fr,
		})

		playSound()
		tween(fr, { Position = UDim2.new(1, -(fw + 10), 0, yp) }, 0.5, Enum.EasingStyle.Quint)

		nd._spawned = true

		if not persistent then
			task.wait(6)
			nd.dismiss()
		else
			nd._persistent = true
		end
	end)
	return nd
end

local function makeRow(parent, layoutOrder)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(20, 20, 20),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder or 1,
		Parent = parent,
	})
	addCorner(row, 10)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		PaddingLeft = UDim.new(0, 0),
		PaddingRight = UDim.new(0, 0),
		Parent = row,
	})
	return row
end

local function makeOrderCounter()
	local order = 0
	return function()
		order = order + 1
		return order
	end
end

function LibClass.new(title, hideKey)
	local self = setmetatable({}, LibClass)
	self._conns = {}
	self._closed = false
	self._listening = false
	self._toggles = {}
	self._keybinds = {}
	self._closeCallbacks = {}
	self._resizePending = false
	self._userResized = false
	self._minimized = false
	self._animating = false
	self._manualWidth = 300
	self._manualHeight = 300
	self._tabs = {}
	self._activeTab = nil
	self._activeTweens = {}
	self._hideKey = hideKey or Enum.KeyCode.RightShift
	self._orderCounter = makeOrderCounter()
	self._destroyed = false

	local function trackConn(c)
		table.insert(self._conns, c)
		return c
	end

	local function conn(signal, fn)
		return trackConn(signal:Connect(fn))
	end

	self._conn = conn

	local function disconnectAll()
		for _, c in ipairs(self._conns) do
			if c and c.Connected then
				c:Disconnect()
			end
		end
		self._conns = {}
		self._closed = true
		self._listening = false
		self._destroyed = true
	end

	self._disconnectAll = disconnectAll

	local titleKey = title or "__untitled__"
	self._titleKey = titleKey

	if activeInstances[titleKey] then
		for _, old in ipairs(activeInstances[titleKey]) do
			if not old._closed then
				for _, fn in ipairs(old._closeCallbacks or {}) do
					pcall(fn)
				end
				old._disconnectAll()
				if old.screenGui and old.screenGui.Parent then
					old.screenGui:Destroy()
				end
			end
		end
		activeInstances[titleKey] = nil
	end
	activeInstances[titleKey] = {}
	table.insert(activeInstances[titleKey], self)

	guiCounter = guiCounter + 1
	local guiName = "AK_ADMIN_LIB_" .. guiCounter .. "_" .. hs:GenerateGUID(false):gsub("-", ""):sub(1, 12)

	self.screenGui = make("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = guiParent,
	})

	self.mainFrame = make("Frame", {
		Size = UDim2.new(0, 300, 0, 40),
		Position = UDim2.new(0.5, -150, 0.5, -200),
		BackgroundColor3 = Color3.fromRGB(10, 10, 10),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Parent = self.screenGui,
	})
	addCorner(self.mainFrame, 14)
	make("UIStroke", {
		Color = Color3.fromRGB(60, 60, 60),
		Thickness = 1,
		Parent = self.mainFrame,
	})

	self.titleBar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = self.mainFrame,
	})

	make("TextLabel", {
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.new(0, 14, 0, 0),
		BackgroundTransparency = 1,
		Text = "AK ADMIN" .. (title and ("  •  " .. title) or ""),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.titleBar,
	})

	self.minimizeBtn = make("TextButton", {
		Size = UDim2.new(0, 24, 0, 24),
		Position = UDim2.new(1, -52, 0.5, -12),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.4,
		Text = "—",
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		BorderSizePixel = 0,
		Parent = self.titleBar,
	})
	addCorner(self.minimizeBtn, 8)

	self.closeBtn = make("TextButton", {
		Size = UDim2.new(0, 24, 0, 24),
		Position = UDim2.new(1, -26, 0.5, -12),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.4,
		Text = "X",
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		BorderSizePixel = 0,
		Parent = self.titleBar,
	})
	addCorner(self.closeBtn, 8)

	self.contentFrame = make("Frame", {
		Size = UDim2.new(1, 0, 1, -44),
		Position = UDim2.new(0, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = self.mainFrame,
	})

	self.tabContainer = make("Frame", {
		Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.contentFrame,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.tabContainer,
	})

	self.scrollFrame = make("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.new(0, 8, 0, 4),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
		ScrollBarImageTransparency = 0.6,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = self.contentFrame,
	})

	self.listLayout = make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.scrollFrame,
	})
	make("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = self.scrollFrame,
	})

	local resizeHandle = make("Frame", {
		Size = UDim2.new(0, 24, 0, 24),
		Position = UDim2.new(1, -6, 1, -6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = self.mainFrame,
	})

	local rLine1 = make("Frame", {
		Size = UDim2.new(0, 14, 0, 2),
		Position = UDim2.new(0, 2, 1, -11),
		BackgroundColor3 = Color3.fromRGB(120, 120, 120),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = resizeHandle,
	})
	addCorner(rLine1, 1)

	local rLine2 = make("Frame", {
		Size = UDim2.new(0, 2, 0, 14),
		Position = UDim2.new(1, -11, 0, 2),
		BackgroundColor3 = Color3.fromRGB(120, 120, 120),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = resizeHandle,
	})
	addCorner(rLine2, 1)


	local minW, minH = 200, 100
	local resizeDragging = false
	local resizeOrigin = nil
	local resizeStartSize = nil

	conn(resizeHandle.InputBegan, function(inp)
		if
			inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch
		then
			resizeDragging = true
			resizeOrigin = inp.Position
			resizeStartSize = self.mainFrame.AbsoluteSize
			self._userResized = true
		end
	end)

	conn(resizeHandle.MouseEnter, function()
		tween(rLine1, { BackgroundTransparency = 0 }, 0.1)
		tween(rLine2, { BackgroundTransparency = 0 }, 0.1)
	end)
	conn(resizeHandle.MouseLeave, function()
		tween(rLine1, { BackgroundTransparency = 0.3 }, 0.1)
		tween(rLine2, { BackgroundTransparency = 0.3 }, 0.1)
	end)

	local screenBounds = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	conn(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function()
		screenBounds = workspace.CurrentCamera.ViewportSize
	end)

	conn(ui.InputChanged, function(inp)
		if
			resizeDragging
			and (
				inp.UserInputType == Enum.UserInputType.MouseMovement
				or inp.UserInputType == Enum.UserInputType.Touch
			)
		then
			local delta = inp.Position - resizeOrigin
			local rawW = resizeStartSize.X + delta.X
			local rawH = resizeStartSize.Y + delta.Y
			local maxW = screenBounds.X - self.mainFrame.AbsolutePosition.X - 10
			local maxH = screenBounds.Y - self.mainFrame.AbsolutePosition.Y - 10
			local newW = math.clamp(rawW, minW, maxW)
			if self._minimized then
				self._manualWidth = newW
				self.mainFrame.Size = UDim2.new(0, newW, 0, 40)
			else
				local newH = math.clamp(rawH, minH, maxH)
				self._manualWidth = newW
				self._manualHeight = newH
				self.mainFrame.Size = UDim2.new(0, newW, 0, newH)
				self:_updateScroll()
			end
		end
	end)

	conn(ui.InputEnded, function(inp)
		if
			inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch
		then
			resizeDragging = false
		end
	end)

	local dragActive = false
	local dragOrigin = nil
	local dragStartPos = nil

	conn(self.titleBar.InputBegan, function(inp)
		if
			inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch
		then
			dragActive = true
			dragOrigin = inp.Position
			dragStartPos = self.mainFrame.Position
		end
	end)

	conn(ui.InputChanged, function(inp)
		if
			dragActive
			and (
				inp.UserInputType == Enum.UserInputType.MouseMovement
				or inp.UserInputType == Enum.UserInputType.Touch
			)
		then
			local delta = inp.Position - dragOrigin
			local newX = dragStartPos.X.Offset + delta.X
			local newY = dragStartPos.Y.Offset + delta.Y
			self.mainFrame.Position = UDim2.new(
				dragStartPos.X.Scale,
				newX,
				dragStartPos.Y.Scale,
				newY
			)
		end
	end)

	conn(ui.InputEnded, function(inp)
		if
			inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch
		then
			dragActive = false
		end
	end)

	conn(self.minimizeBtn.MouseButton1Click, function()
		self:minimize()
	end)

	conn(self.closeBtn.MouseButton1Click, function()
		for _, fn in ipairs(self._closeCallbacks) do
			pcall(fn)
		end
		if activeInstances[self._titleKey] then
			for i, v in ipairs(activeInstances[self._titleKey]) do
				if v == self then
					table.remove(activeInstances[self._titleKey], i)
					break
				end
			end
			if #activeInstances[self._titleKey] == 0 then
				activeInstances[self._titleKey] = nil
			end
		end
		disconnectAll()
		if self.screenGui and self.screenGui.Parent then
			self.screenGui:Destroy()
		end
	end)

	conn(self.minimizeBtn.MouseEnter, function()
		tween(self.minimizeBtn, { BackgroundTransparency = 0.1 }, 0.15)
	end)
	conn(self.minimizeBtn.MouseLeave, function()
		tween(self.minimizeBtn, { BackgroundTransparency = 0.4 }, 0.15)
	end)
	conn(self.closeBtn.MouseEnter, function()
		tween(self.closeBtn, { BackgroundTransparency = 0.1 }, 0.15)
	end)
	conn(self.closeBtn.MouseLeave, function()
		tween(self.closeBtn, { BackgroundTransparency = 0.4 }, 0.15)
	end)

	conn(ui.InputBegan, function(inp, gameProcessed)
		if gameProcessed then return end
		if self._closed then return end
		if inp.KeyCode == self._hideKey then
			self.mainFrame.Visible = not self.mainFrame.Visible
		end
		if not self._listening then
			for _, kb in pairs(self._keybinds) do
				if inp.KeyCode == kb.keyCode then
					pcall(kb.callback)
				end
			end
		end
	end)

	conn(self.listLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
		self:_scheduleResize()
	end)

	self:_updateScroll()
	return self
end

function LibClass:_scheduleResize()
	if self._resizePending then return end
	self._resizePending = true
	task.defer(function()
		self._resizePending = false
		if self._destroyed then return end
		if not self.mainFrame or not self.mainFrame.Parent then return end
		self:resize()
	end)
end

function LibClass:_updateScroll()
	local tabOffset = self.tabContainer.Visible and 32 or 0
	local contentSize = self._activeTab
		and self._activeTab.listLayout.AbsoluteContentSize.Y + 8
		or self.listLayout.AbsoluteContentSize.Y + 8

	self.scrollFrame.CanvasSize = UDim2.new(0, 0, 0, contentSize)
	if tabOffset > 0 then
		self.scrollFrame.Size = UDim2.new(1, -16, 1, -36)
		self.scrollFrame.Position = UDim2.new(0, 8, 0, 32)
	else
		self.scrollFrame.Size = UDim2.new(1, -16, 1, -8)
		self.scrollFrame.Position = UDim2.new(0, 8, 0, 4)
	end
end

function LibClass:resize()
	if self._minimized then return end
	self:_updateScroll()
	if self._userResized then return end

	local tabOffset = self.tabContainer.Visible and 32 or 0
	local contentSize = self._activeTab
		and self._activeTab.listLayout.AbsoluteContentSize.Y + 8
		or self.listLayout.AbsoluteContentSize.Y + 8

	local targetH = math.min(contentSize + tabOffset, 460)
	local finalH = math.max(40 + math.max(targetH, 20), 60)
	local curSize = self.mainFrame.Size

	if math.abs(curSize.Y.Offset - finalH) > 0.5 then
		for _, t in ipairs(self._activeTweens) do
			pcall(function() t:Cancel() end)
		end
		self._activeTweens = {}
		local t = tween(self.mainFrame, { Size = UDim2.new(0, curSize.X.Offset, 0, finalH) }, 0.2)
		table.insert(self._activeTweens, t)
		t.Completed:Connect(function()
			for i, v in ipairs(self._activeTweens) do
				if v == t then
					table.remove(self._activeTweens, i)
					break
				end
			end
		end)
	end
end

function LibClass:minimize()
	if self._animating then return end
	self._animating = true

	if not self._minimized then
		self._minimized = true
		self.minimizeBtn.Text = "+"
		local cw = self.mainFrame.AbsoluteSize.X
		local tweenDone = false
		local t = tween(self.mainFrame, { Size = UDim2.new(0, cw, 0, 40) }, 0.3)
		t.Completed:Connect(function()
			if not tweenDone then
				tweenDone = true
				self.contentFrame.Visible = false
				self._animating = false
			end
		end)
	else
		self._minimized = false
		self.minimizeBtn.Text = "—"
		self.contentFrame.Visible = true
		if self._userResized then
			self:_updateScroll()
			local t = tween(self.mainFrame, { Size = UDim2.new(0, self._manualWidth, 0, self._manualHeight) }, 0.3)
			t.Completed:Connect(function()
				self._animating = false
			end)
		else
			local tabOffset = self.tabContainer.Visible and 32 or 0
			local contentSize = self._activeTab
				and self._activeTab.listLayout.AbsoluteContentSize.Y + 8
				or self.listLayout.AbsoluteContentSize.Y + 8
			local targetH = math.min(contentSize + tabOffset, 460)
			local finalH = math.max(40 + math.max(targetH, 20), 60)
			local curW = self.mainFrame.AbsoluteSize.X
			local t = tween(self.mainFrame, { Size = UDim2.new(0, curW, 0, finalH) }, 0.3)
			t.Completed:Connect(function()
				self:_updateScroll()
				self._animating = false
			end)
		end
	end
end

function LibClass:addTab(name)
	local tabData = {
		name = name,
		lib = self,
		items = {},
		orderCounter = makeOrderCounter(),
	}

	local btn = make("TextButton", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.4,
		Text = "  " .. name .. "  ",
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		BorderSizePixel = 0,
		LayoutOrder = #self._tabs + 1,
		Parent = self.tabContainer,
	})
	addCorner(btn, 8)
	tabData.btn = btn

	tabData.frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.scrollFrame,
	})

	tabData.listLayout = make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabData.frame,
	})

	make("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 4),
		Parent = tabData.frame,
	})

	local libRef = self
	self._conn(tabData.listLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
		if libRef._destroyed then return end
		libRef:_scheduleResize()
		tabData.frame.Size = UDim2.new(1, 0, 0, tabData.listLayout.AbsoluteContentSize.Y + 8)
	end)

	table.insert(self._tabs, tabData)
	self.tabContainer.Visible = #self._tabs > 1

	if self.tabContainer.Visible then
		self.scrollFrame.Parent = self.contentFrame
		self.listLayout.Parent = nil
	end

	self._conn(btn.MouseButton1Click, function()
		self:switchTab(tabData)
	end)

	if #self._tabs == 1 then
		self:switchTab(tabData)
	end

	self:resize()
	return tabData
end

function LibClass:switchTab(tabData)
	for _, other in pairs(self._tabs) do
		other.frame.Visible = false
		tween(other.btn, {
			BackgroundTransparency = 0.6,
			TextColor3 = Color3.fromRGB(160, 160, 160),
		}, 0.15)
	end
	tabData.frame.Visible = true
	tween(tabData.btn, {
		BackgroundTransparency = 0.1,
		TextColor3 = Color3.fromRGB(255, 255, 255),
	}, 0.15)
	self._activeTab = tabData
	self:_updateScroll()
	self:resize()
end

function LibClass:_getTarget()
	if self._activeTab then
		return self._activeTab.frame, self._activeTab.listLayout, self._activeTab.orderCounter()
	end
	return self.scrollFrame, self.listLayout, self._orderCounter()
end

function LibClass:addButton(name, callback)
	local parent, _, layoutOrder = self:_getTarget()
	local row = makeRow(parent, layoutOrder)

	local btn = make("TextButton", {
		Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundColor3 = Color3.fromRGB(35, 35, 35),
		BackgroundTransparency = 0.3,
		Text = name,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		BorderSizePixel = 0,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = row,
	})
	make("UIPadding", {
		PaddingTop = UDim.new(0, 7),
		PaddingBottom = UDim.new(0, 7),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = btn,
	})
	addCorner(btn, 8)

	self._conn(btn.MouseEnter, function()
		tween(btn, { BackgroundTransparency = 0.05 }, 0.1)
	end)
	self._conn(btn.MouseLeave, function()
		tween(btn, { BackgroundTransparency = 0.3 }, 0.1)
	end)
	self._conn(btn.MouseButton1Click, function()
		tween(btn, { BackgroundTransparency = 0.3 }, 0.1)
		if callback then pcall(callback) end
	end)

	if self._activeTab then
		table.insert(self._activeTab.items, row)
	end
	self:resize()

	return {
		setText = function(text)
			btn.Text = text
		end,
		getText = function()
			return btn.Text
		end,
	}
end

function LibClass:addToggle(name, default, callback)
	local parent, _, layoutOrder = self:_getTarget()
	local row = makeRow(parent, layoutOrder)
	local state = default or false

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = row,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = inner,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inner,
	})

	make("TextLabel", {
		Size = UDim2.new(1, -60, 0, 26),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = inner,
	})

	local track = make("Frame", {
		Size = UDim2.new(0, 36, 0, 20),
		BackgroundColor3 = state and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 60),
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = inner,
	})
	addCorner(track, 10)

	local knob = make("Frame", {
		Size = UDim2.new(0, 14, 0, 14),
		Position = UDim2.new(0, state and 19 or 3, 0.5, -7),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = track,
	})
	addCorner(knob, 7)

	local function updateVisual(val)
		tween(track, { BackgroundColor3 = val and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 60) }, 0.15)
		tween(knob, { Position = UDim2.new(0, val and 19 or 3, 0.5, -7) }, 0.15)
	end

	local function setValue(val, fireCallback)
		state = val
		updateVisual(val)
		if fireCallback and callback then
			pcall(callback, val)
		end
	end

	self._conn(track.InputBegan, function(inp)
		if
			inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch
		then
			setValue(not state, true)
		end
	end)

	if self._activeTab then
		table.insert(self._activeTab.items, row)
	end
	self:resize()

	local obj = {}
	local mt = {}
	mt.__index = function(_, k)
		if k == "Value" then return state end
		return nil
	end
	mt.__newindex = function(_, k, v)
		if k == "Value" then
			setValue(v, false)
		else
			rawset(obj, k, v)
		end
	end
	setmetatable(obj, mt)

	obj.set = function(v, silent)
		setValue(v, not silent)
	end
	obj.get = function()
		return state
	end

	self._toggles[name] = obj
	return obj
end

function LibClass:addSlider(name, min, max, default, step, callback)
	if type(step) == "function" then
		callback = step
		step = 1
	end
	step = (type(step) == "number" and step > 0) and step or 1
	if min >= max then
		return {
			set = function() end,
			get = function() return min end,
		}
	end

	local range = max - min
	local steps = math.round(range / step)
	local correctedMax = min + steps * step

	local parent, _, layoutOrder = self:_getTarget()
	local row = makeRow(parent, layoutOrder)
	local current = math.clamp(default or min, min, correctedMax)
	current = min + math.round((current - min) / step) * step

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = row,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inner,
	})

	local headerRow = make("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = inner,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = headerRow,
	})

	make("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = headerRow,
	})

	local valueLabel = make("TextLabel", {
		Size = UDim2.new(0, 55, 1, 0),
		Position = UDim2.new(1, -55, 0, 0),
		BackgroundTransparency = 1,
		Text = tostring(current),
		TextColor3 = Color3.fromRGB(160, 160, 160),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = headerRow,
	})

	local sliderRow = make("Frame", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = inner,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = sliderRow,
	})

	local track = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 0.5, -3),
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		BorderSizePixel = 0,
		Parent = sliderRow,
	})
	addCorner(track, 3)

	local function getProgress(val)
		return (val - min) / (correctedMax - min)
	end

	local fill = make("Frame", {
		Size = UDim2.new(getProgress(current), 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(80, 200, 120),
		BorderSizePixel = 0,
		Parent = track,
	})
	addCorner(fill, 3)

	local knob = make("Frame", {
		Size = UDim2.new(0, 14, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(getProgress(current), 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = track,
	})
	addCorner(knob, 7)

	local function snapValue(raw)
		local stepped = min + math.round((raw - min) / step) * step
		return math.clamp(stepped, min, correctedMax)
	end

	local function applyValue(x)
		local ratio = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = min + ratio * (correctedMax - min)
		local snapped = snapValue(raw)
		current = snapped
		local p = getProgress(snapped)
		fill.Size = UDim2.new(p, 0, 1, 0)
		knob.Position = UDim2.new(p, 0, 0.5, 0)
		valueLabel.Text = tostring(snapped)
		if callback then pcall(callback, snapped) end
	end

	local sliderDragging = false
	self._conn(ui.InputChanged, function(inp)
		if
			sliderDragging
			and (
				inp.UserInputType == Enum.UserInputType.MouseMovement
				or inp.UserInputType == Enum.UserInputType.Touch
			)
		then
			applyValue(inp.Position.X)
		end
	end)
	self._conn(ui.InputEnded, function(inp)
		if
			inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch
		then
			sliderDragging = false
		end
	end)
	self._conn(track.InputBegan, function(inp)
		if
			inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch
		then
			sliderDragging = true
			applyValue(inp.Position.X)
		end
	end)

	if self._activeTab then
		table.insert(self._activeTab.items, row)
	end
	self:resize()

	return {
		set = function(v)
			current = snapValue(v)
			local p = getProgress(current)
			fill.Size = UDim2.new(p, 0, 1, 0)
			knob.Position = UDim2.new(p, 0, 0.5, 0)
			valueLabel.Text = tostring(current)
		end,
		get = function()
			return current
		end,
	}
end

function LibClass:addTextBox(name, placeholder, maxLength, callback)
	if type(maxLength) == "function" then
		callback = maxLength
		maxLength = 200
	end
	maxLength = maxLength or 200

	local parent, _, layoutOrder = self:_getTarget()
	local row = makeRow(parent, layoutOrder)

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = row,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inner,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = inner,
	})

	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = inner,
	})

	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = Color3.fromRGB(15, 15, 15),
		BackgroundTransparency = 0.3,
		PlaceholderText = placeholder or "",
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		PlaceholderColor3 = Color3.fromRGB(100, 100, 100),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		LayoutOrder = 2,
		Parent = inner,
	})
	addCorner(box, 6)

	self._conn(box:GetPropertyChangedSignal("Text"), function()
		if #box.Text > maxLength then
			box.Text = box.Text:sub(1, maxLength)
		end
	end)

	self._conn(box.FocusLost, function(enterPressed)
		if enterPressed and callback then
			pcall(callback, box.Text)
		end
	end)

	if self._activeTab then
		table.insert(self._activeTab.items, row)
	end
	self:resize()

	return {
		get = function() return box.Text end,
		set = function(v) box.Text = tostring(v):sub(1, maxLength) end,
		clear = function() box.Text = "" end,
	}
end

function LibClass:addDropdown(name, options, default, callback)
	if not options or #options == 0 then
		options = { "" }
	end

	local parent, _, layoutOrder = self:_getTarget()
	local row = makeRow(parent, layoutOrder)
	local isOpen = false
	local selected = default or options[1]
	local currentOptions = { table.unpack(options) }

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = row,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = inner,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inner,
	})

	make("TextLabel", {
		Size = UDim2.new(0.5, 0, 0, 26),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = inner,
	})

	local dropBtn = make("TextButton", {
		Size = UDim2.new(0.5, -8, 0, 24),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.3,
		Text = tostring(selected) .. " ▾",
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		BorderSizePixel = 0,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = inner,
	})
	addCorner(dropBtn, 7)

	local panel = make("Frame", {
		Size = UDim2.new(0, 140, 0, 0),
		BackgroundColor3 = Color3.fromRGB(18, 18, 18),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 30,
		Visible = false,
		Parent = self.screenGui,
	})
	addCorner(panel, 8)
	make("UIStroke", {
		Color = Color3.fromRGB(50, 50, 50),
		Thickness = 1,
		Parent = panel,
	})

	local panelLayout = make("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})
	make("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		Parent = panel,
	})

	self._conn(panelLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
		if not panel.Parent then return end
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		local contentH = panelLayout.AbsoluteContentSize.Y + 8
		local maxH = vp.Y - panel.AbsolutePosition.Y - 10
		panel.Size = UDim2.new(0, 140, 0, math.min(contentH, math.max(maxH, 30)))
	end)

	local optionConns = {}
	local optionConnSet = {}

	local function closePanel()
		isOpen = false
		panel.Visible = false
	end

	local function updatePanelPosition()
		local ap = dropBtn.AbsolutePosition
		local as = dropBtn.AbsoluteSize
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		local panelH = panel.AbsoluteSize.Y
		local yBelow = ap.Y + as.Y + 2
		local yAbove = ap.Y - panelH - 2
		local finalY = (yBelow + panelH > vp.Y) and yAbove or yBelow
		local finalX = math.clamp(ap.X, 4, vp.X - 144)
		panel.Position = UDim2.new(0, finalX, 0, finalY)
	end

	local function buildOption(index, value)
		local optBtn = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BackgroundTransparency = 0.5,
			Text = value,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			TextSize = 11,
			Font = Enum.Font.Gotham,
			BorderSizePixel = 0,
			ZIndex = 31,
			LayoutOrder = index,
			Parent = panel,
		})
		addCorner(optBtn, 6)

		local c1 = optBtn.MouseEnter:Connect(function()
			tween(optBtn, { BackgroundTransparency = 0.1 }, 0.1)
		end)
		local c2 = optBtn.MouseLeave:Connect(function()
			tween(optBtn, { BackgroundTransparency = 0.5 }, 0.1)
		end)
		local c3 = optBtn.MouseButton1Click:Connect(function()
			selected = value
			dropBtn.Text = tostring(value) .. " ▾"
			closePanel()
			if callback then pcall(callback, value) end
		end)

		table.insert(optionConns, c1)
		table.insert(optionConns, c2)
		table.insert(optionConns, c3)
		optionConnSet[c1] = true
		optionConnSet[c2] = true
		optionConnSet[c3] = true
		table.insert(self._conns, c1)
		table.insert(self._conns, c2)
		table.insert(self._conns, c3)
	end

	for i, v in ipairs(currentOptions) do
		buildOption(i, v)
	end

	self._conn(dropBtn.MouseButton1Click, function()
		if isOpen then
			closePanel()
		else
			isOpen = true
			updatePanelPosition()
			panel.Visible = true
		end
	end)

	self._conn(dropBtn:GetPropertyChangedSignal("AbsolutePosition"), function()
		if isOpen then
			updatePanelPosition()
		end
	end)

	if self._activeTab then
		table.insert(self._activeTab.items, row)
	end
	self:resize()

	return {
		get = function() return selected end,
		set = function(v)
			selected = v
			dropBtn.Text = tostring(v) .. " ▾"
		end,
		refresh = function(newOptions)
			if not newOptions or #newOptions == 0 then
				newOptions = { "" }
			end
			currentOptions = { table.unpack(newOptions) }

			for _, c in ipairs(optionConns) do
				if c and c.Connected then
					c:Disconnect()
				end
			end
			for i = #self._conns, 1, -1 do
				if optionConnSet[self._conns[i]] then
					table.remove(self._conns, i)
				end
			end
			optionConns = {}
			optionConnSet = {}

			for _, ch in pairs(panel:GetChildren()) do
				if ch:IsA("TextButton") then
					ch:Destroy()
				end
			end
			for i, v in ipairs(currentOptions) do
				buildOption(i, v)
			end
		end,
		destroy = function()
			closePanel()
			for _, c in ipairs(optionConns) do
				if c and c.Connected then c:Disconnect() end
			end
			for i = #self._conns, 1, -1 do
				if optionConnSet[self._conns[i]] then
					table.remove(self._conns, i)
				end
			end
			optionConns = {}
			optionConnSet = {}
			panel:Destroy()
		end,
	}
end

function LibClass:addKeybind(name, defaultKey, callback)
	local parent, _, layoutOrder = self:_getTarget()
	local row = makeRow(parent, layoutOrder)
	local currentKey = defaultKey
	local isListening = false
	local listenConn = nil

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = row,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = inner,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inner,
	})

	make("TextLabel", {
		Size = UDim2.new(1, -90, 0, 26),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = inner,
	})

	local keyBtn = make("TextButton", {
		Size = UDim2.new(0, 76, 0, 24),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.3,
		Text = currentKey and currentKey.Name or "None",
		TextColor3 = currentKey and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(160, 160, 160),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = inner,
	})
	addCorner(keyBtn, 7)

	local function registerKey(keyCode)
		currentKey = keyCode
		self._keybinds[name] = { keyCode = keyCode, callback = callback or function() end }
	end

	local function clearKey()
		currentKey = nil
		keyBtn.Text = "None"
		keyBtn.TextColor3 = Color3.fromRGB(160, 160, 160)
		self._keybinds[name] = nil
	end

	local function removeListenConn()
		if listenConn then
			if listenConn.Connected then listenConn:Disconnect() end
			local target = listenConn
			listenConn = nil
			for i = #self._conns, 1, -1 do
				if self._conns[i] == target then
					table.remove(self._conns, i)
					break
				end
			end
		end
	end

	local function stopListening()
		isListening = false
		self._listening = false
		removeListenConn()
		keyBtn.Text = currentKey and currentKey.Name or "None"
		keyBtn.TextColor3 = currentKey and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(160, 160, 160)
	end

	self._conn(keyBtn.MouseButton1Click, function()
		if self._closed then return end
		if isListening then
			stopListening()
			clearKey()
			return
		end
		removeListenConn()
		isListening = true
		self._listening = true
		keyBtn.Text = "..."
		keyBtn.TextColor3 = Color3.fromRGB(255, 200, 60)

		listenConn = ui.InputBegan:Connect(function(inp, gameProcessed)
			if gameProcessed then return end
			if self._closed then
				stopListening()
				return
			end
			if inp.KeyCode ~= Enum.KeyCode.Unknown then
				isListening = false
				self._listening = false
				removeListenConn()
				registerKey(inp.KeyCode)
				keyBtn.Text = inp.KeyCode.Name
				keyBtn.TextColor3 = Color3.fromRGB(80, 200, 120)
			end
		end)
		table.insert(self._conns, listenConn)
	end)

	if defaultKey then
		registerKey(defaultKey)
	end

	if self._activeTab then
		table.insert(self._activeTab.items, row)
	end
	self:resize()

	return {
		get = function() return currentKey end,
		set = function(v)
			currentKey = v
			keyBtn.Text = v and v.Name or "None"
			keyBtn.TextColor3 = v and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(160, 160, 160)
			if v then registerKey(v) else clearKey() end
		end,
	}
end

function LibClass:addHoldButton(name, keyCode, holdDuration, onActive, onInactive)
	holdDuration = holdDuration or 1
	local parent, _, layoutOrder = self:_getTarget()
	local row = makeRow(parent, layoutOrder)
	local isHolding = false
	local isActive = false
	local holdThread = nil
	local mouseHolding = false
	local keyHolding = false

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = row,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = inner,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inner,
	})

	local topRow = make("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = inner,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = topRow,
	})

	make("TextLabel", {
		Size = UDim2.new(1, -90, 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = topRow,
	})

	local keyLabel = make("TextLabel", {
		Size = UDim2.new(0, 82, 1, 0),
		BackgroundTransparency = 1,
		Text = keyCode and ("[" .. keyCode.Name .. "]") or "[Hold]",
		TextColor3 = Color3.fromRGB(120, 120, 120),
		TextSize = 10,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 2,
		Parent = topRow,
	})

	local barBg = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = inner,
	})
	addCorner(barBg, 3)

	local barFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(80, 200, 120),
		BorderSizePixel = 0,
		Parent = barBg,
	})
	addCorner(barFill, 3)

	local statusLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Text = "Inactive",
		TextColor3 = Color3.fromRGB(120, 120, 120),
		TextSize = 10,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		Parent = inner,
	})

	local holdBtn = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
		Parent = row,
	})

	local function stopHold()
		if holdThread then
			task.cancel(holdThread)
			holdThread = nil
		end
		isHolding = false
		isActive = false
		tween(barFill, { Size = UDim2.new(0, 0, 1, 0) }, 0.2)
		if statusLabel and statusLabel.Parent then
			statusLabel.Text = "Inactive"
			statusLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
		end
		if onInactive then pcall(onInactive) end
	end

	local function startHold()
		if isHolding then return end
		isHolding = true
		isActive = true
		if statusLabel and statusLabel.Parent then
			statusLabel.Text = "Active"
			statusLabel.TextColor3 = Color3.fromRGB(80, 200, 120)
		end
		if onActive then pcall(onActive) end
		holdThread = task.spawn(function()
			local startTime = tick()
			while isHolding do
				local elapsed = tick() - startTime
				local progress = math.clamp(elapsed / holdDuration, 0, 1)
				if barFill and barFill.Parent then
					barFill.Size = UDim2.new(progress, 0, 1, 0)
				end
				task.wait()
			end
		end)
	end

	self._conn(holdBtn.InputBegan, function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			mouseHolding = true
			startHold()
		end
	end)

	self._conn(holdBtn.InputEnded, function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			mouseHolding = false
			if not keyHolding then
				stopHold()
			end
		end
	end)

	if keyCode then
		keyLabel.Text = "[" .. keyCode.Name .. "] or [Hold]"
		self._conn(ui.InputBegan, function(inp, gameProcessed)
			if gameProcessed then return end
			if self._closed then return end
			if self._listening then return end
			if inp.KeyCode == keyCode then
				keyHolding = true
				startHold()
			end
		end)

		self._conn(ui.InputEnded, function(inp)
			if inp.KeyCode == keyCode then
				keyHolding = false
				if not mouseHolding then
					stopHold()
				end
			end
		end)
	end

	if self._activeTab then
		table.insert(self._activeTab.items, row)
	end
	self:resize()

	return {
		isActive = function() return isActive end,
		setActive = function(val)
			isActive = val
			if isActive then
				if barFill and barFill.Parent then
					barFill.Size = UDim2.new(1, 0, 1, 0)
				end
				if statusLabel and statusLabel.Parent then
					statusLabel.Text = "Active"
					statusLabel.TextColor3 = Color3.fromRGB(80, 200, 120)
				end
			else
				if barFill and barFill.Parent then
					tween(barFill, { Size = UDim2.new(0, 0, 1, 0) }, 0.2)
				end
				if statusLabel and statusLabel.Parent then
					statusLabel.Text = "Inactive"
					statusLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
				end
			end
		end,
	}
end

function LibClass:addSection(name)
	local parent, _, layoutOrder = self:_getTarget()

	local sectionFrame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	make("Frame", {
		Size = UDim2.new(1, -16, 0, 1),
		Position = UDim2.new(0, 8, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(55, 55, 55),
		BorderSizePixel = 0,
		Parent = sectionFrame,
	})
	make("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = "  " .. name .. "  ",
		TextColor3 = Color3.fromRGB(140, 140, 140),
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		BorderSizePixel = 0,
		Parent = sectionFrame,
	})

	if self._activeTab then
		table.insert(self._activeTab.items, sectionFrame)
	end
	self:resize()
	return sectionFrame
end

function LibClass:addSeparator()
	local parent, _, layoutOrder = self:_getTarget()

	local sep = make("Frame", {
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	make("Frame", {
		Size = UDim2.new(1, -16, 0, 1),
		Position = UDim2.new(0, 8, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(45, 45, 45),
		BorderSizePixel = 0,
		Parent = sep,
	})

	if self._activeTab then
		table.insert(self._activeTab.items, sep)
	end
	self:resize()
	return sep
end

function LibClass:addLabel(text)
	local parent, _, layoutOrder = self:_getTarget()

	local labelFrame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = labelFrame,
	})

	local textLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(170, 170, 170),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = labelFrame,
	})

	if self._activeTab then
		table.insert(self._activeTab.items, labelFrame)
	end
	self:resize()

	return {
		set = function(v) textLabel.Text = v end,
		get = function() return textLabel.Text end,
	}
end

function LibClass:addStatus(name, initialValue)
	local parent, _, layoutOrder = self:_getTarget()
	local row = makeRow(parent, layoutOrder)

	local inner = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = row,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = inner,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inner,
	})

	make("TextLabel", {
		Size = UDim2.new(0.5, 0, 0, 26),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = Color3.fromRGB(170, 170, 170),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = inner,
	})

	local valueLabel = make("TextLabel", {
		Size = UDim2.new(0.5, 0, 0, 26),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = initialValue or "—",
		TextColor3 = Color3.fromRGB(80, 200, 120),
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = inner,
	})

	if self._activeTab then
		table.insert(self._activeTab.items, row)
	end
	self:resize()

	return {
		set = function(v, color)
			valueLabel.Text = tostring(v)
			if color then valueLabel.TextColor3 = color end
		end,
		get = function() return valueLabel.Text end,
	}
end

function LibClass:addPlayerList(labelOrCallback, callback)
	local toggleMode = false
	local actionLabel = "Select"
	local actionCallback = nil

	if type(labelOrCallback) == "function" then
		actionCallback = labelOrCallback
		toggleMode = true
	elseif type(labelOrCallback) == "string" then
		actionLabel = labelOrCallback
		actionCallback = callback
		toggleMode = false
	end

	local parent, _, layoutOrder = self:_getTarget()

	local wrapper = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = wrapper,
	})

	local header = make("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = wrapper,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = header,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = header,
	})

	local countLabel = make("TextLabel", {
		Size = UDim2.new(1, -58, 1, 0),
		BackgroundTransparency = 1,
		Text = "Players  •  " .. #pl:GetPlayers(),
		TextColor3 = Color3.fromRGB(140, 140, 140),
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = header,
	})

	local refreshBtn = make("TextButton", {
		Size = UDim2.new(0, 54, 0, 20),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.3,
		Text = "↻ Refresh",
		TextColor3 = Color3.fromRGB(160, 160, 160),
		TextSize = 10,
		Font = Enum.Font.Gotham,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = header,
	})
	addCorner(refreshBtn, 6)

	local listFrame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = wrapper,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = listFrame,
	})
	make("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 2),
		Parent = listFrame,
	})

	local libRef = self
	local selectedPlayer = nil
	local cardMap = {}
	local pendingThumbs = {}
	local buildConns = {}
	local buildConnsSet = {}

	local function buildList()
		for _, c in ipairs(buildConns) do
			if c and c.Connected then c:Disconnect() end
		end
		for i = #libRef._conns, 1, -1 do
			if buildConnsSet[libRef._conns[i]] then
				table.remove(libRef._conns, i)
			end
		end
		buildConns = {}
		buildConnsSet = {}

		local function buildConn(signal, fn)
			local c = signal:Connect(fn)
			table.insert(buildConns, c)
			buildConnsSet[c] = true
			table.insert(libRef._conns, c)
			return c
		end

		for _, pending in ipairs(pendingThumbs) do
			pending.cancelled = true
		end
		pendingThumbs = {}

		selectedPlayer = nil
		cardMap = {}

		for _, ch in pairs(listFrame:GetChildren()) do
			if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
				ch:Destroy()
			end
		end

		local players = pl:GetPlayers()
		countLabel.Text = "Players  •  " .. #players

		for idx, player in ipairs(players) do
			local card = make("Frame", {
				Size = UDim2.new(1, 0, 0, 52),
				BackgroundColor3 = Color3.fromRGB(20, 20, 20),
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
				LayoutOrder = idx,
				Parent = listFrame,
			})
			addCorner(card, 10)
			cardMap[player] = card

			local thumbImg = make("ImageLabel", {
				Size = UDim2.new(0, 38, 0, 38),
				Position = UDim2.new(0, 8, 0.5, -19),
				BackgroundColor3 = Color3.fromRGB(30, 30, 30),
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				Image = "",
				Parent = card,
			})
			addCorner(thumbImg, 8)

			local textRight = (not toggleMode and actionCallback) and -134 or -58

			make("TextLabel", {
				Size = UDim2.new(1, textRight, 0, 18),
				Position = UDim2.new(0, 54, 0, 8),
				BackgroundTransparency = 1,
				Text = player.DisplayName,
				TextColor3 = Color3.fromRGB(240, 240, 240),
				TextSize = 12,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = card,
			})

			make("TextLabel", {
				Size = UDim2.new(1, textRight, 0, 14),
				Position = UDim2.new(0, 54, 0, 28),
				BackgroundTransparency = 1,
				Text = "@" .. player.Name,
				TextColor3 = Color3.fromRGB(110, 110, 110),
				TextSize = 10,
				Font = Enum.Font.Gotham,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = card,
			})

			if toggleMode then
				local clickBtn = make("TextButton", {
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 1,
					Text = "",
					Parent = card,
				})
				buildConn(clickBtn.MouseButton1Click, function()
					if selectedPlayer and cardMap[selectedPlayer] and cardMap[selectedPlayer].Parent then
						tween(cardMap[selectedPlayer], {
							BackgroundColor3 = Color3.fromRGB(20, 20, 20),
							BackgroundTransparency = 0.4,
						}, 0.15)
					end
					if selectedPlayer == player then
						selectedPlayer = nil
						if actionCallback then pcall(actionCallback, player, false) end
					else
						selectedPlayer = player
						tween(card, {
							BackgroundColor3 = Color3.fromRGB(20, 80, 30),
							BackgroundTransparency = 0.25,
						}, 0.15)
						if actionCallback then pcall(actionCallback, player, true) end
					end
				end)
			else
				if actionCallback then
					local actBtn = make("TextButton", {
						Size = UDim2.new(0, 68, 0, 26),
						Position = UDim2.new(1, -76, 0.5, -13),
						BackgroundColor3 = Color3.fromRGB(35, 35, 35),
						BackgroundTransparency = 0.2,
						Text = actionLabel,
						TextColor3 = Color3.fromRGB(220, 220, 220),
						TextSize = 11,
						Font = Enum.Font.Gotham,
						BorderSizePixel = 0,
						Parent = card,
					})
					addCorner(actBtn, 7)
					buildConn(actBtn.MouseEnter, function()
						tween(actBtn, { BackgroundTransparency = 0.0, TextColor3 = Color3.fromRGB(255, 255, 255) }, 0.1)
					end)
					buildConn(actBtn.MouseLeave, function()
						tween(actBtn, { BackgroundTransparency = 0.2, TextColor3 = Color3.fromRGB(220, 220, 220) }, 0.1)
					end)
					buildConn(actBtn.MouseButton1Click, function()
						pcall(actionCallback, player)
					end)
				end
			end

			local thumbEntry = { cancelled = false }
			table.insert(pendingThumbs, thumbEntry)

			task.spawn(function()
				local ok, img = pcall(function()
					return pl:GetUserThumbnailAsync(
						player.UserId,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size48x48
					)
				end)
				if not thumbEntry.cancelled and ok and thumbImg and thumbImg.Parent then
					pcall(function()
						thumbImg.Image = img
					end)
				end
			end)
		end

		libRef:resize()
	end

	buildList()

	self._conn(refreshBtn.MouseEnter, function()
		tween(refreshBtn, { BackgroundTransparency = 0.05, TextColor3 = Color3.fromRGB(200, 200, 200) }, 0.1)
	end)
	self._conn(refreshBtn.MouseLeave, function()
		tween(refreshBtn, { BackgroundTransparency = 0.3, TextColor3 = Color3.fromRGB(160, 160, 160) }, 0.1)
	end)
	self._conn(refreshBtn.MouseButton1Click, function()
		buildList()
	end)

	if self._activeTab then
		table.insert(self._activeTab.items, wrapper)
	end
	self:resize()

	return {
		refresh = buildList,
		getSelected = function() return selectedPlayer end,
	}
end

function LibClass:onClose(fn)
	table.insert(self._closeCallbacks, fn)
end

function LibClass:addConnection(signal, fn)
	return self._conn(signal, fn)
end

function LibClass:notify(title, subtitle, imageId, persistent)
	local nd = sendNotif(title, subtitle, imageId, persistent)
	return nd
end

return LibClass

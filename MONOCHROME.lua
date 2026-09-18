local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Player = Players.LocalPlayer
local Environment = getgenv and getgenv() or _G
local Previous = Environment.__MONOCHROME_AIRFLOW

if Previous and type(Previous.Unload) == "function" then
    Previous:Unload()
end

local LibraryURL = "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"
local Success, Airflow = pcall(function()
    return loadstring(game:HttpGet(LibraryURL))()
end)

if not Success or type(Airflow) ~= "table" then
    error("MONOCHROME: Airflow could not be loaded. " .. tostring(Airflow))
end

Airflow.Theme.Background = Color3.fromRGB(18, 20, 23)
Airflow.Theme.Surface = Color3.fromRGB(24, 27, 31)
Airflow.Theme.Surface2 = Color3.fromRGB(31, 35, 40)
Airflow.Theme.Surface3 = Color3.fromRGB(43, 48, 55)
Airflow.Theme.Stroke = Color3.fromRGB(46, 52, 59)
Airflow.Theme.StrokeHover = Color3.fromRGB(99, 119, 124)
Airflow.Theme.Accent = Color3.fromRGB(173, 226, 218)
Airflow.Theme.AccentDark = Color3.fromRGB(19, 32, 32)
Airflow.Theme.Text = Color3.fromRGB(238, 242, 244)
Airflow.Theme.Muted = Color3.fromRGB(154, 164, 176)

local App = {
    Alive = true,
    Generation = 0,
    Options = {},
    Controls = {},
    Connections = {},
    Overrides = {},
    Markers = {},
    Prompts = {},
    Cooldowns = setmetatable({}, {__mode = "k"}),
    BusyPrompts = setmetatable({}, {__mode = "k"}),
    Code = nil,
    Status = "Ready",
    SolverStatus = "Off",
    Dirty = true,
    NextSolve = 0,
}

Environment.__MONOCHROME_AIRFLOW = App

function App:Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self.Connections, connection)
    return connection
end

function App:Notify(title, content)
    if self.Alive and self.Window then
        self.Window:Notify({Title = title, Content = content, Duration = 3})
    end
end

function App:Override(group, object, property, value)
    local entries = self.Overrides[group]
    if not entries then
        entries = {}
        self.Overrides[group] = entries
    end
    local properties = entries[object]
    if not properties then
        properties = {}
        entries[object] = properties
    end
    if properties[property] then
        return
    end
    local ok, original = pcall(function() return object[property] end)
    if not ok then
        return
    end
    local entry = {Original = original, Value = value, Writing = false}
    properties[property] = entry
    local function apply()
        if not object.Parent or entry.Writing then
            return
        end
        local current = object[property]
        if current ~= entry.Value then
            entry.Original = current
            entry.Writing = true
            object[property] = entry.Value
            entry.Writing = false
        end
    end
    entry.Connection = object:GetPropertyChangedSignal(property):Connect(apply)
    entry.Writing = true
    object[property] = value
    entry.Writing = false
end

function App:Restore(group)
    local entries = self.Overrides[group]
    if not entries then
        return
    end
    self.Overrides[group] = nil
    for object, properties in pairs(entries) do
        for property, entry in pairs(properties) do
            entry.Connection:Disconnect()
            pcall(function()
                if object.Parent and object[property] == entry.Value then
                    object[property] = entry.Original
                end
            end)
        end
    end
end

function App:PruneOverrides()
    for _, entries in pairs(self.Overrides) do
        for object, properties in pairs(entries) do
            if not object:IsDescendantOf(game) then
                for _, entry in pairs(properties) do
                    entry.Connection:Disconnect()
                end
                entries[object] = nil
            end
        end
    end
end

function App:GetRoot()
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 or Player:GetAttribute("Downed") then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart")
end

function App:GetPart(object)
    if not object then
        return nil
    elseif object:IsA("BasePart") then
        return object
    elseif object:IsA("Attachment") then
        return self:GetPart(object.Parent)
    elseif object:IsA("Model") then
        return object.PrimaryPart or object:FindFirstChild("RootPart") or object:FindFirstChild("HumanoidRootPart") or object:FindFirstChildWhichIsA("BasePart", true)
    end
end

function App:ReadCode()
    local map = workspace:FindFirstChild("monochrome")
    local note = map and map:FindFirstChild("CodeNote")
    local printed = note and note:FindFirstChild("Printed")
    local digits = printed and printed:FindFirstChild("Digits")
    local code = digits and digits:IsA("TextLabel") and digits.Text:gsub("<[^>]*>", ""):gsub("%D", "") or nil
    if code and #code == 4 then
        self.Code = code
    else
        self.Code = nil
    end
    return self.Code
end

function App:UpdateReader()
    if not self.Reader then
        return
    end
    local code = self.Options.Reader and self:ReadCode() or nil
    local content = not self.Options.Reader and "Reader paused" or code and table.concat({code:sub(1, 1), code:sub(2, 2), code:sub(3, 3), code:sub(4, 4)}, "   ") or "Waiting for the code note"
    if content ~= self.ReaderText then
        self.ReaderText = content
        self.Reader:Set(content)
    end
    local status = "Keypad: " .. self.SolverStatus .. "\n" .. self.Status
    if status ~= self.StatusText then
        self.StatusText = status
        self.StatusCard:Set(status)
    end
end

function App:Copy(value)
    if not value or value == "" then
        self:Notify("Nothing to copy", "The code note is not available yet.")
        return
    end
    local copy = setclipboard or toclipboard
    if type(copy) == "function" then
        local ok = pcall(copy, value)
        if ok then
            self:Notify("Copied", value)
            return
        end
    end
    self:Notify("Clipboard unavailable", value)
end

function App:Scan()
    self.Map = workspace:FindFirstChild("monochrome")
    self.Prompts = {}
    self.Targets = {}
    if self.Map then
        self.Prompts = self.Map:QueryDescendants("ProximityPrompt")
        for _, prompt in ipairs(self.Prompts) do
            local object = self:GetPart(prompt.Parent)
            if object then
                if prompt.Name == "DrawerPrompt" then
                    table.insert(self.Targets, {Object = object, Category = "Drawers", Label = "Drawer", Prompt = prompt})
                elseif prompt.Name == "HidePrompt" then
                    table.insert(self.Targets, {Object = object, Category = "Closets", Label = "Closet", Prompt = prompt})
                end
            end
        end
        for _, key in ipairs(self.Map:QueryDescendants("Model[$KeyId]")) do
            table.insert(self.Targets, {Object = key, Category = "Keys", Label = "Escape Key"})
        end
        local note = self.Map:FindFirstChild("CodeNote")
        if note then
            table.insert(self.Targets, {Object = note, Category = "Note", Label = "Code Note"})
        end
    end
    local monster = workspace:FindFirstChild("VER")
    if not monster or not self:GetPart(monster) then
        monster = workspace:FindFirstChild("MonsterNetwork")
    end
    if monster and self:GetPart(monster) then
        table.insert(self.Targets, {Object = monster, Category = "Monster", Label = "Monster"})
    end
    self.Dirty = false
    self:PruneOverrides()
end

function App:ApplyVisuals()
    if self.Options.Fullbright then
        for property, value in pairs({
            Brightness = 2,
            ClockTime = 14,
            Ambient = Color3.fromRGB(190, 190, 190),
            OutdoorAmbient = Color3.fromRGB(190, 190, 190),
            GlobalShadows = false,
            FogStart = 0,
            FogEnd = 100000,
            ExposureCompensation = 0,
        }) do
            self:Override("Fullbright", Lighting, property, value)
        end
        for _, atmosphere in ipairs(Lighting:QueryDescendants("Atmosphere")) do
            self:Override("Fullbright", atmosphere, "Density", 0)
            self:Override("Fullbright", atmosphere, "Haze", 0)
        end
        local grade = Lighting:FindFirstChild("HorrorGrade")
        if grade and grade:IsA("ColorCorrectionEffect") then
            self:Override("Fullbright", grade, "Brightness", 0)
            self:Override("Fullbright", grade, "Contrast", 0)
        end
    end
    if self.Options.CleanScreen then
        local gui = Player:FindFirstChildOfClass("PlayerGui")
        if gui then
            for _, name in ipairs({"PixelStatic", "AuthenticNTSCVHS"}) do
                local effect = gui:FindFirstChild(name)
                if effect and effect:IsA("ScreenGui") then
                    self:Override("CleanScreen", effect, "Enabled", false)
                end
            end
        end
        for _, parent in ipairs({Lighting, workspace.CurrentCamera or Lighting}) do
            for _, name in ipairs({"AuthenticNTSCVHSColor", "AuthenticNTSCVHSBlur"}) do
                local effect = parent:FindFirstChild(name)
                if effect and effect:IsA("PostEffect") then
                    self:Override("CleanScreen", effect, "Enabled", false)
                end
            end
        end
    end
    if self.Options.Instant then
        for _, prompt in ipairs(workspace:QueryDescendants("ProximityPrompt")) do
            self:Override("Instant", prompt, "HoldDuration", 0)
        end
    end
end

function App:ActivatePrompt(prompt, option)
    if self.BusyPrompts[prompt] or not prompt.Parent or not prompt.Enabled then
        return
    end
    local root, part = self:GetRoot(), self:GetPart(prompt.Parent)
    if not root or not part or (root.Position - part.Position).Magnitude > prompt.MaxActivationDistance then
        return
    end
    local now = os.clock()
    if now < (self.Cooldowns[prompt] or 0) then
        return
    end
    self.Cooldowns[prompt] = now + math.max(0.8, prompt.HoldDuration + 0.25)
    self.BusyPrompts[prompt] = true
    local generation = self.Generation
    task.spawn(function()
        local ok, err = pcall(function()
            if not self.Alive or generation ~= self.Generation or not self.Options[option] then
                return
            end
            if type(fireproximityprompt) == "function" then
                fireproximityprompt(prompt, self.Options.Instant and 0 or prompt.HoldDuration)
            else
                prompt:InputHoldBegin()
                local deadline = os.clock() + prompt.HoldDuration + 0.05
                repeat
                    task.wait(0.03)
                until not self.Alive or generation ~= self.Generation or not self.Options[option] or not prompt.Parent or os.clock() >= deadline
                pcall(function() prompt:InputHoldEnd() end)
            end
        end)
        self.BusyPrompts[prompt] = nil
        if not ok and self.Alive then
            self.Status = "Prompt unavailable: " .. tostring(err):sub(1, 80)
        end
    end)
end

function App:AutomatePrompts()
    for _, prompt in ipairs(self.Prompts) do
        if prompt.Parent then
            local part = self:GetPart(prompt.Parent)
            if part then
                if self.Options.AutoDrawers and prompt.Name == "DrawerPrompt" and part:GetAttribute("Open") ~= true then
                    self:ActivatePrompt(prompt, "AutoDrawers")
                elseif self.Options.AutoPlanks and prompt.Name == "PryPrompt" and part:GetAttribute("Pried") ~= true then
                    self:ActivatePrompt(prompt, "AutoPlanks")
                end
            end
        end
    end
end

function App:SolveStep()
    if not self.Options.AutoKeypad or os.clock() < self.NextSolve then
        return
    end
    self.NextSolve = os.clock() + 0.15
    local code, root = self:ReadCode(), self:GetRoot()
    local map = workspace:FindFirstChild("monochrome")
    local keypad = map and map:FindFirstChild("Keypad")
    if not code then
        self.SolverStatus = "Waiting for the code note"
        return
    elseif not keypad or not root then
        self.SolverStatus = "Waiting for the keypad"
        return
    end
    for index = 1, 4 do
        local digit = keypad:FindFirstChild("Digit" .. index)
        local readout = digit and digit:FindFirstChild("Readout")
        local label = readout and readout:FindFirstChild("Digit")
        local detector = digit and digit:FindFirstChildOfClass("ClickDetector")
        local prompt = digit and digit:FindFirstChild("DigitPrompt")
        if not digit or not label then
            self.SolverStatus = "Waiting for keypad digits"
            return
        end
        local current = tonumber(label.Text)
        local target = tonumber(code:sub(index, index))
        if current == nil then
            self.SolverStatus = "Waiting for keypad readout"
            return
        end
        if current ~= target then
            local range = detector and detector.MaxActivationDistance or prompt and prompt.MaxActivationDistance or 8
            if (root.Position - digit.Position).Magnitude > range then
                self.SolverStatus = "Move closer to the keypad"
                self.PendingDigit = nil
                return
            end
            local pending = self.PendingDigit
            if pending and pending.Object == digit and pending.Value == current and os.clock() - pending.Time < 1 then
                self.SolverStatus = "Waiting for digit " .. index
                return
            end
            local attempts = pending and pending.Object == digit and pending.Value == current and pending.Attempts + 1 or 1
            if attempts > 3 then
                self.SolverStatus = "Keypad is locked or out of reach"
                self.NextSolve = os.clock() + 2
                self.PendingDigit = nil
                return
            end
            if detector and type(fireclickdetector) == "function" then
                local ok = pcall(fireclickdetector, detector)
                if not ok then
                    self.SolverStatus = "Keypad interaction unavailable"
                    return
                end
            elseif prompt and prompt.Enabled then
                self:ActivatePrompt(prompt, "AutoKeypad")
            else
                self.SolverStatus = "This executor needs click detector support"
                self.NextSolve = os.clock() + 2
                return
            end
            self.PendingDigit = {Object = digit, Value = current, Time = os.clock(), Attempts = attempts}
            self.SolverStatus = "Setting digit " .. index .. " of 4"
            return
        end
    end
    self.PendingDigit = nil
    self.SolverStatus = "Solved: " .. code
    self.NextSolve = os.clock() + 0.75
end

local ESPColors = {
    Monster = Color3.fromRGB(255, 105, 109),
    Keys = Color3.fromRGB(255, 218, 112),
    Note = Color3.fromRGB(130, 214, 255),
    Closets = Color3.fromRGB(140, 232, 187),
    Drawers = Color3.fromRGB(193, 181, 233),
}

function App:RemoveMarker(object)
    local marker = self.Markers[object]
    if not marker then return end
    for _, drawing in ipairs(marker.Drawings) do
        pcall(function() drawing.Visible = false drawing:Remove() end)
    end
    self.Markers[object] = nil
end

function App:ClearMarkers(category)
    for object, marker in pairs(self.Markers) do
        if not category or marker.Category == category then self:RemoveMarker(object) end
    end
end

function App:NewMarker(target)
    local objects = {}
    local ok, marker = pcall(function()
        local outline = Drawing.new("Square")
        table.insert(objects, outline)
        outline.Visible = false
        outline.Filled = false
        outline.Color = Color3.new(0, 0, 0)
        outline.Thickness = 3
        outline.Transparency = 0.8
        outline.ZIndex = 1
        local box = Drawing.new("Square")
        table.insert(objects, box)
        box.Visible = false
        box.Filled = false
        box.Color = ESPColors[target.Category]
        box.Thickness = 1
        box.Transparency = 1
        box.ZIndex = 2
        local label = Drawing.new("Text")
        table.insert(objects, label)
        label.Visible = false
        label.Text = target.Label
        label.Center = true
        label.Outline = true
        label.OutlineColor = Color3.new(0, 0, 0)
        label.Color = ESPColors[target.Category]
        label.Size = UserInputService.TouchEnabled and 16 or 14
        label.Font = 2
        label.Transparency = 1
        label.ZIndex = 3
        return {Drawings = objects, Outline = outline, Box = box, Label = label, Category = target.Category, Name = target.Label, Prompt = target.Prompt}
    end)
    if not ok then
        for _, object in ipairs(objects) do pcall(function() object:Remove() end) end
        return nil, tostring(marker)
    end
    self.Markers[target.Object] = marker
    return marker
end

function App:UpdateESP()
    local wanted = {}
    for _, target in ipairs(self.Targets or {}) do
        local object = target.Object
        local part = self:GetPart(object)
        local valid = self.Options[target.Category] and object:IsDescendantOf(workspace) and part
        if valid and target.Category == "Drawers" then
            valid = object:GetAttribute("Open") ~= true and target.Prompt.Parent and target.Prompt.Enabled
        elseif valid and target.Category == "Keys" then
            valid = object:GetAttribute("Collected") ~= true and part.Transparency < 1
        end
        if valid then
            wanted[object] = true
            local marker = self.Markers[object]
            if not marker then
                local err
                marker, err = self:NewMarker(target)
                if not marker then
                    self:SetOption(target.Category, false)
                    self:Notify("Drawing ESP unavailable", err:sub(1, 100))
                end
            end
            if marker then
                local bounds, size
                if object:IsA("Model") then bounds, size = object:GetBoundingBox() else bounds, size = object.CFrame, object.Size end
                marker.Part = part
                marker.Offset = part.CFrame:ToObjectSpace(bounds)
                marker.HalfSize = size * 0.5
            end
        end
    end
    for object in pairs(self.Markers) do
        if not wanted[object] then self:RemoveMarker(object) end
    end
end

local BoxCorners = {
    Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1),
    Vector3.new(-1, 1, -1), Vector3.new(-1, 1, 1),
    Vector3.new(1, -1, -1), Vector3.new(1, -1, 1),
    Vector3.new(1, 1, -1), Vector3.new(1, 1, 1),
}

function App:RenderESP()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local root = self:GetRoot()
    local origin = root and root.Position or camera.CFrame.Position
    for object, marker in pairs(self.Markers) do
        local part = marker.Part
        local visible = self.Options[marker.Category] and object:IsDescendantOf(workspace) and part and part.Parent and marker.Offset
        if visible and marker.Category == "Drawers" then
            visible = object:GetAttribute("Open") ~= true and marker.Prompt.Parent and marker.Prompt.Enabled
        end
        if visible then
            local bounds = part.CFrame * marker.Offset
            if marker.Category == "Monster" and object:IsA("Model") then
                local size
                bounds, size = object:GetBoundingBox()
                marker.HalfSize = size * 0.5
            end
            local center = camera:WorldToViewportPoint(bounds.Position)
            visible = center.Z > 0.1
            if visible then
                local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
                local count = 0
                for _, corner in ipairs(BoxCorners) do
                    local point = camera:WorldToViewportPoint(bounds:PointToWorldSpace(corner * marker.HalfSize))
                    if point.Z > 0.1 then
                        left, top = math.min(left, point.X), math.min(top, point.Y)
                        right, bottom = math.max(right, point.X), math.max(bottom, point.Y)
                        count = count + 1
                    end
                end
                visible = count == 8 and right >= 0 and bottom >= 0 and left <= viewport.X and top <= viewport.Y
                if visible then
                    left, top = math.max(1, left), math.max(1, top)
                    right, bottom = math.min(viewport.X - 1, right), math.min(viewport.Y - 1, bottom)
                    local position = Vector2.new(math.floor(left), math.floor(top))
                    local size = Vector2.new(math.max(4, math.floor(right - left)), math.max(4, math.floor(bottom - top)))
                    marker.Outline.Position, marker.Outline.Size = position, size
                    marker.Box.Position, marker.Box.Size = position, size
                    marker.Label.Text = marker.Name .. " [" .. math.floor((origin - bounds.Position).Magnitude + 0.5) .. "]"
                    local halfText = math.min(marker.Label.TextBounds.X * 0.5 + 3, viewport.X * 0.5)
                    marker.Label.Position = Vector2.new(math.clamp((left + right) * 0.5, halfText, viewport.X - halfText), math.max(2, top - marker.Label.Size - 4))
                end
            end
        end
        for _, drawing in ipairs(marker.Drawings) do drawing.Visible = visible == true end
    end
end

function App:SetOption(name, value)
    if not self.Alive then return end
    if value and ESPColors[name] and (type(Drawing) ~= "table" or type(Drawing.new) ~= "function") then
        if self.Controls[name] then self.Controls[name]:Set(false, true) end
        self:Notify("Drawing ESP unavailable", "This executor does not provide Drawing Library.")
        return
    end
    self.Options[name] = value == true
    local control = self.Controls[name]
    if control and control:Get() ~= self.Options[name] then
        control:Set(self.Options[name], true)
    end
    if not value then
        self:Restore(name)
        if ESPColors[name] then self:ClearMarkers(name) end
        if name == "AutoKeypad" then
            self.PendingDigit = nil
            self.SolverStatus = "Off"
        end
        for prompt in pairs(self.BusyPrompts) do
            if (name == "AutoDrawers" and prompt.Name == "DrawerPrompt") or (name == "AutoPlanks" and prompt.Name == "PryPrompt") then
                pcall(function() prompt:InputHoldEnd() end)
            end
        end
    else
        self.Dirty = true
        if name == "AutoKeypad" then self.NextSolve = 0 end
        self:ApplyVisuals()
    end
    self:UpdateReader()
end

function App:StopAll()
    self.Generation = self.Generation + 1
    for name in pairs(self.Options) do
        self.Options[name] = false
        if self.Controls[name] then self.Controls[name]:Set(false, true) end
    end
    for prompt in pairs(self.BusyPrompts) do
        pcall(function() prompt:InputHoldEnd() end)
    end
    self:Restore("Instant")
    self:Restore("Fullbright")
    self:Restore("CleanScreen")
    self:ClearMarkers()
    self.PendingDigit = nil
    self.SolverStatus = "Off"
    self.Status = "All features stopped"
    self:UpdateReader()
end

function App:Unload()
    if not self.Alive then return end
    self:StopAll()
    self.Alive = false
    if self.RenderBinding then RunService:UnbindFromRenderStep(self.RenderBinding) end
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    self.Connections = {}
    if self.Window then self.Window:Destroy() end
    if Environment.__MONOCHROME_AIRFLOW == self then Environment.__MONOCHROME_AIRFLOW = nil end
end

local Window = Airflow:CreateWindow({
    Name = "MONOCHROME",
    Icon = "eye",
    ToggleUIKeybind = Enum.KeyCode.RightControl,
    Size = UDim2.fromOffset(700, 510),
    MinSize = Vector2.new(300, 260),
    KeepOnScreen = true,
    OpenButton = UserInputService.TouchEnabled and {Title = "MONO", Icon = "eye"} or false,
    Loading = false,
    ConfigurationSaving = {Enabled = false},
})

App.Window = Window

local Main = Window:CreateTab({Name = "Main", Icon = "key-round"})
local ESP = Window:CreateTab({Name = "ESP", Icon = "scan-eye"})
local Visuals = Window:CreateTab({Name = "Visuals", Icon = "sun"})
local Settings = Window:CreateTab({Name = "Settings", Icon = "settings"})
App.Tabs = {Main = Main, ESP = ESP, Visuals = Visuals, Settings = Settings}

function App:AddToggle(tab, key, name, default)
    self.Options[key] = false
    local control = tab:CreateToggle({
        Name = name,
        CurrentValue = false,
        Callback = function(value) self:SetOption(key, value) end,
    })
    self.Controls[key] = control
    for _, label in ipairs(control._frame:QueryDescendants("TextLabel")) do
        label.TextWrapped = true
        label.TextTruncate = Enum.TextTruncate.None
    end
    if default then self:SetOption(key, true) end
    return control
end

App.Reader = Main:CreateParagraph({Title = "Elevator Code", Content = "Waiting for the code note"})
for _, label in ipairs(App.Reader._frame:QueryDescendants("TextLabel")) do
    if label.Text ~= "Elevator Code" then label.TextSize = 26 label.TextColor3 = Airflow.Theme.Accent end
end
App.StatusCard = Main:CreateParagraph({Title = "Status", Content = "Ready"})
App:AddToggle(Main, "Reader", "Live Elevator Code Reader", true)
Main:CreateButton({Name = "Copy Elevator Code", Icon = "copy", Callback = function() App:Copy(App:ReadCode()) end})
App:AddToggle(Main, "AutoKeypad", "Auto Solve Keypad")
App:AddToggle(Main, "Instant", "Instant Proximity Prompts")
App:AddToggle(Main, "AutoDrawers", "Auto Open Drawers")
App:AddToggle(Main, "AutoPlanks", "Auto Pry Planks")

App:AddToggle(ESP, "Monster", "Monster ESP")
App:AddToggle(ESP, "Keys", "Escape Keys ESP")
App:AddToggle(ESP, "Note", "Code Note ESP")
App:AddToggle(ESP, "Closets", "Hiding Closets ESP")
App:AddToggle(ESP, "Drawers", "Unopened Drawers ESP")

App:AddToggle(Visuals, "Fullbright", "Fullbright")
App:AddToggle(Visuals, "CleanScreen", "Remove Screen Grain / VHS Effect")

Settings:CreateSection("Session")
Settings:CreateButton({Name = "Stop All", Icon = "square", Callback = function() App:StopAll() App:Notify("Stopped", "All features are off. Original visuals restored.") end})
App.Keybind = Settings:CreateKeybind({
    Name = "Menu Keybind",
    CurrentKeybind = Enum.KeyCode.RightControl,
    OnChanged = function(key) Window:SetKeybind(key) end,
})
Settings:CreateButton({Name = "Unload", Icon = "power", Callback = function() App:Unload() end})
Settings:CreateSection("Credits")
local credit
local creditStatus = "Loading..."
local creditButton = Settings:CreateButton({
    Name = "Credits - " .. creditStatus,
    Callback = function()
        if credit then
            App:Copy(credit)
        else
            App:Notify("Credits", creditStatus)
        end
    end,
})
Settings:CreateButton({Name = "UI Library - airflowlib.lol", Callback = function() App:Copy("https://airflowlib.lol") end})
task.spawn(function()
    local ok, text = pcall(function() return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram") end)
    if not App.Alive then return end
    if ok and type(text) == "string" then
        text = text:match("^%s*(.-)%s*$")
        if text ~= "" and #text < 250 and not text:find("<html") then
            credit = text
            creditButton:SetText("Credits - " .. credit)
            return
        end
    end
    creditStatus = "Unable to load credits"
    creditButton:SetText("Credits - Unavailable")
end)

local originalToggle = Window.Toggle
function Window:Toggle(open)
    if UserInputService:GetFocusedTextBox() then return end
    originalToggle(self, open)
end

local sidebar = Window.Body:FindFirstChild("Sidebar")
local header = sidebar:FindFirstChild("Header")
if header then
    for _, label in ipairs(header:QueryDescendants("TextLabel")) do
        if label.Text == "MONOCHROME" then
            label.TextSize = 13
            label.Position = UDim2.fromOffset(58, 25)
            label.Size = UDim2.new(1, -64, 0, 20)
        end
    end
end
local tabLayout = Window.TabList:FindFirstChildOfClass("UIListLayout")
local tabPadding = Window.TabList:FindFirstChildOfClass("UIPadding")
local originalProperties = {}
local function remember(object, properties)
    local values = {}
    for _, property in ipairs(properties) do values[property] = object[property] end
    originalProperties[object] = values
end
remember(sidebar, {"Size"})
remember(Window.Content, {"Position", "Size"})
remember(Window.TabList, {"Position", "Size", "AutomaticCanvasSize"})
remember(tabLayout, {"FillDirection"})
remember(tabPadding, {"PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom"})
for _, child in ipairs(sidebar:GetChildren()) do
    if child ~= Window.TabList and child ~= Window.Indicator and child:IsA("GuiObject") then remember(child, {"Visible"}) end
end
for _, child in ipairs(Window.Body:GetChildren()) do
    if child:IsA("Frame") and child.Size.X.Offset == 1 and child.Position.X.Offset == 170 then remember(child, {"Visible"}) end
end
for _, tab in ipairs(Window.Tabs) do
    remember(tab._button, {"Size"})
    remember(tab._label, {"Position", "Size", "TextXAlignment"})
    if tab._icon then remember(tab._icon, {"Visible"}) end
    local padding = tab.List:FindFirstChildOfClass("UIPadding")
    if padding then remember(padding, {"PaddingLeft", "PaddingRight"}) end
end
local originalIndicator = Window._placeIndicator
function Window:_placeIndicator(tab)
    if App.Compact then self.Indicator.Visible = false else originalIndicator(self, tab) end
end

function App:Layout(viewport)
    local size = viewport or Window.Gui.AbsoluteSize
    if size.X < 1 or size.Y < 1 then return end
    self.Compact = size.X < 620
    for object, properties in pairs(originalProperties) do
        for property, value in pairs(properties) do object[property] = value end
    end
    Window.Root.Size = UDim2.fromOffset(math.min(700, math.max(280, size.X - 24)), math.min(510, math.max(220, size.Y - 24)))
    Window.Root.Position = UDim2.fromScale(0.5, 0.5)
    if self.Compact then
        sidebar.Size = UDim2.new(1, 0, 0, 54)
        for object, properties in pairs(originalProperties) do
            if properties.Visible ~= nil and not object:IsDescendantOf(Window.TabList) then object.Visible = false end
        end
        Window.TabList.Position = UDim2.fromOffset(8, 4)
        Window.TabList.Size = UDim2.new(1, -16, 0, 46)
        Window.TabList.AutomaticCanvasSize = Enum.AutomaticSize.None
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabPadding.PaddingLeft = UDim.new(0, 0)
        tabPadding.PaddingRight = UDim.new(0, 0)
        tabPadding.PaddingTop = UDim.new(0, 0)
        tabPadding.PaddingBottom = UDim.new(0, 0)
        Window.Content.Position = UDim2.fromOffset(0, 54)
        Window.Content.Size = UDim2.new(1, 0, 1, -54)
        for _, tab in ipairs(Window.Tabs) do
            tab._button.Size = UDim2.new(0.25, -3, 0, 44)
            tab._label.Position = UDim2.new()
            tab._label.Size = UDim2.fromScale(1, 1)
            tab._label.TextXAlignment = Enum.TextXAlignment.Center
            if tab._icon then tab._icon.Visible = false end
            local padding = tab.List:FindFirstChildOfClass("UIPadding")
            if padding then
                padding.PaddingLeft = UDim.new(0, 12)
                padding.PaddingRight = UDim.new(0, 12)
            end
        end
    end
    Window:_fitToScreen(true)
    Window:_clampToScreen()
    if Window.CurrentTab then Window:_placeIndicator(Window.CurrentTab) end
end

App:Connect(Window.Gui:GetPropertyChangedSignal("AbsoluteSize"), function() App:Layout() end)
App:Connect(workspace.DescendantAdded, function(object)
    if object:IsA("ProximityPrompt") then
        App.Dirty = true
        if App.Options.Instant then App:Override("Instant", object, "HoldDuration", 0) end
    elseif object.Name == "CodeNote" or object.Name == "VER" or object:GetAttribute("KeyId") then
        App.Dirty = true
    end
end)
App:Connect(ProximityPromptService.PromptButtonHoldBegan, function(prompt)
    if App.Options.Instant and type(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, prompt, 0)
    end
end)
App:Connect(Player.CharacterAdded, function() App.Dirty = true App.PendingDigit = nil end)
App:Connect(Window.Gui.Destroying, function() App:Unload() end)
App.RenderBinding = "MonochromeAirflowESP_" .. tostring(Player.UserId)
RunService:BindToRenderStep(App.RenderBinding, Enum.RenderPriority.Last.Value, function()
    if App.Alive and next(App.Markers) then
        local ok, err = pcall(function() App:RenderESP() end)
        if not ok then
            App:ClearMarkers()
            for category in pairs(ESPColors) do App:SetOption(category, false) end
            App:Notify("Drawing ESP stopped", tostring(err):sub(1, 100))
        end
    end
end)

App:Scan()
App:UpdateReader()
task.defer(function() if App.Alive then App:Layout() end end)
task.spawn(function()
    local scanAt, visualAt, espAt, readerAt = 0, 0, 0, 0
    while App.Alive do
        local ok, err = pcall(function()
            local now = os.clock()
            local active = false
            for _, value in pairs(App.Options) do if value then active = true break end end
            if not active then return end
            if App.Dirty or now >= scanAt then App:Scan() scanAt = now + 2 end
            if now >= visualAt then App:ApplyVisuals() visualAt = now + 1 end
            if now >= espAt then App:UpdateESP() espAt = now + 0.3 end
            if App.Options.AutoDrawers or App.Options.AutoPlanks then App:AutomatePrompts() end
            App:SolveStep()
            if now >= readerAt then App:UpdateReader() readerAt = now + 0.3 end
        end)
        if not ok then
            App.Status = "Retrying: " .. tostring(err):sub(1, 100)
            warn("MONOCHROME: " .. tostring(err))
            task.wait(1)
        end
        task.wait(0.1)
    end
end)

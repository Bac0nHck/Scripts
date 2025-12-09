-- https://roscripter.com/scripts/src-leak-word-helper

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- Configuration
local TOGGLE_KEY = Enum.KeyCode.RightControl
local MIN_WPM = 10
local MAX_WPM = 300

-- Seed the random number generator
math.randomseed(os.time())

local THEME = {
    Background = Color3.fromRGB(20, 20, 24),
    ItemBG = Color3.fromRGB(32, 32, 38),
    Accent = Color3.fromRGB(114, 100, 255), -- Purple-ish
    Text = Color3.fromRGB(240, 240, 240),
    SubText = Color3.fromRGB(150, 150, 160),
    Success = Color3.fromRGB(100, 255, 140),
    Warning = Color3.fromRGB(255, 200, 80),
    Slider = Color3.fromRGB(60, 60, 70)
}

local function ColorToRGB(c)
    return string.format("%d,%d,%d", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

-- State
local currentWPM = 110
local useHumanization = true
local useRandomSort = true -- Default to Random
local useFingerModel = true -- 10-finger keyboard movement model
local isTyping = false
local runConn = nil
local inputConn = nil
local unloaded = false
local Blacklist = {}
local RandomOrderCache = {}
local RandomPriority = {}
local ShuffledBuckets = {}
local lastDetected = "---"
local UpdateList -- Forward declaration
-- Error/correction settings
local errorRate = 5 -- percent chance to mistype (per-letter, 0-30)
local thinkDelayMin = 0.4
local thinkDelayMax = 1.2
local thinkDelayCurrent = (thinkDelayMin + thinkDelayMax) / 2

-- Data loading
local url = "https://raw.githubusercontent.com/skrylor/english-words/refs/heads/main/merged_english.txt"
local fileName = "ultimate_words_v4.txt" -- Changed name to force update

if not isfile(fileName) then
    local res = request({Url = url, Method = "GET"})
    if res and res.Body then writefile(fileName, res.Body) end
end

local Words = {}
if isfile(fileName) then
    local content = readfile(fileName)
    for w in content:gmatch("[^\r\n]+") do
        local clean = w:gsub("[%s%c]+", ""):lower()
        if #clean > 0 then table.insert(Words, clean) end
    end
    -- We keep the base list sorted, but we will shuffle results dynamically
    table.sort(Words)
    -- Build buckets by first letter to speed up prefix and fuzzy searches
    Buckets = {}
    for _, w in ipairs(Words) do
        local c = w:sub(1,1) or ""
        if c == "" then c = "#" end
        Buckets[c] = Buckets[c] or {}
        table.insert(Buckets[c], w)
    end
end

-- Utility: Fisher-Yates Shuffle
local function shuffleTable(t)
    local n = #t
    for i = n, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- Utility: Levenshtein Distance
local function getDistance(s1, s2)
    if #s1 == 0 then
        return #s2
    end
    if #s2 == 0 then
        return #s1
    end
    if s1 == s2 then
        return 0
    end
    local matrix = {}
    for i = 0, #s1 do matrix[i] = {[0] = i} end
    for j = 0, #s2 do matrix[0][j] = j end
    for i = 1, #s1 do
        for j = 1, #s2 do
            local cost = (s1:sub(i,i) == s2:sub(j,j)) and 0 or 1
            matrix[i][j] = math.min(matrix[i-1][j]+1, matrix[i][j-1]+1, matrix[i-1][j-1]+cost)
        end
    end
    return matrix[#s1][#s2]
end

local function GetCurrentGameWord()
    local player = Players.LocalPlayer
    local gui = player and player:FindFirstChild("PlayerGui")
    local frame = gui and gui:FindFirstChild("InGame") and gui.InGame:FindFirstChild("Frame")
    local container = frame and frame:FindFirstChild("CurrentWord")
    if not container then return "" end
    local detected = ""
    local i = 1
    while true do
        local letterFrame = container:FindFirstChild(tostring(i))
        if not letterFrame then break end
        local txt = letterFrame:FindFirstChild("Letter")
        if txt and txt:IsA("TextLabel") then detected = detected .. txt.Text end
        i = i + 1
    end
    return detected:lower():gsub(" ", "")
end

-- UI construction
local function GetSecureParent()
    local success, result = pcall(function()
        return gethui()
    end)
    if success and result then return result end
    
    success, result = pcall(function()
        return game:GetService("CoreGui")
    end)
    if success and result then return result end
    
    return game:GetService("Players").LocalPlayer.PlayerGui
end

local ParentTarget = GetSecureParent()
local GuiName = tostring(math.random(1000000, 9999999))

-- Cleanup old if possible
for _, child in ipairs(ParentTarget:GetChildren()) do
    if child:GetAttribute("IsWordHelper") then
        child:Destroy()
    end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GuiName
ScreenGui.Parent = ParentTarget
ScreenGui:SetAttribute("IsWordHelper", true)
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 300, 0, 450) -- Slightly wider/taller
MainFrame.Position = UDim2.new(0.8, -50, 0.4, 0)
MainFrame.BackgroundColor3 = THEME.Background
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
Instance.new("UIDragDetector", MainFrame)
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local Stroke = Instance.new("UIStroke", MainFrame)
Stroke.Color = THEME.Accent
Stroke.Transparency = 0.5
Stroke.Thickness = 2

-- Header
local Header = Instance.new("Frame", MainFrame)
Header.Size = UDim2.new(1, 0, 0, 45)
Header.BackgroundColor3 = THEME.ItemBG
Header.BorderSizePixel = 0

local Title = Instance.new("TextLabel", Header)
Title.Text = "Word<font color=\"rgb(114,100,255)\">Helper</font> V3"
Title.RichText = true
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextColor3 = THEME.Text
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize
local MinBtn = Instance.new("TextButton", Header)
MinBtn.Text = "-"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 24
MinBtn.TextColor3 = THEME.SubText
MinBtn.Size = UDim2.new(0, 45, 1, 0)
MinBtn.Position = UDim2.new(1, -45, 0, 0)
MinBtn.BackgroundTransparency = 1

-- Status
local StatusFrame = Instance.new("Frame", MainFrame)
StatusFrame.Size = UDim2.new(1, -30, 0, 24)
StatusFrame.Position = UDim2.new(0, 15, 0, 55)
StatusFrame.BackgroundTransparency = 1

local StatusDot = Instance.new("Frame", StatusFrame)
StatusDot.Size = UDim2.new(0, 8, 0, 8)
StatusDot.Position = UDim2.new(0, 0, 0.5, -4)
StatusDot.BackgroundColor3 = THEME.SubText
Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

local StatusText = Instance.new("TextLabel", StatusFrame)
StatusText.Text = "Idle..."
StatusText.RichText = true
StatusText.Font = Enum.Font.Gotham
StatusText.TextSize = 12
StatusText.TextColor3 = THEME.SubText
StatusText.Size = UDim2.new(1, -15, 1, 0)
StatusText.Position = UDim2.new(0, 15, 0, 0)
StatusText.BackgroundTransparency = 1
StatusText.TextXAlignment = Enum.TextXAlignment.Left

-- List
local ScrollList = Instance.new("ScrollingFrame", MainFrame)
ScrollList.Size = UDim2.new(1, -10, 1, -190) -- Adjust for bottom panel
ScrollList.Position = UDim2.new(0, 5, 0, 85)
ScrollList.BackgroundTransparency = 1
ScrollList.ScrollBarThickness = 3
ScrollList.ScrollBarImageColor3 = THEME.Accent
ScrollList.CanvasSize = UDim2.new(0,0,0,0)

local UIListLayout = Instance.new("UIListLayout", ScrollList)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 4)

-- Settings Container
local SettingsFrame = Instance.new("Frame", MainFrame)
SettingsFrame.Size = UDim2.new(1, 0, 0, 200)
SettingsFrame.Position = UDim2.new(0, 0, 1, -200)
SettingsFrame.BackgroundColor3 = THEME.ItemBG
SettingsFrame.BorderSizePixel = 0
local sep = Instance.new("Frame", SettingsFrame)
sep.Size = UDim2.new(1, 0, 0, 1)
sep.BackgroundColor3 = Color3.fromRGB(45, 45, 50)

-- WPM Slider
local SliderLabel = Instance.new("TextLabel", SettingsFrame)
SliderLabel.Text = "Speed: " .. currentWPM .. " WPM"
SliderLabel.Font = Enum.Font.GothamMedium
SliderLabel.TextSize = 12
SliderLabel.TextColor3 = THEME.SubText
SliderLabel.Size = UDim2.new(1, -30, 0, 20)
SliderLabel.Position = UDim2.new(0, 15, 0, 8)
SliderLabel.BackgroundTransparency = 1
SliderLabel.TextXAlignment = Enum.TextXAlignment.Left

local SliderBg = Instance.new("Frame", SettingsFrame)
SliderBg.Size = UDim2.new(1, -30, 0, 6)
SliderBg.Position = UDim2.new(0, 15, 0, 30)
SliderBg.BackgroundColor3 = THEME.Slider
Instance.new("UICorner", SliderBg).CornerRadius = UDim.new(1, 0)

local SliderFill = Instance.new("Frame", SliderBg)
SliderFill.Size = UDim2.new(0.5, 0, 1, 0)
SliderFill.BackgroundColor3 = THEME.Accent
Instance.new("UICorner", SliderFill).CornerRadius = UDim.new(1, 0)

local SliderBtn = Instance.new("TextButton", SliderBg)
SliderBtn.Size = UDim2.new(1,0,1,0)
SliderBtn.BackgroundTransparency = 1
SliderBtn.Text = ""

-- Humanize Button
local HumanizeBtn = Instance.new("TextButton", SettingsFrame)
HumanizeBtn.Text = "Humanize: ON"
HumanizeBtn.Font = Enum.Font.GothamMedium
HumanizeBtn.TextSize = 11
HumanizeBtn.TextColor3 = THEME.Success
HumanizeBtn.BackgroundColor3 = THEME.Background
HumanizeBtn.Size = UDim2.new(0, 120, 0, 24)
HumanizeBtn.Position = UDim2.new(0, 15, 0, 50)
Instance.new("UICorner", HumanizeBtn).CornerRadius = UDim.new(0, 4)

-- 10-Finger typing model toggle
local FingerBtn = Instance.new("TextButton", SettingsFrame)
FingerBtn.Text = "10-Finger: ON"
FingerBtn.Font = Enum.Font.GothamMedium
FingerBtn.TextSize = 11
FingerBtn.TextColor3 = THEME.Success
FingerBtn.BackgroundColor3 = THEME.Background
FingerBtn.Size = UDim2.new(0, 120, 0, 24)
FingerBtn.Position = UDim2.new(0, 145, 0, 50)
Instance.new("UICorner", FingerBtn).CornerRadius = UDim.new(0, 4)

FingerBtn.MouseButton1Click:Connect(function()
    useFingerModel = not useFingerModel
    if useFingerModel then
        FingerBtn.Text = "10-Finger: ON"
        FingerBtn.TextColor3 = THEME.Success
    else
        FingerBtn.Text = "10-Finger: OFF"
        FingerBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
    end
end)

-- Randomize Button
local RandomBtn = Instance.new("TextButton", SettingsFrame)
RandomBtn.Text = "Random: ON"
RandomBtn.Font = Enum.Font.GothamMedium
RandomBtn.TextSize = 11
RandomBtn.TextColor3 = THEME.Success
RandomBtn.BackgroundColor3 = THEME.Background
RandomBtn.Size = UDim2.new(0, 120, 0, 24)
RandomBtn.Position = UDim2.new(1, -135, 0, 50)
Instance.new("UICorner", RandomBtn).CornerRadius = UDim.new(0, 4)

-- Error rate slider
local ErrorLabel = Instance.new("TextLabel", SettingsFrame)
ErrorLabel.Text = "Error Rate: " .. errorRate .. "%"
ErrorLabel.Font = Enum.Font.GothamMedium
ErrorLabel.TextSize = 11
ErrorLabel.TextColor3 = THEME.SubText
ErrorLabel.Size = UDim2.new(1, -30, 0, 18)
ErrorLabel.Position = UDim2.new(0, 15, 0, 82)
ErrorLabel.BackgroundTransparency = 1
ErrorLabel.TextXAlignment = Enum.TextXAlignment.Left

local ErrorBg = Instance.new("Frame", SettingsFrame)
ErrorBg.Size = UDim2.new(1, -30, 0, 6)
ErrorBg.Position = UDim2.new(0, 15, 0, 102)
ErrorBg.BackgroundColor3 = THEME.Slider
Instance.new("UICorner", ErrorBg).CornerRadius = UDim.new(1, 0)

local ErrorFill = Instance.new("Frame", ErrorBg)
ErrorFill.Size = UDim2.new(errorRate/30, 0, 1, 0)
ErrorFill.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
Instance.new("UICorner", ErrorFill).CornerRadius = UDim.new(1, 0)

local ErrorBtn = Instance.new("TextButton", ErrorBg)
ErrorBtn.Size = UDim2.new(1,0,1,0)
ErrorBtn.BackgroundTransparency = 1
ErrorBtn.Text = ""

ErrorBtn.MouseButton1Down:Connect(function()
    local mouse = Players.LocalPlayer:GetMouse()
    local move, rel
    local function Update()
        local relX = math.clamp(mouse.X - ErrorBg.AbsolutePosition.X, 0, ErrorBg.AbsoluteSize.X)
        local pct = relX / ErrorBg.AbsoluteSize.X
        errorRate = math.floor(pct * 30) -- slider spans 0..30 percent per-letter
        ErrorFill.Size = UDim2.new(pct, 0, 1, 0)
        ErrorLabel.Text = "Error Rate: " .. errorRate .. "% (per-letter)"
    end
    Update()
    move = mouse.Move:Connect(Update)
    rel = UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            move:Disconnect() rel:Disconnect()
        end
    end)
end)

-- Think delay slider
local ThinkLabel = Instance.new("TextLabel", SettingsFrame)
ThinkLabel.Text = string.format("Think: %.2fs", thinkDelayCurrent)
ThinkLabel.Font = Enum.Font.GothamMedium
ThinkLabel.TextSize = 11
ThinkLabel.TextColor3 = THEME.SubText
ThinkLabel.Size = UDim2.new(1, -30, 0, 18)
ThinkLabel.Position = UDim2.new(0, 15, 0, 122)
ThinkLabel.BackgroundTransparency = 1
ThinkLabel.TextXAlignment = Enum.TextXAlignment.Left

local ThinkBg = Instance.new("Frame", SettingsFrame)
ThinkBg.Size = UDim2.new(1, -30, 0, 6)
ThinkBg.Position = UDim2.new(0, 15, 0, 142)
ThinkBg.BackgroundColor3 = THEME.Slider
Instance.new("UICorner", ThinkBg).CornerRadius = UDim.new(1, 0)

local ThinkFill = Instance.new("Frame", ThinkBg)
local thinkPct = (thinkDelayCurrent - thinkDelayMin) / (thinkDelayMax - thinkDelayMin)
ThinkFill.Size = UDim2.new(thinkPct, 0, 1, 0)
ThinkFill.BackgroundColor3 = THEME.Accent
Instance.new("UICorner", ThinkFill).CornerRadius = UDim.new(1, 0)

local ThinkBtn = Instance.new("TextButton", ThinkBg)
ThinkBtn.Size = UDim2.new(1,0,1,0)
ThinkBtn.BackgroundTransparency = 1
ThinkBtn.Text = ""

ThinkBtn.MouseButton1Down:Connect(function()
    local mouse = Players.LocalPlayer:GetMouse()
    local move, rel
    local function Update()
        local relX = math.clamp(mouse.X - ThinkBg.AbsolutePosition.X, 0, ThinkBg.AbsoluteSize.X)
        local pct = relX / ThinkBg.AbsoluteSize.X
        thinkDelayCurrent = thinkDelayMin + pct * (thinkDelayMax - thinkDelayMin)
        ThinkFill.Size = UDim2.new(pct, 0, 1, 0)
        ThinkLabel.Text = string.format("Think: %.2fs", thinkDelayCurrent)
    end
    Update()
    move = mouse.Move:Connect(Update)
    rel = UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            move:Disconnect() rel:Disconnect()
        end
    end)
end)

-- // 3. TYPING LOGIC //
-- Unload Button (destroys GUI and disconnects main connections)
local UnloadBtn = Instance.new("TextButton", SettingsFrame)
UnloadBtn.Text = "Unload"
UnloadBtn.Font = Enum.Font.GothamMedium
UnloadBtn.TextSize = 11
UnloadBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
UnloadBtn.BackgroundColor3 = THEME.Background
UnloadBtn.Size = UDim2.new(0, 80, 0, 24)
UnloadBtn.Position = UDim2.new(0, 15, 0, 150)
Instance.new("UICorner", UnloadBtn).CornerRadius = UDim.new(0, 4)
UnloadBtn.MouseButton1Click:Connect(function()
    unloaded = true
    if runConn then runConn:Disconnect() runConn = nil end
    if inputConn then inputConn:Disconnect() inputConn = nil end
    if ScreenGui and ScreenGui.Parent then ScreenGui:Destroy() end
end)
local function Tween(obj, props, time)
    TweenService:Create(obj, TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function CalculateDelay()
    local charsPerMin = currentWPM * 5
    local baseDelay = 60 / charsPerMin
    local variance = baseDelay * 0.4 -- More variance for human look
    return useHumanization and (baseDelay + math.random()*variance - (variance/2)) or baseDelay
end

-- Keyboard layout positions (approximate QWERTY coordinates)
local KEY_POS = {}
do
    local row1 = "qwertyuiop"
    local row2 = "asdfghjkl"
    local row3 = "zxcvbnm"
    for i = 1, #row1 do
        KEY_POS[row1:sub(i,i)] = {x = i, y = 1}
    end
    for i = 1, #row2 do
        KEY_POS[row2:sub(i,i)] = {x = i + 0.5, y = 2}
    end
    for i = 1, #row3 do
        KEY_POS[row3:sub(i,i)] = {x = i + 1, y = 3}
    end
end

local function KeyDistance(a, b)
    if not a or not b then return 1 end
    a = a:lower()
    b = b:lower()
    local pa = KEY_POS[a]
    local pb = KEY_POS[b]
    if not pa or not pb then return 1 end
    local dx = pa.x - pb.x
    local dy = pa.y - pb.y
    return math.sqrt(dx*dx + dy*dy)
end

-- Enhanced CalculateDelay using key distance when model enabled
local lastKey = nil
local function CalculateDelayForKeys(prevChar, nextChar)
    local charsPerMin = currentWPM * 5
    local baseDelay = 60 / charsPerMin
    local variance = baseDelay * 0.35
    local extra = 0
    if useHumanization and useFingerModel and prevChar and nextChar and prevChar ~= "" then
        local dist = KeyDistance(prevChar, nextChar)
        -- scale extra delay by distance and normalize by typing speed
        extra = dist * 0.018 * (110 / math.max(30, currentWPM))
        -- small bonus when same hand (faster) - approximate by x coordinate parity
        local pa = KEY_POS[prevChar:lower()]
        local pb = KEY_POS[nextChar:lower()]
        if pa and pb then
            if (pa.x <= 5 and pb.x <= 5) or (pa.x > 5 and pb.x > 5) then
                extra = extra * 0.8
            end
        end
    end
    if useHumanization then
        return baseDelay + extra + (math.random()*variance - variance/2)
    else
        return baseDelay
    end
end

local function SimulateKey(char)
    local key = Enum.KeyCode[char:upper()]
    if key then
        VirtualInputManager:SendKeyEvent(true, key, false, game)
        local hold = 0.005 + math.random() * 0.02
        task.wait(hold)
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    end
end

local function Backspace(count)
    for i = 1, count do
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
        task.wait(0.02 + math.random() * 0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
        task.wait(0.02 + math.random() * 0.05)
    end
    -- After backspacing, we don't have a recent key context
    lastKey = nil
end

local function PressEnter()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
    task.wait(0.02)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    lastKey = nil
end

local function SmartType(targetWord, currentDetected, isCorrection)
    if isTyping or unloaded then return end
    isTyping = true
    
    if isCorrection then
        -- Calculate common prefix to avoid unnecessary backspacing (preserves locked starting letters)
        local commonLen = 0
        local minLen = math.min(#targetWord, #currentDetected)
        for i = 1, minLen do
            if targetWord:sub(i,i) == currentDetected:sub(i,i) then
                commonLen = i
            else
                break
            end
        end

        -- Delete only the mismatching suffix
        local backspaceCount = #currentDetected - commonLen
        if backspaceCount > 0 then
            Backspace(backspaceCount)
            task.wait(0.15)
        end
        
        -- Type the rest of the word
        local toType = targetWord:sub(commonLen + 1)
        for i = 1, #toType do
            local ch = toType:sub(i, i)
            SimulateKey(ch)
            task.wait(CalculateDelayForKeys(lastKey, ch))
            lastKey = ch
            if useHumanization and math.random() < 0.03 then
                task.wait(0.15 + math.random() * 0.45)
            end
        end
        PressEnter()
        
        -- check if the game rejected the submission; if so, revert typed chars and blacklist
        task.wait(0.6)
        if GetCurrentGameWord() == targetWord then
            local typedCount = math.max(0, #targetWord - #currentDetected)
            if typedCount > 0 then
                Backspace(typedCount)
            end
            Blacklist[targetWord] = true
            -- remove random priority so it won't be shown again
            RandomPriority[targetWord] = nil
            StatusText.Text = "Rejected: removed '" .. targetWord .. "'"
            StatusText.TextColor3 = THEME.Warning
            UpdateList(currentDetected)
            isTyping = false
            return
        end
    else
        -- Just append the rest, with optional simulated typo
        local missingPart = ""
        if targetWord:sub(1, #currentDetected) == currentDetected then
            missingPart = targetWord:sub(#currentDetected + 1)
        else
            missingPart = targetWord
        end

        local letters = "abcdefghijklmnopqrstuvwxyz"
        for i = 1, #missingPart do
            local ch = missingPart:sub(i, i)
            if errorRate > 0 and (math.random() < (errorRate / 100)) then
                local typoChar
                repeat
                    local idx = math.random(1, #letters)
                    typoChar = letters:sub(idx, idx)
                until typoChar ~= ch
                SimulateKey(typoChar)
                task.wait(CalculateDelayForKeys(lastKey, typoChar))
                lastKey = typoChar
                local realize = thinkDelayCurrent * (0.6 + math.random() * 0.8)
                task.wait(realize)
                Backspace(1)
                -- after removing the typo, we lose the recent key context
                lastKey = nil
                task.wait(0.04 + math.random() * 0.06)
                SimulateKey(ch)
                task.wait(CalculateDelayForKeys(lastKey, ch))
                lastKey = ch
            else
                SimulateKey(ch)
                task.wait(CalculateDelayForKeys(lastKey, ch))
                lastKey = ch
            end
            if useHumanization and math.random() < 0.03 then
                task.wait(0.12 + math.random() * 0.5)
            end
        end
        PressEnter()
        -- after submit, if rejected, revert typed chars and blacklist the word
        task.wait(0.6)
        if GetCurrentGameWord() == targetWord then
            local typedCount = math.max(0, #targetWord - #currentDetected)
            if typedCount > 0 then
                Backspace(typedCount)
            end
            Blacklist[targetWord] = true
            -- remove from cached random orders so it won't reappear
            for k, list in pairs(RandomOrderCache) do
                for i = #list, 1, -1 do
                    if list[i] == targetWord then table.remove(list, i) end
                end
            end
            StatusText.Text = "Rejected: removed '" .. targetWord .. "'"
            StatusText.TextColor3 = THEME.Warning
            UpdateList(currentDetected)
            isTyping = false
            return
        end
    end
    isTyping = false
end

-- // 4. SEARCH ALGORITHM (UPDATED) //

UpdateList = function(detectedText)
    -- Clean Old UI
    for _, v in ipairs(ScrollList:GetChildren()) do
        if v:IsA("TextButton") then v:Destroy() end
    end
    
    if detectedText == "" then return end

    -- COLLECTION PHASE (Backtracking Support)
    local matches = {}
    local searchPrefix = detectedText
    local isBacktracked = false
    
    -- Try exact match first
    local firstChar = searchPrefix:sub(1,1) or ""
    local bucket = (Buckets and Buckets[firstChar]) or Words
    
    local function CollectMatches(prefix)
        local found = {}
        if bucket then
            for _, w in ipairs(bucket) do
                if not Blacklist[w] and w:sub(1, #prefix) == prefix then
                    table.insert(found, w)
                    -- Performance cap during collection
                    if #found >= 100 then break end
                end
            end
        end
        return found
    end

    matches = CollectMatches(searchPrefix)

    -- Backtracking Logic: If no matches, try removing chars from end
    if #matches == 0 and #searchPrefix > 1 then
        for i = 1, 3 do -- Backtrack up to 3 chars
            local tryPrefix = searchPrefix:sub(1, -(i + 1))
            if #tryPrefix == 0 then break end
            
            local tryMatches = CollectMatches(tryPrefix)
            if #tryMatches > 0 then
                matches = tryMatches
                searchPrefix = tryPrefix
                isBacktracked = true
                break
            end
        end
    end
    
    -- PROCESSING PHASE
    local displayList = {}

    if #matches > 0 then
        -- If useRandomSort is true, the source bucket is already shuffled by the main loop
        -- If useRandomSort is false, the source bucket is sorted
        for i = 1, math.min(40, #matches) do table.insert(displayList, matches[i]) end
    else
        displayList = {}
    end
    
    -- DISPLAY MATCHES
    if isBacktracked then
        local validPart = searchPrefix
        local invalidPart = detectedText:sub(#searchPrefix + 1)
        local accentRGB = ColorToRGB(THEME.Accent)
        StatusText.Text = "No match: <font color=\"rgb(" .. accentRGB .. ")\">" .. validPart .. "</font><font color=\"rgb(255,80,80)\">" .. invalidPart .. "</font>"
        StatusText.TextColor3 = THEME.SubText -- Base color, overridden by RichText
    end

    for i = 1, math.min(40, #displayList) do
        local w = displayList[i]
        local btn = Instance.new("TextButton", ScrollList)
        btn.Size = UDim2.new(1, -6, 0, 30)
        btn.BackgroundColor3 = THEME.ItemBG
        btn.Text = ""
        btn.AutoButtonColor = false
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        
        local lbl = Instance.new("TextLabel", btn)
        lbl.Size = UDim2.new(1, -20, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 14
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.RichText = true
        
        -- Highlight logic
        local accentRGB = ColorToRGB(THEME.Accent)
        local textRGB = ColorToRGB(THEME.Text)
        local warnRGB = ColorToRGB(THEME.Warning)
        
        local displayText = ""
        if isBacktracked then
            -- Highlight the valid part in Accent, the rest in Text
            local prefix = w:sub(1, #searchPrefix)
            local suffix = w:sub(#searchPrefix + 1)
            displayText = "<font color=\"rgb(" .. accentRGB .. ")\">" .. prefix .. "</font>"
                .. "<font color=\"rgb(" .. textRGB .. ")\">" .. suffix .. "</font>"
        else
            -- Normal highlighting
            local prefix = w:sub(1, #detectedText)
            local suffix = w:sub(#detectedText + 1)
            displayText = "<font color=\"rgb(" .. accentRGB .. ")\">" .. prefix .. "</font>"
                .. "<font color=\"rgb(" .. textRGB .. ")\">" .. suffix .. "</font>"
        end
        
        lbl.Text = displayText

        btn.MouseButton1Click:Connect(function()
            -- If backtracked, we need to fix the input first? 
            -- SmartType handles typing the target word. 
            -- If we are correcting, SmartType will backspace the whole detected input and type the word.
            SmartType(w, detectedText, true) -- Force correction mode if clicked
            lbl.TextColor3 = THEME.Success
            Tween(btn, {BackgroundColor3 = Color3.fromRGB(30,60,40)})
        end)
        
        btn.MouseEnter:Connect(function() Tween(btn, {BackgroundColor3 = Color3.fromRGB(45,45,55)}) end)
        btn.MouseLeave:Connect(function() Tween(btn, {BackgroundColor3 = THEME.ItemBG}) end)
    end
    
    ScrollList.CanvasSize = UDim2.new(0,0,0, UIListLayout.AbsoluteContentSize.Y)
end

-- // 5. UI CONTROLS //

-- Random Toggle
RandomBtn.MouseButton1Click:Connect(function()
    useRandomSort = not useRandomSort
    if useRandomSort then
        RandomBtn.Text = "Random: ON"
        RandomBtn.TextColor3 = THEME.Success
    else
        RandomBtn.Text = "Random: OFF"
        RandomBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
    end
    -- Force re-evaluation in the loop to trigger sort/shuffle logic
    lastDetected = "---"
end)

-- Humanize Toggle
HumanizeBtn.MouseButton1Click:Connect(function()
    useHumanization = not useHumanization
    if useHumanization then
        HumanizeBtn.Text = "Humanize: ON"
        HumanizeBtn.TextColor3 = THEME.Success
    else
        HumanizeBtn.Text = "Humanize: OFF"
        HumanizeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
    end
end)

-- WPM Slider
SliderBtn.MouseButton1Down:Connect(function()
    local mouse = Players.LocalPlayer:GetMouse()
    local move, rel
    local function Update()
        local relX = math.clamp(mouse.X - SliderBg.AbsolutePosition.X, 0, SliderBg.AbsoluteSize.X)
        local pct = relX / SliderBg.AbsoluteSize.X
        currentWPM = math.floor(MIN_WPM + (pct * (MAX_WPM - MIN_WPM)))
        SliderFill.Size = UDim2.new(pct, 0, 1, 0)
        SliderLabel.Text = "Speed: " .. currentWPM .. " WPM"
        if currentWPM > 180 then Tween(SliderFill, {BackgroundColor3 = Color3.fromRGB(255,80,80)}) 
        else Tween(SliderFill, {BackgroundColor3 = THEME.Accent}) end
    end
    Update()
    move = mouse.Move:Connect(Update)
    rel = UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            move:Disconnect() rel:Disconnect()
        end
    end)
end)

-- Minimize
MinBtn.MouseButton1Click:Connect(function()
    local isMin = MainFrame.Size.Y.Offset < 100
    if not isMin then
        Tween(MainFrame, {Size = UDim2.new(0, 300, 0, 45)})
        ScrollList.Visible = false
        SettingsFrame.Visible = false
        StatusFrame.Visible = false
        MinBtn.Text = "+"
    else
        Tween(MainFrame, {Size = UDim2.new(0, 300, 0, 450)})
        task.wait(0.2)
        ScrollList.Visible = true
        SettingsFrame.Visible = true
        StatusFrame.Visible = true
        MinBtn.Text = "-"
    end
end)

-- // 6. AUTO DETECT LOOP //

runConn = RunService.RenderStepped:Connect(function()
    -- Safe Pcall to prevent script crashing from game errors
    local success, err = pcall(function()
        local player = Players.LocalPlayer
        local gui = player and player:FindFirstChild("PlayerGui")
        local frame = gui and gui:FindFirstChild("InGame") and gui.InGame:FindFirstChild("Frame")
        
        -- Safe check: does container exist?
        local container = frame and frame:FindFirstChild("CurrentWord")
        if not container then return end

        local detected = ""
        local i = 1
        
        -- Reads child "1", "2", "3" safely and detect censorship (# or *)
        local censored = false
        while true do
            local letterFrame = container:FindFirstChild(tostring(i))
            if not letterFrame then break end

            local txt = letterFrame:FindFirstChild("Letter")
            if txt and txt:IsA("TextLabel") then
                local t = tostring(txt.Text)
                if t:find("#") or t:find("%*") then censored = true end
                detected = detected .. t
            end
            i = i + 1
        end

        detected = detected:lower():gsub(" ", "")
        if censored then
            StatusText.Text = "Censored вЂ” suggestions disabled"
            StatusText.TextColor3 = THEME.Warning
            Tween(StatusDot, {BackgroundColor3 = THEME.Warning})
            UpdateList("")
            return
        end
        
        if detected ~= lastDetected then
            -- Randomization Logic:
            if detected ~= "" then
                local c = detected:sub(1,1)
                if Buckets and Buckets[c] then
                    if useRandomSort then
                        local needsShuffle = false
                        if lastDetected == "" or lastDetected == "---" then
                            needsShuffle = true
                        else
                            -- Check if detected is a continuation of lastDetected (typing)
                            -- or lastDetected is a continuation of detected (backspacing)
                            local isType = (detected:sub(1, #lastDetected) == lastDetected)
                            local isBackspace = (lastDetected:sub(1, #detected) == detected)
                            
                            if not isType and not isBackspace then
                                needsShuffle = true
                            end
                        end
                        
                        if needsShuffle or not ShuffledBuckets[c] then
                            shuffleTable(Buckets[c])
                            ShuffledBuckets[c] = true
                        end
                    else
                        -- If not using random sort, ensure bucket is sorted if it was previously shuffled
                        if ShuffledBuckets[c] then
                            table.sort(Buckets[c])
                            ShuffledBuckets[c] = nil
                        end
                    end
                end
            end

            lastDetected = detected
            if detected == "" then
                StatusText.Text = "Waiting..."
                StatusText.TextColor3 = THEME.SubText
                Tween(StatusDot, {BackgroundColor3 = THEME.SubText})
                UpdateList("")
            else
                StatusText.Text = "Input: " .. detected
                StatusText.TextColor3 = THEME.Accent
                Tween(StatusDot, {BackgroundColor3 = THEME.Success})
                UpdateList(detected)
            end
        end
    end)
end)

-- Global Toggle
inputConn = UserInputService.InputBegan:Connect(function(input)
    if unloaded then return end
    if input.KeyCode == TOGGLE_KEY then ScreenGui.Enabled = not ScreenGui.Enabled end
end)

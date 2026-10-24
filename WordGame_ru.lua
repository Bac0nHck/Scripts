local Environment = getgenv and getgenv() or _G
local Previous = Environment.WordAutoType
if type(Previous) == "table" and type(Previous.Unload) == "function" then
    Previous.Unload()
    task.wait(0.6)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Player = Players.LocalPlayer
if game.PlaceId ~= 71106427459865 then
    warn("Word Auto Type: this game is not supported.")
    return
end

local Network = ReplicatedStorage:WaitForChild("WordGame", 15)
local Action = Network and Network:WaitForChild("Action", 10)
local StateEvent = Network and Network:WaitForChild("State", 10)
if not Action or not StateEvent then
    warn("Word Auto Type: the game connection is unavailable.")
    return
end

local LibraryUrl = "https://github.com/Footagesus/WindUI"
local DictionaryUrl = "https://raw.githubusercontent.com/Harrix/Russian-Nouns/main/dist/russian_nouns.txt"
local CreditsUrl = "https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram"
local CachePath = "WordAutoType_dictionary_v1.txt"
local Randomizer = Random.new()
local Connections = {}
local Threads = {}
local Alive = true
local Window
local WindUI
local Controls = {}
local CurrentState
local CurrentTurn
local CurrentMatch
local CurrentRound
local RoundWords = {}
local Used = {}
local Rejected = {}
local Tried = {}
local Completed = {}
local Attempts = 0
local Pending
local Job
local TypingBox
local TextConnection
local ManualTurn
local SuppressedTurn
local ChoiceSent
local ExpectedText
local AutoEnabled = false
local SmartEnabled = false
local AntiAfkEnabled = true
local Speed = 8
local Mode = "Common"
local Dictionary = {}
local WordCount = 0
local DictionaryStatus = "Loading dictionary..."
local Status = "Waiting for game state"
local SelectedWord = "None"
local StatusPanel
local CreditsAddress = "t.me/arceusxcommunity"
local CopyField
local NextAttemptAt = 0
local LastPanelText
local LastManualInput = -math.huge
local MobileKeyboard
local EngineAvailable = type(firesignal) == "function" or type(getconnections) == "function"

local CommonText = [[
абрикос автобус автомобиль адрес азбука акула алмаз альбом ананас апельсин аптека арбуз артист астронавт
бабочка багаж банан банка барабан бассейн башня белка берег берёза билет библиотека бинт блин болото ботинок брат бревно бумага букет булка бутылка
вагон ваза валенок ванна варенье ведро велосипед веник верблюд верёвка ветер ветка вечер вилка виноград вишня вода водопад воздух вокзал волк волна воробей ворона врач время
газета гараж гвоздь герой гитара глаз глина гриб гроза гром груша город гора горох гость голубь гнездо
дверь девочка дедушка дерево деревня диван дождь дом дорога доска друг дупло дым дыня дятел
еда ёж ёлка ель енот ёрш железо жемчуг жираф живот жук журнал
забор завод заяц звезда звонок зверь зебра зеркало зерно зима змея знак золото зонт зуб
игла игрушка игра изюм индюк иней искра история йог йога йод
кабан кабачок камень капуста карандаш карман картофель карта картина касса качели каша кефир кисть кит клетка ключ книга кнопка ковёр коза колесо колокол комната компас конфета конь корабль корень коридор корова корзина костёр кошка край краска кресло кролик крыша кружка крыло кубик кузнечик курица куст кухня
лампа ласточка лебедь лев лёд лента лес лестница лето лиса лист лимон лодка ложка лошадь лук луна лужа луч лыжа
магазин майка мак малина мальчик мама масло машина медведь мёд месяц метла метро мешок мир молоко молоток море морковь мороз мост мука музыка муравей муха мыло мышь мяч
небо неделя нитка нож ножницы нора нос носок ночь
обед облако огонь огород огурец одежда одеяло озеро окно окунь олень орёл орех оса осень остров ответ очки
пакет палка пальто папа пар парк парта парус паук пена перец перо песня песок петух пещера пила пирог письмо планета платье площадка поезд поле полка полотенце помидор посуда потолок почта праздник подарок птица пчела пыль
работа радуга рак ракета ракушка рама растение река репа рис рисунок робот рог роза рот роща рубашка рука ручей ручка рыба рынок рюкзак
сад салат самолёт сапог сахар свеча свёкла свет свитер свинья север семя семья сено сердце сестра сеть сила скала скатерть сковорода слон слово смех снег сова собака сок сокол солдат солнце соль сорока сосна сосед спина спорт стакан стена стекло стол стул сумка суп сыр
таблица тарелка театр телефон тень тесто тигр торт точка трава трактор тропа труба туман тыква
угол уголь удача ужин узел улица улитка улыбка урок утка утро ухо ученик учитель
фабрика факел фартук фасоль февраль фонарь фонтан форма фотография футбол
халат хлеб хлопок холм холодильник хор хомяк хвост художник
цапля цветок цвет цепь цирк цифра цыплёнок
чай чайник чашка час часы человек черепаха черника чертёж чеснок число чулок чудо
шапка шар шахматы шкаф школа шляпа шмель шнур шорты шоссе шуба шум шутка
щенок щека щётка щука экран экскурсия электричество этаж эхо юбка юг юла юность яблоко ягода язык яйцо якорь яма ящик ящерица
]]
local CommonWords = {}
local CommonSet = {}

local function Spawn(callback)
    local thread = task.defer(function()
        local ok, failure = xpcall(callback, debug.traceback)
        if not ok and Alive then
            warn("Word Auto Type: " .. tostring(failure))
            Status = "An operation failed; check the console"
        end
    end)
    Threads[thread] = true
    return thread
end

local function Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Connections, connection)
    return connection
end

local function Notify(message)
    if Alive and WindUI then
        pcall(function()
            WindUI:Notify({Title = "Word Auto Type", Content = message, Duration = 4})
        end)
    end
end

local function Normalize(word)
    if type(word) ~= "string" then
        return nil
    end
    local ok, result = pcall(function()
        local characters = {}
        for _, code in utf8.codes(word) do
            if code >= 1040 and code <= 1071 then
                code = code + 32
            elseif code == 1025 then
                code = 1105
            end
            if not (code >= 1072 and code <= 1103 or code == 1105) then
                return nil
            end
            table.insert(characters, utf8.char(code))
        end
        if #characters < 2 or #characters > 30 then
            return nil
        end
        return table.concat(characters)
    end)
    return ok and result or nil
end

local function Canonical(word)
    return (word:gsub("ё", "е"))
end

local function FirstLetter(word)
    return word:sub(1, utf8.offset(word, 2) - 1)
end

for word in CommonText:gmatch("%S+") do
    local normalized = Normalize(word)
    if normalized and not CommonSet[normalized] then
        CommonSet[normalized] = true
        table.insert(CommonWords, normalized)
    end
end

local function BuildDictionary(text)
    local index = {}
    local unique = {}
    local count = 0
    local scanned = 0
    for line in text:gmatch("[^\r\n]+") do
        local word = Normalize(line:gsub("^\239\187\191", ""))
        if word and not unique[word] then
            unique[word] = true
            local letter = FirstLetter(word)
            local length = utf8.len(word)
            index[letter] = index[letter] or {}
            index[letter][length] = index[letter][length] or {}
            table.insert(index[letter][length], word)
            count = count + 1
        end
        scanned = scanned + 1
        if scanned % 1500 == 0 then
            task.wait()
            if not Alive then
                return nil, 0
            end
        end
    end
    return index, count
end

local function Fetch(url, fresh)
    if fresh then
        url = url .. "?wat=" .. HttpService:GenerateGUID(false)
    end
    local requestFunction = request or http_request or (syn and syn.request)
    local ok, result = pcall(function()
        if requestFunction then
            local response = requestFunction({Url = url, Method = "GET", Headers = { ["Cache-Control"] = "no-cache" }, Timeout = 12})
            if response.StatusCode ~= 200 or type(response.Body) ~= "string" then
                error("HTTP request failed")
            end
            return response.Body
        end
        return game:HttpGet(url, true)
    end)
    return ok and type(result) == "string" and result or nil
end

local function TurnKey(state)
    if not state then
        return nil
    end
    return table.concat({tostring(state.tableId), tostring(state.generation or 0), tostring(state.round), tostring(state.turn), tostring(state.letter)}, ":")
end

local function MatchKey(state)
    return tostring(state.tableId) .. ":" .. tostring(state.generation or 0)
end

local function GetBox()
    local gui = Player.PlayerGui:FindFirstChild("WordGameUI")
    local canvas = gui and gui:FindFirstChild("Canvas")
    local match = canvas and canvas:FindFirstChild("Match")
    return match and match:FindFirstChild("TypingCapture")
end

local function Blocked()
    if Controls.Keybind and Controls.Keybind.Picking then
        return true
    end
    local focused = InputService:GetFocusedTextBox()
    return (focused ~= nil and focused ~= TypingBox) or (TypingBox and TypingBox:GetAttribute("ChatInputBlocked") == true)
end

local function CanPlay(key)
    local state = CurrentState
    local box = TypingBox
    local match = box and box.Parent
    local hearts = match and match:FindFirstChild("Hearts")
    local focusButton = match and match:FindFirstChild("FocusWord")
    local keyboard = match and match:FindFirstChild("WordKeyboard")
    local inputReady = match and match.Visible and hearts and hearts:GetAttribute("Actor") == (state and state.you)
        and (InputService.TouchEnabled and keyboard and keyboard.Visible or not InputService.TouchEnabled and focusButton and focusButton.Visible)
    return Alive and EngineAvailable and state ~= nil and state.phase == "playing" and state.turn == state.you
        and not state.acceptedWord and type(state.letter) == "string" and state.letter ~= ""
        and inputReady and (not key or CurrentTurn == key) and not Blocked()
        and type(state.deadline) == "number" and state.deadline - workspace:GetServerTimeNow() > 0.5
end

local function CancelTyping(message, suppress)
    local job = Job
    Job = nil
    if suppress then
        SuppressedTurn = CurrentTurn
        ManualTurn = nil
    end
    if job and job.thread and job.thread ~= coroutine.running() then
        pcall(task.cancel, job.thread)
        Threads[job.thread] = nil
    end
    if message then
        Status = message
    end
end

local function IsAvailable(word)
    local normalized = Canonical(word)
    return not Used[normalized] and not Rejected[normalized] and not Tried[normalized] and not RoundWords[normalized]
end

local function Estimate(length)
    if SmartEnabled then
        return 1.2 + (length - 1) * 1.45 / Speed + math.floor((length - 1) / 4) * 0.18
    end
    return (length - 1) / Speed
end

local function CandidatePool(letter, seconds)
    local index = Dictionary[letter]
    if not index then
        return {}
    end
    local pool = {}
    if Mode == "Common" then
        for _, word in ipairs(CommonWords) do
            if FirstLetter(word) == letter and IsAvailable(word) and Estimate(utf8.len(word)) <= seconds then
                table.insert(pool, word)
            end
        end
        if #pool > 0 then
            return pool
        end
    end
    local startLength, endLength, step = 2, 30, 1
    if Mode == "Longest" then
        startLength, endLength, step = 30, 2, -1
    elseif Mode == "Common" then
        startLength, endLength = 4, 10
    end
    for length = startLength, endLength, step do
        if Estimate(length) <= seconds then
            for _, word in ipairs(index[length] or {}) do
                if IsAvailable(word) then
                    table.insert(pool, word)
                end
            end
            if #pool > 0 and Mode ~= "Common" then
                break
            end
        end
    end
    return pool
end

local function SetText(text)
    ExpectedText = text
    TypingBox.Text = text
end

local function Submit(job)
    local box = TypingBox
    local requestId = tonumber(box:GetAttribute("AnalyticsSubmit")) or 0
    Pending = {key = job.key, word = job.word, started = os.clock(), requestId = requestId + 1}
    Attempts = Attempts + 1
    Tried[Canonical(job.word)] = true
    RoundWords[Canonical(job.word)] = job.word
    if type(firesignal) == "function" then
        local ok = pcall(firesignal, box.FocusLost, true)
        if ok then
            return true
        end
    end
    if type(getconnections) == "function" then
        local ok, listeners = pcall(getconnections, box.FocusLost)
        if ok then
            for _, listener in ipairs(listeners) do
                local callback = listener.Function
                if callback and pcall(callback, true) then
                    return true
                end
            end
        end
    end
    Pending = nil
    EngineAvailable = false
    Notify("This executor cannot submit words through the game input.")
    return false
end

local function StartTyping()
    if Job or Pending or not CanPlay() or Completed[CurrentTurn] or Attempts >= 3 then
        return false
    end
    local box = GetBox()
    if not box or box ~= TypingBox then
        Status = "Waiting for the game input"
        return false
    end
    if not AutoEnabled and box.Text ~= "" and box.Text ~= ExpectedText then
        SuppressedTurn = CurrentTurn
        ManualTurn = nil
        Status = "Paused: the game input contains your text"
        return false
    end
    local seconds = CurrentState.deadline - workspace:GetServerTimeNow() - 0.5
    local pool = CandidatePool(CurrentState.letter, seconds)
    if #pool == 0 then
        Status = "No available word fits this turn"
        return false
    end
    local word = pool[Randomizer:NextInteger(1, #pool)]
    local job = {key = CurrentTurn, word = word, speed = Speed, smart = SmartEnabled}
    Job = job
    SelectedWord = word
    job.thread = Spawn(function()
        local function Valid()
            return Job == job and CanPlay(job.key) and (AutoEnabled or SuppressedTurn ~= job.key)
        end
        local function Pause(secondsToWait)
            local finishAt = os.clock() + secondsToWait
            repeat
                if not Valid() then
                    return false
                end
                task.wait(math.min(0.03, math.max(0, finishAt - os.clock())))
            until os.clock() >= finishAt
            return Valid()
        end
        Status = job.smart and "Thinking..." or "Typing..."
        if job.smart and not Pause(Randomizer:NextNumber(0.4, 1.2)) then
            if Job == job then CancelTyping("Paused", false) end
            return
        end
        if not Valid() then
            if Job == job then CancelTyping("Paused", false) end
            return
        end
        SetText("")
        Status = "Typing..."
        local suffix = word:sub(utf8.offset(word, 2))
        local text = ""
        local count = 0
        for _, code in utf8.codes(suffix) do
            count = count + 1
            local delay = 1 / job.speed
            if job.smart then
                delay = delay * Randomizer:NextNumber(0.65, 1.45)
                if count % 4 == 0 then
                    delay = delay + Randomizer:NextNumber(0.06, 0.18)
                end
            end
            if not Pause(delay) then
                if Job == job then CancelTyping("Paused", false) end
                return
            end
            text = text .. utf8.char(code)
            SetText(text)
        end
        task.wait()
        if Valid() and box.Text == text then
            Status = Submit(job) and "Waiting for the server" or "Word submission is unavailable"
        end
        if Job == job then
            Job = nil
        end
    end)
    return true
end

local function UpdateBox()
    local box = GetBox()
    if box == TypingBox then
        return
    end
    CancelTyping(nil, false)
    if TextConnection then
        TextConnection:Disconnect()
    end
    TypingBox = box
    ExpectedText = nil
    if box then
        TextConnection = box:GetPropertyChangedSignal("Text"):Connect(function()
            if not Alive or TypingBox ~= box then
                return
            end
            if box.Text ~= ExpectedText and Job then
                if AutoEnabled then
                    if CanPlay(Job.key) then
                        SetText(ExpectedText or "")
                    else
                        CancelTyping("Waiting for the game input", false)
                    end
                elseif box.Text ~= "" or os.clock() - LastManualInput < 0.3 then
                    CancelTyping("Paused: manual input detected", true)
                else
                    ExpectedText = ""
                    NextAttemptAt = os.clock() + 0.25
                    CancelTyping("Waiting for the game input", false)
                end
            end
        end)
    end
    local keyboard = box and box.Parent:FindFirstChild("WordKeyboard")
    if keyboard and keyboard ~= MobileKeyboard then
        MobileKeyboard = keyboard
        for _, button in ipairs(keyboard:GetDescendants()) do
            if button:IsA("TextButton") then
                Connect(button.Activated, function()
                    LastManualInput = os.clock()
                    if Job and not AutoEnabled then CancelTyping("Paused: manual input detected", true) end
                end)
            end
        end
    end
end

local function HandlePacket(packet)
    if not Alive or type(packet) ~= "table" then
        return
    end
    if packet.kind == "match" then
        if CurrentState and packet.tableId == CurrentState.tableId then
            local generation, oldGeneration = packet.generation or 0, CurrentState.generation or 0
            if generation < oldGeneration or generation == oldGeneration and (packet.round or 0) < (CurrentState.round or 0) then
                return
            end
        end
        local match = MatchKey(packet)
        if CurrentMatch ~= match then
            CurrentMatch = match
            Used = {}
            Completed = {}
        end
        local round = match .. ":" .. tostring(packet.round)
        if CurrentRound ~= round then
            CurrentRound = round
            RoundWords = {}
        end
        local key = TurnKey(packet)
        if key ~= CurrentTurn then
            CancelTyping(nil, false)
            CurrentTurn = key
            Pending = nil
            Attempts = 0
            Tried = {}
            ManualTurn = nil
            SuppressedTurn = nil
            ChoiceSent = nil
            ExpectedText = nil
            NextAttemptAt = os.clock() + 0.25
            Status = packet.phase == "playing" and (packet.turn == packet.you and "Waiting for the game input" or "Waiting for the other player")
                or packet.phase == "choosing" and "Waiting for a letter" or "Waiting for the round"
        end
        CurrentState = table.clone(packet)
        if packet.acceptedWord then
            local word = Normalize(packet.acceptedWord)
            if word then
                Used[Canonical(word)] = true
                RoundWords[Canonical(word)] = word
            end
            Completed[key] = true
        end
    elseif packet.kind == "accepted" then
        if not CurrentState or packet.tableId ~= CurrentState.tableId or (packet.generation or 0) ~= (CurrentState.generation or 0) then
            return
        end
        local word = Normalize(packet.word)
        if word then Used[Canonical(word)] = true end
        if packet.round == CurrentState.round then
            if word then RoundWords[Canonical(word)] = word end
            CurrentState.acceptedWord = packet.word
            Completed[CurrentTurn] = true
            Pending = nil
            ManualTurn = nil
            CancelTyping("Word accepted", false)
        end
    elseif packet.kind == "invalid" or packet.kind == "wordRejected" or packet.kind == "missed" then
        if not Pending or not CurrentState then
            return
        end
        if packet.tableId and packet.tableId ~= CurrentState.tableId
            or packet.round and packet.round ~= CurrentState.round
            or packet.generation and packet.generation ~= (CurrentState.generation or 0)
            or packet.actor and packet.actor ~= CurrentState.you
            or packet.requestId and packet.requestId ~= Pending.requestId then
            return
        end
        if packet.kind == "missed" then
            Completed[CurrentTurn] = true
            Pending = nil
            ManualTurn = nil
            CancelTyping("Turn expired", false)
            return
        end
        local word = Canonical(Pending.word)
        if packet.reason == "used" then
            Used[word] = true
        else
            Rejected[word] = true
        end
        Pending = nil
        NextAttemptAt = os.clock() + 0.6
        Status = Attempts < 3 and "Word rejected; selecting another" or "Attempt limit reached"
        if Attempts >= 3 then ManualTurn = nil end
    elseif packet.kind == "lobby" or packet.kind == "result" then
        CancelTyping("Waiting for a match", false)
        CurrentState = nil
        CurrentTurn = nil
        CurrentMatch = nil
        CurrentRound = nil
        RoundWords = {}
        Pending = nil
        ManualTurn = nil
        ChoiceSent = nil
        Used = {}
        Completed = {}
    end
end

local function StopAll()
    AutoEnabled = false
    SmartEnabled = false
    ManualTurn = nil
    CancelTyping("Stopped", true)
    if Controls.Auto then Controls.Auto:Set(false) end
    if Controls.Smart then Controls.Smart:Set(false) end
end

local Session = {}
Session.Controls = Controls
Session.StopAll = StopAll
Session.TypeWord = function()
    if not CanPlay() then
        Notify("Wait for your turn and close any text input.")
        return false
    end
    if Job or Pending then
        Notify("A word is already being processed.")
        return false
    end
    SuppressedTurn = nil
    ManualTurn = CurrentTurn
    return StartTyping()
end
Session.GetStatus = function()
    local roundWords = {}
    for _, word in pairs(RoundWords) do table.insert(roundWords, word) end
    table.sort(roundWords)
    return {
        alive = Alive, status = Status, word = SelectedWord, words = WordCount,
        dictionary = DictionaryStatus, auto = AutoEnabled, smart = SmartEnabled,
        antiAfk = AntiAfkEnabled, mode = Mode, speed = Speed, typing = Job ~= nil,
        pending = Pending ~= nil, attempts = Attempts, turn = CurrentTurn,
        phase = CurrentState and CurrentState.phase, submittedWord = Pending and Pending.word,
        roundWords = roundWords, round = CurrentState and CurrentState.round,
        yourTurn = CurrentState ~= nil and CurrentState.phase == "playing" and CurrentState.turn == CurrentState.you,
    }
end
Session.Unload = function(fromWindow)
    if not Alive then return end
    Alive = false
    AutoEnabled = false
    AntiAfkEnabled = false
    CancelTyping(nil, false)
    if TextConnection then TextConnection:Disconnect() end
    for _, connection in ipairs(Connections) do connection:Disconnect() end
    if type(getconnections) == "function" then
        for _, signal in ipairs({InputService.InputBegan, InputService.InputEnded}) do
            local ok, listeners = pcall(getconnections, signal)
            if ok then
                for _, listener in ipairs(listeners) do
                    local callback = listener.Function
                    if callback then
                        local found, source = pcall(debug.info, callback, "s")
                        if found and type(source) == "string" and source:find("WordAutoTypeWindUI", 1, true) then
                            pcall(function() listener:Disconnect() end)
                        end
                    end
                end
            end
        end
    end
    local running = coroutine.running()
    for thread in pairs(Threads) do
        if thread ~= running and coroutine.status(thread) ~= "dead" then pcall(task.cancel, thread) end
    end
    table.clear(Connections)
    table.clear(Threads)
    if Environment.WordAutoType == Session then Environment.WordAutoType = nil end
    if Window and not fromWindow then pcall(function() Window:Destroy() end) end
end
Environment.WordAutoType = Session

Connect(StateEvent.OnClientEvent, HandlePacket)
UpdateBox()
Action:FireServer("sync")

local librarySource = Fetch("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua")
local libraryOk, libraryResult = pcall(function()
    assert(librarySource, "WindUI download failed")
    return assert(loadstring(librarySource, "@WordAutoTypeWindUI"))()
end)
if not libraryOk or type(libraryResult) ~= "table" then
    warn("Word Auto Type: WindUI could not be loaded.")
    Session.Unload()
    return
end
WindUI = libraryResult

local setupOk, setupError = xpcall(function()
    local theme = table.clone(WindUI:GetThemes().Dark)
    theme.Name = "WordGold"
    for name, hex in pairs({
        Accent = "211E16", Background = "151410", Dialog = "1D1B15", Text = "F5F0E5",
        Placeholder = "AAA18D", Icon = "F6B940", Toggle = "F6B940", Slider = "F6B940",
        Checkbox = "F6B940", Primary = "F6B940", Button = "332D20", ElementBackground = "242119",
        Outline = "A38A52", PanelBackground = "211E17",
    }) do theme[name] = Color3.fromHex(hex) end
    theme.PanelBackgroundTransparency = 0
    WindUI:AddTheme(theme)
    Window = WindUI:CreateWindow({
        Title = "Word Auto Type", Icon = "keyboard", Theme = "WordGold", NewElements = true,
        Size = UDim2.fromOffset(570, 530), MinSize = Vector2.new(350, 330), MaxSize = Vector2.new(850, 700),
        SideBarWidth = 130, AutoScale = false, Acrylic = false, HideSearchBar = true,
        OpenButton = {Title = "Word Auto Type", Enabled = true, Draggable = true, OnlyMobile = false,
            CornerRadius = UDim.new(1, 0), Color = ColorSequence.new(Color3.fromHex("F6B940"))},
    })
    Session.Window = Window
    Window:OnDestroy(function() Session.Unload(true) end)
    local main = Window:Tab({Title = "Main", Icon = "keyboard"})
    local settings = Window:Tab({Title = "Settings", Icon = "settings"})
    main:Button({Title = "Type Word", Icon = "text-cursor-input", Callback = Session.TypeWord})
    Controls.Auto = main:Toggle({Title = "Auto Type", Value = false, Callback = function(value)
        AutoEnabled = value
        if value then
            SuppressedTurn = nil
            Status = "Auto Type enabled"
        else
            ManualTurn = nil
            CancelTyping("Auto Type disabled", true)
        end
    end})
    Controls.Speed = main:Slider({Title = "Typing Speed", Step = 1, IsTooltip = true,
        Value = {Min = 1, Max = 30, Default = 8}, Callback = function(value) Speed = math.clamp(tonumber(value) or 8, 1, 30) end})
    Controls.Smart = main:Toggle({Title = "Smart Typing", Value = false, Callback = function(value) SmartEnabled = value end})
    Controls.Mode = main:Dropdown({Title = "Word Mode", Values = {"Common", "Shortest", "Longest"}, Value = "Common",
        AllowNone = false, Callback = function(value)
            if type(value) == "table" then value = value.Title end
            if value == "Common" or value == "Shortest" or value == "Longest" then Mode = value end
        end})
    StatusPanel = main:Paragraph({Title = "Status", Desc = "Loading..."})
    settings:Section({Title = "Session"})
    Controls.AntiAfk = settings:Toggle({Title = "Anti AFK", Value = true, Callback = function(value) AntiAfkEnabled = value end})
    settings:Button({Title = "Stop All", Icon = "square", Callback = StopAll})
    Controls.Keybind = settings:Keybind({Title = "Menu Keybind", Value = "RightControl",
        Blacklist = {"Return", "KeypadEnter", "MouseLeftButton", "MouseRightButton"}, Callback = function() end})
    settings:Button({Title = "Unload", Icon = "power", Callback = function() Session.Unload() end})
    settings:Section({Title = "Credits"})
    local function CopyLink(link)
        local copy = setclipboard or toclipboard
        if copy and pcall(copy, link) then
            Notify("Link copied to clipboard.")
        else
            if not CopyField then CopyField = settings:Input({Title = "Link", Type = "Textarea", Value = link, Callback = function() end}) end
            CopyField:Set(link)
            Notify("Select and copy the link below Credits.")
        end
    end
    Controls.Credits = settings:Button({Title = "Credits - " .. CreditsAddress, Icon = "copy", Callback = function() CopyLink("https://" .. CreditsAddress) end})
    settings:Button({Title = "UI Library - github.com/Footagesus/WindUI", Icon = "copy", Callback = function() CopyLink(LibraryUrl) end})
    main:Select()
end, debug.traceback)

if not setupOk then
    warn("Word Auto Type: interface setup failed: " .. tostring(setupError))
    Session.Unload()
    return
end

local CameraConnection
local function FitWindow()
    local camera = workspace.CurrentCamera
    if not Alive or not camera or Window.IsFullscreen then return end
    local viewport = camera.ViewportSize
    local size = Window.Size
    Window:SetUIScale(math.clamp(math.min((viewport.X - 24) / size.X.Offset, (viewport.Y - 24) / size.Y.Offset), 0.3, 1))
    Window:SetToTheCenter()
end
local function WatchCamera()
    if CameraConnection then CameraConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    if camera then CameraConnection = Connect(camera:GetPropertyChangedSignal("ViewportSize"), FitWindow) end
    FitWindow()
end
Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), WatchCamera)
WatchCamera()
Window:OnClose(function()
    Spawn(function()
        task.wait(0.4)
        if Alive and Window.Closed and not Window.Destroyed then Window.OpenButtonMain:Visible(true) end
    end)
end)

Connect(InputService.InputBegan, function(input)
    local bind = Controls.Keybind
    if Alive and bind and not bind.Picking and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == bind.Value then
        Window:Toggle()
    elseif input.UserInputType == Enum.UserInputType.Keyboard and InputService:GetFocusedTextBox() == TypingBox then
        LastManualInput = os.clock()
        if Job and not AutoEnabled then CancelTyping("Paused: manual input detected", true) end
    end
end)

Connect(Player.Idled, function()
    if not Alive or not AntiAfkEnabled then return end
    local ok = pcall(function()
        local virtualUser = game:GetService("VirtualUser")
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.zero)
    end)
    if not ok then
        Controls.AntiAfk:Set(false)
        Notify("Anti AFK is unavailable in this executor.")
    end
end)

Spawn(function()
    local response = Fetch(CreditsUrl, true)
    if not Alive then return end
    if response then
        local address = response:match("^%s*(.-)%s*$"):gsub("^https?://", ""):gsub("/$", "")
        if address:match("^t%.me/[%w_]+$") then CreditsAddress = address end
    end
    Controls.Credits:SetTitle("Credits - " .. CreditsAddress)
end)

Spawn(function()
    local data = Fetch(DictionaryUrl)
    local index, count
    if data then index, count = BuildDictionary(data) end
    local origin = "Online"
    if not index or count < 1000 then
        data = nil
        if type(readfile) == "function" then
            local ok, cached = pcall(readfile, CachePath)
            if ok and type(cached) == "string" then index, count = BuildDictionary(cached) end
        end
        origin = "Cached"
    end
    if not index or count < 1000 then
        index, count = BuildDictionary(CommonText:gsub("%s+", "\n"))
        origin = "Built-in backup"
    elseif data and type(writefile) == "function" and Alive then
        pcall(writefile, CachePath, data)
    end
    if not Alive then return end
    Dictionary, WordCount = index, count
    DictionaryStatus = origin .. " | " .. tostring(count) .. " words"
    if origin ~= "Online" then Notify("Using the " .. origin:lower() .. " dictionary.") end
end)

Spawn(function()
    local nextSync = os.clock() + 2
    while Alive do
        task.wait(0.1)
        UpdateBox()
        for thread in pairs(Threads) do
            if coroutine.status(thread) == "dead" then Threads[thread] = nil end
        end
        if Pending and os.clock() - Pending.started > 5 then
            Completed[Pending.key] = true
            Pending = nil
            ManualTurn = nil
            Status = "No server confirmation; waiting for the next turn"
        end
        if os.clock() >= nextSync then
            nextSync = os.clock() + 15
            Action:FireServer("sync")
        end
        local state = CurrentState
        if EngineAvailable and WordCount > 0 and not Blocked() and os.clock() >= NextAttemptAt then
            if AutoEnabled and state and state.phase == "choosing" and state.chooser == state.you and type(state.choices) == "table" then
                local choiceKey = MatchKey(state) .. ":" .. tostring(state.round)
                if ChoiceSent ~= choiceKey then
                    local best, choices = -1, {}
                    for _, letter in ipairs(state.choices) do
                        local count = #CandidatePool(letter, math.huge)
                        if count > best then best, choices = count, {letter}
                        elseif count == best then table.insert(choices, letter) end
                    end
                    if best > 0 then
                        ChoiceSent = choiceKey
                        Action:FireServer("choose", choices[Randomizer:NextInteger(1, #choices)])
                        Status = "Letter selected"
                    else
                        Status = "No words available for these letters"
                    end
                end
            elseif (AutoEnabled or ManualTurn == CurrentTurn and ManualTurn ~= nil) and (AutoEnabled or SuppressedTurn ~= CurrentTurn) then
                StartTyping()
            end
        elseif Blocked() and not Job then
            Status = "Paused: text input or keybind selection"
        end
        if not state and not Job then Status = "Waiting for a match" end
        local roundCount = 0
        for _ in pairs(RoundWords) do roundCount = roundCount + 1 end
        local panelText = Status .. "\nWord: " .. SelectedWord .. "\nWords this round: " .. roundCount .. "\nDictionary: " .. DictionaryStatus
        if panelText ~= LastPanelText then
            LastPanelText = panelText
            StatusPanel.ParagraphFrame:SetDesc(panelText)
        end
    end
end)

if not EngineAvailable then Notify("This executor does not support word submission. Menu controls remain available.") end
Notify("Ready. Start a match, then use Type Word or enable Auto Type.")

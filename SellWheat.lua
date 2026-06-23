-- // t.me/arceusxcommunity <3
if _G.SellWheatAutoFarm then
    pcall(function() _G.SellWheatAutoFarm:Destroy() end)
end

local GEN = (_G.SellWheatGen or 0) + 1
_G.SellWheatGen = GEN
local function alive() return _G.SellWheatGen == GEN end

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local VirtualUser      = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local Settings    = ReplicatedStorage:WaitForChild("Settings")

local Collect = Remotes:WaitForChild("Collect")
local Sell    = Remotes:WaitForChild("Sell")
local Shops   = Remotes:WaitForChild("Shops")
local Rebirth     = Remotes:WaitForChild("Rebirth")
local QuestR      = Remotes:WaitForChild("Quest")
local QuestSecond = Remotes:WaitForChild("QuestSecond")
local AutoTP      = Remotes:WaitForChild("AutoTP")

local State = {
    AutoCollect     = false,
    AutoSell        = false,
    AntiAFK         = true,
    CollectPercent  = 10,
    SellInterval    = 4,
    CollectInterval = 1,

    AutoBuy         = false,
    BuyInterval     = 3,
    Selected        = {},

    AutoRebirth     = false,
    AutoClaim       = false,
}

local function shortNum(n)
    if type(n) ~= "number" then return tostring(n) end
    local abs = math.abs(n)
    local suf, div = "", 1
    if abs >= 1e12 then suf, div = "T", 1e12
    elseif abs >= 1e9 then suf, div = "B", 1e9
    elseif abs >= 1e6 then suf, div = "M", 1e6
    elseif abs >= 1e3 then suf, div = "K", 1e3 end
    local v = n / div
    if suf == "" then return tostring(math.floor(v)) end
    return string.format("%.2f", v):gsub("%.?0+$", "") .. suf
end

local function rebirths()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local r = ls and ls:FindFirstChild("Rebirths")
    if r then
        local v = r:FindFirstChild("V")
        return tonumber(v and v.Value) or tonumber(r.Value) or 0
    end
    return 0
end

local function cashNum()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local c = ls and ls:FindFirstChild("Cash")
    if not c then return 0 end
    local v = c:FindFirstChild("V")
    return tonumber(v and v.Value) or 0
end

local RebirthCosts = {}
do
    local ok, mod = pcall(require, Settings:FindFirstChild("Rebirths"))
    if ok and type(mod) == "table" then
        for k, info in pairs(mod) do
            local idx = tonumber(k)
            if idx and type(info) == "table" then
                RebirthCosts[idx] = tonumber(info.Cost) or 0
            end
        end
    end
end

local function nextRebirthCost()
    return RebirthCosts[rebirths() + 1]
end

local Catalog = {}
local CatalogByName = {}
local LiveStock = {}

local CAT_META = {
    Harvesters = { emoji = "🚜", info = function(i) return tostring(i.CPS or 0) .. "/s wheat" end },
    Mills      = { emoji = "🏭", info = function(i) return "capacity " .. shortNum(i.Capacity or 0) end },
    Animals    = { emoji = "🐷", info = function(i) return "$" .. shortNum(i.CPS or 0) .. "/s" end },
}

local function buildCatalog()
    for _, cat in ipairs({ "Harvesters", "Mills", "Animals" }) do
        local meta = CAT_META[cat]
        local ok, mod = pcall(require, Settings:FindFirstChild(cat))
        if ok and type(mod) == "table" then
            for name, info in pairs(mod) do
                if type(info) == "table" then
                    local price = info.Price
                    local priceStr = (type(price) == "number") and ("$" .. shortNum(price)) or "Robux"
                    local reb = tonumber(info.Rebirth) or 0
                    local label = string.format("%s %s — %s • %s • R%d",
                        meta.emoji, name, priceStr, meta.info(info), reb)
                    local entry = {
                        cat = cat, name = name, price = price,
                        rebirth = reb, info = meta.info(info), label = label,
                        sortKey = (type(price) == "number") and price or math.huge,
                    }
                    table.insert(Catalog, entry)
                    CatalogByName[cat .. "|" .. name] = entry
                end
            end
        end
    end
    table.sort(Catalog, function(a, b)
        if a.cat ~= b.cat then return a.cat < b.cat end
        return a.sortKey < b.sortKey
    end)
end
buildCatalog()

Shops.OnClientEvent:Connect(function(kind, data)
    if kind == "Data" and type(data) == "table" then
        for cat, items in pairs(data) do
            if type(items) == "table" then
                for _, it in pairs(items) do
                    if type(it) == "table" and it.Name then
                        LiveStock[cat .. "|" .. it.Name] = it.Stock or 0
                    end
                end
            end
        end
    end
end)
pcall(function() Shops:FireServer("Request") end)
task.spawn(function()
    while alive() do
        pcall(function() Shops:FireServer("Request") end)
        task.wait(5)
    end
end)

local function getMyPlot()
    local PO = workspace:FindFirstChild("PlacedObjects")
    return PO and PO:FindFirstChild(LocalPlayer.Name)
end

local function getReadyMills()
    local plot = getMyPlot()
    local list = {}
    if not plot then return list end
    local minFrac = State.CollectPercent / 100
    for _, obj in ipairs(plot:GetChildren()) do
        if obj:GetAttribute("PlacedType") == "Mills" then
            local cap = obj:GetAttribute("CurrentCapacity") or 0
            local max = obj:GetAttribute("MaxCapacity") or 1
            if cap > 1 and cap >= max * minFrac then
                table.insert(list, obj)
            end
        end
    end
    return list
end

local function collectAll()
    local mills = getReadyMills()
    for _, mill in ipairs(mills) do
        Collect:FireServer(mill)
    end
    return #mills
end

local function buyEntry(entry)
    if type(entry.price) ~= "number" then return false, "Robux" end
    if rebirths() < entry.rebirth then return false, "need Rebirth " .. entry.rebirth end
    local key = entry.cat .. "|" .. entry.name
    if (LiveStock[key] or 0) <= 0 then return false, "out of stock" end
    Shops:FireServer("Buy", entry.cat, entry.name)
    return true
end

local Window = Fluent:CreateWindow({
    Title    = "Sell Wheat! 🌾  Auto Farm",
    Search   = false,
    Icon     = "wheat",
    TabWidth = 150,
    Size     = UDim2.fromOffset(560, 420),
    Acrylic  = true,
    Theme    = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

_G.SellWheatAutoFarm = Window

local Tabs = {
    Main = Window:AddTab({ Title = "Auto Farm", Icon = "play" }),
    Buy  = Window:AddTab({ Title = "Auto Buy", Icon = "shopping-cart" }),
}
Window:SelectTab(1)

Tabs.Main:AddParagraph({
    Icon = "info", Title = "How it works",
    Content = "Collects wheat from all your mills and sells it for cash. "
            .. "Turn both switches on, then you can minimize the window (Left Ctrl).",
})

Tabs.Main:AddToggle("AutoCollect", { Title = "Auto Collect Wheat", Default = false })
    :OnChanged(function(v) State.AutoCollect = v end)
Tabs.Main:AddToggle("AutoSell", { Title = "Auto Sell", Default = false })
    :OnChanged(function(v) State.AutoSell = v end)
Tabs.Main:AddSlider("CollectPercent", {
    Title = "Collect when full (%)",
    Description = "Lower value = collects more often",
    Default = 10, Min = 1, Max = 100, Rounding = 0,
    Callback = function(v) State.CollectPercent = v end,
})
Tabs.Main:AddSlider("SellInterval", {
    Title = "Sell interval (sec)",
    Default = 4, Min = 1, Max = 30, Rounding = 0,
    Callback = function(v) State.SellInterval = v end,
})
Tabs.Main:AddButton({ Title = "Collect everything now", Callback = function()
    local n = collectAll()
    Fluent:Notify({ Title = "Collect", Content = "Mills collected: " .. n, Duration = 3 })
end })
Tabs.Main:AddButton({ Title = "Sell now", Callback = function()
    Sell:FireServer()
    Fluent:Notify({ Title = "Sell", Content = "Wheat sold 💰", Duration = 3 })
end })
Tabs.Main:AddToggle("AntiAFK", { Title = "Anti-AFK", Default = true })
    :OnChanged(function(v) State.AntiAFK = v end)

Tabs.Main:AddToggle("AutoRebirth", { Title = "Auto Rebirth (as soon as you can afford it)", Default = false })
    :OnChanged(function(v) State.AutoRebirth = v end)
Tabs.Main:AddToggle("AutoClaim", { Title = "Auto Claim rewards (Quest / Playtime)", Default = false })
    :OnChanged(function(v) State.AutoClaim = v end)
Tabs.Main:AddButton({ Title = "Rebirth now", Callback = function()
    Rebirth:FireServer()
    Fluent:Notify({ Title = "Rebirth", Content = "Rebirth request sent 🔄", Duration = 3 })
end })

local FarmStatus = Tabs.Main:AddParagraph({ Icon = "activity", Title = "Status", Content = "..." })

Tabs.Buy:AddParagraph({
    Icon = "info", Title = "Shop",
    Content = "Pick items from the list. The price, stats and required Rebirth (R) are shown in each label. "
            .. "Bought items go into your inventory — place them yourself.",
})

local labels = {}
for _, e in ipairs(Catalog) do table.insert(labels, e.label) end

local ItemsDropdown = Tabs.Buy:AddDropdown("BuyItems", {
    Title  = "Items to buy",
    Description = "You can pick several",
    Values = labels,
    Multi  = true,
    Default = {},
})
ItemsDropdown:OnChanged(function(value)
    local sel = {}
    if type(value) == "table" then
        for k, v in pairs(value) do
            local label = (v == true) and k or v
            if type(label) == "string" then
                for _, e in ipairs(Catalog) do
                    if e.label == label then sel[label] = e break end
                end
            end
        end
    end
    State.Selected = sel
end)

Tabs.Buy:AddSlider("BuyInterval", {
    Title = "Auto-buy interval (sec)",
    Default = 3, Min = 1, Max = 30, Rounding = 0,
    Callback = function(v) State.BuyInterval = v end,
})

Tabs.Buy:AddButton({ Title = "Buy selected (once)", Callback = function()
    local bought, skipped = 0, 0
    for _, e in pairs(State.Selected) do
        local ok = buyEntry(e)
        if ok then bought += 1 else skipped += 1 end
        task.wait(0.2)
    end
    Fluent:Notify({ Title = "Purchase", Content = ("Bought: %d, Skipped: %d"):format(bought, skipped), Duration = 4 })
end })

Tabs.Buy:AddToggle("AutoBuy", { Title = "Auto Buy", Default = false })
    :OnChanged(function(v) State.AutoBuy = v end)

local BuyStatus = Tabs.Buy:AddParagraph({ Icon = "shopping-cart", Title = "Selected", Content = "nothing selected" })

task.spawn(function()
    while alive() do
        if State.AutoCollect then pcall(collectAll) end
        task.wait(State.CollectInterval)
    end
end)

task.spawn(function()
    while alive() do
        if State.AutoSell then pcall(function() Sell:FireServer() end) end
        task.wait(State.SellInterval)
    end
end)

task.spawn(function()
    while alive() do
        if State.AutoBuy then
            for _, e in pairs(State.Selected) do
                pcall(buyEntry, e)
                task.wait(0.2)
            end
        end
        task.wait(State.BuyInterval)
    end
end)

task.spawn(function()
    while alive() do
        if State.AutoRebirth then
            local cost = nextRebirthCost()
            if cost and cashNum() >= cost then
                pcall(function() Rebirth:FireServer() end)
                task.wait(2)
            end
        end
        task.wait(2)
    end
end)

task.spawn(function()
    local nextAutoTP = 0
    while alive() do
        if State.AutoClaim then
            local now = workspace:GetServerTimeNow()
            local q1 = tonumber(LocalPlayer:GetAttribute("SmallTotemQuestReadyAt")) or 0
            if q1 > 0 and q1 <= now then pcall(function() QuestR:FireServer() end) end
            local q2 = tonumber(LocalPlayer:GetAttribute("QuestSecondReadyAt")) or 0
            if q2 > 0 and q2 <= now then pcall(function() QuestSecond:FireServer() end) end
            if os.clock() >= nextAutoTP then
                pcall(function() AutoTP:FireServer() end)
                nextAutoTP = os.clock() + 1085
            end
        end
        task.wait(3)
    end
end)

LocalPlayer.Idled:Connect(function()
    if State.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

task.spawn(function()
    while alive() do
        local cash = "?"
        local ls = LocalPlayer:FindFirstChild("leaderstats")
        if ls and ls:FindFirstChild("Cash") then cash = ls.Cash.Value end
        local plot = getMyPlot()
        local millCount, totalCap = 0, 0
        if plot then
            for _, o in ipairs(plot:GetChildren()) do
                if o:GetAttribute("PlacedType") == "Mills" then
                    millCount += 1
                    totalCap += (o:GetAttribute("CurrentCapacity") or 0)
                end
            end
        end
        local cost = nextRebirthCost()
        local rebLine
        if cost then
            rebLine = string.format("Next Rebirth: $%s (have $%s, %.0f%%)",
                shortNum(cost), shortNum(cashNum()), math.min(100, cashNum() / cost * 100))
        else
            rebLine = "Next Rebirth: MAX"
        end
        pcall(function() FarmStatus:SetDesc(string.format(
            "💰 Cash: %s | 🔄 Rebirths: %d\n🏭 Mills: %d 🌾 Wheat stored: %s\nCollect: %s | Sell: %s | Rebirth: %s | Claim: %s\n%s",
            tostring(cash), rebirths(), millCount, shortNum(math.floor(totalCap)),
            State.AutoCollect and "ON" or "OFF", State.AutoSell and "ON" or "OFF",
            State.AutoRebirth and "ON" or "OFF", State.AutoClaim and "ON" or "OFF",
            rebLine)) end)
        task.wait(1)
    end
end)

task.spawn(function()
    while alive() do
        local n, total = 0, 0
        local lines = {}
        for _, e in pairs(State.Selected) do
            n += 1
            local key = e.cat .. "|" .. e.name
            local stock = LiveStock[key] or 0
            if type(e.price) == "number" then total += e.price end
            if n <= 8 then
                table.insert(lines, string.format("• %s — $%s (stock %d, R%d)",
                    e.name, shortNum(type(e.price) == "number" and e.price or 0), stock, e.rebirth))
            end
        end
        local header
        if n == 0 then
            header = "nothing selected"
        else
            header = string.format("Selected: %d | Total: $%s | Auto: %s\n%s",
                n, shortNum(total), State.AutoBuy and "ON" or "OFF", table.concat(lines, "\n"))
            if n > 8 then header = header .. ("\n…and %d more"):format(n - 8) end
        end
        pcall(function() BuyStatus:SetDesc(header) end)
        task.wait(1)
    end
end)

local Library = loadstring(game:HttpGetAsync("https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"))()

local Window = Library:CreateWindow{
    Title = "items Manager",
    SubTitle = "by bac0nh1ckoff",
    TabWidth = 160,
    Size = UDim2.fromOffset(530, 325),
    Resize = true,
    MinSize = Vector2.new(470, 380),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.Q
}

local Tabs = {
    Main = Window:CreateTab{
        Title = "Main",
        Icon = "phosphor-users-bold"
    }
}

local Options = Library.Options

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local inventory = player:WaitForChild("Inventory")

local sack = nil
local function findSack()
    for _, item in pairs(inventory:GetChildren()) do
        if string.find(item.Name, "Sack") then
            return item
        end
    end
    return nil
end

sack = findSack()

inventory.ChildAdded:Connect(function(child)
    if string.find(child.Name, "Sack") then
        sack = child
    end
end)

inventory.ChildRemoved:Connect(function(child)
    if sack and child == sack then
        sack = findSack()
    end
end)

local itemsFolder = workspace:FindFirstChild("Items")
local lastPos = nil
local items = {}
local name = nil

local function isSackFull()
    if not sack then return true end
    local current = sack:GetAttribute("NumberItems")
    local capacity = sack:GetAttribute("Capacity")
    return current ~= nil and capacity ~= nil and current >= capacity
end

local function store(item)
    if not sack then return end
    local part = item:FindFirstChildWhichIsA("BasePart")
    if part then
        humanoidRootPart.CFrame = part.CFrame
        task.wait(0.2)
        ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("RequestBagStoreItem"):InvokeServer(sack, item)
        task.wait(0.2)
    end
end

local Items = Tabs.Main:CreateDropdown("ItemsList", {
    Title = "Items List",
    Values = items,
    Multi = false,
    Default = "",
})
Items:OnChanged(function(Value)
    name = Value
end)

local debounce = false
local function updateItemsDropdown()
    if debounce then return end
    debounce = true

    task.delay(0.1, function()
        if not Items then return end

        local uniqueItems = {}
        local addedNames = {}

        for _, itm in pairs(itemsFolder:GetChildren()) do
            if typeof(itm.Name) == "string" and not addedNames[itm.Name] then
                table.insert(uniqueItems, itm.Name)
                addedNames[itm.Name] = true
            end
        end

        items = uniqueItems
        if typeof(Items.SetValues) == "function" then
            pcall(function()
                Items:SetValues(items)
            end)
        end

        debounce = false
    end)
end

updateItemsDropdown()

Tabs.Main:CreateButton{
    Title = "Bring Item",
    Description = "",
    Callback = function()
        lastPos = humanoidRootPart.CFrame
        for _, item in pairs(itemsFolder:GetChildren()) do
            if isSackFull() then
                break
            end
            if item.Name == name then
                store(item)
            end
        end
        humanoidRootPart.CFrame = lastPos
    end
}

Tabs.Main:CreateButton{
    Title = "Teleport to Item",
    Description = "",
    Callback = function()
        local item = itemsFolder:FindFirstChild(name)
        if item then
            local part = item:FindFirstChildWhichIsA("BasePart")
            if part then
                humanoidRootPart.CFrame = part.CFrame
            end
        end
    end
}

local campfire = workspace:FindFirstChild("Map"):FindFirstChild("Campground"):FindFirstChild("MainFire")
Tabs.Main:CreateButton{
    Title = "Teleport to Campfire",
    Description = "",
    Callback = function()
        if campfire then
            local center = campfire:FindFirstChild("Center")
            if center then
                humanoidRootPart.CFrame = center.CFrame * CFrame.new(0, 13, 0)
            end
        end
    end
}

itemsFolder.ChildAdded:Connect(updateItemsDropdown)
itemsFolder.ChildRemoved:Connect(updateItemsDropdown)

Window:SelectTab(1)

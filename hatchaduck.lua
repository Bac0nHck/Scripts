-- // https://www.roblox.com/games/123410273444568/UPD-Hatch-a-Duck
local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Turtle-Brand/Turtle-Lib/main/source.lua"))()
local w = lib:Window("Hatch a Duck")

local players = game:GetService("Players")
local plr = players.LocalPlayer

local hatch = game:GetService("Workspace"):FindFirstChild(plr.Name .. "_Hatch")
if not hatch then
	print("Hatch not found")
	return
end
local eggs = game:GetService("Workspace"):FindFirstChild(plr.Name .. "_Eggs")
if not eggs then
	print("Eggs not found")
	return
end

getgenv().settings = {
	autoCollect = false,
	autoSell = false,
	autoHatch = false
}

w:Toggle("Auto Collect Eggs", false, function (val)
	settings.autoCollect = val
	if val then
		spawn(function ()
			while settings.autoCollect do
				local eggs = {}
				for _, egg in ipairs(hatch:GetDescendants()) do
					if egg:IsA("ProximityPrompt") and egg.Parent then
						table.insert(eggs, egg)
					end
				end
				for _, egg in ipairs(eggs) do
					local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						hrp.CFrame = egg.Parent.CFrame + Vector3.new(0, 3, 0)
						task.wait(0.25)
						fireproximityprompt(egg, egg.MaxActivationDistance)
						task.wait(0.1)
					end
					if not settings.autoCollect then
						break
					end
				end
				task.wait(0.5)
			end
		end)
	end
end)
w:Toggle("Auto Hatch", false, function (val)
	settings.autoHatch = val
	if val then
		spawn(function ()
			while settings.autoHatch do
				for _, egg in ipairs(eggs:GetDescendants()) do
					if egg:FindFirstChild("BillboardGui") and egg.BillboardGui:FindFirstChild("Frame") and egg.BillboardGui.Frame:FindFirstChild("Timer") then
						local timer = egg.BillboardGui.Frame.Timer
						if timer.Text == "Ready!" then
							local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
							if hrp then
								hrp.CFrame = egg.CFrame + Vector3.new(0, 3, 0)
								task.wait(0.25)
								fireproximityprompt(egg:FindFirstChild("ProximityPrompt"), egg:FindFirstChild("ProximityPrompt").MaxActivationDistance)
								task.wait(0.1)
							end
						end
					end
				end
				task.wait(0.5)
			end
		end)
	end
end)
local function sellAll()
	game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("SellAllEvent"):FireServer()
end
w:Button("Sell All", function ()
	sellAll()
end)
w:Toggle("Auto Sell All", false, function (val)
	settings.autoSell = val
	if val then
		spawn(function ()
			while settings.autoSell do
				sellAll()
				task.wait(1)
			end
		end)
	end
end)
w:Button("Open Eggs UI", function ()
	local duckUI = plr.PlayerGui:FindFirstChild("Vliccs_DuckUI"):FindFirstChild("Frames"):FindFirstChild("Ducks")
	duckUI.Visible = true
	duckUI.Size = UDim2.new(1.115, 0, 0.543, 0)
end)
w:Button("Anti AFK", function()
	local bb = game:GetService("VirtualUser")
	plr.Idled:Connect(
        function()
		bb:CaptureController()
		bb:ClickButton2(Vector2.new())
	end
    )
end)
w:Label("~ t.me/arceusxscripts", Color3.fromRGB(127, 143, 166))
w:Button("Destroy GUI", function ()
    w:Destroy()
    settings.autoCollect = false
    settings.autoSell = false
    settings.autoHatch = false
end)

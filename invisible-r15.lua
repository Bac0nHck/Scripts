--Free use, Don't report the animation id.
--https://scriptblox.com/script/Universal-Script-Zayas-Invisibility-Thing-FE-R15-Only-47898

--getgenv().mobile = true -- to create a button for phones

local plr = game.Players.LocalPlayer
local char = nil
local hum = nil
local anim = nil
local isInvisible = false
local isDead = true
local ScriptRunning = true

local invisSettings = {
	HipHeight = 0.3
}

local defaultSettings = {
	HipHeight = 2.11
}

local uis = game:GetService("UserInputService")

local function startmsg()
	local msg = [[
        [Zaya's Invisibility Thing]
-–—————————————————————————————–−
Press V to Toggle invisibility.
Hold C to be invisible.
Press F1 to quit this script.

(Note: this message is not seen by other players, and this script only works in R15.)
-–—————————————————————————————–−
    ]]
	
	local function AddColorToString(String:string, Color:Color3)
		return "<font color='#"..Color:ToHex().."'>"..String.."</font>"
	end
	local function FontFace(String:string, FontId:Enum.Font)
		return "<font face='".. FontId.Name .."'>".. String .."</font>"
	end

	msg = FontFace(msg, Enum.Font.Code)

	game.TextChatService.TextChannels.RBXGeneral:DisplaySystemMessage(AddColorToString(msg, Color3.fromRGB(255, 201, 75)))
end

local function byemsg()
	local msg = [[
Script stopped, Thanks for using Zaya's Invisibility Thing!
    ]]

	local function AddColorToString(String:string, Color:Color3)
		return "<font color='#"..Color:ToHex().."'>"..String.."</font>"
	end
	local function FontFace(String:string, FontId:Enum.Font)
		return "<font face='".. FontId.Name .."'>".. String .."</font>"
	end

	msg = FontFace(msg, Enum.Font.Code)

	game.TextChatService.TextChannels.RBXGeneral:DisplaySystemMessage(AddColorToString(msg, Color3.fromRGB(255, 201, 75)))
end

local function reset(ch)
	char = ch
	hum = char:WaitForChild("Humanoid")
	anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://122954953446602"
	anim = hum:LoadAnimation(anim)
	anim:AdjustSpeed(0.01)
	anim.Priority = Enum.AnimationPriority.Action4
	isDead = false
end

local function Set(state)
	if isDead or not ScriptRunning then return end
	if state then
		isInvisible = true
		anim:Play()
		hum.HipHeight = invisSettings.HipHeight
	else
		isInvisible = false
		anim:Stop()
		hum.HipHeight = defaultSettings.HipHeight
	end
end

plr.CharacterAdded:Connect(function(ch)
	reset(ch)
end)

wait()

if plr.Character then
	reset(plr.Character)
else	
	plr.CharacterAdded:Wait()
	reset(plr.Character)
end

hum.HealthChanged:Connect(function(h)
	if h <= 1 and not isDead and ScriptRunning then
		Set(false)
		isDead = true
		char:SetPrimaryPartCFrame(CFrame.new(0,workspace.FallenPartsDestroyHeight/1.05,0))
	end
end)

uis.InputBegan:Connect(function(input, isChat)
	if isChat or isDead or not ScriptRunning then return end
	if input.KeyCode == Enum.KeyCode.V then
		Set(not isInvisible)
	elseif uis:IsKeyDown(Enum.KeyCode.C) then
		repeat
			wait()
			Set(true)
		until
		uis:IsKeyDown(Enum.KeyCode.C) ~= true
		
		Set(false)
	elseif uis:IsKeyDown(Enum.KeyCode.F1) then
        Set(false)
		ScriptRunning = false
		byemsg()
	end
end)

startmsg()

if mobile then 
    task.spawn(function() -- mobile button
        loadstring(game:HttpGet("https://pastebin.com/raw/uqAfqEJH"))()("V")
    end)
end

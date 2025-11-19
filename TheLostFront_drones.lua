-- getgenv().farm = true

local plr = game:GetService("Players").LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local cam = workspace.CurrentCamera

local drones = workspace:FindFirstChild("drones")
local localTeam = char.Parent.Name
repeat
    task.wait()
    char = plr.Character or plr.CharacterAdded:Wait()
    localTeam = char.Parent.Name
until localTeam == "attackers" or localTeam == "defenders"

if drones then
    drones.ChildAdded:Connect(function(child)
        repeat
            task.wait()
            char = plr.Character or plr.CharacterAdded:Wait()
            localTeam = char.Parent.Name
        until localTeam == "attackers" or localTeam == "defenders"

        local fpv = child:WaitForChild("FPV", 5)
        local teamTag = fpv:WaitForChild("Team", 5)
        if fpv and teamTag and teamTag.Value ~= localTeam and getgenv().farm then
            cam.CameraSubject = fpv
            repeat task.wait() until not getgenv().farm or not fpv:IsDescendantOf(workspace)
            cam.CameraSubject = char:FindFirstChildOfClass("Humanoid") or char
        end
    end)
else
    return
end

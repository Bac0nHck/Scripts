-- https://scriptblox.com/script/RetroStudio-retrostudio-model-copier-47793
-- https://www.roblox.com/games/5846386835/RetroStudio

-- local model_id = ""
local Settings = {};
Settings.ModelId = "rbxassetid://" .. model_id
Settings.BlacklistedProperties = { "PartPack", "Parent", "Shape" }
Settings.BlacklistedClasses = { "Script", "LocalScript", "ModuleScript" }

--! Ignore anything past this
-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local InsertService = game:GetService("InsertService");

-- Variables
local _RetroStudio = ReplicatedStorage:FindFirstChild("_RetroStudio");
local Remotes = _RetroStudio.Remotes
local HashLibrary = require(_RetroStudio.HashLib);
local Properties = require(_RetroStudio.PermissionData.ClassData);
local Hint = Instance.new("Hint", workspace); Hint.Text = "Getting model to copy (if this message won't change, then there has been an error.)"

-- Types
type Creation = {
    Class: string,
    Parent: Instance,
    Properties: { [string]: any },
}

-- Functions
local GenerateHash = function()
    local Clock = os.clock();
    return HashLibrary.md5((("\224\182\158%*\224\182\158"):format(Clock))), Clock
end 

local Create = function(Data: Creation)
    if table.find(Settings.BlacklistedClasses, Data.Class) then
        return warn("Ignored class:", Data.Class);
    end

    local Hash, Clock = GenerateHash();
    local Arguments = {
        [1] = Data.Class,
        [2] = Data.Parent,
        [3] = Hash,
        [4] = Clock,
    }

    local Result = Remotes.CreateObject:InvokeServer(table.unpack(Arguments));

    for Name, Property in next, (Data.Properties or {}) do
        local Arguments = {
            [1] = {
                [1] = Result
            },
            [2] = Name,
            [3] = Property,
        }

        Remotes.ChangeObjectPropertyAndReturn:InvokeServer(table.unpack(Arguments))
    end

    return Result
end

local Copy = function(Target: Instance)
    local FromName = Properties.FromName[Target.ClassName]
    local ClassProperties = FromName and FromName.PropertiesFromName
    
    if ClassProperties then
        local CopyProperties = (function()
            local Properties = {};

            for Property, Data in next, ClassProperties do
                local Default = Data.DefaultValue

                if not table.find(Settings.BlacklistedProperties, Property) then
                    local Success, Result = pcall(function()
                        return Target[Property]
                    end)

                    if (Success) and (Default == nil or Result ~= Default) then
                        print("Setting", Target.Name, "property:", Property);
                        Properties[Property] = Result
                    end
                end
            end

            return Properties
        end)()

        return Create({
            Class = Target.ClassName,
            Parent = workspace,
            Properties = CopyProperties,
        });
    end
end

-- Init
local Old = InsertService:LoadLocalAsset(Settings.ModelId);
local Model = Instance.new("Folder"); Old.Parent = Model

local CreatedInstances = {};
local DescendantsList = Model:GetDescendants();

for Index, Descendant in next, DescendantsList do
    local Created = Copy(Descendant)
    
    Hint.Text = string.format("%d/%d objects created", Index, #DescendantsList);

    if Created then
        print("Object created:", Created);
        CreatedInstances[Descendant] = Created
    end
end

Hint.Text = "Setting parents for the objects (final step)"

for _, Descendant in next, DescendantsList do
    local OriginalParent = Descendant.Parent
    local Created = CreatedInstances[Descendant]
    
    if Created then
        local NewParent = CreatedInstances[OriginalParent] or workspace

        if OriginalParent == Model then
            NewParent = workspace
        end

        print("Setting parent for", Created.Name, ":", NewParent)

        local Arguments = {
            [1] = {
                [1] = Created
            },
            [2] = "Parent",
            [3] = NewParent,
        }

        Remotes.ChangeObjectPropertyAndReturn:InvokeServer(table.unpack(Arguments))
    end
end

Remotes.ChangeHistoryInteractionRequested:FireServer("AddCheckpoint")
Hint.Text = ("Finished building"); task.wait(5);
Hint:Destroy();
Model:Destroy();

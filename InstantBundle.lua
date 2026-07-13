-- // t.me/arceusxcommunity <3
local BUNDLE_INPUT = (getgenv and getgenv().bundle) or (shared and shared.bundle) or (_G and _G.bundle)
local MIX_INPUT    = (getgenv and getgenv().mix)    or (shared and shared.mix)    or (_G and _G.mix)

local Players      = game:GetService("Players")
local AvatarEditor = game:GetService("AvatarEditorService")
local HttpService  = game:GetService("HttpService")
local StarterGui   = game:GetService("StarterGui")

if not game:IsLoaded() then game.Loaded:Wait() end
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

local ENV = (getgenv and getgenv()) or _G
if ENV.__BundleAnimActiveStop then pcall(ENV.__BundleAnimActiveStop); ENV.__BundleAnimActiveStop = nil end

local function log(msg)   print("[BundleAuto] " .. tostring(msg)) end

local hasFS = (typeof(writefile) == "function") and (typeof(readfile) == "function")
local CONFIG_FOLDER    = "BundleAnimations"
local ANIMS_CACHE_PATH = CONFIG_FOLDER .. "/anims_cache.json"

local resolveCache = {}
if hasFS then
    pcall(function()
        if typeof(isfile) == "function" and isfile(ANIMS_CACHE_PATH) then
            local d = HttpService:JSONDecode(readfile(ANIMS_CACHE_PATH))
            if type(d) == "table" then resolveCache = d end
        end
    end)
end
local function saveAnimsCache()
    if not hasFS then return end
    pcall(function()
        if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
            if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
        end
        writefile(ANIMS_CACHE_PATH, HttpService:JSONEncode(resolveCache))
    end)
end
local function isResolved(bundleId)
    return resolveCache[tostring(bundleId)] ~= nil
end

local function parseBundleId(text)
    if not text then return nil end
    text = tostring(text)
    local id = text:match("bundles/(%d+)")
    if not id then id = text:match("(%d%d%d%d+)") end
    if not id then id = text:match("(%d+)") end
    return id and tonumber(id) or nil
end

local detailsCache = {}
local function getBundleDetails(bundleId)
    if detailsCache[bundleId] then return detailsCache[bundleId] end
    local ok, res = pcall(function()
        return AvatarEditor:GetItemDetails(bundleId, Enum.AvatarItemType.Bundle)
    end)
    if ok and res then
        detailsCache[bundleId] = res
        return res
    end
    return nil
end

local ANIM_ASSET_TYPES = {
    IdleAnimation = true, WalkAnimation = true, RunAnimation = true,
    JumpAnimation = true, FallAnimation = true, ClimbAnimation = true, SwimAnimation = true,
}
local RESOLVE_PRIORITY = {
    IdleAnimation = 1, WalkAnimation = 2, RunAnimation = 3,
    JumpAnimation = 4, FallAnimation = 5, ClimbAnimation = 6, SwimAnimation = 7,
}
local ESSENTIAL_TYPES = { IdleAnimation = true, WalkAnimation = true, RunAnimation = true }

local function resolveBundle(bundleId, onProgress, onEssential)
    local key = tostring(bundleId)
    if resolveCache[key] then return resolveCache[key], detailsCache[bundleId] end
    local res = getBundleDetails(bundleId)
    if not res or not res.BundledItems then return nil end

    local jobs = {}
    for _, item in ipairs(res.BundledItems) do
        local at = tostring(item.AssetType)
        if ANIM_ASSET_TYPES[at] and item.Id then
            jobs[#jobs + 1] = { at = at, id = item.Id }
        end
    end
    table.sort(jobs, function(a, b)
        return (RESOLVE_PRIORITY[a.at] or 99) < (RESOLVE_PRIORITY[b.at] or 99)
    end)

    local lastEssential = 0
    for idx, j in ipairs(jobs) do
        if ESSENTIAL_TYPES[j.at] then lastEssential = idx end
    end

    local resolved = {}
    for i, j in ipairs(jobs) do
        local ok, objs = pcall(function()
            return game:GetObjects("rbxassetid://" .. j.id)
        end)
        if ok and objs then
            local inner = {}
            for _, o in ipairs(objs) do
                for _, c in ipairs(o:GetDescendants()) do
                    if c:IsA("Animation") then inner[c.Name] = c.AnimationId end
                end
            end
            if next(inner) then resolved[j.at] = inner end
        end
        if onProgress then pcall(onProgress, i, #jobs) end
        if i == lastEssential and onEssential and next(resolved) then
            pcall(onEssential, resolved)
        end
        task.wait()
    end
    if next(resolved) then
        resolveCache[key] = resolved
        saveAnimsCache()
        return resolved, res
    end
    return nil, res
end

local ctrl = { token = 0, conns = {}, tracks = {}, current = nil, pose = "Standing" }
local lastBundle
local lastMix

local function stopController()
    ctrl.token += 1
    for _, c in ipairs(ctrl.conns) do pcall(function() c:Disconnect() end) end
    ctrl.conns = {}
    for _, t in pairs(ctrl.tracks) do pcall(function() t:Stop(0) end) end
    ctrl.tracks = {}
    ctrl.current = nil
end

local function pickId(resolved, assetType, prefName)
    local inner = resolved[assetType]
    if not inner then return nil end
    local id = prefName and inner[prefName]
    if not id then for _, v in pairs(inner) do id = v; break end end
    return id
end

local function makeTrack(animator, id, priority, looped)
    if not id then return nil end
    local num = tostring(id):match("%d+")
    if not num or num == "0" then return nil end
    local a = Instance.new("Animation")
    a.AnimationId = "rbxassetid://" .. num
    local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
    if not ok or not tr then return nil end
    tr.Looped = (looped ~= false)
    tr.Priority = priority or Enum.AnimationPriority.Core
    return tr
end

local function buildController(char, resolved)
    stopController()
    local myToken = ctrl.token
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return false end

    local animate = char:FindFirstChild("Animate")
    if animate then animate.Disabled = true end
    for _, t in ipairs(animator:GetPlayingAnimationTracks()) do pcall(function() t:Stop(0) end) end

    local P = Enum.AnimationPriority
    local T = {
        idle     = makeTrack(animator, pickId(resolved, "IdleAnimation", "Animation1"), P.Idle),
        walk     = makeTrack(animator, pickId(resolved, "WalkAnimation"),  P.Movement),
        run      = makeTrack(animator, pickId(resolved, "RunAnimation"),   P.Movement),
        jump     = makeTrack(animator, pickId(resolved, "JumpAnimation"),  P.Action, false),
        fall     = makeTrack(animator, pickId(resolved, "FallAnimation"),  P.Action),
        climb    = makeTrack(animator, pickId(resolved, "ClimbAnimation"), P.Movement),
        swim     = makeTrack(animator, pickId(resolved, "SwimAnimation", "Swim"),     P.Movement),
        swimidle = makeTrack(animator, pickId(resolved, "SwimAnimation", "SwimIdle"), P.Idle),
    }
    ctrl.tracks = T

    local REF = 16

    local function play(track, fade, speed)
        if not track then return end
        if ctrl.current ~= track then
            if ctrl.current then pcall(function() ctrl.current:Stop(fade or 0.15) end) end
            ctrl.current = track
            pcall(function() track:Play(fade or 0.15) end)
        end
        if speed then pcall(function() track:AdjustSpeed(speed) end) end
    end

    local emoteTrack
    local function stopEmote(fade)
        if emoteTrack then
            local e = emoteTrack; emoteTrack = nil
            pcall(function() e:Stop(fade or 0.2) end)
        end
    end

    local function planarSpeed()
        local root = hum.RootPart
        if not root then return 0 end
        local v = root.AssemblyLinearVelocity
        return Vector3.new(v.X, 0, v.Z).Magnitude
    end

    local function onRunning(speed)
        if myToken ~= ctrl.token then return end
        if speed > 0.5 then
            if emoteTrack then stopEmote(0.1) end
            ctrl.pose = "Running"
            local mv = (speed > 9 and T.run) or T.walk or T.run
            play(mv, 0.15, speed / REF)
        elseif emoteTrack then
            return
        elseif ctrl.pose ~= "Jumping" and ctrl.pose ~= "FreeFall" then
            ctrl.pose = "Standing"
            play(T.idle, 0.2, 1)
        end
    end

    local function onJump()
        if myToken ~= ctrl.token then return end
        stopEmote(0.1)
        ctrl.pose = "Jumping"; play(T.jump or T.fall, 0.1, 1)
    end
    local function onFall(active)
        if myToken ~= ctrl.token then return end
        if active then
            stopEmote(0.1)
            ctrl.pose = "FreeFall"; play(T.fall or T.jump, 0.25, 1)
        else
            ctrl.pose = "Landed"
            onRunning(planarSpeed())
        end
    end
    local function onClimb(speed)
        if myToken ~= ctrl.token then return end
        stopEmote(0.1)
        ctrl.pose = "Climbing"
        play(T.climb, 0.15, speed / 5)
    end
    local function onSwim(speed)
        if myToken ~= ctrl.token then return end
        ctrl.pose = "Swimming"
        if math.abs(speed or 0) > 1 then play(T.swim, 0.2, 1) else play(T.swimidle or T.swim, 0.2, 1) end
    end

    local function emotePlayableId(raw)
        local id
        if typeof(raw) == "Instance" and raw:IsA("Animation") then
            id = raw.AnimationId:match("%d+")
        elseif type(raw) == "string" and animate and not tonumber(raw) then
            local f = animate:FindFirstChild(raw)
            if f then local a = f:FindFirstChildOfClass("Animation"); if a then return a.AnimationId:match("%d+") end end
            return nil
        elseif tonumber(raw) then
            id = tostring(tonumber(raw))
        end
        if not id then return nil end
        local ekey = "e" .. id
        if resolveCache[ekey] then return resolveCache[ekey] end
        local good = false
        local test = Instance.new("Animation"); test.AnimationId = "rbxassetid://" .. id
        local ok, tr = pcall(function() return animator:LoadAnimation(test) end)
        if ok and tr then
            for _ = 1, 8 do if tr.Length > 0 then good = true break end task.wait(0.05) end
            pcall(function() tr:Destroy() end)
        end
        if good then resolveCache[ekey] = id; return id end
        local ok2, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
        if ok2 and objs then
            for _, o in ipairs(objs) do for _, c in ipairs(o:GetDescendants()) do
                if c:IsA("Animation") then
                    local rid = c.AnimationId:match("%d+")
                    if rid then resolveCache[ekey] = rid; saveAnimsCache(); return rid end
                end
            end end
        end
        return id
    end

    local function playEmote(raw)
        local id = emotePlayableId(raw)
        if not id then return false end
        stopEmote(0)
        local a = Instance.new("Animation"); a.AnimationId = "rbxassetid://" .. id
        local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
        if not ok or not tr then return false end
        tr.Priority = Enum.AnimationPriority.Action4
        emoteTrack = tr
        if ctrl.current then pcall(function() ctrl.current:Stop(0.15) end) end
        ctrl.current = nil; ctrl.pose = "Emote"
        pcall(function() tr:Play(0.1) end)
        tr.Stopped:Once(function()
            if emoteTrack == tr then
                emoteTrack = nil
                if myToken == ctrl.token then onRunning(planarSpeed()) end
            end
        end)
        return true
    end
    ctrl.playEmote = playEmote

    if animate then
        local bf = animate:FindFirstChild("PlayEmote")
        if bf and bf:IsA("BindableFunction") then
            pcall(function() bf.OnInvoke = function(emote) return playEmote(emote) end end)
        end
    end

    table.insert(ctrl.conns, hum.Running:Connect(onRunning))
    table.insert(ctrl.conns, hum.Jumping:Connect(onJump))
    table.insert(ctrl.conns, hum.FreeFalling:Connect(onFall))
    table.insert(ctrl.conns, hum.Climbing:Connect(onClimb))
    table.insert(ctrl.conns, hum.Swimming:Connect(onSwim))
    table.insert(ctrl.conns, hum.Seated:Connect(function(active) if not active then onRunning(0) end end))
    table.insert(ctrl.conns, hum.StateChanged:Connect(function(_, new)
        if myToken ~= ctrl.token then return end
        if new == Enum.HumanoidStateType.Landed
        or new == Enum.HumanoidStateType.Running
        or new == Enum.HumanoidStateType.RunningNoPhysics then
            if ctrl.pose == "Jumping" or ctrl.pose == "FreeFall" then
                ctrl.pose = "Landed"
                onRunning(planarSpeed())
            end
        end
    end))

    play(T.idle, 0.2, 1)

    task.spawn(function()
        while myToken == ctrl.token do
            if animate and not animate.Disabled then animate.Disabled = true end
            local cur = ctrl.current
            if cur and cur.Looped and not cur.IsPlaying then pcall(function() cur:Play(0.1) end) end
            task.wait(0.4)
        end
    end)
    return true
end

local function applyBundle(bundleId, onProgress)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChildOfClass("Humanoid") then
        return false, "No character"
    end
    local resolved, res = resolveBundle(bundleId, onProgress, function(partial)
        buildController(char, partial)
    end)
    if not resolved then
        return false, "Failed to load bundle animations (ID: " .. tostring(bundleId) .. ")"
    end
    if not buildController(char, resolved) then
        return false, "Couldn't apply (no Animator)"
    end
    lastBundle = tostring(bundleId)
    lastMix = nil
    return true, "Applied (visible to all): " .. ((res and res.Name) or ("ID " .. bundleId))
end

local MIX_SLOTS = { "IdleAnimation", "WalkAnimation", "RunAnimation", "JumpAnimation",
                    "FallAnimation", "ClimbAnimation", "SwimAnimation" }
local ANIMATE_TO_ASSET = {
    idle = "IdleAnimation", walk = "WalkAnimation", run = "RunAnimation",
    jump = "JumpAnimation", fall = "FallAnimation", climb = "ClimbAnimation",
    swim = "SwimAnimation", swimidle = "SwimAnimation",
}
local function readDefaultResolved(char)
    local out = {}
    local animate = char and char:FindFirstChild("Animate")
    if not animate then return out end
    for _, grp in ipairs(animate:GetChildren()) do
        local at = ANIMATE_TO_ASSET[string.lower(grp.Name)]
        if at then
            for _, a in ipairs(grp:GetChildren()) do
                if a:IsA("Animation") then
                    local num = tostring(a.AnimationId):match("%d+")
                    if num and num ~= "0" then
                        out[at] = out[at] or {}
                        out[at][a.Name] = a.AnimationId
                    end
                end
            end
        end
    end
    return out
end
local function applyMix(mixSpec, onProgress)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChildOfClass("Humanoid") then
        return false, "No character"
    end
    local combined = readDefaultResolved(char)
    local byBundle = {}
    for _, key in ipairs(MIX_SLOTS) do
        local raw = mixSpec[key]
        if type(raw) == "table" then raw = raw.id end
        local bid = raw and parseBundleId(raw)
        if bid then
            if byBundle[bid] == nil then
                if onProgress then pcall(onProgress, "Loading bundle " .. bid .. "…") end
                byBundle[bid] = resolveBundle(bid) or false
            end
            local r = byBundle[bid]
            if r and r[key] then combined[key] = r[key] end
        end
    end
    if not next(combined) then
        return false, "Mix had no usable animations"
    end
    if not buildController(char, combined) then
        return false, "Couldn't apply (no Animator)"
    end
    lastMix = mixSpec
    lastBundle = nil
    return true, "Applied mix (visible to all)"
end

local charConn = LocalPlayer.CharacterAdded:Connect(function(char)
    char:WaitForChild("Humanoid")
    task.wait(1)
    if lastMix then
        applyMix(lastMix)
    elseif lastBundle then
        applyBundle(tonumber(lastBundle))
    end
end)

ENV.__BundleAnimActiveStop = function()
    stopController()
    if charConn then pcall(function() charConn:Disconnect() end); charConn = nil end
    local ch = LocalPlayer.Character
    local an = ch and ch:FindFirstChild("Animate")
    if an then pcall(function() an.Disabled = false end) end
    ENV.__BundleAnimActiveStop = nil
end

local hasMix = (type(MIX_INPUT) == "table" and next(MIX_INPUT) ~= nil)
local bundleId = parseBundleId(BUNDLE_INPUT)

if not hasMix and not bundleId then
    log('Nothing set. Use  getgenv().bundle = "<ID or link>"  or  getgenv().mix = { IdleAnimation = "id", WalkAnimation = "id", ... }')
    return
end

local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
char:WaitForChild("Humanoid")

if hasMix then
    log("Applying mix combo…")
    local ok, msg = applyMix(MIX_INPUT, function(m) log(m) end)
    log(msg)
    return
end

local firstTime = not isResolved(bundleId)
if firstTime then
    log("First load — downloading animations (brief lag; instant next time)…")
end

local ok, msg = applyBundle(bundleId, firstTime and function(done, total)
    log(("Loading animations… %d/%d"):format(done, total))
end or nil)

log(msg)

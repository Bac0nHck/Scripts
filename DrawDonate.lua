local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local UIS         = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local AssetService= game:GetService("AssetService")
local httpreq     = request or http_request or (syn and syn.request) or (http and http.request)

local guiParent   = (gethui and gethui()) or (protectgui and (function() local s=Instance.new("ScreenGui") protectgui(s) s.Parent=game:GetService("CoreGui") return s end)) or game:GetService("CoreGui")

local function elevate()
    pcall(function()
        if setthreadidentity then setthreadidentity(8)
        elseif setidentity then setidentity(8)
        elseif syn and syn.set_thread_identity then syn.set_thread_identity(8) end
    end)
end

local band, lshift, rshift = bit32.band, bit32.lshift, bit32.rshift
local LEN_BASE ={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local LEN_EXTRA={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local DIST_BASE ={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local DIST_EXTRA={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local CLC_ORDER ={17,18,19,1,9,8,10,7,11,6,12,5,13,4,14,3,15,2,16}

local function inflate(data, startPos)
    local pos = startPos or 1
    local bitbuf, bitcnt = 0, 0
    local function getbit()
        if bitcnt == 0 then bitbuf = string.byte(data, pos) or 0; pos = pos + 1; bitcnt = 8 end
        local b = band(bitbuf, 1); bitbuf = rshift(bitbuf, 1); bitcnt = bitcnt - 1; return b
    end
    local function getbits(n) local v = 0 for i = 0, n-1 do v = v + lshift(getbit(), i) end return v end
    local function buildHuff(lengths, n)
        local mb = 0
        for i = 0, n-1 do local l = lengths[i]; if l > mb then mb = l end end
        local bl = {} for i = 0, mb do bl[i] = 0 end
        for i = 0, n-1 do local l = lengths[i]; if l > 0 then bl[l] = bl[l] + 1 end end
        local nc, code = {}, 0
        for b = 1, mb do code = (code + (bl[b-1] or 0)) * 2; nc[b] = code end
        local tb = {} for i = 1, mb do tb[i] = {} end
        for s = 0, n-1 do local l = lengths[s]; if l > 0 then tb[l][nc[l]] = s; nc[l] = nc[l] + 1 end end
        return { t = tb, mb = mb }
    end
    local function decode(h)
        local code = 0
        for len = 1, h.mb do code = code * 2 + getbit(); local s = h.t[len][code]; if s ~= nil then return s end end
        error("bad huffman")
    end
    local out, outn = {}, 0
    while true do
        local bfinal = getbit()
        local btype  = getbits(2)
        if btype == 0 then
            bitbuf, bitcnt = 0, 0
            local len = (string.byte(data, pos) or 0) + (string.byte(data, pos+1) or 0) * 256
            pos = pos + 4
            for _ = 1, len do outn = outn + 1; out[outn] = string.byte(data, pos) or 0; pos = pos + 1 end
        elseif btype == 1 or btype == 2 then
            local litH, distH
            if btype == 1 then
                local ll = {} for i = 0,143 do ll[i]=8 end for i = 144,255 do ll[i]=9 end for i = 256,279 do ll[i]=7 end for i = 280,287 do ll[i]=8 end
                litH = buildHuff(ll, 288)
                local dl = {} for i = 0,29 do dl[i]=5 end distH = buildHuff(dl, 30)
            else
                local hlit  = getbits(5) + 257
                local hdist = getbits(5) + 1
                local hclen = getbits(4) + 4
                local clen = {} for i = 0,18 do clen[i]=0 end
                for i = 1, hclen do clen[CLC_ORDER[i]-1] = getbits(3) end
                local clH = buildHuff(clen, 19)
                local lens, total, idx = {}, hlit + hdist, 0
                while idx < total do
                    local sym = decode(clH)
                    if sym < 16 then lens[idx] = sym; idx = idx + 1
                    elseif sym == 16 then local rep = getbits(2)+3 local p = lens[idx-1] for _=1,rep do lens[idx]=p; idx=idx+1 end
                    elseif sym == 17 then local rep = getbits(3)+3 for _=1,rep do lens[idx]=0; idx=idx+1 end
                    else local rep = getbits(7)+11 for _=1,rep do lens[idx]=0; idx=idx+1 end end
                end
                local litL = {} for i = 0,hlit-1 do litL[i] = lens[i] or 0 end
                local distL = {} for i = 0,hdist-1 do distL[i] = lens[hlit+i] or 0 end
                litH = buildHuff(litL, hlit); distH = buildHuff(distL, hdist)
            end
            while true do
                local sym = decode(litH)
                if sym == 256 then break
                elseif sym < 256 then outn = outn + 1; out[outn] = sym
                else
                    local li = sym - 256
                    local length = LEN_BASE[li] + getbits(LEN_EXTRA[li])
                    local dsym = decode(distH)
                    local dist = DIST_BASE[dsym+1] + getbits(DIST_EXTRA[dsym+1])
                    local st = outn - dist
                    for i = 1, length do outn = outn + 1; out[outn] = out[st + i] end
                end
            end
        else error("bad btype") end
        if bfinal == 1 then break end
    end
    return out
end

local function decodePNG(body)
    local pos, width, height, colortype, idat = 9, nil, nil, nil, {}
    while pos <= #body do
        local len = string.byte(body,pos)*16777216 + string.byte(body,pos+1)*65536 + string.byte(body,pos+2)*256 + string.byte(body,pos+3)
        local typ = string.sub(body, pos+4, pos+7)
        local dstart = pos + 8
        if typ == "IHDR" then
            width  = string.byte(body,dstart)*16777216 + string.byte(body,dstart+1)*65536 + string.byte(body,dstart+2)*256 + string.byte(body,dstart+3)
            height = string.byte(body,dstart+4)*16777216 + string.byte(body,dstart+5)*65536 + string.byte(body,dstart+6)*256 + string.byte(body,dstart+7)
            colortype = string.byte(body, dstart+9)
        elseif typ == "IDAT" then idat[#idat+1] = string.sub(body, dstart, dstart+len-1)
        elseif typ == "IEND" then break end
        pos = dstart + len + 4
    end
    local raw = inflate(table.concat(idat), 3)
    local ch = (colortype == 2 and 3) or (colortype == 6 and 4) or (colortype == 0 and 1) or 3
    local stride = width * ch
    local buf = buffer.create(width * height * 4)
    local prev = {} for i = 0, stride-1 do prev[i] = 0 end
    local rp = 1
    for y = 0, height-1 do
        local ft, cur = raw[rp], {}; rp = rp + 1
        for x = 0, stride-1 do
            local rb = raw[rp]; rp = rp + 1
            local a = (x >= ch) and cur[x-ch] or 0
            local b = prev[x]
            local c = (x >= ch) and prev[x-ch] or 0
            local val
            if ft == 0 then val = rb
            elseif ft == 1 then val = (rb + a) % 256
            elseif ft == 2 then val = (rb + b) % 256
            elseif ft == 3 then val = (rb + math.floor((a+b)/2)) % 256
            else
                local p = a + b - c
                local pa, pb, pc = math.abs(p-a), math.abs(p-b), math.abs(p-c)
                val = (rb + ((pa <= pb and pa <= pc) and a or (pb <= pc and b or c))) % 256
            end
            cur[x] = val
        end
        for x = 0, width-1 do
            local o = (y*width + x) * 4
            local r, g, bl, al
            if ch == 3 then r = cur[x*3]; g = cur[x*3+1]; bl = cur[x*3+2]; al = 255
            elseif ch == 4 then r = cur[x*4]; g = cur[x*4+1]; bl = cur[x*4+2]; al = cur[x*4+3]
            else r = cur[x]; g = r; bl = r; al = 255 end
            buffer.writeu8(buf, o, r); buffer.writeu8(buf, o+1, g); buffer.writeu8(buf, o+2, bl); buffer.writeu8(buf, o+3, al)
        end
        prev = cur
    end
    return width, height, buf
end

local function fetchDecoded(url, w, h, fit)
    local fitParam = (fit == "contain") and "&fit=contain&bg=white" or "&fit=cover"
    local full = "https://images.weserv.nl/?url=" .. HttpService:UrlEncode(url)
               .. "&w=" .. w .. "&h=" .. h .. fitParam .. "&output=png"
    local ok, body = pcall(function() return httpreq({ Url = full, Method = "GET" }).Body end)
    if not ok or not body or #body < 8 or string.byte(body, 1) ~= 137 then return nil, "download failed" end
    local okd, iw, ih, buf = pcall(decodePNG, body)
    if not okd then return nil, "decode failed" end
    return { w = iw, h = ih, buf = buf }
end

local function newEditableImage(w, h)
    local ok, ei = pcall(function() return AssetService:CreateEditableImage(Vector2.new(w, h)) end)
    if ok and ei then return ei end
    ok, ei = pcall(function() return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) }) end)
    if ok and ei then return ei end
    ok, ei = pcall(function() local e = AssetService:CreateEditableImage(); e:Resize(Vector2.new(w, h)); return e end)
    if ok and ei then return ei end
    return nil
end

local function getLayers()
    local ls = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("guiAssets")
                 and RS.Assets.guiAssets:FindFirstChild("LoadSlot")
    if ls then
        for _, c in ipairs(getconnections(ls.Event)) do
            local ok, ups = pcall(getupvalues, c.Function)
            if ok and ups then
                for _, u in pairs(ups) do
                    if type(u) == "table" and type(u[1]) == "table" and rawget(u[1], "InternalCanvas") then return u end
                end
            end
        end
    end
    local frame = Players.LocalPlayer.PlayerGui:FindFirstChild("MainGameUI")
    frame = frame and frame:FindFirstChild("CanvasFrame") and frame.CanvasFrame:FindFirstChild("WhiteFrame")
    if frame then
        local t = {}
        for _, o in ipairs(getgc(true)) do
            if type(o) == "table" and rawget(o, "InternalCanvas") and rawget(o, "CurrentCanvasFrame") == frame then t[#t+1] = o end
        end
        if #t > 0 then return t end
    end
    return nil
end

local old = guiParent:FindFirstChild("DD_AutoDrawHud")
if old then old:Destroy() end

local function corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p; return c end
local function pad(p, n) local u = Instance.new("UIPadding"); u.PaddingTop=UDim.new(0,n); u.PaddingBottom=UDim.new(0,n); u.PaddingLeft=UDim.new(0,n); u.PaddingRight=UDim.new(0,n); u.Parent=p; return u end

local BG, PANEL, ACCENT, TEXT = Color3.fromRGB(24,26,33), Color3.fromRGB(36,39,48), Color3.fromRGB(254,157,43), Color3.fromRGB(235,238,245)

local screen = Instance.new("ScreenGui")
screen.Name = "DD_AutoDrawHud"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder = 9999
screen.Parent = guiParent

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(320, 440)
main.AnchorPoint = Vector2.new(0, 0.5)
main.Position = UDim2.new(0, 14, 0.5, 0)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = screen
corner(main, 12)
local stroke = Instance.new("UIStroke"); stroke.Color = ACCENT; stroke.Thickness = 1.5; stroke.Transparency = 0.4; stroke.Parent = main

local uiScale = Instance.new("UIScale"); uiScale.Parent = main
local floatScale
local function updateScale()
    elevate()
    local cam = workspace.CurrentCamera
    local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
    local s = math.clamp(math.min(vp.X * 0.92 / 320, vp.Y * 0.92 / 440), 0.55, 1.15)
    uiScale.Scale = s
    if floatScale then floatScale.Scale = math.clamp(s, 0.75, 1.3) end
end

local title = Instance.new("Frame")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundColor3 = PANEL
title.BorderSizePixel = 0
title.Active = true
title.Parent = main
corner(title, 12)
local titleFix = Instance.new("Frame"); titleFix.Size = UDim2.new(1,0,0,14); titleFix.Position = UDim2.new(0,0,1,-14); titleFix.BackgroundColor3 = PANEL; titleFix.BorderSizePixel = 0; titleFix.Parent = title

local titleText = Instance.new("TextLabel")
titleText.BackgroundTransparency = 1
titleText.Size = UDim2.new(1, -50, 1, 0)
titleText.Position = UDim2.fromOffset(14, 0)
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 15
titleText.TextColor3 = TEXT
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.Text = "🎨 Auto Draw"
titleText.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(200,60,60)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.Parent = title
corner(closeBtn, 6)

local previewBox = Instance.new("Frame")
previewBox.Size = UDim2.fromOffset(288, 236)
previewBox.Position = UDim2.fromOffset(16, 50)
previewBox.BackgroundColor3 = Color3.fromRGB(255,255,255)
previewBox.BorderSizePixel = 0
previewBox.Parent = main
corner(previewBox, 8)
local pStroke = Instance.new("UIStroke"); pStroke.Color = PANEL; pStroke.Thickness = 2; pStroke.Parent = previewBox

local previewImg = Instance.new("ImageLabel")
previewImg.Size = UDim2.fromScale(1, 1)
previewImg.BackgroundTransparency = 1
previewImg.ScaleType = Enum.ScaleType.Stretch
previewImg.Parent = previewBox
corner(previewImg, 8)

local previewHint = Instance.new("TextLabel")
previewHint.BackgroundTransparency = 1
previewHint.Size = UDim2.fromScale(1, 1)
previewHint.Font = Enum.Font.GothamMedium
previewHint.TextSize = 14
previewHint.TextColor3 = Color3.fromRGB(150,150,150)
previewHint.Text = "Preview will appear here"
previewHint.Parent = previewBox

local urlBox = Instance.new("TextBox")
urlBox.Size = UDim2.fromOffset(288, 34)
urlBox.Position = UDim2.fromOffset(16, 296)
urlBox.BackgroundColor3 = PANEL
urlBox.BorderSizePixel = 0
urlBox.Font = Enum.Font.Gotham
urlBox.TextSize = 13
urlBox.TextColor3 = TEXT
urlBox.PlaceholderText = "Paste image URL here..."
urlBox.PlaceholderColor3 = Color3.fromRGB(130,134,145)
urlBox.Text = ""
urlBox.ClearTextOnFocus = false
urlBox.TextXAlignment = Enum.TextXAlignment.Left
urlBox.TextTruncate = Enum.TextTruncate.AtEnd
urlBox.Parent = main
corner(urlBox, 8)
pad(urlBox, 8)

local fitBtn = Instance.new("TextButton")
fitBtn.Size = UDim2.fromOffset(90, 34)
fitBtn.Position = UDim2.fromOffset(16, 340)
fitBtn.BackgroundColor3 = PANEL
fitBtn.Font = Enum.Font.GothamMedium
fitBtn.TextSize = 13
fitBtn.TextColor3 = TEXT
fitBtn.Text = "Fit: Cover"
fitBtn.Parent = main
corner(fitBtn, 8)

local previewBtn = Instance.new("TextButton")
previewBtn.Size = UDim2.fromOffset(90, 34)
previewBtn.Position = UDim2.fromOffset(114, 340)
previewBtn.BackgroundColor3 = PANEL
previewBtn.Font = Enum.Font.GothamBold
previewBtn.TextSize = 13
previewBtn.TextColor3 = TEXT
previewBtn.Text = "Preview"
previewBtn.Parent = main
corner(previewBtn, 8)

local drawBtn = Instance.new("TextButton")
drawBtn.Size = UDim2.fromOffset(92, 34)
drawBtn.Position = UDim2.fromOffset(212, 340)
drawBtn.BackgroundColor3 = ACCENT
drawBtn.Font = Enum.Font.GothamBold
drawBtn.TextSize = 14
drawBtn.TextColor3 = Color3.fromRGB(20,20,20)
drawBtn.Text = "Draw"
drawBtn.Parent = main
corner(drawBtn, 8)

local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(288, 40)
status.Position = UDim2.fromOffset(16, 386)
status.BackgroundColor3 = PANEL
status.BorderSizePixel = 0
status.Font = Enum.Font.GothamMedium
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(180,184,195)
status.Text = "Ready. Open the easel editor (E), paste a URL."
status.TextWrapped = true
status.Parent = main
corner(status, 8)

local fitMode = "cover"
local busy = false
local function setStatus(txt, color) elevate(); status.Text = txt; status.TextColor3 = color or Color3.fromRGB(180,184,195) end

fitBtn.MouseButton1Click:Connect(function()
    elevate()
    fitMode = (fitMode == "cover") and "contain" or "cover"
    fitBtn.Text = "Fit: " .. (fitMode == "cover" and "Cover" or "Contain")
end)

local function doPreview()
    elevate()
    if busy then return end
    local url = urlBox.Text
    if url == "" then setStatus("Enter an image URL first.", Color3.fromRGB(230,170,80)); return end
    busy = true
    task.spawn(function()
        elevate()
        setStatus("Loading preview...")
        local data, err = fetchDecoded(url, 288, 236, fitMode)
        elevate()
        if not data then setStatus("Preview error: " .. tostring(err), Color3.fromRGB(230,110,110)); busy = false; return end
        local ei = newEditableImage(data.w, data.h)
        if not ei then setStatus("EditableImage not supported.", Color3.fromRGB(230,110,110)); busy = false; return end
        ei:WritePixelsBuffer(Vector2.zero, Vector2.new(data.w, data.h), data.buf)
        previewImg.ImageContent = Content.fromObject(ei)
        previewHint.Visible = false
        setStatus("Preview ready. Press Draw to paint it.", Color3.fromRGB(120,200,130))
        busy = false
    end)
end

local function doDraw()
    elevate()
    if busy then return end
    local url = urlBox.Text
    if url == "" then setStatus("Enter an image URL first.", Color3.fromRGB(230,170,80)); return end
    local layers = getLayers()
    if not layers then setStatus("Canvas not found. Open the easel editor (E).", Color3.fromRGB(230,170,80)); return end
    busy = true
    task.spawn(function()
        elevate()
        local resX, resY = layers[1].CurrentResX, layers[1].CurrentResY
        setStatus("Drawing (" .. resX .. "x" .. resY .. ")...")
        local data, err = fetchDecoded(url, resX, resY, fitMode)
        elevate()
        if not data then setStatus("Draw error: " .. tostring(err), Color3.fromRGB(230,110,110)); busy = false; return end
        local CanvasDraw = require(game.ReplicatedFirst:WaitForChild("CanvasDraw"))
        elevate()
        local img = CanvasDraw.CreateBlankImageData(data.w, data.h)
        img.ImageBuffer = data.buf
        layers[1]:SetBufferFromImage(img); layers[1]:Render()
        if #layers > 1 then
            local tbuf = buffer.create(data.w * data.h * 4)
            for i = 2, #layers do
                local ti = CanvasDraw.CreateBlankImageData(data.w, data.h)
                ti.ImageBuffer = tbuf
                layers[i]:SetBufferFromImage(ti); layers[i]:Render()
            end
        end
        local MGE = RS:FindFirstChild("MainGameEvents")
        if MGE and MGE:FindFirstChild("NotifyNormalOperation") then MGE.NotifyNormalOperation:FireServer("load_saved_art") end
        setStatus("Done! The game replicates & auto-saves it.", Color3.fromRGB(120,200,130))
        busy = false
    end)
end

previewBtn.MouseButton1Click:Connect(doPreview)
drawBtn.MouseButton1Click:Connect(doDraw)
urlBox.FocusLost:Connect(function(enter) if enter then doPreview() end end)

local floatBtn = Instance.new("TextButton")
floatBtn.Name = "FloatToggle"
floatBtn.Size = UDim2.fromOffset(58, 58)
floatBtn.AnchorPoint = Vector2.new(0, 0.5)
floatBtn.Position = UDim2.new(0, 16, 0.7, 0)
floatBtn.BackgroundColor3 = ACCENT
floatBtn.Text = "🎨"
floatBtn.TextSize = 26
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextColor3 = Color3.fromRGB(20,20,20)
floatBtn.AutoButtonColor = false
floatBtn.Visible = false
floatBtn.Active = true
floatBtn.Parent = screen
corner(floatBtn, 28)
local fStroke = Instance.new("UIStroke"); fStroke.Color = Color3.new(0,0,0); fStroke.Thickness = 2; fStroke.Transparency = 0.55; fStroke.Parent = floatBtn
floatScale = Instance.new("UIScale"); floatScale.Parent = floatBtn

closeBtn.MouseButton1Click:Connect(function() elevate(); main.Visible = false; floatBtn.Visible = true end)

local function makeDraggable(handle, target, onTap)
    local dragging, startInput, startPos, moved = false, nil, nil, false
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            elevate()
            dragging, startInput, startPos, moved = true, input.Position, target.Position, false
            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if conn then conn:Disconnect() end
                    if onTap and not moved then onTap() end
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - startInput
            if math.abs(d.X) + math.abs(d.Y) > 6 then moved = true end
            elevate()
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

makeDraggable(title, main)

do
    local fDragging, fStart, fStartPos, fMoved = false, nil, nil, false
    floatBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            elevate(); fDragging, fStart, fStartPos, fMoved = true, input.Position, floatBtn.Position, false
            local conn; conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then fDragging = false; if conn then conn:Disconnect() end end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if fDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - fStart
            if math.abs(d.X) + math.abs(d.Y) > 6 then fMoved = true end
            elevate(); floatBtn.Position = UDim2.new(fStartPos.X.Scale, fStartPos.X.Offset + d.X, fStartPos.Y.Scale, fStartPos.Y.Offset + d.Y)
        end
    end)
    floatBtn.MouseButton1Click:Connect(function()
        if fMoved then fMoved = false; return end
        elevate(); main.Visible = true; floatBtn.Visible = false
    end)
end

local function hover(btn, base, hi)
    btn.MouseEnter:Connect(function() elevate(); btn.BackgroundColor3 = hi end)
    btn.MouseLeave:Connect(function() elevate(); btn.BackgroundColor3 = base end)
end
hover(previewBtn, PANEL, Color3.fromRGB(52,56,68))
hover(fitBtn, PANEL, Color3.fromRGB(52,56,68))
hover(drawBtn, ACCENT, Color3.fromRGB(255,180,80))
hover(closeBtn, Color3.fromRGB(200,60,60), Color3.fromRGB(230,80,80))

updateScale()
do
    local cam = workspace.CurrentCamera
    if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local c = workspace.CurrentCamera
        if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale); updateScale() end
    end)
end

if not getLayers() then
    setStatus("Tip: open the easel editor (E) so Draw can find your canvas.", Color3.fromRGB(230,170,80))
end
print("[AutoDraw HUD] loaded in " .. guiParent.Name)

-- https://scriptblox.com/script/starving-artists-(DONATION-GAME)-Auto-Draw-Script-37948
warn([[.
  _                        __                                             _       _       
 | |                      / /                                            (_)     | |      
 | |_   _ __ ___   ___   / /_ _ _ __ ___ ___ _   _ _____  _____  ___ _ __ _ _ __ | |_ ___ 
 | __| | '_ ` _ \ / _ \ / / _` | '__/ __/ _ \ | | / __\ \/ / __|/ __| '__| | '_ \| __/ __|
 | |_ _| | | | | |  __// / (_| | | | (_|  __/ |_| \__ \>  <\__ \ (__| |  | | |_) | |_\__ \
  \__(_)_| |_| |_|\___/_/ \__,_|_|  \___\___|\__,_|___/_/\_\___/\___|_|  |_| .__/ \__|___/
                                                                           | |            
                                                                           |_|            
]])
local screen = Instance.new("ScreenGui")
screen.Parent = game:GetService("CoreGui")
local mainFrameClosed = false
local currentDrawing = {}
local currentPixel = 0
local drawingPaused = false
local drawingFinished = true
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 700, 0, 350)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.Style = 6
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screen
local mainFrameLayout = Instance.new("UIListLayout")
mainFrameLayout.SortOrder = Enum.SortOrder.LayoutOrder
mainFrameLayout.Parent = mainFrame
local headerFrame = Instance.new("Frame")
headerFrame.Size = UDim2.new(1, 0, 0, 40)
headerFrame.LayoutOrder = 1
headerFrame.Style = 6
headerFrame.Parent = mainFrame
local headerFrameLayout = Instance.new("UIListLayout")
headerFrameLayout.FillDirection = Enum.FillDirection.Horizontal
headerFrameLayout.SortOrder = Enum.SortOrder.LayoutOrder
headerFrameLayout.VerticalAlignment = Enum.VerticalAlignment.Center
headerFrameLayout.Parent = headerFrame
local headerFrameTitle = Instance.new("Frame")
headerFrameTitle.Size = UDim2.new(0.5, 0, 1, 0)
headerFrameTitle.BackgroundTransparency = 1
headerFrameTitle.Parent = headerFrame
local headerFrameTitleLayout = Instance.new("UIListLayout")
headerFrameTitleLayout.FillDirection = Enum.FillDirection.Horizontal
headerFrameTitleLayout.SortOrder = Enum.SortOrder.LayoutOrder
headerFrameTitleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
headerFrameTitleLayout.Parent = headerFrameTitle
local headerTitle = Instance.new("TextLabel")
headerTitle.Text = "Starving Artists Script"
headerTitle.Size = UDim2.new(0, 0, 1, 0)
headerTitle.AutomaticSize = Enum.AutomaticSize.X
headerTitle.TextColor3 = Color3.fromHex("FFFFFF")
headerTitle.TextTransparency = 0.3
headerTitle.BackgroundColor3 = Color3.fromHex("000000")
headerTitle.BackgroundTransparency = 0.7
headerTitle.BorderSizePixel = 0
headerTitle.Parent = headerFrameTitle
local headerTitlePadding = Instance.new("UIPadding")
headerTitlePadding.PaddingLeft = UDim.new(0, 7)
headerTitlePadding.PaddingRight = UDim.new(0, 7)
headerTitlePadding.Parent = headerTitle
local headerTitleCorner = Instance.new("UICorner")
headerTitleCorner.CornerRadius = UDim.new(0, 3)
headerTitleCorner.Parent = headerTitle
local headerDescription = Instance.new("TextLabel")
headerDescription.Text = "Drawing Script"
headerDescription.Size = UDim2.new(0, 0, 1, 0)
headerDescription.AutomaticSize = Enum.AutomaticSize.X
headerDescription.TextColor3 = Color3.fromHex("FFFFFF")
headerDescription.TextTransparency = 0.3
headerDescription.BackgroundTransparency = 1
headerDescription.Parent = headerFrameTitle
local headerDescriptionPadding = Instance.new("UIPadding")
headerDescriptionPadding.PaddingLeft = UDim.new(0, 7)
headerDescriptionPadding.PaddingRight = UDim.new(0, 7)
headerDescriptionPadding.Parent = headerDescription
local headerUser = Instance.new("TextLabel")
headerUser.Text = "usernaxo"
headerUser.Size = UDim2.new(0, 0, 1, 0)
headerUser.AutomaticSize = Enum.AutomaticSize.X
headerUser.TextColor3 = Color3.fromHex("FFFFFF")
headerUser.TextTransparency = 0.3
headerUser.BackgroundColor3 = Color3.fromHex("C00000")
headerUser.BackgroundTransparency = 0.7
headerUser.BorderSizePixel = 0
headerUser.Parent = headerFrameTitle
local headerUserPadding = Instance.new("UIPadding")
headerUserPadding.PaddingLeft = UDim.new(0, 7)
headerUserPadding.PaddingRight = UDim.new(0, 7)
headerUserPadding.Parent = headerUser
local headerUserCorner = Instance.new("UICorner")
headerUserCorner.CornerRadius = UDim.new(0, 3)
headerUserCorner.Parent = headerUser
local headerFrameButton = Instance.new("Frame")
headerFrameButton.Size = UDim2.new(0.5, 0, 1, 0)
headerFrameButton.BackgroundTransparency = 1
headerFrameButton.Parent = headerFrame
local headerFrameButtonLayout = Instance.new("UIListLayout")
headerFrameButtonLayout.FillDirection = Enum.FillDirection.Horizontal
headerFrameButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
headerFrameButtonLayout.SortOrder = Enum.SortOrder.LayoutOrder
headerFrameButtonLayout.Parent = headerFrameButton
local headerButton = Instance.new("TextButton")
headerButton.Text = "Close"
headerButton.Size = UDim2.new(0, 0, 1, 0)
headerButton.AutomaticSize = Enum.AutomaticSize.X
headerButton.TextColor3 = Color3.fromHex("FFFFFF")
headerButton.TextTransparency = 0.3
headerButton.BackgroundColor3 = Color3.fromHex("000000")
headerButton.BackgroundTransparency = 0.8
headerButton.BorderSizePixel = 0
headerButton.Parent = headerFrameButton
local headerButtonPadding = Instance.new("UIPadding")
headerButtonPadding.PaddingLeft = UDim.new(0, 7)
headerButtonPadding.PaddingRight = UDim.new(0, 7)
headerButtonPadding.Parent = headerButton
local headerButtonCorner = Instance.new("UICorner")
headerButtonCorner.CornerRadius = UDim.new(0, 3)
headerButtonCorner.Parent = headerButton
local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, 0, 1, -40)
contentFrame.LayoutOrder = 2
contentFrame.Style = 6
contentFrame.Parent = mainFrame
headerButton.MouseButton1Click:Connect(
    function()
        if mainFrameClosed then
            headerButton.Text = "Close"
            contentFrame.Visible = true
            mainFrame.Size = UDim2.new(0, 700, 0, 350)
            mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
            mainFrameClosed = false
        else
            headerButton.Text = "Open"
            contentFrame.Visible = false
            mainFrame.Size = UDim2.new(0, 700, 0, 57)
            mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
            mainFrameClosed = true
        end
    end
)
local contentFrameScroll = Instance.new("ScrollingFrame")
contentFrameScroll.Size = UDim2.new(1, 0, 1, 0)
contentFrameScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
contentFrameScroll.BackgroundTransparency = 1
contentFrameScroll.ScrollBarImageColor3 = Color3.fromHex("C00000")
contentFrameScroll.ScrollBarThickness = 3
contentFrameScroll.ScrollBarImageTransparency = 0.3
contentFrameScroll.BorderSizePixel = 0
contentFrameScroll.Parent = contentFrame
local contentFrameGrid = Instance.new("UIGridLayout")
contentFrameGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
contentFrameGrid.CellSize = UDim2.new(0, 100, 0, 100)
contentFrameGrid.CellPadding = UDim2.new(0, 10, 0, 10)
contentFrameGrid.SortOrder = Enum.SortOrder.LayoutOrder
contentFrameGrid.Parent = contentFrameScroll
local progressFrame = Instance.new("Frame")
progressFrame.Size = UDim2.new(0, 570, 0, 57)
progressFrame.AnchorPoint = Vector2.new(0.5, 0.5)
progressFrame.Position = UDim2.new(0.5, 0, 0, 10)
progressFrame.Style = 6
progressFrame.Visible = false
progressFrame.Parent = screen
local progressHeaderFrame = Instance.new("Frame")
progressHeaderFrame.Size = UDim2.new(1, 0, 0, 40)
progressHeaderFrame.Style = 6
progressHeaderFrame.Parent = progressFrame
local progressHeaderFrameLayout = Instance.new("UIListLayout")
progressHeaderFrameLayout.FillDirection = Enum.FillDirection.Horizontal
progressHeaderFrameLayout.SortOrder = Enum.SortOrder.LayoutOrder
progressHeaderFrameLayout.VerticalAlignment = Enum.VerticalAlignment.Center
progressHeaderFrameLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
progressHeaderFrameLayout.Parent = progressHeaderFrame
local drawingName = Instance.new("TextLabel")
drawingName.Text = "Drawing Name"
drawingName.Size = UDim2.new(0, 0, 1, 0)
drawingName.AutomaticSize = Enum.AutomaticSize.X
drawingName.TextColor3 = Color3.fromHex("FFFFFF")
drawingName.TextTransparency = 0.3
drawingName.BackgroundColor3 = Color3.fromHex("000000")
drawingName.BackgroundTransparency = 0.7
drawingName.BorderSizePixel = 0
drawingName.Parent = progressHeaderFrame
local drawingNamePadding = Instance.new("UIPadding")
drawingNamePadding.PaddingLeft = UDim.new(0, 7)
drawingNamePadding.PaddingRight = UDim.new(0, 7)
drawingNamePadding.Parent = drawingName
local drawingNameCorner = Instance.new("UICorner")
drawingNameCorner.CornerRadius = UDim.new(0, 3)
drawingNameCorner.Parent = drawingName
local drawingNameValue = Instance.new("TextLabel")
drawingNameValue.Text = "Drawing"
drawingNameValue.Size = UDim2.new(0, 0, 1, 0)
drawingNameValue.AutomaticSize = Enum.AutomaticSize.X
drawingNameValue.TextColor3 = Color3.fromHex("FFFFFF")
drawingNameValue.TextTransparency = 0.3
drawingNameValue.BackgroundTransparency = 1
drawingNameValue.Parent = progressHeaderFrame
local drawingNameValuePadding = Instance.new("UIPadding")
drawingNameValuePadding.PaddingLeft = UDim.new(0, 7)
drawingNameValuePadding.PaddingRight = UDim.new(0, 7)
drawingNameValuePadding.Parent = drawingNameValue
local drawingPixels = Instance.new("TextLabel")
drawingPixels.Text = "Painted Pixels"
drawingPixels.Size = UDim2.new(0, 0, 1, 0)
drawingPixels.AutomaticSize = Enum.AutomaticSize.X
drawingPixels.TextColor3 = Color3.fromHex("FFFFFF")
drawingPixels.TextTransparency = 0.3
drawingPixels.BackgroundColor3 = Color3.fromHex("000000")
drawingPixels.BackgroundTransparency = 0.7
drawingPixels.BorderSizePixel = 0
drawingPixels.Parent = progressHeaderFrame
local drawingPixelsPadding = Instance.new("UIPadding")
drawingPixelsPadding.PaddingLeft = UDim.new(0, 7)
drawingPixelsPadding.PaddingRight = UDim.new(0, 7)
drawingPixelsPadding.Parent = drawingPixels
local drawingPixelsCorner = Instance.new("UICorner")
drawingPixelsCorner.CornerRadius = UDim.new(0, 3)
drawingPixelsCorner.Parent = drawingPixels
local drawingPixelsValue = Instance.new("TextLabel")
drawingPixelsValue.Text = "0 of 1024"
drawingPixelsValue.Size = UDim2.new(0, 0, 1, 0)
drawingPixelsValue.AutomaticSize = Enum.AutomaticSize.X
drawingPixelsValue.TextColor3 = Color3.fromHex("FFFFFF")
drawingPixelsValue.TextTransparency = 0.3
drawingPixelsValue.BackgroundTransparency = 1
drawingPixelsValue.Parent = progressHeaderFrame
local drawingPixelsValuePadding = Instance.new("UIPadding")
drawingPixelsValuePadding.PaddingLeft = UDim.new(0, 7)
drawingPixelsValuePadding.PaddingRight = UDim.new(0, 7)
drawingPixelsValuePadding.Parent = drawingPixelsValue
local drawingStatus = Instance.new("TextLabel")
drawingStatus.Text = "Drawing Status"
drawingStatus.Size = UDim2.new(0, 0, 1, 0)
drawingStatus.AutomaticSize = Enum.AutomaticSize.X
drawingStatus.TextColor3 = Color3.fromHex("FFFFFF")
drawingStatus.TextTransparency = 0.3
drawingStatus.BackgroundColor3 = Color3.fromHex("C00000")
drawingStatus.BackgroundTransparency = 0.7
drawingStatus.BorderSizePixel = 0
drawingStatus.Parent = progressHeaderFrame
local drawingStatusPadding = Instance.new("UIPadding")
drawingStatusPadding.PaddingLeft = UDim.new(0, 7)
drawingStatusPadding.PaddingRight = UDim.new(0, 7)
drawingStatusPadding.Parent = drawingStatus
local drawingStatusCorner = Instance.new("UICorner")
drawingStatusCorner.CornerRadius = UDim.new(0, 3)
drawingStatusCorner.Parent = drawingStatus
local drawingStatusValue = Instance.new("TextLabel")
drawingStatusValue.Text = "Pending"
drawingStatusValue.Size = UDim2.new(0, 0, 1, 0)
drawingStatusValue.AutomaticSize = Enum.AutomaticSize.X
drawingStatusValue.TextColor3 = Color3.fromHex("FFFFFF")
drawingStatusValue.TextTransparency = 0.3
drawingStatusValue.BackgroundTransparency = 1
drawingStatusValue.Parent = progressHeaderFrame
local drawingStatusValuePadding = Instance.new("UIPadding")
drawingStatusValuePadding.PaddingLeft = UDim.new(0, 7)
drawingStatusValuePadding.PaddingRight = UDim.new(0, 7)
drawingStatusValuePadding.Parent = drawingStatusValue
local drawings =
    loadstring(
    game:HttpGet(
        "https://raw.githubusercontent.com/Bac0nHck/Scripts/refs/heads/main/Drawings.lua",
        true
    )
)()
for indexDrawing, drawing in ipairs(drawings) do
    local imageAsset = Instance.new("ImageLabel")
    imageAsset.Size = UDim2.new(1, 0, 1, 0)
    imageAsset.BackgroundTransparency = 1
    imageAsset.ImageTransparency = 0.5
    imageAsset.BorderSizePixel = 0
    imageAsset.Image = drawing.drawingAsset
    local imageAssetCorner = Instance.new("UICorner")
    imageAssetCorner.CornerRadius = UDim.new(0, 3)
    imageAssetCorner.Parent = imageAsset
    local imageName = Instance.new("TextLabel")
    imageName.Text = drawing.drawingName
    imageName.Size = UDim2.new(1, 0, 0.2, 0)
    imageName.TextColor3 = Color3.fromHex("FFFFFF")
    imageName.TextTransparency = 0.5
    imageName.BackgroundColor3 = Color3.fromHex("000000")
    imageName.TextXAlignment = Enum.TextXAlignment.Left
    imageName.TextYAlignment = Enum.TextYAlignment.Center
    imageName.BackgroundTransparency = 0.7
    imageName.BorderSizePixel = 0
    imageName.Parent = imageAsset
    local imageNamePadding = Instance.new("UIPadding")
    imageNamePadding.PaddingLeft = UDim.new(0, 7)
    imageNamePadding.Parent = imageName
    local imageNameCorner = Instance.new("UICorner")
    imageNameCorner.CornerRadius = UDim.new(0, 3)
    imageNameCorner.Parent = imageName
    local imageButton = Instance.new("TextButton")
    imageButton.Text = "Draw Image"
    imageButton.Size = UDim2.new(0.9, 0, 0.2, 0)
    imageButton.Position = UDim2.new(0.05, 0, 0.75, 0)
    imageButton.TextColor3 = Color3.fromHex("FFFFFF")
    imageButton.TextTransparency = 0.7
    imageButton.BackgroundColor3 = Color3.fromHex("000000")
    imageButton.TextXAlignment = Enum.TextXAlignment.Center
    imageButton.TextYAlignment = Enum.TextYAlignment.Center
    imageButton.BackgroundTransparency = 0.8
    imageButton.BorderSizePixel = 0
    imageButton.Active = false
    imageButton.Parent = imageAsset
    local imageButtonCorner = Instance.new("UICorner")
    imageButtonCorner.CornerRadius = UDim.new(0, 3)
    imageButtonCorner.Parent = imageButton
    imageButton.MouseButton1Click:Connect(
        function()
            if imageButton.Active then
                if drawingFinished then
                    if game.Players.LocalPlayer.Character.Humanoid.Sit then
                        drawingFinished = false
                        progressFrame.Visible = true
                        drawingNameValue.Text = drawing.drawingName
                        game.StarterGui:SetCore(
                            "SendNotification",
                            {
                                Title = "DRAWING STARTED",
                                Text = drawing.drawingName,
                                Icon = drawing.drawingAsset,
                                Duration = 3
                            }
                        )
                        local userCanvas =
                            game.Players.LocalPlayer.PlayerGui.MainGui.PaintFrame.GridHolder.Grid
                        for indexPixel, pixel in ipairs(drawing.drawingPixels) do
                            if game.Players.LocalPlayer.Character.Humanoid.Sit then
                                currentPixel = indexPixel
                                drawingPixelsValue.Text = currentPixel .. " of 1024"
                                userCanvas[indexPixel].BackgroundColor3 =
                                    Color3.fromRGB(pixel.R, pixel.G, pixel.B)
                                if currentPixel == 1024 then
                                    game.StarterGui:SetCore(
                                        "SendNotification",
                                        {
                                            Title = "DRAWING DONE",
                                            Text = drawing.drawingName,
                                            Icon = drawing.drawingAsset,
                                            Duration = 3
                                        }
                                    )
                                    currentPixel = 0
                                    drawingFinished = true
                                    drawingStatus.BackgroundColor3 = Color3.fromHex("00979D")
                                    drawingStatusValue.Text = "Finished"
                                    wait(3)
                                    drawingNameValue.Text = "Drawing"
                                    drawingPixelsValue.Text = "0 of 1024"
                                    drawingStatus.BackgroundColor3 = Color3.fromHex("C00000")
                                    drawingStatusValue.Text = "Pending"
                                    progressFrame.Visible = false
                                end
                                wait(0.285)
                            else
                                currentDrawing = drawing
                                currentPixel = indexPixel
                                drawingPaused = true
                                drawingStatus.BackgroundColor3 = Color3.fromHex("D68000")
                                drawingStatusValue.Text = "Paused"
                                break
                            end
                        end
                    else
                        game.StarterGui:SetCore(
                            "SendNotification",
                            {Title = "SIT DOWN PLEASE", Text = "Sit down to draw", Duration = 3}
                        )
                    end
                else
                    game.StarterGui:SetCore(
                        "SendNotification",
                        {
                            Title = "WAIT CURRENT DRAWING",
                            Text = "Wait for the current drawing",
                            Duration = 3
                        }
                    )
                end
            end
        end
    )
    imageAsset.MouseEnter:Connect(
        function()
            imageAsset.ImageTransparency = 0.3
            imageName.TextTransparency = 0.3
            imageName.BackgroundTransparency = 0.5
            imageButton.BackgroundColor3 = Color3.fromHex("C00000")
            imageButton.TextTransparency = 0
            imageButton.BackgroundTransparency = 0.3
            imageButton.Active = true
        end
    )
    imageAsset.MouseLeave:Connect(
        function()
            imageAsset.ImageTransparency = 0.5
            imageName.TextTransparency = 0.5
            imageName.BackgroundTransparency = 0.7
            imageButton.BackgroundColor3 = Color3.fromHex("000000")
            imageButton.TextTransparency = 0.7
            imageButton.BackgroundTransparency = 0.8
            imageButton.Active = false
        end
    )
    imageAsset.Parent = contentFrameScroll
end
game.Players.LocalPlayer.Character.Humanoid.Seated:Connect(
    function()
        if not drawingFinished then
            if drawingPaused then
                drawingNameValue.Text = currentDrawing.drawingName
                drawingStatus.BackgroundColor3 = Color3.fromHex("C00000")
                drawingStatusValue.Text = "Pending"
                local userCanvas =
                    game.Players.LocalPlayer.PlayerGui.MainGui.PaintFrame.GridHolder.Grid
                for indexPixel = currentPixel, #currentDrawing.drawingPixels do
                    if game.Players.LocalPlayer.Character.Humanoid.Sit then
                        currentPixel = indexPixel
                        drawingPixelsValue.Text = currentPixel .. " of 1024"
                        userCanvas[indexPixel].BackgroundColor3 =
                            Color3.fromRGB(
                            currentDrawing.drawingPixels[indexPixel].R,
                            currentDrawing.drawingPixels[indexPixel].G,
                            currentDrawing.drawingPixels[indexPixel].B
                        )
                        if currentPixel == 1024 then
                            game.StarterGui:SetCore(
                                "SendNotification",
                                {
                                    Title = "DRAWING DONE",
                                    Text = currentDrawing.drawingName,
                                    Icon = currentDrawing.drawingAsset,
                                    Duration = 3
                                }
                            )
                            currentDrawing = {}
                            currentPixel = 0
                            drawingFinished = true
                            drawingPaused = false
                            drawingStatus.BackgroundColor3 = Color3.fromHex("00979D")
                            drawingStatusValue.Text = "Finished"
                            wait(3)
                            drawingNameValue.Text = "Drawing"
                            drawingPixelsValue.Text = "0 of 1024"
                            drawingStatus.BackgroundColor3 = Color3.fromHex("C00000")
                            drawingStatusValue.Text = "Pending"
                            progressFrame.Visible = false
                        end
                        wait(0.285)
                    else
                        currentPixel = indexPixel
                        drawingPaused = true
                        drawingStatus.BackgroundColor3 = Color3.fromHex("D68000")
                        drawingStatusValue.Text = "Paused"
                        break
                    end
                end
            end
        end
    end
)

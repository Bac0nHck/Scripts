type MineConstraint = { cells: { number }, mines: number }
type MineMasks = { safe: number, mine: number }
type MineOptions = { [number]: MineMasks }
type MineComponent = { cells: { number }, options: MineOptions }

local function forcedMineValue(size, mines)
	if mines == 0 then
		return 0
	elseif mines == size then
		return 1
	end
	return nil
end

local function enumerateMineComponent(cells, ruleIds, rules, rulesByCell, minimum, maximum, useTotals, deadline)
	if #cells > 32 then
		return nil
	end

	table.sort(cells, function(left, right)
		local leftDegree = #rulesByCell[left]
		local rightDegree = #rulesByCell[right]
		if leftDegree == rightDegree then
			return left < right
		end
		return leftDegree > rightDegree
	end)

	local needed = {}
	local remaining = {}
	for _, ruleId in ruleIds do
		needed[ruleId] = rules[ruleId].mines
		remaining[ruleId] = #rules[ruleId].cells
	end

	local options: MineOptions = {}
	local fullMask = bit32.rshift(0xFFFFFFFF, 32 - #cells)
	local visited = 0
	local exceededBudget = false
	local finished = false

	local function search(depth, count, mineMask)
		if count > maximum or count + #cells - depth + 1 < minimum then
			return
		end
		visited += 1
		if visited % 64 == 0 and (visited >= 8192 or os.clock() >= deadline) then
			exceededBudget = true
			return
		end
		if depth > #cells then
			local key = if useTotals then count else 0
			local option = options[key] or { safe = 0, mine = 0 }
			option.safe = bit32.bor(option.safe, bit32.bxor(fullMask, mineMask))
			option.mine = bit32.bor(option.mine, mineMask)
			options[key] = option
			finished = not useTotals and option.safe == fullMask and option.mine == fullMask
			return
		end

		local adjacentRules = rulesByCell[cells[depth]]
		local first, last = 0, 1
		for _, ruleId in adjacentRules do
			if needed[ruleId] == 0 then
				last = 0
			elseif needed[ruleId] == remaining[ruleId] then
				first = 1
			end
		end
		if first > last then
			return
		end

		local bit = bit32.lshift(1, depth - 1)
		for _, ruleId in adjacentRules do
			remaining[ruleId] -= 1
		end
		for value = first, last do
			for _, ruleId in adjacentRules do
				needed[ruleId] -= value
			end
			search(depth + 1, count + value, if value == 1 then bit32.bor(mineMask, bit) else mineMask)
			for _, ruleId in adjacentRules do
				needed[ruleId] += value
			end
			if exceededBudget or finished then
				break
			end
		end
		for _, ruleId in adjacentRules do
			remaining[ruleId] += 1
		end
	end

	search(1, 0, 0)
	return if exceededBudget then nil else options
end

local function solveMinesweeper(constraints: { MineConstraint }, unknownCount: number, totalMines: number?): { [number]: number }?
	local deadline = os.clock() + 0.020
	local results: { [number]: number } = {}
	local remainingUnknown = unknownCount
	local remainingMines = totalMines
	local inconsistent = false
	local changed = false

	local function assign(cell, value)
		if results[cell] == nil then
			results[cell] = value
			remainingUnknown -= 1
			if remainingMines ~= nil then
				remainingMines -= value
			end
			changed = true
		elseif results[cell] ~= value then
			inconsistent = true
		end
	end

	local rules: { MineConstraint } = {}
	local rulesByCell: { [number]: { number } } = {}
	for round = 1, 16 do
		changed = false
		table.clear(rules)
		table.clear(rulesByCell)
		for _, constraint in constraints do
			local cells = {}
			local mines = constraint.mines
			for _, cell in constraint.cells do
				local known = results[cell]
				if known == nil then
					cells[#cells + 1] = cell
				else
					mines -= known
				end
			end
			if mines < 0 or mines > #cells then
				return nil
			end
			if #cells == 0 then
				continue
			end
			local value = forcedMineValue(#cells, mines)
			if value ~= nil then
				for _, cell in cells do
					assign(cell, value)
				end
			else
				local ruleId = #rules + 1
				rules[ruleId] = { cells = cells, mines = mines }
				for _, cell in cells do
					local adjacentRules = rulesByCell[cell]
					if adjacentRules == nil then
						adjacentRules = {}
						rulesByCell[cell] = adjacentRules
					end
					adjacentRules[#adjacentRules + 1] = ruleId
				end
			end
		end

		if remainingMines ~= nil then
			if remainingMines < 0 or remainingMines > remainingUnknown then
				return nil
			end
			if remainingUnknown > 0 and (remainingMines == 0 or remainingMines == remainingUnknown) then
				local value = if remainingMines == 0 then 0 else 1
				for cell = 1, unknownCount do
					if results[cell] == nil then
						assign(cell, value)
					end
				end
			end
		end

		if not changed then
			local compared = {}
			local leftSet = {}
			local sharedByRule = {}
			for leftId, left in rules do
				if leftId % 16 == 0 and os.clock() >= deadline then
					return if inconsistent then nil else results
				end
				table.clear(leftSet)
				table.clear(sharedByRule)
				for _, cell in left.cells do
					leftSet[cell] = true
				end
				for _, shared in left.cells do
					for _, rightId in rulesByCell[shared] do
						if rightId <= leftId or compared[rightId] == leftId then
							continue
						end
						compared[rightId] = leftId
						local right = rules[rightId]
						local overlap = 0
						for _, cell in right.cells do
							if leftSet[cell] then
								overlap += 1
								sharedByRule[cell] = rightId
							end
						end
						local leftSize, rightSize = #left.cells - overlap, #right.cells - overlap
						local minimum = math.max(0, left.mines - leftSize, right.mines - rightSize)
						local maximum = math.min(overlap, left.mines, right.mines)
						if minimum > maximum then
							return nil
						end
						if minimum ~= maximum then
							continue
						end
						local overlapValue = forcedMineValue(overlap, minimum)
						local rightValue = forcedMineValue(rightSize, right.mines - minimum)
						if overlapValue ~= nil or (rightSize > 0 and rightValue ~= nil) then
							for _, cell in right.cells do
								local value = if leftSet[cell] then overlapValue else rightValue
								if value ~= nil then
									assign(cell, value)
								end
							end
						end
						local leftValue = forcedMineValue(leftSize, left.mines - minimum)
						if leftSize > 0 and leftValue ~= nil then
							for _, cell in left.cells do
								if sharedByRule[cell] ~= rightId then
									assign(cell, leftValue)
								end
							end
						end
					end
				end
			end
		end

		if inconsistent then
			return nil
		end
		if not changed then
			break
		end
		if round == 16 or os.clock() >= deadline then
			return results
		end
	end

	local seenCells = {}
	local seenRules = {}
	local regions = {}
	local frontierCount = 0
	for root in rulesByCell do
		if seenCells[root] then
			continue
		end
		local cells = { root }
		local ruleIds = {}
		seenCells[root] = true
		local head = 1
		while head <= #cells do
			for _, ruleId in rulesByCell[cells[head]] do
				if not seenRules[ruleId] then
					seenRules[ruleId] = true
					ruleIds[#ruleIds + 1] = ruleId
					for _, cell in rules[ruleId].cells do
						if not seenCells[cell] then
							seenCells[cell] = true
							cells[#cells + 1] = cell
						end
					end
				end
			end
			head += 1
		end
		frontierCount += #cells
		regions[#regions + 1] = { cells = cells, ruleIds = ruleIds }
	end
	table.sort(regions, function(left, right)
		return #left.cells < #right.cells
	end)

	local function recordMasks(cells, safeMask, mineMask)
		for index, cell in cells do
			local bit = bit32.lshift(1, index - 1)
			if bit32.band(safeMask, bit) == 0 then
				results[cell] = 1
			elseif bit32.band(mineMask, bit) == 0 then
				results[cell] = 0
			end
		end
	end

	local components: { MineComponent } = {}
	local target = remainingMines
	for _, region in regions do
		if os.clock() >= deadline then
			return results
		end
		local size = #region.cells
		local minimum = if target ~= nil then math.max(0, target - (remainingUnknown - size)) else 0
		local maximum = if target ~= nil then math.min(size, target) else size
		local options = enumerateMineComponent(region.cells, region.ruleIds, rules, rulesByCell, minimum, maximum, target ~= nil, deadline)
		if options ~= nil then
			if next(options) == nil then
				return nil
			end
			local safeMask, mineMask = 0, 0
			for _, option in options do
				safeMask = bit32.bor(safeMask, option.safe)
				mineMask = bit32.bor(mineMask, option.mine)
			end
			recordMasks(region.cells, safeMask, mineMask)
			components[#components + 1] = { cells = region.cells, options = options }
		end
	end

	if target == nil or #components ~= #regions or #components == 0 then
		return results
	end

	local freeCount = remainingUnknown - frontierCount
	local function combineCounts(left, right)
		local sums = {}
		for first in left do
			if os.clock() >= deadline then
				return nil
			end
			for second in right do
				local sum = first + second
				if sum <= target then
					sums[sum] = true
				end
			end
		end
		return sums
	end

	local prefix = { { [0] = true } }
	for index, component in components do
		local sums = combineCounts(prefix[index], component.options)
		if sums == nil then
			return results
		end
		prefix[index + 1] = sums
	end

	local freeMinimum, freeMaximum = math.huge, -math.huge
	for sum in prefix[#components + 1] do
		local freeMines = target - sum
		if freeMines <= freeCount then
			freeMinimum = math.min(freeMinimum, freeMines)
			freeMaximum = math.max(freeMaximum, freeMines)
		end
	end
	if freeMinimum > freeMaximum then
		return nil
	end
	if freeMaximum == 0 or freeMinimum == freeCount then
		local value = if freeMaximum == 0 then 0 else 1
		for cell = 1, unknownCount do
			if results[cell] == nil and not seenCells[cell] then
				results[cell] = value
			end
		end
	end

	local suffix = {}
	for count = 0, math.min(freeCount, target) do
		suffix[count] = true
	end
	for index = #components, 1, -1 do
		local component = components[index]
		local safeMask, mineMask = 0, 0
		for count, option in component.options do
			if os.clock() >= deadline then
				return results
			end
			for used in prefix[index] do
				if suffix[target - count - used] then
					safeMask = bit32.bor(safeMask, option.safe)
					mineMask = bit32.bor(mineMask, option.mine)
					break
				end
			end
		end
		recordMasks(component.cells, safeMask, mineMask)
		local sums = combineCounts(suffix, component.options)
		if sums == nil then
			return results
		end
		suffix = sums
	end

	return results
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
if game.PlaceId ~= 7871169780 or not player then
	return
end

local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then
	return
end

local environment = if type(getgenv) == "function" then getgenv() else _G
local SESSION_KEY = "BlockermansMinesweeperHints"
local existingStop = environment[SESSION_KEY]
if type(existingStop) == "function" then
	existingStop()
end

local CLOSED = -1
local REFRESH_INTERVAL = 0.12
local SAFE_COLOR = Color3.fromRGB(34, 237, 116)
local MINE_COLOR = Color3.fromRGB(255, 56, 64)

local markers = {}
local boardConnections = {}
local running = true

local function clearMarkers()
	for _, marker in markers do
		marker:Destroy()
	end
	table.clear(markers)
end

local function disconnectBoard()
	for _, connection in boardConnections do
		connection:Disconnect()
	end
	table.clear(boardConnections)
end

local function stop()
	running = false
	disconnectBoard()
	clearMarkers()
	if environment[SESSION_KEY] == stop then
		environment[SESSION_KEY] = nil
	end
end

environment[SESSION_KEY] = stop

local function addMarker(tile, result)
	local color = if result == 0 then SAFE_COLOR else MINE_COLOR
	local marker = Instance.new("SurfaceGui")
	marker.Name = if result == 0 then "MinesweeperSafe" else "MinesweeperMine"
	marker.Adornee = tile
	marker.Face = Enum.NormalId.Top
	marker.Active = false
	marker.ResetOnSpawn = false
	marker.LightInfluence = 0
	marker.ZOffset = 1
	marker.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	marker.CanvasSize = Vector2.new(96, 96)

	local fill = Instance.new("Frame")
	fill.Active = false
	fill.Interactable = false
	fill.Position = UDim2.fromScale(0.07, 0.07)
	fill.Size = UDim2.fromScale(0.86, 0.86)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = color
	fill.BackgroundTransparency = 0.42
	fill.Parent = marker

	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = color
	border.Thickness = 3
	border.Parent = fill

	marker.Parent = playerGui
	markers[tile] = marker
end

local function readBoardSettings()
	local flag = Workspace:FindFirstChild("Flag")
	local parts = flag and flag:FindFirstChild("Parts")
	local info = ReplicatedStorage:FindFirstChild("Info")
	local settings = info and info:FindFirstChild("Settings")
	if not parts or not info or not settings then
		return nil
	end

	local gameRunning = info:FindFirstChild("GameRunning")
	local gridSize = settings:GetAttribute("GridSize")
	local step = settings:GetAttribute("TileSize")
	local mines = info:FindFirstChild("Mines")
	local timer = info:FindFirstChild("Timer")
	local challenges = info:FindFirstChild("ChallengeSettings")
	if not gameRunning or not gameRunning:IsA("BoolValue") or not gameRunning.Value
		or typeof(gridSize) ~= "Vector2" or type(step) ~= "number" or not mines or not mines:IsA("IntValue")
		or not timer or not challenges or settings:GetAttribute("Mode") ~= 1 then
		return nil
	end
	for _, enabled in challenges:GetAttributes() do
		if enabled == true then
			return nil
		end
	end

	local width, height = gridSize.X, gridSize.Y
	local total = mines.Value
	local round = timer:GetAttribute("StartTime")
	if width < 1 or height < 1 or width % 1 ~= 0 or height % 1 ~= 0 or step <= 0
		or total < 1 or total >= width * height or type(round) ~= "number" then
		return nil
	end

	return parts, width, height, step, total, round
end

local function indexTiles(parts, width, height, step)
	local entries = table.create(width * height)
	local origin
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, tile in parts:GetChildren() do
		if tile.Name ~= "Part" or not tile:IsA("BasePart") then
			continue
		end
		local position = tile.Position
		origin = origin or position
		local offset = position - origin
		local x = math.round(offset.X / step)
		local z = math.round(offset.Z / step)
		if math.abs(offset.X - x * step) > 0.04 or math.abs(offset.Z - z * step) > 0.04
			or math.abs(offset.Y) > 0.04 then
			return nil
		end
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
		entries[#entries + 1] = { tile = tile, x = x, z = z }
	end

	local columns = maxX - minX + 1
	local rows = maxZ - minZ + 1
	if #entries == 0 or not ((columns <= width and rows <= height) or (columns <= height and rows <= width)) then
		return nil
	end

	local tiles = table.create(columns * rows)
	for _, entry in entries do
		local index = (entry.z - minZ) * columns + entry.x - minX + 1
		if tiles[index] then
			return nil
		end
		tiles[index] = entry.tile
	end
	return tiles, columns, rows, #entries == width * height
end

local function readClues(tiles, states)
	local changed = false
	local hasClues = false
	local replacedClue = false
	for index, tile in tiles do
		local numberGui = tile:FindFirstChild("NumberGui")
		local clue = CLOSED
		if numberGui then
			local label = numberGui:FindFirstChild("TextLabel")
			if not numberGui:IsA("SurfaceGui") or not numberGui.Enabled or not label
				or not label:IsA("TextLabel") or not label.Visible then
				return false, false
			end
			local text = label.Text
			if text == "" then
				clue = 0
			else
				local digit = tonumber(text:match("^%s*([0-8])%s*$"))
				if digit == nil then
					return false, false
				end
				clue = digit
			end
			hasClues = true
		end
		local previous = states[index]
		if previous ~= clue then
			replacedClue = replacedClue or (previous ~= nil and previous ~= CLOSED)
			states[index] = clue
			changed = true
			if clue ~= CLOSED and markers[tile] then
				markers[tile]:Destroy()
				markers[tile] = nil
			end
		end
	end
	return hasClues, changed, replacedClue
end

local function deduce(tiles, states, columns, rows, total, complete)
	local unknownTiles = {}
	local ids = {}
	for index, clue in states do
		if clue == CLOSED then
			local id = #unknownTiles + 1
			unknownTiles[id] = tiles[index]
			ids[index] = id
		end
	end

	local constraints = {}
	for index, clue in states do
		if clue == CLOSED then
			continue
		end
		local x = (index - 1) % columns + 1
		local z = (index - 1) // columns + 1
		if not complete and (x == 1 or x == columns or z == 1 or z == rows) then
			continue
		end
		local neighbors = {}
		local missing = false
		for neighborZ = math.max(z - 1, 1), math.min(z + 1, rows) do
			for neighborX = math.max(x - 1, 1), math.min(x + 1, columns) do
				local neighborIndex = (neighborZ - 1) * columns + neighborX
				local id = ids[neighborIndex]
				if id then
					neighbors[#neighbors + 1] = id
				end
				missing = missing or states[neighborIndex] == nil
			end
		end
		if missing then
			continue
		end
		if clue > #neighbors then
			return nil
		end
		if #neighbors > 0 then
			constraints[#constraints + 1] = { cells = neighbors, mines = clue }
		end
	end

	return solveMinesweeper(constraints, #unknownTiles, if complete then total else nil), unknownTiles
end

local currentParts, currentWidth, currentHeight, currentStep, currentTotal, currentRound
local tiles, columns, rows, complete
local states = {}
local dirty = true
local snapshotReady = false
local settled = false
local retryIndexAt = 0

local function invalidateBoard()
	dirty = true
	snapshotReady = false
	settled = false
	clearMarkers()
end

local function refresh()
	local parts, width, height, step, total, round = readBoardSettings()
	if parts ~= currentParts then
		disconnectBoard()
		currentParts = parts
		invalidateBoard()
		if parts then
			boardConnections[1] = parts.ChildAdded:Connect(invalidateBoard)
			boardConnections[2] = parts.ChildRemoved:Connect(invalidateBoard)
		end
	end
	if not parts then
		tiles = nil
		return
	end
	if width ~= currentWidth or height ~= currentHeight or step ~= currentStep
		or total ~= currentTotal or round ~= currentRound then
		currentWidth, currentHeight, currentStep, currentTotal, currentRound = width, height, step, total, round
		invalidateBoard()
	end
	if dirty or (not tiles and os.clock() >= retryIndexAt) then
		tiles, columns, rows, complete = indexTiles(parts, width, height, step)
		table.clear(states)
		dirty = false
		retryIndexAt = os.clock() + 0.75
	end
	if not tiles then
		return
	end

	local valid, changed, replacedClue = readClues(tiles, states)
	if not valid or replacedClue then
		clearMarkers()
	end
	if not valid or changed or not snapshotReady then
		snapshotReady = valid
		settled = false
		return
	end
	if settled then
		return
	end

	settled = true
	local results, unknownTiles = deduce(tiles, states, columns, rows, total, complete)
	if not results then
		clearMarkers()
		return
	end
	for id, result in results do
		local tile = unknownTiles[id]
		local marker = markers[tile]
		if marker and (marker.Name == "MinesweeperSafe") ~= (result == 0) then
			clearMarkers()
			return
		end
		if not marker then
			addMarker(tile, result)
		end
	end
end

local success, failure = xpcall(function()
	local announced = false
	while running and playerGui.Parent do
		refresh()
		if not announced then
			announced = true
			warn("t.me/arceusxcommunity")
		end
		task.wait(REFRESH_INTERVAL)
	end
end, debug.traceback)
stop()
if not success then
	warn("Minesweeper Hints stopped: " .. tostring(failure))
end

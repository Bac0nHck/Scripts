local function createPolicy(Plate, Upgrades, Config, English)
	local policy = {}
	local letterMap = {
		[1040] = "A", [1042] = "B", [1045] = "E", [1050] = "K",
		[1052] = "M", [1053] = "H", [1054] = "O", [1056] = "P",
		[1057] = "C", [1058] = "T", [1059] = "Y", [1061] = "X",
	}
	local regionNames = {}
	local defaultRarities = { COMMON = true }
	local defaultQualities = { NEW = true, GOOD = true, USED = true, WORN = true, BAD = true }
	local defaultCategories = { Luck = true, Speed = true, Batch = true, Capacity = true, Equipment = true }
	local categoriesByStat = { luck = "Luck", speed = "Speed", multi = "Batch", slots = "Capacity", wall = "Equipment" }

	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end

	local function ascii(value)
		local text = tostring(value or "")
		if not utf8.len(text) then
			return ""
		end
		local result = {}
		for _, codepoint in utf8.codes(text) do
			local upper = codepoint
			if codepoint >= 1072 and codepoint <= 1103 then
				upper -= 32
			end
			local character = letterMap[upper]
			if codepoint < 128 then
				character = string.upper(string.char(codepoint))
			end
			table.insert(result, character or "?")
		end
		return table.concat(result)
	end

	for _, region in Config.Regions do
		local name = English and English[region.name] or region.name
		if type(name) == "string" then name = name:gsub(utf8.char(8212), "-"):gsub(utf8.char(8211), "-") end
		if type(name) ~= "string" or name:find("[^\032-\126]") then
			name = tostring(region.id)
		end
		regionNames[region.id] = name
	end

	function policy.describe(rawPlate)
		if type(rawPlate) ~= "table" then
			return { text = "Unknown plate", rarity = "UNKNOWN", quality = "UNKNOWN", price = 0, region = "Unknown region" }
		end
		local ok, text, rarity, quality, price, region = pcall(function()
			local value, details = Plate.price(rawPlate)
			return ascii(Plate.fullText(rawPlate)), details.tier, rawPlate.quality, value, regionNames[rawPlate.regionId] or tostring(rawPlate.regionId or "Unknown region")
		end)
		if not ok or not finite(price) or price <= 0 or not Plate.RARITY[rarity] then
			return { text = "Unknown plate", rarity = "UNKNOWN", quality = "UNKNOWN", price = 0, region = "Unknown region", uid = rawPlate.uid }
		end
		return { text = text, rarity = rarity, quality = quality, price = price, region = region, uid = rawPlate.uid }
	end

	local function matchesMask(text, mask)
		local fragments = { "^" }
		for index = 1, #mask do
			local character = mask:sub(index, index)
			if character == "*" then
				table.insert(fragments, ".*")
			elseif character == "?" then
				table.insert(fragments, ".")
			else
				table.insert(fragments, (character:gsub("(%W)", "%%%1")))
			end
		end
		table.insert(fragments, "$")
		return text:match(table.concat(fragments)) ~= nil
	end

	function policy.shouldSell(rawPlate, settings, protectedUids)
		if type(rawPlate) ~= "table" then
			return false, "Plate data unavailable"
		end
		if rawPlate.uid and protectedUids and protectedUids[rawPlate.uid] then
			return false, "Protected plate"
		end
		local description = policy.describe(rawPlate)
		local text, rarity, quality, price = description.text, description.rarity, description.quality, description.price
		if rarity == "UNKNOWN" then
			return false, "Plate data unavailable"
		end
		if not (settings.sellRarities or defaultRarities)[rarity] then
			return false, "Rarity protected"
		end
		if not (settings.sellQualities or defaultQualities)[quality] then
			return false, "Quality protected"
		end
		local ceiling = settings.maxSellPrice
		if ceiling == nil then
			ceiling = 10000
		end
		if not finite(ceiling) or ceiling < 0 then
			return false, "Invalid price limit"
		end
		if ceiling > 0 and price > ceiling then
			return false, "Above price limit"
		end
		local ok, features = pcall(Plate.features, rawPlate)
		if not ok or type(features) ~= "table" then
			return false, "Plate features unavailable"
		end
		local featureIds = {}
		for _, feature in features do
			if type(feature) ~= "table" or type(feature.id) ~= "string" then
				return false, "Plate features unavailable"
			end
			featureIds[feature.id] = true
		end
		if settings.keepSpecial ~= false and featureIds.series then
			return false, "Special series protected"
		end
		local number = rawPlate.num
		if not finite(number) or number % 1 ~= 0 or number < 0 or number > 999 then
			return false, "Invalid plate number"
		end
		local first = number // 100
		local middle = number // 10 % 10
		local last = number % 10
		if settings.keepTripleDigits ~= false and first == middle and middle == last then
			return false, "Triple digits protected"
		end
		if settings.keepTripleLetters ~= false and rawPlate.l1 == rawPlate.l2 and rawPlate.l2 == rawPlate.l3 then
			return false, "Triple letters protected"
		end
		if settings.keepMirrors ~= false and (featureIds.mir or first == last) then
			return false, "Mirror number protected"
		end
		if settings.keepLowNumbers ~= false and number <= 9 then
			return false, "Low number protected"
		end
		local patterns = settings.keepPatterns or ""
		if type(patterns) ~= "string" or #patterns > 2048 then
			return false, "Invalid keep patterns"
		end
		local plateOnly = ascii(Plate.text(rawPlate))
		local fullText = text:gsub("%s+", "")
		for mask in patterns:gmatch("[^,]+") do
			mask = ascii(mask):gsub("%s+", "")
			if #mask > 64 then
				return false, "Keep pattern too long"
			end
			if mask ~= "" and (matchesMask(plateOnly, mask) or matchesMask(fullText, mask)) then
				return false, "Keep pattern matched"
			end
		end
		return true, "Matched sale filters"
	end

	local function categoryOf(definition)
		if definition.kind == "special" then
			return "Luck"
		end
		if definition.feature == "garage" or definition.feature == "car" then
			return "Equipment"
		end
		return categoriesByStat[definition.stat] or "Unlocks"
	end

	local function specialAverage(effects)
		local factor = 1
		for id, interval in effects.special or {} do
			if finite(interval) and interval > 0 then
				factor += math.max(0, (effects.specialMult[id] or 1) - 1) / interval
			end
		end
		return factor
	end

	local function equipmentBonus(effects, luckValues)
		local total = 0
		local index = 1
		if effects.car and luckValues[1] then
			total = luckValues[1] * (Config.CarLuckMult or 2)
			index = 2
		end
		for _ = 1, effects.wallSlots do
			total += luckValues[index] or 0
			index += 1
		end
		return total
	end

	function policy.chooseUpgrade(state, settings)
		if type(state) ~= "table" or type(state.upgrades) ~= "table" then
			return nil
		end
		local budget = settings.upgradeBudget
		if not finite(budget) or budget <= 0 then
			return nil
		end
		local categories = settings.upgradeCategories or defaultCategories
		local strategy = settings.upgradeStrategy or "Balanced"
		local current = Upgrades.effects(state.upgrades)
		local inventory = state.inventory or {}
		local luckValues = {}
		for _, entry in inventory do
			local plate = entry.plate
			if plate and plate.reg ~= false and (not plate.paidUntil or plate.paidUntil > (state.now or 0)) then
				local ok, luck = pcall(Upgrades.plateLuck, plate)
				if ok and finite(luck) then
					table.insert(luckValues, luck)
				end
			end
		end
		table.sort(luckValues, function(left, right)
			return left > right
		end)
		local currentBonus = equipmentBonus(current, luckValues)
		local currentLuck = math.max(1, tonumber(state.luck) or current.treeLuck)
		local bestDefinition, bestCost, bestScore
		for _, definition in Upgrades.list do
			local category = categoryOf(definition)
			local level = Upgrades.level(state.upgrades, definition.id)
			local cost = Upgrades.cost(definition.id, level)
			if definition.start or not categories[category] or not finite(cost) or cost <= 0 or cost > budget then
				continue
			end
			if not Upgrades.unlocked(state.upgrades, definition.id) then
				continue
			end
			local changed = table.clone(state.upgrades)
			changed[definition.id] = level + 1
			local after = Upgrades.effects(changed)
			local gain = 0
			if category == "Luck" then
				gain = (after.treeLuck - current.treeLuck) / currentLuck
				gain += specialAverage(after) / specialAverage(current) - 1
			elseif category == "Speed" then
				gain = current.cooldown / after.cooldown - 1
			elseif category == "Batch" then
				gain = after.maxBatch / current.maxBatch - 1
			elseif category == "Equipment" then
				gain = (equipmentBonus(after, luckValues) - currentBonus) / currentLuck
				if definition.feature == "garage" then
					gain = math.max(0.02, gain)
				end
			elseif category == "Capacity" then
				local occupied = #inventory + #(state.listings or {})
				local pressure = math.clamp(occupied / math.max(1, current.slots), 0, 1)
				gain = (after.slots - current.slots) / math.max(1, current.slots) * math.max(0.02, pressure ^ 4)
			else
				gain = 0.01
			end
			if strategy == category then
				gain *= 4
			end
			local score = gain / cost
			if strategy == "Cheapest" then
				score = 1 / cost
			end
			if score > 0 and (not bestScore or score > bestScore or score == bestScore and cost < bestCost) then
				bestDefinition, bestCost, bestScore = definition, cost, score
			end
		end
		return bestDefinition, bestCost
	end

	return policy
end

local function createWebhook(app, HttpService, requestFunction)
	local service = {}
	local queue = {}
	local activeUrl = ""
	local observedUrl = nil
	local observedEnabled = false
	local generation = 0
	local inFlight = false
	local requestStartedAt = 0
	local stopped = false
	local nextSendAt = 0
	local lastSummaryAt = os.clock()
	local lastStatus = "Notifications are disabled."
	local sent = 0
	local dropped = 0
	local summaryBaseline = {}
	local colors = { COMMON = 9807270, UNCOMMON = 5763719, RARE = 3447003, EPIC = 10181046, MYTHIC = 15548997, LEGEND = 16766720 }

	local function number(value)
		local result = tonumber(value)
		if not result or result ~= result or math.abs(result) == math.huge then
			return 0
		end
		return result
	end

	local function text(value, limit)
		return tostring(value or "Unknown"):gsub("[%z\1-\8\11\12\14-\31]", ""):sub(1, limit or 1024)
	end

	local function snapshot()
		local session = app.session or {}
		return {
			rolls = number(session.rolls),
			sold = number(session.sold),
			kept = number(session.kept),
			upgrades = number(session.upgrades),
			revenue = number(session.revenue),
			moneySpent = number(session.moneySpent),
			upgradeSpent = number(session.upgradeSpent),
		}
	end

	local function endpoint(value)
		if type(value) ~= "string" then
			return nil
		end
		value = value:match("^%s*(.-)%s*$")
		local host, path = value:match("^https://([%w%.%-]+)(/[^%s]*)$")
		if host ~= "discord.com" and host ~= "canary.discord.com" and host ~= "ptb.discord.com" then
			return nil
		end
		path = path:gsub("%?wait=true$", ""):gsub("%?wait=false$", "")
		local id, token = path:match("^/api/webhooks/(%d+)/([%w_%-]+)$")
		if not id then
			id, token = path:match("^/api/v10/webhooks/(%d+)/([%w_%-]+)$")
		end
		if not id or #id < 5 or #token < 10 then
			return nil
		end
		return "https://" .. host .. "/api/webhooks/" .. id .. "/" .. token .. "?wait=true"
	end

	local function synchronize()
		local settings = app.settings
		local url = endpoint(settings.webhookUrl)
		local enabled = settings.webhook == true
		if settings.webhookUrl ~= observedUrl or enabled ~= observedEnabled then
			generation += 1
			dropped += #queue
			table.clear(queue)
			observedUrl = settings.webhookUrl
			observedEnabled = enabled
			activeUrl = url or ""
			lastSummaryAt = os.clock()
			summaryBaseline = snapshot()
			if type(requestFunction) ~= "function" then
				lastStatus = "This executor has no HTTP request function."
			elseif not enabled then
				lastStatus = "Notifications are disabled."
			elseif not url then
				lastStatus = "Enter a valid Discord webhook URL."
			else
				lastStatus = "Ready for matching drops."
			end
		end
		return url
	end

	local function payload(title, description, fields, color)
		return {
			username = "Plate Pilot",
			allowed_mentions = { parse = {} },
			embeds = { {
				title = text(title, 256),
				description = text(description, 4096),
				color = color or 3657150,
				fields = fields or {},
				footer = { text = "Plate Pilot" },
			} },
		}
	end

	local function enqueue(body, manual)
		if stopped or not app.alive then
			return false
		end
		local url = synchronize()
		if type(requestFunction) ~= "function" then
			lastStatus = "This executor has no HTTP request function."
			return false
		end
		if not url then
			lastStatus = "Enter a valid Discord webhook URL."
			return false
		end
		if not manual and not app.settings.webhook then
			return false
		end
		if #queue >= 20 then
			dropped += 1
			lastStatus = "Queue is full. One notification was skipped."
			return false
		end
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, body)
		if not ok then
			dropped += 1
			lastStatus = "Could not encode the notification."
			return false
		end
		table.insert(queue, {
			url = url,
			body = encoded,
			generation = generation,
			serverRetries = 0,
			rateRetries = 0,
			manual = manual == true,
		})
		lastStatus = "Notification queued."
		return true
	end

	local function pump()
		if stopped or not app.alive or inFlight or #queue == 0 or os.clock() < nextSendAt then
			return
		end
		local item = table.remove(queue, 1)
		if item.generation ~= generation or item.url ~= activeUrl or not item.manual and not app.settings.webhook then
			dropped += 1
			return
		end
		inFlight = true
		requestStartedAt = os.clock()
		lastStatus = "Sending notification."
		task.spawn(function()
			local ok, response = pcall(requestFunction, {
				Url = item.url,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = item.body,
				Timeout = 20,
			})
			inFlight = false
			if stopped or not app.alive or item.generation ~= generation then
				return
			end
			if not ok or type(response) ~= "table" then
				dropped += 1
				lastStatus = "Delivery is uncertain. Automatic retry was skipped."
				nextSendAt = os.clock() + 5
				return
			end
			local code = tonumber(response.StatusCode or response.Status)
			local headers = {}
			for key, value in response.Headers or {} do
				headers[tostring(key):lower()] = value
			end
			local resetAfter = number(headers["x-ratelimit-reset-after"])
			nextSendAt = os.clock() + 1
			if tonumber(headers["x-ratelimit-remaining"]) == 0 and resetAfter > 0 then
				nextSendAt = os.clock() + resetAfter + 0.25
			end
			if code and code >= 200 and code < 300 then
				sent += 1
				lastStatus = "Notification delivered."
			elseif code == 429 then
				local retryAfter = number(headers["retry-after"])
				local decodedOk, body = pcall(HttpService.JSONDecode, HttpService, response.Body or "")
				if decodedOk and type(body) == "table" and number(body.retry_after) > 0 then
					retryAfter = number(body.retry_after)
				end
				retryAfter = math.max(1, retryAfter, resetAfter)
				nextSendAt = os.clock() + retryAfter + 0.25
				item.rateRetries += 1
				if item.rateRetries <= 5 and #queue < 20 then
					table.insert(queue, 1, item)
					lastStatus = "Rate limited. Waiting " .. tostring(math.ceil(retryAfter)) .. " seconds."
				else
					dropped += 1
					lastStatus = "Rate-limit retry limit reached."
				end
			elseif code and code >= 500 and code <= 599 and item.serverRetries < 2 and #queue < 20 then
				item.serverRetries += 1
				nextSendAt = os.clock() + 2 ^ item.serverRetries
				table.insert(queue, 1, item)
				lastStatus = "Discord server error. A retry is scheduled."
			else
				dropped += 1
				lastStatus = code and "Delivery failed with HTTP " .. tostring(code) .. "." or "Delivery is uncertain. Automatic retry was skipped."
			end
		end)
	end

	function service.enqueueDrop(record)
		synchronize()
		if not app.settings.webhook or not app.settings.webhookRarities[record.rarity] or number(record.price) < number(app.settings.webhookMinPrice) then
			return false
		end
		return enqueue(payload("Plate drop", text(record.text, 100), {
			{ name = "Rarity", value = text(record.rarity), inline = true },
			{ name = "Condition", value = text(record.quality), inline = true },
			{ name = "Value", value = string.format("%.0f RUB", number(record.price)), inline = true },
			{ name = "Region", value = text(record.region), inline = true },
			{ name = "Outcome", value = text(record.outcome), inline = true },
		}, colors[record.rarity]), false)
	end

	function service.test()
		local accepted = enqueue(payload("Connection test", "Plate Pilot can send notifications to this channel."), true)
		if accepted then
			pump()
		end
		return accepted
	end

	function service.tick()
		if stopped or not app.alive then
			return
		end
		local url = synchronize()
		local interval = number(app.settings.webhookSummaryMinutes) * 60
		if app.settings.webhook and url and interval > 0 and os.clock() - lastSummaryAt >= interval then
			local current = snapshot()
			local delta = {}
			for key, value in current do
				delta[key] = value - (summaryBaseline[key] or 0)
			end
			local net = delta.revenue - delta.moneySpent - delta.upgradeSpent
			local queued = enqueue(payload("Session summary", "Recorded activity since the previous summary.", {
				{ name = "Rolls", value = tostring(delta.rolls), inline = true },
				{ name = "Sold", value = tostring(delta.sold), inline = true },
				{ name = "Kept", value = tostring(delta.kept), inline = true },
				{ name = "Upgrades", value = tostring(delta.upgrades), inline = true },
				{ name = "Recorded net cash flow", value = string.format("%+.0f RUB", net), inline = true },
				{ name = "Current balance", value = string.format("%.0f RUB", number(app.state and app.state.money)), inline = true },
			}), false)
			lastSummaryAt = os.clock()
			if queued then
				summaryBaseline = current
			end
		end
		pump()
	end

	function service.status()
		local message = lastStatus
		if inFlight and os.clock() - requestStartedAt >= 20 then
			message = "HTTP request is still pending. Waiting for completion."
		end
		return message .. string.format("\nSent %d | Queued %d | Skipped %d", sent, #queue, dropped)
	end

	function service.clearPending()
		synchronize()
		generation += 1
		dropped += #queue
		table.clear(queue)
		lastSummaryAt = os.clock()
		summaryBaseline = snapshot()
		lastStatus = "Notifications are disabled."
	end

	function service.destroy()
		stopped = true
		generation += 1
		table.clear(queue)
		activeUrl = ""
		observedUrl = nil
	end

	summaryBaseline = snapshot()
	synchronize()
	return service
end

local function createConfig(app, HttpService, environment, fileApi, path)
	local service = {}
	local active, closed, closing = false, false, false
	local owner = {}
	if type(environment.PlatePilotConfigs) ~= "table" then environment.PlatePilotConfigs = {} end
	local slot = environment.PlatePilotConfigs[path]
	if type(slot) ~= "table" then
		slot = { revision = 0, writing = false, pending = false }
		environment.PlatePilotConfigs[path] = slot
	end
	slot.owner = owner
	slot.write = type(fileApi.write) == "function" and fileApi.write or nil
	slot.read = type(fileApi.read) == "function" and fileApi.read or nil
	local function decode(value)
		if type(value) ~= "string" or #value == 0 or #value > 65536 then return nil end
		local ok, envelope = pcall(HttpService.JSONDecode, HttpService, value)
		if ok and type(envelope) == "table" and envelope.version == 1 and type(envelope.settings) == "table" then
			return envelope.settings
		end
		return nil
	end
	local function read(target)
		if not slot.read then return nil end
		local ok, value = pcall(slot.read, target)
		if ok and decode(value) then return value end
		return nil
	end
	local function write(target, value)
		local ok, result = pcall(slot.write, target, value)
		return ok and result ~= false
	end
	local function cancelScheduled()
		if slot.scheduled then pcall(task.cancel, slot.scheduled) slot.scheduled = nil end
	end
	local function capture()
		local settings = table.clone(app.settings)
		settings.roll, settings.sell = false, false
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, { version = 1, settings = settings })
		if not ok or not decode(encoded) then
			slot.message = "Could not encode settings. The previous saved configuration was preserved."
			return false
		end
		if encoded ~= slot.snapshot then
			slot.snapshot = encoded
			slot.revision = (tonumber(slot.revision) or 0) + 1
		end
		return true
	end
	local function drain()
		if slot.writing then return end
		slot.writing = true
		while slot.pending do
			slot.pending = false
			local snapshot, revision = slot.snapshot, slot.revision
			if not decode(snapshot) then
				slot.message = "Invalid configuration was not written."
			elseif not slot.write then
				slot.message = "Settings are saved for this executor session. File writing is unavailable."
			else
				if not slot.baselineKnown then
					slot.persisted = read(path)
					slot.baselineKnown = slot.read ~= nil
				end
				local ok = true
				if slot.persisted ~= snapshot then
					if decode(slot.persisted) then ok = write(path .. ".bak", slot.persisted) end
					if ok and revision == slot.revision then
						ok = write(path, snapshot)
						if ok then slot.persisted = snapshot slot.baselineKnown = true end
					end
				end
				if not ok then
					slot.message = "File saving failed. Settings are retained for this executor session."
				elseif slot.persisted == snapshot then
					slot.message = slot.read and "Settings are saved automatically." or "Settings were saved. File reading is unavailable in this executor."
				end
			end
			if revision ~= slot.revision then slot.pending = true end
		end
		slot.writing = false
	end
	local function schedule()
		cancelScheduled()
		slot.pending = true
		slot.scheduled = task.delay(0.5, function()
			slot.scheduled = nil
			drain()
		end)
	end
	local function flushSnapshot()
		if not capture() then return false end
		cancelScheduled()
		slot.pending = true
		drain()
		return true
	end
	function service.load()
		if closed or closing or active or slot.owner ~= owner then return false end
		local settings = decode(slot.snapshot)
		if not settings then
			local main = read(path)
			slot.persisted = main
			slot.baselineKnown = slot.read ~= nil
			settings = decode(main) or decode(read(path .. ".bak"))
		end
		if settings then
			for key, value in settings do
				if type(key) == "string" and key ~= "roll" and key ~= "sell" then pcall(app.set, key, value) end
			end
		end
		app.set("roll", false)
		app.set("sell", false)
		slot.message = "Settings loaded. Auto Roll and Auto Sell are off."
		return true
	end
	function service.start()
		if closed or closing or active or slot.owner ~= owner then return false end
		active = true
		if not capture() then return false end
		schedule()
		return true
	end
	function service.changed()
		if closed or closing or not active or slot.owner ~= owner then return false end
		if not capture() then return false end
		schedule()
		return true
	end
	function service.flush()
		if closed or closing or not active or slot.owner ~= owner then return false end
		return flushSnapshot()
	end
	function service.close()
		if closed or closing then return end
		closing = true
		if active and slot.owner == owner then flushSnapshot() end
		closed = true
		closing = false
	end
	function service.status()
		return slot.message or "Settings have not been loaded."
	end
	return service
end

local function createCredits(app, httpRequest)
	local service = { loading = true }
	local finished = false
	local worker, watchdog
	local function finish(value)
		if finished then return end
		finished = true
		service.loading = false
		if app.alive then service.text = value end
		if watchdog then pcall(task.cancel, watchdog) watchdog = nil end
	end
	local function clean(value)
		if type(value) ~= "string" then return nil end
		value = value:gsub("^\239\187\191", ""):match("^%s*(.-)%s*$")
		if #value == 0 or #value > 2048 or value:find("[%z\1-\8\11\12\14-\31]") then return nil end
		return value
	end
	worker = task.defer(function()
		if not app.alive then finish(nil) return end
		local url = "https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram?run=" .. os.time() .. "." .. math.floor(os.clock() * 1000)
		local value
		if type(httpRequest) == "function" then
			local ok, response = pcall(httpRequest, {
				Url = url,
				Method = "GET",
				Headers = { ["Accept"] = "text/plain", ["Cache-Control"] = "no-cache" },
				Timeout = 10,
			})
			if ok and type(response) == "table" then
				local status = tonumber(response.StatusCode or response.Status)
				if status and status >= 200 and status < 300 then value = clean(response.Body or response.body) end
			end
		end
		if not value and app.alive and not finished then
			local ok, body = pcall(function() return game:HttpGet(url, true) end)
			if ok then value = clean(body) end
		end
		finish(value)
	end)
	watchdog = task.delay(15, function()
		watchdog = nil
		if finished then return end
		finish(nil)
		if worker then pcall(task.cancel, worker) worker = nil end
	end)
	function service.destroy()
		finish(nil)
		if worker then pcall(task.cancel, worker) worker = nil end
	end
	return service
end

local function createUI(app, WindUI)
	local Workspace = game:GetService("Workspace")
	local ui = { toggles = {} }
	local settings = app.settings
	local featureKeys = { roll = true, sell = true, upgrades = true, equip = true, antiAfk = true, webhook = true, rollHistory = true }
	local theme = table.clone(WindUI.Themes.Dark)
	theme.Name = "Plate Pilot"
	theme.Accent = Color3.fromHex("172326")
	theme.Background = Color3.fromHex("10191C")
	theme.Dialog = Color3.fromHex("1D2B2F")
	theme.Text = Color3.fromHex("EDF5F4")
	theme.Icon = Color3.fromHex("AFBFBD")
	theme.ElementBackground = Color3.fromHex("223034")
	theme.Primary = Color3.fromHex("49C9B5")
	theme.Toggle = theme.Primary
	theme.Slider = theme.Primary
	theme.Checkbox = theme.Primary
	theme.TabBackgroundActive = theme.Primary
	theme.TabBackgroundActiveTransparency = 0.85
	WindUI:AddTheme(theme)
	WindUI:SetLanguage("en")
	local window = WindUI:CreateWindow({
		Title = "Plate Pilot",
		Folder = "PlatePilot",
		Icon = "car",
		Theme = theme.Name,
		Size = UDim2.fromOffset(680, 520),
		MinSize = Vector2.new(300, 250),
		MaxSize = Vector2.new(900, 800),
		SideBarWidth = 155,
		Resizable = true,
		AutoScale = false,
		Acrylic = false,
		Transparent = false,
		NewElements = false,
		HideSearchBar = true,
		ScrollBarEnabled = true,
		ToggleKey = Enum.KeyCode.RightShift,
		OpenButton = {
			Title = "Plate Pilot",
			Icon = "car",
			Enabled = true,
			OnlyMobile = false,
			Draggable = true,
			Scale = 1,
			Position = UDim2.new(0.5, 0, 0, 72),
			CornerRadius = UDim.new(1, 0),
			StrokeThickness = 1,
			Color = ColorSequence.new(theme.Primary),
		},
	})
	ui.window = window
	local tabs = {}
	for _, definition in {
		{ "Roll", "dices" },
		{ "Sell", "coins" },
		{ "Upgrades", "trending-up" },
		{ "Journal", "notebook-text" },
		{ "Webhook", "bell" },
		{ "Settings", "settings" },
	} do
		tabs[definition[1]] = window:Tab({ Title = definition[1], Icon = definition[2] })
	end
	local function toggle(tab, key, title, description)
		local control = tab:Toggle({
			Title = title,
			Desc = description,
			Value = settings[key] == true,
			Callback = function(value)
				app.set(key, value)
			end,
		})
		if featureKeys[key] then
			ui.toggles[key] = control
		end
		return control
	end
	local function selectValue(tab, key, title, values, description)
		return tab:Dropdown({
			Title = title,
			Desc = description,
			Values = values,
			Value = settings[key],
			AllowNone = false,
			Callback = function(value)
				app.set(key, value)
			end,
		})
	end
	local function selectSet(tab, key, title, definitions, description)
		local values, selected, keys = {}, {}, {}
		for _, definition in definitions do
			local label, id = definition[1], definition[2]
			table.insert(values, label)
			keys[label] = id
			if settings[key][id] then
				table.insert(selected, label)
			end
		end
		return tab:Dropdown({
			Title = title,
			Desc = description,
			Values = values,
			Value = selected,
			Multi = true,
			AllowNone = true,
			Callback = function(selection)
				local enabled = {}
				for _, label in selection do
					if keys[label] then
						enabled[keys[label]] = true
					end
				end
				app.set(key, enabled)
			end,
		})
	end
	local function input(tab, key, title, description, numeric, placeholder)
		local control
		local resetting = false
		control = tab:Input({
			Title = title,
			Desc = description,
			Value = tostring(settings[key]),
			Placeholder = placeholder or "Enter a value",
			ClearTextOnFocus = false,
			Callback = function(text)
				if resetting or text == tostring(settings[key]) then
					return
				end
				local value = if numeric then tonumber(text) else text
				local accepted = value ~= nil and app.set(key, value)
				if not accepted and control then
					resetting = true
					control:Set(tostring(settings[key]))
					resetting = false
				end
			end,
		})
		return control
	end
	local function button(tab, title, action, description)
		return tab:Button({
			Title = title,
			Desc = description,
			Callback = function()
				app.action(action)
			end,
		})
	end
	local rarities = {
		{ "Common", "COMMON" },
		{ "Uncommon", "UNCOMMON" },
		{ "Rare", "RARE" },
		{ "Epic", "EPIC" },
		{ "Mythic", "MYTHIC" },
		{ "Legendary", "LEGEND" },
	}
	toggle(tabs.Roll, "roll", "Auto Roll")
	toggle(tabs.Roll, "equip", "Auto Equip Best")
	local selectedRegions = {}
	local selectedIds = {}
	for _, id in settings.regions do
		selectedIds[id] = true
	end
	for _, label in app.regionOptions do
		if selectedIds[app.regionLabels[label]] then
			table.insert(selectedRegions, label)
		end
	end
	tabs.Roll:Dropdown({
		Title = "Regions",
		Values = app.regionOptions,
		Value = selectedRegions,
		Multi = true,
		AllowNone = false,
		SearchBarEnabled = true,
		MenuWidth = 230,
		Callback = function(selection)
			local ids = {}
			for _, label in selection do
				local id = app.regionLabels[label]
				if id then
					table.insert(ids, id)
				end
			end
			if #ids > 0 then
				app.set("regions", ids)
			end
		end,
	})
	selectValue(tabs.Roll, "regionMode", "Region strategy", { "Rotate", "Best value" }, "Best value compares region multiplier against roll cost.")
	selectValue(tabs.Roll, "batch", "Plates per roll", { "Maximum", "1", "2", "3", "4" })
	input(tabs.Roll, "reserveMoney", "Minimum balance (RUB)", nil, true)
	tabs.Roll:Slider({
		Title = "Extra delay (seconds)",
		Desc = "Added to the server cooldown.",
		Step = 0.05,
		Value = { Min = 0.05, Max = 2, Default = settings.delayPadding },
		Callback = function(value)
			app.set("delayPadding", value)
		end,
	})
	selectValue(tabs.Roll, "stopRarity", "Stop at rarity or higher", { "Disabled", "Epic", "Mythic", "Legendary" })
	button(tabs.Roll, "Roll once", "rollOnce")
	toggle(tabs.Sell, "sell", "Auto Sell", "All filters must match. Protected plates are kept.")
	selectSet(tabs.Sell, "sellRarities", "Sell rarities", rarities)
	selectSet(tabs.Sell, "sellQualities", "Sell conditions", {
		{ "Mint", "NEW" }, { "Good", "GOOD" }, { "Used", "USED" }, { "Worn", "WORN" }, { "Wrecked", "BAD" },
	})
	input(tabs.Sell, "maxSellPrice", "Maximum sell value (RUB)", "0 removes the price limit.", true)
	toggle(tabs.Sell, "keepSpecial", "Keep special series")
	toggle(tabs.Sell, "keepTripleDigits", "Keep triple digits")
	toggle(tabs.Sell, "keepTripleLetters", "Keep triple letters")
	toggle(tabs.Sell, "keepMirrors", "Keep mirror numbers (121)")
	toggle(tabs.Sell, "keepLowNumbers", "Keep 001 to 009")
	input(tabs.Sell, "keepPatterns", "Keep plate patterns", "Separate masks with commas. * matches any text, ? matches one character.", false, "A777*, *007*, *77")
	toggle(tabs.Sell, "protectEquipped", "Keep equipped plates")
	toggle(tabs.Sell, "protectBest", "Keep best plates", "Protects the strongest plates for available wall and car slots.")
	toggle(tabs.Sell, "sellExisting", "Include existing inventory")
	toggle(tabs.Upgrades, "upgrades", "Auto Upgrades")
	selectSet(tabs.Upgrades, "upgradeCategories", "Upgrade categories", {
		{ "Luck", "Luck" }, { "Speed", "Speed" }, { "Batch", "Batch" }, { "Capacity", "Capacity" }, { "Equipment", "Equipment" },
	})
	selectValue(tabs.Upgrades, "upgradeStrategy", "Upgrade strategy", { "Balanced", "Cheapest", "Luck", "Speed" }, "Balanced compares estimated benefit against cost.")
	tabs.Upgrades:Slider({
		Title = "Spending limit",
		Desc = "Percentage available per purchase after reserving money and the next roll.",
		Step = 1,
		Value = { Min = 1, Max = 100, Default = settings.upgradeSpendPercent },
		Callback = function(value)
			app.set("upgradeSpendPercent", value)
		end,
	})
	ui.history = toggle(tabs.Journal, "rollHistory", "Roll history")
	input(tabs.Journal, "logSearch", "Search journal", nil, false, "Plate or region")
	selectValue(tabs.Journal, "logRarity", "Rarity", { "All", "Common", "Uncommon", "Rare", "Epic", "Mythic", "Legendary" })
	ui.log = tabs.Journal:Paragraph({ Title = "Roll history", Desc = "Your next roll will appear here." })
	button(tabs.Journal, "Export journal", "exportLog")
	button(tabs.Journal, "Clear journal", "clearLog")
	ui.stats = tabs.Journal:Paragraph({ Title = "This session", Desc = "Waiting for game state." })
	ui.status = tabs.Journal:Paragraph({ Title = "Status", Desc = "Ready" })
	button(tabs.Journal, "Refresh game state", "refresh")
	toggle(tabs.Webhook, "webhook", "Webhook Notify")
	input(tabs.Webhook, "webhookUrl", "Webhook URL", nil, false, "https://discord.com/api/webhooks/...")
	selectSet(tabs.Webhook, "webhookRarities", "Notify rarities", rarities)
	input(tabs.Webhook, "webhookMinPrice", "Minimum drop value (RUB)", nil, true)
	input(tabs.Webhook, "webhookSummaryMinutes", "Summary interval (minutes)", "0 disables summaries.", true)
	ui.webhookStatus = tabs.Webhook:Paragraph({ Title = "Delivery status", Desc = "Add a webhook URL, then send a test notification." })
	button(tabs.Webhook, "Send test notification", "testWebhook")
	toggle(tabs.Settings, "antiAfk", "Anti AFK")
	button(tabs.Settings, "Stop All", "stop")
	button(tabs.Settings, "Unload UI", "unload")
	tabs.Settings:Section({ Title = "Credits" })
	button(tabs.Settings, "Arceus X Scripts", "copyArceus")
	button(tabs.Settings, "WindUI Library", "copyWindUI")
	local narrow = false
	local navigationOpen = false
	local menuButton
	local function layoutNavigation()
		local isNarrow = window.UIElements.Main.AbsoluteSize.X < 560
		if isNarrow ~= narrow then navigationOpen = false end
		narrow = isNarrow
		local sidebar = window.UIElements.SideBarContainer
		local main = window.UIElements.MainBar
		sidebar.Visible = not narrow or navigationOpen
		sidebar.Size = UDim2.new(narrow and 1 or 0, narrow and 0 or 155, 1, -window.Topbar.Height)
		main.Visible = not narrow or not navigationOpen
		main.Size = UDim2.new(1, narrow and 0 or -155, 1, -window.Topbar.Height)
		if menuButton then
			menuButton.Visible = narrow
		end
	end
	menuButton = window:CreateTopbarButton("Navigation", "menu", function()
		navigationOpen = not navigationOpen
		layoutNavigation()
	end, -10)
	app.connect(window.UIElements.Main:GetPropertyChangedSignal("AbsoluteSize"), layoutNavigation)
	window.TabModule:OnChange(function()
		navigationOpen = false
		layoutNavigation()
	end)
	local floating = window.OpenButtonMain.Button.Parent
	local clampPending = false
	local function clampFloatingButton()
		if clampPending or window.Destroyed or not floating.Visible then
			return
		end
		clampPending = true
		task.defer(function()
			local camera = Workspace.CurrentCamera
			if camera and not window.Destroyed and floating.Visible then
				local viewport = camera.ViewportSize
				local absolute = floating.AbsolutePosition
				local size = floating.AbsoluteSize
				local targetX = math.clamp(absolute.X, 8, math.max(8, viewport.X - size.X - 8))
				local targetY = math.clamp(absolute.Y, 48, math.max(48, viewport.Y - size.Y - 8))
				local deltaX = targetX - absolute.X
				local deltaY = targetY - absolute.Y
				if math.abs(deltaX) > 0.5 or math.abs(deltaY) > 0.5 then
					local position = floating.Position
					floating.Position = UDim2.new(position.X.Scale, position.X.Offset + deltaX, position.Y.Scale, position.Y.Offset + deltaY)
				end
			end
			clampPending = false
		end)
	end
	app.connect(floating:GetPropertyChangedSignal("AbsolutePosition"), clampFloatingButton)
	app.connect(floating:GetPropertyChangedSignal("AbsoluteSize"), clampFloatingButton)
	app.connect(floating:GetPropertyChangedSignal("Visible"), clampFloatingButton)
	local function fitViewport()
		local camera = Workspace.CurrentCamera
		if not camera or window.Destroyed then
			return
		end
		local viewport = camera.ViewportSize
		navigationOpen = false
		local width = math.max(280, math.min(680, viewport.X - 24))
		local height = math.max(220, math.min(560, viewport.Y - 96))
		local size = UDim2.fromOffset(width, height)
		if window.Closed then
			window.Size = size
		else
			window:SetSize(size)
		end
		window:SetUIScale(1)
		window:SetToTheCenter()
		layoutNavigation()
		floating.Position = UDim2.new(0.5, 0, 0, 72)
		clampFloatingButton()
	end
	local viewportConnection
	local function watchCamera()
		if viewportConnection then
			viewportConnection:Disconnect()
		end
		local camera = Workspace.CurrentCamera
		if camera then
			viewportConnection = app.connect(camera:GetPropertyChangedSignal("ViewportSize"), fitViewport)
		end
		fitViewport()
	end
	app.connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera)
	window:OnDestroy(function()
		app.destroy(false)
	end)
	watchCamera()
	tabs.Roll:Select()
	return ui
end

local function loadWindUI(httpRequest)
	if type(loadstring) ~= "function" then
		error("This executor does not support loadstring.")
	end
	local function bounded(operation, label)
		local finished = false
		local result
		local deadline = os.clock() + 15
		local worker = task.spawn(function()
			result = table.pack(pcall(operation))
			finished = true
		end)
		while not finished and os.clock() < deadline do
			task.wait(0.05)
		end
		if not finished then
			pcall(task.cancel, worker)
			error(label .. " timed out after 15 seconds.")
		end
		if not result[1] then
			error(label .. " failed: " .. tostring(result[2]))
		end
		return result[2]
	end
	local function fetch(url, label)
		return bounded(function()
			if type(httpRequest) == "function" then
				local ok, response = pcall(httpRequest, {
					Url = url,
					Method = "GET",
					Headers = { ["Accept"] = "text/plain" },
					Timeout = 15,
				})
				if ok and type(response) == "table" then
					local status = tonumber(response.StatusCode or response.Status)
					local body = response.Body or response.body
					if status and status >= 200 and status < 300 and type(body) == "string" and #body >= 20 then
						return (body:gsub("\r\n", "\n"))
					end
				end
			end
			local body = game:HttpGet(url, true)
			if type(body) ~= "string" or #body < 20 then
				error("Empty library download.")
			end
			return (body:gsub("\r\n", "\n"))
		end, label)
	end
	local function compile(source, name)
		local chunk, message = loadstring(source, name)
		if not chunk then
			error(name .. " could not be compiled: " .. tostring(message))
		end
		return chunk
	end
	local iconRoot = "https://raw.githubusercontent.com/Footagesus/Icons/46d30c19ba7bc601d6ec794a48dc3a89568b1eec/"
	local iconSource = fetch(iconRoot .. "Main-v2.lua", "Icon module download")
	local lucideSource = fetch(iconRoot .. "lucide/dist/Icons.lua", "Icon data download")
	local windSource = fetch("https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua", "WindUI download")
	local iconStart = iconSource:find("\n\tIcons = {", 1, true)
	local iconEnd = iconStart and iconSource:find("\n}\n\nlocal function parseIconString", iconStart, true)
	if not iconStart or not iconEnd then
		error("The pinned icon module has an unexpected format.")
	end
	iconSource = iconSource:sub(1, iconStart - 1)
		.. "\n\tIcons = {lucide = iconData},"
		.. iconSource:sub(iconEnd)
	local windIconStart = windSource:find("local m\nif d:IsStudio()or not writefile then", 1, true)
	local windIconEnd = windIconStart and windSource:find('\nm.SetIconsType"lucide"', windIconStart, true)
	if not windIconStart or not windIconEnd then
		error("The pinned WindUI module has an unexpected format.")
	end
	windSource = windSource:sub(1, windIconStart - 1)
		.. "local m=iconModule\n"
		.. windSource:sub(windIconEnd)
	windSource = windSource:gsub("an%.InputBegan:Connect%(", "aa.Creator.AddSignal(an.InputBegan,", 1)
	windSource = windSource:gsub("an%.InputEnded:Connect%(", "aa.Creator.AddSignal(an.InputEnded,", 1)
	return bounded(function()
		local lucide = compile(lucideSource, "PlatePilotLucide")()
		if type(lucide) ~= "table" then
			error("Invalid icon data.")
		end
		local icons = compile("return function(iconData)\n" .. iconSource .. "\nend", "PlatePilotIcons")()(lucide)
		local library = compile(
			"return function(iconModule)\nlocal writefile=nil\n" .. windSource .. "\nend",
			"PlatePilotWindUI"
		)()(icons)
		if type(library) ~= "table" or type(library.CreateWindow) ~= "function" then
			error("WindUI did not return a valid library.")
		end
		return library
	end, "WindUI initialization")
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local environment = type(getgenv) == "function" and getgenv() or _G
local previous = environment.PlatePilot
if previous then
	previous.destroy(true)
	local deadline = os.clock() + 15
	while previous.pending and not previous.pending.done and os.clock() < deadline do task.wait(0.1) end
	if previous.pending and not previous.pending.done then
		warn("Plate Pilot: a previous server request is unresolved. Rejoin before restarting.")
		return
	end
	task.wait(0.5)
end
if game.PlaceId ~= 138578132401096 then
	warn("Plate Pilot: join License Plate Generator before running this script.")
	return
end
if type(loadstring) ~= "function" then
	warn("Plate Pilot requires an executor with loadstring and HTTP support.")
	return
end
local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
local shared = ReplicatedStorage:WaitForChild("Shared", 15)
if not remotes or not shared then warn("Plate Pilot: game data did not load.") return end
local modulesOk, modules = pcall(function()
	return {
		Config = require(shared:WaitForChild("Config", 10)),
		Plate = require(shared:WaitForChild("Plate", 10)),
		Upgrades = require(shared:WaitForChild("Upgrades", 10)),
		English = require(shared:WaitForChild("LangEN", 10)),
		Events = require(shared:WaitForChild("Events", 10)),
	}
end)
if not modulesOk then warn("Plate Pilot: game modules are unavailable.") return end
local Config, Plate, Upgrades = modules.Config, modules.Plate, modules.Upgrades
local policy = createPolicy(Plate, Upgrades, Config, modules.English)
local httpRequest = request or http_request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)
local app = {
	alive = true,
	connections = {},
	state = nil,
	stateAt = 0,
	stateRevision = 0,
	journal = {},
	owned = {},
	seen = {},
	seenOrder = {},
	saleBlocked = {},
	activity = "Ready. Choose filters before starting automation.",
	statusText = "Loading state",
	regionOptions = { "Any region" },
	regionLabels = { ["Any region"] = "ANY" },
	session = { started = os.clock(), rolls = 0, batches = 0, moneySpent = 0, revenue = 0, kept = 0, sold = 0, upgrades = 0, upgradeSpent = 0 },
	settings = {
		roll = false, sell = false, upgrades = false, equip = false, antiAfk = true, webhook = false,
		regions = { "ANY" }, regionMode = "Rotate", batch = "Maximum", reserveMoney = 2500,
		delayPadding = 0.15, stopRarity = "Disabled",
		sellRarities = { COMMON = true }, sellQualities = { NEW = true, GOOD = true, USED = true, WORN = true, BAD = true },
		maxSellPrice = 10000, keepSpecial = true, keepTripleDigits = true, keepTripleLetters = true,
		keepMirrors = true, keepLowNumbers = true, keepPatterns = "", sellExisting = false,
		protectEquipped = true, protectBest = true,
		upgradeCategories = { Luck = true, Speed = true, Batch = true, Capacity = true, Equipment = true },
		upgradeStrategy = "Balanced", upgradeSpendPercent = 30,
		rollHistory = true, logSearch = "", logRarity = "All", webhookUrl = "",
		webhookRarities = { EPIC = true, MYTHIC = true, LEGEND = true }, webhookMinPrice = 0,
		webhookSummaryMinutes = 10,
	},
}
environment.PlatePilot = app
local ui, webhook
local nextRoll, nextUpgrade, nextEquip, nextSell, nextRefresh = 0, 0, 0, 0, 0
local rotation, rollErrors = 0, 0
local manualRoll = false
local equipSignature = ""
local rarityNames = { COMMON = "Common", UNCOMMON = "Uncommon", RARE = "Rare", EPIC = "Epic", MYTHIC = "Mythic", LEGEND = "Legendary" }
local rarityRanks = { COMMON = 1, UNCOMMON = 2, RARE = 3, EPIC = 4, MYTHIC = 5, LEGEND = 6, Epic = 4, Mythic = 5, Legendary = 6 }

local function money(value)
	local text = tostring(math.floor(tonumber(value) or 0))
	local sign = text:sub(1, 1) == "-" and "-" or ""
	text = text:gsub("^-", "")
	return sign .. text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. " RUB"
end

function app.connect(signal, callback)
	local connection = signal:Connect(function(...)
		if app.alive then callback(...) end
	end)
	table.insert(app.connections, connection)
	return connection
end

function app.setActivity(text)
	app.activity = text
end

function app.notify(title, text)
	if app.library then
		pcall(function() app.library:Notify({ Title = title, Content = text, Duration = 5 }) end)
	else
		pcall(function() StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 5 }) end)
	end
end

local function stop()
	for _, key in { "roll", "sell", "upgrades", "equip", "rollHistory", "webhook" } do
		app.settings[key] = false
		if ui and ui.toggles[key] then ui.toggles[key]:Set(false, false) end
	end
	manualRoll = false
	if webhook then webhook.clearPending() end
	if app.alive and app.config then app.config.changed() end
end

function app.destroy(destroyWindow)
	if not app.alive then return end
	if app.config then app.config.close() end
	app.alive = false
	stop()
	for _, connection in app.connections do connection:Disconnect() end
	table.clear(app.connections)
	if webhook then webhook.destroy() end
	if app.credits then app.credits.destroy() end
	if destroyWindow and ui and ui.window then pcall(function() ui.window:Destroy() end) end
end

local function mergeState(incoming)
	if type(incoming) ~= "table" or type(incoming.money) ~= "number" then return false end
	local state = table.clone(incoming)
	local old = app.state
	if state.sameInventory then
		state.inventory = state.rawInventory or (old and old.inventory)
	else
		state.inventory = state.rawInventory or state.inventory
	end
	for _, key in { "regions", "anyRegionCost", "cheapestRoll", "popular", "persistent" } do
		if state[key] == nil and old then state[key] = old[key] end
	end
	if type(state.inventory) ~= "table" or type(state.upgrades) ~= "table" then return false end
	state.inventory = table.clone(state.inventory)
	app.state = state
	app.stateAt = os.clock()
	app.stateRevision += 1
	return true
end

local function invoke(name, ...)
	if not app.alive or app.fault then return nil end
	if app.pending and not app.pending.done then return nil end
	local remote = remotes:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteFunction") then
		app.fault = true
		stop()
		app.setActivity("Game interface changed. Missing operation " .. name .. ".")
		return nil
	end
	local pending = { done = false, started = os.clock() }
	app.pending = pending
	local arguments = table.pack(...)
	task.spawn(function()
		pending.ok, pending.result = pcall(function() return remote:InvokeServer(table.unpack(arguments, 1, arguments.n)) end)
		pending.done = true
	end)
	while app.alive and not pending.done and os.clock() - pending.started < 12 do task.wait(0.05) end
	if not app.alive then return nil end
	if not pending.done or not pending.ok then
		app.fault = true
		stop()
		app.statusText = "Connection paused"
		app.setActivity("Request outcome is uncertain. Wait, then use Refresh state before restarting.")
		return nil
	end
	return pending.result
end

local function refresh()
	local revision = app.stateRevision
	local response = invoke("GetState")
	if not app.alive then return false end
	if response and revision == app.stateRevision then return mergeState(response) end
	return response ~= nil and app.state ~= nil
end

local stateEvent = remotes:FindFirstChild("StateChanged")
if stateEvent then app.connect(stateEvent.OnClientEvent, mergeState) end
if not refresh() then
	app.destroy(false)
	warn("Plate Pilot: unable to load a valid game state.")
	return
end
app.session.startBalance = app.state.money

local regionById = {}
for _, region in Config.Regions do regionById[region.id] = region end
for _, region in app.state.regions or {} do
	local definition = regionById[region.id] or region
	local name = modules.English[definition.name] or definition.name or region.id
	local label = region.id .. " - " .. name .. " (" .. money(region.cost) .. ")"
	app.regionLabels[label] = region.id
	table.insert(app.regionOptions, label)
end

local numericSettings = {
	reserveMoney = { 0, 1e15 }, delayPadding = { 0.05, 2 }, maxSellPrice = { 0, 1e15 },
	upgradeSpendPercent = { 1, 100 }, webhookMinPrice = { 0, 1e15 }, webhookSummaryMinutes = { 0, 1440 },
}
local choiceSettings = {
	regionMode = { Rotate = true, ["Best value"] = true },
	batch = { Maximum = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true },
	stopRarity = { Disabled = true, Epic = true, Mythic = true, Legendary = true },
	upgradeStrategy = { Balanced = true, Cheapest = true, Luck = true, Speed = true },
	logRarity = { All = true, Common = true, Uncommon = true, Rare = true, Epic = true, Mythic = true, Legendary = true },
}
local setSettings = {
	sellRarities = { COMMON = true, UNCOMMON = true, RARE = true, EPIC = true, MYTHIC = true, LEGEND = true },
	webhookRarities = { COMMON = true, UNCOMMON = true, RARE = true, EPIC = true, MYTHIC = true, LEGEND = true },
	sellQualities = { NEW = true, GOOD = true, USED = true, WORN = true, BAD = true },
	upgradeCategories = { Luck = true, Speed = true, Batch = true, Capacity = true, Equipment = true },
}
function app.set(key, value)
	if not app.alive or type(key) ~= "string" or app.settings[key] == nil then return false end
	local current = app.settings[key]
	local limits = numericSettings[key]
	if limits then
		if type(value) ~= "number" and type(value) ~= "string" then return false end
		value = tonumber(value)
		if not value or value ~= value or value < limits[1] or value > limits[2] then return false end
	elseif type(current) == "boolean" then
		if type(value) ~= "boolean" then return false end
	elseif choiceSettings[key] then
		if type(value) ~= "string" or not choiceSettings[key][value] then return false end
	elseif key == "regions" then
		if type(value) ~= "table" then return false end
		local count = 0
		for index in value do
			if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > 128 then return false end
			count += 1
		end
		if count ~= #value then return false end
		local valid, selected = {}, {}
		for _, id in ipairs(value) do
			if type(id) ~= "string" and type(id) ~= "number" then return false end
			if (id == "ANY" or regionById[id]) and not selected[id] then
				selected[id] = true
				table.insert(valid, id)
			end
		end
		if #valid == 0 then valid = { "ANY" } end
		value = valid
	elseif setSettings[key] then
		if type(value) ~= "table" then return false end
		local valid, count = {}, 0
		for id, enabled in value do
			count += 1
			if count > 64 or type(id) ~= "string" then return false end
			if setSettings[key][id] then
				if type(enabled) ~= "boolean" then return false end
				if enabled then valid[id] = true end
			end
		end
		value = valid
	elseif type(current) == "string" then
		if type(value) ~= "string" or #value > (key == "webhookUrl" and 2048 or 500) or value:find("[%z\1-\8\11\12\14-\31]") then return false end
	else
		return false
	end
	local unchanged = current == value
	if type(current) == "table" and type(value) == "table" then
		unchanged = true
		for id, entry in current do if value[id] ~= entry then unchanged = false break end end
		if unchanged then
			for id, entry in value do if current[id] ~= entry then unchanged = false break end end
		end
	end
	if unchanged then return true end
	app.settings[key] = value
	if key == "equip" then equipSignature = "" end
	if key == "sell" or key == "sellExisting" or key:sub(1, 4) == "keep" then table.clear(app.saleBlocked) end
	if app.config then app.config.changed() end
	return true
end

app.config = createConfig(app, HttpService, environment, { read = readfile, write = writefile }, "PlatePilot-" .. game.GameId .. "-" .. player.UserId .. ".json")
app.config.load()

local function inventoryByUid(uid)
	for _, entry in app.state.inventory do if entry.uid == uid then return entry end end
	return nil
end

local function protectedUids()
	local result = {}
	local inventory = app.state.inventory
	if app.settings.protectEquipped then
		for _, index in app.state.wall or {} do
			local row = inventory[index]
			if row and row.uid then result[row.uid] = true end
		end
		local car = inventory[app.state.car or 0]
		if car and car.uid then result[car.uid] = true end
	end
	if app.settings.protectBest then
		local ranked = {}
		for _, entry in inventory do
			local plate = entry.plate
			if plate and plate.reg ~= false and (not plate.paidUntil or plate.paidUntil > (app.state.now or os.time())) then
				table.insert(ranked, { uid = entry.uid, score = Upgrades.plateLuck(plate) })
			end
		end
		table.sort(ranked, function(a, b) return a.score > b.score end)
		local count = math.max(1, (app.state.wallSlots or 1) + (app.state.hasCar and 1 or 0))
		for i = 1, math.min(count, #ranked) do if ranked[i].uid then result[ranked[i].uid] = true end end
	end
	return result
end

local function logResult(result)
	local raw = result.plate
	if type(raw) ~= "table" then return end
	local uid = result.uid or raw.uid
	if not uid or app.seen[uid] then return end
	app.seen[uid] = true
	table.insert(app.seenOrder, uid)
	if #app.seenOrder > 500 then
		app.seen[table.remove(app.seenOrder, 1)] = nil
	end
	local record = policy.describe(raw)
	record.uid = uid
	record.price = result.price or record.price
	record.rarity = result.rarity or record.rarity
	record.timestamp = os.time()
	record.outcome = result.autosold and "Sold by game" or "Kept"
	app.session.rolls += 1
	if result.autosold then
		app.session.sold += 1
		app.session.revenue += tonumber(result.soldFor) or record.price
	else
		app.session.kept += 1
		app.owned[uid] = true
	end
	if app.settings.rollHistory then
		table.insert(app.journal, record)
		if #app.journal > 500 then table.remove(app.journal, 1) end
	end
	webhook.enqueueDrop(record)
	local threshold = rarityRanks[app.settings.stopRarity]
	if threshold and (rarityRanks[record.rarity] or 0) >= threshold then
		app.settings.roll = false
		if ui then ui.toggles.roll:Set(false, false) end
		app.notify("Rare plate found", record.text .. " - " .. (rarityNames[record.rarity] or record.rarity))
	end
end

local function sellOne()
	if not app.settings.sell then return false end
	local protected = protectedUids()
	for _, entry in app.state.inventory do
		local uid = entry.uid
		local retryAt = uid and app.saleBlocked[uid] or 0
		if uid and (app.owned[uid] or app.settings.sellExisting) and os.clock() >= (retryAt or 0) then
			local eligible = policy.shouldSell(entry.plate, app.settings, protected)
			if eligible then
				local balance = app.state.money
				local result = invoke("SellFromInventory", uid)
				if app.fault or not app.alive then return false end
				if not refresh() then return false end
				local accepted = result == nil or type(result) == "table" and result.ok ~= false
				if accepted and not inventoryByUid(uid) then
					local received = type(result) == "table" and tonumber(result.soldFor or result.amount)
					received = received or math.max(0, app.state.money - balance)
					app.session.sold += 1
					app.session.revenue += received
					if app.owned[uid] then app.session.kept = math.max(0, app.session.kept - 1) end
					app.owned[uid] = nil
					for _, record in app.journal do if record.uid == uid then record.outcome = "Sold for " .. money(received) end end
					app.setActivity("Sold " .. policy.describe(entry.plate).text .. " for " .. money(received) .. ".")
					return true
				end
				app.saleBlocked[uid] = os.clock() + 10
				app.setActivity("Sale skipped after state verification. Inventory was refreshed.")
				return false
			end
		end
	end
	return false
end

local function selectRegion()
	local selected = app.settings.regions
	rotation = rotation % #selected + 1
	local selectedId = selected[rotation]
	local live = {}
	for _, region in app.state.regions or {} do live[region.id] = region end
	if app.settings.regionMode == "Best value" then
		local bestScore = -1
		for _, id in selected do
			local region = live[id]
			local score = region and (region.regionMult or 1) / math.max(1, region.cost) or 1 / math.max(1, app.state.anyRegionCost or 2500)
			if score > bestScore then selectedId, bestScore = id, score end
		end
	end
	local region = live[selectedId]
	if selectedId == "ANY" then selectedId = nil end
	return selectedId, region and region.cost or app.state.anyRegionCost or 2500
end

local function doRoll()
	local state = app.state
	if state.hasAutosell and state.autosellOn and app.settings.sell then
		app.statusText = "Waiting for built-in Auto Sell to be turned off"
		nextRoll = os.clock() + 3
		return
	end
	local region, cost = selectRegion()
	local requested = tonumber(app.settings.batch) or state.maxBatch or 1
	local count = math.clamp(math.floor(requested), 1, state.maxBatch or 1)
	local available = math.max(0, state.money - app.settings.reserveMoney)
	local serverNow = (state.now or os.time()) + (os.clock() - app.stateAt)
	local event = modules.Events.at(serverNow)
	local free = event and event.kind == "free"
	local freeFallback = not free and state.money < (state.cheapestRoll or 2500) and serverNow >= (state.freeRollAt or 0)
	if freeFallback then region, count = nil, 1 end
	if not free and not freeFallback then count = math.min(count, math.floor(available / math.max(1, cost))) end
	local slots = math.max(0, (state.slots or 0) - #state.inventory - #(state.listings or {}) - (state.hand or 0))
	count = math.min(count, slots)
	if count < 1 then
		app.statusText = slots == 0 and "Waiting for garage space" or "Waiting for roll budget or a free roll"
		nextRoll = os.clock() + 2
		return
	end
	app.statusText = "Rolling " .. (region or "any region")
	local result = invoke("Roll", region, count, freeFallback == true)
	nextRoll = os.clock() + math.max(Config.Roll.minCooldownSeconds or 0.4, state.cooldown or 2) + app.settings.delayPadding
	if not result or app.fault or not app.alive then return end
	if result.ok ~= true then
		local code = tostring(result.code or "rejected"):gsub("[^%w_%-]", "")
		app.statusText = "Roll delayed (" .. code .. ")"
		if code ~= "early" and code ~= "money" and code ~= "garage" then rollErrors += 1 end
		if rollErrors >= 3 then stop() app.setActivity("Rolling stopped after three rejected requests. Refresh state before continuing.") end
		nextRoll = os.clock() + math.max(3, state.cooldown or 2)
		refresh()
		return
	end
	rollErrors = 0
	app.session.batches += 1
	app.session.moneySpent += tonumber(result.cost) or (free or freeFallback) and 0 or cost * count
	for _, row in result.results or {} do logResult(row) end
	refresh()
	app.statusText = "Ready for next roll"
	app.setActivity("Received " .. tostring(#(result.results or {})) .. " plate(s).")
end

local function buyUpgrade()
	local state = app.state
	local reserveRolls = (state.anyRegionCost or 2500) * math.max(1, state.maxBatch or 1)
	for _, id in app.settings.regions do
		for _, region in state.regions or {} do
			if region.id == id then reserveRolls = math.max(reserveRolls, region.cost * (state.maxBatch or 1)) end
		end
	end
	local available = math.max(0, state.money - app.settings.reserveMoney - reserveRolls)
	local options = table.clone(app.settings)
	options.upgradeBudget = available * app.settings.upgradeSpendPercent / 100
	local definition, cost = policy.chooseUpgrade(state, options)
	if not definition then return end
	local oldLevel = Upgrades.level(state.upgrades, definition.id)
	local response = invoke("BuyUpgrade", definition.id)
	if not response or app.fault or not app.alive then return end
	if not refresh() then return end
	if response.ok == true and Upgrades.level(app.state.upgrades, definition.id) > oldLevel then
		app.session.upgrades += 1
		app.session.upgradeSpent += cost
		app.setActivity("Purchased " .. definition.id .. " for " .. money(cost) .. ".")
	else
		app.setActivity("Upgrade deferred after state verification.")
		nextUpgrade = os.clock() + 15
	end
end

local function equipBest()
	if not app.state.hasGarage then return end
	local parts = { tostring(app.state.wallSlots), tostring(app.state.hasCar) }
	local serverNow = (app.state.now or os.time()) + os.clock() - app.stateAt
	for _, row in app.state.inventory do
		local registered = row.plate.reg ~= false and (row.paidUntil or math.huge) > serverNow
		table.insert(parts, tostring(row.uid) .. ":" .. tostring(row.price) .. ":" .. tostring(registered))
	end
	table.insert(parts, table.concat(app.state.wall or {}, ",") .. ":" .. tostring(app.state.car))
	local signature = table.concat(parts, "|")
	if signature == equipSignature then return end
	local response = invoke("EquipBest")
	if response and response.ok == true then
		equipSignature = signature
		refresh()
		app.setActivity("Equipped the best registered plates.")
	end
end

local function render()
	if not ui then return end
	local elapsed = math.max(1, os.clock() - app.session.started)
	local flow = app.session.revenue - app.session.moneySpent - app.session.upgradeSpent
	local status = app.fault and "Connection paused. Refresh state after the pending request finishes." or app.statusText
	ui.status:SetDesc(status .. "\n" .. app.activity .. (app.config and "\n" .. app.config.status() or ""))
	ui.stats:SetDesc("Balance  " .. money(app.state.money) .. "\nGarage  " .. #app.state.inventory .. "/" .. app.state.slots .. "\nPlates rolled  " .. app.session.rolls .. "  |  " .. string.format("%.1f", app.session.rolls * 60 / elapsed) .. "/min\nSales  " .. money(app.session.revenue) .. "\nRoll costs  " .. money(app.session.moneySpent) .. "\nUpgrade costs  " .. money(app.session.upgradeSpent) .. "\nSession cash flow  " .. money(flow) .. "\nRetained plates are excluded from cash flow.")
	local rows = {}
	local search = app.settings.logSearch:lower()
	for index = #app.journal, 1, -1 do
		local record = app.journal[index]
		local rarity = rarityNames[record.rarity] or record.rarity
		local matches = app.settings.logRarity == "All" or app.settings.logRarity == rarity or app.settings.logRarity == record.rarity
		if matches and (search == "" or (record.text .. " " .. record.region .. " " .. record.outcome):lower():find(search, 1, true)) then
			table.insert(rows, os.date("%H:%M:%S", record.timestamp) .. "  " .. record.text .. "\n" .. rarity .. " / " .. record.quality .. " / " .. money(record.price) .. "\n" .. record.outcome)
			if #rows >= 12 then break end
		end
	end
	local emptyHistory = app.settings.rollHistory and "No matching rolls. Start Auto Roll or use Roll once." or "Roll history is paused."
	ui.log:SetDesc(#rows > 0 and table.concat(rows, "\n\n") or emptyHistory)
	ui.webhookStatus:SetDesc(webhook.status())
end

local function copyCredit(title, value)
	local clipboard = setclipboard or toclipboard or set_clipboard
	local copied = type(clipboard) == "function" and pcall(clipboard, value)
	app.notify(title, copied and "Copied to clipboard.\n" .. value or value)
end

function app.action(name)
	if not app.alive then return end
	if name == "stop" then stop() app.setActivity("All features stopped. Anti AFK is unchanged.")
	elseif name == "unload" then app.destroy(true)
	elseif name == "copyArceus" then
		if app.credits and app.credits.text then
			copyCredit("Arceus X Scripts", app.credits.text)
		else
			app.notify("Arceus X Scripts", app.credits and app.credits.loading and "The link is still loading. Try again shortly." or "Could not load the link. Run the script again to retry.")
		end
	elseif name == "copyWindUI" then copyCredit("WindUI Library", "https://github.com/Footagesus/WindUI")
	elseif name == "rollOnce" then manualRoll = true
	elseif name == "refresh" then
		if app.pending and not app.pending.done then app.notify("Request pending", "Wait for the current server request to finish.") return end
		app.fault = false
		rollErrors = 0
		app.refreshRequested = true
	elseif name == "clearLog" then table.clear(app.journal)
	elseif name == "exportLog" then
		local encoded = HttpService:JSONEncode(app.journal)
		local ok = false
		if type(writefile) == "function" then ok = pcall(writefile, "PlatePilot-Rolls-" .. os.date("%Y%m%d-%H%M%S") .. ".json", encoded) end
		if not ok and type(setclipboard) == "function" then ok = pcall(setclipboard, encoded) end
		app.notify("Export journal", ok and "Journal exported to an executor file or clipboard." or "This executor has no working file or clipboard support.")
	elseif name == "testWebhook" then webhook.test()
	end
end

app.connect(player.Idled, function()
	if not app.settings.antiAfk then return end
	local ok = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
	if not ok then app.setActivity("Anti AFK input is unavailable in this executor.") end
end)

local libraryOk, library = pcall(loadWindUI, httpRequest)
if not libraryOk then
	app.destroy(false)
	warn("Plate Pilot: WindUI could not load. Check executor HTTP support.")
	return
end
app.library = library
webhook = createWebhook(app, HttpService, httpRequest)
app.credits = createCredits(app, httpRequest)
local uiOk, uiResult = pcall(createUI, app, library)
if not uiOk then
	app.destroy(false)
	warn("Plate Pilot: UI setup failed: " .. tostring(uiResult))
	return
end
ui = uiResult
app.statusText = "Ready"
app.config.start()
render()
task.spawn(function()
	while app.alive do
		local ok, message = pcall(function()
			local now = os.clock()
			if not app.fault then
				if now >= nextRefresh or app.refreshRequested then
					app.refreshRequested = false
					nextRefresh = now + 12
					if refresh() then
						local present = {}
						for _, row in app.state.inventory do present[row.uid] = true end
						for uid in app.owned do if not present[uid] then app.owned[uid] = nil end end
						for uid in app.saleBlocked do if not present[uid] then app.saleBlocked[uid] = nil end end
					end
				end
				if app.settings.sell and now >= nextSell then
					nextSell = now + 0.3
					for _ = 1, (app.state.maxBatch or 1) + 2 do
						if not sellOne() then break end
					end
				end
				if app.settings.upgrades and now >= nextUpgrade then nextUpgrade = now + 4 buyUpgrade() end
				if app.settings.equip and now >= nextEquip then nextEquip = now + 5 equipBest() end
				if (app.settings.roll or manualRoll) and now >= nextRoll then
					manualRoll = false
					doRoll()
				end
			end
		end)
		if not ok then
			stop()
			app.fault = true
			app.setActivity("Automation paused after an unexpected game response. Use Refresh state.")
			warn("Plate Pilot: " .. tostring(message))
		end
		task.wait(0.2)
	end
end)
task.spawn(function()
	while app.alive do
		local ok, message = pcall(function() webhook.tick() render() end)
		if not ok then warn("Plate Pilot display: " .. tostring(message)) end
		task.wait(1)
	end
end)

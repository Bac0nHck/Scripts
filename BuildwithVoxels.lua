if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 9490116046 and game.PlaceId ~= 101914772188620 then
    error("Voxel Schematics: this game is not supported.", 0)
end

if type(readfile) ~= "function" or type(listfiles) ~= "function" then
    error("Voxel Schematics: this executor cannot read files from its workspace folder.", 0)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Player = Players.LocalPlayer
local Environment = type(getgenv) == "function" and getgenv() or _G
local AppKey = "VoxelSchematicsAirflow"

local Previous = Environment[AppKey]
if type(Previous) == "table" and type(Previous.Unload) == "function" then
    pcall(Previous.Unload, Previous)
end

local PlaceRemote = ReplicatedStorage:WaitForChild("PlaceBlockEvent", 60)
local BreakRemote = ReplicatedStorage:WaitForChild("DestroyBlockEven", 60)
if not PlaceRemote or not BreakRemote then
    error("Voxel Schematics: the building remotes did not load.", 0)
end

local band, bxor, lshift, rshift, byteswap = bit32.band, bit32.bxor, bit32.lshift, bit32.rshift, bit32.byteswap
local readu8, readu16, readu32, writeu8, writeu16, writeu32 = buffer.readu8, buffer.readu16, buffer.readu32, buffer.writeu8, buffer.writeu16, buffer.writeu32

local Pace = {Stamp = os.clock(), Budget = 0.012}

function Pace.Step()
    if os.clock() - Pace.Stamp > Pace.Budget then
        task.wait()
        Pace.Stamp = os.clock()
    end
end

function Pace.Reset()
    Pace.Stamp = os.clock()
end

local Bytes = {}

local LengthBase = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258}
local LengthExtra = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0}
local DistBase = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577}
local DistExtra = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13}
local CodeOrder = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}

local function huffman(lengths, offset, count)
    local perLength = table.create(15, 0)
    for i = 1, count do
        local len = lengths[offset + i]
        if len > 0 then
            perLength[len] += 1
        end
    end
    local nextCode = table.create(15, 0)
    local code = 0
    for bits = 1, 15 do
        code = (code + (bits > 1 and perLength[bits - 1] or 0)) * 2
        nextCode[bits] = code
    end
    local fast = table.create(512, 0)
    local slow
    for i = 1, count do
        local len = lengths[offset + i]
        if len > 0 then
            local value = nextCode[len]
            nextCode[len] = value + 1
            if len <= 9 then
                local reversed = 0
                for _ = 1, len do
                    reversed = reversed * 2 + value % 2
                    value = value // 2
                end
                local entry = (i - 1) * 16 + len
                for index = reversed + 1, 512, lshift(1, len) do
                    fast[index] = entry
                end
            else
                slow = slow or {}
                slow[len * 32768 + value] = i - 1
            end
        end
    end
    return fast, slow
end

local FixedLit, FixedDist

local function fixedTables()
    if not FixedLit then
        local lengths = table.create(288, 8)
        for i = 145, 256 do
            lengths[i] = 9
        end
        for i = 257, 280 do
            lengths[i] = 7
        end
        FixedLit = huffman(lengths, 0, 288)
        FixedDist = huffman(table.create(30, 5), 0, 30)
    end
    return FixedLit, FixedDist
end

function Bytes.Inflate(input, pos, hint)
    local capacity = math.max(hint or 0, 4096)
    local out = buffer.create(capacity)
    local outPos = 0
    local bitbuf, bitcnt = 0, 0
    local ticks = 0
    local final = false
    repeat
        if bitcnt < 16 then
            bitbuf += lshift(readu16(input, pos), bitcnt)
            pos += 2
            bitcnt += 16
        end
        final = band(bitbuf, 1) == 1
        local kind = band(rshift(bitbuf, 1), 3)
        bitbuf = rshift(bitbuf, 3)
        bitcnt -= 3
        if kind == 0 then
            bitcnt -= bitcnt % 8
            pos -= bitcnt // 8
            bitbuf, bitcnt = 0, 0
            local len = readu16(input, pos)
            if bxor(len, readu16(input, pos + 2)) ~= 65535 then
                error("stored block is damaged", 0)
            end
            pos += 4
            if outPos + len > capacity then
                capacity = math.max(capacity * 2, outPos + len)
                local grown = buffer.create(capacity)
                buffer.copy(grown, 0, out, 0, outPos)
                out = grown
            end
            buffer.copy(out, outPos, input, pos, len)
            outPos += len
            pos += len
        elseif kind == 1 or kind == 2 then
            local litFast, litSlow, distFast, distSlow
            if kind == 1 then
                litFast, distFast = fixedTables()
            else
                if bitcnt < 16 then
                    bitbuf += lshift(readu16(input, pos), bitcnt)
                    pos += 2
                    bitcnt += 16
                end
                local litCount = band(bitbuf, 31) + 257
                local distCount = band(rshift(bitbuf, 5), 31) + 1
                local codeCount = band(rshift(bitbuf, 10), 15) + 4
                bitbuf = rshift(bitbuf, 14)
                bitcnt -= 14
                local codeLengths = table.create(19, 0)
                for i = 1, codeCount do
                    if bitcnt < 16 then
                        bitbuf += lshift(readu16(input, pos), bitcnt)
                        pos += 2
                        bitcnt += 16
                    end
                    codeLengths[CodeOrder[i] + 1] = band(bitbuf, 7)
                    bitbuf = rshift(bitbuf, 3)
                    bitcnt -= 3
                end
                local codeFast = huffman(codeLengths, 0, 19)
                local total = litCount + distCount
                local lengths = table.create(total, 0)
                local filled = 0
                while filled < total do
                    if bitcnt < 16 then
                        bitbuf += lshift(readu16(input, pos), bitcnt)
                        pos += 2
                        bitcnt += 16
                    end
                    local entry = codeFast[band(bitbuf, 511) + 1]
                    if entry == 0 then
                        error("code length table is damaged", 0)
                    end
                    local used = band(entry, 15)
                    local symbol = rshift(entry, 4)
                    bitbuf = rshift(bitbuf, used)
                    bitcnt -= used
                    if symbol < 16 then
                        filled += 1
                        lengths[filled] = symbol
                    else
                        local value, repeats = 0, 0
                        if symbol == 16 then
                            if filled == 0 then
                                error("code length table is damaged", 0)
                            end
                            value = lengths[filled]
                            repeats = 3 + band(bitbuf, 3)
                            bitbuf = rshift(bitbuf, 2)
                            bitcnt -= 2
                        elseif symbol == 17 then
                            repeats = 3 + band(bitbuf, 7)
                            bitbuf = rshift(bitbuf, 3)
                            bitcnt -= 3
                        else
                            repeats = 11 + band(bitbuf, 127)
                            bitbuf = rshift(bitbuf, 7)
                            bitcnt -= 7
                        end
                        if filled + repeats > total then
                            error("code length table is damaged", 0)
                        end
                        for _ = 1, repeats do
                            filled += 1
                            lengths[filled] = value
                        end
                    end
                end
                litFast, litSlow = huffman(lengths, 0, litCount)
                distFast, distSlow = huffman(lengths, litCount, distCount)
            end
            while true do
                if bitcnt < 16 then
                    bitbuf += lshift(readu16(input, pos), bitcnt)
                    pos += 2
                    bitcnt += 16
                end
                local entry = litFast[band(bitbuf, 511) + 1]
                local symbol
                if entry ~= 0 then
                    local used = band(entry, 15)
                    symbol = rshift(entry, 4)
                    bitbuf = rshift(bitbuf, used)
                    bitcnt -= used
                else
                    local code, used = 0, 0
                    repeat
                        code = code * 2 + band(bitbuf, 1)
                        bitbuf = rshift(bitbuf, 1)
                        used += 1
                        if used > 9 and litSlow then
                            symbol = litSlow[used * 32768 + code]
                        end
                    until symbol or used >= 15
                    if not symbol then
                        error("compressed data is damaged", 0)
                    end
                    bitcnt -= used
                end
                if symbol < 256 then
                    if outPos >= capacity then
                        capacity *= 2
                        local grown = buffer.create(capacity)
                        buffer.copy(grown, 0, out, 0, outPos)
                        out = grown
                    end
                    writeu8(out, outPos, symbol)
                    outPos += 1
                elseif symbol == 256 then
                    break
                else
                    symbol -= 256
                    local length = LengthBase[symbol]
                    if not length then
                        error("compressed data is damaged", 0)
                    end
                    local extra = LengthExtra[symbol]
                    if extra > 0 then
                        if bitcnt < 16 then
                            bitbuf += lshift(readu16(input, pos), bitcnt)
                            pos += 2
                            bitcnt += 16
                        end
                        length += band(bitbuf, lshift(1, extra) - 1)
                        bitbuf = rshift(bitbuf, extra)
                        bitcnt -= extra
                    end
                    if bitcnt < 16 then
                        bitbuf += lshift(readu16(input, pos), bitcnt)
                        pos += 2
                        bitcnt += 16
                    end
                    local distEntry = distFast[band(bitbuf, 511) + 1]
                    local distSymbol
                    if distEntry ~= 0 then
                        local used = band(distEntry, 15)
                        distSymbol = rshift(distEntry, 4)
                        bitbuf = rshift(bitbuf, used)
                        bitcnt -= used
                    else
                        local code, used = 0, 0
                        repeat
                            code = code * 2 + band(bitbuf, 1)
                            bitbuf = rshift(bitbuf, 1)
                            used += 1
                            if used > 9 and distSlow then
                                distSymbol = distSlow[used * 32768 + code]
                            end
                        until distSymbol or used >= 15
                        if not distSymbol then
                            error("compressed data is damaged", 0)
                        end
                        bitcnt -= used
                    end
                    local distance = DistBase[distSymbol + 1]
                    if not distance then
                        error("compressed data is damaged", 0)
                    end
                    local distExtra = DistExtra[distSymbol + 1]
                    if distExtra > 0 then
                        if bitcnt < 16 then
                            bitbuf += lshift(readu16(input, pos), bitcnt)
                            pos += 2
                            bitcnt += 16
                        end
                        distance += band(bitbuf, lshift(1, distExtra) - 1)
                        bitbuf = rshift(bitbuf, distExtra)
                        bitcnt -= distExtra
                    end
                    if distance > outPos then
                        error("compressed data is damaged", 0)
                    end
                    if outPos + length > capacity then
                        capacity = math.max(capacity * 2, outPos + length)
                        local grown = buffer.create(capacity)
                        buffer.copy(grown, 0, out, 0, outPos)
                        out = grown
                    end
                    if distance >= length then
                        buffer.copy(out, outPos, out, outPos - distance, length)
                        outPos += length
                    elseif distance == 1 then
                        buffer.fill(out, outPos, readu8(out, outPos - 1), length)
                        outPos += length
                    else
                        local remaining = length
                        while remaining > 0 do
                            local chunk = remaining < distance and remaining or distance
                            buffer.copy(out, outPos, out, outPos - distance, chunk)
                            outPos += chunk
                            remaining -= chunk
                        end
                    end
                end
                ticks += 1
                if ticks >= 20000 then
                    ticks = 0
                    Pace.Step()
                end
            end
        else
            error("compressed data is damaged", 0)
        end
    until final
    return out, outPos
end

function Bytes.Unpack(data)
    local size = #data
    if size < 4 then
        error("the file is empty", 0)
    end
    local input = buffer.create(size + 16)
    buffer.writestring(input, 0, data)
    local first, second = readu8(input, 0), readu8(input, 1)
    if first == 31 and second == 139 then
        if size < 18 or readu8(input, 2) ~= 8 then
            error("unsupported gzip stream", 0)
        end
        local flags = readu8(input, 3)
        local pos = 10
        if band(flags, 4) ~= 0 then
            pos += 2 + readu16(input, pos)
        end
        if band(flags, 8) ~= 0 then
            while pos < size and readu8(input, pos) ~= 0 do
                pos += 1
            end
            pos += 1
        end
        if band(flags, 16) ~= 0 then
            while pos < size and readu8(input, pos) ~= 0 do
                pos += 1
            end
            pos += 1
        end
        if band(flags, 2) ~= 0 then
            pos += 2
        end
        if pos >= size then
            error("gzip header is damaged", 0)
        end
        local hint = readu32(input, size - 4)
        if hint > 536870912 then
            error("the file is too large", 0)
        end
        return Bytes.Inflate(input, pos, hint)
    end
    if band(first, 15) == 8 and (first * 256 + second) % 31 == 0 and first ~= 10 then
        local pos = 2
        if band(second, 32) ~= 0 then
            pos += 4
        end
        return Bytes.Inflate(input, pos, size * 6)
    end
    return input, size
end

local Nbt = {}

function Nbt.Parse(buf, size)
    local pos = 0
    local scratch = buffer.create(8)
    local count = 0
    local read

    local function int()
        local value = byteswap(readu32(buf, pos))
        pos += 4
        return value >= 2147483648 and value - 4294967296 or value
    end

    local function text()
        local length = readu8(buf, pos) * 256 + readu8(buf, pos + 1)
        pos += 2
        local value = buffer.readstring(buf, pos, length)
        pos += length
        return value
    end

    local function array(tag, width)
        local length = int()
        if length < 0 or pos + length * width > size then
            error("NBT array runs past the end of the file", 0)
        end
        local ref = {Tag = tag, Offset = pos, Count = length}
        pos += length * width
        return ref
    end

    function read(tag)
        if tag == 1 then
            local value = buffer.readi8(buf, pos)
            pos += 1
            return value
        elseif tag == 2 then
            local value = readu8(buf, pos) * 256 + readu8(buf, pos + 1)
            pos += 2
            return value >= 32768 and value - 65536 or value
        elseif tag == 3 then
            return int()
        elseif tag == 4 then
            local high = int()
            local low = byteswap(readu32(buf, pos))
            pos += 4
            return high * 4294967296 + low
        elseif tag == 5 then
            writeu32(scratch, 0, byteswap(readu32(buf, pos)))
            pos += 4
            return buffer.readf32(scratch, 0)
        elseif tag == 6 then
            writeu32(scratch, 4, byteswap(readu32(buf, pos)))
            writeu32(scratch, 0, byteswap(readu32(buf, pos + 4)))
            pos += 8
            return buffer.readf64(scratch, 0)
        elseif tag == 7 then
            return array(7, 1)
        elseif tag == 8 then
            return text()
        elseif tag == 9 then
            local inner = readu8(buf, pos)
            pos += 1
            local length = int()
            if length < 0 or length > size then
                error("NBT list is damaged", 0)
            end
            local list = table.create(length)
            for i = 1, length do
                list[i] = read(inner)
            end
            return list
        elseif tag == 10 then
            local map = {}
            while true do
                local inner = readu8(buf, pos)
                pos += 1
                if inner == 0 then
                    break
                end
                local name = text()
                map[name] = read(inner)
            end
            count += 1
            if count >= 4000 then
                count = 0
                Pace.Step()
            end
            return map
        elseif tag == 11 then
            return array(11, 4)
        elseif tag == 12 then
            return array(12, 8)
        end
        error("NBT tag " .. tostring(tag) .. " is not supported", 0)
    end

    if readu8(buf, 0) ~= 10 then
        error("this is not an NBT file", 0)
    end
    pos = 1
    local name = text()
    return read(10), name
end

local Legacy = {}

local ColorOrder = {"white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"}
local WoodOrder = {"oak", "spruce", "birch", "jungle", "acacia", "dark_oak"}

local LegacyNames = {
    [1] = {"stone", "granite", "polished_granite", "diorite", "polished_diorite", "andesite", "polished_andesite"},
    [2] = "grass_block",
    [3] = {"dirt", "coarse_dirt", "podzol"},
    [4] = "cobblestone",
    [7] = "bedrock",
    [12] = {"sand", "red_sand"},
    [13] = "gravel",
    [14] = "gold_ore",
    [15] = "iron_ore",
    [16] = "coal_ore",
    [19] = {"sponge", "wet_sponge"},
    [20] = "glass",
    [21] = "lapis_ore",
    [22] = "lapis_block",
    [24] = {"sandstone", "chiseled_sandstone", "cut_sandstone"},
    [25] = "note_block",
    [29] = "sticky_piston",
    [30] = "cobweb",
    [31] = {"dead_bush", "short_grass", "fern"},
    [32] = "dead_bush",
    [33] = "piston",
    [34] = "piston_head",
    [36] = "moving_piston",
    [37] = "dandelion",
    [38] = {"poppy", "blue_orchid", "allium", "azure_bluet", "red_tulip", "orange_tulip", "white_tulip", "pink_tulip", "oxeye_daisy"},
    [39] = "brown_mushroom",
    [40] = "red_mushroom",
    [41] = "gold_block",
    [42] = "iron_block",
    [45] = "bricks",
    [46] = "tnt",
    [47] = "bookshelf",
    [48] = "mossy_cobblestone",
    [49] = "obsidian",
    [50] = "torch",
    [51] = "fire",
    [52] = "spawner",
    [55] = "redstone_wire",
    [56] = "diamond_ore",
    [57] = "diamond_block",
    [58] = "crafting_table",
    [59] = "wheat",
    [60] = "farmland",
    [69] = "lever",
    [70] = "stone_pressure_plate",
    [72] = "oak_pressure_plate",
    [73] = "redstone_ore",
    [74] = "redstone_ore",
    [75] = "redstone_torch",
    [76] = "redstone_torch",
    [77] = "stone_button",
    [79] = "ice",
    [80] = "snow_block",
    [81] = "cactus",
    [82] = "clay",
    [83] = "sugar_cane",
    [84] = "jukebox",
    [85] = "oak_fence",
    [87] = "netherrack",
    [88] = "soul_sand",
    [89] = "glowstone",
    [90] = "nether_portal",
    [92] = "cake",
    [93] = "repeater",
    [94] = "repeater",
    [97] = {"infested_stone", "infested_cobblestone", "infested_stone_bricks", "infested_mossy_stone_bricks", "infested_cracked_stone_bricks", "infested_chiseled_stone_bricks"},
    [98] = {"stone_bricks", "mossy_stone_bricks", "cracked_stone_bricks", "chiseled_stone_bricks"},
    [101] = "iron_bars",
    [102] = "glass_pane",
    [103] = "melon",
    [104] = "pumpkin_stem",
    [105] = "melon_stem",
    [106] = "vine",
    [107] = "oak_fence_gate",
    [110] = "mycelium",
    [111] = "lily_pad",
    [112] = "nether_bricks",
    [113] = "nether_brick_fence",
    [115] = "nether_wart",
    [116] = "enchanting_table",
    [117] = "brewing_stand",
    [118] = "cauldron",
    [119] = "end_portal",
    [120] = "end_portal_frame",
    [121] = "end_stone",
    [122] = "dragon_egg",
    [123] = "redstone_lamp",
    [124] = "redstone_lamp",
    [127] = "cocoa",
    [129] = "emerald_ore",
    [131] = "tripwire_hook",
    [132] = "tripwire",
    [133] = "emerald_block",
    [137] = "command_block",
    [138] = "beacon",
    [139] = {"cobblestone_wall", "mossy_cobblestone_wall"},
    [140] = "flower_pot",
    [141] = "carrots",
    [142] = "potatoes",
    [143] = "oak_button",
    [144] = "skeleton_skull",
    [145] = "anvil",
    [147] = "light_weighted_pressure_plate",
    [148] = "heavy_weighted_pressure_plate",
    [149] = "comparator",
    [150] = "comparator",
    [151] = "daylight_detector",
    [152] = "redstone_block",
    [153] = "nether_quartz_ore",
    [154] = "hopper",
    [155] = {"quartz_block", "chiseled_quartz_block", "quartz_pillar", "quartz_pillar", "quartz_pillar"},
    [165] = "slime_block",
    [166] = "barrier",
    [168] = {"prismarine", "prismarine_bricks", "dark_prismarine"},
    [169] = "sea_lantern",
    [170] = "hay_block",
    [172] = "terracotta",
    [173] = "coal_block",
    [174] = "packed_ice",
    [176] = "white_banner",
    [177] = "white_wall_banner",
    [178] = "daylight_detector",
    [179] = {"red_sandstone", "chiseled_red_sandstone", "cut_red_sandstone"},
    [183] = "spruce_fence_gate",
    [184] = "birch_fence_gate",
    [185] = "jungle_fence_gate",
    [186] = "dark_oak_fence_gate",
    [187] = "acacia_fence_gate",
    [188] = "spruce_fence",
    [189] = "birch_fence",
    [190] = "jungle_fence",
    [191] = "dark_oak_fence",
    [192] = "acacia_fence",
    [198] = "end_rod",
    [199] = "chorus_plant",
    [200] = "chorus_flower",
    [201] = "purpur_block",
    [202] = "purpur_pillar",
    [206] = "end_stone_bricks",
    [207] = "beetroots",
    [208] = "dirt_path",
    [209] = "end_gateway",
    [210] = "repeating_command_block",
    [211] = "chain_command_block",
    [212] = "frosted_ice",
    [213] = "magma_block",
    [214] = "nether_wart_block",
    [215] = "red_nether_bricks",
    [216] = "bone_block",
    [217] = "structure_void",
    [218] = "observer",
    [255] = "structure_block",
}

local LegacyStairs = {[53] = "oak", [67] = "cobblestone", [108] = "brick", [109] = "stone_brick", [114] = "nether_brick", [128] = "sandstone", [134] = "spruce", [135] = "birch", [136] = "jungle", [156] = "quartz", [163] = "acacia", [164] = "dark_oak", [180] = "red_sandstone", [203] = "purpur"}
local LegacyDoors = {[64] = "oak", [71] = "iron", [193] = "spruce", [194] = "birch", [195] = "jungle", [196] = "acacia", [197] = "dark_oak"}
local LegacyColored = {[35] = "_wool", [95] = "_stained_glass", [159] = "_terracotta", [160] = "_stained_glass_pane", [171] = "_carpet", [251] = "_concrete", [252] = "_concrete_powder"}
local LegacyFacing = {[23] = "dispenser", [54] = "chest", [61] = "furnace", [62] = "furnace", [65] = "ladder", [68] = "oak_wall_sign", [130] = "ender_chest", [146] = "trapped_chest", [158] = "dropper"}
local LegacyRails = {[27] = "powered_rail", [28] = "detector_rail", [66] = "rail", [157] = "activator_rail"}
local LegacyStoneSlabs = {"smooth_stone", "sandstone", "petrified_oak", "cobblestone", "brick", "stone_brick", "nether_brick", "quartz"}
local StairFacing = {"east", "west", "south", "north"}
local DoorFacing = {"east", "south", "west", "north"}
local BedFacing = {"south", "west", "north", "east"}
local TrapFacing = {"north", "south", "west", "east"}
local SixFacing = {[0] = "down", [1] = "up", [2] = "north", [3] = "south", [4] = "west", [5] = "east"}
local RailShapes = {[0] = "north_south", [1] = "east_west", [2] = "ascending_east", [3] = "ascending_west", [4] = "ascending_north", [5] = "ascending_south", [6] = "south_east", [7] = "south_west", [8] = "north_west", [9] = "north_east"}
local DoublePlants = {"sunflower", "lilac", "tall_grass", "large_fern", "rose_bush", "peony"}

function Legacy.State(id, meta)
    local simple = LegacyNames[id]
    if type(simple) == "string" then
        return simple
    elseif simple then
        return simple[meta + 1] or simple[1]
    end
    local stair = LegacyStairs[id]
    if stair then
        return stair .. "_stairs", {facing = StairFacing[band(meta, 3) + 1], half = band(meta, 4) ~= 0 and "top" or "bottom"}
    end
    local door = LegacyDoors[id]
    if door then
        if band(meta, 8) ~= 0 then
            return door .. "_door", {half = "upper"}
        end
        return door .. "_door", {half = "lower", facing = DoorFacing[band(meta, 3) + 1]}
    end
    local colored = LegacyColored[id]
    if colored then
        return (ColorOrder[meta + 1] or "white") .. colored
    end
    local facing = LegacyFacing[id]
    if facing then
        return facing, {facing = SixFacing[band(meta, 7)] or "north"}
    end
    local rail = LegacyRails[id]
    if rail then
        return rail, {shape = RailShapes[id == 66 and meta or band(meta, 7)] or "north_south"}
    end
    if id == 5 then
        return (WoodOrder[meta + 1] or "oak") .. "_planks"
    elseif id == 6 then
        return (WoodOrder[band(meta, 7) + 1] or "oak") .. "_sapling"
    elseif id == 8 or id == 9 then
        return "water", {level = tostring(meta)}
    elseif id == 10 or id == 11 then
        return "lava", {level = tostring(meta)}
    elseif id == 17 or id == 162 then
        local wood = WoodOrder[band(meta, 3) + (id == 17 and 1 or 5)] or "oak"
        local axis = rshift(meta, 2)
        if axis == 3 then
            return wood .. "_wood"
        end
        return wood .. "_log", {axis = axis == 1 and "x" or axis == 2 and "z" or "y"}
    elseif id == 18 or id == 161 then
        return (WoodOrder[band(meta, 3) + (id == 18 and 1 or 5)] or "oak") .. "_leaves"
    elseif id == 26 then
        return "red_bed", {facing = BedFacing[band(meta, 3) + 1], part = band(meta, 8) ~= 0 and "head" or "foot"}
    elseif id == 43 or id == 44 then
        local kind = LegacyStoneSlabs[band(meta, 7) + 1] or "smooth_stone"
        return kind .. "_slab", {type = id == 43 and "double" or band(meta, 8) ~= 0 and "top" or "bottom"}
    elseif id == 63 then
        return "oak_sign", {rotation = tostring(meta)}
    elseif id == 78 then
        return "snow", {layers = tostring(band(meta, 7) + 1)}
    elseif id == 86 then
        return "carved_pumpkin", {facing = BedFacing[band(meta, 3) + 1]}
    elseif id == 91 then
        return "jack_o_lantern", {facing = BedFacing[band(meta, 3) + 1]}
    elseif id == 96 or id == 167 then
        return (id == 96 and "oak" or "iron") .. "_trapdoor", {facing = TrapFacing[band(meta, 3) + 1], half = band(meta, 8) ~= 0 and "top" or "bottom"}
    elseif id == 99 or id == 100 then
        if meta == 10 or meta == 15 then
            return "mushroom_stem"
        end
        return id == 99 and "brown_mushroom_block" or "red_mushroom_block"
    elseif id == 125 or id == 126 then
        local wood = WoodOrder[band(meta, 7) + 1] or "oak"
        return wood .. "_slab", {type = id == 125 and "double" or band(meta, 8) ~= 0 and "top" or "bottom"}
    elseif id == 175 then
        if band(meta, 8) ~= 0 then
            return "tall_grass", {half = "upper"}
        end
        return DoublePlants[band(meta, 7) + 1] or "tall_grass", {half = "lower"}
    elseif id == 181 or id == 182 then
        return "red_sandstone_slab", {type = id == 181 and "double" or band(meta, 8) ~= 0 and "top" or "bottom"}
    elseif id == 204 or id == 205 then
        return "purpur_slab", {type = id == 204 and "double" or band(meta, 8) ~= 0 and "top" or "bottom"}
    elseif id >= 219 and id <= 234 then
        return ColorOrder[id - 218] .. "_shulker_box"
    elseif id >= 235 and id <= 250 then
        return ColorOrder[id - 234] .. "_glazed_terracotta", {facing = BedFacing[band(meta, 3) + 1]}
    end
    return "legacy:" .. tostring(id)
end

local Formats = {MaxVolume = 24000000}

local AirNames = {air = true, cave_air = true, void_air = true}

local function parseState(text)
    local name, body = string.match(text, "^([^%[]+)%[(.*)%]$")
    if not name then
        return text, nil
    end
    local props = {}
    for key, value in string.gmatch(body, "([^=,]+)=([^,]*)") do
        props[key] = value
    end
    return name, props
end

local function newModel(format, name, sx, sy, sz)
    if not (sx and sy and sz) or sx < 1 or sy < 1 or sz < 1 then
        error("the schematic has no size", 0)
    end
    local volume = sx * sy * sz
    if volume > Formats.MaxVolume then
        error(string.format("the schematic is too large (%d x %d x %d)", sx, sy, sz), 0)
    end
    return {
        Format = format,
        Name = name,
        SX = sx,
        SY = sy,
        SZ = sz,
        Grid = buffer.create(volume * 2),
        Palette = {},
        Lookup = {},
    }
end

local function paletteIndex(model, id, props)
    if type(id) ~= "string" then
        return 0
    end
    if string.sub(id, 1, 10) == "minecraft:" then
        id = string.sub(id, 11)
    end
    if AirNames[id] then
        return 0
    end
    local key = id
    if type(props) == "table" and next(props) ~= nil then
        local parts = {}
        for name, value in props do
            table.insert(parts, tostring(name) .. "=" .. tostring(value))
        end
        table.sort(parts)
        key = id .. "[" .. table.concat(parts, ",") .. "]"
    else
        props = nil
    end
    local index = model.Lookup[key]
    if not index then
        index = #model.Palette + 1
        if index > 65535 then
            error("the schematic has too many block states", 0)
        end
        model.Palette[index] = {Id = id, Props = props, Count = 0}
        model.Lookup[key] = index
    end
    return index
end

local function finishCounts(model, counts)
    for index, entry in model.Palette do
        entry.Count = counts[index] or 0
    end
end

local function unsigned(value)
    if type(value) ~= "number" then
        return nil
    end
    return value < 0 and value + 65536 or value
end

function Formats.Litematic(root, buf)
    local regions = {}
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for _, region in root.Regions do
        local size, position = region.Size, region.Position
        local states, palette = region.BlockStates, region.BlockStatePalette
        if type(size) == "table" and type(position) == "table" and type(states) == "table" and states.Tag == 12 and type(palette) == "table" then
            local sx, sy, sz = math.abs(size.x), math.abs(size.y), math.abs(size.z)
            if sx > 0 and sy > 0 and sz > 0 then
                local ox = position.x + (size.x < 0 and size.x + 1 or 0)
                local oy = position.y + (size.y < 0 and size.y + 1 or 0)
                local oz = position.z + (size.z < 0 and size.z + 1 or 0)
                table.insert(regions, {SX = sx, SY = sy, SZ = sz, OX = ox, OY = oy, OZ = oz, States = states, Palette = palette})
                minX, minY, minZ = math.min(minX, ox), math.min(minY, oy), math.min(minZ, oz)
                maxX, maxY, maxZ = math.max(maxX, ox + sx - 1), math.max(maxY, oy + sy - 1), math.max(maxZ, oz + sz - 1)
            end
        end
    end
    if #regions == 0 then
        error("the litematic has no regions", 0)
    end
    local metadata = type(root.Metadata) == "table" and root.Metadata or {}
    local model = newModel("Litematica", type(metadata.Name) == "string" and metadata.Name or nil, maxX - minX + 1, maxY - minY + 1, maxZ - minZ + 1)
    local grid = model.Grid
    local width, layer = model.SX, model.SX * model.SZ
    local counts = {}
    for _, region in regions do
        local palette = region.Palette
        local remap = table.create(#palette, 0)
        for i, entry in palette do
            if type(entry) == "table" then
                remap[i] = paletteIndex(model, entry.Name, entry.Properties)
            end
        end
        local bits = math.max(2, 32 - bit32.countlz(math.max(#palette - 1, 0)))
        if bits > 24 then
            error("the litematic palette is too large", 0)
        end
        local states = region.States
        local volume = region.SX * region.SY * region.SZ
        if states.Count * 64 < volume * bits then
            error("the litematic block data is shorter than its size", 0)
        end
        local stream = buffer.create(states.Count * 8 + 8)
        for k = 0, states.Count - 1 do
            local base = states.Offset + k * 8
            writeu32(stream, k * 8, byteswap(readu32(buf, base + 4)))
            writeu32(stream, k * 8 + 4, byteswap(readu32(buf, base)))
        end
        Pace.Step()
        local mask = lshift(1, bits) - 1
        local sx, sz = region.SX, region.SZ
        local ox, oy, oz = region.OX - minX, region.OY - minY, region.OZ - minZ
        local bitPos = 0
        for y = 0, region.SY - 1 do
            local layerBase = (oy + y) * layer
            for z = 0, sz - 1 do
                local base = (layerBase + (oz + z) * width + ox) * 2
                for x = 0, sx - 1 do
                    local mapped = remap[band(rshift(readu32(stream, bitPos // 8), bitPos % 8), mask) + 1]
                    bitPos += bits
                    if mapped and mapped ~= 0 then
                        writeu16(grid, base + x * 2, mapped)
                        counts[mapped] = (counts[mapped] or 0) + 1
                    end
                end
            end
            Pace.Step()
        end
    end
    finishCounts(model, counts)
    return model
end

function Formats.Sponge(body, buf)
    local palette, data = body.Palette, body.BlockData
    if type(body.Blocks) == "table" and body.Blocks.Tag == nil then
        palette, data = body.Blocks.Palette, body.Blocks.Data
    end
    if type(palette) ~= "table" or type(data) ~= "table" or data.Tag ~= 7 then
        error("the schematic has no block data", 0)
    end
    local model = newModel("Sponge", nil, unsigned(body.Width), unsigned(body.Height), unsigned(body.Length))
    local remap = {}
    for key, id in palette do
        if type(key) == "string" and type(id) == "number" then
            local name, props = parseState(key)
            remap[id] = paletteIndex(model, name, props)
        end
    end
    local grid = model.Grid
    local counts = {}
    local pos = data.Offset
    local stop = pos + data.Count
    local volume = model.SX * model.SY * model.SZ
    local cell = 0
    while cell < volume and pos < stop do
        local value = readu8(buf, pos)
        pos += 1
        if value >= 128 then
            value -= 128
            local shift = 7
            while pos < stop do
                local byte = readu8(buf, pos)
                pos += 1
                value += lshift(band(byte, 127), shift)
                if byte < 128 then
                    break
                end
                shift += 7
            end
        end
        local mapped = remap[value]
        if mapped and mapped ~= 0 then
            writeu16(grid, cell * 2, mapped)
            counts[mapped] = (counts[mapped] or 0) + 1
        end
        cell += 1
        if cell % 60000 == 0 then
            Pace.Step()
        end
    end
    finishCounts(model, counts)
    return model
end

function Formats.Classic(root, buf)
    local blocks, data, extra = root.Blocks, root.Data, root.AddBlocks or root.Add
    local model = newModel("MCEdit", nil, unsigned(root.Width), unsigned(root.Height), unsigned(root.Length))
    local volume = model.SX * model.SY * model.SZ
    if blocks.Count < volume then
        error("the schematic block data is shorter than its size", 0)
    end
    if type(data) ~= "table" or data.Tag ~= 7 or data.Count < volume then
        data = nil
    end
    if type(extra) ~= "table" or extra.Tag ~= 7 then
        extra = nil
    end
    model.Legacy = true
    local grid = model.Grid
    local counts = {}
    local cache = {}
    local blockOffset = blocks.Offset
    for cell = 0, volume - 1 do
        local id = readu8(buf, blockOffset + cell)
        if extra and cell // 2 < extra.Count then
            local nibble = readu8(buf, extra.Offset + cell // 2)
            id += (cell % 2 == 0 and band(nibble, 15) or rshift(nibble, 4)) * 256
        end
        if id ~= 0 then
            local key = id * 16 + (data and band(readu8(buf, data.Offset + cell), 15) or 0)
            local mapped = cache[key]
            if mapped == nil then
                local name, props = Legacy.State(id, key % 16)
                mapped = paletteIndex(model, name, props)
                cache[key] = mapped
            end
            if mapped ~= 0 then
                writeu16(grid, cell * 2, mapped)
                counts[mapped] = (counts[mapped] or 0) + 1
            end
        end
        if cell % 60000 == 59999 then
            Pace.Step()
        end
    end
    finishCounts(model, counts)
    return model
end

function Formats.Structure(root)
    local size = root.size
    local palette = root.palette
    if type(palette) ~= "table" and type(root.palettes) == "table" then
        palette = root.palettes[1]
    end
    if type(size) ~= "table" or type(palette) ~= "table" or type(root.blocks) ~= "table" then
        error("the structure file has no blocks", 0)
    end
    local model = newModel("Structure", nil, size[1], size[2], size[3])
    local remap = table.create(#palette, 0)
    for i, entry in palette do
        if type(entry) == "table" then
            remap[i] = paletteIndex(model, entry.Name, entry.Properties)
        end
    end
    local grid = model.Grid
    local counts = {}
    local sx, sy, sz = model.SX, model.SY, model.SZ
    for i, block in root.blocks do
        local position = type(block) == "table" and block.pos
        local mapped = position and remap[(block.state or -1) + 1]
        if mapped and mapped ~= 0 then
            local x, y, z = position[1], position[2], position[3]
            if x and y and z and x >= 0 and y >= 0 and z >= 0 and x < sx and y < sy and z < sz then
                writeu16(grid, (x + z * sx + y * sx * sz) * 2, mapped)
                counts[mapped] = (counts[mapped] or 0) + 1
            end
        end
        if i % 20000 == 0 then
            Pace.Step()
        end
    end
    finishCounts(model, counts)
    return model
end

function Formats.Decode(root, buf)
    if type(root) ~= "table" then
        error("the file has no data", 0)
    end
    if type(root.Regions) == "table" then
        return Formats.Litematic(root, buf)
    end
    if type(root.Schematic) == "table" and root.Schematic.Tag == nil then
        return Formats.Sponge(root.Schematic, buf)
    end
    if type(root.Blocks) == "table" and root.Blocks.Tag == 7 then
        return Formats.Classic(root, buf)
    end
    if type(root.Palette) == "table" or type(root.Blocks) == "table" then
        return Formats.Sponge(root, buf)
    end
    if type(root.size) == "table" and type(root.blocks) == "table" then
        return Formats.Structure(root)
    end
    error("this file is not a known schematic format", 0)
end

function Formats.Load(data)
    Pace.Reset()
    local buf, size = Bytes.Unpack(data)
    local root = Nbt.Parse(buf, size)
    return Formats.Decode(root, buf)
end

local Rules = {}

local ColorTitles = {
    white = "White", orange = "Orange", magenta = "Magenta", light_blue = "Light Blue", yellow = "Yellow", lime = "Lime", pink = "Pink", gray = "Gray",
    light_gray = "Light Gray", cyan = "Cyan", purple = "Purple", blue = "Blue", brown = "Brown", green = "Green", red = "Red", black = "Black",
}

local Full = {
    stone = "Stone", smooth_stone = "~Polished Andesite", granite = "Granite", polished_granite = "Polished Granite", diorite = "Diorite",
    polished_diorite = "Polished Diorite", andesite = "Andesite", polished_andesite = "Polished Andesite", cobblestone = "Cobblestone",
    mossy_cobblestone = "Mossy Cobblestone", stone_bricks = "Stone Brick", mossy_stone_bricks = "Mossy Stone Brick",
    cracked_stone_bricks = "Cracked Stone Brick", chiseled_stone_bricks = "Chiseled Stone Brick", infested_stone = "Stone",
    infested_cobblestone = "Cobblestone", infested_stone_bricks = "Stone Brick", infested_mossy_stone_bricks = "Mossy Stone Brick",
    infested_cracked_stone_bricks = "Cracked Stone Brick", infested_chiseled_stone_bricks = "Chiseled Stone Brick",
    infested_deepslate = "~Extra Cracked Stone", bedrock = "~Extra Cracked Stone", deepslate = "~Extra Cracked Stone",
    cobbled_deepslate = "~Extra Cracked Stone", polished_deepslate = "~Super Cracked Stone", deepslate_bricks = "~Super Cracked Stone",
    cracked_deepslate_bricks = "~Super Cracked Stone", deepslate_tiles = "~Really Cracked Stone", cracked_deepslate_tiles = "~Really Cracked Stone",
    chiseled_deepslate = "~Hyper Cracked Stone", reinforced_deepslate = "~Hyper Cracked Stone", tuff = "~Andesite", polished_tuff = "~Polished Andesite",
    tuff_bricks = "~Andesite Brick", chiseled_tuff = "~Engraved Andesite", chiseled_tuff_bricks = "~Engraved Andesite", calcite = "~Diorite",
    dripstone_block = "~Granite", basalt = "~Extra Cracked Stone", smooth_basalt = "~Extra Cracked Stone", polished_basalt = "~Super Cracked Stone",
    blackstone = "~Really Cracked Stone", polished_blackstone = "~Really Cracked Stone", polished_blackstone_bricks = "~Super Cracked Stone",
    cracked_polished_blackstone_bricks = "~Super Cracked Stone", chiseled_polished_blackstone = "~Hyper Cracked Stone",
    gilded_blackstone = "~Fireball Block", obsidian = "Obsidian", crying_obsidian = "Crying Obsidian", respawn_anchor = "~Crying Obsidian",
    lodestone = "~Chiseled Stone Brick",

    oak_planks = "Planks", spruce_planks = "Spruce Wood Plank", birch_planks = "Birch Wood Plank", jungle_planks = "Jungle Wood Plank",
    acacia_planks = "Acacia Wood Plank", dark_oak_planks = "~Spruce Wood Plank", mangrove_planks = "~Spruce Wood Plank",
    cherry_planks = "Cherry Planks", bamboo_planks = "~Mango Planks", bamboo_mosaic = "~Mango Planks", crimson_planks = "~Pear Planks",
    warped_planks = "~Spectral Planks", pale_oak_planks = "~Birch Wood Plank", petrified_oak = "Planks",
    oak_log = "Wood", spruce_log = "~Pine Log", birch_log = "Birch Log", jungle_log = "Jungle Log", acacia_log = "~Plum Log",
    dark_oak_log = "~Pine Log", mangrove_log = "~Palm Log", cherry_log = "Cherry Log", crimson_stem = "~Cherry Log",
    warped_stem = "~Spectral Log", pale_oak_log = "~Withered Log", bamboo_block = "~Palm Leaves",
    oak_leaves = "Oak Leaves Fancy", spruce_leaves = "~Pine Leaves", birch_leaves = "~Elm Leaves", jungle_leaves = "Jungle Leaves Fancy",
    acacia_leaves = "~Elm Leaves", dark_oak_leaves = "~Cedar Leaves", mangrove_leaves = "~Plum Leaves", cherry_leaves = "Cherry Leaves",
    azalea_leaves = "~Elm Leaves", flowering_azalea_leaves = "~Elm Leaves", pale_oak_leaves = "~Light Gray Wool",

    sand = "Sand|~Sandstone", red_sand = "Red Sand|~Red Sandstone", gravel = "Gravel|~Andesite", suspicious_sand = "Sand|~Sandstone",
    suspicious_gravel = "Gravel|~Andesite", sandstone = "Sandstone", chiseled_sandstone = "Chiseled Sandstone", cut_sandstone = "Cut Sandstone",
    smooth_sandstone = "Smooth Sandstone", red_sandstone = "Red Sandstone", chiseled_red_sandstone = "Chiseled Red Sandstone",
    cut_red_sandstone = "~Red Sandstone Brick", smooth_red_sandstone = "~Red Sandstone",
    dirt = "Dirt", coarse_dirt = "Coarse Dirt", rooted_dirt = "~Coarse Dirt", podzol = "Podzol", mycelium = "Mycelium", dirt_path = "~Coarse Dirt",
    farmland = "~Dirt", mud = "~Soul Sand", packed_mud = "~Rocky Dirt", mud_bricks = "~Granite Brick", clay = "Clay",
    moss_block = "~Pine Grass Block", pale_moss_block = "~Light Gray Wool", snow_block = "Snow Block", powder_snow = "~Snow Block", ice = "Ice",
    packed_ice = "Packed Ice", blue_ice = "~Packed Ice", frosted_ice = "~Ice",
    cactus = "Cactus", sponge = "Sponge", wet_sponge = "~Sponge", pumpkin = "Pumpkin", melon = "Watermelon Block", hay_block = "Hay Bale",
    bone_block = "Bone Block", slime_block = "Slime Block|~Lime Wool", honey_block = "~Yellow Wool", honeycomb_block = "~Clay (Yellow)",
    brown_mushroom_block = "Mushroom Cap - Brown", red_mushroom_block = "Mushroom Cap - Red", mushroom_stem = "Mushroom Stem",
    dried_kelp_block = "~Clay (Green)", target = "~Hay Bale", bee_nest = "~Clay (Yellow)", beehive = "~Planks",

    netherrack = "Netherrack", nether_bricks = "Nether Brick", cracked_nether_bricks = "~Nether Brick", chiseled_nether_bricks = "~Nether Brick",
    red_nether_bricks = "~Nether Brick", nether_wart_block = "~Clay (Red)", warped_wart_block = "~Cyan Wool", soul_sand = "Soul Sand",
    soul_soil = "~Soul Sand", magma_block = "Magma", glowstone = "Glowstone", shroomlight = "~Glowstone", nether_quartz_ore = "Quartz Ore",
    nether_gold_ore = "~Gold Ore", ancient_debris = "~Block of Netherite", netherite_block = "Block of Netherite", crimson_nylium = "~Netherrack",
    warped_nylium = "~Netherrack", end_stone = "End Stone", end_stone_bricks = "~End Stone", purpur_block = "~Clay (Magenta)",
    purpur_pillar = "~Clay (Magenta)", end_portal_frame = "~End Stone",

    coal_ore = "Coal Ore", iron_ore = "Iron Ore", gold_ore = "Gold Ore", diamond_ore = "Diamond Ore", emerald_ore = "Emerald Ore",
    lapis_ore = "Lapis Ore", redstone_ore = "Redstone Ore", copper_ore = "Copper Ore", coal_block = "Coal Block|Block of Coal",
    iron_block = "Iron Block", gold_block = "Block of Gold", diamond_block = "Diamond Block", emerald_block = "Emerald Block",
    lapis_block = "Lapis Block", redstone_block = "Block of Redstone|Redstone Block", copper_block = "Copper", exposed_copper = "Exposed Copper",
    weathered_copper = "Weathered Copper", oxidized_copper = "Oxidized Copper", cut_copper = "~Copper", exposed_cut_copper = "~Exposed Copper",
    weathered_cut_copper = "~Weathered Copper", oxidized_cut_copper = "~Oxidized Copper", chiseled_copper = "~Copper",
    exposed_chiseled_copper = "~Exposed Copper", weathered_chiseled_copper = "~Weathered Copper", oxidized_chiseled_copper = "~Oxidized Copper",
    raw_iron_block = "~Iron Ore", raw_gold_block = "~Block of Gold", raw_copper_block = "~Copper", amethyst_block = "~Purple Wool",
    budding_amethyst = "~Purple Wool", quartz_block = "Quartz Block", chiseled_quartz_block = "Chiseled Quartz Block",
    quartz_pillar = "Quartz Pillar", quartz_bricks = "~Quartz Block", smooth_quartz = "~Quartz Block", bricks = "Brick",
    prismarine = "~Prismatic Bricks", prismarine_bricks = "~Prismatic Bricks", dark_prismarine = "~Prismatic Bricks",
    sea_lantern = "~Glowstone", redstone_lamp = "~Glowstone", ochre_froglight = "~Glowstone", verdant_froglight = "~Glowstone",
    pearlescent_froglight = "~Glowstone", beacon = "~Diamond Block", terracotta = "Hardened Clay", glass = "Glass", tinted_glass = "~Glass (Gray)",

    bookshelf = "Book Shelf", chiseled_bookshelf = "~Book Shelf", crafting_table = "Crafting Table", barrel = "Barrel", jukebox = "Jukebox",
    note_block = "Note Block", fletching_table = "~Artisan Table", smithing_table = "~Artisan Table", cartography_table = "~Artisan Table",
    loom = "~Artisan Table", composter = "~Barrel", spawner = "Mob Spawner", trial_spawner = "~Mob Spawner", vault = "~Mob Spawner",
    tnt = "Explosive", anvil = "Anvil", chipped_anvil = "~Anvil", damaged_anvil = "~Anvil", daylight_detector = "Daylight Sensor",
    piston = "~Dropper", sticky_piston = "~Dropper", sculk = "~Obsidian", resin_block = "~Orange Wool", resin_bricks = "~Clay (Orange)",
    tube_coral_block = "~Lapis Block", brain_coral_block = "~Pink Wool", bubble_coral_block = "~Magenta Wool", fire_coral_block = "~Red Wool",
    horn_coral_block = "~Yellow Wool", dead_tube_coral_block = "~Light Gray Wool", dead_brain_coral_block = "~Light Gray Wool",
    dead_bubble_coral_block = "~Light Gray Wool", dead_fire_coral_block = "~Light Gray Wool", dead_horn_coral_block = "~Light Gray Wool",

    poppy = "Poppy", dandelion = "~Daisy", blue_orchid = "Blue Orchid", allium = "Allium", azure_bluet = "Azure Bluet", red_tulip = "Red Tulip",
    orange_tulip = "Orange Tulip", white_tulip = "White Tulip", pink_tulip = "Pink Tulip", oxeye_daisy = "Oxeye Daisy",
    cornflower = "~Blue Orchid", lily_of_the_valley = "~White Tulip", wither_rose = "~Poppy", torchflower = "~Orange Tulip",
    brown_mushroom = "Mushroom (Brown)", red_mushroom = "Mushroom (Red)", moss_carpet = "~Carpet (Green)", pale_moss_carpet = "~Carpet (Light Gray)",
}

local function approx(candidates)
    return string.sub((string.gsub("|" .. candidates, "|~?", "|~")), 2)
end

for color, title in ColorTitles do
    local wool = title .. " Wool"
    if color == "blue" then
        wool ..= "|~Lapis Block"
    elseif color == "green" then
        wool ..= "|~Clay (Green)"
    end
    local glazed = title .. " Glazed Terracotta"
    if color == "red" then
        glazed ..= "|Red Glaxed Terracotta"
    elseif color == "gray" then
        glazed ..= "|Grey Glazed Terracotta"
    elseif color == "light_gray" then
        glazed ..= "|Light Grey Glazed Terracotta"
    end
    Full[color .. "_wool"] = wool
    Full[color .. "_concrete"] = approx(wool)
    Full[color .. "_concrete_powder"] = approx(wool)
    Full[color .. "_shulker_box"] = approx(wool)
    Full[color .. "_terracotta"] = "Clay (" .. title .. ")"
    Full[color .. "_glazed_terracotta"] = glazed
    Full[color .. "_stained_glass"] = "Glass (" .. title .. ")"
    Full[color .. "_carpet"] = "Carpet (" .. title .. ")" .. (color == "white" and "|~Carpet (Light Gray)" or "")
end
Full.shulker_box = "~Purple Wool"

for _, ore in {"coal", "iron", "gold", "diamond", "emerald", "lapis", "redstone", "copper"} do
    Full["deepslate_" .. ore .. "_ore"] = approx(Full[ore .. "_ore"])
end

for _, wood in {"oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak"} do
    Full[wood .. "_wood"] = Full[wood .. "_log"]
    Full["stripped_" .. wood .. "_log"] = approx(Full[wood .. "_planks"])
    Full["stripped_" .. wood .. "_wood"] = approx(Full[wood .. "_planks"])
end
for _, wood in {"crimson", "warped"} do
    Full[wood .. "_hyphae"] = Full[wood .. "_stem"]
    Full["stripped_" .. wood .. "_stem"] = approx(Full[wood .. "_planks"])
    Full["stripped_" .. wood .. "_hyphae"] = approx(Full[wood .. "_planks"])
end
Full.stripped_bamboo_block = Full.bamboo_planks

local Ignored = {
    air = true, cave_air = true, void_air = true, structure_void = true, barrier = true, light = true, moving_piston = true,
    piston_head = true, fire = true, soul_fire = true,
}

local Alias = {grass = "short_grass", grass_path = "dirt_path", sign = "oak_sign", wall_sign = "oak_wall_sign"}

local BackRot = {south = 0, east = 90, north = 180, west = 270}
local FrontRot = {north = 0, west = 90, south = 180, east = 270}
local TrapRot = {west = 0, south = 90, east = 180, north = 270}
local FacingStep = {north = {0, -1}, south = {0, 1}, east = {1, 0}, west = {-1, 0}}

local function facing(candidates)
    return function(props)
        return "place", candidates, "Block", FrontRot[props.facing] or 0
    end
end

local function tall(candidates)
    return function(props)
        if props.half == "upper" then
            return "ignore"
        end
        return "place", candidates, "Block", 0
    end
end

local function liquid(candidates)
    return function(props)
        local level = tonumber(props.level) or 0
        if level == 0 or level >= 8 then
            return "place", candidates, "Block", 0
        end
        return "ignore"
    end
end

local function soaked(props)
    return "place", "~Water Source Block", "Block", 0
end

local function rail(candidates)
    return function(props)
        local shape = props.shape or "north_south"
        if shape == "north_south" or shape == "ascending_north" or shape == "ascending_south" then
            return "place", candidates, "Block", 0
        elseif shape == "east_west" or shape == "ascending_east" or shape == "ascending_west" then
            return "place", candidates, "Block", 90
        end
        return "place", approx(candidates), "Block", 0
    end
end

local function pane(candidates, props)
    if props.east == nil and props.west == nil and props.north == nil and props.south == nil then
        return "place", candidates, "Pane", 0, 0, 0, 0, "pane"
    end
    local alongX = (props.east == "true" and 1 or 0) + (props.west == "true" and 1 or 0)
    local alongZ = (props.north == "true" and 1 or 0) + (props.south == "true" and 1 or 0)
    return "place", candidates, "Pane", alongZ > alongX and 90 or 0
end

local Special = {
    water = liquid("Water Source Block"),
    lava = liquid("Lava Block|~Magma"),
    bubble_column = soaked,
    kelp = soaked,
    kelp_plant = soaked,
    seagrass = soaked,
    tall_seagrass = soaked,
    grass_block = function(props)
        return "place", props.snowy == "true" and "Snowy Grass Block|Grass" or "Grass", "Block", 0
    end,
    snow = function(props)
        if (tonumber(props.layers) or 1) >= 7 then
            return "place", "Snow Block", "Block", 0
        end
        return "place", "~Snow Block", "Slab", 0
    end,
    furnace = facing("Furnace"),
    blast_furnace = facing("~Furnace"),
    smoker = facing("~Furnace"),
    chest = facing("Chest"),
    trapped_chest = facing("~Chest"),
    ender_chest = facing("~Chest"),
    dropper = facing("Dropper"),
    dispenser = facing("~Dropper"),
    observer = facing("~Dropper"),
    carved_pumpkin = facing("~Jack On Latern"),
    jack_o_lantern = facing("Jack On Latern"),
    ladder = facing("Ladder"),
    tall_grass = tall("Tall Grass"),
    large_fern = tall("Tall Fern"),
    peony = tall("Tall Paeonia"),
    rose_bush = tall("Rose Bush"),
    lilac = tall("Lilac"),
    sunflower = tall("~Daisy"),
    rail = rail("Track"),
    powered_rail = rail("Powered Track"),
    detector_rail = rail("~Track"),
    activator_rail = rail("~Track"),
    glass_pane = function(props)
        return pane("Glass", props)
    end,
    iron_bars = function(props)
        return pane("~Glass (Gray)", props)
    end,
}

for color in ColorTitles do
    Special[color .. "_glazed_terracotta"] = facing(Full[color .. "_glazed_terracotta"])
end

local function baseBlock(base)
    return Full[base] or Full[base .. "s"] or Full[base .. "_planks"] or Full[base .. "_block"]
end

local function has(text, ...)
    for _, word in {...} do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

local function guess(id)
    local name = string.match(id, ":(.+)$") or id
    if string.find(name, "_leaves$") or string.find(name, "^leaves_") then
        if has(name, "redwood", "spruce", "pine", "fir", "dark") then
            return "~Pine Leaves"
        elseif has(name, "red", "maple", "crimson") then
            return "~Red Wool"
        elseif has(name, "orange") then
            return "~Orange Wool"
        elseif has(name, "yellow", "gold", "autumn") then
            return "~Aspen Leaves"
        elseif has(name, "pink", "cherry", "blossom", "sakura") then
            return "~Cherry Leaves"
        elseif has(name, "white", "pale", "snow", "frost") then
            return "~White Wool"
        end
        return "~Oak Leaves Fancy"
    end
    local trunk = string.match(name, "^(.+)_log$") or string.match(name, "^(.+)_wood$")
    if trunk then
        if has(trunk, "stripped") then
            return "~Planks"
        elseif has(trunk, "birch", "poplar", "aspen", "white", "pale") then
            return "~Birch Log"
        elseif has(trunk, "dark", "spruce", "pine", "fir", "redwood") then
            return "~Pine Log"
        end
        return "~Wood"
    end
    if string.find(name, "_planks$") then
        return "~Planks"
    end
    return nil
end

function Rules.Resolve(id, props)
    props = props or {}
    if string.sub(id, 1, 6) == "waxed_" then
        id = string.sub(id, 7)
    end
    id = Alias[id] or id
    if Ignored[id] then
        return "ignore"
    end
    local special = Special[id]
    if special then
        return special(props)
    end
    local direct = Full[id]
    if direct then
        return "place", direct, "Block", 0
    end
    local base = string.match(id, "^(.+)_stairs$")
    if base then
        local block = baseBlock(base)
        if not block then
            return "missing"
        end
        return "place", block, props.half == "top" and "UpsideStair" or "Stair", BackRot[props.facing] or 0
    end
    base = string.match(id, "^(.+)_slab$")
    if base then
        local block = baseBlock(base)
        if not block then
            return "missing"
        end
        if props.type == "double" then
            return "place", block, "Block", 0
        end
        return "place", block, "Slab", 0, 0, props.type == "top" and 2 or 0, 0
    end
    base = string.match(id, "^(.+)_wall$")
    if base then
        local block = baseBlock(base)
        if not block then
            return "missing"
        end
        return "place", approx(block), "Block", 0
    end
    base = string.match(id, "^(.+)_stained_glass_pane$")
    if base then
        local block = Full[base .. "_stained_glass"]
        if not block then
            return "missing"
        end
        return pane(block, props)
    end
    if string.find(id, "_fence_gate$") then
        return "place", "~Wood Fence", "Block", 0
    end
    if string.find(id, "_fence$") then
        return "place", id == "oak_fence" and "Wood Fence" or "~Wood Fence", "Block", 0
    end
    if string.find(id, "_trapdoor$") then
        return "place", id == "oak_trapdoor" and "Wooden Trapdoor" or "~Wooden Trapdoor", "Block", TrapRot[props.facing] or 0, 0, props.half == "top" and 3.5 or 0, 0
    end
    if string.find(id, "_door$") then
        if props.half == "upper" then
            return "ignore"
        end
        return "place", id == "oak_door" and "Door" or "~Door", "Block", FrontRot[props.facing] or 0
    end
    if string.find(id, "_bed$") then
        if props.part ~= "head" then
            return "ignore"
        end
        return "place", id == "red_bed" and "Red Bed" or "~Red Bed", "Block", BackRot[props.facing] or 0
    end
    if string.find(id, "hanging_sign$") then
        return "missing"
    end
    if string.find(id, "_wall_sign$") then
        local step = FacingStep[props.facing]
        return "place", id == "oak_wall_sign" and "Sign" or "~Sign", "Block", FrontRot[props.facing] or 0, step and -step[1] * 1.5 or 0, 0, step and -step[2] * 1.5 or 0
    end
    if string.find(id, "_sign$") then
        return "place", id == "oak_sign" and "Sign" or "~Sign", "Block", (180 - (tonumber(props.rotation) or 0) * 22.5) % 360
    end
    local rough = guess(id)
    if rough then
        return "place", rough, "Block", 0
    end
    return "missing"
end

Rules.Full = Full
Rules.Approx = approx

local World = {}

function World.Template(name)
    local found = ReplicatedStorage:FindFirstChild(name)
    if found and (found:IsA("BasePart") or (found:IsA("Model") and found.PrimaryPart)) then
        return found
    end
    return nil
end

function World.Stock(name)
    local resources = Player:FindFirstChild("Resources")
    local value = resources and resources:FindFirstChild((string.gsub(name, " ", "")))
    if value and value:IsA("ValueBase") and type(value.Value) == "number" then
        return value.Value
    end
    return nil
end

local Catalog = {}

local function options(candidates, shape)
    local list = {}
    for option in string.gmatch(candidates, "[^|]+") do
        local rough = string.sub(option, 1, 1) == "~"
        local name = rough and string.sub(option, 2) or option
        local template = World.Template(name)
        if template and (shape == "Block" or template:IsA("BasePart")) then
            table.insert(list, {Block = name, Approx = rough, Template = template})
        end
    end
    return list
end

function Catalog.Compile(model)
    local palette = model.Palette
    local missing, ignoredTotal, sourceTotal = {}, 0, 0
    for _, entry in palette do
        sourceTotal += entry.Count
        local kind, candidates, shape, rot, ox, oy, oz, flag = Rules.Resolve(entry.Id, entry.Props)
        if kind == "place" then
            entry.Options = options(candidates, shape)
            if #entry.Options == 0 then
                kind = "missing"
            else
                entry.Choice = 1
                entry.Shape, entry.Rot, entry.OX, entry.OY, entry.OZ, entry.Flag = shape, (rot or 0) + 0, (ox or 0) + 0, (oy or 0) + 0, (oz or 0) + 0, flag
            end
        end
        entry.Kind = kind
        if kind == "missing" then
            missing[entry.Id] = (missing[entry.Id] or 0) + entry.Count
        elseif kind == "ignore" then
            ignoredTotal += entry.Count
        end
    end

    local short = {}
    local limits = {}
    for _ = 1, 4 do
        local need = {}
        for _, entry in palette do
            if entry.Kind == "place" and entry.Count > 0 then
                local block = entry.Options[entry.Choice].Block
                need[block] = (need[block] or 0) + entry.Count
            end
        end
        local changed = false
        table.clear(limits)
        for block, amount in need do
            local have = World.Stock(block)
            if have and amount > have then
                local record = short[block] or {Block = block, Need = amount, Have = have}
                short[block] = record
                local moved = false
                for _, entry in palette do
                    if entry.Kind == "place" and entry.Options[entry.Choice].Block == block and entry.Options[entry.Choice + 1] then
                        entry.Choice += 1
                        entry.Swapped = true
                        record.Fallback = entry.Options[entry.Choice].Block
                        moved = true
                    end
                end
                if moved then
                    changed = true
                else
                    limits[block] = math.max(have, 0)
                end
            end
        end
        if not changed then
            break
        end
    end

    local specs, lookup = {}, {}
    local function intern(option, shape, rot, ox, oy, oz)
        local key = string.format("%s|%s|%.1f|%.2f|%.2f|%.2f", option.Block, shape, rot, ox, oy, oz)
        local spec = lookup[key]
        if not spec then
            local template = option.Template
            local isPart = template:IsA("BasePart")
            local cube = isPart and template.Size == Vector3.new(4, 4, 4)
            local plain = rot == 0 and ox == 0 and oz == 0
            spec = {
                Id = #specs + 1,
                Block = option.Block,
                Shape = shape,
                Rot = rot,
                OX = ox,
                OY = oy,
                OZ = oz,
                Template = template,
                IsPart = isPart,
                Count = 0,
                Solid = shape == "Block" and cube and template.Transparency < 0.1 and not string.find(option.Block, "Glass", 1, true),
                Merge = plain and cube and ((shape == "Block" and oy == 0 and 3) or (shape == "Slab" and 2)) or 0,
            }
            specs[spec.Id] = spec
            lookup[key] = spec
        end
        return spec
    end

    local specOf = table.create(#palette, 0)
    local turned = {}
    local replaced = {}
    for index, entry in palette do
        if entry.Kind == "place" then
            local option = entry.Options[entry.Choice]
            specOf[index] = intern(option, entry.Shape, entry.Rot, entry.OX, entry.OY, entry.OZ).Id
            if entry.Flag == "pane" then
                turned[index] = intern(option, entry.Shape, 90, entry.OX, entry.OY, entry.OZ).Id
            end
            if option.Approx and not entry.Swapped and entry.Count > 0 then
                local key = entry.Id .. "\0" .. option.Block
                local record = replaced[key]
                if not record then
                    record = {From = entry.Id, To = option.Block, Count = 0}
                    replaced[key] = record
                end
                record.Count += entry.Count
            end
        end
    end

    local grid = model.Grid
    local sx, sy, sz = model.SX, model.SY, model.SZ
    local minX, minY, minZ, maxX, maxY, maxZ = sx, sy, sz, -1, -1, -1
    local cell = 0
    for y = 0, sy - 1 do
        for z = 0, sz - 1 do
            for x = 0, sx - 1 do
                local value = readu16(grid, cell)
                cell += 2
                if value ~= 0 and specOf[value] ~= 0 then
                    if x < minX then
                        minX = x
                    end
                    if x > maxX then
                        maxX = x
                    end
                    if z < minZ then
                        minZ = z
                    end
                    if z > maxZ then
                        maxZ = z
                    end
                    if y < minY then
                        minY = y
                    end
                    maxY = y
                end
            end
        end
        Pace.Step()
    end

    local result = {
        Name = model.Name,
        Format = model.Format,
        Specs = specs,
        Total = 0,
        SourceTotal = sourceTotal,
        SX = 0,
        SY = 0,
        SZ = 0,
        Missing = {},
        MissingTotal = 0,
        Replaced = {},
        ReplacedTotal = 0,
        Short = {},
        Dropped = 0,
    }
    for id, count in missing do
        if count > 0 then
            table.insert(result.Missing, {Id = id, Count = count})
            result.MissingTotal += count
        end
    end
    table.sort(result.Missing, function(a, b)
        if a.Count ~= b.Count then
            return a.Count > b.Count
        end
        return a.Id < b.Id
    end)
    for _, record in replaced do
        table.insert(result.Replaced, record)
        result.ReplacedTotal += record.Count
    end
    table.sort(result.Replaced, function(a, b)
        if a.Count ~= b.Count then
            return a.Count > b.Count
        end
        return a.From < b.From
    end)
    for _, record in short do
        table.insert(result.Short, record)
    end
    table.sort(result.Short, function(a, b)
        return a.Block < b.Block
    end)
    if maxX < 0 then
        result.Cells = buffer.create(2)
        result.Covered = buffer.create(1)
        result.CoveredTotal = 0
        return result
    end

    local tx, ty, tz = maxX - minX + 1, maxY - minY + 1, maxZ - minZ + 1
    local cells = buffer.create(tx * ty * tz * 2)
    local used = {}
    local hasTurned = next(turned) ~= nil
    local total = 0
    local dropped = 0
    for y = 0, ty - 1 do
        for z = 0, tz - 1 do
            local source = ((minY + y) * sz + (minZ + z)) * sx + minX
            local target = ((y * tz) + z) * tx * 2
            for x = 0, tx - 1 do
                local value = readu16(grid, (source + x) * 2)
                local id = value ~= 0 and specOf[value] or 0
                if id ~= 0 then
                    if hasTurned and turned[value] then
                        local gx, gz = minX + x, minZ + z
                        local alongX, alongZ = 0, 0
                        if gx > 0 and readu16(grid, (source + x - 1) * 2) ~= 0 then
                            alongX += 1
                        end
                        if gx < sx - 1 and readu16(grid, (source + x + 1) * 2) ~= 0 then
                            alongX += 1
                        end
                        if gz > 0 and readu16(grid, (source + x - sx) * 2) ~= 0 then
                            alongZ += 1
                        end
                        if gz < sz - 1 and readu16(grid, (source + x + sx) * 2) ~= 0 then
                            alongZ += 1
                        end
                        if alongZ > alongX then
                            id = turned[value]
                        end
                    end
                    local spec = specs[id]
                    local limit = limits[spec.Block]
                    if limit then
                        local count = used[spec.Block] or 0
                        if count >= limit then
                            id = 0
                            dropped += 1
                        else
                            used[spec.Block] = count + 1
                        end
                    end
                    if id ~= 0 then
                        writeu16(cells, target + x * 2, id)
                        spec.Count += 1
                        total += 1
                    end
                end
            end
        end
        Pace.Step()
    end
    local solid, loose = {[0] = false}, {[0] = false}
    for id, spec in specs do
        solid[id] = spec.Solid
        loose[id] = spec.IsPart and not spec.Template.Anchored
    end
    local covered = buffer.create(tx * ty * tz)
    local coveredTotal = 0
    local layer = tx * tz
    for y = 1, ty - 2 do
        for z = 1, tz - 2 do
            local row = y * layer + z * tx
            for x = 1, tx - 2 do
                local at = row + x
                if readu16(cells, at * 2) ~= 0 then
                    local above = readu16(cells, (at + layer) * 2)
                    if solid[above] and not loose[above]
                        and solid[readu16(cells, (at - layer) * 2)]
                        and solid[readu16(cells, (at - 1) * 2)]
                        and solid[readu16(cells, (at + 1) * 2)]
                        and solid[readu16(cells, (at - tx) * 2)]
                        and solid[readu16(cells, (at + tx) * 2)]
                    then
                        writeu8(covered, at, 1)
                        coveredTotal += 1
                    end
                end
            end
        end
        Pace.Step()
    end
    result.Cells = cells
    result.Covered = covered
    result.CoveredTotal = coveredTotal
    result.SX, result.SY, result.SZ = tx, ty, tz
    result.Total = total
    result.Dropped = dropped
    return result
end

local Preview = {Alpha = 0.5, TextureLimit = 9000, PartLimit = 22000, ModelLimit = 1500, Token = 0}

local FaceBits = {
    [Enum.NormalId.Top] = 1,
    [Enum.NormalId.Bottom] = 2,
    [Enum.NormalId.Right] = 4,
    [Enum.NormalId.Left] = 8,
    [Enum.NormalId.Back] = 16,
    [Enum.NormalId.Front] = 32,
}

local FaceCount = {[0] = 0}
for mask = 1, 63 do
    FaceCount[mask] = FaceCount[rshift(mask, 1)] + band(mask, 1)
end

local function quiet(part)
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Locked = true
end

local function ghostPart(spec, textured, mask)
    local cache = spec.Ghosts
    if not cache then
        cache = {}
        spec.Ghosts = cache
    end
    local key = textured and mask or -1
    local prototype = cache[key]
    if prototype then
        return prototype
    end
    local template = spec.Template
    if textured then
        prototype = template:Clone()
        local kept = 0
        for _, child in prototype:GetChildren() do
            local bit = child:IsA("Decal") and FaceBits[child.Face]
            if bit and band(mask, bit) ~= 0 then
                child.Transparency = math.max(child.Transparency, Preview.Alpha)
                kept += 1
            else
                child:Destroy()
            end
        end
        prototype.Transparency = kept > 0 and 1 or math.max(template.Transparency, Preview.Alpha)
    else
        prototype = Instance.new("Part")
        prototype.Size = template.Size
        prototype.Color = template.Color
        prototype.Material = Enum.Material.SmoothPlastic
        prototype.TopSurface = Enum.SurfaceType.Smooth
        prototype.BottomSurface = Enum.SurfaceType.Smooth
        prototype.Transparency = template.Transparency > 0.5 and 0.75 or Preview.Alpha
    end
    prototype.Name = "Ghost"
    quiet(prototype)
    cache[key] = prototype
    return prototype
end

local function ghostModel(spec)
    local prototype = spec.GhostModel
    if prototype then
        return prototype
    end
    prototype = spec.Template:Clone()
    for _, item in prototype:GetDescendants() do
        if item:IsA("BasePart") then
            quiet(item)
            if item.Transparency < 0.95 then
                item.Transparency = math.max(item.Transparency, Preview.Alpha)
            end
        elseif item:IsA("Decal") then
            if item.Transparency < 0.95 then
                item.Transparency = math.max(item.Transparency, Preview.Alpha)
            end
        elseif item:IsA("LuaSourceContainer") or item:IsA("Sound") or item:IsA("ClickDetector") or item:IsA("ProximityPrompt") or item:IsA("Light") or item:IsA("ParticleEmitter") then
            item:Destroy()
        end
    end
    prototype.Name = "Ghost"
    spec.GhostModel = prototype
    return prototype
end

function Preview.Build(schematic, alive)
    local sx, sy, sz = schematic.SX, schematic.SY, schematic.SZ
    local cells, specs = schematic.Cells, schematic.Specs
    local layer = sx * sz
    local solid = table.create(#specs, false)
    for id, spec in specs do
        solid[id] = spec.Solid
    end
    solid[0] = false

    local function hidden(x, y, z, at)
        if x == 0 or y == 0 or z == 0 or x == sx - 1 or y == sy - 1 or z == sz - 1 then
            return false
        end
        return solid[readu16(cells, (at - 1) * 2)]
            and solid[readu16(cells, (at + 1) * 2)]
            and solid[readu16(cells, (at - sx) * 2)]
            and solid[readu16(cells, (at + sx) * 2)]
            and solid[readu16(cells, (at - layer) * 2)]
            and solid[readu16(cells, (at + layer) * 2)]
    end

    local function open(x0, x1, y0, y1, z0, z1)
        for y = y0, y1 do
            for z = z0, z1 do
                local row = y * layer + z * sx
                for x = x0, x1 do
                    if not solid[readu16(cells, (row + x) * 2)] then
                        return true
                    end
                end
            end
        end
        return false
    end

    local function faces(x, y, z, w, h, d)
        local x1, y1, z1 = x + w - 1, y + h - 1, z + d - 1
        local mask = 0
        if y1 == sy - 1 or open(x, x1, y1 + 1, y1 + 1, z, z1) then
            mask += 1
        end
        if y > 0 and open(x, x1, y - 1, y - 1, z, z1) then
            mask += 2
        end
        if x1 == sx - 1 or open(x1 + 1, x1 + 1, y, y1, z, z1) then
            mask += 4
        end
        if x == 0 or open(x - 1, x - 1, y, y1, z, z1) then
            mask += 8
        end
        if z1 == sz - 1 or open(x, x1, y, y1, z1 + 1, z1 + 1) then
            mask += 16
        end
        if z == 0 or open(x, x1, y, y1, z - 1, z - 1) then
            mask += 32
        end
        return mask
    end

    local boxes, boxCount = {}, 0
    local singles, singleCount = {}, 0
    local visited = buffer.create(layer)
    local carried = {}
    for y = 0, sy - 1 do
        buffer.fill(visited, 0, 0)
        local previous = carried
        carried = {}
        local base = y * layer
        for z = 0, sz - 1 do
            for x = 0, sx - 1 do
                local index = x + z * sx
                if readu8(visited, index) == 0 then
                    local id = readu16(cells, (base + index) * 2)
                    if id ~= 0 and not hidden(x, y, z, base + index) then
                        local mode = specs[id].Merge
                        if mode == 0 then
                            singles[singleCount + 1] = id
                            singles[singleCount + 2] = x
                            singles[singleCount + 3] = y
                            singles[singleCount + 4] = z
                            singleCount += 4
                        else
                            local w = 1
                            while x + w < sx do
                                local at = index + w
                                if readu8(visited, at) ~= 0 or readu16(cells, (base + at) * 2) ~= id or hidden(x + w, y, z, base + at) then
                                    break
                                end
                                w += 1
                            end
                            local d = 1
                            while z + d < sz do
                                local row = index + d * sx
                                local fits = true
                                for i = 0, w - 1 do
                                    local at = row + i
                                    if readu8(visited, at) ~= 0 or readu16(cells, (base + at) * 2) ~= id or hidden(x + i, y, z + d, base + at) then
                                        fits = false
                                        break
                                    end
                                end
                                if not fits then
                                    break
                                end
                                d += 1
                            end
                            for j = 0, d - 1 do
                                buffer.fill(visited, index + j * sx, 1, w)
                            end
                            local key = mode == 3 and (id .. ":" .. index .. ":" .. w .. ":" .. d) or nil
                            local at = key and previous[key]
                            if at then
                                boxes[at + 5] += 1
                                carried[key] = at
                            else
                                boxes[boxCount + 1] = id
                                boxes[boxCount + 2] = x
                                boxes[boxCount + 3] = y
                                boxes[boxCount + 4] = z
                                boxes[boxCount + 5] = w
                                boxes[boxCount + 6] = 1
                                boxes[boxCount + 7] = d
                                if key then
                                    carried[key] = boxCount + 1
                                end
                                boxCount += 7
                            end
                        end
                    end
                end
            end
        end
        Pace.Step()
        if not alive() then
            return nil
        end
    end

    local masks = table.create(boxCount // 7, 63)
    local textures = 0
    for at = 1, boxCount, 7 do
        local slot = (at + 6) // 7
        if specs[boxes[at]].Merge == 3 then
            masks[slot] = faces(boxes[at + 1], boxes[at + 2], boxes[at + 3], boxes[at + 4], boxes[at + 5], boxes[at + 6])
        end
        textures += FaceCount[masks[slot]]
        if slot % 400 == 0 then
            Pace.Step()
        end
    end
    for at = 1, singleCount, 4 do
        local spec = specs[singles[at]]
        if spec.IsPart then
            textures += (spec.Shape == "Stair" or spec.Shape == "UpsideStair") and 12 or 6
        end
    end
    if not alive() then
        return nil
    end

    local textured = textures <= Preview.TextureLimit
    local model = Instance.new("Model")
    model.Name = "SchematicPreview"
    local pivot = Instance.new("Part")
    pivot.Name = "Pivot"
    pivot.Size = Vector3.new(0.2, 0.2, 0.2)
    pivot.Transparency = 1
    quiet(pivot)
    pivot.Parent = model
    model.PrimaryPart = pivot

    local px, pz = sx // 2, sz // 2
    local made, models, skipped = 0, 0, 0
    local limit = Preview.PartLimit
    for at = 1, boxCount, 7 do
        local mask = masks[(at + 6) // 7]
        if mask ~= 0 then
            if made >= limit then
                skipped += 1
            else
                local spec = specs[boxes[at]]
                local x, y, z, w, h, d = boxes[at + 1], boxes[at + 2], boxes[at + 3], boxes[at + 4], boxes[at + 5], boxes[at + 6]
                local part = ghostPart(spec, textured, mask):Clone()
                local cx, cz = (x - px + (w - 1) / 2) * 4, (z - pz + (d - 1) / 2) * 4
                if spec.Shape == "Slab" then
                    part.Size = Vector3.new(w * 4, 2, d * 4)
                    part.CFrame = CFrame.new(cx, y * 4 - 1 + spec.OY, cz)
                else
                    part.Size = Vector3.new(w * 4, h * 4, d * 4)
                    part.CFrame = CFrame.new(cx, (y + (h - 1) / 2) * 4, cz)
                end
                part.Parent = model
                made += 1
                if made % 200 == 0 then
                    Pace.Step()
                    if not alive() then
                        model:Destroy()
                        return nil
                    end
                end
            end
        end
    end
    for at = 1, singleCount, 4 do
        local spec = specs[singles[at]]
        local frame = CFrame.new((singles[at + 1] - px) * 4 + spec.OX, singles[at + 2] * 4 + spec.OY, (singles[at + 3] - pz) * 4 + spec.OZ) * CFrame.Angles(0, math.rad(spec.Rot), 0)
        if made >= limit then
            skipped += 1
        elseif not spec.IsPart then
            if models < Preview.ModelLimit then
                local clone = ghostModel(spec):Clone()
                if clone.PrimaryPart then
                    clone:SetPrimaryPartCFrame(frame)
                    clone.Parent = model
                    models += 1
                    made += 1
                else
                    clone:Destroy()
                end
            else
                skipped += 1
            end
        else
            local prototype = ghostPart(spec, textured, 63)
            local shape = spec.Shape
            local part = prototype:Clone()
            if shape == "Slab" then
                part.Size = Vector3.new(4, 2, 4)
                part.CFrame = frame * CFrame.new(0, -1, 0)
            elseif shape == "Pane" then
                part.Size = Vector3.new(4, 4, 0.25)
                part.CFrame = frame
            elseif shape == "Stair" or shape == "UpsideStair" then
                local side = shape == "Stair" and 1 or -1
                part.Size = Vector3.new(4, 2, 4)
                part.CFrame = frame * CFrame.new(0, -side, 0)
                local step = prototype:Clone()
                step.Size = Vector3.new(4, 2, 2)
                step.CFrame = frame * CFrame.new(0, side, 1)
                step.Parent = model
            else
                part.CFrame = frame
            end
            part.Parent = model
            made += 1
        end
        if made % 200 == 0 then
            Pace.Step()
            if not alive() then
                model:Destroy()
                return nil
            end
        end
    end

    local bounds = Instance.new("Part")
    bounds.Name = "Bounds"
    bounds.Transparency = 1
    bounds.Size = Vector3.new(sx * 4, sy * 4, sz * 4)
    bounds.CFrame = CFrame.new((sx / 2 - px - 0.5) * 4, (sy / 2 - 0.5) * 4, (sz / 2 - pz - 0.5) * 4)
    quiet(bounds)
    local outline = Instance.new("SelectionBox")
    outline.LineThickness = 0.06
    outline.Color3 = Color3.fromRGB(110, 205, 255)
    outline.SurfaceTransparency = 1
    outline.Adornee = bounds
    outline.Parent = bounds
    bounds.Parent = model
    return model, {Parts = made, Textured = textured, Trimmed = skipped > 0}
end

local Airflow = loadstring(game:HttpGet("https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"))()
local App = {
    Alive = true,
    Controls = {},
    Connections = {},
    WarnedAt = {},
    Files = {},
    FileLabels = {},
    Place = {X = 0, Y = 0, Z = 0, Turn = 0},
    Options = {Rate = 9, Teleport = true, Hollow = false, Preview = true, AntiAFK = true},
    History = {},
    LoadToken = 0,
    InfoText = "Put a .litematic, .schematic or .schem file into the executor workspace folder, then pick it above.",
    ReportText = "Pick a schematic to see which blocks this game does not have.",
    StatusText = "Idle",
}
Environment[AppKey] = App
if Airflow.Touch then
    Preview.TextureLimit = 3000
    Preview.PartLimit = 9000
end

local Extensions = {litematic = true, schematic = true, schem = true, nbt = true}
local Folders = {"", "schematics", "Schematics", "litematics"}

function App:Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self.Connections, connection)
    return connection
end

function App:Notify(title, content, kind)
    if self.Alive and self.Window then
        pcall(function()
            self.Window:Notify({Title = title, Content = content, Type = kind or "Info", Duration = 5})
        end)
    end
end

function App:Warn(key, message)
    local now = os.clock()
    if now >= (self.WarnedAt[key] or 0) then
        self.WarnedAt[key] = now + 15
        warn("[Voxel Schematics] " .. key .. ": " .. tostring(message))
    end
end

function App:Copy(text)
    if type(setclipboard) == "function" and pcall(setclipboard, text) then
        self:Notify("Copied", text, "Success")
    else
        self:Notify("Link", text, "Info")
    end
end

function App:Root()
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root, character:FindFirstChildOfClass("Humanoid")
    end
    return nil
end

function World.BlockAt(position)
    for _, part in workspace:GetPartBoundsInBox(CFrame.new(position), Vector3.new(3.9, 3.9, 3.9)) do
        local root = part
        while root and root ~= workspace do
            local tag = root:FindFirstChild("BlockType")
            if tag and tag:IsA("StringValue") then
                local at
                if root:IsA("Model") then
                    at = root.PrimaryPart and root.PrimaryPart.Position
                elseif root:IsA("BasePart") then
                    at = root.Position
                end
                if at and (at - position).Magnitude < ((root:IsA("BasePart") and not root.Anchored) and 2 or 0.1) then
                    return root, tag.Value
                end
                break
            end
            root = root.Parent
        end
    end
    return nil
end

function World.Point(place, x, y, z)
    local turn = place.Turn
    local wx, wz
    if turn == 0 then
        wx, wz = x, z
    elseif turn == 1 then
        wx, wz = z, -x
    elseif turn == 2 then
        wx, wz = -x, -z
    else
        wx, wz = -z, x
    end
    return Vector3.new(place.X * 4 + wx, place.Y * 4 + y, place.Z * 4 + wz)
end

function App:ScanFiles()
    local files, labels, taken = {}, {}, {}
    for _, folder in Folders do
        local ok, list = pcall(listfiles, folder)
        if folder == "" and not (ok and type(list) == "table") then
            ok, list = pcall(listfiles, ".")
        end
        if ok and type(list) == "table" then
            for _, path in list do
                if type(path) == "string" then
                    local name = string.match(string.gsub(path, "\\", "/"), "([^/]+)$")
                    local extension = name and string.match(name, "%.(%w+)$")
                    if extension and Extensions[string.lower(extension)] and not taken[string.lower(path)] then
                        taken[string.lower(path)] = true
                        local label = name
                        if files[label] then
                            label = string.gsub(path, "\\", "/")
                        end
                        if not files[label] then
                            files[label] = path
                            table.insert(labels, label)
                        end
                    end
                end
            end
        end
    end
    table.sort(labels, function(a, b)
        return string.lower(a) < string.lower(b)
    end)
    return files, labels
end

function App:RefreshFiles(announce)
    local files, labels = self:ScanFiles()
    local changed = #labels ~= #self.FileLabels
    if not changed then
        for index, label in labels do
            if self.FileLabels[index] ~= label then
                changed = true
                break
            end
        end
    end
    self.Files, self.FileLabels = files, labels
    local dropdown = self.Controls.File
    if dropdown and changed and not dropdown.Open then
        pcall(function()
            dropdown:Refresh(labels, true)
        end)
    end
    if announce then
        if #labels == 0 then
            self:Notify("No schematics", "Put .litematic, .schematic or .schem files into the executor workspace folder.", "Warning")
        else
            self:Notify("Schematics", tostring(#labels) .. (#labels == 1 and " file found." or " files found."), "Success")
        end
    end
    return changed
end

local function grouped(value)
    local text = tostring(math.floor(value + 0.5))
    local result = string.gsub(string.reverse(text), "(%d%d%d)", "%1 ")
    return (string.gsub(string.reverse(result), "^ ", ""))
end

local function duration(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then
        return seconds .. " s"
    elseif seconds < 3600 then
        return string.format("%d min %02d s", seconds // 60, seconds % 60)
    end
    return string.format("%d h %02d min", seconds // 3600, seconds % 3600 // 60)
end

App.Grouped = grouped
App.Duration = duration

function App:Rate()
    return math.clamp(math.min(self.Options.Rate, self.RateCap or math.huge), 1, 60)
end

function App:Describe(schematic)
    local lines = {}
    table.insert(lines, schematic.File .. " (" .. schematic.Format .. ")")
    if schematic.Total == 0 then
        table.insert(lines, "Nothing in this file can be built in this game.")
    else
        local covered = schematic.CoveredTotal
        local count = schematic.Total - (self.Options.Hollow and covered or 0)
        local size = string.format("%d x %d x %d blocks, %s to place", schematic.SX, schematic.SY, schematic.SZ, grouped(count))
        if self.Options.Hollow and covered > 0 then
            size ..= ", " .. grouped(covered) .. " hidden ones skipped"
        end
        table.insert(lines, size)
        table.insert(lines, "About " .. duration(count / self:Rate()) .. " at " .. tostring(self:Rate()) .. " blocks per second")
        if not self.Options.Hollow and covered >= 200 and covered >= schematic.Total * 0.15 then
            table.insert(lines, "Skip Hidden Blocks in the Build tab would leave out " .. grouped(covered) .. " of them")
        end
    end
    self.InfoText = table.concat(lines, "\n")

    local report = {}
    if #schematic.Missing > 0 then
        local names = {}
        for index, record in schematic.Missing do
            if index > 16 then
                table.insert(names, "and " .. tostring(#schematic.Missing - 16) .. " more")
                break
            end
            table.insert(names, record.Id .. " x" .. grouped(record.Count))
        end
        table.insert(report, "Not in this game, skipped (" .. grouped(schematic.MissingTotal) .. " blocks):\n" .. table.concat(names, ", "))
    end
    if #schematic.Short > 0 then
        local rows = {}
        for _, record in schematic.Short do
            local row = record.Block .. ": need " .. grouped(record.Need) .. ", you have " .. grouped(record.Have)
            if record.Fallback then
                row ..= ", " .. record.Fallback .. " is used instead"
            else
                row ..= ", " .. grouped(record.Need - math.max(record.Have, 0)) .. " skipped"
            end
            table.insert(rows, row)
        end
        table.insert(report, "Not enough in your backpack:\n" .. table.concat(rows, "\n"))
    end
    if #schematic.Replaced > 0 then
        local rows = {}
        for index, record in schematic.Replaced do
            if index > 12 then
                table.insert(rows, "and " .. tostring(#schematic.Replaced - 12) .. " more")
                break
            end
            table.insert(rows, record.From .. " -> " .. record.To .. " x" .. grouped(record.Count))
        end
        table.insert(report, "Replaced with the closest block (" .. grouped(schematic.ReplacedTotal) .. " blocks):\n" .. table.concat(rows, "\n"))
    end
    if #report == 0 then
        table.insert(report, "This game has every block the schematic needs.")
    end
    self.ReportText = table.concat(report, "\n\n")
end

function App:PivotFrame()
    local place = self.Place
    return CFrame.new(place.X * 4, place.Y * 4, place.Z * 4) * CFrame.Angles(0, place.Turn * math.pi / 2, 0)
end

function App:SyncPreview()
    local model = self.PreviewModel
    if not model then
        return
    end
    if self.Options.Preview and self.Schematic then
        model:PivotTo(self:PivotFrame())
        if model.Parent ~= workspace then
            model.Parent = workspace
        end
    elseif model.Parent then
        model.Parent = nil
    end
end

function App:DropPreview()
    Preview.Token += 1
    if self.PreviewModel then
        self.PreviewModel:Destroy()
        self.PreviewModel = nil
    end
end

function App:RebuildPreview()
    self:DropPreview()
    local schematic = self.Schematic
    if not schematic or schematic.Total == 0 or not self.Options.Preview then
        return
    end
    local token = Preview.Token
    task.spawn(function()
        local ok, model, info = pcall(Preview.Build, schematic, function()
            return self.Alive and token == Preview.Token
        end)
        if not ok then
            self:Warn("Preview", model)
            return
        end
        if not model then
            return
        end
        if not self.Alive or token ~= Preview.Token then
            model:Destroy()
            return
        end
        self.PreviewModel = model
        self:SyncPreview()
        if info.Trimmed then
            self:Notify("Preview", "The build is very large, so only part of it is drawn.", "Info")
        end
    end)
end

function App:Footprint()
    local schematic = self.Schematic
    if not schematic then
        return 1, 1
    end
    if self.Place.Turn % 2 == 0 then
        return schematic.SX, schematic.SZ
    end
    return schematic.SZ, schematic.SX
end

function App:PushPlace()
    for _, axis in {"X", "Y", "Z"} do
        local control = self.Controls[axis]
        if control then
            pcall(function()
                control:Set(self.Place[axis], true)
            end)
        end
    end
    local turn = self.Controls.Turn
    if turn then
        pcall(function()
            turn:SetText("Rotation: " .. tostring(self.Place.Turn * 90) .. "°")
        end)
    end
    self:SyncPreview()
end

function App:MoveToPlayer()
    local root, humanoid = self:Root()
    if not root then
        return false
    end
    local drop = 3
    if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
        drop = humanoid.HipHeight + root.Size.Y / 2
    end
    local camera = workspace.CurrentCamera
    local look = camera and camera.CFrame.LookVector or root.CFrame.LookVector
    local stepX, stepZ = 0, 0
    if math.abs(look.X) > math.abs(look.Z) then
        stepX = look.X > 0 and 1 or -1
    else
        stepZ = look.Z > 0 and 1 or -1
    end
    local width, depth = self:Footprint()
    local reach = math.ceil((stepX ~= 0 and width or depth) / 2) + 2
    local place = self.Place
    place.X = math.floor(root.Position.X / 4 + 0.5) + stepX * reach
    place.Z = math.floor(root.Position.Z / 4 + 0.5) + stepZ * reach
    place.Y = math.floor((root.Position.Y - drop + 2) / 4 + 0.5)
    self:PushPlace()
    return true
end

function App:Rotate()
    self.Place.Turn = (self.Place.Turn + 1) % 4
    self:PushPlace()
end

function App:Select(label)
    local path = self.Files[label]
    if not path then
        return
    end
    self.LoadToken += 1
    local token = self.LoadToken
    self.Selected = label
    self.InfoText = "Reading " .. label .. "..."
    task.spawn(function()
        local ok, result = pcall(function()
            local schematic = Catalog.Compile(Formats.Load(readfile(path)))
            schematic.File = label
            return schematic
        end)
        if not self.Alive or token ~= self.LoadToken then
            return
        end
        if not ok then
            local message = string.gsub(tostring(result), "^.-:%d+: ", "")
            self.Schematic = nil
            self:DropPreview()
            self.InfoText = label .. " could not be read: " .. message
            self.ReportText = "Pick a schematic to see which blocks this game does not have."
            self:Notify("Schematic", label .. " could not be read: " .. message, "Error")
            return
        end
        self.Schematic = result
        self:Describe(result)
        self:MoveToPlayer()
        self:RebuildPreview()
        if result.Total == 0 then
            self:Notify("Schematic", "Nothing in " .. label .. " can be built in this game.", "Warning")
        elseif #result.Missing > 0 or #result.Short > 0 then
            self:Notify("Schematic", label .. " is loaded. Some blocks are missing, see the list in the Schematic tab.", "Warning")
        else
            self:Notify("Schematic", label .. " is loaded, " .. grouped(result.Total) .. " blocks.", "Success")
        end
    end)
end

local Reach = 40

local Job = {}
Job.__index = Job

function Job.new(kind, count)
    return setmetatable({
        Kind = kind,
        Count = count,
        Cursor = 0,
        Retry = {},
        Far = {},
        Tries = {},
        Pending = {},
        PendingCount = 0,
        Done = 0,
        Existing = 0,
        Blocked = 0,
        Failed = 0,
        Errors = {},
        Sends = 0,
        Rejects = 0,
        Streak = 0,
        NextAt = os.clock(),
        SettleUntil = 0,
        ExpireAt = 0,
        FarAt = 0,
        FlewAt = os.clock(),
        StartedAt = os.clock(),
        Settle = 0.3,
        StreamWait = 1,
        Streamed = true,
        Paused = false,
        Finished = false,
        Cancelled = false,
    }, Job)
end

function Job:Resolved()
    return self.Done + self.Existing + self.Blocked + self.Failed
end

function Job:Take()
    local retry = self.Retry
    local size = #retry
    if size > 0 then
        local index = retry[size]
        retry[size] = nil
        return index
    end
    if self.Cursor < self.Count then
        local index = self.Cursor
        self.Cursor += 1
        return index
    end
    return nil
end

function Job:Skip()
    return false
end

function Job:Fail(reason)
    self.Failed += 1
    self.Errors[reason] = (self.Errors[reason] or 0) + 1
    self.Streak += 1
    if self.Streak >= 30 and not self.Cancelled then
        self.Cancelled = true
        self.Refused = reason
    end
end

function Job:Again(index, reason)
    local tries = (self.Tries[index] or 0) + 1
    if tries > 8 then
        self.Tries[index] = nil
        self:Fail(reason)
    else
        self.Tries[index] = tries
        table.insert(self.Retry, index)
    end
end

function Job:Throttle(index)
    if App.Options.Rate > 9 and not App.RateCap then
        App.RateCap = 9
    end
    self.Rejects += 1
    self.NextAt = math.max(self.NextAt, os.clock() + 0.35)
    table.insert(self.Retry, index)
end

function Job:Sent()
    self.Sends += 1
    if self.Sends % 60 == 0 then
        if self.Rejects >= 4 then
            App.RateCap = math.max(5, App:Rate() - 0.5)
        end
        self.Rejects = 0
    end
end

function Job:Fly(position, a, b, c, d, now)
    local root, humanoid = App:Root()
    if not root then
        return
    end
    local point = self:HoverPoint(position, a, b, c, d)
    if (point - position).Magnitude > Reach - 4 then
        point = position + Vector3.new(0, 10, 0)
    end
    if not self.Origin then
        self.Origin = root.CFrame
    end
    if humanoid and humanoid.SeatPart then
        humanoid.Sit = false
    end
    self.Hover = point
    self.FlewAt = now
    self.SettleUntil = now + self.Settle
    self.Streamed = false
    root.CFrame = CFrame.new(point) * root.CFrame.Rotation
    root.AssemblyLinearVelocity = Vector3.zero
    task.spawn(function()
        pcall(Player.RequestStreamAroundAsync, Player, position, self.StreamWait)
        if self.FlewAt == now then
            self.Streamed = true
        end
    end)
end

function Job:Pump(now)
    if now >= self.ExpireAt then
        self.ExpireAt = now + 1
        for id, pending in self.Pending do
            if now - pending.At > 6 then
                self.Pending[id] = nil
                self.PendingCount -= 1
                self:Again(pending.Index, "The server did not answer")
            end
        end
    end
    if self.Paused or now < self.SettleUntil then
        return
    end
    if not self.Streamed and now - self.FlewAt < self.StreamWait then
        return
    end
    local teleport = App.Options.Teleport
    local root = App:Root()
    if not root then
        return
    end
    local from = self.Hover or root.Position
    if #self.Far > 0 and (teleport or now >= self.FarAt) then
        self.FarAt = now + 0.5
        local kept = {}
        for _, index in self.Far do
            if teleport or (self:Locate(index) - from).Magnitude <= Reach then
                table.insert(self.Retry, index)
            else
                table.insert(kept, index)
            end
        end
        self.Far = kept
    end
    local interval = 1 / math.min(App:Rate(), self.MaxRate or math.huge)
    if now - self.NextAt > interval * 2 then
        self.NextAt = now - interval
    end
    local sends, scans = 0, 0
    while sends < 4 and scans < 300 and now >= self.NextAt and self.PendingCount < 40 do
        local index = self:Take()
        if not index then
            break
        end
        scans += 1
        local position, a, b, c, d = self:Locate(index)
        if not self:Skip(position, a) then
            if (position - from).Magnitude > Reach or (self.Inside and teleport and not self.Hover) then
                if teleport then
                    table.insert(self.Retry, index)
                    self:Fly(position, a, b, c, d, now)
                    return
                end
                table.insert(self.Far, index)
            else
                local sent = self:Dispatch(index, position, a, b, c, d, now)
                if sent == "wait" then
                    return
                elseif sent then
                    sends += 1
                    self.NextAt += interval
                    self:Sent()
                end
            end
        end
    end
    if self.Cursor >= self.Count and #self.Retry == 0 and self.PendingCount == 0 and #self.Far == 0 then
        self.Finished = true
    end
end

local function buildJob(schematic, place, hollow)
    local sx, sy, sz = schematic.SX, schematic.SY, schematic.SZ
    local cells, specs = schematic.Cells, schematic.Specs
    local covered = hollow and schematic.Covered or nil
    local order = buffer.create(math.max(schematic.Total, 1) * 4)
    local count = 0
    local columns = {}
    for cx = 0, sx - 1, 8 do
        table.insert(columns, cx)
    end
    for tier = 0, sy - 1, 4 do
        local row = 0
        for cz = 0, sz - 1, 8 do
            row += 1
            for step = 1, #columns do
                local cx = columns[row % 2 == 1 and step or #columns + 1 - step]
                for y = tier, math.min(tier + 4, sy) - 1 do
                    for z = cz, math.min(cz + 8, sz) - 1 do
                        local base = (y * sz + z) * sx
                        for x = cx, math.min(cx + 8, sx) - 1 do
                            if readu16(cells, (base + x) * 2) ~= 0 and not (covered and readu8(covered, base + x) == 1) then
                                writeu32(order, count * 4, base + x)
                                count += 1
                            end
                        end
                    end
                end
            end
        end
        Pace.Step()
    end

    local job = Job.new("build", count)
    job.Positions = {}
    job.Names = {}
    local px, pz = sx // 2, sz // 2
    local turn = place.Turn * 90

    local low = World.Point(place, -px * 4 - 2, -2, -pz * 4 - 2)
    local high = World.Point(place, (sx - px) * 4 - 2, sy * 4 - 2, (sz - pz) * 4 - 2)
    job.Low = Vector3.new(math.min(low.X, high.X), low.Y, math.min(low.Z, high.Z))
    job.High = Vector3.new(math.max(low.X, high.X), high.Y, math.max(low.Z, high.Z))

    function job:Locate(index)
        local cell = readu32(order, index * 4)
        local x = cell % sx
        local rest = cell // sx
        local z = rest % sz
        local y = rest // sz
        local spec = specs[readu16(cells, cell * 2)]
        return World.Point(place, (x - px) * 4 + spec.OX, y * 4 + spec.OY, (z - pz) * 4 + spec.OZ), spec, x, y, z
    end

    function job:HoverPoint(_, _, x, y, z)
        local x0, z0 = (x // 8) * 8, (z // 8) * 8
        local cx = (x0 + math.min(x0 + 7, sx - 1)) / 2
        local cz = (z0 + math.min(z0 + 7, sz - 1)) / 2
        local top = math.min((y // 4) * 4 + 3, sy - 1)
        return World.Point(place, (cx - px) * 4, top * 4 + 10, (cz - pz) * 4)
    end

    function job:Skip(position, spec)
        local found, kind = World.BlockAt(position)
        if not found then
            return false
        end
        if kind == spec.Block then
            self.Existing += 1
        else
            self.Blocked += 1
        end
        return true
    end

    function job:Dispatch(index, position, spec, _, _, _, now)
        local id = HttpService:GenerateGUID()
        self.Pending[id] = {Index = index, At = now, Position = position, Block = spec.Block}
        self.PendingCount += 1
        PlaceRemote:FireServer(position, spec.Block, (spec.Rot + turn) % 360, id, spec.Shape)
        return true
    end

    function job:Answer(id, result)
        local pending = self.Pending[id]
        if not pending then
            return
        end
        self.Pending[id] = nil
        self.PendingCount -= 1
        if result.success then
            self.Done += 1
            self.Streak = 0
            table.insert(self.Positions, pending.Position)
            table.insert(self.Names, pending.Block)
            return
        end
        local message = tostring(result.err or "The server rejected the block")
        local lower = string.lower(message)
        if string.find(lower, "already exists", 1, true) then
            self.Existing += 1
        elseif string.find(lower, "too quickly", 1, true) then
            self:Throttle(pending.Index)
        elseif string.find(lower, "too far", 1, true) then
            self.SettleUntil = math.max(self.SettleUntil, os.clock() + 0.25)
            self:Again(pending.Index, message)
        else
            self:Fail(message)
        end
    end

    return job
end

local function undoJob(entry)
    local positions, names = entry.Positions, entry.Names
    local count = #positions
    local job = Job.new("undo", count)
    job.Settle = 0.5
    job.StreamWait = 5
    job.MaxRate = App.Options.Rate > 10 and math.huge or 8

    function job:Locate(index)
        return positions[count - index], names[count - index]
    end

    function job:HoverPoint(position)
        return position + Vector3.new(0, 10, 0)
    end

    function job:Dispatch(index, position, name, _, _, _, now)
        local found, kind = World.BlockAt(position)
        if not found then
            if now - self.FlewAt < 1.2 then
                table.insert(self.Retry, index)
                self.SettleUntil = now + 0.3
                return "wait"
            end
            self.Existing += 1
            return false
        end
        if kind ~= name then
            self.Blocked += 1
            return false
        end
        local target = found
        if found:IsA("Model") then
            target = found.PrimaryPart
            for _, child in found:GetChildren() do
                if child:IsA("BasePart") and child ~= found.PrimaryPart then
                    target = child
                    break
                end
            end
        end
        if not target then
            self.Blocked += 1
            return false
        end
        local id = HttpService:GenerateGUID()
        self.Pending[id] = {Index = index, At = now}
        self.PendingCount += 1
        BreakRemote:FireServer(target, id)
        return true
    end

    function job:Answer(id, result)
        local pending = self.Pending[id]
        if not pending then
            return
        end
        self.Pending[id] = nil
        self.PendingCount -= 1
        if result.success then
            self.Done += 1
            self.Streak = 0
            return
        end
        local message = tostring(result.error or result.err or "The server rejected the removal")
        if string.find(string.lower(message), "too quickly", 1, true) then
            self:Throttle(pending.Index)
        else
            self:Again(pending.Index, message)
        end
    end

    return job
end

function App:Release(job, back)
    job.Hover = nil
    local origin = job.Origin
    if not origin or not back then
        return
    end
    job.Origin = nil
    local root = self:Root()
    if not root then
        return
    end
    local low, high = job.Low, job.High
    local at = origin.Position
    if low and at.X > low.X and at.X < high.X and at.Z > low.Z and at.Z < high.Z and at.Y > low.Y - 4 and at.Y < high.Y + 3 then
        origin = CFrame.new((low.X + high.X) / 2, high.Y + 5, (low.Z + high.Z) / 2) * origin.Rotation
    end
    root.CFrame = origin
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

function App:Summary(job)
    local parts = {}
    local verb = job.Kind == "build" and "placed" or "removed"
    table.insert(parts, App.Grouped(job.Done) .. " " .. verb)
    if job.Existing > 0 then
        table.insert(parts, App.Grouped(job.Existing) .. (job.Kind == "build" and " already there" or " already gone"))
    end
    if job.Blocked > 0 then
        table.insert(parts, App.Grouped(job.Blocked) .. (job.Kind == "build" and " blocked by other blocks" or " changed by someone"))
    end
    if job.Failed > 0 then
        table.insert(parts, App.Grouped(job.Failed) .. " failed")
    end
    local text = table.concat(parts, ", ")
    local worst, most = nil, 0
    for message, amount in job.Errors do
        if amount > most then
            worst, most = message, amount
        end
    end
    if worst then
        text ..= "\nServer: " .. worst
    end
    return text
end

function App:StatusLine()
    local job = self.Job
    if not job then
        return self.StatusText, self.LastFraction or 0
    end
    local resolved = job:Resolved()
    local fraction = job.Count > 0 and resolved / job.Count or 1
    local lines = {}
    local head = job.Kind == "build" and "Building" or "Removing"
    if job.Cancelled or job.Finished then
        head = "Finishing"
    elseif job.Paused then
        head = "Paused"
    end
    local left = job.Count - resolved
    local line = head .. ": " .. App.Grouped(resolved) .. " / " .. App.Grouped(job.Count)
    if not job.Paused and left > 0 then
        line ..= ", about " .. App.Duration(left / self:Rate()) .. " left"
    end
    table.insert(lines, line)
    if #job.Far > 0 and not self.Options.Teleport then
        table.insert(lines, App.Grouped(#job.Far) .. " blocks are out of reach. Walk closer or turn on Auto Teleport.")
    end
    table.insert(lines, self:Summary(job))
    return table.concat(lines, "\n"), fraction
end

function App:EndJob(job)
    local deadline = os.clock() + 2.5
    while job.PendingCount > 0 and os.clock() < deadline and self.Alive do
        task.wait()
    end
    self:Release(job, true)
    if job.Kind == "build" and #job.Positions > 0 then
        table.insert(self.History, {Positions = job.Positions, Names = job.Names})
        while #self.History > 5 do
            table.remove(self.History, 1)
        end
    elseif job.Kind == "undo" and job.Finished and not job.Cancelled then
        table.remove(self.History)
    end
    local title = job.Kind == "build" and "Build" or "Undo"
    local summary = self:Summary(job)
    if job.Cancelled then
        self.StatusText = title .. " stopped: " .. summary
    else
        self.StatusText = title .. " finished: " .. summary
    end
    self.LastFraction = job.Count > 0 and job:Resolved() / job.Count or 1
    if self.Job == job then
        self.Job = nil
    end
    if job.Refused then
        self:Notify(title .. " stopped", "The server keeps refusing: " .. job.Refused, "Error")
        return
    end
    self:Notify(title .. (job.Cancelled and " stopped" or " finished"), summary, (job.Failed > 0 or job.Blocked > 0) and "Warning" or "Success")
end

function App:RunJob(job)
    self.Job = job
    task.spawn(function()
        while self.Alive and self.Job == job and not job.Finished and not job.Cancelled do
            local ok, err = pcall(job.Pump, job, os.clock())
            if not ok then
                self:Warn("Job", err)
            end
            task.wait()
        end
        if self.Alive then
            self:EndJob(job)
        else
            self:Release(job, true)
        end
    end)
end

function App:StartBuild()
    local job = self.Job
    if job then
        if job.Cancelled or job.Finished then
            return
        end
        job.Paused = not job.Paused
        if job.Paused then
            self:Release(job, false)
        end
        return
    end
    local schematic = self.Schematic
    if not schematic then
        self:Notify("Build", "Pick a schematic first.", "Warning")
        return
    end
    if schematic.Total == 0 then
        self:Notify("Build", "Nothing in this schematic can be built in this game.", "Warning")
        return
    end
    if not self:Root() then
        self:Notify("Build", "Your character is not in the world yet.", "Warning")
        return
    end
    if self.Options.Preview then
        self.Options.Preview = false
        local toggle = self.Controls.Preview
        if toggle then
            pcall(function()
                toggle:Set(false, true)
            end)
        end
        self:SyncPreview()
    end
    if self.Preparing then
        return
    end
    self.Preparing = true
    local place = table.clone(self.Place)
    task.spawn(function()
        local ok, built = pcall(buildJob, schematic, place, self.Options.Hollow)
        self.Preparing = false
        if not ok then
            self:Warn("Build", built)
            self:Notify("Build", "The build could not be prepared.", "Error")
            return
        end
        local root = self:Root()
        if root then
            local at, low, high = root.Position, built.Low, built.High
            built.Inside = at.X > low.X - 3 and at.X < high.X + 3 and at.Z > low.Z - 3 and at.Z < high.Z + 3 and at.Y > low.Y - 4 and at.Y < high.Y + 4
        end
        if self.Alive and not self.Job then
            self:RunJob(built)
        end
    end)
end

function App:StopJob()
    local job = self.Job
    if job and not job.Cancelled and not job.Finished then
        job.Cancelled = true
        return true
    end
    return false
end

function App:Undo()
    if self.Job then
        self:Notify("Undo", "Stop the current job first.", "Warning")
        return
    end
    local entry = self.History[#self.History]
    if not entry then
        self:Notify("Undo", "Nothing was built with this menu yet.", "Info")
        return
    end
    local function run()
        if self.Alive and not self.Job then
            self:RunJob(undoJob(entry))
        end
    end
    local asked = pcall(function()
        self.Window:Confirm({
            Title = "Undo last build?",
            Content = App.Grouped(#entry.Positions) .. " blocks placed by the last build will be removed.",
            Icon = "undo-2",
            ConfirmText = "Remove",
            CancelText = "Keep",
            Callback = function()
                task.spawn(run)
            end,
        })
    end)
    if not asked then
        task.spawn(run)
    end
end

App:Connect(PlaceRemote.OnClientEvent, function(result)
    local job = App.Job
    if job and job.Kind == "build" and type(result) == "table" and result.id ~= nil then
        job:Answer(result.id, result)
    end
end)

App:Connect(BreakRemote.OnClientEvent, function(id, result)
    local job = App.Job
    if job and job.Kind == "undo" and type(result) == "table" then
        job:Answer(id, result)
    end
end)

App:Connect(RunService.Heartbeat, function()
    local job = App.Job
    local point = job and not job.Paused and job.Hover
    if point then
        local root = App:Root()
        if root then
            root.CFrame = CFrame.new(point) * root.CFrame.Rotation
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end
end)

function App:SetAntiAFK(enabled)
    self.Options.AntiAFK = enabled == true
    if self.Options.AntiAFK and not self.IdleConnection then
        self.IdleConnection = Player.Idled:Connect(function()
            if not (self.Alive and self.Options.AntiAFK) then
                return
            end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
            end)
            task.delay(0.2, function()
                pcall(function()
                    VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
                end)
            end)
        end)
    elseif not self.Options.AntiAFK and self.IdleConnection then
        self.IdleConnection:Disconnect()
        self.IdleConnection = nil
    end
end

function App:StopAll()
    self:StopJob()
end

function App:Unload()
    if not self.Alive then
        return
    end
    local job = self.Job
    if job then
        job.Cancelled = true
        self:Release(job, true)
    end
    self:SetAntiAFK(false)
    self.Alive = false
    self:DropPreview()
    for _, connection in ipairs(self.Connections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(self.Connections)
    if self.Window then
        pcall(self.Window.Destroy, self.Window)
    end
    if Environment[AppKey] == self then
        Environment[AppKey] = nil
    end
end

Airflow.Theme.Background = Color3.fromRGB(15, 17, 21)
Airflow.Theme.Surface = Color3.fromRGB(21, 24, 29)
Airflow.Theme.Surface2 = Color3.fromRGB(27, 31, 37)
Airflow.Theme.Surface3 = Color3.fromRGB(44, 50, 59)
Airflow.Theme.Stroke = Color3.fromRGB(38, 44, 52)
Airflow.Theme.StrokeHover = Color3.fromRGB(62, 120, 150)
Airflow.Theme.Accent = Color3.fromRGB(110, 205, 255)
Airflow.Theme.AccentDark = Color3.fromRGB(8, 28, 40)
Airflow.Theme.Text = Color3.fromRGB(232, 238, 244)
Airflow.Theme.Muted = Color3.fromRGB(140, 150, 162)

local Window = Airflow:CreateWindow({
    Name = "Schematics",
    Icon = "box",
    Size = UDim2.fromOffset(640, 470),
    MinSize = Vector2.new(280, 220),
    ToggleUIKeybind = Enum.KeyCode.RightControl,
    KeepOnScreen = true,
    MaxNotifications = 4,
    OpenButton = {Title = "Schematics", Icon = "box"},
    Loading = false,
    ConfigurationSaving = {Enabled = false},
})
App.Window = Window
if Window._titleLabel then
    Window._titleLabel.Position = UDim2.fromOffset(60, 31)
end

local SchematicTab = Window:CreateTab({Name = "Schematic", Icon = "box"})
local PositionTab = Window:CreateTab({Name = "Position", Icon = "move"})
local BuildTab = Window:CreateTab({Name = "Build", Icon = "hammer"})
local SettingsTab = Window:CreateTab({Name = "Settings", Icon = "settings"})

App.Files, App.FileLabels = App:ScanFiles()

local fileControl
fileControl = SchematicTab:CreateDropdown({
    Name = "Schematic",
    Options = App.FileLabels,
    Placeholder = "Pick a file",
    SearchAfter = 8,
    Callback = function(value)
        if value == nil then
            task.defer(function()
                if App.Alive and App.Selected then
                    fileControl:Set(App.Selected, true)
                end
            end)
            return
        end
        if value ~= App.Selected or not App.Schematic then
            App:Select(value)
        end
    end,
})
App.Controls.File = fileControl
SchematicTab:CreateButton({Name = "Refresh List", Icon = "refresh-cw", Callback = function()
    App:RefreshFiles(true)
end})
App.Controls.Info = SchematicTab:CreateParagraph({Title = "File", Content = App.InfoText})
App.Controls.Report = SchematicTab:CreateParagraph({Title = "Missing Blocks", Content = App.ReportText})

App.Controls.Preview = PositionTab:CreateToggle({
    Name = "Show Preview",
    CurrentValue = true,
    Callback = function(value)
        App.Options.Preview = value == true
        if App.Options.Preview and App.Schematic and not App.PreviewModel then
            App:RebuildPreview()
        else
            App:SyncPreview()
        end
    end,
})

local function axis(name, low, high)
    App.Controls[name] = PositionTab:CreateStepper({
        Name = name,
        Range = {low, high},
        Increment = 1,
        CurrentValue = 0,
        Callback = function(value)
            value = tonumber(value)
            if value then
                App.Place[name] = math.floor(value + 0.5)
                App:SyncPreview()
            end
        end,
    })
end
axis("X", -4000, 4000)
axis("Y", -64, 1000)
axis("Z", -4000, 4000)

App.Controls.Turn = PositionTab:CreateButton({Name = "Rotation: 0°", Icon = "rotate-cw", Callback = function()
    App:Rotate()
end})
PositionTab:CreateButton({Name = "Move To Player", Icon = "locate-fixed", Callback = function()
    if not App.Schematic then
        App:Notify("Position", "Pick a schematic first.", "Warning")
    elseif not App:MoveToPlayer() then
        App:Notify("Position", "Your character is not in the world yet.", "Warning")
    end
end})

App.Controls.Start = BuildTab:CreateButton({Name = "Start Build", Icon = "play", Style = "Primary", Callback = function()
    App:StartBuild()
end})
BuildTab:CreateButton({Name = "Stop", Icon = "square", Callback = function()
    if not App:StopJob() then
        App:Notify("Build", "Nothing is running.", "Info")
    end
end})
App.Controls.Progress = BuildTab:CreateProgress({Name = "Progress", CurrentValue = 0})
App.Controls.Status = BuildTab:CreateParagraph({Title = "Status", Content = App.StatusText})

BuildTab:CreateDivider()

App.Controls.Rate = BuildTab:CreateSlider({
    Name = "Blocks Per Second",
    Desc = "Public servers accept about 10",
    Range = {1, 50},
    Increment = 1,
    CurrentValue = 9,
    Callback = function(value)
        value = tonumber(value)
        if value then
            App.Options.Rate = value
            App.RateCap = nil
            if App.Schematic then
                App:Describe(App.Schematic)
            end
        end
    end,
})
App.Controls.Hollow = BuildTab:CreateToggle({
    Name = "Skip Hidden Blocks",
    Desc = "Faster. Blocks covered on every side are left out",
    CurrentValue = false,
    Callback = function(value)
        App.Options.Hollow = value == true
        if App.Schematic then
            App:Describe(App.Schematic)
        end
    end,
})
App.Controls.Teleport = BuildTab:CreateToggle({
    Name = "Auto Teleport",
    Desc = "Keeps you next to the blocks being placed",
    CurrentValue = true,
    Callback = function(value)
        App.Options.Teleport = value == true
        local job = App.Job
        if job and not App.Options.Teleport then
            App:Release(job, false)
        end
    end,
})

BuildTab:CreateDivider()

BuildTab:CreateButton({Name = "Undo Last Build", Icon = "undo-2", Callback = function()
    App:Undo()
end})

SettingsTab:CreateSection("Session")
App.Controls.AntiAFK = SettingsTab:CreateToggle({
    Name = "Anti AFK",
    CurrentValue = false,
    Callback = function(value)
        App:SetAntiAFK(value)
    end,
})
SettingsTab:CreateButton({Name = "Stop All", Icon = "square", Callback = function()
    App:StopAll()
    App:Notify("Stopped", "The build is stopped. Anti AFK stays as it is.", "Success")
end})
App.Controls.Keybind = SettingsTab:CreateKeybind({
    Name = "Menu Keybind",
    CurrentKeybind = Enum.KeyCode.RightControl,
    OnChanged = function(key)
        if typeof(key) == "EnumItem" then
            Window:SetKeybind(key)
        end
    end,
})
SettingsTab:CreateButton({Name = "Unload", Icon = "power", Callback = function()
    App:Unload()
end})
SettingsTab:CreateSection("Credits")
local creditText
local creditButton = SettingsTab:CreateButton({Name = "Credits - loading...", Icon = "copy", Callback = function()
    if creditText then
        App:Copy(creditText)
    else
        App:Notify("Credits", "The credits text is not available yet.", "Info")
    end
end})
SettingsTab:CreateButton({Name = "UI Library - airflowlib.lol", Icon = "copy", Callback = function()
    App:Copy("https://airflowlib.lol")
end})
task.spawn(function()
    local ok, text = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
    end)
    if not App.Alive then
        return
    end
    if ok and type(text) == "string" then
        text = text:match("^%s*(.-)%s*$")
        if text ~= "" and #text <= 200 and not text:find("[<>\r\n]") then
            creditText = text
            creditButton:SetText("Credits - " .. text)
            return
        end
    end
    creditButton:SetText("Credits - unavailable")
end)

local originalToggle = Window.Toggle
function Window:Toggle(value)
    if value == nil and UserInputService:GetFocusedTextBox() and UserInputService:GetLastInputType() == Enum.UserInputType.Keyboard then
        return
    end
    return originalToggle(self, value)
end

local Sidebar = Window.Body:FindFirstChild("Sidebar")
local TabLayout = Window.TabList:FindFirstChildOfClass("UIListLayout")
local TabPadding = Window.TabList:FindFirstChildOfClass("UIPadding")
local Remembered = {}
local function remember(object, properties)
    if not object then
        return
    end
    local values = Remembered[object] or {}
    for _, property in ipairs(properties) do
        values[property] = object[property]
    end
    Remembered[object] = values
end
remember(Sidebar, {"Size"})
remember(Window.Content, {"Position", "Size"})
remember(Window.TabList, {"Position", "Size", "AutomaticCanvasSize", "ScrollingDirection", "CanvasSize"})
remember(TabLayout, {"FillDirection"})
remember(TabPadding, {"PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom"})
if Sidebar then
    for _, child in ipairs(Sidebar:GetChildren()) do
        if child ~= Window.TabList and child ~= Window.Indicator and child:IsA("GuiObject") then
            remember(child, {"Visible"})
        end
    end
end
for _, child in ipairs(Window.Body:GetChildren()) do
    if child:IsA("Frame") and child.Size.X.Offset == 1 and child.Position.X.Offset == 170 then
        remember(child, {"Visible"})
    end
end
for _, tab in ipairs(Window.Tabs) do
    remember(tab._button, {"Size"})
    remember(tab._label, {"Position", "Size", "TextXAlignment"})
    if tab._icon then
        remember(tab._icon, {"Visible"})
    end
end

local originalIndicator = Window._placeIndicator
function Window:_placeIndicator(tab)
    if App.Compact then
        self.Indicator.Visible = false
        return
    end
    return originalIndicator(self, tab)
end

function App:Layout()
    if not self.Alive then
        return
    end
    local viewport = Window.Gui.AbsoluteSize
    if viewport.X < 1 or viewport.Y < 1 then
        return
    end
    for object, properties in pairs(Remembered) do
        for property, value in pairs(properties) do
            pcall(function()
                object[property] = value
            end)
        end
    end
    local width = math.clamp(viewport.X - 24, 280, 640)
    local height = math.clamp(viewport.Y - 24, 220, 470)
    Window.Root.Size = UDim2.fromOffset(width, height)
    self.Compact = width < 560
    if self.Compact and Sidebar and TabLayout then
        Sidebar.Size = UDim2.new(1, 0, 0, 52)
        for object, properties in pairs(Remembered) do
            if properties.Visible ~= nil and not object:IsDescendantOf(Window.TabList) then
                object.Visible = false
            end
        end
        Window.TabList.Position = UDim2.fromOffset(8, 5)
        Window.TabList.Size = UDim2.new(1, -16, 0, 42)
        Window.TabList.ScrollingDirection = Enum.ScrollingDirection.X
        Window.TabList.AutomaticCanvasSize = Enum.AutomaticSize.X
        Window.TabList.CanvasSize = UDim2.new()
        TabLayout.FillDirection = Enum.FillDirection.Horizontal
        if TabPadding then
            TabPadding.PaddingLeft = UDim.new(0, 0)
            TabPadding.PaddingRight = UDim.new(0, 0)
            TabPadding.PaddingTop = UDim.new(0, 0)
            TabPadding.PaddingBottom = UDim.new(0, 0)
        end
        Window.Content.Position = UDim2.fromOffset(0, 52)
        Window.Content.Size = UDim2.new(1, 0, 1, -52)
        for _, tab in ipairs(Window.Tabs) do
            tab._button.Size = UDim2.fromOffset(math.max(72, #tab.Name * 8 + 26), 40)
            tab._label.Position = UDim2.new()
            tab._label.Size = UDim2.fromScale(1, 1)
            tab._label.TextXAlignment = Enum.TextXAlignment.Center
            if tab._icon then
                tab._icon.Visible = false
            end
        end
        Window.Indicator.Visible = false
    end
    Window:_fitToScreen(true)
    Window:_clampToScreen()
    if Window.CurrentTab and not self.Compact then
        Window:_placeIndicator(Window.CurrentTab)
    end
end

App:Connect(Window.Gui:GetPropertyChangedSignal("AbsoluteSize"), function()
    local ok, err = pcall(App.Layout, App)
    if not ok then
        App:Warn("Layout", err)
    end
end)
App:Connect(Window.Gui.Destroying, function()
    App:Unload()
end)

App.Controls.AntiAFK:Set(true)

task.spawn(function()
    local shown = {}
    local function show(key, value, apply)
        if shown[key] ~= value then
            shown[key] = value
            pcall(apply, value)
        end
    end
    local scanAt = os.clock() + 4
    while App.Alive do
        local status, fraction = App:StatusLine()
        local job = App.Job
        local label = "Start Build"
        if job then
            label = (job.Cancelled or job.Finished) and "Finishing..." or job.Paused and "Resume" or "Pause"
        end
        show("Info", App.InfoText, function(value)
            App.Controls.Info:Set(value)
        end)
        show("Report", App.ReportText, function(value)
            App.Controls.Report:Set(value)
        end)
        show("Status", status, function(value)
            App.Controls.Status:Set(value)
        end)
        show("Start", label, function(value)
            App.Controls.Start:SetText(value)
        end)
        show("Progress", math.floor(fraction * 1000) / 1000, function(value)
            App.Controls.Progress:Set(value, true)
        end)
        if os.clock() >= scanAt then
            scanAt = os.clock() + 4
            pcall(App.RefreshFiles, App, false)
        end
        task.wait(0.25)
    end
end)

task.defer(function()
    if App.Alive then
        local ok, err = pcall(App.Layout, App)
        if not ok then
            App:Warn("Layout", err)
        end
    end
end)

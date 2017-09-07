-- 00d40f681a707d55d0d7b9af25bc761b.fxo

assert("Lua 5.3" == _VERSION)
assert(arg[1], "\n\n[ERROR] no input file\n\n")
local DEBUG = arg[2] or ""

require("mod_binary_reader")
local r = BinaryReader


local function get_blockheader()
    local b = {}
    local flags = r:uint32()
    b.count = r:uint32()
    b.size_z = r:uint64()
    b.size = r:uint64()
    b.next = r:uint64()

    b.compressed = (flags & 1 > 0) and true or false
    b.encrypted  = (flags & 2 > 0) and true or false
    b.havedata   = (flags & 4 > 0) and true or false
    b.deleted    = (flags & 8 > 0) and true or false

    local t = {}
    t[1] = (b.compressed) and "C" or "-"
    t[2] = (b.encrypted) and "E" or "-"
    t[3] = (b.havedata) and "D" or "-"
    t[4] = (b.deleted) and "X" or "-"
    b.parsedflags = table.concat(t)

    return b
end


local function decode(offset, size_z, size)
    local key = 0x71c71c71
    local t = {}
    r:seek(offset)

    for x = 2, size_z, 2 do
        key = key * 0x00343fd
        key = key + 0x00269ec3
        local tmp_key = (key >> 16) & 0x7fff
        local tmp_str = r:uint16() ~ tmp_key
        table.insert(t, string.pack("H", tmp_str))
    end
    return table.concat(t)
end


local function get_fileheader(M, pos)
    local t = {}
    for i = pos, pos+519, 2 do
        local char = string.sub(M, i, i)
        if char == "\0" then break end
        table.insert(t, char)
    end
    pos = pos + 520

    local f = {}
    f.name = table.concat(t)
    f.offset, pos = string.unpack("I8", M, pos)
    f.size_z, pos = string.unpack("I8", M, pos)
    f.size, pos = string.unpack("I8", M, pos)
    f.filetime, pos = string.unpack("I", M, pos)
    f.unknown = string.unpack("c12", M, pos)

    return f
end


--[[ main ]]--

r:open(arg[1])
r:idstring("Resource File V2.2")
r:seek(0x310)

local rda_size = r:size()
local jmp = r:uint64()

while jmp < rda_size do
    r:seek(jmp)

    local block = get_blockheader()
    local offset = jmp - block.size_z
    jmp = block.next

print(offset, block.parsedflags, block.count, block.size_z, block.size)

    if block.size == 0 then goto nextblock end

    if block.havedata then
        offset = offset - 16
    end

    local M1
    if block.encrypted then
        M1 = decode(offset, block.size_z, block.size)
    else
        r:seek(offset)
        M1 = r:str(block.size_z)
    end
    if block.compressed then
--        M1 = unlz(M1, size_z, size)
    end


    -- TODO: нефиг копировать если не шифровано/упаковано
    local M2
    if block.havedata then
        r:seek(offset + block.size_z)
        local size_z = r:uint64()
        local size = r:uint64()
        offset = offset - size_z

        if block.encrypted then
            M2 = decode(offset, size_z, size)
        else
            r:seek(offset)
            M2 = r:str(size_z)
        end
        if block.compressed then
--            M2 = unlz(M2, size_z, size)
        end
    end

    for i = 1, block.count do
        local file = get_fileheader(M1, (i-1)*560+1)

        print(("%4d | %10d | %9d | %9d | %s | %s"):format(
                i, file.offset, file.size_z, file.size,
                os.date("%Y-%m-%d %H:%M:%S", file.filetime), file.name))

        if file.size == 0 then goto nextfile end

        if block.havedata then
            -- copy M2 -> file
        else
            if block.encrypted then
--                decode(file.offset, file.size_z, file.size)
            else
--                r:seek(file.offset)
            end
            if block.compressed then
                -- unlz M2 -> file
            end
        end
        ::nextfile::
    end

    ::nextblock::
end

r:close()

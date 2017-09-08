assert("Lua 5.3" == _VERSION)
assert(arg[1], "\n\n[ERROR] no input file\n\n")
local DEBUG = arg[2] or nil

require("mod_binary_reader")
local r = BinaryReader

local zlib = require("zlib")


local VER22 = false


local function get_blockheader(offset)
    local b = {}
    local flags = r:uint32()
    b.count  = r:uint32()
    b.size_z = VER22 and r:uint64() or r:uint32()
    b.size   = VER22 and r:uint64() or r:uint32()
    b.next   = VER22 and r:uint64() or r:uint32()
    
    b.offset = offset - b.size_z
    b.compressed = (flags & 1 > 0) and true or false
    b.encrypted  = (flags & 2 > 0) and true or false
    b.havedata   = (flags & 4 > 0) and true or false
    b.deleted    = (flags & 8 > 0) and true or false
    
    if b.havedata then
        b.offset = b.offset - (VER22 and 16 or 8)
    end

    local t = {}
    t[1] = (b.compressed) and "C" or "-"
    t[2] = (b.encrypted) and "E" or "-"
    t[3] = (b.havedata) and "D" or "-"
    t[4] = (b.deleted) and "X" or "-"
    b.parsedflags = table.concat(t)

    return b
end


local function unlz(offset, size_z, size)
    local stream = zlib.inflate()
    
    r:seek(offset)
    local data = r:str(size_z)
    local eof, b_in, b_out
    data, eof, b_in, b_out = stream(data)
    
    assert(true == eof)
    assert(size_z == b_in)
    assert(size == b_out)

    return data
end


local function decode(offset, size_z)
    local key = VER22 and 0x71c71c71 or 0x000A2C2A
    local t = {}
    
    r:seek(offset)
    for _ = 2, size_z, 2 do
        key = key * 0x00343fd
        key = key + 0x00269ec3
        local tmp_key = (key >> 16) & 0x7fff
        local tmp_str = r:uint16() ~ tmp_key
        table.insert(t, string.pack("H", tmp_str))
    end
    
    return table.concat(t)
end


local function get_fileheader(data, pos)
    pos = (pos - 1) * (VER22 and 560 or 540) + 1

    local t = {}
    for i = pos, pos+519, 2 do
        local char = string.sub(data, i, i)
        if char == "\0" then break end
        table.insert(t, char)
    end
    pos = pos + 520

    local f = {}
    f.name = table.concat(t)
    
    local SZ = VER22 and "I8" or "I"
    f.offset, pos = string.unpack(SZ, data, pos)
    f.size_z, pos = string.unpack(SZ, data, pos)
    f.size, pos = string.unpack(SZ, data, pos)
    f.filetime, pos = string.unpack(SZ, data, pos)
    f.unknown = string.unpack(SZ, data, pos)
--    assert("\0\0\0\0\0\0\0\0\0\0\0\0" == f.unknown)

    return f
end


--[[ main ]]--

r:open(arg[1])

if "Reso" == r:str(4) then
    VER22 = true
end

local jmp
if VER22 then
    r:seek(0x310)
    jmp = r:uint64()
else
    jmp = 0x0404
end
local rda_size = r:size()

while r:seek(jmp) < rda_size do
    local block = get_blockheader(jmp)
    
    if not DEBUG then
        print(jmp, block.parsedflags, block.count, block.size_z, block.size, block.next)
    end
    jmp = block.next

    if block.size == 0 or not DEBUG then goto nextblock end

    local fileheader, filedata

    if block.compressed then
        fileheader = unlz(block.offset, block.size_z, block.size)

    elseif block.encrypted then
        fileheader = decode(block.offset, block.size_z)

    elseif block.havedata then
        r:seek(block.offset)
        fileheader = r:str(block.size_z)

        local size_z = r:uint64()
        local size = r:uint64()
        r:seek(block.offset - size_z)
        filedata = r:str(size_z)

    else    -- and if (block.deleted)
        r:seek(block.offset)
        fileheader = r:str(block.size_z)
    end

    for i = 1, block.count do
        local file = get_fileheader(fileheader, i)

        if DEBUG then
            print(("%s,%s,%d,%d,%d,%s,%s"):format(
                    DEBUG, block.parsedflags, file.offset, file.size_z, file.size,
                    os.date("%Y-%m-%d %H:%M:%S", file.filetime), file.name))
        end

        if file.size == 0 then goto nextfile end

        if block.compressed then
            -- unlz from filedata -> file
        elseif block.encrypted then
            -- decode(file.offset, file.size_z)
        elseif block.havedata then
            -- copy from filedata -> file
        elseif block.deleted then
            -- delete file
        else
            -- copy from input -> file
        end

        ::nextfile::
    end
    ::nextblock::
end

r:close()

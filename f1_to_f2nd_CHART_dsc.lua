-- Written by:  Brolijah
-- Contact info:
--     Discord: Brolijah#8502
--     Email  : brolijahrh@gmail.com

-- THIS LUA SCRIPT REQUIRES LUVIT TO RUN

-- If you find yourself needing more, refer to the Luvit API at https://luvit.io/api/
-- However, be warned as that API is outdated. The most important "imported" class
-- you'll be using is the Buffer class, but the API doesn't have all the functions
-- the current version supports. It's like a fraction of it, really. So, if you need
-- help with the Buffer class, you'll want to skim through here:
--   https://github.com/luvit/luvit/blob/master/deps/buffer.lua

-- Required stuff. Don't touch. Add more if needed, but you shouldn't.
Buffer = require('buffer').Buffer
FileSystem = require('fs')
Path = require('path')

function Buffer:writeString(offset, str)
    for i=0, #str-1 do
        if (offset+i) <= self.length then
            self[offset+i] = str:byte(i+1)
        end
    end
end

function Buffer:memset(value, size, valType, offset)
    size = (size and size < self.length) or self.length
    offset = offset or 1

    -- MEMSET A STRING OR CHAR
    if type(value) == "string" then
        for i = offset, size, value:len() do
            self:writeString(i, value)
        end

    -- MEMSET A NUMBER
    elseif type(value) == "number" then
        assert(type(valType) == "string",
            "memset'ing a number requires that you specify the type of number")

        local func = ''
        local jump = nil
        valType = valType:lower()
        -- Shortcut cuz this will be easier
        if (valType == 'int8') or (valType == 'uint8') then
            func = 'UInt8'
            jump = 1
        else
            local sstr = ''
            -- GET SIGNED OR UNSIGNED
            if     (valType:sub(1,4) == 'uint') then func = 'UInt'
            elseif (valType:sub(1,3) == 'int')  then func = 'Int'
            end

            -- GET BIT WIDTH
            sstr = valType:sub(func:len()+1, func:len()+2)
            if     (sstr == '16') then func = func .. '16'; jump = 2
            elseif (sstr == '32') then func = func .. '32'; jump = 4
            end

            -- GET ENDIAN
            sstr = valType:sub(func:len()+1, func:len()+2)
            if     (sstr == 'le') then func = func .. 'LE'
            elseif (sstr == 'be') then func = func .. 'BE'
            end
        end

        func = self['write' .. func]
        if (func and type(func) == 'function') then
            for i = offset, size, jump do
                func(self, i, value)
            end
        else error("Cannot memset number value as the following type: " .. valType)
        end

    else
        error("Input value must be a string or number.")
    end
end


DIVA_VERSION = 0x18000000
ENDIAN_FLAG  = 319947808
F2_DSC = {
    HEADER = {
        magic     = 0x0000, -- Value should be "PVSC"
        size1     = 0x0004, -- Will be set when we're done.
        fileStart = 0x0008, -- Value should be 64
        divaVer   = 0x000C, -- Value should be 0x18000000
        size2     = 0x0014, -- Will be set when we're done.
        unkValue  = 0x0020, -- No fucking clue. Let's leave it at 0 and see what happens.
        endFlip   = 0x0030, -- Value should be Endian Flag
    },
}

TARGET_TYPES = {
    [0x0000] = "TRIANGLE",        -- 0
    [0x0001] = "CIRCLE",          -- 1
    [0x0002] = "CROSS",           -- 2
    [0x0003] = "SQUARE",          -- 3
    [0x0004] = "TRIANGLE_UP",     -- 4
    [0x0005] = "CIRCLE_RIGHT",    -- 5
    [0x0006] = "CROSS_DOWN",      -- 6
    [0x0007] = "SQUARE_LEFT",     -- 7
    [0x0008] = "TRIANGLE_HOLD",   -- 8
    [0x0009] = "CIRCLE_HOLD",     -- 9
    [0x000A] = "CROSS_HOLD",      -- 10
    [0x000B] = "SQUARE_HOLD",     -- 11
    [0x000C] = "STAR",            -- 12
    [0x000E] = "DOUBLE_STAR",     -- 14
    [0x000F] = "CHANCE_STAR",     -- 15
    [0x0016] = "LINKED_STAR",     -- 22
    [0x0017] = "LINKED_STAR_END", -- 23
    -- I hope none of the below appear...
    [0x0012] = "TRIANGLE_UP_STAR",  -- 18
    [0x0013] = "CIRCLE_RIGHT_STAR", -- 19
    [0x0014] = "CROSS_DOWN_STAR",   -- 20
    [0x0015] = "SQUARE_LEFT_STAR",  -- 21
}

--[[ Quick rundown of what I am including:
    Let's try to make this as painless as possible. And what I mean by that is we'll try to
    make it automated. In the final version of this script, we shall loop through all files
    in a folder (containing F 1 DSCs) and open them all then export to an out folder. For
    debugging purposes, we'll only let it do a few at a time. So I'll throw in an option that
    you can turn off or on.
--]]

-- This is that debug option I promised. Set to false when you're ready
-- to run it on every file in the folder.
DEBUG = false

-- List of variables we will need for this script.
CURRENT_DIR = Path.resolve("")
SOURCE_DIR  = CURRENT_DIR .. '\\f1_dscs_in\\'
OUTPUT_DIR  = CURRENT_DIR .. '\\f2nd_chart_dscs_out\\'
local input = FileSystem.readdirSync(SOURCE_DIR)

print("\nThis script is for converting Project DIVA F PVDSC (.DSC) to be ")
print("compatible with Project DIVA F 2nd. As of this time, the script ")
print("only outputs to F 2nd Note Charts.")

--[[Function Name: ConvertF1_to_F2
    Parameters: input file's full path
    Returns: True if successful
        (though the script will crash if it fails at any point, anyway)
    Description:
        Elijah: This is where most the magic happens. Its only argument is the
            input file's path. It then opens and reads the file as a buffer and
            creates a second buffer for the output file.
--]]
ConvertF1_to_F2 = function(filepath)
    -- Error handling.
    assert(filepath, "Function ConvertF1_to_F2 requires an argument!!")
    assert(FileSystem.existsSync(filepath), "File doesn't exist!!")

    local name = Path.basename(filepath)
    local in_buffer  = Buffer:new(FileSystem.readFileSync(filepath))
    local out_buffer = Buffer:new(64)
    local out_file   = Buffer:new(8)
    local dwordBuff  = Buffer:new(4)  -- Used when writing values.
    dwordBuff:writeUInt32LE(1, 0)

    local hStruct = F2_DSC.HEADER
    -- Create a F 2nd DSC header
    out_buffer:memset(0, nil, 'uint8') -- Make everything a zero
    out_buffer:writeString(1 + hStruct.magic, 'PVSC')
    out_buffer:writeUInt32LE(1 + hStruct.fileStart, 64)
    out_buffer:writeUInt32LE(1 + hStruct.divaVer, DIVA_VERSION)
    out_buffer:writeUInt32LE(1 + hStruct.unkValue, 34343434)   -- I'm sure something will fuck up eventually.
    out_buffer:writeUInt32LE(1 + hStruct.endFlip, ENDIAN_FLAG)

    -- Write the PVSC subfile Endian flag.
    out_file:writeUInt32BE(1, ENDIAN_FLAG)
    out_file:writeUInt32BE(1 + 4, 0)
    out_file = out_file:toString()

    local inByteLength = in_buffer.length
    local last_timestamp = 0
    local entries = 0
    local valueAtPos = 0

    for pos=(1+(4*2)), (inByteLength-(12*4)), 4 do
      -- PART 1: FIND A TARGET OPCODE
        valueAtPos = in_buffer:readUInt32LE(pos)

        if valueAtPos == 6 then
      -- PART 2: VERIFY WE'VE FOUND THE NEXT TARGET
            local found = false
            local possibleTimeStamp = in_buffer:readUInt32LE(pos-4)
            local possibleStartID   = in_buffer:readUInt32LE(pos-8)
            
            -- Yeah, uhh, WHAT THE FUCK?
            if (possibleStartID == 1) and (possibleTimeStamp > last_timestamp) then
                found = true
            else
                possibleTimeStamp = in_buffer:readUInt32LE(pos-12)
                possibleStartID   = in_buffer:readUInt32LE(pos-16)
                if (possibleStartID == 1) and (possibleTimeStamp > last_timestamp) then
                    found = true
                end
            end

            if found then
      -- PART 3: READ THE VALUES
                local start_id    = possibleStartID                 -- START_ID
                local timestamp   = possibleTimeStamp               -- TIMESTAMP
                local opcode      = valueAtPos                      -- OPCODE
                local target      = in_buffer:readUInt32LE(pos+4)   -- TARGET
                local hold_time   = in_buffer:readInt32LE(pos+8)    -- HOLD_TIME
                local is_hold_end = in_buffer:readInt32LE(pos+12)   -- IS_HOLD_END
                local x_pos       = in_buffer:readUInt32LE(pos+16)  -- X_POS
                local y_pos       = in_buffer:readUInt32LE(pos+20)  -- Y_POS
                local curve1      = in_buffer:readInt32LE(pos+24)   -- CURVE1
                local unkVal_2S   = in_buffer:readInt32LE(pos+28)   -- UNKVAL_2S
                local curve2      = in_buffer:readInt32LE(pos+32)   -- CURVE2
                local unkVal_500  = in_buffer:readUInt32LE(pos+36)  -- UNKVAL_500
                local timer       = in_buffer:readUInt32LE(pos+40)  -- TIMER
                local unkVal_3U   = in_buffer:readUInt32LE(pos+44)  -- UNKVAL_3U

                last_timestamp = possibleTimeStamp
                pos = pos + 44  -- We start looking here on the next iteration.
                entries = entries + 1  -- Increment the number of targets we've located

                -- Here for debugging
                if DEBUG and (entries==1 or entries==100 or entries==200) then
                    print("  >>  Timestamp: " .. timestamp)   -- In a unit of measure with no name. 1x(10^-5)
                    print("  >>  Note ID: " .. target)
                    print("  >>  Note Type: " .. TARGET_TYPES[target])
                    print("  >>  Hold Time: " .. hold_time)
                    print("  >>  Hold End?: " .. is_hold_end)
                    print("  >>  X-Position: " .. x_pos)
                    print("  >>  Y-Position: " .. y_pos)
                    print("  >>  Angle #1?: " .. curve1)
                    print("  >>  Angle #2?: " .. curve2)
                    print("  >>  Note timer: " .. timer) -- In miliseconds
                    print("")
                end

      -- PART 4: WRITE WHAT YOU NEED TO THIS ELEMENTS BUFFER
                dwordBuff:writeUInt32BE(1, start_id)
                out_file = out_file .. dwordBuff
                dwordBuff:writeUInt32BE(1, timestamp)
                out_file = out_file .. dwordBuff
                dwordBuff:writeUInt32BE(1, opcode)
                out_file = out_file .. dwordBuff
                dwordBuff:writeUInt32BE(1, target)
                out_file = out_file .. dwordBuff
                dwordBuff:writeInt32BE(1, hold_time)
                out_file = out_file .. dwordBuff
                dwordBuff:writeInt32BE(1, is_hold_end)
                out_file = out_file .. dwordBuff
                dwordBuff:writeUInt32BE(1, x_pos)
                out_file = out_file .. dwordBuff
                dwordBuff:writeUInt32BE(1, y_pos)
                out_file = out_file .. dwordBuff
                dwordBuff:writeInt32BE(1, curve1)
                out_file = out_file .. dwordBuff
                dwordBuff:writeInt32BE(1, unkVal_2S)
                out_file = out_file .. dwordBuff
                dwordBuff:writeInt32BE(1, curve2)
                out_file = out_file .. dwordBuff
                dwordBuff:writeUInt32BE(1, unkVal_500)
                out_file = out_file .. dwordBuff
                dwordBuff:writeUInt32BE(1, timer)
                out_file = out_file .. dwordBuff
                dwordBuff:writeUInt32BE(1, unkVal_3U)
                out_file = out_file .. dwordBuff
                dwordBuff:writeInt32BE(1, -1)
                out_file = out_file .. dwordBuff

            end -- if possibleStartID and possibleTimeStamp
        end -- if valueAtPos == 6
    end -- for loop


    -- Append 0s onto the end of the file. (I've yet to verify the purpose of this.)
    dwordBuff:writeUInt32BE(1, 0)
    out_file = out_file .. dwordBuff .. dwordBuff .. dwordBuff

    -- Get new out_file size and concatenate
    out_buffer:writeUInt32LE(1 + hStruct.size1, out_file:len())
    out_buffer:writeUInt32LE(1 + hStruct.size2, out_file:len())
    out_buffer = Buffer:new(out_buffer .. out_file)

    -- Append the footer to the file (I'll admit, I'm cheating a bit here)
    out_file = Buffer:new(32)  -- lol, hey, we released some memory at least
    out_file:memset(0, nil, 'uint8')
    out_file:writeString(1, 'EOFC')
    out_file:writeUInt8(1 + 8, 32)
    out_file:writeUInt8(1 + 15, 16)
    out_buffer = out_buffer .. out_file

    print("  >> Number of targets converted for F 2nd: " .. entries .. '\n')
    FileSystem.writeFileSync(OUTPUT_DIR .. name, out_buffer)
end

if DEBUG then
    print("\nDebugging is enabled! Testing with ONLY the first 3 input files!")
    for i=1, 3 do
        print("  File #" .. i .. ": " .. input[i])
        ConvertF1_to_F2(SOURCE_DIR .. input[i])
    end
else
    print("\nTotal number of input files to convert: " .. #input)
    print("Starting loop...")

    --local prog, prev = 0, 0
    for i=1, #input do
        print("  File #" .. i .. ": " .. input[i])
        ConvertF1_to_F2(SOURCE_DIR .. input[i])
        
        --[[
        prog = math.floor(1000000 * (i / #input)/10000)
        if (prog ~= prev) and ((prog % 5) == 0) then
            print("Progress: " .. tostring(prog) .. "%")
            prev = prog
        end]]
    end
end

print("\nFinished the conversion. Check the 'f2nd_chart_dscs_out' folder for results.")
print("Process complete! Exiting script!\n")


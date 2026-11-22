-- lib/audio.lua : WAV / Ogg parsing, WAV parts, Ogg cutting for resume
local _util = require("lib.util")
local clamp, le32s, u32 = _util.clamp, _util.le32s, _util.u32

-- WAV: parse from memory. Gives everything needed to resume from the middle (pause).
local function parseWav(raw, fileSize)
    if #raw < 12 or raw:sub(1, 4) ~= "RIFF" or raw:sub(9, 12) ~= "WAVE" then return nil end
    local pos, fmtBody, dataOff, dataLen = 13, nil, nil, nil
    while pos + 7 <= #raw do
        local id, len = raw:sub(pos, pos + 3), u32(raw, pos + 4)
        if id == "fmt " then
            fmtBody = raw:sub(pos + 8, pos + 7 + len)
        elseif id == "data" then
            dataOff, dataLen = pos + 8, len
            if dataLen == 0 or dataOff + dataLen - 1 > fileSize then
                dataLen = fileSize - dataOff + 1
            end
            break
        end
        pos = pos + 8 + len + (len % 2)
    end
    if not (fmtBody and dataOff and #fmtBody >= 16) then return nil end
    local byteRate = u32(fmtBody, 9)
    local blockAlign = fmtBody:byte(13) + fmtBody:byte(14) * 256
    if not byteRate or byteRate <= 0 or blockAlign <= 0 then return nil end
    return { fmt = fmtBody, byteRate = byteRate, blockAlign = blockAlign,
             dataOff = dataOff, dataLen = dataLen,
             tag = fmtBody:byte(1) + fmtBody:byte(2) * 256,
             channels = fmtBody:byte(3) + fmtBody:byte(4) * 256,
             rate = u32(fmtBody, 5),
             bits = fmtBody:byte(15) + fmtBody:byte(16) * 256 }
end

local function makeWav(w, body)
    local flen = #w.fmt
    local fmtBody = w.fmt
    if flen % 2 == 1 then fmtBody = fmtBody .. "\0" end
    return "RIFF" .. le32s(4 + 8 + #fmtBody + 8 + #body) .. "WAVE"
        .. "fmt " .. le32s(flen) .. fmtBody
        .. "data" .. le32s(#body) .. body
end

local function readBytes(f, n)
    local parts, got = {}, 0
    while got < n do
        local piece = f.read(n - got)
        if not piece or #piece == 0 then break end
        parts[#parts + 1] = piece
        got = got + #piece
    end
    return table.concat(parts)
end

-- One sendable WAV piece: audio from startByte up to the end of its chunk (or the track).
-- returns data, startByte, lastByte (exclusive)  |  nil if the file can't be read
local function wavSeg(path, w, startByte)
    startByte = clamp(startByte, 0, math.max(0, w.dataLen - w.blockAlign))
    startByte = startByte - startByte % w.blockAlign
    local k = math.floor(startByte / w.chunk)
    local lastByte = math.min(w.dataLen, (k + 1) * w.chunk)
    local f = fs.open(path, "rb")
    if not f then return nil end
    f.seek("set", w.dataOff - 1 + startByte)
    local body = readBytes(f, lastByte - startByte)
    f.close()
    if #body == 0 then return nil end
    return makeWav(w, body), startByte, lastByte
end

-- Ogg Vorbis: split the file into pages (Opus returns nil).
-- Gives the track length and lets us cut the file at a page boundary to resume mid-track.
local function parseOgg(raw)
    local head = raw:sub(1, 200)
    local vp = head:find("vorbis", 1, true)
    local rate = vp and u32(head, vp + 11)
    if not rate or rate <= 0 then return nil end

    local pages, pos, n, first = {}, 1, #raw, nil
    while pos + 26 <= n and raw:sub(pos, pos + 3) == "OggS" do
        local nseg = raw:byte(pos + 26)
        local size = 27 + nseg
        for i = 1, nseg do size = size + (raw:byte(pos + 26 + i) or 0) end
        local glo, ghi = u32(raw, pos + 6), u32(raw, pos + 10)
        local gran = (glo == 4294967295 and ghi == 4294967295) and -1
            or (glo + ghi * 4294967296)
        pages[#pages + 1] = { pos = pos, gran = gran, cont = raw:byte(pos + 5) % 2 == 1 }
        if not first and gran > 0 then first = #pages end
        pos = pos + size
    end
    if not first then return nil end

    local lastGran = 0
    for i = #pages, first, -1 do
        if pages[i].gran >= 0 then lastGran = pages[i].gran break end
    end
    return { pages = pages, first = first, rate = rate, dur = lastGran / rate,
             headerEnd = pages[first].pos - 1 }
end

-- headers + audio pages starting near `sec`. returns data, exact start time (or nil)
local function oggFrom(raw, o, sec)
    local target = sec * o.rate
    local idx
    for i = o.first, #o.pages do
        if o.pages[i].gran >= target then idx = i break end
    end
    if not idx then return nil end
    while idx <= #o.pages and o.pages[idx].cont do idx = idx + 1 end -- start on a fresh packet
    if idx > #o.pages then return nil end
    local startSec = 0
    for j = idx - 1, o.first, -1 do
        if o.pages[j].gran >= 0 then startSec = o.pages[j].gran / o.rate break end
    end
    return raw:sub(1, o.headerEnd) .. raw:sub(o.pages[idx].pos), startSec
end

return {
    oggFrom = oggFrom,
    parseOgg = parseOgg,
    parseWav = parseWav,
    wavSeg = wavSeg,
}

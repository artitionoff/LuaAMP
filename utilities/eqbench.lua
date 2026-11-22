-- eqbench.lua : how fast can this computer run a 3-band equalizer on 16-bit stereo audio?
-- usage: eqbench      (takes about 10-20 seconds, nothing is played or saved)

local FRAMES_PER_BLOCK = 512          -- stereo frames processed per step
local BLOCKS = 600                    -- 600 * 512 frames = 307200 frames (~7 s of 44.1 kHz audio)
local BYTES_PER_SEC = 44100 * 4       -- 44.1 kHz stereo 16 bit

-- test data: 2 KB of noise-like bytes, reused for every block
local seed = {}
for i = 1, FRAMES_PER_BLOCK * 4 do seed[i] = (i * 37 + (i % 7) * 91) % 256 end

-- 3 bands: bass < ~150 Hz < mid < ~2 kHz < treble, gains are plain multipliers
local a1, a2 = 0.021, 0.25
local gLow, gMid, gHigh = 1.5, 1.0, 1.3

local l1, l2, r1, r2 = 0, 0, 0, 0
local function block(t)
    for i = 1, FRAMES_PER_BLOCK * 4, 4 do
        local l = t[i] + t[i + 1] * 256
        if l >= 32768 then l = l - 65536 end
        local r = t[i + 2] + t[i + 3] * 256
        if r >= 32768 then r = r - 65536 end

        l1 = l1 + a1 * (l - l1)
        l2 = l2 + a2 * (l - l2)
        r1 = r1 + a1 * (r - r1)
        r2 = r2 + a2 * (r - r2)
        local ly = gLow * l1 + gMid * (l2 - l1) + gHigh * (l - l2)
        local ry = gLow * r1 + gMid * (r2 - r1) + gHigh * (r - r2)

        if ly > 32767 then ly = 32767 elseif ly < -32768 then ly = -32768 end
        if ry > 32767 then ry = 32767 elseif ry < -32768 then ry = -32768 end
        ly = math.floor(ly) % 65536
        ry = math.floor(ry) % 65536
        t[i], t[i + 1] = ly % 256, math.floor(ly / 256)
        t[i + 2], t[i + 3] = ry % 256, math.floor(ry / 256)
    end
end

print("running...")
local start = os.epoch("utc")
local lastYield = start
for _ = 1, BLOCKS do
    local t = {}
    for i = 1, #seed do t[i] = seed[i] end   -- fresh copy, like decoding a block of audio
    block(t)
    local s = string.char(unpack(t))         -- and encoding it back
    local now = os.epoch("utc")
    if now - lastYield > 500 then            -- let the computer breathe (no 'too long without yielding')
        os.queueEvent("eqbench")
        os.pullEvent("eqbench")
        lastYield = os.epoch("utc")
    end
end
local secs = (os.epoch("utc") - start) / 1000

local bytes = BLOCKS * FRAMES_PER_BLOCK * 4
local rate = bytes / secs
print(("processed %.1f MB in %.1f s"):format(bytes / 1048576, secs))
print(("speed: %.0f KB/s  =  %.1fx real time"):format(rate / 1024, rate / BYTES_PER_SEC))
print()
if rate / BYTES_PER_SEC >= 3 then
    print("great: the equalizer is comfortable")
elseif rate / BYTES_PER_SEC >= 1.3 then
    print("ok: works, parts must be processed ahead of time")
else
    print("too slow for a live equalizer on this computer")
end

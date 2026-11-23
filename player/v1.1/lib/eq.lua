-- lib/eq.lua : 5-band sound equalizer for PCM WAV (16 bit, mono or stereo)
-- The speaker cannot filter sound, so the audio data itself is changed before it is sent:
-- the first 2 seconds at once, then the following parts in small steps between events.
-- Bands are split with one-pole low-pass filters at the crossover frequencies below.
local _config = require("lib.config")
local CROSS = _config.EQ_CROSS or { 120, 500, 2000, 8000 } -- Hz between the 5 bands
local FIRST_SEC = _config.EQ_FIRST_SEC or 2   -- first part after a start / change: quick to prepare
local CHUNK_SEC = _config.EQ_CHUNK_SEC or 8   -- following parts
local _state = require("lib.state")
local EQ = _state.EQ
local _audio = require("lib.audio")
local wavBody, makeWav = _audio.wavBody, _audio.makeWav

local NAMES = { "60", "250", "1k", "4k", "12k" } -- label of each band (approximate centers, Hz)
local MAXDB = 12
local EQ_PRESETS = {
    { name = "Flat",   gains = { 0, 0, 0, 0, 0 } },
    { name = "Bass",   gains = { 8, 5, 0, -1, -2 } },
    { name = "Treble", gains = { -2, -1, 0, 5, 8 } },
    { name = "Vocal",  gains = { -3, -1, 4, 4, 0 } },
    { name = "Rock",   gains = { 6, 2, -3, 3, 6 } },
}

------------------------------------------------------------ settings
local EQ_FILE = fs.combine(_config.LIST_DIR, "eq.cfg")

local function saveEq()
    local f = fs.open(EQ_FILE, "w")
    if not f then return end
    pcall(f.write, textutils.serialize({ on = EQ.on, gains = EQ.gains, preset = EQ.preset }))
    pcall(f.close)
end

local function loadEq()
    if not fs.exists(EQ_FILE) then return end
    local f = fs.open(EQ_FILE, "r")
    if not f then return end
    local t = textutils.unserialize(f.readAll())
    f.close()
    if type(t) ~= "table" then return end
    EQ.on = (t.on == true)
    if type(t.gains) == "table" then
        for i = 1, 5 do
            if type(t.gains[i]) == "number" then
                EQ.gains[i] = math.max(-MAXDB, math.min(MAXDB, t.gains[i]))
            end
        end
    end
    if type(t.preset) == "number" then EQ.preset = t.preset end
end
loadEq()

local function matchPreset()
    EQ.preset = 0 -- 0 = custom
    for p, pr in ipairs(EQ_PRESETS) do
        local same = true
        for i = 1, 5 do
            if pr.gains[i] ~= EQ.gains[i] then same = false end
        end
        if same then EQ.preset = p end
    end
end

local function setGain(i, db)
    EQ.gains[i] = math.max(-MAXDB, math.min(MAXDB, math.floor(db + 0.5)))
    matchPreset()
end

local function applyPreset(p)
    local pr = EQ_PRESETS[p]
    if not pr then return end
    for i = 1, 5 do EQ.gains[i] = pr.gains[i] end
    EQ.preset = p
end

local function cyclePreset() applyPreset(EQ.preset % #EQ_PRESETS + 1) end

------------------------------------------------------------ when is it applied
local function eligible(w)
    return (w ~= nil) and (w.tag == 1 or w.tag == 65534) and w.bits == 16
        and (w.channels == 1 or w.channels == 2)
end

local function flat()
    for i = 1, 5 do
        if EQ.gains[i] ~= 0 then return false end
    end
    return true
end

local function active(w) return EQ.on and eligible(w) and not flat() end

------------------------------------------------------------ the filter
local floor = math.floor
local T, M = 26000, 32767 -- soft limiter: smooth squeeze between T and full scale

local function soft(y)
    local s = 1
    if y < 0 then s, y = -1, -y end
    if y > T then
        local u = (y - T) / (M - T)
        y = T + (M - T) * u / (1 + u)
    end
    return s * y
end

-- s = whole frames of 16 bit little-endian PCM; returns the filtered bytes, keeps filter state in job.st
local function crunch(job, s)
    local st, c, a, ch = job.st, job.c, job.a, job.ch
    local l1, l2, l3, l4, r1, r2, r3, r4 = st[1], st[2], st[3], st[4], st[5], st[6], st[7], st[8]
    local a1, a2, a3, a4 = a[1], a[2], a[3], a[4]
    local k0, k4, k3, k2, k1 = c[1], c[2], c[3], c[4], c[5]
    local out, len, pos = {}, #s, 1
    while pos <= len do
        local last = math.min(len, pos + 2047)
        local t = { s:byte(pos, last) }
        if ch == 2 then
            for i = 1, #t, 4 do
                local l = t[i] + t[i + 1] * 256
                if l >= 32768 then l = l - 65536 end
                local r = t[i + 2] + t[i + 3] * 256
                if r >= 32768 then r = r - 65536 end
                l1 = l1 + a1 * (l - l1); l2 = l2 + a2 * (l - l2)
                l3 = l3 + a3 * (l - l3); l4 = l4 + a4 * (l - l4)
                r1 = r1 + a1 * (r - r1); r2 = r2 + a2 * (r - r2)
                r3 = r3 + a3 * (r - r3); r4 = r4 + a4 * (r - r4)
                local ly = k0 * l + k4 * l4 + k3 * l3 + k2 * l2 + k1 * l1
                local ry = k0 * r + k4 * r4 + k3 * r3 + k2 * r2 + k1 * r1
                if ly > T or ly < -T then ly = soft(ly) end
                if ry > T or ry < -T then ry = soft(ry) end
                ly = floor(ly + 0.5) % 65536
                ry = floor(ry + 0.5) % 65536
                t[i], t[i + 1] = ly % 256, floor(ly / 256)
                t[i + 2], t[i + 3] = ry % 256, floor(ry / 256)
            end
        else
            for i = 1, #t, 2 do
                local l = t[i] + t[i + 1] * 256
                if l >= 32768 then l = l - 65536 end
                l1 = l1 + a1 * (l - l1); l2 = l2 + a2 * (l - l2)
                l3 = l3 + a3 * (l - l3); l4 = l4 + a4 * (l - l4)
                local ly = k0 * l + k4 * l4 + k3 * l3 + k2 * l2 + k1 * l1
                if ly > T or ly < -T then ly = soft(ly) end
                ly = floor(ly + 0.5) % 65536
                t[i], t[i + 1] = ly % 256, floor(ly / 256)
            end
        end
        out[#out + 1] = string.char(unpack(t))
        pos = last + 1
    end
    st[1], st[2], st[3], st[4], st[5], st[6], st[7], st[8] = l1, l2, l3, l4, r1, r2, r3, r4
    return table.concat(out)
end

------------------------------------------------------------ jobs
local function newJob(w, body, warm, prev)
    local a = {}
    for k = 1, 4 do a[k] = 1 - math.exp(-2 * math.pi * CROSS[k] / w.rate) end
    local g = {}
    for i = 1, 5 do g[i] = 10 ^ (EQ.gains[i] / 20) end
    -- out = g5*x + (g4-g5)*lp4 + (g3-g4)*lp3 + (g2-g3)*lp2 + (g1-g2)*lp1
    local job = {
        body = body, pos = 1, n = #body, out = {}, ch = w.channels, a = a,
        c = { g[5], g[4] - g[5], g[3] - g[4], g[2] - g[3], g[1] - g[2] },
        st = prev and { prev[1], prev[2], prev[3], prev[4], prev[5], prev[6], prev[7], prev[8] }
            or { 0, 0, 0, 0, 0, 0, 0, 0 },
    }
    if warm and #warm > 0 then crunch(job, warm) end -- settle the filters, output is thrown away
    return job
end

-- reads the part that starts at startByte (first = the short one after a start)
local function startJob(path, w, startByte, first, prev)
    local sec = first and FIRST_SEC or CHUNK_SEC
    local size = floor(sec * w.byteRate / w.blockAlign) * w.blockAlign
    local body, sb, lb, warm = wavBody(path, w, startByte, size, prev and 0 or 1024)
    if not body then return nil end
    local job = newJob(w, body, warm, prev)
    job.startByte, job.lastByte, job.w = sb, lb, w
    return job
end

-- works for about `ms` milliseconds; true when the whole part is done
local function stepJob(job, ms)
    local t0 = os.epoch("utc")
    local piece = job.ch * 2 * 8192
    while job.pos <= job.n do
        local last = math.min(job.n, job.pos + piece - 1)
        job.out[#job.out + 1] = crunch(job, job.body:sub(job.pos, last))
        job.pos = last + 1
        if ms and os.epoch("utc") - t0 >= ms then break end
    end
    return job.pos > job.n
end

-- finished job -> WAV data, first byte, end byte, filter state for the next part
local function finish(job)
    return makeWav(job.w, table.concat(job.out)), job.startByte, job.lastByte, job.st
end

-- all at once
local function segment(path, w, startByte, first, prev)
    local job = startJob(path, w, startByte, first, prev)
    if not job then return nil end
    stepJob(job, nil)
    return finish(job)
end

return {
    EQ = EQ,
    NAMES = NAMES,
    EQ_PRESETS = EQ_PRESETS,
    MAXDB = MAXDB,
    eligible = eligible,
    active = active,
    startJob = startJob,
    stepJob = stepJob,
    finish = finish,
    segment = segment,
    setGain = setGain,
    applyPreset = applyPreset,
    cyclePreset = cyclePreset,
    saveEq = saveEq,
}

-- lib/visual.lua : spectrum bars ("equalizer" look)
-- Data source, in this order:
--   1) <track>.vis next to the track (made on the PC by makevis.py): works for ogg and wav
--   2) live analysis of a PCM WAV (cheap octave bands from a short window, read from disk)
--   3) nothing -> a hint is shown
local _config = require("lib.config")
local VIS_OFFSET = _config.VIS_OFFSET or 0
local _state = require("lib.state")
local S = _state.S
local _theme = require("lib.theme")
local C = _theme.C
local _util = require("lib.util")
local clamp = _util.clamp

local V = { mode = nil, data = nil, nb = 0, fps = 10, level = {}, bandMax = {}, last = 0 }
local N = 1024 -- samples in the live analysis window

local function hex(c) return ("%x"):format(math.floor(math.log(c) / math.log(2) + 0.5)) end

-- called when a track starts
local function load()
    V.mode, V.data, V.nb, V.level, V.bandMax = nil, nil, 0, {}, {}
    if not S.path then return end
    local base = S.path:gsub("%.%w+$", "")
    local f = fs.open(base .. ".vis", "rb")
    if f then
        local d = f.readAll()
        f.close()
        if d and #d >= 7 and d:sub(1, 4) == "VIS1" and d:byte(5) > 0 and d:byte(6) > 0 then
            V.mode, V.data, V.nb, V.fps = "file", d, d:byte(5), d:byte(6)
            return
        end
    end
    local w = S.wav
    if w and w.channels and w.channels >= 1 and w.rate and w.rate >= 8000
        and (w.tag == 1 or w.tag == 65534) and (w.bits == 16 or w.bits == 8) then
        V.mode, V.nb = "live", 9
    end
end

-- Haar-style octave energies: ~2N additions for the whole window
-- returns energies from the lowest band to the highest
local function haar(x, n)
    local scales, cur, m = {}, x, n
    while m >= 2 do
        local nxt, e, half = {}, 0, m / 2
        for i = 1, half do
            local a, b = cur[2 * i - 1], cur[2 * i]
            nxt[i] = (a + b) / 2
            local d = (a - b) / 2
            e = e + d * d
        end
        scales[#scales + 1] = math.sqrt(e / half) -- scales[1] = highest octave
        cur, m = nxt, half
    end
    local out = {}
    for s = math.min(#scales - 1, 9), 1, -1 do out[#out + 1] = scales[s] end -- skip the lowest octave
    return out
end

local function liveLevels(t)
    local w = S.wav
    local frame = w.blockAlign
    local last = math.floor(w.dataLen / frame) - N
    local startFrame = clamp(math.floor((t + VIS_OFFSET) * w.rate), 0, math.max(0, last))
    local f = fs.open(S.path, "rb")
    if not f then return nil end
    f.seek("set", w.dataOff - 1 + startFrame * frame)
    local raw = f.read(N * frame)
    f.close()
    if not raw or #raw < N * frame then return nil end

    local x, ch = {}, w.channels
    if w.bits == 16 then
        for i = 0, N - 1 do
            local p = i * frame + 1
            local lo, hi = raw:byte(p, p + 1)
            local s = lo + hi * 256
            if s >= 32768 then s = s - 65536 end
            if ch >= 2 then
                local lo2, hi2 = raw:byte(p + 2, p + 3)
                local s2 = lo2 + hi2 * 256
                if s2 >= 32768 then s2 = s2 - 65536 end
                s = (s + s2) / 2
            end
            x[i + 1] = s / 32768
        end
    else
        for i = 0, N - 1 do
            local p = i * frame + 1
            local s = raw:byte(p) - 128
            if ch >= 2 then s = (s + raw:byte(p + 1) - 128) / 2 end
            x[i + 1] = s / 128
        end
    end
    return haar(x, N)
end

-- every band is scaled by its own recent peak, so all bars use the full height
local function normalize(raw)
    local out = {}
    for i, e in ipairs(raw) do
        local m = math.max((V.bandMax[i] or 0) * 0.992, e, 0.002)
        V.bandMax[i] = m
        out[i] = math.sqrt(e / m)
    end
    return out
end

-- t = seconds from the start of the track; call once per frame
local function update(t)
    local now = os.clock()
    local dt = math.min(0.5, now - V.last)
    V.last = now

    local raw
    if S.state == "playing" and V.mode == "file" then
        local idx = math.floor((t + VIS_OFFSET) * V.fps)
        local off = 7 + idx * V.nb
        if idx >= 0 and off + V.nb - 1 <= #V.data then
            raw = {}
            for i = 1, V.nb do raw[i] = V.data:byte(off + i - 1) / 255 end
        end
    elseif S.state == "playing" and V.mode == "live" then
        local ok, r = pcall(liveLevels, t)
        if ok and r then raw = normalize(r) end
    end

    local decay = math.exp(-dt * 5) -- fast attack, smooth fall
    for i = 1, math.max(#V.level, raw and #raw or 0) do
        local target = raw and raw[i] or 0
        local cur = V.level[i] or 0
        if target >= cur then cur = target else cur = target + (cur - target) * decay end
        V.level[i] = cur
    end
end

-- bars in the rectangle x1..x2, y1..y2 of target t (partial cells use the 2x3 block characters)
local function draw(t, x1, y1, x2, y2)
    local rows, w = y2 - y1 + 1, x2 - x1 + 1
    if rows < 1 or w < 3 then return end
    local win = t.win

    if not V.mode then
        win.setBackgroundColor(C.bg)
        win.setTextColor(C.dim)
        local y = y1 + math.floor((rows - 1) / 2)
        local a = "no visual data"
        local b = (S.kind == "ogg") and "run makevis.py" or "wav is not PCM"
        win.setCursorPos(x1 + math.max(0, math.floor((w - #a) / 2)), y)
        win.write(a:sub(1, w))
        if rows >= 2 then
            win.setCursorPos(x1 + math.max(0, math.floor((w - #b) / 2)), y + 1)
            win.write(b:sub(1, w))
        end
        return
    end

    local bands = math.max(#V.level, V.nb, 1)
    local nb = math.min(bands, math.floor((w + 1) / 2))
    local barW = math.max(1, math.floor((w + 1) / nb) - 1)
    local total = nb * (barW + 1) - 1
    local xs = math.floor((w - total) / 2)

    local heights, colOf = {}, {}
    for j = 1, nb do
        local a = math.floor((j - 1) * bands / nb) + 1
        local b = math.max(a, math.ceil(j * bands / nb))
        local lv = 0
        for i = a, b do lv = math.max(lv, V.level[i] or 0) end
        heights[j] = math.floor(clamp(lv, 0, 1) * rows * 3 + 0.5) -- in 1/3-row steps
        local c0 = xs + (j - 1) * (barW + 1)
        for c = 1, barW do colOf[c0 + c] = j end
    end

    local hBg, hSel, hAcc = hex(C.bg), hex(C.sel), hex(C.accent)
    for y = y1, y2 do
        local rb = y2 - y -- rows above the bottom
        local tx, fg, bg = {}, {}, {}
        for c = 1, w do
            local j = colOf[c]
            local fill = j and clamp(heights[j] - 3 * rb, 0, 3) or 0
            if fill == 0 then
                tx[c], fg[c], bg[c] = " ", hBg, hBg
            else
                tx[c] = (fill == 3) and " " or ((fill == 2) and "\131" or "\143")
                fg[c], bg[c] = hBg, (rb < rows * 0.55) and hSel or hAcc
            end
        end
        win.setCursorPos(x1, y)
        win.blit(table.concat(tx), table.concat(fg), table.concat(bg))
    end
end

return {
    load = load,
    update = update,
    draw = draw,
}

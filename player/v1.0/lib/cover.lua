-- lib/cover.lua : album cover from <track>.cov (made on the PC by makecov.py)
-- Drawn with the 2x3 block characters. The cover uses 9 palette slots the interface
-- does not need; their colors change with every track.
local _state = require("lib.state")
local S = _state.S
local _theme = require("lib.theme")
local C = _theme.C

-- the interface itself uses black, gray, lightGray, white, lightBlue, blue and red
local SLOTS = { colors.orange, colors.magenta, colors.yellow, colors.lime, colors.pink,
                colors.cyan, colors.purple, colors.brown, colors.green }

local COV = { sizes = nil, palette = nil, version = 0 }

local function hex(c) return ("%x"):format(math.floor(math.log(c) / math.log(2) + 0.5)) end
local HEX = {} -- color index in the file (0..8) -> blit character
for i, c in ipairs(SLOTS) do HEX[i - 1] = hex(c) end

-- called when a track starts
local function load()
    COV.sizes, COV.palette = nil, nil
    if not S.path then return end
    local f = fs.open((S.path:gsub("%.%w+$", "")) .. ".cov", "rb")
    if not f then return end
    local d = f.readAll()
    f.close()
    if not d or #d < 6 or d:sub(1, 4) ~= "COV1" or d:byte(5) ~= #SLOTS then return end

    local pos, pal = 6, {}
    for i = 1, #SLOTS do
        local r, g, b = d:byte(pos, pos + 2)
        pal[i] = r * 65536 + g * 256 + b
        pos = pos + 3
    end
    local k = d:byte(pos)
    pos = pos + 1

    local sizes = {}
    for _ = 1, k do
        local cw, ch = d:byte(pos, pos + 1)
        pos = pos + 2
        if not ch or pos + 3 * cw * ch - 1 > #d then return end -- truncated file
        local rows = {}
        for r = 1, ch do
            local text = d:sub(pos, pos + cw - 1)
            pos = pos + cw
            local fg, bg = {}, {}
            for c = 1, cw do fg[c] = HEX[d:byte(pos + c - 1)] or "0" end
            pos = pos + cw
            for c = 1, cw do bg[c] = HEX[d:byte(pos + c - 1)] or "0" end
            pos = pos + cw
            rows[r] = { text = text, fg = table.concat(fg), bg = table.concat(bg) }
        end
        sizes[#sizes + 1] = { cw = cw, ch = ch, rows = rows }
    end
    if #sizes == 0 then return end
    table.sort(sizes, function(a, b) return a.ch < b.ch end)
    COV.sizes, COV.palette = sizes, pal
    COV.version = COV.version + 1 -- tells the screens to load the new palette
end

-- biggest cover that fits into maxRows x maxCols (nil = none)
local function fitSize(maxRows, maxCols)
    local best
    if COV.sizes then
        for _, sz in ipairs(COV.sizes) do
            if sz.ch <= maxRows and sz.cw <= maxCols then best = sz end
        end
    end
    return best
end

-- draws a cover of size sz with its top-left corner at x, y of the real target t
local function drawAt(t, x, y, sz)
    for r, row in ipairs(sz.rows) do
        if y + r - 1 <= t.h then
            t.win.setCursorPos(x, y + r - 1)
            t.win.blit(row.text, row.fg, row.bg)
        end
    end
end

-- the biggest fitting cover, centered in x1..x2, y1..y2 (or a hint)
local function draw(t, x1, y1, x2, y2)
    local w, rows = x2 - x1 + 1, y2 - y1 + 1
    if w < 3 or rows < 1 then return end
    local sz = fitSize(rows, w)
    if sz then
        drawAt(t, x1 + math.floor((w - sz.cw) / 2), y1 + math.floor((rows - sz.ch) / 2), sz)
        return
    end
    local a = COV.sizes and "too small" or "no cover"
    local b = (not COV.sizes) and "run makecov.py" or ""
    local win = t.win
    win.setBackgroundColor(C.bg)
    win.setTextColor(C.dim)
    local y = y1 + math.floor((rows - 1) / 2)
    win.setCursorPos(x1 + math.max(0, math.floor((w - #a) / 2)), y)
    win.write(a:sub(1, w))
    if b ~= "" and rows >= 2 then
        win.setCursorPos(x1 + math.max(0, math.floor((w - #b) / 2)), y + 1)
        win.write(b:sub(1, w))
    end
end

return {
    COV = COV,
    SLOTS = SLOTS,
    load = load,
    fitSize = fitSize,
    drawAt = drawAt,
    draw = draw,
}

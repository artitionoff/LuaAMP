-- lib/theme.lua : colors. The interface uses 7 palette slots; a theme (dark/light + accent)
-- only changes the RGB values behind them. Background, header, buttons and selection are all
-- tinted with the accent, which is corrected for readability. With "adaptive" on, the accent
-- comes from the current track's cover.
local _config = require("lib.config")

-- names -> CC palette slots (the cover module keeps the other 9 slots)
local C = {
    bg = colors.black, panel = colors.gray, track = colors.gray,
    dim = colors.lightGray, text = colors.white,
    accent = colors.lightBlue, sel = colors.blue, onAccent = colors.black,
    bad = colors.red,
}

local PALETTE = {} -- slot -> 0xRRGGBB, rewritten in place by setTheme (only works on advanced screens)

-- accent = the one picked on the theme screen; coverAccent = taken from the current cover (or nil);
-- adaptive = use coverAccent when there is one, otherwise the picked accent
local THEME = { mode = "dark", accent = 0x86CFFA, adaptive = true, coverAccent = nil, coverNote = "no cover", version = 0 }

-- accent presets shown on the theme screen (exactly as many as the cover module has spare slots)
local PRESETS = { 0x86CFFA, 0x7FE5B0, 0xBDE35A, 0xFFC857, 0xFF9A5A, 0xFF7A7A, 0xFF8AD0, 0xB79CFF, 0x6F9BFF }

------------------------------------------------------------ color math
local function rgb(c) return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256 end

local function pack(r, g, b)
    return math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(b + 0.5)
end

local function mix(a, b, t) -- t = 0 -> a, t = 1 -> b
    local ar, ag, ab = rgb(a)
    local br, bg, bb = rgb(b)
    return pack(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

local function lum(c)
    local r, g, b = rgb(c)
    local function ch(v)
        v = v / 255
        if v <= 0.03928 then return v / 12.92 end
        return ((v + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
end

local function contrast(a, b)
    local la, lb = lum(a), lum(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

-- moves `color` toward `towards` until it has the wanted contrast against `against`
local function readable(color, against, need, towards)
    for _ = 1, 14 do
        if contrast(color, against) >= need then break end
        color = mix(color, towards, 0.12)
    end
    return color
end

------------------------------------------------------------ themes
-- colors <-> HSV (used to pick a lively accent from a cover)
local function hsv(c)
    local r, g, b = rgb(c)
    r, g, b = r / 255, g / 255, b / 255
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, (mx == 0) and 0 or d / mx, mx
end

local function fromHsv(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    local r, g, b
    i = i % 6
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return pack(r * 255, g * 255, b * 255)
end

-- the most characteristic color of a cover: the biggest areas count most, saturation is a bonus.
-- pal = RGB list, cnt[i-1] = how many cells use color i. Pale tints (a "white" cover with a blue
-- cast) are allowed and get a clearly visible tone; only real grays return nil (-> picked accent).
local function pickAccent(pal, cnt)
    local total = 0
    for i = 1, #pal do total = total + (cnt[i - 1] or 0) end
    if total == 0 then return nil end
    local best, bestScore = nil, 0
    for i = 1, #pal do
        local h, s, v = hsv(pal[i])
        local w = (cnt[i - 1] or 0) / total
        if s >= 0.04 and v >= 0.2 and w >= 0.02 then
            local score = w * (0.25 + s)
            if score > bestScore then best, bestScore = { h, s, v }, score end
        end
    end
    if not best then return nil end
    -- the palette holds averages: make the tone livelier, and never weaker than a clear tint
    return fromHsv(best[1], math.min(1, math.max(best[2] * 1.2 + 0.08, 0.45)), math.max(best[3], 0.75))
end

------------------------------------------------------------ themes
-- colors <-> HSV (used to pick a lively accent from a cover)
local function hsv(c)
    local r, g, b = rgb(c)
    r, g, b = r / 255, g / 255, b / 255
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, (mx == 0) and 0 or d / mx, mx
end

local function fromHsv(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    local r, g, b
    i = i % 6
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return pack(r * 255, g * 255, b * 255)
end

-- the most characteristic color of a cover: vivid and not just a speck. pal = RGB list,
-- cnt[i-1] = how many cells use color i. Gray covers return nil (-> the picked accent is used).
local function pickAccent(pal, cnt)
    local total = 0
    for i = 1, #pal do total = total + (cnt[i - 1] or 0) end
    if total == 0 then return nil end
    local best, bestScore = nil, 0
    for i = 1, #pal do
        local h, s, v = hsv(pal[i])
        local w = (cnt[i - 1] or 0) / total
        if s >= 0.22 and v >= 0.25 and w >= 0.02 then
            local score = s * (0.5 + 0.5 * v) * math.sqrt(w)
            if score > bestScore then best, bestScore = { h, s, v }, score end
        end
    end
    if not best then return nil end
    -- the palette holds averages: make the color a bit livelier
    return fromHsv(best[1], math.min(1, best[2] * 1.2 + 0.08), math.max(best[3], 0.75))
end

------------------------------------------------------------ themes
local function rebuild()
    local mode = THEME.mode
    local accent = (THEME.adaptive and THEME.coverAccent) or THEME.accent
    local dark = (mode == "dark")
    local towards = dark and 0xFFFFFF or 0x000000          -- direction that adds contrast
    local need = dark and 4.5 or 4.0
    local text = dark and 0xEAF3FA or 0x14202B
    local bad = dark and 0xFF7A7A or 0xC62828

    -- everything is tinted with the accent: background, header/buttons, selection, dim text
    local base = dark and 0x0B1118 or 0xF4F7FA
    local acc = readable(accent, base, need, towards)
    local bg = mix(base, acc, dark and 0.05 or 0.06)
    acc = readable(acc, bg, need, towards)
    local panel = readable(mix(bg, acc, dark and 0.26 or 0.27), text, 7, bg)   -- header, buttons
    local sel = readable(mix(bg, acc, dark and 0.45 or 0.55), text, 4.5, bg)   -- cursor row, active toggles
    local dim = readable(mix(dark and 0x8FA3B5 or 0x5A6B7C, acc, 0.25), bg, 4.5, towards)

    PALETTE[C.bg], PALETTE[C.panel], PALETTE[C.dim], PALETTE[C.text] = bg, panel, dim, text
    PALETTE[C.accent], PALETTE[C.sel], PALETTE[C.bad] = acc, sel, bad
    THEME.version = THEME.version + 1
end

local function setTheme(mode, accent)
    THEME.mode = (mode == "light") and "light" or "dark"
    THEME.accent = accent or 0x86CFFA
    rebuild()
end

local function setAdaptive(on)
    THEME.adaptive = on and true or false
    rebuild()
end

-- called by the cover module for every track (pal = nil when the track has no cover)
-- fileAccent: number = accent stored in the .cov, false = the file says "gray picture",
-- nil = old file without it (the accent is picked from the palette)
local function setCoverPalette(pal, cnt, fileAccent)
    local acc
    if pal then
        if fileAccent ~= nil then acc = fileAccent or nil else acc = pickAccent(pal, cnt) end
    end
    THEME.coverNote = (not pal) and "no cover" or (acc and ("cover #%06X"):format(acc) or "gray cover")
    if acc == THEME.coverAccent then return end
    THEME.coverAccent = acc
    if THEME.adaptive then rebuild() end
end

-- the choice is stored next to the playlists (that folder is writable)
local THEME_FILE = fs.combine(_config.LIST_DIR, "theme.cfg")

local function saveTheme()
    local f = fs.open(THEME_FILE, "w")
    if not f then return end
    pcall(f.write, textutils.serialize({ mode = THEME.mode, accent = THEME.accent, adaptive = THEME.adaptive }))
    pcall(f.close)
end

local function loadTheme()
    local mode, accent = _config.THEME_MODE or "dark", _config.THEME_ACCENT or 0x86CFFA
    THEME.adaptive = (_config.THEME_ADAPTIVE ~= false)
    if fs.exists(THEME_FILE) then
        local f = fs.open(THEME_FILE, "r")
        if f then
            local t = textutils.unserialize(f.readAll())
            f.close()
            if type(t) == "table" then
                if t.mode == "light" or t.mode == "dark" then mode = t.mode end
                if type(t.accent) == "number" then accent = t.accent end
                if type(t.adaptive) == "boolean" then THEME.adaptive = t.adaptive end
            end
        end
    end
    setTheme(mode, accent)
end

loadTheme()

return {
    C = C,
    PALETTE = PALETTE,
    THEME = THEME,
    PRESETS = PRESETS,
    setTheme = setTheme,
    setAdaptive = setAdaptive,
    setCoverPalette = setCoverPalette,
    saveTheme = saveTheme,
    loadTheme = loadTheme,
}

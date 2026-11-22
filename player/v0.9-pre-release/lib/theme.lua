-- lib/theme.lua : colors. The interface uses 7 palette slots; a theme (dark/light + accent)
-- only changes the RGB values behind them. Background, header, buttons and selection are all
-- tinted with the accent, which is corrected for readability.
local _config = require("lib.config")

-- names -> CC palette slots (the cover module keeps the other 9 slots)
local C = {
    bg = colors.black, panel = colors.gray, track = colors.gray,
    dim = colors.lightGray, text = colors.white,
    accent = colors.lightBlue, sel = colors.blue, onAccent = colors.black,
    bad = colors.red,
}

local PALETTE = {} -- slot -> 0xRRGGBB, rewritten in place by setTheme (only works on advanced screens)

local THEME = { mode = "dark", accent = 0x86CFFA, version = 0 }

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
local function setTheme(mode, accent)
    mode = (mode == "light") and "light" or "dark"
    accent = accent or 0x86CFFA
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
    THEME.mode, THEME.accent = mode, accent
    THEME.version = THEME.version + 1
end

-- the choice is stored next to the playlists (that folder is writable)
local THEME_FILE = fs.combine(_config.LIST_DIR, "theme.cfg")

local function saveTheme()
    local f = fs.open(THEME_FILE, "w")
    if not f then return end
    pcall(f.write, textutils.serialize({ mode = THEME.mode, accent = THEME.accent }))
    pcall(f.close)
end

local function loadTheme()
    local mode, accent = _config.THEME_MODE or "dark", _config.THEME_ACCENT or 0x86CFFA
    if fs.exists(THEME_FILE) then
        local f = fs.open(THEME_FILE, "r")
        if f then
            local t = textutils.unserialize(f.readAll())
            f.close()
            if type(t) == "table" then
                if t.mode == "light" or t.mode == "dark" then mode = t.mode end
                if type(t.accent) == "number" then accent = t.accent end
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
    saveTheme = saveTheme,
    loadTheme = loadTheme,
}

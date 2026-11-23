-- lib/targets.lua : terminal + monitors: windows, palette, render, click
local _config = require("lib.config")
local MONITOR_SCALE, USE_TERMINAL = _config.MONITOR_SCALE, _config.USE_TERMINAL
local _state = require("lib.state")
local UI, VIEW = _state.UI, _state.VIEW
local _actions = require("lib.actions")
local A = _actions.A
local _playback = require("lib.playback")
local expireMsg, elapsed = _playback.expireMsg, _playback.elapsed
local _visual = require("lib.visual")
local visualUpdate = _visual.update
local _cover = require("lib.cover")
local COV, SLOTS = _cover.COV, _cover.SLOTS
local _search = require("lib.search")
local currentMap, syncSearch = _search.currentMap, _search.syncSearch
local _theme = require("lib.theme")
local C, PALETTE, THEME, PRESETS = _theme.C, _theme.PALETTE, _theme.THEME, _theme.PRESETS
local _ui = require("lib.ui")
local drawEq = _ui.drawEq
local drawEdit, drawLists, drawName, drawPlayer, drawTheme = _ui.drawEdit, _ui.drawLists, _ui.drawName, _ui.drawPlayer, _ui.drawTheme

local targets = {}
local allColors = {} -- interface colors + the slots covers use: all saved and restored
for c in pairs(PALETTE) do allColors[#allColors + 1] = c end
for _, c in ipairs(SLOTS) do allColors[#allColors + 1] = c end

local function savePalette(t)
    for _, c in ipairs(allColors) do
        local ok, r, g, b = pcall(t.dev.getPaletteColor, c)
        if ok and r then t.orig[c] = { r, g, b } end
    end
end

local function applyPalette(t)
    for c, rgb in pairs(PALETTE) do
        pcall(t.dev.setPaletteColor, c, rgb)
        pcall(t.win.setPaletteColor, c, rgb)
    end
end

local function restorePalette(t)
    for c, v in pairs(t.orig) do
        pcall(t.dev.setPaletteColor, c, v[1], v[2], v[3])
    end
end

-- the palette of the current cover goes into the spare slots
local function applyCoverTo(t)
    if not COV.palette then return end
    for i, rgb in ipairs(COV.palette) do
        pcall(t.dev.setPaletteColor, SLOTS[i], rgb)
        pcall(t.win.setPaletteColor, SLOTS[i], rgb)
    end
end

local appliedCover = 0
local function syncCoverPalette()
    if UI.screen == "theme" then return end -- the swatches use these slots meanwhile
    if COV.palette and COV.version ~= appliedCover then
        appliedCover = COV.version
        for _, t in ipairs(targets) do applyCoverTo(t) end
    end
end

-- a theme change (dark/light, accent) only rewrites the RGB of the interface slots
local appliedTheme = 0
local function syncTheme()
    if THEME.version ~= appliedTheme then
        appliedTheme = THEME.version
        for _, t in ipairs(targets) do applyPalette(t) end
    end
end

-- the theme screen shows the accent presets in the slots covers normally use
local swatches = false
local function syncSwatches()
    local on = UI.screen == "theme"
    if on == swatches then return end
    swatches = on
    if on then
        for _, t in ipairs(targets) do
            for i, rgb in ipairs(PRESETS) do
                pcall(t.dev.setPaletteColor, SLOTS[i], rgb)
                pcall(t.win.setPaletteColor, SLOTS[i], rgb)
            end
        end
    else
        appliedCover = 0 -- load the cover palette again
    end
end

local function makeTarget(dev, kind, name)
    local w, h = dev.getSize()
    local t = { dev = dev, kind = kind, name = name, w = w, h = h,
                hits = {}, top = 1, ltop = 1, etop = 1, orig = {} }
    savePalette(t)
    t.win = window.create(dev, 1, 1, w, h, true)
    applyPalette(t)
    applyCoverTo(t)
    return t
end

local function destroyTargets()
    for _, t in ipairs(targets) do
        pcall(function()
            t.dev.setBackgroundColor(colors.black)
            t.dev.setTextColor(colors.white)
            t.dev.clear()
            t.dev.setCursorPos(1, 1)
        end)
        restorePalette(t)
    end
    targets = {}
end

local function buildTargets()
    destroyTargets()
    if USE_TERMINAL then
        targets[#targets + 1] = makeTarget(term.current(), "term")
    end
    for _, m in ipairs({ peripheral.find("monitor") }) do
        if MONITOR_SCALE then
            m.setTextScale(MONITOR_SCALE)
        else
            m.setTextScale(1)
            if (m.getSize()) < 15 then m.setTextScale(0.5) end
        end
        targets[#targets + 1] = makeTarget(m, "monitor", peripheral.getName(m))
    end
    if #targets == 0 then
        targets[1] = makeTarget(term.current(), "term")
    end
end

local function resizeAll()
    for _, t in ipairs(targets) do
        local w, h = t.dev.getSize()
        t.w, t.h = w, h
        t.win.reposition(1, 1, w, h)
    end
end

local function render()
    if UI.view == "vis" and UI.screen == "player" then visualUpdate(elapsed()) end
    syncTheme()
    syncSwatches()
    syncCoverPalette()
    expireMsg()
    syncSearch()
    VIEW.map = currentMap()
    for _, t in ipairs(targets) do
        t.win.setVisible(false)
        t.win.setBackgroundColor(C.bg)
        t.win.setTextColor(C.text)
        t.win.clear()
        t.hits = {}
        local ok, err = pcall(function()
            local scr = UI.screen
            if scr == "lists" then drawLists(t)
            elseif scr == "edit" then drawEdit(t)
            elseif scr == "name" then drawName(t)
            elseif scr == "theme" then drawTheme(t)
            elseif scr == "eq" then drawEq(t)
            else drawPlayer(t) end
        end)
        t.win.setVisible(true)
        if not ok then error(err, 0) end
    end
end

local function click(t, x, y)
    for i = #t.hits, 1, -1 do
        local h = t.hits[i]
        if h.y == y and x >= h.x1 and x <= h.x2 then
            if A[h.action] then A[h.action](h.arg, x, y) end
            return
        end
    end
end

local function targetByKind(kind, name)
    for _, t in ipairs(targets) do
        if t.kind == kind and (name == nil or t.name == name) then return t end
    end
end

return {
    buildTargets = buildTargets,
    click = click,
    destroyTargets = destroyTargets,
    render = render,
    resizeAll = resizeAll,
    targetByKind = targetByKind,
}

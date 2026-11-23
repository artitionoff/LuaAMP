-- lib/actions.lua : actions (mouse + keyboard) and key handlers
local _theme = require("lib.theme")
local THEME, PRESETS, setTheme, saveTheme, setAdaptive = _theme.THEME, _theme.PRESETS, _theme.setTheme, _theme.saveTheme, _theme.setAdaptive
local _eq = require("lib.eq")
local EQ, setGain, applyPreset, cyclePreset, saveEq = _eq.EQ, _eq.setGain, _eq.applyPreset, _eq.cyclePreset, _eq.saveEq
local _config = require("lib.config")
local VOL_STEP = _config.VOL_STEP
local SEEK_STEP = _config.SEEK_STEP or 10 -- seconds for the [ and ] keys and the << >> buttons
local _state = require("lib.state")
local E, L, N, Q, S, SEARCH, UI = _state.E, _state.L, _state.N, _state.Q, _state.S, _state.SEARCH, _state.UI
local _library = require("lib.library")
local plPath = _library.plPath
local _lists = require("lib.lists")
local openEdit, playListIndex, refreshLists, saveEdit, tickIndex = _lists.openEdit, _lists.playListIndex, _lists.refreshLists, _lists.saveEdit, _lists.tickIndex
local _playback = require("lib.playback")
local restartSoon, seekTo, seekBy = _playback.restartSoon, _playback.seekTo, _playback.seekBy
local go, setVolume, startTrack, stop, togglePause = _playback.go, _playback.setVolume, _playback.startTrack, _playback.stop, _playback.togglePause
local _queue = require("lib.queue")
local buildOrder = _queue.buildOrder
local _search = require("lib.search")
local currentMap, snapCursor, stepIn = _search.currentMap, _search.snapCursor, _search.stepIn
local _util = require("lib.util")
local clamp = _util.clamp

local A = {}

function A.playpause() togglePause() end
function A.stop() stop() end
function A.next() if #Q.order > 0 then go(1, false) end end
function A.prev() if #Q.order > 0 then go(-1, false) end end
function A.shuffle() Q.shuffle = not Q.shuffle; buildOrder(true); UI.cursor = Q.pos end
function A.repeatm() Q.repeatMode = Q.repeatMode % 3 + 1 end
function A.voldown() setVolume(S.volume - VOL_STEP) end
function A.volup() setVolume(S.volume + VOL_STEP) end
function A.seekback() seekBy(-SEEK_STEP) end
function A.seekfwd() seekBy(SEEK_STEP) end
function A.seek(arg, x) -- click on the progress bar: arg = { first column, width }
    if not x or not S.dur then return end
    seekTo(clamp((x - arg[1] + 0.5) / arg[2], 0, 1) * S.dur)
end
local NEXT_VIEW = { list = "vis", vis = "cover", cover = "list" }
function A.view() UI.view = NEXT_VIEW[UI.view] or "list" end
function A.theme() UI.themeFrom, UI.screen = UI.screen, "theme" end
function A.tmode(m) setTheme(m, THEME.accent); saveTheme() end
function A.taccent(i) if PRESETS[i] then setTheme(THEME.mode, PRESETS[i]); saveTheme() end end
function A.tadapt() setAdaptive(not THEME.adaptive); saveTheme() end
function A.tback() UI.screen = (UI.themeFrom == "lists") and "lists" or "player" end

-- equalizer (a change restarts WAV playback from the same spot a moment later)
local function eqChanged() saveEq(); restartSoon() end
function A.eq() UI.eqFrom, UI.screen = UI.screen, "eq" end
function A.eqback() UI.screen = (UI.eqFrom == "lists") and "lists" or "player" end
function A.eqtoggle() EQ.on = not EQ.on; eqChanged() end
function A.eqsel(i) EQ.sel = i end
function A.eqset(arg) EQ.sel = arg[1]; setGain(arg[1], arg[2]); eqChanged() end
function A.eqnudge(arg) EQ.sel = arg[1]; setGain(arg[1], EQ.gains[arg[1]] + arg[2]); eqChanged() end
function A.eqpreset() cyclePreset(); eqChanged() end
function A.eqreset() applyPreset(1); eqChanged() end
function A.quit() UI.quit = true end
function A.lists()
    L.msg, L.confirm, L.cursor = nil, nil, 1
    refreshLists()
    UI.screen = "lists"
end
function A.pick(i)
    if not Q.order[i] then return end
    Q.pos, UI.cursor = i, i
    if not startTrack() then go(1, false) end
end
function A.lback() UI.screen = "player" end
function A.lpick(i) L.msg, L.confirm = nil, nil; playListIndex(i) end
function A.lnew()
    L.msg, L.confirm = nil, nil
    N.text, N.msg = "", nil
    UI.screen = "name"
end
function A.ledit()
    L.msg, L.confirm = nil, nil
    if L.cursor > 1 then
        openEdit(L.names[L.cursor - 1])
    else
        L.msg = "library can't be edited"
    end
end
function A.nnext()
    local name = N.text:gsub("^%s+", "")
    name = name:gsub("%s+$", "")
    if name == "" then UI.screen = "lists" return end
    if name:lower() == "whole library" then N.msg = "reserved name" return end
    openEdit(name)
end
function A.ncancel() UI.screen = "lists" end
function A.find(skip) -- skip = the character the opening key is about to type
    if UI.screen == "player" or UI.screen == "edit" then
        SEARCH.active = true
        SEARCH.skip = skip
    end
end
function A.fclear() SEARCH.text, SEARCH.active = "", false end
function A.etoggle(i)
    local f = E.lib[i]
    if not f then return end
    E.cursor, E.msg = i, nil
    local p = tickIndex(f)
    if p then table.remove(E.order, p) else E.order[#E.order + 1] = f end
end
function A.esave() saveEdit() end
function A.ecancel() UI.screen = "lists" end
function A.ldel()
    if L.cursor <= 1 then L.msg = "library can't be deleted" return end
    local n = L.names[L.cursor - 1]
    if L.confirm == n then
        fs.delete(plPath(n))
        L.confirm, L.msg = nil, nil
        refreshLists()
    else
        L.confirm, L.msg = n, "press Delete again"
    end
end

-- theme screen: left/right = accent, up/down = dark/light, enter/q = back
local function themeKey(k, held)
    if k == keys.left or k == keys.right then
        local cur = 0
        for i, v in ipairs(PRESETS) do
            if v == THEME.accent then cur = i end
        end
        A.taccent((cur - 1 + ((k == keys.right) and 1 or -1)) % #PRESETS + 1)
    elseif k == keys.up or k == keys.down then
        if not held then A.tmode((THEME.mode == "dark") and "light" or "dark") end
    elseif held then return
    elseif k == keys.a then A.tadapt()
    elseif k == keys.enter or k == keys.q or k == keys.backspace then A.tback() end
end

-- equalizer screen: left/right = band, up/down = +-1 dB, 0 = zero band, P = preset, R = reset,
-- space/E = on/off, enter/Q = back
local function eqKey(k, held)
    if k == keys.left then EQ.sel = (EQ.sel - 2) % 5 + 1
    elseif k == keys.right then EQ.sel = EQ.sel % 5 + 1
    elseif k == keys.up then A.eqnudge({ EQ.sel, 1 })
    elseif k == keys.down then A.eqnudge({ EQ.sel, -1 })
    elseif held then return
    elseif k == keys.zero or k == keys.numPad0 then A.eqset({ EQ.sel, 0 })
    elseif k == keys.p or k == keys.tab then A.eqpreset()
    elseif k == keys.r then A.eqreset()
    elseif k == keys.space or k == keys.e then A.eqtoggle()
    elseif k == keys.enter or k == keys.q or k == keys.backspace then A.eqback() end
end

local function moveCursor(d)
    if UI.screen == "lists" then
        L.cursor = clamp(L.cursor + d, 1, #L.items)
        L.msg, L.confirm = nil, nil
    elseif UI.screen == "edit" then
        E.cursor = stepIn(currentMap(), E.cursor, d, #E.lib)
    elseif UI.screen == "name" or UI.screen == "theme" or UI.screen == "eq" then
        return
    else
        UI.cursor = stepIn(currentMap(), UI.cursor, d, #Q.order)
    end
end

local function playerKey(k, held)
    if k == keys.up then moveCursor(-1)
    elseif k == keys.down then moveCursor(1)
    elseif k == keys.pageUp then moveCursor(-5)
    elseif k == keys.pageDown then moveCursor(5)
    elseif k == keys.home then UI.cursor = 1
    elseif k == keys["end"] then UI.cursor = math.max(1, #Q.order)
    elseif k == keys.backspace and SEARCH.text ~= "" then A.fclear()
    elseif k == keys.equals or k == keys.numPadAdd then setVolume(S.volume + VOL_STEP)
    elseif k == keys.minus or k == keys.numPadSubtract then setVolume(S.volume - VOL_STEP)
    elseif k == keys.leftBracket then A.seekback()
    elseif k == keys.rightBracket then A.seekfwd()
    elseif held then return
    elseif k == keys.slash or k == keys.numPadDivide then A.find("/")
    elseif k == keys.space then A.playpause()
    elseif k == keys.x then A.stop()
    elseif k == keys.n or k == keys.right then A.next()
    elseif k == keys.p or k == keys.left then A.prev()
    elseif k == keys.enter then A.pick(UI.cursor)
    elseif k == keys.s then A.shuffle()
    elseif k == keys.r then A.repeatm()
    elseif k == keys.m or k == keys.l then A.lists()
    elseif k == keys.v then A.view()
    elseif k == keys.t then A.theme()
    elseif k == keys.e then A.eq()
    elseif k == keys.q then A.quit() end
end

local function listsKey(k, held)
    if k == keys.up then moveCursor(-1)
    elseif k == keys.down then moveCursor(1)
    elseif held then return
    elseif k == keys.enter then A.lpick(L.cursor)
    elseif k == keys.q or k == keys.backspace or k == keys.m then A.lback()
    elseif k == keys.n then A.lnew()
    elseif k == keys.e then A.ledit()
    elseif k == keys.d then A.ldel()
    elseif k == keys.t then A.theme() end
end

local function editKey(k, held)
    if k == keys.up then moveCursor(-1)
    elseif k == keys.down then moveCursor(1)
    elseif k == keys.pageUp then moveCursor(-5)
    elseif k == keys.pageDown then moveCursor(5)
    elseif held then return
    elseif k == keys.space then A.etoggle(E.cursor)
    elseif k == keys.enter then A.esave()
    elseif k == keys.slash or k == keys.numPadDivide then A.find("/")
    elseif k == keys.backspace and SEARCH.text ~= "" then A.fclear()
    elseif k == keys.q or k == keys.backspace then A.ecancel() end
end

-- while typing a search: letters go to the text, a few keys keep their meaning
local function searchKey(k, held)
    SEARCH.skip = nil
    if k == keys.backspace then
        if SEARCH.text == "" then SEARCH.active = false
        else SEARCH.text = SEARCH.text:sub(1, -2) end
        snapCursor()
    elseif k == keys.up then moveCursor(-1)
    elseif k == keys.down then moveCursor(1)
    elseif k == keys.pageUp then moveCursor(-5)
    elseif k == keys.pageDown then moveCursor(5)
    elseif held then return
    elseif k == keys.tab then SEARCH.active = false -- stop typing, keep the filter
    elseif k == keys.enter then
        local map = currentMap()
        if map and #map == 0 then return end
        if UI.screen == "edit" then
            A.etoggle(E.cursor)
        else
            local pos = UI.cursor
            SEARCH.text, SEARCH.active = "", false
            A.pick(pos)
        end
    end
end

local function nameKey(k, held)
    if k == keys.backspace then N.text = N.text:sub(1, -2); N.msg = nil
    elseif held then return
    elseif k == keys.enter then A.nnext() end
end

return {
    A = A,
    editKey = editKey,
    listsKey = listsKey,
    moveCursor = moveCursor,
    nameKey = nameKey,
    playerKey = playerKey,
    searchKey = searchKey,
    themeKey = themeKey,
    eqKey = eqKey,
}

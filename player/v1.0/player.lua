-- player.lua : music player for the Create Electro Energetics speaker
-- Files: player.lua (this) + lib/*.lua. Your settings live in lib/config.lua.
--
-- Screens: PLAYER (queue + now playing) and PLAYLISTS.
-- Draws on the computer terminal AND on every attached monitor (1x1 .. 3x4 blocks),
-- layout adapts to the real character size of each screen.
--
-- Keyboard (player):
--   SPACE pause/resume   X stop        N / RIGHT next     P / LEFT prev
--   UP/DOWN/PGUP/PGDN move cursor      ENTER play cursor
--   = / -  (or numpad +/-) volume      S shuffle          R repeat
--   / find (type; ENTER = play, TAB = stop typing but keep the filter, BACKSPACE = erase)
--   M or L playlists                   Q quit
-- Keyboard (playlists): UP/DOWN, ENTER play, N new, E edit, D delete (press twice), Q back
-- Mouse / monitor touch: every button, list row and label is clickable.
--
-- UI text is English on purpose: the CC font has no Cyrillic.


-- find lib/ next to this file, whatever the current directory is
local dir = fs.getDir(shell.getRunningProgram())
local prefix = (dir == "") and "/" or ("/" .. dir .. "/")
package.path = prefix .. "?.lua;" .. prefix .. "?/init.lua;" .. package.path

local _config = require("lib.config")
local GAP, LIST_DIR, MUSIC_DIR = _config.GAP, _config.LIST_DIR, _config.MUSIC_DIR
local _state = require("lib.state")
local N, Q, S, SEARCH, UI = _state.N, _state.Q, _state.S, _state.SEARCH, _state.UI
local _actions = require("lib.actions")
local eqKey = _actions.eqKey
local editKey, listsKey, moveCursor, nameKey, playerKey, searchKey, themeKey = _actions.editKey, _actions.listsKey, _actions.moveCursor, _actions.nameKey, _actions.playerKey, _actions.searchKey, _actions.themeKey
local _library = require("lib.library")
local scanLibrary = _library.scanLibrary
local _lists = require("lib.lists")
local refreshLists = _lists.refreshLists
local _meta = require("lib.meta")
local loadMeta, saveMeta, scanMeta = _meta.loadMeta, _meta.saveMeta, _meta.scanMeta
local _playback = require("lib.playback")
local eqWork = _playback.eqWork
local armTick, go, nextChunk, playFrom, rawElapsed, stop = _playback.armTick, _playback.go, _playback.nextChunk, _playback.playFrom, _playback.rawElapsed, _playback.stop
local _queue = require("lib.queue")
local buildOrder = _queue.buildOrder
local _search = require("lib.search")
local snapCursor, syncSearch = _search.snapCursor, _search.syncSearch
local _targets = require("lib.targets")
local buildTargets, click, destroyTargets, render, resizeAll, targetByKind = _targets.buildTargets, _targets.click, _targets.destroyTargets, _targets.render, _targets.resizeAll, _targets.targetByKind

for _, d in ipairs({ MUSIC_DIR, LIST_DIR }) do
    if not fs.exists(d) then fs.makeDir(d) end
end
math.randomseed(os.epoch("utc"))

local function main()
    Q.tracks, Q.name = scanLibrary(), "Whole library"
    loadMeta()
    print("Reading track info...")
    scanMeta(Q.tracks)
    buildOrder(false)
    UI.cursor = 1
    refreshLists()

    buildTargets()
    armTick()
    render()

    while not UI.quit do
        local ev, a, b, c = os.pullEventRaw()
        local dirty, retick = true, true

        if ev == "terminate" then
            break

        elseif ev == "timer" then
            if a == S.timer then
                S.timer = nil
                go(1, true)
            elseif a == S.nextTimer then
                S.nextTimer = nil
                nextChunk()
            elseif a == S.volTimer then
                S.volTimer = nil
                if S.state == "playing" and S.kind == "wav" and S.wav then
                    playFrom(rawElapsed())
                end
            elseif a == S.tick then
                S.tick = nil
                -- fallbacks in case a timer got lost
                if S.nextSeg and S.state == "playing" and rawElapsed() > S.nextAt + 0.4 then
                    nextChunk()
                end
                if S.state == "playing" and S.dur and rawElapsed() > S.dur + GAP + 0.6 then
                    go(1, true)
                end
                armTick() -- re-armed AFTER any speaker call made above
                retick = false
            else
                dirty, retick = false, false
            end

        elseif ev == "eq_work" then
            eqWork()
            dirty, retick = false, false

        elseif ev == "key" then
            local scr = UI.screen
            syncSearch()
            if SEARCH.active and (scr == "player" or scr == "edit") then searchKey(a, b)
            elseif scr == "lists" then listsKey(a, b)
            elseif scr == "edit" then editKey(a, b)
            elseif scr == "name" then nameKey(a, b)
            elseif scr == "theme" then themeKey(a, b)
            elseif scr == "eq" then eqKey(a, b)
            else playerKey(a, b) end

        elseif ev == "char" then
            if UI.screen == "name" and a:match("^[%w _%-]$") and #N.text < 24 then
                N.text = N.text .. a
                N.msg = nil
            elseif SEARCH.active and (UI.screen == "player" or UI.screen == "edit") then
                if SEARCH.skip == a then
                    SEARCH.skip = nil -- the "/" that opened the search
                elseif a:match("^[ -~]$") and #SEARCH.text < 30 then
                    SEARCH.text = SEARCH.text .. a
                    snapCursor()
                else
                    dirty, retick = false, false
                end
            else
                dirty, retick = false, false
            end

        elseif ev == "mouse_click" then
            local t = targetByKind("term")
            if t then click(t, b, c) end

        elseif ev == "monitor_touch" then
            local t = targetByKind("monitor", a)
            if t then click(t, b, c) end

        elseif ev == "mouse_scroll" then
            moveCursor(a)

        elseif ev == "term_resize" or ev == "monitor_resize" then
            resizeAll()

        elseif ev == "peripheral" or ev == "peripheral_detach" then
            buildTargets()

        else
            dirty, retick = false, false
        end

        -- any handler may have called the speaker (blocking) and swallowed the tick
        if retick then armTick() end
        if dirty then render() end
    end
end

local ok, err = pcall(main)
pcall(stop)
pcall(saveMeta)
destroyTargets()
term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
term.clear(); term.setCursorPos(1, 1)
if not ok then printError(err) end

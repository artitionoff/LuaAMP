-- lib/lists.lua : playlist list + editor logic
local _state = require("lib.state")
local E, L, Q, SEARCH, UI = _state.E, _state.L, _state.Q, _state.SEARCH, _state.UI
local _library = require("lib.library")
local listPlaylists, loadPlaylist, plPath, savePlaylist, scanLibrary = _library.listPlaylists, _library.loadPlaylist, _library.plPath, _library.savePlaylist, _library.scanLibrary
local _playback = require("lib.playback")
local go, startTrack = _playback.go, _playback.startTrack
local _queue = require("lib.queue")
local buildOrder = _queue.buildOrder
local _util = require("lib.util")
local clamp = _util.clamp

local function refreshLists()
    L.names = listPlaylists()
    L.items = { "Whole library" }
    for _, n in ipairs(L.names) do L.items[#L.items + 1] = n end
    L.cursor = clamp(L.cursor, 1, #L.items)
end

local function playListIndex(i)
    local tracks, name
    if i == 1 then
        tracks, name = scanLibrary(), "Whole library"
    else
        name = L.names[i - 1]
        tracks = name and loadPlaylist(name) or {}
    end
    if #tracks == 0 then
        L.msg = "playlist is empty"
        return
    end
    Q.tracks, Q.name = tracks, name
    buildOrder(false)
    UI.cursor, UI.screen = 1, "player"
    if not startTrack() then go(1, false) end
end

local function tickIndex(file)
    for i, v in ipairs(E.order) do
        if v == file then return i end
    end
end

local function openEdit(name)
    E.name, E.lib = name, scanLibrary()
    E.order = fs.exists(plPath(name)) and loadPlaylist(name) or {}
    E.cursor, E.msg = 1, nil
    UI.screen = "edit"
end

local function saveEdit()
    if #E.order == 0 then E.msg = "tick at least one track" return end
    local ok, err = savePlaylist(E.name, E.order)
    if not ok then
        E.msg = err
        SEARCH.text, SEARCH.active = "", false
        return
    end
    refreshLists()
    for i, n in ipairs(L.items) do
        if n == E.name then L.cursor = i end
    end
    L.msg, L.confirm = "saved: " .. E.name, nil
    UI.screen = "lists"
end

return {
    openEdit = openEdit,
    playListIndex = playListIndex,
    refreshLists = refreshLists,
    saveEdit = saveEdit,
    tickIndex = tickIndex,
}

-- lib/library.lua : music folder scan and playlist files
local _config = require("lib.config")
local LIST_DIR, MUSIC_DIR = _config.LIST_DIR, _config.MUSIC_DIR

local function scanLibrary()
    local list = {}
    for _, f in ipairs(fs.list(MUSIC_DIR)) do
        if not fs.isDir(fs.combine(MUSIC_DIR, f)) and (f:match("%.wav$") or f:match("%.ogg$")) then
            list[#list + 1] = f
        end
    end
    table.sort(list)
    return list
end

local function plPath(n) return fs.combine(LIST_DIR, n .. ".pl") end

local function listPlaylists()
    local names = {}
    for _, f in ipairs(fs.list(LIST_DIR)) do
        local n = f:match("^(.+)%.pl$")
        if n then names[#names + 1] = n end
    end
    table.sort(names)
    return names
end

local function loadPlaylist(n)
    local f = fs.open(plPath(n), "r")
    if not f then return {} end
    local t = textutils.unserialize(f.readAll()) or {}
    f.close()
    local out = {}
    for _, track in ipairs(t) do -- drop files that no longer exist
        if fs.exists(fs.combine(MUSIC_DIR, track)) then out[#out + 1] = track end
    end
    return out
end

local function freeSpace()
    local ok, free = pcall(fs.getFreeSpace, "/")
    if ok and type(free) == "number" and free < 1e15 then return math.floor(free) .. " B free" end
    return "free space unknown"
end

-- returns true, or false + reason (e.g. the computer is out of disk space)
local function savePlaylist(n, tracks)
    local f, err = fs.open(plPath(n), "w")
    if not f then
        return false, tostring(err or "can't open file") .. " (" .. freeSpace() .. ")"
    end
    local ok, werr = pcall(f.write, textutils.serialize(tracks))
    pcall(f.close)
    if not ok then return false, tostring(werr) .. " (" .. freeSpace() .. ")" end
    return true
end

return {
    listPlaylists = listPlaylists,
    loadPlaylist = loadPlaylist,
    plPath = plPath,
    savePlaylist = savePlaylist,
    scanLibrary = scanLibrary,
}

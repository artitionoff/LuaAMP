-- lib/search.lua : search filter for the queue and the editor
local _state = require("lib.state")
local E, Q, SEARCH, UI = _state.E, _state.Q, _state.SEARCH, _state.UI
local _meta = require("lib.meta")
local getMeta, trackLabel = _meta.getMeta, _meta.trackLabel
local _util = require("lib.util")
local clamp = _util.clamp

-- "/" or the Find button starts typing; the list is filtered on the fly.
-- Every word must be found in "Artist - Title  Album" (case-insensitive).

local function buildMap(count, fileAt)
    if SEARCH.text == "" then return nil end
    local words = {}
    for w in SEARCH.text:lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return nil end
    local map = {}
    for i = 1, count do
        local file = fileAt(i)
        local m = getMeta(file)
        local hay = (trackLabel(file) .. " " .. (m.album or "")):lower()
        local ok = true
        for _, w in ipairs(words) do
            if not hay:find(w, 1, true) then ok = false break end
        end
        if ok then map[#map + 1] = i end
    end
    return map
end

local function currentMap()
    if UI.screen == "player" then
        return buildMap(#Q.order, function(i) return Q.tracks[Q.order[i]] end)
    elseif UI.screen == "edit" then
        return buildMap(#E.lib, function(i) return E.lib[i] end)
    end
end

-- the search belongs to one screen; leaving it clears the filter
local function syncSearch()
    if SEARCH.screen ~= UI.screen then
        SEARCH.screen, SEARCH.text, SEARCH.active = UI.screen, "", false
    end
end

-- keep the cursor on a row that is still visible after the filter changed
local function snapCursor()
    local map = currentMap()
    if not map or #map == 0 then return end
    local cur = (UI.screen == "edit") and E.cursor or UI.cursor
    for _, real in ipairs(map) do
        if real == cur then return end
    end
    if UI.screen == "edit" then E.cursor = map[1] else UI.cursor = map[1] end
end

local function stepIn(map, cur, d, count)
    if not map then return clamp(cur + d, 1, math.max(1, count)) end
    if #map == 0 then return cur end
    local pos = 1
    for i, real in ipairs(map) do
        if real == cur then pos = i break end
    end
    return map[clamp(pos + d, 1, #map)]
end

return {
    currentMap = currentMap,
    snapCursor = snapCursor,
    stepIn = stepIn,
    syncSearch = syncSearch,
}

-- lib/queue.lua : play order, shuffle, next/prev
local _state = require("lib.state")
local Q = _state.Q
local _util = require("lib.util")
local shuffle = _util.shuffle

local REPEAT = { "off", "all", "one" }

local function buildOrder(keepCurrent)
    local cur = Q.order[Q.pos]
    Q.order = {}
    for i = 1, #Q.tracks do Q.order[i] = i end
    if Q.shuffle then shuffle(Q.order) end
    Q.pos = 1
    if keepCurrent and cur then
        if Q.shuffle then
            for i, v in ipairs(Q.order) do
                if v == cur then table.remove(Q.order, i) break end
            end
            table.insert(Q.order, 1, cur) -- current track goes first, pos stays 1
        else
            Q.pos = cur -- natural order: index == track index
        end
    end
end

local function currentFile() return Q.tracks[Q.order[Q.pos]] end

-- moves Q.pos; auto=true means "track ended by itself". false = nowhere to go
local function advance(dir, auto)
    if #Q.order == 0 then return false end
    if auto and Q.repeatMode == 3 then return true end
    local p = Q.pos + dir
    if p > #Q.order then
        if auto and Q.repeatMode ~= 2 then return false end
        if Q.shuffle then buildOrder(false) end
        p = 1
    elseif p < 1 then
        p = #Q.order
    end
    Q.pos = p
    return true
end

return {
    REPEAT = REPEAT,
    advance = advance,
    buildOrder = buildOrder,
    currentFile = currentFile,
}

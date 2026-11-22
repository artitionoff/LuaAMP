-- lib/ui.lua : drawing: widgets and all screens
local _visual = require("lib.visual")
local visualDraw = _visual.draw
local _cover = require("lib.cover")
local coverDraw, coverFit, coverDrawAt, SLOTS = _cover.draw, _cover.fitSize, _cover.drawAt, _cover.SLOTS
local _config = require("lib.config")
local MUSIC_DIR = _config.MUSIC_DIR
local _state = require("lib.state")
local E, L, N, Q, S, SEARCH, UI, VIEW = _state.E, _state.L, _state.N, _state.Q, _state.S, _state.SEARCH, _state.UI, _state.VIEW
local _lists = require("lib.lists")
local tickIndex = _lists.tickIndex
local _meta = require("lib.meta")
local getMeta, trackLabel = _meta.getMeta, _meta.trackLabel
local _playback = require("lib.playback")
local elapsed = _playback.elapsed
local _queue = require("lib.queue")
local REPEAT, currentFile = _queue.REPEAT, _queue.currentFile
local _theme = require("lib.theme")
local C, THEME, PRESETS = _theme.C, _theme.THEME, _theme.PRESETS
local _util = require("lib.util")
local clamp, fit, marquee, mmss = _util.clamp, _util.fit, _util.marquee, _util.mmss

-- label of the button that switches to the next view (long, medium, short)
local NEXT_LABEL = {
    list = { "Vis", "Vis", "Vis" },
    vis = { "Cover", "Cvr", "Cvr" },
    cover = { "List", "Lst", "Lst" },
}

-- t.ox (optional) shifts everything to the right: used for the list beside a cover
local function put(t, x, y, s, fg, bg)
    if y < 1 or y > t.h or x > t.w or #s == 0 then return end
    local win = t.win
    win.setCursorPos(x + (t.ox or 0), y)
    win.setTextColor(fg or C.text)
    win.setBackgroundColor(bg or C.bg)
    win.write(s)
end

local function hit(t, x1, x2, y, action, arg)
    local ox = t.ox or 0
    t.hits[#t.hits + 1] = { x1 = x1 + ox, x2 = x2 + ox, y = y, action = action, arg = arg }
end

-- progress bar built from vertical half-block characters (char 149)
local function drawBar(t, x, y, w, frac)
    if w <= 0 then return end
    frac = clamp(frac, 0, 1)
    local filled = math.floor(frac * w + 0.5)
    if filled > 0 then put(t, x, y, string.rep("\149", filled), C.accent, C.bg) end
    if filled < w then put(t, x + filled, y, string.rep("\149", w - filled), C.track, C.bg) end
end

-- row of buttons. item = { action=, arg=, style="btn"|"on"|"primary"|"text", labels={long, mid, short} }
-- picks the longest label set that fits; centered; every button is a click target
local function buttonRow(t, y, items)
    local w = t.w
    local nv = #items[1].labels
    local function width(v, pad)
        local total = #items - 1
        for _, it in ipairs(items) do
            total = total + #it.labels[v] + ((it.style == "text") and 0 or 2 * pad)
        end
        return total
    end
    local v, pad = nil, 1
    for i = 1, nv do
        if width(i, 1) <= w then v = i break end
    end
    if not v then v, pad = nv, 0 end
    local x = math.max(1, math.floor((w - width(v, pad)) / 2) + 1)
    for _, it in ipairs(items) do
        local label = it.labels[v]
        if it.style == "text" then
            put(t, x, y, label, C.dim, C.bg)
            x = x + #label + 1
        else
            local fg, bg = C.text, C.panel
            if it.style == "on" then fg, bg = C.text, C.sel
            elseif it.style == "primary" then fg, bg = C.onAccent, C.accent end
            local s = string.rep(" ", pad) .. label .. string.rep(" ", pad)
            put(t, x, y, s, fg, bg)
            hit(t, x, x + #s - 1, y, it.action, it.arg)
            x = x + #s + 1
        end
    end
end

-- buttons = { {label, action}, ... }, drawn from the right edge
local function drawHeader(t, title, buttons, fg)
    put(t, 1, 1, string.rep(" ", t.w), C.text, C.panel)
    local x = t.w + 1
    for i = #(buttons or {}), 1, -1 do
        local s = " " .. buttons[i][1] .. " "
        x = x - #s
        put(t, x, 1, s, C.text, C.sel)
        hit(t, x, x + #s - 1, 1, buttons[i][2])
        x = x - 1
    end
    put(t, 2, 1, marquee(title, x - 2), fg or C.accent, C.panel)
end

local function searchOn() return SEARCH.active or SEARCH.text ~= "" end

-- replaces the header while a search is active or a filter is set
local function drawSearchBar(t)
    put(t, 1, 1, string.rep(" ", t.w), C.text, C.panel)
    local btn = (t.w >= 20) and " Clear " or " x "
    local x = t.w - #btn + 1
    local shown = "/" .. SEARCH.text .. (SEARCH.active and "_" or "")
    local room = x - 3
    if #shown > room then shown = shown:sub(-room) end
    put(t, 2, 1, shown, SEARCH.active and C.accent or C.text, C.panel)
    hit(t, 1, x - 1, 1, "find") -- click the bar to type again
    put(t, x, 1, btn, C.text, C.sel)
    hit(t, x, t.w, 1, "fclear")
end

-- scrolling list; whole row is clickable.
-- map (optional) = real indices of the rows to show (search filter); cursor is a real index
local function drawRows(t, y1, rows, count, cursor, topKey, label, isMarked, action, noMarker, map)
    if map and #map == 0 then
        put(t, 2, y1 + 1, "no matches", C.dim)
        return
    end
    local n = map and #map or count
    if rows < 1 or n < 1 then return end
    local cpos = cursor
    if map then
        cpos = 1
        for i, real in ipairs(map) do
            if real == cursor then cpos = i break end
        end
    end
    local top = t[topKey]
    if cpos < top then top = cpos end
    if cpos > top + rows - 1 then top = cpos - rows + 1 end
    top = math.max(1, math.min(top, math.max(1, n - rows + 1)))
    t[topKey] = top
    for r = 1, rows do
        local i = top + r - 1
        if i > n then break end
        local real = map and map[i] or i
        local y = y1 + r - 1
        local marked = isMarked(real)
        local s = fit(((not noMarker and marked) and ">" or " ") .. label(real), t.w)
        s = s .. string.rep(" ", t.w - #s)
        put(t, 1, y, s, marked and C.accent or C.text, (real == cursor) and C.sel or C.bg)
        hit(t, 1, t.w, y, action, real)
    end
end

---------------------------------------------------------------- screens
local function controlItems(tiny)
    local playing = S.state == "playing"
    local items = {
        { action = "prev", labels = { "|< Prev", "|<", "|<" } },
        { action = "playpause", style = "primary",
          labels = playing and { "|| Pause", "||", "||" } or { "|> Play ", "|>", "|>" } },
        { action = "next", labels = { "Next >|", ">|", ">|" } },
    }
    if not tiny then
        items[4] = { action = "stop", labels = { "[] Stop", "[]", "[]" } }
    end
    return items
end

local function toggleItems(withStop)
    local rm = REPEAT[Q.repeatMode]
    local rshort = ({ off = "Rp", all = "Ra", one = "R1" })[rm]
    local items = {
        { action = "shuffle", style = Q.shuffle and "on" or "btn",
          labels = { "Shuffle", "Shuf", "Sh" } },
        { action = "repeatm", style = (Q.repeatMode > 1) and "on" or "btn",
          labels = { "Repeat: " .. rm, "Rep:" .. rm, rshort } },
    }
    if withStop then
        items[3] = { action = "stop", labels = { "[] Stop", "[]", "[]" } }
    end
    return items
end

local function volumeItems()
    local vt = ("%.1f"):format(S.volume)
    return {
        { action = "voldown", labels = { "-", "-", "-" } },
        { style = "text", labels = { "Vol " .. vt, "Vol " .. vt, vt } },
        { action = "volup", labels = { "+", "+", "+" } },
    }
end

local function drawPanel(t, y0, tiny, wide, listsRow)
    local y, tw = y0, t.w - 2
    local cur = currentFile()

    local m = cur and getMeta(cur)
    put(t, 2, y, marquee(m and m.title or "-", tw), C.accent); y = y + 1

    if S.msg then
        put(t, 2, y, marquee(S.msg, tw), C.bad)
    elseif m and m.artist then
        local line = m.artist
        if wide and m.album then line = line .. "  |  " .. m.album end
        put(t, 2, y, marquee(line, tw), C.dim)
    else
        put(t, 2, y, fit(("%s  %d/%d"):format(Q.name, Q.pos, #Q.order), tw), C.dim)
    end
    y = y + 1

    local e = elapsed()
    drawBar(t, 2, y, tw, S.dur and (e / S.dur) or 0); y = y + 1

    local right = S.dur and mmss(S.dur) or "?:??"
    put(t, 2, y, mmss(e), C.text)
    put(t, t.w - #right, y, right, C.dim)
    if t.w >= 25 then
        local word = ({ playing = "PLAYING", paused = "PAUSED", stopped = "STOPPED" })[S.state]
        put(t, math.floor((t.w - #word) / 2) + 1, y, word, C.accent)
    end
    y = y + 1

    buttonRow(t, y, controlItems(tiny)); y = y + 1

    if wide then
        local items = toggleItems(false)
        items[#items + 1] = { style = "text", labels = { " ", " ", " " } }
        for _, it in ipairs(volumeItems()) do items[#items + 1] = it end
        buttonRow(t, y, items); y = y + 1
    else
        buttonRow(t, y, toggleItems(tiny)); y = y + 1
        buttonRow(t, y, volumeItems()); y = y + 1
    end

    if listsRow then
        buttonRow(t, y, {
            { action = "lists", labels = { "Playlists", "Lists", "Lst" } },
            { action = "find", labels = { "Find", "Find", "Fnd" } },
            { action = "view", labels = NEXT_LABEL[UI.view] },
        })
    end
end

-- tiny screens in visualizer mode: title, bars, progress, play controls
local function drawMini(t)
    local w, h = t.w, t.h
    local cur = currentFile()
    local m = cur and getMeta(cur)
    put(t, 2, 1, marquee(m and m.title or "-", w - 2), C.accent)
    if UI.view == "cover" then coverDraw(t, 1, 2, w, h - 3) else visualDraw(t, 1, 2, w, h - 3) end
    local e = elapsed()
    drawBar(t, 2, h - 2, w - 2, S.dur and (e / S.dur) or 0)
    buttonRow(t, h - 1, controlItems(true))
    buttonRow(t, h, { { action = "view", labels = NEXT_LABEL[UI.view] } })
end

local function drawPlayer(t)
    local w, h = t.w, t.h
    local tiny, wide = w < 20, w >= 40
    local panelRows = wide and 6 or 7
    local listRows = h - panelRows
    local showList = listRows >= 4
    local y0
    local vis = UI.view == "vis" and not searchOn()
    local cover = UI.view == "cover" and not searchOn()

    if not showList and (vis or cover) then
        drawMini(t)
        return
    end

    if not showList and searchOn() then
        drawSearchBar(t)
        drawRows(t, 2, h - 1, #Q.order, UI.cursor, "top",
            function(i) return ("%2d %s"):format(i, trackLabel(Q.tracks[Q.order[i]])) end,
            function(i) return i == Q.pos end, "pick", nil, VIEW.map)
        return
    end

    if showList then
        y0 = listRows + 1
        if searchOn() then
            drawSearchBar(t)
        else
            drawHeader(t, ("%s  %d/%d"):format(Q.name, Q.pos, #Q.order),
                { { NEXT_LABEL[UI.view][1], "view" }, { "Find", "find" }, { "Lists", "lists" } })
        end
        if vis then
            visualDraw(t, 1, 2, w, listRows)
        elseif cover then
            coverDraw(t, 1, 2, w, listRows)
        elseif #Q.order == 0 then
            put(t, 2, 3, fit("No tracks in /" .. MUSIC_DIR, w - 2), C.dim)
        else
            -- a small cover on the left when there is room; the list gets the rest
            local lt = t
            local sz = coverFit(listRows - 1, w - 20)
            if sz then
                coverDrawAt(t, 2, 2, sz)
                lt = setmetatable({ ox = sz.cw + 2, w = w - sz.cw - 2 }, { __index = t, __newindex = t })
            end
            drawRows(lt, 2, listRows - 1, #Q.order, UI.cursor, "top",
                function(i) return ("%2d %s"):format(i, trackLabel(Q.tracks[Q.order[i]])) end,
                function(i) return i == Q.pos end, "pick", nil, VIEW.map)
        end
    else
        panelRows = panelRows + 1
        y0 = math.max(1, math.floor((h - panelRows) / 2) + 1)
    end
    drawPanel(t, y0, tiny, wide, not showList)
end

local function drawLists(t)
    local w, h = t.w, t.h
    drawHeader(t, L.msg or "Playlists", { { "Theme", "theme" } })
    drawRows(t, 2, h - 2, #L.items, L.cursor, "ltop",
        function(i) return L.items[i] end,
        function(i) return L.items[i] == Q.name end, "lpick")
    buttonRow(t, h, {
        { action = "lback", labels = { "Back", "Back", "<" } },
        { action = "lnew", labels = { "New", "New", "+" } },
        { action = "ledit", labels = { "Edit", "Edit", "E" } },
        { action = "ldel", labels = { "Delete", "Del", "X" } },
    })
end

local function drawEdit(t)
    local w, h = t.w, t.h
    if searchOn() then
        drawSearchBar(t)
    else
        drawHeader(t, E.msg or ("Edit: " .. E.name), nil, E.msg and C.bad or C.accent)
    end
    if #E.lib == 0 then
        put(t, 2, 3, fit("No tracks in /" .. MUSIC_DIR, w - 2), C.dim)
    else
        drawRows(t, 2, h - 2, #E.lib, E.cursor, "etop",
            function(i)
                local p = tickIndex(E.lib[i])
                return (p and ("[x]" .. p .. " ") or "[ ] ") .. trackLabel(E.lib[i])
            end,
            function(i) return tickIndex(E.lib[i]) ~= nil end, "etoggle", true, VIEW.map)
    end
    buttonRow(t, h, {
        { action = "esave", style = "primary", labels = { "Save", "Save", "OK" } },
        { action = "ecancel", labels = { "Cancel", "Cancel", "X" } },
        { action = "find", labels = { "Find", "Find", "/" } },
    })
end

local function drawName(t)
    local w, h = t.w, t.h
    drawHeader(t, "New playlist")
    put(t, 2, 3, "Name:", C.dim)
    local shown = N.text .. "_"
    if #shown > w - 2 then shown = shown:sub(-(w - 2)) end
    put(t, 2, 4, shown .. string.rep(" ", (w - 2) - #shown), C.text, C.panel)
    if N.msg then
        put(t, 2, 6, fit(N.msg, w - 2), C.bad)
    else
        put(t, 2, 6, fit("type a name, ENTER = next", w - 2), C.dim)
        put(t, 2, 7, fit("empty + ENTER = cancel", w - 2), C.dim)
    end
    buttonRow(t, h, {
        { action = "nnext", style = "primary", labels = { "Next", "Next", "OK" } },
        { action = "ncancel", labels = { "Cancel", "Cancel", "X" } },
    })
end

-- theme screen: dark/light buttons and accent swatches (they use the cover palette slots)
local function drawTheme(t)
    local w, h = t.w, t.h
    drawHeader(t, "Theme")
    local roomy = h >= 12
    local y = 3
    if roomy then put(t, 2, y, "Mode", C.dim); y = y + 1 end
    buttonRow(t, y, {
        { action = "tmode", arg = "dark", style = (THEME.mode == "dark") and "on" or "btn",
          labels = { "Dark", "Dark", "D" } },
        { action = "tmode", arg = "light", style = (THEME.mode == "light") and "on" or "btn",
          labels = { "Light", "Light", "L" } },
    })
    y = y + 2
    if roomy then put(t, 2, y, "Accent", C.dim); y = y + 1 end

    local sw = (w >= 30) and 3 or 2
    local per = math.max(1, math.floor((w - 1) / (sw + 1)))
    local mark = (THEME.mode == "dark") and C.bg or C.text -- the dark one of the two
    for i = 1, #PRESETS do
        local x = 2 + ((i - 1) % per) * (sw + 1)
        local yy = y + math.floor((i - 1) / per)
        local picked = PRESETS[i] == THEME.accent
        local label = picked and ((sw == 3) and " * " or "* ") or string.rep(" ", sw)
        put(t, x, yy, label, mark, SLOTS[i])
        hit(t, x, x + sw - 1, yy, "taccent", i)
    end

    if w >= 30 and h >= 10 then
        put(t, 2, h - 1, fit("left/right accent   up/down mode", w - 2), C.dim)
    end
    buttonRow(t, h, { { action = "tback", labels = { "Back", "Back", "<" } } })
end

return {
    drawEdit = drawEdit,
    drawLists = drawLists,
    drawName = drawName,
    drawPlayer = drawPlayer,
    drawTheme = drawTheme,
}

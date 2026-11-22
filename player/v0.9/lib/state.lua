-- lib/state.lua : tables shared between modules (they are changed in place, never replaced)
local cfg = require("lib.config")

local state = {}

-- queue: tracks = file names, order = play order (indices into tracks), pos = index into order
state.Q = { tracks = {}, order = {}, pos = 1, shuffle = false, repeatMode = 1, name = "" }

-- playback: state = "stopped" | "playing" | "paused"
state.S = { state = "stopped", volume = cfg.START_VOLUME, kind = "wav", dur = nil, raw = nil, wav = nil,
            ogg = nil, path = nil, base = 0, startedAt = 0, timer = nil, volTimer = nil,
            tick = nil, nextTimer = nil, nextSeg = nil, nextAt = nil, msg = nil, msgUntil = nil }

-- screen: "player" | "lists" | "edit" | "name";  view: "list" | "vis" | "cover"
state.UI = { screen = "player", cursor = 1, quit = false, view = "list", themeFrom = "player" }

-- playlists screen
state.L = { items = { "Whole library" }, names = {}, cursor = 1, msg = nil, confirm = nil }

-- playlist editor and name input
state.E = { name = "", order = {}, lib = {}, cursor = 1, msg = nil }
state.N = { text = "", msg = nil }

-- search (player queue + playlist editor); VIEW.map = indices of the matching rows, set by render()
state.SEARCH = { active = false, text = "", screen = "player" }
state.VIEW = { map = nil }

return state

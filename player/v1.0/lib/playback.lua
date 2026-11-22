-- lib/playback.lua : speaker control: play, pause, resume, WAV parts, timers
local _config = require("lib.config")
local VIS_TICK = _config.VIS_TICK or 0.15
local CHUNK_BYTES, CHUNK_DEBUG, CHUNK_LEAD, GAP, MAX_SEND, MUSIC_DIR, OGG_RESUME, TICK, VOL_MAX, VOL_MIN = _config.CHUNK_BYTES, _config.CHUNK_DEBUG, _config.CHUNK_LEAD, _config.GAP, _config.MAX_SEND, _config.MUSIC_DIR, _config.OGG_RESUME, _config.TICK, _config.VOL_MAX, _config.VOL_MIN
local spk = require("lib.speaker")
local _state = require("lib.state")
local Q, S, UI = _state.Q, _state.S, _state.UI
local _audio = require("lib.audio")
local oggFrom, parseOgg, parseWav, wavSeg = _audio.oggFrom, _audio.parseOgg, _audio.parseWav, _audio.wavSeg
local _queue = require("lib.queue")
local advance, currentFile = _queue.advance, _queue.currentFile
local _util = require("lib.util")
local clamp = _util.clamp
local _visual = require("lib.visual")
local visualLoad = _visual.load
local _cover = require("lib.cover")
local coverLoad = _cover.load
local _eq = require("lib.eq")
local eqActive, eqSegment, eqStartJob, eqStepJob, eqFinish = _eq.active, _eq.segment, _eq.startJob, _eq.stepJob, _eq.finish

-- state: "stopped" | "playing" | "paused"

local function rawElapsed()
    if S.state == "playing" then return S.base + (os.clock() - S.startedAt) end
    if S.state == "paused" then return S.base end
    return 0
end

local function elapsed()
    local e = rawElapsed()
    if S.dur and e > S.dur then e = S.dur end
    return e
end

local function cancelTimer(name)
    if S[name] then os.cancelTimer(S[name]) S[name] = nil end
end

-- (Re)start the UI refresh timer. Speaker calls can block the program for a moment and
-- CC drops events that arrive meanwhile, so the tick is re-armed after every event
-- instead of relying on one endless timer chain.
local function armTick()
    cancelTimer("tick")
    -- refresh faster while the bars are on screen
    S.tick = os.startTimer((UI.view == "vis" and S.state == "playing") and VIS_TICK or TICK)
end

-- status line message; secs = nil keeps it until the next track
local function setMsg(text, secs)
    S.msg = text
    S.msgUntil = (text and secs) and (os.clock() + secs) or nil
end

local function expireMsg()
    if S.msg and S.msgUntil and os.clock() > S.msgUntil then
        S.msg, S.msgUntil = nil, nil
    end
end

local function stop()
    pcall(spk.speakStop)
    S.state, S.base = "stopped", 0
    cancelTimer("timer"); cancelTimer("volTimer"); cancelTimer("nextTimer")
    S.raw, S.wav, S.ogg, S.nextSeg, S.nextAt, S.job = nil, nil, nil, nil, nil, nil
end

-- one speaker call for every piece of audio
local function speakData(data)
    if S.kind == "ogg" then spk.speakOgg(data, S.volume)
    else spk.speakWav(data, S.volume) end
end

-- a piece of audio has just been sent: set the clock and prepare the next piece
local function onSegmentStarted(startSec, lastByte, eqState)
    S.state, S.base, S.startedAt = "playing", startSec, os.clock()
    cancelTimer("timer"); cancelTimer("nextTimer")
    S.nextSeg, S.nextAt, S.job = nil, nil, nil
    if S.dur then
        S.timer = os.startTimer(math.max(0.1, S.dur - startSec + GAP))
    end
    local w = S.wav
    if w and lastByte and lastByte < w.dataLen then
        if eqActive(w) then
            -- equalized: the next part is processed in small steps between events (see eqWork)
            local job = eqStartJob(S.path, w, lastByte, false, eqState)
            if job then
                S.job = job
                S.nextAt = lastByte / w.byteRate - CHUNK_LEAD
                S.nextTimer = os.startTimer(math.max(0.05, S.nextAt - startSec))
                os.queueEvent("eq_work")
            else
                setMsg("cannot read next part of the file")
            end
        else
            -- long WAV: read and build the next part now, send it when this one is over
            local d, sb, lb = wavSeg(S.path, w, lastByte)
            if d then
                S.nextSeg = { data = d, startByte = sb, lastByte = lb }
                S.nextAt = lastByte / w.byteRate - CHUNK_LEAD
                S.nextTimer = os.startTimer(math.max(0.05, S.nextAt - startSec))
            else
                setMsg("cannot read next part of the file")
            end
        end
    end
end

-- one slice of the background equalizing job; called for every "eq_work" event
local function eqWork()
    local job = S.job
    if not job then return end
    if S.state ~= "playing" then S.job = nil return end
    if eqStepJob(job, 40) then
        S.job = nil
        local d, sb, lb, st = eqFinish(job)
        S.nextSeg = { data = d, startByte = sb, lastByte = lb, eqState = st }
    else
        os.queueEvent("eq_work")
    end
end

-- the current part is over: send the next one
local function nextChunk()
    if S.job then -- the next part is still being equalized: try again in a moment
        if S.state == "playing" then S.nextTimer = os.startTimer(0.05) end
        return
    end
    local seg, dueAt = S.nextSeg, S.nextAt
    S.nextSeg, S.nextAt = nil, nil
    if not seg or S.state ~= "playing" or not S.wav then return end
    local late = rawElapsed() - dueAt -- how late the timer fired
    local t0 = os.clock()
    local ok, err = pcall(speakData, seg.data)
    local took = os.clock() - t0       -- how long the speaker call blocked
    seg.data = nil
    if not ok then setMsg(tostring(err)) stop() return end
    onSegmentStarted(seg.startByte / S.wav.byteRate, seg.lastByte, seg.eqState)
    if CHUNK_DEBUG and seg.eqState then
        setMsg(("eq part  late %.2fs  call %.2fs"):format(late, took), 8)
    elseif CHUNK_DEBUG then
        local w = S.wav
        setMsg(("part %d/%d  late %.2fs  call %.2fs"):format(
            math.floor(seg.startByte / w.chunk) + 1, math.ceil(w.dataLen / w.chunk),
            late, took), 8)
    end
end

-- start (or restart) audio of the loaded track from `sec`
local function playFrom(sec)
    if not (S.raw or S.wav) then return false end
    pcall(spk.speakStop)

    local function fail(text)
        setMsg(text)
        cancelTimer("timer"); cancelTimer("nextTimer")
        S.state, S.base = "stopped", 0
        S.raw, S.wav, S.ogg, S.nextSeg, S.nextAt, S.job = nil, nil, nil, nil, nil, nil
        return false
    end

    -- returns data, start time, last byte of this piece (wav), "cut" flag
    local function build(at)
        if S.wav then
            local w = S.wav
            local startByte = math.floor(at * w.byteRate / w.blockAlign) * w.blockAlign
            if eqActive(w) then
                local d, sb, lb, st = eqSegment(S.path, w, startByte, true, nil)
                if not d then return nil end
                return d, sb / w.byteRate, lb, at > 0, st
            end
            local d, sb, lb = wavSeg(S.path, w, startByte)
            if not d then return nil end
            return d, sb / w.byteRate, lb, at > 0
        end
        if at > 0 and S.kind == "ogg" and S.ogg and OGG_RESUME then
            local d, s0 = oggFrom(S.raw, S.ogg, at)
            if d then return d, s0, nil, true end
        end
        if at > 0 then setMsg("can't resume: restarted", 5) end
        return S.raw, 0, nil, false
    end

    local data, startSec, lastByte, cut, eqState = build(sec)
    if not data then return fail("cannot read file") end
    local ok, err = pcall(speakData, data)
    if not ok and cut then
        -- resumed data was rejected: start the whole track from the beginning instead
        setMsg("resume failed: restarted", 5)
        local _
        data, startSec, lastByte, _, eqState = build(0)
        if not data then return fail("cannot read file") end
        ok, err = pcall(speakData, data)
    end
    data = nil
    if not ok then return fail(tostring(err)) end

    onSegmentStarted(startSec, lastByte, eqState)
    if not S.dur and not S.msg then setMsg("unknown length: no auto-next", 5) end
    return true
end

local function startTrack()
    stop()
    local file = currentFile()
    if not file then return false end
    setMsg(nil)
    local path = fs.combine(MUSIC_DIR, file)
    S.kind = file:match("%.ogg$") and "ogg" or "wav"
    S.path, S.dur = path, nil

    if not fs.exists(path) then setMsg("file not found") return false end
    local size = fs.getSize(path)
    local f = fs.open(path, "rb")
    if not f then setMsg("cannot open file") return false end

    if S.kind == "wav" then
        local head = f.read(math.min(size, 65536)) or ""
        f.close()
        S.wav = parseWav(head, size)
        if S.wav then
            -- long files are played in parts of at most CHUNK_BYTES
            local w = S.wav
            local chunk = math.min(CHUNK_BYTES, MAX_SEND - 4096)
            w.chunk = math.max(w.blockAlign, chunk - chunk % w.blockAlign)
            S.dur = w.dataLen / w.byteRate
        elseif size <= MAX_SEND then
            local f2 = fs.open(path, "rb")
            S.raw = f2.readAll()
            f2.close()
        else
            setMsg("unsupported wav header (too big to send whole)")
            return false
        end
    else
        S.raw = f.readAll()
        f.close()
        local ok, o = pcall(parseOgg, S.raw)
        S.ogg = ok and o or nil
        S.dur = S.ogg and S.ogg.dur or nil
    end
    visualLoad()
    coverLoad()
    return playFrom(0)
end

-- step to next/prev track and play it; skips broken files
local function go(dir, auto)
    for _ = 1, #Q.order do
        if not advance(dir, auto) then stop() return end
        UI.cursor = Q.pos
        if startTrack() then return end
        auto = false
    end
    stop()
end

local function togglePause()
    if S.state == "playing" then
        S.base = rawElapsed()
        pcall(spk.speakStop)
        S.state = "paused"
        cancelTimer("timer"); cancelTimer("volTimer"); cancelTimer("nextTimer")
        S.nextSeg, S.nextAt, S.job = nil, nil, nil
    elseif S.state == "paused" then
        if not playFrom(S.base) then go(1, false) end
    else
        if #Q.order == 0 then return end
        if not startTrack() then go(1, false) end
    end
end

-- WAV can be restarted from the same spot shortly after volume / equalizer changes (debounced)
local function restartSoon()
    if S.state == "playing" and S.kind == "wav" and S.wav then
        cancelTimer("volTimer")
        S.volTimer = os.startTimer(0.4)
    end
end

local function setVolume(v)
    S.volume = clamp(math.floor(v * 100 + 0.5) / 100, VOL_MIN, VOL_MAX) -- no 0.30000000000000004
    restartSoon()
end

return {
    armTick = armTick,
    elapsed = elapsed,
    eqWork = eqWork,
    expireMsg = expireMsg,
    go = go,
    nextChunk = nextChunk,
    playFrom = playFrom,
    rawElapsed = rawElapsed,
    restartSoon = restartSoon,
    setVolume = setVolume,
    startTrack = startTrack,
    stop = stop,
    togglePause = togglePause,
}

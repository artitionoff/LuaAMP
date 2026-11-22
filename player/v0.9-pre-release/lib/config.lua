-- lib/config.lua : YOUR SETTINGS. Player updates never need to touch this file.
return {
    SPEAKER_ID    = 10,               -- cee.getPeripheral(<this number>)
    MUSIC_DIR     = "mem/music",      -- tracks (.wav / .ogg)
    LIST_DIR      = "mem2/playlists", -- playlists and the tag cache (must be writable)

    USE_TERMINAL  = true,             -- also draw on the computer's own screen
    MONITOR_SCALE = nil,              -- nil = auto (1, or 0.5 for tiny monitors); or 0.5 / 1 / 1.5 ...

    START_VOLUME  = 0.5,
    VOL_STEP      = 0.1,
    VOL_MIN       = 0,
    VOL_MAX       = 1,

    GAP           = 0.5,              -- extra seconds after a track before auto-next
    TICK          = 0.5,              -- UI refresh period
    VIS_TICK      = 0.05,             -- refresh period while the visualizer is on screen
    VIS_OFFSET    = -2,                -- seconds: shift the bars ahead (+) or behind (-) the sound

    MAX_SEND      = 8388608,          -- speaker limit for one speakWav/speakOgg call (bytes)
    CHUNK_BYTES   = 8000000,          -- long WAVs are sent in parts of at most this many bytes
    CHUNK_LEAD    = 0,                -- seconds before the end of a part when the next one is sent;
                                      -- 0 = right at the end (the speaker REPLACES a playing sound)
    CHUNK_DEBUG   = true,             -- show "part N  late X s  call Y s" on every join

    OGG_RESUME    = true,             -- experimental: real pause/resume for .ogg (cuts the file at a
                                      -- page boundary). false = ogg resumes from the start
}

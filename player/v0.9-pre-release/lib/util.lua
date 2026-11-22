-- lib/util.lua : small helpers


local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    if not d then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function le32s(n)
    return string.char(n % 256, math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function mmss(s)
    s = math.floor(s or 0)
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function fit(s, w)
    if w <= 0 then return "" end
    if #s <= w then return s end
    if w <= 2 then return s:sub(1, w) end
    return s:sub(1, w - 2) .. ".."
end

local function marquee(s, w)
    if w <= 0 then return "" end
    if #s <= w then return s end
    local pad = s .. "   "
    local off = math.floor(os.clock() * 3) % #pad
    return (pad .. pad):sub(off + 1, off + w)
end

return {
    clamp = clamp,
    fit = fit,
    le32s = le32s,
    marquee = marquee,
    mmss = mmss,
    shuffle = shuffle,
    u32 = u32,
}

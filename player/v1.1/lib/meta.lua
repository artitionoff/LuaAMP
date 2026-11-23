-- lib/meta.lua : track tags, file-name fallback, Latin-only text, tag cache
local _config = require("lib.config")
local LIST_DIR, MUSIC_DIR = _config.LIST_DIR, _config.MUSIC_DIR
local _util = require("lib.util")
local u32 = _util.u32

-- Title / artist / album come from the file tags (Ogg Vorbis comments, WAV LIST-INFO),
-- else from the file name ("Artist - Title.ogg"). Text is converted to what the CC font
-- can draw (Cyrillic is transliterated). Results are cached in meta.cache.
local META_FILE, META_VER = fs.combine(LIST_DIR, "meta.cache"), 1
local META = { files = {}, dirty = false }

local TR = {}
do
    local pairsList = {
        "а","a","б","b","в","v","г","g","д","d","е","e","ё","yo","ж","zh","з","z","и","i",
        "й","y","к","k","л","l","м","m","н","n","о","o","п","p","р","r","с","s","т","t",
        "у","u","ф","f","х","kh","ц","ts","ч","ch","ш","sh","щ","shch","ъ","","ы","y",
        "ь","","э","e","ю","yu","я","ya","і","i","ї","yi","є","ye","ґ","g",
        "А","A","Б","B","В","V","Г","G","Д","D","Е","E","Ё","Yo","Ж","Zh","З","Z","И","I",
        "Й","Y","К","K","Л","L","М","M","Н","N","О","O","П","P","Р","R","С","S","Т","T",
        "У","U","Ф","F","Х","Kh","Ц","Ts","Ч","Ch","Ш","Sh","Щ","Shch","Ъ","","Ы","Y",
        "Ь","","Э","E","Ю","Yu","Я","Ya","І","I","Ї","Yi","Є","Ye","Ґ","G",
        "‘","'","’","'","“",'"',"”",'"',"–","-","—","-","…","...","№","No",
    }
    for i = 1, #pairsList, 2 do TR[pairsList[i]] = pairsList[i + 1] end
end

-- UTF-8 text -> text the CC terminal can show
local function latin(s)
    s = s:gsub("%c", "")
    s = s:gsub("[\194-\244][\128-\191]*", function(ch)
        local r = TR[ch]
        if r then return r end
        if #ch == 2 then
            local cp = (ch:byte(1) - 192) * 64 + (ch:byte(2) - 128)
            if cp >= 160 and cp <= 255 then return string.char(cp) end -- Latin-1 letters
        end
        return "?"
    end)
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

-- Ogg Vorbis comments: the comment header is the 2nd packet, it may span several pages
local function oggTags(head)
    local bodies, pos, n = {}, 1, #head
    while pos + 26 <= n and head:sub(pos, pos + 3) == "OggS" do
        local nseg = head:byte(pos + 26)
        local size = 0
        for i = 1, nseg do size = size + (head:byte(pos + 26 + i) or 0) end
        local b0 = pos + 27 + nseg
        bodies[#bodies + 1] = head:sub(b0, b0 + size - 1)
        pos = b0 + size
        if #bodies >= 8 then break end
    end
    local data = table.concat(bodies)
    local p = data:find("\3vorbis", 1, true)
    if not p then return nil end
    local i = p + 7
    local vlen = u32(data, i)
    if not vlen then return nil end
    i = i + 4 + vlen
    local count = u32(data, i)
    if not count then return nil end
    i = i + 4
    local tags = {}
    for _ = 1, math.min(count, 100) do
        local len = u32(data, i)
        if not len or i + 3 + len > #data then break end
        if len <= 4096 then -- big entries (cover art) are skipped
            local k, v = data:sub(i + 4, i + 3 + len):match("^([^=]+)=(.*)$")
            if k then tags[k:upper()] = v end
        end
        i = i + 4 + len
    end
    return tags
end

-- WAV: LIST/INFO chunk (INAM title, IART artist, IPRD album); only if it is near the start
local function wavTags(head)
    if head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WAVE" then return nil end
    local names = { INAM = "TITLE", IART = "ARTIST", IPRD = "ALBUM" }
    local pos = 13
    while pos + 7 <= #head do
        local id, len = head:sub(pos, pos + 3), u32(head, pos + 4)
        if id == "LIST" and head:sub(pos + 8, pos + 11) == "INFO" then
            local tags, p, e = {}, pos + 12, math.min(#head, pos + 7 + len)
            while p + 7 <= e do
                local sid, slen = head:sub(p, p + 3), u32(head, p + 4)
                local v = head:sub(p + 8, p + 7 + slen)
                local z = v:find("\0", 1, true)
                if z then v = v:sub(1, z - 1) end
                if names[sid] then tags[names[sid]] = v end
                p = p + 8 + slen + (slen % 2)
            end
            return tags
        end
        pos = pos + 8 + len + (len % 2)
    end
    return nil
end

-- "01 - Artist - Title.ogg" -> artist, title  (artist is nil if there is no " - ")
local function nameParts(file)
    local n = file:gsub("%.%w+$", "")
    n = n:gsub("_", " ")
    n = n:gsub("^%d+%s*[%.%-]%s*", "")
    local a, t = n:match("^(.-)%s+%-%s+(.+)$")
    if a and a ~= "" and t ~= "" then return a, t end
    return nil, n
end

local function clean(v)
    if not v then return nil end
    v = latin(v)
    if v == "" then return nil end
    return v
end

local function readMeta(file)
    local path = fs.combine(MUSIC_DIR, file)
    local raw = {}
    local okSize, size = pcall(fs.getSize, path)
    pcall(function()
        local f = fs.open(path, "rb")
        if not f then return end
        local head = f.read(65536)
        f.close()
        if not head then return end
        local tags
        if file:match("%.ogg$") then tags = oggTags(head) else tags = wavTags(head) end
        if tags then
            raw.title = tags.TITLE
            raw.artist = tags.ARTIST or tags.PERFORMER or tags.ALBUMARTIST
            raw.album = tags.ALBUM
        end
    end)
    local fnArtist, fnTitle = nameParts(file)
    return {
        size = okSize and size or 0,
        title = clean(raw.title) or clean(fnTitle) or file,
        artist = clean(raw.artist) or clean(fnArtist),
        album = clean(raw.album),
    }
end

local function loadMeta()
    if not fs.exists(META_FILE) then return end
    local f = fs.open(META_FILE, "r")
    if not f then return end
    local t = textutils.unserialize(f.readAll())
    f.close()
    if type(t) == "table" and t.v == META_VER and type(t.files) == "table" then
        META.files = t.files
    end
end

local function saveMeta()
    if not META.dirty then return end
    local f = fs.open(META_FILE, "w") -- may fail when the disk is full: the cache is optional
    if not f then return end
    pcall(f.write, textutils.serialize({ v = META_VER, files = META.files }))
    pcall(f.close)
    META.dirty = false
end

local function getMeta(file)
    local m = META.files[file]
    if not m then
        m = readMeta(file)
        META.files[file] = m
        META.dirty = true
    end
    return m
end

-- read tags of new / changed files; drops cache entries of deleted files
local function scanMeta(list)
    local present = {}
    for _, file in ipairs(list) do
        present[file] = true
        local m = META.files[file]
        local ok, size = pcall(fs.getSize, fs.combine(MUSIC_DIR, file))
        if not m or (ok and m.size ~= size) then
            META.files[file] = readMeta(file)
            META.dirty = true
        end
    end
    for file in pairs(META.files) do
        if not present[file] then META.files[file] = nil; META.dirty = true end
    end
    saveMeta()
end

-- "Artist - Title" (or just the title) for lists
local function trackLabel(file)
    local m = getMeta(file)
    if m.artist then return m.artist .. " - " .. m.title end
    return m.title
end

return {
    getMeta = getMeta,
    loadMeta = loadMeta,
    saveMeta = saveMeta,
    scanMeta = scanMeta,
    trackLabel = trackLabel,
}

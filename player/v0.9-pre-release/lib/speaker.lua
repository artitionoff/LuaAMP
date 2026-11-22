-- lib/speaker.lua : the speaker peripheral
local cfg = require("lib.config")
local spk = cee.getPeripheral(cfg.SPEAKER_ID)
if not spk then error("speaker not found (check SPEAKER_ID in lib/config.lua)", 0) end
return spk

# Customizing *config.lua* for your setup.

If you want to connect your speakers to a different pin, change the offset of the visualiser or just mess around with the settings, you can edit *config.lua* in *lib*.

## Speaker ID

**SPEAKER_ID** - the id of your signal pin where the speakers are connected (1-10).

If you have a speaker on the Signal N (whatever number it is) instead of Signal 10, you can simply change this value to N: ***SPEAKER_ID*** *= N*.

## Directories

**MUSIC_DIR** - path to your music folder in CC itself.

**LIST_DIR** - path to your playlists folder.

If you don't want to hold a server for your music and playlists, you can simply change the path to something else. For example, ***MUSIC_DIR*** *= "rom/music"* or ***LIST_DIR*** *= "cee/something/playlists"*. However, be ready to encounter memory limits if you decide to host everything on the computer. It is recommended to atleast hold your music files in a memory module of a server.

## Volume

**START_VOLUME** - the default value of the volume that is used after the start of the program.

The recommended values for this setting are 0.5-1.0 since speaker volume doesn't increase after 1.

**VOL_STEP** - value of the volume step.

Recommended values: 0.05 or 0.1.

**VOL_MIN** - minimum volume value.

Cannot go below 0.

**VOL_MAX** - maximum volume value.

Recommended values: 1 or more.

## Ticks and offsets

**GAP** - number of seconds before the autoplay plays next track.

**TICK** - refresh rate of the UI.

**VIS_TICK** - refresh rate of the UI while using visualizer.

Bigger values - less frames per second on the monitor. Both **TICK** and **VIS_TICK** cannot go below 0.05 (=20 fps).

**VIS_OFFSET** - number of seconds that shift the visualizer bars.

If your visual data isn't synced with the audio, you can change this setting until you find the right latency.

## Parts

**MAX_SEND** - maximum size of a .wav or .ogg file in bytes that can be sent to the speakers as a whole.

The usual value is 8 MB since it's the maximum limit for speakWav/speakOgg. .ogg files with sizes above 8 MB will not work. However, .wav files are sent in parts with 8 MB or less. You may expirience a pause between parts but the output will still be synced with the visualizer.

**CHUNK_BYTES** - maximum size of a part for a .wav file in bytes.

The max valuse is the same as **MAX_SEND** - no more than 8 MB per part.

**CHUNK_LEAD** - number of seconds before the end of the part when the next one is sent to the speaker.

Basically an offset for parts.

**EQ_CHUNK_SEC** - number of seconds that a part can contain while using the audio equalizer.

By default it has a value of 8, the value can be changed by adding a line with this variable in this block. Recommended value: 8-15.

## Other

**CHUNK_DEBUG** - Boolean, shows "part N  late X s  call Y s" during every join between parts.

**OGG_RESUME** - Boolean, adds pause function to .ogg files.

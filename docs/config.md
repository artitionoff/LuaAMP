# Customizing config.lua for your setup.

If you want to connect your speakers to a different pin, change the offset of the visualizer or just mess around with the settings, you can edit *config.lua* in *lib*.

**SPEAKER_ID** - the id of your signal pin where the speakers are connected (1-10)

If you have a speaker on the Signal N (whatever number it is) instead of Signal 10, you can simply change this value to N: ***SPEAKER_ID*** *= N*


**MUSIC_DIR** - path to your music folder in CC itself

**LIST_DIR** - path to your playlists folder

If you don't want to hold a server rig for your music and playlists, you can simply change the path to something else. For example, ***MUSIC_DIR*** *= "rom/music"* or ***LIST_DIR*** *= "cee/something/playlists"*. However, be ready to encounter memory limits if you decide to host everything on the computer.


**START_VOLUME** - the default value of the volume that is used after the start of the program

The recommended values for this setting are 0.5-1.0 since speaker volume doesn't increase after 1.


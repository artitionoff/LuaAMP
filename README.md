# LuaAMP (Lua Advanced Music Player)
**🟩 LuaAMP** is a CC:CE audio player program which gives you the most advanced and immersive experience of your .wav and .ogg music. This program has all kinds of features you need packed in one convenient imterface! 🎶

# Features:

Volume control;

Whole playlist/ one track repeat;

Shuffle;

Track searching;

Playlists — use the Lists button to open a playlists menu. There you can make and edit your own playlists;

Audio visualizer — use the Vis button to open a visualizer. Works with .wav files natively, or you can make an advanced visualiser for .wav and .ogg using makevis.py (see Functions featuring Python;
18 different UI themes — use the Theme button in the Lists menu to switch the light/dark theme or change an accent color. 

# Functions featuring Python:

Advanced audio player — use makevis.py to make .vis files for your tracks. This file makes better visual data for your audiofiles. 

Album covers — use makecov.py to make .cov files, which contains the covers from your tracks obtained from their metadata. Covers will be displayed in the main menu. 

# Experimental features:

Equalizer — use the EQ button in player or playlists menu to open the equalizer menu. You can either choose the built-in presets or set your own values. **It works only with .wav files and parts will be every 8 seconds instead of every 8 MB (~45 seconds). Use this feature on your own risk.**

# Installation and setup:

**Requirements**:

CC:CE PC/Computer module;

Two memory modules (should be recognized as mem and mem2 in the system);

Speaker (should be connected to the 10th pin if you use the PC);

Python with NumPy, Pillow and SoundFile libraries (optional). 

**If you want to customize LuaAMP to your setup, see *config.md* in docs.**

# Installation:

Download thr latest LuaAMP.zip in releases. Download the archive and unpack it on your CC:CE PC. 

Prepare the memory modules. Make a music folder in the mem module and playlists in the mem2 one. 

Add your music. Add your .wav or .ogg audios to the mem/music folder. 

*Tip: use ffmpeg or any DAW (like Audacity or FL Studio) to convert your unsupported files to .wav or .ogg. Use Mp3Tag to add metadata to your converted audios.*

Make covers and visual (optional). Use makevis.py and makecov.py to make covers and visualizers for your tracks. Usage: python makevis.py/makecov.py "<path\to\your\music\folder>" "[more folders\files]" --force
--force rewrites your .vis/.cov files completely, you don't need to use this setting by deafult.

Run LuaAMP. Launch the player on your CC:CE PC using player.lua.

# Documentation

For more detailed information about LuaAMP, its configuration, features, and additional tools, please refer to the docs folder in this repository. If you have any questions, feel free to DM us on Discord (@artition_off or @msi_gtx1050ti) or open an Issue in this repository. Feedback is truly appriciated!

# Project status

LuaAMP is an actively developed project. Some features, including the audio equalizer, are experimental and may change in future updates.

***Contains AI-generated code.***

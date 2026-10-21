# Credits

ReaScratch is free software, released under the GNU General Public License v3.0 or later (see `LICENSE`).

It was made with help from Claude (Anthropic). Every preset marked as untested in the preset menu has not been tried on real hardware yet; reports from owners are welcome.

## Code ported into ReaScratch

- **Saike FM Filter 2 / protosynth** by Joep Vanlier (MIT License) - https://github.com/JoepVanlier/JSFX
  The filter models (Moog, Ladder, Steiner, Pillow, Rect, Shriek4p, MS-20, nlSVF) and the 2x oversampling (`elliptic_2x`) are ported from `Saike_Yutani_filters.jsfx-inc` and protosynth. FM Filter 2's 303 model is not used. The full license text is `Effects/ReaScratch/LICENSE_Saike_filters.txt`, and the details are in the comments of `reascratch.jsfx`.
- **ntsc** by zhuker (Apache License 2.0) - https://github.com/zhuker/ntsc
  The VHS video effect's composite signal (the colour put on the subcarrier and taken out again, the tape's luma and chroma lowpasses, the video and colour noise, the hue wandering line by line, the chroma loss and the edge wave) is ported from `ntsc.py` and rewritten in EEL2 for the REAPER Video processor (`Scripts/ReaScratch/reascratch_deck_mix.eel`, `vh_ntsc`). ntsc itself follows joncampbell123's composite-video-simulator. The full license text is `Effects/ReaScratch/LICENSE_ntsc_zhuker.txt`.
- **libKeyFinder** by Ibrahim Sha'ath, maintained by the Mixxx team (GPL-3.0-or-later, the same license as ReaScratch) - https://github.com/mixxxdj/libkeyfinder
  The musical key detection (the spectral kernel over 72 semitone bands, the tone profiles and octave weights, the cosine similarity over the 24 keys) is ported to Lua in `Scripts/ReaScratch/reascratch_lib.lua` (`estimate_key`). The hop between frames is doubled for speed.
- **libebur128** by Jan Kokemüller (MIT License) - https://github.com/jiixyj/libebur128
  Auto gain's loudness measure (ITU-R BS.1770 / EBU R128 integrated loudness: the K-weighting filter built from its analogue prototypes with libebur128's constants, and the two gates) follows libebur128, written in Lua in `Scripts/ReaScratch/reascratch_lib.lua`.

## Where the controller presets come from

ReaScratch's presets contain only facts about each controller: MIDI note / CC numbers, channels, value encodings and jog resolutions. No code or mapping files from the sources below are included. Thanks to everyone who documented their hardware:

- **Mixxx** controller mappings and their pull requests (GPL-2.0-or-later) - https://github.com/mixxxdj/mixxx
  The main reference for most DJ controllers, for jog resolutions, and for the HID report layouts of the NI Traktor Kontrol units used by the HID bridge (the bridge is an independent Python implementation).
- **Manufacturers' official MIDI message lists and mappings**: AlphaTheta / Pioneer DJ, Akai Professional, Denon DJ, Hercules, Numark, Reloop, and others - many retrieved through the Internet Archive (https://web.archive.org/), including Reloop's and Numark's own Traktor mappings and Hercules' VirtualDJ mappings.
- **SuperXtremeMapper** manufacturer documentation library (MIT License) - https://github.com/SuperXtremeMapper/super-xtreme-mapper
- **Community mappings**:
  - rylito/mixxx_numark_partymix - https://github.com/rylito/mixxx_numark_partymix
  - saustin2010/denon_sc5000_algoriddim_midi_mapping - https://github.com/saustin2010/denon_sc5000_algoriddim_midi_mapping
  - fixxiefixx/DDJ-FLX6-Mixxx-mapping - https://github.com/fixxiefixx/DDJ-FLX6-Mixxx-mapping
  - randombyte-developer/ddj-800 - https://github.com/randombyte-developer/ddj-800
  - irarainey/silverdaw - https://github.com/irarainey/silverdaw
  - Y0ngg4n/MixxxControllerMappings - https://github.com/Y0ngg4n/MixxxControllerMappings
  - Andymann/mixxx-controllers - https://github.com/Andymann/mixxx-controllers
  - ozzaii/vibemix - https://github.com/ozzaii/vibemix
  - djay user mappings shared on the Algoriddim community forum (Reloop Mixon 8 Pro; Hercules DJControl Inpulse 200 MK2 by th3StonedApe) - https://community.algoriddim.com/

Product and company names are trademarks of their respective owners and are used only to identify compatible hardware. ReaScratch is not affiliated with or endorsed by any of them.

## Inspiration

- **TIME-1** by tilr (tiagolr) - https://github.com/tiagolr/time1
  The idea of scratching a time buffer inside a JSFX. No code from TIME-1 is used.
- **OtoMadSampler (Sampler81800)** by neon-uriel - https://github.com/neon-uriel/Sampler81800
  A sampler made for otoMAD, where the author first learned of WSOLA. No code from it is used.
- The CDJ / rekordbox workflow (hot cues, memory cues, SLIP, BEAT SYNC, needle search) as a model for the controls.
- **Resolume** (https://resolume.com/) and **gl-transitions** (https://gl-transitions.com/) as models for the video effects, blends and transitions. No code from either is used.
- **librosa**'s `beat_track` (D. Ellis, "Beat Tracking by Dynamic Programming", 2007) for the beat maps of songs whose tempo moves, and F. Font and X. Serra, "Tempo estimation for music loops and a simple confidence measure" (ISMIR 2016) for short loops. The methods only, written anew in Lua.

## The spinning speaker

`Scripts/ReaScratch/reascratch_audio_only.avi` (shown for audio-only files) is a 3D model made by the ReaScratch author after a real loudspeaker, with no maker's name or logo on it.

## HID bridge

`HID bridge/ReaScratch-HID-Bridge.exe` bundles Python, hidapi, mido, python-rtmidi / RtMidi, OpenSSL and the PyInstaller bootloader. Their licenses are in `HID bridge/THIRD_PARTY_LICENSES.txt`.

## Runtime

- REAPER by Cockos - https://www.reaper.fm/
- Optional: FFmpeg (installed by the user, not bundled), js_ReaScriptAPI (ReaPack), SWS / S&M extension (ReaPack; previewing a Media Explorer file with the P key).

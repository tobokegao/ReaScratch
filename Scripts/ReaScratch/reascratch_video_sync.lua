-- ReaScratch kit: video sync. Follows the ReaScratch head position (in the video of the sample slot in use, which
-- sits at (slot - 1) x 3600 s) with the edit cursor so the
-- REAPER video window (View > Video) shows the matching frame. Run it again to stop.
-- It keeps running while no project with the ReaScratch JSFX is open: it waits (one check per second)
-- and starts following as soon as such a project is in front, so it can be started once when REAPER
-- starts (reascratch_setup.lua can add that to Scripts/__startup.lua) and never needs starting by hand.
-- Deck B (when reascratch_setup.lua made it): the cursor stays deck A's; deck B is shown by the one item on "video B view"
-- (just above "video"), which this script points at the video of deck B's slot (taken from the muted "video B" track) and
-- moves so that the frame at the cursor is deck B's head (position + start offset; item edits made this way set no
-- undo point and do not mark the project changed, measured 2026-10-04). The Video processor on "video" mixes the two;
-- the crossfader cut then no longer mutes "video".
-- Liveness is a heartbeat (not a flag), so a killed instance never blocks a restart.
-- Launch it under its own file name: REAPER terminates a running defer script when a script with the
-- same file name is started again.
-- Globals read at start (set them before dofile):
--   REASCRATCH_SYNC_ENSURE = true   start only if not already running (never stops a running one)
--   REASCRATCH_AUTOSTART = true     quiet: no console messages (used from __startup.lua)
-- REAPER's own transport: while a ReaScratch project is in front, play / pause of REAPER itself is stopped at once
-- (the video window would show REAPER's play position instead of the head). Recording is not stopped.
-- While REAPER records, the hand on the records and the crossfader are recorded into the decks' lanes (⚪50,
-- reascratch_lib.lua rec_tick; reascratch_record_lanes.lua turns it off / on).
-- With the "Rec" tracks (reascratch_take.lua) each deck is also filmed; when the recording stops a take project is made
-- (reascratch_lib.lua take_tick).
--   REASCRATCH_SYNC_LOG = true     also write "time  head_s  speed_x  touched  xfader_gain" to <temp>/reascratch_sync_log.txt

local ENSURE = _G.REASCRATCH_SYNC_ENSURE or false
local QUIET = _G.REASCRATCH_AUTOSTART or false
local REASCRATCH_SYNC_LOG = _G.REASCRATCH_SYNC_LOG or false

local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local BR = loadfile(HERE .. "reascratch_browser.lua")(L)   -- LOAD A / B from the Media Explorer (⚪78)
local CP = loadfile(HERE .. "reascratch_ctl_presets.lua")(L)   -- the Learn tab's controller presets (⚪68)
local function say(s) if not QUIET then L.log(s) end end

local SECTION, KEY = "ReaScratch", "video_sync_heartbeat"
-- already running: with ENSURE left alone, else it is sent "stop" and exits. Starting: the heartbeat is written at once
-- (a "stop" left behind made the new instance stop itself on its first cycle, 2026-10-04). ((⚪151) L.heartbeat_claim)
do
  local go, stopped = L.heartbeat_claim(KEY, ENSURE, true)
  if not go then
    if stopped then say("video sync: stop") end
    return
  end
end

local log
if REASCRATCH_SYNC_LOG then
  local tmp = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
  log = io.open(tmp .. L.SEP .. "reascratch_sync_log.txt", "w")
end

local tr, fx, P_POS, P_SPD, P_TCH, P_XF, P_SLOT
local trB, fxB, PB_POS, PB_SLOT, vstoreB, viewB
local vitem, vtake, vpath, vplace, vmuted, vrate, vloop
local t0, last, next_look = reaper.time_precise(), -1, 0
-- ⚪38: the envelope scratch / fader lanes of both decks go to gmem (reascratch_lib.lua ev_export), checked every 0.5 s
reaper.gmem_attach(L.GMEM)
local evA, evB, ev_next, engB, fxEB = {}, {}, 0, nil, nil
local pt_seen = nil   -- (⚪115) the pattern pads: the ExtState seen last (written again when it changes)
local TL = {}   -- (⚪111) L.tempo_lead's counters

-- crossfader cut: while the JSFX's crossfader gain is below half, the "video" track is muted (the video
-- window shows black). Only a mute this script set is undone, so a hand-set mute is left alone.
local vtr, hidden = nil, false
local function hide(on)
  if on == hidden then return end
  if vtr and reaper.ValidatePtr2(0, vtr, "MediaTrack*") then
    reaper.SetMediaTrackInfo_Value(vtr, "B_MUTE", on and 1 or 0)
  end
  hidden = on
end

-- ⚪51 REAPER redraws the video window only when the cursor reaches another frame or an item's picture may change, so with
-- both decks standing still a crossfader move, a Z cut or a change of blend / video FX did not show. When the shared
-- memory the deck mix reads changes while nothing moved, deck B's view item is moved by 1 ms and put back the next
-- time: REAPER draws the picture again (no undo point). The move goes to the side that keeps the same frame at the
-- cursor (a move across a frame edge showed the next frame). (Turning a knob of the Video processor set undo points;
-- moving the item by half a microsecond or UpdateTimeline did not redraw. Changing the take volume by a millionth
-- redrew on 2026-10-06 in the morning, but not in the evening in the user's REAPER - the crossfader never showed with
-- both decks stopped, ⚪33; the 1 ms move redrew within 0.03 s.) The shared memory read: gains [0] [1], blend and keys
-- [2..4], the mix's FX [5] [6], the flips [7] [8] [27] [28], each deck's FX, amount and lamp [10 11 13] [20 21 23]
-- (not the beat positions or the counters: they move only while playing)
-- (29 = deck B's slot has video / which, 49 = a LOAD or a slot menu change counted by reascratch_browser.lua: both redraw a
-- standing picture, ⚪78: a sound-only slot loaded into a stopped deck kept the last picture)
-- (32-35 = the decks' picture fade and filter tilt, ⚪91; 372 / 373 = the Media Explorer preview's deck and picture, ⚪188)
local PIC = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 13, 20, 21, 23, 27, 28, 29, 32, 33, 34, 35, 49, 76, 77, 78, 79, 80, 81,
  82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 93, 94, 95, 96, 97, 98, 102, 103, 121, 122, 123, 124,
  126, 127, 131, 132, 133, 136, 137, 138, 139, 140, 141, 142, 143, 170, 171, 172, 173, 174, 175, 176, 177, 188, 241, 242,
  243, 270, 271, 273, 274, 275, 276, 372, 373 }   -- (82-89 / 91-98 = the FX knobs, ⚪94; 102 / 103 the Strobe step, ⚪101; 121-124 the Tint's colours, ⚪114)
-- ((⚪156, user's report 2026-10-13: the VHS knob did nothing to a standing picture) every value the deck mix reads that
-- changes a standing picture: the VHS knobs [126] [127], the camera moves [131-133], the LFOs [136-141], the transition
-- [142] [143], TOUCH FX row 2 [170-177], the blend + transition switch [188], the helper's FX boost [241], the master
-- fader [242], the blackout [243], the pictures cleared [270] [271], the VHS colour [273] [274] (⚪158), its on-screen text [275] [276] (⚪160). The developer's consistency check compares this list with the deck mix's reads
local NUDGE = 0.001
local met_seen, rec_seen                          -- the metronome / record request counters seen (⚪91)
local sav_seen                                    -- (2026-10-13) the project save requests seen (APC40 SESSION)
-- ⚪97: the crossfader's last position, kept in REAPER's settings (a controller sends it only when it moves): given to the
-- JSFX at start (gmem[50] = position + 1), stored again when the JSFX reports a new one (gmem[51] = position + 1)
local xf_saved = tonumber(reaper.GetExtState(SECTION, "xf_last"))
reaper.gmem_write(50, xf_saved and xf_saved + 1 or 0)
local xf_seen, xf_t = nil, 0
local out_next = 0   -- (⚪109) the lights output check
local pic_last, pic_pos, nudged, frame_s = nil, nil, nil, 1 / 30
-- ⚪97 (user's report 2026-10-09: at start the screen stayed black with the crossfader at deck A's end): while both decks
-- stand still REAPER hands the Video processor no frame of deck A's own item until that item is touched, so for the first
-- seconds after a project is found deck A's item at the cursor is nudged with B's view item (and put back next time)
local a_kick_until, a_next, nudgedA = 0, 0, nil
local follow_now = false   -- ((⚪178 stage 5) deck A's item follows REAPER's position: recording, or "play the performance")
local function nudge_a(pos)
  if not (vtr and reaper.ValidatePtr2(0, vtr, "MediaTrack*")) or reaper.GetPlayState() & 4 ~= 0 or follow_now then return end
  for i = 0, reaper.CountTrackMediaItems(vtr) - 1 do
    local it = reaper.GetTrackMediaItem(vtr, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if pos >= p and pos < p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH") then
      reaper.SetMediaItemInfo_Value(it, "D_POSITION", p + NUDGE); reaper.UpdateItemInProject(it)
      nudgedA = { it, p }
      return
    end
  end
end
-- ⚪99 (user's report 2026-10-09: with both decks stopped a fader's video FX changed jerkily): a standing picture is drawn
-- again by moving the deck mix's own "redraw" parameter, as a hand on a Video processor knob does, not by nudging items
-- (measured in the isolated REAPER with a 960x720 video: nudges showed 2-4 new pictures a second, unevenly, and a single
-- slow step often not at all; the parameter shows each step about 0.1 s later). Not too often: a new redraw asked for
-- before the last one reached the window replaced it (LoRez: 0.05-0.085 s apart showed 2-4 pictures a second, 0.1 s 8
-- evenly; the raster, drawn in about 25 ms against LoRez's 10: 0.1 s showed some and then stalled, 0.2 s 5 a second
-- evenly). So the gap follows the deck mix's own drawing time (gmem[99], averaged): 0.06 s + 7 times it, 0.1-0.3 s
-- (LoRez then 6-7 pictures a second, the raster 5-6, both evenly; 4 times stalled the raster again at its larger amounts).
-- The last change is always drawn (it waits), and once more 0.3 s after it
local still_next, still_again, draw_s = 0, nil, 0.01
local miss_next = 0
local vpfx, vp_val = nil, 0
local function param_kick()
  if not (vtr and reaper.ValidatePtr2(0, vtr, "MediaTrack*")) then return end
  local function is_mix(i) return (select(2, reaper.TrackFX_GetParamName(vtr, i, 0)) or ""):find("^redraw") ~= nil end
  if not (vpfx and vpfx < reaper.TrackFX_GetCount(vtr) and is_mix(vpfx)) then
    vpfx = nil
    for i = 0, reaper.TrackFX_GetCount(vtr) - 1 do if is_mix(i) then vpfx = i break end end
  end
  if not vpfx then return end
  vp_val = 1 - vp_val
  reaper.TrackFX_SetParam(vtr, vpfx, 0, vp_val)
end
local function redraw_if_still(pos, b_moved, p_moved)
  if nudgedA then   -- deck A's item back first
    if reaper.ValidatePtr2(0, nudgedA[1], "MediaItem*") then
      reaper.SetMediaItemInfo_Value(nudgedA[1], "D_POSITION", nudgedA[2]); reaper.UpdateItemInProject(nudgedA[1])
    end
    nudgedA = nil
  end
  local now = reaper.time_precise()
  draw_s = draw_s + (math.min(0.2, reaper.gmem_read(99)) - draw_s) * 0.2
  local kick = now < a_kick_until and now >= a_next
  if kick then a_next = now + 0.5; nudge_a(pos) end
  local t = {}
  for i, k in ipairs(PIC) do t[i] = string.format("%.4f", reaper.gmem_read(k)) end
  local sig = table.concat(t, ",")
  local still = pic_pos and math.abs(pos - pic_pos) < frame_s and not b_moved and not p_moved   -- ((⚪188) the preview's picture moving)
  pic_pos = pos
  -- ((⚪156) deck B's view moved (a jump, a slot or its loop video's rate) while A stands: the one item move did not always
  -- redraw (⚪99), so the redraw parameter once more just after
  if b_moved then still_again = now + 0.1 end
  -- ⚪31 (2026-10-06): a playing deck whose video is a still picture (every frame the same, e.g. a cover image) did not
  -- redraw either: REAPER skips a frame that looks like the last one, so a crossfader move or an FX change showed only up
  -- to 0.5 s later and the video FX did not show at all. So a change redraws while moving too, and while a deck moves
  -- with a video FX on (strobe and kaleidoscope go with the beat) it redraws every cycle
  local fx_on = reaper.gmem_read(5) ~= 0 or reaper.gmem_read(10) ~= 0 or reaper.gmem_read(20) ~= 0
  -- ((⚪179) and the TOUCH FX second row's (Disc, Line art, Halftone, Zoom blur: the amounts [170..173] deck A, [174..177]
  -- B), which this missed: a still picture with only the Disc on did not turn)
  for k = 170, 177 do if fx_on then break end fx_on = reaper.gmem_read(k) > 0.001 end
  local want = (sig ~= pic_last or fx_on) and not still or kick   -- (standing: only the start kicks move items)
  -- (⚪100, user's report 2026-10-09: after a restart with both decks stopped, the crossfader moved to deck B showed black)
  -- a deck shows without a frame (the deck mix says so, gmem[100] B / [101] A): its item is touched, every 0.3 s at most
  if still and now >= miss_next and (reaper.gmem_read(100) ~= 0 or reaper.gmem_read(101) ~= 0) then
    miss_next = now + 0.3
    if reaper.gmem_read(101) ~= 0 and not kick then nudge_a(pos) end
    if reaper.gmem_read(100) ~= 0 then want = true end
  end
  -- ((⚪156, user's choice 2026-10-13) an effect that moves by the clock (VHS's grain, a camera move's shake, without a BPM
  -- the LFO, Kaleidoscope's turn, Strobe) stays still on a standing picture: redrawing it on and on cost about a third of
  -- a core. A change of a value in PIC redraws it once, as below
  if still and sig ~= pic_last and sig ~= nil then   -- (⚪99) standing: the redraw parameter
    if now >= still_next then
      param_kick(); still_next = now + math.min(0.3, math.max(0.1, 0.06 + 7 * draw_s)); still_again = now + 0.3; pic_last = sig
    end
  else
    if still and still_again and now >= still_again then param_kick(); still_again = nil end
    pic_last = sig
  end
  if not (vtake and vitem and reaper.ValidatePtr2(0, vitem, "MediaItem*")) then nudged = nil return end
  if nudged then
    -- put it back (this redraws as well), unless follow_b has placed it since
    if not b_moved then
      reaper.SetMediaItemInfo_Value(vitem, "D_POSITION", nudged[1])
      reaper.SetMediaItemTakeInfo_Value(vtake, "D_STARTOFFS", nudged[2])
      reaper.UpdateItemInProject(vitem)
      nudged = nil
      return
    end
    nudged = nil
  end
  if not want then return end
  local p = reaper.GetMediaItemInfo_Value(vitem, "D_POSITION")
  local o = reaper.GetMediaItemTakeInfo_Value(vtake, "D_STARTOFFS")
  local f = ((pos - p + o) / frame_s) % 1           -- where the cursor's frame is in its frame time
  if f >= 0.5 then reaper.SetMediaItemInfo_Value(vitem, "D_POSITION", p + NUDGE)             -- an earlier spot in it
  elseif p >= NUDGE then reaper.SetMediaItemInfo_Value(vitem, "D_POSITION", p - NUDGE)       -- a later spot
  else reaper.SetMediaItemTakeInfo_Value(vtake, "D_STARTOFFS", o + NUDGE) end
  reaper.UpdateItemInProject(vitem)
  nudged = { p, o }
end

-- (re)find the engine in the project in front; nil while there is none
local function look()
  hide(false)
  tr, fx = L.find_engine(1)
  trB, fxB = L.find_engine(2)
  engB, fxEB = trB, fxB
  evA, evB, ev_next = {}, {}, 0                         -- another project: write every lane again
  if trB then
    PB_POS = L.param_index(trB, fxB, "Head position")
    PB_SLOT = L.param_index(trB, fxB, "Sample slot")
    vstoreB, viewB = L.track_by_name(L.TRACK_VIDEO_B), L.track_by_name(L.TRACK_VIEW_B)
    if not (PB_POS and vstoreB and viewB) then trB = nil end
  end
  vitem, vpath, vplace = nil, nil, nil
  if tr then
    P_POS = L.param_index(tr, fx, "Head position")
    P_SPD = L.param_index(tr, fx, "Head speed")
    P_TCH = L.param_index(tr, fx, "Touched")
    P_XF = L.param_index(tr, fx, "Crossfader gain")   -- nil with a JSFX older than the crossfader
    P_SLOT = L.param_index(tr, fx, "Sample slot")     -- nil with a JSFX older than the sample slots
    if not P_POS then tr = nil end
  end
  vtr = L.track_by_name(L.TRACK_VIDEO)
  a_kick_until = reaper.time_precise() + 6   -- (⚪97) deck A's frame at start, see nudge_a
  -- ⚪91: the deck mix of this project brought up to the kit's .eel (it changed: the picture fade, the filter's look)
  if vtr and L.update_deck_mix(vtr, HERE .. "reascratch_deck_mix.eel") then say("video sync: deck mix updated") end
  -- (⚪191) a project set up before the metronome: the decks' metronome (channels 7/8) sent to the Cue track too
  if tr and L.cue_metro_ensure() > 0 then say("video sync: the metronome sent to the Cue track") end
  if tr and vtr and L.fill_black(vtr) > 0 then reaper.UpdateArrange() end   -- (⚪78: black where a slot has no video)
  -- ⚪54: "video B view" on the side of "video" that the project's video setting lets the mix win on
  if trB and vtr and viewB then L.place_view_b(vtr, viewB) end
  frame_s = 1 / math.max(1, (reaper.TimeMap_curFrameRate(0)))   -- (it also returns a drop-frame flag)
  pic_last, pic_pos, nudged = nil, nil, nil
  last = -1
  L.sync_toggles(HERE)   -- ((⚪151) the Rec / record-lanes buttons show this project's state, also after REAPER starts)
  return tr
end

if look() then say("video sync: start (run again to stop)")
else say("video sync: waiting for a project with the ReaScratch JSFX (run again to stop)") end

-- deck B's view item: the one item on "video B view" (made when missing), pointed at `path` (nil = no video: muted; the
-- caller gives the black picture instead, ⚪78)
local soloB = { slot = nil, t = 0, on = false }    -- (2026-10-13) deck B's slot: a sound only?
local function view_item(path, rate)
  if not (vitem and reaper.ValidatePtr2(0, vitem, "MediaItem*")) then
    vitem = reaper.GetTrackMediaItem(viewB, 0) or reaper.AddMediaItemToTrack(viewB)
    vtake = reaper.GetActiveTake(vitem) or reaper.AddTakeToMediaItem(vitem)
    reaper.SetMediaItemInfo_Value(vitem, "B_LOOPSRC", 0)
    reaper.SetMediaItemInfo_Value(vitem, "D_LENGTH", L.SLOTS * L.SLOT_SPAN + L.SLOT_SPAN)
    local src = reaper.GetMediaItemTake_Source(vtake)
    vpath = src and reaper.GetMediaSourceFileName(src, "") or ""
    vplace, vmuted, vrate, vloop = nil, nil, nil, nil
  end
  if path and path ~= vpath then
    -- (the take does not free the source it had: L.take_set_source frees it, ⚪151)
    if L.take_set_source(vtake, reaper.PCM_Source_CreateFromFile(path)) then vpath, vplace = path, nil end
  end
  -- ((2026-10-13) the loop video of a sound-only slot: looped, faster (L.loop_rate); any other picture as it is
  rate = rate or 1
  -- ((⚪188) the black picture looped too, as ⚪186 did for deck A: the PNG is a 1 s source, and with deck B's head near
  -- its end REAPER handed no frame of it now and then, so the deck mix's deck B input became the picture under it (an
  -- unmuted item on "preview view": the user's report 2026-10-16, Matsuken flickering in an empty deck B)
  local loop = rate ~= 1 or vpath == L.BLACK_PNG
  if rate ~= vrate or loop ~= vloop then
    reaper.SetMediaItemInfo_Value(vitem, "B_LOOPSRC", loop and 1 or 0)
    reaper.SetMediaItemTakeInfo_Value(vtake, "D_PLAYRATE", rate)
    vrate, vloop, vplace = rate, loop, nil
  end
  local mute = path == nil
  if mute ~= vmuted then reaper.SetMediaItemInfo_Value(vitem, "B_MUTE", mute and 1 or 0); vmuted = mute end
end

-- the video of deck B's slot: the item starting at the slot's place on "video B" (nil when the slot has none)
local function slot_video(track, slot)
  local it = L.slot_item(track, slot)   -- ((⚪151) L.slot_item)
  local take = it and reaper.GetActiveTake(it)
  local src = take and reaper.GetMediaItemTake_Source(take)
  return src and reaper.GetMediaSourceFileName(src, "")
end

-- (⚪102) deck A's item in its slot on "video": { position, length } (nil without one); looked up again every 0.5 s
local sitem = { slot = nil, t = 0 }
local function slot_item(slot)
  local now = reaper.time_precise()
  if sitem.slot == slot and now < sitem.t then return sitem.v end
  sitem.slot, sitem.t, sitem.v = slot, now + 0.5, nil
  if not (vtr and reaper.ValidatePtr2(0, vtr, "MediaTrack*")) then return nil end
  local it, p = L.slot_item(vtr, slot)   -- ((⚪151) L.slot_item: its margin 0.0005 s, here 0.01 s before)
  if it then sitem.v = { p, reaper.GetMediaItemInfo_Value(it, "D_LENGTH") } end
  return sitem.v
end

-- deck B follows: the frame at the cursor `cur` = deck B's head. Position cur - head (start offset 0); before the
-- timeline start, position 0 and the rest as start offset (both stay >= 0). Returns true when it moved the view item
local function follow_b(cur)
  if not (trB and reaper.ValidatePtr2(0, trB, "MediaTrack*") and reaper.ValidatePtr2(0, viewB, "MediaTrack*")
          and reaper.ValidatePtr2(0, vstoreB, "MediaTrack*") and reaper.TrackFX_GetCount(trB) > fxB) then
    trB = nil
    return
  end
  local slot = PB_SLOT and math.floor(reaper.TrackFX_GetParam(trB, fxB, PB_SLOT) + 0.5) or 1
  -- no video in the slot: the black picture (muted, REAPER kept drawing the last picture of B: ⚪78)
  local sv = slot_video(vstoreB, slot)
  -- ((2026-10-13) no video but a sample there: the loop video (deck B's samples read again on a slot change, or every 3 s)
  local now = reaper.time_precise()
  if not sv and (soloB.slot ~= slot or now > soloB.t) then
    soloB.slot, soloB.t = slot, now + 3
    soloB.on = reaper.file_exists(L.LOOP_VIDEO) and (L.engine_samples(trB))[slot] ~= nil
  end
  local loop = not sv and soloB.on
  if loop then sv = L.LOOP_VIDEO end
  view_item(sv or (reaper.file_exists(L.BLACK_PNG) and L.BLACK_PNG or nil), loop and L.loop_rate(reaper.gmem_read(248)) or 1)
  reaper.gmem_write(29, sv and 2 + slot or 1)   -- the deck mix drops its kept picture of B on a change / no video
  if vmuted then return end
  -- (⚪100) at least half a frame into the video: with deck B's head at 0 the cursor stood right on the item's left edge
  -- and REAPER handed no frame of it while both decks stood still (user's report 2026-10-09: B black after a restart;
  -- in the user's REAPER the deck mix said "no frame of B" until the item was moved half a frame earlier)
  local head = math.max(reaper.TrackFX_GetParam(trB, fxB, PB_POS), frame_s * 0.5)
  -- ((⚪157, user's choice 2026-10-13) past the video's end (the rest a loop plays after the sample) its last frame stays
  local src = not loop and reaper.GetMediaItemTake_Source(vtake)
  local sl = src and reaper.GetMediaSourceLength(src) or 0
  if sl > frame_s then head = math.min(head, sl - frame_s * 0.5) end
  local p, offs = cur - head, 0
  if p < 0 then offs, p = -p * vrate, 0 end   -- (the offset in the source's time)
  if not vplace or math.abs(p - vplace[1]) > 0.000001 or math.abs(offs - vplace[2]) > 0.000001 then
    reaper.SetMediaItemInfo_Value(vitem, "D_POSITION", p)
    reaper.SetMediaItemTakeInfo_Value(vtake, "D_STARTOFFS", offs)
    reaper.UpdateItemInProject(vitem)
    vplace = {p, offs}
    return true
  end
end

-- ⚪53 while REAPER records, the video window shows REAPER's record position and the edit cursor does nothing (it showed
-- the slot's video from the record start on, not the deck; found 2026-10-06 filming with frame-numbered videos). So
-- deck A's slot item on "video" is moved so that the frame at the record position is the head (as deck B's view item
-- is), and put back where it was when the recording stops. Item moves this way set no undo point.
local fillA_slot, fillA_turn = nil, nil                                 -- (2026-10-13) deck A's slot the fill was checked for
local recA = nil                                      -- { item, take, pos, offs } of the moved item
-- The items are placed for the record / play position itself (AHEAD = 0). ((⚪178, user's choice 2026-10-15) they were
-- placed the video window's Video cache ahead (L.video_cache; 2026-10-06: "with 1 s the window showed the decks 59 frames
-- ahead"), but measured with frame-numbered videos against the logged heads that put the picture
-- 0.95-0.99 s behind the decks while recording with the 1 s cache; at the position itself 0.00-0.02 s with 1 s, as with
-- fx_mode=3. Kept as a value for the tests (REASCRATCH_TEST_AHEAD)
local AHEAD, was_roll = 0, false
local pp_was = false   -- (⚪178) "play the performance" seen on the last cycle
local function read_ahead()
  return REASCRATCH_TEST_AHEAD or 0
end
local function rec_a_restore()
  if recA and reaper.ValidatePtr2(0, recA.item, "MediaItem*") then
    reaper.SetMediaItemInfo_Value(recA.item, "D_POSITION", recA.pos)
    reaper.SetMediaItemTakeInfo_Value(recA.take, "D_STARTOFFS", recA.offs)
    reaper.UpdateItemInProject(recA.item)
  end
  recA = nil
  sitem.slot = nil   -- ((⚪151) slot_item kept the moved place for up to 0.5 s after the recording stopped)
end
local function rec_a_follow(P, slot, head)
  if not (vtr and reaper.ValidatePtr2(0, vtr, "MediaTrack*")) then return end
  local start = L.slot_start(slot)
  if not (recA and recA.slot == slot and reaper.ValidatePtr2(0, recA.item, "MediaItem*")) then
    rec_a_restore()
    local it, p = L.slot_item(vtr, slot)   -- ((⚪151) L.slot_item)
    local tk = it and reaper.GetActiveTake(it)
    if tk then recA = { item = it, take = tk, pos = p, offs = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS"), slot = slot } end
    if not recA then return end
  end
  -- the frame at the cursor was the one at (cursor - pos + offs); the same frame at P: P - x + o = start + head - pos + offs
  local x = P - (start + head - recA.pos)
  local o = recA.offs
  if x < 0 then o, x = o - x * reaper.GetMediaItemTakeInfo_Value(recA.take, "D_PLAYRATE"), 0 end   -- (the offset in the source's time)
  if recA.x and math.abs(x - recA.x) < 0.000001 and math.abs(o - recA.o) < 0.000001 then return false end
  recA.x, recA.o = x, o
  reaper.SetMediaItemInfo_Value(recA.item, "D_POSITION", x)
  reaper.SetMediaItemTakeInfo_Value(recA.take, "D_STARTOFFS", o)
  reaper.UpdateItemInProject(recA.item)
  return true
end
-- (⚪178 stage 5) "play the performance" with REAPER's position in the performance zone (from L.PF_ZONE on): a picture
-- item of its own on "video" (L.PERF_VIEW_NAME, deck A's slot's source, rate and loop), placed as rec_a_follow places
-- the slot's item, so that the frame at P is deck A's head. The slot items stay where they are: what reads them (a
-- slot's fill, the take project, a LOAD, a project saved meanwhile) finds them in their places. Taken away when not
-- needed (pv_drop) and, left behind (a project saved while it stood there), when the sync starts (pv_clear)
local pv, pv_tr = nil, nil   -- { item, take, src, slot, rate, x, o } of the picture item; the "video" track it was cleared on
local function pv_drop()
  if pv and reaper.ValidatePtr2(0, pv.item, "MediaItem*") then
    reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(pv.item), pv.item)
    reaper.UpdateArrange()
  end
  pv = nil
end
local function pv_clear()
  pv = nil
  if not (vtr and reaper.ValidatePtr2(0, vtr, "MediaTrack*")) then return end
  for i = reaper.CountTrackMediaItems(vtr) - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(vtr, i)
    if L.is_perf_view(it) then reaper.DeleteTrackMediaItem(vtr, it) end
  end
end
local function pv_follow(P, slot, head)
  if not (vtr and reaper.ValidatePtr2(0, vtr, "MediaTrack*")) then return false end
  local sit, spos = L.slot_item(vtr, slot)
  local stk = sit and reaper.GetActiveTake(sit)
  local ssrc = stk and reaper.GetMediaItemTake_Source(stk)
  if not ssrc then pv_drop() return false end
  local fn = reaper.GetMediaSourceFileName(ssrc, "")
  if not (pv and reaper.ValidatePtr2(0, pv.item, "MediaItem*") and reaper.GetMediaItem_Track(pv.item) == vtr) then
    pv_drop()
    local it = reaper.AddMediaItemToTrack(vtr)
    local tk = reaper.AddTakeToMediaItem(it)
    reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", L.PERF_VIEW_NAME, true)
    pv = { item = it, take = tk }
  end
  local rate = reaper.GetMediaItemTakeInfo_Value(stk, "D_PLAYRATE")
  if pv.src ~= fn or pv.slot ~= slot or pv.rate ~= rate then
    if pv.src ~= fn then L.take_set_source(pv.take, reaper.PCM_Source_CreateFromFile(fn)) end
    reaper.SetMediaItemTakeInfo_Value(pv.take, "D_PLAYRATE", rate)
    reaper.SetMediaItemInfo_Value(pv.item, "B_LOOPSRC", reaper.GetMediaItemInfo_Value(sit, "B_LOOPSRC"))
    reaper.SetMediaItemInfo_Value(pv.item, "D_LENGTH", reaper.GetMediaItemInfo_Value(sit, "D_LENGTH"))
    pv.src, pv.slot, pv.rate, pv.x, pv.o = fn, slot, rate, nil, nil
  end
  -- (as rec_a_follow: the frame of the slot's item at start + head, at P)
  local x = P - (L.slot_start(slot) + head - spos)
  local o = reaper.GetMediaItemTakeInfo_Value(stk, "D_STARTOFFS")
  if x < 0 then o, x = o - x * rate, 0 end
  if pv.x and math.abs(x - pv.x) < 0.000001 and math.abs(o - pv.o) < 0.000001 then return false end
  pv.x, pv.o = x, o
  reaper.SetMediaItemInfo_Value(pv.item, "D_POSITION", x)
  reaper.SetMediaItemTakeInfo_Value(pv.take, "D_STARTOFFS", o)
  reaper.UpdateItemInProject(pv.item)
  return true
end

-- (⚪117) REAPER closing (the script ends by any way but its own stop): the JSFX sends no more lights (gmem[125]) and
-- every light goes off; a stop by running the script again leaves the lights as they are. (⚪124, user's report
-- 2026-10-10: the lights stayed on) on quit the project is already closed when this runs: the outputs are the ones kept
-- while running (light_devs, every 2 s, also written for reascratch_lights_off.ps1, started here: it turns them off once
-- REAPER is gone, as REAPER's outputs are closed by the time this runs)
local own_stop = false
-- what this script changed put back: the video track's crossfader mute, deck A's item moved while recording, the nudged
-- items (⚪33, ⚪53, ⚪97). ((⚪151) also when the script ends any other way (a Lua error, REAPER terminating it): only its
-- own stop did it before, and an error while recording left deck A's video moved and "video" muted)
local function put_back()
  hide(false)
  BR.preview_stop()   -- (⚪188)
  rec_a_restore()
  pv_drop()
  if nudged and vitem and reaper.ValidatePtr2(0, vitem, "MediaItem*") then
    reaper.SetMediaItemInfo_Value(vitem, "D_POSITION", nudged[1])
    reaper.SetMediaItemTakeInfo_Value(vtake, "D_STARTOFFS", nudged[2])
    reaper.UpdateItemInProject(vitem)
  end
  nudged = nil
  if nudgedA and reaper.ValidatePtr2(0, nudgedA[1], "MediaItem*") then
    reaper.SetMediaItemInfo_Value(nudgedA[1], "D_POSITION", nudgedA[2]); reaper.UpdateItemInProject(nudgedA[1])
  end
  nudgedA = nil
end
local light_devs, light_t = L.lights_devs(), reaper.time_precise()
L.lights_write(light_devs)
L.lights_watch()
reaper.gmem_write(125, 0)
reaper.atexit(function()
  if own_stop then return end
  pcall(put_back)   -- (before the lights: an error here must not keep them on)
  reaper.gmem_write(125, 1)
  local now = L.lights_devs()
  if next(now) == nil then now = light_devs end
  L.lights_off(now)
end)

local function tick()
  if reaper.time_precise() - light_t > 2 then
    light_t = reaper.time_precise()
    local d = L.lights_devs()
    if next(d) ~= nil then light_devs = d; L.lights_write(d) end   -- (a project being switched: keep the last ones)
  end
  if reaper.GetExtState(SECTION, KEY) == "stop" then
    own_stop = true
    reaper.SetExtState(SECTION, KEY, "0", false)
    put_back()                                        -- (⚪53 / ⚪33: the moved items back in their places)
    if log then log:close() end
    return
  end
  local t = reaper.time_precise()
  reaper.SetExtState(SECTION, KEY, tostring(t), false)
  -- no engine, another project in front, or the FX was re-added: look again (once per second)
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") or reaper.TrackFX_GetCount(tr) <= fx then
    tr = nil
    if t >= next_look then
      next_look = t + 1.0
      look()
    end
    if not tr then reaper.defer(tick) return end
  elseif t >= next_look then
    -- ((⚪150) once a second: an FX put before the JSFX moved its number (the old one read another FX's parameters),
    -- and a deck B made while the sync ran was never found (look ran only without deck A)
    next_look = t + 1.0
    local eB = L.find_engine(2)
    if L.engine_fx(tr) ~= fx or eB ~= engB or (eB and L.engine_fx(eB) ~= fxEB) then
      look()
      if not tr then reaper.defer(tick) return end
    end
  end
  -- A render is running: do nothing at all. During an offline render REAPER's play state reads "playing"; pressing
  -- stop then made the rest of the rendered audio silent, and moving the cursor made the video window seek the file
  -- being rendered, which put black frames into the AVI (both reproduced 2026-10-03; the imported WAV was silent
  -- from 8.3 s). Two signs: the kit's own renders set the "busy" mark (reascratch_lib.lua); any other offline render
  -- shows as "playing" while the audio device is not running. (An online render cannot be told from real playback.)
  local ps = reaper.GetPlayState()
  local busy = tonumber(reaper.GetExtState(SECTION, "busy"))
  if (busy and t >= busy and t - busy < 7200) or (ps & 1 ~= 0 and reaper.Audio_IsRunning() == 0) then
    reaper.defer(tick)
    return
  end
  BR.tick()                                         -- LOAD requests from the JSFX (gmem 54-57)
  -- (⚪178 stage 2) "play the performance" (reascratch_perf_play.lua): the decks play their performance lanes with REAPER's
  -- play (gmem[400] for the JSFX); meanwhile REAPER is not stopped, the edit cursor stays where REAPER has it, and
  -- REAPER's tempo does not follow a deck (it would move the Perf regions under the lanes being played)
  local PP = L.perf_play_gmem()
  if PP ~= pp_was then pp_was = PP; last = -1 end    -- (off again: the cursor back on the head)
  if not PP then L.tempo_lead(TL) end               -- (⚪111) REAPER's tempo follows a deck ("REAPER follows this deck")
  CP.tick()                                         -- the Learn tab: save a controller preset, the user preset list
  -- ⚪91: REAPER's metronome / record from the controller (APC40 METRONOME / SESSION): counters gmem[72] / [73] from the
  -- JSFX; [74] = the metronome's state back for its light (the JSFX reads the record state itself)
  local gm, gr = reaper.gmem_read(72), reaper.gmem_read(73)
  if met_seen == nil then met_seen, rec_seen = gm, gr end
  if gm ~= met_seen then met_seen = gm; reaper.Main_OnCommand(40364, 0) end            -- Options: Toggle metronome
  if gr ~= rec_seen then
    rec_seen = gr
    if ps & 4 ~= 0 then reaper.Main_OnCommand(1016, 0) else reaper.Main_OnCommand(1013, 0) end   -- stop / record
  end
  -- ((user's choice 2026-10-13) the helper APC40's SESSION: save the project (counter gmem [244] from the JSFX)
  local gsv = reaper.gmem_read(244)
  if sav_seen == nil then sav_seen = gsv end
  if gsv ~= sav_seen then
    sav_seen = gsv
    -- a project with no file yet would open the Save As window in the middle of a set: not saved then (gmem [245] = 2)
    local _, fn = reaper.EnumProjects(-1)
    if fn ~= "" then reaper.Main_OnCommand(40026, 0); reaper.gmem_write(245, 1); say("video sync: project saved (APC40 SESSION)")
    else reaper.gmem_write(245, 2); say("video sync: not saved (the project has no file yet; save it once with Ctrl+S)") end
  end
  reaper.gmem_write(74, reaper.GetToggleCommandState(40364) == 1 and 1 or 0)
  local xg = reaper.gmem_read(51)
  if xg > 0 and xg ~= xf_seen and t - xf_t > 0.5 then
    xf_seen, xf_t = xg, t
    reaper.SetExtState(SECTION, "xf_last", ("%.3f"):format(xg - 1), true)
    reaper.gmem_write(50, xg)
  end
  -- (⚪109) every 2 s: each deck's lights output goes with its Preset (L.preset_output); a change asks the JSFX to send the
  -- controller's mode again (gmem[112]: the APC40's Ableton Live mode). A "ReaScratch LED" output (the HID bridge) is left alone
  -- (⚪110) a deck's "2nd controller" set: the two controllers' tracks (L.cx_apply) instead; the engines' own output stays off
  local cx_on, cx_t = false, t >= out_next
  if cx_t then
    local cx_ch, cx_msg, cx_warn
    cx_ch, cx_on, cx_msg, cx_warn = L.cx_apply({ { tr, fx }, { engB, fxEB } })
    if cx_ch then
      reaper.gmem_write(112, reaper.gmem_read(112) + 1)
      if cx_warn then L.log("video sync: " .. cx_msg) else say("video sync: " .. cx_msg) end   -- ((⚪151) a warning also when quiet)
    end
    out_next = t + 2
  end
  if cx_t and not cx_on then
    for _, ef in ipairs({ { tr, fx }, { engB, fxEB } }) do
      local e, f = ef[1], ef[2]
      local pi = e and reaper.ValidatePtr2(0, e, "MediaTrack*") and L.param_index_cached(e, f, "Preset")   -- ((⚪151) every 2 s)
      if pi then
        local _, pn = reaper.TrackFX_GetFormattedParamValue(e, f, pi, "")
        local want, wname = L.preset_output(pn)
        local cur = math.floor(reaper.GetMediaTrackInfo_Value(e, "I_MIDIHWOUT"))
        local dev = cur >= 0 and (cur >> 5) or -1
        local _, cname = reaper.GetMIDIOutputName(dev, "")
        if want and dev ~= want and not (cname or ""):upper():find("REASCRATCH LED", 1, true) then
          reaper.SetMediaTrackInfo_Value(e, "I_MIDIHWOUT", want << 5)
          reaper.gmem_write(112, reaper.gmem_read(112) + 1)
          say(("video sync: lights of %s now to %s (was %s)"):format(pn, wname, cname ~= "" and cname or "none"))
        end
      end
    end
  end
  if t >= ev_next then
    ev_next = t + 0.5
    L.ev_export(tr, fx, 1, evA)
    L.ev_export(engB and reaper.ValidatePtr2(0, engB, "MediaTrack*") and engB or nil, fxEB, 2, evB)
    -- (⚪115) the PATTERN pads' patterns to gmem, at the start and when the pads' choice changes
    local want = reaper.GetExtState("ReaScratch", "pattern_pads") .. "|" .. reaper.GetExtState("ReaScratch", "pattern_saved")
    if want ~= pt_seen or reaper.gmem_read(L.PT_G) <= 0 then
      pt_seen = want
      L.pad_export(L.load_patterns(HERE))   -- ((⚪151) its return value was kept in pt_sig, never read)
    end
  end
  -- ⚪53: deck A's item back in its place before anything reads the slot videos (the take project does)
  if ps & 4 == 0 and recA then rec_a_restore() end
  -- ⚪50: while REAPER records, the hand and the crossfader go into the lanes (put there when the recording stops)
  local rmsg = L.rec_tick(ps & 4 ~= 0, { { tr, fx }, { engB and reaper.ValidatePtr2(0, engB, "MediaTrack*") and engB or nil, fxEB } })
  if rmsg then say("video sync: " .. rmsg) end
  -- ⚪178: and every lane of the performance (transport, head, slot, tempo, key) on REAPER's timeline, in the performance zone
  local pmsg = L.pf_tick(ps & 4 ~= 0, { { tr, fx }, { engB and reaper.ValidatePtr2(0, engB, "MediaTrack*") and engB or nil, fxEB } })
  if pmsg then say("video sync: " .. pmsg) end
  -- ⚪14: the decks filmed while REAPER records (a take project when it stops; reascratch_take.lua)
  local tmsg = L.take_tick(ps & 4 ~= 0)
  if tmsg then say("video sync: " .. tmsg) end
  -- REAPER's own transport playing or paused: the video window then shows REAPER's play position, not the head,
  -- so stop it (user's choice after pressing REAPER's play by mistake). Recording is left alone (filming a performance).
  if ps & 3 ~= 0 and ps & 4 == 0 and not PP then
    reaper.OnStopButton()
    last = -1                                         -- put the cursor back on the head even if it stands still
  end
  -- sample slot k's video sits at (k - 1) x 3600 s on the timeline (reascratch_import_video.lua)
  local slot = P_SLOT and math.floor(reaper.TrackFX_GetParam(tr, fx, P_SLOT) + 0.5) or 1
  -- ((2026-10-13) a slot switched to: its fill again (a sound-only slot = the loop video, L.fill_black)
  if slot ~= fillA_slot then
    fillA_slot, fillA_turn = slot, nil
    -- ((⚪178 stage 5) the item moved while recording back first: the old slot's place looked empty and got a fill too)
    if recA then rec_a_restore() end
    if vtr and reaper.ValidatePtr2(0, vtr, "MediaTrack*") and L.fill_black(vtr, tr) > 0 then sitem.slot = nil; reaper.UpdateArrange() end
  end
  -- ((2026-10-13) the speaker video's rate for this sample's turn (a whole number of turns in the sample, gmem [247])
  local turnA = reaper.gmem_read(247)
  if turnA ~= fillA_turn and vtr and reaper.ValidatePtr2(0, vtr, "MediaTrack*") then
    fillA_turn = turnA
    local it = L.slot_item(vtr, slot)   -- ((⚪151) L.slot_item, L.take_name)
    local tk = it and reaper.GetActiveTake(it)
    -- ((⚪156) the rate changes the frame at the cursor: a standing picture drawn again (pic_last = nil -> a redraw)
    if L.take_name(tk) == L.LOOP_NAME then reaper.SetMediaItemTakeInfo_Value(tk, "D_PLAYRATE", L.loop_rate(turnA)); reaper.UpdateItemInProject(it); pic_last = nil end
  end
  local pos = reaper.TrackFX_GetParam(tr, fx, P_POS) + L.slot_start(slot)
  -- (⚪102, user's report 2026-10-09: when the Matsuken video ended and looped to its start, Wario showed for a moment)
  -- the cursor kept half a frame inside deck A's item: past its end (or right on its start) the "video" track has no
  -- item at the cursor, REAPER does not run the deck mix there and shows the track above (deck B's view) as it is
  local head = pos - L.slot_start(slot)   -- (the head as it is: for the items placed at REAPER's position)
  if vtr ~= pv_tr then pv_tr = vtr; pv_clear(); BR.preview_stop() end   -- ((⚪178) a project found: a picture item left in it taken away)
  local ai = slot_item(slot)
  if ai and ps & 4 == 0 then pos = math.max(ai[1] + frame_s * 0.5, math.min(ai[1] + ai[2] - frame_s * 0.5, pos)) end
  -- ((⚪178 stage 5) "play the performance" with REAPER's position in the performance zone: the picture item there
  -- (pv_follow) at REAPER's play position (plus AHEAD while it plays), or the edit cursor while it stands (a standing
  -- REAPER shows the picture there)
  local recording = ps & 4 ~= 0
  local rolling = ps & 5 ~= 0
  if rolling and not was_roll then AHEAD = read_ahead() end
  was_roll = rolling
  local base = ps & 7 ~= 0 and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  local PV = PP and not recording and base >= L.PF_ZONE and base + (rolling and AHEAD or 0) or nil
  follow_now = recording or PV ~= nil
  -- compare with the cursor itself, not with the last value sent: a click on the timeline or a stop after recording
  -- moves the cursor while the head stands still, and the video then stayed on the wrong frame. ((⚪178) "play the
  -- performance" leaves the cursor alone, but for REAPER standing outside the performance zone: there it is on the head)
  if (not PP or (ps & 7 == 0 and not PV)) and (math.abs(pos - last) > 0.002 or math.abs(pos - reaper.GetCursorPosition()) > 0.002) then
    reaper.SetEditCurPos(pos, false, false)
    last = pos
  end
  -- ⚪53 recording: the window shows the record position; the items follow it instead of the cursor
  local P = recording and reaper.GetPlayPosition() + AHEAD or PV
  local a_moved = false
  if recording then a_moved = rec_a_follow(P, slot, head) end
  if PV then a_moved = pv_follow(PV, slot, head) or a_moved elseif pv then pv_drop() end
  local xf = P_XF and reaper.TrackFX_GetParam(tr, fx, P_XF) or 1
  if trB then
    -- the cursor as it really is (it moves only when deck A moves more than 2 ms): placing B from `pos` left B's frame
    -- up to 2 ms off, and a stopped deck B near a frame edge flickered between two frames (user's report, 2026-10-05)
    local b_moved = follow_b(P or reaper.GetCursorPosition())
    -- ((⚪188) a file of the Media Explorer previewed with P: its picture item placed for the same time as deck B's view)
    local p_moved = BR.preview_follow(P or reaper.GetCursorPosition(), not vmuted)
    hide(false)                                      -- with deck B the Video processor on "video" fades / cuts
    redraw_if_still(reaper.GetCursorPosition(), b_moved or a_moved, p_moved)
  else
    BR.preview_follow(reaper.GetCursorPosition(), false)   -- (⚪188: no deck mix, the sound only)
    hide(xf < 0.5)
  end
  if log then
    -- ((⚪151) 0 for a parameter the JSFX does not have: nil stopped the script)
    log:write(string.format("%.3f\t%.4f\t%.2f\t%d\t%.2f\n", t - t0, pos, P_SPD and reaper.TrackFX_GetParam(tr, fx, P_SPD) or 0,
      math.floor(P_TCH and reaper.TrackFX_GetParam(tr, fx, P_TCH) or 0), xf))
    log:flush()
  end
  reaper.defer(tick)
end
tick()

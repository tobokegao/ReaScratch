-- ReaScratch kit: load a video into the scratch project.
--   1. pick a video file (or use the selected item)
--   2. choose the sample slot (1-8): the slot in use if empty, else ask (first empty slot / replace the one in use)
--   3. put it on the "video" track at the slot's place, (slot - 1) x 3600 s (that slot's earlier items on "video" /
--      "audio" are removed)
--   4. render its audio to Data/ReaScratch_samples/<name>.wav (24-bit, project sample rate)
--      and point the slot of the ReaScratch JSFX at that file (it becomes the slot in use, with fresh cues);
--      the WAV also goes on the "audio" track (waveform only)
--   5. offer to re-encode the video to all-keyframe MJPEG (see reascratch_reencode_mjpeg.lua)
-- With deck B (reascratch_setup.lua): the deck is the one whose window was used last, or of the selected video
-- item; otherwise asked. Deck B's videos go on "video B", its WAVs on "audio B", into the JSFX of "scratch engine B".
-- Run reascratch_setup.lua first (tracks + JSFX).

local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")

-- which deck
local deck = 1
local sel = reaper.GetSelectedMediaItem(0, 0)
local sel_tr = sel and reaper.GetMediaItemTrack(sel)
if L.find_engine(2) then
  local _, ftr = reaper.GetFocusedFX2()   -- the FX window used last (also when it lost focus to the action list)
  local ftrack = ftr and ftr > 0 and reaper.GetTrack(0, ftr - 1)
  if L.TEST and L.TEST.deck then
    deck = L.TEST.deck
  elseif sel_tr and sel_tr == L.track_by_name(L.TRACK_VIDEO_B) then
    deck = 2
  elseif sel_tr and sel_tr == L.track_by_name(L.TRACK_VIDEO) then
    deck = 1
  elseif ftrack and ftrack == L.track_by_name(L.TRACK_ENGINE_B) then
    deck = 2
  elseif not (ftrack and ftrack == L.track_by_name(L.TRACK_ENGINE)) then
    local ans = L.choose(L.T("どちらのデッキに入れますか？", "Which deck should it go to?"), { L.T("デッキA", "Deck A"), L.T("デッキB", "Deck B") })
    if ans == 2 then deck = 2 elseif ans ~= 1 then return end
  end
end
local vname, aname = L.deck_tracks(deck)
local video, audio = L.track_by_name(vname), L.track_by_name(aname)
local engine, fx = L.find_engine(deck)
if not (video and audio and engine) then
  local m = L.T("先に reascratch_setup.lua を実行してください（video / audio / scratch engine トラックが要ります）",
    "Run reascratch_setup.lua first (it needs the video / audio / scratch engine tracks).")
  L.log(m) L.msgbox(m) return
end

-- source file, and the sample slot (1-8) it goes to
local names, cur = L.engine_samples(engine)
local path, slot
if L.TEST and L.TEST.video then
  path, slot = L.TEST.video, L.TEST.slot or cur
elseif sel and reaper.GetMediaItemTrack(sel) == video then
  -- a video already on the "video" track: import it again into its own slot
  -- ((⚪151) an empty item (no take) stopped the script with an error)
  local tk = reaper.GetActiveTake(sel)
  local src = tk and reaper.GetMediaItemTake_Source(tk)
  if not src then
    local m = L.T("選んだアイテムに動画がありません（空のアイテム）", "The selected item has no video (an empty item).")
    L.log(m) L.msgbox(m) return
  end
  path = reaper.GetMediaSourceFileName(src, "")
  slot = math.max(1, math.min(L.SLOTS, math.floor(reaper.GetMediaItemInfo_Value(sel, "D_POSITION") / L.SLOT_SPAN + 0.001) + 1))
else
  -- the slot in use if it is empty; else ask: the first empty slot, or replace the one in use
  slot = cur
  if names[cur] then
    local empty
    for k = 1, L.SLOTS do if not names[k] then empty = k break end end
    if empty then
      local ans = L.msgbox(string.format(L.T("いまの素材 %d（%s）は使用中です。\n\n" ..
        "「はい」: 空いている素材 %d に入れる\n「いいえ」: 素材 %d を差し替える",
        "The current slot %d (%s) is in use.\n\nYes: put it in the empty slot %d\nNo: replace slot %d"), cur, names[cur], empty, cur), "ReaScratch", 3)
      if ans == 6 then slot = empty elseif ans ~= 7 then return end
    elseif L.msgbox(string.format(L.T("素材 1〜%d はすべて使用中です。\nいまの素材 %d（%s）を差し替えますか？",
        "Slots 1-%d are all in use.\nReplace the current slot %d (%s)?"), L.SLOTS, cur, names[cur]),
        "ReaScratch", 4) ~= 6 then
      return
    end
  end
  local ok, f = reaper.GetUserFileNameForRead("", string.format(L.T("ReaScratch: %s素材 %d に入れる動画ファイルを選ぶ", "ReaScratch: choose the video for %sslot %d"), deck == 2 and L.T("デッキBの", "deck B ") or "", slot), "")
  if not ok then return end
  path = f
end
if not reaper.file_exists(path) then L.log("file not found: " .. path) return end
local name = L.stem(path)
local start = L.slot_start(slot)

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
L.clear_items(video, start, start + L.SLOT_SPAN)
L.clear_items(audio, start, start + L.SLOT_SPAN)
local item = L.insert_on_track(video, path, start)
if not item then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ReaScratch import", -1)
  L.log("could not insert " .. path)
  return
end
reaper.PreventUIRefresh(-1)

-- audio -> WAV in the sample folder
reaper.RecursiveCreateDirectory(L.SAMPLE_DIR, 0)
L.ensure_empty_wav()   -- what an empty sample slot points at (setup writes it too)
reaper.SelectAllMediaItems(0, false)
reaper.SetMediaItemSelected(item, true)
-- a WAV of the same name (an earlier import of this video, or another video with the same name) is replaced:
-- otherwise REAPER asks, and "Increment filenames" would write name-001.wav while the JSFX loads the old name.wav.
-- One that cannot be removed is in use (the same video on the other deck or in another slot: its audio item holds
-- it) -> the next free name_2.wav, name_3.wav ... (before, ffmpeg and REAPER's render both failed and the render
-- window stopped at "Can't create file", ⚪33)
local wname = name
local wav = L.SAMPLE_DIR .. L.SEP .. wname .. ".wav"
local wn = 1
while reaper.file_exists(wav) and not os.remove(wav) and wn < 99 do
  wn = wn + 1; wname = name .. "_" .. wn; wav = L.SAMPLE_DIR .. L.SEP .. wname .. ".wav"
end
-- ffmpeg first (as for the MJPEG conversion): REAPER's render can be disturbed by whatever else runs in REAPER
-- (a WAV came out silent from 8.3 s on, 2026-10-03). Without ffmpeg, or when it fails: REAPER's render.
local wav_by
local ffmpeg = L.find_ffmpeg(HERE)
if ffmpeg then
  local ok, err = L.ffmpeg_wav(ffmpeg, path, wav)
  if ok then
    wav_by = "ffmpeg"
  else
    L.log("ffmpeg could not write the audio (" .. tostring(err) .. ") -> REAPER's renderer instead")
    if reaper.file_exists(wav) then os.remove(wav) end
  end
end
if not wav_by then
  L.render_selected_items(L.SAMPLE_DIR, wname, L.CFG_WAV24)
  wav_by = "REAPER"
end
if not reaper.file_exists(wav) then
  reaper.Undo_EndBlock("ReaScratch import", -1)
  local m = L.T("音声の書き出しに失敗しました: ", "Could not export the audio: ") .. wav
  L.log(m) L.msgbox(m)
  return
end
reaper.PreventUIRefresh(1)
L.insert_on_track(audio, wav, start)
reaper.SetMediaTrackInfo_Value(audio, "B_MUTE", 1)
L.set_engine_sample(engine, wname .. ".wav", slot)
engine, fx = L.find_engine(deck)                   -- chunk replaced: re-resolve
-- switch to the slot (stores the slot left), then forget the slot's old cues (a new file); the values below are its own
if fx then
  L.set_param(engine, fx, "Sample slot", slot)
  L.set_param(engine, fx, "Clear sample cues", slot)
  -- (the CUE: where the sound starts, set by the JSFX when it clears the slot; 2026-10-13)
end
-- tempo and beat grid for the beat-synced jumps. JSFX sliders take their own values through TrackFX_SetParam
-- (not 0..1). Unsure (tempo changes, no steady beat) -> BPM stays 0 = unknown and the user is told how to set it;
-- no estimate at all (shorter than 4 s, silent) -> only the log. (⚪179) found by L.analyse_sample, as LOAD does:
-- (⚪175) the musical key, (⚪177) rekordbox's values (they win over the estimates), (⚪176) a tempo that moves: the
-- slot's beat map (not over rekordbox's grid)
local beat_unsure = false                          -- said after the undo block (not while the UI refresh is held)
if fx then
  local a = L.analyse_sample(wav, { path, wav })
  L.set_param(engine, fx, "BPM", a.bpm)
  L.set_param(engine, fx, "Beat grid", a.grid)
  if a.sure then
    L.log(string.format("tempo: %.2f BPM, beat at %.4f s (confidence %.2f, %.1f s)", a.est, a.est_grid, a.conf, a.t_beat) .. L.bpm_note(a.est, a.bdur))
  else
    L.log(a.est and string.format("tempo: unsure (%.2f BPM, beat at %.4f s, confidence %.2f, %.1f s) -> BPM left at 0",
      a.est, a.est_grid, a.conf, a.t_beat) or string.format("tempo: could not estimate (%.1f s) -> BPM left at 0", a.t_beat))
  end
  L.set_key(engine, fx, slot, L.key_code(a.key, a.lead))
  L.set_loudness(engine, fx, slot, a.lufs, a.peak)   -- (⚪185 auto gain)
  L.log(a.lufs and string.format("loudness: %.1f LUFS, peak %.1f dBFS (%.1f s)", a.lufs, a.peak, a.t_loud) or "loudness: could not measure")
  L.log(a.key and string.format("key: %s (lead %.4f, %.1f s)", L.key_name(L.key_code(a.key, a.lead)), a.lead, a.t_key)
    or string.format("key: could not estimate (%.1f s)", a.t_key))
  if a.rb then
    L.rb_send(engine, fx, slot, a.rb)
    L.log(L.rb_summary(a.rb))
  elseif a.why ~= "no rekordbox XML chosen" then
    L.log("rekordbox: " .. a.why)
  end
  if a.map then
    L.gb_send(engine, fx, slot, a.map)
    L.log(string.format("tempo moves: a beat map of %d marks (%s, %.1f s)", #a.map, a.minfo, a.t_map))
  elseif a.t_map then
    L.log(string.format("beat map: %s (%.1f s)", tostring(a.minfo), a.t_map))
  end
  beat_unsure = a.unsure
end
reaper.SelectAllMediaItems(0, false)
reaper.SetMediaItemSelected(item, true)
reaper.SetEditCurPos(start, false, false)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("ReaScratch import " .. name, -1)
L.log("video: " .. path)
L.log("audio: " .. wav .. " (" .. tostring(L.file_size(wav)) .. " bytes, by " .. wav_by .. ") -> JSFX sample " .. slot .. (deck == 2 and " of deck B" or ""))
if beat_unsure then
  L.msgbox(L.T("BPMを推定できませんでした。setupで入れるか、再生中にTキーを拍に合わせて叩いてください。",
    "Could not detect the BPM. Enter it on the setup page, or tap T on the beat while playing."), "ReaScratch", 0)
end

-- does the sound stop long before the end? (more than 5 s and more than a tenth of the length of pure silence at the
-- end: a render that was cut short looks like this; a video that really ends in silence does too, so only say so)
local total, sound_end = L.wav_sound_end(wav)
if total and total - sound_end > math.max(5, total * 0.1) then
  L.log(string.format("silent from %s to the end (%s)", L.mmss(sound_end), L.mmss(total)))
  L.msgbox(string.format(L.T("取り込んだ音が %s から最後（%s）まで無音です。\n" ..
    "元の動画でもそこから無音なら問題ありません。\n" ..
    "音があるはずなら、書き出しが途中で止まっています。もう一度取り込んでください。",
    "The imported audio is silent from %s to the end (%s).\n" ..
    "That is fine if the original video is silent there too.\n" ..
    "If there should be sound, the export stopped partway. Import it again."), L.mmss(sound_end), L.mmss(total)),
    "ReaScratch", 0)
end

-- longer than the JSFX memory holds (it depends on the REAPER version)? The JSFX keeps the start: say so.
local cut = L.too_long(engine, fx, wav, slot)
if cut then
  L.log(string.format("too long: only the first %s of %s is loaded", L.mmss(cut.keep), L.mmss(cut.total)))
  L.msgbox(string.format(L.T("曲が長すぎるため、最初の %s だけ読み込みました（全体は %s）。\n" ..
    "続きをスクラッチするには、動画を短く切ってから取り込んでください。",
    "The track is too long, so only the first %s was loaded (total %s).\n" ..
    "To scratch the rest, cut the video shorter and import it again."), L.mmss(cut.keep), L.mmss(cut.total)),
    "ReaScratch", 0)
end

-- all-keyframe re-encode? Check the file first: no question when it is already all-keyframe.
local all_intra, why = L.keyframe_info(path)
L.log("keyframes: " .. tostring(why))
local vw, vh = L.video_info(path)
local max_h = L.video_height()   -- this PC's height (setup); the answer below can change it for this video
-- yes -> ask the height, then convert at that height (Cancel = no conversion)
local function convert()
  local h = L.ask_video_height(L.T("ReaScratch: この動画を変換する高さ", "ReaScratch: height to convert this video to"))
  if not h then L.log("conversion cancelled") return end
  REASCRATCH_REENCODE_HEIGHT = h
  dofile(HERE .. "reascratch_reencode_mjpeg.lua")
  REASCRATCH_REENCODE_HEIGHT = nil
end
if all_intra and vh and vh > max_h then
  -- all-keyframe but large (1920x1080): decoding it and the deck mix at that size were too slow (2026-10-04: a
  -- 1080p60 video made the per-pixel blends draw 15-22 frames/s). The conversion also scales it down.
  L.log(string.format("all-keyframe but %dx%d: offering the %dp conversion", vw, vh, max_h))
  local ans = L.msgbox(string.format(L.T("この動画はすでに全コマキーフレームですが、大きい動画です（%dx%d）。\n\n" ..
    "小さい全コマキーフレーム (AVI/MJPEG) に縮めて変換し、差し替えますか？\n" ..
    "動画の表示とデッキBとの重ね合わせが軽くなります。元のファイルは残ります。\n" ..
    "「はい」のあとで高さ（720 / 540 / 360）を選びます。",
    "This video is already all keyframes, but it is large (%dx%d).\n\n" ..
    "Convert it to a smaller all-keyframe video (AVI/MJPEG) and replace it?\n" ..
    "Showing it and mixing it with deck B gets lighter. The original file is kept.\n" ..
    "After Yes you choose the height (720 / 540 / 360)."), vw, vh), "ReaScratch", 4)
  if ans == 6 then convert() end
elseif all_intra then
  L.log("already all-keyframe: no conversion needed")
  L.msgbox(L.T("この動画はすでに全コマキーフレームです（", "This video is already all keyframes (") .. why .. L.T("）。\n変換は不要です。", ").\nNo conversion needed."), "ReaScratch", 0)
else
  local state = (all_intra == false) and (L.T("全コマキーフレームではありません（", "Not all frames are keyframes (") .. why .. L.T("）。", ")."))
    or (L.T("全コマキーフレームか判定できませんでした（", "Could not tell whether all frames are keyframes (") .. why .. L.T("）。", ")."))
  local ans = L.msgbox(state .. L.T("\n\n全コマキーフレーム (AVI/MJPEG) に変換して差し替えますか？\n" ..
    "スクラッチ中のコマ送りが軽くなります。元のファイルは残ります。\n" ..
    "「はい」のあとで高さ（720 / 540 / 360）を選びます。",
    "\n\nConvert it to all keyframes (AVI/MJPEG) and replace it?\n" ..
    "Frame stepping while scratching gets lighter. The original file is kept.\n" ..
    "After Yes you choose the height (720 / 540 / 360)."), "ReaScratch", 4)
  if ans == 6 then convert() end
end

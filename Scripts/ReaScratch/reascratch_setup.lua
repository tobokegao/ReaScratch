-- ReaScratch kit: set up the current project for ReaScratch.
--   * checks that the JSFX is installed (Effects/ReaScratch/reascratch.jsfx)
--   * registers the other kit scripts in the action list (Main section)
--   * scrub speed limit back to 1.0x (needs SWS; otherwise it is left alone)
--   * tracks "video", "audio" (muted: the JSFX makes the sound) and "scratch engine"
--     with the JSFX, MIDI input = the DJ controller (all channels), monitoring on
--   * deck B, if wanted (asked once per project): "video B" / "audio B" (muted), "scratch engine B" (JSFX with
--     Deck = B, the other crossfader side), "video B view" right above "video" (the video sync moves its one item),
--     and a Video processor on "video" that mixes the two decks (reascratch_deck_mix.eel)
--   * a "Cue" track for the headphones (each deck's cue + the main, the Cue mix knob), out to the output picked before, named
--     like headphones (Phones), or one picked from a list (kept in REAPER); the decks get 6 channels (5/6 = the cue)
--   * asks whether the video sync should start by itself whenever REAPER starts: Yes adds a short block to
--     Scripts/__startup.lua (REAPER runs that file at every start) and starts the sync now; No removes it
--   * the language of the kit's messages (Auto = REAPER's language pack / English / 日本語), asked first; kept in REAPER
--   * asks whether to use the ReaScratch window layout (⚪100): the kit's buttons on toolbar 3, and a window set "ReaScratch"
--     (Data/ReaScratch/reascratch_screenset.ini: the toolbar at the top left, the video at the top right at 16:9), loaded
--     by the user after restarting REAPER (REAPER reads window sets at start only)
-- Run it again any time: existing tracks are reused, the JSFX is re-added so an edited .jsfx recompiles.

local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")

local function fail(msg)
  L.log(msg)
  L.msgbox(msg, "ReaScratch setup")
end

local jsfx_path = L.RES .. L.SEP .. "Effects" .. L.SEP .. "ReaScratch" .. L.SEP .. "reascratch.jsfx"
if not reaper.file_exists(jsfx_path) then
  return fail(L.T("JSFX が見つかりません:\n", "JSFX not found:\n") .. jsfx_path .. L.T("\n\nキットの Effects フォルダを REAPER の設定フォルダ\n(", "\n\nCopy the kit's Effects folder into REAPER's resource folder\n(") .. L.RES
    .. L.T(")\nにコピーしてから、もう一度実行してください。\n（設定フォルダは Options > Show REAPER resource path で開けます）",
           ")\nand run this again.\n(Options > Show REAPER resource path opens that folder)"))
end
reaper.RecursiveCreateDirectory(L.SAMPLE_DIR, 0)
L.ensure_empty_wav()   -- what an empty sample slot points at
loadfile(HERE .. "reascratch_browser.lua")(L).ensure_files()   -- the slots' own files for LOAD (⚪78): listed by the JSFX added below

-- scripts into the action list, and their command names ("_RS..." - they hang on where the kit is, so the toolbar
-- below is made here, not shipped). ((⚪179) one list: the names were asked for by adding the scripts a second time)
local CMD, ids = {}, {}
for _, name in ipairs({ "reascratch_import_video.lua", "reascratch_reencode_mjpeg.lua", "reascratch_video_sync.lua", "reascratch_load_test.lua", "reascratch_pattern.lua", "reascratch_pattern_save.lua", "reascratch_record_lanes.lua", "reascratch_lanes.lua", "reascratch_perf_play.lua", "reascratch_perf_play_decks.lua", "reascratch_take.lua", "reascratch_video_reopen.lua", "reascratch_rekordbox.lua", "reascratch_export.lua", "reascratch_setup.lua" }) do
  local p = HERE .. name
  if reaper.file_exists(p) then ids[name] = reaper.AddRemoveReaScript(true, 0, p, false) end
end
reaper.AddRemoveReaScript(true, 0, HERE .. "reascratch_setup.lua", true)
for name, id in pairs(ids) do
  local nm = id > 0 and reaper.ReverseNamedCommandLookup(id)
  CMD[name] = nm and nm ~= "" and ("_" .. nm) or nil
end

-- language of the kit's messages (public release, 2026-10-08): REAPER's ExtState ReaScratch / lang, all projects.
-- Asked at every setup run like the video height; the current choice is checked, closing the menu keeps it
if not L.TEST then
  local cur = L.lang_setting()
  local auto = L.auto_lang() == "ja" and "日本語" or "English"
  local k = L.choose(L.T("言語 / Language（ReaScratch のメッセージ）", "Language / 言語 (ReaScratch messages)"), {
    (cur == "auto" and "!" or "") .. L.T("自動（REAPER の言語パックに合わせる: ", "Auto (follows REAPER's language pack: ") .. auto .. L.T("）", ")"),
    (cur == "en" and "!" or "") .. "English",
    (cur == "ja" and "!" or "") .. "日本語" })
  if k >= 1 then L.set_lang(({ "auto", "en", "ja" })[k]) end
  L.log("language: " .. L.lang_setting() .. " (" .. L.lang() .. ")")
end

-- scrub speed limit (bit 4 of scrubmode = "limit scrub speed to 1.0x" off)
if reaper.SNM_GetIntConfigVar then
  local m = reaper.SNM_GetIntConfigVar("scrubmode", -1)
  if m >= 0 and (m & 4) ~= 0 then
    reaper.SNM_SetIntConfigVar("scrubmode", m & ~4)
    -- ((env notes, 2026-10-17) a REAPER-wide setting: said so, with where to turn it back)
    L.log("REAPER setting changed (all projects): Preferences > Scrub/Jog > 'Limit scrub rate to 1.0x' turned off (scrubmode "
      .. m .. " -> " .. (m & ~4) .. ")")
  end
end

-- MIDI input: all MIDI inputs, all channels (the JSFX filters by channel / CC number via its Preset),
-- so switching between controllers needs no track input change. Devices must be enabled in
-- Options > Preferences > Audio > MIDI Inputs.
local midi_dev = 63   -- 63 = "All MIDI inputs"
local devs = {}
for i = 0, reaper.GetNumMIDIInputs() - 1 do
  local ok, name = reaper.GetMIDIInputName(i, "")
  if ok and name ~= "" then devs[#devs + 1] = { idx = i, name = name } end
end

-- MIDI output (⚪76, ⚪77): the JSFX lights a controller's pads and buttons (the presets with lights) through its
-- track's MIDI hardware output: the first enabled output whose name has one of these in it (DJ controllers' port
-- names; not the virtual ports or synths); none = no output (the lights stay as the controller has them). Devices must
-- be enabled in Options > Preferences > Audio > MIDI Devices (as outputs too). Change it in the track's routing window.
-- "ReaScratch LED" first: the HID bridge's port for the lights (Windows: a second loopMIDI port of that name; macOS:
-- the bridge makes it), which must not be an enabled MIDI input (loopMIDI sends it straight back: the lights would
-- come in as button presses)
local LIGHT_NAMES = { "REASCRATCH LED", "APC40", "BUDDY", "READY", "DDJ", "XDJ", "MIXON", "BEATMIX", "BEATPAD", "TERMINAL MIX", "MIXAGE",
  "MIXTRACK", "PARTY MIX", "PARTYMIX", "DJ2GO", "INPULSE", "DJCONTROL", "DJ CONTROL", "DJ CONSOLE", "PRIME", "SC5000",
  "SC6000", "KAOSS", "CMD MICRO", "FIRSTMIX", "DISCOVER" }
local midi_out, midi_out_name = -1, nil
for i = 0, reaper.GetNumMIDIOutputs() - 1 do
  local ok, name = reaper.GetMIDIOutputName(i, "")
  if midi_out < 0 and ok then
    for _, k in ipairs(LIGHT_NAMES) do
      if name:upper():find(k, 1, true) then midi_out, midi_out_name = i, name break end
    end
  end
end

-- deck B (a second JSFX + its tracks, mixed into the video by a Video processor on "video"): asked once per project
-- while there is none (No is remembered in the project); once made, every setup run renews it like deck A
local has_b = L.track_by_name(L.TRACK_ENGINE_B) ~= nil
local want_b = has_b
if not has_b then
  local _, no_b = reaper.GetProjExtState(0, "ReaScratch", "no_deck_b")
  if L.TEST and L.TEST.deck_b ~= nil then
    want_b = L.TEST.deck_b
  elseif no_b ~= "1" then
    want_b = L.msgbox(L.T("2つ目のデッキ（デッキB）を作りますか？\n\n"
      .. "クロスフェーダーで2つのデッキの音と映像を移せるようになります（映像は Video processor で重ねます）。\n"
      .. "「いいえ」はこのプロジェクトでは覚えておき、もう聞きません（作るときは setup の前に\n"
      .. "「scratch engine B」という名前のトラックを作ってください）。",
      "Make a second deck (deck B)?\n\n"
      .. "The crossfader then moves between the two decks' sound and picture (the pictures are mixed by a Video processor).\n"
      .. "No is remembered in this project and not asked again (to make it later, create a track named\n"
      .. "\"scratch engine B\" before running setup)."), "ReaScratch setup", 4) == 6
    if not want_b then reaper.SetProjExtState(0, "ReaScratch", "no_deck_b", "1") end
  end
end

-- (re)loads the JSFX on an engine track; nil when the JSFX could not be loaded.
-- A deck already there (⚪60, 2026-10-07): the FX is taken out and the track's own chunk put back, so REAPER builds the FX
-- again from the .jsfx on disk (an edited file recompiles, new sliders get their defaults) while every slider value, the
-- stored state (memory cues, each sample's values, hot cues 5-8) and the envelopes on its parameters stay. (Setting the
-- same chunk alone does not rebuild it.) Until then the FX was deleted and added anew with only the samples carried over:
-- the preset, BPM, crossfader settings, ... went back to the defaults and the envelopes were lost.
local function setup_engine(engine, deck)
  local old = L.engine_fx(engine)
  local fx
  if old then
    local samples, slot = L.engine_samples(engine)   -- (only for the fallback below)
    local ok, chunk = reaper.GetTrackStateChunk(engine, "", false)
    reaper.TrackFX_Delete(engine, old)
    if ok then reaper.SetTrackStateChunk(engine, chunk, false) end
    fx = L.engine_fx(engine)
    if not fx then   -- could not be rebuilt from the chunk: a new one, with the samples
      fx = reaper.TrackFX_AddByName(engine, "JS:" .. L.JSFX, false, 1)
      if fx < 0 then return nil end
      L.set_param(engine, fx, "Deck (", deck)
      if samples and next(samples) then L.set_engine_samples(engine, samples, slot) end
      fx = L.engine_fx(engine)
    end
    L.set_param(engine, fx, "Deck (", deck)
    if deck == 1 and want_b and not has_b then L.set_param(engine, fx, "Layout", 1) end   -- deck B made now: A goes left-handed
  else
    fx = reaper.TrackFX_AddByName(engine, "JS:" .. L.JSFX, false, 1)
    if fx < 0 then return nil end
    L.set_param(engine, fx, "Deck (", deck)
    -- layout of the front page (a new deck only; a deck already there keeps the one chosen): with deck B, deck A
    -- left-handed (record on the left) and deck B right-handed (record on the right), so two windows side by side have
    -- the records outside; deck A alone stays right-handed (user's choice, 2026-10-04: first A right / B left, then
    -- swapped, then one deck right-handed; either can be changed on the setup page)
    L.set_param(engine, fx, "Layout", (deck == 1 and want_b) and 1 or 0)
  end
  L.set_want_all_keys(engine, true)   -- keys reach the JSFX (Space would otherwise start REAPER's transport)
  if midi_dev then
    reaper.SetMediaTrackInfo_Value(engine, "I_RECINPUT", 4096 + (midi_dev << 5))  -- MIDI, all channels
    reaper.SetMediaTrackInfo_Value(engine, "I_RECMODE", 2)                        -- record disabled (monitor only)
    reaper.SetMediaTrackInfo_Value(engine, "I_RECARM", 1)
    reaper.SetMediaTrackInfo_Value(engine, "I_RECMON", 1)
  end
  -- lights (⚪76): (⚪109) the output of the deck's Preset's controller when there is one (L.preset_output), else the first
  -- DJ controller found
  local efx = L.engine_fx(engine)
  local pi = efx and L.param_index(engine, efx, "Preset")
  local pout = pi and L.preset_output(select(2, reaper.TrackFX_GetFormattedParamValue(engine, efx, pi, "")))
  local out = pout or midi_out
  reaper.SetMediaTrackInfo_Value(engine, "I_MIDIHWOUT", out >= 0 and (out << 5) or -1)
  return efx
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local video = L.ensure_track(L.TRACK_VIDEO)
local audio = L.ensure_track(L.TRACK_AUDIO)
reaper.SetMediaTrackInfo_Value(audio, "B_MUTE", 1)
local engine = L.ensure_track(L.TRACK_ENGINE)
local fx = setup_engine(engine, 1)
if not fx then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ReaScratch setup", -1)
  return fail(L.T("JSFX を読み込めませんでした: JS:", "Could not load the JSFX: JS:") .. L.JSFX)
end

if want_b then
  local video_b = L.ensure_track(L.TRACK_VIDEO_B)
  local audio_b = L.ensure_track(L.TRACK_AUDIO_B)
  reaper.SetMediaTrackInfo_Value(video_b, "B_MUTE", 1)   -- shown through "video B view" only
  reaper.SetMediaTrackInfo_Value(audio_b, "B_MUTE", 1)
  local engine_b, new_b = L.ensure_track(L.TRACK_ENGINE_B)
  new_b = new_b or not L.engine_fx(engine_b)
  local fx_b = setup_engine(engine_b, 2)
  -- the view track goes right next to "video": above it when REAPER lays lower tracks over upper ones, below it when
  -- the project's video setting lets the upper track win (⚪54); the mix on "video" takes it as deck B
  local view = L.ensure_track(L.TRACK_VIEW_B)
  L.place_view_b(video, view)
  if fx_b and new_b then
    -- a new deck B: the other side of the crossfader, the same fade as deck A; FLX4 / FLX2 / Reloop Buddy / CDJ deck 1 -> deck 2
    local function get(label) local p = L.param_index(engine, fx, label) return p and reaper.TrackFX_GetParam(engine, fx, p) end
    -- by the name: the presets are listed by maker (2026-10-08), each "... deck 1" / "(MIDI ch 1)" right before its deck 2
    local pre = math.floor((get("Preset") or 0) + 0.5)
    local pp = L.param_index(engine, fx, "Preset")
    local _, pname = reaper.TrackFX_GetFormattedParamValue(engine, fx, pp or 0, "")
    if pp and (pname:match("deck 1$") or pname:match("%(MIDI ch 1%)$")) then L.set_param(engine_b, fx_b, "Preset", pre + 1) end
    local side = math.floor((get("Crossfader side") or 0) + 0.5)
    if side == 0 then side = 1; L.set_param(engine, fx, "Crossfader side", 1) end
    L.set_param(engine_b, fx_b, "Crossfader side", side == 1 and 2 or 1)
    for _, label in ipairs({ "Cut-in", "Fade width", "Fade curve" }) do
      local v = get(label)
      if v then L.set_param(engine_b, fx_b, label, v) end
    end
    -- video FX knob: the same channel; with a hand-set (Custom) CC, deck B takes the next one (as FLX4 CFX 23 -> 24)
    local ch, cc = get("Video FX MIDI channel"), get("Video FX CC")
    if ch then L.set_param(engine_b, fx_b, "Video FX MIDI channel", ch) end
    if cc and cc > 0 and cc < 127 and math.floor((get("Preset") or 0) + 0.5) == 0 then L.set_param(engine_b, fx_b, "Video FX CC", cc + 1) end
  end
  if not L.install_deck_mix(video, HERE .. "reascratch_deck_mix.eel") then
    L.log("could not put the deck mix Video processor on the video track")
  end
end
-- (⚪178) the performance lanes (reascratch_perf.jsfx) right before each deck's engine (kept when there)
for deck = 1, 2 do
  local e = L.find_engine(deck)
  if e and not L.perf_ensure(e, deck) then L.log("could not put the performance lanes JSFX on deck " .. (deck == 2 and "B" or "A")) end
end
-- (⚪110) a deck's "2nd controller" set: the two controllers' tracks and routing (the video sync keeps them so too)
do
  local ea, fa = L.find_engine(1)
  local eb, fb = L.find_engine(2)
  local _, _, cx_msg = L.cx_apply({ { ea, fa }, { eb, fb } })
  if cx_msg then L.log(cx_msg) end
end
-- headphone cue: the "Cue" track (decks' cue + main, the Cue mix knob) straight to the headphone output
local _, cue_out = L.cue_prepare()
reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.Undo_EndBlock("ReaScratch setup", -1)

if cue_out then
  L.log("cue: the \"Cue\" track goes to " .. cue_out)
else
  L.log("cue: no headphone output found")
  L.msgbox(L.T("ヘッドホンでデッキの音を聴く（Cue）ための「Cue」トラックを作りましたが、ヘッドホンの出力が選ばれていません"
    .. "（出力の一覧で選ばなかったか、オーディオの出力がありません）。\n\n"
    .. "「Cue」トラックの[ROUTE]ボタンから、ヘッドホンにつながる出力（Hardware output）を選んでください。",
    "The \"Cue\" track for listening to the decks in your headphones was made, but no headphone output is set"
    .. " (none was picked from the list, or there is no audio output).\n\n"
    .. "Pick the output your headphones are on (Hardware output) with the [ROUTE] button of the \"Cue\" track."), "ReaScratch setup", 0)
end
local names = {}
for _, d in ipairs(devs) do names[#names + 1] = d.name end

-- this PC's height for the all-keyframe conversion (kept in REAPER, all projects); Cancel keeps it
local vh = L.ask_video_height(L.T("ReaScratch setup: 変換する動画の高さ（小さいほど軽い・粗い）", "ReaScratch setup: video conversion height (smaller = lighter, coarser)"))
if vh then L.set_video_height(vh) end
L.log("video conversion height: " .. L.video_height() .. "p (this PC)")

-- ⚪56 / ⚪33 REAPER draws the video ahead and keeps it (the Video processor reads the crossfader then): with the video
-- FX cached, the crossfader / effects showed up late - while REAPER plays or records by the video cache (1 s by
-- default), and while the decks play (REAPER stopped) 0.2-0.5 s even with a 0.1 s cache (measured 2026-10-06 in the
-- user's REAPER; "All media and video FX are not cached": 0.07 s). L.video_cache reads both
local vcache, vmode = L.video_cache()
vmode = vmode or 1                                  -- (not set = 1, the default)
if vmode ~= 3 then
  L.msgbox(L.T("REAPERが映像を先に描いてためておく設定になっています。\n\n"
    .. "このままだと、クロスフェーダーや映像エフェクトが画面に出るのが 0.2〜0.5秒ほど遅れます（デッキの再生中も）。\n\n"
    .. "動画の窓（View > Video、日本語の画面では 表示 > ビデオ）を右クリックし、「Performance tweaks (experimental)」（パフォーマンス調整）→"
    .. "「Video cache」（ビデオキャッシュ）→「All media and video FX are not cached」（すべてのメディアおよびビデオFXはキャッシュされません）"
    .. "を選んでください（すぐに効きます。REAPERを起動し直す必要はありません）。",
    "REAPER is set to draw the video ahead and cache it.\n\n"
    .. "With this, the crossfader and video effects show up about 0.2-0.5 s late (also while the decks play).\n\n"
    .. "Right-click the video window (View > Video) and choose \"Performance tweaks (experimental)\" > "
    .. "\"Video cache\" > \"All media and video FX are not cached\" "
    .. "(it works at once; no need to restart REAPER)."),
    "ReaScratch setup", 0)
end
L.log(("video cache: %.2g s, fx mode %d%s"):format(vcache, vmode, vmode ~= 3 and " (cached: the crossfader shows late)" or ""))
-- ((⚪178 stage 6) REAPER stopping at the project's end: the performance lanes' zone could not be played)
if L.stop_at_end_on() then
  L.msgbox(L.T(L.STOP_AT_END_MSG[1], L.STOP_AT_END_MSG[2]), "ReaScratch setup", 0)
  L.log("stop at the end of the project: on (the performance lanes cannot be played)")
end

-- ((⚪185) auto gain) the loudness of every sample in the decks' slots, for samples that came in before auto gain (the
-- import and LOAD measure new ones): measured and sent to the JSFX one by one (each takes about a second, so the JSFX
-- has read the last one before the next is sent)
for deck = 1, 2 do
  local tr, fx = L.find_engine(deck)
  if tr and fx then
    for k, name in pairs((L.engine_samples(tr))) do
      local path = L.SAMPLE_DIR .. L.SEP .. name
      if reaper.file_exists(path) then
        local lufs, peak, sec = L.estimate_loudness(path)
        L.set_loudness(tr, fx, k, lufs, peak)
        local t = reaper.time_precise() while reaper.time_precise() - t < 0.1 do end   -- (at least a few audio blocks apart)
        L.log(lufs and ("auto gain: deck %s slot %d %s: %.1f LUFS, peak %.1f dBFS (%.1f s)"):format(deck == 2 and "B" or "A", k, name, lufs, peak, sec)
          or ("auto gain: deck %s slot %d %s: could not measure"):format(deck == 2 and "B" or "A", k, name))
      end
    end
  end
end

-- video sync at REAPER start: a marked block in Scripts/__startup.lua (other content of that file is kept)
local BEGIN, END = "-- >>> ReaScratch autostart", "-- <<< ReaScratch autostart"
local startup = L.RES .. L.SEP .. "Scripts" .. L.SEP .. "__startup.lua"
local function read_all(p) return L.read_file(p) or "" end
local old_text = read_all(startup)
local a, b = old_text:find(BEGIN, 1, true), select(2, old_text:find(END, 1, true))
local body = old_text
if a and b then body = (old_text:sub(1, a - 1):gsub("%s*$", "")) .. "\n" .. (old_text:sub(b + 1):gsub("^%s*", "")) end
local sync = HERE .. "reascratch_video_sync.lua"
local yes = L.msgbox(L.T("REAPER を起動したときに、動画の同期（reascratch_video_sync.lua）を自動で始めますか？\n\n"
  .. "「はい」: REAPER の Scripts/__startup.lua に起動用の数行を足し、今すぐ同期も始めます。"
  .. "ReaScratch の入っていないプロジェクトでは何もしません。\n"
  .. "「いいえ」: 足した行があれば取り除きます（同期は手で起動します）。",
  "Start the video sync (reascratch_video_sync.lua) automatically when REAPER starts?\n\n"
  .. "Yes: adds a few lines to REAPER's Scripts/__startup.lua and starts the sync now. "
  .. "It does nothing in projects without ReaScratch.\n"
  .. "No: removes those lines if they are there (you start the sync by hand)."), "ReaScratch setup", 4) == 6
if yes then
  body = (body:gsub("%s*$", "")) .. (body:match("%S") and "\n\n" or "")
    .. BEGIN .. " (added by reascratch_setup.lua; run setup again and answer No to remove)\n"
    .. "REASCRATCH_SYNC_ENSURE, REASCRATCH_AUTOSTART = true, true\n"
    -- ((env notes, 2026-10-17) the kit's path is written here: a moved kit or REAPER folder (another drive letter, a
    -- portable REAPER on a USB stick) said so in the console instead of not starting without a word)
    .. "if not pcall(dofile, [[" .. sync .. "]]) then reaper.ShowConsoleMsg(\"ReaScratch: the video sync did not start "
    .. "(the kit moved?). Run reascratch_setup.lua again. / 動画の同期を起動できませんでした（キットの場所が変わった？）。"
    .. "reascratch_setup.lua をもう一度実行してください。\\n\") end\n"
    .. "REASCRATCH_SYNC_ENSURE, REASCRATCH_AUTOSTART = nil, nil\n"
    .. END .. "\n"
end
if body ~= old_text and (yes or a) then
  local f = io.open(startup, "wb")
  if f then f:write(body); f:close() else L.log("could not write " .. startup) end
end
if yes then
  -- ((⚪150) started as its own action, not by dofile: a dofile ran the sync's defer loop as this setup script, so
  -- running setup again stopped the sync or brought up REAPER's "ReaScript task control" dialog. Started only when
  -- its heartbeat is old: an action run again stops a sync that is running)
  local beat = tonumber(reaper.GetExtState("ReaScratch", "video_sync_heartbeat")) or 0
  if reaper.time_precise() - beat >= 1.0 then
    local id = reaper.AddRemoveReaScript(true, 0, sync, true)
    if id > 0 then reaper.Main_OnCommand(id, 0) end
  end
  L.log("video sync: starts with REAPER (" .. startup .. ")")
end
-- (⚪100, user's request 2026-10-09: the author's layout as the kit's default) the ReaScratch window layout. A window
-- layout is REAPER's, not the project's (a template cannot carry it): toolbar 3 gets the kit's 11 buttons (reaper-menu.ini;
-- REAPER reads a toolbar's buttons from there when it opens) and reaper-screensets.ini a window set "ReaScratch" (the kit's
-- copy of the author's), which is then loaded. Someone else's toolbar 3 or window sets are not replaced without asking
local function layout()
  local menu = L.RES .. L.SEP .. "reaper-menu.ini"
  local txt = read_all(menu)
  local a3 = txt:find("[Floating toolbar 3]", 1, true)
  local e3 = a3 and (txt:find("\n%[", a3 + 1) or #txt + 1)
  local others = a3 and not txt:sub(a3, e3):find("title=ReaScratch", 1, true)
  if others and L.msgbox(L.T(
      "ツールバー3には、すでに別のボタンが入っています。ReaScratch のボタンに入れ替えますか？\n\n"
        .. "（前の内容は reaper-menu.ini.before_reascratch に控えます）",
      "Toolbar 3 has other buttons. Replace them with ReaScratch's?\n\n"
        .. "(the old ones are kept in reaper-menu.ini.before_reascratch)"), "ReaScratch setup", 4) ~= 6 then return end
  -- ((env notes, 2026-10-17) someone else's toolbar 3 or window set: the file as it was, kept before it is written)
  local function keep(path, text)
    local k = io.open(path .. ".before_reascratch", "wb")
    if k then k:write(text); k:close(); L.log("kept the old " .. path .. " as " .. path .. ".before_reascratch")
    else L.log("could not write " .. path .. ".before_reascratch") end
  end
  if others then keep(menu, txt) end
  local B = { { "reascratch_setup.lua", "SETUP" }, { "reascratch_import_video.lua", "IMPORT VIDEO" }, { "reascratch_reencode_mjpeg.lua", "MJPEG" },
    { "reascratch_video_sync.lua", "VIDEO SYNC" }, { "reascratch_video_reopen.lua", "VIDEO REOPEN" }, { "reascratch_pattern.lua", "PATTERN" },
    { "reascratch_pattern_save.lua", "PATTERN SAVE" }, { "reascratch_record_lanes.lua", "REC LANES" }, { "reascratch_lanes.lua", "LANES" }, { "reascratch_take.lua", "TAKE" },
    { "reascratch_perf_play.lua", "PERF PLAY" } }
  local sec, n = { "[Floating toolbar 3]" }, 0
  for _, b in ipairs(B) do
    if CMD[b[1]] then sec[#sec + 1] = ("icon_%d=text_wide\nitem_%d=%s %s"):format(n, n, CMD[b[1]], b[2]); n = n + 1 end
  end
  sec[#sec + 1] = "title=ReaScratch\n"
  sec = table.concat(sec, "\n")
  txt = a3 and (txt:sub(1, a3 - 1) .. sec .. txt:sub(e3)) or ((txt:gsub("%s*$", "")) .. (txt:match("%S") and "\n\n" or "") .. sec)
  local f = io.open(menu, "wb"); if not f then L.log("could not write " .. menu) return end
  f:write(txt); f:close()
  -- the window set: the one named ReaScratch, else the first empty one, else #10 if allowed
  local ssp = L.RES .. L.SEP .. "reaper-screensets.ini"
  local ss = read_all(ssp)
  local kit = read_all(L.RES .. L.SEP .. "Data" .. L.SEP .. "ReaScratch" .. L.SEP .. "reascratch_screenset.ini")
  kit = kit:gsub("\r", ""):gsub("^;[^\n]*\n", ""):gsub("\n;[^\n]*", "")
  kit = kit:match("%[sset%d+%]\n(.*)")
  if not kit then L.log("window layout: Data/ReaScratch/reascratch_screenset.ini missing (copy the kit's Data folder)") return end
  local function section(i)
    local a = ss:find("[sset" .. i .. "]", 1, true)
    if not a then return nil end
    return a, (ss:find("\n%[", a + 1) or #ss + 1)
  end
  local slot
  for i = 0, 9 do local a, e = section(i); if a and ss:sub(a, e):find("\nname=ReaScratch\n", 1, true) then slot = i break end end
  for i = 0, 9 do
    if slot then break end
    local a, e = section(i)
    if not a or not ss:sub(a, e):find("\nname=", 1, true) then slot = i end
  end
  if not slot then
    if L.msgbox(L.T("ウィンドウセット #01〜#10 はすべて使われています。#10 を ReaScratch の配置で上書きしますか？\n\n"
          .. "（前の内容は reaper-screensets.ini.before_reascratch に控えます）",
        "Window sets #01-#10 are all in use. Overwrite #10 with ReaScratch's layout?\n\n"
          .. "(the old ones are kept in reaper-screensets.ini.before_reascratch)"), "ReaScratch setup", 4) ~= 6 then return end
    slot = 9
    keep(ssp, ss)
  end
  local new = "[sset" .. slot .. "]\n" .. (kit:gsub("%s*$", "")) .. "\n"
  local a, e = section(slot)
  if a then ss = ss:sub(1, a - 1) .. new .. ss:sub(e) else
    if not ss:find("[screensets]", 1, true) then ss = "[screensets]\nnb=10\n\n" .. ss end
    ss = (ss:gsub("%s*$", "")) .. "\n" .. new
  end
  f = io.open(ssp, "wb"); if not f then L.log("could not write " .. ssp) return end
  f:write(ss); f:close()
  -- REAPER reads its window sets at start only (loading the set now gave the old one: tried in the isolated REAPER;
  -- after a restart it opened toolbar 3 and docked the video), so the user loads it after a restart
  L.log(("window layout: toolbar 3 = ReaScratch's %d buttons, window set #%02d = ReaScratch (load it after restarting REAPER)"):format(n, slot + 1))
  if not L.TEST then
    L.msgbox(L.T(("ReaScratch の配置をウィンドウセット #%02d に入れました。\n\nREAPER を再起動してから、アクション"
        .. "「スクリーンセット: ウィンドウセット #%02d をロード」（または「表示: スクリーンセット/レイアウトを表示」の窓）で読み込んでください。"):format(slot + 1, slot + 1),
      ("ReaScratch's layout is now window set #%02d.\n\nRestart REAPER, then load it with the action "
        .. "\"Screenset: Load window set #%02d\" (or the window of \"View: Show screensets/layouts window\")."):format(slot + 1, slot + 1)), "ReaScratch setup", 0)
  end
end
if L.msgbox(L.T("ReaScratch のウィンドウ配置を使いますか？\n\n"
    .. "左上に ReaScratch のボタン（ツールバー3）、右上に 16:9 のビデオ、などの配置です。\n"
    .. "「はい」: ツールバー3にボタンを入れ、ウィンドウセット「ReaScratch」を足します"
    .. "（REAPER の再起動後に読み込みます。前の配置には「スクリーンセット: ウィンドウセットをロード」で戻せます）。",
    "Use the ReaScratch window layout?\n\n"
    .. "ReaScratch's buttons at the top left (toolbar 3), the video at the top right at 16:9, ...\n"
    .. "Yes: puts the buttons on toolbar 3 and adds a window set \"ReaScratch\" (load it after restarting REAPER; "
    .. "Screenset: Load window set switches back to another layout)."), "ReaScratch setup", 4) == 6 or (L.TEST and L.TEST.layout) then
  layout()
end
L.log("lights (MIDI output): " .. (midi_out_name or "none (no DJ controller among the enabled MIDI outputs)"))
for _, d in ipairs(devs) do
  if d.name:upper():find("REASCRATCH LED", 1, true) then
    L.log("warning: '" .. d.name .. "' is enabled as a MIDI input: disable its input (the HID bridge's lights would come back as button presses)")
    if not L.TEST then
      L.msgbox(L.T("「" .. d.name .. "」が MIDI 入力として有効になっています。\n\n"
        .. "HID ブリッジの明かりがボタンの操作として戻ってきてしまうので、入力だけ無効にしてください\n"
        .. "（Options > Preferences の MIDI 入力の一覧で、このポートの入力を無効に）。出力は有効のままにします。",
        "'" .. d.name .. "' is enabled as a MIDI input.\n\n"
        .. "The HID bridge's lights would come back as button presses: disable its input only\n"
        .. "(Options > Preferences, the list of MIDI inputs: disable this port's input). Keep its output enabled."), "ReaScratch", 0)
    end
  end
end
L.log("setup done. MIDI input = all MIDI inputs (enabled devices: " .. (#names > 0 and table.concat(names, ", ") or "none") .. ")")
L.log("pick your controller with the JSFX 'Preset' slider (FX button on the scratch engine track).")
L.log("next: run 'reascratch_import_video.lua' to load a video.")

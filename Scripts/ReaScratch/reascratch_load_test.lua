-- ReaScratch kit: load test (how well this PC keeps up). For about 40 s: 10 s as things are, then every deck scratches
-- by itself for 30 s (the JSFX's 'Load test' switch: jumps, +-3x scratching, 1x play, and all samples read again once).
-- Meanwhile it counts the audio dropouts (each JSFX's own counter, and what REAPER reports), reads the JSFX's CPU meters and
-- watches how often this script gets to run (long gaps = the screen and the video stall). The result is written to a
-- text file in REAPER's resource folder and shown; testers send that file back. Run it again to stop early.

local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")

local SECTION, KEY = "ReaScratch", "load_test_heartbeat"
-- a running test is sent "stop" and ends; the heartbeat is written when the test starts (after the question) ((⚪151) L.heartbeat_claim)
if not L.heartbeat_claim(KEY, false, false) then return end

local IDLE, LOAD = 10, 30   -- seconds
local TITLE = L.T("ReaScratch 負荷試験", "ReaScratch load test")

local decks = {}
for d = 1, 2 do
  local tr, fx = L.find_engine(d)
  if tr then
    local function p(label) return L.param_index(tr, fx, label) end
    local dk = { name = d == 1 and "A" or "B", tr = tr, fx = fx, p_test = p("Load test"), p_worst = p("CPU worst"),
                 p_avg = p("CPU average"), p_load = p("Sample load time"), p_len = p("File length"), p_fsr = p("File sample rate"),
                 p_xthr = p("Dropout threshold"), p_xn = p("Dropouts (count") }
    decks[#decks + 1] = dk
  end
end
if #decks == 0 then
  L.msgbox(L.T("ReaScratchのデッキが見つかりません。\nsetupを実行して動画を取り込んだプロジェクトで実行してください。",
    "No ReaScratch deck found.\nRun this in a project where setup was run and a video was imported."), TITLE, 0)
  return
end
if not decks[1].p_test or not decks[1].p_worst or not decks[1].p_xn then
  L.msgbox(L.T("JSFXが古いため試験できません。\nキットの Effects フォルダをREAPERの設定フォルダへコピーし直し、setupをもう一度実行してください。",
    "The JSFX is too old for this test.\nCopy the kit's Effects folder into REAPER's resource folder again and run setup again."), TITLE, 0)
  return
end
local function get(dk, p) return p and reaper.TrackFX_GetParam(dk.tr, dk.fx, p) or 0 end
for _, dk in ipairs(decks) do
  if get(dk, dk.p_len) <= 0 then
    L.msgbox(string.format(L.T("デッキ%sに素材が入っていません。\n動画を取り込んでから実行してください（デッキBを使わないときは、デッキBのトラックを消すか、デッキBにも取り込んでください）。",
      "Deck %s has no sample.\nImport a video first (if you do not use deck B, delete deck B's tracks or import into deck B too)."), dk.name), TITLE, 0)
    return
  end
end

local ans = L.msgbox(L.T("負荷試験を始めます（約40秒）。\n\n" ..
  "最初の10秒はそのまま、残りの30秒は各デッキが自動でスクラッチします。\n" ..
  "動画ウィンドウは開いたままにしてください。試験中はマウスやキーに触らないでください。\n\n" ..
  "「はい」: 音を出す（先に音量を下げてください）\n「いいえ」: 音を消して測る\n「キャンセル」: やめる\n\n" ..
  "途中でやめるときは、このスクリプトをもう一度実行します。",
  "Start the load test (about 40 s)?\n\n" ..
  "The first 10 s run as things are; for the other 30 s every deck scratches by itself.\n" ..
  "Keep the video window open. Do not touch the mouse or keys during the test.\n\n" ..
  "Yes: with sound (turn the volume down first)\nNo: measure muted\nCancel: do not start\n\n" ..
  "To stop early, run this script again."), TITLE, 3)
if ans ~= 6 and ans ~= 7 then return end
local master = reaper.GetMasterTrack(0)
local master_mute = reaper.GetMediaTrackInfo_Value(master, "B_MUTE")
if ans == 7 then reaper.SetMediaTrackInfo_Value(master, "B_MUTE", 1) end

-- the JSFX's dropout threshold: the device buffer + 3 ms (WaveOut / DirectSound hand REAPER whole device buffers at once)
local _, bs0 = reaper.GetAudioDeviceInfo("BSIZE", "")
local _, sr0 = reaper.GetAudioDeviceInfo("SRATE", "")
bs0, sr0 = tonumber(bs0) or 0, tonumber(sr0) or 0
local xthr = sr0 > 0 and bs0 / sr0 * 1000 + 3 or 0
local function set_test(on)
  for _, dk in ipairs(decks) do
    if reaper.ValidatePtr2(0, dk.tr, "MediaTrack*") then
      if dk.p_test then reaper.TrackFX_SetParam(dk.tr, dk.fx, dk.p_test, on and 1 or 0) end   -- ((⚪151) only deck A's is checked above)
      if not on and dk.p_xthr then reaper.TrackFX_SetParam(dk.tr, dk.fx, dk.p_xthr, 0) end   -- ((⚪151) nil with an older JSFX)
    end
  end
end
local finished = false
local function restore()
  if finished then return end
  finished = true
  set_test(false)
  reaper.SetMediaTrackInfo_Value(master, "B_MUTE", master_mute)
  reaper.SetExtState(SECTION, KEY, "", false)
end
reaper.atexit(restore)

-- what is measured, per phase (1 = as things are, 2 = scratching by itself)
local ph = { { xrun = 0, mxrun = 0, gap = 0, frames = 0 }, { xrun = 0, mxrun = 0, gap = 0, frames = 0 } }
for _, dk in ipairs(decks) do dk.worst = { 0, 0 }; dk.avg = { 0, 0 }; dk.navg = { 0, 0 }; dk.xn = { 0, 0 } end
for _, dk in ipairs(decks) do
  if dk.p_xthr then reaper.TrackFX_SetParam(dk.tr, dk.fx, dk.p_xthr, xthr) end   -- ((⚪151) nil with an older JSFX)
  dk.xn0 = get(dk, dk.p_xn)
end
local a0, m0 = reaper.GetUnderrunTime()
local last_a, last_m = a0, m0
local t_start = reaper.time_precise()
local t_prev, t_meter = t_start, 0
local phase = 1
local sync_seen = false

local function mmss(sec) return L.mmss and L.mmss(sec) or string.format("%.0f s", sec) end

-- dropouts the JSFX counted in a phase: the most of any deck (a stall delays every deck alike)
local function xruns(i)
  local n = 0
  for _, dk in ipairs(decks) do n = math.max(n, dk.xn[i]) end
  return n
end

local function report(stopped)
  local _, mode = reaper.GetAudioDeviceInfo("MODE", "")
  local _, dev = reaper.GetAudioDeviceInfo("IDENT_OUT", "")
  local _, bs = reaper.GetAudioDeviceInfo("BSIZE", "")
  local _, sr = reaper.GetAudioDeviceInfo("SRATE", "")
  bs, sr = tonumber(bs) or 0, tonumber(sr) or 0
  local o = {}
  local function w(s) o[#o + 1] = s end
  w(L.T("ReaScratch 負荷試験の結果", "ReaScratch load test result") .. (stopped and L.T("（途中でやめた）", " (stopped early)") or ""))
  w(L.T("日時: ", "Date: ") .. os.date("%Y-%m-%d %H:%M"))
  w("REAPER: " .. reaper.GetAppVersion() .. " / OS: " .. reaper.GetOS())
  w("CPU: " .. (os.getenv("PROCESSOR_IDENTIFIER") or L.T("（不明。PCの機種名を書き添えてください）", "(unknown: please add your PC's model name)")) ..
    L.T(" / 論理コア数: ", " / logical cores: ") .. (os.getenv("NUMBER_OF_PROCESSORS") or "?"))
  w(string.format(L.T("音声: %s / %s / バッファ %d サンプル / %d Hz（1回の処理の持ち時間 %.2f ms）", "Audio: %s / %s / buffer %d samples / %d Hz (time per block %.2f ms)"),
    mode or "?", dev or "?", bs, sr, sr > 0 and bs / sr * 1000 or 0))
  for _, dk in ipairs(decks) do
    local fsr = get(dk, dk.p_fsr)
    w(string.format(L.T("デッキ%s: 素材の長さ %s", "Deck %s: sample length %s"), dk.name, fsr > 0 and mmss(get(dk, dk.p_len) / fsr) or "?"))
  end
  w(L.T("動画の同期: ", "Video sync: ") .. (sync_seen and L.T("動いていた", "running") or L.T("動いていなかった（動画の負荷は入っていない）", "not running (no video load included)")))
  w("")
  w(L.T("--- 結果 ---", "--- Results ---"))
  local names = { string.format(L.T("そのまま %d秒", "as is %d s"), IDLE), string.format(L.T("自動スクラッチ %d秒", "auto scratch %d s"), LOAD) }
  for i = 1, 2 do
    w(string.format(L.T("[%s] 音切れ %d回（JSFXが数えた、音声処理の遅れ %.1f ms 超）／REAPERの数え: 音切れ %d回・読み込みの途切れ %d回",
      "[%s] dropouts %d (counted by the JSFX, audio blocks late by more than %.1f ms) / REAPER's count: dropouts %d, media read gaps %d"),
      names[i], xruns(i), xthr, ph[i].xrun, ph[i].mxrun))
    for _, dk in ipairs(decks) do
      w(string.format(L.T("    デッキ%s のJSFXの重さ（持ち時間に対する割合）: ふだん %.1f%%、いちばん重い瞬間 %.1f%%",
        "    Deck %s JSFX load (share of the time per block): average %.1f%%, heaviest moment %.1f%%"),
        dk.name, dk.navg[i] > 0 and dk.avg[i] / dk.navg[i] or 0, dk.worst[i]))
    end
    w(string.format(L.T("    画面の更新: いちばん長い途切れ %.0f ms（平均 %.0f ms ごと）", "    Screen updates: longest gap %.0f ms (every %.0f ms on average)"), ph[i].gap * 1000,
      ph[i].frames > 0 and ph[i].dur / ph[i].frames * 1000 or 0))
  end
  for _, dk in ipairs(decks) do
    w(string.format(L.T("素材の読み直しにかかったCPUの時間: デッキ%s %.0f ms（何回にも分けて読むので、音は止まらない作り）",
      "CPU time to read the sample again: deck %s %.0f ms (read in many small parts, so the sound does not stop)"), dk.name, get(dk, dk.p_load)))
  end
  w("")
  w(L.T("--- 判定 ---", "--- Verdict ---"))
  local worst_sum = 0
  for _, dk in ipairs(decks) do worst_sum = worst_sum + dk.worst[2] end
  local bad = false
  if xruns(2) + ph[2].xrun + ph[2].mxrun > 0 then
    bad = true
    w(L.T("× 自動スクラッチ中に音切れがありました。setupで動画の高さを小さく（540や360）するか、音声のバッファを大きくして試してください。",
      "x There were dropouts during the auto scratch. Try a smaller video height in setup (540 or 360) or a larger audio buffer."))
  end
  if worst_sum >= 70 then
    bad = true
    w(string.format(L.T("△ JSFXだけで持ち時間の %.0f%% を使う瞬間がありました（全デッキの合計）。余裕が少ないです。",
      "! At moments the JSFX alone used %.0f%% of the time per block (all decks together). Little headroom."), worst_sum))
  end
  if ph[2].gap > 0.25 then
    bad = true
    w(string.format(L.T("△ 画面が %.2f 秒止まった瞬間がありました。映像が引っかかって見えることがあります。",
      "! The screen froze for %.2f s at a moment. The video may look jerky."), ph[2].gap))
  end
  if not bad then w(L.T("○ 問題は見つかりませんでした。", "OK: no problems found.")) end
  -- (measured 2026-10-04: a 0.3-0.6 s stall of the audio thread left GetUnderrunTime at 0 with WaveOut and with ASIO
  -- (Fireface), so the count that matters is the JSFX's own)
  -- (with WaveOut a stall on another track did not delay the JSFX's blocks, one in its own track did - 2026-10-04)
  if mode and (mode:find("WaveOut") or mode:find("DirectSound")) then
    w(string.format(L.T("※この音声の方式（%s）では、ReaScratch以外のトラックやプラグインが原因の音切れは数えられないことがあります。",
      "Note: with this audio system (%s), dropouts caused by tracks or plug-ins other than ReaScratch may not be counted."), mode))
  end
  if xruns(1) + ph[1].xrun + ph[1].mxrun > 0 then w(L.T("（試験の前から音切れがありました。ほかのソフトや設定の影響かもしれません）", "(There were dropouts before the test too: maybe other software or settings.)")) end
  local text = table.concat(o, "\n")
  local path = L.RES .. L.SEP .. "ReaScratch_load_test_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
  local fh = io.open(path, "w")
  if fh then fh:write(text .. "\n") fh:close() end
  L.log("load test: " .. path)
  reaper.ShowConsoleMsg(text .. "\n")
  L.msgbox(text .. L.T("\n\n結果はこのファイルに保存しました（送ってください）:\n", "\n\nThe result was saved to this file (please send it):\n") .. path, TITLE, 0)
end

local function tick()
  local t = reaper.time_precise()
  if reaper.GetExtState(SECTION, KEY) == "stop" then restore() report(true) return end
  reaper.SetExtState(SECTION, KEY, tostring(t), false)
  local p = ph[phase]
  p.gap = math.max(p.gap, t - t_prev); p.frames = p.frames + 1; p.dur = (p.dur or 0) + (t - t_prev)
  t_prev = t
  -- dropouts: REAPER keeps the time of the last one; a new time stamp = at least one more (two in one frame count once)
  local a, m = reaper.GetUnderrunTime()
  if a ~= last_a and a > a0 then p.xrun = p.xrun + 1 end
  if m ~= last_m and m > m0 then p.mxrun = p.mxrun + 1 end
  last_a, last_m = a, m
  for _, dk in ipairs(decks) do
    if reaper.ValidatePtr2(0, dk.tr, "MediaTrack*") then
      local n = get(dk, dk.p_xn)
      dk.xn[phase] = dk.xn[phase] + math.max(0, n - dk.xn0); dk.xn0 = n
    end
  end
  -- the JSFX meters change once a second
  if t - t_meter >= 0.25 then
    t_meter = t
    for _, dk in ipairs(decks) do
      if reaper.ValidatePtr2(0, dk.tr, "MediaTrack*") then
        dk.worst[phase] = math.max(dk.worst[phase], get(dk, dk.p_worst))
        dk.avg[phase] = dk.avg[phase] + get(dk, dk.p_avg); dk.navg[phase] = dk.navg[phase] + 1
      end
    end
    if t - (tonumber(reaper.GetExtState("ReaScratch", "video_sync_heartbeat")) or 0) < 1.0 then sync_seen = true end
  end
  if phase == 1 and t - t_start >= IDLE then
    phase = 2
    for _, dk in ipairs(decks) do dk.worst[2] = 0 end
    set_test(true)
  elseif phase == 2 and t - t_start >= IDLE + LOAD then
    restore()
    report(false)
    return
  end
  reaper.defer(tick)
end
reaper.SetExtState(SECTION, KEY, tostring(t_start), false)
L.log("load test: start (" .. (IDLE + LOAD) .. " s; run again to stop)")
reaper.defer(tick)

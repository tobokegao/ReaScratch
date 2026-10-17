-- ReaScratch kit: LOAD from REAPER's Media Explorer (⚪78; the Reloop Buddy's LOAD A / B). The file is chosen with the mouse
-- in the Media Explorer (user's choice 2026-10-08; the BROWSE knob works the decks' slots, in the JSFX).
-- Run from reascratch_video_sync.lua (its tick calls tick()): the JSFX counts the LOADs in gmem (ReaScratch_video [54] /
-- [56] deck A / B, [55] / [57] 1 = replace the slot in use); this reads the Media Explorer's chosen file with
-- js_ReaScriptAPI and loads it (a video, or only a sound) into the deck: an empty slot (while the deck plays, one after
-- the slot in use, so the sound playing is not read again), SHIFT + LOAD = into the slot in use. A stopped deck changes
-- to the slot (user's choice 2026-10-08).
-- The sound goes through ffmpeg in the background (the video keeps following meanwhile) into the slot's own file
-- Data/ReaScratch_samples/rs_load_<deck><slot>.wav: the JSFX lists that folder once when it loads, so a file made later
-- could only be used after adding the FX again (which starts the deck over). The 16 files are made here and by the setup;
-- if a deck's JSFX does not list them yet, the first LOAD adds it again (only while the deck is stopped).
-- (⚪173) As the names stay, a project that was not saved after a LOAD (reopened, or the LOAD undone) pointed at a file
-- that now held the later sound (user's report 2026-10-14: deck A showed the Matsuken video with the test pattern's sound).
-- So the engine track keeps which file each slot file was made from (P_EXT:ReaScratch_src_<rs_load_a1>, saved and undone
-- with the project) and the folder which one it holds now (<rs_load_a1>_src.txt, removed just before the file changes);
-- when they differ, the sound is written again from the project's file and the JSFX reads the slot again (cues kept).
-- The Media Explorer is found by its window class (the title is translated).

local L = ...
local M = {}
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""

local G_LOAD = { 54, 56 }
local VIDEO = { mp4 = 1, mov = 1, avi = 1, mkv = 1, webm = 1, wmv = 1, m4v = 1, mpg = 1, mpeg = 1, flv = 1, ts = 1, mts = 1 }
local AUDIO = { wav = 1, mp3 = 1, flac = 1, ogg = 1, aif = 1, aiff = 1, m4a = 1, aac = 1, opus = 1, wma = 1 }

local seen          -- the gmem values handled so far (nil = not read yet: what was there at start is not done again)
local jobs = {}     -- per deck: the LOAD in progress
local warned = {}

-- a short message by the mouse (the console window would cover the screen on stage)
local function tell(s)
  L.log("browser: " .. s)
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip("ReaScratch: " .. s, x + 16, y + 16, true)
end

function M.reserved(deck, slot) return string.format("rs_load_%s%d", deck == 2 and "b" or "a", slot) end

-- the 16 slot files (copies of the empty WAV), so a JSFX added after this lists them
function M.ensure_files()
  if not L.ensure_empty_wav() then return end
  local src = L.SAMPLE_DIR .. L.SEP .. L.EMPTY_WAV
  for d = 1, 2 do
    for k = 1, L.SLOTS do
      local p = L.SAMPLE_DIR .. L.SEP .. M.reserved(d, k) .. ".wav"
      if not reaper.file_exists(p) then
        local fi, fo = io.open(src, "rb"), io.open(p, "wb")
        if fi and fo then fo:write(fi:read("a")) end
        if fi then fi:close() end
        if fo then fo:close() end
      end
    end
  end
end

-- ---------------------------------------------------------------- the Media Explorer
local mx_cache
local function find_class(list, cls)
  for adr in (list or ""):gmatch("[^,]+") do
    local h = reaper.JS_Window_HandleFromAddress(tonumber(adr))
    if h and reaper.JS_Window_GetClassName(h) == cls then return h end
  end
end
local function mx_win()
  if mx_cache and reaper.JS_Window_IsWindow(mx_cache) then return mx_cache end
  local _, top = reaper.JS_Window_ListAllTop()
  mx_cache = find_class(top, "REAPERMediaExplorerMainwnd")
  if not mx_cache then   -- docked
    local _, ch = reaper.JS_Window_ListAllChild(reaper.GetMainHwnd())
    mx_cache = find_class(ch, "REAPERMediaExplorerMainwnd")
  end
  return mx_cache
end
local function child(w, id, cls)
  local _, ch = reaper.JS_Window_ListAllChild(w)
  for adr in (ch or ""):gmatch("[^,]+") do
    local h = reaper.JS_Window_HandleFromAddress(tonumber(adr))
    if reaper.JS_Window_GetLong(h, "ID") == id and reaper.JS_Window_GetClassName(h) == cls then return h end
  end
end
-- the Media Explorer (opened if closed), or nil when js_ReaScriptAPI is missing
local function mx()
  if not reaper.JS_Window_ListAllTop then
    if not warned.js then warned.js = true; tell(L.T("js_ReaScriptAPI が要ります（ReaPack で入れてください）", "needs js_ReaScriptAPI (install it with ReaPack)")) end
    return nil
  end
  local w = mx_win()
  if not w then reaper.Main_OnCommand(50124, 0); mx_cache = nil; w = mx_win() end
  return w
end

-- the chosen entry: full path, is it a folder
local function chosen(w)
  local list = child(w, 1001, "SysListView32")
  if not list then return nil end
  local n, sel = reaper.JS_ListView_ListAllSelItems(list)
  if not n or n < 1 then return nil end
  local idx = tonumber(sel:match("^(%d+)"))
  local name = reaper.JS_ListView_GetItemText(list, idx, 0)
  if name == "" then return nil end
  local dir = reaper.JS_Window_GetTitle(child(w, 1002, "ComboBox") or w)
  local path = (name:match("^%a:[\\/]") or name:match("^\\\\")) and name or (dir:gsub("[\\/]$", "") .. L.SEP .. name)
  local i, is_dir = 0, false
  local pdir, pname = path:match("^(.*)[\\/]([^\\/]+)$")
  repeat
    local s = pdir and reaper.EnumerateSubdirectories(pdir, i)
    if s == pname then is_dir = true end
    i = i + 1
  until not s or is_dir
  return path, is_dir
end

-- ---------------------------------------------------------------- LOAD
local function param(tr, fx, label)
  local p = L.param_index(tr, fx, label)
  return p, p and reaper.TrackFX_GetParam(tr, fx, p)
end
local function file_label(slot) return slot == 1 and "Sample file" or ("Sample file " .. slot) end
-- the list index of the file `name` (without .wav) in a file slider p, nil = not listed ((⚪151) one search, slot_file and
-- empty_index had a copy each)
local function list_index(tr, fx, p, name)
  local _, _, mx_v = reaper.TrackFX_GetParam(tr, fx, p)
  for i = 0, math.floor(mx_v + 0.5) do
    local ok, s = reaper.TrackFX_FormatParamValue(tr, fx, p, i, "")
    if ok and s == name then return i end
  end
end
-- slot k's file name (without .wav) as the JSFX shows it, and the list index of name (nil = not listed)
local function slot_file(tr, fx, slot, name)
  local p = param(tr, fx, file_label(slot))
  if not p then return nil end
  local _, cur = reaper.TrackFX_GetFormattedParamValue(tr, fx, p, "")
  return cur, name and list_index(tr, fx, p, name), p
end
-- ffprobe next to the ffmpeg found ((⚪151) written out twice before)
local function probe_of(ffmpeg) return (ffmpeg:gsub("ffmpeg(%.?%a*)$", "ffprobe%1")) end

-- (⚪173) which file a slot file was made from: as the project says (the engine track) and as the folder says
local src_key = L.src_key
local function src_mark(rname) return L.SAMPLE_DIR .. L.SEP .. rname .. "_src.txt" end
local function read_mark(rname) return L.read_file(src_mark(rname)) end

local write_sound
local function start_load(deck, replace, path_in)
  -- (⚪107; read first: a LOAD that stops early must not leave it for the next) SHIFT + a sample pad: the JSFX names the slot (gmem[110] / [111] = slot, 0 = none)
  local want = math.floor((reaper.gmem_read(deck == 2 and 111 or 110) or 0) + 0.5)
  reaper.gmem_write(deck == 2 and 111 or 110, 0)
  if jobs[deck] then tell(string.format(L.T("読み込み中です（デッキ%s）", "still loading (deck %s)"), deck == 2 and "B" or "A")) return end
  -- ((⚪179) it runs ffmpeg through batch files: on macOS it waited for a file that never came, up to 15 min, silently)
  if not reaper.GetOS():find("Win") then tell(L.T("LOAD は Windows だけで動きます", "LOAD works on Windows only")) return end
  local path, is_dir = path_in, false   -- (path_in: the tests)
  if not path then
    local w = mx()
    if not w then return end
    path, is_dir = chosen(w)
  end
  if not path or is_dir then tell(L.T("Media Explorer でファイルを選んでください", "select a file in the Media Explorer")) return end
  -- ((⚪151) the path is put together from the folder box and the name: in a database view of the Media Explorer that is
  -- not the file, and ffmpeg failed later with "could not convert the audio")
  if not reaper.file_exists(path) then
    if path_in then tell(L.T("ファイルが見つかりません（フォルダーは読み込めません）: ", "file not found (a folder cannot be loaded): ") .. path) return end   -- (⚪187 a drop)
    tell(L.T("ファイルが見つかりません（Media Explorerのデータベース表示では読めません。フォルダを開いて選んでください）: ",
      "file not found (a database view of the Media Explorer cannot be read: open the folder and select it there): ") .. path)
    return
  end
  local ext = (path:match("%.([%w]+)$") or ""):lower()
  local is_video = VIDEO[ext] ~= nil
  if not is_video and not AUDIO[ext] then tell(L.T("動画か音のファイルを選んでください: ", "select a video or audio file: ") .. path) return end
  local tr, fx = L.find_engine(deck)
  if not tr then tell(string.format(L.T("デッキ%sがありません", "no deck %s in this project"), deck == 2 and "B" or "A")) return end
  local _, playing = param(tr, fx, "Untouched transport")
  local _, cur = param(tr, fx, "Sample slot")
  playing = (playing or 0) > 0.5; cur = math.floor((cur or 1) + 0.5)
  local slot
  if want >= 1 and want <= L.SLOTS then
    slot = want
  elseif replace then
    slot = cur
  else
    for k = playing and cur + 1 or 1, L.SLOTS do
      local name = slot_file(tr, fx, k)
      if name == "(empty)" or name == "" then slot = k break end
    end
    if not slot then tell(playing and L.T("いまのスロットより後ろに空きがありません（止めると前の空きにも入ります）", "no empty slot after the current one (stop the deck to use the ones before it)") or L.T("空きスロットがありません", "no empty slot")) return end
  end
  local rname = M.reserved(deck, slot)
  local _, idx = slot_file(tr, fx, slot, rname)
  if not idx and playing then
    tell(L.T("初めての LOAD はデッキを止めてから（準備に JSFX を入れ直します）", "stop the deck for the first LOAD (it reloads the JSFX to prepare)")) return
  end
  if write_sound(deck, slot, rname, path, is_video, { listed = idx ~= nil, replace = replace }) then
    tell(string.format(L.T("デッキ%s のスロット %d に読み込み中: %s%s", "loading into deck %s slot %d: %s%s"), deck == 2 and "B" or "A", slot, L.stem(path),
      is_video and "" or L.T("（音だけのファイル: 映像なし）", " (audio file: no video)")))
  end
end

-- the sound of `path` into the slot file rname in the background (jobs[deck]; opt: listed, replace, heal); false = not started
write_sound = function(deck, slot, rname, path, is_video, opt)
  local ffmpeg = L.find_ffmpeg(HERE)
  if not ffmpeg then tell(L.T("ffmpeg が見つかりません（探す場所: 説明書「動画が重い場合」の方法A）", "ffmpeg not found (where it is looked for: the manual, \"Heavy video\", method A)")) return false end
  -- ffmpeg in the background: a batch file writes the WAV under a temporary name, then renames it and leaves a mark
  local final = L.SAMPLE_DIR .. L.SEP .. rname .. ".wav"
  local tmp = L.SAMPLE_DIR .. L.SEP .. rname .. "_tmp.wav"
  local mark = L.SAMPLE_DIR .. L.SEP .. rname .. "_done.txt"
  local bat = L.SAMPLE_DIR .. L.SEP .. rname .. "_load.bat"
  os.remove(tmp); os.remove(mark)
  local q = L.bat_esc   -- (% in a batch file)
  -- a video without sound (the kit's MJPEG conversions keep the sound apart, user's test 2026-10-08): silence as long as
  -- the video (_silent.txt says so)
  local dur = 0
  local src = reaper.PCM_Source_CreateFromFile(path)
  if src then dur = reaper.GetMediaSourceLength(src); reaper.PCM_Source_Destroy(src) end
  local probe = probe_of(ffmpeg)
  if is_video and dur <= 0 and reaper.file_exists(probe) then   -- (REAPER without a decoder for it: ffprobe's length)
    local r = reaper.ExecProcess(string.format('"%s" -v error -show_entries format=duration -of csv=p=0 "%s"', probe, path), 10000)
    dur = tonumber(r and r:match("^0\n%s*([%d%.]+)")) or 0
  end
  local silent = L.SAMPLE_DIR .. L.SEP .. rname .. "_silent.txt"
  os.remove(silent)
  -- ((⚪151) L.write_bat (@echo off, chcp 65001, CR LF) and L.run_bat (no wait, minimized: -1 could bring up a console window))
  local b = { '"' .. q(ffmpeg) .. '" ' .. L.ffmpeg_wav_args(q(path), q(tmp)),
    "if %errorlevel% equ 0 goto moved" }   -- (ffmpeg's exit code can be negative: 'if not errorlevel 1' took it for done)
  if is_video and dur > 0 then
    b[#b + 1] = string.format('echo silent> "%s"', q(silent))
    b[#b + 1] = string.format('"%s" -hide_banner -nostdin -loglevel error -y -f lavfi -i anullsrc=r=48000:cl=stereo -t %.3f -c:a pcm_s24le "%s"',
      q(ffmpeg), dur, q(tmp))
    b[#b + 1] = "if %errorlevel% neq 0 goto fail"
  else
    b[#b + 1] = "goto fail"
  end
  b[#b + 1] = ":moved"
  b[#b + 1] = string.format('del /q "%s" 2>nul', q(src_mark(rname):gsub("/", "\\")))   -- (⚪173) the file changes now: what it holds is not known until finish()
  b[#b + 1] = string.format('move /y "%s" "%s" >nul || goto fail', q(tmp:gsub("/", "\\")), q(final:gsub("/", "\\")))   -- ((⚪151) backslashes: see start_conv
  b[#b + 1] = string.format('echo ok> "%s"', q(mark))
  b[#b + 1] = "exit /b"
  b[#b + 1] = ":fail"
  b[#b + 1] = string.format('echo fail> "%s"', q(mark))
  if not L.write_bat(bat, b) then tell(L.T("書き出しの準備ができません: ", "cannot prepare the conversion: ") .. bat) return false end
  L.run_bat(bat)
  jobs[deck] = { path = path, video = is_video, slot = slot, rname = rname, final = final, mark = mark, bat = bat, silent = silent,
    listed = opt.listed, t0 = reaper.time_precise(), replace = opt.replace, heal = opt.heal }
  return true
end

-- (⚪106, user's choice 2026-10-09) a LOADed video that is not all keyframes (H.264 etc.: scratching it was slow - a frame
-- far from a keyframe is built from the keyframe before it; measured in the isolated REAPER with a 1920x1080 H.264 Wario:
-- an effect change showed 0.01-0.27 s late, as MJPEG 0.00-0.04 s) or larger than this PC's height (setup) is converted
-- to all-keyframe MJPEG in the background, next to it as <name>_mjpeg.avi (as reascratch_reencode_mjpeg.lua names it); when
-- done, the slot's video item takes it (the sound stays). One already there is used at once.
local convs = {}
local function norm(p) return (p:gsub("\\", "/"):lower()) end   -- (the same file however its path is written)
local function swap_video(c)
  local vname = L.deck_tracks(c.deck)
  local video = L.track_by_name(vname)
  if not video then return false end
  for _, it in ipairs(L.slot_items(video, c.slot)) do   -- ((⚪151) L.slot_items: margin 0.0005 s, here 0.01 s before)
    local tk = reaper.GetActiveTake(it)
    local src = tk and reaper.GetMediaItemTake_Source(tk)
    if src and norm(reaper.GetMediaSourceFileName(src, "")) == norm(c.src) then
      if not L.take_set_source(tk, reaper.PCM_Source_CreateFromFile(c.out)) then return false end   -- ((⚪151) L.take_set_source)
      reaper.UpdateItemInProject(it)
      reaper.UpdateArrange()
      reaper.gmem_write(49, (reaper.gmem_read(49) or 0) + 1)   -- (the video sync script redraws a standing picture)
      return true
    end
  end
  return false
end
local function start_conv(deck, slot, path)
  local all_intra = L.keyframe_info(path)
  local _, vh = L.video_info(path)
  local max_h = L.video_height()
  if all_intra and not (vh and vh > max_h) then return end
  local out = path:gsub("%.[^%.\\/]+$", "") .. "_mjpeg.avi"
  local c = { deck = deck, slot = slot, src = path, out = out, t0 = reaper.time_precise() }
  -- an older <name>_mjpeg.avi only when it has the source's frames: one from REAPER's renderer (the earlier way of
  -- reascratch_reencode_mjpeg.lua) had a frame more and black frames in it (user's report 2026-10-09: black flashes in the
  -- first half of the Matsuken video, frames 1 and 28-30 of a 2026-10-03 copy); else it is made again
  local ffmpeg = L.find_ffmpeg(HERE)
  local function frames(f)
    if not ffmpeg then return nil end
    local probe = probe_of(ffmpeg)
    local r = reaper.ExecProcess(string.format('"%s" -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 "%s"', probe, f), 10000)
    return r and tonumber((r:match("^%-?%d+\n(.-)%s*$") or ""):match("%d+"))
  end
  local nf_out = reaper.file_exists(out) and (L.file_size(out) or 0) > 1024 and frames(out)
  if nf_out and nf_out == frames(path) then
    if swap_video(c) then tell(string.format(L.T("デッキ%s のスロット %d: 全コマキーフレームの動画 %s を使います", "deck %s slot %d: using the all-keyframe video %s"),
      deck == 2 and "B" or "A", slot, L.stem(out))) end
    return
  end
  if not ffmpeg then return end
  local tmp = out:gsub("%.avi$", "_tmp.avi")
  c.mark = out .. "_done.txt"; c.bat = out .. "_conv.bat"
  os.remove(tmp); os.remove(c.mark)
  local q = L.bat_esc
  -- ((⚪151) L.write_bat (chcp 65001 there: (⚪150) without it a Japanese file name failed) and L.run_bat (minimized))
  if not L.write_bat(c.bat, {
    '"' .. q(ffmpeg) .. '" ' .. L.ffmpeg_mjpeg_args(q(path), q(tmp), max_h),   -- ((⚪179) quality 85 = -q:v 3, as before)
    "if %errorlevel% neq 0 goto fail",
    -- ((⚪151) the move with backslashes (cmd's move took a path with / for a switch and failed) and, failed, "fail"
    -- (before, "ok" with the video left as _tmp)
    string.format('move /y "%s" "%s" >nul || goto fail', q(tmp:gsub("/", "\\")), q(out:gsub("/", "\\"))),
    string.format('echo ok>"%s"', q(c.mark)), "exit /b 0",
    ":fail", string.format('echo fail>"%s"', q(c.mark)) }) then return end
  L.run_bat(c.bat)
  convs[#convs + 1] = c
  tell(string.format(L.T("デッキ%s のスロット %d: 全コマキーフレーム (MJPEG) へ裏で変換中（終わると映像だけ入れ替えます）", "deck %s slot %d: converting to all keyframes (MJPEG) in the background (the video is swapped when done)"),
    deck == 2 and "B" or "A", slot))
end
local function conv_tick()
  for i = #convs, 1, -1 do
    local c = convs[i]
    if reaper.file_exists(c.mark) or reaper.time_precise() - c.t0 > 1800 then
      table.remove(convs, i)
      local fm = io.open(c.mark, "rb"); local res = fm and fm:read("a") or ""; if fm then fm:close() end
      os.remove(c.mark); if not _G.REASCRATCH_KEEP_BAT then os.remove(c.bat) end
      if res:find("ok") and reaper.file_exists(c.out) and swap_video(c) then
        tell(string.format(L.T("デッキ%s のスロット %d: 映像を全コマキーフレーム (%s) に入れ替えました（%.0f 秒）", "deck %s slot %d: the video is now all keyframes (%s, %.0f s)"),
          c.deck == 2 and "B" or "A", c.slot, L.stem(c.out), reaper.time_precise() - c.t0))
      else
        tell(L.T("全コマキーフレームへの変換に失敗しました（元の動画のまま）: ", "the all-keyframe conversion failed (the original video stays): ") .. c.src)
      end
    end
  end
end

M.conv_start, M.conv_tick, M.start_load = start_conv, conv_tick, start_load   -- (for the tests)
local function finish(deck, j)
  local fm = io.open(j.mark, "rb")
  local res = fm and fm:read("a") or ""
  if fm then fm:close() end
  os.remove(j.mark); if not _G.REASCRATCH_KEEP_BAT then os.remove(j.bat) end
  local no_sound = reaper.file_exists(j.silent)
  os.remove(j.silent)
  if not res:find("ok") or not reaper.file_exists(j.final) then
    tell(L.T("音の書き出しに失敗しました: ", "could not convert the audio: ") .. j.path) return
  end
  local fs = io.open(src_mark(j.rname), "wb")   -- (⚪173) what the slot file holds now
  if fs then fs:write(j.path); fs:close() end
  local tr, fx = L.find_engine(deck)
  if not tr then return end
  if j.heal then   -- (⚪173) the project's own sound again: the JSFX reads the slot holding it (slots may have been swapped meanwhile)
    for k = 1, L.SLOTS do
      if slot_file(tr, fx, k) == j.rname then   -- (gmem, not a parameter: that made an undo point and the LOAD undone could not be redone)
        reaper.gmem_write(289 + deck, k); reaper.gmem_write(291 + deck, reaper.gmem_read(291 + deck) + 1)
      end
    end
    tell(string.format(L.T("デッキ%s: %s の音を戻しました（保存していない LOAD で上書きされていました）", "deck %s: the sound of %s is back (a LOAD that was not saved had overwritten it)"),
      deck == 2 and "B" or "A", L.stem(j.path)))
    return
  end
  local _, playing = param(tr, fx, "Untouched transport")
  playing = (playing or 0) > 0.5
  local vname, aname = L.deck_tracks(deck)
  local video, audio = L.track_by_name(vname), L.track_by_name(aname)
  local start = L.slot_start(j.slot)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  -- the slot's video (a sound only: none) and no old waveform
  local cpos = reaper.GetCursorPosition()
  local seltr = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do seltr[#seltr + 1] = reaper.GetSelectedTrack(0, i) end
  if video then L.clear_items(video, start, start + L.SLOT_SPAN) end
  if audio then L.clear_items(audio, start, start + L.SLOT_SPAN) end
  if video and j.video then L.insert_on_track(video, j.path, start) end
  reaper.SetEditCurPos(cpos, false, false)
  reaper.SetOnlyTrackSelected(seltr[1] or tr)
  for i = 2, #seltr do reaper.SetTrackSelected(seltr[i], true) end
  reaper.PreventUIRefresh(-1)
  -- the JSFX's slot file: the slot's own file (listed: just point at it; not yet: add the JSFX again, only stopped)
  if not j.listed then
    if playing then
      if deck == 1 and video then L.fill_black(video) end
      reaper.Undo_EndBlock("ReaScratch LOAD", -1) tell(L.T("デッキが動いているので入れ直せません。止めてからもう一度 LOAD", "the deck is playing, so the JSFX cannot be reloaded. Stop it and LOAD again")) return
    end
    L.set_engine_sample(tr, j.rname .. ".wav", j.slot)
    tr, fx = L.find_engine(deck)
  else
    local _, idx, p = slot_file(tr, fx, j.slot, j.rname)
    if p and idx then reaper.TrackFX_SetParam(tr, fx, p, idx) end
  end
  reaper.GetSetMediaTrackInfo_String(tr, src_key(j.rname), j.path, true)   -- (⚪173; in the undo block: undone with the LOAD)
  -- (a sound-only slot: black, ⚪78; (⚪150) after the slot's file is set: before it, fill_black read the old name, and a
  -- sound put into the slot in use left it black instead of the turning speaker)
  if deck == 1 and video then L.fill_black(video) end
  -- tempo and grid, then the JSFX reads the slot again and starts it fresh. (⚪179) found by L.analyse_sample, as the
  -- import does: (⚪177) rekordbox's values win (sent after the slot is read), (⚪176) a tempo that moves: its beat map,
  -- (⚪175) the key
  local a = L.analyse_sample(j.final, { j.path, j.final })
  local bpm, bdur = a.bpm, a.bdur
  L.set_param(tr, fx, "New file's BPM", bpm)
  L.set_param(tr, fx, "New file's beat grid", a.grid)
  L.set_key(tr, fx, j.slot, L.key_code(a.key, a.lead))
  L.set_loudness(tr, fx, j.slot, a.lufs, a.peak)   -- (⚪185 auto gain)
  L.set_param(tr, fx, "New file in slot", j.slot)
  if a.rb then L.rb_send(tr, fx, j.slot, a.rb); L.log(L.rb_summary(a.rb)) end
  if a.map then L.gb_send(tr, fx, j.slot, a.map); L.log("tempo moves: a beat map of " .. #a.map .. " marks (" .. a.minfo .. ")") end
  if not playing then L.set_param(tr, fx, "Sample slot", j.slot) end
  reaper.UpdateArrange()
  reaper.gmem_write(49, reaper.gmem_read(49) + 1)   -- the video sync script redraws the video window (⚪78)
  reaper.Undo_EndBlock("ReaScratch LOAD " .. L.stem(j.path), -1)
  if j.video then start_conv(deck, j.slot, j.path) end   -- (⚪106)
  tell(string.format(L.T("デッキ%s のスロット %d: %s（%s%s, %.1f 秒）", "deck %s slot %d: %s (%s%s, %.1f s)"), deck == 2 and "B" or "A", j.slot, L.stem(j.path),
    j.video and (no_sound and L.T("音なしの動画: 無音で入れました, ", "video without sound: loaded silence, ") or "") or L.T("音だけ・映像なし, ", "audio only, no video, "),
    bpm > 0 and string.format("%.2f BPM", bpm) .. L.bpm_note(bpm, bdur) or L.T("BPM 不明", "BPM unknown"), reaper.time_precise() - j.t0))
end

-- ---------------------------------------------------------------- the slot menu (⚪78, the JSFX's slot buttons' right-click)
-- The JSFX empties / swaps slots itself; here: (1) every 2 s, the list index of (empty).wav for its file sliders (gmem[58] /
-- [59] = index + 1, deck A / B), (2) its requests (gmem[60] / [66]: counter, +1 op, +2, +3; +5 = done up to): op 1 = empty the
-- slots in the mask +2, op 2 = swap slots +2 and +3 (0-7): their file sliders (the JSFX changed the rest) and their videos
-- and waveforms on the timeline
local G_OPS = { 60, 66 }
local G_DROP, drop_seen, drops = { 9100000, 9110000 }, {}, { {}, {} }   -- (⚪187) files dropped onto the JSFX windows
local ops_seen, empty_next = {}, 0
local function empty_index()
  for d = 1, 2 do
    local tr, fx = L.find_engine(d)
    local idx
    if tr then
      local p = L.param_index(tr, fx, "Sample file")
      if p then idx = list_index(tr, fx, p, "(empty)") end   -- ((⚪150) nil with an old JSFX: an error stopped the sync; (⚪151) list_index)
    end
    reaper.gmem_write(57 + d, idx and idx + 1 or 0)
  end
end
local function span_items(tr, slot) return L.slot_items(tr, slot + 1) end   -- slot 0-7 ((⚪151) L.slot_items)
local function slot_op(deck, op, a, b)
  local vname, aname = L.deck_tracks(deck)
  local tracks = {}   -- ((⚪150) not { video, audio }: a missing video track ended ipairs before the audio one)
  for _, nm in ipairs({ vname, aname }) do tracks[#tracks + 1] = L.track_by_name(nm) end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for _, tr in ipairs(tracks) do
    if op == 1 then
      for k = 0, L.SLOTS - 1 do
        if math.floor(a / 2 ^ k) % 2 == 1 then L.clear_items(tr, k * L.SLOT_SPAN, (k + 1) * L.SLOT_SPAN) end
      end
    elseif op == 2 then
      local ia, ib = span_items(tr, a), span_items(tr, b)
      for _, it in ipairs(ia) do reaper.SetMediaItemInfo_Value(it, "D_POSITION", reaper.GetMediaItemInfo_Value(it, "D_POSITION") + (b - a) * L.SLOT_SPAN) end
      for _, it in ipairs(ib) do reaper.SetMediaItemInfo_Value(it, "D_POSITION", reaper.GetMediaItemInfo_Value(it, "D_POSITION") + (a - b) * L.SLOT_SPAN) end
    end
  end
  -- the file sliders (set from the JSFX they did not always reach what REAPER saves, measured 2026-10-08); the JSFX
  -- already holds these values for the slots, so nothing is read again
  local tr, fx = L.find_engine(deck)
  if tr then
    local function fp(k) return L.param_index(tr, fx, file_label(k + 1)) end
    if op == 1 then
      local e = reaper.gmem_read(57 + deck) - 1
      for k = 0, L.SLOTS - 1 do
        if math.floor(a / 2 ^ k) % 2 == 1 and e >= 0 then reaper.TrackFX_SetParam(tr, fx, fp(k), e) end
      end
    elseif op == 2 then
      local va, vb = reaper.TrackFX_GetParam(tr, fx, fp(a)), reaper.TrackFX_GetParam(tr, fx, fp(b))
      reaper.TrackFX_SetParam(tr, fx, fp(a), vb); reaper.TrackFX_SetParam(tr, fx, fp(b), va)
    end
  end
  if deck == 1 then L.fill_black(L.track_by_name(vname)) end   -- (the emptied slots: black, ⚪78)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.gmem_write(49, reaper.gmem_read(49) + 1)   -- the video sync script redraws the video window (⚪78)
  reaper.Undo_EndBlock(op == 1 and "ReaScratch: empty slots" or string.format("ReaScratch: swap slots %d and %d", a + 1, b + 1), -1)
end

-- (⚪173) every 2 s: a slot file that holds another file's sound than the project made it from is written again from
-- the project's file (one at a time per deck; a project from before ⚪173 says nothing and is left alone)
local heal_warned = {}
local function heal_check()
  for d = 1, 2 do
    local tr, fx = L.find_engine(d)
    if tr and not jobs[d] then
      for k = 1, L.SLOTS do
        local rname = slot_file(tr, fx, k)
        if rname and rname:match("^rs_load_[ab]%d+$") then
          local _, want = reaper.GetSetMediaTrackInfo_String(tr, src_key(rname), "", false)
          if want ~= "" and read_mark(rname) ~= want then
            if reaper.file_exists(want) then
              local ext = (want:match("%.([%w]+)$") or ""):lower()
              if write_sound(d, k, rname, want, VIDEO[ext] ~= nil, { listed = true, heal = true }) then
                tell(string.format(L.T("デッキ%s のスロット %d: 音が保存していない LOAD で上書きされていたので、%s から書き出し直しています",
                  "deck %s slot %d: the sound was overwritten by a LOAD that was not saved; writing it again from %s"), d == 2 and "B" or "A", k, L.stem(want)))
              end
              break
            elseif not heal_warned[rname .. want] then
              heal_warned[rname .. want] = true
              tell(string.format(L.T("デッキ%s のスロット %d: 音が別の素材で上書きされていて、元のファイルが見つかりません（LOAD し直してください）: %s",
                "deck %s slot %d: the sound was overwritten by another file and the original is missing (LOAD it again): %s"), d == 2 and "B" or "A", k, want))
            end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- the tick (from reascratch_video_sync.lua)
-- ---------------------------------------------------------------- PREVIEW (⚪188)
-- (user's request 2026-10-16) the Media Explorer's own preview shows a video in the video window (the audience's picture),
-- and no setting of REAPER hides it, nor does it pass through a Video processor (tried 2026-10-16). So the P
-- key in a deck's JSFX previews the file chosen in the Media Explorer here: the sound by SWS's CF_Preview straight to
-- the "Cue" track's headphone output, the picture by the item on "preview view" (L.TRACK_PREVIEW), moved so its frame at
-- the cursor is the preview's position; the deck mix reads it (input_track(1)) into a grid for that deck's record label.
-- P again with the same file (or from the other deck) = stop; with another file chosen = that one. A LOAD stops it.
-- gmem: [370] / [371] P from deck A / B (count up), [372] the deck previewing (0 none), [373] 1 = its picture is placed,
-- [374] / [375] position / length (s); the deck mix's grid [9020000 ..] (+ 4096 = count)
local G_PREV, G_PDECK, G_PPIC, G_PPOS, G_PLEN, G_PGRID = { 370, 371 }, 372, 373, 374, 375, 9020000 + 4096
local prev_seen
local pr = nil                  -- { h = CF preview, src, path, deck, video, len }
local pv_it, pv_tk, pv_path     -- the item on "preview view", the file it shows

-- the "Cue" track's headphone output (its first hardware output's channel; +1024 = mono), nil without one
local function cue_chan()
  local cue = L.track_by_name(L.TRACK_CUE)
  if not cue or reaper.GetTrackNumSends(cue, 1) < 1 then return nil end
  return math.floor(reaper.GetTrackSendInfo_Value(cue, 1, 0, "I_DSTCHAN"))
end

-- ((⚪188, user's report 2026-10-16) the whole track muted while nothing is previewed: an item put on it by mistake (a
-- double-click in the Media Explorer inserts on the selected track) showed through deck B. Its own item muted as well
local function pv_track_mute(tr, on)
  if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") and reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") ~= (on and 1 or 0) then
    reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", on and 1 or 0)
  end
end
local function pv_mute()
  pv_track_mute(L.track_by_name(L.TRACK_PREVIEW), true)
  if pv_it and reaper.ValidatePtr2(0, pv_it, "MediaItem*") and reaper.GetMediaItemInfo_Value(pv_it, "B_MUTE") == 0 then
    reaper.SetMediaItemInfo_Value(pv_it, "B_MUTE", 1); reaper.UpdateItemInProject(pv_it)
  end
end

function M.preview_stop()
  if pr then
    reaper.CF_Preview_Stop(pr.h)      -- (false when SWS let it go already: played to the end)
    reaper.PCM_Source_Destroy(pr.src)
    pr = nil
  end
  reaper.gmem_write(G_PDECK, 0); reaper.gmem_write(G_PPIC, 0)
  pv_mute()
end

local function preview_start(deck)
  if not reaper.CF_CreatePreview then
    tell(L.T("試聴（P）にはSWS拡張が要ります（ReaPackかsws-extension.orgで入れてください）",
      "the preview (P) needs the SWS extension (install it with ReaPack or from sws-extension.org)"))
    return
  end
  local w = mx()
  if not w then return end
  local path, is_dir = chosen(w)
  if not path or is_dir then tell(L.T("Media Explorer でファイルを選んでください", "select a file in the Media Explorer")) return end
  if pr and (pr.path == path or pr.deck ~= deck) then M.preview_stop() return end   -- the same file / the other deck: stop
  if not reaper.file_exists(path) then
    tell(L.T("ファイルが見つかりません（Media Explorerのデータベース表示では読めません。フォルダを開いて選んでください）: ",
      "file not found (a database view of the Media Explorer cannot be read: open the folder and select it there): ") .. path)
    return
  end
  local ext = (path:match("%.([%w]+)$") or ""):lower()
  if not VIDEO[ext] and not AUDIO[ext] then tell(L.T("動画か音のファイルを選んでください: ", "select a video or audio file: ") .. path) return end
  -- only to the headphones: without the Cue track's output it does not play at all (it would go to the audience)
  local ch = cue_chan()
  if not ch then
    tell(L.T("試聴の出力がありません（「Cue」トラックのROUTEでヘッドホンの出力を選んでください）",
      "no output for the preview (pick the headphone output with ROUTE on the \"Cue\" track)"))
    return
  end
  M.preview_stop()
  local src = reaper.PCM_Source_CreateFromFile(path)
  if not src then tell(L.T("読めないファイルです: ", "cannot read the file: ") .. path) return end
  local h = reaper.CF_CreatePreview(src)
  reaper.CF_Preview_SetValue(h, "I_OUTCHAN", ch)
  reaper.CF_Preview_Play(h)
  pr = { h = h, src = src, path = path, deck = deck, video = VIDEO[ext] ~= nil, len = reaper.GetMediaSourceLength(src) }
  reaper.gmem_write(G_PGRID, 0)   -- (the last preview's picture not shown meanwhile)
  reaper.gmem_write(G_PPOS, 0); reaper.gmem_write(G_PLEN, pr.len)
  reaper.gmem_write(G_PDECK, deck)
  tell(L.T("試聴: ", "preview: ") .. (path:match("([^\\/]+)$") or path))
end

-- the item on "preview view" (the track made right after "video B view", or put back there), nil without deck B's view
local function pv_item()
  local vb = L.track_by_name(L.TRACK_VIEW_B)
  if not vb then return nil end
  local at = math.floor(reaper.GetMediaTrackInfo_Value(vb, "IP_TRACKNUMBER"))   -- (1-based: the index right after it)
  local tr = L.track_by_name(L.TRACK_PREVIEW)
  if tr and reaper.GetTrack(0, at) ~= tr then reaper.DeleteTrack(tr); tr = nil end   -- (moved away: the deck mix reads the next one)
  if not tr then
    reaper.InsertTrackAtIndex(at, false)
    tr = reaper.GetTrack(0, at)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", L.TRACK_PREVIEW, true)
    reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)          -- (no sound from it while REAPER records)
    reaper.SetMediaTrackInfo_Value(tr, "C_BEATATTACHMODE", 0)
    reaper.SetTrackSelected(tr, false)   -- (a double-click in the Media Explorer would insert onto it)
    pv_it = nil
  end
  if not (pv_it and reaper.ValidatePtr2(0, pv_it, "MediaItem*") and reaper.GetMediaItem_Track(pv_it) == tr) then
    pv_it = reaper.GetTrackMediaItem(tr, 0) or reaper.AddMediaItemToTrack(tr)
    pv_tk = reaper.GetActiveTake(pv_it) or reaper.AddTakeToMediaItem(pv_it)
    reaper.SetMediaItemInfo_Value(pv_it, "B_LOOPSRC", 0)
    reaper.SetMediaItemInfo_Value(pv_it, "D_LENGTH", L.SLOTS * L.SLOT_SPAN + L.SLOT_SPAN)
    local src = reaper.GetMediaItemTake_Source(pv_tk)
    pv_path = src and reaper.GetMediaSourceFileName(src, "") or ""
  end
  return pv_it
end

-- every cycle of the video sync (after deck B's view is placed): `cur` = the time the video window shows, `view_ok` =
-- deck B's view shows a picture (the deck mix's input_track(0); without it input_track(1) would not be the preview).
-- Returns true when the picture item moved (the video window draws again)
function M.preview_follow(cur, view_ok)
  if not pr then return false end
  local ok, pos = reaper.CF_Preview_GetValue(pr.h, "D_POSITION")
  if not ok or pos >= pr.len - 0.02 then M.preview_stop() return true end   -- played to the end (SWS lets it go)
  reaper.gmem_write(G_PPOS, pos)
  if not (pr.video and view_ok) then reaper.gmem_write(G_PPIC, 0) pv_mute() return false end
  local it = pv_item()
  if not it then reaper.gmem_write(G_PPIC, 0) return false end
  if pv_path ~= pr.path and L.take_set_source(pv_tk, reaper.PCM_Source_CreateFromFile(pr.path)) then pv_path = pr.path end
  local p, o = cur - pos, 0
  if p < 0 then o, p = -p, 0 end
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", p)
  reaper.SetMediaItemTakeInfo_Value(pv_tk, "D_STARTOFFS", o)
  reaper.SetMediaItemInfo_Value(it, "B_MUTE", 0)
  pv_track_mute(reaper.GetMediaItem_Track(it), false)
  reaper.UpdateItemInProject(it)
  reaper.gmem_write(G_PPIC, 1)
  return true
end

local function preview_requests()
  local g = { reaper.gmem_read(G_PREV[1]), reaper.gmem_read(G_PREV[2]) }
  if not prev_seen then
    -- (the sync started: a preview item left unmuted in a saved project is muted, no deck previews)
    prev_seen = g
    reaper.gmem_write(G_PDECK, 0); reaper.gmem_write(G_PPIC, 0)
    local tr = L.track_by_name(L.TRACK_PREVIEW)
    pv_it = tr and reaper.GetTrackMediaItem(tr, 0)
    pv_mute(); pv_it = nil   -- (the track muted too: projects made before the track mute)
    return
  end
  for d = 1, 2 do
    if g[d] > prev_seen[d] then preview_start(d) end
  end
  prev_seen = g
end

function M.tick()
  local now = reaper.time_precise()
  local two_s = now >= empty_next
  if two_s then empty_next = now + 2; empty_index() end
  for d = 1, 2 do
    local c = reaper.gmem_read(G_OPS[d])
    if ops_seen[d] and c > ops_seen[d] then
      slot_op(d, math.floor(reaper.gmem_read(G_OPS[d] + 1) + 0.5), math.floor(reaper.gmem_read(G_OPS[d] + 2) + 0.5),
        math.floor(reaper.gmem_read(G_OPS[d] + 3) + 0.5))   -- (whole numbers: "Sample file 2.0" is no parameter)
      reaper.gmem_write(G_OPS[d] + 5, c)   -- done: the JSFX may read slots again
    end
    ops_seen[d] = c
  end
  preview_requests()   -- (⚪188)
  -- (⚪187) files dragged onto a deck's JSFX window (G_DROP: see the JSFX's gfx_getdropfile): each a LOAD of that file,
  -- the first into the slot it fell on (replacing it; 0 = an empty slot), one at a time per deck (jobs)
  for d = 1, 2 do
    local b = G_DROP[d]
    local c = reaper.gmem_read(b)
    if drop_seen[d] and c > drop_seen[d] then
      local n, slot, o = math.floor(reaper.gmem_read(b + 2) + 0.5), math.floor(reaper.gmem_read(b + 1) + 0.5), b + 8
      for k = 1, math.min(n, 8) do
        local s = {}
        for _ = 1, 4001 do
          local ch = math.floor(reaper.gmem_read(o) + 0.5) % 256; o = o + 1
          if ch == 0 then break end
          s[#s + 1] = string.char(ch)
        end
        drops[d][#drops[d] + 1] = { path = table.concat(s), slot = k == 1 and slot or 0 }
      end
    end
    drop_seen[d] = c
    if drops[d][1] and not jobs[d] then
      local q = table.remove(drops[d], 1)
      if pr then M.preview_stop() end
      reaper.gmem_write(d == 2 and 111 or 110, q.slot)   -- (start_load's slot, as SHIFT + a sample pad)
      start_load(d, q.slot > 0, q.path)
    end
  end
  local g = { reaper.gmem_read(G_LOAD[1]), reaper.gmem_read(G_LOAD[2]) }
  if not seen then seen = g; M.ensure_files() return end
  if two_s then heal_check() end
  for d = 1, 2 do
    if g[d] > seen[d] then
      if pr then M.preview_stop() end   -- ((⚪188) a LOAD stops the preview, as the Media Explorer's own does)
      start_load(d, reaper.gmem_read(G_LOAD[d] + 1) > 0.5)
    end
  end
  seen = g
  conv_tick()   -- (⚪106)
  for d = 1, 2 do
    local j = jobs[d]
    if j and (reaper.file_exists(j.mark) or reaper.time_precise() - j.t0 > 900) then
      jobs[d] = nil
      finish(d, j)
    end
  end
end

return M

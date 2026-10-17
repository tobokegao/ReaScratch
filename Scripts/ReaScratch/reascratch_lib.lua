-- ReaScratch kit: shared helpers (loaded with dofile() by the other scripts in this folder).
-- Pure ReaScript API + Lua 5.3, no extensions required. Windows and macOS.

local M = {}

M.SEP = package.config:sub(1, 1)
M.RES = reaper.GetResourcePath()
M.SAMPLE_DIR = M.RES .. M.SEP .. "Data" .. M.SEP .. "ReaScratch_samples"   -- the JSFX file slider lists this folder
M.JSFX = "ReaScratch/reascratch.jsfx"
M.JSFX_NAME = "ReaScratch"
M.TRACK_VIDEO, M.TRACK_AUDIO, M.TRACK_ENGINE = "video", "audio", "scratch engine"
-- deck B (a second JSFX, 2026-10-04): its slot videos sit on the muted "video B" track like deck A's on "video"; what
-- the video window shows of it is the one item on "video B view" (just above "video"), which the video sync moves and
-- re-points so the frame at the edit cursor is deck B's head. A Video processor on "video" mixes the two (deck_mix.eel).
M.TRACK_VIDEO_B, M.TRACK_AUDIO_B, M.TRACK_ENGINE_B, M.TRACK_VIEW_B = "video B", "audio B", "scratch engine B", "video B view"
-- (⚪188) the picture of a file previewed from the Media Explorer (P key): one item on "preview view", right after "video B
-- view" (made at the first preview), which the video sync moves as deck B's view; the deck mix only reads it (never shown)
M.TRACK_PREVIEW = "preview view"
M.GMEM = "ReaScratch_video"   -- shared memory the JSFX writes and the Video processor reads (options:gmem in the JSFX)
function M.deck_tracks(deck)   -- video, audio, engine track names of deck 1 (A) or 2 (B)
  if deck == 2 then return M.TRACK_VIDEO_B, M.TRACK_AUDIO_B, M.TRACK_ENGINE_B end
  return M.TRACK_VIDEO, M.TRACK_AUDIO, M.TRACK_ENGINE
end

-- test hook: when a test harness sets this global table, dialogs are answered from it
M.TEST = _G.REASCRATCH_TEST

function M.log(s)
  reaper.ShowConsoleMsg("[ReaScratch] " .. tostring(s) .. "\n")
end

-- Language of the messages (public release, 2026-10-08): REAPER's ExtState ReaScratch / lang = "ja", "en" or "auto"
-- (default). auto = Japanese when REAPER's language pack (reaper.ini [REAPER] langpack= has "ja", "jp" or "日本"), else English.
-- Each message keeps both texts at its call site: M.T("日本語", "English") (same %-specifiers in the same order).
function M.lang_setting()
  local s = reaper.GetExtState("ReaScratch", "lang")
  return (s == "ja" or s == "en") and s or "auto"
end
function M.set_lang(s)
  reaper.SetExtState("ReaScratch", "lang", (s == "ja" or s == "en") and s or "auto", true)
end
-- (⚪151) the lines of one section of reaper.ini (the section name in any case; {} when the file cannot be read), for
-- auto_lang and video_cache (each read it with its own loop before)
function M.ini_section(name)
  local out = {}
  local f = reaper.get_ini_file and io.open(reaper.get_ini_file(), "r")
  if not f then return out end
  name = name:lower()
  local sec
  for l in f:lines() do
    local s = l:match("^%s*%[(.-)%]")
    if s then sec = s:lower()
    elseif sec == name then out[#out + 1] = l end
  end
  f:close()
  return out
end
local auto_lang   -- read from reaper.ini once per script run
function M.auto_lang()
  if auto_lang then return auto_lang end
  auto_lang = "en"
  for _, l in ipairs(M.ini_section("reaper")) do
    local v = l:match("^%s*langpack%s*=%s*(.*)$")
    if v then
      local lv = (v:match("[^/\\]*$") or v):lower()   -- the file name only
      -- whole-word Japanese markers only ("ja" alone would match Azerbaijani, Russian_by_Jaroslav ...)
      if lv:find("japan") or lv:find("jpn") or lv:find("^ja[_%-%. ]") or lv:find("^jp[_%-%. ]")
         or v:find("日本") then auto_lang = "ja" end
      break
    end
  end
  return auto_lang
end
function M.lang()   -- "ja" or "en" (a test harness gets Japanese unless it sets REASCRATCH_TEST.lang)
  if M.TEST then return M.TEST.lang or "ja" end
  local s = M.lang_setting()
  if s == "auto" then return M.auto_lang() end
  return s
end
function M.T(ja, en)
  return M.lang() == "ja" and ja or en
end

function M.msgbox(text, title, kind)   -- kind: 0 ok, 4 yes/no ; returns 6 = yes
  if M.TEST and M.TEST.answer then return M.TEST.answer end
  return reaper.ShowMessageBox(text, title or "ReaScratch", kind or 0)
end

-- A choice with its own words (a message box only has yes / no): a small menu at the mouse, the question greyed on
-- top. items = { "デッキA", "デッキB" }; returns the chosen number, 0 = closed without a choice (⚪33, user's request)
function M.choose(question, items)
  if M.TEST and M.TEST.choose then return M.TEST.choose end
  local mx, my = reaper.GetMousePosition()
  gfx.init("ReaScratch", 1, 1, 0, mx, my)   -- showmenu needs a gfx window; a 1 px one at the mouse
  gfx.x, gfx.y = 0, 0
  local r = gfx.showmenu("#" .. question:gsub("|", "/") .. "||" .. table.concat(items, "|"))
  gfx.quit()
  return r > 1 and r - 1 or 0   -- 1 = the greyed question line
end

-- Height of the all-keyframe conversion (2026-10-04, ⚪18): a slow PC can take smaller videos. This PC's choice is
-- kept in REAPER (all projects), set by the setup; each import can change it for that video.
M.VIDEO_HEIGHTS = { 720, 540, 360 }
function M.snap_video_height(h)   -- the nearest of VIDEO_HEIGHTS, or nil
  h = tonumber(h)
  if not h then return nil end
  local best
  for _, c in ipairs(M.VIDEO_HEIGHTS) do
    if not best or math.abs(c - h) < math.abs(best - h) then best = c end
  end
  return best
end
function M.video_height()
  if M.TEST and M.TEST.video_height then return M.TEST.video_height end
  return M.snap_video_height(reaper.GetExtState("ReaScratch", "video_height")) or 720
end
function M.set_video_height(h)
  reaper.SetExtState("ReaScratch", "video_height", tostring(h), true)
end
-- asks for a height (default: this PC's); returns it, or nil when cancelled. M.TEST.height_answer: the typed text.
function M.ask_video_height(title)
  local ans
  if M.TEST then   -- a test without height_answer keeps the height (no dialog)
    ans = M.TEST.height_answer or tostring(M.video_height())
  else
    local ok
    ok, ans = reaper.GetUserInputs(title or "ReaScratch", 1,
      M.T("高さ (720 / 540 / 360)", "Height (720 / 540 / 360)") .. ",extrawidth=120", tostring(M.video_height()))
    if not ok then return nil end
  end
  return M.snap_video_height(ans:match("%d+")) or M.video_height()
end

function M.basename(path)
  return (path:match("([^/\\]+)$") or path)
end

function M.stem(path)
  local b = M.basename(path)
  return (b:gsub("%.[^%.]+$", ""))
end

function M.dirname(path)
  return (path:match("^(.*)[/\\][^/\\]*$") or ".")
end

-- a whole file as a string, nil when it cannot be read ((⚪179) the scripts had their own copies)
function M.read_file(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local s = fh:read("a")
  fh:close()
  return s
end

function M.file_size(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local n = fh:seek("end")
  fh:close()
  return n
end

function M.mmss(sec)
  sec = math.floor(sec)
  return string.format("%d:%02d", sec // 60, sec % 60)
end

-- Does the WAV fit in the JSFX sample memory ("Sample memory (values)", set from __memtop(), depends on the
-- REAPER version)? The JSFX loads the slots in order, so the samples of the slots before `slot` come first.
-- nil = fits or unknown; else {keep = seconds loaded, total = seconds in the file}.
function M.wav_values(path)   -- values the JSFX holds for a WAV (frames x channels), nil if unreadable
  local src = path and reaper.file_exists(path) and reaper.PCM_Source_CreateFromFile(path)
  if not src then return nil end
  local sr, nch, total = reaper.GetMediaSourceSampleRate(src), reaper.GetMediaSourceNumChannels(src), reaper.GetMediaSourceLength(src)
  reaper.PCM_Source_Destroy(src)
  if sr <= 0 or nch <= 0 then return nil end
  return math.floor(total * sr + 0.5) * nch
end
function M.too_long(tr, fx, wav, slot)
  local p = tr and fx and M.param_index(tr, fx, "Sample memory")
  -- ((⚪151) no such parameter (an older JSFX) = unknown: with slot > 1 the memory came out as 1 value and every file
  -- "did not fit"; and a source was made and not freed when the memory was 0)
  if not p then return nil end
  local mem = reaper.TrackFX_GetParam(tr, fx, p)
  if mem <= 0 then return nil end
  if slot and slot > 1 then
    local names = M.engine_samples(tr)
    for k = 1, slot - 1 do
      if names[k] then mem = mem - (M.wav_values(M.SAMPLE_DIR .. M.SEP .. names[k]) or 0) end
    end
    mem = math.max(mem, 1)
  end
  local src = reaper.PCM_Source_CreateFromFile(wav)
  if not src then return nil end
  local sr, nch = reaper.GetMediaSourceSampleRate(src), reaper.GetMediaSourceNumChannels(src)
  local total = reaper.GetMediaSourceLength(src)
  reaper.PCM_Source_Destroy(src)
  if sr <= 0 or nch <= 0 or math.floor(total * sr + 0.5) * nch <= mem then return nil end
  return {keep = math.floor(mem / nch) / sr, total = total}
end

-- ---------------------------------------------------------------- tracks / FX
function M.track_by_name(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, n = reaper.GetTrackName(tr)
    if n == name then return tr end
  end
end

-- (⚪173) the engine track's note of the file a slot file was made from (LOAD writes it; the rekordbox script reads it)
function M.src_key(rname) return "P_EXT:ReaScratch_src_" .. rname end

-- REAPER draws the video this far ahead while it plays / records (video window right-click > Performance tweaks (experimental) > Video cache; in the
-- user's Japanese language pack パフォーマンス調整（実験的） > ビデオキャッシュ), reaper.ini
-- [reaper_video] playback_cache, s; 1 s when not set), and the video processors read the shared memory when they draw:
-- the crossfader / effects / deck B's kept picture show up that late on the screen (⚪56, measured 2026-10-06 in a bare
-- REAPER: 0.87-0.97 s with 1 s, under 0.05 s with 0.1 s; stopped no delay). "All media and video FX are not cached"
-- (fx_mode=3) also took the delay away with 1 s; then nothing is drawn ahead (the video sync places nothing ahead, ⚪53).
-- ⚪33: with the video FX cached (fx_mode 0-2) the crossfader also showed 0.2-0.5 s late while the decks played with
-- REAPER stopped (0.1 s cache, measured 2026-10-06 in the user's REAPER); fx_mode=3: 0.07 s. The menu takes effect at once.
-- Returns the seconds and fx_mode (nil when not set)
function M.video_cache()
  local cache, mode
  for _, line in ipairs(M.ini_section("reaper_video")) do   -- ((⚪151) M.ini_section)
    local x = line:match("^playback_cache=([%d%.]+)")
    if x then cache = tonumber(x) end
    x = line:match("^fx_mode=(%d+)")
    if x then mode = tonumber(x) end
  end
  return cache or 1.0, mode
end

-- ⚪54 Project settings > Video "Items in lower numbered tracks replace higher" (VIDEO_CONFIG flag 0x100, the default of
-- new projects on this PC and a bare REAPER): the track above wins, and "video B view" above "video" covered the deck
-- mix (only deck B showed). With that setting "video B view" goes just below "video" (the mix then still gets deck B as
-- its input track; checked 2026-10-06). The flag has no API: read from a copy of the project saved to a temporary file.
-- Returns true when the upper track wins, nil when it could not be read
function M.video_upper_wins()
  local tmp = M.RES .. M.SEP .. "Data" .. M.SEP .. "ReaScratch_vidcfg.rpp"
  reaper.RecursiveCreateDirectory(M.RES .. M.SEP .. "Data", 0)
  reaper.Main_SaveProjectEx(0, tmp, 0)              -- (a copy: the project keeps its own file and state)
  local h = io.open(tmp, "r")
  if not h then return nil end
  local flags = 0
  for line in h:lines() do
    local f = line:match("^%s*VIDEO_CONFIG%s+%-?%d+%s+%-?%d+%s+(%d+)")
    if f then flags = tonumber(f) break end
    if line:match("^%s*<TRACK") then break end       -- (the project header is over)
  end
  h:close()
  os.remove(tmp)
  return flags & 0x100 ~= 0
end

-- put "video B view" right above "video" (the lower track wins) or right below it (the upper one wins). Returns true
-- when it moved it
function M.place_view_b(video, view)
  local upper = M.video_upper_wins()
  if upper == nil then return false end
  local vi = math.floor(reaper.GetMediaTrackInfo_Value(video, "IP_TRACKNUMBER")) - 1
  local wi = math.floor(reaper.GetMediaTrackInfo_Value(view, "IP_TRACKNUMBER")) - 1
  local want = upper and vi + 1 or vi - 1
  if wi == want then return false end
  reaper.SetOnlyTrackSelected(view)
  reaper.ReorderSelectedTracks(upper and vi + 1 or vi, 0)   -- (the index before which the selected track goes)
  return true
end

function M.ensure_track(name)
  local tr = M.track_by_name(name)
  if tr then return tr, false end
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
  tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr, true
end

-- the ReaScratch JSFX on a track (its FX index), nil when none
function M.engine_fx(tr)
  for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local _, name = reaper.TrackFX_GetFXName(tr, fx, "")
    -- JSFX only: the deck mix Video processor is named after its first line, "ReaScratch deck mix ..."; ((⚪178) not the
    -- performance lanes before it, whatever REAPER shows in the name)
    if name:find("^JS") and name:find(M.JSFX_NAME, 1, true) and not name:find("DJ performance lanes", 1, true) then return fx end
  end
end

-- which deck a JSFX is: its 'Deck' slider (1 = A, 2 = B); a JSFX older than deck B is deck A
function M.engine_deck(tr, fx)
  local p = M.param_index(tr, fx, "Deck (")
  return p and math.floor(reaper.TrackFX_GetParam(tr, fx, p) + 0.5) == 2 and 2 or 1
end

-- the engine of deck 1 (A, the default) or 2 (B): track and FX index, nil when there is none
function M.find_engine(deck)
  deck = deck or 1
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local fx = M.engine_fx(tr)
    if fx and M.engine_deck(tr, fx) == deck then return tr, fx end
  end
end

-- parameter index by name: a name that starts with the label wins over one that merely contains it
-- ("Release note" must not pick "Auto release (ms, 0=hold until Release note)")
function M.param_index(tr, fx, label)
  local contains
  for p = 0, reaper.TrackFX_GetNumParams(tr, fx) - 1 do
    local _, pn = reaper.TrackFX_GetParamName(tr, fx, p, "")
    if pn:sub(1, #label) == label then return p end
    if not contains and pn:find(label, 1, true) then contains = p end
  end
  return contains
end
-- (⚪151) the same, remembered per track: the video sync looked up about 22 names every 0.5 s through all of the JSFX's
-- parameters. Forgotten when the FX index, the number of FX or of parameters changes; a remembered index is used only
-- while its parameter still has the label in its name
local pi_cache = {}
function M.param_index_cached(tr, fx, label)
  local nfx, np = reaper.TrackFX_GetCount(tr), reaper.TrackFX_GetNumParams(tr, fx)
  local c = pi_cache[tr]
  if not c or c.fx ~= fx or c.nfx ~= nfx or c.np ~= np then c = { fx = fx, nfx = nfx, np = np, idx = {} }; pi_cache[tr] = c end
  local p = c.idx[label]
  if p == false then return nil end
  if p then
    local _, pn = reaper.TrackFX_GetParamName(tr, fx, p, "")
    if pn:find(label, 1, true) then return p end
  end
  p = M.param_index(tr, fx, label)
  c.idx[label] = p or false
  return p
end

function M.set_param(tr, fx, label, value)
  local p = M.param_index(tr, fx, label)
  if p then reaper.TrackFX_SetParam(tr, fx, p, value) end
  return p
end

-- The JSFX file sliders: slot 1 = slider2 (Preset is slider1 so that it shows first in the UI), slots 2-8 =
-- sliders 65-71, slider 72 = the slot in use. On the chunk line after "<JS .../reascratch.jsfx" slider n is token n
-- up to 64; then comes the preset name (token 65) and slider n > 64 is token n + 1 (quoted names; split on spaces).
M.SLOTS = 8
M.SLOT_SPAN = 3600          -- the video / audio of slot k sit at (k - 1) x this on the timeline (reascratch_video_sync.lua)
M.FILE_TOKEN = 2
M.SLOT_TOKEN = 73           -- slider 72
function M.file_token(slot) return slot == 1 and 2 or 64 + slot end
-- An empty slot points at this WAV with no samples (the JSFX's default). Without it REAPER fell back to the first file in
-- the folder, so every unused slot loaded that file (2026-10-04). In the kit's Data folder; setup writes it if missing.
M.EMPTY_WAV = "(empty).wav"
function M.ensure_empty_wav()
  local p = M.SAMPLE_DIR .. M.SEP .. M.EMPTY_WAV
  if reaper.file_exists(p) then return true end
  reaper.RecursiveCreateDirectory(M.SAMPLE_DIR, 0)
  local f = io.open(p, "wb")
  if not f then return false end
  -- RIFF header of a 16-bit stereo 48 kHz WAV whose data chunk is empty
  f:write("RIFF", string.pack("<I4", 36), "WAVEfmt ", string.pack("<I4I2I2I4I4I2I2", 16, 1, 2, 48000, 192000, 4, 16),
    "data", string.pack("<I4", 0))
  f:close()
  return true
end
function M.slot_start(slot) return (slot - 1) * M.SLOT_SPAN end

local function split_tokens(s)
  local t = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == " " then
      i = i + 1
    elseif c == '"' then
      local j = s:find('"', i + 1, true) or #s
      t[#t + 1] = s:sub(i, j)
      i = j + 1
    else
      local j = s:find(" ", i, true) or (#s + 1)
      t[#t + 1] = s:sub(i, j - 1)
      i = j
    end
  end
  return t
end

local function unquote(tok)
  if tok then tok = tok:match('^"(.*)"$') or tok end
  if tok and tok ~= "" and tok ~= "none" and tok ~= "ERR" and tok ~= "-" and tok ~= M.EMPTY_WAV then return tok end
end

-- sample file names of the engine: {[slot] = name} (empty slots are nil), and the slot in use (1 when unknown)
function M.engine_samples(tr)
  local names, slot = {}, 1
  local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if not ok then return names, slot end
  local vals = chunk:match("<JS[^\n]*reascratch%.jsfx[^\n]*\n%s*([^\n]*)")
  if not vals then return names, slot end
  local toks = split_tokens(vals)
  for k = 1, M.SLOTS do names[k] = unquote(toks[M.file_token(k)]) end
  slot = math.tointeger(tonumber(toks[M.SLOT_TOKEN] or "") or 1) or 1
  if slot < 1 or slot > M.SLOTS then slot = 1 end
  return names, slot
end

-- sample file name of slot 1 (or of `slot`) of the engine (nil when none). ((⚪179) not used in the kit: kept for
-- a development script)
function M.engine_sample_name(tr, slot)
  return (M.engine_samples(tr))[slot or 1]
end

-- put file names into slots ({[slot] = name}, "" = empty the slot) and, if `use` is given, make it the slot in use,
-- in one chunk change (the JSFX is re-added and loads all slots again)
function M.set_engine_samples(tr, files, use)
  local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if not ok then return false end
  local out, n = {}, 0
  local pending = false
  for line in (chunk .. "\n"):gmatch("(.-)\r?\n") do
    if pending then
      local indent, rest = line:match("^(%s*)(.*)$")
      local toks = split_tokens(rest)
      local need = M.FILE_TOKEN
      for k in pairs(files) do need = math.max(need, M.file_token(k)) end
      if use then need = math.max(need, M.SLOT_TOKEN) end
      for i = #toks + 1, need do toks[i] = (i == 65) and '""' or "-" end   -- token 65 = the preset name
      for k, name in pairs(files) do toks[M.file_token(k)] = '"' .. (name == "" and M.EMPTY_WAV or name) .. '"' end
      if use then toks[M.SLOT_TOKEN] = tostring(use) end
      line = indent .. table.concat(toks, " ")
      pending = false
      n = n + 1
    elseif line:match("<JS%s+.*reascratch%.jsfx") then
      pending = true
    end
    out[#out + 1] = line
  end
  if n == 0 then return false end
  -- REAPER caches the folder listing of a file slider per JSFX; a file created after the JSFX was
  -- loaded shows up as "ERR" unless the JSFX is loaded afresh. Re-add it (rescans), then apply the chunk.
  local fx = M.engine_fx(tr)
  if fx then
    reaper.TrackFX_Delete(tr, fx)
    reaper.TrackFX_AddByName(tr, "JS:" .. M.JSFX, false, 1)
  end
  return reaper.SetTrackStateChunk(tr, table.concat(out, "\n"), false)
end

function M.set_engine_sample(tr, filename, slot)
  return M.set_engine_samples(tr, {[slot or 1] = filename})
end

-- "Send all keyboard input to plug-in" (FX window + menu) = the WAK line of the FX in the track chunk.
-- On, the keys (Space, C, 1-4 ...) reach the JSFX while its window is focused instead of REAPER's own
-- shortcuts (otherwise Space starts REAPER's transport).
function M.set_want_all_keys(tr, on)
  local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if not ok then return false end
  local out, n, inside = {}, 0, false
  for line in (chunk .. "\n"):gmatch("(.-)\r?\n") do
    if line:match("<JS%s+.*reascratch%.jsfx") then
      inside = true
    elseif inside and line:match("^%s*BYPASS ") then
      inside = false   -- next FX without a WAK line. (Not at any "<" line: the JSFX's own <JS_SER> block, written since
                       -- the memory cues (2026-10-03), comes before WAK, and the switch was silently left off.)
    elseif inside and line:match("^%s*WAK ") then
      line = line:gsub("WAK %d+", "WAK " .. (on and 1 or 0), 1)
      inside = false
      n = n + 1
    end
    out[#out + 1] = line
  end
  if n == 0 then return false end
  return reaper.SetTrackStateChunk(tr, table.concat(out, "\n"), false)
end

-- ---------------------------------------------------------------- deck mix (Video processor on "video")
-- puts the code of reascratch_deck_mix.eel into a Video processor on the track (a new one, or the one added before:
-- found by the first line of the code). Returns true when done.
M.DECK_MIX_TAG = "// ReaScratch deck mix"
function M.install_deck_mix(tr, eel_path)
  local code = {}
  for line in io.lines(eel_path) do code[#code + 1] = "|" .. line end
  if #code == 0 then return false end
  local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if not ok then return false end
  local at = chunk:find("<CODE%s*\n%s*|" .. M.DECK_MIX_TAG:gsub("%p", "%%%0"))
  if not at then
    local fx = reaper.TrackFX_AddByName(tr, "Video processor", false, -1)
    if fx < 0 then return false end
    reaper.TrackFX_SetPreset(tr, fx, "Basic helpers: Track opacity/zoom/pan")   -- any code: gives a CODE block to replace
    ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
    -- the last CODE block of the track = the one just added
    local p = 1
    while true do local q = chunk:find("<CODE%s*\n", p) if not q then break end at = q; p = q + 1 end
    if not at then return false end
  end
  local e1 = chunk:find("\n%s*>\n", at)
  if not e1 then return false end
  return reaper.SetTrackStateChunk(tr, chunk:sub(1, at - 1) .. "<CODE\n" .. table.concat(code, "\n") .. chunk:sub(e1), false)
end

-- the deck mix of an existing project brought up to the kit's .eel (⚪91: the video sync script calls it when it finds the
-- project). Only where setup put one (its tag); nothing when it is already the same. Returns true when it changed it.
function M.update_deck_mix(tr, eel_path)
  local code = {}
  local f = io.open(eel_path, "r")
  if not f then return false end
  for line in f:lines() do code[#code + 1] = "|" .. line end
  f:close()
  local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if not ok then return false end
  local at = chunk:find("|" .. M.DECK_MIX_TAG, 1, true)
  if not at then return false end
  -- the code lines as REAPER keeps them (it may indent them): "|..." up to the end of the block
  local have, n = {}, 0
  for line in chunk:sub(at):gmatch("[^\n]*") do
    local t = line:match("^%s*(.-)%s*$")
    if t:sub(1, 1) ~= "|" then if t ~= "" then break end else n = n + 1; have[n] = t end
  end
  local same = n == #code
  for i = 1, n do if not same then break end; same = have[i] == code[i]:match("^(.-)%s*$") end
  if same then return false end
  return M.install_deck_mix(tr, eel_path)
end

-- remove the items of a track (only those starting in [from, to) when given)
-- a black picture where a slot has no video (⚪78): REAPER does not draw the video window again while no video is at the
-- edit cursor, so a sound-only or emptied slot kept showing the last picture (user's report and the recorded test,
-- 2026-10-08). Deck A: an image item over each slot's place on "video" that has nothing there; deck B: its view item
-- points at the picture (reascratch_video_sync.lua). The items are named BLACK_NAME.
M.BLACK_PNG = (debug.getinfo(1, "S").source:match("^@(.*[\\/])") or "") .. "reascratch_black.png"
M.BLACK_NAME = "ReaScratch black"
-- (user's choice 2026-10-13) a sound-only slot (a sample but no video) shows a turning speaker set instead: the loop video
-- (360 degrees, 4 s) looped and played LOOP_TURN s of the head a turn, as the platter (1 turn = 1.8 s, as the Disc video FX):
-- scratched, it turns back and forth with the record. Its items are named LOOP_NAME (an emptied slot stays black)
M.LOOP_VIDEO = (debug.getinfo(1, "S").source:match("^@(.*[\\/])") or "") .. "reascratch_audio_only.avi"
M.LOOP_NAME = "ReaScratch sound only"
M.LOOP_TURN = 1.8
-- the loop video's play rate: its length / the turn (s; the JSFX's turn for its sample, gmem [247] / [248], else LOOP_TURN)
function M.loop_rate(turn)
  if not M._loop_len then
    local src = reaper.PCM_Source_CreateFromFile(M.LOOP_VIDEO)
    M._loop_len = src and reaper.GetMediaSourceLength(src) or 0
    if src then reaper.PCM_Source_Destroy(src) end
  end
  if not turn or turn <= 0.1 then turn = M.LOOP_TURN end
  return M._loop_len > 0 and M._loop_len / turn or 1
end
-- (⚪151) the items whose start lies in slot `slot` (1-8) of a track, and the first of them with its position. One
-- margin for all (the 8 loops before had 0.0005 s, two of them 0.01 s; the items start on the slot's place, a nudge of
-- the video sync moves one by 0.001 s at most)
M.SLOT_TOL = 0.0005
-- (⚪178 stage 5) the picture item the video sync puts on "video" in the performance zone (from M.PF_ZONE on, past every
-- slot) while "play the performance" is on: deck A's frame at REAPER's position. Taken away when the mode goes off and
-- when the sync starts; never a slot's video
M.PERF_VIEW_NAME = "ReaScratch perf view"
function M.is_perf_view(it)
  return M.take_name(reaper.GetActiveTake(it)) == M.PERF_VIEW_NAME
end
function M.slot_items(tr, slot)
  local out, a = {}, M.slot_start(slot)
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if p >= a - M.SLOT_TOL and p < a + M.SLOT_SPAN - M.SLOT_TOL then out[#out + 1] = it end
  end
  return out
end
function M.slot_item(tr, slot)
  local a = M.slot_start(slot)
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if p >= a - M.SLOT_TOL and p < a + M.SLOT_SPAN - M.SLOT_TOL then return it, p end
  end
end
-- (⚪151) a take's name, nil without a take (written as two statements: "tk and select(2, ...)" keeps one value only)
function M.take_name(tk)
  if not tk then return nil end
  local _, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  return nm
end
-- (⚪151) a take's source replaced by src, the old one freed (the take does not free the source it had). False when src is nil
function M.take_set_source(tk, src)
  if not src then return false end
  local old = reaper.GetMediaItemTake_Source(tk)
  reaper.SetMediaItemTake_Source(tk, src)
  if old and old ~= src then reaper.PCM_Source_Destroy(old) end
  return true
end
-- put the black picture (loop = false) or the loop video (loop = true) into a take
function M.set_fill(it, tk, loop)
  M.take_set_source(tk, reaper.PCM_Source_CreateFromFile(loop and M.LOOP_VIDEO or M.BLACK_PNG))   -- ((⚪151) the old source freed)
  reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", loop and M.LOOP_NAME or M.BLACK_NAME, true)
  -- (⚪186) the black picture looped too: the PNG is a 1 s source, and past its first second an unlooped item hands no
  -- frame, so deck A's input in the deck mix became the picture under it (deck B's view: an emptied deck A showed deck B
  -- with deck A's head past 1 s, user's report 2026-10-15, found 2026-10-16)
  reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 1)
  reaper.SetMediaItemTakeInfo_Value(tk, "D_PLAYRATE", loop and M.loop_rate() or 1)
  reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", 0)
end
-- deck A: fill each slot's place on `tr` ("video") that has nothing: the loop video where the engine `eng` (deck A's when
-- nil) has a sample there, else black; a fill already there is switched when its slot changed. Returns the count changed
function M.fill_black(tr, eng)
  if not (tr and reaper.file_exists(M.BLACK_PNG)) then return 0 end
  eng = eng or M.find_engine(1)
  local names = eng and M.engine_samples(eng) or {}
  local loop_ok = reaper.file_exists(M.LOOP_VIDEO)
  local n = 0
  for k = 0, M.SLOTS - 1 do
    local a = k * M.SLOT_SPAN
    local it = M.slot_item(tr, k + 1)
    local loop = loop_ok and names[k + 1] ~= nil
    if not it then
      it = reaper.AddMediaItemToTrack(tr)
      M.set_fill(it, reaper.AddTakeToMediaItem(it), loop)
      reaper.SetMediaItemInfo_Value(it, "D_POSITION", a)
      reaper.SetMediaItemInfo_Value(it, "D_LENGTH", M.SLOT_SPAN - 1)
      n = n + 1
    else
      local tk = reaper.GetActiveTake(it)
      local nm = M.take_name(tk)
      if tk and (nm == M.BLACK_NAME and loop or nm == M.LOOP_NAME and not loop) then M.set_fill(it, tk, loop); n = n + 1
      elseif nm == M.BLACK_NAME and reaper.GetMediaItemInfo_Value(it, "B_LOOPSRC") == 0 then
        -- (⚪186) a black picture put by an older kit (not looped)
        reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 1); n = n + 1
      end
    end
  end
  return n
end
function M.clear_items(tr, from, to)
  for i = reaper.CountTrackMediaItems(tr) - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if not from or (p >= from - 0.0005 and p < to - 0.0005) then reaper.DeleteTrackMediaItem(tr, it) end
  end
end

-- (⚪150) InsertMedia puts the file on the last touched track (40914 makes the selected one that), and the items of a
-- track are in position order: the new item is the one that was not there before, not the track's last item (that
-- was a later slot's video when one had a video)
function M.insert_on_track(tr, path, pos)
  local before = {}
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do before[reaper.GetTrackMediaItem(tr, i)] = true end
  reaper.SetOnlyTrackSelected(tr)
  reaper.Main_OnCommand(40914, 0)   -- Track: set first selected track as last touched track
  reaper.SetEditCurPos(pos or 0, false, false)
  reaper.InsertMedia(path, 0)
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if not before[it] then return it end
  end
end

-- ---------------------------------------------------------------- render configs
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function M.b64(data)
  return ((data:gsub('.', function(x)
    local r, b = '', x:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
    return r
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if #x < 6 then return '' end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
    return B64:sub(c + 1, c + 1)
  end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

M.CFG_WAV24 = "ZXZhdxgAAQ=="   -- WAV 24-bit PCM

-- AVI / MJPEG through REAPER's built-in encoder (works without FFmpeg, verified 2026-10-02 on 7.80).
-- Layout: "PMFF" file(AVI=0) codec(MJPEG=3) vidkbps audio(16-bit PCM=3) audkbps W H fps(float) aspect(1) quality opts\0 opts\0
function M.cfg_avi_mjpeg(w, h, fps, quality)
  return M.b64("PMFF" .. string.pack("<I4I4I4I4I4I4I4fI4I4", 0, 3, 0, 3, 0, w, h, fps, 1, quality or 85) .. "\0\0")
end

-- Render the selected items (RENDER_SETTINGS 32) with the given config, restoring the project's
-- render settings afterwards. Returns the output path (dir/pattern + extension guessed by the caller).
function M.render_selected_items(dir, pattern, cfg)
  local keys_n = { "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_ADDTOPROJ", "RENDER_SRATE", "RENDER_CHANNELS", "RENDER_TAILFLAG" }
  local keys_s = { "RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT" }
  local saved = {}
  for _, k in ipairs(keys_n) do saved[k] = reaper.GetSetProjectInfo(0, k, 0, false) end
  for _, k in ipairs(keys_s) do local _, v = reaper.GetSetProjectInfo_String(0, k, "", false); saved[k] = v end
  reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 32, true)     -- selected media items
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 4, true)    -- bounds = selected items
  reaper.GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)
  reaper.GetSetProjectInfo(0, "RENDER_TAILFLAG", 0, true)      -- no render tail: REAPER's default adds 1 s to selected items (the WAV and the AVI came out 1 s longer than the source)
  reaper.GetSetProjectInfo(0, "RENDER_SRATE", 0, true)         -- project sample rate
  reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", dir, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", pattern, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", cfg, true)
  -- tell the video sync script to keep its hands off while the render runs: it saw the render as "REAPER is playing"
  -- and pressed stop (the rest of the WAV came out silent), and its cursor moves put black frames into the AVI
  -- (both reproduced 2026-10-03). The mark is a time, so one left behind by a crash stops counting.
  reaper.SetExtState("ReaScratch", "busy", tostring(reaper.time_precise()), false)
  -- a muted track renders silent / black: deck B's "video B" track is muted (only "video B view" is meant to show)
  local unmuted = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local tr = reaper.GetMediaItem_Track(reaper.GetSelectedMediaItem(0, i))
    if reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 then reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 0); unmuted[#unmuted + 1] = tr end
  end
  reaper.Main_OnCommand(42230, 0)   -- File: Render project, using the most recent render settings, auto-close render dialog
  for _, tr in ipairs(unmuted) do reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 1) end
  reaper.SetExtState("ReaScratch", "busy", "", false)
  for _, k in ipairs(keys_n) do reaper.GetSetProjectInfo(0, k, saved[k], true) end
  for _, k in ipairs(keys_s) do reaper.GetSetProjectInfo_String(0, k, saved[k], true) end
end

-- ---------------------------------------------------------------- ffmpeg (optional)
-- The MJPEG re-encode prefers ffmpeg when there is one: its AVI has exactly the frames of the source, while
-- REAPER's own render came out shifted by 1-2 frames and sometimes with black frames (2026-10-03).
-- Looked for in: this script folder, REAPER's UserPlugins, PATH, and the usual Homebrew folders (a macOS app
-- does not get the shell's PATH). Returns the program to run, or nil. M.TEST.ffmpeg: false = "none", string = that one.
local WIN = M.SEP == "\\"
local ffmpeg_found
-- A "shared" ffmpeg.exe names the FFmpeg DLLs it needs (avcodec-62.dll ...). When one of them is not next to it, running
-- it made Windows show "ffmpeg.exe - System Error" (a DLL not found) and the window stayed open: an ffmpeg.exe 8.x left
-- in UserPlugins next to 9.x DLLs did that on every take (found 2026-10-06). Such a candidate is skipped without running
-- it. (A static build names none; DLLs found only on PATH are not looked for, so such a build is skipped too.)
-- "every frame as it is" for the ffmpeg found: -fps_mode from 5.1, -vsync before it (4.4 did not know -fps_mode)
function M.ffmpeg_passthrough()
  local v = (M.FFMPEG_MAJOR or 99) + (M.FFMPEG_MINOR or 0) / 100
  return v >= 5.01 and "-fps_mode passthrough" or "-vsync passthrough"
end

function M.ffmpeg_dlls_ok(path)
  if not WIN then return true end
  local data = M.read_file(path)
  if not data then return false end
  local dir = M.dirname(path)
  for name in data:gmatch("(%l+%-%d+%.dll)") do
    if (name:match("^av") or name:match("^sw") or name:match("^postproc")) and not reaper.file_exists(dir .. M.SEP .. name) then
      return false
    end
  end
  return true
end
function M.find_ffmpeg(here)
  if M.TEST and M.TEST.ffmpeg ~= nil then return M.TEST.ffmpeg or nil end
  if ffmpeg_found ~= nil then return ffmpeg_found or nil end
  local exe = WIN and "ffmpeg.exe" or "ffmpeg"
  local cands = {}
  -- one chosen by hand first (REAPER's ExtState ReaScratch / ffmpeg = its full path)
  local chosen = reaper.GetExtState("ReaScratch", "ffmpeg")
  if chosen ~= "" then cands[#cands + 1] = chosen end
  if here and here ~= "" then cands[#cands + 1] = here .. exe end
  cands[#cands + 1] = M.RES .. M.SEP .. "UserPlugins" .. M.SEP .. exe
  -- ((⚪150) Windows: the bare name last, after the full paths that get the DLL check: first, it started a shared build
  -- with DLLs missing and brought up the "System Error" windows)
  if not WIN then cands[#cands + 1] = "ffmpeg" end
  if WIN then
    -- every ffmpeg.exe on PATH, not only the first: a "shared" build (WinGet's Gyan.FFmpeg.Shared) first on PATH failed to
    -- start from REAPER with 0xC0000135 (a DLL not found) while another one later on PATH worked (2026-10-04)
    local list = reaper.ExecProcess('cmd.exe /C where ffmpeg.exe', 5000)
    for line in (list or ""):gmatch("[^\r\n]+") do
      if line:lower():match("ffmpeg%.exe$") then cands[#cands + 1] = line end
    end
    cands[#cands + 1] = "C:\\Program Files\\FFmpeg\\ffmpeg.exe"
    cands[#cands + 1] = "C:\\Program Files\\FFmpeg\\bin\\ffmpeg.exe"
    cands[#cands + 1] = "C:\\ffmpeg\\bin\\ffmpeg.exe"
    cands[#cands + 1] = "ffmpeg"
  end
  if not WIN then
    cands[#cands + 1] = "/opt/homebrew/bin/ffmpeg"
    cands[#cands + 1] = "/usr/local/bin/ffmpeg"
  end
  ffmpeg_found = false
  for _, c in ipairs(cands) do
    if c == "ffmpeg" or (reaper.file_exists(c) and M.ffmpeg_dlls_ok(c)) then
      local out = reaper.ExecProcess('"' .. c .. '" -version', 10000)
      if out and out:match("^0\n") and out:find("ffmpeg version", 1, true) then
        ffmpeg_found = c
        -- its major version ("ffmpeg version 6.1.1-..." / "n7.1.1-..."; a git build "N-12345-..." counts as new)
        local v, mi = out:match("ffmpeg version n?(%d+)%.(%d+)")
        M.FFMPEG_MAJOR = tonumber(v) or 99
        M.FFMPEG_MINOR = tonumber(mi) or 0
        break
      end
    end
  end
  return ffmpeg_found or nil
end

-- (⚪151) the Windows batch files that run ffmpeg in the background (the take videos, the mix, the browser's LOAD and
-- conversion: four writers before). bat_esc doubles every % (a batch file reads %0 in "%06d.jpg" or a % in a file name as
-- its own); write_bat puts @echo off and chcp 65001 (the file is UTF-8: a Japanese file name failed without it) before
-- the lines, with CR LF (opened "w", the CR LF written came out CR CR LF); run_bat starts it without waiting, minimized
-- (ExecProcess: -1 = no wait, -2 = no wait and minimize, as lights_watch: a console window came up over the stage)
function M.bat_esc(s) return (s:gsub("%%", "%%%%")) end
function M.write_bat(path, lines)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write("@echo off\r\nchcp 65001 > nul\r\n", table.concat(lines, "\r\n"), "\r\n")
  f:close()
  return true
end
function M.run_bat(path) reaper.ExecProcess('cmd.exe /C "' .. path .. '"', -2) end
-- ((⚪179) macOS: the same for a shell script, written out twice in the takes before)
function M.write_sh(path, lines)
  local f = io.open(path, "w")
  if not f then return false end
  f:write("#!/bin/sh\n", table.concat(lines, "\n"), "\n")
  f:close()
  return true
end
function M.run_sh(path) reaper.ExecProcess('/bin/sh "' .. path .. '"', -1) end
-- ((⚪179) a file to write, or nil and a line in the log (a full disk, no right to write): the takes went on to h:write
-- and stopped the video sync with an error)
function M.open_w(path)
  local h = io.open(path, "w")
  if not h then M.log(M.T("書き込めません: ", "cannot write: ") .. path) end
  return h
end
-- the lines that end a background batch: its log ends with a line "ReaScratch: done" or "ReaScratch: failed", set by the
-- exit codes (|| goto fail), read by the mix's batch (and "done" / "failed" by a composer script run with --wait)
M.BAT_DONE, M.BAT_FAILED = "ReaScratch: done", "ReaScratch: failed"

-- All-keyframe AVI / MJPEG with ffmpeg, straight from the source file (blocks until done).
-- max_h: larger sources are scaled down, 0 = keep the size; quality 1..100 as in cfg_avi_mjpeg (85 -> -q:v 3).
-- Video only, like REAPER's render (the sound comes from the WAV in the JSFX).
-- Returns true, or false plus the reason.
-- ((⚪179) the arguments after the ffmpeg path, shared with LOAD's batch files (reascratch_browser.lua), which had a copy)
function M.ffmpeg_mjpeg_args(src, out, max_h, quality)
  local q = math.max(2, math.min(31, math.floor((100 - (quality or 85)) / 5 + 0.5)))
  local hexpr = (max_h and max_h > 0) and ("min(ih," .. max_h .. ")") or "ih"
  return string.format('-hide_banner -nostdin -loglevel error -y -i "%s" -map 0:v:0 ' ..
    "-vf \"scale=-2:'2*trunc(%s/2)'\" -c:v mjpeg -pix_fmt yuvj420p -q:v %d -an \"%s\"", src, hexpr, q, out)
end
function M.ffmpeg_mjpeg(ffmpeg, src, out, max_h, quality)
  local cmd = '"' .. ffmpeg .. '" ' .. M.ffmpeg_mjpeg_args(src, out, max_h, quality)
  local res = reaper.ExecProcess(cmd, 3600000)
  if not res then return false, "could not run (or took over an hour)" end
  local code, text = res:match("^(%-?%d+)\n(.*)$")
  if code ~= "0" then return false, "exit " .. tostring(code) .. ": " .. (text or res):gsub("%s+$", "") end
  if not reaper.file_exists(out) or (M.file_size(out) or 0) <= 1024 then return false, "no output file" end
  return true
end

-- The video's audio as a 24-bit stereo WAV (the file's own sample rate), by ffmpeg. Returns true, or false + reason.
function M.ffmpeg_wav_args(src, out)   -- ((⚪179) as ffmpeg_mjpeg_args)
  return string.format('-hide_banner -nostdin -loglevel error -y -i "%s" -map 0:a:0 -vn -ac 2 -c:a pcm_s24le "%s"', src, out)
end
function M.ffmpeg_wav(ffmpeg, src, out)
  local cmd = '"' .. ffmpeg .. '" ' .. M.ffmpeg_wav_args(src, out)
  local res = reaper.ExecProcess(cmd, 3600000)
  if not res then return false, "could not run (or took over an hour)" end
  local code, text = res:match("^(%-?%d+)\n(.*)$")
  if code ~= "0" then return false, "exit " .. tostring(code) .. ": " .. (text or res):gsub("%s+$", "") end
  if not reaper.file_exists(out) or (M.file_size(out) or 0) <= 1024 then return false, "no output file" end
  return true
end

-- Where the sound of a WAV ends: returns total length (s) and the time of the last non-zero sample (s; 0 = all
-- silent), or nil when the file cannot be read. Used after an import to notice a WAV that went silent part-way.
function M.wav_sound_end(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local size = fh:seek("end")
  fh:seek("set", 0)
  local head = fh:read(12)
  if not head or #head < 12 or head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WAVE" then fh:close() return nil end
  local pos, align, rate, d0, dn = 12, nil, nil, nil, nil
  while pos + 8 <= size do
    fh:seek("set", pos)
    local h = fh:read(8)
    if not h or #h < 8 then break end
    local id, n = h:sub(1, 4), (string.unpack("<I4", h, 5))
    if id == "fmt " then
      local b = fh:read(16)
      if b and #b == 16 then rate = string.unpack("<I4", b, 5); align = string.unpack("<I2", b, 13) end
    elseif id == "data" then
      d0 = pos + 8; dn = math.min(n, size - d0)
      break
    end
    pos = pos + 8 + n + (n % 2)
  end
  if not (d0 and rate and align and rate > 0 and align > 0 and dn > 0) then fh:close() return nil end
  local BLOCK = 1 << 20
  local e, last = dn, 0
  while e > 0 do
    local s = math.max(0, e - BLOCK)
    fh:seek("set", d0 + s)
    local blk = fh:read(e - s)
    local i = blk and blk:reverse():find("[^%z]")
    if i then last = s + (#blk - i + 1) break end
    e = s
  end
  fh:close()
  return dn / align / rate, math.ceil(last / align) / rate
end

-- ---------------------------------------------------------------- tempo / beat grid
-- BPM and one beat position of a WAV, for the JSFX "BPM" / "Beat grid" sliders (beat = grid + k * 60 / BPM).
-- Same steps as a Python prototype from development (checked against it number for number):
--   11025 Hz mono through an audio accessor -> 3 bands (one-pole x2 at 200 Hz / 2 kHz), energy per 64 samples
--   -> onset strength (rise of log energy, minus 1 s moving mean) -> rough tempo by autocorrelation (60..200 BPM,
--   weighted toward 120) -> onset peaks folded on the beat period over the whole song, most peaked fold wins
--   (+-4 %, then +-0.1, then 0.01 BPM) -> off-beat as strong as the beat = double tempo; folded into 70..180.
-- Returns bpm (0.01 steps), grid (s), confidence 0..1 (fold peak vs. nearby tempos x 8 s windows agreeing on the
-- phase; a song that changes tempo or has no steady beat comes out low), or nil when it cannot tell at all.
local BT_SR, BT_HOP, BT_NB = 11025, 64, 96
local BT_FR = BT_SR / BT_HOP

local bt_last = {}                       -- (⚪176) estimate_beat's band energies, for estimate_beat_map
local BT_MAX_S = 600                            -- only the first 10 minutes are looked at (time, memory)

-- Energy per 64-sample frame in 3 bands (one-pole x2 low-pass at 200 Hz and 2 kHz: low / mid / high) of the file
-- read at 11025 Hz mono (average of its channels), streamed in blocks. Reads through a temporary track and item
-- (an audio accessor needs a take), removed again before returning. Returns E1, E2, E3, their sums, frame count.
local function bt_band_energy(path, dump)
  local src = reaper.PCM_Source_CreateFromFile(path)
  if not src then return nil end
  local len = reaper.GetMediaSourceLength(src)
  local nch = math.max(1, math.min(2, reaper.GetMediaSourceNumChannels(src)))
  if not len or len <= 0 then reaper.PCM_Source_Destroy(src) return nil end
  reaper.PreventUIRefresh(1)
  local ti = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(ti, false)
  local tr = reaper.GetTrack(0, ti)
  local item = reaper.AddMediaItemToTrack(tr)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, src)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
  local acc = reaper.CreateTakeAudioAccessor(take)
  local a1, a2 = math.exp(-2 * math.pi * 200 / BT_SR), math.exp(-2 * math.pi * 2000 / BT_SR)
  local c1, c2 = 1 - a1, 1 - a2
  local l1, l2, m1, m2 = 0, 0, 0, 0
  local E1, E2, E3 = {}, {}, {}
  local s1, s2, s3 = 0, 0, 0
  local nf = 0
  local total = math.floor(math.min(len, BT_MAX_S) * BT_SR)
  total = total - total % BT_HOP                 -- whole frames only
  local BLK = BT_HOP * 700                       -- ~4 s, whole frames
  local buf = reaper.new_array(BLK * nch)
  local pos = 0
  while pos < total do
    local cnt = math.min(BLK, total - pos)
    buf.clear()
    reaper.GetAudioAccessorSamples(acc, BT_SR, nch, pos / BT_SR, cnt, buf)
    local b = buf.table(1, cnt * nch)
    local y = b
    if nch == 2 then
      y = {}
      for i = 1, cnt do y[i] = 0.5 * (b[2 * i - 1] + b[2 * i]) end
    end
    if dump then dump:write(string.pack("<" .. string.rep("f", cnt), table.unpack(y, 1, cnt))) end
    local i = 0
    for _ = 1, cnt // BT_HOP do
      local e1, e2, e3 = 0, 0, 0
      for _ = 1, BT_HOP do
        i = i + 1
        local x = y[i]
        l1 = c1 * x + a1 * l1; l2 = c1 * l1 + a1 * l2
        m1 = c2 * x + a2 * m1; m2 = c2 * m1 + a2 * m2
        local lo, mid, hi = l2, m2 - l2, x - m2
        e1 = e1 + lo * lo; e2 = e2 + mid * mid; e3 = e3 + hi * hi
      end
      nf = nf + 1
      E1[nf], E2[nf], E3[nf] = e1, e2, e3
      s1, s2, s3 = s1 + e1, s2 + e2, s3 + e3
    end
    pos = pos + cnt
  end
  reaper.DestroyAudioAccessor(acc)
  reaper.DeleteTrack(tr)                         -- the item, take and source go with it
  reaper.PreventUIRefresh(-1)
  return E1, E2, E3, s1, s2, s3, nf, math.min(len, BT_MAX_S)
end

-- onset strength per frame: rise of log(1 + E / (0.01 x mean E)) summed over the bands, minus its 1 s moving mean
local function bt_onsets(E1, E2, E3, s1, s2, s3, nf)
  local o = {}
  for f = 1, nf do o[f] = 0 end
  for _, B in ipairs({ { E1, s1 }, { E2, s2 }, { E3, s3 } }) do
    local E, ref = B[1], 0.01 * B[2] / nf + 1e-12
    local prev = math.log(1 + E[1] / ref)
    for f = 2, nf do
      local L = math.log(1 + E[f] / ref)
      if L > prev then o[f] = o[f] + (L - prev) end
      prev = L
    end
  end
  -- minus the 1 s moving mean (centered), clipped at 0
  local h = math.floor(BT_FR + 0.5) // 2
  local cum = { [0] = 0 }
  for f = 1, nf do cum[f] = cum[f - 1] + o[f] end
  local out = {}
  for f = 1, nf do
    local lo, hi = math.max(0, f - 1 - h), math.min(nf, f + h)
    local v = o[f] - (cum[hi] - cum[lo]) / (hi - lo)
    out[f] = v > 0 and v or 0
  end
  return out, nf
end

local function bt_rough_tempo(o, nf)
  local lag_lo, lag_hi = math.floor(60 * BT_FR / 200), math.ceil(60 * BT_FR / 60)
  local mean = 0
  for f = 1, nf do mean = mean + o[f] end
  mean = mean / nf
  local z = {}
  for f = 1, nf do z[f] = o[f] - mean end
  local r = {}
  for L = lag_lo, lag_hi do
    local s = 0
    for f = 1, nf - L do s = s + z[f] * z[f + L] end
    r[#r + 1] = s / (nf - L)
  end
  local best, best_lag = -math.huge, nil
  for k = 2, #r - 1 do
    local L = lag_lo + k - 1
    local bpm = 60 * BT_FR / L
    local s = r[k] * math.exp(-0.5 * (math.log(bpm / 120, 2) / 0.6) ^ 2)
    if r[k] >= r[k - 1] and r[k] >= r[k + 1] and s > best then
      local den = r[k - 1] - 2 * r[k] + r[k + 1]
      best, best_lag = s, L + (den < 0 and 0.5 * (r[k - 1] - r[k + 1]) / den or 0)
    end
  end
  return best_lag and 60 * BT_FR / best_lag
end

local function bt_peaks(o, nf)
  local pos = {}
  for f = 1, nf do if o[f] > 0 then pos[#pos + 1] = o[f] end end
  local thr = 0
  if #pos > 0 then                               -- 0.1 x 99th percentile (numpy's linear interpolation)
    table.sort(pos)
    local q = 0.99 * (#pos - 1)
    local i = math.floor(q)
    thr = 0.1 * (pos[i + 1] + (q - i) * ((pos[i + 2] or pos[i + 1]) - pos[i + 1]))
  end
  local t, v = {}, {}
  for f = 2, nf - 1 do
    local a, b, c = o[f - 1], o[f], o[f + 1]
    if b > thr and b > a and b >= c then
      local den = a - 2 * b + c
      local off = den < 0 and 0.5 * (a - c) / den or 0
      t[#t + 1] = (f - 1 + off + 0.5) * BT_HOP / BT_SR
      v[#v + 1] = b
    end
  end
  return t, v
end

-- onset weight over the beat phase: BT_NB bins (1-based), linear split, circular [1 2 1] smoothing
local function bt_fold(t, v, period, from, to)
  local h = {}
  for k = 1, BT_NB do h[k] = 0 end
  for i = from or 1, to or #t do
    local ph = (t[i] / period) % 1.0 * BT_NB
    local i0 = math.floor(ph)
    local fr = ph - i0
    local k0 = i0 % BT_NB + 1
    local k1 = k0 % BT_NB + 1
    h[k0] = h[k0] + v[i] * (1 - fr)
    h[k1] = h[k1] + v[i] * fr
  end
  local s = {}
  for k = 1, BT_NB do
    s[k] = 0.25 * h[(k - 2) % BT_NB + 1] + 0.5 * h[k] + 0.25 * h[k % BT_NB + 1]
  end
  return s
end

-- how peaked the fold is: weighted mean height above the plain mean (0 = flat; less tied to the bin edges than
-- the maximum, which picked 93.38 for a 93.37 BPM test)
local function bt_score(t, v, bpm)
  local h = bt_fold(t, v, 60 / bpm)
  local sum, sq = 0, 0
  for k = 1, BT_NB do sum = sum + h[k]; sq = sq + h[k] * h[k] end
  return sq / math.max(sum, 1e-12) - sum / BT_NB, h
end

local function bt_peak_phase(h)   -- phase 0..1 of the highest bin (parabola), and that bin (1-based)
  local k = 1
  for j = 2, BT_NB do if h[j] > h[k] then k = j end end
  local a, b, c = h[(k - 2) % BT_NB + 1], h[k], h[k % BT_NB + 1]
  local den = a - 2 * b + c
  local off = den < 0 and 0.5 * (a - c) / den or 0
  return ((k - 1 + off) / BT_NB) % 1.0, k
end

local BT_SNAP_S = 0.010   -- whole-number snap: most drift allowed over the material (s)
local function bt_refine(t, v, bpm)
  local function search(center, half, step)
    local best, bb = -math.huge, center
    local k = math.floor(half / step + 0.5)
    for j = -k, k do
      local b = center + j * step
      local s = bt_score(t, v, b)
      if s > best then best, bb = s, b end
    end
    return bb
  end
  local b = search(bpm, bpm * 0.04, 0.05)
  b = search(b, 0.1, 0.005)
  b = search(math.floor(b * 100 + 0.5) / 100, 0.02, 0.01)
  return math.floor(b * 100 + 0.5) / 100
end

local function bt_song(E1, E2, E3, s1, s2, s3, nf)
  if nf * BT_HOP < BT_SR * 4 then return nil end
  local o = bt_onsets(E1, E2, E3, s1, s2, s3, nf)
  local omax = 0
  for f = 1, nf do if o[f] > omax then omax = o[f] end end
  if omax <= 0 then return nil end
  local bpm0 = bt_rough_tempo(o, nf)
  if not bpm0 then return nil end
  local t, v = bt_peaks(o, nf)
  if #t < 8 then return nil end
  local bpm = bt_refine(t, v, bpm0)
  -- half / double: an off-beat nearly as strong as the beat means the beat is really twice as fast
  local _, h = bt_score(t, v, bpm)
  local _, k = bt_peak_phase(h)
  if h[(k - 1 + BT_NB // 2) % BT_NB + 1] >= 0.7 * h[k] and bpm * 2 <= 185 then bpm = bt_refine(t, v, bpm * 2) end
  while bpm < 70 do bpm = bt_refine(t, v, bpm * 2) end
  while bpm > 180 do bpm = bt_refine(t, v, bpm / 2) end
  -- whole-number BPM (user's request, 2026-10-04: 159.99 for a 160 song): songs made in a DAW mostly are. Snap when the
  -- whole number drifts at most BT_SNAP_S from the estimate over the material and folds the beats nearly as sharply
  -- (a clip too short to tell 140.02 from 140 snaps too - harmless, it stays within BT_SNAP_S to the end)
  local bi = math.floor(bpm + 0.5)
  if bi ~= bpm and t[#t] * math.abs(bpm - bi) / bpm <= BT_SNAP_S and bt_score(t, v, bi) >= 0.9 * bt_score(t, v, bpm) then bpm = bi end
  local T = 60 / bpm
  local sc
  sc, h = bt_score(t, v, bpm)
  local ph
  ph, k = bt_peak_phase(h)
  local vmax, first = 0, 0
  for i = 1, #v do if v[i] > vmax then vmax = v[i] end end
  for i = 1, #v do if v[i] >= 0.3 * vmax then first = t[i] break end end
  -- beat or off-beat? When the half-beat is nearly as strong (2-beat rock, off-beat hats), take the one the first
  -- strong onset of the song falls on (songs mostly start on a beat)
  if h[(k - 1 + BT_NB // 2) % BT_NB + 1] >= 0.6 * h[k] then
    if math.abs(((first / T - ph) + 0.5) % 1.0 - 0.5) > 0.25 then ph = (ph + 0.5) % 1.0 end
  end
  -- the first beat at or after the first strong onset (any beat would do for the JSFX)
  local grid = ph * T
  grid = grid + math.ceil((first - grid) / T - 0.25) * T
  if grid < 0 then grid = grid + T * math.ceil(-grid / T) end
  -- confidence: (a) the fold at this tempo stands out from nearby tempos, (b) 8 s windows agree on the phase
  local near = {}
  for j = -10, 10 do if j ~= 0 then near[#near + 1] = bt_score(t, v, bpm * (1 + j * 0.004)) end end
  table.sort(near)
  local med = 0.5 * (near[#near // 2] + near[#near // 2 + 1])
  local ca = math.min(1, math.max(0, (sc / math.max(med, 1e-12) - 2) / 4))
  local agree, nw = 0, 0
  local i = 1
  while i <= #t do
    local w = math.floor((t[i] - t[1]) / 8)
    local j = i
    while j < #t and math.floor((t[j + 1] - t[1]) / 8) == w do j = j + 1 end
    if j - i + 1 >= 6 then
      local pp = bt_peak_phase(bt_fold(t, v, T, i, j))
      nw = nw + 1
      if math.abs(((pp - ph) * 2 + 0.5) % 1.0 - 0.5) <= 0.16 then agree = agree + 1 end
    end
    i = j + 1
  end
  local conf = ca * (nw > 0 and agree / nw or 0)
  return bpm, grid, conf
end

-- ((⚪153, user's report 2026-10-13: a 2.44 s drum loop came in with no BPM) short loops. bt_song needs 4 s and its
-- confidence 8 s windows: a clip shorter than about 16 s never passed. A clip of BT_LOOP_S or less is most likely a loop
-- cut to whole beats (Font & Serra, ISMIR 2016, "Tempo estimation for music loops and a simple confidence measure").
-- Same steps as that Python prototype's estimate_loop: the beat counts n = base x 2^k that put 70 .. 180 BPM into
-- the clip (base 1: 4/4; base 3: 3/4, 6/8), doubled while the half-beats of the low + mid bands (kick / snare / bass,
-- not the hats) are half the beats or more; each scored by pulse trains on the onset strength (beats + 0.5 x half-beats
-- at the best phase, as Percival & Tzanetakis, IEEE/ACM TASLP 2014), read circularly (the loop's end runs into its
-- start), each pulse the largest onset within 2 frames; phase 0 kept at 0.8 of the best (a loop starts on a beat).
-- Confidence: the pulses over the mean onset (1.5 -> 0, 3 -> 1) x Font & Serra's measure with the tempo the onsets fold
-- best at within 6 % (the clip's length within half a beat of a whole number of those beats: 0.8 -> 0, 0.95 -> 1; a
-- clip cut anywhere gets little). The BPM stays as the length makes it (see the end of bt_loop)
local BT_LOOP_S = 20

local function bt_loop_onsets(E1, E2, E3, s1, s2, s3, nf)
  local o, olm = {}, {}
  for f = 1, nf do o[f] = 0; olm[f] = 0 end
  for b, B in ipairs({ { E1, s1 }, { E2, s2 }, { E3, s3 } }) do
    local E, ref = B[1], 0.01 * B[2] / nf + 1e-12
    local prev = math.log(1 + E[nf] / ref)        -- (circular: frame 1 rises from the last one)
    for f = 1, nf do
      local L = math.log(1 + E[f] / ref)
      if L > prev then o[f] = o[f] + (L - prev); if b < 3 then olm[f] = olm[f] + (L - prev) end end
      prev = L
    end
  end
  return o, olm
end
local function bt_loop_at(o, nf, x)
  local i = math.floor(x + 0.5)
  local m = 0
  for d = -2, 2 do local w = o[(i + d) % nf + 1]; if w > m then m = w end end
  return m
end
local function bt_loop_train(o, nf, P, n)
  local function sc(k)
    local b, h = 0, 0
    for j = 0, n - 1 do b = b + bt_loop_at(o, nf, k + j * P); h = h + bt_loop_at(o, nf, k + (j + 0.5) * P) end
    return (b + 0.5 * h) / n, b / n, h / n
  end
  local best, bb, bh, bph = -1, 0, 0, 0
  for k = 0, math.ceil(P) - 1 do
    local v, b, h = sc(k)
    if v > best then best, bb, bh, bph = v, b, h, k end
  end
  local v0, b0, h0 = sc(0)
  if v0 >= 0.8 * best then bb, bh, bph = b0, h0, 0 end
  return bb, bh, bph
end
local function bt_loop(E1, E2, E3, s1, s2, s3, nf, dur)
  if nf < 16 or dur <= 0 then return nil end
  local o, olm = bt_loop_onsets(E1, E2, E3, s1, s2, s3, nf)
  local m = 0
  for f = 1, nf do m = m + o[f] end
  m = m / nf
  if m <= 0 then return nil end
  local fr = dur * BT_SR / BT_HOP                 -- frames in the clip (its own length, not the whole frames)
  local fams = {}
  for _, bp in ipairs({ { 1, 1.0 }, { 3, 0.8 } }) do
    local n = bp[1]
    while n <= 64 and 60 * n / dur < 70 do n = n * 2 end
    if n <= 64 and 60 * n / dur < 180 then
      while true do
        local b, h = bt_loop_train(olm, nf, fr / n, n)
        if 2 * n > 64 or 120 * n / dur >= 180 or h < 0.5 * b then break end
        n = n * 2
      end
      local b, h, ph = bt_loop_train(o, nf, fr / n, n)
      fams[#fams + 1] = { (b + 0.5 * h) / m * bp[2], 60 * n / dur, ph * BT_HOP / BT_SR, n }
    end
  end
  if #fams == 0 then return nil end
  table.sort(fams, function(a, b) return a[1] > b[1] end)
  local val, bpm, grid, n = fams[1][1], fams[1][2], fams[1][3], fams[1][4]
  local t, v = bt_peaks(o, nf)
  if #t < 3 then return nil end
  -- Font & Serra's measure with the onsets' own tempo
  local best, bo = -math.huge, bpm
  for j = -60, 60 do
    local b = bpm * (1 + j * 0.001)
    local sc = bt_score(t, v, b)
    if sc > best then best, bo = sc, b end
  end
  local lb = 60 / bo
  local k = math.max(1, math.floor(dur / lb + 0.5))
  local cl = math.max(0, 1 - math.abs(k * lb - dur) / (0.5 * lb))
  local ca = math.min(1, math.max(0, (val - 1.5) / 1.5))
  local cb = math.min(1, math.max(0, (cl - 0.8) / 0.15))
  -- ((2026-10-13, user's report: deck A synced to a 2.54 s drum loop ran ahead) a loop played round repeats every its own
  -- length: its tempo is 60 n / length, decimals and all (94.49 for 4 beats in 2.54 s). Put to the whole number within a
  -- hand cut (95: 14 ms) the other deck followed 95 while the loop went round at 94.49. No whole-number snap (only a value
  -- within 0.005 of one is rounded); the "bpm?" note leaves out a BPM that fits the length (M.bpm_fits). A beat within
  -- 20 ms of the clip's start is put on it (the loop starts on a beat)
  if math.abs(bpm - math.floor(bpm + 0.5)) <= 0.005 then bpm = math.floor(bpm + 0.5) end
  local T = 60 / bpm
  grid = grid % T
  if grid < 0.02 or grid > T - 0.02 then grid = 0 end
  return bpm, grid, ca * cb
end

-- ((⚪153, user's request 2026-10-13) a BPM with decimals is suspect: the note the LOAD / import messages add. Not for a
-- BPM that puts a whole number of beats (1 .. 64, within 0.01) into a clip of 20 s or less (dur): a loop's own tempo,
-- decimals and all (the JSFX's "bpm?" the same)
function M.bpm_fits(bpm, dur)
  if not (bpm and dur) or bpm <= 0 or dur <= 0 or dur > BT_LOOP_S then return false end
  local nb = bpm * dur / 60
  local k = math.floor(nb + 0.5)
  return k >= 1 and k <= 64 and math.abs(nb - k) <= 0.01
end
function M.bpm_note(bpm, dur)
  if not bpm or bpm <= 0 or math.abs(bpm - math.floor(bpm + 0.5)) <= 0.005 or M.bpm_fits(bpm, dur) then return "" end
  return M.T("（小数のBPM: 少しずれていることがあります。bpmの窓でタップか入力で直せます）",
    " (BPM with decimals: it may be a little off; tap the tempo or type the BPM in the bpm box)")
end

function M.estimate_beat(wav)
  local dump = M.TEST and M.TEST.beat_dump and io.open(M.TEST.beat_dump, "wb")   -- samples as read, for the prototype (--raw)
  local E1, E2, E3, s1, s2, s3, nf, dur = bt_band_energy(wav, dump)
  if dump then dump:close() end
  if not E1 or nf < 1 then return nil end
  bt_last = { path = wav, E1 = E1, E2 = E2, E3 = E3, s1 = s1, s2 = s2, s3 = s3, nf = nf }   -- (⚪176 estimate_beat_map)
  local b, g, c = bt_song(E1, E2, E3, s1, s2, s3, nf)
  if dur > BT_LOOP_S then return b, g, c, dur end
  -- (a short clip's song estimate has one or two 8 s windows: its confidence says little; the loop one first)
  local lb, lg, lc = bt_loop(E1, E2, E3, s1, s2, s3, nf, dur)
  if lb and lc >= 0.35 then return lb, lg, lc, dur end
  if b and (not lb or c >= lc) then return b, g, c, dur end
  return lb, lg, lc, dur
end

-- ---------------------------------------------------------------- tempo that moves (⚪176)
-- Beats one by one for a song whose tempo moves, then its beat map, or nil (one tempo is right). Same steps as
-- a Python prototype from development: dynamic programming over estimate_beat's onset strength (D. Ellis 2007, as librosa's
-- beat_track): score[t] = o[t] / std(o) + max over p in [t - 2P, t - P/2] of score[p] - 60 log((t - p) / P)^2, a first
-- pass at the one tempo, a second at the tempo the first pass's beats show around t (median of 8 intervals). The map
-- is used when the tracked beats are steady (median over 16-beat windows of the intervals' spread < 0.04) and their
-- local tempo moves (90th / 10th percentile > 1.04): a synthetic 95 -> 125 BPM ramp and a song in three tempos (120.5 /
-- 131 / 141.5) came out as maps, the user's 8 one-tempo songs not (their tracked beats are not steady enough, or the
-- tempo stays). Anchors every 4th beat (a bar), the one-tempo grid's bars kept.
local BM_TIGHT, BM_SPREAD, BM_MOVE = 60, 0.04, 1.04

local function bm_median(a, i0, i1)      -- median of a[i0 .. i1] (1-based, inclusive)
  local t = {}
  for i = i0, i1 do t[#t + 1] = a[i] end
  table.sort(t)
  local n = #t
  if n == 0 then return nil end
  if n % 2 == 1 then return t[(n + 1) // 2] end
  return 0.5 * (t[n // 2] + t[n // 2 + 1])
end
local function bm_pct(a, q)              -- numpy's linear percentile
  local t = {}
  for i = 1, #a do t[i] = a[i] end
  table.sort(t)
  local x = (#t - 1) * q / 100
  local lo = math.floor(x)
  local hi = math.min(#t - 1, lo + 1)
  return t[lo + 1] + (t[hi + 1] - t[lo + 1]) * (x - lo)
end

local function bm_dp(o, n, sd, period_at)   -- o 1-based; returns beat frames (0-based, as the prototype)
  local score, back = {}, {}
  for t = 0, n - 1 do
    local P = period_at(t)
    local lo, hi = math.floor(t - 2 * P + 0.5), math.floor(t - P / 2 + 0.5)
    local best, bi = 0, -1
    if hi >= 0 then
      lo = math.max(0, lo)
      local cb, cp = -math.huge, -1
      for p = lo, hi do
        local c = score[p] - BM_TIGHT * math.log((t - p) / P) ^ 2
        if c > cb then cb, cp = c, p end
      end
      if cp >= 0 and cb > 0 then best, bi = cb, cp end
    end
    score[t] = o[t + 1] / sd + best
    back[t] = bi
  end
  local P = period_at(n - 1)
  local s0 = math.max(0, n - math.floor(P))
  local t, bs = s0, -math.huge
  for f = s0, n - 1 do if score[f] > bs then bs, t = score[f], f end end
  local rev = {}
  while t >= 0 do rev[#rev + 1] = t; t = back[t] end
  local out = {}
  for i = #rev, 1, -1 do out[#out + 1] = rev[i] end
  return out
end

function M.estimate_beat_map(wav, bpm, grid)
  local E = bt_last.path == wav and bt_last or nil
  if not E then
    local E1, E2, E3, s1, s2, s3, nf = bt_band_energy(wav)
    if not E1 then return nil, "could not read" end
    E = { E1 = E1, E2 = E2, E3 = E3, s1 = s1, s2 = s2, s3 = s3, nf = nf }
  end
  local o, n = bt_onsets(E.E1, E.E2, E.E3, E.s1, E.s2, E.s3, E.nf)
  local mean, sd = 0, 0
  for f = 1, n do mean = mean + o[f] end
  mean = mean / n
  for f = 1, n do sd = sd + (o[f] - mean) ^ 2 end
  sd = math.sqrt(sd / n)
  if sd <= 0 then sd = 1 end
  local rough = bpm and bpm > 0 and bpm or bt_rough_tempo(o, n)
  if not rough then return nil, "no tempo" end
  local P0 = 60 * BT_FR / rough
  local b = bm_dp(o, n, sd, function() return P0 end)
  if #b >= 8 then
    local ibi, mids = {}, {}
    for i = 1, #b - 1 do ibi[i] = b[i + 1] - b[i]; mids[i] = (b[i + 1] + b[i]) / 2 end
    b = bm_dp(o, n, sd, function(t)
      local lo, hi = 1, #mids + 1                  -- searchsorted (left): the count of mids below t
      while lo < hi do local m = (lo + hi) // 2; if mids[m] < t then lo = m + 1 else hi = m end end
      local i = lo - 1
      local P = bm_median(ibi, math.max(0, i - 4) + 1, math.min(#ibi, i + 4)) or P0
      return math.min(math.max(P, P0 / 1.6), P0 * 1.6)
    end)
  end
  if #b < 16 then return nil, "too few tracked beats" end
  local ts = {}
  for i = 1, #b do ts[i] = b[i] / BT_FR end
  local ibi = {}
  for i = 1, #ts - 1 do ibi[i] = ts[i + 1] - ts[i] end
  local sp = {}
  for i = 0, math.max(1, #ibi - 15) - 1 do
    local m, v, c = 0, 0, 0
    for j = i + 1, math.min(#ibi, i + 16) do m = m + ibi[j]; c = c + 1 end
    m = m / c
    for j = i + 1, math.min(#ibi, i + 16) do v = v + (ibi[j] - m) ^ 2 end
    sp[#sp + 1] = math.sqrt(v / c) / m
  end
  local spread = bm_median(sp, 1, #sp)
  local lb = {}
  for i = 0, #ibi - 1 do lb[i + 1] = 60 / bm_median(ibi, math.max(0, i - 4) + 1, math.min(#ibi, i + 4)) end
  local p10, p90 = bm_pct(lb, 10), bm_pct(lb, 90)
  local info = string.format("%d tracked beats, %.1f .. %.1f BPM, spread %.3f", #ts, p10, p90, spread)
  if spread >= BM_SPREAD then return nil, "one tempo (tracked beats not steady: " .. info .. ")" end
  if p90 / p10 <= BM_MOVE then return nil, "one tempo (it does not move: " .. info .. ")" end
  local k0 = 0
  if bpm and bpm > 0 and grid then k0 = math.floor((ts[1] - grid) * bpm / 60 + 0.5) % 4 end
  local map = {}
  for i = 1, #ts do
    if (k0 + i - 1) % 4 == 0 or i == #ts then map[#map + 1] = { ts[i], k0 + i - 1 } end
  end
  return M.gb_thin(map), info, (p10 + p90) / 2
end

-- ---------------------------------------------------------------- musical key (⚪175)
-- The key of a WAV, for the JSFX "Musical key" slider. libKeyFinder (github.com/mixxxdj/libkeyfinder, Ibrahim Sha'ath,
-- GPL-3.0-or-later like this kit) re-written in Lua, checked number for number against a Python prototype:
--   4410 Hz mono through an audio accessor -> Blackman frames of 16384 (hop 8192: libKeyFinder's 4096 halved for the
--   time, the same score on 120 GiantSteps songs) -> |FFT| -> 72 bands C1..B6, each a (1 - cos) kernel over the bins
--   0.8 semitone wide, normalised by its sum x the band's frequency -> mean over the frames -> cosine similarity with
--   the tone profiles (Sha'ath's major / minor x octave weights) for the 24 keys.
-- On 120 GiantSteps Key songs (EDM): 57 % the same key, MIREX score 0.67. When the best key is less than
-- 0.002 ahead of the next (15 % of those songs, of which 22 % right) it is marked unsure.
-- Returns k (0-11 = C..B major, 12-23 = C..B minor), the lead over the next key, or nil (silent, shorter than 4 s).
local KY_SR, KY_N, KY_HOP = 4410, 16384, 8192
local KY_MAJ = { 7.23900502618145225142, 3.50351166725158691406, 3.58445177536649417505, 2.84511816478676315967,
  5.81898892118549859731, 4.55865057415321039969, 2.44778850545506543313, 6.99473192146829525484,
  3.39106613673504853068, 4.55614256655143456953, 4.07392666663523606019, 4.45932757378886890365 }
local KY_MIN = { 7.00255045060284420089, 3.14360279015996679775, 4.35904319714962529275, 5.40418120718934069657,
  3.67234420879306133756, 4.08971184917797891956, 3.90791435991553992579, 6.19960288562316463867,
  3.63424625625277419871, 2.87241191079875557435, 5.35467999794542670600, 3.83242038595048351013 }
local KY_OCT = { 0.39997267549999998559, 0.55634425248300645173, 0.52496636345143543600,
  0.60847548384277727607, 0.59898115679999996974, 0.49072435317960994006 }
M.KEY_UNSURE = 0.002
local KEY_NAMES = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }

-- in-place radix-2 FFT of n complex values (re, im: 1-based tables), forward
local function ky_fft(re, im, n, cs, sn, rev)
  for i = 1, n do
    local j = rev[i]
    if j > i then re[i], re[j] = re[j], re[i]; im[i], im[j] = im[j], im[i] end
  end
  local len = 2
  while len <= n do
    local half, step = len // 2, n // len
    for s = 0, n - 1, len do
      local k = 0
      for j = 1, half do
        local a, b = s + j, s + j + half
        local wr, wi = cs[k + 1], sn[k + 1]
        local xr, xi = re[b], im[b]
        local tr, ti = xr * wr - xi * wi, xr * wi + xi * wr
        re[b], im[b] = re[a] - tr, im[a] - ti
        re[a], im[a] = re[a] + tr, im[a] + ti
        k = k + step
      end
    end
    len = len * 2
  end
end

function M.estimate_key(wav)
  local src = reaper.PCM_Source_CreateFromFile(wav)
  if not src then return nil end
  local len = reaper.GetMediaSourceLength(src)
  local nch = math.max(1, math.min(2, reaper.GetMediaSourceNumChannels(src)))
  if not len or len < 4 then reaper.PCM_Source_Destroy(src) return nil end
  -- the samples (mono) through a temporary track (an audio accessor needs a take), as bt_band_energy
  reaper.PreventUIRefresh(1)
  local ti = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(ti, false)
  local tr = reaper.GetTrack(0, ti)
  local item = reaper.AddMediaItemToTrack(tr)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, src)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
  local acc = reaper.CreateTakeAudioAccessor(take)
  local total = math.floor(math.min(len, BT_MAX_S) * KY_SR)
  local y = {}
  local BLK = 44100
  local buf = reaper.new_array(BLK * nch)
  local pos = 0
  while pos < total do
    local cnt = math.min(BLK, total - pos)
    buf.clear()
    reaper.GetAudioAccessorSamples(acc, KY_SR, nch, pos / KY_SR, cnt, buf)
    local b = buf.table(1, cnt * nch)
    if nch == 2 then
      for i = 1, cnt do y[pos + i] = 0.5 * (b[2 * i - 1] + b[2 * i]) end
    else
      for i = 1, cnt do y[pos + i] = b[i] end
    end
    pos = pos + cnt
  end
  reaper.DestroyAudioAccessor(acc)
  reaper.DeleteTrack(tr)
  reaper.PreventUIRefresh(-1)
  if M.TEST and M.TEST.key_dump then
    local fh = io.open(M.TEST.key_dump, "wb")
    for i = 1, total, 4096 do fh:write(string.pack("<" .. string.rep("f", math.min(4096, total - i + 1)), table.unpack(y, i, math.min(total, i + 4095)))) end
    fh:close()
  end
  -- the real FFT of N samples as the complex FFT of N / 2 (even samples real, odd imaginary), then split
  local N, H = KY_N, KY_N // 2
  local cs, sn, rev = {}, {}, {}
  for k = 0, H - 1 do cs[k + 1] = math.cos(-2 * math.pi * k / H); sn[k + 1] = math.sin(-2 * math.pi * k / H) end
  local bits = 0
  while (1 << bits) < H do bits = bits + 1 end
  for i = 0, H - 1 do
    local r, x = 0, i
    for _ = 1, bits do r = (r << 1) | (x & 1); x = x >> 1 end
    rev[i + 1] = r + 1
  end
  local win = {}
  for n = 0, N - 1 do win[n + 1] = 0.42 - 0.5 * math.cos(2 * math.pi * n / (N - 1)) + 0.08 * math.cos(4 * math.pi * n / (N - 1)) end
  local wc, ws = {}, {}   -- e^(-2 pi i k / N) for the split
  for k = 0, H - 1 do wc[k + 1] = math.cos(-2 * math.pi * k / N); ws[k + 1] = math.sin(-2 * math.pi * k / N) end
  -- the band kernels
  local q = 0.8 * (2 ^ (1 / 12) - 1)
  local kb, kc = {}, {}   -- first bin, coefficients (1-based)
  local top = 0
  for b = 0, 71 do
    local f = 440 * 2 ^ ((b + 24 - 69) / 12)
    local c = f * N / KY_SR
    local w = c * q
    local beg = c - w / 2
    local first, last = math.ceil(beg), math.floor(beg + w)
    local co, sum = {}, 0
    for bin = first, last do local v = 1 - math.cos(2 * math.pi * (bin - beg) / w); co[#co + 1] = v; sum = sum + v end
    for j = 1, #co do co[j] = co[j] / sum * f end
    kb[b + 1], kc[b + 1] = first, co
    if last > top then top = last end
  end
  -- frames (zero padded at the end, as libKeyFinder)
  local hops = math.max(1, math.ceil(total / KY_HOP))
  local acc72 = {}
  for b = 1, 72 do acc72[b] = 0 end
  local re, im, mag = {}, {}, {}
  for h = 0, hops - 1 do
    local o = h * KY_HOP
    for n = 1, H do
      local i0, i1 = o + 2 * n - 1, o + 2 * n
      re[n] = (y[i0] or 0) * win[2 * n - 1]
      im[n] = (y[i1] or 0) * win[2 * n]
    end
    ky_fft(re, im, H, cs, sn, rev)
    for k = 0, top do
      local k1, k2 = k % H + 1, (H - k) % H + 1
      local zr, zi, cr, ci = re[k1], im[k1], re[k2], -im[k2]   -- Z[k], conj(Z[H - k])
      local er, ei = 0.5 * (zr + cr), 0.5 * (zi + ci)          -- even part
      local orr, oi = 0.5 * (zi - ci), -0.5 * (zr - cr)         -- odd part = (Z - conj) / 2i
      local tc, ts
      if k < H then tc, ts = wc[k + 1], ws[k + 1] else tc, ts = -wc[k - H + 1], -ws[k - H + 1] end
      local xr, xi = er + orr * tc - oi * ts, ei + orr * ts + oi * tc
      mag[k] = math.sqrt(xr * xr + xi * xi)
    end
    for b = 1, 72 do
      local first, co, s = kb[b], kc[b], 0
      for j = 1, #co do s = s + mag[first + j - 1] * co[j] end
      acc72[b] = acc72[b] + s
    end
  end
  for b = 1, 72 do acc72[b] = acc72[b] / hops end
  -- the 24 keys
  local cn = 0
  for b = 1, 72 do cn = cn + acc72[b] * acc72[b] end
  if cn <= 0 then return nil end
  local best, bk, second = -1, nil, -1
  for k = 0, 23 do
    local prof = k < 12 and KY_MAJ or KY_MIN
    local t = k % 12
    local dot, pn = 0, 0
    for b = 0, 71 do
      local p = KY_OCT[b // 12 + 1] * prof[(b % 12 - t) % 12 + 1]
      dot = dot + acc72[b + 1] * p; pn = pn + p * p
    end
    local s = dot / (math.sqrt(cn) * math.sqrt(pn))
    if s > best then second = best; best, bk = s, k elseif s > second then second = s end
  end
  if M.TEST and M.TEST.key_out then M.TEST.key_out.chroma = acc72; M.TEST.key_out.score = best end
  return bk, best - second
end

-- the JSFX's key value: 0 = unknown, 1-12 = C..B major, 13-24 = C..B minor, +24 = unsure
function M.key_code(k, lead)
  if not k then return 0 end
  return k + 1 + (lead < M.KEY_UNSURE and 24 or 0)
end

-- slot (1-8) of the deck on track tr (its JSFX fx) gets the key value: through the shared memory (no slider left for it),
-- [302] deck A / [305] deck B = the value, +1 = the slot, +2 = a counter the JSFX watches
function M.set_key(tr, fx, slot, code)
  local p = M.param_index(tr, fx, "Deck (1 = A")
  local base = p and reaper.TrackFX_GetParam(tr, fx, p) >= 1.5 and 305 or 302
  reaper.gmem_attach(M.GMEM)
  reaper.gmem_write(base, code or 0)
  reaper.gmem_write(base + 1, slot)
  reaper.gmem_write(base + 2, reaper.gmem_read(base + 2) + 1)
end

-- "Am", "F#" (with "?" when unsure); "" for 0
function M.key_name(code)
  code = math.floor(code or 0)
  if code < 1 or code > 48 then return "" end
  local k = (code - 1) % 24
  return KEY_NAMES[k % 12 + 1] .. (k >= 12 and "m" or "") .. (code > 24 and "?" or "")
end

-- ---------------------------------------------------------------- auto gain (⚪185)
-- (user's choice 2026-10-15, as the DJ programs' Auto Gain: Serato, rekordbox, Mixxx's ReplayGain) each sample's loudness
-- is measured when it comes in (import, LOAD, setup for the slots that have none) and the JSFX turns the deck up / down
-- to a target loudness (setup: Samples tab), never up past the sample's peak (less LD_PK_MARGIN). The measure is
-- ITU-R BS.1770 / EBU R128 integrated loudness, as libebur128 (MIT) does it: K-weighting (a high shelf and a high pass),
-- the mean square of 400 ms blocks every 100 ms, gated at -70 LUFS and at 10 LU under the mean of those. Read at LD_SR
-- (24 kHz: the K-weighting's shelf sits at 1.7 kHz; a 3-minute sample in about a second) through an audio accessor,
-- the first BT_MAX_S seconds. Returns integrated loudness (LUFS), the sample peak (dBFS) and the seconds it took;
-- nil for a silent or unreadable file
M.LD_SR = 24000
M.LD_PK_MARGIN = 1
function M.estimate_loudness(wav)
  local t0 = reaper.time_precise()
  local src = reaper.PCM_Source_CreateFromFile(wav)
  if not src then return nil end
  local len = reaper.GetMediaSourceLength(src)
  local nch = math.max(1, math.min(2, reaper.GetMediaSourceNumChannels(src)))
  if not len or len < 0.5 then reaper.PCM_Source_Destroy(src) return nil end
  reaper.PreventUIRefresh(1)
  local ti = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(ti, false)
  local tr = reaper.GetTrack(0, ti)
  local item = reaper.AddMediaItemToTrack(tr)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, src)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
  local acc = reaper.CreateTakeAudioAccessor(take)
  local sr = M.LD_SR
  -- K-weighting for sr (BS.1770's two stages, by their analogue prototypes as libebur128)
  local f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
  local K = math.tan(math.pi * f0 / sr); local Vh = 10 ^ (G / 20); local Vb = Vh ^ 0.4996667741545416
  local a0 = 1 + K / Q + K * K
  local b10, b11, b12 = (Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0
  local a11, a12 = 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0
  f0, Q = 38.13547087602444, 0.5003270373238773
  K = math.tan(math.pi * f0 / sr); a0 = 1 + K / Q + K * K
  local a21, a22 = 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0
  local st = {}   -- per channel: x1 x2 y1 y2 of stage 1, then stage 2's
  for c = 1, nch do st[c] = { 0, 0, 0, 0, 0, 0, 0, 0 } end
  local total = math.floor(math.min(len, BT_MAX_S) * sr)
  local sub = sr // 10                                   -- 100 ms
  local subs, acc_sq, n_sub, peak = {}, 0, 0, 0
  local BLK = sr
  local buf = reaper.new_array(BLK * nch)
  local pos = 0
  while pos < total do
    local cnt = math.min(BLK, total - pos)
    buf.clear()
    reaper.GetAudioAccessorSamples(acc, sr, nch, pos / sr, cnt, buf)
    local b = buf.table(1, cnt * nch)
    for i = 1, cnt do
      for c = 1, nch do
        local x = b[(i - 1) * nch + c]
        local ax = x < 0 and -x or x
        if ax > peak then peak = ax end
        local s = st[c]
        local y = b10 * x + b11 * s[1] + b12 * s[2] - a11 * s[3] - a12 * s[4]
        s[2] = s[1]; s[1] = x; s[4] = s[3]; s[3] = y
        local z = y - 2 * s[5] + s[6] - a21 * s[7] - a22 * s[8]
        s[6] = s[5]; s[5] = y; s[8] = s[7]; s[7] = z
        acc_sq = acc_sq + z * z
      end
      n_sub = n_sub + 1
      if n_sub == sub then subs[#subs + 1] = acc_sq / sub; acc_sq, n_sub = 0, 0 end
    end
    pos = pos + cnt
  end
  reaper.DestroyAudioAccessor(acc)
  reaper.DeleteTrack(tr)
  reaper.PreventUIRefresh(-1)
  -- 400 ms blocks every 100 ms, the gates
  local blocks = {}
  for i = 4, #subs do blocks[#blocks + 1] = (subs[i] + subs[i - 1] + subs[i - 2] + subs[i - 3]) / 4 end
  local function lufs(z) return -0.691 + 10 * math.log(z, 10) end
  local sum, n = 0, 0
  for _, z in ipairs(blocks) do if z > 0 and lufs(z) > -70 then sum, n = sum + z, n + 1 end end
  if n == 0 or peak <= 0 then return nil end
  local rel = lufs(sum / n) - 10
  local sum2, n2 = 0, 0
  for _, z in ipairs(blocks) do if z > 0 and lufs(z) > -70 and lufs(z) > rel then sum2, n2 = sum2 + z, n2 + 1 end end
  if n2 == 0 then return nil end
  return lufs(sum2 / n2), 20 * math.log(peak, 10), reaper.time_precise() - t0
end

-- slot (1-8) of the deck on track tr (its JSFX fx) gets its loudness and peak: through the shared memory (as set_key),
-- [380] deck A / [384] deck B = loudness (LUFS; 0 = unknown), +1 = the peak (dBFS), +2 = the slot, +3 = a counter
function M.set_loudness(tr, fx, slot, lufs, peak)
  local p = M.param_index(tr, fx, "Deck (1 = A")
  local base = p and reaper.TrackFX_GetParam(tr, fx, p) >= 1.5 and 384 or 380
  reaper.gmem_attach(M.GMEM)
  reaper.gmem_write(base, lufs or 0)
  reaper.gmem_write(base + 1, peak or 0)
  reaper.gmem_write(base + 2, slot)
  reaper.gmem_write(base + 3, reaper.gmem_read(base + 3) + 1)
end

-- ---------------------------------------------------------------- rekordbox (⚪177)
-- Cues, beat grid and key from rekordbox's XML (rekordbox: File > Export Collection in xml format; the format:
-- pyrekordbox.readthedocs.io/en/stable/formats/xml.html). The XML's place is kept in the ExtState
-- ReaScratch/rekordbox_xml (reascratch_rekordbox.lua sets it). A track is found by its file (Location) or, failing
-- that, by its file name without the extension (a video converted to MJPEG / a WAV made from it keeps the name):
--   TRACK  Location="file://localhost/C:/Music/a%20b.mp4" AverageBpm Tonality ("Am", "F#m", "Db"; also "8A")
--   TEMPO  Inizio (s) Bpm Metro Battito (the beat of the bar there, 1-4); more than one = the tempo changes
--   POSITION_MARK Type (0 cue, 4 loop: its start) Start (s) Num (-1 memory cue, 0-7 hot cue A-H)
-- (⚪180) the same file can also be Traktor's collection.nml or VirtualDJ's database.xml (told apart by what is in it;
-- read into the same values):
--   Traktor   ENTRY TITLE > LOCATION VOLUME ("C:") DIR ("/:Users/:me/:") FILE, TEMPO BPM, INFO KEY / MUSICAL_KEY VALUE,
--             CUE_V2 TYPE (0 cue, 3 load, 4 grid = a bar's first beat, 5 loop) START (ms) HOTCUE
--             (-1 none, 0-7), a grid marker's GRID BPM
--   VirtualDJ Song FilePath > Tags Title, Scan Bpm (seconds a beat) Key, Poi Pos (s) Type (cue / none = a cue,
--             beatgrid = a bar's first beat, loop) Num (hot cue 1-8)
M.RB_KEY = "rekordbox_xml"
M.RB_KINDS = { rekordbox = "rekordbox", traktor = "Traktor", vdj = "VirtualDJ", reascratch = "ReaScratch track data" }
local rb_cache = { path = nil, data = nil, tracks = nil, by_loc = nil, by_stem = nil }

local function rb_unxml(s)
  return (s:gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&#(%d+);", function(n)
    return utf8.char(tonumber(n)) end):gsub("&amp;", "&"))
end

local function rb_attrs(s)
  local t = {}
  for k, v in s:gmatch('([%w_]+)="([^"]*)"') do t[k] = rb_unxml(v) end
  return t
end

-- a file path in one form for comparing: "/" separators, lower case on Windows, no "file://localhost"
function M.rb_norm(path)
  if not path or path == "" then return "" end
  path = path:gsub("^file://localhost", ""):gsub("^file://", "")
  path = path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  path = path:gsub("[/\\]+", "/")
  if path:match("^/%a:/") then path = path:sub(2) end        -- "/C:/..." -> "C:/..."
  if M.SEP == "\\" then path = path:lower() end
  return path
end

-- the name a track is found by: the file name without the extension, lower case, without what ReaScratch adds
-- (the MJPEG conversion's "_mjpeg" / "_960_mjpeg", a second import's "_2", REAPER's "-001")
function M.rb_stem(path)
  local s = M.stem(path or ""):lower()
  for _ = 1, 3 do
    s = s:gsub("_%d*_?mjpeg$", ""):gsub("_mjpeg$", ""):gsub("_%d$", ""):gsub("%-%d%d%d$", "")
  end
  return s
end

local function rb_load(xml)
  local data = M.read_file(xml)
  if not data then return nil, "cannot open" end
  -- ((⚪179) it was read again only when the size changed: a cue moved in rekordbox (12.345 -> 12.346) keeps the size, and
  -- LOAD (in the video sync, which keeps this cache until REAPER closes) went on with the old values. Plain Lua has no
  -- file time: the whole text is compared (a LOAD reads it once, tens of ms for a large collection))
  if rb_cache.path == xml and rb_cache.data == data and rb_cache.tracks then return true end
  local tracks, by_loc, by_stem = {}, {}, {}
  -- (⚪180) which program's: Traktor's NML, VirtualDJ's database, else rekordbox's
  local kind, tag, start = "rekordbox", "TRACK", data:find("<COLLECTION", 1, true)
  if data:find('<PRODUCT Name="ReaScratch"', 1, true) then kind = "reascratch"   -- (⚪181) ReaScratch's own (rb_write)
  elseif data:find("<NML", 1, true) then kind, tag = "traktor", "ENTRY"
  elseif data:find("<VirtualDJ_Database", 1, true) then kind, tag, start = "vdj", "Song", 1 end
  if not start then return nil, "no COLLECTION (not a rekordbox / Traktor / VirtualDJ file?)" end
  local stop = kind == "vdj" and #data or (data:find("</COLLECTION>", start, true) or #data)
  local i = start
  while true do
    local a, b, attrs, close = data:find("<" .. tag .. "%s([^>]-)(/?)>", i)
    if not a or a > stop then break end
    local body = ""
    if close == "" then
      local e = data:find("</" .. tag .. ">", b, true) or stop
      body = data:sub(b + 1, e - 1); i = e + #tag + 3
    else
      i = b + 1
    end
    local t = rb_attrs(attrs)
    t.body, t.kind = body, kind
    if kind == "traktor" then
      -- LOCATION: VOLUME "C:" + DIR "/:Users/:me/:Music/:" + FILE; a volume that is not a drive (macOS: "Macintosh HD")
      -- is left out
      local la = body:match("<LOCATION%s([^>]-)/?>")
      local l = la and rb_attrs(la) or {}
      local vol = (l.VOLUME or ""):match("^%a:$") and l.VOLUME or ""
      t.Name = t.TITLE
      t.Location = l.FILE and (vol .. (l.DIR or "/"):gsub("/:", "/") .. l.FILE) or ""
      -- (macOS: a volume's own path too, "/Volumes/<name>/..", for files on another drive; as Mixxx reads it)
      if l.FILE and vol == "" and (l.VOLUME or "") ~= "" then t.Location2 = "/Volumes/" .. l.VOLUME .. t.Location end
    elseif kind == "vdj" then
      local ta = body:match("<Tags%s([^>]-)/?>")
      t.Name = ta and rb_attrs(ta).Title or nil
      t.Location = t.FilePath or ""
    end
    tracks[#tracks + 1] = t
    if t.Location2 then by_loc[M.rb_norm(t.Location2)] = t end
    local n = M.rb_norm(t.Location)
    if n ~= "" then
      by_loc[n] = t
      local st = M.rb_stem(n)
      by_stem[st] = by_stem[st] or {}
      table.insert(by_stem[st], t)
    end
  end
  rb_cache = { path = xml, data = data, tracks = tracks, by_loc = by_loc, by_stem = by_stem, kind = kind }
  return true
end

-- rekordbox's key name -> the JSFX's key value (1-12 major C..B, 13-24 minor); "" / unknown -> 0
local RB_PC = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
function M.rb_key_code(s)
  if not s or s == "" then return 0 end
  s = s:gsub("%s", "")
  local ok_n, ok_dm = s:match("^(%d+)([dmDM])$")             -- (⚪180) Open Key (Traktor): 1d = C, 1m = Am = Camelot + 7
  if ok_n then s = tostring((tonumber(ok_n) + 6) % 12 + 1) .. (ok_dm:lower() == "d" and "B" or "A") end
  local num, ab = s:match("^(%d+)([ABab])$")                 -- Camelot: 8B = C, 8A = Am, +1 = a fifth up
  if num then
    num = tonumber(num)
    if num < 1 or num > 12 then return 0 end
    local pc = ((num - 8) * 7) % 12
    if ab:upper() == "A" then return (pc + 9) % 12 + 13 end
    return pc + 1
  end
  local l, acc, rest = s:match("^([A-Ga-g])([#b]?)(.*)$")
  if not l then return 0 end
  local pc = RB_PC[l:upper()]
  if acc == "#" then pc = pc + 1 elseif acc == "b" then pc = pc - 1 end
  pc = pc % 12
  local minor = rest:lower():match("^m") ~= nil and not rest:lower():match("^maj")
  return pc + 1 + (minor and 12 or 0)
end

-- the rekordbox track for a sample: by any of the paths given (the source video first), then by its name.
-- Returns the track's values or nil, why
function M.rb_find(paths)
  local xml = reaper.GetExtState("ReaScratch", M.RB_KEY)
  if xml == "" then return nil, "no rekordbox XML chosen" end
  local ok, err = rb_load(xml)
  if not ok then return nil, "rekordbox XML " .. xml .. ": " .. tostring(err) end
  local t, how
  for _, p in ipairs(paths) do
    t = p and rb_cache.by_loc[M.rb_norm(p)]
    if t then how = "file" break end
  end
  if not t then
    for _, p in ipairs(paths) do
      local list = p and rb_cache.by_stem[M.rb_stem(p)]
      if list then t = list[1]; how = #list > 1 and ("name (" .. #list .. " tracks with it: the first)") or "name" break end
    end
  end
  if not t then return nil, "not in the " .. M.RB_KINDS[rb_cache.kind] .. " file" end
  local r = { name = t.Name or "", how = how, hot = {}, mem = {}, tempos = {}, key = 0, kind = t.kind }
  if t.kind == "traktor" then
    -- (⚪180) Traktor: one BPM (TEMPO), grid markers = a bar's first beat (each its own BPM in GRID, else TEMPO's)
    local tb = tonumber((rb_attrs(t.body:match("<TEMPO%s([^>]-)/?>") or "")).BPM)
    local mk = tonumber((rb_attrs(t.body:match("<MUSICAL_KEY%s([^>]-)/?>") or "")).VALUE)
    -- the key as written (INFO KEY: "Am", "8A", Open Key "1m") first; else MUSICAL_KEY read as Mixxx reads it (1-12 major
    -- C..B, 13-24 minor = the JSFX's numbers; not checked on a file from Traktor)
    r.key = M.rb_key_code((rb_attrs(t.body:match("<INFO%s([^>]-)/?>") or "")).KEY)
    if r.key == 0 and mk and mk >= 1 and mk <= 24 then r.key = math.floor(mk) end
    local j = 1
    while true do
      local a, b, attrs, close = t.body:find("<CUE_V2%s([^>]-)(/?)>", j)
      if not a then break end
      local inner = ""
      if close == "" then
        local e = t.body:find("</CUE_V2>", b, true) or #t.body
        inner = t.body:sub(b + 1, e - 1); j = e + 9
      else
        j = b + 1
      end
      local v = rb_attrs(attrs)
      local ty, st, hc = tonumber(v.TYPE), tonumber(v.START), tonumber(v.HOTCUE)
      if st then
        st = st / 1000
        if ty == 4 then
          local gb = tonumber((rb_attrs(inner:match("<GRID%s([^>]-)/?>") or "")).BPM) or tb
          if gb and gb > 0 then r.tempos[#r.tempos + 1] = { t = st, bpm = gb, beat = 1 } end
        end
        if hc and hc >= 0 and hc <= 7 and ty ~= 1 and ty ~= 2 then r.hot[hc + 1] = st
        elseif ty == 0 or ty == 3 or ty == 5 then r.mem[#r.mem + 1] = st end
      end
    end
    if #r.tempos == 0 then r.avg = tb end
  elseif t.kind == "vdj" then
    -- (⚪180) VirtualDJ: Scan Bpm = seconds a beat (a value of 10 or more read as BPM), beatgrid = a bar's first beat
    local sc = rb_attrs(t.body:match("<Scan%s([^>]-)/?>") or "")
    local function vbpm(x) x = tonumber(x); return x and x > 0 and (x < 10 and 60 / x or x) or nil end
    local sb = vbpm(sc.Bpm)
    r.key = M.rb_key_code(sc.Key)
    for a in t.body:gmatch("<Poi%s([^>]-)/?>") do
      local v = rb_attrs(a)
      local ty, st, num = (v.Type or "cue"):lower(), tonumber(v.Pos), tonumber(v.Num)
      if st then
        if ty == "beatgrid" then
          local gb = vbpm(v.Bpm) or sb
          if gb then r.tempos[#r.tempos + 1] = { t = st, bpm = gb, beat = 1 } end
        elseif ty == "cue" then
          if num and num >= 1 and num <= 8 then r.hot[num] = st else r.mem[#r.mem + 1] = st end
        elseif ty == "loop" then
          r.mem[#r.mem + 1] = st
        end
      end
    end
    if #r.tempos == 0 then r.avg = sb end
  else
    r.key = M.rb_key_code(t.Tonality)
    for a in t.body:gmatch("<TEMPO%s([^>]-)/?>") do
      local v = rb_attrs(a)
      local ini, bpm = tonumber(v.Inizio), tonumber(v.Bpm)
      if ini and bpm and bpm > 0 then r.tempos[#r.tempos + 1] = { t = ini, bpm = bpm, beat = tonumber(v.Battito) or 1 } end
    end
    for a in t.body:gmatch("<POSITION_MARK%s([^>]-)/?>") do
      local v = rb_attrs(a)
      local ty, st, num = tonumber(v.Type), tonumber(v.Start), tonumber(v.Num)
      if st and (ty == 0 or ty == 4) then
        if num and num >= 0 and num <= 7 then r.hot[num + 1] = st
        elseif num == -1 then r.mem[#r.mem + 1] = st end
      end
    end
    r.avg = tonumber(t.AverageBpm)
    if t.kind == "reascratch" then
      -- (⚪181) ReaScratch's own: the CUE as it was (not a memory cue), loudness / peak, the beat map as it was
      r.cue, r.lufs, r.peak = tonumber(t.ReaScratchCue), tonumber(t.ReaScratchLufs), tonumber(t.ReaScratchPeak)
      local bm = {}
      for a in t.body:gmatch("<REASCRATCH_BEAT%s([^>]-)/?>") do
        local v = rb_attrs(a)
        local tt, bb = tonumber(v.Time), tonumber(v.Beat)
        if tt and bb then bm[#bm + 1] = { tt, bb } end
      end
      if #bm > 1 then r.rsmap = bm end
    end
  end
  table.sort(r.mem)
  table.sort(r.tempos, function(x, y) return x.t < y.t end)
  local f = r.tempos[1]
  -- (⚪176) more than one TEMPO: a beat map, beat numbers counted on from the first (bars on beats 0, 4, 8 ..), each
  -- next TEMPO at the whole beat nearest to where the tempo before it puts it; a last anchor a beat on at the last tempo
  if #r.tempos > 1 then
    local map = { { f.t, (f.beat - 1) % 4 } }
    for k = 2, #r.tempos do
      local p, q = r.tempos[k - 1], r.tempos[k]
      local b = map[#map][2] + math.max(1, math.floor((q.t - p.t) * p.bpm / 60 + 0.5))
      if q.t > map[#map][1] then map[#map + 1] = { q.t, b } end
    end
    local last = r.tempos[#r.tempos]
    map[#map + 1] = { map[#map][1] + 60 / last.bpm, map[#map][2] + 1 }
    r.map = M.gb_thin(map)
  end
  if r.rsmap then r.map = M.gb_thin(r.rsmap) end
  if f then
    r.bpm = f.bpm
    -- the grid: a bar's first beat (the JSFX counts bars from the grid)
    local beat = 60 / f.bpm
    r.grid = f.t - ((f.beat - 1) % 4) * beat
    while r.grid < 0 do r.grid = r.grid + 4 * beat end
  else
    r.bpm = r.avg
    if r.bpm and r.bpm <= 0 then r.bpm = nil end
  end
  return r
end

-- send a found track's values to slot (1-8) of the deck on track tr: shared memory [310] deck, [311] slot, [313] BPM
-- (0 = keep), [314] grid, [315] key value (0 = keep), [316] CUE (-1 = keep), [320 .. 327] hot cues 1-8 (-1 = empty),
-- [328] memory cue count, [330 ..] the memory cues; then [312] counter += 1 (the JSFX takes them into the slot's store
-- and answers with the counter in [317]: waited for, up to 1 s, so the next request does not overwrite this one)
function M.rb_send(tr, fx, slot, r)
  local p = M.param_index(tr, fx, "Deck (1 = A")
  local deck = p and reaper.TrackFX_GetParam(tr, fx, p) >= 1.5 and 2 or 1
  reaper.gmem_attach(M.GMEM)
  local w = reaper.gmem_write
  w(310, deck); w(311, slot)
  w(313, r.bpm or 0); w(314, r.grid or 0); w(315, r.key or 0)
  w(316, r.cue or r.mem[1] or -1)                            -- rekordbox loads a track at its first memory cue (ours: its CUE)
  for k = 1, 8 do w(319 + k, r.hot[k] or -1) end
  local n = math.min(32, #r.mem)
  w(328, n)
  for k = 1, n do w(329 + k, r.mem[k]) end
  local c = reaper.gmem_read(312) + 1
  w(312, c)
  local t0 = reaper.time_precise()
  while reaper.gmem_read(317) ~= c and reaper.time_precise() - t0 < 1 do end
  local ok = reaper.gmem_read(317) == c
  -- (⚪176) its beat map (more than one TEMPO), or one tempo again (a map the slot had is dropped)
  if r.bpm then ok = M.gb_send(tr, fx, slot, r.map or {}) and ok end
  if r.lufs and r.lufs < 0 then M.set_loudness(tr, fx, slot, r.lufs, r.peak or 0) end   -- (⚪181) ours only
  return ok
end

-- (⚪181) a slot's values (1-8) of the deck on track tr, from the JSFX (RQ = gmem 7100000, see rd_give; waited for up to
-- 1 s): nil when the deck did not answer, else { has, cue, bpm, grid, key, lufs, peak, hot = {[n] = s}, mem = {..},
-- map = { {time, beat} .. } or nil }
function M.slot_values(tr, fx, slot)
  local p = M.param_index(tr, fx, "Deck (1 = A")
  local deck = p and reaper.TrackFX_GetParam(tr, fx, p) >= 1.5 and 2 or 1
  local Q, g = 7100000, reaper.gmem_read
  reaper.gmem_attach(M.GMEM)
  reaper.gmem_write(Q, deck); reaper.gmem_write(Q + 1, slot)
  local c = g(Q + 2) + 1
  reaper.gmem_write(Q + 2, c)
  local t0 = reaper.time_precise()
  while g(Q + 4) ~= c and reaper.time_precise() - t0 < 1 do end
  if g(Q + 4) ~= c then return nil end
  local v = { has = g(Q + 8) == 1, cue = g(Q + 9), bpm = g(Q + 10), grid = g(Q + 11), key = math.floor(g(Q + 12) + 0.5),
              lufs = g(Q + 13), peak = g(Q + 14), hot = {}, mem = {} }
  for k = 1, 8 do local h = g(Q + 15 + k) if h >= 0 then v.hot[k] = h end end
  for k = 1, math.floor(g(Q + 24) + 0.5) do v.mem[k] = g(Q + 31 + k) end
  local n = math.floor(g(Q + 64) + 0.5)
  if n >= 2 then
    v.map = {}
    for k = 1, n do v.map[k] = { g(Q + 70 + 2 * k), g(Q + 71 + 2 * k) } end
  end
  return v
end

-- (⚪181) the file a slot's sample came from: LOAD's record, else the video at the slot's place on the video track; a
-- converted video ("x_960_mjpeg.avi") gives way to a file beside it with the same name before the conversion
-- ("x.mp4") when there is one. Returns the list (best first) and the WAV's path last
M.SRC_EXTS = { "mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "mpg", "flv", "mp3", "m4a", "aac", "flac", "wav", "aiff", "ogg" }
function M.slot_paths(tr, deck, slot, wav)
  local paths = {}
  local _, src = reaper.GetSetMediaTrackInfo_String(tr, M.src_key(M.stem(wav)), "", false)   -- LOAD's record (⚪173)
  if src ~= "" then paths[#paths + 1] = src end
  local vtr = M.track_by_name(deck == 2 and M.TRACK_VIDEO_B or M.TRACK_VIDEO)
  local it = vtr and M.slot_item(vtr, slot)
  local tk = it and reaper.GetActiveTake(it)
  local srcv = tk and reaper.GetMediaItemTake_Source(tk)
  if srcv then
    local v = reaper.GetMediaSourceFileName(srcv, "")
    local dir, base = v:match("^(.*[\\/])(.-)%.[^.\\/]+$")
    local orig = base and base:match("^(.-)_%d*_?mjpeg$")
    if orig then
      for _, e in ipairs(M.SRC_EXTS) do
        local f = dir .. orig .. "." .. e
        if reaper.file_exists(f) then paths[#paths + 1] = f break end
      end
    end
    if v ~= "" then paths[#paths + 1] = v end
  end
  paths[#paths + 1] = M.SAMPLE_DIR .. M.SEP .. wav
  return paths
end

local function rb_esc(x)
  return (tostring(x):gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
-- a path as rekordbox writes Location: file://localhost/C:/a%20b.mp4 (every byte but A-Z a-z 0-9 - . _ ~ / : percent-encoded)
function M.rb_location(path)
  path = path:gsub("\\", "/")
  if not path:match("^/") then path = "/" .. path end
  return "file://localhost" .. path:gsub("[^%w%-%._~/:]", function(c) return string.format("%%%02X", c:byte()) end)
end
local function num(x, d) return string.format("%." .. (d or 3) .. "f", x) end

-- (⚪181) write tracks to an XML in rekordbox's form (kind "rekordbox": for rekordbox's "rekordbox xml" import) or
-- ReaScratch's own (kind "reascratch": the same form + the CUE as it is, loudness / peak and the beat map as it is;
-- read back by rb_find). tracks = { { name, path, cue, bpm, grid, key, lufs, peak, hot, mem, map }, .. }. For rekordbox
-- the CUE is added as a memory cue when it is not one (rekordbox loads a track at its first memory cue)
function M.rb_write(file, tracks, kind)
  local o = { '<?xml version="1.0" encoding="UTF-8"?>', "", '<DJ_PLAYLISTS Version="1.0.0">',
    string.format('  <PRODUCT Name="%s" Version="%s" Company="%s"/>', kind == "reascratch" and "ReaScratch" or "rekordbox",
      kind == "reascratch" and "1" or "6.8.5", kind == "reascratch" and "ReaScratch" or "AlphaTheta"),
    string.format('  <COLLECTION Entries="%d">', #tracks) }
  for i, t in ipairs(tracks) do
    local kn = (t.key or 0) > 24 and t.key - 24 or (t.key or 0)
    local ex = ""
    if kind == "reascratch" then
      ex = string.format(' ReaScratchCue="%s"%s', num(t.cue or 0),
        (t.lufs or 0) < 0 and string.format(' ReaScratchLufs="%s" ReaScratchPeak="%s"', num(t.lufs, 2), num(t.peak or 0, 2)) or "")
    end
    o[#o + 1] = string.format('    <TRACK TrackID="%d" Name="%s" Artist="" Kind="" AverageBpm="%s" Tonality="%s" Location="%s"%s>',
      i, rb_esc(t.name), num(t.bpm or 0, 2), M.key_name(kn), rb_esc(M.rb_location(t.path)), ex)
    -- the tempo: the beat map's stretches (each anchor to the next; its beat in the bar), else the grid (a bar's first beat)
    if t.map and #t.map >= 2 then
      for k = 1, #t.map - 1 do
        local a, b = t.map[k], t.map[k + 1]
        o[#o + 1] = string.format('      <TEMPO Inizio="%s" Bpm="%s" Metro="4/4" Battito="%d"/>', num(a[1]),
          num(60 * (b[2] - a[2]) / (b[1] - a[1]), 2), math.floor(a[2] + 0.5) % 4 + 1)
      end
    elseif (t.bpm or 0) > 0 then
      o[#o + 1] = string.format('      <TEMPO Inizio="%s" Bpm="%s" Metro="4/4" Battito="1"/>', num(t.grid or 0), num(t.bpm, 2))
    end
    if kind == "reascratch" and t.map then
      for _, a in ipairs(t.map) do o[#o + 1] = string.format('      <REASCRATCH_BEAT Time="%s" Beat="%s"/>', num(a[1], 6), num(a[2], 3)) end
    end
    local mem = {}
    for _, m in ipairs(t.mem or {}) do mem[#mem + 1] = m end
    if kind ~= "reascratch" and t.cue and t.cue >= 0 then
      local has = false
      for _, m in ipairs(mem) do if math.abs(m - t.cue) < 0.001 then has = true end end
      if not has then mem[#mem + 1] = t.cue end
    end
    table.sort(mem)
    for _, m in ipairs(mem) do o[#o + 1] = string.format('      <POSITION_MARK Name="" Type="0" Start="%s" Num="-1"/>', num(m)) end
    for k = 1, 8 do
      if t.hot and t.hot[k] then o[#o + 1] = string.format('      <POSITION_MARK Name="" Type="0" Start="%s" Num="%d"/>', num(t.hot[k]), k - 1) end
    end
    o[#o + 1] = "    </TRACK>"
  end
  o[#o + 1] = "  </COLLECTION>"
  o[#o + 1] = string.format('  <PLAYLISTS><NODE Type="0" Name="ROOT" Count="1"><NODE Name="ReaScratch" Type="1" KeyType="0" Entries="%d">', #tracks)
  for i = 1, #tracks do o[#o + 1] = string.format('    <TRACK Key="%d"/>', i) end
  o[#o + 1] = "  </NODE></NODE></PLAYLISTS>"
  o[#o + 1] = "</DJ_PLAYLISTS>"
  local fh = io.open(file, "wb")
  if not fh then return false end
  fh:write(table.concat(o, "\n") .. "\n"); fh:close()
  return true
end

-- (⚪176) a beat map ({ {time s, beat}, ... }, both rising) of at most GB_MAX anchors: every m-th kept, the last too
M.GB_MAX = 2040
function M.gb_thin(map)
  if #map <= M.GB_MAX then return map end
  local m, out = math.ceil(#map / (M.GB_MAX - 1)), {}
  for i = 1, #map, m do out[#out + 1] = map[i] end
  if out[#out] ~= map[#map] then out[#out + 1] = map[#map] end
  return out
end

-- send a beat map to slot (1-8) of the deck on track tr (the JSFX's GBQ = gmem 7000000: [0] deck, [1] slot, [3] count,
-- [8 ..] the pairs, then [2] counter += 1; it answers with the counter in [4], waited for up to 1 s). An empty map (or
-- one anchor) = one tempo. Send it after the slot's file and BPM are set (a new file forgets the map)
function M.gb_send(tr, fx, slot, map)
  local p = M.param_index(tr, fx, "Deck (1 = A")
  local deck = p and reaper.TrackFX_GetParam(tr, fx, p) >= 1.5 and 2 or 1
  local G = 7000000
  reaper.gmem_attach(M.GMEM)
  map = M.gb_thin(map or {})
  reaper.gmem_write(G, deck); reaper.gmem_write(G + 1, slot); reaper.gmem_write(G + 3, #map)
  for i, a in ipairs(map) do reaper.gmem_write(G + 6 + 2 * i, a[1]); reaper.gmem_write(G + 7 + 2 * i, a[2]) end
  local c = reaper.gmem_read(G + 2) + 1
  reaper.gmem_write(G + 2, c)
  local t0 = reaper.time_precise()
  while reaper.gmem_read(G + 4) ~= c and reaper.time_precise() - t0 < 1 do end
  return reaper.gmem_read(G + 4) == c
end

-- a line for the log / a message: "rekordbox: <name> (by file): 3 hot cues, 2 memory cues, 128.00 BPM, key Am"
function M.rb_summary(r)
  local nh = 0
  for k = 1, 8 do if r.hot[k] then nh = nh + 1 end end
  return string.format("%s: %s (by %s): %d hot cues, %d memory cues, %s, key %s%s", M.RB_KINDS[r.kind] or "rekordbox", r.name, r.how, nh, #r.mem,
    r.bpm and string.format("%.2f BPM", r.bpm) or "no BPM", r.key > 0 and M.key_name(r.key) or "-",
    r.map and string.format(" (tempo changes: a beat map of %d marks)", #r.map) or "")
end

-- ---------------------------------------------------------------- a new sample's tempo, beats, key, rekordbox (⚪179)
-- What the import (reascratch_import_video.lua) and LOAD (reascratch_browser.lua) find for a new sample, in one place:
-- they had a copy each, and LOAD gave the beat map no tempo when the estimate was unsure (the import gave it the
-- unsure one, as the beat map was tried in ⚪176). bpm / grid = what the JSFX gets (0 = unknown): rekordbox's when it
-- has a BPM, else the beat map's when the tempo moves, else the estimate when sure (confidence >= BEAT_MIN_CONF).
-- Also: est / est_grid / conf / bdur (estimate_beat), sure, unsure (an estimate, but nothing to use: tell the user),
-- key / lead, rb / why (rb_find), map / minfo / mbpm (estimate_beat_map, not tried over rekordbox's BPM) and the
-- seconds each took (t_beat, t_key, t_map)
M.BEAT_MIN_CONF = 0.35
function M.analyse_sample(wav, paths)
  local a, t0 = {}, reaper.time_precise()
  a.est, a.est_grid, a.conf, a.bdur = M.estimate_beat(wav)
  a.t_beat = reaper.time_precise() - t0
  a.sure = a.est ~= nil and a.conf ~= nil and a.conf >= M.BEAT_MIN_CONF
  a.bpm, a.grid = a.sure and a.est or 0, a.sure and a.est_grid or 0
  t0 = reaper.time_precise()
  a.key, a.lead = M.estimate_key(wav)
  a.t_key = reaper.time_precise() - t0
  a.rb, a.why = M.rb_find(paths)
  if a.rb and a.rb.bpm then
    a.bpm, a.grid = a.rb.bpm, a.rb.grid
  else
    t0 = reaper.time_precise()
    a.map, a.minfo, a.mbpm = M.estimate_beat_map(wav, a.est, a.est_grid)
    a.t_map = reaper.time_precise() - t0
    if a.map then a.bpm, a.grid = math.floor(a.mbpm * 100 + 0.5) / 100, a.map[1][1] end
  end
  a.unsure = a.est ~= nil and a.bpm == 0
  a.lufs, a.peak, a.t_loud = M.estimate_loudness(wav)   -- (⚪185 auto gain)
  return a
end

-- ---------------------------------------------------------------- video file header parsing
-- ((⚪151) this heading stood above ffmpeg_wav)
-- Width / height / fps of a video file from its container header (no decoder needed).
-- MP4/MOV: moov > trak > (tkhd size, mdia > mdhd timescale, hdlr 'vide', minf > stbl > stts first delta).
-- AVI: avih dwMicroSecPerFrame / dwWidth / dwHeight.  Anything else -> nil (the caller asks the user).
local function u32be(s, i) return (string.unpack(">I4", s, i)) end

local function parse_mp4(data)
  local w, h, fps
  local function walk(from, to, state)   -- ((⚪151) without the unused depth)
    local i = from
    while i + 8 <= to do
      local size = u32be(data, i)
      local typ = data:sub(i + 4, i + 7)
      local hdr = 8
      if size == 1 then size = string.unpack(">I8", data, i + 8); hdr = 16 end
      if size == 0 then size = to - i + 1 end
      if size < hdr then return end
      local body, bend = i + hdr, i + size - 1
      if typ == "moov" or typ == "trak" or typ == "mdia" or typ == "minf" or typ == "stbl" then
        local st = (typ == "trak") and {} or state
        walk(body, bend, st)
        if typ == "trak" and st.video and st.w and st.w > 0 then
          w, h = st.w, st.h
          if st.timescale and st.delta and st.delta > 0 then fps = st.timescale / st.delta end
        end
      elseif typ == "tkhd" and state then
        local ver = data:byte(body)
        local off = body + (ver == 1 and 88 or 76)
        state.w = u32be(data, off) / 65536
        state.h = u32be(data, off + 4) / 65536
      elseif typ == "mdhd" and state then
        local ver = data:byte(body)
        state.timescale = u32be(data, body + (ver == 1 and 20 or 12))
      elseif typ == "hdlr" and state then
        if data:sub(body + 8, body + 11) == "vide" then state.video = true end
      elseif typ == "stts" and state then
        if u32be(data, body + 4) > 0 then state.delta = u32be(data, body + 12) end
      end
      i = i + size
    end
  end
  walk(1, #data, nil)
  if w and h then return math.floor(w + 0.5), math.floor(h + 0.5), fps end
end

local function parse_avi(data)
  local p = data:find("avih", 1, true)
  if not p then return end
  local usec = string.unpack("<I4", data, p + 8)
  local w = string.unpack("<I4", data, p + 8 + 32)
  local h = string.unpack("<I4", data, p + 8 + 36)
  return w, h, usec > 0 and 1000000 / usec or nil
end

-- Read only the parts of a container we need, skipping the media data, so big files with the
-- index at the end still work: MP4/MOV -> the 'moov' box; AVI -> the header list + 'idx1'.
-- Returns kind ("mp4"/"avi"), header data, and (AVI only) the idx1 data.
local function read_container(path)
  local fh = io.open(path, "rb")
  if not fh then return end
  local head = fh:read(12) or ""
  if head:sub(1, 4) == "RIFF" and head:sub(9, 12) == "AVI " then
    local hdrl, idx1 = "", nil
    local pos = 12
    while true do
      fh:seek("set", pos)
      local h = fh:read(12)
      if not h or #h < 8 then break end
      local id, size = h:sub(1, 4), string.unpack("<I4", h, 5)
      if id == "LIST" and h:sub(9, 12) == "hdrl" then
        fh:seek("set", pos); hdrl = fh:read(8 + size) or ""
      elseif id == "idx1" then
        fh:seek("set", pos + 8); idx1 = fh:read(size)
      end
      pos = pos + 8 + size + (size % 2)
    end
    fh:close()
    return "avi", hdrl, idx1
  end
  local pos, moov = 0, nil
  while true do
    fh:seek("set", pos)
    local h = fh:read(16)
    if not h or #h < 8 then break end
    local size, typ, hdr = string.unpack(">I4", h, 1), h:sub(5, 8), 8
    if size == 1 then size = string.unpack(">I8", h, 9); hdr = 16 end
    if size == 0 then size = fh:seek("end") - pos end
    if size < hdr then break end
    if typ == "moov" then fh:seek("set", pos); moov = fh:read(size) break end
    pos = pos + size
  end
  fh:close()
  if moov then return "mp4", moov end
end

function M.video_info(path)
  local kind, data = read_container(path)
  if kind == "avi" then return parse_avi(data) end
  if kind == "mp4" then return parse_mp4(data) end
end

-- Intra-only codecs: every frame is a keyframe by design.
local INTRA_FOURCC = {
  jpeg = "MJPEG", mjpa = "MJPEG", mjpb = "MJPEG", MJPG = "MJPEG", mjpg = "MJPEG",
  apch = "ProRes", apcn = "ProRes", apcs = "ProRes", apco = "ProRes", ap4h = "ProRes", ap4x = "ProRes",
  Hap1 = "HAP", Hap5 = "HAP", HapY = "HAP", HapM = "HAP", HapA = "HAP",
  AVdh = "DNxHD", AVdn = "DNxHD", png = "PNG", ["png "] = "PNG", rle = "QuickTime RLE",
}

-- Is every video frame a keyframe? Returns true / false / nil (could not tell), plus a short reason.
function M.keyframe_info(path)
  local kind, data, idx1 = read_container(path)
  if kind == "mp4" then
    -- find the video trak: hdlr 'vide'; then its stsd format, stsz count and stss (sync table)
    local result
    local function walk(from, to, st)
      local i = from
      while i + 8 <= to do
        local size, typ, hdr = u32be(data, i), data:sub(i + 4, i + 7), 8
        if size == 1 then size = string.unpack(">I8", data, i + 8); hdr = 16 end
        if size == 0 then size = to - i + 1 end
        if size < hdr then return end
        local body, bend = i + hdr, i + size - 1
        if typ == "trak" then
          local t = {}
          walk(body, bend, t)
          if t.video and not result then result = t end
        elseif typ == "moov" or typ == "mdia" or typ == "minf" or typ == "stbl" then
          walk(body, bend, st)
        elseif st and typ == "hdlr" then
          if data:sub(body + 8, body + 11) == "vide" then st.video = true end
        elseif st and typ == "stsd" then
          st.fourcc = data:sub(body + 12, body + 15)
        elseif st and typ == "stsz" then
          st.samples = u32be(data, body + 8)
        elseif st and typ == "stss" then
          st.sync = u32be(data, body + 4)
        end
        i = i + size
      end
    end
    walk(1, #data, nil)
    if not result then return nil, M.T("動画トラックが見つからない", "no video track found") end
    local codec = INTRA_FOURCC[result.fourcc or ""]
    if codec then return true, codec .. M.T("（全コマ独立の形式）", " (every frame stands alone)") end
    if not result.sync then return true, (result.fourcc or "?") .. M.T("、キーフレーム表なし＝全コマがキーフレーム", ", no keyframe table = every frame is a keyframe") end
    if result.samples and result.samples > 0 then
      local all = result.sync >= result.samples
      return all, string.format(M.T("%s、キーフレーム %d / %d コマ", "%s, keyframes %d / %d frames"), result.fourcc or "?", result.sync, result.samples)
    end
    return nil, M.T("コマ数が読めない", "cannot read the frame count")
  elseif kind == "avi" then
    local p = data:find("strf", 1, true)
    local comp = p and data:sub(p + 8 + 16, p + 8 + 19) or ""
    local codec = INTRA_FOURCC[comp]
    if codec then return true, codec .. M.T("（全コマ独立の形式）", " (every frame stands alone)") end
    if not idx1 then return nil, comp .. M.T("、索引なし", ", no index") end
    local total, keys = 0, 0
    for i = 1, #idx1 - 15, 16 do
      local id = idx1:sub(i + 2, i + 3)
      if id == "dc" or id == "db" then
        total = total + 1
        if (string.unpack("<I4", idx1, i + 4) & 0x10) ~= 0 then keys = keys + 1 end
      end
    end
    if total == 0 then return nil, comp .. M.T("、映像の索引なし", ", no video index") end
    return keys >= total, string.format(M.T("%s、キーフレーム %d / %d コマ", "%s, keyframes %d / %d frames"), comp, keys, total)
  end
  return nil, M.T("mp4 / mov / avi 以外の入れ物", "container is not mp4 / mov / avi")
end


-- ⚪38 envelope scratch / fader. The JSFX's "Envelope scratch" (beats from where it grabbed, the bottom -0.25 = hand away) and
-- "Envelope fader" (1 = open) envelopes on the engine track, laid where the deck's sample sits on the timeline (slot k at
-- (k - 1) x SLOT_SPAN, like the video). REAPER's transport never plays them: ev_export samples them with
-- Envelope_Evaluate (automation items, pools, loops and shapes as REAPER draws them) every EV_DT s over the stretches
-- that hold something (each automation item; the plain envelope's points when one leaves the resting value) and writes
-- them to gmem, where the JSFX reads them at the deck's own time. Lane layout: see the JSFX (EV_OFF).
M.EV_SCRATCH, M.EV_FADER = "Envelope scratch", "Envelope fader"
M.EV_OFF, M.EV_DT, M.EV_SPMAX = -0.25, 0.002, 4000   -- EV_OFF: the scratch lane's bottom (hand away), as in the JSFX
M.EV_VALS = 8 + 3 * M.EV_SPMAX                       -- first value's index in a lane
M.EV_LANE = 1000000                                  -- lane size (fader lane = scratch lane + this)
function M.ev_base(deck) return deck == 2 and 2100000 or 100000 end
-- (⚪119) the other recorded lanes (the JSFX's sliders 251-258): gmem from lv_base, LV_LANE a lane, every LV_DT s.
-- grp: which recorded stretch makes them (vfx, filter, pad, master); f: the record's field; sq: a value that steps
-- (square points); tol: how far the thinned line may leave the played one
M.LV_DT, M.LV_LANE = 0.01, 200000
function M.lv_base(deck) return deck == 2 and 12000000 or 10000000 end
M.LV = {
  { label = "Envelope vfx type", off = 0, rest = 0, grp = "vfx", f = 6, sq = true },
  { label = "Envelope vfx amount", off = 200000, rest = 0, grp = "vfx", f = 7, tol = 0.01 },
  { label = "Envelope filter cutoff", off = 400000, rest = 0, grp = "filter", f = 8, tol = 0.005 },
  { label = "Envelope filter resonance", off = 600000, rest = 0.4, grp = "filter", f = 9, tol = 0.01 },
  { label = "Envelope filter morph", off = 800000, rest = 0, grp = "filter", f = 10, tol = 0.01 },
  { label = "Envelope pad FX", off = 1000000, rest = 0, grp = "pad", f = 11, sq = true },
  { label = "Envelope master type", off = 1200000, rest = 0, grp = "master", f = 12, sq = true, deck_a = true },
  { label = "Envelope master amount", off = 1400000, rest = 0, grp = "master", f = 13, tol = 0.01, deck_a = true },
}
-- a record belongs to a group's stretch while this holds
M.LV_ON = {
  vfx = function(r) return r[7] > 0.001 end,
  filter = function(r) return math.abs(r[8]) > 0.02 end,
  pad = function(r) return r[11] >= 0.5 end,
  master = function(r) return r[13] > 0.001 end,
}

function M.ev_env(tr, fx, label, create)
  local p = M.param_index_cached(tr, fx, label)   -- ((⚪151) ev_export asks for 11 lanes per deck every 0.5 s)
  return p and reaper.GetFXEnvelope(tr, fx, p, create or false), p
end

local AI_KEYS = { "D_POSITION", "D_LENGTH", "D_PLAYRATE", "D_STARTOFFS", "D_BASELINE", "D_AMPLITUDE", "D_LOOPSRC", "D_POOL_ID" }
local function ev_sig(env)   -- a string that changes whenever the lane would sound different
  if not env then return "none" end
  local t = {}
  local function pts(ai)
    local c = reaper.CountEnvelopePointsEx(env, ai)
    t[#t + 1] = c
    for k = 0, c - 1 do
      local _, tm, v, sh, te = reaper.GetEnvelopePointEx(env, ai, k)
      t[#t + 1] = string.format("%.6f:%.6f:%d:%.3f", tm, v, sh, te)
    end
  end
  pts(-1)
  for i = 0, reaper.CountAutomationItems(env) - 1 do
    for _, key in ipairs(AI_KEYS) do t[#t + 1] = reaper.GetSetAutomationItemInfo(env, i, key, 0, false) end
    pts(i)
  end
  return table.concat(t, ",")
end

-- the stretches (sorted, merged) where the lane may differ from `rest`
local function ev_spans(env, rest)
  local sp = {}
  for i = 0, reaper.CountAutomationItems(env) - 1 do
    local a = reaper.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
    sp[#sp + 1] = { a, a + reaper.GetSetAutomationItemInfo(env, i, "D_LENGTH", 0, false) }
  end
  local c = reaper.CountEnvelopePointsEx(env, -1)
  local first, last, lastv, any
  for k = 0, c - 1 do
    local _, tm, v = reaper.GetEnvelopePointEx(env, -1, k)
    first = first or tm; last, lastv = tm, v
    if math.abs(v - rest) > 0.001 then any = true end
  end
  if any then sp[#sp + 1] = { first, last + (math.abs(lastv - rest) > 0.001 and 60 or 0) } end
  table.sort(sp, function(x, y) return x[1] < y[1] end)
  local out = {}
  for _, s in ipairs(sp) do
    if s[2] > s[1] then
      local o = out[#out]
      if o and s[1] <= o[2] + M.EV_DT then o[2] = math.max(o[2], s[2]) else out[#out + 1] = { s[1], s[2] } end
    end
  end
  return out
end

-- write one lane to gmem (base); returns the number of values written
local function ev_write(env, base, rest, dt, lane)
  dt, lane = dt or M.EV_DT, lane or M.EV_LANE         -- ((⚪119) the other lanes: their own step and size)
  reaper.gmem_write(base + 1, 0)                       -- nothing to read while it is written
  if not env then reaper.gmem_write(base, reaper.gmem_read(base) + 1) return 0, 0 end
  local idx, n_sp = M.EV_VALS, 0
  local spans, left = ev_spans(env, rest), 0
  for si, s in ipairs(spans) do
    -- ((⚪115) what does not fit (more than M.EV_SPMAX stretches, or about 33 min in all) was left out without a word:
    -- counted, and ev_export says so)
    if n_sp >= M.EV_SPMAX then left = #spans - si + 1 break end
    local n = math.floor((s[2] - s[1]) / dt) + 2
    if idx + n > lane then left = #spans - si + 1 break end
    for i = 0, n - 1 do
      local t = math.min(s[1] + i * dt, s[2] - 0.000001)
      local _, v = reaper.Envelope_Evaluate(env, t, 0, 0)
      reaper.gmem_write(base + idx + i, v)
    end
    reaper.gmem_write(base + 8 + 3 * n_sp, s[1]); reaper.gmem_write(base + 9 + 3 * n_sp, n); reaper.gmem_write(base + 10 + 3 * n_sp, idx)
    idx, n_sp = idx + n, n_sp + 1
  end
  reaper.gmem_write(base + 2, dt)
  reaper.gmem_write(base + 1, n_sp)
  reaper.gmem_write(base, reaper.gmem_read(base) + 1)
  return idx - M.EV_VALS, left
end

-- check the deck's two lanes and rewrite the ones that changed; cache = a table kept by the caller (per deck).
-- tr = nil clears both lanes (no deck)
-- ((⚪151) the signatures read every point of every lane (heavy with long recorded lanes): only when the project changed
-- (GetProjectStateChangeCount: an edit, an undo point), another deck / FX index came, or EV_FULL s have passed (an edit
-- that does not count as a change is then written at most that late)
M.EV_FULL = 5
function M.ev_export(tr, fx, deck, cache)
  local scc, now = reaper.GetProjectStateChangeCount(0), reaper.time_precise()
  if cache.scc == scc and cache.tr == tr and cache.fx == fx and now < (cache.full_t or 0)
     and reaper.gmem_read(M.pn_base(deck)) > 0 then return end
  cache.scc, cache.tr, cache.fx, cache.full_t = scc, tr, fx, now + M.EV_FULL
  local base = M.ev_base(deck)
  local lanes = { { M.EV_SCRATCH, base, M.EV_OFF }, { M.EV_FADER, base + M.EV_LANE, 1 } }
  for _, l in ipairs(M.LV) do lanes[#lanes + 1] = { l.label, M.lv_base(deck) + l.off, l.rest, M.LV_DT, M.LV_LANE } end   -- (⚪119)
  for k, ln in ipairs(lanes) do
    local env = tr and (M.ev_env(tr, fx, ln[1]))
    local sig = ev_sig(env)
    if cache[k] ~= sig then
      cache[k] = sig
      local _, left = ev_write(env, ln[2], ln[3], ln[4], ln[5])   -- ((⚪151) the count was kept in cache.n, never read)
      if left > 0 then
        M.log(string.format(M.T("デッキ%s の「%s」: 長すぎて %d 区間を読めませんでした（読めるのは合計約33分・%d 区間まで）",
          "deck %s, \"%s\": too long, %d stretch(es) left out (up to about 33 min / %d stretches in all)"),
          deck == 2 and "B" or "A", ln[1], left, M.EV_SPMAX))
      end
    end
  end
  -- (⚪115) the names of the scratch lane's automation items, for the JSFX's bottom bar while the lane holds
  local env = tr and (M.ev_env(tr, fx, M.EV_SCRATCH))
  local items = {}
  if env then
    for i = 0, reaper.CountAutomationItems(env) - 1 do
      local a = reaper.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
      local _, nm = reaper.GetSetAutomationItemInfo_String(env, i, "P_POOL_NAME", "", false)
      items[#items + 1] = { a, a + reaper.GetSetAutomationItemInfo(env, i, "D_LENGTH", 0, false), nm or "" }
    end
  end
  local sig = {}
  for _, it in ipairs(items) do sig[#sig + 1] = string.format("%.6f:%.6f:%s", it[1], it[2], it[3]) end
  sig = table.concat(sig, "\n")
  if cache.names ~= sig or reaper.gmem_read(M.pn_base(deck)) <= 0 then
    cache.names = sig
    M.pn_write(deck, items)
  end
end

-- (⚪115) the scratch lane's item names in gmem: deck A at PN_G, B at PN_G + PN_DECK. [0] counts the writes, [1] the
-- items (up to PN_MAX); item i at + 8 + PN_W * i: [0] start, [1] end (s on the timeline), [2..33] the name's bytes (0 at
-- the end). Layout in the JSFX: PNM
M.PN_G, M.PN_DECK, M.PN_W, M.PN_MAX = 6600000, 20000, 40, 400
function M.pn_base(deck) return deck == 2 and M.PN_G + M.PN_DECK or M.PN_G end
-- (⚪151) at most n bytes of s, cut before a UTF-8 character that does not fit whole (a Japanese name was cut inside
-- its last character)
function M.utf8_cut(s, n)
  if #s <= n then return s end
  local i = n
  while i > 0 and ((s:byte(i + 1) or 0) & 0xC0) == 0x80 do i = i - 1 end   -- byte i + 1 continues a character
  return s:sub(1, i)
end
function M.pn_write(deck, items)
  local b = M.pn_base(deck)
  reaper.gmem_write(b + 1, 0)                          -- nothing to read while it is written
  local n = math.min(#items, M.PN_MAX)
  for i = 1, n do
    local o, it = b + 8 + M.PN_W * (i - 1), items[i]
    local nm = M.utf8_cut(it[3], 31)   -- ((⚪151) not :sub(1, 31))
    reaper.gmem_write(o, it[1]); reaper.gmem_write(o + 1, it[2])
    for j = 1, #nm do reaper.gmem_write(o + 1 + j, nm:byte(j)) end
    reaper.gmem_write(o + 2 + #nm, 0)
  end
  reaper.gmem_write(b + 1, n)
  reaper.gmem_write(b, reaper.gmem_read(b) + 1)
end

-- (⚪115, user's choices 2026-10-10) the PATTERN pad mode: 8 patterns on the pads (the JSFX plays them; mode 13). Their
-- names: ExtState ReaScratch / pattern_pads (8 lines; reascratch_pattern.lua's menu sets them), else the defaults.
-- pad_export writes them to gmem for the JSFX (layout there: PTG): [0] counts the writes, [1] 8, pad k (0-7) at
-- PT_G + 10 + k * 400: [0] beats, [1] / [2] position / fader points, [4..35] the name's bytes (0 at the end), [40..] the
-- position points, [280..] the fader points (beat, value, smooth). ((⚪179) the string it returned was never read: gone)
M.PT_G, M.PT_POS, M.PT_FAD = 6500000, 80, 40
M.PAD_PATTERNS = { "Baby", "Baby x2", "Chirp", "Tear", "Flare (1 click)", "Crab", "Transformer", "Stutter 16th" }
function M.pad_patterns()
  local s, out = reaper.GetExtState("ReaScratch", "pattern_pads"), {}
  for line in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  for k = 1, 8 do if not out[k] or out[k] == "" then out[k] = M.PAD_PATTERNS[k] end end
  return out
end
function M.pad_set(k, name)
  local t = M.pad_patterns(); t[k] = name
  reaper.SetExtState("ReaScratch", "pattern_pads", table.concat(t, "\n", 1, 8), true)
end
function M.pad_export(pats)
  local names, by = M.pad_patterns(), {}
  for _, p in ipairs(pats) do if not by[p.name] then by[p.name] = p end end
  for k = 1, 8 do
    local b, p = M.PT_G + 10 + (k - 1) * 400, by[names[k]]
    reaper.gmem_write(b + 1, 0)
    if p then
      local np, nf = math.min(#p.pos, M.PT_POS), p.fader and math.min(#p.fader, M.PT_FAD) or 0
      for i = 1, np do for j = 1, 3 do reaper.gmem_write(b + 40 + 3 * (i - 1) + j - 1, p.pos[i][j] or 0) end end
      for i = 1, nf do for j = 1, 3 do reaper.gmem_write(b + 280 + 3 * (i - 1) + j - 1, p.fader[i][j] or 0) end end
      local nm = M.utf8_cut(p.name, 31)   -- ((⚪151) not :sub(1, 31))
      for i = 1, #nm do reaper.gmem_write(b + 3 + i, nm:byte(i)) end
      reaper.gmem_write(b + 4 + #nm, 0)
      reaper.gmem_write(b, p.beats); reaper.gmem_write(b + 2, nf); reaper.gmem_write(b + 1, np)
    end
  end
  reaper.gmem_write(M.PT_G + 1, 8); reaper.gmem_write(M.PT_G, reaper.gmem_read(M.PT_G) + 1)
end

-- patterns: reascratch_patterns.lua (the kit's), then every Data/ReaScratch_patterns_*.lua (yours: _user.lua is what
-- reascratch_pattern_save.lua writes; others, e.g. converted from another plugin, are read the same way). Each pattern
-- from _user.lua gets .user = true
M.USER_PATTERNS = M.RES .. M.SEP .. "Data" .. M.SEP .. "ReaScratch_patterns_user.lua"
function M.load_patterns(here)
  local files = { here .. "reascratch_patterns.lua" }
  local dir, i = M.RES .. M.SEP .. "Data", 0
  local more = {}
  reaper.EnumerateFiles(dir, -1)                       -- forget the cached listing (a file saved since)
  while true do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    if f:match("^ReaScratch_patterns_.*%.lua$") then more[#more + 1] = f end
    i = i + 1
  end
  table.sort(more)
  for _, f in ipairs(more) do files[#files + 1] = dir .. M.SEP .. f end
  local out = {}
  for _, f in ipairs(files) do
    local ok, t = pcall(dofile, f)
    if ok and type(t) == "table" then
      for _, p in ipairs(t) do
        if type(p) == "table" and p.name and p.pos and (p.beats or 0) > 0 then p.user = f == M.USER_PATTERNS; out[#out + 1] = p end
      end
    end
  end
  return out
end

-- one beat of the deck's sample (s), its grid offset (s), slot, head (s); beat = nil without a BPM
function M.deck_time(tr, fx)
  local function g(label) local p = M.param_index(tr, fx, label); return p and reaper.TrackFX_GetParam(tr, fx, p) end
  local bpm = g("BPM") or 0
  return bpm > 0 and 60 / bpm or nil, g("Beat grid") or 0, math.floor((g("Sample slot") or 1) + 0.5), g("Head position") or 0
end

local function lua_val(v, ind)
  if type(v) == "table" then
    local parts, isarr = {}, #v > 0
    for i, x in ipairs(v) do parts[#parts + 1] = lua_val(x, ind) end
    if not isarr then
      local keys = {}
      for k in pairs(v) do if type(k) == "string" then keys[#keys + 1] = k end end
      table.sort(keys)
      for _, k in ipairs(keys) do parts[#parts + 1] = k .. " = " .. lua_val(v[k], ind) end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
  elseif type(v) == "string" then return string.format("%q", v)
  -- ((⚪151) 10 digits, not 5: a point at beat 12.34567 was saved as 12.346)
  elseif type(v) == "number" then return (v == math.floor(v) and math.abs(v) < 1e9) and string.format("%d", v) or string.format("%.10g", v)
  else return tostring(v) end
end
-- the user's patterns file, written whole (list = patterns without .user)
function M.save_user_patterns(list)
  local h = io.open(M.USER_PATTERNS, "w")
  if not h then return false end
  h:write("-- ReaScratch: your own scratch patterns (reascratch_pattern_save.lua; the same form as Scripts/ReaScratch/reascratch_patterns.lua)\nreturn {\n")
  for _, p in ipairs(list) do
    local q = { name = p.name, cat = p.cat, beats = p.beats, pos = p.pos, fader = p.fader }
    h:write("  " .. lua_val(q) .. ",\n")
  end
  h:write("}\n")
  h:close()
  return true
end

-- ⚪39 swing for patterns: s = the first note's share of each pair (0.5 = straight, 0.58 = the measured Rip), pair = the
-- pair's length in beats. The deck's own Swing (slider 109, 16ths) when it swings the sample; else REAPER's grid swing
-- (Snap/Grid settings; measured 2026-10-05: amount a moves the off note by a x half a grid step, so s = 0.5 + a / 4)
function M.pattern_swing(tr, fx)
  local p = M.param_index(tr, fx, "Swing (16th")
  local sw = p and reaper.TrackFX_GetParam(tr, fx, p) or 50
  if math.abs(sw - 50) > 0.01 then return sw / 100, 0.5, "deck" end
  local _, div, mode, amt = reaper.GetSetProjectGrid(0, false)
  if mode == 1 and amt ~= 0 and div > 0 and div <= 0.125 then return 0.5 + amt / 4, div * 8, "grid" end
  return 0.5, 0.5, "none"
end
-- b = beats from the deck's beat grid: straight -> swung, and back
function M.swing_warp(b, s, pair)
  local e = math.floor(b / pair) * pair
  local u = (b - e) / pair
  return e + pair * (u < 0.5 and u * 2 * s or s + (u - 0.5) * 2 * (1 - s))
end
function M.swing_unwarp(b, s, pair)
  local e = math.floor(b / pair) * pair
  local u = (b - e) / pair
  return e + pair * (u < s and u / (2 * s) or 0.5 + (u - s) / (2 * (1 - s)))
end

-- a deck's lane (envelope of the JSFX slider `label`), made when missing; a new lane rests at `rest` (hand away / open),
-- whatever the slider showed
function M.ev_lane(tr, fx, label, rest)
  local had = M.ev_env(tr, fx, label, false)
  local env = M.ev_env(tr, fx, label, true)
  if env and not had then
    reaper.DeleteEnvelopePointRangeEx(env, -1, -1e9, 1e9)
    reaper.InsertEnvelopePointEx(env, -1, 0, rest, 0, 0, false, false)
  end
  return env
end

-- one automation item on a lane from `at` for `len` s with the points { time, value, shape } (shape 5 = bezier, else
-- straight lines); name = its pool name. Returns its index
function M.ev_item(env, at, len, pts, name)
  local ai = reaper.InsertAutomationItem(env, -1, at, len)
  reaper.DeleteEnvelopePointRangeEx(env, ai, at - 1, at + len + 1)
  for _, q in ipairs(pts) do reaper.InsertEnvelopePointEx(env, ai, q[1], q[2], q[3] or 0, 0, false, true) end
  reaper.Envelope_SortPointsEx(env, ai)
  if name then reaper.GetSetAutomationItemInfo_String(env, ai, "P_POOL_NAME", name, true) end
  return ai
end

-- (⚪115) clear the stretch [a, b] of a lane's automation items, as a punch in: REAPER plays overlapping items all
-- together (their values add up), so a recorded touch laid over a pattern sounded as the touch plus the pattern, while
-- the hand had ruled alone when it was played. Items inside are deleted, the ones across an end shortened, one across
-- both split in two (the right part: another instance of its pool, moved on in its source). Other items' selection is
-- kept (the delete action acts on the selected ones)
function M.ev_punch(env, a, b)
  local AI = function(i, k, v) return reaper.GetSetAutomationItemInfo(env, i, k, v or 0, v ~= nil) end
  local kill = {}
  for i = reaper.CountAutomationItems(env) - 1, 0, -1 do
    local p, l = AI(i, "D_POSITION"), AI(i, "D_LENGTH")
    local e, rate, so = p + l, AI(i, "D_PLAYRATE"), AI(i, "D_STARTOFFS")
    if p < b - 0.0005 and e > a + 0.0005 then
      if p >= a - 0.0005 and e <= b + 0.0005 then kill[#kill + 1] = i
      elseif p < a and e > b then
        local j = reaper.InsertAutomationItem(env, AI(i, "D_POOL_ID"), b, e - b)
        for _, k in ipairs({ "D_PLAYRATE", "D_BASELINE", "D_AMPLITUDE", "D_LOOPSRC" }) do AI(j, k, AI(i, k)) end
        AI(j, "D_STARTOFFS", so + (b - p) * rate)
        AI(i, "D_LENGTH", a - p)
      elseif p < a then AI(i, "D_LENGTH", a - p)
      else AI(i, "D_POSITION", b); AI(i, "D_LENGTH", e - b); AI(i, "D_STARTOFFS", so + (b - p) * rate) end
    end
  end
  if #kill == 0 then return end
  -- the delete action works on the selected items of every lane: keep the others' selection, select only these
  local saved = {}
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    for k = 0, reaper.CountTrackEnvelopes(tr) - 1 do
      local e2 = reaper.GetTrackEnvelope(tr, k)
      for i = 0, reaper.CountAutomationItems(e2) - 1 do
        if reaper.GetSetAutomationItemInfo(e2, i, "D_UISEL", 0, false) ~= 0 then saved[#saved + 1] = { e2, i } end
        reaper.GetSetAutomationItemInfo(e2, i, "D_UISEL", 0, true)
      end
    end
  end
  for _, i in ipairs(kill) do AI(i, "D_UISEL", 1) end
  reaper.Main_OnCommand(42086, 0)                      -- Envelope: Delete automation items
  for _, q in ipairs(saved) do
    if q[1] ~= env then reaper.GetSetAutomationItemInfo(q[1], q[2], "D_UISEL", 1, true) end
  end
end

-- ⚪50 recording the hand into the lanes. While REAPER records, each deck's JSFX adds a record per audio block to a ring
-- in gmem (layout: the JSFX, RC_W). rec_tick (called by the video sync script on every cycle) reads the rings while it
-- records and, when the recording stops, puts what was played on the lanes as automation items, where the deck's sample
-- was (as the lanes are read back):
--   each touch of the hand while the deck played = one item on "Envelope scratch" (named "Rec A-1" ...), and one on
--     "Envelope fader" at the same place when the crossfader moved during it (reascratch_pattern_save.lua keeps the pair)
--   the crossfader moved while no hand held the record = items on "Envelope fader" only
-- New items go on top of what the lanes had. Off with the ExtState ReaScratch / rec_lanes = "off"
-- (reascratch_record_lanes.lua toggles it).
M.RC_W = 13                                -- ((⚪119) + video FX, filter, pad FX, master FX: see the JSFX)
M.RC_N = math.floor((30000 - 8) / M.RC_W)
function M.rc_base(deck) return deck == 2 and 70000 or 40000 end
M.RC_TOL_POS, M.RC_TOL_XF = 0.002, 0.005   -- how far the thinned line may leave the played one (beats / gain)
M.RC_GAP = 0.05                            -- the deck's time moving back, or on by more than this (s) in a block = a jump
M.RC_LO, M.RC_HI = -0.2, 2                 -- the scratch values kept within the lane (its bottom -0.25 = hand away)
M.RC_XF_BEATS = 2                          -- (⚪115) a closed fader with no hand longer than this (beats) is not recorded
M.RC_OFF = 0.03                            -- (⚪115) the let go after a recorded touch (s at the bottom; longer than an audio block, else the JSFX
                                           -- may not read the lane inside it: 1024 samples at 44.1 kHz = 23 ms)
function M.rec_lanes_on() return reaper.GetExtState("ReaScratch", "rec_lanes") ~= "off" end

local rc = { on = false }

-- (⚪151) one reader for the JSFX's record rings (the hand, the take, the mix: three copies before): at b the count
-- written, records of W values from b + 8, N of them. New records go to d.recs; d.read = the count read, d.lost = overrun
local function ring_drain(d, b, W, N)
  local n = reaper.gmem_read(b)
  if n - d.read > N then d.lost = d.lost + (n - d.read - N); d.read = n - N end
  for k = d.read, n - 1 do
    local o = b + 8 + W * (k % N)
    local r = {}
    for j = 0, W - 1 do r[j + 1] = reaper.gmem_read(o + j) end
    d.recs[#d.recs + 1] = r
  end
  d.read = n
end
local function rc_drain(d) ring_drain(d, M.rc_base(d.deck), M.RC_W, M.RC_N) end

-- Ramer-Douglas-Peucker: the fewest of the points { t, v } whose straight lines stay within tol of all of them
local function rc_thin(pts, tol)
  local n = #pts
  if n <= 2 then return pts end
  local keep, stack = { [1] = true, [n] = true }, { { 1, n } }
  while #stack > 0 do
    local s = table.remove(stack)
    local a, b = s[1], s[2]
    local ta, va, tb, vb = pts[a][1], pts[a][2], pts[b][1], pts[b][2]
    local worst, wi = tol, nil
    for i = a + 1, b - 1 do
      local u = tb > ta and (pts[i][1] - ta) / (tb - ta) or 0
      local e = math.abs(pts[i][2] - (va + (vb - va) * u))
      if e > worst then worst, wi = e, i end
    end
    if wi then keep[wi] = true; stack[#stack + 1] = { a, wi }; stack[#stack + 1] = { wi, b } end
  end
  local out = {}
  for i = 1, n do if keep[i] then out[#out + 1] = pts[i] end end
  return out
end

-- the records of one deck -> stretches { hand = true/false, pos = { {t, v} }, xf = { {t, gain} } }
local function rc_stretches(recs)
  local out, cur = {}, nil
  local function close() if cur then out[#out + 1] = cur; cur = nil end end
  for i, r in ipairs(recs) do
    local t, hand, v, xf = r[1], r[2] > 0.5, r[3], r[4]
    local p = recs[i - 1]
    local jump = not p or t < p[1] - 0.000001 or t - p[1] > M.RC_GAP
    if hand then
      if not (cur and cur.hand) or jump then close(); cur = { hand = true, pos = {}, xf = {} } end
      cur.pos[#cur.pos + 1] = { t, v }; cur.xf[#cur.xf + 1] = { t, xf }
    else
      if cur and cur.hand then close() end
      if cur and not jump then
        cur.xf[#cur.xf + 1] = { t, xf }
        if xf >= 0.999 then close() end                  -- back open: this point ends it
      else
        close()
        if xf < 0.999 then
          cur = { hand = false, xf = {} }
          if p and not jump and p[2] < 0.5 then cur.xf[1] = { p[1], p[4] } end   -- the open point before it closed
          cur.xf[#cur.xf + 1] = { t, xf }
        end
      end
    end
  end
  close()
  return out
end

-- put one deck's recording on its lanes; returns the numbers of scratch / fader items and of touches that went beyond
-- the lane's range (clipped)
local function rc_put(d)
  if not (d.tr and reaper.ValidatePtr2(0, d.tr, "MediaTrack*")) then return 0, 0, 0, 0 end
  -- ((⚪151) the JSFX's index now, not the one at the record start: an FX put before it meanwhile moved it, and the lanes
  -- went to the other FX's parameters)
  d.fx = M.engine_fx(d.tr)
  if not d.fx then return 0, 0, 0, 0 end
  local tag = d.deck == 2 and "B" or "A"
  local senv, fenv
  local n_s, n_f, clipped, dropped = 0, 0, 0, 0
  local bp = M.param_index(d.tr, d.fx, "BPM (0")
  local bpm = bp and reaper.TrackFX_GetParam(d.tr, d.fx, bp) or 0
  local beat_s = bpm > 0 and 60 / bpm or 0.5
  -- go on from the highest "Rec A-<n>" already on the lane
  local num = 0
  local e0 = M.ev_env(d.tr, d.fx, M.EV_SCRATCH, false)
  if e0 then
    for i = 0, reaper.CountAutomationItems(e0) - 1 do
      local _, nm = reaper.GetSetAutomationItemInfo_String(e0, i, "P_POOL_NAME", "", false)
      local k = tonumber(nm:match("^Rec " .. tag .. "%-(%d+)$"))
      if k and k > num then num = k end
    end
  end
  for _, st in ipairs(rc_stretches(d.recs)) do
    local xf = st.xf
    local t0, t1 = xf[1][1], xf[#xf][1]
    if st.hand then
      -- the item ends one block after the last record (the hand let go there)
      local dt = #xf > 1 and (xf[#xf][1] - xf[#xf - 1][1]) or 0.003
      t1 = t1 + dt
      -- the head from where the hand went on, moved as a whole so that it fits the lane (only the differences count:
      -- the JSFX takes the value where it grabs as the place it grabbed)
      local lo, hi = math.huge, -math.huge
      for _, q in ipairs(st.pos) do lo = math.min(lo, q[2]); hi = math.max(hi, q[2]) end
      local v0 = lo < M.RC_LO and M.RC_LO - lo or 0
      if hi + v0 > M.RC_HI then v0 = M.RC_HI - hi; clipped = clipped + 1 end
      local pts = {}
      for _, q in ipairs(st.pos) do pts[#pts + 1] = { q[1], math.max(M.RC_LO, math.min(M.RC_HI, q[2] + v0)) } end
      pts[#pts + 1] = { t1, pts[#pts][2] }
      senv = senv or M.ev_lane(d.tr, d.fx, M.EV_SCRATCH, M.EV_OFF)
      if not senv then return n_s, n_f, clipped, dropped end
      num = num + 1
      -- ((⚪115) the hand lets go at the end: a short stretch at the bottom (EV_OFF) after the last point. Over a pattern,
      -- the lane went on into the pattern's values with no let go, and the head jumped by their difference)
      -- (square points: the last value up to t1, then the bottom from just after t1 for M.RC_OFF)
      pts = rc_thin(pts, M.RC_TOL_POS)
      pts[#pts][3] = 1
      pts[#pts + 1] = { t1 + 0.001, M.EV_OFF, 1 }
      pts[#pts + 1] = { t1 + M.RC_OFF, M.EV_OFF, 1 }
      M.ev_punch(senv, t0, t1 + M.RC_OFF + 0.003)
      M.ev_item(senv, t0, t1 - t0 + M.RC_OFF + 0.003, pts, "Rec " .. tag .. "-" .. num)
      n_s = n_s + 1
      local moved = false
      for _, q in ipairs(xf) do if q[2] < 0.999 then moved = true break end end
      if moved then xf[#xf + 1] = { t1, xf[#xf][2] } else xf = nil end
    end
    if xf and not st.hand then
      -- the item ends one block after its last point (REAPER keeps no point on an item's very end)
      t1 = t1 + (#xf > 1 and (xf[#xf][1] - xf[#xf - 1][1]) or 0.003)
      -- ((⚪115) a closed stretch longer than M.RC_XF_BEATS beats with no hand is the deck left out of the mix, not a cut:
      -- kept, it closed the fader over all that place of the sample (no sound there when played again))
      if t1 - t0 > M.RC_XF_BEATS * beat_s then xf = nil; dropped = dropped + 1
      -- (and a cut while the deck's place stood still, e.g. a pattern holding the record: all its points at one place, an
      -- item of 3 ms that says nothing)
      elseif xf[#xf][1] - xf[1][1] < 0.001 then xf = nil end
    end
    if xf and t1 > t0 then
      fenv = fenv or M.ev_lane(d.tr, d.fx, M.EV_FADER, 1)
      if fenv then
        M.ev_item(fenv, t0, t1 - t0, rc_thin(xf, M.RC_TOL_XF), st.hand and ("Rec " .. tag .. "-" .. num) or nil)
        n_f = n_f + 1
      end
    end
  end
  -- (⚪119) the other lanes: a stretch of each group while it holds something (and the deck's time runs on), as items
  -- that cut out what was under them (as the hand's)
  local n_o = 0
  for grp, on in pairs(M.LV_ON) do
    if not (grp == "master" and d.deck == 2) then
      local sts, cur = {}, nil
      for i, r in ipairs(d.recs) do
        local p = d.recs[i - 1]
        local jump = not p or r[1] < p[1] - 0.000001 or r[1] - p[1] > M.RC_GAP
        if on(r) then
          if not cur or jump then cur = {}; sts[#sts + 1] = cur end
          cur[#cur + 1] = r
        else cur = nil end
      end
      for _, st in ipairs(sts) do
        local t0, t1 = st[1][1], st[#st][1] + (#st > 1 and (st[#st][1] - st[#st - 1][1]) or 0.003)
        if t1 - t0 > 0.002 then
          for _, l in ipairs(M.LV) do
            if l.grp == grp then
              local env = M.ev_lane(d.tr, d.fx, l.label, l.rest)
              if env then
                local pts = {}
                if l.sq then
                  for _, r in ipairs(st) do if #pts == 0 or math.abs(r[l.f] - pts[#pts][2]) > 0.0001 then pts[#pts + 1] = { r[1], r[l.f], 1 } end end
                else
                  for _, r in ipairs(st) do pts[#pts + 1] = { r[1], r[l.f] } end
                  pts[#pts + 1] = { t1, st[#st][l.f] }
                  pts = rc_thin(pts, l.tol)
                end
                M.ev_punch(env, t0, t1 + 0.003)
                M.ev_item(env, t0, t1 - t0 + 0.003, pts, "Rec " .. tag)
                n_o = n_o + 1
              end
            end
          end
        end
      end
    end
  end
  d.n_other = n_o
  return n_s, n_f, clipped, dropped
end

-- called on every cycle of the video sync script: recording = REAPER records now; decks = { {tr, fx}, {tr, fx} } (nil
-- when missing). Returns a line to show when it has put a recording on the lanes
function M.rec_tick(recording, decks)
  if recording and not rc.on then
    if not M.rec_lanes_on() then return end
    rc.on, rc.decks = true, {}
    for deck = 1, 2 do
      local e = decks[deck]
      if e and e[1] then
        local b = M.rc_base(deck)
        rc.decks[#rc.decks + 1] = { deck = deck, tr = e[1], fx = e[2], read = reaper.gmem_read(b), recs = {}, lost = 0 }
        reaper.gmem_write(b + 1, 1)
      end
    end
  elseif rc.on then
    -- ((⚪115) a deck that came during the recording (deck B made, the script started again): recorded from then on)
    if recording then
      for deck = 1, 2 do
        local e, have = decks[deck], false
        for _, d in ipairs(rc.decks) do if d.deck == deck then have = true end end
        if e and e[1] and not have then
          local b = M.rc_base(deck)
          rc.decks[#rc.decks + 1] = { deck = deck, tr = e[1], fx = e[2], read = reaper.gmem_read(b), recs = {}, lost = 0 }
          reaper.gmem_write(b + 1, 1)
        end
      end
    end
    for _, d in ipairs(rc.decks) do rc_drain(d) end
    if recording then return end
    rc.on = false
    for _, d in ipairs(rc.decks) do reaper.gmem_write(M.rc_base(d.deck) + 1, 0) end
    _G.REASCRATCH_REC_LAST = rc.decks                   -- (tests read the raw records)
    local msg, any = {}, false
    reaper.Undo_BeginBlock()
    -- ((⚪151) in pcall: an error inside left the undo block open, and the video sync stopped)
    local ok, err = pcall(function()
      for _, d in ipairs(rc.decks) do
        local n_s, n_f, clipped, dropped = rc_put(d)
        any = any or n_s + n_f > 0
        local line = string.format("deck %s: %d scratch / %d fader items", d.deck == 2 and "B" or "A", n_s, n_f)
        if clipped > 0 then line = line .. string.format(", %d touch(es) beyond the lane's range (clipped)", clipped) end
        if d.lost > 0 then line = line .. string.format(", %d blocks lost", d.lost) end
        if dropped > 0 then line = line .. string.format(", %d long closed fader stretch(es) left out (no hand, over %d beats)", dropped, M.RC_XF_BEATS) end
        if (d.n_other or 0) > 0 then line = line .. string.format(", %d video FX / filter / pad FX item(s)", d.n_other); any = true end
        msg[#msg + 1] = line
      end
    end)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock(M.T("ReaScratch: 演奏をエンベロープに記録", "ReaScratch: record the performance into envelopes"), -1)
    if not ok then
      M.log(M.T("演奏をエンベロープに書き込む途中でエラー: ", "error while writing the performance into the lanes: ") .. tostring(err))
      return "recorded into the lanes (stopped by an error): " .. table.concat(msg, "; ")
    end
    if any then return "recorded into the lanes: " .. table.concat(msg, "; ") end
  end
end

-- ⚪178 the performance lanes. Each deck's engine track holds a second JSFX before the engine, reascratch_perf.jsfx
-- ("DJ performance lanes"), whose sliders are lanes on REAPER's timeline (not the deck's time): transport, head, driven,
-- slot, tempo, key (lane i = its slider i + 1; new lanes only at the end, see the file). While REAPER records, the engine
-- adds a record (REAPER's position, lane, value) to a ring in gmem whenever a lane's state changes (layout: the JSFX,
-- PRF_W); pf_tick (called by the video sync script next to rec_tick) reads the rings and, when the recording stops, puts
-- one automation item per lane and deck ("Perf A-1" ...) in the performance zone: from PF_ZONE s (10 hours) on, each
-- recording after the last one (PF_GAP s apart), with a region "Perf <n>" over it (needed: automation items do not make
-- the project longer, and REAPER stops playing at the project's end). A recording started inside the zone stays where it
-- was played (what was under it is cut out first, as ev_punch). The hand's lanes (rec_tick) are written as before.
-- Off with the ExtState ReaScratch / perf_lanes = "off".
M.PERF_JSFX = "ReaScratch/reascratch_perf.jsfx"
M.PERF_NAME = "DJ performance lanes"
M.PF_W = 3
M.PF_N = math.floor((500000 - 8) / M.PF_W)
function M.pf_base(deck) return deck == 2 and 14600000 or 14100000 end
M.PF_ZONE, M.PF_GAP = 36000, 2
-- sq = steps (square points); else straight lines, thinned within tol. The head's corners come from the JSFX (it records
-- the block before a jump); the other straight lanes hold their value up to just before the next record
M.PF_LANES = {
  { label = "Perf transport", sq = true },
  { label = "Perf head", tol = 0.0005, head = true },
  { label = "Perf driven", sq = true },
  { label = "Perf slot", sq = true },
  { label = "Perf tempo", tol = 0.001 },
  { label = "Perf key", sq = true },
  -- (stage 3) loop (s of the sample), SYNC (recorded only), CUE, hot cues (-1 = empty), memory cue events (ev: each one a
  -- 30 ms step, 0 between), PITCH PLAY's key
  { label = "Perf loop on", sq = true },
  { label = "Perf loop start", sq = true },
  { label = "Perf loop end", sq = true },
  { label = "Perf loop roll", sq = true },
  { label = "Perf sync", sq = true },
  { label = "Perf cue position", sq = true },
  { label = "Perf hot cue 1", sq = true },
  { label = "Perf hot cue 2", sq = true },
  { label = "Perf hot cue 3", sq = true },
  { label = "Perf hot cue 4", sq = true },
  { label = "Perf hot cue 5", sq = true },
  { label = "Perf hot cue 6", sq = true },
  { label = "Perf hot cue 7", sq = true },
  { label = "Perf hot cue 8", sq = true },
  { label = "Perf memory cue", ev = true },
  { label = "Perf pitch play", sq = true },
  -- (stage 4) the mixer and the effects (lanes 23-74, see PRF_M in the JSFX): continuous ones thinned within 0.001 (the
  -- playback takes a change over that), the rest steps
  { label = "Perf xfader position", tol = 0.001 },
  { label = "Perf xfader cut", sq = true },
  { label = "Perf xfader side", sq = true },
  { label = "Perf channel volume", tol = 0.001 },
  { label = "Perf mute", sq = true },
  { label = "Perf video opacity", tol = 0.001 },
  { label = "Perf video blend", sq = true },
  { label = "Perf blend key threshold", tol = 0.001 },
  { label = "Perf blend key softness", tol = 0.001 },
  { label = "Perf filter type", sq = true },
  { label = "Perf filter cutoff", tol = 0.001 },
  { label = "Perf filter resonance", tol = 0.001 },
  { label = "Perf filter morph", tol = 0.001 },
  { label = "Perf video FX type", sq = true },
  { label = "Perf video FX amount", tol = 0.001 },
  { label = "Perf master FX type", sq = true },
  { label = "Perf master FX amount", tol = 0.001 },
  { label = "Perf FX knob 1", tol = 0.001 },
  { label = "Perf FX knob 2", tol = 0.001 },
  { label = "Perf FX knob 3", tol = 0.001 },
  { label = "Perf FX knob 4", tol = 0.001 },
  { label = "Perf FX knob 5", tol = 0.001 },
  { label = "Perf FX knob 6", tol = 0.001 },
  { label = "Perf FX knob 7", tol = 0.001 },
  { label = "Perf FX knob 8", tol = 0.001 },
  { label = "Perf Strobe knob", tol = 0.001 },
  { label = "Perf echo amount", tol = 0.001 },
  { label = "Perf bitcrusher amount", tol = 0.001 },
  { label = "Perf vibrato amount", tol = 0.001 },
  { label = "Perf sound of video FX", tol = 0.001 },
  { label = "Perf touch FX row 1", sq = true },
  { label = "Perf touch FX row 2", sq = true },
  { label = "Perf touch FX 1-1 amount", sq = true },
  { label = "Perf touch FX 1-2 amount", sq = true },
  { label = "Perf touch FX 1-3 amount", sq = true },
  { label = "Perf touch FX 1-4 amount", sq = true },
  { label = "Perf touch FX 1-5 amount", sq = true },
  { label = "Perf touch FX 1-6 amount", sq = true },
  { label = "Perf touch FX 1-7 amount", sq = true },
  { label = "Perf touch FX 1-8 amount", sq = true },
  { label = "Perf touch FX 2-1 amount", sq = true },
  { label = "Perf touch FX 2-2 amount", sq = true },
  { label = "Perf touch FX 2-3 amount", sq = true },
  { label = "Perf touch FX 2-4 amount", sq = true },
  { label = "Perf touch FX 2-5 amount", sq = true },
  { label = "Perf touch FX 2-6 amount", sq = true },
  { label = "Perf touch FX 2-7 amount", sq = true },
  { label = "Perf touch FX 2-8 amount", sq = true },
  { label = "Perf pitch mode", tol = 0.001 },
  { label = "Perf vibrato step", sq = true },
  { label = "Perf vibrato width", sq = true },
  { label = "Perf fader lanes gain", tol = 0.001 },
  { label = "Perf CLIP STOP held", sq = true },
  { label = "Perf video FX LFO shape", sq = true },
  { label = "Perf video FX LFO rate", sq = true },
  { label = "Perf video FX LFO depth", tol = 0.001 },
  { label = "Perf picture mute", sq = true },
  { label = "Perf FX boost", tol = 0.001 },
  { label = "Perf master level", tol = 0.001 },
  { label = "Perf blackout", sq = true },
}
M.PF_EV_LEN = 0.03   -- an event's step on its lane (s): over one block (23 ms at 1024 / 44.1 kHz), the playback reads one value a block
function M.perf_lanes_on() return reaper.GetExtState("ReaScratch", "perf_lanes") ~= "off" end
-- (⚪178 stage 2) "play the performance": while on (ExtState ReaScratch / perf_play = "on", kept; off by default) the video
-- sync lets REAPER play (it does not stop it, nor put the edit cursor on the head) and each deck plays its performance
-- lanes back (the JSFX, gmem[400] = the mode, [401] / [402] = deck A / B plays its lanes: on unless the ExtState
-- perf_play_A / perf_play_B = "off"). Toggled by reascratch_perf_play.lua
function M.perf_play_on() return reaper.GetExtState("ReaScratch", "perf_play") == "on" end
function M.perf_play_gmem()
  local on = M.perf_play_on()
  reaper.gmem_write(400, on and 1 or 0)
  reaper.gmem_write(401, reaper.GetExtState("ReaScratch", "perf_play_A") ~= "off" and 1 or 0)
  reaper.gmem_write(402, reaper.GetExtState("ReaScratch", "perf_play_B") ~= "off" and 1 or 0)
  return on
end
-- (⚪178) REAPER's "Stop/repeat playback at end of project" (Preferences > Audio > Playback; reaper.ini stopprojlen, on
-- when not written): on, REAPER stops one block after Play past the last media item, and the performance zone (from
-- PF_ZONE s, past the slot videos) cannot be played (found in stage 2). True when on. The user turns it off: the kit
-- only says where (a script cannot set it without an extension)
function M.stop_at_end_on()
  local ok, v = false, nil
  if reaper.get_config_var_string then ok, v = reaper.get_config_var_string("stopprojlen") end
  if not ok then
    for _, line in ipairs(M.ini_section("reaper")) do v = line:match("^stopprojlen=(%-?%d+)") or v end
  end
  return v == nil or tonumber(v) ~= 0
end
M.STOP_AT_END_MSG = {
  "REAPERの「プロジェクトの終わりで再生を止める」設定がオンです。このままでは、演奏の列（スロットの動画より後ろの区域）を再生できません。\n\n"
    .. "Options > Preferences（設定）> Audio > Playback の「Stop/repeat playback at end of project」のチェックを外してください（日本語の画面でも英語のままです）。",
  "REAPER's \"Stop/repeat playback at end of project\" is on. With it, the performance lanes (in the zone past the slot videos) cannot be played.\n\n"
    .. "Uncheck \"Stop/repeat playback at end of project\" in Options > Preferences > Audio > Playback." }

-- the perf JSFX on a track (its FX index), nil when none
function M.perf_fx(tr)
  for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local _, name = reaper.TrackFX_GetFXName(tr, fx, "")
    if name:find("^JS") and name:find(M.PERF_NAME, 1, true) then return fx end
  end
end

-- (⚪178 stage 1) the lanes must not move with REAPER's tempo: in a project whose timebase is beats, a tempo change moved
-- and stretched the automation items (120 -> 90 BPM: 36000 s -> 48000 s, 7.5 s of points -> 10.0 s), as it moves the
-- deck's own lanes (tempo_lead sets the kit's tracks to time for that on its first change). The engine track in time:
-- the items and their points stayed in place at any tempo (measured)
function M.pf_time_track(tr)
  if reaper.GetSetProjectInfo(0, "PROJECT_TIMEBASE", 0, false) ~= 0 and reaper.GetMediaTrackInfo_Value(tr, "C_BEATATTACHMODE") ~= 0 then
    reaper.SetMediaTrackInfo_Value(tr, "C_BEATATTACHMODE", 0)
  end
end

-- setup: the perf JSFX right before the deck's engine (added when missing, moved there when after it); its Deck slider
function M.perf_ensure(tr, deck)
  local efx = tr and M.engine_fx(tr)
  if not efx then return nil end
  M.pf_time_track(tr)
  local p = M.perf_fx(tr)
  if p and p > efx then reaper.TrackFX_CopyToTrack(tr, p, tr, efx, true); p = M.perf_fx(tr) end
  if not p then
    if reaper.TrackFX_AddByName(tr, "JS:" .. M.PERF_JSFX, false, -1000 - efx) < 0 then return nil end
    p = M.perf_fx(tr)
  end
  if p then M.set_param(tr, p, "Deck (", deck) end
  return p
end

local pf = { on = false }

-- the regions "Perf <n>": { k, a, b, idx, colour }
local function pf_regions()
  local out, i = {}, 0
  while true do
    local ret, isrgn, pos, rend, name, idx, col = reaper.EnumProjectMarkers3(0, i)
    if ret == 0 then break end
    local k = isrgn and tonumber(name:match("^Perf (%d+)$"))
    if k then out[#out + 1] = { k = k, a = pos, b = rend, idx = idx, c = col } end
    i = i + 1
  end
  return out
end

-- an automation item from `at` for `len` s with the points { t, v, shape }, named `name`, not looped. (The points
-- InsertAutomationItem puts in a new item are deleted one by one: DeleteEnvelopePointRangeEx left them, ⚪178 stage 0)
local function pf_item(env, at, len, pts, name)
  local ai = reaper.InsertAutomationItem(env, -1, at, len)
  for i = reaper.CountEnvelopePointsEx(env, ai) - 1, 0, -1 do reaper.DeleteEnvelopePointEx(env, ai, i) end
  for _, q in ipairs(pts) do reaper.InsertEnvelopePointEx(env, ai, q[1], q[2], q[3] or 0, 0, false, true) end
  reaper.Envelope_SortPointsEx(env, ai)
  reaper.GetSetAutomationItemInfo(env, ai, "D_LOOPSRC", 0, true)
  reaper.GetSetAutomationItemInfo_String(env, ai, "P_POOL_NAME", name, true)
  return ai
end

-- (⚪178 stage 3) the head lane's jumps (a hot cue, CUE, a loop's wrap or its end ...) as steps. The JSFX records the block
-- before a jump and the block of it, and a straight line between them is right only on the recording's own block grid:
-- played from another place (another grid; stage 3 test, from 2.0 s into the recording) the playback read a place between
-- the two, put the head there and back again (8 jumps more). A jump = two records a block apart (not driven) whose step is
-- off the running speed (the median of the slopes around) by over PF_JUMP s: the head runs on at that speed up to just
-- before the second one, then the step
M.PF_JUMP = 0.02
local function pf_steps(pts, drv)
  local function driven(t)
    local v = 0
    for _, r in ipairs(drv or {}) do if r[1] <= t + 0.000001 then v = r[2] else break end end
    return v > 0.5
  end
  local function slope(k) return (pts[k + 1][2] - pts[k][2]) / (pts[k + 1][1] - pts[k][1]) end
  local out = { pts[1] }
  for k = 2, #pts do
    local a, b = pts[k - 1], pts[k]
    local dt = b[1] - a[1]
    if dt > 0.0003 and dt < 0.06 and not driven(a[1]) and not driven(b[1] - 0.000001) then
      local sl = {}
      for j = math.max(1, k - 5), math.min(#pts - 1, k + 3) do
        if j ~= k - 1 and pts[j + 1][1] > pts[j][1] + 0.0001 then sl[#sl + 1] = slope(j) end
      end
      table.sort(sl)
      local sp = #sl > 0 and sl[math.floor((#sl + 1) / 2)] or 0
      if math.abs((b[2] - a[2]) - sp * dt) > M.PF_JUMP then out[#out + 1] = { b[1] - 0.0001, a[2] + sp * (dt - 0.0001) } end
    end
    out[#out + 1] = b
  end
  return out
end

-- one deck's records -> its lanes, moved by off (s); b = the recording's end there; n = the number in the items' names.
-- Returns the number of items
local function pf_put(d, off, b, n)
  if not (d.tr and reaper.ValidatePtr2(0, d.tr, "MediaTrack*")) then return 0 end
  local pfx = M.perf_fx(d.tr)   -- (its index now: an FX put before it meanwhile moved it)
  if not pfx then return 0 end
  M.pf_time_track(d.tr)
  local per = {}
  for _, r in ipairs(d.recs) do
    local l = math.floor(r[2] + 0.5)
    per[l] = per[l] or {}
    per[l][#per[l] + 1] = { r[1] + off, r[3] }
  end
  local last = {}
  for i = 1, #M.PF_LANES do local q = per[i]; last[i] = q and q[#q] and q[#q][2] end
  local made = 0
  for i, ln in ipairs(M.PF_LANES) do
    local q = per[i]
    if q and #q > 0 then
      table.sort(q, function(x, y) return x[1] < y[1] end)
      local pts = {}
      if ln.ev then
        -- (stage 3) events: each one PF_EV_LEN long (shorter when the next comes sooner), 0 between them and to the end
        for k, p in ipairs(q) do
          if p[2] == 0 then
            if #pts == 0 or pts[#pts][2] ~= 0 then pts[#pts + 1] = { p[1], 0, 1 } end
          else
            pts[#pts + 1] = { p[1], p[2], 1 }
            local e = p[1] + M.PF_EV_LEN
            if q[k + 1] and q[k + 1][1] < e then e = nil end
            if e then pts[#pts + 1] = { e, 0, 1 } end
          end
        end
        if pts[#pts][1] < b - 0.0005 then pts[#pts + 1] = { b, 0, 1 } end
      elseif ln.sq then
        for _, p in ipairs(q) do if #pts == 0 or math.abs(p[2] - pts[#pts][2]) > 0.0001 then pts[#pts + 1] = { p[1], p[2], 1 } end end
        if pts[#pts][1] < b - 0.0005 then pts[#pts + 1] = { b, pts[#pts][2], 1 } end
      elseif ln.head then
        for _, p in ipairs(q) do pts[#pts + 1] = { p[1], p[2] } end
        -- on to the end at the last speed (0 when paused) while nothing drove the head at the end
        local m = #pts
        if m >= 2 and last[3] == 0 and pts[m][1] < b - 0.0005 and pts[m][1] - pts[m - 1][1] > 0.0001 then
          local s = (pts[m][2] - pts[m - 1][2]) / (pts[m][1] - pts[m - 1][1])
          pts[m + 1] = { b, pts[m][2] + s * (b - pts[m][1]) }
        end
        pts = pf_steps(pts, per[3])
        pts = rc_thin(pts, ln.tol)
      else
        for k, p in ipairs(q) do
          if k > 1 and p[1] - q[k - 1][1] > 0.03 then pts[#pts + 1] = { p[1] - 0.001, q[k - 1][2] } end
          pts[#pts + 1] = { p[1], p[2] }
        end
        if pts[#pts][1] < b - 0.0005 then pts[#pts + 1] = { b, pts[#pts][2] } end
        pts = rc_thin(pts, ln.tol)
      end
      -- (stage 0) the last point square and the item ending right after it: else the item's end runs a straight line back
      -- to its first value (a looped source), and a point at the item's very end is read at its start
      pts[#pts][3] = 1
      local a, e = pts[1][1], pts[#pts][1] + 0.001
      local _, mark = reaper.TrackFX_GetParamEx(d.tr, pfx, i)
      local env = M.ev_lane(d.tr, pfx, ln.label, mark)
      if env then
        M.ev_punch(env, a, e)
        pf_item(env, a, e - a, pts, ("Perf %s-%d"):format(d.deck == 2 and "B" or "A", n))
        made = made + 1
      end
    end
  end
  return made
end

-- the project's tempo set (as SetCurrentBPM) with the "Perf <n>" regions kept where they are: the regions follow the
-- project's timebase (beats: they moved away from the lanes, which stay in time on the engine track)
function M.pf_set_bpm(bpm)
  local keep = pf_regions()
  reaper.SetCurrentBPM(0, bpm, false)
  for _, g in ipairs(keep) do reaper.SetProjectMarker3(0, g.idx, true, g.a, g.b, "Perf " .. g.k, g.c) end
end

-- called on every cycle of the video sync script (as rec_tick). Returns a line to show when it put a recording on the lanes
function M.pf_tick(recording, decks)
  local function add(deck)
    for _, d in ipairs(pf.decks) do if d.deck == deck then return end end
    local e = decks[deck]
    if not (e and e[1]) then return end
    if not M.perf_fx(e[1]) then pf.missing[deck] = true return end
    local b = M.pf_base(deck)
    pf.decks[#pf.decks + 1] = { deck = deck, tr = e[1], read = reaper.gmem_read(b), recs = {}, lost = 0 }
    reaper.gmem_write(b + 1, 1)
  end
  if recording and not pf.on then
    if not M.perf_lanes_on() then return end
    pf.on, pf.decks, pf.missing = true, {}, {}
    add(1); add(2)
    return
  end
  if not pf.on then return end
  if recording then add(1); add(2) end   -- (a deck that came during the recording: from then on)
  for _, d in ipairs(pf.decks) do ring_drain(d, M.pf_base(d.deck), M.PF_W, M.PF_N) end
  if recording then return end
  pf.on = false
  local rs, re = math.huge, -math.huge
  for _, d in ipairs(pf.decks) do
    reaper.gmem_write(M.pf_base(d.deck) + 1, 0)
    if #d.recs > 0 then re = math.max(re, reaper.gmem_read(M.pf_base(d.deck) + 2)) end
    for _, r in ipairs(d.recs) do rs = math.min(rs, r[1]); re = math.max(re, r[1]) end
  end
  _G.REASCRATCH_PERF_LAST = pf.decks                  -- (tests read the raw records)
  local msg = {}
  for deck in pairs(pf.missing) do
    msg[#msg + 1] = ("deck %s has no performance lanes (run setup)"):format(deck == 2 and "B" or "A")
  end
  if rs == math.huge then return #msg > 0 and ("performance lanes: " .. table.concat(msg, "; ")) or nil end
  -- where: inside the zone as played, else after the last recording there
  local regs = pf_regions()
  local n = 0
  for _, g in ipairs(regs) do n = math.max(n, g.k) end
  for _, d in ipairs(pf.decks) do
    local pfx = d.tr and reaper.ValidatePtr2(0, d.tr, "MediaTrack*") and M.perf_fx(d.tr)
    if pfx then
      for i = 1, #M.PF_LANES do
        local env = M.ev_env(d.tr, pfx, M.PF_LANES[i].label, false)
        for j = 0, (env and reaper.CountAutomationItems(env) or 0) - 1 do
          local _, nm = reaper.GetSetAutomationItemInfo_String(env, j, "P_POOL_NAME", "", false)
          local k = tonumber(nm:match("^Perf %u%-(%d+)$"))
          if k and k > n then n = k end
        end
      end
    end
  end
  n = n + 1
  local off = 0
  if rs < M.PF_ZONE - 0.001 then
    local at = M.PF_ZONE
    for _, g in ipairs(regs) do at = math.max(at, math.ceil(g.b + M.PF_GAP)) end
    off = at - rs
  end
  local a, b = rs + off, re + off
  reaper.Undo_BeginBlock()
  local ok, err = pcall(function()
    -- the region: a new one, or (inside the zone) the one it overlaps made long enough
    local hit
    if off == 0 then for _, g in ipairs(regs) do if g.a < b and g.b > a then hit = g break end end end
    if hit then
      if a < hit.a or b > hit.b then reaper.SetProjectMarker3(0, hit.idx, true, math.min(a, hit.a), math.max(b + 0.001, hit.b), "Perf " .. hit.k, hit.c) end
      msg[#msg + 1] = ("in Perf %d at %.3f-%.3f s"):format(hit.k, a, b)
    else
      reaper.AddProjectMarker2(0, true, a, b + 0.001, "Perf " .. n, -1, 0)
      msg[#msg + 1] = ("Perf %d at %.3f-%.3f s"):format(n, a, b)
    end
    for _, d in ipairs(pf.decks) do
      local line = ("deck %s: %d lanes"):format(d.deck == 2 and "B" or "A", pf_put(d, off, b, n))
      if d.lost > 0 then line = line .. (", %d records lost"):format(d.lost) end
      msg[#msg + 1] = line
    end
  end)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(M.T("ReaScratch: 演奏の列に記録", "ReaScratch: record the performance lanes"), -1)
  if not ok then
    M.log(M.T("演奏の列に書き込む途中でエラー: ", "error while writing the performance lanes: ") .. tostring(err))
    return "performance lanes (stopped by an error): " .. table.concat(msg, "; ")
  end
  return "performance lanes: " .. table.concat(msg, "; ")
end

-- ⚪14 filming the decks. reascratch_take.lua adds a track "Rec A" ("Rec B") per deck that records the deck's sound
-- before the crossfader (the JSFX's channels 3/4, a pre-fader send; it does not feed the master). While REAPER records,
-- each deck's JSFX adds a record per audio block to its take ring in gmem (REAPER's position, the frame shown, how late
-- the sound is, crossfader gain; layout: the JSFX, TK_W). When the recording stops and REAPER has put the recorded item on the track,
-- take_tick makes a new project (Data/ReaScratch_takes/<project>_<date>.rpp, opened in a new tab, the live project stays
-- in front): per deck a video track whose items cut the deck's video (the original file when it lies next to the
-- all-keyframe copy) so that each frame is the one the deck showed, and the recorded sound. The recorded item leaves the
-- live project (its file stays). The take project can be edited and rendered like any project.
M.TK_W = 4
M.TK_N = math.floor((400000 - 8) / M.TK_W)
function M.tk_base(deck) return deck == 2 and 4600000 or 4200000 end
M.TRACK_TAKE = { "Rec A", "Rec B" }
M.TRACK_TAKE_MIX = "Rec Mix"
M.MX_BASE, M.MX_W = 5000000, 22                -- the mix ring (the JSFX: MX_K = the shared memory each record copies)
M.MX_N = math.floor((400000 - 8) / M.MX_W)
M.TAKE_DIR = M.RES .. M.SEP .. "Data" .. M.SEP .. "ReaScratch_takes"
M.TK_RATE_MIN = 0.0001                     -- play rate of an item that holds one frame
M.TK_JUMP = 0.5                            -- the frame shown moving by more than this (s) in a block = a jump (not drawn between)
M.TK_PART = 20                             -- ((⚪151) s after the first recorded item is found: the take is made without the missing ones

-- a "Rec" track: deck 1 / 2, or "mix". nil when none
function M.take_track(which)
  if which == "mix" then return M.track_by_name(M.TRACK_TAKE_MIX) end
  return M.track_by_name(M.TRACK_TAKE[which])
end

-- the "Rec" tracks on (true) / off (false). On: one per deck, the engine gets 4 channels (its parent send keeps 1/2).
-- Returns the number of decks filmed
function M.take_prepare(on)
  local n = 0
  for deck = 1, 2 do
    local eng = M.find_engine(deck)
    local cap = M.track_by_name(M.TRACK_TAKE[deck])
    if on and eng then
      cap = cap or M.ensure_track(M.TRACK_TAKE[deck])
      reaper.SetMediaTrackInfo_Value(cap, "B_MAINSEND", 0)
      reaper.SetMediaTrackInfo_Value(cap, "I_RECINPUT", -1)
      reaper.SetMediaTrackInfo_Value(cap, "I_RECMODE", 1)          -- record: output (stereo)
      reaper.SetMediaTrackInfo_Value(cap, "I_RECMON", 0)
      reaper.SetMediaTrackInfo_Value(cap, "I_RECARM", 1)
      local has = false
      for i = 0, reaper.GetTrackNumSends(cap, -1) - 1 do
        if reaper.GetTrackSendInfo_Value(cap, -1, i, "P_SRCTRACK") == eng then has = true end
      end
      if not has then
        local k = reaper.CreateTrackSend(eng, cap)
        reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SRCCHAN", 2)       -- channels 3/4: before the crossfader
        reaper.SetTrackSendInfo_Value(eng, 0, k, "I_DSTCHAN", 0)
        reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SENDMODE", 3)      -- pre-fader (post-FX)
      end
      local _, was = reaper.GetSetMediaTrackInfo_String(eng, "P_EXT:ReaScratch_take", "", false)
      if was == "" then
        reaper.GetSetMediaTrackInfo_String(eng, "P_EXT:ReaScratch_take", string.format("%d %d",
          reaper.GetMediaTrackInfo_Value(eng, "I_NCHAN"), reaper.GetMediaTrackInfo_Value(eng, "C_MAINSEND_NCH")), true)
      end
      if reaper.GetMediaTrackInfo_Value(eng, "I_NCHAN") < 4 then reaper.SetMediaTrackInfo_Value(eng, "I_NCHAN", 4) end
      reaper.SetMediaTrackInfo_Value(eng, "C_MAINSEND_NCH", 2)
      n = n + 1
    elseif not on then
      if cap then reaper.DeleteTrack(cap) end
      if eng then
        local _, was = reaper.GetSetMediaTrackInfo_String(eng, "P_EXT:ReaScratch_take", "", false)
        local nch, msn = was:match("^(%-?%d+) (%-?%d+)$")
        if nch then
          -- (the cue needs channels 5/6 while the "Cue" track is there)
          reaper.SetMediaTrackInfo_Value(eng, "I_NCHAN", math.max(tonumber(nch), M.track_by_name(M.TRACK_CUE) and M.CUE_NCH or 0))
          reaper.SetMediaTrackInfo_Value(eng, "C_MAINSEND_NCH", tonumber(msn))
          reaper.GetSetMediaTrackInfo_String(eng, "P_EXT:ReaScratch_take", "", true)
        end
      end
    end
  end
  -- the mix as heard: both decks after their faders (sends 1/2), through a copy of the master's FX at the master's
  -- volume (a meter / visualizer is left out). It does not feed the master
  local mixt = M.track_by_name(M.TRACK_TAKE_MIX)
  if on and n > 0 then
    if not mixt then
      mixt = M.ensure_track(M.TRACK_TAKE_MIX)
      local m = reaper.GetMasterTrack(0)
      for i = 0, reaper.TrackFX_GetCount(m) - 1 do
        local _, nm = reaper.TrackFX_GetFXName(m, i, "")
        if not nm:lower():find("visuali") and not nm:lower():find("meter") then
          reaper.TrackFX_CopyToTrack(m, i, mixt, reaper.TrackFX_GetCount(mixt), false)
        end
      end
      reaper.SetMediaTrackInfo_Value(mixt, "D_VOL", reaper.GetMediaTrackInfo_Value(m, "D_VOL"))
      for deck = 1, 2 do
        local eng = M.find_engine(deck)
        if eng then
          local k = reaper.CreateTrackSend(eng, mixt)
          reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SRCCHAN", 0)
          reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SENDMODE", 0)    -- post-fader (the channel's volume counts)
        end
      end
    end
    reaper.SetMediaTrackInfo_Value(mixt, "B_MAINSEND", 0)
    reaper.SetMediaTrackInfo_Value(mixt, "I_RECINPUT", -1)
    reaper.SetMediaTrackInfo_Value(mixt, "I_RECMODE", 1)
    reaper.SetMediaTrackInfo_Value(mixt, "I_RECMON", 0)
    reaper.SetMediaTrackInfo_Value(mixt, "I_RECARM", 1)
  elseif not on and mixt then
    reaper.DeleteTrack(mixt)
  end
  return n
end

-- headphone cue (2026-10-06): a "Cue" track that does not feed the master and goes straight to the headphone output.
-- Each deck sends its channels 5/6 (the JSFX puts its sound before the crossfader there while the deck's cue is on;
-- pre-fader) to the Cue track's 1/2, and its channels 1/2 (the main, after the track fader) to the Cue track's 3/4;
-- the cue mix JSFX on the Cue track mixes the two (the Cue mix knob). The same build as the AB Router's Cue bus in the
-- Playtime project (playtime2_realearn/setup_ab_cue_routing.lua). Run again any time: the sends are made anew, the
-- JSFX and its settings are kept, the headphone output is set only when the track has none (a hand-picked one stays).
-- Returns the Cue track and the name of the output it goes to (nil when no output named like headphones was found)
M.TRACK_CUE = "Cue"
M.CUE_JSFX = "ReaScratch/reascratch_cue.jsfx"
M.CUE_NCH = 8   -- (⚪191) + channels 7/8: the metronome (to the Cue track's 5/6)
-- (⚪191) a deck's send of its metronome (channels 7/8) to the Cue track's 5/6: pre-fader (post-FX), as the cue
local function cue_metro_send(eng, cue)
  if reaper.GetMediaTrackInfo_Value(eng, "I_NCHAN") < M.CUE_NCH then reaper.SetMediaTrackInfo_Value(eng, "I_NCHAN", M.CUE_NCH) end
  local k = reaper.CreateTrackSend(eng, cue)
  reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SRCCHAN", 6)
  reaper.SetTrackSendInfo_Value(eng, 0, k, "I_DSTCHAN", 4)
  reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SENDMODE", 3)
end
-- (⚪191) a project set up before the metronome: its decks' metronome sends added (the video sync script, at its start).
-- Returns how many were added
function M.cue_metro_ensure()
  local cue = M.track_by_name(M.TRACK_CUE)
  if not cue then return 0 end
  local n = 0
  for deck = 1, 2 do
    local eng = M.find_engine(deck)
    if eng then
      local has = false
      for i = 0, reaper.GetTrackNumSends(eng, 0) - 1 do
        if reaper.GetTrackSendInfo_Value(eng, 0, i, "P_DESTTRACK") == cue and reaper.GetTrackSendInfo_Value(eng, 0, i, "I_SRCCHAN") == 6 then has = true end
      end
      if not has then cue_metro_send(eng, cue); n = n + 1 end
    end
  end
  if n > 0 and reaper.GetMediaTrackInfo_Value(cue, "I_NCHAN") < 6 then reaper.SetMediaTrackInfo_Value(cue, "I_NCHAN", 6) end
  return n
end
-- the headphone output's first channel: the one picked before on this PC (kept in REAPER by its name), else one named
-- like headphones, else asked from a list of the stereo pairs (RME UCX II: no names say phones, its Phones are Analog
-- 7/8 - found with the user, 2026-10-07). Returns the channel and its name, or nil (no choice)
-- ((⚪151) an output without a name (GetOutputChannelName nil) stopped the setup with an error: "Output <n>" then)
local function output_name(i) return reaper.GetOutputChannelName(i) or ("Output " .. (i + 1)) end
function M.headphone_output()
  local n_out = reaper.GetNumAudioOutputs()
  local kept = reaper.GetExtState("ReaScratch", "cue_out")
  for i = 0, n_out - 1 do
    if kept ~= "" and output_name(i) == kept then return i, kept end
  end
  for i = 0, n_out - 1 do
    local n = output_name(i)
    local l = n:lower()
    if l:find("phone") or n:find("ヘッドホン") or n:find("ヘッドフォン") then return i, n end
  end
  if n_out < 2 then return nil end
  local items, chans = {}, {}
  for i = 0, n_out - 2, 2 do
    items[#items + 1] = output_name(i) .. " / " .. output_name(i + 1)
    chans[#chans + 1] = i
  end
  local k = M.choose(M.T("ヘッドホン（Cue）につながる出力はどれですか？（あとで変えるときは Cue トラックの ROUTE）",
    "Which output goes to your headphones (Cue)? (to change it later: ROUTE on the Cue track)"), items)
  if k < 1 or not chans[k] then return nil end
  local n = output_name(chans[k])
  reaper.SetExtState("ReaScratch", "cue_out", n, true)
  return chans[k], n
end
function M.cue_prepare()
  local cue = M.ensure_track(M.TRACK_CUE)
  reaper.SetMediaTrackInfo_Value(cue, "B_MAINSEND", 0)
  reaper.SetMediaTrackInfo_Value(cue, "I_NCHAN", 6)   -- (⚪191) 5/6: the metronome
  local has_fx = false
  for fx = 0, reaper.TrackFX_GetCount(cue) - 1 do
    local _, nm = reaper.TrackFX_GetFXName(cue, fx, "")
    if nm:find("cue mix", 1, true) then has_fx = true end
  end
  if not has_fx then reaper.TrackFX_AddByName(cue, "JS:" .. M.CUE_JSFX, false, -1) end
  -- the decks' sends: old ones out, new ones in
  for i = reaper.GetTrackNumSends(cue, -1) - 1, 0, -1 do reaper.RemoveTrackSend(cue, -1, i) end
  for deck = 1, 2 do
    local eng = M.find_engine(deck)
    if eng then
      if reaper.GetMediaTrackInfo_Value(eng, "I_NCHAN") < M.CUE_NCH then reaper.SetMediaTrackInfo_Value(eng, "I_NCHAN", M.CUE_NCH) end
      reaper.SetMediaTrackInfo_Value(eng, "C_MAINSEND_NCH", 2)          -- the master gets 1/2 only
      local k = reaper.CreateTrackSend(eng, cue)
      reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SRCCHAN", 4)          -- channels 5/6: the cue
      reaper.SetTrackSendInfo_Value(eng, 0, k, "I_DSTCHAN", 0)
      reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SENDMODE", 3)         -- pre-fader (post-FX)
      k = reaper.CreateTrackSend(eng, cue)
      reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SRCCHAN", 0)          -- channels 1/2: the main
      reaper.SetTrackSendInfo_Value(eng, 0, k, "I_DSTCHAN", 2)
      reaper.SetTrackSendInfo_Value(eng, 0, k, "I_SENDMODE", 0)         -- post-fader
      cue_metro_send(eng, cue)                                          -- channels 7/8: the metronome (⚪191)
    end
  end
  -- the headphone output (a hardware output of the track)
  local out_name
  -- ((env notes, 2026-10-17) the output is kept in the project by its channel number: a project opened on another PC
  -- or with another audio device whose outputs end before it is given its output anew)
  local n_out = reaper.GetNumAudioOutputs()
  if reaper.GetTrackNumSends(cue, 1) > 0 and n_out > 0 then
    local dst = math.floor(reaper.GetTrackSendInfo_Value(cue, 1, 0, "I_DSTCHAN"))
    local last = (dst & 1023) + ((dst & 1024) ~= 0 and 0 or 1)
    if last >= n_out then
      M.log(("cue: the Cue track went to output %d, which this audio device does not have (%d outputs): picked anew"):format((dst & 1023) + 1, n_out))
      reaper.RemoveTrackSend(cue, 1, 0)
    end
  end
  if reaper.GetTrackNumSends(cue, 1) == 0 then
    local ch, n = M.headphone_output()
    if ch then
      local k = reaper.CreateTrackSend(cue, nil)
      reaper.SetTrackSendInfo_Value(cue, 1, k, "I_SRCCHAN", 0)
      reaper.SetTrackSendInfo_Value(cue, 1, k, "I_DSTCHAN", ch)          -- stereo pair from this output channel
      out_name = n
    end
  else
    out_name = reaper.GetOutputChannelName(math.floor(reaper.GetTrackSendInfo_Value(cue, 1, 0, "I_DSTCHAN")) & 1023)
  end
  return cue, out_name
end

function M.take_on()
  return M.take_track(1) ~= nil or M.take_track(2) ~= nil
end

-- (⚪151) the on / off state of an action on the toolbar (reascratch_take.lua and reascratch_record_lanes.lua wrote it
-- each in its own way; REAPER forgets it on restart, so "record into the lanes", on by default, showed off until clicked
-- twice). set_toggle: one action (section, command id); sync_toggles: both scripts from the kit folder `here`, by the
-- state they stand for (called by the video sync when it starts and for each project it finds; written only when it differs)
function M.set_toggle(sec, cmd, on)
  if not (cmd and cmd > 0) then return end
  reaper.SetToggleCommandState(sec, cmd, on and 1 or 0)
  reaper.RefreshToolbar2(sec, cmd)
end
local tg_ids = nil
function M.sync_toggles(here)
  if not tg_ids then
    -- (setup registered them; asking again only returns their command ids)
    tg_ids = {}
    for _, nm in ipairs({ "reascratch_take.lua", "reascratch_record_lanes.lua", "reascratch_perf_play.lua" }) do
      local p = here .. nm
      tg_ids[nm] = reaper.file_exists(p) and reaper.AddRemoveReaScript(true, 0, p, false) or 0
    end
  end
  for nm, on in pairs({ ["reascratch_take.lua"] = M.take_on(), ["reascratch_record_lanes.lua"] = M.rec_lanes_on(), ["reascratch_perf_play.lua"] = M.perf_play_on() }) do
    local id = tg_ids[nm]
    if id and id > 0 and reaper.GetToggleCommandStateEx(0, id) ~= (on and 1 or 0) then M.set_toggle(0, id, on) end
  end
end

-- (⚪151) a defer script's liveness by a heartbeat in the ExtState ReaScratch / key (the video sync and the load test had
-- each their own copy): a running one (beat within 1 s) is sent "stop" (not when ensure: left alone). Returns true when
-- this run should go on; then, with claim, the heartbeat is written at once (a "stop" left behind made a new video sync
-- stop itself on its first cycle, 2026-10-04). Second value: a stop was sent
function M.heartbeat_claim(key, ensure, claim)
  local now = reaper.time_precise()
  if now - (tonumber(reaper.GetExtState("ReaScratch", key)) or 0) < 1.0 then
    if ensure then return false, false end
    reaper.SetExtState("ReaScratch", key, "stop", false)
    return false, true
  end
  if claim then reaper.SetExtState("ReaScratch", key, tostring(now), false) end
  return true
end

-- the original of an all-keyframe copy "<name>_mjpeg.avi": a video "<name>.*" next to it (nil when there is none)
local TK_EXT = { "mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv", "mpg", "mpeg" }
function M.take_original(path)
  local base = M.stem(path):match("^(.*)_mjpeg$")
  if not base then return nil end
  local dir = M.dirname(path)
  for _, e in ipairs(TK_EXT) do
    for _, x in ipairs({ e, e:upper() }) do
      local f = dir .. M.SEP .. base .. "." .. x
      if f ~= path and reaper.file_exists(f) then return f end
    end
  end
end

-- the slot videos of a deck's store track ("video" / "video B"): { {pos, len, offs, rate, path} }
local function tk_videos(deck)
  local tr = M.track_by_name(deck == 2 and M.TRACK_VIDEO_B or M.TRACK_VIDEO)
  local out = {}
  if not tr then return out end
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local tk = reaper.GetActiveTake(it)
    local src = tk and reaper.GetMediaItemTake_Source(tk)
    if src and not M.is_perf_view(it) then   -- ((⚪178) not the performance's picture item)
      out[#out + 1] = { reaper.GetMediaItemInfo_Value(it, "D_POSITION"), reaper.GetMediaItemInfo_Value(it, "D_LENGTH"),
                        reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS"), reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"),
                        reaper.GetMediaSourceFileName(src, "") }
    end
  end
  return out
end

-- the frame at REAPER's position p: the records { pos, frame (s on the timeline), sound lag, xf }, sorted by pos (the
-- positions already moved on by the lag, so the frame is the one of the sound heard then).
-- Between two blocks the frame moves on in a straight line (not across a jump). nil before the first / after the last
local function tk_at(recs, p)
  local n = #recs
  if n == 0 or p > recs[n][1] + 0.05 then return nil end
  -- before the first record (it starts the sound's lag after the recording): its frame
  if p < recs[1][1] then return p >= recs[1][1] - 0.1 and recs[1][2] >= 0 and recs[1][2] or nil end
  local lo, hi = 1, n
  while lo < hi do local m = (lo + hi + 1) // 2; if recs[m][1] <= p then lo = m else hi = m - 1 end end
  local a, b = recs[lo], recs[lo + 1]
  if a[2] < 0 then return nil end
  if not b or b[2] < 0 or math.abs(b[2] - a[2]) > M.TK_JUMP or b[1] <= a[1] then return a[2] end
  return a[2] + (b[2] - a[2]) * (p - a[1]) / (b[1] - a[1])
end

-- frames { q (index in the source), path } on a grid of F per second -> items { at, len, offs, rate, path } so that a
-- frame at t shows the frame of the source at offs + (t - at) x rate. A run is one item when a straight line through
-- the frames' middles stays inside each frame (away from its edges); a run of one frame holds it (TK_RATE_MIN)
local function tk_items(fr, F, Fs)
  local out, i, n = {}, 1, #fr
  local function fits(i, j)
    local a, b = fr[i], fr[j]
    if not b or a.path ~= b.path then return false end
    local r = (b.q - a.q) / Fs / ((j - i) / F)
    if r < 0 then return false end
    local o = (a.q + 0.5) / Fs
    for m = i + 1, j - 1 do
      local f = fr[m]
      if not f or f.path ~= a.path then return false end
      local x = (o + r * (m - i) / F) * Fs
      if math.floor(x) ~= f.q or x - f.q < 0.1 or x - f.q > 0.9 then return false end
    end
    if r == 0 then return (j - i + 1) / F * M.TK_RATE_MIN * Fs < 0.4 end
    return true
  end
  while i <= n do
    if not fr[i] then i = i + 1 else
      -- grow by doubling, then halve back to the longest run that fits
      local good, step = i, 1
      while i + step <= n and fits(i, i + step) do good = i + step; step = step * 2 end
      local lo, hi = good, math.min(n, i + step - 1)
      while lo < hi do
        local m = (lo + hi + 1) // 2
        if fits(i, m) then lo = m else hi = m - 1 end
      end
      local j = lo
      local r = j > i and (fr[j].q - fr[i].q) / Fs / ((j - i) / F) or 0
      out[#out + 1] = { (i - 1) / F, (j - i + 1) / F, (fr[i].q + 0.5) / Fs, r > 0 and r or M.TK_RATE_MIN, fr[i].path }
      i = j + 1
    end
  end
  return out
end

-- one deck's frames over the recorded item (project position t0, length len): frames { q, path, w, h }, F (grid per s,
-- the first source's frame rate or fps_min when higher), Fs (that source's frame rate)
local function tk_frames(d, t0, len, fps_min)
  local vids = tk_videos(d.deck)
  local src_of = {}
  local function source(v)
    for _, w in ipairs(vids) do
      if v >= w[1] - 0.0005 and v < w[1] + w[2] then
        local path = w[5]
        if src_of[path] == nil then
          local hq = M.take_original(path)
          local w, h, fps = M.video_info(hq or path)
          if not fps and hq then w, h, fps = M.video_info(path) end
          -- the header's rounded rate (an AVI's 33366 us = 29.9706) -> the usual one it means (30000/1001)
          for _, r in ipairs({ 24000 / 1001, 24, 25, 30000 / 1001, 30, 50, 60000 / 1001, 60 }) do
            if fps and math.abs(fps - r) < r * 0.0005 then fps = r end
          end
          src_of[path] = { hq or path, fps or 30, w, h }
        end
        return src_of[path], w[3] + (v - w[1]) * w[4]
      end
    end
  end
  -- the grid: the first source's frame rate (at least the project's)
  local Fs
  for _, r in ipairs(d.recs) do
    if r[2] >= 0 then local s = source(r[2]); if s then Fs = s[2] break end end
  end
  if not Fs then return nil end
  local F = math.max(Fs, fps_min or 0)
  local fr = {}
  -- up to the end of the sound: the last frame may start before it and end after it (rounding dropped it, user's choice
  -- 2026-10-06: keep it)
  for k = 1, math.ceil(len * F - 0.000001) do
    local v = tk_at(d.recs, t0 + (k - 1) / F)
    local s, st
    if v then s, st = source(v) end
    fr[k] = s and { q = math.floor(st * s[2] + 0.0001), path = s[1], w = s[3], h = s[4] } or false
  end
  return fr, F, Fs
end

-- a frame-exact video of one deck with ffmpeg, in the background: frames fr (on a grid of F per second, { q, path, w, h }
-- or false = no picture) and the recorded sound (wav from offs, len s) -> out (H.264 + AAC). The frames used are taken out of
-- each source in one pass (select by frame number, as JPEG), then put in order with the concat demuxer (each with its
-- duration). Works in <out>_frames (deleted at the end); ffmpeg's messages go to <out>.log. Returns true when started
function M.take_ffmpeg(ff, fr, F, wav, offs, len, out)
  -- the rate as ffmpeg should read it: 30000/1001 exactly, not 29.970030
  local n1001 = math.floor(F * 1001 + 0.5)
  local Fr = (math.abs(F * 1001 - n1001) < 0.000001 and n1001 % 1000 == 0) and string.format("%d/1001", n1001)
             or string.format("%.6f", F)
  local dir = out:gsub("%.mp4$", "") .. "_frames"
  reaper.RecursiveCreateDirectory(dir, 0)
  -- per source: the frame numbers used -> their order among the frames taken out
  local srcs, order = {}, {}
  for _, f in ipairs(fr) do
    if f then
      if not srcs[f.path] then srcs[f.path] = { used = {}, w = f.w, h = f.h }; order[#order + 1] = f.path end
      srcs[f.path].used[f.q] = true
    end
  end
  if #order == 0 then return false end
  local lines = {}
  local function q_(p) return '"' .. p .. '"' end
  local ffq = q_(ff) .. " -hide_banner -nostdin -loglevel error -y"
  for i, path in ipairs(order) do
    local s = srcs[path]
    local qs = {}
    for q in pairs(s.used) do qs[#qs + 1] = q end
    table.sort(qs)
    s.idx = {}
    local ranges, a, b = {}, nil, nil
    for k, q in ipairs(qs) do
      s.idx[q] = k
      if a and q == b + 1 then b = q else
        if a then ranges[#ranges + 1] = string.format("between(n\\,%d\\,%d)", a, b) end
        a, b = q, q
      end
    end
    ranges[#ranges + 1] = string.format("between(n\\,%d\\,%d)", a, b)
    local sel = dir .. M.SEP .. "select" .. i .. ".txt"
    local h = M.open_w(sel)
    if not h then return false end
    h:write("select=" .. table.concat(ranges, "+"))
    h:close()
    reaper.RecursiveCreateDirectory(dir .. M.SEP .. "s" .. i, 0)
    -- ((⚪151) -filter_script is deprecated from ffmpeg 7.0: -/filter:v there, as -/filter_complex in take_ffmpeg_mix)
    lines[#lines + 1] = ffq .. " -i " .. q_(path) .. " -map 0:v:0" ..
      ((M.FFMPEG_MAJOR or 99) >= 7 and " -/filter:v " or " -filter_script:v ") .. q_(sel) ..
      " " .. M.ffmpeg_passthrough() .. " -q:v 2 " .. q_(dir .. M.SEP .. "s" .. i .. M.SEP .. "%06d.jpg")
    s.sub = "s" .. i
  end
  -- a black frame where the deck showed nothing (the first source's size)
  local s1 = srcs[order[1]]
  lines[#lines + 1] = ffq .. string.format(" -f lavfi -i color=black:s=%dx%d -frames:v 1 -q:v 2 ", s1.w or 1280, s1.h or 720) ..
    q_(dir .. M.SEP .. "black.jpg")
  -- the concat list: runs of the same frame are one entry
  local h = M.open_w(dir .. M.SEP .. "list.txt")
  if not h then return false end
  local last, run = nil, 0
  local function flush()
    -- (an image's own time base is 1/25 s, which put the entries on a 25 fps grid: each gets the frame rate)
    if last then h:write(string.format("file '%s'\noption framerate %s\nduration %.6f\n", last, Fr, run / F)) end
  end
  for _, f in ipairs(fr) do
    local nm = f and string.format("%s/%06d.jpg", srcs[f.path].sub, srcs[f.path].idx[f.q]) or "black.jpg"
    if nm == last then run = run + 1 else flush(); last, run = nm, 1 end
  end
  flush()
  h:write(string.format("file '%s'\noption framerate %s\n", last, Fr))              -- (the concat demuxer drops the last entry's duration)
  h:close()
  -- (the entries start on frame edges, which the fps filter rounded either way: moved on by half a frame, rounded down)
  lines[#lines + 1] = ffq .. " -f concat -safe 0 -i " .. q_(dir .. M.SEP .. "list.txt") ..
    string.format(" -ss %.6f -t %.6f -i ", offs or 0, len) .. q_(wav) ..
    string.format(" -map 0:v:0 -map 1:a:0 -vf settb=AVTB,setpts=PTS+%.9f/TB,fps=%s:round=down", 0.5 / F, Fr) ..
    -- (no -shortest: it dropped the last frame; the repeated last entry adds one frame: cut at the planned count)
    string.format(" -frames:v %d", #fr) ..
    " -c:v libx264 -crf 14 -pix_fmt yuv420p -c:a aac -b:a 320k " .. q_(out)
  local log = out .. ".log"
  local script
  if WIN then
    script = dir .. ".bat"
    local b = {}
    -- (a batch file reads %0 in "%06d.jpg" as its own name: every % doubled)
    for _, l in ipairs(lines) do b[#b + 1] = M.bat_esc(l .. " >> " .. q_(log)) .. " 2>&1 || goto fail" end
    b[#b + 1] = "rmdir /s /q " .. M.bat_esc(q_(dir))
    -- ((⚪151) the status on a line of its own (echo. ends a line ffmpeg left open), read by the mix's batch)
    b[#b + 1] = "(echo.& echo " .. M.BAT_DONE .. ") >> " .. M.bat_esc(q_(log))
    b[#b + 1] = 'del "%~f0" & exit /b 0'
    b[#b + 1] = ":fail"
    b[#b + 1] = "(echo.& echo " .. M.BAT_FAILED .. ") >> " .. M.bat_esc(q_(log))
    if not M.write_bat(script, b) then M.log(M.T("書き込めません: ", "cannot write: ") .. script) return false end   -- ((⚪151) M.write_bat / M.run_bat)
    M.run_bat(script)
  else
    script = dir .. ".sh"
    local b = {}
    for _, l in ipairs(lines) do b[#b + 1] = l .. " >> " .. q_(log) .. " 2>&1 || { printf '\\n%s\\n' '" .. M.BAT_FAILED .. "' >> " .. q_(log) .. "; exit 1; }" end
    b[#b + 1] = "rm -rf " .. q_(dir)
    b[#b + 1] = "printf '\\n%s\\n' '" .. M.BAT_DONE .. "' >> " .. q_(log)
    b[#b + 1] = 'rm -f "$0"'
    if not M.write_sh(script, b) then M.log(M.T("書き込めません: ", "cannot write: ") .. script) return false end
    M.run_sh(script)
  end
  return true
end

-- the mix as the video window showed it, with ffmpeg only, in the background (after the decks' videos are done): both
-- decks' frame-exact videos fitted into W x H, mixed by the crossfader (the gains after the flips, as the deck mix
-- draws them) and the per-pixel blends mix / add / subtract / multiply / overlay / soft light / hard light, with the
-- recorded mix sound -> out. The blend has one fixed expression that picks each frame's mix by its time T (changing it
-- per frame with sendcmd was one frame early or late now and then, 2026-10-06). Not drawn: the luma / chroma key (drawn
-- as mix), the transitions and camera moves (the blends 9 .. : drawn as a plain crossfade) and the video FX - counted
-- in <out>.log (⚪179: the transitions were counted as keys). The developer's composer script draws them as well (Python).
-- Returns true when started
local MX_BL = { [1] = "min(255,A+B)", [2] = "max(0,A-B)", [3] = "A*B/255",
  [4] = "if(lt(A,128),A*B*2/255,255-(255-A)*(255-B)*2/255)", [5] = "(255-2*B)*A*A/65025+2*B*A/255",
  [6] = "if(lt(B,128),A*B*2/255,255-(255-A)*(255-B)*2/255)" }
function M.take_ffmpeg_mix(ff, mix, decks, W, H, F, out)
  local g = {}                                        -- shared memory index -> place in a record
  for i, k in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 16, 20, 21, 22, 23, 26, 27, 28 }) do g[k] = i + 1 end
  local recs = mix.recs
  local N = math.ceil(mix.len * F - 0.000001)
  local lines, last, ri = {}, nil, 1
  local fnA, fnB, fkA, fkB, fgA, fgB = nil, nil, 0, 0, 0, 0
  local skip = { key = 0, tr = 0, fxA = 0, fxB = 0, fxMix = 0 }
  local function clamp(v) return math.max(0, math.min(1, v)) end
  for k = 0, N - 1 do
    local t = k / F
    while recs[ri + 1] and recs[ri + 1][1] - mix.pos <= t do ri = ri + 1 end
    local r = recs[ri]
    local function v(i) return r[g[i]] end
    local gA, gB = clamp(v(0)), clamp(v(1))
    if v(7) ~= fnA then if fnA then fkA, fgA = 2, v(8) end; fnA = v(7) end
    if fkA > 0 then gA = clamp(fgA); fkA = fkA - 1 end
    if v(27) ~= fnB then if fnB then fkB, fgB = 2, v(28) end; fnB = v(27) end
    if fkB > 0 then gB = clamp(fgB); fkB = fkB - 1 end
    local mb = math.max(0, math.floor(v(2)))
    local s = gA + gB
    local xf = s > 0.0001 and gB / s or 0.5
    local vis = math.min(1, s)
    local cA = (xf < 0.5 and 1 - 2 * xf or 0) * vis
    local cY = (xf < 0.5 and 2 * xf or 2 - 2 * xf) * vis
    local cB = (xf < 0.5 and 0 or 2 * xf - 1) * vis
    -- (⚪179) the keys (7, 8) and the transitions / camera moves (9 ..) are drawn as a mix: counted where they would
    -- show (the crossfader between the ends), each as what it is
    if mb >= 7 then
      if cY > 0 then if mb >= 9 then skip.tr = skip.tr + 1 else skip.key = skip.key + 1 end end
      mb = 0
    end
    if mb == 0 then cA = cA + cY * 0.5; cB = cB + cY * 0.5; cY = 0 end
    if (cA > 0 or cY > 0) and v(10) >= 1 and v(11) > 0.001 then skip.fxA = skip.fxA + 1 end
    if (cB > 0 or cY > 0) and v(20) >= 1 and v(21) > 0.001 then skip.fxB = skip.fxB + 1 end
    if v(5) >= 1 and v(6) > 0.001 then skip.fxMix = skip.fxMix + 1 end
    local terms = {}
    if cA > 0 then terms[#terms + 1] = string.format("A*%.5f", cA) end
    if cY > 0 then terms[#terms + 1] = string.format("(%s)*%.5f", MX_BL[mb], cY) end
    if cB > 0 then terms[#terms + 1] = string.format("B*%.5f", cB) end
    local expr = #terms > 0 and ("min(255," .. table.concat(terms, "+") .. ")") or "0"
    if expr ~= last then lines[#lines + 1] = { t, expr }; last = expr end
  end
  -- one fixed expression: the frame's time T picks the frame's mix through a balanced tree of if(lt(T, ...))
  local function tree(lo, hi)
    if lo == hi then return lines[lo][2] end
    local mid = (lo + hi + 1) // 2
    return string.format("if(lt(T,%.6f),%s,%s)", lines[mid][1] - 0.5 / F, tree(lo, mid - 1), tree(mid, hi))
  end
  local log = out .. ".log"
  local h = M.open_w(log); if not h then return false end
  h:write(string.format("frames %d; not drawn (frames): luma/chroma key %d, transition / camera move %d, deck A FX %d, deck B FX %d, mix FX %d\n",
    N, skip.key, skip.tr, skip.fxA, skip.fxB, skip.fxMix))
  h:close()
  local function q_(p) return '"' .. p .. '"' end
  local Fr = string.format("%.9f", F)
  local fit = string.format("scale=%d:%d:force_original_aspect_ratio=decrease:flags=bilinear,pad=%d:%d:(ow-iw)/2:(oh-ih)/2,fps=%s,format=gbrp",
    W, H, W, H, Fr)
  local inputs, waits = {}, {}
  for _, tag in ipairs({ "A", "B" }) do
    local d
    for _, x in ipairs(decks) do if (x.deck == 2 and "B" or "A") == tag then d = x end end
    if d and d.mp4 then
      inputs[#inputs + 1] = "-i " .. q_(d.mp4); waits[#waits + 1] = d.mp4 .. ".log"
    else
      inputs[#inputs + 1] = string.format("-f lavfi -i color=black:s=%dx%d:r=%s", W, H, Fr)
    end
  end
  -- the filter graph in a file (the expression is long; -/filter_complex from ffmpeg 7.0, -filter_complex_script before)
  local fcf = out .. ".filter.txt"
  h = M.open_w(fcf); if not h then return false end
  h:write("[0:v]" .. fit .. "[a];[1:v]" .. fit .. "[b];[a][b]blend=all_expr='" .. tree(1, #lines) ..
    "':shortest=1,format=yuv420p[v]")
  h:close()
  local line = q_(ff) .. " -hide_banner -nostdin -loglevel error -y " .. table.concat(inputs, " ") ..
    string.format(" -ss %.6f -t %.6f -i ", mix.offs or 0, mix.len) .. q_(mix.wav) ..
    -- (-filter_complex_script: the older form, before 7.0)
    ((M.FFMPEG_MAJOR or 99) >= 7 and " -/filter_complex " or " -filter_complex_script ") .. q_(fcf) ..
    ' -map "[v]" -map 2:a:0' .. string.format(" -frames:v %d", N) ..
    " -c:v libx264 -crf 14 -pix_fmt yuv420p -c:a aac -b:a 320k " .. q_(out)
  -- ((⚪151) the decks' batches are waited for by their status lines (M.BAT_DONE / BAT_FAILED, from ffmpeg's exit codes),
  -- not by "failed" / "done" anywhere in their logs: ffmpeg's own messages go into those logs too, and a message with
  -- "failed" in it from a deck video that was made gave the mix up)
  if WIN then
    local script = out:gsub("%.mp4$", "") .. "_mix.bat"
    local b = {}
    for i, w in ipairs(waits) do       -- wait for the decks' videos
      b[#b + 1] = ":wait" .. i
      b[#b + 1] = M.bat_esc('findstr /b /c:"' .. M.BAT_FAILED .. '" ' .. q_(w)) .. " > nul 2>&1 && goto fail"
      b[#b + 1] = M.bat_esc('findstr /b /c:"' .. M.BAT_DONE .. '" ' .. q_(w)) .. " > nul 2>&1 || (timeout /t 2 /nobreak > nul & goto wait" .. i .. ")"
    end
    b[#b + 1] = M.bat_esc(line .. " >> " .. q_(log)) .. " 2>&1 || goto fail"
    b[#b + 1] = "(echo.& echo " .. M.BAT_DONE .. ") >> " .. M.bat_esc(q_(log))
    b[#b + 1] = 'del "%~f0" & exit /b 0'
    b[#b + 1] = ":fail"
    b[#b + 1] = "(echo.& echo " .. M.BAT_FAILED .. ") >> " .. M.bat_esc(q_(log))
    if not M.write_bat(script, b) then M.log(M.T("書き込めません: ", "cannot write: ") .. script) return false end
    M.run_bat(script)
  else
    local script = out:gsub("%.mp4$", "") .. "_mix.sh"
    local b = {}
    for _, w in ipairs(waits) do
      b[#b + 1] = "until grep -q -e '^" .. M.BAT_DONE .. "$' -e '^" .. M.BAT_FAILED .. "$' " .. q_(w) .. " 2>/dev/null; do sleep 2; done"
      b[#b + 1] = "grep -q '^" .. M.BAT_FAILED .. "$' " .. q_(w) .. " && { printf '\\n%s\\n' '" .. M.BAT_FAILED .. "' >> " .. q_(log) .. "; exit 1; }"
    end
    b[#b + 1] = line .. " >> " .. q_(log) .. " 2>&1 || { printf '\\n%s\\n' '" .. M.BAT_FAILED .. "' >> " .. q_(log) .. "; exit 1; }"
    b[#b + 1] = "printf '\\n%s\\n' '" .. M.BAT_DONE .. "' >> " .. q_(log)
    b[#b + 1] = 'rm -f "$0"'
    if not M.write_sh(script, b) then M.log(M.T("書き込めません: ", "cannot write: ") .. script) return false end
    M.run_sh(script)
  end
  return true
end

local tk = { on = false, pending = {} }

local function tk_drain(d) ring_drain(d, M.tk_base(d.deck), M.TK_W, M.TK_N) end   -- ((⚪151) ring_drain)
local function mx_drain(mx) ring_drain(mx, M.MX_BASE, M.MX_W, M.MX_N) end

-- the recorded item of a deck (d.deck) or of the mix (d.mix): on its "Rec" track, covering the records (nil until REAPER
-- has put it there)
local function tk_recorded(d)
  local cap = M.take_track(d.mix and "mix" or d.deck)
  if not cap or #d.recs == 0 then return nil end
  local p0 = math.huge
  for _, r in ipairs(d.recs) do p0 = math.min(p0, r[1]) end
  for i = 0, reaper.CountTrackMediaItems(cap) - 1 do
    local it = reaper.GetTrackMediaItem(cap, i)
    local pos, len = reaper.GetMediaItemInfo_Value(it, "D_POSITION"), reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if pos <= p0 + 0.1 and pos + len > p0 then return it end
  end
end

local function tk_build(take)
  local live, live_path = reaper.EnumProjects(-1)
  local fps_proj = reaper.TimeMap_curFrameRate(0)
  local decks, T0 = {}, math.huge
  for _, d in ipairs(take.decks) do
    local it = d.item
    local t = reaper.GetActiveTake(it)
    local src = t and reaper.GetMediaItemTake_Source(t)
    d.pos, d.len = reaper.GetMediaItemInfo_Value(it, "D_POSITION"), reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    d.offs = t and reaper.GetMediaItemTakeInfo_Value(t, "D_STARTOFFS") or 0
    d.wav = src and reaper.GetMediaSourceFileName(src, "") or nil
    -- the sound comes out a little after the head (the grains): the frame goes with the sound
    for _, r in ipairs(d.recs) do r[1] = r[1] + r[3] end
    table.sort(d.recs, function(a, b) return a[1] < b[1] end)
    d.fr, d.F, d.Fs = tk_frames(d, d.pos, d.len, fps_proj)
    d.items = d.fr and tk_items(d.fr, d.F, d.Fs) or {}
    T0 = math.min(T0, d.pos)
    decks[#decks + 1] = d
  end
  local mix = take.mix
  if mix then
    local t = reaper.GetActiveTake(mix.item)
    local src = t and reaper.GetMediaItemTake_Source(t)
    mix.pos, mix.len = reaper.GetMediaItemInfo_Value(mix.item, "D_POSITION"), reaper.GetMediaItemInfo_Value(mix.item, "D_LENGTH")
    mix.offs = t and reaper.GetMediaItemTakeInfo_Value(t, "D_STARTOFFS") or 0
    mix.wav = src and reaper.GetMediaSourceFileName(src, "") or nil
  end
  local name = (live_path and live_path ~= "" and M.stem(live_path) or "untitled") .. "_" .. os.date("%Y%m%d_%H%M%S")
  reaper.RecursiveCreateDirectory(M.TAKE_DIR, 0)
  local path = M.TAKE_DIR .. M.SEP .. name .. ".rpp"
  reaper.Main_OnCommand(40859, 0)                    -- New project tab
  local proj = reaper.EnumProjects(-1)
  local function track(nm)
    reaper.InsertTrackAtIndex(reaper.CountTracks(proj), true)
    local tr = reaper.GetTrack(proj, reaper.CountTracks(proj) - 1)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", nm, true)
    return tr
  end
  local function item(tr, at, len, offs, rate, file, vol)
    local it = reaper.AddMediaItemToTrack(tr)
    local t = reaper.AddTakeToMediaItem(it)
    reaper.SetMediaItemTake_Source(t, reaper.PCM_Source_CreateFromFile(file))
    reaper.SetMediaItemInfo_Value(it, "D_POSITION", at)
    reaper.SetMediaItemInfo_Value(it, "D_LENGTH", len)
    reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
    reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0)      -- (the default 10 ms fades darken one-frame items)
    reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0)
    reaper.SetMediaItemTakeInfo_Value(t, "D_STARTOFFS", offs)
    reaper.SetMediaItemTakeInfo_Value(t, "D_PLAYRATE", rate)
    reaper.SetMediaItemTakeInfo_Value(t, "B_PPITCH", 0)
    if vol then reaper.SetMediaItemTakeInfo_Value(t, "D_VOL", vol) end
    return it
  end
  local summary = {}
  for _, d in ipairs(decks) do
    local tag = d.deck == 2 and "B" or "A"
    local vt = track(tag .. M.T(" 映像", " video"))
    local at = d.pos - T0
    for _, x in ipairs(d.items) do item(vt, at + x[1], x[2], x[3], x[4], x[5], 0) end   -- the video's own sound off
    local st = track(tag .. M.T(" 音", " audio"))
    if d.wav then item(st, at, d.len, d.offs, 1, d.wav) end
    summary[#summary + 1] = string.format("deck %s: %d video items, %.1f s%s", tag, #d.items, d.len,
      d.lost > 0 and string.format(", %d blocks lost", d.lost) or "")
  end
  if mix and mix.wav then item(track(M.T("完成 音", "mix audio")), mix.pos - T0, mix.len, mix.offs, 1, mix.wav) end
  reaper.UpdateArrange()
  -- saving a copy leaves the tab untitled: open the saved file in it (the tab then is that file)
  reaper.Main_SaveProjectEx(proj, path, 0)
  reaper.Main_openProject("noprompt:" .. path)
  reaper.SelectProjectInstance(live)
  -- the recorded items leave the live project (their files stay, the take project uses them)
  reaper.Undo_BeginBlock()
  for _, d in ipairs(decks) do
    if reaper.ValidatePtr2(live, d.item, "MediaItem*") then reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(d.item), d.item) end
  end
  if mix and reaper.ValidatePtr2(live, mix.item, "MediaItem*") then
    reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(mix.item), mix.item)
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(M.T("ReaScratch: Recで録ったものを別のプロジェクトへ", "ReaScratch: move the Rec recording into a new project"), -1)
  -- with ffmpeg: also a frame-exact video file per deck (REAPER's own render can be a frame or two off), made in the
  -- background
  local ff = M.find_ffmpeg()
  local made = {}
  -- the frame-exact videos need ffmpeg 5.1 or later (4.4's concat had no "option" lines: the pictures fell on a 25 fps
  -- grid; checked 2026-10-06 with 4.4.1, 5.1.2, 6.1.1, 7.1.1, 9.0.2)
  local old_ff = ff and (M.FFMPEG_MAJOR or 99) + (M.FFMPEG_MINOR or 0) / 100 < 5.01
  if old_ff then ff = nil end
  for _, d in ipairs(decks) do
    if ff and d.wav then
      local out = M.TAKE_DIR .. M.SEP .. name .. "_" .. (d.deck == 2 and "B" or "A") .. ".mp4"
      local fr, F = tk_frames(d, d.pos, d.len, 0)
      if fr and M.take_ffmpeg(ff, fr, F, d.wav, d.offs, d.len, out) then made[#made + 1] = M.basename(out); d.mp4 = out end
    end
  end
  -- the mix: what the deck mix read, block by block, for a composer that draws the video window again from the decks'
  -- frame-exact videos (<name>_mix.txt)
  local mixfile, h
  if mix and mix.wav and #mix.recs > 0 then
    mixfile = M.TAKE_DIR .. M.SEP .. name .. "_mix.txt"
    h = M.open_w(mixfile)                            -- ((⚪179) not written: no mix file, no _mix.mp4)
    if not h then mixfile = nil end
  end
  if h then
    h:write("#reascratch-mix 1\n")
    -- ((⚪179) the size as the deck mix takes it: the largest picture either deck handed (it was deck A's first)
    local fps, ww, hh = 0, nil, nil
    for _, d in ipairs(decks) do
      h:write(string.format("deck%s\t%s\t%.6f\t%.9f\n", d.deck == 2 and "B" or "A", d.mp4 or "-", d.pos - mix.pos, d.Fs or 0))
      fps = math.max(fps, d.Fs or 0)
      for _, f in ipairs(d.fr or {}) do
        if f and f.w and f.h and f.w * f.h > (ww or 0) * (hh or 0) then ww, hh = f.w, f.h end
      end
    end
    h:write(string.format("fps\t%.9f\n", fps > 0 and fps or 30))
    h:write(string.format("size\t%d\t%d\n", ww or 1280, hh or 720))
    h:write(string.format("audio\t%s\t%.6f\t%.6f\n", mix.wav, mix.offs, mix.len))
    h:write("out\t" .. M.TAKE_DIR .. M.SEP .. name .. "_mix.mp4\n")
    for _, r in ipairs(mix.recs) do
      local v = { string.format("%.6f", r[1] - mix.pos) }
      for i = 2, #r do v[#v + 1] = string.format("%.6g", r[i]) end
      h:write("rec\t" .. table.concat(v, "\t") .. "\n")
    end
    h:close()
    -- the mix with ffmpeg (crossfader and blends) at the deck mix's size: at most 1280 x 720, (⚪169) at least as large
    -- as fits in 960 x 720 (reascratch_deck_mix.eel; the developer's composer script the same)
    if ff then
      local w, hh0 = ww or 1280, hh or 720
      local sc = math.min(1, 1280 / math.max(1, w), 720 / math.max(1, hh0))
      if sc >= 1 then sc = math.max(1, math.min(960 / math.max(1, w), 720 / math.max(1, hh0))) end
      local W, H = math.max(2, math.floor(w * sc * 0.5) * 2), math.max(2, math.floor(hh0 * sc * 0.5) * 2)
      if M.take_ffmpeg_mix(ff, mix, decks, W, H, fps > 0 and fps or 30, M.TAKE_DIR .. M.SEP .. name .. "_mix.mp4") then
        made[#made + 1] = name .. "_mix.mp4"
      end
    end
    -- a composer to run on it (REAPER's ExtState ReaScratch / composer, e.g. a Python script run with --wait): started
    -- in the background; it waits for the decks' videos and writes <name>_mix_full.mp4 (with the video FX and keys)
    local comp = reaper.GetExtState("ReaScratch", "composer")
    if comp ~= "" and ff then                       -- (it draws from the decks' videos)
      local ffa = ff and (' --ffmpeg "' .. ff .. '"') or ""   -- (REAPER's PATH may not have it)
      if WIN then reaper.ExecProcess('cmd.exe /C "' .. comp .. ffa .. ' "' .. mixfile .. '""', -2)   -- ((⚪151) minimized, see M.run_bat)
      else reaper.ExecProcess('/bin/sh -c \'' .. comp .. ffa .. ' "' .. mixfile .. '"\'', -1) end
      made[#made + 1] = name .. "_mix_full.mp4 (python)"
    end
  end
  _G.REASCRATCH_TAKE_LAST = { path = path, decks = decks, mix = mix, mixfile = mixfile }   -- (tests read it)
  return "filmed: " .. path .. " (" .. table.concat(summary, "; ") .. ")" ..
    (#made > 0 and ("; ffmpeg is writing " .. table.concat(made, ", ") .. " (frame-exact, a few minutes)") or "") ..
    (old_ff and string.format("; ffmpeg %d.%d is too old for the frame-exact videos (5.1 or later)", M.FFMPEG_MAJOR, M.FFMPEG_MINOR or 0) or "")
end

-- called on every cycle of the video sync script (recording = REAPER records now). Returns a line to show when it has
-- made a take project
function M.take_tick(recording)
  if recording and not tk.on then
    -- a take still waiting for its recorded item (the files were deleted in REAPER's dialog): given up, so that this
    -- one is not queued behind it
    tk.pending = {}
    local decks = {}
    for deck = 1, 2 do
      if M.find_engine(deck) and M.take_track(deck) then
        local b = M.tk_base(deck)
        decks[#decks + 1] = { deck = deck, read = reaper.gmem_read(b), recs = {}, lost = 0 }
        reaper.gmem_write(b + 1, 1)
      end
    end
    if #decks > 0 then
      tk.on, tk.decks, tk.mix = true, decks, nil
      -- the mix (deck A's JSFX records what the deck mix reads)
      if M.find_engine(1) and M.take_track("mix") then
        tk.mix = { mix = true, read = reaper.gmem_read(M.MX_BASE), recs = {}, lost = 0 }
        reaper.gmem_write(M.MX_BASE + 1, 1)
      end
    end
  elseif tk.on then
    for _, d in ipairs(tk.decks) do tk_drain(d) end
    if tk.mix then mx_drain(tk.mix) end
    if not recording then
      tk.on = false
      for _, d in ipairs(tk.decks) do reaper.gmem_write(M.tk_base(d.deck) + 1, 0) end
      reaper.gmem_write(M.MX_BASE + 1, 0)
      tk.pending[#tk.pending + 1] = { decks = tk.decks, mix = tk.mix, until_t = reaper.time_precise() + 600 }
    end
  end
  if recording or #tk.pending == 0 then return end
  local take = tk.pending[1]
  local ready = true
  for _, d in ipairs(take.decks) do
    d.item = d.item and reaper.ValidatePtr2(0, d.item, "MediaItem*") and d.item or tk_recorded(d)
    if not d.item then ready = false end
  end
  if take.mix then
    local m = take.mix
    m.item = m.item and reaper.ValidatePtr2(0, m.item, "MediaItem*") and m.item or tk_recorded(m)
    if not m.item then ready = false end
  end
  if not ready then
    -- ((⚪151) one deck's recorded item missing (its file deleted in REAPER's dialog, its track removed) kept the whole take
    -- waiting 600 s and then dropped it without a word: TK_PART s after the first one is there, the take is made of the
    -- ones found; nothing found by until_t: given up, said so)
    local now, found, miss = reaper.time_precise(), {}, {}
    for _, d in ipairs(take.decks) do
      if d.item then found[#found + 1] = d else miss[#miss + 1] = d.deck == 2 and "B" or "A" end
    end
    if take.mix and not take.mix.item then miss[#miss + 1] = "Mix" end
    if #found > 0 then
      take.part_t = take.part_t or now + M.TK_PART
      if now < take.part_t then return end
      table.remove(tk.pending, 1)
      take.decks = found
      if take.mix and not take.mix.item then take.mix = nil end
      M.log(string.format(M.T("Rec: %sの録った項目が見つからないので、見つかった分だけでテイクを作ります",
        "Rec: the recorded item of %s was not found; the take is made of the ones found"), table.concat(miss, ", ")))
      return tk_build(take)
    end
    if now > take.until_t then
      table.remove(tk.pending, 1)
      M.log(M.T("Rec: 録った項目が見つからないので、テイクを作りませんでした（録音ファイルを消したか、Recトラックを外しましたか？）",
        "Rec: no recorded item was found, so no take was made (were the recorded files deleted, or the Rec tracks removed?)"))
    end
    return
  end
  table.remove(tk.pending, 1)
  return tk_build(take)
end

-- (⚪109, user's report 2026-10-09: the APC40 mkII did not light and some knobs acted oddly) the lights' MIDI output that
-- goes with a deck's Preset: the enabled output whose name has the preset's controller in it ("APC40 mkII deck 1" ->
-- "APC40" and "mkII", "Reloop Buddy deck 2" -> "Reloop" and "Buddy", as whole words; none: nil, nothing changes). With the
-- Buddy and the APC40 both connected, setup had taken the first DJ controller among the outputs (the Buddy) for both
-- decks, so the APC40 never got its Ableton Live mode (its knobs then send other numbers) nor its lights.
-- Returns the output's index and name, or nil (Custom, a test preset, no such output). (⚪110) input = true: the same for
-- the enabled MIDI inputs (the two controllers' tracks take each one's own input)
-- ((⚪151) every word of the preset's controller counts, not only the first two: "Reloop Mixon 4" took a Mixon 8 Pro, and
-- the Hercules DJControl ... / Numark Mixtrack ... presets each other's ports. A preset's name -> groups of words, each
-- { alternatives..., opt = true/false }: "200/300" and "DDJ-SB3 / SX" = either; words in brackets ("(MK2)", "(Pro)") and
-- the maker's name (the ports often lack it: "DJControl Compact", "Mixtrack Pro 3") may be missing; "DJ Control" is read
-- as "DJControl". A port fits when it has every other group as a whole word; the more words it has, the better. A port
-- that another preset of the JSFX's list fits better is not taken ("Mixtrack Pro 3" for "Numark Mixtrack").
local PO_MAKERS = { akai = true, reloop = true, hercules = true, numark = true, behringer = true, denon = true, gemini = true,
  ion = true, korg = true, pioneer = true, alphatheta = true, ni = true }
local function po_norm(s)
  s = (s or ""):lower():gsub("dj control", "djcontrol")
  return s
end
local function po_groups(preset_name)
  local base = (preset_name or ""):gsub("^[^%w]+", ""):gsub("%s+[Dd]eck%s+%d.*$", ""):gsub("%s*%([Mm][Ii][Dd][Ii] .*$", "")
  base = po_norm(base)
  local groups, alt_next, in_br = {}, false, false
  for w in base:gmatch("%S+") do
    if w == "/" then
      alt_next = #groups > 0
    else
      local opt = in_br or w:sub(1, 1) == "("          -- (in brackets, also over several words: "(NI S2/S3/S4)")
      in_br = opt and not w:find(")", 1, true)
      w = w:gsub("[%(%)]", "")
      local g = alt_next and groups[#groups] or { opt = opt or PO_MAKERS[w] == true }
      for a in w:gmatch("[^/]+") do g[#g + 1] = a end
      if not alt_next and #g > 0 then groups[#groups + 1] = g end
      alt_next = false
    end
  end
  return groups
end
-- how well a port's name fits a preset's groups: nil = not at all, else the number of groups found
local function po_score(groups, port)
  local n, score, req = po_norm(port), 0, 0
  for _, g in ipairs(groups) do
    local hit = false
    for _, a in ipairs(g) do
      if n:find("%f[%w]" .. a:gsub("%p", "%%%0") .. "%f[%W]") then hit = true break end
    end
    if hit then score = score + 1 elseif not g.opt then return nil end
    if not g.opt then req = req + 1 end
  end
  if req == 0 then return nil end   -- (only optional words: a maker's name alone fits every port of the maker)
  return score
end
-- the Preset list of the JSFX (its slider1), read once
local po_list
local function po_presets()
  if po_list then return po_list end
  po_list = {}
  local f = io.open(M.RES .. M.SEP .. "Effects" .. M.SEP .. M.JSFX:gsub("/", M.SEP), "r")
  if not f then return po_list end
  for line in f:lines() do
    local l = line:match("^slider1:[^{]*{(.*)}")
    if l then
      for nm in l:gmatch("[^,]+") do po_list[#po_list + 1] = po_groups(nm) end
      break
    end
  end
  f:close()
  return po_list
end
function M.preset_output(preset_name, input)
  local groups = po_groups(preset_name)
  local first = groups[1] and groups[1][1]
  if not first or first == "custom" or first == "flx4" or first == "none" then return nil end
  local best_i, best_name, best_s
  for i = 0, (input and reaper.GetNumMIDIInputs() or reaper.GetNumMIDIOutputs()) - 1 do
    local ok, name
    if input then ok, name = reaper.GetMIDIInputName(i, "") else ok, name = reaper.GetMIDIOutputName(i, "") end
    local s = ok and po_score(groups, name or "")
    if s and (not best_s or s > best_s) then
      local better = false   -- another preset fits this port with more words
      for _, g in ipairs(po_presets()) do
        local s2 = po_score(g, name)
        if s2 and s2 > s then better = true break end
      end
      if not better then best_i, best_name, best_s = i, name, s end
    end
  end
  return best_i, best_name
end

-- (⚪110, user's request 2026-10-09) two controllers at once (the Reloop Buddy and the APC40 mkII): a deck's "2nd controller"
-- (JSFX slider 230) = the second one's preset. Its MIDI must reach the JSFX on MIDI bus 2 and its lights leave on bus 2:
--   "controller 2 in": input = the second controller, armed (monitor only), sends its MIDI to each engine on bus 2
--   each engine: input = the first controller only (all inputs would bring the second one in on bus 1 as well), its own
--     MIDI hardware output off; sends bus 1 to "lights 1" and bus 2 to "lights 2" (both taken to bus 1 there)
--   "lights 1" / "lights 2": MIDI hardware output = the first / second controller (by the presets' names)
-- (A send's MIDI buses are in I_MIDIFLAGS: >> 14 = the source bus, >> 22 = the destination bus, 0 = all / as it was;
-- I_MIDI_SRCBUS / DSTBUS did nothing in REAPER 7.80. Tried in an isolated REAPER.)
-- With no deck's 2nd controller set, the three tracks go and the engines are back to all inputs and their Preset's
-- output. engines = { { track, fx }, ... }. Returns changed, on (the two controllers' routing in use), what it did
M.TRACK_CX_IN, M.TRACK_LIGHTS = "controller 2 in", { "lights 1", "lights 2" }

-- (⚪117, user's report 2026-10-10: the controllers' lights stayed on after REAPER was closed) every light off: to each
-- MIDI hardware output the engines and the "lights" tracks send to, a note on at 0 for every note of the 16 channels and
-- CC 0 for every CC (the APC40's knob rings: their ring style 0 = off). Returns the number of outputs
-- (⚪124, user's report 2026-10-10: still on after REAPER closed) the MIDI hardware outputs the decks' lights go to
-- (device number = its name). REAPER runs a script's atexit on quit after the project is closed (no tracks) and with its
-- MIDI outputs closed (nothing sent arrives; both measured in the isolated REAPER): the video sync keeps this list from
-- while it runs, writes their names to LIGHTS_FILE (lights_write) and starts reascratch_lights_off.ps1 when it starts
-- (lights_watch): that waits for REAPER to close, then opens those outputs itself and sends every light off
function M.lights_devs()
  local trs, outs = {}, {}
  trs[1] = M.find_engine(1); trs[2] = M.find_engine(2)
  trs[3] = M.track_by_name(M.TRACK_LIGHTS[1]); trs[4] = M.track_by_name(M.TRACK_LIGHTS[2])
  for i = 1, 4 do
    local tr = trs[i]
    if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") then
      local o = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_MIDIHWOUT"))
      if o >= 0 and not outs[o >> 5] then
        local ok, nm = reaper.GetMIDIOutputName(o >> 5, "")
        outs[o >> 5] = ok and nm or ""
      end
    end
  end
  return outs
end
M.LIGHTS_PS1 = (debug.getinfo(1, "S").source:match("^@(.*[\\/])") or "") .. "reascratch_lights_off.ps1"
M.LIGHTS_FILE = reaper.GetResourcePath() .. "/ReaScratch_lights_outputs.txt"
local lights_last
function M.lights_write(outs)
  local names = {}
  for _, nm in pairs(outs) do if nm ~= "" then names[#names + 1] = nm end end
  table.sort(names)
  local txt = table.concat(names, "\n")
  if txt == lights_last then return end
  local h = io.open(M.LIGHTS_FILE, "w")
  if h then h:write(txt) h:close() lights_last = txt end
end
function M.lights_watch()
  if not reaper.ExecProcess or not reaper.GetOS():find("Win") then return end
  local ps = (os.getenv("SystemRoot") or "C:\\Windows") .. "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"   -- (PATH may not have it)
  reaper.ExecProcess('"' .. ps .. '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' .. M.LIGHTS_PS1 ..
                     '" -NamesFile "' .. M.LIGHTS_FILE .. '"', -2)
end
function M.lights_off(outs)
  local n = 0
  outs = outs or M.lights_devs()
  if not reaper.SendMIDIMessageToHardware then return 0 end
  for dev in pairs(outs) do
    for ch = 0, 15 do
      for k = 0, 127 do
        reaper.SendMIDIMessageToHardware(dev, string.char(0x90 | ch, k, 0))
        reaper.SendMIDIMessageToHardware(dev, string.char(0xB0 | ch, k, 0))
      end
    end
    n = n + 1
  end
  return n
end
local function cx_set(tr, key, v)
  if math.floor(reaper.GetMediaTrackInfo_Value(tr, key) + 0.5) ~= v then reaper.SetMediaTrackInfo_Value(tr, key, v) return true end
  return false
end
local function cx_send(a, b, flags)   -- a MIDI-only send from a to b with these buses; true = something changed
  local ch, s = false, nil
  for i = 0, reaper.GetTrackNumSends(a, 0) - 1 do
    if reaper.GetTrackSendInfo_Value(a, 0, i, "P_DESTTRACK") == b then s = i break end
  end
  if not s then s = reaper.CreateTrackSend(a, b); ch = true end
  if reaper.GetTrackSendInfo_Value(a, 0, s, "I_SRCCHAN") ~= -1 then reaper.SetTrackSendInfo_Value(a, 0, s, "I_SRCCHAN", -1); ch = true end
  if math.floor(reaper.GetTrackSendInfo_Value(a, 0, s, "I_MIDIFLAGS")) ~= flags then reaper.SetTrackSendInfo_Value(a, 0, s, "I_MIDIFLAGS", flags); ch = true end
  return ch
end
function M.cx_apply(engines)
  local list, p1, p2 = {}, nil, nil
  for _, ef in ipairs(engines) do
    local e, f = ef[1], ef[2]
    if e and f and reaper.ValidatePtr2(0, e, "MediaTrack*") then
      list[#list + 1] = e
      local pi, pp = M.param_index_cached(e, f, "2nd controller"), M.param_index_cached(e, f, "Preset")   -- ((⚪151) every 2 s)
      local v = pi and reaper.TrackFX_GetParam(e, f, pi) or 0
      if v >= 0.5 and pp and not p2 then
        p2 = select(2, reaper.TrackFX_FormatParamValue(e, f, pp, v, ""))
        p1 = select(2, reaper.TrackFX_GetFormattedParamValue(e, f, pp, ""))
      end
    end
  end
  local cx, l1, l2 = M.track_by_name(M.TRACK_CX_IN), M.track_by_name(M.TRACK_LIGHTS[1]), M.track_by_name(M.TRACK_LIGHTS[2])
  if not p2 then
    if not (cx or l1 or l2) then return false, false end
    for _, tr in ipairs({ cx, l1, l2 }) do if tr then reaper.DeleteTrack(tr) end end
    for _, e in ipairs(list) do
      cx_set(e, "I_RECINPUT", 4096 + (63 << 5))   -- all MIDI inputs, as setup makes it
      local f = M.engine_fx(e)
      local pp = f and M.param_index(e, f, "Preset")
      local o = pp and M.preset_output(select(2, reaper.TrackFX_GetFormattedParamValue(e, f, pp, "")))
      if o then cx_set(e, "I_MIDIHWOUT", o << 5) end
    end
    return true, false, "two controllers: off (the tracks removed, the engines back to all MIDI inputs)"
  end
  local in1, in1n = M.preset_output(p1, true)
  local in2, in2n = M.preset_output(p2, true)
  local o1, o1n = M.preset_output(p1)
  local o2, o2n = M.preset_output(p2)
  local ch = false
  if not cx then cx = M.ensure_track(M.TRACK_CX_IN); ch = true end
  if not l1 then l1 = M.ensure_track(M.TRACK_LIGHTS[1]); ch = true end
  if not l2 then l2 = M.ensure_track(M.TRACK_LIGHTS[2]); ch = true end
  for _, tr in ipairs({ cx, l1, l2 }) do   -- armed, monitor only (as the engines: they pass MIDI on while stopped too)
    ch = cx_set(tr, "B_MAINSEND", 0) or ch
    ch = cx_set(tr, "I_RECMODE", 2) or ch
    ch = cx_set(tr, "I_RECARM", 1) or ch
    ch = cx_set(tr, "I_RECMON", 1) or ch
  end
  ch = cx_set(cx, "I_RECINPUT", in2 and (4096 + (in2 << 5)) or -1) or ch
  ch = cx_set(l1, "I_RECINPUT", -1) or ch
  ch = cx_set(l2, "I_RECINPUT", -1) or ch
  ch = cx_set(l1, "I_MIDIHWOUT", o1 and (o1 << 5) or -1) or ch
  ch = cx_set(l2, "I_MIDIHWOUT", o2 and (o2 << 5) or -1) or ch
  -- ((⚪151, user's choice) the first controller's input not found from its preset (Custom, FLX4, a port named otherwise):
  -- all MIDI inputs, as without a 2nd controller, not -1 (no MIDI reached the decks at all); said in the message
  local all_in = 4096 + (63 << 5)
  for _, e in ipairs(list) do
    ch = cx_set(e, "I_RECINPUT", in1 and (4096 + (in1 << 5)) or all_in) or ch
    ch = cx_set(e, "I_MIDIHWOUT", -1) or ch
    ch = cx_send(cx, e, 2 << 22) or ch
    ch = cx_send(e, l1, (1 << 14) | (1 << 22)) or ch
    ch = cx_send(e, l2, (2 << 14) | (1 << 22)) or ch
  end
  return ch, true, ("two controllers: 1 = %s (in %s, lights %s), 2 = %s (in %s, lights %s)"):format(p1, in1n or "all MIDI inputs",
    o1n or "none", p2, in2n or "none", o2n or "none") ..
    (in1 and "" or M.T("（1台目の入力を機種名から決められないので、デッキは全MIDI入力にしました。2台目の信号もデッキに直接届いて二重になることがあります）",
      " (the first controller's input could not be told from its preset, so the decks take all MIDI inputs: the second controller's MIDI may also reach them directly, twice)")),
    not in1   -- ((⚪151) a 4th value: the message warns (the video sync shows it also when started quietly)
end


-- (⚪111, user's request 2026-10-09) REAPER's tempo follows a deck: a deck whose "REAPER tempo" is "REAPER follows this deck"
-- (the JSFX writes it into gmem [113] / [114]) and that plays ([106] / [107]) with a BPM ([14] / [24] = its BPM at the tempo)
-- and is alive (its block counter [15] / [25] moves) leads; two of them: the louder on the crossfader ([0] / [1]). Its BPM
-- goes into the project's tempo (SetCurrentBPM) when it differs by more than 0.005. The first time it does so in a project
-- whose timebase is not time, the kit's tracks are set to time (their items must not move with the tempo: the slot videos
-- are found at their places). st = the caller's table (counters seen). Returns the BPM written, or nil
function M.tempo_lead(st)
  local lead, lg
  for d = 0, 1 do
    local blk = reaper.gmem_read(d == 0 and 15 or 25)
    local alive = st["blk" .. d] ~= nil and blk ~= st["blk" .. d]
    st["blk" .. d] = blk
    local bpm = reaper.gmem_read(d == 0 and 14 or 24)
    if alive and reaper.gmem_read(113 + d) == 2 and reaper.gmem_read(106 + d) ~= 0 and bpm > 0 then
      local g = reaper.gmem_read(d)
      if not lead or g > lg then lead, lg = bpm, g end
    end
  end
  if not lead or math.abs(lead - reaper.Master_GetTempo()) <= 0.005 then return nil end
  if not st.timebase_done then
    st.timebase_done = true
    if reaper.GetSetProjectInfo(0, "PROJECT_TIMEBASE", 0, false) ~= 0 then
      for _, n in ipairs({ M.TRACK_VIDEO, M.TRACK_AUDIO, M.TRACK_ENGINE, M.TRACK_VIDEO_B, M.TRACK_AUDIO_B, M.TRACK_ENGINE_B,
          M.TRACK_VIEW_B, M.TRACK_TAKE[1], M.TRACK_TAKE[2], M.TRACK_TAKE_MIX, M.TRACK_CUE, M.TRACK_PREVIEW }) do
        local tr = M.track_by_name(n)
        if tr and reaper.GetMediaTrackInfo_Value(tr, "C_BEATATTACHMODE") ~= 0 then reaper.SetMediaTrackInfo_Value(tr, "C_BEATATTACHMODE", 0) end
      end
    end
  end
  M.pf_set_bpm(lead)   -- ((⚪178) the performance regions stay with their lanes)
  return lead
end

return M

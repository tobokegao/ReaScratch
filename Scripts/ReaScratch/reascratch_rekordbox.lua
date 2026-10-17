-- ReaScratch kit (⚪177): rekordbox's cues, BPM / beat grid and key for the samples. Choose the XML rekordbox exported
-- (rekordbox: File > Export Collection in xml format); it is remembered (ExtState ReaScratch / rekordbox_xml, all
-- projects), and from then on the import script and LOAD take a video's values from it by themselves. This script
-- also puts them into the samples already in both decks' slots: a slot's track is found by the video it was made
-- from (LOAD's record, or the video on the "video" / "video B" track at the slot's place), else by the file name.
-- What a slot gets: hot cues A-H -> 1-8 (a loop: its start), memory cues (up to 32), CUE = the first memory cue,
-- BPM and grid (the first TEMPO; the grid on a bar's first beat), key. (⚪180) Traktor's collection.nml and VirtualDJ's
-- database.xml are read the same way (reascratch_lib.lua, rb_load: told apart by their contents). Test hooks (REASCRATCH_TEST): xml = path
-- (no dialog), quiet = true.
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local T = L.TEST or {}

local old = reaper.GetExtState("ReaScratch", L.RB_KEY)
local xml = T.xml
if not xml then
  local ok, p = reaper.GetUserFileNameForRead(old, L.T("DJソフトの曲データを選ぶ（rekordbox: ファイル→コレクションをxml形式でエクスポートしたXML、Traktor: collection.nml、VirtualDJ: database.xml）",
    "Choose the DJ software's track data (rekordbox: the XML of File > Export Collection in xml format, Traktor: collection.nml, VirtualDJ: database.xml)"), "")
  if not ok then return end
  xml = p
end
reaper.SetExtState("ReaScratch", L.RB_KEY, xml, true)

local found, missing, lines, why_late = 0, 0, {}, false
for deck = 1, 2 do
  local tr, fx = L.find_engine(deck)
  if tr and fx then
    local names = L.engine_samples(tr)
    local vtr = L.track_by_name(deck == 2 and L.TRACK_VIDEO_B or L.TRACK_VIDEO)
    for slot = 1, L.SLOTS do
      local wav = names[slot]
      if wav and wav ~= "" and not wav:find("(empty)", 1, true) then
        local rname = L.stem(wav)
        local paths = {}
        local _, src = reaper.GetSetMediaTrackInfo_String(tr, L.src_key(rname), "", false)   -- LOAD's record (⚪173)
        if src ~= "" then paths[#paths + 1] = src end
        local it = vtr and L.slot_item(vtr, slot)
        local tk = it and reaper.GetActiveTake(it)
        local srcv = tk and reaper.GetMediaItemTake_Source(tk)
        if srcv then paths[#paths + 1] = reaper.GetMediaSourceFileName(srcv, "") end
        paths[#paths + 1] = L.SAMPLE_DIR .. L.SEP .. wav
        local rb, why = L.rb_find(paths)
        if rb then
          if not L.rb_send(tr, fx, slot, rb) then why_late = true end
          found = found + 1
          lines[#lines + 1] = string.format("%s %d: %s", deck == 2 and "B" or "A", slot, L.rb_summary(rb))
        else
          missing = missing + 1
          lines[#lines + 1] = string.format("%s %d: %s - %s", deck == 2 and "B" or "A", slot, rname, why)
          if why:find("^rekordbox XML ") then break end
        end
      end
    end
  end
end
if why_late then lines[#lines + 1] = L.T("（デッキが答えませんでした: scratch engineトラックの録音待機とモニターがオンか確かめてください）",
  "(a deck did not answer: check that the scratch engine track is armed with monitoring on)") end
for _, s in ipairs(lines) do L.log(s) end
if not T.quiet then
  L.msgbox(string.format(L.T("DJソフトの曲データ: %s\n\n見つかった素材: %d、見つからなかった素材: %d\n\n%s\n\nこれからは動画の取り込みとLOADのときにも、このファイルから読み込みます。",
    "DJ software's track data: %s\n\nSamples found: %d, not found: %d\n\n%s\n\nFrom now on, importing a video and LOAD also take their values from this file."),
    xml, found, missing, table.concat(lines, "\n")), "ReaScratch rekordbox", 0)
end

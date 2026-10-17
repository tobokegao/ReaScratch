-- ReaScratch kit (⚪181): writes the samples in both decks' slots to a file: hot cues 1-8, memory cues, CUE, BPM and
-- beat grid (a tempo map as tempo changes), key.
--   rekordbox XML: for rekordbox's "rekordbox xml" import (Preferences > View > Layout: rekordbox xml on; then the
--     tracks under "rekordbox xml" in the tree > right-click > Import To Collection). Only a new file is written:
--     nothing of rekordbox's own is touched. The CUE is added as a memory cue (rekordbox loads a track there)
--   ReaScratch track data: the same form + the CUE as it is, the loudness (auto gain) and the beat map as it is. Read
--     back with reascratch_rekordbox.lua (choose the file), like a rekordbox XML
-- A track's file: the video it was made from (LOAD's record, else the video at the slot's place; a converted
-- "_mjpeg" video gives way to the original beside it), else the sample's WAV. The WAV holds the whole sound of the video
-- from its start, so the times are the video's.
-- The file goes where the save dialog says (with the js_ReaScriptAPI extension), else to
-- <REAPER resource folder>/Data/ReaScratch_export/. Test hooks (REASCRATCH_TEST): export_kind = "rekordbox" /
-- "reascratch", file = path (no dialog), quiet = true; the result in REASCRATCH_TEST.result
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local T = L.TEST or {}

local kind = T.export_kind
if not kind then
  local a = reaper.ShowMessageBox(L.T("書き出す形を選んでください。\n\nはい: rekordbox用のXML（rekordboxの「rekordbox xml」から読み込む）\nいいえ: ReaScratch専用の曲データ（ReaScratchで読み直す。CUE・音量・テンポの変化もそのまま）",
    "Choose what to write.\n\nYes: an XML for rekordbox (read it through rekordbox's \"rekordbox xml\")\nNo: ReaScratch track data (read back into ReaScratch; keeps the CUE, loudness and tempo changes as they are)"),
    "ReaScratch export", 3)
  if a == 6 then kind = "rekordbox" elseif a == 7 then kind = "reascratch" else return end
end

local tracks, lines, late, seen = {}, {}, false, {}
for deck = 1, 2 do
  local tr, fx = L.find_engine(deck)
  if tr and fx then
    local names = L.engine_samples(tr)
    for slot = 1, L.SLOTS do
      local wav = names[slot]
      if wav and wav ~= "" and not wav:find("(empty)", 1, true) then
        local v = L.slot_values(tr, fx, slot)
        if not v then
          late = true
        elseif v.has then
          local paths = L.slot_paths(tr, deck, slot, wav)
          local path = paths[#paths]
          for _, p in ipairs(paths) do if reaper.file_exists(p) then path = p break end end
          v.path, v.name = path, L.stem(path)
          -- the same file in two slots / both decks: one track (the first; the file has one set of cues)
          local key = L.rb_norm(path)
          if seen[key] then goto next_slot end
          seen[key] = true
          tracks[#tracks + 1] = v
          local nh = 0
          for k = 1, 8 do if v.hot[k] then nh = nh + 1 end end
          lines[#lines + 1] = string.format("%s %d: %s (%d hot cues, %d memory cues, %s)", deck == 2 and "B" or "A", slot,
            path, nh, #v.mem, v.bpm > 0 and string.format("%.2f BPM", v.bpm) or "no BPM")
        end
      end
      ::next_slot::
    end
  end
end
if late then lines[#lines + 1] = L.T("（デッキが答えませんでした: scratch engineトラックの録音待機とモニターがオンか確かめてください）",
  "(a deck did not answer: check that the scratch engine track is armed with monitoring on)") end
if #tracks == 0 then
  if T.result ~= nil or T.quiet then T.result = { n = 0 } return end
  L.msgbox(L.T("書き出す素材がありません（デッキのスロットに素材を入れてください）。", "No samples to write (load samples into the decks' slots).")
    .. (late and "\n\n" .. lines[#lines] or ""), "ReaScratch export", 0)
  return
end

local file = T.file
if not file then
  local dir = reaper.GetResourcePath() .. L.SEP .. "Data" .. L.SEP .. "ReaScratch_export"
  local name = (kind == "rekordbox" and "rekordbox_" or "reascratch_tracks_") .. os.date("%Y%m%d_%H%M%S") .. ".xml"
  if reaper.JS_Dialog_BrowseForSaveFile then
    local rv, f = reaper.JS_Dialog_BrowseForSaveFile(L.T("書き出す場所", "Where to write"), dir, name, "XML (*.xml)\0*.xml\0\0")
    if rv ~= 1 then return end
    file = f:match("%.[xX][mM][lL]$") and f or f .. ".xml"
  else
    reaper.RecursiveCreateDirectory(dir, 0)
    file = dir .. L.SEP .. name
  end
end
local ok = L.rb_write(file, tracks, kind)
for _, s in ipairs(lines) do L.log(s) end
L.log((ok and "export: " or "export failed: ") .. file)
T.result = { n = #tracks, file = file, ok = ok }
if T.quiet then return end
if not ok then
  L.msgbox(L.T("書き込めませんでした: ", "Could not write: ") .. file, "ReaScratch export", 0)
  return
end
L.msgbox(string.format(L.T("%d個の素材を書き出しました:\n%s\n\n%s\n\n%s", "Wrote %d samples:\n%s\n\n%s\n\n%s"), #tracks, file,
  table.concat(lines, "\n"),
  kind == "rekordbox" and L.T("rekordboxで: 環境設定→表示→レイアウトで「rekordbox xml」をオン、詳細→データベースで「rekordbox xml」にこのファイルを指定 → 左の「rekordbox xml」の曲を選んで右クリック→「コレクションにインポート」。",
    "In rekordbox: Preferences > View > Layout: turn on \"rekordbox xml\"; Advanced > Database: set this file as \"rekordbox xml\" -> select the tracks under \"rekordbox xml\" on the left, right-click > Import To Collection.")
  or L.T("ReaScratchで読み直すには、reascratch_rekordbox.luaでこのファイルを選びます。", "To read it back into ReaScratch, choose this file in reascratch_rekordbox.lua.")),
  "ReaScratch export", 0)

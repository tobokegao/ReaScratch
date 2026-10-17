-- ReaScratch kit: which decks "play the performance" plays (⚪178): both (the default), deck A only, or deck B only. A deck
-- left out follows only the hands while the other plays its lanes. Kept in REAPER's ExtState (perf_play_A / perf_play_B),
-- read by the video sync on each cycle (gmem [401] / [402]); "play the performance" itself is turned on / off by
-- reascratch_perf_play.lua. A menu at the mouse.
-- Test hooks (REASCRATCH_TEST): pick = 1 (both) / 2 (A) / 3 (B) instead of the menu.
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local T = L.TEST or {}

local a = reaper.GetExtState("ReaScratch", "perf_play_A") ~= "off"
local b = reaper.GetExtState("ReaScratch", "perf_play_B") ~= "off"
local pick = T.pick
if not pick then
  local items = {
    (a and b and "!" or "") .. L.T("両方のデッキ", "Both decks"),
    (a and not b and "!" or "") .. L.T("デッキAだけ", "Deck A only"),
    (b and not a and "!" or "") .. L.T("デッキBだけ", "Deck B only") }
  gfx.init("", 0, 0, 0, reaper.GetMousePosition())
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  pick = gfx.showmenu(table.concat(items, "|"))
  gfx.quit()
end
if pick and pick >= 1 and pick <= 3 then
  reaper.SetExtState("ReaScratch", "perf_play_A", (pick == 3) and "off" or "on", true)
  reaper.SetExtState("ReaScratch", "perf_play_B", (pick == 2) and "off" or "on", true)
  L.perf_play_gmem()
  L.log(L.T("演奏の再生で鳴らすデッキ: ", "the decks the performance plays: ") .. ({ L.T("両方", "both"), "A", "B" })[pick])
end

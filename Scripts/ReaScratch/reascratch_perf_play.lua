-- ReaScratch kit: turn "play the performance" on / off (⚪178). While it is on, REAPER's own play plays the performance
-- lanes back (what was recorded on REAPER's timeline: PLAY / pause, the head and the hand, slot, tempo, key): the video
-- sync then lets REAPER play (it no longer stops it, nor puts the edit cursor on the deck's head), and each deck follows
-- its lanes while REAPER plays. A hand on a deck wins until its lane changes again (the head: while held; let go, it
-- goes back to the lane). Off (the default): the decks play only by hand, and REAPER's play is stopped as before.
-- The setting is kept (REAPER's ExtState) and shows as the on / off state of this action on a toolbar button.
-- Test hooks (REASCRATCH_TEST): on = true / false instead of toggling, quiet = true (no message box).
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local T = L.TEST or {}

local on = not L.perf_play_on()
if T.on ~= nil then on = T.on end
reaper.SetExtState("ReaScratch", "perf_play", on and "on" or "off", true)
L.perf_play_gmem()   -- (at once; the video sync writes it again on each cycle)
local _, _, sec, cmd = reaper.get_action_context()
L.set_toggle(sec, cmd, on)   -- (the video sync sets it again when REAPER starts)
-- ((⚪178 stage 6) REAPER stopping at the project's end would stop the performance zone at once: said when turned on)
if on and L.stop_at_end_on() then
  L.log(L.T(L.STOP_AT_END_MSG[1], L.STOP_AT_END_MSG[2]))
  if not T.quiet then L.msgbox(L.T(L.STOP_AT_END_MSG[1], L.STOP_AT_END_MSG[2]), L.T("ReaScratch: 演奏の再生", "ReaScratch: play the performance"), 0) end
end
if not T.quiet then
  L.msgbox(on and L.T("演奏の再生モード: オン。REAPER の再生で、演奏の列（再生/停止・頭・スロット・テンポ・キー）をデッキが鳴らします。動画同期は REAPER の再生を止めません。",
                     "Play the performance: on. REAPER's play now plays the performance lanes (play / pause, the head, slot, tempo, key) on the decks. The video sync no longer stops REAPER's play.")
              or L.T("演奏の再生モード: オフ。デッキは手元の操作だけで動き、REAPER の再生は今までどおり止めます。",
                     "Play the performance: off. The decks follow only your hands, and REAPER's play is stopped as before."),
           L.T("ReaScratch: 演奏の再生", "ReaScratch: play the performance"), 0)
end

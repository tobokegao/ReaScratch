-- ReaScratch kit: turn "record the hand into the lanes" off / on (⚪50). While it is on (the default) and REAPER records,
-- the video sync script records the hand on each deck's record and the crossfader, and when the recording stops puts them
-- on the decks' "Envelope scratch" / "Envelope fader" lanes as automation items (reascratch_lib.lua rec_tick). Turn it off
-- when you record a performance that the lanes already play and do not want new items on them. The setting is kept
-- (REAPER's ExtState) and shows as the on / off state of this action on a toolbar button.
-- Test hooks (REASCRATCH_TEST): on = true / false instead of toggling, quiet = true (no message box).
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local T = L.TEST or {}

local on = not L.rec_lanes_on()
if T.on ~= nil then on = T.on end
reaper.SetExtState("ReaScratch", "rec_lanes", on and "on" or "off", true)
local _, _, sec, cmd = reaper.get_action_context()
L.set_toggle(sec, cmd, on)   -- ((⚪151) L.set_toggle; the video sync sets it again when REAPER starts)
if not T.quiet then
  L.msgbox(on and L.T("録音中のスクラッチとクロスフェーダーを、録音を止めたときにエンベロープ（Envelope scratch / Envelope fader）へ書き込みます。",
                     "Scratches and crossfader moves while recording are written into the envelopes (Envelope scratch / Envelope fader) when the recording stops.")
              or L.T("録音してもエンベロープへは書き込みません。", "Recording no longer writes into the envelopes."),
           L.T("ReaScratch: 演奏をエンベロープに記録", "ReaScratch: record the performance into envelopes"), 0)
end

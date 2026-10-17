-- ReaScratch kit: film the decks (⚪14) on / off. On: a track "Rec A" (and "Rec B", and "Rec Mix") records each deck's sound before the
-- crossfader whenever REAPER records. When the recording stops, the video sync script makes a new project from it
-- (Data/ReaScratch_takes/<project>_<date>.rpp, opened in a new tab behind the live project): per deck a video track
-- that cuts the deck's video so each frame is the one the deck showed (the original file when it lies next to the
-- all-keyframe copy), and the recorded sound. Edit / render it like any project. Off: the "Rec" tracks go away.
-- The on / off state shows on a toolbar button. Test hooks (REASCRATCH_TEST): on = true / false, quiet = true.
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local T = L.TEST or {}

local on = not L.take_on()
if T.on ~= nil then on = T.on end
reaper.Undo_BeginBlock()
local n = L.take_prepare(on)
reaper.Undo_EndBlock(on and L.T("ReaScratch: Recトラック（オン）", "ReaScratch: Rec tracks (on)") or L.T("ReaScratch: Recトラック（オフ）", "ReaScratch: Rec tracks (off)"), -1)
local _, _, sec, cmd = reaper.get_action_context()
L.set_toggle(sec, cmd, on and n > 0)   -- ((⚪151) L.set_toggle; the video sync sets it again when REAPER starts)
if not T.quiet then
  if on and n == 0 then
    L.msgbox(L.T("先にreascratch_setup.luaを実行してください（scratch engineトラックが要ります）", "Run reascratch_setup.lua first (it needs the scratch engine track)."), L.T("ReaScratch: Recトラック", "ReaScratch: Rec tracks"), 0)
  else
    L.msgbox(on and L.T("「Rec」トラックを置きました。REAPERで録音すると、デッキごとの音（クロスフェーダーの前）と、完成形の音（混ぜてマスターのエフェクトを通した音）を録ります。\n" ..
                    "録音を止めると、その音と、デッキが映していたコマどおりに元の動画を切り貼りした映像を、" ..
                    "新しいプロジェクト（Data/ReaScratch_takes）にまとめて別のタブで開きます。\n" ..
                    "ffmpegがあれば、デッキごとの動画と、動画の窓どおりの完成形の動画（_mix.mp4）も裏で作ります。",
                    "The \"Rec\" tracks are in place. When you record in REAPER, each deck's sound (before the crossfader) and the final mix (mixed, through the master effects) are recorded.\n" ..
                    "When the recording stops, that sound and a video cut from the original videos frame by frame as the decks showed them " ..
                    "are put together in a new project (Data/ReaScratch_takes) and opened in another tab.\n" ..
                    "With ffmpeg, each deck's video and the final video as in the video window (_mix.mp4) are also made in the background.")
                 or L.T("Recをオフにしました（「Rec」トラックを外しました）。", "Recording the decks is off (the \"Rec\" tracks were removed)."),
             L.T("ReaScratch: Recトラック", "ReaScratch: Rec tracks"), 0)
  end
end

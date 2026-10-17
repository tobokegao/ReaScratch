-- ReaScratch: 動画の窓を開き直す
-- モニターやプロジェクターの電源・抜き差しのあとで動画の窓が止まったときに使う。
-- 全画面だった窓は全画面のまま戻る。窓が閉じていたときは開くだけ。

local SHOW_HIDE = 50125 -- Video: Show/hide Video window

if reaper.GetToggleCommandState(SHOW_HIDE) ~= 1 then
  reaper.Main_OnCommand(SHOW_HIDE, 0)
  return
end

reaper.Main_OnCommand(SHOW_HIDE, 0)
-- 閉じたのが反映されてから開く（同じ瞬間に2回送ると作り直されないことがある）
local t0 = reaper.time_precise()
local function reopen()
  if reaper.time_precise() - t0 < 0.3 then
    reaper.defer(reopen)
    return
  end
  if reaper.GetToggleCommandState(SHOW_HIDE) ~= 1 then
    reaper.Main_OnCommand(SHOW_HIDE, 0)
  end
end
reaper.defer(reopen)

-- ReaScratch kit: keep a scratch pattern you made or changed (⚪38). Select its automation item on a deck's
-- "Envelope scratch" lane and run this; the item's points (and the "Envelope fader" item that starts at the same place,
-- if any) are saved under a name to <REAPER resource folder>/Data/ReaScratch_patterns_user.lua, and reascratch_pattern.lua
-- lists them from then on. The same name in the same group replaces the old one.
-- Test hooks (REASCRATCH_TEST): name, cat.
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local T = L.TEST or {}
local TITLE = L.T("ReaScratch: パターンを保存", "ReaScratch: save pattern")

-- the first selected automation item on a deck's scratch lane
local tr, fx, env, ai
for deck = 1, 2 do
  local t, f = L.find_engine(deck)
  local e = t and L.ev_env(t, f, L.EV_SCRATCH, false)
  if e and not ai then
    for i = 0, reaper.CountAutomationItems(e) - 1 do
      if reaper.GetSetAutomationItemInfo(e, i, "D_UISEL", 0, false) ~= 0 then tr, fx, env, ai = t, f, e, i break end
    end
  end
end
if not ai then
  L.msgbox(L.T("保存するパターンのオートメーションアイテムを、デッキの「Envelope scratch」の列で選んでから実行してください。",
    "Select the pattern's automation item in the deck's \"Envelope scratch\" lane, then run this."), TITLE, 0)
  return
end
local beat, grid, slot = L.deck_time(tr, fx)
if not beat then L.msgbox(L.T("このデッキの素材にBPMがありません。BPMを入れてから保存してください。", "This deck's sample has no BPM. Set the BPM, then save."), TITLE, 0) return end

local pos = reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
local len = reaper.GetSetAutomationItemInfo(env, ai, "D_LENGTH", 0, false)
-- the item's points as heard (playback rate and loops already in their times), in beats from its start, with the swing
-- taken out (⚪39: reascratch_pattern.lua puts it back in where the pattern goes, so it never swings twice)
local sw_s, sw_pair = L.pattern_swing(tr, fx)
if T.swing then sw_s, sw_pair = T.swing, 0.5 end
local function straight(t) return L.swing_unwarp((t - L.slot_start(slot) - grid) / beat, sw_s, sw_pair) end
local function points(e, i)
  local out = {}
  for k = 0, reaper.CountEnvelopePointsEx(e, i) - 1 do
    local _, t, v, shape = reaper.GetEnvelopePointEx(e, i, k)
    if t >= pos - 0.0005 and t <= pos + len + 0.0005 then
      out[#out + 1] = { math.floor((straight(t) - straight(pos)) * 10000 + 0.5) / 10000, math.floor(v * 10000 + 0.5) / 10000, shape == 5 and 1 or 0 }
    end
  end
  -- REAPER does not list a point on the item's very end: the value there, as heard
  local b_end = math.floor((straight(pos + len) - straight(pos)) * 10000 + 0.5) / 10000
  if #out > 0 and out[#out][1] < b_end - 0.0001 then
    local _, v = reaper.Envelope_Evaluate(e, pos + len - 0.000001, 0, 0)
    out[#out + 1] = { b_end, math.floor(v * 10000 + 0.5) / 10000, 0 }
  end
  return out
end
local pat = { pos = points(env, ai), beats = math.floor((straight(pos + len) - straight(pos)) * 1000 + 0.5) / 1000 }
local fenv = L.ev_env(tr, fx, L.EV_FADER, false)
if fenv then
  for i = 0, reaper.CountAutomationItems(fenv) - 1 do
    if math.abs(reaper.GetSetAutomationItemInfo(fenv, i, "D_POSITION", 0, false) - pos) < 0.001 then
      local f = points(fenv, i)
      if #f > 0 then pat.fader = f end
      break
    end
  end
end
if #pat.pos == 0 then L.msgbox(L.T("選んだアイテムに点がありません。", "The selected item has no points."), TITLE, 0) return end

local _, old = reaper.GetSetAutomationItemInfo_String(env, ai, "P_POOL_NAME", "", false)
local name, cat = T.name, T.cat
if not name then
  local ok, csv = reaper.GetUserInputs(TITLE, 2, L.T("名前,グループ（メニューの分類）", "Name,Group (menu section)") .. ",extrawidth=120", (old ~= "" and old or "My pattern") .. ",My patterns")
  if not ok then return end
  name, cat = csv:match("^([^,]*),(.*)$")
end
name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
cat = (cat or ""):gsub("^%s+", ""):gsub("%s+$", "")
if name == "" then L.msgbox(L.T("名前が空です。", "The name is empty."), TITLE, 0) return end
pat.name, pat.cat = name, cat ~= "" and cat or "My patterns"

local mine = {}
for _, p in ipairs(L.load_patterns(HERE)) do
  if p.user and not (p.name == pat.name and p.cat == pat.cat) then mine[#mine + 1] = p end
end
mine[#mine + 1] = pat
if not L.save_user_patterns(mine) then L.msgbox(L.T("保存できませんでした: ", "Could not save: ") .. L.USER_PATTERNS, TITLE, 0) return end
reaper.SetExtState("ReaScratch", "pattern_saved", tostring(reaper.time_precise()), false)   -- ((⚪115) the PATTERN pads read it again)
reaper.GetSetAutomationItemInfo_String(env, ai, "P_POOL_NAME", pat.name, true)
if T.log then T.log(string.format("saved %s / %s: %d pos points, %s fader, %.3f beats", pat.cat, pat.name, #pat.pos, pat.fader and #pat.fader or "no", pat.beats))
else L.msgbox(string.format(L.T("「%s」を保存しました（%s）。reascratch_pattern.luaのメニューに出ます。", "Saved \"%s\" (%s). It is in the reascratch_pattern.lua menu."), pat.name, pat.cat), TITLE, 0) end

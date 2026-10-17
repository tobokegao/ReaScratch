-- ReaScratch kit: show only the envelope lanes you need (2026-10-17, user's request). The engine track carries about 90
-- automatable sliders (the ReaScratch JSFX's lanes and the DJ performance lanes); REAPER's envelope list shows them all.
-- A menu at the mouse shows / hides the lanes by group, on both decks' engine tracks:
--   hand-made scratch (Envelope scratch / fader), the recorded effects (the deck's time), and the performance lanes
--   (REAPER's time) in four groups. A lane that is shown is made when missing; hiding keeps its points (they still play).
-- The menu comes back after each choice; close it to finish. One undo step.
-- Test hooks (REASCRATCH_TEST): picks = { n, ... } instead of the menu (0 ends), menu = function(s) -> n.
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local T = L.TEST or {}

-- perf lanes (L.PF_LANES) by the start of their label; the ones in no group are the effects
local PERF_GROUPS = {
  play = { "Perf transport", "Perf head", "Perf driven", "Perf slot", "Perf tempo", "Perf key", "Perf sync", "Perf pitch play", "Perf pitch mode" },
  mix = { "Perf xfader", "Perf channel volume", "Perf mute", "Perf video opacity", "Perf video blend", "Perf blend key", "Perf picture mute",
          "Perf master level", "Perf blackout", "Perf fader lanes gain" },
  cue = { "Perf loop", "Perf cue position", "Perf hot cue", "Perf memory cue" },
}
local function perf_group(label)
  for g, heads in pairs(PERF_GROUPS) do
    for _, h in ipairs(heads) do if label:sub(1, #h) == h then return g end end
  end
  return "fx"
end

-- groups: on = "engine" (the ReaScratch JSFX) or "perf" (DJ performance lanes); labels
local G = {
  { name = L.T("手打ちスクラッチ（Envelope scratch / fader）", "Hand-made scratch (Envelope scratch / fader)"), on = "engine",
    labels = { "Envelope scratch", "Envelope fader" } },
  { name = L.T("録音したエフェクト（素材の時間）", "Recorded effects (the sample's time)"), on = "engine", labels = {} },
  { name = L.T("演奏: 再生・素材・テンポ", "Performance: play, sample, tempo"), on = "perf", key = "play", labels = {} },
  { name = L.T("演奏: クロスフェーダー・音量・映像の切り替え", "Performance: crossfader, volume, picture"), on = "perf", key = "mix", labels = {} },
  { name = L.T("演奏: ループ・キュー", "Performance: loops, cues"), on = "perf", key = "cue", labels = {} },
  { name = L.T("演奏: エフェクト", "Performance: effects"), on = "perf", key = "fx", labels = {} },
}
for _, l in ipairs(L.LV) do table.insert(G[2].labels, l.label) end
for _, l in ipairs(L.PF_LANES) do
  local k = perf_group(l.label)
  for _, g in ipairs(G) do if g.key == k then table.insert(g.labels, l.label) end end
end

-- the decks' engine tracks: { tr, engine fx, perf fx }
local decks = {}
for d = 1, 2 do
  local tr, fx = L.find_engine(d)
  if tr then decks[#decks + 1] = { tr = tr, engine = fx, perf = L.perf_fx(tr) } end
end
if #decks == 0 then
  L.msgbox(L.T("ReaScratchのデッキが見つかりません。先にSETUPを実行してください。", "No ReaScratch deck found. Run SETUP first."))
  return
end

local function lanes(g)   -- every (track, fx, param) of a group
  local out = {}
  for _, d in ipairs(decks) do
    local fx = g.on == "engine" and d.engine or d.perf
    if fx then
      for _, label in ipairs(g.labels) do
        local p = L.param_index(d.tr, fx, label)
        if p then out[#out + 1] = { tr = d.tr, fx = fx, p = p } end
      end
    end
  end
  return out
end

-- the VIS line of an envelope's chunk ("VIS 1 1 1": shown, in its own lane)
local function visible(env)
  if not env then return false end
  local _, ch = reaper.GetEnvelopeStateChunk(env, "", false)
  return ch:match("\nVIS 1 ") ~= nil
end
local function set_visible(env, on)
  local _, ch = reaper.GetEnvelopeStateChunk(env, "", false)
  local v = on and "1" or "0"
  local new, n = ch:gsub("\nVIS %S+ (%S+) (%S+)", "\nVIS " .. v .. " %1 %2", 1)
  if n == 0 then new = ch:gsub("\n", "\nVIS " .. v .. " 1 1\n", 1) end
  if new ~= ch then reaper.SetEnvelopeStateChunk(env, new, false) end
end
local function has_points(env)   -- (a lane REAPER made has one point of its own: that one does not count)
  return env and (reaper.CountEnvelopePoints(env) > 1 or reaper.CountAutomationItems(env) > 0)
end

local function group_shown(g)
  local ls = lanes(g)
  if #ls == 0 then return false end
  for _, l in ipairs(ls) do
    if not visible(reaper.GetFXEnvelope(l.tr, l.fx, l.p, false)) then return false end
  end
  return true
end
local function show_group(g, on)
  for _, l in ipairs(lanes(g)) do
    local env = reaper.GetFXEnvelope(l.tr, l.fx, l.p, on)   -- shown: made when missing
    if env then set_visible(env, on) end
  end
end
local function each_lane(f)
  for _, g in ipairs(G) do for _, l in ipairs(lanes(g)) do f(reaper.GetFXEnvelope(l.tr, l.fx, l.p, false)) end end
end

reaper.Undo_BeginBlock()
local picks = T.picks and { table.unpack(T.picks) }
while true do
  local items = {}
  for _, g in ipairs(G) do items[#items + 1] = (group_shown(g) and "!" or "") .. g.name end
  items[#items + 1] = ""   -- a line (not counted by showmenu)
  items[#items + 1] = L.T("点のある列だけ出す", "Show only the lanes with points")
  items[#items + 1] = L.T("ReaScratchの列を全部隠す（点は残る）", "Hide all ReaScratch lanes (points kept)")
  local menu = "#" .. L.T("出すエンベロープの列（両デッキ）", "Envelope lanes to show (both decks)") .. "||" .. table.concat(items, "|")
  local r
  if picks then r = table.remove(picks, 1) or 0
  elseif T.menu then r = T.menu(menu)
  else
    local mx, my = reaper.GetMousePosition()
    gfx.init("ReaScratch", 1, 1, 0, mx, my)
    gfx.x, gfx.y = 0, 0
    r = gfx.showmenu(menu)
    gfx.quit()
  end
  local i = r - 1   -- 1 = the greyed title
  if i < 1 then break end
  if i <= #G then
    show_group(G[i], not group_shown(G[i]))
  elseif i == #G + 1 then
    each_lane(function(env) if env then set_visible(env, has_points(env)) end end)
  elseif i == #G + 2 then
    each_lane(function(env) if env then set_visible(env, false) end end)
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end
reaper.Undo_EndBlock(L.T("ReaScratch: エンベロープの列の表示", "ReaScratch: Show/hide envelope lanes"), -1)

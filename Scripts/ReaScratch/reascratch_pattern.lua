-- ReaScratch kit: put a scratch pattern on a deck (⚪38). Pick the deck (when there are two) and a pattern from the
-- menu; it goes in as automation items on the deck's "Envelope scratch" lane (and "Envelope fader" when the pattern
-- moves the fader), at the deck's read head snapped to the nearest beat of its grid. The lanes sit where the deck's
-- sample sits on the timeline, so a pattern belongs to that place of the sample: when the deck plays through it, the
-- pattern scratches from there (the video sync script hands the lanes to the JSFX; REAPER's own transport is not used).
-- Move, copy, stretch or edit the items as any automation item; reascratch_pattern_save.lua keeps one as your own.
-- (⚪115, user's request 2026-10-10: easier to pick) the menu starts with the pattern put last ("Again"), your own patterns
-- (Data/ReaScratch_patterns_user.lua) carry a star, and a submenu picks where it snaps (nearest beat as before, next
-- beat = never before the head, nearest half beat, next bar); the last pattern and the snap are kept (ExtState).
-- Another submenu puts a pattern on a pad of the PATTERN pad mode (pick the pad, then the pattern; the JSFX plays it).
-- Test hooks (REASCRATCH_TEST): deck = 1 / 2, pattern = name, at = timeline position (s) instead of the head,
-- snap = 1..4 (as the menu) with the head, menu = function(menu string) returning the item number in place of the click.
local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")
local T = L.TEST or {}

local trA, fxA = L.find_engine(1)
local trB, fxB = L.find_engine(2)
if not trA then
  L.msgbox(L.T("ReaScratchのデッキが見つかりません。先にreascratch_setup.luaを実行してください。", "No ReaScratch deck found. Run reascratch_setup.lua first."), L.T("ReaScratch: パターン", "ReaScratch: pattern"), 0)
  return
end
local deck = T.deck or 1
if not T.deck and trB then
  deck = L.choose(L.T("どちらのデッキに置きますか？", "Which deck should it go on?"), { L.T("デッキA", "Deck A"), L.T("デッキB", "Deck B") })
  if deck == 0 then return end
end
local tr, fx = trA, fxA
if deck == 2 then tr, fx = trB, fxB end

local pats = L.load_patterns(HERE)
local SNAPS = { L.T("一番近い拍", "Nearest beat"), L.T("次の拍（再生位置より前にしない）", "Next beat (never before the head)"),
                L.T("一番近い半拍", "Nearest half beat"), L.T("次の小節", "Next bar") }
local snap = T.snap or tonumber(reaper.GetExtState("ReaScratch", "pattern_snap")) or 1
if snap < 1 or snap > #SNAPS then snap = 1 end
local last = reaper.GetExtState("ReaScratch", "pattern_last")
local pick, pad = nil, T.pad                         -- pad: assigning to that pad (1-8) instead of placing
if T.pattern then
  for _, p in ipairs(pats) do if p.name == T.pattern then pick = p end end
else
  while true do
    -- the menu: one submenu per group, in the order they first appear
    local groups, order = {}, {}
    for _, p in ipairs(pats) do
      local c = p.cat or "Other"
      if not groups[c] then groups[c] = {}; order[#order + 1] = c end
      table.insert(groups[c], p)
    end
    local items, list = {}, {}
    -- ((⚪151) a name starting with # ! > < was read by showmenu as its mark (greyed, checked, a submenu): a space before it)
    local function safe(s) s = s:gsub("|", "/"); return s:find("^[#!<>]") and " " .. s or s end
    local function lab(p) return (p.user and "★ " or "") .. safe(p.name) .. "  (" .. p.beats .. (p.beats == 1 and " beat)" or " beats)") end
    -- first: the one put last, then the groups, then where it snaps and the pads
    for _, p in ipairs(pats) do
      if not pad and p.name == last then items[#items + 1] = L.T("もう一度: ", "Again: ") .. lab(p); list[#list + 1] = p; items[#items + 1] = "" break end   -- ("" = a line: not counted by showmenu)
    end
    for _, c in ipairs(order) do
      local g = groups[c]
      for i, p in ipairs(g) do
        local label = lab(p)
        if i == #g then label = "<" .. label end           -- the group's last item closes it (also when it is the only one)
        if i == 1 then label = ">" .. safe(c) .. "|" .. label end
        items[#items + 1] = label
        list[#list + 1] = p
      end
    end
    items[#items + 1] = ""
    for k, nm in ipairs(SNAPS) do
      local label = (k == snap and "!" or "") .. nm
      if k == 1 then label = ">" .. L.T("置く位置: ", "Snap: ") .. SNAPS[snap] .. "|" .. label end
      if k == #SNAPS then label = "<" .. label end
      items[#items + 1] = label; list[#list + 1] = { snap = k }
    end
    local names = L.pad_patterns()
    for k = 1, 8 do
      local label = string.format(L.T("パッド%d: %s", "Pad %d: %s"), k, (names[k]:gsub("|", "/")))   -- ((⚪151) | splits the menu)
      if k == 1 then label = ">" .. L.T("PATTERNのパッドに割り当てる", "Put on a PATTERN pad") .. "|" .. label end
      if k == 8 then label = "<" .. label end
      items[#items + 1] = label; list[#list + 1] = { pad = k }
    end
    local mx, my = reaper.GetMousePosition()
    gfx.init("ReaScratch", 1, 1, 0, mx, my)
    gfx.x, gfx.y = 0, 0
    local title = pad and string.format(L.T("パッド%dに割り当てるパターン", "Pattern for pad %d"), pad)
                  or string.format(L.T("デッキ%sに置くパターン", "Pattern for deck %s"), deck == 2 and "B" or "A")
    local menu = "#" .. title .. "||" .. table.concat(items, "|")
    local r
    if T.menu then r = T.menu(menu) else r = gfx.showmenu(menu) end   -- (test: T.menu gets the menu, returns what showmenu would)
    gfx.quit()
    pick = r > 1 and list[r - 1] or nil
    if pick and pick.snap then                           -- a new snap: kept, and the menu again
      snap = pick.snap; reaper.SetExtState("ReaScratch", "pattern_snap", tostring(snap), true)
      pick = nil
    elseif pick and pick.pad then                        -- a pad: the menu again, for its pattern
      pad = pick.pad; pick = nil
    else
      break
    end
  end
end
if not pick then return end
if pad then                                          -- (⚪115) on a PATTERN pad: the video sync script writes it for the JSFX
  L.pad_set(pad, pick.name)
  if T.log then T.log(string.format("pad %d = %s", pad, pick.name)) end
  return
end
reaper.SetExtState("ReaScratch", "pattern_last", pick.name, true)

local beat, grid, slot, head = L.deck_time(tr, fx)
if not beat then
  L.msgbox(L.T("このデッキの素材にBPMがありません。JSFXの画面の「bpm」か、setupの「Beat」でBPMを入れてから置いてください（パターンの長さは拍で決まります）。",
    "This deck's sample has no BPM. Set it with \"bpm\" on the JSFX screen or \"Beat\" on the setup page first (a pattern's length is in beats)."), L.T("ReaScratch: パターン", "ReaScratch: pattern"), 0)
  return
end
local at = T.at
if not at then
  local x = (head - grid) / beat                       -- the head in beats of the grid
  local b = snap == 2 and math.ceil(x - 0.0001) or snap == 3 and math.floor(x * 2 + 0.5) / 2 or
            snap == 4 and math.ceil(x / 4 - 0.0001) * 4 or math.floor(x + 0.5)
  at = L.slot_start(slot) + math.max(0, grid + b * beat)
end

-- swing (⚪39): each point's time goes through the swing of the deck / the project grid, counted from the deck's beat
-- grid, so the 16ths of a pattern land on the music's swung 16ths
local sw_s, sw_pair, sw_from = L.pattern_swing(tr, fx)
if T.swing then sw_s, sw_pair, sw_from = T.swing, 0.5, "test" end
local b0 = (at - L.slot_start(slot) - grid) / beat     -- the item's start in beats of the deck's grid
local function when(b) return L.slot_start(slot) + grid + L.swing_warp(b0 + b, sw_s, sw_pair) * beat end

-- one automation item on a lane, the pattern's points in it (smooth = REAPER's bezier, else straight lines)
local function put(label, pts, rest)
  local env = L.ev_lane(tr, fx, label, rest)
  if not env then return end
  local q = {}
  for _, p in ipairs(pts) do q[#q + 1] = { when(p[1]), p[2], p[3] == 1 and 5 or 0 } end
  local ai = L.ev_item(env, at, when(pick.beats) - at, q, pick.name)
  for i = 0, reaper.CountAutomationItems(env) - 1 do reaper.GetSetAutomationItemInfo(env, i, "D_UISEL", i == ai and 1 or 0, true) end
end

reaper.Undo_BeginBlock()
put(L.EV_SCRATCH, pick.pos, L.EV_OFF)
if pick.fader then put(L.EV_FADER, pick.fader, 1) end
reaper.UpdateArrange()
reaper.Undo_EndBlock(string.format(L.T("ReaScratch: パターン「%s」を置く", "ReaScratch: insert pattern \"%s\""), pick.name), -1)
if T.log then T.log(string.format("pattern %s deck %d at %.3f beat %.4f swing %.3f (%s)", pick.name, deck, at, beat, sw_s, sw_from)) end

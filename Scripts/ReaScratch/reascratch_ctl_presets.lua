-- ReaScratch kit: the controller presets made on the setup page's Learn tab (⚪68). The JSFX cannot write files, so it
-- puts the text of one deck into the shared memory and this writes it; it also reads the saved presets back into the
-- shared memory for the JSFX's "user" menu.
-- Run from reascratch_video_sync.lua (its tick calls tick()). Files: Data/ReaScratch_controllers/<name>.reascratch-preset,
-- one per controller, a [deck 1] / [deck 2] section each (saving deck 2 keeps the deck 1 section of the file).
-- Shared memory (ReaScratch_video; the JSFX: WZG):
--   6000000 save requests (counter; the JSFX adds 1 after filling the rest), 6000001 the controller's deck (1 / 2),
--   6000002 name length, 6000010.. name (character codes), 6000099 text length, 6000100.. the deck's text (codes)
--   6000003 requests done (counter), 6000004 result (1 = saved, -1 = failed), 6000005 message length, 6095000.. message
--   (up to 200; at 6000006 it ran over alive, the name and the text, ⚪129)
--   6000009 alive (counts up every tick: the JSFX knows this script runs)
--   6100000 list version (counts up when it changed), 6100001 entries (up to LIST_MAX); entry k at 6100016 + 512 k:
--     [0] deck, [1] name length, [2..49] name, [50] pairs, [51..] slider number, value, ...

local L = ...
local M = {}

M.DIR = L.RES .. L.SEP .. "Data" .. L.SEP .. "ReaScratch_controllers"
M.EXT = ".reascratch-preset"
local G = 6000000
local GL = 6100000
local LIST_MAX = 32
local NAME_MAX = 48
local PAIRS_MAX = 230          -- (the Learn list WZ_CTL; 51 + 2 x 230 = 511 of the 512 an entry has, ⚪94)

local seen          -- the save counter handled (nil = not read yet: an old request is not done again)
local alive = 0
local list_next = 0
local list_sig = nil

local function gstr(base, n)
  local t = {}
  for i = 0, math.floor(n + 0.5) - 1 do
    local c = math.floor(reaper.gmem_read(base + i) + 0.5)
    if c > 0 and c < 256 then t[#t + 1] = string.char(c) end
  end
  return table.concat(t)
end

local function gput(base, s, max)
  local n = math.min(#s, max or #s)
  for i = 1, n do reaper.gmem_write(base + i - 1, s:byte(i)) end
  return n
end

-- a file name from the controller's name (letters, digits, space, - _ . ( ) only)
function M.file_name(name)
  local s = name:gsub("[^%w%-_%. %(%)]", "_"):gsub("^[%s%.]+", ""):gsub("[%s%.]+$", "")
  if s == "" then s = "controller" end
  return s .. M.EXT
end

-- a file split into its head (lines before the first section) and its sections (deck number -> text)
local function split(text)
  local head, secs, cur = {}, {}, nil
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    local d = line:match("^%[deck (%d)%]")
    if d then cur = tonumber(d); secs[cur] = { line }
    elseif cur then secs[cur][#secs[cur] + 1] = line
    else head[#head + 1] = line end
  end
  return head, secs
end

local read_file = L.read_file

-- write deck `deck`'s text (it starts with its "[deck n]" line) into the controller's file
function M.save(name, deck, text)
  reaper.RecursiveCreateDirectory(M.DIR, 0)
  local path = M.DIR .. L.SEP .. M.file_name(name)
  local _, secs = split(read_file(path) or "")
  local _, mine = split(text)
  secs[deck] = mine[deck] or { "[deck " .. deck .. "]" }
  local out = {
    "# ReaScratch controller preset, made on the setup page's Learn tab",
    "# Send this file to the ReaScratch author to make it a built-in preset.",
    "name = " .. name,
    "saved = " .. os.date("%Y-%m-%d %H:%M"),
    "",
  }
  for d = 1, 2 do
    if secs[d] then
      while #secs[d] > 1 and secs[d][#secs[d]] == "" do secs[d][#secs[d]] = nil end
      for _, l in ipairs(secs[d]) do out[#out + 1] = l end
      out[#out + 1] = ""
    end
  end
  local f = io.open(path, "wb")
  if not f then return nil, "cannot write Data/ReaScratch_controllers/" .. M.file_name(name) end
  f:write(table.concat(out, "\n"))
  f:close()
  return path
end

-- every saved preset: { name =, deck =, pairs = { {slider, value}, ... } }, by name then deck
function M.list()
  local r = {}
  local i = 0
  while true do
    local fn = reaper.EnumerateFiles(M.DIR, i)
    if not fn then break end
    i = i + 1
    if fn:sub(-#M.EXT):lower() == M.EXT then
      local text = read_file(M.DIR .. L.SEP .. fn)
      if text then
        local head, secs = split(text)
        local name = fn:sub(1, -#M.EXT - 1)
        for _, l in ipairs(head) do
          local v = l:match("^name%s*=%s*(.-)%s*$")
          if v and v ~= "" then name = v end
        end
        for d = 1, 2 do
          if secs[d] then
            local pairs_ = {}
            for _, l in ipairs(secs[d]) do
              local s, v = l:match("^slider(%d+)%s*=%s*(%-?[%d%.]+)")
              if s and #pairs_ < PAIRS_MAX then pairs_[#pairs_ + 1] = { tonumber(s), tonumber(v) } end
            end
            if #pairs_ > 0 then r[#r + 1] = { name = name, deck = d, pairs = pairs_ } end
          end
        end
      end
    end
  end
  table.sort(r, function(a, b) if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end return a.deck < b.deck end)
  return r
end

local function publish()
  local r = M.list()
  local sig = {}
  for _, e in ipairs(r) do
    local p = {}
    for _, kv in ipairs(e.pairs) do p[#p + 1] = kv[1] .. "=" .. kv[2] end
    sig[#sig + 1] = e.name .. "/" .. e.deck .. ":" .. table.concat(p, ",")
  end
  sig = table.concat(sig, ";")
  if sig == list_sig then return end
  list_sig = sig
  local n = math.min(#r, LIST_MAX)
  for k = 1, n do
    local e, b = r[k], GL + 16 + 512 * (k - 1)
    reaper.gmem_write(b, e.deck)
    reaper.gmem_write(b + 1, gput(b + 2, e.name, NAME_MAX))
    reaper.gmem_write(b + 50, #e.pairs)
    for j, kv in ipairs(e.pairs) do
      reaper.gmem_write(b + 49 + 2 * j, kv[1])
      reaper.gmem_write(b + 50 + 2 * j, kv[2])
    end
  end
  reaper.gmem_write(GL + 1, n)
  reaper.gmem_write(GL, reaper.gmem_read(GL) + 1)
end

local function answer(c, ok, msg)
  reaper.gmem_write(G + 5, gput(G + 95000, msg, 200))
  reaper.gmem_write(G + 4, ok and 1 or -1)
  reaper.gmem_write(G + 3, c)
end

function M.tick()
  alive = alive + 1
  reaper.gmem_write(G + 9, alive)
  local c = reaper.gmem_read(G)
  if seen and c > seen then
    local name = gstr(G + 10, reaper.gmem_read(G + 2))
    local deck = math.floor(reaper.gmem_read(G + 1) + 0.5) == 2 and 2 or 1
    local text = gstr(G + 100, reaper.gmem_read(G + 99))
    local path, err = M.save(name, deck, text)
    if path then
      L.log("controller preset saved: " .. path)
      -- (the screen shows the place inside the resource folder: a full path shows the user name on screen recordings)
      answer(c, true, "saved: Data/ReaScratch_controllers/" .. M.file_name(name))
      list_next = 0
    else
      L.log("controller preset: " .. err)
      answer(c, false, err)
    end
  end
  seen = c
  local now = reaper.time_precise()
  if now >= list_next then list_next = now + 3; publish() end
end

return M

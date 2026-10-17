-- ReaScratch kit: the built-in scratch patterns (⚪38), placed by reascratch_pattern.lua as automation items.
-- A pattern: name, cat (menu group), beats (length), pos = record position points, fader = crossfader points (optional;
-- none = open). A point = { beat, value, smooth } : pos value in beats of the sample from where the hand went on
-- (0 = there, 0.5 = half a beat further), fader value 0 (closed) .. 1 (open); smooth 1 = a curve through the point,
-- 0 = a corner (straight lines). Your own patterns (reascratch_pattern_save.lua) go to
-- <REAPER resource folder>/Data/ReaScratch_patterns_user.lua in the same form.
local P = {}
local function add(p) P[#P + 1] = p end

-- the fader closed between a and b (beats), short ramps so it clicks without a pop; rest open
local function cuts(list)
  local f, r = {}, 0.01
  for i, c in ipairs(list) do
    if c[1] <= 0 then f[#f + 1] = { 0, 0, 0 }                      -- closed from the start
    else
      if i == 1 then f[#f + 1] = { 0, 1, 0 } end
      f[#f + 1] = { c[1], 1, 0 }; f[#f + 1] = { c[1] + r, 0, 0 }
    end
    f[#f + 1] = { c[2] - r, 0, 0 }; f[#f + 1] = { c[2], 1, 0 }
  end
  return f
end

add({ name = "Baby", cat = "Basic", beats = 1, pos = { { 0, 0, 1 }, { 0.5, 0.5, 1 }, { 1, 0, 1 } } })
add({ name = "Baby x2", cat = "Basic", beats = 1, pos = { { 0, 0, 1 }, { 0.25, 0.25, 1 }, { 0.5, 0, 1 }, { 0.75, 0.25, 1 }, { 1, 0, 1 } } })
add({ name = "Drag (slow)", cat = "Basic", beats = 2, pos = { { 0, 0, 1 }, { 1.5, 0.5, 1 }, { 2, 0, 1 } } })
add({ name = "Stab", cat = "Basic", beats = 1, pos = { { 0, 0, 0 }, { 0.2, 0.5, 1 }, { 0.5, 0.5, 1 }, { 1, 0, 1 } },
      fader = cuts({ { 0.25, 1 } }) })
add({ name = "Forward", cat = "Basic", beats = 1, pos = { { 0, 0, 1 }, { 0.5, 0.5, 1 }, { 1, 0, 1 } },
      fader = cuts({ { 0.5, 1 } }) })
add({ name = "Backward", cat = "Basic", beats = 1, pos = { { 0, 0, 1 }, { 0.5, 0.5, 1 }, { 1, 0, 1 } },
      fader = cuts({ { 0, 0.5 } }) })
do   -- scribble: small fast wiggles
  local pos = { { 0, 0, 1 } }
  for i = 1, 16 do pos[#pos + 1] = { i / 16, (i % 2 == 1) and 0.06 or 0, 1 } end
  add({ name = "Scribble", cat = "Basic", beats = 1, pos = pos })
end
add({ name = "Chirp", cat = "Chirp", beats = 1, pos = { { 0, 0, 1 }, { 0.5, 0.4, 1 }, { 1, 0, 1 } },
      fader = cuts({ { 0.42, 0.58 }, { 0.92, 1 } }) })
add({ name = "Chirp x2", cat = "Chirp", beats = 1, pos = { { 0, 0, 1 }, { 0.25, 0.25, 1 }, { 0.5, 0, 1 }, { 0.75, 0.25, 1 }, { 1, 0, 1 } },
      fader = cuts({ { 0.2, 0.3 }, { 0.45, 0.55 }, { 0.7, 0.8 }, { 0.95, 1 } }) })
add({ name = "Tear", cat = "Tear", beats = 1, pos = { { 0, 0, 1 }, { 0.4, 0.5, 1 }, { 0.55, 0.25, 1 }, { 0.65, 0.25, 0 }, { 0.95, 0, 1 }, { 1, 0, 0 } } })
add({ name = "Tear (3 steps)", cat = "Tear", beats = 1, pos = { { 0, 0, 1 }, { 0.3, 0.45, 1 }, { 0.42, 0.3, 1 }, { 0.5, 0.3, 0 }, { 0.62, 0.15, 1 }, { 0.7, 0.15, 0 }, { 0.85, 0, 1 }, { 1, 0, 0 } } })
add({ name = "Flare (1 click)", cat = "Flare", beats = 1, pos = { { 0, 0, 1 }, { 0.5, 0.5, 1 }, { 1, 0, 1 } },
      fader = cuts({ { 0.23, 0.28 }, { 0.73, 0.78 } }) })
add({ name = "Flare (2 clicks)", cat = "Flare", beats = 1, pos = { { 0, 0, 1 }, { 0.5, 0.5, 1 }, { 1, 0, 1 } },
      fader = cuts({ { 0.15, 0.2 }, { 0.32, 0.37 }, { 0.65, 0.7 }, { 0.82, 0.87 } }) })
add({ name = "Crab", cat = "Flare", beats = 1, pos = { { 0, 0, 1 }, { 0.5, 0.5, 1 }, { 1, 0, 1 } },
      fader = cuts({ { 0.06, 0.1 }, { 0.16, 0.2 }, { 0.26, 0.3 }, { 0.36, 0.4 }, { 0.56, 0.6 }, { 0.66, 0.7 }, { 0.76, 0.8 }, { 0.86, 0.9 } }) })
do   -- transformer: a slow drag, the fader on the 16ths
  local c = {}
  for i = 0, 15 do if i % 2 == 1 then c[#c + 1] = { i / 8, (i + 1) / 8 } end end
  add({ name = "Transformer", cat = "Transform", beats = 2, pos = { { 0, 0, 1 }, { 1, 0.75, 1 }, { 2, 0, 1 } }, fader = cuts(c) })
end
add({ name = "Hold (freeze 1 beat)", cat = "Stutter", beats = 1,   -- ((⚪115) with the freezes; it was alone in "Other")
    pos = { { 0, 0, 0 }, { 1, 0, 0 } } })
-- freeze and stutter (⚪45): a freeze keeps the grain where the hand went on; a stutter plays the first `step` beats at
-- 1x and jumps back, `n` times, with a short fader cut over each jump (the jump itself would be a fast rewind)
add({ name = "Freeze (2 beats)", cat = "Stutter", beats = 2, pos = { { 0, 0, 0 }, { 2, 0, 0 } } })
local function stutter(name, step, n)
  local pos, c = {}, {}
  for i = 0, n - 1 do
    local t = i * step
    pos[#pos + 1] = { t, 0, 0 }
    pos[#pos + 1] = { t + step - 0.002, step - 0.002, 0 }
    if i > 0 then c[#c + 1] = { t - 0.02, t + 0.02 } end
  end
  pos[#pos + 1] = { n * step, step, 0 }
  add({ name = name, cat = "Stutter", beats = n * step, pos = pos, fader = cuts(c) })
end
stutter("Stutter 16th", 0.25, 4)
stutter("Stutter 8th", 0.5, 4)
stutter("Stutter 32nd roll", 0.125, 8)
stutter("Stutter 8th (1 beat)", 0.5, 2)
return P

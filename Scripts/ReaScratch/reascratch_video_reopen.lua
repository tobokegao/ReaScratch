-- ReaScratch: reopen the video window
-- Use it when the video window has frozen after a monitor or projector was turned off/on or unplugged/replugged.
-- A full-screen window comes back full screen. When the window was closed, this only opens it.

local SHOW_HIDE = 50125 -- Video: Show/hide Video window

if reaper.GetToggleCommandState(SHOW_HIDE) ~= 1 then
  reaper.Main_OnCommand(SHOW_HIDE, 0)
  return
end

reaper.Main_OnCommand(SHOW_HIDE, 0)
-- open it only after the close has taken effect (two toggles at the same moment may not rebuild the window)
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

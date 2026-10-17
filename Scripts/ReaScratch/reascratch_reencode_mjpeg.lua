-- ReaScratch kit: re-encode the selected video item(s) to all-keyframe AVI/MJPEG and swap the item's source
-- to the new file. Long-GOP H.264 seeks slowly when scratching; MJPEG decodes any frame directly.
-- Encoder: ffmpeg when there is one (frame-exact copy of the source; looked for next to this script, in
-- REAPER's UserPlugins, on PATH and in the Homebrew folders), otherwise REAPER's own renderer (no FFmpeg
-- needed; verified without FFmpeg DLLs on REAPER 7.80 / Windows, but its frames can be 1-2 frames off).
-- An all-keyframe source is skipped, unless it is taller than MAX_HEIGHT (then it is converted to scale it down).
-- MAX_HEIGHT: this PC's height from the setup (720 / 540 / 360), or the one picked at import (⚪18).
-- Output: next to the source, <name>_mjpeg.avi (overwritten). The item keeps its position / start offset.
-- Nothing selected -> the item of the sample slot in use on the "video" track (else its first item) is used.
-- (deck A's; for deck B's videos select the item on "video B")

local HERE = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local L = dofile(HERE .. "reascratch_lib.lua")

-- larger sources are scaled down (keeps aspect ratio); 0 = keep source size
local MAX_HEIGHT = tonumber(_G.REASCRATCH_REENCODE_HEIGHT) or L.video_height()
local JPEG_QUALITY = 85      -- 1..100

local items = {}
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do items[#items + 1] = reaper.GetSelectedMediaItem(0, i) end
if #items == 0 then
  local video = L.track_by_name(L.TRACK_VIDEO)
  if video and reaper.CountTrackMediaItems(video) > 0 then
    local engine = L.find_engine()
    local slot = engine and select(2, L.engine_samples(engine)) or 1
    items[1] = L.slot_item(video, slot) or reaper.GetTrackMediaItem(video, 0)   -- ((⚪151) L.slot_item)
  end
end
if #items == 0 then L.log("no video item selected") return end

local function even(n) return math.max(2, math.floor(n / 2 + 0.5) * 2) end

-- REAPER's own renderer. Returns false when the user cancelled the size question (stop the whole script).
local function render_with_reaper(item, take, src, path, dir, name)
  local w, h, fps = L.video_info(path)
  local defaults = string.format("%d,%d,%.3f", w or 1280, h or 720, fps or 30)
  if L.TEST and L.TEST.dims then
    defaults = L.TEST.dims
  elseif not (w and h and fps) then
    local ok, ans = reaper.GetUserInputs(L.T("ReaScratch: 動画の大きさ", "ReaScratch: video size"), 3, L.T("幅 (px),高さ (px),フレームレート", "Width (px),Height (px),Frame rate"), defaults)
    if not ok then return false end
    defaults = ans
  end
  local sw, sh, sfps = defaults:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*([%d%.]+)")
  w, h, fps = tonumber(sw), tonumber(sh), tonumber(sfps)
  if not (w and h and fps) then L.log("bad size: " .. defaults) return false end
  if MAX_HEIGHT > 0 and h > MAX_HEIGHT then
    w = even(w * MAX_HEIGHT / h); h = MAX_HEIGHT
  end
  w, h = even(w), even(h)
  L.log(string.format("re-encoding with REAPER's renderer: %s -> %s_mjpeg.avi (%dx%d %.3f fps, q%d)",
    L.basename(path), L.stem(path), w, h, fps, JPEG_QUALITY))
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  -- render the whole source, not just the item's visible part: temporarily stretch the item to the full file
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local srclen = reaper.GetMediaSourceLength(src)
  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", srclen)
  L.render_selected_items(dir, name, L.cfg_avi_mjpeg(w, h, fps, JPEG_QUALITY))
  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", offs)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
  return true
end

for _, item in ipairs(items) do
  local take = reaper.GetActiveTake(item)
  local src = take and reaper.GetMediaItemTake_Source(take)
  -- ((⚪151) a take whose source is a SECTION (a part of the file, reversed ...) or another wrapper was skipped without a
  -- word: the file under it (GetMediaSourceParent) is converted; the swapped take then plays the whole file, as an item
  -- of the kit does. Not a video: said so)
  local wrapped = false
  while src and reaper.GetMediaSourceType(src, "") ~= "VIDEO" and reaper.GetMediaSourceParent(src) do
    src, wrapped = reaper.GetMediaSourceParent(src), true
  end
  if take and not (src and reaper.GetMediaSourceType(src, "") == "VIDEO") then
    L.log("skip (not a video: " .. (src and reaper.GetMediaSourceType(src, "") or "no source") .. "): " .. reaper.GetTakeName(take))
  end
  if wrapped and src and reaper.GetMediaSourceType(src, "") == "VIDEO" then
    L.log("the take's source is a part of the file (section / reverse): the whole file is converted, the take then plays it as it is")
  end
  local path = src and reaper.GetMediaSourceFileName(src, "") or ""
  local already, why = nil, ""
  if src and reaper.GetMediaSourceType(src, "") == "VIDEO" then already, why = L.keyframe_info(path) end
  -- all-keyframe but taller than MAX_HEIGHT: converted anyway, to scale it down (a 1080p60 video was too heavy, 2026-10-04)
  local _, vh = L.video_info(path)
  if already and MAX_HEIGHT > 0 and vh and vh > MAX_HEIGHT then already = false end
  if already then L.log("skip (already all-keyframe: " .. why .. "): " .. L.basename(path)) end
  -- an earlier conversion is left alone, unless it is taller than the height now asked for (720p -> 360p)
  local small_mjpeg = path:find("_mjpeg%.avi$") and not (MAX_HEIGHT > 0 and vh and vh > MAX_HEIGHT)
  if src and reaper.GetMediaSourceType(src, "") == "VIDEO" and not already and not small_mjpeg then
    local dir, name = L.dirname(path), L.stem(path) .. "_mjpeg"
    local out = dir .. L.SEP .. name .. ".avi"
    local t0 = reaper.time_precise()
    -- an older <name>_mjpeg.avi is replaced: otherwise REAPER asks, and "Increment filenames" / "Cancel" would
    -- leave the old file in place, which the size check below would then take as this render's result.
    -- If it cannot be removed (in use), ffmpeg fails and REAPER's own overwrite question comes up.
    if reaper.file_exists(out) then os.remove(out) end

    local how
    local ffmpeg = L.find_ffmpeg(HERE)
    if ffmpeg then
      L.log(string.format("re-encoding with ffmpeg (%s): %s -> %s (REAPER waits until it is done)",
        ffmpeg, L.basename(path), L.basename(out)))
      local ok, err = L.ffmpeg_mjpeg(ffmpeg, path, out, MAX_HEIGHT, JPEG_QUALITY)
      if ok then
        how = "ffmpeg"
      else
        L.log("ffmpeg failed (" .. tostring(err) .. ") -> REAPER's renderer instead")
        if reaper.file_exists(out) then os.remove(out) end
      end
    else
      L.log("ffmpeg not found -> REAPER's renderer")
    end
    if not how then
      if not render_with_reaper(item, take, src, path, dir, name) then return end
      how = "REAPER"
    end

    if reaper.file_exists(out) and (L.file_size(out) or 0) > 1024 then
      reaper.Undo_BeginBlock()
      L.take_set_source(take, reaper.PCM_Source_CreateFromFile(out))   -- ((⚪151) the old source freed)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", L.basename(out), true)
      reaper.UpdateItemInProject(item)
      reaper.Undo_EndBlock("ReaScratch re-encode " .. name, -1)
      L.log(string.format("done in %.1f s (%s): %s (%.1f MB)", reaper.time_precise() - t0, how, out, (L.file_size(out) or 0) / 1e6))
    else
      L.log("render failed: " .. out)
      L.msgbox(L.T("MJPEG の書き出しに失敗しました:\n", "Could not render the MJPEG:\n") .. out .. "\n\n" ..
        L.T("代わりに kit/tools の allintra_ffmpeg スクリプトで変換してください（ffmpeg が要ります）。",
            "Convert it with the allintra_ffmpeg script in kit/tools instead (needs ffmpeg)."))
    end
  end
end

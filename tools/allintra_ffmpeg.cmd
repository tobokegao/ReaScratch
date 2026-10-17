@echo off
rem ReaScratch: all-keyframe H.264 (every frame is a keyframe, so any frame seeks instantly)
rem Drag video files onto this .cmd. Output: <name>_allintra.mp4 next to each source. Needs ffmpeg on PATH.
rem Height is capped at 720; change MAXH below to keep larger sizes. (ASCII only: cmd.exe is not UTF-8)
setlocal
set MAXH=720
where ffmpeg >nul 2>nul
if errorlevel 1 (
  echo ffmpeg not found. Install "release essentials" from https://www.gyan.dev/ffmpeg/builds/ and add its bin folder to PATH.
  pause
  exit /b 1
)
if "%~1"=="" (
  echo Drag and drop video files onto this .cmd file.
  pause
  exit /b 1
)
:next
if "%~1"=="" goto done
echo === %~nx1
ffmpeg -hide_banner -y -i "%~1" -vf "scale=-2:'min(ih,%MAXH%)'" -c:v libx264 -g 1 -keyint_min 1 -sc_threshold 0 -crf 18 -preset fast -pix_fmt yuv420p -c:a aac -b:a 192k "%~dpn1_allintra.mp4"
shift
goto next
:done
echo Done. Import the _allintra.mp4 file with reascratch_import_video.lua.
pause

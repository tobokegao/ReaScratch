#!/bin/bash
# ReaScratch: all-keyframe H.264 (every frame is a keyframe, so any frame seeks instantly) - macOS
# Use: double-click this file (Terminal opens), then drag video files into the Terminal window and press Enter.
# Or: ./allintra_ffmpeg.command movie1.mp4 movie2.mov
# Output: <name>_allintra.mp4 next to each source. Needs ffmpeg (brew install ffmpeg).
# Height is capped at 720; change MAXH below to keep larger sizes.
MAXH=720
# messages: Japanese when the Mac's language is Japanese ($LANG ja_...), else English
t() { case "${LANG:-}" in ja*) printf '%s' "$1" ;; *) printf '%s' "$2" ;; esac; }
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "$(t "ffmpeg が見つかりません。ターミナルで: brew install ffmpeg" "ffmpeg not found. In Terminal: brew install ffmpeg")"
  read -r -p "$(t "Enter で閉じる" "Press Enter to close")"
  exit 1
fi
if [ $# -eq 0 ]; then
  echo "$(t "動画ファイルをこのウィンドウにドラッグして Enter:" "Drag video files into this window and press Enter:")"
  read -r LINE
  eval "set -- $LINE"      # Terminal escapes spaces in dragged paths with backslashes
fi
for f in "$@"; do
  echo "=== $(basename "$f")"
  out="${f%.*}_allintra.mp4"
  ffmpeg -hide_banner -y -i "$f" -vf "scale=-2:'min(ih,$MAXH)'" -c:v libx264 -g 1 -keyint_min 1 -sc_threshold 0 -crf 18 -preset fast -pix_fmt yuv420p -c:a aac -b:a 192k "$out"
done
echo "$(t "完了。_allintra.mp4 を reascratch_import_video.lua で取り込んでください。" "Done. Import the _allintra.mp4 file with reascratch_import_video.lua.")"
read -r -p "$(t "Enter で閉じる" "Press Enter to close")"

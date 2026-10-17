#!/bin/bash
# ReaScratch HID bridge - build a stand-alone macOS program (no Python needed afterwards), for handing to others.
# Use: double-click this file on a Mac with Python 3. Output: dist/ReaScratch-HID-Bridge next to this file
# (a command-line program: double-click it, or run it in Terminal). Built for the Mac it runs on (Apple silicon or
# Intel). Not signed: the first start needs right-click > Open.
cd "$(dirname "$0")" || exit 1
# messages: Japanese when the Mac's language is Japanese ($LANG ja_...), else English
t() { case "${LANG:-}" in ja*) printf '%s' "$1" ;; *) printf '%s' "$2" ;; esac; }
PY=python3
if ! command -v "$PY" >/dev/null 2>&1; then
  t "python3 が見つかりません。https://www.python.org/downloads/ から入れるか、ターミナルで: brew install python" \
    "python3 not found. Install it from https://www.python.org/downloads/ or in Terminal: brew install python"; echo
  read -r -p "$(t "Enter で閉じる" "Press Enter to close")"
  exit 1
fi
"$PY" -m venv .venv-build && .venv-build/bin/python -m pip install --quiet --upgrade pip && \
  .venv-build/bin/python -m pip install --quiet hidapi mido python-rtmidi pyinstaller || { read -r -p "$(t "準備に失敗しました。Enter で閉じる" "Setup failed. Press Enter to close")"; exit 1; }
.venv-build/bin/python -m PyInstaller --noconfirm --onefile --console --name ReaScratch-HID-Bridge \
  --hidden-import mido.backends.rtmidi hid_bridge.py && echo "$(t "できました" "Done"): $(pwd)/dist/ReaScratch-HID-Bridge"
read -r -p "$(t "Enter で閉じる" "Press Enter to close")"

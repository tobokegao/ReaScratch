#!/bin/bash
# ReaScratch HID bridge (NI Traktor Kontrol S4 MK3 / MK2, S3, S2 MK3 / MK2 / MK1) - macOS
# Use: double-click this file (Terminal opens). The first time it makes a private Python folder (.venv) next to this
# file and installs hidapi / mido / python-rtmidi into it (needs Python 3: https://www.python.org/downloads/ or
# `brew install python`). Then it waits for the unit and sends MIDI to a new virtual port "ReaScratch HID Bridge".
# In REAPER: Settings > MIDI Inputs > enable "ReaScratch HID Bridge", and pick the JSFX preset
# "HID bridge (NI S2/S3/S4) deck 1 / deck 2". Quit Traktor first (on macOS the unit can be opened by one app only).
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
if [ ! -x .venv/bin/python ]; then
  echo "$(t "初回の準備（.venv を作って hidapi・mido・python-rtmidi を入れます）..." "First-time setup (making .venv and installing hidapi, mido, python-rtmidi)...")"
  "$PY" -m venv .venv && .venv/bin/python -m pip install --quiet --upgrade pip && \
    .venv/bin/python -m pip install --quiet hidapi mido python-rtmidi || { read -r -p "$(t "準備に失敗しました。Enter で閉じる" "Setup failed. Press Enter to close")"; exit 1; }
fi
.venv/bin/python hid_bridge.py "$@"
read -r -p "$(t "Enter で閉じる" "Press Enter to close")"

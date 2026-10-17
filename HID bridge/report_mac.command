#!/bin/bash
# ReaScratch HID bridge - report for testers (macOS). Double-click with the controller connected (quit Traktor first).
# It writes hid_bridge_report.txt next to this file: the Mac, the Python parts, a self-check, the MIDI ports, and
# 15 seconds of the controller's data while you move it (read only: nothing is sent to the controller).
# Attach the file to a GitHub issue or the forum thread. The first run sets up .venv like run_mac.command.
bash "$(dirname "$0")/run_mac.command" --report

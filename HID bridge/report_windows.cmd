@echo off
rem ReaScratch HID bridge - report for testers (Windows). Double-click with the controller connected (quit Traktor first).
rem It writes hid_bridge_report.txt next to this file (read only: nothing is sent to the controller). Attach it to a GitHub issue or the forum thread.
cd /d "%~dp0"
if exist ReaScratch-HID-Bridge.exe (ReaScratch-HID-Bridge.exe --report) else (python hid_bridge.py --report)
pause

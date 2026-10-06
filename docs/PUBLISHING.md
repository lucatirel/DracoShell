# Public-edition publishing

This standalone edition contains the selected cyan outline dragon, subtle motion,
narrow green typing lightning and foreground/background storm layers. It is a
snapshot of development revision `53208816a2cc6687e1b498de15a2d40fd96ddc3b`,
prepared without development Git history. The public repository uses `main`.

CI validates assets, setup, startup, input boundaries, prompt and the actual
production shader on Windows. The README demonstration is an offscreen Direct3D
capture with simulated anonymous activity; it does not measure live input latency.

Before tagging a release, test install → install again → uninstall → close all
Terminal windows → reopen → reinstall on Windows. Backups stay private and the
uninstaller preserves only the inactive graphics cache for safe asynchronous
Terminal reloads. Record Terminal, PowerShell, editor and prompt versions.

Run `Publish-To-GitHub.ps1` from a clean checkout for a read-only publishing
preflight. It does not create repositories or push changes. Optional creator
funding is configured using `scripts/Set-CreatorSupport.ps1`.

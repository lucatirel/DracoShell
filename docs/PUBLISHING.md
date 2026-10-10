# Publishing DracoShell

DracoShell keeps independent public Git history. Its default is cyan `lineart`;
the catalog includes public, subtle, armored and three historical ambient effects
adapted to that public drawing. Manufacturer artwork, derived crops/icons/atlases
and private demo media are excluded.

Transfer reviewed code and permitted packs as file-level commits based on public
main. Never merge or push private branches, tags or commit ancestry. Preserve public
licenses, issue templates, funding settings and demo media. Private branch snapshots,
the archive helper and recovery backups do not belong here.

Before release:

1. Run Windows checks for every preset, shared setup/input/prompt/reset and WARP
   rendering. `tests/validate-publication.ps1` rejects known excluded artwork and
   private source commits in tracked files and reachable history.
2. Verify install → reinstall → switch preset → uninstall → close all Terminal
   windows → reopen → reinstall on Windows. Record dependency/Terminal versions.
3. Inspect all new artwork and history. Known-hash checks cannot establish rights
   for new or altered images. Keep personal settings and recordings private until reviewed.
4. Keep the README demo identified as a production-shader capture with simulated activity.
5. Tag the tested public commit and write release notes from CHANGELOG.

`Publish-To-GitHub.ps1` is a read-only clean-checkout preflight. Optional creator
support uses `scripts/Set-CreatorSupport.ps1`; preserve configured destinations.


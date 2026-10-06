# Contributing

Use a small branch and describe the visible behavior before and after the change.
Keep the shader compatible with `ps_4_0` and scripts compatible with Windows
PowerShell 5.1. Avoid per-key processes, global hooks, command/character inspection,
unbounded effect queues and changes to custom editor shortcuts.

Run `tests/validate.ps1`, `tests/validate-setup.ps1` and
`tests/validate-input.ps1` on Windows. See [dependencies](docs/DEPENDENCIES.md)
for optional asset/media/C++ development tools. GitHub Actions
also renders the production shader through Direct3D WARP at landscape, portrait
and half-screen sizes, checks anonymous pulse transport, and exercises the real
Oh My Posh prompt. A shader change also needs a live Terminal check at fullscreen
and half-screen; CI does not measure live frame rate or input latency.

For assets, record provenance and redistribution rights. Do not submit unrelated
logos or third-party imagery without documented permission. Never commit local
profiles, backups, settings, tokens or private keys.


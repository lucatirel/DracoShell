# Source security review — 2026-10-05

## Result and scope

The current development source was inspected across installer/reset scripts,
PowerShell profiles and prompt configuration, C# pulse transport, HLSL, asset/media
helpers, publishing/funding helpers, tests and CI. The review did not identify an
unresolved high/critical issue in DRACO's own current source after the changes
below. This is a source and behavior review, not an independent penetration test,
a signature attestation, a complete dependency audit or a zero-vulnerability
certificate. Reachable Git history is outside this source-review scope.

## Findings addressed

| Finding | Change / evidence |
| --- | --- |
| Installer wrote the profile before validating Terminal JSON/target profile | Parse JSONC, check target/profile syntax and destination flags before active writes; negative fixtures preserve the original profile |
| File writes could leave truncated settings/profile content | Write to a unique adjacent file and use atomic replacement; restore settings if the subsequent profile write fails and no concurrent edit occurred |
| Update could overwrite Terminal settings edited during dependency work | Compare the file with its original content before committing active settings |
| Font discovery queried a catalog rather than installed fonts and ignored failure | Enumerate actual installed families; check install exit status; fail before active writes if unavailable |
| Setup assumed packaged Stable/Preview settings | Add unpackaged path, explicit `-SettingsPath` and recorded target for update/reset |
| Cached DLL bytes could be endorsed by a new config without rebuilding | Compile from reviewed C# source during each input-enabled installation; corruption fixture verifies repair |
| DLL was hashed and then read separately for loading | Read once, SHA-256 that exact byte array, then pass it to `Assembly.Load` |
| Linked runtime paths could redirect installation/removal | Reject reparse points along every runtime destination; junction fixture preserves the outside sentinel |
| Setup/reset could clobber a user hotkey or pre-existing `-NoLogo` | Keep custom chords, including legacy actions; record whether DRACO added `-NoLogo`; repeated reset does not remove unrelated appearance |
| Prompt initialization could evaluate partial output after a native failure | Check version and successful initialization before evaluating the trusted local dependency's initialization code |
| Old Oh My Posh releases have published prompt-injection vulnerabilities | Require 31.4.1+ in installer and startup; both reviewed advisories were fixed in 29.35.1 |
| Media helper could let ffmpeg open network resources | Require a local input file, disable network protocols and stdin, execute an argument list without a shell |
| Checkout persisted repository credentials | Pin the action commit, use `persist-credentials: false`, read-only contents permission and a bounded job timeout |
| Donation URL could be guessed or expose financial credentials | Inactive funding template; creator helper accepts only HTTPS PayPal.Me profile links and writes documentation/config only |

Earlier protections are retained: strict local DLL basename validation, asset
hashes and fixed manifest names, checked dependency install exit codes, custom
editor-handler restoration, and quarantine only for malformed JSON rather than
permissions/write failures. The publishing helper remains a read-only preflight.

## Input privacy boundary

`Click()` and `Fire()` have zero arguments. The component stores bounded anonymous
counts/timestamps and output state. It never receives characters or command
content. PSReadLine wrappers delegate their existing opaque arguments unchanged
to the normal editor action, then notify graphics. Custom handlers and vi mode are
preserved. The editor path does not wait for the background console writer.

Native imports are limited to `kernel32.dll` output APIs: `GetStdHandle(-11)`,
`GetConsoleMode`, `SetConsoleMode` and `WriteConsoleW`. Tests assert the native API
allowlist. There are no global keyboard hooks, input-console reads, clipboard
reads, file logging, telemetry or networking in the effects component.

The shader receives Terminal's ordinary rendered texture and decodes the marker
at two fixed output coordinates; it does not extract text or sample the command
line/caret. The marker changes only one background attribute, preserving the
character, foreground and cursor.

PSReadLine/Oh My Posh retain ordinary command validation, history, path/environment
and Git display. The prompt cache reads the latest history ID, not command text,
and remains separate from the anonymous graphics bridge. DRACO does not disable
shell history or audit the internals of those upstream products.

## Dependency advisories checked

Primary maintainer advisories reviewed on 2026-10-05:

- [GHSA-6xj8-qv9j-xcjq / CVE-2026-73505](https://github.com/JanDeDobbeleer/oh-my-posh/security/advisories/GHSA-6xj8-qv9j-xcjq): path template injection; affected through 29.35.0, patched in 29.35.1.
- [GHSA-fwjx-9p69-h25h / CVE-2026-73506](https://github.com/JanDeDobbeleer/oh-my-posh/security/advisories/GHSA-fwjx-9p69-h25h): terminal escape injection; same affected/patched version boundary.

The CI-tested/baseline Oh My Posh 31.4.1 is above both fixes. This does not establish
that every future/current upstream vulnerability is absent. The upstream security
policy supports its latest release; users should keep dependencies updated.
[PSReadLine's maintainer security page](https://github.com/PowerShell/PSReadLine/security)
listed no published advisories at review time, which is not proof of no flaws.

Optional media tooling pins Pillow 12.3.0 in `requirements-dev.txt`; Python/Pillow
and ffmpeg are absent from normal installation/runtime. Update the pin after
reviewing upstream releases. System components and third-party binaries/fonts are
installed separately and retain their own licenses/trust boundaries.

## Verification

Windows checks cover PowerShell 5.1 parsing, asset hash/layout/alpha validation,
production Direct3D shader compilation, quiet healthy startup, exact DLL-byte
integrity and path traversal rejection, installer migration/rollback safeguards,
invalid JSON/missing-target early rejection, JSONC strings, unwritable files,
custom shortcuts, launch-option ownership, cached-DLL repair, unpackaged settings
and linked-runtime rejection.

Pulse checks cover anonymous APIs, the native output allowlist, bounded flood
behavior, expiry/restarts, no flame backlog, editor calls while graphics output
is deliberately stalled, actual ConPTY transport, stock/custom/Oh My Posh handler
restoration and untouched Ctrl+C. WARP render checks cover several viewport shapes,
signed clocks, pane-wide lightning, protected text, marker cleanup and moving fire.

A high-confidence pattern scan of the current tracked text found no GitHub/AWS
credentials, private-key headers or credential-bearing URLs. It cannot rule out
unrecognized formats, secrets in binary assets or old commits. No user profiles,
recordings, recovery backups or compiled binaries are included in the current tree.
The README capture was inspected for visible commands/paths before committing.

## Remaining trust boundaries

- The checkout, user profile/runtime directory and installed Oh My Posh executable
  are trusted local code. A same-user attacker who can replace profiles/configs
  can already run code as that user; hash checks are not signatures and cannot
  defend against replacement of both bytes and their recorded hashes.
- Reparse checks and atomic writes reduce accidental/redirection risk; they are
  not a sandbox against a privileged attacker racing filesystem changes.
- Initialization intentionally evaluates code emitted by the installed local
  Oh My Posh binary, following its documented integration. DRACO does not execute
  arbitrary remote installation scripts or command text for graphics.
- Package/font tools perform their own network and installation work. DRACO does
  not change execution policy, repository trust, enterprise restrictions or
  machine security controls. Run setup as a normal user.
- Recovery backups can contain personal settings/profile data. Keep them private.
  Reset uses Terminal defaults for DRACO appearance; exact prior appearance is
  recovered manually from the timestamped backup.
- Live Terminal performance, reachable Git history and asset provenance
  still require their own checks before public distribution. See [publishing](PUBLISHING.md).


## Public-edition startup and reset

An argument-free `powershell.exe` handed off to Windows Terminal can print its
native profile timing after all profiles run. The public and development profiles
clear the initial screen once when the first prompt is invoked. Explicit launch
arguments, non-Terminal hosts, existing history or startup errors prevent this.
The wrapper delegates to the original prompt and never reads console input.

Reset removes settings, loaders, DLLs and executable state; it retains inactive
PNG/HLSL cache files because settings reloads are asynchronous. This avoids
missing-resource reload failures without timers, process launches or handlers.
Close all Terminal windows and reopen to verify the fresh shell state.

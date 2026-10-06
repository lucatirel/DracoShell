# Security

The effects API accepts anonymous `Click()` and `Fire()` calls with no arguments.
It does not receive characters, commands, clipboard content or keyboard identity.
There are no global keyboard hooks, input-console reads, telemetry or network
calls in the pulse component. It writes a fixed background attribute to one
output cell; the shader decodes only the anonymous activity and flame age.

PSReadLine and Oh My Posh still perform their normal editor/prompt functions,
including command validation, history and path/branch display. That existing
behavior is separate from the anonymous graphics bridge.

Keep Oh My Posh updated. Setup and startup require 31.4.1+, above the known
29.35.1 prompt-injection fixes. Local DLL bytes are verified before loading, and
setup rejects linked runtime paths. These are safeguards, not a security sandbox
or a guarantee of zero vulnerabilities.

See [the source review](docs/SECURITY_REVIEW.md) for scope, fixes and limitations.

For a vulnerability, use GitHub's private **Report a vulnerability** feature when
enabled on this repository. If it is unavailable, open an issue requesting a
private reporting channel without including exploit details or secrets. Please
include the commit, Windows/Terminal/PowerShell versions and a minimal reproducer.


# Armored Draco: flight and landing

Draco is a heavy black armored reptile: thick chest and neck, broad head,
large graphite plates, red eye, heavy legs and talons. Its two authored component
sprites are packed into the existing atlas: body and one wing used twice.

| Scene age | Action |
| --- | --- |
| 0–1.25 s | Enter from the upper-left, approach and grow in apparent size |
| 1.25–3.15 s | Fly across the lightning with large, offset wing beats |
| 3.15–4.35 s | Brake, descend and extend the legs |
| 4.35–4.95 s | Land with recoil, a lightning flash and a brief energy ring |
| 4.95–5.5 s | Settle into the grounded pose |
| Afterward | Gentle breathing, head and tail motion; lightning and fire remain active |

This is an articulated 2D scene. The wings pivot and change projected span at
independent shoulders; the body travels, scales and tilts. Legs retract in flight.
It does not offer a 3D camera orbit, independent feet/contact physics or a full
skeletal walk cycle. A single generated illustration cannot supply those poses.

The scene plays once per tab when input effects and body motion are enabled.
`Test-DracoFlight` replays it. Repeated requests replace one timestamp rather
than accumulating flights. `-NoDragonMotion` disables body and flight motion,
keeping eye, lightning and Enter fire. `-Static` uses a native static background.
`-NoTypingEffects` disables the marker bridge, so there is no entrance.

The clock is a 5.5-second monotonic anonymous marker, carried by the existing
output-only helper. Red encodes entrance age, green typing, blue fire; all three
can coexist. Shader Time still drives ambient effects and may be signed/uptime.
The marker never includes a character or command. Reset/Stop cancels the entrance;
the existing timer sleeps when the marker and pending effects drain.

One 4352 x 640 atlas is 10.625 MiB decoded, compared with 7.5 MiB for the previous
single-body version. The rig uses one body sample and two wing samples in its
bounds. There are no additional runtime dependencies or per-key processes.
GPU usage and responsiveness need comparison on the target PC.


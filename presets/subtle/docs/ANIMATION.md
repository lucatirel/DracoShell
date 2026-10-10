# A living dragon in the terminal

The public dragon uses a minimal transparent 640 x 640 sprite. The artwork is
intentionally simpler: broad cyan wing ribs, two dark body tones, a red eye and
a long curved tail remain legible at terminal size.

| Part | Idle motion | During Enter breath |
| --- | --- | --- |
| Chest | Small expansion and relaxation over 4.8 seconds | Continues breathing |
| Head and neck | Gentle tilt following the breathing cycle | Short forward lunge, then recovery |
| Wing | Slow flex over 6.4 seconds | Slight tension |
| Tail | Sway over 5.6 seconds | Continues swaying |
| Eye and contour discharges | Follow the same deformed sprite | Stay attached to the head/body |
| Fire | Inactive | Starts from the moving jaw and follows its local direction |

This is a continuous 2D deformation of one image. It does not provide a full
flight cycle, independent jaw opening, separate overlapping limbs or 3D rotation.
Those would need separately authored layers or consistent animation frames.
Motion stays small to preserve the silhouette and keep the terminal readable.

The shader adds arithmetic inside the dragon bounds, with one cached body
texture sample and no additional atlas memory. The input bridge is unchanged.
GPU usage and typing responsiveness still require a live comparison on the
Windows target machine; the offscreen renderer is a visual regression check.

## Compare modes

Run from the repository, then open a new PowerShell tab:

```powershell
# Living body, eye, lightning and fire (default)
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# Still body with the same effects
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoDragonMotion

# Entirely static native Terminal background
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Static
```

Normal installation restores motion. The opt-out uses a different shader filename
so Terminal reloads the selected mode. Existing tabs may need reopening.

The Windows checks compile both shader variants as `ps_4_0`, verify that wing
and tail silhouettes actually change while the disabled version remains fixed,
and preserve the existing fire, marker, text and setup/reset checks.


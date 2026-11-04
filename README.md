# ContraLoWRecomp

Work-in-progress static-recompilation port of **Contra: Legacy of War**
(PlayStation, USA release) targeting **native Android (arm64 APK)**, built with
[psxrecomp-android](https://github.com/dguillot-gh/psxrecomp-android) — the game's
own MIPS program is translated to C and compiled for the phone, not emulated.

**Launcher-based**: the APK contains no game data. On first launch the app's start
menu asks you to **Select game file** and you pick your own `.cue` + `.bin` dump.
That is also what makes this repository safe to publish: nothing from the disc is
ever committed here.

Unofficial, non-commercial fan project for personal use. Not affiliated with or
endorsed by Konami or Appaloosa Interactive. **No disc image, BIOS (beyond the
MIT-licensed OpenBIOS), saves, or disc-derived code is distributed by this
repository.** The engine is PolyForm Noncommercial 1.0.0: personal,
non-commercial use only.

## Verified disc

| Field | Value |
| --- | --- |
| Game | Contra: Legacy of War (USA) |
| Serial | `SLUS-00288` |
| Boot program | `SLUS_002.88` (610,304 bytes), entry `0x800513E4` |
| Tracks | 12 (1 data + 11 CDDA audio) |
| Data track MD5 | `15a2a2759e8e2db4d85022a2c7aebe1e` |
| Data track SHA-1 | `71469e048f0f6f0680356652ea8ec5bf4ce9cc7a` |

Put your legally obtained dump (`.cue` + all track `.bin` files) at
`disc/` (gitignored). Other dumps of the same serial usually work too.

## Build (Windows host)

**Clone / keep this repository at a short path** (for example `C:\psx\ContraLoWRecomp`).
The engine's source tree contains file paths that overflow Windows' 260-character
`MAX_PATH` limit inside a deeply nested folder — the recompiler build fails with
`Filename longer than 260 characters` if the checkout sits too deep.

Requires PowerShell 7 (`winget install Microsoft.PowerShell`), Python 3, Java 17+,
and an Android SDK with **NDK 28.2.13676358** + **CMake 3.22.1** (`ANDROID_HOME`
set). The first recompiler build downloads a portable llvm-mingw (~190 MB) into
`tools-cache\`; the first APK build downloads Gradle 8.12 and SDL3 (pinned by
SHA-256). Nothing is installed into Windows.

```powershell
# 0. once: fetch the engine submodule
git submodule update --init --depth 1

# 1. Build the recompiler from the pinned psxrecomp worktree (5-10 min)
pwsh tools\build-recompiler.ps1

# 2. Generate the game's C code from your disc (disc\ must hold your dump)
pwsh tools\regen.ps1

# 3. Android APK (arm64, launcher-style: no disc embedded)
pwsh tools\build-apk.ps1          # add -Play for the faster "play" build
```

The APK lands in `apk\`. Install it (`adb install <apk>`), copy your `.cue` +
`.bin` files to the phone (e.g. `Download\contralow_recomp`), open the app,
**Select game file**, pick the `.cue`, then **Play**.

## What's here

| Path | Purpose |
| --- | --- |
| `game.toml` | the game's configuration (boot program, memory layout, controller, video) |
| `seeds/` | code entry points the recompiler starts from (first pass from the boot EXE) |
| `disc_probe.json`, `catalog_identity.json` | disc identity + digests from the probe |
| `android/` | the Android app project (package `com.psxrecomp.contralow`) |
| `CMakeLists.txt` | native build glue: generated code + the psxrecomp runtime |
| `psxrecomp/` | the engine, as a git submodule (`dguillot-gh/psxrecomp-android`, branch `android`) |
| `tools/` | build-recompiler / regen / build-apk / icon scripts |
| `boxart-name.txt` | the cover's name in libretro-thumbnails (for the app icon) |
| `disc/`, `generated/`, `saves/` | your dump, generated code, memory cards — **gitignored, never committed** |

## Status

- [x] Disc probed: SLUS-00288, boot EXE + 811 first-pass seeds
- [x] Android app generated from the psx-android template (launcher start menu)
- [ ] Recompiler built
- [ ] Game code generated from the disc
- [ ] APK builds
- [ ] Boots on device
- [ ] Gameplay verified

## Credits

- [mstan/psxrecomp](https://github.com/mstan/psxrecomp) and the
  [psxrecomp-android](https://github.com/dguillot-gh/psxrecomp-android) Android layer
  (PolyForm Noncommercial 1.0.0)
- [psx-android](https://github.com/dguillot-gh/psx-android) build scripts and app
  template (MIT) — `tools/` here are adapted from it
- [OpenBIOS](https://github.com/grumpycoders/pcsx-redux) (MIT) — the free PS1 BIOS
  the app boots
- [SDL](https://libsdl.org) (zlib)

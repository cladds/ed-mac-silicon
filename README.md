# ed-mac

Reproducible, scriptable setup for **Elite Dangerous** on Apple Silicon, using Homebrew, Wine, and Apple's Game Porting Toolkit (GPTK / D3DMetal). No CrossOver, no Whisky, no GUI wrappers. Every step is a shell script you can read, diff, and re-run.

If this saves you a weekend of debugging, you can buy me a coffee at **[ko-fi.com/cladds](https://ko-fi.com/cladds)**.

---

## What you end up with

- Elite Dangerous installed into a dedicated Wine prefix at `~/Games/elite-dangerous`
- [min-ed-launcher](https://github.com/rfvgyhn/min-ed-launcher) authenticated to your Frontier account, with credentials encrypted at rest (same DPAPI format the Windows launcher uses)
- A double-clickable `Elite Dangerous.command` in `~/Applications`
- A second prefix at `~/Games/ed-tools` for companion tools (EDDiscovery, etc.) so a bad tool update cannot corrupt your game install

Everything else (idempotent scripts, log files, sentinels, nuke-and-pave) is there to make the setup recoverable from any failed state.

## Prerequisites

| What | Why | How |
|---|---|---|
| Apple Silicon Mac (M1 or later) | GPTK only runs on Apple Silicon | - |
| macOS 14 Sonoma or later | GPTK requires Sonoma+ | - |
| ~150 GB free disk | ED + Odyssey + tooling + prefix overhead | - |
| **Xcode.app** from the Mac App Store | GPTK needs the full Metal toolchain. Command Line Tools alone will not do. | `mas install 497799835` or install from the App Store |
| A Steam account that owns Elite Dangerous | So SteamCMD can download the game files | - |
| A Frontier account | min-ed-launcher authenticates here directly (no Steam client needed at runtime) | Register at https://user.frontierstore.net |
| **.NET 8 SDK** | One-time dependency to compile the credential helper | `brew install --cask dotnet-sdk` |

If you bought ED as a Steam key but never linked it to a Frontier account, go to https://user.frontierstore.net -> Account -> Add Game Code and redeem the key there first. Steam at runtime is optional; a Frontier account is not.

---

## Step-by-step setup

Clone the repo, then work through these in order. Every script is idempotent. Each one writes a sentinel under `~/Games/.ed-mac-setup/sentinels/` when it finishes, and re-running a completed step is a no-op. Delete the matching sentinel file to force a re-run.

### 1. Preflight check

```bash
./scripts/00-preflight.sh
```

Confirms you are on Apple Silicon, macOS is recent enough, Xcode.app is installed, and you have enough free disk. If anything is wrong it says exactly what.

### 2. Install dependencies

```bash
./scripts/01-install-deps.sh
```

Installs Homebrew (if missing), Rosetta 2, the [gcenx/wine](https://github.com/gcenx/homebrew-wine) tap, the GPTK-bundled Wine cask, winetricks, and jq. Nothing here is unusual Homebrew activity; you can watch it happen in the log.

Keep Rosetta current separately (occasionally macOS Software Update defers it):

```bash
softwareupdate --install-rosetta --agree-to-license
```

### 3. Create the Wine prefix

```bash
./scripts/02-create-ed-prefix.sh
```

Builds a clean 64-bit Wine prefix at `~/Games/elite-dangerous`, installs core Windows fonts and the VC++ runtime via winetricks, and runs the Steam installer inside the prefix (needed only so the prefix has the expected directory layout).

### 4. Install Elite Dangerous

The Steam GUI's `steamwebhelper` process crashes on Apple Silicon in many setups, so the recommended path is headless SteamCMD:

```bash
./scripts/02b-install-ed-via-steamcmd.sh
```

Prompts for your Steam username, then hands off to SteamCMD running inside the Wine prefix. SteamCMD will prompt for your Steam password and a Steam Guard code (approve the mobile prompt or type the emailed code). Download is ~30 GB and resumable; Ctrl+C and re-run if it stalls.

Want Odyssey too? Re-run with `ED_APP_ID=1278510 ./scripts/02b-install-ed-via-steamcmd.sh`.

If you would rather brave the Steam GUI, `./scripts/03-install-ed.sh` does the same thing interactively. Use `./scripts/launch-steam.sh` if `steamwebhelper` keeps crashing; it passes `-cef-disable-gpu -no-cef-sandbox` which usually gets you to the library screen.

### 5. Install min-ed-launcher

```bash
./scripts/04-install-launcher.sh
```

Downloads the latest [min-ed-launcher](https://github.com/rfvgyhn/min-ed-launcher) win-x64 release from GitHub, extracts it into the prefix at `C:\Program Files\min-ed-launcher`, and drops a starter `settings.json` into `%LOCALAPPDATA%\min-ed-launcher\` (where the launcher actually reads it from).

### 6. Build the credential helper

```bash
./scripts/build-cred-helper.sh
```

Compiles `tools/mel-cred-helper/` to a self-contained Windows x64 single-file exe. You only run this once (or again when the helper source changes). The output lands at `tools/mel-cred-helper/bin/publish/MelCredHelper.exe` and is ignored by git.

### 7. Seed your Frontier credentials

```bash
./scripts/04b-setup-frontier-creds.sh
```

Prompts for your Frontier email and password. Both are passed to the helper, which runs under Wine, reflects the DPAPI salt out of `ClientSupport.dll` (same way min-ed-launcher does), encrypts the password, and writes the 2-line `.cred` file the launcher expects.

On the first interactive launch after this, Frontier will email you a 2FA verification code for this "new device". Type it blind at the prompt (Wine does not echo characters, but it does accept them). After that one success, the launcher appends a machine token to the `.cred` file and 2FA is done forever for this install.

### 8. Install the double-click launcher

```bash
./scripts/install-app-launcher.sh
```

Drops `Elite Dangerous.command` into `~/Applications`. Double-click it from Finder and ED boots. Under the hood it just calls `./scripts/launch-ed.sh`.

### 9. Launch

Either double-click the .command file, or from a terminal:

```bash
./scripts/launch-ed.sh
```

Flags:
- `--debug` enables `WINEDEBUG=+all` (very verbose, useful when something breaks)
- `--hud` turns on Apple's Metal HUD (FPS / VRAM overlay)
- `--no-caffeinate` lets the Mac sleep while ED is running (default is to prevent sleep)
- `--profile NAME` uses a different Frontier credential profile (default is `default`). Useful if you have multiple Frontier accounts.

### 10. (Optional) Companion tools

```bash
./scripts/05-create-tools-prefix.sh
```

Creates a separate prefix at `~/Games/ed-tools` for EDDiscovery and similar. A borked tool update in this prefix cannot touch your game install. EDMarketConnector has a native macOS build so no Wine prefix needed for that one; the script installs it via Homebrew cask.

---

## Day-to-day use

Once set up, launching is just the double-click. Everything the launch script does on each run:

1. Resolves the GPTK Wine binary (probes a few known homebrew paths)
2. Exports env vars that make Wine's .NET TLS and Rosetta behave (see [How it works](#how-it-works))
3. Runs min-ed-launcher under `caffeinate` so your Mac does not sleep mid-jump
4. Passes `EDLaunch.exe` as an argv argument so the launcher skips its broken install-dir discovery
5. Uses `/frontier default /autorun /autoquit` to login with your saved creds, auto-start ED, and close the launcher when the game exits

Logs land in `~/Games/.ed-mac-setup/logs/` timestamped by run.

---

## How it works

This section is useful if something breaks and you want to understand why. Skip if you just want to play.

### Why a Wine prefix, not a Mac-native port

There is no macOS build of Elite Dangerous. Apple's Game Porting Toolkit (D3DMetal) translates DirectX 11/12 API calls to Metal in real time. It runs inside a Wine prefix with a specialised `wine64` binary shipped via the `gcenx/wine` Homebrew tap. We install ED into that prefix exactly as if it were a weird-flavoured Windows PC.

### Why SteamCMD instead of the Steam client

The Steam client's `steamwebhelper` (a CEF/Chromium subprocess) crashes frequently on Apple Silicon under Wine. SteamCMD is a headless command-line alternative that just talks to Steam's download CDN. Once ED is installed, the Steam client is not needed at runtime because we auth against Frontier directly.

### Why min-ed-launcher instead of the Frontier launcher

The official Frontier launcher hangs at its splash screen under Wine. min-ed-launcher is a clean-room reimplementation that does the OAuth dance and directly launches `EliteDangerous64.exe`. It is the recommended approach in the Linux+Wine ED community too.

### The interactive-login workaround

min-ed-launcher's first-run flow prompts for Frontier email + password on the console. Under Wine, .NET's `Console.ReadLine()` and `Console.ReadKey()` do not reliably receive piped input or echo typed characters, so this flow is effectively broken. We sidestep it by precomputing the `.cred` file.

Key insight: the `.cred` file on Windows is DPAPI-encrypted (`ProtectedData.Protect` with a salt reflected out of `ClientSupport.dll`). DPAPI keys are bound to the Wine prefix, so the helper has to run **inside** the prefix. `tools/mel-cred-helper/` does exactly that: it is a tiny .NET 8 app that mirrors min-ed-launcher's `Cobra.encrypt` logic and writes the 2-line `.cred` file directly, skipping all interactive IO.

### The TLS + Rosetta env vars in launch-ed.sh

Two workarounds are wired into `launch-ed.sh`:

- `SSL_CERT_FILE=/etc/ssl/cert.pem` and friends. .NET's TLS under Wine has no trusted root CAs by default, so HTTPS calls to Frontier's manifest server fail with `0x80131506`. Pointing the TLS libraries at macOS's bundled CA file fixes it.
- `DOTNET_EnableHWIntrinsic=0`. Rosetta 2 cannot faithfully emulate some x86 hardware-crypto instructions (AES-NI, AVX) that .NET 8's TLS stack uses, which manifests as `rosetta error: unexpectedly need to EmulateForward on a synchronous exception`. Disabling .NET hardware intrinsics makes it fall back to software crypto. The perf hit only applies to the launcher's update check, not the game.

### Settings.json lives in AppData, not next to the exe

A trap that cost me hours: min-ed-launcher ignores `settings.json` next to `MinEdLauncher.exe`. It only reads `%LOCALAPPDATA%\min-ed-launcher\settings.json`. Script `04-install-launcher.sh` drops the template in the correct place.

### Layout

```
ed-mac/
|-- README.md
|-- .gitignore
|-- .shellcheckrc
|-- config/
|   |-- ed-launch.env            # WINEPREFIX, paths, HUD toggle
|   \-- min-ed-launcher.json     # starter settings.json template
|-- scripts/
|   |-- _common.sh               # shared lib (colors, logging, sentinels, traps)
|   |-- 00-preflight.sh          # hardware / OS / Xcode check
|   |-- 01-install-deps.sh       # brew, Rosetta, GPTK, winetricks, jq
|   |-- 02-create-ed-prefix.sh   # Wine prefix + core runtime
|   |-- 02b-install-ed-via-steamcmd.sh   # ED install via headless SteamCMD
|   |-- 03-install-ed.sh         # ED install via Steam GUI (fallback path)
|   |-- 04-install-launcher.sh   # min-ed-launcher install + settings.json
|   |-- 04b-setup-frontier-creds.sh     # one-time credential seed
|   |-- 05-create-tools-prefix.sh       # second prefix for EDDiscovery etc.
|   |-- build-cred-helper.sh     # compile MelCredHelper.exe
|   |-- install-app-launcher.sh  # drop Elite Dangerous.command into ~/Applications
|   |-- launch-ed.sh             # day-to-day launcher
|   |-- launch-eddiscovery.sh    # launcher for the tools prefix
|   |-- launch-steam.sh          # re-open Steam GUI with Apple Silicon flags
|   \-- nuke-and-pave.sh         # full teardown
|-- tools/
|   \-- mel-cred-helper/
|       |-- MelCredHelper.csproj # .NET 8 WinExe, win-x64 self-contained
|       \-- Program.cs
\-- local/                       # gitignored scratch area for your own stuff
    \-- README.md
```

---

## Known issues

These are quirks of running ED via Wine + GPTK on macOS, not bugs in this repo.

- **VRAM leak.** Elite Dangerous leaks GPU memory under D3DMetal. After 2-4 hours framerate collapses or the game crashes. Quit to desktop (not just the main menu) and relaunch to reset. There is no clean fix, only the workaround. Lower texture quality extends your runway.
- **First-run shader stutter.** The first 10-20 minutes of play hitch while D3DMetal compiles shader pipelines (new station types, new ship types, first planetary landing). Noticeably better after one play session because the compiled shaders are cached.
- **HOTAS support.** Wine on macOS passes HID joysticks through the native macOS stack. In ED's Controls menu, move an axis; if it moves in the UI, you are fine. T.16000M, X52, X56, and Virpil sticks work without extra config.
- **Steam Big Picture / overlay.** Both unreliable inside Wine. Disable them.
- **`steamwebhelper` crashes.** Covered above: use `02b-install-ed-via-steamcmd.sh` or run the Steam GUI via `launch-steam.sh`.

---

## Troubleshooting

**`0x80131506` fatal error during launcher's "Checking for updates".** TLS handshake failing. Check `/etc/ssl/cert.pem` exists and `launch-ed.sh` is setting `SSL_CERT_FILE` (see the top of the script).

**`rosetta error: unexpectedly need to EmulateForward`.** Hardware intrinsics not being disabled. Check `DOTNET_EnableHWIntrinsic=0` is exported in `launch-ed.sh`. Also run `softwareupdate --install-rosetta --agree-to-license` to pick up the latest Rosetta.

**`Failed to find Elite Dangerous install directory` from min-ed-launcher.** The script passes the EDLaunch.exe path as argv to work around this. If you see this error, verify `EDLaunch.exe` exists at `~/Games/elite-dangerous/drive_c/Program Files (x86)/Steam/steamapps/common/Elite Dangerous/EDLaunch.exe` and that `config/ed-launch.env` points at the right prefix.

**`Format_BadBase64Char` when launcher reads the .cred file.** The cred file is malformed. Regenerate: `./scripts/04b-setup-frontier-creds.sh --force`.

**Typing in the Frontier 2FA prompt does nothing visible.** That is expected. Wine does not echo the characters but still accepts them. Type the code and press Enter. After one successful login, the machine token is saved and 2FA stops prompting.

**Wine exits immediately.** Re-run with verbose logging:
```bash
WINEDEBUG=+all ./scripts/launch-ed.sh --debug
```
Log lands in `~/Games/.ed-mac-setup/logs/`. Grep for `err:` first.

**`find_wine` returns nothing.** GPTK installed to a non-default location. Check where:
```bash
brew --prefix game-porting-toolkit
ls -la "$(brew --prefix game-porting-toolkit)/bin"
```
If you find a `wine64` there, add the path to `find_wine`'s candidate list in `scripts/_common.sh`.

**Steam will not finish updating.** Quit Steam inside Wine, then:
```bash
rm -rf ~/Games/elite-dangerous/drive_c/Program\ Files\ \(x86\)/Steam/package
```
Relaunch.

**EDDiscovery cannot find the journal.** It defaults to `%USERPROFILE%\Saved Games\Frontier Developments\Elite Dangerous`. In the prefix that is:
```
~/Games/elite-dangerous/drive_c/users/crossover/Saved Games/Frontier Developments/Elite Dangerous
```
Point EDDiscovery at that.

**Crashes that look like driver issues.** Restart first (likely VRAM leak). Then check whether macOS or GPTK got a point release.

---

## Updating

### GPTK / Wine

```bash
brew update
brew upgrade --cask gcenx/wine/game-porting-toolkit
```

Test with a short session. If something regresses, the gcenx tap tags releases so you can pin an older version.

### min-ed-launcher

```bash
rm ~/Games/.ed-mac-setup/sentinels/04-install-launcher.done
./scripts/04-install-launcher.sh
```

Your settings.json and cred file are preserved. If a min-ed-launcher release changes the cred file format, re-run `./scripts/04b-setup-frontier-creds.sh --force`.

### The credential helper

Only needed if `tools/mel-cred-helper/Program.cs` changes or if ED rotates the DPAPI salt (very rare; happens on major game patches):

```bash
./scripts/build-cred-helper.sh
./scripts/04b-setup-frontier-creds.sh --force
```

---

## Uninstall

Remove prefixes, sentinels, and cached installers but keep Homebrew + GPTK:

```bash
./scripts/nuke-and-pave.sh
```

Remove everything, including the brew casks, winetricks, jq, and the gcenx tap:

```bash
./scripts/nuke-and-pave.sh --all
```

Homebrew itself stays. To uninstall it too, see https://docs.brew.sh/FAQ#how-do-i-uninstall-homebrew.

---

## Why this stack

- **GPTK / D3DMetal**, not DXVK or MoltenVK. Apple's translator targets D3D11/12 directly to Metal and improves with every macOS point release. DXVK/MVK add a Vulkan hop that performs worse for ED.
- **SteamCMD**, not the Steam client. `steamwebhelper` is fragile on Apple Silicon.
- **Frontier auth**, not Steam auth. Once ED is installed, Steam at runtime is optional and flakiness-prone. Frontier auth needs no running Steam client.
- **min-ed-launcher**, not the Frontier launcher. The official launcher hangs on splash under Wine.
- **Two prefixes**, not one. EDDiscovery and other tools break often. Isolating them means a bad tool update never costs you the game install.
- **Native EDMarketConnector**, not the Windows build. It has a maintained .app and reads journals from the ED prefix without Wine.
- **No Whisky / Sikarugir / CrossOver.** Whisky is unmaintained as of early 2025. Sikarugir is a GUI wrapper that hides moving parts. CrossOver is paid, closed-source, and hits the same VRAM leak.

---

## Credits

- Apple, for shipping GPTK.
- [@gcenx](https://github.com/Gcenx) for the `gcenx/wine` tap.
- [@rfvgyhn](https://github.com/rfvgyhn) for [min-ed-launcher](https://github.com/rfvgyhn/min-ed-launcher).
- [EDCD](https://github.com/EDCD) for EDMarketConnector.
- [@EDDiscovery](https://github.com/EDDiscovery) for EDDiscovery.

---

## Support the work

If this saved you time, coffee money is always welcome: **[ko-fi.com/cladds](https://ko-fi.com/cladds)**.

o7 Commander.

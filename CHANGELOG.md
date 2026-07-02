# Changelog

All notable changes to Speed Up My Mac are documented here.
This project follows semantic versioning.

## [1.2.0] - 2026-07-02

The admin-rights hand-off now does the copying for you.

### Changed
- **The pending sudo command is copied to your clipboard automatically.** When a run ends with steps that need your password (freeing memory, flushing DNS, pausing Spotlight), the script now copies the joined command itself (pbcopy, built into macOS) and prints plain paste instructions: open a fresh Terminal window, paste, press Enter, type your password. It also warns that the screen shows nothing while you type the password, which trips up people who think the prompt is frozen.
- **Scheduled runs never touch your clipboard.** The weekly launch agent printed by `schedule` sets `SPEED_NO_CLIPBOARD=1`, so a background maintenance run can never overwrite something you had copied. Set the same variable to opt out of the clipboard copy anywhere else.

## [1.1.0] - 2026-07-02

Correctness fixes and four new capabilities. Fully backward compatible: every existing mode behaves the same, only safer and more useful.

### Fixed
- **Runaway-process detector no longer flags critical apps.** It used a lifetime CPU average and an "up for days" rule, which flagged `WindowServer` and `Terminal` as runaways on any long-running Mac. It now takes a live CPU sample (`top -l 2`, second sample) with a real threshold, so it only surfaces something actually pegging the CPU right now.
- **Kill suggestions never point at GUI or system-critical processes.** The review list now excludes `WindowServer`, `loginwindow`, `Terminal`, `iTerm2`, `Finder`, `Dock`, `SystemUIServer`, and `coreaudiod` (whole-word, so `Docker` is still a valid candidate).
- **Nothing is deleted automatically.** `deep` and `maintenance` used to delete Xcode `DerivedData` on their own, which contradicts the tool's own promise. DerivedData is now report-only: it shows the size and the command, and you decide.
- **`caffeinate` only touches the one this tool started.** `call` now records its own caffeinate PID and `restore` stops only that process, so it never kills a `caffeinate` you started yourself.
- **Saved Wi-Fi count returns a clean number.** A shell quirk could append a second `0` and break the arithmetic that decides whether to warn about too many saved networks.

### Added
- **Named startup-load audit.** `diagnose` and `deep` now list the auto-start helpers loading at boot by name across the user and system domains (user LaunchAgents, system LaunchAgents, system LaunchDaemons), and call out the third-party ones, instead of printing a bare count of a single folder.
- **Broader disk review in `deep`.** Now surfaces the real space eaters: `~/Library/Application Support` top items (Docker.raw, sync clients), `~/Library/Containers`, and large `node_modules` folders under your home directory.
- **Run log.** Every run appends one line (date, mode, free space) to `~/.local/state/speed/run.log` so you can see free-space and usage trends over time.
- **`schedule` mode.** Report-only: prints a ready launch agent that runs `maintenance` automatically once a week, plus the exact commands to install and remove it. Changes nothing by itself.

## [1.0.0] - 2026-06-28

Initial public release. Zero-dependency Mac speed and thermal tool with five modes (`diagnose`, `call`, `restore`, `deep`, `maintenance`), Intel and Apple Silicon aware, using only built-in macOS tools.

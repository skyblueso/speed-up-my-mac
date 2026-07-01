---
name: speed
description: Speed up and cool down any Mac (Intel or Apple Silicon), with zero dependencies. Six modes. Use "deep" for the first big cleanup (clears the backlog, frees memory, surfaces what to delete or tune) and "maintenance" for fast recurring upkeep after that. Use "call" before any Zoom, Meet, Teams, live TV, podcast, interview, or screen share to free thermal and CPU headroom so the machine does not stutter or fan-spike mid-call. Use "restore" after a call. Use "diagnose" to check state. Use "schedule" to set up automatic weekly maintenance. Triggers: "/speed", "speed up my mac", "clean up my computer", "make it run light", "maintenance", "before a call", "schedule maintenance", "my mac is hot/slow/choppy/laggy".
---

# Speed

A one-stop speed and thermal tool for any Mac. It works on both Intel and Apple Silicon, detects which one it is running on, and tailors its advice accordingly. It has zero dependencies: everything uses built-in macOS commands. Optional package-manager cache cleaning is skipped automatically when the tool is not installed.

Why two architectures matter: Intel Macs (especially the 2018 to 2020 models) run hot and throttle hard under sustained load, so a live call can make the fans spike and the video stutter. Apple Silicon Macs run cool and rarely thermal-throttle, so their wins come from quitting heavy apps and freeing memory rather than from cooling. The skill handles both.

The driver script is `speed.sh` in this folder. It takes one mode argument.

## Modes

Run with: `bash ~/.claude/skills/speed/speed.sh <mode>`

| Mode | When | What it does |
|---|---|---|
| `diagnose` | "is my mac ok", "why is it hot", "why is it slow" | Read only. Model, chip, macOS, thermal/throttle state, Low Power Mode, memory, swap, top CPU and top memory, live runaway processes, named auto-start helpers across user and system domains (third-party boot items called out by name), saved Wi-Fi count, Desktop/Trash clutter, reclaimable caches. Changes nothing. |
| `call` | **Before any live call, TV hit, podcast, interview, screen share** | Reversible. Freezes Photos and media-analysis daemons, runs caffeinate so the Mac never sleeps mid-call, pauses Spotlight and Time Machine, frees inactive memory, lists top CPU hogs to quit, prints an architecture-specific checklist. |
| `restore` | **After the call** | Idempotent. Resumes the frozen daemons, stops caffeinate, re-enables Spotlight and Time Machine. |
| `deep` | **First run**, or occasional full clean | The big one. Cleans all package-manager and system caches, excludes dev junk from Spotlight, frees memory, flushes DNS, then REPORTS runaway processes, Trash, big logs and backups, big files, saved Wi-Fi, Desktop clutter, optional UI tuning, and snapshots for a decision. It does not change settings or delete anything on its own. |
| `maintenance` | **Recurring** (weekly) | Fast repeatable upkeep. Cleans the caches that regrow, frees memory, flushes DNS, and checks for runaway processes. Skips the heavy review. Run this regularly after the first `deep`. |
| `schedule` | "run this automatically", "set it and forget it" | Report only. Prints a ready launchd job that runs `maintenance` weekly (Monday 10:00) plus the exact commands to install and remove it. Changes nothing by itself. |

Every run appends a one-line record (date, mode, free space) to `~/.local/state/speed/run.log` so trends are visible over time.

## How to run each mode

### call
1. Run `bash ~/.claude/skills/speed/speed.sh call`.
2. The script makes the reversible system changes itself. If it prints a "needs admin rights" line, hand that exact line to the user to run (in Claude Code, paste with a leading `!`; in a terminal, run it directly). Never type a password.
3. Read back the top-CPU list. If something heavy is open that the user does not need on the call (a browser with many tabs, a render, Docker, a large IDE), offer to quit it. Never quit the call app itself or work they need.
4. Surface the checklist it printed. On Intel the physical wins (elevate the laptop, airflow, Low Power Mode) matter most; on Apple Silicon the wins are network and quitting heavy apps.
5. Remind the user to run `/speed restore` when the call ends.

### restore
Run `bash ~/.claude/skills/speed/speed.sh restore`. Hand off any "needs admin rights" line the same way. Confirm everything is back on.

### deep
1. Run `bash ~/.claude/skills/speed/speed.sh deep`. The automatic part (cache cleaning, Spotlight exclusions, freeing memory, DNS flush) is safe and runs on its own. It does NOT change any setting or delete anything by itself; those are only reported.
2. The script then prints REVIEW sections. These are NOT auto-applied. Present them with the **Premium review flow** above: turn each category into a checkbox menu (AskUserQuestion, multiSelect) and act only on what the user ticks. Use this guidance for what to recommend in each option's description:
   - **Runaway processes**: show the full command line. Never kill anything you do not recognize, an app the user is using, or background helpers (claude, mcp, node/python servers they started). A script pegging high CPU with an old start time is the usual culprit. Kill with `kill -9 <pid>` only after the user confirms.
   - **Big installers / files in Downloads and Desktop**: list them, confirm, then delete. Never delete anything not listed first. Skip anything that looks like the user's work or assets.
   - **Browser-automation caches (ms-playwright, puppeteer)**: deleting these breaks Playwright/Puppeteer until reinstall. Only clear if the user says so.
   - **Local Time Machine snapshots**: if many exist and purgeable space is tight, offer `tmutil thinlocalsnapshots / 9999999999 4`, with any admin step handed to the user.
3. Report before/after disk and load.

### maintenance
Run `bash ~/.claude/skills/speed/speed.sh maintenance`. This is the recurring pass: it cleans the caches that regrow, frees memory, flushes DNS, and lists any runaway processes. It does NOT do the heavy review. If it surfaces a runaway process or a non-empty Trash, present those with the **Premium review flow** (a checkbox menu), never a prose "kill this?". Suggest the user run this weekly, and run `deep` only occasionally.

**First run vs upkeep:** the first time on a machine, run `deep` to clear the backlog and see the full review. After that, `maintenance` keeps it light week to week.

## What runs automatically vs what needs the user's OK

This is the core contract. Hold to it.

**Runs automatically (safe, reversible, no data loss, no visible change):** cleaning package-manager and QuickLook caches (they refetch on demand), excluding dev caches from Spotlight indexing, freeing inactive memory, flushing DNS. These do not matter if undone, so they just run.

**Always ask first. The script only REPORTS these; never act without the user confirming:**
- Killing any process. Even an obvious runaway gets confirmed first, and you never kill an app the user is using or a render/build in progress.
- Deleting any file: Trash, Downloads, Desktop, logs, old iPhone backups.
- Removing purgeable space or Time Machine snapshots.
- Changing any visible setting: transparency, motion, animations (the script prints the commands; apply only if the user says yes).
- Pruning saved Wi-Fi networks.

The rule of thumb the user gave: if it does not really matter, just do it; if it kills, deletes, or changes something, ask first.

## Premium review flow (how to present every "keep or remove" decision)

Never dump the candidate lists as plain text and ask "do you want to keep this?" in prose. Present them as clean, clickable checkbox menus using the AskUserQuestion tool with `multiSelect: true`, so the user just ticks what to act on. This is the whole premium feel of the skill: tap checkmarks, done.

How to build the menus from a `deep` or `maintenance` run:

1. Group the candidates by category. Make ONE multiSelect question per category that actually has items:
   - "Delete these files?" (big Downloads/Desktop files, Trash, large logs, old iPhone backups)
   - "Quit these processes?" (only genuine runaways: a full core or more, or days-old and active)
   - "Reclaim this space?" (Time Machine snapshots / purgeable space)
   - "Trim background load?" (prune saved Wi-Fi networks)
   - "Apply optional UI tuning?" (reduce transparency / motion / animations)
2. Each option is one item. Keep the label short and human: the filename plus its size (for example `instagram-brodsky-2026-05-15.zip  (834M)`), or the process name plus CPU and age. Put the reasoning in the option description (for example "Old installer, safe to delete" or "Active Remotion render, leave it").
3. Nothing is pre-checked. The user opts in by ticking. State your recommendation in each option's description so the choice is easy.
4. AskUserQuestion allows up to 4 options per question and up to 4 questions per call. If a category has more than 4 items, show the 4 biggest or most relevant, and tell the user in your message how many more there are and that you can show the rest in a follow-up menu.
5. After the menus return, act ONLY on the checked items, using the safe command for each (`rm` for files, `kill` then `kill -9` if needed for processes, `tmutil thinlocalsnapshots` for snapshots, the `defaults write` lines for UI tuning, `networksetup -removepreferredwirelessnetwork` for Wi-Fi). The checkmark IS the confirmation; do not ask again in prose.
6. Hard guards still apply: never put an app the user is using, an active render/build, or anything unrecognized into a "quit" menu; never put documents, project assets, or unlisted files into a "delete" menu.

After acting, give a short, clean summary of what was removed and the space or CPU freed.

## Safety rules (do not violate)
- Never kill `claude`, `mcp`, MCP servers, or the app the user is actively using.
- Never delete a file you have not listed to the user first. Documents, project assets, and anything unrecognized are off limits.
- Never touch the iCloud daemons `bird` or `cloudd`. Suspending them risks stuck sync loops. If iCloud is hammering the CPU, tell the user to pause iCloud Drive in System Settings.
- Never run `mdutil -E` (erases the Spotlight index) or `tmutil disablelocal` (deprecated). The script does not; do not add them.
- You cannot type the user's password. Steps needing admin rights are handed back for the user to run.

## Recommendations to surface (not automated)
These are levers beyond what a script can safely do. Mention the relevant ones based on the detected architecture.

**Intel Macs (run hot, throttle under load):**
- **Low Power Mode** (System Settings > Battery). On Intel it caps Turbo Boost and cuts heat sharply. Free, and the single best built-in fix for call thermals.
- **Turbo Boost Switcher Pro** (paid, signed). Caps the CPU at base clock above a temperature threshold so it never spike-throttles. The strongest software fix for hot Intel models.
- **Macs Fan Control** (free) or **TG Pro** (paid). Ramp the fans earlier so the CPU is pre-cooled before it hits the throttle point.
- **Dust the fans and repaste** with a quality thermal compound. Owners of hot 2019/2020 models report large temperature drops. Highest-impact hardware fix.
- **Elevate on a stand, hard flat surface, fewer peripherals.** Free and real.

**Apple Silicon Macs (run cool):**
- Thermal tools are rarely needed. Focus on quitting heavy apps, freeing memory, and a stable network for calls.
- Plug into AC power for long sustained workloads or calls.

## Notes
- On Intel, disk and idle RAM are usually not the bottleneck; heat under sustained load is. Tune for thermal headroom. On Apple Silicon, the wins are memory pressure and runaway processes.
- `diagnose` is always safe to run first. Start there when the symptom is unclear.

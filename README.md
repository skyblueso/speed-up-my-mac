# Speed Up My Mac

![Speed Up My Mac](banner.png)

Hey. Is your Mac slow? Hot? Are the fans spinning up like a tiny jet engine every time you join a Zoom call?

Try this. It will probably clean up some space, cool the thing down, and hand you back some speed you did not even know you lost.

Here is the quiet truth about Macs: they hoard junk, and nobody tells you.

- Every Wi-Fi network you have ever joined is saved, and your Mac keeps scanning for all of them. Forever. Even when you are plugged into ethernet. The first time we ran this on a real machine it found 72 saved networks the laptop was quietly hunting for around the clock.
- Package-manager and app caches that just keep growing. That same first run cleaned up 16 GB of cache that had been sitting there doing nothing.
- A runaway process pinning a CPU core. We once found a script that had been stuck at 99 percent for FIVE DAYS, orphaned, slowly cooking the machine while the fans screamed and nobody knew why.
- Your memory quietly spilling onto the disk (swap) because nothing ever got freed, which makes everything feel sluggish even with apps closed.
- "Purgeable space" squatting on your drive for who knows how long. It looks free. It is not. You can absolutely get rid of it.
- Old installers in Downloads, and a Desktop with a hundred icons quietly taxing your graphics card every time you look at it.

All of it, just sitting there, slowing you down. This finds it and helps you clean it up. No app to buy. No subscription. No dependencies. It uses only the tools already built into macOS, and you can read the whole thing in two minutes.

Works on every Mac, Intel and Apple Silicon. It even knows the difference: Intel Macs run hot, so it leans on cooling; Apple Silicon runs cool, so it leans on memory and clutter.

## What it does

| Mode | When | What it does |
|---|---|---|
| `diagnose` | "why is my Mac hot or slow?" | Read only. Tells you exactly what is going on: heat, throttling, memory, live runaway processes, the auto-start helpers loading at boot (named, not just counted), saved Wi-Fi, clutter, reclaimable space. Touches nothing. |
| `deep` | The first big clean | Clears the junk that piled up, frees memory, flushes caches, then hands you a checklist of the bigger stuff to review (now including Application Support, Containers, and large node_modules folders). |
| `maintenance` | Weekly, going forward | The quick recurring pass. Cleans what regrows and flags anything pegging your CPU. In and out. |
| `call` | Right before a Zoom / Meet / Teams / live anything | Frees up heat and CPU so the fans do not spike and the video does not stutter mid-call. Fully reversible. |
| `restore` | After the call | Puts everything back the way it was. |
| `schedule` | "just run it for me" | Report only. Prints a ready launch agent that runs `maintenance` automatically every week, plus the exact commands to install and remove it. Changes nothing on its own. |

## The best part: it never nukes anything behind your back

The harmless stuff (caches that just redownload, freeing up memory) it handles on its own. Anything that actually matters (deleting a file, quitting a process, changing a setting) it shows you a list and **you tick the checkboxes** for what goes. Your files stay your files. Nothing gets deleted, quit, or changed without you saying so.

## Install

**The easy way (in Claude Code):** drop this folder at `~/.claude/skills/speed/` and just say "speed up my mac." Done.

**Standalone:** clone it and run the script.

```bash
git clone https://github.com/skyblueso/speed-up-my-mac
bash speed-up-my-mac/speed.sh diagnose
```

## Usage

```bash
bash speed.sh diagnose     # see what is going on (start here, it changes nothing)
bash speed.sh deep         # the big first clean
bash speed.sh maintenance  # the quick weekly tidy
bash speed.sh call         # before a live call
bash speed.sh restore      # after the call
bash speed.sh schedule     # print a weekly auto-maintenance job to install
```

Every run appends one line (date, mode, free space) to `~/.local/state/speed/run.log`, so you can watch the trend over time.

A couple of steps need admin rights (pausing Spotlight, freeing memory). In a terminal it just asks for your password the normal way. In Claude Code it hands you the exact line to run. It never sees or stores your password.

## Is this safe?

Yes, and you do not have to take my word for it. It is one commented shell script. Read it. It never deletes a file without showing it to you first, never kills an app you are using, and never touches your iCloud. The cautious-by-default design is the whole point.

## License

MIT. Use it, share it, fork it. See [LICENSE](LICENSE).

Built by [Simcha Brodsky](https://github.com/skyblueso) ([@simchabrodsky](https://x.com/simchabrodsky)).

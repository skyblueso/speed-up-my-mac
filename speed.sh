#!/usr/bin/env bash
# speed.sh: one-stop speed and thermal tool for any Mac (Intel or Apple Silicon).
#
# Modes:
#   diagnose     read-only health: thermal, CPU, memory/swap, background load, clutter, space
#   call         reversible: free thermal/CPU headroom before a live call or screen share
#   restore      undo everything 'call' changed
#   deep         FIRST RUN / occasional: full cleanup + one-time OS tuning + review report
#   maintenance  RECURRING: fast, repeatable cleanup (caches, memory, runaway-process check)
#   schedule     report-only: print a launchd job to run 'maintenance' weekly, plus how to install it
#
# Every run appends a one-line record to ~/.local/state/speed/run.log so you can
# see free-space and usage trends over time.
#
# Use 'deep' once to clear the backlog and tune the OS. Use 'maintenance' weekly
# to keep it light. 'deep' includes everything 'maintenance' does, plus the
# one-time tuning and the full review of what to delete.
#
# Zero dependencies: built-in macOS tools only (sysctl, pmset, ps, df, du, mdutil,
# tmutil, caffeinate, purge, defaults, killall, networksetup, dscacheutil, qlmanage).
# Package-manager cache cleaning is skipped when the tool is not installed.
#
# Safety principle: only reversible, no-loss, invisible actions run automatically
# (cache cleaning, Spotlight exclusions, freeing memory, DNS flush). Anything that
# kills a process, deletes a file, removes purgeable space/snapshots, or changes a
# visible setting is only REPORTED for review, never done automatically.

set -uo pipefail

MODE="${1:-diagnose}"
HR="------------------------------------------------------------"

# PID file so 'restore' only stops a caffeinate THIS script started, never the
# user's own intentional caffeinate.
CAFFEINATE_PIDFILE="${TMPDIR:-/tmp}/speed_sh_caffeinate.pid"

# ----------------------------------------------------------------------
# Machine detection (drives architecture-specific advice)
# ----------------------------------------------------------------------
ARCH="$(uname -m)"
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ] || [ "$ARCH" = "arm64" ]; then
  CHIP_KIND="apple"   # Apple Silicon (M-series)
else
  CHIP_KIND="intel"
fi
MODEL="$(sysctl -n hw.model 2>/dev/null)"
CPU="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
OSVER="$(sw_vers -productVersion 2>/dev/null)"

# ----------------------------------------------------------------------
# sudo handling: never type a password for the user. If a sudo credential is
# cached, run it. If we are in an interactive terminal, let sudo prompt.
# Otherwise collect the command and print it for the user to run.
# ----------------------------------------------------------------------
PENDING_SUDO=()

run_sudo() {
  local desc="$1"; shift
  if sudo -n true 2>/dev/null; then
    sudo "$@" && echo "  done: $desc"
  elif [ -t 0 ]; then
    if sudo "$@"; then echo "  done: $desc"; else echo "  skipped (no password): $desc"; fi
  else
    PENDING_SUDO+=("$*")
    echo "  needs admin rights: $desc"
  fi
}

flush_pending_sudo() {
  if [ "${#PENDING_SUDO[@]}" -gt 0 ]; then
    echo ""
    echo "$HR"
    echo "STEPS THAT NEED ADMIN RIGHTS. Run this to finish:"
    echo "  (in Claude Code, paste it with a leading !   in a terminal, just run it)"
    echo ""
    local joined=""
    for c in "${PENDING_SUDO[@]}"; do
      if [ -z "$joined" ]; then joined="sudo $c"; else joined="$joined && sudo $c"; fi
    done
    echo "  $joined"
    echo "$HR"
  fi
}

# ----------------------------------------------------------------------
# Small probes (built-in tools only)
# ----------------------------------------------------------------------
wifi_iface() {
  networksetup -listallhardwareports 2>/dev/null \
    | awk '/Wi-Fi|AirPort/{getline; print $2; exit}'
}

saved_wifi_count() {
  local ifc count; ifc="$(wifi_iface)"
  [ -z "$ifc" ] && { echo "0"; return; }
  # grep -vc prints 0 AND exits nonzero when nothing matches, so a trailing
  # `|| echo 0` used to append a SECOND 0 ("0\n0") and break later arithmetic.
  # Capturing into a variable takes just the clean count (exit status ignored).
  count="$(networksetup -listpreferredwirelessnetworks "$ifc" 2>/dev/null \
    | grep -vc "Preferred networks")"
  # Keep only the first line and strip non-digits, then default to 0.
  count="$(printf '%s\n' "$count" | head -n1 | tr -cd '0-9')"
  echo "${count:-0}"
}

dir_size() { [ -e "$1" ] && du -sh "$1" 2>/dev/null | cut -f1 || echo "0B"; }

print_thermal() {
  local limit
  limit="$(pmset -g therm 2>/dev/null | awk -F'= ' '/CPU_Speed_Limit/{gsub(/ /,"",$2);print $2}')"
  if [ -n "$limit" ]; then
    if [ "$limit" -lt 100 ] 2>/dev/null; then
      echo "  CPU speed limit: ${limit}% (BELOW 100 = actively throttling, held back by heat or power)"
    else
      echo "  CPU speed limit: 100% (no throttling right now)"
    fi
  elif [ "$CHIP_KIND" = "apple" ]; then
    echo "  Apple Silicon: no CPU speed limit reported. These chips run cool and rarely thermal-throttle."
  else
    echo "  No CPU speed limit reported (not throttling, or unsupported on this model)."
  fi
  echo "  Low Power Mode: $(pmset -g 2>/dev/null | awk '/lowpowermode/{print ($2==1?"ON":"off")}')"
}

# ----------------------------------------------------------------------
# Shared cleanup building blocks (used by both 'deep' and 'maintenance')
# ----------------------------------------------------------------------
clean_pkg_caches() {
  command -v uv   >/dev/null 2>&1 && { uv cache clean        >/dev/null 2>&1 && echo "  cleaned: uv cache"; }
  command -v npm  >/dev/null 2>&1 && { npm cache clean --force >/dev/null 2>&1 && echo "  cleaned: npm cache"; }
  command -v pnpm >/dev/null 2>&1 && { pnpm store prune      >/dev/null 2>&1 && echo "  cleaned: pnpm store"; }
  command -v yarn >/dev/null 2>&1 && { yarn cache clean      >/dev/null 2>&1 && echo "  cleaned: yarn cache"; }
  command -v pip3 >/dev/null 2>&1 && { pip3 cache purge      >/dev/null 2>&1 && echo "  cleaned: pip cache"; }
  command -v brew >/dev/null 2>&1 && { brew cleanup -s       >/dev/null 2>&1 && echo "  cleaned: Homebrew"; }
  command -v go   >/dev/null 2>&1 && { go clean -cache       >/dev/null 2>&1 && echo "  cleaned: Go build cache"; }
  # Report-only: never auto-delete DerivedData (SKILL.md: nothing is deleted
  # automatically). Show what could be freed and how to clear it by hand.
  [ -d "$HOME/Library/Developer/Xcode/DerivedData" ] && echo "  review (not deleted): Xcode DerivedData is $(dir_size "$HOME/Library/Developer/Xcode/DerivedData"); clear it yourself with: rm -rf ~/Library/Developer/Xcode/DerivedData/*"
  qlmanage -r cache >/dev/null 2>&1 && echo "  flushed: QuickLook thumbnail cache"
}

free_mem_flush() {
  run_sudo "free inactive memory"  purge
  run_sudo "flush DNS cache"       dscacheutil -flushcache
}

# A runaway is a process burning real CPU right now (roughly half a core or
# more). We take a LIVE sample with `top -l 2` and read ONLY the second sample:
# the first top sample reports a useless cumulative figure on macOS. A long
# uptime is NOT a runaway, so elapsed time is deliberately ignored here.
find_runaways() {
  top -l 2 -n 20 -stats pid,cpu,command -o cpu 2>/dev/null \
    | awk -v thresh=50 '
        /^Processes:/ { sample++; rows=0; next }
        sample >= 2 && /^PID/ { rows=1; next }
        sample >= 2 && rows && $1 ~ /^[0-9]+$/ && $2+0 > thresh { print }
      ' \
    | grep -viwE "top|grep|awk"
}

report_runaway() {
  echo "  A process pegging the CPU (a full core or more), or running for days, is the usual culprit."
  echo "  NEVER kill anything you do not recognize, an app you're using, or helpers you started"
  echo "  (claude, mcp, node/python servers, or an active render)."
  # Never offer to kill our own helpers (claude/mcp) or GUI/system-critical
  # processes. The second grep uses -w (whole word) so "Dock" does not also
  # shield "Docker", which is a legitimate kill candidate.
  local hits; hits="$(find_runaways \
    | grep -viE "claude|mcp" \
    | grep -viwE "WindowServer|loginwindow|Terminal|iTerm2|Finder|Dock|SystemUIServer|coreaudiod" \
    | head -6)"
  [ -n "$hits" ] && echo "$hits" | sed 's/^/  /' || echo "  nothing pegging the CPU right now (good)"
}

# Auto-start helpers are the usual hidden cause of a slow login and steady
# background CPU. Apple's own agents are fine; the ones that pile up are
# third-party LaunchAgents and LaunchDaemons (updaters, sync clients, helpers).
# We list them BY NAME across the user and system domains, not just a bare count.
report_startup_load() {
  local detail="${1:-brief}"
  local ua sa sd
  ua="$(ls -1 "$HOME/Library/LaunchAgents"/*.plist 2>/dev/null | wc -l | tr -d ' ')"
  sa="$(ls -1 /Library/LaunchAgents/*.plist 2>/dev/null | wc -l | tr -d ' ')"
  sd="$(ls -1 /Library/LaunchDaemons/*.plist 2>/dev/null | wc -l | tr -d ' ')"
  echo "  auto-start helpers: $ua user agents, $sa system agents, $sd system daemons"
  # The third-party system agents and daemons are the real slowdown suspects
  # (they load at boot for every user). Apple's own com.apple.* are expected.
  local third n
  third="$( { ls -1 /Library/LaunchAgents/*.plist /Library/LaunchDaemons/*.plist 2>/dev/null; } \
    | sed 's#.*/##; s#\.plist$##' | grep -viE '^com\.apple\.' | sort -u )"
  if [ -n "$third" ]; then
    n="$(printf '%s\n' "$third" | wc -l | tr -d ' ')"
    echo "  third-party system helpers ($n) loading at boot:"
    if [ "$detail" = full ]; then
      printf '%s\n' "$third" | sed 's/^/    /'
    else
      printf '%s\n' "$third" | head -8 | sed 's/^/    /'
      [ "$n" -gt 8 ] 2>/dev/null && echo "    ... and $((n-8)) more (see them all with: /speed deep)"
    fi
  else
    echo "  third-party system helpers: none (clean)"
  fi
  # User-account auto-start items you or an app added (shown in full detail).
  if [ "$detail" = full ]; then
    local uthird
    uthird="$(ls -1 "$HOME/Library/LaunchAgents"/*.plist 2>/dev/null \
      | sed 's#.*/##; s#\.plist$##' | grep -viE '^com\.apple\.' | sort -u)"
    if [ -n "$uthird" ]; then
      echo "  your user auto-start items:"
      printf '%s\n' "$uthird" | sed 's/^/    /'
    fi
  fi
}

# Append a one-line record of every run so trends are visible over time
# (free space and mode). Writes only to its own state dir, never fails the run.
log_run() {
  local logdir="$HOME/.local/state/speed"
  mkdir -p "$logdir" 2>/dev/null || return 0
  local free; free="$(df -h / 2>/dev/null | awk 'NR==2{print $4}')"
  printf '%s\t%-11s\tfree=%s\n' "$(date '+%Y-%m-%d %H:%M')" "$MODE" "${free:-?}" \
    >> "$logdir/run.log" 2>/dev/null || true
}

# ----------------------------------------------------------------------
diagnose() {
  echo "$HR"; echo "SPEED DIAGNOSE  $(date '+%Y-%m-%d %H:%M')"; echo "$HR"
  echo "MAC: $MODEL  /  ${CPU:-unknown CPU}  /  macOS $OSVER  ($([ "$CHIP_KIND" = apple ] && echo 'Apple Silicon' || echo 'Intel'))"
  local up; up="$(uptime)"; echo "UPTIME: ${up#*up }"

  echo ""
  echo "THERMAL:"
  print_thermal

  echo ""
  echo "MEMORY & SWAP:"
  echo "  free: $(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{print $2}')"
  echo "  swap: $(sysctl -n vm.swapusage 2>/dev/null | sed 's/^ *//')"
  echo "  (heavy swap use or many days of uptime means a reboot is the cleanest fix)"

  echo ""
  echo "TOP CPU NOW:"
  ps -Ao pcpu,pid,comm -r | grep -viE "/top$| ps$|grep|awk" | head -6 | sed 's/^/  /'
  echo "TOP MEMORY NOW:"
  ps -Ao pmem,rss,pid,comm -m | grep -viE "grep|awk" | head -6 | sed 's/^/  /'

  echo ""
  echo "BACKGROUND & STARTUP LOAD (the usual hidden cause of slowness):"
  echo "  runaway processes (a full core or more pegged now, or running for days with real CPU):"
  local runaway; runaway="$(find_runaways | head -5)"
  [ -n "$runaway" ] && echo "$runaway" | sed 's/^/    /' || echo "    none found (good)"
  report_startup_load brief
  echo "  saved Wi-Fi networks: $(saved_wifi_count)  (a large number makes Wi-Fi scanning burn CPU when not connected)"

  echo ""
  echo "CLUTTER (render and indexing load):"
  echo "  Desktop items: $(ls -1 ~/Desktop 2>/dev/null | wc -l | tr -d ' ')  (a packed Desktop slows Finder and WindowServer; turn on Stacks)"
  echo "  Trash: $(dir_size ~/.Trash)"

  echo ""
  echo "DISK: $(df -h / | awk 'NR==2{print $4" free of "$2}')"
  echo "RECLAIMABLE DEV CACHES (cleaned by 'deep'/'maintenance', they refetch on demand):"
  local found=0
  for d in ~/.cache/uv ~/.npm/_cacache "$HOME/Library/Caches/pip" \
           "$HOME/Library/Caches/ms-playwright" ~/.cache/puppeteer \
           "$HOME/Library/Developer/Xcode/DerivedData" ~/.gradle/caches ~/.cocoapods; do
    if [ -e "$d" ]; then echo "  $(du -sh "$d" 2>/dev/null | cut -f1)  $d"; found=1; fi
  done
  [ "$found" = 0 ] && echo "  (none found)"
  echo "$HR"
}

# ----------------------------------------------------------------------
# Stop ONLY the caffeinate this script launched (tracked by PID file). Returns 0
# if it stopped one, nonzero otherwise. Never touches a caffeinate we did not
# start, so the user's own intentional caffeinate is always left alone.
stop_our_caffeinate() {
  local pid
  [ -f "$CAFFEINATE_PIDFILE" ] || return 1
  pid="$(cat "$CAFFEINATE_PIDFILE" 2>/dev/null)"
  rm -f "$CAFFEINATE_PIDFILE" 2>/dev/null
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;   # missing or not a clean PID: nothing to do
  esac
  # Only kill it if that PID is still actually a caffeinate process (guards
  # against the PID having been recycled to some unrelated process).
  if ps -p "$pid" -o comm= 2>/dev/null | grep -q "caffeinate"; then
    kill "$pid" 2>/dev/null && return 0
  fi
  return 1
}

# ----------------------------------------------------------------------
call_mode() {
  echo "$HR"; echo "SPEED CALL MODE: freeing headroom for a live call (reversible)"; echo "$HR"

  echo "Freezing background analysis daemons (Photos / media scan):"
  if killall -STOP photoanalysisd 2>/dev/null; then echo "  frozen: photoanalysisd"; else echo "  photoanalysisd not running (fine)"; fi
  if killall -STOP mediaanalysisd 2>/dev/null; then echo "  frozen: mediaanalysisd"; else echo "  mediaanalysisd not running (fine)"; fi

  echo "Keeping the Mac awake for the call (no sleep, no display nap):"
  stop_our_caffeinate >/dev/null 2>&1   # clear only a stale one we started before
  nohup caffeinate -dimsu >/dev/null 2>&1 &
  CAFF_PID=$!
  disown 2>/dev/null || true
  echo "$CAFF_PID" > "$CAFFEINATE_PIDFILE" 2>/dev/null || true
  echo "  caffeinate running (pid $CAFF_PID)"

  echo "Pausing Spotlight indexing and Time Machine, freeing inactive memory:"
  run_sudo "Spotlight indexing off"        mdutil -i off / >/dev/null
  run_sudo "Time Machine auto-backup off"  tmutil disable
  run_sudo "purge inactive memory"         purge

  echo ""
  echo "TOP CPU RIGHT NOW. Quit anything heavy you do not need on the call:"
  ps -Ao pcpu,pid,comm -r | grep -viE "/top$|grep|awk|caffeinate" | head -5 | sed 's/^/  /'

  echo ""
  echo "$HR"
  echo "MANUAL WINS for the next few minutes:"
  echo "  1. Close every browser tab except the call, or quit the browser. Browser GPU and video calls fight for the same resources."
  echo "  2. In your video app (Zoom/Meet/Teams): turn OFF HD video, touch-up/retouch, virtual background, and noise suppression. Keep hardware acceleration ON."
  echo "  3. Quit anything you are not using on the call: other browsers, Docker, renders, large IDEs, photo/video editors."
  if [ "$CHIP_KIND" = "intel" ]; then
    echo "  4. Elevate the laptop so air can reach the bottom. Use a hard flat surface, not a lap or bed. Intel Macs run hot and need airflow."
    echo "  5. Turn ON Low Power Mode (System Settings > Battery). On Intel it caps Turbo Boost and cuts heat sharply for calls."
    echo "  6. Unplug extra peripherals and external displays if you can."
  else
    echo "  4. Apple Silicon runs cool, so software heat is rarely the issue. The wins are a stable network and quitting heavy apps."
    echo "  5. If you are on battery, plug in. Sustained calls are smoother on AC power."
  fi
  echo "$HR"
  echo "After the call run:  /speed restore"
  flush_pending_sudo
}

# ----------------------------------------------------------------------
restore_mode() {
  echo "$HR"; echo "SPEED RESTORE: turning background services back on"; echo "$HR"
  killall -CONT photoanalysisd 2>/dev/null && echo "  resumed: photoanalysisd" || echo "  photoanalysisd already running"
  killall -CONT mediaanalysisd 2>/dev/null && echo "  resumed: mediaanalysisd" || echo "  mediaanalysisd already running"
  if stop_our_caffeinate; then
    echo "  stopped: caffeinate this script started (sleep allowed again)"
  else
    echo "  no caffeinate started by this script (any of your own is left running)"
  fi
  run_sudo "Spotlight indexing on"        mdutil -i on / >/dev/null
  run_sudo "Time Machine auto-backup on"  tmutil enable
  echo "Everything 'call' changed is restored."
  flush_pending_sudo
}

# ----------------------------------------------------------------------
# maintenance: fast, repeatable. Run this weekly. No one-time OS tweaks,
# no heavy review. Just reclaim the stuff that regrows and check for runaways.
# ----------------------------------------------------------------------
maintenance_mode() {
  echo "$HR"; echo "SPEED MAINTENANCE: quick repeatable cleanup"; echo "$HR"
  local before; before=$(df -h / | awk 'NR==2{print $4}')

  echo "1. Cleaning caches that regrow (refetch on demand, zero risk):"
  clean_pkg_caches

  echo ""
  echo "2. Freeing memory and flushing DNS (needs admin rights):"
  free_mem_flush

  local after; after=$(df -h / | awk 'NR==2{print $4}')
  echo ""
  echo "Free space: $before -> $after"

  echo ""
  echo "$HR"
  echo "RUNAWAY / heavy processes to review (the recurring slowdown cause):"
  report_runaway
  echo ""
  echo "Trash: $(dir_size ~/.Trash)   (empty in Finder, or: rm -rf ~/.Trash/*)"
  echo ""
  echo "For a full clean (one-time OS tuning + big-file review) run:  /speed deep"
  echo "$HR"
  flush_pending_sudo
}

# ----------------------------------------------------------------------
# deep: first-run / occasional. Everything maintenance does, PLUS one-time OS
# tuning and a full review of what to delete.
# ----------------------------------------------------------------------
deep_clean() {
  echo "$HR"; echo "SPEED DEEP: full cleanup, one-time tuning, and review (good for the first run)"; echo "$HR"
  local before; before=$(df -h / | awk 'NR==2{print $4}')

  echo "1. Cleaning package-manager and system caches (refetch on demand, zero risk):"
  clean_pkg_caches

  echo ""
  echo "2. Excluding dev junk from Spotlight (invisible, reversible, stops reindex CPU/heat):"
  for d in ~/.npm ~/.cache ~/.local/share/uv ~/.local/share/pnpm \
           "$HOME/Library/Caches/ms-playwright" ~/.cache/puppeteer ~/.gradle/caches; do
    [ -d "$d" ] && touch "$d/.metadata_never_index" 2>/dev/null && echo "  excluded: $d"
  done

  echo ""
  echo "3. Freeing memory and flushing DNS (no data loss, needs admin rights):"
  free_mem_flush

  local after; after=$(df -h / | awk 'NR==2{print $4}')
  echo ""
  echo "Free space: $before -> $after"

  echo ""
  echo "$HR"
  echo "REVIEW THESE (not auto-deleted, decide for each):"

  echo ""
  echo "RUNAWAY / heavy processes (kill candidates, never blind-kill):"
  report_runaway

  echo ""
  echo "EMPTY THE TRASH? current size: $(dir_size ~/.Trash)  (empty in Finder, or: rm -rf ~/.Trash/*)"

  echo ""
  echo "BIG SPACE EATERS to review:"
  echo "  user logs:          $(dir_size ~/Library/Logs)   (safe to clear: ~/Library/Logs)"
  [ -d "$HOME/Library/Application Support/MobileSync/Backup" ] && \
    echo "  old iPhone backups: $(dir_size "$HOME/Library/Application Support/MobileSync/Backup")   (manage in Finder/Apple Devices)"
  echo "  big caches (ms-playwright/puppeteer break browser automation until reinstall):"
  du -sh ~/Library/Caches/* 2>/dev/null | sort -rh | head -5 | sed 's/^/    /'
  echo "  Application Support (apps keep data and caches here; Docker.raw and sync clients get huge):"
  du -sh ~/Library/Application\ Support/* 2>/dev/null | sort -rh | head -5 | sed 's/^/    /'
  echo "  Containers (sandboxed app data): $(dir_size ~/Library/Containers)"
  echo "  large node_modules folders under home (safe to delete; restore with npm/yarn install; may take a moment):"
  find "$HOME" -maxdepth 4 -type d -name node_modules -prune 2>/dev/null | while read -r nm; do
    echo "$(du -sh "$nm" 2>/dev/null | cut -f1)  $nm"
  done | sort -rh | head -6 | sed 's/^/    /'

  echo ""
  echo "BIG installers / files in Downloads and Desktop (delete candidates):"
  find ~/Downloads ~/Desktop -maxdepth 2 -type f \( -iname "*.dmg" -o -iname "*.pkg" -o -size +500M \) 2>/dev/null | while read -r f; do
    echo "  $(du -sh "$f" 2>/dev/null | cut -f1)  $f"
  done | head -15

  echo ""
  echo "BACKGROUND LOAD to trim:"
  local wc; wc="$(saved_wifi_count)"
  echo "  saved Wi-Fi networks: $wc"
  if [ "$wc" -gt 10 ] 2>/dev/null; then
    echo "    that is a lot; each one gets scanned. Prune in System Settings > Wi-Fi > Advanced, or:"
    echo "    sudo networksetup -removepreferredwirelessnetwork \"$(wifi_iface)\" \"NETWORK NAME\""
  fi
  report_startup_load full
  echo "  Desktop items: $(ls -1 ~/Desktop 2>/dev/null | wc -l | tr -d ' ')  (right-click Desktop > Use Stacks to cut render load, no files moved)"

  echo ""
  echo "LOCAL Time Machine snapshots (eat 'purgeable' space; thin with: tmutil thinlocalsnapshots / 9999999999 4):"
  echo "  count: $(tmutil listlocalsnapshots / 2>/dev/null | grep -c snapshot)"

  echo ""
  echo "OPTIONAL UI tuning (changes how the Mac looks; apply ONLY if you want it):"
  echo "  Reduces transparency and animation, which helps older Macs and integrated GPUs."
  echo "  To apply:"
  echo "    defaults write com.apple.universalaccess reduceTransparency -bool true"
  echo "    defaults write com.apple.universalaccess reduceMotion -bool true"
  echo "    defaults write com.apple.dock expose-animation-duration -float 0.1"
  echo "    defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false"
  echo "  To undo: replace 'write ... value' with 'delete', or toggle in System Settings > Accessibility > Display."
  echo "$HR"
  flush_pending_sudo
}

# ----------------------------------------------------------------------
# schedule: report-only. Print a ready launchd job that runs 'maintenance'
# weekly, plus the exact commands to install and remove it. Changes nothing.
# ----------------------------------------------------------------------
schedule_mode() {
  local plist="$HOME/Library/LaunchAgents/com.speed.maintenance.plist"
  local script; script="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
  echo "$HR"; echo "SPEED SCHEDULE: weekly automatic maintenance (report-only, nothing is changed)"; echo "$HR"
  echo "To run 'maintenance' by itself every week, save this launch agent and load it."
  echo "Copy-paste the whole block:"
  echo ""
  echo "  mkdir -p \"$HOME/.local/state/speed\" \"$HOME/Library/LaunchAgents\""
  echo "  cat > \"$plist\" <<'PLIST'"
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.speed.maintenance</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$script</string>
    <string>maintenance</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$HOME/.local/state/speed/maintenance.log</string>
  <key>StandardErrorPath</key><string>$HOME/.local/state/speed/maintenance.log</string>
</dict>
</plist>
PLIST
  echo "  PLIST"
  echo "  launchctl load \"$plist\""
  echo ""
  echo "It runs 'maintenance' every Monday at 10:00 and logs to ~/.local/state/speed/maintenance.log"
  echo "To stop and remove it:  launchctl unload \"$plist\" && rm \"$plist\""
  echo "$HR"
}

case "$MODE" in
  diagnose)        diagnose; log_run ;;
  call)            call_mode; log_run ;;
  restore)         restore_mode; log_run ;;
  maintenance|tidy) maintenance_mode; log_run ;;
  deep)            diagnose; echo ""; deep_clean; log_run ;;
  schedule)        schedule_mode ;;
  -h|--help|help|usage) echo "usage: speed.sh [diagnose|call|restore|deep|maintenance|schedule]" ;;
  *) echo "usage: speed.sh [diagnose|call|restore|deep|maintenance|schedule]"; exit 1 ;;
esac

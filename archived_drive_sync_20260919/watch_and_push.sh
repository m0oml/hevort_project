#!/bin/bash
# watch_and_push.sh — Watch sys and macros dirs, push to Drive on any change.
# Re-execs itself when a new subdirectory appears: inotify has no recursive
# mode, so `-r` only watches directories that existed when the watch was set.
# Directories created later (e.g. /sys/closed-loop, /sys/accelerometer) get
# no watch and their contents are invisible until the watch is rebuilt.
SCRIPT="/home/trev/push_to_drive.sh"
WATCH_DIRS="/opt/dsf/sd/sys /opt/dsf/sd/macros"
LOG="/home/trev/push_to_drive.log"
MAINPID=$$

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO Watcher started" >> "$LOG"

# Reconcile on startup — catches anything written while the watch was down
# or inside a directory that wasn't yet watched.
"$SCRIPT"

inotifywait -m -r -e close_write,moved_to,create $WATCH_DIRS \
    --format '%T %w %f %e' --timefmt '%Y-%m-%d %H:%M:%S' |
while read -r datetime dir file event; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO Change detected: ${dir}${file} (${event})" >> "$LOG"
    "$SCRIPT"
    case "$event" in
        *ISDIR*)
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO New directory ${dir}${file} - rebuilding watches" >> "$LOG"
            kill -TERM "$MAINPID"
            ;;
    esac
done

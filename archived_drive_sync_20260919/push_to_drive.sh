#!/bin/bash
# push_to_drive.sh — Mirror /opt/dsf/sd/sys and /opt/dsf/sd/macros to Google Drive.
# Uses rclone (remote "gdrive") — rclone ships a Google-verified OAuth client,
# so the refresh token does not expire after 7 days like the old script's did.
#
# Replaces push_to_drive.py. Same sources, same destination folders, same log.

REMOTE="gdrive"
LOG="/home/trev/push_to_drive.log"
STATUS="/home/trev/push_to_drive.status"
LOCK="/home/trev/.push_to_drive.lock"

# Destination Drive folder IDs — same folders the Python script used.
SYS_DIR="/opt/dsf/sd/sys"
SYS_ID="1gLAcXXCszW8oZrBpZwaeeRTaJNPs9gTI"
MACROS_DIR="/opt/dsf/sd/macros"
MACROS_ID="1oXYyhdUJHUqfROvr4jJeL3fo5T1uOwUI"
# ─────────────────────────────────────────────────────────────────────────────

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1 $2" >> "$LOG"; }

# Serialise pushes. The watcher fires one per inotify event and events arrive in
# bursts, so without this several rclone runs pile up against the same folders.
exec 9>"$LOCK"
if ! flock -w 300 9; then
    log ERROR "Timed out waiting for lock, skipping this push"
    exit 1
fi

sync_dir() {
    local dir="$1" fid="$2" out rc

    if [ ! -d "$dir" ]; then
        log WARNING "Source dir not found, skipping: $dir"
        return 0
    fi

    # --max-depth 1 keeps this to top-level files, matching the old behaviour.
    # "copy" never deletes on the remote, also matching the old behaviour.
    # duetBackup/ is plugin runtime state, not machine config. Its .config holds
    # a plaintext GitHub token, and its .log is appended while rclone reads it,
    # which fails the copy ("source file is being updated" / md5 differ).
    out=$(rclone copy "$dir" "${REMOTE},root_folder_id=${fid}:" \
            --exclude "duetBackup/**" \
            --stats 0 -v 2>&1)
    rc=$?

    if [ $rc -ne 0 ]; then
        log ERROR "Failed to sync $dir (rclone exit $rc)"
        while IFS= read -r line; do
            [ -n "$line" ] && log ERROR "  $line"
        done <<< "$(echo "$out" | tail -5)"
        return 1
    fi

    while IFS= read -r line; do
        [ -n "$line" ] && log INFO "  $line"
    done <<< "$(echo "$out" | grep -E ': (Copied|Updated|Deleted)' | sed 's/^.*NOTICE *//; s/^.*INFO *: *//')"

    log INFO "Synced $dir"
    return 0
}

log INFO "Push started"

failed=0
sync_dir "$SYS_DIR"    "$SYS_ID"    || failed=1
sync_dir "$MACROS_DIR" "$MACROS_ID" || failed=1

if [ $failed -ne 0 ]; then
    log ERROR "Push finished with errors"
    echo "FAIL $(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS"
    exit 1
fi

log INFO "Push complete"
echo "OK $(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS"

#!/bin/bash
# cleanup_drive.sh — MANUAL. Delete files on Google Drive that no longer exist
# locally under /opt/dsf/sd/sys or /opt/dsf/sd/macros.
#
# Why this exists: push_to_drive.sh uses "rclone copy", which never deletes on
# the remote. Anything ever written to sys/ or macros/ is on Drive permanently,
# including deleted scratch files and old capture data, and Claude Web reads
# that Drive as the live source of truth for this machine. This script is the
# only thing that prunes it.
#
# Run it by hand. Nothing calls it automatically and nothing should.
#
#   ./cleanup_drive.sh              dry run - list what WOULD be deleted
#   ./cleanup_drive.sh --delete     delete, after showing the list and asking
#   ./cleanup_drive.sh --delete -y  delete without the confirmation prompt
#
# Deletions go to the Drive TRASH, not permanent removal, so a mistake is
# recoverable from drive.google.com for 30 days. There is deliberately no
# option here to bypass the trash.

REMOTE="gdrive"
LOG="/home/trev/cleanup_drive.log"
LOCK="/home/trev/.push_to_drive.lock"

SYS_DIR="/opt/dsf/sd/sys"
SYS_ID="1gLAcXXCszW8oZrBpZwaeeRTaJNPs9gTI"
MACROS_DIR="/opt/dsf/sd/macros"
MACROS_ID="1oXYyhdUJHUqfROvr4jJeL3fo5T1uOwUI"
# ─────────────────────────────────────────────────────────────────────────────

DO_DELETE=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --delete) DO_DELETE=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 2 ;;
    esac
done

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1 $2" >> "$LOG"; }

command -v rclone >/dev/null || { echo "rclone not found"; exit 1; }

# Share push_to_drive.sh's lock. The watcher fires a push on every inotify
# event, so without this a push could re-upload a file while we are deleting
# it, or we could delete a file mid-copy.
exec 9>"$LOCK"
if ! flock -w 300 9; then
    echo "Timed out waiting for the push lock - a sync is running. Try again."
    log ERROR "Timed out waiting for lock"
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

total_orphans=0
total_bytes=0

scan_dir() {
    local dir="$1" fid="$2" label="$3"
    local remote="${REMOTE},root_folder_id=${fid}:"

    if [ ! -d "$dir" ]; then
        echo "  local dir missing, refusing to touch the remote: $dir"
        log WARNING "Local dir missing, skipped: $dir"
        return 0
    fi

    if ! rclone lsf -R --files-only "$remote" > "$WORK/$label.remote" 2>"$WORK/$label.err"; then
        echo "  ERROR listing remote for $label:"
        sed 's/^/    /' "$WORK/$label.err"
        log ERROR "Failed to list remote for $dir"
        return 1
    fi

    ( cd "$dir" && find . -type f -printf '%P\n' ) | sort > "$WORK/$label.local"
    sort -o "$WORK/$label.remote" "$WORK/$label.remote"

    # Present on the remote, absent locally.
    comm -23 "$WORK/$label.remote" "$WORK/$label.local" > "$WORK/$label.orphans"

    local n bytes
    n=$(wc -l < "$WORK/$label.orphans")
    echo
    echo "=== $label ==="
    echo "  local files : $(wc -l < "$WORK/$label.local")"
    echo "  remote files: $(wc -l < "$WORK/$label.remote")"
    echo "  orphaned on Drive: $n"

    [ "$n" -eq 0 ] && return 0

    # Size of the orphans, for the summary only.
    bytes=$(rclone size --json --files-from "$WORK/$label.orphans" "$remote" 2>/dev/null \
            | grep -o '"bytes":[0-9]*' | cut -d: -f2)
    [ -n "$bytes" ] && total_bytes=$((total_bytes + bytes))
    total_orphans=$((total_orphans + n))

    echo
    sed 's/^/    /' "$WORK/$label.orphans"

    if [ "$DO_DELETE" -eq 1 ]; then
        echo
        echo "  deleting $n file(s) from $label -> Drive trash"
        if rclone delete --files-from "$WORK/$label.orphans" "$remote" --drive-use-trash -v 2>&1 \
             | sed 's/^/    /'; then
            log INFO "Deleted $n orphaned file(s) from $label"
        else
            log ERROR "rclone delete failed for $label"
            return 1
        fi
        # Tidy directories left empty by the deletions.
        rclone rmdirs "$remote" --leave-root 2>/dev/null
    fi
    return 0
}

echo "Drive cleanup — files on Drive with no local counterpart"
echo "Mode: $( [ "$DO_DELETE" -eq 1 ] && echo 'DELETE (to Drive trash)' || echo 'DRY RUN' )"
log INFO "Cleanup started (delete=$DO_DELETE)"

# In delete mode, show everything first, get consent, then run for real.
if [ "$DO_DELETE" -eq 1 ] && [ "$ASSUME_YES" -eq 0 ]; then
    DO_DELETE=0
    scan_dir "$SYS_DIR"    "$SYS_ID"    "sys"
    scan_dir "$MACROS_DIR" "$MACROS_ID" "macros"
    echo
    if [ "$total_orphans" -eq 0 ]; then
        echo "Nothing to delete. Drive matches local."
        log INFO "Nothing to delete"
        exit 0
    fi
    printf 'Delete %d file(s), %s, from Drive (recoverable from trash)? [y/N] ' \
        "$total_orphans" "$(numfmt --to=iec "$total_bytes" 2>/dev/null || echo "$total_bytes bytes")"
    read -r reply
    case "$reply" in
        y|Y|yes|YES) DO_DELETE=1; total_orphans=0; total_bytes=0 ;;
        *) echo "Aborted, nothing deleted."; log INFO "Aborted at prompt"; exit 0 ;;
    esac
fi

failed=0
scan_dir "$SYS_DIR"    "$SYS_ID"    "sys"    || failed=1
scan_dir "$MACROS_DIR" "$MACROS_ID" "macros" || failed=1

echo
if [ "$total_orphans" -eq 0 ]; then
    echo "Drive matches local. Nothing orphaned."
else
    printf 'Total: %d orphaned file(s), %s\n' \
        "$total_orphans" "$(numfmt --to=iec "$total_bytes" 2>/dev/null || echo "$total_bytes bytes")"
    [ "$DO_DELETE" -eq 0 ] && echo "Dry run — nothing was deleted. Re-run with --delete to act."
fi

if [ "$failed" -ne 0 ]; then
    echo "Finished WITH ERRORS — see $LOG"
    log ERROR "Cleanup finished with errors"
    exit 1
fi

log INFO "Cleanup complete (delete=$DO_DELETE, orphans=$total_orphans)"
exit 0

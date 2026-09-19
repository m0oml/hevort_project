#!/usr/bin/env bash
# hevort_project_watch.sh — commit and push ~/hevort_project on change.
#
# Notes, slicer notes and survey data. Survey captures are generated on the Pi,
# renamed, then copied across in batches, so the debounce here is longer than
# the Pi's: a multi-file scp should land as ONE commit, not one per file.
#
#   systemctl status hevort-project-watch     is it alive
#   journalctl -u hevort-project-watch -f     what it has been doing
#   cat /home/trev/hevort_project_watch.status   last outcome, one line

set -u

REPO=/home/trev/hevort_project
STATUS=/home/trev/hevort_project_watch.status
DEBOUNCE=10          # seconds of quiet before committing
PUSH_RETRIES=5      # network outages are obvious from the printer being dead,
PUSH_BACKOFF=30     # so retry quietly and let the log carry the detail

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
status() { printf '%s | %s\n' "$(date '+%F %T')" "$*" > "$STATUS"; }

# No printer display here, so a blocked commit goes to the desktop if there is
# one, and to the status file and journal regardless.
notify_machine() {
    command -v notify-send >/dev/null && \
        notify-send -u critical "hevort_project watcher" "$1" 2>/dev/null || true
}

cd "$REPO" || { log "FATAL: cannot cd to $REPO"; exit 1; }

commit_and_push() {
    local reason="$1"

    git add -A || { log "ERROR: git add failed"; return 1; }

    if git diff --cached --quiet; then
        return 0            # nothing real changed (ignored files only)
    fi

    # Mark each path with what happened to it: + added, ~ modified, - deleted.
    # Without this an add and a delete of the same file produce identical
    # subjects, which is unreadable in a history you are scanning for "when did
    # X change".
    local files count subject
    files=$(git diff --cached --name-status \
            | awk '{ p=$2; 
                     if ($1 ~ /^A/) s="+"; else if ($1 ~ /^D/) s="-"; else s="~";
                     printf "%s%s, ", s, p }' \
            | sed 's/, $//')
    count=$(git diff --cached --name-only | wc -l)
    [ "${#files}" -gt 140 ] && files="${files:0:137}..."
    subject="$reason: $files"
    [ "$count" -gt 6 ] && subject="$reason: $count files"

    if ! git commit -q -m "$subject" 2>&1 | tee /tmp/hcw_commit.err >&2; then
        if grep -qi "credential\|COMMIT ABORTED" /tmp/hcw_commit.err 2>/dev/null; then
            log "BLOCKED: pre-commit secret scan refused this commit"
            log "         $(grep -i 'possible credential' /tmp/hcw_commit.err | head -3)"
            status "BLOCKED — secret scan refused a commit; see journalctl"
            notify_machine "GIT BLOCKED: secret in sys - check journal"
        else
            log "ERROR: commit failed"
            status "ERROR — commit failed; see journalctl"
        fi
        git reset -q            # unstage so the next event retries cleanly
        return 1
    fi

    log "committed: $subject"

    local n=1
    while [ "$n" -le "$PUSH_RETRIES" ]; do
        if git push -q origin main 2>&1; then
            log "pushed ($(git rev-parse --short HEAD))"
            status "OK — pushed $(git rev-parse --short HEAD)"
            return 0
        fi
        log "push failed (attempt $n/$PUSH_RETRIES), retrying in ${PUSH_BACKOFF}s"
        sleep "$PUSH_BACKOFF"
        n=$((n + 1))
    done

    # Commits are safe locally; only the push is behind. Say so precisely.
    log "WARNING: push failing after $PUSH_RETRIES attempts — commits are local only"
    status "BEHIND — committed locally, push failing; check network/auth"
    return 1
}

# Commit repeatedly until the tree is actually clean.
#
# inotify only delivers events while a watch is active. Between the debounce
# ending and the push finishing there is NO watch — a couple of seconds — and
# anything changed in that window is lost for good. Observed in testing on
# 19/09/2026: a file deleted while the previous commit was being pushed was
# never committed at all.
#
# So after committing, re-check the tree rather than trusting that we saw
# everything. Bounded, because a commit the hook refuses leaves the tree dirty
# forever and would spin.
drain() {
    local reason="$1" attempt
    for attempt in 1 2 3; do
        commit_and_push "$reason" || return 1
        [ -z "$(git status --porcelain)" ] && return 0
        log "changes landed during commit/push — catching up (round $((attempt + 1)))"
        reason="catch-up"
    done
    log "WARNING: tree still dirty after 3 rounds; next event or restart will catch it"
    return 0
}

# ── Reconcile ────────────────────────────────────────────────────────────────
# The gap an on-change watcher leaves is its own downtime: a reboot, a crash, or
# being stopped. Anything changed in that window would never be seen, which is
# the same loss the timer had. So the first thing on start is to commit whatever
# is outstanding, BEFORE watching begins.
log "starting; reconciling anything changed while not running"
drain "reconcile" || true

# ── Watch ────────────────────────────────────────────────────────────────────
# inotifywait -r establishes watches at START and does not follow directories
# created later, so a new macros/Whatever/ would sit unwatched. Re-exec on an
# ISDIR event rebuilds the watch set. (The old watch_and_push.sh did the same.)
log "watching $REPO (excluding .git)"
status "OK — watching"

while true; do
    # --exclude '/\.git/' is NOT optional: committing writes into .git, which
    # would fire events, which would trigger another commit, forever.
    event=$(inotifywait -q -r --exclude '/\.git/' \
                -e close_write,moved_to,move_self,create,delete \
                --format '%e %w%f' "$REPO" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log "inotifywait exited rc=$rc; restarting watch in 5s"
        sleep 5
        continue
    fi

    case "$event" in
        *ISDIR*) log "new directory ($event) — re-execing to rebuild watches"
                 exec "$0" ;;
    esac

    # Debounce: one save fires several events, and an scp of many files should
    # be one commit. Short enough that two deliberate edits stay two commits.
    while inotifywait -q -r -t "$DEBOUNCE" --exclude '/\.git/' \
            -e close_write,moved_to,create,delete \
            "$REPO" >/dev/null 2>&1; do :; done

    drain "update" || true
done

#!/usr/bin/env bash
# hevort_config_watch.sh — commit and push /opt/dsf/sd/{sys,macros} on change.
#
# Replaces a duetBackup plugin that committed on a 6-hour timer. The objection
# to that was not commit noise, it was LOSS: anything changed and changed again
# inside a 6-hour window only ever reached GitHub in its final state. This
# commits on the change itself, so every intermediate state is preserved.
#
# The working tree IS /opt/dsf/sd. Nothing is copied or synced.
#
#   systemctl status hevort-config-watch     is it alive
#   journalctl -u hevort-config-watch -f     what it has been doing
#   cat /home/trev/hevort_config_watch.status   last outcome, one line

set -u

REPO=/opt/dsf/sd
STATUS=/home/trev/hevort_config_watch.status
DEBOUNCE=5          # seconds of quiet before committing
LOCK="/opt/dsf/sd/sys/BACKUP_PAUSED"
LOCK_MAX_AGE=600    # 10 min. The lock is for batching a few edits, not for
                    # holding a whole session, so a forgotten one should clear
                    # itself quickly. A silently paused backup is the same
                    # failure reconcile() and drain() exist to prevent.
POLL=60             # wake this often even with no file activity, so a released
                    # or expired lock is noticed without needing a file to change

PUSH_RETRIES=5      # network outages are obvious from the printer being dead,
PUSH_BACKOFF=30     # so retry quietly and let the log carry the detail

BATCH_SUBJECT=""

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
status() { printf '%s | %s\n' "$(date '+%F %T')" "$*" > "$STATUS"; }

# Shout on the printer's own display. A blocked commit is the one failure that
# looks like nothing is wrong — network is up, the machine prints fine — so it
# has to appear where the user actually is.
notify_machine() {
    command -v duet >/dev/null || return 0
    duet -q "M117 \"$1\"" 2>/dev/null || true
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
            | awk '{ p=$2; sub(/^sys\//,"",p);
                     if ($1 ~ /^A/) s="+"; else if ($1 ~ /^D/) s="-"; else s="~";
                     printf "%s%s, ", s, p }' \
            | sed 's/, $//')
    count=$(git diff --cached --name-only | wc -l)
    [ "${#files}" -gt 140 ] && files="${files:0:137}..."
    subject="$reason: $files"
    [ "$count" -gt 6 ] && subject="$reason: $count files"

    # A batch released from the lock gets the lock's own text as its subject:
    # deliberate work deserves a real message, not a list of filenames.
    if [ -n "${BATCH_SUBJECT:-}" ]; then
        subject="$BATCH_SUBJECT"
        BATCH_SUBJECT=""
    fi

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

# Is committing paused?
#
#   echo "retune extruder limits" > LOCK   pause, and set the commit subject
#   touch LOCK                             pause, auto subject as usual
#   rm LOCK                                resume; everything lands as ONE commit
#
# Returns 0 while genuinely paused. A lock past LOCK_MAX_AGE is treated as
# forgotten and cleared loudly, because "backups stopped and everything looks
# fine" is the worst state this system can be in.
locked() {
    [ -e "$LOCK" ] || return 1
    local age
    age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
    if [ "$age" -gt "$LOCK_MAX_AGE" ]; then
        log "WARNING: lock held ${age}s (limit ${LOCK_MAX_AGE}s) — treating as forgotten, resuming"
        notify_machine "BACKUP LOCK EXPIRED - resuming"
        rm -f "$LOCK"
        return 1
    fi
    return 0
}

# Human-readable age of the held lock, for the status line.
lock_age() {
    local age; age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
    printf '%dm%02ds' "$((age / 60))" "$((age % 60))"
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

    # Checked here rather than at the call sites so that reconcile-on-start
    # honours it too — otherwise a restart or reboot would commit everything
    # the lock was holding back, and the lock would silently mean nothing.
    if locked; then
        local why; why=$(head -c 120 "$LOCK" 2>/dev/null | tr -d '\n')
        # Remembered now because `rm` destroys it, and the batch it describes is
        # committed after the lock is already gone.
        [ -n "$why" ] && BATCH_SUBJECT="$why"
        log "paused by $LOCK ($(lock_age))${why:+ — $why}"
        status "PAUSED ($(lock_age))${why:+ — $why}"
        return 0
    fi
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
log "watching $REPO/sys and $REPO/macros"
status "OK — watching"

while true; do
    event=$(inotifywait -q -r -e close_write,moved_to,move_self,create,delete \
                -t "$POLL" --format '%e %w%f' "$REPO/sys" "$REPO/macros" 2>/dev/null)
    rc=$?

    # rc 2 is the poll timeout, not a fault. Use it to notice a lock that has
    # been released or has expired: removing the lock changes no watched file,
    # so without this the batch would sit uncommitted until something else moved.
    if [ "$rc" -eq 2 ]; then
        if ! locked && [ -n "$(git status --porcelain)" ]; then
            log "outstanding changes and no lock — committing"
            drain "batch" || true
        elif ! locked; then
            status "OK — watching"
        fi
        continue
    fi

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
    while inotifywait -q -r -t "$DEBOUNCE" \
            -e close_write,moved_to,create,delete \
            "$REPO/sys" "$REPO/macros" >/dev/null 2>&1; do :; done

    drain "config" || true
done

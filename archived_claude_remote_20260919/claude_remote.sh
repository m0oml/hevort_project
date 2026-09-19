#!/usr/bin/env bash
# Claude Code Remote Control session for the HevORT project.
# Started at boot by claude-remote.service, which runs this inside tmux.
#
#   tmux attach -t claude     join the live session from any SSH login
#   Ctrl-b d                  detach and leave it running
#   Ctrl-c                    do NOT — that kills the session, the loop
#                             below just restarts it 10s later
#
# The restart loop lives here rather than in systemd Restart= because the
# process systemd actually launches is `tmux new-session`, which returns
# immediately; the unit is oneshot and has no main process to supervise.

set -u

SESSION_DIR=/home/trev/hevort_project
CLAUDE=/home/trev/.local/bin/claude
LOG=/home/trev/claude_remote.log

# The script's stdout is the tmux pane, not the journal, so the pane scrollback
# is the real transcript. These loop markers are teed to LOG as well so that a
# crash-restart history survives the pane being cleared or the server dying.
log() { printf '[claude-remote %s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

cd "$SESSION_DIR" || { log "cannot cd to $SESSION_DIR, giving up"; exit 1; }

delay=10
while true; do
    log "starting Remote Control session in $SESSION_DIR"
    started=$SECONDS

    # --permission-mode auto: the classifier, not a bypass. The soft_deny rules
    # in ~/.claude/settings.json (sudo reboot, pkill -f/pgrep -f under
    # /opt/dsf/sd) still stop and ask, which is the point of running it here.
    "$CLAUDE" --remote-control hevort --permission-mode auto
    rc=$?

    # A session that stayed up is a normal exit (network blip, /exit from the
    # phone) and should come back promptly. Only rapid repeat failures — bad
    # credentials, no network at boot — get backed off, and only as far as one
    # try per minute: being reachable again soon after an outage matters more
    # here than being gentle about retries.
    if (( SECONDS - started > 60 )); then
        delay=10
    else
        (( delay = delay < 60 ? delay * 2 : 60 ))
    fi

    log "session exited (rc=$rc); restarting in ${delay}s"
    sleep "$delay"
done

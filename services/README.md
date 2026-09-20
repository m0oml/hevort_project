# services

The two watchers that back this machine up, kept here so they survive the loss
of either box. Neither is installed *from* here — these are copies of what is
running, committed so they can be restored.

| File | Runs on | Installed at |
|---|---|---|
| `hevort_project_watch.sh` | workstation | `~/hevort_project_watch.sh` |
| `hevort-project-watch.service` | workstation | `/etc/systemd/system/` |
| `hevort_config_watch.sh` | Pi | `~/hevort_config_watch.sh` |
| `hevort-config-watch.service` | Pi | `/etc/systemd/system/` |
| `pre-commit.hook` | both | `<repo>/.git/hooks/pre-commit` |

Each watcher commits its own repo on change: the workstation writes
`hevort_project`, the Pi writes `hevort_config`. One writer per repo — two
unattended pushers on one branch would race and lose changes.

## Restoring one

```bash
cp hevort_config_watch.sh ~/ && chmod +x ~/hevort_config_watch.sh
sudo cp hevort-config-watch.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hevort-config-watch
```

The hook is not copied by `git clone` — git never installs hooks from a
repository. After cloning either repo:

```bash
cp services/pre-commit.hook .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

A fresh machine also needs its own GitHub SSH key (`~/.ssh/id_ed25519_github`,
no passphrase so the watcher can run unattended) added to the account, and
`git config user.name/user.email` set in the repo.

## Pausing a watcher to batch edits

Both watchers respect a lock file in the repo root, checked from `drain()` so
it applies to reconcile-on-start too:

```bash
echo "retune extruder limits for PA 0.03" > BACKUP_PAUSED   # workstation
echo "retune extruder limits for PA 0.03" > sys/BACKUP_PAUSED  # Pi
```

While the lock exists, nothing is committed. `rm` it and everything that
changed while it was held lands as **one commit**, titled with the lock's own
text rather than a list of filenames.

`touch BACKUP_PAUSED` with no message works too — the commit falls back to the
usual auto-generated subject.

**Auto-expires after 10 minutes.** This is a lock for batching a few edits, not
for holding a whole session, so a forgotten one clears itself rather than
silently pausing backup indefinitely — "everything looks fine and nothing is
being committed" is the one failure state this whole system was built to avoid.
Expiry logs a `WARNING`, and on the Pi also puts `BACKUP LOCK EXPIRED` on the
printer's display, for the same reason a blocked commit does: it needs to
surface somewhere you're actually looking, not just in a log you'd have to
think to check.

Verified 20/09/2026: locked, made two edits, confirmed nothing committed,
released — landed as one commit with the batch message. Separately, backdated
a lock past the 10-minute limit and confirmed both watchers detected it,
cleared it, and resumed on their own.

## Two failure modes these were built around

**inotify only delivers events while a watch is active.** There is no watch
during a commit and push, so changes landing in that window were lost outright
— observed in testing, a file deleted mid-push was never committed. `drain()`
re-checks the tree after each commit rather than trusting it saw everything.

**A watcher's own downtime is a silent gap.** Both reconcile on start,
committing anything outstanding before they begin watching, so a reboot or
crash does not quietly swallow whatever changed meanwhile.

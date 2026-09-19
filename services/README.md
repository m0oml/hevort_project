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

## Two failure modes these were built around

**inotify only delivers events while a watch is active.** There is no watch
during a commit and push, so changes landing in that window were lost outright
— observed in testing, a file deleted mid-push was never committed. `drain()`
re-checks the tree after each commit rather than trusting it saw everything.

**A watcher's own downtime is a silent gap.** Both reconcile on start,
committing anything outstanding before they begin watching, so a reboot or
crash does not quietly swallow whatever changed meanwhile.

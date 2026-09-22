# Terminal workflow

Open Terminal in this folder:

```sh
cd /Users/bdunbar/Documents/Codex/2026-09-20/referenced-chatgpt-conversation-this-is-an/outputs/LocalPilot
git status
git log --oneline --decorate -10
```

Git stores local checkpoints and works offline. GitHub stores an optional remote copy. Keep the repository private for this prototype. Generated LocalPilot.app and .build files are excluded; rebuild from the committed source when needed. Raw diagnostic dumps and audio should stay out of Git.

## One-time GitHub connection

First check GitHub authentication in your own Terminal:

```sh
gh auth status
```

If it asks you to sign in, use browser login; do not paste tokens into chat:

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
```

After confirming the intended account, create a new private repository and push the local checkpoint:

```sh
gh repo create localpilot --private --source=. --remote=origin --push
git remote -v
```

If localpilot already exists on GitHub, stop and inspect that repository before connecting it. Do not overwrite an existing remote or force-push.

## Each development checkpoint

Review changes, run checks, and update CHANGELOG.md and TESTING.md:

```sh
git status
git diff
bash scripts/test.sh
```

Stage the intended files explicitly, review, and commit. Example for test-result updates:

```sh
git add TESTING.md CHANGELOG.md
git diff --cached
git commit -m "Record stability build 2 live test results"
git push
```

Use one meaningful change per commit. A passing build is not a stable release until the live regression checklist passes. Name checkpoint tags honestly; reserve release tags for verified builds.

To inspect an older version without changing files:

```sh
git log --oneline --decorate
git show HEAD
git diff HEAD~1 HEAD
```

The last command needs at least two commits. Avoid hard resets or force-pushes to undo mistakes; use a reviewed revert commit. After rebuilding an older source revision, macOS may require refreshing Accessibility permission for the locally signed app.

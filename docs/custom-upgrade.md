# Custom Upgrade Workflow

This fork keeps upstream checks manual, then automates the mechanical sync and
patch replay work. `develop` is kept as the always-current customized branch:
latest upstream `main` plus the product customization commits.

## Branch Roles

- `upstream/main`: original QwenPaw upstream.
- `main`: clean fork sync branch (fast-forward only).
- `develop`: customized product branch (rebased onto `main`).
- `release`: deployable release branch, updated only after manual review.

## Manual Upgrade

Start from a clean working tree, then run:

```bash
scripts/custom/upgrade-from-upstream.sh
```

The script will:

1. Verify `upstream` and `origin` remotes exist.
2. Fetch `upstream` and `origin`.
3. Fast-forward local `main` to `upstream/main`.
4. Tag a backup of the current `develop` HEAD (`custom-backup-YYYYMMDDHHMM`).
5. Rebase `develop` directly onto the refreshed `main`.
6. Run frontend tests, frontend build, and Python unit tests on `develop`.

`release` is intentionally untouched by the script.

## Useful Options

```bash
# Skip fetch if you already fetched remotes
scripts/custom/upgrade-from-upstream.sh --no-fetch

# Push refreshed main to origin/main
scripts/custom/upgrade-from-upstream.sh --push-main

# Push rebased develop to origin (force-with-lease)
scripts/custom/upgrade-from-upstream.sh --push-custom

# Push both branches in one run
scripts/custom/upgrade-from-upstream.sh --push-main --push-custom

# Skip all verification
scripts/custom/upgrade-from-upstream.sh --skip-verify
```

## Release Workflow

After a successful upgrade and manual testing:

```bash
# 1. Ensure develop is tested and ready
git checkout develop

# 2. Create or update release branch
git checkout release
git merge develop

# 3. Tag the release
git tag -a v<VERSION> -m "Release <VERSION>"

# 4. Push
git push origin release --tags
```

## Troubleshooting

### Rebase conflicts

The script stops and prints instructions. Resolve on `develop`:

```bash
git status
# edit conflicted files
git add <files>
git rebase --continue
```

Or abort and try again later:

```bash
git rebase --abort
```

A backup tag (`custom-backup-*`) was created before rebase. Use it to restore
if needed:

```bash
git checkout develop
git reset --hard custom-backup-YYYYMMDDHHMM
git tag -d custom-backup-YYYYMMDDHHMM  # cleanup when no longer needed
```

### "remote 'upstream' not found"

```bash
git remote add upstream git@github.com:agentscope-ai/QwenPaw.git
```

### Fast-forward failed on main

Local `main` has diverged from upstream (unlikely if it's only ever ff-merged).
Fix by resetting to upstream:

```bash
git checkout main
git reset --hard upstream/main
```

### Python tests failed after upgrade

Non-blocking — the script prints a warning and continues. Check if upstream
changed test fixtures or added new test dependencies:

```bash
pip install -e ".[dev,full]"
pytest tests/unit/ -x -q --tb=short
```

### Want to undo the entire upgrade

```bash
git checkout develop
git reset --hard custom-backup-YYYYMMDDHHMM
git checkout main
git reset --hard origin/main
```

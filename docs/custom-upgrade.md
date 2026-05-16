# Custom Upgrade Workflow

This fork keeps upstream synchronization manual, then automates the mechanical
branch and patch replay work.

## Branch Roles

- `upstream/main`: original QwenPaw upstream.
- `main`: clean fork sync branch.
- `develop`: customized product branch.
- `release`: deployable release branch, updated only after manual review.

## Manual Upgrade

Start from a clean working tree, then run:

```bash
scripts/custom/upgrade-from-upstream.sh
```

The script will:

1. Fetch `upstream` and `origin`.
2. Fast-forward local `main` to `upstream/main`.
3. Create an `upgrade/<timestamp>-main` branch from `develop`.
4. Rebase the customization commits onto the refreshed `main`.
5. Run frontend tests and build.

When it succeeds, review the upgrade branch:

```bash
git log --oneline main..upgrade/<branch-name>
git diff main...upgrade/<branch-name>
```

After review, promote it to `develop`:

```bash
git switch develop
git reset --hard upgrade/<branch-name>
```

`release` is intentionally untouched by the script.

## Useful Options

```bash
# Use an explicit branch name
scripts/custom/upgrade-from-upstream.sh --upgrade-branch upgrade/qwenpaw-1.2.0

# Skip fetch if you already fetched remotes
scripts/custom/upgrade-from-upstream.sh --no-fetch

# Push refreshed main to origin/main
scripts/custom/upgrade-from-upstream.sh --push-main

# Move develop to the upgrade result after verification
scripts/custom/upgrade-from-upstream.sh --apply
```

If rebase conflicts happen, resolve them on the upgrade branch and continue:

```bash
git status
git add <files>
git rebase --continue
```

Or abort the attempt:

```bash
git rebase --abort
git branch -D upgrade/<branch-name>
```

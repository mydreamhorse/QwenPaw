# Custom Upgrade Workflow

This fork keeps upstream checks manual, then automates the mechanical sync and
patch replay work. `develop` is kept as the always-current customized branch:
latest upstream `main` plus the product customization commits.

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
3. Rebase `develop` directly onto the refreshed `main`.
4. Run frontend tests and build on `develop`.

`release` is intentionally untouched by the script.

## Useful Options

```bash
# Skip fetch if you already fetched remotes
scripts/custom/upgrade-from-upstream.sh --no-fetch

# Push refreshed main to origin/main
scripts/custom/upgrade-from-upstream.sh --push-main
```

If rebase conflicts happen, resolve them on `develop` and continue:

```bash
git status
git add <files>
git rebase --continue
```

Or abort the attempt:

```bash
git rebase --abort
```

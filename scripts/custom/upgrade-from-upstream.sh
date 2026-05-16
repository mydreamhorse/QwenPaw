#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
FORK_REMOTE="${FORK_REMOTE:-origin}"
SYNC_BRANCH="${SYNC_BRANCH:-main}"
CUSTOM_BRANCH="${CUSTOM_BRANCH:-develop}"
UPGRADE_BRANCH=""
FETCH=1
VERIFY=1
PUSH_MAIN=0
APPLY_TO_DEVELOP=0

usage() {
  cat <<EOF
Usage:
  scripts/custom/upgrade-from-upstream.sh [options]

Manual-trigger upstream upgrade helper for the customized QwenPaw fork.

Default flow:
  1. Check the working tree is clean.
  2. Fetch remotes.
  3. Fast-forward local ${SYNC_BRANCH} to ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}.
  4. Create an upgrade branch from ${CUSTOM_BRANCH}.
  5. Rebase custom commits onto the refreshed ${SYNC_BRANCH}.
  6. Run frontend verification.

Options:
  --upgrade-branch NAME  Use a specific upgrade branch name.
  --no-fetch            Skip git fetch. Use already-fetched refs.
  --skip-verify         Skip npm test/build verification.
  --push-main           Push refreshed ${SYNC_BRANCH} to ${FORK_REMOTE}.
  --apply               After verification, move ${CUSTOM_BRANCH} to the upgrade result.
  -h, --help            Show this help.

Environment overrides:
  UPSTREAM_REMOTE        Default: upstream
  UPSTREAM_BRANCH        Default: main
  FORK_REMOTE            Default: origin
  SYNC_BRANCH            Default: main
  CUSTOM_BRANCH          Default: develop
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

run() {
  echo "+ $*"
  "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upgrade-branch)
      [[ $# -ge 2 ]] || die "--upgrade-branch requires a value"
      UPGRADE_BRANCH="$2"
      shift 2
      ;;
    --no-fetch)
      FETCH=0
      shift
      ;;
    --skip-verify)
      VERIFY=0
      shift
      ;;
    --push-main)
      PUSH_MAIN=1
      shift
      ;;
    --apply)
      APPLY_TO_DEVELOP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "not inside a git repository"
cd "$REPO_ROOT"

[[ -z "$(git status --porcelain)" ]] \
  || die "working tree is not clean. Commit or stash changes before upgrading."

git show-ref --verify --quiet "refs/heads/${SYNC_BRANCH}" \
  || die "local branch not found: ${SYNC_BRANCH}"
git show-ref --verify --quiet "refs/heads/${CUSTOM_BRANCH}" \
  || die "local branch not found: ${CUSTOM_BRANCH}"

CURRENT_BRANCH="$(git branch --show-current)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -z "$UPGRADE_BRANCH" ]]; then
  UPGRADE_BRANCH="upgrade/${TIMESTAMP}-${UPSTREAM_BRANCH}"
fi

git show-ref --verify --quiet "refs/heads/${UPGRADE_BRANCH}" \
  && die "upgrade branch already exists: ${UPGRADE_BRANCH}"

BASE_BEFORE_UPGRADE="$(git merge-base "${CUSTOM_BRANCH}" "${SYNC_BRANCH}")"
CUSTOM_HEAD_BEFORE_UPGRADE="$(git rev-parse "${CUSTOM_BRANCH}")"
SYNC_HEAD_BEFORE_UPGRADE="$(git rev-parse "${SYNC_BRANCH}")"

info "Upgrade configuration"
echo "  upstream:       ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"
echo "  sync branch:    ${SYNC_BRANCH}"
echo "  custom branch:  ${CUSTOM_BRANCH}"
echo "  upgrade branch: ${UPGRADE_BRANCH}"
echo "  custom base:    ${BASE_BEFORE_UPGRADE}"

if [[ "$FETCH" -eq 1 ]]; then
  info "Fetching remotes"
  run git fetch --prune "$UPSTREAM_REMOTE"
  run git fetch --prune "$FORK_REMOTE"
fi

git show-ref --verify --quiet "refs/remotes/${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" \
  || die "remote ref not found: ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"

info "Refreshing ${SYNC_BRANCH} from ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"
run git switch "$SYNC_BRANCH"
run git merge --ff-only "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"

if [[ "$PUSH_MAIN" -eq 1 ]]; then
  info "Pushing ${SYNC_BRANCH} to ${FORK_REMOTE}"
  run git push "$FORK_REMOTE" "$SYNC_BRANCH"
fi

if [[ "$BASE_BEFORE_UPGRADE" == "$CUSTOM_HEAD_BEFORE_UPGRADE" ]]; then
  info "${CUSTOM_BRANCH} has no commits on top of the previous ${SYNC_BRANCH}."
  run git switch -c "$UPGRADE_BRANCH" "$SYNC_BRANCH"
else
  info "Creating upgrade branch from ${CUSTOM_BRANCH}"
  run git switch -c "$UPGRADE_BRANCH" "$CUSTOM_BRANCH"

  info "Rebasing custom commits onto refreshed ${SYNC_BRANCH}"
  if ! git rebase --onto "$SYNC_BRANCH" "$BASE_BEFORE_UPGRADE"; then
    cat <<EOF >&2

Rebase stopped because conflicts need manual resolution.

You are on ${UPGRADE_BRANCH}. Continue with:
  git status
  # edit conflicted files
  git add <files>
  git rebase --continue

Or abort this upgrade attempt:
  git rebase --abort
  git switch ${CURRENT_BRANCH:-$CUSTOM_BRANCH}
  git branch -D ${UPGRADE_BRANCH}

EOF
    exit 1
  fi
fi

if [[ "$VERIFY" -eq 1 ]]; then
  info "Running frontend tests"
  run bash -lc "cd console && npm run test -- --run"

  info "Running frontend build"
  run bash -lc "cd console && npm run build"
else
  info "Skipping verification because --skip-verify was provided"
fi

UPGRADE_HEAD="$(git rev-parse "$UPGRADE_BRANCH")"

if [[ "$APPLY_TO_DEVELOP" -eq 1 ]]; then
  info "Moving ${CUSTOM_BRANCH} to verified upgrade result"
  run git switch "$CUSTOM_BRANCH"
  run git reset --hard "$UPGRADE_HEAD"
else
  cat <<EOF

Upgrade branch is ready for review:
  ${UPGRADE_BRANCH}

To inspect:
  git log --oneline ${SYNC_BRANCH}..${UPGRADE_BRANCH}
  git diff ${SYNC_BRANCH}...${UPGRADE_BRANCH}

To promote it to ${CUSTOM_BRANCH} after review:
  git switch ${CUSTOM_BRANCH}
  git reset --hard ${UPGRADE_BRANCH}

This script did not touch release.
EOF
fi

SYNC_HEAD_AFTER_UPGRADE="$(git rev-parse "${SYNC_BRANCH}")"
cat <<EOF

Summary:
  ${SYNC_BRANCH}: ${SYNC_HEAD_BEFORE_UPGRADE} -> ${SYNC_HEAD_AFTER_UPGRADE}
  ${CUSTOM_BRANCH} before upgrade: ${CUSTOM_HEAD_BEFORE_UPGRADE}
  upgrade branch head: ${UPGRADE_HEAD}
EOF

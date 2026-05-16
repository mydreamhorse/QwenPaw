#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
FORK_REMOTE="${FORK_REMOTE:-origin}"
SYNC_BRANCH="${SYNC_BRANCH:-main}"
CUSTOM_BRANCH="${CUSTOM_BRANCH:-develop}"
FETCH=1
VERIFY=1
PUSH_MAIN=0
PUSH_CUSTOM=0

usage() {
  cat <<EOF
Usage:
  scripts/custom/upgrade-from-upstream.sh [options]

Manual-trigger upstream upgrade helper for the customized QwenPaw fork.

Default flow:
  1. Check the working tree is clean.
  2. Verify remotes exist.
  3. Fetch remotes.
  4. Fast-forward local ${SYNC_BRANCH} to ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}.
  5. Tag a backup of the current ${CUSTOM_BRANCH} HEAD.
  6. Rebase ${CUSTOM_BRANCH} directly onto the refreshed ${SYNC_BRANCH}.
  7. Run frontend + backend verification on ${CUSTOM_BRANCH}.

Options:
  --no-fetch            Skip git fetch. Use already-fetched refs.
  --skip-verify         Skip all verification.
  --push-main           Push refreshed ${SYNC_BRANCH} to ${FORK_REMOTE}.
  --push-custom         Push rebased ${CUSTOM_BRANCH} (force-with-lease).
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

warn() {
  echo "Warning: $*" >&2
}

run() {
  echo "+ $*"
  "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --push-custom)
      PUSH_CUSTOM=1
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

# ── Pre-flight: verify remotes ─────────────────────────────────────────────

git remote get-url "$UPSTREAM_REMOTE" &>/dev/null \
  || die "remote '${UPSTREAM_REMOTE}' not found. Add it with: git remote add ${UPSTREAM_REMOTE} <url>"
git remote get-url "$FORK_REMOTE" &>/dev/null \
  || die "remote '${FORK_REMOTE}' not found."

# ── Snapshot ────────────────────────────────────────────────────────────────

BASE_BEFORE_UPGRADE="$(git merge-base "${CUSTOM_BRANCH}" "${SYNC_BRANCH}")"
CUSTOM_HEAD_BEFORE_UPGRADE="$(git rev-parse "${CUSTOM_BRANCH}")"
SYNC_HEAD_BEFORE_UPGRADE="$(git rev-parse "${SYNC_BRANCH}")"

info "Upgrade configuration"
echo "  upstream:       ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"
echo "  sync branch:    ${SYNC_BRANCH}"
echo "  custom branch:  ${CUSTOM_BRANCH}"
echo "  custom base:    ${BASE_BEFORE_UPGRADE}"
echo "  custom head:    ${CUSTOM_HEAD_BEFORE_UPGRADE}"

if [[ "$FETCH" -eq 1 ]]; then
  info "Fetching remotes"
  run git fetch --prune "$UPSTREAM_REMOTE"
  run git fetch --prune "$FORK_REMOTE"
fi

git show-ref --verify --quiet "refs/remotes/${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" \
  || die "remote ref not found: ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"

# ── Refresh sync branch ────────────────────────────────────────────────────

info "Refreshing ${SYNC_BRANCH} from ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"
run git switch "$SYNC_BRANCH"
run git merge --ff-only "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"

if [[ "$PUSH_MAIN" -eq 1 ]]; then
  info "Pushing ${SYNC_BRANCH} to ${FORK_REMOTE}"
  run git push "$FORK_REMOTE" "$SYNC_BRANCH"
fi

# ── Backup tag ──────────────────────────────────────────────────────────────

BACKUP_TAG="custom-backup-$(date +%Y%m%d%H%M)"
info "Creating backup tag: ${BACKUP_TAG} -> ${CUSTOM_HEAD_BEFORE_UPGRADE}"
run git tag "$BACKUP_TAG" "$CUSTOM_HEAD_BEFORE_UPGRADE"

# ── Dry-run conflict check ──────────────────────────────────────────────────

if [[ "$BASE_BEFORE_UPGRADE" != "$CUSTOM_HEAD_BEFORE_UPGRADE" ]]; then
  info "Dry-run: checking for potential conflicts"
  if git merge-tree --write-tree "$SYNC_BRANCH" "$CUSTOM_HEAD_BEFORE_UPGRADE" >/dev/null 2>&1; then
    info "Dry-run: clean — no conflicts detected"
  else
    warn "Potential conflicts detected between ${SYNC_BRANCH} and ${CUSTOM_BRANCH}"
    echo ""
    read -rp "Continue with rebase anyway? [y/N] " CONFIRM
    [[ "${CONFIRM,,}" == "y" || "${CONFIRM,,}" == "yes" ]] \
      || { info "Aborted by user"; exit 0; }
  fi
fi

# ── Rebase custom branch ───────────────────────────────────────────────────

if [[ "$BASE_BEFORE_UPGRADE" == "$CUSTOM_HEAD_BEFORE_UPGRADE" ]]; then
  info "${CUSTOM_BRANCH} has no commits on top of the previous ${SYNC_BRANCH}."
  run git switch "$CUSTOM_BRANCH"
  run git merge --ff-only "$SYNC_BRANCH"
else
  info "Rebasing ${CUSTOM_BRANCH} directly onto refreshed ${SYNC_BRANCH}"
  if ! git rebase --onto "$SYNC_BRANCH" "$BASE_BEFORE_UPGRADE" "$CUSTOM_BRANCH"; then
    cat <<EOF >&2

Rebase stopped because conflicts need manual resolution.

Backup tag: ${BACKUP_TAG}

You are on ${CUSTOM_BRANCH}. Continue with:
  git status
  # edit conflicted files
  git add <files>
  git rebase --continue

Or abort this upgrade attempt:
  git rebase --abort
  git tag -d ${BACKUP_TAG}  # optional: remove backup tag

EOF
    exit 1
  fi
fi

# ── Verification ────────────────────────────────────────────────────────────

if [[ "$VERIFY" -eq 1 ]]; then
  info "Running frontend tests"
  run bash -lc "cd console && npm run test -- --run"

  info "Running frontend build"
  run bash -lc "cd console && npm run build"

  info "Running Python unit tests"
  run bash -lc "cd '$REPO_ROOT' && python -m pytest tests/unit/ -x -q --tb=line 2>/dev/null || echo 'WARNING: Python tests failed (non-blocking)'"
else
  info "Skipping verification because --skip-verify was provided"
fi

# ── Push custom branch (optional) ──────────────────────────────────────────

if [[ "$PUSH_CUSTOM" -eq 1 ]]; then
  info "Pushing rebased ${CUSTOM_BRANCH} to ${FORK_REMOTE} (force-with-lease)"
  run git push --force-with-lease "$FORK_REMOTE" "$CUSTOM_BRANCH"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

SYNC_HEAD_AFTER_UPGRADE="$(git rev-parse "${SYNC_BRANCH}")"
CUSTOM_HEAD_AFTER_UPGRADE="$(git rev-parse "${CUSTOM_BRANCH}")"
cat <<EOF

Summary:
  ${SYNC_BRANCH}:   ${SYNC_HEAD_BEFORE_UPGRADE} -> ${SYNC_HEAD_AFTER_UPGRADE}
  ${CUSTOM_BRANCH}: ${CUSTOM_HEAD_BEFORE_UPGRADE} -> ${CUSTOM_HEAD_AFTER_UPGRADE}
  backup tag:       ${BACKUP_TAG}
  release:          untouched
EOF

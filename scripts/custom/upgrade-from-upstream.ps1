# Manual-trigger upstream upgrade helper for the customized QwenPaw fork.
# PowerShell equivalent of upgrade-from-upstream.sh.
#
# Default flow:
#   1. Check the working tree is clean.
#   2. Verify remotes exist.
#   3. Fetch remotes.
#   4. Fast-forward local main to upstream/main.
#   5. Tag a backup of the current develop HEAD.
#   6. Dry-run conflict detection.
#   7. Rebase develop onto the refreshed main.
#   8. Run frontend + backend verification on develop.

param(
  [switch]$NoFetch,
  [switch]$SkipVerify,
  [switch]$PushMain,
  [switch]$PushCustom,
  [switch]$Help
)

$ErrorActionPreference = "Stop"

$UpstreamRemote = if ($env:UPSTREAM_REMOTE) { $env:UPSTREAM_REMOTE } else { "upstream" }
$UpstreamBranch = if ($env:UPSTREAM_BRANCH) { $env:UPSTREAM_BRANCH } else { "main" }
$ForkRemote     = if ($env:FORK_REMOTE)     { $env:FORK_REMOTE }     else { "origin" }
$SyncBranch     = if ($env:SYNC_BRANCH)     { $env:SYNC_BRANCH }     else { "main" }
$CustomBranch   = if ($env:CUSTOM_BRANCH)   { $env:CUSTOM_BRANCH }   else { "develop" }

function Show-Usage {
  @"
Usage:
  scripts\custom\upgrade-from-upstream.ps1 [options]

Manual-trigger upstream upgrade helper for the customized QwenPaw fork.

Default flow:
  1. Check the working tree is clean.
  2. Verify remotes exist.
  3. Fetch remotes.
  4. Fast-forward local $SyncBranch to $UpstreamRemote/$UpstreamBranch.
  5. Tag a backup of the current $CustomBranch HEAD.
  6. Rebase $CustomBranch directly onto the refreshed $SyncBranch.
  7. Run frontend + backend verification on $CustomBranch.

Options:
  -NoFetch            Skip git fetch. Use already-fetched refs.
  -SkipVerify         Skip all verification.
  -PushMain           Push refreshed $SyncBranch to $ForkRemote.
  -PushCustom         Push rebased $CustomBranch (force-with-lease).
  -Help               Show this help.

Environment overrides:
  UPSTREAM_REMOTE     Default: upstream
  UPSTREAM_BRANCH     Default: main
  FORK_REMOTE         Default: origin
  SYNC_BRANCH         Default: main
  CUSTOM_BRANCH       Default: develop
"@
}

function Die($msg) {
  Write-Error "Error: $msg"
  exit 1
}

function Info($msg) {
  Write-Host "==> $msg"
}

function Warn($msg) {
  Write-Warning $msg
}

function Run {
  param([string[]]$Cmd)
  Write-Host "+ $($Cmd -join ' ')"
  & $Cmd[0] $Cmd[1..($Cmd.Length-1)]
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code $LASTEXITCODE`: $($Cmd -join ' ')"
  }
}

if ($Help) {
  Show-Usage
  exit 0
}

# ── Resolve repo root ──────────────────────────────────────────────────────────

$RepoRoot = git rev-parse --show-toplevel 2>$null
if (-not $RepoRoot) { Die "not inside a git repository" }
Set-Location $RepoRoot

# ── Check working tree ─────────────────────────────────────────────────────────

$status = git status --porcelain
if ($status) {
  Die "working tree is not clean. Commit or stash changes before upgrading."
}

# ── Verify branches exist ──────────────────────────────────────────────────────

git show-ref --verify --quiet "refs/heads/$SyncBranch" 2>$null
if ($LASTEXITCODE -ne 0) { Die "local branch not found: $SyncBranch" }

git show-ref --verify --quiet "refs/heads/$CustomBranch" 2>$null
if ($LASTEXITCODE -ne 0) { Die "local branch not found: $CustomBranch" }

# ── Pre-flight: verify remotes ─────────────────────────────────────────────────

git remote get-url $UpstreamRemote 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Die "remote '$UpstreamRemote' not found. Add it with: git remote add $UpstreamRemote <url>"
}
git remote get-url $ForkRemote 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Die "remote '$ForkRemote' not found." }

# ── Snapshot ───────────────────────────────────────────────────────────────────

$BaseBeforeUpgrade = (git merge-base $CustomBranch $SyncBranch).Trim()
$CustomHeadBefore  = (git rev-parse $CustomBranch).Trim()
$SyncHeadBefore    = (git rev-parse $SyncBranch).Trim()

Info "Upgrade configuration"
Write-Host "  upstream:       $UpstreamRemote/$UpstreamBranch"
Write-Host "  sync branch:    $SyncBranch"
Write-Host "  custom branch:  $CustomBranch"
Write-Host "  custom base:    $BaseBeforeUpgrade"
Write-Host "  custom head:    $CustomHeadBefore"

# ── Fetch ──────────────────────────────────────────────────────────────────────

if (-not $NoFetch) {
  Info "Fetching remotes"
  Run git, fetch, --prune, $UpstreamRemote
  Run git, fetch, --prune, $ForkRemote
}

git show-ref --verify --quiet "refs/remotes/$UpstreamRemote/$UpstreamBranch" 2>$null
if ($LASTEXITCODE -ne 0) {
  Die "remote ref not found: $UpstreamRemote/$UpstreamBranch"
}

# ── Refresh sync branch ───────────────────────────────────────────────────────

Info "Refreshing $SyncBranch from $UpstreamRemote/$UpstreamBranch"
Run git, switch, $SyncBranch
Run git, merge, --ff-only, "$UpstreamRemote/$UpstreamBranch"

if ($PushMain) {
  Info "Pushing $SyncBranch to $ForkRemote"
  Run git, push, $ForkRemote, $SyncBranch
}

# ── Backup tag ─────────────────────────────────────────────────────────────────

$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$shortHash = $CustomHeadBefore.Substring(0, 8)
$BackupTag = "custom-backup-$timestamp-$shortHash"
Info "Creating backup tag: $BackupTag -> $CustomHeadBefore"
Run git, tag, $BackupTag, $CustomHeadBefore

# ── Dry-run conflict check ─────────────────────────────────────────────────────

if ($BaseBeforeUpgrade -ne $CustomHeadBefore) {
  Info "Dry-run: checking for potential conflicts"
  git merge-tree --write-tree $SyncBranch $CustomHeadBefore 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Info "Dry-run: clean — no conflicts detected"
  } else {
    Warn "Potential conflicts detected between $SyncBranch and $CustomBranch"
    $confirm = Read-Host "Continue with rebase anyway? [y/N]"
    if ($confirm -notin @("y", "yes", "Y", "YES")) {
      Info "Aborted by user"
      exit 0
    }
  }
}

# ── Rebase custom branch ──────────────────────────────────────────────────────

if ($BaseBeforeUpgrade -eq $CustomHeadBefore) {
  Info "$CustomBranch has no commits on top of the previous $SyncBranch."
  Run git, switch, $CustomBranch
  Run git, merge, --ff-only, $SyncBranch
} else {
  Info "Rebasing $CustomBranch directly onto refreshed $SyncBranch"
  # Use git directly here since rebase failure is expected and handled
  Write-Host "+ git rebase --onto $SyncBranch $BaseBeforeUpgrade $CustomBranch"
  git rebase --onto $SyncBranch $BaseBeforeUpgrade $CustomBranch
  if ($LASTEXITCODE -ne 0) {
    Write-Host @"

Rebase stopped because conflicts need manual resolution.

Backup tag: $BackupTag

You are on $CustomBranch. Continue with:
  git status
  # edit conflicted files
  git add <files>
  git rebase --continue

Or abort this upgrade attempt:
  git rebase --abort
  git tag -d $BackupTag  # optional: remove backup tag

"@ -ForegroundColor Yellow
    exit 1
  }
}

# ── Verification ──────────────────────────────────────────────────────────────

if (-not $SkipVerify) {
  Info "Running frontend tests"
  Push-Location console
  try {
    npm run test -- --run
    if ($LASTEXITCODE -ne 0) { Warn "Frontend tests failed (exit code: $LASTEXITCODE)" }
  } finally { Pop-Location }

  Info "Running frontend build"
  Push-Location console
  try {
    npm run build
    if ($LASTEXITCODE -ne 0) { Warn "Frontend build failed (exit code: $LASTEXITCODE)" }
  } finally { Pop-Location }

  Info "Running Python unit tests"
  python -m pytest tests/unit/ -x -q --tb=line 2>$null
  if ($LASTEXITCODE -ne 0) {
    Warn "Python tests failed (non-blocking)"
  }
} else {
  Info "Skipping verification because -SkipVerify was provided"
}

# ── Push custom branch (optional) ─────────────────────────────────────────────

if ($PushCustom) {
  Info "Pushing rebased $CustomBranch to $ForkRemote (force-with-lease)"
  Run git, push, --force-with-lease, $ForkRemote, $CustomBranch
}

# ── Summary ────────────────────────────────────────────────────────────────────

$SyncHeadAfter   = (git rev-parse $SyncBranch).Trim()
$CustomHeadAfter = (git rev-parse $CustomBranch).Trim()

Write-Host @"

Summary:
  ${SyncBranch}:   $SyncHeadBefore -> $SyncHeadAfter
  ${CustomBranch}: $CustomHeadBefore -> $CustomHeadAfter
  backup tag:      $BackupTag
  release:         untouched
"@

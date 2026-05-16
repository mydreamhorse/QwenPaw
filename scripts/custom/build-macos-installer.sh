#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

export APP_NAME="${APP_NAME:-Luobotou}"
export APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-AI工作台}"
export APP_BUNDLE_IDENTIFIER="${APP_BUNDLE_IDENTIFIER:-com.luobotou.desktop}"
export ZIP_BASENAME="${ZIP_BASENAME:-Luobotou}"
export QWENPAW_DESKTOP_TITLE="${QWENPAW_DESKTOP_TITLE:-${APP_DISPLAY_NAME}}"
export FORCE_WHEEL_BUILD="${FORCE_WHEEL_BUILD:-1}"
export CREATE_ZIP="${CREATE_ZIP:-1}"

exec bash scripts/pack/build_macos.sh "$@"

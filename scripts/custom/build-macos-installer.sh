#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

export APP_NAME="${APP_NAME:-Luobotou}"
export APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-萝卜头}"
export APP_BUNDLE_IDENTIFIER="${APP_BUNDLE_IDENTIFIER:-com.luobotou.desktop}"
export ZIP_BASENAME="${ZIP_BASENAME:-Luobotou}"
export CREATE_ZIP="${CREATE_ZIP:-1}"

exec bash scripts/pack/build_macos.sh "$@"

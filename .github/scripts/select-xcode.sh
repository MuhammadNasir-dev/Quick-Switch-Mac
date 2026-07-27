#!/usr/bin/env bash
# Selects the newest Xcode on the runner and fails loudly if its Swift is too
# old, rather than letting the build die in a wall of syntax errors.
set -euo pipefail

newest="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)"
if [ -z "$newest" ]; then
  echo "::error::No Xcode found on the runner"
  exit 1
fi

sudo xcode-select -s "$newest"
xcodebuild -version

swift_version="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9]*\.[0-9]*\).*/\1/p' | head -1)"
minimum="${MINIMUM_SWIFT:-6.1}"
echo "Swift $swift_version (minimum $minimum)"

if [ "$(printf '%s\n%s\n' "$minimum" "$swift_version" | sort -V | head -1)" != "$minimum" ]; then
  echo "::error::Swift $swift_version is older than the required $minimum."
  echo "::error::QuickSwitch uses 'nonisolated' on type declarations (SE-0449)."
  exit 1
fi

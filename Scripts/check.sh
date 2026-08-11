#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Phase 73: test doubles belong in test targets, never in a shipping library. They used to live
# in Sources/ and were wired in as production initializer defaults, so the app both linked and
# constructed them. Nothing but a build-time gate keeps that from growing back.
echo "==> Checking for test doubles in library sources"
if offenders=$(grep -rnE '^(public |final |internal |fileprivate |private )*(class|struct|enum|actor|typealias) +(Mock|Stub|Fake)' \
    --include='*.swift' "$ROOT"/Packages/*/Sources "$ROOT"/App 2>/dev/null); then
  echo "error: test doubles declared in library sources; move them to a Tests/ target:" >&2
  echo "$offenders" >&2
  exit 1
fi

for package in "$ROOT"/Packages/*; do
  if [[ -f "$package/Package.swift" ]]; then
    echo "==> Testing $(basename "$package")"
    swift test --package-path "$package"
  fi
done

echo "==> Building LiquidBagel"
xcodebuild -project "$ROOT/LiquidBagel.xcodeproj" -scheme LiquidBagel -destination 'platform=macOS' build

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for package in "$ROOT"/Packages/*; do
  if [[ -f "$package/Package.swift" ]]; then
    echo "==> Testing $(basename "$package")"
    swift test --package-path "$package"
  fi
done

echo "==> Building LiquidBagel"
xcodebuild -project "$ROOT/LiquidBagel.xcodeproj" -scheme LiquidBagel -destination 'platform=macOS' build

#!/usr/bin/env bash
#
# Enforces CLAUDE.md's Design System rule: raw color/font literals live only
# in ACDesignSystem/Theme — Feature code and the App target reference tokens,
# never raw values. This is the CI-side substitute for the M34 "grep check
# finds no raw color/font literals outside ACDesignSystem/Theme" acceptance
# criterion, run on every change instead of once at the end of the roadmap.
#
# Run from the repo root. Exits non-zero on any violation.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# check_no_raw_colors PATH LABEL
# Skips silently if PATH doesn't exist yet — see check-import-boundaries.sh
# for why that's correct here, not a bug.
check_no_raw_colors() {
  local check_path="$1"
  local label="$2"

  if [ ! -d "$check_path" ]; then
    return 0
  fi

  # Matches Color(red:/green:/blue:), Color(hex:), NSColor(red:...),
  # UIColor(red:...), and raw 6-digit hex literals used as a color argument.
  local hits
  hits=$(grep -rnE '(Color\(red:|Color\(hex:|NSColor\(red:|UIColor\(red:|#[0-9A-Fa-f]{6}\b)' \
    "$check_path" --include="*.swift" || true)
  if [ -n "$hits" ]; then
    echo "FAIL: $label"
    echo "$hits"
    echo ""
    fail=1
  fi
}

check_no_raw_colors "Packages/ACFeatures/Sources" \
  "raw color literal found outside ACDesignSystem/Theme (CLAUDE.md, Design System)"
check_no_raw_colors "AutoCue" \
  "raw color literal found in the App target (CLAUDE.md, Design System)"

if [ "$fail" -ne 0 ]; then
  echo "Color literal check FAILED — see CLAUDE.md, \"Design System.\" Use ACDesignSystem/Theme tokens instead."
  exit 1
fi

echo "Color literal check passed."

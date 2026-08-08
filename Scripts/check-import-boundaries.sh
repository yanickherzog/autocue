#!/usr/bin/env bash
#
# Enforces CLAUDE.md's "Package Dependency Graph" import-boundary rules — the
# ones SPM itself cannot enforce (system-framework imports and local-package
# imports both compile regardless of what Package.swift declares; see
# CLAUDE.md's "Important limitation of this graph" note). This script is the
# CI-side substitute for the manual "grep check" acceptance criteria that used
# to be the only enforcement, once, at the milestone that introduced each rule.
#
# Run from the repo root. Exits non-zero on any violation.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# check_no_import PATH FORBIDDEN_REGEX DESCRIPTION
# Skips silently if PATH doesn't exist yet (package not scaffolded yet, e.g.
# ahead of the milestone that creates it) — this script must stay a no-op for
# packages that don't exist, not fail CI for something not yet built.
check_no_import() {
  local check_path="$1"
  local forbidden_pattern="$2"
  local description="$3"

  if [ ! -d "$check_path" ]; then
    return 0
  fi

  local hits
  hits=$(grep -rnE "^\s*import\s+(${forbidden_pattern})\b" "$check_path" --include="*.swift" || true)
  if [ -n "$hits" ]; then
    echo "FAIL: $description"
    echo "$hits"
    echo ""
    fail=1
  fi
}

# ACCore (Domain + Application): Foundation only — CLAUDE.md rule 1.
check_no_import "Packages/ACCore/Sources" \
  "AVFoundation|SwiftData|PDFKit|Accelerate|SwiftUI|AppKit|UIKit|CoreGraphics|CoreText|Combine|libxlsxwriter" \
  "ACCore/Sources must import Foundation only (CLAUDE.md, rule 1 / Package Dependency Graph)"

# ACDesignSystem: SwiftUI/AppKit only — no local package, ever.
check_no_import "Packages/ACDesignSystem/Sources" \
  "ACCore|ACFeatures|ACAudioKit|ACExport|ACPersistence" \
  "ACDesignSystem/Sources must not import any local package (CLAUDE.md, Package Dependency Graph)"

# ACFeatures: ACCore + ACDesignSystem only — never a Data-layer package or
# SwiftData/AVFoundation directly (CLAUDE.md, Single Source of Truth: "Views
# never use @Query and never import SwiftData").
check_no_import "Packages/ACFeatures/Sources" \
  "ACAudioKit|ACExport|ACPersistence|SwiftData|AVFoundation" \
  "ACFeatures/Sources must not import a Data-layer package, SwiftData, or AVFoundation directly (CLAUDE.md, Package Dependency Graph + Single Source of Truth)"

# Data-layer packages never depend on each other — each talks to ACCore only.
check_no_import "Packages/ACAudioKit/Sources" \
  "ACExport|ACPersistence|ACFeatures" \
  "ACAudioKit/Sources must not import another Data-layer or Presentation package (CLAUDE.md, Package Dependency Graph)"
check_no_import "Packages/ACExport/Sources" \
  "ACAudioKit|ACPersistence|ACFeatures" \
  "ACExport/Sources must not import another Data-layer or Presentation package (CLAUDE.md, Package Dependency Graph)"
check_no_import "Packages/ACPersistence/Sources" \
  "ACAudioKit|ACExport|ACFeatures" \
  "ACPersistence/Sources must not import another Data-layer or Presentation package (CLAUDE.md, Package Dependency Graph)"

# ACTestSupport must never be linked into a .target — this script checks the
# import-boundary half of that rule (source files, not Package.swift target
# dependency lists, which a human/reviewer must still check at PR time until
# a Package.swift-aware version of this check is written).
check_no_import "Packages/ACCore/Sources" "ACTestSupport" "ACTestSupport must not be imported from a .target's Sources (CLAUDE.md, Naming Conventions)"
check_no_import "Packages/ACFeatures/Sources" "ACTestSupport" "ACTestSupport must not be imported from a .target's Sources (CLAUDE.md, Naming Conventions)"

if [ "$fail" -ne 0 ]; then
  echo "Import boundary check FAILED — see CLAUDE.md, \"Package Dependency Graph.\""
  exit 1
fi

echo "Import boundary check passed."

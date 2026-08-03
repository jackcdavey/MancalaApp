#!/usr/bin/env bash
#
# Builds and runs the whole headless AI suite. Run from the repo root:
#
#   Scripts/run-ai-checks.sh          # the standard pass
#   Scripts/run-ai-checks.sh --quick  # smaller samples, for a fast sanity check
#   Scripts/run-ai-checks.sh --full   # large samples and full search budgets
#
# Exits nonzero if any check fails, so it works as a pre-commit or CI gate.

set -uo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="${TMPDIR:-/tmp}/mancala-ai-checks"
mkdir -p "$BUILD_DIR"

MODE="${1:-standard}"
case "$MODE" in
  --quick)  RULES_GAMES=2000;  ORACLE_POSITIONS=40;  DEEP_POSITIONS=8;  LADDER_GAMES=12; LADDER_SCALE=0.02 ;;
  --full)   RULES_GAMES=50000; ORACLE_POSITIONS=500; DEEP_POSITIONS=60; LADDER_GAMES=200; LADDER_SCALE=0.25 ;;
  *)        RULES_GAMES=20000; ORACLE_POSITIONS=200; DEEP_POSITIONS=40; LADDER_GAMES=40;  LADDER_SCALE=0.05 ;;
esac

# Foundation-only sources. ContentView.swift and GameSettings.swift import
# SwiftUI and must stay out of both builds.
CORE_SOURCES=(
  Mancala/Models/Player.swift
  Mancala/Models/MancalaGame.swift
  Mancala/Models/AIDifficulty.swift
  Mancala/AI/SplitMix64.swift
  Mancala/AI/HeuristicAIPlayer.swift
  Mancala/AI/MancalaOptimalSolver.swift
  Mancala/AI/AIMoveSelector.swift
)

echo "==> Building ai-arena"
swiftc -O -o "$BUILD_DIR/ai-arena" "${CORE_SOURCES[@]}" Scripts/ai-arena.swift || exit 1

echo "==> Building verify-challenges"
swiftc -O -o "$BUILD_DIR/verify-challenges" \
  Mancala/Models/Player.swift \
  Mancala/Models/MancalaGame.swift \
  Mancala/Models/AIDifficulty.swift \
  Mancala/AI/MancalaOptimalSolver.swift \
  Mancala/Models/ChallengeCatalog.swift \
  Scripts/verify-challenges.swift || exit 1

FAILED=()

run_check() {
  local name="$1"; shift
  echo
  echo "==> $name"
  if "$@"; then
    return 0
  fi
  FAILED+=("$name")
  return 1
}

# Rules first: if the solver's private rules engine has drifted from
# MancalaGame, every other number below is measuring the wrong game.
run_check "rules-diff" \
  "$BUILD_DIR/ai-arena" rules-diff --games "$RULES_GAMES"

# Ground truth for Impossible: small endgames solved exhaustively.
run_check "oracle-endgame" \
  "$BUILD_DIR/ai-arena" oracle-endgame --games "$ORACLE_POSITIONS" --stones 8

# Proxy oracle for the middlegame. Reported, not gated — it has no ground truth.
run_check "oracle-deep" \
  "$BUILD_DIR/ai-arena" oracle-deep --games "$DEEP_POSITIONS"

run_check "bench" \
  "$BUILD_DIR/ai-arena" bench

# The regression gate: each tier must genuinely outplay the one below it.
run_check "ladder" \
  "$BUILD_DIR/ai-arena" ladder --games "$LADDER_GAMES" --budget-scale "$LADDER_SCALE"

run_check "verify-challenges" \
  "$BUILD_DIR/verify-challenges"

echo
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "All AI checks passed."
  exit 0
fi

echo "FAILED: ${FAILED[*]}"
exit 1

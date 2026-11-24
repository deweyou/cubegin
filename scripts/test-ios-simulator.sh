#!/usr/bin/env bash
set -euo pipefail

shard=${1:?Specify simulator-a or simulator-b}
shift

# Shard B runs the complementary UI tests and all App unit tests.
# Use hosted test durations when moving cases into or out of this list.
shard_a_cases=(
  testCelebrationReplaysOnlyWhileTheLatestSolveQualifies
  testClearingResultsRequiresCountdownAndResetsSettingsNavigation
  testDCTimerImportOpensFilesAndCanBeCancelled
  testDCTimerImportPreviewsAppendsAndCanBeUndoneAfterRelaunch
  testFormulaHintsShowSolutionsForCurrentScramble
  testLandscapeLongestTimerAndSummary
  testLandscapeNavigationAndCenteredTimer
  testLandscapePageEdgesAlignInBothDirections
  testManualEntryCanCancelAndSaveAPenalizedResult
  testPersonalBestToastsStackAtTheBottom
  testPortraitSolveListKeepsPickersFixedWhileScrolling
  testTimerSwipeShortcutsPersistAndUseTheExistingSolveFlows
)

case "$shard" in
  simulator-a)
    selectors=()
    case_option=-only-testing
    ;;
  simulator-b)
    selectors=(-only-testing:CubeginTests -only-testing:CubeginUITests)
    case_option=-skip-testing
    ;;
  *)
    echo "Unknown simulator shard: $shard" >&2
    exit 2
    ;;
esac

for test_case in "${shard_a_cases[@]}"; do
  selectors+=("$case_option:CubeginUITests/SolveFlowTests/$test_case")
done

exec xcodebuild "$@" -parallel-testing-enabled NO "${selectors[@]}" test-without-building

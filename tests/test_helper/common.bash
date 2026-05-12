# Common bash helpers for bats tests.
#
# Source this from a .bats file with:
#   load '../test_helper/common.bash'

# Repo root, available as $REPO_ROOT
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Helper: assert that the captured ${output} contains a substring.
# Usage: assert_output_contains "expected substring"
assert_output_contains() {
  local needle="$1"
  if ! echo "$output" | grep -qF -- "$needle"; then
    echo "Expected output to contain: $needle"
    echo "Actual output:"
    echo "$output"
    return 1
  fi
}

# Helper: assert exit status was a given value.
# Usage: assert_status 2
assert_status() {
  local expected="$1"
  if [ "$status" -ne "$expected" ]; then
    echo "Expected status: $expected, got: $status"
    echo "Output:"
    echo "$output"
    return 1
  fi
}

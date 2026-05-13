#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
  export SCRIPT="$REPO_ROOT/scripts/verify.sh"
}

@test "verify.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "verify.sh fails fast on unknown target" {
  run "$SCRIPT" not-a-target
  assert_status 2
}

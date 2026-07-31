#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
  export SCRIPT="$REPO_ROOT/scripts/publish.sh"
  export GNUPGHOME="$REPO_ROOT/tests/fixtures/gpg"
}

@test "publish.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "publish.sh fails if build/out is empty" {
  local empty="$REPO_ROOT/build/out-empty-test"
  rm -rf "$empty"
  mkdir -p "$empty"
  OUT_DIR_OVERRIDE="$empty" GNUPGHOME="$GNUPGHOME" run "$SCRIPT"
  assert_status 2
  rmdir "$empty"
}

@test "publish.sh hosts both bookworm and bullseye codenames" {
  grep -q "Codename: bookworm" "$REPO_ROOT/scripts/publish.sh"
  grep -q "Codename: bullseye" "$REPO_ROOT/scripts/publish.sh"
}

@test "publish.sh declares both amd64 and arm64 architectures" {
  grep -q "Architectures: amd64 arm64" "$REPO_ROOT/scripts/publish.sh"
}

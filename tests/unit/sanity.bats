#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "REPO_ROOT points at the repo containing this plan" {
  [ -f "$REPO_ROOT/Makefile" ]
  [ -f "$REPO_ROOT/config/kazoo.version" ]
}

@test "version pins are non-empty and trimmed" {
  local v
  for f in kazoo.version otp.version rebar.version package.revision; do
    v=$(cat "$REPO_ROOT/config/$f")
    [ -n "$v" ]
    # Must not contain trailing whitespace or newlines within
    [ "$(echo -n "$v" | wc -l | tr -d ' ')" -eq 0 ]
  done
}

@test "make help mentions both targets" {
  run make -C "$REPO_ROOT" help
  assert_status 0
  assert_output_contains "debian-12"
  assert_output_contains "el9"
}

@test "make build without TARGET fails with code 2" {
  run make -C "$REPO_ROOT" build
  assert_status 2
  assert_output_contains "TARGET is required"
}

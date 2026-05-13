#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
  # We test build.sh via direct invocation, not inside Docker, for speed.
  # The script's environment-validation logic doesn't require Docker.
  export SCRIPT="$REPO_ROOT/scripts/build.sh"
}

@test "build.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "build.sh fails fast if TARGET is unset" {
  unset TARGET
  run "$SCRIPT"
  assert_status 2
  assert_output_contains "TARGET"
}

@test "build.sh fails fast if TARGET is invalid" {
  TARGET=ubuntu-99 KAZOO_VERSION=master OTP_VERSION=26.2.5 PKG_REVISION=1 \
    run "$SCRIPT"
  assert_status 2
  assert_output_contains "invalid"
}

@test "build.sh fails fast if KAZOO_VERSION is unset" {
  TARGET=debian-12 OTP_VERSION=26.2.5 PKG_REVISION=1 \
    run "$SCRIPT"
  assert_status 2
  assert_output_contains "KAZOO_VERSION"
}

@test "build.sh fails fast if OTP_VERSION is unset" {
  TARGET=debian-12 KAZOO_VERSION=master PKG_REVISION=1 \
    run "$SCRIPT"
  assert_status 2
  assert_output_contains "OTP_VERSION"
}

@test "build.sh fails fast if PKG_REVISION is unset" {
  TARGET=debian-12 KAZOO_VERSION=master OTP_VERSION=26.2.5 \
    run "$SCRIPT"
  assert_status 2
  assert_output_contains "PKG_REVISION"
}

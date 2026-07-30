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

@test "SHA-256 pins are valid 64-char hex" {
  local v
  for f in otp.sha256 rebar.sha256; do
    [ -f "$REPO_ROOT/config/$f" ] || { echo "MISSING: config/$f"; return 1; }
    v=$(cat "$REPO_ROOT/config/$f")
    echo "$v" | grep -qE '^[0-9a-f]{64}$' || { echo "bad checksum in $f: $v"; return 1; }
  done
}

@test "Dockerfile SHA-256 defaults match the config pins" {
  # The Dockerfiles default these ARGs; they must equal config/*.sha256 so a
  # bare 'docker build' verifies against the same value the Makefile passes.
  local otp rebar
  otp=$(cat "$REPO_ROOT/config/otp.sha256")
  rebar=$(cat "$REPO_ROOT/config/rebar.sha256")
  for d in debian-11 debian-12 el9; do
    grep -q "^ARG OTP_SHA256=${otp}$" "$REPO_ROOT/docker/Dockerfile.$d"
    grep -q "^ARG REBAR_SHA256=${rebar}$" "$REPO_ROOT/docker/Dockerfile.$d"
  done
}

@test "make help mentions both targets" {
  run make -C "$REPO_ROOT" help
  assert_status 0
  assert_output_contains "debian-11"
  assert_output_contains "debian-12"
  assert_output_contains "el9"
}

@test "make build without TARGET fails with code 2" {
  run make -C "$REPO_ROOT" build
  assert_status 2
  assert_output_contains "TARGET is required"
}

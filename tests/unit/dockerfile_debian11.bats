#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "Dockerfile.debian-11 exists and uses debian:11-slim base" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-11"
  [ -f "$f" ]
  grep -q "^FROM debian:11-slim$" "$f"
}
@test "Dockerfile.debian-11 accepts OTP_VERSION and REBAR_VERSION build args" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-11"
  grep -q "^ARG OTP_VERSION=" "$f"
  grep -q "^ARG REBAR_VERSION=" "$f"
}
@test "Dockerfile.debian-11 verifies SHA-256 of the OTP tarball and rebar3 binary" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-11"
  grep -q 'sha256sum -c -' "$f"
}
@test "Dockerfile.debian-11 sets WORKDIR /work and ENTRYPOINT to build.sh" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-11"
  grep -q '^WORKDIR /work$' "$f"
  grep -q 'ENTRYPOINT \["/work/scripts/build.sh"\]' "$f"
}

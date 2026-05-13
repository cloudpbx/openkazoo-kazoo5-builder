#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "Dockerfile.debian-12 exists and declares the expected base image" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  [ -f "$f" ]
  grep -q "^FROM debian:12-slim" "$f"
}

@test "Dockerfile.debian-12 accepts OTP_VERSION and REBAR_VERSION build args" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  grep -q "^ARG OTP_VERSION=" "$f"
  grep -q "^ARG REBAR_VERSION=" "$f"
}

@test "Dockerfile.debian-12 installs reprepro, debsigs, fpm, and kerl (for source-built OTP)" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  grep -q "reprepro" "$f"
  grep -q "debsigs" "$f"
  grep -q "gem install" "$f"
  grep -q "fpm" "$f"
  # OTP is compiled from source via kerl (was esl-erlang from packages.erlang-solutions.com
  # before that server was retired by ESL in mid-2026).
  grep -q "kerl" "$f"
  grep -q "kerl build" "$f"
}

@test "Dockerfile.debian-12 sets WORKDIR /work and ENTRYPOINT to build.sh" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  grep -q "^WORKDIR /work" "$f"
  grep -q 'ENTRYPOINT \["/work/scripts/build.sh"\]' "$f"
}

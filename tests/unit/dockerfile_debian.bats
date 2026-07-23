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

@test "Dockerfile.debian-12 installs reprepro, debsigs, fpm, and source-builds OTP" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  grep -q "reprepro" "$f"
  grep -q "debsigs" "$f"
  grep -q "gem install" "$f"
  grep -q "fpm" "$f"
  # OTP is fetched + compiled from source (was esl-erlang from
  # packages.erlang-solutions.com before that server was retired in mid-2026).
  grep -q "otp_src_" "$f"
  grep -q "./configure" "$f"
  grep -q "make install" "$f"
}

@test "Dockerfile.debian-12 verifies SHA-256 of the OTP tarball and rebar3 binary" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  grep -q "^ARG OTP_SHA256=" "$f"
  grep -q "^ARG REBAR_SHA256=" "$f"
  # Both downloads are checked with sha256sum -c before use
  grep -q 'echo "${OTP_SHA256}  /tmp/otp.tar.gz" | sha256sum -c -' "$f"
  grep -q 'echo "${REBAR_SHA256}  /usr/local/bin/rebar3" | sha256sum -c -' "$f"
}

@test "Dockerfile.debian-12 sets WORKDIR /work and ENTRYPOINT to build.sh" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  grep -q "^WORKDIR /work" "$f"
  grep -q 'ENTRYPOINT \["/work/scripts/build.sh"\]' "$f"
}

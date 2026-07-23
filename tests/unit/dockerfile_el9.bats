#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "Dockerfile.el9 exists and uses rockylinux:9 base" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  [ -f "$f" ]
  grep -q "^FROM rockylinux:9" "$f"
}

@test "Dockerfile.el9 accepts OTP_VERSION and REBAR_VERSION build args" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  grep -q "^ARG OTP_VERSION=" "$f"
  grep -q "^ARG REBAR_VERSION=" "$f"
}

@test "Dockerfile.el9 installs createrepo_c, rpm-sign, fpm, and source-builds OTP" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  grep -q "createrepo_c" "$f"
  grep -q "rpm-sign" "$f"
  grep -q "fpm" "$f"
  # OTP is compiled from source (was esl-erlang from
  # packages.erlang-solutions.com before that server was retired).
  grep -q "otp_src_" "$f"
  grep -q "./configure" "$f"
  grep -q "make install" "$f"
}

@test "Dockerfile.el9 verifies SHA-256 of the OTP tarball and rebar3 binary" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  grep -q "^ARG OTP_SHA256=" "$f"
  grep -q "^ARG REBAR_SHA256=" "$f"
  grep -q 'echo "${OTP_SHA256}  /tmp/otp.tar.gz" | sha256sum -c -' "$f"
  grep -q 'echo "${REBAR_SHA256}  /usr/local/bin/rebar3" | sha256sum -c -' "$f"
}

@test "Dockerfile.el9 sets WORKDIR /work and ENTRYPOINT to build.sh" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  grep -q "^WORKDIR /work" "$f"
  grep -q 'ENTRYPOINT \["/work/scripts/build.sh"\]' "$f"
}

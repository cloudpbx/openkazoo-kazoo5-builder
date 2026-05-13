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

@test "Dockerfile.el9 installs createrepo_c, rpm-sign, kerl (source-built OTP), and fpm" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  grep -q "createrepo_c" "$f"
  grep -q "rpm-sign" "$f"
  grep -q "fpm" "$f"
  # OTP is compiled from source via kerl (was esl-erlang from
  # packages.erlang-solutions.com before that server was retired by ESL).
  grep -q "kerl" "$f"
  grep -q "kerl build" "$f"
}

@test "Dockerfile.el9 sets WORKDIR /work and ENTRYPOINT to build.sh" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  grep -q "^WORKDIR /work" "$f"
  grep -q 'ENTRYPOINT \["/work/scripts/build.sh"\]' "$f"
}

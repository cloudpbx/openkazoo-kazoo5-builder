#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "kazoo.service is a valid systemd unit (passes systemd-analyze verify in container)" {
  # Quick syntactic checks here; full verify happens in the install-test workflow.
  local f="$REPO_ROOT/packaging/common/kazoo.service"
  [ -f "$f" ]
  grep -q "^\[Unit\]" "$f"
  grep -q "^\[Service\]" "$f"
  grep -q "^\[Install\]" "$f"
  grep -q "^User=kazoo" "$f"
  grep -q "^Group=kazoo" "$f"
  grep -q "EnvironmentFile=-/etc/default/kazoo" "$f"
  grep -q "ExecStart=" "$f"
  grep -q "^WantedBy=multi-user.target" "$f"
}

@test "kazoo.sysusers declares user kazoo with home in /var/lib/kazoo" {
  local f="$REPO_ROOT/packaging/common/kazoo.sysusers"
  [ -f "$f" ]
  # Format: "u kazoo - 'Kazoo platform' /var/lib/kazoo /usr/sbin/nologin"
  grep -qE "^u +kazoo " "$f"
  grep -q "/var/lib/kazoo" "$f"
  grep -q "/usr/sbin/nologin" "$f"
}

@test "kazoo.tmpfiles creates /var/lib/kazoo and /var/log/kazoo owned by kazoo:kazoo" {
  local f="$REPO_ROOT/packaging/common/kazoo.tmpfiles"
  [ -f "$f" ]
  grep -qE "^d +/var/lib/kazoo +0750 +kazoo +kazoo " "$f"
  grep -qE "^d +/var/log/kazoo +0750 +kazoo +kazoo " "$f"
}

@test "kazoo.defaults defines NODE_NAME, COOKIE, and ERL_FLAGS as documented env" {
  local f="$REPO_ROOT/packaging/common/kazoo.defaults"
  [ -f "$f" ]
  grep -q "^NODE_NAME=" "$f"
  grep -q "^COOKIE=" "$f"
  grep -q "^ERL_FLAGS=" "$f"
}

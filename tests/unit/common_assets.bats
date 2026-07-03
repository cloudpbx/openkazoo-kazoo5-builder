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

@test "kazoo.service reads the generated cookie file before /etc/default/kazoo" {
  # /etc/kazoo.cookie holds the auto-generated distribution cookie; it must be
  # listed before /etc/default/kazoo so an operator-set COOKIE there wins.
  local f="$REPO_ROOT/packaging/common/kazoo.service"
  grep -q "EnvironmentFile=-/etc/kazoo.cookie" "$f"
  local cookie_ln default_ln
  cookie_ln=$(grep -n "EnvironmentFile=-/etc/kazoo.cookie" "$f" | head -1 | cut -d: -f1)
  default_ln=$(grep -n "EnvironmentFile=-/etc/default/kazoo" "$f" | head -1 | cut -d: -f1)
  [ "$cookie_ln" -lt "$default_ln" ]
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

@test "kazoo.defaults defines NODE_NAME and ERL_FLAGS as documented env" {
  local f="$REPO_ROOT/packaging/common/kazoo.defaults"
  [ -f "$f" ]
  grep -q "^NODE_NAME=" "$f"
  grep -q "^ERL_FLAGS=" "$f"
}

@test "kazoo.defaults ships no insecure hardcoded COOKIE default" {
  # The old 'COOKIE=change-me-please' default was a security footgun. The cookie
  # is now auto-generated at install time; kazoo.defaults must not set an active
  # COOKIE value (a commented example for cluster operators is fine).
  local f="$REPO_ROOT/packaging/common/kazoo.defaults"
  ! grep -q "change-me-please" "$f"
  ! grep -qE "^COOKIE=" "$f"
}

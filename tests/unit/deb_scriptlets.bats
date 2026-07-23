#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "deb scriptlets exist and are executable" {
  for f in preinst postinst prerm postrm; do
    local p="$REPO_ROOT/packaging/deb/${f}.sh"
    [ -f "$p" ] || { echo "MISSING: $p"; return 1; }
    [ -x "$p" ] || { echo "NOT EXECUTABLE: $p"; return 1; }
  done
}

@test "deb scriptlets start with shebang and 'set -e'" {
  for f in preinst postinst prerm postrm; do
    local p="$REPO_ROOT/packaging/deb/${f}.sh"
    head -1 "$p" | grep -q "^#!/" || { echo "no shebang: $p"; return 1; }
    grep -q "^set -e" "$p" || { echo "no 'set -e': $p"; return 1; }
  done
}

@test "postinst.sh applies sysusers and tmpfiles, runs daemon-reload" {
  local p="$REPO_ROOT/packaging/deb/postinst.sh"
  grep -q "systemd-sysusers" "$p"
  grep -q "systemd-tmpfiles" "$p"
  grep -q "systemctl daemon-reload" "$p"
}

@test "postinst.sh generates a random cookie into /etc/kazoo.cookie, guarded and 0640" {
  local p="$REPO_ROOT/packaging/deb/postinst.sh"
  # Only generate when the file is absent (don't rotate an in-use cookie)
  grep -q '\[ ! -e /etc/kazoo.cookie \]' "$p"
  grep -q "/dev/urandom" "$p"
  grep -q "chmod 640 /etc/kazoo.cookie" "$p"
  # Must NOT ship the old insecure default
  ! grep -q "change-me-please" "$p"
}

@test "prerm.sh stops the service idempotently" {
  local p="$REPO_ROOT/packaging/deb/prerm.sh"
  grep -q "systemctl stop kazoo" "$p"
}

@test "postrm.sh removes /var/lib/kazoo /var/log/kazoo on purge only" {
  local p="$REPO_ROOT/packaging/deb/postrm.sh"
  # Match within shell case branch
  grep -q 'purge)' "$p"
  grep -q "rm -rf /var/lib/kazoo" "$p"
  grep -q "rm -rf /var/log/kazoo" "$p"
  # The generated cookie is a secret; purge must remove it
  grep -q "rm -f /etc/kazoo.cookie" "$p"
}

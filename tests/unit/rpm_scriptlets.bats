#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "rpm scriptlets exist and are executable" {
  for f in pre post preun postun; do
    local p="$REPO_ROOT/packaging/rpm/${f}.sh"
    [ -f "$p" ] || { echo "MISSING: $p"; return 1; }
    [ -x "$p" ] || { echo "NOT EXECUTABLE: $p"; return 1; }
  done
}

@test "rpm post.sh applies sysusers and tmpfiles, runs daemon-reload" {
  local p="$REPO_ROOT/packaging/rpm/post.sh"
  grep -q "systemd-sysusers" "$p"
  grep -q "systemd-tmpfiles" "$p"
  grep -q "systemctl daemon-reload" "$p"
}

@test "rpm preun.sh stops the service only on final removal" {
  local p="$REPO_ROOT/packaging/rpm/preun.sh"
  # On RPM, $1=0 means "final uninstall"; $1=1 means "upgrade in progress"
  grep -q '\[ "\$1" -eq 0 \]' "$p" || grep -qE 'if .*\$1.*-eq.*0' "$p"
  grep -q "systemctl stop kazoo" "$p"
}

@test "rpm postun.sh removes runtime dirs on final removal" {
  local p="$REPO_ROOT/packaging/rpm/postun.sh"
  grep -q "rm -rf /var/lib/kazoo" "$p"
  grep -q "rm -rf /var/log/kazoo" "$p"
}

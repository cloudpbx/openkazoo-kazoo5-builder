#!/usr/bin/env bash
# Post-uninstall scriptlet for kazoo (RPM).
# $1: 0 = final uninstall, 1 = upgrade in progress
set -e

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload || true
fi

if [ "$1" -eq 0 ]; then
  # Final uninstall: remove runtime dirs (matches dpkg purge behavior)
  rm -rf /var/lib/kazoo
  rm -rf /var/log/kazoo
  # Remove the generated distribution cookie (a secret; don't leave it behind)
  rm -f /etc/kazoo.cookie
fi

exit 0

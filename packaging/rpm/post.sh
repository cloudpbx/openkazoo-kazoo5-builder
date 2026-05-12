#!/usr/bin/env bash
# Post-install scriptlet for kazoo (RPM).
# $1: 1 = first install, 2 = upgrade
set -e

if [ -x /bin/systemd-sysusers ] || [ -x /usr/bin/systemd-sysusers ]; then
  systemd-sysusers /usr/lib/sysusers.d/kazoo.conf
fi

if [ -x /bin/systemd-tmpfiles ] || [ -x /usr/bin/systemd-tmpfiles ]; then
  systemd-tmpfiles --create /usr/lib/tmpfiles.d/kazoo.conf
fi

if id -u kazoo >/dev/null 2>&1; then
  chown -R kazoo:kazoo /var/lib/kazoo /var/log/kazoo 2>/dev/null || true
fi

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload || true
fi

exit 0

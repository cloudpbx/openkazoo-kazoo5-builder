#!/usr/bin/env bash
# Post-remove scriptlet for kazoo (Debian).
# Reload systemd. On purge, additionally remove runtime directories.
# We deliberately do NOT remove the kazoo system user (debian convention).
set -e

case "$1" in
  remove|upgrade|disappear)
    if [ -d /run/systemd/system ]; then
      systemctl daemon-reload || true
    fi
    ;;
  purge)
    rm -rf /var/lib/kazoo
    rm -rf /var/log/kazoo
    # Remove the generated distribution cookie (a secret; don't leave it behind)
    rm -f /etc/kazoo.cookie
    if [ -d /run/systemd/system ]; then
      systemctl daemon-reload || true
    fi
    ;;
  failed-upgrade|abort-install|abort-upgrade)
    ;;
  *)
    echo "postrm called with unknown argument: $1" >&2
    exit 1
    ;;
esac

exit 0

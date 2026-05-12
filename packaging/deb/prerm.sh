#!/usr/bin/env bash
# Pre-remove scriptlet for kazoo (Debian).
# Stop the service cleanly (best-effort; do not fail removal if service was never started).
set -e

case "$1" in
  remove|upgrade|deconfigure)
    if [ -d /run/systemd/system ]; then
      systemctl stop kazoo.service 2>/dev/null || true
    fi
    ;;
  failed-upgrade)
    ;;
  *)
    echo "prerm called with unknown argument: $1" >&2
    exit 1
    ;;
esac

exit 0

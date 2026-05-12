#!/usr/bin/env bash
# Pre-uninstall scriptlet for kazoo (RPM).
# $1: 0 = final uninstall, 1 = upgrade in progress
set -e

if [ "$1" -eq 0 ]; then
  # Final uninstall: stop the service
  if [ -d /run/systemd/system ]; then
    systemctl stop kazoo.service 2>/dev/null || true
    systemctl disable kazoo.service 2>/dev/null || true
  fi
fi

exit 0

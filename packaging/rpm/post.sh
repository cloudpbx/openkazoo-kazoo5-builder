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

# Generate a strong random Erlang distribution cookie on first install.
# Guarded on absence so upgrades ($1=2) never rotate an in-use cookie.
# Alphanumeric only: valid as an unquoted Erlang atom. Read first by the unit;
# an operator can override with COOKIE= in /etc/default/kazoo.
if [ ! -e /etc/kazoo.cookie ]; then
  cookie="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 42)"
  ( umask 077; printf 'COOKIE=%s\n' "$cookie" > /etc/kazoo.cookie )
  if id -u kazoo >/dev/null 2>&1; then
    chown root:kazoo /etc/kazoo.cookie
  fi
  chmod 640 /etc/kazoo.cookie
fi

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload || true
fi

exit 0

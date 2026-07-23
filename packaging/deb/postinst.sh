#!/usr/bin/env bash
# Post-install scriptlet for kazoo (Debian).
# Runs after package files are unpacked. First and configure stages handled below.
set -e

case "$1" in
  configure)
    # Apply sysusers (creates 'kazoo' system user if missing)
    if [ -x /bin/systemd-sysusers ] || [ -x /usr/bin/systemd-sysusers ]; then
      systemd-sysusers /usr/lib/sysusers.d/kazoo.conf
    fi

    # Apply tmpfiles (creates /var/lib/kazoo, /var/log/kazoo)
    if [ -x /bin/systemd-tmpfiles ] || [ -x /usr/bin/systemd-tmpfiles ]; then
      systemd-tmpfiles --create /usr/lib/tmpfiles.d/kazoo.conf
    fi

    # Ensure ownership (idempotent)
    if id -u kazoo >/dev/null 2>&1; then
      chown -R kazoo:kazoo /var/lib/kazoo /var/log/kazoo 2>/dev/null || true
    fi

    # Generate a strong random Erlang distribution cookie on first install.
    # Guarded on absence so upgrades/reconfigures never rotate an in-use cookie.
    # Alphanumeric only: valid as an unquoted Erlang atom. Read first by the
    # unit; an operator can override with COOKIE= in /etc/default/kazoo.
    if [ ! -e /etc/kazoo.cookie ]; then
      cookie="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 42)"
      ( umask 077; printf 'COOKIE=%s\n' "$cookie" > /etc/kazoo.cookie )
      if id -u kazoo >/dev/null 2>&1; then
        chown root:kazoo /etc/kazoo.cookie
      fi
      chmod 640 /etc/kazoo.cookie
    fi

    # Reload systemd so the new unit file is visible
    if [ -d /run/systemd/system ]; then
      systemctl daemon-reload || true
    fi
    ;;
  abort-upgrade|abort-remove|abort-deconfigure)
    ;;
  *)
    echo "postinst called with unknown argument: $1" >&2
    exit 1
    ;;
esac

exit 0

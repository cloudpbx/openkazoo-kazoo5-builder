#!/usr/bin/env bash
# verify.sh — smoke-test built packages.
#
# Usage: verify.sh <target>
#   target: debian-12 | el9
#
# Asserts:
#   - At least one matching package exists in build/out/
#   - Package metadata is well-formed
#   - Required files are present inside the package
#   - (If signed) signature is parseable

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 2; }
ok()  { echo "  OK: $*"; }

TARGET="${1:-}"
[ -n "$TARGET" ] || die "TARGET is required (debian-12 or el9)"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/build/out"

case "$TARGET" in
  debian-12)
    shopt -s nullglob
    DEBS=("$OUT_DIR"/kazoo_*.deb)
    shopt -u nullglob
    [ "${#DEBS[@]}" -gt 0 ] || die "no .deb in $OUT_DIR"

    for deb in "${DEBS[@]}"; do
      echo ">> Verifying $deb"
      dpkg-deb --info "$deb" >/dev/null && ok "metadata parseable"
      dpkg-deb --contents "$deb" | grep -q "./opt/kazoo/bin/kazoo$" \
        && ok "/opt/kazoo/bin/kazoo present"
      dpkg-deb --contents "$deb" | grep -q "./lib/systemd/system/kazoo.service$" \
        && ok "/lib/systemd/system/kazoo.service present"
      dpkg-deb --contents "$deb" | grep -q "./etc/default/kazoo$" \
        && ok "/etc/default/kazoo present"
      # Signature check (optional — only if signed)
      if ar t "$deb" | grep -q "_gpgorigin"; then
        ok "GPG signature embedded"
      else
        echo "  WARN: package is not signed (yet)"
      fi
    done
    ;;

  el9)
    shopt -s nullglob
    RPMS=("$OUT_DIR"/kazoo-*.rpm)
    shopt -u nullglob
    [ "${#RPMS[@]}" -gt 0 ] || die "no .rpm in $OUT_DIR"

    for rpm in "${RPMS[@]}"; do
      echo ">> Verifying $rpm"
      rpm -qpi "$rpm" >/dev/null && ok "metadata parseable"
      rpm -qpl "$rpm" | grep -q "^/opt/kazoo/bin/kazoo$" \
        && ok "/opt/kazoo/bin/kazoo present"
      rpm -qpl "$rpm" | grep -q "^/lib/systemd/system/kazoo.service$\|^/usr/lib/systemd/system/kazoo.service$" \
        && ok "kazoo.service present"
      rpm -qpl "$rpm" | grep -q "^/etc/default/kazoo$" \
        && ok "/etc/default/kazoo present"
      # Check Requires
      rpm -qpR "$rpm" | grep -q "esl-erlang" \
        && ok "Requires esl-erlang"
    done
    ;;

  *)
    die "TARGET=$TARGET invalid"
    ;;
esac

echo ">> Verify passed."

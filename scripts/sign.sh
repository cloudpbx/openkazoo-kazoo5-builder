#!/usr/bin/env bash
# sign.sh — sign built packages with GPG.
#
# Usage: sign.sh <target>
#   target: debian-11 | debian-12 | el9
#
# Key source priority:
#   1. $GPG_PRIVATE_KEY env var (ASCII-armored private key, CI mode)
#   2. tests/fixtures/gpg/ keyring (local-dev mode; throwaway key)
#
# Output: signs build/out/*.deb (debsigs) or build/out/*.rpm (rpmsign) in place.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 2; }

TARGET="${1:-}"
[ -n "$TARGET" ] || die "TARGET is required (debian-11, debian-12, or el9)"
case "$TARGET" in
  debian-11|debian-12|el9) ;;
  *) die "TARGET=$TARGET is invalid" ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/build/out"

# --- Resolve GPG identity ---------------------------------------------------

if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
  TMP_GNUPGHOME=$(mktemp -d)
  trap "rm -rf '$TMP_GNUPGHOME'" EXIT
  chmod 700 "$TMP_GNUPGHOME"
  export GNUPGHOME="$TMP_GNUPGHOME"
  echo ">> Importing key from \$GPG_PRIVATE_KEY"
  if [ -n "${GPG_PASSPHRASE:-}" ]; then
    echo "$GPG_PRIVATE_KEY" | gpg --batch --pinentry-mode loopback \
      --passphrase "$GPG_PASSPHRASE" --import 2>&1 | tail -3
  else
    echo "$GPG_PRIVATE_KEY" | gpg --batch --import 2>&1 | tail -3
  fi
elif [ -n "${GNUPGHOME:-}" ] && [ -d "$GNUPGHOME" ]; then
  echo ">> Using local GNUPGHOME=$GNUPGHOME"
else
  die "no key source: set GPG_PRIVATE_KEY or GNUPGHOME"
fi

# Get the first available signing-capable key fingerprint
FPR=$(gpg --list-secret-keys --with-colons \
       | awk -F: '/^fpr:/ { print $10; exit }')
[ -n "$FPR" ] || die "no secret key found in keyring"
echo ">> Signing with key fingerprint: $FPR"

# --- Sign packages ----------------------------------------------------------

case "$TARGET" in
  debian-11|debian-12)
    shopt -s nullglob
    DEBS=("$OUT_DIR"/kazoo_*.deb)
    shopt -u nullglob
    [ "${#DEBS[@]}" -gt 0 ] || die "no .deb files in $OUT_DIR"
    for deb in "${DEBS[@]}"; do
      echo ">> debsigs sign: $deb"
      debsigs --sign=origin --default-key="$FPR" "$deb"
    done
    ;;
  el9)
    shopt -s nullglob
    RPMS=("$OUT_DIR"/kazoo-*.rpm)
    shopt -u nullglob
    [ "${#RPMS[@]}" -gt 0 ] || die "no .rpm files in $OUT_DIR"
    # Write rpmmacros so rpmsign uses our key
    cat > "${HOME}/.rpmmacros" <<EOF
%_signature gpg
%_gpg_name $FPR
%__gpg /usr/bin/gpg
EOF
    for rpm in "${RPMS[@]}"; do
      echo ">> rpmsign: $rpm"
      rpm --addsign "$rpm"
    done
    ;;
esac

echo ">> Signing complete."

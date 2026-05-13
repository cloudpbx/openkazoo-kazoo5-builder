#!/usr/bin/env bash
# publish.sh — assemble signed apt + yum repos under build/repo/.
#
# Inputs:
#   build/out/*.deb     signed Debian packages (one per supported codename)
#   build/out/*.rpm     signed RPM packages
#
# Output layout under build/repo/:
#   build/repo/debian/{dists/bookworm/...,pool/main/k/kazoo/}
#   build/repo/el/9/{repodata/...,Packages/}
#   build/repo/el/9/openkazoo.repo
#   build/repo/pubkey.asc
#
# Run inside the debian-12 build image (which has reprepro + createrepo_c).

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR_OVERRIDE:-$REPO_ROOT/build/out}"
REPO_DIR="$REPO_ROOT/build/repo"

shopt -s nullglob
DEBS=("$OUT_DIR"/*.deb)
RPMS=("$OUT_DIR"/*.rpm)
shopt -u nullglob

if [ "${#DEBS[@]}" -eq 0 ] && [ "${#RPMS[@]}" -eq 0 ]; then
  die "no packages in $OUT_DIR; run 'make build' first"
fi

# --- Resolve GPG identity (mirrors sign.sh) ---------------------------------

if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
  TMP_GNUPGHOME=$(mktemp -d)
  trap "rm -rf '$TMP_GNUPGHOME'" EXIT
  chmod 700 "$TMP_GNUPGHOME"
  export GNUPGHOME="$TMP_GNUPGHOME"
  echo "$GPG_PRIVATE_KEY" | gpg --batch --import 2>&1 | tail -3
fi
FPR=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')
[ -n "$FPR" ] || die "no GPG key available"

# --- Export public key ------------------------------------------------------

mkdir -p "$REPO_DIR"
gpg --armor --export "$FPR" > "$REPO_DIR/pubkey.asc"
echo ">> Exported public key to $REPO_DIR/pubkey.asc"

# --- Debian / apt repo via reprepro -----------------------------------------

if [ "${#DEBS[@]}" -gt 0 ]; then
  echo ">> Building apt repo for ${#DEBS[@]} .deb file(s)"
  APT_DIR="$REPO_DIR/debian"
  mkdir -p "$APT_DIR/conf"
  cat > "$APT_DIR/conf/distributions" <<EOF
Origin: openkazoo
Label: openkazoo-kazoo5-builder
Suite: stable
Codename: bookworm
Architectures: amd64
Components: main
Description: Community-built Kazoo packages for Debian 12
SignWith: $FPR
EOF
  for deb in "${DEBS[@]}"; do
    echo ">> reprepro includedeb bookworm: $deb"
    reprepro -b "$APT_DIR" includedeb bookworm "$deb"
  done
fi

# --- EL9 / yum repo via createrepo_c ----------------------------------------

if [ "${#RPMS[@]}" -gt 0 ]; then
  echo ">> Building yum repo for ${#RPMS[@]} .rpm file(s)"
  YUM_DIR="$REPO_DIR/el/9"
  mkdir -p "$YUM_DIR/Packages"
  cp "${RPMS[@]}" "$YUM_DIR/Packages/"
  createrepo_c "$YUM_DIR"

  # Sign the repomd.xml
  gpg --detach-sign --armor --local-user "$FPR" "$YUM_DIR/repodata/repomd.xml"

  # Generate the end-user .repo file
  cat > "$YUM_DIR/openkazoo.repo" <<EOF
[openkazoo-kazoo5]
name=openkazoo Kazoo 5 community packages for EL\$releasever
baseurl=https://cloudpbx.github.io/openkazoo-kazoo5-builder/el/\$releasever/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc
EOF
fi

# --- Top-level README for the repo -----------------------------------------

cat > "$REPO_DIR/README.md" <<EOF
# openkazoo-kazoo5-builder package repository

This branch (\`gh-pages\`) hosts the apt and yum repositories for
[openkazoo-kazoo5-builder](https://github.com/cloudpbx/openkazoo-kazoo5-builder).

See the [INSTALL.md](https://github.com/cloudpbx/openkazoo-kazoo5-builder/blob/main/docs/INSTALL.md)
in the main branch for usage.

Public signing key: \`pubkey.asc\` at the root of this site.
EOF

echo ">> Done. Repo published under: $REPO_DIR"

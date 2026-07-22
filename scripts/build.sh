#!/usr/bin/env bash
# build.sh — universal entrypoint for producing a Kazoo .deb or .rpm.
#
# Required env vars:
#   TARGET           one of: debian-12, el9
#   KAZOO_VERSION    upstream ref to build (tag like "5.4.0", or "master" for tip)
#   OTP_VERSION      Erlang/OTP version installed in the build image
#   PKG_REVISION     packaging-only revision (bumped for postinst fixes etc.)
#
# Output: build/out/<package>
#
# Called by `make build TARGET=...` inside the Docker image for TARGET.
# Can also be invoked directly inside a build container that already has the
# toolchain installed.

set -euo pipefail

# --- Argument validation ----------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 2; }

[ -n "${TARGET:-}"        ] || die "TARGET is required (debian-12 or el9)"
[ -n "${KAZOO_VERSION:-}" ] || die "KAZOO_VERSION is required"
[ -n "${OTP_VERSION:-}"   ] || die "OTP_VERSION is required"
[ -n "${PKG_REVISION:-}"  ] || die "PKG_REVISION is required"

case "$TARGET" in
  debian-12|el9) ;;
  *) die "TARGET=$TARGET is invalid (must be debian-12 or el9)" ;;
esac

# --- Paths ------------------------------------------------------------------

WORKDIR="${WORKDIR:-/work}"
BUILD_DIR="$WORKDIR/build"
SRC_DIR="$BUILD_DIR/kazoo5-src"
STAGE_DIR="$BUILD_DIR/stage-$TARGET"
OUT_DIR="$BUILD_DIR/out"

mkdir -p "$BUILD_DIR" "$OUT_DIR"

# --- Step 1: Fetch upstream source ------------------------------------------

echo ">> Fetching 2600hz/kazoo5 at ref: $KAZOO_VERSION"
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"
git clone --depth 1 --branch "$KAZOO_VERSION" \
  https://github.com/2600hz/kazoo5.git "$SRC_DIR"

# Compute a build-tag for the package version. If KAZOO_VERSION is a numeric
# tag like "5.4.0", we use that verbatim. If it's a branch name (e.g. "master"),
# we synthesize a pseudo-version like "5.4.0~master.YYYYMMDD.shortsha".
cd "$SRC_DIR"

# --- Work around upstream bug in rel/dist.relx.config.script ----------------
# The {release,...} tuple closes with "}," and the next list element line is
# ",{mode, prod}" (leading-comma style), producing ",," -> the release config
# fails to parse and `make build-dist-release` dies with:
#   {error,{_,erl_parse,["syntax error before: ","','"]}}  (build-release.escript:71)
# Drop the trailing comma after the release tuple's closing brace. Portable
# (awk), idempotent, and ASSERTED below so we fail loudly if upstream ever
# restructures this file (so the workaround can't silently rot).
RELX_SCRIPT="rel/dist.relx.config.script"
if [ -f "$RELX_SCRIPT" ]; then
  awk '
    /^[[:space:]]*},$/ {
      cur=$0
      if ((getline nxt) > 0) {
        if (nxt ~ /^[[:space:]]*,\{mode, prod\}$/) { sub(/,$/,"",cur) }
        print cur; print nxt; next
      } else { print cur; next }
    }
    { print }
  ' "$RELX_SCRIPT" > "$RELX_SCRIPT.tmp" && mv "$RELX_SCRIPT.tmp" "$RELX_SCRIPT"
  if awk 'p ~ /^[[:space:]]*},$/ && /^[[:space:]]*,\{mode, prod\}$/ {bad=1} {p=$0} END{exit bad?1:0}' "$RELX_SCRIPT"; then
    echo ">> Patched stray double-comma in $RELX_SCRIPT (upstream workaround)"
  else
    echo "ERROR: failed to patch double-comma in $RELX_SCRIPT — upstream layout changed?" >&2
    exit 1
  fi
fi

RAW_VERSION="$(cat VERSION 2>/dev/null || echo "$KAZOO_VERSION")"

if [[ "$KAZOO_VERSION" =~ ^[0-9] ]]; then
  PKG_VERSION="$KAZOO_VERSION"
else
  TODAY=$(date -u +%Y%m%d)
  SHORTSHA=$(git rev-parse --short=8 HEAD)
  # Strip "master" or non-numeric prefixes from RAW_VERSION
  BASE_VERSION=$(grep -Eo '^[0-9]+\.[0-9]+(\.[0-9]+)?' <<<"$RAW_VERSION" \
                  || echo "5.4.0")
  PKG_VERSION="${BASE_VERSION}~${KAZOO_VERSION}.${TODAY}.${SHORTSHA}"
fi
echo ">> Package version will be: $PKG_VERSION"

# --- Step 2: Compile + tarball Erlang release -------------------------------

# Force kazoo5's app fetch to use HTTPS instead of SSH (its default).
# Per make/app_urls.mk: `dep_blackhole = git $(FETCH_AS)2600hz/kazoo-blackhole.git`
# with FETCH_AS ?= git@github.com:  →  override to public HTTPS so CI without
# SSH credentials can clone the public app repos.
export FETCH_AS=https://github.com/

# kazoo5/make/releases.mk's `build-release` target sets ERL_LIBS but
# `tar-release` (which we call) does not. Without it, build-release.escript
# fails with `undefined function getopt:parse/2` because the deps aren't
# on the code path. Set it explicitly so both targets find deps + core + apps.
export ERL_LIBS="$SRC_DIR/deps:$SRC_DIR/core:$SRC_DIR/applications"

echo ">> Running make compile + make build-dist-release (FETCH_AS=$FETCH_AS)"
echo ">>   ERL_LIBS=$ERL_LIBS"
make compile
# Use build-dist-release (not tar-release) so we get rel/dist.* configs.
# The default `tar-release` uses rel/vm.args which is missing `-s lager` —
# that's the developer/console variant. rel/dist.vm.args has BOTH
# `-s lager` AND `-s kazoo_apps_app`, so the BEAM auto-starts lager AND
# kicks off kazoo_apps_app:start/0 on boot — i.e. kazoo apps actually
# come up, not just the supervision tree.
# Phase-2 boot test caught this: the package shipped with `tar-release`
# (=rel/vm.args) produced a BEAM that loaded apps but never started
# them; nothing connected to CouchDB or RabbitMQ. Switching to
# `build-dist-release` (rel/dist.*) gets us a functional release.
#
# build-dist-release only assembles _rel/kazoo (no tarball); we tar
# the directory ourselves to control the artifact name.
make build-dist-release
[ -d _rel/kazoo ] || die "_rel/kazoo not found — build-dist-release did not produce a release"
RELEASE_TARBALL="$BUILD_DIR/kazoo-${PKG_VERSION}.tar.gz"
tar -czf "$RELEASE_TARBALL" -C _rel/kazoo .
echo ">> Release tarball: $RELEASE_TARBALL (from rel/dist.* config)"

# --- Step 3: Stage files into FHS layout ------------------------------------

echo ">> Staging files into $STAGE_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/opt/kazoo"
tar -xzf "$RELEASE_TARBALL" -C "$STAGE_DIR/opt/kazoo"

install -Dm644 "$WORKDIR/packaging/common/kazoo.service"  "$STAGE_DIR/lib/systemd/system/kazoo.service"
install -Dm644 "$WORKDIR/packaging/common/kazoo.sysusers" "$STAGE_DIR/usr/lib/sysusers.d/kazoo.conf"
install -Dm644 "$WORKDIR/packaging/common/kazoo.tmpfiles" "$STAGE_DIR/usr/lib/tmpfiles.d/kazoo.conf"
install -Dm644 "$WORKDIR/packaging/common/kazoo.defaults" "$STAGE_DIR/etc/default/kazoo"

# --- Step 4: Run FPM --------------------------------------------------------

cd "$OUT_DIR"

# Derive Depends/Requires from OTP_VERSION's major.minor (e.g. 26.2)
OTP_MAJ_MIN="${OTP_VERSION%.*}"

case "$TARGET" in
  debian-12)
    echo ">> Wrapping into .deb with fpm"
    # No esl-erlang dependency: relx's tar-release bundles ERTS into
    # the release tarball, so the package is self-contained.
    fpm -s dir -t deb \
        --name kazoo \
        --version "$PKG_VERSION" \
        --iteration "${PKG_REVISION}~bookworm1" \
        --architecture amd64 \
        --depends "adduser" \
        --depends "systemd" \
        --depends "libssl3" \
        --depends "libncurses6" \
        --maintainer "openkazoo <support@cloudpbx.example>" \
        --description "Kazoo telephony platform (community build of 2600hz/kazoo5)" \
        --url "https://github.com/cloudpbx/openkazoo-kazoo5-builder" \
        --license "MPL-1.1" \
        --config-files /etc/default/kazoo \
        --before-install "$WORKDIR/packaging/deb/preinst.sh" \
        --after-install  "$WORKDIR/packaging/deb/postinst.sh" \
        --before-remove  "$WORKDIR/packaging/deb/prerm.sh" \
        --after-remove   "$WORKDIR/packaging/deb/postrm.sh" \
        -C "$STAGE_DIR" .
    ;;
  el9)
    echo ">> Wrapping into .rpm with fpm"
    # No esl-erlang Requires: relx's tar-release bundles ERTS.
    fpm -s dir -t rpm \
        --name kazoo \
        --version "$PKG_VERSION" \
        --iteration "${PKG_REVISION}.el9" \
        --architecture x86_64 \
        --depends "shadow-utils" \
        --depends "systemd" \
        --depends "openssl-libs" \
        --depends "ncurses-libs" \
        --rpm-dist el9 \
        --rpm-summary "Kazoo telephony platform" \
        --maintainer "openkazoo <support@cloudpbx.example>" \
        --description "Kazoo telephony platform (community build of 2600hz/kazoo5)" \
        --url "https://github.com/cloudpbx/openkazoo-kazoo5-builder" \
        --license "MPL-1.1" \
        --config-files /etc/default/kazoo \
        --before-install "$WORKDIR/packaging/rpm/pre.sh" \
        --after-install  "$WORKDIR/packaging/rpm/post.sh" \
        --before-remove  "$WORKDIR/packaging/rpm/preun.sh" \
        --after-remove   "$WORKDIR/packaging/rpm/postun.sh" \
        -C "$STAGE_DIR" .
    ;;
esac

echo ">> Done. Artifacts in: $OUT_DIR"
ls -la "$OUT_DIR"

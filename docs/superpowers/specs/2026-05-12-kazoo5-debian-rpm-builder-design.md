# Kazoo 5 Debian + RPM Builder — Design

**Status:** Draft, pending implementation plan
**Date:** 2026-05-12
**Owner:** Graham Nelson-Zutter (cloudpbx, with openkazoo community)
**Repo (planned):** `github.com/cloudpbx/openkazoo-kazoo5-builder`

---

## 1. Background

The openkazoo project has historically maintained community RPM and DEB packages for Kazoo v4.4 targeting Rocky Linux and Debian. Upstream development has moved to `github.com/2600hz/kazoo5` (v5.x). The kazoo5 repo contains the Erlang source and a Makefile that produces a `relx` release tarball, but the OS-packaging layer (spec files, postinst scripts, repo metadata) lives in 2600Hz's private CircleCI orb (`official-2600hz/kazoo`) and private Docker image (`2600hz/kazoo-packager`). 2600Hz publishes RPMs for Rocky/EL/CentOS at `packages.2600hz.com` but does not publish `.deb`s, and the public `artifacts/kazoo/` directory has not yet been observed to include 5.4 (latest visible: 5.3).

This project recreates the OS-packaging layer as a community-maintained pipeline, producing both `.deb` and `.rpm` artifacts for Kazoo 5.4.

### Factual research findings (recorded for the implementation team)

- **kazoo5 build is open**: `make compile` + `make tar-release` produces `kazoo-X.Y.Z.tar.gz` containing Erlang BEAM bundle + relx release.
- **kazoo5 OS-packaging is not open**: CircleCI commands `kazoo/build-rockylinux9`, `kazoo/build-centos7`, etc. are defined in the private orb `official-2600hz/kazoo`. Packager Docker image `2600hz/kazoo-packager` is published to Docker Hub but its Dockerfile is not public.
- **No Debian/Ubuntu builds upstream**: `packages.2600hz.com` has only `centos/{6,7}/`, `el/{8,9}/`, `rockylinux/{8,9}/`, plus `artifacts/`. No `debian/` or `ubuntu/` tree.
- **packages.2600hz.com `artifacts/kazoo/` versions**: 4.0, 4.1, 4.2, 4.3, 5.3 visible at time of writing. 5.4 not visibly published as of 2026-05-12.

## 2. Scope

**MVP (this design):**
- Single component: the Kazoo Erlang application from `2600hz/kazoo5`.
- Two target distributions: **Debian 12 (bookworm)** amd64 and **EL9** (a single RPM serving Rocky 9, Alma 9, RHEL 9).
- Runtime dependency on Erlang/OTP via **Erlang Solutions** apt/yum repos (`packages.erlang-solutions.com`). Users add ESL as a second apt/yum source.
- Packaging tool: **FPM** (Effing Package Management) — "wrap-and-ship" approach over native debhelper/spec files.
- CI host: **GitHub Actions** on public `ubuntu-latest` runners.
- Distribution: **GitHub Pages** apt repo (via `reprepro`) + yum repo (via `createrepo_c`), GPG-signed.

**Out of scope (explicit Phase 2+ backlog, see §10):**
- FreeSWITCH (2600Hz fork) packaging.
- Kamailio (2600Hz fork) packaging.
- Monster UI packaging.
- CouchDB, RabbitMQ — users install these from distro/upstream repos.
- arm64, Debian 11, Ubuntu LTS, Rocky 8, EL8, CentOS 7.
- Native debhelper / RPM spec files (migration when scope or quality demands).
- Reproducible builds (`SOURCE_DATE_EPOCH`).
- Auto-bumping on upstream tag detection.

## 3. Architecture

```
┌─────────────────────────────┐         ┌─────────────────────────────────┐
│  github.com/2600hz/kazoo5   │ pinned  │  github.com/cloudpbx/           │
│  (upstream, read-only)      │◄────────│  openkazoo-kazoo5-builder       │
│  Tags: 5.4.0, 5.4.1, ...    │ tag ref │  Owns packaging-layer only      │
└─────────────────────────────┘         └────────────────┬────────────────┘
                                                         │ on tag push (v5.*) or workflow_dispatch
                                                         ▼
                              ┌───────────────────────────────────────────────┐
                              │  GitHub Actions — matrix build                │
                              │  strategy.matrix.target: [debian-12, el9]    │
                              │                                              │
                              │  per target:                                 │
                              │    1. checkout builder repo                  │
                              │    2. docker build docker/Dockerfile.<tgt>   │
                              │    3. docker run scripts/build.sh:           │
                              │       - clone kazoo5 @ tag                   │
                              │       - make compile && make tar-release     │
                              │       - stage files into FHS layout          │
                              │       - fpm -s dir -t {deb|rpm}              │
                              │    4. sign package (debsigs / rpm --addsign) │
                              │    5. upload artifact                        │
                              └────────────────────┬─────────────────────────┘
                                                   │ after both jobs succeed
                                                   ▼
                              ┌───────────────────────────────────────────────┐
                              │  publish job                                  │
                              │   - download both artifacts                  │
                              │   - reprepro includedeb (gh-pages/debian/)   │
                              │   - createrepo_c          (gh-pages/el/9/)   │
                              │   - sign Release / repomd.xml                │
                              │   - commit + push gh-pages                   │
                              │   - attach both to GH Release                │
                              └────────────────────┬─────────────────────────┘
                                                   ▼
              ┌─────────────────────────────────────────────────────────────────┐
              │  https://cloudpbx.github.io/openkazoo-kazoo5-builder/           │
              │  (gh-pages branch)                                              │
              │                                                                 │
              │  ├── debian/                                                   │
              │  │   ├── dists/bookworm/{Release,InRelease,main/binary-amd64/} │
              │  │   └── pool/main/k/kazoo/kazoo_5.4.0-1~bookworm1_amd64.deb   │
              │  ├── el/9/                                                     │
              │  │   ├── openkazoo.repo  (yum .repo file end users curl down) │
              │  │   ├── repodata/{repomd.xml,*-primary.xml.gz,...}            │
              │  │   └── Packages/kazoo-5.4.0-1.el9.x86_64.rpm                 │
              │  ├── pubkey.asc                                                │
              │  └── README.md  (install instructions)                         │
              └─────────────────────────────────────────────────────────────────┘
                                          │
                ┌─────────────────────────┴────────────────────────┐
                ▼                                                  ▼
       End user on Debian 12:                    End user on Rocky 9 / Alma 9 / RHEL 9:
       apt-get install kazoo                     dnf install kazoo
```

### Key properties

- **Two-repo split**: upstream `kazoo5` is untouched; this builder owns packaging only.
- **Containerized, locally reproducible**: `make build TARGET=debian-12` works identically on a developer laptop and in CI.
- **Zero managed infrastructure**: no AWS, no Docker Hub publishing, no third-party SaaS. GitHub Pages hosts both apt and yum repos from one branch under different subpaths.
- **One signing key, one source of trust**: a single GPG key signs Debian `Release` files, RPM `repomd.xml`, and individual RPMs. Public key published in repo root and at `gh-pages/pubkey.asc`.
- **Per-distro Erlang/OTP** from Erlang Solutions:
  - Debian 12 → `packages.erlang-solutions.com/debian bookworm contrib`
  - EL 9 → `packages.erlang-solutions.com/rpm/centos/9/`

## 4. Repository layout

```
openkazoo-kazoo5-builder/
├── README.md                    # Public install instructions, project status
├── LICENSE                      # MIT (matches openkazoo)
├── Makefile                     # Top-level: `make build TARGET=debian-12`, `make publish`
│
├── .github/workflows/
│   ├── build.yml                # Matrix build on tag push (v5.*) + workflow_dispatch
│   └── verify-install.yml       # Post-release: end-to-end install test from published repo
│
├── config/                      # Single source of truth for pins
│   ├── kazoo.version            # e.g. 5.4.0
│   ├── otp.version              # e.g. 26.2.5
│   └── package.revision         # e.g. 1
│
├── docker/
│   ├── Dockerfile.debian-12     # FROM debian:12-slim + esl-erlang + fpm + reprepro/debsigs
│   └── Dockerfile.el9           # FROM rockylinux:9 + esl-erlang + fpm + createrepo_c/rpm-sign
│
├── packaging/
│   ├── common/                  # Identical across deb/rpm
│   │   ├── kazoo.service        # systemd unit
│   │   ├── kazoo.sysusers       # systemd-sysusers (creates 'kazoo' user)
│   │   ├── kazoo.tmpfiles       # /var/lib/kazoo, /var/log/kazoo
│   │   └── kazoo.defaults       # env defaults sourced by the unit
│   ├── deb/
│   │   ├── preinst.sh
│   │   ├── postinst.sh
│   │   ├── prerm.sh
│   │   ├── postrm.sh
│   │   └── fpm.args
│   └── rpm/
│       ├── pre.sh
│       ├── post.sh
│       ├── preun.sh
│       ├── postun.sh
│       └── fpm.args
│
├── scripts/
│   ├── build.sh                 # Universal entrypoint (Makefile, Docker, GHA all call it)
│   ├── publish.sh               # reprepro includedeb + createrepo_c + sign repo metadata
│   ├── sign.sh                  # debsigs / rpm --addsign with GPG_PRIVATE_KEY from env
│   └── verify.sh                # Smoke test: dpkg --info / rpm -qpi on fresh artifact
│
└── docs/
    ├── INSTALL.md               # End-user: add apt/yum source, import key, install
    ├── ARCHITECTURE.md          # Contributor-facing build pipeline docs
    ├── CONTRIBUTING.md          # How to bump versions, add a target, etc.
    └── superpowers/specs/
        └── 2026-05-12-kazoo5-debian-rpm-builder-design.md  # this document
```

### Design rationale

- **One entrypoint, one code path**: `scripts/build.sh` is what Makefile, Docker, and GHA all invoke. No drift between "local build" and "CI build".
- **Three-file version pinning**: `config/{kazoo,otp,package}.version` + `package.revision`. Bumping each is a one-line PR.
- **Shared `packaging/common/`**: systemd unit, sysusers, tmpfiles, defaults file are *not* duplicated between deb and rpm. Both `fpm` invocations reference the same files.
- **No upstream checkout in this repo**: `kazoo5` source is cloned fresh inside the build container at the pinned tag. Builder repo stays small; no submodules.

## 5. Build flow

### Dockerfile.debian-12

```dockerfile
FROM debian:12-slim
ARG OTP_VERSION=26.2.5

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git make build-essential \
      autoconf zip unzip xsltproc libxslt1-dev \
      libssl-dev libncurses-dev \
      python3 ruby ruby-dev rubygems \
      reprepro debsigs \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc \
      -o /usr/share/keyrings/erlang-solutions.asc \
 && echo "deb [signed-by=/usr/share/keyrings/erlang-solutions.asc] \
      https://packages.erlang-solutions.com/debian bookworm contrib" \
      > /etc/apt/sources.list.d/erlang-solutions.list \
 && apt-get update && apt-get install -y "esl-erlang=1:${OTP_VERSION}-1" \
 && rm -rf /var/lib/apt/lists/*

RUN gem install --no-document fpm:1.16.0

WORKDIR /work
ENTRYPOINT ["/work/scripts/build.sh"]
```

`Dockerfile.el9` is structurally identical: `FROM rockylinux:9`, enable EPEL + Erlang Solutions yum repo, install matching `esl-erlang`, install `rpm-build rpm-sign createrepo_c`, install `fpm` via rubygem.

### scripts/build.sh — universal entrypoint

```bash
#!/usr/bin/env bash
set -euo pipefail

# Required env (set by Makefile or GHA matrix):
#   TARGET           debian-12 | el9
#   KAZOO_VERSION    e.g. 5.4.0     (from config/kazoo.version)
#   OTP_VERSION      e.g. 26.2.5    (from config/otp.version, asserted against host runtime)
#   PKG_REVISION     e.g. 1         (from config/package.revision)

WORKDIR=/work
SRC_DIR=$WORKDIR/build/kazoo5-src
STAGE_DIR=$WORKDIR/build/stage
OUT_DIR=$WORKDIR/build/out

# 1. Fetch upstream source at pinned tag
rm -rf "$SRC_DIR" && mkdir -p "$SRC_DIR"
git clone --depth 1 --branch "$KAZOO_VERSION" \
    https://github.com/2600hz/kazoo5.git "$SRC_DIR"

# 2. Build Erlang release
cd "$SRC_DIR"
make compile
make tar-release

# 3. Stage files into FHS layout under $STAGE_DIR
rm -rf "$STAGE_DIR" && mkdir -p "$STAGE_DIR/opt/kazoo"
tar -xzf "_rel/kazoo/kazoo-${KAZOO_VERSION}.tar.gz" -C "$STAGE_DIR/opt/kazoo"
install -Dm644 /work/packaging/common/kazoo.service   "$STAGE_DIR/lib/systemd/system/kazoo.service"
install -Dm644 /work/packaging/common/kazoo.sysusers  "$STAGE_DIR/usr/lib/sysusers.d/kazoo.conf"
install -Dm644 /work/packaging/common/kazoo.tmpfiles  "$STAGE_DIR/usr/lib/tmpfiles.d/kazoo.conf"
install -Dm644 /work/packaging/common/kazoo.defaults  "$STAGE_DIR/etc/default/kazoo"

# 4. Wrap with fpm
mkdir -p "$OUT_DIR" && cd "$OUT_DIR"
case "$TARGET" in
  debian-12)
    fpm -s dir -t deb \
        --name kazoo \
        --version "$KAZOO_VERSION" \
        --iteration "${PKG_REVISION}~bookworm1" \
        --architecture amd64 \
        --depends "esl-erlang (>= ${OTP_VERSION%.*})" \
        --depends "adduser" \
        --depends "systemd" \
        --maintainer "openkazoo <support@cloudpbx.example>" \
        --description "Kazoo telephony platform (community build of 2600hz/kazoo5)" \
        --url "https://github.com/cloudpbx/openkazoo-kazoo5-builder" \
        --license "MPL-1.1" \
        --before-install /work/packaging/deb/preinst.sh \
        --after-install  /work/packaging/deb/postinst.sh \
        --before-remove  /work/packaging/deb/prerm.sh \
        --after-remove   /work/packaging/deb/postrm.sh \
        -C "$STAGE_DIR" .
    ;;
  el9)
    fpm -s dir -t rpm \
        --name kazoo \
        --version "$KAZOO_VERSION" \
        --iteration "${PKG_REVISION}.el9" \
        --architecture x86_64 \
        --depends "esl-erlang >= ${OTP_VERSION%.*}" \
        --depends "shadow-utils" \
        --depends "systemd" \
        --rpm-dist el9 \
        --rpm-summary "Kazoo telephony platform" \
        --maintainer "openkazoo <support@cloudpbx.example>" \
        --description "Kazoo telephony platform (community build of 2600hz/kazoo5)" \
        --url "https://github.com/cloudpbx/openkazoo-kazoo5-builder" \
        --license "MPL-1.1" \
        --before-install /work/packaging/rpm/pre.sh \
        --after-install  /work/packaging/rpm/post.sh \
        --before-remove  /work/packaging/rpm/preun.sh \
        --after-remove   /work/packaging/rpm/postun.sh \
        -C "$STAGE_DIR" .
    ;;
esac
```

### File layout inside the .deb / .rpm

```
/opt/kazoo/                              # Erlang release tree (unmodified relx output)
├── bin/                                 # kazoo, kazoo_apps, ...
├── erts-X.Y.Z/                          # bundled OTP runtime fragment
├── lib/                                 # BEAM apps
├── releases/5.4.0/
└── ...

/lib/systemd/system/kazoo.service        # systemd unit
/usr/lib/sysusers.d/kazoo.conf           # creates 'kazoo' system user on install
/usr/lib/tmpfiles.d/kazoo.conf           # creates /var/lib/kazoo, /var/log/kazoo
/etc/default/kazoo                       # env vars; conffile/%config(noreplace)
```

### Service lifecycle (postinst summary)

```bash
# packaging/deb/postinst.sh (rpm/post.sh is equivalent)
set -e
systemd-sysusers /usr/lib/sysusers.d/kazoo.conf
systemd-tmpfiles --create /usr/lib/tmpfiles.d/kazoo.conf
chown -R kazoo:kazoo /var/lib/kazoo /var/log/kazoo
systemctl daemon-reload
# Do NOT auto-enable or auto-start — leave to the admin (debian policy + safer default)
```

`prerm`/`preun` stops the service if running. `postrm`/`postun` on `purge`/full-remove cleans log/lib dirs but not the system user (debian convention; rpm follows similarly).

### GitHub Actions workflow

```yaml
# .github/workflows/build.yml
on:
  push:
    tags: ['v5.*']
  workflow_dispatch:
    inputs:
      kazoo_version:
        required: false
        description: Override config/kazoo.version (for ad-hoc test builds)

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        target: [debian-12, el9]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make build TARGET=${{ matrix.target }}
      - run: make sign  TARGET=${{ matrix.target }}
        env:
          GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
          GPG_PASSPHRASE:  ${{ secrets.GPG_PASSPHRASE }}
      - run: make verify TARGET=${{ matrix.target }}
      - uses: actions/upload-artifact@v4
        with:
          name: kazoo-${{ matrix.target }}
          path: build/out/*

  publish:
    needs: build
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { ref: gh-pages }
      - uses: actions/download-artifact@v4
      - run: make publish
        env:
          GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
          GPG_PASSPHRASE:  ${{ secrets.GPG_PASSPHRASE }}
      - run: |
          git add -A
          git -c user.name=openkazoo-bot \
              -c user.email=bot@cloudpbx.example \
              commit -m "publish ${GITHUB_REF_NAME}"
          git push origin gh-pages
      - uses: softprops/action-gh-release@v2
        with:
          files: 'build/out/*'
```

### Secrets required in the GH repo

| Secret | Purpose |
|---|---|
| `GPG_PRIVATE_KEY` | Armored private key — signs `.deb`, `.rpm`, apt `Release`, yum `repomd.xml` |
| `GPG_PASSPHRASE` | Required only if the key is passphrase-protected |

No AWS keys, no Docker Hub credentials, no third-party SaaS tokens.

## 6. Testing & verification

Three layers, all in CI:

**Layer 1 — Lint (every PR)**
- `shellcheck` against `scripts/*.sh`, `packaging/**/*.sh`
- `hadolint` against `docker/Dockerfile.*`
- YAML lint against `.github/workflows/`

**Layer 2 — Package smoke test (every build, in the matrix job, pre-publish)**
After `fpm` produces the artifact:
- `dpkg --info` / `rpm -qpi` to validate metadata.
- `dpkg --contents` / `rpm -qpl` asserts `/opt/kazoo/bin/kazoo` and `/lib/systemd/system/kazoo.service` are present.
- Optional: attempt full install in a clean target container with ESL repo enabled (skipped in MVP; revisit if package layout bugs slip through).

**Layer 3 — End-to-end install test (post-release, in `verify-install.yml`)**
A separate workflow spins up clean `debian:12-slim` / `rockylinux:9` containers and follows the published `INSTALL.md` steps verbatim:
1. Add apt/yum source for `cloudpbx.github.io/openkazoo-kazoo5-builder/...`
2. Import the GPG key from `pubkey.asc`
3. Add the Erlang Solutions source
4. Install `kazoo`
5. Assert `systemctl status kazoo` reports the unit as `loaded` (not necessarily `active`; full startup needs CouchDB/RabbitMQ which are out of MVP scope)

Lintian and rpmlint run as **warnings only** in MVP. FPM-produced packages will not be lintian-clean; chasing that prompts the Phase 2 migration to native packaging.

## 7. Versioning & release model

| File | Bumps when | Example |
|---|---|---|
| `config/kazoo.version` | Upstream Kazoo release (5.4.0 → 5.4.1) | `5.4.0` |
| `config/otp.version` | OTP track changes (matches `kazoo5/.tool-versions`) | `26.2.5` |
| `config/package.revision` | Packaging-only fix (systemd, postinst, etc.) | `1` |

**Bump workflow:** Each config change is a one-line PR. Merging to `main` does **not** trigger a build.

**Release workflow:** Maintainer creates a git tag `v{KAZOO_VERSION}-{PKG_REVISION}` (e.g. `v5.4.0-1`). Tag push fires the GHA workflow.

**Manual builds for testing:** Use `workflow_dispatch` with optional `kazoo_version` override. These produce downloadable artifacts on the workflow run but do **not** publish to `gh-pages`.

**Artifact naming:**
- Debian: `kazoo_5.4.0-1~bookworm1_amd64.deb`
- RPM: `kazoo-5.4.0-1.el9.x86_64.rpm`

The `~bookworm1` / `.el9` suffixes distinguish per-distro builds and allow multiple distros' artifacts to coexist in the same naming space when more distros are added in Phase 2.

## 8. End-user install instructions (target content of `docs/INSTALL.md`)

**Debian 12 (bookworm):**
```bash
# 1. Add Erlang Solutions repo (runtime dependency)
curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc \
  | sudo tee /usr/share/keyrings/erlang-solutions.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/erlang-solutions.asc] \
  https://packages.erlang-solutions.com/debian bookworm contrib" \
  | sudo tee /etc/apt/sources.list.d/erlang-solutions.list

# 2. Add openkazoo kazoo5 repo
curl -fsSL https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc \
  | sudo tee /usr/share/keyrings/openkazoo.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/openkazoo.asc] \
  https://cloudpbx.github.io/openkazoo-kazoo5-builder/debian bookworm main" \
  | sudo tee /etc/apt/sources.list.d/openkazoo.list

# 3. Install
sudo apt-get update
sudo apt-get install -y kazoo
```

**Rocky 9 / AlmaLinux 9 / RHEL 9:**
```bash
# 1. Erlang Solutions repo
sudo dnf install -y https://packages.erlang-solutions.com/rpm/centos/9/erlang-solutions-2.0-1.noarch.rpm

# 2. openkazoo kazoo5 repo
sudo dnf config-manager --add-repo \
  https://cloudpbx.github.io/openkazoo-kazoo5-builder/el/9/openkazoo.repo
sudo rpm --import https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc

# 3. Install
sudo dnf install -y kazoo
```

## 9. Risks & open questions

| Risk | Mitigation |
|---|---|
| Upstream `make tar-release` target or its output layout changes between minor versions | CI fails loudly; bumping `config/kazoo.version` is gated by a successful tag-build run. Smoke test asserts `/opt/kazoo/bin/kazoo` is present. |
| Erlang Solutions repo drops a version we depend on | `config/otp.version` is pinned; we can pin to the previous OTP and bump `package.revision`. ESL maintains older OTP packages for several years. |
| GPG signing key compromise | Key is GHA-only; rotate by generating a new key, bumping `package.revision`, re-signing existing packages, and updating `pubkey.asc`. End users must re-import the key once. |
| GitHub Pages outage or quota issues | GitHub Pages is generally reliable; Phase 2 can migrate to S3+CloudFront or Cloudsmith if scale demands. |
| 2600Hz publishes their own 5.4 RPMs and our build diverges semantically | Our package name (`kazoo`) is conservative; if 2600Hz publishes a differently-named RPM (`2600hz-kazoo`?), they coexist. If same name, users opt in by enabling our repo. |
| `2600hz/kazoo5` license restrictions on community redistribution | LICENSE file in upstream repo confirmed permissive (MPL-1.1); document this in our README. Verify before first release. |
| FPM-produced packages won't pass `lintian` strict mode | Accepted: lintian runs as warning-only in MVP. Phase 2 migration to debhelper if needed. |

**Open questions to resolve before implementation:**
- Confirm exact `make` targets produce a self-contained release tarball (verify `_rel/kazoo/kazoo-X.Y.Z.tar.gz` layout against `2600hz/kazoo5@5.4.0` or latest available tag).
- Confirm `2600hz/kazoo5` has a tag matching `v5.4.*` pattern (none was visible via the GitHub API at design time; may require building from `master` initially with a pseudo-version).
- Confirm the `kazoo` user/group conventions used by upstream Docker/RPM (UID/GID, home dir, shell) so our sysusers entry matches.
- Confirm whether the kazoo Erlang release embeds ERTS (relx default) or expects host OTP — affects whether the `esl-erlang` dependency is strict or advisory.
- Final maintainer contact email (placeholder `support@cloudpbx.example` used throughout this design).

## 10. Phase 2+ backlog

Explicitly deferred to keep MVP focused. Each item below is additive — none requires restructuring the MVP.

- **FreeSWITCH (2600Hz fork) packaging** — reuses Dockerfiles, GHA matrix, gh-pages publish; adds new source tree and `make build TARGET=...` invocation.
- **Kamailio (2600Hz fork) packaging** — same pattern.
- **Monster UI packaging** — JS frontend; trivial `noarch` package.
- **arm64 builds** — expand matrix to `target × arch`. Erlang has reasonable arm64 support.
- **Debian 11 (bullseye), Ubuntu 22.04 (jammy), Ubuntu 24.04 (noble)** — add Dockerfiles, matrix entries.
- **Rocky 8 / EL 8** — add Dockerfile, matrix entry, separate yum repo path.
- **Native debhelper / native RPM spec migration** — when scope or quality demands (Debian official upload, Clio internal adoption requiring lintian-clean, etc.).
- **Auto-bumping on upstream tag detection** — scheduled GHA workflow polls `2600hz/kazoo5` for new tags, opens PR bumping `config/kazoo.version`.
- **Reproducible builds** — timestamp normalization, `SOURCE_DATE_EPOCH`.
- **Signed apt source list bootstrap package** — small `cloudpbx-keyring.deb` to one-line the apt setup for end users.
- **Multi-component meta-package** — once FreeSWITCH/Kamailio/Monster UI are packaged, a `kazoo-platform` meta-package depending on all components.
- **Migration to Clio internal infrastructure** — if/when this graduates from community-OSS to a Clio production artifact: Buildkite pipeline mirroring this design, publish to S3-backed apt repo on Clio infra.

## 11. Implementation summary (handoff to writing-plans)

The implementation plan should cover:

1. **Repo bootstrap**: `Makefile`, `README.md`, `LICENSE`, `.gitignore`, `config/{kazoo,otp,package}.{version,revision}` files with initial values.
2. **Docker build images**: `docker/Dockerfile.debian-12`, `docker/Dockerfile.el9` and a `make docker-build TARGET=...` target.
3. **Universal build script**: `scripts/build.sh` and shared `packaging/common/*` (systemd unit, sysusers, tmpfiles, defaults).
4. **Package metadata**: `packaging/deb/{preinst,postinst,prerm,postrm}.sh` + `fpm.args`, and `packaging/rpm/{pre,post,preun,postun}.sh` + `fpm.args`.
5. **Signing**: `scripts/sign.sh` with GPG via `debsigs` (deb) and `rpm --addsign` (rpm).
6. **Publishing**: `scripts/publish.sh` with `reprepro` (deb) and `createrepo_c` (rpm), generating signed `Release`/`repomd.xml`. Also generates a `gh-pages/el/9/openkazoo.repo` file that end users `curl` to add the yum source in one step.
7. **CI wiring**: `.github/workflows/build.yml` (tag-driven matrix + publish) and `.github/workflows/verify-install.yml` (post-release E2E).
8. **Verification**: `scripts/verify.sh` for in-build smoke tests; install-from-published-repo E2E.
9. **End-user docs**: `docs/INSTALL.md`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`.
10. **First release dry-run**: produce v5.4.0-1 artifacts via `workflow_dispatch` and inspect before tagging.

Each component above is independently testable and can be developed in parallel by separate contributors after step 1 lands.

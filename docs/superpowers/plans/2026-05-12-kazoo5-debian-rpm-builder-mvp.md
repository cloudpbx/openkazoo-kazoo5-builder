# Kazoo 5 Debian + RPM Builder MVP — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a CI-driven build pipeline that produces signed `.deb` (Debian 12) and `.rpm` (EL9) packages of the Kazoo Erlang application from upstream `2600hz/kazoo5`, publishes them to a GitHub-Pages-hosted apt + yum repository, and is fully reproducible from a single `make` command locally.

**Architecture:** A small Make-driven wrapper over Docker. Per target distro, a Dockerfile builds an image with the toolchain (Erlang/OTP from Erlang Solutions + FPM); `scripts/build.sh` runs inside that image to clone upstream Kazoo at a pinned ref, compile, tarball, and wrap with FPM into a `.deb` or `.rpm`. GitHub Actions runs the same `make` targets in a matrix, signs the artifacts with GPG, and publishes the resulting apt + yum repos to the `gh-pages` branch. Design spec at `docs/superpowers/specs/2026-05-12-kazoo5-debian-rpm-builder-design.md`.

**Tech Stack:** Bash, GNU Make, Docker, FPM (Ruby gem), Erlang/OTP 26.2.5 (via Erlang Solutions), reprepro (Debian repo), createrepo_c (RPM repo), GPG (debsigs / rpm --addsign), bats-core (shell test framework), GitHub Actions.

**Critical pre-flight finding:** `2600hz/kazoo5` has no git tags published as of 2026-05-12. The first build must target the `master` branch with a date-stamped pseudo-version (`5.4.0~master.YYYYMMDD.shortsha`). When upstream tags appear, `config/kazoo.version` switches from `master` to e.g. `5.4.0` — a one-line change.

---

## File Structure

Files created or modified, with one-line responsibility:

```
Repo root
├── Makefile                                # one-line targets: build, sign, publish, verify, clean
├── README.md                               # public-facing: project status, link to INSTALL.md
├── LICENSE                                 # MIT
├── .gitignore                              # already exists (extended in Task 1)
│
├── .github/workflows/
│   ├── build.yml                           # tag-driven matrix build + publish
│   └── verify-install.yml                  # post-release E2E install test
│
├── config/                                 # all version pins; bumped via PR
│   ├── kazoo.version
│   ├── otp.version
│   ├── rebar.version
│   └── package.revision
│
├── docker/
│   ├── Dockerfile.debian-12                # debian:12-slim + esl-erlang + fpm + reprepro/debsigs
│   └── Dockerfile.el9                      # rockylinux:9 + esl-erlang + fpm + createrepo_c
│
├── packaging/
│   ├── common/                             # one source of truth across deb/rpm
│   │   ├── kazoo.service                   # systemd unit
│   │   ├── kazoo.sysusers                  # systemd-sysusers: creates 'kazoo' user
│   │   ├── kazoo.tmpfiles                  # /var/lib/kazoo, /var/log/kazoo
│   │   └── kazoo.defaults                  # /etc/default/kazoo env defaults
│   ├── deb/
│   │   ├── preinst.sh                      # noop hook (placeholder for future)
│   │   ├── postinst.sh                     # apply sysusers, tmpfiles; chown; daemon-reload
│   │   ├── prerm.sh                        # systemctl stop kazoo (best-effort)
│   │   └── postrm.sh                       # on purge: rm -rf /var/lib/kazoo /var/log/kazoo
│   └── rpm/
│       ├── pre.sh
│       ├── post.sh
│       ├── preun.sh
│       └── postun.sh
│
├── scripts/
│   ├── build.sh                            # universal entrypoint: clone, compile, tarball, fpm
│   ├── sign.sh                             # debsigs (.deb) + rpm --addsign (.rpm)
│   ├── publish.sh                          # reprepro + createrepo_c; emits openkazoo.repo
│   └── verify.sh                           # dpkg --info / rpm -qpi smoke tests
│
├── tests/                                  # bats-core shell tests
│   ├── bats/                               # git submodule: bats-core
│   ├── test_helper/                        # shared bash helpers
│   │   └── common.bash
│   ├── unit/
│   │   ├── build.bats                      # build.sh arg parsing + preflight
│   │   ├── sign.bats                       # sign.sh round-trip with throwaway key
│   │   ├── publish.bats                    # publish.sh produces well-formed metadata
│   │   └── verify.bats                     # verify.sh asserts package contents
│   └── fixtures/
│       └── mock-kazoo5/                    # tiny fake upstream for fast unit tests
│           ├── Makefile
│           ├── VERSION
│           └── _rel/kazoo/kazoo-FAKE.tar.gz
│
└── docs/
    ├── INSTALL.md                          # end-user install instructions
    ├── ARCHITECTURE.md                     # contributor build-pipeline docs
    ├── CONTRIBUTING.md                     # how to bump versions, add a target
    └── superpowers/
        ├── specs/2026-05-12-kazoo5-debian-rpm-builder-design.md   # exists
        └── plans/2026-05-12-kazoo5-debian-rpm-builder-mvp.md      # this file
```

---

## Conventions used throughout this plan

- **All commands run from the repo root** (`/Users/grahamnsnz/Projects/openkazoo-kazoo5-builder`) unless noted.
- **Commits are atomic and small.** Each task ends with one or more commits; commit messages follow `<type>: <subject>` (`feat:`, `chore:`, `docs:`, `test:`, `fix:`, `ci:`).
- **TDD adaptation for shell scripts:** each script gets bats tests written first, fails, then minimal implementation. For build outputs (`.deb`/`.rpm`), verification is direct package inspection (`dpkg-deb --info`, `rpm -qpi`).
- **Docker pulls are large.** First task that pulls `debian:12-slim` or `rockylinux:9` may take a couple of minutes; subsequent tasks reuse the cached image.
- **GPG for local testing** uses an ephemeral throwaway key generated in `tests/fixtures/gpg/`. The CI uses `secrets.GPG_PRIVATE_KEY`. These are different keys; do not commit the local-test key.
- **Don't push intermediate commits.** Each task's commits land on `main` locally; pushing to `origin/main` happens explicitly in Task 14.

---

## Task 1: Repo scaffolding and Makefile skeleton

**Goal:** Lay down the directory structure, version pins, Makefile entrypoints, README, LICENSE. No build logic yet — just the bones.

**Files:**
- Create: `Makefile`
- Create: `README.md`
- Create: `LICENSE`
- Create: `config/kazoo.version`
- Create: `config/otp.version`
- Create: `config/rebar.version`
- Create: `config/package.revision`
- Modify: `.gitignore` (extend)
- Create (empty placeholders): `docker/.gitkeep`, `packaging/common/.gitkeep`, `packaging/deb/.gitkeep`, `packaging/rpm/.gitkeep`, `scripts/.gitkeep`, `tests/.gitkeep`

- [ ] **Step 1: Create version-pin files**

```bash
mkdir -p config docker packaging/{common,deb,rpm} scripts tests/{unit,fixtures,test_helper} .github/workflows docs

echo "master" > config/kazoo.version
echo "26.2.5" > config/otp.version
echo "3.23.0" > config/rebar.version
echo "1"      > config/package.revision
```

These four files are the entire version surface. Bumping kazoo from `master` to (eventually) `5.4.0` is a one-line PR. `package.revision` increments when packaging metadata changes but kazoo source does not (e.g., systemd unit fix).

- [ ] **Step 2: Write the Makefile**

Create `Makefile`:

```makefile
# Kazoo 5 Debian + RPM builder
# Top-level entrypoints. All real logic lives in scripts/*.sh.

SHELL          := /usr/bin/env bash
.SHELLFLAGS    := -euo pipefail -c
.DEFAULT_GOAL  := help

# --- Version pins (single source of truth) ---
KAZOO_VERSION  := $(shell cat config/kazoo.version)
OTP_VERSION    := $(shell cat config/otp.version)
REBAR_VERSION  := $(shell cat config/rebar.version)
PKG_REVISION   := $(shell cat config/package.revision)

# --- Required per-invocation variable ---
TARGET         ?=

VALID_TARGETS  := debian-12 el9

# --- Build directories ---
BUILD_DIR      := build
OUT_DIR        := $(BUILD_DIR)/out

export KAZOO_VERSION OTP_VERSION REBAR_VERSION PKG_REVISION

.PHONY: help
help:  ## Show available targets
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | sort \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  TARGET=$(VALID_TARGETS)  (required for build/sign/verify)"
	@echo "  KAZOO_VERSION=$(KAZOO_VERSION) OTP_VERSION=$(OTP_VERSION) PKG_REVISION=$(PKG_REVISION)"

.PHONY: check-target
check-target:
	@if [ -z "$(TARGET)" ]; then \
	  echo "ERROR: TARGET is required. One of: $(VALID_TARGETS)"; exit 2; \
	fi
	@case " $(VALID_TARGETS) " in \
	  *" $(TARGET) "*) ;; \
	  *) echo "ERROR: TARGET=$(TARGET) invalid. One of: $(VALID_TARGETS)"; exit 2 ;; \
	esac

.PHONY: docker-build
docker-build: check-target  ## Build the docker image for TARGET
	docker build \
	  --build-arg OTP_VERSION=$(OTP_VERSION) \
	  --build-arg REBAR_VERSION=$(REBAR_VERSION) \
	  -t openkazoo-kazoo5-builder:$(TARGET) \
	  -f docker/Dockerfile.$(TARGET) .

.PHONY: build
build: check-target docker-build  ## Produce a package for TARGET in $(OUT_DIR)
	mkdir -p $(OUT_DIR)
	docker run --rm \
	  -v $(CURDIR):/work \
	  -e TARGET=$(TARGET) \
	  -e KAZOO_VERSION -e OTP_VERSION -e REBAR_VERSION -e PKG_REVISION \
	  openkazoo-kazoo5-builder:$(TARGET) \
	  /work/scripts/build.sh

.PHONY: sign
sign: check-target  ## Sign the package for TARGET (requires GPG_PRIVATE_KEY in env or files in tests/fixtures/gpg/)
	./scripts/sign.sh $(TARGET)

.PHONY: verify
verify: check-target  ## Smoke-test the package for TARGET
	./scripts/verify.sh $(TARGET)

.PHONY: publish
publish:  ## Build apt + yum repos under build/repo/ for both targets (assumes build/out/ populated)
	./scripts/publish.sh

.PHONY: test
test:  ## Run bats unit tests
	./tests/bats/bin/bats tests/unit/

.PHONY: clean
clean:  ## Remove build outputs (does NOT remove docker images)
	rm -rf $(BUILD_DIR)

.PHONY: sparkly-clean
sparkly-clean: clean  ## Also remove docker images
	-docker image rm openkazoo-kazoo5-builder:debian-12 openkazoo-kazoo5-builder:el9 2>/dev/null
```

- [ ] **Step 3: Write the README**

Create `README.md`:

````markdown
# openkazoo-kazoo5-builder

Community-built Debian (12) and RPM (EL9) packages for [Kazoo v5](https://github.com/2600hz/kazoo5), the open-source telephony platform from 2600Hz.

**Status:** alpha — see `docs/superpowers/specs/2026-05-12-kazoo5-debian-rpm-builder-design.md` for the design.

## Install

See [docs/INSTALL.md](docs/INSTALL.md) for end-user install instructions.

## Build locally

```bash
make build TARGET=debian-12        # produces build/out/kazoo_*.deb
make build TARGET=el9              # produces build/out/kazoo-*.rpm
```

See `make help` for all targets.

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
````

- [ ] **Step 4: Write the LICENSE**

Create `LICENSE` (standard MIT, year 2026, copyright "openkazoo contributors"):

```
MIT License

Copyright (c) 2026 openkazoo contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 5: Extend .gitignore**

Replace `.gitignore` contents with:

```
# Build artifacts
build/
_rel/
*.deb
*.rpm

# OS noise
.DS_Store
Thumbs.db

# Editor noise
*.swp
*~
.vscode/
.idea/

# Secrets — never commit
*.asc.private
*.gpg
gpg-agent.*
tests/fixtures/gpg/
```

(The new line is `tests/fixtures/gpg/` — the local-only test GPG keyring.)

- [ ] **Step 6: Verify the skeleton holds together**

Run:

```bash
make help
```

Expected output (formatting may vary by terminal width):

```
Targets:
  build              Produce a package for TARGET in build/out
  check-target
  clean              Remove build outputs (does NOT remove docker images)
  docker-build       Build the docker image for TARGET
  help               Show available targets
  publish            Build apt + yum repos under build/repo/ for both targets ...
  sign               Sign the package for TARGET (requires GPG_PRIVATE_KEY ...)
  sparkly-clean      Also remove docker images
  test               Run bats unit tests
  verify             Smoke-test the package for TARGET

Variables:
  TARGET=debian-12 el9  (required for build/sign/verify)
  KAZOO_VERSION=master OTP_VERSION=26.2.5 PKG_REVISION=1
```

Also run:

```bash
make build
```

Expected: exits with code 2, message `ERROR: TARGET is required. One of: debian-12 el9`. (Don't pass a TARGET yet — we just want to confirm the error path.)

- [ ] **Step 7: Commit**

```bash
git add Makefile README.md LICENSE .gitignore config/
git commit -m "feat: repo skeleton with Makefile, version pins, README, LICENSE"
```

---

## Task 2: Bats test harness

**Goal:** Add the bats-core shell-testing framework as a git submodule, write a sanity test, get `make test` working.

**Files:**
- Create: `tests/bats/` (submodule)
- Create: `tests/test_helper/common.bash`
- Create: `tests/unit/sanity.bats`

- [ ] **Step 1: Add bats-core as a git submodule**

```bash
git submodule add https://github.com/bats-core/bats-core.git tests/bats
```

(If submodules are objected to for any reason — e.g. CI complications — fall back to a curl-based install in CI and add `tests/bats/` to `.gitignore`. Submodules are simpler.)

- [ ] **Step 2: Write the shared bash helper**

Create `tests/test_helper/common.bash`:

```bash
# Common bash helpers for bats tests.
#
# Source this from a .bats file with:
#   load '../test_helper/common.bash'

# Repo root, available as $REPO_ROOT
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Helper: assert that the captured ${output} contains a substring.
# Usage: assert_output_contains "expected substring"
assert_output_contains() {
  local needle="$1"
  if ! echo "$output" | grep -qF -- "$needle"; then
    echo "Expected output to contain: $needle"
    echo "Actual output:"
    echo "$output"
    return 1
  fi
}

# Helper: assert exit status was a given value.
# Usage: assert_status 2
assert_status() {
  local expected="$1"
  if [ "$status" -ne "$expected" ]; then
    echo "Expected status: $expected, got: $status"
    echo "Output:"
    echo "$output"
    return 1
  fi
}
```

- [ ] **Step 3: Write a sanity test**

Create `tests/unit/sanity.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "REPO_ROOT points at the repo containing this plan" {
  [ -f "$REPO_ROOT/Makefile" ]
  [ -f "$REPO_ROOT/config/kazoo.version" ]
}

@test "version pins are non-empty and trimmed" {
  local v
  for f in kazoo.version otp.version rebar.version package.revision; do
    v=$(cat "$REPO_ROOT/config/$f")
    [ -n "$v" ]
    # Must not contain trailing whitespace or newlines within
    [ "$(echo -n "$v" | wc -l | tr -d ' ')" -eq 0 ]
  done
}

@test "make help mentions both targets" {
  run make -C "$REPO_ROOT" help
  assert_status 0
  assert_output_contains "debian-12"
  assert_output_contains "el9"
}

@test "make build without TARGET fails with code 2" {
  run make -C "$REPO_ROOT" build
  assert_status 2
  assert_output_contains "TARGET is required"
}
```

- [ ] **Step 4: Run the tests**

```bash
make test
```

Expected:

```
1..4
ok 1 REPO_ROOT points at the repo containing this plan
ok 2 version pins are non-empty and trimmed
ok 3 make help mentions both targets
ok 4 make build without TARGET fails with code 2
```

- [ ] **Step 5: Commit**

```bash
git add .gitmodules tests/
git commit -m "test: add bats-core submodule and sanity tests"
```

---

## Task 3: Shared packaging assets (systemd, sysusers, tmpfiles, defaults)

**Goal:** Define the systemd unit and runtime file/user contracts. These are shared verbatim between deb and rpm builds.

**Files:**
- Create: `packaging/common/kazoo.service`
- Create: `packaging/common/kazoo.sysusers`
- Create: `packaging/common/kazoo.tmpfiles`
- Create: `packaging/common/kazoo.defaults`
- Create: `tests/unit/common_assets.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/common_assets.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "kazoo.service is a valid systemd unit (passes systemd-analyze verify in container)" {
  # Quick syntactic checks here; full verify happens in the install-test workflow.
  local f="$REPO_ROOT/packaging/common/kazoo.service"
  [ -f "$f" ]
  grep -q "^\[Unit\]" "$f"
  grep -q "^\[Service\]" "$f"
  grep -q "^\[Install\]" "$f"
  grep -q "^User=kazoo" "$f"
  grep -q "^Group=kazoo" "$f"
  grep -q "EnvironmentFile=-/etc/default/kazoo" "$f"
  grep -q "ExecStart=" "$f"
  grep -q "^WantedBy=multi-user.target" "$f"
}

@test "kazoo.sysusers declares user kazoo with home in /var/lib/kazoo" {
  local f="$REPO_ROOT/packaging/common/kazoo.sysusers"
  [ -f "$f" ]
  # Format: "u kazoo - 'Kazoo platform' /var/lib/kazoo /usr/sbin/nologin"
  grep -qE "^u +kazoo " "$f"
  grep -q "/var/lib/kazoo" "$f"
  grep -q "/usr/sbin/nologin" "$f"
}

@test "kazoo.tmpfiles creates /var/lib/kazoo and /var/log/kazoo owned by kazoo:kazoo" {
  local f="$REPO_ROOT/packaging/common/kazoo.tmpfiles"
  [ -f "$f" ]
  grep -qE "^d +/var/lib/kazoo +0750 +kazoo +kazoo " "$f"
  grep -qE "^d +/var/log/kazoo +0750 +kazoo +kazoo " "$f"
}

@test "kazoo.defaults defines NODE_NAME, COOKIE, and ERL_FLAGS as documented env" {
  local f="$REPO_ROOT/packaging/common/kazoo.defaults"
  [ -f "$f" ]
  grep -q "^NODE_NAME=" "$f"
  grep -q "^COOKIE=" "$f"
  grep -q "^ERL_FLAGS=" "$f"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | tail -30
```

Expected: 4 tests fail with messages like `[ -f "$REPO_ROOT/packaging/common/kazoo.service" ]` failing. The 4 sanity tests from Task 2 still pass.

- [ ] **Step 3: Write packaging/common/kazoo.service**

```ini
[Unit]
Description=Kazoo telephony platform
Documentation=https://github.com/cloudpbx/openkazoo-kazoo5-builder
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=kazoo
Group=kazoo
EnvironmentFile=-/etc/default/kazoo
WorkingDirectory=/var/lib/kazoo
ExecStart=/opt/kazoo/bin/kazoo start
ExecStop=/opt/kazoo/bin/kazoo stop
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535
# Hardening (conservative defaults; tighten in a later phase)
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 4: Write packaging/common/kazoo.sysusers**

```
# Type Name  ID GECOS                       Home           Shell
u     kazoo  -  "Kazoo platform"            /var/lib/kazoo /usr/sbin/nologin
```

- [ ] **Step 5: Write packaging/common/kazoo.tmpfiles**

```
# Type Path             Mode  User   Group  Age  Argument
d     /var/lib/kazoo    0750  kazoo  kazoo  -    -
d     /var/log/kazoo    0750  kazoo  kazoo  -    -
```

- [ ] **Step 6: Write packaging/common/kazoo.defaults**

```sh
# /etc/default/kazoo
# Environment for the kazoo systemd service.
# Edit this file to customize. Marked as a conffile / %config(noreplace);
# package upgrades will not overwrite your changes.

# Erlang node short name for this host. Must be unique per cluster member.
NODE_NAME=kazoo_apps@127.0.0.1

# Erlang distribution cookie. CHANGE THIS to a strong secret in production.
# All nodes in the same Kazoo cluster must share the same cookie.
COOKIE=change-me-please

# Additional Erlang VM flags (e.g. memory limits).
ERL_FLAGS=""
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
make test
```

Expected: 8 tests pass (4 from Task 2 + 4 new).

- [ ] **Step 8: Commit**

```bash
git add packaging/common/ tests/unit/common_assets.bats
git commit -m "feat: shared packaging assets (systemd unit, sysusers, tmpfiles, defaults)"
```

---

## Task 4: Debian packaging scriptlets

**Goal:** Write the maintainer scripts that run on `apt install` / `apt remove` / `apt purge`.

**Files:**
- Create: `packaging/deb/preinst.sh`
- Create: `packaging/deb/postinst.sh`
- Create: `packaging/deb/prerm.sh`
- Create: `packaging/deb/postrm.sh`
- Create: `tests/unit/deb_scriptlets.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/deb_scriptlets.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "deb scriptlets exist and are executable" {
  for f in preinst postinst prerm postrm; do
    local p="$REPO_ROOT/packaging/deb/${f}.sh"
    [ -f "$p" ] || { echo "MISSING: $p"; return 1; }
    [ -x "$p" ] || { echo "NOT EXECUTABLE: $p"; return 1; }
  done
}

@test "deb scriptlets start with shebang and 'set -e'" {
  for f in preinst postinst prerm postrm; do
    local p="$REPO_ROOT/packaging/deb/${f}.sh"
    head -1 "$p" | grep -q "^#!/" || { echo "no shebang: $p"; return 1; }
    grep -q "^set -e" "$p" || { echo "no 'set -e': $p"; return 1; }
  done
}

@test "postinst.sh applies sysusers and tmpfiles, runs daemon-reload" {
  local p="$REPO_ROOT/packaging/deb/postinst.sh"
  grep -q "systemd-sysusers" "$p"
  grep -q "systemd-tmpfiles" "$p"
  grep -q "systemctl daemon-reload" "$p"
}

@test "prerm.sh stops the service idempotently" {
  local p="$REPO_ROOT/packaging/deb/prerm.sh"
  grep -q "systemctl stop kazoo" "$p"
}

@test "postrm.sh removes /var/lib/kazoo /var/log/kazoo on purge only" {
  local p="$REPO_ROOT/packaging/deb/postrm.sh"
  # Match within shell case branch
  grep -q 'purge)' "$p"
  grep -q "rm -rf /var/lib/kazoo" "$p"
  grep -q "rm -rf /var/log/kazoo" "$p"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | grep -E "not ok|fail" | head
```

Expected: 5 new failures.

- [ ] **Step 3: Write packaging/deb/preinst.sh**

```bash
#!/usr/bin/env bash
# Pre-install scriptlet for kazoo (Debian).
# Runs before package files are unpacked. Keep this minimal.
set -e

# Currently a noop; reserved for future use (e.g., backup of config before
# upgrades that change config layout).

exit 0
```

- [ ] **Step 4: Write packaging/deb/postinst.sh**

```bash
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
```

- [ ] **Step 5: Write packaging/deb/prerm.sh**

```bash
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
```

- [ ] **Step 6: Write packaging/deb/postrm.sh**

```bash
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
    rm -rf /var/lib/kazoo /var/log/kazoo
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
```

- [ ] **Step 7: Make all four executable**

```bash
chmod +x packaging/deb/{preinst,postinst,prerm,postrm}.sh
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
make test
```

Expected: 13 tests pass (8 prior + 5 new).

- [ ] **Step 9: Commit**

```bash
git add packaging/deb/ tests/unit/deb_scriptlets.bats
git commit -m "feat: Debian maintainer scripts (preinst/postinst/prerm/postrm)"
```

---

## Task 5: RPM packaging scriptlets

**Goal:** Mirror Task 4 for RPM-side maintainer scripts. RPM scriptlets take a numeric `$1` (count of remaining package versions) instead of action strings.

**Files:**
- Create: `packaging/rpm/pre.sh`
- Create: `packaging/rpm/post.sh`
- Create: `packaging/rpm/preun.sh`
- Create: `packaging/rpm/postun.sh`
- Create: `tests/unit/rpm_scriptlets.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/rpm_scriptlets.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "rpm scriptlets exist and are executable" {
  for f in pre post preun postun; do
    local p="$REPO_ROOT/packaging/rpm/${f}.sh"
    [ -f "$p" ] || { echo "MISSING: $p"; return 1; }
    [ -x "$p" ] || { echo "NOT EXECUTABLE: $p"; return 1; }
  done
}

@test "rpm post.sh applies sysusers and tmpfiles, runs daemon-reload" {
  local p="$REPO_ROOT/packaging/rpm/post.sh"
  grep -q "systemd-sysusers" "$p"
  grep -q "systemd-tmpfiles" "$p"
  grep -q "systemctl daemon-reload" "$p"
}

@test "rpm preun.sh stops the service only on final removal" {
  local p="$REPO_ROOT/packaging/rpm/preun.sh"
  # On RPM, $1=0 means "final uninstall"; $1=1 means "upgrade in progress"
  grep -q '\[ "\$1" -eq 0 \]' "$p" || grep -qE 'if .*\$1.*-eq.*0' "$p"
  grep -q "systemctl stop kazoo" "$p"
}

@test "rpm postun.sh removes runtime dirs on final removal" {
  local p="$REPO_ROOT/packaging/rpm/postun.sh"
  grep -q "rm -rf /var/lib/kazoo" "$p"
  grep -q "rm -rf /var/log/kazoo" "$p"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | grep -E "not ok" | head
```

Expected: 4 new failures.

- [ ] **Step 3: Write packaging/rpm/pre.sh**

```bash
#!/usr/bin/env bash
# Pre-install scriptlet for kazoo (RPM).
# $1: 1 = first install, 2 = upgrade
set -e

exit 0
```

- [ ] **Step 4: Write packaging/rpm/post.sh**

```bash
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

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload || true
fi

exit 0
```

- [ ] **Step 5: Write packaging/rpm/preun.sh**

```bash
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
```

- [ ] **Step 6: Write packaging/rpm/postun.sh**

```bash
#!/usr/bin/env bash
# Post-uninstall scriptlet for kazoo (RPM).
# $1: 0 = final uninstall, 1 = upgrade in progress
set -e

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload || true
fi

if [ "$1" -eq 0 ]; then
  # Final uninstall: remove runtime dirs (matches dpkg purge behavior)
  rm -rf /var/lib/kazoo /var/log/kazoo
fi

exit 0
```

- [ ] **Step 7: Make all four executable**

```bash
chmod +x packaging/rpm/{pre,post,preun,postun}.sh
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
make test
```

Expected: 17 tests pass (13 prior + 4 new).

- [ ] **Step 9: Commit**

```bash
git add packaging/rpm/ tests/unit/rpm_scriptlets.bats
git commit -m "feat: RPM maintainer scripts (pre/post/preun/postun)"
```

---

## Task 6: Dockerfile.debian-12

**Goal:** A Debian 12 builder image with Erlang Solutions OTP, rebar3, FPM, and the apt-repo tooling baked in.

**Files:**
- Create: `docker/Dockerfile.debian-12`
- Create: `tests/unit/dockerfile_debian.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/dockerfile_debian.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "Dockerfile.debian-12 exists and declares the expected base image" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  [ -f "$f" ]
  grep -q "^FROM debian:12-slim" "$f"
}

@test "Dockerfile.debian-12 accepts OTP_VERSION and REBAR_VERSION build args" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  grep -q "^ARG OTP_VERSION=" "$f"
  grep -q "^ARG REBAR_VERSION=" "$f"
}

@test "Dockerfile.debian-12 installs reprepro, debsigs, fpm, esl-erlang" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  grep -q "reprepro" "$f"
  grep -q "debsigs" "$f"
  grep -q "gem install" "$f"
  grep -q "fpm" "$f"
  grep -q "esl-erlang" "$f"
}

@test "Dockerfile.debian-12 sets WORKDIR /work and ENTRYPOINT to build.sh" {
  local f="$REPO_ROOT/docker/Dockerfile.debian-12"
  grep -q "^WORKDIR /work" "$f"
  grep -q 'ENTRYPOINT \["/work/scripts/build.sh"\]' "$f"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | grep -E "not ok" | head
```

- [ ] **Step 3: Write docker/Dockerfile.debian-12**

```dockerfile
# syntax=docker/dockerfile:1.6
# Build image for Debian 12 (bookworm) packages.

FROM debian:12-slim

ARG OTP_VERSION=26.2.5
ARG REBAR_VERSION=3.23.0
ARG DEBIAN_FRONTEND=noninteractive

# Toolchain: build tools, packaging utilities, Ruby (for FPM), Erlang/OTP from ESL.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git make build-essential \
      autoconf zip unzip xsltproc libxslt1-dev \
      libssl-dev libncurses-dev \
      python3 ruby ruby-dev rubygems \
      reprepro debsigs \
 && rm -rf /var/lib/apt/lists/*

# Erlang Solutions apt source. The same .asc key works for Debian and Ubuntu repos.
RUN curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc \
      -o /usr/share/keyrings/erlang-solutions.asc \
 && echo "deb [signed-by=/usr/share/keyrings/erlang-solutions.asc] \
https://packages.erlang-solutions.com/debian bookworm contrib" \
      > /etc/apt/sources.list.d/erlang-solutions.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends "esl-erlang=1:${OTP_VERSION}-1" \
 && rm -rf /var/lib/apt/lists/*

# rebar3 (matches kazoo5/.tool-versions). Fetch the pinned binary from upstream.
RUN curl -fsSL "https://github.com/erlang/rebar3/releases/download/${REBAR_VERSION}/rebar3" \
      -o /usr/local/bin/rebar3 \
 && chmod +x /usr/local/bin/rebar3 \
 && rebar3 --version

# FPM for wrapping the relx tarball into .deb
RUN gem install --no-document fpm:1.16.0

WORKDIR /work
ENTRYPOINT ["/work/scripts/build.sh"]
```

- [ ] **Step 4: Run the bats tests (static)**

```bash
make test
```

Expected: 21 tests pass (17 prior + 4 new).

- [ ] **Step 5: Build the image and verify the toolchain**

```bash
make docker-build TARGET=debian-12
```

This will take 3-5 minutes on first run (apt update + esl-erlang download is ~200MB). Subsequent rebuilds use the Docker layer cache.

Then verify the toolchain works:

```bash
docker run --rm openkazoo-kazoo5-builder:debian-12 bash -c "
  erl -version 2>&1 &&
  rebar3 --version &&
  fpm --version &&
  reprepro --version &&
  debsigs --help 2>&1 | head -1
"
```

Expected output (versions may differ slightly):

```
Erlang (SMP,ASYNC_THREADS) (BEAM) emulator version 14.2.5
rebar 3.23.0 on Erlang/OTP 26 ...
1.16.0
reprepro: 5.4.x
debsigs --
```

(The `bash -c "..."` form is needed because the Dockerfile sets ENTRYPOINT to build.sh; we're overriding to run arbitrary commands.)

- [ ] **Step 6: Commit**

```bash
git add docker/Dockerfile.debian-12 tests/unit/dockerfile_debian.bats
git commit -m "feat: Debian 12 build image with esl-erlang, rebar3, fpm"
```

---

## Task 7: Dockerfile.el9

**Goal:** Mirror Task 6 for Rocky Linux 9. Same toolchain, RPM-side equivalents.

**Files:**
- Create: `docker/Dockerfile.el9`
- Create: `tests/unit/dockerfile_el9.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/dockerfile_el9.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

@test "Dockerfile.el9 exists and uses rockylinux:9 base" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  [ -f "$f" ]
  grep -q "^FROM rockylinux:9" "$f"
}

@test "Dockerfile.el9 accepts OTP_VERSION and REBAR_VERSION build args" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  grep -q "^ARG OTP_VERSION=" "$f"
  grep -q "^ARG REBAR_VERSION=" "$f"
}

@test "Dockerfile.el9 installs createrepo_c, rpm-sign, esl-erlang, fpm" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  grep -q "createrepo_c" "$f"
  grep -q "rpm-sign" "$f"
  grep -q "esl-erlang" "$f"
  grep -q "fpm" "$f"
}

@test "Dockerfile.el9 sets WORKDIR /work and ENTRYPOINT to build.sh" {
  local f="$REPO_ROOT/docker/Dockerfile.el9"
  grep -q "^WORKDIR /work" "$f"
  grep -q 'ENTRYPOINT \["/work/scripts/build.sh"\]' "$f"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | grep -E "not ok" | head
```

- [ ] **Step 3: Write docker/Dockerfile.el9**

```dockerfile
# syntax=docker/dockerfile:1.6
# Build image for EL9 (Rocky 9 / Alma 9 / RHEL 9) packages.

FROM rockylinux:9

ARG OTP_VERSION=26.2.5
ARG REBAR_VERSION=3.23.0

# Toolchain: development tools, packaging utilities, Erlang/OTP from ESL.
RUN dnf -y install dnf-plugins-core \
 && dnf -y install epel-release \
 && dnf -y groupinstall "Development Tools" \
 && dnf -y install \
      ca-certificates curl git make \
      autoconf zip unzip libxslt \
      openssl-devel ncurses-devel \
      python3 ruby ruby-devel rubygems \
      createrepo_c rpm-sign \
 && dnf clean all

# Erlang Solutions yum repo. Bootstrap RPM:
RUN dnf -y install \
      https://packages.erlang-solutions.com/rpm/centos/9/erlang-solutions-2.0-1.noarch.rpm \
 && dnf -y install "esl-erlang-${OTP_VERSION}" \
 && dnf clean all

# rebar3
RUN curl -fsSL "https://github.com/erlang/rebar3/releases/download/${REBAR_VERSION}/rebar3" \
      -o /usr/local/bin/rebar3 \
 && chmod +x /usr/local/bin/rebar3 \
 && rebar3 --version

# FPM
RUN gem install --no-document fpm:1.16.0

WORKDIR /work
ENTRYPOINT ["/work/scripts/build.sh"]
```

- [ ] **Step 4: Run the bats tests (static)**

```bash
make test
```

Expected: 25 tests pass (21 prior + 4 new).

- [ ] **Step 5: Build the image and verify the toolchain**

```bash
make docker-build TARGET=el9
```

Then:

```bash
docker run --rm openkazoo-kazoo5-builder:el9 bash -c "
  erl -version 2>&1 &&
  rebar3 --version &&
  fpm --version &&
  createrepo_c --version 2>&1 &&
  rpmsign --help 2>&1 | head -1
"
```

Expected: similar to Task 6, with `createrepo_c` and `rpmsign` outputs.

- [ ] **Step 6: Commit**

```bash
git add docker/Dockerfile.el9 tests/unit/dockerfile_el9.bats
git commit -m "feat: EL9 (Rocky 9) build image with esl-erlang, rebar3, fpm"
```

---

## Task 8: scripts/build.sh — universal entrypoint

**Goal:** A single Bash script that, given `TARGET`, `KAZOO_VERSION`, `OTP_VERSION`, `PKG_REVISION` env vars, clones the upstream Kazoo source, compiles it, stages files, and produces a `.deb` or `.rpm` via FPM. Called by `make build` inside the appropriate Docker image.

**Files:**
- Create: `scripts/build.sh`
- Create: `tests/unit/build.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/build.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
  # We test build.sh via direct invocation, not inside Docker, for speed.
  # The script's environment-validation logic doesn't require Docker.
  export SCRIPT="$REPO_ROOT/scripts/build.sh"
}

@test "build.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "build.sh fails fast if TARGET is unset" {
  unset TARGET
  run "$SCRIPT"
  assert_status 2
  assert_output_contains "TARGET"
}

@test "build.sh fails fast if TARGET is invalid" {
  TARGET=ubuntu-99 KAZOO_VERSION=master OTP_VERSION=26.2.5 PKG_REVISION=1 \
    run "$SCRIPT"
  assert_status 2
  assert_output_contains "invalid"
}

@test "build.sh fails fast if KAZOO_VERSION is unset" {
  TARGET=debian-12 OTP_VERSION=26.2.5 PKG_REVISION=1 \
    run "$SCRIPT"
  assert_status 2
  assert_output_contains "KAZOO_VERSION"
}

@test "build.sh fails fast if OTP_VERSION is unset" {
  TARGET=debian-12 KAZOO_VERSION=master PKG_REVISION=1 \
    run "$SCRIPT"
  assert_status 2
  assert_output_contains "OTP_VERSION"
}

@test "build.sh fails fast if PKG_REVISION is unset" {
  TARGET=debian-12 KAZOO_VERSION=master OTP_VERSION=26.2.5 \
    run "$SCRIPT"
  assert_status 2
  assert_output_contains "PKG_REVISION"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | grep -E "not ok" | head
```

Expected: 6 new failures (file doesn't exist).

- [ ] **Step 3: Write scripts/build.sh**

```bash
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

echo ">> Running make compile + make tar-release"
make compile
make tar-release

# The output of tar-release lives at _rel/kazoo/kazoo-${VERSION}.tar.gz where
# VERSION is whatever the upstream Makefile uses. Find it.
RELEASE_TARBALL=$(find _rel/kazoo -maxdepth 2 -name "kazoo-*.tar.gz" | head -1)
[ -f "$RELEASE_TARBALL" ] || die "tar-release did not produce a kazoo-*.tar.gz"
echo ">> Release tarball: $RELEASE_TARBALL"

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
    fpm -s dir -t deb \
        --name kazoo \
        --version "$PKG_VERSION" \
        --iteration "${PKG_REVISION}~bookworm1" \
        --architecture amd64 \
        --depends "esl-erlang (>= 1:${OTP_MAJ_MIN})" \
        --depends "adduser" \
        --depends "systemd" \
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
    fpm -s dir -t rpm \
        --name kazoo \
        --version "$PKG_VERSION" \
        --iteration "${PKG_REVISION}.el9" \
        --architecture x86_64 \
        --depends "esl-erlang >= ${OTP_MAJ_MIN}" \
        --depends "shadow-utils" \
        --depends "systemd" \
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
```

- [ ] **Step 4: Make executable**

```bash
chmod +x scripts/build.sh
```

- [ ] **Step 5: Run the unit tests to verify they pass**

```bash
make test
```

Expected: 31 tests pass (25 prior + 6 new).

- [ ] **Step 6: Run a real Debian build end-to-end**

```bash
make build TARGET=debian-12
```

This will:
1. Confirm the docker image is built (cache hit from Task 6).
2. Run the container with build.sh.
3. Clone 2600hz/kazoo5 master inside the container.
4. Run `make compile && make tar-release` — **this takes 5-10 minutes** on first run.
5. Produce a `.deb` in `build/out/`.

Expected output ends with:

```
>> Done. Artifacts in: /work/build/out
-rw-r--r-- 1 root root <some-size> <date> kazoo_5.4.0~master.YYYYMMDD.<sha>-1~bookworm1_amd64.deb
```

If `make compile` fails: the error message from upstream Kazoo will be shown. Common causes are missing build deps in the Docker image (revisit Task 6) or breakages in upstream master (try pinning `config/kazoo.version` to a known-good commit SHA).

- [ ] **Step 7: Inspect the built .deb**

```bash
DEB=$(ls build/out/kazoo_*.deb | head -1)
dpkg-deb --info "$DEB"
dpkg-deb --contents "$DEB" | head -20
dpkg-deb --contents "$DEB" | grep -E "opt/kazoo/bin/kazoo$|lib/systemd/system/kazoo.service|usr/lib/sysusers.d/kazoo.conf|etc/default/kazoo$"
```

Expected:
- `dpkg-deb --info` shows Package, Version, Depends including `esl-erlang (>= 1:26.2)`.
- The three control files (kazoo binary, systemd unit, sysusers config) all appear in `--contents` output.

- [ ] **Step 8: Run an EL9 build end-to-end**

```bash
make build TARGET=el9
```

This produces a `.rpm` analogously.

- [ ] **Step 9: Inspect the built .rpm**

```bash
RPM=$(ls build/out/kazoo-*.rpm | head -1)
rpm -qpi "$RPM"
rpm -qpl "$RPM" | head -20
rpm -qpR "$RPM"  # requires
```

Expected: Version, Requires including `esl-erlang >= 26.2`, presence of `/opt/kazoo/bin/kazoo`.

- [ ] **Step 10: Commit**

```bash
git add scripts/build.sh tests/unit/build.bats
git commit -m "feat: build.sh — universal Kazoo deb/rpm builder entrypoint"
```

---

## Task 9: scripts/sign.sh — GPG sign packages

**Goal:** Sign the produced `.deb` (with `debsigs`) and `.rpm` (with `rpmsign`) using a GPG key supplied either as an env var (`GPG_PRIVATE_KEY`) or via a local keyring under `tests/fixtures/gpg/`.

**Files:**
- Create: `scripts/sign.sh`
- Create: `tests/unit/sign.bats`
- Create (gitignored): `tests/fixtures/gpg/` (local-only directory; never committed)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/sign.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
  export SCRIPT="$REPO_ROOT/scripts/sign.sh"
  export GNUPGHOME="$REPO_ROOT/tests/fixtures/gpg"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"

  # Generate a throwaway signing key if not already present
  if ! gpg --homedir "$GNUPGHOME" --list-secret-keys 2>/dev/null | grep -q "openkazoo-test"; then
    gpg --homedir "$GNUPGHOME" --batch --generate-key <<EOF 2>/dev/null
%no-protection
Key-Type: EDDSA
Key-Curve: ed25519
Subkey-Type: ECDH
Subkey-Curve: cv25519
Name-Real: openkazoo-test
Name-Email: openkazoo-test@example.invalid
Expire-Date: 0
%commit
EOF
  fi
}

@test "sign.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "sign.sh fails if no TARGET is given" {
  run "$SCRIPT"
  assert_status 2
  assert_output_contains "TARGET"
}

@test "sign.sh fails if TARGET is unknown" {
  run "$SCRIPT" ubuntu-99
  assert_status 2
}

@test "sign.sh fails gracefully if no package exists yet" {
  rm -rf "$REPO_ROOT/build/out/kazoo_*.deb"
  GNUPGHOME="$GNUPGHOME" run "$SCRIPT" debian-12
  # Acceptable to either find no .deb (status nonzero) OR succeed if a deb is present
  if [ ! -f "$REPO_ROOT/build/out/kazoo_*.deb" ] 2>/dev/null; then
    [ "$status" -ne 0 ]
  fi
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | grep -E "not ok" | head
```

- [ ] **Step 3: Write scripts/sign.sh**

```bash
#!/usr/bin/env bash
# sign.sh — sign built packages with GPG.
#
# Usage: sign.sh <target>
#   target: debian-12 | el9
#
# Key source priority:
#   1. $GPG_PRIVATE_KEY env var (ASCII-armored private key, CI mode)
#   2. tests/fixtures/gpg/ keyring (local-dev mode; throwaway key)
#
# Output: signs build/out/*.deb (debsigs) or build/out/*.rpm (rpmsign) in place.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 2; }

TARGET="${1:-}"
[ -n "$TARGET" ] || die "TARGET is required (debian-12 or el9)"
case "$TARGET" in
  debian-12|el9) ;;
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
  debian-12)
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
```

- [ ] **Step 4: Make executable**

```bash
chmod +x scripts/sign.sh
```

- [ ] **Step 5: Run unit tests**

```bash
make test
```

Expected: 35 tests pass (31 prior + 4 new).

- [ ] **Step 6: Locally sign the .deb produced in Task 8**

Note: `debsigs` may not be installed on your host (it's in the Docker image). Run it via Docker:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -v "$PWD/tests/fixtures/gpg:/root/.gnupg" \
  -e GNUPGHOME=/root/.gnupg \
  -w /work \
  --entrypoint /work/scripts/sign.sh \
  openkazoo-kazoo5-builder:debian-12 \
  debian-12
```

Expected: `>> debsigs sign: /work/build/out/kazoo_*.deb` and exits 0.

Verify the signature is present:

```bash
docker run --rm -v "$PWD:/work" openkazoo-kazoo5-builder:debian-12 \
  bash -c "ar t /work/build/out/kazoo_*.deb | grep -E '_gpgorigin$'"
```

Expected: `_gpgorigin` listed in the .deb archive.

- [ ] **Step 7: Locally sign the .rpm**

```bash
docker run --rm \
  -v "$PWD:/work" \
  -v "$PWD/tests/fixtures/gpg:/root/.gnupg" \
  -e GNUPGHOME=/root/.gnupg \
  -w /work \
  --entrypoint /work/scripts/sign.sh \
  openkazoo-kazoo5-builder:el9 \
  el9
```

Verify:

```bash
docker run --rm -v "$PWD:/work" openkazoo-kazoo5-builder:el9 \
  bash -c "rpm -K /work/build/out/kazoo-*.rpm 2>&1"
```

Expected output contains `digests signatures OK` or `pgp` indicators (not `NOT OK`).

- [ ] **Step 8: Commit**

```bash
git add scripts/sign.sh tests/unit/sign.bats
git commit -m "feat: sign.sh — GPG sign .deb and .rpm artifacts"
```

(Note: `tests/fixtures/gpg/` is gitignored from Task 1, so the throwaway key is not committed.)

---

## Task 10: scripts/publish.sh — assemble apt + yum repos

**Goal:** Generate signed apt (`reprepro`) and yum (`createrepo_c`) metadata under `build/repo/` so that `build/repo/` can be deployed as-is to the `gh-pages` branch.

**Files:**
- Create: `scripts/publish.sh`
- Create: `tests/unit/publish.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/publish.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
  export SCRIPT="$REPO_ROOT/scripts/publish.sh"
  export GNUPGHOME="$REPO_ROOT/tests/fixtures/gpg"
}

@test "publish.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "publish.sh fails if build/out is empty" {
  local empty="$REPO_ROOT/build/out-empty-test"
  rm -rf "$empty"
  mkdir -p "$empty"
  OUT_DIR_OVERRIDE="$empty" GNUPGHOME="$GNUPGHOME" run "$SCRIPT"
  assert_status 2
  rmdir "$empty"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | grep -E "not ok" | head
```

- [ ] **Step 3: Write scripts/publish.sh**

```bash
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
```

- [ ] **Step 4: Make executable**

```bash
chmod +x scripts/publish.sh
```

- [ ] **Step 5: Run unit tests**

```bash
make test
```

Expected: 37 tests pass.

- [ ] **Step 6: Run publish locally**

```bash
docker run --rm \
  -v "$PWD:/work" \
  -v "$PWD/tests/fixtures/gpg:/root/.gnupg" \
  -e GNUPGHOME=/root/.gnupg \
  -w /work \
  --entrypoint /work/scripts/publish.sh \
  openkazoo-kazoo5-builder:debian-12
```

Note: we use the debian-12 image because it has both `reprepro` and `createrepo_c` is unavailable — wait. `createrepo_c` is in the el9 image, not debian-12. We need to bundle both into one image OR run two passes.

**Fix:** add `createrepo_c` to the debian-12 image so publish.sh can run there for both repo types. It's available in `apt-get install -y createrepo-c` on Debian 12.

Modify `docker/Dockerfile.debian-12` — add `createrepo-c` to the first apt-get install:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git make build-essential \
      autoconf zip unzip xsltproc libxslt1-dev \
      libssl-dev libncurses-dev \
      python3 ruby ruby-dev rubygems \
      reprepro debsigs createrepo-c \
 && rm -rf /var/lib/apt/lists/*
```

(One line change: added `createrepo-c` at the end.)

Rebuild:

```bash
make docker-build TARGET=debian-12
```

Then re-run the publish command above. Expected:

```
>> Exported public key to /work/build/repo/pubkey.asc
>> Building apt repo for 1 .deb file(s)
>> reprepro includedeb bookworm: ...
>> Building yum repo for 1 .rpm file(s)
>> Done. Repo published under: /work/build/repo
```

- [ ] **Step 7: Inspect the published repo structure**

```bash
find build/repo -type f | sort
```

Expected (paths are illustrative):

```
build/repo/README.md
build/repo/debian/conf/distributions
build/repo/debian/db/checksums.db
build/repo/debian/db/contents.cache.db
build/repo/debian/db/packages.db
build/repo/debian/db/release.caches.db
build/repo/debian/db/version
build/repo/debian/dists/bookworm/Release
build/repo/debian/dists/bookworm/Release.gpg
build/repo/debian/dists/bookworm/InRelease
build/repo/debian/dists/bookworm/main/binary-amd64/Packages
build/repo/debian/dists/bookworm/main/binary-amd64/Packages.gz
build/repo/debian/dists/bookworm/main/binary-amd64/Release
build/repo/debian/pool/main/k/kazoo/kazoo_<ver>_amd64.deb
build/repo/el/9/Packages/kazoo-<ver>.el9.x86_64.rpm
build/repo/el/9/openkazoo.repo
build/repo/el/9/repodata/repomd.xml
build/repo/el/9/repodata/repomd.xml.asc
build/repo/el/9/repodata/<hash>-primary.xml.gz
build/repo/el/9/repodata/<hash>-filelists.xml.gz
build/repo/el/9/repodata/<hash>-other.xml.gz
build/repo/pubkey.asc
```

- [ ] **Step 8: Commit (Dockerfile change is bundled with publish.sh)**

```bash
git add scripts/publish.sh tests/unit/publish.bats docker/Dockerfile.debian-12
git commit -m "feat: publish.sh — assemble signed apt + yum repos"
```

---

## Task 11: scripts/verify.sh — smoke-test built packages

**Goal:** Quick sanity checks on built artifacts before publishing — metadata, file presence, signature validity.

**Files:**
- Create: `scripts/verify.sh`
- Create: `tests/unit/verify.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/verify.bats`:

```bash
#!/usr/bin/env bats

load '../test_helper/common.bash'

setup() {
  export SCRIPT="$REPO_ROOT/scripts/verify.sh"
}

@test "verify.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "verify.sh fails fast on unknown target" {
  run "$SCRIPT" not-a-target
  assert_status 2
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
make test 2>&1 | grep -E "not ok" | head
```

- [ ] **Step 3: Write scripts/verify.sh**

```bash
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
```

- [ ] **Step 4: Make executable**

```bash
chmod +x scripts/verify.sh
```

- [ ] **Step 5: Run unit tests**

```bash
make test
```

Expected: 39 tests pass.

- [ ] **Step 6: Run verify on the built artifacts**

```bash
make verify TARGET=debian-12
make verify TARGET=el9
```

Expected: both end with `>> Verify passed.` (verify.sh has to run on host — it uses `dpkg-deb` and `rpm` which may or may not be on macOS. If not, fall back to Docker:

```bash
docker run --rm -v "$PWD:/work" -w /work \
  --entrypoint /work/scripts/verify.sh \
  openkazoo-kazoo5-builder:debian-12 \
  debian-12

docker run --rm -v "$PWD:/work" -w /work \
  --entrypoint /work/scripts/verify.sh \
  openkazoo-kazoo5-builder:el9 \
  el9
```

If running on macOS without `dpkg-deb`/`rpm` locally, update the `verify` Make target to run in Docker. For simplicity in this MVP, document that `make verify` requires a Linux host or Docker fallback.)

- [ ] **Step 7: Commit**

```bash
git add scripts/verify.sh tests/unit/verify.bats
git commit -m "feat: verify.sh — smoke-test built packages"
```

---

## Task 12: GitHub Actions build workflow

**Goal:** Tag-driven CI workflow that builds the matrix, signs, publishes to gh-pages, and attaches artifacts to the GitHub Release.

**Files:**
- Create: `.github/workflows/build.yml`

- [ ] **Step 1: Bootstrap the gh-pages branch**

Before the workflow can push to gh-pages, the branch must exist with an empty initial commit:

```bash
git checkout --orphan gh-pages
git rm -rf . 2>/dev/null
cat > README.md <<'EOF'
# openkazoo-kazoo5-builder — package repository

This branch is auto-managed by CI. Do not commit to it manually.

See the [main branch](https://github.com/cloudpbx/openkazoo-kazoo5-builder)
for the source.
EOF
git add README.md
git commit -m "chore: bootstrap gh-pages branch"
git push origin gh-pages
git checkout main
```

After this push, enable GitHub Pages serving from the `gh-pages` branch root in the repo settings (Settings → Pages → Source: `gh-pages` branch, `/` folder). The Pages URL will be `https://cloudpbx.github.io/openkazoo-kazoo5-builder/`.

- [ ] **Step 2: Generate a production GPG key and set repo secrets**

Run **on your local machine** (NOT in the repo):

```bash
gpg --batch --generate-key <<EOF
%no-protection
Key-Type: EDDSA
Key-Curve: ed25519
Subkey-Type: ECDH
Subkey-Curve: cv25519
Name-Real: openkazoo-kazoo5 signing key
Name-Email: openkazoo-bot@cloudpbx.example
Expire-Date: 2y
%commit
EOF

# Export the private key (armored)
gpg --armor --export-secret-keys openkazoo-bot@cloudpbx.example \
  > /tmp/openkazoo-gpg-private.asc

# Export the public key (will be published)
gpg --armor --export openkazoo-bot@cloudpbx.example \
  > /tmp/openkazoo-gpg-public.asc
```

Then add the secrets to the GitHub repo. From the repo root:

```bash
TOKEN=$(/opt/homebrew/bin/gh auth token)

# Upload GPG_PRIVATE_KEY
curl -sS -X PUT \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/secrets/public-key \
  | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['key_id']); print(d['key'])"
```

(Encrypting the secret value with the repo's public key requires `pynacl`. If `gh` isn't usable due to the TLS issue, the easiest workaround is to set secrets via the GitHub web UI: Settings → Secrets and variables → Actions → New repository secret. Add `GPG_PRIVATE_KEY` (paste contents of `/tmp/openkazoo-gpg-private.asc`) and optionally `GPG_PASSPHRASE` if the key was passphrase-protected.)

**Delete the private key files** from `/tmp/` after upload:

```bash
shred -u /tmp/openkazoo-gpg-private.asc 2>/dev/null \
  || rm -f /tmp/openkazoo-gpg-private.asc
```

- [ ] **Step 3: Write the GHA workflow**

Create `.github/workflows/build.yml`:

```yaml
name: build-and-publish

on:
  push:
    tags:
      - 'v5.*'
  workflow_dispatch:
    inputs:
      kazoo_version:
        description: 'Override config/kazoo.version for this run (e.g. master, 5.4.0)'
        required: false
        default: ''
      publish:
        description: 'If true, publish to gh-pages (workflow_dispatch only)'
        type: boolean
        default: false

permissions:
  contents: write   # needed to push gh-pages and create releases

jobs:
  build:
    name: build (${{ matrix.target }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        target: [debian-12, el9]
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true

      - name: Apply kazoo_version override
        if: ${{ inputs.kazoo_version != '' }}
        run: echo "${{ inputs.kazoo_version }}" > config/kazoo.version

      - name: Build package
        run: make build TARGET=${{ matrix.target }}

      - name: Sign package
        env:
          GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
          GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}
        run: |
          # sign.sh runs on the host (not in the build container) — pass key through env
          docker run --rm \
            -v "$PWD:/work" -w /work \
            -e GPG_PRIVATE_KEY -e GPG_PASSPHRASE \
            --entrypoint /work/scripts/sign.sh \
            openkazoo-kazoo5-builder:${{ matrix.target }} \
            ${{ matrix.target }}

      - name: Verify package
        run: |
          docker run --rm -v "$PWD:/work" -w /work \
            --entrypoint /work/scripts/verify.sh \
            openkazoo-kazoo5-builder:${{ matrix.target }} \
            ${{ matrix.target }}

      - uses: actions/upload-artifact@v4
        with:
          name: package-${{ matrix.target }}
          path: build/out/*
          if-no-files-found: error

  publish:
    name: publish to gh-pages + release
    needs: build
    if: |
      startsWith(github.ref, 'refs/tags/v') ||
      (github.event_name == 'workflow_dispatch' && inputs.publish)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: build/out-staging

      - name: Flatten artifacts into build/out
        run: |
          mkdir -p build/out
          find build/out-staging -type f \( -name "*.deb" -o -name "*.rpm" \) \
            -exec cp -v {} build/out/ \;
          ls -la build/out

      - name: Build debian-12 image (publish.sh runs in it)
        run: make docker-build TARGET=debian-12

      - name: Assemble apt + yum repos
        env:
          GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
          GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}
        run: |
          docker run --rm \
            -v "$PWD:/work" -w /work \
            -e GPG_PRIVATE_KEY -e GPG_PASSPHRASE \
            --entrypoint /work/scripts/publish.sh \
            openkazoo-kazoo5-builder:debian-12

      - name: Checkout gh-pages
        uses: actions/checkout@v4
        with:
          ref: gh-pages
          path: gh-pages

      - name: Sync build/repo into gh-pages
        run: |
          rsync -av --delete \
            --exclude='.git' \
            --exclude='README.md' \
            build/repo/ gh-pages/

      - name: Commit + push gh-pages
        working-directory: gh-pages
        run: |
          git config user.name "openkazoo-bot"
          git config user.email "openkazoo-bot@users.noreply.github.com"
          git add -A
          if git diff --cached --quiet; then
            echo "No changes to publish."
          else
            git commit -m "publish: ${{ github.ref_name }}"
            git push origin gh-pages
          fi

      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: build/out/*
          body: |
            Automated build for `${{ github.ref_name }}`.

            Install instructions: see [docs/INSTALL.md](https://github.com/cloudpbx/openkazoo-kazoo5-builder/blob/main/docs/INSTALL.md).
```

- [ ] **Step 4: Test the workflow with workflow_dispatch (no tag yet)**

```bash
git add .github/workflows/build.yml
git commit -m "ci: build + publish workflow (matrix + sign + gh-pages)"
git push origin main
```

Then trigger a manual run:

```bash
TOKEN=$(/opt/homebrew/bin/gh auth token) && \
curl -sS -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/workflows/build.yml/dispatches \
  -d '{"ref":"main","inputs":{"kazoo_version":"master","publish":"false"}}'
```

Monitor the run at `https://github.com/cloudpbx/openkazoo-kazoo5-builder/actions`.

Expected: both matrix jobs (`build (debian-12)` and `build (el9)`) succeed. `publish` is skipped because `inputs.publish` is `false`.

If a job fails:
- **Image build fails (apt/dnf errors)**: usually a transient mirror issue. Re-run.
- **kazoo5 clone fails**: confirm the ref in `config/kazoo.version` exists upstream.
- **`make compile` fails**: likely an upstream change. Pin `config/kazoo.version` to a specific commit SHA in a separate PR.
- **`sign` step fails with "no key source"**: `GPG_PRIVATE_KEY` secret is not set or wrong.

- [ ] **Step 5: Verify artifacts are uploaded**

Once the matrix succeeds, download artifacts:

```bash
TOKEN=$(/opt/homebrew/bin/gh auth token) && \
curl -sS \
  -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/runs \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['workflow_runs'][0]['id'])"
```

Or use the web UI to download `package-debian-12` and `package-el9` artifacts and confirm they contain `.deb`/`.rpm` files.

- [ ] **Step 6: Commit (already done in Step 4; nothing further)**

If the workflow needed iteration to get green (image fixes, missing deps, etc.), each iteration is a separate commit on `main`.

---

## Task 13: GitHub Actions verify-install workflow

**Goal:** Post-publish E2E test that spins up clean Debian/Rocky containers and follows `docs/INSTALL.md` verbatim to install kazoo from the published apt/yum repo.

**Files:**
- Create: `.github/workflows/verify-install.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/verify-install.yml`:

```yaml
name: verify-install

on:
  workflow_run:
    workflows: [build-and-publish]
    types: [completed]
    branches: [main]
  workflow_dispatch:
  schedule:
    - cron: '17 4 * * 1'   # Mondays at 04:17 UTC

permissions:
  contents: read

jobs:
  install-debian-12:
    if: ${{ github.event.workflow_run.conclusion == 'success' || github.event_name != 'workflow_run' }}
    runs-on: ubuntu-latest
    steps:
      - name: Install from published apt repo
        run: |
          docker run --rm debian:12-slim bash -e -c '
            set -euxo pipefail
            apt-get update
            apt-get install -y --no-install-recommends ca-certificates curl gnupg

            # Erlang Solutions repo
            curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc \
              -o /usr/share/keyrings/erlang-solutions.asc
            echo "deb [signed-by=/usr/share/keyrings/erlang-solutions.asc] \
              https://packages.erlang-solutions.com/debian bookworm contrib" \
              > /etc/apt/sources.list.d/erlang-solutions.list

            # openkazoo repo
            curl -fsSL https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc \
              -o /usr/share/keyrings/openkazoo.asc
            echo "deb [signed-by=/usr/share/keyrings/openkazoo.asc] \
              https://cloudpbx.github.io/openkazoo-kazoo5-builder/debian bookworm main" \
              > /etc/apt/sources.list.d/openkazoo.list

            apt-get update
            apt-get install -y --no-install-recommends kazoo

            # Asserts
            test -x /opt/kazoo/bin/kazoo
            test -f /lib/systemd/system/kazoo.service
            test -f /etc/default/kazoo
            id kazoo >/dev/null
            echo "OK: kazoo installs cleanly on Debian 12"
          '

  install-rocky-9:
    if: ${{ github.event.workflow_run.conclusion == 'success' || github.event_name != 'workflow_run' }}
    runs-on: ubuntu-latest
    steps:
      - name: Install from published yum repo
        run: |
          docker run --rm rockylinux:9 bash -e -c '
            set -euxo pipefail
            dnf install -y curl

            # Erlang Solutions repo
            dnf install -y https://packages.erlang-solutions.com/rpm/centos/9/erlang-solutions-2.0-1.noarch.rpm

            # openkazoo repo
            curl -fsSL https://cloudpbx.github.io/openkazoo-kazoo5-builder/el/9/openkazoo.repo \
              -o /etc/yum.repos.d/openkazoo.repo
            rpm --import https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc

            dnf install -y kazoo

            # Asserts
            test -x /opt/kazoo/bin/kazoo
            test -f /lib/systemd/system/kazoo.service || test -f /usr/lib/systemd/system/kazoo.service
            test -f /etc/default/kazoo
            id kazoo >/dev/null
            echo "OK: kazoo installs cleanly on Rocky 9"
          '
```

- [ ] **Step 2: Commit and push**

```bash
git add .github/workflows/verify-install.yml
git commit -m "ci: verify-install workflow — E2E install from published repo"
git push origin main
```

- [ ] **Step 3: Manually trigger verify-install (once a publish has happened)**

```bash
TOKEN=$(/opt/homebrew/bin/gh auth token) && \
curl -sS -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/workflows/verify-install.yml/dispatches \
  -d '{"ref":"main"}'
```

This only succeeds if Task 14 has already published artifacts to gh-pages. If not, expect failures like `404 Not Found` on the `pubkey.asc` URL — that's OK at this stage; the workflow will be exercised properly after Task 14.

---

## Task 14: End-user docs

**Goal:** `docs/INSTALL.md` (consumed by users), `docs/ARCHITECTURE.md` (consumed by contributors), `docs/CONTRIBUTING.md` (consumed by maintainers).

**Files:**
- Create: `docs/INSTALL.md`
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/CONTRIBUTING.md`

- [ ] **Step 1: Write docs/INSTALL.md**

```markdown
# Installing Kazoo from openkazoo packages

These instructions install the [Kazoo](https://github.com/2600hz/kazoo5) telephony platform
on Debian 12 (bookworm) or Rocky Linux 9 / AlmaLinux 9 / RHEL 9 from the community
[openkazoo-kazoo5-builder](https://github.com/cloudpbx/openkazoo-kazoo5-builder) repository.

**Important:** the `kazoo` package installs only the Erlang application. You must separately
install and configure:
- **CouchDB** (use distro packages or upstream apache.org packages)
- **RabbitMQ** (use distro packages)
- **FreeSWITCH** and **Kamailio** (community 2600Hz forks not yet packaged here; see issue tracker)

## Debian 12 (bookworm)

```bash
# 1. Add Erlang Solutions repo (runtime dependency)
curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc \
  | sudo tee /usr/share/keyrings/erlang-solutions.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/erlang-solutions.asc] \
https://packages.erlang-solutions.com/debian bookworm contrib" \
  | sudo tee /etc/apt/sources.list.d/erlang-solutions.list

# 2. Add the openkazoo repo
curl -fsSL https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc \
  | sudo tee /usr/share/keyrings/openkazoo.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/openkazoo.asc] \
https://cloudpbx.github.io/openkazoo-kazoo5-builder/debian bookworm main" \
  | sudo tee /etc/apt/sources.list.d/openkazoo.list

# 3. Install
sudo apt-get update
sudo apt-get install -y kazoo
```

## Rocky Linux 9 / AlmaLinux 9 / RHEL 9

```bash
# 1. Erlang Solutions repo
sudo dnf install -y https://packages.erlang-solutions.com/rpm/centos/9/erlang-solutions-2.0-1.noarch.rpm

# 2. openkazoo repo
sudo dnf config-manager --add-repo \
  https://cloudpbx.github.io/openkazoo-kazoo5-builder/el/9/openkazoo.repo
sudo rpm --import https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc

# 3. Install
sudo dnf install -y kazoo
```

## Post-install configuration

Edit `/etc/default/kazoo` to set at minimum:
- `COOKIE` — a strong shared secret across cluster members. **Required.**
- `NODE_NAME` — defaults to `kazoo_apps@127.0.0.1`; change for multi-node deployments.

Then start the service:

```bash
sudo systemctl enable --now kazoo
sudo systemctl status kazoo
```

Kazoo will fail to start until CouchDB and RabbitMQ are reachable. See the upstream
[2600hz/kazoo5 installation guide](https://github.com/2600hz/kazoo5/tree/master/doc)
for cluster setup.

## Verifying the install

```bash
dpkg -V kazoo        # Debian
rpm -V kazoo         # RPM
```

## Reporting bugs

Open an issue at https://github.com/cloudpbx/openkazoo-kazoo5-builder/issues.
```

- [ ] **Step 2: Write docs/ARCHITECTURE.md**

```markdown
# Architecture

This repo builds Debian and RPM packages of the [Kazoo](https://github.com/2600hz/kazoo5)
telephony platform. The full design document lives at
[docs/superpowers/specs/2026-05-12-kazoo5-debian-rpm-builder-design.md](superpowers/specs/2026-05-12-kazoo5-debian-rpm-builder-design.md).

## How a build works (one diagram)

```
1. CI checkout of this repo                  ─┐
2. `make build TARGET=debian-12`              │  per matrix entry
   ├─ docker build docker/Dockerfile.debian-12│  (parallel for el9)
   └─ docker run scripts/build.sh             │
        ├─ git clone 2600hz/kazoo5 @ <pin>    │
        ├─ make compile && make tar-release  │
        ├─ stage files into FHS layout       │
        └─ fpm -s dir -t deb (or -t rpm)     │
3. `make sign TARGET=...`                    ─┘  (GPG-signs the artifact)

After matrix completes:
4. `make publish` (in debian-12 image)
   ├─ reprepro includedeb           → build/repo/debian/
   ├─ createrepo_c + signed repomd  → build/repo/el/9/
   └─ exports pubkey.asc            → build/repo/pubkey.asc
5. rsync build/repo/ → gh-pages branch
6. push gh-pages
```

## Why FPM and not native debhelper / RPM spec?

FPM trades formal correctness for speed-of-iteration. The MVP scope (single component,
two distros, community-driven) doesn't justify the upfront cost of full debhelper +
spec-file packaging. If/when the scope expands (FreeSWITCH, Kamailio, Monster UI, Debian
official upload, etc.), migration to native packaging is the documented Phase 2 path.

## Why GitHub Pages as the apt/yum host?

Zero managed infrastructure. The `gh-pages` branch holds both `debian/` (reprepro layout)
and `el/9/` (createrepo_c layout) trees under different subpaths — clients see them via
different `deb`/`baseurl` URLs.

## Adding a new target distro

1. Create `docker/Dockerfile.<target>` (copy from an existing one).
2. Add the target to `VALID_TARGETS` in the `Makefile`.
3. Extend `scripts/build.sh`'s `case` for the FPM invocation.
4. Update `.github/workflows/build.yml` matrix.
5. Update `scripts/publish.sh` to put the artifact in the correct repo subpath.
6. Update `docs/INSTALL.md` with install instructions.
7. Add tests in `tests/unit/dockerfile_<target>.bats`.

## Adding a new component (e.g. FreeSWITCH)

Out of MVP scope. The pattern would be:
1. Add `config/freeswitch.version` and corresponding pins.
2. Add `packaging/common/freeswitch-kazoo.service` etc.
3. Extend `scripts/build.sh` with a `COMPONENT=freeswitch` axis.
4. Add a Makefile target `make build COMPONENT=freeswitch TARGET=...`.
5. Add a separate `.github/workflows/build-freeswitch.yml` or expand the matrix.
```

- [ ] **Step 3: Write docs/CONTRIBUTING.md**

```markdown
# Contributing

## Bumping the Kazoo version

When upstream `2600hz/kazoo5` publishes a new tag or you want to track a newer commit:

```bash
echo "5.4.0" > config/kazoo.version        # or "master", or a 40-char SHA
git commit -am "feat: bump kazoo to 5.4.0"
```

Merging this PR does **not** trigger a release build. To release:

```bash
git tag v5.4.0-1
git push origin v5.4.0-1
```

The tag pattern is `v{KAZOO_VERSION}-{PKG_REVISION}`. Bumping `config/package.revision`
without changing `config/kazoo.version` is how you release a packaging-only fix.

## Bumping Erlang/OTP

```bash
echo "26.2.6" > config/otp.version
```

Make sure the version exists in Erlang Solutions' apt and yum repos for both Debian 12
and EL9 before merging. Check:
- https://packages.erlang-solutions.com/debian/dists/bookworm/contrib/binary-amd64/
- https://packages.erlang-solutions.com/rpm/centos/9/x86_64/

## Running tests

```bash
make test                                  # bats unit tests
make build TARGET=debian-12                # full build (Docker required)
make verify TARGET=debian-12               # smoke-test the build
```

## Coding conventions

- Bash scripts: `set -euo pipefail`, shellcheck-clean.
- Dockerfiles: pin all version-sensitive ARGs at the top.
- Commit messages: `<type>: <subject>`, where type is one of `feat`, `chore`, `docs`,
  `test`, `fix`, `ci`, `refactor`.
- Atomic commits — one logical change per commit.

## Adding a new distro target

See [ARCHITECTURE.md § Adding a new target distro](ARCHITECTURE.md#adding-a-new-target-distro).

## Releasing a new version

1. Verify CI is green on `main`.
2. (If kazoo source moved) bump `config/kazoo.version` and merge.
3. (If packaging changed) bump `config/package.revision` and merge.
4. Tag: `git tag v<kazoo>-<rev>` (e.g. `v5.4.0-1`), then `git push origin v<tag>`.
5. Watch the `build-and-publish` workflow.
6. After publish, `verify-install` will run automatically; confirm it's green.
7. Edit the GitHub Release with any release notes.
```

- [ ] **Step 4: Verify the docs render correctly**

```bash
ls docs/
```

Expected:
```
ARCHITECTURE.md
CONTRIBUTING.md
INSTALL.md
superpowers/
```

- [ ] **Step 5: Commit**

```bash
git add docs/INSTALL.md docs/ARCHITECTURE.md docs/CONTRIBUTING.md
git commit -m "docs: end-user INSTALL, ARCHITECTURE, CONTRIBUTING"
```

---

## Task 15: First dry-run release

**Goal:** Manually trigger the workflow with `publish=true` to produce the first published artifacts on `gh-pages`. Then tag `v5.4.0-1` (or equivalent for whatever upstream ref is current) for the first formal release.

- [ ] **Step 1: Push current state to GitHub**

```bash
git push origin main
```

Confirm all commits from Tasks 1-14 land on `main`.

- [ ] **Step 2: Trigger workflow_dispatch with publish=true**

```bash
TOKEN=$(/opt/homebrew/bin/gh auth token) && \
curl -sS -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/workflows/build.yml/dispatches \
  -d '{"ref":"main","inputs":{"kazoo_version":"master","publish":"true"}}'
```

- [ ] **Step 3: Monitor the run**

```bash
TOKEN=$(/opt/homebrew/bin/gh auth token) && \
curl -sS \
  -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/runs?per_page=1 \
  | python3 -c "import sys,json; r=json.load(sys.stdin); w=r['workflow_runs'][0]; print(w['html_url'], w['status'], w['conclusion'])"
```

Wait until conclusion is `success`. If `failure`, inspect logs at the URL printed.

- [ ] **Step 4: Confirm gh-pages was updated**

```bash
TOKEN=$(/opt/homebrew/bin/gh auth token) && \
curl -sS \
  -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/branches/gh-pages \
  | python3 -c "import sys,json; b=json.load(sys.stdin); print(b['commit']['sha'][:8], b['commit']['commit']['message'][:80])"
```

Expected: a fresh commit from `openkazoo-bot` with message `publish: main`.

- [ ] **Step 5: Confirm pages site serves the repo**

```bash
curl -sI https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc | head -3
curl -sI https://cloudpbx.github.io/openkazoo-kazoo5-builder/debian/dists/bookworm/Release | head -3
curl -sI https://cloudpbx.github.io/openkazoo-kazoo5-builder/el/9/repodata/repomd.xml | head -3
```

Each should return `HTTP/2 200`. Pages deployment can take 1-3 minutes after the gh-pages push.

- [ ] **Step 6: Trigger verify-install manually**

```bash
TOKEN=$(/opt/homebrew/bin/gh auth token) && \
curl -sS -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/workflows/verify-install.yml/dispatches \
  -d '{"ref":"main"}'
```

Watch both `install-debian-12` and `install-rocky-9` jobs go green. If either fails, the
likely causes are:
- GPG key not yet trusted by the install machine (re-import).
- Pages not yet propagated globally (wait 5 min).
- Missing dependency declared on the package (revisit FPM `--depends` flags).

- [ ] **Step 7: Tag the first release**

Pick a tag name that reflects the upstream ref you just built. If `config/kazoo.version`
is still `master`:

```bash
TODAY=$(date -u +%Y%m%d)
git tag -a "v5.4.0-master-${TODAY}-1" -m "First MVP release built from kazoo5 master"
git push origin "v5.4.0-master-${TODAY}-1"
```

If upstream has published a real `5.4.0` tag and you've bumped `config/kazoo.version` accordingly:

```bash
git tag -a v5.4.0-1 -m "Kazoo 5.4.0 — first release"
git push origin v5.4.0-1
```

This re-runs the workflow under the tag, which triggers the `softprops/action-gh-release` step
in `publish` and creates a GitHub Release with the artifacts attached.

- [ ] **Step 8: Final sanity — try installing from a fresh Debian 12 VM/container locally**

```bash
docker run --rm -it debian:12-slim bash -c "
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg

  curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc \
    | tee /usr/share/keyrings/erlang-solutions.asc > /dev/null
  echo 'deb [signed-by=/usr/share/keyrings/erlang-solutions.asc] \
    https://packages.erlang-solutions.com/debian bookworm contrib' \
    > /etc/apt/sources.list.d/erlang-solutions.list

  curl -fsSL https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc \
    | tee /usr/share/keyrings/openkazoo.asc > /dev/null
  echo 'deb [signed-by=/usr/share/keyrings/openkazoo.asc] \
    https://cloudpbx.github.io/openkazoo-kazoo5-builder/debian bookworm main' \
    > /etc/apt/sources.list.d/openkazoo.list

  apt-get update
  apt-cache policy kazoo
  apt-get install -y kazoo
  ls -la /opt/kazoo/bin/
"
```

Expected: ends with `/opt/kazoo/bin/kazoo` listed.

This is the **MVP complete** moment. From here, the Phase 2 backlog in the design spec
(§10) lists what to add next.

---

## Self-review notes

After writing this plan, applied checklist from writing-plans skill:

**1. Spec coverage:**
- §1 Background → covered in plan header (background sentence)
- §2 Scope → reflected in MVP boundary (Task scope summary)
- §3 Architecture → Task 8 (build.sh) + Task 10 (publish.sh) + Task 12 (build.yml)
- §4 Repository layout → Task 1 (skeleton) + each subsequent file-creating task
- §5 Build flow / Dockerfiles → Tasks 6, 7, 8
- §6 Testing & verification → bats throughout + Task 11 (verify.sh) + Task 13 (verify-install)
- §7 Versioning & release model → Task 1 (pins) + Task 14 (CONTRIBUTING.md) + Task 15 (tagging)
- §8 End-user install → Task 14 (INSTALL.md)
- §9 Risks/open questions → preflight check in plan header (no 5.4 tag); ref handling in Task 8
- §10 Phase 2 backlog → not implemented; referenced in Task 14 docs
- §11 Implementation summary → essentially this plan

**2. Placeholder scan:** none — every step contains executable content.

**3. Type consistency:** the four env vars (TARGET, KAZOO_VERSION, OTP_VERSION, PKG_REVISION) are referenced identically across Makefile, scripts/build.sh, sign.sh, publish.sh, verify.sh, and GHA. The `VALID_TARGETS = debian-12 el9` set is consistent throughout.

**One known fragility:** Task 12's "set GitHub Actions secret via gh CLI" workflow may hit the same Go-TLS bug we encountered in the brainstorming session; the fallback is the web UI, documented inline.

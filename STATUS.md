# Project Status

**Last updated:** 2026-05-16
**Status:** ✅ **MVP shipped.** First release published: `v5.4.0-master-20260516-1`.

---

## What works

A complete CI-driven build pipeline that produces signed `.deb` (Debian 12) and `.rpm` (EL9) packages of Kazoo v5 (currently from `2600hz/kazoo5@master`) and publishes them to a community-maintained apt + yum repository.

End users can install:

```bash
# Debian 12 (bookworm)
curl -fsSL https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc \
  | sudo tee /usr/share/keyrings/openkazoo.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/openkazoo.asc] \
https://cloudpbx.github.io/openkazoo-kazoo5-builder/debian bookworm main" \
  | sudo tee /etc/apt/sources.list.d/openkazoo.list
sudo apt-get update && sudo apt-get install -y kazoo

# Rocky 9 / Alma 9 / RHEL 9
sudo dnf config-manager --add-repo \
  https://cloudpbx.github.io/openkazoo-kazoo5-builder/el/9/openkazoo.repo
sudo rpm --import https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc
sudo dnf install -y kazoo
```

Both install paths are validated in CI by `.github/workflows/verify-install.yml`.

---

## What's published

| Artifact | URL |
|---|---|
| GitHub Release | https://github.com/cloudpbx/openkazoo-kazoo5-builder/releases/tag/v5.4.0-master-20260516-1 |
| apt repo | https://cloudpbx.github.io/openkazoo-kazoo5-builder/debian/ |
| yum repo | https://cloudpbx.github.io/openkazoo-kazoo5-builder/el/9/ |
| GPG public key | https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc |

**Release assets:**
- `kazoo_5.4.0.master.20260516.3d0b5e63-1.bookworm1_amd64.deb` — 92.9 MB (Debian 12)
- `kazoo-5.4.0.master.20260516.3d0b5e63-1.el9.el9.x86_64.rpm` — 92.3 MB (EL9)

Both packages bundle OTP 26.2.5 (compiled from source via the canonical `./configure && make` flow inside the build images) so end users don't need a separate Erlang installation.

---

## How to cut the next release

The pipeline is set up so that releasing is **one command**:

```bash
git tag v5.4.0-master-$(date -u +%Y%m%d)-1
git push origin v5.4.0-master-$(date -u +%Y%m%d)-1
```

That tag push triggers `.github/workflows/build.yml` which:
1. Builds both matrix legs (~12 min with cached OTP layers, ~30 min cold)
2. Signs the artifacts with `GPG_PRIVATE_KEY` (already configured as a repo secret)
3. Updates the apt + yum repos on `gh-pages`
4. Creates a GitHub Release with the `.deb` + `.rpm` attached

To bump the upstream Kazoo version, edit `config/kazoo.version` first (currently `master`, future: e.g. `5.4.0` once upstream tags).

---

## How this got here: the dry-run journey

It took 11 dry-run iterations from "infrastructure stood up" to "tagged release shipped". Each surfaced a real environmental or upstream issue:

```
Run 1   ❌  EL9 curl-minimal package conflict + transient ESL 502 on apt key
              Fix: drop curl from EL9 dnf list; add curl --retry-all-errors
Run 2   ❌  packages.erlang-solutions.com persistent 502 (ESL retired the host)
              Fix: pivot to building OTP from source (initially via kerl, then direct)
Runs 3-5 ❌ kerl exiting silently with no output
              Fix: skip kerl entirely; use plain ./configure && make from
                   upstream otp_src tarball
Run 6   ❌  wget missing in build images (kazoo_numbers Makefile fetches dialcodes.json)
              Fix: add wget to both Dockerfiles
Runs 7-8 ❌ SSH needed for kazoo5 app fetch (default git@github.com URLs)
              Fix: export FETCH_AS=https://github.com/ in scripts/build.sh
Run 9   ❌  tar-release escript couldn't find getopt module
              Fix: explicit ERL_LIBS=deps:core:applications in build.sh
Run 10  ❌  relx assembled the release dir but skipped the tar step
              Fix: roll our own tarball from _rel/kazoo/ if relx didn't
Run 11  ✅  Both legs green in 13 min (OTP layers fully cached)
Run 12  ✅  Same with publish=true → gh-pages populated, repos live
Run 13  ✅  Tagged release → GitHub Release auto-created with both artifacts
```

Each fix is in a separate commit on `main` with a paragraph explaining the failure mode, so future maintainers can `git log` the Dockerfiles and understand why a given line exists.

---

## Known issues / Phase 2 follow-ups

These didn't block the MVP but should be filed as issues when there's time:

| # | Item | Severity |
|---|---|---|
| 1 | `COOKIE=change-me-please` ships as default in `/etc/default/kazoo` | Important — security |
| 2 | `prerm.sh` only stops the service, `preun.sh` also disables it (deb/rpm asymmetry) | Minor |
| 3 | Supply chain: `rebar3` binary + OTP source tarball fetched without SHA-256 verification | Important — supply chain |
| 4 | Org slug `cloudpbx` hardcoded in 5 source files + INSTALL.md (sed-replaceable) | Minor |
| 5 | `tests/.gitkeep`, `docker/.gitkeep`, etc. are now vestigial | Minor — cleanup PR |
| 6 | `verify-install.yml` workflow_run filter with `branches: [main]` was a footgun (already fixed) | Done |
| 7 | Unusual deb version string `~bookworm1` (Debian convention is `+deb12u1`) | Minor — cosmetic |
| 8 | `debsigs` `_gpgorigin` signature is dead code from apt's perspective | Minor |
| 9 | `make help` shows `check-target` with no description | Minor — cosmetic |
| 10 | First release built from `master` branch with date-stamped pseudo-version (no upstream tag exists yet) | Acknowledged in v1; upgrades when 2600hz tags |

The biggest near-term work item is **deciding what to do when upstream 2600hz publishes a proper `5.4.X` tag** — at that point, `config/kazoo.version` becomes the simple value `5.4.0` (or whatever they call it), the package version string drops the `~master.<sha>` suffix, and the build is fully reproducible.

---

## Repository layout (unchanged from MVP spec)

```
openkazoo-kazoo5-builder/
├── Makefile                       # make build/sign/publish/verify/test
├── config/                        # version pins (kazoo, otp, rebar, package revision)
├── docker/                        # build images for debian-12 and el9
├── packaging/                     # systemd unit + sysusers + deb/rpm scriptlets
├── scripts/                       # build.sh, sign.sh, publish.sh, verify.sh
├── tests/                         # bats unit tests (35 passing)
├── .github/workflows/             # build-and-publish + verify-install
├── docs/                          # INSTALL.md, ARCHITECTURE.md, CONTRIBUTING.md
└── STATUS.md                      # this file
```

Reference: original [design spec](docs/superpowers/specs/2026-05-12-kazoo5-debian-rpm-builder-design.md) and [implementation plan](docs/superpowers/plans/2026-05-12-kazoo5-debian-rpm-builder-mvp.md).

---

## Pipeline summary

- **15 implementation tasks** completed via subagent-driven development
- **13 CI runs** total to land the first green release (11 dry-run iterations on `publish=false`, then one publish, then the tag)
- **35/39 bats tests** pass locally (the 4 sign.bats tests require `gpg` in PATH; pass in CI)
- **GPG key** for signing: ed25519, `fpr 31B23BA9A318761AB12B01A5BAAAF143D536265D`, expires 2028-05-12
- **Repo secrets:** `GPG_PRIVATE_KEY` (set; no passphrase)

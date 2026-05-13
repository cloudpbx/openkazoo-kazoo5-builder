# Project Status

**Last updated:** 2026-05-12 (paused awaiting upstream recovery)
**Current task:** Task 15 — First dry-run release
**Status:** ⏸ blocked on upstream outage (Erlang Solutions package server)

---

## TL;DR

The MVP build pipeline is fully implemented (Tasks 1-14 ✅). The first end-to-end CI release (Task 15) is in progress but blocked on `packages.erlang-solutions.com` returning HTTP 502. When ESL recovers, re-dispatch the workflow and proceed through the rest of Task 15.

---

## Where things are

### Branches

| Branch | Tip | State |
|---|---|---|
| `main` | `8015685` | 16 commits past initial; pushed to origin |
| `feature/mvp-build` | `8015685` | identical to main (fast-forwarded); pushed to origin |
| `gh-pages` | `9bee02e` | bootstrap commit only; pushed to origin; GitHub Pages serves from here |

### Tags
None yet. First tag will be cut in Task 15 step 9, format: `v5.4.0-master-YYYYMMDD-1` or `v5.4.0-1` once upstream has a real tag.

### GitHub repo
`https://github.com/cloudpbx/openkazoo-kazoo5-builder` — public.

### GitHub Pages
- Enabled, source: `gh-pages` branch, `/`
- URL: `https://cloudpbx.github.io/openkazoo-kazoo5-builder/`
- Currently serves only the bootstrap README; will be populated by `publish` job in build.yml on next successful release.

### Repo secrets
- `GPG_PRIVATE_KEY` — set ✅ (ed25519, fpr `31B23BA9A318761AB12B01A5BAAAF143D536265D`, expires 2028-05-12)
- `GPG_PASSPHRASE` — not set (key has no passphrase; `sign.sh` handles both cases)

### Local artifacts (not committed)
- `~/$TMPDIR/openkazoo-release-keyring/` — local GPG keyring with private key
- `~/$TMPDIR/openkazoo-gpg-public.asc` — public key (just for reference; not needed for CI)
- Private key `.asc` file has been shredded from disk

---

## Task 15 progress checklist

The remaining steps from the [implementation plan](docs/superpowers/plans/2026-05-12-kazoo5-debian-rpm-builder-mvp.md) §Task 15:

- [x] Push `feature/mvp-build`
- [x] Bootstrap and push `gh-pages` branch
- [x] Enable GitHub Pages (Settings → Pages, gh-pages /)
- [x] Generate production GPG signing key
- [x] Upload `GPG_PRIVATE_KEY` repo secret (via API + PyNaCl sealed box)
- [x] Fast-forward `main` so workflows are dispatchable
- [x] First `workflow_dispatch` (publish=false) → run #1 ❌ failed (Dockerfile bugs)
- [x] Patch Dockerfile issues, commit `8015685`, push main
- [x] Second `workflow_dispatch` (publish=false) → run #2 ❌ failed (ESL 502 outage)
- [ ] **Wait for ESL recovery** ← we are here
- [ ] Third `workflow_dispatch` (publish=false) — confirm both matrix legs green
- [ ] `workflow_dispatch` with publish=true → confirm gh-pages populated
- [ ] Manually dispatch `verify-install.yml` → confirm both install jobs green
- [ ] Tag first release: `git tag v5.4.0-master-$(date -u +%Y%m%d)-1 && git push origin <tag>`
- [ ] Verify auto-created GitHub Release attaches `.deb` + `.rpm`

---

## What's blocking us

### Erlang Solutions upstream outage
**`packages.erlang-solutions.com` returns HTTP 502** to both GitHub runners and local machines as of 2026-05-12.

Affected:
- `https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc` (Debian apt key)
- `https://packages.erlang-solutions.com/rpm/centos/9/erlang-solutions-2.0-1.noarch.rpm` (EL9 yum bootstrap)
- `https://packages.erlang-solutions.com/` (their homepage)

Both Dockerfile stages depend on ESL being reachable at build time. The retry logic in commit `8015685` (5 retries × 5s = 30s) won't help because ESL is consistently down, not flapping.

**Resume manually:**
```bash
# Check ESL health from your machine
curl -sI https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | head -1
# Look for "HTTP/2 200" (not 502)

# Re-dispatch the build workflow once ESL is back
TOKEN=$(/opt/homebrew/bin/gh auth token)
curl -sS -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/workflows/build.yml/dispatches \
  -d '{"ref":"main","inputs":{"kazoo_version":"master","publish":"false"}}'
```

A Monitor (`task b04ij29pw`) was watching ESL but is bound to the chat session. If the session ends, the monitor terminates.

---

## Failed run history

| Run # | Status | Root cause | Fix |
|---|---|---|---|
| [1](https://github.com/cloudpbx/openkazoo-kazoo5-builder/actions/runs/25778830784) | ❌ failure | EL9: `curl` vs `curl-minimal` conflict on Rocky 9 base. Debian: transient ESL 502 on apt-key fetch | Commit `8015685` |
| [2](https://github.com/cloudpbx/openkazoo-kazoo5-builder/actions/runs/25778986356) | ❌ failure | Persistent ESL 502 outage on both legs (NOT in our code) | Wait for ESL recovery |

---

## Known issues to track post-Task 15

These came out of the final whole-implementation code review. None block Task 15 dry-run; all are good follow-up issues to file once the release lands.

### Important (consider filing as GH issues)

1. **`Type=forking` in `kazoo.service` may not match relx-generated launcher behavior.**
   - File: `packaging/common/kazoo.service:8`
   - Risk: `systemctl start kazoo` may not reliably supervise the BEAM VM. `verify-install.yml` only checks file placement, not service start, so this won't surface until a real install.
   - Fix options: (a) switch to `bin/kazoo foreground` + `Type=simple`, OR (b) add `PIDFile=/var/lib/kazoo/kazoo.pid` and verify relx writes one there.

2. **`COOKIE=change-me-please` ships as default.**
   - File: `packaging/common/kazoo.defaults:14`
   - Documented in `INSTALL.md` but a known-weak literal value. Consider generating a random cookie in postinst on first install only.

3. **Behavioral asymmetry between deb `prerm.sh` and rpm `preun.sh`.**
   - `prerm.sh` only stops the service; `preun.sh` also disables it. Pick one and apply consistently.

4. **Supply-chain: `rebar3` binary and ESL bootstrap RPM are fetched without checksum verification.**
   - Files: `docker/Dockerfile.debian-12:30-32`, `docker/Dockerfile.el9:28-31`
   - Phase 2 hardening: pin SHA-256 of `rebar3` and the ESL bootstrap RPM as ARGs, verify with `sha256sum -c` before installing.

5. **Hardcoded org slug `cloudpbx` in 5 source files + INSTALL.md.**
   - If the canonical org changes, sed-replace across:
     - `scripts/build.sh` (maintainer + URL for both deb and rpm)
     - `scripts/publish.sh` (baseurl, gpgkey URL in .repo, README link)
     - `packaging/common/kazoo.service` (Documentation= URL)
     - `.github/workflows/build.yml` (release body INSTALL.md link)
     - `.github/workflows/verify-install.yml` (4× published-repo URLs)
     - `docs/INSTALL.md` (6 references)

### Minor

6. **Unusual deb version string** `${PKG_REVISION}~bookworm1` (the `~` is intended for pre-release sortable versions, not distro tags). Debian convention is `1+deb12u1`. Cosmetic.

7. **`make publish` target on macOS host fails** — needs `reprepro`/`createrepo_c` which are only inside the Docker image. CI handles this correctly via `docker run`. Local-dev only.

8. **debsigs `_gpgorigin` signature is dead code from apt's perspective** — apt verifies `Release.gpg` (reprepro's `SignWith:`), not `_gpgorigin`. Useful only for manual `debsig-verify`. Document or remove.

9. **`tests/.gitkeep`, `docker/.gitkeep`, etc.** are now vestigial — every dir that had a `.gitkeep` is now populated. Cleanup PR is a 6-line `git rm` job.

10. **`make help` shows `check-target` with no description**; `make help` regex `?` is GNU-grep-specific. Cosmetic.

11. **`Type=forking` and `COOKIE` plan defects are in the plan file too** (`docs/superpowers/plans/...`). If the plan is to stay authoritative for v1.1, append a "Known issues" section there or amend in place.

---

## How to resume

### If you're coming back fresh (no Claude Code session)

```bash
cd /Users/grahamnsnz/Projects/openkazoo-kazoo5-builder
git status                 # should be clean on feature/mvp-build (or main)
git log --oneline -5       # should show 8015685 at HEAD
```

Check ESL:
```bash
curl -sI https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | head -1
```

If `HTTP/2 200`, re-trigger:
```bash
TOKEN=$(/opt/homebrew/bin/gh auth token)
curl -sS -X POST -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/workflows/build.yml/dispatches \
  -d '{"ref":"main","inputs":{"kazoo_version":"master","publish":"false"}}'
```

Watch at `https://github.com/cloudpbx/openkazoo-kazoo5-builder/actions`.

### If both matrix legs go ✅

Proceed through the remaining Task 15 checklist items above (in order).

### If they go ❌ again

Pull logs:
```bash
TOKEN=$(/opt/homebrew/bin/gh auth token)
RUN_ID=$(curl -sS -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/cloudpbx/openkazoo-kazoo5-builder/actions/runs?event=workflow_dispatch&per_page=1" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['workflow_runs'][0]['id'])")
echo "latest run: $RUN_ID"
# Then visit https://github.com/cloudpbx/openkazoo-kazoo5-builder/actions/runs/$RUN_ID
```

### If you want to resume in a Claude Code session

> Continue Task 15 from `feature/mvp-build` @ `8015685`. ESL outage was the blocker; status in `STATUS.md`. Verify ESL is back, re-dispatch the workflow with `publish: false`, then proceed through the remaining checklist if both legs go green.

---

## Reference

- **Design spec:** [`docs/superpowers/specs/2026-05-12-kazoo5-debian-rpm-builder-design.md`](docs/superpowers/specs/2026-05-12-kazoo5-debian-rpm-builder-design.md)
- **Implementation plan:** [`docs/superpowers/plans/2026-05-12-kazoo5-debian-rpm-builder-mvp.md`](docs/superpowers/plans/2026-05-12-kazoo5-debian-rpm-builder-mvp.md)
- **End-user install instructions:** [`docs/INSTALL.md`](docs/INSTALL.md)
- **Architecture overview:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Contributor guide:** [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)

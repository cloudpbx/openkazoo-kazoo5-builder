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

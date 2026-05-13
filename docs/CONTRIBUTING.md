# Contributing

## Bumping the Kazoo version

When upstream `2600hz/kazoo5` publishes a new tag or you want to track a newer commit:

```bash
echo "5.4.0" > config/kazoo.version        # tag or branch name
git commit -am "feat: bump kazoo to 5.4.0"
```

`config/kazoo.version` must be a tag or branch name that `git clone --branch` accepts.
Bare commit SHAs are not supported by `scripts/build.sh` today — pin a branch instead,
or extend `build.sh` to deep-clone + `git checkout` if SHA-pinning becomes a requirement.

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

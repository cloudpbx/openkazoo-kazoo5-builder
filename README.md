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

# Installing Kazoo from openkazoo packages

These instructions install the [Kazoo](https://github.com/2600hz/kazoo5) telephony platform
on Debian 12 (bookworm) or Rocky Linux 9 / AlmaLinux 9 / RHEL 9 from the community
[openkazoo-kazoo5-builder](https://github.com/cloudpbx/openkazoo-kazoo5-builder) repository.

**Important:** the `kazoo` package installs only the Erlang application (with its OTP
runtime bundled in). You must separately install and configure:
- **CouchDB** (use distro packages or upstream apache.org packages)
- **RabbitMQ** (use distro packages)
- **FreeSWITCH** and **Kamailio** (community 2600Hz forks not yet packaged here; see issue tracker)

The Erlang/OTP runtime is **bundled inside the package** — you do not need to add the
Erlang Solutions apt/yum source separately. (Background: ESL retired
`packages.erlang-solutions.com` in mid-2026 and the replacement does not carry OTP 26.x
for Debian bookworm or any Rocky 9 builds, so this builder compiles OTP from source via
`kerl` and ships ERTS inside the `.deb` / `.rpm`.)

## Debian 12 (bookworm)

```bash
# 1. Add the openkazoo repo
curl -fsSL https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc \
  | sudo tee /usr/share/keyrings/openkazoo.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/openkazoo.asc] \
https://cloudpbx.github.io/openkazoo-kazoo5-builder/debian bookworm main" \
  | sudo tee /etc/apt/sources.list.d/openkazoo.list

# 2. Install
sudo apt-get update
sudo apt-get install -y kazoo
```

## Rocky Linux 9 / AlmaLinux 9 / RHEL 9

```bash
# 1. Add the openkazoo repo
sudo dnf config-manager --add-repo \
  https://cloudpbx.github.io/openkazoo-kazoo5-builder/el/9/openkazoo.repo
sudo rpm --import https://cloudpbx.github.io/openkazoo-kazoo5-builder/pubkey.asc

# 2. Install
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

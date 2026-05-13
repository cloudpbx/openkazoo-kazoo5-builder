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

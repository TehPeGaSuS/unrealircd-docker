> [!WARNING]
> THIS IS A WORK IN PROGRESS! \
> USE AT YOUR OWN RISK!

# unrealircd-docker

Docker image for [UnrealIRCd](https://www.unrealircd.org/), tracking the `unreal60_dev` branch.

Built automatically every week and published to GHCR. This repo contains only the Docker packaging — source is cloned from the official UnrealIRCd repository at build time.

## Quick start

```bash
# Pull the image
docker pull ghcr.io/tehpegasus/unrealircd-docker:latest

# Create directories for persistent data
mkdir -p conf data logs

# First run: seeds conf/, generates a TLS cert, prints cloak keys and exits
docker compose run --rm unrealircd

# Edit ./conf/unrealircd.conf with your cloak keys and other settings,
# then start for real
docker compose up -d
```

When no `conf/unrealircd.conf` exists yet the container:
- seeds `conf/` with the full default configuration and copies `example.conf` to `unrealircd.conf`
- creates an empty `conf/modules.txt` (see [Third-party modules](#third-party-modules))
- copies the CA bundle to `conf/tls/curl-ca-bundle.crt` and generates a self-signed certificate in `conf/tls/`
- prints your cloak keys and **exits** instead of starting, because the example config cannot run as-is

The minimum you need to do before `docker compose up -d` is edit `conf/unrealircd.conf` and set your server name, network name, admin info, listeners and cloak keys.

> [!IMPORTANT]
> Cloak keys must be identical on every server of a network, otherwise users
> get a different cloaked host depending on which server they connect to and
> bans stop matching. If this server will link to an existing network, copy
> the network's keys instead of using the generated ones.

## Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest build from `unreal60_dev` |
| `unreal60_dev` | Same as latest |
| `YYYYMMDD` | Build date |
| `<sha>` | Short SHA of the **UnrealIRCd** commit the image was built from |

The workflow checks the upstream branch daily and builds only when its tip has
no published image yet, so a `<sha>` tag always identifies the exact UnrealIRCd
code inside. The container logs that commit on every start, and it is also in
the `org.opencontainers.image.revision` label.

## Volumes

| Path | Purpose |
|------|---------|
| `/opt/unrealircd/conf` | Configuration files, TLS certificates, and modules list |
| `/opt/unrealircd/data` | Runtime data |
| `/opt/unrealircd/logs` | Log files |

Mount all three from the host so they survive image updates.

## Ports

The compose file uses `network_mode: host`, so there is no `ports:` section:
every `listen` block in `unrealircd.conf` is live on the host's addresses,
exactly as with a native install.

## Third-party modules

Compiled modules live inside the image, so they vanish when you pull a new
one. `conf/modules.txt` is the list of third-party modules the container
installs on every start when they are missing, one per line (`#` starts a
comment):

```
third/ojoin
third/clearlist
```

### Installing a module

```bash
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd module install third/ojoin
```

The `-u unrealircd` flag is required — UnrealIRCd refuses to run as root.

Then add the module to `conf/modules.txt` so it comes back after an image
update, and load it from `unrealircd.conf` as usual.

### Removing a module

1. Remove its `loadmodule` line from `unrealircd.conf` and its line from `conf/modules.txt`
2. Restart the container, or pull a new image: anything not listed is not reinstalled

## Common commands

All commands require `-u unrealircd` when using `docker compose exec`.

```bash
# Test configuration
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd configtest

# Rehash (reload config)
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd rehash

# Reload TLS certificates
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd reloadtls

# Install a third-party module
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd module install third/ojoin

# Generate cloak keys
docker compose run --rm unrealircd /opt/unrealircd/unrealircd gencloak
```

## Networking

### Host networking (default)

With `network_mode: host` the container shares the host's network stack.
UnrealIRCd binds the host's IPv4 and IPv6 addresses directly, sees every
client's real address, and nothing depends on Docker's NAT or on which
Docker version handles IPv6 how. This is the right default for a public IRC
server on a typical VPS with one IPv4 and an on-link /64.

What you give up is only the network namespace: the container can reach
services bound to the host's `127.0.0.1`, and it competes with the host for
ports. Filesystem, process and user isolation are unchanged, and the exposure
is the same as running UnrealIRCd natively under its own user.

> **Note:** `network_mode: host` only works on Linux. On Docker Desktop
> (macOS/Windows) use the bridge setup below.

### Bridge networking (alternative)

If you prefer the extra isolation, replace `network_mode: host` with:

```yaml
    ports:
      - "6667:6667"
      - "6697:6697"
    networks:
      - irc
```

and add at the end of the file:

```yaml
networks:
  irc:
    enable_ipv6: true
```

Docker forwards published ports with iptables/ip6tables NAT, which preserves
the client's address for both IPv4 and IPv6 (clients are NATed from a private
IPv6 range, so no public prefix is needed for the containers). This requires
Docker 27 or newer, where `ip6tables` is on by default.

Clients appearing to come from the Docker gateway (e.g. `172.18.0.1`) means
Docker's *userland proxy* handled the connection, which happens for IPv6 on
older Docker and for connections from the host itself. Disable the fallback in
`/etc/docker/daemon.json` and restart Docker so misconfigurations fail loudly
instead of hiding IPs:

```json
{
  "userland-proxy": false
}
```

### Why not a proxy in front?

A reverse or TCP proxy does **not** help: UnrealIRCd has no PROXY-protocol
support, so everything would appear to come from the proxy. Its `proxy` block
only covers WEBIRC gateways and HTTP `Forwarded`/`X-Forwarded-For` headers
for websocket reverse proxies.

## Building locally

```bash
git clone https://github.com/TehPeGaSuS/unrealircd-docker
cd unrealircd-docker
docker compose build
```

## Notes

- Tracks `unreal60_dev` which is a development branch — not a stable release.
- Builds for `linux/amd64`.
- Runs as a non-root user (`unrealircd`).
- Uses `tini` as PID 1 for correct signal handling and zombie reaping.
- The compose healthcheck runs `unrealircd status`, which asks the daemon over its control socket.
- The `-F` flag keeps UnrealIRCd in the foreground as required by Docker.

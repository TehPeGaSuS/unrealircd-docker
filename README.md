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

Configured via `network_mode: host` — see [Networking](#networking) below. Define your listeners directly in `unrealircd.conf`.

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

This image uses `network_mode: host` by default. This is intentional and important.

Without host networking, Docker routes all incoming connections through its internal bridge network, which means UnrealIRCd sees every user connecting from the Docker gateway IP (typically `172.17.0.1`) instead of their real IP address. This breaks:

- IP-based bans and K-Lines
- Cloaking (all users get the same cloak)
- Throttling and connection limits per host
- Geolocation and reputation tracking

With `network_mode: host`, the container shares the host's network stack directly, so UnrealIRCd sees real client IPs as if it were running natively. The tradeoff is that Docker's network isolation is bypassed, but for a public-facing IRC server this is the correct tradeoff.

Since ports are exposed directly from the host with host networking, the `ports:` section is not needed — configure your listeners directly in `unrealircd.conf`.

> **Note:** `network_mode: host` only works on Linux. On Docker Desktop (macOS/Windows) you will need to use `ports:` mapping instead and accept that client IPs will not be accurate.

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

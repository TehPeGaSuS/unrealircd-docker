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

# Start once — seeds conf/, prints cloak keys, generates TLS cert
docker compose run --rm unrealircd

# Edit ./conf/unrealircd.conf with your cloak keys and other settings
# then start for real
docker compose up -d
```

On first run the following happens automatically:
- `conf/` is seeded with the full default configuration and `example.conf` is copied to `unrealircd.conf`
- Your cloak keys are printed to the console — copy them into `unrealircd.conf`
- A self-signed TLS certificate is generated into `conf/tls/`
- The CA bundle is copied into `conf/tls/curl-ca-bundle.crt`

The minimum you need to do before `docker compose up -d` is edit `conf/unrealircd.conf` and set your server name, network name, admin info, and cloak keys.

## Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest build from `unreal60_dev` |
| `unreal60_dev` | Same as latest |
| `YYYYMMDD` | Weekly dated snapshot |
| `<sha>` | Specific build by git short SHA |

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

Third-party modules are tracked in `modules.txt`. On each startup it will:

1. Scan `modules/third/` for any installed `.so` files and automatically check against `modules.txt`
2. Install any modules listed in `modules.txt` that are not yet compiled

This means you need to edit `modules.txt` manually to add or remove a module that you want to install/remove, one module per line like:
```
# Add the third party modules that you'd  like to keep on your server, so they
# are recompiled every time the image is updated. One module per line.
third/ojoin
third/clearlist
```

### Installing a module

```bash
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd module install third/ojoin
```

The `-u unrealircd` flag is required — UnrealIRCd refuses to run as root.

On next restart, the module is automatically checked if it exists on `modules.txt` and will be recompiled.

### Removing a module

1. Delete its line from `modules.txt`
2. Restart the container

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
- The `-F` flag keeps UnrealIRCd in the foreground as required by Docker.

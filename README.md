> [!WARNING]
> THIS IS A WORK IN PROGRESS!
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
| `/opt/unrealircd/conf` | Configuration files and TLS certificates |
| `/opt/unrealircd/data` | Runtime data |
| `/opt/unrealircd/logs` | Log files |

Mount all three from the host so they survive image updates.

## Ports

| Port | Purpose |
|------|---------|
| `6667` | Plain IRC (consider disabling if TLS-only) |
| `6697` | TLS IRC |

Add any additional ports your config uses to `docker-compose.yml`.

## Common commands

```bash
# Test configuration
docker compose exec unrealircd /opt/unrealircd/unrealircd configtest

# Rehash (reload config)
docker compose exec unrealircd /opt/unrealircd/unrealircd rehash

# Reload TLS certificates
docker compose exec unrealircd /opt/unrealircd/unrealircd reloadtls

# Install a third-party module
docker compose exec unrealircd /opt/unrealircd/unrealircd module install third/somemodule

# Generate cloak keys
docker compose run --rm unrealircd /opt/unrealircd/unrealircd gencloak
```

## Building locally

```bash
git clone https://github.com/TehPeGaSuS/unrealircd-docker
cd unrealircd-docker
docker compose build
```

## Notes

- Tracks `unreal60_dev` which is a development branch — not a stable release.
- Builds for `linux/amd64` and `linux/arm64`.
- Runs as a non-root user (`unrealircd`).
- Uses `tini` as PID 1 for correct signal handling and zombie reaping.
- The `-F` flag keeps UnrealIRCd in the foreground as required by Docker.

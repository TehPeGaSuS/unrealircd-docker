# unrealircd-docker

Docker image for [UnrealIRCd](https://www.unrealircd.org/), tracking the `unreal60_dev` branch.

Published to GHCR and rebuilt whenever the upstream branch gets new commits
(checked daily). This repo contains only the Docker packaging: the source is
fetched from the official UnrealIRCd repository at build time.

> [!TIP]
> This image was tested on Ubuntu 26.04 without any issues: first run, TLS,
> cloaking, real client IPs (IPv4 and IPv6) with host, bridge and routed IPv6
> networking, third-party modules and restarts. If it fails on your machine, please
> [open an issue](https://github.com/TehPeGaSuS/unrealircd-docker/issues) with
> your distro, Docker version and the output of `docker compose logs`.

## Quick start

```bash
# Get the compose file into a directory of your choice
mkdir -p /opt/unrealircd && cd /opt/unrealircd
curl -fsSLO https://raw.githubusercontent.com/TehPeGaSuS/unrealircd-docker/main/docker-compose.yml

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

The minimum you need to do before `docker compose up -d` is edit `conf/unrealircd.conf` and set your server name, network name, admin info, listeners and cloak keys. The example config also refuses to start until you rename the default `bobsmith` oper block and set `set::kline-address`; `docker compose logs` shows any remaining error with its line number.

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

## Updating

```bash
docker compose pull
docker compose up -d
```

Compose recreates the container on the new image. Modules listed in
`conf/modules.txt` are compiled again on that first start, and your `conf/`,
`data/` and `logs/` are untouched.

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

Compiled modules live inside the container, not in a volume, so they are gone
whenever the container is recreated (for example after `docker compose pull`
and `up -d`). `conf/modules.txt` is the list of third-party modules to bring
back, one per line (`#` starts a comment):

```
third/ojoin
third/clearlist
```

Each time the server starts, any listed module that is not compiled yet is
installed before UnrealIRCd launches. A plain `docker compose restart` reuses
the same container, so nothing is rebuilt. One-off commands such as
`docker compose run --rm unrealircd ... mkpasswd` skip this step entirely.

### Installing a module

```bash
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd module install third/ojoin
```

The `-u unrealircd` flag is required — UnrealIRCd refuses to run as root.

Then add the module to `conf/modules.txt` so it comes back after an image
update, and load it from `unrealircd.conf` as usual.

### Removing a module

1. Remove its `loadmodule` line from `unrealircd.conf` and `/rehash`
2. Remove its line from `conf/modules.txt`, so it is not reinstalled the next time the container is recreated

## Common commands

Use `docker compose exec` while the server is running, and
`docker compose run --rm` for one-off commands when it is not. All `exec`
commands require `-u unrealircd`.

```bash
# Server status and logs
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd status
docker compose logs -f

# Test configuration
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd configtest

# Rehash (reload config)
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd rehash

# Reload TLS certificates
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd reloadtls

# Install a third-party module
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd module install third/ojoin

# Hash a password for an oper block (prompts for the password)
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd mkpasswd
docker compose run --rm unrealircd /opt/unrealircd/unrealircd mkpasswd

# Show the SPKI fingerprint of the server certificate (for link blocks)
docker compose exec -u unrealircd unrealircd /opt/unrealircd/unrealircd spkifp

# Generate cloak keys
docker compose run --rm unrealircd /opt/unrealircd/unrealircd gencloak
```

`run --rm` goes through the same startup as the server: on a directory
without `conf/unrealircd.conf` it seeds the configuration and exits instead of
running your command.

## TLS certificates

The first run generates a self-signed `conf/tls/server.cert.pem` valid for
10 years. Keep it for server links: pin it with `spkifp` in the other
server's link block (see Common commands) and it never needs renewing.

For clients, use a Let's Encrypt certificate on the client listeners only,
as UnrealIRCd recommends:

```
listen {
    ip *;
    port 6697;
    options { tls; clientsonly; }
    tls-options {
        certificate "tls/letsencrypt/fullchain.pem";
        key "tls/letsencrypt/privkey.pem";
    }
}
```

Get the certificate on the host with certbot (DNS-01 needs no open port), then
install [`renew-cert.sh`](renew-cert.sh) as a deploy hook. On every renewal
it copies the new files into `conf/tls/letsencrypt/`, fixes their ownership
and runs `reloadtls`, without touching `server.*.pem`:

```sh
sudo curl -o /etc/letsencrypt/renewal-hooks/deploy/renew-cert.sh \
  https://raw.githubusercontent.com/TehPeGaSuS/unrealircd-docker/main/renew-cert.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/renew-cert.sh
sudo nano /etc/letsencrypt/renewal-hooks/deploy/renew-cert.sh   # subdomain, container, path
```

To run it once without waiting for a renewal:

```sh
sudo certbot renew --force-renewal --cert-name irc.example.org
```

(Let's Encrypt rate-limits duplicate certificates, so don't repeat that often.)

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
the client's address for both IPv4 and IPv6 (the container gets an address
from a private IPv6 range, so no public prefix is needed). This requires
Docker 27 or newer, where `ip6tables` is on by default. Tested with real
client IPs over LAN IPv4, external IPv4 (router port forward) and external
IPv6.

Use listeners with `ip *;` in bridge mode: the container does not have the
host's addresses, so a listener bound to one of them fails.

Clients appearing to come from the Docker gateway (e.g. `172.18.0.1`) means
Docker's *userland proxy* handled the connection, which happens for IPv6 on
older Docker and for connections from the host itself. We recommend disabling
it in `/etc/docker/daemon.json` and restarting Docker (this restarts all
containers), so misconfigurations fail loudly instead of hiding IPs:

```json
{
  "userland-proxy": false
}
```

### Routed IPv6 (own public address)

If your provider routes an IPv6 prefix to the host (a spare /64 from a home
router with several prefixes, or a block routed to a VPS), the container can
have its own public IPv6 address with no NAT at all. Create the network once,
using a prefix that is not configured on any host interface:

```sh
docker network create --ipv6 --subnet 2001:db8:1:2::/64 \
  -o com.docker.network.bridge.gateway_mode_ipv6=routed pubv6
```

Then use it instead of the bridge network:

```yaml
    ports:
      - "6667:6667"
      - "6697:6697"
    networks:
      pubv6:
        ipv6_address: 2001:db8:1:2::6667
```

and at the end of the file:

```yaml
networks:
  pubv6:
    external: true
```

IPv6 clients connect straight to the container's address. IPv4 still works
through the host's published ports, as with bridge networking (Docker adds a
private IPv4 subnet to the network). Only published ports are reachable on the
routed address. Point your AAAA record at that address; outgoing server links
also use it.

The prefix must be *routed* to the host (the router sends it to the host's
address as next hop) and must not be on-link anywhere: not announced on the
LAN by the router, and not assigned to a host interface. If the host also has
an address from that prefix (e.g. `2001:db8:1:2::1/64` on `eth0`), the
kernel treats the prefix as local to that interface and the container is
unreachable. Tested with real client IPs over external IPv6 and IPv4.

### Why not a proxy in front?

A reverse or TCP proxy does **not** help: UnrealIRCd has no PROXY-protocol
support, so everything would appear to come from the proxy. Its `proxy` block
only covers WEBIRC gateways and HTTP `Forwarded`/`X-Forwarded-For` headers
for websocket reverse proxies.

## Building locally

```bash
git clone https://github.com/TehPeGaSuS/unrealircd-docker
cd unrealircd-docker
docker build -t ghcr.io/tehpegasus/unrealircd-docker:latest .
```

This builds the current tip of `unreal60_dev`. To build an exact upstream
commit, add `--build-arg UPSTREAM_SHA=<full sha>`. The compose file then uses
the local image; alternatively uncomment `build: .` in `docker-compose.yml`
and run `docker compose build`.

## Notes

- Tracks `unreal60_dev` which is a development branch — not a stable release.
- Builds for `linux/amd64`, compiled for generic x86-64 so it runs on any 64-bit Intel/AMD CPU. Argon2 comes from Debian's `libargon2` rather than UnrealIRCd's bundled copy, which would be tuned to the CPU of the build machine.
- Runs as a non-root user (`unrealircd`).
- Uses `tini` as PID 1 for correct signal handling and zombie reaping.
- The compose healthcheck runs `unrealircd status`, which asks the daemon over its control socket.
- The container prints the UnrealIRCd commit it was built from on every start.
- The `-F` flag keeps UnrealIRCd in the foreground as required by Docker.

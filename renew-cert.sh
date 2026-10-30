#!/usr/bin/env bash

# Certbot deploy hook for the UnrealIRCd container.
#
# Copies a renewed Let's Encrypt certificate into conf/tls/letsencrypt/ and
# makes UnrealIRCd reload it. The default conf/tls/server.cert.pem and
# server.key.pem are never touched, so the SPKI fingerprint used in link
# blocks (spkifp) stays the same across renewals. See README "TLS
# certificates" for the matching listen block.
#
# NOTE: This script was made to work with certbot. It is not guaranteed to
#       work with other ACME clients.
#
#       Place this script inside /etc/letsencrypt/renewal-hooks/deploy/ and
#       make it executable:
#
#           chmod +x /etc/letsencrypt/renewal-hooks/deploy/renew-cert.sh
#
#       Edit the subdomain, container name and path to fit your setup.

# What's your subdomain? (the certbot certificate name)
subdomain=irc.example.org

# Name of the UnrealIRCd container (container_name in docker-compose.yml)
container=unrealircd

# Host path of the conf/tls folder bind-mounted into the container, plus
# /letsencrypt. With docker-compose.yml in /opt/unrealircd this is:
tlsDir=/opt/unrealircd/conf/tls/letsencrypt

# Don't edit anything below unless you know exactly what you're doing.

case $RENEWED_LINEAGE in
    */"$subdomain")
        mkdir -p -- "$tlsDir" &&
        cp -f -- "$RENEWED_LINEAGE"/fullchain.pem "$RENEWED_LINEAGE"/privkey.pem "$tlsDir" &&
        docker exec "$container" chown -R unrealircd:unrealircd /opt/unrealircd/conf/tls/letsencrypt &&
        docker exec -u unrealircd "$container" /opt/unrealircd/unrealircd reloadtls
esac

#!/bin/sh
set -e

BASEPATH=/opt/unrealircd
CONFDIR=$BASEPATH/conf
TLSDIR=$CONFDIR/tls
MODULES_LIST=$CONFDIR/modules.txt

echo "UnrealIRCd image built from upstream commit $(cat $BASEPATH/UPSTREAM_SHA 2>/dev/null || echo unknown)"

# Fix ownership of mounted volumes in case host dirs are owned by root.
# Only touch what is wrong so a big logs/ volume does not slow every start.
find "$CONFDIR" "$BASEPATH/data" "$BASEPATH/logs" \
    ! -user unrealircd -exec chown unrealircd:unrealircd {} +

# Seed conf/ from defaults if unrealircd.conf is missing, then stop so the
# admin can edit it. Starting with the example config would only fail on the
# placeholder cloak keys.
if [ ! -f "$CONFDIR/unrealircd.conf" ]; then
    echo "No unrealircd.conf found, seeding default configuration..."
    cp -rn $BASEPATH/conf.defaults/. "$CONFDIR/"
    cp "$CONFDIR/examples/example.conf" "$CONFDIR/unrealircd.conf"
    chown -R unrealircd:unrealircd "$CONFDIR"
    SEEDED=1
fi

# Third-party modules to (re)install on every start, one per line.
if [ ! -f "$MODULES_LIST" ]; then
    cat > "$MODULES_LIST" <<'EOT'
# Third-party modules to keep on this server, one per line, e.g.
#   third/ojoin
# They are (re)installed on every container start when missing, so they
# survive image updates. Remove a line and restart to drop a module.
EOT
    chown unrealircd:unrealircd "$MODULES_LIST"
fi

# Copy CA bundle if missing
if [ ! -f "$TLSDIR/curl-ca-bundle.crt" ]; then
    mkdir -p "$TLSDIR"
    cp /etc/ssl/certs/ca-certificates.crt "$TLSDIR/curl-ca-bundle.crt"
    chown -R unrealircd:unrealircd "$TLSDIR"
fi

# Generate a self-signed TLS cert if none exists
if [ ! -f "$TLSDIR/server.cert.pem" ]; then
    echo "No TLS certificate found, generating a self-signed one..."
    mkdir -p "$TLSDIR"
    chown unrealircd:unrealircd "$TLSDIR"
    gosu unrealircd openssl req -x509 -newkey rsa:4096 \
        -keyout "$TLSDIR/server.key.pem" \
        -out "$TLSDIR/server.cert.pem" \
        -days 3650 -nodes \
        -subj "/CN=localhost"
    echo "TLS certificate generated in $TLSDIR"
    echo "Replace with a real certificate when you have one."
fi

if [ -n "$SEEDED" ]; then
    echo ""
    echo "================================================================"
    echo " Default configuration seeded into ./conf/"
    echo " Here are your cloak keys — put them in conf/unrealircd.conf:"
    echo "================================================================"
    gosu unrealircd $BASEPATH/unrealircd gencloak
    echo "================================================================"
    echo " NOTE: cloak keys must be identical on every server of a network."
    echo " If this server will link to an existing network, use that"
    echo " network's keys instead of the ones generated above."
    echo "================================================================"
    echo " Edit conf/unrealircd.conf (server name, network, admin, cloak"
    echo " keys, listeners), then start the server with: docker compose up -d"
    echo "================================================================"
    exit 0
fi

# Install any third-party modules listed in modules.txt that are not
# compiled yet (e.g. after an image update).
while IFS= read -r mod || [ -n "$mod" ]; do
    mod=${mod%%#*}
    mod=$(printf '%s' "$mod" | tr -d '[:space:]')
    [ -n "$mod" ] || continue
    if [ ! -f "$BASEPATH/modules/${mod}.so" ]; then
        echo "Installing missing module: $mod"
        gosu unrealircd $BASEPATH/unrealircd module install "$mod" || \
            echo "WARNING: Failed to install module $mod"
    fi
done < "$MODULES_LIST"

# Drop to unrealircd user for the actual process
exec gosu unrealircd "$@"

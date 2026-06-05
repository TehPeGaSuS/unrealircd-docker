#!/bin/sh
set -e

BASEPATH=/opt/unrealircd
TLSDIR=$BASEPATH/conf/tls
MODULES_LIST=$BASEPATH/modules.txt

# Fix ownership of mounted volumes in case host dirs are owned by root
chown -R unrealircd:unrealircd \
    $BASEPATH/conf \
    $BASEPATH/data \
    $BASEPATH/logs

# Seed conf/ from defaults if unrealircd.conf is missing
if [ ! -f "$BASEPATH/conf/unrealircd.conf" ]; then
    echo "No unrealircd.conf found, seeding default configuration..."
    cp -rn $BASEPATH/conf.defaults/. $BASEPATH/conf/
    cp $BASEPATH/conf/examples/example.conf $BASEPATH/conf/unrealircd.conf
    chown -R unrealircd:unrealircd $BASEPATH/conf
    echo ""
    echo "================================================================"
    echo " Default configuration seeded into $BASEPATH/conf/"
    echo " Here are your cloak keys — add them to unrealircd.conf:"
    echo "================================================================"
    gosu unrealircd $BASEPATH/unrealircd gencloak
    echo "================================================================"
    echo ""
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
    gosu unrealircd openssl req -x509 -newkey rsa:4096 \
        -keyout "$TLSDIR/server.key.pem" \
        -out "$TLSDIR/server.cert.pem" \
        -days 3650 -nodes \
        -subj "/CN=localhost"
    chown -R unrealircd:unrealircd "$TLSDIR"
    echo "TLS certificate generated in $TLSDIR"
    echo "Replace with a real certificate when you have one."
fi

# Install any third-party modules listed in modules.txt.
# Edit modules.txt in your project directory to add/remove modules.
# On each start, any listed module that is not compiled will be installed.
if [ -f "$MODULES_LIST" ]; then
    while IFS= read -r mod || [ -n "$mod" ]; do
        case "$mod" in
            ''|\#*) continue ;;
        esac
        SO="$BASEPATH/modules/${mod}.so"
        if [ ! -f "$SO" ]; then
            echo "Installing missing module: $mod"
            gosu unrealircd $BASEPATH/unrealircd module install "$mod" || \
                echo "WARNING: Failed to install module $mod"
        fi
    done < "$MODULES_LIST"
fi

# Drop to unrealircd user for the actual process
exec gosu unrealircd "$@"

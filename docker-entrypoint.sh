#!/bin/sh
set -e

BASEPATH=/opt/unrealircd
TLSDIR=$BASEPATH/conf/tls
MODULES_LIST=$BASEPATH/data/modules.list

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

# Reinstall any third-party modules that are missing.
#
# modules.list lives in the data volume so it survives image updates.
# Each line is a module name, e.g. third/ojoin
# Add modules to this file manually, or it is updated automatically
# when you run: unrealircd module install <name>
#
# On every start we check each listed module and reinstall it if the
# compiled .so is absent (e.g. after pulling a new image).
if [ -f "$MODULES_LIST" ]; then
    while IFS= read -r mod || [ -n "$mod" ]; do
        # skip empty lines and comments
        case "$mod" in
            ''|\#*) continue ;;
        esac
        # derive the .so filename: third/ojoin -> third/ojoin.so
        SO="$BASEPATH/modules/${mod}.so"
        if [ ! -f "$SO" ]; then
            echo "Reinstalling missing module: $mod"
            gosu unrealircd $BASEPATH/unrealircd module install "$mod" || \
                echo "WARNING: Failed to install module $mod"
        fi
    done < "$MODULES_LIST"
fi

# Drop to unrealircd user for the actual process
exec gosu unrealircd "$@"

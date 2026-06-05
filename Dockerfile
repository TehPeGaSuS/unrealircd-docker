# UnrealIRCd Docker image
# Tracks the unreal60_dev branch from the official UnrealIRCd repository.
# Source is cloned at build time — this repo is packaging only.

# Stage 1: build
FROM debian:12-slim AS builder

ARG BRANCH=unreal60_dev
ARG BASEPATH=/opt/unrealircd

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    git \
    ca-certificates \
    libssl-dev \
    libpcre2-dev \
    libargon2-0-dev \
    libsodium-dev \
    libc-ares-dev \
    libcurl4-openssl-dev \
    libjansson-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --branch ${BRANCH} --depth 1 \
    https://github.com/unrealircd/unrealircd.git src

WORKDIR /build/src

RUN cat > config.settings <<SETTINGS
BASEPATH=${BASEPATH}
BINDIR=${BASEPATH}/bin
DATADIR=${BASEPATH}/data
CONFDIR=${BASEPATH}/conf
MODULESDIR=${BASEPATH}/modules
LOGDIR=${BASEPATH}/logs
CACHEDIR=${BASEPATH}/cache
DOCDIR=${BASEPATH}/doc
TMPDIR=${BASEPATH}/tmp
PRIVATELIBDIR=${BASEPATH}/lib
MAXCONNECTIONS_REQUEST="auto"
NICKNAMEHHISTORYLENGTH="2000"
GEOIP="classic"
DEFPERM="0600"
SSLDIR=""
REMOTEINC=""
CURLDIR=""
NOOPEROVERRIDE=""
OPEROVERRIDEVERIFY=""
GENCERTIFICATE="0"
EXTRAPARA=""
ADVANCED=""
SETTINGS

ENV CFLAGS="-O2 -march=x86-64"

RUN ./Config -quick \
  && make -j$(nproc) \
  && make install

# Stage 2: runtime
FROM debian:12-slim

ARG BASEPATH=/opt/unrealircd
ENV BASEPATH=${BASEPATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libpcre2-8-0 \
    libargon2-1 \
    libsodium23 \
    libc-ares2 \
    libcurl4 \
    libjansson4 \
    ca-certificates \
    openssl \
    tini \
    gosu \
    netcat-openbsd \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder ${BASEPATH} ${BASEPATH}
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Save defaults before VOLUME wipes the layer, then fix ownership
RUN useradd -r -d ${BASEPATH} -s /sbin/nologin unrealircd \
  && cp -r ${BASEPATH}/conf ${BASEPATH}/conf.defaults \
  && chown -R unrealircd:unrealircd ${BASEPATH} \
  && chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["${BASEPATH}/conf", "${BASEPATH}/data", "${BASEPATH}/logs"]

EXPOSE 6667 6697

WORKDIR ${BASEPATH}
# Entrypoint runs as root to fix permissions, then drops to unrealircd via gosu

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["/opt/unrealircd/bin/unrealircd", "-F"]

# UnrealIRCd Docker image
# Tracks the unreal60_dev branch from the official UnrealIRCd repository.
# Source is cloned at build time — this repo is packaging only.

# Stage 1: build
FROM debian:12-slim AS builder

ARG BRANCH=unreal60_dev
# Exact upstream commit to build. The CI passes the current tip of BRANCH so
# the clone layer is never served from cache; empty means "tip of BRANCH".
ARG UPSTREAM_SHA=

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
RUN git init -q src \
  && cd src \
  && git remote add origin https://github.com/unrealircd/unrealircd.git \
  && git fetch -q --depth 1 origin "${UPSTREAM_SHA:-${BRANCH}}" \
  && git checkout -q FETCH_HEAD \
  && git rev-parse HEAD > /build/UPSTREAM_SHA

WORKDIR /build/src

# Answers for ./Config -quick (paths under /opt/unrealircd)
COPY config.settings ./config.settings

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
    # Required for 'unrealircd module install' at runtime
    build-essential \
    pkg-config \
    libssl-dev \
    libpcre2-dev \
    libargon2-0-dev \
    libsodium-dev \
    libc-ares-dev \
    libcurl4-openssl-dev \
    libjansson-dev \
    git \
  && rm -rf /var/lib/apt/lists/* \
  # The module manager requires 'gmake' by name; Debian only ships 'make'
  && ln -sf /usr/bin/make /usr/local/bin/gmake

COPY --from=builder ${BASEPATH} ${BASEPATH}
COPY --from=builder /build/UPSTREAM_SHA ${BASEPATH}/UPSTREAM_SHA
# Source tree is required by the module manager to compile modules
COPY --from=builder /build/src /build/src
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Save defaults before VOLUME wipes the layer, then fix ownership
RUN useradd -r -d ${BASEPATH} -s /usr/sbin/nologin unrealircd \
  && cp -r ${BASEPATH}/conf ${BASEPATH}/conf.defaults \
  && chown -R unrealircd:unrealircd ${BASEPATH} /build/src \
  && chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["${BASEPATH}/conf", "${BASEPATH}/data", "${BASEPATH}/logs"]

EXPOSE 6667 6697

WORKDIR ${BASEPATH}
# Entrypoint runs as root to fix permissions, then drops to unrealircd via gosu

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["/opt/unrealircd/bin/unrealircd", "-F"]

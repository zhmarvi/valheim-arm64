ARG DEBIAN_IMAGE=arm64v8/debian:trixie-slim

FROM ${DEBIAN_IMAGE} AS box64-builder

ARG BOX64_VERSION=0.4.4
ARG BOX64_SHA256=99c6de4f509e46ab1de15df740d0e0ea338a7790efa3f67510dfbb975cc24029

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/box64

# Box64 0.4.4 omits this libogg 1.3.x symbol even though Valheim's
# libparty.so imports it. Keep the patch explicit until upstream wraps it.
RUN curl --fail --location --show-error --silent --retry 3 \
        "https://github.com/ptitSeb/box64/archive/refs/tags/v${BOX64_VERSION}.tar.gz" \
        --output box64.tar.gz \
    && echo "${BOX64_SHA256}  box64.tar.gz" | sha256sum --check --strict \
    && mkdir source build \
    && tar --extract --gzip --file box64.tar.gz --strip-components=1 --directory source \
    && sed --in-place \
        's|^//GO(ogg_stream_pageout_fill,.*$|GO(ogg_stream_pageout_fill, iFppi)|' \
        source/src/wrapped/wrappedlibogg_private.h \
    && grep --fixed-strings --line-regexp \
        'GO(ogg_stream_pageout_fill, iFppi)' \
        source/src/wrapped/wrappedlibogg_private.h \
    && cmake \
        -S source \
        -B build \
        -DARM_DYNAREC=ON \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DNOGIT=1 \
    && cmake --build build --parallel "$(nproc)" \
    && DESTDIR=/box64-root cmake --install build \
    && install -D -m 0644 source/LICENSE /box64-root/usr/share/licenses/box64/LICENSE

FROM ${DEBIAN_IMAGE} AS depotdownloader

ARG DEPOTDOWNLOADER_VERSION=3.4.0
ARG DEPOTDOWNLOADER_SHA256=d9fb612ccebc1db8eeea3b4045d2221ec70431381393ce908fb72f01d4f9c812
ARG DEPOTDOWNLOADER_SOURCE_SHA256=2f09a0aaf003ee01fce44ec9acc0371441172e27d544eb7ccbe7974c01f47f42

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/depotdownloader

RUN curl --fail --location --show-error --silent --retry 3 \
        "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOTDOWNLOADER_VERSION}/DepotDownloader-linux-arm64.zip" \
        --output depotdownloader.zip \
    && echo "${DEPOTDOWNLOADER_SHA256}  depotdownloader.zip" | sha256sum --check --strict \
    && mkdir -p /depot-root/opt/depotdownloader /depot-root/usr/src \
    && unzip -q depotdownloader.zip -d /depot-root/opt/depotdownloader \
    && chmod 0755 /depot-root/opt/depotdownloader/DepotDownloader \
    && curl --fail --location --show-error --silent --retry 3 \
        "https://github.com/SteamRE/DepotDownloader/archive/refs/tags/DepotDownloader_${DEPOTDOWNLOADER_VERSION}.tar.gz" \
        --output depotdownloader-source.tar.gz \
    && echo "${DEPOTDOWNLOADER_SOURCE_SHA256}  depotdownloader-source.tar.gz" | sha256sum --check --strict \
    && install -m 0644 depotdownloader-source.tar.gz \
        "/depot-root/usr/src/DepotDownloader-${DEPOTDOWNLOADER_VERSION}.tar.gz"

FROM ${DEBIAN_IMAGE}

ARG PUID=1000
ARG PGID=1000

LABEL org.opencontainers.image.title="Valheim dedicated server for ARM64" \
      org.opencontainers.image.description="Debian-based Valheim dedicated server using native ARM64 DepotDownloader and Box64" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/home/valheim \
    VALHEIM_SERVER_DIR=/opt/valheim \
    VALHEIM_CONFIG_DIR=/config \
    DEPOTDOWNLOADER_DIR=/opt/depotdownloader \
    DOTNET_BUNDLE_EXTRACT_BASE_DIR=/tmp/dotnet-bundle \
    BOX64_LOG=0 \
    BOX64_DYNAREC=1 \
    BOX64_LD_PRELOAD=libogg.so.0 \
    SERVER_NAME="Valheim ARM64" \
    WORLD_NAME="Dedicated" \
    SERVER_PORT=2456 \
    SERVER_PUBLIC=1 \
    SERVER_CROSSPLAY=false \
    UPDATE_ON_START=true \
    SAVE_INTERVAL=1800 \
    BACKUPS=4 \
    BACKUP_SHORT=7200 \
    BACKUP_LONG=43200

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --chmod=0755 scripts/security-updates.sh /usr/local/bin/security-updates.sh

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libatomic1 \
        libc6 \
        libcurl4 \
        libgcc-s1 \
        libglib2.0-0 \
        libgssapi-krb5-2 \
        libicu76 \
        libogg0 \
        libpulse-mainloop-glib0 \
        libpulse0 \
        libsdl2-2.0-0 \
        libsdl3-0 \
        libssl3t64 \
        libstdc++6 \
        tini \
        zlib1g \
    && /usr/local/bin/security-updates.sh \
    && groupadd --gid "${PGID}" valheim \
    && useradd \
        --uid "${PUID}" \
        --gid "${PGID}" \
        --create-home \
        --home-dir /home/valheim \
        --shell /bin/bash \
        valheim \
    && mkdir -p \
        /config \
        /home/valheim/.steam/sdk64 \
        /opt/valheim \
        /run/valheim \
        /tmp/dotnet-bundle \
    && chown -R valheim:valheim \
        /config \
        /home/valheim \
        /opt/valheim \
        /run/valheim \
        /tmp/dotnet-bundle \
    && rm -rf /var/lib/apt/lists/*

COPY --from=box64-builder /box64-root/ /
COPY --from=depotdownloader /depot-root/ /
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY --chmod=0644 THIRD_PARTY_NOTICES.md /usr/share/doc/valheim-arm64/THIRD_PARTY_NOTICES.md

USER valheim:valheim
WORKDIR /opt/valheim

VOLUME ["/opt/valheim", "/config"]
EXPOSE 2456-2458/udp

STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=10m --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

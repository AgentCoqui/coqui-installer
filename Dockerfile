# syntax=docker/dockerfile:1

# ── Runtime base: PHP 8.4 CLI + coqui extension set (parity with install.sh) ──
FROM php:8.4-cli-bookworm

ARG COQUI_VERSION
LABEL org.opencontainers.image.title="coqui" \
      org.opencontainers.image.source="https://github.com/carmelosantana/coqui-installer" \
      org.opencontainers.image.description="Coqui CAP API + Flutter web UI (single container)"

# System deps: build headers for the PHP extensions + tools for fetch/verify.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl coreutils \
        libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
        libxml2-dev libsqlite3-dev libonig-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" dom xml pdo_sqlite mbstring gd pcntl posix; \
    rm -rf /var/lib/apt/lists/*

# Assemble the coqui server from its prebuilt release (fail-closed checksum verify).
COPY docker/fetch-coqui.sh /usr/local/bin/fetch-coqui.sh
RUN chmod +x /usr/local/bin/fetch-coqui.sh \
    && /usr/local/bin/fetch-coqui.sh "${COQUI_VERSION}" /srv/coqui

# Record the server version so AppVersion reports it at runtime.
ENV COQUI_VERSION=${COQUI_VERSION}

WORKDIR /srv/coqui

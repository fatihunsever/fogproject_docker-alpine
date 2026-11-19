# FOG Project on Alpine - thin image.
# The image only carries the FOG source tree + entrypoint. The official FOG
# installer (which supports Alpine since 1.6.0) pulls the runtime packages
# (nginx, php-fpm, tftp-hpa, vsftpd, nfs-utils ...) on first boot, so the base
# image stays tiny and always follows Alpine's current php8x packages.

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

ARG FOG_VERSION=1.6.0.158
ENV FOG_VERSION=${FOG_VERSION}

RUN apk add --no-cache bash curl tar xz ca-certificates openrc \
 && mkdir -p /opt/fog-src \
 && curl -fsSL "https://codeload.github.com/FOGProject/fogproject/tar.gz/refs/tags/${FOG_VERSION}" \
    | tar -xz -C /opt/fog-src --strip-components=1

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Persistent state: captured images, FOG settings/snapins/ssl, tftp tree
VOLUME ["/images", "/opt/fog"]

ENTRYPOINT ["/entrypoint.sh"]

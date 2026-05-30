# syntax=docker/dockerfile:1
#
# apache-oidc — a small, maintained Apache 2.4 + mod_auth_openidc base image.
#
# A configurable, up-to-date replacement for older OIDC-enabled httpd images.
# It ships Apache, the OpenID Connect module and the modules commonly needed to
# build an authenticating reverse proxy / gateway (proxy, SSL, websockets, SSI,
# content negotiation). It is intentionally CONFIG-FREE: provide your own virtual
# host (see README) — nothing project-specific is baked in.
#
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="apache-oidc" \
      org.opencontainers.image.description="Maintained Apache + mod_auth_openidc base image — config-free OIDC reverse-proxy / gateway" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/tripple-v/apache-oidc"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      apache2 \
      libapache2-mod-auth-openidc \
      ca-certificates \
 && a2enmod \
      auth_openidc \
      proxy proxy_http proxy_wstunnel \
      headers rewrite \
      include negotiation \
      ssl \
 && a2dissite 000-default \
 && rm -rf /var/lib/apt/lists/*

# Apache logs → container stdout/stderr (so `docker logs` / log shippers work).
RUN ln -sf /dev/stdout /var/log/apache2/access.log \
 && ln -sf /dev/stderr /var/log/apache2/error.log

# Runtime dir + env needed by apachectl in the foreground.
RUN mkdir -p /var/run/apache2
ENV APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid \
    APACHE_LOG_DIR=/var/log/apache2

EXPOSE 80 443
CMD ["apachectl", "-D", "FOREGROUND"]

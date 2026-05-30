# apache-oidc

[![Docker Hub](https://img.shields.io/docker/v/vwuilbea/apache-oidc?sort=semver&logo=docker&label=Docker%20Hub&color=2496ED)](https://hub.docker.com/r/vwuilbea/apache-oidc)
[![Image size](https://img.shields.io/docker/image-size/vwuilbea/apache-oidc?sort=semver)](https://hub.docker.com/r/vwuilbea/apache-oidc/tags)
[![Pulls](https://img.shields.io/docker/pulls/vwuilbea/apache-oidc)](https://hub.docker.com/r/vwuilbea/apache-oidc)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](https://github.com/tripple-v/apache-oidc/blob/main/LICENSE)

**Source:** [github.com/tripple-v/apache-oidc](https://github.com/tripple-v/apache-oidc) · **Image:** [`vwuilbea/apache-oidc`](https://hub.docker.com/r/vwuilbea/apache-oidc)

A small, **maintained** Apache HTTP Server + [`mod_auth_openidc`](https://github.com/OpenIDC/mod_auth_openidc)
base image. Drop it in front of any web app to add **OpenID Connect** login (Keycloak, Auth0,
Microsoft Entra, Google…) and proxy authenticated traffic to your backend.

It is **config-free**: you bring your own virtual host. Nothing project-specific — and **no
secrets** — are baked in.

```dockerfile
FROM vwuilbea/apache-oidc:1
COPY my-vhost.conf /etc/apache2/sites-available/app.conf
RUN a2ensite app
```

## Why this image

- **Up to date & patched.** Built on Debian `bookworm-slim` with the distro's current
  `libapache2-mod-auth-openidc` and OpenSSL — rebuilt to pick up security fixes, instead of
  relying on years-old images.
- **Config-free, secret-free.** No baked-in vhost and, deliberately, **no bundled TLS
  certificate or private key**. Some older images ship a *shared* self-signed key in the repo —
  convenient, but everyone ends up with the same private key, which is not real security. You
  provide your own (or terminate TLS upstream). See [TLS](#tls).
- **Batteries included.** The modules you actually need for a gateway are pre-enabled
  (reverse proxy, websockets, SSL, SSI, content negotiation).
- **Multi-arch.** Published for `linux/amd64` and `linux/arm64` (works on servers and on
  Apple Silicon laptops).
- **12-factor friendly.** Logs to `stdout`/`stderr`; configuration via environment variables.

## What's inside

| | |
|---|---|
| Base | `debian:bookworm-slim` |
| Server | Apache HTTP Server 2.4 (`apache2`) |
| OIDC | `libapache2-mod-auth-openidc` |
| Modules enabled | `auth_openidc`, `proxy`, `proxy_http`, `proxy_wstunnel`, `headers`, `rewrite`, `include`, `negotiation`, `ssl` |
| Logging | Apache access/error → container `stdout`/`stderr` |
| Ports | `80`, `443` |
| Entrypoint | `apachectl -D FOREGROUND` |

## Usage

You provide a virtual host. Two ways:

### Option A — extend the image (recommended for an app)

```dockerfile
FROM vwuilbea/apache-oidc:1
COPY app.conf /etc/apache2/sites-available/app.conf
RUN a2ensite app
```

### Option B — mount a vhost at runtime

```yaml
services:
  gateway:
    image: vwuilbea/apache-oidc:1
    ports: ["80:80"]
    environment:
      SERVER_NAME: app.example.com
      OIDC_METADATA_URL: https://idp.example.com/realms/demo/.well-known/openid-configuration
      OIDC_CLIENT: my-client
      OIDC_SECRET: ${OIDC_SECRET}
      OIDC_CRYPT: ${OIDC_CRYPT}
      UPSTREAM: http://app:8080
    volumes:
      - ./vhost.conf:/etc/apache2/sites-enabled/app.conf:ro
```

> **Tip:** Apache expands `${VAR}` in the config from environment variables, so the *same*
> vhost file works across environments by changing env values only — no rebuild.

A complete, ready-to-edit vhost is in [`examples/vhost.conf.example`](https://github.com/tripple-v/apache-oidc/blob/main/examples/vhost.conf.example).

## Full example: gateway + app + Keycloak

```yaml
services:
  gateway:
    image: vwuilbea/apache-oidc:1
    ports: ["8080:80"]
    environment:
      SERVER_NAME: localhost
      OIDC_METADATA_URL: http://keycloak:8080/realms/demo/.well-known/openid-configuration
      OIDC_CLIENT: demo-client
      OIDC_SECRET: demo-secret
      OIDC_CRYPT: a-random-passphrase
      UPSTREAM: http://app:80
    volumes:
      - ./vhost.conf:/etc/apache2/sites-enabled/app.conf:ro
    depends_on: [keycloak, app]

  app:
    image: traefik/whoami   # any backend; receives the OIDC access token as Bearer

  keycloak:
    image: quay.io/keycloak/keycloak:26.3
    command: start-dev
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin
    ports: ["8081:8080"]
```

Use [`examples/vhost.conf.example`](https://github.com/tripple-v/apache-oidc/blob/main/examples/vhost.conf.example) as `vhost.conf`, create a
`demo` realm + `demo-client` in Keycloak, then open <http://localhost:8080> → you'll be
redirected to Keycloak to log in, then proxied to the app.

## Environment variables (used by the example vhost)

Because the image is config-free, the variables are **whatever your vhost references**. The
example vhost uses:

| Variable | Description |
|---|---|
| `SERVER_NAME` | Public host name of the gateway |
| `OIDC_METADATA_URL` | The IdP's `.well-known/openid-configuration` URL |
| `OIDC_CLIENT` | OIDC client id |
| `OIDC_SECRET` | OIDC client secret |
| `OIDC_CRYPT` | Passphrase used by mod_auth_openidc to encrypt session state |
| `UPSTREAM` | Backend to proxy to, e.g. `http://app:8080` |

## TLS

This image **does not ship a certificate or private key**. Pick one:

1. **Terminate TLS upstream** (recommended in production): put Traefik / nginx / a cloud LB in
   front, let it handle HTTPS, and run this gateway on `:80`. Add
   `OIDCXForwardedHeaders X-Forwarded-Proto X-Forwarded-Host X-Forwarded-Port` to your vhost so
   cookies are marked `Secure` and redirects are built as `https`.
2. **Terminate TLS in Apache**: in your vhost use a `<VirtualHost *:443>` with `SSLEngine on`
   and mount **your own** certificate + key:
   ```yaml
   volumes:
     - ./tls.crt:/etc/ssl/app/tls.crt:ro
     - ./tls.key:/etc/ssl/app/tls.key:ro
   ```

## Tags & versioning

| Tag | Meaning |
|---|---|
| `1.0.0` | Exact, **immutable** release — pin for full reproducibility |
| `1.0` | Latest patch of `1.0.x` |
| `1` | Latest minor+patch of major `1` — good default to pin |
| `latest` | Latest release |
| `edge` | Latest commit on `main` (preview, may be unstable) |

Releases are cut from semver git tags (`vX.Y.Z`). Pin `:1` for auto security/patch updates, or
`:1.0.0` to freeze. Rebuilds (re)publish to pick up Debian/OpenSSL fixes.

## Build & publish (maintainer)

Publishing is automated by GitHub Actions ([`.github/workflows/publish.yml`](https://github.com/tripple-v/apache-oidc/blob/main/.github/workflows/publish.yml)):

- **Push to `main`** → builds multi-arch (amd64 + arm64), pushes `:edge`, and syncs this
  README to the Docker Hub description.
- **Push a tag `vX.Y.Z`** → publishes `:X.Y.Z`, `:X.Y`, `:X` and `:latest`. Cut a release with:
  ```bash
  git tag v1.0.0 && git push origin v1.0.0
  ```

Requires two repo secrets: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (a Docker Hub access
token with Read/Write).

<details>
<summary>Manual build (fallback)</summary>

```bash
docker login
docker buildx create --use --name multiarch 2>/dev/null || docker buildx use multiarch
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t vwuilbea/apache-oidc:1 \
  -t vwuilbea/apache-oidc:latest \
  --push .
```
</details>

## Contributing

Issues and PRs welcome — this exists to give the community a current, no-surprises OIDC gateway
base image. Please don't commit certificates or secrets.

## License

[Apache License 2.0](https://github.com/tripple-v/apache-oidc/blob/main/LICENSE) — see also [NOTICE](https://github.com/tripple-v/apache-oidc/blob/main/NOTICE).

# PHP WordPress Base Image

An optimized **PHP-FPM 8.5** Docker image for WordPress, built on Debian 13 ("Trixie"). It maps host users (PUID/PGID) into the container and renders all PHP / FPM / mail configuration from environment variables at container start. It is the shared base image for many WordPress sites across a multi-server Docker stack.

## Features

- **PHP 8.5 FPM** — official image on Debian 13 (Trixie)
- **Optimized for WordPress** — tuned PHP settings for performance and security
- **APCu object cache** — with the igbinary serializer for fast, compact caching
- **OPcache** — with file cache for faster performance after restart
- **Redis extension** — ready for a Redis object-cache drop-in
- **Imagick** — for image processing
- **Automatic user mapping** — runs with the same PUID/PGID as the host
- **Per-site configuration** — every WordPress installation sets its own resources via environment variables
- **msmtp built-in** — mail via a host SMTP relay
- **Secure** — dangerous PHP functions disabled, `expose_php` off, secure session cookies
- **Multi-site ready** — works with WordPress Multisite

## Tags

| Tag | Description | When to use |
|-----|-------------|-------------|
| `latest` | Most recent build from `main` | Production |
| `vX.Y.Z` | Semantic version (from `v*` git tags) | Pin a specific release |
| `<short-sha>` | Commit SHA | Debugging / testing a specific commit |

## Requirements

- Docker 20.10+ and Docker Compose 2.0+
- An existing Docker network: `phpnet` (subnet `172.50.0.0/24`)
- Access to GitHub Container Registry (`ghcr.io`)

## One-time setup

```bash
docker network create --subnet=172.50.0.0/24 phpnet
```

## Quick start

Copy `.env.example` to `.env`, adjust the values, then start the stack. See the environment variable reference below.

### docker-compose.yaml

```yaml
services:
  php:
    image: ghcr.io/hansvaneijsden/php-wordpress-base:latest
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    user: root
    environment:
      # Required
      - CONTAINER_NAME=${CONTAINER_NAME}
      - PUID=${PUID}
      - PGID=${PGID}
      - USERNAME=${USERNAME}
      - VOLUME_PREFIX=${VOLUME_PREFIX}

      # PHP
      - TIMEZONE=${TIMEZONE}
      - PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT}
      - PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_FILESIZE}
      - PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE}
      - PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME}
      - PHP_MAX_INPUT_VARS=${PHP_MAX_INPUT_VARS}

      # APCu
      - APC_SHM_SIZE=${APC_SHM_SIZE}

      # OPcache
      - OPCACHE_MEMORY_CONSUMPTION=${OPCACHE_MEMORY_CONSUMPTION}
      - OPCACHE_INTERNED_STRINGS_BUFFER=${OPCACHE_INTERNED_STRINGS_BUFFER}
      - OPCACHE_MAX_ACCELERATED_FILES=${OPCACHE_MAX_ACCELERATED_FILES}
      - OPCACHE_REVALIDATE_FREQ=${OPCACHE_REVALIDATE_FREQ}
      - OPCACHE_VALIDATE_TIMESTAMPS=${OPCACHE_VALIDATE_TIMESTAMPS}

      # Sessions
      - SESSION_SAVE_PATH=/var/lib/php/sessions

      # PHP-FPM pool
      - PM_TYPE=${PM_TYPE}
      - PM_MAX_CHILDREN=${PM_MAX_CHILDREN}
      - PM_START_SERVERS=${PM_START_SERVERS}
      - PM_MIN_SPARE_SERVERS=${PM_MIN_SPARE_SERVERS}
      - PM_MAX_SPARE_SERVERS=${PM_MAX_SPARE_SERVERS}
      - PM_MAX_REQUESTS=${PM_MAX_REQUESTS}

      # SMTP (mail relay)
      - SMTP_HOST=${SMTP_HOST}
      - SMTP_PORT=${SMTP_PORT}
      - SMTP_FROM=${SMTP_FROM}

    volumes:
      - ${WP_PATH}:/var/www/html:rw
      - php-opcache-data:/var/cache/php-opcache
      - php-session-data:/var/lib/php/sessions
      - /run/mysqld:/run/mysqld
      - /run/php:/run/php
      - ${LOG_PATH}:/var/log/php:rw

    networks:
      phpnet:
        ipv4_address: ${CONTAINER_IP}

    healthcheck:
      test: ["CMD-SHELL", "cgi-fcgi -bind -connect /run/php/${CONTAINER_NAME}.sock /ping || kill -s 15 1"]
      interval: 360s
      timeout: 10s
      retries: 3
      start_period: 30s

  wp-cli:
    image: wordpress:cli
    container_name: ${CONTAINER_NAME}-cli
    user: "${PUID}:${PGID}"
    volumes:
      - ${WP_PATH}:/var/www/html
      - /run/php:/run/php
    networks:
      - phpnet
    working_dir: /var/www/html
    environment:
      - HTTP_HOST=${WP_DOMAIN}
      - HTTPS=on
      - REMOTE_ADDR=127.0.0.1
      - SERVER_PORT=443
      - SERVER_NAME=${WP_DOMAIN}
      - SERVER_PROTOCOL=HTTP/2.0
      - REQUEST_METHOD=GET
      - DOCUMENT_ROOT=/var/www/html
    entrypoint: ["wp"]
    profiles:
      - cli

networks:
  phpnet:
    external: true
    name: phpnet

volumes:
  php-opcache-data:
    name: ${VOLUME_PREFIX}-php-opcache
  php-session-data:
    name: ${VOLUME_PREFIX}-php-sessions
```

## Environment variable reference

### Required

| Variable | Description |
|---|---|
| `PUID` | Host user ID to map into the container |
| `PGID` | Host group ID to map into the container |
| `USERNAME` | Username created inside the container |
| `CONTAINER_NAME` | Container name; used for the FPM socket, log files and pool name |
| `VOLUME_PREFIX` | Prefix for the named volumes and the FPM pool name |

### Optional (the image applies a default when unset)

| Variable | Default | Description |
|---|---|---|
| `TIMEZONE` | `Europe/Amsterdam` | PHP timezone |
| `PHP_MEMORY_LIMIT` | `256M` | PHP `memory_limit` |
| `PHP_UPLOAD_MAX_FILESIZE` | `64M` | PHP `upload_max_filesize` |
| `PHP_POST_MAX_SIZE` | `64M` | PHP `post_max_size` |
| `PHP_MAX_EXECUTION_TIME` | `300` | PHP `max_execution_time` (seconds) |
| `PHP_MAX_INPUT_VARS` | `4000` | PHP `max_input_vars` |
| `APC_SHM_SIZE` | `16M` | APCu shared memory size |
| `OPCACHE_MEMORY_CONSUMPTION` | `192` | OPcache memory (MB) |
| `OPCACHE_INTERNED_STRINGS_BUFFER` | `32` | OPcache interned strings buffer (MB) |
| `OPCACHE_MAX_ACCELERATED_FILES` | `10000` | OPcache max accelerated files |
| `OPCACHE_REVALIDATE_FREQ` | `30` | OPcache revalidate frequency (seconds) |
| `OPCACHE_VALIDATE_TIMESTAMPS` | `1` | OPcache validate timestamps |
| `SESSION_SAVE_PATH` | `/var/lib/php/sessions` | PHP session save path |
| `SMTP_HOST` | `127.0.0.1` | msmtp relay host |
| `SMTP_PORT` | `25` | msmtp relay port |
| `SMTP_FROM` | `localhost` | msmtp "From" address |
| `PM_TYPE` | `dynamic` | FPM process manager: `dynamic`, `static` or `ondemand` |
| `PM_MAX_CHILDREN` | `20` | FPM max children |
| `PM_START_SERVERS` | `5` | FPM start servers |
| `PM_MIN_SPARE_SERVERS` | `3` | FPM min spare servers |
| `PM_MAX_SPARE_SERVERS` | `10` | FPM max spare servers |
| `PM_MAX_REQUESTS` | `500` | FPM max requests per child |
| `REQUEST_TERMINATE_TIMEOUT` | `60s` | FPM request terminate timeout |
| `ENABLE_STATUS_ENDPOINTS` | `true` | Write OPcache/APCu status endpoints to `/tmp` |

`CONTAINER_IP`, `WP_PATH`, `WP_DOMAIN` and `LOG_PATH` are used by the compose file (network IP, volumes, the wp-cli service and the log directory); they are not read by the image itself.

## How it works

- **Configuration is rendered at startup.** `docker-entrypoint.sh` uses `envsubst` to render the built-in `*.template` files into the real PHP / FPM / msmtp configuration, substituting the environment variables above.
- **User mapping.** The container runs as `root`; the entrypoint creates a user/group from `PUID`/`PGID` and PHP-FPM drops privileges to that user.
- **Per-container FPM pool.** The pool `[www]` is renamed to `[<VOLUME_PREFIX|CONTAINER_NAME>]` and listens on `/run/php/<CONTAINER_NAME>.sock`.
- **MySQL socket.** The default MySQL socket is set to `/run/mysqld/mysqld.sock` — mount the host socket into the container (see the compose example).
- The entrypoint ignores the container command and always starts `php-fpm` in the foreground.

## Health check & monitoring

- The compose example uses `cgi-fcgi` to hit the FPM ping endpoint: `GET /ping` returns `pong`.
- Optional status endpoints are written to `/tmp/opcache-status.php` and `/tmp/apcu-status.php` (JSON). Disable with `ENABLE_STATUS_ENDPOINTS=false`.

## Optimization per site

| Setting | Small | Medium | Large |
|---|---|---|---|
| `PHP_MEMORY_LIMIT` | `128M` | `256M` | `512M` |
| `PM_MAX_CHILDREN` | `10` | `20` | `40` |
| `OPCACHE_MEMORY_CONSUMPTION` | `96` | `256` | `512` |
| `APC_SHM_SIZE` | `16M` | `32M` | `64M` |

## WP-CLI

WP-CLI is baked into this image at `/usr/local/bin/wp` (pinned version, checksum
verified at build time). Run it inside the **running** site container with
`docker exec`, so it uses the exact same PHP runtime, extensions, database
socket and `wp-config.php` as the site itself:

```bash
# List plugins
docker exec -it -u <USERNAME> <CONTAINER_NAME> wp plugin list

# Optimize the database
docker exec -it -u <USERNAME> <CONTAINER_NAME> wp db optimize

# Flush the cache
docker exec -it -u <USERNAME> <CONTAINER_NAME> wp cache flush
```

For convenience you can install the `wpx <site>` wrapper (resolves the container
and the site user automatically) on the host.

## Maintenance

```bash
# View logs
docker compose logs -f php

# Restart
docker compose restart php

# Update the image
docker compose pull php
docker compose up -d php

# Monitor resource usage
docker stats ${CONTAINER_NAME}
```

## Troubleshooting

### "PUID, PGID, USERNAME, and CONTAINER_NAME are required"

One of the required variables is missing. Make sure it is set in `.env` **and** passed in the `environment:` section of the php service.

### "invalid process manager"

`PM_TYPE` has an invalid value. Use `dynamic`, `static` or `ondemand` (lowercase).

### The container exits immediately

Check the logs: `docker compose logs php` and `docker compose config`. The entrypoint runs `php-fpm -t` at startup and exits non-zero if the generated configuration is invalid.

### Smoke test the image

```bash
docker build -t php-wordpress-base .
docker run -d --name smoke-test \
  -e PUID=1000 -e PGID=1000 -e USERNAME=test -e CONTAINER_NAME=test \
  php-wordpress-base
docker exec smoke-test php -v
docker rm -f smoke-test
```

## Security

- Dangerous PHP functions disabled: `exec, passthru, shell_exec, system, popen, parse_ini_file, show_source`
- `expose_php = Off` — hides the PHP version
- Secure session cookies (`session.cookie_secure`, `session.cookie_httponly`, `session.cookie_samesite = Lax`)
- Strict session mode (`session.use_strict_mode = 1`)
- `display_errors = off` in the FPM pool
- Based on the official PHP images
- Public images are automatically scanned for vulnerabilities by GitHub Container Registry

## Performance

- **OPcache file cache** — compiled scripts cached on disk
- **igbinary serializer** — faster, more compact serialization (APCu, Redis, sessions)
- **APCu object cache** — for WordPress transients (object-cache drop-in)
- **OPcache interned strings** — saves memory for duplicate strings
- **Configurable PHP-FPM pool** — tuned per site

## Contributing

Issues and pull requests are welcome. Please:

1. Build and smoke-test the image locally before opening a PR
2. Do not break the GitHub Actions workflows
3. Keep the image backward compatible — existing deployments pass their own env vars
4. Update the README and `.env.example` when the env-var surface changes

## License

MIT
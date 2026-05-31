# PHP WordPress Base Image

Geoptimaliseerde PHP-FPM image voor WordPress met APCu en OPcache.

## Beschikbare tags

- `latest` - Meest recente stable versie
- `v1.x.x` - Semantische version tags
- `main-abc1234` - Commit SHA tag

## Gebruik in docker-compose.yaml

```yaml
services:
  php:
    image: ghcr.io/jouw-gebruikersnaam/php-wordpress-base:latest
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    user: root
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TIMEZONE=Europe/Amsterdam
      - PHP_MEMORY_LIMIT=256M
      - PHP_UPLOAD_MAX_FILESIZE=64M
      - PHP_POST_MAX_SIZE=64M
      - PHP_MAX_EXECUTION_TIME=300
      - PHP_MAX_INPUT_VARS=4000
      - APC_SHM_SIZE=32M
      - OPCACHE_MEMORY_CONSUMPTION=348
      - OPCACHE_INTERNED_STRINGS_BUFFER=32
      - OPCACHE_MAX_ACCELERATED_FILES=10000
      - PM_TYPE=dynamic
      - PM_MAX_CHILDREN=20
      - PM_START_SERVERS=5
      - PM_MIN_SPARE_SERVERS=3
      - PM_MAX_SPARE_SERVERS=10
      - SMTP_HOST=127.0.0.1
      - SMTP_PORT=25
      - SMTP_FROM=localhost
    volumes:
      - ${WP_PATH}:/var/www/html:rw
      - php-opcache-data:/var/cache/php-opcache
      - php-session-data:/var/lib/php/sessions
    networks:
      phpnet:
        ipv4_address: ${CONTAINER_IP}
# PHP WordPress Base Image

Een geoptimaliseerde PHP-FPM 8.5 Docker image speciaal voor WordPress, met APCu, OPcache, en automatische gebruikersrechten.

## Kenmerken

- PHP 8.5 FPM - Gebaseerd op Debian 13 (Trixie)
- Geoptimaliseerd voor WordPress - Specifieke PHP settings voor verbeterde performance
- APCu voor Object Cache - Met igbinary serializer voor snellere caching
- OPcache - Met file cache voor betere performance na start
- Automatische gebruikersrechten - Draait met dezelfde PUID/PGID als de host
- Per-site configuratie - Elke WordPress installatie kan eigen resources krijgen
- MSMTP ingebouwd - Mail verzenden via host SMTP
- Beveiligd - Gevaarlijke PHP functies uitgeschakeld
- Multi-site ready - Werkt met WordPress Multisite installaties

## Beschikbare tags

| Tag | Beschrijving | Wanneer gebruiken |
|-----|--------------|-------------------|
| latest | Meest recente stable versie | Productie omgevingen |
| v1.0.0 | Semantische version tags | Specifieke versie vastzetten |
| main-abc1234 | Commit SHA tag | Debugging / testen |

## Vereisten

- Docker 20.10+ en Docker Compose 2.0+
- Een bestaand Docker netwerk: phpnet met subnet 172.50.0.0/24
- Toegang tot GitHub Container Registry (ghcr.io)

## Eénmalige setup

### Maak het Docker netwerk aan

docker network create --subnet=172.50.0.0/24 phpnet

## Gebruik

### Basis docker-compose.yaml

```
services:
  php:
    image: ghcr.io/hansvaneijsden/php-wordpress-base:latest
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    user: root
    environment:
      # Gebruiker instellingen (verplicht!)
      - PUID=${PUID}
      - PGID=${PGID}
      - USERNAME=${USERNAME}
      
      # PHP instellingen
      - TIMEZONE=${TIMEZONE:-Europe/Amsterdam}
      - PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-256M}
      - PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_FILESIZE:-64M}
      - PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE:-64M}
      - PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME:-300}
      - PHP_MAX_INPUT_VARS=${PHP_MAX_INPUT_VARS:-4000}
      
      # APCu instellingen
      - APC_SHM_SIZE=${APC_SHM_SIZE:-32M}
      
      # OPcache instellingen
      - OPCACHE_MEMORY_CONSUMPTION=${OPCACHE_MEMORY_CONSUMPTION:-348}
      - OPCACHE_INTERNED_STRINGS_BUFFER=${OPCACHE_INTERNED_STRINGS_BUFFER:-32}
      - OPCACHE_MAX_ACCELERATED_FILES=${OPCACHE_MAX_ACCELERATED_FILES:-10000}
      
      # Session instellingen
      - SESSION_SAVE_PATH=/var/lib/php/sessions
      
      # PHP-FPM pool instellingen
      - PM_TYPE=${PM_TYPE:-dynamic}
      - PM_MAX_CHILDREN=${PM_MAX_CHILDREN:-20}
      - PM_START_SERVERS=${PM_START_SERVERS:-5}
      - PM_MIN_SPARE_SERVERS=${PM_MIN_SPARE_SERVERS:-3}
      - PM_MAX_SPARE_SERVERS=${PM_MAX_SPARE_SERVERS:-10}
      
      # SMTP instellingen
      - SMTP_HOST=${SMTP_HOST:-127.0.0.1}
      - SMTP_PORT=${SMTP_PORT:-25}
      - SMTP_FROM=${SMTP_FROM:-localhost}
    
    volumes:
      - ${WP_PATH}:/var/www/html:rw
      - php-opcache-data:/var/cache/php-opcache
      - php-session-data:/var/lib/php/sessions
    
    networks:
      phpnet:
        ipv4_address: ${CONTAINER_IP}

  wp-cli:
    image: wordpress:cli
    container_name: ${CONTAINER_NAME}-cli
    user: "${PUID}:${PGID}"
    volumes:
      - ${WP_PATH}:/var/www/html
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

### Voorbeeld .env bestand

```
# Container instellingen
CONTAINER_NAME=my-website-php
VOLUME_PREFIX=my-website
CONTAINER_IP=172.50.0.10

# Gebruiker instellingen (verplicht!)
PUID=1001
PGID=1001
USERNAME=gebruiker

# WordPress domein
WP_DOMAIN=example.com
WP_PATH=/var/www/example.com/public

# PHP resource instellingen
PHP_MEMORY_LIMIT=256M
PHP_UPLOAD_MAX_FILESIZE=64M
PHP_POST_MAX_SIZE=64M
PHP_MAX_EXECUTION_TIME=300
PHP_MAX_INPUT_VARS=4000

# APC instellingen
APC_SHM_SIZE=32M

# OPcache instellingen
OPCACHE_MEMORY_CONSUMPTION=348
OPCACHE_INTERNED_STRINGS_BUFFER=32
OPCACHE_MAX_ACCELERATED_FILES=10000

# PHP-FPM pool instellingen
PM_TYPE=dynamic
PM_MAX_CHILDREN=20
PM_START_SERVERS=5
PM_MIN_SPARE_SERVERS=3
PM_MAX_SPARE_SERVERS=10

# SMTP instellingen
SMTP_HOST=127.0.0.1
SMTP_PORT=25
SMTP_FROM=localhost
```

## Optimalisatie per WordPress installatie

### Kleine website

PHP_MEMORY_LIMIT=128M
PM_MAX_CHILDREN=10
OPCACHE_MEMORY_CONSUMPTION=96
APC_SHM_SIZE=16M

### Gemiddelde website

PHP_MEMORY_LIMIT=256M
PM_MAX_CHILDREN=20
OPCACHE_MEMORY_CONSUMPTION=256
APC_SHM_SIZE=32M

### Grote website

PHP_MEMORY_LIMIT=512M
PM_MAX_CHILDREN=40
OPCACHE_MEMORY_CONSUMPTION=512
APC_SHM_SIZE=64M

## Beheer met WP-CLI

# WordPress installatie
docker compose run --rm wp-cli core install --url=example.com --title="My Website" --admin_user=admin --admin_password=securepass --admin_email=admin@example.com

# Plugins lijst
docker compose run --rm wp-cli plugin list

# Database optimalisatie
docker compose run --rm wp-cli db optimize

# Cache clearen
docker compose run --rm wp-cli cache flush

## Onderhoud

### Container logs bekijken
docker compose logs -f php

### Container herstarten
docker compose restart php

### Image updaten naar nieuwste versie
docker compose pull php
docker compose up -d php

### Resource usage monitoren
docker stats ${CONTAINER_NAME}

## Troubleshooting

### Fout: "PUID, PGID, and USERNAME environment variables are required"

Oorzaak: Environment variabelen niet correct doorgegeven.
Oplossing: Controleer of .env bestand bestaat en variabelen bevat.

### Fout: "invalid process manager"

Oorzaak: PM_TYPE heeft een ongeldige waarde.
Oplossing: Gebruik dynamic, static of ondemand (kleine letters).

### Fout: "unable to parse value for entry 'pm'"

Oorzaak: De PM_TYPE variabele is niet vervangen.
Oplossing: Zorg dat PM_TYPE in de environment sectie staat.

### Container start niet op

docker compose logs php
docker compose config

docker run --rm -e PUID=1000 -e PGID=1000 -e USERNAME=test ghcr.io/hansvaneijsden/php-wordpress-base:latest php -v

## Beveiliging

Deze image heeft de volgende beveiligingsmaatregelen:

- Gevaarlijke PHP functies uitgeschakeld (exec, shell_exec, etc.)
- expose_php = Off - Verbergt PHP versie informatie
- Secure session cookies (session.cookie_secure = 1)
- Strict session mode (session.use_strict_mode = 1)
- Wekelijkse security scans met Trivy
- Gebaseerd op officiële PHP images

## Performance optimalisaties

De image bevat:

- OPcache file cache - Gecached scripts opslaan op disk
- Igbinary serializer - Snellere en compactere serialization
- APCu object cache - Voor WordPress transients via SQLite Object Cache plugin
- OPcache interned strings - Bespaart geheugen voor duplicate strings
- PHP-FPM static/dynamic pool - Aanpasbaar per website

## Contribueren

Issues en pull requests zijn welkom! Zorg dat je:

1. De Dockerfile lokaal test
2. De GitHub Actions workflow niet breekt
3. De README update indien nodig

## Changelog

### v1.0.0 (2026-05-31)

- Eerste stabiele release
- PHP 8.5 FPM basis
- APCu en OPcache optimalisaties
- Automatische gebruikersrechten
- MSMTP integratie voor mail

## Licentie

MIT License - Vrij te gebruiken en aan te passen.

## Credits

- PHP Docker official images
- WordPress Docker Hub
- Trivy security scanner

## Snelle start voor een nieuwe WordPress site

# 1. Clone de repository template
git clone https://github.com/HansVanEijsden/php-wordpress-base.git my-site
cd my-site

# 2. Kopieer en pas .env aan
cp .env.example .env
nano .env

# 3. Start de container
docker compose up -d

# 4. Installeer WordPress
docker compose run --rm wp-cli core download
docker compose run --rm wp-cli config create --dbname=wordpress --dbuser=root --dbpass=password --dbhost=mariadb
docker compose run --rm wp-cli core install --url=example.com --title="My Site" --admin_user=admin --admin_password=secure --admin_email=admin@example.com

# 5. Bezoek je website, zodra je je frontend via FastCGI hebt geconfigureerd!

Tip: Voor productieomgevingen wordt aangeraden om een specifieke versie tag te gebruiken in plaats van latest, bijvoorbeeld v1.0.0.

Bug gevonden? Open een issue op GitHub
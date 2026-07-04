#!/bin/bash
set -e

# Controleer of envsubst beschikbaar is
if ! command -v envsubst &> /dev/null; then
    echo "ERROR: envsubst command not found. Please install gettext package."
    exit 1
fi

# Verplichte environment variabelen check
if [ -z "${PUID}" ] || [ -z "${PGID}" ] || [ -z "${USERNAME}" ] || [ -z "${CONTAINER_NAME}" ]; then
    echo "ERROR: PUID, PGID, USERNAME, and CONTAINER_NAME are required"
    exit 1
fi

# Check of essentiële PHP configuratie variabelen bestaan
REQUIRED_VARS=(
    "TIMEZONE"
    "PHP_MEMORY_LIMIT"
    "PHP_UPLOAD_MAX_FILESIZE"
    "PHP_POST_MAX_SIZE"
    "PHP_MAX_EXECUTION_TIME"
    "PHP_MAX_INPUT_VARS"
    "APC_SHM_SIZE"
    "OPCACHE_MEMORY_CONSUMPTION"
    "OPCACHE_INTERNED_STRINGS_BUFFER"
    "OPCACHE_MAX_ACCELERATED_FILES"
    "SESSION_SAVE_PATH"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "WARNING: The following required variables are not set, using empty values in config:"
    printf '  - %s\n' "${MISSING_VARS[@]}"
fi

# Gebruiker aanmaken
if ! id -u "${USERNAME}" > /dev/null 2>&1; then
    echo "Creating user ${USERNAME} with PUID: ${PUID}, PGID: ${PGID}"
    groupadd -g "${PGID}" "${USERNAME}"
    useradd -u "${PUID}" -g "${USERNAME}" -m -s /bin/bash "${USERNAME}"
    usermod -a -G www-data "${USERNAME}"
else
    echo "User ${USERNAME} already exists"
    usermod -a -G www-data "${USERNAME}"
fi

# Directories voorbereiden
mkdir -p /var/log/php /var/cache/php-opcache /var/lib/php/sessions /run/php
chown -R "${USERNAME}":${USERNAME} /var/log/php /var/cache/php-opcache /var/lib/php/sessions /run/php
chmod 755 /var/log/php /var/cache/php-opcache /var/lib/php/sessions /run/php

# PHP configuratie genereren
echo "Generating PHP configuration..."
envsubst < /usr/local/etc/php/conf.d/wordpress.template > /usr/local/etc/php/conf.d/wordpress.ini
envsubst < /usr/local/etc/php/conf.d/apcu.template > /usr/local/etc/php/conf.d/apcu.ini
envsubst < /usr/local/etc/php/conf.d/opcache.template > /usr/local/etc/php/conf.d/opcache.ini
envsubst < /usr/local/etc/php/conf.d/session.template > /usr/local/etc/php/conf.d/session.ini
envsubst < /usr/local/etc/php/conf.d/mail.template > /usr/local/etc/php/conf.d/mail.ini

# MySQL socket configuratie
cat > /usr/local/etc/php/conf.d/mysql-socket.ini <<EOF
mysql.default_socket = /run/mysqld/mysqld.sock
mysqli.default_socket = /run/mysqld/mysqld.sock
pdo_mysql.default_socket = /run/mysqld/mysqld.sock
EOF

# Standaardwaarden mailconfiguratie wanneer niet ingegeven
SMTP_HOST="${SMTP_HOST:-127.0.0.1}"
SMTP_PORT="${SMTP_PORT:-25}"
SMTP_FROM="${SMTP_FROM:-localhost}"

# msmtp configuratie genereren
echo "Generating msmtp configuration..."
envsubst < /etc/msmtp.template > /etc/msmtprc

# Pool naam bepalen
POOL_NAME="${VOLUME_PREFIX:-${CONTAINER_NAME}}"
echo "Configuring PHP-FPM pool: ${POOL_NAME}"

# Pas bestaande configuraties aan naar de juiste pool naam
sed -i "s/\[www\]/[${POOL_NAME}]/g" /usr/local/etc/php-fpm.d/docker.conf
sed -i "s/\[www\]/[${POOL_NAME}]/g" /usr/local/etc/php-fpm.d/zz-docker.conf

# Overschrijf www.conf met volledige configuratie
cat > /usr/local/etc/php-fpm.d/www.conf <<EOF
[${POOL_NAME}]

user = ${USERNAME}
group = ${USERNAME}

listen = /run/php/${CONTAINER_NAME}.sock
listen.owner = ${USERNAME}
listen.group = ${USERNAME}
listen.mode = 0660

pm = ${PM_TYPE:-dynamic}
pm.max_children = ${PM_MAX_CHILDREN:-20}
pm.start_servers = ${PM_START_SERVERS:-5}
pm.min_spare_servers = ${PM_MIN_SPARE_SERVERS:-3}
pm.max_spare_servers = ${PM_MAX_SPARE_SERVERS:-10}
pm.max_requests = ${PM_MAX_REQUESTS:-500}

request_terminate_timeout = ${REQUEST_TERMINATE_TIMEOUT:-60s}
catch_workers_output = yes

ping.path = /ping
ping.response = pong

security.limit_extensions = .php

; Error logging - using CONTAINER_NAME for unique log files per container
php_admin_value[error_log] = /var/log/php/${CONTAINER_NAME}-error.log
php_admin_flag[log_errors] = on
php_admin_flag[display_errors] = off

env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
EOF

# Debug info
echo "PHP-FPM pool: ${POOL_NAME}"
echo "Socket: /run/php/${CONTAINER_NAME}.sock"
echo "Error log: /var/log/php/${CONTAINER_NAME}-error.log"

# Toon OPcache revalidate frequentie
echo "OPcache revalidate_freq: ${OPCACHE_REVALIDATE_FREQ:-30} seconds"

# Validatie
echo "Validating PHP-FPM configuration..."
php-fpm -t
if [ $? -ne 0 ]; then
    echo "ERROR: PHP-FPM configuration validation failed!"
    exit 1
fi

# Status scripts voor monitoring (optioneel)
if [ "${ENABLE_STATUS_ENDPOINTS:-true}" = "true" ]; then
    echo "Creating status endpoints..."
    cat > /tmp/opcache-status.php <<'EOF'
<?php
header('Content-Type: application/json');
echo json_encode(opcache_get_status(false));
EOF
    
    cat > /tmp/apcu-status.php <<'EOF'
<?php
header('Content-Type: application/json');
echo json_encode(apcu_sma_info(true));
EOF
    
    chmod 644 /tmp/opcache-status.php /tmp/apcu-status.php
    echo "Status endpoints created in /tmp/"
else
    echo "Status endpoints disabled"
fi

# Start PHP-FPM
echo "Starting PHP-FPM as user: ${USERNAME}"
exec php-fpm --nodaemonize --allow-to-run-as-root
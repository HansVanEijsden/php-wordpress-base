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
mkdir -p /var/cache/php-opcache /var/lib/php/sessions /run/php
chown -R "${USERNAME}":${USERNAME} /var/cache/php-opcache /var/lib/php/sessions /run/php
chmod 755 /var/cache/php-opcache /var/lib/php/sessions /run/php

# PHP configuratie genereren
echo "Generating PHP configuration..."
envsubst < /usr/local/etc/php/conf.d/wordpress.template > /usr/local/etc/php/conf.d/wordpress.ini
envsubst < /usr/local/etc/php/conf.d/apcu.template > /usr/local/etc/php/conf.d/apcu.ini
envsubst < /usr/local/etc/php/conf.d/opcache.template > /usr/local/etc/php/conf.d/opcache.ini
envsubst < /usr/local/etc/php/conf.d/session.template > /usr/local/etc/php/conf.d/session.ini
envsubst < /usr/local/etc/php/conf.d/mail.template > /usr/local/etc/php/conf.d/mail.ini

# MySQL socket configuratie (zodat 'localhost' werkt)
cat > /usr/local/etc/php/conf.d/mysql-socket.ini <<EOF
; Default MySQL socket pad voor WordPress
mysql.default_socket = /run/mysqld/mysqld.sock
mysqli.default_socket = /run/mysqld/mysqld.sock
pdo_mysql.default_socket = /run/mysqld/mysqld.sock
EOF

# msmtp configuratie
cat > /etc/msmtprc <<EOF
account default
host ${SMTP_HOST:-127.0.0.1}
port ${SMTP_PORT:-25}
from ${SMTP_FROM:-localhost}
auth off
tls off
syslog LOG_MAIL
EOF

# PHP-FPM configuratie
cat > /usr/local/etc/php-fpm.d/www.conf <<EOF
[www]

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
pm.max_requests = 500

request_terminate_timeout = 60s
catch_workers_output = yes

ping.path = /ping
ping.response = pong

slowlog = /var/log/php-fpm-slow.log
request_slowlog_timeout = 10s

security.limit_extensions = .php

env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
EOF

# Validatie
echo "Validating PHP-FPM configuration..."
php-fpm -t
if [ $? -ne 0 ]; then
    echo "ERROR: PHP-FPM configuration validation failed!"
    exit 1
fi

# Start PHP-FPM
echo "Starting PHP-FPM as user: ${USERNAME}"
echo "Socket: /run/php/${CONTAINER_NAME}.sock"
echo "MySQL socket: /run/mysqld/mysqld.sock"
exec php-fpm --nodaemonize --allow-to-run-as-root
#!/bin/bash
set -e

# Controleer of envsubst beschikbaar is
if ! command -v envsubst &> /dev/null; then
    echo "ERROR: envsubst command not found. Please install gettext package."
    exit 1
fi

# Verplichte environment variabelen check
if [ -z "${PUID}" ] || [ -z "${PGID}" ] || [ -z "${USERNAME}" ] || [ -z "${CONTAINER_NAME}" ]; then
    echo "ERROR: PUID, PGID, USERNAME, and CONTAINER_NAME environment variables are required"
    echo "Current values:"
    echo "  PUID='${PUID}'"
    echo "  PGID='${PGID}'"
    echo "  USERNAME='${USERNAME}'"
    echo "  CONTAINER_NAME='${CONTAINER_NAME}'"
    exit 1
fi

# Gebruiker aanmaken op basis van PUID/PGID en USERNAME
if ! id -u "${USERNAME}" > /dev/null 2>&1; then
    echo "Creating user ${USERNAME} with PUID: ${PUID}, PGID: ${PGID}"
    groupadd -g "${PGID}" "${USERNAME}"
    useradd -u "${PUID}" -g "${USERNAME}" -m -s /bin/bash "${USERNAME}"
    usermod -a -G www-data "${USERNAME}"
else
    echo "User ${USERNAME} already exists with PUID $(id -u ${USERNAME})"
    usermod -a -G www-data "${USERNAME}"
fi

# Zet juiste eigenaren op directories
echo "Setting permissions for cache and session directories..."
mkdir -p /var/cache/php-opcache /var/lib/php/sessions /run/php
chown -R "${USERNAME}":${USERNAME} /var/cache/php-opcache /var/lib/php/sessions /run/php
chmod 755 /var/cache/php-opcache /var/lib/php/sessions /run/php

# Genereer PHP configuratie uit templates
echo "Generating PHP configuration from templates..."
envsubst < /usr/local/etc/php/conf.d/wordpress.template > /usr/local/etc/php/conf.d/wordpress.ini
envsubst < /usr/local/etc/php/conf.d/apcu.template > /usr/local/etc/php/conf.d/apcu.ini
envsubst < /usr/local/etc/php/conf.d/opcache.template > /usr/local/etc/php/conf.d/opcache.ini
envsubst < /usr/local/etc/php/conf.d/session.template > /usr/local/etc/php/conf.d/session.ini
envsubst < /usr/local/etc/php/conf.d/mail.template > /usr/local/etc/php/conf.d/mail.ini

# Genereer msmtp configuratie
echo "Generating msmtp configuration..."
cat > /etc/msmtprc <<EOF
account default
host ${SMTP_HOST:-127.0.0.1}
port ${SMTP_PORT:-25}
from ${SMTP_FROM:-localhost}
auth off
tls off
syslog LOG_MAIL
EOF

# EERST environment vars vervangen in FPM config
echo "Processing PHP-FPM pool configuration..."

# Vervang eerst alle ${VAR} placeholders
envsubst < /usr/local/etc/php-fpm.d/www.conf > /usr/local/etc/php-fpm.d/www.conf.envsubst

# Vervang daarna de PM_TYPE_PLACEHOLDER
PM_TYPE_CLEAN=$(echo "${PM_TYPE:-dynamic}" | tr -d ' ')
sed -i "s/PM_TYPE_PLACEHOLDER/${PM_TYPE_CLEAN}/g" /usr/local/etc/php-fpm.d/www.conf.envsubst

# Vervang de originele config met de bewerkte versie
mv /usr/local/etc/php-fpm.d/www.conf.envsubst /usr/local/etc/php-fpm.d/www.conf

# Toon de gegenereerde configuratie voor debugging
echo "PM_TYPE set to: ${PM_TYPE_CLEAN}"
echo "FPM user/group settings:"
grep "^user = " /usr/local/etc/php-fpm.d/www.conf
grep "^group = " /usr/local/etc/php-fpm.d/www.conf
echo "FPM listen socket:"
grep "^listen = " /usr/local/etc/php-fpm.d/www.conf

# Toon welke configuratie is gegenereerd
echo "Generated PHP configuration files:"
ls -la /usr/local/etc/php/conf.d/*.ini

# Valideer de FPM configuratie voor we starten
echo "Validating PHP-FPM configuration..."
php-fpm -t
if [ $? -ne 0 ]; then
    echo "ERROR: PHP-FPM configuration validation failed!"
    echo "Check /usr/local/etc/php-fpm.d/www.conf for errors"
    cat /usr/local/etc/php-fpm.d/www.conf
    exit 1
fi

# Start PHP-FPM
echo "Starting PHP-FPM as user: ${USERNAME}"
echo "Socket will be created at: /run/php/${CONTAINER_NAME}.sock"

exec "$@" --allow-to-run-as-root
#!/bin/bash
set -e

# Controleer of envsubst beschikbaar is
if ! command -v envsubst &> /dev/null; then
    echo "ERROR: envsubst command not found. Please install gettext package."
    exit 1
fi

# Gebruiker aanmaken op basis van PUID/PGID
if ! id -u "${PUID}" > /dev/null 2>&1; then
    echo "Creating user with PUID: ${PUID}, PGID: ${PGID}"
    groupadd -g "${PGID}" "wpuser"
    useradd -u "${PUID}" -g "wpuser" -m -s /bin/bash "wpuser"
    usermod -a -G www-data "wpuser"
    USERNAME="wpuser"
else
    USERNAME=$(id -nu "${PUID}")
    echo "User ${USERNAME} already exists with PUID ${PUID}"
    # Zorg dat de gebruiker in www-data groep zit
    usermod -a -G www-data "${USERNAME}"
fi

# Zet juiste eigenaren op directories
echo "Setting permissions for cache and session directories..."
chown -R "${USERNAME}":www-data /var/cache/php-opcache /var/lib/php/sessions
chmod 755 /var/cache/php-opcache /var/lib/php/sessions

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

# Vervang environment vars in FPM config
echo "Processing PHP-FPM pool configuration..."
envsubst < /usr/local/etc/php-fpm.d/www.conf > /usr/local/etc/php-fpm.d/www.conf.tmp
mv /usr/local/etc/php-fpm.d/www.conf.tmp /usr/local/etc/php-fpm.d/www.conf

# Toon welke configuratie is gegenereerd (voor debugging)
echo "Generated PHP configuration files:"
ls -la /usr/local/etc/php/conf.d/*.ini

# Start PHP-FPM als de juiste gebruiker
echo "Starting PHP-FPM as user: ${USERNAME}"
exec "$@" --allow-to-run-as-root
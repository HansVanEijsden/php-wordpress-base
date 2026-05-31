#!/bin/bash
set -e

# Gebruiker aanmaken op basis van PUID/PGID
if ! id -u "${PUID}" > /dev/null 2>&1; then
    groupadd -g "${PGID}" "wpuser"
    useradd -u "${PUID}" -g "wpuser" -m -s /bin/bash "wpuser"
    usermod -a -G www-data "wpuser"
    USERNAME="wpuser"
else
    USERNAME=$(id -nu "${PUID}")
    # Zorg dat de gebruiker in www-data groep zit
    usermod -a -G www-data "${USERNAME}"
fi

# Zet juiste eigenaren op directories
chown -R "${USERNAME}":www-data /var/cache/php-opcache /var/lib/php/sessions
chmod 755 /var/cache/php-opcache /var/lib/php/sessions

# Genereer PHP configuratie uit templates
envsubst < /usr/local/etc/php/conf.d/wordpress.template > /usr/local/etc/php/conf.d/wordpress.ini
envsubst < /usr/local/etc/php/conf.d/apcu.template > /usr/local/etc/php/conf.d/apcu.ini
envsubst < /usr/local/etc/php/conf.d/opcache.template > /usr/local/etc/php/conf.d/opcache.ini
envsubst < /usr/local/etc/php/conf.d/session.template > /usr/local/etc/php/conf.d/session.ini
envsubst < /usr/local/etc/php/conf.d/mail.template > /usr/local/etc/php/conf.d/mail.ini

# Genereer msmtp configuratie
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
envsubst < /usr/local/etc/php-fpm.d/www.conf > /usr/local/etc/php-fpm.d/www.conf.tmp
mv /usr/local/etc/php-fpm.d/www.conf.tmp /usr/local/etc/php-fpm.d/www.conf

# Start PHP-FPM als de juiste gebruiker
exec "$@" --allow-to-run-as-root
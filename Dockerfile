# Use the official PHP 8.5 FPM image on Debian 13 (Trixie)
FROM php:8.5.9-fpm

# Build metadata for GitHub Container Registry
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.opencontainers.image.created=$BUILD_DATE \
    org.opencontainers.image.title="PHP WordPress Base" \
    org.opencontainers.image.description="Optimized PHP-FPM image for WordPress" \
    org.opencontainers.image.version=$VERSION \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.source="https://github.com/hansvaneijsden/php-wordpress-base"

# --- Step 1: System dependencies ---
RUN apt-get update && apt-get install -y \
    libmagickwand-dev \
    libzip-dev \
    libicu-dev \
    libxml2-dev \
    libssl-dev \
    msmtp \
    msmtp-mta \
    gettext \
    default-mysql-client \
    fcgiwrap \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    mysqli \
    pdo_mysql \
    exif \
    gd \
    intl \
    zip \
    bcmath \
    soap \
    && pecl install igbinary \
    && pecl install --configureoptions 'with-igbinary="yes"' apcu \
    && pecl install imagick \
    && pecl install --configureoptions 'enable-redis-igbinary="yes"' redis \
    && docker-php-ext-enable igbinary apcu imagick redis \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# --- Step 2: PHP configuration templates ---
RUN { \
    echo 'date.timezone = ${TIMEZONE}'; \
    echo 'memory_limit = ${PHP_MEMORY_LIMIT}'; \
    echo 'upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}'; \
    echo 'post_max_size = ${PHP_POST_MAX_SIZE}'; \
    echo 'max_execution_time = ${PHP_MAX_EXECUTION_TIME}'; \
    echo 'max_input_vars = ${PHP_MAX_INPUT_VARS}'; \
    echo 'expose_php = Off'; \
    echo 'disable_functions = exec,passthru,shell_exec,system,popen,parse_ini_file,show_source'; \
    } > /usr/local/etc/php/conf.d/wordpress.template

RUN { \
    echo 'apc.enabled = 1'; \
    echo 'apc.shm_size = ${APC_SHM_SIZE}'; \
    echo 'apc.serializer = igbinary'; \
    echo 'apc.slam_defense = 1'; \
    } > /usr/local/etc/php/conf.d/apcu.template

# OPcache template (defaults are applied in docker-entrypoint.sh before envsubst)
RUN { \
    echo 'opcache.enable = 1'; \
    echo 'opcache.enable_cli = 0'; \
    echo 'opcache.memory_consumption = ${OPCACHE_MEMORY_CONSUMPTION}'; \
    echo 'opcache.interned_strings_buffer = ${OPCACHE_INTERNED_STRINGS_BUFFER}'; \
    echo 'opcache.max_accelerated_files = ${OPCACHE_MAX_ACCELERATED_FILES}'; \
    echo 'opcache.revalidate_freq = ${OPCACHE_REVALIDATE_FREQ}'; \
    echo 'opcache.validate_timestamps = ${OPCACHE_VALIDATE_TIMESTAMPS}'; \
    echo 'opcache.file_cache = /var/cache/php-opcache'; \
    } > /usr/local/etc/php/conf.d/opcache.template

RUN { \
    echo 'session.save_handler = files'; \
    echo 'session.save_path = ${SESSION_SAVE_PATH}'; \
    echo 'session.cookie_secure = 1'; \
    echo 'session.use_strict_mode = 1'; \
    echo 'session.cookie_httponly = 1'; \
    echo 'session.cookie_samesite = "Lax"'; \
    echo 'session.serialize_handler = igbinary'; \
    } > /usr/local/etc/php/conf.d/session.template

RUN { \
    echo 'mail.add_x_header = On'; \
    echo 'sendmail_path = /usr/bin/msmtp -t'; \
    } > /usr/local/etc/php/conf.d/mail.template

# --- Step 3: msmtp configuration template ---
RUN { \
    echo 'account default'; \
    echo 'host $SMTP_HOST'; \
    echo 'port $SMTP_PORT'; \
    echo 'from $SMTP_FROM'; \
    echo 'auth off'; \
    echo 'tls off'; \
    echo 'syslog LOG_MAIL'; \
    } > /etc/msmtp.template

# --- Step 4: Directories for cache, sessions and logs ---
RUN mkdir -p /var/log/php /var/cache/php-opcache /var/lib/php/sessions /run/php && \
    chmod 755 /var/cache/php-opcache /var/lib/php/sessions /run/php /var/log/php

# --- Step 5: WP-CLI (pinned version, checksum verified) ---
ARG WP_CLI_VERSION=2.11.0
ARG WP_CLI_SHA512=adb12146bab8d829621efed41124dcd0012f9027f47e0228be7080296167566070e4a026a09c3989907840b21de94b7a35f3bfbd5f827c12f27c5803546d1bba
RUN curl -fsSL "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" -o /usr/local/bin/wp \
    && echo "${WP_CLI_SHA512}  /usr/local/bin/wp" | sha512sum -c - \
    && chmod +x /usr/local/bin/wp \
    && wp --info --allow-root

# --- Step 6: Entrypoint script ---
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
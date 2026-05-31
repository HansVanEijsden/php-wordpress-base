# Gebruik officiële PHP 8.5 FPM met Debian 13 (Trixie) basis
FROM php:8.5-fpm

# Build metadata voor GitHub Container Registry
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.title="PHP WordPress Base" \
      org.opencontainers.image.description="Optimized PHP-FPM image for WordPress" \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.source="https://github.com/hansvaneijsden/php-wordpress-base"

# --- Stap 1: Systeem dependencies ---
RUN apt-get update && apt-get install -y \
    libmagickwand-dev \
    libzip-dev \
    libicu-dev \
    libxml2-dev \
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
    && docker-php-ext-enable igbinary apcu imagick \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# --- Stap 2: PHP configuratie templates ---
RUN { \
        echo 'date.timezone = ${TIMEZONE}'; \
        echo 'memory_limit = ${PHP_MEMORY_LIMIT}'; \
        echo 'upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}'; \
        echo 'post_max_size = ${PHP_POST_MAX_SIZE}'; \
        echo 'max_execution_time = ${PHP_MAX_EXECUTION_TIME}'; \
        echo 'max_input_vars = ${PHP_MAX_INPUT_VARS}'; \
        echo 'expose_php = Off'; \
        echo 'disable_functions = exec,passthru,shell_exec,system,proc_open,popen,parse_ini_file,show_source'; \
    } > /usr/local/etc/php/conf.d/wordpress.template

RUN { \
        echo 'apc.enabled = 1'; \
        echo 'apc.shm_size = ${APC_SHM_SIZE}'; \
        echo 'apc.serializer = igbinary'; \
    } > /usr/local/etc/php/conf.d/apcu.template

RUN { \
        echo 'opcache.enable = 1'; \
        echo 'opcache.enable_cli = 1'; \
        echo 'opcache.memory_consumption = ${OPCACHE_MEMORY_CONSUMPTION}'; \
        echo 'opcache.interned_strings_buffer = ${OPCACHE_INTERNED_STRINGS_BUFFER}'; \
        echo 'opcache.max_accelerated_files = ${OPCACHE_MAX_ACCELERATED_FILES}'; \
        echo 'opcache.revalidate_freq = 2'; \
        echo 'opcache.validate_timestamps = 1'; \
        echo 'opcache.file_cache = /var/cache/php-opcache'; \
        echo 'opcache.file_cache_only = 0'; \
    } > /usr/local/etc/php/conf.d/opcache.template

RUN { \
        echo 'session.save_handler = files'; \
        echo 'session.save_path = ${SESSION_SAVE_PATH}'; \
        echo 'session.cookie_secure = 1'; \
        echo 'session.use_strict_mode = 1'; \
        echo 'session.serialize_handler = igbinary'; \
    } > /usr/local/etc/php/conf.d/session.template

RUN { \
        echo 'mail.add_x_header = On'; \
        echo 'sendmail_path = /usr/bin/msmtp -t'; \
    } > /usr/local/etc/php/conf.d/mail.template

# --- Stap 3: Directories voor cache en sessions ---
RUN mkdir -p /var/cache/php-opcache /var/lib/php/sessions /run/php && \
    chmod 755 /var/cache/php-opcache /var/lib/php/sessions /run/php

# --- Stap 4: Entrypoint script ---
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
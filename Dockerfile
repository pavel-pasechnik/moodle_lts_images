# syntax=docker/dockerfile:1.6

ARG PHP_VERSION=8.2
FROM php:${PHP_VERSION}-apache

ARG PHP_VERSION
ARG MOODLE_VERSION=v5.1.0
ARG DOCUMENT_ROOT=/var/www/moodle/public
ARG APACHE_CONF=apache-5.x.conf
ARG MOODLE_GIT_REPO=https://github.com/moodle/moodle.git

ENV MOODLE_APP_DIR=/var/www/moodle \
    DOCUMENT_ROOT=${DOCUMENT_ROOT} \
    MOODLE_VERSION=${MOODLE_VERSION} \
    REDIS_HOST=redis \
    REDIS_PORT=6379 \
    REDIS_DB=0 \
    REDIS_TIMEOUT=2.5 \
    REDIS_READ_TIMEOUT=2.5 \
    REDIS_PASSWORD="" \
    REDIS_SESSION_LOCKING=1 \
    REDIS_SESSION_LOCK_RETRIES=200 \
    REDIS_SESSION_LOCK_WAIT=20000 \
    REDIS_PCONNECT_POOLING=1 \
    ENABLE_REDIS_SESSION=1

LABEL org.opencontainers.image.title="Moodle LTS image" \
      org.opencontainers.image.version="${MOODLE_VERSION}" \
      org.opencontainers.image.description="Production-ready Moodle LTS image with Apache, tuned Redis integration, Elasticsearch driver, and PostgreSQL/MySQL/MariaDB clients." \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Enable Apache modules required by Moodle and disable sendfile/mmap per Moodle docs
RUN a2enmod rewrite headers ssl deflate expires \
 && printf "EnableSendfile Off\nEnableMMAP Off\n" > /etc/apache2/conf-available/moodle-performance.conf \
 && a2enconf moodle-performance

# -------- Install system dependencies --------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    cron \
    postgresql-client \
    default-mysql-client \
    mariadb-client \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libxml2-dev \
    libzip-dev \
    libpq-dev \
    libicu-dev \
    libcurl4-openssl-dev \
    libxslt1-dev \
    libonig-dev \
    libmariadb-dev-compat \
    libmariadb-dev \
    liblzf-dev \
    liblz4-dev \
    pkg-config \
 && rm -rf /var/lib/apt/lists/*

# -------- PHP extensions --------
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" \
    gd intl zip soap xsl opcache \
    mysqli pdo_mysql pdo_pgsql pgsql

# Redis driver with performance extensions (PECL elasticsearch is unmaintained)
RUN set -eux \
 && pecl install igbinary msgpack \
 && cd /tmp \
 && pecl bundle redis \
 && cd redis \
 && phpize \
 && ./configure --enable-redis-igbinary --enable-redis-msgpack --enable-redis-lzf \
 && make -j"$(nproc)" \
 && make install \
 && cd /tmp \
 && rm -rf redis \
 && docker-php-ext-enable igbinary msgpack redis

# Moodle root
WORKDIR /var/www

# -------- Download Moodle --------
RUN rm -rf "${MOODLE_APP_DIR}" \
 && git clone --branch "${MOODLE_VERSION}" --depth 1 "${MOODLE_GIT_REPO}" "${MOODLE_APP_DIR}" \
 && chown -R www-data:www-data "${MOODLE_APP_DIR}"

WORKDIR ${MOODLE_APP_DIR}

# Apache config per Moodle generation
COPY ${APACHE_CONF} /etc/apache2/sites-enabled/000-default.conf

# Custom PHP overrides (e.g., higher max_input_vars required by installer)
COPY config/php/php.ini /usr/local/etc/php/conf.d/zzz-moodle.ini

# -------- Cron --------
RUN echo "* * * * * www-data php ${MOODLE_APP_DIR}/admin/cli/cron.php > /dev/null 2>&1" \
    > /etc/cron.d/moodle-cron \
 && chmod 0644 /etc/cron.d/moodle-cron \
 && crontab /etc/cron.d/moodle-cron

COPY docker/moodle-entrypoint.sh /usr/local/bin/moodle-entrypoint.sh
RUN chmod +x /usr/local/bin/moodle-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/moodle-entrypoint.sh"]
CMD ["apache2-foreground"]

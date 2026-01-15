# Complete ProcessMaker 4 Dockerfile with PHP 8.3
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ="America/Los_Angeles"

ARG PM_VERSION=4.15.11+patch-c
ARG NODE_VERSION=22.13.1
ENV DOCKERVERSION=29.1.4

# Update and install prerequisites
RUN apt update && apt upgrade -y && \
    apt install -y software-properties-common ca-certificates lsb-release

# Add ondrej/php PPA
RUN add-apt-repository ppa:ondrej/php -y && apt update

# Install PHP 8.3 and all required extensions
RUN apt install -y \
    php8.3 php8.3-cli php8.3-fpm php8.3-mysql php8.3-zip php8.3-gd \
    php8.3-mbstring php8.3-curl php8.3-xml php8.3-bcmath php8.3-imagick \
    php8.3-dom php8.3-sqlite3 php8.3-redis php8.3-ldap php8.3-imap \
    php8.3-dev php-pear \
    nginx vim curl unzip wget supervisor cron mysql-client build-essential git

# Install librdkafka (required for rdkafka PHP extension)
RUN apt install -y librdkafka-dev && \
    pecl install rdkafka && \
    echo "extension=rdkafka.so" > /etc/php/8.3/mods-available/rdkafka.ini && \
    ln -s /etc/php/8.3/mods-available/rdkafka.ini /etc/php/8.3/cli/conf.d/20-rdkafka.ini && \
    ln -s /etc/php/8.3/mods-available/rdkafka.ini /etc/php/8.3/fpm/conf.d/20-rdkafka.ini

# Install exact Node.js version required by ProcessMaker
RUN apt-get update && apt-get install -y curl ca-certificates xz-utils \
    && curl -fsSLO https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz \
    && tar -xJf node-v${NODE_VERSION}-linux-x64.tar.xz -C /usr/local --strip-components=1 \
    && rm node-v${NODE_VERSION}-linux-x64.tar.xz \
    && node -v \
    && npm -v

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer

# Install Docker client for script execution
ENV DOCKERVERSION=29.1.4
RUN curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKERVERSION}.tgz && \
    tar xzvf docker-${DOCKERVERSION}.tgz --strip 1 -C /usr/local/bin docker/docker && \
    rm docker-${DOCKERVERSION}.tgz

# Configure PHP-FPM to run
RUN sed -i 's/^user\s*=.*/user = www-data/' /etc/php/8.3/fpm/pool.d/www.conf \
    && sed -i 's/^group\s*=.*/group = www-data/' /etc/php/8.3/fpm/pool.d/www.conf \
    && sed -i 's/^listen\.owner\s*=.*/listen.owner = www-data/' /etc/php/8.3/fpm/pool.d/www.conf \
    && sed -i 's/^listen\.group\s*=.*/listen.group = www-data/' /etc/php/8.3/fpm/pool.d/www.conf

RUN grep -nE '^(user|group)\s*=' /etc/php/8.3/fpm/pool.d/www.conf && \
    php-fpm8.3 -tt

# Setup cron for Laravel scheduler
RUN echo "* * * * * cd /code/pm4 && php artisan schedule:run >> /dev/null 2>&1" > /etc/cron.d/laravel-cron && \
    chmod 0644 /etc/cron.d/laravel-cron && \
    crontab /etc/cron.d/laravel-cron

# Copy configuration files
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/supervisor/services.conf /etc/supervisor/conf.d/services.conf
COPY docker/php/local.ini /etc/php/8.3/fpm/conf.d/99-local.ini
COPY docker/php/local.ini /etc/php/8.3/cli/conf.d/99-local.ini

# Download and setup ProcessMaker
WORKDIR /tmp
RUN wget https://github.com/ProcessMaker/processmaker/archive/refs/tags/v${PM_VERSION}.zip && \
    unzip v${PM_VERSION}.zip && \
    rm -rf /code/pm4 && \
    mkdir -p /code && \
    mv processmaker-$(echo ${PM_VERSION} | tr '+' '-') /code/pm4 && \
    rm v${PM_VERSION}.zip

# Install ProcessMaker dependencies
WORKDIR /code/pm4
RUN composer install --optimize-autoloader --no-scripts

# Make cache detereministic and clear caches
ENV NPM_CONFIG_CACHE=/code/pm4/.npm-cache
RUN rm -rf /code/pm4/.npm-cache && npm cache clean --force

# Copy Laravel Echo Server config and install
COPY docker/laravel-echo-server.json /code/pm4/laravel-echo-server.json
RUN npm install --unsafe-perm=true

# Build frontend assets (this takes a while)
ENV NODE_OPTIONS="--max-old-space-size=2048"
RUN npm run dev || echo "Asset build failed, will build at startup"

# Copy initialization script and set permissions
COPY docker/init.sh /code/pm4/init.sh
# Fix line endings (Windows CRLF -> Unix LF) and make executable
RUN sed -i 's/\r$//' /code/pm4/init.sh && chmod +x /code/pm4/init.sh

# Create all necessary directories with proper permissions
# IMPORTANT: Do this AFTER copying init.sh to ensure directories exist before volume mount
RUN mkdir -p /code/pm4/storage/app/public \
    /code/pm4/storage/framework/cache/data \
    /code/pm4/storage/framework/sessions \
    /code/pm4/storage/framework/views \
    /code/pm4/storage/logs \
    /code/pm4/bootstrap/cache && \
    chmod -R 777 /code/pm4/storage && \
    chmod -R 777 /code/pm4/bootstrap/cache && \
    touch /code/pm4/storage/logs/laravel.log && \
    chmod 666 /code/pm4/storage/logs/laravel.log

# Create a startup wrapper script
RUN printf '#!/bin/bash\n\
set -e\n\
echo "Starting ProcessMaker 4..."\n\
# Ensure storage directories still exist after volume mount\n\
mkdir -p /code/pm4/storage/{app,framework/{cache/data,sessions,views},logs}\n\
mkdir -p /code/pm4/bootstrap/cache\n\
# Set permissions\n\
chmod -R 777 /code/pm4/storage /code/pm4/bootstrap/cache\n\
# Build assets if they do not exist\n\
if [ ! -f /code/pm4/public/js/app.js ]; then\n\
  echo "Building frontend assets (this may take a few minutes)..."\n\
  export NODE_OPTIONS="--max-old-space-size=4096"\n\
  cd /code/pm4 && npm run dev\n\
fi\n\
# Run initialization\n\
/code/pm4/init.sh\n\
# Start supervisor\n\
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf\n\
' > /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80 6001

# Use entrypoint script
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Complete ProcessMaker 4 Dockerfile with PHP 8.1
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ="America/Los_Angeles"
ARG PM_VERSION=4.15.11

# Update and install prerequisites
RUN apt update && apt upgrade -y && \
    apt install -y software-properties-common ca-certificates lsb-release

# Add ondrej/php PPA
RUN add-apt-repository ppa:ondrej/php -y && apt update

# Install PHP 8.1 and all required extensions
RUN apt install -y \
    php8.1 php8.1-cli php8.1-fpm php8.1-mysql php8.1-zip php8.1-gd \
    php8.1-mbstring php8.1-curl php8.1-xml php8.1-bcmath php8.1-imagick \
    php8.1-dom php8.1-sqlite3 php8.1-redis php8.1-ldap php8.1-imap \
    nginx vim curl unzip wget supervisor cron mysql-client build-essential git

ARG NODE_VERSION=16.18.1
# Install exact Node.js version required by ProcessMaker 4.3.0
RUN apt-get update && apt-get install -y curl ca-certificates xz-utils \
    && curl -fsSLO https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz \
    && tar -xJf node-v${NODE_VERSION}-linux-x64.tar.xz -C /usr/local --strip-components=1 \
    && rm node-v${NODE_VERSION}-linux-x64.tar.xz \
    && node -v \
    && npm -v \
    && npm i -g npm@8.19.4 \
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
RUN sed -i 's/^user\s*=.*/user = www-data/' /etc/php/8.1/fpm/pool.d/www.conf \
    && sed -i 's/^group\s*=.*/group = www-data/' /etc/php/8.1/fpm/pool.d/www.conf \
    && sed -i 's/^listen\.owner\s*=.*/listen.owner = www-data/' /etc/php/8.1/fpm/pool.d/www.conf \
    && sed -i 's/^listen\.group\s*=.*/listen.group = www-data/' /etc/php/8.1/fpm/pool.d/www.conf

RUN grep -nE '^(user|group)\s*=' /etc/php/8.1/fpm/pool.d/www.conf && \
    php-fpm8.1 -tt

# Setup cron for Laravel scheduler
RUN echo "* * * * * cd /code/pm4 && php artisan schedule:run >> /dev/null 2>&1" > /etc/cron.d/laravel-cron && \
    chmod 0644 /etc/cron.d/laravel-cron && \
    crontab /etc/cron.d/laravel-cron

# Copy configuration files
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/supervisor/services.conf /etc/supervisor/conf.d/services.conf
COPY docker/php/local.ini /etc/php/8.1/fpm/conf.d/99-local.ini
COPY docker/php/local.ini /etc/php/8.1/cli/conf.d/99-local.ini

# Download and setup ProcessMaker
WORKDIR /tmp
RUN wget https://github.com/ProcessMaker/processmaker/archive/refs/tags/v${PM_VERSION}.zip && \
    unzip v${PM_VERSION}.zip && \
    rm -rf /code/pm4 && \
    mkdir -p /code && \
    mv processmaker-${PM_VERSION} /code/pm4 && \
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
RUN npm run dev

# Copy initialization script and set permissions
COPY docker/init.sh /code/pm4/init.sh
RUN chmod +x /code/pm4/init.sh

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
RUN echo '#!/bin/bash\n\
set -e\n\
echo "Starting ProcessMaker 4..."\n\
# Ensure storage directories still exist after volume mount\n\
mkdir -p /code/pm4/storage/{app,framework/{cache/data,sessions,views},logs}\n\
mkdir -p /code/pm4/bootstrap/cache\n\
# Set permissions\n\
chmod -R 777 /code/pm4/storage /code/pm4/bootstrap/cache\n\
# Run initialization\n\
/code/pm4/init.sh\n\
# Start supervisor\n\
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf\n\
' > /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80 6001

# Use entrypoint script
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
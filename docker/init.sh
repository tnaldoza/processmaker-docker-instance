#!/bin/bash
set -e
cd /code/pm4

echo "================================================"
echo "ProcessMaker 4 Initialization"
echo "================================================"

# Helpers
ensure_env_kv () {
  local key="$1"
  local val="$2"

  # If .env doesn't exist yet, create it (only used after install decision)
  [ -f ".env" ] || touch .env

  if grep -q "^${key}=" .env 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|g" .env
  else
    echo "${key}=${val}" >> .env
  fi
}

# Wait for MySQL
echo "Waiting for MySQL to be ready..."
MAX_RETRIES=60
RETRY_COUNT=0

while ! mysqladmin ping -u pm -ppass -h mysql --silent 2>/dev/null; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "ERROR: MySQL failed to start after $MAX_RETRIES attempts"
    echo "Check MySQL logs: docker compose logs mysql"
    exit 1
  fi
  echo "  Attempt $RETRY_COUNT/$MAX_RETRIES - MySQL not ready yet..."
  sleep 2
done

echo "✓ MySQL is ready!"

# Storage dirs
echo "Setting up storage directories..."
mkdir -p storage/app/public
mkdir -p storage/framework/{cache,sessions,views}
mkdir -p storage/logs
mkdir -p bootstrap/cache
chmod -R 777 storage bootstrap/cache
echo "✓ Storage directories ready"

# --------------------------
# Normalize host + port safely
# --------------------------
# PM_APP_URL should be like: http://localhost (no port) OR http://localhost:8080
PM_APP_URL="${PM_APP_URL:-http://localhost}"
PM_APP_URL="${PM_APP_URL%/}"

# Extract scheme
SCHEME="http"
case "$PM_APP_URL" in
  https://*) SCHEME="https" ;;
esac

# Extract host:port from PM_APP_URL
APP_HOSTPORT="${PM_APP_URL#http://}"
APP_HOSTPORT="${APP_HOSTPORT#https://}"
APP_HOSTPORT="${APP_HOSTPORT%%/*}"   # remove any path
APP_DOMAIN="${APP_HOSTPORT%%:*}"     # hostname only (no port)

# Decide effective port
# If PM_APP_PORT is set, prefer it. Otherwise keep any port already in PM_APP_URL.
if [ -n "${PM_APP_PORT:-}" ] && [ "${PM_APP_PORT}" != "80" ]; then
  APP_HOSTPORT="${APP_DOMAIN}:${PM_APP_PORT}"
fi

APP_URL_EFFECTIVE="${SCHEME}://${APP_HOSTPORT}"
STATEFUL_DOMAINS="${APP_HOSTPORT},127.0.0.1:${PM_APP_PORT:-8080},localhost:${PM_APP_PORT:-8080}"

# --------------------------
# Handle Windows bind mount edge case: .env accidentally becomes a directory
# --------------------------
ENV_FILE="/code/pm4/.env"
if [ -d "$ENV_FILE" ]; then
  echo "WARNING: .env is a directory (likely Windows bind-mount issue). Removing it..."
  rm -rf "$ENV_FILE"
fi

# Install decision:
# - If .env missing -> install
# - If .env exists but no APP_KEY -> treat as stale -> remove -> install
NEED_INSTALL=0
if [ ! -f "$ENV_FILE" ]; then
  NEED_INSTALL=1
else
  if ! grep -q '^APP_KEY=' "$ENV_FILE"; then
    echo "WARNING: .env exists but no APP_KEY found. Treating as incomplete install and reinstalling..."
    rm -f "$ENV_FILE"
    NEED_INSTALL=1
  fi
fi

if [ "$NEED_INSTALL" -eq 1 ]; then
  echo ""
  echo "================================================"
  echo "First-time (or incomplete) installation detected"
  echo "================================================"
  echo "Installing ProcessMaker..."
  echo "This may take a few minutes..."

  php artisan processmaker:install --no-interaction \
    --url="${APP_URL_EFFECTIVE}" \
    --broadcast-host="${APP_HOSTPORT%:*}:${PM_BROADCASTER_PORT}" \
    --username=admin \
    --password=admin123 \
    --email=admin@processmaker.com \
    --first-name=Admin \
    --last-name=User \
    --db-host=mysql \
    --db-port=3306 \
    --db-name=processmaker \
    --db-username=pm \
    --db-password=pass \
    --data-driver=mysql \
    --data-host=mysql \
    --data-port=3306 \
    --data-name=processmaker \
    --data-username=pm \
    --data-password=pass \
    --redis-host=redis

  echo "✓ ProcessMaker installed"
fi

# Always enforce env fixes (post-install + restarts)
echo ""
echo "Ensuring .env settings are correct..."

ensure_env_kv "APP_URL" "${APP_URL_EFFECTIVE}"
ensure_env_kv "SESSION_DOMAIN" "${APP_DOMAIN}"   # MUST be hostname only
ensure_env_kv "SANCTUM_STATEFUL_DOMAINS" "${STATEFUL_DOMAINS}"

ensure_env_kv "PROCESSMAKER_SCRIPTS_DOCKER" "/usr/local/bin/docker"
ensure_env_kv "PROCESSMAKER_SCRIPTS_DOCKER_MODE" "copying"
ensure_env_kv "LARAVEL_ECHO_SERVER_AUTH_HOST" "${APP_URL_EFFECTIVE}"
ensure_env_kv "SESSION_SECURE_COOKIE" "false"

# ? Maybe we should'nt clear cache, issues with runtime.
php artisan config:clear || true
php artisan cache:clear || true

# Storage link
if [ ! -L "public/storage" ]; then
  php artisan storage:link || true
fi

# DB migrations on restart/update
echo "Checking for database updates..."
php artisan migrate --force 2>/dev/null || echo "No migrations needed"

chmod -R 777 storage bootstrap/cache

echo ""
echo "Initialization complete! Services starting..."
echo "================================================"

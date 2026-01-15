#!/bin/bash
set -euo pipefail
cd /code/pm4

echo "================================================"
echo "ProcessMaker 4 Initialization"
echo "================================================"

# Config defaults (override via env)
PM_APP_URL="${PM_APP_URL:-http://localhost}"
PM_APP_URL="${PM_APP_URL%/}"

PM_APP_PORT="${PM_APP_PORT:-8080}"
PM_BROADCASTER_PORT="${PM_BROADCASTER_PORT:-6001}"

PM_DB_HOST="${PM_DB_HOST:-mysql}"
PM_DB_PORT="${PM_DB_PORT:-3306}"
PM_DB_NAME="${PM_DB_NAME:-processmaker}"
PM_DB_USER="${PM_DB_USER:-pm}"
PM_DB_PASS="${PM_DB_PASS:-pass}"

PM_REDIS_HOST="${PM_REDIS_HOST:-redis}"

PM_ADMIN_USER="${PM_ADMIN_USER:-admin}"
PM_ADMIN_PASS="${PM_ADMIN_PASS:-admin123}"
PM_ADMIN_EMAIL="${PM_ADMIN_EMAIL:-admin@processmaker.com}"
PM_ADMIN_FIRST="${PM_ADMIN_FIRST:-Admin}"
PM_ADMIN_LAST="${PM_ADMIN_LAST:-User}"

PM_ENABLE_EXECUTORS="${PM_ENABLE_EXECUTORS:-0}"

# Helpers
ensure_env_kv () {
  local key="$1"
  local val="$2"

  [ -f ".env" ] || touch .env

  if grep -q "^${key}=" .env 2>/dev/null; then
    local esc_val
    esc_val="$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')"
    sed -i "s/^${key}=.*/${key}=${esc_val}/" .env
  else
    echo "${key}=${val}" >> .env
  fi
}

wait_for_tcp () {
	local host="$1"
	local port="$2"
	local name="$3"
	local max_retries="${4:-60}"

	echo "Waiting for ${name} to be ready at ${host}:${port}..."
	local i=0
	while true; do
		i=$((i+1))
		if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
			echo "✓ ${name} is ready!"
			break
		fi
		if [ "$i" -ge "$max_retries" ]; then
			echo "ERROR: ${name} failed to start after ${max_retries} attempts"
			exit 1
		fi
		echo "  Attempt ${i}/${max_retries} - ${name} not ready yet..."
		sleep 2
	done
}

# Wait for MySQL
echo "Waiting for MySQL to be ready at ${PM_DB_HOST}:${PM_DB_PORT}..."
MAX_RETRIES=60
RETRY_COUNT=0

while ! mysqladmin ping -u "${PM_DB_USER}" -p"${PM_DB_PASS}" -h "${PM_DB_HOST}" -P "${PM_DB_PORT}" --silent 2>/dev/null; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
    echo "ERROR: MySQL failed to start after $MAX_RETRIES attempts"
    echo "Check MySQL logs: docker compose logs mysql"
    exit 1
  fi
  echo "  Attempt $RETRY_COUNT/$MAX_RETRIES - MySQL not ready yet..."
  sleep 2
done

echo "✓ MySQL is ready!"
wait_for_tcp "${PM_REDIS_HOST}" "6379" "Redis" 60

# Storage dirs
echo "Setting up storage directories..."
mkdir -p storage/app/public \
         storage/framework/cache \
         storage/framework/sessions \
         storage/framework/views \
         storage/logs \
         bootstrap/cache
chmod -R 777 storage bootstrap/cache
echo "✓ Storage directories ready"

# Normalize URL/host/port
SCHEME="http"
case "$PM_APP_URL" in
  https://*) SCHEME="https" ;;
esac

APP_HOSTPORT="${PM_APP_URL#http://}"
APP_HOSTPORT="${APP_HOSTPORT#https://}"
APP_HOSTPORT="${APP_HOSTPORT%%/*}"
APP_DOMAIN="${APP_HOSTPORT%%:*}"

if [ -n "${PM_APP_PORT:-}" ] && [ "${PM_APP_PORT}" != "80" ]; then
  	APP_HOSTPORT="${APP_DOMAIN}:${PM_APP_PORT}"
fi

APP_URL_EFFECTIVE="${SCHEME}://${APP_HOSTPORT}"

STATEFUL_DOMAINS="$(printf '%s\n' \
	"${APP_DOMAIN}" \
	"${APP_HOSTPORT}" \
	"localhost" \
	"localhost:${PM_APP_PORT}" \
	"127.0.0.1" \
	"127.0.0.1:${PM_APP_PORT}" \
	| awk 'NF' | sort -u | paste -sd, -)"

BROADCAST_HOST="${APP_DOMAIN}:${PM_BROADCASTER_PORT}"

# Windows bind mount edge case: .env accidentally becomes a directory
ENV_FILE="/code/pm4/.env"
if [ -d "$ENV_FILE" ]; then
	echo "WARNING: .env is a directory (likely Windows bind-mount issue). Removing it..."
	rm -rf "$ENV_FILE"
fi

# Install decision
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
		--broadcast-host="${BROADCAST_HOST}" \
		--username="${PM_ADMIN_USER}" \
		--password="${PM_ADMIN_PASS}" \
		--email="${PM_ADMIN_EMAIL}" \
		--first-name="${PM_ADMIN_FIRST}" \
		--last-name="${PM_ADMIN_LAST}" \
		--db-host="${PM_DB_HOST}" \
		--db-port="${PM_DB_PORT}" \
		--db-name="${PM_DB_NAME}" \
		--db-username="${PM_DB_USER}" \
		--db-password="${PM_DB_PASS}" \
		--data-driver=mysql \
		--data-host="${PM_DB_HOST}" \
		--data-port="${PM_DB_PORT}" \
		--data-name="${PM_DB_NAME}" \
		--data-username="${PM_DB_USER}" \
		--data-password="${PM_DB_PASS}" \
		--redis-host="${PM_REDIS_HOST}"

	if [ "${PM_ENABLE_EXECUTORS}" = "1" ]; then
		echo "Checking Docker access..."
		docker version >/dev/null 2>&1 || (echo "ERROR: Docker not accessible inside container (is /var/run/docker.sock mounted?)" && exit 1)

		run_executor_install () {
			local cmd="$1"
			echo "→ $cmd"
			if ! bash -lc "$cmd"; then
				echo "WARNING: executor install failed: $cmd"
				return 1
			fi
		}

		FAIL=0
		run_executor_install "php artisan docker-executor-php:install"  || FAIL=1
		run_executor_install "php artisan docker-executor-node:install" || FAIL=1
		run_executor_install "php artisan docker-executor-lua:install"  || FAIL=1
		run_executor_install "php artisan processmaker:build-script-executor" || true

		echo "Executor image inventory:"
		docker image ls | egrep -i 'executor|docker-executor|processmaker.*executor|pm-executor' || true

		if [ "$FAIL" -eq 1 ]; then
			echo "WARNING: One or more executor installs failed. Check logs above."
		fi
	fi

	echo "✓ ProcessMaker installed"
fi

# Ensure executors exist (install if missing) - ONLY if enabled
if [ "${PM_ENABLE_EXECUTORS}" = "1" ]; then
	need_executor=0
	docker image inspect processmaker4/executor-processmaker-javascript-2:v1.0.0 >/dev/null 2>&1 || need_executor=1
	docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -qi 'pm-executor' || need_executor=1

	if [ "$need_executor" -eq 1 ]; then
		echo "Executor images missing -> (re)installing..."
		php artisan docker-executor-php:install  || true
		php artisan docker-executor-node:install || true
		php artisan docker-executor-lua:install  || true
		php artisan processmaker:build-script-executor || true
	fi
fi

echo ""
echo "Ensuring .env settings are correct..."

ensure_env_kv "APP_URL" "${APP_URL_EFFECTIVE}"

# Cookie safety: localhost can be special; allow override
if [ "${APP_DOMAIN}" = "localhost" ] || [ "${APP_DOMAIN}" = "127.0.0.1" ]; then
  	ensure_env_kv "SESSION_DOMAIN" ""
else
  	ensure_env_kv "SESSION_DOMAIN" "${APP_DOMAIN}"
fi

ensure_env_kv "SANCTUM_STATEFUL_DOMAINS" "${STATEFUL_DOMAINS}"

# Only set docker script settings if executors enabled
if [ "${PM_ENABLE_EXECUTORS}" = "1" ]; then
	ensure_env_kv "PROCESSMAKER_SCRIPTS_DOCKER" "/usr/local/bin/docker"
	ensure_env_kv "PROCESSMAKER_SCRIPTS_DOCKER_MODE" "copying"
fi

ensure_env_kv "LARAVEL_ECHO_SERVER_AUTH_HOST" "${APP_URL_EFFECTIVE}"
ensure_env_kv "SESSION_SECURE_COOKIE" "false"
ensure_env_kv "CACHE_DRIVER" "redis"
ensure_env_kv "QUEUE_CONNECTION" "redis"
ensure_env_kv "SESSION_DRIVER" "redis"
ensure_env_kv "REDIS_CLIENT" "phpredis"
ensure_env_kv "APP_ENV" "local"
ensure_env_kv "APP_DEBUG" "true"
ensure_env_kv "REDIS_HOST" "${PM_REDIS_HOST}"
ensure_env_kv "REDIS_PORT" "6379"

if [ "${PM_CLEAR_CACHES_ON_BOOT:-0}" = "1" ]; then
	echo "PM_CLEAR_CACHES_ON_BOOT=1 -> clearing caches..."
	php artisan config:clear || true
	php artisan cache:clear || true
fi

if [ ! -f "storage/oauth-public.key" ] || [ ! -f "storage/oauth-private.key" ]; then
	echo "Passport keys missing -> generating..."
  	php artisan passport:keys --force || php artisan passport:install --force
fi

if [ ! -L "public/storage" ]; then
  php artisan storage:link || true
fi

echo "Checking for database updates..."
if php artisan migrate --force; then
  echo "✓ Migrations complete"
else
  echo "WARNING: migrations failed (see output above)"
fi

chmod -R 777 storage bootstrap/cache

echo ""
echo "Initialization complete! Services starting..."
echo "================================================"

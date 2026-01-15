# setup.ps1 - ProcessMaker 4 Development Environment Setup
# Run this script with: .\setup.ps1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "ProcessMaker 4 Development Environment Setup" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Create necessary directories
Write-Host "Creating directory structure..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "docker\nginx" | Out-Null
New-Item -ItemType Directory -Force -Path "docker\supervisor" | Out-Null
New-Item -ItemType Directory -Force -Path "docker" | Out-Null

# Check if configuration files exist
Write-Host "Checking for required configuration files..." -ForegroundColor Yellow

$requiredFiles = @(
    "docker\nginx\nginx.conf",
    "docker\supervisor\services.conf",
    "docker\laravel-echo-server.json",
    "Dockerfile",
    "docker-compose.yml"
)

$missingFiles = @()
foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: Missing required configuration files:" -ForegroundColor Red
    foreach ($file in $missingFiles) {
        Write-Host "  - $file" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Please create these files from the artifacts first!" -ForegroundColor Red
    exit 1
}

Write-Host "All configuration files found!" -ForegroundColor Green

# Build Docker containers
Write-Host ""
Write-Host "Building Docker containers (this may take several minutes)..." -ForegroundColor Yellow
docker-compose build
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker build failed!" -ForegroundColor Red
    exit 1
}

# Start containers
Write-Host ""
Write-Host "Starting containers..." -ForegroundColor Yellow
docker-compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to start containers!" -ForegroundColor Red
    exit 1
}

# Wait for MySQL to be ready
Write-Host ""
Write-Host "Waiting for MySQL to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Check if .env exists (if not, we need to install)
Write-Host ""
Write-Host "Checking for existing ProcessMaker installation..." -ForegroundColor Yellow

if (Test-Path .\pm4.env -PathType Container) { Remove-Item -Recurse -Force .\pm4.env }
New-Item -ItemType File -Force .\pm4.env | Out-Null

$envExists = docker-compose exec -T web test -f /code/pm4/.env
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "No .env file found. Running ProcessMaker installation..." -ForegroundColor Yellow
    Write-Host "This will take several minutes..." -ForegroundColor Yellow

    # Install Composer dependencies
    Write-Host ""
    Write-Host "Installing Composer dependencies..." -ForegroundColor Yellow
    docker-compose exec -T web composer install --no-interaction --prefer-dist
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Composer install had issues, continuing anyway..." -ForegroundColor Yellow
    }

    # Install NPM dependencies
    Write-Host ""
    Write-Host "Installing NPM dependencies..." -ForegroundColor Yellow
    docker-compose exec -T web npm install
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: NPM install had issues, continuing anyway..." -ForegroundColor Yellow
    }

    # Build frontend assets
    Write-Host ""
    Write-Host "Building frontend assets..." -ForegroundColor Yellow
    docker-compose exec -T web npm run dev
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Asset build had issues, continuing anyway..." -ForegroundColor Yellow
    }

    # Run ProcessMaker install command
    Write-Host ""
    Write-Host "Running ProcessMaker installation wizard..." -ForegroundColor Yellow
    docker-compose exec -T web php artisan processmaker:install `
        --no-interaction `
        --url=http://localhost:8080 `
        --broadcast-host=http://localhost:6001 `
        --username=admin `
        --password=admin123 `
        --email=admin@processmaker.com `
        --first-name=Admin `
        --last-name=User `
        --db-host=mysql `
        --db-port=3306 `
        --db-name=processmaker `
        --db-username=pm `
        --db-password=pass `
        --data-driver=mysql `
        --data-host=mysql `
        --data-port=3306 `
        --data-name=processmaker `
        --data-username=pm `
        --data-password=pass `
        --redis-host=redis

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: ProcessMaker installation had issues, check logs..." -ForegroundColor Yellow
    }

    # Add additional environment variables
    Write-Host ""
    Write-Host "Configuring additional settings..." -ForegroundColor Yellow
    docker-compose exec -T web bash -c 'echo "PROCESSMAKER_SCRIPTS_DOCKER=/usr/local/bin/docker" >> .env'
    docker-compose exec -T web bash -c 'echo "PROCESSMAKER_SCRIPTS_DOCKER_MODE=copying" >> .env'
    docker-compose exec -T web bash -c 'echo "LARAVEL_ECHO_SERVER_AUTH_HOST=http://localhost" >> .env'
    docker-compose exec -T web bash -c 'echo "SESSION_SECURE_COOKIE=false" >> .env'

    # Create storage link
    Write-Host ""
    Write-Host "Creating storage link..." -ForegroundColor Yellow
    docker-compose exec -T web php artisan storage:link

} else {
    Write-Host ""
    Write-Host ".env file exists, skipping installation." -ForegroundColor Green
    Write-Host "Installing/updating dependencies..." -ForegroundColor Yellow
    docker-compose exec -T web composer install --no-interaction
    docker-compose exec -T web npm install
}

# Restart services to pick up any changes
Write-Host ""
Write-Host "Restarting services..." -ForegroundColor Yellow
docker-compose restart web

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "ProcessMaker 4 is now running!" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 Application:     http://localhost:8080" -ForegroundColor Cyan
Write-Host "🔌 WebSockets:      ws://localhost:6001" -ForegroundColor Cyan
Write-Host ""
Write-Host "📧 Login Credentials:" -ForegroundColor Yellow
Write-Host "   Email:           admin@processmaker.com"
Write-Host "   Password:        admin123"
Write-Host ""
Write-Host "🗄️  Database Connection:" -ForegroundColor Yellow
Write-Host "   Host:            localhost:3306"
Write-Host "   Database:        processmaker"
Write-Host "   Username:        pm"
Write-Host "   Password:        pass"
Write-Host ""
Write-Host "📊 Redis:" -ForegroundColor Yellow
Write-Host "   Host:            localhost:6379"
Write-Host ""
Write-Host "⚙️  Useful Commands:" -ForegroundColor Yellow
Write-Host "   View logs:               docker-compose logs -f web"
Write-Host "   Access container:        docker-compose exec web bash"
Write-Host "   Run artisan:             docker-compose exec web php artisan [command]"
Write-Host "   Rebuild assets:          docker-compose exec web npm run dev"
Write-Host "   Watch assets:            docker-compose exec web npm run watch"
Write-Host "   Stop containers:         docker-compose down"
Write-Host "   Remove everything:       docker-compose down -v"
Write-Host ""
Write-Host "🔧 Services Running:" -ForegroundColor Yellow
Write-Host "   - Nginx (web server)"
Write-Host "   - PHP-FPM 7.4"
Write-Host "   - Laravel Horizon (queue worker)"
Write-Host "   - Laravel Echo Server (websockets)"
Write-Host "   - Cron (scheduled tasks)"
Write-Host ""

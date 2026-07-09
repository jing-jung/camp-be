# PowerShell DB Migration Script

# Database connection information
$DB_HOST = "stockbrief-dev-postgres.c5s4g8sm0q35.ap-northeast-2.rds.amazonaws.com"
$DB_PORT = "5432"
$DB_NAME = "stockbrief"
$DB_USER = "stockbrief_admin"
$DB_PASSWORD = "1Bd8sB?obnD))zgMftsYVQN#fv)i"

# Set DATABASE_URL environment variable
$env:DATABASE_URL = "postgresql+psycopg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

Write-Host "🔄 Running database migrations..." -ForegroundColor Cyan
Write-Host "📍 Database: ${DB_HOST}/${DB_NAME}" -ForegroundColor Yellow

# Run Alembic migrations
alembic upgrade head

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Database migration completed successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ Database migration failed!" -ForegroundColor Red
    exit 1
}

#!/bin/bash
# DB Migration Script

# Database connection information
DB_HOST="stockbrief-dev-postgres.c5s4g8sm0q35.ap-northeast-2.rds.amazonaws.com"
DB_PORT="5432"
DB_NAME="stockbrief"
DB_USER="stockbrief_admin"
DB_PASSWORD="1Bd8sB?obnD))zgMftsYVQN#fv)i"

# Set DATABASE_URL environment variable
export DATABASE_URL="postgresql+psycopg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

echo "🔄 Running database migrations..."
echo "📍 Database: ${DB_HOST}/${DB_NAME}"

# Run Alembic migrations
alembic upgrade head

if [ $? -eq 0 ]; then
    echo "✅ Database migration completed successfully!"
else
    echo "❌ Database migration failed!"
    exit 1
fi

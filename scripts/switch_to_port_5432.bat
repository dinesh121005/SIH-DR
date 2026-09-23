@echo off
:: ==============================================================================
:: Diabetic Retinopathy Screening Pipeline - Switch Host Port to 5432
:: Run this batch file as Administrator (Right Click -> Run as administrator)
:: ==============================================================================

echo [1/4] Stopping conflicting Windows PostgreSQL service (postgresql-x64-13)...
net stop postgresql-x64-13
sc config postgresql-x64-13 start= demand

echo [2/4] Updating local .env files to port 5432...
powershell -Command "(Get-Content .env) -replace 'POSTGRES_PORT=5434', 'POSTGRES_PORT=5432' | Set-Content .env"
powershell -Command "(Get-Content backend\.env) -replace '5434', '5432' | Set-Content backend\.env"

echo [3/4] Recreating Docker Compose containers on port 5432...
docker compose down
docker compose up -d

echo [4/4] Verifying container status...
docker compose ps
docker exec dr_screening_postgres psql -U dr_user -d dr_screening -c "SELECT 1 AS connected;"

echo Done! Docker Postgres is now active and listening on host port 5432.
pause

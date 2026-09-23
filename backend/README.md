# Backend Service (`backend`)

## Architecture
FastAPI asynchronous backend orchestrating data persistence, background queues, and clinician authentication.

## Tech Stack
- **Framework**: FastAPI + Uvicorn
- **Database**: PostgreSQL 16 (via SQLAlchemy async + asyncpg)
- **Cache & Queue**: Redis 7
- **Validation**: Pydantic v2

## Local Setup
```bash
cp .env.example .env
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

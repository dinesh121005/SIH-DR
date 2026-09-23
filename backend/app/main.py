from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="Diabetic Retinopathy Screening API",
    description="Backend service orchestrating fundus image analysis, patient records, and doctor triage.",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health", tags=["System"])
async def health_check():
    return {
        "status": "healthy",
        "service": "backend-api",
        "stage": "STAGE 0 — PROJECT DISCOVERY",
    }

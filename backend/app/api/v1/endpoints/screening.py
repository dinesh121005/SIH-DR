"""Tele-Ophthalmology Screening Endpoints.

Provides:
- POST /api/v1/quality/check: Standalone Stage 1 image quality assessment (Good / Usable / Reject).
- POST /api/v1/screening/upload: Unified clinical pipeline (Stage 1 Quality Gate -> Stage 2 DR Grading).
"""

from __future__ import annotations

import threading
from typing import Optional

from fastapi import APIRouter, File, HTTPException, Query, UploadFile, status
from starlette.concurrency import run_in_threadpool

from app.ml.inference import predict
from app.ml.quality_inference import assess_image_quality
from app.schemas.grading import PredictionResponse
from app.schemas.quality import QualityResponse, UnifiedScreeningResponse

router = APIRouter(tags=["screening"])

MAX_FILE_SIZE = 10 * 1024 * 1024
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/jpg"}
_pipeline_lock = threading.Lock()


def _safe_quality(image_bytes: bytes) -> dict:
    with _pipeline_lock:
        return assess_image_quality(image_bytes)


def _safe_grading(image_bytes: bytes, threshold: Optional[float]) -> dict:
    with _pipeline_lock:
        return predict(image_bytes, referable_threshold=threshold)


@router.post(
    "/quality/check",
    response_model=QualityResponse,
    summary="Stage 1: Fundus Image Quality Check (EyeQ)",
    status_code=status.HTTP_200_OK,
)
async def check_image_quality(
    file: UploadFile = File(..., description="Fundus image (JPEG or PNG, max 10MB)"),
):
    """Evaluates uploaded fundus image quality using the EyeQ composite model.
    
    Classifies image into Good, Usable, or Reject to catch blur, glare, and cataracts
    at the screening clinic before sending to the grading pipeline.
    """
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported media type '{file.content_type}'. Please upload PNG or JPEG.",
        )

    contents = await file.read()
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=getattr(status, "HTTP_413_CONTENT_TOO_LARGE", 413),
            detail="Uploaded file size exceeds the 10 MB limit.",
        )

    try:
        result = await run_in_threadpool(_safe_quality, contents)
        return QualityResponse(**result)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Quality assessment failed: {exc}",
        )


@router.post(
    "/screening/upload",
    response_model=UnifiedScreeningResponse,
    summary="Unified Clinical Screening Pipeline (Quality Check -> DR Grading)",
    status_code=status.HTTP_200_OK,
)
async def upload_and_screen(
    file: UploadFile = File(..., description="Fundus image (JPEG or PNG, max 10MB)"),
    referable_threshold: Optional[float] = Query(
        None,
        ge=0.0,
        le=1.0,
        description="Optional probability threshold for referable DR decision (0.0 to 1.0)",
    ),
):
    """Full End-to-End Clinical Screening Pipeline.
    
    1. **Stage 1 (Quality Gate):** Checks clarity, illumination, and EyeQ grade.
       - If **Reject**: Workflow halts immediately, advising the field nurse to recapture image.
    2. **Stage 2 (DR Grading):** If Good or Usable, executes autonomous ICDR grading (0-4),
       computes referral risk, and assigns doctor triage priority.
    """
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported media type '{file.content_type}'. Please upload PNG or JPEG.",
        )

    contents = await file.read()
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=getattr(status, "HTTP_413_CONTENT_TOO_LARGE", 413),
            detail="Uploaded file size exceeds the 10 MB limit.",
        )

    try:
        # Step 1: Quality Check
        quality_data = await run_in_threadpool(_safe_quality, contents)
        quality_res = QualityResponse(**quality_data)

        # If rejected, halt and prompt on-site recapture
        if not quality_res.is_acceptable:
            return UnifiedScreeningResponse(
                workflow_stage="STAGE_1_QUALITY_GATE_REJECTED",
                action_required="RECAPTURE_IMAGE",
                quality_assessment=quality_res,
                dr_grading=None,
                summary_message=(
                    "Image quality is ungradable (blur/occlusion). "
                    "Recapture requested on-site while patient is seated. Not routed to grading."
                ),
            )

        # Step 2: Quality passed -> Proceed to DR Grading
        grading_data = await run_in_threadpool(_safe_grading, contents, referable_threshold)
        dr_res = PredictionResponse(**grading_data)

        action = "DOCTOR_REFERRAL_REQUIRED" if dr_res.referable else "ROUTINE_ANNUAL_SCREENING"
        summary = (
            f"Quality verified ({quality_res.quality_class}). "
            f"Diagnosis: {dr_res.grade_name} (Grade {dr_res.grade}). "
            f"{'Referral required for ophthalmologist evaluation.' if dr_res.referable else 'No referable DR detected.'}"
        )

        return UnifiedScreeningResponse(
            workflow_stage="STAGE_2_DR_GRADING_COMPLETED",
            action_required=action,
            quality_assessment=quality_res,
            dr_grading=dr_res,
            summary_message=summary,
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Screening workflow pipeline encountered an error: {exc}",
        )

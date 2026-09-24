"""DR Grading API Endpoints (FastAPI).

Provides endpoints for:
- POST /api/v1/grading/predict: Multi-class prediction, probabilities, and referral flag.
- POST /api/v1/grading/gradcam: Saliency heatmap overlay on the fundus image.
- GET  /api/v1/grading/model-info: Model metadata and weight presence.
"""

from __future__ import annotations

import threading
from typing import Optional

import cv2
from fastapi import APIRouter, File, HTTPException, Query, Response, UploadFile, status
from starlette.concurrency import run_in_threadpool

from app.ml.inference import (
    generate_gradcam,
    load_metadata,
    predict,
    resolve_path,
)
from app.schemas.grading import ModelDetails, ModelInfoResponse, PredictionResponse

router = APIRouter(prefix="/grading", tags=["grading"])

# Max upload limit: 10 MB
MAX_FILE_SIZE = 10 * 1024 * 1024
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/jpg"}

# Module-level thread lock to protect shared model state during inference and Grad-CAM hooks
_model_lock = threading.Lock()


def _safe_predict(image_bytes: bytes, threshold: Optional[float]) -> dict:
    """Thread-safe synchronous prediction helper."""
    with _model_lock:
        return predict(image_bytes, referable_threshold=threshold)


def _safe_gradcam(image_bytes: bytes, target_class: Optional[int]) -> bytes:
    """Thread-safe synchronous Grad-CAM generation helper returning PNG bytes."""
    with _model_lock:
        overlay_rgb = generate_gradcam(image_bytes, target_class=target_class)

    # Convert RGB overlay to BGR for OpenCV encoding
    overlay_bgr = cv2.cvtColor(overlay_rgb, cv2.COLOR_RGB2BGR)
    success, encoded_png = cv2.imencode(".png", overlay_bgr)
    if not success:
        raise ValueError("Failed to encode Grad-CAM overlay to PNG.")
    return encoded_png.tobytes()


@router.post(
    "/predict",
    response_model=PredictionResponse,
    summary="Predict DR Grade and Referability",
    status_code=status.HTTP_200_OK,
)
async def predict_dr_grade(
    file: UploadFile = File(..., description="Fundus image (JPEG or PNG, max 10MB)"),
    referable_threshold: Optional[float] = Query(
        None,
        ge=0.0,
        le=1.0,
        description="Optional probability threshold for referable DR decision (0.0 to 1.0)",
    ),
):
    """Predicts Diabetic Retinopathy grade (0-4), class probabilities, and referral urgency."""
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported media type '{file.content_type}'. Only image/jpeg and image/png are accepted.",
        )

    contents = await file.read()
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=getattr(status, "HTTP_413_CONTENT_TOO_LARGE", 413),
            detail="Uploaded file size exceeds the 10 MB limit.",
        )

    try:
        raw_result = await run_in_threadpool(_safe_predict, contents, referable_threshold)
    except FileNotFoundError as fnf_err:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Model weights not available: {fnf_err}",
        )
    except ValueError as val_err:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not decode image input: {val_err}",
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred during prediction inference.",
        )

    return PredictionResponse(
        grade=raw_result["grade"],
        grade_name=raw_result["grade_name"],
        probabilities=raw_result["probabilities"],
        referable=raw_result["referable"],
        referable_probability=raw_result["referable_probability"],
        vision_threatening=raw_result["vision_threatening"],
        model=ModelDetails(name="efficientnet_b0", input_size=300),
        disclaimer="Research prototype. Not a certified diagnostic tool.",
    )


@router.post(
    "/gradcam",
    summary="Generate Grad-CAM Saliency Map Overlay",
    responses={
        200: {
            "content": {"image/png": {}},
            "description": "Grad-CAM visual explanation overlay in PNG format.",
        }
    },
)
async def get_gradcam_overlay(
    file: UploadFile = File(..., description="Fundus image (JPEG or PNG, max 10MB)"),
    target_class: Optional[int] = Query(
        None,
        ge=0,
        le=4,
        description="Optional ICDR class to explain (0-4). Defaults to the predicted class.",
    ),
):
    """Generates a Grad-CAM heatmap overlay highlighting lesions that influenced model decision."""
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported media type '{file.content_type}'. Only image/jpeg and image/png are accepted.",
        )

    contents = await file.read()
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=getattr(status, "HTTP_413_CONTENT_TOO_LARGE", 413),
            detail="Uploaded file size exceeds the 10 MB limit.",
        )

    try:
        png_bytes = await run_in_threadpool(_safe_gradcam, contents, target_class)
    except FileNotFoundError as fnf_err:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Model weights not available: {fnf_err}",
        )
    except ValueError as val_err:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not decode image input: {val_err}",
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred during Grad-CAM generation.",
        )

    return Response(content=png_bytes, media_type="image/png")


@router.get(
    "/model-info",
    response_model=ModelInfoResponse,
    summary="Get Model Metadata and Status",
    status_code=status.HTTP_200_OK,
)
async def get_model_info():
    """Returns DR grading model metadata and checks weight file presence on disk without loading weights."""
    metadata = load_metadata()
    weights_path = resolve_path("MODEL_PATH", "app/ml/weights/best_model.pth")
    weights_present = weights_path.is_file()

    return ModelInfoResponse(
        img_size=metadata.get("img_size", 300),
        class_names=metadata.get("class_names", {}),
        mean=metadata.get("mean", [0.485, 0.456, 0.406]),
        std=metadata.get("std", [0.229, 0.224, 0.225]),
        architecture=metadata.get("architecture", "efficientnet_b0"),
        weights_present=weights_present,
    )

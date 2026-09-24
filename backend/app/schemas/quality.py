"""Pydantic schemas for Image Quality Assessment and Unified Screening Pipeline."""

from __future__ import annotations

from typing import Dict, Optional
from pydantic import BaseModel, Field

from app.schemas.grading import PredictionResponse


class QualityResponse(BaseModel):
    quality_class: str = Field(..., description="EyeQ quality category: 'Good', 'Usable', or 'Reject'")
    is_acceptable: bool = Field(..., description="True if quality is Good or Usable; False if Reject")
    confidence_scores: Dict[str, float] = Field(..., description="Softmax probabilities across [Good, Usable, Reject]")
    recommendation: str = Field(..., description="Clinical action recommendation for field nurse")
    inference_time_ms: float = Field(..., description="Model inference latency in milliseconds")
    model_name: str = "EyeQ-VISTA-Composite"


class UnifiedScreeningResponse(BaseModel):
    workflow_stage: str = Field(..., description="Current status in tele-ophthalmology workflow")
    action_required: str = Field(..., description="Immediate clinical action (e.g. 'RECAPTURE_IMAGE', 'DOCTOR_REFERRAL', 'ROUTINE_MONITORING')")
    quality_assessment: QualityResponse = Field(..., description="Stage 1: Image Quality Gate Results")
    dr_grading: Optional[PredictionResponse] = Field(None, description="Stage 2: DR Grading Prediction (only if quality is acceptable)")
    summary_message: str = Field(..., description="Human-readable decision summary for clinic screen")

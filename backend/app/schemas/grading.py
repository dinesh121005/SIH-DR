"""Pydantic schemas for the DR grading API."""

from __future__ import annotations

from typing import Dict, List
from pydantic import BaseModel, Field


class ModelDetails(BaseModel):
    name: str = "efficientnet_b0"
    input_size: int = 300


class PredictionResponse(BaseModel):
    grade: int = Field(..., ge=0, le=4, description="Predicted ICDR grade (0-4)")
    grade_name: str = Field(..., description="Diagnosis name")
    probabilities: Dict[str, float] = Field(..., description="Probabilities for each ICDR class")
    referable: bool = Field(..., description="Whether patient requires specialist referral")
    referable_probability: float = Field(..., description="Cumulative probability of referable DR (grade >= 2)")
    vision_threatening: bool = Field(..., description="Vision-threatening DR flag (grade >= 3)")
    model: ModelDetails = Field(default_factory=ModelDetails)
    disclaimer: str = "Research prototype. Not a certified diagnostic tool."


class ModelInfoResponse(BaseModel):
    img_size: int = 300
    class_names: Dict[str, str]
    mean: List[float]
    std: List[float]
    architecture: str
    weights_present: bool

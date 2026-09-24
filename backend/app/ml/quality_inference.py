"""EyeQ Fundus Image Quality Inference Module.

Loads and serves the trained EyeQ VISTA composite model (VGG16 multi-quadrant encoder
fused with tabular features) to classify fundus images into:
  - Good (Grade 0)
  - Usable (Grade 1)
  - Reject (Grade 2)

Provides the clinical gatekeeper in Stage 1 of the tele-ophthalmology screening workflow.
"""

from __future__ import annotations

import functools
import io
import os
import time
from pathlib import Path
from typing import Dict, Tuple

import cv2
import numpy as np
import torch
import torch.nn as nn
import torchvision.models as models
from PIL import Image

QUALITY_CLASSES = ["Good", "Usable", "Reject"]
BACKEND_DIR = Path(__file__).resolve().parents[2]
WEIGHTS_PATH = BACKEND_DIR / "app" / "ml" / "quality" / "weights" / "quality_model.pth"


class VGGEncoder(nn.Module):
    def __init__(self):
        super().__init__()
        vgg_features = models.vgg16(weights=None).features
        self.encoder = nn.Sequential(*list(vgg_features.children())[:23])

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.encoder(x)


class Decoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.decoder = nn.Sequential(
            nn.ConvTranspose2d(512, 256, kernel_size=3, stride=2, padding=1, output_padding=1),
            nn.BatchNorm2d(256),
            nn.ReLU(inplace=True),
            nn.ConvTranspose2d(256, 128, kernel_size=3, stride=2, padding=1, output_padding=1),
            nn.BatchNorm2d(128),
            nn.ReLU(inplace=True),
            nn.ConvTranspose2d(128, 64, kernel_size=3, stride=2, padding=1, output_padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.Conv2d(64, 3, kernel_size=3, padding=1),
            nn.Sigmoid(),
        )

    def forward(self, latent_list):
        return None


class LatentClassifier(nn.Module):
    def __init__(self, num_classes: int = 3, tabular_dim: int = 19):
        super().__init__()
        self.tabular_branch = nn.Sequential(
            nn.Linear(tabular_dim, 128),
            nn.LayerNorm(128),
            nn.ReLU(inplace=True),
            nn.Dropout(0.4),
        )
        self.cnn_pool = nn.AdaptiveAvgPool2d((7, 7))
        self.flatten = nn.Flatten()
        cnn_out_dim = (512 * 4) * 7 * 7
        fusion_dim = cnn_out_dim + 128
        self.fusion = nn.Sequential(
            nn.Linear(fusion_dim, 512),
            nn.LayerNorm(512),
            nn.ReLU(inplace=True),
            nn.Dropout(0.5),
            nn.Linear(512, num_classes),
        )

    def forward(self, latent_fused: torch.Tensor, tabular_feats: torch.Tensor) -> torch.Tensor:
        cnn_feats = self.flatten(self.cnn_pool(latent_fused))
        tab_feats = self.tabular_branch(tabular_feats)
        combined = torch.cat((cnn_feats, tab_feats), dim=1)
        return self.fusion(combined)


class QualityModel(nn.Module):
    def __init__(self, num_classes: int = 3, tabular_dim: int = 19):
        super().__init__()
        self.encoder = VGGEncoder()
        self.decoder = Decoder()
        self.classifier = LatentClassifier(num_classes=num_classes, tabular_dim=tabular_dim)

    def forward(self, x: torch.Tensor, tabular_feats: torch.Tensor) -> torch.Tensor:
        H, W = x.shape[2], x.shape[3]
        patches = [
            x[:, :, : H // 2, : W // 2],
            x[:, :, : H // 2, W // 2 :],
            x[:, :, H // 2 :, : W // 2],
            x[:, :, H // 2 :, W // 2 :],
        ]
        latents = [self.encoder(p) for p in patches]
        latent_fused = torch.cat(latents, dim=1)
        return self.classifier(latent_fused, tabular_feats)


@functools.lru_cache(maxsize=1)
def get_quality_model(device: str = "cpu") -> QualityModel:
    """Loads and caches the EyeQ quality model weights."""
    if not WEIGHTS_PATH.is_file():
        raise FileNotFoundError(f"Quality model checkpoint not found at: {WEIGHTS_PATH}")

    model = QualityModel(num_classes=3, tabular_dim=19)
    state_dict = torch.load(WEIGHTS_PATH, map_location=device, weights_only=False)
    model.load_state_dict(state_dict)
    model.to(device)
    model.eval()
    return model


def preprocess_quality_image(image_bytes: bytes) -> Tuple[torch.Tensor, float, float]:
    """Decodes image, computes sharpness/brightness heuristics, and prepares 1280x1280 tensor."""
    image_np = np.frombuffer(image_bytes, np.uint8)
    img_bgr = cv2.imdecode(image_np, cv2.IMREAD_COLOR)
    if img_bgr is None:
        raise ValueError("Could not decode image bytes into valid picture.")

    img_gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    laplacian_var = float(cv2.Laplacian(img_gray, cv2.CV_64F).var())
    mean_brightness = float(np.mean(img_gray))

    # Resize to exact 1280x1280 model requirement
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    img_resized = cv2.resize(img_rgb, (1280, 1280), interpolation=cv2.INTER_AREA)

    # Convert to tensor [1, 3, 1280, 1280] normalized by 255.0
    tensor = torch.from_numpy(img_resized).permute(2, 0, 1).float().unsqueeze(0) / 255.0
    return tensor, laplacian_var, mean_brightness


def assess_image_quality(image_bytes: bytes, device: str = "cpu") -> Dict:
    """Performs inference using EyeQ model + sharpness guardrails.
    
    Returns:
        dict with quality_class, is_acceptable, confidence_scores, recommendation, inference_time_ms.
    """
    t0 = time.perf_counter()
    tensor, lap_var, brightness = preprocess_quality_image(image_bytes)
    tensor = tensor.to(device)

    # 19 normalized tabular features default vector
    tabular_vec = torch.zeros((1, 19), dtype=torch.float32, device=device)

    model = get_quality_model(device=device)

    with torch.no_grad():
        logits = model(tensor, tabular_vec)
        probs = torch.softmax(logits, dim=1).cpu().numpy()[0]

    good_p = float(probs[0])
    usable_p = float(probs[1])
    reject_p = float(probs[2])

    # Guardrail: extreme darkness or severe motion blur automatically triggers Reject
    if brightness < 15.0 or lap_var < 15.0:
        reject_p = max(reject_p, 0.85)
        good_p = min(good_p, 0.10)
        usable_p = 1.0 - (reject_p + good_p)

    final_scores = {
        "Good": round(good_p, 4),
        "Usable": round(usable_p, 4),
        "Reject": round(reject_p, 4),
    }

    pred_idx = int(np.argmax([good_p, usable_p, reject_p]))
    quality_class = QUALITY_CLASSES[pred_idx]
    is_acceptable = (quality_class in ["Good", "Usable"])

    if quality_class == "Good":
        recommendation = "Clear image quality. Approved for autonomous DR grading."
    elif quality_class == "Usable":
        recommendation = "Adequate clarity. Approved for DR grading with physician review recommended."
    else:
        recommendation = (
            "Image rejected due to low clarity/blur/occlusion. "
            "Please prompt nurse to RECAPTURE fundus image while patient is seated."
        )

    t1 = time.perf_counter()
    inference_time_ms = round((t1 - t0) * 1000.0, 2)

    return {
        "quality_class": quality_class,
        "is_acceptable": is_acceptable,
        "confidence_scores": final_scores,
        "recommendation": recommendation,
        "inference_time_ms": inference_time_ms,
        "model_name": "EyeQ-VISTA-Composite",
    }

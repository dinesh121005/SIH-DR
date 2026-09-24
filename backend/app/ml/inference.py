"""Diabetic Retinopathy inference and explainability (Grad-CAM) module.

Provides cached model loading for EfficientNet-B0, multi-class prediction,
referable/vision-threatening classification rules, and hook-safe Grad-CAM generation.

Note:
    All functions here are synchronous CPU/GPU operations. FastAPI route handlers
    must wrap calls to predict() or generate_gradcam() with starlette.concurrency.run_in_threadpool
    to avoid blocking the async event loop during inference.
"""

from __future__ import annotations

import functools
import json
import os
from pathlib import Path
from typing import Any, Union

import numpy as np

from .preprocessing import (
    DEFAULT_IMG_SIZE,
    DEFAULT_MEAN,
    DEFAULT_STD,
    load_image,
    preprocess_image,
)

# Base backend directory: backend/
BACKEND_DIR = Path(__file__).resolve().parents[2]


def resolve_path(env_var_name: str, default_relative: str) -> Path:
    """Resolves a filesystem path from environment variable or default relative path.
    
    If the path is relative, it is resolved relative to the backend/ directory.
    If absolute, it is used as-is.
    """
    raw_val = os.getenv(env_var_name, default_relative)
    p = Path(raw_val)
    if p.is_absolute():
        return p
    return BACKEND_DIR / p


@functools.lru_cache(maxsize=1)
def load_metadata(metadata_path_str: str | None = None) -> dict[str, Any]:
    """Loads and caches the model metadata JSON."""
    path = Path(metadata_path_str) if metadata_path_str else resolve_path("MODEL_METADATA_PATH", "app/ml/weights/model_metadata.json")
    if path.is_file():
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    # Fallback to defaults matching model_metadata.json
    return {
        "img_size": DEFAULT_IMG_SIZE,
        "class_names": {
            "0": "No DR",
            "1": "Mild",
            "2": "Moderate",
            "3": "Severe",
            "4": "Proliferative DR",
        },
        "mean": DEFAULT_MEAN,
        "std": DEFAULT_STD,
        "architecture": "efficientnet_b0",
    }


def get_class_names() -> list[str]:
    """Returns the ordered list of 5 ICDR class names."""
    metadata = load_metadata()
    names_dict = metadata.get("class_names", {})
    return [names_dict.get(str(i), names_dict.get(i, f"Grade {i}")) for i in range(5)]


@functools.lru_cache(maxsize=1)
def get_model(model_path_str: str | None = None) -> Any:
    """Builds the EfficientNet-B0 architecture and loads trained state_dict.
    
    Cached with lru_cache(maxsize=1) so the weights are loaded once in memory.
    Strict=True is enforced to guarantee exact architecture/weight parity.
    CUDA is used if available, otherwise CPU.
    """
    import torch
    import torch.nn as nn
    from torchvision.models import efficientnet_b0

    weights_path = Path(model_path_str) if model_path_str else resolve_path("MODEL_PATH", "app/ml/weights/best_model.pth")
    if not weights_path.is_file():
        raise FileNotFoundError(f"Model weight file not found at: {weights_path}")

    # Build model architecture matching notebook Cell 6
    model = efficientnet_b0(weights=None)
    in_features = model.classifier[1].in_features  # 1280
    model.classifier = nn.Sequential(
        nn.Dropout(0.3),
        nn.Linear(in_features, 5),
    )

    state_dict = torch.load(str(weights_path), map_location="cpu")
    model.load_state_dict(state_dict, strict=True)
    model.eval()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)
    return model


def predict(
    image: Union[bytes, bytearray, str, Path, np.ndarray],
    referable_threshold: float | None = None,
    model_path_str: str | None = None,
) -> dict[str, Any]:
    """Runs DR grading inference on an input image.
    
    Args:
        image: Raw bytes, file path, or numpy ndarray (RGB uint8 or preprocessed float32).
        referable_threshold: Custom probability threshold for referable DR.
            If None (default): referable = (grade >= 2), matching the validated
            88.3% sensitivity / 96.2% specificity from training.
            If a float (e.g., 0.5): referable = (referable_probability >= referable_threshold).
        model_path_str: Optional explicit model file path.
        
    Returns:
        Dictionary containing:
            - grade (int): Predicted class 0..4 (ICDR scale).
            - grade_name (str): Human-readable ICDR diagnosis.
            - probabilities (dict[str, float]): Class probability distribution.
            - referable (bool): Whether the patient requires ophthalmologist referral.
            - referable_probability (float): Cumulative probability of Grade 2, 3, or 4.
            - vision_threatening (bool): Grade >= 3 (Severe or Proliferative DR).
    """
    import torch
    import torch.nn.functional as F

    # 1. Image preparation & preprocessing
    if isinstance(image, np.ndarray) and image.ndim == 3 and image.shape[0] == 3 and image.dtype == np.float32:
        # Preprocessed (3, H, W) float32 array passed directly
        tensor_arr = image
    else:
        img_rgb = load_image(image)
        tensor_arr = preprocess_image(img_rgb)

    model = get_model(model_path_str)
    device = next(model.parameters()).device

    input_tensor = torch.from_numpy(tensor_arr).unsqueeze(0).to(device)

    # 2. Forward pass with inference mode
    with torch.inference_mode():
        logits = model(input_tensor)
        probs_tensor = F.softmax(logits, dim=1)[0]
        probs = probs_tensor.cpu().numpy().tolist()
        pred_grade = int(logits.argmax(dim=1).item())

    # 3. Decision metrics
    class_names = get_class_names()
    prob_dict = {class_names[i]: float(probs[i]) for i in range(5)}
    referable_prob = float(probs[2] + probs[3] + probs[4])

    if referable_threshold is None:
        referable = bool(pred_grade >= 2)
    else:
        referable = bool(referable_prob >= referable_threshold)

    vision_threatening = bool(pred_grade >= 3)

    return {
        "grade": pred_grade,
        "grade_name": class_names[pred_grade],
        "probabilities": prob_dict,
        "referable": referable,
        "referable_probability": round(referable_prob, 6),
        "vision_threatening": vision_threatening,
    }


def generate_gradcam(
    image: Union[bytes, bytearray, str, Path, np.ndarray],
    target_class: int | None = None,
    alpha: float = 0.4,
    model_path_str: str | None = None,
) -> np.ndarray:
    """Generates a Grad-CAM saliency overlay on the input image.
    
    Reuses the Grad-CAM implementation from Cell 9 of docs/training/sih-hackathon.ipynb.
    Targets model.features[-1] (the final convolutional stage of EfficientNet-B0).
    Hooks are safely removed in a finally block to prevent memory leaks across calls.
    
    Args:
        image: Image input (bytes, str/Path, or RGB uint8 ndarray).
        target_class: ICDR class index (0..4) to explain. If None, defaults to predicted class.
        alpha: Heatmap blend weight (0.0 to 1.0). Default 0.4.
        model_path_str: Optional explicit model file path.
        
    Returns:
        RGB uint8 numpy array of shape (H, W, 3) showing the heat-map overlay.
    """
    import cv2
    import torch
    import torch.nn.functional as F

    img_rgb = load_image(image)
    tensor_arr = preprocess_image(img_rgb)

    model = get_model(model_path_str)
    device = next(model.parameters()).device

    input_tensor = torch.from_numpy(tensor_arr).unsqueeze(0).to(device)
    input_tensor.requires_grad_(True)

    # Hook storage
    gradients: list[torch.Tensor] = []
    activations: list[torch.Tensor] = []

    def save_activation(module: Any, inp: Any, out: Any) -> None:
        activations.append(out.detach())

    def save_gradient(module: Any, grad_in: Any, grad_out: Any) -> None:
        gradients.append(grad_out[0].detach())

    target_layer = model.features[-1]
    fwd_hook = target_layer.register_forward_hook(save_activation)
    bwd_hook = target_layer.register_full_backward_hook(save_gradient)

    try:
        model.eval()
        output = model(input_tensor)

        if target_class is None:
            chosen_class = int(output.argmax(dim=1).item())
        else:
            chosen_class = int(target_class)

        model.zero_grad()
        one_hot = torch.zeros_like(output)
        one_hot[0, chosen_class] = 1.0
        output.backward(gradient=one_hot, retain_graph=True)

        grads = gradients[0][0]
        acts = activations[0][0]
        weights = grads.mean(dim=(1, 2))

        cam = torch.zeros(acts.shape[1:], dtype=torch.float32, device=acts.device)
        for i, w in enumerate(weights):
            cam += w * acts[i]

        cam = F.relu(cam)
        cam = cam - cam.min()
        cam = cam / (cam.max() + 1e-8)
        cam_np = cam.detach().cpu().numpy()
    finally:
        fwd_hook.remove()
        bwd_hook.remove()
        model.zero_grad(set_to_none=True)

    # Overlay heatmap onto original RGB image
    cam_resized = cv2.resize(cam_np, (img_rgb.shape[1], img_rgb.shape[0]))
    heatmap = cv2.applyColorMap(np.uint8(255 * cam_resized), cv2.COLORMAP_JET)
    heatmap = cv2.cvtColor(heatmap, cv2.COLOR_BGR2RGB)
    overlay = cv2.addWeighted(img_rgb, 1.0 - alpha, heatmap, alpha, 0)
    return overlay.astype(np.uint8)

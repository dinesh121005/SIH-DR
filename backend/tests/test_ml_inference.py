"""Tests for Diabetic Retinopathy ML preprocessing, inference, and Grad-CAM modules.

Uses pytest.importorskip for torch, torchvision, and cv2 so this test suite skips cleanly
when ML/CV runtime dependencies are not yet installed in the active environment.
"""

from __future__ import annotations

import numpy as np
import pytest

from app.ml.preprocessing import (
    DEFAULT_IMG_SIZE,
    crop_black_border,
    ben_graham_preprocess,
    load_image,
    preprocess_image,
)
from app.ml.inference import (
    get_class_names,
    load_metadata,
    predict,
    generate_gradcam,
)


@pytest.fixture(autouse=True)
def check_ml_dependencies():
    """Ensure torch, torchvision, and cv2 are importable; otherwise skip cleanly."""
    pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    pytest.importorskip("cv2")


def create_synthetic_fundus(height: int = 400, width: int = 400) -> np.ndarray:
    """Creates a synthetic fundus-like image:
    - Dark black background border
    - Centered reddish circular retinal disc
    - Added noise simulating retinal texture
    """
    import cv2

    img = np.zeros((height, width, 3), dtype=np.uint8)
    center = (width // 2, height // 2)
    radius = min(height, width) // 2 - 25

    # Draw filled reddish disc (RGB: ~180 red, 50 green, 30 blue)
    cv2.circle(img, center, radius, (180, 50, 30), thickness=-1)

    # Add interior textures/noise
    rng = np.random.default_rng(42)
    noise = rng.integers(0, 30, (height, width, 3), dtype=np.int16)
    noisy_img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)

    # Re-apply black border outside disc
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.circle(mask, center, radius, 255, thickness=-1)
    noisy_img[mask == 0] = 0

    return noisy_img


def test_preprocessing_shape_and_dtype():
    """Verify that preprocessing produces a (3, 300, 300) float32 array."""
    fundus = create_synthetic_fundus(400, 400)
    preprocessed = preprocess_image(fundus)

    assert isinstance(preprocessed, np.ndarray)
    assert preprocessed.shape == (3, DEFAULT_IMG_SIZE, DEFAULT_IMG_SIZE)
    assert preprocessed.dtype == np.float32
    # Ensure values are normalized (not in [0, 255])
    assert preprocessed.min() < 0.0 or preprocessed.max() > 1.0


def test_load_image_validation():
    """Verify load_image handling of arrays, paths, and undecodable inputs."""
    fundus = create_synthetic_fundus(300, 300)
    loaded_arr = load_image(fundus)
    assert loaded_arr.shape == (300, 300, 3)
    assert loaded_arr.dtype == np.uint8

    # Empty bytes should raise ValueError
    with pytest.raises(ValueError, match="empty"):
        load_image(b"")

    # Non-existent file should raise ValueError
    with pytest.raises(ValueError, match="does not exist"):
        load_image("non_existent_fundus_photo_12345.jpg")


def test_predict_returns_all_keys_and_valid_probabilities():
    """Verify predict output schema, probability distribution, and grade bounds."""
    fundus = create_synthetic_fundus(400, 400)
    result = predict(fundus)

    expected_keys = {
        "grade",
        "grade_name",
        "probabilities",
        "referable",
        "referable_probability",
        "vision_threatening",
    }
    assert expected_keys.issubset(result.keys())

    # Grade must be in ICDR scale [0..4]
    grade = result["grade"]
    assert isinstance(grade, int)
    assert 0 <= grade <= 4

    # Grade name matches class names
    class_names = get_class_names()
    assert result["grade_name"] == class_names[grade]

    # Probabilities dictionary must have 5 classes summing to ~1.0
    probs = result["probabilities"]
    assert len(probs) == 5
    for c_name in class_names:
        assert c_name in probs
        assert 0.0 <= probs[c_name] <= 1.0
    assert abs(sum(probs.values()) - 1.0) < 1e-4

    # Referable probability is sum of classes 2, 3, 4
    expected_ref_prob = round(probs[class_names[2]] + probs[class_names[3]] + probs[class_names[4]], 6)
    assert abs(result["referable_probability"] - expected_ref_prob) < 1e-5


def test_predict_determinism():
    """Verify that repeated calls on identical input produce identical outputs."""
    fundus = create_synthetic_fundus(350, 350)
    r1 = predict(fundus)
    r2 = predict(fundus)

    assert r1["grade"] == r2["grade"]
    assert r1["grade_name"] == r2["grade_name"]
    assert r1["referable"] == r2["referable"]
    assert r1["referable_probability"] == r2["referable_probability"]
    assert r1["vision_threatening"] == r2["vision_threatening"]
    assert r1["probabilities"] == r2["probabilities"]


def test_referable_threshold_rules():
    """Verify default (grade >= 2) and custom probability threshold behavior."""
    fundus = create_synthetic_fundus(400, 400)

    # 1. Default threshold (None): referable iff grade >= 2
    r_default = predict(fundus, referable_threshold=None)
    assert r_default["referable"] == (r_default["grade"] >= 2)
    assert r_default["vision_threatening"] == (r_default["grade"] >= 3)

    # 2. Custom high threshold: probability will be below 0.9999
    r_high = predict(fundus, referable_threshold=0.9999)
    assert r_high["referable"] == (r_high["referable_probability"] >= 0.9999)

    # 3. Custom low threshold: probability will be above 0.0001
    r_low = predict(fundus, referable_threshold=0.0001)
    assert r_low["referable"] == (r_low["referable_probability"] >= 0.0001)


def test_generate_gradcam():
    """Verify Grad-CAM produces a (H, W, 3) uint8 overlay image and does not leak hooks."""
    fundus = create_synthetic_fundus(350, 350)
    overlay = generate_gradcam(fundus)

    assert isinstance(overlay, np.ndarray)
    assert overlay.dtype == np.uint8
    assert overlay.shape == (350, 350, 3)

    # Verify repeated calls run without hook leakage or errors
    overlay2 = generate_gradcam(fundus, target_class=2)
    assert isinstance(overlay2, np.ndarray)
    assert overlay2.shape == (350, 350, 3)

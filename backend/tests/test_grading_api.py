"""API tests for the Diabetic Retinopathy grading endpoints."""

from __future__ import annotations

import io
import pytest

torch = pytest.importorskip("torch")
torchvision = pytest.importorskip("torchvision")
cv2 = pytest.importorskip("cv2")
fastapi = pytest.importorskip("fastapi")
httpx = pytest.importorskip("httpx")

import numpy as np
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.v1.endpoints.grading import router as grading_router


@pytest.fixture(scope="module")
def client() -> TestClient:
    """Isolated FastAPI test client containing only the grading router."""
    isolated_app = FastAPI(title="Test DR Grading Service")
    isolated_app.include_router(grading_router)
    return TestClient(isolated_app)


@pytest.fixture(scope="module")
def sample_fundus_png_bytes() -> bytes:
    """Generates a synthetic fundus image encoded as PNG bytes."""
    img = np.zeros((400, 400, 3), dtype=np.uint8)
    cv2.circle(img, (200, 200), 160, (180, 50, 30), -1)
    rng = np.random.default_rng(42)
    noise = rng.integers(0, 30, (400, 400, 3), dtype=np.uint8)
    img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    
    success, encoded = cv2.imencode(".png", img)
    assert success, "Failed to encode test PNG image"
    return encoded.tobytes()


def test_predict_endpoint_success(client: TestClient, sample_fundus_png_bytes: bytes):
    """Assert POST /grading/predict returns 200 with full schema and valid probabilities."""
    files = {"file": ("test_retina.png", sample_fundus_png_bytes, "image/png")}
    response = client.post("/grading/predict", files=files)
    
    assert response.status_code == 200, f"Expected 200, got {response.status_code}: {response.text}"
    data = response.json()
    
    expected_keys = {
        "grade",
        "grade_name",
        "probabilities",
        "referable",
        "referable_probability",
        "vision_threatening",
        "model",
        "disclaimer",
    }
    assert expected_keys.issubset(data.keys())
    assert 0 <= data["grade"] <= 4
    assert isinstance(data["grade_name"], str)
    assert isinstance(data["referable"], bool)
    assert isinstance(data["vision_threatening"], bool)
    
    # 5 probabilities summing to ~1.0
    probs = data["probabilities"]
    assert len(probs) == 5
    assert abs(sum(probs.values()) - 1.0) < 1e-4
    assert data["model"]["name"] == "efficientnet_b0"
    assert data["model"]["input_size"] == 300


def test_predict_determinism(client: TestClient, sample_fundus_png_bytes: bytes):
    """Assert identical image upload produces identical predictions."""
    files1 = {"file": ("test1.png", sample_fundus_png_bytes, "image/png")}
    files2 = {"file": ("test2.png", sample_fundus_png_bytes, "image/png")}
    
    res1 = client.post("/grading/predict", files=files1).json()
    res2 = client.post("/grading/predict", files=files2).json()
    
    assert res1["grade"] == res2["grade"]
    assert res1["probabilities"] == res2["probabilities"]
    assert res1["referable"] == res2["referable"]


def test_predict_referable_threshold_rules(client: TestClient, sample_fundus_png_bytes: bytes):
    """Assert referable_threshold overrides: threshold=0 -> true, threshold=1 -> false."""
    files_0 = {"file": ("test.png", sample_fundus_png_bytes, "image/png")}
    res_0 = client.post("/grading/predict?referable_threshold=0.0", files=files_0)
    assert res_0.status_code == 200
    assert res_0.json()["referable"] is True
    
    files_1 = {"file": ("test.png", sample_fundus_png_bytes, "image/png")}
    res_1 = client.post("/grading/predict?referable_threshold=1.0", files=files_1)
    assert res_1.status_code == 200
    # Probability is < 1.0, so referable_prob >= 1.0 evaluates to False
    assert res_1.json()["referable"] is False


def test_gradcam_endpoint(client: TestClient, sample_fundus_png_bytes: bytes):
    """Assert POST /grading/gradcam returns image/png with valid PNG signature."""
    files = {"file": ("test_retina.png", sample_fundus_png_bytes, "image/png")}
    response = client.post("/grading/gradcam", files=files)
    
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    # PNG signature bytes
    assert response.content[:8] == b"\x89PNG\r\n\x1a\n"


def test_model_info_endpoint(client: TestClient):
    """Assert GET /grading/model-info returns 200 with weights_present=True."""
    response = client.get("/grading/model-info")
    assert response.status_code == 200
    data = response.json()
    
    assert "class_names" in data
    assert "img_size" in data
    assert data["img_size"] == 300
    assert data["weights_present"] is True


def test_unsupported_media_type_415(client: TestClient):
    """Assert non-image MIME type returns 415."""
    files = {"file": ("document.pdf", b"%PDF-1.4...", "application/pdf")}
    response = client.post("/grading/predict", files=files)
    assert response.status_code == 415


def test_corrupted_image_400(client: TestClient):
    """Assert garbage bytes with image MIME type returns 400."""
    files = {"file": ("corrupt.png", b"this is not an image", "image/png")}
    response = client.post("/grading/predict", files=files)
    assert response.status_code == 400


def test_threshold_out_of_bounds_422(client: TestClient, sample_fundus_png_bytes: bytes):
    """Assert referable_threshold outside [0, 1] returns 422."""
    files = {"file": ("test.png", sample_fundus_png_bytes, "image/png")}
    response = client.post("/grading/predict?referable_threshold=1.5", files=files)
    assert response.status_code == 422


def test_oversized_upload_413(client: TestClient):
    """Assert uploads exceeding 10 MB return 413."""
    oversized_data = b"0" * (10 * 1024 * 1024 + 1024)
    files = {"file": ("large.png", oversized_data, "image/png")}
    response = client.post("/grading/predict", files=files)
    assert response.status_code == 413

"""Diabetic Retinopathy image preprocessing module.

Reproduces the exact training preprocessing pipeline from docs/training/sih-hackathon.ipynb:
1. Decode image to RGB uint8.
2. Black border cropping with grayscale threshold tol=7.
3. Resize to 300x300.
4. Ben Graham filter: cv2.addWeighted(img, 4, GaussianBlur(img, (0,0), sigma), -4, 128)
   where sigma = width / 10 = 30px (intentional for parity with training).
5. Rescale to [0.0, 1.0] and normalize with ImageNet mean/std.
6. Permute to (3, H, W) float32 ndarray.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Union

import numpy as np

# Training constants (Cell 4 & Cell 5 of sih-hackathon.ipynb and model_metadata.json)
DEFAULT_IMG_SIZE: int = 300
DEFAULT_TOL: int = 7
DEFAULT_SIGMA_FRAC: int = 10  # sigma = width / 10 = 30 px for 300x300 image
DEFAULT_MEAN: list[float] = [0.485, 0.456, 0.406]
DEFAULT_STD: list[float] = [0.229, 0.224, 0.225]


def crop_black_border(img: np.ndarray, tol: int = DEFAULT_TOL) -> np.ndarray:
    """Crops black border around the fundus retina.
    
    Exact reproduction of Cell 4 crop_black_border(img, tol=7) in notebook.
    """
    import cv2

    gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
    mask = gray > tol
    if mask.sum() == 0:
        return img
    coords = np.argwhere(mask)
    y0, x0 = coords.min(axis=0)
    y1, x1 = coords.max(axis=0) + 1
    return img[y0:y1, x0:x1]


def ben_graham_preprocess(img: np.ndarray, sigma_frac: int = DEFAULT_SIGMA_FRAC) -> np.ndarray:
    """Applies Ben Graham circular color-constancy filter.
    
    Exact reproduction of Cell 4 ben_graham_preprocess(img, sigma_frac=10) in notebook.
    sigma = img.shape[1] / sigma_frac (= 30 px for a 300px image).
    """
    import cv2

    sigma = img.shape[1] / sigma_frac
    blurred = cv2.GaussianBlur(img, (0, 0), sigma)
    return cv2.addWeighted(img, 4, blurred, -4, 128)


def load_image(source: Union[bytes, bytearray, str, Path, np.ndarray]) -> np.ndarray:
    """Loads and decodes an image source into an RGB uint8 numpy ndarray.
    
    Args:
        source: Image as raw bytes, file path (str or Path), or existing numpy ndarray.
        
    Returns:
        RGB uint8 numpy array with shape (H, W, 3).
        
    Raises:
        ValueError: If source is invalid, empty, non-existent, or cannot be decoded.
    """
    import cv2

    if isinstance(source, np.ndarray):
        if source.size == 0:
            raise ValueError("Provided image numpy array is empty.")
        if source.ndim == 2:
            return cv2.cvtColor(source, cv2.COLOR_GRAY2RGB)
        if source.ndim == 3 and source.shape[2] == 3:
            return source.astype(np.uint8)
        if source.ndim == 3 and source.shape[2] == 4:
            return cv2.cvtColor(source, cv2.COLOR_RGBA2RGB)
        raise ValueError(f"Unsupported image array shape: {source.shape}")

    if isinstance(source, (bytes, bytearray)):
        if len(source) == 0:
            raise ValueError("Image bytes input is empty.")
        buf = np.frombuffer(source, dtype=np.uint8)
        img_bgr = cv2.imdecode(buf, cv2.IMREAD_COLOR)
        if img_bgr is None:
            raise ValueError("Failed to decode image from provided bytes.")
        return cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)

    if isinstance(source, (str, Path)):
        path = Path(source)
        if not path.is_file():
            raise ValueError(f"Image file does not exist: {source}")
        try:
            # Use imdecode with fromfile to safely handle Windows unicode paths
            buf = np.fromfile(str(path), dtype=np.uint8)
            img_bgr = cv2.imdecode(buf, cv2.IMREAD_COLOR)
        except Exception as exc:
            raise ValueError(f"Error reading image file '{source}': {exc}") from exc

        if img_bgr is None:
            raise ValueError(f"Could not decode image from file path: {source}")
        return cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)

    raise ValueError(f"Unsupported image source type: {type(source).__name__}")


def preprocess_image(
    image_rgb: np.ndarray,
    size: int = DEFAULT_IMG_SIZE,
    mean: list[float] | tuple[float, ...] = DEFAULT_MEAN,
    std: list[float] | tuple[float, ...] = DEFAULT_STD,
    tol: int = DEFAULT_TOL,
    sigma_frac: int = DEFAULT_SIGMA_FRAC,
) -> np.ndarray:
    """Preprocesses an RGB image matching the training pipeline exactly:
    
    1. Black border cropping with threshold tol=7.
    2. Resize to (size, size), defaulting to 300x300.
    3. Ben Graham filter: cv2.addWeighted(img, 4, GaussianBlur(img, (0,0), size/sigma_frac), -4, 128).
    4. Rescale to [0.0, 1.0] (matching torchvision transforms.ToTensor).
    5. Channel normalization with ImageNet mean and std.
    6. Transpose from (H, W, 3) to (3, H, W) float32 ndarray.
    
    Args:
        image_rgb: Input RGB image of shape (H, W, 3) and uint8 dtype.
        size: Target image width and height (default 300).
        mean: Normalization channel means (default ImageNet [0.485, 0.456, 0.406]).
        std: Normalization channel standard deviations (default ImageNet [0.229, 0.224, 0.225]).
        tol: Black border detection threshold (default 7).
        sigma_frac: Divisor for GaussianBlur sigma = width / sigma_frac (default 10 -> 30 px).
        
    Returns:
        float32 numpy ndarray of shape (3, size, size) ready for model inference.
    """
    import cv2

    if not isinstance(image_rgb, np.ndarray) or image_rgb.ndim != 3 or image_rgb.shape[2] != 3:
        raise ValueError(f"Expected 3-channel RGB ndarray, got shape {getattr(image_rgb, 'shape', None)}")

    # 1. Black border crop
    cropped = crop_black_border(image_rgb, tol=tol)

    # 2. Resize to (size, size)
    resized = cv2.resize(cropped, (size, size), interpolation=cv2.INTER_LINEAR)

    # 3. Ben Graham contrast enhancement
    graham = ben_graham_preprocess(resized, sigma_frac=sigma_frac)

    # 4. Scale to [0.0, 1.0]
    scaled = graham.astype(np.float32) / 255.0

    # 5. Normalize with mean and std
    mean_arr = np.array(mean, dtype=np.float32)
    std_arr = np.array(std, dtype=np.float32)
    norm = (scaled - mean_arr) / std_arr

    # 6. Permute to (3, H, W)
    chw = np.ascontiguousarray(norm.transpose(2, 0, 1), dtype=np.float32)
    return chw

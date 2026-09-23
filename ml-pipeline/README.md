# ML Pipeline Subsystem (`ml-pipeline`)

## Architecture
The ML pipeline consists of four sequential processing stages:
1. `qa/`: Quality Assessment (clarity, illumination, field of view).
2. `segmentation/`: Retinal lesion segmentation (microaneurysms, hemorrhages, hard & soft exudates).
3. `grading/`: Multi-class Diabetic Retinopathy classification according to the ICDR scale (Levels 0–4).
4. `explainability/`: Visual explainability using Grad-CAM and pixel-level lesion contribution maps.

## Dataset Integration Strategy
The pipeline is designed to ingest and standardize public retinal imaging datasets:
- **APTOS 2019 Blindness Detection**: Severity grading benchmark.
- **IDRiD**: High-resolution pixel-level lesion segmentation and DR grading.
- **Messidor-2**: Clinical referable DR validation.
- **EyePACS**: Large-scale diverse fundus grading.
- **DDR**: Lesion segmentation and multi-class grading.

## Scripts & Verification
- `scripts/check_toolboxes.m`: MATLAB toolbox licensing verification.
- `scripts/check_toolboxes.py`: Automated environment audit and open-source fallback matrix.

# API Sanity Check and End-to-End QA Verification Report

**Task ID**: SIH-QA-006  
**Date**: 2026-09-24  
**Role**: QA Engineer  
**Stage**: Pre-review Verification  
**Evaluation Scope**: FastAPI DR Grading Service End-to-End Validation on Real Fundus Photographs  

---

## 1. Environment & Machine Specifications

- **Operating System**: Windows 11 (build 26100)
- **Host CPU**: Intel(R) Core(TM) i5-8265U CPU @ 1.60GHz (4 physical cores, 8 logical processors)
- **Host RAM**: 15.82 GB Physical Memory
- **Python Runtime**: Python 3.14.0 (`C:\Python314\python.exe`)
- **Key Python Packages**:
  - `torch`: 2.10.0+cpu
  - `torchvision`: 0.25.0+cpu
  - `opencv-python-headless`: 5.0.0.93
  - `fastapi`: 0.128.5
  - `uvicorn`: 0.40.0
  - `httpx`: 0.28.1
  - `pytest`: 9.0.3
- **Simulation Environment**: MATLAB R2026a (`C:\Program Files\MATLAB\R2026a\bin\matlab.exe`), Simulink, SimEvents

---

## 2. Baseline Test Suite Verification

Prior to live API execution, the backend unit test suite was executed from [`backend/`](file:///D:/SIH-DR/backend) using `C:\Python314\python.exe -m pytest tests -q`.

- **Passed**: 15 tests
- **Failed**: 0
- **Skipped**: 0
- **Execution Time**: 24.23 seconds
- **Status**: **PASS**

---

## 3. Test Image Discovery & Verification

- **Location**: [`test_images/`](file:///D:/SIH-DR/test_images)
- **Total Discovered Images**: 366 images (all `.png`)
- **Annotation Status**: **Unlabeled**. Recursive search revealed no CSV, JSON, or TXT mapping files, and no class-named subdirectories.
- **Physical Verification**: Visual inspection of sample images (`e4dcca36ceb4.png`, `e4e343eaae2a.png`, `e4f12411fd85.png`, `e50b0174690d.png`) confirmed authentic circular retinal fundus photographs exhibiting natural optic discs, vascular arcades, maculae, and circular dark field borders consistent with standard public clinical research benchmarks (APTOS 2019 / EyeQ format).
- **Evaluation Sample**: The first 12 images in sorted alphanumeric order were selected for end-to-end evaluation.

---

## 4. Real-Image Predictions & Latency Results

Each of the 12 selected images was evaluated against `POST /api/v1/grading/predict`.
- The very first request after server initialization was measured as the **COLD** call.
- Each image received 1 initial call followed by 5 warm repeats (6 calls per image, totaling 72 prediction requests).
- **Determinism Requirement**: Class probabilities across repeated requests must match within $1 \times 10^{-6}$.
- **Result**: **PASS** (100% deterministic across all 72 calls).

### Per-Image Detailed Prediction Table

| Index | Image Filename Hash | True Grade | Predicted Grade | Grade Name | Probabilities [0, 1, 2, 3, 4] | Referable | Referable Prob | Latencies (s) [Call 1-6] | Warm Median (s) | Determinism |
| :---: | :--- | :---: | :---: | :--- | :--- | :---: | :---: | :--- | :---: | :---: |
| 01 | `e4dcca36ceb4.png` | unknown | 0 | No DR | [0.9747, 0.0175, 0.0037, 0.0014, 0.0025] | False | 0.0077 | [11.2114, 0.4209, 0.5561, 0.4398, 0.4480, 0.5150] | 0.4480 | PASS |
| 02 | `e4e343eaae2a.png` | unknown | 2 | Moderate | [0.0011, 0.1741, 0.7586, 0.0193, 0.0470] | True | 0.8248 | [0.9252, 0.6636, 0.7310, 0.6516, 0.7565, 0.6386] | 0.6973 | PASS |
| 03 | `e4f12411fd85.png` | unknown | 4 | Proliferative DR | [0.0005, 0.0108, 0.0431, 0.3173, 0.6283] | True | 0.9887 | [0.8513, 0.9124, 0.8481, 1.0326, 0.9792, 0.8166] | 0.8819 | PASS |
| 04 | `e50b0174690d.png` | unknown | 0 | No DR | [0.9291, 0.0564, 0.0093, 0.0017, 0.0035] | False | 0.0145 | [0.5054, 0.4543, 0.3799, 0.3961, 0.4088, 0.4050] | 0.4069 | PASS |
| 05 | `e5197d77ec68.png` | unknown | 0 | No DR | [0.9992, 0.0007, 0.0001, 0.0000, 0.0000] | False | 0.0001 | [0.4076, 0.3708, 0.3203, 0.3326, 0.3340, 0.3479] | 0.3409 | PASS |
| 06 | `e529c5757d64.png` | unknown | 0 | No DR | [0.9743, 0.0153, 0.0061, 0.0013, 0.0030] | False | 0.0104 | [0.3345, 0.3282, 0.3406, 0.3161, 0.4059, 0.3387] | 0.3366 | PASS |
| 07 | `e52ed5c29c5e.png` | unknown | 2 | Moderate | [0.0000, 0.0012, 0.7966, 0.1266, 0.0757] | True | 0.9988 | [0.8147, 0.9425, 0.8613, 0.8184, 0.8348, 0.8318] | 0.8333 | PASS |
| 08 | `e540d2e35d15.png` | unknown | 1 | Mild | [0.0461, 0.5124, 0.2092, 0.1028, 0.1295] | False | 0.4415 | [0.6649, 0.7539, 0.6678, 0.7690, 0.7393, 0.6692] | 0.7043 | PASS |
| 09 | `e55188915f9d.png` | unknown | 1 | Mild | [0.0064, 0.7357, 0.2441, 0.0020, 0.0118] | False | 0.2579 | [0.6378, 0.6331, 0.6291, 0.6313, 0.7722, 0.5991] | 0.6322 | PASS |
| 10 | `e580676516b0.png` | unknown | 1 | Mild | [0.0332, 0.4786, 0.4130, 0.0592, 0.0160] | False | 0.4882 | [0.8615, 0.8787, 0.8177, 0.8098, 0.8714, 0.9740] | 0.8664 | PASS |
| 11 | `e582e56e7942.png` | unknown | 0 | No DR | [0.9947, 0.0036, 0.0007, 0.0005, 0.0004] | False | 0.0017 | [0.4660, 0.5289, 0.4359, 0.5006, 0.3941, 0.4452] | 0.4556 | PASS |
| 12 | `e594c19e2e1d.png` | unknown | 0 | No DR | [0.9560, 0.0289, 0.0065, 0.0031, 0.0056] | False | 0.0151 | [0.4289, 0.4318, 0.4165, 0.5145, 0.5703, 0.3743] | 0.4304 | PASS |

> [!NOTE]
> Ground-truth labels are absent from the local test set directory. Therefore, exact agreement percentage and within-one-grade percentage cannot be calculated against this set. Evaluated purely as an end-to-end execution, determinism, and latency benchmark.

---

## 5. Referable Threshold Sensitivity Analysis

The API allows client-side calibration of referral sensitivity via the query parameter `?referable_threshold=T`. The endpoint calculates `referable_probability = sum(P[grade >= 2])` and flags `referable = (referable_probability >= threshold)`.

| Image Index | Predicted Grade | Referable Probability | Default Referral (0.5) | Referral @ Threshold = 0.3 | Referral @ Threshold = 0.5 | Threshold Sensitivity Note |
| :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| 01 | 0 | 0.0077 | False | False | False | Unambiguous negative |
| 02 | 2 | 0.8248 | True | True | True | Unambiguous referable |
| 03 | 4 | 0.9887 | True | True | True | Unambiguous referable |
| 04 | 0 | 0.0145 | False | False | False | Unambiguous negative |
| 05 | 0 | 0.0001 | False | False | False | Unambiguous negative |
| 06 | 0 | 0.0104 | False | False | False | Unambiguous negative |
| 07 | 2 | 0.9988 | True | True | True | Unambiguous referable |
| 08 | 1 | 0.4415 | False | **True** | False | **Borderline case**: escalated to referral under sensitive threshold 0.3 |
| 10 | 1 | 0.4882 | False | **True** | False | **Borderline case**: escalated to referral under sensitive threshold 0.3 |
| 09 | 1 | 0.2579 | False | False | False | Retains non-referable status |
| 11 | 0 | 0.0017 | False | False | False | Unambiguous negative |
| 12 | 0 | 0.0151 | False | False | False | Unambiguous negative |

---

## 6. Latency Benchmark Summary

- **Cold Call Latency (First Model Load)**: **11.2114 s**  
  *(Includes PyTorch model construction, state dict deserialization from disk, and first forward pass compilation)*
- **Warm Inference Calls**: $N = 71$ calls
- **Warm Median Latency**: **0.5991 s** (~600 ms)
- **Warm Mean Latency**: **0.6043 s**
- **Warm Minimum Latency**: **0.3161 s**
- **Warm Maximum Latency**: **1.0326 s**

---

## 7. Process Memory Profile

Measured via process working set (`WorkingSet64` / RSS) on the active server PID:
- **Baseline Server Startup**: ~48.2 MB
- **Working Set Immediately After Model Load**: **366.36 MB**
- **Working Set Following Concurrency Test (4 threads)**: **531.56 MB**
- **Net Leakage / Growth**: Stable; no unbounded memory growth observed across 72 sequential inferences.

---

## 8. Negative & Edge-Case Testing

The API robustly validated edge cases and malformed inputs, returning compliant HTTP error codes.

| Test Case Description | Expected HTTP Status | Actual HTTP Status | Validation Status |
| :--- | :---: | :---: | :---: |
| Non-image file upload (`test.txt`, `text/plain`) | 415 Unsupported Media Type | 415 | **PASS** |
| Random corrupt bytes declared as `image/png` | 400 Bad Request | 400 | **PASS** |
| Zero-byte empty file payload | 400 Bad Request | 400 | **PASS** |
| File size exceeding 10 MB limit (11 MB payload) | 413 Content Too Large | 413 | **PASS** |
| Out-of-bounds referral threshold (`?referable_threshold=1.5`) | 422 Unprocessable Content | 422 | **PASS** |
| Multipart request lacking required `"file"` field | 422 Unprocessable Content | 422 | **PASS** |

---

## 9. Concurrency & Thread-Safety Verification

- **Workload**: 4 simultaneous client threads dispatching `POST /api/v1/grading/predict` concurrently on `e4dcca36ceb4.png`.
- **Response Statuses**: 4 / 4 returned HTTP 200 OK.
- **Output Determinism**: Identical predicted grades and probability distributions across all 4 concurrent workers (difference $< 1 \times 10^{-6}$).
- **Total Wall Clock Time**: **3.7384 s**
- **Individual Thread Latencies**: 0.8825 s, 1.2287 s, 1.6058 s, 0.4592 s (CPU resource contention across 4 threads).
- **Result**: **PASS**

---

## 10. Grad-CAM Explainability Overlays

Generated via `POST /api/v1/grading/gradcam` for 4 distinct images spanning representative predicted DR stages. Overlays were saved to [`docs/testing/gradcam/`](file:///D:/SIH-DR/docs/testing/gradcam/).

| File Name | Source Image Index | Predicted Grade | Image Dimensions (H, W, C) | File Size (Bytes) | Visual Inspection Findings |
| :--- | :---: | :---: | :---: | :---: | :--- |
| [`gradcam_01.png`](file:///D:/SIH-DR/docs/testing/gradcam/gradcam_01.png) | 01 | Grade 0 (No DR) | 1050 × 1050 × 3 | 1,108,823 | Activation heat is concentrated over retinal vascular arcades and optic disc margin. The dark peripheral margin has zero heat activation. |
| [`gradcam_02.png`](file:///D:/SIH-DR/docs/testing/gradcam/gradcam_02.png) | 02 | Grade 2 (Moderate DR) | 1424 × 2144 × 3 | 2,771,381 | Saliency heat is intensely localized directly over inferior retinal exudate lesion clusters. Background border is unaffected. |
| [`gradcam_03.png`](file:///D:/SIH-DR/docs/testing/gradcam/gradcam_03.png) | 03 | Grade 4 (Proliferative DR) | 1944 × 2896 × 3 | 3,412,886 | Activation heatmap highlights dense peripheral laser photocoagulation scars and neovascular lesions; minor boundary bleed at extreme left edge. |
| [`gradcam_04.png`](file:///D:/SIH-DR/docs/testing/gradcam/gradcam_04.png) | 08 | Grade 1 (Mild DR) | 1736 × 2416 × 3 | 3,058,091 | Heat is tightly focused on superior retinal vascular branching and microaneurysm sites. Clean margin isolation. |

All 4 Grad-CAM images decode successfully via `cv2.imread`.

---

## 11. Simulink Workflow Calibration (Step 12)

Because all 12 real fundus images yielded reliable warm inference latency measurements, the simulation parameters were updated:
- **Empirical Warm Median**: **0.5991 s**
- **Calibrated Value (rounded up to 0.1s)**: **0.6 s** (updated from initial placeholder of 5.0 s)
- **Updated File**: [`simulink-model/scripts/screening_params.m`](file:///D:/SIH-DR/simulink-model/scripts/screening_params.m) (`P.ai_grading_time_s = 0.6;`)
- **Documentation Updated**: [`simulink-model/README.md`](file:///D:/SIH-DR/simulink-model/README.md) parameter table status marked **MEASURED**.
- **MATLAB Simulation & Verification**:
  - Test Suite (`test_screening_sim.m`): 5 / 5 passed in 152.8 s.
  - Sustainable Annual Throughput: **117,446 patients/year** (exceeds district requirement of 100,000).
  - Primary Bottleneck: **Capture Stations** (85.01% utilization across 4 stations).
  - AI Grading Server Utilization: **0.69%** (down from 5.76% with the placeholder value, confirming server headroom).

---

## 12. Limitations & Clinical Governance Disclaimers

> [!CAUTION]
> **Research Prototype Disclaimer**: This service, its underlying neural network weights, and the simulation parameters reported herein represent an engineering prototype and research feasibility demonstration.
> - **No Clinical Validation**: The predictions and metrics reported in this document do not constitute certified diagnostic performance or clinical safety validation.
> - **Sample Size**: Latency and determinism benchmarks were conducted on a sample of 12 real fundus photos ($N=71$ warm inferences).
> - **Unlabeled Data**: Because the test images lacked reference clinical ground truth, diagnostic metrics (sensitivity, specificity, quadratic weighted kappa) were not computed on this set.

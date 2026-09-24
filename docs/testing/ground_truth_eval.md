# Held-Out Ground-Truth Evaluation Report: Diabetic Retinopathy Grading Model

**Task ID:** SIH-EVAL-007  
**Evaluator:** ML Engineering Agent  
**Date:** September 24, 2026  
**Artifacts Generated:**
- [ground_truth_predictions.csv](file:///d:/SIH-DR/docs/testing/ground_truth_predictions.csv)
- [ground_truth_confusion_matrix.png](file:///d:/SIH-DR/docs/testing/ground_truth_confusion_matrix.png)
- [dr_performance_test.json](file:///d:/SIH-DR/simulink-model/data/dr_performance_test.json)
- Reference validation benchmark: [dr_performance.json](file:///d:/SIH-DR/simulink-model/data/dr_performance.json)

---

## 1. Executive Summary

This report documents the independent, empirical evaluation of the EfficientNet-B0 Diabetic Retinopathy (DR) grading model against held-out ground-truth test labels. The model was evaluated strictly out-of-sample on all **366 fundus images** residing in `test_images/` using the official APTOS 2019 test set annotations (`backend/app/ml/data/test.csv`).

### Headline Performance
- **Exact Accuracy:** **81.15%** (297 / 366 images)
- **Within-One-Grade Agreement:** **94.26%** (345 / 366 images)
- **Quadratic Weighted Kappa (QWK):** **0.8688** (indicates strong agreement across ordinal severity grades)
- **Referable DR Sensitivity (Grade $\ge$ 2):** **86.13%** (118 / 137) [95% Wilson CI: **79.35% – 90.94%**]
- **Referable DR Specificity (Grade $\ge$ 2):** **94.76%** (217 / 229) [95% Wilson CI: **91.07% – 96.98%**]
- **Vision-Threatening Sensitivity (Grade $\ge$ 3):** **62.00%** (31 / 50) [95% Wilson CI: **48.15% – 74.14%**]
- **Average Inference Latency:** **428.57 ms** per image on CPU runtime (total runtime: 156.86 s for 366 sequential inferences)

---

## 2. Dataset Matching & Leakage Verification

To guarantee rigorous scientific validity, a comprehensive file discovery and data leakage check was performed across the workspace before inference.

### Candidate CSV Search
Search across repository and user directories identified 3 candidate label files:
1. `backend/app/ml/data/test.csv` (366 rows): Exactly matches all 366 PNGs in `test_images/`.
2. `backend/app/ml/data/train_1.csv` (2,930 rows): Primary training split.
3. `backend/app/ml/data/valid.csv` (366 rows): Kaggle notebook 15% validation split.

### Data Leakage Audit Results
| Metric | Count | Details |
| :--- | :--- | :--- |
| **Total Test Images in `test_images/`** | 366 | All valid 3-channel PNGs |
| **Matched against `test.csv`** | 366 (100.0%) | Joined on `id_code == filename_without_extension` |
| **Unmatched / Excluded** | 0 (0.0%) | No missing images or labels |
| **Overlap with `train_1.csv`** | **0 / 366 (0.0%)** | **No training data leakage** |
| **Overlap with `valid.csv`** | **0 / 366 (0.0%)** | **No validation data leakage** |
| **Evaluation Status** | **Confirmed Held-Out Test Set** | Truly unseen test distribution |

---

## 3. Evaluation Methodology

1. **Environment:** Python 3.14.0 x86_64 running under PowerShell in `backend/`.
2. **Inference Pipeline:** Each image was loaded sequentially from disk via `load_image()` and processed by `app.ml.inference.predict()` with default decision rules (`referable_threshold=None`, implying `referable = (pred_grade >= 2)`).
3. **Parity Check:** Re-running inference on sample images confirmed deterministic, identical predictions.
4. **Metrics Formulation:**
   - **Quadratic Weighted Kappa (QWK):**
     $$\kappa = 1 - \frac{\sum_{i,j} w_{i,j} O_{i,j}}{\sum_{i,j} w_{i,j} E_{i,j}}, \quad w_{i,j} = \frac{(i - j)^2}{(5 - 1)^2}$$
   - **Wilson 95% Score Confidence Intervals:** Computed using $z = 1.95996$ without continuity correction.

---

## 4. 5x5 Confusion Matrix

The 5x5 confusion matrix maps ground-truth ICDR grades (rows) against predicted grades (columns):

| True Grade \ Predicted Grade | 0: No DR | 1: Mild | 2: Moderate | 3: Severe | 4: Proliferative | Total (Support) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **0: No DR** | **194** | 3 | 2 | 0 | 0 | **199** |
| **1: Mild** | 2 | **18** | 10 | 0 | 0 | **30** |
| **2: Moderate** | 1 | 14 | **59** | 8 | 5 | **87** |
| **3: Severe** | 0 | 0 | 6 | **11** | 0 | **17** |
| **4: Proliferative DR** | 1 | 3 | 9 | 5 | **15** | **33** |
| **Total Predicted** | **198** | **38** | **86** | **24** | **20** | **366** |

![Confusion Matrix Heatmap](file:///d:/SIH-DR/docs/testing/ground_truth_confusion_matrix.png)

---

## 5. Detailed Metric Breakdown

### 5.1 Per-Class Classification Metrics
| Grade | ICDR Diagnosis | Support | True Positives (TP) | False Positives (FP) | False Negatives (FN) | Precision | Recall (Sensitivity) | F1-Score |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **0** | No DR | 199 | 194 | 4 | 5 | 97.98% | 97.49% | 0.9773 |
| **1** | Mild NPDR | 30 | 18 | 20 | 12 | 47.37% | 60.00% | 0.5294 |
| **2** | Moderate NPDR | 87 | 59 | 27 | 28 | 68.60% | 67.82% | 0.6821 |
| **3** | Severe NPDR | 17 | 11 | 13 | 6 | 45.83% | 64.71% | 0.5366 |
| **4** | Proliferative DR | 33 | 15 | 5 | 18 | 75.00% | 45.45% | 0.5660 |

### 5.2 Key Diagnostic Indicators
| Diagnostic Category | Definition | Ratio | Metric Value | 95% Wilson Score Interval |
| :--- | :--- | :---: | :---: | :---: |
| **Overall Accuracy** | Exact grade match | 297 / 366 | **81.15%** | [76.84% – 84.84%] |
| **Within-1-Grade Accuracy** | $|y_{\text{true}} - y_{\text{pred}}| \le 1$ | 345 / 366 | **94.26%** | [91.39% – 96.22%] |
| **Quadratic Weighted Kappa** | Ordinal penalization | — | **0.8688** | — |
| **Referable DR Sensitivity** | True $\ge 2$ flagged $\ge 2$ | 118 / 137 | **86.13%** | [**79.35% – 90.94%**] |
| **Referable DR Specificity** | True $< 2$ flagged $< 2$ | 217 / 229 | **94.76%** | [**91.07% – 96.98%**] |
| **Vision-Threatening Sens.** | True $\ge 3$ flagged $\ge 3$ | 31 / 50 | **62.00%** | [**48.15% – 74.14%**] |

---

## 6. Exploratory Referable Threshold Analysis

> [!NOTE]
> **Exploratory Finding Only:** Decision thresholds must always be calibrated on validation splits or pre-specified trial protocols. Evaluating thresholds on this test set is presented strictly to characterize the receiver operating curve behavior under varying operational cost regimes.

By altering the referable decision rule from $\text{pred\_grade} \ge 2$ to cumulative referable probability threshold $p_2 + p_3 + p_4 \ge t$:

| Threshold $t$ | TP | FP | TN | FN | Sensitivity | Specificity | Clinical Trade-off Context |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **0.50** | 118 | 13 | 216 | 19 | **86.13%** (118/137) | **94.32%** (216/229) | Standard threshold (balanced) |
| **0.40** | 126 | 14 | 215 | 11 | **91.97%** (126/137) | **93.89%** (215/229) | Exceeds 90% sensitivity with <1% specificity loss |
| **0.30** | 129 | 14 | 215 | 8 | **94.16%** (129/137) | **93.89%** (215/229) | Robust high-sensitivity screening profile |
| **0.25** | 130 | 17 | 212 | 7 | **94.89%** (130/137) | **92.58%** (212/229) | Catches 95% of referable cases |
| **0.20** | 134 | 18 | 211 | 3 | **97.81%** (134/137) | **92.14%** (211/229) | Misses only 3 referable cases, maintains >92% spec |

---

## 7. Qualitative Demonstration Cases

Eight representative test examples illustrate typical prediction modes:

| Mode | `id_code` | Ground Truth | Model Prediction | Top Class Prob. | Clinical Observation |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Exact Match** | `e4dcca36ceb4` | 0 (No DR) | 0 (No DR) | 97.47% | High-confidence true negative; clean retina. |
| **Exact Match** | `e4e343eaae2a` | 2 (Moderate) | 2 (Moderate) | 75.86% | Clear microaneurysms and exudates detected. |
| **Exact Match** | `e4f12411fd85` | 4 (Proliferative) | 4 (Proliferative) | 62.83% | Neovascularization correctly classified. |
| **One Grade Off** | `e52ed5c29c5e` | 3 (Severe) | 2 (Moderate) | 79.66% | Borderline 2/3: correctly marked referable ($p_{\text{ref}}=99.88\%$). |
| **One Grade Off** | `e540d2e35d15` | 2 (Moderate) | 1 (Mild) | 51.24% | Mild vs moderate boundary; borderline referable ($p_{\text{ref}}=44.15\%$). |
| **One Grade Off** | `e5d56f4f359b` | 2 (Moderate) | 3 (Severe) | 45.16% | Conservative overcall; still referable. |
| **Largest Error** | `f549294e12e1` | 4 (Proliferative) | 0 (No DR) | 28.75% | Low model confidence across all classes; severe false negative. |
| **Largest Error** | `eaa0dfbd5024` | 4 (Proliferative) | 1 (Mild) | 61.64% | Severe undercall; localized pathology outside model focus. |

---

## 8. Comparison: Validation Set vs Held-Out Test Set

A direct comparison with the validation split recorded in `simulink-model/data/dr_performance.json` demonstrates consistent generalization:

| Metric | Validation Set (`dr_performance.json`, n=440) | Held-Out Test Set (`dr_performance_test.json`, n=366) | Delta ($\Delta$) |
| :--- | :---: | :---: | :---: |
| **Exact Accuracy** | 81.60% | 81.15% | **-0.45%** |
| **QWK** | 0.9230 | 0.8688 | **-0.0542** |
| **Referable DR Sensitivity** | 88.30% (158/179) | 86.13% (118/137) | **-2.17%** |
| **Referable DR Specificity** | 96.20% (251/261) | 94.76% (217/229) | **-1.44%** |
| **Measured Latency** | *Unmeasured (null)* | **428.57 ms / image** | — |

The close alignment between validation and held-out test performance confirms the absence of catastrophic over-fitting.

---

## 9. Limitations & Clinical Governance Notice

> [!WARNING]
> **Limitations:**
> 1. **Sample Size:** The test set comprises $n=366$ images. While sufficient for statistical estimation with reasonably tight confidence intervals, rare classes (e.g. Grade 3 with $n=17$) exhibit wider uncertainty bounds ($[48.15\% - 74.14\%]$).
> 2. **Single Cohort:** All images originate from the APTOS 2019 dataset (Aravind Eye Hospital, India). Performance may differ on fundus cameras from different manufacturers (e.g., Topcon, Zeiss, Canon) or in diverse patient populations.
> 3. **Inter-Observer Variability:** Diabetic Retinopathy grading by human retina specialists has an established inter-observer agreement kappa between 0.80 and 0.88. Many "errors" lie at subjective clinical decision boundaries (e.g., Grade 2 vs 3).
> 4. **Non-Clinical Deployment:** This evaluation is an engineering benchmark and does not constitute clinical trial validation for autonomous diagnostic use.

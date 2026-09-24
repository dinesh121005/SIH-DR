# Simulink Model & Capacity Simulation Subsystem

## Overview
This subsystem models clinic queueing dynamics, patient arrivals, rural internet latency, and ophthalmologist review backlogs for tele-ophthalmology camps in rural India.

## Components
- `models/`: Simulink (`.slx`) block diagrams for discrete-event queues and throughput simulation.
- `scripts/`: MATLAB runner scripts and Python SimPy fallbacks for headless CI/CD capacity simulations.
- `data/`: Clinic parameters (arrival distributions, nurse exam times, doctor review latency).
- `tests/`: Automated unit and regression tests for simulation accuracy.

## Toolboxes & Fallback
- **MATLAB Toolbox**: Simulink + SimEvents (licensed)
- **Open-Source Fallback**: Python `simpy` discrete-event simulation engine (ready out-of-the-box in `ml-pipeline/requirements.txt`).

## Simulation Parameters and Assumptions

The workflow simulation parameters are centrally maintained in [`scripts/screening_params.m`](file:///D:/SIH-DR/simulink-model/scripts/screening_params.m). Every parameter is explicitly categorized as **MEASURED** (derived directly from model validation data), **PROGRAM TARGET** (mandated by clinical/program guidelines), or **PLACEHOLDER** (operational heuristic pending field telemetry).

| Parameter Name | Value | Unit | Status | Description / Source |
| :--- | :--- | :--- | :--- | :--- |
| `sens` | 0.8613 | fraction | **MEASURED** | Referable DR sensitivity (Held-out test set, n=366, APTOS 2019; `data/dr_performance_test.json`) |
| `spec` | 0.9476 | fraction | **MEASURED** | Referable DR specificity (Held-out test set, n=366, APTOS 2019; `data/dr_performance_test.json`) |
| `sens_val` | 0.883 | fraction | **MEASURED** | Referable DR sensitivity on validation split (for reference only; `data/dr_performance.json`) |
| `spec_val` | 0.962 | fraction | **MEASURED** | Referable DR specificity on validation split (for reference only; `data/dr_performance.json`) |
| `sens_B` / `spec_B` | 0.9197 / 0.9389 | fraction | **EXPLORATORY** | Operating point B (threshold 0.4 on p2+p3+p4 chosen on test set: 126/137 sens, 215/229 spec; must be re-chosen on validation data) |
| `quality_reject_recall` | 1.000 | fraction | **PLACEHOLDER** | Quality-gate poor image recall (assumed ideal until EyeQ test set evaluated) |
| `quality_false_reject_rate` | 0.000 | fraction | **PLACEHOLDER** | Quality-gate good image false rejection rate (assumed ideal until test set evaluated) |
| `gate_is_ideal` | true | boolean | **PLACEHOLDER** | Flag indicating quality gate currently operates under ideal theoretical assumptions |
| `annual_patients` | 100,000 | patients/yr | **PROGRAM TARGET** | Target screening volume for district tele-ophthalmology program |
| `validation_time_s` | 30 | seconds | **PROGRAM TARGET** | Target doctor review latency per AI-flagged case |
| `operating_days_per_year` | 300 | days | **PLACEHOLDER** | Working days per clinic year |
| `hours_per_day` | 8 | hours | **PLACEHOLDER** | Screening operational hours per day |
| `capture_stations` | 4 | stations | **PLACEHOLDER** | Concurrent fundus camera stations deployed |
| `capture_time_min` | 4.0 | minutes | **PLACEHOLDER** | Exam and image acquisition time per attempt |
| `p_poor_image` | 0.19 | fraction | **PLACEHOLDER** | Pre-gate uncorrected poor image prevalence (EyeQ Reject class share) |
| `max_recaptures` | 2 | attempts | **PLACEHOLDER** | Maximum recapture attempts before routing to manual review |
| `gate_time_s` | 10 | seconds | **PLACEHOLDER** | Automated quality assessment turnaround time |
| `ai_grading_time_s` | 0.6 | seconds | **MEASURED** | Backend AI grading inference time (warm median over 71 calls, Intel Core i5-8265U, 2026-09-24) |
| `referable_prevalence` | 0.20 | fraction | **PLACEHOLDER** | Prevalence of referable DR (grade >= 2) in target screening population |
| `ophthalmologists` | 2 | doctors | **PLACEHOLDER** | Number of active ophthalmologists reviewing flagged cases |
| `manual_review_time_s` | 60 | seconds | **PLACEHOLDER** | Doctor review time for persistent ungradable cases |

### Dataset Provenance & Operating Points Evaluation

The baseline Diabetic Retinopathy screening simulation metrics are driven by the empirical held-out test evaluation on the APTOS 2019 test partition (366 images, labels in `test.csv`), documented in [`simulink-model/data/dr_performance_test.json`](file:///D:/SIH-DR/simulink-model/data/dr_performance_test.json). The default argmax classification rule achieves referable DR sensitivity of 0.8613 (95% CI: [0.7935, 0.9094]) and specificity of 0.9476 (95% CI: [0.9107, 0.9698]). Earlier validation-split metrics (sens: 0.883, spec: 0.962) from [`simulink-model/data/dr_performance.json`](file:///D:/SIH-DR/simulink-model/data/dr_performance.json) are retained as `P.sens_val` and `P.spec_val` for reference.

An alternative referral threshold—Operating Point B—applies a threshold of 0.4 to the combined referable class probability ($p_2 + p_3 + p_4 \ge 0.4$), yielding 126/137 sensitivity (0.9197) and 215/229 specificity (0.9389). **Status: EXPLORATORY: threshold 0.4 was chosen on the test set; it must be re-chosen and calibrated on validation data before clinical deployment.** A full operational comparison of Points A and B is exported to [`simulink-model/data/sim_operating_points.csv`](file:///D:/SIH-DR/simulink-model/data/sim_operating_points.csv) and visualized in [`docs/simulation/sweep4_operating_point.png`](file:///D:/SIH-DR/docs/simulation/sweep4_operating_point.png).

The EyeQ 3-class quality model performance (accuracy 0.9000, weighted F1 0.8991) was evaluated on a 15% random validation split of pooled EyeQ data (4,282 images), as recorded in [`simulink-model/data/quality_performance.json`](file:///D:/SIH-DR/simulink-model/data/quality_performance.json). Because test-set evaluation has not yet been executed on the held-out EyeQ test partition (4,283 images), the quality gate currently assumes ideal discrimination (`quality_reject_recall = 1.0`, `quality_false_reject_rate = 0.0`, `gate_is_ideal = true`). Once formal test-set evaluation is performed on Kaggle, the empirical reject recall and false rejection rates will replace these placeholders.


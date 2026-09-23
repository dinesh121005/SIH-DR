# AI-Powered Diabetic Retinopathy (DR) Screening Pipeline

An end-to-end tele-ophthalmology screening and clinic capacity simulation platform designed for rural India, developed for the Smart India Hackathon (SIH).

---

## 📌 Project Overview

Diabetic Retinopathy (DR) is a major cause of preventable blindness worldwide, particularly affecting underserved rural populations where specialized ophthalmologists are scarce. This platform integrates:
1. **Automated Fundus Image Quality Assessment (QA)**: Real-time feedback for rural health workers to prevent ungradable image captures.
2. **Deep Learning Lesion Segmentation & Severity Grading**: Automated detection of microaneurysms, hemorrhages, and exudates alongside International Clinical Diabetic Retinopathy (ICDR) grading (Levels 0–4).
3. **Clinical Explainability**: Grad-CAM overlays and lesion heatmaps enabling clinician trust and verification.
4. **Tele-Ophthalmology Workflows**: Specialized portals for rural clinic nurses (screening/intake) and central ophthalmologists (secondary review and confirmation).
5. **Capacity & Workflow Simulation**: Discrete-event capacity modeling (Simulink / SimPy) simulating patient arrival distributions, network bandwidth constraints, and doctor review latency.

> [!NOTE]
> Physical fundus cameras are not directly attached. The pipeline consumes standard digital retinal fundus photographs sourced from premier public benchmarks (APTOS 2019, IDRiD, Messidor-2, EyePACS, DDR).

---

## 🏛️ Subsystems Architecture

```
SIH-DR/
├── ml-pipeline/         # Retinal image QA, segmentation, grading, and explainability
├── backend/             # FastAPI asynchronous backend service, database & queue orchestration
├── frontend-nurse/      # React/Vite portal for rural health workers (intake & capture QA)
├── frontend-doctor/     # React/Vite portal for ophthalmologists (triage & audit)
├── simulink-model/      # Clinic queuing, referral workflow, and tele-health capacity simulation
├── docker-compose.yml   # Infrastructure orchestration (PostgreSQL 16, Redis 7)
└── README.md            # Project master documentation
```

### 1. `ml-pipeline/`
- **QA Subsystem**: Fast artifact, blur, and field-of-view detection.
- **Segmentation**: Deep segmentation masks for optic disc, blood vessels, microaneurysms, hemorrhages, and exudates.
- **Grading**: 5-class severity classification (0: No DR, 1: Mild, 2: Moderate, 3: Severe, 4: Proliferative DR).
- **Explainability**: Saliency mapping, Grad-CAM visualization for doctor confidence.

### 2. `backend/`
- **FastAPI Core**: Async REST endpoints for patient intake, fundus upload, screening records, and doctor verification.
- **Data Persistence**: PostgreSQL 16 relational database with SQLAlchemy / Asyncpg.
- **Queue & Caching**: Redis 7 message broker and cache for inference tasks.

### 3. `frontend-nurse/`
- **Intake Flow**: Quick patient registration, vitals, diabetes history.
- **Immediate QA**: Near real-time feedback on fundus clarity (Pass / Retake needed).
- **Referral Generation**: Automated patient slip with preliminary triage priority.

### 4. `frontend-doctor/`
- **Triage Dashboard**: Priority queue ordered by DR severity and urgency.
- **Multimodal Viewer**: High-resolution fundus inspection with toggleable lesion segmentation masks and Grad-CAM overlays.
- **Clinician Confirmation**: Structured diagnostic sign-off and referral plan.

### 5. `simulink-model/`
- **Capacity Modeling**: Simulink `.slx` and Python `SimPy` models simulating rural primary health centres (PHCs), district hospitals, patient arrival rates, tele-transmission delays, and ophthalmologist review backlogs.

---

## 🗺️ Project Roadmap (Phase 0 – Phase 4)

| Phase | Title | Scope & Milestones | Status |
|---|---|---|---|
| **Phase 0** | **Project Discovery & Foundation** | Repo structure, Docker services (Postgres 16, Redis 7), MATLAB & Python licensing audit, shared contracts | **COMPLETED** |
| **Phase 1** | **Data Ingestion & Preprocessing / QA** | Acquisition & partitioning of APTOS 2019, IDRiD, Messidor-2, EyePACS, DDR; image normalization, quality assessment model | *Next* |
| **Phase 2** | **ML Model Development & Explainability** | Lesion segmentation models, 5-class ICDR severity classification, Grad-CAM saliency generation, model validation | Upcoming |
| **Phase 3** | **Service Integration & Capacity Simulation** | FastAPI backend integration, Nurse & Doctor frontends, Simulink / SimPy rural clinic capacity simulation | Upcoming |
| **Phase 4** | **System Validation & Field Deployment** | End-to-end integration testing, throughput benchmarking, clinician acceptance testing, rural pilot deployment | Upcoming |

---

## ⚙️ Development Environment Setup

### Prerequisites
- **Docker & Docker Compose** (Docker v20+ / Docker Compose v2+)
- **Python 3.10+** (Python 3.11/3.12 recommended)
- **Node.js 18+** & npm (for frontends)
- **MATLAB R2022b+** *(Optional - full open-source Python fallbacks provided)*

### 1. Database & Cache Services (Docker Compose)
Start PostgreSQL 16 and Redis 7:
```bash
# Start containers in background
docker compose up -d

# Verify health status
docker compose ps
```

### 2. Backend Service Configuration
```bash
cd backend
cp .env.example .env
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

### 3. MATLAB Toolbox Verification & Fallback Matrix
Run the automated toolbox verification:
```bash
python ml-pipeline/scripts/check_toolboxes.py
```

| Required MATLAB Toolbox | Target Subsystem | Open-Source / Python Fallback |
|---|---|---|
| Image Processing Toolbox | `ml-pipeline` (QA & preproc) | OpenCV (`cv2`) + `scikit-image` + `albumentations` |
| Computer Vision Toolbox | `ml-pipeline` (features) | OpenCV + `torchvision` |
| Deep Learning Toolbox | `ml-pipeline` (CNN/ViT) | PyTorch + `timm` (ConvNeXt, EfficientNet) |
| Medical Imaging Toolbox | `ml-pipeline` (retinal) | `monai` (Medical Open Network for AI) |
| Simulink | `simulink-model` (capacity) | `simpy` (Discrete-event simulation) |
| Statistics and ML Toolbox | `ml-pipeline` / `simulink-model` | `scikit-learn` + `scipy` + `pandas` |

---

## 🔒 Security & Privacy

- No real patient health information (PHI) or unanonymized datasets are stored in git.
- Secrets and credentials (`.env`) are strictly excluded via `.gitignore`.
- HIPAA / Indian Digital Personal Data Protection (DPDP) compliance considerations embedded in database schemas.

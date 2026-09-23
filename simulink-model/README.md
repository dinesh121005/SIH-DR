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

function P = screening_params()
% SCREENING_PARAMS Returns the single-source-of-truth parameter struct for the
% DR screening workflow simulation (SIH-SIMULINK-003).
%
% Every parameter is explicitly tagged with exactly one status:
%   - MEASURED (with source file)
%   - PROGRAM TARGET (from the official problem statement)
%   - PLACEHOLDER (operational assumption)

% -------------------------------------------------------------------------
% 1. LOCATE MEASURED DATA FILES
% -------------------------------------------------------------------------
scripts_dir = fileparts(mfilename('fullpath'));
sim_root = fileparts(scripts_dir);
data_dir = fullfile(sim_root, 'data');

dr_test_json_path = fullfile(data_dir, 'dr_performance_test.json');
dr_val_json_path = fullfile(data_dir, 'dr_performance.json');
quality_json_path = fullfile(data_dir, 'quality_performance.json');

% -------------------------------------------------------------------------
% 2. MEASURED PARAMETERS: DR GRADING MODEL
% -------------------------------------------------------------------------
% Source: simulink-model/data/dr_performance_test.json (held-out test, n=366)
if ~exist(dr_test_json_path, 'file')
    error('dr_performance_test.json not found at: %s', dr_test_json_path);
end
dr_test_raw = fileread(dr_test_json_path);
dr_test_data = jsondecode(dr_test_raw);

if ~isfield(dr_test_data, 'referable_dr') || ...
   ~isfield(dr_test_data.referable_dr, 'sensitivity') || ...
   ~isfield(dr_test_data.referable_dr, 'specificity')
    error('dr_performance_test.json lacks required referable_dr sensitivity or specificity fields.');
end

% Operating Point A (default argmax rule, held-out test, n=366)
P.sens = dr_test_data.referable_dr.sensitivity;  % MEASURED: simulink-model/data/dr_performance_test.json (held-out test, n=366)
P.spec = dr_test_data.referable_dr.specificity;  % MEASURED: simulink-model/data/dr_performance_test.json (held-out test, n=366)

% Validation set metrics kept for reference only
if ~exist(dr_val_json_path, 'file')
    error('dr_performance.json not found at: %s', dr_val_json_path);
end
dr_val_raw = fileread(dr_val_json_path);
dr_val_data = jsondecode(dr_val_raw);

if ~isfield(dr_val_data, 'referable_dr') || ...
   ~isfield(dr_val_data.referable_dr, 'sensitivity') || ...
   ~isfield(dr_val_data.referable_dr, 'specificity')
    error('dr_performance.json lacks required referable_dr sensitivity or specificity fields.');
end

P.sens_val = dr_val_data.referable_dr.sensitivity;  % MEASURED: simulink-model/data/dr_performance.json (validation, for reference only)
P.spec_val = dr_val_data.referable_dr.specificity;  % MEASURED: simulink-model/data/dr_performance.json (validation, for reference only)

% Operating Point B (exploratory threshold 0.4 on p2+p3+p4)
P.sens_B = 126 / 137;  % EXPLORATORY: threshold 0.4 chosen on the test set; must be re-chosen on validation data
P.spec_B = 215 / 229;  % EXPLORATORY: threshold 0.4 chosen on the test set; must be re-chosen on validation data

% -------------------------------------------------------------------------
% 3. MEASURED PARAMETERS: QUALITY MODEL (EYEQ)
% -------------------------------------------------------------------------
% Source: simulink-model/data/quality_performance.json
if exist(quality_json_path, 'file')
    q_raw = fileread(quality_json_path);
    q_data = jsondecode(q_raw);
else
    q_data = struct();
end

% Quality gate parameters
if isfield(q_data, 'reject_recall') && ~isempty(q_data.reject_recall) && ~isnan(q_data.reject_recall) && ...
   isfield(q_data, 'false_reject_rate') && ~isempty(q_data.false_reject_rate) && ~isnan(q_data.false_reject_rate)
    P.quality_reject_recall = q_data.reject_recall;        % MEASURED: quality_performance.json
    P.quality_false_reject_rate = q_data.false_reject_rate; % MEASURED: quality_performance.json
    P.gate_is_ideal = false;
else
    % Test-set evaluation not yet run; assuming ideal quality gate per instructions
    P.quality_reject_recall = 1.0;                         % PLACEHOLDER: assumed ideal quality gate
    P.quality_false_reject_rate = 0.0;                     % PLACEHOLDER: assumed ideal quality gate
    P.gate_is_ideal = true;                                % Status flag: true if ideal gate assumed
end

% -------------------------------------------------------------------------
% 4. PROGRAM TARGETS (From problem statement & clinical program requirements)
% -------------------------------------------------------------------------
P.annual_patients = 100000;         % PROGRAM TARGET: District program target serving 100,000+ patients/year
P.validation_time_s = 30;           % PROGRAM TARGET: Ophthalmologist validation target under 30s per AI-flagged case

% -------------------------------------------------------------------------
% 5. OPERATIONAL & CLINICAL PLACEHOLDERS
% -------------------------------------------------------------------------
P.operating_days_per_year = 300;    % PLACEHOLDER: Clinic operating days per year
P.hours_per_day = 8;                % PLACEHOLDER: Working hours per clinic day
P.operating_hours_per_year = P.operating_days_per_year * P.hours_per_day; % Derived: 2,400 hours/yr

P.capture_stations = 4;             % PLACEHOLDER: Number of fundus camera capture stations
P.capture_time_min = 4;             % PLACEHOLDER: Exam and capture duration per attempt (minutes)
P.capture_time_s = P.capture_time_min * 60; % Derived: 240 seconds per capture attempt

P.p_poor_image = 0.19;              % PLACEHOLDER: Pre-gate uncorrected poor image probability (from EyeQ Reject share)
P.max_recaptures = 2;               % PLACEHOLDER: Maximum recaptures allowed before routing to manual review
P.gate_time_s = 10;                 % PLACEHOLDER: Quality gate automated inference & assessment latency (seconds)
P.ai_grading_time_s = 0.6;          % MEASURED: warm median over 71 calls (12 real fundus images), Intel Core i5-8265U, FastAPI CPU inference, 2026-09-24

P.referable_prevalence = 0.20;      % PLACEHOLDER: Population prevalence of referable DR (grade >= 2)
% Probability of AI flagging a case as referable:
P.ai_referable_rate = P.referable_prevalence * P.sens + (1 - P.referable_prevalence) * (1 - P.spec); % Derived

P.ophthalmologists = 2;             % PLACEHOLDER: Number of concurrent ophthalmologists reviewing flagged cases
P.manual_review_time_s = 60;        % PLACEHOLDER: Time required for manual review of persistent ungradable cases (seconds)

end

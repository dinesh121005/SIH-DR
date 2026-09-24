function mdl_path = build_screening_model()
% BUILD_SCREENING_MODEL Programmatically builds the base-Simulink fluid-queue
% model 'screening_workflow.slx' representing the DR screening pipeline.
%
% Architecture:
%   1. Patient Arrivals (Poisson mean rate lambda in patients/hour)
%   2. Capture Stations (Queue Integrator + Service Capacity mu_capture)
%   3. Quality Gate (Automated inspection with Recapture loop & Manual Review)
%   4. AI Grading (Inference queue & service)
%   5. Split to Non-Referable Discharge vs Referable Ophthalmologist Review
%   6. Ophthalmologist Validation & Manual Review Queue
%
% Signals Logged:
%   - Queue_Lengths: [Q_capture, Q_quality, Q_ai, Q_ophth, Q_manual]
%   - Utilizations:  [U_capture, U_quality, U_ai, U_ophth, U_manual]
%   - Completed:     Cumulative screened patients

scripts_dir = fileparts(mfilename('fullpath'));
sim_root = fileparts(scripts_dir);
models_dir = fullfile(sim_root, 'models');
if ~exist(models_dir, 'dir')
    mkdir(models_dir);
end

mdl = 'screening_workflow';
mdl_path = fullfile(models_dir, [mdl '.slx']);

% Close if already open
if bdIsLoaded(mdl)
    close_system(mdl, 0);
end

% Create new Simulink system
new_system(mdl);

% Model Configuration
set_param(mdl, 'Solver', 'ode23tb');
set_param(mdl, 'StopTime', '2400'); % 2,400 hours = 1 standard operating year
set_param(mdl, 'SaveOutput', 'on');
set_param(mdl, 'SignalLogging', 'on');
set_param(mdl, 'SignalLoggingName', 'logsout');

% Set up model pre-load / init callback to load screening_params automatically
set_param(mdl, 'PreLoadFcn', 'P = screening_params();');
set_param(mdl, 'InitFcn', 'P = screening_params();');

% Base rates from screening_params
P = screening_params();

% -------------------------------------------------------------------------
% 1. ARRIVALS BLOCK
% -------------------------------------------------------------------------
lambda = P.annual_patients / P.operating_hours_per_year; % patients / hour (~41.67)

add_block('simulink/Sources/Constant', [mdl '/Arrivals'], ...
    'Value', sprintf('%.6f', lambda), ...
    'Position', [50, 100, 100, 130]);

% -------------------------------------------------------------------------
% 2. CAPTURE STATIONS STAGE
% Inflow = New Arrivals + Recaptures
% -------------------------------------------------------------------------
add_block('simulink/Math Operations/Sum', [mdl '/Sum_Capture_Inflow'], ...
    'Inputs', '++', ...
    'Position', [160, 105, 185, 145]);

% Recapture feedback gain (from quality gate rejects that can be retried)
% With max 2 recaptures: p_recapture_return = p + p^2
p_recapture_eff = P.p_poor_image * P.quality_reject_recall + (P.p_poor_image * P.quality_reject_recall)^2;
add_block('simulink/Math Operations/Gain', [mdl '/Gain_Recapture_Return'], ...
    'Gain', sprintf('%.6f', p_recapture_eff), ...
    'Position', [160, 220, 210, 250], ...
    'Orientation', 'left');

% Capture Service capacity (stations * 60 / capture_time_min)
mu_cap = P.capture_stations * (60 / P.capture_time_min); % patients / hr (60)
add_block('simulink/Continuous/Integrator', [mdl '/Queue_Capture'], ...
    'InitialCondition', '0', ...
    'LimitOutput', 'on', ...
    'LowerSaturationLimit', '0', ...
    'Position', [250, 105, 290, 145]);

add_block('simulink/Commonly Used Blocks/Saturation', [mdl '/Cap_Capture_Rate'], ...
    'UpperLimit', sprintf('%.6f', mu_cap), ...
    'LowerLimit', '0', ...
    'Position', [340, 105, 380, 145]);

add_block('simulink/Math Operations/Gain', [mdl '/Gain_Util_Capture'], ...
    'Gain', sprintf('%.8f', 1 / mu_cap), ...
    'Position', [420, 160, 460, 190]);

% Net flow to integrator = inflow - outflow
add_block('simulink/Math Operations/Sum', [mdl '/Sum_dCapture'], ...
    'Inputs', '+-', ...
    'Position', [210, 110, 230, 140]);

% -------------------------------------------------------------------------
% 3. QUALITY GATE STAGE
% Evaluates captured images. Divides into Pass vs Persistent Reject (Manual Review)
% -------------------------------------------------------------------------
mu_gate = 3600 / P.gate_time_s; % images / hr (360)

% Passed fraction (good or usable) = 1 - p_poor^3
p_pass_final = 1 - (P.p_poor_image * P.quality_reject_recall)^3;
p_manual_review = (P.p_poor_image * P.quality_reject_recall)^3;

add_block('simulink/Math Operations/Gain', [mdl '/Gain_Quality_Pass'], ...
    'Gain', sprintf('%.6f', p_pass_final), ...
    'Position', [470, 110, 520, 140]);

add_block('simulink/Math Operations/Gain', [mdl '/Gain_Quality_Reject_Manual'], ...
    'Gain', sprintf('%.6f', p_manual_review), ...
    'Position', [470, 270, 520, 300]);

add_block('simulink/Math Operations/Gain', [mdl '/Gain_Util_Quality'], ...
    'Gain', sprintf('%.8f', 1 / mu_gate), ...
    'Position', [470, 50, 510, 80]);

% -------------------------------------------------------------------------
% 4. AI GRADING STAGE
% Evaluates passed images. Divides into Non-referable vs Referable
% -------------------------------------------------------------------------
mu_ai = 3600 / P.ai_grading_time_s; % patients / hr (720)

add_block('simulink/Math Operations/Gain', [mdl '/Gain_AI_Referable'], ...
    'Gain', sprintf('%.6f', P.ai_referable_rate), ...
    'Position', [590, 110, 640, 140]);

add_block('simulink/Math Operations/Gain', [mdl '/Gain_AI_NonReferable'], ...
    'Gain', sprintf('%.6f', 1 - P.ai_referable_rate), ...
    'Position', [590, 170, 640, 200]);

add_block('simulink/Math Operations/Gain', [mdl '/Gain_Util_AI'], ...
    'Gain', sprintf('%.8f', 1 / mu_ai), ...
    'Position', [590, 50, 630, 80]);

% -------------------------------------------------------------------------
% 5. OPHTHALMOLOGIST VALIDATION STAGE
% Reviews AI-flagged referable cases
% -------------------------------------------------------------------------
mu_ophth = P.ophthalmologists * (3600 / P.validation_time_s); % cases / hr (240)

add_block('simulink/Continuous/Integrator', [mdl '/Queue_Ophth'], ...
    'InitialCondition', '0', ...
    'LimitOutput', 'on', ...
    'LowerSaturationLimit', '0', ...
    'Position', [700, 105, 740, 145]);

add_block('simulink/Commonly Used Blocks/Saturation', [mdl '/Cap_Ophth_Rate'], ...
    'UpperLimit', sprintf('%.6f', mu_ophth), ...
    'LowerLimit', '0', ...
    'Position', [780, 105, 820, 145]);

add_block('simulink/Math Operations/Sum', [mdl '/Sum_dOphth'], ...
    'Inputs', '+-', ...
    'Position', [665, 110, 685, 140]);

add_block('simulink/Math Operations/Gain', [mdl '/Gain_Util_Ophth'], ...
    'Gain', sprintf('%.8f', 1 / mu_ophth), ...
    'Position', [860, 160, 900, 190]);

% -------------------------------------------------------------------------
% 6. MANUAL REVIEW STAGE (Ungradables after 2 recaptures)
% -------------------------------------------------------------------------
mu_manual = P.ophthalmologists * (3600 / P.manual_review_time_s); % cases / hr (120)

add_block('simulink/Continuous/Integrator', [mdl '/Queue_Manual'], ...
    'InitialCondition', '0', ...
    'LimitOutput', 'on', ...
    'LowerSaturationLimit', '0', ...
    'Position', [570, 270, 610, 310]);

add_block('simulink/Commonly Used Blocks/Saturation', [mdl '/Cap_Manual_Rate'], ...
    'UpperLimit', sprintf('%.6f', mu_manual), ...
    'LowerLimit', '0', ...
    'Position', [650, 270, 690, 310]);

add_block('simulink/Math Operations/Sum', [mdl '/Sum_dManual'], ...
    'Inputs', '+-', ...
    'Position', [540, 275, 560, 305]);

add_block('simulink/Math Operations/Gain', [mdl '/Gain_Util_Manual'], ...
    'Gain', sprintf('%.8f', 1 / mu_manual), ...
    'Position', [720, 320, 760, 350]);

% -------------------------------------------------------------------------
% 7. MULTIPLEXERS & OUTPORTS FOR SIGNAL LOGGING
% -------------------------------------------------------------------------
% Queue Lengths Vector
add_block('simulink/Signal Routing/Mux', [mdl '/Mux_Queues'], ...
    'Inputs', '5', ...
    'Position', [880, 220, 890, 320]);

% Zero placeholder for quality gate & AI grading queues (near-zero delay)
add_block('simulink/Sources/Constant', [mdl '/Const_Zero_Q'], ...
    'Value', '0', ...
    'Position', [820, 245, 840, 265]);

add_block('simulink/Sinks/Out1', [mdl '/Queue_Lengths'], ...
    'Position', [930, 260, 960, 280]);

% Utilizations Vector
add_block('simulink/Signal Routing/Mux', [mdl '/Mux_Utils'], ...
    'Inputs', '5', ...
    'Position', [880, 50, 890, 150]);

add_block('simulink/Sinks/Out1', [mdl '/Utilizations'], ...
    'Position', [930, 90, 960, 110]);

% Cumulative Completed Patients (Discharge + Referred)
add_block('simulink/Math Operations/Sum', [mdl '/Sum_Completed_Rate'], ...
    'Inputs', '+++', ...
    'Position', [860, 370, 885, 410]);

add_block('simulink/Continuous/Integrator', [mdl '/Cumulative_Completed'], ...
    'InitialCondition', '0', ...
    'Position', [910, 375, 940, 405]);

add_block('simulink/Sinks/Out1', [mdl '/Completed_Patients'], ...
    'Position', [970, 380, 1000, 400]);

% -------------------------------------------------------------------------
% 8. SIGNAL WIRING
% -------------------------------------------------------------------------
% Arrivals -> Sum_Capture_Inflow
add_line(mdl, 'Arrivals/1', 'Sum_Capture_Inflow/1');

% Recapture Return -> Sum_Capture_Inflow (second port)
add_line(mdl, 'Gain_Recapture_Return/1', 'Sum_Capture_Inflow/2');

% Sum_Capture_Inflow -> Sum_dCapture
add_line(mdl, 'Sum_Capture_Inflow/1', 'Sum_dCapture/1');

% Sum_dCapture -> Queue_Capture
add_line(mdl, 'Sum_dCapture/1', 'Queue_Capture/1');

% Queue_Capture -> Cap_Capture_Rate
add_line(mdl, 'Queue_Capture/1', 'Cap_Capture_Rate/1');

% Cap_Capture_Rate feedback to Sum_dCapture port 2
add_line(mdl, 'Cap_Capture_Rate/1', 'Sum_dCapture/2');

% Cap_Capture_Rate -> Gain_Util_Capture & Gain_Recapture_Return & Quality Gate
add_line(mdl, 'Cap_Capture_Rate/1', 'Gain_Util_Capture/1');
add_line(mdl, 'Cap_Capture_Rate/1', 'Gain_Recapture_Return/1');
add_line(mdl, 'Cap_Capture_Rate/1', 'Gain_Quality_Pass/1');
add_line(mdl, 'Cap_Capture_Rate/1', 'Gain_Quality_Reject_Manual/1');
add_line(mdl, 'Cap_Capture_Rate/1', 'Gain_Util_Quality/1');

% Quality Gate Pass -> AI Grading
add_line(mdl, 'Gain_Quality_Pass/1', 'Gain_AI_Referable/1');
add_line(mdl, 'Gain_Quality_Pass/1', 'Gain_AI_NonReferable/1');
add_line(mdl, 'Gain_Quality_Pass/1', 'Gain_Util_AI/1');

% AI Referable -> Sum_dOphth
add_line(mdl, 'Gain_AI_Referable/1', 'Sum_dOphth/1');
add_line(mdl, 'Sum_dOphth/1', 'Queue_Ophth/1');
add_line(mdl, 'Queue_Ophth/1', 'Cap_Ophth_Rate/1');
add_line(mdl, 'Cap_Ophth_Rate/1', 'Sum_dOphth/2');
add_line(mdl, 'Cap_Ophth_Rate/1', 'Gain_Util_Ophth/1');

% Quality Manual Review -> Sum_dManual
add_line(mdl, 'Gain_Quality_Reject_Manual/1', 'Sum_dManual/1');
add_line(mdl, 'Sum_dManual/1', 'Queue_Manual/1');
add_line(mdl, 'Queue_Manual/1', 'Cap_Manual_Rate/1');
add_line(mdl, 'Cap_Manual_Rate/1', 'Sum_dManual/2');
add_line(mdl, 'Cap_Manual_Rate/1', 'Gain_Util_Manual/1');

% Mux Utilizations: [Capture, Quality, AI, Ophth, Manual]
add_line(mdl, 'Gain_Util_Capture/1', 'Mux_Utils/1');
add_line(mdl, 'Gain_Util_Quality/1', 'Mux_Utils/2');
add_line(mdl, 'Gain_Util_AI/1', 'Mux_Utils/3');
add_line(mdl, 'Gain_Util_Ophth/1', 'Mux_Utils/4');
add_line(mdl, 'Gain_Util_Manual/1', 'Mux_Utils/5');
add_line(mdl, 'Mux_Utils/1', 'Utilizations/1');

% Mux Queues: [Capture, Quality, AI, Ophth, Manual]
add_line(mdl, 'Queue_Capture/1', 'Mux_Queues/1');
add_line(mdl, 'Const_Zero_Q/1', 'Mux_Queues/2');
add_line(mdl, 'Const_Zero_Q/1', 'Mux_Queues/3');
add_line(mdl, 'Queue_Ophth/1', 'Mux_Queues/4');
add_line(mdl, 'Queue_Manual/1', 'Mux_Queues/5');
add_line(mdl, 'Mux_Queues/1', 'Queue_Lengths/1');

% Cumulative Completed: Discharge + Referrals Validated + Manual Completed
add_line(mdl, 'Gain_AI_NonReferable/1', 'Sum_Completed_Rate/1');
add_line(mdl, 'Cap_Ophth_Rate/1', 'Sum_Completed_Rate/2');
add_line(mdl, 'Cap_Manual_Rate/1', 'Sum_Completed_Rate/3');
add_line(mdl, 'Sum_Completed_Rate/1', 'Cumulative_Completed/1');
add_line(mdl, 'Cumulative_Completed/1', 'Completed_Patients/1');

% Save model
save_system(mdl, mdl_path);
close_system(mdl);

fprintf('Successfully built and saved Simulink model: %s\n', mdl_path);
end

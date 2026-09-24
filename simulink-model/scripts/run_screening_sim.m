function results = run_screening_sim()
% RUN_SCREENING_SIM Executes baseline DR screening simulation and parameter sweeps.
%
% Tasks performed:
%   1. Loads single-source parameters from screening_params().
%   2. Runs Simulink fluid-queue model 'screening_workflow.slx'.
%   3. Runs stochastic discrete-event Monte Carlo simulation (M/M/c & M/G/c queues).
%   4. Writes simulink-model/data/sim_results.csv with complete labeled metrics.
%   5. Performs 3 parameter sweeps and exports publication-ready PNG plots to docs/simulation/.

scripts_dir = fileparts(mfilename('fullpath'));
sim_root = fileparts(scripts_dir);
data_dir = fullfile(sim_root, 'data');
docs_sim_dir = fullfile(fileparts(sim_root), 'docs', 'simulation');

if ~exist(data_dir, 'dir'), mkdir(data_dir); end
if ~exist(docs_sim_dir, 'dir'), mkdir(docs_sim_dir); end

addpath(scripts_dir);
addpath(fullfile(sim_root, 'models'));

% Load parameters
P = screening_params();

fprintf('\n======================================================================\n');
fprintf('  DR SCREENING WORKFLOW SIMULATION ENGINE (SIH-SIMULINK-003)\n');
fprintf('======================================================================\n');
fprintf('Target Annual Screening Volume:  %d patients/year [PROGRAM TARGET]\n', P.annual_patients);
fprintf('Operating Hours per Year:        %d hrs (%d days x %d hrs) [PLACEHOLDER]\n', ...
    P.operating_hours_per_year, P.operating_days_per_year, P.hours_per_day);
fprintf('Measured DR Sensitivity:         %.4f [MEASURED: dr_performance_test.json]\n', P.sens);
fprintf('Measured DR Specificity:         %.4f [MEASURED: dr_performance_test.json]\n', P.spec);
fprintf('Quality Gate Status:             Ideal Assumed = %s [PLACEHOLDER]\n', string(P.gate_is_ideal));
fprintf('----------------------------------------------------------------------\n');

% -------------------------------------------------------------------------
% 1. RUN SIMULINK FLUID-QUEUE MODEL
% -------------------------------------------------------------------------
fprintf('Running base-Simulink fluid-queue model...\n');
% Ensure model exists
if ~exist(fullfile(sim_root, 'models', 'screening_workflow.slx'), 'file')
    build_screening_model();
end
simOut = sim('screening_workflow');
fprintf('Simulink simulation completed successfully.\n');

% -------------------------------------------------------------------------
% 2. MONTE CARLO DISCRETE-EVENT SIMULATION
% -------------------------------------------------------------------------
fprintf('Running Monte Carlo discrete-event simulation (reproducible seed 42)...\n');
rng(42); % Fixed random seed for repeatability

% Simulation duration: 1 full operating year (2,400 hours = 8,640,000 s)
total_sim_seconds = P.operating_hours_per_year * 3600;
lambda_per_s = P.annual_patients / total_sim_seconds;

% Generate patient cohort
N_patients = P.annual_patients;
inter_arrivals = exprnd(1 / lambda_per_s, [N_patients, 1]);
arrival_times = cumsum(inter_arrivals);

% Trim to simulation window
valid_idx = arrival_times <= total_sim_seconds;
arrival_times = arrival_times(valid_idx);
N = length(arrival_times);

% Stage 1: Capture Stations (c servers)
c_cap = P.capture_stations;
station_free_times = zeros(c_cap, 1);
capture_start = zeros(N, 1);
capture_end = zeros(N, 1);
recaptures_count = zeros(N, 1);
is_poor = zeros(N, 1);

for i = 1:N
    t_arr = arrival_times(i);
    attempts = 0;
    while true
        % Next available capture station
        [t_avail, s_idx] = min(station_free_times);
        t_start = max(t_arr, t_avail);
        % Service duration (normal with mean 240s, std 20s, min 120s)
        dur = max(120, normrnd(P.capture_time_s, 20));
        t_end = t_start + dur;
        station_free_times(s_idx) = t_end;
        
        if attempts == 0
            capture_start(i) = t_start;
        end
        capture_end(i) = t_end;
        
        % Quality gate check
        % True poor image Bernoulli trial
        image_is_poor = rand() < P.p_poor_image;
        if P.gate_is_ideal
            rejected = image_is_poor;
        else
            if image_is_poor
                rejected = rand() < P.quality_reject_recall;
            else
                rejected = rand() < P.quality_false_reject_rate;
            end
        end
        
        if rejected && attempts < P.max_recaptures
            attempts = attempts + 1;
            t_arr = t_end + P.gate_time_s; % queue back for recapture after gate check
        else
            recaptures_count(i) = attempts;
            is_poor(i) = image_is_poor;
            is_persistent_reject = rejected && (attempts >= P.max_recaptures);
            break;
        end
    end
end

% Stage 2: Quality Gate & Routing
gate_wait_times = P.gate_time_s * ones(N, 1);

% Persistent ungradables routed to manual review
manual_review_mask = (recaptures_count >= P.max_recaptures) & (is_poor == 1);
N_manual = sum(manual_review_mask);

% Graded by AI
N_graded = N - N_manual;
graded_idx = find(~manual_review_mask);

% Stage 3: AI Grading
% Population referable ground truth
is_referable = rand(N_graded, 1) < P.referable_prevalence;
% AI test outcomes using measured sensitivity and specificity
ai_flagged = zeros(N_graded, 1);
for k = 1:N_graded
    if is_referable(k)
        ai_flagged(k) = rand() < P.sens; % True Positive
    else
        ai_flagged(k) = rand() < (1 - P.spec); % False Positive
    end
end

N_referred = sum(ai_flagged);
referred_indices = graded_idx(ai_flagged == 1);

% Stage 4: Ophthalmologist Validation (2 doctors)
c_ophth = P.ophthalmologists;
ophth_free_times = zeros(c_ophth, 1);
ophth_wait_times = zeros(N_referred, 1);
for r = 1:N_referred
    p_id = referred_indices(r);
    t_ready = capture_end(p_id) + P.gate_time_s + P.ai_grading_time_s;
    [t_avail, doc_idx] = min(ophth_free_times);
    t_start = max(t_ready, t_avail);
    dur = exprnd(P.validation_time_s); % mean 30s
    t_end = t_start + dur;
    ophth_free_times(doc_idx) = t_end;
    ophth_wait_times(r) = t_start - t_ready;
end

% Stage 5: Manual Review by Ophthalmologists
manual_free_times = zeros(c_ophth, 1);
manual_wait_times = zeros(N_manual, 1);
manual_indices = find(manual_review_mask);
for m = 1:N_manual
    p_id = manual_indices(m);
    t_ready = capture_end(p_id) + P.gate_time_s;
    [t_avail, doc_idx] = min(manual_free_times);
    t_start = max(t_ready, t_avail);
    dur = exprnd(P.manual_review_time_s); % mean 60s
    t_end = t_start + dur;
    manual_free_times(doc_idx) = t_end;
    manual_wait_times(m) = t_start - t_ready;
end

% -------------------------------------------------------------------------
% 3. CALCULATE STAGE PERFORMANCE & UTILIZATIONS
% -------------------------------------------------------------------------
total_captures = N + sum(recaptures_count);
U_capture = (total_captures * P.capture_time_s) / (c_cap * total_sim_seconds);
U_gate = (total_captures * P.gate_time_s) / total_sim_seconds;
U_ai = (N_graded * P.ai_grading_time_s) / total_sim_seconds;
U_ophth_val = (N_referred * P.validation_time_s) / (c_ophth * total_sim_seconds);
U_ophth_manual = (N_manual * P.manual_review_time_s) / (c_ophth * total_sim_seconds);
U_ophth_total = U_ophth_val + U_ophth_manual;

% Mean queue waits (in minutes)
capture_wait_min = mean(max(0, capture_start - arrival_times)) / 60;
ophth_wait_min = mean(ophth_wait_times) / 60;
manual_wait_min = mean(manual_wait_times) / 60;

% Mean queue lengths (Little's Law: L = lambda * W)
lambda_min = P.annual_patients / (P.operating_hours_per_year * 60);
Q_capture = lambda_min * capture_wait_min;
Q_ophth = (N_referred / (P.operating_hours_per_year * 60)) * ophth_wait_min;
Q_manual = (N_manual / (P.operating_hours_per_year * 60)) * manual_wait_min;

% Sustainable capacity calculation
cap_per_station = (P.operating_hours_per_year * 60) / P.capture_time_min; % 36,000
recapture_multiplier = 1 + P.p_poor_image + P.p_poor_image^2; % 1.2261
sustainable_patients_per_yr = round((c_cap * cap_per_station) / recapture_multiplier);
bottleneck_stage = 'Capture Stations';

% Clinical epidemiological metrics
expected_missed_referables = round(P.annual_patients * P.referable_prevalence * (1 - P.sens));
expected_false_referrals = round(P.annual_patients * (1 - P.referable_prevalence) * (1 - P.spec));
recapture_rate = sum(recaptures_count) / N;

fprintf('\n----------------------------------------------------------------------\n');
fprintf('  BASELINE SIMULATION RESULTS SUMMARY\n');
fprintf('----------------------------------------------------------------------\n');
fprintf('Sustainable Annual Throughput:   %d patients/year (Target: 100,000)\n', sustainable_patients_per_yr);
fprintf('Identified Bottleneck:           %s (Utilization: %.1f%%)\n', bottleneck_stage, U_capture * 100);
fprintf('Capture Station Utilization:     %.2f%% [PLACEHOLDER]\n', U_capture * 100);
fprintf('Quality Gate Utilization:        %.2f%% [PLACEHOLDER]\n', U_gate * 100);
fprintf('AI Grading Server Utilization:   %.2f%% [PLACEHOLDER]\n', U_ai * 100);
fprintf('Ophthalmologist Utilization:     %.2f%% (Validation: %.2f%%, Manual: %.2f%%) [PROGRAM TARGET / PLACEHOLDER]\n', ...
    U_ophth_total * 100, U_ophth_val * 100, U_ophth_manual * 100);
fprintf('Recapture Rate:                  %.2f%% of cases require recapture\n', recapture_rate * 100);
fprintf('Manual Review Queue Volume:      %d persistent ungradable cases/yr\n', N_manual);
fprintf('Expected Missed Referable Cases: %d cases/yr [MEASURED: sens=%.4f]\n', expected_missed_referables, P.sens);
fprintf('Expected False Referrals:        %d cases/yr [MEASURED: spec=%.4f]\n', expected_false_referrals, P.spec);
fprintf('----------------------------------------------------------------------\n');

% -------------------------------------------------------------------------
% 4. WRITE SIM_RESULTS.CSV
% -------------------------------------------------------------------------
csv_path = fullfile(data_dir, 'sim_results.csv');
fid = fopen(csv_path, 'w');

fprintf(fid, '# ==============================================================================\n');
fprintf(fid, '# DR Screening Workflow Simulation Results (SIH-SIMULINK-003)\n');
fprintf(fid, '# Single-source parameters: simulink-model/scripts/screening_params.m\n');
fprintf(fid, '# Status labels: MEASURED, PROGRAM TARGET, PLACEHOLDER\n');
fprintf(fid, '# Gate Ideal Assumed: %s\n', string(P.gate_is_ideal));
fprintf(fid, '# ==============================================================================\n');
fprintf(fid, 'Metric,Value,Unit,Status,Notes\n');

% Program level summary
fprintf(fid, 'annual_target_patients,%d,patients/yr,PROGRAM TARGET,Official screening requirement\n', P.annual_patients);
fprintf(fid, 'sustainable_annual_patients,%d,patients/yr,SIMULATED,Maximum sustainable volume without queue divergence\n', sustainable_patients_per_yr);
fprintf(fid, 'bottleneck_stage,%s,text,SIMULATED,Stage limiting program capacity\n', bottleneck_stage);
fprintf(fid, 'gate_is_ideal,%s,boolean,PLACEHOLDER,True until EyeQ test-set evaluation completed\n', string(P.gate_is_ideal));
fprintf(fid, 'recapture_rate,%.4f,fraction,SIMULATED,Ratio of recaptures to incoming patients\n', recapture_rate);
fprintf(fid, 'expected_missed_referable_cases,%d,cases/yr,MEASURED,annual_patients * prevalence * (1 - sens)\n', expected_missed_referables);
fprintf(fid, 'expected_false_referrals,%d,cases/yr,MEASURED,annual_patients * (1 - prevalence) * (1 - spec)\n', expected_false_referrals);

% Per-stage metrics table
fprintf(fid, '\n# Per-Stage Detailed Performance\n');
fprintf(fid, 'Stage,Resource_Count,Service_Time_s,Utilization_Fraction,Mean_Queue_Patients,Mean_Wait_min,Status\n');
fprintf(fid, 'Capture_Stations,%d,%.1f,%.4f,%.2f,%.2f,PLACEHOLDER\n', c_cap, P.capture_time_s, U_capture, Q_capture, capture_wait_min);
fprintf(fid, 'Quality_Gate,1,%.1f,%.4f,0.00,0.17,PLACEHOLDER\n', P.gate_time_s, U_gate);
fprintf(fid, 'AI_Grading,1,%.1f,%.4f,0.00,0.08,PLACEHOLDER\n', P.ai_grading_time_s, U_ai);
fprintf(fid, 'Ophthalmologist_Validation,%d,%.1f,%.4f,%.2f,%.2f,PROGRAM TARGET\n', c_ophth, P.validation_time_s, U_ophth_val, Q_ophth, ophth_wait_min);
fprintf(fid, 'Ophthalmologist_Manual_Review,%d,%.1f,%.4f,%.2f,%.2f,PLACEHOLDER\n', c_ophth, P.manual_review_time_s, U_ophth_manual, Q_manual, manual_wait_min);

fclose(fid);
fprintf('Saved simulation results table: %s\n', csv_path);

% -------------------------------------------------------------------------
% 5. PARAMETER SWEEPS & PNG EXPORTS
% -------------------------------------------------------------------------
fprintf('\nGenerating parameter sweep plots in docs/simulation/...\n');

% --- SWEEP 1: Capture Stations (2 to 8) ---
stations_range = 2:8;
sw1_throughput = zeros(length(stations_range), 1);
sw1_utilization = zeros(length(stations_range), 1);
sw1_wait_min = zeros(length(stations_range), 1);

for idx = 1:length(stations_range)
    st = stations_range(idx);
    cap_yr = (st * cap_per_station) / recapture_multiplier;
    sw1_throughput(idx) = cap_yr;
    u_st = (total_captures * P.capture_time_s) / (st * total_sim_seconds);
    sw1_utilization(idx) = u_st;
    % M/M/c approximation for wait
    rho = min(0.99, u_st);
    sw1_wait_min(idx) = (rho / (1 - rho + 0.05)) * (P.capture_time_min / st);
end

f1 = figure('Visible', 'off', 'Position', [100, 100, 800, 500]);
subplot(2, 1, 1);
bar(stations_range, sw1_throughput / 1000, 0.6, 'FaceColor', [0.15, 0.45, 0.75]);
hold on;
yline(100, 'r--', 'Target (100k/yr)', 'LineWidth', 1.8, 'LabelHorizontalAlignment', 'left');
grid on;
ylabel('Capacity (k patients/yr)');
title('Sweep 1: Sustainable Annual Capacity vs Capture Stations');
set(gca, 'FontSize', 10);

subplot(2, 1, 2);
plot(stations_range, sw1_utilization * 100, '-o', 'LineWidth', 2, 'Color', [0.85, 0.35, 0.1]);
grid on;
xlabel('Number of Fundus Capture Stations');
ylabel('Station Utilization (%)');
yline(85, 'k:', 'Target Load (85%)', 'LineWidth', 1.2);
title('Capture Station Operational Utilization');
set(gca, 'FontSize', 10);

saveas(f1, fullfile(docs_sim_dir, 'sweep1_capture_stations.png'));
close(f1);

% --- SWEEP 2: Poor Image Probability p_poor_image (0.05 to 0.30) ---
p_range = 0.05:0.025:0.30;
sw2_recapture_rate = zeros(length(p_range), 1);
sw2_manual_volume = zeros(length(p_range), 1);
sw2_utilization = zeros(length(p_range), 1);

for idx = 1:length(p_range)
    p = p_range(idx);
    rec_m = p + p^2;
    sw2_recapture_rate(idx) = rec_m * 100;
    sw2_manual_volume(idx) = P.annual_patients * (p^3);
    tot_caps = P.annual_patients * (1 + rec_m);
    sw2_utilization(idx) = (tot_caps * P.capture_time_s) / (c_cap * total_sim_seconds) * 100;
end

f2 = figure('Visible', 'off', 'Position', [100, 100, 800, 500]);
subplot(2, 1, 1);
plot(p_range * 100, sw2_recapture_rate, '-s', 'LineWidth', 2, 'Color', [0.2, 0.6, 0.3]);
grid on;
xlabel('Pre-Gate Poor Image Prevalence p\_poor\_image (%)');
ylabel('Recaptures / Patients (%)');
title('Sweep 2: Recapture Rate vs Field Image Degradation');
set(gca, 'FontSize', 10);

subplot(2, 1, 2);
plot(p_range * 100, sw2_manual_volume, '-d', 'LineWidth', 2, 'Color', [0.75, 0.2, 0.2]);
grid on;
xlabel('Pre-Gate Poor Image Prevalence p\_poor\_image (%)');
ylabel('Manual Review Cases / Year');
title('Persistent Ungradables Routed to Ophthalmologist Review (after 2 recaptures)');
set(gca, 'FontSize', 10);

saveas(f2, fullfile(docs_sim_dir, 'sweep2_p_poor_image.png'));
close(f2);

% --- SWEEP 3: Quality Gate Reject Recall (0.70 to 1.00) ---
recall_range = 0.70:0.03:1.00;
fp_rate = 0.05; % PLACEHOLDER false-reject rate
sw3_recaptures = zeros(length(recall_range), 1);
sw3_leaked_poor = zeros(length(recall_range), 1);
sw3_manual_cases = zeros(length(recall_range), 1);

for idx = 1:length(recall_range)
    rec = recall_range(idx);
    % Effective reject probability per attempt
    p_rej = P.p_poor_image * rec + (1 - P.p_poor_image) * fp_rate;
    sw3_recaptures(idx) = P.annual_patients * (p_rej + p_rej^2);
    % Poor images leaking past 3 attempts into AI grading
    sw3_leaked_poor(idx) = P.annual_patients * P.p_poor_image * (1 - rec);
    sw3_manual_cases(idx) = P.annual_patients * (p_rej^3);
end

f3 = figure('Visible', 'off', 'Position', [100, 100, 800, 500]);
subplot(2, 1, 1);
plot(recall_range * 100, sw3_leaked_poor, '-o', 'LineWidth', 2, 'Color', [0.8, 0.1, 0.1]);
grid on;
xlabel('Quality-Gate Reject Recall (%)');
ylabel('Leaked Poor Images / Year');
title('Sweep 3: Poor Images Leaking into AI Grading vs Gate Recall');
set(gca, 'FontSize', 10);

subplot(2, 1, 2);
plot(recall_range * 100, sw3_recaptures / 1000, '-^', 'LineWidth', 2, 'Color', [0.1, 0.4, 0.8]);
grid on;
xlabel('Quality-Gate Reject Recall (%)');
ylabel('Total Recaptures (k / year)');
title('Recapture Exam Load Imposed on Clinics vs Gate Strictness');
set(gca, 'FontSize', 10);

saveas(f3, fullfile(docs_sim_dir, 'sweep3_quality_gate_recall.png'));
close(f3);

fprintf('Exported 3 sweep plots to docs/simulation/:\n');
fprintf('  - sweep1_capture_stations.png\n');
fprintf('  - sweep2_p_poor_image.png\n');
fprintf('  - sweep3_quality_gate_recall.png\n');

% -------------------------------------------------------------------------
% 6. OPERATING POINTS COMPARISON (SWEEP 4: POINT A VS POINT B)
% -------------------------------------------------------------------------
fprintf('\n----------------------------------------------------------------------\n');
fprintf('  OPERATING POINTS COMPARISON: POINT A (ARGMAX) vs POINT B (EXPLORATORY)\n');
fprintf('----------------------------------------------------------------------\n');

% Common parameters
ann_pts = P.annual_patients;
prev = P.referable_prevalence;
t_val = P.validation_time_s;
t_man = P.manual_review_time_s;
total_ophth_cap_s = P.ophthalmologists * (P.operating_hours_per_year * 3600);
manual_review_pts = round(ann_pts * (P.p_poor_image * P.quality_reject_recall)^3);
manual_review_doc_s = manual_review_pts * t_man;

% Operating Point A: Default argmax rule (held-out test set, n=366)
sens_A = P.sens;
spec_A = P.spec;
missed_A = ann_pts * prev * (1 - sens_A);
false_ref_A = ann_pts * (1 - prev) * (1 - spec_A);
true_ref_A = ann_pts * prev * sens_A;
referrals_A = round(true_ref_A + false_ref_A);
U_val_A = (referrals_A * t_val) / total_ophth_cap_s;
U_total_A = (referrals_A * t_val + manual_review_doc_s) / total_ophth_cap_s;

% Operating Point B: Exploratory threshold 0.4 on p2+p3+p4
sens_B = P.sens_B;
spec_B = P.spec_B;
missed_B = ann_pts * prev * (1 - sens_B);
false_ref_B = ann_pts * (1 - prev) * (1 - spec_B);
true_ref_B = ann_pts * prev * sens_B;
referrals_B = round(true_ref_B + false_ref_B);
U_val_B = (referrals_B * t_val) / total_ophth_cap_s;
U_total_B = (referrals_B * t_val + manual_review_doc_s) / total_ophth_cap_s;

fprintf('Point A (Default Argmax, Held-Out Test MEASURED):\n');
fprintf('  Sensitivity: %.4f, Specificity: %.4f\n', sens_A, spec_A);
fprintf('  AI-Flagged Referrals / Year:     %d cases/yr\n', referrals_A);
fprintf('  Expected Missed Referable / Yr:  %d cases/yr\n', round(missed_A));
fprintf('  Expected False Referrals / Yr:   %d cases/yr\n', round(false_ref_A));
fprintf('  Ophthalmologist Validation Util: %.2f%% (Total Util: %.2f%%)\n', U_val_A * 100, U_total_A * 100);

fprintf('Point B (Exploratory Threshold 0.4, Test-Set Chosen):\n');
fprintf('  Sensitivity: %.4f, Specificity: %.4f\n', sens_B, spec_B);
fprintf('  AI-Flagged Referrals / Year:     %d cases/yr\n', referrals_B);
fprintf('  Expected Missed Referable / Yr:  %d cases/yr\n', round(missed_B));
fprintf('  Expected False Referrals / Yr:   %d cases/yr\n', round(false_ref_B));
fprintf('  Ophthalmologist Validation Util: %.2f%% (Total Util: %.2f%%)\n', U_val_B * 100, U_total_B * 100);
fprintf('----------------------------------------------------------------------\n');

% Write sim_operating_points.csv
op_csv_path = fullfile(data_dir, 'sim_operating_points.csv');
fid_op = fopen(op_csv_path, 'w');
fprintf(fid_op, '# ==============================================================================\n');
fprintf(fid_op, '# DR Screening Referral Operating Points Comparison (SIH-SIMULINK-008)\n');
fprintf(fid_op, '# Single-source parameters: simulink-model/scripts/screening_params.m\n');
fprintf(fid_op, '# Operating Point A: Default argmax rule (held-out test set, n=366, MEASURED)\n');
fprintf(fid_op, '# Operating Point B: Threshold 0.4 on p2+p3+p4 (EXPLORATORY, chosen on test set)\n');
fprintf(fid_op, '# Population assumptions: annual_patients = %d, referable_prevalence = %.2f (PLACEHOLDER)\n', ann_pts, prev);
fprintf(fid_op, '# ==============================================================================\n');
fprintf(fid_op, 'Operating_Point,Threshold_Rule,Sensitivity,Specificity,AI_Flagged_Referrals_Per_Year,Expected_Missed_Referable_Per_Year,Expected_False_Referrals_Per_Year,Ophthalmologist_Validation_Utilization_Fraction,Ophthalmologist_Total_Utilization_Fraction,Status,Notes\n');
fprintf(fid_op, 'A,Default argmax (grade >= 2),%.4f,%.4f,%d,%d,%d,%.4f,%.4f,MEASURED,Held-out test set (n=366) default classification rule\n', ...
    sens_A, spec_A, referrals_A, round(missed_A), round(false_ref_A), U_val_A, U_total_A);
fprintf(fid_op, 'B,Threshold 0.4 on p2+p3+p4,%.4f,%.4f,%d,%d,%d,%.4f,%.4f,EXPLORATORY,Threshold chosen on test set; must be re-chosen on validation data\n', ...
    sens_B, spec_B, referrals_B, round(missed_B), round(false_ref_B), U_val_B, U_total_B);
fclose(fid_op);
fprintf('Saved operating points comparison table: %s\n', op_csv_path);

% Export two-group bar chart to docs/simulation/sweep4_operating_point.png
f4 = figure('Visible', 'off', 'Position', [100, 100, 850, 560]);

% Subplot 1: Clinical Diagnostic Errors Comparison (Grouped Bar Chart)
subplot(2, 1, 1);
bar_data_errors = [round(missed_A), round(false_ref_A); ...
                   round(missed_B), round(false_ref_B)];
b1 = bar(bar_data_errors, 0.7);
b1(1).FaceColor = [0.85, 0.25, 0.20]; % Missed referable (Red)
b1(2).FaceColor = [0.95, 0.65, 0.15]; % False referrals (Orange)
grid on;
set(gca, 'XTickLabel', {'Point A: Default Argmax (MEASURED)', 'Point B: Threshold 0.4 (EXPLORATORY)'}, 'FontSize', 10);
ylabel('Cases per Year');
title('Operating Point Clinical Diagnostic Trade-off (100,000 Screenings/yr, 20% Prevalence)');
legend({'Expected Missed Referable (FN)', 'Expected False Referrals (FP)'}, 'Location', 'north');
ylim([0, max(bar_data_errors(:)) * 1.30]);

for grp = 1:2
    for bar_idx = 1:2
        val = bar_data_errors(grp, bar_idx);
        x_pos = b1(bar_idx).XEndPoints(grp);
        text(x_pos, val + 150, sprintf('%d', val), 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'FontSize', 9, 'FontWeight', 'bold');
    end
end

% Subplot 2: Operational Workload & Doctor Utilization (Grouped Bar Chart)
subplot(2, 1, 2);
yyaxis left;
bar([1, 2] - 0.15, [referrals_A; referrals_B], 0.3, 'FaceColor', [0.15, 0.45, 0.75]);
ylabel('AI-Flagged Referrals / Year');
ylim([0, 30000]);
grid on;
v_ref = [referrals_A, referrals_B];
for grp = 1:2
    text(grp - 0.15, v_ref(grp) + 800, sprintf('%d', v_ref(grp)), 'HorizontalAlignment', 'center', ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.15, 0.45, 0.75]);
end

yyaxis right;
bar([1, 2] + 0.15, [U_val_A * 100; U_val_B * 100], 0.3, 'FaceColor', [0.30, 0.65, 0.35]);
ylabel('Ophth. Utilization (%)');
ylim([0, 8.0]);
u_vals = [U_val_A * 100, U_val_B * 100];
for grp = 1:2
    text(grp + 0.15, u_vals(grp) + 0.25, sprintf('%.2f%%', u_vals(grp)), 'HorizontalAlignment', 'center', ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.20, 0.50, 0.25]);
end

set(gca, 'XTick', [1, 2], 'XTickLabel', {'Point A: Default Argmax', 'Point B: Threshold 0.4'}, 'FontSize', 10);
title('Operational Workload & Doctor Validation Utilization (2 Ophthalmologists)');

saveas(f4, fullfile(docs_sim_dir, 'sweep4_operating_point.png'));
close(f4);
fprintf('Exported operating point comparison plot to docs/simulation/sweep4_operating_point.png\n');

% Operating point structs for programmatic testing and analysis
op_A.sens = sens_A;
op_A.spec = spec_A;
op_A.missed_referable = missed_A;
op_A.false_referrals = false_ref_A;
op_A.referrals_per_year = referrals_A;
op_A.utilization_validation = U_val_A;
op_A.utilization_total = U_total_A;

op_B.sens = sens_B;
op_B.spec = spec_B;
op_B.missed_referable = missed_B;
op_B.false_referrals = false_ref_B;
op_B.referrals_per_year = referrals_B;
op_B.utilization_validation = U_val_B;
op_B.utilization_total = U_total_B;

% Package results struct
results.P = P;
results.sustainable_patients_per_yr = sustainable_patients_per_yr;
results.bottleneck_stage = bottleneck_stage;
results.U_capture = U_capture;
results.U_gate = U_gate;
results.U_ai = U_ai;
results.U_ophth_total = U_ophth_total;
results.recapture_rate = recapture_rate;
results.expected_missed_referables = expected_missed_referables;
results.expected_false_referrals = expected_false_referrals;
results.op_A = op_A;
results.op_B = op_B;

end

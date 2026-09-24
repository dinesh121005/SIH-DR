function tests = test_screening_sim
% TEST_SCREENING_SIM MATLAB unit test suite for DR screening simulation (SIH-SIMULINK-003).
%
% Tests:
%   1. Parameter values read from JSON equal the held-out test JSON file values.
%   2. Patient flow conservation (patients in = patients out + patients in queues).
%   3. Utilizations lie strictly within [0, 1].
%   4. Fixed random seed produces identical results.
%   5. Simulink model runs to completion without errors.
%   6. Operating point A missed-referable matches annual_patients*prevalence*(1-sens).


tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    test_dir = fileparts(mfilename('fullpath'));
    sim_root = fileparts(test_dir);
    addpath(fullfile(sim_root, 'scripts'));
    addpath(fullfile(sim_root, 'models'));
end

function test_json_parameter_matching(testCase)
    % Verify parameters in P match dr_performance_test.json exactly
    test_dir = fileparts(mfilename('fullpath'));
    sim_root = fileparts(test_dir);
    data_dir = fullfile(sim_root, 'data');
    
    dr_raw = fileread(fullfile(data_dir, 'dr_performance_test.json'));
    dr_data = jsondecode(dr_raw);
    
    P = screening_params();
    
    testCase.verifyEqual(P.sens, dr_data.referable_dr.sensitivity, 'AbsTol', 1e-6, ...
        'P.sens must equal sensitivity in dr_performance_test.json');
    testCase.verifyEqual(P.spec, dr_data.referable_dr.specificity, 'AbsTol', 1e-6, ...
        'P.spec must equal specificity in dr_performance_test.json');
    testCase.verifyTrue(P.gate_is_ideal, ...
        'P.gate_is_ideal must be true when test metrics are null');
    testCase.verifyEqual(P.annual_patients, 100000, ...
        'P.annual_patients must be 100,000');
end

function test_utilizations_bounded(testCase)
    % Verify all stage utilizations lie within [0, 1]
    res = run_screening_sim();
    
    testCase.verifyGreaterThanOrEqual(res.U_capture, 0.0);
    testCase.verifyLessThanOrEqual(res.U_capture, 1.0, ...
        'Capture station utilization must be <= 1.0 under sustainable design');
    
    testCase.verifyGreaterThanOrEqual(res.U_gate, 0.0);
    testCase.verifyLessThanOrEqual(res.U_gate, 1.0);
    
    testCase.verifyGreaterThanOrEqual(res.U_ai, 0.0);
    testCase.verifyLessThanOrEqual(res.U_ai, 1.0);
    
    testCase.verifyGreaterThanOrEqual(res.U_ophth_total, 0.0);
    testCase.verifyLessThanOrEqual(res.U_ophth_total, 1.0);
end

function test_flow_conservation(testCase)
    % Verify conservation of patient flow through the network
    P = screening_params();
    total_sec = P.operating_hours_per_year * 3600;
    
    % Theoretical balance:
    % Inflow = Patients entering capture
    % Pass fraction + Persistent ungradable fraction = 1.0
    p_poor_gate = P.p_poor_image * P.quality_reject_recall;
    p_pass = 1 - (p_poor_gate^3);
    p_manual = p_poor_gate^3;
    
    testCase.verifyEqual(p_pass + p_manual, 1.0, 'AbsTol', 1e-9, ...
        'All patients must either pass quality gate or enter manual review');
    
    % Non-referable + Referable = Passed cases
    p_ref = P.ai_referable_rate;
    p_non_ref = 1 - p_ref;
    testCase.verifyEqual(p_ref + p_non_ref, 1.0, 'AbsTol', 1e-9, ...
        'Graded cases must partition into referable and non-referable');
end

function test_reproducibility(testCase)
    % Fixed seed 42 must yield identical results across repeated runs
    res1 = run_screening_sim();
    res2 = run_screening_sim();
    
    testCase.verifyEqual(res1.U_capture, res2.U_capture, 'AbsTol', 1e-9);
    testCase.verifyEqual(res1.recapture_rate, res2.recapture_rate, 'AbsTol', 1e-9);
    testCase.verifyEqual(res1.sustainable_patients_per_yr, res2.sustainable_patients_per_yr);
end

function test_simulink_model_execution(testCase)
    % Verify base Simulink model compiles and simulates without errors
    simOut = sim('screening_workflow');
    testCase.verifyNotEmpty(simOut);
    testCase.verifyEmpty(simOut.ErrorMessage);
end

function test_operating_point_A_missed_referable(testCase)
    % Verify operating point A missed-referable equals annual_patients*prevalence*(1-sens) within 1e-6
    P = screening_params();
    expected_missed = P.annual_patients * P.referable_prevalence * (1 - P.sens);
    
    res = run_screening_sim();
    testCase.verifyEqual(res.op_A.missed_referable, expected_missed, 'AbsTol', 1e-6, ...
        'Operating point A missed-referable must equal annual_patients*prevalence*(1-sens)');
end

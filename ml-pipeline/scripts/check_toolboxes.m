% check_toolboxes.m
% ==============================================================================
% MATLAB Toolbox Licensing and Installation Verification
% Project: AI-Powered Diabetic Retinopathy Screening Pipeline (SIH Hackathon)
% ==============================================================================

% check_toolboxes.m
% ==============================================================================
% MATLAB Toolbox Licensing and Installation Verification
% Project: AI-Powered Diabetic Retinopathy Screening Pipeline (SIH Hackathon)
% ==============================================================================

required_toolboxes = {
    'Image Processing Toolbox', 'Image_Toolbox';
    'Computer Vision Toolbox', 'Video_and_Image_Blockset';
    'Deep Learning Toolbox', 'Neural_Network_Toolbox';
    'Medical Imaging Toolbox', 'Medical_Imaging_Toolbox';
    'Simulink', 'SIMULINK';
    'Statistics and Machine Learning Toolbox', 'Statistics_Toolbox'
};

fprintf('\n');
fprintf('====================================================================\n');
fprintf('  MATLAB TOOLBOX LICENSING & AVAILABILITY VERIFICATION REPORT\n');
fprintf('====================================================================\n');
fprintf('%-40s | %-10s | %-10s | %-8s\n', 'Toolbox Name', 'Installed', 'Licensed', 'Result');
fprintf('--------------------------------------------------------------------\n');

all_passed = true;
v = ver;
installed_names = {v.Name};

for i = 1:size(required_toolboxes, 1)
    name = required_toolboxes{i, 1};
    feature = required_toolboxes{i, 2};

    installed = any(strcmpi(installed_names, name));
    licensed = license('test', feature) == 1;

    status = installed && licensed;
    if ~status
        all_passed = false;
    end

    result_str = 'FAIL';
    if status
        result_str = 'PASS';
    end

    fprintf('%-40s | %-10s | %-10s | %-8s\n', ...
        name, ...
        string(installed), ...
        string(licensed), ...
        result_str);
end

fprintf('====================================================================\n');
if all_passed
    fprintf('STATUS: ALL REQUIRED TOOLBOXES PASS VERIFICATION.\n');
else
    fprintf('STATUS: GAPS DETECTED IN LOCAL MATLAB ENVIRONMENT.\n');
    fprintf('ACTION: Install missing toolboxes via Add-Ons Explorer or use Python fallbacks.\n');
end
fprintf('====================================================================\n\n');


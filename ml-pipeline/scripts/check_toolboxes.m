% check_toolboxes.m
% ==============================================================================
% MATLAB Toolbox Licensing and Installation Verification
% Project: AI-Powered Diabetic Retinopathy Screening Pipeline (SIH Hackathon)
% ==============================================================================

function report = check_toolboxes()
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
    report = struct();

    for i = 1:size(required_toolboxes, 1)
        name = required_toolboxes{i, 1};
        feature = required_toolboxes{i, 2};

        v = ver;
        installed = any(strcmpi({v.Name}, name));
        
        % Check licensing availability
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
        
        safe_field = regexprep(name, '[^a-zA-Z0-9]', '_');
        report.(safe_field).installed = installed;
        report.(safe_field).licensed = licensed;
        report.(safe_field).passed = status;
    end

    fprintf('====================================================================\n');
    if all_passed
        fprintf('STATUS: ALL REQUIRED TOOLBOXES PASS VERIFICATION.\n');
    else
        fprintf('STATUS: GAPS DETECTED IN LOCAL MATLAB ENVIRONMENT.\n');
        fprintf('ACTION: Refer to project documentation for open-source / Python fallbacks.\n');
    end
    fprintf('====================================================================\n\n');
end

if ~isdeployed
    check_toolboxes();
end

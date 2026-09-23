@echo off
:: ==============================================================================
:: Diabetic Retinopathy Screening Pipeline - MATLAB R2026a Setup Launcher
:: ==============================================================================

set SETUP_PATH=C:\Users\dines\Downloads\_temp_matlab_R2026a_Windows\setup.exe
set INSTALLER_EXE=C:\Users\dines\Downloads\matlab_R2026a_Windows.exe

echo ==============================================================================
echo   MATLAB TOOLBOX SETUP LAUNCHER
echo ==============================================================================
echo Required Toolboxes for Diabetic Retinopathy Project:
echo   1. Image Processing Toolbox
echo   2. Computer Vision Toolbox
echo   3. Deep Learning Toolbox
echo   4. Medical Imaging Toolbox
echo   5. Simulink
echo   6. Statistics and Machine Learning Toolbox
echo ==============================================================================

if exist "%SETUP_PATH%" (
    echo Launching MathWorks setup from: %SETUP_PATH%
    start "" "%SETUP_PATH%"
) else if exist "%INSTALLER_EXE%" (
    echo Launching MathWorks installer from: %INSTALLER_EXE%
    start "" "%INSTALLER_EXE%"
) else (
    echo [ERROR] Neither setup.exe nor matlab installer found in Downloads.
    echo Please ensure MATLAB installer is present in C:\Users\dines\Downloads
)

echo.
echo After completing the installation, re-run the verification script:
echo   python ml-pipeline\scripts\check_toolboxes.py
echo ==============================================================================
pause

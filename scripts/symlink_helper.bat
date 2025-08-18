@echo off

set /p target_dir="Enter the target directory: "
set /p source_dir="Enter the source directory: "
set /p symlink_name="Enter the name for the symlinked folder: "

rem Check if the source directory exists
if not exist "%source_dir%" (
    echo Source directory does not exist.
    pause
    exit /b
)

rem Check if the target directory exists
if not exist "%target_dir%" (
    echo Target directory does not exist.
    pause
    exit /b
)

rem Create symlink
mklink /d "%target_dir%\%symlink_name%" "%source_dir%"

rem Check if symlink creation was successful
if errorlevel 1 (
    echo Failed to create symlink.
    pause
) else (
    echo Symlink created successfully.
    pause
)

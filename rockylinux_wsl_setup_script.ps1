# Set up the log file
$logFilePath = "$scriptPath\wsl_script.log"

# Function to write log messages
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "$timestamp - $message"
    Write-Output $formattedMessage
    $formattedMessage | Add-Content -Path $logFilePath
}

# Start by overwriting the log file at the beginning of the script
"Initiating WSL 2 Installer" | Out-File $logFilePath

# Set the current directory as the working path, or default to C: if not available
$scriptPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
if (-not (Test-Path $scriptPath)) {
    $scriptPath = "C:"
}

Write-Log "Script path set to $scriptPath"

$rockyFolder = "$scriptPath\rockylinux-wsl"
$rockyName = "RockyLinux"
$shortcutName = "Rocky Linux Terminal"
$shortcutPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("Desktop"), "$shortcutName.lnk")

# Define the function to check if a feature is enabled
function Check-Feature {
    param (
        [string]$featureName
    )
    $featureStatus = (Get-WindowsOptionalFeature -Online -FeatureName $featureName).State
    return $featureStatus -eq "Enabled"
}

# Define the function to enable a feature
function Enable-Feature {
    param (
        [string]$featureName
    )
    Write-Log "Enabling $featureName..."
    dism.exe /online /enable-feature /featurename:$featureName /all /norestart
    $global:restartNeeded = $true
}

Write-Log "Checking if WSL and Virtual Machine Platform are enabled"
$wslEnabled = Check-Feature -featureName "Microsoft-Windows-Subsystem-Linux"
$vmPlatformEnabled = Check-Feature -featureName "VirtualMachinePlatform"
$restartNeeded = $false

# Enable WSL if not already enabled
if (-not $wslEnabled) {
    Enable-Feature -featureName "Microsoft-Windows-Subsystem-Linux"
}

# Enable Virtual Machine Platform if not already enabled
if (-not $vmPlatformEnabled) {
    Enable-Feature -featureName "VirtualMachinePlatform"
}

# Check if either feature was enabled, set restartNeeded accordingly
if (-not $wslEnabled -or -not $vmPlatformEnabled) {
    $global:restartNeeded = $true
    Write-Log "System restart needed to enable WSL and/or Virtual Machine Platform"
}

# Prompt for restart if needed
if ($restartNeeded) {
    $userConsent = Read-Host "Changes require a restart. Do you want to restart now? (Y/N)"
    
    if ($userConsent -eq 'Y') {
        $taskName = "ReRunEnableWSLHyperV"
        Write-Log "Scheduling task $taskName for post-restart script run"
        schtasks /create /tn $taskName /tr "$scriptPath" /sc once /st 00:00 /rl highest /f
        schtasks /run /tn $taskName
        Write-Log "Restarting system"
        Restart-Computer -Force
    } else {
        Write-Log "User opted not to restart. Please restart later."
        Write-Output "Please restart your system later to complete the changes."
    }
} else {
    Write-Log "WSL and Virtual Machine Platform are already enabled. Proceeding."
}

# Step 0: Download Rocky Linux tar file for WSL2
$downloadUrl = "https://ftp.crak.in/api/public/dl/JmZsdU3H/wsl_images/rockylinux.tar"
$rockyTarPath = "./rockylinux.tar"

# Check if the tar file already exists with added error handling
try {
    Write-Log "Checking if 'rockylinux.tar' already exists"
    
    if (Test-Path -Path $rockyTarPath) {
        Write-Log "'rockylinux.tar' found"
        $overwrite = Read-Host "The file 'rockylinux.tar' already exists. Do you want to overwrite it? (y/n)"
        if ($overwrite -ne 'y') {
            Write-Log "Skipping download of 'rockylinux.tar'"
            Write-Output "Skipping download of 'rockylinux.tar'."
        } else {
            Write-Log "Downloading Rocky Linux tar file"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $rockyTarPath
            Write-Log "Download complete"
        }
    } else {
        Write-Log "'rockylinux.tar' not found, starting download"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $rockyTarPath
        Write-Log "Download complete"
    }
} catch {
    Write-Log "An error occurred while checking/downloading the tar file: $_"
    Write-Warning "An error occurred: $_. "
}

Write-Log "Step 3: Finished checking/downloading tar file"

# Function to check if the WSL 2 kernel is installed
function Check-WSL2Kernel {
    try {
        wsl --version | Out-Null
        return $true
    } catch {
        return $false
    }
}

Write-Log "Checking if WSL 2 kernel is installed"

# Function to download and install the WSL 2 kernel
function Install-WSL2Kernel {
    $kernelDownloadUrl = "https://aka.ms/wsl2kernel"
    $kernelInstallerPath = "$env:TEMP\wsl_update.msi"

    Write-Log "Downloading WSL 2 kernel installer"
    Invoke-WebRequest -Uri $kernelDownloadUrl -OutFile $kernelInstallerPath

    Write-Log "Installing WSL 2 kernel"
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $kernelInstallerPath /quiet /norestart" -Wait
    Remove-Item -Path $kernelInstallerPath

    Write-Log "WSL 2 kernel installed successfully"
}

# Check if the WSL 2 kernel is already installed
if (-not (Check-WSL2Kernel)) {
    Install-WSL2Kernel
} else {
    Write-Log "WSL 2 kernel is already installed"
}


Write-Log "Setting WSL as default version 2"
# Set WSL as default version 2
wsl --set-default-version 2

# Step 2: Create a folder at the script location if it doesn't exist
if (!(Test-Path -Path $rockyFolder)) {
    Write-Log "Creating directory at $rockyFolder"
    New-Item -ItemType Directory -Path $rockyFolder | Out-Null
} else {
    Write-Log "Directory $rockyFolder already exists"
}

# Step 3: Move the Rocky Linux tar file to the created folder
Write-Log "Moving Rocky Linux tar file to $rockyFolder"
Copy-Item -Path $rockyTarPath -Destination "$rockyFolder\rockylinux.tar" -Force

# Step 4: Import Rocky Linux into WSL
Write-Log "Importing Rocky Linux into WSL"
wsl --import $rockyName $rockyFolder "$rockyFolder\rockylinux.tar" --version 2

# Step 5: Remove the tar file after import (optional)
Write-Log "Cleaning up the tar file"
Remove-Item -Path "$rockyFolder\rockylinux.tar"

# Step 6: Create a desktop shortcut to launch Rocky Linux WSL
Write-Log "Creating shortcut for Rocky Linux Terminal"
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = "wsl.exe"
$Shortcut.Arguments = "-d $rockyName"
$Shortcut.Save()

# Function to set the locale in the Rocky Linux distribution
function Set-LinuxLocale {
    wsl.exe -d $rockyName yum -y update
    Write-Log "Setting Rocky Linux locale to en_US.UTF-8"
    
    Write-Log "You can change locale in environment variables if you want"

    wsl.exe -d $rockyName yum -y install glibc-locale-source glibc-langpack-en
    wsl.exe -d $rockyName /bin/bash -c "localedef -i en_US -f UTF-8 en_US.UTF-8"
    wsl.exe -d $rockyName source /etc/bashrc

}

# Call the function to set the locale
Set-LinuxLocale


Write-Log "Setup complete! You can launch Rocky Linux from the desktop shortcut."
Write-Output "Setup complete! You can launch Rocky Linux from the desktop shortcut."

$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$InstallDir = Join-Path $env:LOCALAPPDATA "WhisperBridge"
$Python = (Get-Command python.exe -ErrorAction Stop).Source

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -Recurse -Force (Join-Path $PackageRoot "common") $InstallDir
Copy-Item -Recurse -Force (Join-Path $PackageRoot "windows-server") $InstallDir

$Launch = Join-Path $InstallDir "windows-server\launch.py"
& $Python $Launch --install-login
Start-Process -WindowStyle Hidden -FilePath $Python -ArgumentList @("`"$Launch`"")

$TokenFile = Join-Path $env:APPDATA "WhisperBridge\token"
for ($Attempt = 0; $Attempt -lt 10 -and -not (Test-Path $TokenFile); $Attempt++) {
    Start-Sleep -Milliseconds 500
}

if (Test-Path $TokenFile) {
    $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls $TokenFile /inheritance:r /grant:r "${CurrentUser}:(R,W)" | Out-Null
    $Token = (Get-Content -Raw $TokenFile).Trim()
    Start-Process "http://localhost:9877/?token=$([uri]::EscapeDataString($Token))"
}

Write-Host "Whisper Bridge is installed and will start when you sign in."
Write-Host "Allow Python through Windows Firewall on Private networks if prompted."

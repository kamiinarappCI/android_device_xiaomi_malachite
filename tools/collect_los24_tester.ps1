# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string]$Serial,
    [string]$OutputDirectory = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\los24-captures')
)

$ErrorActionPreference = 'Stop'
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($adbCommand) {
    $captureAdbPath = $adbCommand.Source
} elseif (Test-Path -LiteralPath (Join-Path $PWD 'adb.exe')) {
    $captureAdbPath = (Join-Path $PWD 'adb.exe')
} elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'adb.exe')) {
    $captureAdbPath = (Join-Path $PSScriptRoot 'adb.exe')
} else {
    throw 'ADB was not found. Add platform-tools to PATH or run from its folder.'
}

$captureScriptPath = Join-Path $PSScriptRoot 'collect_los24_tester.sh'
if (-not (Test-Path -LiteralPath $captureScriptPath)) {
    throw 'Keep collect_los24_tester.sh beside this PowerShell script.'
}
$captureDeviceArgs = @()
if ($Serial) {
    $captureDeviceArgs = @('-s', $Serial)
}

function Invoke-CaptureAdb {
    & $captureAdbPath @captureDeviceArgs @args
    if ($LASTEXITCODE -ne 0) {
        throw "ADB command failed (exit $LASTEXITCODE): $args"
    }
}

Write-Host 'Restarting ADB with root access. Accept the USB debugging prompt if shown.'
Invoke-CaptureAdb root
Invoke-CaptureAdb wait-for-device
$captureUid = (& $captureAdbPath @captureDeviceArgs shell id -u | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $captureUid -ne '0') {
    throw 'adb root did not provide a root shell. Enable Rooted debugging in Developer options if this build provides it, then rerun.'
}

$captureName = 'los24-capture-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$captureRemoteScript = '/data/local/tmp/collect_los24_tester.sh'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$captureLocalArchive = Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path "$captureName.tar.gz"

Invoke-CaptureAdb push $captureScriptPath $captureRemoteScript
# A PTY keeps the device script interactive, including its cleanup on disconnect.
Invoke-CaptureAdb shell -tt sh $captureRemoteScript adb $captureName
Invoke-CaptureAdb shell test -s "/sdcard/Download/$captureName.tar.gz"
Invoke-CaptureAdb pull "/sdcard/Download/$captureName.tar.gz" $captureLocalArchive
Write-Host "Saved capture: $captureLocalArchive"
Write-Host 'Send it privately with the two original photos and the reproduction details.'

[CmdletBinding()]
param(
    [string]$RootPath = 'C:\Users\brian.caudill\OneDrive - Covetrus\PriceMatching',
    [switch]$ForceCredentialReset
)

$ErrorActionPreference = 'Stop'

$Folders = @(
    'Incoming',
    'Processing',
    'Archive',
    'Failed',
    'Logs',
    'State',
    'Secrets',
    'Scripts'
)

foreach ($Folder in $Folders) {
    $Path = Join-Path $RootPath $Folder
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

$CredentialPath = Join-Path $RootPath 'Secrets\SmartPakCredential.xml'

if ((Test-Path -LiteralPath $CredentialPath) -and -not $ForceCredentialReset) {
    Write-Host "Credential already exists: $CredentialPath"
    Write-Host 'Use -ForceCredentialReset only when the alias password changes.'
}
else {
    $Credential = Get-Credential -Message 'Enter the SmartPak alias credentials (DOMAIN\alias)'

    if ($null -eq $Credential) {
        throw 'Credential setup was cancelled.'
    }

    $Credential | Export-Clixml -LiteralPath $CredentialPath

    $CurrentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $CredentialPath '/inheritance:r' '/grant:r' "${CurrentIdentity}:F" | Out-Null

    Write-Host "Encrypted credential saved: $CredentialPath" -ForegroundColor Green
    Write-Host 'It can only be decrypted by this Windows user on this computer.'
}

Write-Host ''
Write-Host "SmartPak automation folders are ready under: $RootPath" -ForegroundColor Green
Write-Host 'Production upload remains disabled.' -ForegroundColor Yellow

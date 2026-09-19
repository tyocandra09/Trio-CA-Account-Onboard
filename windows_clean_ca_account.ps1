#Requires -RunAsAdministrator
<#
.SYNOPSIS
    CyberArk Account Cleanup Script for Windows.
.DESCRIPTION
    Removes ca_usr, ca_adm, and ca_recon local accounts, their local profiles,
    and the optional ca_recon password file.
.NOTES
    Run from an elevated PowerShell session.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PasswordFilePath = "C:\Users\Public\Documents\ca_recon_password.txt"
$Accounts         = @("ca_usr", "ca_adm", "ca_recon")

Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host " CyberArk Account Cleanup - Windows"          -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ""

# --- Step 1: Remove optional ca_recon password file ---
Write-Host "--- Removing password file ---" -ForegroundColor Yellow
if (Test-Path -LiteralPath $PasswordFilePath) {
    $fileSize = (Get-Item -LiteralPath $PasswordFilePath).Length
    [System.IO.File]::WriteAllBytes($PasswordFilePath, (New-Object byte[] $fileSize))
    Remove-Item -LiteralPath $PasswordFilePath -Force
    Write-Host "[OK] Password file removed: $PasswordFilePath" -ForegroundColor Green
} else {
    Write-Host "[INFO] Password file not found: $PasswordFilePath. Skipping." -ForegroundColor Gray
}

# --- Step 2: Remove local accounts ---
Write-Host ""
Write-Host "--- Removing user accounts ---" -ForegroundColor Yellow
foreach ($acct in $Accounts) {
    $user = Get-LocalUser -Name $acct -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        Write-Host "[INFO] Account '$acct' not found. Skipping." -ForegroundColor Gray
        continue
    }

    # Remove-LocalUser automatically purges all SAM group memberships
    try {
        Remove-LocalUser -Name $acct -ErrorAction Stop
        $check = Get-LocalUser -Name $acct -ErrorAction SilentlyContinue
        if ($null -eq $check) {
            Write-Host "[OK] Account '$acct' removed successfully." -ForegroundColor Green
        } else {
            Write-Warning "Account '$acct' still exists; remove it manually."
        }
    } catch {
        Write-Warning "Failed to remove account '$acct': $_"
    }
}

# --- Step 3: Remove residual local profile folders ---
Write-Host ""
Write-Host "--- Cleaning user profile directories ---" -ForegroundColor Yellow
foreach ($acct in $Accounts) {
    $profilePath = "C:\Users\$acct"
    if (Test-Path -LiteralPath $profilePath) {
        try {
            Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Profile directory removed: $profilePath" -ForegroundColor Green
        } catch {
            Write-Warning "Could not remove '$profilePath'. A process may still hold files; retry after reboot."
        }
    } else {
        Write-Host "[INFO] Profile directory not found: $profilePath. Skipping." -ForegroundColor Gray
    }
}

# --- Verification ---
Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host " CLEANUP COMPLETE"                             -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow

$remainingAccounts = @()
foreach ($acct in $Accounts) {
    $user = Get-LocalUser -Name $acct -ErrorAction SilentlyContinue
    if ($null -ne $user) {
        $remainingAccounts += $acct
    }
}

if ($remainingAccounts.Count -eq 0) {
    Write-Host "[OK] ca_usr, ca_adm, and ca_recon have been removed." -ForegroundColor Green
} else {
    Write-Host "[WARN] Remaining accounts: $($remainingAccounts -join ', ')" -ForegroundColor Red
}
Write-Host ""

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    CyberArk Account Provisioning Script for Windows
.DESCRIPTION
    Creates three local accounts for CyberArk PAM integration:
      - ca_usr   : Standard user (static password)
      - ca_adm   : Local Administrator (static password)
      - ca_recon : Reconcile account, Local Administrator privilege (random password)
                   Password is known only to the operator and sysadmin manager.
.NOTES
    Run from an elevated PowerShell session.
    Tested on Windows Server 2016/2019/2022 and Windows 10/11.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURATION - edit static passwords here before deployment
# ============================================================
$StaticPassword_ca_usr = "CyB3r@rk_Usr!2025"
$StaticPassword_ca_adm = "CyB3r@rk_Adm!2025"

$PasswordFilePath    = "C:\Users\Public\Documents\ca_recon_password.txt"
$ReconPasswordLength = 16

# ============================================================
# FUNCTIONS
# ============================================================

function New-RandomPassword {
    param([int]$Length = 16)

    # Character pools
    $upper   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $lower   = "abcdefghijklmnopqrstuvwxyz"
    $digits  = "0123456789"
    $symbols = "!@#$%^&*()-_=+[]{}|;:,.<>?"

    # Guarantee at least one from each pool
    $mandatory  = $upper[(Get-Random -Maximum $upper.Length)]
    $mandatory += $lower[(Get-Random -Maximum $lower.Length)]
    $mandatory += $digits[(Get-Random -Maximum $digits.Length)]
    $mandatory += $symbols[(Get-Random -Maximum $symbols.Length)]

    $allChars  = $upper + $lower + $digits + $symbols
    $remaining = $Length - 4

    for ($i = 0; $i -lt $remaining; $i++) {
        $mandatory += $allChars[(Get-Random -Maximum $allChars.Length)]
    }

    # Shuffle (Fisher-Yates)
    $charArray = $mandatory.ToCharArray()
    for ($i = $charArray.Length - 1; $i -gt 0; $i--) {
        $j          = Get-Random -Maximum ($i + 1)
        $tmp        = $charArray[$i]
        $charArray[$i] = $charArray[$j]
        $charArray[$j] = $tmp
    }

    return -join $charArray
}

function New-LocalUserAccount {
    param(
        [string]$Username,
        [string]$Password,
        [string]$FullName,
        [string]$Description
    )

    $existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Write-Warning "Account '$Username' already exists. Skipping creation."
        return $false
    }

    # Windows Local SAM limits Description (usri1_comment) to 48 chars
    if ($Description.Length -gt 48) {
        $Description = $Description.Substring(0, 48)
    }

    $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Username `
                  -Password $secPass `
                  -FullName $FullName `
                  -Description $Description `
                  -PasswordNeverExpires `
                  -UserMayNotChangePassword `
                  -AccountNeverExpires | Out-Null

    # Verify using built-in cmdlet
    $created = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($null -ne $created) {
        Write-Host "[OK] Account '$Username' created successfully. (Enabled: $($created.Enabled))" -ForegroundColor Green
        return $true
    } else {
        Write-Error "Failed to create account '$Username'."
        return $false
    }
}

function Add-ToLocalGroup {
    param(
        [string]$GroupName,
        [string]$Username
    )

    try {
        Add-LocalGroupMember -Group $GroupName -Member $Username -ErrorAction Stop
        Write-Host "[OK] $Username -> '$GroupName' group" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -match "already a member") {
            Write-Host "[INFO] '$Username' is already a member of '$GroupName'." -ForegroundColor Gray
        } else {
            Write-Warning "Failed to add '$Username' to '$GroupName': $_"
        }
    }
}

# ============================================================
# MAIN
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host " CyberArk Account Provisioning - Windows"     -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ""

# --- Step 1: Generate random password for ca_recon ---
$ReconPassword = New-RandomPassword -Length $ReconPasswordLength

# --- Step 2: Ask user how to handle ca_recon password ---
Write-Host "How would you like to handle the ca_recon password?" -ForegroundColor Cyan
Write-Host "  [1] Save to file only   ($PasswordFilePath)"
Write-Host "  [2] Display in terminal only"
Write-Host "  [3] Save to file AND display in terminal"
Write-Host ""

do {
    $choice = Read-Host "Select option (1/2/3)"
} while ($choice -notin @("1", "2", "3"))

# --- Step 3: Create accounts ---
Write-Host ""
Write-Host "--- Creating accounts ---" -ForegroundColor Yellow

New-LocalUserAccount -Username    "ca_usr" `
                     -Password    $StaticPassword_ca_usr `
                     -FullName    "CyberArk Managed User" `
                     -Description "CyberArk PAM - Standard Account"

New-LocalUserAccount -Username    "ca_adm" `
                     -Password    $StaticPassword_ca_adm `
                     -FullName    "CyberArk Managed Admin" `
                     -Description "CyberArk PAM - Admin Account"

New-LocalUserAccount -Username    "ca_recon" `
                     -Password    $ReconPassword `
                     -FullName    "CyberArk Reconcile Account" `
                     -Description "CyberArk PAM - Reconcile Account"

# --- Step 4: Assign group memberships ---
Write-Host ""
Write-Host "--- Configuring privileges ---" -ForegroundColor Yellow

# ca_usr -> Users (standard, no elevation)
Add-ToLocalGroup -GroupName "Users" -Username "ca_usr"

# ca_adm -> Administrators
Add-ToLocalGroup -GroupName "Administrators" -Username "ca_adm"

# ca_recon -> Administrators (same as ca_adm; password held by operator + sysadmin manager only)
Add-ToLocalGroup -GroupName "Administrators" -Username "ca_recon"

# --- Step 5: Handle ca_recon password output ---
Write-Host ""
Write-Host "--- ca_recon password handling ---" -ForegroundColor Yellow

$passwordContent = @"
# CyberArk Reconcile Account Password
# Generated : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Host      : $env:COMPUTERNAME
# WARNING   : Store securely. Delete this file after onboarding ca_recon to CyberArk Vault.
#             This password must be known ONLY by the operator and sysadmin manager.

Username: ca_recon
Password: $ReconPassword
"@

switch ($choice) {
    "1" {
        $passwordContent | Out-File -FilePath $PasswordFilePath -Encoding UTF8 -Force

        # Restrict ACL: Administrators + SYSTEM only
        $acl = Get-Acl $PasswordFilePath
        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")))
        Set-Acl -Path $PasswordFilePath -AclObject $acl

        Write-Host "[OK] Password saved to  : $PasswordFilePath" -ForegroundColor Green
        Write-Host "     ACL restricted to  : Administrators, SYSTEM" -ForegroundColor Gray
    }
    "2" {
        Write-Host ""
        Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
        Write-Host "|  ca_recon Password (COPY NOW - shown once)  |" -ForegroundColor Magenta
        Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
        Write-Host "|  $ReconPassword                           |" -ForegroundColor White
        Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
        Write-Host ""
    }
    "3" {
        $passwordContent | Out-File -FilePath $PasswordFilePath -Encoding UTF8 -Force

        $acl = Get-Acl $PasswordFilePath
        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")))
        Set-Acl -Path $PasswordFilePath -AclObject $acl

        Write-Host "[OK] Password saved to  : $PasswordFilePath" -ForegroundColor Green
        Write-Host "     ACL restricted to  : Administrators, SYSTEM" -ForegroundColor Gray
        Write-Host ""
        Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
        Write-Host "|  ca_recon Password                          |" -ForegroundColor Magenta
        Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
        Write-Host "|  $ReconPassword                           |" -ForegroundColor White
        Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
        Write-Host ""
    }
}

# --- Summary ---
Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host " PROVISIONING COMPLETE"                        -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host " Account Summary:" -ForegroundColor Cyan

$allGroups = @(Get-LocalGroup -ErrorAction SilentlyContinue)

foreach ($acct in @("ca_usr", "ca_adm", "ca_recon")) {
    $user = Get-LocalUser -Name $acct -ErrorAction SilentlyContinue
    if ($null -ne $user) {
        $userGroups = [System.Collections.Generic.List[string]]::new()
        foreach ($grp in $allGroups) {
            try {
                $members = @(Get-LocalGroupMember -Group $grp.Name -ErrorAction Stop)
                foreach ($m in $members) {
                    if ($null -ne $m -and $m.Name -like "*\$acct") {
                        $userGroups.Add($grp.Name)
                        break
                    }
                }
            } catch {
                # Ignore groups that cannot be enumerated (e.g. IIS, virtual accounts)
            }
        }
        $groupStr = if ($userGroups.Count -gt 0) { $userGroups -join ", " } else { "None" }
        Write-Host "   $acct  |  Enabled: $($user.Enabled)  |  Groups: $groupStr" -ForegroundColor White
    }
}

Write-Host ""
Write-Host " Next Steps:" -ForegroundColor Cyan
Write-Host "   1. Onboard ca_usr and ca_adm to CyberArk Vault with their static passwords." -ForegroundColor Gray
Write-Host "   2. Onboard ca_recon as the reconcile account in the platform configuration." -ForegroundColor Gray
Write-Host "   3. Delete the password file after onboarding (if option 1 or 3 was selected)." -ForegroundColor Gray
Write-Host ""

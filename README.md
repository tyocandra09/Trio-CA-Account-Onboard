# Trio-CA-Account-Onboard

Automated provisioning and decommissioning toolkit for onboarding local accounts to **CyberArk Privileged Access Management (PAM)** on Windows and Linux targets.

---

## 📌 Architecture & Account Roles

This toolkit provisions three standardized local accounts configured for CyberArk Central Policy Manager (CPM) management and password rotation:

| Account | Target Platform | Privilege Level | Password Policy | Primary CyberArk Role |
|---|---|---|---|---|
| `ca_usr` | Windows / Linux | Standard User (no elevation) | Static (configured in script) | Managed Target User Account |
| `ca_adm` | Windows | `Administrators` local group | Static (configured in script) | Managed Privileged / Admin Account |
| `ca_adm` | Linux | `sudo` or `wheel` group | Static (configured in script) | Managed Privileged / Admin Account |
| `ca_recon` | Windows | `Administrators` local group | Random 16-char (upper, lower, digits, symbols) | Reconcile Account (held by operator & sysadmin manager) |
| `ca_recon` | Linux | Standard User + targeted `sudoers` delegation | Random 16-char (upper, lower, digits, symbols) | Reconcile Account (least-privilege `passwd` reset only) |

### Reconcile Account Password Handling
During provisioning, you will be prompted with three options for `ca_recon`:
1. **Option 1**: Save to secure file only
   - **Windows**: `C:\Users\Public\Documents\ca_recon_password.txt` (ACL restricted to `Administrators` & `SYSTEM`)
   - **Linux**: `/home/<active_user>/ca_recon_password.txt` (chmod `0400`, owned by active non-root user)
2. **Option 2**: Display on terminal only (one-time copy)
3. **Option 3**: Save to file **and** display on terminal

> ⚠️ **Security Notice**: Immediately delete the password file once `ca_recon` is securely onboarded into the CyberArk Vault.

---

## 🚀 Execution Guide: Windows

> **Prerequisite**: Run PowerShell or Command Prompt as **Administrator** (`Run as Administrator`).

### 1. `windows_make_ca_account.ps1` (Provisioning)

#### Option A: One-Liner Execution (No download required)

**PowerShell (Elevated):**
```powershell
irm https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/windows_make_ca_account.ps1 | iex
```

**Command Prompt / CMD (Elevated):**
```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/windows_make_ca_account.ps1 | iex"
```

---

#### Option B: Download First, Then Execute

**PowerShell (Elevated):**
```powershell
# Download script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/windows_make_ca_account.ps1" -OutFile "windows_make_ca_account.ps1"

# Execute
.\windows_make_ca_account.ps1
```

**Command Prompt / CMD (Elevated):**
```cmd
:: Download via curl (built-in Windows 10/11 / Server 2019+)
curl -sSL "https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/windows_make_ca_account.ps1" -o windows_make_ca_account.ps1

:: Execute via PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows_make_ca_account.ps1
```

---

### 2. `windows_clean_ca_account.ps1` (Decommissioning)

Purges `ca_usr`, `ca_adm`, `ca_recon`, their local user profiles, and the password file.

#### Option A: One-Liner Execution

**PowerShell (Elevated):**
```powershell
irm https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/windows_clean_ca_account.ps1 | iex
```

**Command Prompt / CMD (Elevated):**
```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/windows_clean_ca_account.ps1 | iex"
```

---

#### Option B: Download First, Then Execute

**PowerShell (Elevated):**
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/windows_clean_ca_account.ps1" -OutFile "windows_clean_ca_account.ps1"
.\windows_clean_ca_account.ps1
```

**Command Prompt / CMD (Elevated):**
```cmd
curl -sSL "https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/windows_clean_ca_account.ps1" -o windows_clean_ca_account.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows_clean_ca_account.ps1
```

---

## 🐧 Execution Guide: Linux

> **Prerequisite**: Must be executed with `root` privileges or via `sudo`.

### 1. `linux_make_ca_account.sh` (Provisioning)

#### Option A: One-Liner Execution (Interactive Prompt Supported)

**Using `curl`:**
```bash
curl -sSL https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/linux_make_ca_account.sh | sudo bash
```

**Using `wget`:**
```bash
wget -qO- https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/linux_make_ca_account.sh | sudo bash
```

---

#### Option B: Download First, Then Execute

**Using `curl`:**
```bash
# Download
curl -sSLO https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/linux_make_ca_account.sh

# Make executable & run
chmod +x linux_make_ca_account.sh
sudo ./linux_make_ca_account.sh
```

**Using `wget`:**
```bash
# Download
wget https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/linux_make_ca_account.sh

# Make executable & run
chmod +x linux_make_ca_account.sh
sudo ./linux_make_ca_account.sh
```

---

### 2. `linux_clean_ca_account.sh` (Decommissioning)

Purges `ca_usr`, `ca_adm`, `ca_recon`, home directories, custom sudoers rules, and securely shreds the generated password file.

#### Option A: One-Liner Execution

**Using `curl`:**
```bash
curl -sSL https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/linux_clean_ca_account.sh | sudo bash
```

**Using `wget`:**
```bash
wget -qO- https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/linux_clean_ca_account.sh | sudo bash
```

---

#### Option B: Download First, Then Execute

```bash
# Download
curl -sSLO https://raw.githubusercontent.com/tyocandra09/Trio-CA-Account-Onboard/refs/heads/main/linux_clean_ca_account.sh

# Make executable & run
chmod +x linux_clean_ca_account.sh
sudo ./linux_clean_ca_account.sh
```

---

## 🔒 Security & Hardening Details

1. **Pure ASCII Encoding**: All scripts avoid Unicode/multibyte box-drawing characters to prevent terminal Mojibake across non-UTF8 consoles and Windows PowerShell 5.1 default codepages.
2. **Linux Least Privilege Delegation**: `ca_recon` on Linux is granted strict, non-interactive password reset rights solely for `ca_usr` and `ca_adm` via `/etc/sudoers.d/cyberark_recon`:
   ```text
   ca_recon ALL=(root) NOPASSWD: /usr/bin/passwd ca_usr, /usr/bin/passwd ca_adm
   ```
3. **Secure Deletion**: Cleanup scripts use `shred -u -z` (falling back to `dd` zero-fill) on Linux and `System.IO.File::WriteAllBytes` zero-fill on Windows before removing password files.
4. **SAM Description Constraint**: Windows account descriptions strictly adhere to the 48-character limit enforced by the Win32 `MAXCOMMENTSZ` parameter in `New-LocalUser`.

---

## ⚙️ Post-Provisioning Workflow (CyberArk PAM)

1. **Vault Onboarding**:
   - Onboard `ca_usr` into target Safe with its static password.
   - Onboard `ca_adm` into target Safe with its static password.
   - Onboard `ca_recon` into target Safe with the generated 16-character password.
2. **Platform Association**:
   - Link `ca_recon` as the **Reconcile Account** in the CyberArk platform settings for `ca_usr` and `ca_adm`.
3. **Password File Sanitization**:
   - Verify that all three accounts are synchronized and managed in the Vault.
   - Delete the password file (`ca_recon_password.txt`) from the target machine.

#!/usr/bin/env bash
#
# CyberArk Account Cleanup Script for Linux
# ==========================================
# Removes the three CyberArk local accounts (ca_usr, ca_adm, ca_recon)
# and cleans up associated artifacts (password file, sudoers entries, SSH config).
#
# Must be run as root or with sudo.

set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================
ACCOUNTS=("ca_usr" "ca_adm" "ca_recon")
PASSWORD_FILENAME="ca_recon_password.txt"
SUDOERS_RECON="/etc/sudoers.d/cyberark_recon"
SUDOERS_ADM="/etc/sudoers.d/cyberark_ca_adm"

# Detect the active non-root user who invoked sudo (for password file path)
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    ACTIVE_USER="${SUDO_USER}"
else
    ACTIVE_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /nologin|false/ {print $1; exit}' /etc/passwd)
fi

if [[ -n "${ACTIVE_USER:-}" ]]; then
    ACTIVE_USER_HOME=$(eval echo "~${ACTIVE_USER}")
    PASSWORD_FILE_PATH="${ACTIVE_USER_HOME}/${PASSWORD_FILENAME}"
else
    PASSWORD_FILE_PATH=""
fi

# ============================================================
# PRE-FLIGHT CHECKS
# ============================================================
if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root or with sudo."
    exit 1
fi

# ============================================================
# FUNCTIONS
# ============================================================

secure_delete_file() {
    local filepath="$1"
    if [[ -f "${filepath}" ]]; then
        # Overwrite with zeros before deletion (basic sanitization)
        # Use shred if available, otherwise dd
        if command -v shred &>/dev/null; then
            shred -u -z -n 3 "${filepath}"
            echo "[OK] File securely shredded and removed: ${filepath}"
        else
            local filesize
            filesize=$(stat -c%s "${filepath}" 2>/dev/null || echo 0)
            if [[ "${filesize}" -gt 0 ]]; then
                dd if=/dev/zero of="${filepath}" bs=1 count="${filesize}" conv=notrunc &>/dev/null
            fi
            rm -f "${filepath}"
            echo "[OK] File zeroed and removed: ${filepath}"
        fi
    else
        echo "[INFO] File not found: ${filepath}. Skipping."
    fi
}

remove_user_account() {
    local username="$1"

    if id "${username}" &>/dev/null; then
        # Kill any active sessions for this user
        pkill -u "${username}" 2>/dev/null || true

        # Remove user and their home directory
        userdel -r "${username}" 2>/dev/null || userdel "${username}" 2>/dev/null || true

        # Verify removal using built-in getent
        if ! getent passwd "${username}" &>/dev/null; then
            echo "[OK] Account '${username}' removed successfully."
        else
            echo "[WARN] Account '${username}' may not have been fully removed. Check manually."
        fi
    else
        echo "[INFO] Account '${username}' not found. Skipping."
    fi
}

# ============================================================
# MAIN
# ============================================================

echo ""
echo "============================================="
echo " CyberArk Account Cleanup - Linux"
echo "============================================="
echo ""

# --- Step 1: Remove sudoers delegation files ---
echo "--- Removing sudoers delegation ---"

if [[ -f "${SUDOERS_RECON}" ]]; then
    rm -f "${SUDOERS_RECON}"
    echo "[OK] Sudoers file removed: ${SUDOERS_RECON}"
else
    echo "[INFO] Sudoers file not found: ${SUDOERS_RECON}. Skipping."
fi

if [[ -f "${SUDOERS_ADM}" ]]; then
    rm -f "${SUDOERS_ADM}"
    echo "[OK] Sudoers file removed: ${SUDOERS_ADM}"
else
    echo "[INFO] Sudoers file not found: ${SUDOERS_ADM}. Skipping."
fi

# --- Step 2: Remove SSH config block for ca_recon ---
echo ""
echo "--- Removing SSH config entries ---"

if [[ -f /etc/ssh/sshd_config ]]; then
    if grep -q "# CyberArk ca_recon restriction" /etc/ssh/sshd_config; then
        # Remove the Match block added by the provisioning script
        sed -i '/^# CyberArk ca_recon restriction/,/^ForceCommand \/bin\/bash$/d' /etc/ssh/sshd_config
        # Clean up any trailing blank lines left behind
        sed -i '/^[[:space:]]*$/N;/^\n[[:space:]]*$/d' /etc/ssh/sshd_config
        echo "[OK] SSH config block for ca_recon removed from /etc/ssh/sshd_config"
        echo "     Restart sshd to apply: systemctl restart sshd"
    else
        echo "[INFO] No CyberArk SSH config block found in sshd_config. Skipping."
    fi
else
    echo "[INFO] /etc/ssh/sshd_config not found. Skipping."
fi

# --- Step 3: Remove password file ---
echo ""
echo "--- Removing password file ---"

if [[ -n "${PASSWORD_FILE_PATH}" ]]; then
    secure_delete_file "${PASSWORD_FILE_PATH}"
else
    echo "[INFO] Could not determine active user home directory. Skipping password file removal."
    echo "       Manually check and remove: ~/ca_recon_password.txt"
fi

# --- Step 4: Remove user accounts ---
echo ""
echo "--- Removing user accounts ---"

for acct in "${ACCOUNTS[@]}"; do
    remove_user_account "${acct}"
done

# --- Step 5: Clean up any residual home directories ---
echo ""
echo "--- Checking for residual home directories ---"

for acct in "${ACCOUNTS[@]}"; do
    for base_dir in /home /root; do
        local_dir="${base_dir}/${acct}"
        if [[ -d "${local_dir}" ]]; then
            rm -rf "${local_dir}"
            echo "[OK] Residual directory removed: ${local_dir}"
        fi
    done
done

# --- Step 6: Remove from /etc/group if any residual entries ---
echo ""
echo "--- Cleaning group entries ---"

for acct in "${ACCOUNTS[@]}"; do
    # Check if any group still references these users
    if grep -q "\b${acct}\b" /etc/group 2>/dev/null; then
        # Use gpasswd or sed to remove residual group memberships
        while IFS=: read -r grpname _ _ members; do
            if echo "${members}" | grep -qw "${acct}"; then
                gpasswd -d "${acct}" "${grpname}" 2>/dev/null || true
                echo "[OK] Removed '${acct}' from group '${grpname}'"
            fi
        done < /etc/group
    fi
done

# --- Summary ---
echo ""
echo "============================================="
echo " CLEANUP COMPLETE"
echo "============================================="
echo ""
echo " Verification:"

remaining=()
for acct in "${ACCOUNTS[@]}"; do
    if id "${acct}" &>/dev/null; then
        remaining+=("${acct}")
    fi
done

if [[ ${#remaining[@]} -eq 0 ]]; then
    echo "   All CyberArk accounts (ca_usr, ca_adm, ca_recon) have been removed."
else
    echo "   WARNING: The following accounts still exist: ${remaining[*]}"
    echo "   Run 'id <username>' to verify and remove manually if needed."
fi

echo ""
echo " Artifacts cleaned:"
echo "   - Sudoers delegation: ${SUDOERS_RECON}"
echo "   - Sudoers delegation: ${SUDOERS_ADM}"
echo "   - Password file:      ${PASSWORD_FILE_PATH:-N/A}"
echo "   - SSH config block:   /etc/ssh/sshd_config (ca_recon Match block)"
echo ""
echo " Reminder: Restart sshd if SSH config was modified."
echo "   systemctl restart sshd"
echo ""

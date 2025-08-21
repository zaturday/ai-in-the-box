#!/bin/bash

# ==============================================================================
# RHEL 9 Hardening Script
#
# This script applies or rolls back security configurations.
#
# Usage:
#   sudo ./harden_rhel9.sh --remediate   (Applies hardening)
#   sudo ./harden_rhel9.sh --rollback    (Reverts changes)
#   sudo ./harden_rhel9.sh --enable-ssh-root  (Enables SSH root access)
#
# Configurations:
# 1. Sets password quality rules.
# 2. Configures password aging, history, and hashing algorithm.
# 3. Implements an account lockout policy for failed logins.
# 4. Restricts direct root login to the physical console.
# 5. Sets inactive account locking policy.
# 6. Disables passwords for all system accounts with nologin shell.
# 7. Option to enable SSH root access with proper PAM configuration.
# ==============================================================================

# --- Script Preliminaries ---

# Exit immediately if a command exits with a non-zero status.
set -e

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

# --- Helper Functions ---

# Creates a timestamped backup of a file.
backup_file() {
  local file_path=$1
  if [ -f "$file_path" ]; then
    # Avoid making backups of backups
    if [[ ! $file_path =~ \.bak_[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        cp "$file_path" "$file_path.bak_$(date +%F_%T)"
        echo "Backed up $file_path"
    fi
  fi
}

# Restores the most recent backup of a file.
restore_backup() {
    local file_path=$1
    local latest_backup
    latest_backup=$(ls -t "$file_path".bak_* 2>/dev/null | head -n 1)

    if [ -f "$latest_backup" ]; then
        cp "$latest_backup" "$file_path"
        echo "Restored $file_path from $latest_backup"
    else
        echo "Warning: No backup found for $file_path. Cannot restore."
    fi
}


# Sets a configuration value in a file (key = value format).
set_config() {
    # Usage: set_config FILE KEY VALUE [SEPARATOR]
    local file=$1
    local key=$2
    local value=$3
    # Default separator is " = ", handles spaces. For login.defs, we'll use a tab.
    local separator=${4:-"[[:space:]]*=[[:space:]]*"} 
    
    # Escape special characters for sed
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's:[][\\/.^$*]:\\&:g')

    # Check if the key exists and update it, otherwise append it.
    if grep -q -E "^${key}${separator}.*" "$file"; then
        sed -i -E "s/^((${key})${separator}).*/\1${escaped_value}/" "$file"
        echo "Updated '${key}' in ${file}"
    else
        # If appending, use a clean separator.
        local clean_separator=${4:-" = "}
        if [[ "$separator" == "[[:space:]]\+" ]]; then
            clean_separator="   " # Use spaces if tab is specified for alignment
        fi
        echo "${key}${clean_separator}${value}" >> "$file"
        echo "Added '${key}' to ${file}"
    fi
}

# --- Core Functions ---

remediate() {
    echo "Starting RHEL 9 hardening process..."
    echo "-----------------------------------------------------"

    # 1. Configure Password Quality
    echo "Configuring Password Quality in /etc/security/pwquality.conf..."
    PWQUALITY_CONF="/etc/security/pwquality.conf"
    backup_file "$PWQUALITY_CONF"
    set_config "$PWQUALITY_CONF" "retry" "3"
    set_config "$PWQUALITY_CONF" "minlen" "8"
    set_config "$PWQUALITY_CONF" "dcredit" "-1"
    set_config "$PWQUALITY_CONF" "ocredit" "-1"
    set_config "$PWQUALITY_CONF" "lcredit" "-1"
    set_config "$PWQUALITY_CONF" "ucredit" "-1"
    echo "Password quality settings applied."
    echo

    # 2. Configure Password Aging and Length Defaults
    echo "Configuring Password Policies in /etc/login.defs..."
    LOGIN_DEFS="/etc/login.defs"
    backup_file "$LOGIN_DEFS"
    set_config "$LOGIN_DEFS" "PASS_MAX_DAYS" "30" "[[:space:]]+"
    set_config "$LOGIN_DEFS" "PASS_MIN_DAYS" "7" "[[:space:]]+"
    set_config "$LOGIN_DEFS" "PASS_MIN_LEN" "8" "[[:space:]]+"
    set_config "$LOGIN_DEFS" "PASS_WARN_AGE" "7" "[[:space:]]+"
    echo "Password aging and length defaults applied."
    echo

    # 3. Configure PAM for History, Hashing, and Lockout using authselect
    echo "Configuring PAM for password history, hashing, and account lockout..."
    PROFILE_NAME="custom-hardening"
    if ! authselect list | grep -q "custom/${PROFILE_NAME}"; then
      echo "Creating custom authselect profile '${PROFILE_NAME}'..."
      BASE_PROFILE=$(authselect current | awk '/^Profile ID:/ {print $3}')
      authselect create-profile "${PROFILE_NAME}" -b "${BASE_PROFILE}" --symlink-meta
    else
      echo "Custom authselect profile '${PROFILE_NAME}' already exists. Proceeding to modify it."
    fi
    authselect select "custom/${PROFILE_NAME}" --force
    CUSTOM_SYSTEM_AUTH="/etc/authselect/custom/${PROFILE_NAME}/system-auth"
    CUSTOM_PASSWORD_AUTH="/etc/authselect/custom/${PROFILE_NAME}/password-auth"
    echo "Setting password history to remember 5 passwords..."
    sed -i '/pam_pwhistory.so/ {s/ remember=[0-9]\+//g; s/$/ remember=5/}' "$CUSTOM_SYSTEM_AUTH" "$CUSTOM_PASSWORD_AUTH"
    echo "Enforcing sha512 password hashing..."
    sed -i '/pam_unix.so/ {/sha512/! s/$/ sha512/}' "$CUSTOM_SYSTEM_AUTH" "$CUSTOM_PASSWORD_AUTH"
    echo "Setting account lockout after 3 failed attempts for 15 minutes (root user exempt)..."
    sed -i '/pam_faillock.so/d' "$CUSTOM_SYSTEM_AUTH" "$CUSTOM_PASSWORD_AUTH"
    for pam_file in "$CUSTOM_SYSTEM_AUTH" "$CUSTOM_PASSWORD_AUTH"; do
        sed -i '/^auth\s*sufficient\s*pam_unix.so/i auth        required      pam_faillock.so preauth silent audit deny=3 unlock_time=900' "$pam_file"
        sed -i '/^auth\s*sufficient\s*pam_unix.so/i auth        [default=die] pam_faillock.so authfail audit deny=3 unlock_time=900' "$pam_file"
        sed -i '/^account\s*required\s*pam_unix.so/a account     required      pam_faillock.so' "$pam_file"
    done
    echo "Applying PAM profile changes..."
    authselect apply-changes -b
    echo "PAM configured successfully."
    echo

    # 4. Restrict Root Login
    echo "Restricting root login to console and tty1..."
    SECURETTY_FILE="/etc/securetty"
    backup_file "$SECURETTY_FILE"
    echo -e "console\ntty1" > "$SECURETTY_FILE"
    echo "Root login restricted."
    echo

    # 5. Set Inactive Account Lock
    echo "Setting inactive account lock to 30 days..."
    USERADD_CONF="/etc/default/useradd"
    backup_file "$USERADD_CONF"
    set_config "$USERADD_CONF" "INACTIVE" "30"
    echo "Inactive account lock applied."
    echo

    # 6. Disable Passwords for nologin Accounts
    echo "Disabling passwords for system accounts with nologin shell..."
    for user in $(getent passwd | grep '/sbin/nologin' | cut -d: -f1); do
      if [[ $(passwd -S "$user" | awk '{print $2}') != "L" ]]; then
        passwd -l "$user" > /dev/null
        echo "Locked password for system account: $user"
      fi
    done
    echo "System account passwords disabled."
    echo

    echo "-----------------------------------------------------"
    echo "Hardening script completed successfully!"
    echo "It is recommended to reboot the system for all changes to take full effect."
}

rollback() {
    echo "Starting rollback of hardening configurations..."
    echo "-----------------------------------------------------"

    # 1 & 2. Restore config files from backup
    echo "Restoring configuration files from backups..."
    restore_backup "/etc/security/pwquality.conf"
    restore_backup "/etc/login.defs"
    restore_backup "/etc/default/useradd"
    restore_backup "/etc/securetty"
    echo

    # 3. Revert PAM configuration
    echo "Reverting PAM configuration to system default..."
    PROFILE_NAME="custom-hardening"
    # Revert to a common default like sssd, change if your system uses something else
    authselect select sssd --force
    if [ -d "/etc/authselect/custom/${PROFILE_NAME}" ]; then
        rm -rf "/etc/authselect/custom/${PROFILE_NAME}"
        echo "Custom authselect profile '${PROFILE_NAME}' deleted."
    fi
    authselect apply-changes -b
    echo "PAM configuration reverted."
    echo

    # 6. Unlock passwords for nologin accounts
    echo "Unlocking passwords for system accounts with nologin shell..."
    for user in $(getent passwd | grep '/sbin/nologin' | cut -d: -f1); do
        if [[ $(passwd -S "$user" | awk '{print $2}') == "L" ]]; then
            passwd -u "$user" > /dev/null
            echo "Unlocked password for system account: $user"
        fi
    done
    echo "System account passwords unlocked."
    echo
    
    # 7. Restore SSH configuration if it was modified
    echo "Restoring SSH configuration..."
    restore_backup "/etc/ssh/sshd_config"
    echo "SSH configuration restored."
    echo
    
    # 8. Restore securetty if it was modified
    echo "Restoring securetty configuration..."
    restore_backup "/etc/securetty"
    echo "Securetty configuration restored."
    echo
    
    # 9. Revert PAM configuration for SSH root access
    echo "Reverting PAM configuration for SSH root access..."
    PROFILE_NAME="custom-ssh-root"
    if [ -d "/etc/authselect/custom/${PROFILE_NAME}" ]; then
        rm -rf "/etc/authselect/custom/${PROFILE_NAME}"
        echo "Custom authselect profile '${PROFILE_NAME}' deleted."
    fi
    authselect select sssd --force
    authselect apply-changes -b
    echo "PAM configuration for SSH root access reverted."
    echo
    
    # 10. Restart SSH service
    echo "Restarting SSH service..."
    systemctl restart sshd
    echo "SSH service restarted."
    echo

    echo "-----------------------------------------------------"
    echo "Rollback completed successfully!"
    echo "It is recommended to reboot the system for all changes to take full effect."
}

enable_ssh_root() {
    echo "Enabling SSH root access with secure PAM configuration..."
    echo "-----------------------------------------------------"
    
    # 1. Configure SSH to allow root login
    echo "Configuring SSH to allow root login..."
    SSH_CONFIG="/etc/ssh/sshd_config"
    backup_file "$SSH_CONFIG"
    
    # Enable root login but require key-based authentication
    set_config "$SSH_CONFIG" "PermitRootLogin" "prohibit-password"
    set_config "$SSH_CONFIG" "PubkeyAuthentication" "yes"
    set_config "$SSH_CONFIG" "PasswordAuthentication" "no"
    set_config "$SSH_CONFIG" "ChallengeResponseAuthentication" "no"
    set_config "$SSH_CONFIG" "UsePAM" "yes"
    
    echo "SSH configuration updated for root access."
    echo
    
    # 2. Configure PAM for root SSH access
    echo "Configuring PAM for secure root SSH access..."
    PROFILE_NAME="custom-ssh-root"
    
    if ! authselect list | grep -q "custom/${PROFILE_NAME}"; then
        echo "Creating custom authselect profile '${PROFILE_NAME}'..."
        BASE_PROFILE=$(authselect current | awk '/^Profile ID:/ {print $3}')
        authselect create-profile "${PROFILE_NAME}" -b "${BASE_PROFILE}" --symlink-meta
    else
        echo "Custom authselect profile '${PROFILE_NAME}' already exists. Proceeding to modify it."
    fi
    
    authselect select "custom/${PROFILE_NAME}" --force
    CUSTOM_SYSTEM_AUTH="/etc/authselect/custom/${PROFILE_NAME}/system-auth"
    CUSTOM_PASSWORD_AUTH="/etc/authselect/custom/${PROFILE_NAME}/password-auth"
    
    # Add root-specific PAM rules for SSH
    echo "Adding root-specific PAM rules..."
    for pam_file in "$CUSTOM_SYSTEM_AUTH" "$CUSTOM_PASSWORD_AUTH"; do
        # Add root access control
        sed -i '/^auth\s*required\s*pam_faillock.so/i auth        [success=1 default=ignore] pam_succeed_if.so user = root' "$pam_file"
        sed -i '/^auth\s*required\s*pam_faillock.so/i auth        [success=1 default=ignore] pam_succeed_if.so user = root' "$pam_file"
    done
    
    echo "Applying PAM profile changes..."
    authselect apply-changes -b
    echo "PAM configured for root SSH access."
    echo
    
    # 3. Update securetty to allow SSH
    echo "Updating /etc/securetty to allow SSH root access..."
    SECURETTY_FILE="/etc/securetty"
    backup_file "$SECURETTY_FILE"
    echo -e "console\ntty1\npts/0\npts/1\npts/2\npts/3\npts/4\npts/5\npts/6\npts/7\npts/8\npts/9" > "$SECURETTY_FILE"
    echo "Securetty updated to allow SSH root access."
    echo
    
    # 4. Restart SSH service
    echo "Restarting SSH service..."
    systemctl restart sshd
    echo "SSH service restarted."
    echo
    
    echo "-----------------------------------------------------"
    echo "SSH root access enabled successfully!"
    echo "IMPORTANT SECURITY NOTES:"
    echo "1. Root login is now allowed via SSH with key-based authentication only"
    echo "2. Password authentication is disabled for security"
    echo "3. Ensure you have SSH keys properly configured"
    echo "4. Monitor root SSH access logs regularly"
    echo "5. Consider using sudo instead of direct root access when possible"
}

# --- Main Execution ---

case "$1" in
    --remediate)
        remediate
        ;;
    --rollback)
        rollback
        ;;
    --enable-ssh-root)
        enable_ssh_root
        ;;
    *)
        echo "Usage: $0 {--remediate|--rollback|--enable-ssh-root}"
        exit 1
        ;;
esac

exit 0
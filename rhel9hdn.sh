#!/bin/bash

# ==============================================================================
# RHEL 9 Hardening Script
#
# This script applies or rolls back security configurations.
#
# Usage:
#   sudo ./harden_rhel9.sh --remediate   (Applies hardening)
#   sudo ./harden_rhel9.sh --rollback    (Reverts changes)
#
# Configurations:
# 1. Sets password quality rules.
# 2. Configures password aging, history, and hashing algorithm.
# 3. Implements an account lockout policy for failed logins.
# 4. Restricts direct root login to the physical console.
# 5. Sets inactive account locking policy.
# 6. Disables passwords for all system accounts with nologin shell.
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
    
    echo "Enabling and configuring pam_faillock..."
    authselect enable-feature with-faillock
    
    FAILLOCK_CONF="/etc/security/faillock.conf"
    backup_file "$FAILLOCK_CONF"
    cat > "$FAILLOCK_CONF" <<EOF
# Lockout after 3 failed attempts
deny = 3
# Unlock after 15 minutes (900 seconds)
unlock_time = 900
# Exempt the root user from lockout
filter = user != root
EOF
    
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
    restore_backup "/etc/security/faillock.conf"
    echo

    # 3. Revert PAM configuration
    echo "Reverting PAM configuration to system default..."
    PROFILE_NAME="custom-hardening"
    authselect select "custom/${PROFILE_NAME}" --force &>/dev/null || true # Select profile to disable feature
    authselect disable-feature with-faillock
    
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

    echo "-----------------------------------------------------"
    echo "Rollback completed successfully!"
    echo "It is recommended to reboot the system for all changes to take full effect."
}

# --- Main Execution ---

case "$1" in
    --remediate)
        remediate
        ;;
    --rollback)
        rollback
        ;;
    *)
        echo "Usage: $0 {--remediate|--rollback}"
        exit 1
        ;;
esac

exit 0
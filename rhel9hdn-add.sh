#!/bin/bash

# ==============================================================================
# RHEL 9 Additional Hardening Script
#
# This script applies or rolls back security configurations.
#
# Usage:
#   sudo ./harden_rhel9_additional.sh --remediate   (Applies hardening)
#   sudo ./harden_rhel9_additional.sh --rollback    (Reverts changes)
#
# Configurations:
# 1. Sets security logon banners.
# 2. Hardens kernel network parameters via sysctl.
# 3. Configures a global session timeout.
# 4. Enables auditing for failed file access attempts.
# 5. Configures auditd log file size.
# 6. Configures user rights policies (disables insecure remote access).
# 7. Configures event log settings (logrotate, rsyslog).
# 8. Configures file permission settings (umask).
# 9. Configures time synchronization settings (chrony).
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
        # If no backup, just clear the file to revert the change
        echo "" > "$file_path"
        echo "Warning: No backup found for $file_path. File has been cleared."
    fi
}

# --- Core Functions ---

remediate() {
    echo "Starting RHEL 9 additional hardening process..."
    echo "-----------------------------------------------------"

    # 1. Configure Logon Warning Banners
    echo "Configuring logon warning banners..."
    
    # Backup and apply to /etc/motd and /etc/issue
    backup_file "/etc/motd"
    backup_file "/etc/issue"
    
    # Use a here-document to write the banner directly to the file.
    # The 'EOF' is quoted to prevent any shell expansion inside the banner.
    cat > /etc/motd <<'EOF'
***********************************************************
WARNING:

This system is restricted to KTB Computer Services (KTBCS) authorized users for business purposes only.  Unauthorized access or use is a violation of laws and KTBCS security policy. This service may be monitored for administrative and security reasons.  By proceeding, you consent to this monitoring.
***********************************************************
EOF

    # Copy the same banner to /etc/issue
    cp /etc/motd /etc/issue
    
    echo "Logon banners configured for /etc/motd and /etc/issue."
    echo

    # 2. Configure Network Security Settings
    echo "Hardening kernel network parameters..."
    SYSCTL_CONF="/etc/sysctl.d/99-network-security.conf"
    backup_file "$SYSCTL_CONF"
    cat > "$SYSCTL_CONF" <<EOF
# Enable TCP SYN Cookie to prevent SYN flood
net.ipv4.tcp_syncookies = 1
# Disable IP Source Routing
net.ipv4.conf.all.accept_source_route = 0
# Disable ICMP Redirect Acceptance
net.ipv4.conf.all.accept_redirects = 0
# Disable Secure ICMP Redirect Acceptance
net.ipv4.conf.all.secure_redirects = 0
# Enable IP Spoofing Protection
net.ipv4.conf.all.rp_filter = 1
# Enable Ignoring Broadcasts Request
net.ipv4.icmp_echo_ignore_broadcasts = 1
# Enable Bad Error Message Protection
net.ipv4.icmp_ignore_bogus_error_responses = 1
# Enable Logging of Spoofed Packets, Source Routed Packets, Redirect Packet
net.ipv4.conf.all.log_martians = 1
# Disable forward package
net.ipv4.ip_forward = 0
EOF
    # Apply all sysctl configuration files
    sysctl --system
    echo "Kernel network parameters applied."
    echo

    # 3. Configure Session Timeout
    echo "Configuring session timeout..."
    TIMEOUT_FILE="/etc/profile.d/session-timeout.sh"
    backup_file "$TIMEOUT_FILE"
    cat > "$TIMEOUT_FILE" <<EOF
# System-wide session timeout
TMOUT=600
readonly TMOUT
export TMOUT
EOF
    chmod +x "$TIMEOUT_FILE"
    echo "Session timeout set to 600 seconds."
    echo

    # 4. Configure Audit Rules for Failed Access
    echo "Configuring audit rules for failed file access..."
    AUDIT_RULES_FILE="/etc/audit/rules.d/99-failed-access.rules"
    backup_file "$AUDIT_RULES_FILE"
    cat > "$AUDIT_RULES_FILE" <<EOF
# Audit failed attempts to access files and programs
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=500 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=500 -F auid!=4294967295 -k access
EOF
    echo "Failed access audit rules configured."
    echo

    # 5. Configure Auditd Log Size
    echo "Configuring auditd log size..."
    AUDITD_CONF="/etc/audit/auditd.conf"
    backup_file "$AUDITD_CONF"
    # Ensure the max_log_file is set to 32
    if grep -q -E "^\s*#*\s*max_log_file\s*=" "$AUDITD_CONF"; then
        sed -i -E 's/^\s*#*\s*(max_log_file\s*=\s*).*/\132/' "$AUDITD_CONF"
    else
        echo "max_log_file = 32" >> "$AUDITD_CONF"
    fi
    # Reload audit rules to apply all changes
    augenrules --load
    echo "Auditd max_log_file set to 32MB and rules reloaded."
    echo

    # 6. Configure User Rights Policies
    echo "Configuring User Rights Policies..."
    # Remove .netrc and .rhosts files
    echo "Removing insecure auto-login files (.netrc, .rhosts)..."
    find /home -name .netrc -type f -exec echo "Removing {}" \; -exec rm -f {} \;
    find /home -name .rhosts -type f -exec echo "Removing {}" \; -exec rm -f {} \;

    # Disable insecure remote login services
    echo "Disabling network root login services..."
    if dnf list installed telnet-server &>/dev/null; then
        dnf remove -y telnet-server
        echo "Removed telnet-server package."
    fi
    if dnf list installed rsh-server &>/dev/null; then
        dnf remove -y rsh-server
        echo "Removed rsh-server package."
    fi

    # Secure SSH to not permit root login
    SSHD_CONFIG="/etc/ssh/sshd_config"
    backup_file "$SSHD_CONFIG"
    if grep -q -E "^\s*#*\s*PermitRootLogin" "$SSHD_CONFIG"; then
        sed -i -E 's/^\s*#*\s*(PermitRootLogin\s+).*/\1no/' "$SSHD_CONFIG"
    else
        echo "PermitRootLogin no" >> "$SSHD_CONFIG"
    fi
    systemctl restart sshd
    echo "SSH root login disabled and service restarted."
    echo

    # 7. Configure Event Log Settings
    echo "Configuring Event Log Settings..."
    LOGROTATE_CONF="/etc/logrotate.conf"
    RSYSLOG_CONF="/etc/rsyslog.conf"
    backup_file "$LOGROTATE_CONF"
    backup_file "$RSYSLOG_CONF"

    # Configure logrotate
    sed -i -E 's/^\s*#*\s*(weekly|monthly|yearly)/daily/' "$LOGROTATE_CONF"
    sed -i -E 's/^\s*#*\s*rotate\s+[0-9]+/rotate 90/' "$LOGROTATE_CONF"
    sed -i -E 's/^\s*#\s*create/create/' "$LOGROTATE_CONF"
    sed -i -E 's/^\s*#*\s*dateext/dateext/' "$LOGROTATE_CONF"
    echo "Configured logrotate for daily rotation, keeping 90 days."

    # Configure rsyslog for secure and messages logs
    if ! grep -q -E "^\s*authpriv\.\*\s+/var/log/secure" "$RSYSLOG_CONF"; then
        echo "authpriv.* /var/log/secure" >> "$RSYSLOG_CONF"
        echo "Enabled logging for successful/unsuccessful logins."
    fi
    if ! grep -q -E "^\s*\*\.info;mail\.none;authpriv\.none;cron\.none\s+/var/log/messages" "$RSYSLOG_CONF"; then
        echo "*.info;mail.none;authpriv.none;cron.none                /var/log/messages" >> "$RSYSLOG_CONF"
        echo "Enabled system access logging."
    fi
    systemctl restart rsyslog
    echo "Event log settings applied and rsyslog restarted."
    echo

    # 8. Configure File Permission Settings
    echo "Configuring File Permission Settings..."
    PROFILE_CONF="/etc/profile"
    backup_file "$PROFILE_CONF"
    if grep -q -E "^\s*umask" "$PROFILE_CONF"; then
        sed -i -E 's/^\s*umask\s+[0-9]+/umask 027/' "$PROFILE_CONF"
    else
        echo "umask 027" >> "$PROFILE_CONF"
    fi
    echo "Default umask set to 027 in /etc/profile."
    echo

    # 9. Configure Time Synchronization
    echo "Configuring Time Synchronization..."
    CHRONY_CONF="/etc/chrony.conf"
    backup_file "$CHRONY_CONF"
    # Comment out existing pool and server lines
    sed -i -E 's/^\s*(pool|server)/#\1/' "$CHRONY_CONF"
    # Add authorized time servers
    echo "server NTP_PBS_ST1.kcs" >> "$CHRONY_CONF"
    echo "server NTP_BBT_ST1.kcs" >> "$CHRONY_CONF"
    # Ensure chronyd is enabled and restart it
    systemctl enable --now chronyd
    systemctl restart chronyd
    echo "NTP configured with authorized time servers and service restarted."
    echo


    echo "-----------------------------------------------------"
    echo "Additional hardening script completed successfully!"
}

rollback() {
    echo "Starting rollback of additional hardening configurations..."
    echo "-----------------------------------------------------"

    # 1. Rollback Logon Warning Banners
    echo "Reverting logon warning banners..."
    restore_backup "/etc/motd"
    restore_backup "/etc/issue"
    echo "Logon banners reverted."
    echo

    # 2. Rollback Network Security Settings
    echo "Reverting kernel network parameters..."
    SYSCTL_CONF="/etc/sysctl.d/99-network-security.conf"
    if [ -f "$SYSCTL_CONF" ]; then
        rm -f "$SYSCTL_CONF"
        # Reload sysctl settings from remaining files
        sysctl --system
        echo "Removed custom network security sysctl configuration."
    else
        echo "No custom network security sysctl configuration found to remove."
    fi
    echo

    # 3. Rollback Session Timeout
    echo "Reverting session timeout..."
    TIMEOUT_FILE="/etc/profile.d/session-timeout.sh"
    if [ -f "$TIMEOUT_FILE" ]; then
        rm -f "$TIMEOUT_FILE"
        echo "Removed session timeout configuration."
    else
        echo "No session timeout configuration found to remove."
    fi
    echo

    # 4. Rollback Audit Rules
    echo "Reverting audit rules for failed file access..."
    AUDIT_RULES_FILE="/etc/audit/rules.d/99-failed-access.rules"
    if [ -f "$AUDIT_RULES_FILE" ]; then
        rm -f "$AUDIT_RULES_FILE"
        echo "Removed failed access audit rules."
    else
        echo "No failed access audit rules file found to remove."
    fi
    echo

    # 5. Rollback Auditd Log Size
    echo "Reverting auditd log size..."
    restore_backup "/etc/audit/auditd.conf"
    # Reload audit rules to apply all audit changes from rollback
    augenrules --load
    echo "Auditd log size configuration reverted and rules reloaded."
    echo

    # 6. Rollback User Rights Policies
    echo "Reverting User Rights Policies..."
    echo "Note: Removal of .netrc, .rhosts, telnet-server, and rsh-server is not reversible by this script."
    restore_backup "/etc/ssh/sshd_config"
    systemctl restart sshd
    echo "SSH configuration reverted and service restarted."
    echo

    # 7. Rollback Event Log Settings
    echo "Reverting Event Log Settings..."
    restore_backup "/etc/logrotate.conf"
    restore_backup "/etc/rsyslog.conf"
    systemctl restart rsyslog
    echo "Event log settings reverted and rsyslog restarted."
    echo

    # 8. Rollback File Permission Settings
    echo "Reverting File Permission Settings..."
    restore_backup "/etc/profile"
    echo "Restored /etc/profile."
    echo

    # 9. Rollback Time Synchronization
    echo "Reverting Time Synchronization..."
    restore_backup "/etc/chrony.conf"
    systemctl restart chronyd
    echo "chrony.conf restored and service restarted."
    echo

    echo "-----------------------------------------------------"
    echo "Rollback completed successfully!"
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
#!/bin/bash

# ==============================================================================
# RHEL 9 Services Hardening Script
#
# This script applies or rolls back security configurations for system services.
#
# Usage:
#   sudo ./harden_rhel9_services.sh --remediate   (Applies hardening)
#   sudo ./harden_rhel9_services.sh --rollback    (Reverts changes)
#
# Configurations:
# 1. Disables autofs daemon.
# 2. Hardens SNMP service.
# 3. Disables unsecure remote login services (telnet, rsh, etc.).
# 4. Disables vsftp, postfix, sendmail, cups, and smb daemons.
#
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

# --- Core Functions ---

remediate() {
    echo "Starting RHEL 9 services hardening process..."
    echo "-----------------------------------------------------"

    # 1. Disable Autofs Daemon
    echo "Disabling autofs daemon..."
    systemctl disable --now autofs &>/dev/null || echo "autofs service not found or already disabled."
    echo "Autofs daemon disabled."
    echo

    # 2. Harden SNMP Service
    echo "Hardening SNMP service..."
    SNMPD_CONF="/etc/snmp/snmpd.conf"
    if [ -f "$SNMPD_CONF" ]; then
        backup_file "$SNMPD_CONF"
        # Remove default public/private communities
        sed -i '/^com2sec notConfigUser\s\+default\s\+public/d' "$SNMPD_CONF"
        sed -i '/^com2sec mynetwork\s\+localhost\s\+private/d' "$SNMPD_CONF"
        # Add a secure SNMPv3 user (read-only)
        echo "createUser v3user SHA YourSecureAuthPassword AES YourSecurePrivPassword" >> "$SNMPD_CONF"
        echo "rouser   v3user" >> "$SNMPD_CONF"
        systemctl enable --now snmpd
        systemctl restart snmpd
        echo "SNMPd hardened with v3 user and default communities removed."
    else
        echo "SNMPd configuration not found. Skipping."
    fi
    echo

    # 3. Disable Unsecure Remote Services
    echo "Disabling unsecure remote services..."
    # Remove packages for legacy services
    for pkg in telnet-server rsh-server tftp-server finger-server rwhod; do
        if dnf list installed $pkg &>/dev/null; then
            dnf remove -y $pkg
            echo "Removed package: $pkg"
        fi
    done
    # Disable services in xinetd if it exists
    if [ -d "/etc/xinetd.d" ]; then
        for service in telnet rlogin rexec rsh tftp eklogin klogin gssftp kshell shell loginp krb5-telnet finger chargen daytime time echo discard talk chargen-dgram chargen-stream daytime-dgram daytime-stream discard-dgram discard-stream echo-dgram echo-stream time-dgram time-stream tcpmux-server; do
            if [ -f "/etc/xinetd.d/$service" ]; then
                sed -i 's/disable\s*=\s*no/disable = yes/' "/etc/xinetd.d/$service"
                echo "Disabled $service in xinetd."
            fi
        done
        systemctl restart xinetd &>/dev/null || true
    fi
    # Disable systemd services
    for service in rsyncd rpc-sprayd; do
        systemctl disable --now $service &>/dev/null || echo "$service service not found or already disabled."
    done
    echo "Unsecure remote services disabled."
    echo

    # 4. Disable vsftpd
    echo "Disabling vsftpd daemon..."
    systemctl disable --now vsftpd &>/dev/null || echo "vsftpd service not found or already disabled."
    echo "vsftpd daemon disabled."
    echo

    # 5. Disable Mail Daemons
    echo "Disabling postfix and sendmail daemons..."
    systemctl disable --now postfix &>/dev/null || echo "postfix service not found or already disabled."
    systemctl disable --now sendmail &>/dev/null || echo "sendmail service not found or already disabled."
    echo "Mail daemons disabled."
    echo

    # 6. Disable Print Server Daemon
    echo "Disabling cups daemon..."
    systemctl disable --now cups &>/dev/null || echo "cups service not found or already disabled."
    echo "Cups daemon disabled."
    echo

    # 7. Disable Samba Daemon
    echo "Disabling smb daemon..."
    systemctl disable --now smb &>/dev/null || echo "smb service not found or already disabled."
    echo "Samba daemon disabled."
    echo

    echo "-----------------------------------------------------"
    echo "Services hardening script completed successfully!"
}

rollback() {
    echo "Starting rollback of services hardening configurations..."
    echo "-----------------------------------------------------"

    # 1. Enable Autofs Daemon
    echo "Enabling autofs daemon..."
    systemctl enable --now autofs &>/dev/null || true
    echo "Autofs daemon enabled."
    echo

    # 2. Revert SNMP Service
    echo "Reverting SNMP service..."
    restore_backup "/etc/snmp/snmpd.conf"
    systemctl restart snmpd &>/dev/null || true
    echo "SNMP service reverted."
    echo

    # 3. Revert Unsecure Remote Services
    echo "Reverting unsecure remote services..."
    echo "Note: Package removal is not reversible by this script."
    if [ -d "/etc/xinetd.d" ]; then
        systemctl restart xinetd &>/dev/null || true
    fi
    for service in rsyncd rpc-sprayd; do
        systemctl enable --now $service &>/dev/null || true
    done
    echo "Unsecure remote services rollback attempted."
    echo

    # 4. Enable vsftpd
    echo "Enabling vsftpd daemon..."
    systemctl enable --now vsftpd &>/dev/null || true
    echo "vsftpd daemon enabled."
    echo

    # 5. Enable Mail Daemons
    echo "Enabling postfix and sendmail daemons..."
    systemctl enable --now postfix &>/dev/null || true
    systemctl enable --now sendmail &>/dev/null || true
    echo "Mail daemons enabled."
    echo

    # 6. Enable Print Server Daemon
    echo "Enabling cups daemon..."
    systemctl enable --now cups &>/dev/null || true
    echo "Cups daemon enabled."
    echo

    # 7. Enable Samba Daemon
    echo "Enabling smb daemon..."
    systemctl enable --now smb &>/dev/null || true
    echo "Samba daemon enabled."
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
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
#   (To be added)
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

    # --- Add new service hardening sections below ---

    # Example Section:
    # echo "Configuring Service XYZ..."
    # backup_file "/etc/xyz/xyz.conf"
    # ... your commands here ...
    # echo "Service XYZ configured."
    # echo

    echo "-----------------------------------------------------"
    echo "Services hardening script completed successfully!"
    echo "A reboot may be required for some changes to take full effect."
}

rollback() {
    echo "Starting rollback of services hardening configurations..."
    echo "-----------------------------------------------------"

    # --- Add rollback steps for service hardening sections below ---

    # Example Section:
    # echo "Reverting Service XYZ..."
    # restore_backup "/etc/xyz/xyz.conf"
    # ... your commands here ...
    # echo "Service XYZ reverted."
    # echo


    echo "-----------------------------------------------------"
    echo "Rollback completed successfully!"
    echo "A reboot may be required for some changes to take full effect."
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

#!/bin/bash

# Define the drop-in directory structure
services=("systemd-suspend" "systemd-hibernate" "systemd-hybrid-sleep" "systemd-suspend-then-hibernate")
dropin_dir="/etc/systemd/system"

# Create drop-in directories and configuration files
for service in "${services[@]}"; do
    dir="$dropin_dir/${service}.service.d"
    config_file="$dir/override.conf"

    # Create the drop-in directory if it doesn't exist
    sudo mkdir -p "$dir"

    # Create or overwrite the configuration file with the required content
    echo "[Service]" | sudo tee "$config_file" > /dev/null
    echo "Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false" | sudo tee -a "$config_file" > /dev/null

    echo "Created $config_file"
done

# Reload systemd to apply changes
sudo systemctl daemon-reload

echo "systemd has been reloaded. Changes applied."

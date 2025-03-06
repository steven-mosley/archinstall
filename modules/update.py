#!/usr/bin/env python3
# Update checking and version management

import os
import sys
import subprocess
import urllib.request
import json
import tempfile
import shutil
from pathlib import Path
from modules.utils import log, error, prompt, TEST_MODE

# GitHub repository information
GITHUB_REPO = "steven-mosley/archinstall"  # Change to your GitHub username/repo
GITHUB_API_URL = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
GITHUB_RELEASES_URL = f"https://github.com/{GITHUB_REPO}/releases/latest"
GITHUB_RAW_URL = f"https://raw.githubusercontent.com/{GITHUB_REPO}"

def get_current_version():
    """Get the current version from VERSION file"""
    script_dir = Path(__file__).parent.parent.resolve()
    version_file = os.path.join(script_dir, "VERSION")
    
    try:
        with open(version_file, 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        return "0.0.0"  # Default version if file doesn't exist

def get_latest_version():
    """Get the latest version from GitHub releases"""
    try:
        # Try to get version via GitHub API
        req = urllib.request.Request(
            GITHUB_API_URL,
            headers={"Accept": "application/vnd.github.v3+json",
                     "User-Agent": "ArchInstall-UpdateChecker"}
        )
        
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode('utf-8'))
            return data["tag_name"].strip("v")
    except Exception as e:
        # If API fails, try to get version from VERSION file in main branch
        try:
            version_url = f"{GITHUB_RAW_URL}/main/VERSION"
            req = urllib.request.Request(
                version_url,
                headers={"User-Agent": "ArchInstall-UpdateChecker"}
            )
            
            with urllib.request.urlopen(req, timeout=5) as response:
                return response.read().decode('utf-8').strip()
        except Exception as inner_e:
            log(f"Failed to check for updates: {str(e)} / {str(inner_e)}")
            return None

def version_compare(v1, v2):
    """Compare two version strings
    Returns: -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
    """
    def normalize(v):
        return [int(x) for x in v.split('.')]
    
    n1 = normalize(v1)
    n2 = normalize(v2)
    
    for i in range(max(len(n1), len(n2))):
        v1_part = n1[i] if i < len(n1) else 0
        v2_part = n2[i] if i < len(n2) else 0
        
        if v1_part < v2_part:
            return -1
        elif v1_part > v2_part:
            return 1
    
    return 0

def check_for_updates(print_message=True):
    """Check if an update is available
    Returns: (update_available, current_version, latest_version)
    """
    current_version = get_current_version()
    latest_version = get_latest_version()
    
    if not latest_version:
        if print_message:
            log("Could not check for updates - network issue or repository not found")
        return False, current_version, None
    
    update_available = version_compare(current_version, latest_version) < 0
    
    if print_message:
        if update_available:
            log(f"Update available: {current_version} → {latest_version}")
        else:
            log(f"Your version ({current_version}) is up to date")
    
    return update_available, current_version, latest_version

def download_update():
    """Download the latest version of the script
    Returns: Path to downloaded archive or None if failed
    """
    try:
        log("Downloading latest version...")
        
        # Create temporary directory
        temp_dir = tempfile.mkdtemp()
        archive_path = os.path.join(temp_dir, "archinstall.zip")
        
        # Download the latest zip from GitHub
        download_url = f"https://github.com/{GITHUB_REPO}/archive/main.zip"
        urllib.request.urlretrieve(download_url, archive_path)
        
        return archive_path
    except Exception as e:
        error(f"Failed to download update: {str(e)}", log_only=True)
        # Clean up temp directory if something went wrong
        if 'temp_dir' in locals():
            shutil.rmtree(temp_dir, ignore_errors=True)
        return None

def install_update(archive_path):
    """Install the downloaded update
    Returns: True if successful, False otherwise
    """
    script_dir = Path(__file__).parent.parent.resolve()
    temp_extract_dir = tempfile.mkdtemp()
    
    try:
        log("Installing update...")
        
        # Extract the archive
        import zipfile
        with zipfile.ZipFile(archive_path, 'r') as zip_ref:
            zip_ref.extractall(temp_extract_dir)
        
        # Find the extracted directory (usually reponame-main)
        for item in os.listdir(temp_extract_dir):
            extracted_dir = os.path.join(temp_extract_dir, item)
            if os.path.isdir(extracted_dir):
                break
        
        # Backup current config files
        config_dir = os.path.join(script_dir, "config")
        backup_dir = os.path.join(temp_extract_dir, "config_backup")
        
        if os.path.exists(config_dir):
            os.makedirs(backup_dir, exist_ok=True)
            for config_file in os.listdir(config_dir):
                src = os.path.join(config_dir, config_file)
                dst = os.path.join(backup_dir, config_file)
                if os.path.isfile(src):
                    shutil.copy2(src, dst)
        
        # Copy new files over existing ones
        for root, dirs, files in os.walk(extracted_dir):
            # Compute the relative path from the extracted directory
            rel_path = os.path.relpath(root, extracted_dir)
            if rel_path == ".":
                rel_path = ""
                
            # Skip the .git directory if it exists
            if ".git" in dirs:
                dirs.remove(".git")
                
            # Create directories if they don't exist
            for dir_name in dirs:
                target_dir = os.path.join(script_dir, rel_path, dir_name)
                os.makedirs(target_dir, exist_ok=True)
                
            # Copy files
            for file_name in files:
                source_file = os.path.join(root, file_name)
                target_file = os.path.join(script_dir, rel_path, file_name)
                
                # Skip user config files
                if rel_path == "config" and os.path.exists(target_file):
                    continue
                    
                shutil.copy2(source_file, target_file)
                
                # Make scripts executable
                if file_name.endswith(".py"):
                    os.chmod(target_file, 0o755)
        
        # Restore backed up config files
        if os.path.exists(backup_dir):
            for config_file in os.listdir(backup_dir):
                src = os.path.join(backup_dir, config_file)
                dst = os.path.join(script_dir, "config", config_file)
                if os.path.isfile(src):
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    shutil.copy2(src, dst)
        
        log("Update installed successfully!")
        return True
    except Exception as e:
        error(f"Failed to install update: {str(e)}", log_only=True)
        return False
    finally:
        # Clean up temp directories
        shutil.rmtree(temp_extract_dir, ignore_errors=True)
        if os.path.exists(archive_path):
            os.remove(archive_path)
        shutil.rmtree(os.path.dirname(archive_path), ignore_errors=True)

def update_script():
    """Check for updates and install if available
    Returns: True if updated or already up to date, False if failed
    """
    update_available, current_version, latest_version = check_for_updates()
    
    if not update_available:
        return True
    
    if TEST_MODE:
        log(f"Would update from {current_version} to {latest_version} (skipped in test mode)")
        return True
    
    if not prompt(f"Update available: {current_version} → {latest_version}. Update now?"):
        log("Update skipped")
        return True
    
    log(f"Updating from {current_version} to {latest_version}...")
    
    # Download the update
    archive_path = download_update()
    if not archive_path:
        return False
    
    # Install the update
    if install_update(archive_path):
        # Save new version to VERSION file
        script_dir = Path(__file__).parent.parent.resolve()
        with open(os.path.join(script_dir, "VERSION"), 'w') as f:
            f.write(latest_version)
        
        log("Update completed successfully!")
        
        if prompt("Restart the script with the new version?"):
            # Restart the script
            python = sys.executable
            os.execl(python, python, *sys.argv)
            
        return True
    else:
        log("Failed to install update")
        return False

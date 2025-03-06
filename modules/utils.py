#!/usr/bin/env python3
# Utility functions module

import os
import sys
import subprocess
import time
import re
from datetime import datetime

# Terminal colors
YELLOW = "\033[1;33m"
GREEN = "\033[1;32m"
RED = "\033[1;31m"
BLUE = "\033[1;34m"
NC = "\033[0m"  # No Color

# Global variables
DEBUG = False
TEST_MODE = False
LOG_FILE = None
LAST_ERROR = ""

def setup_logging(log_file=None):
    """Set up logging configuration"""
    global LOG_FILE
    LOG_FILE = log_file

def log(message):
    """Log a message to stdout and log file if configured"""
    if TEST_MODE:
        print(f"[LOG] {message}")
    else:
        print(f"{YELLOW}[LOG]{NC} {message}")
    
    # Write to log file if available
    if LOG_FILE and os.path.isdir(os.path.dirname(LOG_FILE)):
        with open(LOG_FILE, 'a') as f:
            f.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}\n")

def error(message, exit_code=1, log_only=False):
    """Handle errors with consistent formatting"""
    global LAST_ERROR
    LAST_ERROR = message
    
    print(f"{RED}[ERROR]{NC} {message}", file=sys.stderr)
    
    # Write to log file if available
    if LOG_FILE and os.path.isdir(os.path.dirname(LOG_FILE)):
        with open(LOG_FILE, 'a') as f:
            f.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ERROR: {message}\n")
    
    # Exit if not in test mode and not log-only
    if not TEST_MODE and not log_only:
        sys.exit(exit_code)
    elif TEST_MODE and not log_only:
        print(f"Would exit with code {exit_code} in non-test mode")
        return exit_code
    
    return 0

def show_progress(title, command, timeout=300, exit_on_error=False):
    """Show progress for long running commands"""
    print(f"{BLUE}[PROGRESS]{NC} Starting: {title}...")
    
    process = None
    try:
        process = subprocess.Popen(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        
        spinner = ['|', '/', '-', '\\']
        start_time = time.time()
        i = 0
        
        # Collect output
        output = []
        
        while process.poll() is None:
            if time.time() - start_time > timeout:
                process.kill()
                print(f"{RED}[TIMEOUT]{NC} Operation timed out after {timeout} seconds")
                if exit_on_error and not TEST_MODE:
                    error(f"Command timed out: {command}", exit_code=1)
                return 1
                
            print(f" [{spinner[i % 4]}]  ", end='\r')
            time.sleep(0.5)
            i += 1
            
            # Read any available output
            while True:
                line = process.stdout.readline()
                if not line:
                    break
                output.append(line.strip())
        
        status = process.wait()
        
        if status == 0:
            print(f"{GREEN}[DONE]{NC} {title} completed successfully")
        else:
            print(f"{RED}[FAILED]{NC} {title} failed with exit code {status}")
            # Show the output
            for line in output:
                print(line)
                
            # Exit on error if requested
            if exit_on_error and not TEST_MODE:
                error(f"Command failed: {command}", exit_code=status)
                
        return status
    
    except Exception as e:
        if process and process.poll() is None:
            process.kill()
        print(f"{RED}[ERROR]{NC} {title} failed: {str(e)}")
        
        # Exit on error if requested
        if exit_on_error and not TEST_MODE:
            error(f"Command failed with exception: {command}\n{str(e)}", exit_code=1)
            
        return 1

def validate_input(input_val, input_type, msg_prefix="Input validation"):
    """Validate user input of various types"""
    if input_type == "number":
        if not re.match(r'^[0-9]+$', str(input_val)):
            error(f"{msg_prefix}: '{input_val}' is not a valid number", 1, True)
            return False
    elif input_type == "text":
        if not input_val or input_val.strip() == "":
            error(f"{msg_prefix}: Input cannot be empty", 1, True)
            return False
    elif input_type == "path":
        if not os.path.exists(input_val):
            error(f"{msg_prefix}: Path '{input_val}' does not exist", 1, True)
            return False
    elif input_type == "device":
        if not os.path.exists(input_val) or not os.path.isfile(f"/sys/block/{os.path.basename(input_val)}") and not os.path.basename(input_val).startswith("loop"):
            error(f"{msg_prefix}: '{input_val}' is not a valid block device", 1, True)
            return False
    else:
        error(f"Unknown validation type: {input_type}", 1, True)
        return False
    
    return True

def prompt(message):
    """Get user confirmation with validation"""
    while True:
        response = input(f"{message} [y/n]: ").lower()
        if response in ['y', 'yes']:
            return True
        elif response in ['n', 'no']:
            return False
        else:
            print("Please answer yes or no.")

def run_command(command, exit_on_error=True, show_output=False):
    """Run a shell command and return result"""
    try:
        if show_output:
            result = subprocess.run(command, shell=True, check=exit_on_error, text=True)
            return result.returncode == 0
        else:
            result = subprocess.run(
                command,
                shell=True,
                check=exit_on_error,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            return result.stdout.strip() if result.returncode == 0 else None
    except subprocess.CalledProcessError as e:
        if exit_on_error:
            error(f"Command failed: {command}\n{e.stderr}")
        return None
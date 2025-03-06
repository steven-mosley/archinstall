#!/usr/bin/env python3
# Configuration file reader

import os
import re
import shlex

def parse_config_value(value):
    """Parse a configuration value into the appropriate Python type"""
    # Check for boolean
    if value.lower() in ('true', 'yes'):
        return True
    if value.lower() in ('false', 'no'):
        return False
    
    # Check for number
    try:
        if '.' in value:
            return float(value)
        return int(value)
    except ValueError:
        pass
    
    # Check for array/list
    if value.startswith('(') and value.endswith(')'):
        # Parse array values, handling quotes properly
        items = shlex.split(value[1:-1])
        return [item for item in items if item.strip()]
    
    # Return as string by default
    return value.strip('"\'')

def read_config(config_path):
    """Read a configuration file and return a dict of values"""
    config = {}
    
    if not os.path.exists(config_path):
        return config
    
    with open(config_path, 'r') as f:
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if not line or line.startswith('#'):
                continue
                
            # Find variable assignments
            parts = line.split('=', 1)
            if len(parts) == 2:
                key = parts[0].strip()
                value = parts[1].strip()
                
                # Handle comments at the end of the line
                if '#' in value:
                    value = value.split('#', 1)[0].strip()
                    
                config[key] = parse_config_value(value)
    
    return config

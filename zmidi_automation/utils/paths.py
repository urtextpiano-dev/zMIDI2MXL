"""Path conversion utilities for WSL/Windows compatibility"""

import os
from pathlib import Path


def to_windows_path(path: str) -> str:
    """Convert WSL path to Windows path for cmd.exe commands"""
    path_str = str(path)
    
    # Already a Windows path
    if ':\\' in path_str or path_str.startswith('\\\\'):
        return path_str
    
    # Convert /mnt/x/ to X:\
    if path_str.startswith('/mnt/'):
        parts = path_str.split('/')
        if len(parts) > 2:
            drive = parts[2].upper()
            rest = '\\'.join(parts[3:])
            return f"{drive}:\\{rest}" if rest else f"{drive}:\\"
    
    # Fallback - assume relative path
    return path_str.replace('/', '\\')


def to_wsl_path(path: str) -> str:
    """Convert Windows path to WSL path for internal operations"""
    path_str = str(path)
    
    # Already a WSL path
    if path_str.startswith('/'):
        return path_str
    
    # Convert X:\ to /mnt/x/
    if len(path_str) > 1 and path_str[1] == ':':
        drive = path_str[0].lower()
        rest = path_str[2:].replace('\\', '/')
        rest = rest.lstrip('/')
        return f"/mnt/{drive}/{rest}" if rest else f"/mnt/{drive}"
    
    # Fallback - assume relative path
    return path_str.replace('\\', '/')


def normalize_path(path: str) -> Path:
    """Normalize any path to WSL Path object for internal use"""
    return Path(to_wsl_path(path))
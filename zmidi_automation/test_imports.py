#!/usr/bin/env python3
"""
Test script to verify all imports work correctly
Run this to check for import errors before running the main application
"""

import sys
import traceback
from pathlib import Path

# Add parent to path
sys.path.insert(0, str(Path(__file__).parent.parent))

def test_imports():
    """Test all module imports"""
    
    modules_to_test = [
        # Config
        ("zmidi_automation.config", "Configuration"),
        ("zmidi_automation.config.settings", "Settings"),
        
        # Core
        ("zmidi_automation.core", "Core"),
        ("zmidi_automation.core.orchestrator", "Orchestrator"),
        ("zmidi_automation.core.pipeline", "Pipeline"),
        ("zmidi_automation.core.pipeline_enhanced", "Enhanced Pipeline"),
        ("zmidi_automation.core.state_manager", "State Manager"),
        
        # Sync
        ("zmidi_automation.sync", "Sync"),
        ("zmidi_automation.sync.sync_manager", "Sync Manager"),
        
        # Claude
        ("zmidi_automation.claude", "Claude"),
        ("zmidi_automation.claude.client", "Claude Client"),
        
        # UI Automation
        ("zmidi_automation.ui_automation", "UI Automation"),
        ("zmidi_automation.ui_automation.window_manager", "Window Manager"),
        ("zmidi_automation.ui_automation.prompt_detector", "Prompt Detector"),
        
        # Monitoring
        ("zmidi_automation.monitoring", "Monitoring"),
        ("zmidi_automation.monitoring.progress_tracker", "Progress Tracker"),
        
        # Utils
        ("zmidi_automation.utils", "Utils"),
        ("zmidi_automation.utils.retry", "Retry"),
        
        # Main
        ("zmidi_automation.main", "Main Entry Point"),
    ]
    
    print("=" * 60)
    print("TESTING MODULE IMPORTS")
    print("=" * 60)
    
    failed = []
    optional_missing = []
    
    for module_name, description in modules_to_test:
        try:
            __import__(module_name)
            print(f"✅ {description:<30} ({module_name})")
        except ImportError as e:
            # Check if it's an optional dependency
            if "pyautogui" in str(e) or "pyperclip" in str(e) or "pytesseract" in str(e) or "PIL" in str(e) or "watchdog" in str(e) or "win32" in str(e):
                optional_missing.append((module_name, description, str(e)))
                print(f"⚠️  {description:<30} (optional dependency missing)")
            else:
                failed.append((module_name, description, str(e)))
                print(f"❌ {description:<30} FAILED")
                print(f"   Error: {e}")
        except Exception as e:
            failed.append((module_name, description, str(e)))
            print(f"❌ {description:<30} FAILED")
            print(f"   Error: {e}")
    
    print("\n" + "=" * 60)
    
    if failed:
        print("❌ IMPORT ERRORS FOUND:")
        print("=" * 60)
        for module, desc, error in failed:
            print(f"\n{desc} ({module}):")
            print(f"  {error}")
        print("\n" + "=" * 60)
        return False
    
    if optional_missing:
        print("⚠️  OPTIONAL DEPENDENCIES MISSING:")
        print("=" * 60)
        print("\nThe following optional features won't be available:")
        for module, desc, error in optional_missing:
            print(f"  - {desc}")
        
        print("\nTo enable all features, install:")
        print("  pip install pyautogui pyperclip pytesseract pillow watchdog pywin32")
        print("\n" + "=" * 60)
    
    print("✅ All required imports successful!")
    print("=" * 60)
    return True


if __name__ == "__main__":
    success = test_imports()
    sys.exit(0 if success else 1)
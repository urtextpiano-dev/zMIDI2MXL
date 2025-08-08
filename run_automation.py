#!/usr/bin/env python3
"""
Simple launcher for ZMIDI Automation that handles import issues gracefully
Run this instead of zmidi_automation/main.py for better error handling
"""

import sys
import os
from pathlib import Path

# Add zmidi_automation to path
sys.path.insert(0, str(Path(__file__).parent))

def check_dependencies():
    """Check for optional dependencies and provide guidance"""
    missing = []
    
    try:
        import pyautogui
    except ImportError:
        missing.append("pyautogui")
    
    try:
        import pyperclip
    except ImportError:
        missing.append("pyperclip")
    
    try:
        import watchdog
    except ImportError:
        missing.append("watchdog")
    
    if missing:
        print("⚠️  Optional dependencies missing:")
        print(f"   pip install {' '.join(missing)}")
        print("\nThe system will run with reduced automation features.")
        print("Continue anyway? (y/n): ", end="")
        
        response = input().strip().lower()
        if response != 'y':
            print("Exiting. Install dependencies and try again.")
            sys.exit(0)
        print()

def main():
    """Main entry point with error handling"""
    
    print("=" * 60)
    print("ZMIDI AUTOMATION SYSTEM v2.0")
    print("=" * 60)
    
    # Check dependencies
    check_dependencies()
    
    try:
        # Import and run the main module
        from zmidi_automation.main import main as zmidi_main
        
        # Run with command line arguments
        sys.exit(zmidi_main())
        
    except ImportError as e:
        print(f"\n❌ Import Error: {e}")
        print("\nPossible solutions:")
        print("1. Install missing dependencies:")
        print("   pip install -r zmidi_automation/requirements.txt")
        print("2. Run the import test:")
        print("   python zmidi_automation/test_imports.py")
        print("3. Check the setup guide:")
        print("   zmidi_automation/SETUP_GUIDE.md")
        sys.exit(1)
        
    except KeyboardInterrupt:
        print("\n\n✋ Interrupted by user")
        sys.exit(0)
        
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        print("\nPlease report this issue with the full error trace.")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
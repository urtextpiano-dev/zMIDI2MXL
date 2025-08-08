# ZMIDI Automation Setup Guide

## Quick Fix for Import Error

You encountered:
```
NameError: name 'Any' is not defined
```

This has been **FIXED**. The issue was a missing import in `claude/client.py`.

## Complete Setup Instructions

### 1. Test All Imports
```bash
cd zmidi_automation
python test_imports.py
```

This will show you:
- ✅ Which modules import successfully
- ⚠️ Which optional dependencies are missing
- ❌ Any critical import errors

### 2. Install Dependencies

#### Minimal Setup (Basic Functionality)
```bash
# No additional packages needed - uses Python stdlib
python main.py --start
```

#### Full Setup (All Features)
```bash
# Install all optional dependencies
pip install -r requirements.txt

# On Windows, also install:
pip install pywin32
```

### 3. Verify Installation
```bash
# Run import test again
python test_imports.py

# If all green, you're ready:
python main.py --status
```

## Dependency Overview

| Package | Purpose | Required? | Features Lost Without It |
|---------|---------|-----------|-------------------------|
| watchdog | File monitoring | No | Manual sync file updates only |
| pyautogui | UI automation | No | Can't auto-type messages |
| pyperclip | Clipboard ops | No | Slower message typing |
| pytesseract | OCR | No | No prompt detection |
| Pillow | Screenshots | No | No visual monitoring |
| pywin32 | Windows API | No (Win) | No window focus control |

## Running Without Optional Dependencies

The system will still work but with reduced automation:

### What Works Without Dependencies:
- ✅ Configuration management
- ✅ State persistence
- ✅ Task processing
- ✅ Sync file management (manual)
- ✅ Basic pipeline execution

### What Doesn't Work:
- ❌ Auto-detecting Claude Code prompts
- ❌ Auto-accepting file creation
- ❌ Auto-typing messages
- ❌ Window focus management
- ❌ Screenshot capture

## Fallback Mode

If you can't install dependencies, use manual mode:
```bash
python main.py --start --manual-focus
```

You'll need to:
1. Manually focus the console window
2. Copy/paste messages to Claude
3. Manually accept file creation prompts
4. Update SYNC_STATUS.md manually

## Common Issues & Solutions

### Issue 1: Import Errors
```bash
# Solution: Run test script first
python test_imports.py
# Install missing packages shown
```

### Issue 2: OCR Not Working
```bash
# Install Tesseract OCR engine
# Windows: Download from https://github.com/tesseract-ocr/tesseract
# Linux: sudo apt-get install tesseract-ocr
# Mac: brew install tesseract
```

### Issue 3: pywin32 Installation Fails
```bash
# Alternative for Windows:
pip install pypiwin32
# Or download wheel from: https://www.lfd.uci.edu/~gohlke/pythonlibs/#pywin32
```

### Issue 4: Permission Errors
```bash
# Run as administrator (Windows) or with sudo (Linux/Mac)
# Or use virtual environment:
python -m venv venv
venv\Scripts\activate  # Windows
source venv/bin/activate  # Linux/Mac
pip install -r requirements.txt
```

## Testing Your Setup

### Step 1: Basic Test
```python
# test_basic.py
from zmidi_automation.config import AutomationConfig
from zmidi_automation.sync import SyncManager

config = AutomationConfig()
sync = SyncManager()
sync.update_status("TEST")
print("✅ Basic modules working!")
```

### Step 2: Full Test
```python
# test_full.py
from zmidi_automation.core import Orchestrator

orchestrator = Orchestrator()
print(f"✅ Full system initialized!")
print(f"Config: {orchestrator.config}")
```

## Next Steps

1. **Fix imports**: Already done ✅
2. **Install dependencies**: `pip install -r requirements.txt`
3. **Test imports**: `python test_imports.py`
4. **Run system**: `python main.py --start`

---

**The import error is fixed. Run `python main.py --start` again and it should work!**
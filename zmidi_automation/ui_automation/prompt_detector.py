"""
Claude Code prompt detection and handling
Critical for autonomous operation - detects and responds to file creation prompts
"""

import time
import re
from typing import Optional, Dict, List, Tuple, TYPE_CHECKING


def _spam_paused(lock_path: str = ".spam_pause.lock") -> bool:
    try:
        return Path(lock_path).exists()
    except Exception:
        return False


if TYPE_CHECKING:
    from PIL import Image as PILImage
from pathlib import Path
from dataclasses import dataclass
from datetime import datetime

try:
    import pyautogui

    PYAUTOGUI_AVAILABLE = True
except ImportError:
    PYAUTOGUI_AVAILABLE = False
    print("Warning: pyautogui not installed. Prompt detection disabled.")

try:
    import pytesseract
    from PIL import Image

    OCR_AVAILABLE = True
except ImportError:
    OCR_AVAILABLE = False
    print("Warning: pytesseract/PIL not installed. OCR disabled.")

    # Create dummy Image class to prevent NameError
    class Image:
        Image = None


def _spam_paused(lock_path: str = ".spam_pause.lock") -> bool:
    try:
        return Path(lock_path).exists()
    except Exception:
        return False


@dataclass
class PromptInfo:
    """Information about a detected Claude Code prompt"""

    prompt_type: str  # 'file_creation', 'modification', 'unknown'
    file_path: Optional[str]
    detected_text: str
    confidence: float
    timestamp: datetime
    screenshot_path: Optional[str]
    action_taken: Optional[str]


class PromptDetector:
    """Detects and handles Claude Code prompts"""

    def __init__(self, config, window_manager=None, screenshot_module=None):
        self.config = config
        self.window_mgr = window_manager
        self.screenshot = screenshot_module

        # Prompt patterns (updated to match Claude Code's actual prompts)
        self.prompt_patterns = {
            "file_creation": [
                r"Do you want to create.*\?",
                r"Would you like to create.*\?",
                r"Create new file.*\?",
                r"I'll create.*file",
                r"Creating.*\.md",
                r"Save.*analysis.*to",
                r"write.*file.*at",
            ],
            "modification": [
                r"Do you want to make this edit.*\?",
                r"Would you like to modify.*\?",
                r"Update.*file.*\?",
                r"Edit.*existing",
                r"Edit file",
            ],
            "error": [
                r"Error.*file",
                r"Permission denied",
                r"Cannot create",
            ],
        }

        # Expected file patterns for auto-accept
        self.safe_patterns = [
            r"SYNC_STATUS\.md",  # Critical for automation to work
            r"analysis_results/.*\.md",
            r".*simplification.*\.md",
            r".*documentation.*\.md",
            r"ANALYSIS_.*\.md",  # ANALYSIS_PROGRESS.md etc.
            r".*\.md$",  # All markdown files are generally safe
        ]

        # Dangerous patterns to reject
        self.danger_patterns = [
            r".*\.zig",
            r"src/.*",
            r".*\.py",
            r".*\.js",
            r".*\.ts",
        ]

        self.last_prompt_time = 0
        self.prompt_history: List[PromptInfo] = []

    def monitor_for_prompts(
        self, duration: int = 5, callback=None
    ) -> Optional[PromptInfo]:
        """Monitor screen for Claude Code prompts"""

        if not self.config.ui.prompt_detection_enabled:
            return None

        if not PYAUTOGUI_AVAILABLE:
            print("⚠️ Prompt detection unavailable (pyautogui not installed)")
            return None

        start_time = time.time()
        check_interval = 0.5

        while time.time() - start_time < duration:
            # Take screenshot
            screenshot = self._capture_screen()
            if not screenshot:
                time.sleep(check_interval)
                continue

            # Detect prompt
            prompt_info = self._detect_prompt(screenshot)

            if prompt_info:
                print(f"🔍 Detected prompt: {prompt_info.prompt_type}")

                # Handle the prompt
                if self.config.ui.auto_response_to_prompts:
                    handled = self.handle_prompt(prompt_info)
                    if handled:
                        prompt_info.action_taken = "auto_accepted"

                # Callback if provided
                if callback:
                    callback(prompt_info)

                # Record history
                self.prompt_history.append(prompt_info)
                self.last_prompt_time = time.time()

                return prompt_info

            time.sleep(check_interval)

        return None

    def _capture_screen(self) -> Optional["Image.Image"]:
        """Capture screenshot of console window"""
        try:
            if self.screenshot:
                # Use dedicated screenshot module if available
                return self.screenshot.capture()
            elif self.window_mgr:
                # Get window region
                region = self.window_mgr.get_window_region()
                if region:
                    screenshot = pyautogui.screenshot(region=region)
                    return screenshot
            else:
                # Full screen fallback
                return pyautogui.screenshot()
        except Exception as e:
            if self.config.debug:
                print(f"Screenshot failed: {e}")
            return None

    def _detect_prompt(self, screenshot: "Image.Image") -> Optional[PromptInfo]:
        """Detect Claude Code prompt in screenshot"""

        # Try OCR if available
        if OCR_AVAILABLE:
            try:
                text = pytesseract.image_to_string(screenshot)
                return self._analyze_text_for_prompt(text, screenshot)
            except Exception as e:
                if self.config.debug:
                    print(f"OCR failed: {e}")

        # Fallback: Look for visual patterns
        return self._detect_visual_patterns(screenshot)

    def _analyze_text_for_prompt(
        self, text: str, screenshot: "Image.Image"
    ) -> Optional[PromptInfo]:
        """Analyze OCR text for prompt patterns"""

        # Normalize text
        text_lower = text.lower()
        lines = text.split("\n")

        # Check for prompt patterns
        for prompt_type, patterns in self.prompt_patterns.items():
            for pattern in patterns:
                if re.search(pattern, text_lower):
                    # Extract file path if present
                    file_path = self._extract_file_path(text)

                    return PromptInfo(
                        prompt_type=prompt_type,
                        file_path=file_path,
                        detected_text=text[:500],  # First 500 chars
                        confidence=0.8,
                        timestamp=datetime.now(),
                        screenshot_path=None,
                        action_taken=None,
                    )

        # Check for button text (Claude Code specific)
        button_patterns = [
            r"1\.\s*Yes",  # Claude Code's actual prompt format
            r"2\.\s*Yes.*don't ask again",
            r"3\.\s*No.*tell Claude",
            r"\[1\].*Accept",
            r"\[2\].*Reject",
            r"Press.*to.*accept",
            r"Y/N",
        ]

        for pattern in button_patterns:
            if re.search(pattern, text, re.IGNORECASE):
                file_path = self._extract_file_path(text)
                return PromptInfo(
                    prompt_type="file_creation",
                    file_path=file_path,
                    detected_text=text[:500],
                    confidence=0.7,
                    timestamp=datetime.now(),
                    screenshot_path=None,
                    action_taken=None,
                )

        return None

    def _extract_file_path(self, text: str) -> Optional[str]:
        """Extract file path from text"""

        # Claude Code specific patterns (these are what actually appear)
        claude_patterns = [
            r"Do you want to create ([^\?\n]+)\?",
            r"Do you want to make this edit to ([^\?\n]+)\?",
            r"Create new file.*?([a-zA-Z0-9_/\\.-]+\.[a-zA-Z]+)",
            r"Edit file.*?([a-zA-Z0-9_/\\.-]+\.[a-zA-Z]+)",
        ]

        for pattern in claude_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                file_path = match.group(1).strip()
                print(f"   📁 Extracted file path: {file_path}")
                return file_path

        # Fallback patterns for file paths
        path_patterns = [
            r"([a-zA-Z0-9_/\\.-]+\.md)",
            r"analysis_results/[a-zA-Z0-9_/\\.-]+\.md",
            r"SYNC_STATUS\.md",
        ]

        for pattern in path_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                return match.group(1) if match.lastindex else match.group(0)

        return None

    def _detect_visual_patterns(
        self, screenshot: "Image.Image"
    ) -> Optional[PromptInfo]:
        """Detect prompts using visual patterns (fallback)"""

        # This is a simplified version
        # In production, you'd use computer vision techniques

        # Convert to grayscale
        gray = screenshot.convert("L")

        # Look for dialog-like regions (simplified)
        # Real implementation would use OpenCV or similar

        return None

    def handle_prompt(self, prompt_info: PromptInfo) -> bool:
        """Automatically handle a detected prompt"""

        if not PYAUTOGUI_AVAILABLE:
            return False

        # Determine action based on prompt type and file path
        action = self._determine_action(prompt_info)

        if action == "accept":
            print(f"✅ Auto-accepting: {prompt_info.file_path}")
            self._press_accept()
            return True
        elif action == "reject":
            print(f"❌ Auto-rejecting: {prompt_info.file_path}")
            self._press_reject()
            return True
        else:
            print(f"⚠️ Cannot auto-handle prompt: {prompt_info.file_path}")
            return False

    def _determine_action(self, prompt_info: PromptInfo) -> str:
        """Determine whether to accept or reject a prompt"""

        if not prompt_info.file_path:
            return "unknown"

        file_path = prompt_info.file_path

        # Check if it's a dangerous pattern
        for pattern in self.danger_patterns:
            if re.match(pattern, file_path):
                return "reject"

        # Check if it's a safe pattern
        for pattern in self.safe_patterns:
            if re.match(pattern, file_path):
                return "accept"

        # Check file extension
        if file_path.endswith(".md"):
            # Markdown files in analysis_results are safe
            if "analysis_results" in file_path:
                return "accept"

        # Default to unknown (manual intervention needed)
        return "unknown"

    def _press_accept(self):
        """Press the accept button (usually '1')"""
        try:
            if _spam_paused():
                return

            # Focus window first
            if self.window_mgr:
                self.window_mgr.focus_console()
                time.sleep(0.2)

            # Press '1' to accept (no enter needed for Claude Code)
            pyautogui.press("1")
            time.sleep(1)  # Wait a moment after pressing

        except Exception as e:
            print(f"Error pressing accept: {e}")

    def _press_reject(self):
        """Press the reject button (usually '3' or 'n')"""
        try:
            if _spam_paused():
                return

            # Focus window first
            if self.window_mgr:
                self.window_mgr.focus_console()
                time.sleep(0.2)

            # Press '3' to reject (Claude Code uses 3 for "No, and tell Claude what to do differently")
            pyautogui.press("3")
            time.sleep(1)  # Wait a moment after pressing

        except Exception as e:
            print(f"Error pressing reject: {e}")

    def wait_for_prompt(
        self, timeout: int = 30, expected_file: Optional[str] = None
    ) -> bool:
        """Wait for a specific prompt to appear"""

        print(f"⏳ Waiting for prompt... (timeout: {timeout}s)")

        prompt = self.monitor_for_prompts(duration=timeout)

        if prompt:
            if expected_file:
                if prompt.file_path and expected_file in prompt.file_path:
                    print(f"✅ Found expected prompt for: {expected_file}")
                    return True
                else:
                    print(f"⚠️ Found prompt but not for expected file")
                    return False
            else:
                print(f"✅ Found prompt: {prompt.prompt_type}")
                return True

        print("⏱️ No prompt detected within timeout")
        return False

    def get_recent_prompts(self, minutes: int = 5) -> List[PromptInfo]:
        """Get prompts from recent history"""
        cutoff = datetime.now().timestamp() - (minutes * 60)
        return [p for p in self.prompt_history if p.timestamp.timestamp() > cutoff]

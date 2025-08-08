#!/usr/bin/env python3
"""
Ideal Autonomous Code Analyzer v2 - Enhanced with Grok4 Recommendations
Improved synchronization, error handling, and performance tracking
"""

import os
import json
import time
import glob
import pyautogui
import hashlib
import logging
import platform
import cv2
import numpy as np
import re
import signal
import sys
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from multiprocessing import Queue
from threading import Thread

# Platform-specific imports
try:
    import fcntl
except ImportError:
    fcntl = None  # Not available on Windows

try:
    import pytesseract
except ImportError:
    pytesseract = None

from watchdog.observers.polling import PollingObserver
from watchdog.events import FileSystemEventHandler

from analysis_thinking_phrases import AnalysisThinkingPhrases


# Configure logging with more verbose output
logging.basicConfig(
    level=logging.DEBUG,  # More detailed logging
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('analyzer.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Global flag for clean shutdown
shutdown_requested = False

def signal_handler(signum, frame):
    """Handle Ctrl+C gracefully."""
    global shutdown_requested
    print("\n🛑 INTERRUPT RECEIVED - Shutting down gracefully...")
    print("📊 Saving current state and logs...")
    shutdown_requested = True
    
    # Force exit after 3 seconds if graceful shutdown fails
    def force_exit():
        print("\n⚠️  FORCING EXIT - Graceful shutdown timeout")
        os._exit(1)
    
    import threading
    timer = threading.Timer(3.0, force_exit)
    timer.daemon = True
    timer.start()

# Register signal handlers
signal.signal(signal.SIGINT, signal_handler)
if hasattr(signal, 'SIGTERM'):
    signal.signal(signal.SIGTERM, signal_handler)


class SyncFileHandler(FileSystemEventHandler):
    """Handle file system events for synchronization."""
    
    def __init__(self, sync_file: str, event_queue: Queue):
        self.sync_file = sync_file
        self.event_queue = event_queue
        self.last_hash = self._get_file_hash()
    
    def _get_file_hash(self) -> str:
        """Get current file hash."""
        if not os.path.exists(self.sync_file):
            return ""
        try:
            with open(self.sync_file, "rb") as f:
                return hashlib.md5(f.read()).hexdigest()
        except:
            return ""
    
    def on_modified(self, event):
        """Handle file modification events."""
        if event.src_path.endswith(os.path.basename(self.sync_file)):
            current_hash = self._get_file_hash()
            if current_hash != self.last_hash:
                self.last_hash = current_hash
                self.event_queue.put("file_changed")
                logger.debug(f"Sync file changed: {self.sync_file}")


class IdealAutonomousAnalyzerV2:
    """Production-ready analyzer with enhanced reliability."""
    
    def show_status(self, message: str, level: str = "info"):
        """Display clean status messages with appropriate icons."""
        icons = {
            "info": "ℹ️",
            "success": "✅", 
            "warning": "⚠️",
            "error": "❌",
            "working": "🔄",
            "waiting": "⏳",
            "search": "🔍"
        }
        icon = icons.get(level, "•")
        print(f"{icon} {message}")
        
        # Also log for debugging
        if level == "error":
            logger.error(message)
        elif level == "warning":
            logger.warning(message)
        else:
            logger.info(message)

    def __init__(self, manual_focus=False, auto_clear=True):
        # Communication files
        self.sync_file = "SYNC_STATUS.md"
        self.progress_file = "ANALYSIS_PROGRESS.md"
        self.rules_file = "SIMPLIFICATION_RULES.md"
        self.state_file = "analyzer_state.json"
        self.metrics_file = "analyzer_metrics.json"
        self.screenshot_dir = "screenshots/"
        
        # Configuration
        self.auto_clear = auto_clear  # Auto-clear conversation after each task
        
        # Safety tracking
        self.source_file_hashes = {}
        self.allowed_output_dirs = [
            "analysis_results/simplification/",
            "analysis_results/bugs/",
            "analysis_results/features/"
        ]
        
        # Performance tracking
        self.task_metrics = []
        self.start_time = time.perf_counter()
        
        # Synchronization
        self.sync_queue = Queue()
        self.observer = None
        
        # OCR-based prompt monitoring
        self.prompt_monitoring = True
        self.last_screenshot_time = 0
        self.screenshot_interval = 5  # Increased from 2 to 5 seconds - less aggressive monitoring
        self.fast_interval = 3  # Faster checking when expecting prompts
        self.slow_interval = 10  # Slower checking when Claude is working
        self.expecting_prompt = False  # Track when we expect a prompt
        
        # Claude Code prompt region (bottom area where prompts appear)
        # Format: (left, top, width, height) or None for full screen
        # No custom regions - always use console window
        
        self.manual_focus = manual_focus
        self.thinking = AnalysisThinkingPhrases()
        
        # Context management
        self.messages_sent = 0
        self.context_refresh_interval = 10
        
        # Track the focused window handle for consistent screenshots
        self.target_window_handle = None
        
        # OCR duplicate detection for failsafe recovery
        self.ocr_history = []
        self.max_ocr_history = 100  # Store up to 100 recent OCR readings
        self.ocr_count = 0  # Total OCR attempts counter
        # Progressive thresholds: try pressing "1" at 50, 75, and 99 similar texts
        
        # Context monitoring and auto-compact
        self.low_context_threshold = 15  # Trigger /compact when context < 15%
        self.last_context_percentage = None
        self.needs_compact = False
        self.compact_sent = False
        self.compact_cooldown_until = 0  # Prevent rapid re-compacting
        self.rule_reminder_interval = 12  # Remind of rules every 12-15 messages
        self.last_rule_reminder_count = 0
        
        # Configure pyautogui safely
        pyautogui.FAILSAFE = True
        pyautogui.PAUSE = 0.1
        
        # Create screenshot directory
        os.makedirs(self.screenshot_dir, exist_ok=True)
        
        self.analysis_phases = [
            {
                "name": "Function Simplification",
                "steps_file": None,  # No steps file - just one agent analysis per function
                "output_dir": "analysis_results/simplification/"
            }
        ]
        
        # Load custom prompt region if configured
        # No custom region config needed
        
        logger.info("Analyzer initialized with enhanced features v2.1 - WITH ZEN TOOLS")

    def setup_file_watcher(self):
        """Setup Watchdog for efficient file monitoring."""
        handler = SyncFileHandler(self.sync_file, self.sync_queue)
        self.observer = PollingObserver()  # Cross-platform compatible
        self.observer.schedule(handler, path='.', recursive=False)
        self.observer.start()
        logger.info("File watcher started")

    def stop_file_watcher(self):
        """Stop the file watcher."""
        if self.observer:
            self.observer.stop()
            self.observer.join()
            logger.info("File watcher stopped")

    def write_file_atomic(self, filepath: str, content: str):
        """Write file atomically with locking."""
        temp_file = f"{filepath}.tmp"
        try:
            with open(temp_file, "w", encoding="utf-8") as f:
                # Use file locking only on Unix systems
                if fcntl and platform.system() != "Windows":
                    fcntl.flock(f, fcntl.LOCK_EX)
                f.write(content)
                f.flush()
                os.fsync(f.fileno())
                if fcntl and platform.system() != "Windows":
                    fcntl.flock(f, fcntl.LOCK_UN)
            
            # Atomic rename
            os.replace(temp_file, filepath)
            logger.debug(f"Atomically wrote: {filepath}")
        except Exception as e:
            logger.error(f"Failed to write {filepath}: {e}")
            if os.path.exists(temp_file):
                os.remove(temp_file)
            raise

    def get_unique_output_filename(self, source_file: str) -> str:
        """Generate a unique output filename based on the full path."""
        # Remove src/ prefix if present
        if source_file.startswith("src/"):
            relative_path = source_file[4:]
        else:
            relative_path = source_file
        
        # Replace path separators with underscores and change extension
        output_name = relative_path.replace('/', '_').replace('\\', '_')
        output_name = output_name.replace('.txt', '.md').replace('.ts', '.md').replace('.tsx', '.md')
        
        return output_name
    
    def update_sync_file(self, content: str):
        """Update sync file atomically."""
        full_content = f"# SYNC STATUS\n\n{content}\n\n"
        full_content += f"Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        self.write_file_atomic(self.sync_file, full_content)

    def clear_conversation(self):
        """Send /clear command to clear conversation context."""
        try:
            print("   🧹 Clearing conversation context...")
            
            if not self.manual_focus:
                self.focus_console_window()
            
            # Type /clear command
            pyautogui.typewrite("/clear", interval=0.02)
            time.sleep(0.5)
            
            # Press Enter to execute
            pyautogui.press("enter")
            time.sleep(2)  # Wait for clear to complete
            
            logger.info("Conversation context cleared with /clear")
            
        except Exception as e:
            logger.error(f"Failed to clear conversation: {e}")
            print(f"   ❌ Failed to clear conversation: {e}")

    def wait_for_claude_update(self, timeout_minutes=None) -> str:
        """Wait for Claude to update sync file using Watchdog."""
        # Dynamic timeout based on file size
        if timeout_minutes is None:
            timeout_minutes = self.calculate_dynamic_timeout()
        
        logger.info(f"Waiting for status update (timeout: {timeout_minutes}min)...")
        
        max_wait = timeout_minutes * 60
        start_time = time.time()
        last_safety_check = time.time()
        last_prompt_check = 0
        
        while time.time() - start_time < max_wait and not shutdown_requested:
            try:
                # Check for shutdown first
                if shutdown_requested:
                    print("🛑 Shutdown requested during wait")
                    return "INTERRUPTED"
                
                # More frequent prompt monitoring during handshake
                current_time = time.time()
                if (self.prompt_monitoring and pytesseract and 
                    current_time - last_prompt_check >= 1):  # Check every 1 second
                    last_prompt_check = current_time
                    # Only show periodic status updates every 30 seconds
                    if int(current_time - start_time) % 30 == 0:
                        history_size = len(self.ocr_history)
                        print(f"⏳ Monitoring... ({int(current_time - start_time)}s elapsed, OCR: {self.ocr_count} total, {history_size} in history)")
                    self.monitor_for_prompts()
                
                # Check for file change event (non-blocking with timeout)  
                event = self.sync_queue.get(timeout=0.5)  # Shorter timeout for faster response
                if event == "file_changed":
                    status = self.read_sync_status()
                    print(f"📄 FILE CHANGED - Status: {status}")
                    logger.info(f"Status update received: {status}")
                    
                    # Verify no source modifications
                    safe, modified = self.verify_no_source_modifications()
                    if not safe:
                        logger.critical("Source files modified!")
                        self.emergency_stop(modified)
                        return "EMERGENCY_STOP"
                    
                    # During initialization, only return when we get the expected status
                    # Don't return intermediate statuses like WAITING_FOR_READY
                    if status in ["READY", "WORKING", "COMPLETE", "PASS", "ERROR", "HELP"]:
                        return status
                    else:
                        # Status like WAITING_FOR_READY - keep waiting
                        print(f"   ⏳ Intermediate status, continuing to wait...")
                        continue
                        
            except:
                pass  # Queue timeout, continue checking
            
            # Periodic safety check
            if time.time() - last_safety_check > 30:
                safe, modified = self.verify_no_source_modifications()
                if not safe:
                    logger.critical("Source modification detected during wait!")
                    self.emergency_stop(modified)
                    return "EMERGENCY_STOP"
                last_safety_check = time.time()
            
            # Progress indicator
            elapsed = int(time.time() - start_time)
            if elapsed > 0 and elapsed % 30 == 0:
                logger.debug(f"Still waiting... ({elapsed}s)")
        
        logger.warning(f"Timeout after {timeout_minutes} minutes")
        return "TIMEOUT"

    def calculate_dynamic_timeout(self) -> int:
        """Calculate timeout based on current context."""
        base_timeout = 5  # 5 minutes base
        
        # Add time based on file size if available
        if hasattr(self, 'current_file_size'):
            # 1 minute per MB
            size_factor = self.current_file_size / (1024 * 1024)
            base_timeout += int(size_factor)
        
        # Cap at 30 minutes
        return min(base_timeout, 30)

    def track_task_performance(self, task_id: str, duration: float, status: str):
        """Track performance metrics for each task."""
        metric = {
            "task_id": task_id,
            "duration": duration,
            "status": status,
            "timestamp": datetime.now().isoformat()
        }
        self.task_metrics.append(metric)
        
        # Save metrics periodically
        if len(self.task_metrics) % 10 == 0:
            self.save_metrics()

    def save_metrics(self):
        """Save performance metrics to file."""
        try:
            metrics_data = {
                "session_start": datetime.fromtimestamp(self.start_time).isoformat(),
                "total_duration": time.perf_counter() - self.start_time,
                "tasks": self.task_metrics,
                "avg_task_duration": sum(m["duration"] for m in self.task_metrics) / len(self.task_metrics) if self.task_metrics else 0
            }
            
            with open(self.metrics_file, "w", encoding="utf-8") as f:
                json.dump(metrics_data, f, indent=2)
            
            logger.debug(f"Saved {len(self.task_metrics)} metrics")
        except Exception as e:
            logger.error(f"Failed to save metrics: {e}")

    def retry_with_backoff(self, func, max_attempts=3, *args, **kwargs):
        """Retry a function with exponential backoff."""
        for attempt in range(max_attempts):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                if attempt == max_attempts - 1:
                    logger.error(f"Failed after {max_attempts} attempts: {e}")
                    raise
                
                wait_time = 2 ** attempt
                logger.warning(f"Attempt {attempt + 1} failed, retrying in {wait_time}s: {e}")
                time.sleep(wait_time)

    def type_message(self, message: str, wait_after=3):
        """Type message with retry logic."""
        def _type():
            # Update context if needed
            self.messages_sent += 1
            if self.messages_sent % self.context_refresh_interval == 0:
                self.refresh_context()
            
            # Type actual message
            if not self.manual_focus:
                self.focus_console_window()
            
            # IMPORTANT: We use Ctrl+Enter for newlines to avoid autocomplete issues
            # No need to escape newlines - we'll type them directly with Ctrl+Enter
            console_message = message
            
            # DEBUG: Check if the replacement is causing issues
            if "to begin." in message and "to begin." not in console_message:
                print(f"   ⚠️  WARNING: 'to begin.' was altered during newline replacement!")
                print(f"   Original ending: {repr(message[-30:])}")
                print(f"   Console ending: {repr(console_message[-30:])}")
            
            # Type message with proper interval for reliability
            print(f"   ⌨️ Typing {len(console_message)} characters...")
            # Debug: Show exactly what we're typing
            print(f"   📝 DEBUG - First 100 chars being typed: {repr(console_message[:100])}")
            
            # Split message by newlines and type each part quickly
            lines = console_message.split('\n')
            for i, line in enumerate(lines):
                if i > 0:
                    # Use Ctrl+Enter for newlines (except before first line)
                    pyautogui.hotkey('ctrl', 'enter')
                    time.sleep(0.05)  # Slightly longer pause to ensure newline registers
                
                # Type the entire line at once for speed
                if line:  # Only type if line is not empty
                    # Add a space at the end to prevent autocomplete on last word
                    line_to_type = line + " " if i == len(lines) - 1 else line
                    pyautogui.typewrite(line_to_type, interval=0.005)  # 5ms between chars for speed
            
            # Wait before pressing enter to ensure message is fully typed
            # Reduced wait time: 2ms per character, minimum 0.5s
            type_completion_wait = max(0.5, len(console_message) * 0.002)  # 2ms per character, min 0.5s
            print(f"   ⏳ Waiting {type_completion_wait:.1f}s for typing completion...")
            time.sleep(type_completion_wait)
            
            # Add a space to dismiss any autocomplete before sending
            print(f"   🚫 Adding space to dismiss autocomplete...")
            pyautogui.press("space")
            time.sleep(0.05)
            
            print(f"   ↵ Pressing Enter...")
            pyautogui.press("enter")
            
            # Track when we sent the message for smart waiting
            self.last_message_time = time.time()
            self.expecting_prompt = True  # Expect a prompt after sending message
            
            print(f"   ✅ Message sent ({len(message)} chars)")
            logger.info(f"Sent message ({len(message)} chars)")
            time.sleep(wait_after)
        
        try:
            self.retry_with_backoff(_type)
        except Exception as e:
            logger.error(f"Failed to type message: {e}")

    def check_usage_limits(self, text: str) -> bool:
        """Check if usage limits have been reached - but allow model switching."""
        text_lower = text.lower()
        
        # Import fuzzy matching
        from difflib import SequenceMatcher
        
        def fuzzy_match(text_to_check: str, pattern: str, threshold: float = 0.75) -> bool:
            """Check if pattern fuzzy matches in text with given threshold."""
            text_to_check_lower = text_to_check.lower()
            pattern_lower = pattern.lower()
            
            # For model switching, check if pattern appears anywhere in text
            if len(pattern) < 30:
                # Sliding window approach for better detection
                for i in range(len(text_to_check_lower) - len(pattern_lower) + 1):
                    substring = text_to_check_lower[i:i + len(pattern_lower) + 5]
                    ratio = SequenceMatcher(None, substring, pattern_lower).ratio()
                    if ratio >= threshold:
                        return True
            return False

        # Model switching indicators (these are OK - continue operation)
        # Use fuzzy matching to catch variations
        model_switch_patterns = [
            ("switching to sonnet", 0.75),
            ("switched to sonnet", 0.75),
            ("opus limit", 0.70),
            ("opus 4 limit", 0.70),
            ("opus 4 limits reached", 0.75),
            ("continuing with sonnet", 0.75),
            ("now using sonnet", 0.75),
            ("fallback to sonnet", 0.70),
            ("opus to sonnet", 0.70),
            ("model switch", 0.75)
        ]

        # Check if this is just a model switch using fuzzy matching
        for pattern, threshold in model_switch_patterns:
            if fuzzy_match(text, pattern, threshold):
                print(f"   🔄 Model switch detected: Opus → Sonnet (fuzzy match: '{pattern}', continuing operation)")
                logger.info(f"Claude Code switched models - fuzzy matched '{pattern}' - continuing")
                self.log_model_switch()
                return False  # Don't terminate - just a model switch

        # Also check for explicit model switching phrases with "limit" and model names together
        if ("limit" in text_lower or "reached" in text_lower) and \
           ("opus" in text_lower or "opus 4" in text_lower) and \
           ("sonnet" in text_lower or "switch" in text_lower or "continuing" in text_lower):
            print(f"   🔄 Model switch detected: Found limit + opus + sonnet/switch keywords (continuing)")
            logger.info("Model switch detected via keyword combination")
            self.log_model_switch()
            return False
        
        # HARD STOP indicators - these mean we can't continue at all
        hard_stop_indicators = [
            "all models unavailable",
            "no models available",
            "completely out of",
            "billing required",
            "payment required",
            "subscription expired",
            "account suspended",
            "api for more",  # This usually means ALL limits hit
            "upgrade to continue"
        ]
        
        # Check for hard stops first (exact match is fine for these)
        for indicator in hard_stop_indicators:
            if indicator in text_lower:
                logger.critical(f"HARD STOP: Usage limit indicator detected: {indicator}")
                return True
        
        # Soft limit indicators - only stop if no model switch mentioned
        soft_limit_indicators = [
            "usage limit",
            "rate limit",
            "quota exceeded",
            "limit reached",
            "usage exceeded",
            "daily limit",
            "monthly limit"
        ]
        
        # Check soft limits ONLY if no model switch is happening
        has_soft_limit = any(indicator in text_lower for indicator in soft_limit_indicators)
        has_model_info = any(model in text_lower for model in ["sonnet", "opus", "model", "switch", "fallback"])
        
        if has_soft_limit and not has_model_info:
            # Generic limit without model info - probably a hard stop
            logger.critical("Usage limit detected without model switch info - assuming hard stop")
            return True
        
        return False
    
    def log_model_switch(self):
        """Log when Claude switches models."""
        try:
            with open("model_switches.log", "a", encoding="utf-8") as f:
                f.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - Switched from Opus to Sonnet\n")
        except:
            pass
    
    def emergency_shutdown(self, reason: str):
        """Emergency shutdown of all operations."""
        print("\n" + "="*60)
        print("🚨 EMERGENCY SHUTDOWN 🚨")
        print("="*60)
        print(f"\nReason: {reason}")
        print("\nActions taken:")
        print("  • Saving current state")
        print("  • Updating SYNC_STATUS.md")
        print("  • Generating partial ACTION_REQUIRED.md")
        print("  • Terminating all operations")
        
        try:
            # Update sync status
            self.update_sync_file(f"STATUS: EMERGENCY_STOP\n\nReason: {reason}\n\nScript terminated to prevent errors.")
            
            # Save current state
            if hasattr(self, 'state') and self.state:
                self.write_file_atomic(self.state_file, json.dumps(self.state, indent=2))
            
            # Generate partial action list
            self.generate_action_list()
            
            # Log the shutdown
            logger.critical(f"Emergency shutdown: {reason}")
            
        except Exception as e:
            logger.error(f"Error during emergency shutdown: {e}")
        
        print("\n⚠️ IMPORTANT: Claude Code usage limits reached!")
        print("   Options:")
        print("   1. Wait for limits to reset")
        print("   2. Use Claude API directly")
        print("   3. Upgrade your plan")
        print("\n" + "="*60)
        
        # Force exit
        import sys
        sys.exit(1)

    def extract_context_percentage(self, text: str) -> Optional[int]:
        """Extract context percentage from OCR text."""
        import re
        
        # Look for patterns like "Context left until auto-compact: 3%"
        patterns = [
            r'context left until auto-compact:\s*(\d+)%',
            r'context left:\s*(\d+)%',
            r'context remaining:\s*(\d+)%',
            r'(\d+)%\s*context left',
            r'(\d+)%\s*remaining'
        ]
        
        text_lower = text.lower()
        for pattern in patterns:
            match = re.search(pattern, text_lower)
            if match:
                percentage = int(match.group(1))
                print(f"   📊 Context detected: {percentage}%")
                return percentage
        
        return None

    def should_send_compact(self) -> bool:
        """Check if we should send /compact command."""
        if self.last_context_percentage is not None:
            if (self.last_context_percentage <= self.low_context_threshold and 
                not self.compact_sent):
                return True
        return False


    def handle_low_context(self) -> bool:
        """Handle low context situation - non-blocking approach."""
        print(f"\n{'='*60}")
        print(f"🛑 COMPACT NEEDED - Context at {self.last_context_percentage}%")
        print(f"{'='*60}")
        logger.info(f"Low context detected at {self.last_context_percentage}%")
        
        # Check current task status
        current_status = self.read_sync_status()
        
        if current_status == "COMPLETE":
            # Task already complete, execute compact after brief wait
            print(f"✅ Task already completed - will compact in 30s...")
            self.compact_wait_start = time.time()
            self.compact_wait_duration = 30
            self.monitoring_for_complete = True
        else:
            # Start monitoring for completion
            print(f"⏳ Task in progress (Status: {current_status}) - monitoring for COMPLETE...")
            print(f"   (Will compact when task completes)")
            self.monitoring_for_complete = True
            self.monitoring_start_time = time.time()
        
        # Return True to indicate we've started monitoring
        return True
    
    def execute_compact(self) -> bool:
        """Execute the compact command with retry logic."""
        # Try to compact with retry logic
        max_attempts = 3
        compact_success = False
        
        for attempt in range(1, max_attempts + 1):
            print(f"\n📤 Sending /compact command (attempt {attempt}/{max_attempts})...")
            
            # Hold backspace for 10 seconds to clear any text
            print(f"🔙 Clearing input field (holding backspace)...")
            pyautogui.keyDown('backspace')
            time.sleep(10)
            pyautogui.keyUp('backspace')
            time.sleep(0.5)  # Small pause after releasing
            
            print(f"⌨️ Typing /compact...")
            pyautogui.typewrite('/compact', interval=0.01)
            pyautogui.press('enter')
            
            # Wait 3 minutes for compact to complete
            print(f"⏳ Waiting 3 minutes for /compact to complete...")
            print(f"   (The context indicator should disappear)")
            
            # Wait in 30-second intervals to show progress
            for i in range(6):  # 6 * 30 seconds = 3 minutes
                time.sleep(30)
                print(f"   {(i+1)*30}s elapsed...")
            
            # Check if compact was successful by looking for ANY context percentage
            print(f"📸 Checking if compact was successful...")
            screenshot_path = os.path.join(self.screenshot_dir, f"compact_check_{attempt}.png")
            pyautogui.screenshot(screenshot_path)
            
            # Use OCR to check for context percentage
            context_found = False
            detected_percentage = None
            
            if pytesseract:
                try:
                    img = cv2.imread(screenshot_path)
                    if img is not None:
                        text = pytesseract.image_to_string(img)
                        # Extract context percentage if present
                        detected_percentage = self.extract_context_percentage(text)
                        if detected_percentage is not None:
                            context_found = True
                            print(f"   📊 Detected context: {detected_percentage}%")
                except Exception as e:
                    logger.warning(f"OCR check failed: {e}")
            
            # Compact is successful if:
            # 1. No context percentage found (indicator disappeared)
            # 2. Context percentage > 40% (plenty of context after compact)
            if not context_found:
                print(f"✅ Compact successful! Context indicator disappeared (no percentage found).")
                compact_success = True
                break
            elif detected_percentage and detected_percentage > 40:
                print(f"✅ Compact successful! Context restored to {detected_percentage}%.")
                compact_success = True
                break
            else:
                print(f"⚠️ Compact may have failed - context still at {detected_percentage}%")
                if attempt < max_attempts:
                    print(f"   Retrying compact...")
                    time.sleep(5)  # Small pause before retry
                else:
                    print(f"❌ Compact failed after {max_attempts} attempts.")
        
        # Only set cooldown and clear flags if compact was successful
        if compact_success:
            # Set state to prevent re-detection
            self.compact_cooldown_until = time.time() + 900  # 15-minute cooldown
            self.needs_compact = False
            self.last_context_percentage = None  # Clear so we don't see old value
            
            # Send context refresh
            print(f"\n📤 Sending full context refresh...")
            self.send_full_context_refresh()
            
            print(f"\n✅ Compact complete! Resuming normal operations.")
            print(f"ℹ️ Will monitor for context again in 15 minutes")
            print(f"{'='*60}\n")
            
            return True
        else:
            # Compact failed - don't set cooldown so it can try again
            print(f"\n❌ Compact failed - will try again when context drops.")
            print(f"   Continuing operations but may hit context limits.")
            print(f"{'='*60}\n")
            
            # Clear the needs_compact flag to avoid infinite loop
            # but don't set cooldown so it can trigger again
            self.needs_compact = False
            
            return False

    def send_full_context_refresh(self, include_task=False):
        """Send comprehensive context refresh after /compact.
        
        Args:
            include_task: Whether to include the last task message (avoid double-sending)
        """
        try:
            # Read current sync status
            current_status = self.read_sync_status()
            
            # Get current task details
            task_details = self.get_current_task_details()
            
            # Build comprehensive context refresh message
            refresh_message = f"""[CONTEXT REFRESH AFTER /compact]

🚨 CRITICAL IDENTITY REMINDER:
You are communicating with autonomous_analyzer_ideal_v2.py - an automated Python script for systematic code analysis.

📋 CURRENT STATUS: {current_status}

🎯 CURRENT TASK:
{task_details}

🔒 CRITICAL SAFETY RULES:
1. NEVER MODIFY SOURCE CODE - Not even to fix bugs you find!
2. ONLY CREATE .md FILES - Documentation only  
3. ONLY IN analysis_results/ directories
4. NO OTHER FILE OPERATIONS - No deletes, renames, etc.
5. CLAUDE CODE FILE PROMPTS - ALWAYS press "1" to accept .md files in analysis_results/ only

⚡ SIMPLIFIED PROCESS - ONE AGENT PER FILE:
- Use ONLY @zmidi-code-simplifier agent for entire analysis
- NO other tools needed - the agent handles everything
- One comprehensive analysis per file
- Agent will only recommend 110% necessary improvements
- Focus on simplicity - less is more

📊 COMMUNICATION PROTOCOL:
Update SYNC_STATUS.md with EXACTLY one of these:
- STATUS: READY - Initial handshake complete
- STATUS: WORKING - Started analysis  
- STATUS: COMPLETE - Finished (with or without findings)
- STATUS: PASS - Skip this file/step
- STATUS: ERROR: [message] - Problem occurred
- STATUS: HELP: [question] - Need clarification

🎯 NEXT ACTION REQUIRED:
Please continue with the current task as outlined in SYNC_STATUS.md. Use @zmidi-code-simplifier agent for analysis.

Quality over speed - take as much time as needed for thorough analysis."""

            # Decide whether to include task based on current status
            # Only include task if status is WORKING or NEW_TASK (active work)
            should_include_task = include_task and current_status in ["WORKING", "NEW_TASK"]
            
            if should_include_task and hasattr(self, 'last_task_message'):
                print(f"   📤 Sending full context refresh with task...")
                # Type the context refresh without pressing enter
                print(f"   📝 Typing context refresh...")
                if not self.manual_focus:
                    self.focus_console_window()
                
                pyautogui.typewrite(refresh_message, interval=0.005)
                
                print(f"   📝 Adding task message...")
                pyautogui.typewrite("\n\n" + self.last_task_message, interval=0.005)
                
                # Now press enter to send both together
                print(f"   ↵ Pressing Enter to send combined message...")
                pyautogui.press("enter")
                
                print(f"   ✅ Context refresh + task sent successfully!")
                logger.info("Full context refresh with task sent after /compact")
            else:
                # Just send context refresh normally
                print(f"   📤 Sending full context refresh...")
                self.type_message(refresh_message, wait_after=3)
                print(f"   ✅ Context refresh sent successfully!")
                logger.info("Full context refresh sent after /compact")
            
        except Exception as e:
            print(f"   ❌ Failed to send context refresh: {e}")
            logger.error(f"Failed to send context refresh: {e}")

    def get_current_task_details(self) -> str:
        """Get details about the current task from SYNC_STATUS.md."""
        try:
            if os.path.exists(self.sync_file):
                with open(self.sync_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                # Extract task information
                lines = content.split('\n')
                task_info = []
                in_task_section = False
                
                for line in lines:
                    if line.startswith('## Task:'):
                        in_task_section = True
                        task_info.append(line)
                    elif in_task_section and line.startswith('**'):
                        task_info.append(line)
                    elif in_task_section and line.strip() == '':
                        if task_info:  # Stop at first empty line after task info
                            break
                
                if task_info:
                    return '\n'.join(task_info)
                else:
                    return "No specific task details found in SYNC_STATUS.md"
            else:
                return "SYNC_STATUS.md file not found"
                
        except Exception as e:
            logger.error(f"Failed to get current task details: {e}")
            return f"Error reading task details: {e}"

    def is_strict_file_prompt(self, text: str) -> bool:
        """Strictly detect Claude Code file creation/edit prompts."""
        text_lower = text.lower()
        
        # Must contain one of these prompt phrases
        prompt_phrases = [
            "do you want to create",
            "do you want to make this edit to",
            "do you want to edit",
            "want to create",
            "want to make this edit",
            "want to edit"
        ]
        
        # Must contain choice options - more lenient matching
        choice_indicators = [
            # Look for various formats of numbered choices
            ("1" in text and "yes" in text_lower and "2" in text),  # Basic check
            ("> 1" in text and "2." in text),  # Arrow format
            ("1." in text and "2." in text),   # Numbered list
            ("❯ 1" in text and "2" in text),   # Different arrow
            # Also check for the specific Claude Code pattern
            ("1 yes" in text_lower or "1. yes" in text_lower),
            # Check for "No" option which is common in prompts
            ("3" in text and ("no" in text_lower or "cancel" in text_lower))
        ]
        
        has_prompt_phrase = any(phrase in text_lower for phrase in prompt_phrases)
        has_choice_options = any(choice_indicators)
        
        # Additional validation: must be relatively short (actual prompt, not file content)
        is_reasonable_length = len(text.strip()) < 500
        
        # Must contain a filename with extension - more lenient pattern
        import re
        # Look for any filename pattern with common extensions
        filename_patterns = [
            r'[\w\-_]+\.(ts|tsx|js|jsx|py|md|json|yaml|yml|css|html|txt)',  # Standard files
            r'SYNC_STATUS\.md',  # Specific file we care about
            r'analysis_results/.*\.md',  # Analysis result patterns
            r'\w+\.\w{2,4}'  # Generic filename.ext pattern
        ]
        has_filename = any(re.search(pattern, text, re.IGNORECASE) for pattern in filename_patterns)
        
        result = has_prompt_phrase and has_choice_options and is_reasonable_length and has_filename
        
        # Only show validation details if debugging or if prompt detected
        if result:
            logger.debug(f"Prompt validation passed - phrase: {has_prompt_phrase}, choices: {has_choice_options}, length: {is_reasonable_length}, filename: {has_filename}")
        
        if not result and has_prompt_phrase:
            # Only log validation failures in debug mode
            logger.debug(f"Prompt validation failed - choices: {has_choice_options}, filename: {has_filename}")
        
        if result:
            print(f"   ✅ PROMPT DETECTED!")
        
        return result

    def calculate_text_similarity(self, text1: str, text2: str) -> float:
        """Calculate similarity between two texts using Levenshtein distance."""
        import difflib
        
        # Normalize texts (remove extra whitespace, lowercase)
        text1 = ' '.join(text1.lower().split())
        text2 = ' '.join(text2.lower().split())
        
        # Use difflib's SequenceMatcher for similarity
        similarity = difflib.SequenceMatcher(None, text1, text2).ratio()
        return similarity

    def attempt_claude_recovery(self) -> bool:
        """Attempt to recover Claude Code when it gets stuck."""
        try:
            print("🔄 ATTEMPTING CLAUDE RECOVERY...")
            logger.info("Starting Claude recovery procedure")
            
            # Step 1: Exit current command with Ctrl+Z
            print("   ⏹️ Stopping current process (Ctrl+Z)...")
            pyautogui.hotkey('ctrl', 'z')
            time.sleep(2)
            
            # Step 2: Clear input field and start claude --resume
            print("   🔙 Clearing input field (holding backspace for 15s)...")
            pyautogui.keyDown('backspace')
            time.sleep(15)  # Increased from 10 to 15 seconds
            pyautogui.keyUp('backspace')
            time.sleep(0.5)  # Small pause after releasing
            
            # Also try pressing backspace multiple times quickly
            print("   🔙 Additional backspace presses...")
            for _ in range(50):  # Press backspace 50 times
                pyautogui.press('backspace')
                time.sleep(0.01)  # Small delay between presses
            
            print("   🔄 Starting claude --resume...")
            pyautogui.typewrite('claude --resume', interval=0.01)
            pyautogui.press('enter')
            time.sleep(10)  # Wait for Claude to load
            
            # Step 3: Press 1 to load latest chat
            print("   📂 Loading latest chat (pressing 1)...")
            pyautogui.press('1')
            time.sleep(3)
            
            # Step 4: Clear OCR history to avoid immediate re-trigger
            self.ocr_history.clear()
            print("   🧹 Cleared OCR history")
            
            # Step 5: Send current task prompt again
            current_status = self.read_sync_status()
            if current_status in ["WORKING", "NEW_TASK"]:
                print("   📤 Resending current task prompt...")
                # Get the last message we would have sent
                if hasattr(self, 'last_task_message'):
                    self.type_message(self.last_task_message, wait_after=2)
                else:
                    # Fallback: send a generic continue message
                    continue_msg = "Continue with current task from SYNC_STATUS.md"
                    self.type_message(continue_msg, wait_after=2)
            
            logger.info("Claude recovery completed successfully")
            return True
            
        except Exception as e:
            print(f"   ❌ Recovery failed: {e}")
            logger.error(f"Claude recovery failed: {e}")
            return False

    def refresh_context(self):
        """Refresh context with summary instead of full rules."""
        logger.info("Refreshing context...")
        
        # Create a condensed summary
        summary = f"""[CONTEXT REFRESH #{self.messages_sent}]

Key Rules:
- NO source code modifications
- Only create .md files in analysis_results/
- Update SYNC_STATUS.md with your status
- Focus on current step only

Current Progress: {self.get_progress_summary()}
Continue with current task."""
        
        pyautogui.typewrite(summary, interval=0.001)
        pyautogui.press("enter")
        time.sleep(2)

    def get_progress_summary(self) -> str:
        """Get a brief progress summary."""
        if not hasattr(self, 'current_progress'):
            return "Starting analysis"
        
        return f"{self.current_progress:.1f}% complete"

    def generate_action_list(self):
        """Generate a consolidated list of files that need changes."""
        logger.info("Generating ACTION_REQUIRED.md...")
        
        action_content = f"""# 🎯 ACTION REQUIRED - Files Needing Changes

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

This is a quick reference list of all files that need modifications based on the analysis.

## 📋 Files Requiring Changes

"""
        
        files_needing_changes = []
        
        # Scan all analysis result files
        results_dir = "analysis_results/simplification/"
        if os.path.exists(results_dir):
            for filename in os.listdir(results_dir):
                if filename.endswith('.md'):
                    filepath = os.path.join(results_dir, filename)
                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            content = f.read()
                        
                        # Look for indicators that changes are needed
                        if any(indicator in content.lower() for indicator in [
                            "recommend", "should", "could be simplified", "needs",
                            "change", "refactor", "improve", "fix", "bug",
                            "simplification", "optimization"
                        ]):
                            # Extract the source file name from the analysis filename
                            source_file = filename.replace('.md', '.ts')
                            if 'types.md' in filename:
                                source_file = 'src/common/types.ts'
                            elif filename.replace('.md', '') in ['performanceHandlers', 'fileHandlers']:
                                source_file = f"src/main/handlers/{filename.replace('.md', '.ts')}"
                            else:
                                # Try to find the actual path from the content
                                import re
                                path_match = re.search(r'(?:File:|Analyzing:)\s*`?([^`\n]+\.tsx?)`?', content)
                                if path_match:
                                    source_file = path_match.group(1)
                            
                            files_needing_changes.append({
                                'file': source_file,
                                'analysis': filepath,
                                'summary': self.extract_change_summary(content)
                            })
                    except Exception as e:
                        logger.error(f"Error reading {filepath}: {e}")
        
        # Group by urgency/impact
        high_priority = []
        medium_priority = []
        low_priority = []
        
        for item in files_needing_changes:
            summary_lower = item['summary'].lower()
            if any(word in summary_lower for word in ['bug', 'error', 'critical', 'broken']):
                high_priority.append(item)
            elif any(word in summary_lower for word in ['performance', 'memory', 'latency']):
                medium_priority.append(item)
            else:
                low_priority.append(item)
        
        # Write the action list
        if high_priority:
            action_content += "### 🔴 HIGH PRIORITY (Bugs/Critical Issues)\n\n"
            for item in high_priority:
                action_content += f"- **{item['file']}**\n"
                action_content += f"  - Summary: {item['summary']}\n"
                action_content += f"  - Details: [{item['analysis']}]({item['analysis']})\n\n"
        
        if medium_priority:
            action_content += "### 🟡 MEDIUM PRIORITY (Performance/Optimization)\n\n"
            for item in medium_priority:
                action_content += f"- **{item['file']}**\n"
                action_content += f"  - Summary: {item['summary']}\n"
                action_content += f"  - Details: [{item['analysis']}]({item['analysis']})\n\n"
        
        if low_priority:
            action_content += "### 🟢 LOW PRIORITY (Simplification/Cleanup)\n\n"
            for item in low_priority:
                action_content += f"- **{item['file']}**\n"
                action_content += f"  - Summary: {item['summary']}\n"
                action_content += f"  - Details: [{item['analysis']}]({item['analysis']})\n\n"
        
        if not files_needing_changes:
            action_content += "✨ **No files require changes!** The codebase is in good shape.\n"
        else:
            action_content += f"\n## 📊 Summary\n\n"
            action_content += f"- Total files needing changes: {len(files_needing_changes)}\n"
            action_content += f"- High priority: {len(high_priority)}\n"
            action_content += f"- Medium priority: {len(medium_priority)}\n"
            action_content += f"- Low priority: {len(low_priority)}\n"
        
        # Save the action list
        with open("ACTION_REQUIRED.md", "w", encoding="utf-8") as f:
            f.write(action_content)
        
        print(f"✅ Generated ACTION_REQUIRED.md with {len(files_needing_changes)} files needing changes")
        logger.info(f"ACTION_REQUIRED.md created with {len(files_needing_changes)} files")

    def extract_change_summary(self, content: str) -> str:
        """Extract a brief summary of recommended changes from analysis content."""
        # Look for recommendation sections
        lines = content.split('\n')
        summary_parts = []
        
        in_recommendation = False
        for line in lines:
            if any(header in line for header in ['## Recommendation', '## Summary', '### Simplified']):
                in_recommendation = True
                continue
            elif line.startswith('##'):
                in_recommendation = False
            elif in_recommendation and line.strip() and not line.startswith('#'):
                # Get first meaningful line of recommendation
                summary_parts.append(line.strip())
                if len(summary_parts) >= 1:
                    break
        
        if summary_parts:
            return summary_parts[0][:100] + "..." if len(summary_parts[0]) > 100 else summary_parts[0]
        
        # Fallback: look for key phrases
        for line in lines:
            if any(key in line.lower() for key in ['should', 'recommend', 'needs', 'could be']):
                return line.strip()[:100] + "..." if len(line.strip()) > 100 else line.strip()
        
        return "Changes recommended"

    def generate_final_summary(self):
        """Generate comprehensive summary of all findings."""
        logger.info("Generating final summary...")
        
        # First, generate a quick action list
        self.generate_action_list()
        
        summary_content = f"""# Autonomous Analysis Summary

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Total Duration: {(time.perf_counter() - self.start_time) / 3600:.1f} hours

## Overview

This document summarizes all findings from the autonomous code analysis across three phases:
1. Pragmatic Simplification
2. Systematic Bug Hunt  
3. Feature Planning

## Key Statistics

"""
        
        # Collect all markdown files
        all_findings = []
        for phase in self.analysis_phases:
            phase_files = glob.glob(f"{phase['output_dir']}*.md")
            summary_content += f"- **{phase['name']}**: {len(phase_files)} files with findings\n"
            
            for file in phase_files:
                with open(file, "r", encoding="utf-8") as f:
                    content = f.read()
                    all_findings.append({
                        "phase": phase['name'],
                        "file": os.path.basename(file),
                        "content": content[:500] + "..." if len(content) > 500 else content
                    })
        
        # Add top findings
        summary_content += "\n## Top Findings by Phase\n\n"
        
        for phase in self.analysis_phases:
            summary_content += f"### {phase['name']}\n\n"
            phase_findings = [f for f in all_findings if f['phase'] == phase['name']]
            
            if phase_findings:
                for finding in phase_findings[:5]:  # Top 5 per phase
                    summary_content += f"**{finding['file']}**\n"
                    summary_content += f"```\n{finding['content']}\n```\n\n"
            else:
                summary_content += "No significant findings in this phase.\n\n"
        
        # Add performance metrics
        if self.task_metrics:
            avg_duration = sum(m["duration"] for m in self.task_metrics) / len(self.task_metrics)
            summary_content += f"\n## Performance Metrics\n\n"
            summary_content += f"- Average task duration: {avg_duration:.1f} seconds\n"
            summary_content += f"- Total tasks completed: {len(self.task_metrics)}\n"
            summary_content += f"- Success rate: {sum(1 for m in self.task_metrics if m['status'] == 'COMPLETE') / len(self.task_metrics) * 100:.1f}%\n"
        
        # Save summary
        self.write_file_atomic("ANALYSIS_SUMMARY.md", summary_content)
        logger.info("Summary generated: ANALYSIS_SUMMARY.md")
        
        # Also type a brief summary in chat
        brief_summary = f"""Analysis Complete! Summary generated in ANALYSIS_SUMMARY.md

Key Stats:
- Files analyzed: {len(self.get_source_files())}
- Total findings: {len(all_findings)}
- Duration: {(time.perf_counter() - self.start_time) / 3600:.1f} hours

Check ANALYSIS_SUMMARY.md for detailed findings."""
        
        self.type_message(brief_summary)

    # Keep all the safety methods from the original
    def initialize_source_monitoring(self) -> Dict[str, str]:
        """Hash ALL source files to detect any modifications."""
        logger.info("Initializing source file monitoring...")
        hashes = {}
        
        patterns = ["src/**/*.ts", "src/**/*.tsx", "src/**/*.js", "src/**/*.jsx"]
        for pattern in patterns:
            for file in glob.glob(pattern, recursive=True):
                if os.path.exists(file):
                    with open(file, "rb") as f:
                        hashes[file] = hashlib.sha256(f.read()).hexdigest()
        
        logger.info(f"Monitoring {len(hashes)} source files")
        return hashes

    def verify_no_source_modifications(self) -> Tuple[bool, List[str]]:
        """Check if any source files were modified."""
        modified = []
        
        for file, original_hash in self.source_file_hashes.items():
            if os.path.exists(file):
                with open(file, "rb") as f:
                    current_hash = hashlib.sha256(f.read()).hexdigest()
                if current_hash != original_hash:
                    modified.append(file)
        
        return len(modified) == 0, modified

    def emergency_stop(self, modified_files: List[str]):
        """Emergency stop with clear instructions."""
        msg = f"""🚨 EMERGENCY STOP - SOURCE FILES MODIFIED! 🚨

The following files were changed:
{chr(10).join(f'- {f}' for f in modified_files[:5])}

CRITICAL: Please revert ALL changes immediately!
Only .md documentation files should be created.

The analysis has been stopped for safety."""
        
        self.update_sync_file(f"STATUS: EMERGENCY_STOP\n\n{msg}")
        self.type_message(msg)
        
        # Save state for investigation
        with open("EMERGENCY_STOP_LOG.txt", "w") as f:
            f.write(f"Timestamp: {datetime.now()}\n")
            f.write(f"Modified files:\n")
            for f in modified_files:
                f.write(f"  - {f}\n")
        
        logger.critical(f"Emergency stop: {len(modified_files)} files modified")

    def focus_console_window(self):
        """Attempt to focus Console/Terminal window."""
        if os.name == "nt":  # Windows
            try:
                import win32gui
                import win32con
                
                def callback(hwnd, windows):
                    if win32gui.IsWindowVisible(hwnd):
                        text = win32gui.GetWindowText(hwnd)
                        # Skip the script's own window (be specific to avoid filtering out valid windows)
                        if "autonomous_analyzer" in text.lower() or "python  autonomous_analyzer" in text.lower():
                            return
                        # Check for console windows OR WSL sessions with @username format
                        if (any(term.lower() in text.lower() for term in ["PowerShell", "Windows PowerShell", "pwsh", "cmd.exe", "Command Prompt", "Windows Terminal", "Ubuntu", "WSL", "bash", "wsl.exe", "ubuntu"]) 
                            or ("@" in text and ":" in text)):
                            windows.append(hwnd)
                
                windows = []
                win32gui.EnumWindows(callback, windows)
                
                # Debug: show what windows were found
                console_windows = []
                import win32process
                current_pid = os.getpid()
                
                for hwnd in windows:
                    window_text = win32gui.GetWindowText(hwnd)
                    # Get process ID of this window
                    _, pid = win32process.GetWindowThreadProcessId(hwnd)
                    rect = win32gui.GetWindowRect(hwnd)
                    print(f"   Found: '{window_text}' (PID: {pid}, Pos: {rect[:2]})")
                    console_windows.append((hwnd, window_text, pid, rect))
                
                # Find target window - NOT the one running this script
                target_window = None
                
                # First pass: look for WSL windows (with @)
                for hwnd, text, pid, rect in console_windows:
                    if "@" in text and ":" in text:
                        target_window = (hwnd, text)
                        print(f"   ✓ Found WSL/SSH window: '{text}'")
                        break
                
                # Second pass: look for windows that are NOT running this script
                if not target_window:
                    for hwnd, text, pid, rect in console_windows:
                        # Skip if it's the same process as this script
                        if pid == current_pid:
                            print(f"   ⏭️  Skipping script window (same PID): '{text}'")
                            continue
                        
                        # Found a different console window
                        target_window = (hwnd, text)
                        print(f"   ✓ Found different console window: '{text}'")
                        break
                
                # If no different window found, try manual selection
                if not target_window and len(console_windows) > 1:
                    print(f"   🤔 Multiple windows found, using position-based selection...")
                    # Sort by window position (leftmost or topmost first)
                    console_windows.sort(key=lambda x: (x[3][0], x[3][1]))
                    # Take the first one that's not minimized
                    for hwnd, text, pid, rect in console_windows:
                        if rect[2] - rect[0] > 100:  # Width > 100 (not minimized)
                            target_window = (hwnd, text)
                            break
                
                if target_window:
                    hwnd, window_text = target_window
                    print(f"   🎯 Focusing on: '{window_text}'")
                    
                    # Save the window handle for consistent screenshots
                    # But NEVER save if it's the script window
                    if not any(keyword in window_text.lower() for keyword in ["autonomous_analyzer", ".py", "python"]):
                        self.target_window_handle = hwnd
                        print(f"   💾 Saved window handle for screenshots")
                    else:
                        print(f"   ⚠️ NOT saving script window handle!")
                    
                    win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
                    win32gui.SetForegroundWindow(hwnd)
                    time.sleep(0.5)
                    
                    # Don't click - console doesn't need clicking like VSCode chat
                    # Just focusing the window is enough
                    return True
                else:
                    print("   ❌ No console windows found!")
            except:
                pass
        return False

    def take_screenshot(self) -> str:
        """Take targeted screenshot of Claude Code prompt area."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{self.screenshot_dir}screenshot_{timestamp}.png"
        
        try:
            # Always get Console window region - no custom coordinates
            console_region = self.get_console_window_region()
                
            
            if console_region:
                # Take screenshot of Console window (capture more area for console)
                left, top, width, height = console_region
                # For console, capture bottom 25% where commands and output appear
                prompt_height = min(300, int(height * 0.25))
                prompt_top = top + height - prompt_height
                
                # Move the capture area up by 50 pixels from the bottom
                prompt_top = prompt_top - 50
                
                prompt_region = (left, prompt_top, width, prompt_height)
                print(f"   Using Console region: {prompt_region}")
                screenshot = pyautogui.screenshot(region=prompt_region)
                logger.debug(f"Console prompt area screenshot: {prompt_region}")
            else:
                # Fallback to screen bottom area
                screen_width, screen_height = pyautogui.size()
                prompt_region = (0, screen_height - 200, screen_width, 200)
                print(f"   Using fallback region: {prompt_region}")
                screenshot = pyautogui.screenshot(region=prompt_region)
                logger.debug(f"Screen bottom screenshot: {prompt_region}")
            
            screenshot.save(filename)
            print(f"   ✅ Screenshot saved: {filename}")
            return filename
        except Exception as e:
            print(f"   ❌ Screenshot failed: {e}")
            logger.error(f"Failed to take screenshot: {e}")
            return ""

    def get_console_window_region(self) -> Optional[tuple]:
        """Get Console/Terminal window bounds for targeted screenshots."""
        if os.name == "nt":  # Windows
            try:
                import win32gui
                
                # If we have a saved window handle, use it directly
                if self.target_window_handle:
                    try:
                        rect = win32gui.GetWindowRect(self.target_window_handle)
                        left, top, right, bottom = rect
                        width = right - left
                        height = bottom - top
                        window_text = win32gui.GetWindowText(self.target_window_handle)
                        logger.debug(f"Using saved window: '{window_text}' - Bounds: ({left}, {top}, {width}, {height})")
                        return (left, top, width, height)
                    except Exception as e:
                        print(f"   ⚠️ Saved window handle invalid: {e}")
                        self.target_window_handle = None
                
                # Fallback to searching for console windows
                def callback(hwnd, windows):
                    if win32gui.IsWindowVisible(hwnd):
                        text = win32gui.GetWindowText(hwnd)
                        # Skip the script's own window
                        if "autonomous_analyzer" in text.lower() or ".py" in text.lower() or "python" in text.lower():
                            return
                        # Check for console windows OR WSL sessions with @username format
                        if (any(term.lower() in text.lower() for term in ["PowerShell", "Windows PowerShell", "pwsh", "cmd.exe", "Command Prompt", "Windows Terminal", "Ubuntu", "WSL", "bash", "wsl.exe", "ubuntu"]) 
                            or ("@" in text and ":" in text)):
                            rect = win32gui.GetWindowRect(hwnd)
                            windows.append((hwnd, text, rect))
                
                windows = []
                win32gui.EnumWindows(callback, windows)
                
                # Find the right console window
                target_window = None
                target_text = None
                for hwnd, text, rect in windows:
                    print(f"   🪟 Found window: '{text}' at {rect}")
                    # Skip script windows
                    if "autonomous_analyzer" in text.lower() or ".py" in text.lower():
                        print(f"      ⏭️ Skipping script window")
                        continue
                    # Prefer windows with @ (WSL/SSH)
                    if "@" in text:
                        target_window = rect
                        target_text = text
                        print(f"      ✅ Selected WSL window: '{text}'")
                        break
                    # Otherwise take the first non-script window
                    if not target_window:
                        target_window = rect
                        target_text = text
                        print(f"      📌 Selected as fallback: '{text}'")
                
                if target_window:
                    left, top, right, bottom = target_window
                    width = right - left
                    height = bottom - top
                    print(f"   📐 DEBUG: Window bounds - Left: {left}, Top: {top}, Width: {width}, Height: {height}")
                    return (left, top, width, height)  # pyautogui format
                    
            except Exception as e:
                logger.debug(f"Could not get VSCode window region: {e}")
        
        return None


    def detect_claude_code_prompt(self, screenshot_path: str) -> Optional[Dict]:
        """Detect Claude Code prompts using OCR text recognition."""
        if not os.path.exists(screenshot_path) or not pytesseract:
            print("   ⏭️ Skipping OCR (no pytesseract or file)")
            return None
        
        try:
            # Load screenshot for OCR
            img = cv2.imread(screenshot_path)
            if img is None:
                return None
            
            # Use OCR to extract text from the image
            text = pytesseract.image_to_string(img)
            self.ocr_count += 1  # Increment OCR counter
            logger.debug(f"OCR #{self.ocr_count} extracted text: {text[:200]}...")
            
            # Check for usage limits FIRST - this is critical
            if self.check_usage_limits(text):
                print(f"   🚨 USAGE LIMITS REACHED - TERMINATING ALL OPERATIONS!")
                logger.critical("Claude Code usage limits reached - terminating script")
                self.emergency_shutdown("Usage limits reached")
                return None
            
            # Check for context percentage
            # The "Context left until auto-compact: X%" text appears when context is getting low
            # It shows up around 40% and counts down, disappears after compact
            context_percentage = self.extract_context_percentage(text)
            if context_percentage is not None:
                print(f"   📊 Context detected: {context_percentage}% remaining")
                self.last_context_percentage = context_percentage
                current_time = time.time()
                
                # Debug output to understand why compact isn't triggering
                if context_percentage <= self.low_context_threshold:
                    print(f"   🔍 Compact check: needs_compact={self.needs_compact}, cooldown_remaining={max(0, self.compact_cooldown_until - current_time):.0f}s")
                
                # Check if we should trigger compact (with cooldown)
                if (context_percentage <= self.low_context_threshold and 
                    not self.needs_compact and 
                    current_time > self.compact_cooldown_until):
                    print(f"   ⚠️ LOW CONTEXT WARNING: {context_percentage}% - Will compact!")
                    self.needs_compact = True
                elif context_percentage <= self.low_context_threshold:
                    # Show why we're not compacting
                    if self.needs_compact:
                        print(f"   ℹ️ Compact already scheduled (needs_compact=True)")
                    elif current_time <= self.compact_cooldown_until:
                        remaining = int(self.compact_cooldown_until - current_time)
                        print(f"   ℹ️ Compact on cooldown ({remaining}s remaining)")
                    if hasattr(self, 'compact_in_progress') and self.compact_in_progress:
                        print(f"   ℹ️ Compact already in progress")
            else:
                # No context text means either:
                # 1. We have plenty of context (>40%)
                # 2. We just compacted and text disappeared
                # Either way, we're good to continue
                pass
            
            # Check for OCR duplicates using fuzzy matching (failsafe detection)
            current_text = text.strip()
            self.ocr_history.append(current_text)
            
            # Keep only recent history
            if len(self.ocr_history) > self.max_ocr_history:
                self.ocr_history.pop(0)
            
            # Progressive duplicate handling - try pressing "1" at different thresholds
            history_length = len(self.ocr_history)
            
            # Define thresholds for progressive handling
            thresholds = [
                (50, 0.90, "first"),    # At 50 similar texts with 90% similarity
                (75, 0.90, "second"),   # At 75 similar texts with 90% similarity  
                (99, 0.90, "final")     # At 99 similar texts with 90% similarity
            ]
            
            for threshold, similarity_req, attempt_name in thresholds:
                if history_length >= threshold:
                    # Check if we've already tried at this threshold
                    threshold_key = f"tried_{threshold}"
                    if not hasattr(self, threshold_key):
                        # Check similarity for recent texts
                        recent_texts = self.ocr_history[-threshold:]
                        similar_count = 0
                        base_text = recent_texts[0]
                        
                        for check_text in recent_texts[1:]:
                            similarity = self.calculate_text_similarity(base_text, check_text)
                            if similarity >= similarity_req:
                                similar_count += 1
                        
                        similarity_ratio = similar_count / (len(recent_texts) - 1)
                        
                        if similarity_ratio >= 0.9:  # 90% of texts are similar
                            self.show_status(f"Similar text detected {threshold} times (similarity: {similarity_ratio:.0%}) - Attempting {attempt_name} recovery", "warning")
                            
                            # Try pressing "1" in case there's a hidden prompt
                            pyautogui.press("1")
                            time.sleep(2)
                            
                            # Mark that we tried at this threshold
                            setattr(self, threshold_key, True)
                            
                            # Only do full recovery after final threshold
                            if threshold == 99:
                                print(f"   🔄 Final threshold reached - attempting full Claude recovery...")
                                logger.warning(f"OCR stuck on similar text 99 times, triggering full recovery")
                                if self.attempt_claude_recovery():
                                    # Reset all threshold markers
                                    for t, _, _ in thresholds:
                                        if hasattr(self, f"tried_{t}"):
                                            delattr(self, f"tried_{t}")
                                    return None  # Skip this OCR cycle
                                else:
                                    print("   ❌ Recovery failed, continuing normally")
            
            # Only show OCR text if something meaningful is detected
            if text.strip() and len(text.strip()) > 10:
                # Just show a clean summary of what was detected
                text_preview = text[:100].replace('\n', ' ').strip()
                if len(text) > 100:
                    text_preview += "..."
                logger.debug(f"OCR preview: {text_preview}")
            
            # Look for Claude Code prompt patterns - both dialog text AND file content
            prompt_detected = False
            prompt_type = None
            
            # Create lowercase version for case-insensitive matching
            text_lower = text.lower()
            
            # Method 1: Look for any prompt with numbered options (very lenient)
            # Auto-accept any prompt that has "1" and "2" options with Yes/No pattern
            # More flexible pattern matching - look for "1" followed by space/period and "2" 
            import re
            has_option_1 = bool(re.search(r'[>❯]?\s*1[\s\.]', text))
            has_option_2 = bool(re.search(r'2[\s\.]', text))
            has_question = "?" in text
            
            # Debug output to understand detection
            if has_question and (has_option_1 or has_option_2):
                logger.info(f"Potential prompt - Option1: {has_option_1}, Option2: {has_option_2}, Question: {has_question}")
            
            if has_option_1 and has_option_2 and has_question:
                prompt_detected = True
                prompt_type = "bash_command"  # Use bash_command type for all auto-accept prompts
                print("   🎯 PROMPT WITH OPTIONS DETECTED (auto-accepting)!")
                logger.debug(f"Option detection - Option1: {has_option_1}, Option2: {has_option_2}, Question: {has_question}")
            
            # Method 2: Special handling for SYNC_STATUS.md - always accept
            elif "sync_status.md" in text_lower and ("do you want to" in text_lower or "create" in text_lower or "edit" in text_lower):
                prompt_detected = True
                prompt_type = "sync_status"
                filename = "SYNC_STATUS.md"
                print("   🎯 SYNC_STATUS.md PROMPT DETECTED - Critical file!")
            
            # Method 3: Look for file edit prompts - STRICT detection only
            elif self.is_strict_file_prompt(text):
                prompt_detected = True
                prompt_type = "file_edit"
                print("   🎯 CLAUDE CODE FILE PROMPT DETECTED (strict match)!")
            
            # Method 3: Look for file content patterns (what we're actually seeing)
            elif ("SYNC_STATUS.md" in text and "# SYNC STATUS" in text):
                prompt_detected = True
                prompt_type = "file_content"
                print("   🎯 CLAUDE CODE PROMPT DETECTED (file content)!")
            
            if prompt_detected:
                logger.info("Claude Code prompt detected via OCR")
                
                # Extract filename from the prompt text
                filename = self.extract_filename_from_ocr_text(text)
                print(f"   📄 Extracted filename: {filename}")
                
                return {
                    "type": prompt_type,
                    "screenshot": screenshot_path,
                    "filename": filename,
                    "text": text
                }
            else:
                # No detected prompt - show debug info if there's meaningful text
                if text.strip() and len(text.strip()) > 20:
                    print(f"   ℹ️ No prompt detected. Has question: {has_question}, Option1: {has_option_1}, Option2: {has_option_2}")
                    if has_question:
                        logger.debug(f"Text with question but no options detected: {text[:200]}")
                else:
                    print("   ✅ No prompt detected (minimal text)")
            
            return None
        except Exception as e:
            print(f"   ❌ OCR error: {e}")
            logger.error(f"Error in OCR detection: {e}")
            return None

    def extract_filename_from_ocr_text(self, text: str) -> str:
        """Extract filename from OCR text."""
        try:
            # Look for common patterns in Claude Code prompts
            patterns = [
                r"Do you want to create ([^\?\n]+)\?",
                r"Do you want to make this edit to ([^\?\n]+)\?",
                r"([a-zA-Z0-9_]+\.(md|ts|tsx|js|jsx|py))",
            ]
            
            for pattern in patterns:
                match = re.search(pattern, text)
                if match:
                    filename = match.group(1).strip()
                    logger.info(f"Extracted filename from OCR: {filename}")
                    return filename
            
            # Fallback to context extraction
            return self.extract_filename_from_context()
            
        except Exception as e:
            logger.error(f"Error extracting filename from OCR: {e}")
            return "unknown"

    def extract_filename_from_context(self) -> str:
        """Extract filename from current context."""
        try:
            # First, check if we can extract from the prompt dialog itself
            # This would require OCR in a real implementation
            
            # For now, check sync file for current task context
            if os.path.exists(self.sync_file):
                with open(self.sync_file, "r", encoding="utf-8") as f:
                    content = f.read()
                
                # Look for file patterns in the sync file
                import re
                
                # Look for output file mentions (what we're trying to create)
                output_match = re.search(r'\*\*Output\*\*:\s*`([^`]+)`', content)
                if output_match:
                    full_path = output_match.group(1)
                    return os.path.basename(full_path)
                
                # Look for analysis_results/ files (documentation)
                doc_match = re.search(r'analysis_results/[^/]+/(\w+\.md)', content)
                if doc_match:
                    return doc_match.group(1)
                
                # Look for src/ files being analyzed (source code)
                src_match = re.search(r'\*\*File\*\*:\s*`([^`]+)`', content)
                if src_match:
                    full_path = src_match.group(1)
                    # Extract just the filename
                    return os.path.basename(full_path)
                
                # Look for any filename pattern
                file_match = re.search(r'(\w+\.(ts|tsx|js|jsx|md|py))', content)
                if file_match:
                    return file_match.group(1)
            
            return "unknown"
        except Exception as e:
            logger.error(f"Error extracting filename: {e}")
            return "unknown"

    def determine_file_type(self, filename: str) -> str:
        """Determine if prompt is for documentation (.md) or source code."""
        try:
            # Check file extension
            if filename.endswith('.md'):
                return "documentation"
            elif filename.endswith(('.ts', '.tsx', '.js', '.jsx', '.py')):
                return "source_code"
            
            # If filename unclear, check sync file context
            if os.path.exists(self.sync_file):
                with open(self.sync_file, "r", encoding="utf-8") as f:
                    content = f.read().lower()
                
                # If sync file mentions analysis_results, likely documentation
                if "analysis_results/" in content and ".md" in content:
                    return "documentation"
                
                # If mentions source files, might be trying to modify code  
                if any(ext in content for ext in [".ts", ".tsx", ".js", ".jsx", ".py"]):
                    return "source_code"
            
            # Default to documentation since that's our main use case
            return "documentation"
            
        except Exception as e:
            logger.error(f"Error determining file type: {e}")
            return "unknown"

    def handle_claude_code_prompt(self, prompt_info: Dict) -> bool:
        """Automatically handle Claude Code prompts."""
        try:
            prompt_type = prompt_info.get("type", "unknown")
            filename = prompt_info.get("filename", "unknown")
            
            print(f"🎮 HANDLING PROMPT: {prompt_type} for file: {filename}")
            logger.info(f"Claude Code prompt: {prompt_type} for file: {filename}")
            
            if prompt_type == "bash_command":
                # Always accept bash commands by pressing "1"
                print(f"   ✅ ACCEPTING bash command - Pressing key '1'")
                logger.info(f"ACCEPT: Bash command (pressing 1)")
                pyautogui.press("1")
                print(f"   ⌨️ Key '1' pressed!")
                time.sleep(1)
                return True
            
            elif prompt_type == "sync_status":
                # Always accept SYNC_STATUS.md edits - critical for operation
                print(f"   ✅ ACCEPTING SYNC_STATUS.md edit - Pressing key '1'")
                logger.info(f"ACCEPT: SYNC_STATUS.md edit (pressing 1)")
                pyautogui.press("1")
                print(f"   ⌨️ Key '1' pressed!")
                time.sleep(1)
                return True
            
            else:
                # Handle file-related prompts
                file_type = self.determine_file_type(filename)
                
                if file_type == "documentation":
                    # Press "1" to accept documentation file creation
                    print(f"   ✅ ACCEPTING .md file - Pressing key '1'")
                    logger.info(f"ACCEPT: Documentation file: {filename} (pressing 1)")
                    pyautogui.press("1")
                    print(f"   ⌨️ Key '1' pressed!")
                    time.sleep(1)
                    return True
                    
                elif file_type == "source_code":
                    # Press "3" to reject source code modification
                    print(f"   🚫 REJECTING source code - Pressing key '3'")
                    logger.warning(f"REJECT: Source code modification: {filename} (pressing 3)")
                    pyautogui.press("3")
                    print(f"   ⌨️ Key '3' pressed!")
                    time.sleep(1)
                    
                    # Inform Claude not to modify source code
                    reminder_msg = f"""SOURCE CODE MODIFICATION BLOCKED!

File: {filename}
Action: Rejected modification attempt

CRITICAL REMINDER:
- Only create .md documentation files in analysis_results/
- Never modify source code files (.ts, .tsx, .js, .jsx, .py)
- Focus on analysis and documentation only

Continue with current task using documentation approach."""
                    
                    print(f"   💬 Sending reminder message to Claude...")
                    self.type_message(reminder_msg)
                    self.refresh_context()  # Refresh rules
                    return True
                
                else:
                    # Unknown - be safe and reject
                    print(f"   ❓ UNKNOWN file type - Pressing key '3' (safe reject)")
                    logger.warning(f"UNKNOWN: File type: {filename}, rejecting (pressing 3)")
                    pyautogui.press("3")
                    print(f"   ⌨️ Key '3' pressed!")
                    time.sleep(1)
                    
                    # Ask for clarification
                    clarification_msg = f"""Unclear file modification attempt: {filename}

Please focus on creating .md documentation files only.
Continue with current analysis task."""
                    
                    print(f"   💬 Sending clarification message...")
                    self.type_message(clarification_msg)
                    return True
                
        except Exception as e:
            print(f"   ❌ Error handling prompt: {e}")
            logger.error(f"Error handling prompt: {e}")
            return False

    def monitor_for_prompts(self):
        """Continuously monitor for Claude Code prompts with smart waiting."""
        current_time = time.time()
        
        # Use dynamic interval based on whether we're expecting a prompt
        interval = self.fast_interval if self.expecting_prompt else self.slow_interval
        
        if current_time - self.last_screenshot_time >= interval:
            self.last_screenshot_time = current_time
            
            # Ensure console is ready for capture
            self.ensure_chat_ready_for_capture()
            
            # Take screenshot
            screenshot_path = self.take_screenshot()
            if not screenshot_path:
                return
            
            # Check for prompts
            prompt_info = self.detect_claude_code_prompt(screenshot_path)
            if prompt_info:
                logger.info("Claude Code prompt detected, handling...")
                self.expecting_prompt = False  # Reset since we found a prompt
                success = self.handle_claude_code_prompt(prompt_info)
                
                if success:
                    # Keep screenshot for debugging
                    debug_name = screenshot_path.replace(".png", "_prompt_handled.png")
                    os.rename(screenshot_path, debug_name)
                    logger.info(f"Prompt handled, screenshot saved: {debug_name}")
                    
                    # Clear OCR history and reset threshold markers after successful prompt handling
                    self.ocr_history.clear()
                    for threshold in [50, 75, 99]:
                        if hasattr(self, f"tried_{threshold}"):
                            delattr(self, f"tried_{threshold}")
                    print("   🧹 Cleared OCR history after successful prompt handling")
                    
                    # Force check file after prompt handling (bypass Watchdog timing issues)
                    time.sleep(2)  # Give Claude Code time to create/update file
                    if os.path.exists(self.sync_file):
                        logger.info("Checking sync file directly after prompt handling")
                        self.sync_queue.put("file_changed")  # Trigger immediate check
                else:
                    logger.error("Failed to handle prompt")
            else:
                # No prompt, clean up screenshot to save space
                try:
                    os.remove(screenshot_path)
                except:
                    pass
                
                # Reset expecting_prompt after timeout (30 seconds)
                if self.expecting_prompt and (time.time() - self.last_message_time > 30):
                    print("   ⏱️ No prompt appeared after 30s, resuming normal monitoring")
                    self.expecting_prompt = False
            
            # Check for low context and handle if needed
            if self.needs_compact and not hasattr(self, 'compact_in_progress'):
                print(f"🔄 LOW CONTEXT DETECTED - Starting monitoring...")
                self.compact_in_progress = True
                self.handle_low_context()  # Non-blocking, just sets up monitoring
                
            # Check if we should execute compact now
            if hasattr(self, 'monitoring_for_complete') and self.monitoring_for_complete:
                # Check if we have a scheduled wait
                if hasattr(self, 'compact_wait_start'):
                    if time.time() - self.compact_wait_start >= self.compact_wait_duration:
                        print(f"⏰ Wait complete, executing compact...")
                        success = self.execute_compact()
                        # Clean up monitoring state
                        self.monitoring_for_complete = False
                        if hasattr(self, 'compact_in_progress'):
                            delattr(self, 'compact_in_progress')
                        if hasattr(self, 'compact_wait_start'):
                            delattr(self, 'compact_wait_start')
                        if hasattr(self, 'monitoring_start_time'):
                            delattr(self, 'monitoring_start_time')
                else:
                    # Check for task completion or timeout
                    status = self.read_sync_status()
                    elapsed = time.time() - self.monitoring_start_time
                    
                    if status == "COMPLETE":
                        print(f"✅ Task completed! Waiting 30s before compact...")
                        self.compact_wait_start = time.time()
                        self.compact_wait_duration = 30
                    elif elapsed >= 600:  # 10 minute timeout
                        print(f"⚠️ Task timeout after 10 minutes, compacting anyway...")
                        success = self.execute_compact()
                        # Clean up monitoring state
                        self.monitoring_for_complete = False
                        if hasattr(self, 'compact_in_progress'):
                            delattr(self, 'compact_in_progress')
                        if hasattr(self, 'monitoring_start_time'):
                            delattr(self, 'monitoring_start_time')
                    elif int(elapsed) % 30 == 0 and int(elapsed) > 0:  # Progress updates
                        print(f"   Still monitoring... ({int(elapsed)}s elapsed, status: {status})")

    def ensure_chat_ready_for_capture(self):
        """Ensure console is ready for screenshot capture."""
        try:
            print("   🎯 Preparing console for screenshot capture...")
            
            # Focus Console first (but don't click)
            if not self.manual_focus:
                print("   🔍 Focusing Console window...")
                self.focus_console_window_minimal()
            
            # Console windows are simpler - just ensure it's active
            time.sleep(0.5)
            
            # Wait for console to stabilize
            print("   ⏳ Waiting for console to stabilize...")
            time.sleep(0.5)
            
            # Additional wait if we recently typed something
            if hasattr(self, 'last_message_time'):
                time_since_message = time.time() - self.last_message_time
                if time_since_message < 5:  # Within 5 seconds of typing
                    print(f"   ⏳ Recent command detected ({time_since_message:.1f}s ago), extra wait...")
                    logger.debug("Recent command detected, waiting for output...")
                    time.sleep(1)  # Wait for command output
            
            print("   ✅ Chat ready for capture!")
            
        except Exception as e:
            print(f"   ❌ Error preparing chat: {e}")
            logger.debug(f"Error ensuring chat ready: {e}")

    def focus_console_window_minimal(self):
        """Minimal Console/Terminal focus without clicking in chat area."""
        if os.name == "nt":  # Windows
            try:
                import win32gui
                import win32con
                
                def callback(hwnd, windows):
                    if win32gui.IsWindowVisible(hwnd):
                        text = win32gui.GetWindowText(hwnd)
                        # Check for console windows OR WSL sessions with @username format
                        if (any(term.lower() in text.lower() for term in ["PowerShell", "Windows PowerShell", "pwsh", "cmd.exe", "Command Prompt", "Windows Terminal", "Ubuntu", "WSL", "bash", "wsl.exe", "ubuntu"]) 
                            or ("@" in text and ":" in text)):
                            windows.append((hwnd, text))
                
                windows = []
                win32gui.EnumWindows(callback, windows)
                
                # Find the right console window
                target_window = None
                for hwnd, text in windows:
                    # Skip script windows
                    if "autonomous_analyzer" in text.lower() or ".py" in text.lower():
                        continue
                    # Prefer windows with @ (WSL/SSH)
                    if "@" in text:
                        target_window = hwnd
                        break
                    # Otherwise take the first non-script window
                    if not target_window:
                        target_window = hwnd
                
                if target_window:
                    win32gui.ShowWindow(target_window, win32con.SW_RESTORE)
                    win32gui.SetForegroundWindow(target_window)
                    time.sleep(0.2)  # Brief pause for focus
                    return True
            except:
                pass
        return False

    def read_sync_status(self) -> str:
        """Extract status from sync file."""
        if not os.path.exists(self.sync_file):
            return "MISSING"
        
        try:
            with open(self.sync_file, "r", encoding="utf-8") as f:
                content = f.read()
            
            for line in content.split("\n"):
                line = line.strip()
                if line.startswith("STATUS:"):
                    return line.split(":", 1)[1].strip()
        except Exception as e:
            logger.error(f"Failed to read sync status: {e}")
        
        return "INVALID"

    def create_rules_file(self):
        """Create comprehensive rules file."""
        rules = """# ZIG FUNCTION SIMPLIFICATION RULES

## CRITICAL: You are talking to an automated Python script!

### Identity Verification
- **Script**: autonomous_analyzer_ideal_v2.py
- **Purpose**: Systematic Zig function simplification analysis
- **Communication**: File-based through SYNC_STATUS.md
- **Claude Code Agents**: Use @zmidi-code-simplifier for ALL simplification tasks

### 🎯 YOUR SIMPLE MISSION
Read the function. Ask "Why is this complex when it could be simpler?" Test your simpler version. If tests pass, recommend it. If not, say it's fine as is.

### 🚨 ABSOLUTE HONESTY REQUIREMENTS 🚨
1. **BE BRUTALLY HONEST** - Don't sugarcoat findings
2. **NO FABRICATION** - Never make up metrics or test results
3. **RUN ACTUAL TESTS** - Use `zig build test` to verify simplifications
4. **STATE LIMITATIONS** - Be clear about what you cannot measure
5. **MEANINGFUL CHANGES ONLY** - Minimum 20% complexity reduction to report

### Testing Protocol (from extracted functions)
1. Identify source file from function metadata
2. Navigate to the actual .zig file in the project
3. Apply your simplification to the actual function
4. Run `zig build test` (handle errors gracefully)
5. Document exact results (pass/fail/compilation error)
6. ALWAYS revert changes - leave no modifications
7. If tests pass: 110% confidence achieved

### What You CAN Test
- **Functional Equivalence**: Run existing tests to verify behavior
- **Compilation Success**: Verify code compiles without errors
- **Test Coverage**: Run regression tests, voice preservation tests
- **Basic Validation**: Run converter on test files if needed

### What You CANNOT Fabricate (be honest)
- Precise runtime benchmarks (like "21.0ms → 8.7ms")
- Detailed memory profiling statistics
- Binary size comparisons down to the byte
- Performance percentages you didn't actually measure

### Communication Protocol
Update SYNC_STATUS.md with EXACTLY one of these:
- `STATUS: READY` - Initial handshake complete
- `STATUS: WORKING` - Started analysis
- `STATUS: COMPLETE` - Finished (with or without findings)
- `STATUS: PASS` - No simplification needed (function already optimal)
- `STATUS: ERROR: [message]` - Problem occurred
- `STATUS: HELP: [question]` - Need clarification

### Quality Standards
- If function is already optimal, say "No simplification needed" and move on
- Don't invent improvements just to seem helpful
- Focus on algorithmic improvements, not cosmetic changes
- If simplification is marginal (<20%), say "Minor improvement possible but not recommended"

### Remember
Quality over speed - thorough analysis required.
Be blunt and direct - truth over comfort.
Actually run tests - don't guess or assume.
"""
        
        self.write_file_atomic(self.rules_file, rules)

    def load_steps(self, steps_file: str) -> List[Dict]:
        """Parse steps from analysis file."""
        if not os.path.exists(steps_file):
            return []
        
        steps = []
        with open(steps_file, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip().startswith("STEP ") and ":" in line:
                    parts = line.strip().split(":", 1)
                    steps.append({
                        "number": parts[0].replace("STEP", "").strip(),
                        "title": parts[1].strip()
                    })
        return steps

    def load_step_methodology(self, steps_file: str, step_number: str) -> str:
        """Load the full methodology for a specific step."""
        print(f"🔍 DEBUG load_step_methodology: file={steps_file}, step_number='{step_number}'")
        
        if not os.path.exists(steps_file):
            print(f"❌ DEBUG: Steps file not found: {steps_file}")
            return f"Error: Steps file {steps_file} not found"
        
        with open(steps_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        print(f"📄 DEBUG: Loaded file, total length: {len(content)} chars")
        
        # Extract ALL content for this step including detailed actions
        import re
        # Match from STEP X: until the next STEP or end markers
        step_pattern = rf'STEP {step_number}:[^\n]*\n(.*?)(?=\nSTEP \d+:|FINAL STEP:|KEY PRINCIPLES:|$)'
        print(f"🔍 DEBUG: Using pattern: {step_pattern}")
        match = re.search(step_pattern, content, re.DOTALL)
        
        if match:
            print(f"✅ DEBUG: Initial match found, groups: {len(match.groups())}")
            # Get the full match including the STEP header and ALL content
            full_step_pattern = rf'(STEP {step_number}:.*?)(?=\nSTEP \d+:|FINAL STEP:|KEY PRINCIPLES:|$)'
            print(f"🔍 DEBUG: Using full pattern: {full_step_pattern}")
            full_match = re.search(full_step_pattern, content, re.DOTALL)
            if full_match:
                result = full_match.group(1).strip()
                print(f"✅ DEBUG: Full match found, length: {len(result)} chars")
                print(f"✅ DEBUG: Preview: {result[:150]}...")
                return result
        else:
            print(f"❌ DEBUG: No match found for step {step_number}")
            # Let's see what steps are in the file
            all_steps = re.findall(r'STEP (\d+):', content)
            print(f"📋 DEBUG: Available steps in file: {all_steps}")
        
        return f"Step {step_number} methodology not found in {steps_file}"
    
    def get_detailed_step_instructions(self, phase_name: str, step_number: int, file_path: str) -> str:
        """Get detailed, explicit instructions for each analysis step."""
        
        # Add universal rules for all steps
        universal_rules = """
### CRITICAL RULES FOR ALL ANALYSIS:

1. **NEVER include file extensions in your .md reports**: 
   - Do NOT write things like "the types.ts file" or "src/common/types.ts"
   - Instead write "the types module" or "the common types file"
   - This prevents OCR from blocking your documentation

2. **ONLY analyze the specific file given in this task**:
   - Do NOT examine other files even if they seem related
   - Do NOT look at how this file is used elsewhere
   - Stay focused ONLY on the file specified in the task
   - Save findings about other files for their respective analysis steps

3. **Zen Chat AI Model Instructions**:
   - There is NO limit to prompt length - be as detailed and thorough as needed
   - ONLY have the AI models recommend things that they believe are 110% necessary
   - Recommendations must be absolutely beneficial WITHOUT adding unnecessary complexity
   - Focus on pragmatic simplification that reduces complexity while maintaining functionality

4. **AGENT USAGE FOR SIMPLIFICATION PHASE**:
   - For ALL Bug Detection tasks, use the @zmidi-code-simplifier agent
   - This agent specializes in data-driven simplification and performance analysis
   - It will provide structured reports with measurements and concrete recommendations
"""
        
        if phase_name == "Function Simplification" and step_number == 1:
            return universal_rules + """

### Step 1: Performance Baseline Analysis Using Code Simplification Specialist

**CRITICAL**: Use @zmidi-code-simplifier for this entire analysis.

1. **Invoke the Specialist Agent**:
   ```
   @zmidi-code-simplifier Please analyze potential bugs and performance issues in this file, focusing on:
   - Type complexity and performance implications
   - Memory allocation patterns in hot paths
   - GC pressure from object creation
   - Potential latency impacts on the <20ms budget
   ```

2. **Request Structured Deliverables**:
   - Performance Baseline Report with p50/p95/p99 metrics
   - Type complexity analysis with concrete examples
   - Memory allocation hotspots
   - Recommendations ranked by impact

3. **Additional Multi-AI Analysis** (if needed for deeper insights):
   - Have the agent collaborate with other models via zen tools
   - Focus on concrete measurements, not theoretical concerns
   - Document specific type patterns that impact performance

4. **Expected Output from Agent**:
   - Structured performance baseline report
   - Specific complexity scores
   - Actionable recommendations with measurable impact
   - Clear identification of hot path concerns

**REMEMBER**: The @zmidi-code-simplifier agent specializes in bug detection and issue analysis. Let it lead the investigation with its systematic methodology."""

        elif phase_name == "Function Simplification" and step_number == 2:
            return universal_rules + """

### Step 2: State Management Audit Using Code Simplification Specialist

**CRITICAL**: Use @zmidi-code-simplifier for comprehensive bug analysis.

1. **Invoke the Specialist Agent**:
   ```
   @zmidi-code-simplifier Please investigate potential bugs and issues in this file:
   - Identify all useState/useReducer that should be in Zustand
   - Find component-level state that's actually shared across components
   - Detect any direct MIDI subscriptions violating Single Source of Truth
   - Analyze React reconciliation impact of current state patterns
   ```

2. **Request State Violations Table**:
   The agent will provide a structured table format:
   | Component | Current Pattern | Issue | Zustand Migration | Priority |
   
   Ask for:
   - Migration difficulty assessment (easy/medium/hard)
   - Performance impact quantification (<3ms target)
   - Code examples for each migration

3. **Expected Deliverables**:
   - Complete state violations inventory
   - Migration roadmap with priorities
   - Performance impact measurements
   - Before/after code examples
   - Reconciliation optimization opportunities

**REMEMBER**: The @zmidi-code-simplifier will provide issue analysis and bug detection. Focus on problems that impact the <20ms latency budget."""

        # For all other Simplification steps, use the agent
        if phase_name == "Function Simplification":
            return universal_rules + f"""

### Step {step_number}: Simplification Analysis Using Code Simplification Specialist

**CRITICAL**: Use @zmidi-code-simplifier for all bug detection tasks.

1. **Invoke the Specialist Agent**:
   ```
   @zmidi-code-simplifier Please investigate bugs and issues in this file according to Step {step_number} methodology, focusing on:
   - Performance measurements and baselines
   - Code complexity reduction opportunities
   - Library usage optimization (reinvented wheels)
   - Memory and resource management
   - Developer experience improvements
   ```

2. **Expected Analysis Areas** (based on step requirements):
   - Hot path performance profiling
   - Over-abstraction identification (YAGNI)
   - Memory leak detection
   - Build time optimization
   - Type system simplification

3. **Request Structured Output**:
   - Baseline measurements with p50/p95/p99 metrics
   - Specific recommendations with effort estimates
   - Before/after code examples
   - Complexity reduction scores
   - Implementation roadmap

**REMEMBER**: The @zmidi-code-simplifier provides bug detection and issue analysis. Every finding must be backed by evidence and aligned with the <20ms latency requirement."""

        # For non-Simplification phases, use original approach
        return universal_rules + f"""

### Step {step_number} Analysis

1. **Deep Investigation Required**:
   - Use multiple zen tools for comprehensive analysis
   - Have AIs examine the code from different perspectives
   - Document all findings with specific examples

2. **Multi-Model Analysis**:
   - Each AI should analyze independently first
   - Then share findings and debate
   - Look for consensus and disagreements

3. **Concrete Deliverables**:
   - Specific code examples
   - Quantified impacts where possible
   - Clear recommendations"""

    def get_source_files(self) -> List[str]:
        """Get Zig functions to analyze from extraction manifest."""
        manifest_file = "extracted_functions/function_manifest.json"
        
        try:
            with open(manifest_file, 'r') as f:
                manifest = json.load(f)
                
            # Get function files, excluding test functions
            function_files = [
                f"extracted_functions/{func['function_file']}"
                for func in manifest['functions']
                if func['type'] == 'function'  # Skip test functions
            ]
            
            logger.info(f"Loaded {len(function_files)} functions from manifest")
            return function_files
            
        except FileNotFoundError:
            logger.error(f"Function manifest not found at {manifest_file}")
            logger.error("Please run extract_functions.py first")
            return []
        except json.JSONDecodeError as e:
            logger.error(f"Error parsing manifest: {e}")
            return []

    def update_progress_file(self, state: Dict, files: List[str]):
        """Update detailed progress tracking."""
        content = f"""# ANALYSIS PROGRESS

Started: {state.get('start_time', 'Unknown')}
Updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

"""
        
        # Calculate progress - simplified for one task per file
        total_tasks = len(files)  # One agent analysis per file
        completed = len(state.get("completed_tasks", []))
        progress = (completed / total_tasks * 100) if total_tasks > 0 else 0
        self.current_progress = progress
        
        content += f"## Overall: {progress:.1f}% ({completed}/{total_tasks} files)\n\n"
        
        # Add file status
        content += "## File Status\n\n"
        for file_idx, file in enumerate(files[:20]):  # Show first 20 files
            task_id = f"0-{file_idx}"  # Phase 0, file index
            is_complete = task_id in state.get("completed_tasks", [])
            
            status_icon = "✅" if is_complete else "⬜"
            content += f"{status_icon} {os.path.basename(file)}\n"
        
        if len(files) > 20:
            content += f"\n... and {len(files) - 20} more files\n"
        
        self.write_file_atomic(self.progress_file, content)

    def save_state(self, state: Dict):
        """Save current analysis state to file for crash recovery."""
        try:
            state["last_checkpoint"] = datetime.now().isoformat()
            state["script_version"] = "v2.1"
            with open(self.state_file, 'w', encoding='utf-8') as f:
                json.dump(state, f, indent=2)
            logger.debug(f"Saved state: {len(state.get('completed_tasks', []))} tasks completed")
        except Exception as e:
            logger.error(f"Failed to save state: {e}")
    
    def load_state(self) -> Dict:
        """Load previous analysis state if exists."""
        if os.path.exists(self.state_file):
            try:
                with open(self.state_file, 'r', encoding='utf-8') as f:
                    state = json.load(f)
                logger.info(f"Loaded previous state: {len(state.get('completed_tasks', []))} tasks already completed")
                
                # Ask user if they want to resume
                print(f"\n📂 Found previous session with {len(state.get('completed_tasks', []))} completed tasks")
                print(f"   Last checkpoint: {state.get('last_checkpoint', 'Unknown')}")
                
                if not self.manual_focus:
                    # Auto-resume in automated mode
                    print("   ✅ Auto-resuming from last checkpoint...")
                    return state
                else:
                    # Ask user in manual mode
                    response = input("   Resume from last checkpoint? (y/n): ").lower()
                    if response == 'y':
                        return state
                    else:
                        print("   🆕 Starting fresh analysis...")
                        
            except Exception as e:
                logger.error(f"Failed to load state: {e}")
        
        return {
            "completed_tasks": [],
            "current_phase": 0,
            "start_time": time.time(),
            "last_checkpoint": None
        }

    def run(self):
        """Main execution loop with enhanced features."""
        logger.info("Starting Ideal Autonomous Code Analyzer v2")
        print("🚀 Ideal Autonomous Code Analyzer v2")
        print("=" * 50)
        
        # Setup file watcher
        self.setup_file_watcher()
        
        try:
            # Initialize safety monitoring
            self.source_file_hashes = self.initialize_source_monitoring()
            
            # Create output directories
            for phase in self.analysis_phases:
                os.makedirs(phase["output_dir"], exist_ok=True)
            
            # Load state - this method already handles file existence and resume logic
            state = self.load_state()
            
            # Update start time if new session
            if not state.get("completed_tasks"):
                state["start_time"] = datetime.now().isoformat()
            
            # Get files to analyze
            files = self.get_source_files()
            logger.info(f"Found {len(files)} files to analyze")
            
            # Create initial files
            self.create_rules_file()
            self.update_progress_file(state, files)
            
            # Setup focus
            if self.manual_focus:
                print("\n📍 MANUAL MODE: Click in Console/Terminal window in 10 seconds...")
                time.sleep(10)
            else:
                print("🔄 Will attempt auto-focus...")
                time.sleep(3)
            
            # Initial handshake
            completed_count = len(state.get("completed_tasks", []))
            remaining_count = len(files) - completed_count
            init_msg = f"""Autonomous Zig Function Simplifier starting! (SYSTEMATIC ANALYSIS MODE)

📁 Functions: {len(files)} total ({remaining_count} remaining)
🤖 Agent: @zmidi-code-simplifier ONLY
📄 Communication: {self.sync_file}
⚡ Process: One agent analysis per function

Read {self.rules_file} and update {self.sync_file} with "STATUS: READY" to begin."""
            
            self.type_message(init_msg)
            self.update_sync_file("STATUS: WAITING_FOR_READY")
            
            # Wait for ready
            status = self.wait_for_claude_update()
            if status != "READY":
                logger.error(f"Failed to start: {status}")
                return
            
            # Main processing loop - SIMPLIFIED for single agent per file
            for phase_idx, phase in enumerate(self.analysis_phases):
                for file_idx, file in enumerate(files):
                    task_id = f"{phase_idx}-{file_idx}"
                    
                    # Skip completed
                    if task_id in state["completed_tasks"]:
                        continue
                    
                    # Track file size for dynamic timeout
                    self.current_file_size = os.path.getsize(file)
                    
                    # Track task start time
                    task_start = time.perf_counter()
                    
                    # Update state
                    state["current_phase"] = phase_idx
                    state["current_file"] = file_idx
                    
                    # Save state
                    self.write_file_atomic(self.state_file, json.dumps(state, indent=2))
                    
                    # Update progress
                    self.update_progress_file(state, files)
                    
                    # Check if we need rule reminder
                    self.messages_sent += 1
                    rule_reminder = ""
                    if (self.messages_sent - self.last_rule_reminder_count) >= self.rule_reminder_interval:
                        self.last_rule_reminder_count = self.messages_sent
                        rule_reminder = """

## 🚨 CRITICAL RULE REMINDER (Every 10-15 messages) 🚨

You are communicating with an AUTONOMOUS PYTHON SCRIPT:
- NEVER MODIFY SOURCE CODE - Only create .md documentation
- ONLY CREATE FILES IN analysis_results/ directories
- ALWAYS ACCEPT .md file prompts (press "1" in Claude Code)
- NEVER ACCEPT source code modifications
- Use @zmidi-code-simplifier agent for ALL analysis
"""
                        
                    # Create SIMPLIFIED task - agent only
                    unique_output_name = self.get_unique_output_filename(file)
                    task_content = f"""STATUS: NEW_TASK

## Task: {file} - Code Simplification Analysis

**Function**: `{file}`
**Output**: `{phase['output_dir']}{unique_output_name}`

### 🎯 YOUR SIMPLE MISSION
Read the function. Ask "Why is this complex when it could be simpler?" Test your simpler version. If tests pass, recommend it. If not, say it's fine as is.

### TESTING PROTOCOL
1. Read the extracted function in `{file}`
2. Find the source file mentioned in the function metadata
3. Apply your simplification to the actual function
4. Run `zig build test` to verify changes
5. Document exact test results (pass/fail/error)
6. ALWAYS revert changes after testing

### HONESTY REQUIREMENTS
- **BE BRUTALLY HONEST** - Don't sugarcoat findings
- **NO FABRICATION** - Never make up metrics or test results  
- **STATE LIMITATIONS** - Be clear about what you cannot measure
- **MEANINGFUL CHANGES ONLY** - Minimum 20% complexity reduction to report
- If function is already optimal, say "No simplification needed" and mark STATUS: PASS

⚠️ **CRITICAL OUTPUT REQUIREMENT** ⚠️
You MUST save your analysis to EXACTLY this file:
```
{phase['output_dir']}{unique_output_name}
```
When Claude Code prompts to create this file, ALWAYS press "1" to accept.

{rule_reminder}

## 🚀 AGENT-ONLY ANALYSIS

**You MUST use ONLY the @zmidi-code-simplifier agent for this entire analysis**

1. **Update Status**: Immediately update this file with "STATUS: WORKING"

2. **Invoke the Agent**:
   ```
   @zmidi-code-simplifier Please analyze the function in {file} for simplification opportunities
   
   Focus on:
   - Algorithm complexity reduction
   - Memory allocation optimization
   - Control flow simplification
   - Redundant code elimination
   - Performance improvements
   
   Requirements:
   - 110% confidence through actual testing
   - Maintain 100% MIDI-to-MusicXML accuracy
   - Run tests to verify equivalence
   - Be honest about what cannot be measured
   ```

3. **Document Findings**: The agent MUST create the analysis file at EXACTLY this path:
   ```
   {phase['output_dir']}{unique_output_name}
   ```
   
   CRITICAL: When Claude Code prompts to create this file, ALWAYS press "1" to accept.

4. **Complete**: Update status to "STATUS: COMPLETE"

## CRITICAL RULES:
- Use ONLY @zmidi-code-simplifier agent - no other tools
- NO source code modifications - documentation only
- Quality over speed - take as much time as needed
- Less is more - simplicity is key
- If no improvements needed, that's a success!

Remember: This is a focused agent-only analysis of {os.path.basename(file)}."""
                        
                    # Debug: Show what we're about to send
                    print(f"\n📤 DEBUG: Task content length: {len(task_content)} chars")
                    print(f"📤 DEBUG: Task content preview (first 500 chars):")
                    print("-" * 50)
                    print(task_content[:500])
                    print("-" * 50)
                    
                    self.update_sync_file(task_content)
                    
                    # Notify with explicit instructions
                    msg = f"Task ready: {file} | USE @zmidi-code-simplifier AGENT ONLY | IMMEDIATELY read @SYNC_STATUS.md for full instructions | Function simplification analysis | 110% confidence required | Evidence-based only | Think deeply and analytically"
                    
                    # Store for potential recovery
                    self.last_task_message = msg
                    
                    self.type_message(msg, wait_after=2)
                    
                    # Wait for completion - keep waiting until terminal status
                    while True:
                        status = self.wait_for_claude_update()
                        
                        if status == "EMERGENCY_STOP":
                            logger.critical("Emergency stop triggered!")
                            return
                        
                        elif status in ["COMPLETE", "PASS"]:
                            state["completed_tasks"].append(task_id)
                            task_duration = time.perf_counter() - task_start
                            self.track_task_performance(task_id, task_duration, status)
                            logger.info(f"✅ {task_id}: {status} ({task_duration:.1f}s)")
                            
                            # Save state after each completed task
                            self.save_state(state)
                            self.update_progress_file(state, files)
                            
                            # Clear conversation context for next task (if enabled)
                            if self.auto_clear:
                                self.clear_conversation()
                            
                            break  # Exit waiting loop, proceed to next file
                        
                        elif status.startswith("ERROR"):
                            # Retry logic
                            retry_count = state.get("retry_counts", {}).get(task_id, 0)
                            if retry_count < 2:
                                logger.warning(f"Retrying {task_id} (attempt {retry_count + 1})")
                                state.setdefault("retry_counts", {})[task_id] = retry_count + 1
                                # Don't mark as complete, will retry
                            else:
                                logger.error(f"❌ {task_id}: {status} (max retries exceeded)")
                                state["completed_tasks"].append(task_id)
                                task_duration = time.perf_counter() - task_start
                                self.track_task_performance(task_id, task_duration, status)
                            break
                        
                        elif status.startswith("HELP"):
                            self.type_message("Skip if not applicable to this file.")
                            help_status = self.wait_for_claude_update(timeout_minutes=5)
                            if help_status in ["COMPLETE", "PASS"]:
                                state["completed_tasks"].append(task_id)
                                task_duration = time.perf_counter() - task_start
                                self.track_task_performance(task_id, task_duration, help_status)
                            break
                        
                        elif status == "WORKING":
                            logger.info(f"Task in progress: {task_id}")
                            # Continue waiting
                        
                        elif status == "TIMEOUT":
                            logger.warning(f"Timeout reached, but task still in progress")
                            # Continue waiting but with longer timeout
                            time.sleep(5)
                        
                        else:
                            logger.warning(f"Unknown status '{status}', continuing to wait...")
                            # Continue waiting
                    
                    # Safety check
                    safe, modified = self.verify_no_source_modifications()
                    if not safe:
                        self.emergency_stop(modified)
                        return
                    
                    time.sleep(1)
            
            # Success!
            logger.info("Analysis completed successfully!")
            self.update_sync_file("STATUS: ALL_COMPLETE\n\nAnalysis finished successfully!")
            self.type_message("🎉 All analysis complete! Generating summary...")
            self.update_progress_file(state, files)
            
            # Generate final summary
            self.generate_final_summary()
            
            # Save final metrics
            self.save_metrics()
            
            print("\n" + "="*60)
            print("✅ ANALYSIS COMPLETED SUCCESSFULLY!")
            print("="*60)
            print(f"\n📋 Generated Files:")
            print(f"   • ACTION_REQUIRED.md - Quick list of files needing changes")
            print(f"   • ANALYSIS_SUMMARY.md - Comprehensive analysis summary")
            print(f"   • {self.metrics_file} - Performance metrics")
            print(f"   • analysis_results/ - Detailed analysis for each file")
            print("\n🎯 Next Steps:")
            print("   1. Review ACTION_REQUIRED.md for prioritized changes")
            print("   2. Check individual analysis files for detailed recommendations")
            print("   3. Implement changes starting with HIGH PRIORITY items")
            print("\n" + "="*60)
            
            # Clean exit
            return True
            
        except KeyboardInterrupt:
            print("\n🛑 KeyboardInterrupt caught")
            logger.warning("Interrupted by user")
            self.update_sync_file("STATUS: INTERRUPTED")
        except Exception as e:
            print(f"\n❌ Unexpected error: {e}")
            logger.exception(f"Unexpected error: {e}")
            self.update_sync_file(f"STATUS: ERROR\n\n{str(e)}")
        finally:
            print("🧹 Cleaning up...")
            self.stop_file_watcher()
            if shutdown_requested:
                print("✅ Shutdown completed gracefully")
                print("📋 Check analyzer.log for full details")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Ideal Autonomous Code Analyzer v2")
    parser.add_argument(
        "--manual-focus",
        action="store_true",
        help="Manual focus mode (click in chat yourself)"
    )
    parser.add_argument(
        "--reset", 
        action="store_true", 
        help="Reset all state and progress"
    )
    parser.add_argument(
        "--no-auto-clear",
        action="store_true", 
        help="Disable automatic /clear after each task completion"
    )
    
    args = parser.parse_args()
    
    if args.reset:
        # Close any existing loggers first
        logging.shutdown()
        
        files_to_remove = [
            "analyzer_state.json",
            "analyzer_metrics.json",
            "analyzer.log",
            "SYNC_STATUS.md",
            "ANALYSIS_PROGRESS.md",
            "SIMPLIFICATION_RULES.md",
            "ANALYSIS_SUMMARY.md",
            "EMERGENCY_STOP_LOG.txt"
        ]
        
        for f in files_to_remove:
            if os.path.exists(f):
                try:
                    os.remove(f)
                    print(f"Removed {f}")
                except PermissionError:
                    print(f"⚠️  Could not remove {f} (file in use)")
                except Exception as e:
                    print(f"⚠️  Error removing {f}: {e}")
        
        # Clean up directories
        dirs_to_clean = ["screenshots/", "analysis_results/"]
        for dir_path in dirs_to_clean:
            if os.path.exists(dir_path):
                try:
                    import shutil
                    shutil.rmtree(dir_path)
                    print(f"Removed directory {dir_path}")
                except Exception as e:
                    print(f"⚠️  Could not remove {dir_path}: {e}")
        
        print("✅ Reset complete")
        return
    
    # Check dependencies
    try:
        from watchdog.observers.polling import PollingObserver
        import cv2
        import numpy as np
    except ImportError as e:
        print("❌ Missing required dependencies!")
        if "watchdog" in str(e):
            print("   Install with: pip install watchdog")
        if "cv2" in str(e):
            print("   Install with: pip install opencv-python")
        if "numpy" in str(e):
            print("   Install with: pip install numpy")
        return
    
    # Check OCR dependency (optional but recommended)
    if not pytesseract:
        print("⚠️ pytesseract not installed - OCR prompt detection disabled")
        print("   Install with: pip install pytesseract")
        print("   Also install Tesseract: https://github.com/tesseract-ocr/tesseract")
        print("   Continuing without OCR...")
        time.sleep(3)
    
    required_files = [
        "pragmatic_simplification_tasks_v2.txt",
        "systematic_bug_hunt_v2.txt",
        "feature_planning_deep_dive_v2.txt",
        "analysis_thinking_phrases.py"
    ]
    
    missing = [f for f in required_files if not os.path.exists(f)]
    if missing:
        print("❌ Missing required files:")
        for f in missing:
            print(f"   - {f}")
        return
    
    # Run analyzer
    analyzer = IdealAutonomousAnalyzerV2(
        manual_focus=args.manual_focus,
        auto_clear=not args.no_auto_clear
    )
    analyzer.run()


if __name__ == "__main__":
    main()
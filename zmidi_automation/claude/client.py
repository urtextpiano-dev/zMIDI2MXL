"""
Claude Code interaction client
Handles communication with Claude through console/terminal
"""

import time
import pyautogui
import pyperclip
from typing import Optional, List, Callable, Any
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass
class ClaudeMessage:
    """Represents a message to/from Claude"""

    content: str
    timestamp: datetime
    direction: str  # 'sent' or 'received'
    message_type: str  # 'text', 'command', 'context_refresh'
    metadata: dict = None


class ClaudeClient:
    """Client for interacting with Claude Code through terminal"""

    def __init__(self, config, window_manager=None):
        self.config = config
        self.window_mgr = window_manager
        self.message_history: List[ClaudeMessage] = []
        self.context_usage = 0
        self.messages_sent = 0
        self.last_command_time = 0

        # Typing configuration
        self.typing_delay = 0.03  # Delay between keystrokes
        self.pre_send_delay = 0.02  # Delay before pressing Enter (UI processing time)
        self.command_wait = 3  # Wait after sending command

    def send_message(self, message: str, wait_after: int = 3) -> bool:
        """Send a message to Claude through the terminal WITHOUT requiring focus"""
        try:
            # Check if we can use background sending (Cmder with window manager)
            can_send_background = False
            if self.window_mgr and self.window_mgr.console_handle:
                try:
                    import win32gui

                    window_title = win32gui.GetWindowText(
                        self.window_mgr.console_handle
                    ).lower()
                    can_send_background = any(
                        term in window_title
                        for term in ["cmder", "conemu", "consoleapp"]
                    )
                except:
                    pass

            if can_send_background:
                # Briefly focus, paste, and return (simpler and faster!)
                print("📤 Quick focus to send message...")

                # Save current window
                try:
                    import win32gui

                    previous_window = win32gui.GetForegroundWindow()
                except:
                    previous_window = None

                # Focus Cmder briefly (quick=True skips delays)
                self.window_mgr.focus_console(quick=True)
                time.sleep(0.05)  # Very brief pause for focus

                # Paste and send (pause accept spam while we type)
                lock = Path(".spam_pause.lock")
                try:
                    lock.write_text("1", encoding="utf-8")
                    time.sleep(0.02)

                    self._type_message(message)
                    time.sleep(self.pre_send_delay)
                    pyautogui.press("enter")
                finally:
                    try:
                        lock.unlink(missing_ok=True)
                    except Exception:
                        pass

                # Return focus to previous window

                # Return focus to previous window
                if (
                    previous_window
                    and previous_window != self.window_mgr.console_handle
                ):
                    try:
                        win32gui.SetForegroundWindow(previous_window)
                    except:
                        pass  # Previous window might be gone
            else:
                # Fallback: Original method that requires focus
                if self.window_mgr:
                    self.window_mgr.focus_console()

                # Type the message
                self._type_message(message)

                # Allow UI to process message before sending
                time.sleep(self.pre_send_delay)

                # Press Enter to send
                pyautogui.press("enter")

            # Wait for processing
            time.sleep(wait_after)

            # Track message
            self.messages_sent += 1
            self.message_history.append(
                ClaudeMessage(
                    content=message,
                    timestamp=datetime.now(),
                    direction="sent",
                    message_type=self._classify_message(message),
                )
            )

            return True

        except Exception as e:
            print(f"Error sending message: {e}")
            return False

    def _type_message(self, message: str):
        """Type a message with proper handling of special characters"""
        # Use clipboard for long messages or those with special characters
        if len(message) > 100 or "\n" in message or "`" in message:
            # Copy to clipboard
            pyperclip.copy(message)
            time.sleep(0.2)

            # Paste using Ctrl+V (Windows/Linux) or Cmd+V (Mac)
            pyautogui.hotkey("ctrl", "v")
            time.sleep(0.5)
        else:
            # Type character by character for short messages
            pyautogui.typewrite(message, interval=self.typing_delay)

    def _classify_message(self, message: str) -> str:
        """Classify the type of message"""
        if message.startswith("/"):
            return "command"
        elif "[CONTEXT REFRESH" in message:
            return "context_refresh"
        else:
            return "text"

    def send_command(self, command: str) -> bool:
        """Send a Claude command (e.g., /clear, /compact)"""
        if not command.startswith("/"):
            command = "/" + command

        # Rate limiting for commands
        current_time = time.time()
        if current_time - self.last_command_time < 2:
            time.sleep(2 - (current_time - self.last_command_time))

        result = self.send_message(command, wait_after=5)
        self.last_command_time = time.time()

        # Handle specific commands
        if command == "/clear":
            self.context_usage = 0
            print("✅ Context cleared")
        elif command == "/compact":
            self.context_usage = max(0, self.context_usage - 50)
            print("✅ Context compacted")

        return result

    def handle_context_warning(self, usage_percentage: int):
        """Handle context usage warnings"""
        self.context_usage = usage_percentage

        if usage_percentage >= self.config.claude.emergency_threshold:
            print(f"🚨 EMERGENCY: Context at {usage_percentage}%")
            return self.send_command("/clear")
        elif usage_percentage >= self.config.claude.compact_threshold:
            print(f"⚠️ High context: {usage_percentage}%")
            return self.send_command("/compact")

        return True

    def send_context_refresh(self, task_info: str = None) -> bool:
        """Send a context refresh message"""
        refresh_num = (
            len(
                [m for m in self.message_history if m.message_type == "context_refresh"]
            )
            + 1
        )

        message = f"""[CONTEXT REFRESH #{refresh_num * 10}]

 CRITICAL IDENTITY REMINDER:
You are communicating with autonomous_analyzer_ideal_v2.py - an automated Python script for systematic code analysis.

 CURRENT STATUS: WORKING

"""

        if task_info:
            message += f""" CURRENT TASK:
{task_info}

"""

        message += """ CRITICAL SAFETY RULES:
1. NEVER MODIFY SOURCE CODE - Not even to fix bugs you find!
2. ONLY CREATE .md FILES - Documentation only  
3. ONLY IN analysis_results/ directories
4. NO OTHER FILE OPERATIONS - No deletes, renames, etc.
5. CLAUDE CODE FILE PROMPTS - ALWAYS press "1" to accept .md files in analysis_results/ only

 SIMPLIFIED PROCESS - ONE AGENT PER FILE:
- Use ONLY @zmidi-code-simplifier agent for entire analysis
- NO other tools needed - the agent handles everything
- One comprehensive analysis per file
- Agent will only recommend 110% necessary improvements
- Focus on simplicity - less is more

 COMMUNICATION PROTOCOL:
Update SYNC_STATUS.md with EXACTLY one of these:
- STATUS: READY - Initial handshake complete
- STATUS: WORKING - Started analysis  
- STATUS: COMPLETE - Finished (with or without findings)
- STATUS: PASS - Skip this file/step
- STATUS: ERROR: [message] - Problem occurred
- STATUS: HELP: [question] - Need clarification

 NEXT ACTION REQUIRED:
Please continue with the current task as outlined in SYNC_STATUS.md. Use @zmidi-code-simplifier agent for analysis.

Quality over speed - take as much time as needed for thorough analysis."""

        return self.send_message(message, wait_after=2)

    def retry_with_backoff(
        self, func: Callable, max_attempts: int = 3, *args, **kwargs
    ) -> Optional[Any]:
        """Retry a function with exponential backoff"""
        for attempt in range(max_attempts):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                if attempt == max_attempts - 1:
                    print(f"Failed after {max_attempts} attempts: {e}")
                    return None

                wait_time = self.config.claude.retry_delay * (2**attempt)
                print(f"Attempt {attempt + 1} failed, retrying in {wait_time}s...")
                time.sleep(wait_time)

        return None

    def get_message_stats(self) -> dict:
        """Get statistics about messages sent"""
        return {
            "total_messages": len(self.message_history),
            "messages_sent": self.messages_sent,
            "commands_sent": len(
                [m for m in self.message_history if m.message_type == "command"]
            ),
            "context_refreshes": len(
                [m for m in self.message_history if m.message_type == "context_refresh"]
            ),
            "context_usage": self.context_usage,
            "last_message": (
                self.message_history[-1].timestamp if self.message_history else None
            ),
        }

    def should_send_rule_reminder(self, interval: int = 10) -> bool:
        """Check if it's time to send a rule reminder"""
        return self.messages_sent > 0 and self.messages_sent % interval == 0

    def get_rule_reminder(self) -> str:
        """Get the rule reminder text"""
        return """
## 🚨 CRITICAL RULE REMINDER 🚨

You are communicating with an AUTONOMOUS PYTHON SCRIPT:
- NEVER MODIFY SOURCE CODE - Only create .md documentation
- ONLY CREATE FILES IN analysis_results/ directories
- ALWAYS ACCEPT .md file prompts (press "1" in Claude Code)
- NEVER ACCEPT source code modifications
- Use @zmidi-code-simplifier agent for ALL analysis
"""

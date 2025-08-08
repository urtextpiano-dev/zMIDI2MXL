"""
Sync file management for coordinating with Claude Code
Handles SYNC_STATUS.md updates with atomic writes and file watching
"""

import os
import time
import hashlib
import tempfile
import shutil
from pathlib import Path
from typing import Optional, Callable, Dict, Any
from dataclasses import dataclass
from datetime import datetime
from threading import Lock, Thread
from queue import Queue, Empty
import re

# Optional dependency - file watching
try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler, FileModifiedEvent

    WATCHDOG_AVAILABLE = True
except ImportError:
    WATCHDOG_AVAILABLE = False

    # Create dummy classes so code doesn't break
    class FileSystemEventHandler:
        pass

    class FileModifiedEvent:
        pass

    class Observer:
        pass


@dataclass
class SyncStatus:
    """Represents the current sync status"""

    status: str
    task: Optional[str] = None
    timestamp: Optional[datetime] = None
    metadata: Dict[str, Any] = None

    def to_markdown(self) -> str:
        """Convert to markdown format for SYNC_STATUS.md"""
        lines = ["# SYNC STATUS", "", f"STATUS: {self.status}"]

        if self.task:
            lines.append("")
            lines.append(f"## Task: {self.task}")

        if self.metadata:
            lines.append("")
            for key, value in self.metadata.items():
                lines.append(f"**{key}**: {value}")

        if self.timestamp:
            lines.append("")
            lines.append(
                f"Last updated: {self.timestamp.strftime('%Y-%m-%d %H:%M:%S')}"
            )

        return "\n".join(lines)

    @classmethod
    def from_markdown(cls, content: str) -> "SyncStatus":
        """Parse from markdown content (robust + normalized)"""
        # STATUS: allow any case/spacing; capture ONLY the first word (e.g., ERROR from "ERROR: msg")
        m = re.search(r"(?mi)^\s*status\s*:\s*([A-Za-z_]+)", content)
        status = m.group(1).upper() if m else "UNKNOWN"

        # Task: tolerate case/spacing too (optional but harmless)
        m_task = re.search(r"(?mi)^\s*##\s*task\s*:\s*(.+)$", content)
        task = m_task.group(1).strip() if m_task else None

        # Metadata (leave as-is)
        metadata = {}
        for line in content.split("\n"):
            line = line.strip()
            if line.startswith("**") and "**:" in line:
                parts = line.split("**:", 1)
                if len(parts) == 2:
                    key = parts[0].strip("*").strip()
                    value = parts[1].strip()
                    metadata[key] = value

        return cls(status=status, task=task, metadata=metadata or None)


class SyncFileWatcher(FileSystemEventHandler):
    """Watches SYNC_STATUS.md for changes"""

    def __init__(self, file_path: Path, callback: Callable[[str], None]):
        self.file_path = file_path
        self.callback = callback
        self.last_hash = self._get_file_hash()
        self._lock = Lock()

    def _get_file_hash(self) -> str:
        """Get hash of file contents"""
        try:
            return hashlib.md5(self.file_path.read_bytes()).hexdigest()
        except (FileNotFoundError, PermissionError, OSError):
            # Handle permission errors gracefully
            return ""

    def on_modified(self, event):
        """Handle file modification events"""
        if not isinstance(event, FileModifiedEvent):
            return

        if Path(event.src_path) != self.file_path:
            return

        with self._lock:
            current_hash = self._get_file_hash()
            if current_hash != self.last_hash:
                self.last_hash = current_hash
                try:
                    content = self.file_path.read_text(encoding="utf-8")
                    self.callback(content)
                except (PermissionError, OSError):
                    # Silently ignore permission errors during file watching
                    pass
                except Exception as e:
                    print(f"Error reading sync file: {e}")


class SyncManager:
    """Manages synchronization with Claude Code via SYNC_STATUS.md"""

    def __init__(
        self,
        sync_file: str = "SYNC_STATUS.md",
        watch: bool = False,
        atomic_write: bool = True,
    ):
        self.sync_file = Path(sync_file)
        self.atomic_write = atomic_write
        self.watch = watch
        self._observer: Optional[Observer] = None
        self._watcher: Optional[SyncFileWatcher] = None
        self._update_callbacks: list[Callable[[SyncStatus], None]] = []
        self._lock = Lock()

        # Create sync file if it doesn't exist
        if not self.sync_file.exists():
            self.update_status("READY")

    def start_watching(self, callback: Optional[Callable[[SyncStatus], None]] = None):
        """Start watching the sync file for changes"""
        if not WATCHDOG_AVAILABLE:
            print("Warning: watchdog not installed. File watching disabled.")
            print("Install with: pip install watchdog")
            return

        if callback:
            self._update_callbacks.append(callback)

        if self._observer is None:
            self._watcher = SyncFileWatcher(self.sync_file, self._on_file_changed)
            self._observer = Observer()
            self._observer.schedule(
                self._watcher, str(self.sync_file.parent), recursive=False
            )
            self._observer.start()

    def stop_watching(self):
        """Stop watching the sync file"""
        if self._observer:
            self._observer.stop()
            self._observer.join(timeout=2)
            self._observer = None
            self._watcher = None

    def _on_file_changed(self, content: str):
        """Handle sync file changes"""
        try:
            status = SyncStatus.from_markdown(content)
            for callback in self._update_callbacks:
                callback(status)
        except Exception as e:
            print(f"Error processing sync file change: {e}")

    def update_status(
        self,
        status: str,
        task: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ):
        """Update the sync status"""
        sync_status = SyncStatus(
            status=status, task=task, timestamp=datetime.now(), metadata=metadata
        )

        content = sync_status.to_markdown()
        self._write_file(content)

    def update(self, content: str):
        """Update sync file with raw content"""
        self._write_file(content)

    def _write_file(self, content: str):
        """Write to file, optionally using atomic write"""
        with self._lock:
            if self.atomic_write:
                # Write to temp file first, then rename
                temp_file = None
                try:
                    with tempfile.NamedTemporaryFile(
                        mode="w",
                        encoding="utf-8",
                        dir=self.sync_file.parent,
                        delete=False,
                        suffix=".tmp",
                    ) as temp_file:
                        temp_file.write(content)
                        temp_file.flush()
                        os.fsync(temp_file.fileno())

                    # Atomic rename
                    shutil.move(temp_file.name, str(self.sync_file))

                except Exception as e:
                    # Clean up temp file if something went wrong
                    if temp_file and os.path.exists(temp_file.name):
                        os.unlink(temp_file.name)
                    raise e
            else:
                # Regular write
                self.sync_file.write_text(content, encoding="utf-8")

    def read_status(self) -> SyncStatus:
        """Read current sync status with retry for partial reads"""
        for attempt in range(3):  # Try up to 3 times
            try:
                content = self.sync_file.read_text(encoding="utf-8")
                status = SyncStatus.from_markdown(content)

                # If we got UNKNOWN and file exists, might be partial read
                if status.status == "UNKNOWN" and self.sync_file.exists():
                    if attempt < 2:  # Don't sleep on last attempt
                        time.sleep(0.1)  # Brief pause before retry
                        continue

                return status

            except FileNotFoundError:
                return SyncStatus(status="NOT_FOUND")
            except (OSError, PermissionError) as e:
                # File might be locked for writing, retry
                if attempt < 2:
                    time.sleep(0.1)
                    continue
                # Final attempt failed
                return SyncStatus(status="UNKNOWN")

        # All retries exhausted
        return SyncStatus(status="UNKNOWN")

    def wait_for_status(self, target_status: str, timeout: int = 300) -> bool:
        """Wait for a specific status, with timeout"""
        start_time = time.time()

        while time.time() - start_time < timeout:
            current = self.read_status()
            if current.status == target_status:
                return True
            time.sleep(0.5)

        return False

    def wait_for_claude_response(self, timeout_minutes: int = 5) -> Optional[str]:
        """Wait for Claude to update the sync file"""
        timeout = timeout_minutes * 60
        start_time = time.time()
        initial_status = self.read_status()

        print(f"Waiting for Claude response (timeout: {timeout_minutes} minutes)...")

        while time.time() - start_time < timeout:
            current_status = self.read_status()

            # Check if status changed
            if current_status.status != initial_status.status:
                return current_status.status

            # Check for specific statuses that indicate Claude responded
            if current_status.status in ["COMPLETE", "ERROR", "HELP", "PASS"]:
                return current_status.status

            time.sleep(0.5)

        print(f"Timeout waiting for Claude response after {timeout_minutes} minutes")
        return None

    def clear(self):
        """Clear the sync file to minimal state"""
        self.update_status("READY")

    def __enter__(self):
        """Context manager entry"""
        if self.watch:
            self.start_watching()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        if self.watch:
            self.stop_watching()

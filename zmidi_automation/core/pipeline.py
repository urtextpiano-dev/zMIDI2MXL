"""
Complete pipeline orchestration for ZMIDI automation
Coordinates all modules to execute the full analysis workflow
"""

import os
import json
import time
import hashlib
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, field, asdict
from datetime import datetime
from enum import Enum
from abc import ABC, abstractmethod


class TaskStatus(Enum):
    """Status of a task in the pipeline"""
    PENDING = "PENDING"
    WAITING_FOR_READY = "WAITING_FOR_READY"
    NEW_TASK = "NEW_TASK"
    WORKING = "WORKING"
    COMPLETE = "COMPLETE"
    PASS = "PASS"
    ERROR = "ERROR"
    HELP = "HELP"
    TIMEOUT = "TIMEOUT"


@dataclass
class Task:
    """Represents a single analysis task"""
    id: str
    file_path: str
    phase: str
    output_path: str
    status: TaskStatus = TaskStatus.PENDING
    start_time: Optional[float] = None
    end_time: Optional[float] = None
    error: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def duration(self) -> float:
        """Calculate task duration in seconds"""
        if self.start_time and self.end_time:
            return self.end_time - self.start_time
        return 0.0
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            'id': self.id,
            'file_path': self.file_path,
            'phase': self.phase,
            'output_path': self.output_path,
            'status': self.status.value,
            'start_time': self.start_time,
            'end_time': self.end_time,
            'error': self.error,
            'metadata': self.metadata
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Task':
        """Create from dictionary"""
        data['status'] = TaskStatus(data['status'])
        return cls(**data)


@dataclass
class PipelineState:
    """Tracks the state of the entire pipeline"""
    tasks: List[Task] = field(default_factory=list)
    completed_task_ids: List[str] = field(default_factory=list)
    current_task: Optional[Task] = None
    start_time: Optional[datetime] = None
    last_checkpoint: Optional[datetime] = None
    context_usage: int = 0
    messages_sent: int = 0
    source_file_hashes: Dict[str, str] = field(default_factory=dict)
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            'tasks': [t.to_dict() for t in self.tasks],
            'completed_task_ids': self.completed_task_ids,
            'current_task': self.current_task.to_dict() if self.current_task else None,
            'start_time': self.start_time.isoformat() if self.start_time else None,
            'last_checkpoint': self.last_checkpoint.isoformat() if self.last_checkpoint else None,
            'context_usage': self.context_usage,
            'messages_sent': self.messages_sent,
            'source_file_hashes': self.source_file_hashes,
            'metadata': self.metadata
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'PipelineState':
        """Create from dictionary"""
        if data.get('tasks'):
            data['tasks'] = [Task.from_dict(t) for t in data['tasks']]
        if data.get('current_task'):
            data['current_task'] = Task.from_dict(data['current_task'])
        if data.get('start_time'):
            data['start_time'] = datetime.fromisoformat(data['start_time'])
        if data.get('last_checkpoint'):
            data['last_checkpoint'] = datetime.fromisoformat(data['last_checkpoint'])
        return cls(**data)
    
    def get_progress(self) -> Dict[str, Any]:
        """Calculate progress statistics"""
        total = len(self.tasks)
        completed = len(self.completed_task_ids)
        pending = total - completed
        
        return {
            'total_tasks': total,
            'completed': completed,
            'pending': pending,
            'percentage': (completed / total * 100) if total > 0 else 0,
            'current_task': self.current_task.id if self.current_task else None
        }


class TaskProcessor(ABC):
    """Abstract base class for task processors"""
    
    @abstractmethod
    def process(self, task: Task, state: PipelineState) -> TaskStatus:
        """Process a task and return its final status"""
        pass
    
    @abstractmethod
    def can_process(self, task: Task) -> bool:
        """Check if this processor can handle the task"""
        pass


class SimplificationTaskProcessor(TaskProcessor):
    """Processes function simplification tasks"""
    
    def __init__(self, sync_manager, claude_client, ui_automation, config):
        self.sync = sync_manager
        self.claude = claude_client
        self.ui = ui_automation
        self.config = config
    
    def can_process(self, task: Task) -> bool:
        """Check if this is a simplification task"""
        return task.phase == "simplification"
    
    def process(self, task: Task, state: PipelineState) -> TaskStatus:
        """Process a simplification task"""
        # Generate task content
        task_content = self._generate_task_content(task, state)
        
        # Update sync file with new task
        self.sync.update(task_content)
        
        # Send message to Claude
        msg = self._generate_claude_message(task)
        self.claude.send_message(msg)
        
        # Track messages and estimate context usage
        state.messages_sent += 1
        state.context_usage = min(100, state.messages_sent * 5)
        
        # Wait for Claude response while monitoring for prompts
        status = self._wait_with_monitoring(task, self.config.claude.timeout_minutes)
        
        # Map response to TaskStatus
        if status == "COMPLETE":
            return TaskStatus.COMPLETE
        elif status == "PASS":
            return TaskStatus.PASS
        elif status == "ERROR":
            return TaskStatus.ERROR
        elif status == "HELP":
            return TaskStatus.HELP
        elif status == "TIMEOUT":
            return TaskStatus.TIMEOUT
        else:
            return TaskStatus.ERROR
    
    def _generate_task_content(self, task: Task, state: PipelineState) -> str:
        """Generate the sync file content for a task"""
        from zmidi_automation.utils import to_windows_path
        
        # Convert paths to Windows format for Claude
        task_file_windows = to_windows_path(task.file_path)
        output_path_windows = to_windows_path(task.output_path)
        
        # Include rule reminders periodically
        rule_reminder = ""
        if state.messages_sent % 10 == 0:
            rule_reminder = self._get_rule_reminder()
        
        content = f"""STATUS: NEW_TASK

## Task: {task_file_windows} - Code Simplification Analysis

**Function**: `{task_file_windows}`
**Output**: `{output_path_windows}`

### 🎯 YOUR SIMPLE MISSION
Read the function. Ask "Why is this complex when it could be simpler?" Test your simpler version. If tests pass, recommend it. If not, say it's fine as is.

### ✅ PROVEN ISOLATED TESTING PROTOCOL
**BREAKTHROUGH**: Isolated testing methodology eliminates build failures and produces real evidence instead of estimates.

1. **Create isolated test environment** in `/isolated_function_tests/FUNCTION_NAME_test/`
2. **Extract function + dependencies** using grep to find required structs/types  
3. **Create comprehensive test cases** with realistic data in `test_runner.zig`
4. **Get baseline metrics**: `cmd.exe /c "zig build run"`, `cmd.exe /c "zig build test"`, `wc -l`, `time zig build`
5. **Apply simplifications** directly in isolated environment  
6. **Verify identical output** for all test cases
7. **Document real metrics** - no estimates allowed
8. **Clean up** test directory after analysis

### HONESTY REQUIREMENTS
- **BE BRUTALLY HONEST** - Don't sugarcoat findings
- **NO FABRICATION** - Never make up metrics or test results  
- **STATE LIMITATIONS** - Be clear about what you cannot measure
- **MEANINGFUL CHANGES ONLY** - Minimum 20% complexity reduction to report
- If function is already optimal, say "No simplification needed" and mark STATUS: PASS

⚠️ **CRITICAL OUTPUT REQUIREMENT** ⚠️
You MUST save your analysis to EXACTLY this file:
```
{output_path_windows}
```
When Claude Code prompts to create this file, ALWAYS press "1" to accept.

{rule_reminder}

## 🚀 AGENT-ONLY ANALYSIS

**You MUST use ONLY the @zmidi-code-simplifier agent for this entire analysis**

1. **Update Status**: Immediately update this file with "STATUS: WORKING"

2. **Invoke the Agent with Proven Templates**:
   ```
   @zmidi-code-simplifier Please analyze the function in {task_file_windows} using isolated testing methodology
   
   MANDATORY Templates:
   - Use @isolated_function_tests/task_breakdown_template.md for TodoWrite tasks
   - Use @isolated_function_tests/function_analysis_template.md for documentation  
   - Reference @isolated_function_tests/countEnabled_analysis_results.md (simple function example)
   - Reference @isolated_function_tests/calculateBeatLength_analysis_results.md (complex function example)
   
   Focus on proven patterns:
   - Arithmetic over branching (@intFromBool vs manual counting)
   - Early return over collection (eliminate ArrayList where possible)
   - Switch statements over cascading if statements
   - Memory allocation elimination
   
   Requirements:
   - 110% confidence through isolated testing (NOT main project build)
   - Maintain 100% MIDI-to-MusicXML accuracy
   - Real evidence through isolated test environments
   - Document exact before/after metrics, no estimates
   ```

3. **Document Findings**: The agent MUST create the analysis file at EXACTLY this path:
   ```
   {output_path_windows}
   ```
   
   CRITICAL: When Claude Code prompts to create this file, ALWAYS press "1" to accept.

4. **Complete**: Update status to "STATUS: COMPLETE"

## ✅ REAL RESULTS ACHIEVED WITH THIS METHODOLOGY:
- **countEnabled** (6 lines): 33% line reduction, 7% faster compilation, 100% functional equivalence
- **calculateBeatLength** (27 lines): 22% line reduction, eliminated O(n) allocation, 100% functional equivalence

## CRITICAL RULES:
- Use ONLY @zmidi-code-simplifier agent - no other tools
- NO source code modifications - documentation only  
- Use isolated testing methodology - NOT main project build
- Quality over speed - take as much time as needed
- Less is more - simplicity is key
- If no improvements needed, that's a success!

Remember: This is a focused agent-only analysis of {os.path.basename(task_file_windows)}.

Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"""
        
        return content
    
    def _generate_claude_message(self, task: Task) -> str:
        """Generate the message to send to Claude"""
        from zmidi_automation.utils import to_windows_path
        task_file_windows = to_windows_path(task.file_path)
        return (f"Task ready: {task_file_windows} | "
                f"USE @zmidi-code-simplifier AGENT ONLY | "
                f"IMMEDIATELY read @SYNC_STATUS.md for full instructions | "
                f"Use @isolated_function_tests/task_breakdown_template.md for TodoWrite tasks | "
                f"Use @isolated_function_tests/function_analysis_template.md for documentation | "
                f"Reference @isolated_function_tests/countEnabled_analysis_results.md for simple function example | "
                f"Reference @isolated_function_tests/calculateBeatLength_analysis_results.md for complex function example | "
                f"Function simplification analysis | "
                f"110% confidence required | "
                f"Evidence-based only | "
                f"Think deeply and analytically")
    
    def _wait_with_monitoring(self, task: Task, timeout_minutes: int) -> str:
        """Wait for Claude response"""
        import time
        start_time = time.time()
        timeout_seconds = timeout_minutes * 60
        
        while time.time() - start_time < timeout_seconds:
            # Check for sync file updates
            status = self.sync.read_status()
            if status.status in ["COMPLETE", "PASS", "ERROR", "HELP"]:
                return status.status
            
            # Small delay to avoid busy waiting
            time.sleep(0.5)
        
        # Timeout reached
        print(f"⏱️ Timeout after {timeout_minutes} minutes")
        return "TIMEOUT"
    
    
    def _get_rule_reminder(self) -> str:
        """Get the rule reminder text"""
        return """

## 🚨 CRITICAL RULE REMINDER (Every 10-15 messages) 🚨

You are communicating with an AUTONOMOUS PYTHON SCRIPT:
- NEVER MODIFY SOURCE CODE - Only create .md documentation
- ONLY CREATE FILES IN analysis_results/ directories
- ALWAYS ACCEPT .md file prompts (press "1" in Claude Code)
- NEVER ACCEPT source code modifications
- Use @zmidi-code-simplifier agent for ALL analysis
"""


class Pipeline:
    """Main pipeline orchestrator"""
    
    def __init__(self, config, sync_manager, claude_client, 
                 ui_automation, state_manager, progress_tracker):
        self.config = config
        self.sync = sync_manager
        self.claude = claude_client
        self.ui = ui_automation
        self.state_mgr = state_manager
        self.progress = progress_tracker
        
        # Task processors
        self.processors: List[TaskProcessor] = [
            SimplificationTaskProcessor(sync_manager, claude_client, ui_automation, config)
        ]
        
        # Pipeline state
        self.state = PipelineState()
    
    def initialize(self) -> bool:
        """Initialize the pipeline"""
        # Load saved state if exists
        saved_state = self.state_mgr.load()
        if saved_state:
            self.state = saved_state
            print(f"Resumed from checkpoint: {len(self.state.completed_task_ids)} tasks completed")
        else:
            self.state.start_time = datetime.now()
        
        # Initialize source monitoring
        self.state.source_file_hashes = self._hash_source_files()
        
        # Create output directories
        os.makedirs(self.config.analysis.output_dir, exist_ok=True)
        os.makedirs(self.config.analysis.simplification_dir, exist_ok=True)
        
        # Initial handshake with Claude
        return self._initial_handshake()
    
    def _initial_handshake(self) -> bool:
        """Perform initial handshake with Claude"""
        # Send initial message
        init_msg = self._generate_init_message()
        self.claude.send_message(init_msg)
        
        # Set status to waiting and wait for Claude to update to READY
        self.sync.update_status("WAITING_FOR_READY")
        
        # Wait for Claude to update status to READY
        import time
        timeout = 60  # Wait up to 60 seconds for handshake
        start_time = time.time()
        
        print("⏳ Waiting for Claude to respond with STATUS: READY...")
        while time.time() - start_time < timeout:
            status = self.sync.read_status()
            if status.status == "READY":
                print("✅ Claude responded with READY - handshake complete")
                return True
            elif status.status in ["ERROR", "HELP"]:
                print(f"⚠️ Claude responded with {status.status} - continuing without handshake")
                return True  # Continue execution even if handshake fails
            time.sleep(1)  # Check every second
        
        print("⏱️ Timeout waiting for Claude to respond with READY - continuing anyway")
        return True  # Continue even if handshake times out
    
    def _generate_init_message(self) -> str:
        """Generate initialization message"""
        progress = self.state.get_progress()
        return f"""Autonomous Zig Function Simplifier starting! (SYSTEMATIC ANALYSIS MODE)

📁 Functions: {progress['total_tasks']} total ({progress['pending']} remaining)
🤖 Agent: @zmidi-code-simplifier ONLY
📄 Communication: {self.config.sync.sync_file}
⚡ Process: One agent analysis per function

Read {self.config.project_root}/ANALYSIS_RULES.md and update {self.config.sync.sync_file} with "STATUS: READY" to begin."""
    
    def _hash_source_files(self) -> Dict[str, str]:
        """Hash all source files for change detection"""
        hashes = {}
        for file in Path(self.config.project_root).glob("**/*.zig"):
            if "zig-cache" not in str(file):
                hashes[str(file)] = hashlib.md5(file.read_bytes()).hexdigest()
        return hashes
    
    def load_tasks(self, files: List[str]) -> List[Task]:
        """Load tasks from extracted function files"""
        from zmidi_automation.utils import normalize_path
        
        # Generate session prefix from start time for unique task IDs across sessions
        session_prefix = ""
        if self.state.start_time:
            session_prefix = f"s{self.state.start_time.strftime('%m%d-%H%M')}-"
        
        tasks = []
        for idx, file_path in enumerate(files):
            # Normalize path to WSL format for internal consistency
            normalized_path = normalize_path(file_path)
            
            # Generate unique output filename
            base_name = normalized_path.stem
            output_name = f"{base_name}.md"
            output_path = Path(self.config.analysis.simplification_dir) / output_name
            
            task = Task(
                id=f"{session_prefix}{base_name}",  # Session-unique ID (e.g., "s0807-1430-0001_build_build")
                file_path=str(normalized_path),  # Store as WSL path
                phase="simplification",
                output_path=str(output_path)  # Also WSL path
            )
            
            # Skip if already completed (check both ID and file content)
            completion_key = self._get_completion_key(task)
            if completion_key not in self.state.completed_task_ids:
                tasks.append(task)
        
        return tasks
    
    def _get_completion_key(self, task: Task) -> str:
        """Generate completion key including file content hash"""
        try:
            file_hash = hashlib.md5(Path(task.file_path).read_bytes()).hexdigest()[:8]
            return f"{task.id}:{file_hash}"
        except (FileNotFoundError, OSError):
            # File doesn't exist or can't be read, use ID only
            return task.id
    
    def execute(self, tasks: List[Task]) -> bool:
        """Execute the pipeline with given tasks"""
        self.state.tasks = tasks
                # ---- START OVERRIDE ----
        start_idx = 0
        if hasattr(self, "start_override") and self.start_override is not None:
            s = str(self.start_override).strip()
            if s.isdigit():
                start_idx = max(0, min(int(s), len(tasks)))
            else:
                for i, t in enumerate(tasks):
                    tid = getattr(t, "id", None) or getattr(t, "uid", None)
                    if not tid and hasattr(t, "to_dict"):
                        d = t.to_dict() or {}
                        tid = d.get("id")
                    if tid == s:
                        start_idx = i
                        break
        # ---- END OVERRIDE ----

        for task in tasks[start_idx:]:
            # Check for source modifications
            modified_files = self._check_and_handle_modifications()
            if modified_files:
                print(f"⚠️ Source files modified before task {task.id}: {', '.join(modified_files)}")
                if self._attempt_auto_revert(modified_files):
                    print("✅ Auto-reverted changes, continuing processing")
                else:
                    print("⚠️ Could not auto-revert, logging for manual review")
                    self._log_modifications(modified_files, task.id, "before_task")
            
            # Process task
            self.state.current_task = task
            task.start_time = time.time()
            
            # Find appropriate processor
            processor = self._get_processor(task)
            if not processor:
                print(f"No processor for task: {task.id}")
                task.status = TaskStatus.ERROR
                continue
            
            # Process the task
            try:
                status = processor.process(task, self.state)
                task.status = status
                task.end_time = time.time()
                
                # Check source integrity AFTER task completion (TOCTOU fix)
                modified_files = self._check_and_handle_modifications()
                if modified_files:
                    print(f"⚠️ Source files modified during task {task.id} processing!")
                    if self._attempt_auto_revert(modified_files):
                        print("✅ Auto-reverted changes")
                    else:
                        print("⚠️ Could not auto-revert, task results may be based on outdated code")
                        self._log_modifications(modified_files, task.id, "during_task")
                
                # Update state
                if status in [TaskStatus.COMPLETE, TaskStatus.PASS]:
                    completion_key = self._get_completion_key(task)
                    self.state.completed_task_ids.append(completion_key)
                
                # Track metrics
                self.progress.track_task(task)
                
                # Save checkpoint
                self.state.last_checkpoint = datetime.now()
                self.state_mgr.save(self.state)
                
                # Update progress display
                self.progress.update_display(self.state)
                
                # Clear context AFTER task completes if we've hit the threshold
                if self.state.context_usage >= 95 and status in [TaskStatus.COMPLETE, TaskStatus.PASS]:
                    print("📋 Clearing context after task completion (reached 95% usage)")
                    self.claude.send_message("/clear")
                    self.state.context_usage = 0
                    self.state.messages_sent = 0
                
            except Exception as e:
                print(f"Error processing task {task.id}: {e}")
                task.status = TaskStatus.ERROR
                task.error = str(e)
                task.end_time = time.time()
        
        return True
    
    def _get_processor(self, task: Task) -> Optional[TaskProcessor]:
        """Get the appropriate processor for a task"""
        for processor in self.processors:
            if processor.can_process(task):
                return processor
        return None
    
    def _verify_source_integrity(self) -> bool:
        """Verify source files haven't been modified"""
        current_hashes = self._hash_source_files()
        for file, original_hash in self.state.source_file_hashes.items():
            if file in current_hashes and current_hashes[file] != original_hash:
                print(f"⚠️ Source file modified: {file}")
                return False
        return True
    
    def _check_and_handle_modifications(self) -> List[str]:
        """Check for source modifications and return list of modified files"""
        modified_files = []
        current_hashes = self._hash_source_files()
        for file, original_hash in self.state.source_file_hashes.items():
            if file in current_hashes and current_hashes[file] != original_hash:
                modified_files.append(file)
        return modified_files
    
    def _attempt_auto_revert(self, modified_files: List[str]) -> bool:
        """Attempt to auto-revert modified files using git"""
        import subprocess
        success = True
        
        for file in modified_files:
            try:
                # Convert WSL path to Windows path for git
                windows_path = file.replace('/mnt/e/', 'E:/')
                result = subprocess.run(['git', 'checkout', 'HEAD', windows_path], 
                                       cwd=self.config.project_root,
                                       capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"   Failed to revert {file}: {result.stderr.strip()}")
                    success = False
            except Exception as e:
                print(f"   Error reverting {file}: {e}")
                success = False
        
        # Update hashes if revert was successful
        if success:
            self.state.source_file_hashes = self._hash_source_files()
        
        return success
    
    def _log_modifications(self, modified_files: List[str], task_id: str, phase: str):
        """Log modifications for final reporting"""
        if not hasattr(self, 'modification_log'):
            self.modification_log = []
        
        self.modification_log.append({
            'files': modified_files,
            'task_id': task_id, 
            'phase': phase,
            'timestamp': datetime.now()
        })
    
    
    def generate_summary(self) -> str:
        """Generate final summary of the pipeline execution"""
        progress = self.state.get_progress()
        
        completed_tasks = [t for t in self.state.tasks if t.status == TaskStatus.COMPLETE]
        passed_tasks = [t for t in self.state.tasks if t.status == TaskStatus.PASS]
        error_tasks = [t for t in self.state.tasks if t.status == TaskStatus.ERROR]
        timeout_tasks = [t for t in self.state.tasks if t.status == TaskStatus.TIMEOUT]
        
        total_duration = sum(t.duration() for t in self.state.tasks)
        
        summary = f"""
# Pipeline Execution Summary

## Overall Progress
- Total Tasks: {progress['total_tasks']}
- Completed: {len(completed_tasks)} (simplifications found)
- Passed: {len(passed_tasks)} (already optimal)
- Errors: {len(error_tasks)}
- Timeouts: {len(timeout_tasks)}
- Success Rate: {(len(completed_tasks) + len(passed_tasks)) / progress['total_tasks'] * 100:.1f}%

## Timing
- Start Time: {self.state.start_time}
- Last Checkpoint: {self.state.last_checkpoint}
- Total Duration: {total_duration:.1f} seconds
- Average per Task: {total_duration / progress['total_tasks']:.1f} seconds

## Tasks with Simplifications Found
"""
        
        for task in completed_tasks:
            summary += f"- {task.file_path} → {task.output_path}\n"
        
        if error_tasks:
            summary += "\n## Failed Tasks\n"
            for task in error_tasks:
                summary += f"- {task.file_path}: {task.error}\n"
        
        if timeout_tasks:
            summary += "\n## Timed Out Tasks\n"
            for task in timeout_tasks:
                summary += f"- {task.file_path} (exceeded {self.config.claude.timeout_minutes} minutes)\n"
        
        # Add modification reporting
        if hasattr(self, 'modification_log') and self.modification_log:
            summary += "\n## Source File Modifications Detected\n"
            for mod in self.modification_log:
                files_str = ', '.join(mod['files'])
                summary += f"- Task {mod['task_id']} ({mod['phase']}): {files_str}\n"
                summary += f"  Time: {mod['timestamp']}\n"
                summary += "  Status: Could not auto-revert - manual review required\n"
        
        return summary
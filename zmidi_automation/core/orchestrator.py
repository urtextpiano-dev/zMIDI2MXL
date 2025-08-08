"""
Main orchestrator for the ZMIDI automation system
Coordinates all modules to execute the complete analysis workflow
"""

import os
import sys
import time
import json
import signal
import hashlib
from pathlib import Path
from typing import List, Dict, Any, Optional
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

from ..config.settings import AutomationConfig, get_config
from ..sync.sync_manager import SyncManager
from ..claude.client import ClaudeClient
from ..ui_automation.window_manager import WindowManager
from .state_manager import StateManager
from .pipeline import Pipeline, Task, TaskStatus, PipelineState


class Orchestrator:
    """Main orchestrator that coordinates the entire automation workflow"""
    
    def __init__(self, config: Optional[AutomationConfig] = None):
        # Configuration
        self.config = config or get_config()
        
        # Validate configuration - warn but don't fail
        if not self.config.validate():
            print("⚠️ Configuration validation failed - using safe defaults")
            # Continue with potentially degraded functionality
        
        # Core components
        self.sync_mgr = SyncManager(
            sync_file=self.config.sync.sync_file,
            atomic_write=self.config.sync.atomic_write
        )
        
        self.window_mgr = WindowManager(self.config)
        
        self.claude_client = ClaudeClient(
            config=self.config,
            window_manager=self.window_mgr
        )
        
        self.state_mgr = StateManager(
            state_file=self.config.monitoring.progress_file
        )
        
        # Pipeline
        self.pipeline = Pipeline(
            config=self.config,
            sync_manager=self.sync_mgr,
            claude_client=self.claude_client,
            ui_automation=self.window_mgr,
            state_manager=self.state_mgr,
            progress_tracker=self  # Orchestrator acts as progress tracker
        )
        
        # State tracking
        self.start_time = None
        self.tasks_processed = 0
        self.errors_encountered = 0
        self.should_stop = False
        
        # Auto-accept thread (just presses '1' periodically)
        self.auto_accept_thread = None
        self.auto_accept_running = False
        
        # Signal handling for graceful shutdown
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        print("\n🛑 Shutdown signal received. Saving state...")
        self.should_stop = True
        self.auto_accept_running = False
        
        # Stop auto-accept thread
        if self.auto_accept_thread and self.auto_accept_thread.is_alive():
            print("🤖 Stopping auto-accept...")
            self.auto_accept_thread.join(timeout=3)
        
        # Save current state
        if hasattr(self, 'pipeline') and self.pipeline.state:
            self.state_mgr.save(self.pipeline.state)
            print("✅ State saved. You can resume later.")
        
        sys.exit(0)
    
    def _start_auto_accept(self):
        """Start auto-accept thread - optimized for Cmder/ConEmu"""
        import threading
        
        # Check if we found a Cmder window
        if self.window_mgr.console_handle:
            try:
                window_title = self.window_mgr.win32gui.GetWindowText(self.window_mgr.console_handle).lower()
                is_cmder = any(term in window_title for term in ["cmder", "conemu", "consoleapp"])
                
                if is_cmder:
                    print("✅ Detected Cmder/ConEmu - using optimized input method")
                else:
                    print("⚠️  Not using Cmder - automation may be less reliable")
            except:
                pass
        
        self.auto_accept_running = True
        self.auto_accept_thread = threading.Thread(target=self._auto_accept_loop, daemon=True)
        self.auto_accept_thread.start()
        print("🤖 Started auto-accept - pressing '1' every second")
    
    def _auto_accept_loop(self):
        """Send '1' to console window every second - works without focus!"""
        import time
        
        press_count = 0
        method_info_shown = False
        
        while self.auto_accept_running and not self.should_stop:
            try:
                # Send '1' directly to console window (no focus needed with pywinauto!)
                if self.window_mgr.send_key_to_window('1'):
                    # Small delay then backspace 3 times to clean up if '1' went to chat
                    time.sleep(0.05)
                    for _ in range(3):
                        self.window_mgr.send_key_to_window('backspace')
                        time.sleep(0.01)  # Tiny delay between backspaces
                    
                    press_count += 1
                    
                    # Show method info on first successful press
                    if press_count == 1 and not method_info_shown:
                        # Check which method is being used
                        try:
                            window_title = self.window_mgr.win32gui.GetWindowText(self.window_mgr.console_handle).lower()
                            is_cmder = any(term in window_title for term in ["cmder", "conemu", "consoleapp"])
                            
                            if is_cmder:
                                print("   ✅ Using enhanced PostMessage for Cmder/ConEmu - should work without focus!")
                            elif self.window_mgr.pywinauto_app:
                                print("   ✅ Using pywinauto UI Automation")
                            else:
                                print("   ⚠️ Using standard PostMessage - may need window focus")
                        except:
                            print("   ℹ️ Auto-accept method determined")
                        method_info_shown = True
                    
                    # Show we're alive every 10 presses
                    if press_count % 10 == 0:
                        print(f"   🤖 Auto-accept active: {press_count} presses")
                else:
                    # Window might be gone, try to find it again
                    if press_count % 10 == 0:
                        print("   ⚠️ Console window not found, retrying...")
                    self.window_mgr.find_console_window()
                
                # Wait before next attempt
                time.sleep(1)
                
            except Exception as e:
                if self.config.debug:
                    print(f"   ⚠️ Auto-accept error: {e}")
                time.sleep(1)
    
    def _stop_auto_accept(self):
        """Stop auto-accept thread"""
        self.auto_accept_running = False
        if self.auto_accept_thread and self.auto_accept_thread.is_alive():
            self.auto_accept_thread.join(timeout=3)
            if self.auto_accept_thread.is_alive():
                print("⚠️ Auto-accept thread did not stop gracefully")
            else:
                print("🤖 Stopped auto-accept")
    
    def initialize(self, skip_handshake=False) -> bool:
        """Initialize the orchestrator and all components"""
        print("🚀 Initializing ZMIDI Automation System v2.0")
        print("=" * 60)
        
        self.start_time = datetime.now()
        
        # Check environment - warn but continue
        if not self._check_environment():
            print("⚠️ Environment issues detected - attempting to continue with degraded functionality")
        
        # Initialize components
        print("📦 Initializing components...")
        
        # Start sync file watching
        self.sync_mgr.start_watching(self._on_sync_update)
        
        # Find and focus console window
        if not self.config.claude.manual_focus:
            print("🔍 Looking for console window...")
            if self.window_mgr.ensure_window_ready():
                print("✅ Console window ready")
            else:
                print("⚠️ Could not find console window. Using manual mode.")
                self.config.claude.manual_focus = True
        
        if self.config.claude.manual_focus:
            print("\n📍 MANUAL MODE: Click in Console/Terminal window in 10 seconds...")
            time.sleep(10)
        
        # DON'T do the handshake yet if skip_handshake is True
        # We'll do it after loading tasks
        self.skip_handshake = skip_handshake
        
        # Start auto-accept thread (just presses '1' every second)
        self._start_auto_accept()
        
        print("✅ Initialization complete")
        print("=" * 60)
        return True
    
    def send_initial_handshake(self) -> bool:
        """Send the initial handshake after tasks are loaded"""
        # Initialize pipeline which sends the handshake
        print("🔧 Initializing pipeline...")
        if not self.pipeline.initialize():
            print("⚠️ Failed to initialize pipeline - continuing without handshake")
            # Continue execution without full initialization
        return True
    
    def _check_environment(self) -> bool:
        """Check that the environment is properly configured"""
        issues = []
        
        # Check project root exists
        if not self.config.project_root.exists():
            issues.append(f"Project root not found: {self.config.project_root}")
        
        # Check output directories can be created
        try:
            os.makedirs(self.config.analysis.output_dir, exist_ok=True)
        except Exception as e:
            issues.append(f"Cannot create output directory: {e}")
        
        # Check sync file is writable
        try:
            self.sync_mgr.update_status("INITIALIZING")
        except Exception as e:
            issues.append(f"Cannot write sync file: {e}")
        
        if issues:
            print("❌ Environment check failed:")
            for issue in issues:
                print(f"  - {issue}")
            return False
        
        return True
    
    def _on_sync_update(self, status):
        """Callback when sync file is updated"""
        # This could trigger actions based on Claude's responses
        if self.config.debug:
            print(f"📝 Sync update: {status.status}")
    
    def load_tasks_from_directory(self, directory: str, pattern: str = "*.txt", 
                                  exclude_tests: bool = True) -> List[Task]:
        """Load tasks from extracted function files, optionally excluding test functions"""
        print(f"\n📂 Loading tasks from: {directory}")
        
        # Convert to Path and handle relative paths
        dir_path = Path(directory)
        if not dir_path.is_absolute():
            # Make it relative to project root
            dir_path = self.config.project_root / dir_path
        
        if not dir_path.exists():
            print(f"❌ Directory not found: {dir_path}")
            return []
        
        # Check for function manifest to filter tests
        manifest_file = dir_path / "function_manifest.json"
        files_to_process = []
        
        if manifest_file.exists() and exclude_tests:
            print("📋 Using function_manifest.json to exclude test functions")
            import json
            with open(manifest_file, 'r') as f:
                manifest = json.load(f)
            
            # Get only non-test function files
            files_to_process = [
                dir_path / func['function_file']
                for func in manifest['functions']
                if func['type'] == 'function'  # Skip test functions
            ]
            print(f"Found {len(files_to_process)} non-test functions (from {len(manifest['functions'])} total)")
        else:
            # Fallback: use pattern matching but exclude obvious test files
            all_files = sorted(dir_path.glob(pattern))
            if exclude_tests:
                files_to_process = [f for f in all_files if 'test_' not in f.name]
                excluded = len(all_files) - len(files_to_process)
                if excluded > 0:
                    print(f"Excluded {excluded} test files based on filename pattern")
            else:
                files_to_process = all_files
            print(f"Found {len(files_to_process)} files to process")
        
        # Load tasks through pipeline
        tasks = self.pipeline.load_tasks([str(f) for f in files_to_process])
        
        print(f"Created {len(tasks)} tasks (excluding completed)")
        return tasks
    
    def run(self, tasks: Optional[List[Task]] = None) -> bool:
        """Run the main orchestration loop"""
        print("\n🎯 Starting main execution loop")
        print("=" * 60)
        
        # Load tasks if not provided
        if tasks is None:
            # Default: load from extracted_functions directory
            tasks = self.load_tasks_from_directory("extracted_functions")
        
        if not tasks:
            print("ℹ️ No tasks to process")
            return True
        
        # Create initial status files
        self._create_initial_files()
        
        # Main execution loop
        success = True
        try:
            # Execute pipeline
            success = self.pipeline.execute(tasks)
            
        except KeyboardInterrupt:
            print("\n⚠️ Interrupted by user - saving progress and continuing")
            self.state_mgr.save(self.pipeline.state)
            success = True  # Continue processing
            
        except Exception as e:
            print(f"\n⚠️ Unexpected error: {e} - saving progress and continuing")
            import traceback
            traceback.print_exc()
            self.state_mgr.save(self.pipeline.state)
            success = True  # Continue processing
            
        finally:
            # Stop auto-accept thread
            self._stop_auto_accept()
            
            # Save final state
            self.state_mgr.save(self.pipeline.state)
            
            # Generate summary
            self._generate_final_summary()
            
            # Cleanup
            self.sync_mgr.stop_watching()
        
        return success
    
    def _create_initial_files(self):
        """Create initial documentation files"""
        # Create rules file
        rules_file = self.config.project_root / "ANALYSIS_RULES.md"
        if not rules_file.exists():
            rules_content = """# ANALYSIS RULES

## CRITICAL SAFETY RULES
1. **NEVER MODIFY SOURCE CODE** - Not even to fix bugs you find!
2. **ONLY CREATE .md FILES** - Documentation only
3. **ONLY IN analysis_results/ directories**
4. **NO OTHER FILE OPERATIONS** - No deletes, renames, etc.
5. **CLAUDE CODE FILE PROMPTS** - ALWAYS press "1" to accept .md files only

## PROCESS
- Use ONLY @zmidi-code-simplifier agent for analysis
- One comprehensive analysis per file
- Focus on simplicity - less is more
- Quality over speed

## COMMUNICATION
Update SYNC_STATUS.md with status:
- STATUS: READY - Ready to begin
- STATUS: WORKING - Analysis in progress
- STATUS: COMPLETE - Analysis complete
- STATUS: PASS - Function already optimal
- STATUS: ERROR - Problem occurred
- STATUS: HELP - Need clarification
"""
            rules_file.write_text(rules_content, encoding='utf-8')
            print(f"✅ Created rules file: {rules_file}")
    
    def _generate_final_summary(self):
        """Generate and save final summary"""
        summary = self.pipeline.generate_summary()
        
        # Add orchestrator-level stats
        if self.start_time:
            duration = datetime.now() - self.start_time
            summary += f"\n\n## Session Statistics\n"
            summary += f"- Session Duration: {duration}\n"
            summary += f"- Tasks Processed: {self.tasks_processed}\n"
            summary += f"- Errors Encountered: {self.errors_encountered}\n"
        
        # Save summary
        summary_file = self.config.project_root / "analysis_summary.md"
        summary_file.write_text(summary, encoding='utf-8')
        
        # Also print to console
        print("\n" + "=" * 60)
        print("📊 FINAL SUMMARY")
        print("=" * 60)
        print(summary)
    
    def resume(self) -> bool:
        """Resume from a previous session"""
        print("\n♻️ Attempting to resume from checkpoint...")
        
        # Load saved state
        saved_state = self.state_mgr.load()
        if not saved_state:
            print("ℹ️ No saved state found. Starting fresh.")
            return self.run()
        
        # Restore pipeline state
        self.pipeline.state = saved_state
        
        # Get remaining tasks
        remaining_tasks = [t for t in saved_state.tasks 
                          if t.id not in saved_state.completed_task_ids]
        
        print(f"✅ Resumed: {len(saved_state.completed_task_ids)} completed, "
              f"{len(remaining_tasks)} remaining")
        
        # Continue execution
        return self.run(remaining_tasks)
    
    def track_task(self, task: Task):
        """Track task completion (implements progress tracker interface)"""
        self.tasks_processed += 1
        
        if task.status == TaskStatus.ERROR:
            self.errors_encountered += 1
        
        # Log metrics if enabled
        if self.config.monitoring.enable_metrics:
            self._log_metrics(task)
    
    def update_display(self, state: PipelineState):
        """Update progress display"""
        progress = state.get_progress()
        
        # Clear line and print progress
        print(f"\r📊 Progress: {progress['completed']}/{progress['total_tasks']} "
              f"({progress['percentage']:.1f}%) - Current: {progress['current_task']}",
              end='', flush=True)
        
        # New line every 10 tasks for visibility
        if progress['completed'] % 10 == 0:
            print()  # New line
    
    def _log_metrics(self, task: Task):
        """Log task metrics"""
        metrics_file = Path(self.config.monitoring.metrics_file)
        
        try:
            # Load existing metrics
            if metrics_file.exists():
                with open(metrics_file, 'r') as f:
                    metrics = json.load(f)
            else:
                metrics = {"tasks": []}
            
            # Add new task metrics
            metrics["tasks"].append({
                "id": task.id,
                "file": task.file_path,
                "status": task.status.value,
                "duration": task.duration(),
                "timestamp": datetime.now().isoformat()
            })
            
            # Save metrics
            with open(metrics_file, 'w') as f:
                json.dump(metrics, f, indent=2)
                
        except Exception as e:
            if self.config.debug:
                print(f"Warning: Failed to log metrics: {e}")
    
    @classmethod
    def create_from_config_file(cls, config_path: str) -> 'Orchestrator':
        """Create orchestrator from configuration file"""
        config = AutomationConfig.from_file(config_path)
        return cls(config)
    
    @classmethod
    def create_with_defaults(cls) -> 'Orchestrator':
        """Create orchestrator with default configuration"""
        config = AutomationConfig.default()
        return cls(config)
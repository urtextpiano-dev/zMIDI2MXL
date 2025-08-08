"""
Enhanced pipeline with all missing critical features
Includes retry logic, prompt detection, progress tracking, and emergency stop
"""

import os
import time
from pathlib import Path
from typing import Optional, Dict, Any
from datetime import datetime

from .pipeline import (
    Pipeline, Task, TaskStatus, PipelineState, 
    SimplificationTaskProcessor, TaskProcessor
)
from ..ui_automation.prompt_detector import PromptDetector
from ..monitoring.progress_tracker import ProgressTracker
from ..utils.retry import TaskRetryManager


class EnhancedSimplificationProcessor(SimplificationTaskProcessor):
    """Enhanced processor with prompt detection and retry logic"""
    
    def __init__(self, sync_manager, claude_client, ui_automation, 
                 config, prompt_detector, retry_manager):
        super().__init__(sync_manager, claude_client, ui_automation, config)
        self.prompt_detector = prompt_detector
        self.retry_manager = retry_manager
    
    def process(self, task: Task, state: PipelineState) -> TaskStatus:
        """Process with retry logic and prompt detection"""
        
        task_id = task.id
        
        # Check if we should retry
        if not self.retry_manager.should_retry(task_id):
            print(f"❌ Task {task_id} exceeded max retries")
            return TaskStatus.ERROR
        
        try:
            # Generate task content
            task_content = self._generate_task_content(task, state)
            
            # Update sync file with new task
            self.sync.update(task_content)
            
            # Send message to Claude
            msg = self._generate_claude_message(task)
            self.claude.send_message(msg)
            
            # Monitor for Claude Code prompts (CRITICAL)
            prompt_handled = self._monitor_for_prompts_enhanced(task)
            
            # Wait for Claude response with status loop
            status = self._wait_with_status_loop(task)
            
            # Handle different statuses
            if status == "COMPLETE":
                self.retry_manager.reset_task(task_id)
                return TaskStatus.COMPLETE
            elif status == "PASS":
                self.retry_manager.reset_task(task_id)
                return TaskStatus.PASS
            elif status == "ERROR":
                # Record retry attempt
                self.retry_manager.record_attempt(task_id, "Task returned ERROR")
                
                # Retry if possible
                if self.retry_manager.should_retry(task_id):
                    print(f"⚠️ Retrying task {task_id} (attempt {self.retry_manager.get_retry_count(task_id) + 1})")
                    time.sleep(2)
                    return self.process(task, state)  # Recursive retry
                else:
                    return TaskStatus.ERROR
            elif status == "HELP":
                # Send clarification
                self.claude.send_message("Skip if not applicable to this file.")
                
                # Wait for response again
                help_status = self.sync.wait_for_claude_response(timeout_minutes=5)
                if help_status in ["COMPLETE", "PASS"]:
                    return TaskStatus.COMPLETE if help_status == "COMPLETE" else TaskStatus.PASS
                else:
                    return TaskStatus.ERROR
            elif status == "EMERGENCY_STOP":
                print("🛑 EMERGENCY STOP triggered!")
                raise Exception("Emergency stop requested")
            else:
                return TaskStatus.ERROR
                
        except Exception as e:
            print(f"Error processing task {task_id}: {e}")
            self.retry_manager.record_attempt(task_id, str(e))
            
            if self.retry_manager.should_retry(task_id):
                print(f"⚠️ Retrying task {task_id} after error")
                time.sleep(2)
                return self.process(task, state)  # Recursive retry
            else:
                return TaskStatus.ERROR
    
    def _monitor_for_prompts_enhanced(self, task: Task) -> bool:
        """Enhanced prompt monitoring with actual detection"""
        
        print("🔍 Monitoring for Claude Code prompts...")
        
        # Expected file path
        expected_file = Path(task.output_path).name
        
        # Monitor for up to 10 seconds
        prompt_info = self.prompt_detector.monitor_for_prompts(
            duration=10,
            callback=lambda p: print(f"Detected: {p.prompt_type}")
        )
        
        if prompt_info:
            if prompt_info.file_path and expected_file in prompt_info.file_path:
                print(f"✅ Auto-handled prompt for: {expected_file}")
                return True
            else:
                print(f"⚠️ Detected prompt but not for expected file")
                return False
        
        # No prompt detected (might be okay if Claude doesn't show one)
        return True
    
    def _wait_with_status_loop(self, task: Task) -> str:
        """Wait with full status loop like original"""
        
        timeout_minutes = self.config.claude.timeout_minutes
        
        # Adjust timeout based on file size
        if hasattr(task, 'file_size'):
            from ..monitoring.progress_tracker import ProgressTracker
            tracker = ProgressTracker()
            timeout_minutes = tracker.calculate_dynamic_timeout(task.file_size)
        
        print(f"⏳ Waiting for Claude response (timeout: {timeout_minutes} minutes)...")
        
        start_time = time.time()
        timeout_seconds = timeout_minutes * 60
        
        while True:
            # Check for timeout
            if time.time() - start_time > timeout_seconds:
                print("⏱️ Timeout reached")
                # Continue waiting with extended timeout
                timeout_seconds += 300  # Add 5 more minutes
                
                if timeout_seconds > 1800:  # Max 30 minutes total
                    return "TIMEOUT"
            
            # Wait for status update
            status = self.sync.wait_for_claude_response(timeout_minutes=1)
            
            if status is None:
                # No update yet, continue waiting
                continue
            
            # Handle different statuses
            if status == "EMERGENCY_STOP":
                return "EMERGENCY_STOP"
            
            elif status in ["COMPLETE", "PASS"]:
                print(f"✅ Task completed with status: {status}")
                return status
            
            elif status.startswith("ERROR"):
                print(f"❌ Task error: {status}")
                return "ERROR"
            
            elif status.startswith("HELP"):
                print(f"❓ Claude needs help: {status}")
                return "HELP"
            
            elif status == "WORKING":
                print(f"⚙️ Task in progress...")
                # Continue waiting
            
            elif status == "TIMEOUT":
                print(f"⏱️ Status check timeout, continuing...")
                # Continue waiting
            
            else:
                print(f"❓ Unknown status: {status}")
                # Continue waiting
            
            time.sleep(2)


class EnhancedPipeline(Pipeline):
    """Enhanced pipeline with all missing features"""
    
    def __init__(self, config, sync_manager, claude_client, 
                 ui_automation, state_manager, window_manager):
        # Initialize base pipeline
        super().__init__(
            config, sync_manager, claude_client,
            ui_automation, state_manager, None  # We'll create our own progress tracker
        )
        
        # Create enhanced components
        self.progress_tracker = ProgressTracker(
            output_dir=config.project_root,
            progress_file="ANALYSIS_PROGRESS.md",
            action_file="ACTION_REQUIRED.md"
        )
        
        self.prompt_detector = PromptDetector(
            config=config,
            window_manager=window_manager
        )
        
        self.retry_manager = TaskRetryManager(max_retries=2)
        
        # Replace processor with enhanced version
        self.processors = [
            EnhancedSimplificationProcessor(
                sync_manager, claude_client, ui_automation, config,
                self.prompt_detector, self.retry_manager
            )
        ]
        
        # Emergency stop flag
        self.emergency_stop = False
    
    def execute(self, tasks: list[Task]) -> bool:
        """Execute with enhanced features"""
        
        # Set total tasks for progress tracking
        self.progress_tracker.set_total_tasks(len(tasks))
        
        # Update state
        self.state.tasks = tasks
        
        for task in tasks:
            # Check for emergency stop
            if self.emergency_stop:
                print("🛑 Emergency stop activated!")
                return False
            
            # Check for source modifications
            if not self._verify_source_integrity():
                print("❌ Source files modified! Emergency stop!")
                self._emergency_stop_handler()
                return False
            
            # Check context usage
            if self._should_handle_context():
                self._handle_context_management()
            
            # Start task tracking
            self.progress_tracker.start_task(task.id, task.file_path)
            
            # Process task
            self.state.current_task = task
            task.start_time = time.time()
            
            # Get file size for dynamic timeout
            if os.path.exists(task.file_path):
                task.file_size = os.path.getsize(task.file_path)
            
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
                
                # Update state
                if status in [TaskStatus.COMPLETE, TaskStatus.PASS]:
                    self.state.completed_task_ids.append(task.id)
                
                # Track in progress tracker
                self.progress_tracker.complete_task(
                    task_id=task.id,
                    status=status.value,
                    duration=task.duration(),
                    file_path=task.file_path,
                    retries=self.retry_manager.get_retry_count(task.id),
                    simplification_found=(status == TaskStatus.COMPLETE),
                    error=task.error
                )
                
                # Save checkpoint
                self.state.last_checkpoint = datetime.now()
                self.state_mgr.save(self.state)
                
                # Clear conversation if enabled
                if self.config.claude.auto_clear:
                    self.claude.send_command("/clear")
                    print("✅ Cleared conversation context")
                
            except Exception as e:
                print(f"Error processing task {task.id}: {e}")
                task.status = TaskStatus.ERROR
                task.error = str(e)
                task.end_time = time.time()
                
                # Track error
                self.progress_tracker.complete_task(
                    task_id=task.id,
                    status="ERROR",
                    duration=task.duration() if task.start_time else 0,
                    file_path=task.file_path,
                    error=str(e)
                )
        
        # Generate final reports
        self.progress_tracker.generate_action_list()
        self.progress_tracker.save_metrics()
        self.progress_tracker.print_summary()
        
        # Send completion message
        self.sync.update_status("ALL_COMPLETE", 
                              task="Analysis finished successfully!")
        self.claude.send_message("🎉 All analysis complete! Check ACTION_REQUIRED.md for results.")
        
        return True
    
    def _emergency_stop_handler(self):
        """Handle emergency stop"""
        
        self.emergency_stop = True
        
        # Log to file
        emergency_log = Path("EMERGENCY_STOP_LOG.txt")
        emergency_log.write_text(f"""
EMERGENCY STOP TRIGGERED
Time: {datetime.now()}
Reason: Source files modified during analysis
Current task: {self.state.current_task.id if self.state.current_task else 'None'}
Completed tasks: {len(self.state.completed_task_ids)}

Check source files for unauthorized modifications!
""")
        
        # Update sync file
        self.sync.update_status("EMERGENCY_STOP", 
                              task="Source files modified! Analysis stopped for safety.")
        
        # Save state for recovery
        self.state_mgr.save(self.state)
        
        print("\n" + "=" * 60)
        print("🛑 EMERGENCY STOP")
        print("=" * 60)
        print("Source files were modified during analysis!")
        print("Check EMERGENCY_STOP_LOG.txt for details")
        print("State saved - you can investigate and resume later")
        print("=" * 60)
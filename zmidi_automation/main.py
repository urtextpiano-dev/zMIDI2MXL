#!/usr/bin/env python3
"""
Main entry point for ZMIDI Automation System v2.0
Replaces the monolithic autonomous_analyzer_ideal_v2.py with modular architecture
"""

import sys
import os
import argparse
import json
from pathlib import Path
from typing import Optional

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from zmidi_automation.core.orchestrator import Orchestrator
from zmidi_automation.config.settings import AutomationConfig


def main():
    """Main entry point with CLI argument parsing"""
    parser = argparse.ArgumentParser(
        description="ZMIDI Automation System - Modular Code Analysis Pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Start new analysis
  python -m zmidi_automation.main --input extracted_functions --start
  
  # Resume from checkpoint
  python -m zmidi_automation.main --resume
  
  # Use custom configuration
  python -m zmidi_automation.main --config my_config.json --start
  
  # Manual window focus mode
  python -m zmidi_automation.main --manual-focus --start
  
  # Debug mode with verbose output
  python -m zmidi_automation.main --debug --start
  
  # Clear saved state and start fresh
  python -m zmidi_automation.main --clear --start
        """,
    )

    # Operation modes (mutually exclusive)
    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument(
        "--start", action="store_true", help="Start new analysis session"
    )
    mode_group.add_argument(
        "--resume", action="store_true", help="Resume from last checkpoint"
    )
    mode_group.add_argument(
        "--status", action="store_true", help="Show current status and exit"
    )
    mode_group.add_argument(
        "--clear", action="store_true", help="Clear saved state and exit"
    )
    mode_group.add_argument(
        "--reset",
        action="store_true",
        help="Reset all state, logs, and output directories",
    )

    # Configuration options
    parser.add_argument("--config", type=str, help="Path to configuration JSON file")
    parser.add_argument(
        "--input",
        type=str,
        default="extracted_functions",
        help="Input directory with extracted functions (default: extracted_functions)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="analysis_results",
        help="Output directory for analysis results (default: analysis_results)",
    )

    # Behavioral options
    parser.add_argument(
        "--manual-focus",
        action="store_true",
        help="Use manual window focus mode (don't auto-focus console)",
    )
    parser.add_argument(
        "--auto-clear",
        action="store_true",
        default=True,
        help="Automatically clear context when high (default: True)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Timeout in minutes for Claude responses (default: 30)",
    )
    parser.add_argument(
        "--include-tests",
        action="store_true",
        help="Include test functions in analysis (default: exclude tests)",
    )

    # Debug options
    parser.add_argument("--debug", action="store_true", help="Enable debug output")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate execution without actually running tasks",
    )

    parser.add_argument(
        "--start-at",
        help="Start from a specific task index (0-based) or exact task ID (e.g., 71 or task_00123)",
        default=None,
    )

    args = parser.parse_args()

    # Create configuration
    config = create_config(args)

    # Handle different modes
    if args.status:
        return show_status(config)
    elif args.clear:
        return clear_state(config)
    elif args.reset:
        return reset_all(config)
    elif args.start:
        return start_analysis(config, args.input, args.start_at)
    elif args.resume:
        return resume_analysis(config)

    return 1


def create_config(args) -> AutomationConfig:
    """Create configuration from arguments"""
    # Start with base configuration
    if args.config:
        config = AutomationConfig.from_file(args.config)
        print(f"✅ Loaded configuration from: {args.config}")
    else:
        config = AutomationConfig.from_env()

    # Override with command-line arguments
    if args.manual_focus:
        config.claude.manual_focus = True

    if args.auto_clear is not None:
        config.claude.auto_clear = args.auto_clear

    if args.timeout:
        config.claude.timeout_minutes = args.timeout

    if args.output:
        config.analysis.output_dir = args.output
        config.analysis.simplification_dir = f"{args.output}/simplification"

    if args.debug:
        config.debug = True

    if args.dry_run:
        config.dry_run = True

    return config


def show_status(config: AutomationConfig) -> int:
    """Show current status and exit"""
    print("📊 ZMIDI Automation Status")
    print("=" * 60)

    # Check for saved state
    from zmidi_automation.core.state_manager import StateManager

    state_mgr = StateManager(state_file=config.monitoring.progress_file)

    checkpoint_info = state_mgr.get_checkpoint_info()
    if checkpoint_info:
        print("\n📁 Saved State:")
        print(f"  File: {checkpoint_info['file']}")
        print(f"  Modified: {checkpoint_info['modified']}")
        print(
            f"  Progress: {checkpoint_info['tasks_completed']}/{checkpoint_info['tasks_total']} tasks"
        )
        print(f"  Version: {checkpoint_info['version']}")
    else:
        print("\nℹ️ No saved state found")

    # Check sync status
    from zmidi_automation.sync.sync_manager import SyncManager

    sync_mgr = SyncManager(sync_file=config.sync.sync_file)
    sync_status = sync_mgr.read_status()

    print(f"\n🔄 Sync Status: {sync_status.status}")
    if sync_status.task:
        print(f"  Current Task: {sync_status.task}")

    # Check configuration
    print("\n⚙️ Configuration:")
    print(f"  Project Root: {config.project_root}")
    print(f"  Input Directory: extracted_functions")
    print(f"  Output Directory: {config.analysis.output_dir}")
    print(f"  Timeout: {config.claude.timeout_minutes} minutes")
    print(f"  Auto Clear: {config.claude.auto_clear}")
    print(f"  Manual Focus: {config.claude.manual_focus}")
    print(f"  Debug Mode: {config.debug}")

    print("\n" + "=" * 60)
    return 0


def clear_state(config: AutomationConfig) -> int:
    """Clear saved state and exit"""
    print("🗑️ Clearing saved state...")

    from zmidi_automation.core.state_manager import StateManager

    state_mgr = StateManager(state_file=config.monitoring.progress_file)

    if state_mgr.clear():
        print("✅ State cleared successfully")
        return 0
    else:
        print("❌ Failed to clear state")
        return 1


def reset_all(config: AutomationConfig) -> int:
    """Reset all state, logs, and output directories"""
    import shutil
    import logging

    print("🔄 Resetting all state and output...")
    print("=" * 60)

    # Close any existing loggers first
    logging.shutdown()

    # Files to remove
    files_to_remove = [
        config.monitoring.progress_file,  # analyzer_state.json
        config.monitoring.metrics_file,  # analyzer_metrics.json
        "analyzer.log",
        "SYNC_STATUS.md",
        "ANALYSIS_PROGRESS.md",
        "SIMPLIFICATION_RULES.md",
        "ANALYSIS_SUMMARY.md",
        "EMERGENCY_STOP_LOG.txt",
    ]

    for f in files_to_remove:
        if os.path.exists(f):
            try:
                os.remove(f)
                print(f"  ✓ Removed {f}")
            except PermissionError:
                print(f"  ⚠️ Could not remove {f}: file in use")
            except Exception as e:
                print(f"  ⚠️ Could not remove {f}: {e}")

    # Directories to clean
    dirs_to_clean = [
        "screenshots",
        config.analysis.output_dir,  # analysis_results
    ]

    for dir_path in dirs_to_clean:
        if os.path.exists(dir_path):
            try:
                shutil.rmtree(dir_path)
                print(f"  ✓ Removed directory {dir_path}/")
            except Exception as e:
                print(f"  ⚠️ Could not remove {dir_path}/: {e}")

    print("=" * 60)
    print("✅ Reset complete - all state and output cleared")
    print("   You can now run with --start to begin fresh")
    return 0


def start_analysis(
    config: AutomationConfig, input_dir: str, start_at: Optional[str]
) -> int:
    """Start new analysis session"""
    print("\n🚀 Starting New Analysis Session")
    print("=" * 60)

    # Create orchestrator
    orchestrator = Orchestrator(config)
    orchestrator.pipeline.start_override = start_at

    # Initialize WITHOUT sending handshake yet
    if not orchestrator.initialize(skip_handshake=True):
        print("❌ Initialization failed")
        return 1

    # NOW load tasks AFTER basic initialization
    tasks = orchestrator.load_tasks_from_directory(input_dir)

    if not tasks:
        print("ℹ️ No tasks found to process")
        print(f"   Looked in: {input_dir}")
        print("   Make sure extracted_functions directory contains .txt files")
        return 0

    # Set the tasks in the pipeline state so the init message shows correct count
    orchestrator.pipeline.state.tasks = tasks

    # NOW send the initial handshake with correct task count
    if not orchestrator.send_initial_handshake():
        print("❌ Failed to send initial handshake")
        return 1

    # Confirm with user
    print(f"\n📋 Ready to process {len(tasks)} tasks")
    print("Press Ctrl+C at any time to pause (state will be saved)")
    print("=" * 60)

    # Run orchestration
    success = orchestrator.run(tasks)

    return 0 if success else 1


def resume_analysis(config: AutomationConfig) -> int:
    """Resume analysis from checkpoint"""
    print("\n♻️ Resuming Analysis from Checkpoint")
    print("=" * 60)

    # Create orchestrator
    orchestrator = Orchestrator(config)

    # Initialize
    if not orchestrator.initialize():
        print("❌ Initialization failed")
        return 1

    # Resume from saved state
    success = orchestrator.resume()

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())

"""
Progress tracking and reporting
Generates ANALYSIS_PROGRESS.md and ACTION_REQUIRED.md files
"""

import json
import time
from pathlib import Path
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict


@dataclass
class TaskMetrics:
    """Metrics for a completed task"""

    task_id: str
    file_path: str
    status: str
    duration: float
    start_time: float
    end_time: float
    retries: int = 0
    error: Optional[str] = None
    simplification_found: bool = False
    complexity_reduction: Optional[float] = None


class ProgressTracker:
    """Tracks and reports analysis progress"""

    def __init__(
        self,
        output_dir: str = ".",
        progress_file: str = "ANALYSIS_PROGRESS.md",
        action_file: str = "ACTION_REQUIRED.md",
    ):
        self.output_dir = Path(output_dir)
        self.progress_file = self.output_dir / progress_file
        self.action_file = self.output_dir / action_file

        self.start_time = datetime.now()
        self.metrics: List[TaskMetrics] = []
        self.current_task: Optional[str] = None
        self.total_tasks = 0
        self.completed_tasks = 0

    def set_total_tasks(self, total: int):
        """Set the total number of tasks"""
        self.total_tasks = total

    def start_task(self, task_id: str, file_path: str):
        """Mark a task as started"""
        self.current_task = task_id

    def complete_task(self, task_id: str, status: str, duration: float, **kwargs):
        """Mark a task as completed with metrics"""
        metrics = TaskMetrics(
            task_id=task_id,
            file_path=kwargs.get("file_path", ""),
            status=status,
            duration=duration,
            start_time=time.time() - duration,
            end_time=time.time(),
            retries=kwargs.get("retries", 0),
            error=kwargs.get("error"),
            simplification_found=kwargs.get("simplification_found", False),
            complexity_reduction=kwargs.get("complexity_reduction"),
        )

        self.metrics.append(metrics)
        self.completed_tasks += 1
        self.current_task = None

        # Update progress file
        self.update_progress_file()

    def update_progress_file(self):
        """Generate and update ANALYSIS_PROGRESS.md"""

        # Calculate statistics
        elapsed = datetime.now() - self.start_time
        completed = self.completed_tasks
        remaining = self.total_tasks - completed

        remaining = max(remaining, 0)
        comp_pct = (completed / self.total_tasks * 100) if self.total_tasks > 0 else 0.0

        if completed > 0:
            avg_duration = sum(m.duration for m in self.metrics) / len(self.metrics)
            estimated_remaining = timedelta(seconds=avg_duration * remaining)
        else:
            avg_duration = 0
            estimated_remaining = timedelta(0)

        # Calculate success rate
        successful = len([m for m in self.metrics if m.status in ["COMPLETE", "PASS"]])
        errors = len([m for m in self.metrics if m.status == "ERROR"])
        timeouts = len([m for m in self.metrics if m.status == "TIMEOUT"])
        success_rate = (successful / completed * 100) if completed > 0 else 0
        # --- extra stats (lightweight, no new deps) ---
        elapsed_seconds = max(elapsed.total_seconds(), 1e-9)
        throughput_per_hour = completed / (elapsed_seconds / 3600.0)

        durations = [m.duration for m in self.metrics] if self.metrics else []
        if durations:
            sdur = sorted(durations)
            idx50 = max(0, int(0.50 * (len(sdur) - 1)))
            idx95 = max(0, int(0.95 * (len(sdur) - 1)))
            p50 = sdur[idx50]
            p95 = sdur[idx95]
            fastest = sdur[0]
            slowest = sdur[-1]
            lastn = durations[-5:] if len(durations) >= 5 else durations
            rolling5 = sum(lastn) / len(lastn)
        else:
            p50 = p95 = fastest = slowest = rolling5 = 0.0

        eta_ts = (
            (datetime.now() + estimated_remaining).strftime("%Y-%m-%d %H:%M:%S")
            if remaining > 0
            else "—"
        )

        bar_len = 20
        filled = int(round(bar_len * comp_pct / 100.0))
        progress_bar = (
            "[" + "█" * filled + "░" * (bar_len - filled) + f"] {comp_pct:.1f}%"
        )

        # Count simplifications found
        simplifications = len([m for m in self.metrics if m.simplification_found])

        content = f"""# ANALYSIS PROGRESS

## Overview
- **Started**: {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}
- **Elapsed**: {str(elapsed).split('.')[0]}
- **Status**: {'RUNNING' if self.current_task else 'WAITING'}

## Progress
- **Total Tasks**: {self.total_tasks}
- **Completed**: {completed} ({comp_pct:.1f}%)
- **Remaining**: {remaining}
- **Current Task**: {self.current_task or 'None'}
- **Progress Bar**: {progress_bar}

- **Throughput**: {throughput_per_hour:.2f} tasks/hour
- **Median Duration**: {p50:.1f}s
- **P95 Duration**: {p95:.1f}s
- **Fastest/Slowest**: {fastest:.1f}s / {slowest:.1f}s
- **Rolling Avg (last 5)**: {rolling5:.1f}s
- **ETA**: {eta_ts}


## Performance
- **Average Duration**: {avg_duration:.1f}s per task
- **Estimated Remaining**: {str(estimated_remaining).split('.')[0]}
- **Success Rate**: {success_rate:.1f}%
- **Simplifications Found**: {simplifications}

## Task Summary
| Status | Count | Percentage |
|--------|-------|------------|
| COMPLETE | {len([m for m in self.metrics if m.status == 'COMPLETE'])} | {len([m for m in self.metrics if m.status == 'COMPLETE'])/max(completed,1)*100:.1f}% |
| PASS | {len([m for m in self.metrics if m.status == 'PASS'])} | {len([m for m in self.metrics if m.status == 'PASS'])/max(completed,1)*100:.1f}% |
| ERROR | {errors} | {errors/max(completed,1)*100:.1f}% |
| TIMEOUT | {timeouts} | {timeouts/max(completed,1)*100:.1f}% |

## Recent Tasks
"""

        # Add recent tasks (last 10)
        recent = self.metrics[-10:] if self.metrics else []
        for metric in reversed(recent):
            status_icon = (
                "✅"
                if metric.status == "COMPLETE"
                else (
                    "⭕"
                    if metric.status == "PASS"
                    else "⏱️" if metric.status == "TIMEOUT" else "❌"
                )
            )
            content += f"- {status_icon} {Path(metric.file_path).name} ({metric.duration:.1f}s)\n"

        if errors > 0:
            content += "\n## Errors\n"
            for metric in self.metrics:
                if metric.status == "ERROR":
                    content += f"- {Path(metric.file_path).name}: {metric.error or 'Unknown error'}\n"

        if timeouts > 0:
            content += "\n## Timeouts\n"
            for metric in self.metrics:
                if metric.status == "TIMEOUT":
                    content += (
                        f"- {Path(metric.file_path).name}: Exceeded timeout limit\n"
                    )

        content += (
            f"\n---\n*Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*"
        )

        # Write file
        self.progress_file.write_text(content, encoding="utf-8")

    def generate_action_list(self):
        """Generate ACTION_REQUIRED.md with prioritized changes"""

        # Collect all simplifications found
        simplifications = [m for m in self.metrics if m.simplification_found]

        if not simplifications:
            content = f"""# ACTION REQUIRED

## No Simplifications Found

All analyzed functions are already optimized. No changes required.

---
*Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*
"""
        else:
            # Sort by complexity reduction (highest first)
            simplifications.sort(
                key=lambda m: m.complexity_reduction or 0, reverse=True
            )

            content = f"""# ACTION REQUIRED

## Summary
- **Total Simplifications Found**: {len(simplifications)}
- **Functions Analyzed**: {self.completed_tasks}
- **Success Rate**: {len(simplifications)/max(self.completed_tasks,1)*100:.1f}%

## Priority Changes

### HIGH PRIORITY (>40% complexity reduction)
"""

            high = [s for s in simplifications if (s.complexity_reduction or 0) > 0.4]
            medium = [
                s
                for s in simplifications
                if 0.2 <= (s.complexity_reduction or 0) <= 0.4
            ]
            low = [s for s in simplifications if (s.complexity_reduction or 0) < 0.2]

            for s in high:
                content += f"- [ ] {Path(s.file_path).name} - {s.complexity_reduction*100:.0f}% reduction\n"

            if not high:
                content += "- None\n"

            content += "\n### MEDIUM PRIORITY (20-40% complexity reduction)\n"
            for s in medium:
                content += f"- [ ] {Path(s.file_path).name} - {s.complexity_reduction*100:.0f}% reduction\n"

            if not medium:
                content += "- None\n"

            content += "\n### LOW PRIORITY (<20% complexity reduction)\n"
            for s in low:
                content += f"- [ ] {Path(s.file_path).name} - {s.complexity_reduction*100:.0f}% reduction\n"

            if not low:
                content += "- None\n"

            content += f"""

## Implementation Guide

1. Start with HIGH PRIORITY items
2. Review analysis file in `analysis_results/simplification/`
3. Apply recommended changes
4. Run `zig build test` to verify
5. Commit changes with reference to analysis

## Files to Review
"""

            for s in simplifications:
                analysis_file = (
                    f"analysis_results/simplification/{Path(s.file_path).stem}.md"
                )
                content += f"- {analysis_file}\n"

            content += (
                f"\n---\n*Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*"
            )

        # Write file
        self.action_file.write_text(content, encoding="utf-8")

    def get_current_progress(self) -> Dict[str, Any]:
        """Get current progress as dictionary"""
        return {
            "total_tasks": self.total_tasks,
            "completed_tasks": self.completed_tasks,
            "remaining_tasks": self.total_tasks - self.completed_tasks,
            "percentage": (
                (self.completed_tasks / self.total_tasks * 100)
                if self.total_tasks > 0
                else 0
            ),
            "current_task": self.current_task,
            "elapsed_time": str(datetime.now() - self.start_time).split(".")[0],
            "simplifications_found": len(
                [m for m in self.metrics if m.simplification_found]
            ),
            "errors": len([m for m in self.metrics if m.status == "ERROR"]),
            "timeouts": len([m for m in self.metrics if m.status == "TIMEOUT"]),
        }

    def print_summary(self):
        """Print a summary to console"""
        progress = self.get_current_progress()

        print("\n" + "=" * 60)
        print("📊 PROGRESS SUMMARY")
        print("=" * 60)
        print(f"Total Tasks: {progress['total_tasks']}")
        print(
            f"Completed: {progress['completed_tasks']} ({progress['percentage']:.1f}%)"
        )
        print(f"Remaining: {progress['remaining_tasks']}")
        print(f"Simplifications Found: {progress['simplifications_found']}")
        print(f"Errors: {progress['errors']}")
        print(f"Elapsed Time: {progress['elapsed_time']}")
        print("=" * 60)

    def save_metrics(self, file_path: Optional[str] = None):
        """Save detailed metrics to JSON file"""
        if not file_path:
            file_path = self.output_dir / ".automation_metrics.json"

        metrics_data = {
            "session": {
                "start_time": self.start_time.isoformat(),
                "elapsed": str(datetime.now() - self.start_time),
                "total_tasks": self.total_tasks,
                "completed_tasks": self.completed_tasks,
            },
            "tasks": [asdict(m) for m in self.metrics],
            "summary": self.get_current_progress(),
        }

        with open(file_path, "w") as f:
            json.dump(metrics_data, f, indent=2)

    def calculate_dynamic_timeout(self, file_size: int) -> int:
        """Calculate timeout based on file size and historical data"""

        # Base timeout
        base_timeout = 30  # minutes

        # Adjust based on file size (1 minute per 1000 bytes)
        size_factor = file_size / 1000

        # Adjust based on historical performance
        if self.metrics:
            # Get average duration for similar sized files
            avg_duration = sum(m.duration for m in self.metrics) / len(self.metrics)
            # Convert to minutes and add buffer
            historical_factor = (avg_duration / 60) * 1.5
        else:
            historical_factor = 0

        # Calculate final timeout
        timeout = base_timeout + size_factor + historical_factor

        # Cap at maximum
        return min(int(timeout), 30)  # Max 30 minutes

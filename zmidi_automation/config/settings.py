"""
Configuration management for ZMIDI Automation
Centralizes all settings and provides multiple loading methods
"""

import os
import json
from dataclasses import dataclass, field, asdict
from typing import Optional, Dict, Any
from pathlib import Path


@dataclass
class SyncConfig:
    """Configuration for sync file management"""
    sync_file: str = "SYNC_STATUS.md"
    watch_interval: float = 0.5
    atomic_write: bool = True
    backup_count: int = 3


@dataclass
class ClaudeConfig:
    """Configuration for Claude Code interaction"""
    timeout_minutes: int = 30
    auto_clear: bool = True
    manual_focus: bool = False
    compact_threshold: int = 75  # Context percentage
    emergency_threshold: int = 95
    max_retries: int = 3
    retry_delay: float = 2.0


@dataclass
class UIConfig:
    """Configuration for UI automation"""
    screenshot_delay: float = 0.5
    window_title: str = "Windows PowerShell"
    ocr_confidence: float = 0.8
    prompt_detection_enabled: bool = True
    auto_response_to_prompts: bool = True


@dataclass
class AnalysisConfig:
    """Configuration for code analysis"""
    output_dir: str = "analysis_results"
    simplification_dir: str = "analysis_results/simplification"
    min_complexity_reduction: float = 0.20  # 20% minimum
    require_testing: bool = True
    zig_command: str = 'cmd.exe /c "zig {}"'  # Windows wrapper


@dataclass
class MonitoringConfig:
    """Configuration for monitoring and metrics"""
    enable_metrics: bool = True
    metrics_file: str = ".automation_metrics.json"
    source_check_interval: int = 60  # seconds
    progress_file: str = ".analysis_progress.json"


@dataclass
class AutomationConfig:
    """Main configuration container"""
    sync: SyncConfig = field(default_factory=SyncConfig)
    claude: ClaudeConfig = field(default_factory=ClaudeConfig)
    ui: UIConfig = field(default_factory=UIConfig)
    analysis: AnalysisConfig = field(default_factory=AnalysisConfig)
    monitoring: MonitoringConfig = field(default_factory=MonitoringConfig)
    
    # Global settings
    project_root: Path = field(default_factory=lambda: Path.cwd())
    debug: bool = False
    dry_run: bool = False
    
    @classmethod
    def from_env(cls) -> 'AutomationConfig':
        """Load configuration from environment variables"""
        config = cls()
        
        # Override with environment variables
        if sync_file := os.getenv("ZMIDI_SYNC_FILE"):
            config.sync.sync_file = sync_file
        
        if timeout := os.getenv("ZMIDI_TIMEOUT_MINUTES"):
            config.claude.timeout_minutes = int(timeout)
        
        if debug := os.getenv("ZMIDI_DEBUG"):
            config.debug = debug.lower() in ("true", "1", "yes")
        
        if zig_cmd := os.getenv("ZMIDI_ZIG_COMMAND"):
            config.analysis.zig_command = zig_cmd
            
        return config
    
    @classmethod
    def from_file(cls, path: str) -> 'AutomationConfig':
        """Load configuration from JSON file"""
        with open(path, 'r') as f:
            data = json.load(f)
        
        config = cls()
        
        # Update nested configs
        if 'sync' in data:
            config.sync = SyncConfig(**data['sync'])
        if 'claude' in data:
            config.claude = ClaudeConfig(**data['claude'])
        if 'ui' in data:
            config.ui = UIConfig(**data['ui'])
        if 'analysis' in data:
            config.analysis = AnalysisConfig(**data['analysis'])
        if 'monitoring' in data:
            config.monitoring = MonitoringConfig(**data['monitoring'])
        
        # Update global settings
        if 'debug' in data:
            config.debug = data['debug']
        if 'dry_run' in data:
            config.dry_run = data['dry_run']
        if 'project_root' in data:
            config.project_root = Path(data['project_root'])
            
        return config
    
    @classmethod
    def default(cls) -> 'AutomationConfig':
        """Get default configuration"""
        return cls()
    
    def save(self, path: str):
        """Save configuration to JSON file"""
        data = {
            'sync': asdict(self.sync),
            'claude': asdict(self.claude),
            'ui': asdict(self.ui),
            'analysis': asdict(self.analysis),
            'monitoring': asdict(self.monitoring),
            'debug': self.debug,
            'dry_run': self.dry_run,
            'project_root': str(self.project_root)
        }
        
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)
    
    def validate(self) -> bool:
        """Validate configuration settings"""
        errors = []
        
        # Check paths exist
        if not self.project_root.exists():
            errors.append(f"Project root does not exist: {self.project_root}")
        
        # Check timeout is reasonable
        if self.claude.timeout_minutes < 1 or self.claude.timeout_minutes > 60:
            errors.append(f"Timeout must be between 1 and 60 minutes: {self.claude.timeout_minutes}")
        
        # Check thresholds
        if self.claude.compact_threshold >= self.claude.emergency_threshold:
            errors.append("Compact threshold must be less than emergency threshold")
        
        # Check complexity reduction
        if not 0 < self.analysis.min_complexity_reduction < 1:
            errors.append("Min complexity reduction must be between 0 and 1")
        
        if errors:
            print("Configuration validation errors:")
            for error in errors:
                print(f"  - {error}")
            return False
            
        return True


# Singleton pattern for global config
_global_config: Optional[AutomationConfig] = None


def get_config() -> AutomationConfig:
    """Get the global configuration instance"""
    global _global_config
    if _global_config is None:
        # Try loading from file first, then env, then default
        config_file = os.getenv("ZMIDI_CONFIG_FILE", "zmidi_config.json")
        if os.path.exists(config_file):
            _global_config = AutomationConfig.from_file(config_file)
        else:
            _global_config = AutomationConfig.from_env()
    return _global_config


def set_config(config: AutomationConfig):
    """Set the global configuration instance"""
    global _global_config
    _global_config = config


def reset_config():
    """Reset to default configuration"""
    global _global_config
    _global_config = AutomationConfig.default()
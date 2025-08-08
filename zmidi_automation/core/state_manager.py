"""
State management for the automation pipeline
Handles persistence and recovery of pipeline state
"""

import json
import os
import shutil
import tempfile
from pathlib import Path
from typing import Optional, Dict, Any
from datetime import datetime
from .pipeline import PipelineState


class StateManager:
    """Manages pipeline state persistence and recovery"""
    
    def __init__(self, state_file: str = ".automation_state.json", 
                 backup_dir: str = ".state_backups"):
        self.state_file = Path(state_file)
        self.backup_dir = Path(backup_dir)
        self.backup_dir.mkdir(exist_ok=True)
        
        # Keep last N backups
        self.max_backups = 10
    
    def save(self, state: PipelineState) -> bool:
        """Save pipeline state to disk with atomic write"""
        try:
            # Convert state to dict
            state_dict = state.to_dict()
            
            # Add metadata
            state_dict['_metadata'] = {
                'version': '2.0.0',
                'saved_at': datetime.now().isoformat(),
                'tasks_completed': len(state.completed_task_ids),
                'tasks_total': len(state.tasks)
            }
            
            # Atomic write
            content = json.dumps(state_dict, indent=2)
            self._atomic_write(self.state_file, content)
            
            # Create backup
            self._create_backup(state_dict)
            
            return True
            
        except Exception as e:
            print(f"Error saving state: {e}")
            return False
    
    def load(self) -> Optional[PipelineState]:
        """Load pipeline state from disk"""
        try:
            if not self.state_file.exists():
                return None
            
            with open(self.state_file, 'r') as f:
                state_dict = json.load(f)
            
            # Remove metadata before creating PipelineState
            state_dict.pop('_metadata', None)
            
            # Create PipelineState from dict
            state = PipelineState.from_dict(state_dict)
            
            print(f"✅ Loaded state: {len(state.completed_task_ids)} tasks completed")
            return state
            
        except Exception as e:
            print(f"Error loading state: {e}")
            
            # Try to recover from backup
            backup = self._recover_from_backup()
            if backup:
                print("✅ Recovered from backup")
                return backup
            
            return None
    
    def _atomic_write(self, file_path: Path, content: str):
        """Write file atomically to prevent corruption"""
        # Write to temporary file
        with tempfile.NamedTemporaryFile(
            mode='w',
            dir=file_path.parent,
            delete=False,
            suffix='.tmp'
        ) as tmp_file:
            tmp_file.write(content)
            tmp_file.flush()
            os.fsync(tmp_file.fileno())
            tmp_path = tmp_file.name
        
        # Atomic rename
        shutil.move(tmp_path, str(file_path))
    
    def _create_backup(self, state_dict: Dict[str, Any]):
        """Create a backup of the state"""
        try:
            # Generate backup filename with timestamp
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_file = self.backup_dir / f"state_backup_{timestamp}.json"
            
            # Save backup
            with open(backup_file, 'w') as f:
                json.dump(state_dict, f, indent=2)
            
            # Clean old backups
            self._cleanup_old_backups()
            
        except Exception as e:
            print(f"Warning: Failed to create backup: {e}")
    
    def _cleanup_old_backups(self):
        """Remove old backups keeping only the most recent ones"""
        try:
            backups = sorted(self.backup_dir.glob("state_backup_*.json"))
            
            if len(backups) > self.max_backups:
                # Remove oldest backups
                for backup in backups[:-self.max_backups]:
                    backup.unlink()
                    
        except Exception as e:
            print(f"Warning: Failed to cleanup backups: {e}")
    
    def _recover_from_backup(self) -> Optional[PipelineState]:
        """Try to recover state from most recent backup"""
        try:
            backups = sorted(self.backup_dir.glob("state_backup_*.json"))
            
            if not backups:
                return None
            
            # Try most recent backup first
            for backup_file in reversed(backups):
                try:
                    with open(backup_file, 'r') as f:
                        state_dict = json.load(f)
                    
                    # Remove metadata
                    state_dict.pop('_metadata', None)
                    
                    # Create PipelineState
                    state = PipelineState.from_dict(state_dict)
                    
                    print(f"Recovered from backup: {backup_file.name}")
                    return state
                    
                except Exception as e:
                    print(f"Failed to recover from {backup_file.name}: {e}")
                    continue
            
            return None
            
        except Exception as e:
            print(f"Error recovering from backup: {e}")
            return None
    
    def clear(self) -> bool:
        """Clear the saved state"""
        try:
            if self.state_file.exists():
                # Create final backup before clearing
                if state := self.load():
                    state_dict = state.to_dict()
                    state_dict['_metadata'] = {
                        'cleared_at': datetime.now().isoformat(),
                        'reason': 'manual_clear'
                    }
                    self._create_backup(state_dict)
                
                # Remove state file
                self.state_file.unlink()
                print("✅ State cleared")
                return True
            
            return True
            
        except Exception as e:
            print(f"Error clearing state: {e}")
            return False
    
    def get_checkpoint_info(self) -> Optional[Dict[str, Any]]:
        """Get information about the current checkpoint"""
        try:
            if not self.state_file.exists():
                return None
            
            # Get file stats
            stats = self.state_file.stat()
            
            # Load metadata
            with open(self.state_file, 'r') as f:
                state_dict = json.load(f)
            
            metadata = state_dict.get('_metadata', {})
            
            return {
                'file': str(self.state_file),
                'size': stats.st_size,
                'modified': datetime.fromtimestamp(stats.st_mtime),
                'saved_at': metadata.get('saved_at'),
                'tasks_completed': metadata.get('tasks_completed', 0),
                'tasks_total': metadata.get('tasks_total', 0),
                'version': metadata.get('version', 'unknown')
            }
            
        except Exception as e:
            print(f"Error getting checkpoint info: {e}")
            return None
    
    def export_state(self, export_path: str) -> bool:
        """Export current state to a file"""
        try:
            if not self.state_file.exists():
                print("No state to export")
                return False
            
            shutil.copy2(self.state_file, export_path)
            print(f"✅ State exported to: {export_path}")
            return True
            
        except Exception as e:
            print(f"Error exporting state: {e}")
            return False
    
    def import_state(self, import_path: str) -> bool:
        """Import state from a file"""
        try:
            import_file = Path(import_path)
            if not import_file.exists():
                print(f"Import file not found: {import_path}")
                return False
            
            # Validate it's valid JSON
            with open(import_file, 'r') as f:
                state_dict = json.load(f)
            
            # Backup current state if exists
            if self.state_file.exists():
                self._create_backup(json.loads(self.state_file.read_text()))
            
            # Copy imported state
            shutil.copy2(import_file, self.state_file)
            print(f"✅ State imported from: {import_path}")
            return True
            
        except Exception as e:
            print(f"Error importing state: {e}")
            return False
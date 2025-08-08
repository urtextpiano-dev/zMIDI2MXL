"""UI automation modules"""

from .window_manager import WindowManager, WindowInfo
from .prompt_detector import PromptDetector, PromptInfo

__all__ = [
    "WindowManager",
    "WindowInfo",
    "PromptDetector", 
    "PromptInfo"
]
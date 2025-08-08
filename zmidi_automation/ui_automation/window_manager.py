"""
Window management for UI automation
Handles window focus, positioning, and interaction
"""

import time
import platform
from typing import Optional, Tuple, List, Callable
from dataclasses import dataclass


@dataclass
class WindowInfo:
    """Information about a window"""
    handle: int
    title: str
    rect: Tuple[int, int, int, int]  # left, top, right, bottom
    is_visible: bool
    is_minimized: bool


class WindowManager:
    """Manages window operations across platforms"""
    
    def __init__(self, config):
        self.config = config
        self.platform = platform.system()
        self.console_handle: Optional[int] = None
        self.last_focus_time = 0
        self.pywinauto_app = None  # Store pywinauto application connection
        
        # Platform-specific imports
        if self.platform == "Windows":
            self._init_windows()
        elif self.platform == "Darwin":  # macOS
            self._init_macos()
        else:  # Linux
            self._init_linux()
    
    def _init_windows(self):
        """Initialize Windows-specific components"""
        try:
            import win32gui
            import win32con
            import win32process
            self.win32gui = win32gui
            self.win32con = win32con
            self.win32process = win32process
            self.platform_available = True
        except ImportError:
            print("Warning: pywin32 not installed. Window management disabled.")
            print("Install with: pip install pywin32")
            self.platform_available = False
    
    def _init_macos(self):
        """Initialize macOS-specific components"""
        # macOS implementation would use AppleScript or PyObjC
        self.platform_available = False
        print("macOS window management not yet implemented")
    
    def _init_linux(self):
        """Initialize Linux-specific components"""
        # Linux implementation would use xdotool or wmctrl
        self.platform_available = False
        print("Linux window management not yet implemented")
    
    def find_console_window(self) -> Optional[WindowInfo]:
        """Find the console/terminal window"""
        if not self.platform_available:
            return None
        
        if self.platform == "Windows":
            return self._find_windows_console()
        
        return None
    
    def _find_windows_console(self) -> Optional[WindowInfo]:
        """Find console window on Windows"""
        found_windows = []
        
        # Console window patterns - PRIORITIZE CMDER/CONEMU
        console_terms = [
            "cmder", "conemu", "consoleapp",  # Cmder/ConEmu specific
            "powershell", "windows powershell", "pwsh", 
            "cmd.exe", "command prompt", "windows terminal",
            "ubuntu", "wsl", "bash", "wsl.exe"
        ]
        
        def enum_callback(hwnd, windows):
            if self.win32gui.IsWindowVisible(hwnd):
                window_title = self.win32gui.GetWindowText(hwnd)
                window_title_lower = window_title.lower()
                
                # Check if it's a console window OR has @ in title (WSL/SSH sessions)
                is_console = any(term in window_title_lower for term in console_terms)
                is_wsl_ssh = "@" in window_title  # Matches alex@DESKTOP-FBH488U
                
                if is_console or is_wsl_ssh:
                    rect = self.win32gui.GetWindowRect(hwnd)
                    is_minimized = self.win32gui.IsIconic(hwnd)
                    
                    info = WindowInfo(
                        handle=hwnd,
                        title=window_title,
                        rect=rect,
                        is_visible=True,
                        is_minimized=bool(is_minimized)
                    )
                    windows.append(info)
            return True
        
        self.win32gui.EnumWindows(enum_callback, found_windows)
        
        if found_windows:
            # Sort windows by preference
            # 1. PREFER CMDER/CONEMU FIRST (best automation support)
            # 2. Then windows with @ (WSL/SSH sessions)
            # 3. Then non-minimized windows
            # 4. Then any window
            
            # First, look for Cmder/ConEmu windows
            for window in found_windows:
                title_lower = window.title.lower()
                if any(term in title_lower for term in ["cmder", "conemu", "consoleapp"]):
                    print(f"✅ Found Cmder/ConEmu window: '{window.title}'")
                    self.console_handle = window.handle
                    return window
            
            # Then, look for windows with @ that aren't minimized
            for window in found_windows:
                if "@" in window.title and not window.is_minimized:
                    print(f"✅ Found WSL/SSH window: '{window.title}'")
                    self.console_handle = window.handle
                    return window
            
            # Then, look for any window with @
            for window in found_windows:
                if "@" in window.title:
                    print(f"✅ Found WSL/SSH window (minimized): '{window.title}'")
                    self.console_handle = window.handle
                    return window
            
            # Then prefer non-minimized windows
            for window in found_windows:
                if not window.is_minimized:
                    print(f"✅ Found console window: '{window.title}'")
                    self.console_handle = window.handle
                    return window
            
            # Fall back to first found
            print(f"✅ Using first found window: '{found_windows[0].title}'")
            self.console_handle = found_windows[0].handle
            return found_windows[0]
        
        return None
    
    def focus_console(self, force: bool = False, quick: bool = False) -> bool:
        """Focus the console window"""
        if not self.platform_available:
            return False
        
        # Rate limiting (skip for quick focus operations)
        if not quick:
            current_time = time.time()
            if not force and current_time - self.last_focus_time < 1:
                return True  # Skip if recently focused
        
        if self.platform == "Windows":
            result = self._focus_windows_console()
        else:
            result = False
        
        if result and not quick:
            self.last_focus_time = time.time()
            time.sleep(0.5)  # Give window time to focus (skip for quick operations)
        
        return result
    
    def _focus_windows_console(self) -> bool:
        """Focus console window on Windows"""
        if not self.console_handle:
            window = self.find_console_window()
            if not window:
                return False
            self.console_handle = window.handle
        
        try:
            # Restore if minimized
            if self.win32gui.IsIconic(self.console_handle):
                self.win32gui.ShowWindow(self.console_handle, self.win32con.SW_RESTORE)
                time.sleep(0.3)
            
            # Bring to foreground
            self.win32gui.SetForegroundWindow(self.console_handle)
            
            # Also try alternative methods for stubborn windows
            self.win32gui.BringWindowToTop(self.console_handle)
            self.win32gui.SetActiveWindow(self.console_handle)
            
            return True
            
        except Exception as e:
            print(f"Error focusing window: {e}")
            # Try to find window again
            self.console_handle = None
            return False
    
    def send_key_to_window(self, key: str) -> bool:
        """Send a key to the console window - optimized for Cmder/ConEmu"""
        if not self.platform_available or self.platform != "Windows":
            return False
        
        # Validate window handle is still valid
        if self.console_handle:
            try:
                # IsWindow returns 0 if handle is invalid
                if not self.win32gui.IsWindow(self.console_handle):
                    self.console_handle = None  # Clear stale handle
            except:
                self.console_handle = None  # Clear on any error
        
        # Find window if we don't have a valid handle
        if not self.console_handle:
            window = self.find_console_window()
            if not window:
                return False
            self.console_handle = window.handle
        
        # Check if this is Cmder/ConEmu (they handle input better)
        try:
            window_title = self.win32gui.GetWindowText(self.console_handle).lower()
            is_cmder = any(term in window_title for term in ["cmder", "conemu", "consoleapp"])
        except:
            is_cmder = False
        
        # Try methods in order of reliability for Cmder
        if is_cmder:
            # For Cmder, try enhanced PostMessage first (works better than with other terminals)
            if self._send_key_with_enhanced_postmessage(key):
                return True
        
        # Try pywinauto if available
        if self._send_key_with_pywinauto(key):
            return True
        
        # Fallback to regular PostMessage
        return self._send_key_with_postmessage(key)
    
    def _send_key_with_enhanced_postmessage(self, key: str) -> bool:
        """Enhanced PostMessage for Cmder/ConEmu - they handle this better"""
        try:
            import time
            
            # Windows message constants
            WM_KEYDOWN = 0x0100
            WM_KEYUP = 0x0101
            WM_CHAR = 0x0102
            WM_SYSKEYDOWN = 0x0104
            WM_SYSKEYUP = 0x0105
            
            # Virtual key codes
            key_codes = {
                '1': 0x31,
                '2': 0x32,
                '3': 0x33,
                'enter': 0x0D,
                'backspace': 0x08,
            }
            
            if key not in key_codes:
                return False
            
            vk_code = key_codes[key]
            
            # For Cmder/ConEmu, send a more complete sequence
            if key in ['1', '2', '3']:
                # Send both KEYDOWN, CHAR, and KEYUP for better compatibility
                # This sequence works better with ConEmu's input handling
                
                # Key down with proper scan code for number keys
                scan_code = 0x02 + (ord(key) - ord('1'))  # Scan codes: 1=0x02, 2=0x03, 3=0x04
                lparam_down = (1 | (scan_code << 16))  # repeat count 1, scan code
                self.win32gui.PostMessage(self.console_handle, WM_KEYDOWN, vk_code, lparam_down)
                
                # Small delay for Cmder to process
                time.sleep(0.001)
                
                # Character message (most important for Cmder)
                self.win32gui.PostMessage(self.console_handle, WM_CHAR, ord(key), 0)
                
                # Small delay before key up
                time.sleep(0.001)
                
                # Key up with scan code and release flags
                lparam_up = (1 | (scan_code << 16) | (1 << 30) | (1 << 31))  # key up flags
                self.win32gui.PostMessage(self.console_handle, WM_KEYUP, vk_code, lparam_up)
            else:
                # For special keys like Enter/Backspace
                scan_code = 0x0E if key == 'backspace' else 0x1C if key == 'enter' else 0x01
                lparam_down = (1 | (scan_code << 16))
                self.win32gui.PostMessage(self.console_handle, WM_KEYDOWN, vk_code, lparam_down)
                
                time.sleep(0.001)
                
                lparam_up = (1 | (scan_code << 16) | (1 << 30) | (1 << 31))
                self.win32gui.PostMessage(self.console_handle, WM_KEYUP, vk_code, lparam_up)
            
            return True
            
        except Exception as e:
            if self.config.debug:
                print(f"Enhanced PostMessage error: {e}")
            return False
    
    def _send_key_with_pywinauto(self, key: str) -> bool:
        """Send key using pywinauto UI Automation (works without focus!)"""
        try:
            from pywinauto import Application
            from pywinauto.findwindows import ElementNotFoundError
            
            # Connect to window if not already connected
            if not self.pywinauto_app:
                try:
                    # Connect using window handle
                    self.pywinauto_app = Application(backend="uia").connect(handle=self.console_handle)
                except ElementNotFoundError:
                    # Try win32 backend if UIA fails
                    try:
                        self.pywinauto_app = Application(backend="win32").connect(handle=self.console_handle)
                    except:
                        return False
            
            # Get the window
            window = self.pywinauto_app.window(handle=self.console_handle)
            
            # Map key names to pywinauto format
            key_map = {
                '1': '1',
                '2': '2', 
                '3': '3',
                'enter': '{ENTER}',
                'backspace': '{BACKSPACE}'
            }
            
            pywinauto_key = key_map.get(key, key)
            
            # Send key without focusing (type_keys works in background!)
            window.type_keys(pywinauto_key, with_spaces=False, set_foreground=False)
            
            return True
            
        except ImportError:
            # pywinauto not installed
            return False
        except Exception as e:
            if self.config.debug:
                print(f"pywinauto error (will try fallback): {e}")
            # Reset connection on error
            self.pywinauto_app = None
            return False
    
    def _send_key_with_postmessage(self, key: str) -> bool:
        """Fallback: Send key using PostMessage (less reliable)"""
        try:
            # Windows virtual key codes
            key_codes = {
                '1': 0x31,  # VK_1
                '2': 0x32,  # VK_2
                '3': 0x33,  # VK_3
                'enter': 0x0D,  # VK_RETURN
                'backspace': 0x08,  # VK_BACK
            }
            
            if key not in key_codes:
                return False
            
            vk_code = key_codes[key]
            
            # Send key press directly to window using PostMessage
            WM_KEYDOWN = 0x0100
            WM_KEYUP = 0x0101
            WM_CHAR = 0x0102
            
            # For character keys, send WM_CHAR which is simpler
            if key in ['1', '2', '3']:
                # Send character directly
                self.win32gui.PostMessage(self.console_handle, WM_CHAR, ord(key), 0)
            else:
                # For special keys, send key down and up
                self.win32gui.PostMessage(self.console_handle, WM_KEYDOWN, vk_code, 0)
                self.win32gui.PostMessage(self.console_handle, WM_KEYUP, vk_code, 0)
            
            return True
            
        except Exception as e:
            if self.config.debug:
                print(f"PostMessage error: {e}")
            return False
    
    def get_window_region(self) -> Optional[Tuple[int, int, int, int]]:
        """Get the region of the console window for screenshots"""
        if not self.platform_available:
            return None
        
        if self.platform == "Windows":
            return self._get_windows_region()
        
        return None
    
    def _get_windows_region(self) -> Optional[Tuple[int, int, int, int]]:
        """Get window region on Windows - captures only bottom 25% where prompts appear"""
        if not self.console_handle:
            window = self.find_console_window()
            if not window:
                return None
            self.console_handle = window.handle
        
        try:
            rect = self.win32gui.GetWindowRect(self.console_handle)
            left, top, right, bottom = rect
            width = right - left
            height = bottom - top
            
            # Capture only bottom 25% where prompts appear (like old script)
            prompt_height = min(300, int(height * 0.25))
            prompt_top = bottom - prompt_height - 50  # Move up 50px from bottom
            
            # Return region for bottom area only
            return (left + 5, prompt_top, width - 10, prompt_height)
        except Exception as e:
            print(f"Error getting window region: {e}")
            return None
    
    def minimize_window(self) -> bool:
        """Minimize the console window"""
        if not self.platform_available:
            return False
        
        if self.platform == "Windows" and self.console_handle:
            try:
                self.win32gui.ShowWindow(self.console_handle, self.win32con.SW_MINIMIZE)
                return True
            except:
                return False
        
        return False
    
    def restore_window(self) -> bool:
        """Restore the console window"""
        if not self.platform_available:
            return False
        
        if self.platform == "Windows" and self.console_handle:
            try:
                self.win32gui.ShowWindow(self.console_handle, self.win32con.SW_RESTORE)
                return True
            except:
                return False
        
        return False
    
    def is_window_focused(self) -> bool:
        """Check if console window is currently focused"""
        if not self.platform_available:
            return False
        
        if self.platform == "Windows" and self.console_handle:
            try:
                foreground = self.win32gui.GetForegroundWindow()
                return foreground == self.console_handle
            except:
                return False
        
        return False
    
    def ensure_window_ready(self) -> bool:
        """Ensure window is ready for interaction"""
        # Find window if needed
        if not self.console_handle:
            window = self.find_console_window()
            if not window:
                print("❌ Console window not found")
                return False
        
        # Focus window
        if not self.focus_console(force=True):
            print("❌ Failed to focus console window")
            return False
        
        # Wait a moment for focus
        time.sleep(0.5)
        
        # Verify focus
        if not self.is_window_focused():
            print("⚠️ Console window may not be focused")
            # Try once more
            self.focus_console(force=True)
            time.sleep(0.5)
        
        return True
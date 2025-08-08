"""
Retry logic with exponential backoff
Handles transient failures and error recovery
"""

import time
import functools
from typing import Any, Callable, Optional, Type, Tuple, Union
from dataclasses import dataclass


@dataclass
class RetryConfig:
    """Configuration for retry behavior"""
    max_attempts: int = 3
    initial_delay: float = 1.0
    max_delay: float = 60.0
    exponential_base: float = 2.0
    jitter: bool = True
    exceptions: Tuple[Type[Exception], ...] = (Exception,)


class RetryError(Exception):
    """Raised when all retry attempts fail"""
    def __init__(self, message: str, last_exception: Optional[Exception] = None):
        super().__init__(message)
        self.last_exception = last_exception


def calculate_backoff(attempt: int, config: RetryConfig) -> float:
    """Calculate backoff delay for given attempt"""
    delay = min(
        config.initial_delay * (config.exponential_base ** attempt),
        config.max_delay
    )
    
    if config.jitter:
        import random
        delay = delay * (0.5 + random.random())
    
    return delay


def retry_with_backoff(
    func: Optional[Callable] = None,
    *,
    max_attempts: int = 3,
    initial_delay: float = 1.0,
    max_delay: float = 60.0,
    exponential_base: float = 2.0,
    jitter: bool = True,
    exceptions: Tuple[Type[Exception], ...] = (Exception,),
    on_retry: Optional[Callable[[int, Exception], None]] = None,
    on_success: Optional[Callable[[Any], None]] = None,
    on_failure: Optional[Callable[[Exception], None]] = None
) -> Union[Callable, Any]:
    """
    Decorator/function for retrying with exponential backoff
    
    Can be used as decorator:
        @retry_with_backoff(max_attempts=5)
        def my_function():
            pass
    
    Or as function:
        result = retry_with_backoff(my_function, max_attempts=5)()
    """
    
    config = RetryConfig(
        max_attempts=max_attempts,
        initial_delay=initial_delay,
        max_delay=max_delay,
        exponential_base=exponential_base,
        jitter=jitter,
        exceptions=exceptions
    )
    
    def decorator(f: Callable) -> Callable:
        @functools.wraps(f)
        def wrapper(*args, **kwargs) -> Any:
            last_exception = None
            
            for attempt in range(config.max_attempts):
                try:
                    result = f(*args, **kwargs)
                    
                    # Success callback
                    if on_success:
                        on_success(result)
                    
                    return result
                    
                except config.exceptions as e:
                    last_exception = e
                    
                    # Check if this is the last attempt
                    if attempt == config.max_attempts - 1:
                        # Failure callback
                        if on_failure:
                            on_failure(e)
                        
                        raise RetryError(
                            f"Failed after {config.max_attempts} attempts",
                            last_exception
                        )
                    
                    # Calculate delay
                    delay = calculate_backoff(attempt, config)
                    
                    # Retry callback
                    if on_retry:
                        on_retry(attempt + 1, e)
                    
                    # Wait before retry
                    time.sleep(delay)
            
            # Should never reach here
            raise RetryError(
                f"Failed after {config.max_attempts} attempts",
                last_exception
            )
        
        return wrapper
    
    if func is None:
        # Called with arguments: @retry_with_backoff(...)
        return decorator
    else:
        # Called without arguments: @retry_with_backoff
        return decorator(func)


class TaskRetryManager:
    """Manages retry state for tasks"""
    
    def __init__(self, max_retries: int = 2):
        self.max_retries = max_retries
        self.retry_counts = {}
        self.retry_history = {}
    
    def should_retry(self, task_id: str) -> bool:
        """Check if task should be retried"""
        count = self.retry_counts.get(task_id, 0)
        return count < self.max_retries
    
    def record_attempt(self, task_id: str, error: Optional[str] = None):
        """Record a retry attempt"""
        self.retry_counts[task_id] = self.retry_counts.get(task_id, 0) + 1
        
        if task_id not in self.retry_history:
            self.retry_history[task_id] = []
        
        self.retry_history[task_id].append({
            'attempt': self.retry_counts[task_id],
            'timestamp': time.time(),
            'error': error
        })
    
    def get_retry_count(self, task_id: str) -> int:
        """Get current retry count for task"""
        return self.retry_counts.get(task_id, 0)
    
    def reset_task(self, task_id: str):
        """Reset retry count for task"""
        self.retry_counts.pop(task_id, None)
        self.retry_history.pop(task_id, None)
    
    def get_stats(self) -> dict:
        """Get retry statistics"""
        total_retries = sum(self.retry_counts.values())
        tasks_with_retries = len([c for c in self.retry_counts.values() if c > 0])
        
        return {
            'total_retries': total_retries,
            'tasks_with_retries': tasks_with_retries,
            'max_retries_used': max(self.retry_counts.values()) if self.retry_counts else 0,
            'retry_counts': dict(self.retry_counts)
        }


# Convenience functions
def retry_task(func: Callable, task_id: str, 
               retry_manager: TaskRetryManager,
               *args, **kwargs) -> Any:
    """Retry a task with managed state"""
    
    if not retry_manager.should_retry(task_id):
        raise RetryError(f"Task {task_id} exceeded max retries")
    
    def on_retry(attempt, error):
        print(f"⚠️ Retry {attempt}/{retry_manager.max_retries} for {task_id}: {error}")
        retry_manager.record_attempt(task_id, str(error))
    
    def on_success(result):
        print(f"✅ Task {task_id} succeeded after {retry_manager.get_retry_count(task_id)} retries")
        retry_manager.reset_task(task_id)
    
    def on_failure(error):
        print(f"❌ Task {task_id} failed after all retries: {error}")
    
    return retry_with_backoff(
        func,
        max_attempts=retry_manager.max_retries - retry_manager.get_retry_count(task_id) + 1,
        on_retry=on_retry,
        on_success=on_success,
        on_failure=on_failure
    )(*args, **kwargs)
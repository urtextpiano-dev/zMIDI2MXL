
/**
 * Feature Flags for Urtext Piano
 * 
 * Service-level feature flags for safe rollout of performance optimizations.
 * Flags can be controlled via URL parameters or localStorage for development/testing.
 */

interface FeatureFlags {
  /** Replace 50ms MIDI debounce with 10ms micro-batching */
  microBatching: boolean;
  /** Use pre-computed practice sequences instead of real-time OSMD traversal */
  preComputedSequence: boolean;
  /** Practice controller version: "auto" | "v1" | "v2" */
  practiceControllerVersion: "auto" | "v1" | "v2";
}

/**
 * Read feature flag from URL parameters or localStorage
 */
function readFromQueryOrLocalStorage(key: string, defaultValue: boolean): boolean {
  // Check URL parameters first (for testing)
  if (typeof window !== 'undefined') {
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.has(key)) {
      return urlParams.get(key) === 'true';
    }
    
    // Check localStorage for persistent overrides
    const stored = localStorage.getItem(`abc_piano_flag_${key}`);
    if (stored !== null) {
      return stored === 'true';
    }
  }
  
  return defaultValue;
}

/**
 * Read string feature flag from URL parameters or localStorage
 */
function readStringFromQueryOrLocalStorage<T extends string>(
  key: string, 
  defaultValue: T, 
  validValues: readonly T[]
): T {
  if (typeof window !== 'undefined') {
    // Check URL parameters first (for testing)
    const urlParams = new URLSearchParams(window.location.search);
    const urlValue = urlParams.get(key);
    if (urlValue && validValues.includes(urlValue as T)) {
      return urlValue as T;
    }
    
    // Check localStorage for persistent overrides
    const stored = localStorage.getItem(`abc_piano_flag_${key}`);
    if (stored && validValues.includes(stored as T)) {
      return stored as T;
    }
  }
  
  return defaultValue;
}

/**
 * Global feature flags instance
 */
export const Flags: FeatureFlags = {
  // Critical latency fixes (enabled by default for V2)
  microBatching: readFromQueryOrLocalStorage('mb', true),
  preComputedSequence: readFromQueryOrLocalStorage('pcs', true),
  
  // Controller version selection (v2 default - state machine with optimizations)
  practiceControllerVersion: readStringFromQueryOrLocalStorage('pcv', 'v2', ['auto', 'v1', 'v2'] as const),
};

/**
 * Debug helper to show current flag state
 */
export function logFeatureFlags(): void {
  console.group('[FeatureFlags] Current State');
  Object.entries(Flags).forEach(([key, value]) => {
    console.log(`  ${key}: ${value}`);
  });
  console.groupEnd();
}

/**
 * Enable a feature flag for testing (persists to localStorage)
 */
export function enableFlag(key: keyof FeatureFlags): void {
  if (typeof window !== 'undefined') {
    localStorage.setItem(`abc_piano_flag_${key}`, 'true');
    console.log(`[FeatureFlags] Enabled ${key} - reload page to take effect`);
  }
}

/**
 * Disable a feature flag for testing
 */
export function disableFlag(key: keyof FeatureFlags): void {
  if (typeof window !== 'undefined') {
    localStorage.removeItem(`abc_piano_flag_${key}`);
    console.log(`[FeatureFlags] Disabled ${key} - reload page to take effect`);
  }
}

// Expose to window for debugging (development only)
if (typeof window !== 'undefined' && process.env.NODE_ENV === 'development') {
  (window as any).abcFeatureFlags = {
    current: Flags,
    enable: enableFlag,
    disable: disableFlag,
    log: logFeatureFlags,
  };
}
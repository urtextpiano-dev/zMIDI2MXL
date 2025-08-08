# Isolated Function Testing

## Problem
The main ZMIDI2MXL project has compilation issues that prevent testing individual functions. The agent was trying to run `zig build test` on the broken project and making estimates instead of real measurements.

## Solution
Create isolated test environments for individual functions, completely separate from the main project's build issues.

## How It Works

### 1. Extract Function 
- Copy function and dependencies to isolated environment
- Include necessary types, structs, and imports
- Create standalone test file

### 2. Create Test Environment
- Minimal `build.zig` focused only on the function
- Real sample data for testing
- Unit tests to verify behavior  

### 3. Get Real Metrics
- **Line Count**: `wc -l test_runner.zig` → Exact numbers
- **Compilation Time**: `time zig build` → Real measurements
- **Test Results**: `zig build test` → Actual pass/fail counts
- **Function Output**: `zig build run` → Verify identical behavior

### 4. Apply & Verify Simplifications
- Modify function in isolated environment
- Compare exact before/after metrics
- Prove functional equivalence with real test data

## Example: parseAndValidate Function

```bash
$ cd isolated_function_tests/parseAndValidate_test/
$ zig build run
info: Testing parseAndValidate function in isolation...
info: Results:
info:   Tempo: 120 BPM
info:   Time Signature: 4/4
info:   Key: 0 fifths
info:   Measures: 2
info:   Notes: 4
info:   Rests: 1
info:   Chords: 1
info:   Has beams: true
info:   Has tuplets: false
info:   Has dynamics: false
info: ✅ Function test completed successfully!

$ zig build test
[No output - all tests passed]

$ wc -l test_runner.zig
248 test_runner.zig

$ time zig build
real	0m1.372s
```

## Benefits

### ✅ **Real Verification** (Not Estimates)
- **Before**: "~40% reduction estimated"  
- **After**: "248 lines → 180 lines (68 lines removed, 27.4% reduction measured)"

### ✅ **Actual Testing** (Not Build Failures)  
- **Before**: "Cannot test due to build system broken"
- **After**: "All 3 unit tests pass, output verified identical"

### ✅ **Independent of Main Project**
- **Before**: Blocked by compilation errors in unrelated files
- **After**: Function tests work regardless of main project state

### ✅ **Rapid Iteration**
- **Before**: Wait for entire project build (fails anyway)
- **After**: 1.3s compilation time for isolated function

## Usage for Agents

Agents should now:
1. Create isolated test environment in `isolated_function_tests/FUNCTION_NAME_test/`
2. Extract function with real test data
3. Measure baseline metrics
4. Apply simplifications
5. Measure modified metrics  
6. Compare real numbers, not estimates
7. Clean up after analysis

This provides **actual evidence** instead of **educated guesses** about function improvements.
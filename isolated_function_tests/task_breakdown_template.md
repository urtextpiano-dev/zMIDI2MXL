# Task Breakdown Template for Function Analysis

**Use TodoWrite to track function analysis with this exact breakdown:**

## Standard Task Breakdown for Any Function

```json
[
  {"content": "Create isolated test environment for [functionName] function", "status": "pending", "id": "create-isolated-env"},
  {"content": "Extract function dependencies ([list key dependencies])", "status": "pending", "id": "extract-deps"}, 
  {"content": "Create test cases with realistic data for [function purpose]", "status": "pending", "id": "create-test-cases"},
  {"content": "Get baseline metrics (compilation, tests, line count)", "status": "pending", "id": "get-baseline-metrics"},
  {"content": "Apply potential simplifications if found", "status": "pending", "id": "apply-simplifications"},
  {"content": "Compare before/after metrics", "status": "pending", "id": "compare-metrics"},
  {"content": "Document analysis results", "status": "pending", "id": "document-results"}
]
```

## Task Status Management Rules

**CRITICAL: Mark tasks completed IMMEDIATELY after finishing - never batch completions**

**Status Progression:**
- `pending` → `in_progress` → `completed`
- Only ONE task should be `in_progress` at any time
- Complete current task before starting next task
- Remove irrelevant tasks entirely if discovered during analysis

## Task Completion Criteria

**Task 1: Create isolated test environment**
✅ Completed when:
- Directory created: `/mnt/e/LearnTypeScript/zMIDI2MXL-main/isolated_function_tests/[functionName]_test/`
- `build.zig` created with correct function name
- Basic structure ready for testing

**Task 2: Extract function dependencies**  
✅ Completed when:
- All required structs/types identified using grep
- Dependencies copied to `test_runner.zig`
- Minimal mocks created for complex dependencies (allocators, etc.)
- Function compiles in isolation

**Task 3: Create test cases with realistic data**
✅ Completed when:
- Comprehensive test cases covering normal usage
- Edge cases included (empty inputs, boundary values)
- Test data matches actual function usage patterns
- Unit tests created and passing

**Task 4: Get baseline metrics**
✅ Completed when:
- `cmd.exe /c "zig build run"` executed successfully  
- `cmd.exe /c "zig build test"` executed (pass/fail recorded)
- `wc -l test_runner.zig` measured
- `time cmd.exe /c "zig build"` measured
- All outputs saved for comparison

**Task 5: Apply potential simplifications**
✅ Completed when:
- Function analyzed for improvement opportunities
- Simplifications applied (if any found) 
- Modified function maintains identical behavior for all test cases
- OR "No simplification needed" determined with evidence

**Task 6: Compare before/after metrics**
✅ Completed when:
- All baseline commands re-run on modified version
- Metrics compared line-by-line
- Functional equivalence verified
- Performance changes measured

**Task 7: Document analysis results**
✅ Completed when:
- Analysis report created using function_analysis_template.md
- Complete test outputs included as evidence
- Real metrics documented (no estimates)
- Test directory cleaned up after documentation

## Example: Actual Task Progression

**Function: countEnabled (6 lines, simple)**
1. ✅ "Create isolated test environment for countEnabled function"
2. ✅ "Extract function dependencies (FeatureFlags struct)" 
3. ✅ "Create test cases with realistic flag combinations"
4. ✅ "Get baseline metrics (compilation, tests, line count)"
5. ✅ "Apply simplification: @intFromBool arithmetic over manual counting"
6. ✅ "Compare before/after metrics"  
7. ✅ "Document analysis results with evidence package"

**Function: calculateBeatLength (27 lines, complex)**
1. ✅ "Create isolated test environment for calculateBeatLength function"
2. ✅ "Extract complex function dependencies (TimedNote, EducationalProcessor)" 
3. ✅ "Create test cases with realistic MIDI timing data"
4. ✅ "Analyze potential simplifications in algorithm"
5. ✅ "Apply simplifications: ArrayList → early return + switch statement"
6. ✅ "Compare before/after metrics"
7. ✅ "Document workflow and update agent definition"

## Task Management Best Practices

1. **Start with TodoWrite** - Create all tasks before beginning analysis
2. **Mark in_progress** - Before starting work on a task  
3. **Complete immediately** - As soon as task is finished
4. **One task at a time** - Never have multiple in_progress
5. **Update task names** - Add specifics as you learn more about the function
6. **Clean completion** - All tasks should be completed or explicitly removed

This systematic approach ensures nothing is forgotten and provides clear progress tracking through the analysis process.
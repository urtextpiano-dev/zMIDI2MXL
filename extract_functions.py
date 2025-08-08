#!/usr/bin/env python3
"""
ZMIDI2MXL Function Extraction Script

Systematically extracts all functions from the Zig codebase for simplification analysis.
Creates individual text files for each function with complete context and metadata.
"""

import os
import re
import json
from pathlib import Path
from typing import List, Dict, Tuple, Optional
import argparse

class ZigFunctionExtractor:
    def __init__(self, project_root: str, output_dir: str = "extracted_functions"):
        self.project_root = Path(project_root)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        
        # Function patterns for Zig
        self.function_patterns = [
            # Standard functions: pub fn name(...) type { ... }
            r'(pub\s+)?fn\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(',
            # Test functions: test "description" { ... }
            r'test\s+"([^"]+)"\s*\{',
        ]
        
        # Track extraction statistics
        self.stats = {
            'files_processed': 0,
            'functions_extracted': 0,
            'test_functions': 0,
            'errors': []
        }
    
    def find_zig_files(self) -> List[Path]:
        """Find all .zig files in the project, excluding build cache."""
        zig_files = []
        
        for root, dirs, files in os.walk(self.project_root):
            # Skip build cache and other generated directories
            dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'zig-out']
            
            for file in files:
                if file.endswith('.zig'):
                    file_path = Path(root) / file
                    zig_files.append(file_path)
        
        return sorted(zig_files)
    
    def extract_functions_from_file(self, file_path: Path) -> List[Dict]:
        """Extract all functions from a single Zig file."""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            self.stats['errors'].append(f"Could not read {file_path}: {e}")
            return []
        
        functions = []
        lines = content.split('\n')
        
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            
            # Check for function definitions
            function_match = self._match_function_start(line)
            if function_match:
                function_info = self._extract_complete_function(
                    lines, i, file_path, function_match
                )
                if function_info:
                    functions.append(function_info)
                    i = function_info['end_line']
                else:
                    i += 1
            else:
                i += 1
        
        return functions
    
    def _match_function_start(self, line: str) -> Optional[Dict]:
        """Check if line starts a function definition."""
        # Standard function pattern
        fn_match = re.match(r'(\s*)(pub\s+)?fn\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(', line)
        if fn_match:
            return {
                'type': 'function',
                'name': fn_match.group(3),
                'is_public': fn_match.group(2) is not None,
                'indentation': fn_match.group(1)
            }
        
        # Test function pattern
        test_match = re.match(r'(\s*)test\s+"([^"]+)"\s*\{', line)
        if test_match:
            return {
                'type': 'test',
                'name': f"test_{test_match.group(2).replace(' ', '_')}",
                'is_public': False,
                'indentation': test_match.group(1),
                'test_description': test_match.group(2)
            }
        
        return None
    
    def _extract_complete_function(self, lines: List[str], start_line: int, 
                                 file_path: Path, match_info: Dict) -> Optional[Dict]:
        """Extract complete function including signature and body."""
        try:
            # Find the opening brace
            brace_line = start_line
            opening_brace_found = False
            
            # Look for opening brace (might be on same line or subsequent lines)
            while brace_line < len(lines) and not opening_brace_found:
                if '{' in lines[brace_line]:
                    opening_brace_found = True
                    break
                brace_line += 1
            
            if not opening_brace_found:
                return None
            
            # Count braces to find function end
            brace_count = 0
            end_line = brace_line
            
            for i in range(brace_line, len(lines)):
                line = lines[i]
                # Count braces (handling strings and comments)
                in_string = False
                in_comment = False
                j = 0
                
                while j < len(line):
                    if not in_string and not in_comment:
                        if line[j:j+2] == '//':
                            in_comment = True
                            j += 2
                            continue
                        elif line[j] == '"' and (j == 0 or line[j-1] != '\\'):
                            in_string = True
                        elif line[j] == '{':
                            brace_count += 1
                        elif line[j] == '}':
                            brace_count -= 1
                            if brace_count == 0:
                                end_line = i
                                break
                    elif in_string:
                        if line[j] == '"' and (j == 0 or line[j-1] != '\\'):
                            in_string = False
                    j += 1
                
                if brace_count == 0:
                    break
            
            # Extract function content
            function_lines = lines[start_line:end_line + 1]
            function_content = '\n'.join(function_lines)
            
            # Get relative file path
            relative_path = file_path.relative_to(self.project_root)
            
            function_info = {
                'name': match_info['name'],
                'type': match_info['type'],
                'is_public': match_info['is_public'],
                'file_path': str(relative_path),
                'start_line': start_line + 1,  # 1-indexed for display
                'end_line': end_line + 1,
                'content': function_content,
                'signature': lines[start_line].strip(),
                'line_count': len(function_lines)
            }
            
            if match_info['type'] == 'test':
                function_info['test_description'] = match_info.get('test_description', '')
            
            return function_info
            
        except Exception as e:
            self.stats['errors'].append(f"Error extracting function at {file_path}:{start_line}: {e}")
            return None
    
    def save_function_file(self, function_info: Dict, index: int) -> str:
        """Save individual function to a text file."""
        # Create safe filename
        safe_name = re.sub(r'[^\w\-_\.]', '_', function_info['name'])
        filename = f"{index:04d}_{safe_name}_{function_info['file_path'].replace('/', '_').replace('.zig', '')}.txt"
        
        file_path = self.output_dir / filename
        
        # Create function analysis template
        content = f"""# Function Analysis: {function_info['name']}

## Metadata
- **File**: `{function_info['file_path']}`
- **Lines**: {function_info['start_line']}-{function_info['end_line']} ({function_info['line_count']} lines)
- **Type**: {function_info['type']}
- **Visibility**: {'public' if function_info['is_public'] else 'private'}
- **Signature**: `{function_info['signature']}`

## Function Content
```zig
{function_info['content']}
```

## Analysis Template (To be completed by simplification agent)

### Current Implementation Analysis
- **Purpose**: [Function's role in MIDI-to-MXL conversion]
- **Algorithm**: [How the function works]
- **Complexity**: [Time/space complexity, cyclomatic complexity]
- **Pipeline Role**: [Where this fits in the conversion pipeline]

### Simplification Opportunity
- **Proposed Change**: [Specific simplification identified]
- **Rationale**: [Why this simplification improves the code]
- **Complexity Reduction**: [Measurable improvement metrics]

### Evidence Package
- **Functional Proof**: [Demonstration of equivalence]
- **Performance Data**: [Before/after benchmarks if applicable]
- **Test Results**: [Validation of correctness]
- **Risk Assessment**: [Potential issues and mitigations]

### Recommendation
- **Confidence Level**: [0-100% with justification]
- **Implementation Priority**: [High/Medium/Low with reasoning]
- **Prerequisites**: [Dependencies or requirements]
"""
        
        if function_info['type'] == 'test':
            content += f"\n## Test Description\n{function_info.get('test_description', 'N/A')}\n"
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        return str(file_path)
    
    def create_manifest(self, all_functions: List[Dict]) -> str:
        """Create a manifest file for automation script consumption."""
        manifest_path = self.output_dir / "function_manifest.json"
        
        manifest = {
            'project_info': {
                'name': 'ZMIDI2MXL',
                'root_path': str(self.project_root),
                'extraction_timestamp': str(Path().cwd()),
            },
            'statistics': self.stats,
            'functions': []
        }
        
        for i, func in enumerate(all_functions):
            safe_name = re.sub(r'[^\w\-_\.]', '_', func['name'])
            filename = f"{i+1:04d}_{safe_name}_{func['file_path'].replace('/', '_').replace('.zig', '')}.txt"
            
            manifest['functions'].append({
                'index': i + 1,
                'name': func['name'],
                'file_path': func['file_path'],
                'function_file': filename,
                'type': func['type'],
                'is_public': func['is_public'],
                'line_count': func['line_count'],
                'start_line': func['start_line'],
                'end_line': func['end_line']
            })
        
        with open(manifest_path, 'w', encoding='utf-8') as f:
            json.dump(manifest, f, indent=2)
        
        return str(manifest_path)
    
    def extract_all_functions(self) -> Tuple[List[Dict], str]:
        """Main extraction process."""
        print(f"Extracting functions from: {self.project_root}")
        print(f"Output directory: {self.output_dir}")
        
        # Find all Zig files
        zig_files = self.find_zig_files()
        print(f"Found {len(zig_files)} Zig files")
        
        all_functions = []
        
        # Process each file
        for file_path in zig_files:
            print(f"Processing: {file_path.relative_to(self.project_root)}")
            
            functions = self.extract_functions_from_file(file_path)
            all_functions.extend(functions)
            
            self.stats['files_processed'] += 1
            self.stats['functions_extracted'] += len([f for f in functions if f['type'] == 'function'])
            self.stats['test_functions'] += len([f for f in functions if f['type'] == 'test'])
        
        # Save individual function files
        print(f"Saving {len(all_functions)} functions to individual files...")
        for i, function_info in enumerate(all_functions):
            self.save_function_file(function_info, i + 1)
        
        # Create manifest
        manifest_path = self.create_manifest(all_functions)
        
        # Print summary
        print(f"\n=== Extraction Complete ===")
        print(f"Files processed: {self.stats['files_processed']}")
        print(f"Functions extracted: {self.stats['functions_extracted']}")
        print(f"Test functions extracted: {self.stats['test_functions']}")
        print(f"Total extracted: {len(all_functions)}")
        print(f"Manifest created: {manifest_path}")
        
        if self.stats['errors']:
            print(f"Errors encountered: {len(self.stats['errors'])}")
            for error in self.stats['errors'][:5]:  # Show first 5 errors
                print(f"  - {error}")
        
        return all_functions, manifest_path

def main():
    parser = argparse.ArgumentParser(description="Extract functions from ZMIDI2MXL Zig codebase")
    parser.add_argument("--project-root", "-p", default=".", help="Project root directory")
    parser.add_argument("--output-dir", "-o", default="extracted_functions", help="Output directory")
    
    args = parser.parse_args()
    
    extractor = ZigFunctionExtractor(args.project_root, args.output_dir)
    functions, manifest = extractor.extract_all_functions()
    
    print(f"\nReady for simplification analysis!")
    print(f"Use the manifest file: {manifest}")

if __name__ == "__main__":
    main()
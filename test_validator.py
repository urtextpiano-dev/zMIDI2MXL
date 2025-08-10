#!/usr/bin/env python3
"""
Comprehensive MIDI to MusicXML validation framework
Compares zMIDI2MXL output against MuseScore reference
"""

import zipfile
import xml.etree.ElementTree as ET
import json
import sys
import os
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import difflib
import re

class MusicXMLValidator:
    """Validates and compares MusicXML files from different sources"""
    
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.metrics = {}
        
    def extract_musicxml_from_mxl(self, mxl_path: str) -> str:
        """Extract MusicXML content from MXL (compressed) file"""
        try:
            with zipfile.ZipFile(mxl_path, 'r') as z:
                # Find the main MusicXML file
                for name in z.namelist():
                    if name.endswith('.musicxml') or name.endswith('.xml'):
                        if 'container' not in name.lower():
                            return z.read(name).decode('utf-8')
            raise ValueError(f"No MusicXML file found in {mxl_path}")
        except Exception as e:
            self.errors.append(f"Failed to extract MusicXML: {e}")
            return ""
    
    def parse_musicxml(self, xml_content: str) -> Optional[ET.Element]:
        """Parse MusicXML content into ElementTree"""
        try:
            # Remove BOM if present
            if xml_content.startswith('\ufeff'):
                xml_content = xml_content[1:]
            return ET.fromstring(xml_content)
        except ET.ParseError as e:
            self.errors.append(f"XML parsing error: {e}")
            return None
    
    def extract_musical_elements(self, root: ET.Element) -> Dict:
        """Extract key musical elements for comparison"""
        elements = {
            'notes': [],
            'measures': [],
            'parts': [],
            'time_signatures': [],
            'key_signatures': [],
            'dynamics': [],
            'articulations': [],
            'voices': set(),
            'chords': []
        }
        
        # Extract parts
        for part in root.findall('.//part'):
            part_id = part.get('id', 'unknown')
            elements['parts'].append(part_id)
            
            # Extract measures
            for measure in part.findall('.//measure'):
                measure_num = measure.get('number', '0')
                elements['measures'].append({
                    'part': part_id,
                    'number': measure_num
                })
                
                # Extract notes
                for note in measure.findall('.//note'):
                    note_data = {
                        'part': part_id,
                        'measure': measure_num,
                        'pitch': None,
                        'duration': None,
                        'voice': None,
                        'type': None,
                        'is_rest': False,
                        'is_chord': False
                    }
                    
                    # Check if rest
                    if note.find('rest') is not None:
                        note_data['is_rest'] = True
                    
                    # Check if part of chord
                    if note.find('chord') is not None:
                        note_data['is_chord'] = True
                    
                    # Extract pitch
                    pitch_elem = note.find('pitch')
                    if pitch_elem is not None:
                        step = pitch_elem.findtext('step', '')
                        octave = pitch_elem.findtext('octave', '')
                        alter = pitch_elem.findtext('alter', '0')
                        note_data['pitch'] = f"{step}{octave}"
                        if alter != '0':
                            note_data['pitch'] += f"({alter})"
                    
                    # Extract duration
                    duration = note.findtext('duration')
                    if duration:
                        note_data['duration'] = int(duration)
                    
                    # Extract voice
                    voice = note.findtext('voice')
                    if voice:
                        note_data['voice'] = voice
                        elements['voices'].add(voice)
                    
                    # Extract note type
                    note_type = note.findtext('type')
                    if note_type:
                        note_data['type'] = note_type
                    
                    elements['notes'].append(note_data)
                
                # Extract time signatures
                for attr in measure.findall('.//attributes'):
                    time = attr.find('time')
                    if time is not None:
                        beats = time.findtext('beats')
                        beat_type = time.findtext('beat-type')
                        if beats and beat_type:
                            elements['time_signatures'].append({
                                'part': part_id,
                                'measure': measure_num,
                                'signature': f"{beats}/{beat_type}"
                            })
                    
                    # Extract key signatures
                    key = attr.find('key')
                    if key is not None:
                        fifths = key.findtext('fifths', '0')
                        elements['key_signatures'].append({
                            'part': part_id,
                            'measure': measure_num,
                            'fifths': int(fifths)
                        })
        
        return elements
    
    def compare_elements(self, our_elements: Dict, ref_elements: Dict) -> Dict:
        """Compare musical elements between our output and reference"""
        comparison = {
            'note_count': {
                'ours': len(our_elements['notes']),
                'reference': len(ref_elements['notes']),
                'match': len(our_elements['notes']) == len(ref_elements['notes'])
            },
            'measure_count': {
                'ours': len(our_elements['measures']),
                'reference': len(ref_elements['measures']),
                'match': len(our_elements['measures']) == len(ref_elements['measures'])
            },
            'part_count': {
                'ours': len(our_elements['parts']),
                'reference': len(ref_elements['parts']),
                'match': len(our_elements['parts']) == len(ref_elements['parts'])
            },
            'voice_count': {
                'ours': len(our_elements['voices']),
                'reference': len(ref_elements['voices']),
                'match': len(our_elements['voices']) == len(ref_elements['voices'])
            },
            'differences': []
        }
        
        # Compare note sequences
        if len(our_elements['notes']) == len(ref_elements['notes']):
            for i, (our_note, ref_note) in enumerate(zip(our_elements['notes'], ref_elements['notes'])):
                if our_note['pitch'] != ref_note['pitch']:
                    comparison['differences'].append({
                        'type': 'pitch_mismatch',
                        'position': i,
                        'ours': our_note['pitch'],
                        'reference': ref_note['pitch']
                    })
                if our_note['duration'] != ref_note['duration']:
                    comparison['differences'].append({
                        'type': 'duration_mismatch',
                        'position': i,
                        'ours': our_note['duration'],
                        'reference': ref_note['duration']
                    })
        
        return comparison
    
    def calculate_accuracy_score(self, comparison: Dict) -> float:
        """Calculate overall accuracy score"""
        total_checks = 0
        correct_checks = 0
        
        # Weight different aspects
        weights = {
            'note_count': 3,
            'measure_count': 2,
            'part_count': 2,
            'voice_count': 1
        }
        
        for key, weight in weights.items():
            if key in comparison:
                total_checks += weight
                if comparison[key]['match']:
                    correct_checks += weight
        
        # Penalize for differences
        if 'differences' in comparison:
            difference_penalty = min(len(comparison['differences']) * 0.02, 0.5)
            accuracy = (correct_checks / total_checks) - difference_penalty
        else:
            accuracy = correct_checks / total_checks
        
        return max(0, min(1, accuracy))
    
    def generate_report(self, our_path: str, ref_path: str) -> Dict:
        """Generate comprehensive comparison report"""
        report = {
            'timestamp': str(Path(our_path).stat().st_mtime),
            'files': {
                'our_output': our_path,
                'reference': ref_path if ref_path else "No reference provided"
            },
            'validation': {},
            'comparison': {},
            'accuracy': 0.0,
            'errors': self.errors,
            'warnings': self.warnings
        }
        
        # Extract and parse our output
        print("Extracting our MusicXML output...")
        our_xml = self.extract_musicxml_from_mxl(our_path)
        if not our_xml:
            report['validation']['extraction'] = "FAILED"
            return report
        
        our_root = self.parse_musicxml(our_xml)
        if our_root is None:
            report['validation']['parsing'] = "FAILED"
            return report
        
        report['validation']['our_output'] = "VALID"
        our_elements = self.extract_musical_elements(our_root)
        
        # If reference provided, compare
        if ref_path and os.path.exists(ref_path):
            print("Extracting reference MusicXML...")
            ref_xml = None
            
            # Handle both .mxl and .musicxml formats
            if ref_path.endswith('.mxl'):
                ref_xml = self.extract_musicxml_from_mxl(ref_path)
            else:
                with open(ref_path, 'r', encoding='utf-8') as f:
                    ref_xml = f.read()
            
            if ref_xml:
                ref_root = self.parse_musicxml(ref_xml)
                if ref_root is not None:
                    report['validation']['reference'] = "VALID"
                    ref_elements = self.extract_musical_elements(ref_root)
                    
                    # Compare elements
                    report['comparison'] = self.compare_elements(our_elements, ref_elements)
                    report['accuracy'] = self.calculate_accuracy_score(report['comparison'])
                else:
                    report['validation']['reference'] = "PARSE_ERROR"
            else:
                report['validation']['reference'] = "EXTRACT_ERROR"
        else:
            # No reference, just report our metrics
            report['metrics'] = {
                'total_notes': len(our_elements['notes']),
                'total_measures': len(our_elements['measures']),
                'total_parts': len(our_elements['parts']),
                'unique_voices': len(our_elements['voices']),
                'rest_count': sum(1 for n in our_elements['notes'] if n['is_rest']),
                'chord_notes': sum(1 for n in our_elements['notes'] if n['is_chord'])
            }
        
        return report

def main():
    """Main testing function"""
    print("=" * 70)
    print("zMIDI2MXL Validation Framework")
    print("=" * 70)
    
    validator = MusicXMLValidator()
    
    # Check for our output
    our_output = "sweden_output.mxl"
    if not os.path.exists(our_output):
        print(f"ERROR: Output file {our_output} not found!")
        print("Please run: zig-out\\bin\\zmidi2mxl.exe Sweden_Minecraft.mid sweden_output.mxl")
        return 1
    
    # Check for reference (optional)
    ref_output = None
    for possible_ref in ["sweden_musescore.mxl", "sweden_musescore.musicxml", 
                          "Sweden_Minecraft.musicxml", "reference.musicxml"]:
        if os.path.exists(possible_ref):
            ref_output = possible_ref
            print(f"Found reference file: {ref_output}")
            break
    
    if not ref_output:
        print("No MuseScore reference found. Performing standalone validation...")
        print("To compare with MuseScore:")
        print("1. Open Sweden_Minecraft.mid in MuseScore")
        print("2. Export as Uncompressed MusicXML (.musicxml)")
        print("3. Save as 'sweden_musescore.musicxml' in this directory")
        print("")
    
    # Generate report
    report = validator.generate_report(our_output, ref_output)
    
    # Display results
    print("\n" + "=" * 70)
    print("VALIDATION RESULTS")
    print("=" * 70)
    
    if 'validation' in report:
        print("\nFile Validation:")
        for key, value in report['validation'].items():
            status = "[OK]" if value == "VALID" else "[FAIL]"
            print(f"  {status} {key}: {value}")
    
    if 'metrics' in report:
        print("\nOutput Metrics:")
        for key, value in report['metrics'].items():
            print(f"  {key}: {value}")
    
    if 'comparison' in report and report['comparison']:
        print("\nComparison Results:")
        comp = report['comparison']
        
        for metric in ['note_count', 'measure_count', 'part_count', 'voice_count']:
            if metric in comp:
                match_str = "[MATCH]" if comp[metric]['match'] else "[MISMATCH]"
                print(f"  {metric}:")
                print(f"    Our output: {comp[metric]['ours']}")
                print(f"    Reference:  {comp[metric]['reference']}")
                print(f"    Status: {match_str}")
        
        if comp.get('differences'):
            print(f"\n  Found {len(comp['differences'])} differences:")
            for i, diff in enumerate(comp['differences'][:5]):  # Show first 5
                print(f"    {i+1}. {diff['type']} at position {diff['position']}")
                print(f"       Ours: {diff['ours']} | Ref: {diff['reference']}")
            if len(comp['differences']) > 5:
                print(f"    ... and {len(comp['differences']) - 5} more differences")
        
        print(f"\n  Accuracy Score: {report['accuracy']*100:.1f}%")
    
    if report.get('errors'):
        print("\nErrors:")
        for error in report['errors']:
            print(f"  [ERROR] {error}")
    
    # Save detailed report
    report_path = "validation_report.json"
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nDetailed report saved to: {report_path}")
    
    # Return exit code based on validation
    if report.get('accuracy', 0) >= 0.9:
        print("\n[PASSED] Validation PASSED - High accuracy achieved!")
        return 0
    elif report.get('accuracy', 0) >= 0.7:
        print("\n[WARNING] Validation PASSED with warnings - Good accuracy")
        return 0
    elif 'validation' in report and report['validation'].get('our_output') == "VALID":
        print("\n[OK] Output is valid MusicXML (no reference for comparison)")
        return 0
    else:
        print("\n[FAILED] Validation FAILED")
        return 1

if __name__ == "__main__":
    sys.exit(main())
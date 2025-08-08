#!/usr/bin/env python3
"""
Human-like thinking phrases for code analysis
Provides natural language expressions for different analysis scenarios
"""

import random
from typing import List, Dict


class AnalysisThinkingPhrases:
    """Collection of human-like phrases for code analysis."""
    
    def __init__(self):
        self.phrases = {
            "initial_reaction": [
                "Alright, let me take a look at this file...",
                "Okay, diving into {filename} now...",
                "Let's see what we have here in {filename}...",
                "Opening up {filename}. First impressions...",
                "Interesting, {filename} - let me examine this carefully...",
            ],
            
            "confusion": [
                "Wait a minute, why is this here?",
                "Hmm, this seems odd...",
                "Hold on, I'm not sure why we're doing this...",
                "This is confusing - let me think about this...",
                "Uh, this doesn't look right to me...",
                "Wait, what? Why would we...",
                "I'm puzzled by this approach...",
            ],
            
            "realization": [
                "Oh, I see what's happening here!",
                "Ah, now it makes sense...",
                "Actually, wait - I think I understand now...",
                "Oh! This is trying to...",
                "I get it now - this is for...",
                "Aha! This must be handling...",
            ],
            
            "concern": [
                "This could be a problem...",
                "I'm worried about this pattern...",
                "This might cause issues when...",
                "Ooh, this is risky because...",
                "This concerns me - what if...",
                "I'm not comfortable with this approach...",
                "This feels fragile to me...",
            ],
            
            "improvement": [
                "This could be simplified by...",
                "We could make this cleaner by...",
                "Actually, a better approach might be...",
                "What if we refactored this to...",
                "This would be more maintainable if...",
                "I think we could improve this by...",
                "Have we considered using...",
            ],
            
            "deep_examination": [
                "Let me examine this function more closely...",
                "Diving deeper into this logic...",
                "Let me trace through this step by step...",
                "Following the execution path here...",
                "Let me think through what happens when...",
                "Okay, so if I understand correctly...",
                "Walking through this code path...",
            ],
            
            "appreciation": [
                "Oh, this is actually quite clever!",
                "Nice! This is a clean approach to...",
                "I like how this handles...",
                "This is well-thought-out for...",
                "Good use of {pattern} here...",
                "This is elegantly solving...",
            ],
            
            "questioning": [
                "But why aren't we using {alternative}?",
                "Is there a reason we're not...",
                "I wonder if the author considered...",
                "What happens if {scenario}?",
                "Have we tested this with...",
                "Does this handle the case where...",
                "I'm curious why we chose...",
            ],
            
            "performance_concern": [
                "This might be expensive when...",
                "I'm seeing potential performance issues with...",
                "This could cause latency because...",
                "In the hot path, this might...",
                "With high load, this would...",
                "This allocation in a loop worries me...",
            ],
            
            "code_smell": [
                "This smells like {pattern} to me...",
                "I'm getting code smell vibes from...",
                "This feels like an anti-pattern...",
                "Red flag: {issue}",
                "This is textbook {anti_pattern}...",
                "Classic case of {problem} here...",
            ],
            
            "moving_on": [
                "Alright, moving on to the next section...",
                "Let's see what else we have...",
                "Continuing down the file...",
                "Next up, we have...",
                "Okay, now looking at...",
                "Scrolling further down...",
            ],
            
            "summary": [
                "So to summarize what I found here...",
                "Overall, this file...",
                "The main issues I'm seeing are...",
                "In conclusion for {filename}...",
                "Key takeaways from this analysis...",
            ]
        }
    
    def get_phrase(self, category: str, **kwargs) -> str:
        """Get a random phrase from a category with optional formatting."""
        if category not in self.phrases:
            return ""
        
        phrase = random.choice(self.phrases[category])
        return phrase.format(**kwargs)
    
    def get_analysis_sequence(self, filename: str) -> List[str]:
        """Get a natural sequence of phrases for analyzing a file."""
        return [
            self.get_phrase("initial_reaction", filename=filename),
            # Mix of reactions based on findings
            # These would be selected based on actual code analysis
        ]


# Example analysis narration patterns
ANALYSIS_NARRATION_EXAMPLES = """
# Example 1: Finding unnecessary complexity
"Let me take a look at MidiService.ts...

Oh, interesting architecture here. I see we're handling MIDI events in the main process and forwarding to renderer. Makes sense for security.

Wait a minute, why is this parsing logic so complex? We're doing... let me see... 5 different transformations on the MIDI data? 

*scrolling down*

Hmm, and then we're transforming it AGAIN in the renderer? This seems redundant. Let me trace through this...

Actually, hold on - I think we're duplicating effort here. The main process transforms the data, sends it via IPC, then the renderer transforms it again in almost the same way. This could definitely be simplified.

Let me check if there's a reason for this... *checking the git history*... Nope, looks like technical debt from parallel development."

# Example 2: Finding a potential bug
"Alright, diving into usePracticeController.ts now...

This is the core practice mode logic. Let me understand the flow... okay, so we're evaluating notes as they come in, comparing against expected notes, updating score...

*reading evaluateNote function*

Wait, what? We're using includes() to check if a note is correct? But this is an array of note objects, not primitives. This would always return false unless... 

Oh no, this is definitely a bug. We're comparing object references, not note values. This means practice mode would mark everything as incorrect!

Let me double-check this... yep, `expectedNotes` is an array of objects with {pitch, octave} but we're comparing with just a number. Classic JavaScript gotcha.

This needs to be fixed to compare the actual pitch values."

# Example 3: Finding over-engineering
"Let's see what we have here in AudioEngineFactory.ts...

Okay, so this is a factory for creating audio engines. We have... an interface, an abstract class, a factory class, and... wait, how many implementations do we have?

*searching for implementations*

Just one? We only have WebAudioEngine? 

So we built this entire factory pattern infrastructure for a single implementation? This is textbook YAGNI (You Aren't Gonna Need It). 

Unless there's a plan to add more audio engines... *checking TODOs and docs*... nope, nothing mentioned.

This could literally just be a direct instantiation. We're adding 3 layers of abstraction for no benefit. This is making the codebase harder to understand for new developers."
"""


def create_analysis_prompt(filename: str, step: str, analysis_type: str) -> str:
    """Create a natural analysis prompt for a specific file and step."""
    phrases = AnalysisThinkingPhrases()
    
    prompt = f"""
Analyze {filename} for {analysis_type}, step: {step}

Think out loud naturally as you work through the code. Use phrases like:
- "{phrases.get_phrase('confusion')}"
- "{phrases.get_phrase('realization')}"
- "{phrases.get_phrase('concern')}"
- "{phrases.get_phrase('improvement')}"

Describe what each function does as you read through it, question design decisions, 
and document any issues or improvements in a conversational way.
"""
    
    return prompt


if __name__ == "__main__":
    # Example usage
    phrases = AnalysisThinkingPhrases()
    
    print("Example thinking phrases:")
    print("\nInitial reaction:")
    print(f"- {phrases.get_phrase('initial_reaction', filename='test.ts')}")
    
    print("\nWhen confused:")
    print(f"- {phrases.get_phrase('confusion')}")
    
    print("\nWhen finding issues:")
    print(f"- {phrases.get_phrase('concern')}")
    
    print("\nWhen suggesting improvements:")
    print(f"- {phrases.get_phrase('improvement')}")
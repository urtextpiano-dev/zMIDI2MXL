    fn validateAndResolveBeamTupletConflicts(
        self: *EducationalProcessor,
        enhanced_notes: []EnhancedTimedNote
    ) EducationalProcessingError!void {
        // Single pass to check if validation is needed
        var needs_validation = false;
        for (enhanced_notes) |note| {
            const has_tuplet = note.tuplet_info != null and note.tuplet_info.?.tuplet != null;
            const has_beam = note.beaming_info != null;
            if (has_tuplet and has_beam) {
                needs_validation = true;
                break;
            }
        }
        if (!needs_validation) return;
        
        // Build tuplet spans - single error handling point
        const tuplet_spans = self.buildTupletSpans(enhanced_notes) catch 
            return EducationalProcessingError.AllocationFailure;
        defer self.arena.allocator().free(tuplet_spans);
        if (tuplet_spans.len == 0) return;
        
        // Build beam groups - single error handling point  
        const beam_groups = self.buildBeamGroups(enhanced_notes) catch
            return EducationalProcessingError.AllocationFailure;
        defer self.arena.allocator().free(beam_groups);
        
        // Process beam groups for conflicts
        for (beam_groups) |group| {
            if (group.notes.len < 2) continue;
            
            const crosses_boundary = self.beamCrossesTupletBoundary(group, tuplet_spans);
            const needs_consistency = !self.validateBeamConsistencyInTuplet(group, tuplet_spans);
            
            if (crosses_boundary) {
                self.resolveBeamTupletConflict(group.notes, tuplet_spans) catch
                    return EducationalProcessingError.CoordinationConflict;
                self.metrics.coordination_conflicts_resolved += 1;
            }
            
            if (needs_consistency) {
                self.adjustBeamingForTupletConsistency(group.notes) catch
                    return EducationalProcessingError.CoordinationConflict;
                self.metrics.coordination_conflicts_resolved += 1;
            }
        }
        
        // Handle special cases - errors already caught internally
        self.handlePartialTuplets(enhanced_notes, tuplet_spans) catch {};
        self.handleNestedGroupings(enhanced_notes, tuplet_spans, beam_groups) catch {};
        self.ensureTupletBeamConsistency(enhanced_notes, tuplet_spans) catch {};
    }
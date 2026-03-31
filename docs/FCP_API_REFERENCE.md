# Final Cut Pro Internal API Reference

This reference documents the key ObjC classes, methods, and patterns inside Final Cut Pro
that are accessible through FCPBridge. You do NOT need the decompiled source to use this --
the bridge discovers everything at runtime via the ObjC runtime.

Use `explore_class("ClassName")` or `search_methods("ClassName", "keyword")` to discover
more methods beyond what's documented here.

---

## Class Hierarchy & Navigation

```
NSApplication.sharedApplication
  └─ delegate (PEAppController)
       ├─ activeEditorContainer (PEEditorContainerModule)
       │    ├─ timelineModule (FFAnchoredTimelineModule) ← main editing interface
       │    │    └─ sequence (FFAnchoredSequence) ← timeline data model
       │    │         └─ primaryObject (FFAnchoredCollection) ← the spine
       │    │              └─ containedItems (NSArray of clips/transitions)
       │    └─ editorModule (FFEditorModule)
       └─ _targetLibrary (FFLibrary)
            ├─ events (NSArray of FFEventRecord)
            ├─ _deepLoadedSequences (NSSet of FFAnchoredSequence)
            └─ libraryDocument (PEDocument / FFLibraryDocument)
                 └─ undoManager (FFUndoManager)
```

---

## FFAnchoredTimelineModule (1,435 methods)

The main editing interface. Most timeline_action() calls route here.

### Blade / Split
| Method | Args | Description |
|--------|------|-------------|
| `blade:` | sender | Split clip at playhead |
| `bladeAll:` | sender | Split all clips at playhead |

### Markers
| Method | Args | Description |
|--------|------|-------------|
| `addMarker:` | sender | Add standard marker at playhead |
| `addAndEditMarker:` | sender | Add marker and open editor |
| `addTodoMarker:` | sender | Add todo/incomplete marker |
| `addChapterMarker:` | sender | Add chapter marker |
| `deleteMarker:` | sender | Delete marker at playhead |
| `nextMarker:` | sender | Navigate to next marker |
| `previousMarker:` | sender | Navigate to previous marker |

### Transitions
| Method | Args | Description |
|--------|------|-------------|
| `addTransition:` | sender | Add default transition at edit point |

### Selection
| Method | Args | Description |
|--------|------|-------------|
| `selectAll:` | sender | Select all items |
| `deselectAll:` | sender | Clear selection |
| `selectClipAtPlayhead:` | sender | Select clip under playhead |
| `selectToPlayhead:` | sender | Extend selection to playhead |
| `selectedItems:includeItemBeforePlayheadIfLast:` | BOOL, BOOL | Get selected items array |

### Navigation
| Method | Args | Description |
|--------|------|-------------|
| `nextEdit:` | sender | Move to next edit point |
| `previousEdit:` | sender | Move to previous edit point |
| `playheadTime` | (none) | Get current playhead position (CMTime) |
| `setPlayheadTime:` | CMTime | Set playhead position |
| `committedPlayheadTime` | (none) | Get committed playhead time |
| `currentSequenceTime` | (none) | Get sequence-relative time |

### Color Correction
| Method | Args | Description |
|--------|------|-------------|
| `addColorBoardEffect:` | sender | Add Color Board to selected clip |
| `addColorWheelsEffect:` | sender | Add Color Wheels |
| `addColorCurvesEffect:` | sender | Add Color Curves |
| `addColorAdjustmentEffect:` | sender | Add Color Adjustments |
| `addHueSaturationEffect:` | sender | Add Hue/Saturation Curves |
| `addEnhanceLightAndColorEffect:` | sender | Add auto enhance |

### Effects
| Method | Args | Description |
|--------|------|-------------|
| `addEffectToStacks:effectID:actionName:` | items, NSString, NSString | Add effect by ID |
| `addDefaultVideoEffect:` | sender | Add default video effect |
| `addDefaultAudioEffect:` | sender | Add default audio effect |

### Volume
| Method | Args | Description |
|--------|------|-------------|
| `adjustVolumeRelative:` | sender | Increase volume |
| `adjustVolumeAbsolute:` | sender | Decrease volume |

### Titles
| Method | Args | Description |
|--------|------|-------------|
| `addBasicTitle:` | sender | Add basic title |
| `addBasicLowerThird:` | sender | Add lower third title |

### Speed / Retiming
| Method | Args | Description |
|--------|------|-------------|
| `retimeNormal:` | sender | Reset to normal speed |
| `retimeFastx2:` | sender | 2x fast |
| `retimeFastx4:` | sender | 4x fast |
| `retimeFastx8:` | sender | 8x fast |
| `retimeFastx20:` | sender | 20x fast |
| `retimeSlowHalf:` | sender | 50% slow |
| `retimeSlowQuarter:` | sender | 25% slow |
| `retimeSlowTenth:` | sender | 10% slow |
| `retimeReverse:` | sender | Reverse clip |
| `retimeHoldFromSelection:` | sender | Hold frame from selection |
| `retimeBladeSpeed:` | sender | Blade speed segment |
| `freezeFrame:` | sender | Create freeze frame |

### Keyframes
| Method | Args | Description |
|--------|------|-------------|
| `addKeyframe:` | sender | Add keyframe at playhead |
| `deleteKeyframes:` | sender | Delete selected keyframes |
| `nextKeyframe:` | sender | Navigate to next keyframe |
| `previousKeyframe:` | sender | Navigate to previous keyframe |

### Clip Operations
| Method | Args | Description |
|--------|------|-------------|
| `delete:` | sender | Delete selected clips |
| `cut:` | sender | Cut to clipboard |
| `copy:` | sender | Copy to clipboard |
| `paste:` | sender | Paste from clipboard |
| `trimToPlayhead:` | sender | Trim clip edge to playhead |
| `soloSelectedClips:` | sender | Solo selected clips |
| `disableSelectedClips:` | sender | Disable selected clips |
| `createCompoundClip:` | sender | Create compound from selection |
| `autoReframe:` | sender | Auto-reframe selected clip |

### Export
| Method | Args | Description |
|--------|------|-------------|
| `exportXML:` | sender | Export FCPXML |
| `shareSelection:` | sender | Open share dialog |

### Sequence Access
| Method | Args | Description |
|--------|------|-------------|
| `sequence` | (none) | Get the FFAnchoredSequence |
| `sequenceFrameDuration` | (none) | Get frame duration (CMTime) |

---

## FFAnchoredSequence (1,074 methods)

Timeline data model. Contains all clips, transitions, effects.

### Content Access
| Method | Args | Description |
|--------|------|-------------|
| `primaryObject` | (none) | Get the spine (FFAnchoredCollection) |
| `containedItems` | (none) | Get items (call on primaryObject, not sequence) |
| `allContainedItems` | (none) | Get all items recursively |
| `hasContainedItems` | (none) | Check if has content |
| `displayName` | (none) | Get sequence/project name |
| `duration` | (none) | Get total duration (CMTime) |

### Editing Transactions (required for undo/redo)
| Method | Args | Description |
|--------|------|-------------|
| `actionBeginEditing` | (none) | Start edit transaction |
| `actionEnd:save:error:` | name, BOOL, NSError** | End transaction |
| `performActionWithName:error:usingBlock:` | NSString, NSError**, block | Transaction wrapper |
| `hasOpenTimelineTransaction` | (none) | Check if transaction open |

### Properties
| Property | Type | Description |
|----------|------|-------------|
| `renderFormat` | id | Render format settings |
| `audioChannelCount` | int | Number of audio channels |
| `project` | id | Parent project reference |
| `actionBeginHooks` | id | Pre-action hooks |
| `actionEndHooks` | id | Post-action hooks |

---

## FFLibrary (203 methods)

Container for all media, events, and projects.

### Access
| Method | Args | Description |
|--------|------|-------------|
| `events` | (none) | Get all FFEventRecord objects |
| `_deepLoadedSequences` | (none) | Get all loaded sequences (NSSet) |
| `displayName` | (none) | Library name |
| `libraryDocument` | (none) | Get PEDocument |
| `event` | (none) | Get default event |
| `eventForName:` | NSString | Find event by name |
| `eventForIdentifier:` | id | Find event by ID |

### Modification
| Method | Args | Description |
|--------|------|-------------|
| `insertNewSequence:name:error:` | id, NSString, NSError** | Create new project |
| `insertNewEvent:name:error:` | id, NSString, NSError** | Create new event |

### Roles
| Method | Args | Description |
|--------|------|-------------|
| `mainRoles` | (none) | Get all roles |
| `findRoleWithUID:` | NSString | Find role by ID |

---

## FFLibraryDocument / PEDocument (231 methods)

Library file management and undo/redo.

### Class Methods
| Method | Args | Description |
|--------|------|-------------|
| `+copyActiveLibraries` | (none) | Get all open libraries (NSArray) |
| `+isAnyLibraryUpdating` | (none) | Check if any library updating |
| `+openDocumentWithoutDisplay:error:` | NSURL, NSError** | Open library file |

### Instance Methods
| Method | Args | Description |
|--------|------|-------------|
| `undoManager` | (none) | Get FFUndoManager for undo/redo |
| `library` | (none) | Get FFLibrary instance |
| `fileURL` | (none) | Get library file path |
| `close` | (none) | Close library |

---

## FFEditActionMgr (42 methods)

Command pattern for insert/append/overwrite edits.

### Edit Operations
| Method | Args | Description |
|--------|------|-------------|
| `insertWithSelectedMedia:` | sender | Insert at playhead |
| `insertWithSelectedMediaVideo:` | sender | Insert video only |
| `insertWithSelectedMediaAudio:` | sender | Insert audio only |
| `appendWithSelectedMedia:` | sender | Append to end |
| `appendWithSelectedMediaUp:` | sender | Append to track above |
| `appendWithSelectedMediaDown:` | sender | Append to track below |
| `overwriteWithSelectedMedia:` | sender | Overwrite at playhead |
| `anchorWithSelectedMedia:` | sender | Connect/anchor clip |
| `replaceWithSelectedMediaWhole:` | sender | Replace entire clip |
| `replaceWithSelectedMediaAtPlayhead:` | sender | Replace from playhead |
| `freezeFrame:` | sender | Create freeze frame |

### Validation
| Method | Args | Description |
|--------|------|-------------|
| `canPerformEditAction:withMenuItem:withSource:resultData:` | action, menuItem, source, data | Check if valid |
| `performEditAction:` | action | Execute edit action |

---

## PEEditorContainerModule

Editor container managing timeline and player modules.

| Method | Args | Description |
|--------|------|-------------|
| `timelineModule` | (none) | Get FFAnchoredTimelineModule |
| `editorModule` | (none) | Get FFEditorModule |
| `loadEditorForSequence:` | FFAnchoredSequence | Open project in timeline |
| `loadEditorForLastOpenSequence` | (none) | Reopen last project |
| `playPause:` | sender | Toggle playback |
| `playheadSequenceTime` | (none) | Get playhead time |

---

## FFPlayerModule

Player UI with playback controls.

| Method | Args | Description |
|--------|------|-------------|
| `gotoStart:` | sender | Jump to beginning |
| `gotoEnd:` | sender | Jump to end |
| `stepForward:` | sender | Advance one frame |
| `stepBackward:` | sender | Go back one frame |
| `stepForward10Frames:` | sender | Advance 10 frames |
| `stepBackward10Frames:` | sender | Go back 10 frames |
| `playAroundCurrentFrame:` | sender | Play around current position |

---

## FFEffectStack

Effect container on clips.

| Method | Args | Description |
|--------|------|-------------|
| `effects` | (none) | Get all effects (NSArray) |
| `addEffect:` | FFEffect | Add effect |
| `addEffectWithID:` | NSString | Add effect by ID |
| `removeEffect:` | FFEffect | Remove effect |
| `effectCount` | (none) | Count of effects |
| `effectAtIndex:` | NSUInteger | Get effect by index |
| `effectForEffectID:` | NSString | Find effect by ID |
| `colorCorrectionEffects` | (none) | Get color correction effects |

---

## FFEventRecord

Container for clips and projects within a library.

| Method | Args | Description |
|--------|------|-------------|
| `sequenceRecords` | (none) | Get projects in this event |
| `displayOwnedClips` | (none) | Get media clips |
| `countOfSequenceRecords` | (none) | Number of projects |
| `hasSequenceRecords` | (none) | Has any projects |

---

## Timeline Item Classes

All items in the timeline spine inherit from FFAnchoredObject:

| Class | Description |
|-------|-------------|
| `FFAnchoredMediaComponent` | Video/audio clip in timeline |
| `FFAnchoredTransition` | Transition between clips (Cross Dissolve, etc.) |
| `FFAnchoredGapGeneratorComponent` | Gap/placeholder |
| `FFAnchoredCollection` | Container (storyline, spine) |
| `FFAnchoredClip` | Clip reference |
| `FFAnchoredCaption` | Caption/subtitle |
| `FFAnchoredMarker` | Marker |
| `FFAnchoredKeywordMarker` | Keyword marker |
| `FFAnchoredChapterMarker` | Chapter marker |

### Common Properties on Timeline Items
| Property | Type | Description |
|----------|------|-------------|
| `displayName` | NSString | Item name |
| `duration` | CMTime | Item duration |
| `mediaType` | int | Media type (1=video, 2=audio) |
| `anchoredLane` | int | Lane index (0=spine) |
| `effectStack` | FFEffectStack | Effects on this item |
| `effects` | NSArray | Shortcut to effects |
| `enabled` | BOOL | Is item enabled |

---

## Key Notifications

Observable via NSNotificationCenter:

| Notification | When |
|-------------|------|
| `FFTimelineDidChangeNotification` | Timeline content modified |
| `FFSequenceEditedNotification` | Sequence was edited |
| `FFTimelineSelectionManagerDidChange` | Selection changed |
| `FFEffectsChangedNotification` | Any effect changed |
| `FFEffectStackChangedNotification` | Effect stack modified |
| `FFLibraryUpdateBeginNotification` | Library update starting |
| `FFLibraryUpdateEndNotification` | Library update complete |
| `FFPlayerDidBeginPlaybackNotification` | Playback started |
| `FFPlayerDidEndPlaybackNotification` | Playback stopped |
| `FFProjectAssetsChangedNotification` | Project media changed |
| `FFRolesInLibraryDidChange` | Roles modified |
| `FFAssetMediaChangedNotification` | Source media changed |

---

## CMTime Structure

FCP uses Apple's CMTime for all time values:

```
CMTime {
    int64_t value;       // Frame count (numerator)
    int32_t timescale;   // Frames per second (denominator)
    uint32_t flags;      // 1 = valid
    int64_t epoch;       // Usually 0
}
```

Seconds = value / timescale. For 24fps: timescale=24, value=48 = 2.0 seconds.

In JSON-RPC calls, pass CMTime as: `{"type":"cmtime","value":{"value":48,"timescale":24}}`

---

## Common Patterns

### Opening a Project
```
FFLibraryDocument.copyActiveLibraries → array
array.objectAtIndex:0 → FFLibrary
library._deepLoadedSequences → NSSet
set.allObjects → array of FFAnchoredSequence
sequence.hasContainedItems → check for content
NSApp.delegate.activeEditorContainer.loadEditorForSequence: → load it
```

### Reading Timeline State
```
timelineModule.sequence → FFAnchoredSequence
sequence.primaryObject → FFAnchoredCollection (spine)
spine.containedItems → NSArray of clips/transitions
timelineModule.playheadTime → CMTime
timelineModule.selectedItems:includeItemBeforePlayheadIfLast: → selection
```

### Performing Edits
Most edits are IBAction methods (take nil sender):
```
timelineModule.blade:(nil)
timelineModule.addMarker:(nil)
timelineModule.addColorBoardEffect:(nil)
```

### Undo / Redo
Route through FFLibraryDocument's undoManager:
```
library.libraryDocument.undoManager.undo
library.libraryDocument.undoManager.redo
library.libraryDocument.undoManager.canUndo → BOOL
library.libraryDocument.undoManager.undoActionName → NSString
```

### Inspecting Effects
```
clip.effectStack → FFEffectStack
effectStack.effects → NSArray
effectStack.effectCount → int
effectStack.effectAtIndex:0 → FFEffect
effect.displayName → name
effect.effectID → identifier string
```

# FCPBridge - Programmatic Final Cut Pro Control

## Architecture

FCPBridge is an ObjC dylib injected into FCP's process. It exposes the full ObjC runtime
(78,000+ classes) via a JSON-RPC server on TCP `127.0.0.1:9876`. The MCP server wraps this
into Claude-friendly tools.

## Workflow

### 1. Check connection
```
bridge_status()
```

### 2. Read timeline state
```
get_timeline_clips()     -- structured table of all clips with handles
get_selected_clips()     -- just the selection
verify_action("before")  -- snapshot for before/after comparison
```

### 3. Perform edits
```
timeline_action("blade")               -- blade at playhead
timeline_action("addMarker")           -- add marker
timeline_action("addTransition")       -- add default transition
timeline_action("addColorBoard")       -- add color board to selected clip
timeline_action("addBasicTitle")       -- add title
timeline_action("retimeSlow50")        -- slow motion 50%
timeline_action("freezeFrame")         -- freeze frame
playback_action("goToStart")           -- navigate
playback_action("nextFrame")           -- step forward
```

### 4. Verify
```
verify_action("after")  -- compare with before snapshot
```

## All Timeline Actions

### Blade/Split
blade, bladeAll

### Markers
addMarker, addTodoMarker, addChapterMarker, deleteMarker, nextMarker, previousMarker

### Transitions
addTransition

### Navigation
nextEdit, previousEdit, selectClipAtPlayhead, selectToPlayhead

### Selection
selectAll, deselectAll

### Edit Operations
delete, cut, copy, paste, undo, redo

### Insert
insertGap

### Trim
trimToPlayhead

### Color Correction
addColorBoard, addColorWheels, addColorCurves, addColorAdjustment, addHueSaturation, addEnhanceLightAndColor

### Volume
adjustVolumeUp, adjustVolumeDown

### Titles
addBasicTitle, addBasicLowerThird

### Speed/Retiming
retimeNormal, retimeFast2x, retimeFast4x, retimeFast8x, retimeFast20x,
retimeSlow50, retimeSlow25, retimeSlow10, retimeReverse, retimeHold,
freezeFrame, retimeBladeSpeed

### Keyframes
addKeyframe, deleteKeyframes, nextKeyframe, previousKeyframe

### Other
solo, disable, createCompoundClip, autoReframe, exportXML, shareSelection, addVideoGenerator

## Playback Actions
playPause, goToStart, goToEnd, nextFrame, prevFrame, nextFrame10, prevFrame10

## Object Handle Pattern
For advanced operations, use handles to chain calls:
```
# Get libraries as a handle
libs = call_method_with_args("FFLibraryDocument", "copyActiveLibraries", return_handle=True)
# Navigate: array -> library -> events
lib = call_method_with_args("obj_1", "objectAtIndex:", '[{"type":"int","value":0}]', false, true)
# Read properties
get_object_property("obj_2", "displayName")
```

## Calling Methods With Arguments
```
call_method_with_args(
    target="obj_5",                       # class name or handle
    selector="objectAtIndex:",
    args='[{"type":"int","value":0}]',
    class_method=False,
    return_handle=True
)
```
Argument types: string, int, double, float, bool, nil, sender, handle, cmtime, selector

## FCPXML Import (No Restart Required)
Generate FCPXML and import into the running FCP instance:
```
# Generate FCPXML with gaps and titles
xml = generate_fcpxml(
    project_name="My Project",
    generators='[{"type":"gap","duration":10},{"type":"title","text":"Hello","duration":5}]'
)
# Import it (uses internal PEAppController method - no restart)
import_fcpxml(xml, internal=True)
```

## Effects Inspection
```
# Get effects on selected clip
get_clip_effects()
# Get effects on a specific clip by handle
get_clip_effects("obj_3")
```

## Opening a Project Programmatically
```python
# Navigate: library -> sequences -> find project -> load it
libs = call_method_with_args("FFLibraryDocument", "copyActiveLibraries", return_handle=True)
lib = call_method_with_args(libs_handle, "objectAtIndex:", '[{"type":"int","value":0}]', false, true)
seqs = call_method_with_args(lib_handle, "_deepLoadedSequences", "[]", false, true)
allSeqs = call_method_with_args(seqs_handle, "allObjects", "[]", false, true)
# Get sequence by index
seq = call_method_with_args(allSeqs_handle, "objectAtIndex:", '[{"type":"int","value":0}]', false, true)
# Load it into the timeline
app = call_method_with_args("NSApplication", "sharedApplication", "[]", true, true)
delegate = call_method_with_args(app_handle, "delegate", "[]", false, true)
container = call_method_with_args(delegate_handle, "activeEditorContainer", "[]", false, true)
call_method_with_args(container_handle, "loadEditorForSequence:", '[{"type":"handle","value":"seq_handle"}]', false)
```

## Key FCP Classes

| Class | Methods | Use |
|-------|---------|-----|
| FFAnchoredTimelineModule | 1435 | Timeline editing, blade, markers, selection, effects |
| FFAnchoredSequence | 1074 | Timeline data model, clips, structure |
| FFAnchoredObject | base | All timeline items (clips, gaps, transitions) |
| FFAnchoredClip | - | Video/audio clips |
| FFAnchoredMediaComponent | - | Media components in timeline |
| FFAnchoredTransition | - | Transitions between clips |
| FFLibrary | 203 | Library container, events, projects |
| FFLibraryDocument | 231 | Library persistence |
| FFEditActionMgr | 42 | Edit commands (insert, append, overwrite) |
| FFPlayer | 228 | Playback engine |
| FFEffectStack | - | Effect management on clips |
| FFProOSC | - | Transform/position/scale/rotation |
| PEAppController | 484 | App controller, windows |
| PEEditorContainerModule | - | Editor container, timeline/player modules |

## Timeline Data Model
FCP uses a spine-based model:
```
FFAnchoredSequence
  -> primaryObject (FFAnchoredCollection = the spine)
    -> containedItems (array of FFAnchoredMediaComponent, FFAnchoredTransition, etc.)
```
The `get_timeline_clips()` tool handles this automatically.

## Error Recovery
- "No active timeline module" -> No project open. Load a project via handle chain.
- "No responder handled X" -> Action not available in current state.
- "Handle not found" -> Object was released. Get fresh reference.
- "Cannot connect" -> FCP not running or bridge not loaded.
- Connection reset -> MCP server auto-reconnects on next call.

## Undo/Redo
Undo/redo routes through the document's `FFUndoManager` (not the responder chain).
Returns the action name for verification:
```
timeline_action("undo")  # -> {"action": "undo", "status": "ok", "actionName": "Blade"}
```

## Editing Safety
- timeline_action() methods go through FCP's normal action/undo system
- set_object_property() bypasses undo -- use only for non-undoable changes
- Always verify edits with get_timeline_clips() or verify_action()

## Discovering New APIs
```
get_classes(filter="FFColor")           -- find classes by prefix
explore_class("FFColorCorrectionEffect") -- full class overview
search_methods("FFAnchoredTimelineModule", "color") -- find methods by keyword
get_methods("FFEffectStack")            -- complete method listing
```

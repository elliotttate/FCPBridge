# SpliceKit - Programmatic Final Cut Pro Control

SpliceKit is an ObjC dylib injected into FCP's process. It exposes all 78,000+ ObjC classes
via a JSON-RPC server on TCP 127.0.0.1:9876. Everything is fully programmatic -- no AppleScript,
no UI automation, no menu clicks.

## Quick Start

```
1. bridge_status()                    -- verify connection
2. get_timeline_clips()               -- see timeline contents
3. timeline_action("blade")           -- edit
4. verify_action("after blade")       -- confirm
```

## CRITICAL: Must Know Before Editing

### Opening a Project
If `get_timeline_clips()` returns an error about "no sequence", load a project:
```python
# Navigate: library -> sequences -> find one with content -> load it
libs = call_method_with_args("FFLibraryDocument", "copyActiveLibraries", "[]", true, true)
lib = call_method_with_args(libs_handle, "objectAtIndex:", '[{"type":"int","value":0}]', false, true)
seqs = call_method_with_args(lib_handle, "_deepLoadedSequences", "[]", false, true)
allSeqs = call_method_with_args(seqs_handle, "allObjects", "[]", false, true)
# Check each: call_method_with_args(seq_handle, "hasContainedItems", "[]", false)
# Load: get NSApp -> delegate -> activeEditorContainer -> loadEditorForSequence:
```

### Select Before Acting
Color correction, retiming, titles, and effects require a selected clip:
```
playback_action("goToStart")              # position
playback_action("nextFrame") x N          # navigate
timeline_action("selectClipAtPlayhead")   # select
timeline_action("addColorBoard")          # now apply
```

### Playhead Positioning
- 1 frame = ~0.042s at 24fps, ~0.033s at 30fps
- Use `nextFrame` with repeat count for precise positioning
- `batch_timeline_actions` is fastest for multi-step sequences
- Always go to a known position (goToStart) before stepping

### Undo After Mistakes
```
timeline_action("undo")   # undoes last edit, returns action name
timeline_action("redo")   # redoes it
```
Undo routes through FCP's FFUndoManager (not the responder chain).

### Timeline Data Model (Spine)
FCP stores items in: `sequence -> primaryObject (FFAnchoredCollection) -> containedItems`
- `FFAnchoredMediaComponent` = video/audio clips
- `FFAnchoredTransition` = transitions (Cross Dissolve, etc.)
- `get_timeline_clips()` handles this automatically

## All Timeline Actions

| Category | Actions |
|----------|---------|
| Blade | blade, bladeAll |
| Markers | addMarker, addTodoMarker, addChapterMarker, deleteMarker, nextMarker, previousMarker, deleteMarkersInSelection |
| Transitions | addTransition |
| Navigation | nextEdit, previousEdit, selectClipAtPlayhead, selectToPlayhead |
| Selection | selectAll, deselectAll |
| Edit | delete, cut, copy, paste, undo, redo, pasteAsConnected, replaceWithGap, copyTimecode |
| Edit Modes | connectToPrimaryStoryline, insertEdit, appendEdit, overwriteEdit |
| Effects | pasteEffects, pasteAttributes, removeAttributes, copyAttributes, removeEffects |
| Insert | insertGap, insertPlaceholder, addAdjustmentClip |
| Trim | trimToPlayhead, extendEditToPlayhead, trimStart, trimEnd, joinClips, nudgeLeft, nudgeRight, nudgeUp, nudgeDown |
| Color | addColorBoard, addColorWheels, addColorCurves, addColorAdjustment, addHueSaturation, addEnhanceLightAndColor, balanceColor, matchColor, addMagneticMask, smartConform |
| Volume | adjustVolumeUp, adjustVolumeDown |
| Audio | expandAudio, expandAudioComponents, addChannelEQ, enhanceAudio, matchAudio, detachAudio |
| Titles | addBasicTitle, addBasicLowerThird |
| Speed | retimeNormal, retimeFast2x/4x/8x/20x, retimeSlow50/25/10, retimeReverse, retimeHold, freezeFrame, retimeBladeSpeed, retimeSpeedRampToZero, retimeSpeedRampFromZero |
| Keyframes | addKeyframe, deleteKeyframes, nextKeyframe, previousKeyframe |
| Rating | favorite, reject, unrate |
| Range | setRangeStart, setRangeEnd, clearRange, setClipRange |
| Clip Ops | solo, disable, createCompoundClip, autoReframe, breakApartClipItems, synchronizeClips, openClip, renameClip, addToSoloedClips, referenceNewParentClip, changeDuration |
| Storyline | createStoryline, liftFromPrimaryStoryline, overwriteToPrimaryStoryline, collapseToConnectedStoryline |
| Audition | createAudition, finalizeAudition, nextAuditionPick, previousAuditionPick |
| Captions | addCaption, splitCaption, resolveOverlaps |
| Multicam | createMulticamClip |
| Show/Hide | showVideoAnimation, showAudioAnimation, soloAnimation, showTrackingEditor, showCinematicEditor, showMagneticMaskEditor, enableBeatDetection, showPrecisionEditor, showAudioLanes, expandSubroles, showDuplicateRanges, showKeywordEditor |
| View | zoomToFit, zoomIn, zoomOut, verticalZoomToFit, zoomToSamples, toggleSnapping, toggleSkimming, toggleClipSkimming, toggleAudioSkimming, toggleInspector, toggleTimeline, toggleTimelineIndex, toggleInspectorHeight, beatDetectionGrid, timelineScrolling, enterFullScreen, timelineHistoryBack, timelineHistoryForward |
| Project | duplicateProject, snapshotProject, projectProperties |
| Library | closeLibrary, libraryProperties, consolidateEventMedia, mergeEvents, deleteGeneratedFiles |
| Render | renderSelection, renderAll |
| Export | exportXML, shareSelection |
| Find | find, findAndReplaceTitle |
| Reveal | revealInBrowser, revealProjectInBrowser, revealInFinder, moveToTrash |
| Keywords | showKeywordEditor, removeAllKeywords, removeAnalysisKeywords |
| Other | analyzeAndFix, backgroundTasks, recordVoiceover, editRoles, hideClip, addVideoGenerator |

## Playback Actions
playPause, goToStart, goToEnd, nextFrame, prevFrame, nextFrame10, prevFrame10, playAroundCurrent

## New: Universal Menu Access
```
execute_menu_command(["File", "New", "Project"])     # any menu item
execute_menu_command(["Modify", "Balance Color"])     # color correction
execute_menu_command(["View", "Playback", "Loop"])    # toggle loop
list_menus(menu="File")                               # discover menu items
list_menus(menu="Modify", depth=3)                    # see nested submenus
```

## New: Inspector Properties
```
get_inspector_properties()                    # read all properties of selected clip
get_inspector_properties("transform")         # just transform (position, rotation, scale)
get_inspector_properties("compositing")       # opacity, blend mode
set_inspector_property("opacity", 0.5)        # set opacity to 50%
set_inspector_property("volume", -6.0)        # set audio volume
set_inspector_property("positionX", 100.0)    # move clip position
```

## New: Panel/View Toggles
```
toggle_panel("videoScopes")          # show/hide video scopes
toggle_panel("inspector")            # toggle inspector
toggle_panel("effectsBrowser")       # effects browser
set_workspace("colorEffects")        # switch workspace layout
```

## New: Tool Selection
```
select_tool("blade")     # switch to blade tool
select_tool("trim")      # switch to trim tool
select_tool("range")     # switch to range selection
select_tool("transform") # switch to transform tool
```

## New: Roles & Export
```
assign_role("audio", "Dialogue")     # assign audio role
assign_role("video", "Titles")       # assign video role
share_project("Export File")         # export with specific destination
share_project()                      # export with default destination
create_project()                     # create new project
create_event()                       # create new event
create_library()                     # create new library
```

## Common Workflows

### Blade at a specific time
```
playback_action("goToStart")
batch_timeline_actions('[{"type":"playback","action":"nextFrame","repeat":72}]')  # 3s at 24fps
timeline_action("blade")
```

### Multiple cuts
```
batch_timeline_actions('[
  {"type":"playback","action":"goToStart"},
  {"type":"playback","action":"nextFrame","repeat":48},
  {"type":"timeline","action":"blade"},
  {"type":"playback","action":"nextFrame","repeat":48},
  {"type":"timeline","action":"blade"},
  {"type":"playback","action":"nextFrame","repeat":48},
  {"type":"timeline","action":"blade"}
]')
```

### Add color correction
```
playback_action("goToStart")
timeline_action("selectClipAtPlayhead")
timeline_action("addColorBoard")
```

### Change speed
```
timeline_action("selectClipAtPlayhead")
timeline_action("retimeSlow50")    # 50% speed
# Undo: timeline_action("undo")
```

### Add markers at intervals
```
playback_action("goToStart")
batch_timeline_actions('[
  {"type":"playback","action":"nextFrame","repeat":120},
  {"type":"timeline","action":"addMarker"},
  {"type":"playback","action":"nextFrame","repeat":120},
  {"type":"timeline","action":"addChapterMarker"}
]')
```

### Create project via FCPXML (no restart)
```
xml = generate_fcpxml(
    project_name="My Project",
    frame_rate="24",
    items='[
      {"type":"gap","duration":10},
      {"type":"title","text":"Introduction","duration":5},
      {"type":"transition","duration":1},
      {"type":"gap","duration":15},
      {"type":"marker","time":5,"name":"Chapter 1","kind":"chapter"}
    ]'
)
import_fcpxml(xml, internal=True)
```

### Inspect clip effects
```
timeline_action("selectClipAtPlayhead")
get_clip_effects()  # shows effect names, IDs, handles
```

### Analyze timeline health
```
analyze_timeline()  # pacing, flash frames, clip stats
```

### Batch export clips individually
```
batch_export()                    # export all clips using default share destination
batch_export(scope="selected")    # export only selected clips
```

Each clip is exported individually with all effects/color grading baked in.
For each clip, SpliceKit:
1. Computes the clip's exact position in the timeline
2. Sets the in/out range (mark in/out) to the clip boundaries
3. Triggers FCP's share dialog — click "Share" to confirm

Set your default share destination in FCP first (File > Share > Add Destination).

### Set in/out range programmatically
```
set_timeline_range(start_seconds=5.0, end_seconds=10.0)  # mark in at 5s, out at 10s
timeline_action("setRangeStart")   # mark in at current playhead
timeline_action("setRangeEnd")     # mark out at current playhead
timeline_action("clearRange")      # remove range selection
```

### Text-based editing via transcript
```
open_transcript()                              # transcribe all clips on timeline
open_transcript(file_url="/path/to/video.mp4") # transcribe a specific file
get_transcript()                               # get words with timestamps + speakers + silences
delete_transcript_words(start_index=5, count=3) # delete words 5-7 (removes video segment)
move_transcript_words(start_index=10, count=2, dest_index=3) # reorder clips
search_transcript("hello")                     # search for text in transcript
search_transcript("pauses")                    # find all silences/pauses
delete_transcript_silences()                   # batch-remove all silences from timeline
delete_transcript_silences(min_duration=1.0)   # remove only silences > 1 second
set_transcript_speaker(start_index=0, count=50, speaker="Host")  # label speakers
set_silence_threshold(threshold=0.5)           # set minimum pause detection (seconds)
close_transcript()                             # close the panel
```

The transcript panel opens inside FCP as a floating window with an **engine selector dropdown**:
- **Parakeet v3** (default) — NVIDIA Parakeet TDT 0.6B multilingual (25 languages), on-device via FluidAudio
- **Parakeet v2** — English-optimized variant, same speed
- **Apple Speech** — SFSpeechRecognizer (slower, network-capable)
- **FCP Native** — Built-in AASpeechAnalyzer

All clips are transcribed in a single batch process (model loaded once, reused across clips).
Speaker diarization is available with Parakeet engines (checkbox in UI).

Panel features:
- Shows transcribed text grouped by **speaker segments** with timecode ranges (HH:MM:SS:FF)
- **Silence markers** `[...]` shown inline between words where pauses are detected
- Click a word to jump the playhead to that time
- Click a silence marker to jump to that pause
- Select words and press Delete to remove those video segments (ripple delete)
- Select silence markers and press Delete to remove pauses
- Drag words to reorder clips on the timeline
- Current word is highlighted as playback progresses
- **Search bar** with text search and filter by Pauses or Low Confidence
- **Batch operations**: Delete all search results or delete all silences
- Result count with prev/next navigation (Cmd+F to focus search)

Deleting words performs: blade at start -> blade at end -> select segment -> delete
Moving words performs: blade + cut at source -> move playhead -> paste at destination

## Transitions
```
list_transitions()                             # list all 376+ available transitions
list_transitions(filter="dissolve")            # filter by name or category
apply_transition(name="Flow")                  # apply by display name
apply_transition(name="Cross Dissolve")        # apply specific transition
apply_transition(effectID="HEFlowTransition")  # apply by effect ID
```

Transitions are applied at the current edit point. Navigate to an edit point first:
```
timeline_action("nextEdit")           # go to next edit point
apply_transition(name="Flow")         # apply Flow transition there
```

### Freeze Extend (not enough media handles)
When clips don't have enough extra media beyond their edges for a transition, FCP normally
shows a dialog offering to ripple trim. SpliceKit adds a third option: **"Use Freeze Frames"**.

- **UI button**: Whenever the "not enough extra media" dialog appears (including manual use),
  a "Use Freeze Frames" button is added. It extends clip edges with freeze frames and
  re-applies the transition without shortening the project.
- **API parameter**: Use `freeze_extend=True` to automatically extend with freeze frames:
```
apply_transition(name="Cross Dissolve", freeze_extend=True)  # auto freeze-extend if needed
```

This creates freeze frames at the outgoing clip's last frame and the incoming clip's first
frame, providing the media handles needed for the transition overlap.

## Command Palette
```
show_command_palette()                         # open the palette (or Cmd+Shift+P)
search_commands("blade")                       # find commands by name/keyword
execute_command("blade", type="timeline")      # run a command directly
ai_command("slow this clip to half speed")     # natural language via Apple Intelligence
hide_command_palette()                         # close it
```

The command palette opens as a floating window inside FCP:
- Fuzzy search across all available actions (editing, playback, color, speed, markers, etc.)
- Arrow keys to navigate, Return to execute, Escape to close
- Type natural language sentences and press Tab to ask Apple Intelligence
- Falls back to keyword matching when Apple Intelligence is unavailable
- Also accessible via toolbar button or Enhancements menu

## Object Handles
```
# Get a handle to an object
r = call_method_with_args("FFLibraryDocument", "copyActiveLibraries", "[]", true, true)
# r = {"handle": "obj_1", "class": "__NSArrayM", ...}

# Use handle in subsequent calls
call_method_with_args("obj_1", "objectAtIndex:", '[{"type":"int","value":0}]', false, true)

# Read properties via KVC
get_object_property("obj_2", "displayName")

# Always clean up
manage_handles(action="release_all")
```

Argument types: string, int, double, float, bool, nil, sender, handle, cmtime, selector

## Error Recovery
- "No active timeline module" -> No project open. Load one (see above).
- "No sequence in timeline" -> Same. Need loadEditorForSequence:.
- "Cannot connect" -> FCP not running. Launch it.
- "Handle not found" -> Released or GC'd. Get a fresh reference.
- "No responder handled X" -> Action not available (wrong state or no selection).
- Broken pipe -> Stale connection. Next call auto-reconnects.

## Key Classes
| Class | Use |
|-------|-----|
| FFAnchoredTimelineModule | Timeline editing (1435 methods) |
| FFAnchoredSequence | Timeline data model |
| FFAnchoredMediaComponent | Clips in timeline |
| FFAnchoredTransition | Transitions |
| FFLibrary / FFLibraryDocument | Library management |
| FFEditActionMgr | Edit commands |
| FFEffectStack | Effects on clips |
| PEAppController | App controller |
| PEEditorContainerModule | Editor/timeline modules |

## Discovering APIs
```
get_classes(filter="FFColor")                          # find classes
explore_class("FFAnchoredTimelineModule")              # full overview
search_methods("FFAnchoredTimelineModule", "blade")    # find methods
get_methods("FFEffectStack")                           # all methods
```

## Debug & Diagnostics (FCP Internal Developer Tools)

SpliceKit exposes FCP's internal developer logging, debug overlays, and performance
monitoring tools that are normally hidden. These are built into FCP's own frameworks
(ProAppSupport, TimelineKit, Helium, ProCore) and controlled via NSUserDefaults and
CFPreferences keys.

### Quick Start
```
debug_get_config()                              # see all current debug settings
debug_enable_preset("timeline_visual")          # turn on visual debug overlays
debug_enable_preset("all_off")                  # reset everything to normal
```

### Get Current State
```
debug_get_config()
```
Returns the current value of every debug flag organized into four groups:
- **timeline_debug**: 35 TLKUserDefaults keys (visual overlays, logging, rendering)
- **cfpreferences_debug**: 6 CFPreferences keys (video decoder, frame drops, GPU)
- **proapp_log**: ProAppSupport structured log system (level, categories, UI, threads)
- **fcp_flags**: FCP behavioral overrides (gap coalescing, snapping, skimming)

### Set Individual Flags
```
debug_set_config("TLKShowHiddenGapItems", "true")       # show hidden gaps in timeline
debug_set_config("TLKPerformanceMonitorEnabled", "true") # enable perf monitor
debug_set_config("LogLevel", "trace")                    # most verbose logging
debug_set_config("VideoDecoderLogLevelInNLE", "3")       # video decoder verbosity
debug_set_config("GPU_LOGGING", "true")                  # GPU/FxPlug logging
debug_set_config("TLKShowHiddenGapItems", "false")       # turn it back off
```

TLK flags take effect immediately (TLKUserDefaults is reloaded live).
CFPreferences flags may require FCP restart for some subsystems.

### Presets (Enable Groups of Flags)
```
debug_enable_preset("timeline_visual")     # visual debug overlays
debug_enable_preset("timeline_logging")    # timeline subsystem logging
debug_enable_preset("performance")         # perf monitor + decoder/frame drop logging
debug_enable_preset("render_debug")        # disable rendering layers + GPU logging
debug_enable_preset("verbose_logging")     # trace-level logging + log UI + thread info
debug_enable_preset("all_off")             # reset all debug flags to defaults
```

**Preset details:**

| Preset | What it enables |
|--------|----------------|
| `timeline_visual` | Lane indices, misaligned edges, render bar, hidden gaps, invalid layouts, color-highlight changed objects |
| `timeline_logging` | Log layer changes, parts, reload requests, recycling, visible rect changes, segmentation stats |
| `performance` | TLK performance monitor, VideoDecoderLogLevelInNLE=2, FrameDropLogLevel=2 |
| `render_debug` | Disable filmstrip/background/waveform rendering, enable GPU logging (isolate render issues) |
| `verbose_logging` | LogLevel=trace, LogUI=true, LogThread=true, EnableScheduledReadAudioLogging=true |
| `all_off` | Remove all debug flags, reset CFPreferences, clear log settings |

### Framerate Monitor
```
debug_start_framerate_monitor(2.0)   # log fps every 2 seconds
debug_stop_framerate_monitor()       # stop monitoring
```
Uses FCP's built-in HMDFramerate (ProCore). Reports to system log:
- Overall fps
- Average getFrame() call time in ms
- Min/max frame times

View output: `log stream --process "Final Cut Pro"` or Console.app

### Reset
```
debug_reset_config("all")       # reset everything
debug_reset_config("tlk")       # reset timeline flags only
debug_reset_config("cfprefs")   # reset CFPreferences only
debug_reset_config("log")       # reset ProAppSupport log settings only
```

### All Available Debug Keys

**Timeline visual overlays** (TLK*):
| Key | Effect |
|-----|--------|
| TLKShowItemLaneIndex | Show lane index number on each timeline item |
| TLKShowMisalignedEdges | Highlight misaligned edges between items |
| TLKShowRenderBar | Show render status bar overlay |
| TLKShowHiddenGapItems | Reveal hidden gap items in timeline |
| TLKShowHiddenItemHeaders | Reveal hidden item headers |
| TLKShowInvalidLayoutRects | Highlight invalid layout rectangles |
| TLKShowContainerBounds | Show container bounds |
| TLKShowContentLayers | Show content layer boundaries |
| TLKShowRulerBounds | Show ruler bounds overlay |
| TLKShowUsedRegion | Show used region overlay |
| TLKShowZeroHeightSpineItems | Show zero-height spine items |

**Timeline logging** (TLK*):
| Key | What it logs |
|-----|-------------|
| TLKLogVisibleLayerChanges | Changes to visible layers |
| TLKLogParts | Timeline parts lifecycle |
| TLKLogReloadRequests | Reload/refresh requests |
| TLKLogRecyclingLayerChanges | Layer recycling events |
| TLKLogVisibleRectChanges | Visible rect geometry changes |
| TLKLogSegmentationStatistics | Segmentation statistics |

**Timeline performance/rendering** (TLK* and Debug*):
| Key | Effect |
|-----|--------|
| TLKPerformanceMonitorEnabled | Enable timeline performance monitoring |
| TLKDebugColorChangedObjects | Color-highlight changed objects after updates |
| TLKDebugLayoutConstraints | Debug layout constraint resolution |
| TLKDebugErrorsAndWarnings | Show errors and warnings visually |
| TLKDisableItemContents | Disable all item content rendering |
| DebugKeyItemVideoFilmstripsDisabled | Disable video filmstrip thumbnails |
| DebugKeyItemBackgroundDisabled | Disable item background rendering |
| DebugKeyItemAudioWaveformsDisabled | Disable audio waveform rendering |

**Video/audio/GPU logging** (CFPreferences):
| Key | Type | Effect |
|-----|------|--------|
| VideoDecoderLogLevelInNLE | int | Video decoder verbosity (0=off, higher=more) |
| FrameDropLogLevel | int | Frame drop reporting (0=off, higher=more) |
| GPU_LOGGING | bool | GPU/FxPlug pipeline logging |
| EnableScheduledReadAudioLogging | bool | Audio scheduled read logging |
| EnableLibraryUpdateHistoryValidation | bool | Library update history validation |
| FFVAMLSaveTranscription | bool | Save transcription data to disk |

**ProAppSupport log system**:
| Key | Values | Effect |
|-----|--------|--------|
| LogLevel | trace, debug, info, warning, error, failure | Set minimum log level |
| LogUI | bool | Toggle in-app log viewer panel |
| LogThread | bool | Include thread info in log output |
| LogCategory | bitmask | Filter by subsystem category |

Log categories: dev, player, sequenceEditor, camera, inspector, director,
voiceover, selection, network, theme, share, analysisKit, backgroundTasks,
angleEditor, lessons, onboarding, userNotifications, ui, all

**FCP behavior overrides**:
| Key | Effect |
|-----|--------|
| FFDontCoalesceGaps | Prevent automatic gap coalescing in timeline |
| FFDisableSnapping | Disable magnetic snapping |
| FFDisableSkimming | Disable clip skimming |

### How Debug Tools Help

**Diagnosing timeline layout issues**: Enable `timeline_visual` preset to see lane
indices, hidden gaps, misaligned edges, and invalid layout rects. This reveals
structural problems invisible in the normal UI.

**Performance troubleshooting**: Enable `performance` preset + `debug_start_framerate_monitor()`
to measure actual rendering fps and identify bottlenecks. Video decoder and frame drop
logging pinpoint decode pipeline issues.

**Render pipeline isolation**: The `render_debug` preset disables filmstrips, backgrounds,
and waveforms independently, letting you isolate which rendering subsystem is causing
problems. GPU logging captures the FxPlug/shader pipeline.

**Verbose logging for development**: The `verbose_logging` preset sets ProAppSupport to
trace level with the log UI enabled, giving maximum visibility into FCP's internal
operations. Useful when developing new SpliceKit features or investigating FCP behavior.

**Understanding timeline internals**: `TLKShowHiddenGapItems` and `TLKShowZeroHeightSpineItems`
reveal items FCP hides from the user, helping understand the true timeline data model.

## Full API Reference
See `docs/FCP_API_REFERENCE.md` for comprehensive documentation of all key classes,
methods, properties, notifications, and patterns. This reference is sufficient to use
SpliceKit without access to the decompiled FCP source code.

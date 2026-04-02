# Guards in Final Cut Pro: A Comprehensive Reverse-Engineering Report

> **Generated**: April 2, 2026
> **Source**: Decompiled analysis of 303K+ functions across 53 FCP binaries
> **FCPBridge Version**: 2.8.3

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [FFUndoGuard — Undo Transaction Guards](#1-ffundoguard--undo-transaction-guards)
3. [FFEnableGuards — Viewer On-Screen Control Guards](#2-ffenableguards--viewer-on-screen-control-guards)
4. [C++ RAII Guards — Resource Safety](#3-c-raii-guards--resource-safety)
   - [FFFigStreamMutexGuard](#31-fffigstreammutexguard)
   - [FFSharedLockRAIIGuardLockAndUnlocker](#32-ffsharedlockraiiguardlockandunlocker)
   - [FFAudioGraph Guards](#33-ffaudiograph-guards)
   - [FFDestAnalyzerSynchronizer::_LockGuard](#34-ffdestanalyzersynchronizer_lockguard)
5. [Helium GPU/GL Guards](#4-helium-gpugl-guards)
   - [HGNode::GetGuardedOutput](#41-hgnodegetguardedoutput)
   - [HGGLSetCurrentContextGuard](#42-hgglsetcurrentcontextguard)
   - [HGGLState::SetCurrentContextGuard](#43-hgglstatesetcurrentcontextguard)
   - [HGPagePullTexturesGuard](#44-hgpagepulltexturesguard)
   - [HGAutoReleasePoolScopeGuard](#45-hgautoreleasepoolscopeguard)
   - [HGTraceGuard / HGProfilerGuard](#46-hgtraceguard--hgprofilerguard)
6. [AudioMixEngine Guards](#5-audiomixengine-guards)
7. [Safe Zones Overlay System](#6-safe-zones-overlay-system)
8. [__cxa_guard — Static Initialization Guards](#7-__cxa_guard--static-initialization-guards)
9. [Event Locking: Could We Implement It?](#8-event-locking-could-we-implement-it)
   - [FCP's Locking Architecture](#fcps-locking-architecture)
   - [The Three Lock Layers](#the-three-lock-layers)
   - [Model Object Lock Hierarchy](#model-object-lock-hierarchy)
   - [Storyline Locking](#storyline-locking)
   - [Editing Model Coordinators](#editing-model-coordinators)
   - [File-Level Locking (FFFileLock)](#file-level-locking-fffilelock)
   - [Undo/Transaction System](#undotransaction-system)
   - [Possible Approaches for Event Locking via FCPBridge](#possible-approaches-for-event-locking-via-fcpbridge)
10. [Complete Guard Inventory](#complete-guard-inventory)
11. [Key Classes Reference](#key-classes-reference)

---

## Executive Summary

The concept of "guards" is deeply woven throughout the Final Cut Pro codebase, manifesting in at least **seven distinct forms** across multiple binaries. From undo transaction protection to GPU render graph validation, from audio mutex RAII patterns to broadcast safe zone overlays, guards serve as a fundamental architectural pattern in FCP.

This report catalogs every guard-related symbol found across 53 decompiled FCP binaries, provides full decompiled pseudocode for each, and analyzes their behavior and relationships.

### Guard Categories at a Glance

| Category | Primary Class/Symbol | Binary | Purpose |
|----------|---------------------|--------|---------|
| Undo Protection | `FFUndoGuard` | Flexo | Prevents undo/redo across closed libraries |
| Viewer Overlays | `FFEnableGuards` | Flexo (OSC) | Toggles guard region overlays in viewer |
| Stream Mutex | `FFFigStreamMutexGuard` | Flexo | RAII mutex for FIG stream operations |
| Shared Lock | `FFSharedLockRAIIGuardLockAndUnlocker` | Flexo | RAII reader-writer lock wrapper |
| Audio Graph | `SuspendUpdatesGuard` / `FormatChangeGuard` | Flexo | Audio graph state protection |
| Analyzer Lock | `FFDestAnalyzerSynchronizer::_LockGuard` | Flexo | Analyzer synchronization |
| GL Context | `HGGLSetCurrentContextGuard` | Helium | OpenGL context scope management |
| GL State | `HGGLState::SetCurrentContextGuard` | Helium | GL state context switching |
| Textures | `HGPagePullTexturesGuard` | Helium | GPU texture lifetime management |
| Metal Textures | `HGPagePullMetalTexturesGuard` | Helium | Metal texture lifetime management |
| Render Validation | `HGNode::GetGuardedOutput` | Helium | Render node validity check |
| AutoRelease | `HGAutoReleasePoolScopeGuard` | Helium | ObjC autorelease pool scoping |
| Trace/Debug | `HGTraceGuard` | Helium | Logging/profiling scope |
| Profiler | `HGProfilerGuard` / `ProfilerScopeGuard` | Helium | Performance measurement scope |
| Audio Format | `STGraphOwner::FormatChangeGuard` | AudioMixEngine | Audio format change protection |
| Audio Unit | `STModuleUninitializeGuard` | AudioMixEngine | Audio unit teardown safety |
| Safe Zones | `OZSafeZonesOverlay` | Ozone | Broadcast safe zone rendering |
| Static Init | `__cxa_guard_acquire/release/abort` | All binaries | Thread-safe static initialization |
| Exception | `std::__exception_guard_exceptions` | Multiple | C++ exception safety |

---

## 1. FFUndoGuard — Undo Transaction Guards

**Binary**: Flexo
**Class**: `FFUndoGuard` (8 methods)
**Related**: `FFUndoHandler` (54 methods)

### Purpose

`FFUndoGuard` is an Objective-C class that protects the undo/redo system when library items are involved. It tracks which libraries participate in an undo group and prevents undo/redo operations from corrupting state when a referenced library has been closed.

### Architecture

```
FFUndoHandler
  ├── _guard: FFUndoGuard (nullable)
  ├── _undoManager: FFUndoManager
  └── _actionStack: NSMutableArray
  
FFUndoGuard
  ├── _libraryItems: NSMutableSet (set of FFLibrary objects)
  ├── _closedURL: NSURL (set when a library is closed)
  └── _status: char (0=normal, 1=active, -1=error)
```

### Lifecycle

1. **Registration**: When an undoable action involves library items, `+[FFUndoHandler registerGuardForLibraryItems:]` creates or extends a guard
2. **Attachment**: On `appendGuardToStackIfNecessary`, the guard is moved from the handler's `_guard` slot to the undo stack via `addToHandler:`
3. **Triggering**: On undo/redo, `guardAction:` fires — it re-registers itself on the opposite undo stack and checks for closed libraries
4. **Error Handling**: If a library was closed (`_closedURL != nil`), shows a localized error alert
5. **Cleanup**: `undoFinished:` / `redoFinished:` process the notification and advance the undo/redo state

### Decompiled Code

#### +[FFUndoHandler registerGuardForLibraryItems:]

Entry point — creates a guard when an undoable action touches library items:

```c
// Address: 0x51CBE0 (Flexo)

void __cdecl +[FFUndoHandler registerGuardForLibraryItems:](id a1, SEL a2, id a3)
{
  id v4, v5;
  FFUndoGuard *v6, *v7;
  id v8;

  v4 = +[FFUndoHandler fromCurrentTransaction](&OBJC_CLASS___FFUndoHandler, 
         "fromCurrentTransaction");
  v5 = _objc_msgSend(v4, "undoManager");
  
  // Only register guards for new operations (not during undo/redo replay)
  if ( !(unsigned __int8)_objc_msgSend(v5, "isUndoing")
    && !(unsigned __int8)_objc_msgSend(v5, "isRedoing")
    && _objc_msgSend(v5, "groupingLevel") )
  {
    v6 = objc_alloc(&OBJC_CLASS___FFUndoGuard);
    v7 = -[FFUndoGuard initWithLibraryItems:](v6, "initWithLibraryItems:", a3);
    v8 = _objc_msgSend(v4, "guard");
    if ( v8 )
      _objc_msgSend(v8, "addGuard:", v7);  // Merge into existing guard
    else
      _objc_msgSend(v4, "setGuard:", v7);  // Set as new guard
    objc_release(v7);
  }
}
```

#### -[FFUndoGuard initWithLibraryItems:]

Initializes a guard by extracting the set of libraries from the given items:

```c
// Address: 0x51DA00 (Flexo)

FFUndoGuard *__cdecl -[FFUndoGuard initWithLibraryItems:](FFUndoGuard *self, SEL a2, id a3)
{
  FFUndoGuard *result;

  result = -[FFUndoGuard init](&v13, "init");
  if ( result )
  {
    v16 = objc_opt_new(&OBJC_CLASS___NSMutableSet);
    // Enumerate library items, extract each item's library, add to set
    v5 = _objc_msgSend(a3, "countByEnumeratingWithState:objects:count:", &v9, v18, 16);
    if ( v5 )
    {
      do
      {
        v7 = 0;
        do
        {
          v8 = _objc_msgSend(*(id *)(*((_QWORD *)&v9 + 1) + 8LL * (_QWORD)v7), "library");
          _objc_msgSend(v16, "addObject:", v8);
          v7 = (char *)v7 + 1;
        }
        while ( v6 != v7 );
        v6 = _objc_msgSend(obj, "countByEnumeratingWithState:objects:count:", ...);
      }
      while ( v6 );
    }
    result->_libraryItems = (NSMutableSet *)v16;
  }
  return result;
}
```

#### -[FFUndoGuard guardAction:]

The core guard logic — fires on undo/redo, re-registers itself, and handles closed libraries:

```c
// Address: 0x51D4D0 (Flexo)

void __cdecl -[FFUndoGuard guardAction:](FFUndoGuard *self, SEL a2, id a3)
{
  id v3;
  char status;
  
  v3 = _objc_msgSend(a3, "undoManager");
  status = self->_status;
  self->_status = 1;  // Mark as active
  
  if ( status != 1 )  // Prevent re-entrancy
  {
    // Update library items (check for closed libraries)
    obj = -[FFUndoGuard updateItems](self, "updateItems");
    
    // Re-register guard on each library's document for the opposite operation
    // (undo registers for redo, and vice versa)
    for each library in obj:
      v6 = _objc_msgSend(library, "document");
      _objc_msgSend(v6, "registerUndoWithTarget:selector:object:", 
                    self, "guardAction:", a3);
    
    if ( status == 0 )  // First activation (not re-entry)
    {
      if ( self->_closedURL )
      {
        // Library was closed! Show error alert
        // "FFUndoApp%@Cannot%@DueToMissingLibrary%@"
        v11 = localizedString("FFUndoApp%@Cannot%@DueToMissingLibrary%@");
        v13 = [NSRunningApplication currentApplication].localizedName;
        v16 = isUndoing ? undoActionName : redoActionName;
        v18 = self->_closedURL.lastPathComponent.stringByDeletingPathExtension;
        alert = [NSAlert alertWithMessageText:... informativeTextWithFormat:v11, 
                 v13, v16, v18];
        [alert runModal];
      }
      
      // Listen for undo/redo completion notification
      [FFNotificationCenter addObserver:self 
                               selector:isUndoing ? "undoFinished:" : "redoFinished:"
                                   name:isUndoing ? "FFUndoHandlerDidUndo" : "FFUndoHandlerDidRedo"
                                 object:a3];
    }
  }
}
```

#### -[FFUndoGuard updateItems]

Checks if any tracked libraries have been closed, removes them from the set, and records the closed URL:

```c
// Address: 0x51DC00 (Flexo)

id __cdecl -[FFUndoGuard updateItems](FFUndoGuard *self, SEL a2)
{
  for each library in self->_libraryItems:
    closedURL = [library cachedURLAtClose];
    if ( closedURL )
    {
      // Library has been closed — remove it from the set
      if ( !mutableCopy )
        mutableCopy = [self->_libraryItems mutableCopy];
      [mutableCopy removeObject:library];
      
      // Record the first closed URL for the error message
      if ( !self->_closedURL )
        self->_closedURL = [closedURL copy];
    }
  
  if ( mutableCopy )
    self->_libraryItems = mutableCopy;
  
  return self->_libraryItems;
}
```

#### -[FFUndoGuard undoFinished:]

Handles undo completion — if library is still open, silently replays the redo to maintain consistency:

```c
// Address: 0x51D940 (Flexo)

void __cdecl -[FFUndoGuard undoFinished:](FFUndoGuard *self, SEL a2, id a3)
{
  v3 = [a3 object];
  [FFNotificationCenter removeObserver:self name:"FFUndoHandlerDidUndo" object:v3];
  v5 = [v3 undoManager];
  
  if ( self->_closedURL )
  {
    self->_status = -1;  // Error state
    [v5 redo];           // Try to redo (will fail gracefully)
  }
  else
  {
    // Library still open — silently redo to maintain stack consistency
    [v5 disableUndoRegistration];
    [v5 redo];
    [v5 enableUndoRegistration];
    [v3 setGuard:self];
    [v5 undo];  // The actual undo
  }
  self->_status = 0;
}
```

#### -[FFUndoGuard redoFinished:]

Mirror of `undoFinished:` for redo operations:

```c
// Address: 0x51D880 (Flexo)

void __cdecl -[FFUndoGuard redoFinished:](FFUndoGuard *self, SEL a2, id a3)
{
  v3 = [a3 object];
  [FFNotificationCenter removeObserver:self name:"FFUndoHandlerDidRedo" object:v3];
  v5 = [v3 undoManager];
  
  if ( self->_closedURL )
  {
    self->_status = -1;
    [v5 undo];
  }
  else
  {
    [v5 disableUndoRegistration];
    [v5 undo];
    [v5 enableUndoRegistration];
    [v3 setGuard:self];
    [v5 redo];
  }
  self->_status = 0;
}
```

#### -[FFUndoGuard addGuard:]

Merges another guard's library items into this one:

```c
// Address: 0x51D220 (Flexo)

void __cdecl -[FFUndoGuard addGuard:](FFUndoGuard *self, SEL a2, id a3)
{
  [self->_libraryItems unionSet:a3->_libraryItems];
}
```

#### -[FFUndoGuard addToHandler:]

Pushes the guard onto the undo stack by registering with each library's document:

```c
// Address: 0x51D240 (Flexo)

void __cdecl -[FFUndoGuard addToHandler:](FFUndoGuard *self, SEL a2, id a3)
{
  obj = [self updateItems];
  if ( [obj count] )
  {
    v4 = [a3 undoManager];
    wasWarningEnabled = [a3 isUndoWarningEnabled];
    if ( wasWarningEnabled ) [a3 disableUndoWarning];
    
    actionName = [v4 canRedo] ? [v4 redoActionName] : [v4 undoActionName];
    [a3 undoableBegin:actionName];
    
    for each library in obj:
      doc = [library document];
      [doc registerUndoWithTarget:self selector:"guardAction:" object:a3];
    
    [v4 setActionName:actionName];
    [a3 undoableEnd:actionName option:2 error:nil];
    
    if ( wasWarningEnabled ) [a3 enableUndoWarning];
  }
}
```

#### -[FFUndoHandler appendGuardToStackIfNecessary]

Transfers the pending guard from the handler to the undo stack:

```c
// Address: 0x51CB70 (Flexo)

void __cdecl -[FFUndoHandler appendGuardToStackIfNecessary](FFUndoHandler *self, SEL a2)
{
  guard = self->_guard;
  if ( guard )
  {
    objc_retain(guard);
    [self setGuard:nil];             // Clear from handler
    [guard addToHandler:self];       // Push to undo stack
    objc_release(guard);
  }
}
```

#### Supporting Methods

```c
// -[FFUndoHandler guard] — Address: 0x51D200
FFUndoGuard *__cdecl -[FFUndoHandler guard](FFUndoHandler *self, SEL a2) {
  return self->_guard;
}

// -[FFUndoHandler setGuard:] — Address: 0x51D210
void __cdecl -[FFUndoHandler setGuard:](FFUndoHandler *self, SEL a2, id a3) {
  objc_setProperty_nonatomic(self, a2, a3, 48);
}

// -[FFUndoGuard dealloc] — Address: 0x51DBB0
void __cdecl -[FFUndoGuard dealloc](FFUndoGuard *self, SEL a2) {
  objc_release(self->_libraryItems);
  objc_release(self->_closedURL);
  [super dealloc];
}
```

---

## 2. FFEnableGuards — Viewer On-Screen Control Guards

**Binary**: Flexo
**Class**: `FFOSCUtils` (21 methods)
**Preference**: `NSUserDefaults` key `"FFEnableGuards"` (integer)

### Purpose

In broadcast video terminology, "guards" refer to safe area boundary overlays displayed in the viewer — typically action-safe and title-safe zones. The `FFEnableGuards` preference controls whether these guard overlays are rendered in FCP's viewer via the On-Screen Controls (OSC) system.

### Architecture

```
FFOSCUtils (class methods)
  ├── +initialize           — reads FFEnableGuards from NSUserDefaults
  ├── +registerForNSUD:     — sets up KVO observation
  ├── +observeValueForKeyPath:... — updates on preference change
  └── +getFFEnableGuards    — returns current value
  
  Static variable: sFFEnableGuards (signed __int64)
  KVO context: sKVOContextFFOSCUtils
```

### Decompiled Code

#### +[FFOSCUtils initialize]

```c
// Address: 0xCEA220 (Flexo)

void __cdecl +[FFOSCUtils initialize](id a1, SEL a2)
{
  NSUserDefaults *v2;

  if ( (id)objc_opt_class(&OBJC_CLASS___FFOSCUtils) == a1 )
  {
    v2 = +[NSUserDefaults standardUserDefaults](&OBJC_CLASS___NSUserDefaults, 
           "standardUserDefaults");
    sFFEnableGuards = -[NSUserDefaults integerForKey:](v2, "integerForKey:", 
                       CFSTR("FFEnableGuards"));
    _objc_msgSend(a1, "performSelectorOnMainThread:withObject:waitUntilDone:", 
                  "registerForNSUD:", 0, 0);
  }
}
```

#### +[FFOSCUtils getFFEnableGuards]

```c
// Address: 0xCEA110 (Flexo)

signed __int64 __cdecl +[FFOSCUtils getFFEnableGuards](id a1, SEL a2)
{
  return sFFEnableGuards;
}
```

#### +[FFOSCUtils observeValueForKeyPath:ofObject:change:context:]

```c
// Address: 0xCEA120 (Flexo)

void __cdecl +[FFOSCUtils observeValueForKeyPath:ofObject:change:context:](
        id a1, SEL a2, id a3, id a4, id a5, void *a6)
{
  if ( a6 == &sKVOContextFFOSCUtils )
  {
    v6 = +[NSUserDefaults standardUserDefaults]();
    sFFEnableGuards = [v6 integerForKey:@"FFEnableGuards"];
  }
  else
  {
    [super observeValueForKeyPath:a3 ofObject:a4 change:a5 context:a6];
  }
}
```

### Related: OZSafeZonesOverlay

The actual safe zone rendering is handled by `OZSafeZonesOverlay` in the Ozone framework, which draws action-safe and title-safe zone boundaries:

```c
// OZSafeZonesOverlay has two line collections:
//   _actionzoneLines — action-safe boundary (typically 5% inset)
//   _titlezoneLines  — title-safe boundary (typically 10% inset)

// Margins are read from OZPreferenceManager:
//   OZPreferenceManager::SafeZonesActionPercentage
//   OZPreferenceManager::SafeZonesTitlePercentage
//   OZPreferenceManager::SafeZonesColor

// Default color: sRGB(0.0, 0.753, 1.0, 1.0) — a cyan/light blue
```

---

## 3. C++ RAII Guards — Resource Safety

FCP makes extensive use of the C++ RAII (Resource Acquisition Is Initialization) pattern for scope-based resource management. These guards acquire a resource in their constructor and release it in their destructor, ensuring exception-safe cleanup.

### 3.1 FFFigStreamMutexGuard

**Binary**: Flexo
**Purpose**: Mutex locking for FIG (media framework) stream operations with signpost-based performance tracing.

#### Constructor

```c
// Address: 0x10AAC80 (Flexo)
// FFFigStreamMutexGuard::FFFigStreamMutexGuard(FFFigStreamMutex&, FFSignPostReason)

__int64 __fastcall FFFigStreamMutexGuard::FFFigStreamMutexGuard(
        _QWORD *a1, __int64 a2, int a3)
{
  *a1 = a2;                    // Store mutex reference
  a1[6] = 0;                  // Clear callback slots
  a1[12] = 0;
  a1[18] = 0;
  a1[20] = 0;
  
  // Set up three callback stages:
  // 1. "start" — called when lock acquisition begins
  v5 = operator new(0x28u);
  *v5 = off_18B63C8;
  v5[1] = FFFigStreamMutex::start;
  v5[3] = a2;                 // Reference to the mutex
  *((_DWORD *)v5 + 8) = a3;   // SignPost reason
  // ... swap into slot a1[2]
  
  // 2. "acquired" — called when lock is held
  v17[1] = FFFigStreamMutex::acquired;
  v17[3] = lock;
  // ... swap into slot a1[8]
  
  // 3. "end" — called when lock is released
  v10 = operator new(0x28u);
  v10[1] = FFFigStreamMutex::end;
  v10[3] = lock;
  *((_DWORD *)v10 + 8) = a3;
  // ... swap into slot a1[14]
  
  // Create FFLockerWithCallbacks wrapping the mutex + callbacks
  v14 = operator new(0x18u);
  FFLockerWithCallbacks::FFLockerWithCallbacks(v14, lock, callbacks);
  *v4 = v14;  // Store locker
}
```

#### Destructor

```c
// Address: 0x10A0900 (Flexo)

void __fastcall FFFigStreamMutexGuard::~FFFigStreamMutexGuard(FFFigStreamMutexGuard *this)
{
  // Destroy the locker (which releases the mutex)
  v2 = (FFLockerWithCallbacks *)*((_QWORD *)this + 20);
  *((_QWORD *)this + 20) = 0;
  if ( v2 )
  {
    FFLockerWithCallbacks::~FFLockerWithCallbacks(v2);
    operator delete(v2);
  }
  
  // Destroy the three std::function callback slots (end, acquired, start)
  // Each checks if the function object is inline or heap-allocated
  // and calls the appropriate destructor
}
```

### 3.2 FFSharedLockRAIIGuardLockAndUnlocker

**Binary**: Flexo
**Purpose**: RAII wrapper for FFSharedLock that automatically unlocks on scope exit and optionally calls a cleanup callback.

```c
// Address: 0x2AC100 (Flexo)

void __fastcall FFSharedLockRAIIGuardLockAndUnlocker::~FFSharedLockRAIIGuardLockAndUnlocker(
        FFSharedLockRAIIGuardLockAndUnlocker *this)
{
  __int64 v2;

  // Call the cleanup callback if set and not already called
  v2 = *((_QWORD *)this + 1);
  if ( v2 && !*((_BYTE *)this + 16) )
    (*(void (__fastcall **)(__int64))(v2 + 16))(v2);
  *((_BYTE *)this + 16) = 1;  // Mark as cleaned up
  
  // Unlock the FFSharedLock
  _objc_msgSend(*(id *)this, "unlock");
  objc_release(*(id *)this);
}
```

### 3.3 FFAudioGraph Guards

**Binary**: Flexo

#### SuspendUpdatesGuard

Suspends audio graph updates for the duration of a scope:

```c
// Address: 0x83E220 (Flexo)

void __fastcall FFAudioGraph::SuspendUpdatesGuard::~SuspendUpdatesGuard(FFAudioGraph **this)
{
  FFAudioGraph *v1;

  v1 = *this;
  if ( v1 )
    FFAudioGraph::ResumeUpdates(v1);
}
```

#### FormatChangeGuard

Protects audio format changes — on destruction, re-initializes all affected audio units:

```c
// Address: 0x5F090 (Flexo)

void __fastcall FFAudioGraph::FormatChangeGuard::~FormatChangeGuard(
        FFAudioGraph::FormatChangeGuard *this)
{
  v1 = *(_QWORD *)this;  // Audio graph reference
  if ( v1 )
  {
    // Decrement format change reference count
    v2 = (*(_DWORD *)(v1 + 224))-- == 1;
    if ( v2 )  // Last guard leaving scope
    {
      // Re-initialize all audio units that were affected
      v3 = *(_QWORD **)(v1 + 200);  // Changed units set (std::set)
      v4 = (_QWORD *)(v1 + 208);    // End sentinel
      while ( v3 != v4 )
      {
        AudioUnitInitialize(*(AudioUnit *)(v3[4] + 24LL));
        // ... std::set iterator advancement (red-black tree walk)
        v3 = nextNode;
      }
      // Clear the changed units set
      std::__tree::destroy(v1 + 200, *(_QWORD **)(v1 + 208));
      // Reset sentinel pointers
    }
  }
}
```

### 3.4 FFDestAnalyzerSynchronizer::_LockGuard

**Binary**: Flexo
**Purpose**: Lock guard for destination analyzer synchronization with acquire/release callbacks stored as `std::function<void()>`.

#### Constructor

```c
// Address: 0x34A390 (Flexo)

__int64 __fastcall FFDestAnalyzerSynchronizer::_LockGuard::_LockGuard(
        __int64 a1, __int64 acquireFunc, __int64 releaseFunc)
{
  // Copy the acquire function (std::function<void()>)
  // Handles inline-stored vs heap-allocated function objects
  v8 = *(_QWORD *)(acquireFunc + 32);
  if ( v8 == acquireFunc )  // Inline storage
    *(_QWORD *)(a1 + 32) = a1;
    // ... copy via virtual call
  else
    *(_QWORD *)(a1 + 32) = (*(...)(v8 + 16))(v8);  // Heap: clone
  
  // Copy the release function similarly at offset +80
  v10 = *(_QWORD *)(releaseFunc + 32);
  // ... same pattern
  
  // Call the acquire function immediately
  v13 = *(_QWORD *)(a1 + 32);
  if ( !v13 )
    std::__throw_bad_function_call();
  return (*(__int64 (**)(...))(v13 + 48))(v13);  // acquire()
}
```

#### Destructor

```c
// Address: 0x34A310 (Flexo)

void __fastcall FFDestAnalyzerSynchronizer::_LockGuard::~_LockGuard(
        FFDestAnalyzerSynchronizer::_LockGuard *this)
{
  // Call the release function
  v7 = *((_QWORD *)this + 10);  // Release function at offset +80
  if ( !v7 )
    std::__throw_bad_function_call();
  (*(void (**)(...))(v7 + 48))(v7);  // release()
  
  // Destruct stored std::function objects
}
```

---

## 4. Helium GPU/GL Guards

The Helium framework (FCP's GPU rendering engine) uses guards extensively for OpenGL/Metal context management, texture lifetime, render graph validation, and profiling.

### 4.1 HGNode::GetGuardedOutput

**Binary**: Helium
**Purpose**: Validates render graph node output before use — catches deallocated or invalid nodes.

```c
// Address: 0x1195A0 (Helium)

HGNode *__fastcall HGNode::GetGuardedOutput(HGNode *this, HGRenderer *a2)
{
  // Call the virtual GetOutput method
  result = (*(__int64 (**)(HGNode *, HGRenderer *))(*(_QWORD *)this + 368LL))(this, a2);
  
  if ( result != 0 && result != this )
  {
    if ( *((int *)result + 4) < 0 )  // Reference count negative = deallocated
    {
      v4 = "HGNode::GetOutput (%s) received a de-allocated HGNode.";
      v3 = 0;  // Return NULL (safe failure)
    }
    else
    {
      if ( *((int *)result + 34) >= 0 )
        return result;  // Valid node — pass through
      
      // Invalid flag set — clear it and warn
      v3 = result;
      *((_DWORD *)result + 34) = 0;  // Clear invalid flag
      v4 = "HGNode::GetOutput (%s) received an invalid HGNode.";
    }
    
    v5 = (*(__int64 (**)(HGNode *))(*(_QWORD *)this + 48LL))(this);  // GetName()
    HGLogger::error(v4, v5);
    return v3;
  }
  return result;
}
```

### 4.2 HGGLSetCurrentContextGuard

**Binary**: Helium
**Purpose**: Saves the current OpenGL context on construction and restores it on destruction.

```c
// Address: 0x1AC150 (Helium) — Destructor

void __fastcall HGGLSetCurrentContextGuard::~HGGLSetCurrentContextGuard(
        HGGLSetCurrentContextGuard *this)
{
  if ( *((_BYTE *)this + 8) == 1 )  // Context was changed
  {
    v2 = *(_QWORD *)this;           // Saved context
    HGGLContextCGL::setCurrent(&v2); // Restore original
  }
  *(_QWORD *)this = 0;
}
```

### 4.3 HGGLState::SetCurrentContextGuard

**Binary**: Helium
**Purpose**: State-aware OpenGL context switching guard that integrates with `HGGLState`.

#### Constructor

```c
// Address: 0x14CE60 (Helium)

void __fastcall HGGLState::SetCurrentContextGuard::SetCurrentContextGuard(
        __int64 *a1, __int64 a2, HGGLContextPtr *a3)
{
  *a1 = a2;  // Store HGGLState reference
  HGGLContextPtr::HGGLContextPtr((a1 + 1), 0);  // Init saved context to null
  *((_BYTE *)a1 + 16) = 0;  // Not yet changed
  
  // Get the current context (from state or from GL directly)
  v6 = *a1;
  if ( v6 )
  {
    if ( *(_BYTE *)(v6 + 40) == 1 )
      savedCtx = *(_QWORD *)(v6 + 32);  // From state cache
    else
      savedCtx = HGGLGetCurrentContext();  // From GL
    *((_QWORD *)a1 + 1) = savedCtx;
  }
  
  // Only switch if target context differs from current
  currentCtx = HGGLContextPtr::ptr(a1 + 1);
  targetCtx  = HGGLContextPtr::ptr(a3);
  if ( currentCtx != targetCtx )
  {
    if ( *a1 )  // Have HGGLState — use state-aware path
      HGGLState::setCurrentContext(*a1, a3);
    else         // No state — raw GL call
      HGGLSetCurrentContext(a3);
    *((_BYTE *)a1 + 16) = 1;  // Mark as changed
  }
}
```

#### Destructor

```c
// Address: 0x14D060 (Helium)

void __fastcall HGGLState::SetCurrentContextGuard::~SetCurrentContextGuard(
        HGGLState::SetCurrentContextGuard *this)
{
  if ( *((_BYTE *)this + 16) == 1 )  // Context was changed
  {
    if ( *(_QWORD *)this )  // Have HGGLState
      HGGLState::setCurrentContext(*(_QWORD *)this, savedContext);
    else
      HGGLSetCurrentContext(savedContext);
  }
  HGGLContextPtr::~HGGLContextPtr(savedContext);
}
```

### 4.4 HGPagePullTexturesGuard

**Binary**: Helium
**Purpose**: Ensures GPU textures are available for rendering a page, then releases them on scope exit.

#### OpenGL Variant

```c
// Constructor — Address: 0x1158C0
void __fastcall HGPagePullTexturesGuard::HGPagePullTexturesGuard(
        HGPagePullTexturesGuard *this, HGNode *a2, HGPage *a3)
{
  *(_QWORD *)this = a3;
  if ( a2 )
    // Virtual call: node->PullTextures(page, 0)
    (*(*(_QWORD *)a2 + 456LL))(a2, a3, 0);
}

// Destructor — Address: 0x115920
void __fastcall HGPagePullTexturesGuard::~HGPagePullTexturesGuard(HGPage **this)
{
  v1 = *this;
  if ( v1 )
    HGPage::ReleaseTextures(v1);
}
```

#### Metal Variant

```c
// Constructor — Address: 0x115960
void __fastcall HGPagePullMetalTexturesGuard::HGPagePullMetalTexturesGuard(
        HGPagePullMetalTexturesGuard *this, HGNode *a2, HGPage *a3)
{
  *(_QWORD *)this = a3;
  if ( a2 )
    // Virtual call offset differs: +464 vs +456
    (*(*(_QWORD *)a2 + 464LL))(a2, a3, 0);
}
// Destructor is identical to the GL variant
```

### 4.5 HGAutoReleasePoolScopeGuard

**Binary**: Helium
**Purpose**: Creates an NSAutoreleasePool on construction, drains it on destruction — used in render threads that don't have a run loop.

```c
// Constructor — Address: 0x8A9A0
void __fastcall HGAutoReleasePoolScopeGuard::HGAutoReleasePoolScopeGuard(
        HGAutoReleasePoolScopeGuard *this)
{
  *(_QWORD *)this = objc_opt_new(&OBJC_CLASS___NSAutoreleasePool);
}

// Destructor — Address: 0x8A9E0
void __fastcall HGAutoReleasePoolScopeGuard::~HGAutoReleasePoolScopeGuard(id *this)
{
  objc_msgSend(*this, "drain");
  *this = 0;
}
```

### 4.6 HGTraceGuard / HGProfilerGuard

**Binary**: Helium
**Purpose**: Scoped logging and performance measurement.

#### HGTraceGuard

```c
// Constructor — Address: 0x1A85D0
void __fastcall HGTraceGuard::HGTraceGuard(HGTraceGuard *this, const char *file, 
                                            int level, const char *label)
{
  *(_OWORD *)this = 0;
  if ( level > 0 && (HGLogger::_enabled & 1) != 0 
       && (int)HGLogger::getLevel(file) >= level )
  {
    *(_QWORD *)this = strdup(label);
    snprintf(str, 0x64u, "/-- %s\n", label);
    HGLogger::print("%s", str);
    _InterlockedIncrement(&HGLogger::_indent);
    
    v6 = new HGProfiler();
    *((_QWORD *)this + 1) = v6;
    HGProfiler::start(v6);
  }
}

// Destructor — Address: 0x1A86D0
void __fastcall HGTraceGuard::~HGTraceGuard(HGProfiler **this)
{
  if ( *this )
  {
    HGProfiler::stop(*(this + 1));
    HGProfiler::getTime(*(this + 1));  // Returns elapsed ms
    snprintf(str, 0x64u, "\\-- %s : %f msec\n", (const char *)*this, elapsedMs);
    _InterlockedDecrement(&HGLogger::_indent);
    HGLogger::print("%s", str);
    free(*this);
  }
  if ( *(this + 1) )
    delete *(this + 1);
}
```

#### HGProfilerGuard / HGStats::ProfilerScopeGuard

```c
// HGProfilerGuard<0> constructor — Address: 0x1BBF00
uint64_t __fastcall HGProfilerGuard<(HGProfilerGuardMode)0>::HGProfilerGuard(
        uint64_t **a1, uint64_t *a2)
{
  *a1 = a2;
  if ( a2 )
    *a2 = mach_absolute_time();  // Start timestamp
}

// HGStats::ProfilerScopeGuard — Address: 0x97FB0
void __fastcall HGStats::ProfilerScopeGuard::ProfilerScopeGuard(
        HGStats::ProfilerScopeGuard *this, HGStats::UnitStatsImpl **a2, HGNode *a3)
{
  v3 = *a2;
  if ( *((_BYTE *)*a2 + 120) )  // Stats enabled?
  {
    *(_QWORD *)this = v3;
    Profiler = HGStats::UnitStatsImpl::getProfiler(v3, a3);
    *((_QWORD *)this + 1) = Profiler;
    HGStats::UnitStatsImpl::start(*(HGStats::UnitStatsImpl **)this, Profiler);
  }
  else
  {
    *(_QWORD *)this = 0;  // No-op if stats disabled
  }
}
```

---

## 5. AudioMixEngine Guards

**Binary**: AudioMixEngine

### STGraphOwner::FormatChangeGuard

Protects audio format changes in the Soundtrack audio graph:

```c
// Address: 0x2ECB0 (AudioMixEngine) — Destructor

void __fastcall STGraphOwner::FormatChangeGuard::~FormatChangeGuard(STGraphOwner **this)
{
  STGraphOwner *v1;

  v1 = *this;
  if ( v1 )
    STGraphOwner::EndFormatChanges(v1);
}
```

### STModuleUninitializeGuard

Ensures an audio unit is re-initialized after format changes, even if an exception is thrown:

```c
// Address: 0x292D0 (AudioMixEngine) — Destructor

void __fastcall STModuleUninitializeGuard::~STModuleUninitializeGuard(
        STModuleUninitializeGuard *this)
{
  OSStatus v1;

  if ( *((_BYTE *)this + 8) == 1 )  // Was uninitialized?
  {
    v1 = AudioUnitInitialize(*(AudioUnit *)(*(_QWORD *)this + 80LL));
    if ( v1 )
    {
      // Throw STError if re-initialization fails
      exception = __cxa_allocate_exception(0x20u);
      STError::STError(exception, v1,
        "::AudioUnitInitialize(mModule->GetUnit())",
        ".../AudioMixEngine-9169/Model/Module.cp",
        0x161u);
      __cxa_throw(exception, &typeid(STError), 0);
    }
  }
}
```

---

## 6. Safe Zones Overlay System

**Binary**: Ozone
**Class**: `OZSafeZonesOverlay` (13+ methods)
**Related**: `OZPreferenceManager`, `LKColor`

### Overview

The safe zones overlay draws two rectangular boundaries in the viewer:
- **Action-safe zone**: Area safe for important action (typically 5% inset)
- **Title-safe zone**: Area safe for text/titles (typically 10% inset)

### Class Structure

```
OZSafeZonesOverlay : OZOverlay : POOnScreenControl
  ├── _actionzoneLines: NSMutableArray  (line primitives for action zone)
  ├── _titlezoneLines: NSMutableArray   (line primitives for title zone)
  └── Inherits: _viewer, _delegate, _viewDelegate from POOnScreenControl
```

### Key Methods

#### Initialization

```c
// Address: 0x2682C0 (Ozone)

OZSafeZonesOverlay *__cdecl -[OZSafeZonesOverlay initWithHostDelegate:...](...)
{
  v6 = [super initWithHostDelegate:a3 andViewDelegate:a4 
              andObjectDelegate:a5 andChannel:a6];
  if ( v6 )
  {
    v6->_titlezoneLines  = [[NSMutableArray alloc] initWithCapacity:0];
    v6->_actionzoneLines = [[NSMutableArray alloc] initWithCapacity:0];
  }
  return v6;
}
```

#### Drawing Order

```c
// Address: 0x2683C0 (Ozone)

int __cdecl -[OZSafeZonesOverlay getDrawingOrder](...) {
  return -400;  // Draw behind most other overlays
}
```

#### Metal Support

```c
// Address: 0x2687D0 (Ozone)

char __cdecl -[OZSafeZonesOverlay supportsMetalRendering](...) {
  return 1;  // Yes, supports Metal rendering path
}
```

#### Main Rendering (newPrimitivesForContext:userInfo:)

The primary rendering function transforms safe zone margins through the camera matrix and creates line primitives:

```c
// Address: 0x2687E0 (Ozone) — Simplified

id __cdecl -[OZSafeZonesOverlay newPrimitivesForContext:userInfo:](...)
{
  if ( ![self.viewer isOSCEnabled] )
    return nil;
  
  camera = [self.viewDelegate getCamera];
  if ( camera.isOrthographic || !camera.isPerspective )
    return nil;
  
  // Get safe zone color from preferences
  color = OZPreferenceManager::getSafeZonesColor(OZPreferenceManager::Instance());
  
  result = [NSMutableArray array];
  transform = [self getFilmToViewOrModelViewTransform];
  [self removeViewScaleFactorFromTransform:transform];
  
  // ACTION SAFE ZONE
  actionMargin = [self actionSafeZoneMargin];
  [self verticesFromMargin:actionMargin topLeft:&tl topRight:&tr 
        bottomLeft:&bl bottomRight:&br];
  // Transform vertices through camera matrix (SIMD math)
  // ... matrix multiplication for each corner ...
  actionLines = [self linesFromCollection:self->_actionzoneLines 
                      topLeft:tl topRight:tr bottomLeft:bl bottomRight:br 
                      lineColor:color];
  [result addObjectsFromArray:actionLines];
  
  // TITLE SAFE ZONE
  titleMargin = [self titleSafeZoneMargin];
  [self verticesFromMargin:titleMargin topLeft:&tl topRight:&tr 
        bottomLeft:&bl bottomRight:&br];
  // ... same transform ...
  titleLines = [self linesFromCollection:self->_titlezoneLines 
                     topLeft:tl topRight:tr bottomLeft:bl bottomRight:br 
                     lineColor:color];
  [result addObjectsFromArray:titleLines];
  
  return [[NSArray alloc] initWithArray:result];
}
```

### Preference Management

```c
// OZPreferenceManager — stored in NSUserDefaults

// Get title safe percentage (default ~10%)
OZPreferenceManager::getSafeZonesTitlePercentage()
  -> [NSUserDefaults floatForKey:@"OZPreferenceManager::SafeZonesTitlePercentage"]

// Get action safe percentage (default ~5%)
OZPreferenceManager::getSafeZonesActionPercentage()
  -> [NSUserDefaults floatForKey:@"OZPreferenceManager::SafeZonesActionPercentage"]

// Set safe zones color
OZPreferenceManager::setSafeZonesColor(NSColor *color)
  -> [NSUserDefaults OZ_setNSColor:color forKey:@"OZPreferenceManager::SafeZonesColor"]

// Default color: +[LKColor ozDefaultSafeZonesColor]
  -> sRGB(0.0, 0.753, 1.0, 1.0)  // Cyan/light blue
```

---

## 7. __cxa_guard — Static Initialization Guards

**Binary**: All binaries
**Purpose**: Thread-safe initialization of C++ static local variables (compiler-generated).

### How It Works

When a C++ function has a `static` local variable with a non-trivial constructor, the compiler generates guard code:

```c
// Pattern seen throughout the codebase:

if ( __cxa_guard_acquire(&guard_variable) )
{
  // Initialize the static variable (runs exactly once)
  static_variable = new_value;
  __cxa_guard_release(&guard_variable);
}
// Use static_variable
```

### Examples Found

#### Singleton Pattern (LiGradientEnvCache)
```c
// Lithium binary — thread-safe singleton

LiGradientEnvCache *LiGradientEnvCache::instance()
{
  if ( __cxa_guard_acquire(&guard) )
  {
    instance = new LiGradientEnvCache();
    __cxa_guard_release(&guard);
  }
  return instance;
}
```

#### Mutex Initialization (Observers::ClassID)
```c
// Flexo — Address: 0x141DF10

void __fastcall Observers::ClassID(objc_object *a2)
{
  if ( __cxa_guard_acquire(&guard_for_sClassesMutex) )
  {
    __cxa_atexit(&std::mutex::~mutex, &sClassesMutex, &dword_0);
    __cxa_guard_release(&guard_for_sClassesMutex);
  }
  // Use sClassesMutex...
}
```

#### Hardware Decoder Limit
```c
// Flexo — Address: 0x10C3A20

__int64 maxNumPRFHWDecoders()
{
  if ( !guard && __cxa_guard_acquire(&guard) )
  {
    s_maxNumPRFHWDecoders = prioritizePerformanceOverMemory() ? 2 : 1;
    __cxa_guard_release(&guard);
  }
  return s_maxNumPRFHWDecoders;
}
```

### Distribution

`__cxa_guard_acquire/release/abort` symbols are present in virtually every binary:

| Binary | Has __cxa_guard |
|--------|----------------|
| Flexo | Yes |
| Final Cut Pro | Yes |
| Helium | Yes |
| Ozone | Yes |
| AudioMixEngine | Yes |
| AudioEffects | Yes |
| CoreAudioSDK | Yes |
| FxPlug | Yes |
| Lithium | Yes |
| ProCore | Yes |
| TimelineKit | Yes |
| AppleMediaServicesKit | Yes |

---

## 8. Event Locking: Could We Implement It?

> *"Could we modify things to enable some kind of event locking?"*

FCP has **no built-in event locking feature** — there is no `eventLock`, `lockEvent`, or `EventLock` symbol anywhere in the codebase. However, FCP has a deep, multi-layered locking infrastructure designed for concurrent data access safety that could potentially be leveraged or hooked to implement event-level protection via FCPBridge.

### FCP's Locking Architecture

FCP's editing model is protected by a three-layer locking system:

```
┌────────────────────────────────────────────────┐
│  Layer 3: Edit Action Layer                     │
│  FFEditActionMgr / FFUndoHandler               │
│  (canPerformEditAction, undoableBegin/End)      │
├────────────────────────────────────────────────┤
│  Layer 2: Model Coordinator Layer              │
│  FFEditingModelCoordinatorTo*Adapter           │
│  (writeAndWaitUsingBlock, readAndWaitUsingBlock)│
├────────────────────────────────────────────────┤
│  Layer 1: Lock Primitives Layer                │
│  FFSharedLock / PCDispatchLock / _FFModelLocker │
│  (_writeLock, _readLock, _writeUnlock)          │
└────────────────────────────────────────────────┘
```

### The Three Lock Layers

#### Layer 1: FFSharedLock — The Core Lock Primitive

`FFSharedLock` is a custom reader-writer lock with 38 methods. It is the foundation of all model protection in FCP.

**Key insight**: Most model objects (`FFModelObject`, `FFLibraryDocument`) return `+[FFSharedLock globalLock]` — a **process-wide singleton**. This means the entire FCP process shares ONE main lock for all editing operations.

```
FFSharedLock internals:
  _guard: NSCondition           — mutex for state changes
  _readers: CFMutableBag        — bag of pthread_t tracking read-lock holders
  _writer: FFThread*            — current write-lock holder
  _readLockCount                — reentrant counter
  _writeLockCount               — reentrant counter
  _writeRequested (atomic)      — signals readers to yield for pending writer
  _deferredWriteQueue           — deferred write dispatch queue
  _workQueue                    — model coordinator serialization queue
  _disableWritePrioritization   — toggleable write priority
```

**Write lock acquisition** (`_writeLock`):
1. Checks if current thread already holds write lock (reentrant)
2. Increments `_writeRequested` atomically (signals readers to yield)
3. Waits on `NSCondition` while `_writer != nil || readersExist`
4. Sets `_writer = currentThread`
5. Increments both `_readLockCount` and `_writeLockCount`

**Read lock acquisition** (`_readLock:`):
1. If current thread IS the writer → just increment counts (reentrant)
2. Otherwise waits while: writer active, writer waiting, or deferred write pending
3. Adds `pthread_t` to `_readers` bag

**Deferred write system**: Writes can be queued to the main thread:
```
queueDeferredWriteLockBlockOnMainThread: → sets _deferredWritePending
_deferredWriteHandler → executes on main thread
```

**Mouse/keyboard awareness**: During mouse drags (`sCurrentMouseButtons`), deferred writes may be deprioritized to maintain UI responsiveness.

#### Layer 2: _FFModelLocker — RAII Lock Wrapper

A C++ class providing RAII-style lock scoping, supporting multiple locks simultaneously:

```c
// Single lock
_FFModelLocker locker(sharedLock, FFModelLockActionWrite);
// block executes under write lock
// ~_FFModelLocker() releases

// Multiple locks (deadlock-free via CFSet iteration)
_FFModelLocker locker(lockArray, FFModelLockActionRead);
```

The multi-lock functions iterate a `CFMutableSet` of `FFSharedLock` objects:
```c
FFSharedWriteLockMultiple(CFSet* locks)   // iterates, calls _writeLock on each
FFSharedReadLockMultiple(CFSet* locks)    // iterates, calls _readLock on each
FFSharedWriteUnlockMultiple(CFSet* locks)
FFSharedReadUnlockMultiple(CFSet* locks)
```

#### Layer 3: PCDispatchLock — GCD-Based Lock

A simpler GCD-based reader-writer lock in ProCore:

```c
// Init
-[PCDispatchLock initForConcurrentReadAccess:YES]
  → dispatch_queue_create(..., DISPATCH_QUEUE_CONCURRENT)

// Read
-[PCDispatchLock lockForReadingUsingBlock:]
  → dispatch_sync(_synchronizationQueue, block)

// Write (barrier)
-[PCDispatchLock lockForWritingUsingBlock:]
  → dispatch_barrier_sync(_synchronizationQueue, block)
```

### Model Object Lock Hierarchy

Every model object has a `modelLockingObject` and `sharedLock`:

```
FFModelObject.sharedLock       → +[FFSharedLock globalLock]  (singleton!)
FFModelObject.libraryLock      → +[FFSharedLock globalLock]  (same!)
FFLibraryDocument.sharedLock   → +[FFSharedLock globalLock]
FFCatalog.sharedLock           → self._sharedLock  (per-catalog instance!)
FFCatalogDocument.sharedLock   → self._catalog.sharedLock
FFAnchoredObject.modelLockingObject → self
```

The resolution chain: `FFModelLockFromRef(object)` → `object.modelLockingObject.sharedLock`

### Storyline Locking

`FFStorylineLock` (12 methods) provides read/write locking scoped to storyline items:

```c
-[FFStorylineLock lockForReadingUsingBlock:]
  lockObj = FFModelLockingAPI(self->_lockingObject);
  lock = [lockObj libraryLock];
  _FFPerformModelReadUsingBlock(lock, block);

-[FFStorylineLock lockForWritingUsingBlock:]
  // Same pattern with write lock
```

`FFNullStorylineLock` is a no-op variant that just executes blocks directly.

### Editing Model Coordinators

Two adapter classes bridge editing operations to locks:

**FFEditingModelCoordinatorToModelCoordinatorAdapter**:
```c
writeAndWaitUsingBlock:
  if modelCoordinatorWritesAllowed → block()           // Already in write scope
  else if hasWriteLockScope → performAsyncBlockAndWait  // Queue and wait
  else if modelCoordinatorIsActive → _FFPerformModelWriteUsingBlock  // Acquire + run
  else → performAsyncChangesAndWait                     // Full queue + barrier + wait
```

**FFEditingModelCoordinatorToLibraryLockAdapter**:
```c
writeAndWaitUsingBlock:
  if isMainThread → _FFPerformModelWriteUsingBlock(self->_lock, block)
  else → dispatch_sync(main_queue, block)  // MUST be main thread for writes!
```

**Critical**: Library-level writes are **forced to the main thread** via `dispatch_sync(&_dispatch_main_q, ...)`.

### File-Level Locking (FFFileLock)

FCP has filesystem-level library directory locking via `FFFileLock` (33 methods):

```c
+[FFFileLock lockDirectory:error:]     // Lock a library bundle on disk
-[FFFileLock lock:]                    // Acquire (flock/advisory)
-[FFFileLock unlock:]                  // Release
-[FFFileLock isLocked]                 // Check state
-[FFFileLock allowLockRecovery]        // Stale lock recovery
-[FFFileLock lockInfoIdentifierMatches] // Verify lock owner identity
```

This prevents multiple FCP instances from modifying the same `.fcpbundle` simultaneously. Uses POSIX file descriptors and `NSURLFileResourceIdentifierKey`.

### Undo/Transaction System

`FFUndoHandler` (54 methods) wraps `NSUndoManager` with lock integration:

```
undoableBegin: → Push action onto _actionStack
             → _transactionPrepare (set FFUndoHandlerStack in model coordinator)
             → Suspend FFUndoPerformBlockHandler
             → _transactionBegin → [FFCatalog transactionBegin:] → [DSBridge transactionBegin:]

... model writes (under write lock) ...

undoableEnd:option:error: → Set action name
                         → Post FFUndoableEnd notification
                         → _transactionEnd → database commit via DSBridge
                         → Post FFUndoHandlerDidPerformAction
                         → Resume FFUndoPerformBlockHandler
```

### beginEditing / endEditing Pattern

Timeline sequences use a reference-counted editing scope:

```c
-[FFAnchoredSequence beginEditing]
  // Increments _editingCount
  // On first entry: processingUpdates(YES), _beginObservingEdits, _setEditing(YES)

-[FFAnchoredSequence endEditing:]
  // Decrements _editingCount  
  // On last exit: invalidates removed objects, processes deferred updates,
  //   _setEditing(NO), _endObservingEdits, processingUpdates(NO)
```

### Ozone Locking (Effects/Rendering)

The Ozone framework has its own C++ locking for scene objects:

```
OZLockingGroup (tree-based lock groups)
  acquireLocks()     → walk tree, lock each OZLocking object
  releaseLocks()     → walk tree, unlock each
  acquireReadLocks() → read-only variant
  
  WriteSentry (RAII) → ~WriteSentry() calls releaseLocks()
  ReadSentry (RAII)  → ~ReadSentry() calls releaseReadLocks()
```

### Possible Approaches for Event Locking via FCPBridge

#### Approach A: Intercept at the Edit Action Level (Recommended)

Swizzle `canPerformEditAction:withMenuItem:withSource:resultData:` on `FFEditActionMgr` (or its delegate) to reject edits targeting locked events.

The edit action flow is:
```
performEditAction: →
  delegate.activeSourceForEditAction:       → source
  delegate.activeDestinationForEditAction:  → destination  
  canPerformEditAction:withMenuItem:withSource:resultData: → YES/NO
  source.writeDataForEditAction:toPasteboardWithName:      → data
  destination.performEditAction:fromPasteboardWithName:    → execute
```

**Implementation**:
1. Maintain a set of "locked event" identifiers in FCPBridge
2. Swizzle `canPerformEditAction:` to check if the current timeline/sequence belongs to a locked event
3. Return `NO` to block the edit
4. Optionally show an alert via `NSAlert`

**Pros**: Fine-grained, per-event control; doesn't affect global lock state
**Cons**: Need to identify which event is targeted from the edit action context

#### Approach B: Intercept beginEditing on Sequences

Swizzle `-[FFAnchoredSequence beginEditing]` to return early for locked events:

```objc
// Pseudocode
- (void)swizzled_beginEditing {
  NSString *eventName = [[self event] name];
  if ([FCPBridge isEventLocked:eventName])
    return;  // Skip — no _beginObservingEdits, no _setEditing:YES
  [self original_beginEditing];
}
```

**Pros**: Catches all editing at the data model level
**Cons**: May cause inconsistent state if FCP expects beginEditing to always succeed

#### Approach C: Intercept undoableBegin

Swizzle `-[FFUndoHandler undoableBegin:]` to reject operations targeting locked events:

```objc
- (void)swizzled_undoableBegin:(id)actionName {
  if ([FCPBridge currentEditTargetsLockedEvent])
    return;  // No transaction = no edit
  [self original_undoableBegin:actionName];
}
```

**Pros**: Blocks at the transaction level — no partial state
**Cons**: Need to determine the target event from the action context

#### Approach D: Read Lock Flooding (Nuclear Option)

Since write locks wait for all readers, acquire a permanent read lock:

```objc
[[FFSharedLock globalLock] _readLock:0];
// Never release → all writes blocked forever
```

**This blocks the ENTIRE application**, not just one event. Only useful for a global "read-only mode".

#### Approach E: File-Level Locking

Use `FFFileLock` patterns to mark event directories as locked:

```objc
FFFileLock *lock = [FFFileLock lockDirectory:eventBundlePath error:&error];
```

**Pros**: Prevents saving, uses existing infrastructure
**Cons**: Doesn't prevent in-memory edits; only protects on-disk state

#### Recommended Strategy

**Combine Approach A + C**: Intercept at both the edit action level (UI) and the transaction level (model) for defense-in-depth:

1. **FCPBridge maintains**: `NSMutableSet *lockedEventUUIDs`
2. **API exposed**: `lock_event(event_uuid)` / `unlock_event(event_uuid)`
3. **Swizzle `canPerformEditAction:`**: Check if active sequence's event UUID is in locked set → return NO
4. **Swizzle `undoableBegin:`**: Secondary check at transaction level
5. **Visual indicator**: Add a lock icon overlay on locked events in the browser (via OSC)

This would give true per-event locking without affecting the global lock state or other events.

---

## Complete Guard Inventory

### All Guard Symbols by Binary

#### Flexo (Main FCP Framework)

| Symbol | Type | Address |
|--------|------|---------|
| `-[FFUndoGuard initWithLibraryItems:]` | ObjC | 0x51DA00 |
| `-[FFUndoGuard addGuard:]` | ObjC | 0x51D220 |
| `-[FFUndoGuard addToHandler:]` | ObjC | 0x51D240 |
| `-[FFUndoGuard guardAction:]` | ObjC | 0x51D4D0 |
| `-[FFUndoGuard undoFinished:]` | ObjC | 0x51D940 |
| `-[FFUndoGuard redoFinished:]` | ObjC | 0x51D880 |
| `-[FFUndoGuard updateItems]` | ObjC | 0x51DC00 |
| `-[FFUndoGuard dealloc]` | ObjC | 0x51DBB0 |
| `-[FFUndoHandler guard]` | ObjC | 0x51D200 |
| `-[FFUndoHandler setGuard:]` | ObjC | 0x51D210 |
| `-[FFUndoHandler appendGuardToStackIfNecessary]` | ObjC | 0x51CB70 |
| `+[FFUndoHandler registerGuardForLibraryItems:]` | ObjC | 0x51CBE0 |
| `+[FFOSCUtils getFFEnableGuards]` | ObjC | 0xCEA110 |
| `+[FFOSCUtils initialize]` (reads FFEnableGuards) | ObjC | 0xCEA220 |
| `+[FFOSCUtils observeValueForKeyPath:...]` | ObjC | 0xCEA120 |
| `FFFigStreamMutexGuard::FFFigStreamMutexGuard(...)` | C++ | 0x10AAC80 |
| `FFFigStreamMutexGuard::~FFFigStreamMutexGuard()` | C++ | 0x10A0900 |
| `FFSharedLockRAIIGuardLockAndUnlocker::~...()` | C++ | 0x2AC100 |
| `-[FFSharedLock _updateDWQStateWhileHoldingGuard]` | ObjC | 0x2ABBF0 |
| `FFAudioGraph::SuspendUpdatesGuard::~...()` | C++ | 0x83E220 |
| `FFAudioGraph::FormatChangeGuard::~...()` | C++ | 0x5F090 |
| `FFDestAnalyzerSynchronizer::_LockGuard::_LockGuard(...)` | C++ | 0x34A390 |
| `FFDestAnalyzerSynchronizer::_LockGuard::~_LockGuard()` | C++ | 0x34A310 |
| `HGPagePullTexturesGuard::HGPagePullTexturesGuard(...)` | C++ thunk | 0x143DDDE |
| `HGPagePullTexturesGuard::~...()` | C++ thunk | 0x143DDE4 |
| `HGPagePullMetalTexturesGuard::HGPagePullMetalTexturesGuard(...)` | C++ thunk | 0x143DE44 |
| `HGPagePullMetalTexturesGuard::~...()` | C++ thunk | 0x143DE4A |
| `std::__exception_guard_exceptions<...KaiserWindow...>` | C++ | 0x557D50+ |
| `std::__exception_guard_exceptions<...FFAudioPanAdvancedSettingChannelKey...>` | C++ | 0xC5BE80 |
| `std::__exception_guard_exceptions<...FFVTDecompressionSession...>` | C++ | 0x4ACD50 |
| `std::__exception_guard_exceptions<...MTLBuffer...>` | C++ | 0x557D50 |
| `std::__exception_guard_exceptions<...OMRgbChar...>` | C++ | 0xD2D6A0 |
| `std::__exception_guard_exceptions<...FFVideoScopesRenderer...>` | C++ | 0x557980 |
| `std::__exception_guard_exceptions<...ProResRaw...>` | C++ | 0xAB6780 |
| `std::__exception_guard_exceptions<...FFAudioUnitParameterInfo...>` | C++ | 0x595BE0 |
| `__insertion_sort_unguarded<...ProResRaw...>` | C++ | 0x910180 |
| `__cxa_guard_acquire` | C ABI | 0x143EAD4 |
| `__cxa_guard_release` | C ABI | 0x143EADA |
| `__cxa_guard_abort` | C ABI | 0x143EACE |

#### Helium (GPU Rendering)

| Symbol | Type | Address |
|--------|------|---------|
| `HGNode::GetGuardedOutput(HGRenderer*)` | C++ | 0x1195A0 |
| `HGGLSetCurrentContextGuard::~...()` (D1) | C++ | 0x1AC150 |
| `HGGLSetCurrentContextGuard::~...()` (D2) | C++ | 0x1AC110 |
| `HGGLState::SetCurrentContextGuard::SetCurrentContextGuard(...)` | C++ | 0x14CE60 |
| `HGGLState::SetCurrentContextGuard::~...()` (D1) | C++ | 0x14D0D0 |
| `HGGLState::SetCurrentContextGuard::~...()` (D2) | C++ | 0x14D060 |
| `HGPagePullTexturesGuard::HGPagePullTexturesGuard(...)` | C++ | 0x1158C0 |
| `HGPagePullTexturesGuard::~...()` (D1) | C++ | 0x115940 |
| `HGPagePullTexturesGuard::~...()` (D2) | C++ | 0x115920 |
| `HGPagePullMetalTexturesGuard::HGPagePullMetalTexturesGuard(...)` | C++ | 0x115960 |
| `HGAutoReleasePoolScopeGuard::HGAutoReleasePoolScopeGuard()` | C++ | 0x8A9A0 |
| `HGAutoReleasePoolScopeGuard::~...()` (D1) | C++ | 0x8AA10 |
| `HGAutoReleasePoolScopeGuard::~...()` (D2) | C++ | 0x8A9E0 |
| `HGStackStateGuard::HGStackStateGuard(HGExecutionUnit*)` | C++ | 0x13E380 |
| `HGTraceGuard::HGTraceGuard(...)` | C++ | 0x1A85D0 |
| `HGTraceGuard::~...()` (D1) | C++ | 0x1A8730 |
| `HGTraceGuard::~...()` (D2) | C++ | 0x1A86D0 |
| `HGProfilerGuard<0>::HGProfilerGuard(...)` | C++ | 0x1BBF00 |
| `HGStats::ProfilerScopeGuard::ProfilerScopeGuard(UnitStats, HGNode)` | C++ | 0x97FB0 |
| `HGStats::ProfilerScopeGuard::ProfilerScopeGuard(UnitStats, OP)` | C++ | 0x98160 |
| `HGStats::ProfilerScopeGuard::ProfilerScopeGuard(UnitStats, OP, x, x)` | C++ | 0x98280 |

#### AudioMixEngine

| Symbol | Type | Address |
|--------|------|---------|
| `STGraphOwner::FormatChangeGuard::~...()` | C++ | 0x2ECB0 |
| `STModuleUninitializeGuard::~...()` | C++ | 0x292D0 |
| `__cxa_guard_acquire` | C ABI | 0x4B0DA |
| `__cxa_guard_release` | C ABI | 0x4B0E0 |
| `__cxa_guard_abort` | C ABI | 0x4B0D4 |

#### Ozone (Effects/Rendering)

| Symbol | Type | Address |
|--------|------|---------|
| `OZSafeZonesOverlay` (13 methods) | ObjC class | 0x2682C0+ |
| `OZPreferenceManager::getSafeZonesColor` | C++ | 0x1550E0 |
| `OZPreferenceManager::setSafeZonesColor` | C++ | 0x155110 |
| `OZPreferenceManager::getSafeZonesTitlePercentage` | C++ | 0x155230 |
| `OZPreferenceManager::getSafeZonesActionPercentage` | C++ | 0x1551A0 |
| `+[LKColor ozDefaultSafeZonesColor]` | ObjC | 0x5211A0 |

#### Other Binaries

| Binary | Symbol | Type |
|--------|--------|------|
| AudioEffects | `std::__exception_guard_exceptions<...KaiserWindow...>` | C++ |
| Final Cut Pro | `__cxa_guard_acquire/release` | C ABI |
| FxPlug | `__cxa_guard_acquire/release/abort` | C ABI |
| CoreAudioSDK | `__cxa_guard_acquire/release/abort` | C ABI |
| AppleMediaServicesKit | `__cxa_guard_acquire/release/abort` | C ABI |

---

## Key Classes Reference

### Guard-Related Classes

| Class | Binary | Methods | Role |
|-------|--------|---------|------|
| `FFUndoGuard` | Flexo | 8 | Undo/redo library protection |
| `FFUndoHandler` | Flexo | 54 | Undo management + guard integration |
| `FFOSCUtils` | Flexo | 21 | On-screen control utils (guard toggle) |
| `FFSharedLock` | Flexo | 38 | Core reader-writer lock |
| `FFStorylineLock` | Flexo | 12 | Storyline-scoped locking |
| `FFNullStorylineLock` | Flexo | 6 | No-op lock |
| `FFFileLock` | Flexo | 33 | File-level library locking |
| `FFEditActionMgr` | Flexo | ~60 | Edit action dispatch |
| `PCDispatchLock` | ProCore | 8 | GCD-based reader-writer lock |
| `OZSafeZonesOverlay` | Ozone | 13 | Safe zone rendering |
| `OZLockingGroup` | Ozone | ~12 | Scene object lock groups |

### Lock Hierarchy

```
+[FFSharedLock globalLock]          ← process-wide singleton
  ├── FFModelObject.sharedLock      ← returns globalLock
  ├── FFLibraryDocument.sharedLock  ← returns globalLock
  ├── _FFModelLocker (RAII)         ← wraps one or more FFSharedLocks
  ├── _FFPerformModelWriteUsingBlock ← acquires write lock + runs block
  ├── _FFPerformModelReadUsingBlock  ← acquires read lock + runs block
  └── FFStorylineLock              ← delegates to libraryLock

FFCatalog._sharedLock               ← per-catalog instance (separate from global)
PCDispatchLock                       ← independent GCD locks in ProCore/TimelineKit
OZLockingGroup                       ← Ozone scene-level lock trees
```

---

*Report generated by analyzing decompiled Final Cut Pro binaries via FCPBridge's fcp-search MCP server. All addresses are from FCP 11.1 / Flexo-44000.5.166.*

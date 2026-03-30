# FCPBridge

Direct in-process control of Final Cut Pro via dylib injection. FCPBridge loads a custom framework into FCP's process space, giving you full access to all 78,000+ ObjC classes and their methods through a JSON-RPC interface and MCP server.

## What This Does

FCPBridge injects a dynamic library into a re-signed copy of Final Cut Pro that:

- Exposes the entire ObjC runtime (78,000+ classes, including all private APIs)
- Runs a JSON-RPC 2.0 server on `127.0.0.1:9876` for external control
- Provides an MCP server for AI-assisted FCP automation
- Swizzles out CloudKit/ImagePlayground calls that crash without iCloud entitlements
- Gives direct access to Flexo, Ozone, TimelineKit, LunaKit, and all internal frameworks

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Final Cut Pro (modded copy)                    │
│  ┌───────────────────────────────────────────┐  │
│  │  FCPBridge.framework (injected via        │  │
│  │  LC_LOAD_DYLIB)                           │  │
│  │                                           │  │
│  │  - ObjC runtime introspection             │  │
│  │  - JSON-RPC server on TCP :9876           │  │
│  │  - Method swizzling                       │  │
│  │  - CloudContent crash prevention          │  │
│  └───────────┬───────────────────────────────┘  │
│              │ direct objc_msgSend              │
│  ┌───────────▼───────────────────────────────┐  │
│  │  Flexo, Ozone, TimelineKit, LunaKit ...  │  │
│  │  (78,000+ ObjC classes)                   │  │
│  └───────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────┘
                       │ TCP :9876
        ┌──────────────▼──────────────┐
        │  MCP Server (mcp/server.py) │
        │  Python Client              │
        │  nc / curl / any TCP client │
        └─────────────────────────────┘
```

## Quick Setup (Patcher)

The easiest way to set up FCPBridge:

```bash
git clone https://github.com/elliotttate/FCPBridge.git
cd FCPBridge
./patcher/patch_fcp.sh
```

This automatically:
1. Copies FCP to `~/Desktop/FinalCutPro_Modded/`
2. Builds the FCPBridge dylib from source
3. Injects it into the FCP binary
4. Re-signs everything (no sandbox, library validation disabled)
5. Patches CloudContent/ImagePlayground crash points
6. Creates `.mcp.json` for Claude Code integration

Then just launch the modded FCP and connect.

### Patcher Options

```bash
./patcher/patch_fcp.sh --dest ~/my-fcp    # Custom destination
./patcher/patch_fcp.sh --rebuild           # Rebuild dylib only (after code changes)
./patcher/patch_fcp.sh --uninstall         # Remove the modded copy
```

## Manual Setup

### Prerequisites

- macOS 14+ with Xcode Command Line Tools
- Final Cut Pro installed at `/Applications/Final Cut Pro.app`
- Python 3 with `mcp` package (`pip install mcp`)

### 1. Create the Modded FCP Copy

```bash
# Copy FCP
mkdir -p ~/Desktop/FinalCutPro_Modded
cp -R "/Applications/Final Cut Pro.app" ~/Desktop/FinalCutPro_Modded/"Final Cut Pro.app"

# Copy MAS receipt (needed for licensing)
cp "/Applications/Final Cut Pro.app/Contents/_MASReceipt/receipt" \
   ~/Desktop/FinalCutPro_Modded/"Final Cut Pro.app/Contents/_MASReceipt/receipt"

# Remove quarantine
xattr -cr ~/Desktop/FinalCutPro_Modded/"Final Cut Pro.app"
```

### 2. Build and Inject FCPBridge

```bash
# Build the dylib
make all

# Deploy to the modded app (creates framework, signs everything)
make deploy

# Inject LC_LOAD_DYLIB into the binary (requires insert_dylib)
# Build insert_dylib: git clone https://github.com/tyilo/insert_dylib.git && cd insert_dylib && clang -o /usr/local/bin/insert_dylib insert_dylib/main.c -framework Foundation
insert_dylib --inplace --all-yes \
    "@rpath/FCPBridge.framework/Versions/A/FCPBridge" \
    ~/Desktop/FinalCutPro_Modded/"Final Cut Pro.app"/Contents/MacOS/"Final Cut Pro"

# Re-sign with custom entitlements (no sandbox, library validation disabled)
codesign --force --sign - --entitlements entitlements.plist \
    ~/Desktop/FinalCutPro_Modded/"Final Cut Pro.app"
```

### 3. Launch

```bash
~/Desktop/FinalCutPro_Modded/"Final Cut Pro.app"/Contents/MacOS/"Final Cut Pro"
```

Check `~/Desktop/fcpbridge.log` for startup messages. You should see:
```
[FCPBridge] Control server listening on 127.0.0.1:9876
```

## Usage

### Python Client (Interactive REPL)

```bash
python3 Scripts/fcpbridge_client.py
```

```
fcpbridge> version
fcpbridge> classes FFAnchored
fcpbridge> methods FFPlayer
fcpbridge> props FFAnchoredSequence
fcpbridge> super FFAnchoredSequence
fcpbridge> ivars FFLibrary
```

### Direct TCP

```bash
echo '{"jsonrpc":"2.0","method":"system.version","id":1}' | nc 127.0.0.1 9876
```

### MCP Server

Add to your `.mcp.json`:
```json
{
  "mcpServers": {
    "fcpbridge": {
      "command": "python3",
      "args": ["/path/to/FCPBridge/mcp/server.py"]
    }
  }
}
```

## JSON-RPC API

| Method | Description |
|--------|-------------|
| `system.version` | FCPBridge + FCP version info |
| `system.getClasses` | List/filter all ObjC classes |
| `system.getMethods` | List methods on a class |
| `system.getProperties` | List @property declarations |
| `system.getIvars` | List instance variables |
| `system.getProtocols` | List protocol conformances |
| `system.getSuperchain` | Get inheritance chain |
| `system.callMethod` | Call any ObjC class/instance method |

### Key FCP Internal Classes

| Class | Methods | Purpose |
|-------|---------|---------|
| `FFAnchoredTimelineModule` | 1435 | Primary timeline controller |
| `FFAnchoredSequence` | 1074 | Timeline data model |
| `FFLibrary` | 203 | Library container |
| `FFLibraryDocument` | 231 | Library persistence |
| `FFEditActionMgr` | 42 | Edit command dispatcher |
| `FFPlayer` | 228 | Playback engine |
| `PEAppController` | 484 | App controller |

### Key FCP Frameworks

| Prefix | Framework | Classes | Purpose |
|--------|-----------|---------|---------|
| FF | Flexo | 2849 | Core engine, timeline, editing |
| OZ | Ozone | 841 | Effects, compositing, color |
| PE | ProEditor | 271 | App controller, windows |
| LK | LunaKit | 220 | UI framework |
| TK | TimelineKit | 111 | Timeline UI |
| IX | Interchange | 155 | FCPXML import/export |

## How It Works

1. **App duplication**: FCP is copied to a writable location
2. **Re-signing**: Ad-hoc signature with entitlements that disable library validation and sandbox
3. **Binary patching**: `insert_dylib` adds an `LC_LOAD_DYLIB` command pointing to `FCPBridge.framework`
4. **Auto-load**: On launch, dyld loads FCPBridge before `main()` runs
5. **Constructor**: `__attribute__((constructor))` caches class references and swizzles CloudContent
6. **Server start**: On `NSApplicationDidFinishLaunchingNotification`, starts TCP server on port 9876
7. **Runtime access**: All calls use `objc_getClass()`, `objc_msgSend()`, and the ObjC runtime API

## Project Structure

```
FCPBridge/
├── patcher/
│   └── patch_fcp.sh           # One-command patcher (copies, builds, injects, signs)
├── Sources/
│   ├── FCPBridge.h            # Public header
│   ├── FCPBridge.m            # Constructor, class caching, CloudContent fix
│   ├── FCPBridgeRuntime.m     # ObjC runtime utilities
│   ├── FCPBridgeServer.m      # JSON-RPC TCP server (28 tool endpoints)
│   └── FCPBridgeSwizzle.m     # Method swizzling infrastructure
├── Scripts/
│   ├── fcpbridge_client.py    # Interactive Python REPL client
│   └── launch.sh             # Launch helper script
├── mcp/
│   └── server.py             # MCP server (28 tools)
├── CLAUDE.md                  # Skill documentation for Claude
├── Makefile                   # Build, deploy, launch targets
└── entitlements.plist         # Unsandboxed entitlements for re-signing
```

## License

MIT

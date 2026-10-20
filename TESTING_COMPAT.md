# Testing Compatibility Reports

## Build modes and debug features

### Release build (production)
The standard `./build.sh` creates a release build with **all QA hooks enabled**:

```bash
./build.sh
# Creates Vermut.app in the repo root
```

### Debug build
For development with debug symbols:

```bash
swift build -c debug
# Binary: .build/debug/Vermut
```

**Both release and debug builds support:**
- `vermut.compat.debugJsonPath` UserDefaults override
- `VERMUT_DEBUG_FEEDBACK=1` environment variable

---

## QA Testing

### Test with a local JSON file

Works in **both debug and release builds**.

1. Create a test compatibility JSON file:
```bash
cat > /tmp/test-compat.json << 'EOF'
{
  "games": [
    {
      "store": "steam",
      "gameId": "620",
      "gameName": "Portal 2",
      "byGraphics": {
        "dxmt": { "perfect": 42, "issues": 3, "broken": 1 },
        "dxvk": { "perfect": 12, "issues": 5, "broken": 0 }
      },
      "recommended": "dxmt",
      "totalReports": 63
    }
  ],
  "generated": 1730000000,
  "reportCount": 63
}
EOF
```

2. Configure Vermut to use it (plain path or file:// URL):
```bash
# Plain filesystem path (preferred)
defaults write com.vermut.Vermut vermut.compat.debugJsonPath "/tmp/test-compat.json"

# Or file:// URL
defaults write com.vermut.Vermut vermut.compat.debugJsonPath "file:///tmp/test-compat.json"
```

3. Launch Vermut and check Library for badges:
```bash
# Release build
open -a Vermut

# Debug build
.build/debug/Vermut
```

Decode failures are logged to Console.app.

### Trigger the feedback banner

Works in **both debug and release builds**.

**Option 1: Environment variable (easiest)**
```bash
# Release build
VERMUT_DEBUG_FEEDBACK=1 open -a Vermut

# Debug build
VERMUT_DEBUG_FEEDBACK=1 .build/debug/Vermut
```

A test session (Portal 2, 10 min playtime) will trigger the banner 2 seconds after launch.

**Option 2: Programmatically (from debugger)**
```swift
let session = GameSession(
    store: .steam,
    gameId: "620",
    gameName: "Portal 2",
    engine: "vermut-wine",
    graphics: "dxmt",
    startTime: Date().addingTimeInterval(-600) // 10 min ago
)
CompatibilityService.shared.triggerDebugFeedback(
    session: session,
    autoDetectedCrash: false
)
```

### Clear debug settings

```bash
defaults delete com.vermut.Vermut vermut.compat.debugJsonPath
```

---

## Running builds

### Release build
```bash
# Standard release build
./build.sh

# Launch normally
open -a Vermut

# Or with debug trigger
VERMUT_DEBUG_FEEDBACK=1 open -a Vermut
```

### Debug build
```bash
# Build
swift build -c debug

# Launch
.build/debug/Vermut

# Or with debug trigger
VERMUT_DEBUG_FEEDBACK=1 .build/debug/Vermut
```

Both builds support the same QA features.

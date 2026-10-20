# Testing Compatibility Reports

## Building for debug

Build in debug mode to get full debug symbols:

```bash
swift build -c debug
```

The debug binary will be at:
```
.build/debug/Vermut
```

## Running a debug build

```bash
# Run the debug build directly
.build/debug/Vermut

# Or with the debug feedback trigger:
VERMUT_DEBUG_FEEDBACK=1 .build/debug/Vermut
```

## QA Testing

### Test with a local JSON file

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

2. Configure Vermut to use it:
```bash
# Plain filesystem path (preferred)
defaults write com.vermut.Vermut vermut.compat.debugJsonPath "/tmp/test-compat.json"

# Or file:// URL
defaults write com.vermut.Vermut vermut.compat.debugJsonPath "file:///tmp/test-compat.json"
```

3. Launch Vermut (release or debug build) and check Library for badges

### Trigger the feedback banner

**Option 1: Environment variable (easiest)**
```bash
VERMUT_DEBUG_FEEDBACK=1 open -a Vermut
# Or for a local build:
VERMUT_DEBUG_FEEDBACK=1 .build/debug/Vermut
```

**Option 2: Programmatically (from code/debugger)**
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

## Release build (production)

The standard `build.sh` creates a release build:

```bash
./build.sh
# Creates Vermut.app in the repo root
```

Release builds still support QA overrides (debugJsonPath and VERMUT_DEBUG_FEEDBACK).

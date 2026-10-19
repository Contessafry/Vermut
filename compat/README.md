# Community Compatibility Reports

This folder contains the aggregated compatibility data from community reports submitted via GitHub issues.

## `compatibility.json`

Automatically generated and updated daily by the [Process Compatibility Reports workflow](../.github/workflows/process-compat-reports.yml).

Contains per-game compatibility counts by graphics layer, plus recommended settings based on community feedback.

**Format:**

```json
{
  "games": [
    {
      "store": "steam",
      "gameId": "123456",
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
```

## How to contribute

Play a game on Vermut for 5+ minutes, then fill out a compatibility report via the in-app prompt or [directly on GitHub](https://github.com/Contessafry/Vermut/issues/new?template=compatibility-report.yml).

Reports are validated and aggregated automatically. Thank you for helping the community!

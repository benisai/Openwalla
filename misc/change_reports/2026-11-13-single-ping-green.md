# Single Green For Ping Charts

- Version: 1.0.567+469.
- Removed the light-green latency band from the shared ping color function. All successful readings below the configured warning threshold now use the existing green (`#20CF70`).
- Applies to the dashboard Network Performance timeline, the Network Performance page timeline, and the Ping Test bar graph through their existing shared function.
- Configured warning thresholds, yellow warnings, red failures, and gray missing-data states are unchanged. CPU/resource colors are unchanged.
- Updated color expectations and rendered-bar checks. All 20 focused tests passed; analyzer and `git diff --check` passed.
- No APK built or live-router changes made.

# Swap Ping Greens

- Swap the shared green shades: below 30% of the configured ping threshold is now
  dark green; 30% up to the threshold is now light green.
- Applies to the dashboard timeline, Network Performance timeline, and Ping Test
  bars through the existing shared palette.
- Threshold calculations and yellow/red/gray states remain unchanged.
- Update boundary and rendered-bar expectations. App version 1.0.548+450.
- No router changes or APK build.
- All 20 focused color/rendering tests passed; targeted analyzer and diff checks passed.

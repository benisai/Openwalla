# Usage Chart Units

## Changes

- Added Chart Units to Usage Settings: KB, MB, GB (default), or TB. Uses the existing 1,024-byte conversion convention; monthly limits remain in GB.
- Saved per-router in `openwalla.dashboard.usage_chart_unit` and the existing offline Statistics snapshot. Missing or invalid settings default to GB. The older monthly settings editor preserves the unit when saving other preferences.
- Interface usage bars display numbers only, with `Values in XX` under the timeframe. All swipe ranges use the selected unit. Monthly daily chart axis uses the same unit and header label.
- Summary totals and tap details retain explicit byte units. Download/upload colors, data collection, stacked bars, swipe controls and tap details are unchanged.
- Small nonzero buckets retain meaningful decimal precision instead of rounding to zero. Label spacing accounts for formatted width and larger text.
- Returning from Usage Settings refreshes the setting immediately. Settings heading and monthly summary wrap on narrow screens; chart legends fit and axis edge labels stay inside their bounds.
- Version: `1.0.581+483`.

## Verification

- 34 tests passed, covering all units, numeric-only labels, zero/tiny values, settings selection/save, UCI persistence, offline snapshots, returning from settings, swiping and monthly tooltip regressions.
- Checked narrow/desktop layouts including 320px with 1.5x text; rendered a narrow-screen screenshot using real fonts.
- Static analysis and whitespace checks passed. No APK built or router accessed. Existing user APK/attachment changes were left untouched.

# Monthly Usage Bar Tooltips

## Changes

- Monthly daily bars now show a tap tooltip with the full date, total usage, download, and upload.
- Tooltip colors, typography, and compact padding follow the existing interface usage graph.
- Uses Flutter's bounded tooltip overlay, with a five-second display duration and automatic switching/dismissal when tapping elsewhere.
- Each full-height day slot is tappable, including days without recorded traffic. Missing data says `No usage data`; an actual zero-byte sample shows zero totals.
- Stores each bar's calendar date with its daily usage data and shares the existing monthly byte formatter across summaries, axis labels, and tooltips.
- Reads already loaded samples; taps do not request router data and work with cached usage too.
- Version: `1.0.579+481`.

## Scope and Verification

- Monthly Usage screen, its existing test file, version, and this report only.
- No backend, collection, cache, or router script changes.
- 14 tests passed, including date/totals, zero versus missing data, switching tips, edge bounds at 320/430px with large text, and existing month-length/date-axis regressions.
- Static analysis and whitespace checks passed.
- Rendered and visually inspected a tooltip on a 320px screen with 1.5x text.
- No APK built or live-router settings changed. Existing user APK changes were left untouched.

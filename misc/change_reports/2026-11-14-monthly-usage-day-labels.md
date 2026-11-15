# Readable Monthly Usage Dates

## Changes

- Replaced the crowded 1/5/10/15/20/25/end labels with 1, 7, 14, 21, and the actual final day of the month.
- Dates now use a separate measured axis rather than being constrained to individual narrow daily bar columns.
- Endpoint labels stay inside the plot area. Intermediate labels are omitted if unusually large text would cause overlap; font size is not reduced.
- Tick positions follow the matching daily bar centers, including RTL direction.
- Monthly total and days-left text can wrap on narrow/large-text layouts instead of overflowing.
- Version: `1.0.578+480`.

## Scope and Verification

- Monthly Usage screen, focused axis/layout tests, version, and this report only.
- No traffic collection, caching, statistics totals, or backend changes.
- 10 tests passed across 28/29/30/31-day months, normal/large text, and 320/430px full-page layouts.
- Rendered and visually inspected the 320px page with 1.5x text; both digits remain readable.
- Static analysis and whitespace checks passed.
- No APK built or live-router settings changed. Existing user APK changes were left untouched.

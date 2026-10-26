# Interface Usage Header Total

- Move the usage total out of the bar plot and into a centered header column,
  between the interface title and right-aligned timeframe.
- Calculate the header total from the selected range's displayed buckets, using
  the same memoized data future and bucket logic as the chart.
- Preserve swipe navigation, bar totals, stacked download/upload data and tooltips.
- Bound header columns to avoid overlap on small screens or long interface names.
- App version 1.0.550+452. No router changes or APK build.
- Verification: focused widget tests cover centered, non-overlapping headers at
  360, 390 and 1280 pixels, including total updates after swiping timeframes.
- A 320-pixel full-page check exposed an existing overflow outside the header;
  unrelated layout changes are excluded from this update.

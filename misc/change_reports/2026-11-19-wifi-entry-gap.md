# Wi-Fi Entry Gap

- Reproduced a temporary blank area above Wi-Fi cards when the inner list inherited an overscrolled primary controller: the first card appeared 213px below the tab label instead of the normal 33px.
- Wi-Fi and Repeater lists now opt out of the surrounding primary scroll controller and have distinct PageStorage keys. Their scroll positions remain independent across tab changes and data updates.
- Production change is four lines in the Wi-Fi pager. No radio/password/repeater configuration commands, API calls, refresh timing or wired-screen behavior changed.
- Regression tests check the first frame with an inherited negative offset, pull-to-refresh, changing tabs, early frames, and delayed updates from UCI-only configuration to runtime data. The inherited-offset test failed before the fix and passes afterward.
- Scope: Interfaces screen scroll configuration, focused tests, version and report. No router changes or APK build; existing user APK/attachment changes preserved.
- Version: `1.0.587+489`.
- Verification: 43 focused tests passed when run sequentially, including layout, interface visibility, wired-only behavior, repeater reconnect/removal and Wi-Fi sharing cache. Static analysis and whitespace checks passed. No live router was accessed.

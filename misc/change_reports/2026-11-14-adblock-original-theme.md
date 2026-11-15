# AdBlock Original Theme with Current Controls

## Request and Reference

Compare the UI before the recent AdBlock redesign and reuse its visual styling without losing the current layout or features. Reviewed the pre-simplification screen at `8d84c85` and the subsequent design commits.

## Changes

- Restored the earlier `colorScheme.surface` background, 8px corners, and original outline opacity.
- Replaced the large tinted icon tiles and mixed accent colors with compact 22px theme-primary icons.
- Restored heavier section-heading typography, muted state labels, and tighter vertical padding.
- Added subtle theme-accent highlighting to selected feeds, retaining standard checkbox controls rather than restoring the old nested feed tiles.
- Kept the current order, immediate-save switches, collapsible feeds, Reports navigation, and hiding of dependent panels when Block Ads is off.
- Version: `1.0.575+477`.

## Scope and Verification

- AdBlock screen, its widget tests, version, and this report only.
- No backend, reporting scheduler, router script, ACL, or installer changes.
- 14 AdBlock tests passed, including theme styling, selected feeds, saves, visibility, retained settings, navigation, and narrow layouts in light/dark themes with large text.
- Static analysis and whitespace checks passed.
- Rendered and visually inspected collapsed and expanded views using Openwalla's dark theme colors.
- No APK built or live-router settings changed. Existing user APK changes were left untouched.

# AdBlock Dependent Panel Visibility

## Changes

- Show Feeds, Safe Search, and Reports only when Block Ads is enabled.
- Preserve all dependent settings when hiding the controls; re-enabling restores them.
- A failed disable restores the enabled UI and dependent panels through the existing save rollback.
- Version: `1.0.574+476`.

## Scope and Verification

- AdBlock screen, its widget tests, version, and this report only.
- No backend, router script, installer, or report-generation changes.
- 13 AdBlock tests passed, including initial disabled state, hide/show, retained settings, failed disable, saving, navigation, and responsive layouts.
- Static analysis and diff whitespace checks passed.
- No APK built; existing user APK changes left untouched. No live-router settings changed.

# Full-Page Port Forwarding Editor

- Version: 1.0.568+470.
- Replaced the add/edit bottom sheet with a dedicated Port Forwarding page. Network and Rules now open the same editor and refresh their lists after a successful save or deletion.
- Layout follows the supplied reference: top-bar Save, compact labeled fields, an optional different-internal-port switch, grouped protocol radio choices, an enabled switch, and a destructive Delete action for existing rules. Colors/surfaces use the existing Openwalla theme; the form is width-constrained on wide screens.
- Kept Destination IP because rules opened from Network/Rules do not have an implicit device destination. Source/destination firewall zones and the existing router-target option remain under Advanced. Existing custom zones and imported protocol values are retained rather than silently replaced.
- Added single-port and ascending port-range validation (1-65535), whitespace normalization around range separators, and IP-address validation. Internal ports match the external port/range unless the override is enabled.
- Enabled-state changes are staged until Save. The existing backend now accepts the flag; editing explicitly normalizes legacy `disabled=1` when setting enabled/disabled, while callers omitting the optional update flag retain the previous behavior.
- Save/Delete lock the form while pending; failures retain edits. Back navigation confirms discarding unsaved changes. Delete requires confirmation. Removed the superseded modal editor, section-label helper, and Rules port-forward detail sheet.
- No firewall enforcement/reload policy, router helper, or installer changes.

## Verification

- 26 focused tests passed across editor workflows, enabled-state UCI persistence, and existing firewall/interface tests.
- Cases include create/edit, ranges, invalid inputs, protocol/enable changes, custom zones, router destination, pending-save lock, failed saves, confirmed deletion, and discard confirmation.
- Layout tested in light/dark modes at widths 320, 430, and 1200, with 1.5x text and an open keyboard. A 430px dark preview was rendered with real text/icon fonts and visually inspected.
- Focused Flutter analyzer and `git diff --check` passed.
- No APK built or live-router configuration changed.

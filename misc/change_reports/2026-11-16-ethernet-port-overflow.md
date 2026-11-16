# Ethernet Port Overflow

- The dashboard now shows at most four physical Ethernet-port icons, followed by `+N` for additional ports. Five ports shows `+1`; eight shows `+4`. Four or fewer show no overflow count.
- Icons and count stay together on one line and scale down on narrow layouts. The count has a tooltip identifying the additional Ethernet ports.
- Physical-port discovery, cached inventory, Network/Wi-Fi counts, colors and navigation remain unchanged.
- Scope: network-panel widget, focused widget tests, version and this report. No router helper or ACL update required.
- Version: `1.0.584+486`.
- 14 tests passed, covering 3/4/5/8 physical ports, accurate overflow counts, single-line alignment, unchanged totals, and existing panel layouts/navigation. Static analysis and whitespace checks passed. Real-font narrow-screen screenshot verified. No APK built; user-owned APK/attachment changes were left untouched.

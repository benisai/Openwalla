# HTTP-Only Router Netify History

- Version: 1.0.562+464.
- Added UCI `openwalla.collector.include_protocols`, default `HTTP,HTTP/S`, to the router Netify collector, packaged config, and standalone installer. Existing explicit include-list settings are preserved by installation; missing settings use the new default.
- Only matching protocol names are retained in new detailed-flow rows. Matching is case insensitive and normalized (`HTTPS` equals `HTTP/S`); it is not a prefix or destination-port match. TLS, QUIC, DNS, unknown/missing names, and other protocols are skipped by default.
- Existing exclusions still take precedence. An explicit `include_protocols='*'` restores broad collection subject to those exclusions.
- Existing stored history is not deleted. Five-minute accounting/labels, traffic totals, app display filters, external-server collection, and retention schedules are unchanged.
- Deploy the updated router collector before using the new UCI setting. Apply manually afterward with:

```sh
uci set openwalla.collector.include_protocols='HTTP,HTTP/S'
uci commit openwalla
/etc/init.d/openwalla-netify-collector restart
```

## Verification

- 18 tests passed: protocol allowlist/UCI configuration, column-storage migration/compaction, and traffic accounting.
- Analyzer passed for the added tests; edited shell scripts passed syntax checks; `git diff --check` passed.
- No APK built and no live-router changes made.

# Reboot Without State Sync

- Check whether /usr/bin/openwalla-state-sync exists before app reboot.
  A confirmed missing helper permits normal reboot without installing scripts.
- Display a countdown warning that runtime data is not backed up and temporary
  history may be lost. Do not claim that a skipped backup completed.
- Preserve verified-backup requirements for installed helpers, including older
  or broken installations. Availability-check errors, permission failures and
  malformed responses are not interpreted as proof that the helper is missing.
- Preserve router/session checks before backup and reboot. No router script
  changes or additional helper deployment required for the missing-helper case.
- Version 1.0.559+461. No APK build or physical-router reboot performed.
- Verification: all 20 focused reboot/checkpoint tests pass, including missing
  helper, installed-helper failure, unknown availability and honest error text
  when reboot fails after skipping backup. Targeted analyzer/diff checks clean.

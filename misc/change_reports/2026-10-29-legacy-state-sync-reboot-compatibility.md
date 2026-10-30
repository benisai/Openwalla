# Legacy State Sync Reboot Compatibility

- Regression: app reboot required save-for-reboot even on existing helpers that
  only support save. Their usage response was hidden by a generic failure message.
- Recognize only the known old-helper usage response and exit status, then wait
  for its existing save command before sending reboot. No helper reinstall is
  required for this compatibility path. Surface a legacy-integrity warning.
- Do not downgrade on transport, permission, disk, malformed-response or current
  helper failures. Legacy save must still report exit zero. Preserve the missing
  helper normal reboot and current helper acknowledgement requirements.
- Legacy helpers can internally mask filesystem errors; their old exit-zero
  behavior cannot provide the new helper's integrity guarantee. Update State Sync
  to obtain that guarantee, but it is not mandatory for normal legacy reboot.
- Also fix the updated shell helper's trailing exit zero masking standard save,
  backup and scheduled-save failures. save-for-reboot already failed correctly.
- Show actual helper diagnostics instead of discarding stdout on failure.
- Version 1.0.560+462. No APK build or physical-router reboot performed.
- Verification: 25 focused reboot and shell-checkpoint tests pass. Covers the
  old-helper usage response on stdout/stderr, legacy save failure, current-helper
  failure without downgrade, no-helper reboot, and masked standard-save errors.
  Targeted analyzer, shell syntax and diff checks are clean.

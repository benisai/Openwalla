# Immediate Smart Queue Toggle

- Version: 1.0.566+468.
- Smart Queue's enable/disable switch now runs Save & Apply immediately, including the current form settings. No second tap on Save & Apply is required.
- Controls are locked during the operation to prevent duplicate requests. The switch is refreshed from router settings afterward; toggle errors also trigger a re-read instead of leaving an optimistic state displayed.
- Enabling retains fresh WAN-to-device resolution. Disabling an existing queue can use its stored device even if the WAN is unavailable.
- SQM saves now check UCI write and commit responses. Application uses the ACL-permitted shell execution path, enables the SQM boot service when enabling a queue, restarts SQM, and requires a successful exit plus a confirmation marker. Removed the prior `|| true` that hid restart failures; allowed up to 60 seconds for application.
- Disabling one queue does not disable the entire boot service or overwrite other queues. A failed runtime application may leave committed settings; the error reports that distinction and the UI reloads the router configuration. The marker confirms command completion, not a live bandwidth/shaping measurement.
- Scope: Smart Queue screen, its existing save method, focused tests, and version/report metadata. No helper installer, firewall, reboot, or dashboard changes.

## Verification

- 17 focused tests passed across immediate-toggle UI, save/apply ordering and errors, WAN mapping, and responsive layouts.
- Cases include immediate enable without Save, pending-operation lock, failed enable, disabling an unavailable device, UCI rejection, commit failure, restart failure, and missing confirmation.
- Focused analyzer and `git diff --check` passed.
- No APK built or live-router SQM test performed.

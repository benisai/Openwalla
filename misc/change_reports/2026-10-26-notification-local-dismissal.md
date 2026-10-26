# Notification Local Dismissal

- Keep the existing archive operation behind the notification close button.
  After success, remove only the matching ID from the local list instead of
  reloading the page. Preserve the search, filter and scroll position.
- Disable that card's close button while its archive request is pending.
  Keep the card and show the standard error toast on failure.
- Add stable notification keys. Retain pull-to-refresh and Archive All behavior;
  backend archive/count updates and Network Performance history are unchanged.
- Version 1.0.554+456. No router deployment or APK build.
- Verification: 15 focused widget/model tests pass, including unchanged scroll
  offset, no refetch, disabled pending action, failure retention and empty state.
  Targeted analyzer and diff checks are clean.

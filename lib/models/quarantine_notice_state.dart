class QuarantineNoticeState {
  final _dismissed = <String, Set<String>>{};

  void reconcile(String routerKey, Set<String> active) =>
      _dismissed[routerKey]?.retainAll(active);

  Set<String> unseen(String routerKey, Set<String> active) =>
      active.difference(_dismissed[routerKey] ?? const {});

  void dismiss(String routerKey, Set<String> active) =>
      (_dismissed[routerKey] ??= {}).addAll(active);

  void clear() => _dismissed.clear();
}

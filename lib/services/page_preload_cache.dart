/// Short-lived, in-memory results shared by post-login warmup and page entry.
class PagePreloadCache<T> {
  PagePreloadCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, _Entry<T>> _entries = {};
  static const freshness = Duration(seconds: 15);

  T? peek(String key) => _entries[key]?.data;

  Future<T> load(String key, Future<T> Function() fetch, {bool force = false}) {
    final entry = _entries.putIfAbsent(key, () => _Entry<T>());
    if (entry.pending != null) return entry.pending!;
    if (!force &&
        entry.savedAt != null &&
        _now().difference(entry.savedAt!) < freshness) {
      return Future.value(entry.data as T);
    }
    final pending = Future<T>.sync(fetch)
        .then((data) {
          if (identical(_entries[key], entry)) {
            entry.data = data;
            entry.savedAt = _now();
          }
          return data;
        })
        .whenComplete(() => entry.pending = null);
    entry.pending = pending;
    return pending;
  }

  void clear() => _entries.clear();
}

class _Entry<T> {
  T? data;
  DateTime? savedAt;
  Future<T>? pending;
}

import 'dart:async';

import 'repeater_reconnect_service.dart';

/// Mirrors LuCI wireless Remove, followed by Save & Apply.
class RepeaterRemovalService {
  final Future<dynamic> Function(
    String object,
    String method,
    Map<String, dynamic> params,
  )
  call;
  final Duration timeout;
  final Duration pollInterval;

  RepeaterRemovalService({
    required this.call,
    this.timeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(seconds: 2),
  });

  Map _data(dynamic result) {
    if (result is! List || result.isEmpty || result.first != 0) {
      throw StateError('The router rejected the repeater removal request.');
    }
    return result.length > 1 && result[1] is Map ? result[1] as Map : {};
  }

  Future<void> remove(String section) async {
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(section)) {
      throw ArgumentError('Invalid repeater section.');
    }
    final config = _data(await call('uci', 'get', {'config': 'wireless'}));
    final values = config['values'];
    final entry = values is Map ? values[section] : null;
    if (entry is! Map ||
        entry['.type'] != 'wifi-iface' ||
        entry['mode'] != 'sta') {
      throw StateError('Only an existing repeater connection can be removed.');
    }

    _data(
      await call('uci', 'delete', {'config': 'wireless', 'section': section}),
    );
    try {
      _data(await call('uci', 'apply', {'rollback': false}));
    } catch (error) {
      if (!isRepeaterTransportDisconnect(error)) rethrow;
      // Never replay the deletion after an uncertain apply response.
    }

    final watch = Stopwatch()..start();
    while (watch.elapsed < timeout) {
      try {
        Future<dynamic> probe(String method) => call('uci', method, {
          'config': 'wireless',
        }).timeout(timeout - watch.elapsed);
        final changes = _data(await probe('changes'))['changes'];
        final pending = changes is Map ? changes['wireless'] : null;
        final current = _data(await probe('get'))['values'];
        if (changes is Map &&
            (pending == null || (pending is List && pending.isEmpty)) &&
            current is Map &&
            !current.containsKey(section)) {
          return;
        }
      } catch (error) {
        if (!isRepeaterTransportDisconnect(error)) rethrow;
      }
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        pollInterval < remaining ? pollInterval : remaining,
      );
    }
    throw StateError(
      'Repeater removal could not be confirmed. Reconnect to the router and '
      'refresh before trying again.',
    );
  }
}

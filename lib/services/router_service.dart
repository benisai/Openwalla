import 'dart:convert';

import 'package:openwalla/models/router.dart' as model;
import 'package:openwalla/services/secure_storage_service.dart';

class RouterService {
  final SecureStorageService _secureStorageService = SecureStorageService();

  List<model.Router> _routers = [];
  model.Router? _selectedRouter;

  List<model.Router> get routers => _routers;
  model.Router? get selectedRouter => _selectedRouter;

  Future<void> loadRouters() async {
    _routers = await _secureStorageService.getRouters();

    // Try to restore the previously selected router
    final selectedId = await _secureStorageService.getSelectedRouterId();
    if (selectedId != null && _routers.isNotEmpty) {
      // Try to find the router with the saved ID
      try {
        _selectedRouter = _routers.firstWhere((r) => r.id == selectedId);
      } catch (e) {
        // If not found, fall back to first router
        _selectedRouter = _routers.first;
      }
    } else if (_routers.isNotEmpty && _selectedRouter == null) {
      _selectedRouter = _routers.first;
    }

    // Save the selected router ID if we have one
    if (_selectedRouter != null) {
      await _secureStorageService.saveSelectedRouterId(_selectedRouter!.id);
    }
  }

  Future<void> addRouter(model.Router router) async {
    _routers.add(router);
    await _secureStorageService.saveRouters(_routers);
    if (_selectedRouter == null) {
      await setSelectedRouter(router.id);
    }
  }

  Future<model.Router?> setSelectedRouter(String id) async {
    final found = selectRouter(id);
    if (found != null) {
      await _secureStorageService.saveSelectedRouterId(found.id);
    }
    return found;
  }

  Future<bool> removeRouter(String id) async {
    final wasActive = _selectedRouter?.id == id;
    _routers.removeWhere((r) => r.id == id);
    await _secureStorageService.saveRouters(_routers);

    if (wasActive) {
      if (_routers.isNotEmpty) {
        _selectedRouter = _routers.first;
        await _secureStorageService.saveSelectedRouterId(_selectedRouter!.id);
        return true; // Indicates need to switch to new router
      } else {
        _selectedRouter = null;
        await _secureStorageService.saveSelectedRouterId(null);
        return false; // No routers available
      }
    }
    return false; // No router switch needed
  }

  model.Router? selectRouter(String id) {
    if (_routers.isEmpty) return null;

    final found = _routers.firstWhere(
      (r) => r.id == id,
      orElse: () => _routers.first,
    );

    _selectedRouter = found;
    // Save the selected router ID asynchronously
    _secureStorageService.saveSelectedRouterId(found.id);
    return found;
  }

  Future<void> updateRouter(model.Router router) async {
    final idx = _routers.indexWhere((r) => r.id == router.id);
    if (idx != -1) {
      _routers[idx] = router;
      if (_selectedRouter?.id == router.id) {
        _selectedRouter = router;
      }
      await _secureStorageService.saveRouters(_routers);
    }
  }

  Future<void> updateSelectedRouterHostname(String hostname) async {
    if (_selectedRouter != null && hostname.isNotEmpty) {
      final idx = _routers.indexWhere((r) => r.id == _selectedRouter!.id);
      if (idx != -1) {
        _routers[idx] = _routers[idx].copyWith(lastKnownHostname: hostname);
        _selectedRouter = _routers[idx];
        await _secureStorageService.saveRouters(_routers);
      }
    }
  }

  model.Router createRouter(
    String ip,
    String user,
    String pass,
    bool useHttps,
  ) {
    final id = '$ip-$user';
    return model.Router(
      id: id,
      ipAddress: ip,
      username: user,
      password: pass,
      useHttps: useHttps,
    );
  }

  String exportRoutersAsJson() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'app': 'Openwalla',
    'profiles': _routers.map((router) => router.toJson()).toList(),
  });

  Future<RouterImportResult> importRoutersFromJson(String content) async {
    final source = content.trim().replaceFirst('\uFEFF', '');
    if (source.isEmpty) {
      return const RouterImportResult.error('The selected file is empty.');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      return RouterImportResult.error('Invalid JSON: ${error.message}');
    }
    final List<dynamic> entries;
    if (decoded is Map && decoded['profiles'] is List) {
      entries = decoded['profiles'] as List;
    } else if (decoded is List) {
      entries = decoded;
    } else if (decoded is Map && decoded.containsKey('ipAddress')) {
      entries = [decoded];
    } else {
      return const RouterImportResult.error(
        'Expected an Openwalla profile backup or profile array.',
      );
    }

    var imported = 0;
    var updated = 0;
    final warnings = <String>[];
    for (var index = 0; index < entries.length; index++) {
      final raw = entries[index];
      if (raw is! Map) {
        warnings.add('Profile ${index + 1} is not an object.');
        continue;
      }
      final values = Map<String, dynamic>.from(raw);
      final address = values['ipAddress']?.toString().trim() ?? '';
      final username = values['username']?.toString().trim() ?? '';
      if (address.isEmpty || username.isEmpty) {
        warnings.add('Profile ${index + 1} is missing an address or username.');
        continue;
      }
      final useHttps =
          values['useHttps'] == true || values['useHttps'] == 'true';
      final id = values['id']?.toString().trim().isNotEmpty == true
          ? values['id'].toString().trim()
          : '$address-$username';
      final router = model.Router(
        id: id,
        ipAddress: address,
        username: username,
        password: values['password']?.toString() ?? '',
        useHttps: useHttps,
        lastKnownHostname:
            values['lastKnownHostname']?.toString().trim().isNotEmpty == true
            ? values['lastKnownHostname'].toString().trim()
            : null,
      );
      final existingIndex = _routers.indexWhere((item) => item.id == router.id);
      if (existingIndex >= 0) {
        _routers[existingIndex] = router;
        if (_selectedRouter?.id == router.id) _selectedRouter = router;
        updated++;
      } else {
        _routers.add(router);
        imported++;
      }
    }
    if (imported == 0 && updated == 0) {
      return RouterImportResult.error(
        warnings.isEmpty
            ? 'No router profiles were found.'
            : warnings.join(' '),
      );
    }
    await _secureStorageService.saveRouters(_routers);
    if (_selectedRouter == null && _routers.isNotEmpty) {
      await setSelectedRouter(_routers.first.id);
    }
    return RouterImportResult(
      success: true,
      importedCount: imported,
      updatedCount: updated,
      warnings: warnings,
    );
  }
}

class RouterImportResult {
  const RouterImportResult({
    required this.success,
    this.importedCount = 0,
    this.updatedCount = 0,
    this.errorMessage,
    this.warnings = const [],
  });

  const RouterImportResult.error(String message)
    : success = false,
      importedCount = 0,
      updatedCount = 0,
      errorMessage = message,
      warnings = const [];

  final bool success;
  final int importedCount;
  final int updatedCount;
  final String? errorMessage;
  final List<String> warnings;
}

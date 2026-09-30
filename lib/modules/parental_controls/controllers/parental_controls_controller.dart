// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/utils/self_device_guard.dart';
import '../models/parental_profile.dart';
import '../models/parental_controls_store.dart';

enum ParentalFailureType {
  none,
  firewallDenied,
  routerUnreachable,
  selfGuardBlocked,
  partialSuccess,
  storageError,
}

class ParentalActionResult {
  final bool success;
  final ParentalFailureType failureType;
  final List<String> failedMacs;
  final String message;

  const ParentalActionResult({
    required this.success,
    this.failureType = ParentalFailureType.none,
    this.failedMacs = const [],
    required this.message,
  });

  static const ParentalActionResult ok = ParentalActionResult(
    success: true,
    message: 'Operation completed successfully.',
  );
}

/// Central coordinator for parental control business logic, storage sync,
/// timer-based schedule/pause enforcement, and backend router synchronization.
class ParentalControlsController {
  static ParentalControlsController? _instance;
  static ParentalControlsController get instance =>
      _instance ??= ParentalControlsController._();
  ParentalControlsController._();

  final ParentalControlsStore _store = ParentalControlsStore.instance;
  bool _isInitializing = false;

  ParentalControlsStore get store => _store;

  // ── Storage Persistence ──────────────────────────────────────────────────

  /// Reset in-memory store so another router's profiles don't linger.
  void reset() {
    _store.loadFromString(null);
  }

  /// Deterministically load store state from secure storage and sync with backend if available.
  Future<ParentalActionResult> loadStore(AppState appState) async {
    if (_isInitializing) return ParentalActionResult.ok;
    _isInitializing = true;

    try {
      final routerProfiles = await appState.fetchParentalProfiles();
      if (routerProfiles != null) {
        if (routerProfiles.isEmpty) {
          final routerId = appState.selectedRouter?.id;
          final key = routerId == null
              ? 'parental_controls_store_v1'
              : 'parental_controls_store_v1:$routerId';
          final legacy = await appState.secureRead(key);
          _store.loadFromString(legacy);
          for (final profile in _store.profiles) {
            await appState.saveParentalProfile(profile: profile);
          }
        } else {
          _store.setProfiles(routerProfiles);
        }
        final activity = await appState.fetchParentalActivity();
        if (activity != null) _store.setActivityLog(activity);
      } else {
        _store.loadFromString(null);
      }
      return const ParentalActionResult(
        success: true,
        message: 'Parental store loaded successfully.',
      );
    } catch (e) {
      debugPrint('ParentalControlsController: load error — $e');
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.storageError,
        message: 'Failed to load parental controls store: $e',
      );
    } finally {
      _isInitializing = false;
    }
  }

  /// Single write path to persist store to secure storage.
  Future<ParentalActionResult> persistStore(AppState appState) async {
    if (!_store.isLoaded) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.storageError,
        message: 'Cannot persist store before initial load completes.',
      );
    }
    try {
      return ParentalActionResult.ok;
    } catch (e) {
      debugPrint('ParentalControlsController: persist error — $e');
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.storageError,
        message: 'Failed to persist parental controls store: $e',
      );
    }
  }

  Future<ParentalActionResult> clearActivityLog(AppState appState) async {
    final cleared = await appState.clearParentalActivity();
    if (cleared) {
      _store.clearActivityLog();
      return const ParentalActionResult(
        success: true,
        message: 'Activity log cleared.',
      );
    }
    return const ParentalActionResult(
      success: false,
      failureType: ParentalFailureType.routerUnreachable,
      message: 'Unable to clear the router activity log.',
    );
  }

  // ── Timer & Lifecycle Orchestration ──────────────────────────────────────

  void startExpiryTimer(AppState appState) {
    // Router cron owns schedule, pause-expiry, and daily-limit enforcement.
  }

  void stopExpiryTimer() {}

  void handleLifecycleState(AppLifecycleState state, AppState appState) {
    if (state == AppLifecycleState.resumed) {
      loadStore(appState);
    }
  }

  /// Auto-resume expired manual pauses and sync active scheduled time blocks.
  Future<void> checkPausesAndSchedules(AppState appState) async {
    await loadStore(appState);
  }

  // ── Profile Actions & Router Sync ─────────────────────────────────────────

  Future<ParentalActionResult> pauseProfile(
    ParentalProfile profile,
    PauseDuration duration,
    AppState appState, {
    BuildContext? context,
  }) async {
    // Run self-device guard against ALL MAC addresses assigned to profile
    if (context != null) {
      for (final mac in profile.macAddresses) {
        final safe = await SelfDeviceGuard.checkSelfActionGuardrail(
          context,
          actionName: 'Pause Internet for ${profile.name}',
          targetMac: mac,
        );
        if (!safe) {
          return ParentalActionResult(
            success: false,
            failureType: ParentalFailureType.selfGuardBlocked,
            message: 'Action cancelled to protect self device.',
          );
        }
      }
    }

    DateTime? expiresAt;
    if (duration == PauseDuration.untilTomorrow) {
      final now = DateTime.now().toLocal();
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 7, 0);
      expiresAt = tomorrow.toUtc();
    } else if (duration.duration != null) {
      expiresAt = DateTime.now().toUtc().add(duration.duration!);
    }

    final paused = await appState.setParentalProfilePause(
      profile.id,
      paused: true,
      expiresAt: expiresAt,
    );
    if (paused) {
      _store.markProfilePaused(profile.id, expiresAt: expiresAt);
      final msg = expiresAt != null
          ? 'Internet paused for ${profile.name} (${duration.label}).'
          : 'Internet paused for ${profile.name}.';
      return ParentalActionResult(success: true, message: msg);
    } else {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        message: 'Failed to pause internet. Check router connection.',
      );
    }
  }

  Future<ParentalActionResult> resumeProfile(
    ParentalProfile profile, {
    required AppState appState,
    bool auto = false,
  }) async {
    final resumed = await appState.setParentalProfilePause(
      profile.id,
      paused: false,
    );
    if (resumed) {
      _store.markProfileResumed(profile.id);
      return ParentalActionResult(
        success: true,
        message: 'Internet resumed for ${profile.name}.',
      );
    } else {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.routerUnreachable,
        message: 'Failed to resume internet for devices.',
      );
    }
  }

  Future<ParentalActionResult> addProfile(
    ParentalProfile profile,
    AppState appState,
  ) async {
    _store.addProfile(profile);
    final profileSaved = await appState.saveParentalProfile(profile: profile);

    var dnsApplied = true;
    if (profile.hasContentFilter) {
      dnsApplied = await appState.applyParentalProfileDns(
        profileId: profile.id,
        macAddresses: profile.macAddresses,
        dnsServers: profile.contentFilter == ContentFilterDns.custom
            ? profile.customDnsServers
            : profile.contentFilter.primaryServers,
        context: null,
      );
    }
    await persistStore(appState);
    if (!profileSaved || !dnsApplied) {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.partialSuccess,
        message: dnsApplied
            ? 'Profile saved locally, but the router profile could not be saved.'
            : 'Profile saved locally, but its content filter could not be applied.',
      );
    }
    return ParentalActionResult(
      success: true,
      message: 'Profile "${profile.name}" created.',
    );
  }

  Future<ParentalActionResult> updateProfile(
    ParentalProfile updated,
    ParentalProfile oldProfile,
    AppState appState,
  ) async {
    _store.updateProfile(updated);

    final profileSaved = await appState.saveParentalProfile(profile: updated);

    // Apply DNS changes after the router-side profile is updated.
    final dnsApplied = await appState.applyParentalProfileDns(
      profileId: updated.id,
      macAddresses: updated.macAddresses,
      dnsServers: updated.contentFilter == ContentFilterDns.custom
          ? updated.customDnsServers
          : updated.contentFilter.primaryServers,
      context: null,
    );

    await persistStore(appState);
    if (!profileSaved || !dnsApplied) {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.partialSuccess,
        message: dnsApplied
            ? 'Profile updated locally, but the router profile could not be saved.'
            : 'Profile updated locally, but its content filter could not be applied.',
      );
    }
    return ParentalActionResult(
      success: true,
      message: 'Profile "${updated.name}" updated.',
    );
  }

  Future<ParentalActionResult> deleteProfile(
    String profileId,
    AppState appState,
  ) async {
    final profile = _store.getProfile(profileId);
    final profileName = profile?.name ?? 'Profile';

    _store.deleteProfile(profileId);
    final profileDeleted = await appState.deleteParentalProfile(
      profileId: profileId,
    );
    final dnsRemoved = await appState.applyParentalProfileDns(
      profileId: profileId,
      macAddresses: [],
      dnsServers: null,
      context: null,
    );

    await persistStore(appState);
    if (!profileDeleted || !dnsRemoved) {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.partialSuccess,
        message: dnsRemoved
            ? 'Profile removed locally, but its router record could not be deleted.'
            : 'Profile removed locally, but its DNS filter could not be removed.',
      );
    }
    return ParentalActionResult(
      success: true,
      message: 'Profile "$profileName" deleted.',
    );
  }

  Future<ParentalActionResult> toggleProfileEnabled(
    String profileId,
    AppState appState,
  ) async {
    _store.toggleProfileEnabled(profileId);
    final updated = _store.getProfile(profileId);
    if (updated == null) {
      return const ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.storageError,
        message: 'Profile not found.',
      );
    }

    final isNowEnabled = updated.isEnabled;
    final profileSaved = await appState.saveParentalProfile(profile: updated);

    final dnsApplied = await appState.applyParentalProfileDns(
      profileId: updated.id,
      macAddresses: isNowEnabled ? updated.macAddresses : [],
      dnsServers: isNowEnabled
          ? (updated.contentFilter == ContentFilterDns.custom
                ? updated.customDnsServers
                : updated.contentFilter.primaryServers)
          : null,
      context: null,
    );

    await persistStore(appState);
    if (!profileSaved || !dnsApplied) {
      return ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.partialSuccess,
        message: dnsApplied
            ? 'Profile state changed locally, but the router record was not updated.'
            : 'Profile state changed locally, but its DNS filter was not updated.',
      );
    }
    final msg = isNowEnabled
        ? 'Rules re-enabled for ${updated.name}'
        : 'Restrictions bypassed for ${updated.name}';
    return ParentalActionResult(success: true, message: msg);
  }
}

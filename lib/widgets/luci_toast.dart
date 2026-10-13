import 'package:flutter/material.dart';
import 'package:openwalla/widgets/openwalla_toast.dart';

extension LuciToastContext on BuildContext {
  void showToastLoading(
    String message, {
    String? subtitle,
    String? actionKey,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    OpenwallaToast.showLoading(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void showToastSuccess(
    String message, {
    String? subtitle,
    String? actionKey,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    OpenwallaToast.showSuccess(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  void showToastError(
    String message, {
    String? subtitle,
    String? actionKey,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 6),
  }) {
    OpenwallaToast.showError(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  void showToastWarning(
    String message, {
    String? subtitle,
    String? actionKey,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 5),
  }) {
    OpenwallaToast.showWarning(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  void showToastInfo(
    String message, {
    String? subtitle,
    String? actionKey,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    OpenwallaToast.showInfo(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }
}

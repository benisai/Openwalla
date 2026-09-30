import 'package:flutter/material.dart';
import 'package:openwalla/widgets/openwalla_toast.dart';

extension LuciToastContext on BuildContext {
  void showToastLoading(String message, {String? subtitle, String? actionKey}) {
    OpenwallaToast.showLoading(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
    );
  }

  void showToastSuccess(String message, {String? subtitle, String? actionKey}) {
    OpenwallaToast.showSuccess(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
    );
  }

  void showToastError(String message, {String? subtitle, String? actionKey}) {
    OpenwallaToast.showError(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
    );
  }

  void showToastWarning(String message, {String? subtitle, String? actionKey}) {
    OpenwallaToast.showWarning(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
    );
  }

  void showToastInfo(String message, {String? subtitle, String? actionKey}) {
    OpenwallaToast.showInfo(
      this,
      key: actionKey ?? message,
      message: message,
      subtitle: subtitle,
    );
  }
}

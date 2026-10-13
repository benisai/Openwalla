import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_toast.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

class RouterAclPromptHost extends StatefulWidget {
  const RouterAclPromptHost({
    super.key,
    required this.appState,
    required this.navigatorKey,
    required this.child,
  });

  final AppState appState;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<RouterAclPromptHost> createState() => _RouterAclPromptHostState();
}

class _RouterAclPromptHostState extends State<RouterAclPromptHost> {
  bool _dialogOpen = false;
  bool _promptScheduled = false;

  @override
  void initState() {
    super.initState();
    _schedulePromptIfNeeded();
  }

  @override
  void didUpdateWidget(covariant RouterAclPromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePromptIfNeeded();
  }

  void _schedulePromptIfNeeded() {
    if (_dialogOpen ||
        _promptScheduled ||
        !widget.appState.routerAclInstallPromptPending) {
      return;
    }
    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _promptScheduled = false;
      if (!mounted || _dialogOpen) return;
      if (!widget.appState.consumeRouterAclInstallPrompt()) return;
      await _showInstallPrompt();
    });
  }

  Future<void> _showInstallPrompt() async {
    final navigatorContext = widget.navigatorKey.currentContext;
    if (navigatorContext == null) return;
    _dialogOpen = true;
    final install = await showDialog<bool>(
      context: navigatorContext,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.policy_outlined),
        title: const Text('Install Openwalla permissions?'),
        content: const Text(
          'The Openwalla RPC ACL is not installed on this router. Stock LuCI '
          'will still work, but some Openwalla controls may be unavailable.\n\n'
          'Install the bundled permissions over SSH now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.download_done_rounded),
            label: const Text('Install'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (install == true && mounted) {
      await _installAcl();
    }
  }

  Future<void> _installAcl() async {
    final navigatorContext = widget.navigatorKey.currentContext;
    if (navigatorContext == null) return;
    final console = SshConsoleController(
      initialOutput:
          'Connecting to the router over SSH...\n'
          'Installing the bundled Openwalla RPC ACL...\n\n',
      running: true,
    );
    unawaited(
      showSshConsoleSheet(
        context: navigatorContext,
        controller: console,
        title: 'Openwalla ACL Installer',
      ).whenComplete(console.dispose),
    );

    final output = StringBuffer();
    try {
      final result = await widget.appState.installBundledRouterAcl(
        onOutput: (chunk) {
          output.write(chunk);
          console.setOutput(output.toString());
        },
      );
      console.setOutput(result.trimRight());
      final toastContext = widget.navigatorKey.currentContext;
      if (mounted && toastContext?.mounted == true) {
        toastContext!.showToastSuccess(
          'Openwalla permissions installed',
          subtitle: 'Openwalla controls are ready.',
          actionKey: 'router-acl-install',
        );
      }
    } catch (error) {
      console.setOutput(
        '${output.toString().trimRight()}\n\nInstallation failed.\n\n$error',
      );
      final toastContext = widget.navigatorKey.currentContext;
      if (mounted && toastContext?.mounted == true) {
        toastContext!.showToastError(
          'Could not install Openwalla permissions',
          subtitle: error.toString(),
          actionKey: 'router-acl-install',
        );
      }
    } finally {
      console.complete();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

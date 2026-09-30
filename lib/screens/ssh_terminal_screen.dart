import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/services/ssh_service.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class SshTerminalScreen extends ConsumerStatefulWidget {
  const SshTerminalScreen({super.key});

  @override
  ConsumerState<SshTerminalScreen> createState() => _SshTerminalScreenState();
}

class _SshTerminalScreenState extends ConsumerState<SshTerminalScreen> {
  static final _ansiPattern = RegExp(
    r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1B\\))',
  );

  final _keyboardController = TextEditingController();
  final _terminalFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _output = StringBuffer();
  SshShellConnection? _connection;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  bool _connecting = true;
  bool _connected = false;
  bool _keyboardVisible = false;
  bool _ctrlActive = false;
  bool _altActive = false;
  String _keyboardValue = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _keyboardController.dispose();
    _terminalFocusNode.dispose();
    _scrollController.dispose();
    unawaited(_disconnect(updateState: false));
    super.dispose();
  }

  String _sshHost(String address) {
    final value = address.trim();
    if (value.contains('://')) return Uri.parse(value).host;
    final withoutPath = value.split('/').first;
    if (withoutPath.startsWith('[')) {
      final end = withoutPath.indexOf(']');
      return end > 0 ? withoutPath.substring(1, end) : withoutPath;
    }
    if (':'.allMatches(withoutPath).length == 1) {
      return withoutPath.split(':').first;
    }
    return withoutPath;
  }

  Future<void> _connect() async {
    await _disconnect(updateState: false);
    final router = ref.read(appStateProvider).selectedRouter;
    if (router == null) {
      setState(() {
        _connecting = false;
        _error = 'No router is selected.';
      });
      return;
    }
    if (router.username.trim().isEmpty || router.password.isEmpty) {
      setState(() {
        _connecting = false;
        _error = 'Saved router SSH credentials are missing.';
      });
      return;
    }

    setState(() {
      _connecting = true;
      _connected = false;
      _error = null;
      _output.clear();
      _output.writeln(
        'Connecting to ${router.username}@${_sshHost(router.ipAddress)}...',
      );
    });

    try {
      final connection = await SshService().connectShell(
        host: _sshHost(router.ipAddress),
        username: router.username,
        password: router.password,
      );
      if (!mounted) {
        await connection.close();
        return;
      }
      _connection = connection;
      _stdoutSubscription = connection.stdout.listen(_appendOutput);
      _stderrSubscription = connection.stderr.listen(_appendOutput);
      unawaited(
        connection.done.then((_) {
          if (!mounted || _connection != connection) return;
          setState(() {
            _connected = false;
            _connecting = false;
            _keyboardVisible = false;
            _output.writeln('\nConnection closed.');
          });
          _scrollToBottom();
        }),
      );
      setState(() {
        _connecting = false;
        _connected = true;
      });
      _showKeyboard();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connected = false;
        _error = error.toString();
        _output.writeln('\nConnection failed.');
      });
    }
  }

  void _appendOutput(String chunk) {
    if (!mounted) return;
    setState(() => _output.write(chunk.replaceAll(_ansiPattern, '')));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleKeyboardInput(String value) {
    if (!_connected) return;
    final previous = _keyboardValue;
    if (value.length > previous.length && value.startsWith(previous)) {
      _writeText(value.substring(previous.length));
    } else if (value.length < previous.length && previous.startsWith(value)) {
      _connection?.write(
        List.filled(previous.length - value.length, '\x7f').join(),
      );
    } else if (value.isNotEmpty) {
      _writeText(value);
    }
    _keyboardValue = value;
  }

  void _sendEnter() {
    if (!_connected) return;
    _connection?.write('\r');
    _keyboardValue = '';
    _keyboardController.clear();
    _showKeyboard();
  }

  void _writeText(String value) {
    if (!_connected || value.isEmpty) return;
    var output = value;
    if (_ctrlActive) {
      final first = value.codeUnitAt(0);
      if (first >= 64 && first <= 127) {
        output = String.fromCharCode(first & 0x1f) + value.substring(1);
      }
    }
    if (_altActive) output = '\x1b$output';
    _connection?.write(output);
    if (_ctrlActive || _altActive) {
      setState(() {
        _ctrlActive = false;
        _altActive = false;
      });
    }
  }

  void _sendSequence(String sequence) {
    if (!_connected) return;
    _connection?.write(sequence);
  }

  void _showKeyboard() {
    if (!_connected) return;
    _terminalFocusNode.requestFocus();
    setState(() => _keyboardVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_connected) return;
      _terminalFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  void _hideKeyboard() {
    setState(() => _keyboardVisible = false);
    _terminalFocusNode.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _toggleKeyboard() {
    if (_keyboardVisible) {
      _hideKeyboard();
    } else {
      _showKeyboard();
    }
  }

  Future<void> _disconnect({bool updateState = true}) async {
    final connection = _connection;
    _connection = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    await connection?.close();
    if (updateState && mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
        _keyboardVisible = false;
        _ctrlActive = false;
        _altActive = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final router = ref.watch(appStateProvider).selectedRouter;
    return Scaffold(
      appBar: LuciAppBar(
        title: 'SSH Terminal',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Clear terminal',
            onPressed: () => setState(() => _output.clear()),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: _connected ? 'Disconnect' : 'Reconnect',
            onPressed: _connecting
                ? null
                : _connected
                ? _disconnect
                : _connect,
            icon: Icon(
              _connected ? Icons.link_off_rounded : Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _connected
                          ? const Color(0xFF20CF70)
                          : _connecting
                          ? colors.tertiary
                          : colors.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connecting
                          ? 'Connecting'
                          : _connected
                          ? '${router?.username}@${_sshHost(router?.ipAddress ?? '')}'
                          : 'Disconnected',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _connected ? _showKeyboard : null,
                  child: Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _terminalFocusNode,
                        builder: (context, child) => Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF090C12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _terminalFocusNode.hasFocus
                                  ? colors.primary
                                  : colors.outlineVariant,
                            ),
                          ),
                          child: child,
                        ),
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: SelectableText(
                            _output.isEmpty
                                ? 'Waiting for terminal output...'
                                : _output.toString(),
                            style: const TextStyle(
                              color: Color(0xFFE5E7EB),
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        height: 36,
                        child: Opacity(
                          opacity: 0.02,
                          child: TextField(
                            controller: _keyboardController,
                            focusNode: _terminalFocusNode,
                            enabled: _connected,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.send,
                            onChanged: _handleKeyboardInput,
                            onSubmitted: (_) => _sendEnter(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _TerminalShortcutBar(
                enabled: _connected,
                keyboardVisible: _keyboardVisible,
                ctrlActive: _ctrlActive,
                altActive: _altActive,
                onKeyboard: _toggleKeyboard,
                onSequence: _sendSequence,
                onCtrl: () => setState(() => _ctrlActive = !_ctrlActive),
                onAlt: () => setState(() => _altActive = !_altActive),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalShortcutBar extends StatelessWidget {
  final bool enabled;
  final bool keyboardVisible;
  final bool ctrlActive;
  final bool altActive;
  final VoidCallback onKeyboard;
  final ValueChanged<String> onSequence;
  final VoidCallback onCtrl;
  final VoidCallback onAlt;

  const _TerminalShortcutBar({
    required this.enabled,
    required this.keyboardVisible,
    required this.ctrlActive,
    required this.altActive,
    required this.onKeyboard,
    required this.onSequence,
    required this.onCtrl,
    required this.onAlt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                _TerminalKeyButton(
                  label: 'ESC',
                  enabled: enabled,
                  onTap: () => onSequence('\x1b'),
                ),
                _TerminalKeyButton(
                  label: '/',
                  enabled: enabled,
                  onTap: () => onSequence('/'),
                ),
                _TerminalKeyButton(
                  label: '|',
                  enabled: enabled,
                  onTap: () => onSequence('|'),
                ),
                _TerminalKeyButton(
                  label: '-',
                  enabled: enabled,
                  onTap: () => onSequence('-'),
                ),
                _TerminalKeyButton(
                  label: 'HOME',
                  enabled: enabled,
                  onTap: () => onSequence('\x1b[H'),
                ),
                _TerminalKeyButton(
                  icon: Icons.arrow_upward_rounded,
                  tooltip: 'Up',
                  enabled: enabled,
                  onTap: () => onSequence('\x1b[A'),
                ),
                _TerminalKeyButton(
                  label: 'END',
                  enabled: enabled,
                  onTap: () => onSequence('\x1b[F'),
                ),
                _TerminalKeyButton(
                  label: 'PGUP',
                  enabled: enabled,
                  onTap: () => onSequence('\x1b[5~'),
                ),
                _TerminalKeyButton(
                  label: '^C',
                  tooltip: 'Ctrl+C',
                  enabled: enabled,
                  onTap: () => onSequence('\x03'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                _TerminalKeyButton(
                  label: 'TAB',
                  enabled: enabled,
                  onTap: () => onSequence('\t'),
                ),
                _TerminalKeyButton(
                  label: 'CTRL',
                  enabled: enabled,
                  selected: ctrlActive,
                  onTap: onCtrl,
                ),
                _TerminalKeyButton(
                  label: 'ALT',
                  enabled: enabled,
                  selected: altActive,
                  onTap: onAlt,
                ),
                _TerminalKeyButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Left',
                  enabled: enabled,
                  onTap: () => onSequence('\x1b[D'),
                ),
                _TerminalKeyButton(
                  icon: Icons.arrow_downward_rounded,
                  tooltip: 'Down',
                  enabled: enabled,
                  onTap: () => onSequence('\x1b[B'),
                ),
                _TerminalKeyButton(
                  icon: Icons.arrow_forward_rounded,
                  tooltip: 'Right',
                  enabled: enabled,
                  onTap: () => onSequence('\x1b[C'),
                ),
                _TerminalKeyButton(
                  label: 'PGDN',
                  enabled: enabled,
                  onTap: () => onSequence('\x1b[6~'),
                ),
                _TerminalKeyButton(
                  icon: keyboardVisible
                      ? Icons.keyboard_hide_rounded
                      : Icons.keyboard_rounded,
                  tooltip: keyboardVisible ? 'Hide keyboard' : 'Show keyboard',
                  enabled: enabled,
                  selected: keyboardVisible,
                  onTap: onKeyboard,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalKeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  const _TerminalKeyButton({
    this.label,
    this.icon,
    this.tooltip,
    required this.enabled,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final button = SizedBox(
      width: label != null && label!.length > 3 ? 60 : 48,
      height: 38,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: Center(
            child: icon != null
                ? Icon(
                    icon,
                    size: 19,
                    color: enabled
                        ? selected
                              ? colors.primary
                              : colors.onSurface
                        : colors.onSurfaceVariant.withValues(alpha: 0.4),
                  )
                : Text(
                    label!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: enabled
                          ? selected
                                ? colors.primary
                                : colors.onSurface
                          : colors.onSurfaceVariant.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: tooltip == null
          ? button
          : Tooltip(message: tooltip!, child: button),
    );
  }
}

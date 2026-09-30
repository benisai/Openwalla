import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/manage_routers_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:openwalla/config/app_config.dart';
import 'package:openwalla/models/router.dart' as model;
import 'package:openwalla/services/secure_storage_service.dart';
import 'package:openwalla/services/ssh_service.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/utils/gateway_utils.dart';
import 'package:openwalla/utils/url_parser.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _usernameController = TextEditingController(text: 'root');
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isCheckingAutoLogin = true;
  bool _passwordVisible = false;
  bool _advancedLogin = false;
  bool _saveCredentials = true;
  bool _isDetectingRouter = false;
  late AnimationController _logoAnimController;
  late AnimationController _progressAnimController;
  bool _isActivatingReviewerMode = false;

  Future<void> _openAuthenticatedApp(AppState appState) async {
    final showWelcome = await appState.shouldShowWelcomeSetup();
    if (!mounted) return;
    unawaited(
      Navigator.of(
        context,
      ).pushReplacementNamed(showWelcome ? '/welcome-setup' : '/'),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkReviewerModeAndAutoLogin();
    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _progressAnimController = AnimationController(
      vsync: this,
      duration: AppConfig.reviewerModeActivationDuration,
    );
    _logoAnimController.forward();
  }

  Future<void> _checkReviewerModeAndAutoLogin() async {
    // Check if reviewer mode is enabled
    final secureStorage = SecureStorageService();
    final reviewerModeEnabled = await secureStorage.readValue(
      AppConfig.reviewerModeKey,
    );

    if (reviewerModeEnabled == 'true' && mounted) {
      // Navigate directly to main screen in reviewer mode
      unawaited(Navigator.of(context).pushReplacementNamed('/'));
    } else {
      // Try auto login
      unawaited(_tryAutoLogin());
    }
  }

  void _startReviewerModeActivation() {
    setState(() {
      _isActivatingReviewerMode = true;
    });

    // Start progress animation
    _progressAnimController.forward();

    // Start a timer to check if the user has held for 5 seconds
    Future.delayed(AppConfig.reviewerModeActivationDuration, () {
      if (_isActivatingReviewerMode && mounted) {
        _showReviewerModeDialog();
      }
    });
  }

  void _cancelReviewerModeActivation() {
    setState(() {
      _isActivatingReviewerMode = false;
    });
    // Reset progress animation
    _progressAnimController.reset();
  }

  void _showReviewerModeDialog() {
    _confirmationController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Activate Reviewer Mode?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will enable reviewer mode which bypasses authentication '
                'and provides mock data for app demonstration purposes.',
              ),
              const SizedBox(height: 16),
              const Text(
                'To confirm, type "REVIEWER" below:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmationController,
                decoration: const InputDecoration(
                  hintText: 'Type REVIEWER',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _confirmationController.text == 'REVIEWER'
                  ? () {
                      Navigator.of(context).pop();
                      _activateReviewerMode();
                    }
                  : null,
              child: const Text('Activate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activateReviewerMode() async {
    final appState = ref.read(appStateProvider);
    await appState.setReviewerMode(true);

    if (mounted) {
      unawaited(Navigator.of(context).pushReplacementNamed('/'));
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    _logoAnimController.dispose();
    _progressAnimController.dispose();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    final appState = ref.read(appStateProvider);
    await appState.initialized;
    if (!mounted) return;

    if (appState.consumeSkipNextAutoLogin()) {
      final savedRouter =
          appState.selectedRouter ??
          (appState.routers.isNotEmpty ? appState.routers.first : null);
      if (savedRouter != null) _prefillRouter(savedRouter);
      if (mounted) setState(() => _isCheckingAutoLogin = false);
      return;
    }

    final savedRouter =
        appState.selectedRouter ??
        (appState.routers.isNotEmpty ? appState.routers.first : null);

    if (savedRouter != null) {
      _prefillRouter(savedRouter);

      if (savedRouter.password.isNotEmpty) {
        final success = await appState.login(
          savedRouter.ipAddress,
          savedRouter.username.trim().isEmpty ? 'root' : savedRouter.username,
          savedRouter.password,
          savedRouter.useHttps,
          fromRouter: true,
          saveCredentials: true,
          context: context,
        );
        if (success && mounted) {
          await _openAuthenticatedApp(appState);
          return;
        }
      }

      if (mounted) setState(() => _isCheckingAutoLogin = false);
      return;
    }

    final success = await appState.tryAutoLogin(context: context);
    if (success && mounted) {
      await _openAuthenticatedApp(appState);
    } else {
      if (mounted) {
        setState(() {
          _isCheckingAutoLogin = false;
        });
        unawaited(_detectRouterAddress(showResult: false));
      }
    }
  }

  Future<void> _detectRouterAddress({bool showResult = true}) async {
    if (_isDetectingRouter) return;
    if (!showResult && _ipController.text.trim().isNotEmpty) return;
    setState(() => _isDetectingRouter = true);
    final detectedAddress = await GatewayUtils.detectGatewayIp();
    if (!mounted) return;

    setState(() {
      _isDetectingRouter = false;
      if (detectedAddress != null &&
          (showResult || _ipController.text.trim().isEmpty)) {
        _ipController.text = detectedAddress;
      }
    });

    if (!showResult) return;
    final message = detectedAddress == null
        ? 'No router address found. Check your Wi-Fi connection.'
        : 'Router address found: $detectedAddress';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _prefillRouter(model.Router router) {
    _ipController.text = router.useHttps
        ? 'https://${router.ipAddress}'
        : router.ipAddress;
    _usernameController.text = router.username.trim().isEmpty
        ? 'root'
        : router.username;
    _passwordController.text = router.password;
    _saveCredentials = true;
  }

  Future<void> _openRouterManager() async {
    final router = await Navigator.of(context).push<model.Router>(
      MaterialPageRoute(
        builder: (context) => const ManageRoutersScreen(isFromLogin: true),
      ),
    );
    if (router != null && mounted) {
      setState(() => _prefillRouter(router));
    }
  }

  Future<bool> _confirmExit() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            final colors = Theme.of(context).colorScheme;
            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.exit_to_app_rounded,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Exit Openwalla?')),
                ],
              ),
              content: const Text('Are you sure you want to exit the app?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Exit'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Widget _withExitGuard(Widget child) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmExit() && mounted) {
          await SystemNavigator.pop();
        }
      },
      child: child,
    );
  }

  Future<void> _connect() async {
    if (_formKey.currentState!.validate()) {
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));

      final appState = ref.read(appStateProvider);
      final input = _ipController.text.trim();
      final user = _usernameController.text;
      final pass = _passwordController.text;

      // Parse the input to extract host, port, and protocol
      final parsedUrl = UrlParser.parse(input);

      if (!parsedUrl.isValid) {
        // Show error message
        appState.setError(parsedUrl.error ?? 'Invalid address format');
        return;
      }

      // Use the parsed values
      final success = await appState.login(
        parsedUrl.hostWithPort,
        user,
        pass,
        parsedUrl.useHttps,
        fromRouter: false,
        saveCredentials: _saveCredentials,
        context: context,
      );

      if (success && mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
        );
        await _openAuthenticatedApp(appState);
      }
    }
  }

  Future<void> _openGitHubRepository() async {
    final url = AppConfig.githubRepositoryUrl;
    final success = await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open Openwalla on GitHub'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showLoginHelp() async {
    final parsed = UrlParser.parse(_ipController.text.trim());
    final request = await showModalBottomSheet<_LuciSshInstallRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _LoginHelpSheet(
        initialHost: parsed.isValid ? parsed.host : _ipController.text.trim(),
        initialUsername: _usernameController.text.trim().isEmpty
            ? 'root'
            : _usernameController.text.trim(),
        initialPassword: _passwordController.text,
        onOpenGitHub: _openGitHubRepository,
      ),
    );
    if (request == null || !mounted) return;
    await _installLuciViaSsh(request);
  }

  Future<void> _installLuciViaSsh(_LuciSshInstallRequest request) async {
    final console = SshConsoleController(
      initialOutput:
          'Connecting to ${request.username}@${request.host}:${request.port}...\n'
          'Installing LuCI and RPC support...\n\n',
      running: true,
    );
    unawaited(
      showSshConsoleSheet(
        context: context,
        controller: console,
        title: 'LuCI SSH Installer',
      ).whenComplete(console.dispose),
    );

    const command = r'''
set -e
echo "[openwalla-luci] Detecting package manager..."
if command -v apk >/dev/null 2>&1; then
  echo "[openwalla-luci] Updating APK packages..."
  apk update
  apk add luci luci-mod-rpc rpcd-mod-file || apk add luci luci-mod-rpc
elif command -v opkg >/dev/null 2>&1; then
  echo "[openwalla-luci] Updating OPKG packages..."
  opkg update
  opkg install luci luci-mod-rpc rpcd-mod-file || opkg install luci luci-mod-rpc
else
  echo "[openwalla-luci] No supported package manager was found."
  exit 1
fi
for service in rpcd uhttpd; do
  if [ -x "/etc/init.d/$service" ]; then
    "/etc/init.d/$service" enable || true
    "/etc/init.d/$service" restart || true
  fi
done
echo "[openwalla-luci] Install complete. Return to Openwalla and connect again."
''';

    final output = StringBuffer();
    try {
      final result = await SshService().runCommand(
        host: request.host,
        port: request.port,
        username: request.username,
        password: request.password,
        command: command,
        onOutput: (chunk) {
          output.write(chunk);
          console.setOutput(output.toString());
        },
      );
      if (result.exitCode != null && result.exitCode != 0) {
        console.setOutput(
          '${result.output.trimRight()}\n\nInstallation failed with exit code ${result.exitCode}.',
        );
      } else {
        console.setOutput(
          result.output.trim().isEmpty
              ? 'LuCI installation completed. Return to Openwalla and connect again.'
              : result.output.trimRight(),
        );
      }
    } catch (error) {
      console.setOutput(
        '${output.toString().trimRight()}\n\nSSH installation failed. Verify that SSH is enabled and the root credentials are correct.\n\n$error',
      );
    } finally {
      console.complete();
    }
  }

  InputDecoration _loginInputDecoration({
    required BuildContext context,
    required IconData icon,
    String? hintText,
    String? helperText,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      isDense: false,
      hintText: hintText,
      helperText: helperText,
      helperMaxLines: 2,
      helperStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.36),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.36),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.78),
          width: 1.4,
        ),
      ),
    );
  }

  Widget _loginField({
    Key? key,
    required BuildContext context,
    String? label,
    required Widget child,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 22, bottom: 6),
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.86),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAutoLogin) {
      return _withExitGuard(
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return _withExitGuard(
      Scaffold(
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.surfaceContainerLowest,
                    colorScheme.surface,
                    colorScheme.surfaceContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 32),
                          GestureDetector(
                            onLongPress: () {
                              _startReviewerModeActivation();
                            },
                            onLongPressUp: () {
                              _cancelReviewerModeActivation();
                            },
                            child: Column(
                              children: [
                                Column(
                                  children: [
                                    Text(
                                      'Openwalla',
                                      style: textTheme.headlineLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Connect to your OpenWrt router',
                                      style: textTheme.titleMedium?.copyWith(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Fast. Secure. Open source.',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: _isActivatingReviewerMode
                                      ? Padding(
                                          key: const ValueKey('progress'),
                                          padding: const EdgeInsets.only(
                                            top: 24,
                                          ),
                                          child: AnimatedBuilder(
                                            animation: _progressAnimController,
                                            builder: (context, child) {
                                              return Column(
                                                children: [
                                                  Text(
                                                    'Hold to activate reviewer mode...',
                                                    style: textTheme.bodySmall
                                                        ?.copyWith(
                                                          color: colorScheme
                                                              .primary,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 13,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Container(
                                                    width: 280,
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      color: colorScheme
                                                          .surfaceContainerHighest
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      border: Border.all(
                                                        color: colorScheme
                                                            .outline
                                                            .withValues(
                                                              alpha: 0.15,
                                                            ),
                                                        width: 0.5,
                                                      ),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      child: LinearProgressIndicator(
                                                        value:
                                                            _progressAnimController
                                                                .value,
                                                        backgroundColor:
                                                            Colors.transparent,
                                                        valueColor:
                                                            AlwaysStoppedAnimation<
                                                              Color
                                                            >(
                                                              colorScheme
                                                                  .primary
                                                                  .withValues(
                                                                    alpha: 0.9,
                                                                  ),
                                                            ),
                                                        minHeight: 6,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        )
                                      : const SizedBox(
                                          key: ValueKey('empty'),
                                          height: 0,
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Card(
                                elevation: 0,
                                color: colorScheme.surface.withValues(
                                  alpha: 0.94,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  side: BorderSide(
                                    color: colorScheme.outline.withValues(
                                      alpha: 0.14,
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18.0,
                                    vertical: 16.0,
                                  ),
                                  child: Form(
                                    key: _formKey,
                                    child: Builder(
                                      builder: (context) {
                                        final appState = ref.watch(
                                          appStateProvider,
                                        );
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            _loginField(
                                              context: context,
                                              child: Tooltip(
                                                message:
                                                    'Enter the IP address, hostname, or full URL of your router',
                                                child: TextFormField(
                                                  controller: _ipController,
                                                  autofocus: true,
                                                  autofillHints: const [
                                                    AutofillHints.url,
                                                    AutofillHints.username,
                                                  ],
                                                  decoration: _loginInputDecoration(
                                                    context: context,
                                                    icon: Icons.shield_outlined,
                                                    helperText:
                                                        '192.168.1.1, router.local:8080, or https://192.168.1.1',
                                                    suffixIcon: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          tooltip:
                                                              'Locate router',
                                                          onPressed:
                                                              _isDetectingRouter
                                                              ? null
                                                              : () =>
                                                                    _detectRouterAddress(),
                                                          icon:
                                                              _isDetectingRouter
                                                              ? const SizedBox(
                                                                  width: 18,
                                                                  height: 18,
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                )
                                                              : const Icon(
                                                                  Icons
                                                                      .my_location_rounded,
                                                                ),
                                                        ),
                                                        IconButton(
                                                          tooltip:
                                                              'Manage routers',
                                                          onPressed:
                                                              _openRouterManager,
                                                          icon: const Icon(
                                                            Icons
                                                                .arrow_drop_down_rounded,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  textInputAction:
                                                      TextInputAction.next,
                                                  validator: (value) {
                                                    if (value == null ||
                                                        value.isEmpty) {
                                                      return 'Please enter the router address';
                                                    }
                                                    final parsed =
                                                        UrlParser.parse(value);
                                                    if (!parsed.isValid) {
                                                      return parsed.error ??
                                                          'Invalid address format';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 180,
                                              ),
                                              child: _advancedLogin
                                                  ? _loginField(
                                                      key: const ValueKey(
                                                        'username',
                                                      ),
                                                      context: context,
                                                      label: 'Username',
                                                      child: Tooltip(
                                                        message:
                                                            'Enter your router username',
                                                        child: TextFormField(
                                                          controller:
                                                              _usernameController,
                                                          autofillHints: const [
                                                            AutofillHints
                                                                .username,
                                                          ],
                                                          decoration: _loginInputDecoration(
                                                            context: context,
                                                            icon: Icons
                                                                .person_outline,
                                                            helperText:
                                                                'Default is root',
                                                          ),
                                                          textInputAction:
                                                              TextInputAction
                                                                  .next,
                                                          validator: (value) {
                                                            if (value == null ||
                                                                value.isEmpty) {
                                                              return 'Please enter the username';
                                                            }
                                                            return null;
                                                          },
                                                        ),
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(),
                                            ),
                                            if (_advancedLogin)
                                              const SizedBox(height: 14),
                                            _loginField(
                                              context: context,
                                              child: Tooltip(
                                                message:
                                                    'Enter your router password',
                                                child: TextFormField(
                                                  controller:
                                                      _passwordController,
                                                  obscureText:
                                                      !_passwordVisible,
                                                  autofillHints: const [
                                                    AutofillHints.password,
                                                  ],
                                                  decoration: _loginInputDecoration(
                                                    context: context,
                                                    icon: Icons.lock_outline,
                                                    hintText: 'Password',
                                                    suffixIcon: IconButton(
                                                      icon: Icon(
                                                        _passwordVisible
                                                            ? Icons
                                                                  .visibility_outlined
                                                            : Icons
                                                                  .visibility_off_outlined,
                                                      ),
                                                      onPressed: () => setState(
                                                        () => _passwordVisible =
                                                            !_passwordVisible,
                                                      ),
                                                      tooltip: _passwordVisible
                                                          ? 'Hide password'
                                                          : 'Show password',
                                                    ),
                                                  ),
                                                  textInputAction:
                                                      TextInputAction.done,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 18),
                                            Row(
                                              children: [
                                                Checkbox(
                                                  value: _saveCredentials,
                                                  onChanged: appState.isLoading
                                                      ? null
                                                      : (value) => setState(
                                                          () =>
                                                              _saveCredentials =
                                                                  value ?? true,
                                                        ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTap: appState.isLoading
                                                        ? null
                                                        : () => setState(
                                                            () => _saveCredentials =
                                                                !_saveCredentials,
                                                          ),
                                                    child: Text(
                                                      'Save credentials',
                                                      style: textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            color: colorScheme
                                                                .onSurfaceVariant,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  onPressed: () => setState(
                                                    () => _advancedLogin =
                                                        !_advancedLogin,
                                                  ),
                                                  icon: Icon(
                                                    _advancedLogin
                                                        ? Icons.expand_less
                                                        : Icons.tune_rounded,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    _advancedLogin
                                                        ? 'Hide User'
                                                        : 'Show User',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              child:
                                                  appState.errorMessage != null
                                                  ? Padding(
                                                      key: const ValueKey(
                                                        'error',
                                                      ),
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 12.0,
                                                          ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              10,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: colorScheme
                                                              .errorContainer
                                                              .withValues(
                                                                alpha: 1,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .error_outline,
                                                              color: colorScheme
                                                                  .onErrorContainer,
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                appState
                                                                    .errorMessage!,
                                                                style: textTheme
                                                                    .bodyMedium
                                                                    ?.copyWith(
                                                                      color: colorScheme
                                                                          .onErrorContainer,
                                                                    ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(),
                                            ),
                                            const SizedBox(height: 16),
                                            TweenAnimationBuilder<double>(
                                              duration: const Duration(
                                                milliseconds: 100,
                                              ),
                                              tween: Tween<double>(
                                                begin: 1,
                                                end: appState.isLoading
                                                    ? 0.98
                                                    : 1,
                                              ),
                                              builder: (context, scale, child) {
                                                return Transform.scale(
                                                  scale: scale,
                                                  child: child,
                                                );
                                              },
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton(
                                                  onPressed: appState.isLoading
                                                      ? null
                                                      : _connect,
                                                  style: ElevatedButton.styleFrom(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 18,
                                                        ),
                                                    textStyle: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                    ),
                                                    elevation: 4,
                                                    backgroundColor:
                                                        colorScheme.primary,
                                                    foregroundColor:
                                                        colorScheme.onPrimary,
                                                  ),
                                                  child: appState.isLoading
                                                      ? const SizedBox(
                                                          height: 26,
                                                          width: 26,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 3,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        )
                                                      : Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: const [
                                                            Icon(Icons.login),
                                                            SizedBox(width: 12),
                                                            Text('Connect'),
                                                          ],
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Tooltip(
                            message: 'Login and router setup help',
                            child: TextButton(
                              onPressed: _showLoginHelp,
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                              ),
                              child: const Text('Need help?'),
                            ),
                          ),
                          FutureBuilder<PackageInfo>(
                            future: PackageInfo.fromPlatform(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const SizedBox.shrink();
                              }
                              final info = snapshot.data!;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Text(
                                  'Version ${info.version}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LuciSshInstallRequest {
  final String host;
  final int port;
  final String username;
  final String password;

  const _LuciSshInstallRequest({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });
}

class _LoginHelpSheet extends StatefulWidget {
  final String initialHost;
  final String initialUsername;
  final String initialPassword;
  final Future<void> Function() onOpenGitHub;

  const _LoginHelpSheet({
    required this.initialHost,
    required this.initialUsername,
    required this.initialPassword,
    required this.onOpenGitHub,
  });

  @override
  State<_LoginHelpSheet> createState() => _LoginHelpSheetState();
}

class _LoginHelpSheetState extends State<_LoginHelpSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _showInstaller = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.initialHost);
    _portController = TextEditingController(text: '22');
    _usernameController = TextEditingController(text: widget.initialUsername);
    _passwordController = TextEditingController(text: widget.initialPassword);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  String? _validatePort(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    if (port == null || port < 1 || port > 65535) {
      return 'Use a port from 1 to 65535';
    }
    return null;
  }

  void _install() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _LuciSshInstallRequest(
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 10, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.help_outline_rounded,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Connect to Openwalla',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Missing LuCI support?',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Some newer GL.iNet routers do not include LuCI and LuCI RPC support. Openwalla needs these router packages to connect and manage settings.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: widget.onOpenGitHub,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open Openwalla on GitHub'),
                ),
                const SizedBox(height: 18),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _showInstaller = !_showInstaller),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.34,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.terminal_rounded, color: colors.primary),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Install LuCI via SSH',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Use root SSH access to add required packages',
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _showInstaller
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState: _showInstaller
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Form(
                    key: _formKey,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _hostController,
                            decoration: const InputDecoration(
                              labelText: 'Router Address',
                              prefixIcon: Icon(Icons.router_outlined),
                            ),
                            validator: _required,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _usernameController,
                                  decoration: const InputDecoration(
                                    labelText: 'SSH User',
                                    prefixIcon: Icon(
                                      Icons.person_outline_rounded,
                                    ),
                                  ),
                                  validator: _required,
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _portController,
                                  decoration: const InputDecoration(
                                    labelText: 'Port',
                                  ),
                                  validator: _validatePort,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_showPassword,
                            decoration: InputDecoration(
                              labelText: 'SSH Password',
                              prefixIcon: const Icon(Icons.password_rounded),
                              suffixIcon: IconButton(
                                tooltip: _showPassword
                                    ? 'Hide password'
                                    : 'Show password',
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: _required,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _install(),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _install,
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Install Required Packages'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

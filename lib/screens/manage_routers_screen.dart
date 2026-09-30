import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/router.dart' as model;
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/utils/url_parser.dart';

class ManageRoutersScreen extends ConsumerStatefulWidget {
  const ManageRoutersScreen({super.key, this.isFromLogin = false});

  final bool isFromLogin;

  @override
  ConsumerState<ManageRoutersScreen> createState() =>
      _ManageRoutersScreenState();
}

class _ManageRoutersScreenState extends ConsumerState<ManageRoutersScreen> {
  String? _switchingRouterId;
  bool _profileIoBusy = false;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importProfiles() async {
    if (_profileIoBusy) return;
    setState(() => _profileIoBusy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      if (bytes == null) return;
      final result = await ref
          .read(appStateProvider)
          .importRouterProfiles(utf8.decode(bytes, allowMalformed: true));
      if (!mounted) return;
      _message(
        result.success
            ? 'Imported ${result.importedCount} and updated ${result.updatedCount} router profiles.'
            : result.errorMessage ?? 'Unable to import router profiles.',
      );
    } catch (error) {
      _message('Unable to import profiles: $error');
    } finally {
      if (mounted) setState(() => _profileIoBusy = false);
    }
  }

  Future<void> _exportProfiles() async {
    if (_profileIoBusy) return;
    final appState = ref.read(appStateProvider);
    if (appState.routers.isEmpty) {
      _message('There are no saved routers to export.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export router profiles?'),
        content: const Text(
          'The JSON backup includes router addresses, usernames, and passwords. Store it securely.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Export'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _profileIoBusy = true);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Openwalla Router Profiles',
        fileName: 'openwalla-router-profiles.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: utf8.encode(appState.exportRouterProfiles()),
      );
      if (path != null) _message('Router profiles exported.');
    } catch (error) {
      _message('Unable to export profiles: $error');
    } finally {
      if (mounted) setState(() => _profileIoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final List<model.Router> routers = appState.routers;
    final String? selectedId = appState.selectedRouter?.id;
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Routers',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Import JSON',
            onPressed: _profileIoBusy ? null : _importProfiles,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Export JSON',
            onPressed: _profileIoBusy || routers.isEmpty
                ? null
                : _exportProfiles,
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => appState.loadRouters(),
              child: routers.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.2,
                        ),
                        Center(
                          child: Text(
                            'No routers added yet.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      children: [
                        ...List.generate(routers.length, (index) {
                          final model.Router router = routers[index];
                          final bool isSelected = router.id == selectedId;
                          final bool isSwitching =
                              router.id == _switchingRouterId;
                          String routerTitle;
                          if (isSelected && appState.dashboardData != null) {
                            final boardInfo =
                                appState.dashboardData?['boardInfo']
                                    as Map<String, dynamic>?;
                            final hostname = boardInfo?['hostname']?.toString();
                            routerTitle =
                                (hostname != null && hostname.isNotEmpty)
                                ? hostname
                                : (router.lastKnownHostname ??
                                      router.ipAddress);
                          } else if (router.lastKnownHostname != null &&
                              router.lastKnownHostname!.isNotEmpty) {
                            routerTitle = router.lastKnownHostname!;
                          } else {
                            routerTitle = router.ipAddress;
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: _UnifiedRouterCard(
                              routerTitle: routerTitle,
                              subtitle:
                                  '${router.ipAddress} (${router.username})',
                              isSelected: isSelected,
                              isSwitching: isSwitching,
                              onTap: () async {
                                if (widget.isFromLogin) {
                                  Navigator.of(context).pop(router);
                                  return;
                                }
                                if (!isSelected && !isSwitching) {
                                  setState(() {
                                    _switchingRouterId = router.id;
                                  });

                                  try {
                                    await appState.selectRouter(
                                      router.id,
                                      context: context,
                                    );
                                    // Fetch dashboard data before navigating
                                    await appState.fetchDashboardData();
                                    if (!context.mounted) return;
                                    // Pop all the way back to MainScreen
                                    Navigator.of(
                                      context,
                                    ).popUntil((route) => route.isFirst);
                                    // Set Dashboard tab as active
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          ref
                                              .read(appStateProvider)
                                              .requestTab(0);
                                        });
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _switchingRouterId = null;
                                      });
                                    }
                                  }
                                }
                              },
                              onDelete: () async {
                                String routerLabel;
                                if (isSelected &&
                                    appState.dashboardData != null) {
                                  final boardInfo =
                                      appState.dashboardData?['boardInfo']
                                          as Map<String, dynamic>?;
                                  final hostname = boardInfo?['hostname']
                                      ?.toString();
                                  routerLabel =
                                      (hostname != null && hostname.isNotEmpty)
                                      ? hostname
                                      : router.ipAddress;
                                } else {
                                  routerLabel = router.ipAddress;
                                }
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Remove Router'),
                                    content: Text(
                                      'Are you sure you want to remove $routerLabel?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (!context.mounted) return;
                                if (confirm == true) {
                                  if (widget.isFromLogin) {
                                    await appState.removeSavedRouterProfile(
                                      router.id,
                                    );
                                  } else {
                                    await appState.removeRouter(router.id);
                                  }
                                  if (!context.mounted) return;
                                  if (appState.routers.isEmpty) {
                                    if (widget.isFromLogin) {
                                      Navigator.of(context).pop();
                                    } else {
                                      unawaited(
                                        Navigator.of(
                                          context,
                                        ).pushNamedAndRemoveUntil(
                                          '/login',
                                          (route) => false,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add, size: 20),
                              label: const Text('Add Router'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 24,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimary,
                                elevation: 2,
                              ),
                              onPressed: () async {
                                final ipController = TextEditingController();
                                final userController = TextEditingController(
                                  text: 'root',
                                );
                                final passController = TextEditingController();
                                final formKey = GlobalKey<FormState>();
                                bool obscureText = true;
                                bool isConnecting = false;
                                String? errorMessage;
                                await showDialog<Map<String, dynamic>>(
                                  context: context,
                                  builder: (context) {
                                    return StatefulBuilder(
                                      builder: (context, setState) {
                                        return AlertDialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surface
                                              .withValues(alpha: 0.95),
                                          shadowColor: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.10),
                                          insetPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 60,
                                              ), // Make dialog larger
                                          content: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 400,
                                              minWidth: 320,
                                              minHeight: 380,
                                            ),
                                            child: Form(
                                              key: formKey,
                                              child: SingleChildScrollView(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 32,
                                                      ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      TextFormField(
                                                        controller:
                                                            ipController,
                                                        decoration: const InputDecoration(
                                                          labelText:
                                                              'Router Address',
                                                          border:
                                                              OutlineInputBorder(),
                                                          prefixIcon: Icon(
                                                            Icons
                                                                .router_outlined,
                                                          ),
                                                          helperText:
                                                              'e.g. 192.168.1.1, router.local:8080, https://192.168.1.1',
                                                        ),
                                                        validator: (value) {
                                                          if (value == null ||
                                                              value.isEmpty) {
                                                            return 'Please enter the router address';
                                                          }
                                                          final parsed =
                                                              UrlParser.parse(
                                                                value,
                                                              );
                                                          if (!parsed.isValid) {
                                                            return parsed
                                                                    .error ??
                                                                'Invalid address format';
                                                          }
                                                          return null;
                                                        },
                                                        autofillHints: const [
                                                          AutofillHints.url,
                                                          AutofillHints
                                                              .username,
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      TextFormField(
                                                        controller:
                                                            userController,
                                                        decoration: const InputDecoration(
                                                          labelText: 'Username',
                                                          border:
                                                              OutlineInputBorder(),
                                                          prefixIcon: Icon(
                                                            Icons
                                                                .person_outline,
                                                          ),
                                                          helperText:
                                                              'Default is usually root',
                                                        ),
                                                        validator: (v) =>
                                                            v == null ||
                                                                v.isEmpty
                                                            ? 'Required'
                                                            : null,
                                                        autofillHints: const [
                                                          AutofillHints
                                                              .username,
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      TextFormField(
                                                        controller:
                                                            passController,
                                                        decoration: InputDecoration(
                                                          labelText: 'Password',
                                                          border:
                                                              const OutlineInputBorder(),
                                                          prefixIcon: const Icon(
                                                            Icons.lock_outline,
                                                          ),
                                                          helperText:
                                                              'Your router password',
                                                          suffixIcon: IconButton(
                                                            icon: Icon(
                                                              obscureText
                                                                  ? Icons
                                                                        .visibility_outlined
                                                                  : Icons
                                                                        .visibility_off_outlined,
                                                            ),
                                                            onPressed: () => setState(
                                                              () => obscureText =
                                                                  !obscureText,
                                                            ),
                                                            tooltip: obscureText
                                                                ? 'Hide password'
                                                                : 'Show password',
                                                          ),
                                                        ),
                                                        obscureText:
                                                            obscureText,
                                                        autofillHints: const [
                                                          AutofillHints
                                                              .password,
                                                        ],
                                                      ),
                                                      if (errorMessage !=
                                                          null) ...[
                                                        const SizedBox(
                                                          height: 16,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                10,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
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
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .onErrorContainer,
                                                              ),
                                                              const SizedBox(
                                                                width: 12,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  errorMessage!,
                                                                  style: Theme.of(context)
                                                                      .textTheme
                                                                      .bodyMedium
                                                                      ?.copyWith(
                                                                        color: Theme.of(
                                                                          context,
                                                                        ).colorScheme.onErrorContainer,
                                                                      ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                      const SizedBox(
                                                        height: 28,
                                                      ),
                                                      SizedBox(
                                                        width: double.infinity,
                                                        child: ElevatedButton(
                                                          onPressed:
                                                              isConnecting
                                                              ? null
                                                              : () async {
                                                                  if (formKey
                                                                      .currentState!
                                                                      .validate()) {
                                                                    final input =
                                                                        ipController
                                                                            .text
                                                                            .trim();
                                                                    final user =
                                                                        userController
                                                                            .text
                                                                            .trim();
                                                                    final pass =
                                                                        passController
                                                                            .text;

                                                                    // Parse the input to extract host, port, and protocol
                                                                    final parsedUrl =
                                                                        UrlParser.parse(
                                                                          input,
                                                                        );

                                                                    if (!parsedUrl
                                                                        .isValid) {
                                                                      setState(() {
                                                                        errorMessage =
                                                                            parsedUrl.error ??
                                                                            'Invalid address format';
                                                                      });
                                                                      return;
                                                                    }

                                                                    final hostWithPort =
                                                                        parsedUrl
                                                                            .hostWithPort;
                                                                    final useHttps =
                                                                        parsedUrl
                                                                            .useHttps;
                                                                    final id =
                                                                        '$hostWithPort-$user';

                                                                    if (routers.any(
                                                                      (r) =>
                                                                          r.id ==
                                                                          id,
                                                                    )) {
                                                                      setState(() {
                                                                        errorMessage =
                                                                            'Router already exists.';
                                                                      });
                                                                      return;
                                                                    }

                                                                    // Show connecting state
                                                                    setState(() {
                                                                      errorMessage =
                                                                          null;
                                                                      isConnecting =
                                                                          true;
                                                                    });

                                                                    // Always fetch hostname from router after login
                                                                    try {
                                                                      // Attempt login with the new router's credentials
                                                                      final loginSuccess = await appState.login(
                                                                        hostWithPort,
                                                                        user,
                                                                        pass,
                                                                        useHttps,
                                                                        fromRouter:
                                                                            false,
                                                                        context:
                                                                            context,
                                                                      );
                                                                      if (!loginSuccess) {
                                                                        setState(() {
                                                                          errorMessage =
                                                                              appState.errorMessage ??
                                                                              'Failed to connect: Invalid credentials or host unreachable.';
                                                                          isConnecting =
                                                                              false;
                                                                        });
                                                                        return;
                                                                      }
                                                                      // Do NOT addRouter here; login already adds it if needed
                                                                      if (!context
                                                                          .mounted) {
                                                                        return;
                                                                      }
                                                                      Navigator.pop(
                                                                        context,
                                                                      );
                                                                    } catch (
                                                                      e
                                                                    ) {
                                                                      setState(() {
                                                                        errorMessage =
                                                                            'Failed to connect: ${e.toString()}';
                                                                        isConnecting =
                                                                            false;
                                                                      });
                                                                    } finally {
                                                                      if (mounted) {
                                                                        setState(() {
                                                                          _switchingRouterId =
                                                                              null;
                                                                        });
                                                                      }
                                                                    }
                                                                  }
                                                                },
                                                          style: ElevatedButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 18,
                                                                ),
                                                            textStyle:
                                                                const TextStyle(
                                                                  fontSize: 18,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    14,
                                                                  ),
                                                            ),
                                                            elevation: 4,
                                                            backgroundColor:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                            foregroundColor:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onPrimary,
                                                          ),
                                                          child: isConnecting
                                                              ? Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    SizedBox(
                                                                      width: 22,
                                                                      height:
                                                                          22,
                                                                      child: CircularProgressIndicator(
                                                                        strokeWidth:
                                                                            3,
                                                                        valueColor: AlwaysStoppedAnimation<Color>(
                                                                          Theme.of(
                                                                            context,
                                                                          ).colorScheme.onPrimary,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 12,
                                                                    ),
                                                                    const Text(
                                                                      'Connecting...',
                                                                    ),
                                                                  ],
                                                                )
                                                              : Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: const [
                                                                    Icon(
                                                                      Icons.add,
                                                                    ),
                                                                    SizedBox(
                                                                      width: 12,
                                                                    ),
                                                                    Text('Add'),
                                                                  ],
                                                                ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                                if (!context.mounted) return;
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _profileIoBusy
                                      ? null
                                      : _importProfiles,
                                  icon: const Icon(
                                    Icons.file_download_outlined,
                                  ),
                                  label: const Text('Import JSON'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _profileIoBusy
                                      ? null
                                      : _exportProfiles,
                                  icon: const Icon(Icons.file_upload_outlined),
                                  label: const Text('Export JSON'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedRouterCard extends StatelessWidget {
  final String routerTitle;
  final String subtitle;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _UnifiedRouterCard({
    required this.routerTitle,
    required this.subtitle,
    required this.isSelected,
    required this.isSwitching,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: isSelected ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.router,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                  size: 22,
                  semanticLabel: 'Router icon',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routerTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected && !isSwitching)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Chip(
                    label: const Text('Active'),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimary,
                    ),
                    backgroundColor: colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
              if (isSwitching)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

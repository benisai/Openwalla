import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/config/app_config.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/app_version.dart';
import 'package:openwalla/screens/router_components_screen.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  static const _outdatedRose = Color(0xFFFF8FB3);

  late final Future<_AppVersionStatus> _appVersionStatus;
  Future<RouterComponentStatus>? _componentStatus;

  @override
  void initState() {
    super.initState();
    _appVersionStatus = _loadAppVersionStatus();
  }

  Future<_AppVersionStatus> _loadAppVersionStatus() async {
    final package = await PackageInfo.fromPlatform();
    final installed = AppVersion(
      version: package.version,
      buildNumber: int.tryParse(package.buildNumber) ?? 0,
    );
    try {
      final response = await http
          .get(Uri.parse(AppConfig.githubPubspecUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return _AppVersionStatus(installed: installed);
      }
      return _AppVersionStatus(
        installed: installed,
        available: AppVersion.fromPubspec(response.body),
      );
    } catch (_) {
      return _AppVersionStatus(installed: installed);
    }
  }

  Future<RouterComponentStatus> _loadComponentStatus() async {
    final output = await ref
        .read(appStateProvider)
        .runRouterSetupCommandViaSsh(buildRouterComponentsCommand('status'));
    return RouterComponentStatus.parse(output);
  }

  void _checkComponentStatus() {
    setState(() => _componentStatus = _loadComponentStatus());
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final opened = await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this link.')),
      );
    }
  }

  void _openRouterComponents() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const RouterComponentsScreen(),
      ),
    );
  }

  Widget _buildRouterComponentsCard(ColorScheme colors) {
    final componentStatus = _componentStatus;
    if (componentStatus == null) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          leading: Icon(Icons.memory_rounded, color: colors.primary),
          title: const Text('Router Components'),
          subtitle: const Text('Tap to check the installed version'),
          trailing: const Icon(Icons.refresh_rounded),
          onTap: _checkComponentStatus,
        ),
      );
    }

    return FutureBuilder<RouterComponentStatus>(
      future: componentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final checking = snapshot.connectionState != ConnectionState.done;
        final outOfSync =
            snapshot.hasError || (status != null && !status.isCurrent);
        final statusColor = outOfSync ? _outdatedRose : colors.primary;
        final installedVersion = checking
            ? 'Checking'
            : status?.installedVersion ?? 'Unknown';

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Icon(Icons.memory_rounded, color: statusColor),
            title: const Text('Router Components'),
            subtitle: snapshot.hasError
                ? Text(
                    'Unable to check component version',
                    style: TextStyle(color: colors.error),
                  )
                : Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Installed '),
                        TextSpan(
                          text: '$installedVersion${outOfSync ? ' !' : ''}',
                          style: TextStyle(
                            color: outOfSync ? _outdatedRose : null,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text:
                              '  •  Available ${status?.availableVersion ?? 'Unknown'}',
                        ),
                      ],
                    ),
                  ),
            trailing: checking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : snapshot.hasError
                ? Icon(Icons.refresh_rounded, color: colors.error)
                : outOfSync
                ? const Icon(Icons.chevron_right_rounded, color: _outdatedRose)
                : Icon(Icons.verified_rounded, color: statusColor),
            onTap: checking
                ? null
                : snapshot.hasError
                ? _checkComponentStatus
                : outOfSync
                ? _openRouterComponents
                : _checkComponentStatus,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const LuciAppBar(title: 'About', showBack: true),
      body: FutureBuilder<_AppVersionStatus>(
        future: _appVersionStatus,
        builder: (context, snapshot) {
          final appVersion = snapshot.data;
          final appOutdated = appVersion?.isOutdated ?? false;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
            children: [
              Center(
                child: Image.asset(
                  'assets/branding/openwalla-mark.png',
                  width: 88,
                  height: 88,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Openwalla',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'OpenWrt router control',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: Icon(
                    Icons.info_outline_rounded,
                    color: colors.primary,
                  ),
                  title: const Text('App Version'),
                  subtitle: appVersion?.available == null
                      ? null
                      : Text('Available ${appVersion!.available!.display}'),
                  trailing: snapshot.connectionState != ConnectionState.done
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${appVersion?.installed.display ?? 'Unknown'}${appOutdated ? ' !' : ''}',
                              style: TextStyle(
                                color: appOutdated ? _outdatedRose : null,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (!appOutdated &&
                                appVersion?.available != null) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.verified_rounded,
                                size: 20,
                                color: colors.primary,
                              ),
                            ],
                          ],
                        ),
                  onTap: appOutdated
                      ? () => _openLink(context, AppConfig.githubRepositoryUrl)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              _buildRouterComponentsCard(colors),
              const SizedBox(height: 12),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: Icon(Icons.code_rounded, color: colors.primary),
                  title: const Text('Openwalla on GitHub'),
                  subtitle: const Text('benisai/openwalla-apk'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () =>
                      _openLink(context, AppConfig.githubRepositoryUrl),
                ),
              ),
              const SizedBox(height: 24),
              Text('Credits', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Icon(
                        Icons.account_tree_outlined,
                        color: colors.primary,
                      ),
                      title: const Text('Original Codebase'),
                      subtitle: const Text('cogwheel0/luci-mobile'),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () => _openLink(
                        context,
                        'https://github.com/cogwheel0/luci-mobile',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Icon(
                        Icons.fork_right_rounded,
                        color: colors.primary,
                      ),
                      title: const Text('Fork Codebase'),
                      subtitle: const Text('nightcodex7/yala'),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () => _openLink(
                        context,
                        'https://github.com/nightcodex7/yala',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppVersionStatus {
  final AppVersion installed;
  final AppVersion? available;

  const _AppVersionStatus({required this.installed, this.available});

  bool get isOutdated =>
      available != null && available!.compareTo(installed) > 0;
}

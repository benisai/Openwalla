import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openwalla/services/secure_storage_service.dart';
import 'package:openwalla/config/app_config.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _logoScale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
    _checkReviewerMode();
  }

  Future<void> _checkReviewerMode() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Check if reviewer mode is enabled
    final secureStorage = SecureStorageService();
    final reviewerModeEnabled = await secureStorage.readValue(
      AppConfig.reviewerModeKey,
    );

    if (reviewerModeEnabled == 'true' && mounted) {
      // Navigate directly to main screen in reviewer mode
      unawaited(Navigator.of(context).pushReplacementNamed('/'));
    } else if (mounted) {
      // Normal flow - go to login screen
      unawaited(Navigator.of(context).pushReplacementNamed('/login'));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _logoScale,
                child: Image.asset(
                  'assets/branding/openwalla-mark.png',
                  width: 112,
                  height: 112,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Openwalla',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'OpenWrt router control',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

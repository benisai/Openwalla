import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/screens/login_screen.dart';
import 'package:openwalla/screens/main_screen.dart';
import 'package:openwalla/screens/settings_screen.dart';
import 'package:openwalla/screens/splash_screen.dart';
import 'package:openwalla/screens/welcome_setup_screen.dart';

void main() {
  runApp(ProviderScope(child: const LuCIApp()));
}

final appStateProvider = ChangeNotifierProvider<AppState>(
  (ref) => AppState.instance,
);

class LuCIApp extends ConsumerWidget {
  const LuCIApp({super.key});

  static const Color _openwallaBackground = Color(0xFF151B29);
  static const Color _openwallaSurface = Color(0xFF202636);
  static const Color _openwallaSurfaceAlt = Color(0xFF242B3B);
  static const Color _openwallaCyan = Color(0xFF18AEEA);
  static const Color _openwallaOrange = Color(0xFFF27C24);
  static const Color _openwallaText = Color(0xFFF8FAFC);
  static const Color _openwallaMuted = Color(0xFF9CA4B5);

  ThemeData _buildOpenwallaTheme(
    Brightness brightness,
    OpenwallaThemeAccent accent,
  ) {
    final isDark = brightness == Brightness.dark;
    final primaryColor = accent.color;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: brightness,
        ).copyWith(
          primary: primaryColor,
          secondary: _openwallaCyan,
          tertiary: _openwallaOrange,
          surface: isDark ? _openwallaSurface : const Color(0xFFF5F7FB),
          surfaceContainerLowest: isDark
              ? _openwallaBackground
              : const Color(0xFFFFFFFF),
          surfaceContainerLow: isDark
              ? _openwallaSurface
              : const Color(0xFFFFFFFF),
          surfaceContainer: isDark
              ? _openwallaSurfaceAlt
              : const Color(0xFFE9EDF5),
          surfaceContainerHigh: isDark
              ? const Color(0xFF2B3345)
              : const Color(0xFFE1E6EF),
          surfaceContainerHighest: isDark
              ? const Color(0xFF344052)
              : const Color(0xFFD6DDE9),
          onSurface: isDark ? _openwallaText : const Color(0xFF172033),
          onSurfaceVariant: isDark ? _openwallaMuted : const Color(0xFF647086),
          outlineVariant: isDark
              ? const Color(0xFF334056)
              : const Color(0xFFC8D0DD),
          error: OpenwallaThemeAccent.red.color,
        );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? _openwallaBackground
          : const Color(0xFFF5F7FB),
      useMaterial3: true,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
            size: selected ? 27 : 25,
          );
        }),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        contentTextStyle: TextStyle(color: colorScheme.onSurface),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    return MaterialApp(
      title: 'Openwalla',
      theme: _buildOpenwallaTheme(Brightness.light, appState.themeAccent),
      darkTheme: _buildOpenwallaTheme(Brightness.dark, appState.themeAccent),
      themeMode: appState.themeMode,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/welcome-setup': (context) => const WelcomeSetupScreen(),
        '/': (context) => const MainScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}

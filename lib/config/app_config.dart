class AppConfig {
  static const String githubRepositoryUrl =
      'https://github.com/benisai/openwalla-apk';
  static const String githubPubspecUrl =
      'https://raw.githubusercontent.com/benisai/openwalla-apk/main/pubspec.yaml';

  // GitHub issues URL
  static const String githubIssuesUrl = '$githubRepositoryUrl/issues';

  // Reviewer mode configuration
  static const String reviewerModeKey = 'reviewer_mode_enabled';
  static const String mockDataPath = 'assets/mock/';
  static const Duration reviewerModeActivationDuration = Duration(seconds: 5);
  static const String reviewerModeWatermark = 'Reviewer Mode';
}

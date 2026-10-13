class AppConfig {
  static const String githubRepositoryUrl =
      'https://github.com/benisai/Openwalla';
  static const String githubPubspecUrl =
      'https://raw.githubusercontent.com/benisai/Openwalla/main/pubspec.yaml';
  static const String privacyPolicyUrl =
      '$githubRepositoryUrl/blob/main/PRIVACY_POLICY.md';

  // GitHub issues URL
  static const String githubIssuesUrl = '$githubRepositoryUrl/issues';

  // Reviewer mode configuration
  static const String reviewerModeKey = 'reviewer_mode_enabled';
  static const String mockDataPath = 'assets/mock/';
  static const Duration reviewerModeActivationDuration = Duration(seconds: 5);
  static const String reviewerModeWatermark = 'Reviewer Mode';
}

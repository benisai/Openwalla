class AppVersion implements Comparable<AppVersion> {
  final String version;
  final int buildNumber;

  const AppVersion({required this.version, required this.buildNumber});

  static AppVersion? fromPubspec(String contents) {
    final match = RegExp(
      r'^version:\s*([^+\s]+)(?:\+(\d+))?\s*$',
      multiLine: true,
    ).firstMatch(contents);
    if (match == null) return null;
    return AppVersion(
      version: match.group(1)!,
      buildNumber: int.tryParse(match.group(2) ?? '') ?? 0,
    );
  }

  @override
  int compareTo(AppVersion other) {
    final ownParts = _numericParts(version);
    final otherParts = _numericParts(other.version);
    final length = ownParts.length > otherParts.length
        ? ownParts.length
        : otherParts.length;
    for (var index = 0; index < length; index++) {
      final own = index < ownParts.length ? ownParts[index] : 0;
      final theirs = index < otherParts.length ? otherParts[index] : 0;
      if (own != theirs) return own.compareTo(theirs);
    }
    return buildNumber.compareTo(other.buildNumber);
  }

  static List<int> _numericParts(String value) => value
      .split('.')
      .map((part) => int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '') ?? 0)
      .toList();

  String get display => '$version ($buildNumber)';
}

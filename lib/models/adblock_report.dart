class AdblockDnsRequest {
  final int id;
  final DateTime timestamp;
  final String client;
  final String mac;
  final String deviceName;
  final String domain;
  final String type;
  final String matchedRule;

  AdblockDnsRequest._(List<String> fields)
    : id = int.parse(fields[1]),
      timestamp = DateTime.fromMillisecondsSinceEpoch(
        int.parse(fields[2]) * 1000,
      ),
      client = fields[3],
      mac = fields[4],
      deviceName = fields[5],
      domain = fields[6],
      type = fields[7],
      matchedRule = fields[8];

  String get deviceLabel => deviceName.isEmpty ? client : deviceName;
}

class AdblockReport {
  final int total;
  final int matching;
  final DateTime? heartbeat;
  final List<AdblockDnsRequest> requests;
  final bool hasMore;
  int? get nextId => requests.isEmpty ? null : requests.last.id;

  AdblockReport._(
    this.total,
    this.matching,
    this.heartbeat,
    this.requests,
    this.hasMore,
  );

  factory AdblockReport.parse(String source, {int limit = 200}) {
    final lines = source.trim().split('\n');
    final summary = lines.first.split('|');
    if (summary.length != 6 || summary[0] != 'S') {
      throw const FormatException('Invalid SQLite report response');
    }
    final total = int.parse(summary[1]);
    final matching = int.parse(summary[2]);
    final heartbeat = int.parse(summary[5]);
    final rows = <AdblockDnsRequest>[];
    for (final line in lines.skip(1)) {
      final fields = line.split('|');
      if (fields.length != 9 || fields[0] != 'R') {
        throw const FormatException('Invalid SQLite report row');
      }
      rows.add(AdblockDnsRequest._(fields));
    }
    return AdblockReport._(
      total,
      matching,
      heartbeat == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(heartbeat * 1000),
      rows.take(limit).toList(),
      rows.length > limit,
    );
  }
}

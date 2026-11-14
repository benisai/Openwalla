import 'dart:convert';

const adblockReportPath = '/tmp/openwalla/adblock-report.json';

class AdblockDnsRequest {
  final String domain;
  final String client;
  final String date;
  final String time;
  final String type;
  final String interface;
  final String result;

  AdblockDnsRequest.fromJson(Map data)
    : domain = '${data['domain'] ?? ''}',
      client = '${data['client'] ?? ''}',
      date = '${data['date'] ?? ''}',
      time = '${data['time'] ?? ''}',
      type = '${data['type'] ?? ''}',
      interface = '${data['iface'] ?? ''}',
      result = '${data['rc'] ?? ''}';

  String get resultLabel => switch (result) {
    'OK' => 'Allowed',
    'NX' => 'NXDOMAIN',
    'SF' => 'Failed',
    _ => result,
  };

  bool matches(String search) => [
    domain,
    client,
    date,
    time,
    type,
    interface,
    result,
    resultLabel,
  ].any((value) => value.toLowerCase().contains(search.toLowerCase()));
}

class AdblockReport {
  final DateTime generatedAt;
  final int total;
  final int blocked;
  final String start;
  final String end;
  final List<AdblockDnsRequest> requests;

  AdblockReport._(
    this.generatedAt,
    this.total,
    this.blocked,
    this.start,
    this.end,
    this.requests,
  );

  factory AdblockReport.parse(String source) {
    final envelope = jsonDecode(source);
    if (envelope is! Map || envelope['generated_at'] is! num) {
      throw const FormatException('Invalid AdBlock report cache');
    }
    final payload = envelope['data'];
    final data = payload is List && payload.isNotEmpty
        ? payload.first
        : payload;
    if (data is! Map || !data.containsKey('total')) {
      throw const FormatException('Invalid AdBlock report data');
    }
    int count(String key) => int.tryParse('${data[key]}') ?? 0;
    final rows = data['requests'];
    if (rows != null && rows is! List) {
      throw const FormatException('Invalid DNS requests');
    }
    return AdblockReport._(
      DateTime.fromMillisecondsSinceEpoch(
        (envelope['generated_at'] as num).toInt() * 1000,
      ),
      count('total'),
      count('blocked'),
      '${data['start_date'] ?? ''} ${data['start_time'] ?? ''}'.trim(),
      '${data['end_date'] ?? ''} ${data['end_time'] ?? ''}'.trim(),
      [
        for (final row in rows as List? ?? [])
          if (row is Map) AdblockDnsRequest.fromJson(row),
      ],
    );
  }
}

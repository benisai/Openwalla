// JSON is only the transport encoding here, not a stored database payload.
class NetifyFlowStorage {
  static const projection = '''json_object(
    'type','flow','timeinsert',timeinsert,'interface',interface,
    'flow',json_object(
      'first_seen_at',first_seen_at,'last_seen_at',last_seen_at,
      'local_ip',local_ip,'local_port',local_port,'local_mac',local_mac,
      'fqdn',fqdn,'other_ip',dest_ip,'other_port',dest_port,
      'detected_protocol_name',detected_protocol_name,
      'detected_application_name',detected_app_name,
      'host_server_name',fqdn,
      'dns_host_name',dns_host_name,
      'other_bytes',downloaded_bytes,'local_bytes',uploaded_bytes,
      'total_bytes',total_bytes,'other_country_code',country_code,
      'other_country_name',region,'direction',direction))''';

  static String _quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  static String pageCommand({
    required String dbExpression,
    required String where,
    required int limit,
    required int offset,
    required String endMarker,
  }) {
    final suffix =
        'FROM flow_raw $where ORDER BY id DESC LIMIT $limit OFFSET $offset; '
        "SELECT '$endMarker';";
    return 'db="$dbExpression"; '
        'if command -v sqlite3 >/dev/null 2>&1; then sqlite=sqlite3; '
        'elif command -v sqlite3-cli >/dev/null 2>&1; then sqlite=sqlite3-cli; '
        'else echo "sqlite3 not installed" >&2; exit 127; fi; '
        'statement=${_quote('SELECT $projection $suffix')}; '
        '"\$sqlite" -batch -list -noheader "\$db" "\$statement"';
  }
}

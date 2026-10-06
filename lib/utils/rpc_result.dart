bool rpcBooleanResultSucceeded(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value == 1;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' || normalized == 'true';
  }

  if (value is Map) {
    if (value.containsKey('result')) {
      return rpcBooleanResultSucceeded(value['result']);
    }
    if (value.containsKey('data')) {
      return rpcBooleanResultSucceeded(value['data']);
    }
    return false;
  }

  if (value is List) {
    if (value.isEmpty) return false;

    final status = value.first;
    if (status is num || status is String) {
      final statusCode = int.tryParse(status.toString());
      if (statusCode != null) {
        if (statusCode != 0 || value.length < 2) return false;
        return rpcBooleanResultSucceeded(value[1]);
      }
    }

    return value.any(rpcBooleanResultSucceeded);
  }

  return false;
}

int? rpcUbusStatusCode(dynamic value) {
  if (value is! List || value.isEmpty) return null;
  return int.tryParse(value.first.toString());
}

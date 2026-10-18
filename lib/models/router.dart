class Router {
  final String id;
  final String ipAddress;
  final String username;
  final String password;
  final bool useHttps;
  final String? lastKnownHostname;
  final String? fingerprint;
  final int identityVersion;

  Router({
    required this.id,
    required this.ipAddress,
    required this.username,
    required this.password,
    required this.useHttps,
    this.lastKnownHostname,
    this.fingerprint,
    this.identityVersion = 2,
  });

  factory Router.fromJson(Map<String, dynamic> json) {
    return Router(
      id: json['id'] as String,
      ipAddress: json['ipAddress'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      useHttps: json['useHttps'] == true || json['useHttps'] == 'true',
      lastKnownHostname: json['lastKnownHostname'] as String?,
      fingerprint: json['fingerprint']?.toString(),
      identityVersion:
          int.tryParse(json['identityVersion']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ipAddress': ipAddress,
    'username': username,
    'password': password,
    'useHttps': useHttps,
    if (lastKnownHostname != null) 'lastKnownHostname': lastKnownHostname,
    if (fingerprint != null) 'fingerprint': fingerprint,
    'identityVersion': identityVersion,
  };

  Router copyWith({
    String? id,
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps,
    String? lastKnownHostname,
    String? fingerprint,
    int? identityVersion,
  }) {
    return Router(
      id: id ?? this.id,
      ipAddress: ipAddress ?? this.ipAddress,
      username: username ?? this.username,
      password: password ?? this.password,
      useHttps: useHttps ?? this.useHttps,
      lastKnownHostname: lastKnownHostname ?? this.lastKnownHostname,
      fingerprint: fingerprint ?? this.fingerprint,
      identityVersion: identityVersion ?? this.identityVersion,
    );
  }
}

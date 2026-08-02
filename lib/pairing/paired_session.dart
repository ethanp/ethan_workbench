/// One paired phone on the Mac companion (token stored as SHA-256 only).
class PairedSession {
  const PairedSession({
    required this.sessionId,
    required this.tokenHash,
    required this.label,
    required this.pairedAt,
  });

  final String sessionId;

  /// Hex SHA-256 of the bearer token — never the raw token.
  final String tokenHash;
  final String label;
  final DateTime pairedAt;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'tokenHash': tokenHash,
    'label': label,
    'pairedAt': pairedAt.toIso8601String(),
  };

  factory PairedSession.fromJson(Map<String, dynamic> json) {
    return PairedSession(
      sessionId: json['sessionId'] as String,
      tokenHash: json['tokenHash'] as String,
      label: json['label'] as String? ?? 'iPhone',
      pairedAt: DateTime.tryParse(json['pairedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class PairedSession {
  final String sessionId;
  final String token;
  final String label;
  final DateTime pairedAt;

  const PairedSession({
    required this.sessionId,
    required this.token,
    required this.label,
    required this.pairedAt,
  });
}

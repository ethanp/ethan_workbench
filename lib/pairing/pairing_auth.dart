import 'dart:async';
import 'dart:math';

import 'paired_session.dart';

/// Issues short-lived pairing PINs and long-lived phone sessions.
class PairingAuth {
  static const pinLifetime = Duration(minutes: 1);

  final _updates = StreamController<void>.broadcast();
  final _sessions = <PairedSession>[];
  final _random = Random.secure();

  String? _pin;
  DateTime? _pinExpiresAt;

  Stream<void> get updates => _updates.stream;
  int get sessionCount => _sessions.length;
  List<PairedSession> get sessions => List.unmodifiable(_sessions);

  String get pin {
    ensureFreshPin();
    return _pin!;
  }

  DateTime get pinExpiresAt {
    ensureFreshPin();
    return _pinExpiresAt!;
  }

  Duration get pinTimeRemaining {
    final remaining = pinExpiresAt.difference(DateTime.now());
    if (remaining.isNegative) return Duration.zero;
    return remaining;
  }

  void ensureFreshPin() {
    if (_pin == null ||
        _pinExpiresAt == null ||
        !DateTime.now().isBefore(_pinExpiresAt!)) {
      rotatePin();
    }
  }

  void rotatePin() {
    _pin = _random.nextInt(1000000).toString().padLeft(6, '0');
    _pinExpiresAt = DateTime.now().add(pinLifetime);
    _emit();
  }

  /// Returns a session token when [pin] matches the current live PIN.
  String? pair(String pin, {String label = 'iPhone'}) {
    ensureFreshPin();
    if (pin.trim() != _pin) return null;
    final token = _newToken();
    _sessions.add(
      PairedSession(
        sessionId: _newToken().substring(0, 12),
        token: token,
        label: label.trim().isEmpty ? 'iPhone' : label.trim(),
        pairedAt: DateTime.now(),
      ),
    );
    rotatePin();
    return token;
  }

  bool isAuthorized(String? bearerToken) {
    if (bearerToken == null || bearerToken.isEmpty) return false;
    return _sessions.any((session) => session.token == bearerToken);
  }

  bool revokeSession(String sessionId) {
    final before = _sessions.length;
    _sessions.removeWhere((session) => session.sessionId == sessionId);
    final removed = _sessions.length < before;
    if (removed) _emit();
    return removed;
  }

  void revokeAllSessions() {
    if (_sessions.isEmpty) return;
    _sessions.clear();
    _emit();
  }

  Future<void> dispose() async {
    await _updates.close();
  }

  String _newToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  void _emit() {
    if (!_updates.isClosed) _updates.add(null);
  }
}

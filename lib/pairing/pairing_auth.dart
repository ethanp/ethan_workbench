import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'paired_session.dart';
import 'paired_session_store.dart';

/// Issues short-lived pairing PINs and long-lived phone sessions.
///
/// Session bearer tokens are shown once to the phone; the Mac only keeps
/// SHA-256 hashes on disk so companion restarts do not force re-pairing.
class PairingAuth {
  PairingAuth({PairedSessionStore? store})
    : _store = store ?? PairedSessionStore();

  static const pinLifetime = Duration(minutes: 1);

  /// Paired phones older than this must enter a fresh PIN.
  static const sessionLifetime = Duration(days: 180);

  final PairedSessionStore _store;
  final _updates = StreamController<void>.broadcast();
  final _sessions = <PairedSession>[];
  final _random = Random.secure();

  String? _pin;
  DateTime? _pinExpiresAt;
  Future<void>? _persistInFlight;

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

  /// Load hashed sessions from disk (call once during companion bootstrap).
  Future<void> restorePersistedSessions() async {
    final restored = await _store.readSessions();
    _sessions
      ..clear()
      ..addAll(restored.where(_isSessionUnexpired));
    if (_sessions.length != restored.length) {
      await _persistSessions();
    }
    _emit();
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
        tokenHash: hashBearerToken(token),
        label: label.trim().isEmpty ? 'iPhone' : label.trim(),
        pairedAt: DateTime.now(),
      ),
    );
    rotatePin();
    unawaited(_persistSessions());
    return token;
  }

  bool isAuthorized(String? bearerToken) {
    if (bearerToken == null || bearerToken.isEmpty) return false;
    final tokenHash = hashBearerToken(bearerToken);
    final matchIndex = _sessions.indexWhere(
      (session) =>
          _isSessionUnexpired(session) && session.tokenHash == tokenHash,
    );
    if (matchIndex < 0) {
      _pruneExpiredSessions();
      return false;
    }
    return true;
  }

  bool revokeSession(String sessionId) {
    final before = _sessions.length;
    _sessions.removeWhere((session) => session.sessionId == sessionId);
    final removed = _sessions.length < before;
    if (removed) {
      unawaited(_persistSessions());
      _emit();
    }
    return removed;
  }

  void revokeAllSessions() {
    if (_sessions.isEmpty) return;
    _sessions.clear();
    unawaited(_persistSessions());
    _emit();
  }

  Future<void> dispose() async {
    await _persistInFlight;
    await _updates.close();
  }

  /// Completes when the latest disk write finishes (tests / shutdown).
  Future<void> waitForPersistence() async {
    await _persistInFlight;
  }

  static String hashBearerToken(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }

  bool _isSessionUnexpired(PairedSession session) {
    return DateTime.now().difference(session.pairedAt) <= sessionLifetime;
  }

  void _pruneExpiredSessions() {
    final before = _sessions.length;
    _sessions.removeWhere((session) => !_isSessionUnexpired(session));
    if (_sessions.length < before) {
      unawaited(_persistSessions());
      _emit();
    }
  }

  Future<void> _persistSessions() async {
    final previous = _persistInFlight;
    final next = () async {
      await previous;
      await _store.writeSessions(List.unmodifiable(_sessions));
    }();
    _persistInFlight = next;
    await next;
  }

  String _newToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  void _emit() {
    if (!_updates.isClosed) _updates.add(null);
  }
}

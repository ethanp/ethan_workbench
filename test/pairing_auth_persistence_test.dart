import 'dart:io';

import 'package:ethan_workbench/pairing/paired_session_store.dart';
import 'package:ethan_workbench/pairing/pairing_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDirectory;
  late PairingAuth pairingAuth;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('pairing_auth_');
    pairingAuth = PairingAuth(
      store: PairedSessionStore(directory: tempDirectory),
    );
  });

  tearDown(() async {
    await pairingAuth.dispose();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('paired token survives restore from disk as hash only', () async {
    final pin = pairingAuth.pin;
    final token = pairingAuth.pair(pin, label: 'TestPhone');
    expect(token, isNotNull);
    expect(pairingAuth.isAuthorized(token), isTrue);
    expect(
      pairingAuth.sessions.single.tokenHash,
      PairingAuth.hashBearerToken(token!),
    );
    await pairingAuth.waitForPersistence();

    final restored = PairingAuth(
      store: PairedSessionStore(directory: tempDirectory),
    );
    await restored.restorePersistedSessions();
    expect(restored.sessionCount, 1);
    expect(restored.sessions.single.label, 'TestPhone');
    expect(restored.isAuthorized(token), isTrue);
    expect(restored.isAuthorized('deadbeef'), isFalse);

    final storeFile = File('${tempDirectory.path}/paired_phone_sessions.json');
    final disk = await storeFile.readAsString();
    expect(disk.contains(token), isFalse);
    expect(disk.contains(restored.sessions.single.tokenHash), isTrue);

    await restored.dispose();
  });

  test('revokeAllSessions clears disk', () async {
    final token = pairingAuth.pair(pairingAuth.pin)!;
    await pairingAuth.waitForPersistence();
    pairingAuth.revokeAllSessions();
    await pairingAuth.waitForPersistence();

    final restored = PairingAuth(
      store: PairedSessionStore(directory: tempDirectory),
    );
    await restored.restorePersistedSessions();
    expect(restored.sessionCount, 0);
    expect(restored.isAuthorized(token), isFalse);
    await restored.dispose();
  });
}

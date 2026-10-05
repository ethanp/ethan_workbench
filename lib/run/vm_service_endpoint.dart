import 'dart:async';
import 'dart:io';

/// A Dart VM service URL saved from `flutter run` (host-forwarded debug URI).
class const VmServiceEndpoint(final String? uriText) {
  bool get isPresent => uriText != null && uriText!.isNotEmpty;

  /// Whether something is accepting TCP connections at this URI's host and port.
  ///
  /// A saved URI often dies with the `flutter run` that forwarded it, while the
  /// app is still on the simulator. Attach must not keep that URI or it retries
  /// the closed port instead of discovering the app.
  Future<bool> get isListening async {
    if (!isPresent) return false;
    final uri = Uri.tryParse(uriText!);
    if (uri == null || uri.host.isEmpty || uri.port == 0) return false;
    try {
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: const Duration(milliseconds: 400),
      );
      await socket.close();
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }
}

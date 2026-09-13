import 'package:http/http.dart' as http;

import 'server_endpoint.dart';

/// Probe the workbench daemon on loopback (`GET /health`).
class WorkbenchLoopback() {
  static Future<bool> get isHealthy async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse('$loopbackServerBaseUrl/health'))
          .timeout(const Duration(seconds: 1));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}

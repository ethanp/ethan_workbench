import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Logs meaningful traffic; skips noisy job/health polls from the phone UI.
Middleware quietRequestLog() {
  return (Handler innerHandler) {
    return (Request request) async {
      final startedAt = DateTime.now();
      final requestBody = await _readMutableRequestBody(request);
      final effectiveRequest =
          requestBody == null ? request : request.change(body: requestBody);
      final requestDetail = _deployRequestDetailForLog(
        effectiveRequest.requestedUri.path,
        requestBody,
      );
      final response = await innerHandler(effectiveRequest);
      if (!_shouldLogRequest(effectiveRequest, response)) return response;

      final elapsed = DateTime.now().difference(startedAt);
      final path = effectiveRequest.requestedUri.path;
      if (response.statusCode < 400) {
        // ignore: avoid_print — companion console feedback for deploy actions
        print(
          '${startedAt.toIso8601String()}  '
          '${elapsed.toString().padLeft(15)} '
          '${effectiveRequest.method.padRight(7)} '
          '[${response.statusCode}] '
          '$path'
          '${requestDetail == null ? '' : ' — $requestDetail'}',
        );
        return response;
      }

      final responseBody = await response.readAsString();
      final errorDetail = _errorDetailForLog(responseBody);
      final details = [
        ?requestDetail,
        ?errorDetail,
      ].join(' — ');
      // ignore: avoid_print — companion console feedback for deploy actions
      print(
        '${startedAt.toIso8601String()}  '
        '${elapsed.toString().padLeft(15)} '
        '${effectiveRequest.method.padRight(7)} '
        '[${response.statusCode}] '
        '$path'
        '${details.isEmpty ? '' : ' — $details'}',
      );
      return response.change(body: responseBody);
    };
  };
}

Future<String?> _readMutableRequestBody(Request request) async {
  if (request.method != 'POST' && request.method != 'PUT') return null;
  return request.readAsString();
}

String? _deployRequestDetailForLog(String path, String? body) {
  if (path != '/deploy' || body == null || body.isEmpty) return null;
  try {
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final projectId = payload['projectId'] as String?;
    if (projectId == null || projectId.isEmpty) return null;
    final force = payload['force'] as bool? ?? false;
    return force ? '$projectId force' : projectId;
  } catch (_) {
    return null;
  }
}

String? _errorDetailForLog(String body) {
  if (body.isEmpty) return null;
  try {
    final payload = jsonDecode(body);
    if (payload is Map<String, dynamic>) {
      final errorMessage = payload['error'];
      if (errorMessage is String && errorMessage.isNotEmpty) {
        return errorMessage;
      }
    }
  } catch (_) {
    // Fall through to raw body.
  }
  const maxLength = 200;
  if (body.length <= maxLength) return body;
  return '${body.substring(0, maxLength)}…';
}

bool _shouldLogRequest(Request request, Response response) {
  if (response.statusCode >= 400) return true;
  final path = request.requestedUri.path;
  if (request.method == 'GET' && path == '/health') return false;
  if (request.method == 'GET' && path.startsWith('/jobs/')) return false;
  return true;
}

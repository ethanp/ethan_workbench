import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'server_endpoint.dart';

/// Requires `Authorization: Bearer <SERVER_PASSWORD>` for every route except
/// `/health`. Fails closed when [serverPassword] is empty.
Middleware passwordAuthMiddleware() {
  return (Handler innerHandler) {
    return (Request request) {
      final path = request.requestedUri.path;
      if (path == '/health') {
        return innerHandler(request);
      }
      final expected = serverPassword;
      if (expected.isEmpty) {
        return Response.unauthorized(
          jsonEncode({
            'error':
                'SERVER_PASSWORD is not set on the Mac — add it to .env and restart',
          }),
          headers: const {'Content-Type': 'application/json'},
        );
      }
      final authorization = request.headers['authorization'];
      final token = authorization?.startsWith('Bearer ') == true
          ? authorization!.substring('Bearer '.length).trim()
          : null;
      if (token != expected) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized — check the shared password'}),
          headers: const {'Content-Type': 'application/json'},
        );
      }
      return innerHandler(request);
    };
  };
}

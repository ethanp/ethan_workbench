import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'pairing_auth.dart';

/// Requires a paired bearer token for all routes except health and pair.
Middleware pairingAuthMiddleware(PairingAuth pairingAuth) {
  return (Handler innerHandler) {
    return (Request request) {
      final path = request.requestedUri.path;
      if (path == '/health' || path == '/pair') {
        return innerHandler(request);
      }
      final authorization = request.headers['authorization'];
      final token = authorization?.startsWith('Bearer ') == true
          ? authorization!.substring('Bearer '.length).trim()
          : null;
      if (!pairingAuth.isAuthorized(token)) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized — pair with the PIN on the Mac'}),
          headers: const {'Content-Type': 'application/json'},
        );
      }
      return innerHandler(request);
    };
  };
}

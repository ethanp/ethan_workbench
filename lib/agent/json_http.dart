import 'dart:convert';

import 'package:shelf/shelf.dart';

const jsonHeaders = {'Content-Type': 'application/json'};

Response jsonOk(Object body) {
  return Response.ok(jsonEncode(body), headers: jsonHeaders);
}

Response jsonError(String message, {required int status}) {
  return Response(
    status,
    body: jsonEncode({'error': message}),
    headers: jsonHeaders,
  );
}

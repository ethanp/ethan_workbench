import 'dart:convert';

import 'package:http/http.dart' as http;

import '../agent/agent_endpoint.dart';
import 'models.dart';

class DeployClientException implements Exception {
  final String message;
  final int? statusCode;

  const DeployClientException(this.message, {this.statusCode});

  @override
  String toString() => message;

  bool get isUnauthorized => statusCode == 401;
}

class DeployClient {
  DeployClient({
    String? baseUrl,
    this._bearerToken,
    http.Client? httpClient,
  })  : _baseUrl = (baseUrl ?? phoneDeployAgentBaseUrl)
            .replaceAll(RegExp(r'/+$'), ''),
        _httpClient = httpClient ?? http.Client();

  final String _baseUrl;
  String? _bearerToken;
  final http.Client _httpClient;

  String? get bearerToken => _bearerToken;

  void setBearerToken(String? token) {
    _bearerToken = token;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = _bearerToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<void> checkHealth() async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/health'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Health check failed');
  }

  Future<String> pair(String pin, {String label = 'iPhone'}) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/pair'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'pin': pin,
        'label': label,
      }),
    );
    _throwIfFailed(response, 'Pairing failed');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final token = payload['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const DeployClientException('Pairing response missing token');
    }
    _bearerToken = token;
    return token;
  }

  Future<List<DeployableProject>> listProjects() async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/projects'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to list projects');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final projectMaps = payload['projects'] as List<dynamic>;
    return projectMaps
        .map(
          (projectMap) =>
              DeployableProject.fromJson(projectMap as Map<String, dynamic>),
        )
        .toList();
  }

  Future<DeployJob> startDeploy({
    required String projectId,
    bool force = false,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/deploy'),
      headers: _headers,
      body: jsonEncode({
        'projectId': projectId,
        'force': force,
      }),
    );
    _throwIfFailed(response, 'Failed to start deploy');
    return DeployJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<DeployJob> getJob(String jobId) async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/jobs/$jobId'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to load job');
    return DeployJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<DeployJob?> getActiveJob() async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/jobs/active'),
      headers: _headers,
    );
    if (response.statusCode == 404) return null;
    _throwIfFailed(response, 'Failed to load active job');
    return DeployJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  void _throwIfFailed(http.Response response, String fallbackMessage) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = fallbackMessage;
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final errorMessage = payload['error'] as String?;
      if (errorMessage != null && errorMessage.isNotEmpty) {
        message = errorMessage;
      }
    } catch (_) {}
    throw DeployClientException(message, statusCode: response.statusCode);
  }

  void close() => _httpClient.close();
}

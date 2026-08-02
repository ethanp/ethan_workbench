import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../agent/agent_endpoint.dart';
import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_run_record.dart';
import '../projects/deployable_project.dart';
import '../run/local_run_state.dart';

class AgentRequestException implements Exception {
  final String message;
  final int? statusCode;

  const AgentRequestException(this.message, {this.statusCode});

  @override
  String toString() => message;

  bool get isUnauthorized => statusCode == 401;
}

/// HTTP client for the Mac LAN agent (pair, list projects, start deploys).
class MacAgentClient {
  MacAgentClient({String? baseUrl, this._bearerToken, http.Client? httpClient})
    : _baseUrl = (baseUrl ?? agentBaseUrl).replaceAll(
        RegExp(r'/+$'),
        '',
      ),
      _httpClient = httpClient ?? http.Client();

  final String _baseUrl;
  String? _bearerToken;
  final http.Client _httpClient;
  http.Client? _jobEventsClient;
  http.Client? _runEventsClient;

  String? get bearerToken => _bearerToken;

  void setBearerToken(String? token) {
    _bearerToken = token;
  }

  /// Aborts an in-flight [watchJobEvents] connection, if any.
  void cancelJobEvents() {
    _jobEventsClient?.close();
    _jobEventsClient = null;
  }

  /// Aborts an in-flight [watchLocalRunEvents] connection, if any.
  void cancelRunEvents() {
    _runEventsClient?.close();
    _runEventsClient = null;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = _bearerToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, String> get _sseHeaders {
    final headers = <String, String>{'Accept': 'text/event-stream'};
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
      body: jsonEncode({'pin': pin, 'label': label}),
    );
    _throwIfFailed(response, 'Pairing failed');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final token = payload['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const AgentRequestException('Pairing response missing token');
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
    return _parseProjects(response.body);
  }

  Future<List<DeployableProject>> evaluateSourceChanges() async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/projects/evaluate-changes'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to check for source changes');
    return _parseProjects(response.body);
  }

  List<DeployableProject> _parseProjects(String body) {
    final payload = jsonDecode(body) as Map<String, dynamic>;
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
    required DeployPlatform platform,
    bool force = false,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/deploy'),
      headers: _headers,
      body: jsonEncode({
        'projectId': projectId,
        'platform': platform.name,
        'force': force,
      }),
    );
    if (response.statusCode == 409) {
      final conflict = _deployAlreadyRunningFromConflict(response);
      if (conflict != null) throw conflict;
    }
    _throwIfFailed(response, 'Failed to start deploy');
    return DeployJob.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  DeployAlreadyRunning? _deployAlreadyRunningFromConflict(
    http.Response response,
  ) {
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final jobJson = payload['job'];
      if (jobJson is! Map<String, dynamic>) return null;
      final job = DeployJob.fromJson(jobJson);
      return DeployAlreadyRunning(
        projectName: job.projectName,
        jobId: job.jobId,
        statusName: job.status.name,
        job: job,
      );
    } catch (_) {
      return null;
    }
  }

  Future<DeployJob> fetchJob(String jobId) async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/jobs/$jobId'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to load job');
    return DeployJob.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<DeployJob?> fetchActiveJob() async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/jobs/active'),
      headers: _headers,
    );
    if (response.statusCode == 404) return null;
    _throwIfFailed(response, 'Failed to load active job');
    return DeployJob.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<DeployRunRecord>> listDeployHistory() async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/jobs/history'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to load deploy history');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final runMaps = payload['runs'] as List<dynamic>? ?? const [];
    return [
      for (final runMap in runMaps)
        DeployRunRecord.fromJson(runMap as Map<String, dynamic>),
    ];
  }

  /// Live job snapshots from `GET /jobs/events` (SSE). Completes when the
  /// connection drops; callers should reconnect while still paired.
  Stream<DeployJob> watchJobEvents() async* {
    cancelJobEvents();
    final eventsClient = http.Client();
    _jobEventsClient = eventsClient;
    try {
      yield* _watchSseJson(
        client: eventsClient,
        path: '/jobs/events',
        parse: (payload) =>
            DeployJob.fromJson(payload as Map<String, dynamic>),
        failureMessage: 'Failed to open job events stream',
      );
    } finally {
      if (identical(_jobEventsClient, eventsClient)) {
        _jobEventsClient = null;
      }
      eventsClient.close();
    }
  }

  Future<LocalRunState> fetchLocalRun() async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl/run'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to load local run');
    return LocalRunState.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Stream<LocalRunState> watchLocalRunEvents() async* {
    cancelRunEvents();
    final eventsClient = http.Client();
    _runEventsClient = eventsClient;
    try {
      yield* _watchSseJson(
        client: eventsClient,
        path: '/run/events',
        parse: (payload) =>
            LocalRunState.fromJson(payload as Map<String, dynamic>),
        failureMessage: 'Failed to open local run events stream',
      );
    } finally {
      if (identical(_runEventsClient, eventsClient)) {
        _runEventsClient = null;
      }
      eventsClient.close();
    }
  }

  Future<LocalRunState> startLocalRun({
    required String projectId,
    required String deviceKey,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/run'),
      headers: _headers,
      body: jsonEncode({
        'projectId': projectId,
        'deviceKey': deviceKey,
      }),
    );
    _throwIfFailed(response, 'Failed to start local run');
    return LocalRunState.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<LocalRunState> stopLocalRun() async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/run/stop'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to stop local run');
    return LocalRunState.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<LocalRunState> hotReloadLocalRun() async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/run/hot-reload'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to hot reload');
    return LocalRunState.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<LocalRunState> hotRestartLocalRun() async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/run/hot-restart'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to hot restart');
    return LocalRunState.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<LocalRunState> fullRestartLocalRun() async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/run/full-restart'),
      headers: _headers,
    );
    _throwIfFailed(response, 'Failed to full restart');
    return LocalRunState.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Stream<T> _watchSseJson<T>({
    required http.Client client,
    required String path,
    required T Function(Object? payload) parse,
    required String failureMessage,
  }) async* {
    final request = http.Request('GET', Uri.parse('$_baseUrl$path'));
    request.headers.addAll(_sseHeaders);
    final streamedResponse = await client.send(request);
    if (streamedResponse.statusCode == 401) {
      throw const AgentRequestException(
        'Unauthorized',
        statusCode: 401,
      );
    }
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      throw AgentRequestException(
        failureMessage,
        statusCode: streamedResponse.statusCode,
      );
    }

    final lines = streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trimLeft();
      if (payload.isEmpty || payload == '[DONE]') continue;
      yield parse(jsonDecode(payload));
    }
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
    throw AgentRequestException(message, statusCode: response.statusCode);
  }

  void close() {
    cancelJobEvents();
    cancelRunEvents();
    _httpClient.close();
  }
}

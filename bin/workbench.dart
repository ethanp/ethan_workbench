import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Standalone CLI — do not import `package:ethan_workbench` (that pulls Flutter).
Future<void> main(List<String> arguments) async {
  await WorkbenchCli().run(arguments);
}

class WorkbenchCli() {
  static const _flutterSdk = '/opt/homebrew/share/flutter/bin/flutter';
  static const _launchAgentLabel = 'com.ethan.ethanWorkbench.daemon';
  static const _daemonDownHint =
      'Workbench daemon is not running. Start it with:\n'
      '  Flutter/ethan_workbench/scripts/workbench daemon start';

  final Directory packageRoot = _packageRoot();
  late final Map<String, String> envFile = _loadEnvFile(packageRoot);

  Future<void> run(List<String> arguments) async {
    if (arguments.isEmpty) {
      _usage();
      exitCode = 1;
      return;
    }
    switch (arguments.first) {
      case 'health':
        await health();
      case 'projects':
        await projects();
      case 'deploy':
        await deploy(arguments.skip(1).toList());
      case 'job':
        await job(arguments.skip(1).toList());
      case 'daemon':
        await daemon(arguments.skip(1).toList());
      case '-h':
      case '--help':
        _usage();
      default:
        stderr.writeln('Unknown command: ${arguments.first}');
        _usage();
        exitCode = 1;
    }
  }

  String get _baseUrl => 'http://127.0.0.1:$port';

  int get port => int.tryParse(env('SERVER_PORT') ?? '') ?? 8787;

  String get password => env('SERVER_PASSWORD') ?? '';

  String? env(String key) {
    final fromFile = envFile[key];
    if (fromFile != null && fromFile.isNotEmpty) return fromFile;
    final fromProcess = Platform.environment[key];
    if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
    return null;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (password.isNotEmpty) {
      headers['Authorization'] = 'Bearer $password';
    }
    return headers;
  }

  Future<void> health() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        stdout.writeln('ok $_baseUrl');
        return;
      }
      stderr.writeln('health failed: HTTP ${response.statusCode}');
      exitCode = 1;
    } on SocketException {
      stderr.writeln(_daemonDownHint);
      exitCode = 1;
    }
  }

  Future<bool> get isHealthy async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 1));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> projects() async {
    final response = await _get('/projects');
    if (response == null) return;
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final projects = payload['projects'] as List<dynamic>? ?? const [];
    for (final project in projects) {
      final map = project as Map<String, dynamic>;
      final platforms = (map['platforms'] as List<dynamic>? ?? const [])
          .join(',');
      stdout.writeln('${map['projectId']}\t${map['name']}\t$platforms');
    }
  }

  Future<void> deploy(List<String> arguments) async {
    var platform = 'ios';
    var force = false;
    var wait = false;
    final projectIds = <String>[];
    for (final argument in arguments) {
      switch (argument) {
        case '--ios':
          platform = 'ios';
        case '--macos':
          platform = 'macos';
        case '--force':
          force = true;
        case '--wait':
          wait = true;
        default:
          if (argument.startsWith('-')) {
            stderr.writeln('Unknown flag: $argument');
            exitCode = 1;
            return;
          }
          projectIds.add(argument);
      }
    }
    if (projectIds.isEmpty) {
      stderr.writeln(
        'Usage: workbench deploy <projectId> [projectId ...] '
        '[--ios|--macos] [--force] [--wait]',
      );
      exitCode = 1;
      return;
    }

    final jobIds = <String>[];
    for (final projectId in projectIds) {
      final job = await _enqueueDeploy(
        projectId: projectId,
        platform: platform,
        force: force,
      );
      if (job == null) {
        exitCode = 1;
        continue;
      }
      _printJob(job);
      jobIds.add(job['jobId'] as String);
    }
    if (!wait) return;
    for (final jobId in jobIds) {
      await _waitForJob(jobId);
    }
  }

  Future<Map<String, dynamic>?> _enqueueDeploy({
    required String projectId,
    required String platform,
    required bool force,
  }) async {
    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_baseUrl/deploy'),
        headers: _headers,
        body: jsonEncode({
          'projectId': projectId,
          'platform': platform,
          'force': force,
        }),
      );
    } on SocketException {
      stderr.writeln(_daemonDownHint);
      return null;
    }

    if (response.statusCode == 409) {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final jobJson = payload['job'];
      if (jobJson is Map<String, dynamic>) return jobJson;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _printHttpError(response);
      return null;
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> job(List<String> arguments) async {
    final jobId = arguments.isEmpty ? null : arguments.first;
    if (jobId == null) {
      final response = await _get('/jobs/active', notFoundOk: true);
      if (response == null) return;
      if (response.statusCode == 404) {
        stdout.writeln('no active job');
        return;
      }
      _printJob(jsonDecode(response.body) as Map<String, dynamic>);
      return;
    }
    final response = await _get('/jobs/$jobId');
    if (response == null) return;
    _printJob(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> daemon(List<String> arguments) async {
    if (arguments.isEmpty) {
      stderr.writeln(
        'Usage: workbench daemon start|stop|restart|status|install',
      );
      exitCode = 1;
      return;
    }
    switch (arguments.first) {
      case 'install':
        _installLaunchAgent();
      case 'start':
        await _startDaemon();
      case 'stop':
        await _stopDaemon();
      case 'restart':
        await _restartDaemon();
      case 'status':
        await _daemonStatus();
      default:
        stderr.writeln('Unknown daemon command: ${arguments.first}');
        exitCode = 1;
    }
  }

  Future<void> _daemonStatus() async {
    if (!await isHealthy) {
      stdout.writeln('not running');
      exitCode = 1;
      return;
    }
    final response = await _get('/health');
    if (response == null) return;
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final restartAfterQueue = payload['restartAfterQueue'] == true;
      stdout.writeln(
        restartAfterQueue
            ? 'running $_baseUrl (restart after queue)'
            : 'running $_baseUrl',
      );
    } catch (_) {
      stdout.writeln('running $_baseUrl');
    }
  }

  Future<void> _restartDaemon() async {
    if (!await isHealthy) {
      await _startDaemon();
      return;
    }
    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_baseUrl/daemon/restart'),
        headers: _headers,
      );
    } on SocketException {
      stderr.writeln(_daemonDownHint);
      exitCode = 1;
      return;
    }
    if (response.statusCode == 404) {
      stdout.writeln(
        'This daemon build cannot enqueue a restart. '
        'Waiting until the deploy queue is idle, then restarting…',
      );
      if (!await _waitUntilDeployQueueIdle()) {
        exitCode = 1;
        return;
      }
      await _stopDaemon();
      await _startDaemon();
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _printHttpError(response);
      exitCode = 1;
      return;
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (payload['beganImmediately'] == true) {
      stdout.writeln('Daemon restarting now');
      await _waitUntilUnhealthy();
      await _startDaemon();
      return;
    }
    stdout.writeln(
      'Daemon restart scheduled after the deploy queue drains '
      '(waiting=${payload['waitingJobCount']} '
      'active=${payload['activeJobId'] ?? 'none'})',
    );
  }

  Future<bool> _waitUntilDeployQueueIdle() async {
    while (true) {
      final queueResponse = await _get('/deploy/queue');
      if (queueResponse == null) return false;
      final queuePayload =
          jsonDecode(queueResponse.body) as Map<String, dynamic>;
      final waitingJobs = queuePayload['jobs'] as List<dynamic>? ?? const [];
      final activeResponse = await _get('/jobs/active', notFoundOk: true);
      if (activeResponse == null) return false;
      if (waitingJobs.isEmpty && activeResponse.statusCode == 404) return true;
      stdout.writeln(
        'waiting for idle (queue=${waitingJobs.length} '
        'active=${activeResponse.statusCode == 404 ? 'no' : 'yes'})',
      );
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  Future<void> _waitUntilUnhealthy() async {
    for (var attempt = 0; attempt < 40; attempt++) {
      if (!await isHealthy) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<http.Response?> _get(String path, {bool notFoundOk = false}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl$path'),
        headers: _headers,
      );
      if (notFoundOk && response.statusCode == 404) return response;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _printHttpError(response);
        exitCode = 1;
        return null;
      }
      return response;
    } on SocketException {
      stderr.writeln(_daemonDownHint);
      exitCode = 1;
      return null;
    }
  }

  void _printHttpError(http.Response response) {
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final error = payload['error'] as String?;
      if (error != null && error.isNotEmpty) {
        stderr.writeln(error);
        return;
      }
    } catch (_) {}
    stderr.writeln('HTTP ${response.statusCode}');
  }

  void _printJob(Map<String, dynamic> job) {
    stdout.writeln(
      '${job['jobId']}\t${job['projectId']}\t${job['platform']}\t${job['status']}',
    );
    final checklist = job['checklist'] as List<dynamic>? ?? const [];
    for (final item in checklist) {
      final step = item as Map<String, dynamic>;
      if (step['status'] == 'active') {
        stdout.writeln(step['label']);
        break;
      }
    }
  }

  Future<void> _waitForJob(String jobId) async {
    while (true) {
      final response = await _get('/jobs/$jobId');
      if (response == null) return;
      final job = jsonDecode(response.body) as Map<String, dynamic>;
      final status = job['status'] as String? ?? '';
      stdout.writeln(status);
      if (status == 'succeeded' || status == 'failed') {
        final exit = job['exitCode'];
        if (status != 'succeeded') {
          exitCode = exit is int && exit != 0 ? exit : 1;
        }
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  File get _plistFile {
    final home = Platform.environment['HOME'] ?? '';
    return File(
      path.join(home, 'Library', 'LaunchAgents', '$_launchAgentLabel.plist'),
    );
  }

  String get _guiDomain {
    final result = Process.runSync('id', ['-u']);
    return 'gui/${(result.stdout as String).trim()}';
  }

  void _installLaunchAgent() {
    final logs = Directory(path.join(packageRoot.path, '.workbench'));
    logs.createSync(recursive: true);
    final plist =
        '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_launchAgentLabel</string>
  <key>WorkingDirectory</key>
  <string>${packageRoot.path}</string>
  <key>ProgramArguments</key>
  <array>
    <string>$_flutterSdk</string>
    <string>test</string>
    <string>tool/workbench_daemon_harness.dart</string>
    <string>--reporter</string>
    <string>failures-only</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/opt/ruby/bin:/opt/homebrew/share/flutter/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>LANG</key>
    <string>en_US.UTF-8</string>
    <key>LC_ALL</key>
    <string>en_US.UTF-8</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${path.join(packageRoot.path, '.workbench', 'daemon.stdout.log')}</string>
  <key>StandardErrorPath</key>
  <string>${path.join(packageRoot.path, '.workbench', 'daemon.stderr.log')}</string>
</dict>
</plist>
''';
    _plistFile.parent.createSync(recursive: true);
    _plistFile.writeAsStringSync(plist);
    stdout.writeln('Wrote ${_plistFile.path}');
  }

  Future<void> _startDaemon() async {
    if (await isHealthy) {
      stdout.writeln('Workbench daemon already running on $_baseUrl');
      return;
    }
    if (!_plistFile.existsSync()) {
      _installLaunchAgent();
    }
    Process.runSync('launchctl', ['bootout', '$_guiDomain/$_launchAgentLabel']);
    final bootstrap = Process.runSync('launchctl', [
      'bootstrap',
      _guiDomain,
      _plistFile.path,
    ]);
    if (bootstrap.exitCode != 0) {
      final err = (bootstrap.stderr as String).trim();
      if (err.isNotEmpty) stderr.writeln(err);
      stdout.writeln('launchctl bootstrap failed; starting a detached process.');
      await Process.start(_flutterSdk, [
        'test',
        'tool/workbench_daemon_harness.dart',
        '--reporter',
        'failures-only',
      ], workingDirectory: packageRoot.path, mode: ProcessStartMode.detached);
    }
    for (var attempt = 0; attempt < 80; attempt++) {
      if (await isHealthy) {
        stdout.writeln('Workbench daemon listening on $_baseUrl');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    stderr.writeln('Daemon did not become healthy at $_baseUrl');
    exitCode = 1;
  }

  Future<void> _stopDaemon() async {
    Process.runSync('launchctl', ['bootout', '$_guiDomain/$_launchAgentLabel']);
    if (await isHealthy) {
      final lsof = Process.runSync('lsof', [
        '-nP',
        '-iTCP:$port',
        '-sTCP:LISTEN',
        '-t',
      ]);
      for (final line in (lsof.stdout as String).split('\n')) {
        final listenerPid = int.tryParse(line.trim());
        if (listenerPid == null) continue;
        final command = Process.runSync('ps', [
          '-o',
          'command=',
          '-p',
          '$listenerPid',
        ]);
        final commandLine = (command.stdout as String).trim();
        if (!commandLine.contains('workbench_daemon_harness.dart')) continue;
        Process.runSync('kill', ['$listenerPid']);
      }
    }
    if (await isHealthy) {
      stderr.writeln(
        'Daemon still listening on $_baseUrl. '
        'Stop the process that owns port $port.',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln('Workbench daemon stopped');
  }

  void _usage() {
    stdout.writeln('''
Usage: workbench <command>

  health
  projects
  deploy <projectId> [projectId ...] [--ios|--macos] [--force] [--wait]
  job [jobId]
  daemon start|stop|restart|status|install
''');
  }

  static Directory _packageRoot() {
    var directory = Directory.current;
    for (var i = 0; i < 6; i++) {
      final pubspec = File(path.join(directory.path, 'pubspec.yaml'));
      if (pubspec.existsSync() &&
          pubspec.readAsStringSync().contains(
            RegExp(r'^name:\s*ethan_workbench\s*$', multiLine: true),
          )) {
        return directory;
      }
      directory = directory.parent;
    }
    return Directory.current;
  }

  static Map<String, String> _loadEnvFile(Directory packageRoot) {
    final envFile = File(path.join(packageRoot.path, '.env'));
    if (!envFile.existsSync()) return {};
    final values = <String, String>{};
    for (final line in envFile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      var value = trimmed.substring(eq + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      values[trimmed.substring(0, eq).trim()] = value;
    }
    return values;
  }
}

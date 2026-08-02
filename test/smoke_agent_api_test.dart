import 'dart:convert';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:ethan_workbench/agent/agent_config.dart';
import 'package:ethan_workbench/agent/deploy_agent.dart';
import 'package:shelf/shelf.dart';

void main() {
  test('agent API requires pairing for projects', () async {
    final fixtureRoot = Directory.systemTemp.createTempSync(
      'ethan_workbench_smoke_',
    );
    addTearDown(() => fixtureRoot.deleteSync(recursive: true));

    final sampleAppDirectory = Directory(
      path.join(fixtureRoot.path, 'sample_app'),
    )..createSync();
    File(
      path.join(sampleAppDirectory.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: sample_app\n');
    Directory(path.join(sampleAppDirectory.path, 'ios')).createSync();

    final deployRbPath = path.join(fixtureRoot.path, 'deploy.rb');
    File(deployRbPath).writeAsStringSync("# fixture\n");

    dotenv.loadFromString(
      envString:
          '''
AGENT_HOST=localhost
AGENT_PORT=18787
FLUTTER_ROOT=${fixtureRoot.path}
DEPLOY_RB=$deployRbPath
''',
    );

    final config = AgentConfig(
      port: 18787,
      flutterRoots: [fixtureRoot.path],
      deployRbPath: deployRbPath,
    );

    final agent = DeployAgent(config: config);
    addTearDown(agent.dispose);
    final handler = agent.buildHandler();
    final pin = agent.pairingAuth.pin;

    final health = await handler(
      Request('GET', Uri.parse('http://localhost/health')),
    );
    expect(health.statusCode, 200);

    final unauthorized = await handler(
      Request('GET', Uri.parse('http://localhost/projects')),
    );
    expect(unauthorized.statusCode, 401);

    final badPin = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/pair'),
        body: jsonEncode({'pin': '000000'}),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    expect(badPin.statusCode, 403);

    final pair = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/pair'),
        body: jsonEncode({'pin': pin}),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    expect(pair.statusCode, 200);
    final pairPayload =
        jsonDecode(await pair.readAsString()) as Map<String, dynamic>;
    final token = pairPayload['token'] as String;
    expect(token, isNotEmpty);

    final projectsResponse = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/projects'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    expect(projectsResponse.statusCode, 200);
    final payload =
        jsonDecode(await projectsResponse.readAsString())
            as Map<String, dynamic>;
    final projects = payload['projects'] as List<dynamic>;
    expect(
      projects.any((project) => project['projectId'] == 'sample_app'),
      isTrue,
    );
  });
}

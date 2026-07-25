import 'dart:convert';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:phone_deploy/agent/agent_config.dart';
import 'package:phone_deploy/agent/deploy_agent_server.dart';
import 'package:shelf/shelf.dart';

void main() {
  test('agent API health and project scan', () async {
    final fixtureRoot = Directory.systemTemp.createTempSync('phone_deploy_smoke_');
    addTearDown(() => fixtureRoot.deleteSync(recursive: true));

    final sampleAppDirectory = Directory(path.join(fixtureRoot.path, 'sample_app'))
      ..createSync();
    File(path.join(sampleAppDirectory.path, 'pubspec.yaml'))
        .writeAsStringSync('name: sample_app\n');
    Directory(path.join(sampleAppDirectory.path, 'ios')).createSync();

    final deployRbPath = path.join(fixtureRoot.path, 'deploy.rb');
    File(deployRbPath).writeAsStringSync("# fixture\n");

    dotenv.loadFromString(
      envString: '''
PHONE_DEPLOY_AGENT_HOST=localhost
PHONE_DEPLOY_AGENT_PORT=18787
PHONE_DEPLOY_FLUTTER_ROOT=${fixtureRoot.path}
PHONE_DEPLOY_DEPLOY_RB=$deployRbPath
''',
    );

    final config = AgentConfig(
      port: 18787,
      flutterRoots: [fixtureRoot.path],
      deployRbPath: deployRbPath,
    );

    expect(File(config.deployRbPath).existsSync(), isTrue);

    final server = DeployAgentServer(config: config);
    addTearDown(server.dispose);
    final handler = server.buildHandler();

    final health = await handler(
      Request('GET', Uri.parse('http://localhost/health')),
    );
    expect(health.statusCode, 200);

    final projectsResponse = await handler(
      Request('GET', Uri.parse('http://localhost/projects')),
    );
    expect(projectsResponse.statusCode, 200);
    final payload =
        jsonDecode(await projectsResponse.readAsString()) as Map<String, dynamic>;
    final projects = payload['projects'] as List<dynamic>;
    expect(projects, isNotEmpty);
    expect(
      projects.any((project) => project['projectId'] == 'sample_app'),
      isTrue,
    );
  });
}

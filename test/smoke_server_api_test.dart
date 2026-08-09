import 'dart:convert';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:ethan_workbench/server/deploy_server.dart';
import 'package:ethan_workbench/server/server_config.dart';
import 'package:shelf/shelf.dart';

void main() {
  test('deploy server API requires shared password for projects', () async {
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
SERVER_HOST=localhost
SERVER_PORT=18787
SERVER_PASSWORD=test-password
FLUTTER_ROOT=${fixtureRoot.path}
DEPLOY_RB=$deployRbPath
''',
    );

    final config = ServerConfig(
      port: 18787,
      flutterRoots: [fixtureRoot.path],
      deployRbPath: deployRbPath,
    );

    final server = DeployServer(config: config);
    addTearDown(server.dispose);
    final handler = server.buildHandler();

    final health = await handler(
      Request('GET', Uri.parse('http://localhost/health')),
    );
    expect(health.statusCode, 200);

    final unauthorized = await handler(
      Request('GET', Uri.parse('http://localhost/projects')),
    );
    expect(unauthorized.statusCode, 401);

    final wrongPassword = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/projects'),
        headers: {'Authorization': 'Bearer wrong'},
      ),
    );
    expect(wrongPassword.statusCode, 401);

    final projectsResponse = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/projects'),
        headers: {'Authorization': 'Bearer test-password'},
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

  test('deploy server fails closed when SERVER_PASSWORD is empty', () async {
    final fixtureRoot = Directory.systemTemp.createTempSync(
      'ethan_workbench_smoke_empty_pw_',
    );
    addTearDown(() => fixtureRoot.deleteSync(recursive: true));
    final deployRbPath = path.join(fixtureRoot.path, 'deploy.rb');
    File(deployRbPath).writeAsStringSync("# fixture\n");

    dotenv.loadFromString(
      envString:
          '''
SERVER_HOST=localhost
SERVER_PORT=18788
SERVER_PASSWORD=
FLUTTER_ROOT=${fixtureRoot.path}
DEPLOY_RB=$deployRbPath
''',
    );

    final server = DeployServer(
      config: ServerConfig(
        port: 18788,
        flutterRoots: [fixtureRoot.path],
        deployRbPath: deployRbPath,
      ),
    );
    addTearDown(server.dispose);
    final handler = server.buildHandler();

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/projects'),
        headers: {'Authorization': 'Bearer anything'},
      ),
    );
    expect(response.statusCode, 401);
    final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(body['error'], contains('SERVER_PASSWORD'));
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_pipeline.dart';
import 'deploy_http_sse.dart';
import 'json_http.dart';

const _log = ELogger('ServerJobEvents');

class DeployHttpRoutes({required final DeployPipeline deployPipeline}) {
  void mount(Router router) {
    router
      ..get('/projects', _listProjects)
      ..post('/projects/evaluate-changes', _evaluateSourceChanges)
      ..post('/deploy', _startDeploy)
      ..get('/deploy/queue', _listDeployQueue)
      ..delete('/deploy/queue/<jobId>', _cancelQueuedDeploy)
      ..patch('/deploy/queue/<jobId>', _reorderQueuedDeploy)
      ..get('/jobs/history', _listHistory)
      ..get('/jobs/active', _activeJob)
      ..get('/jobs/events', _streamJobEvents)
      ..get('/jobs/<jobId>', _getJob)
      ..get('/jobs/<jobId>/log', _streamLog);
  }

  Future<Response> _listProjects(Request request) async {
    final projects = await deployPipeline.listProjects();
    return jsonOk({
      'projects': projects.map((project) => project.toJson()).toList(),
    });
  }

  Future<Response> _evaluateSourceChanges(Request request) async {
    final projects = await deployPipeline.evaluateSourceChanges();
    return jsonOk({
      'projects': projects.map((project) => project.toJson()).toList(),
    });
  }

  Future<Response> _startDeploy(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final projectId = body['projectId'] as String?;
      if (projectId == null || projectId.isEmpty) {
        return jsonError('projectId is required', status: 400);
      }
      final force = body['force'] as bool? ?? false;
      final platformName =
          body['platform'] as String? ?? DeployPlatform.ios.name;
      if (platformName != DeployPlatform.ios.name &&
          platformName != DeployPlatform.macos.name) {
        return jsonError('platform must be ios or macos', status: 400);
      }
      final job = await deployPipeline.startDeploy(
        projectId: projectId,
        platform: DeployPlatform.fromName(platformName),
        force: force,
      );
      return jsonOk(job.toJson());
    } on DeployAlreadyQueued catch (error) {
      return jsonError(
        error.toString(),
        status: 409,
        extra: {'job': error.job.toJson(), 'alreadyQueued': true},
      );
    } on UnknownProject catch (error) {
      return jsonError(error.toString(), status: 404);
    } on UnsupportedDeployPlatform catch (error) {
      return jsonError(error.toString(), status: 400);
    } on DeployScriptMissing catch (error) {
      return jsonError(error.toString(), status: 500);
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }

  Future<Response> _listDeployQueue(Request request) async {
    return jsonOk({
      'jobs': deployPipeline.waitingQueue.map((job) => job.toJson()).toList(),
    });
  }

  Future<Response> _cancelQueuedDeploy(Request request, String jobId) async {
    if (!deployPipeline.cancelWaiting(jobId)) {
      return jsonError('Queued job not found', status: 404);
    }
    return jsonOk({'ok': true});
  }

  Future<Response> _reorderQueuedDeploy(Request request, String jobId) async {
    final Object decoded;
    try {
      decoded = jsonDecode(await request.readAsString());
    } on FormatException {
      return jsonError('Invalid JSON', status: 400);
    }
    if (decoded is! Map<String, dynamic>) {
      return jsonError('JSON object required', status: 400);
    }
    final toIndex = switch (decoded['toIndex']) {
      final int index => index,
      final num index => index.toInt(),
      _ => null,
    };
    if (toIndex == null) {
      return jsonError('toIndex is required', status: 400);
    }
    if (!deployPipeline.waitingQueue.any((job) => job.jobId == jobId)) {
      return jsonError('Queued job not found', status: 404);
    }
    if (!deployPipeline.moveWaitingJob(jobId: jobId, toIndex: toIndex)) {
      return jsonError('toIndex is out of range', status: 400);
    }
    return jsonOk({'ok': true});
  }

  Future<Response> _activeJob(Request request) async {
    final job = deployPipeline.activeJob;
    if (job == null || job.status.isTerminal) {
      return jsonError('No active job', status: 404);
    }
    return jsonOk(job.toJson());
  }

  Future<Response> _listHistory(Request request) async {
    final runs = await deployPipeline.listRecentRuns();
    return jsonOk({'runs': runs.map((run) => run.toJson()).toList()});
  }

  Future<Response> _getJob(Request request, String jobId) async {
    try {
      final job = await deployPipeline.fetchJob(jobId);
      return jsonOk(job.toJson());
    } on DeployJobNotFound {
      return jsonError('Job not found', status: 404);
    }
  }

  FutureOr<Response> _streamJobEvents(Request request) {
    final controller = StreamController<List<int>>();
    var emitCount = 0;
    String? lastStatus;
    String? lastChecklist;

    void emitJob(DeployJob job) {
      if (controller.isClosed) return;
      emitCount += 1;
      final checklistSignature = job.checklist
          .map((item) => '${item.id}:${item.status.name}')
          .join(',');
      final noteworthy =
          job.status.name != lastStatus ||
          checklistSignature != lastChecklist ||
          emitCount == 1 ||
          emitCount % 25 == 0;
      if (noteworthy) {
        _log.log('SSE emit #$emitCount ${job.debugSummary}');
        lastStatus = job.status.name;
        lastChecklist = checklistSignature;
      }
      controller.add(utf8.encode('data: ${jsonEncode(job.toJson())}\n\n'));
    }

    void emitQueue(List<DeployJob> jobs) {
      if (controller.isClosed) return;
      controller.add(
        utf8.encode(
          'data: ${jsonEncode({'type': 'queue', 'jobs': jobs.map((job) => job.toJson()).toList()})}\n\n',
        ),
      );
    }

    final activeJob = deployPipeline.activeJob;
    _log.log(
      'SSE subscriber open active='
      '${activeJob?.debugSummary ?? 'none'}',
    );
    if (activeJob != null && !activeJob.status.isTerminal) {
      emitJob(activeJob);
    }
    emitQueue(deployPipeline.waitingQueue);

    final jobSubscription = deployPipeline.jobUpdates.listen(
      emitJob,
      onError: (Object error, StackTrace stackTrace) {
        _log.warn('SSE jobUpdates error', error, stackTrace);
        controller.addError(error, stackTrace);
      },
      onDone: () {
        _log.log('SSE jobUpdates done emits=$emitCount');
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
      },
    );
    final queueSubscription = deployPipeline.queueUpdates.listen(emitQueue);

    controller.onCancel = () {
      _log.log('SSE subscriber cancel emits=$emitCount');
      unawaited(jobSubscription.cancel());
      unawaited(queueSubscription.cancel());
    };

    return Response.ok(
      controller.stream,
      headers: DeployHttpSse.headers,
      context: DeployHttpSse.context,
    );
  }

  FutureOr<Response> _streamLog(Request request, String jobId) {
    final job = deployPipeline.activeJob;
    if (job == null || job.jobId != jobId) {
      return jsonError('Job not found', status: 404);
    }

    final logStream = deployPipeline.watchLog(jobId);
    final transformed = logStream.map((chunk) {
      final escaped = chunk
          .replaceAll('\r', '')
          .split('\n')
          .map((line) => 'data: $line')
          .join('\n');
      return utf8.encode('$escaped\n\n');
    });

    return Response.ok(
      transformed,
      headers: DeployHttpSse.headers,
      context: DeployHttpSse.context,
    );
  }
}

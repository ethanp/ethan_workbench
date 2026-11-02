import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// The Dart VM of an app under `flutter run`, reached over the VM service
/// websocket.
///
/// Plain HTTP calls to the same URI cannot evaluate expressions: `flutter run`
/// offers its expression compiler only to websocket clients.
class RunningAppVm._(final VmService _vmService) {
  /// The library that defines `appLogBuffer`, so the default eval target can
  /// read every app's info-level log.
  static const appLogBufferLibrarySuffix =
      'ethan_utils/src/app_log_buffer.dart';

  /// [vmServiceUri] is the `http://…/` URI `flutter run` prints.
  static Future<RunningAppVm> connect(String vmServiceUri) async {
    final httpUri = Uri.parse(vmServiceUri);
    final pathWithSlash = httpUri.path.endsWith('/')
        ? httpUri.path
        : '${httpUri.path}/';
    final websocketUri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      path: '${pathWithSlash}ws',
    );
    return RunningAppVm._(await vmServiceConnectUri(websocketUri.toString()));
  }

  /// Kills isolates that started before the newest `main` isolate. A hot
  /// restart replaces `main`, but an isolate the old run spawned (PowerSync's
  /// `Sync <db path>`) keeps running. Returns the killed isolates' names.
  Future<List<String>> killIsolatesLeftFromBeforeRestart() async {
    final List<Isolate> isolates = await _allIsolates();
    final mainStartTimes = [
      for (final isolate in isolates)
        if (isolate.name == 'main') isolate.startTime ?? 0,
    ];
    if (mainStartTimes.isEmpty) return const [];
    final int newestMainStart = mainStartTimes.reduce(
      (latest, startTime) => startTime > latest ? startTime : latest,
    );
    final killedNames = <String>[];
    for (final isolate in isolates) {
      if ((isolate.startTime ?? newestMainStart) >= newestMainStart) continue;
      await _vmService.kill(isolate.id!);
      killedNames.add(isolate.name ?? isolate.id!);
    }
    return killedNames;
  }

  /// Evaluates [expression] in the newest `main` isolate, in the scope of the
  /// library whose URI ends with [librarySuffix], and returns its `toString()`
  /// in full.
  Future<String> evaluateInMainIsolate(
    String expression, {
    String librarySuffix = appLogBufferLibrarySuffix,
  }) async {
    final Isolate mainIsolate = await _newestMainIsolate();
    final LibraryRef? library = mainIsolate.libraries
        ?.where((library) => library.uri?.endsWith(librarySuffix) ?? false)
        .firstOrNull;
    if (library == null) {
      throw StateError('No loaded library ends with $librarySuffix');
    }
    final Response evaluation = await _vmService.evaluate(
      mainIsolate.id!,
      library.id!,
      '($expression).toString()',
    );
    if (evaluation is ErrorRef) {
      throw StateError(evaluation.message ?? 'Evaluation failed');
    }
    return _fullString(mainIsolate.id!, evaluation as InstanceRef);
  }

  /// `dart:developer` log records as the app writes them, message text only.
  /// `ELogger` info and fine lines go there, never to `flutter run` output.
  /// The stream survives hot restarts; it ends when the VM goes away, and
  /// cancelling it never waits for another log record.
  Stream<String> appLogLines() async* {
    await _vmService.streamListen(EventStreams.kLogging);
    yield* _loggingEventsUntilDisconnected()
        .where(
          (event) =>
              event.logRecord?.message != null && event.isolate?.id != null,
        )
        .asyncMap(
          (event) => _fullString(event.isolate!.id!, event.logRecord!.message!),
        );
  }

  /// [VmService.onLoggingEvent] stays open after the connection closes, so an
  /// `await for` over it hangs, and so does cancelling that loop.
  Stream<Event> _loggingEventsUntilDisconnected() {
    final loggingEvents = StreamController<Event>();
    loggingEvents.onListen = () {
      final StreamSubscription<Event> loggingEventSubscription = _vmService
          .onLoggingEvent
          .listen(loggingEvents.add);
      loggingEvents.onCancel = loggingEventSubscription.cancel;
      unawaited(_vmService.onDone.then((_) => loggingEvents.close()));
    };
    return loggingEvents.stream;
  }

  /// A string instance in full, even past the VM's inline truncation limit.
  Future<String> _fullString(String isolateId, InstanceRef instance) async {
    if (instance.valueAsStringIsTruncated != true) {
      return instance.valueAsString ?? '';
    }
    final fullString = await _vmService.getObject(
      isolateId,
      instance.id!,
      count: instance.length,
    ) as Instance;
    return fullString.valueAsString ?? '';
  }

  Future<void> dispose() => _vmService.dispose();

  Future<Isolate> _newestMainIsolate() async {
    final List<Isolate> mainIsolates = [
      for (final isolate in await _allIsolates())
        if (isolate.name == 'main') isolate,
    ];
    if (mainIsolates.isEmpty) throw StateError('No main isolate is running');
    return mainIsolates.reduce(
      (newest, isolate) =>
          (isolate.startTime ?? 0) > (newest.startTime ?? 0) ? isolate : newest,
    );
  }

  /// Isolates that exit while being listed are left out.
  Future<List<Isolate>> _allIsolates() async {
    final VM vm = await _vmService.getVM();
    final List<Isolate?> isolates = await Future.wait(
      (vm.isolates ?? const <IsolateRef>[]).mapL(
        (isolateRef) => _isolateStillRunning(isolateRef.id!),
      ),
    );
    return isolates.nonNulls.toList();
  }

  Future<Isolate?> _isolateStillRunning(String isolateId) async {
    try {
      return await _vmService.getIsolate(isolateId);
    } on SentinelException {
      return null;
    }
  }
}

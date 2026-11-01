import '../projects/workbench_project.dart';
import 'flutter_run_device.dart';
import 'local_run_state.dart';

/// Shared surface for Mac in-process and phone-remote local `flutter run`.
abstract class LocalRunControls() {
  LocalRunState get state;
  Stream<LocalRunState> get updates;
  bool get isActive;

  Future<void> start(
    WorkbenchProject project, {
    required FlutterRunDevice device,
  });

  Future<void> stop();
  Future<void> hotReload();
  Future<void> hotRestart();
  Future<void> fullRestart();

  /// Streams the app's info-level log lines into the run log while [enabled].
  /// See [LocalRunState.infoLogs].
  Future<void> setInfoLogs(bool enabled);

  /// Evaluates a Dart [expression] in the running app and returns its
  /// `toString()`. [librarySuffix] picks the library scope; the default is
  /// the one that defines `appLogBuffer`.
  Future<String> evaluateInApp(String expression, {String? librarySuffix});
}

import '../projects/deployable_project.dart';
import 'flutter_run_device.dart';
import 'local_run_state.dart';

/// Shared surface for Mac in-process and phone-remote local `flutter run`.
abstract class LocalRunControls {
  LocalRunState get state;
  Stream<LocalRunState> get updates;
  bool get isActive;

  Future<void> start(
    DeployableProject project, {
    required FlutterRunDevice device,
  });

  Future<void> stop();
  Future<void> hotReload();
  Future<void> hotRestart();
  Future<void> fullRestart();
}

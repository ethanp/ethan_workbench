import 'package:ethan_workbench/run/local_flutter_run.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterRunOutput', () {
    test('looksReady matches flutter run banners', () {
      expect(
        FlutterRunOutput.looksReady('Flutter run key commands'),
        isTrue,
      );
      expect(FlutterRunOutput.looksReady('building…'), isFalse);
    });

    test('vmServiceUriFrom extracts http URI', () {
      const line =
          'A Dart VM Service on macOS is available at: '
          'http://127.0.0.1:54321/abc=/';
      expect(
        FlutterRunOutput.vmServiceUriFrom(line),
        'http://127.0.0.1:54321/abc=/',
      );
    });

    test('vmServiceUriFrom strips trailing punctuation', () {
      const line =
          'A Dart VM Service on macOS is available at: '
          'http://127.0.0.1:54321/abc=/.';
      expect(
        FlutterRunOutput.vmServiceUriFrom(line),
        'http://127.0.0.1:54321/abc=/',
      );
    });
  });
}

import 'package:ethan_workbench/run/local_flutter_run.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterRunOutput', () {
    test('looksReady matches flutter run banners', () {
      expect(FlutterRunOutput.looksReady('Flutter run key commands'), isTrue);
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

    test('exceptionFrom extracts high-signal layout dump fields', () {
      const dump = '''
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═══════════════════════════════════
The following assertion was thrown during layout:
RenderBox was not laid out.

The relevant error-causing widget was:
  IntrinsicWidth
  IntrinsicWidth:file:///Users/Ethan/code/my-code/Active/Flutter/ethan_ui/lib/chrome/e_side_panel.dart:43:12

The following RenderObject was being processed when the exception was fired: RenderIntrinsicWidth#c35e0 relayoutBoundary=up5 NEEDS-LAYOUT NEEDS-PAINT:
  creator: IntrinsicWidth ← ESidePanel ← LabelsPane ← Row ← Expanded ← Column ← ConstrainedBox ←
    LayoutBuilder ← Align ← Stack ← DecoratedBox ← KeyedSubtree-[GlobalKey#16f1d] ← ⋯
  parentData: offset=Offset(0.0, 0.0); flex=null; fit=null (can use size)
  constraints: BoxConstraints(0.0<=w<=Infinity, 0.0<=h<=869.0)
  size: MISSING
  stepWidth: null
  stepHeight: null
This RenderObject had the following descendants (showing up to depth 5):
    child: RenderDecoratedBox#6bcc1 NEEDS-LAYOUT
════════════════════════════════════════════════════════════════════════════

Another exception was thrown: RenderBox was not laid out: RenderIntrinsicWidth#c35e0 relayoutBoundary=up5 NEEDS-PAINT
''';

      final exception = FlutterRunOutput.exceptionFrom(dump);
      expect(exception, isNotNull);
      expect(exception!.library, 'RENDERING LIBRARY');
      expect(exception.thrownDuring, 'during layout');
      expect(exception.assertion, 'RenderBox was not laid out.');
      expect(exception.widget, 'IntrinsicWidth');
      expect(
        exception.fileUri,
        'file:///Users/Ethan/code/my-code/Active/Flutter/ethan_ui/lib/chrome/e_side_panel.dart:43:12',
      );
      expect(
        exception.displayLocation,
        'ethan_ui/lib/chrome/e_side_panel.dart:43:12',
      );
      expect(
        exception.creatorChain,
        'IntrinsicWidth ← ESidePanel ← LabelsPane ← Row ← Expanded ← '
        'Column ← ConstrainedBox ← LayoutBuilder',
      );
      expect(
        exception.constraints,
        'BoxConstraints(0.0<=w<=Infinity, 0.0<=h<=869.0)',
      );
      expect(exception.size, 'MISSING');
      expect(
        exception.followOn,
        startsWith('RenderBox was not laid out: RenderIntrinsicWidth#c35e0'),
      );

      final prompt = exception.promptText;
      expect(prompt, contains('Flutter exception in RENDERING LIBRARY.'));
      expect(prompt, contains('IntrinsicWidth:file:///Users/Ethan/'));
      expect(prompt, contains('creator: IntrinsicWidth ← ESidePanel'));
      expect(prompt, contains('constraints: BoxConstraints(0.0<=w<=Infinity'));
      expect(prompt, contains('size: MISSING'));
      expect(prompt, contains('Another exception was thrown:'));
    });

    test('exceptionFrom extracts assertion and app frame from gesture dumps', () {
      const dump = '''
══╡ EXCEPTION CAUGHT BY GESTURE LIBRARY ╞═══════════════════════════════════════════════════════════
The following assertion was thrown while dispatching a pointer event:
setState() called after dispose(): ZoomPanViewState#939e6(lifecycle state: defunct, not mounted)
This error happens if you call setState() on a State object for a widget that no longer appears in
the widget tree.

When the exception was thrown, this was the stack:
#0      State.setState.<anonymous closure> (package:flutter/src/widgets/framework.dart:1163:9)
#1      State.setState (package:flutter/src/widgets/framework.dart:1200:6)
#2      ZoomPanViewState._forgetPointerContact (package:viant_core/widgets/zoom_pan_view.dart:215:5)
#3      RenderPointerListener.handleEvent (package:flutter/src/rendering/proxy_box.dart:3270:40)

Event:
  PointerUpEvent#90a75(position: Offset(575.7, 1267.5))
Target:
  RenderPointerListener#72fe6 DISPOSED
════════════════════════════════════════════════════════════════════════════════════════════════════
''';

      final exception = FlutterRunOutput.exceptionFrom(dump);
      expect(exception, isNotNull);
      expect(exception!.library, 'GESTURE LIBRARY');
      expect(exception.thrownDuring, 'while dispatching a pointer event');
      expect(
        exception.assertion,
        'setState() called after dispose(): ZoomPanViewState#939e6(lifecycle state: defunct, not mounted)',
      );
      expect(exception.appFrameSymbol, 'ZoomPanViewState._forgetPointerContact');
      expect(
        exception.packageUri,
        'package:viant_core/widgets/zoom_pan_view.dart:215:5',
      );
      expect(
        exception.displayLocation,
        'viant_core/widgets/zoom_pan_view.dart:215:5',
      );
      expect(
        exception.event,
        'PointerUpEvent#90a75(position: Offset(575.7, 1267.5))',
      );
      expect(exception.target, 'RenderPointerListener#72fe6 DISPOSED');

      final prompt = exception.promptText;
      expect(prompt, contains('Flutter exception in GESTURE LIBRARY.'));
      expect(
        prompt,
        contains('The following assertion was thrown while dispatching a pointer event:'),
      );
      expect(prompt, contains('setState() called after dispose()'));
      expect(prompt, contains('ZoomPanViewState._forgetPointerContact'));
      expect(
        prompt,
        contains('package:viant_core/widgets/zoom_pan_view.dart:215:5'),
      );
      expect(prompt, contains('Event: PointerUpEvent#90a75'));
      expect(prompt, contains('Target: RenderPointerListener#72fe6 DISPOSED'));
    });

    test('exceptionFrom returns null when log has no dump', () {
      expect(
        FlutterRunOutput.exceptionFrom('Flutter run key commands'),
        isNull,
      );
    });

    test('exceptionFrom ignores dumps before hot restart completion', () {
      const log = '''
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═══════════════════════════════════
The relevant error-causing widget was:
  OldWidget
  OldWidget:file:///tmp/old.dart:1:1
════════════════════════════════════════════════════════════════════════════
Performing hot restart...
Restarted application in 1,035ms.

══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═════════════════════════════════════
The relevant error-causing widget was:
  NewWidget
  NewWidget:file:///tmp/new.dart:2:2
════════════════════════════════════════════════════════════════════════════
''';

      final exception = FlutterRunOutput.exceptionFrom(log);
      expect(exception, isNotNull);
      expect(exception!.library, 'WIDGETS LIBRARY');
      expect(exception.widget, 'NewWidget');
      expect(exception.fileUri, 'file:///tmp/new.dart:2:2');
    });

    test(
      'exceptionFrom ignores dumps before floor even without restart banner',
      () {
        const dump = '''
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═══════════════════════════════════
The relevant error-causing widget was:
  OldWidget
  OldWidget:file:///tmp/old.dart:1:1
════════════════════════════════════════════════════════════════════════════
''';
        expect(
          FlutterRunOutput.exceptionFrom(dump, floor: dump.length),
          isNull,
        );
      },
    );

    test('exceptionScanStart advances past Restarted application banner', () {
      const log = 'before\nRestarted application in 1,035ms.\nafter\n';
      final start = FlutterRunOutput.exceptionScanStart(log);
      expect(log.substring(start).trimLeft(), startsWith('after'));
    });
  });
}

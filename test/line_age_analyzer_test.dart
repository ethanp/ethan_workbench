import 'package:flutter_test/flutter_test.dart';
import 'package:ethan_workbench/line_age/line_age_analyzer.dart';

void main() {
  test('generated suffixes match the Python tool defaults', () {
    expect(
      LineAgeAnalyzer.generatedSuffixes,
      containsAll([
        '.g.dart',
        '.freezed.dart',
        '.gr.dart',
        '.gen.dart',
        '.mocks.dart',
      ]),
    );
  });

  test('skip directories match the Python tool defaults', () {
    expect(
      LineAgeAnalyzer.skipDirectoryNames,
      containsAll({'.dart_tool', 'build', '.symlinks'}),
    );
  });
}

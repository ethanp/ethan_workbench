/// The analysis was cancelled (the viewer left the screen); not a failure.
class const LineAgeAnalysisCancelled() implements Exception {
  @override
  String toString() => 'Line age analysis cancelled.';
}

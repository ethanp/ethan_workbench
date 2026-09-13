/// High-signal bits from a Flutter framework EXCEPTION CAUGHT dump.
class const FlutterRunException({
  final String? library,
  final String? widget,

  /// Full `file:///…dart:line:col` when present.
  final String? fileUri,

  /// `package:…/file.dart:line:col` from the first non-Flutter stack frame.
  final String? packageUri,
  final String? appFrameSymbol,
  final String? thrownDuring,
  final String? assertion,
  final String? event,
  final String? target,
  final String? creatorChain,
  final String? constraints,
  final String? size,
  final String? followOn,
}) {
  bool get hasSignal =>
      library != null ||
      widget != null ||
      fileUri != null ||
      packageUri != null ||
      appFrameSymbol != null ||
      thrownDuring != null ||
      assertion != null ||
      event != null ||
      target != null ||
      creatorChain != null ||
      constraints != null ||
      size != null ||
      followOn != null;

  /// Short path for on-screen labels (`…/e_side_panel.dart:43:12`).
  String? get displayLocation {
    final package = packageUri;
    if (package != null && package.isNotEmpty) {
      return package.startsWith('package:')
          ? package.substring('package:'.length)
          : package;
    }
    final uri = fileUri;
    if (uri == null || uri.isEmpty) return null;
    final withoutScheme = uri.startsWith('file://')
        ? uri.substring('file://'.length)
        : uri;
    final parts = withoutScheme.split('/');
    if (parts.length <= 3) return withoutScheme;
    // Prefer `packageDir/lib/.../file.dart:line:col` when recognizable.
    final libIndex = parts.lastIndexWhere((part) => part == 'lib');
    if (libIndex > 0 && libIndex < parts.length - 1) {
      return parts.sublist(libIndex - 1).join('/');
    }
    return parts.sublist(parts.length - 3).join('/');
  }

  /// Clipboard payload shaped for pasting into a Cursor chat prompt.
  String get promptText {
    final lines = <String>[];
    if (library != null && library!.isNotEmpty) {
      lines.add('Flutter exception in $library.');
      lines.add('');
    } else {
      lines.add('Flutter exception.');
      lines.add('');
    }
    if (thrownDuring != null && thrownDuring!.isNotEmpty) {
      lines.add('The following assertion was thrown $thrownDuring:');
    }
    if (assertion != null && assertion!.isNotEmpty) {
      lines.add(assertion!);
      lines.add('');
    }
    if (widget != null || fileUri != null) {
      lines.add('The relevant error-causing widget was:');
      if (widget != null) lines.add('  $widget');
      if (widget != null && fileUri != null) {
        lines.add('  $widget:$fileUri');
      } else if (fileUri != null) {
        lines.add('  $fileUri');
      }
      lines.add('');
    }
    if (appFrameSymbol != null || packageUri != null) {
      if (appFrameSymbol != null) lines.add('  $appFrameSymbol');
      if (packageUri != null) lines.add('  $packageUri');
      lines.add('');
    }
    if (event != null && event!.isNotEmpty) {
      lines.add('Event: $event');
    }
    if (target != null && target!.isNotEmpty) {
      lines.add('Target: $target');
    }
    if (creatorChain != null && creatorChain!.isNotEmpty) {
      lines.add('creator: $creatorChain');
    }
    if (constraints != null && constraints!.isNotEmpty) {
      lines.add('constraints: $constraints');
    }
    if (size != null && size!.isNotEmpty) {
      lines.add('size: $size');
    }
    if (followOn != null && followOn!.isNotEmpty) {
      if (lines.isNotEmpty && lines.last.isNotEmpty) lines.add('');
      lines.add('Another exception was thrown: $followOn');
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
  }

  int get richness {
    var score = 0;
    if (library != null) score += 1;
    if (assertion != null) score += 3;
    if (thrownDuring != null) score += 1;
    if (appFrameSymbol != null) score += 2;
    if (packageUri != null) score += 3;
    if (event != null) score += 1;
    if (target != null) score += 1;
    if (widget != null) score += 2;
    if (fileUri != null) score += 3;
    if (creatorChain != null) score += 2;
    if (constraints != null) score += 1;
    if (size != null) score += 1;
    if (followOn != null) score += 1;
    return score;
  }

  bool isRicherThan(FlutterRunException? other) {
    if (other == null) return hasSignal;
    return richness > other.richness;
  }

  factory fromJson(Map<String, dynamic> json) {
    return FlutterRunException(
      library: json['library'] as String?,
      widget: json['widget'] as String?,
      fileUri: json['fileUri'] as String?,
      packageUri: json['packageUri'] as String?,
      appFrameSymbol: json['appFrameSymbol'] as String?,
      thrownDuring: json['thrownDuring'] as String?,
      assertion: json['assertion'] as String?,
      event: json['event'] as String?,
      target: json['target'] as String?,
      creatorChain: json['creatorChain'] as String?,
      constraints: json['constraints'] as String?,
      size: json['size'] as String?,
      followOn: json['followOn'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'library': library,
    'widget': widget,
    'fileUri': fileUri,
    'packageUri': packageUri,
    'appFrameSymbol': appFrameSymbol,
    'thrownDuring': thrownDuring,
    'assertion': assertion,
    'event': event,
    'target': target,
    'creatorChain': creatorChain,
    'constraints': constraints,
    'size': size,
    'followOn': followOn,
  };

  @override
  bool operator ==(Object other) =>
      other is FlutterRunException &&
      other.library == library &&
      other.widget == widget &&
      other.fileUri == fileUri &&
      other.packageUri == packageUri &&
      other.appFrameSymbol == appFrameSymbol &&
      other.thrownDuring == thrownDuring &&
      other.assertion == assertion &&
      other.event == event &&
      other.target == target &&
      other.creatorChain == creatorChain &&
      other.constraints == constraints &&
      other.size == size &&
      other.followOn == followOn;

  @override
  int get hashCode => Object.hash(
    library,
    widget,
    fileUri,
    packageUri,
    appFrameSymbol,
    thrownDuring,
    assertion,
    event,
    target,
    creatorChain,
    constraints,
    size,
    followOn,
  );
}

/// High-signal bits from a Flutter framework EXCEPTION CAUGHT dump.
class FlutterRunException {
  const FlutterRunException({
    this.library,
    this.widget,
    this.fileUri,
    this.creatorChain,
    this.constraints,
    this.size,
    this.followOn,
  });

  final String? library;
  final String? widget;

  /// Full `file:///…dart:line:col` when present.
  final String? fileUri;
  final String? creatorChain;
  final String? constraints;
  final String? size;
  final String? followOn;

  bool get hasSignal =>
      library != null ||
      widget != null ||
      fileUri != null ||
      creatorChain != null ||
      constraints != null ||
      size != null ||
      followOn != null;

  /// Short path for on-screen labels (`…/e_side_panel.dart:43:12`).
  String? get displayLocation {
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

  factory FlutterRunException.fromJson(Map<String, dynamic> json) {
    return FlutterRunException(
      library: json['library'] as String?,
      widget: json['widget'] as String?,
      fileUri: json['fileUri'] as String?,
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
      other.creatorChain == creatorChain &&
      other.constraints == constraints &&
      other.size == size &&
      other.followOn == followOn;

  @override
  int get hashCode => Object.hash(
    library,
    widget,
    fileUri,
    creatorChain,
    constraints,
    size,
    followOn,
  );
}

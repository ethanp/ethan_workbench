import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

/// Finds a list-tile-sized launcher PNG under a Flutter project's AppIcon sets.
abstract final class ProjectAppIcon {
  static const _preferredFileNames = [
    'Icon-App-76x76@2x.png',
    'Icon-App-60x60@3x.png',
    'app_icon_128.png',
    'app_icon_256.png',
    'Icon-App-60x60@2x.png',
    'Icon-App-1024x1024@1x.png',
    'app_icon_1024.png',
  ];

  static Future<Uint8List?> loadPngBytes(String projectPath) async {
    final iconFile = await _resolveIconFile(projectPath);
    if (iconFile == null) return null;
    try {
      return await iconFile.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _resolveIconFile(String projectPath) async {
    for (final relativeIconset in const [
      'ios/Runner/Assets.xcassets/AppIcon.appiconset',
      'macos/Runner/Assets.xcassets/AppIcon.appiconset',
    ]) {
      final iconsetDirectory = Directory(
        path.join(projectPath, relativeIconset),
      );
      if (!await iconsetDirectory.exists()) continue;

      for (final fileName in _preferredFileNames) {
        final candidate = File(path.join(iconsetDirectory.path, fileName));
        if (await candidate.exists()) return candidate;
      }

      await for (final entity in iconsetDirectory.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
          return entity;
        }
      }
    }
    return null;
  }
}

import 'dart:ffi';

import 'package:powersync/powersync.dart';
import 'package:powersync/sqlite3_common.dart';
import 'package:powersync/sqlite3_open.dart' as sqlite_open;
import 'package:powersync/sqlite_async.dart';

/// Opens the ledger with the SQLite and PowerSync core bundled in the
/// installed workbench app.
///
/// The daemon is hosted by `flutter test`, where PowerSync looks for a bare
/// `libpowersync.dylib` and SQLite resolves to the system library, which
/// refuses extensions.
class InstalledAppSqliteOpenFactory({required super.path})
    extends PowerSyncOpenFactory {
  static const _frameworksPath =
      '/Applications/ethan_workbench.app/Contents/Frameworks';

  @override
  String getLibraryForPlatform({String? path}) =>
      '$_frameworksPath/powersync-sqlite-core.framework/powersync-sqlite-core';

  /// Runs in each connection isolate, so the SQLite override is set there.
  @override
  CommonDatabase open(SqliteOpenOptions options) {
    sqlite_open.open.overrideFor(
      sqlite_open.OperatingSystem.macOS,
      () => DynamicLibrary.open('$_frameworksPath/CSQLite.framework/CSQLite'),
    );
    return super.open(options);
  }
}

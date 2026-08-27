import 'package:drift/drift.dart';

import 'app_database.dart';

part 'settings_store.g.dart';

/// 应用配置(key/value)。
@DataClassName('AppSetting')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 配置存储(key/value)。
@DriftAccessor(tables: [AppSettings])
class SettingsStore extends DatabaseAccessor<AppDatabase>
    with _$SettingsStoreMixin {
  SettingsStore(super.db);

  /// 读取单个 key。
  Future<String?> get(String key) async {
    final row = await (select(appSettings)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// 读取全部(转成 Map)。
  Future<Map<String, String>> getAll() async {
    final rows = await select(appSettings).get();
    return {for (final r in rows) r.key: r.value};
  }

  /// 写入或覆盖单个 key。
  Future<void> set(String key, String value) =>
      into(appSettings).insert(
        AppSettingsCompanion(key: Value(key), value: Value(value)),
        mode: InsertMode.insertOrReplace,
      );

  /// 一次性写入多个 key(走事务)。
  Future<void> setMany(Map<String, String> entries) async {
    await batch((b) {
      for (final e in entries.entries) {
        b.insert(
          appSettings,
          AppSettingsCompanion(key: Value(e.key), value: Value(e.value)),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// 观察所有 key 变化。
  Stream<List<AppSetting>> watchAll() => select(appSettings).watch();
}
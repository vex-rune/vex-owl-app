import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'session_store.dart';
import 'message_store.dart';
import 'memory_store.dart';
import 'settings_store.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Sessions, Messages, MemoryEntries, AppSettings],
  daos: [SessionStore, MessageStore, MemoryStore, SettingsStore],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // v1 -> v2:messages 表新增 type 列,默认 'text'。
          if (from < 2) {
            await m.addColumn(messages, messages.type);
          }
          // v2 -> v3:messages 表新增 turnId 列,用于把"一次助手回复"的多事件聚合为一组。
          if (from < 3) {
            await m.addColumn(messages, messages.turnId);
          }
        },
        beforeOpen: (details) async {
          // 启用外键约束(默认关闭,需要 ON DELETE CASCADE 才有效)
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// 数据库文件路径:`<docs>/.vex_owl/vex_owl.db`。
Future<File> _resolveDbFile() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, '.vex_owl'));
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  return File(p.join(dir.path, 'vex_owl.db'));
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFile = await _resolveDbFile();
    return NativeDatabase.createInBackground(dbFile);
  });
}
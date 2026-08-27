// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'memory_store.dart';

// ignore_for_file: type=lint
mixin _$MemoryStoreMixin on DatabaseAccessor<AppDatabase> {
  $MemoryEntriesTable get memoryEntries => attachedDatabase.memoryEntries;
  MemoryStoreManager get managers => MemoryStoreManager(this);
}

class MemoryStoreManager {
  final _$MemoryStoreMixin _db;
  MemoryStoreManager(this._db);
  $$MemoryEntriesTableTableManager get memoryEntries =>
      $$MemoryEntriesTableTableManager(_db.attachedDatabase, _db.memoryEntries);
}

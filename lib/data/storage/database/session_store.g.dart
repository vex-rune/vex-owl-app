// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_store.dart';

// ignore_for_file: type=lint
mixin _$SessionStoreMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  SessionStoreManager get managers => SessionStoreManager(this);
}

class SessionStoreManager {
  final _$SessionStoreMixin _db;
  SessionStoreManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
}

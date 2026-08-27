// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_store.dart';

// ignore_for_file: type=lint
mixin _$MessageStoreMixin on DatabaseAccessor<AppDatabase> {
  $MessagesTable get messages => attachedDatabase.messages;
  MessageStoreManager get managers => MessageStoreManager(this);
}

class MessageStoreManager {
  final _$MessageStoreMixin _db;
  MessageStoreManager(this._db);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db.attachedDatabase, _db.messages);
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_store.dart';

// ignore_for_file: type=lint
mixin _$SettingsStoreMixin on DatabaseAccessor<AppDatabase> {
  $AppSettingsTable get appSettings => attachedDatabase.appSettings;
  SettingsStoreManager get managers => SettingsStoreManager(this);
}

class SettingsStoreManager {
  final _$SettingsStoreMixin _db;
  SettingsStoreManager(this._db);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db.attachedDatabase, _db.appSettings);
}

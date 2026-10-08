import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../offline/offline_library_cache.dart';

class ManualBookDraftStore {
  static Future<void>? _pending;
  Future<void> _serialize(Future<void> Function() action) {
    final next = (_pending ?? Future<void>.value()).then((_) => action());
    final settled = next.catchError((Object _) {});
    _pending = settled;
    settled.then((_) {
      if (identical(_pending, settled)) _pending = null;
    });
    return next;
  }

  ManualBookDraftStore({OfflineCacheStorage? storage}) : _provided = storage;
  final OfflineCacheStorage? _provided;
  static const prefix = 'readuo.manualBookDraft.v1.';
  late final OfflineCacheStorage preferences =
      _provided ?? PreferencesOfflineCacheStorage(SharedPreferencesAsync());
  Future<Map<String, dynamic>?> read(String uid) async {
    final raw = await preferences.read('$prefix$uid');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['ownerId'] != uid || data['shelfId'] is! String)
        throw const FormatException();
      return data;
    } catch (_) {
      await clear(uid);
      return null;
    }
  }

  Future<void> write(String uid, Map<String, dynamic> data) => _serialize(
    () =>
        preferences.write('$prefix$uid', jsonEncode({...data, 'ownerId': uid})),
  );
  Future<void> clear(String uid) =>
      _serialize(() => preferences.remove('$prefix$uid'));
  Future<void> clearExcept(String? uid) => _serialize(() async {
    for (final key in await preferences.keys()) {
      if (key.startsWith(prefix) && key != '$prefix$uid')
        await preferences.remove(key);
    }
  });
}

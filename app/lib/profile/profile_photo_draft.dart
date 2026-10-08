import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../offline/offline_library_cache.dart';
import 'profile_repository.dart';

abstract interface class ProfilePhotoPicker {
  Future<ProfilePhoto?> pick(ImageSource source);
}

abstract interface class RecoverableProfilePhotoPicker {
  Future<ProfilePhoto?> recover();
}

class DeviceProfilePhotoPicker
    implements ProfilePhotoPicker, RecoverableProfilePhotoPicker {
  const DeviceProfilePhotoPicker();
  Future<ProfilePhoto?> _read(XFile? file) async {
    if (file == null) return null;
    if (await file.length() > 5 * 1024 * 1024)
      throw const ProfileFailure('Choose a photo smaller than 5 MB.');
    final bytes = await file.readAsBytes();
    final photo = ProfilePhoto(
      bytes,
      bytes.isNotEmpty && bytes.first == 137 ? 'image/png' : 'image/jpeg',
    );
    photo.validate();
    return photo;
  }

  @override
  Future<ProfilePhoto?> pick(ImageSource source) async => _read(
    await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    ),
  );
  @override
  Future<ProfilePhoto?> recover() async {
    final result = await ImagePicker().retrieveLostData();
    if (result.exception != null)
      throw const ProfileFailure(
        'Your details were recovered. Please choose the photo again.',
      );
    return _read(result.files?.firstOrNull);
  }
}

class ProfilePhotoDraftStore {
  ProfilePhotoDraftStore({OfflineCacheStorage? storage}) : _provided = storage;
  final OfflineCacheStorage? _provided;
  late final _storage =
      _provided ?? PreferencesOfflineCacheStorage(SharedPreferencesAsync());
  static const prefix = 'readuo.profilePhotoDraft.v1.';
  static Future<void>? _pending;
  Future<void> _serialize(Future<void> Function() work) {
    final result = (_pending ?? Future<void>.value()).then((_) => work());
    final settled = result.catchError((Object _) {});
    _pending = settled;
    settled.then((_) {
      if (identical(_pending, settled)) _pending = null;
    });
    return result;
  }

  Future<Map<String, dynamic>?> read(String uid) async {
    await _pending;
    final raw = await _storage.read('$prefix$uid');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['uid'] != uid || !['setup', 'edit'].contains(data['flow']))
        throw const FormatException();
      return data;
    } catch (_) {
      await clear(uid);
      return null;
    }
  }

  Future<void> write(String uid, Map<String, dynamic> data) => _serialize(
    () => _storage.write('$prefix$uid', jsonEncode({...data, 'uid': uid})),
  );
  Future<void> clear(String uid) =>
      _serialize(() => _storage.remove('$prefix$uid'));
  Future<void> clearExcept(String? uid) => _serialize(() async {
    for (final key in await _storage.keys()) {
      if (key.startsWith(prefix) && key != '$prefix$uid')
        await _storage.remove(key);
    }
  });
}

class ProfilePhotoDraft extends ChangeNotifier {
  ProfilePhotoDraft({
    required this.uid,
    required this.flow,
    required this.name,
    this.picker = const DeviceProfilePhotoPicker(),
    ProfilePhotoDraftStore? store,
    this.isCurrentUser,
  }) : store = store ?? ProfilePhotoDraftStore(),
       persistent = store != null || picker is DeviceProfilePhotoPicker;
  final String uid;
  final String flow;
  final ProfilePhotoPicker picker;
  final ProfilePhotoDraftStore store;
  final bool persistent;
  final bool Function()? isCurrentUser;
  String name;
  ProfilePhoto? photo;
  bool pickerPending = false;
  bool _disposed = false;
  bool get active => !_disposed && (isCurrentUser?.call() ?? true);
  Future<void> persist() async {
    if (!persistent || !active) return;
    await store.write(uid, {
      'flow': flow,
      'name': name,
      'pickerPending': pickerPending,
      if (photo != null) 'photo': base64Encode(photo!.bytes),
      if (photo != null) 'contentType': photo!.contentType,
    });
  }

  Future<void> restore() async {
    if (!persistent) return;
    final saved = await store.read(uid);
    if (!active || saved == null || saved['flow'] != flow) return;
    name = saved['name'] as String? ?? name;
    if (saved['photo'] is String) {
      photo = ProfilePhoto(
        base64Decode(saved['photo'] as String),
        saved['contentType'] as String,
      );
      photo!.validate();
    }
    notifyListeners();
    if (saved['pickerPending'] == true &&
        picker is RecoverableProfilePhotoPicker) {
      final recovered = await (picker as RecoverableProfilePhotoPicker)
          .recover();
      if (!active) return;
      if (recovered != null) {
        recovered.validate();
        photo = recovered;
      }
      pickerPending = false;
      await persist();
      if (active) notifyListeners();
    }
  }

  Future<void> pick(ImageSource source) async {
    if (!active) return;
    pickerPending = true;
    await persist();
    if (!active) return;
    try {
      final selected = await picker.pick(source);
      if (!active) return;
      if (selected != null) {
        selected.validate();
        photo = selected;
      }
    } finally {
      if (active) {
        pickerPending = false;
        await persist();
        if (active) notifyListeners();
      }
    }
  }

  Future<void> clear() async {
    if (persistent) await store.clear(uid);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

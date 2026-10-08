import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'deletion_models.dart';

class SharedPreferencesDeletionCheckpointStore
    implements DeletionCheckpointStore {
  SharedPreferencesDeletionCheckpointStore(this.preferences);
  final SharedPreferencesAsync preferences;
  static const key = 'readuo.pendingAccountDeletion.v1';
  @override
  Future<DeletionCheckpoint?> read() async {
    final value = await preferences.getString(key);
    if (value == null) return null;
    try {
      return DeletionCheckpoint.fromJson(
        jsonDecode(value) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const DeletionFailure(
        'The saved deletion request could not be read. Contact support before trying again.',
      );
    }
  }

  @override
  Future<void> write(DeletionCheckpoint checkpoint) =>
      preferences.setString(key, jsonEncode(checkpoint.toJson()));
  @override
  Future<void> clear() => preferences.remove(key);
}

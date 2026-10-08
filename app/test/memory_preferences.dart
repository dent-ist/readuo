import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void useMemoryPreferences() =>
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences();

final class MemoryPreferences extends SharedPreferencesAsyncPlatform {
  final values = <String, String>{};
  @override
  Future<void> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    values[key] = value;
  }

  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async => values[key];
  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => values.keys
      .where((key) => parameters.filter.allowList?.contains(key) ?? true)
      .toSet();
  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    values.removeWhere(
      (key, _) => parameters.filter.allowList?.contains(key) ?? true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

import 'package:flutter/foundation.dart';

import 'photo_repository.dart';

class CachedCirclePhotoRepository implements CirclePhotoRepository {
  CachedCirclePhotoRepository(
    this.delegate, {
    this.maxBytes = 24 * 1024 * 1024,
  });

  final CirclePhotoRepository delegate;
  final int maxBytes;
  final _bytes = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List?>>{};
  int _size = 0;

  void retainPaths(Set<String> paths) {
    for (final path in _bytes.keys.toList()) {
      if (!paths.contains(path)) _size -= _bytes.remove(path)!.length;
    }
    _pending.removeWhere((path, _) => !paths.contains(path));
  }

  void clear() => retainPaths({});

  @override
  Future<Uint8List?> load(String storagePath) {
    final cached = _bytes.remove(storagePath);
    if (cached != null) {
      _bytes[storagePath] = cached;
      return SynchronousFuture(cached);
    }
    final pending = _pending[storagePath];
    if (pending != null) return pending;
    late final Future<Uint8List?> request;
    request = Future.sync(() => delegate.load(storagePath))
        .then((bytes) {
          if (identical(_pending[storagePath], request) &&
              bytes != null &&
              bytes.length <= maxBytes) {
            _bytes[storagePath] = bytes;
            _size += bytes.length;
            while (_size > maxBytes || _bytes.length > 32) {
              _size -= _bytes.remove(_bytes.keys.first)!.length;
            }
          }
          return bytes;
        })
        .whenComplete(() {
          if (identical(_pending[storagePath], request))
            _pending.remove(storagePath);
        });
    _pending[storagePath] = request;
    return request;
  }

  @override
  Future<String> upload({
    required String ownerId,
    required String postId,
    required Uint8List bytes,
    required String contentType,
  }) => delegate.upload(
    ownerId: ownerId,
    postId: postId,
    bytes: bytes,
    contentType: contentType,
  );

  @override
  Future<void> delete(String storagePath) {
    _size -= _bytes.remove(storagePath)?.length ?? 0;
    _pending.remove(storagePath);
    return delegate.delete(storagePath);
  }
}

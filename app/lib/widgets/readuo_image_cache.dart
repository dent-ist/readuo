import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Shared URL-keyed disk cache. Signed/private storage paths are not handled here.
class ReaduoImageCache {
  static final manager = CacheManager(
    Config(
      'readuo-public-images-v1',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 400,
    ),
  );

  static ImageProvider image(String url) =>
      CachedNetworkImageProvider(url, cacheManager: manager);

  static Future<void> clear() async {
    await manager.emptyCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

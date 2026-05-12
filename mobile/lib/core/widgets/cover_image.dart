import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Shared cover-image widget used everywhere the app paints a bangumi /
/// episode cover. Wraps [CachedNetworkImage] so:
/// - Decoded bitmaps stay in the in-memory image cache between rebuilds,
///   eliminating decode jank as the user scrolls a grid back and forth.
/// - The bytes also land in the platform disk cache, so coming back to
///   the home page after a restart doesn't re-download every poster.
/// - [cacheWidth] downsamples large source images to roughly the on-screen
///   size, keeping the GPU off the slow path for huge JPEGs.
///
/// Null/empty URL falls back to a themed placeholder; load errors fall back
/// to a broken-image icon so the surrounding layout stays stable.
class CoverImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final double? cacheWidth;
  final BorderRadius? borderRadius;

  const CoverImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius;
    if (url == null || url!.isEmpty) {
      return _placeholder(
        context,
        const Icon(Icons.image_not_supported_outlined),
        radius,
      );
    }
    final image = CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      memCacheWidth: cacheWidth?.round(),
      maxWidthDiskCache: cacheWidth?.round(),
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => _placeholderInner(context, null),
      errorWidget: (_, __, ___) =>
          _placeholderInner(context, const Icon(Icons.broken_image_outlined)),
    );
    if (radius == null) return image;
    return ClipRRect(borderRadius: radius, child: image);
  }

  Widget _placeholder(
    BuildContext context,
    Widget? child,
    BorderRadius? radius,
  ) {
    final inner = _placeholderInner(context, child);
    if (radius == null) return inner;
    return ClipRRect(borderRadius: radius, child: inner);
  }

  Widget _placeholderInner(BuildContext context, Widget? child) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: child,
    );
  }
}

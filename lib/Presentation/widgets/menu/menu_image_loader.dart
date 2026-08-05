import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:restaurant_app/Presentation/core/utils/local_image_provider_stub.dart';

List<String> buildImageCandidates(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return const [];
  if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
    return <String>[normalized];
  }
  if (normalized.startsWith('assets/')) return <String>[normalized];
  return const <String>[];
}

class MenuImageLoader extends StatefulWidget {
  final String? primaryImageValue;
  final String? fallbackImageValue;
  final String? localCachePath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final Widget placeholder;
  final bool showPlaceholderWhileLoading;
  final bool enableFadeIn;

  const MenuImageLoader({
    super.key,
    this.primaryImageValue,
    this.fallbackImageValue,
    this.localCachePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth = 720,
    this.filterQuality = FilterQuality.low,
    required this.placeholder,
    this.showPlaceholderWhileLoading = true,
    this.enableFadeIn = true,
  });

  @override
  State<MenuImageLoader> createState() => _MenuImageLoaderState();
}

class _MenuImageLoaderState extends State<MenuImageLoader> {
  List<_ImageCandidate> _candidates = const [];
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _rebuildCandidates();
  }

  @override
  void didUpdateWidget(covariant MenuImageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryImageValue != widget.primaryImageValue ||
        oldWidget.fallbackImageValue != widget.fallbackImageValue ||
        oldWidget.localCachePath != widget.localCachePath ||
        oldWidget.cacheWidth != widget.cacheWidth) {
      _rebuildCandidates();
    }
  }

  void _rebuildCandidates() {
    final candidates = <_ImageCandidate>[];
    _appendLocalCandidate(candidates);
    _appendRawImageCandidates(
      widget.primaryImageValue,
      candidates,
      prefix: 'primary',
    );
    _appendRawImageCandidates(
      widget.fallbackImageValue,
      candidates,
      prefix: 'fallback',
    );

    final dedup = <String, _ImageCandidate>{};
    for (final candidate in candidates) {
      dedup.putIfAbsent(candidate.key, () => candidate);
    }

    _candidates = dedup.values.toList(growable: false);
    _activeIndex = 0;
  }

  void _appendLocalCandidate(List<_ImageCandidate> candidates) {
    final path = widget.localCachePath?.trim();
    if (path == null || path.isEmpty) return;

    final provider = buildLocalImageProvider(path);
    if (provider == null) return;

    candidates.add(
      _ImageCandidate(key: 'local:$path', provider: _resized(provider)),
    );
  }

  void _appendRawImageCandidates(
    String? value,
    List<_ImageCandidate> candidates, {
    required String prefix,
  }) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return;

    if (raw.startsWith('data:image')) {
      final commaIndex = raw.indexOf(',');
      if (commaIndex == -1) return;
      try {
        final bytes = base64Decode(raw.substring(commaIndex + 1));
        candidates.add(
          _ImageCandidate(
            key: '$prefix:data:${raw.hashCode}',
            provider: _resized(MemoryImage(bytes)),
          ),
        );
      } catch (error, stackTrace) {
        debugPrint('ERROR AL DECODIFICAR IMAGEN EN BASE64');
        debugPrint(error.toString());
        debugPrintStack(stackTrace: stackTrace);
      }
      return;
    }

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final candidateUrls = buildImageCandidates(raw);
      final urls = candidateUrls.isNotEmpty ? candidateUrls : [raw];
      for (final candidateUrl in urls) {
        final fixedUrl = candidateUrl;
        if (kIsWeb) {
          candidates.add(
            _ImageCandidate(
              key: '$prefix:web-net:$fixedUrl',
              networkUrl: fixedUrl,
            ),
          );
        } else {
          candidates.add(
            _ImageCandidate(
              key: '$prefix:net:$fixedUrl',
              provider: _resized(NetworkImage(fixedUrl)),
            ),
          );
        }
      }
      return;
    }

    if (raw.startsWith('assets/')) {
      candidates.add(
        _ImageCandidate(
          key: '$prefix:asset:$raw',
          provider: _resized(AssetImage(raw)),
        ),
      );
    }
  }

  ImageProvider<Object> _resized(ImageProvider<Object> provider) {
    return ResizeImage.resizeIfNeeded(widget.cacheWidth, null, provider);
  }

  void _advanceCandidate() {
    if (_activeIndex >= _candidates.length - 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _activeIndex += 1;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty || _activeIndex >= _candidates.length) {
      return widget.placeholder;
    }

    final candidate = _candidates[_activeIndex];

    if (kIsWeb && candidate.networkUrl != null) {
      return _WebIndexedCachedNetworkImage(
        imageUrl: candidate.networkUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        filterQuality: widget.filterQuality,
        placeholder: widget.placeholder,
        cacheWidth: widget.cacheWidth,
        showPlaceholderWhileLoading: widget.showPlaceholderWhileLoading,
        enableFadeIn: widget.enableFadeIn,
        onError: _advanceCandidate,
      );
    }

    final provider = candidate.provider;
    if (provider == null) {
      _advanceCandidate();
      return widget.placeholder;
    }

    return Image(
      image: provider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: widget.filterQuality,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (!widget.enableFadeIn || wasSynchronouslyLoaded) {
          return child;
        }
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      loadingBuilder: widget.showPlaceholderWhileLoading
          ? (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return widget.placeholder;
            }
          : null,
      errorBuilder: (context, error, stackTrace) {
        _advanceCandidate();
        return widget.placeholder;
      },
    );
  }
}

class _ImageCandidate {
  final String key;
  final ImageProvider<Object>? provider;
  final String? networkUrl;

  const _ImageCandidate({required this.key, this.provider, this.networkUrl});
}

class _WebIndexedCachedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final Widget placeholder;
  final bool showPlaceholderWhileLoading;
  final bool enableFadeIn;
  final VoidCallback onError;

  const _WebIndexedCachedNetworkImage({
    required this.imageUrl,
    required this.fit,
    required this.width,
    required this.height,
    required this.cacheWidth,
    required this.filterQuality,
    required this.placeholder,
    required this.showPlaceholderWhileLoading,
    required this.enableFadeIn,
    required this.onError,
  });

  @override
  State<_WebIndexedCachedNetworkImage> createState() =>
      _WebIndexedCachedNetworkImageState();
}

class _WebIndexedCachedNetworkImageState
    extends State<_WebIndexedCachedNetworkImage> {
  bool _didNotifyError = false;

  @override
  void didUpdateWidget(covariant _WebIndexedCachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _didNotifyError = false;
    }
  }

  void _notifyErrorOnce() {
    if (_didNotifyError) return;
    _didNotifyError = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onError();
    });
  }

  bool _needsHtmlImageElement(String url) {
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl.trim();
    if (url.isEmpty) return widget.placeholder;

    return Image.network(
      url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      filterQuality: widget.filterQuality,
      gaplessPlayback: true,
      webHtmlElementStrategy: _needsHtmlImageElement(url)
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.never,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (!widget.enableFadeIn || wasSynchronouslyLoaded) {
          return child;
        }
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      loadingBuilder: widget.showPlaceholderWhileLoading
          ? (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return widget.placeholder;
            }
          : null,
      errorBuilder: (_, __, ___) {
        _notifyErrorOnce();
        return widget.placeholder;
      },
    );
  }
}

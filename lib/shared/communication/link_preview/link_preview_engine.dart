import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final linkPreviewEngineProvider =
    Provider<LinkPreviewEngine>((ref) => LinkPreviewEngine());

class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? domain;
  final String? favicon;

  const LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.domain,
    this.favicon,
  });

  bool get hasContent => title != null || description != null || imageUrl != null;
}

class LinkPreviewEngine {
  static final RegExp urlPattern = RegExp(
    r'https?://[^\s<]+[^<.,:;"' "'" r')\]\s]',
    caseSensitive: false,
  );

  static final RegExp _youtubePattern = RegExp(
    r'(?:youtube\.com/watch\?v=|youtu\.be/)([a-zA-Z0-9_-]+)',
  );

  final Map<String, LinkPreviewData> _cache = {};
  static const int _maxCache = 100;

  List<String> extractUrls(String text) {
    return urlPattern.allMatches(text).map((m) => m.group(0)!).toList();
  }

  Future<LinkPreviewData?> fetchPreview(String url) async {
    if (_cache.containsKey(url)) return _cache[url];

    final youtubeMatch = _youtubePattern.firstMatch(url);
    if (youtubeMatch != null) {
      final videoId = youtubeMatch.group(1)!;
      final preview = LinkPreviewData(
        url: url,
        title: 'YouTube Video',
        imageUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
        siteName: 'YouTube',
        domain: 'youtube.com',
      );
      _addToCache(url, preview);
      return preview;
    }

    // link-preview Edge Function is not deployed — return domain-only fallback.
    final fallback = LinkPreviewData(
      url: url,
      domain: _extractDomain(url),
    );
    _addToCache(url, fallback);
    return fallback;
  }

  Future<LinkPreviewData?> getFirstPreview(String text) async {
    final urls = extractUrls(text);
    if (urls.isEmpty) return null;
    return fetchPreview(urls.first);
  }

  void invalidate(String url) {
    _cache.remove(url);
  }

  void clearCache() {
    _cache.clear();
  }

  void _addToCache(String url, LinkPreviewData data) {
    if (_cache.length >= _maxCache) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = data;
  }

  static String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}

class WebSearchResult {
  final String title;
  final String url;
  final String displayUrl;
  final String snippet;
  final String? faviconUrl;
  final String source;
  final String? publishedDate;

  const WebSearchResult({
    required this.title,
    required this.url,
    required this.displayUrl,
    required this.snippet,
    this.faviconUrl,
    required this.source,
    this.publishedDate,
  });

  factory WebSearchResult.fromJson(Map<String, dynamic> json) {
    return WebSearchResult(
      title: json['title'] as String,
      url: json['url'] as String,
      displayUrl: json['displayUrl'] as String,
      snippet: json['snippet'] as String,
      faviconUrl: json['faviconUrl'] as String?,
      source: json['source'] as String,
      publishedDate: json['publishedDate'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'displayUrl': displayUrl,
      'snippet': snippet,
      'faviconUrl': faviconUrl,
      'source': source,
      'publishedDate': publishedDate,
    };
  }
}

class WebSearchResponse {
  final List<WebSearchResult> results;
  final int page;
  final bool hasMore;
  final int? totalEstimated;
  final String provider;
  final String query;

  const WebSearchResponse({
    required this.results,
    required this.page,
    required this.hasMore,
    this.totalEstimated,
    required this.provider,
    required this.query,
  });

  factory WebSearchResponse.fromJson(Map<String, dynamic> json) {
    return WebSearchResponse(
      results: (json['results'] as List)
          .map((r) => WebSearchResult.fromJson(r as Map<String, dynamic>))
          .toList(),
      page: json['page'] as int,
      hasMore: json['hasMore'] as bool,
      totalEstimated: json['totalEstimated'] as int?,
      provider: json['provider'] as String,
      query: json['query'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'results': results.map((r) => r.toJson()).toList(),
      'page': page,
      'hasMore': hasMore,
      'totalEstimated': totalEstimated,
      'provider': provider,
      'query': query,
    };
  }
}


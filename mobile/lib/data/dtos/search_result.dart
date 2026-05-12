class SearchResult {
  final String title;
  final String? bangumiTitle;
  final String? coverUrl;
  final String? summary;
  final String? link;
  final String torrentUrl;
  final String? magnet;
  final String? size;
  final String? updated;
  final String? episodeLabel;

  const SearchResult({
    required this.title,
    required this.torrentUrl,
    this.bangumiTitle,
    this.coverUrl,
    this.summary,
    this.link,
    this.magnet,
    this.size,
    this.updated,
    this.episodeLabel,
  });

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        title: j['title'] as String,
        torrentUrl: j['torrent_url'] as String? ?? '',
        bangumiTitle: j['bangumi_title'] as String?,
        coverUrl: j['cover_url'] as String?,
        summary: j['summary'] as String?,
        link: j['link'] as String?,
        magnet: j['magnet'] as String?,
        size: j['size'] as String?,
        updated: j['updated'] as String?,
        episodeLabel: j['episode_label'] as String?,
      );
}

class SearchResponse {
  final List<SearchResult> results;
  final String? query;
  final String? matchedQuery;

  const SearchResponse({
    required this.results,
    this.query,
    this.matchedQuery,
  });

  factory SearchResponse.fromJson(Map<String, dynamic> j) => SearchResponse(
        results: ((j['results'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        query: j['query'] as String?,
        matchedQuery: j['matched_query'] as String?,
      );
}

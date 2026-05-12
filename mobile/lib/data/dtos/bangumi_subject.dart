class BangumiSubject {
  final int id;
  final String title;
  final String? name;
  final String? coverUrl;
  final String? summary;
  final double score;
  final int rank;
  final String? airDate;
  final int airWeekday;
  final int doing;
  final int collection;

  const BangumiSubject({
    required this.id,
    required this.title,
    this.name,
    this.coverUrl,
    this.summary,
    this.score = 0,
    this.rank = 0,
    this.airDate,
    this.airWeekday = 0,
    this.doing = 0,
    this.collection = 0,
  });

  factory BangumiSubject.fromJson(Map<String, dynamic> j) => BangumiSubject(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String,
        name: j['name'] as String?,
        coverUrl: j['cover_url'] as String?,
        summary: j['summary'] as String?,
        score: (j['score'] as num?)?.toDouble() ?? 0,
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        airDate: j['air_date'] as String?,
        airWeekday: (j['air_weekday'] as num?)?.toInt() ?? 0,
        doing: (j['doing'] as num?)?.toInt() ?? 0,
        collection: (j['collection'] as num?)?.toInt() ?? 0,
      );
}

class BangumiDiscoverPage {
  final List<BangumiSubject> subjects;
  final int limit;
  final int offset;
  final bool hasMore;

  const BangumiDiscoverPage({
    required this.subjects,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory BangumiDiscoverPage.fromJson(Map<String, dynamic> j) =>
      BangumiDiscoverPage(
        subjects: ((j['subjects'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => BangumiSubject.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        limit: (j['limit'] as num?)?.toInt() ?? 0,
        offset: (j['offset'] as num?)?.toInt() ?? 0,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

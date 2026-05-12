import 'package:animex_mobile/data/dtos/bangumi_subject.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';
import 'package:animex_mobile/data/dtos/search_result.dart';

/// Detail page accepts info from three different sources (Bangumi discover /
/// Mikan schedule item / Mikan search). This is the lowest-common-denominator
/// shape they need to render the hero + drive subscription.
class DetailArgs {
  final String title;
  final String? coverUrl;
  final String? summary;
  final int? subjectId;
  final double score;
  final String? meta; // e.g. air_date, updated, episodeLabel

  const DetailArgs({
    required this.title,
    this.coverUrl,
    this.summary,
    this.subjectId,
    this.score = 0,
    this.meta,
  });

  factory DetailArgs.fromBangumiSubject(BangumiSubject s) => DetailArgs(
        title: s.title,
        coverUrl: s.coverUrl,
        summary: s.summary,
        subjectId: s.id,
        score: s.score,
        meta: s.airDate,
      );

  factory DetailArgs.fromSearch(SearchResult r, {int? subjectId}) => DetailArgs(
        title: r.bangumiTitle ?? r.title,
        coverUrl: r.coverUrl,
        summary: r.summary,
        subjectId: subjectId,
        meta: r.episodeLabel ?? r.updated,
      );

  factory DetailArgs.fromLibraryBangumi(LibraryBangumi b) => DetailArgs(
        title: b.title,
        coverUrl: b.coverUrl,
        summary: b.summary,
      );
}

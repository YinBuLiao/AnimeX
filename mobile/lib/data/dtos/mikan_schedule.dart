class ScheduleItem {
  final int id;
  final String title;
  final String? coverUrl;
  final String? coverFrom;
  final String? pageUrl;
  final String? updated;
  final int weekday;
  final String? dayLabel;

  const ScheduleItem({
    required this.id,
    required this.title,
    this.coverUrl,
    this.coverFrom,
    this.pageUrl,
    this.updated,
    this.weekday = 0,
    this.dayLabel,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String,
        coverUrl: j['cover_url'] as String?,
        coverFrom: j['cover_from'] as String?,
        pageUrl: j['page_url'] as String?,
        updated: j['updated'] as String?,
        weekday: (j['weekday'] as num?)?.toInt() ?? 0,
        dayLabel: j['day_label'] as String?,
      );
}

class ScheduleDay {
  final int weekday;
  final String label;
  final List<ScheduleItem> items;

  const ScheduleDay({
    required this.weekday,
    required this.label,
    required this.items,
  });

  factory ScheduleDay.fromJson(Map<String, dynamic> j) => ScheduleDay(
        weekday: (j['weekday'] as num).toInt(),
        label: j['label'] as String,
        items: ((j['items'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class MikanSchedule {
  final int year;
  final String season;
  final List<ScheduleDay> days;

  const MikanSchedule({
    required this.year,
    required this.season,
    required this.days,
  });

  factory MikanSchedule.fromJson(Map<String, dynamic> j) => MikanSchedule(
        year: (j['year'] as num?)?.toInt() ?? 0,
        season: j['season'] as String? ?? '',
        days: ((j['days'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => ScheduleDay.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

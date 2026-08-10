import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'activity_models.dart';

/// Ported from web useActivityTracking.fetchActivitySummary — reads
/// `user_activity_logs` and aggregates client-side, exactly like the web app.
class ActivityRepository extends BaseRepository {
  const ActivityRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  final SupabaseDataSource _db;

  static const _daysOfWeek = [
    'Yakshanba',
    'Dushanba',
    'Seshanba',
    'Chorshanba',
    'Payshanba',
    'Juma',
    'Shanba'
  ];

  Future<ActivitySummary?> fetchSummary(String userId) async {
    return guard('fetchSummary', () async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart =
          todayStart.subtract(Duration(days: todayStart.weekday % 7));
      final monthStart = DateTime(now.year, now.month, 1);
      final yearStart = DateTime(now.year, 1, 1);

      final logs = await _db
          .table('user_activity_logs')
          .select()
          .eq('user_id', userId)
          .gte('created_at', yearStart.toUtc().toIso8601String())
          .order('created_at', ascending: false);

      final params = _AggregateParams(
        logs: logs as List,
        todayStart: todayStart,
        weekStart: weekStart,
        monthStart: monthStart,
        yearStart: yearStart,
        now: now,
      );

      return compute(_aggregateActivityLogs, params);
    });
  }

  static ActivitySummary? _aggregateActivityLogs(_AggregateParams params) {
    double today = 0, thisWeek = 0, thisMonth = 0, thisYear = 0;
    final hourly = List<double>.filled(24, 0);
    final dailyMap = <String, _MutableDaily>{};
    final dowMinutes = List<double>.filled(7, 0);

    for (final raw in params.logs) {
      final log = raw as Map<String, dynamic>;
      final logDate =
          DateTime.tryParse((log['created_at'] as String?) ?? '')?.toLocal();
      if (logDate == null) continue;
      final seconds = (log['duration_seconds'] as num?)?.toDouble() ?? 0;
      final minutes = seconds / 60.0;
      final dateKey = logDate.toIso8601String().split('T').first;
      final hour = logDate.hour;
      final dow = logDate.weekday % 7; // Sunday=0
      final page = (log['page'] as String?) ?? 'other';

      thisYear += minutes;
      if (!logDate.isBefore(params.monthStart)) thisMonth += minutes;
      if (!logDate.isBefore(params.weekStart)) thisWeek += minutes;
      if (!logDate.isBefore(params.todayStart)) today += minutes;

      hourly[hour] += minutes;
      dowMinutes[dow] += minutes;

      final d = dailyMap.putIfAbsent(dateKey, () => _MutableDaily(dateKey));
      d.total += minutes;
      d.sessions += 1;
      d.pages[page] = (d.pages[page] ?? 0) + minutes;
    }

    int mostActiveHour = 0;
    double maxHour = -1;
    for (var i = 0; i < 24; i++) {
      if (hourly[i] > maxHour) {
        maxHour = hourly[i];
        mostActiveHour = i;
      }
    }

    int mostActiveDayIdx = 0;
    double maxDow = -1;
    for (var i = 0; i < 7; i++) {
      if (dowMinutes[i] > maxDow) {
        maxDow = dowMinutes[i];
        mostActiveDayIdx = i;
      }
    }

    final daysWithActivity = dailyMap.length;
    final averageDaily = daysWithActivity > 0 ? thisYear / daysWithActivity : 0;

    final weeklyPattern = [
      for (var i = 0; i < 7; i++)
        (day: _daysOfWeek[i].substring(0, 3), minutes: dowMinutes[i])
    ];

    final dailyData = dailyMap.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ActivitySummary(
      today: today.round(),
      thisWeek: thisWeek.round(),
      thisMonth: thisMonth.round(),
      thisYear: thisYear.round(),
      averageDaily: averageDaily.round(),
      totalSessions: params.logs.length,
      mostActiveHour: mostActiveHour,
      mostActiveDay: _daysOfWeek[mostActiveDayIdx],
      dailyData: dailyData
          .take(30)
          .map((d) => DailyActivity(
                date: d.date,
                totalMinutes: d.total,
                sessions: d.sessions,
                pages: d.pages,
              ))
          .toList(),
      hourlyDistribution: hourly,
      weeklyPattern: weeklyPattern,
    );
  }

  /// Log a page view (web parity: minimum 5 seconds).
  Future<void> logActivity(
      String userId, String page, int durationSeconds) async {
    return guard('logActivity', () async {
      if (durationSeconds < 5) return;
      try {
        await _db.table('user_activity_logs').insert({
          'user_id': userId,
          'page': page,
          'duration_seconds': durationSeconds,
          'activity_type': 'page_view',
          'content_category': _category(page),
        });
      } catch (_) {}
    });
  }

  String _category(String page) {
    if (page.contains('/home')) return 'feed';
    if (page.contains('/messages')) return 'messaging';
    if (page.contains('/videos')) return 'videos';
    if (page.contains('/discover')) return 'discovery';
    if (page.contains('/profile')) return 'profile';
    if (page.contains('/marketplace')) return 'shopping';
    if (page.contains('/map')) return 'maps';
    if (page.contains('/settings')) return 'settings';
    if (page.contains('/ai')) return 'ai';
    if (page.contains('/create')) return 'creation';
    return 'other';
  }
}

class _MutableDaily {
  _MutableDaily(this.date);
  final String date;
  double total = 0;
  int sessions = 0;
  final Map<String, double> pages = {};
}

class _AggregateParams {
  final List logs;
  final DateTime todayStart;
  final DateTime weekStart;
  final DateTime monthStart;
  final DateTime yearStart;
  final DateTime now;

  _AggregateParams({
    required this.logs,
    required this.todayStart,
    required this.weekStart,
    required this.monthStart,
    required this.yearStart,
    required this.now,
  });
}

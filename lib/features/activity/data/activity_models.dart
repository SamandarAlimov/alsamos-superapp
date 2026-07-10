/// Ported from web useActivityTracking.
class DailyActivity {
  final String date;
  final double totalMinutes;
  final int sessions;
  final Map<String, double> pages;
  const DailyActivity({
    required this.date,
    this.totalMinutes = 0,
    this.sessions = 0,
    this.pages = const {},
  });
}

class ActivitySummary {
  final int today;
  final int thisWeek;
  final int thisMonth;
  final int thisYear;
  final int averageDaily;
  final int totalSessions;
  final int mostActiveHour;
  final String mostActiveDay;
  final List<DailyActivity> dailyData;
  final List<double> hourlyDistribution; // length 24
  final List<({String day, double minutes})> weeklyPattern;

  const ActivitySummary({
    this.today = 0,
    this.thisWeek = 0,
    this.thisMonth = 0,
    this.thisYear = 0,
    this.averageDaily = 0,
    this.totalSessions = 0,
    this.mostActiveHour = 0,
    this.mostActiveDay = '',
    this.dailyData = const [],
    this.hourlyDistribution = const [],
    this.weeklyPattern = const [],
  });
}

/// Ported from web AdminPage + AdminAnalyticsDashboard + AdminOnlineUsersMap.
library;

class VerificationRequest {
  final String id;
  final String userId;
  final String fullName;
  final String? knownAs;
  final String category;
  final String? bioLink;
  final String? idDocumentUrl;
  final String? additionalInfo;
  final String status; // pending | approved | rejected
  final DateTime createdAt;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;

  const VerificationRequest({
    required this.id,
    required this.userId,
    required this.fullName,
    this.knownAs,
    this.category = '',
    this.bioLink,
    this.idDocumentUrl,
    this.additionalInfo,
    this.status = 'pending',
    required this.createdAt,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
  });

  factory VerificationRequest.fromMap(Map<String, dynamic> m) {
    final p = m['profile'] as Map<String, dynamic>?;
    return VerificationRequest(
      id: m['id'] as String,
      userId: (m['user_id'] as String?) ?? '',
      fullName: (m['full_name'] as String?) ?? 'Foydalanuvchi',
      knownAs: m['known_as'] as String?,
      category: (m['category'] as String?) ?? '',
      bioLink: m['bio_link'] as String?,
      idDocumentUrl: m['id_document_url'] as String?,
      additionalInfo: m['additional_info'] as String?,
      status: (m['status'] as String?) ?? 'pending',
      createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '')
              ?.toLocal() ??
          DateTime.now(),
      username: p?['username'] as String?,
      displayName: p?['display_name'] as String?,
      avatarUrl: p?['avatar_url'] as String?,
      isVerified: (p?['is_verified'] as bool?) ?? false,
    );
  }
}

class AdminUser {
  final String id;
  final String userId;
  final String role;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  const AdminUser({
    required this.id,
    required this.userId,
    this.role = 'admin',
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  factory AdminUser.fromMap(Map<String, dynamic> m) {
    final p = m['profile'] as Map<String, dynamic>?;
    return AdminUser(
      id: m['id'] as String,
      userId: (m['user_id'] as String?) ?? '',
      role: (m['role'] as String?) ?? 'admin',
      username: p?['username'] as String?,
      displayName: p?['display_name'] as String?,
      avatarUrl: p?['avatar_url'] as String?,
    );
  }
}

class AdminStats {
  final int users;
  final int posts;
  final int products;
  final int channels;
  const AdminStats({
    this.users = 0,
    this.posts = 0,
    this.products = 0,
    this.channels = 0,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Analytics models — match the RPCs in src/hooks/useAdminAnalytics.ts.
// ─────────────────────────────────────────────────────────────────────────────

class PlatformStats {
  final int totalUsers;
  final int onlineUsers;
  final int newUsers24h;
  final int newUsers7d;
  final int newUsers30d;
  final int verifiedUsers;
  final int totalPosts;
  final int posts24h;
  final int totalMessages;
  final int messages24h;

  const PlatformStats({
    this.totalUsers = 0,
    this.onlineUsers = 0,
    this.newUsers24h = 0,
    this.newUsers7d = 0,
    this.newUsers30d = 0,
    this.verifiedUsers = 0,
    this.totalPosts = 0,
    this.posts24h = 0,
    this.totalMessages = 0,
    this.messages24h = 0,
  });

  factory PlatformStats.fromMap(Map<String, dynamic> m) => PlatformStats(
        totalUsers: (m['total_users'] as num?)?.toInt() ?? 0,
        onlineUsers: (m['online_users'] as num?)?.toInt() ?? 0,
        newUsers24h: (m['new_users_24h'] as num?)?.toInt() ?? 0,
        newUsers7d: (m['new_users_7d'] as num?)?.toInt() ?? 0,
        newUsers30d: (m['new_users_30d'] as num?)?.toInt() ?? 0,
        verifiedUsers: (m['verified_users'] as num?)?.toInt() ?? 0,
        totalPosts: (m['total_posts'] as num?)?.toInt() ?? 0,
        posts24h: (m['posts_24h'] as num?)?.toInt() ?? 0,
        totalMessages: (m['total_messages'] as num?)?.toInt() ?? 0,
        messages24h: (m['messages_24h'] as num?)?.toInt() ?? 0,
      );
}

class HourlyActivity {
  final int hour;
  final int activityCount;
  final int totalDuration;
  const HourlyActivity({
    required this.hour,
    this.activityCount = 0,
    this.totalDuration = 0,
  });
  factory HourlyActivity.fromMap(Map<String, dynamic> m) => HourlyActivity(
        hour: (m['hour'] as num?)?.toInt() ?? 0,
        activityCount: (m['activity_count'] as num?)?.toInt() ?? 0,
        totalDuration: (m['total_duration'] as num?)?.toInt() ?? 0,
      );
}

class PageStat {
  final String page;
  final int visitCount;
  final int uniqueUsers;
  final int totalDuration;
  final int avgDuration;
  const PageStat({
    required this.page,
    this.visitCount = 0,
    this.uniqueUsers = 0,
    this.totalDuration = 0,
    this.avgDuration = 0,
  });
  factory PageStat.fromMap(Map<String, dynamic> m) => PageStat(
        page: (m['page'] as String?) ?? '',
        visitCount: (m['visit_count'] as num?)?.toInt() ?? 0,
        uniqueUsers: (m['unique_users'] as num?)?.toInt() ?? 0,
        totalDuration: (m['total_duration'] as num?)?.toInt() ?? 0,
        avgDuration: (m['avg_duration'] as num?)?.toInt() ?? 0,
      );
}

class CountryStat {
  final String country;
  final int userCount;
  const CountryStat({required this.country, this.userCount = 0});
  factory CountryStat.fromMap(Map<String, dynamic> m) => CountryStat(
        country: (m['country'] as String?) ?? 'Unknown',
        userCount: (m['user_count'] as num?)?.toInt() ?? 0,
      );
}

class AgeStat {
  final String ageGroup;
  final int userCount;
  const AgeStat({required this.ageGroup, this.userCount = 0});
  factory AgeStat.fromMap(Map<String, dynamic> m) => AgeStat(
        ageGroup: (m['age_group'] as String?) ?? 'Unknown',
        userCount: (m['user_count'] as num?)?.toInt() ?? 0,
      );
}

class DauPoint {
  final DateTime date;
  final int dau;
  const DauPoint({required this.date, this.dau = 0});
  factory DauPoint.fromMap(Map<String, dynamic> m) => DauPoint(
        date: DateTime.tryParse((m['date'] as String?) ?? '') ?? DateTime.now(),
        dau: (m['dau'] as num?)?.toInt() ?? 0,
      );
}

class WeeklyPoint {
  final int dayOfWeek; // 0..6 (Sun..Sat)
  final int activityCount;
  final int uniqueUsers;
  const WeeklyPoint({
    required this.dayOfWeek,
    this.activityCount = 0,
    this.uniqueUsers = 0,
  });
  factory WeeklyPoint.fromMap(Map<String, dynamic> m) => WeeklyPoint(
        dayOfWeek: (m['day_of_week'] as num?)?.toInt() ?? 0,
        activityCount: (m['activity_count'] as num?)?.toInt() ?? 0,
        uniqueUsers: (m['unique_users'] as num?)?.toInt() ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Online users map — mirrors `useAdminOnlineUsers`.
// ─────────────────────────────────────────────────────────────────────────────

class OnlineUser {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? country;
  final DateTime? lastSeen;
  const OnlineUser({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.country,
    this.lastSeen,
  });
  factory OnlineUser.fromMap(Map<String, dynamic> m) => OnlineUser(
        id: m['id'] as String,
        username: m['username'] as String?,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        country: m['country'] as String?,
        lastSeen: DateTime.tryParse((m['last_seen'] as String?) ?? ''),
      );
}

class OnlineCountry {
  final String country;
  final int count;
  final double lat;
  final double lng;
  final List<OnlineUser> users;
  const OnlineCountry({
    required this.country,
    required this.count,
    required this.lat,
    required this.lng,
    required this.users,
  });
}

/// Approximate centroids for major countries (mirrors web `COUNTRY_COORDS`).
const Map<String, ({double lat, double lng})> kCountryCoords = {
  'Uzbekistan': (lat: 41.3775, lng: 64.5853),
  'Russia': (lat: 55.7558, lng: 37.6173),
  'Kazakhstan': (lat: 51.1694, lng: 71.4491),
  'USA': (lat: 37.0902, lng: -95.7129),
  'United States': (lat: 37.0902, lng: -95.7129),
  'Germany': (lat: 51.1657, lng: 10.4515),
  'Turkey': (lat: 38.9637, lng: 35.2433),
  'United Kingdom': (lat: 55.3781, lng: -3.4360),
  'UK': (lat: 55.3781, lng: -3.4360),
  'France': (lat: 46.2276, lng: 2.2137),
  'Italy': (lat: 41.8719, lng: 12.5674),
  'Spain': (lat: 40.4637, lng: -3.7492),
  'China': (lat: 35.8617, lng: 104.1954),
  'Japan': (lat: 36.2048, lng: 138.2529),
  'South Korea': (lat: 35.9078, lng: 127.7669),
  'India': (lat: 20.5937, lng: 78.9629),
  'Brazil': (lat: -14.2350, lng: -51.9253),
  'Canada': (lat: 56.1304, lng: -106.3468),
  'Australia': (lat: -25.2744, lng: 133.7751),
  'UAE': (lat: 23.4241, lng: 53.8478),
  'Saudi Arabia': (lat: 23.8859, lng: 45.0792),
  'Egypt': (lat: 26.8206, lng: 30.8025),
  'Poland': (lat: 51.9194, lng: 19.1451),
  'Ukraine': (lat: 48.3794, lng: 31.1656),
  'Tajikistan': (lat: 38.8610, lng: 71.2761),
  'Kyrgyzstan': (lat: 41.2044, lng: 74.7661),
  'Turkmenistan': (lat: 38.9697, lng: 59.5563),
  'Azerbaijan': (lat: 40.1431, lng: 47.5769),
};

class AdminAnalyticsSnapshot {
  final PlatformStats stats;
  final List<HourlyActivity> hourly;
  final List<PageStat> pages;
  final List<CountryStat> countries;
  final List<AgeStat> ages;
  final List<DauPoint> dau;
  final List<WeeklyPoint> weekly;

  const AdminAnalyticsSnapshot({
    this.stats = const PlatformStats(),
    this.hourly = const [],
    this.pages = const [],
    this.countries = const [],
    this.ages = const [],
    this.dau = const [],
    this.weekly = const [],
  });
}

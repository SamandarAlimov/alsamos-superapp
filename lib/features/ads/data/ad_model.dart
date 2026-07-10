/// Full Ad model — mirrors web `useAds.ts` Ad interface 1:1.
class Ad {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final String? mediaUrl;
  final String mediaType; // image | video
  final String? destinationUrl;
  final String? callToAction;
  final String adType; // feed | story | both
  final String status; // pending | active | paused | rejected | completed
  final num budget;
  final num spent;
  final num? dailyBudget;
  final String billingType; // cpm | cpc
  final String? targetGender;
  final int? targetAgeMin;
  final int? targetAgeMax;
  final int impressions;
  final int clicks;
  final int reach;
  final DateTime createdAt;

  const Ad({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.mediaUrl,
    this.mediaType = 'image',
    this.destinationUrl,
    this.callToAction,
    this.adType = 'feed',
    this.status = 'pending',
    this.budget = 0,
    this.spent = 0,
    this.dailyBudget,
    this.billingType = 'cpm',
    this.targetGender,
    this.targetAgeMin,
    this.targetAgeMax,
    this.impressions = 0,
    this.clicks = 0,
    this.reach = 0,
    required this.createdAt,
  });

  factory Ad.fromMap(Map<String, dynamic> m) => Ad(
        id: m['id'] as String,
        userId: (m['user_id'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        description: m['description'] as String?,
        mediaUrl: m['media_url'] as String?,
        mediaType: (m['media_type'] as String?) ?? 'image',
        destinationUrl: m['destination_url'] as String?,
        callToAction: m['call_to_action'] as String?,
        adType: (m['ad_type'] as String?) ?? 'feed',
        status: (m['status'] as String?) ?? 'pending',
        budget: (m['budget'] as num?) ?? 0,
        spent: (m['spent'] as num?) ?? 0,
        dailyBudget: m['daily_budget'] as num?,
        billingType: (m['billing_type'] as String?) ?? 'cpm',
        targetGender: m['target_gender'] as String?,
        targetAgeMin: m['target_age_min'] as int?,
        targetAgeMax: m['target_age_max'] as int?,
        impressions: (m['impressions_count'] as int?) ?? 0,
        clicks: (m['clicks_count'] as int?) ?? 0,
        reach: (m['reach_count'] as int?) ?? 0,
        createdAt:
            DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal() ??
                DateTime.now(),
      );

  double get ctr => impressions == 0 ? 0 : (clicks / impressions) * 100;
}

/// Per-day stats row used by AdStatsDialog.
class AdDailyStats {
  final String date;
  final int impressions;
  final int clicks;
  const AdDailyStats({
    required this.date,
    required this.impressions,
    required this.clicks,
  });
}

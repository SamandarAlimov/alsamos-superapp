/// Ported from web MiniAppsPage `MiniApp` interface.
class MiniApp {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final String url;
  final String? iconUrl;
  final String category;
  final bool isApproved;
  final int usersCount;
  final num rating;
  final DateTime createdAt;
  final String? authorName;
  final String? authorUsername;

  const MiniApp({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    required this.url,
    this.iconUrl,
    this.category = 'other',
    this.isApproved = false,
    this.usersCount = 0,
    this.rating = 0,
    required this.createdAt,
    this.authorName,
    this.authorUsername,
  });

  /// Normalized https URL for opening.
  String get normalizedUrl =>
      (url.startsWith('http://') || url.startsWith('https://')) ? url : 'https://$url';

  factory MiniApp.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'] as Map<String, dynamic>?;
    return MiniApp(
      id: m['id'] as String,
      userId: (m['user_id'] as String?) ?? '',
      name: (m['name'] as String?) ?? 'App',
      description: m['description'] as String?,
      url: (m['url'] as String?) ?? '',
      iconUrl: m['icon_url'] as String?,
      category: (m['category'] as String?) ?? 'other',
      isApproved: (m['is_approved'] as bool?) ?? false,
      usersCount: (m['users_count'] as num?)?.toInt() ?? 0,
      rating: (m['rating'] as num?) ?? 0,
      createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
      authorName: profile?['display_name'] as String?,
      authorUsername: profile?['username'] as String?,
    );
  }
}

class MiniAppCategory {
  final String id;
  final String label;
  const MiniAppCategory(this.id, this.label);
}

const miniAppCategories = <MiniAppCategory>[
  MiniAppCategory('all', 'Barchasi'),
  MiniAppCategory('tools', 'Asboblar'),
  MiniAppCategory('social', 'Ijtimoiy'),
  MiniAppCategory('education', "Ta'lim"),
  MiniAppCategory('lifestyle', 'Turmush tarzi'),
  MiniAppCategory('entertainment', "Ko'ngil ochar"),
  MiniAppCategory('news', 'Yangiliklar'),
  MiniAppCategory('other', 'Boshqa'),
];

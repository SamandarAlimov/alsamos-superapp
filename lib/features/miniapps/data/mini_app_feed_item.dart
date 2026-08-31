// `mini_apps_feed` RPC natijasiga mos model.
// Ustun nomlari web'dagi `src/features/miniapps/types.ts` bilan bir xil kontraktdan keladi.

class MiniAppPublisher {
  const MiniAppPublisher({
    this.id,
    this.handle,
    this.name,
    this.type,
    this.verification = 'unverified',
  });

  final String? id;
  final String? handle;
  final String? name;
  final String? type;
  final String verification;

  bool get isOfficial => verification == 'official';
  bool get isVerified => verification == 'official' || verification == 'domain_verified';
}

class MiniAppFeedItem {
  const MiniAppFeedItem({
    required this.id,
    required this.name,
    required this.category,
    required this.appType,
    required this.displayMode,
    required this.priceModel,
    required this.publisher,
    this.handle,
    this.shortDescription,
    this.description,
    this.url,
    this.iconUrl,
    this.permissions = const <String>[],
    this.screenshots = const <String>[],
    this.privacyUrl,
    this.supportUrl,
    this.deepLink,
    this.isPinned = false,
    this.ownerId,
    this.authorUsername,
    this.authorDisplayName,
    this.authorAvatarUrl,
    this.rating = 0,
    this.ratingCount = 0,
    this.usersCount = 0,
    this.opens30d = 0,
    this.isInstalled = false,
    this.createdAt,
    this.updatedAt,
    this.score = 0,
    this.totalCount = 0,
  });

  final String id;
  final String? handle;
  final String name;
  final String? shortDescription;
  final String? description;
  final String? url;
  final String? iconUrl;
  final String category;
  final String appType;
  final String displayMode;
  final String priceModel;
  final List<String> permissions;
  final List<String> screenshots;
  final String? privacyUrl;
  final String? supportUrl;
  final String? deepLink;
  final bool isPinned;
  final String? ownerId;
  final MiniAppPublisher publisher;
  final String? authorUsername;
  final String? authorDisplayName;
  final String? authorAvatarUrl;
  final double rating;
  final int ratingCount;
  final int usersCount;
  final int opens30d;
  final bool isInstalled;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double score;
  final int totalCount;

  String get publisherLabel =>
      publisher.handle != null && publisher.handle!.isNotEmpty
          ? '@${publisher.handle}'
          : (publisher.name ?? authorDisplayName ?? authorUsername ?? 'Noma\u2019lum');

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _toInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static List<String> _toStringList(Object? value) {
    if (value is List) {
      return value.whereType<Object>().map((item) => item.toString()).toList();
    }
    return const <String>[];
  }

  static DateTime? _toDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  factory MiniAppFeedItem.fromRow(Map<String, dynamic> row) {
    String? text(String key) {
      final value = row[key];
      if (value == null) return null;
      final string = value.toString();
      return string.isEmpty ? null : string;
    }

    return MiniAppFeedItem(
      id: (row['app_id'] ?? row['id'] ?? '').toString(),
      handle: text('handle'),
      name: text('name') ?? 'Nomsiz ilova',
      shortDescription: text('short_description'),
      description: text('description'),
      url: text('url'),
      iconUrl: text('icon_url'),
      category: text('category') ?? 'other',
      appType: text('app_type') ?? 'link',
      displayMode: text('display_mode') ?? 'iframe',
      priceModel: text('price_model') ?? 'free',
      permissions: _toStringList(row['permissions']),
      screenshots: _toStringList(row['screenshots']),
      privacyUrl: text('privacy_url'),
      supportUrl: text('support_url'),
      deepLink: text('deep_link'),
      isPinned: row['is_pinned'] == true,
      ownerId: text('owner_id'),
      publisher: MiniAppPublisher(
        id: text('publisher_id'),
        handle: text('publisher_handle'),
        name: text('publisher_name'),
        type: text('publisher_type'),
        verification: text('publisher_verification') ?? 'unverified',
      ),
      authorUsername: text('author_username'),
      authorDisplayName: text('author_display_name'),
      authorAvatarUrl: text('author_avatar_url'),
      rating: _toDouble(row['rating']),
      ratingCount: _toInt(row['rating_count']),
      usersCount: _toInt(row['users_count']),
      opens30d: _toInt(row['opens_30d']),
      isInstalled: row['is_installed'] == true,
      createdAt: _toDate(row['created_at']),
      updatedAt: _toDate(row['updated_at']),
      score: _toDouble(row['score']),
      totalCount: _toInt(row['total_count']),
    );
  }
}

class MiniAppFeedPage {
  const MiniAppFeedPage({
    required this.items,
    required this.total,
    required this.hasMore,
  });

  final List<MiniAppFeedItem> items;
  final int total;
  final bool hasMore;
}

class MiniAppCategoryItem {
  const MiniAppCategoryItem({
    required this.id,
    required this.label,
    this.sortOrder = 100,
    this.icon,
  });

  final String id;
  final String label;
  final int sortOrder;
  final String? icon;

  factory MiniAppCategoryItem.fromRow(Map<String, dynamic> row, String locale) {
    final labels = (row['labels'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final id = (row['id'] ?? '').toString();
    final label = (labels[locale] ?? labels['uz'] ?? labels['en'] ?? id).toString();
    return MiniAppCategoryItem(
      id: id,
      label: label,
      sortOrder: row['sort_order'] is num ? (row['sort_order'] as num).toInt() : 100,
      icon: row['icon']?.toString(),
    );
  }
}

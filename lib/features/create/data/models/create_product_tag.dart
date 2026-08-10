class CreateProductTag {
  final String id;
  final String title;
  final double price;
  final String currency;
  final String? imageUrl;

  const CreateProductTag({
    required this.id,
    required this.title,
    required this.price,
    required this.currency,
    this.imageUrl,
  });

  factory CreateProductTag.fromMap(Map<String, dynamic> map) {
    return CreateProductTag(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Product',
      price: _toDouble(map['price']),
      currency: map['currency']?.toString() ?? 'USD',
      imageUrl: _firstImageUrl(map['images'] ?? map['product_images']),
    );
  }

  static List<CreateProductTag> fromRows(
    Object? rows, {
    Iterable<String> selectedIds = const <String>[],
    int limit = 20,
  }) {
    if (rows is! List) return const <CreateProductTag>[];

    final excluded = selectedIds.toSet();
    return rows
        .whereType<Map>()
        .map((row) => CreateProductTag.fromMap(
              Map<String, dynamic>.from(row),
            ))
        .where((product) =>
            product.id.isNotEmpty && !excluded.contains(product.id))
        .take(limit.clamp(0, 20))
        .toList(growable: false);
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static String? _firstImageUrl(Object? images) {
    if (images is! List || images.isEmpty) return null;

    final imageRows = images
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    if (imageRows.isEmpty) return null;

    imageRows.sort((a, b) {
      final pa = (a['position'] as num?)?.toInt() ?? 0;
      final pb = (b['position'] as num?)?.toInt() ?? 0;
      return pa.compareTo(pb);
    });

    final url = imageRows.first['url']?.toString();
    return url == null || url.isEmpty ? null : url;
  }
}

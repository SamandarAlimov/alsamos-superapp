class ReactionEntity {
  final String emoji;
  final String? animatedAssetUrl;
  final bool isAnimated;
  final int count;
  final bool hasReacted;
  final List<String> userIds;

  const ReactionEntity({
    required this.emoji,
    this.animatedAssetUrl,
    this.isAnimated = false,
    this.count = 0,
    this.hasReacted = false,
    this.userIds = const [],
  });

  ReactionEntity copyWith({
    int? count,
    bool? hasReacted,
    List<String>? userIds,
  }) =>
      ReactionEntity(
        emoji: emoji,
        animatedAssetUrl: animatedAssetUrl,
        isAnimated: isAnimated,
        count: count ?? this.count,
        hasReacted: hasReacted ?? this.hasReacted,
        userIds: userIds ?? this.userIds,
      );
}

class CreateCollaborator {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isVerified;

  const CreateCollaborator({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isVerified = false,
  });

  factory CreateCollaborator.fromMap(Map<String, dynamic> map) {
    final username = map['username']?.toString() ?? '';
    return CreateCollaborator(
      id: map['id']?.toString() ?? '',
      username: username,
      displayName: map['display_name']?.toString() ??
          (username.isEmpty ? 'User' : username),
      avatarUrl: map['avatar_url']?.toString(),
      isVerified: map['is_verified'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'is_verified': isVerified,
      };

  static List<CreateCollaborator> filterSearchRows(
    Iterable<dynamic> rows, {
    required Iterable<String> selectedIds,
    int limit = 20,
  }) {
    final selected = selectedIds.toSet();
    return rows
        .whereType<Map>()
        .map((row) => CreateCollaborator.fromMap(
              Map<String, dynamic>.from(row),
            ))
        .where((user) => user.id.isNotEmpty && !selected.contains(user.id))
        .take(limit.clamp(0, 20))
        .toList(growable: false);
  }
}

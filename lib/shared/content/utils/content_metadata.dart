String stripPostMetadata(String? content) {
  var value = content?.trim() ?? '';
  if (value.isEmpty) return '';

  const markers = [
    r'\[MUSIC\].*?\[/MUSIC\]',
    r'\[POLL\].*?\[/POLL\]',
    r'\[STORY_META\].*?\[/STORY_META\]',
    r'\[ASPECT:[^\]]+\]',
  ];

  for (final marker in markers) {
    value = value.replaceAll(RegExp(marker, dotAll: true), '').trim();
  }

  return value;
}

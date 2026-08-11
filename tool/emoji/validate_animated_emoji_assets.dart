import 'dart:convert';
import 'dart:io';

const _catalogFiles = [
  'assets/animated_emoji/alsamos/metadata/catalog.json',
  'assets/animated_emoji/licensed/metadata/catalog.json',
];

const _supportedFormats = {'lottie', 'tgs', 'json'};

void main() {
  var hasError = false;
  final seenEmojis = <String>{};
  final seenKeys = <String>{};

  for (final catalogPath in _catalogFiles) {
    final file = File(catalogPath);
    if (!file.existsSync()) {
      stderr.writeln('Missing catalog: $catalogPath');
      hasError = true;
      continue;
    }

    final data = jsonDecode(file.readAsStringSync());
    if (data is! Map<String, dynamic>) {
      stderr.writeln('Catalog must be a JSON object: $catalogPath');
      hasError = true;
      continue;
    }

    final entries = data['entries'];
    if (entries is! List) {
      stderr.writeln('Catalog entries must be a list: $catalogPath');
      hasError = true;
      continue;
    }

    for (final rawEntry in entries) {
      if (rawEntry is! Map<String, dynamic>) {
        stderr.writeln('Catalog entry must be an object: $catalogPath');
        hasError = true;
        continue;
      }

      final emoji = rawEntry['emoji'];
      final key = rawEntry['key'];
      final asset = rawEntry['asset'];
      final format = rawEntry['format'];
      final fps = rawEntry['fps'];
      final loop = rawEntry['loop'];

      if (emoji is! String || emoji.trim().isEmpty) {
        stderr.writeln('Entry has invalid emoji in $catalogPath: $rawEntry');
        hasError = true;
      } else if (!seenEmojis.add('$catalogPath::$emoji')) {
        stderr.writeln('Duplicate emoji in $catalogPath: $emoji');
        hasError = true;
      }

      if (key is! String || key.trim().isEmpty) {
        stderr.writeln('Entry has invalid key in $catalogPath: $rawEntry');
        hasError = true;
      } else if (!seenKeys.add('$catalogPath::$key')) {
        stderr.writeln('Duplicate key in $catalogPath: $key');
        hasError = true;
      }

      if (asset is! String || asset.trim().isEmpty) {
        stderr
            .writeln('Entry has invalid asset path in $catalogPath: $rawEntry');
        hasError = true;
      } else if (!File(asset).existsSync()) {
        stderr.writeln('Missing asset for $key: $asset');
        hasError = true;
      }

      if (format is! String || !_supportedFormats.contains(format)) {
        stderr.writeln('Unsupported format for $key: $format');
        hasError = true;
      }

      if (fps is! int || fps <= 0 || fps > 120) {
        stderr.writeln('Invalid fps for $key: $fps');
        hasError = true;
      }

      if (loop is! bool) {
        stderr.writeln('Invalid loop flag for $key: $loop');
        hasError = true;
      }
    }
  }

  if (hasError) {
    exitCode = 1;
    return;
  }

  stdout.writeln('Animated emoji asset catalogs are valid.');
}

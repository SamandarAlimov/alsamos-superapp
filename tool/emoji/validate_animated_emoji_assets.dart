import 'dart:convert';
import 'dart:io';

import 'package:alsamos_flutter/shared/communication/emoji/animated_emoji_catalog.dart';
import 'package:alsamos_flutter/shared/communication/emoji/bundled_animated_emoji_pack.dart';

const _catalogFiles = [
  'assets/animated_emoji/alsamos/metadata/catalog.json',
  'assets/animated_emoji/licensed/metadata/catalog.json',
];

const _bundledManifestFile = 'assets/animated_emoji/manifest.json';
const _assetRoot = 'assets/animated_emoji';
const _supportedFormats = {'lottie', 'tgs', 'json', 'lottie_json'};
const _allowedExtensions = {'.json', '.tgs', '.webm', '.webp', '.md'};

void main() {
  var hasError = false;
  var catalogEntryCount = 0;
  var duplicateMappingCount = 0;
  var brokenAssetCount = 0;
  var bundledManifestMappings = 0;
  final seenEmojis = <String>{};
  final seenKeys = <String>{};
  final catalogAssetPaths = <String>{};
  final bundledManifestAssetPaths = <String>{};

  final bundledManifest = File(_bundledManifestFile);
  if (!bundledManifest.existsSync()) {
    stderr.writeln('Missing bundled manifest: $_bundledManifestFile');
    hasError = true;
  } else {
    try {
      final data = jsonDecode(bundledManifest.readAsStringSync());
      if (data is! Map<String, dynamic>) {
        stderr.writeln('Bundled manifest must be a JSON object.');
        hasError = true;
      } else {
        final entries = data['entries'];
        if (entries is! List) {
          stderr.writeln('Bundled manifest entries must be a list.');
          hasError = true;
        } else {
          final bundledKeys = <String>{};
          final bundledEmojis = <String>{};
          for (final rawEntry in entries) {
            if (rawEntry is! Map<String, dynamic>) {
              stderr.writeln('Bundled manifest entry must be an object.');
              hasError = true;
              continue;
            }
            final emoji = rawEntry['emoji'];
            final id = rawEntry['id'];
            final asset = rawEntry['asset'];
            final format = rawEntry['format'];
            final checksum = rawEntry['checksumSha256'];
            if (emoji is! String || emoji.isEmpty) {
              stderr.writeln(
                  'Bundled manifest entry has invalid emoji: $rawEntry');
              hasError = true;
            } else if (!bundledEmojis.add(emoji)) {
              stderr.writeln('Duplicate bundled emoji: $emoji');
              duplicateMappingCount++;
              hasError = true;
            }
            if (id is! String || id.isEmpty) {
              stderr
                  .writeln('Bundled manifest entry has invalid id: $rawEntry');
              hasError = true;
            } else if (!bundledKeys.add(id)) {
              stderr.writeln('Duplicate bundled id: $id');
              duplicateMappingCount++;
              hasError = true;
            } else if (!bundledAnimatedEmojiAssetKeys.contains(id)) {
              stderr.writeln(
                  'Bundled manifest id missing from Dart catalog: $id');
              hasError = true;
            }
            if (asset is! String || asset.isEmpty) {
              stderr.writeln(
                  'Bundled manifest entry has invalid asset: $rawEntry');
              hasError = true;
            } else if (!_isSafeAssetPath(asset) || !File(asset).existsSync()) {
              stderr.writeln('Invalid bundled asset path for $id: $asset');
              hasError = true;
            } else {
              bundledManifestAssetPaths.add(_normalizePath(asset));
            }
            if (format is! String || !_supportedFormats.contains(format)) {
              stderr.writeln('Unsupported bundled format for $id: $format');
              hasError = true;
            }
            if (checksum is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
              stderr.writeln('Invalid bundled checksum for $id: $checksum');
              hasError = true;
            }
          }
          bundledManifestMappings = entries.length;
          if (bundledKeys.length != bundledAnimatedEmojiAssetKeys.length) {
            stderr.writeln(
              'Bundled manifest/Dart catalog count mismatch: '
              '${bundledKeys.length} vs ${bundledAnimatedEmojiAssetKeys.length}',
            );
            hasError = true;
          }
        }
      }
    } on Object catch (error) {
      stderr.writeln('Bundled manifest is not valid JSON: $error');
      hasError = true;
    }
  }

  for (final catalogPath in _catalogFiles) {
    final file = File(catalogPath);
    if (!file.existsSync()) {
      stderr.writeln('Missing catalog: $catalogPath');
      hasError = true;
      continue;
    }

    final Object? data;
    try {
      data = jsonDecode(file.readAsStringSync());
    } on Object catch (error) {
      stderr.writeln('Catalog is not valid JSON: $catalogPath ($error)');
      hasError = true;
      continue;
    }

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

      catalogEntryCount++;
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
        duplicateMappingCount++;
        hasError = true;
      }

      if (key is! String || key.trim().isEmpty) {
        stderr.writeln('Entry has invalid key in $catalogPath: $rawEntry');
        hasError = true;
      } else if (!seenKeys.add('$catalogPath::$key')) {
        stderr.writeln('Duplicate key in $catalogPath: $key');
        duplicateMappingCount++;
        hasError = true;
      }

      if (asset is! String || asset.trim().isEmpty) {
        stderr
            .writeln('Entry has invalid asset path in $catalogPath: $rawEntry');
        hasError = true;
      } else if (!File(asset).existsSync()) {
        stderr.writeln('Missing asset for $key: $asset');
        hasError = true;
      } else {
        catalogAssetPaths.add(_normalizePath(asset));
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

  final root = Directory(_assetRoot);
  if (!root.existsSync()) {
    stderr.writeln('Missing animated emoji asset root: $_assetRoot');
    hasError = true;
  }

  final files = root.existsSync()
      ? root
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => _normalizePath(file.path))
          .toList(growable: false)
      : const <String>[];

  final unsupportedFiles = <String>[];
  final animationJsonAssets = <String>[];
  for (final path in files) {
    final extension = _extensionOf(path);
    if (!_allowedExtensions.contains(extension)) {
      unsupportedFiles.add(path);
      hasError = true;
      continue;
    }

    if (extension == '.json' &&
        !path.contains('/metadata/') &&
        path != _bundledManifestFile) {
      animationJsonAssets.add(path);
    }
  }

  for (final path in unsupportedFiles) {
    stderr.writeln('Unsupported file under $_assetRoot: $path');
  }

  for (final path in animationJsonAssets) {
    try {
      jsonDecode(File(path).readAsStringSync());
    } on Object catch (error) {
      brokenAssetCount++;
      stderr.writeln('Broken animated emoji JSON: $path ($error)');
      hasError = true;
    }
  }

  final generatedNotoAssetPaths = animatedEmojiAssetKeys
      .map((key) => 'assets/animated_emoji/noto/$key.json')
      .toSet();
  final reachableAssetPaths = <String>{
    ...bundledManifestAssetPaths,
    ...generatedNotoAssetPaths,
    ...catalogAssetPaths,
  };
  final orphanAssetPaths = animationJsonAssets
      .where((path) => !reachableAssetPaths.contains(path))
      .toList(growable: false);
  if (orphanAssetPaths.isNotEmpty) {
    for (final path in orphanAssetPaths) {
      stderr.writeln('Orphan animated emoji asset: $path');
    }
    hasError = true;
  }

  if (hasError) {
    exitCode = 1;
    return;
  }

  stdout.writeln('Animated emoji asset catalogs are valid.');
  stdout.writeln('Total animation assets: ${animationJsonAssets.length}');
  stdout.writeln('Bundled manifest mappings: $bundledManifestMappings');
  stdout.writeln('Generated Noto mappings: ${animatedEmojiAssetKeys.length}');
  stdout.writeln('Catalog mappings: $catalogEntryCount');
  stdout.writeln('Reachable assets: ${reachableAssetPaths.length}');
  stdout.writeln('Orphan assets: ${orphanAssetPaths.length}');
  stdout.writeln('Broken assets: $brokenAssetCount');
  stdout.writeln('Duplicate mappings: $duplicateMappingCount');
}

String _normalizePath(String path) => path.replaceAll('\\', '/');

bool _isSafeAssetPath(String path) {
  final normalized = _normalizePath(path);
  return normalized.startsWith('assets/animated_emoji/') &&
      !normalized.contains('..') &&
      !normalized.startsWith('/') &&
      !RegExp(r'^[A-Za-z]:').hasMatch(normalized);
}

String _extensionOf(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1) return '';
  return path.substring(dotIndex).toLowerCase();
}

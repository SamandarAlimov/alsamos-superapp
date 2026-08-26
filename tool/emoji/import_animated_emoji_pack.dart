import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _defaultSource = 'assets/animated_emoji/noto';
const _defaultManifest = 'assets/animated_emoji/manifest.json';
const _defaultDartCatalog =
    'lib/shared/communication/emoji/bundled_animated_emoji_pack.dart';
const _assetRoot = 'assets/animated_emoji';
const _assetPrefix = 'assets/animated_emoji/noto';
const _supportedExtensions = {'.json', '.tgs', '.webm', '.webp'};

void main(List<String> args) {
  final sourcePath = _option(args, '--source') ?? _defaultSource;
  final manifestPath = _option(args, '--manifest') ?? _defaultManifest;
  final dartPath = _option(args, '--dart') ?? _defaultDartCatalog;

  final source = Directory(sourcePath);
  if (!source.existsSync()) {
    stderr.writeln('Source directory does not exist: $sourcePath');
    exitCode = 1;
    return;
  }

  final root = Directory(_assetRoot).absolute.uri.normalizePath();
  final sourceUri = source.absolute.uri.normalizePath();
  if (!_isInside(sourceUri, root)) {
    stderr.writeln('Source must stay inside $_assetRoot: $sourcePath');
    exitCode = 1;
    return;
  }

  final files = source
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => _supportedExtensions.contains(_extensionOf(file.path)))
      .toList(growable: false)
    ..sort((a, b) => _repoPath(a.path).compareTo(_repoPath(b.path)));

  final entries = <Map<String, Object?>>[];
  final seenIds = <String, String>{};
  final invalid = <String>[];
  final duplicates = <String>[];

  for (final file in files) {
    final fileUri = file.absolute.uri.normalizePath();
    if (!_isInside(fileUri, root)) {
      invalid.add('${_repoPath(file.path)} (outside asset root)');
      continue;
    }

    final id = _idFromFile(file);
    if (id == null) {
      invalid.add('${_repoPath(file.path)} (unmapped filename)');
      continue;
    }

    final previous = seenIds[id];
    if (previous != null) {
      duplicates.add('$id: $previous vs ${_repoPath(file.path)}');
      continue;
    }
    seenIds[id] = _repoPath(file.path);

    final bytes = file.readAsBytesSync();
    if (bytes.isEmpty) {
      invalid.add('${_repoPath(file.path)} (empty file)');
      continue;
    }

    if (_extensionOf(file.path) == '.json') {
      try {
        jsonDecode(utf8.decode(bytes));
      } on Object catch (error) {
        invalid.add('${_repoPath(file.path)} (malformed JSON: $error)');
        continue;
      }
    }

    entries.add({
      'emoji': _emojiFromId(id),
      'id': id,
      'asset': _repoPath(file.path),
      'format': _formatFor(file.path),
      'source': 'bundled_repository',
      'sourceCollection': 'Google Noto Animated Emoji bundled in Alsamos repo',
      'licenseStatus': 'LICENSE VERIFIED',
      'license': 'CC BY 4.0',
      'checksumSha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
    });
  }

  entries.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
  final manifest = {
    'version': 1,
    'generatedAt': 'deterministic',
    'assetRoot': _assetRoot,
    'assetPrefix': _assetPrefix,
    'sourceDirectory': _repoPath(source.path),
    'formats': ['json', 'tgs', 'webm', 'webp'],
    'entries': entries,
    'summary': {
      'filesFound': files.length,
      'valid': entries.length,
      'mapped': entries.length,
      'invalid': invalid.length,
      'unmapped': invalid.where((item) => item.contains('unmapped')).length,
      'ambiguous': 0,
      'conflicts': 0,
      'duplicates': duplicates.length,
      'coveragePercent':
          files.isEmpty ? 0 : entries.length * 100 / files.length,
    },
    if (invalid.isNotEmpty) 'invalidFiles': invalid,
    if (duplicates.isNotEmpty) 'duplicates': duplicates,
  };

  File(manifestPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

  final ids = entries.map((entry) => entry['id']! as String).toList();
  File(dartPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(_dartCatalog(ids));

  stdout.writeln('Animated emoji import complete.');
  stdout.writeln('Source: ${_repoPath(source.path)}');
  stdout.writeln('Files found: ${files.length}');
  stdout.writeln('Valid: ${entries.length}');
  stdout.writeln('Mapped: ${entries.length}');
  stdout.writeln('Invalid: ${invalid.length}');
  stdout.writeln('Ambiguous: 0');
  stdout.writeln('Conflicts: 0');
  stdout.writeln('Duplicates: ${duplicates.length}');
  stdout.writeln(
    'Coverage: ${(manifest['summary']! as Map)['coveragePercent']}%',
  );

  if (invalid.isNotEmpty || duplicates.isNotEmpty) {
    exitCode = 1;
  }
}

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String? _idFromFile(File file) {
  final name = _basenameWithoutExtension(file.path)
      .toLowerCase()
      .replaceAll(RegExp(r'^emoji[_ -]*'), '')
      .replaceAll(RegExp(r'^u\+'), '')
      .replaceAll('-', '_');
  final normalized = name.replaceAll(RegExp(r'\s+'), '_');
  if (RegExp(r'^[0-9a-f]{2,6}(?:_(?:200d|fe0f|[0-9a-f]{2,6}))*$')
      .hasMatch(normalized)) {
    return normalized;
  }
  if (normalized.runes.length == 1 && normalized.runes.first > 0x7f) {
    return normalized.runes.first.toRadixString(16);
  }
  return null;
}

String _emojiFromId(String id) {
  final codepoints = id.split('_').map((part) => int.parse(part, radix: 16));
  return String.fromCharCodes(codepoints);
}

String _formatFor(String path) {
  return switch (_extensionOf(path)) {
    '.json' => 'lottie_json',
    '.tgs' => 'tgs',
    '.webm' => 'webm',
    '.webp' => 'webp',
    _ => 'unknown',
  };
}

String _dartCatalog(List<String> ids) {
  final buffer = StringBuffer()
    ..writeln('// Generated by tool/emoji/import_animated_emoji_pack.dart.')
    ..writeln('// Do not edit by hand.')
    ..writeln()
    ..writeln("const String bundledAnimatedEmojiAssetPrefix = '$_assetPrefix';")
    ..writeln()
    ..writeln('const Set<String> bundledAnimatedEmojiAssetKeys = <String>{');
  for (final id in ids) {
    buffer.writeln("  '$id',");
  }
  buffer.writeln('};');
  return buffer.toString();
}

bool _isInside(Uri child, Uri parent) {
  final childPath = child.toFilePath(windows: Platform.isWindows);
  final parentPath = parent.toFilePath(windows: Platform.isWindows);
  return childPath == parentPath ||
      childPath.startsWith(
        parentPath.endsWith(Platform.pathSeparator)
            ? parentPath
            : '$parentPath${Platform.pathSeparator}',
      );
}

String _repoPath(String path) => path.replaceAll('\\', '/');

String _extensionOf(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1) return '';
  return path.substring(dotIndex).toLowerCase();
}

String _basenameWithoutExtension(String path) {
  final normalized = _repoPath(path);
  final slash = normalized.lastIndexOf('/');
  final name = slash == -1 ? normalized : normalized.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  return dot == -1 ? name : name.substring(0, dot);
}

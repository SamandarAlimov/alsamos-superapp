import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../messages/presentation/providers/conversations_provider.dart';

/// Data & Storage settings - REAL implementation (relocated messages cache from Appearance)
class DataStorageSettingsPage extends ConsumerStatefulWidget {
  const DataStorageSettingsPage({super.key});
  @override
  ConsumerState<DataStorageSettingsPage> createState() =>
      _DataStorageSettingsPageState();
}

class _DataStorageSettingsPageState
    extends ConsumerState<DataStorageSettingsPage> {
  double _messagesSize = 0.0;
  double _imagesSize = 0.0;
  double _videosSize = 0.0;
  double _voiceSize = 0.0;
  double _filesSize = 0.0;
  bool _loading = true;
  int _imageQuality = 85;
  bool _autoDownloadImages = true;
  bool _autoDownloadVideos = false;
  bool _autoDownloadFiles = false;
  bool _autoDownloadImagesMobile = true;
  bool _autoDownloadVideosMobile = false;
  bool _autoDownloadFilesMobile = false;
  bool _autoDownloadImagesRoaming = false;
  bool _autoDownloadVideosRoaming = false;
  bool _autoDownloadFilesRoaming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateSizes());
  }

  Future<void> _calculateSizes() async {
    setState(() => _loading = true);
    try {
      // Calculate messages cache (SharedPreferences + local DB)
      final prefs = await SharedPreferences.getInstance();
      await _hydrateRemoteStorageSettings(prefs);
      _imageQuality =
          prefs.getInt('messages_image_compression_quality') ?? _imageQuality;
      _autoDownloadImages =
          prefs.getBool('messages_auto_download_images') ?? true;
      _autoDownloadVideos =
          prefs.getBool('messages_auto_download_videos') ?? false;
      _autoDownloadFiles =
          prefs.getBool('messages_auto_download_files') ?? false;
      _autoDownloadImagesMobile =
          prefs.getBool('messages_auto_download_images_mobile') ??
              _autoDownloadImages;
      _autoDownloadVideosMobile =
          prefs.getBool('messages_auto_download_videos_mobile') ?? false;
      _autoDownloadFilesMobile =
          prefs.getBool('messages_auto_download_files_mobile') ?? false;
      _autoDownloadImagesRoaming =
          prefs.getBool('messages_auto_download_images_roaming') ?? false;
      _autoDownloadVideosRoaming =
          prefs.getBool('messages_auto_download_videos_roaming') ?? false;
      _autoDownloadFilesRoaming =
          prefs.getBool('messages_auto_download_files_roaming') ?? false;
      double messagesBytes = 0;
      for (final key in prefs.getKeys()) {
        if (key.startsWith('alsamos_messages_') ||
            key.startsWith('alsamos_conversations_')) {
          final value = prefs.get(key);
          messagesBytes += value.toString().length;
        }
      }

      // Calculate images cache (scan app cache directory)
      double imagesBytes = 0;
      try {
        final tempDir = await getTemporaryDirectory();
        final cacheDir = Directory('${tempDir.path}/libCachedImageData');

        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list(recursive: true)) {
            if (entity is File) {
              try {
                imagesBytes += await entity.length();
              } catch (e) {
                debugPrint('File size error: $e');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Image cache calculation error: $e');
      }

      // Calculate videos and files from app directory
      double videosBytes = 0;
      double voiceBytes = 0;
      double filesBytes = 0;

      try {
        final appDir = await getApplicationDocumentsDirectory();
        final cacheDir = Directory('${appDir.path}/cache');

        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list(recursive: true)) {
            if (entity is File) {
              try {
                final size = await entity.length();
                final path = entity.path.toLowerCase();
                if (path.endsWith('.mp4') ||
                    path.endsWith('.mov') ||
                    path.endsWith('.avi') ||
                    path.endsWith('.mkv')) {
                  videosBytes += size;
                } else if (path.endsWith('.m4a') ||
                    path.endsWith('.mp3') ||
                    path.endsWith('.aac') ||
                    path.endsWith('.wav') ||
                    path.endsWith('.ogg') ||
                    path.endsWith('.opus')) {
                  voiceBytes += size;
                } else if (!path.endsWith('.jpg') &&
                    !path.endsWith('.jpeg') &&
                    !path.endsWith('.png') &&
                    !path.endsWith('.gif') &&
                    !path.endsWith('.webp')) {
                  filesBytes += size;
                }
              } catch (e) {
                debugPrint('File size error: $e');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('App directory error: $e');
      }

      if (!mounted) return;
      setState(() {
        _messagesSize = messagesBytes / (1024 * 1024); // MB
        _imagesSize = imagesBytes / (1024 * 1024);
        _videosSize = videosBytes / (1024 * 1024);
        _voiceSize = voiceBytes / (1024 * 1024);
        _filesSize = filesBytes / (1024 * 1024);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Storage calculation error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearMessagesCache(BuildContext context, WidgetRef ref) async {
    final c = AlsamosColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(AppStrings.of(ref).t('settings.data.messagesCache')),
        content: const Text(
            'Lokal saqlangan suhbat va xabarlar tozalanadi. Serverdagi xabarlar o\'chmaydi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tozalash')),
        ],
      ),
    );
    if (ok != true) return;

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('alsamos_messages_') ||
          key.startsWith('alsamos_conversations_')) {
        await prefs.remove(key);
      }
    }

    if (!context.mounted) return;
    await ref.read(conversationsProvider.notifier).load();
    await _calculateSizes();
    AppToast.success(context, 'Xabarlar keshi tozalandi');
  }

  Future<void> _hydrateRemoteStorageSettings(SharedPreferences prefs) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    try {
      final row =
          await Supabase.instance.client.from('user_settings').select('''
            data_image_quality,
            auto_download_images_wifi,
            auto_download_images_mobile,
            auto_download_images_roaming,
            auto_download_videos_wifi,
            auto_download_videos_mobile,
            auto_download_videos_roaming,
            auto_download_files_wifi,
            auto_download_files_mobile,
            auto_download_files_roaming
          ''').eq('user_id', userId).maybeSingle();
      if (row == null) return;
      final int? quality = (row['data_image_quality'] as num?)?.round();
      if (quality != null) {
        await prefs.setInt('messages_image_compression_quality', quality);
      }
      await _setBoolIfPresent(prefs, row, 'auto_download_images_wifi',
          'messages_auto_download_images_wifi');
      await _setBoolIfPresent(prefs, row, 'auto_download_images_mobile',
          'messages_auto_download_images_mobile');
      await _setBoolIfPresent(prefs, row, 'auto_download_images_roaming',
          'messages_auto_download_images_roaming');
      await _setBoolIfPresent(prefs, row, 'auto_download_videos_wifi',
          'messages_auto_download_videos_wifi');
      await _setBoolIfPresent(prefs, row, 'auto_download_videos_mobile',
          'messages_auto_download_videos_mobile');
      await _setBoolIfPresent(prefs, row, 'auto_download_videos_roaming',
          'messages_auto_download_videos_roaming');
      await _setBoolIfPresent(prefs, row, 'auto_download_files_wifi',
          'messages_auto_download_files_wifi');
      await _setBoolIfPresent(prefs, row, 'auto_download_files_mobile',
          'messages_auto_download_files_mobile');
      await _setBoolIfPresent(prefs, row, 'auto_download_files_roaming',
          'messages_auto_download_files_roaming');
    } catch (e) {
      debugPrint('[DataStorageSettings] remote hydrate ignored: $e');
    }
  }

  Future<void> _setBoolIfPresent(
    SharedPreferences prefs,
    Map<String, dynamic> row,
    String column,
    String key,
  ) async {
    final value = row[column];
    if (value is bool) await prefs.setBool(key, value);
  }

  Future<void> _saveStorageSetting(
    String prefKey,
    Object value,
    String remoteColumn,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(prefKey, value);
    } else if (value is int) {
      await prefs.setInt(prefKey, value);
    }
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('user_settings').upsert({
        'user_id': userId,
        remoteColumn: value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('[DataStorageSettings] remote save ignored: $e');
    }
  }

  Future<void> _clearImagesCache() async {
    final c = AlsamosColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: const Text('Rasmlar keshini tozalash?'),
        content: const Text(
            'Yuklab olingan rasmlar tozalanadi. Ularni qayta yuklab olish mumkin.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tozalash')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      // Clear cached_network_image cache directory
      final tempDir = await getTemporaryDirectory();
      final imageCacheDir = Directory('${tempDir.path}/libCachedImageData');

      if (await imageCacheDir.exists()) {
        await imageCacheDir.delete(recursive: true);
      }

      // Also clear custom cache directories
      final appDir = await getApplicationDocumentsDirectory();
      final customCacheDir = Directory('${appDir.path}/cache');

      if (await customCacheDir.exists()) {
        await for (final entity in customCacheDir.list(recursive: true)) {
          if (entity is File) {
            final path = entity.path.toLowerCase();
            if (path.endsWith('.jpg') ||
                path.endsWith('.jpeg') ||
                path.endsWith('.png') ||
                path.endsWith('.gif') ||
                path.endsWith('.webp')) {
              try {
                await entity.delete();
              } catch (e) {
                debugPrint('Delete error: $e');
              }
            }
          }
        }
      }

      if (!mounted) return;
      await _calculateSizes();
      AppToast.success(context, 'Rasmlar keshi tozalandi');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  Future<void> _clearVideosCache() async {
    final ok = await _showClearConfirmDialog(
        'Videolar keshini tozalash?', 'Yuklab olingan videolar tozalanadi.');
    if (!ok) return;
    await _deleteCacheFilesByExtensions(['.mp4', '.mov', '.avi', '.mkv']);
  }

  Future<void> _clearVoiceCache() async {
    final ok = await _showClearConfirmDialog('Audio/voice keshini tozalash?',
        'Yuklab olingan audio va voice xabarlar tozalanadi.');
    if (!ok) return;
    await _deleteCacheFilesByExtensions(
        ['.m4a', '.mp3', '.aac', '.wav', '.ogg', '.opus']);
  }

  Future<void> _clearFilesCache() async {
    final ok = await _showClearConfirmDialog('Fayllar keshini tozalash?',
        'Yuklab olingan fayllar va hujjatlar tozalanadi.');
    if (!ok) return;
    await _deleteCacheFilesByExtensions([], isOther: true);
  }

  Future<bool> _showClearConfirmDialog(String title, String content) async {
    final c = AlsamosColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tozalash')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteCacheFilesByExtensions(List<String> extensions,
      {bool isOther = false}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final customCacheDir = Directory('${appDir.path}/cache');

      if (await customCacheDir.exists()) {
        await for (final entity in customCacheDir.list(recursive: true)) {
          if (entity is File) {
            final path = entity.path.toLowerCase();
            bool shouldDelete = false;

            if (isOther) {
              if (!path.endsWith('.jpg') &&
                  !path.endsWith('.jpeg') &&
                  !path.endsWith('.png') &&
                  !path.endsWith('.gif') &&
                  !path.endsWith('.webp') &&
                  !path.endsWith('.mp4') &&
                  !path.endsWith('.mov') &&
                  !path.endsWith('.avi') &&
                  !path.endsWith('.mkv') &&
                  !path.endsWith('.m4a') &&
                  !path.endsWith('.mp3') &&
                  !path.endsWith('.aac') &&
                  !path.endsWith('.wav') &&
                  !path.endsWith('.ogg') &&
                  !path.endsWith('.opus')) {
                shouldDelete = true;
              }
            } else {
              for (final ext in extensions) {
                if (path.endsWith(ext)) {
                  shouldDelete = true;
                  break;
                }
              }
            }

            if (shouldDelete) {
              try {
                await entity.delete();
              } catch (e) {
                debugPrint('Delete error: $e');
              }
            }
          }
        }
      }

      if (!mounted) return;
      await _calculateSizes();
      AppToast.success(context, 'Kesh tozalandi');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.card,
          elevation: 0,
          leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(LucideIcons.arrowLeft, size: 22)),
          title: Text(AppStrings.of(ref).t('settings.items.dataStorage'),
              style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontWeight: FontWeight.w600,
                  fontSize: 18)),
        ),
        body: Center(child: CircularProgressIndicator(color: primary)),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(LucideIcons.arrowLeft, size: 22)),
        title: Text(AppStrings.of(ref).t('settings.items.dataStorage'),
            style: const TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: _calculateSizes,
            tooltip: 'Yangilash',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
                AppStrings.of(ref).t('settings.data.storageUsage'), c),
            _SettingsCard(
                c: c,
                child: Column(children: [
                  _StorageItem(
                      c: c,
                      label: 'Xabarlar',
                      size: _formatSize(_messagesSize),
                      icon: LucideIcons.messageSquare,
                      color: Colors.green),
                  Divider(height: 1, color: c.border),
                  _StorageItem(
                      c: c,
                      label: 'Rasmlar',
                      size: _formatSize(_imagesSize),
                      icon: LucideIcons.image,
                      color: Colors.blue),
                  Divider(height: 1, color: c.border),
                  _StorageItem(
                      c: c,
                      label: 'Videolar',
                      size: _formatSize(_videosSize),
                      icon: LucideIcons.video,
                      color: Colors.red),
                  Divider(height: 1, color: c.border),
                  _StorageItem(
                      c: c,
                      label: 'Audio/voice',
                      size: _formatSize(_voiceSize),
                      icon: LucideIcons.mic,
                      color: Colors.purple),
                  Divider(height: 1, color: c.border),
                  _StorageItem(
                      c: c,
                      label: 'Fayllar',
                      size: _formatSize(_filesSize),
                      icon: LucideIcons.file,
                      color: Colors.orange),
                ])),
            const SizedBox(height: 16),
            _sectionHeader('Upload va auto-download', c),
            _SettingsCard(
                c: c,
                child: Column(children: [
                  ListTile(
                    leading: Icon(LucideIcons.slidersHorizontal,
                        color: c.mutedForeground, size: 20),
                    title: const Text('Rasm siqish sifati'),
                    subtitle: Slider(
                      value: _imageQuality.toDouble(),
                      min: 40,
                      max: 100,
                      divisions: 12,
                      label: '$_imageQuality%',
                      onChanged: (value) async {
                        setState(() => _imageQuality = value.round());
                        await _saveStorageSetting(
                            'messages_image_compression_quality',
                            _imageQuality,
                            'data_image_quality');
                      },
                    ),
                    trailing: Text('$_imageQuality%',
                        style: TextStyle(
                            color: c.mutedForeground,
                            fontWeight: FontWeight.w700)),
                  ),
                  Divider(height: 1, color: c.border),
                  SwitchListTile(
                    secondary: Icon(LucideIcons.image,
                        color: c.mutedForeground, size: 20),
                    title: const Text('Rasmlarni avtomatik yuklash'),
                    value: _autoDownloadImages,
                    onChanged: (value) async {
                      setState(() => _autoDownloadImages = value);
                      await _saveStorageSetting('messages_auto_download_images',
                          value, 'auto_download_images_wifi');
                      await _saveStorageSetting(
                          'messages_auto_download_images_wifi',
                          value,
                          'auto_download_images_wifi');
                    },
                  ),
                  _NetworkAutoDownloadRow(
                    c: c,
                    label: 'Rasmlar mobile data',
                    value: _autoDownloadImagesMobile,
                    onChanged: (value) async {
                      setState(() => _autoDownloadImagesMobile = value);
                      await _saveStorageSetting(
                          'messages_auto_download_images_mobile',
                          value,
                          'auto_download_images_mobile');
                    },
                  ),
                  _NetworkAutoDownloadRow(
                    c: c,
                    label: 'Rasmlar roaming',
                    value: _autoDownloadImagesRoaming,
                    onChanged: (value) async {
                      setState(() => _autoDownloadImagesRoaming = value);
                      await _saveStorageSetting(
                          'messages_auto_download_images_roaming',
                          value,
                          'auto_download_images_roaming');
                    },
                  ),
                  SwitchListTile(
                    secondary: Icon(LucideIcons.video,
                        color: c.mutedForeground, size: 20),
                    title: const Text('Videolarni avtomatik yuklash'),
                    value: _autoDownloadVideos,
                    onChanged: (value) async {
                      setState(() => _autoDownloadVideos = value);
                      await _saveStorageSetting('messages_auto_download_videos',
                          value, 'auto_download_videos_wifi');
                      await _saveStorageSetting(
                          'messages_auto_download_videos_wifi',
                          value,
                          'auto_download_videos_wifi');
                    },
                  ),
                  _NetworkAutoDownloadRow(
                    c: c,
                    label: 'Videolar mobile data',
                    value: _autoDownloadVideosMobile,
                    onChanged: (value) async {
                      setState(() => _autoDownloadVideosMobile = value);
                      await _saveStorageSetting(
                          'messages_auto_download_videos_mobile',
                          value,
                          'auto_download_videos_mobile');
                    },
                  ),
                  _NetworkAutoDownloadRow(
                    c: c,
                    label: 'Videolar roaming',
                    value: _autoDownloadVideosRoaming,
                    onChanged: (value) async {
                      setState(() => _autoDownloadVideosRoaming = value);
                      await _saveStorageSetting(
                          'messages_auto_download_videos_roaming',
                          value,
                          'auto_download_videos_roaming');
                    },
                  ),
                  SwitchListTile(
                    secondary: Icon(LucideIcons.file,
                        color: c.mutedForeground, size: 20),
                    title: const Text('Fayllarni avtomatik yuklash'),
                    value: _autoDownloadFiles,
                    onChanged: (value) async {
                      setState(() => _autoDownloadFiles = value);
                      await _saveStorageSetting('messages_auto_download_files',
                          value, 'auto_download_files_wifi');
                      await _saveStorageSetting(
                          'messages_auto_download_files_wifi',
                          value,
                          'auto_download_files_wifi');
                    },
                  ),
                  _NetworkAutoDownloadRow(
                    c: c,
                    label: 'Fayllar mobile data',
                    value: _autoDownloadFilesMobile,
                    onChanged: (value) async {
                      setState(() => _autoDownloadFilesMobile = value);
                      await _saveStorageSetting(
                          'messages_auto_download_files_mobile',
                          value,
                          'auto_download_files_mobile');
                    },
                  ),
                  _NetworkAutoDownloadRow(
                    c: c,
                    label: 'Fayllar roaming',
                    value: _autoDownloadFilesRoaming,
                    onChanged: (value) async {
                      setState(() => _autoDownloadFilesRoaming = value);
                      await _saveStorageSetting(
                          'messages_auto_download_files_roaming',
                          value,
                          'auto_download_files_roaming');
                    },
                  ),
                ])),
            const SizedBox(height: 16),
            _sectionHeader(AppStrings.of(ref).t('settings.data.clearCache'), c),
            _SettingsCard(
                c: c,
                child: Column(children: [
                  ListTile(
                    leading: Icon(LucideIcons.messageSquare,
                        color: c.mutedForeground, size: 20),
                    title: Text(
                        AppStrings.of(ref).t('settings.data.messagesCache')),
                    subtitle: Text(_formatSize(_messagesSize),
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 12)),
                    trailing:
                        Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                    onTap: () => _clearMessagesCache(context, ref),
                  ),
                  Divider(height: 1, color: c.border),
                  ListTile(
                    leading: Icon(LucideIcons.image,
                        color: c.mutedForeground, size: 20),
                    title: const Text('Rasmlar keshi'),
                    subtitle: Text(_formatSize(_imagesSize),
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 12)),
                    trailing:
                        Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                    onTap: _clearImagesCache,
                  ),
                  Divider(height: 1, color: c.border),
                  ListTile(
                    leading: Icon(LucideIcons.video,
                        color: c.mutedForeground, size: 20),
                    title: const Text('Videolar keshi'),
                    subtitle: Text(_formatSize(_videosSize),
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 12)),
                    trailing:
                        Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                    onTap: _clearVideosCache,
                  ),
                  Divider(height: 1, color: c.border),
                  ListTile(
                    leading: Icon(LucideIcons.mic,
                        color: c.mutedForeground, size: 20),
                    title: const Text('Audio/voice keshi'),
                    subtitle: Text(_formatSize(_voiceSize),
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 12)),
                    trailing:
                        Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                    onTap: _clearVoiceCache,
                  ),
                  Divider(height: 1, color: c.border),
                  ListTile(
                    leading: Icon(LucideIcons.fileText,
                        color: c.mutedForeground, size: 20),
                    title: const Text('Fayllar keshi'),
                    subtitle: Text(_formatSize(_filesSize),
                        style:
                            TextStyle(color: c.mutedForeground, fontSize: 12)),
                    trailing:
                        Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                    onTap: _clearFilesCache,
                  ),
                ])),
          ],
        ),
      ),
    );
  }

  String _formatSize(double mb) {
    if (mb < 0.1) return '${(mb * 1024).toStringAsFixed(1)} KB';
    if (mb < 1000) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground)));
}

class _SettingsCard extends StatelessWidget {
  final AlsamosColors c;
  final Widget child;
  const _SettingsCard({required this.c, required this.child});
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border)),
      child: child);
}

class _NetworkAutoDownloadRow extends StatelessWidget {
  final AlsamosColors c;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NetworkAutoDownloadRow({
    required this.c,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 56, right: 12),
        child: SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: TextStyle(color: c.mutedForeground)),
          value: value,
          onChanged: onChanged,
        ),
      );
}

class _StorageItem extends StatelessWidget {
  final AlsamosColors c;
  final String label;
  final String size;
  final IconData icon;
  final Color color;
  const _StorageItem(
      {required this.c,
      required this.label,
      required this.size,
      required this.icon,
      required this.color});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        trailing: Text(size,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.mutedForeground)),
      );
}

import 'package:connectivity_plus/connectivity_plus.dart' show Connectivity, ConnectivityResult;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/services/connectivity_service.dart';

class MediaDownloadPolicy {
  final bool imagesWifi;
  final bool imagesMobile;
  final bool imagesRoaming;
  final bool videosWifi;
  final bool videosMobile;
  final bool videosRoaming;
  final bool filesWifi;
  final bool filesMobile;
  final bool filesRoaming;

  const MediaDownloadPolicy({
    this.imagesWifi = true,
    this.imagesMobile = true,
    this.imagesRoaming = false,
    this.videosWifi = false,
    this.videosMobile = false,
    this.videosRoaming = false,
    this.filesWifi = false,
    this.filesMobile = false,
    this.filesRoaming = false,
  });

  bool allows(String mediaType, List<ConnectivityResult> connectivity) {
    final mobile = connectivity.contains(ConnectivityResult.mobile);
    final wifi = connectivity.contains(ConnectivityResult.wifi) ||
        connectivity.contains(ConnectivityResult.ethernet) ||
        connectivity.contains(ConnectivityResult.vpn);
    if (!mobile && !wifi) return false;
    final image =
        mediaType == 'image' || mediaType == 'gif' || mediaType == 'album';
    final video = mediaType == 'video' || mediaType == 'video_note';
    if (image) return mobile ? imagesMobile : imagesWifi;
    if (video) return mobile ? videosMobile : videosWifi;
    return mobile ? filesMobile : filesWifi;
  }
}

class MediaSettingsService {
  Future<int> imageQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('messages_image_compression_quality') ?? 85;
  }

  Future<MediaDownloadPolicy> downloadPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    return MediaDownloadPolicy(
      imagesWifi: prefs.getBool('messages_auto_download_images_wifi') ??
          prefs.getBool('messages_auto_download_images') ??
          true,
      imagesMobile: prefs.getBool('messages_auto_download_images_mobile') ??
          prefs.getBool('messages_auto_download_images') ??
          true,
      imagesRoaming:
          prefs.getBool('messages_auto_download_images_roaming') ?? false,
      videosWifi: prefs.getBool('messages_auto_download_videos_wifi') ??
          prefs.getBool('messages_auto_download_videos') ??
          false,
      videosMobile:
          prefs.getBool('messages_auto_download_videos_mobile') ?? false,
      videosRoaming:
          prefs.getBool('messages_auto_download_videos_roaming') ?? false,
      filesWifi: prefs.getBool('messages_auto_download_files_wifi') ??
          prefs.getBool('messages_auto_download_files') ??
          false,
      filesMobile:
          prefs.getBool('messages_auto_download_files_mobile') ?? false,
      filesRoaming:
          prefs.getBool('messages_auto_download_files_roaming') ?? false,
    );
  }

  Future<bool> shouldAutoDownload(String mediaType) async {
    if (!ConnectivityService.instance.isOnlineNow) return false;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      return (await downloadPolicy()).allows(mediaType, connectivity);
    } catch (_) {
      return true;
    }
  }
}

final mediaSettingsServiceProvider = Provider((_) => MediaSettingsService());

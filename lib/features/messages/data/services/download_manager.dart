import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String? savedPath;
  final double progress;
  final DownloadStatus status;
  final String? error;
  final CancelToken? cancelToken;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    this.savedPath,
    this.progress = 0,
    this.status = DownloadStatus.queued,
    this.error,
    this.cancelToken,
  });

  DownloadTask copyWith({
    String? savedPath,
    double? progress,
    DownloadStatus? status,
    String? error,
    CancelToken? cancelToken,
  }) =>
      DownloadTask(
        id: id,
        url: url,
        fileName: fileName,
        savedPath: savedPath ?? this.savedPath,
        progress: progress ?? this.progress,
        status: status ?? this.status,
        error: error,
        cancelToken: cancelToken ?? this.cancelToken,
      );
}

final downloadManagerProvider =
    StateNotifierProvider<DownloadManager, List<DownloadTask>>(
  (ref) => DownloadManager(),
);

class DownloadManager extends StateNotifier<List<DownloadTask>> {
  DownloadManager() : super(const []);

  final Dio _dio = Dio();

  Future<void> download(
    String url, {
    String? fileName,
    bool openAfterDownload = true,
  }) async {
    if (kIsWeb) {
      await OpenFilex.open(url);
      return;
    }
    final name = _safeFileName(fileName ?? Uri.parse(url).pathSegments.last);
    final id = '$url|$name';
    final token = CancelToken();
    final existing = state.indexWhere((task) => task.id == id);
    final initial = DownloadTask(
      id: id,
      url: url,
      fileName: name,
      status: DownloadStatus.downloading,
      cancelToken: token,
    );
    if (existing >= 0) {
      final next = [...state];
      next[existing] = initial;
      state = next;
    } else {
      state = [...state, initial];
    }
    try {
      final dir = await _downloadsDirectory();
      final path = await _uniquePath(dir.path, name);
      await _dio.download(
        url,
        path,
        cancelToken: token,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          _replace(
              id,
              (task) => task.copyWith(
                    progress: received / total,
                    status: DownloadStatus.downloading,
                  ));
        },
      );
      _replace(
          id,
          (task) => task.copyWith(
                savedPath: path,
                progress: 1,
                status: DownloadStatus.completed,
              ));
      if (openAfterDownload) await OpenFilex.open(path);
    } on DioException catch (e) {
      _replace(
        id,
        (task) => task.copyWith(
          status: e.type == DioExceptionType.cancel
              ? DownloadStatus.cancelled
              : DownloadStatus.failed,
          error: e.message,
        ),
      );
    } catch (e) {
      _replace(
          id,
          (task) => task.copyWith(
              status: DownloadStatus.failed, error: e.toString()));
    }
  }

  void cancel(String id) {
    final task = state.where((item) => item.id == id).firstOrNull;
    task?.cancelToken?.cancel('cancelled');
  }

  Future<void> retry(String id) async {
    final task = state.where((item) => item.id == id).firstOrNull;
    if (task == null) return;
    await download(task.url, fileName: task.fileName);
  }

  void _replace(String id, DownloadTask Function(DownloadTask task) update) {
    state = [
      for (final task in state) task.id == id ? update(task) : task,
    ];
  }

  Future<Directory> _downloadsDirectory() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir;
    }
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<String> _uniquePath(String dir, String name) async {
    var path = p.join(dir, name);
    if (!await File(path).exists()) return path;
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var i = 1;
    do {
      path = p.join(dir, '$base ($i)$ext');
      i++;
    } while (await File(path).exists());
    return path;
  }

  String _safeFileName(String raw) {
    final decoded = Uri.decodeComponent(raw.trim().isEmpty ? 'download' : raw);
    return decoded.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  }
}

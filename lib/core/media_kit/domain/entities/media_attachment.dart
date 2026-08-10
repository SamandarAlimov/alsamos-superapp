enum MediaAttachmentType { image, video, audio, voiceNote, videoNote, gif, sticker, file, location, contact, poll }

class MediaAttachment {
  final MediaAttachmentType type;
  final String? localPath;
  final String? remoteUrl;
  final String? thumbnailUrl;
  final String? mimeType;
  final String? fileName;
  final int? durationMs;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final List<double>? waveform;
  final Map<String, dynamic> metadata;

  const MediaAttachment({
    required this.type,
    this.localPath,
    this.remoteUrl,
    this.thumbnailUrl,
    this.mimeType,
    this.fileName,
    this.durationMs,
    this.sizeBytes,
    this.width,
    this.height,
    this.waveform,
    this.metadata = const {},
  });

  bool get isLocal => localPath != null;
  bool get isRemote => remoteUrl != null;

  MediaAttachment copyWith({
    MediaAttachmentType? type,
    String? localPath,
    String? remoteUrl,
    String? thumbnailUrl,
    String? mimeType,
    String? fileName,
    int? durationMs,
    int? sizeBytes,
    int? width,
    int? height,
    List<double>? waveform,
    Map<String, dynamic>? metadata,
  }) {
    return MediaAttachment(
      type: type ?? this.type,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      mimeType: mimeType ?? this.mimeType,
      fileName: fileName ?? this.fileName,
      durationMs: durationMs ?? this.durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      waveform: waveform ?? this.waveform,
      metadata: metadata ?? this.metadata,
    );
  }
}
